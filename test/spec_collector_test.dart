// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_create_repo/gg_create_repo.dart';
import 'package:gg_interact/gg_interact.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
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
/// A folder host with a preset org and DNA candidates.
class _Host extends StandaloneHost {
  _Host({super.orgs = const [], this.preset, this.candidates = const []})
    : super(outputDir: Directory.systemTemp);

  final String? preset;
  final List<DnaCandidate> candidates;

  @override
  String? get presetOrg => preset;

  @override
  List<DnaCandidate> dnaCandidates(RepoSpec spec) => candidates;
}

void main() {
  late MockGitHub gitHub;
  late Set<String> inRegistry;
  late List<String> messages;

  const description =
      'An example repository created by gg_create_repo for the tests.';

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

  setUp(() {
    gitHub = MockGitHub();
    inRegistry = {};
    messages = [];
    when(() => gitHub.orgs()).thenAnswer((_) async => ['tssuite']);
    when(() => gitHub.login()).thenAnswer((_) async => 'ada');
  });

  tearDown(() => GgPrompts.current = null);

  const pubDnaGgsuite = 'https://pub.dev/api/packages/dna_ggsuite';

  group('SpecCollector', () {
    group('collect()', () {
      test('takes given options without asking', () async {
        final prompts = _ScriptedPrompts([]);
        final c = collector(prompts, terminal: false);

        final spec = await c.collect(RepoOptions.example(), _Host());

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
        expect(c.asked, isFalse);
        expect(prompts.questions, isEmpty);
      });

      test('uses GgPrompts.current without own prompts', () async {
        final prompts = _ScriptedPrompts([1]);
        GgPrompts.current = prompts;
        final c = SpecCollector(
          ggLog: messages.add,
          hasTerminal: () => true,
          gitHub: gitHub,
        );
        final spec = await c.collect(
          const RepoOptions(
            name: 'my-lib',
            org: 'ggsuite',
            description: 'x',
            withoutDna: true,
          ),
          _Host(),
        );
        expect(spec.language, RepoLanguage.typescript);
        expect(prompts.questions, ['Which language?']);
      });

      group('refuses invalid options', () {
        Future<void> refuse(RepoOptions options, String reason) async {
          await expectLater(
            collector(_ScriptedPrompts([])).collect(options, _Host()),
            throwsA(
              isA<Exception>().having((e) => '$e', 'message', contains(reason)),
            ),
          );
        }

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
          collector(_ScriptedPrompts([]), terminal: false).collect(
            const RepoOptions(language: 'dart', org: 'ggsuite'),
            _Host(),
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
        final c = collector(prompts);

        final spec = await c.collect(
          const RepoOptions(withoutDna: true),
          _Host(orgs: ['ggsuite']),
        );

        expect(spec.language, RepoLanguage.dart);
        expect(spec.org, 'tssuite');
        expect(spec.name, 'good_name');
        expect(spec.description, description);
        expect(c.asked, isTrue);
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
        expect(messages.single, contains('no valid Dart package name'));
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
          final spec = await collector(prompts).collect(noOrg(), _Host());
          expect(spec.org, 'acme');
          expect(prompts.questions.last, 'GitHub organization or user');
        });

        test('is entered right away when none is known', () async {
          when(() => gitHub.orgs()).thenAnswer((_) async => []);
          when(() => gitHub.login()).thenAnswer((_) async => null);
          final prompts = _ScriptedPrompts(['acme']);
          final spec = await collector(prompts).collect(noOrg(), _Host());
          expect(spec.org, 'acme');
          expect(prompts.questions, ['GitHub organization or user']);
        });

        test('is the preset of the host', () async {
          final prompts = _ScriptedPrompts([]);
          final spec = await collector(prompts)
              .collect(noOrg(), _Host(preset: 'rljson'));
          expect(spec.org, 'rljson');
          expect(prompts.questions, isEmpty);
        });

        test('offers the preset first when interactive', () async {
          final prompts = _ScriptedPrompts([0]);
          final spec = await collector(prompts)
              .collect(noOrg(interactive: true), _Host(preset: 'rljson'));
          expect(spec.org, 'rljson');
          expect(prompts.options.single.first, 'rljson');
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
          final spec = await collector(prompts).collect(all(), _Host());
          expect(spec.isPrivate, isTrue);
          expect(spec.cli, isTrue);
          expect(spec.example, isFalse);
          expect(spec.flutter, isFalse);
          expect(prompts.questions, [
            'Visibility',
            'With a CLI?',
            'With an example?',
          ]);
        });

        test('asks for Flutter without a CLI', () async {
          final prompts = _ScriptedPrompts([0, 1, 0, 0]);
          final spec = await collector(prompts).collect(all(), _Host());
          expect(spec.isPrivate, isFalse);
          expect(spec.cli, isFalse);
          expect(spec.example, isTrue);
          expect(spec.flutter, isTrue);
          expect(prompts.questions.last, 'A Flutter package?');
        });

        test('asks for the npm scope of TypeScript', () async {
          final prompts = _ScriptedPrompts([0, 'acme']);
          final spec = await collector(prompts)
              .collect(all(language: 'ts'), _Host());
          expect(spec.npmScope, 'acme');
          expect(spec.packageName, '@acme/my-lib');
          expect(prompts.defaults.last, 'ggsuite');
          expect(spec.cli, isFalse);
          expect(spec.example, isFalse);
        });

        test('fails headless at the first question', () async {
          await expectLater(
            collector(
              _ScriptedPrompts([]),
              terminal: false,
            ).collect(all(isPrivate: false), _Host()),
            throwsA(
              isA<Exception>().having(
                (e) => '$e',
                'message',
                contains('With a CLI?'),
              ),
            ),
          );
        });
      });

      test('takes a given npm scope', () async {
        final spec = await collector(_ScriptedPrompts([])).collect(
          const RepoOptions(
            name: 'my-lib',
            language: 'ts',
            org: 'ggsuite',
            description: 'x',
            npmScope: 'acme',
            withoutDna: true,
          ),
          _Host(),
        );
        expect(spec.packageName, '@acme/my-lib');
      });

      test('parses the variables', () async {
        final spec = await collector(_ScriptedPrompts([])).collect(
          const RepoOptions(
            name: 'a',
            language: 'dart',
            org: 'ggsuite',
            description: description,
            withoutDna: true,
            vars: ['a=1', 'b=x=y'],
          ),
          _Host(),
        );
        expect(spec.vars, {'a': '1', 'b': 'x=y'});
      });

      group('the DNA', () {
        RepoOptions noDna() => const RepoOptions(
          name: 'a',
          language: 'dart',
          org: 'ggsuite',
          description: description,
        );

        test('is none with --without-dna', () async {
          final spec = await collector(_ScriptedPrompts([])).collect(
            RepoOptions.example(dnaLayers: [], withoutDna: true),
            _Host(),
          );
          expect(spec.dnaLayers, isEmpty);
        });

        test('is the suggestion when headless', () async {
          inRegistry.add(pubDnaGgsuite);
          final spec = await collector(
            _ScriptedPrompts([]),
            terminal: false,
          ).collect(noDna(), _Host());
          expect(spec.dnaLayers, ['dna_ggsuite']);
        });

        test('must be passed headless without a suggestion', () async {
          await expectLater(
            collector(
              _ScriptedPrompts([]),
              terminal: false,
            ).collect(noDna(), _Host()),
            throwsA(
              isA<Exception>().having(
                (e) => '$e',
                'message',
                contains('--without-dna'),
              ),
            ),
          );
        });

        test('is picked from the menu, one layer after another', () async {
          final prompts = _ScriptedPrompts([
            0, // the suggestion
            0, // add another: yes
            1, // the candidate of the host
            0, // add another: yes
            2, // enter one
            '', // invalid
            'pkg_y',
            1, // add another: no
          ]);
          final host = _Host(
            candidates: [
              DnaCandidate.example(),
              DnaCandidate.example(label: 'dna_x', ref: 'git@x'),
            ],
          );

          final spec = await collector(prompts).collect(noDna(), host);

          expect(spec.dnaLayers, ['dna_ggsuite', 'git@x', 'pkg_y']);
          expect(prompts.options.first, [
            'dna_ggsuite (suggested)',
            'dna_x',
            'Enter a package name or git URL',
            'No DNA',
          ]);
          expect(prompts.questions, contains('Which further DNA?'));
          expect(messages.map(rmConsoleColors), ['Please enter a layer.']);
        });

        test('stops when no further DNA is picked', () async {
          inRegistry.add(pubDnaGgsuite);
          final prompts = _ScriptedPrompts([0, 0, 2]);
          final spec = await collector(prompts).collect(noDna(), _Host());
          expect(spec.dnaLayers, ['dna_ggsuite']);
          expect(prompts.options.last, [
            'dna_ggsuite (suggested)',
            'Enter a package name or git URL',
            'No DNA',
          ]);
        });

        test('can be none from the menu', () async {
          final prompts = _ScriptedPrompts([1]);
          final spec = await collector(prompts).collect(noDna(), _Host());
          expect(spec.dnaLayers, isEmpty);
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
