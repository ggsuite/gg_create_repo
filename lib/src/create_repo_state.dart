// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:path/path.dart' as p;

import 'json_file.dart';
import 'repo_spec.dart';

/// The steps that create a repository, in the order they run.
enum CreateStep {
  /// Writes the files of the skeleton and runs `git init`.
  scaffold('Write the skeleton'),

  /// Adds the dependencies.
  install('Install the dependencies'),

  /// Commits the skeleton, so the DNA step finds a clean tree.
  initialCommit('Commit the skeleton'),

  /// Adds the DNA layers.
  dna('Add the DNA'),

  /// Runs the gg checks and records them in `.gg/gg.json`.
  check('Run the gg checks'),

  /// Creates the repository on GitHub.
  remote('Create the GitHub repository'),

  /// Pushes `main`.
  push('Push main'),

  /// Applies the merge settings and the branch rules.
  github('Set up the GitHub repository'),

  /// Lets the host take over, e.g. adds the repository to a ticket.
  host('Integrate the repository');

  /// Constructor
  const CreateStep(this.label);

  /// What the step does, for the progress output.
  final String label;
}

/// Which steps of a run are done, kept in `.gg/create_repo_state.json`.
class CreateRepoState {
  /// Constructor
  CreateRepoState({required this.spec, Set<CreateStep>? done})
    : done = done ?? {};

  /// A realistic state; tests pass only what they care about.
  factory CreateRepoState.example({RepoSpec? spec, Set<CreateStep>? done}) =>
      CreateRepoState(spec: spec ?? RepoSpec.example(), done: done);

  // ...........................................................................
  /// The state of an earlier run in [directory], `null` if there is none.
  /// Throws a readable error when the file cannot be read.
  static CreateRepoState? load(Directory directory) {
    final file = fileIn(directory);
    if (!file.existsSync()) return null;
    try {
      final json = JsonFile(file).read();
      return CreateRepoState(
        spec: RepoSpec.fromJson(json['spec'] as Map<String, dynamic>),
        done: (json['done'] as List<dynamic>)
            .map((name) => CreateStep.values.byName(name as String))
            .toSet(),
      );
    } on Object catch (e) {
      throw Exception(
        '${file.path} cannot be read ($e). It belongs to an earlier run of '
        'gg_create_repo; move it away to start the run anew.',
      );
    }
  }

  // ...........................................................................
  /// The state file below [directory].
  static File fileIn(Directory directory) =>
      File(p.join(directory.path, '.gg', 'create_repo_state.json'));

  // ...........................................................................
  /// Writes the state to [directory].
  void save(Directory directory) => JsonFile(fileIn(directory)).write({
    'spec': spec.toJson(),
    'done': [
      for (final step in CreateStep.values)
        if (done.contains(step)) step.name,
    ],
  });

  // ...........................................................................
  /// Marks [step] as done and writes the state to [directory].
  void markDone(CreateStep step, Directory directory) {
    done.add(step);
    save(directory);
  }

  // ...........................................................................
  /// Removes the state file once every step is done.
  static void delete(Directory directory) {
    final file = fileIn(directory);
    if (file.existsSync()) file.deleteSync();
  }

  /// The spec the run was started with.
  final RepoSpec spec;

  /// The steps already done.
  final Set<CreateStep> done;
}
