// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_one_core/gg_one_core.dart'
    show
        buildMustRunScript,
        buildPreScript,
        prepublishMustRunScript,
        prepublishScriptNames;
import 'package:path/path.dart' as p;

import '../json_file.dart';
import '../repo_spec.dart';
import '../tools.dart';
import 'common_files.dart';
import 'scaffold.dart';

/// The skeleton of a TypeScript package built with vite, tested with
/// vitest at 100 % coverage and managed with pnpm.
class TsScaffold extends Scaffold {
  /// Constructor; [nodeMajor] is the major version of the installed node.
  const TsScaffold({this._nodeMajor});

  /// A scaffold for node 22; tests pass what they care about.
  factory TsScaffold.example({int? nodeMajor}) =>
      TsScaffold(nodeMajor: nodeMajor ?? 22);

  // ...........................................................................
  @override
  void write(Directory directory, RepoSpec spec) {
    void file(String path, String content) =>
        CommonFiles.writeFile(directory, path, content);

    final n = spec.name;
    file('package.json', packageJson(spec));
    file('pnpm-workspace.yaml', 'allowBuilds:\n  esbuild: true\n');
    file('.npmrc', 'registry=https://registry.npmjs.org/\n');
    file('.gitignore', _gitignore);
    file('tsconfig.json', _tsconfig);
    file('vite.config.mts', _viteConfig(spec));
    file('vitest.config.mts', _vitestConfig(spec));
    file('eslint.config.js', _eslintConfig(spec));
    file('src/index.ts', _index(spec));
    file('src/$n.ts', _class(spec));
    file('test/$n.spec.ts', _classTest(spec));
  }

  // ...........................................................................
  @override
  Future<void> install(Directory directory, RepoSpec spec, Tools tools) async {
    final packageJson = _json(directory, ['package.json']);
    final pnpm = await tools.version('pnpm');
    if (pnpm != null) {
      packageJson.edit((json) => json['packageManager'] = 'pnpm@$pnpm');
    }
    await tools.run('pnpm', [
      'add',
      '--save-dev',
      ..._devDependencies,
    ], directory: directory);
    _setTypescript(packageJson, typescriptRange(directory));
    await tools.run('pnpm', ['install'], directory: directory);
    final installed = _installedVersion(directory, 'typescript');
    if (installed != null) {
      _setTypescript(packageJson, '^$installed');
      await tools.run('pnpm', ['install'], directory: directory);
    }
  }

  // ...........................................................................
  /// The TypeScript versions the installed typescript-eslint supports:
  /// the newest TypeScript is often ahead of it.
  String typescriptRange(Directory directory) {
    final json = _json(directory, [
      'node_modules',
      'typescript-eslint',
      'package.json',
    ]).read();
    final peers = json['peerDependencies'] as Map<String, dynamic>? ?? {};
    return peers['typescript'] as String? ?? 'latest';
  }

  // ...........................................................................
  /// The package.json, without dependencies: `install` adds them.
  String packageJson(RepoSpec spec) {
    final json = <String, dynamic>{
      'name': spec.packageName,
      'version': '0.0.1',
      'description': spec.description,
      'homepage': spec.webUrl,
      'bugs': '${spec.webUrl}/issues',
      'private': spec.isPrivate,
      'license': spec.isPrivate ? 'UNLICENSED' : 'MIT',
      'engines': {'node': '>=${_nodeMajor ?? 22}'},
      'repository': {'type': 'git', 'url': 'git+${spec.webUrl}.git'},
      'type': 'module',
      'main': 'dist/${spec.name}.js',
      'types': 'dist/index.d.ts',
      'exports': {
        '.': {'types': './dist/index.d.ts', 'import': './dist/${spec.name}.js'},
      },
      'files': ['dist'],
      if (!spec.isPrivate) 'publishConfig': {'access': 'public'},
      'scripts': scripts,
    };
    return '${const JsonEncoder.withIndent('  ').convert(json)}\n';
  }

  /// The npm scripts, named as gg's package.json check expects them.
  static final scripts = <String, String>{
    'build': 'vite build',
    buildPreScript: 'pnpm run $buildMustRunScript',
    'test': 'vitest run --coverage && pnpm run lint',
    'lint': 'tsc --noEmit && eslint',
    prepublishScriptNames.first: 'pnpm run $prepublishMustRunScript',
  };

  // ######################
  // Private
  // ######################

  final int? _nodeMajor;

  static const _devDependencies = [
    '@eslint/js',
    '@types/node',
    '@vitest/coverage-v8',
    'eslint',
    'typescript-eslint',
    'vite',
    'vite-plugin-dts',
    'vitest',
  ];

