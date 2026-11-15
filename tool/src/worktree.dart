import 'dart:convert';
import 'dart:io';

import 'build_artifacts.dart';
import 'git.dart';
import 'hash.dart';
import 'paths.dart';

const String _stateSuffix = '.state.json';

enum WorktreeStatus { creating, ready, failed }

class WorktreeState {
  const WorktreeState({
    required this.modsetHash,
    required this.upstreamPath,
    required this.upstreamCommit,
    required this.worktreePath,
    required this.status,
    this.failure,
  });

  static const int schemaVersion = 1;

  final String modsetHash;
  final String upstreamPath;
  final String upstreamCommit;
  final String worktreePath;
  final WorktreeStatus status;
  final String? failure;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'modsetHash': modsetHash,
    'upstreamPath': upstreamPath,
    'upstreamCommit': upstreamCommit,
    'worktreePath': worktreePath,
    'status': status.name,
    if (failure != null) 'failure': failure,
  };
}

class WorktreeHandle {
  const WorktreeHandle({
    required this.path,
    required this.modsetHash,
    required this.upstreamCommit,
    required this.reused,
  });

  final String path;
  final String modsetHash;
  final String upstreamCommit;
  final bool reused;

  Directory get directory => Directory(path);
}

class WorktreeVerification {
  const WorktreeVerification({
    required this.path,
    required this.headCommit,
    required this.issues,
  });

  final String path;
  final String? headCommit;
  final List<String> issues;

  bool get isValid => issues.isEmpty;
}

class WorktreeCleanResult {
  const WorktreeCleanResult({
    required this.modsetHash,
    required this.path,
    required this.removedDirectory,
    required this.removedState,
  });

  final String modsetHash;
  final String path;
  final bool removedDirectory;
  final bool removedState;
}

sealed class WorktreeException implements Exception {
  WorktreeException(this.path, this.message);

  final String path;
  final String message;

  @override
  String toString() => '$runtimeType：$path：$message';
}

class UpstreamException extends WorktreeException {
  UpstreamException(super.path, super.message);
}

class UpstreamDirtyException extends UpstreamException {
  UpstreamDirtyException(String path, this.changes)
    : super(path, '上游仓存在未提交的已跟踪文件改动：${changes.join(', ')}');

  final List<String> changes;
}

class WorktreeStateException extends WorktreeException {
  WorktreeStateException(super.path, super.message);
}

class WorktreeCreationException extends WorktreeException {
  WorktreeCreationException(super.path, super.message, this.cause);

  final Object cause;
}

class WorktreeVerificationException extends WorktreeException {
  WorktreeVerificationException(String path, this.issues)
    : super(path, '合成树校验失败：\n${issues.map((issue) => '- $issue').join('\n')}');

  final List<String> issues;
}

class WorktreeCleanException extends WorktreeException {
  WorktreeCleanException(super.path, super.message);
}

class WorktreeManager {
  WorktreeManager({
    required String privateRepoRoot,
    required String upstreamPath,
    required String upstreamCommit,
    Git? git,
  }) : privateRepoRoot = _normalizeAbsolute(privateRepoRoot, 'privateRepoRoot'),
       upstreamPath = _normalizeAbsolute(upstreamPath, 'upstreamPath'),
       upstreamCommit = _validateCommit(upstreamCommit) {
    if (isWithinDirectory(this.upstreamPath, this.privateRepoRoot)) {
      throw ArgumentError('私有仓不能位于上游仓内部：${this.privateRepoRoot}');
    }
    _git = git ?? Git(workingDirectory: this.upstreamPath);
  }

  final String privateRepoRoot;
  final String upstreamPath;
  final String upstreamCommit;
  late final Git _git;

  Git get git => _git;

  String get buildRoot => joinPath(privateRepoRoot, '.build');

  String get worktreesRoot => joinPath(buildRoot, 'worktrees');

  String worktreePathFor(String modsetHash) =>
      joinPath(worktreesRoot, modsetDirectoryName(modsetHash));

