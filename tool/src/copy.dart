/// 新增文件复制：只新增、不覆盖，并拒绝越界、符号链接和大小写冲突。
///
/// 只依赖 Dart SDK 与 Loader 共享的路径规则。复制前先完成整批计划与
/// 目标预检，再逐个以独占方式创建并回读校验；任一失败会清理本次新建的
/// 文件和目录后抛出 [CopyException]。
library;

import 'dart:io';

import 'paths.dart';

/// 复制计划或执行失败。
class CopyException implements Exception {
  const CopyException(this.message, {this.label, this.path});

  /// 面向开发者的中文错误说明。
  final String message;

  /// 复制项所属的 Mod id 或其他标签。
  final String? label;

  /// 与失败相关的仓库相对路径或本机路径。
  final String? path;

  @override
  String toString() {
    final buffer = StringBuffer('复制失败');
    if (label != null && label!.isNotEmpty) {
      buffer.write('[$label]');
    }
    buffer.write('：$message');
    if (path != null && path!.isNotEmpty) {
      buffer.write('\n  路径：$path');
    }
    return buffer.toString();
  }
}

/// 一个复制项：把 [sourceRoot] 下的 [source] 复制到 worktree 的 [destination]。
class CopyRequest {
  const CopyRequest({
    required this.sourceRoot,
    required this.source,
    required this.destination,
    this.exclude = const <String>[],
    this.label = '',
  });

  /// 源根目录的本机绝对路径，例如 `mods/<id>/overlay`。
  final String sourceRoot;

  /// 相对 [sourceRoot] 的源路径；`.` 或空串表示源根目录本身。
  final String source;

  /// 相对 worktree 根的目标路径；`.` 或空串表示 worktree 根目录。
  final String destination;

  /// 额外的排除项，相对 [sourceRoot]，匹配自身及其子路径。
  final List<String> exclude;

  /// 用于错误信息的标签，例如 Mod id。
  final String label;
}

/// 计划复制的单个文件。
class CopyPlannedFile {
  const CopyPlannedFile({
    required this.label,
    required this.sourcePath,
    required this.sourceRelative,
    required this.destinationPath,
    required this.destinationRelative,
    required this.size,
  });

  final String label;

  /// 源文件的本机绝对路径。
  final String sourcePath;

  /// 相对 [CopyRequest.sourceRoot] 的源路径。
  final String sourceRelative;

  /// 目标文件的本机绝对路径。
  final String destinationPath;

  /// 相对 worktree 根的目标路径，始终使用 `/`。
  final String destinationRelative;

  /// 计划时的源文件字节数。
  final int size;
}

/// 被排除而未复制的源路径。
class CopySkipped {
  const CopySkipped({required this.path, required this.reason});

  /// 相对 [CopyRequest.sourceRoot] 的路径。
  final String path;

  /// 排除原因，便于 `plan` 输出。
  final String reason;
}

/// 一次复制计划；[CopyPlanner.applyAll] 成功返回时表示已按此计划写入。
class CopyPlan {
  const CopyPlan({
    required this.specs,
    required this.files,
    required this.directories,
    required this.skipped,
  });

  final List<CopyRequest> specs;
  final List<CopyPlannedFile> files;

  /// 需要在 worktree 中新建的目录，按父目录在前的顺序排列。
  final List<String> directories;

  final List<CopySkipped> skipped;
}

/// 复制计划、执行与校验入口。
class CopyPlanner {
  CopyPlanner({required String worktree}) : worktree = _absoluteUnix(worktree) {
    if (worktree.trim().isEmpty) {
      throw const CopyException('worktree 路径为空');
    }
  }

  /// 合成 worktree 的本机绝对路径，内部统一使用 `/`。
  final String worktree;

  /// 只生成计划，不写文件。
  CopyPlan plan(CopyRequest spec, {bool allowExistingTargets = false}) =>
      planAll(<CopyRequest>[spec], allowExistingTargets: allowExistingTargets);

  /// 合并多个复制项生成计划，并在返回前完成全部目标预检。
  CopyPlan planAll(
    List<CopyRequest> specs, {
    bool allowExistingTargets = false,
  }) {
    _requireWorktree();

    final context = _PlanContext();
    for (final spec in specs) {
      _planSpec(spec, context);
    }
    for (final file in context.files) {
      _checkDestination(file, allowExistingFile: allowExistingTargets);
    }

    return CopyPlan(
      specs: List<CopyRequest>.unmodifiable(specs),
      files: List<CopyPlannedFile>.unmodifiable(context.files),
      directories: List<String>.unmodifiable(context.directories),
      skipped: List<CopySkipped>.unmodifiable(context.skipped),
    );
  }

