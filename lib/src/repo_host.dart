// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as p;

import 'repo_spec.dart';

/// A DNA layer the user can pick: a label and what `gg dna add` gets.
class DnaCandidate {
  /// Constructor
  const DnaCandidate({required this.label, required this.ref});

  /// A realistic candidate.
  factory DnaCandidate.example({String? label, String? ref}) =>
      DnaCandidate(label: label ?? 'dna_ggsuite', ref: ref ?? 'dna_ggsuite');

  /// The name shown in the menu.
  final String label;

  /// A package name or a git URL.
  final String ref;
}

/// Where a new repository lives and what happens with it after the push.
/// gg_create_repo knows no workspace; a host does.
abstract class RepoHost {
  /// Constructor
  const RepoHost();

  // ...........................................................................
  /// The organizations the user can pick from.
  Future<List<String>> knownOrgs();

  // ...........................................................................
  /// The DNA layers the user can pick from, besides entering one.
  List<DnaCandidate> dnaCandidates(RepoSpec spec);

  // ...........................................................................
  /// The local folder of the DNA layer [layer], `null` if there is none.
  Directory? layerDir(String layer);

  // ...........................................................................
  /// The organization to propose, e.g. the one of the current folder.
  String? get presetOrg;

  // ...........................................................................
  /// The folder the repository is created in.
  Directory targetDir(RepoSpec spec);

  // ...........................................................................
  /// Problems the host sees with [spec]; [resumes] when an earlier run of
  /// the same repository is continued.
  Future<List<String>> check(RepoSpec spec, {required bool resumes});

  // ...........................................................................
  /// What [afterCreate] will do, for the plan; `null` when nothing.
  String? afterCreateDescription(RepoSpec spec);

  // ...........................................................................
  /// Runs after the push, e.g. adds the repository to a ticket. Must be
  /// idempotent: a failed run repeats it.
  Future<void> afterCreate({
    required RepoSpec spec,
    required Directory directory,
    required GgLog ggLog,
  });
}

/// Creates the repository in a folder below [outputDir].
class StandaloneHost extends RepoHost {
  /// Constructor
  const StandaloneHost({required this.outputDir, this.orgs = const []});

  /// A host in the system temp folder; tests pass what they care about.
  factory StandaloneHost.example({Directory? outputDir, List<String>? orgs}) =>
      StandaloneHost(
        outputDir: outputDir ?? Directory.systemTemp,
        orgs: orgs ?? const ['ggsuite'],
      );

  // ...........................................................................
  @override
  Future<List<String>> knownOrgs() async => orgs;

  // ...........................................................................
  @override
  List<DnaCandidate> dnaCandidates(RepoSpec spec) => const [];

  // ...........................................................................
  @override
  Directory? layerDir(String layer) => null;

  // ...........................................................................
  @override
  String? get presetOrg => null;

  // ...........................................................................
  @override
  Directory targetDir(RepoSpec spec) =>
      Directory(p.join(outputDir.path, spec.name));

  // ...........................................................................
  @override
  Future<List<String>> check(RepoSpec spec, {required bool resumes}) async =>
      const [];

  // ...........................................................................
  @override
  String? afterCreateDescription(RepoSpec spec) => null;

  // ...........................................................................
  @override
  Future<void> afterCreate({
    required RepoSpec spec,
    required Directory directory,
    required GgLog ggLog,
  }) async {}

  /// The folder the repository folder is created in.
  final Directory outputDir;

  /// The organizations offered in the menu.
  final List<String> orgs;
}
