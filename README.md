# gg_create_repo

Creates new Dart and TypeScript repositories with DNA, GitHub setup and a
first commit that passes the gg checks.

## Inside gg

```bash
gg do create repo                 # asks for everything that is missing
gg do create repo -i              # asks for everything
gg do create repo -n gg_foo -l dart -g ggsuite -d "…" --dna dna_ggsuite
```

Where you run it decides where the repository lands:

| Where                          | What happens                                        |
| ------------------------------ | --------------------------------------------------- |
| In a ticket or one of its repos | Created in `.ocean/<org>/<name>`, then added to the ticket like `gg do add` (`--no-add` keeps it out) |
| In the workspace or `.ocean`   | Created in `.ocean/<org>/<name>`; in `.ocean/<org>` the org is preset |
| Outside of a workspace         | Created in `<--output>/<name>`                      |

## Standalone

```bash
dart pub global activate gg_create_repo
gg_create_repo -n my-lib -l ts -g tssuite -d "…" --dna @tssuite/dna-tssuite
```

## Options

| Option                    | Meaning                                                   |
| ------------------------- | --------------------------------------------------------- |
| `-n`, `--name`            | Name of repository, folder and package                    |
| `-l`, `--language`        | `dart` or `ts`                                            |
| `-g`, `--org`             | GitHub organization or user — free text or from the menu  |
| `-d`, `--description`     | One line; Dart needs 60 to 180 characters (pana)          |
| `--scope`                 | TypeScript: npm scope, default: the org                   |
| `--[no-]private`          | Private repository, never published                       |
| `--[no-]cli`              | Dart: a command line interface                            |
| `--[no-]example`          | Dart: an `example/` folder                                |
| `--[no-]flutter`          | Dart: a Flutter package                                   |
| `--dna <layer>`           | A DNA layer, package name or git URL; repeat for more     |
| `--without-dna`           | No DNA at all                                             |
| `--var key=value`         | A DNA variable; repeat for more                           |
| `-o`, `--output`          | Standalone: the folder to create the repository in        |
| `-i`, `--interactive`     | Ask every question                                        |
| `-y`, `--yes`             | Do not ask before creating                                |
| `--dry-run`               | Only show the plan and the checks                         |

Without a terminal every missing value is an error naming the option to
pass. The DNA proposed by default is the one named after the org
(`dna_<org>`, `@<scope>/dna-<org>`) when it exists.

## What it does

1. **Checks everything first:** git (2.28+, name, email), gh login, the
   tools of the language, the target folder, the GitHub owner and
   repository, the name on pub.dev/npm, every DNA layer, and the
   workspace (name taken by another package, gg command names).
2. **Writes the skeleton** — version `0.0.1`, `CHANGELOG.md` with
   `## Unreleased`, LICENSE (MIT or proprietary), tests at 100 % coverage —
   and adds the dependencies at their latest versions. TypeScript gets the
   newest TypeScript that the installed typescript-eslint supports.
3. **Adds the DNA** with `gg dna init` and `gg dna add`.
4. **Runs the gg checks** and records them in `.gg/gg.json`, so the quick
   check of `main` is green from the first push.
5. **Creates the GitHub repository** (or takes over an empty one), pushes
   `main` and applies the merge settings and branch rules.

A run that stops half way continues where it stopped: run the same command
again. Nothing is ever deleted.
