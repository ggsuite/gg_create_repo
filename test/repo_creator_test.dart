// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_create_repo/gg_create_repo.dart';
import 'package:gg_create_repo/src/github.dart';
import 'package:gg_create_repo/src/tools.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_process/gg_process.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Runs git for real; every other tool only records its call.
///
/// Package managers, node and gh need the network, so they are faked.
class _Processes extends GgProcessWrapper {
  final calls = <String>[];

  /// How often `git push` fails before it succeeds.
  int failingPushes = 0;

  /// What a failing push reports.
  String pushError = 'fatal: Could not resolve host: github.com';

  /// Executables that fail.
  final failing = <String>{};

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
  }) async {
    calls.add('$executable ${arguments.join(' ')}');
    if (failing.contains(executable)) {
      return ProcessResult(0, 1, '', '$executable failed');
    }
    if (executable == 'git') {
      if (arguments.first == 'push' && failingPushes > 0) {
        failingPushes--;
        return ProcessResult(0, 1, '', pushError);
      }
      return Process.run(
        'git',
        arguments,
        workingDirectory: workingDirectory,
        environment: gitIdentity,
        stdoutEncoding: utf8,
      );
    }
    if (failing.contains(executable)) {
      return ProcessResult(0, 1, '', '$executable failed');
    }
    return ProcessResult(0, 0, '', '');
  }
}

/// The identity of the commits the tests make; CI has none of its own.
const gitIdentity = {
  'GIT_AUTHOR_NAME': 'Test',
  'GIT_AUTHOR_EMAIL': 'test@example.com',
  'GIT_COMMITTER_NAME': 'Test',
  'GIT_COMMITTER_EMAIL': 'test@example.com',
};

/// GitHub without the network: a local bare repository is the remote.
class _GitHub extends GitHub {
  _GitHub(this.bare);

  final Directory bare;
  RemoteState remoteState = RemoteState.missing;
  bool remoteIsPrivate = false;
  bool mergeSettingsFail = false;
  final created = <String>[];
  final merged = <String>[];

  @override
  Future<RemoteRepo> remote(String slug) async =>
      RemoteRepo(remoteState, isPrivate: remoteIsPrivate);

  @override
  Future<void> create(RepoSpec spec) async {
    created.add(spec.slug);
    await Process.run('git', ['init', '--bare', '-b', 'main', bare.path]);
  }

  @override
  Future<String> cloneUrl(String slug) async => bare.path;

  @override
  Future<void> applyMergeSettings(String slug) async {
    if (mergeSettingsFail) throw Exception('forbidden');
    merged.add(slug);
  }
}

/// Records whether the host took over.
class _Host extends StandaloneHost {
  _Host(Directory dir) : super(outputDir: dir);
  final handedOver = <String>[];

  @override
  Future<void> afterCreate({
    required RepoSpec spec,
    required Directory directory,
    required GgLog ggLog,
  }) async => handedOver.add(spec.slug);
}

