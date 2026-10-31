// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_create_repo/gg_create_repo.dart';
import 'package:gg_create_repo/src/github.dart';
import 'package:gg_process/gg_process.dart';
import 'package:test/test.dart';

/// Answers `gh` calls from a script: gh talks to GitHub over the network.
class _FakeGh extends GgProcessWrapper {
  _FakeGh(this.answer, {this.executable = 'gh'});

  final ProcessResult Function(List<String> args) answer;
  final String executable;
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
    expect(executable, this.executable);
    calls.add(arguments);
    return answer(arguments);
  }
}

ProcessResult _ok([String out = '']) => ProcessResult(0, 0, out, '');
ProcessResult _fail([String err = 'failed']) => ProcessResult(0, 1, '', err);

/// What `gh api --include` prints: status line, headers, blank line, body.
ProcessResult _http(int status, [String body = '']) => ProcessResult(
  0,
  status == 200 ? 0 : 1,
  'HTTP/2.0 $status Reason\r\nContent-Type: x\r\n\r\n$body',
  'gh: (HTTP $status)',
);

/// The api path of [args], `null` for calls that are no `gh api --include`.
String? _path(List<String> args) =>
    args.length > 2 && args[0] == 'api' && args[1] == '--include'
    ? args[2]
    : null;

void main() {
  group('GitHub', () {
    test('example() uses a process wrapper', () {
      expect(GitHub.example(), isA<GitHub>());
      expect(GitHub.example(processWrapper: _FakeGh((_) => _ok())), isNotNull);
    });

    // #########################################################################
    group('authProblem()', () {
      test('is null when gh is installed and logged in', () async {
        final gh = GitHub(processWrapper: _FakeGh((_) => _ok()));
        expect(await gh.authProblem(), isNull);
      });

      test('names a missing gh', () async {
        final failing = GitHub(processWrapper: _FakeGh((_) => _fail()));
        expect(await failing.authProblem(), contains('not installed'));

        final missing = GitHub(
          processWrapper: _FakeGh(
            (_) => throw const ProcessException('gh', []),
          ),
        );
        expect(await missing.authProblem(), contains('not installed'));
      });

      test('names a missing login', () async {
        final gh = GitHub(
          processWrapper: _FakeGh(
            (args) => args.first == 'auth' ? _fail() : _ok('gh 2.0'),
          ),
        );
        expect(await gh.authProblem(), contains('gh auth login'));
      });
    });

    // #########################################################################
    group('sshProblem()', () {
      final spec = RepoSpec.example(org: 'o', name: 'r');
      late List<List<String>> calls;

      Future<String?> problem(ProcessResult Function(List<String>) answer) {
        final ssh = _FakeGh(answer, executable: 'ssh');
        calls = ssh.calls;
        return GitHub(processWrapper: ssh).sshProblem(spec);
      }

      test('is null when GitHub greets the key, asking nothing', () async {
        const hi = "Hi me! You've successfully authenticated, but no shell.";
        expect(await problem((_) => _fail(hi)), isNull);
        expect(calls.single, containsAll(['BatchMode=yes', 'git@github.com']));
      });

      test('names unknown and changed host keys, refused keys, missing ssh '
          'and other failures', () async {
        expect(
          await problem((_) => _fail('Host key verification failed.')),
          contains('SSH does not know github.com'),
        );
        expect(
          await problem(
            (_) => _fail(
              'WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!\n'
              'Host key verification failed.',
            ),
          ),
          contains('ssh-keygen -R github.com'),
        );
        expect(
          await problem((_) => _fail('Permission denied (publickey).')),
          contains('ssh-keygen -t ed25519'),
        );
        expect(
          await problem((_) => throw const ProcessException('ssh', [])),
          contains('ssh is not installed'),
        );
        expect(
          await problem((_) => _fail('Connection timed out')),
          contains('failed: Connection timed out'),
        );
      });
    });

    // #########################################################################
    group('login() and orgs()', () {
      test('read the user and their organizations', () async {
        final gh = GitHub(
          processWrapper: _FakeGh(
            (args) => args[1] == 'user' ? _ok('me\n') : _ok(' a \n\nb\n'),
          ),
        );
        expect(await gh.login(), 'me');
        expect(await gh.orgs(), ['a', 'b']);
      });

      test('are empty when gh fails', () async {
        final gh = GitHub(processWrapper: _FakeGh((_) => _fail()));
        expect(await gh.login(), isNull);
        expect(await gh.orgs(), isEmpty);
      });
    });

    // #########################################################################
    group('creationProblem()', () {
      GitHub gh(Map<String, ProcessResult> byPath, {String login = 'me'}) =>
          GitHub(
            processWrapper: _FakeGh((args) {
              final path = _path(args);
              if (path == null) return _ok('$login\n');
              return byPath[path] ?? _http(500);
            }),
          );

      test('names an owner GitHub does not know', () async {
        final problem = await gh({'users/ghost': _http(404)})
            .creationProblem('ghost');
        expect(problem, contains('knows no organization or user'));
      });

      test('allows the own user, in any case', () async {
        final users = {'users/Me': _http(200, 'User')};
        expect(await gh(users).creationProblem('Me'), isNull);
      });

      test('refuses another user', () async {
        final users = {'users/other': _http(200, 'User')};
        expect(
          await gh(users).creationProblem('other'),
          contains('only be created for yourself (me)'),
        );
      });

      test('allows a user when the login is unknown', () async {
        final unknown = GitHub(
          processWrapper: _FakeGh(
            (args) => _path(args) == null ? _fail() : _http(200, 'User'),
          ),
        );
        expect(await unknown.creationProblem('other'), isNull);
      });

      test('refuses an organization the user is no member of', () async {
        expect(
          await gh({
            'users/org': _http(200, 'Organization'),
            'user/memberships/orgs/org': _http(404),
          }).creationProblem('org'),
          contains('no member'),
        );
      });

      test('refuses a pending invitation', () async {
        expect(
          await gh({
            'users/org': _http(200, 'Organization'),
            'user/memberships/orgs/org': _http(200, 'pending\tmember'),
          }).creationProblem('org'),
          contains('not accepted'),
        );
      });

      test('allows admins', () async {
        expect(
          await gh({
            'users/org': _http(200, 'Organization'),
            'user/memberships/orgs/org': _http(200, 'active\tadmin'),
          }).creationProblem('org'),
          isNull,
        );
      });

      test('asks the org whether members may create repositories', () async {
        final member = {
          'users/org': _http(200, 'Organization'),
          'user/memberships/orgs/org': _http(200, 'active\tmember'),
        };
        expect(
          await gh({...member, 'orgs/org': _http(200, 'false')})
              .creationProblem('org'),
          contains('may not create'),
        );
        expect(
          await gh({...member, 'orgs/org': _http(200, 'true')})
              .creationProblem('org'),
          isNull,
        );
      });
    });

    // #########################################################################
    group('remote()', () {
      GitHub gh(ProcessResult repo, [ProcessResult? commits]) => GitHub(
        processWrapper: _FakeGh(
          (args) =>
              _path(args)!.endsWith('/commits?per_page=1') ? commits! : repo,
        ),
      );

      test('is missing when GitHub answers 404', () async {
        final remote = await gh(_http(404)).remote('o/r');
        expect(remote.state, RemoteState.missing);
        expect(remote.isPrivate, isNull);
      });

      test('throws when GitHub cannot be asked', () async {
        final noAnswer = ProcessResult(0, 1, '', 'no network');
        await expectLater(
          gh(noAnswer).remote('o/r'),
          throwsA(
            isA<Exception>().having(
              (e) => '$e',
              'message',
              contains('no network'),
            ),
          ),
        );
      });

      test('throws when gh is missing', () async {
        final missing = GitHub(
          processWrapper: _FakeGh(
            (_) => throw const ProcessException('gh', [], 'not found'),
          ),
        );
        await expectLater(
          missing.remote('o/r'),
          throwsA(
            isA<Exception>().having((e) => '$e', 'message', contains('found')),
          ),
        );
      });

      test('is empty when the commits answer 409', () async {
        final remote = await gh(_http(200, 'true'), _http(409)).remote('o/r');
        expect(remote.state, RemoteState.empty);
        expect(remote.isPrivate, isTrue);
      });

      test('is filled when there are commits', () async {
        final remote = await gh(
          _http(200, 'false'),
          _http(200, '[{}]'),
        ).remote('o/r');
        expect(remote.state, RemoteState.filled);
        expect(remote.isPrivate, isFalse);
      });

      test('throws when the commits cannot be asked for', () async {
        await expectLater(
          gh(_http(200, 'false'), _http(500)).remote('o/r'),
          throwsA(isA<Exception>()),
        );
      });
    });

    // #########################################################################
    group('create()', () {
      test('creates a public or private repository', () async {
        final fake = _FakeGh((_) => _ok());
        final gh = GitHub(processWrapper: fake);

        await gh.create(RepoSpec.example(org: 'o', name: 'r'));
        await gh.create(RepoSpec.example(org: 'o', name: 'r', isPrivate: true));

        expect(fake.calls.first.take(4), ['repo', 'create', 'o/r', '--public']);
        expect(fake.calls.last[3], '--private');
        expect(fake.calls.first, contains('--description'));
      });

      test('throws with the output of gh', () async {
        final gh = GitHub(processWrapper: _FakeGh((_) => _fail('taken')));
        await expectLater(
          gh.create(RepoSpec.example()),
          throwsA(
            isA<Exception>().having((e) => '$e', 'message', contains('taken')),
          ),
        );
      });
    });

    // #########################################################################
    group('cloneUrl()', () {
      test('is the ssh url of the spec', () async {
        final spec = RepoSpec.example();
        expect(await const GitHub().cloneUrl(spec), spec.cloneUrl);
      });
    });

    // #########################################################################
    group('applyMergeSettings()', () {
      test('patches the repository', () async {
        final fake = _FakeGh((_) => _ok());
        await GitHub(processWrapper: fake).applyMergeSettings('o/r');
        expect(fake.calls.single.take(4), [
          'api',
          '--method',
          'PATCH',
          'repos/o/r',
        ]);
        expect(fake.calls.single, contains('allow_auto_merge=true'));
      });

      test('throws when gh fails', () async {
        final gh = GitHub(processWrapper: _FakeGh((_) => _fail('403')));
        await expectLater(
          gh.applyMergeSettings('o/r'),
          throwsA(isA<Exception>()),
        );
      });
    });

    // #########################################################################
    test('RemoteRepo.example() is a missing repository', () {
      expect(RemoteRepo.example().state, RemoteState.missing);
      final empty = RemoteRepo.example(
        state: RemoteState.empty,
        isPrivate: true,
      );
      expect(empty.isPrivate, isTrue);
    });

    test('has a mock', () {
      expect(MockGitHub(), isA<GitHub>());
    });
  });
}
