// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_process/gg_process.dart';
import 'package:test/test.dart';

import '../../bin/gg_create_repo.dart';

void main() {
  group('bin/gg_create_repo.dart', () {
    test('logs the usage for an unknown option', () async {
      addTearDown(() => ggExitCode = 0);
      final messages = <String>[];
      await run(args: ['--unknown-option'], ggLog: messages.add);
      expect(messages.join('\n'), contains('--without-dna'));
    });
  });
}
