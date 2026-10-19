# gg_create_repo

Creates new Dart and TypeScript repositories with DNA, GitHub setup and a
pushed `main` that passes the gg checks.

## Inside gg

```bash
gg do create repo                 # asks for everything that is missing
gg do create repo -i              # also asks what has a default
gg do create repo -n gg_foo -l dart -g ggsuite -d "…" --dna dna_ggsuite
```

Where you run it decides where the repository lands:

| Where                           | What happens                                        |
| ------------------------------- | --------------------------------------------------- |
| In a ticket or one of its repos | Created in `.ocean/<org>/<name>`, then added to the ticket like `gg do add` (`--no-add` keeps it out) |
| In the workspace or `.ocean`    | Created in `.ocean/<org>/<name>`; in `.ocean/<org>` the org is preset |
| Outside of a workspace          | Created in `<--output>/<name>`                      |

Inside a workspace `--output` is an error: the repository always goes to
the ocean.

## Standalone

```bash
dart pub global activate gg_create_repo
gg_create_repo -n my-lib -l ts -g tssuite -d "…" --dna @tssuite/dna-tssuite
```

## Options

| Option                | Meaning                                                   |
| --------------------- | --------------------------------------------------------- |
| `-n`, `--name`        | Name of repository, folder and package (Dart: at most 64) |
| `-l`, `--language`    | `dart` or `ts`                                            |
| `-g`, `--org`         | GitHub organization or user — free text or from the menu  |
| `-d`, `--description` | One line; Dart needs 60 to 180 characters (pana)          |
| `--scope`             | TypeScript: npm scope, default: the org                   |
| `--[no-]private`      | Private repository, never published                       |
| `--[no-]cli`          | Dart: a command line interface                            |
| `--[no-]example`      | Dart: an `example/` folder                                |
| `--[no-]flutter`      | Dart: a Flutter package (no CLI)                          |
| `--dna <layer>`       | A DNA layer, package name or git URL; repeat for more     |
| `--without-dna`       | No DNA at all                                             |
| `--var dnaKey=value`  | A DNA variable, like `dnaCompany=Acme`; repeat for more   |
| `-o`, `--output`      | Outside of a workspace: the folder to create it in        |
| `--[no-]add`          | gg, inside a ticket: add the new repository (default on)  |
| `-i`, `--interactive` | Also ask what has a default (visibility, CLI, …)          |
| `-y`, `--yes`         | Do not ask before creating                                |
| `--dry-run`           | Only show the plan and the checks                         |

Without a terminal every missing value is an error naming the option to
pass. The one exception: the DNA named after the org (`dna_<org>`,
`@<scope>/dna-<org>`) is taken without asking when the workspace itself
has it. Required DNA variables (`mustOverride`) are asked for up front, or
must be given with `--var` when running headless — as far as the workspace
has a local copy of the layer. Outside of a workspace, helix asks for them
while it installs the layer.

## What it does

1. **Checks everything first:**
   - git (2.28+, name and email), the gh login and your right to create
     repositories under the org;
   - the tools of the language (`dart`/`flutter`, or `node` and pnpm 10+);
   - the target folder, the GitHub repository (missing, or empty with the
     same visibility), the name on pub.dev/npm;
   - every DNA layer and its required variables;
   - the workspace: package names that exist already, the same name in
     another org, gg command names.
2. **Writes the skeleton** — version `0.0.1`, `CHANGELOG.md` with
   `## Unreleased`, LICENSE (MIT or proprietary), tests at 100 % coverage —
   and adds the dependencies at their latest versions. The Dart SDK and node
   constraints come from the installed tools; TypeScript gets the newest
   version the installed typescript-eslint supports.
3. **Adds the DNA** with `gg dna init` and `gg dna add`.
4. **Runs the gg checks** and records them in `.gg/gg.json`, so the quick
   check of `main` is green from the first push.
5. **Creates the GitHub repository** (or takes over an empty one), pushes
   `main` and runs the DNA's `setup-github-repo.js`: squash merges,
   auto-merge and the branch rules. Without that script only the merge
   settings are applied, and `main` stays unprotected.

A run that stops half way continues where it stopped: run the command again
with the same name, language and org; everything else is taken from the
earlier run. Nothing is ever deleted.
