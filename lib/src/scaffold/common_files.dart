// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../repo_spec.dart';

/// Writes the files every new repository gets, whatever its language.
class CommonFiles {
  /// Constructor
  const CommonFiles({this._now = DateTime.now});

  /// The files at a fixed [now]; tests pass what they care about.
  factory CommonFiles.example({DateTime Function()? now}) =>
      CommonFiles(now: now ?? () => DateTime(2026));

  // ...........................................................................
  /// Writes LICENSE, README.md, CHANGELOG.md and .gitattributes.
  void write(Directory directory, RepoSpec spec) {
    writeFile(directory, 'LICENSE', license(spec));
    writeFile(
      directory,
      'README.md',
      '# ${spec.name}\n\n${spec.description}\n',
    );
    writeFile(directory, 'CHANGELOG.md', '# Changelog\n\n## Unreleased\n');
    writeFile(directory, '.gitattributes', _gitattributes);
  }

  // ...........................................................................
  /// MIT for public repositories, all rights reserved for private ones.
  String license(RepoSpec spec) {
    final holder = '${_now().year} ${spec.org}';
    return spec.isPrivate
        ? 'Copyright (c) $holder. All rights reserved.\n\n'
              'This software is proprietary and confidential. Unauthorized '
              'copying,\ndistribution or use, via any medium, is strictly '
              'prohibited.\n'
        : _mit.replaceFirst('<holder>', holder);
  }

  // ...........................................................................
  /// The header every source file starts with.
  static String fileHeader(RepoSpec spec, {String comment = '//'}) =>
      '$comment @license\n'
      '$comment Copyright (c) ${spec.org}\n'
      '$comment\n'
      '$comment Use of this source code is governed by terms that can be\n'
      '$comment found in the LICENSE file in the root of this package.\n';

  // ...........................................................................
  /// Writes [content] to [relativePath] below [directory], with LF endings.
  static void writeFile(
    Directory directory,
    String relativePath,
    String content,
  ) {
    final file = File(p.join(directory.path, relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content.replaceAll('\r\n', '\n'));
  }

  // ######################
  // Private
  // ######################

  final DateTime Function() _now;

  static const _gitattributes =
      '* text=auto eol=lf\n'
      '.gg/gg.json merge=ours\n'
      'pubspec.lock merge=ours\n'
      'pnpm-lock.yaml merge=ours\n'
      'CHANGELOG.md merge=union\n';

  static const _mit = '''
MIT License

Copyright (c) <holder>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
''';
}
