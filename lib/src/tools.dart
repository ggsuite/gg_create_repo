// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_process/gg_process.dart';
import 'package:mocktail/mocktail.dart';

/// Runs the command line tools gg_create_repo needs.
///
/// On Windows `pnpm`, `npm` and `flutter` are batch files, which only a
/// shell can start; everything else runs without one, so no argument is
/// ever reinterpreted by `cmd.exe`.
class Tools {
  /// Constructor
  const Tools({
    GgProcessWrapper processWrapper = const GgProcessWrapper(),
    this._isWindows,
  }) : _process = processWrapper;

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

  // ...........................................................................
  Future<ProcessResult> _start(
    String executable,
    List<String> args,
    String? workingDirectory,
  ) => _process.run(
    executable,
    args,
    workingDirectory: workingDirectory,
    runInShell:
        (_isWindows ?? Platform.isWindows) && _batchFiles.contains(executable),
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
}

/// Mock for [Tools].
class MockTools extends Mock implements Tools {}
