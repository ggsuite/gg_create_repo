// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';

import 'package:gg_create_repo/gg_create_repo.dart';
import 'package:gg_create_repo/src/registry.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

// The registries are on the network: MockClient answers in their place.
void main() {
  group('Registry', () {
    late List<Uri> asked;

    Registry registry(int status) => Registry(
      client: MockClient((request) async {
        asked.add(request.url);
        return http.Response('{}', status);
      }),
    );

    setUp(() => asked = []);

    test('asks pub.dev for Dart packages', () async {
      expect(await registry(200).has('gg_x', RepoLanguage.dart), isTrue);
      expect(asked.single.toString(), 'https://pub.dev/api/packages/gg_x');
    });

    test('asks npm for scoped packages, with the slash encoded', () async {
      expect(
        await registry(404).has('@tssuite/x', RepoLanguage.typescript),
        isFalse,
      );
      expect(
        asked.single.toString(),
        'https://registry.npmjs.org/@tssuite%2Fx',
      );
    });

    test('is null when the registry answers something else', () async {
      expect(await registry(500).has('gg_x', RepoLanguage.dart), isNull);
    });

    test('is null when the registry cannot be reached', () async {
      final offline = Registry(
        client: MockClient((_) async => throw http.ClientException('down')),
      );
      expect(await offline.has('gg_x', RepoLanguage.dart), isNull);
    });

    test('is null when the registry does not answer in time', () async {
      final slow = Registry(
        timeout: const Duration(milliseconds: 10),
        client: MockClient((_) => Completer<http.Response>().future),
      );
      expect(await slow.has('gg_x', RepoLanguage.dart), isNull);
    });

    test('has a default client and an example', () {
      expect(Registry(), isA<Registry>());
      expect(Registry.example(), isA<Registry>());
      expect(MockRegistry(), isA<Registry>());
    });

    test('nameOf() names the registry', () {
      expect(Registry.nameOf(RepoLanguage.dart), 'pub.dev');
      expect(Registry.nameOf(RepoLanguage.typescript), 'npm');
    });
  });
}
