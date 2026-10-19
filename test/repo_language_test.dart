// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_create_repo/gg_create_repo.dart';
import 'package:test/test.dart';

void main() {
  group('RepoLanguage', () {
    group('parse()', () {
      test('reads dart, ts and typescript, ignoring case and spaces', () {
        expect(RepoLanguage.parse('dart'), RepoLanguage.dart);
        expect(RepoLanguage.parse(' Dart '), RepoLanguage.dart);
        expect(RepoLanguage.parse('ts'), RepoLanguage.typescript);
        expect(RepoLanguage.parse('TypeScript'), RepoLanguage.typescript);
      });

      test('throws for anything else', () {
        expect(
          () => RepoLanguage.parse('java'),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('»dart« or »ts«'),
            ),
          ),
        );
      });
    });

    test('has a label for the user', () {
      expect(RepoLanguage.dart.label, 'Dart');
      expect(RepoLanguage.typescript.label, 'TypeScript');
    });
  });
}
