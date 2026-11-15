import 'dart:convert';
import 'dart:io';

import 'paths.dart';

const Utf8Codec _utf8 = Utf8Codec(allowMalformed: true);

/// Windows 超长路径的进程级 Git 配置：只对当前 git 进程生效，
/// 不写入仓库、全局或上游配置。
const List<String> _longPathsConfig = <String>['-c', 'core.longpaths=true'];

const String _longPathMarker = 'Filename too long';

/// `git worktree add` 失败时把 Git 的裸报错转成可执行提示。
///
/// 超长路径失败时 Git 会先报 `Filename too long`，再补一句
/// `fatal: Could not reset index file to revision 'HEAD'`；后者容易
/// 被误判为上游仓库损坏，因此在提示里指明真实原因。
String worktreeAddFailureMessage(GitResult result) {
  final stderrText = result.stderr;
  if (stderrText.contains(_longPathMarker)) {
    return 'worktree add 失败（退出码 ${result.exitCode}）：'
        'Windows 路径超过 260 字符，Git 无法检出上游文件'
        '（$_longPathMarker）。\n'
        'Loader 已对该 git 进程传入 -c core.longpaths=true；'
        '仍然失败说明该进程级设置未覆盖到出错的文件操作'
        '（例如外部工具或系统调用链）。\n'
        '处理方式：把私有仓或合成目录移到更短的绝对路径。\n'
        '注意：修改系统注册表 LongPathsEnabled 只影响声明了 '
        'longPathAware 的程序，实测不能修复 Git 的这条失败，'
        '不要把它当成 Git 的开关。\n'
        '这不是上游仓库损坏，也不是索引文件损坏；处理后可重试 apply。';
  }
  return 'worktree add 失败（退出码 ${result.exitCode}）';
}

class GitResult {
  const GitResult({
    required this.args,
    required this.workingDirectory,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final List<String> args;
  final String workingDirectory;
  final int exitCode;
  final String stdout;
  final String stderr;

  bool get succeeded => exitCode == 0;

  String get output => stdout.trim();

  String get commandLine {
    final buffer = StringBuffer('git');
    for (final arg in args) {
      buffer.write(' ');
      buffer.write(_quoteForDisplay(arg));
    }
    return buffer.toString();
  }
}

class GitException implements Exception {
  GitException(this.result, this.message);

  final GitResult result;
  final String message;

  @override
  String toString() {
    final buffer = StringBuffer(message)
      ..writeln()
      ..writeln('命令：${result.commandLine}')
      ..writeln('目录：${result.workingDirectory}');
    final stderrText = result.stderr.trim();
    if (stderrText.isNotEmpty) buffer.writeln('stderr：$stderrText');
    final stdoutText = result.stdout.trim();
    if (stdoutText.isNotEmpty) buffer.writeln('stdout：$stdoutText');
    return buffer.toString().trimRight();
  }
}

class GitStatusEntry {
  const GitStatusEntry({required this.status, required this.path});

  final String status;
  final String path;

  bool get isRenameOrCopy => status.contains('R') || status.contains('C');
}

class GitWorktreeEntry {
  const GitWorktreeEntry({
    required this.path,
    required this.head,
    required this.branch,
    required this.detached,
    required this.locked,
    required this.prunable,
  });

  final String path;
  final String? head;
  final String? branch;
  final bool detached;
  final bool locked;
  final bool prunable;
}

class Git {
  Git({required String workingDirectory, Map<String, String>? environment})
    : workingDirectory = stripTrailingSlashes(toPosixPath(workingDirectory)),
      _environment = Map<String, String>.unmodifiable(
        environment ?? const <String, String>{},
      );

  final String workingDirectory;
  final Map<String, String> _environment;

  Future<GitResult> run(
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    if (args.isEmpty) throw ArgumentError('Git 参数不能为空');
    final effectiveArgs = <String>[..._longPathsConfig, ...args];
    final directory = workingDirectory ?? this.workingDirectory;
    final ProcessResult result;
    try {
      result = await Process.run(
        'git',
        effectiveArgs,
        workingDirectory: directory,
        stdoutEncoding: _utf8,
        stderrEncoding: _utf8,
        environment: <String, String>{
          'GIT_TERMINAL_PROMPT': '0',
          ..._environment,
          ...?environment,
        },
      );
    } on ProcessException catch (error) {
      throw GitException(
        GitResult(
          args: List<String>.unmodifiable(effectiveArgs),
          workingDirectory: directory,
          exitCode: -1,
          stdout: '',
          stderr: error.message,
        ),
        '无法执行 git：${error.message}',
      );
    }
    return GitResult(
      args: List<String>.unmodifiable(effectiveArgs),
      workingDirectory: directory,
      exitCode: result.exitCode,
      stdout: result.stdout as String,
      stderr: result.stderr as String,
    );
  }

  Future<GitResult> runChecked(
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final result = await run(
      args,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    if (!result.succeeded) {
      throw GitException(result, 'Git 命令失败（退出码 ${result.exitCode}）');
    }
    return result;
  }

  Future<String> topLevel() async {
    final result = await runChecked(<String>['rev-parse', '--show-toplevel']);
    return result.output;
  }

  Future<bool> isInsideWorkTree() async {
    final result = await run(<String>['rev-parse', '--is-inside-work-tree']);
    return result.succeeded && result.output == 'true';
  }

  Future<String> revParseCommit(String ref) async {
    final result = await run(<String>[
      'rev-parse',
      '--verify',
      '--quiet',
      '$ref^{commit}',
    ]);
    if (!result.succeeded) {
      throw GitException(result, '无法解析 commit：$ref');
    }
    final commit = result.output;
    if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(commit)) {
      throw GitException(result, 'Git 返回了非完整 commit：$commit');
    }
    return commit;
  }

  Future<String?> objectType(String ref) async {
    final result = await run(<String>['cat-file', '-t', ref]);
    if (!result.succeeded) return null;
    return result.output;
  }

  Future<bool> commitExists(String commit) async {
    final result = await run(<String>['cat-file', '-e', '$commit^{commit}']);
    return result.succeeded;
  }

  Future<String> headCommit({String? workingDirectory}) async {
    final result = await runChecked(<String>[
      'rev-parse',
      '--verify',
      'HEAD^{commit}',
    ], workingDirectory: workingDirectory);
    final commit = result.output;
    if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(commit)) {
      throw GitException(result, 'Git 返回了非完整 HEAD commit：$commit');
    }
    return commit;
  }

  Future<List<GitStatusEntry>> trackedChanges({
    String? workingDirectory,
  }) async {
    final staged = await runChecked(<String>[
      'diff',
      '--cached',
      '--name-status',
      '-z',
      '--no-color',
      '--no-ext-diff',
      '--find-renames',
    ], workingDirectory: workingDirectory);
    final unstaged = await runChecked(<String>[
      'diff',
      '--name-status',
      '-z',
      '--no-color',
      '--no-ext-diff',
      '--find-renames',
    ], workingDirectory: workingDirectory);
    return _mergeDiffChanges(
      staged: _parseNameStatusZ(staged.stdout),
      unstaged: _parseNameStatusZ(unstaged.stdout),
    );
  }

  Future<String> cachedDiff({String? workingDirectory}) async {
    final result = await runChecked(<String>[
      'diff',
      '--cached',
      '--binary',
      '--full-index',
      '--no-color',
      '--no-ext-diff',
    ], workingDirectory: workingDirectory);
    return result.stdout;
  }

  Future<List<GitWorktreeEntry>> worktreeList() async {
    final result = await runChecked(<String>[
      'worktree',
      'list',
      '--porcelain',
    ]);
    return _parseWorktreeList(result.stdout);
  }

  Future<void> worktreeAddDetached({
    required String path,
    required String commit,
  }) async {
    final result = await run(<String>[
      '-c',
      'core.autocrlf=false',
      'worktree',
      'add',
      '--detach',
      path,
      commit,
    ]);
    if (!result.succeeded) {
      throw GitException(result, worktreeAddFailureMessage(result));
    }
  }

  Future<void> worktreeRemove({
    required String path,
    bool force = false,
  }) async {
    final args = <String>['worktree', 'remove'];
    if (force) args.add('--force');
    args.add(path);
    await runChecked(args);
  }
}

class _DiffChange {
  const _DiffChange({required this.status, required this.path});

