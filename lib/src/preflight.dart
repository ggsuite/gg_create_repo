// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:mocktail/mocktail.dart';

import 'dna/dna_variables.dart';
import 'dna/git_url.dart';
import 'github.dart';
import 'registry.dart';
import 'repo_host.dart';
import 'repo_language.dart';
import 'repo_spec.dart';
import 'tools.dart';

/// How serious a finding of the [Preflight] is.
enum FindingLevel {
  /// Nothing is created while there is one.
  error,

  /// Worth knowing, but no reason to stop.
  warning,

  /// What will happen, e.g. that an earlier run is continued.
  info,
}

/// One result of the [Preflight].
class Finding {
  /// Constructor
  const Finding(this.level, this.message);

  /// A realistic finding.
  factory Finding.example({FindingLevel? level, String? message}) =>
      Finding(level ?? FindingLevel.error, message ?? 'Something is wrong.');

  /// How serious it is.
  final FindingLevel level;

  /// What it is about.
  final String message;
}

/// Checks everything that can be checked before anything is created.
class Preflight {
  /// Constructor
  Preflight({
    Tools? tools,
    GitHub? gitHub,
    Registry? registry,
    this._dnaVariables = const DnaVariables(),
  }) : _tools = tools ?? const Tools(),
       _gitHub = gitHub ?? const GitHub(),
       _registry = registry ?? Registry();

  /// A preflight on the real tools; tests pass what they care about.
  factory Preflight.example({
    Tools? tools,
    GitHub? gitHub,
    Registry? registry,
  }) => Preflight(tools: tools, gitHub: gitHub, registry: registry);

  // ...........................................................................
  /// The findings for [spec]; nothing may be created while one is an error.
  /// [resumes] when an earlier run of the same repository is continued.
  Future<List<Finding>> run(
    RepoSpec spec,
    RepoHost host, {
    required bool resumes,
  }) async {
    final findings = <Finding>[];
    void error(String m) => findings.add(Finding(FindingLevel.error, m));
    void warn(String m) => findings.add(Finding(FindingLevel.warning, m));
    void info(String m) => findings.add(Finding(FindingLevel.info, m));

    await _checkGit(error);
    final ghProblem = await _gitHub.authProblem();
    if (ghProblem != null) error(ghProblem);
    await _checkTools(spec, error, warn);
    await _checkTarget(host.targetDir(spec), resumes, error, warn, info);
    if (ghProblem == null) await _checkGitHub(spec, resumes, error, info);
    if (!spec.isPrivate) await _checkRegistry(spec, error, warn);
    await _checkDna(spec, host, error, warn);
    for (final problem in await host.check(spec, resumes: resumes)) {
      error(problem);
    }
    return findings;
  }

  // ######################
  // Private
  // ######################

  final Tools _tools;
  final GitHub _gitHub;
  final Registry _registry;
  final DnaVariables _dnaVariables;

  // ...........................................................................
  Future<void> _checkGit(void Function(String) error) async {
    final version = await _tools.version('git');
    if (version == null) {
      error('git is not installed.');
      return;
    }
    final match = RegExp(r'(\d+)\.(\d+)').firstMatch(version);
    final major = int.parse(match?.group(1) ?? '0');
    final minor = int.parse(match?.group(2) ?? '0');
    if (major < 2 || (major == 2 && minor < 28)) {
      error('git $major.$minor is too old: 2.28 or newer is needed.');
    }
    for (final key in ['user.name', 'user.email']) {
      if ((await _tools.gitConfig(key)).isEmpty) {
        error('git has no $key. Run »git config --global $key <value>«.');
      }
    }
  }

  // ...........................................................................
  Future<void> _checkTools(
    RepoSpec spec,
    void Function(String) error,
    void Function(String) warn,
  ) async {
    if (spec.language == RepoLanguage.typescript) {
      if (await _tools.version('node') == null) error('node is not installed.');
      final pnpm = await _tools.majorVersion('pnpm');
      if (pnpm == null) {
        error('pnpm is not installed.');
      } else if (pnpm < 10) {
        error('pnpm $pnpm is too old: 10 or newer is needed.');
      }
      return;
    }

    final tool = spec.flutter ? 'flutter' : 'dart';
    if (await _tools.version(tool) == null) error('$tool is not installed.');
    final nodeOptional = spec.dnaLayers.isNotEmpty;
    if (nodeOptional && await _tools.version('node') == null) {
      warn(
        'node is not installed: the GitHub setup script of the DNA cannot '
        'run, only the merge settings will be applied.',
      );
    }
  }

