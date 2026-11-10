import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/src/build_artifacts.dart';
import '../tool/src/paths.dart';

final String _cliPath = toPosixPath(File('tool/mod_loader.dart').absolute.path);

void main() {
  group('mod_loader CLI', () {
    late _CliFixture fixture;

    setUp(() async {
      fixture = await _CliFixture.create();
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('plan 只读打印基线、Mod 顺序和补丁目标', () async {
      final result = await fixture.run(<String>['plan']);
      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.stdout, contains('modsetHash：'));
      expect(result.stdout, contains('mods/alpha'));
      expect(result.stdout, contains('patches/alpha.patch'));
      expect(result.stdout, contains('lib/features/alpha'));
      expect(
        Directory(joinPath(fixture.privatePath, '.build')).existsSync(),
        isFalse,
      );
    });

    test('apply 复制 overlay、应用补丁和 copy 并生成注册表与构建记录', () async {
      final result = await fixture.run(<String>['apply']);
      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.stdout, contains('合成完成（新建）'));

      final worktree = fixture.worktree;
      final worktreePath = toPosixPath(worktree.path);
      expect(
        File(joinPath(worktreePath, 'lib/modding/tool_mod.dart')).existsSync(),
        isTrue,
      );
      expect(
        File(
          joinPath(worktreePath, 'lib/modding/mod_registry.g.dart'),
        ).existsSync(),
        isTrue,
      );
      expect(
        File(joinPath(worktreePath, 'MOD_BUILD.json')).existsSync(),
        isTrue,
      );
      expect(
        File(
          joinPath(worktreePath, 'lib/features/alpha/alpha_mod.dart'),
        ).existsSync(),
        isTrue,
      );

      final controller = File(
        joinPath(
          worktreePath,
          'lib/features/home/controllers/generation_controller.dart',
        ),
      ).readAsStringSync();
      expect(controller, contains('// loader seam'));
      expect(controller, contains('// alpha'));

      final registry = File(
        joinPath(worktreePath, 'lib/modding/mod_registry.g.dart'),
      ).readAsStringSync();
      expect(registry, contains('AlphaMod'));
      expect(
        registry,
        contains('package:Kelivo/features/alpha/alpha_mod.dart'),
      );

      expect(
        await fixture.git(fixture.upstreamPath, <String>[
          'status',
          '--porcelain',
          '--untracked-files=no',
        ]),
        isEmpty,
      );
      expect(
        (await fixture.git(worktreePath, <String>['rev-parse', 'HEAD'])).trim(),
        fixture.commit,
      );
    });

    test('apply 幂等复用同一 worktree', () async {
      final first = await fixture.run(<String>['apply']);
      expect(first.exitCode, 0, reason: first.stderr);
      final second = await fixture.run(<String>['apply']);
      expect(second.exitCode, 0, reason: second.stderr);
      expect(second.stdout, contains('合成完成（复用）'));
      expect(fixture.worktrees, hasLength(1));
    });

    test('verify 校验合成结果', () async {
      final applied = await fixture.run(<String>['apply']);
      expect(applied.exitCode, 0, reason: applied.stderr);
      final verified = await fixture.run(<String>['verify']);
      expect(verified.exitCode, 0, reason: verified.stderr);
      expect(verified.stdout, contains('校验通过'));
    });

    test('verify 发现复制文件被篡改', () async {
      final applied = await fixture.run(<String>['apply']);
      expect(applied.exitCode, 0, reason: applied.stderr);
      final worktreePath = toPosixPath(fixture.worktree.path);
      File(
        joinPath(worktreePath, 'lib/features/alpha/alpha_mod.dart'),
      ).writeAsStringSync('tampered\n');

      final verified = await fixture.run(<String>['verify']);
      expect(verified.exitCode, 1);
      expect(verified.stderr, contains('复制'));
    });

    test('verify 允许 Flutter 生成注册文件和 pubspec.lock 漂移', () async {
      final applied = await fixture.run(<String>['apply']);
      expect(applied.exitCode, 0, reason: applied.stderr);
      final worktreePath = toPosixPath(fixture.worktree.path);
      for (final path in flutterGeneratedBuildArtifacts) {
        File(
          joinPath(worktreePath, path),
        ).writeAsStringSync('changed by flutter\n');
      }
      File(
        joinPath(worktreePath, 'pubspec.lock'),
      ).writeAsStringSync('changed by flutter\n');

      final verified = await fixture.run(<String>['verify']);
      expect(verified.exitCode, 0, reason: verified.stderr);
    });

    test('verify 拒绝其他已跟踪文件漂移', () async {
      final applied = await fixture.run(<String>['apply']);
      expect(applied.exitCode, 0, reason: applied.stderr);
      final worktreePath = toPosixPath(fixture.worktree.path);
      File(joinPath(worktreePath, 'README.md')).writeAsStringSync('changed\n');

      final verified = await fixture.run(<String>['verify']);
      expect(verified.exitCode, 1);
      expect(verified.stderr, contains('README.md'));
    });

    test('verify 不把 Flutter 重写的 CRLF 行尾当作已跟踪改动', () async {
      final applied = await fixture.run(<String>['apply']);
      expect(applied.exitCode, 0, reason: applied.stderr);
      final worktreePath = toPosixPath(fixture.worktree.path);
      await fixture.git(fixture.upstreamPath, <String>[
        'config',
        'core.autocrlf',
        'true',
      ]);
      File(
        joinPath(worktreePath, 'lib/l10n/app_localizations.dart'),
      ).writeAsStringSync('class AppLocalizations {}\r\n');

      final status = await fixture.git(worktreePath, <String>[
        'status',
        '--porcelain',
        '--untracked-files=no',
      ]);
      expect(status, contains('lib/l10n/app_localizations.dart'));

      final verified = await fixture.run(<String>['verify']);
      expect(verified.exitCode, 0, reason: verified.stderr);
    });

    test('verify 在 core.autocrlf=true 下仍拒绝真实内容变化', () async {
      final applied = await fixture.run(<String>['apply']);
      expect(applied.exitCode, 0, reason: applied.stderr);
      final worktreePath = toPosixPath(fixture.worktree.path);
      await fixture.git(fixture.upstreamPath, <String>[
        'config',
        'core.autocrlf',
        'true',
      ]);
      File(
        joinPath(worktreePath, 'lib/l10n/app_localizations.dart'),
      ).writeAsStringSync('class Changed {}\r\n');

      final verified = await fixture.run(<String>['verify']);
      expect(verified.exitCode, 1);
      expect(verified.stderr, contains('app_localizations.dart'));
    });

    test('verify 在未 apply 时失败', () async {
      final verified = await fixture.run(<String>['verify']);
      expect(verified.exitCode, 1);
      expect(verified.stderr, contains('合成目录不存在'));
    });

    test('clean 只删除指定 modset 的 worktree 和状态记录', () async {
      final applied = await fixture.run(<String>['apply']);
      expect(applied.exitCode, 0, reason: applied.stderr);
      final hash = fixture.modsetHashFrom(applied.stdout);
      final worktreePath = toPosixPath(fixture.worktree.path);

      final cleaned = await fixture.run(<String>['clean', '--modset', hash]);
      expect(cleaned.exitCode, 0, reason: cleaned.stderr);
      expect(Directory(worktreePath).existsSync(), isFalse);
      expect(fixture.worktrees, isEmpty);
      final list = await fixture.git(fixture.upstreamPath, <String>[
        'worktree',
        'list',
        '--porcelain',
      ]);
      expect(list, isNot(contains(worktreePath)));
    });

    test('clean 缺少 --modset 时不删除任何内容', () async {
      final applied = await fixture.run(<String>['apply']);
      expect(applied.exitCode, 0, reason: applied.stderr);
      final cleaned = await fixture.run(<String>['clean']);
      expect(cleaned.exitCode, 2);
      expect(fixture.worktrees, hasLength(1));
    });

    test('clean 拒绝未知 modset', () async {
      final cleaned = await fixture.run(<String>[
        'clean',
        '--modset',
        '0' * 64,
      ]);
      expect(cleaned.exitCode, 1);
      expect(cleaned.stderr, contains('状态'));
    });

    test('rebase-drill 在临时 worktree 验证新基线且不改主合成树', () async {
      final applied = await fixture.run(<String>['apply']);
      expect(applied.exitCode, 0, reason: applied.stderr);
      final mainWorktree = fixture.worktree;
      final mainHead = (await fixture.git(
        toPosixPath(mainWorktree.path),
        <String>['rev-parse', 'HEAD'],
      )).trim();
      final modsBefore = File(
        joinPath(fixture.privatePath, 'mods.json'),
      ).readAsStringSync();

      final secondCommit = await fixture.createCommit(
        relativePath: 'SECOND.md',
        content: 'second\n',
        message: 'second',
      );
      final drilled = await fixture.run(<String>[
        'rebase-drill',
        '--to',
        secondCommit,
      ]);
      expect(drilled.exitCode, 0, reason: drilled.stderr);
      expect(drilled.stdout, contains('演练通过'));
      expect(drilled.stdout, contains('临时 worktree 已清理'));

      expect(
        (await fixture.git(toPosixPath(mainWorktree.path), <String>[
          'rev-parse',
          'HEAD',
        ])).trim(),
        mainHead,
      );
      expect(
        File(joinPath(fixture.privatePath, 'mods.json')).readAsStringSync(),
        modsBefore,
      );
      final drills = Directory(joinPath(fixture.privatePath, '.build/drills'));
      expect(
        drills.existsSync()
            ? drills.listSync().whereType<Directory>().length
            : 0,
        0,
      );
    });

    test('rebase-drill 补丁冲突时失败并清理临时 worktree', () async {
      final applied = await fixture.run(<String>['apply']);
      expect(applied.exitCode, 0, reason: applied.stderr);
      final mainWorktree = fixture.worktree;
      final mainHead = (await fixture.git(
        toPosixPath(mainWorktree.path),
        <String>['rev-parse', 'HEAD'],
      )).trim();

      final secondCommit = await fixture.createCommit(
        relativePath:
            'lib/features/home/controllers/generation_controller.dart',
        content: 'changed\n',
        message: 'conflict',
      );
      final drilled = await fixture.run(<String>[
        'rebase-drill',
        '--to',
        secondCommit,
      ]);
      expect(drilled.exitCode, 1);
      expect(drilled.stderr, contains('补丁'));
      expect(
        (await fixture.git(toPosixPath(mainWorktree.path), <String>[
          'rev-parse',
          'HEAD',
        ])).trim(),
        mainHead,
      );
      final drills = Directory(joinPath(fixture.privatePath, '.build/drills'));
      expect(
        drills.existsSync()
            ? drills.listSync().whereType<Directory>().length
            : 0,
        0,
      );
    });
  });
}

