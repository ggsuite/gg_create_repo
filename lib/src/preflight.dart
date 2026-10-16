// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'create_repo_state.dart';
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
  Preflight({Tools? tools, GitHub? gitHub, Registry? registry})
    : _tools = tools ?? const Tools(),
      _gitHub = gitHub ?? const GitHub(),
      _registry = registry ?? Registry();

  // ...........................................................................
  /// The findings for [spec]; nothing may be created while one is an error.
  Future<List<Finding>> run(RepoSpec spec, RepoHost host) async {
    final findings = <Finding>[];
    void error(String m) => findings.add(Finding(FindingLevel.error, m));
    void warn(String m) => findings.add(Finding(FindingLevel.warning, m));
    void info(String m) => findings.add(Finding(FindingLevel.info, m));

    await _checkGit(error);
    await _checkTools(spec, error, warn);
    final resumes = _checkTarget(spec, host.targetDir(spec), error, info);
    await _checkGitHub(spec, resumes, error, info);
    if (!spec.isPrivate) await _checkRegistry(spec, error, warn);
    await _checkDna(spec, error, warn);
    for (final problem in await host.check(spec)) {
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
    final problem = await _gitHub.authProblem();
    if (problem != null) error(problem);

    final needed = switch (spec.language) {
      RepoLanguage.dart => [spec.flutter ? 'flutter' : 'dart'],
      RepoLanguage.typescript => ['node', 'pnpm'],
    };
    for (final tool in needed) {
      if (await _tools.version(tool) == null) error('$tool is not installed.');
    }

    final usesNode = spec.language == RepoLanguage.dart;
    if (usesNode && spec.dnaLayers.isNotEmpty) {
      if (await _tools.version('node') == null) {
        warn(
          'node is not installed: the GitHub setup script of the DNA cannot '
          'run, only the merge settings will be applied.',
        );
      }
    }
  }

  // ...........................................................................
  /// Whether [dir] holds an earlier run of the same repository.
  bool _checkTarget(
    RepoSpec spec,
    Directory dir,
    void Function(String) error,
    void Function(String) info,
  ) {
    if (!dir.existsSync()) return false;
    final state = CreateRepoState.load(dir);
    if (state != null && state.spec.slug == spec.slug) {
      info('Continues the earlier run in ${dir.path}.');
      return true;
    }
    if (dir.listSync().isNotEmpty) {
      error('${dir.path} already exists and is not empty.');
    }
    return false;
  }

  // ...........................................................................
  Future<void> _checkGitHub(
    RepoSpec spec,
    bool resumes,
    void Function(String) error,
    void Function(String) info,
  ) async {
    if (await _gitHub.ownerType(spec.org) == null) {
      error('GitHub knows no organization or user »${spec.org}«.');
      return;
    }
    final RemoteState state;
    try {
      state = await _gitHub.state(spec.slug);
    } on Exception catch (e) {
      error('$e');
      return;
    }
    switch (state) {
      case RemoteState.missing:
        break;
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
  Future<void> _checkDna(
    RepoSpec spec,
    void Function(String) error,
    void Function(String) warn,
  ) async {
    for (final layer in spec.dnaLayers) {
      if (_isGitUrl(layer)) {
        try {
          await _tools.run('git', [
            'ls-remote',
            '--heads',
            layer,
          ], directory: Directory.systemTemp);
        } on Exception {
          error('The DNA layer $layer cannot be read with git.');
        }
        continue;
      }
      final language = layer.startsWith('@')
          ? RepoLanguage.typescript
          : RepoLanguage.dart;
      final registry = Registry.nameOf(language);
      final exists = await _registry.has(layer, language);
      if (exists == false) error('The DNA layer $layer is not on $registry.');
      if (exists == null) warn('$registry could not be asked for $layer.');
    }
  }

  // ...........................................................................
  static bool _isGitUrl(String layer) =>
      layer.contains('://') || layer.startsWith('git@');
}