void main() {
  late Directory root;
  late Directory dir;
  late _Processes processes;
  late _GitHub gitHub;
  late _Host host;
  late List<String> messages;
  late List<List<String>> dnaCalls;
  late List<Duration> delays;

  RepoCreator creator({RunChecks? runChecks}) => RepoCreator(
    ggLog: messages.add,
    tools: Tools(processWrapper: processes),
    gitHub: gitHub,
    runDna: (args) async => dnaCalls.add(args),
    runChecks: runChecks ?? (dir, ggLog) async {},
    delay: (d) async => delays.add(d),
  );

  String git(List<String> args, {Directory? at}) => Process.runSync(
    'git',
    args,
    workingDirectory: (at ?? dir).path,
    environment: gitIdentity,
  ).stdout.toString().trim();

  setUp(() {
    root = Directory.systemTemp.createTempSync('repo_creator_');
    processes = _Processes();
    gitHub = _GitHub(Directory(p.join(root.path, 'remote.git')));
    host = _Host(root);
    messages = [];
    dnaCalls = [];
    delays = [];
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('RepoCreator', () {
    // #########################################################################
    test('runs every step and hands the pushed repository over', () async {
      final spec = RepoSpec.example(dnaLayers: []);
      dir = host.targetDir(spec);

      await creator(
        runChecks: (dir, ggLog) async =>
            File(p.join(dir.path, '.gg', 'gg.json'))
              ..parent.createSync(recursive: true)
              ..writeAsStringSync('{}'),
      ).create(
        state: CreateRepoState(spec: spec),
        directory: dir,
        host: host,
      );

      expect(File(p.join(dir.path, 'pubspec.yaml')).existsSync(), true);
      expect(File(p.join(dir.path, 'LICENSE')).existsSync(), true);
      expect(git(['status', '--porcelain']), isEmpty);
      expect(git(['log', '--format=%s']), 'Initial version');
      expect(git(['show', '--name-only', 'HEAD']), contains('.gg/gg.json'));
      expect(git(['log', '--format=%s', 'main'], at: gitHub.bare), isNotEmpty);
      expect(gitHub.created, ['ggsuite/gg_example_repo']);
      expect(gitHub.merged, ['ggsuite/gg_example_repo']);
      expect(host.handedOver, ['ggsuite/gg_example_repo']);
      expect(dnaCalls, isEmpty);
      expect(processes.calls, contains('dart pub add dev:lints dev:test'));
      expect(CreateRepoState.fileIn(dir).existsSync(), false);
      expect(messages.join('\n'), contains('main branch is not protected'));
    });

    // #########################################################################
    test('continues after the steps an earlier run did', () async {
      final spec = RepoSpec.example(dnaLayers: []);
      dir = host.targetDir(spec)..createSync(recursive: true);
      git(['init', '--initial-branch=main']);
      File(p.join(dir.path, 'README.md')).writeAsStringSync('# x\n');
      git(['add', '--all']);
      git(['commit', '-m', 'Earlier run']);
      final state = CreateRepoState(spec: spec);
      for (final step in [
        CreateStep.scaffold,
        CreateStep.install,
        CreateStep.initialCommit,
        CreateStep.dna,
        CreateStep.check,
      ]) {
        state.markDone(step, dir);
      }

      await creator().create(state: state, directory: dir, host: host);

      expect(messages.first, contains('Write the skeleton (done before)'));
      expect(processes.calls.where((c) => c.startsWith('dart')), isEmpty);
      expect(File(p.join(dir.path, 'pubspec.yaml')).existsSync(), false);
      expect(git(['log', '--format=%s']), 'Earlier run');
      expect(host.handedOver, hasLength(1));
    });

    // #########################################################################
    group('dna', () {
      test('initializes helix and adds every layer with the vars', () async {
        final spec = RepoSpec.example(
          language: RepoLanguage.typescript,
          name: 'my-lib',
          dnaLayers: ['@tssuite/dna-tssuite', 'git@github.com:x/dna_x.git'],
          vars: {'dnaCompany': 'Acme'},
        );
        dir = host.targetDir(spec);
        File(p.join(dir.path, 'dna', '_vars.json'))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('{"dnaJiraPrefix": "ACM"}');

        await creator().create(
          state: CreateRepoState(spec: spec),
          directory: dir,
          host: host,
        );

        expect(dnaCalls, [
          ['init', '--target', dir.path, '--language', 'typescript'],
          ['add', '@tssuite/dna-tssuite', '--target', dir.path],
          ['add', 'git@github.com:x/dna_x.git', '--target', dir.path],
        ]);
        final vars = jsonDecode(
          File(p.join(dir.path, 'dna', '_vars.json')).readAsStringSync(),
        );
        expect(vars, {'dnaJiraPrefix': 'ACM', 'dnaCompany': 'Acme'});
      });

      test('writes the vars when there is no vars file yet', () async {
        final spec = RepoSpec.example(vars: {'dnaCompany': 'Acme'});
        dir = host.targetDir(spec);

        await creator().create(
          state: CreateRepoState(spec: spec),
          directory: dir,
          host: host,
        );

        final file = File(p.join(dir.path, 'dna', '_vars.json'));
        expect(jsonDecode(file.readAsStringSync()), {'dnaCompany': 'Acme'});
        expect(dnaCalls.first.first, 'init');
        expect(dnaCalls.first.last, 'dart');
      });
    });

    // #########################################################################
    group('remote', () {
      test('takes over an empty repository', () async {
        gitHub.remoteState = RemoteState.empty;
        await Process.run('git', [
          'init',
          '--bare',
          '-b',
          'main',
          gitHub.bare.path,
        ]);
        final spec = RepoSpec.example(dnaLayers: []);
        dir = host.targetDir(spec);

        await creator().create(
          state: CreateRepoState(spec: spec),
          directory: dir,
          host: host,
        );

        expect(gitHub.created, isEmpty);
        expect(messages.join('\n'), contains('Using the empty repository'));
      });

      test('refuses a repository that has commits', () async {
        gitHub.remoteState = RemoteState.filled;
        final spec = RepoSpec.example(dnaLayers: []);
        dir = host.targetDir(spec);

        await expectLater(
          creator().create(
            state: CreateRepoState(spec: spec),
            directory: dir,
            host: host,
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('already has commits'),
            ),
          ),
        );
        final state = CreateRepoState.load(dir)!;
        expect(state.done, contains(CreateStep.check));
        expect(state.done, isNot(contains(CreateStep.remote)));
      });
    });

    // #########################################################################
    group('push', () {
      test('retries a failing push and replaces an origin', () async {
        processes.failingPushes = 2;
        final spec = RepoSpec.example(dnaLayers: []);
        dir = host.targetDir(spec)..createSync(recursive: true);
        git(['init', '--initial-branch=main']);
        git(['remote', 'add', 'origin', 'https://example.com/x.git']);

        await creator().create(
          state: CreateRepoState(spec: spec),
          directory: dir,
          host: host,
        );

        expect(delays, [
          const Duration(seconds: 2),
          const Duration(seconds: 4),
        ]);
        expect(git(['remote', 'get-url', 'origin']), gitHub.bare.path);
      });

      test('gives up after three failed pushes', () async {
        processes.failingPushes = 3;
        final spec = RepoSpec.example(dnaLayers: []);
        dir = host.targetDir(spec);

        await expectLater(
          creator().create(
            state: CreateRepoState(spec: spec),
            directory: dir,
            host: host,
          ),
          throwsA(isA<Exception>()),
        );
        expect(delays, hasLength(2));
      });
    });

    // #########################################################################
    group('github', () {
      test('runs the setup script of the DNA', () async {
        final spec = RepoSpec.example(dnaLayers: []);
        dir = host.targetDir(spec);
        File(p.join(dir.path, 'scripts', 'setup-github-repo.js'))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('');

        await creator().create(
          state: CreateRepoState(spec: spec),
          directory: dir,
          host: host,
        );

        final script = p.join('scripts', 'setup-github-repo.js');
        expect(
          processes.calls,
          contains('node $script ggsuite/gg_example_repo --apply'),
        );
        expect(gitHub.merged, isEmpty);
      });

      test('only warns when the setup fails', () async {
        processes.failing.add('node');
        final spec = RepoSpec.example(dnaLayers: []);
        dir = host.targetDir(spec);
        File(p.join(dir.path, 'scripts', 'setup-github-repo.js'))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('');

        await creator().create(
          state: CreateRepoState(spec: spec),
          directory: dir,
          host: host,
        );

        final log = messages.join('\n');
        expect(log, contains('setup script of the DNA failed'));
        expect(log, contains('Only the merge settings were applied'));
        expect(gitHub.merged, ['ggsuite/gg_example_repo']);
        expect(host.handedOver, hasLength(1));
      });

      test('only warns when the merge settings fail', () async {
        gitHub.mergeSettingsFail = true;
        final spec = RepoSpec.example(dnaLayers: []);
        dir = host.targetDir(spec);

        await creator().create(
          state: CreateRepoState(spec: spec),
          directory: dir,
          host: host,
        );

        expect(messages.join('\n'), contains('An admin of ggsuite'));
      });
    });

    // #########################################################################
    test('writes the state before the first step runs', () async {
      processes.failing.add('git');
      final spec = RepoSpec.example(dnaLayers: []);
      dir = host.targetDir(spec);

      await expectLater(
        creator().create(
          state: CreateRepoState(spec: spec),
          directory: dir,
          host: host,
        ),
        throwsA(isA<Exception>()),
      );

      final state = CreateRepoState.load(dir)!;
      expect(state.spec.slug, spec.slug);
      expect(state.done, isEmpty);
    });

    test('does not retry a push that failed for another reason', () async {
      processes
        ..failingPushes = 1
        ..pushError = '! [rejected] main -> main (fetch first)';
      final spec = RepoSpec.example(dnaLayers: []);
      dir = host.targetDir(spec);

      await expectLater(
        creator().create(
          state: CreateRepoState(spec: spec),
          directory: dir,
          host: host,
        ),
        throwsA(isA<Exception>()),
      );
      expect(delays, isEmpty);
    });

    test('refuses an empty repository of the other visibility', () async {
      gitHub
        ..remoteState = RemoteState.empty
        ..remoteIsPrivate = true;
      final spec = RepoSpec.example(dnaLayers: []);
      dir = host.targetDir(spec);

      await expectLater(
        creator().create(
          state: CreateRepoState(spec: spec),
          directory: dir,
          host: host,
        ),
        throwsA(
          isA<Exception>().having(
            (e) => rmConsoleColors('$e'),
            'message',
            contains('visibility of the empty'),
          ),
        ),
      );
    });

    test('has an example on the real tools', () {
      final example = RepoCreator.example();
      expect(example, isA<RepoCreator>());
      example.ggLog('logged nowhere');
    });
  });
}
