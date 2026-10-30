<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# New repos follow the git protocol gh has set for github.com

## Motivation

- After creating the repository on GitHub, gg_create_repo adds the remote
  `origin` and pushes `main`.
- The remote URL should match how the user talks to GitHub: SSH users get
  `git@github.com:<org>/<name>.git`, everybody else
  `https://github.com/<org>/<name>.git`.
- gg_create_repo read that choice with `gh config get git_protocol`.
- `gh auth login` does not store the protocol globally, though. It stores
  it for the host, in `hosts.yml` under `github.com`.
- The call without a host only saw the global default, which is `https`.
  So SSH users got an https remote and had to switch it by hand.

## Strategy

- Ask gh for the protocol of the host the repository lives on.
- Let gh handle the fallback: a host without its own setting answers with
  the global one.
- Keep everything else as it was: one gh call, `ssh` selects SSH,
  anything else or a failing call selects https.

## Asking gh for the host

- `GitHub.cloneUrl` in `lib/src/github.dart` now runs
  `gh config get git_protocol --host github.com`.
- Its only caller, `RepoCreator._push`, is unchanged. It still adds or
  updates `origin` with the URL and pushes with retries.
- A repository that is resumed after a failed push gets its remote set
  again from the current gh setting.

## Tests

- The `cloneUrl()` test in `test/github_test.dart` now also checks the
  exact gh arguments, including `--host github.com`.
- It still covers both outcomes: `ssh` gives the SSH URL, a failing gh call
  gives the https URL.

## Open Points

- gg_create_repo only knows github.com. GitHub Enterprise hosts or
  `GH_HOST` are not supported, for the protocol nor for the repository
  itself.
