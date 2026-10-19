// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

/// Creates new Dart and TypeScript repositories for the gg suite.
library;

export 'src/commands/create_repo.dart' show CreateRepo, HostFactory;
export 'src/create_repo_state.dart' show CreateRepoState, CreateStep;
export 'src/dna/gg_dna.dart' show GgDna, helixSelectPrompt, helixTextPrompt;
export 'src/preflight.dart'
    show Finding, FindingLevel, MockPreflight, Preflight;
export 'src/repo_creator.dart'
    show MockRepoCreator, RepoCreator, RunChecks, RunDna;
export 'src/repo_host.dart' show DnaCandidate, RepoHost, StandaloneHost;
export 'src/repo_language.dart' show RepoLanguage;
export 'src/repo_options.dart' show RepoOptions;
export 'src/repo_spec.dart' show RepoSpec;
export 'src/spec_collector.dart'
    show CollectedSpec, MockSpecCollector, SpecCollector;
