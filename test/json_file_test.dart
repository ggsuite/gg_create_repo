// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_create_repo/src/json_file.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory d;

  setUp(() => d = Directory.systemTemp.createTempSync('json_file_'));
  tearDown(() => d.deleteSync(recursive: true));

  group('JsonFile', () {
    test('read() is empty without a file', () {
      expect(JsonFile(File(p.join(d.path, 'missing.json'))).read(), isEmpty);
    });

    test('write() creates folders and indents with a final newline', () {
      final file = File(p.join(d.path, 'a', 'b.json'));
      JsonFile(file).write({'x': 1});
      expect(file.readAsStringSync(), '{\n  "x": 1\n}\n');
      expect(JsonFile(file).read(), {'x': 1});
    });

    test('edit() changes what is there', () {
      final json = JsonFile(File(p.join(d.path, 'c.json')))..write({'a': 1});
      json.edit((map) => map['b'] = 2);
      expect(json.read(), {'a': 1, 'b': 2});
    });

    test('example() points into the system temp folder', () {
      expect(
        JsonFile.example().file.path,
        startsWith(Directory.systemTemp.path),
      );
      final file = File(p.join(d.path, 'e.json'));
      expect(JsonFile.example(file: file).file, file);
    });
  });
}
