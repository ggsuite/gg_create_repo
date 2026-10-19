// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_one_commit/gg_one_commit.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;

import 'create_repo_state.dart';
import 'dna/gg_dna.dart';
import 'github.dart';
import 'json_file.dart';
import 'repo_host.dart';
import 'repo_language.dart';
import 'repo_spec.dart';
import 'scaffold/common_files.dart';
import 'scaffold/scaffold.dart';
import 'tools.dart';

/// Runs the gg checks in [directory] and records them in `.gg/gg.json`.
typedef RunChecks = Future<void> Function(Directory directory, GgLog ggLog);

/// Creates a repository step by step. Every step is recorded once it is
/// done, so running again skips it and repeats only the step that failed.
class RepoCreator {
  /// Constructor
  RepoCreator({
    required this.ggLog,
    Tools? tools,
    GitHub? gitHub,
    this._runDna,
    RunChecks? runChecks,
    Future<void> Function(Duration)? delay,
  }) : _tools = tools ?? const Tools(),
       _gitHub = gitHub ?? const GitHub(),
       _runChecks = runChecks ?? _ggChecks,
       _delay = delay ?? Future<void>.delayed;

  /// A creator on the real tools; tests pass what they care about.
  factory RepoCreator.example({
    GgLog? ggLog,
    Tools? tools,
    GitHub? gitHub,
    RunDna? runDna,
    RunChecks? runChecks,
    Future<void> Function(Duration)? delay,
  }) => RepoCreator(
    ggLog: ggLog ?? (_) {},
    tools: tools,
    gitHub: gitHub,
    runDna: runDna,
    runChecks: runChecks,
    delay: delay,
  );

  // ...........................................................................
  /// Runs the steps of [state] not done yet in [directory].
  Future<void> create({
    required CreateRepoState state,
    required Directory directory,
    required RepoHost host,
  }) async {
    directory.createSync(recursive: true);
    state.save(directory);
    for (final step in CreateStep.values) {
      if (state.done.contains(step)) {
        ggLog(darkGray('✓ ${step.label} (done before)'));
        continue;
      }
      await GgStatusPrinter<void>(
        message: step.label,
        ggLog: ggLog,
      ).run(() => _run(step, state.spec, directory, host));
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
  final RunDna? _runDna;
  final RunChecks _runChecks;
  final Future<void> Function(Duration) _delay;

  /// helix' commands are built on the first use, not with every gg call.
  late final RunDna _dnaRunner = _runDna ?? helixDnaRunner(ggLog);

  static final _networkError = RegExp(
    'Could not resolve host|Connection (was )?(refused|reset|closed|timed '
    'out)|timed out|Failed to connect|early EOF|returned error: 5[0-9][0-9]|'
    'not closed cleanly',
    caseSensitive: false,
  );

  static final _layers = RegExp(r'"layers"\s*:\s*\[[^\]]*\]');

  // ...........................................................................
  Future<void> _run(
    CreateStep step,
    RepoSpec spec,
    Directory dir,
    RepoHost host,
  ) => switch (step) {
    CreateStep.scaffold => _scaffold(spec, dir),
    CreateStep.install => _install(spec, dir),
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
  Future<Scaffold> _scaffoldFor(RepoSpec spec) async => Scaffold.forSpec(
    spec,
    dartSdk: spec.language == RepoLanguage.dart
        ? await _tools.dartSdkVersion(flutter: spec.flutter)
        : null,
    nodeMajor: spec.language == RepoLanguage.typescript
        ? await _tools.majorVersion('node')
        : null,
  );

  // ...........................................................................
  Future<void> _scaffold(RepoSpec spec, Directory dir) async {
    (await _scaffoldFor(spec)).write(dir, spec);
    const CommonFiles().write(dir, spec);
    if (!Directory(p.join(dir.path, '.git')).existsSync()) {
      await _git(dir, ['init', '--initial-branch=main']);
    }
  }

  // ...........................................................................
  Future<void> _install(RepoSpec spec, Directory dir) async =>
      (await _scaffoldFor(spec)).install(dir, spec, _tools);

  // ...........................................................................
  Future<void> _dna(RepoSpec spec, Directory dir) async {
    if (spec.dnaLayers.isEmpty) return;
    if (spec.vars.isNotEmpty) {
      JsonFile(File(p.join(dir.path, 'dna', '_vars.json')))
          .edit((vars) => vars.addAll(spec.vars));
    }
    final language = spec.language == RepoLanguage.dart ? 'dart' : 'typescript';
    await _dnaRunner([
      'init',
      '--target',
      dir.path,
      '--language',
      language,
      '--quiet',
    ]);
    _withoutProposedLayers(dir);
    for (final layer in spec.dnaLayers) {
      await _dnaRunner(['add', layer, '--target', dir.path]);
    }
  }

  // ...........................................................................
  /// `gg dna init` proposes the DNA packages the skeleton depends on, like
  /// gg_args; only the chosen layers are applied, in their order.
  void _withoutProposedLayers(Directory dir) {
    final file = File(p.join(dir.path, 'dna', '_dna.json'));
    if (!file.existsSync()) return;
    file.writeAsStringSync(
      file.readAsStringSync().replaceFirst(_layers, '"layers": []'),
    );
  }

  // ...........................................................................
  /// gg leaves its state uncommitted on main; it goes into the last commit.
  Future<void> _check(Directory dir) async {
    await _commitAll(dir, 'Complete the initial version');
    await _runChecks(dir, ggLog);
    if ((await _git(dir, ['status', '--porcelain'])).trim().isEmpty) return;
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
    final remote = await _gitHub.remote(spec.slug);
    switch (remote.state) {
      case RemoteState.missing:
        await _gitHub.create(spec);
      case RemoteState.empty when remote.isPrivate != spec.isPrivate:
        throw Exception(
          cError('The visibility of the empty ${spec.webUrl} differs. ') +
              cAction('Change it on GitHub or pick another name.'),
        );
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
  /// Retries [task] twice when it fails with a network error.
  Future<T> _retry<T>(Future<T> Function() task) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await task();
      } on Exception catch (e) {
        if (attempt == 3 || !_networkError.hasMatch('$e')) rethrow;
        await _delay(Duration(seconds: 2 * attempt));
      }
    }
  }

  // ...........................................................................
  /// The setup script of the DNA; the merge settings when there is none or
  /// it cannot run.
  Future<void> _github(RepoSpec spec, Directory dir) async {
    final script = p.join('scripts', 'setup-github-repo.js');
    if (File(p.join(dir.path, script)).existsSync()) {
      try {
        await _tools.run('node', [
          script,
          spec.slug,
          '--apply',
        ], directory: dir);
        return;
      } on Exception catch (e) {
        ggLog(cWarn('The setup script of the DNA failed: $e'));
      }
    }
    try {
      await _gitHub.applyMergeSettings(spec.slug);
      ggLog(
        cWarn(
          'Only the merge settings were applied: the main branch is not '
          'protected.',
        ),
      );
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
  static Future<void> _ggChecks(Directory dir, GgLog ggLog) async {
    await CanCommit(ggLog: ggLog).exec(directory: dir, ggLog: ggLog);
    await DoCommit(ggLog: ggLog).exec(
      directory: dir,
      ggLog: ggLog,
      message: 'Add the initial version',
      force: true,
    );
  }

  // coverage:ignore-end
}

/// Mock for [RepoCreator].
class MockRepoCreator extends Mock implements RepoCreator {}
