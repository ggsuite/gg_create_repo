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
import 'package:gg_create_repo/src/registry.dart';
import 'package:gg_interact/gg_interact.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// .............................................................................
/// Answers from a queue and records every question.
class _ScriptedPrompts extends GgPrompts {
  _ScriptedPrompts(this.answers);

  final List<Object> answers;
  final questions = <String>[];
  final options = <List<String>>[];
  final defaults = <String?>[];

  @override
  Future<int> select({
    required String prompt,
    required List<String> options,
    int initialIndex = 0,
  }) async {
    questions.add(prompt);
    this.options.add(options);
    return answers.removeAt(0) as int;
  }

  @override
  Future<String> input({
    required String prompt,
    String? defaultValue,
    String? initialText,
    bool asMessageEditor = false,
  }) async {
    questions.add(prompt);
    defaults.add(defaultValue);
    return answers.removeAt(0) as String;
  }
}

// .............................................................................
/// A folder host with a preset org, DNA candidates and local layers.
class _Host extends StandaloneHost {
  _Host({
    super.orgs = const [],
    this.preset,
    this.candidates = const [],
    this.layers = const {},
  }) : super(outputDir: Directory.systemTemp);

  final String? preset;
  final List<DnaCandidate> candidates;
  final Map<String, Directory> layers;

  @override
  String? get presetOrg => preset;

  @override
  List<DnaCandidate> dnaCandidates(RepoSpec spec) => candidates;

  @override
  Directory? layerDir(String layer) => layers[layer];
}

