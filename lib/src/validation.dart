// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'repo_language.dart';

/// Checks the values of a new repository before anything is created.
///
/// Every method returns `null` for a valid value and the reason otherwise,
/// so the same rules serve the options and the interactive prompts.
class Validation {
  /// Constructor
  const Validation();

  // ...........................................................................
  /// The name of the repository, its folder and its package.
  String? name(String name, RepoLanguage language) {
    if (name.isEmpty) return 'The name must not be empty.';
    if (name.length > 100) {
      return 'The name must have at most 100 characters.';
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
  /// A `key=value` pair for a DNA variable.
  String? variable(String pair) {
    final index = pair.indexOf('=');
    if (index <= 0) {
      return '»$pair« is no variable: use key=value.';
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
    return null;
  }

  static final _dartIdentifier = RegExp(r'^[a-z][a-z0-9_]*$');
  static final _npmPart = RegExp(r'^[a-z0-9][a-z0-9._-]*$');
  static final _githubOwner = RegExp(r'^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$');

  static const _windowsDeviceNames = {
    'con', 'prn', 'aux', 'nul', //
    'com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'com8', 'com9',
    'lpt1', 'lpt2', 'lpt3', 'lpt4', 'lpt5', 'lpt6', 'lpt7', 'lpt8', 'lpt9',
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
