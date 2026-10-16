// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import '../repo_spec.dart';
import '../tools.dart';
import 'common_files.dart';
import 'scaffold.dart';

/// The skeleton of a Dart or Flutter package in the style of the gg suite.
class DartScaffold extends Scaffold {
  /// Constructor
  const DartScaffold({this._sdkVersion});

  // ...........................................................................
  @override
  void write(Directory directory, RepoSpec spec) {
    void file(String path, String content) =>
        CommonFiles.writeFile(directory, path, content);

    final n = spec.name;
    file('pubspec.yaml', pubspec(spec));
    file('analysis_options.yaml', _analysisOptions(spec));
    file('.gitignore', _gitignore);
    file('lib/$n.dart', _library(spec));
    if (spec.cli) {
      file('lib/src/$n.dart', _cliRoot(spec));
      file('lib/src/commands/my_command.dart', _myCommand(spec));
      file('bin/$n.dart', _bin(spec));
      file('test/$n$_t', _cliRootTest(spec));
      file('test/commands/my_command$_t', _myCommandTest(spec));
      file('test/bin/$n$_t', _binTest(spec));
    } else {
      file('lib/src/$n.dart', _class(spec));
      file('test/$n$_t', _classTest(spec));
    }
    if (spec.example) {
      file('example/${n}_example.dart', _example(spec));
    }
  }

  // ...........................................................................
  @override
  Future<void> install(Directory directory, RepoSpec spec, Tools tools) async {
    final tool = spec.flutter ? 'flutter' : 'dart';
    final packages = [
      if (spec.cli) ...['args', 'gg_args', 'gg_log'],
      if (spec.flutter) 'dev:flutter_lints' else ...['dev:lints', 'dev:test'],
    ];
    await tools.run(tool, ['pub', 'add', ...packages], directory: directory);
    await tools.run('dart', ['format', '.'], directory: directory);
  }

  // ...........................................................................
  /// The pubspec.yaml; the description is JSON-quoted, which YAML reads.
  String pubspec(RepoSpec spec) {
    final buffer = StringBuffer()
      ..writeln('name: ${spec.name}')
      ..writeln('description: ${jsonEncode(spec.description)}')
      ..writeln('version: 0.0.1')
      ..writeln('repository: ${spec.webUrl}.git');
    if (spec.isPrivate) buffer.writeln('publish_to: none');
    buffer
      ..writeln()
      ..writeln('environment:')
      ..writeln('  sdk: ">=$_sdk <4.0.0"');
    if (spec.flutter) {
      buffer
        ..writeln()
        ..writeln('dependencies:')
        ..writeln('  flutter:')
        ..writeln('    sdk: flutter')
        ..writeln()
        ..writeln('dev_dependencies:')
        ..writeln('  flutter_test:')
        ..writeln('    sdk: flutter');
    }
    if (spec.cli) {
      buffer
        ..writeln()
        ..writeln('executables:')
        ..writeln('  ${spec.name}:');
    }
    return buffer.toString();
  }

  // ######################
  // Private
  // ######################

  final String? _sdkVersion;

  static const _t = '_test.dart';

  // ...........................................................................
  /// `major.minor.0` of the Dart SDK that runs gg_create_repo.
  String get _sdk {
    final version = _sdkVersion ?? Platform.version;
    final parts = version.split(RegExp(r'[.\s]'));
    return '${parts[0]}.${parts[1]}.0';
  }

  // ...........................................................................
  String _testImport(RepoSpec spec) => spec.flutter
      ? "import 'package:flutter_test/flutter_test.dart';"
      : "import 'package:test/test.dart';";

  // ...........................................................................
  String _analysisOptions(RepoSpec spec) =>
      'include: package:'
      '${spec.flutter ? 'flutter_lints/flutter' : 'lints/recommended'}.yaml\n'
      '$_lintRules';

  // ...........................................................................
  String _library(RepoSpec spec) =>
      '${CommonFiles.fileHeader(spec)}\n'
      '/// ${spec.description}\n'
      'library;\n\n'
      "export 'src/${spec.name}.dart';\n"
      '${spec.cli ? "export 'src/commands/my_command.dart';\n" : ''}';

  // ...........................................................................
  String _class(RepoSpec spec) {
    final c = Scaffold.pascalCase(spec.name);
    return '''
${CommonFiles.fileHeader(spec)}
/// Greets whoever asks.
class $c {
  /// Constructor
  const $c({this.greeting = 'Hello'});

  /// A realistic instance; tests pass only what they care about.
  factory $c.example({String? greeting}) => $c(greeting: greeting ?? 'Hello');

  // ...........................................................................
  /// Greets [name].
  String greet(String name) => '\$greeting, \$name!';

  /// The word to greet with.
  final String greeting;
}
''';
  }

  // ...........................................................................
  String _classTest(RepoSpec spec) {
    final c = Scaffold.pascalCase(spec.name);
    return '''
${CommonFiles.fileHeader(spec)}
import 'package:${spec.name}/${spec.name}.dart';
${_testImport(spec)}

void main() {
  group('$c', () {
    test('greets with the greeting', () {
      expect(const $c(greeting: 'Hi').greet('Ada'), 'Hi, Ada!');
    });

    test('example() greets with Hello', () {
      expect($c.example().greet('Ada'), 'Hello, Ada!');
      expect($c.example(greeting: 'Hey').greeting, 'Hey');
    });
  });
}
''';
  }

