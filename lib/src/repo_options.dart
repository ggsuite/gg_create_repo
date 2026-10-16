// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

/// The values given on the command line; `null` means not given.
class RepoOptions {
  /// Constructor
  const RepoOptions({
    this.name,
    this.language,
    this.org,
    this.description,
    this.npmScope,
    this.isPrivate,
    this.cli,
    this.example,
    this.flutter,
    this.dnaLayers = const [],
    this.withoutDna = false,
    this.vars = const [],
    this.interactive = false,
  });

  /// Options that answer every question; tests change what they need.
  factory RepoOptions.example({
    String? name,
    String? language,
    String? org,
    String? description,
    List<String>? dnaLayers,
    bool? withoutDna,
    bool? interactive,
  }) => RepoOptions(
    name: name ?? 'gg_example_repo',
    language: language ?? 'dart',
    org: org ?? 'ggsuite',
    description:
        description ??
        'An example repository created by gg_create_repo for the tests.',
    dnaLayers: dnaLayers ?? const ['dna_ggsuite'],
    withoutDna: withoutDna ?? false,
    interactive: interactive ?? false,
  );

  /// `--name`
  final String? name;

  /// `--language`
  final String? language;

  /// `--org`
  final String? org;

  /// `--description`
  final String? description;

  /// `--scope`
  final String? npmScope;

  /// `--[no-]private`
  final bool? isPrivate;

  /// `--[no-]cli`
  final bool? cli;

  /// `--[no-]example`
  final bool? example;

  /// `--[no-]flutter`
  final bool? flutter;

  /// `--dna`, given as often as needed.
  final List<String> dnaLayers;

  /// `--without-dna`
  final bool withoutDna;

  /// `--var key=value`, given as often as needed.
  final List<String> vars;

  /// `--interactive`: ask every question, not only the missing ones.
  final bool interactive;
}
