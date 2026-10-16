// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_interact/gg_interact.dart';
import 'package:gg_log/gg_log.dart';

import 'github.dart';
import 'registry.dart';
import 'repo_host.dart';
import 'repo_language.dart';
import 'repo_options.dart';
import 'repo_spec.dart';
import 'validation.dart';

/// Turns the options into a [RepoSpec] and asks for what is missing.
///
/// Name, language, organization, description and the DNA are needed:
/// missing ones are asked for, or headless runs fail with the option to
/// pass. Everything else has a default and is only asked with `-i`.
class SpecCollector {
  /// Constructor
  SpecCollector({
    required this.ggLog,
    this._prompts,
    this._hasTerminal = stdioHasTerminal,
    this._gitHub = const GitHub(),
    Registry? registry,
    this._validation = const Validation(),
  }) : _registry = registry ?? Registry();

  // ...........................................................................
  /// The spec for [options]; [asked] tells whether a question was asked.
  Future<RepoSpec> collect(RepoOptions options, RepoHost host) async {
    _asked = false;
    _interactive = options.interactive;

    final language = options.language != null
        ? _parseLanguage(options.language!)
        : RepoLanguage.values[await _select(
            'Which language?',
            RepoLanguage.values.map((l) => l.label).toList(),
            option: '--language',
          )];

    final org = await _org(options, host);

    final name = await _text(
      options.name,
      'Name of the repository',
      option: '--name',
      validate: (v) => _validation.name(v, language),
    );

    final description = await _text(
      options.description,
      'Description',
      option: '--description',
      validate: (v) => _validation.description(v, language),
    );

    final isPrivate =
        options.isPrivate ??
        (_interactive &&
            await _select('Visibility', [
                  'Public',
                  'Private',
                ], option: '--[no-]private') ==
                1);

    final isDart = language == RepoLanguage.dart;
    final cli = isDart && await _optional(options.cli, 'With a CLI?', false);
    final example =
        isDart && await _optional(options.example, 'With an example?', true);
    final flutter =
        isDart &&
        !cli &&
        await _optional(options.flutter, 'A Flutter package?', false);
    if (options.flutter == true && cli) {
      throw Exception(cError('A Flutter package gets no CLI.'));
    }

    final npmScope = isDart ? null : await _scope(options, org);

    final draft = RepoSpec(
      name: name,
      language: language,
      org: org,
      description: description,
      isPrivate: isPrivate,
      cli: cli,
      example: example,
      flutter: flutter,
      npmScope: npmScope,
    );

    return draft.copyWith(
      dnaLayers: await _dna(options, host, draft),
      vars: _vars(options.vars),
    );
  }

  /// Whether the last [collect] asked the user anything.
  bool get asked => _asked;

  /// The log function.
  final GgLog ggLog;

  /// Whether a user can answer: stdin to read and stdout to draw on.
  ///
  /// stdin alone is not enough: on Windows it reports a terminal even when
  /// the output goes to a pipe and nobody sees the question.
  // coverage:ignore-start
  static bool stdioHasTerminal() => stdin.hasTerminal && stdout.hasTerminal;
  // coverage:ignore-end

  /// The DNA layer proposed for [spec]: the one named after the org.
  static String suggestedDna(RepoSpec spec) {
    final org = spec.org.toLowerCase();
    return spec.language == RepoLanguage.dart
        ? 'dna_${org.replaceAll('-', '_')}'
        : '@${spec.npmScope}/dna-$org';
  }

  // ######################
  // Private
  // ######################

  final GgPrompts? _prompts;
  final HasTerminal _hasTerminal;
  final GitHub _gitHub;
  final Registry _registry;
  final Validation _validation;
  var _asked = false;
  var _interactive = false;

  static const _enterDna = 'Enter a package name or git URL';
  static const _noDna = 'No DNA';
  static const _otherOrg = 'Another organization or user';

  GgPrompts get _p => _prompts ?? GgPrompts.current;

  // ...........................................................................
  RepoLanguage _parseLanguage(String value) {
    try {
      return RepoLanguage.parse(value);
    } on ArgumentError {
      throw Exception(cError('»$value« is no language. Use dart or ts.'));
    }
  }

