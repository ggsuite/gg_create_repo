// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

@Tags(['integration'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';

import 'package:gg_create_repo/gg_create_repo.dart';
import 'package:gg_create_repo/src/scaffold/common_files.dart';
import 'package:gg_create_repo/src/scaffold/dart_scaffold.dart';
import 'package:gg_create_repo/src/validation.dart';
import 'package:gg_one_commit/gg_one_commit.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/git_identity.dart';

/// Writes the real Dart skeleton of [spec] and runs gg's commit checks on
/// it: analyze, format and the tests with 100 % coverage. The packages
/// come from the pub cache, so the test needs no network.
Future<void> expectGreen(RepoSpec spec) async {
  final root = Directory.systemTemp.createTempSync('dart_skeleton_');
  addTearDown(() => root.deleteSync(recursive: true));
  final dir = Directory(p.join(root.path, spec.name))..createSync();

  DartScaffold(sdkVersion: Platform.version).write(dir, spec);
  const CommonFiles().write(dir, spec);
  final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
  pubspec.writeAsStringSync(
    '${pubspec.readAsStringSync()}\n'
    'dependencies:\n'
    '${spec.cli ? '  args: any\n  gg_args: any\n  gg_log: any\n' : ''}'
    '\ndev_dependencies:\n  lints: any\n  test: any\n',
  );

  Future<void> run(String exe, List<String> args) async {
    final result = await Process.run(
      exe,
      args,
      workingDirectory: dir.path,
      environment: gitIdentity,
      runInShell: Platform.isWindows,
    );
    expect(result.exitCode, 0, reason: '$exe $args\n${result.stderr}');
  }

  await run('dart', ['pub', 'get', '--offline']);
  expect(
    resolvedPackages(dir).difference({spec.name}),
    everyElement(isIn(Validation.skeletonDependencies)),
    reason: 'A package of this name could not depend on the skeleton.',
  );
  await run('dart', ['format', '.']);
  await run('git', ['init', '--initial-branch=main']);
  await run('git', ['add', '--all']);
  await run('git', ['commit', '-m', 'Initial version']);

  final messages = <String>[];
  await CanCommit(ggLog: messages.add)
      .exec(directory: dir, ggLog: messages.add);
}

/// The packages pub resolved for the package in [dir].
Set<String> resolvedPackages(Directory dir) {
  final config = File(p.join(dir.path, '.dart_tool', 'package_config.json'));
  final packages = (jsonDecode(config.readAsStringSync()) as Map)['packages'];
  return {for (final package in packages as List) '${package['name']}'};
}

void main() {
  const description =
      'A package whose description is as long as pub.dev allows, mentions '
      'generic types like Map<String, int> and List<T>, and still has to '
      'pass the gg checks.';

  group('The Dart skeleton passes the gg commit checks', () {
    // The longest name and description the validation lets through.
    final longestName = 'gg_${'a_long_name_' * 5}'.padRight(64, 'x');

    test('for a library with the longest name and description', () async {
      expect(description.length, lessThanOrEqualTo(180));
      expect(longestName.length, 64);
      await expectGreen(
        RepoSpec.example(name: longestName, description: description),
      );
    });

    test('for a command line package without an example', () async {
      await expectGreen(
        RepoSpec.example(
          name: longestName,
          description: description,
          cli: true,
          example: false,
        ),
      );
    });
  });
}
