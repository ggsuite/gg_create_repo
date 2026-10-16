// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_create_repo/gg_create_repo.dart';
import 'package:test/test.dart';

void main() {
  group('Scaffold', () {
    group('forSpec()', () {
      test('picks the scaffold of the language', () {
        expect(Scaffold.forSpec(RepoSpec.example()), isA<DartScaffold>());
        expect(
          Scaffold.forSpec(RepoSpec.example(language: RepoLanguage.typescript)),
          isA<TsScaffold>(),
        );
      });
    });

    group('pascalCase()', () {
      test('joins the parts of snake, kebab and dotted names', () {
        expect(Scaffold.pascalCase('gg_create_repo'), 'GgCreateRepo');
        expect(Scaffold.pascalCase('my-lib'), 'MyLib');
        expect(Scaffold.pascalCase('a..b__c'), 'ABC');
      });

      test('prefixes a leading digit', () {
        expect(Scaffold.pascalCase('1st-lib'), 'Repo1stLib');
      });
    });

    group('quoted()', () {
      test('escapes backslashes, quotes and dollars', () {
        expect(Scaffold.quoted('plain'), "'plain'");
        expect(Scaffold.quoted(r"it's \ $x"), r"'it\'s \\ \$x'");
      });
    });
  });
}
