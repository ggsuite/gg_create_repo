// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_create_repo/gg_create_repo.dart';
import 'package:gg_create_repo/src/github.dart';
import 'package:gg_create_repo/src/registry.dart';
import 'package:gg_create_repo/src/tools.dart';
import 'package:gg_process/gg_process.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The answer of a faked tool: a result, or `null` for "not installed".
typedef _Answer = ProcessResult? Function();

ProcessResult _ok([String out = '']) => ProcessResult(0, 0, out, '');
ProcessResult _fail([String err = 'failed']) => ProcessResult(0, 1, '', err);

/// What `gh api --include` prints: the status line, a header, the body.
ProcessResult _http(int status, [String body = '']) => ProcessResult(
  0,
  status == 200 ? 0 : 1,
  'HTTP/2.0 $status X\r\nContent-Type: application/json\r\n\r\n$body\n',
  status == 200 ? '' : 'gh: (HTTP $status)',
);

// .............................................................................
/// Runs git for real; answers every other tool, and the git calls listed
/// in [answers], from the table. gh, node and pnpm need the network.
class _Processes extends GgProcessWrapper {
  final answers = <String, _Answer>{};
  final calls = <String>[];

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
    final call = [executable, ...arguments].join(' ');
    calls.add(call);
    final answer = answers[call];
    if (answer != null) {
      final result = answer();
      if (result == null) throw ProcessException(executable, arguments);
      return result;
    }
    if (executable == 'git') {
      return Process.run(
        'git',
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        stdoutEncoding: utf8,
      );
    }
    return _fail('no answer for $call');
  }
}

// .............................................................................
/// A host in [root] that records what it was asked.
class _Host extends StandaloneHost {
  _Host(Directory root, {this.problems = const [], this.layers = const {}})
    : super(outputDir: root);

  final List<String> problems;
  final Map<String, Directory> layers;
  bool? resumes;

  @override
  Directory? layerDir(String layer) => layers[layer];

  @override
  Future<List<String>> check(RepoSpec spec, {required bool resumes}) async {
    this.resumes = resumes;
    return problems;
  }
}

