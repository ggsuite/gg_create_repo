// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_create_repo/gg_create_repo.dart';
import 'package:gg_create_repo/src/scaffold/common_files.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('common_files_'));
  tearDown(() => dir.deleteSync(recursive: true));

  String read(String path) => File(p.join(dir.path, path)).readAsStringSync();

  final fixedNow = CommonFiles(now: () => DateTime(2031));

  group('CommonFiles', () {
    group('write()', () {
      test('writes LICENSE, README, CHANGELOG and .gitattributes', () {
        final spec = RepoSpec.example(description: 'Says: "hi" for \$5');
        fixedNow.write(dir, spec);

        expect(read('LICENSE'), startsWith('MIT License'));
        expect(read('LICENSE'), contains('Copyright (c) 2031 ggsuite'));
        expect(read('README.md'), '# gg_example_repo\n\nSays: "hi" for \$5\n');
        expect(read('CHANGELOG.md'), '# Changelog\n\n## Unreleased\n');
        expect(read('.gitattributes'), startsWith('* text=auto eol=lf\n'));
        expect(read('.gitattributes'), contains('CHANGELOG.md merge=union'));
      });
    });

    group('license()', () {
      test('is MIT for public repositories', () {
        final license = fixedNow.license(RepoSpec.example(org: 'acme'));
        expect(license, contains('Copyright (c) 2031 acme'));
        expect(license, contains('Permission is hereby granted'));
        expect(license, isNot(contains('<holder>')));
      });

      test('reserves all rights for private repositories', () {
        final license = fixedNow.license(
          RepoSpec.example(org: 'acme', isPrivate: true),
        );
        expect(license, startsWith('Copyright (c) 2031 acme.'));
        expect(license, contains('All rights reserved'));
        expect(license, isNot(contains('MIT')));
      });

      test('uses the current year by default', () {
        final license = const CommonFiles().license(RepoSpec.example());
        expect(license, contains('${DateTime.now().year} ggsuite'));
      });
    });

    group('fileHeader()', () {
      test('names the org as copyright holder', () {
        final header = CommonFiles.fileHeader(RepoSpec.example(org: 'acme'));
        expect(header, startsWith('// @license\n// Copyright (c) acme\n'));
        expect(header.split('\n'), hasLength(6));
      });

      test('takes another comment marker', () {
        final header = CommonFiles.fileHeader(RepoSpec.example(), comment: '#');
        expect(header, startsWith('# @license\n'));
      });
    });

    group('writeFile()', () {
      test('creates the folders and writes LF line endings', () {
        CommonFiles.writeFile(dir, 'a/b/c.txt', 'one\r\ntwo\n');
        expect(read('a/b/c.txt'), 'one\ntwo\n');
      });
    });
  });
}
