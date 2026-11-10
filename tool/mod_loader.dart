import 'dart:io';

import 'src/build_artifacts.dart';
import 'src/build_record.dart';
import 'src/config.dart';
import 'src/copy.dart';
import 'src/git.dart';
import 'src/hash.dart' as content_hash;
import 'src/patch.dart';
import 'src/paths.dart';
import 'src/registry.dart' as registry;
import 'src/worktree.dart';

const String loaderVersion = '1.0.0';
const String loaderOverlayRelative = 'overlay';
const String loaderSeamsPatchRelative = 'patches/tool_mod_seams.patch';
const String loaderSeamsTouch =
    'lib/features/home/controllers/generation_controller.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.first == '--help' || args.first == '-h') {
    _printUsage(args.isEmpty ? stderr : stdout);
    exitCode = args.isEmpty ? 2 : 0;
    return;
  }

  final command = args.first;
  try {
    switch (command) {
      case 'plan':
        _parseOptions(args, const <String>{});
        await _plan();
        return;
      case 'apply':
        _parseOptions(args, const <String>{});
        await _apply();
        return;
      case 'verify':
        _parseOptions(args, const <String>{});
        await _verify();
        return;
      case 'rebase-drill':
        final options = _parseOptions(args, const <String>{'--to'});
        final to = options['--to'];
        if (to == null) {
          throw const UsageException('rebase-drill 必须提供 --to <完整 commit>');
        }
        await _rebaseDrill(to);
        return;
      case 'clean':
        final options = _parseOptions(args, const <String>{'--modset'});
        final modset = options['--modset'];
        if (modset == null) {
          throw const UsageException('clean 必须提供 --modset <hash>，未执行删除');
        }
        await _clean(modset);
        return;
      default:
        throw UsageException('未知命令：$command');
    }
  } on UsageException catch (error) {
    stderr.writeln(error.message);
    _printUsage(stderr);
    exitCode = 2;
  } on ConfigException catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } on BuildRecordException catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } on PatchException catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } on CopyException catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } on registry.ModRegistryException catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } on WorktreeException catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } on GitException catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } on content_hash.HashException catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } on LoaderVerificationException catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } on FileSystemException catch (error) {
    final path = error.path == null ? '' : '：${error.path}';
    stderr.writeln('文件操作失败：${error.message}$path');
    exitCode = 1;
  } on FormatException catch (error) {
    stderr.writeln('数据格式错误：${error.message}');
    exitCode = 1;
  } on ArgumentError catch (error) {
    stderr.writeln('参数错误：${error.message}');
    exitCode = 2;
  } catch (error) {
    stderr.writeln('Loader 失败：$error');
    exitCode = 1;
  }
}

class UsageException implements Exception {
  const UsageException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LoaderVerificationException implements Exception {
  LoaderVerificationException(this.issues);

  final List<String> issues;

  @override
  String toString() =>
      '合成结果校验失败：\n${issues.map((issue) => '- $issue').join('\n')}';
}

class _LoaderContext {
  _LoaderContext({
    required this.privateRepoRoot,
    required this.set,
    required this.modsetHash,
    required this.manager,
  });

  final String privateRepoRoot;
  final ModSet set;
  final String modsetHash;
  final WorktreeManager manager;

  String get overlayPath => joinPath(privateRepoRoot, loaderOverlayRelative);

  String get seamsPatchPath =>
      joinPath(privateRepoRoot, loaderSeamsPatchRelative);

