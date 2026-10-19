// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

/// The languages a new repository can be written in.
enum RepoLanguage {
  /// A Dart (or Flutter) package managed with pub.
  dart('Dart'),

  /// A TypeScript package managed with pnpm.
  typescript('TypeScript');

  /// Constructor
  const RepoLanguage(this.label);

  // ...........................................................................
  /// Parses `dart`, `ts` or `typescript`, ignoring case.
  static RepoLanguage parse(String value) =>
      switch (value.trim().toLowerCase()) {
        'dart' => dart,
        'ts' || 'typescript' => typescript,
        _ => throw ArgumentError.value(value, 'language', 'Use »dart« or »ts«'),
      };

  /// The name shown to the user.
  final String label;
}
