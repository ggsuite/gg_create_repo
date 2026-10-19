// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_interact/gg_interact.dart';
import 'package:gg_log/gg_log.dart';
import 'package:mocktail/mocktail.dart';

import 'dna/dna_variables.dart';
import 'github.dart';
import 'registry.dart';
import 'repo_host.dart';
import 'repo_language.dart';
import 'repo_options.dart';
import 'repo_spec.dart';
import 'validation.dart';

/// A collected spec and whether the user was asked anything for it.
typedef CollectedSpec = ({RepoSpec spec, bool asked});

/// Turns the options into a [RepoSpec] and asks for what is missing; headless
/// runs fail with the option to pass instead. Name, language, org,
/// description and DNA are needed, the rest is only asked with `-i`.
class SpecCollector {
  /// Constructor
  SpecCollector({
    required this.ggLog,
    this._prompts,
    this._hasTerminal = stdioHasTerminal,
    this._gitHub = const GitHub(),
    Registry? registry,
    this._validation = const Validation(),
    this._dnaVariables = const DnaVariables(),
  }) : _registry = registry ?? Registry();

  /// A collector on the real tools; tests pass what they care about.
  factory SpecCollector.example({
    GgLog? ggLog,
    GgPrompts? prompts,
    HasTerminal? hasTerminal,
    GitHub? gitHub,
    Registry? registry,
  }) => SpecCollector(
    ggLog: ggLog ?? (_) {},
    prompts: prompts,
    hasTerminal: hasTerminal ?? stdioHasTerminal,
    gitHub: gitHub ?? const GitHub(),
    registry: registry,
  );

  // ...........................................................................
  /// The spec for [options] and whether a question was asked.
  Future<CollectedSpec> collect(RepoOptions options, RepoHost host) async {
    final run = _Run(this, options);
    final language = options.language != null
        ? _parseLanguage(options.language!)
        : RepoLanguage.values[await run.select(
            'Which language?',
            RepoLanguage.values.map((l) => l.label).toList(),
            option: '--language',
          )];

    final org = await _org(run, host);
    final name = await run.text(
      options.name,
      'Name of the repository',
      option: '--name',
      validate: (v) => _validation.name(v, language),
    );
    final description = await run.text(
      options.description,
      'Description',
      option: '--description',
      validate: (v) => _validation.description(v, language),
    );
    final isPrivate =
        options.isPrivate ??
        (options.interactive &&
            await run.select('Visibility', [
                  'Public',
                  'Private',
                ], option: '--[no-]private') ==
                1);

    final isDart = language == RepoLanguage.dart;
    if (isDart && options.flutter == true && options.cli == true) {
      throw Exception(cError('A Flutter package gets no CLI.'));
    }
    final cli = isDart && await run.optional(options.cli, 'With a CLI?', false);
    final example =
        isDart && await run.optional(options.example, 'With an example?', true);
    final flutter =
        isDart &&
        !cli &&
        await run.optional(options.flutter, 'A Flutter package?', false);

    final draft = RepoSpec(
      name: name,
      language: language,
      org: org,
      description: description,
      isPrivate: isPrivate,
      cli: cli,
      example: example,
      flutter: flutter,
      npmScope: isDart ? null : await _scope(run, org),
    );
    final layers = await _dna(run, host, draft);
    final vars = await _vars(run, host, layers);
    return (
      spec: draft.copyWith(dnaLayers: layers, vars: vars),
      asked: run.asked,
    );
  }

  // ...........................................................................
  /// The DNA layer proposed for [spec]: the one named after the org.
  static String suggestedDna(RepoSpec spec) {
    final org = spec.org.toLowerCase();
    return spec.language == RepoLanguage.dart
        ? 'dna_${org.replaceAll('-', '_')}'
        : '@${spec.npmScope}/dna-$org';
  }

  /// The log function.
  final GgLog ggLog;

  // ######################
  // Private
  // ######################

  final GgPrompts? _prompts;
  final HasTerminal _hasTerminal;
  final GitHub _gitHub;
  final Registry _registry;
  final Validation _validation;
  final DnaVariables _dnaVariables;

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
  Future<String> _org(_Run run, RepoHost host) async {
    final given = run.options.org;
    if (given != null) return run.valid(given, _validation.org);
    final preset = host.presetOrg;
    if (preset != null && !run.options.interactive) return preset;

    run.ensureTerminal('Organization', '--org');
    final known = <String>{
      ?preset,
      ...await host.knownOrgs(),
      ...await _gitHub.orgs(),
      ?await _gitHub.login(),
    }.toList();
    if (known.isNotEmpty) {
      final index = await run.select('Organization', [
        ...known,
        _otherOrg,
      ], option: '--org');
      if (index < known.length) return known[index];
    }
    return run.text(
      null,
      'GitHub organization or user',
      option: '--org',
      validate: _validation.org,
    );
  }

