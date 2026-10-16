// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_create_repo/gg_create_repo.dart';
import 'package:gg_process/gg_process.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Records how processes are started; only for the shell decision and
/// failures that real tools cannot be made to produce on demand.
class _FakeProcess extends GgProcessWrapper {
  _FakeProcess(this.answer);

  final ProcessResult Function(String executable) answer;
  final shells = <String, bool>{};

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
    shells[executable] = runInShell;
    return answer(executable);
  }
}

void main() {
  late Directory d;

  setUp(() => d = Directory.systemTemp.createTempSync('tools_'));
  tearDown(() => d.deleteSync(recursive: true));

  group('Tools', () {
    group('run()', () {
      test('runs git for real and returns its output', () async {
        const tools = Tools();
        await tools.run('git', ['init', '--initial-branch=main'], directory: d);
        expect(Directory(p.join(d.path, '.git')).existsSync(), isTrue);

        final branch = await tools.run('git', [
          'symbolic-ref',
          '--short',
          'HEAD',
        ], directory: d);
        expect(branch.trim(), 'main');
      });

      test('throws with command, folder and output on failure', () async {
        const tools = Tools();
        await expectLater(
          tools.run('git', ['no-such-command'], directory: d),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              allOf(contains('»git no-such-command«'), contains(d.path)),
            ),
          ),
        );
      });

      test('starts batch files through the shell on Windows only', () async {
        final fake = _FakeProcess((_) => ProcessResult(0, 0, '', ''));
        final windows = Tools(processWrapper: fake, isWindows: true);
        await windows.run('pnpm', ['install'], directory: d);
        await windows.run('git', ['status'], directory: d);
        expect(fake.shells, {'pnpm': true, 'git': false});

        final linux = Tools(processWrapper: fake, isWindows: false);
        await linux.run('flutter', ['pub', 'get'], directory: d);
        expect(fake.shells['flutter'], isFalse);
      });
    });

    group('version()', () {
      test('is the first line of a real tool', () async {
        expect(await const Tools().version('git'), startsWith('git version'));
      });

      test('reads the version from stderr as well', () async {
        final fake = _FakeProcess((_) => ProcessResult(0, 0, '', 'v1\nv2'));
        expect(await Tools(processWrapper: fake).version('x'), 'v1');
      });

      test('is null when the tool fails or is missing', () async {
        final failing = _FakeProcess((_) => ProcessResult(0, 1, '', ''));
        expect(await Tools(processWrapper: failing).version('x'), isNull);
        expect(
          await const Tools().version('no_such_tool_for_gg_create_repo'),
          isNull,
        );
      });
    });

    group('gitConfig()', () {
      test('is the value of a key', () async {
        final fake = _FakeProcess((_) => ProcessResult(0, 0, ' Ada \n', ''));
        expect(await Tools(processWrapper: fake).gitConfig('user.name'), 'Ada');
      });

      test('is empty when the key is not set', () async {
        expect(
          await const Tools().gitConfig('gg-create-repo.no-such-key'),
          isEmpty,
        );
      });

      test('is empty when git is missing', () async {
        final missing = _FakeProcess(
          (_) => throw const ProcessException('git', []),
        );
        expect(
          await Tools(processWrapper: missing).gitConfig('user.name'),
          isEmpty,
        );
      });
    });

    test('has a mock', () {
      expect(MockTools(), isA<Tools>());
    });
  });
}
