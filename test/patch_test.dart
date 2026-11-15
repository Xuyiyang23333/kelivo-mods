import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/src/patch.dart';

void main() {
  late Directory tempDir;
  late Directory repo;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('kelivo_patch_test_');
    repo = Directory('${tempDir.path}/repo')..createSync();
    _git(['init', '-q'], cwd: repo.path);
    _git(['config', 'user.email', 'test@example.com'], cwd: repo.path);
    _git(['config', 'user.name', 'Kelivo Test'], cwd: repo.path);
    _git(['config', 'core.autocrlf', 'false'], cwd: repo.path);
    _git(['config', 'core.safecrlf', 'false'], cwd: repo.path);
    Directory('${repo.path}/lib').createSync();
    File('${repo.path}/lib/base.txt').writeAsStringSync('base\n');
    _git(['add', '-A'], cwd: repo.path);
    _git(['commit', '-qm', 'init'], cwd: repo.path);
  });

  tearDown(() {
    _deleteTemp(tempDir);
  });

  test('inspect 解析补丁路径且不修改工作树', () {
    final patch = _capturePatch(repo, () {
      File('${repo.path}/lib/new.txt').writeAsStringSync('one\n');
    });
    final patchFile = _writePatch(tempDir, 'new.patch', patch);
    final applier = PatchApplier(worktree: repo.path);

    final inspection = applier.inspect(
      PatchSpec(patchFile: patchFile, touches: ['lib/new.txt'], label: 'test'),
    );

    expect(inspection.paths, ['lib/new.txt']);
    expect(inspection.newFiles, ['lib/new.txt']);
    expect(inspection.binary, isFalse);
    expect(File('${repo.path}/lib/new.txt').existsSync(), isFalse);
  });

  test('apply 应用补丁并更新索引', () async {
    final patch = _capturePatch(repo, () {
      File('${repo.path}/lib/new.txt').writeAsStringSync('one\n');
    });
    final patchFile = _writePatch(tempDir, 'new.patch', patch);
    final applier = PatchApplier(worktree: repo.path);

    await applier.apply(
      PatchSpec(patchFile: patchFile, touches: ['lib/new.txt']),
    );

    expect(File('${repo.path}/lib/new.txt').readAsStringSync(), 'one\n');
    final staged =
        _git(['diff', '--cached', '--name-only'], cwd: repo.path).stdout
            as String;
    expect(staged, contains('lib/new.txt'));
  });

  test('按顺序应用补丁，后一个补丁依赖前一个结果', () async {
    final first = _capturePatch(repo, () {
      File('${repo.path}/lib/order.txt').writeAsStringSync('one\n');
    });
    const second = '''
diff --git a/lib/order.txt b/lib/order.txt
--- a/lib/order.txt
+++ b/lib/order.txt
@@ -1 +1 @@
-one
+two
''';
    final firstFile = _writePatch(tempDir, 'first.patch', first);
    final secondFile = _writePatch(tempDir, 'second.patch', second);
    final applier = PatchApplier(worktree: repo.path);

    final applied = await applier.applyAll([
      PatchSpec(patchFile: firstFile, touches: ['lib/order.txt']),
      PatchSpec(patchFile: secondFile, touches: ['lib/order.txt']),
    ]);

    expect(applied, hasLength(2));
    expect(File('${repo.path}/lib/order.txt').readAsStringSync(), 'two\n');
  });

  test('补丁冲突时立即失败，后续补丁不应用', () async {
    final first = _capturePatch(repo, () {
      File('${repo.path}/lib/conflict.txt').writeAsStringSync('one\n');
    });
    const second = '''
diff --git a/lib/conflict.txt b/lib/conflict.txt
--- a/lib/conflict.txt
+++ b/lib/conflict.txt
@@ -1 +1 @@
-wrong
+right
''';
    const third = '''
diff --git a/lib/third.txt b/lib/third.txt
new file mode 100644
--- /dev/null
+++ b/lib/third.txt
@@ -0,0 +1 @@
+third
''';
    final firstFile = _writePatch(tempDir, 'first.patch', first);
    final secondFile = _writePatch(tempDir, 'second.patch', second);
    final thirdFile = _writePatch(tempDir, 'third.patch', third);
    final applier = PatchApplier(worktree: repo.path);

    await expectLater(
      applier.applyAll([
        PatchSpec(
          patchFile: firstFile,
          touches: ['lib/conflict.txt'],
          label: 'first',
        ),
        PatchSpec(
          patchFile: secondFile,
          touches: ['lib/conflict.txt'],
          label: 'second',
        ),
        PatchSpec(
          patchFile: thirdFile,
          touches: ['lib/third.txt'],
          label: 'third',
        ),
      ]),
      throwsA(_patchError('--check')),
    );

    expect(File('${repo.path}/lib/conflict.txt').readAsStringSync(), 'one\n');
    expect(File('${repo.path}/lib/third.txt').existsSync(), isFalse);
  });

  test('补丁路径不在白名单内时拒绝应用', () async {
    final patch = _capturePatch(repo, () {
      File('${repo.path}/lib/other.txt').writeAsStringSync('x\n');
    });
    final patchFile = _writePatch(tempDir, 'other.patch', patch);
    final applier = PatchApplier(worktree: repo.path);

    await expectLater(
      applier.apply(PatchSpec(patchFile: patchFile, touches: ['lib/base.txt'])),
      throwsA(_patchError('白名单')),
    );
    expect(File('${repo.path}/lib/other.txt').existsSync(), isFalse);
  });

  test('touches 目录条目允许其子路径', () async {
    final patch = _capturePatch(repo, () {
      File('${repo.path}/lib/modding/tool_mod.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('class ToolMod {}\n');
    });
    final patchFile = _writePatch(tempDir, 'dir.patch', patch);
    final applier = PatchApplier(worktree: repo.path);

    final inspection = await applier.apply(
      PatchSpec(patchFile: patchFile, touches: ['lib/modding/']),
    );

    expect(inspection.paths, ['lib/modding/tool_mod.dart']);
    expect(File('${repo.path}/lib/modding/tool_mod.dart').existsSync(), isTrue);
  });

  test('补丁路径与白名单大小写不一致时拒绝', () {
    const patch = '''
diff --git a/lib/Case.txt b/lib/Case.txt
new file mode 100644
--- /dev/null
+++ b/lib/Case.txt
@@ -0,0 +1 @@
+x
''';
    final patchFile = _writePatch(tempDir, 'case.patch', patch);
    final applier = PatchApplier(worktree: repo.path);

    expect(
      () => applier.inspect(
        PatchSpec(patchFile: patchFile, touches: ['lib/case.txt']),
      ),
      throwsA(_patchError('大小写')),
    );
  });

  test('拒绝绝对路径补丁', () {
    const patch = '''
diff --git a//tmp/evil.txt b//tmp/evil.txt
new file mode 100644
--- /dev/null
+++ b//tmp/evil.txt
@@ -0,0 +1 @@
+x
''';
    final patchFile = _writePatch(tempDir, 'absolute.patch', patch);
    final applier = PatchApplier(worktree: repo.path);

    expect(
      () => applier.inspect(PatchSpec(patchFile: patchFile, touches: ['lib'])),
      throwsA(_patchError('绝对路径')),
    );
  });

  test('拒绝路径穿越补丁', () {
    const patch = '''
diff --git a/../evil.txt b/../evil.txt
new file mode 100644
--- /dev/null
+++ b/../evil.txt
@@ -0,0 +1 @@
+x
''';
    final patchFile = _writePatch(tempDir, 'traversal.patch', patch);
    final applier = PatchApplier(worktree: repo.path);

    expect(
      () => applier.inspect(PatchSpec(patchFile: patchFile, touches: ['lib'])),
      throwsA(_patchError('路径穿越')),
    );
  });

  test('拒绝修改 .git 的补丁', () {
    const patch = '''
diff --git a/.git/config b/.git/config
--- a/.git/config
+++ b/.git/config
@@ -1 +1 @@
-a
+b
''';
    final patchFile = _writePatch(tempDir, 'git-dir.patch', patch);
    final applier = PatchApplier(worktree: repo.path);

    expect(
      () => applier.inspect(
        PatchSpec(patchFile: patchFile, touches: ['.git/config']),
      ),
      throwsA(_patchError('.git')),
    );
  });

  test('拒绝符号链接补丁', () {
    const patch = '''
diff --git a/lib/link b/lib/link
new file mode 120000
index 0000000..1111111
--- /dev/null
+++ b/lib/link
@@ -0,0 +1 @@
+target
\ No newline at end of file
''';
    final patchFile = _writePatch(tempDir, 'symlink.patch', patch);
    final applier = PatchApplier(worktree: repo.path);

    expect(
      () => applier.inspect(PatchSpec(patchFile: patchFile, touches: ['lib'])),
      throwsA(_patchError('符号链接')),
    );
  });

  test('拒绝 submodule 补丁', () {
    const patch = '''
diff --git a/vendor/sub b/vendor/sub
new file mode 160000
index 0000000..1111111
--- /dev/null
+++ b/vendor/sub
@@ -0,0 +1 @@
+Subproject commit 1111111111111111111111111111111111111111
''';
    final patchFile = _writePatch(tempDir, 'submodule.patch', patch);
    final applier = PatchApplier(worktree: repo.path);

    expect(
      () =>
          applier.inspect(PatchSpec(patchFile: patchFile, touches: ['vendor'])),
      throwsA(_patchError('submodule')),
    );
  });

  test('补丁文件不存在时失败', () {
    final applier = PatchApplier(worktree: repo.path);

    expect(
      () => applier.inspect(
        PatchSpec(patchFile: '${tempDir.path}/missing.patch', touches: ['lib']),
      ),
      throwsA(_patchError('不存在')),
    );
  });

  test('空补丁失败', () {
    final patchFile = _writePatch(tempDir, 'empty.patch', '');
    final applier = PatchApplier(worktree: repo.path);

    expect(
      () => applier.inspect(PatchSpec(patchFile: patchFile, touches: ['lib'])),
      throwsA(_patchError('不包含任何文件变更')),
    );
  });

  test('空 touches 白名单拒绝所有补丁', () {
    final patch = _capturePatch(repo, () {
      File('${repo.path}/lib/new.txt').writeAsStringSync('one\n');
    });
    final patchFile = _writePatch(tempDir, 'new.patch', patch);
    final applier = PatchApplier(worktree: repo.path);

    expect(
      () => applier.inspect(
        PatchSpec(patchFile: patchFile, touches: const <String>[]),
      ),
      throwsA(_patchError('白名单')),
    );
  });

  test('git apply 携带进程级 core.longpaths=true', () async {
    final patch = _capturePatch(repo, () {
      File('${repo.path}/lib/longpath.txt').writeAsStringSync('long\n');
    });
    final patchFile = _writePatch(tempDir, 'longpath.patch', patch);
    final invocations = <List<String>>[];
    final applier = PatchApplier(
      worktree: repo.path,
      runProcess: (executable, arguments) {
        invocations.add(arguments);
        return Process.run(
          executable,
          arguments,
          stdoutEncoding: const Utf8Codec(allowMalformed: true),
          stderrEncoding: const Utf8Codec(allowMalformed: true),
        );
      },
    );

    await applier.apply(
      PatchSpec(patchFile: patchFile, touches: ['lib/longpath.txt']),
    );

    expect(invocations, hasLength(2));
    for (final arguments in invocations) {
      expect(arguments.take(2).toList(), <String>['-c', 'core.longpaths=true']);
    }
  });

  test('二进制补丁可以应用', () async {
    final bytes = List<int>.generate(256, (index) => index);
    final patch = _capturePatch(repo, () {
      File('${repo.path}/lib/logo.bin').writeAsBytesSync(bytes);
    });
    final patchFile = _writePatch(tempDir, 'binary.patch', patch);
    final applier = PatchApplier(worktree: repo.path);

    final inspection = await applier.apply(
      PatchSpec(patchFile: patchFile, touches: ['lib/logo.bin']),
    );

    expect(inspection.binary, isTrue);
    expect(File('${repo.path}/lib/logo.bin').readAsBytesSync(), bytes);
  });

  test('带空格的补丁路径可以解析并应用', () async {
    final patch = _capturePatch(repo, () {
      File('${repo.path}/lib/with space.txt').writeAsStringSync('space\n');
    });
    final patchFile = _writePatch(tempDir, 'space.patch', patch);
    final applier = PatchApplier(worktree: repo.path);

    final inspection = await applier.apply(
      PatchSpec(patchFile: patchFile, touches: ['lib/with space.txt']),
    );

    expect(inspection.paths, ['lib/with space.txt']);
    expect(
      File('${repo.path}/lib/with space.txt').readAsStringSync(),
      'space\n',
    );
  });

  test('带中文的补丁路径可以解析并应用', () async {
    final patch = _capturePatch(repo, () {
      File('${repo.path}/lib/中文.txt').writeAsStringSync('中文\n');
    });
    final patchFile = _writePatch(tempDir, 'unicode.patch', patch);
    final applier = PatchApplier(worktree: repo.path);

    final inspection = await applier.apply(
      PatchSpec(patchFile: patchFile, touches: ['lib/中文.txt']),
    );

    expect(inspection.paths, ['lib/中文.txt']);
    expect(File('${repo.path}/lib/中文.txt').readAsStringSync(), '中文\n');
  });

  test('重命名补丁同时校验新旧路径', () async {
    final patch = _capturePatch(repo, () {
      _git(['mv', 'lib/base.txt', 'lib/renamed.txt'], cwd: repo.path);
    });
    final patchFile = _writePatch(tempDir, 'rename.patch', patch);
    final applier = PatchApplier(worktree: repo.path);

    final inspection = await applier.apply(
      PatchSpec(
        patchFile: patchFile,
        touches: ['lib/base.txt', 'lib/renamed.txt'],
      ),
    );

    expect(inspection.paths, containsAll(['lib/base.txt', 'lib/renamed.txt']));
    expect(File('${repo.path}/lib/base.txt').existsSync(), isFalse);
    expect(File('${repo.path}/lib/renamed.txt').readAsStringSync(), 'base\n');
  });

  test('git apply --check 失败时不修改工作树', () async {
    const patch = '''
diff --git a/lib/missing.txt b/lib/missing.txt
--- a/lib/missing.txt
+++ b/lib/missing.txt
@@ -1 +1 @@
-a
+b
''';
    final patchFile = _writePatch(tempDir, 'missing-target.patch', patch);
    final applier = PatchApplier(worktree: repo.path);

    await expectLater(
      applier.apply(
        PatchSpec(patchFile: patchFile, touches: ['lib/missing.txt']),
      ),
      throwsA(_patchError('--check')),
    );

    expect(File('${repo.path}/lib/missing.txt').existsSync(), isFalse);
    final status =
        _git(['status', '--porcelain'], cwd: repo.path).stdout as String;
    expect(status.trim(), isEmpty);
  });

  test('worktree 不存在时失败', () async {
    final patch = _capturePatch(repo, () {
      File('${repo.path}/lib/new.txt').writeAsStringSync('one\n');
    });
    final patchFile = _writePatch(tempDir, 'new.patch', patch);
    final applier = PatchApplier(worktree: '${tempDir.path}/missing');

    await expectLater(
      applier.apply(PatchSpec(patchFile: patchFile, touches: ['lib/new.txt'])),
      throwsA(_patchError('worktree')),
    );
  });

  test('inspectAll 保持声明顺序', () {
    final first = _capturePatch(repo, () {
      File('${repo.path}/lib/a.txt').writeAsStringSync('a\n');
    });
    final second = _capturePatch(repo, () {
      File('${repo.path}/lib/b.txt').writeAsStringSync('b\n');
    });
    final firstFile = _writePatch(tempDir, 'a.patch', first);
    final secondFile = _writePatch(tempDir, 'b.patch', second);
    final applier = PatchApplier(worktree: repo.path);

    final inspections = applier.inspectAll([
      PatchSpec(patchFile: firstFile, touches: ['lib/a.txt']),
      PatchSpec(patchFile: secondFile, touches: ['lib/b.txt']),
    ]);

    expect(inspections.map((item) => item.paths.single), [
      'lib/a.txt',
      'lib/b.txt',
    ]);
  });
}

