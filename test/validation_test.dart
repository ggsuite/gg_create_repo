// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_create_repo/gg_create_repo.dart';
import 'package:gg_create_repo/src/validation.dart';
import 'package:test/test.dart';

void main() {
  final v = Validation.example();
  const dart = RepoLanguage.dart;
  const ts = RepoLanguage.typescript;

  group('Validation', () {
    group('name()', () {
      test('accepts valid names', () {
        expect(v.name('gg_create_repo', dart), isNull);
        expect(v.name('my-lib.js', ts), isNull);
        expect(v.name('1lib', ts), isNull);
      });

      test('rejects empty and too long names', () {
        expect(v.name('', dart), contains('empty'));
        expect(v.name('a' * 64, dart), isNull);
        expect(v.name('a' * 65, dart), contains('64'));
        expect(v.name('a' * 100, ts), isNull);
        expect(v.name('a' * 101, ts), contains('100'));
      });

      test('rejects Windows device names', () {
        expect(v.name('con', dart), contains('Windows'));
        expect(v.name('nul.ts', ts), contains('Windows'));
      });

      test('rejects invalid Dart names and reserved words', () {
        expect(v.name('Gg', dart), contains('Dart package name'));
        expect(v.name('1gg', dart), contains('Dart package name'));
        expect(v.name('my-lib', dart), contains('Dart package name'));
        expect(v.name('class', dart), contains('reserved'));
      });

      test('rejects the dependencies of the skeleton', () {
        expect(v.name('lints', dart), contains('dependency of the skeleton'));
        expect(v.name('gg_log', dart), contains('dependency'));
        expect(v.name('path', dart), contains('dependency'));
        expect(v.name('vector_math', dart), contains('dependency'));
      });

      test('rejects names whose class clashes with another one', () {
        expect(v.name('string', dart), contains('»String«'));
        expect(v.name('my_command', dart), contains('»MyCommand«'));
        expect(v.name('gg_command_runner', dart), contains('clash'));
      });

      test('rejects TypeScript names that hide a global type', () {
        expect(v.name('partial', ts), contains('»Partial«'));
        expect(v.name('promise', ts), contains('global'));
        expect(v.name('my-promise', ts), isNull);
      });

      test('rejects the TypeScript name index', () {
        expect(v.name('index', ts), contains('src/index.ts'));
      });

      test('rejects invalid npm names', () {
        expect(v.name('My', ts), contains('npm package name'));
        expect(v.name('.x', ts), contains('npm package name'));
        expect(v.name('_x', ts), contains('npm package name'));
        expect(v.name('a b', ts), contains('npm package name'));
      });
    });

    group('org()', () {
      test('accepts GitHub owners', () {
        expect(v.org('ggsuite'), isNull);
        expect(v.org('audanika-private'), isNull);
        expect(v.org('A1'), isNull);
      });

      test('rejects invalid owners', () {
        expect(v.org(''), contains('empty'));
        expect(v.org('a' * 40), contains('39'));
        expect(v.org('a--b'), contains('39'));
        expect(v.org('-a'), contains('39'));
        expect(v.org('a_b'), contains('39'));
      });
    });

    group('description()', () {
      test('accepts a line of the right length', () {
        expect(v.description('x' * 60, dart), isNull);
        expect(v.description('short is fine', ts), isNull);
      });

      test('rejects several lines', () {
        expect(v.description('a\nb', ts), contains('single line'));
        expect(v.description('a\rb', ts), contains('single line'));
      });

      test('needs 60 to 180 characters for Dart', () {
        expect(v.description('x' * 59, dart), contains('has 59'));
        expect(v.description('x' * 181, dart), contains('has 181'));
        expect(v.description('x' * 180, dart), isNull);
      });

      test('needs 1 to 350 characters for TypeScript', () {
        expect(v.description('', ts), contains('empty'));
        expect(v.description('x' * 351, ts), contains('350'));
        expect(v.description('x' * 350, ts), isNull);
      });
    });

    group('npmScope()', () {
      test('accepts valid scopes', () {
        expect(v.npmScope('tssuite'), isNull);
        expect(v.npmScope('my-org_1'), isNull);
      });

      test('rejects invalid scopes', () {
        expect(v.npmScope('@x'), contains('npm scope'));
        expect(v.npmScope('Upper'), contains('npm scope'));
        expect(v.npmScope('.x'), contains('npm scope'));
      });
    });

    group('variable()', () {
      test('accepts DNA variables with a value', () {
        expect(v.variable('dnaCompany=Acme'), isNull);
        expect(v.variable('dnaA1=b=c'), isNull);
        expect(v.variable(' dnaCompany = Acme '), isNull);
      });

      test('rejects pairs without a key', () {
        expect(v.variable('ab'), contains('key=value'));
        expect(v.variable('=b'), contains('key=value'));
      });

      test('rejects keys helix does not read', () {
        expect(v.variable('company=Acme'), contains('no DNA variable'));
        expect(v.variable('dnacompany=Acme'), contains('dnaProjectName'));
        expect(v.variable('dna_company=Acme'), contains('no DNA variable'));
      });

      test('rejects empty values', () {
        expect(v.variable('dnaCompany='), contains('needs a value'));
        expect(v.variable('dnaCompany=  '), contains('needs a value'));
      });
    });
  });
}