  String get worktreePath => manager.worktreePathFor(modsetHash);
}

Future<void> _plan() async {
  final context = _loadContext();
  final overlayFiles = _listOverlayFiles(context.overlayPath);
  final inspections = PatchApplier(
    worktree: context.worktreePath,
  ).inspectAll(_patchSpecs(context.set, context.privateRepoRoot));

  stdout.writeln(
    '基线：${context.set.config.upstreamPath} @ '
    '${context.set.config.upstreamCommit}',
  );
  stdout.writeln('modsetHash：${context.modsetHash}');
  stdout.writeln('合成目录：${context.worktreePath}');
  stdout.writeln('Loader overlay：${context.overlayPath} -> 合成树根');
  for (final file in overlayFiles) {
    stdout.writeln('  overlay/$file -> $file');
  }
  stdout.writeln('Loader 接缝补丁：$loaderSeamsPatchRelative');
  stdout.writeln('  touches：$loaderSeamsTouch');
  for (final inspection in inspections) {
    stdout.writeln('  补丁 ${inspection.spec.label}：${inspection.patchPath}');
    stdout.writeln('    路径：${inspection.paths.join('、')}');
    if (inspection.newFiles.isNotEmpty) {
      stdout.writeln('    新增：${inspection.newFiles.join('、')}');
    }
    if (inspection.binary) {
      stdout.writeln('    二进制补丁：是');
    }
  }
  stdout.writeln('Mod 顺序：');
  if (context.set.mods.isEmpty) {
    stdout.writeln('  （空）');
  }
  for (var index = 0; index < context.set.mods.length; index++) {
    final mod = context.set.mods[index];
    stdout.writeln(
      '  ${index + 1}. ${mod.id} ${mod.config.version}（${mod.entry.path}）',
    );
    for (final patch in mod.config.patches) {
      stdout.writeln('     patch：$patch');
    }
    for (final copy in mod.config.copy) {
      final exclude = copy.exclude.isEmpty
          ? ''
          : '（排除：${copy.exclude.join('、')}）';
      stdout.writeln('     copy：${copy.from} -> ${copy.to}$exclude');
    }
  }
  stdout.writeln('注册表：${registry.modRegistryPath}');
  stdout.writeln('构建记录：$buildRecordFileName');
}

Future<void> _apply() async {
  final context = _loadContext();
  final handle = await context.manager.createOrReuse(
    modsetHash: context.modsetHash,
    allowTrackedChanges: true,
    synthesize: (handle) async {
      await _synthesize(
        worktreePath: handle.path,
        set: context.set,
        privateRepoRoot: context.privateRepoRoot,
        upstreamCommit: context.set.config.upstreamCommit,
        modsetHash: context.modsetHash,
      );
    },
  );

  final issues = await _verifySynthesis(
    context: context,
    worktreePath: handle.path,
  );
  if (issues.isNotEmpty) throw LoaderVerificationException(issues);

  stdout.writeln('合成完成（${handle.reused ? '复用' : '新建'}）：${handle.path}');
  stdout.writeln('modsetHash：${context.modsetHash}');
  stdout.writeln('注册表：${joinPath(handle.path, registry.modRegistryPath)}');
  stdout.writeln('构建记录：${joinPath(handle.path, buildRecordFileName)}');
}

Future<void> _verify() async {
  final context = _loadContext();
  final issues = await _verifySynthesis(
    context: context,
    worktreePath: context.worktreePath,
  );
  if (issues.isNotEmpty) throw LoaderVerificationException(issues);
  stdout.writeln('校验通过：${context.worktreePath}');
}

Future<void> _rebaseDrill(String to) async {
  if (!content_hash.isFullCommitSha(to)) {
    throw const UsageException('--to 必须是完整 40 位小写 commit SHA');
  }
  final context = _loadContext();
  final git = Git(workingDirectory: context.set.config.upstreamPath);
  await _validateDrillUpstream(git, context.set.config.upstreamPath, to);

  final drillHash = _computeModsetHash(
    set: context.set,
    privateRepoRoot: context.privateRepoRoot,
    upstreamCommit: to,
  );
  final drillsRoot = joinPath(context.privateRepoRoot, '.build/drills');
  Directory(drillsRoot).createSync(recursive: true);
  final drillPath = joinPath(
    drillsRoot,
    '${content_hash.modsetDirectoryName(drillHash)}-'
    '${DateTime.now().microsecondsSinceEpoch}',
  );

  var created = false;
  try {
    await git.worktreeAddDetached(path: drillPath, commit: to);
    created = true;
    await _synthesize(
      worktreePath: drillPath,
      set: context.set,
      privateRepoRoot: context.privateRepoRoot,
      upstreamCommit: to,
      modsetHash: drillHash,
    );
    final issues = await _verifySynthesisContent(
      worktreePath: drillPath,
      set: context.set,
      privateRepoRoot: context.privateRepoRoot,
      upstreamCommit: to,
      modsetHash: drillHash,
    );
    if (issues.isNotEmpty) throw LoaderVerificationException(issues);
    stdout.writeln('演练通过：$to');
    stdout.writeln('临时 worktree：$drillPath');
  } finally {
    if (created) {
      try {
        await git.worktreeRemove(path: drillPath, force: true);
        stdout.writeln('临时 worktree 已清理');
      } on GitException catch (error) {
        stderr.writeln('临时 worktree 清理失败：$drillPath：${error.message}');
        exitCode = 1;
      }
    } else if (Directory(drillPath).existsSync()) {
      stderr.writeln('临时目录可能残留：$drillPath');
      exitCode = 1;
    }
  }
}

Future<void> _clean(String modset) async {
  if (!content_hash.isSha256Hex(modset) &&
      !RegExp(r'^[0-9a-f]{16}$').hasMatch(modset)) {
    throw const UsageException('--modset 必须是完整 64 位 SHA-256 或 16 位目录前缀');
  }
  final root = stripTrailingSlashes(toPosixPath(Directory.current.path));
  final config = ModLoaderConfig.load(joinPath(root, 'mods.json'));
  final manager = WorktreeManager(
    privateRepoRoot: root,
    upstreamPath: config.upstreamPath,
    upstreamCommit: config.upstreamCommit,
  );
  final result = await manager.clean(modsetHash: modset);
  stdout.writeln('已清理：${result.path}');
  stdout.writeln('modsetHash：${result.modsetHash}');
  stdout.writeln('目录已删除：${result.removedDirectory}');
  stdout.writeln('状态文件已删除：${result.removedState}');
}

_LoaderContext _loadContext() {
  final root = stripTrailingSlashes(toPosixPath(Directory.current.path));
  final set = ModSet.load(root);
  final modsetHash = _computeModsetHash(
    set: set,
    privateRepoRoot: root,
    upstreamCommit: set.config.upstreamCommit,
  );
  final manager = WorktreeManager(
    privateRepoRoot: root,
    upstreamPath: set.config.upstreamPath,
    upstreamCommit: set.config.upstreamCommit,
  );
  return _LoaderContext(
    privateRepoRoot: root,
    set: set,
    modsetHash: modsetHash,
    manager: manager,
  );
}

String _computeModsetHash({
  required ModSet set,
  required String privateRepoRoot,
  required String upstreamCommit,
}) {
  final base = content_hash.computeModsetHash(
    schemaVersion: set.config.schemaVersion,
    upstreamCommit: upstreamCommit,
    loaderVersion: loaderVersion,
    mods: set.computeModTrees(),
  );
  final loaderTree = content_hash.hashFileList(
    _loaderContentHashes(privateRepoRoot),
  );
  return content_hash.sha256Text(
    'kelivo-loader-modset-v1\n$base\n$loaderTree\n',
  );
}

List<content_hash.FileHash> _loaderContentHashes(String privateRepoRoot) {
  final overlayPath = joinPath(privateRepoRoot, loaderOverlayRelative);
  final files = <content_hash.FileHash>[];
  for (final relative in _listOverlayFiles(overlayPath)) {
    final file = File(joinPath(overlayPath, relative));
    files.add(
      content_hash.FileHash(
        path: 'overlay/$relative',
        sha256: content_hash.sha256File(file),
        size: file.lengthSync(),
      ),
    );
  }
  final seams = File(joinPath(privateRepoRoot, loaderSeamsPatchRelative));
  files.add(
    content_hash.FileHash(
      path: loaderSeamsPatchRelative,
      sha256: content_hash.sha256File(seams),
      size: seams.lengthSync(),
    ),
  );
  return files;
}

List<String> _listOverlayFiles(String overlayPath) {
  final type = FileSystemEntity.typeSync(overlayPath, followLinks: false);
  if (type == FileSystemEntityType.link) {
    throw CopyException('Loader overlay 不能是符号链接', path: overlayPath);
  }
  if (type != FileSystemEntityType.directory) {
    throw CopyException('Loader overlay 目录不存在', path: overlayPath);
  }
  final files = <String>[];
  for (final entity in Directory(
    overlayPath,
  ).listSync(recursive: true, followLinks: false)) {
    if (entity is Link) {
      throw CopyException('Loader overlay 包含符号链接', path: entity.path);
    }
    if (entity is Directory) continue;
    if (entity is! File) {
      throw CopyException('Loader overlay 包含不支持的文件类型', path: entity.path);
    }
    final relative = relativeTo(overlayPath, toPosixPath(entity.path));
    if (relative == null || relative.isEmpty) {
      throw CopyException('无法计算 overlay 相对路径', path: entity.path);
    }
    if (isDefaultExcludedPath(relative)) continue;
    files.add(relative);
  }
  files.sort();
  return files;
}

List<PatchSpec> _patchSpecs(ModSet set, String privateRepoRoot) {
  final specs = <PatchSpec>[
    PatchSpec(
      patchFile: joinPath(privateRepoRoot, loaderSeamsPatchRelative),
      touches: const <String>[loaderSeamsTouch],
      label: 'loader-seams',
    ),
  ];
  for (final mod in set.mods) {
    for (final patch in mod.config.patches) {
      specs.add(
        PatchSpec(
          patchFile: joinPath(mod.directory.path, patch),
          touches: mod.config.touches,
          label: mod.id,
        ),
      );
    }
  }
  return specs;
}

List<CopyRequest> _modCopyRequests(ModSet set) => <CopyRequest>[
  for (final mod in set.mods)
    for (final spec in mod.config.copy)
      CopyRequest(
        sourceRoot: mod.directory.path,
        source: spec.from,
        destination: spec.to,
        exclude: spec.exclude,
        label: mod.id,
      ),
];

List<CopyRequest> _allCopyRequests(ModSet set, String privateRepoRoot) =>
    <CopyRequest>[
      CopyRequest(
        sourceRoot: joinPath(privateRepoRoot, loaderOverlayRelative),
        source: '.',
        destination: '.',
        label: 'loader-overlay',
      ),
      ..._modCopyRequests(set),
    ];

List<registry.ModRegistration> _registrations(ModSet set) {
  final registrations = <registry.ModRegistration>[];
  for (final mod in set.mods) {
    final registration = mod.config.registration;
    if (registration == null) continue;
    registrations.add(
      registry.ModRegistration(
        id: mod.id,
        importUri: registration.importUri,
        className: registration.className,
        toolNames: mod.config.toolNames,
      ),
    );
  }
  return registrations;
}

Future<void> _synthesize({
  required String worktreePath,
  required ModSet set,
  required String privateRepoRoot,
  required String upstreamCommit,
  required String modsetHash,
}) async {
  final copyPlanner = CopyPlanner(worktree: worktreePath);
  final overlayPlan = copyPlanner.applyAll(<CopyRequest>[
    CopyRequest(
      sourceRoot: joinPath(privateRepoRoot, loaderOverlayRelative),
      source: '.',
      destination: '.',
      label: 'loader-overlay',
    ),
  ]);

  final patchApplier = PatchApplier(worktree: worktreePath);
  final inspections = await patchApplier.applyAll(
    _patchSpecs(set, privateRepoRoot),
  );

  final modCopyRequests = _modCopyRequests(set);
  final modCopyPlan = modCopyRequests.isEmpty
      ? null
      : copyPlanner.applyAll(modCopyRequests);

  final registryContent = _writeRegistry(worktreePath, set);
  final copiedFiles = <CopyPlannedFile>[
    ...overlayPlan.files,
    ...?modCopyPlan?.files,
  ];
  final record = await _createBuildRecord(
    worktreePath: worktreePath,
    set: set,
    upstreamCommit: upstreamCommit,
    modsetHash: modsetHash,
    inspections: inspections,
    copiedFiles: copiedFiles,
    registryContent: registryContent,
  );
  record.write(File(joinPath(worktreePath, buildRecordFileName)));
}

String _writeRegistry(String worktreePath, ModSet set) {
  final content = registry.renderModRegistry(_registrations(set));
  final file = File(joinPath(worktreePath, registry.modRegistryPath));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content, flush: true);
  return content;
}

