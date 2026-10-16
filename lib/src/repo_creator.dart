// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_interact/gg_interact.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_one_commit/gg_one_commit.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:helix/helix.dart' as helix;
import 'package:path/path.dart' as p;

import 'create_repo_state.dart';
import 'github.dart';
import 'repo_host.dart';
import 'repo_language.dart';
import 'repo_spec.dart';
import 'scaffold/common_files.dart';
import 'scaffold/scaffold.dart';
import 'spec_collector.dart';
import 'tools.dart';

/// Runs one `gg dna` command with [args]; the seam of the tests.
typedef RunDna = Future<void> Function(List<String> args);

/// Runs the gg checks in [directory] and records them in `.gg/gg.json`.
typedef RunChecks = Future<void> Function(Directory directory, GgLog ggLog);

/// Creates a repository step by step and continues an interrupted run.
///
/// Every step is recorded in [CreateRepoState] once it is done, so running
/// again skips what is done and repeats only the step that failed.
class RepoCreator {
  /// Constructor
  RepoCreator({
    required this.ggLog,
    Tools? tools,
    GitHub? gitHub,
    RunDna? runDna,
    RunChecks? runChecks,
    Future<void> Function(Duration)? delay,
  }) : _tools = tools ?? const Tools(),
       _gitHub = gitHub ?? const GitHub(),
       _runDna = runDna ?? _helixDna(ggLog),
       _runChecks = runChecks ?? _ggChecks,
       _delay = delay ?? Future<void>.delayed;

  // ...........................................................................
  /// Creates [spec] in [directory] and hands it over to [host].
  Future<void> create({
    required RepoSpec spec,
    required Directory directory,
    required RepoHost host,
  }) async {
    final state =
        CreateRepoState.load(directory) ?? CreateRepoState(spec: spec);
    for (final step in CreateStep.values) {
      if (state.done.contains(step)) {
        ggLog(darkGray('✓ ${step.label} (done before)'));
        continue;
      }
      await GgStatusPrinter<void>(
        message: step.label,
        ggLog: ggLog,
      ).run(() => _run(step, spec, directory, host));
      state.markDone(step, directory);
    }
    CreateRepoState.delete(directory);
  }

  /// The log function.
  final GgLog ggLog;

  // ######################
  // Private
  // ######################

  final Tools _tools;
  final GitHub _gitHub;
  final RunDna _runDna;
  final RunChecks _runChecks;
  final Future<void> Function(Duration) _delay;

  // ...........................................................................
  Future<void> _run(
    CreateStep step,
    RepoSpec spec,
    Directory dir,
    RepoHost host,
  ) => switch (step) {
    CreateStep.scaffold => _scaffold(spec, dir),
    CreateStep.install => Scaffold.forSpec(spec).install(dir, spec, _tools),
    CreateStep.initialCommit => _commitAll(dir, 'Initial version'),
    CreateStep.dna => _dna(spec, dir),
    CreateStep.check => _check(dir),
    CreateStep.remote => _remote(spec),
    CreateStep.push => _push(spec, dir),
    CreateStep.github => _github(spec, dir),
    CreateStep.host => host.afterCreate(
      spec: spec,
      directory: dir,
      ggLog: ggLog,
    ),
  };

  // ...........................................................................
  Future<void> _scaffold(RepoSpec spec, Directory dir) async {
    dir.createSync(recursive: true);
    Scaffold.forSpec(spec).write(dir, spec);
    const CommonFiles().write(dir, spec);
    if (!Directory(p.join(dir.path, '.git')).existsSync()) {
      await _git(dir, ['init', '--initial-branch=main']);
    }
  }

  // ...........................................................................
  Future<void> _dna(RepoSpec spec, Directory dir) async {
    if (spec.dnaLayers.isEmpty) return;
    _writeVars(spec, dir);
    final language = spec.language == RepoLanguage.dart ? 'dart' : 'typescript';
    await _runDna(['init', '--target', dir.path, '--language', language]);
    for (final layer in spec.dnaLayers) {
      await _runDna(['add', layer, '--target', dir.path]);
    }
  }

