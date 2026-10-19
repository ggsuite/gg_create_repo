// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_create_repo/gg_create_repo.dart';
import 'package:gg_create_repo/src/scaffold/ts_scaffold.dart';
import 'package:gg_create_repo/src/tools.dart';
import 'package:gg_one_core/gg_one_core.dart'
    show
        buildMustRunScript,
        buildPreScript,
        prepublishMustRunScript,
        prepublishScriptNames,
        requiredNpmScripts;
import 'package:gg_process/gg_process.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// .............................................................................
/// Stands in for pnpm: `add` and `install` write what pnpm would install.
class _FakePnpm extends GgProcessWrapper {
  _FakePnpm({
    this.version = '10.28.2',
    this.installedTypescript = '6.0.3',
    this.writeTypescriptEslint = true,
  });

  final String? version;
  static const peerRange = '>=4.8.4 <6.1.0';
  final String? installedTypescript;
  final bool writeTypescriptEslint;
  final calls = <String>[];
  final typescriptOnInstall = <String?>[];

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
  }) async {
    calls.add([executable, ...arguments].join(' '));
    if (arguments.first == '--version') {
      return version == null
          ? ProcessResult(0, 1, '', 'not found')
          : ProcessResult(0, 0, '$version\n', '');
    }
    final dir = Directory(workingDirectory!);
    if (arguments.first == 'add') _add(dir);
    if (arguments.first == 'install') _install(dir);
    return ProcessResult(0, 0, '', '');
  }

  void _add(Directory dir) {
    final pkg = _readJson(p.join(dir.path, 'package.json'));
    pkg['devDependencies'] = {'vitest': '^4.0.0', '@eslint/js': '^9.0.0'};
    _writeJson(p.join(dir.path, 'package.json'), pkg);
    if (!writeTypescriptEslint) return;
    _writeJson(
      p.join(dir.path, 'node_modules', 'typescript-eslint', 'package.json'),
      {
        'name': 'typescript-eslint',
        'peerDependencies': {'typescript': peerRange},
      },
    );
  }

  void _install(Directory dir) {
    final pkg = _readJson(p.join(dir.path, 'package.json'));
    final dev = pkg['devDependencies'] as Map<String, dynamic>;
    typescriptOnInstall.add(dev['typescript'] as String?);
    if (installedTypescript == null) return;
    _writeJson(p.join(dir.path, 'node_modules', 'typescript', 'package.json'), {
      'name': 'typescript',
      'version': installedTypescript,
    });
  }
}