  Future<WorktreeHandle> createOrReuse({
    required String modsetHash,
    required Future<void> Function(WorktreeHandle handle) synthesize,
    bool allowTrackedChanges = false,
  }) async {
    _requireFullHash(modsetHash);
    await _validateUpstream();

    final path = worktreePathFor(modsetHash);
    final stateFile = File(_statePathFor(modsetHash));
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    final stateExists = stateFile.existsSync();

    if (type != FileSystemEntityType.notFound) {
      if (type != FileSystemEntityType.directory) {
        throw WorktreeStateException(path, '目标路径已存在且不是目录，拒绝覆盖');
      }
      if (!stateExists) {
        throw WorktreeStateException(
          path,
          '合成目录已存在但没有 Loader 状态记录，拒绝覆盖；请人工检查后清理',
        );
      }
      final state = _readState(stateFile);
      _validateStateForReuse(state, modsetHash, path);
      await _verifyReusable(
        path,
        modsetHash,
        allowTrackedChanges: allowTrackedChanges,
      );
      return WorktreeHandle(
        path: path,
        modsetHash: modsetHash,
        upstreamCommit: upstreamCommit,
        reused: true,
      );
    }

    if (stateExists) {
      throw WorktreeStateException(
        path,
        '状态文件存在但合成目录缺失，请先执行 clean --modset $modsetHash',
      );
    }

    _ensureWorktreesRoot();
    final relativePath = relativeTo(privateRepoRoot, path);
    if (relativePath == null) {
      throw WorktreeStateException(path, '合成目录不在私有仓内');
    }
    _writeState(
      stateFile,
      WorktreeState(
        modsetHash: modsetHash,
        upstreamPath: upstreamPath,
        upstreamCommit: upstreamCommit,
        worktreePath: relativePath,
        status: WorktreeStatus.creating,
      ),
    );

    final handle = WorktreeHandle(
      path: path,
      modsetHash: modsetHash,
      upstreamCommit: upstreamCommit,
      reused: false,
    );
    try {
      await _git.worktreeAddDetached(path: path, commit: upstreamCommit);
      final head = await _gitAt(path).headCommit();
      if (head != upstreamCommit) {
        throw WorktreeStateException(
          path,
          '创建后的 HEAD $head 与固定基线 $upstreamCommit 不一致',
        );
      }
      await synthesize(handle);
      _writeState(
        stateFile,
        WorktreeState(
          modsetHash: modsetHash,
          upstreamPath: upstreamPath,
          upstreamCommit: upstreamCommit,
          worktreePath: relativePath,
          status: WorktreeStatus.ready,
        ),
      );
      return handle;
    } catch (error) {
      final needsClean = await _recordFailure(
        stateFile: stateFile,
        path: path,
        modsetHash: modsetHash,
        relativePath: relativePath,
        error: error,
      );
      if (error is WorktreeException) rethrow;
      final hint = needsClean
          ? '\n重试前请执行 dart tool/mod_loader.dart clean --modset $modsetHash'
          : '';
      throw WorktreeCreationException(
        path,
        '创建或合成 worktree 失败：$error$hint',
        error,
      );
    }
  }