  // ...........................................................................
  Future<String?> _scope(_Run run, String org) async {
    final given = run.options.npmScope;
    if (given != null) return run.valid(given, _validation.npmScope);
    if (!run.options.interactive) return null;
    return run.text(
      null,
      'npm scope (without @)',
      option: '--scope',
      validate: _validation.npmScope,
      defaultValue: org.toLowerCase(),
    );
  }

  // ...........................................................................
  /// Headless, only a suggestion the host itself offers is taken: a
  /// registry name alone could belong to anybody.
  Future<List<String>> _dna(_Run run, RepoHost host, RepoSpec spec) async {
    final options = run.options;
    if (options.withoutDna && options.dnaLayers.isNotEmpty) {
      throw Exception(cError('Pass either --dna or --without-dna.'));
    }
    if (options.withoutDna) return const [];
    if (options.dnaLayers.isNotEmpty) return options.dnaLayers;

    final suggested = suggestedDna(spec);
    final fromHost = host.dnaCandidates(spec);
    if (!_hasTerminal() && fromHost.any((c) => c.ref == suggested)) {
      return [suggested];
    }
    run.ensureTerminal('Which DNA?', '--dna <layer> or --without-dna');

    final candidates = await _dnaCandidates(spec, fromHost, suggested);
    final layers = <String>[];
    while (true) {
      final labels = [for (final c in candidates) c.label, _enterDna, _noDna];
      final index = await run.select(
        layers.isEmpty ? 'Which DNA?' : 'Which further DNA?',
        labels,
        option: '--dna',
      );
      if (index == labels.length - 1) return layers;
      layers.add(
        index < candidates.length
            ? candidates[index].ref
            : await run.text(
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
  /// The suggested layer when the host or the registry has it, then the
  /// other layers of the host.
  Future<List<DnaCandidate>> _dnaCandidates(
    RepoSpec spec,
    List<DnaCandidate> fromHost,
    String suggested,
  ) async {
    final exists =
        fromHost.any((c) => c.ref == suggested) ||
        await _registry.has(suggested, spec.language) == true;
    return [
      if (exists) DnaCandidate(label: '$suggested (suggested)', ref: suggested),
      ...fromHost.where((c) => c.ref != suggested),
    ];
  }

  // ...........................................................................
  /// The `--var` values plus the required variables the layers' local
  /// copies name; headless, a missing one is an error.
  Future<Map<String, String>> _vars(
    _Run run,
    RepoHost host,
    List<String> layers,
  ) async {
    final vars = <String, String>{
      for (final pair in run.options.vars)
        run.valid(pair, _validation.variable).split('=').first: pair.substring(
          pair.indexOf('=') + 1,
        ),
    };
    final missing = _dnaVariables
        .missing(layers: layers, given: vars, host: host)
        .missing;
    for (final variable in missing) {
      vars[variable.name] = await run.text(
        null,
        '${variable.name} (required by ${variable.requiredBy})',
        option: '--var ${variable.name}=<value>',
        validate: (v) => v.isEmpty ? 'A value is required.' : null,
      );
    }
    return vars;
  }
}

/// The state of one [SpecCollector.collect] call.
class _Run {
  _Run(this.collector, this.options);

  final SpecCollector collector;
  final RepoOptions options;
  var asked = false;

  // ...........................................................................
  Future<bool> optional(bool? given, String prompt, bool fallback) async {
    if (given != null) return given;
    if (!options.interactive) return fallback;
    ensureTerminal(prompt, '--[no-]<flag>');
    asked = true;
    return collector._p.confirm(prompt: prompt, defaultValue: fallback);
  }

  // ...........................................................................
  Future<int> select(
    String prompt,
    List<String> choices, {
    required String option,
  }) {
    ensureTerminal(prompt, option);
    asked = true;
    return collector._p.select(prompt: prompt, options: choices);
  }

  // ...........................................................................
  Future<String> text(
    String? given,
    String prompt, {
    required String option,
    required String? Function(String) validate,
    String? defaultValue,
  }) {
    if (given != null) return Future.value(valid(given, validate));
    ensureTerminal(prompt, option);
    asked = true;
    return collector._p.inputUntilValid(
      prompt: prompt,
      validate: validate,
      onInvalid: (reason) => collector.ggLog(cError(reason)),
      defaultValue: defaultValue,
    );
  }

  // ...........................................................................
  String valid(String value, String? Function(String) validate) {
    final reason = validate(value.trim());
    if (reason != null) throw Exception(cError(reason));
    return value.trim();
  }

  // ...........................................................................
  void ensureTerminal(String prompt, String option) => throwWhenNotATerminal(
    'the question »$prompt«',
    'pass $option',
    hasTerminal: collector._hasTerminal,
  );
}

/// Mock for [SpecCollector].
class MockSpecCollector extends Mock implements SpecCollector {}
