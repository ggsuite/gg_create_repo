// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'repo_language.dart';
import 'scaffold/scaffold.dart';

/// Checks the values of a new repository before anything is created.
/// Every method returns `null` for a valid value and the reason otherwise.
class Validation {
  /// Constructor
  const Validation();

  /// The rules; there is nothing to configure.
  factory Validation.example() => const Validation();

  // ...........................................................................
  /// The name of the repository, its folder and its package.
  String? name(String name, RepoLanguage language) {
    if (name.isEmpty) return 'The name must not be empty.';
    final maxLength = language == RepoLanguage.dart ? 64 : 100;
    if (name.length > maxLength) {
      return 'The name must have at most $maxLength characters.';
    }
    if (_windowsDeviceNames.contains(name.split('.').first)) {
      return '»$name« is a reserved file name on Windows.';
    }
    return switch (language) {
      RepoLanguage.dart => _dartName(name),
      RepoLanguage.typescript => _npmName(name),
    };
  }

  // ...........................................................................
  /// A GitHub owner: letters, digits and single hyphens, at most 39.
  String? org(String org) {
    if (org.isEmpty) return 'The organization must not be empty.';
    if (org.length > 39 || !_githubOwner.hasMatch(org)) {
      return '»$org« is no valid GitHub organization or user name: '
          'use letters, digits and single hyphens, at most 39 characters.';
    }
    return null;
  }

  // ...........................................................................
  /// One line of text; Dart needs 60 to 180 characters for pana.
  String? description(String description, RepoLanguage language) {
    if (description.contains('\n') || description.contains('\r')) {
      return 'The description must be a single line.';
    }
    final length = description.length;
    if (language == RepoLanguage.dart && (length < 60 || length > 180)) {
      return 'pub.dev needs 60 to 180 characters, the description has '
          '$length.';
    }
    if (length == 0) return 'The description must not be empty.';
    if (length > 350) {
      return 'GitHub allows at most 350 characters, the description has '
          '$length.';
    }
    return null;
  }

  // ...........................................................................
  /// An npm scope without `@`.
  String? npmScope(String scope) =>
      _npmPart.hasMatch(scope) && !scope.startsWith('.')
      ? null
      : '»$scope« is no valid npm scope: use lowercase letters, digits, '
            '».«, »-« and »_«.';

  // ...........................................................................
  /// A `key=value` pair for a DNA variable; helix names them like
  /// `dnaProjectName`.
  String? variable(String pair) {
    final index = pair.indexOf('=');
    if (index <= 0) return '»$pair« is no variable: use key=value.';
    final key = pair.substring(0, index).trim();
    if (!_dnaVariable.hasMatch(key)) {
      return '»$key« is no DNA variable: use dna and camel case, like '
          'dnaProjectName.';
    }
    if (pair.substring(index + 1).trim().isEmpty) {
      return 'The variable »$key« needs a value.';
    }
    return null;
  }

  // ######################
  // Private
  // ######################

  // ...........................................................................
  String? _dartName(String name) {
    if (!_dartIdentifier.hasMatch(name)) {
      return '»$name« is no valid Dart package name: use lowercase '
          'letters, digits and underscores, starting with a letter.';
    }
    if (_dartReservedWords.contains(name)) {
      return '»$name« is a reserved word in Dart.';
    }
    if (skeletonDependencies.contains(name)) {
      return '»$name« is a dependency of the skeleton itself.';
    }
    final pascal = Scaffold.pascalCase(name);
    if (_takenClassNames.contains(pascal)) {
      return 'The class »$pascal« of »$name« would clash with a Dart or '
          'gg class of the same name.';
    }
    return null;
  }

  // ...........................................................................
  String? _npmName(String name) {
    if (!_npmPart.hasMatch(name) ||
        name.startsWith('.') ||
        name.startsWith('_')) {
      return '»$name« is no valid npm package name: use lowercase '
          'letters, digits, ».«, »-« and »_«, not starting with ».« or »_«.';
    }
    if (name == 'index') {
      return '»index« is taken by src/index.ts.';
    }
    final pascal = Scaffold.pascalCase(name);
    if (_tsGlobals.contains(pascal)) {
      return 'The class »$pascal« of »$name« would hide the global '
          'JavaScript or TypeScript type of the same name.';
    }
    return null;
  }

  static final _dartIdentifier = RegExp(r'^[a-z][a-z0-9_]*$');
  static final _npmPart = RegExp(r'^[a-z0-9][a-z0-9._-]*$');
  static final _githubOwner = RegExp(r'^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$');
  static final _dnaVariable = RegExp(r'^dna[A-Z][a-zA-Z0-9]*$');

