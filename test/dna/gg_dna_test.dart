// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_log/gg_log.dart';
import 'package:gg_interact/gg_interact.dart';
import 'package:gg_create_repo/src/dna/gg_dna.dart';
import 'package:helix/helix.dart' as helix;
import 'package:test/test.dart';

/// Prompts that record the questions, answer selects with a fixed index
/// and inputs with the queued [inputs].
class _FakePrompts extends GgPrompts {
  _FakePrompts(this.answer, {List<String> inputs = const []})
    : _inputs = [...inputs];

  final int answer;
  final List<String> _inputs;
  final List<({String prompt, List<String> options})> asked = [];
  final List<({String prompt, String? defaultValue})> inputsAsked = [];

  @override
  Future<int> select({
    required String prompt,
    required List<String> options,
    int initialIndex = 0,
  }) async {
    asked.add((prompt: prompt, options: options));
    return answer;
  }

  @override
  Future<String> input({
    required String prompt,
    String? defaultValue,
    String? initialText,
    bool asMessageEditor = false,
  }) async {
    inputsAsked.add((prompt: prompt, defaultValue: defaultValue));
    return _inputs.removeAt(0);
  }
}

/// Prompts of a platform that cannot draw any, like gg in Wasm.
class _UnsupportedPrompts extends GgPrompts {
  @override
  Future<int> select({
    required String prompt,
    required List<String> options,
    int initialIndex = 0,
  }) async => throw GgPromptsUnsupportedError('select');

  @override
  Future<String> input({
    required String prompt,
    String? defaultValue,
    String? initialText,
    bool asMessageEditor = false,
  }) async => throw GgPromptsUnsupportedError('input');
}

/// Prompts that fail reading the terminal, like gg's own prompts on the
/// redirected stdin Git Bash reports as a terminal.
class _BrokenPrompts extends GgPrompts {
  @override
  Future<int> select({
    required String prompt,
    required List<String> options,
    int initialIndex = 0,
  }) async => throw RangeError('no cursor position');

  @override
  Future<String> input({
    required String prompt,
    String? defaultValue,
    String? initialText,
    bool asMessageEditor = false,
  }) async => throw RangeError('no cursor position');
}

/// Matches the exception helix takes for "nobody to ask".
final _unavailable = throwsA(isA<helix.PromptUnavailableException>());

void main() {
  group('GgDna', () {
    late GgDna command;
    late List<String> messages;
    late GgLog ggLog;

    setUp(() {
      messages = <String>[];
      ggLog = messages.add;
      command = GgDna(ggLog: ggLog);
    });

    test('returns the expected name', () {
      expect(command.name, 'dna');
    });

    test('returns the expected description', () {
      expect(command.description, 'Manage the DNA of a repo');
    });

    test('registers all helix subcommands', () {
      final expected = helix.Helix(ggLog: ggLog).subcommands;

      expect(command.subcommands.keys, expected.keys);
      expect(command.subcommands, hasLength(expected.length));
    });

    test('exposes the same subcommand names and descriptions', () {
      final expected = helix.Helix(ggLog: ggLog).subcommands;

      for (final entry in expected.entries) {
        final actual = command.subcommands[entry.key];

        expect(actual, isNotNull);
        expect(actual!.name, entry.value.name);
        expect(actual.description, entry.value.description);
      }
    });
  });

  group('helixSelectPrompt', () {
    tearDown(() => GgPrompts.current = null);

    test('asks through the prompts of the gg suite', () async {
      final prompts = _FakePrompts(1);
      GgPrompts.current = prompts;

      final index = await helixSelectPrompt(
        prompt: 'Which?',
        options: const ['Dart', 'TypeScript'],
      );

      expect(index, 1);
      expect(prompts.asked, [
        (prompt: 'Which?', options: const ['Dart', 'TypeScript']),
      ]);
    });

    test('does not ask an embedder for a terminal', () async {
      GgPrompts.current = _FakePrompts(0);

      final index = await helixSelectPrompt(
        prompt: 'Which?',
        options: const ['Dart'],
        hasTerminal: () => false,
      );

      expect(index, 0);
    });

    test('has nobody to ask without a terminal', () {
      expect(
        helixSelectPrompt(
          prompt: 'Which?',
          options: const ['Dart'],
          hasTerminal: () => false,
        ),
        _unavailable,
      );
    });

    test('has nobody to ask where stdin cannot be read', () {
      expect(
        helixSelectPrompt(
          prompt: 'Which?',
          options: const ['Dart'],
          hasTerminal: () => throw UnsupportedError('no stdin'),
        ),
        _unavailable,
      );
    });

    test('has nobody to ask where gg cannot draw prompts', () {
      GgPrompts.current = _UnsupportedPrompts();

      expect(
        helixSelectPrompt(prompt: 'Which?', options: const ['Dart']),
        _unavailable,
      );
    });

    test('has nobody to ask where its own prompts cannot read', () {
      final own = _BrokenPrompts();
      GgPrompts.current = own;

      expect(
        helixSelectPrompt(
          prompt: 'Which?',
          options: const ['Dart'],
          hasTerminal: () => true,
          ownPrompts: own,
        ),
        _unavailable,
      );
    });

    test('passes the errors of an embedder on', () {
      GgPrompts.current = _BrokenPrompts();

      expect(
        helixSelectPrompt(prompt: 'Which?', options: const ['Dart']),
        throwsA(isA<RangeError>()),
      );
    });
  });

  group('helixTextPrompt', () {
    tearDown(() => GgPrompts.current = null);

    test('asks through the prompts of the gg suite', () async {
      final prompts = _FakePrompts(0, inputs: ['  acme  ']);
      GgPrompts.current = prompts;

      final answer = await helixTextPrompt(
        prompt: 'dnaGitOrg (required by dna_readme)',
        defaultValue: 'old',
      );

      expect(answer, 'acme');
      expect(prompts.inputsAsked, [
        (prompt: 'dnaGitOrg (required by dna_readme)', defaultValue: 'old'),
      ]);
    });

    test('takes the default for an empty answer', () async {
      GgPrompts.current = _FakePrompts(0, inputs: ['  ']);

      final answer = await helixTextPrompt(prompt: 'Org', defaultValue: 'acme');

      expect(answer, 'acme');
    });

    test('asks again for an empty answer without a default', () async {
      final prompts = _FakePrompts(0, inputs: ['', '', 'acme']);
      GgPrompts.current = prompts;

      final answer = await helixTextPrompt(
        prompt: 'Org',
        hasTerminal: () => true,
        ownPrompts: prompts,
      );

      expect(answer, 'acme');
      expect(prompts.inputsAsked.map((q) => q.prompt), [
        'Org',
        'Org — a value is required',
        'Org — a value is required',
      ]);
    });

    test('has nobody to ask when an embedder answers empty', () {
      GgPrompts.current = _FakePrompts(0, inputs: ['']);

      expect(helixTextPrompt(prompt: 'Org'), _unavailable);
    });

    test('has nobody to ask without a terminal', () {
      expect(
        helixTextPrompt(prompt: 'Org', hasTerminal: () => false),
        _unavailable,
      );
    });

    test('has nobody to ask where gg cannot draw prompts', () {
      GgPrompts.current = _UnsupportedPrompts();

      expect(helixTextPrompt(prompt: 'Org'), _unavailable);
    });

    test('has nobody to ask where its own prompts cannot read', () {
      final own = _BrokenPrompts();
      GgPrompts.current = own;

      expect(
        helixTextPrompt(
          prompt: 'Org',
          hasTerminal: () => true,
          ownPrompts: own,
        ),
        _unavailable,
      );
    });
  });
}