  Future<WorktreeVerification> verify({
    required String modsetHash,
    bool allowTrackedChanges = false,
  }) async {
    _requireFullHash(modsetHash);
    final path = worktreePathFor(modsetHash);
    final stateFile = File(_statePathFor(modsetHash));
    final issues = <String>[];
    final buildIssue = _buildRootIssue();
    if (buildIssue != null) {
      issues.add(buildIssue);
      return WorktreeVerification(
        path: path,
        headCommit: null,
        issues: List<String>.unmodifiable(issues),
      );
    }
    String? head;
    final type = FileSystemEntity.typeSync(path, followLinks: false);

    if (type == FileSystemEntityType.notFound) {
      issues.add('合成目录不存在：$path');
    } else if (type != FileSystemEntityType.directory) {
      issues.add('合成路径不是目录：$path');
    }

    if (!stateFile.existsSync()) {
      issues.add('缺少 Loader 状态文件：${stateFile.path}');
    } else {
      try {
        final state = _readState(stateFile);
        if (state.status != WorktreeStatus.ready) {
          issues.add('状态不是 ready：${state.status.name}');
        }
        if (state.modsetHash != modsetHash) {
          issues.add('状态 modsetHash 不匹配：${state.modsetHash}');
        }
        if (!samePath(state.upstreamPath, upstreamPath)) {
          issues.add('状态 upstreamPath 不匹配：${state.upstreamPath}');
        }
        if (state.upstreamCommit != upstreamCommit) {
          issues.add('状态 upstreamCommit 不匹配：${state.upstreamCommit}');
        }
        final expectedRelative = relativeTo(privateRepoRoot, path);
        if (expectedRelative == null ||
            !samePath(state.worktreePath, expectedRelative)) {
          issues.add('状态 worktreePath 不匹配：${state.worktreePath}');
        }
      } on WorktreeStateException catch (error) {
        issues.add(error.message);
      }
    }

    if (type == FileSystemEntityType.directory) {
      try {
        final entries = await _git.worktreeList();
        if (!entries.any((entry) => samePath(entry.path, path))) {
          issues.add('Git 未登记该 worktree：$path');
        }
        head = await _gitAt(path).headCommit();
        if (head != upstreamCommit) {
          issues.add('HEAD 为 $head，与固定基线 $upstreamCommit 不一致');
        }
        final changes = await _gitAt(path).trackedChanges();
        if (!allowTrackedChanges) {
          for (final change in changes) {
            if (!isAllowedBuildArtifact(change.path)) {
              issues.add('已跟踪文件被修改：${change.path}');
            }
          }
        }
      } on GitException catch (error) {
        issues.add('无法检查 worktree：${error.message}');
      }
    }

    return WorktreeVerification(
      path: path,
      headCommit: head,
      issues: List<String>.unmodifiable(issues),
    );
  }

  Future<WorktreeVerification> verifyOrThrow({
    required String modsetHash,
    bool allowTrackedChanges = false,
  }) async {
    final verification = await verify(
      modsetHash: modsetHash,
      allowTrackedChanges: allowTrackedChanges,
    );
    if (!verification.isValid) {
      throw WorktreeVerificationException(
        verification.path,
        verification.issues,
      );
    }
    return verification;
  }

  Future<WorktreeCleanResult> clean({required String modsetHash}) async {
    final fullHash = _resolveModsetHash(modsetHash);
    final buildIssue = _buildRootIssue();
    if (buildIssue != null) {
      throw WorktreeCleanException(worktreesRoot, buildIssue);
    }
    final path = worktreePathFor(fullHash);
    final stateFile = File(_statePathFor(fullHash));
    if (!stateFile.existsSync()) {
      throw WorktreeCleanException(path, '缺少 Loader 状态记录，拒绝清理');
    }

    final WorktreeState state;
    try {
      state = _readState(stateFile);
    } on WorktreeStateException catch (error) {
      throw WorktreeCleanException(path, '状态文件损坏，拒绝清理：${error.message}');
    }
    if (state.modsetHash != fullHash) {
      throw WorktreeCleanException(path, '状态记录与目标 modsetHash 不一致');
    }
    final expectedRelative = relativeTo(privateRepoRoot, path);
    if (expectedRelative == null ||
        !samePath(state.worktreePath, expectedRelative)) {
      throw WorktreeCleanException(path, '状态记录中的 worktreePath 与目标不一致');
    }
    if (!isWithinDirectory(worktreesRoot, path)) {
      throw WorktreeCleanException(path, '目标不在 .build/worktrees 下');
    }

    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.directory) {
      throw WorktreeCleanException(path, '目标路径不是目录，拒绝清理');
    }