Future<BuildRecord> _createBuildRecord({
  required String worktreePath,
  required ModSet set,
  required String upstreamCommit,
  required String modsetHash,
  required List<PatchInspection> inspections,
  required List<CopyPlannedFile> copiedFiles,
  required String registryContent,
}) async {
  final trees = set.computeModTrees();
  final mods = <BuildModRecord>[
    for (var index = 0; index < set.mods.length; index++)
      BuildModRecord(
        id: set.mods[index].id,
        version: set.mods[index].config.version,
        path: set.mods[index].entry.path,
        treeHash: trees[index].treeHash,
      ),
  ];

  final patchedFiles = <String, String?>{};
  for (final inspection in inspections) {
    for (final path in inspection.paths) {
      final file = File(joinPath(worktreePath, path));
      patchedFiles[path] = file.existsSync()
          ? content_hash.sha256File(file)
          : null;
    }
  }

  final copied = <String, String>{};
  for (final file in copiedFiles) {
    if (copied.containsKey(file.destinationRelative)) {
      throw BuildRecordException('重复的复制目标：${file.destinationRelative}');
    }
    copied[file.destinationRelative] = content_hash.sha256File(
      File(file.destinationPath),
    );
  }

  final indexDiffHash = content_hash.sha256Text(
    await Git(workingDirectory: worktreePath).cachedDiff(),
  );

  return BuildRecord(
    schemaVersion: buildRecordSchemaVersion,
    loaderVersion: loaderVersion,
    modsetHash: modsetHash,
    upstreamPath: set.config.upstreamPath,
    upstreamCommit: upstreamCommit,
    indexDiffHash: indexDiffHash,
    mods: mods,
    patchedFiles: patchedFiles,
    copiedFiles: copied,
    generatedFiles: <String, String>{
      registry.modRegistryPath: content_hash.sha256Text(registryContent),
    },
  );
}