  final String status;
  final String path;
}

List<_DiffChange> _parseNameStatusZ(String output) {
  final parts = output.split('\x00');
  final changes = <_DiffChange>[];
  var index = 0;
  while (index < parts.length) {
    final status = parts[index];
    if (status.isEmpty) {
      index++;
      continue;
    }
    final code = status.substring(0, 1);
    final isRenameOrCopy = code == 'R' || code == 'C';
    final pathIndex = isRenameOrCopy ? index + 2 : index + 1;
    if (pathIndex >= parts.length || parts[pathIndex].isEmpty) {
      throw FormatException('无法解析 git diff --name-status 输出：$status');
    }
    changes.add(_DiffChange(status: code, path: parts[pathIndex]));
    index = pathIndex + 1;
  }
  return changes;
}

List<GitStatusEntry> _mergeDiffChanges({
  required List<_DiffChange> staged,
  required List<_DiffChange> unstaged,
}) {
  final indexStatus = <String, String>{
    for (final change in staged) change.path: change.status,
  };
  final worktreeStatus = <String, String>{
    for (final change in unstaged) change.path: change.status,
  };
  final paths = <String>{...indexStatus.keys, ...worktreeStatus.keys}.toList()
    ..sort();
  return <GitStatusEntry>[
    for (final path in paths)
      GitStatusEntry(
        status: '${indexStatus[path] ?? ' '}${worktreeStatus[path] ?? ' '}',
        path: path,
      ),
  ];
}

List<GitWorktreeEntry> _parseWorktreeList(String output) {
  final entries = <GitWorktreeEntry>[];
  String? path;
  String? head;
  String? branch;
  var detached = false;
  var locked = false;
  var prunable = false;

  void flush() {
    if (path != null) {
      entries.add(
        GitWorktreeEntry(
          path: path!,
          head: head,
          branch: branch,
          detached: detached,
          locked: locked,
          prunable: prunable,
        ),
      );
    }
    path = null;
    head = null;
    branch = null;
    detached = false;
    locked = false;
    prunable = false;
  }

  for (final line in const LineSplitter().convert(output)) {
    if (line.isEmpty) {
      flush();
      continue;
    }
    if (line.startsWith('worktree ')) {
      path = line.substring('worktree '.length);
    } else if (line.startsWith('HEAD ')) {
      head = line.substring('HEAD '.length);
    } else if (line.startsWith('branch ')) {
      branch = line.substring('branch '.length);
    } else if (line == 'detached') {
      detached = true;
    } else if (line == 'locked' || line.startsWith('locked ')) {
      locked = true;
    } else if (line == 'prunable' || line.startsWith('prunable ')) {
      prunable = true;
    }
  }
  flush();
  return entries;
}

String _quoteForDisplay(String arg) {
  if (arg.isEmpty || arg.contains(RegExp(r'[\s"\\]'))) {
    return '"${arg.replaceAll('"', r'\"')}"';
  }
  return arg;
}
