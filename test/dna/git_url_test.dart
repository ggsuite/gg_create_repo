// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_create_repo/gg_create_repo.dart';
import 'package:test/test.dart';

void main() {
  group('git_url', () {
    test('isGitUrl() follows the rules of helix', () {
      for (final url in [
        'https://x/y',
        'http://x/y',
        'git://x/y',
        'git+ssh://x/y',
        'ssh://x/y',
        'local/path.git',
        'git@github.com:o/r',
      ]) {
        expect(isGitUrl(url), isTrue, reason: url);
      }
      expect(isGitUrl('dna_ggsuite'), isFalse);
      expect(isGitUrl('@tssuite/dna-tssuite'), isFalse);
    });

    test('gitReadableUrl() drops the git+ of npm', () {
      expect(gitReadableUrl('git+https://x/y.git'), 'https://x/y.git');
      expect(gitReadableUrl('git+ssh://git@x/y'), 'ssh://git@x/y');
      expect(gitReadableUrl('https://x/y'), 'https://x/y');
      expect(gitReadableUrl('git+https://x/y.git#v1'), 'https://x/y.git');
    });
  });
}
