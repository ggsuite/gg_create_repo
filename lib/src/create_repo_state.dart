// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'repo_spec.dart';

/// The steps that create a repository, in the order they run.
enum CreateStep {
  /// Writes the files of the skeleton and runs `git init`.
  scaffold('Write the skeleton'),

  /// Adds the dependencies.
  install('Install the dependencies'),

  /// Commits the skeleton.
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
  static CreateRepoState? load(Directory directory) {
    final file = fileIn(directory);
    if (!file.existsSync()) return null;
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return CreateRepoState(
      spec: RepoSpec.fromJson(json['spec'] as Map<String, dynamic>),
      done: (json['done'] as List<dynamic>)
          .map((name) => CreateStep.values.byName(name as String))
          .toSet(),
    );
  }

  // ...........................................................................
  /// The state file below [directory].
  static File fileIn(Directory directory) =>
      File(p.join(directory.path, '.gg', 'create_repo_state.json'));

  // ...........................................................................
  /// Marks [step] as done and writes the state to [directory].
  void markDone(CreateStep step, Directory directory) {
    done.add(step);
    final file = fileIn(directory)..parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'spec': spec.toJson(),
        'done': [
          for (final step in CreateStep.values)
            if (done.contains(step)) step.name,
        ],
      }),
    );
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