  // ...........................................................................
  /// The constraint goes into package.json, not through the shell:
  /// `cmd.exe` would read the `<` and `>` of a range as redirects.
  void _setTypescript(JsonFile packageJson, String constraint) =>
      packageJson.edit((json) {
        final dev = json['devDependencies'] as Map<String, dynamic>? ?? {};
        dev['typescript'] = constraint;
        json['devDependencies'] = Map.fromEntries(
          dev.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
        );
      });

  // ...........................................................................
  String? _installedVersion(Directory directory, String package) =>
      _json(directory, [
            'node_modules',
            package,
            'package.json',
          ]).read()['version']
          as String?;

  // ...........................................................................
  JsonFile _json(Directory directory, List<String> parts) =>
      JsonFile(File(p.joinAll([directory.path, ...parts])));

  // ...........................................................................
  String _index(RepoSpec spec) =>
      '${CommonFiles.fileHeader(spec)}\n'
      "export * from './${spec.name}.ts';\n";

  // ...........................................................................
  String _class(RepoSpec spec) {
    final c = Scaffold.pascalCase(spec.name);
    return '''
${CommonFiles.fileHeader(spec)}
/** Greets whoever asks. */
export class $c {
  /**
   * Creates a greeter.
   * @param greeting - The word to greet with.
   */
  constructor(public readonly greeting: string = 'Hello') {}

  /**
   * A realistic instance; tests pass only what they care about.
   * @param options - The values to change.
   */
  static example(options: Partial<{ greeting: string }> = {}): $c {
    return new $c(options.greeting ?? 'Hello');
  }

  /**
   * Greets someone.
   * @param name - Who to greet.
   */
  greet(name: string): string {
    return `\${this.greeting}, \${name}!`;
  }
}
''';
  }

  // ...........................................................................
  String _classTest(RepoSpec spec) {
    final c = Scaffold.pascalCase(spec.name);
    return '''
${CommonFiles.fileHeader(spec)}
import { describe, expect, it } from 'vitest';

import { $c } from '../src/${spec.name}.ts';

describe('$c', () => {
  it('greets with the greeting', () => {
    expect(new $c('Hi').greet('Ada')).toBe('Hi, Ada!');
  });

  it('example() greets with Hello', () => {
    expect($c.example().greet('Ada')).toBe('Hello, Ada!');
    expect($c.example({ greeting: 'Hey' }).greeting).toBe('Hey');
  });
});
''';
  }

  // ...........................................................................
  String _viteConfig(RepoSpec spec) =>
      '''
${CommonFiles.fileHeader(spec)}
import { readFileSync } from 'node:fs';
import { builtinModules } from 'node:module';
import { defineConfig } from 'vite';
import dts from 'vite-plugin-dts';

const pkg = JSON.parse(
  readFileSync(new URL('./package.json', import.meta.url), 'utf8'),
) as { dependencies?: Record<string, string> };

export default defineConfig({
  plugins: [dts({ include: ['src'] })],
  build: {
    lib: {
      entry: 'src/index.ts',
      formats: ['es'],
      fileName: '${spec.name}',
    },
    rollupOptions: {
      external: [
        ...builtinModules,
        ...builtinModules.map((m) => `node:\${m}`),
        ...Object.keys(pkg.dependencies ?? {}),
      ],
    },
  },
});
''';

  // ...........................................................................
  String _vitestConfig(RepoSpec spec) =>
      '''
${CommonFiles.fileHeader(spec)}
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    include: ['test/**/*.spec.ts'],
    coverage: {
      provider: 'v8',
      include: ['src/**/*.ts'],
      exclude: ['src/index.ts'],
      thresholds: {
        lines: 100,
        functions: 100,
        branches: 100,
        statements: 100,
      },
    },
  },
});
''';

  // ...........................................................................
  String _eslintConfig(RepoSpec spec) =>
      '''
${CommonFiles.fileHeader(spec)}
import js from '@eslint/js';
import { defineConfig } from 'eslint/config';
import tseslint from 'typescript-eslint';

export default defineConfig(
  { ignores: ['**/*.js', 'coverage/', 'dist/', 'node_modules/'] },
  js.configs.recommended,
  tseslint.configs.recommended,
);
''';

  // ...........................................................................
  static const _tsconfig = '''
{
  "compilerOptions": {
    "target": "esnext",
    "module": "NodeNext",
    "moduleResolution": "nodenext",
    "lib": ["ESNext"],
    "types": ["node"],
    "skipLibCheck": true,
    "declaration": true,
    "noEmit": true,
    "allowImportingTsExtensions": true,
    "isolatedModules": true,
    "moduleDetection": "force",
    "resolveJsonModule": true,
    "esModuleInterop": true,
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true
  },
  "include": ["src", "test", "*.mts"]
}
''';

  static const _gitignore = '''
node_modules/
dist/
coverage/
.DS_Store
.gg/*
!.gg/gg.json
''';
}
