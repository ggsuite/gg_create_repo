// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_interact/gg_interact.dart';
import 'package:helix/helix.dart' as helix;

/// Answers the questions of helix through the prompts of the gg suite —
/// the same menus `gg do publish` draws, and in an embedded gg whatever
/// the embedder assigned to [GgPrompts.current].
///
/// Throws [helix.PromptUnavailableException] when there is nobody to ask
/// (see [_ask]), so helix falls back as it does for its own terminal
/// prompts. [hasTerminal] and [ownPrompts] replace stdin and the prompts
/// gg draws itself in tests.
Future<int> helixSelectPrompt({
  required String prompt,
  required List<String> options,
  HasTerminal hasTerminal = stdioHasTerminal,
  GgPrompts? ownPrompts,
}) => _ask(
  (prompts) => prompts.select(prompt: prompt, options: options),
  hasTerminal: hasTerminal,
  ownPrompts: ownPrompts,
);

/// Asks helix's text questions — the variables a layer marks
/// `mustOverride` — through the input prompt of the gg suite. An empty
/// answer takes [defaultValue]; without one, gg's own prompts ask again
/// and say a value is required: helix expects a value, never an empty
/// string. An embedder answering empty without a default has nobody
/// behind it to ask again — at the end of its input, say.
///
/// Throws [helix.PromptUnavailableException] when there is nobody to ask,
/// like [helixSelectPrompt].
Future<String> helixTextPrompt({
  required String prompt,
  String? defaultValue,
  HasTerminal hasTerminal = stdioHasTerminal,
  GgPrompts? ownPrompts,
}) async {
  var question = prompt;
  while (true) {
    final answer = (await _ask(
      (prompts) => prompts.input(prompt: question, defaultValue: defaultValue),
      hasTerminal: hasTerminal,
      ownPrompts: ownPrompts,
    )).trim();
    if (answer.isNotEmpty) return answer;
    if (defaultValue != null) return defaultValue;
    if (!_isOwn(GgPrompts.current, ownPrompts)) {
      throw const helix.PromptUnavailableException('the answer was empty');
    }
    question = '$prompt — a value is required';
  }
}

/// Asks [question] with [GgPrompts.current] and turns "nobody to ask" into
/// the [helix.PromptUnavailableException] helix expects:
///
/// - a platform that cannot draw prompts (Wasm without an embedder),
/// - gg's own prompts — [ownPrompts], by default
///   [GgPrompts.defaultPrompts] — where stdin or stdout is no terminal:
///   they would wait forever in CI, in a pipe or behind a null device, or
///   draw into a redirected output where nobody sees them,
/// - gg's own prompts failing to read the terminal: Git Bash on Windows
///   reports a terminal for redirected input, and reading it then fails.
///
/// An embedder that assigned [GgPrompts.current] answers without a
/// terminal: it is never checked, and its errors are its own.
Future<T> _ask<T>(
  Future<T> Function(GgPrompts prompts) question, {
  required HasTerminal hasTerminal,
  required GgPrompts? ownPrompts,
}) async {
  final prompts = GgPrompts.current;
  final isOwn = _isOwn(prompts, ownPrompts);
  if (isOwn) _ensureTerminal(hasTerminal);
  try {
    return await question(prompts);
  } on GgPromptsUnsupportedError catch (e) {
    throw helix.PromptUnavailableException('$e');
  } on Object catch (e) {
    if (!isOwn) rethrow;
    throw helix.PromptUnavailableException('the terminal cannot be read: $e');
  }
}

/// Whether [prompts] are the ones gg draws itself — [ownPrompts], by
/// default [GgPrompts.defaultPrompts] — rather than an embedder's.
bool _isOwn(GgPrompts prompts, GgPrompts? ownPrompts) =>
    identical(prompts, ownPrompts ?? GgPrompts.defaultPrompts);

/// Throws [helix.PromptUnavailableException] unless [hasTerminal] says
/// the prompts have a terminal.
void _ensureTerminal(HasTerminal hasTerminal) {
  final bool isTerminal;
  try {
    isTerminal = hasTerminal();
  } on Object {
    // A platform without stdin (Wasm) has nobody to ask either.
    throw const helix.PromptUnavailableException('stdin cannot be read');
  }
  if (!isTerminal) {
    throw const helix.PromptUnavailableException(
      'stdin or stdout is not a terminal',
    );
  }
}

/// Command that exposes all helix subcommands under the `dna` namespace.
class GgDna extends Command<void> {
  /// Create the command and register all helix subcommands.
  GgDna({required this.ggLog}) {
    helix.Helix(
      ggLog: ggLog,
      selectPrompt: helixSelectPrompt,
      textPrompt: helixTextPrompt,
    ).subcommands.values.forEach(addSubcommand);
  }

  /// The log function.
  final GgLog ggLog;

  @override
  String get name => 'dna';

  @override
  String get description => 'Manage the DNA of a repo';
}

/// Runs one `gg dna` command — `init`, `add` or `build` — with its args;
/// the seam that lets tests skip the package managers and the network.
typedef RunDna = Future<void> Function(List<String> args);

/// The `gg dna` runner outside of tests: helix' own commands with the
/// prompts of the gg suite, what `gg dna` itself runs.
RunDna helixDnaRunner(GgLog ggLog) {
  final runner = CommandRunner<dynamic>('gg', 'gg')
    ..addCommand(GgDna(ggLog: ggLog));
  return (args) => runner.run(['dna', ...args]);
}
