// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

import 'repo_language.dart';

/// Looks package names up on pub.dev and npm.
class Registry {
  /// Constructor
  Registry({http.Client? client, Duration? timeout})
    : _client = client ?? http.Client(),
      _timeout = timeout ?? const Duration(seconds: 15);

  /// A registry client; tests pass a `MockClient` from `http/testing`.
  factory Registry.example({http.Client? client, Duration? timeout}) =>
      Registry(client: client, timeout: timeout);

  // ...........................................................................
  /// Whether [packageName] exists; `null` when the registry is unreachable.
  Future<bool?> has(String packageName, RepoLanguage language) async {
    final url = switch (language) {
      RepoLanguage.dart => 'https://pub.dev/api/packages/$packageName',
      RepoLanguage.typescript =>
        'https://registry.npmjs.org/'
            '${packageName.replaceFirst('/', '%2f')}',
    };
    try {
      final response = await _client.get(Uri.parse(url)).timeout(_timeout);
      return switch (response.statusCode) {
        200 => true,
        404 => false,
        _ => null,
      };
    } on Exception {
      return null;
    }
  }

  // ...........................................................................
  /// The name of the registry, for messages.
  static String nameOf(RepoLanguage language) =>
      language == RepoLanguage.dart ? 'pub.dev' : 'npm';

  // ######################
  // Private
  // ######################

  final http.Client _client;
  final Duration _timeout;
}

/// Mock for [Registry].
class MockRegistry extends Mock implements Registry {}
