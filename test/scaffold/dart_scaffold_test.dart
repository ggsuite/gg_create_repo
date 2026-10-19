// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_create_repo/gg_create_repo.dart';
import 'package:gg_create_repo/src/scaffold/dart_scaffold.dart';
import 'package:gg_create_repo/src/tools.dart';
import 'package:gg_process/gg_process.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

// .............................................................................
/// Records the processes instead of starting them; `pub add` needs pub.dev.
class _RecordingProcess extends GgProcessWrapper {
  final calls = <String>[];

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
    calls.add([executable, ...arguments].join(' '));
    return ProcessResult(0, 0, '', '');
  }
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('dart_scaffold_'));
  tearDown(() => dir.deleteSync(recursive: true));

  final scaffold = DartScaffold.example(
    sdkVersion: '3.13.2 (stable) on "windows"',
  );
  const tricky =
      r'''Creates: "quoted" and 'single' things, costs $5 \ more, '''
      'and is long enough for pub.dev.';

  String read(String path) => File(p.join(dir.path, path)).readAsStringSync();
  bool exists(String path) => File(p.join(dir.path, path)).existsSync();

  group('DartScaffold', () {
    group('write()', () {
      test('writes a plain package with an example', () {
        scaffold.write(dir, RepoSpec.example(description: tricky));

        final pubspec = loadYaml(read('pubspec.yaml')) as YamlMap;
        expect(pubspec['name'], 'gg_example_repo');
        expect(pubspec['description'], tricky);
        expect(pubspec['version'], '0.0.1');
        expect(
          pubspec['repository'],
          'https://github.com/ggsuite/gg_example_repo.git',
        );
        expect((pubspec['environment'] as YamlMap)['sdk'], '>=3.13.0 <4.0.0');
        expect(pubspec.containsKey('publish_to'), isFalse);
        expect(pubspec.containsKey('executables'), isFalse);
        expect(pubspec.containsKey('dependencies'), isFalse);

        expect(
          read('analysis_options.yaml'),
          startsWith('include: package:lints/recommended.yaml\n'),
        );
        expect(read('.gitignore'), contains('!.gg/gg.json'));
        expect(
          read('lib/gg_example_repo.dart'),
          contains("export 'src/gg_example_repo.dart';"),
        );
        expect(read('lib/gg_example_repo.dart'), isNot(contains('my_command')));
        expect(
          read('lib/src/gg_example_repo.dart'),
          contains('class GgExampleRepo {'),
        );
        expect(
          read('test/gg_example_repo_test.dart'),
          contains("import 'package:test/test.dart' show expect, group, test;"),
        );
        final example = read('example/gg_example_repo_example.dart');
        expect(example, startsWith('#!/usr/bin/env dart\n// @license'));
        expect(example, contains('print(const GgExampleRepo().greet('));
        expect(example, isNot(contains('avoid_print')));
        expect(exists('bin/gg_example_repo.dart'), isFalse);
      });

      test('writes no example when not wanted', () {
        scaffold.write(dir, RepoSpec.example(example: false));
        expect(Directory(p.join(dir.path, 'example')).existsSync(), isFalse);
      });

      test('marks a private package as not published', () {
        scaffold.write(dir, RepoSpec.example(isPrivate: true));
        final pubspec = loadYaml(read('pubspec.yaml')) as YamlMap;
        expect(pubspec['publish_to'], 'none');
      });

      test('writes a command line interface', () {
        scaffold.write(dir, RepoSpec.example(cli: true));

        final pubspec = loadYaml(read('pubspec.yaml')) as YamlMap;
        expect(
          (pubspec['executables'] as YamlMap).containsKey('gg_example_repo'),
          isTrue,
        );
        expect(
          read('lib/gg_example_repo.dart'),
          contains("export 'src/commands/my_command.dart';"),
        );
        expect(
          read('lib/src/gg_example_repo.dart'),
          contains('class GgExampleRepo extends Command<dynamic>'),
        );
        expect(
          read('lib/src/commands/my_command.dart'),
          contains("final name = 'my-command';"),
        );
        expect(
          read('bin/gg_example_repo.dart'),
          contains('command: GgExampleRepo(ggLog: ggLog)'),
        );
        expect(
          read('test/gg_example_repo_test.dart'),
          contains("['my-command']"),
        );
        expect(exists('test/commands/my_command_test.dart'), isTrue);
        expect(
          read('test/bin/gg_example_repo_test.dart'),
          contains("import '../../bin/gg_example_repo.dart';"),
        );
        expect(
          read('example/gg_example_repo_example.dart'),
          contains("CommandRunner<dynamic>('gg_example_repo', 'Example')"),
        );
      });

      test('writes a Flutter package', () {
        scaffold.write(dir, RepoSpec.example(flutter: true));

        final pubspec = loadYaml(read('pubspec.yaml')) as YamlMap;
        expect((pubspec['dependencies'] as YamlMap)['flutter'], {
          'sdk': 'flutter',
        });
        expect((pubspec['dev_dependencies'] as YamlMap)['flutter_test'], {
          'sdk': 'flutter',
        });
        expect(
          read('analysis_options.yaml'),
          startsWith('include: package:flutter_lints/flutter.yaml\n'),
        );
        expect(
          read('test/gg_example_repo_test.dart'),
          contains("import 'package:flutter_test/flutter_test.dart' show"),
        );
        expect(
          read('example/gg_example_repo_example.dart'),
          contains('// ignore: avoid_print'),
        );
      });
    });

    group('pubspec()', () {
      test('takes the SDK that runs gg_create_repo by default', () {
        final version = Platform.version.split(' ').first;
        final parts = version.split('.');
        final pre = version.contains('-') ? '-0' : '';
        expect(
          const DartScaffold().pubspec(RepoSpec.example()),
          contains('sdk: ">=${parts[0]}.${parts[1]}.0$pre <4.0.0"'),
        );
      });

      test('keeps a pre-release SDK inside the constraint', () {
        final pubspec = DartScaffold.example(sdkVersion: '3.14.0-12.0.dev')
            .pubspec(RepoSpec.example());
        expect(pubspec, contains('sdk: ">=3.14.0-0 <4.0.0"'));
      });

      test('example() builds with Dart 3.9.2', () {
        expect(
          DartScaffold.example().pubspec(RepoSpec.example()),
          contains('sdk: ">=3.9.0 <4.0.0"'),
        );
      });
    });

    group('docComment()', () {
      test('wraps a long text at 80 characters and escapes tags', () {
        const text =
            'Parses a Map<String, int> into a List<T> of entries, keeps '
            'their order and reports every duplicate key it meets on the '
            'way with the line it was found in.';
        expect(text.length, greaterThan(150));

        final comment = DartScaffold.docComment(text);
        final lines = comment.trimRight().split('\n');

        expect(lines.length, greaterThan(1));
        for (final line in lines) {
          expect(line, startsWith('/// '));
          expect(line.length, lessThanOrEqualTo(80));
        }
        expect(comment, contains('Map&lt;String, int&gt;'));
        expect(comment, contains('List&lt;T&gt;'));
        expect(comment, isNot(contains('<')));
        expect(comment, endsWith('\n'));
      });

      test('keeps a short text on one line', () {
        expect(
          DartScaffold.docComment('  Short   text. '),
          '/// Short text.\n',
        );
      });
    });

    group('write() with long values', () {
      test('keeps every generated comment and string within 80', () {
        final long = 'A ${'very ' * 30}long description with <T>.';
        final name = 'gg_${'long_name_' * 4}x';
        scaffold.write(
          dir,
          RepoSpec.example(name: name, description: long, cli: true),
        );

        final library = read('lib/$name.dart');
        for (final line in library.split('\n')) {
          expect(line.length, lessThanOrEqualTo(80));
        }
        expect(library, contains('&lt;T&gt;'));
        expect(
          read('lib/src/$name.dart'),
          contains("'The command line interface of '\n      '$name.';"),
        );
      });
    });

    group('install()', () {
      test('adds the dependencies of a plain package and formats', () async {
        final process = _RecordingProcess();
        await scaffold.install(
          dir,
          RepoSpec.example(),
          Tools(processWrapper: process),
        );
        expect(process.calls, [
          'dart pub add dev:lints dev:test',
          'dart format .',
        ]);
      });

      test('adds the CLI packages', () async {
        final process = _RecordingProcess();
        await scaffold.install(
          dir,
          RepoSpec.example(cli: true),
          Tools(processWrapper: process),
        );
        expect(
          process.calls.first,
          'dart pub add args gg_args gg_log dev:lints dev:test',
        );
      });

      test('uses flutter pub for a Flutter package', () async {
        final process = _RecordingProcess();
        await scaffold.install(
          dir,
          RepoSpec.example(flutter: true),
          Tools(processWrapper: process),
        );
        expect(process.calls, [
          'flutter pub add dev:flutter_lints',
          'dart format .',
        ]);
      });
    });
  });
}
