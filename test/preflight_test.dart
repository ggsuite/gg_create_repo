// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_create_repo/gg_create_repo.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// .............................................................................
/// A folder host that reports [problems].
class _ProblemHost extends StandaloneHost {
  const _ProblemHost({required super.outputDir, this.problems = const []});

  final List<String> problems;

  @override
  Future<List<String>> check(RepoSpec spec) async => problems;
}

void main() {
  late Directory dir;
  late MockTools tools;
  late MockGitHub gitHub;
  late Map<String, int> registry;
  late bool registryDown;

  Preflight preflight() => Preflight(
    tools: tools,
    gitHub: gitHub,
    registry: Registry(
      client: MockClient((request) async {
        if (registryDown) throw http.ClientException('offline');
        return http.Response('', registry[request.url.toString()] ?? 404);
      }),
    ),
  );

  Future<List<String>> findings(
    RepoSpec spec, {
    List<String> problems = const [],
    FindingLevel? level,
  }) async {
    final all = await preflight().run(
      spec,
      _ProblemHost(outputDir: dir, problems: problems),
    );
    return [
      for (final f in all)
        if (level == null || f.level == level) f.message,
    ];
  }

  Future<List<String>> errors(RepoSpec spec, {List<String>? problems}) =>
      findings(spec, problems: problems ?? [], level: FindingLevel.error);

  setUpAll(() => registerFallbackValue(Directory('.')));

  setUp(() {
    dir = Directory.systemTemp.createTempSync('preflight_');
    tools = MockTools();
    gitHub = MockGitHub();
    registry = {};
    registryDown = false;
    when(() => tools.version(any())).thenAnswer((_) async => '1.0.0');
    when(() => tools.version('git'))
        .thenAnswer((_) async => 'git version 2.45.1.windows.1');
    when(() => tools.gitConfig(any())).thenAnswer((_) async => 'Ada');
    when(() => tools.run(any(), any(), directory: any(named: 'directory')))
        .thenAnswer((_) async => '');
    when(() => gitHub.authProblem()).thenAnswer((_) async => null);
    when(() => gitHub.ownerType(any())).thenAnswer((_) async => 'User');
    when(() => gitHub.state(any()))
        .thenAnswer((_) async => RemoteState.missing);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  final spec = RepoSpec.example(dnaLayers: const []);
  const pubDna = 'https://pub.dev/api/packages/dna_ggsuite';

  group('Finding', () {
    test('example() is an error', () {
      expect(Finding.example().level, FindingLevel.error);
      expect(Finding.example(message: 'x').message, 'x');
    });
  });

  group('Preflight', () {
    test('finds nothing when everything is fine', () async {
      expect(await findings(spec), isEmpty);
    });

    test('uses the real tools by default', () {
      expect(Preflight(), isA<Preflight>());
    });

    group('git', () {
      test('must be installed', () async {
        when(() => tools.version('git')).thenAnswer((_) async => null);
        expect(await errors(spec), ['git is not installed.']);
      });

      test('must be 2.28 or newer', () async {
        when(() => tools.version('git'))
            .thenAnswer((_) async => 'git version 2.27.0');
        expect(await errors(spec), [contains('git 2.27 is too old')]);

        when(() => tools.version('git')).thenAnswer((_) async => 'git 1.9');
        expect(await errors(spec), [contains('git 1.9 is too old')]);

        when(() => tools.version('git')).thenAnswer((_) async => 'weird');
        expect(await errors(spec), [contains('git 0.0 is too old')]);
      });

      test('must know who commits', () async {
        when(() => tools.gitConfig('user.email')).thenAnswer((_) async => '');
        expect(await errors(spec), [contains('git has no user.email')]);
      });
    });

    group('tools', () {
      test('report a problem of the GitHub CLI', () async {
        when(() => gitHub.authProblem()).thenAnswer((_) async => 'no gh');
        expect(await errors(spec), ['no gh']);
      });

      test('need dart or flutter for Dart', () async {
        when(() => tools.version('dart')).thenAnswer((_) async => null);
        expect(await errors(spec), ['dart is not installed.']);

        when(() => tools.version('flutter')).thenAnswer((_) async => null);
        expect(
          await errors(RepoSpec.example(dnaLayers: const [], flutter: true)),
          ['flutter is not installed.'],
        );
      });

      test('need node and pnpm for TypeScript', () async {
        when(() => tools.version('pnpm')).thenAnswer((_) async => null);
        when(() => tools.version('node')).thenAnswer((_) async => null);
        final ts = RepoSpec.example(
          language: RepoLanguage.typescript,
          name: 'my-lib',
          dnaLayers: const [],
        );
        expect(await errors(ts), [
          'node is not installed.',
          'pnpm is not installed.',
        ]);
      });

      test('warn when Dart DNA cannot run its node script', () async {
        when(() => tools.version('node')).thenAnswer((_) async => null);
        registry[pubDna] = 200;
        final warnings = await findings(
          RepoSpec.example(),
          level: FindingLevel.warning,
        );
        expect(warnings, [contains('node is not installed')]);
        expect(await findings(spec), isEmpty);
      });
    });

    group('target folder', () {
      Directory target() => Directory(p.join(dir.path, spec.name));

      test('may be missing or empty', () async {
        expect(await findings(spec), isEmpty);
        target().createSync();
        expect(await findings(spec), isEmpty);
      });

      test('must not hold other files', () async {
        File(p.join(target().path, 'x.txt')).createSync(recursive: true);
        expect(await errors(spec), [contains('already exists and is not')]);
      });

      test('continues an earlier run of the same repository', () async {
        CreateRepoState(spec: spec).markDone(CreateStep.scaffold, target());
        expect(await findings(spec, level: FindingLevel.info), [
          startsWith('Continues the earlier run'),
        ]);
        expect(await errors(spec), isEmpty);
      });

      test('does not continue the run of another repository', () async {
        CreateRepoState(spec: RepoSpec.example(org: 'other'))
            .markDone(CreateStep.scaffold, target());
        expect(await errors(spec), [contains('already exists and is not')]);
      });
    });

    group('GitHub', () {
      test('must know the owner', () async {
        when(() => gitHub.ownerType(any())).thenAnswer((_) async => null);
        expect(await errors(spec), [contains('knows no organization')]);
      });

      test('uses an empty repository', () async {
        when(() => gitHub.state(any()))
            .thenAnswer((_) async => RemoteState.empty);
        expect(await findings(spec, level: FindingLevel.info), [
          contains('empty repository'),
        ]);
      });

      test('reports when GitHub cannot be asked', () async {
        when(() => gitHub.state(any()))
            .thenThrow(Exception('GitHub could not be asked for x'));
        expect(await errors(spec), [contains('could not be asked')]);
      });

      test('refuses a repository with commits', () async {
        when(() => gitHub.state(any()))
            .thenAnswer((_) async => RemoteState.filled);
        expect(await errors(spec), [contains('already exists and has')]);
      });

      test('accepts the repository of the earlier run', () async {
        when(() => gitHub.state(any()))
            .thenAnswer((_) async => RemoteState.filled);
        CreateRepoState(spec: spec)
            .markDone(CreateStep.push, Directory(p.join(dir.path, spec.name)));
        expect(await errors(spec), isEmpty);
        expect(
          await findings(spec, level: FindingLevel.info),
          contains(contains('exists from the earlier run')),
        );
      });
    });

    group('registry', () {
      test('refuses a name that is taken', () async {
        registry['https://pub.dev/api/packages/gg_example_repo'] = 200;
        expect(await errors(spec), [contains('already taken on pub.dev')]);
      });

      test('checks npm with the scoped name', () async {
        registry['https://registry.npmjs.org/@ggsuite%2Fmy-lib'] = 200;
        final ts = RepoSpec.example(
          language: RepoLanguage.typescript,
          name: 'my-lib',
          dnaLayers: const [],
        );
        expect(await errors(ts), [contains('already taken on npm')]);
      });

      test('warns when the registry cannot be asked', () async {
        registryDown = true;
        expect(await findings(spec, level: FindingLevel.warning), [
          contains('pub.dev could not be asked'),
        ]);
      });

      test('is not asked for a private repository', () async {
        registry['https://pub.dev/api/packages/gg_example_repo'] = 200;
        expect(
          await errors(RepoSpec.example(isPrivate: true, dnaLayers: const [])),
          isEmpty,
        );
      });
    });

    group('DNA', () {
      test('accepts a layer on pub.dev and npm', () async {
        registry[pubDna] = 200;
        registry['https://registry.npmjs.org/@tssuite%2Fdna-tssuite'] = 200;
        final layers = RepoSpec.example(
          dnaLayers: const ['dna_ggsuite', '@tssuite/dna-tssuite'],
        );
        expect(await findings(layers), isEmpty);
      });

      test('refuses a layer that is not in the registry', () async {
        final layers = RepoSpec.example(
          dnaLayers: const ['dna_ggsuite', '@tssuite/dna-x'],
        );
        expect(await errors(layers), [
          'The DNA layer dna_ggsuite is not on pub.dev.',
          'The DNA layer @tssuite/dna-x is not on npm.',
        ]);
      });

      test('warns when the registry cannot be asked', () async {
        registryDown = true;
        final warnings = await findings(
          RepoSpec.example(isPrivate: true),
          level: FindingLevel.warning,
        );
        expect(warnings, ['pub.dev could not be asked for dna_ggsuite.']);
      });

      test('reads a git URL with git', () async {
        const urls = [
          'git@github.com:ggsuite/dna_ggsuite.git',
          'https://github.com/ggsuite/dna_x.git',
        ];
        when(
          () => tools.run('git', [
            'ls-remote',
            '--heads',
            urls[1],
          ], directory: any(named: 'directory')),
        ).thenThrow(Exception('not found'));

        expect(await errors(RepoSpec.example(dnaLayers: urls)), [
          'The DNA layer ${urls[1]} cannot be read with git.',
        ]);
        verify(
          () => tools.run('git', [
            'ls-remote',
            '--heads',
            urls[0],
          ], directory: any(named: 'directory')),
        ).called(1);
      });
    });

    group('host', () {
      test('adds its problems as errors', () async {
        expect(await errors(spec, problems: ['in use']), ['in use']);
      });
    });
  });
}