Future<List<String>> _verifySynthesis({
  required _LoaderContext context,
  required String worktreePath,
}) async {
  final issues = <String>[];
  final verification = await context.manager.verify(
    modsetHash: context.modsetHash,
    allowTrackedChanges: true,
  );
  issues.addAll(verification.issues);
  issues.addAll(
    await _verifySynthesisContent(
      worktreePath: worktreePath,
      set: context.set,
      privateRepoRoot: context.privateRepoRoot,
      upstreamCommit: context.set.config.upstreamCommit,
      modsetHash: context.modsetHash,
    ),
  );
  return issues;
}

Future<List<String>> _verifySynthesisContent({
  required String worktreePath,
  required ModSet set,
  required String privateRepoRoot,
  required String upstreamCommit,
  required String modsetHash,
}) async {
  final issues = <String>[];
  final worktreeType = FileSystemEntity.typeSync(
    worktreePath,
    followLinks: false,
  );
  if (worktreeType != FileSystemEntityType.directory) {
    issues.add('合成目录不存在或不是目录：$worktreePath');
    return issues;
  }

  final git = Git(workingDirectory: worktreePath);
  try {
    final head = await git.headCommit();
    if (head != upstreamCommit) {
      issues.add('worktree HEAD 为 $head，与基线 $upstreamCommit 不一致');
    }
  } on GitException catch (error) {
    issues.add('无法读取 worktree HEAD：${error.message}');
  }

  final recordFile = File(joinPath(worktreePath, buildRecordFileName));
  final recordType = FileSystemEntity.typeSync(
    recordFile.path,
    followLinks: false,
  );
  if (recordType != FileSystemEntityType.file) {
    issues.add('缺少有效的 $buildRecordFileName');
    return issues;
  }
  final BuildRecord record;
  try {
    record = BuildRecord.read(recordFile);
  } on BuildRecordException catch (error) {
    issues.add('$buildRecordFileName 无效：${error.message}');
    return issues;
  } on FileSystemException catch (error) {
    issues.add('无法读取 $buildRecordFileName：${error.message}');
    return issues;
  }

  if (record.loaderVersion != loaderVersion) {
    issues.add(
      '构建记录 loaderVersion 为 ${record.loaderVersion}，'
      '当前为 $loaderVersion',
    );
  }
  if (record.modsetHash != modsetHash) {
    issues.add('构建记录 modsetHash 与当前配置不一致');
  }
  if (!samePath(record.upstreamPath, set.config.upstreamPath)) {
    issues.add('构建记录 upstreamPath 与当前配置不一致');
  }
  if (record.upstreamCommit != upstreamCommit) {
    issues.add('构建记录 upstreamCommit 与目标基线不一致');
  }

  final trees = set.computeModTrees();
  if (record.mods.length != set.mods.length) {
    issues.add('构建记录 Mod 数量与当前配置不一致');
  } else {
    for (var index = 0; index < set.mods.length; index++) {
      final mod = set.mods[index];
      final recorded = record.mods[index];
      if (recorded.id != mod.id ||
          recorded.version != mod.config.version ||
          recorded.path != mod.entry.path ||
          recorded.treeHash != trees[index].treeHash) {
        issues.add('构建记录 Mod 顺序或内容不匹配：${mod.id}');
      }
    }
  }

  try {
    final diffHash = content_hash.sha256Text(await git.cachedDiff());
    if (record.indexDiffHash != diffHash) {
      issues.add('暂存区补丁内容哈希不一致');
    }
  } on GitException catch (error) {
    issues.add('无法读取暂存区差异：${error.message}');
  }

  try {
    final changes = await git.trackedChanges();
    for (final change in changes) {
      if (change.status.length > 1 &&
          change.status[1] != ' ' &&
          !isAllowedBuildArtifact(change.path)) {
        issues.add('存在未暂存的已跟踪文件改动：${change.path}');
      }
    }
  } on GitException catch (error) {
    issues.add('无法读取 worktree 状态：${error.message}');
  }

  final inspections = <PatchInspection>[];
  try {
    inspections.addAll(
      PatchApplier(
        worktree: worktreePath,
      ).inspectAll(_patchSpecs(set, privateRepoRoot)),
    );
  } on PatchException catch (error) {
    issues.add('无法检查补丁：$error');
  }
  final expectedPatched = <String>{
    for (final inspection in inspections) ...inspection.paths,
  };
  if (!_sameStringSet(expectedPatched, record.patchedFiles.keys.toSet())) {
    issues.add('构建记录的补丁路径与当前配置不一致');
  }
  for (final path in expectedPatched) {
    _checkFileHash(
      worktreePath,
      path,
      record.patchedFiles[path],
      issues,
      '补丁文件',
    );
  }

  CopyPlan? expectedCopyPlan;
  try {
    final copyPlanner = CopyPlanner(worktree: worktreePath);
    expectedCopyPlan = copyPlanner.planAll(
      _allCopyRequests(set, privateRepoRoot),
      allowExistingTargets: true,
    );
    copyPlanner.verify(expectedCopyPlan);
  } on CopyException catch (error) {
    issues.add('无法校验复制结果：$error');
  }
  if (expectedCopyPlan != null) {
    final expectedCopied = expectedCopyPlan.files
        .map((file) => file.destinationRelative)
        .toSet();
    if (!_sameStringSet(expectedCopied, record.copiedFiles.keys.toSet())) {
      issues.add('构建记录的复制文件与当前配置不一致');
    }
    for (final path in expectedCopied) {
      _checkFileHash(
        worktreePath,
        path,
        record.copiedFiles[path],
        issues,
        '复制文件',
      );
    }
  }

  String? expectedRegistry;
  try {
    expectedRegistry = registry.renderModRegistry(_registrations(set));
  } on registry.ModRegistryException catch (error) {
    issues.add('注册表配置无效：$error');
  }
  if (expectedRegistry != null) {
    final registryFile = File(joinPath(worktreePath, registry.modRegistryPath));
    final registryType = FileSystemEntity.typeSync(
      registryFile.path,
      followLinks: false,
    );
    if (registryType != FileSystemEntityType.file) {
      issues.add('缺少注册表：${registry.modRegistryPath}');
    } else {
      final actualRegistry = registryFile.readAsStringSync();
      if (actualRegistry != expectedRegistry) {
        issues.add('注册表内容与当前配置不一致');
      }
      final expectedHash = content_hash.sha256Text(expectedRegistry);
      if (record.generatedFiles[registry.modRegistryPath] != expectedHash) {
        issues.add('构建记录的注册表哈希不一致');
      }
      if (record.generatedFiles.length != 1 ||
          !record.generatedFiles.containsKey(registry.modRegistryPath)) {
        issues.add('构建记录的生成文件列表不匹配');
      }
    }
  }

  return issues;
}

