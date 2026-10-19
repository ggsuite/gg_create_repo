// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'repo_language.dart';

/// Everything that describes the repository to create.
class RepoSpec {
  /// Constructor
  const RepoSpec({
    required this.name,
    required this.language,
    required this.org,
    required this.description,
    this.isPrivate = false,
    this.dnaLayers = const [],
    this.vars = const {},
    this.cli = false,
    this.example = true,
    this.flutter = false,
    this._npmScope,
  });

  /// Restores a spec written by [toJson].
  factory RepoSpec.fromJson(Map<String, dynamic> json) => RepoSpec(
    name: json['name'] as String,
    language: RepoLanguage.parse(json['language'] as String),
    org: json['org'] as String,
    description: json['description'] as String,
    isPrivate: json['isPrivate'] as bool,
    dnaLayers: (json['dnaLayers'] as List<dynamic>).cast<String>(),
    vars: (json['vars'] as Map<String, dynamic>).cast<String, String>(),
    cli: json['cli'] as bool,
    example: json['example'] as bool,
    flutter: json['flutter'] as bool,
    npmScope: json['npmScope'] as String?,
  );

  /// A realistic spec; tests pass only what they care about.
  factory RepoSpec.example({
    String? name,
    RepoLanguage? language,
    String? org,
    String? description,
    bool? isPrivate,
    List<String>? dnaLayers,
    Map<String, String>? vars,
    bool? cli,
    bool? example,
    bool? flutter,
    String? npmScope,
  }) => RepoSpec(
    name: name ?? 'gg_example_repo',
    language: language ?? RepoLanguage.dart,
    org: org ?? 'ggsuite',
    description:
        description ??
        'An example repository created by gg_create_repo for the tests.',
    isPrivate: isPrivate ?? false,
    dnaLayers: dnaLayers ?? const ['dna_ggsuite'],
    vars: vars ?? const {},
    cli: cli ?? false,
    example: example ?? true,
    flutter: flutter ?? false,
    npmScope: npmScope,
  );

  // ...........................................................................
  /// The values as JSON, for the state file.
  Map<String, dynamic> toJson() => {
    'name': name,
    'language': language.name,
    'org': org,
    'description': description,
    'isPrivate': isPrivate,
    'dnaLayers': dnaLayers,
    'vars': vars,
    'cli': cli,
    'example': example,
    'flutter': flutter,
    'npmScope': _npmScope,
  };

  // ...........................................................................
  /// A copy with the DNA layers and variables replaced.
  RepoSpec copyWith({List<String>? dnaLayers, Map<String, String>? vars}) =>
      RepoSpec(
        name: name,
        language: language,
        org: org,
        description: description,
        isPrivate: isPrivate,
        dnaLayers: dnaLayers ?? this.dnaLayers,
        vars: vars ?? this.vars,
        cli: cli,
        example: example,
        flutter: flutter,
        npmScope: _npmScope,
      );

  /// `org/name`, the slug on GitHub.
  String get slug => '$org/$name';

  /// The npm scope without `@`: the given one or the lower-cased org.
  String get npmScope => _npmScope ?? org.toLowerCase();

  /// The name in the registry: `name` for Dart, `@scope/name` for npm.
  String get packageName =>
      language == RepoLanguage.dart ? name : '@$npmScope/$name';

  /// The web URL of the repository on GitHub.
  String get webUrl => 'https://github.com/$slug';

  /// The name of the repository, folder and package (without scope).
  final String name;

  /// The language of the package.
  final RepoLanguage language;

  /// The GitHub owner: an organization or a user.
  final String org;

  /// One line saying what the package is for.
  final String description;

  /// Private repositories are never published to a registry.
  final bool isPrivate;

  /// DNA layers to add, as package names or git URLs; empty for none.
  final List<String> dnaLayers;

  /// Values for the DNA variables, written to `dna/_vars.json`.
  final Map<String, String> vars;

  /// Dart only: whether the package gets a command line interface.
  final bool cli;

  /// Dart only: whether the package gets an `example/` folder.
  final bool example;

  /// Dart only: whether the package is a Flutter package.
  final bool flutter;

  // ######################
  // Private
  // ######################

  final String? _npmScope;
}
