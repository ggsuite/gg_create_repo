// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_process/gg_process.dart';
import 'package:mocktail/mocktail.dart';

/// Runs the command line tools gg_create_repo needs. Only the batch files
/// `pnpm`, `npm`, `npx` and `flutter` go through a shell on Windows.
class Tools {
  /// Constructor
  const Tools({
    GgProcessWrapper processWrapper = const GgProcessWrapper(),
    this._isWindows,
  }) : _process = processWrapper;

  /// The real tools; tests pass a fake process wrapper.
  factory Tools.example({GgProcessWrapper? processWrapper, bool? isWindows}) =>
      Tools(
        processWrapper: processWrapper ?? const GgProcessWrapper(),
        isWindows: isWindows,
      );

  // ...........................................................................
  /// Runs [executable] in [directory] and throws with its output on failure.
  Future<String> run(
    String executable,
    List<String> args, {
    required Directory directory,
  }) async {
    final result = await _start(executable, args, directory.path);
    if (result.exitCode != 0) {
      throw Exception(
        '»$executable ${args.join(' ')}« failed in ${directory.path}:\n'
                '${result.stderr}${result.stdout}'
            .trim(),
      );
    }
    return result.stdout.toString();
  }

  // ...........................................................................
  /// The first line [executable] prints for `--version`, `null` if missing.
  Future<String?> version(String executable) async {
    try {
      final result = await _start(executable, ['--version'], null);
      if (result.exitCode != 0) return null;
      final out = '${result.stdout}${result.stderr}'.trim();
      return out.split('\n').first.trim();
    } on ProcessException {
      return null;
    }
  }

  // ...........................................................................
  /// The major version of [executable], e.g. 22 for `v22.14.0`.
  Future<int?> majorVersion(String executable) async {
    final match = RegExp(r'(\d+)\.\d+')
        .firstMatch(await version(executable) ?? '');
    return match == null ? null : int.parse(match.group(1)!);
  }

  // ...........................................................................
  /// The Dart SDK version of `dart`, or of the Dart bundled with
  /// `flutter` when [flutter] is set; `null` if unknown.
  Future<String?> dartSdkVersion({bool flutter = false}) async {
    try {
      if (flutter) {
        final result = await _start('flutter', [
          '--version',
          '--machine',
        ], null);
        final out = result.stdout.toString();
        final json = jsonDecode(out.substring(out.indexOf('{')));
        return (json as Map<String, dynamic>)['dartSdkVersion'] as String?;
      }
      final match = RegExp(r'version: (\S+)')
          .firstMatch(await version('dart') ?? '');
      return match?.group(1);
    } on Object {
      return null;
    }
  }

  // ...........................................................................
  /// The value of `git config [key]`, empty when it is not set.
  Future<String> gitConfig(String key) async {
    try {
      final result = await _start('git', ['config', key], null);
      return result.exitCode == 0 ? result.stdout.toString().trim() : '';
    } on ProcessException {
      return '';
    }
  }

  // ######################
  // Private
  // ######################

  final GgProcessWrapper _process;
  final bool? _isWindows;

  static const _batchFiles = {'pnpm', 'npm', 'npx', 'flutter'};

  /// git may never wait for a password: nobody would see the question.
  static const _gitEnvironment = {'GIT_TERMINAL_PROMPT': '0'};

  // ...........................................................................
  Future<ProcessResult> _start(
    String executable,
    List<String> args,
    String? workingDirectory,
  ) => _process.run(
    executable,
    args,
    workingDirectory: workingDirectory,
    environment: executable == 'git' ? _gitEnvironment : null,
    runInShell:
        (_isWindows ?? Platform.isWindows) && _batchFiles.contains(executable),
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
}

/// Mock for [Tools].
class MockTools extends Mock implements Tools {}