  static const _windowsDeviceNames = {
    'con', 'prn', 'aux', 'nul', //
    'com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'com8', 'com9',
    'lpt1', 'lpt2', 'lpt3', 'lpt4', 'lpt5', 'lpt6', 'lpt7', 'lpt8', 'lpt9',
  };

  /// What a Dart, CLI or Flutter skeleton resolves; nothing depends on itself.
  static const skeletonDependencies = {
    '_fe_analyzer_shared', 'analyzer', 'args', 'async', 'boolean_selector', //
    'characters', 'cli_config', 'cli_util', 'clock', 'collection', 'colorize',
    'convert', 'coverage', 'crypto', 'fake_async', 'ffi', 'file', 'flutter',
    'flutter_lints', 'flutter_test', 'frontend_server_client', 'gg_args',
    'gg_capture_print', 'gg_console_colors', 'gg_hash', 'gg_json', 'gg_log',
    'gg_process', 'glob', 'helix', 'http_multi_server', 'http_parser', 'io',
    'leak_tracker', 'leak_tracker_flutter_testing', 'leak_tracker_testing',
    'lints', 'logging', 'matcher', 'material_color_utilities', 'meta', 'mime',
    'mocktail', 'node_preamble', 'package_config', 'path', 'pool',
    'pub_semver', 'recase', 'shelf', 'shelf_packages_handler', 'shelf_static',
    'shelf_web_socket', 'sky_engine', 'source_map_stack_trace', 'source_maps',
    'source_span', 'stack_trace', 'stream_channel', 'string_scanner',
    'term_glyph', 'test', 'test_api', 'test_core', 'typed_data',
    'vector_math', 'vm_service', 'watcher', 'web', 'web_socket',
    'web_socket_channel', 'webkit_inspection_protocol', 'yaml',
  };

  /// Classes of `dart:core` and the skeleton; the rest is imported by `show`.
  static const _takenClassNames = {
    'BigInt', 'Comparable', 'Command', 'CommandRunner', 'DateTime', //
    'Deprecated', 'Duration', 'Enum', 'Error', 'Exception', 'Expando',
    'Finalizer', 'Function', 'Future', 'GgCommandRunner', 'GgLog',
    'Invocation', 'Iterable', 'Iterator', 'List', 'Map', 'MapEntry',
    'Match', 'MyCommand', 'Null', 'Object', 'Pattern', 'Record', 'RegExp',
    'Runes', 'Set', 'Sink', 'StackTrace', 'Stopwatch', 'Stream', 'String',
    'StringBuffer', 'StringSink', 'Symbol', 'Type', 'Uri', 'UriData',
    'WeakReference',
  };

  static const _tsGlobals = {
    'Array', 'ArrayBuffer', 'Awaited', 'BigInt', 'Boolean', 'Capitalize', //
    'ConstructorParameters', 'DataView', 'Date', 'Error', 'Exclude',
    'Extract', 'Function', 'InstanceType', 'Intl', 'Iterator', 'JSON',
    'Lowercase', 'Map', 'Math', 'NoInfer', 'NonNullable', 'Number', 'Object',
    'Omit', 'Parameters', 'Partial', 'Pick', 'Promise', 'Proxy', 'Readonly',
    'Record', 'Reflect', 'RegExp', 'Required', 'ReturnType', 'Set', 'String',
    'Symbol', 'ThisType', 'Uncapitalize', 'Uppercase', 'WeakMap', 'WeakRef',
    'WeakSet',
  };

  static const _dartReservedWords = {
    'abstract',
    'as',
    'assert',
    'async',
    'await',
    'base',
    'break',
    'case',
    'catch',
    'class',
    'const',
    'continue',
    'covariant',
    'default',
    'deferred',
    'do',
    'dynamic',
    'else',
    'enum',
    'export',
    'extends',
    'extension',
    'external',
    'factory',
    'false',
    'final',
    'finally',
    'for',
    'function',
    'get',
    'hide',
    'if',
    'implements',
    'import',
    'in',
    'interface',
    'is',
    'late',
    'library',
    'mixin',
    'new',
    'null',
    'of',
    'on',
    'operator',
    'part',
    'required',
    'rethrow',
    'return',
    'sealed',
    'set',
    'show',
    'static',
    'super',
    'switch',
    'sync',
    'this',
    'throw',
    'true',
    'try',
    'type',
    'typedef',
    'var',
    'void',
    'when',
    'while',
    'with',
    'yield',
  };
}
