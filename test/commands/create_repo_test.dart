// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_create_repo/gg_create_repo.dart';
import 'package:gg_create_repo/src/github.dart';
import 'package:gg_create_repo/src/registry.dart';
import 'package:gg_create_repo/src/tools.dart';
import 'package:gg_interact/gg_interact.dart';
import 'package:gg_process/gg_process.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/git_identity.dart';

/// Answers every confirmation with [yes].
class _Prompts extends GgPrompts {
  _Prompts(this.yes);

  final bool yes;
  var confirmations = 0;

  @override
  Future<int> select({
    required String prompt,
    required List<String> options,
    int initialIndex = 0,
  }) async {
    confirmations++;
    return yes ? 0 : 1;
  }

  @override
  Future<String> input({
    required String prompt,
    String? defaultValue,
    String? initialText,
    bool asMessageEditor = false,
  }) async => '';
}

/// A host whose plan names a next step.
class _TicketHost extends StandaloneHost {
  _TicketHost(Directory dir) : super(outputDir: dir);

  @override
  String? afterCreateDescription(RepoSpec spec) => 'add it to the ticket t';
}

// .............................................................................
/// Runs git for real and answers gh for an admin of ggsuite; package
/// managers need the network, so they only succeed.
class _Tools extends GgProcessWrapper {
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
    if (executable == 'git') {
      return Process.run(
        'git',
        arguments,
        workingDirectory: workingDirectory,
        environment: gitIdentity,
        stdoutEncoding: utf8,
      );
    }
    final call = arguments.join(' ');
    final out = switch (call) {
      '--version' when executable == 'dart' => 'Dart SDK version: 3.9.2',
      '--version' => 'version 2.60.0',
      _ when call.contains('users/ggsuite') => 'HTTP/2 200\n\nOrganization',
      _ when call.contains('memberships') => 'HTTP/2 200\n\nactive\tadmin',
      _ => '',
    };
    return ProcessResult(0, 0, out, '');
  }
}

// .............................................................................
/// GitHub as a local bare repository; the push fails while [unreachable].
class _LocalGitHub extends GitHub {
  _LocalGitHub(this.bare) : super(processWrapper: _Tools());

  final Directory bare;
  var unreachable = true;
  var _isPrivate = false;

  @override
  Future<RemoteRepo> remote(String slug) async {
    if (!bare.existsSync()) return const RemoteRepo(RemoteState.missing);
    final heads = Process.runSync('git', ['-C', bare.path, 'branch']);
    final empty = '${heads.stdout}'.trim().isEmpty;
    return RemoteRepo(
      empty ? RemoteState.empty : RemoteState.filled,
      isPrivate: _isPrivate,
    );
  }

  @override
  Future<void> create(RepoSpec spec) async {
    _isPrivate = spec.isPrivate;
    Process.runSync('git', ['init', '--bare', '-b', 'main', bare.path]);
  }

  @override
  Future<String> cloneUrl(String slug) async =>
      unreachable ? p.join(bare.path, 'missing') : bare.path;

  @override
  Future<void> applyMergeSettings(String slug) async {}
}

