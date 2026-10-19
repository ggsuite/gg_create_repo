// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_create_repo/gg_create_repo.dart';
import 'package:gg_create_repo/src/dna/dna_variables.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Finds layers in folders below [root], named like the layer.
class _Host extends StandaloneHost {
  _Host(this.root) : super(outputDir: root);

  final Directory root;

  @override
  Directory? layerDir(String layer) {
    if (layer.contains(':')) return null;
    final dir = Directory(p.join(root.path, layer));
    return dir.existsSync() ? dir : null;
  }
}

void main() {
  late Directory root;
  late _Host host;
  const variables = DnaVariables();

  /// Writes the layer [name] with its parents and `mustOverride` flags.
  void layer(
    String name, {
    List<String> parents = const [],
    Map<String, bool> mustOverride = const {},
  }) {
    final flags = mustOverride.entries
        .map((e) => '"${e.key}": ${e.value}')
        .join(', ');
    File(p.join(root.path, name, 'dna', '_dna.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        '{\n'
        '  // A DNA config, comments allowed.\n'
        '  "version": 2,\n'
        '  "layers": [${parents.map((l) => '"$l"').join(', ')}],\n'
        '  "mustOverride": {$flags},\n'
        '}\n',
      );
  }

  ({List<MissingDnaVariable> missing, List<String> unresolved}) missing(
    List<String> layers, {
    Map<String, String> given = const {},
  }) => variables.missing(layers: layers, given: given, host: host);

  setUp(() {
    root = Directory.systemTemp.createTempSync('dna_variables_');
    host = _Host(root);
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('DnaVariables', () {
    test('names the variables a layer requires', () {
      layer('dna_gg', mustOverride: {'dnaCompany': true, 'dnaOther': false});

      final result = missing(['dna_gg']);

      expect(result.missing.map((v) => v.name), ['dnaCompany']);
      expect(result.missing.single.requiredBy, 'dna_gg');
      expect(result.unresolved, isEmpty);
    });

    test('leaves out the variables that are given', () {
      layer('dna_gg', mustOverride: {'dnaCompany': true});
      expect(missing(['dna_gg'], given: {'dnaCompany': 'x'}).missing, isEmpty);
    });

    test('passes a requirement on to the children', () {
      layer('dna_gg', mustOverride: {'dnaCompany': true});
      layer('dna_mid', parents: ['dna_gg'], mustOverride: {'dnaOwn': true});

      final result = missing(['dna_mid']);

      expect(
        {for (final v in result.missing) v.name: v.requiredBy},
        {'dnaCompany': 'dna_gg', 'dnaOwn': 'dna_mid'},
      );
    });

    test('a child lifts the requirement with false', () {
      layer('dna_gg', mustOverride: {'dnaCompany': true});
      layer(
        'dna_ggsuite',
        parents: ['dna_gg'],
        mustOverride: {'dnaCompany': false},
      );
      expect(missing(['dna_ggsuite']).missing, isEmpty);
    });

    test('a later requirement replaces the layer that names it', () {
      layer('dna_gg', mustOverride: {'dnaCompany': true});
      layer(
        'dna_strict',
        parents: ['dna_gg'],
        mustOverride: {'dnaCompany': true},
      );
      expect(missing(['dna_strict']).missing.single.requiredBy, 'dna_strict');
    });

    test('visits a shared parent once', () {
      layer('dna_gg', mustOverride: {'dnaCompany': true});
      layer('dna_a', parents: ['dna_gg']);
      layer('dna_b', parents: ['dna_gg']);

      final result = missing(['dna_a', 'dna_b']);

      expect(result.missing.map((v) => v.name), ['dnaCompany']);
    });

    test('stops at a cycle', () {
      layer('dna_a', parents: ['dna_b'], mustOverride: {'dnaX': true});
      layer('dna_b', parents: ['dna_a']);

      final result = missing(['dna_a']);

      expect(result.missing.map((v) => v.name), ['dnaX']);
    });

    test('lists layers without a local copy', () {
      layer('dna_known', parents: ['dna_remote']);

      final result = missing(['dna_known', 'git@github.com:x/dna_x.git']);

      expect(result.unresolved, ['dna_remote', 'git@github.com:x/dna_x.git']);
      expect(result.missing, isEmpty);
    });

    test('lists a layer whose config cannot be read', () {
      Directory(p.join(root.path, 'dna_broken', 'dna'))
          .createSync(recursive: true);
      expect(missing(['dna_broken']).unresolved, ['dna_broken']);
    });

    test('a layer without dna folder requires nothing', () {
      Directory(p.join(root.path, 'gg_args')).createSync();
      final result = missing(['gg_args']);
      expect(result.missing, isEmpty);
      expect(result.unresolved, isEmpty);
    });

    test('example() finds nothing without layers', () {
      expect(
        DnaVariables.example()
            .missing(layers: const [], given: const {}, host: host)
            .missing,
        isEmpty,
      );
    });
  });

  group('MissingDnaVariable', () {
    test('example() has realistic defaults and takes values', () {
      final variable = MissingDnaVariable.example();
      expect(variable.name, 'dnaCompany');
      expect(variable.requiredBy, 'dna_gg');
      final other = MissingDnaVariable.example(name: 'a', requiredBy: 'b');
      expect([other.name, other.requiredBy], ['a', 'b']);
    });
  });
}
