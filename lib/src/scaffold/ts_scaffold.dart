// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import '../repo_spec.dart';
import '../tools.dart';
import 'common_files.dart';
import 'scaffold.dart';

/// The skeleton of a TypeScript package built with vite, tested with
/// vitest at 100 % coverage and managed with pnpm.
class TsScaffold extends Scaffold {
  /// Constructor
  const TsScaffold();

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
    final pnpm = await tools.version('pnpm');
    if (pnpm != null) _setPackageManager(directory, pnpm);
    await tools.run('pnpm', [
      'add',
      '--save-dev',
      ..._devDependencies,
    ], directory: directory);
    _setTypescript(directory, typescriptRange(directory));
    await tools.run('pnpm', ['install'], directory: directory);
    final installed = _installedVersion(directory, 'typescript');
    if (installed != null) {
      _setTypescript(directory, '^$installed');
      await tools.run('pnpm', ['install'], directory: directory);
    }
  }

  // ...........................................................................
  /// The TypeScript versions the installed typescript-eslint supports.
  ///
  /// The newest TypeScript is often ahead of typescript-eslint; taking its
  /// peer range keeps lint working without pinning a major here.
  String typescriptRange(Directory directory) {
    final file = File(
      '${directory.path}/node_modules/typescript-eslint/package.json',
    );
    if (!file.existsSync()) return 'latest';
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
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
      'engines': {'node': '>=22.14.0'},
      'repository': {'type': 'git', 'url': 'git+${spec.webUrl}.git'},
      'type': 'module',
      'main': 'dist/${spec.name}.js',
      'types': 'dist/index.d.ts',
      'exports': {
        '.': {'types': './dist/index.d.ts', 'import': './dist/${spec.name}.js'},
      },
      'files': ['dist'],
      if (!spec.isPrivate) 'publishConfig': {'access': 'public'},
      'scripts': {
        'build': 'vite build',
        'prebuild': 'pnpm run test',
        'test': 'vitest run --coverage && pnpm run lint',
        'lint': 'tsc --noEmit && eslint',
        'prepublishOnly': 'pnpm run build',
      },
    };
    return '${const JsonEncoder.withIndent('  ').convert(json)}\n';
  }

  // ######################
  // Private
  // ######################

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
  /// Pins the pnpm that installed the package, as corepack expects it.
  void _setPackageManager(Directory directory, String version) =>
      _editPackageJson(directory, (json) {
        json['packageManager'] = 'pnpm@$version';
      });

  // ...........................................................................
  /// Writes the TypeScript constraint into package.json, not through the
  /// shell: `cmd.exe` would read the `<` and `>` of a range as redirects.
  void _setTypescript(Directory directory, String constraint) =>
      _editPackageJson(directory, (json) {
        final dev = json['devDependencies'] as Map<String, dynamic>? ?? {};
        dev['typescript'] = constraint;
        json['devDependencies'] = Map.fromEntries(
          dev.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
        );
      });

  // ...........................................................................
  String? _installedVersion(Directory directory, String package) {
    final file = File('${directory.path}/node_modules/$package/package.json');
    if (!file.existsSync()) return null;
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return json['version'] as String?;
  }

  // ...........................................................................
  void _editPackageJson(
    Directory directory,
    void Function(Map<String, dynamic> json) edit,
  ) {
    final file = File('${directory.path}/package.json');
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    edit(json);
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(json)}\n',
    );
  }

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
      thresholds: { lines: 100, functions: 100, branches: 100, statements: 100 },
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
