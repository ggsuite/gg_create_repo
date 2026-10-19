// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_create_repo/gg_create_repo.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('DnaCandidate', () {
    test('example() has realistic defaults and takes values', () {
      final candidate = DnaCandidate.example();
      expect(candidate.label, 'dna_ggsuite');
      expect(candidate.ref, 'dna_ggsuite');

      final other = DnaCandidate.example(label: 'l', ref: 'r');
      expect(other.label, 'l');
      expect(other.ref, 'r');
    });
  });

  group('StandaloneHost', () {
    final out = Directory(p.join('some', 'folder'));
    final spec = RepoSpec.example(name: 'gg_x');

    test('example() lives in the system temp folder', () async {
      final host = StandaloneHost.example();
      expect(host.outputDir.path, Directory.systemTemp.path);
      expect(await host.knownOrgs(), ['ggsuite']);
      final other = StandaloneHost.example(outputDir: out, orgs: ['x']);
      expect(other.outputDir, out);
      expect(await other.knownOrgs(), ['x']);
    });

    test('creates the repository below the output folder', () {
      final host = StandaloneHost(outputDir: out);
      expect(host.targetDir(spec).path, p.join('some', 'folder', 'gg_x'));
      expect(host.outputDir, out);
    });

    test('offers the given organizations and no DNA', () async {
      final host = StandaloneHost(outputDir: out, orgs: ['a', 'b']);
      expect(await host.knownOrgs(), ['a', 'b']);
      expect(await StandaloneHost(outputDir: out).knownOrgs(), isEmpty);
      expect(host.dnaCandidates(spec), isEmpty);
      expect(host.layerDir('dna_ggsuite'), isNull);
      expect(host.presetOrg, isNull);
    });

    test('sees no problems and does nothing afterwards', () async {
      final host = StandaloneHost(outputDir: out);
      expect(await host.check(spec, resumes: false), isEmpty);
      expect(await host.check(spec, resumes: true), isEmpty);
      expect(host.afterCreateDescription(spec), isNull);
      final messages = <String>[];
      await host.afterCreate(spec: spec, directory: out, ggLog: messages.add);
      expect(messages, isEmpty);
    });
  });
}
