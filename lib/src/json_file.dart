// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

/// Reads and writes the JSON object files gg_create_repo edits.
class JsonFile {
  /// Constructor
  const JsonFile(this.file);

  /// A file in the system temp folder; tests pass what they care about.
  factory JsonFile.example({File? file}) => JsonFile(
    file ?? File('${Directory.systemTemp.path}/gg_create_repo_example.json'),
  );

  // ...........................................................................
  /// The object in [file]; an empty one when the file does not exist.
  Map<String, dynamic> read() => file.existsSync()
      ? jsonDecode(file.readAsStringSync()) as Map<String, dynamic>
      : <String, dynamic>{};

  // ...........................................................................
  /// Writes [json] with two spaces of indentation and a final newline.
  void write(Map<String, dynamic> json) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(json)}\n',
    );
  }

  // ...........................................................................
  /// Reads the object, lets [change] edit it and writes it back.
  void edit(void Function(Map<String, dynamic> json) change) {
    final json = read();
    change(json);
    write(json);
  }

  /// The file.
  final File file;
}
