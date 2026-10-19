// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:helix/helix.dart' as helix;

import '../repo_host.dart';

/// A DNA variable the new repository has to set itself.
class MissingDnaVariable {
  /// Constructor
  const MissingDnaVariable({required this.name, required this.requiredBy});

  /// A realistic variable.
  factory MissingDnaVariable.example({String? name, String? requiredBy}) =>
      MissingDnaVariable(
        name: name ?? 'dnaCompany',
        requiredBy: requiredBy ?? 'dna_gg',
      );

  /// The variable, e.g. `dnaCompany`.
  final String name;

  /// The layer whose `mustOverride: true` asks for it.
  final String requiredBy;
}

/// Finds the `mustOverride` variables of the chosen DNA layers before
/// anything is installed, from the local copies the host knows.
class DnaVariables {
  /// Constructor
  const DnaVariables();

  /// The finder; it has nothing to configure.
  factory DnaVariables.example() => const DnaVariables();

  // ...........................................................................
  /// The variables [layers] require that [given] does not set, the layers
  /// no local copy was found for and those whose config is broken.
  ({
    List<MissingDnaVariable> missing,
    List<String> unresolved,
    Map<String, String> broken,
  })
  missing({
    required List<String> layers,
    required Map<String, String> given,
    required RepoHost host,
  }) {
    final graph = _Graph(host);
    for (final layer in layers) {
      graph.visit(layer);
    }
    final required = <String, String>{};
    for (final layer in layers) {
      graph.passedOn[layer]?.forEach(
        (k, v) => required.putIfAbsent(k, () => v),
      );
    }
    return (
      missing: [
        for (final entry in required.entries)
          if (!given.containsKey(entry.key))
            MissingDnaVariable(name: entry.key, requiredBy: entry.value),
      ],
      unresolved: graph.unresolved.toList(),
      broken: graph.broken,
    );
  }
}

/// The layer graph below the chosen layers, parents first.
class _Graph {
  _Graph(this.host);

  final RepoHost host;

  /// Per layer: variable → the layer whose `true` its children inherit.
  final passedOn = <String, Map<String, String>>{};

  /// Layers without a local copy.
  final unresolved = <String>{};

  /// Layers whose local config cannot be read, with the reason.
  final broken = <String, String>{};

  /// Layers being visited; a cycle stops at them.
  final _visiting = <String>{};

  // ...........................................................................
  void visit(String layer) {
    if (passedOn.containsKey(layer) || unresolved.contains(layer)) return;
    if (broken.containsKey(layer) || !_visiting.add(layer)) return;
    final dir = host.layerDir(layer);
    if (dir == null) {
      unresolved.add(layer);
      return;
    }
    final config = _config(dir, layer);
    if (config == null) return;
    final inherited = <String, String>{};
    for (final parent in config.layers) {
      visit(parent);
      passedOn[parent]?.forEach((k, v) => inherited.putIfAbsent(k, () => v));
    }
    config.mustOverride.forEach((variable, flag) {
      if (flag) {
        inherited[variable] = layer;
      } else {
        inherited.remove(variable);
      }
    });
    passedOn[layer] = inherited;
  }

  // ...........................................................................
  helix.DnaConfig? _config(Directory dir, String layer) {
    try {
      return helix
          .readDnaConfig(helix.IoDnaHost(), dir.path, packageLabel: layer)
          .config;
    } on FormatException catch (e) {
      broken[layer] = e.message;
      return null;
    }
  }
}
