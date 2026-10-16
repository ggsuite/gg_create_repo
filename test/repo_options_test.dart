// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_create_repo/gg_create_repo.dart';
import 'package:test/test.dart';

void main() {
  group('RepoOptions', () {
    test('defaults to nothing given', () {
      const options = RepoOptions();
      expect(options.name, isNull);
      expect(options.language, isNull);
      expect(options.org, isNull);
      expect(options.description, isNull);
      expect(options.npmScope, isNull);
      expect(options.isPrivate, isNull);
      expect(options.cli, isNull);
      expect(options.example, isNull);
      expect(options.flutter, isNull);
      expect(options.dnaLayers, isEmpty);
      expect(options.withoutDna, isFalse);
      expect(options.vars, isEmpty);
      expect(options.interactive, isFalse);
    });

    test('example() answers every needed question', () {
      final options = RepoOptions.example();
      expect(options.name, 'gg_example_repo');
      expect(options.language, 'dart');
      expect(options.org, 'ggsuite');
      expect(options.description, isNotNull);
      expect(options.dnaLayers, ['dna_ggsuite']);
      expect(options.withoutDna, isFalse);
      expect(options.interactive, isFalse);
    });

    test('example() takes what a test cares about', () {
      final options = RepoOptions.example(
        name: 'n',
        language: 'ts',
        org: 'o',
        description: 'd',
        dnaLayers: [],
        withoutDna: true,
        interactive: true,
      );
      expect(options.name, 'n');
      expect(options.language, 'ts');
      expect(options.org, 'o');
      expect(options.description, 'd');
      expect(options.dnaLayers, isEmpty);
      expect(options.withoutDna, isTrue);
      expect(options.interactive, isTrue);
    });
  });
}
