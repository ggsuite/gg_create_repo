// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import '../repo_language.dart';
import '../repo_spec.dart';
import '../tools.dart';
import 'dart_scaffold.dart';
import 'ts_scaffold.dart';

/// Writes and installs the skeleton of one language.
abstract class Scaffold {
  /// Constructor
  const Scaffold();

  /// The scaffold for the language of [spec].
  factory Scaffold.forSpec(RepoSpec spec) => switch (spec.language) {
    RepoLanguage.dart => const DartScaffold(),
    RepoLanguage.typescript => const TsScaffold(),
  };

  // ...........................................................................
  /// Writes every file of the skeleton into [directory].
  void write(Directory directory, RepoSpec spec);

  /// Adds the dependencies at their latest versions.
  Future<void> install(Directory directory, RepoSpec spec, Tools tools);

  // ...........................................................................
  /// `gg_create_repo` becomes `GgCreateRepo`, `my-lib` becomes `MyLib`.
  /// A leading digit gets the prefix `Repo`: classes cannot start with one.
  static String pascalCase(String name) {
    final pascal = name
        .split(RegExp('[^A-Za-z0-9]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join();
    return RegExp('^[0-9]').hasMatch(pascal) ? 'Repo$pascal' : pascal;
  }

  // ...........................................................................
  /// [text] as a single-quoted Dart or TypeScript string literal.
  static String quoted(String text) {
    final escaped = text
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll(r'$', r'\$');
    return "'$escaped'";
  }
}
