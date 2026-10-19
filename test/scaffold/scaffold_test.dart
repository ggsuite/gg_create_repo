// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_create_repo/gg_create_repo.dart';
import 'package:gg_create_repo/src/scaffold/dart_scaffold.dart';
import 'package:gg_create_repo/src/scaffold/scaffold.dart';
import 'package:gg_create_repo/src/scaffold/ts_scaffold.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('Scaffold', () {
    group('forSpec()', () {
      late Directory dir;

      setUp(() => dir = Directory.systemTemp.createTempSync('scaffold_'));
      tearDown(() => dir.deleteSync(recursive: true));

      String read(String path) =>
          File(p.join(dir.path, path)).readAsStringSync();

      test('picks the Dart scaffold with the Dart SDK given', () {
        final spec = RepoSpec.example();
        final scaffold = Scaffold.forSpec(spec, dartSdk: '3.7.1');
        expect(scaffold, isA<DartScaffold>());

        scaffold.write(dir, spec);
        expect(read('pubspec.yaml'), contains('sdk: ">=3.7.0 <4.0.0"'));
      });

      test('picks the TypeScript scaffold with the node given', () {
        final spec = RepoSpec.example(
          language: RepoLanguage.typescript,
          name: 'my-lib',
        );
        final scaffold = Scaffold.forSpec(spec, nodeMajor: 24);
        expect(scaffold, isA<TsScaffold>());

        scaffold.write(dir, spec);
        expect(read('package.json'), contains('"node": ">=24"'));
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
  });
}
