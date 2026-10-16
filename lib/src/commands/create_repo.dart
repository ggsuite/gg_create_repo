// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_interact/gg_interact.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as p;

import '../create_repo_state.dart';
import '../preflight.dart';
import '../repo_creator.dart';
import '../repo_host.dart';
import '../repo_language.dart';
import '../repo_options.dart';
import '../repo_spec.dart';
import '../spec_collector.dart';

/// Builds the host from the parsed options.
typedef HostFactory = RepoHost Function(ArgResults args);

/// Creates a new Dart or TypeScript repository, ready for the gg cycle.
class CreateRepo extends Command<dynamic> {
  /// Constructor
  CreateRepo({
    required this.ggLog,
    this.name = 'create-repo',
    this.description =
        'Creates a new Dart or TypeScript repository with DNA, GitHub '
        'setup and a first commit that passes the gg checks.',
    HostFactory? host,
    SpecCollector? collector,
    Preflight? preflight,
    RepoCreator? creator,
    this._prompts,
  }) : _host = host ?? standaloneHost,
       _collector = collector ?? SpecCollector(ggLog: ggLog),
       _preflight = preflight ?? Preflight(),
       _creator = creator ?? RepoCreator(ggLog: ggLog) {
    _addOptions();
  }

  // ...........................................................................
  @override
  final String name;

  @override
  final String description;

  @override
  Future<void> run() async {
    final args = argResults!;
    final host = _host(args);
    var spec = await _collector.collect(_optionsFrom(), host);
    final directory = host.targetDir(spec);
    spec = CreateRepoState.load(directory)?.spec ?? spec;

    _logPlan(spec, directory, host);
    final findings = await _preflight.run(spec, host);
    _logFindings(findings);
    if (findings.any((f) => f.level == FindingLevel.error)) {
      throw Exception(cError('Nothing was created.'));
    }
    if (args['dry-run'] as bool) {
      ggLog(cAction('Dry run: nothing was created.'));
      return;
    }
    if (_collector.asked && !(args['yes'] as bool)) {
      final ok = await (_prompts ?? GgPrompts.current).confirm(
        prompt: 'Create ${spec.slug}?',
      );
      if (!ok) {
        ggLog(cAction('Nothing was created.'));
        return;
      }
    }

    await _creator.create(spec: spec, directory: directory, host: host);
    ggLog(cSuccess('✓ Created ${spec.webUrl} in ${directory.path}'));
  }

  /// The log function.
  final GgLog ggLog;

  /// A [StandaloneHost] in the folder given with `--output`.
  static RepoHost standaloneHost(ArgResults args) => StandaloneHost(
    outputDir: Directory(p.normalize(p.absolute(args['output'] as String))),
  );

  // ######################
  // Private
  // ######################

  final HostFactory _host;
  final SpecCollector _collector;
  final Preflight _preflight;
  final RepoCreator _creator;
  final GgPrompts? _prompts;

  // ...........................................................................
  void _addOptions() {
    argParser
      ..addOption('name', abbr: 'n', help: 'Name of repository and package.')
      ..addOption(
        'language',
        abbr: 'l',
        help: 'The language of the package.',
        allowed: ['dart', 'ts'],
      )
      ..addOption('org', abbr: 'g', help: 'The GitHub organization or user.')
      ..addOption(
        'description',
        abbr: 'd',
        help: 'One line; Dart needs 60 to 180 characters.',
      )
      ..addOption('scope', help: 'TypeScript: the npm scope, default: org.')
      ..addFlag(
        'private',
        defaultsTo: null,
        help: 'Private repository, never published.',
      )
      ..addFlag('cli', defaultsTo: null, help: 'Dart: add a CLI.')
      ..addFlag('example', defaultsTo: null, help: 'Dart: add an example.')
      ..addFlag('flutter', defaultsTo: null, help: 'Dart: a Flutter package.')
      ..addMultiOption(
        'dna',
        help: 'A DNA layer: package name or git URL. Repeat for more.',
      )
      ..addFlag(
        'without-dna',
        negatable: false,
        help: 'Create the repository without any DNA.',
      )
      ..addMultiOption(
        'var',
        help: 'A DNA variable as key=value. Repeat for more.',
      )
      ..addOption(
        'output',
        abbr: 'o',
        help: 'The folder the repository folder is created in.',
        defaultsTo: '.',
      )
      ..addFlag(
        'interactive',
        abbr: 'i',
        negatable: false,
        help: 'Ask every question, not only the missing ones.',
      )
      ..addFlag(
        'yes',
        abbr: 'y',
        negatable: false,
        help: 'Do not ask before creating.',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Only show the plan and the checks.',
      );
  }

  // ...........................................................................
  RepoOptions _optionsFrom() {
    final a = argResults!;
    return RepoOptions(
      name: a['name'] as String?,
      language: a['language'] as String?,
      org: a['org'] as String?,
      description: a['description'] as String?,
      npmScope: a['scope'] as String?,
      isPrivate: a['private'] as bool?,
      cli: a['cli'] as bool?,
      example: a['example'] as bool?,
      flutter: a['flutter'] as bool?,
      dnaLayers: a['dna'] as List<String>,
      withoutDna: a['without-dna'] as bool,
      vars: a['var'] as List<String>,
      interactive: a['interactive'] as bool,
    );
  }

  // ...........................................................................
  void _logPlan(RepoSpec spec, Directory directory, RepoHost host) {
    final isDart = spec.language == RepoLanguage.dart;
    final dna = spec.dnaLayers.isEmpty ? 'none' : spec.dnaLayers.join(', ');
    final kind = [
      spec.language.label,
      if (spec.flutter) 'Flutter',
      if (spec.cli) 'CLI',
      if (isDart && spec.example) 'example',
      spec.isPrivate ? 'private' : 'public',
    ].join(', ');
    final then = host.afterCreateDescription(spec);
    ggLog(
      '${cAction('Repository: ')}${cCmd(spec.slug)} ($kind)\n'
      '${cAction('Package:    ')}${spec.packageName} 0.0.1\n'
      '${cAction('Folder:     ')}${directory.path}\n'
      '${cAction('DNA:        ')}$dna'
      '${then == null ? '' : '\n${cAction('Then:       ')}$then'}',
    );
  }

  // ...........................................................................
  void _logFindings(List<Finding> findings) {
    for (final f in findings) {
      ggLog(switch (f.level) {
        FindingLevel.error => cError('✗ ${f.message}'),
        FindingLevel.warning => cWarn('! ${f.message}'),
        FindingLevel.info => darkGray('· ${f.message}'),
      });
    }
  }
}