void _checkFileHash(
  String worktreePath,
  String relative,
  String? expectedHash,
  List<String> issues,
  String kind,
) {
  final file = File(joinPath(worktreePath, relative));
  final type = FileSystemEntity.typeSync(file.path, followLinks: false);
  if (expectedHash == null) {
    if (type != FileSystemEntityType.notFound) {
      issues.add('$kind 应不存在：$relative');
    }
    return;
  }
  if (type != FileSystemEntityType.file) {
    issues.add('$kind 缺失或不是普通文件：$relative');
    return;
  }
  final actual = content_hash.sha256File(file);
  if (actual != expectedHash) {
    issues.add('$kind 内容哈希不一致：$relative');
  }
}

bool _sameStringSet(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

Future<void> _validateDrillUpstream(
  Git git,
  String upstreamPath,
  String commit,
) async {
  try {
    if (!await git.isInsideWorkTree()) {
      throw UpstreamException(upstreamPath, '上游路径不是 Git 工作树');
    }
    final top = await git.topLevel();
    if (!samePath(top, upstreamPath)) {
      throw UpstreamException(upstreamPath, '上游路径不是 Git 仓库根目录（实际根目录：$top）');
    }
    final type = await git.objectType(commit);
    if (type != 'commit') {
      throw UpstreamException(
        upstreamPath,
        '目标 commit $commit 不存在或不是 commit（实际类型：${type ?? '不存在'}）',
      );
    }
    final changes = await git.trackedChanges();
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

Map<String, String> _parseOptions(List<String> args, Set<String> allowed) {
  final options = <String, String>{};
  for (var index = 1; index < args.length; index++) {
    final arg = args[index];
    if (!arg.startsWith('--')) {
      throw UsageException('未知参数：$arg');
    }
    final equals = arg.indexOf('=');
    final name = equals >= 0 ? arg.substring(0, equals) : arg;
    if (!allowed.contains(name)) {
      throw UsageException('未知选项：$name');
    }
    final String value;
    if (equals >= 0) {
      value = arg.substring(equals + 1);
    } else {
      if (index + 1 >= args.length) {
        throw UsageException('$name 缺少值');
      }
      value = args[++index];
    }
    if (options.containsKey(name)) {
      throw UsageException('重复的选项：$name');
    }
    options[name] = value;
  }
  return options;
}

void _printUsage(IOSink sink) {
  sink
    ..writeln('用法：')
    ..writeln('  dart tool/mod_loader.dart plan')
    ..writeln('  dart tool/mod_loader.dart apply')
    ..writeln('  dart tool/mod_loader.dart verify')
    ..writeln('  dart tool/mod_loader.dart rebase-drill --to <完整 commit>')
    ..writeln('  dart tool/mod_loader.dart clean --modset <完整哈希或 16 位前缀>');
}
