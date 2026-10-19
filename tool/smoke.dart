// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_create_repo/gg_create_repo.dart';
import 'package:gg_create_repo/src/github.dart';

/// Creates a real repository end to end with a local bare repository as
/// GitHub. Usage: `dart run tool/smoke.dart folder name dart|ts`
/// `[dna,...|-] [--cli]`
Future<void> main(List<String> args) async {
  final root = Directory(args[0])..createSync(recursive: true);
  final layers = args.length > 3 && args[3] != '-'
      ? args[3].split(',')
      : <String>[];
  final spec = RepoSpec(
    name: args[1],
    language: RepoLanguage.parse(args[2]),
    org: 'ggsuite',
    description:
        'A throwaway repository to try out gg_create_repo end to end, '
        'pushed to a local bare repository.',
    dnaLayers: layers,
    cli: args.contains('--cli'),
  );
  final host = StandaloneHost(outputDir: root);
  final bare = Directory('${root.path}/${spec.name}.git');
  await RepoCreator(ggLog: print, gitHub: _LocalGitHub(bare)).create(
    state: CreateRepoState(spec: spec),
    directory: host.targetDir(spec),
    host: host,
  );
}

/// GitHub replaced by the bare repository [bare].
class _LocalGitHub extends GitHub {
  _LocalGitHub(this.bare);

  final Directory bare;

  @override
  Future<RemoteRepo> remote(String slug) async =>
      const RemoteRepo(RemoteState.missing);

  @override
  Future<void> create(RepoSpec spec) async {
    await Process.run('git', ['init', '--bare', '-b', 'main', bare.path]);
  }

  @override
  Future<String> cloneUrl(String slug) async => bare.path;

  @override
  Future<void> applyMergeSettings(String slug) async {}
}
