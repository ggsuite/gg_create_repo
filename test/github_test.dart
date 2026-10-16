// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_create_repo/gg_create_repo.dart';
import 'package:gg_process/gg_process.dart';
import 'package:test/test.dart';

/// Answers `gh` calls from a script: gh talks to GitHub over the network.
class _FakeGh extends GgProcessWrapper {
  _FakeGh(this.answer);

  final ProcessResult Function(List<String> args) answer;
  final calls = <List<String>>[];

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
  }) async {
    expect(executable, 'gh');
    calls.add(arguments);
    return answer(arguments);
  }
}

ProcessResult _ok([String out = '']) => ProcessResult(0, 0, out, '');
ProcessResult _fail([String err = 'failed']) => ProcessResult(0, 1, '', err);

void main() {
  group('GitHub', () {
    group('authProblem()', () {
      test('is null when gh is installed and logged in', () async {
        final gh = GitHub(processWrapper: _FakeGh((_) => _ok()));
        expect(await gh.authProblem(), isNull);
      });

      test('says when gh is not installed', () async {
        final failing = GitHub(processWrapper: _FakeGh((_) => _fail()));
        expect(await failing.authProblem(), contains('not installed'));

        final missing = GitHub(
          processWrapper: _FakeGh(
            (_) => throw const ProcessException('gh', []),
          ),
        );
        expect(await missing.authProblem(), contains('not installed'));
      });

      test('says when gh is not logged in', () async {
        final gh = GitHub(
          processWrapper: _FakeGh(
            (args) => args.first == 'auth' ? _fail() : _ok('gh 2.0'),
          ),
        );
        expect(await gh.authProblem(), contains('gh auth login'));
      });
    });

    test('login() is the trimmed login, null when unknown', () async {
      expect(
        await GitHub(processWrapper: _FakeGh((_) => _ok('me\n'))).login(),
        'me',
      );
      expect(
        await GitHub(processWrapper: _FakeGh((_) => _fail())).login(),
        isNull,
      );
    });

    test('orgs() lists the organizations, empty on failure', () async {
      final fake = _FakeGh((_) => _ok(' a \n\nb\n'));
      expect(await GitHub(processWrapper: fake).orgs(), ['a', 'b']);
      expect(fake.calls.single, ['api', 'user/orgs', '--jq', '.[].login']);
      expect(
        await GitHub(processWrapper: _FakeGh((_) => _fail())).orgs(),
        isEmpty,
      );
    });

    test('ownerType() is the type, null for unknown owners', () async {
      expect(
        await GitHub(processWrapper: _FakeGh((_) => _ok('Organization\n')))
            .ownerType('ggsuite'),
        'Organization',
      );
      expect(
        await GitHub(processWrapper: _FakeGh((_) => _fail())).ownerType('x'),
        isNull,
      );
    });

    group('state()', () {
      test('is missing when GitHub answers 404', () async {
        final gh = GitHub(
          processWrapper: _FakeGh((_) => _fail('gh: Not Found (HTTP 404)')),
        );
        expect(await gh.state('o/r'), RemoteState.missing);
      });

      test('throws when GitHub cannot be asked', () async {
        final gh = GitHub(processWrapper: _FakeGh((_) => _fail('no network')));
        await expectLater(gh.state('o/r'), throwsA(isA<Exception>()));
      });

      test('is empty when GitHub answers 409 for the commits', () async {
        final gh = GitHub(
          processWrapper: _FakeGh(
            (args) => args[1].endsWith('/commits?per_page=1')
                ? _fail('gh: Git Repository is empty. (HTTP 409)')
                : _ok('o/r'),
          ),
        );
        expect(await gh.state('o/r'), RemoteState.empty);
      });

      test('throws when the commits cannot be asked for', () async {
        final gh = GitHub(
          processWrapper: _FakeGh(
            (args) => args[1].endsWith('/commits?per_page=1')
                ? _fail('timeout')
                : _ok('o/r'),
          ),
        );
        await expectLater(gh.state('o/r'), throwsA(isA<Exception>()));
      });

      test('is filled when it has commits', () async {
        final gh = GitHub(processWrapper: _FakeGh((_) => _ok('[{}]')));
        expect(await gh.state('o/r'), RemoteState.filled);
      });
    });

    group('create()', () {
      test('creates a public or private repository', () async {
        final fake = _FakeGh((_) => _ok());
        final gh = GitHub(processWrapper: fake);

        await gh.create(RepoSpec.example(org: 'o', name: 'r'));
        await gh.create(RepoSpec.example(org: 'o', name: 'r', isPrivate: true));

        expect(fake.calls.first.take(4), ['repo', 'create', 'o/r', '--public']);
        expect(fake.calls.last[3], '--private');
        expect(fake.calls.last[4], '--description');
      });

      test('throws with the output of gh', () async {
        final gh = GitHub(processWrapper: _FakeGh((_) => _fail('no rights')));
        await expectLater(
          gh.create(RepoSpec.example()),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              allOf(contains('Could not create'), contains('no rights')),
            ),
          ),
        );
      });
    });

    test('cloneUrl() follows the configured git protocol', () async {
      expect(
        await GitHub(processWrapper: _FakeGh((_) => _ok('ssh\n')))
            .cloneUrl('o/r'),
        'git@github.com:o/r.git',
      );
      expect(
        await GitHub(processWrapper: _FakeGh((_) => _ok('https\n')))
            .cloneUrl('o/r'),
        'https://github.com/o/r.git',
      );
    });

    test('applyMergeSettings() patches squash and auto-merge', () async {
      final fake = _FakeGh((_) => _ok());
      await GitHub(processWrapper: fake).applyMergeSettings('o/r');
      expect(fake.calls.single, containsAll(['repos/o/r', 'PATCH']));
      expect(fake.calls.single, contains('allow_auto_merge=true'));

      final failing = GitHub(processWrapper: _FakeGh((_) => _fail()));
      await expectLater(failing.applyMergeSettings('o/r'), throwsException);
    });

    test('has a default process wrapper and a mock', () {
      expect(const GitHub(), isA<GitHub>());
      expect(MockGitHub(), isA<GitHub>());
    });
  });
}
