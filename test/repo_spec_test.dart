// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_create_repo/gg_create_repo.dart';
import 'package:test/test.dart';

void main() {
  group('RepoSpec', () {
    test('example() has realistic defaults', () {
      final spec = RepoSpec.example();
      expect(spec.name, 'gg_example_repo');
      expect(spec.language, RepoLanguage.dart);
      expect(spec.org, 'ggsuite');
      expect(spec.description.length, greaterThanOrEqualTo(60));
      expect(spec.isPrivate, isFalse);
      expect(spec.dnaLayers, ['dna_ggsuite']);
      expect(spec.vars, isEmpty);
      expect(spec.cli, isFalse);
      expect(spec.example, isTrue);
      expect(spec.flutter, isFalse);
    });

    test('example() takes every value', () {
      final spec = RepoSpec.example(
        name: 'x',
        language: RepoLanguage.typescript,
        org: 'Org',
        description: 'd',
        isPrivate: true,
        dnaLayers: [],
        vars: {'a': 'b'},
        cli: true,
        example: false,
        flutter: true,
        npmScope: 'scope',
      );
      expect(spec.name, 'x');
      expect(spec.language, RepoLanguage.typescript);
      expect(spec.org, 'Org');
      expect(spec.description, 'd');
      expect(spec.isPrivate, isTrue);
      expect(spec.dnaLayers, isEmpty);
      expect(spec.vars, {'a': 'b'});
      expect(spec.cli, isTrue);
      expect(spec.example, isFalse);
      expect(spec.flutter, isTrue);
      expect(spec.npmScope, 'scope');
    });

    test('survives toJson() and fromJson()', () {
      final spec = RepoSpec.example(
        language: RepoLanguage.typescript,
        vars: {'k': 'v'},
        npmScope: 'scope',
        cli: true,
      );
      final copy = RepoSpec.fromJson(spec.toJson());
      expect(copy.toJson(), spec.toJson());
      expect(copy.language, RepoLanguage.typescript);
      expect(copy.npmScope, 'scope');
    });

    test('copyWith() replaces DNA and vars, keeps the rest', () {
      final spec = RepoSpec.example(npmScope: 'scope');
      final copy = spec.copyWith(dnaLayers: ['x'], vars: {'a': 'b'});
      expect(copy.dnaLayers, ['x']);
      expect(copy.vars, {'a': 'b'});
      expect(copy.name, spec.name);
      expect(copy.npmScope, 'scope');

      final same = spec.copyWith();
      expect(same.toJson(), spec.toJson());
    });

    test('derives slug, scope, package name and URL', () {
      final dart = RepoSpec.example(org: 'GgSuite', name: 'gg_x');
      expect(dart.slug, 'GgSuite/gg_x');
      expect(dart.npmScope, 'ggsuite');
      expect(dart.packageName, 'gg_x');
      expect(dart.webUrl, 'https://github.com/GgSuite/gg_x');

      final ts = RepoSpec.example(
        language: RepoLanguage.typescript,
        name: 'my-lib',
        org: 'TsSuite',
      );
      expect(ts.packageName, '@tssuite/my-lib');

      final scoped = RepoSpec.example(
        language: RepoLanguage.typescript,
        name: 'my-lib',
        npmScope: 'other',
      );
      expect(scoped.packageName, '@other/my-lib');
    });
  });
}
