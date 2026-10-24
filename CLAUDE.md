# gg_create_repo

Creates new Dart and TypeScript repositories that are ready for the gg
ticket cycle on their first commit. Runs standalone (`gg_create_repo`) and
inside gg (`gg do create repo`, wired in `gg_multi_workspace`).

## Concept

1. **All or nothing, never half.** First every answer is collected and every
   check runs (`Preflight`). Only then anything is written. The state of a
   run (`<repo>/.gg/create_repo_state.json`, git ignores `.gg/*`) is written
   before the first step and after each one, and every step is idempotent:
   running the same command again continues where it stopped. Language, org
   and name find the earlier run; every other value comes from its state and
   is not asked again. Options given on a rerun must match it; `--var` values
   are added until the DNA step is done, later they are an error.
   Nothing is ever deleted automatically — least of all on GitHub.
2. **The DNA is the only source of boilerplate.** gg_create_repo writes only
   what no DNA layer delivers: manifest, code, tests, LICENSE, CHANGELOG and
   the build configuration. Skills, workflows, `.vscode`, guides and scripts
   come from the DNA layers the user picks — or are missing on purpose when
   the user picks none.
3. **Ask once, ask first.** Every value can be given as an option. A value
   that is missing is asked for when stdin and stdout are a terminal (`-i`
   also asks what has a default); headless runs fail with the option to
   pass. This includes the `mustOverride` variables of the chosen DNA
   layers, as far as the host has local copies of them (the ocean does, a
   plain folder does not); helix asks for the others when it installs them.
   Headless, only a DNA layer the host itself offers is taken without
   asking: a registry name alone could belong to anybody.
4. **Green from the first push.** The skeleton is committed as `Initial
   version`, `gg dna add` commits the generated DNA. What is left is
   committed, gg's `CanCommit` runs every check and `DoCommit --force`
   records it in `.gg/gg.json`. gg leaves that file uncommitted on `main`,
   so it is amended into the last commit before the push — the quick check
   of `main` passes.
5. **The host knows the workspace, the package does not.** `RepoHost` gives
   the known organizations, DNA candidates and their local folders, the
   target folder, extra checks and what happens after the push.
   `StandaloneHost` is a plain folder; `gg_multi_workspace` supplies the
   ocean and ticket host.

## Steps (`RepoCreator`, `CreateStep`)

| Step            | What it does                                                 |
| --------------- | ------------------------------------------------------------ |
| `scaffold`      | Writes the files of the language and runs `git init`         |
| `install`       | `dart pub add` / `flutter pub add` + `dart format`, or `pnpm add` with the TypeScript of the typescript-eslint range |
| `initialCommit` | Commits the skeleton, so the DNA step finds a clean tree     |
| `dna`           | `gg dna init --quiet`, drops the layers init proposes for the dependencies (gg_args, gg_log), then `gg dna add <layer>` for each chosen layer |
| `check`         | Commits what is left, `CanCommit` + `DoCommit --force`, amends `.gg/gg.json` |
| `remote`        | `gh repo create`, or takes over an empty repo of the same visibility |
| `push`          | `git push -u origin main`, retried on network errors         |
| `github`        | `scripts/setup-github-repo.js --apply` from the DNA, else (or when it fails) the merge settings via `gh api` |
| `host`          | `RepoHost.afterCreate` — e.g. register the org, add to the ticket |

## Where things live

- `GgDna`, `helixDnaRunner`, `RunDna` (`lib/src/dna/gg_dna.dart`): the
  bridge from helix' commands and prompts to gg's. `gg dna`, the workspace
  DNA and this package all use it.
- `isGitUrl`, `gitReadableUrl` (`lib/src/dna/git_url.dart`): helix' rules for
  a layer that is a git URL; the workspace host uses them too.
- `DnaVariables`: the `mustOverride` rules of helix, applied to local copies
  of the layers before they are installed.
- Prompts and the terminal check come from `gg_interact`.

## Rules for changes

- New edge cases get a check in `Preflight` (before anything is written) or
  make their step resumable — never a cleanup that deletes.
- Every value that can be asked for must also be an option.
- Generated code imports other packages with `show`, so a package name can
  only clash with `dart:core` and the skeleton (`Validation`).
- `Validation.skeletonDependencies` lists every package a skeleton
  resolves; the integration test fails when it misses one.
- Versions start at `0.0.1`, for Dart and TypeScript.
- Tool versions are read from the tools that build the package (`dart`,
  `flutter --machine`, `node`, the typescript-eslint peer range), not
  hardcoded.
- Network (gh, pub.dev, npm, `pub add`, `pnpm add`) goes through
  `GgProcessWrapper` / `http.Client`, so tests replace only that. Files and
  git are real in tests, with a test git identity.
- `test/integration/dart_skeleton_test.dart` runs gg's real checks on the
  Dart skeleton; `tool/smoke.dart` creates a real repository end to end
  against a local bare repository (also for TypeScript).

<!-- helix:claude_md:start -->

# gg workflow

This repo is developed ticket by ticket with the `gg` CLI. Follow the
development guide, it tells you when to ask the user and which command
comes next:

@doc/guides/for-ai/ai-dev-guide.md

The steps are also available as skills: `/gg-ticket`, `/gg-commit`,
`/gg-push`, `/gg-review`, `/gg-publish`, `/gg-cleanup`. `/gg` lists them
and says which one comes next.

<!-- helix:claude_md:end -->