    final List<GitWorktreeEntry> entries;
    try {
      entries = await _git.worktreeList();
    } on GitException catch (error) {
      throw WorktreeCleanException(
        path,
        '无法读取 Git worktree 列表：${error.message}',
      );
    }
    final registered = entries.any((entry) => samePath(entry.path, path));

    if (type == FileSystemEntityType.notFound) {
      if (registered) {
        try {
          await _git.worktreeRemove(path: path, force: true);
        } on GitException catch (error) {
          throw WorktreeCleanException(
            path,
            '目录已缺失，git worktree remove 失败：${error.message}',
          );
        }
        final List<GitWorktreeEntry> after;
        try {
          after = await _git.worktreeList();
        } on GitException catch (error) {
          throw WorktreeCleanException(
            path,
            '无法确认 Git worktree 是否已移除：${error.message}',
          );
        }
        if (after.any((entry) => samePath(entry.path, path))) {
          throw WorktreeCleanException(path, 'Git 仍登记该 worktree，未删除状态记录');
        }
      }
      try {
        stateFile.deleteSync();
      } on FileSystemException catch (error) {
        throw WorktreeCleanException(path, '状态文件删除失败：${error.message}');
      }
      return WorktreeCleanResult(
        modsetHash: fullHash,
        path: path,
        removedDirectory: false,
        removedState: true,
      );
    }

    if (registered) {
      try {
        await _git.worktreeRemove(path: path, force: true);
      } on GitException catch (error) {
        throw WorktreeCleanException(
          path,
          'git worktree remove 失败，可能被文件锁占用：${error.message}',
        );
      }
      final List<GitWorktreeEntry> after;
      try {
        after = await _git.worktreeList();
      } on GitException catch (error) {
        throw WorktreeCleanException(
          path,
          '无法确认 Git worktree 是否已移除：${error.message}',
        );
      }
      if (after.any((entry) => samePath(entry.path, path))) {
        throw WorktreeCleanException(path, 'Git 仍登记该 worktree，未删除状态记录');
      }
    } else {
      try {
        Directory(path).deleteSync(recursive: true);
      } on FileSystemException catch (error) {
        throw WorktreeCleanException(path, '删除目录失败，可能被文件锁占用：${error.message}');
      }
    }

