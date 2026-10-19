// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_process/gg_process.dart';
import 'package:mocktail/mocktail.dart';

import 'repo_spec.dart';

/// What GitHub knows about a repository slug.
enum RemoteState {
  /// No repository with that slug exists.
  missing,

  /// The repository exists but has no commit yet.
  empty,

  /// The repository exists and has commits.
  filled,
}

/// A repository as GitHub reports it.
class RemoteRepo {
  /// Constructor
  const RemoteRepo(this.state, {this.isPrivate});

  /// A realistic repository.
  factory RemoteRepo.example({RemoteState? state, bool? isPrivate}) =>
      RemoteRepo(state ?? RemoteState.missing, isPrivate: isPrivate);

  /// Whether it is missing, empty or has commits.
  final RemoteState state;

  /// Whether it is private; `null` when it is missing.
  final bool? isPrivate;
}

/// The GitHub operations of gg_create_repo, all through the `gh` CLI.
class GitHub {
  /// Constructor
  const GitHub({GgProcessWrapper processWrapper = const GgProcessWrapper()})
    : _process = processWrapper;

  /// A client on the real `gh`; tests pass a fake process wrapper.
  factory GitHub.example({GgProcessWrapper? processWrapper}) =>
      GitHub(processWrapper: processWrapper ?? const GgProcessWrapper());

  // ...........................................................................
  /// Whether `gh` is installed and logged in; the reason otherwise.
  Future<String?> authProblem() async {
    final version = await _gh(['--version']);
    if (version == null) {
      return 'The GitHub CLI »gh« is not installed: https://cli.github.com';
    }
    final status = await _gh(['auth', 'status']);
    if (status == null) {
      return 'The GitHub CLI is not logged in. Run »gh auth login«.';
    }
    return null;
  }

  // ...........................................................................
  /// The login of the user `gh` is logged in as, `null` if unknown.
  Future<String?> login() async =>
      (await _gh(['api', 'user', '--jq', '.login']))?.trim();

  // ...........................................................................
  /// The organizations the logged in user is a member of.
  Future<List<String>> orgs() async {
    final out = await _gh(['api', 'user/orgs', '--jq', '.[].login']);
    return _lines(out);
  }

  // ...........................................................................
  /// Why the logged in user may not create repositories under [owner],
  /// `null` when they may. Unknown answers count as allowed.
  Future<String?> creationProblem(String owner) async {
    final type = await _api('users/$owner', jq: '.type');
    if (type.status == 404) {
      return 'GitHub knows no organization or user »$owner«.';
    }
    if (type.body.trim() == 'User') {
      final me = await login();
      return me == null || me.toLowerCase() == owner.toLowerCase()
          ? null
          : 'Repositories can only be created for yourself ($me), '
                'not for the user »$owner«.';
    }
    final membership = await _api(
      'user/memberships/orgs/$owner',
      jq: '[.state, .role] | @tsv',
    );
    if (membership.status == 404) {
      return 'You are no member of the organization »$owner«.';
    }
    final parts = membership.body.trim().split('\t');
    if (parts.first == 'pending') {
      return 'Your invitation to »$owner« is not accepted yet.';
    }
    if (parts.length > 1 && parts[1] == 'member') {
      final allowed = await _api(
        'orgs/$owner',
        jq: '.members_can_create_repositories',
      );
      if (allowed.body.trim() == 'false') {
        return 'Members of »$owner« may not create repositories.';
      }
    }
    return null;
  }

  // ...........................................................................
  /// What GitHub knows about [slug]. Only status codes count: 404 is
  /// missing, 409 for the commits is empty; anything else throws.
  Future<RemoteRepo> remote(String slug) async {
    final repo = await _api('repos/$slug', jq: '.private');
    if (repo.status == 404) return const RemoteRepo(RemoteState.missing);
    if (repo.status != 200) {
      throw Exception('GitHub could not be asked for $slug: ${repo.body}');
    }
    final isPrivate = repo.body.trim() == 'true';
    final commits = await _api('repos/$slug/commits?per_page=1');
    return switch (commits.status) {
      200 => RemoteRepo(RemoteState.filled, isPrivate: isPrivate),
      409 => RemoteRepo(RemoteState.empty, isPrivate: isPrivate),
      _ => throw Exception(
        'GitHub could not be asked for the commits of $slug: '
        '${commits.body}',
      ),
    };
  }

  // ...........................................................................
  /// Creates the repository of [spec] on GitHub.
  Future<void> create(RepoSpec spec) => _ghOrThrow([
    'repo',
    'create',
    spec.slug,
    spec.isPrivate ? '--private' : '--public',
    '--description',
    spec.description,
  ], 'create ${spec.slug} on GitHub');

  // ...........................................................................
  /// The URL to clone [slug] with, matching the configured git protocol.
  Future<String> cloneUrl(String slug) async {
    final protocol = (await _gh(['config', 'get', 'git_protocol']))?.trim();
    return protocol == 'ssh'
        ? 'git@github.com:$slug.git'
        : 'https://github.com/$slug.git';
  }

  // ...........................................................................
  /// Sets the merge settings gg needs: squash only and auto-merge.
  Future<void> applyMergeSettings(String slug) => _ghOrThrow([
    'api',
    '--method',
    'PATCH',
    'repos/$slug',
    '-F',
    'allow_merge_commit=false',
    '-F',
    'allow_squash_merge=true',
    '-F',
    'allow_rebase_merge=false',
    '-F',
    'allow_auto_merge=true',
    '-F',
    'delete_branch_on_merge=true',
  ], 'apply the merge settings to $slug');

  // ######################
  // Private
  // ######################

  final GgProcessWrapper _process;

  // ...........................................................................
  Future<String?> _gh(List<String> args) async {
    try {
      final result = await _process.run('gh', args, stdoutEncoding: utf8);
      return result.exitCode == 0 ? result.stdout.toString() : null;
    } on ProcessException {
      return null;
    }
  }

  // ...........................................................................
  /// The status and body of `gh api --include [path]`; the status is
  /// `null` when no response arrived at all.
  Future<({int? status, String body})> _api(String path, {String? jq}) async {
    final result = await _process.run('gh', [
      'api',
      '--include',
      path,
      if (jq != null) ...['--jq', jq],
    ], stdoutEncoding: utf8);
    final out = result.stdout.toString().replaceAll('\r\n', '\n');
    final match = RegExp(r'^HTTP/\S+ (\d{3})').firstMatch(out);
    final separator = out.indexOf('\n\n');
    final body = separator < 0
        ? '${result.stderr}'
        : out.substring(separator + 2);
    return (status: int.tryParse(match?.group(1) ?? ''), body: body);
  }

  // ...........................................................................
  Future<void> _ghOrThrow(List<String> args, String what) async {
    final result = await _process.run('gh', args, stdoutEncoding: utf8);
    if (result.exitCode != 0) {
      throw Exception('Could not $what: ${result.stderr}'.trim());
    }
  }

  // ...........................................................................
  List<String> _lines(String? out) => (out ?? '')
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
}

/// Mock for [GitHub].
class MockGitHub extends Mock implements GitHub {}