  /// 生成计划并执行复制。
  CopyPlan apply(CopyRequest spec) => applyAll(<CopyRequest>[spec]);

  /// 生成计划、写入文件并立即回读校验。
  CopyPlan applyAll(List<CopyRequest> specs) {
    final plan = planAll(specs);
    final createdFiles = <String>[];
    final createdDirectories = <String>[];
    try {
      for (final relative in plan.directories) {
        final path = '$worktree/$relative';
        if (Directory(path).existsSync()) {
          continue;
        }
        Directory(path).createSync(recursive: true);
        createdDirectories.add(path);
      }
      for (final file in plan.files) {
        _writeFile(file, createdFiles);
      }
    } catch (_) {
      _cleanup(createdFiles, createdDirectories);
      rethrow;
    }
    return plan;
  }

  /// 校验计划中的目标文件仍存在且与当前源文件逐字节一致。
  void verify(CopyPlan plan) {
    for (final file in plan.files) {
      final type = FileSystemEntity.typeSync(
        file.destinationPath,
        followLinks: false,
      );
      if (type != FileSystemEntityType.file) {
        throw CopyException(
          '目标文件缺失或不是普通文件',
          label: file.label,
          path: file.destinationRelative,
        );
      }
      final sourceBytes = File(file.sourcePath).readAsBytesSync();
      final targetBytes = File(file.destinationPath).readAsBytesSync();
      if (!_bytesEqual(sourceBytes, targetBytes)) {
        throw CopyException(
          '目标文件内容与复制源不一致',
          label: file.label,
          path: file.destinationRelative,
        );
      }
    }
  }

  void _requireWorktree() {
    final type = FileSystemEntity.typeSync(worktree, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw CopyException('worktree 目录不存在', path: worktree);
    }
    if (type == FileSystemEntityType.link) {
      throw CopyException('worktree 根目录不能是符号链接', path: worktree);
    }
    if (type != FileSystemEntityType.directory) {
      throw CopyException('worktree 路径不是目录', path: worktree);
    }
  }

  void _planSpec(CopyRequest spec, _PlanContext context) {
    final sourceRoot = _absoluteUnix(spec.sourceRoot);
    if (sourceRoot.isEmpty) {
      throw CopyException('复制源根目录为空', label: spec.label);
    }
    final rootType = FileSystemEntity.typeSync(sourceRoot, followLinks: false);
    if (rootType == FileSystemEntityType.link) {
      throw CopyException('复制源根目录不能是符号链接', label: spec.label, path: sourceRoot);
    }
    if (rootType != FileSystemEntityType.directory) {
      throw CopyException(
        '复制源根目录不存在或不是目录',
        label: spec.label,
        path: sourceRoot,
      );
    }

    final sourceRelative = _normalizeSourceRelative(spec.source, spec);
    final destinationRelative = _normalizeDestination(spec.destination, spec);
    final excludes = <String>[
      for (final raw in spec.exclude) _normalizeExclude(raw, spec),
    ];
    final sourcePath = sourceRelative.isEmpty
        ? sourceRoot
        : '$sourceRoot/$sourceRelative';
    final sourceType = FileSystemEntity.typeSync(
      sourcePath,
      followLinks: false,
    );
    if (sourceType == FileSystemEntityType.link) {
      throw CopyException(
        '复制源不能是符号链接',
        label: spec.label,
        path: sourceRelative,
      );
    }
    if (sourceType == FileSystemEntityType.notFound) {
      throw CopyException('复制源不存在', label: spec.label, path: sourceRelative);
    }
    if (sourceType != FileSystemEntityType.file &&
        sourceType != FileSystemEntityType.directory) {
      throw CopyException('复制源类型不受支持', label: spec.label, path: sourceRelative);
    }

    final before = context.files.length;
    if (sourceType == FileSystemEntityType.file) {
      _addFile(context, spec, sourcePath, sourceRelative, destinationRelative);
    } else {
      _walk(
        context,
        spec,
        sourcePath,
        sourceRelative,
        destinationRelative,
        excludes,
      );
    }
    if (context.files.length == before) {
      throw CopyException(
        '复制源没有可复制的文件（可能全部被排除）',
        label: spec.label,
        path: sourceRelative.isEmpty ? spec.sourceRoot : sourceRelative,
      );
    }
  }

