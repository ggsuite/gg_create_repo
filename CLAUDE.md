# gg_create_repo

Creates new Dart and TypeScript repositories that are ready for the gg
ticket cycle on their first commit. Runs standalone (`gg_create_repo`) and
inside gg (`gg do create repo`, wired in `gg_multi_workspace`).

## Concept

1. **All or nothing, never half.** First every answer is collected and every
   check runs (`Preflight`). Only then anything is written. Every step of
   `RepoCreator` is idempotent and records itself in
   `<repo>/.gg/create_repo_state.json` (git ignores `.gg/*`). A run that
   stops half way is continued by running the same command again. Nothing
   is ever deleted automatically — least of all on GitHub.
2. **The DNA is the only source of boilerplate.** gg_create_repo writes only
   what no DNA layer delivers: manifest, code, tests, LICENSE, CHANGELOG and
   the build configuration. Skills, workflows, `.vscode`, guides and scripts
   come from the DNA layers the user picks — or are missing on purpose when
   the user picks none.
3. **Ask once, ask first.** Every value can be given as an option. A value
   that is missing is asked for when stdin is a terminal (`-i` asks for
   everything); headless runs fail with the option to pass instead
   (`throwWhenNotATerminal`). No prompt sits between two irreversible steps.
4. **Green from the first commit.** The first commit on `main` is made by
   `gg one do commit --force`: it runs every gg check and writes
   `.gg/gg.json`, so the quick check of the pushed `main` passes.
5. **The host knows the workspace, the package does not.** `RepoHost` gives
   the known organizations, DNA candidates, the target folder, extra checks
   and what happens after the push. `StandaloneHost` is the plain folder;
   `gg_multi_workspace` supplies the ocean and ticket host.

## Steps (`RepoCreator`)

| Step       | What it does                                                |
| ---------- | ----------------------------------------------------------- |
| `scaffold` | Writes the files of the language (`DartScaffold`, `TsScaffold`) |
| `install`  | Adds the dependencies with `dart pub add` / `pnpm add`      |
| `dna`      | `gg dna init` and `gg dna add <layer>` for each chosen layer |
| `commit`   | `gg one do commit --force` — checks, `.gg/gg.json`, commit  |
| `remote`   | `gh repo create`, or takes over an empty existing repo      |
| `push`     | `git push -u origin main`, retried on network errors        |
| `github`   | `scripts/setup-github-repo.js --apply` from the DNA, else the merge settings via `gh api` |
| `host`     | `RepoHost.afterCreate` — e.g. register the org, add to the ticket |

## Rules for changes

- New edge cases get a check in `Preflight` (before anything is written) or
  make their step resumable — never a cleanup that deletes.
- Every value that can be asked for must also be an option.
- Versions start at `0.0.1`, for Dart and TypeScript.
- Network (gh, pub.dev, npm, `pub add`, `pnpm add`) goes through
  `GgProcessWrapper` / `http.Client`, so tests replace only that. Files and
  git are real in tests.

<!-- helix:claude_md:start -->

# gg workflow

This repo is developed ticket by ticket with the `gg` CLI. Follow the
development guide, it tells you when to ask the user and which command
comes next:

@doc/guides/for-ai/ai-dev-guide.md

The steps are also available as skills: `/gg-ticket`, `/gg-commit`,
`/gg-push`, `/gg-publish`, `/gg-cleanup`. `/gg` lists them and says which
one comes next.

<!-- helix:claude_md:end -->