  // ...........................................................................
  Future<void> _checkTarget(
    Directory dir,
    bool resumes,
    void Function(String) error,
    void Function(String) warn,
    void Function(String) info,
  ) async {
    if (resumes) {
      info('Continues the earlier run in ${dir.path}.');
      return;
    }
    if (dir.existsSync() && dir.listSync().isNotEmpty) {
      error('${dir.path} already exists and is not empty.');
    }
    final parent = dir.parent;
    if (!parent.existsSync()) return;
    try {
      final outer = await _tools.run('git', [
        'rev-parse',
        '--show-toplevel',
      ], directory: parent);
      warn(
        '${dir.path} is inside the git repository ${outer.trim()}: the new '
        'repository becomes a nested one.',
      );
    } on Exception {
      // Not inside a git repository: as it should be.
    }
  }

  // ...........................................................................
  Future<void> _checkGitHub(
    RepoSpec spec,
    bool resumes,
    void Function(String) error,
    void Function(String) info,
  ) async {
    final problem = await _gitHub.creationProblem(spec.org);
    if (problem != null) {
      error(problem);
      return;
    }
    final RemoteRepo remote;
    try {
      remote = await _gitHub.remote(spec.slug);
    } on Exception catch (e) {
      error('$e');
      return;
    }
    final visibility = remote.isPrivate == true ? 'private' : 'public';
    switch (remote.state) {
      case RemoteState.missing:
        break;
      case RemoteState.empty when remote.isPrivate != spec.isPrivate:
        error(
          'The empty repository ${spec.webUrl} is $visibility; it does not '
          'match the repository to create.',
        );
      case RemoteState.empty:
        info('The empty repository ${spec.webUrl} will be used.');
      case RemoteState.filled when resumes:
        info('${spec.webUrl} exists from the earlier run.');
      case RemoteState.filled:
        error('${spec.webUrl} already exists and has commits.');
    }
  }

  // ...........................................................................
  Future<void> _checkRegistry(
    RepoSpec spec,
    void Function(String) error,
    void Function(String) warn,
  ) async {
    final registry = Registry.nameOf(spec.language);
    final taken = await _registry.has(spec.packageName, spec.language);
    if (taken == true) {
      error(
        '»${spec.packageName}« is already taken on $registry. '
        'Pick another name, or create a private repository.',
      );
    } else if (taken == null) {
      warn('$registry could not be asked whether the name is free.');
    }
  }

  // ...........................................................................
  /// Sorts every layer the way helix does: a git URL, or a package of the
  /// registry of the new repository.
  Future<void> _checkDna(
    RepoSpec spec,
    RepoHost host,
    void Function(String) error,
    void Function(String) warn,
  ) async {
    for (final layer in spec.dnaLayers) {
      if (isGitUrl(layer)) {
        try {
          await _tools.run('git', [
            'ls-remote',
            '--heads',
            gitReadableUrl(layer),
          ], directory: Directory.current);
        } on Exception {
          error('The DNA layer $layer cannot be read with git.');
        }
        continue;
      }
      final npmOnly = layer.startsWith('@') || layer.contains('-');
      if (spec.language == RepoLanguage.dart && npmOnly) {
        error(
          'The DNA layer $layer is an npm package; a Dart repository '
          'needs a pub package or a git URL.',
        );
        continue;
      }
      if (host.layerDir(layer) != null) continue;
      final registry = Registry.nameOf(spec.language);
      final exists = await _registry.has(layer, spec.language);
      if (exists == false) error('The DNA layer $layer is not on $registry.');
      if (exists == null) warn('$registry could not be asked for $layer.');
    }

    final (:unresolved, :broken, missing: _) = _dnaVariables.missing(
      layers: spec.dnaLayers,
      given: spec.vars,
      host: host,
    );
    broken.forEach(
      (layer, reason) => error('The DNA config of $layer is broken: $reason'),
    );
    for (final layer in unresolved) {
      warn(
        'The required variables of $layer are only known once it is '
        'installed; helix asks for missing ones then.',
      );
    }
  }
}

/// Mock for [Preflight].
class MockPreflight extends Mock implements Preflight {}