  void _walk(
    _PlanContext context,
    CopyRequest spec,
    String directoryPath,
    String directoryRelative,
    String destinationRelative,
    List<String> excludes,
  ) {
    final entries = Directory(directoryPath).listSync(followLinks: false)
      ..sort(
        (a, b) => _basename(_unix(a.path)).compareTo(_basename(_unix(b.path))),
      );
    for (final entity in entries) {
      final name = _basename(_unix(entity.path));
      final childRelative = directoryRelative.isEmpty
          ? name
          : '$directoryRelative/$name';
      final childDestination = destinationRelative.isEmpty
          ? name
          : '$destinationRelative/$name';
      final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw CopyException(
          '复制源包含符号链接',
          label: spec.label,
          path: childRelative,
        );
      }
      if (type == FileSystemEntityType.directory) {
        final reason = _exclusionReason(childRelative, excludes);
        if (reason != null) {
          context.skipped.add(CopySkipped(path: childRelative, reason: reason));
          continue;
        }
        _rejectHighRiskSecret(childRelative, spec);
        _walk(
          context,
          spec,
          entity.path,
          childRelative,
          childDestination,
          excludes,
        );
        continue;
      }
      if (type == FileSystemEntityType.file) {
        final reason = _exclusionReason(childRelative, excludes);
        if (reason != null) {
          context.skipped.add(CopySkipped(path: childRelative, reason: reason));
          continue;
        }
        _rejectHighRiskSecret(childRelative, spec);
        _addFile(context, spec, entity.path, childRelative, childDestination);
        continue;
      }
      throw CopyException(
        '复制源包含不支持的文件类型',
        label: spec.label,
        path: childRelative,
      );
    }
  }

  String? _exclusionReason(String relative, List<String> excludes) {
    if (isDefaultExcludedPath(relative)) {
      return '默认排除路径';
    }
    if (_matchesExclude(relative, excludes)) {
      return '排除项';
    }
    return null;
  }

  void _rejectHighRiskSecret(String relative, CopyRequest spec) {
    if (!_isHighRiskSecretPath(relative)) {
      return;
    }
    throw CopyException(
      '复制源包含 SSH 私钥或签名秘密文件，拒绝合成',
      label: spec.label,
      path: relative,
    );
  }

  void _addFile(
    _PlanContext context,
    CopyRequest spec,
    String sourcePath,
    String sourceRelative,
    String destinationRelative,
  ) {
    final destination = _normalizeDestination(destinationRelative, spec);
    if (destination.isEmpty) {
      throw CopyException(
        '文件复制目标不能是 worktree 根目录',
        label: spec.label,
        path: sourceRelative,
      );
    }
    final folded = destination.toLowerCase();
    final existing = context.destinations[folded];
    if (existing != null) {
      throw CopyException(
        existing == destination ? '多个复制源指向同一目标' : '目标路径大小写冲突',
        label: spec.label,
        path: destination,
      );
    }
    context.destinations[folded] = destination;
    _registerDirectory(context, spec, _dirname(destination));
    context.files.add(
      CopyPlannedFile(
        label: spec.label,
        sourcePath: sourcePath,
        sourceRelative: sourceRelative,
        destinationPath: '$worktree/$destination',
        destinationRelative: destination,
        size: File(sourcePath).lengthSync(),
      ),
    );
  }

  void _registerDirectory(
    _PlanContext context,
    CopyRequest spec,
    String relative,
  ) {
    if (relative.isEmpty) {
      return;
    }
    final folded = relative.toLowerCase();
    final planned = context.plannedDirectories[folded];
    if (planned != null) {
      if (planned != relative) {
        throw CopyException('目标目录大小写冲突', label: spec.label, path: relative);
      }
      return;
    }
    _registerDirectory(context, spec, _dirname(relative));
    context.plannedDirectories[folded] = relative;
    if (!Directory('$worktree/$relative').existsSync()) {
      context.directories.add(relative);
    }
  }

  void _checkDestination(
    CopyPlannedFile file, {
    required bool allowExistingFile,
  }) {
    final segments = file.destinationRelative.split('/');
    var current = worktree;
    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      if (!Directory(current).existsSync()) {
        return;
      }
      final entries = Directory(current).listSync(followLinks: false);
      String? exact;
      String? folded;
      for (final entity in entries) {
        final name = _basename(_unix(entity.path));
        if (name == segment) {
          exact = entity.path;
        } else if (folded == null &&
            name.toLowerCase() == segment.toLowerCase()) {
          folded = entity.path;
        }
      }
      if (exact != null) {
        final type = FileSystemEntity.typeSync(exact, followLinks: false);
        if (type == FileSystemEntityType.link) {
          throw CopyException(
            '目标路径经过符号链接',
            label: file.label,
            path: file.destinationRelative,
          );
        }
        if (index == segments.length - 1) {
          if (allowExistingFile) {
            current = exact;
            continue;
          }
          throw CopyException(
            '目标已存在，拒绝覆盖',
            label: file.label,
            path: file.destinationRelative,
          );
        }
        if (type != FileSystemEntityType.directory) {
          throw CopyException(
            '目标路径的上级不是目录',
            label: file.label,
            path: file.destinationRelative,
          );
        }
        current = exact;
        continue;
      }
      if (folded != null) {
        throw CopyException(
          '目标路径与现有文件大小写冲突',
          label: file.label,
          path:
              '${file.destinationRelative}（现有：${_relativeToWorktree(folded)}）',
        );
      }
      return;
    }
  }

  void _writeFile(CopyPlannedFile file, List<String> createdFiles) {
    final bytes = File(file.sourcePath).readAsBytesSync();
    if (bytes.length != file.size) {
      throw CopyException(
        '复制前源文件大小发生变化',
        label: file.label,
        path: file.sourceRelative,
      );
    }
    final target = File(file.destinationPath);
    try {
      target.createSync(exclusive: true);
      createdFiles.add(file.destinationPath);
      final handle = target.openSync(mode: FileMode.writeOnly);
      try {
        handle.writeFromSync(bytes);
        handle.flushSync();
      } finally {
        handle.closeSync();
      }
    } on FileSystemException catch (error) {
      throw CopyException(
        '写入目标文件失败：${error.message}',
        label: file.label,
        path: file.destinationRelative,
      );
    }
    final copied = target.readAsBytesSync();
    if (!_bytesEqual(bytes, copied)) {
      throw CopyException(
        '复制后内容校验失败',
        label: file.label,
        path: file.destinationRelative,
      );
    }
    final type = FileSystemEntity.typeSync(
      file.destinationPath,
      followLinks: false,
    );
    if (type != FileSystemEntityType.file) {
      throw CopyException(
        '复制后目标不是普通文件',
        label: file.label,
        path: file.destinationRelative,
      );
    }
  }

  String _relativeToWorktree(String path) {
    final unix = _unix(path);
    return unix.startsWith('$worktree/')
        ? unix.substring(worktree.length + 1)
        : unix;
  }
}