void main() {
  late Directory root;
  late List<String> messages;
  late MockSpecCollector collector;
  late MockPreflight preflight;
  late MockRepoCreator creator;

  setUpAll(() {
    registerFallbackValue(const RepoOptions());
    registerFallbackValue(StandaloneHost.example());
    registerFallbackValue(RepoSpec.example());
    registerFallbackValue(CreateRepoState.example());
    registerFallbackValue(Directory.systemTemp);
  });

  /// The collector answers [spec], the preflight [findings].
  void answer({
    RepoSpec? spec,
    bool asked = false,
    List<Finding> findings = const [],
  }) {
    when(
      () => collector.collect(any(), any(), earlier: any(named: 'earlier')),
    ).thenAnswer((_) async => (spec: spec ?? RepoSpec.example(), asked: asked));
    when(() => preflight.run(any(), any(), resumes: any(named: 'resumes')))
        .thenAnswer((_) async => findings);
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('create_repo_command_');
    messages = [];
    collector = MockSpecCollector();
    preflight = MockPreflight();
    creator = MockRepoCreator();
    when(
      () => creator.create(
        state: any(named: 'state'),
        directory: any(named: 'directory'),
        host: any(named: 'host'),
      ),
    ).thenAnswer((_) async {});
    answer();
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<void> run(List<String> args, {GgPrompts? prompts, HostFactory? host}) {
    final command = CreateRepo.example(
      ggLog: (m) => messages.add(rmConsoleColors(m)),
      host: host,
      collector: collector,
      preflight: preflight,
      creator: creator,
      prompts: prompts,
    );
    return (CommandRunner<dynamic>(
      'test',
      'test',
    )..addCommand(command)).run(['create-repo', '-o', root.path, ...args]);
  }

  String target([String name = 'gg_example_repo']) =>
      p.join(p.normalize(p.absolute(root.path)), name);

  ({CreateRepoState state, Directory directory}) created() {
    final captured = verify(
      () => creator.create(
        state: captureAny(named: 'state'),
        directory: captureAny(named: 'directory'),
        host: any(named: 'host'),
      ),
    ).captured;
    return (
      state: captured[0] as CreateRepoState,
      directory: captured[1] as Directory,
    );
  }

  void expectNothingCreated() => verifyNever(
    () => creator.create(
      state: any(named: 'state'),
      directory: any(named: 'directory'),
      host: any(named: 'host'),
    ),
  );

  RepoOptions collectedOptions() =>
      verify(
            () => collector.collect(
              captureAny(),
              any(),
              earlier: any(named: 'earlier'),
            ),
          ).captured.single
          as RepoOptions;

  Matcher throwsMentioning(List<String> parts) => throwsA(
    isA<Exception>().having(
      (e) => rmConsoleColors('$e'),
      'message',
      allOf([for (final part in parts) contains(part)]),
    ),
  );

  group('CreateRepo', () {
    // #########################################################################
    test('passes every option on to the collector', () async {
      await run([
        ...['-n', 'x', '-l', 'ts', '-g', 'org', '-d', 'desc'],
        ...['--scope', 's', '--private', '--no-cli', '--example'],
        ...['--flutter', '--dna', 'a', '--dna', 'b', '--without-dna'],
        ...['--var', 'k=v', '-i'],
      ]);

      final o = collectedOptions();
      expect(
        [o.name, o.language, o.org, o.description, o.npmScope],
        ['x', 'ts', 'org', 'desc', 's'],
      );
      expect(
        [o.isPrivate, o.cli, o.example, o.flutter],
        [true, false, true, true],
      );
      expect(o.dnaLayers, ['a', 'b']);
      expect(o.withoutDna, true);
      expect(o.vars, ['k=v']);
      expect(o.interactive, true);
    });

    test('leaves unset flags null', () async {
      await run([]);
      final o = collectedOptions();
      expect([o.isPrivate, o.cli, o.example, o.flutter], everyElement(null));
    });

    // #########################################################################
    test('creates the repository in the output folder', () async {
      await run([]);

      final call = created();
      expect(call.state.spec.slug, 'ggsuite/gg_example_repo');
      expect(call.state.done, isEmpty);
      expect(call.directory.path, target());
      final log = messages.join('\n');
      expect(log, contains('gg_example_repo 0.0.1'));
      expect(log, contains('DNA:        dna_ggsuite'));
      expect(log, contains('Dart, example, public'));
      expect(log, contains('Created https://github.com/ggsuite/'));
    });

    test('shows the kind of package and what follows', () async {
      answer(
        spec: RepoSpec.example(
          flutter: true,
          cli: true,
          isPrivate: true,
          dnaLayers: [],
        ),
      );
      await run([], host: (args) => _TicketHost(root));

      final log = messages.join('\n');
      expect(log, contains('Dart, Flutter, CLI, example, private'));
      expect(log, contains('DNA:        none'));
      expect(log, contains('Then:       add it to the ticket t'));
    });

    // #########################################################################
    group('with an earlier run in the folder', () {
      void earlierRun(RepoSpec spec, {Set<CreateStep>? done}) {
        Directory(target()).createSync();
        CreateRepoState(
          spec: spec,
          done: done ?? {CreateStep.scaffold},
        ).save(Directory(target()));
      }

      test('hands the collector the earlier run of a folder', () async {
        earlierRun(RepoSpec.example(description: 'x' * 70));
        await run([]);

        final find =
            verify(
                  () => collector.collect(
                    any(),
                    any(),
                    earlier: captureAny(named: 'earlier'),
                  ),
                ).captured.single
                as RepoSpec? Function(RepoSpec);
        expect(find(RepoSpec.example())?.description, 'x' * 70);
        expect(find(RepoSpec.example(name: 'gg_other')), isNull);
      });

      test('refuses new variables once the DNA is added', () async {
        earlierRun(
          RepoSpec.example(vars: {'dnaA': '1'}),
          done: {CreateStep.scaffold, CreateStep.dna},
        );
        answer(spec: RepoSpec.example(vars: {'dnaA': '1', 'dnaB': '2'}));

        await expectLater(
          run([]),
          throwsMentioning(['without dnaB', 'dna/_vars.json']),
        );
        expectNothingCreated();
      });

      test('keeps the variables of the DNA added already', () async {
        earlierRun(
          RepoSpec.example(vars: {'dnaA': '1'}),
          done: {CreateStep.scaffold, CreateStep.dna},
        );
        answer(spec: RepoSpec.example(vars: {'dnaA': '1'}));

        await run([]);
        expect(created().state.spec.vars, {'dnaA': '1'});
      });

      test('continues it and takes the variables given now', () async {
        earlierRun(RepoSpec.example(vars: {'a': '1', 'b': '2'}));
        answer(spec: RepoSpec.example(vars: {'b': '3'}));

        await run([]);

        final state = created().state;
        expect(state.done, {CreateStep.scaffold});
        expect(state.spec.vars, {'a': '1', 'b': '3'});
        verify(() => preflight.run(any(), any(), resumes: true)).called(1);
      });

      test('refuses options that contradict it', () async {
        earlierRun(RepoSpec.example(description: 'x' * 70));
        answer(
          spec: RepoSpec.example(
            description: 'y' * 70,
            isPrivate: true,
            cli: true,
            dnaLayers: ['other'],
          ),
        );

        await expectLater(
          run(['-d', 'y' * 70, '--private', '--cli', '--dna', 'other']),
          throwsMentioning(['description', 'private', 'cli', 'dna']),
        );
      });

      test('compares every option it was started with', () async {
        earlierRun(
          RepoSpec.example(language: RepoLanguage.typescript, npmScope: 'a'),
        );
        answer(
          spec: RepoSpec.example(
            npmScope: 'b',
            example: false,
            flutter: true,
            dnaLayers: [],
          ),
        );

        await expectLater(
          run([
            ...['-l', 'dart', '--scope', 'b', '--no-example', '--flutter'],
            '--without-dna',
          ]),
          throwsMentioning(['language', 'scope', 'example', 'flutter', 'dna']),
        );
      });

      test('ignores options that match it', () async {
        earlierRun(RepoSpec.example());
        await run(['-d', RepoSpec.example().description, '--no-cli']);
        expect(created().state.spec.slug, 'ggsuite/gg_example_repo');
      });

      test('refuses an earlier run of another repository', () async {
        earlierRun(RepoSpec.example(org: 'other'));
        await expectLater(run([]), throwsMentioning(['other/gg_example_repo']));
      });
    });

    // #########################################################################
    test('logs the findings and stops at an error', () async {
      answer(
        findings: [
          const Finding(FindingLevel.warning, 'careful'),
          const Finding(FindingLevel.info, 'fyi'),
          const Finding(FindingLevel.error, 'broken'),
        ],
      );

      await expectLater(run([]), throwsMentioning(['Nothing was created']));

      final log = messages.join('\n');
      expect(log, contains('! careful'));
      expect(log, contains('· fyi'));
      expect(log, contains('✗ broken'));
      expectNothingCreated();
    });

    // #########################################################################
    test('creates nothing in a dry run', () async {
      await run(['--dry-run']);
      expect(messages.last, contains('Dry run'));
      expectNothingCreated();
    });

    // #########################################################################
    group('after questions', () {
      test('creates when the user confirms', () async {
        answer(asked: true);
        final prompts = _Prompts(true);
        await run([], prompts: prompts);
        expect(prompts.confirmations, 1);
        created();
      });

      test('creates nothing when the user declines', () async {
        answer(asked: true);
        await run([], prompts: _Prompts(false));
        expect(messages.last, contains('Nothing was created'));
        expectNothingCreated();
      });

      test('does not ask with --yes', () async {
        answer(asked: true);
        final prompts = _Prompts(false);
        await run(['-y'], prompts: prompts);
        expect(prompts.confirmations, 0);
        created();
      });

      test('asks with the current prompts by default', () async {
        answer(asked: true);
        GgPrompts.current = _Prompts(true);
        addTearDown(() => GgPrompts.current = null);
        await run([]);
        created();
      });
    });

    // #########################################################################
    test('continues a failed run headless with fewer options', () async {
      final gitHub = _LocalGitHub(Directory(p.join(root.path, 'remote.git')));
      final tools = Tools(processWrapper: _Tools());
      final registry = Registry(
        client: MockClient((_) async => http.Response('', 404)),
      );
      Future<void> create(List<String> args) =>
          (CommandRunner<dynamic>('test', 'test')..addCommand(
                CreateRepo(
                  ggLog: (m) => messages.add(rmConsoleColors(m)),
                  collector: SpecCollector(
                    ggLog: messages.add,
                    hasTerminal: () => false,
                    gitHub: gitHub,
                    registry: registry,
                  ),
                  preflight: Preflight(
                    tools: tools,
                    gitHub: gitHub,
                    registry: registry,
                  ),
                  creator: RepoCreator(
                    ggLog: messages.add,
                    tools: tools,
                    gitHub: gitHub,
                    runDna: (_) async {},
                    runChecks: (dir, ggLog) async {},
                    delay: (_) async {},
                  ),
                ),
              ))
              .run(['create-repo', '-o', root.path, ...args]);
      const identity = ['-n', 'gg_resumed', '-l', 'dart', '-g', 'ggsuite'];

      await expectLater(
        create([
          ...identity,
          '-d',
          'A repository created in two runs: the first one fails at the push.',
          ...['--private', '--cli', '--without-dna'],
        ]),
        throwsA(isA<Exception>()),
      );
      final dir = Directory(target('gg_resumed'));
      expect(CreateRepoState.load(dir)?.done, contains(CreateStep.remote));

      gitHub.unreachable = false;
      await create(identity);

      expect(CreateRepoState.fileIn(dir).existsSync(), isFalse);
      expect(messages.join('\n'), contains('Continues the earlier run'));
      final pubspec = File(p.join(dir.path, 'pubspec.yaml')).readAsStringSync();
      expect(pubspec, contains('publish_to: none'));
      expect(pubspec, contains('executables:'));
      final pushed = Process.runSync('git', [
        '-C',
        gitHub.bare.path,
        'log',
        '--format=%s',
        'main',
      ]);
      expect('${pushed.stdout}', contains('Initial version'));
    });

    // #########################################################################
    test('has working defaults', () {
      CreateRepo.example().ggLog('logged nowhere');
      final command = CreateRepo(ggLog: (_) {});
      expect(command.name, 'create-repo');
      expect(command.description, contains('Dart or TypeScript'));
    });
  });
}
