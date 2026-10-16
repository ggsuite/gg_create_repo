#!/usr/bin/env dart

// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_args/gg_args.dart';
import 'package:gg_create_repo/gg_create_repo.dart';
import 'package:gg_log/gg_log.dart';

// .............................................................................
/// Runs gg_create_repo with [args].
Future<void> run({required List<String> args, required GgLog ggLog}) =>
    GgCommandRunner(
      ggLog: ggLog,
      command: CreateRepo(ggLog: ggLog, name: 'gg_create_repo'),
    ).run(args: args);

// .............................................................................
Future<void> main(List<String> args) async {
  await run(args: args, ggLog: print);
}
