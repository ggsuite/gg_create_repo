// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:http/http.dart' as http;

import 'repo_language.dart';

/// Looks package names up on pub.dev and npm.
class Registry {
  /// Constructor
  Registry({http.Client? client}) : _client = client ?? http.Client();

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
      final response = await _client.get(Uri.parse(url));
      return switch (response.statusCode) {
        200 => true,
        404 => false,
        _ => null,
      };
    } on Exception {
      return null;
    }
  }

  /// The name of the registry, for messages.
  static String nameOf(RepoLanguage language) =>
      language == RepoLanguage.dart ? 'pub.dev' : 'npm';

  // ######################
  // Private
  // ######################

  final http.Client _client;
}
