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
  late Directory d;

  setUp(() => d = Directory.systemTemp.createTempSync('create_repo_state_'));
  tearDown(() => d.deleteSync(recursive: true));

  group('CreateStep', () {
    test('every step has a label', () {
      for (final step in CreateStep.values) {
        expect(step.label, isNotEmpty);
      }
    });
  });

  group('CreateRepoState', () {
    test('example() has a spec and nothing done', () {
      final state = CreateRepoState.example();
      expect(state.spec.name, RepoSpec.example().name);
      expect(state.done, isEmpty);

      final other = CreateRepoState.example(
        spec: RepoSpec.example(name: 'other'),
        done: {CreateStep.push},
      );
      expect(other.spec.name, 'other');
      expect(other.done, {CreateStep.push});
    });

    test('lives in .gg/create_repo_state.json', () {
      expect(
        CreateRepoState.fileIn(d).path,
        p.join(d.path, '.gg', 'create_repo_state.json'),
      );
    });

    test('load() is null without an earlier run', () {
      expect(CreateRepoState.load(d), isNull);
    });

    test('markDone() writes what load() reads, in step order', () {
      final spec = RepoSpec.example(name: 'gg_resumed', vars: {'a': 'b'});
      CreateRepoState(spec: spec)
        ..markDone(CreateStep.push, d)
        ..markDone(CreateStep.scaffold, d);

      final loaded = CreateRepoState.load(d)!;
      expect(loaded.spec.toJson(), spec.toJson());
      expect(loaded.done, {CreateStep.scaffold, CreateStep.push});

      final json = CreateRepoState.fileIn(d).readAsStringSync();
      expect(json.indexOf('scaffold'), lessThan(json.indexOf('push')));
    });

    test('save() writes the state without marking a step', () {
      CreateRepoState.example().save(d);
      final loaded = CreateRepoState.load(d)!;
      expect(loaded.done, isEmpty);
      expect(loaded.spec.slug, RepoSpec.example().slug);
    });

    test('load() names the file it cannot read', () {
      CreateRepoState.fileIn(d)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{"spec": {}, "done": ["renamedStep"]}');
      expect(
        () => CreateRepoState.load(d),
        throwsA(
          isA<Exception>().having(
            (e) => '$e',
            'message',
            allOf(contains('create_repo_state.json'), contains('move it')),
          ),
        ),
      );

      CreateRepoState.fileIn(d).writeAsStringSync('not json');
      expect(() => CreateRepoState.load(d), throwsA(isA<Exception>()));
    });

    test('delete() removes the file, and is fine without one', () {
      CreateRepoState.example().markDone(CreateStep.scaffold, d);
      expect(CreateRepoState.fileIn(d).existsSync(), isTrue);

      CreateRepoState.delete(d);
      expect(CreateRepoState.fileIn(d).existsSync(), isFalse);

      CreateRepoState.delete(d);
      expect(CreateRepoState.load(d), isNull);
    });
  });
}
