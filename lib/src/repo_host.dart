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
  factory DnaCandidate.example({String? label, String? ref}) => DnaCandidate(
    label: label ?? 'dna_ggsuite',
    ref: ref ?? 'git@github.com:ggsuite/dna_ggsuite.git',
  );

  /// The name shown in the menu.
  final String label;

  /// A package name or a git URL.
  final String ref;
}

/// Where a new repository lives and what happens with it after the push.
///
/// gg_create_repo knows no workspace; a host does. [StandaloneHost] is a
/// plain folder, gg's workspace host adds the ocean and the ticket.
abstract class RepoHost {
  /// Constructor
  const RepoHost();

  // ...........................................................................
  /// The organizations the user can pick from.
  Future<List<String>> knownOrgs();

  /// The DNA layers the user can pick from, besides entering one.
  List<DnaCandidate> dnaCandidates(RepoSpec spec);

  /// The organization to propose, e.g. the one of the current folder.
  String? get presetOrg;

  /// The folder the repository is created in.
  Directory targetDir(RepoSpec spec);

  /// Problems the host sees with [spec]; empty when there are none.
  Future<List<String>> check(RepoSpec spec);

  /// What [afterCreate] will do, for the plan; `null` when nothing.
  String? afterCreateDescription(RepoSpec spec);

  /// Runs after the repository was pushed, e.g. adds it to a ticket.
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

  // ...........................................................................
  @override
  Future<List<String>> knownOrgs() async => orgs;

  @override
  List<DnaCandidate> dnaCandidates(RepoSpec spec) => const [];

  @override
  String? get presetOrg => null;

  @override
  Directory targetDir(RepoSpec spec) =>
      Directory(p.join(outputDir.path, spec.name));

  @override
  Future<List<String>> check(RepoSpec spec) async => const [];

  @override
  String? afterCreateDescription(RepoSpec spec) => null;

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
