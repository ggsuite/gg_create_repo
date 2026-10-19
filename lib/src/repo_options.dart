// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'repo_language.dart';
import 'repo_spec.dart';

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

  // ...........................................................................
  /// These options with the values of [earlier] where none was given: a
  /// continued run asks nothing the earlier one answered.
  RepoOptions withDefaultsOf(RepoSpec earlier) {
    final ts = earlier.language == RepoLanguage.typescript;
    final layers = dnaLayers.isEmpty && !withoutDna
        ? earlier.dnaLayers
        : dnaLayers;
    return RepoOptions(
      name: name ?? earlier.name,
      language: language,
      org: org ?? earlier.org,
      description: description ?? earlier.description,
      npmScope: npmScope ?? (ts ? earlier.npmScope : null),
      isPrivate: isPrivate ?? earlier.isPrivate,
      cli: cli ?? earlier.cli,
      example: example ?? earlier.example,
      flutter: flutter ?? earlier.flutter,
      dnaLayers: layers,
      withoutDna: withoutDna || layers.isEmpty,
      vars: [
        for (final MapEntry(:key, :value) in earlier.vars.entries)
          '$key=$value',
        ...vars,
      ],
      interactive: interactive,
    );
  }

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
