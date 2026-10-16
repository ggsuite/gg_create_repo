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

/// The GitHub operations of gg_create_repo, all through the `gh` CLI.
class GitHub {
  /// Constructor
  const GitHub({GgProcessWrapper processWrapper = const GgProcessWrapper()})
    : _process = processWrapper;

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
  /// `User`, `Organization`, or `null` when no such owner exists.
  Future<String?> ownerType(String owner) async =>
      (await _gh(['api', 'users/$owner', '--jq', '.type']))?.trim();

  // ...........................................................................
  /// Whether the repository [slug] is missing, empty or has commits.
  ///
  /// Only GitHub's own answers count — 404 is missing, 409 is empty. Any
  /// other failure, a network error say, throws instead of guessing.
  Future<RemoteState> state(String slug) async {
    final repo = await _process.run('gh', [
      'api',
      'repos/$slug',
      '--jq',
      '.full_name',
    ], stdoutEncoding: utf8);
    if (repo.exitCode != 0) {
      if (_isHttp(repo, 404)) return RemoteState.missing;
      throw Exception('GitHub could not be asked for $slug: ${repo.stderr}');
    }
    final commits = await _process.run('gh', [
      'api',
      'repos/$slug/commits?per_page=1',
    ], stdoutEncoding: utf8);
    if (commits.exitCode == 0) return RemoteState.filled;
    if (_isHttp(commits, 409)) return RemoteState.empty;
    throw Exception(
      'GitHub could not be asked for the commits of $slug: ${commits.stderr}',
    );
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
  Future<void> _ghOrThrow(List<String> args, String what) async {
    final result = await _process.run('gh', args, stdoutEncoding: utf8);
    if (result.exitCode != 0) {
      throw Exception('Could not $what: ${result.stderr}'.trim());
    }
  }

  // ...........................................................................
  static bool _isHttp(ProcessResult result, int status) =>
      '${result.stderr}${result.stdout}'.contains('HTTP $status');

  // ...........................................................................
  List<String> _lines(String? out) => (out ?? '')
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
}

/// Mock for [GitHub].
class MockGitHub extends Mock implements GitHub {}