class _PlanContext {
  final List<CopyPlannedFile> files = <CopyPlannedFile>[];
  final List<String> directories = <String>[];
  final List<CopySkipped> skipped = <CopySkipped>[];
  final Map<String, String> destinations = <String, String>{};
  final Map<String, String> plannedDirectories = <String, String>{};
}

void _cleanup(List<String> files, List<String> directories) {
  for (final path in files.reversed) {
    try {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } on FileSystemException {
      // 清理失败不掩盖原始错误。
    }
  }
  for (final path in directories.reversed) {
    try {
      final directory = Directory(path);
      if (directory.existsSync()) {
        directory.deleteSync();
      }
    } on FileSystemException {
      // 目录可能包含其他文件，保留即可。
    }
  }
}

String _absoluteUnix(String path) {
  return Directory(path).absolute.path.replaceAll('\\', '/');
}

String _unix(String path) => path.replaceAll('\\', '/');

String _basename(String path) => path.substring(path.lastIndexOf('/') + 1);

String _dirname(String path) {
  final index = path.lastIndexOf('/');
  return index < 0 ? '' : path.substring(0, index);
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

const Set<String> _reservedNames = <String>{
  'con',
  'prn',
  'aux',
  'nul',
  'com1',
  'com2',
  'com3',
  'com4',
  'com5',
  'com6',
  'com7',
  'com8',
  'com9',
  'lpt1',
  'lpt2',
  'lpt3',
  'lpt4',
  'lpt5',
  'lpt6',
  'lpt7',
  'lpt8',
  'lpt9',
};

bool _isReservedName(String segment) {
  final lower = segment.toLowerCase();
  final dot = lower.indexOf('.');
  return _reservedNames.contains(dot >= 0 ? lower.substring(0, dot) : lower);
}

const Set<String> _secretKeyNames = <String>{
  'id_rsa',
  'id_ed25519',
  'id_ecdsa',
  'id_dsa',
};

const Set<String> _secretKeyExtensions = <String>{
  '.p8',
  '.mobileprovision',
  '.provisionprofile',
};

bool _isHighRiskSecretPath(String relative) {
  final segments = relative.split('/');
  if (segments.contains('.ssh') || segments.first == 'secrets') {
    return true;
  }
  final name = segments.last.toLowerCase();
  if (_secretKeyNames.contains(name)) {
    return true;
  }
  final dot = name.lastIndexOf('.');
  return dot >= 0 && _secretKeyExtensions.contains(name.substring(dot));
}

String _normalizeSourceRelative(String raw, CopyRequest spec) {
  var path = raw.trim();
  if (path.isEmpty || path == '.') {
    return '';
  }
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (path.isEmpty) {
    return '';
  }
  _requireRelative(path, spec, '复制源');
  for (final segment in path.split('/')) {
    _validateSegment(segment, spec, raw);
  }
  if (isDefaultExcludedPath(path)) {
    throw CopyException('复制源位于默认排除路径', label: spec.label, path: raw);
  }
  if (_isHighRiskSecretPath(path)) {
    throw CopyException(
      '复制源包含 SSH 私钥或签名秘密文件，拒绝合成',
      label: spec.label,
      path: raw,
    );
  }
  return path;
}

String _normalizeDestination(String raw, CopyRequest spec) {
  var path = raw.trim();
  if (path.isEmpty || path == '.') {
    return '';
  }
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (path.isEmpty) {
    return '';
  }
  _requireRelative(path, spec, '复制目标');
  for (final segment in path.split('/')) {
    _validateSegment(segment, spec, raw);
  }
  if (isDefaultExcludedPath(path)) {
    throw CopyException('复制目标位于默认排除路径', label: spec.label, path: raw);
  }
  if (_isHighRiskSecretPath(path)) {
    throw CopyException(
      '复制目标包含 SSH 私钥或签名秘密文件，拒绝合成',
      label: spec.label,
      path: raw,
    );
  }
  return path;
}

String _normalizeExclude(String raw, CopyRequest spec) {
  var path = raw.trim();
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (path.isEmpty) {
    throw CopyException('排除项为空', label: spec.label);
  }
  _requireRelative(path, spec, '排除项');
  for (final segment in path.split('/')) {
    if (segment.isEmpty ||
        segment == '.' ||
        segment == '..' ||
        segment.toLowerCase() == '.git') {
      throw CopyException('排除项路径非法', label: spec.label, path: raw);
    }
  }
  return path;
}

void _requireRelative(String path, CopyRequest spec, String what) {
  if (path.contains('\\')) {
    throw CopyException('$what路径必须使用 /', label: spec.label, path: path);
  }
  if (path.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(path)) {
    throw CopyException('$what必须是相对路径', label: spec.label, path: path);
  }
  if (path.contains(':')) {
    throw CopyException('$what路径包含冒号', label: spec.label, path: path);
  }
}

void _validateSegment(String segment, CopyRequest spec, String raw) {
  if (segment.isEmpty) {
    throw CopyException('路径包含空路径段', label: spec.label, path: raw);
  }
  if (segment == '.' || segment == '..') {
    throw CopyException('路径包含路径穿越', label: spec.label, path: raw);
  }
  if (segment.toLowerCase() == '.git') {
    throw CopyException('路径不能指向 .git', label: spec.label, path: raw);
  }
  if (segment.codeUnits.any((unit) => unit < 0x20)) {
    throw CopyException('路径包含控制字符', label: spec.label, path: raw);
  }
  if (segment.endsWith('.') || segment.endsWith(' ')) {
    throw CopyException('Windows 不允许路径段以点或空格结尾', label: spec.label, path: raw);
  }
  if (_isReservedName(segment)) {
    throw CopyException('Windows 保留文件名：$segment', label: spec.label, path: raw);
  }
}

bool _matchesExclude(String relative, List<String> excludes) {
  return excludes.any(
    (entry) => relative == entry || relative.startsWith('$entry/'),
  );
}
