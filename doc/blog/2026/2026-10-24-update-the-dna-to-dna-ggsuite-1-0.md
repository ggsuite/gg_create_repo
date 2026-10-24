<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Update the DNA to dna_ggsuite 1.0

## Motivation

- gg_create_repo creates new Dart and TypeScript repositories with DNA,
  GitHub setup and workspace integration
- Its guides, skills, Claude hooks and the managed block of `CLAUDE.md`
  are not written by hand: the DNA generates them from `dna_ggsuite`
- With `dna_ggsuite` 0.5.0, an AI working here followed a workflow without
  a review step and without rules for repos that depend on each other
- The change is small: no code, test or API changes, only the generated
  files and two dependency constraints

## Strategy

- Raise `dna_ggsuite` to ^1.0.0
- Raise `gg_one_commit` to ^2.8.6, the release now in use
- Rebuild the DNA and commit the generated files as they come
- Leave `lib/` and `test/` untouched

## Implementation 1: A review step in the workflow

- The new skill `/gg-review` checks the diff against the scope of the repo,
  writes the blog post, updates README.md and `index.jsonc`, then opens the
  pull requests and runs `/review-light`
- `/gg`, `CLAUDE.md` and the develop guide list it between `/gg-push` and
  `/gg-publish`; `/gg-publish` sends back to it when a post is missing
- The AI dev guide no longer writes blog post, README.md and `index.jsonc`
  at the publish, but at the review, together with the code

## Implementation 2: Rules for repos that depend on each other

- Describe every repo in its own terms: messages, blog posts and code
  comments of a dependency never name the repos that use it
- `/gg-commit` proposes one message per repo and commits each repo on its
  own when repos of the ticket depend on each other
- Keep every repo in its scope: when code does not fit, propose a split, a
  new repo, another repo or a move, and let the user decide when
- Keep `index.jsonc` current: `summary`, `domain` and `interfaces` follow
  the code; a repo without one gets it with its first change

## Implementation 3: Guides and hooks

- The code guides no longer ask for the package prefix in type names; most
  types of this repo, like `Tools` and `GitHub`, already go without it
- Hooks in `.claude/settings.json` keep the prompts in the project
  management repo; `pm-prompts.json` names none, so they stay idle here
- Blog, README and translate guides were current already and stay as they
  are

## Dependency updates

- `dna_ggsuite` 1.0.0 pulls in `dna_gg` 1.0.0 and `dna_clean_code` 0.2.2,
  the sources of the files above
- `gg_one_commit` 2.8.6 only updated its own dependencies; nothing changes
  for this repo

## Result

- The checks for commit and push pass on Windows; `.gg/gg.json` records
  them

## Open Points

- The repo has no `index.jsonc` yet, which the new guide asks of every
  repo of a ticket
- README.md does not follow the README guide: `check-readme.js` misses
  Motivation, Installation, Usage, License and `README.de.md`, and its
  first sentence differs from the `description`
- README.md also documents the command of a package that uses this repo,
  which the rule to describe every repo in its own terms excludes
- `Tools` runs `pnpm`, `npm`, `npx` and `flutter` through the shell on
  Windows by a list of its own; once a `gg_process` release starts batch
  commands through the shell by itself, that list can go