  // ...........................................................................
  String _cliRoot(RepoSpec spec) {
    final c = Scaffold.pascalCase(spec.name);
    return '''
${CommonFiles.fileHeader(spec)}
import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';

import 'commands/my_command.dart';

/// The root command of ${spec.name}.
class $c extends Command<dynamic> {
  /// Constructor
  $c({required this.ggLog}) {
    addSubcommand(MyCommand(ggLog: ggLog));
  }

  // ...........................................................................
  @override
  final name = '${spec.name}';

  @override
  final description = 'The command line interface of ${spec.name}.';

  /// The log function.
  final GgLog ggLog;
}
''';
  }

  // ...........................................................................
  String _cliRootTest(RepoSpec spec) {
    final c = Scaffold.pascalCase(spec.name);
    return '''
${CommonFiles.fileHeader(spec)}
import 'package:${spec.name}/${spec.name}.dart';
${_testImport(spec)}

void main() {
  group('$c', () {
    test('offers my-command', () {
      final command = $c(ggLog: (_) {});
      expect(command.name, '${spec.name}');
      expect(command.description, contains('${spec.name}'));
      expect(command.subcommands.keys, ['my-command']);
    });
  });
}
''';
  }

  // ...........................................................................
  String _myCommand(RepoSpec spec) =>
      '''
${CommonFiles.fileHeader(spec)}
import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';

/// Logs the text given with --input.
class MyCommand extends Command<dynamic> {
  /// Constructor
  MyCommand({required this.ggLog}) {
    argParser.addOption(
      'input',
      abbr: 'i',
      help: 'The text to log.',
      mandatory: true,
    );
  }

  // ...........................................................................
  @override
  final name = 'my-command';

  @override
  final description = 'Logs the text given with --input.';

  @override
  Future<void> run() async => ggLog(argResults!['input'] as String);

  /// The log function.
  final GgLog ggLog;
}
''';

  // ...........................................................................
  String _myCommandTest(RepoSpec spec) =>
      '''
${CommonFiles.fileHeader(spec)}
import 'package:args/command_runner.dart';
import 'package:${spec.name}/${spec.name}.dart';
${_testImport(spec)}

void main() {
  group('MyCommand', () {
    test('logs the input', () async {
      final messages = <String>[];
      final runner = CommandRunner<dynamic>('test', 'test')
        ..addCommand(MyCommand(ggLog: messages.add));

      await runner.run(['my-command', '--input', 'hello']);
      expect(messages, ['hello']);
    });
  });
}
''';

  // ...........................................................................
  String _bin(RepoSpec spec) {
    final c = Scaffold.pascalCase(spec.name);
    return '''
#!/usr/bin/env dart
${CommonFiles.fileHeader(spec)}
import 'package:gg_args/gg_args.dart';
import 'package:gg_log/gg_log.dart';
import 'package:${spec.name}/${spec.name}.dart';

// .............................................................................
/// Runs ${spec.name} with [args].
Future<void> run({required List<String> args, required GgLog ggLog}) =>
    GgCommandRunner(ggLog: ggLog, command: $c(ggLog: ggLog)).run(args: args);

// .............................................................................
Future<void> main(List<String> args) async {
  await run(args: args, ggLog: print);
}
''';
  }

  // ...........................................................................
  String _binTest(RepoSpec spec) =>
      '''
${CommonFiles.fileHeader(spec)}
import '../../bin/${spec.name}.dart';
${_testImport(spec)}

void main() {
  group('bin/${spec.name}.dart', () {
    test('runs my-command', () async {
      final messages = <String>[];
      await run(args: ['my-command', '-i', 'hello'], ggLog: messages.add);
      expect(messages, ['hello']);
    });
  });
}
''';

  // ...........................................................................
  String _example(RepoSpec spec) {
    final c = Scaffold.pascalCase(spec.name);
    final body = spec.cli
        ? "  await CommandRunner<dynamic>('${spec.name}', 'Example')\n"
              "      .run(['help']);\n"
        : "${spec.flutter ? '  // ignore: avoid_print\n' : ''}"
              "  print(const $c().greet('World'));\n";
    final imports = spec.cli
        ? "import 'package:args/command_runner.dart';\n"
        : "import 'package:${spec.name}/${spec.name}.dart';\n";
    return '#!/usr/bin/env dart\n'
        '${CommonFiles.fileHeader(spec)}\n'
        '$imports\n'
        'Future<void> main() async {\n'
        '$body'
        '}\n';
  }

  // ...........................................................................
  static const _gitignore = '''
.dart_tool/
build/
coverage/
node_modules/
*.vm.json
.DS_Store
.gg/*
!.gg/gg.json
''';

  static const _lintRules = '''

linter:
  rules:
    - always_declare_return_types
    - camel_case_types
    - lines_longer_than_80_chars
    - missing_whitespace_between_adjacent_strings
    - prefer_const_constructors
    - prefer_const_constructors_in_immutables
    - prefer_const_declarations
    - prefer_const_literals_to_create_immutables
    - prefer_single_quotes
    - public_member_api_docs
    - require_trailing_commas
    - unawaited_futures
    - void_checks

analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
''';
}
