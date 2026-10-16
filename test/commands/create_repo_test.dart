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
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Returns [spec] and remembers the options it got.
class _Collector extends SpecCollector {
  _Collector(this.spec, {this.didAsk = false}) : super(ggLog: (_) {});

  final RepoSpec spec;
  final bool didAsk;
  RepoOptions? options;

  @override
  Future<RepoSpec> collect(RepoOptions options, RepoHost host) async {
    this.options = options;
    return spec;
  }

  @override
  bool get asked => didAsk;
}

/// Answers with fixed findings.
class _Preflight extends Preflight {
  _Preflight([this.findings = const []]);

  final List<Finding> findings;
  RepoSpec? checked;

  @override
  Future<List<Finding>> run(RepoSpec spec, RepoHost host) async {
    checked = spec;
    return findings;
  }
}

/// Remembers what it was asked to create.
class _Creator extends RepoCreator {
  _Creator() : super(ggLog: (_) {});

  final created = <String>[];

  @override
  Future<void> create({
    required RepoSpec spec,
    required Directory directory,
    required RepoHost host,
  }) async => created.add('${spec.slug} ${directory.path}');
}

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
  late _Creator creator;

  setUp(() {
    root = Directory.systemTemp.createTempSync('create_repo_command_');
    messages = [];
    creator = _Creator();
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<void> run(
    List<String> args, {
    RepoSpec? spec,
    bool asked = false,
    List<Finding> findings = const [],
    GgPrompts? prompts,
    HostFactory? host,
    _Collector? collector,
    _Preflight? preflight,
  }) {
    final command = CreateRepo(
      ggLog: (m) => messages.add(rmConsoleColors(m)),
      host: host,
      collector:
          collector ?? _Collector(spec ?? RepoSpec.example(), didAsk: asked),
      preflight: preflight ?? _Preflight(findings),
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

  group('CreateRepo', () {
    // #########################################################################
    test('passes every option on to the collector', () async {
      final collector = _Collector(RepoSpec.example());

      await run([
        ...['-n', 'x', '-l', 'ts', '-g', 'org', '-d', 'desc'],
        ...['--scope', 's', '--private', '--no-cli', '--example'],
        ...['--flutter', '--dna', 'a', '--dna', 'b', '--without-dna'],
        ...['--var', 'k=v', '-i'],
      ], collector: collector);

      final o = collector.options!;
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
      final collector = _Collector(RepoSpec.example());
      await run([], collector: collector);
      final o = collector.options!;
      expect([o.isPrivate, o.cli, o.example, o.flutter], everyElement(null));
    });

    // #########################################################################
    test('creates the repository in the output folder', () async {
      await run([]);

      expect(creator.created, ['ggsuite/gg_example_repo ${target()}']);
      final log = messages.join('\n');
      expect(log, contains('ggsuite/gg_example_repo'));
      expect(log, contains('gg_example_repo 0.0.1'));
      expect(log, contains('dna_ggsuite'));
      expect(log, contains('Dart, example, public'));
      expect(log, contains('Created https://github.com/ggsuite/'));
    });

    test('shows the kind of package and what follows', () async {
      await run(
        [],
        spec: RepoSpec.example(
          flutter: true,
          cli: true,
          isPrivate: true,
          dnaLayers: [],
        ),
        host: (args) => _TicketHost(root),
      );

      final log = messages.join('\n');
      expect(log, contains('Dart, Flutter, CLI, example, private'));
      expect(log, contains('DNA:        none'));
      expect(log, contains('Then:       add it to the ticket t'));
    });

    // #########################################################################
    test('continues the spec of an earlier run', () async {
      final earlier = RepoSpec.example(description: 'x' * 70);
      Directory(target()).createSync();
      CreateRepoState(spec: earlier)
          .markDone(CreateStep.scaffold, Directory(target()));
      final preflight = _Preflight();

      await run([], preflight: preflight);

      expect(preflight.checked!.description, 'x' * 70);
    });

    // #########################################################################
    test('logs the findings and stops at an error', () async {
      await expectLater(
        run(
          [],
          findings: [
            const Finding(FindingLevel.warning, 'careful'),
            const Finding(FindingLevel.info, 'fyi'),
            const Finding(FindingLevel.error, 'broken'),
          ],
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Nothing was created'),
          ),
        ),
      );

      final log = messages.join('\n');
      expect(log, contains('! careful'));
      expect(log, contains('· fyi'));
      expect(log, contains('✗ broken'));
      expect(creator.created, isEmpty);
    });

    // #########################################################################
    test('creates nothing in a dry run', () async {
      await run(['--dry-run']);

      expect(messages.last, contains('Dry run'));
      expect(creator.created, isEmpty);
    });

    // #########################################################################
    group('after questions', () {
      test('creates when the user confirms', () async {
        final prompts = _Prompts(true);
        await run([], asked: true, prompts: prompts);
        expect(prompts.confirmations, 1);
        expect(creator.created, hasLength(1));
      });

      test('creates nothing when the user declines', () async {
        await run([], asked: true, prompts: _Prompts(false));
        expect(messages.last, contains('Nothing was created'));
        expect(creator.created, isEmpty);
      });

      test('does not ask with --yes', () async {
        final prompts = _Prompts(false);
        await run(['-y'], asked: true, prompts: prompts);
        expect(prompts.confirmations, 0);
        expect(creator.created, hasLength(1));
      });

      test('asks with the current prompts by default', () async {
        GgPrompts.current = _Prompts(true);
        addTearDown(() => GgPrompts.current = null);
        await run([], asked: true);
        expect(creator.created, hasLength(1));
      });
    });

    // #########################################################################
    test('has working defaults', () {
      final command = CreateRepo(ggLog: (_) {});
      expect(command.name, 'create-repo');
      expect(command.description, contains('Dart or TypeScript'));
    });
  });
}
