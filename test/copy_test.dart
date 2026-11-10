import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/src/copy.dart';

void main() {
  late Directory tempDir;
  late Directory worktree;
  late Directory overlay;
  late CopyPlanner planner;

  CopyRequest spec({
    String source = '.',
    String destination = '.',
    List<String> exclude = const <String>[],
    String label = 'test',
  }) {
    return CopyRequest(
      sourceRoot: overlay.path,
      source: source,
      destination: destination,
      exclude: exclude,
      label: label,
    );
  }

  File writeSource(String relative, String content) {
    final file = File('${overlay.path}/$relative');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file;
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('kelivo_copy_test_');
    worktree = Directory('${tempDir.path}/worktree')..createSync();
    _git(['init', '-q'], cwd: worktree.path);
    _git(['config', 'user.email', 'test@example.com'], cwd: worktree.path);
    _git(['config', 'user.name', 'Kelivo Test'], cwd: worktree.path);
    _git(['config', 'core.autocrlf', 'false'], cwd: worktree.path);
    Directory('${worktree.path}/lib').createSync();
    File(
      '${worktree.path}/lib/existing.dart',
    ).writeAsStringSync('void main() {}\n');
    File('${worktree.path}/README.md').writeAsStringSync('# upstream\n');
    _git(['add', '-A'], cwd: worktree.path);
    _git(['commit', '-qm', 'init'], cwd: worktree.path);
    overlay = Directory('${tempDir.path}/mod/overlay')
      ..createSync(recursive: true);
    planner = CopyPlanner(worktree: worktree.path);
  });

  tearDown(() {
    _deleteTemp(tempDir);
  });

  test('复制单个新增文件到已存在目录', () {
    writeSource('lib/modding/tool_mod.dart', 'class ToolMod {}\n');

    final plan = planner.applyAll([
      spec(
        source: 'lib/modding/tool_mod.dart',
        destination: 'lib/modding/tool_mod.dart',
      ),
    ]);

    expect(
      File('${worktree.path}/lib/modding/tool_mod.dart').readAsStringSync(),
      'class ToolMod {}\n',
    );
    expect(plan.files, hasLength(1));
    expect(plan.directories, contains('lib/modding'));
    expect(plan.skipped, isEmpty);
  });

  test('planAll 可在验证模式下允许目标已存在', () {
    writeSource('lib/modding/tool_mod.dart', 'class ToolMod {}\n');
    final request = spec(
      source: 'lib/modding/tool_mod.dart',
      destination: 'lib/modding/tool_mod.dart',
    );
    planner.applyAll(<CopyRequest>[request]);

    final plan = planner.planAll(<CopyRequest>[
      request,
    ], allowExistingTargets: true);

    expect(plan.files, hasLength(1));
    planner.verify(plan);
  });

  test('plan 只生成计划，不写文件', () {
    writeSource('lib/modding/tool_mod.dart', 'class ToolMod {}\n');

    final plan = planner.planAll([
      spec(
        source: 'lib/modding/tool_mod.dart',
        destination: 'lib/modding/tool_mod.dart',
      ),
    ]);

    expect(
      File('${worktree.path}/lib/modding/tool_mod.dart').existsSync(),
      isFalse,
    );
    expect(plan.files.single.destinationRelative, 'lib/modding/tool_mod.dart');
    expect(plan.files.single.size, greaterThan(0));
  });

  test('复制目录树并保留二进制字节', () {
    writeSource('lib/features/a/one.dart', 'one\n');
    writeSource('lib/features/a/deep/two.dart', 'two\n');
    final bytes = List<int>.generate(256, (index) => 255 - index);
    final binary = File('${overlay.path}/assets/logo.bin')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes);

    final plan = planner.applyAll([spec()]);

    expect(
      File('${worktree.path}/lib/features/a/one.dart').readAsStringSync(),
      'one\n',
    );
    expect(
      File('${worktree.path}/lib/features/a/deep/two.dart').readAsStringSync(),
      'two\n',
    );
    expect(File('${worktree.path}/assets/logo.bin').readAsBytesSync(), bytes);
    expect(binary.existsSync(), isTrue);
    expect(plan.files, hasLength(3));
    expect(
      plan.directories,
      containsAll([
        'lib/features',
        'lib/features/a',
        'lib/features/a/deep',
        'assets',
      ]),
    );
  });

  test('目标已存在时拒绝覆盖且不写入同批其他文件', () {
    File('${worktree.path}/lib/modding/tool_mod.dart')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('upstream\n');
    writeSource('lib/modding/tool_mod.dart', 'mod\n');
    writeSource('lib/modding/other.dart', 'other\n');

    expect(() => planner.applyAll([spec()]), throwsA(_copyError('已存在')));

    expect(
      File('${worktree.path}/lib/modding/tool_mod.dart').readAsStringSync(),
      'upstream\n',
    );
    expect(
      File('${worktree.path}/lib/modding/other.dart').existsSync(),
      isFalse,
    );
  });

  test('排除构建和版本控制目录', () {
    writeSource('lib/keep.dart', 'keep\n');
    writeSource('build/out.txt', 'build\n');
    writeSource('.dart_tool/cache.bin', 'cache');
    writeSource('.gradle/gradle.properties', 'gradle');
    writeSource('.git/overlay-marker', 'overlay-git\n');

    final plan = planner.applyAll([spec()]);

    expect(File('${worktree.path}/lib/keep.dart').existsSync(), isTrue);
    for (final path in [
      'build/out.txt',
      '.dart_tool/cache.bin',
      '.gradle/gradle.properties',
    ]) {
      expect(File('${worktree.path}/$path').existsSync(), isFalse);
    }
    expect(File('${worktree.path}/.git/overlay-marker').existsSync(), isFalse);
    expect(
      plan.skipped.map((item) => item.path),
      containsAll(['build', '.dart_tool', '.gradle', '.git']),
    );
  });

  test('排除锁文件和本地秘密文件', () {
    writeSource('lib/keep.dart', 'keep\n');
    writeSource('pubspec.lock', 'lock');
    writeSource('.env', 'SECRET=1');
    writeSource('key.properties', 'storePassword=x');
    writeSource('signing.jks', 'jks');
    writeSource('lib/secrets/token.dart', 'token');

    final plan = planner.applyAll([spec()]);

    expect(File('${worktree.path}/lib/keep.dart').existsSync(), isTrue);
    for (final path in [
      'pubspec.lock',
      '.env',
      'key.properties',
      'signing.jks',
      'lib/secrets/token.dart',
    ]) {
      expect(File('${worktree.path}/$path').existsSync(), isFalse);
    }
    expect(
      plan.skipped.map((item) => item.path),
      containsAll([
        'pubspec.lock',
        '.env',
        'key.properties',
        'signing.jks',
        'lib/secrets',
      ]),
    );
  });

  test('拒绝 SSH 私钥和签名秘密文件', () {
    writeSource('lib/keep.dart', 'keep\n');
    writeSource('id_rsa', 'PRIVATE KEY');

    expect(() => planner.planAll([spec()]), throwsA(_copyError('SSH')));

    File('${overlay.path}/id_rsa').deleteSync();
    expect(
      () => planner.planAll([
        spec(source: 'lib/keep.dart', destination: 'config/id_rsa'),
      ]),
      throwsA(_copyError('SSH')),
    );
  });

  test('自定义排除项按目录前缀生效', () {
    writeSource('lib/generated/a.dart', 'a\n');
    writeSource('lib/keep.dart', 'keep\n');

    final plan = planner.applyAll([
      spec(exclude: ['lib/generated']),
    ]);

    expect(File('${worktree.path}/lib/generated/a.dart').existsSync(), isFalse);
    expect(File('${worktree.path}/lib/keep.dart').existsSync(), isTrue);
    expect(plan.skipped.single.path, 'lib/generated');
    expect(plan.skipped.single.reason, '排除项');
  });

  test('拒绝复制源中的符号链接', () {
    writeSource('lib/keep.dart', 'keep\n');
    final link = Link('${overlay.path}/lib/link.dart');
    try {
      link.createSync('${overlay.path}/lib/keep.dart');
    } on FileSystemException {
      markTestSkipped('当前环境不允许创建符号链接');
      return;
    }

    expect(() => planner.planAll([spec()]), throwsA(_copyError('符号链接')));
  });

  test('拒绝经过符号链接的目标路径', () {
    writeSource('lib/keep.dart', 'keep\n');
    final outside = Directory('${tempDir.path}/outside')..createSync();
    final link = Link('${worktree.path}/linkdir');
    try {
      link.createSync(outside.path);
    } on FileSystemException {
      markTestSkipped('当前环境不允许创建符号链接');
      return;
    }

    expect(
      () => planner.planAll([
        spec(source: 'lib/keep.dart', destination: 'linkdir/keep.dart'),
      ]),
      throwsA(_copyError('符号链接')),
    );
  });

  test('拒绝路径穿越目标', () {
    writeSource('lib/keep.dart', 'keep\n');

    expect(
      () => planner.planAll([
        spec(source: 'lib/keep.dart', destination: '../escape.dart'),
      ]),
      throwsA(_copyError('路径穿越')),
    );
  });

  test('拒绝绝对目标路径', () {
    writeSource('lib/keep.dart', 'keep\n');

    expect(
      () => planner.planAll([
        spec(source: 'lib/keep.dart', destination: '/tmp/escape.dart'),
      ]),
      throwsA(_copyError('相对路径')),
    );
    expect(
      () => planner.planAll([
        spec(source: 'lib/keep.dart', destination: 'C:/escape.dart'),
      ]),
      throwsA(_copyError('相对路径')),
    );
  });

  test('拒绝写入 .git', () {
    writeSource('lib/keep.dart', 'keep\n');

    expect(
      () => planner.planAll([
        spec(source: 'lib/keep.dart', destination: '.git/hooks/pre-commit'),
      ]),
      throwsA(_copyError('.git')),
    );
  });

  test('拒绝与现有文件的大小写冲突', () {
    File('${worktree.path}/lib/Foo.dart').writeAsStringSync('upstream\n');
    writeSource('lib/foo.dart', 'mod\n');

    expect(
      () => planner.planAll([
        spec(source: 'lib/foo.dart', destination: 'lib/foo.dart'),
      ]),
      throwsA(_copyError('大小写')),
    );
  });

  test('拒绝计划内目标的大小写冲突', () {
    writeSource('one/lib/File.dart', 'one\n');
    writeSource('two/lib/file.dart', 'two\n');

    expect(
      () => planner.planAll([
        spec(source: 'one', destination: '.'),
        spec(source: 'two', destination: '.'),
      ]),
      throwsA(_copyError('大小写')),
    );
  });

  test('拒绝多个复制源指向同一目标', () {
    writeSource('one/lib/same.dart', 'one\n');
    writeSource('two/lib/same.dart', 'two\n');

    expect(
      () => planner.planAll([
        spec(source: 'one', destination: '.'),
        spec(source: 'two', destination: '.'),
      ]),
      throwsA(_copyError('同一目标')),
    );
  });

  test('复制源全部被排除时失败', () {
    writeSource('build/out.txt', 'build\n');

    expect(() => planner.planAll([spec()]), throwsA(_copyError('没有可复制')));
  });

  test('复制后校验能发现目标被篡改', () {
    writeSource('lib/keep.dart', 'keep\n');
    final plan = planner.applyAll([spec()]);

    planner.verify(plan);
    File('${worktree.path}/lib/keep.dart').writeAsStringSync('tampered\n');

    expect(() => planner.verify(plan), throwsA(_copyError('不一致')));
  });

  test('拒绝 Windows 保留文件名', () {
    writeSource('lib/keep.dart', 'keep\n');

    expect(
      () => planner.planAll([
        spec(source: 'lib/keep.dart', destination: 'con.txt'),
      ]),
      throwsA(_copyError('保留')),
    );
  });

  test('拒绝以点结尾的目标路径段', () {
    writeSource('lib/keep.dart', 'keep\n');

    expect(
      () => planner.planAll([
        spec(source: 'lib/keep.dart', destination: 'lib/keep.'),
      ]),
      throwsA(_copyError('结尾')),
    );
  });

  test('拒绝目标路径的上级是文件', () {
    writeSource('lib/child.dart', 'child\n');

    expect(
      () => planner.planAll([
        spec(
          source: 'lib/child.dart',
          destination: 'lib/existing.dart/child.dart',
        ),
      ]),
      throwsA(_copyError('上级')),
    );
  });

  test('目标为已存在目录时失败', () {
    writeSource('lib/keep.dart', 'keep\n');

    expect(
      () =>
          planner.planAll([spec(source: 'lib/keep.dart', destination: 'lib')]),
      throwsA(_copyError('已存在')),
    );
  });

  test('文件复制目标不能是 worktree 根目录', () {
    writeSource('lib/keep.dart', 'keep\n');

    expect(
      () => planner.planAll([spec(source: 'lib/keep.dart', destination: '.')]),
      throwsA(_copyError('根目录')),
    );
  });

  test('拒绝不存在的复制源', () {
    expect(
      () => planner.planAll([
        spec(source: 'missing.dart', destination: 'lib/missing.dart'),
      ]),
      throwsA(_copyError('不存在')),
    );
  });

  test('拒绝不存在的复制源根目录', () {
    expect(
      () => planner.planAll([
        CopyRequest(
          sourceRoot: '${tempDir.path}/missing',
          source: '.',
          destination: '.',
        ),
      ]),
      throwsA(_copyError('根目录')),
    );
  });

  test('拒绝源路径穿越', () {
    expect(
      () => planner.planAll([
        spec(source: '../outside', destination: 'lib/x.dart'),
      ]),
      throwsA(_copyError('路径穿越')),
    );
  });

  test('拒绝目标中的排除目录', () {
    writeSource('lib/keep.dart', 'keep\n');

    expect(
      () => planner.planAll([
        spec(source: 'lib/keep.dart', destination: 'build/keep.dart'),
      ]),
      throwsA(_copyError('默认排除')),
    );
  });

  test('拒绝目标中的秘密路径和锁文件', () {
    writeSource('lib/keep.dart', 'keep\n');

    expect(
      () => planner.planAll([
        spec(source: 'lib/keep.dart', destination: 'lib/secrets/token.dart'),
      ]),
      throwsA(_copyError('默认排除')),
    );
    expect(
      () => planner.planAll([
        spec(source: 'lib/keep.dart', destination: 'pubspec.lock'),
      ]),
      throwsA(_copyError('默认排除')),
    );
  });

  test('复制目录到新的嵌套目标', () {
    writeSource('lib/keep.dart', 'keep\n');

    final plan = planner.applyAll([
      spec(source: 'lib', destination: 'lib/modding/overlay'),
    ]);

    expect(
      File('${worktree.path}/lib/modding/overlay/keep.dart').readAsStringSync(),
      'keep\n',
    );
    expect(
      plan.directories,
      containsAll(['lib/modding', 'lib/modding/overlay']),
    );
  });

  test('空复制项列表返回空计划', () {
    final plan = planner.planAll([]);

    expect(plan.files, isEmpty);
    expect(plan.directories, isEmpty);
    expect(plan.skipped, isEmpty);
  });
}

Matcher _copyError(String fragment) {
  return isA<CopyException>().having(
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