    if (Directory(path).existsSync()) {
      throw WorktreeCleanException(path, '目录仍然存在，未删除状态记录');
    }
    try {
      stateFile.deleteSync();
    } on FileSystemException catch (error) {
      throw WorktreeCleanException(path, '目录已删除但状态文件删除失败：${error.message}');
    }
    return WorktreeCleanResult(
      modsetHash: fullHash,
      path: path,
      removedDirectory: true,
      removedState: true,
    );
  }

  Future<void> _validateUpstream() async {
    final directory = Directory(upstreamPath);
    if (!directory.existsSync()) {
      throw UpstreamException(upstreamPath, '上游仓路径不存在');
    }
    try {
      if (!await _git.isInsideWorkTree()) {
        throw UpstreamException(upstreamPath, '上游路径不是 Git 工作树');
      }
      final top = await _git.topLevel();
      if (!samePath(top, upstreamPath)) {
        throw UpstreamException(upstreamPath, '上游路径不是 Git 仓库根目录（实际根目录：$top）');
      }
      final type = await _git.objectType(upstreamCommit);
      if (type != 'commit') {
        throw UpstreamException(
          upstreamPath,
          '固定基线 $upstreamCommit 不是存在的 commit（实际类型：${type ?? '不存在'}）',
        );
      }
      final changes = await _git.trackedChanges();
      if (changes.isNotEmpty) {
        throw UpstreamDirtyException(
          upstreamPath,
          changes.map((change) => change.path).toList(growable: false),
        );
      }
    } on GitException catch (error) {
      throw UpstreamException(upstreamPath, '无法检查上游仓：${error.message}');
    }
  }

  void _validateStateForReuse(
    WorktreeState state,
    String modsetHash,
    String path,
  ) {
    if (state.status != WorktreeStatus.ready) {
      throw WorktreeStateException(
        path,
        '合成树状态为 ${state.status.name}，不是 ready；请先执行 clean --modset $modsetHash',
      );
    }
    if (state.modsetHash != modsetHash) {
      throw WorktreeStateException(
        path,
        '状态记录的 modsetHash ${state.modsetHash} 与目标 $modsetHash 不一致',
      );
    }
    if (!samePath(state.upstreamPath, upstreamPath)) {
      throw WorktreeStateException(
        path,
        '状态记录的 upstreamPath ${state.upstreamPath} 与当前上游不一致',
      );
    }
    if (state.upstreamCommit != upstreamCommit) {
      throw WorktreeStateException(
        path,
        '状态记录的 upstreamCommit ${state.upstreamCommit} 与当前固定基线不一致',
      );
    }
    final expectedRelative = relativeTo(privateRepoRoot, path);
    if (expectedRelative == null ||
        !samePath(state.worktreePath, expectedRelative)) {
      throw WorktreeStateException(
        path,
        '状态记录的 worktreePath ${state.worktreePath} 与目标路径不一致',
      );
    }
  }

  Future<void> _verifyReusable(
    String path,
    String modsetHash, {
    required bool allowTrackedChanges,
  }) async {
    try {
      final entries = await _git.worktreeList();
      if (!entries.any((entry) => samePath(entry.path, path))) {
        throw WorktreeStateException(
          path,
          'Git 未登记该 worktree；请先执行 clean --modset $modsetHash',
        );
      }
      final head = await _gitAt(path).headCommit();
      if (head != upstreamCommit) {
        throw WorktreeStateException(
          path,
          'worktree HEAD 为 $head，与固定基线 $upstreamCommit 不一致；请先 clean',
        );
      }
      final changes = await _gitAt(path).trackedChanges();
      if (!allowTrackedChanges) {
        final unexpected = changes
            .where((change) => !isAllowedBuildArtifact(change.path))
            .toList(growable: false);
        if (unexpected.isNotEmpty) {
          throw WorktreeStateException(
            path,
            '合成树存在未预期的已跟踪文件改动：'
            '${unexpected.map((change) => change.path).join(', ')}；请先 clean',
          );
        }
      }
    } on GitException catch (error) {
      throw WorktreeStateException(path, '无法校验 worktree：${error.message}');
    }
  }

  String _statePathFor(String modsetHash) =>
      '${worktreePathFor(modsetHash)}$_stateSuffix';

  WorktreeState _readState(File file) {
    final stateType = FileSystemEntity.typeSync(file.path, followLinks: false);
    if (stateType == FileSystemEntityType.link) {
      throw WorktreeStateException(file.path, '状态文件不能是符号链接');
    }
    if (stateType != FileSystemEntityType.file) {
      throw WorktreeStateException(file.path, '状态文件不存在或不是普通文件');
    }
    String text;
    try {
      text = file.readAsStringSync();
    } on FileSystemException catch (error) {
      throw WorktreeStateException(file.path, '无法读取状态文件：${error.message}');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (error) {
      throw WorktreeStateException(file.path, '状态文件不是合法 JSON：${error.message}');
    }
    if (decoded is! Map) {
      throw WorktreeStateException(file.path, '状态文件根节点必须是对象');
    }
    final map = <String, Object?>{};
    for (final entry in decoded.entries) {
      if (entry.key is! String) {
        throw WorktreeStateException(file.path, '状态文件键必须是字符串');
      }
      map[entry.key as String] = entry.value;
    }
    if (map['schemaVersion'] != WorktreeState.schemaVersion) {
      throw WorktreeStateException(
        file.path,
        '不支持的状态文件 schemaVersion：${map['schemaVersion']}',
      );
    }
    final modsetHash = map['modsetHash'];
    if (modsetHash is! String || !isSha256Hex(modsetHash)) {
      throw WorktreeStateException(file.path, 'modsetHash 必须是完整 64 位 SHA-256');
    }
    final upstreamPath = map['upstreamPath'];
    if (upstreamPath is! String || absolutePathError(upstreamPath) != null) {
      throw WorktreeStateException(file.path, 'upstreamPath 必须是本机绝对路径');
    }
    final upstreamCommit = map['upstreamCommit'];
    if (upstreamCommit is! String || !isFullCommitSha(upstreamCommit)) {
      throw WorktreeStateException(
        file.path,
        'upstreamCommit 必须是完整 commit SHA',
      );
    }
    final worktreePath = map['worktreePath'];
    if (worktreePath is! String || relativePathError(worktreePath) != null) {
      throw WorktreeStateException(file.path, 'worktreePath 必须是仓库内相对路径');
    }
    final statusValue = map['status'];
    final status = switch (statusValue) {
      'creating' => WorktreeStatus.creating,
      'ready' => WorktreeStatus.ready,
      'failed' => WorktreeStatus.failed,
      _ => throw WorktreeStateException(
        file.path,
        '未知的 worktree 状态：$statusValue',
      ),
    };
    final failureValue = map['failure'];
    if (failureValue != null && failureValue is! String) {
      throw WorktreeStateException(file.path, 'failure 必须是字符串或 null');
    }
    return WorktreeState(
      modsetHash: modsetHash,
      upstreamPath: upstreamPath,
      upstreamCommit: upstreamCommit,
      worktreePath: worktreePath,
      status: status,
      failure: failureValue as String?,
    );
  }

  void _writeState(File file, WorktreeState state) {
    final stateType = FileSystemEntity.typeSync(file.path, followLinks: false);
    if (stateType == FileSystemEntityType.link) {
      throw FileSystemException('状态文件不能是符号链接', file.path);
    }
    if (stateType != FileSystemEntityType.notFound &&
        stateType != FileSystemEntityType.file) {
      throw FileSystemException('状态路径不是普通文件', file.path);
    }
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(state.toJson())}\n',
      flush: true,
    );
  }

  /// 记录失败结果，并在失败没有留下任何痕迹时撤销本次写入的状态文件。
  ///
  /// `git worktree add` 失败（例如 Windows 超长路径）通常既不留目标目录，
  /// 也不留 Git 的 worktree 登记；此时把刚写入的 `creating` 状态一并删除，
  /// 处理完根因后直接重试 `apply` 即可，不需要先 `clean`。
  /// 只要目标目录存在（检出中途失败）或 Git 仍登记该路径，就保留 `failed`
  /// 记录，避免把半成品当成就绪树复用。
  ///
  /// 返回是否保留了需要 `clean` 才能恢复的状态记录。
  Future<bool> _recordFailure({
    required File stateFile,
    required String path,
    required String modsetHash,
    required String relativePath,
    required Object error,
  }) async {
    if (FileSystemEntity.typeSync(path, followLinks: false) ==
            FileSystemEntityType.notFound &&
        !await _registeredAsWorktree(path)) {
      try {
        if (stateFile.existsSync()) stateFile.deleteSync();
        return false;
      } on FileSystemException {
        // 删除失败时退回失败记录，按需要 clean 的路径处理。
      }
    }
    _markFailed(stateFile, modsetHash, relativePath, error.toString());
    return true;
  }

  /// Git 是否仍登记该路径；查询失败时按“已登记”处理，保留失败记录。
  Future<bool> _registeredAsWorktree(String path) async {
    final List<GitWorktreeEntry> entries;
    try {
      entries = await _git.worktreeList();
    } on GitException {
      return true;
    }
    return entries.any((entry) => samePath(entry.path, path));
  }

  void _markFailed(
    File stateFile,
    String modsetHash,
    String relativePath,
    String message,
  ) {
    try {
      _writeState(
        stateFile,
        WorktreeState(
          modsetHash: modsetHash,
          upstreamPath: upstreamPath,
          upstreamCommit: upstreamCommit,
          worktreePath: relativePath,
          status: WorktreeStatus.failed,
          failure: message,
        ),
      );
    } on FileSystemException {
      // 保留原始失败原因；状态文件写入失败不覆盖它。
    }
  }

  String? _buildRootIssue() {
    final buildType = FileSystemEntity.typeSync(buildRoot, followLinks: false);
    if (buildType == FileSystemEntityType.link) {
      return '.build 不能是符号链接';
    }
    if (buildType != FileSystemEntityType.notFound &&
        buildType != FileSystemEntityType.directory) {
      return '.build 不是目录';
    }
    final worktreesType = FileSystemEntity.typeSync(
      worktreesRoot,
      followLinks: false,
    );
    if (worktreesType == FileSystemEntityType.link) {
      return '.build/worktrees 不能是符号链接';
    }
    if (worktreesType != FileSystemEntityType.notFound &&
        worktreesType != FileSystemEntityType.directory) {
      return '.build/worktrees 不是目录';
    }
    return null;
  }

  void _ensureWorktreesRoot() {
    final privateType = FileSystemEntity.typeSync(
      privateRepoRoot,
      followLinks: false,
    );
    if (privateType != FileSystemEntityType.directory) {
      throw WorktreeStateException(privateRepoRoot, '私有仓根目录不存在或不是目录');
    }
    final issue = _buildRootIssue();
    if (issue != null) throw WorktreeStateException(worktreesRoot, issue);
    Directory(worktreesRoot).createSync(recursive: true);
    final type = FileSystemEntity.typeSync(worktreesRoot, followLinks: false);
    if (type != FileSystemEntityType.directory) {
      throw WorktreeStateException(worktreesRoot, '.build/worktrees 不是目录');
    }
  }

  String _resolveModsetHash(String input) {
    if (isSha256Hex(input)) return input;
    if (!RegExp(r'^[0-9a-f]{16}$').hasMatch(input)) {
      throw ArgumentError.value(
        input,
        'modsetHash',
        '必须是完整 64 位 SHA-256 或 16 位目录前缀',
      );
    }
    final buildIssue = _buildRootIssue();
    if (buildIssue != null) {
      throw WorktreeCleanException(worktreesRoot, buildIssue);
    }
    final root = Directory(worktreesRoot);
    if (!root.existsSync()) {
      throw WorktreeCleanException(worktreesRoot, '没有可清理的合成树');
    }
    final matches = <String>[];
    final errors = <String>[];
    for (final entity in root.listSync()) {
      if (entity is! File) continue;
      final name = basename(entity.path);
      if (!name.endsWith(_stateSuffix) || !name.startsWith(input)) continue;
      try {
        matches.add(_readState(entity).modsetHash);
      } on WorktreeStateException catch (error) {
        errors.add(error.message);
      }
    }
    if (matches.length == 1) return matches.single;
    if (matches.isEmpty) {
      if (errors.isNotEmpty) {
        throw WorktreeCleanException(
          worktreesRoot,
          '匹配前缀的状态文件损坏：${errors.join('；')}',
        );
      }
      throw WorktreeCleanException(worktreesRoot, '找不到前缀为 $input 的合成树');
    }
    throw WorktreeCleanException(
      worktreesRoot,
      '前缀 $input 匹配多个合成树：${matches.join(', ')}',
    );
  }

  Git _gitAt(String path) => Git(workingDirectory: path);

  void _requireFullHash(String modsetHash) {
    if (!isSha256Hex(modsetHash)) {
      throw ArgumentError.value(
        modsetHash,
        'modsetHash',
        '必须是完整 64 位小写 SHA-256',
      );
    }
  }
}

String _normalizeAbsolute(String path, String name) {
  final normalized = stripTrailingSlashes(toPosixPath(path));
  final error = absolutePathError(normalized);
  if (error != null) throw ArgumentError.value(path, name, error);
  return normalized;
}

String _validateCommit(String commit) {
  if (!isFullCommitSha(commit)) {
    throw ArgumentError.value(
      commit,
      'upstreamCommit',
      '必须是完整 40 位小写 commit SHA',
    );
  }
  return commit;
}