  // ...........................................................................
  /// Merges the variables of [spec] into `dna/_vars.json`.
  void _writeVars(RepoSpec spec, Directory dir) {
    if (spec.vars.isEmpty) return;
    final file = File(p.join(dir.path, 'dna', '_vars.json'));
    final vars = file.existsSync()
        ? jsonDecode(file.readAsStringSync()) as Map<String, dynamic>
        : <String, dynamic>{};
    vars.addAll(spec.vars);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(vars)}\n',
    );
  }

  // ...........................................................................
  Future<void> _check(Directory dir) async {
    await _commitAll(dir, 'Complete the initial version');
    await _runChecks(dir, ggLog);
    await _amendState(dir);
  }

  // ...........................................................................
  /// gg leaves its state uncommitted on main; it goes into the last commit.
  Future<void> _amendState(Directory dir) async {
    final status = await _git(dir, ['status', '--porcelain']);
    if (status.trim().isEmpty) return;
    await _git(dir, ['add', '--all']);
    await _git(dir, ['commit', '--amend', '--no-edit']);
  }

  // ...........................................................................
  /// Commits everything, unless there is nothing to commit.
  Future<void> _commitAll(Directory dir, String message) async {
    await _git(dir, ['add', '--all']);
    final status = await _git(dir, ['status', '--porcelain']);
    if (status.trim().isEmpty) return;
    await _git(dir, ['commit', '-m', message]);
  }

  // ...........................................................................
  Future<void> _remote(RepoSpec spec) async {
    final state = await _gitHub.state(spec.slug);
    switch (state) {
      case RemoteState.missing:
        await _gitHub.create(spec);
      case RemoteState.empty:
        ggLog(darkGray('Using the empty repository ${spec.webUrl}'));
      case RemoteState.filled:
        throw Exception(
          cError('${spec.webUrl} already has commits. ') +
              cAction('Pick another name or remove the repository.'),
        );
    }
  }

  // ...........................................................................
  Future<void> _push(RepoSpec spec, Directory dir) async {
    final url = await _gitHub.cloneUrl(spec.slug);
    final remotes = await _git(dir, ['remote']);
    final has = remotes.split('\n').map((r) => r.trim()).contains('origin');
    await _git(dir, ['remote', if (has) 'set-url' else 'add', 'origin', url]);
    await _retry(() => _git(dir, ['push', '-u', 'origin', 'main']));
  }

  // ...........................................................................
  Future<T> _retry<T>(Future<T> Function() task) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await task();
      } on Exception {
        if (attempt == 3) rethrow;
        await _delay(Duration(seconds: 2 * attempt));
      }
    }
  }

  // ...........................................................................
  /// The setup script of the DNA, else only the merge settings.
  Future<void> _github(RepoSpec spec, Directory dir) async {
    final script = File(p.join(dir.path, 'scripts', 'setup-github-repo.js'));
    try {
      if (script.existsSync()) {
        await _tools.run('node', [
          p.join('scripts', 'setup-github-repo.js'),
          spec.slug,
          '--apply',
        ], directory: dir);
      } else {
        await _gitHub.applyMergeSettings(spec.slug);
        ggLog(
          cWarn(
            'No DNA brought scripts/setup-github-repo.js: only the merge '
            'settings were applied, the main branch is not protected.',
          ),
        );
      }
    } on Exception catch (e) {
      ggLog(
        cWarn(
          'The GitHub repository could not be set up: $e\n'
          'An admin of ${spec.org} can apply the settings later.',
        ),
      );
    }
  }

  // ...........................................................................
  Future<String> _git(Directory dir, List<String> args) =>
      _tools.run('git', args, directory: dir);

  // ...........................................................................
  // coverage:ignore-start
  static RunDna _helixDna(GgLog ggLog) {
    final runner = CommandRunner<dynamic>('gg', 'gg')
      ..addCommand(_DnaCommand(ggLog));
    return (args) => runner.run(['dna', ...args]);
  }

  // ...........................................................................
  static Future<void> _ggChecks(Directory dir, GgLog ggLog) async {
    await CanCommit(ggLog: ggLog).exec(directory: dir, ggLog: ggLog);
    await DoCommit(ggLog: ggLog).exec(
      directory: dir,
      ggLog: ggLog,
      message: 'Add the initial version',
      force: true,
    );
  }
}

/// `gg dna` with helix' commands, asking through [GgPrompts].
class _DnaCommand extends Command<dynamic> {
  _DnaCommand(GgLog ggLog) {
    helix.Helix(
      ggLog: ggLog,
      selectPrompt: ({required prompt, required options}) =>
          _ask((prompts) => prompts.select(prompt: prompt, options: options)),
      textPrompt: ({required prompt, defaultValue}) => _ask(
        (prompts) => prompts.input(prompt: prompt, defaultValue: defaultValue),
      ),
    ).subcommands.values.forEach(addSubcommand);
  }

  @override
  final name = 'dna';

  @override
  final description = 'Manage the DNA of a repo';

  /// Lets helix fall back when gg's own prompts have no terminal.
  static Future<T> _ask<T>(Future<T> Function(GgPrompts) question) {
    final prompts = GgPrompts.current;
    if (identical(prompts, GgPrompts.defaultPrompts) &&
        !SpecCollector.stdioHasTerminal()) {
      throw const helix.PromptUnavailableException('stdin is no terminal');
    }
    return question(prompts);
  }
}

// coverage:ignore-end