class _CliResult {
  const _CliResult(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;
}

class _CliFixture {
  _CliFixture._(this.root, this.upstream, this.privateRepo, this.commit);

  final Directory root;
  final Directory upstream;
  final Directory privateRepo;
  final String commit;

  String get upstreamPath => toPosixPath(upstream.path);

  String get privatePath => toPosixPath(privateRepo.path);

  List<Directory> get worktrees {
    final directory = Directory(joinPath(privatePath, '.build/worktrees'));
    if (!directory.existsSync()) return const <Directory>[];
    return directory.listSync().whereType<Directory>().toList();
  }

  Directory get worktree => worktrees.single;

  static Future<_CliFixture> create() async {
    final root = Directory.systemTemp.createTempSync('kelivo_loader_cli_');
    final upstreamPath = joinPath(toPosixPath(root.path), 'upstream');
    final privatePath = joinPath(toPosixPath(root.path), 'private');
    final upstream = Directory(upstreamPath)..createSync(recursive: true);
    final privateRepo = Directory(privatePath)..createSync(recursive: true);

    await _runGit(upstreamPath, <String>['init', '-b', 'main']);
    await _runGit(upstreamPath, <String>['config', 'core.autocrlf', 'false']);

    File(
        joinPath(
          upstreamPath,
          'lib/features/home/controllers/generation_controller.dart',
        ),
      )
      ..createSync(recursive: true)
      ..writeAsStringSync('line1\nline2\n');
    File(joinPath(upstreamPath, 'pubspec.lock')).writeAsStringSync('lock\n');
    File(joinPath(upstreamPath, 'README.md')).writeAsStringSync('readme\n');
    File(joinPath(upstreamPath, 'lib/l10n/app_localizations.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('class AppLocalizations {}\n');
    for (final path in flutterGeneratedBuildArtifacts) {
      File(joinPath(upstreamPath, path))
        ..createSync(recursive: true)
        ..writeAsStringSync('generated\n');
    }
    await _runGit(upstreamPath, <String>['add', '-A']);
    await _runGit(upstreamPath, <String>[
      '-c',
      'user.email=test@example.com',
      '-c',
      'user.name=Kelivo Test',
      'commit',
      '-m',
      'initial',
    ]);
    final commit = (await _runGit(upstreamPath, <String>[
      'rev-parse',
      'HEAD',
    ])).trim();

    _writeJson(File(joinPath(privatePath, 'mods.json')), <String, Object?>{
      'schemaVersion': 1,
      'upstream': <String, Object?>{'path': upstreamPath, 'commit': commit},
      'mods': <Map<String, Object?>>[
        <String, Object?>{'path': 'mods/alpha', 'enabled': true},
      ],
    });

    File(joinPath(privatePath, 'patches/tool_mod_seams.patch'))
      ..createSync(recursive: true)
      ..writeAsStringSync(_seamsPatch.trimLeft());

    File(joinPath(privatePath, 'overlay/lib/modding/tool_mod.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('class ToolMod { const ToolMod(); }\n');
    File(joinPath(privatePath, 'overlay/test/modding/tool_mod_test.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('void main() {}\n');

    final modDirectory = joinPath(privatePath, 'mods/alpha');
    _writeJson(File(joinPath(modDirectory, 'mod.json')), <String, Object?>{
      'schemaVersion': 1,
      'id': 'alpha',
      'version': '1.0.0',
      'upstreamCommit': commit,
      'toolNames': <String>['alpha_tool'],
      'registration': <String, Object?>{
        'import': 'package:Kelivo/features/alpha/alpha_mod.dart',
        'className': 'AlphaMod',
      },
      'touches': <String>[
        'lib/features/home/controllers/generation_controller.dart',
      ],
      'patches': <String>['patches/alpha.patch'],
      'copy': <Map<String, Object?>>[
        <String, Object?>{
          'from': 'overlay/lib/features/alpha',
          'to': 'lib/features/alpha',
        },
      ],
    });
    File(joinPath(modDirectory, 'patches/alpha.patch'))
      ..createSync(recursive: true)
      ..writeAsStringSync(_alphaPatch.trimLeft());
    File(joinPath(modDirectory, 'overlay/lib/features/alpha/alpha_mod.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('class AlphaMod { const AlphaMod(); }\n');

    return _CliFixture._(root, upstream, privateRepo, commit);
  }

  Future<String> createCommit({
    required String relativePath,
    required String content,
    required String message,
  }) async {
    final file = File(joinPath(upstreamPath, relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    await _runGit(upstreamPath, <String>['add', '-A']);
    await _runGit(upstreamPath, <String>[
      '-c',
      'user.email=test@example.com',
      '-c',
      'user.name=Kelivo Test',
      'commit',
      '-m',
      message,
    ]);
    return (await _runGit(upstreamPath, <String>['rev-parse', 'HEAD'])).trim();
  }

  Future<_CliResult> run(List<String> args) async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      <String>[_cliPath, ...args],
      workingDirectory: privatePath,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    return _CliResult(
      result.exitCode,
      result.stdout as String,
      result.stderr as String,
    );
  }

  Future<String> git(String workingDirectory, List<String> args) =>
      _runGit(workingDirectory, args);

  String modsetHashFrom(String output) {
    final match = RegExp(r'modsetHash：([0-9a-f]{64})').firstMatch(output);
    if (match == null) {
      throw StateError('输出中没有 modsetHash：$output');
    }
    return match.group(1)!;
  }

  Future<void> dispose() async {
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        if (root.existsSync()) root.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}

Future<String> _runGit(String workingDirectory, List<String> args) async {
  final result = await Process.run(
    'git',
    args,
    workingDirectory: workingDirectory,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) {
    throw StateError('git ${args.join(' ')} failed: ${result.stderr}');
  }
  return result.stdout as String;
}

void _writeJson(File file, Object? value) {
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(value)}\n',
  );
}

const String _seamsPatch = '''
diff --git a/lib/features/home/controllers/generation_controller.dart b/lib/features/home/controllers/generation_controller.dart
--- a/lib/features/home/controllers/generation_controller.dart
+++ b/lib/features/home/controllers/generation_controller.dart
@@ -1,2 +1,3 @@
 line1
 line2
+// loader seam
''';

const String _alphaPatch = '''
diff --git a/lib/features/home/controllers/generation_controller.dart b/lib/features/home/controllers/generation_controller.dart
--- a/lib/features/home/controllers/generation_controller.dart
+++ b/lib/features/home/controllers/generation_controller.dart
@@ -1,3 +1,4 @@
 line1
 line2
 // loader seam
+// alpha
''';