  // ...........................................................................
  Future<String> _org(RepoOptions options, RepoHost host) async {
    if (options.org != null) return _valid(options.org!, _validation.org);
    final preset = host.presetOrg;
    if (preset != null && !options.interactive) return preset;

    final known = <String>{
      ?preset,
      ...await host.knownOrgs(),
      ...await _gitHub.orgs(),
      ?await _gitHub.login(),
    }.toList();
    if (known.isNotEmpty) {
      final index = await _select('Organization', [
        ...known,
        _otherOrg,
      ], option: '--org');
      if (index < known.length) return known[index];
    }
    return _text(
      null,
      'GitHub organization or user',
      option: '--org',
      validate: _validation.org,
    );
  }

  // ...........................................................................
  Future<String?> _scope(RepoOptions options, String org) async {
    if (options.npmScope != null) {
      return _valid(options.npmScope!, _validation.npmScope);
    }
    if (!options.interactive) return null;
    return _text(
      null,
      'npm scope (without @)',
      option: '--scope',
      validate: _validation.npmScope,
      defaultValue: org.toLowerCase(),
    );
  }

  // ...........................................................................
  Future<List<String>> _dna(
    RepoOptions options,
    RepoHost host,
    RepoSpec spec,
  ) async {
    if (options.withoutDna && options.dnaLayers.isNotEmpty) {
      throw Exception(cError('Pass either --dna or --without-dna.'));
    }
    if (options.withoutDna) return const [];
    if (options.dnaLayers.isNotEmpty) return options.dnaLayers;

    final candidates = await _dnaCandidates(host, spec);
    final suggested = suggestedDna(spec);
    final hasSuggestion = candidates.any((c) => c.ref == suggested);
    if (!_hasTerminal() && hasSuggestion) return [suggested];

    final layers = <String>[];
    while (true) {
      final labels = [for (final c in candidates) c.label, _enterDna, _noDna];
      final index = await _select(
        layers.isEmpty ? 'Which DNA?' : 'Which further DNA?',
        labels,
        option: '--dna <package or git url> or --without-dna',
      );
      if (index == labels.length - 1) return layers;
      layers.add(
        index < candidates.length
            ? candidates[index].ref
            : await _text(
                null,
                'DNA package name or git URL',
                option: '--dna',
                validate: (v) => v.isEmpty ? 'Please enter a layer.' : null,
              ),
      );
      if (!await _p.confirm(prompt: 'Add another DNA?', defaultValue: false)) {
        return layers;
      }
    }
  }

  // ...........................................................................
  /// The suggested layer when it exists, then those of the host.
  Future<List<DnaCandidate>> _dnaCandidates(
    RepoHost host,
    RepoSpec spec,
  ) async {
    final suggested = suggestedDna(spec);
    final fromHost = host.dnaCandidates(spec);
    final exists =
        fromHost.any((c) => c.label == suggested) ||
        await _registry.has(suggested, spec.language) == true;
    return [
      if (exists) DnaCandidate(label: '$suggested (suggested)', ref: suggested),
      ...fromHost.where((c) => c.label != suggested),
    ];
  }

  // ...........................................................................
  Map<String, String> _vars(List<String> pairs) => {
    for (final pair in pairs)
      _valid(pair, _validation.variable).split('=').first: pair.substring(
        pair.indexOf('=') + 1,
      ),
  };

  // ...........................................................................
  Future<bool> _optional(bool? given, String prompt, bool fallback) async {
    if (given != null) return given;
    if (!_interactive) return fallback;
    _ensureTerminal(prompt, '--[no-]<flag>');
    _asked = true;
    return _p.confirm(prompt: prompt, defaultValue: fallback);
  }

  // ...........................................................................
  Future<int> _select(
    String prompt,
    List<String> options, {
    required String option,
  }) {
    _ensureTerminal(prompt, option);
    _asked = true;
    return _p.select(prompt: prompt, options: options);
  }

  // ...........................................................................
  Future<String> _text(
    String? given,
    String prompt, {
    required String option,
    required String? Function(String) validate,
    String? defaultValue,
  }) {
    if (given != null) return Future.value(_valid(given, validate));
    _ensureTerminal(prompt, option);
    _asked = true;
    return _p.inputUntilValid(
      prompt: prompt,
      validate: validate,
      onInvalid: (reason) => ggLog(cError(reason)),
      defaultValue: defaultValue,
    );
  }

  // ...........................................................................
  String _valid(String value, String? Function(String) validate) {
    final reason = validate(value.trim());
    if (reason != null) throw Exception(cError(reason));
    return value.trim();
  }

  // ...........................................................................
  void _ensureTerminal(String prompt, String option) => throwWhenNotATerminal(
    'the question »$prompt«',
    'pass $option',
    hasTerminal: _hasTerminal,
  );
}
