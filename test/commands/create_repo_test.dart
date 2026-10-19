// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_create_repo/gg_create_repo.dart';
import 'package:gg_interact/gg_interact.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

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
      () => collector.collect(any(), any()),
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
      verify(() => collector.collect(captureAny(), any())).captured.single
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
      void earlierRun(RepoSpec spec) {
        Directory(target()).createSync();
        CreateRepoState(
          spec: spec,
          done: {CreateStep.scaffold},
        ).save(Directory(target()));
      }

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
    test('has working defaults', () {
      CreateRepo.example().ggLog('logged nowhere');
      final command = CreateRepo(ggLog: (_) {});
      expect(command.name, 'create-repo');
      expect(command.description, contains('Dart or TypeScript'));
    });
  });
}