void main() {
  late Directory root;
  late Directory dnaGgsuite;
  late _Processes processes;
  late Set<String> inRegistry;
  late Set<String> unreachable;

  const slug = 'ggsuite/gg_example_repo';
  const ssh = 'ssh -T -o BatchMode=yes -o ConnectTimeout=10 git@github.com';
  const sshWelcome =
      "Hi ada! You've successfully authenticated, but GitHub does not "
      'provide shell access.';
  const pub = 'https://pub.dev/api/packages';

  String api(String path, [String? jq]) =>
      'gh api --include $path${jq == null ? '' : ' --jq $jq'}';

  void answer(String call, _Answer result) => processes.answers[call] = result;

  Preflight preflight() => Preflight.example(
    tools: Tools.example(processWrapper: processes),
    gitHub: GitHub.example(processWrapper: processes),
    registry: Registry.example(
      client: MockClient((r) async {
        final url = '${r.url}';
        if (unreachable.contains(url)) throw http.ClientException('down');
        return http.Response('', inRegistry.contains(url) ? 200 : 404);
      }),
    ),
  );

  _Host host({
    List<String> problems = const [],
    Map<String, Directory>? layers,
  }) => _Host(
    root,
    problems: problems,
    layers: layers ?? {'dna_ggsuite': dnaGgsuite},
  );

  Future<List<Finding>> run({
    RepoSpec? spec,
    _Host? on,
    bool resumes = false,
  }) => preflight().run(
    spec ?? RepoSpec.example(),
    on ?? host(),
    resumes: resumes,
  );

  Future<List<String>> level(
    FindingLevel level, {
    RepoSpec? spec,
    _Host? on,
    bool resumes = false,
  }) async => [
    for (final f in await run(spec: spec, on: on, resumes: resumes))
      if (f.level == level) f.message,
  ];

  Future<List<String>> errors({
    RepoSpec? spec,
    _Host? on,
    bool resumes = false,
  }) => level(FindingLevel.error, spec: spec, on: on, resumes: resumes);

  Future<List<String>> warnings({RepoSpec? spec, _Host? on}) =>
      level(FindingLevel.warning, spec: spec, on: on);

  Future<List<String>> infos({RepoSpec? spec, bool resumes = false}) =>
      level(FindingLevel.info, spec: spec, resumes: resumes);

  setUp(() {
    root = Directory.systemTemp.createTempSync('preflight_');
    dnaGgsuite = Directory(p.join(root.path, '_layers', 'dna_ggsuite'));
    File(p.join(dnaGgsuite.path, 'dna', '_dna.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync('{"version": 2, "layers": []}');
    inRegistry = {};
    unreachable = {};
    processes = _Processes();
    processes.answers.addAll({
      'git config user.name': () => _ok('Test\n'),
      'git config user.email': () => _ok('test@example.com\n'),
      'gh --version': () => _ok('gh version 2.60.0\n'),
      'gh auth status': () => _ok(),
      ssh: () => _fail(sshWelcome),
      'gh api user --jq .login': () => _ok('ada\n'),
      'dart --version': () => _ok('Dart SDK version: 3.9.2 (stable)\n'),
      'flutter --version': () => _ok('Flutter 3.35.0\n'),
      'node --version': () => _ok('v22.14.0\n'),
      'pnpm --version': () => _ok('10.28.2\n'),
      api('users/ggsuite', '.type'): () => _http(200, 'Organization'),
      api('user/memberships/orgs/ggsuite', '[.state, .role] | @tsv'): () =>
          _http(200, 'active\tadmin'),
      api('repos/$slug', '.private'): () => _http(404),
    });
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('Preflight', () {
    test('finds nothing for a fresh repository', () async {
      expect(await run(), isEmpty);
      expect(processes.calls, contains('git --version'));
    });

    test('passes resumes on to the host', () async {
      final h = host(problems: ['the host objects']);
      expect(await errors(on: h, resumes: true), ['the host objects']);
      expect(h.resumes, isTrue);
    });

    // #########################################################################
    group('git', () {
      test('must be installed', () async {
        answer('git --version', () => null);
        expect(await errors(), contains('git is not installed.'));
      });

      test('must be 2.28 or newer', () async {
        answer('git --version', () => _ok('git version 2.27.0\n'));
        expect(await errors(), [contains('git 2.27 is too old')]);
      });

      test('must know who commits', () async {
        answer('git config user.name', () => _fail(''));
        answer('git config user.email', () => null);
        expect(await errors(), [
          contains('git has no user.name'),
          contains('git has no user.email'),
        ]);
      });
    });

    // #########################################################################
    group('tools', () {
      test('gh must be logged in', () async {
        answer('gh auth status', () => _fail());
        expect(await errors(), [contains('not logged in')]);
      });

      test('ssh must reach GitHub', () async {
        answer(ssh, () => _fail('Permission denied (publickey).'));
        expect(await errors(), [contains('github.com refused your SSH key')]);
      });

      test('without gh, GitHub is not asked', () async {
        answer('gh --version', () => null);
        expect(await errors(), [contains('»gh« is not installed')]);
        expect(processes.calls.where((c) => c.startsWith('gh api')), isEmpty);
      });

      test('Dart needs dart, Flutter needs flutter', () async {
        answer('dart --version', () => null);
        expect(await errors(), ['dart is not installed.']);
        answer('flutter --version', () => _fail());
        expect(await errors(spec: RepoSpec.example(flutter: true)), [
          'flutter is not installed.',
        ]);
      });

      test('Dart with DNA warns without node', () async {
        answer('node --version', () => null);
        expect(await warnings(), [contains('node is not installed')]);
        expect(await warnings(spec: RepoSpec.example(dnaLayers: [])), isEmpty);
      });

      group('TypeScript', () {
        final ts = RepoSpec.example(
          name: 'my-lib',
          language: RepoLanguage.typescript,
          dnaLayers: [],
        );

        setUp(() {
          answer(api('repos/ggsuite/my-lib', '.private'), () => _http(404));
        });

        test('needs node', () async {
          answer('node --version', () => null);
          expect(await errors(spec: ts), ['node is not installed.']);
        });

        test('needs pnpm 10 or newer', () async {
          answer('pnpm --version', () => null);
          expect(await errors(spec: ts), ['pnpm is not installed.']);
          answer('pnpm --version', () => _ok('9.15.0\n'));
          expect(await errors(spec: ts), [contains('pnpm 9 is too old')]);
        });
      });
    });

    // #########################################################################
    group('target', () {
      Directory target() =>
          Directory(p.join(root.path, 'gg_example_repo'))..createSync();

      test('may exist when it is empty', () async {
        target();
        expect(await errors(), isEmpty);
      });

      test('must not hold anything', () async {
        File(p.join(target().path, 'x')).writeAsStringSync('');
        expect(await errors(), [contains('already exists and is not empty')]);
      });

      test('is continued when the run resumes', () async {
        File(p.join(target().path, 'x')).writeAsStringSync('');
        expect(await errors(resumes: true), isEmpty);
        expect(await infos(resumes: true), [
          contains('Continues the earlier run'),
        ]);
      });

      test('warns when it sits inside a git repository', () async {
        await Process.run('git', ['init', root.path]);
        expect(await warnings(), [contains('becomes a nested one')]);
      });
    });

    // #########################################################################
    group('GitHub', () {
      test('must know the owner', () async {
        answer(api('users/ggsuite', '.type'), () => _http(404));
        expect(await errors(), [contains('knows no organization or user')]);
      });

      test('creates for the logged in user only', () async {
        answer(api('users/ggsuite', '.type'), () => _http(200, 'User'));
        expect(await errors(), [contains('only be created for yourself')]);
        answer('gh api user --jq .login', () => _ok('GgSuite\n'));
        expect(await errors(), isEmpty);
        answer('gh api user --jq .login', () => _fail());
        expect(await errors(), isEmpty);
      });

      test('needs a membership in the organization', () async {
        final membership = api(
          'user/memberships/orgs/ggsuite',
          '[.state, .role] | @tsv',
        );
        answer(membership, () => _http(404));
        expect(await errors(), [contains('no member of the organization')]);
        answer(membership, () => _http(200, 'pending\tmember'));
        expect(await errors(), [contains('not accepted yet')]);
      });

      test('needs members to be allowed to create', () async {
        answer(
          api('user/memberships/orgs/ggsuite', '[.state, .role] | @tsv'),
          () => _http(200, 'active\tmember'),
        );
        final setting = api('orgs/ggsuite', '.members_can_create_repositories');
        answer(setting, () => _http(200, 'false'));
        expect(await errors(), [contains('may not create repositories')]);
        answer(setting, () => _http(200, 'true'));
        expect(await errors(), isEmpty);
      });

      group('the repository', () {
        void exists({required bool isPrivate, required int commits}) {
          answer(
            api('repos/$slug', '.private'),
            () => _http(200, '$isPrivate'),
          );
          answer(
            api('repos/$slug/commits?per_page=1'),
            () => _http(commits, '[]'),
          );
        }

        test('is used when it is empty', () async {
          exists(isPrivate: false, commits: 409);
          expect(await errors(), isEmpty);
          expect(await infos(), [contains('will be used')]);
        });

        test('must have the same visibility when it is empty', () async {
          exists(isPrivate: true, commits: 409);
          expect(await errors(), [contains('is private')]);
          exists(isPrivate: false, commits: 409);
          expect(await errors(spec: RepoSpec.example(isPrivate: true)), [
            contains('is public'),
          ]);
        });

        test('must not have commits', () async {
          exists(isPrivate: false, commits: 200);
          expect(await errors(), [contains('already exists and has commits')]);
        });

        test('may have commits of the earlier run', () async {
          exists(isPrivate: false, commits: 200);
          expect(await errors(resumes: true), isEmpty);
          expect(await infos(resumes: true), contains(contains('earlier run')));
        });

        test('is an error when GitHub cannot be asked', () async {
          answer(api('repos/$slug', '.private'), () => _fail('no network'));
          expect(await errors(), [contains('could not be asked')]);
        });
      });
    });

    // #########################################################################
    group('registry', () {
      test('refuses a name that is taken', () async {
        inRegistry.add('$pub/gg_example_repo');
        expect(await errors(), [contains('already taken on pub.dev')]);
      });

      test('warns when it cannot be asked', () async {
        unreachable.add('$pub/gg_example_repo');
        expect(await warnings(), [contains('pub.dev could not be asked')]);
      });

      test('is not asked for a private repository', () async {
        inRegistry.add('$pub/gg_example_repo');
        expect(await errors(spec: RepoSpec.example(isPrivate: true)), isEmpty);
      });
    });

    // #########################################################################
    group('DNA', () {
      RepoSpec withDna(List<String> layers, {RepoLanguage? language}) =>
          RepoSpec.example(
            name: language == RepoLanguage.typescript ? 'my-lib' : null,
            language: language,
            dnaLayers: layers,
          );

      test('reads a git URL with git', () async {
        final bare = p.join(root.path, 'dna_x.git');
        await Process.run('git', ['init', '--bare', bare]);
        expect(await errors(spec: withDna([bare])), isEmpty);
      });

      test('refuses a git URL git cannot read', () async {
        const scp = 'git@example.invalid:org/dna_x';
        answer('git ls-remote --heads $scp', () => _fail('denied'));
        const https = 'https://example.invalid/org/dna_y';
        answer('git ls-remote --heads $https', () => _fail('denied'));
        expect(await errors(spec: withDna([scp, https])), [
          contains('$scp cannot be read with git'),
          contains('$https cannot be read with git'),
        ]);
      });

      test('reads a git+ URL of npm without git+ and #ref', () async {
        answer(api('repos/ggsuite/my-lib', '.private'), () => _http(404));
        const url = 'git+https://example.invalid/org/dna-z.git#main';
        answer(
          'git ls-remote --heads https://example.invalid/org/dna-z.git',
          _ok,
        );
        final spec = withDna([url], language: RepoLanguage.typescript);
        expect(await errors(spec: spec), isEmpty);
      });

      test('refuses a git URL written for npm in a Dart repo', () async {
        const url = 'git+https://example.invalid/org/dna_z.git';
        expect(await errors(spec: withDna([url])), [
          contains('written for npm'),
        ]);
      });

      test('warns about a layer whose local config is broken', () async {
        final broken = Directory(p.join(root.path, 'dna_broken'));
        File(p.join(broken.path, 'dna', '_dna.json'))
          ..createSync(recursive: true)
          ..writeAsStringSync('{"layers": 3}');
        final on = host(layers: {'dna_broken': broken});
        expect(await errors(spec: withDna(['dna_broken']), on: on), isEmpty);
        expect(await warnings(spec: withDna(['dna_broken']), on: on), [
          contains('The local copy of dna_broken has a broken DNA config'),
        ]);
      });

      test('refuses an npm layer for a Dart repository', () async {
        expect(await errors(spec: withDna(['@tssuite/dna-tssuite'])), [
          contains('is an npm package'),
        ]);
        expect(await errors(spec: withDna(['dna-tssuite'])), [
          contains('is an npm package'),
        ]);
      });

      test('takes a layer with a local copy without the registry', () async {
        expect(await errors(spec: withDna(['dna_ggsuite'])), isEmpty);
      });

      test('looks other layers up in the registry', () async {
        final on = host(layers: {});
        expect(await errors(spec: withDna(['dna_other']), on: on), [
          contains('dna_other is not on pub.dev'),
        ]);
        unreachable.add('$pub/dna_other');
        expect(await warnings(spec: withDna(['dna_other']), on: on), [
          contains('pub.dev could not be asked for dna_other'),
          contains('only known once it is installed'),
        ]);
        inRegistry.add('$pub/dna_other');
        unreachable.clear();
        expect(await errors(spec: withDna(['dna_other']), on: on), isEmpty);
      });

      test('looks TypeScript layers up on npm', () async {
        answer(api('repos/ggsuite/my-lib', '.private'), () => _http(404));
        const layer = 'dna-plain';
        final spec = withDna([layer], language: RepoLanguage.typescript);
        expect(
          await errors(
            spec: spec,
            on: host(layers: {}),
          ),
          [contains('dna-plain is not on npm')],
        );
      });

      test('warns about variables of layers without a local copy', () async {
        inRegistry.add('$pub/dna_other');
        expect(
          await warnings(
            spec: withDna(['dna_other']),
            on: host(layers: {}),
          ),
          [contains('The required variables of dna_other')],
        );
      });
    });

    // #########################################################################
    test('Finding.example() is an error', () {
      final finding = Finding.example();
      expect(finding.level, FindingLevel.error);
      expect(finding.message, isNotEmpty);
    });

    test('works on the real tools by default', () {
      expect(Preflight(), isA<Preflight>());
    });
  });
}