Map<String, dynamic> _readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void _writeJson(String path, Map<String, dynamic> json) => File(path)
  ..parent.createSync(recursive: true)
  ..writeAsStringSync(jsonEncode(json));

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('ts_scaffold_'));
  tearDown(() => dir.deleteSync(recursive: true));

  final scaffold = TsScaffold.example();
  const tricky = r'''Says: "hi" and 'bye' for $5 \ less''';

  RepoSpec ts({bool isPrivate = false, String? npmScope}) => RepoSpec.example(
    name: 'my-lib',
    language: RepoLanguage.typescript,
    org: 'ggsuite',
    description: tricky,
    isPrivate: isPrivate,
    npmScope: npmScope,
  );

  String read(String path) => File(p.join(dir.path, path)).readAsStringSync();
  Map<String, dynamic> packageJson() =>
      _readJson(p.join(dir.path, 'package.json'));

  group('TsScaffold', () {
    group('write()', () {
      test('writes a public package', () {
        scaffold.write(dir, ts());

        final pkg = packageJson();
        expect(pkg['name'], '@ggsuite/my-lib');
        expect(pkg['version'], '0.0.1');
        expect(pkg['description'], tricky);
        expect(pkg['private'], isFalse);
        expect(pkg['license'], 'MIT');
        expect(pkg['publishConfig'], {'access': 'public'});
        expect(pkg['main'], 'dist/my-lib.js');
        expect(pkg['repository'], {
          'type': 'git',
          'url': 'git+https://github.com/ggsuite/my-lib.git',
        });
        final scripts = pkg['scripts'] as Map<String, dynamic>;
        expect(scripts.keys, containsAll(requiredNpmScripts));
        expect(scripts[buildPreScript], contains(buildMustRunScript));
        expect(
          scripts[prepublishScriptNames.first],
          contains(prepublishMustRunScript),
        );
        expect(scripts['test'], contains('vitest run --coverage'));
        expect(scripts, TsScaffold.scripts);
        expect(pkg['engines'], {'node': '>=22'});
        expect(read('package.json'), endsWith('}\n'));

        expect(read('pnpm-workspace.yaml'), contains('esbuild: true'));
        expect(read('.npmrc'), contains('registry.npmjs.org'));
        expect(read('.gitignore'), contains('node_modules/'));
        expect(jsonDecode(read('tsconfig.json')), isA<Map<String, dynamic>>());
        expect(read('vite.config.mts'), contains("fileName: 'my-lib'"));
        expect(read('vitest.config.mts'), contains('lines: 100'));
        for (final file in ['vitest.config.mts', 'vite.config.mts']) {
          for (final line in read(file).split('\n')) {
            expect(line.length, lessThanOrEqualTo(80), reason: file);
          }
        }
        expect(read('eslint.config.js'), contains('typescript-eslint'));
        expect(read('src/index.ts'), contains("export * from './my-lib.ts';"));
        expect(read('src/my-lib.ts'), contains('export class MyLib {'));
        expect(
          read('test/my-lib.spec.ts'),
          contains("import { MyLib } from '../src/my-lib.ts';"),
        );
      });

      test('writes a private package', () {
        scaffold.write(dir, ts(isPrivate: true));
        final pkg = packageJson();
        expect(pkg['private'], isTrue);
        expect(pkg['license'], 'UNLICENSED');
        expect(pkg.containsKey('publishConfig'), isFalse);
      });

      test('requires the node it was created with', () {
        const TsScaffold(nodeMajor: 24).write(dir, ts());
        expect(packageJson()['engines'], {'node': '>=24'});
      });

      test('requires node 22 when the node version is unknown', () {
        const TsScaffold().write(dir, ts());
        expect(packageJson()['engines'], {'node': '>=22'});
      });

      test('takes another npm scope', () {
        scaffold.write(dir, ts(npmScope: 'acme'));
        expect(packageJson()['name'], '@acme/my-lib');
      });
    });

    group('install()', () {
      test('pins the newest TypeScript typescript-eslint supports', () async {
        scaffold.write(dir, ts());
        final pnpm = _FakePnpm();

        await scaffold.install(dir, ts(), Tools(processWrapper: pnpm));

        expect(pnpm.calls, [
          'pnpm --version',
          'pnpm add --save-dev @eslint/js @types/node @vitest/coverage-v8 '
              'eslint typescript-eslint vite vite-plugin-dts vitest',
          'pnpm install',
          'pnpm install',
        ]);
        expect(pnpm.typescriptOnInstall, ['>=4.8.4 <6.1.0', '^6.0.3']);

        final pkg = packageJson();
        expect(pkg['packageManager'], 'pnpm@10.28.2');
        final dev = pkg['devDependencies'] as Map<String, dynamic>;
        expect(dev.keys, ['@eslint/js', 'typescript', 'vitest']);
        expect(dev['typescript'], '^6.0.3');
      });

      test('takes the latest TypeScript without typescript-eslint', () async {
        scaffold.write(dir, ts());
        final pnpm = _FakePnpm(
          version: null,
          writeTypescriptEslint: false,
          installedTypescript: null,
        );

        await scaffold.install(dir, ts(), Tools(processWrapper: pnpm));

        expect(pnpm.calls.where((c) => c == 'pnpm install'), hasLength(1));
        expect(pnpm.typescriptOnInstall, ['latest']);
        expect(packageJson().containsKey('packageManager'), isFalse);
      });
    });

    group('typescriptRange()', () {
      test('is latest when typescript-eslint has no peer range', () {
        _writeJson(
          p.join(dir.path, 'node_modules', 'typescript-eslint', 'package.json'),
          {'name': 'typescript-eslint'},
        );
        expect(scaffold.typescriptRange(dir), 'latest');
      });

      test('is latest when the peer range names no TypeScript', () {
        _writeJson(
          p.join(dir.path, 'node_modules', 'typescript-eslint', 'package.json'),
          {
            'peerDependencies': {'eslint': '^10.0.0'},
          },
        );
        expect(scaffold.typescriptRange(dir), 'latest');
      });

      test('is the peer range otherwise', () {
        _writeJson(
          p.join(dir.path, 'node_modules', 'typescript-eslint', 'package.json'),
          {
            'peerDependencies': {'typescript': '>=5 <6'},
          },
        );
        expect(scaffold.typescriptRange(dir), '>=5 <6');
      });
    });
  });
}