void main() {
  late MockGitHub gitHub;
  late Set<String> inRegistry;
  late List<String> messages;

  const description =
      'An example repository created by gg_create_repo for the tests.';
  const pubDnaGgsuite = 'https://pub.dev/api/packages/dna_ggsuite';
  final ggsuiteDna = DnaCandidate.example();

  SpecCollector collector(_ScriptedPrompts prompts, {bool terminal = true}) =>
      SpecCollector(
        ggLog: messages.add,
        prompts: prompts,
        hasTerminal: () => terminal,
        gitHub: gitHub,
        registry: Registry(
          client: MockClient(
            (r) async =>
                http.Response('', inRegistry.contains('${r.url}') ? 200 : 404),
          ),
        ),
      );

  Future<RepoSpec> spec(
    RepoOptions options, {
    _ScriptedPrompts? prompts,
    _Host? host,
    bool terminal = true,
  }) async {
    final collected = await collector(
      prompts ?? _ScriptedPrompts([]),
      terminal: terminal,
    ).collect(options, host ?? _Host());
    return collected.spec;
  }

  Matcher throwsWith(String text) => throwsA(
    isA<Exception>().having(
      (e) => rmConsoleColors('$e'),
      'message',
      contains(text),
    ),
  );

  setUp(() {
    gitHub = MockGitHub();
    inRegistry = {};
    messages = [];
    when(() => gitHub.orgs()).thenAnswer((_) async => ['tssuite']);
    when(() => gitHub.login()).thenAnswer((_) async => 'ada');
  });

  tearDown(() => GgPrompts.current = null);

  group('SpecCollector', () {
    group('collect()', () {
      test('takes given options without asking', () async {
        final prompts = _ScriptedPrompts([]);

        final (:spec, :asked) = await collector(
          prompts,
          terminal: false,
        ).collect(RepoOptions.example(), _Host());

        expect(spec.name, 'gg_example_repo');
        expect(spec.language, RepoLanguage.dart);
        expect(spec.org, 'ggsuite');
        expect(spec.description, description);
        expect(spec.isPrivate, isFalse);
        expect(spec.cli, isFalse);
        expect(spec.example, isTrue);
        expect(spec.flutter, isFalse);
        expect(spec.dnaLayers, ['dna_ggsuite']);
        expect(spec.vars, isEmpty);
        expect(asked, isFalse);
        expect(prompts.questions, isEmpty);
      });

      test('uses GgPrompts.current without own prompts', () async {
        final prompts = _ScriptedPrompts([1]);
        GgPrompts.current = prompts;
        final collected =
            await SpecCollector.example(
              ggLog: messages.add,
              hasTerminal: () => true,
              gitHub: gitHub,
            ).collect(
              const RepoOptions(
                name: 'my-lib',
                org: 'ggsuite',
                description: 'x',
                withoutDna: true,
              ),
              _Host(),
            );
        expect(collected.spec.language, RepoLanguage.typescript);
        expect(prompts.questions, ['Which language?']);
      });

      test('example() collects given options with the defaults', () async {
        final collected = await SpecCollector.example().collect(
          const RepoOptions(
            name: 'my-lib',
            language: 'ts',
            org: 'ggsuite',
            description: 'x',
            withoutDna: true,
          ),
          _Host(),
        );
        expect(collected.spec.packageName, '@ggsuite/my-lib');
      });

      test('example() logs nowhere by default', () async {
        final prompts = _ScriptedPrompts(['Bad', 'my-lib']);
        final collected =
            await SpecCollector.example(
              prompts: prompts,
              hasTerminal: () => true,
            ).collect(
              const RepoOptions(
                language: 'ts',
                org: 'ggsuite',
                description: 'x',
                withoutDna: true,
              ),
              _Host(),
            );
        expect(collected.spec.name, 'my-lib');
        expect(prompts.questions, hasLength(2));
      });

      group('refuses invalid options', () {
        Future<void> refuse(RepoOptions options, String reason) =>
            expectLater(spec(options), throwsWith(reason));

        test('language, name, org and description', () async {
          await refuse(
            RepoOptions.example(language: 'cobol'),
            'is no language',
          );
          await refuse(
            RepoOptions.example(name: 'Bad Name'),
            'no valid Dart package name',
          );
          await refuse(RepoOptions.example(org: '-x'), 'no valid GitHub');
          await refuse(
            RepoOptions.example(description: 'short'),
            'pub.dev needs 60 to 180',
          );
        });

        test('a Flutter package with a CLI', () async {
          await refuse(
            const RepoOptions(
              name: 'a',
              language: 'dart',
              org: 'ggsuite',
              description: description,
              cli: true,
              flutter: true,
              withoutDna: true,
            ),
            'A Flutter package gets no CLI.',
          );
        });

        test('an invalid npm scope', () async {
          await refuse(
            const RepoOptions(
              name: 'my-lib',
              language: 'ts',
              org: 'ggsuite',
              description: 'x',
              npmScope: '@Bad',
              withoutDna: true,
            ),
            'no valid npm scope',
          );
        });

        test('--dna together with --without-dna', () async {
          await refuse(
            RepoOptions.example(withoutDna: true),
            'Pass either --dna or --without-dna.',
          );
        });

        test('a variable without a key', () async {
          await refuse(
            const RepoOptions(
              name: 'a',
              language: 'dart',
              org: 'ggsuite',
              description: description,
              withoutDna: true,
              vars: ['=x'],
            ),
            'is no variable',
          );
        });
      });

      test('fails headless with the option to pass', () async {
        await expectLater(
          spec(
            const RepoOptions(language: 'dart', org: 'ggsuite'),
            terminal: false,
          ),
          throwsA(
            isA<Exception>().having(
              (e) => '$e',
              'message',
              allOf(contains('stdin is not a terminal'), contains('--name')),
            ),
          ),
        );
      });

      test('asks for the missing values', () async {
        final prompts = _ScriptedPrompts([
          0, // Dart
          1, // tssuite
          'Bad', // invalid name
          'good_name',
          description,
        ]);

        final (:spec, :asked) = await collector(prompts).collect(
          const RepoOptions(withoutDna: true),
          _Host(orgs: ['ggsuite']),
        );

        expect(spec.language, RepoLanguage.dart);
        expect(spec.org, 'tssuite');
        expect(spec.name, 'good_name');
        expect(spec.description, description);
        expect(asked, isTrue);
        expect(prompts.questions, [
          'Which language?',
          'Organization',
          'Name of the repository',
          'Name of the repository',
          'Description',
        ]);
        expect(prompts.options[1], [
          'ggsuite',
          'tssuite',
          'ada',
          'Another organization or user',
        ]);
        expect(
          messages.map(rmConsoleColors).single,
          contains('no valid Dart package name'),
        );
      });

      group('the organization', () {
        RepoOptions noOrg({bool interactive = false}) => RepoOptions(
          name: 'a',
          language: 'dart',
          description: description,
          withoutDna: true,
          interactive: interactive,
          isPrivate: false,
          cli: false,
          example: true,
          flutter: false,
        );

        test('can be entered when it is not in the menu', () async {
          final prompts = _ScriptedPrompts([2, 'acme']);
          final result = await spec(noOrg(), prompts: prompts);
          expect(result.org, 'acme');
          expect(prompts.questions.last, 'GitHub organization or user');
        });

        test('is entered right away when none is known', () async {
          when(() => gitHub.orgs()).thenAnswer((_) async => []);
          when(() => gitHub.login()).thenAnswer((_) async => null);
          final prompts = _ScriptedPrompts(['acme']);
          final result = await spec(noOrg(), prompts: prompts);
          expect(result.org, 'acme');
          expect(prompts.questions, ['GitHub organization or user']);
        });

        test('is the preset of the host', () async {
          final prompts = _ScriptedPrompts([]);
          final result = await spec(
            noOrg(),
            prompts: prompts,
            host: _Host(preset: 'rljson'),
            terminal: false,
          );
          expect(result.org, 'rljson');
          expect(prompts.questions, isEmpty);
        });

        test('offers the preset first when interactive', () async {
          final prompts = _ScriptedPrompts([0]);
          final result = await spec(
            noOrg(interactive: true),
            prompts: prompts,
            host: _Host(preset: 'rljson'),
          );
          expect(result.org, 'rljson');
          expect(prompts.options.single.first, 'rljson');
        });

        test('needs a terminal for the menu', () async {
          await expectLater(
            spec(noOrg(), terminal: false),
            throwsWith('--org'),
          );
          verifyNever(() => gitHub.orgs());
        });
      });

      group('with --interactive', () {
        RepoOptions all({String language = 'dart', bool? isPrivate}) =>
            RepoOptions(
              name: language == 'dart' ? 'a' : 'my-lib',
              language: language,
              org: 'ggsuite',
              description: description,
              withoutDna: true,
              interactive: true,
              isPrivate: isPrivate,
            );

        test('asks visibility, CLI and example', () async {
          final prompts = _ScriptedPrompts([1, 0, 1]);
          final result = await spec(all(), prompts: prompts);
          expect(result.isPrivate, isTrue);
          expect(result.cli, isTrue);
          expect(result.example, isFalse);
          expect(result.flutter, isFalse);
          expect(prompts.questions, [
            'Visibility',
            'With a CLI?',
            'With an example?',
          ]);
        });

        test('asks for Flutter without a CLI', () async {
          final prompts = _ScriptedPrompts([0, 1, 0, 0]);
          final result = await spec(all(), prompts: prompts);
          expect(result.isPrivate, isFalse);
          expect(result.cli, isFalse);
          expect(result.example, isTrue);
          expect(result.flutter, isTrue);
          expect(prompts.questions.last, 'A Flutter package?');
        });

        test('asks for the npm scope of TypeScript', () async {
          final prompts = _ScriptedPrompts([0, 'acme']);
          final result = await spec(all(language: 'ts'), prompts: prompts);
          expect(result.npmScope, 'acme');
          expect(result.packageName, '@acme/my-lib');
          expect(prompts.defaults.last, 'ggsuite');
          expect(result.cli, isFalse);
          expect(result.example, isFalse);
        });

        test('fails headless at the first question', () async {
          await expectLater(
            spec(all(isPrivate: false), terminal: false),
            throwsWith('With a CLI?'),
          );
        });
      });

      test('takes a given npm scope', () async {
        final result = await spec(
          const RepoOptions(
            name: 'my-lib',
            language: 'ts',
            org: 'ggsuite',
            description: 'x',
            npmScope: 'acme',
            withoutDna: true,
          ),
        );
        expect(result.packageName, '@acme/my-lib');
      });

      test('parses the variables', () async {
        final result = await spec(
          const RepoOptions(
            name: 'a',
            language: 'dart',
            org: 'ggsuite',
            description: description,
            withoutDna: true,
            vars: ['a=1', 'b=x=y'],
          ),
        );
        expect(result.vars, {'a': '1', 'b': 'x=y'});
      });

      group('the DNA', () {
        RepoOptions noDna({List<String> vars = const []}) => RepoOptions(
          name: 'a',
          language: 'dart',
          org: 'ggsuite',
          description: description,
          vars: vars,
        );

        test('is none with --without-dna', () async {
          final result = await spec(
            RepoOptions.example(dnaLayers: [], withoutDna: true),
          );
          expect(result.dnaLayers, isEmpty);
        });

        test('is the suggestion of the host when headless', () async {
          final result = await spec(
            noDna(),
            host: _Host(candidates: [ggsuiteDna]),
            terminal: false,
          );
          expect(result.dnaLayers, ['dna_ggsuite']);
        });

        test('is not taken from the registry alone when headless', () async {
          inRegistry.add(pubDnaGgsuite);
          await expectLater(
            spec(noDna(), terminal: false),
            throwsWith('--dna <layer> or --without-dna'),
          );
        });

        test('must be passed headless without a suggestion', () async {
          await expectLater(
            spec(noDna(), terminal: false),
            throwsWith('--without-dna'),
          );
        });

        test('is picked from the menu, one layer after another', () async {
          final prompts = _ScriptedPrompts([
            0, // the suggestion
            0, // add another: yes
            1, // the other candidate of the host
            0, // add another: yes
            2, // enter one
            '', // invalid
            'pkg_y',
            1, // add another: no
          ]);
          final host = _Host(
            candidates: [
              ggsuiteDna,
              DnaCandidate.example(label: 'dna_x', ref: 'git@x'),
            ],
          );

          final result = await spec(noDna(), prompts: prompts, host: host);

          expect(result.dnaLayers, ['dna_ggsuite', 'git@x', 'pkg_y']);
          expect(prompts.options.first, [
            'dna_ggsuite (suggested)',
            'dna_x',
            'Enter a package name or git URL',
            'No DNA',
          ]);
          expect(prompts.questions, contains('Which further DNA?'));
          expect(messages.map(rmConsoleColors), ['Please enter a layer.']);
        });

        test('offers the suggestion the registry has', () async {
          inRegistry.add(pubDnaGgsuite);
          final prompts = _ScriptedPrompts([0, 0, 2]);
          final result = await spec(noDna(), prompts: prompts);
          expect(result.dnaLayers, ['dna_ggsuite']);
          expect(prompts.options.last, [
            'dna_ggsuite (suggested)',
            'Enter a package name or git URL',
            'No DNA',
          ]);
        });

        test('can be none from the menu', () async {
          final prompts = _ScriptedPrompts([1]);
          final result = await spec(noDna(), prompts: prompts);
          expect(result.dnaLayers, isEmpty);
          expect(prompts.options.single, [
            'Enter a package name or git URL',
            'No DNA',
          ]);
        });

        group('variables', () {
          late Directory root;

          /// Writes a layer with [parents] and [mustOverride] flags.
          Directory layer(
            String name, {
            List<String> parents = const [],
            Map<String, bool> mustOverride = const {},
          }) {
            final dir = Directory(p.join(root.path, name));
            File(p.join(dir.path, 'dna', '_dna.json'))
              ..createSync(recursive: true)
              ..writeAsStringSync(
                jsonEncode({
                  'version': 2,
                  'layers': parents,
                  'mustOverride': mustOverride,
                }),
              );
            return dir;
          }

          setUp(() => root = Directory.systemTemp.createTempSync('layers_'));
          tearDown(() => root.deleteSync(recursive: true));

          _Host host() => _Host(
            candidates: [ggsuiteDna],
            layers: {
              'dna_base': layer('dna_base', mustOverride: {'dnaCompany': true}),
              'dna_ggsuite': layer('dna_ggsuite', parents: ['dna_base']),
              'dna_umbrella': layer(
                'dna_umbrella',
                parents: ['dna_base'],
                mustOverride: {'dnaCompany': false},
              ),
            },
          );

          test('asks for the required ones', () async {
            final prompts = _ScriptedPrompts(['', 'Acme']);
            final result = await spec(
              RepoOptions.example(),
              prompts: prompts,
              host: host(),
            );
            expect(result.vars, {'dnaCompany': 'Acme'});
            expect(prompts.questions.last, 'dnaCompany (required by dna_base)');
            expect(
              messages.map(rmConsoleColors),
              contains('A value is required.'),
            );
          });

          test('takes a required one given with --var', () async {
            final result = await spec(
              noDna(vars: ['dnaCompany=Given']),
              host: host(),
              terminal: false,
            );
            expect(result.vars, {'dnaCompany': 'Given'});
          });

          test('fail headless with the option to pass', () async {
            await expectLater(
              spec(noDna(), host: host(), terminal: false),
              throwsWith('--var dnaCompany=<value>'),
            );
          });

          test('are not asked when a layer lifts the duty', () async {
            final result = await spec(
              RepoOptions.example(dnaLayers: ['dna_umbrella']),
              host: host(),
              terminal: false,
            );
            expect(result.vars, isEmpty);
          });

          test('are not asked for a layer without a local copy', () async {
            final result = await spec(
              RepoOptions.example(dnaLayers: ['dna_unknown']),
              host: host(),
              terminal: false,
            );
            expect(result.vars, isEmpty);
          });
        });
      });
    });

    group('suggestedDna()', () {
      test('is dna_<org> for Dart', () {
        expect(
          SpecCollector.suggestedDna(RepoSpec.example(org: 'My-Org')),
          'dna_my_org',
        );
      });

      test('is @<scope>/dna-<org> for TypeScript', () {
        expect(
          SpecCollector.suggestedDna(
            RepoSpec.example(language: RepoLanguage.typescript, org: 'RlJson'),
          ),
          '@rljson/dna-rljson',
        );
      });
    });
  });
}