Matcher _patchError(String fragment) {
  return isA<PatchException>().having(
    (error) => error.message,
    'message',
    contains(fragment),
  );
}

ProcessResult _git(List<String> args, {String? cwd}) {
  final result = Process.runSync(
    'git',
    args,
    workingDirectory: cwd,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) {
    throw StateError(
      'git ${args.join(' ')} 失败：\n${result.stdout}\n${result.stderr}',
    );
  }
  return result;
}

String _capturePatch(Directory repo, void Function() mutate) {
  mutate();
  _git(['add', '-A'], cwd: repo.path);
  final patch =
      _git(['diff', '--cached', '--binary'], cwd: repo.path).stdout as String;
  _git(['reset', '-q'], cwd: repo.path);
  _git(['checkout', '--', '.'], cwd: repo.path);
  final untracked =
      (_git([
                'ls-files',
                '-z',
                '--others',
                '--exclude-standard',
              ], cwd: repo.path).stdout
              as String)
          .split('\u0000')
          .where((line) => line.isNotEmpty);
  for (final relative in untracked) {
    final file = File('${repo.path}/$relative');
    if (file.existsSync()) {
      file.deleteSync();
    }
  }
  return patch;
}

String _writePatch(Directory directory, String name, String content) {
  final file = File('${directory.path}/$name');
  file.writeAsStringSync(content);
  return file.path;
}

void _deleteTemp(Directory directory) {
  for (var attempt = 0; attempt < 5; attempt++) {
    try {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
      return;
    } on FileSystemException {
      sleep(const Duration(milliseconds: 100));
    }
  }
}
