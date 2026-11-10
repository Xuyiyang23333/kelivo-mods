import 'dart:convert';
import 'dart:io';

import 'hash.dart' as hash;
import 'paths.dart';

const int supportedSchemaVersion = 1;

final RegExp _modIdPattern = RegExp(r'^[a-z][a-z0-9_]*$');
final RegExp _toolNamePattern = RegExp(r'^[a-z][a-z0-9_]*$');
final RegExp _versionPattern = RegExp(r'^[0-9A-Za-z][0-9A-Za-z.+-]*$');
final RegExp _classNamePattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
final RegExp _packageNamePattern = RegExp(
  r'^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$',
);

class ConfigException implements Exception {
  const ConfigException({
    required this.source,
    required this.path,
    required this.code,
    required this.message,
  });

  final String source;
  final String path;
  final String code;
  final String message;

  @override
  String toString() => '$source: $path [$code] $message';
}

class ModLoaderConfig {
  const ModLoaderConfig._({
    required this.source,
    required this.schemaVersion,
    required this.upstreamPath,
    required this.upstreamCommit,
    required this.mods,
  });

  final String source;
  final int schemaVersion;
  final String upstreamPath;
  final String upstreamCommit;
  final List<ModEntry> mods;

  List<ModEntry> get enabledMods =>
      List<ModEntry>.unmodifiable(mods.where((mod) => mod.enabled));

  static ModLoaderConfig load(String path) {
    final source = toPosixPath(path);
    final file = File(source);
    if (!file.existsSync()) {
      throw ConfigException(
        source: source,
        path: r'$',
        code: 'missingFile',
        message: '找不到配置文件',
      );
    }
    return parse(file.readAsStringSync(), source: source);
  }

  static ModLoaderConfig parse(String jsonText, {String source = 'mods.json'}) {
    final reader = _Reader(source);
    final root = reader.asObject(reader.decode(jsonText), r'$');
    reader.checkKeys(
      root,
      r'$',
      allowed: const {'schemaVersion', 'upstream', 'mods'},
      required: const {'schemaVersion', 'upstream', 'mods'},
    );

    final schemaVersion = reader.asInt(
      root['schemaVersion'],
      r'$.schemaVersion',
    );
    if (schemaVersion != supportedSchemaVersion) {
      reader.error(
        r'$.schemaVersion',
        'unsupportedSchema',
        '仅支持 schemaVersion $supportedSchemaVersion，实际为 $schemaVersion',
      );
    }

    final upstream = reader.asObject(root['upstream'], r'$.upstream');
    reader.checkKeys(
      upstream,
      r'$.upstream',
      allowed: const {'path', 'commit'},
      required: const {'path', 'commit'},
    );
    final upstreamPathRaw = reader.asString(
      upstream['path'],
      r'$.upstream.path',
    );
    final upstreamPathError = absolutePathError(upstreamPathRaw);
    if (upstreamPathError != null) {
      reader.error(r'$.upstream.path', 'invalidPath', upstreamPathError);
    }
    final upstreamPath = stripTrailingSlashes(upstreamPathRaw);
    final upstreamCommit = _readCommit(
      reader,
      upstream['commit'],
      r'$.upstream.commit',
    );

    final modsJson = reader.asList(root['mods'], r'$.mods');
    final mods = <ModEntry>[];
    final seenPaths = <String>{};
    for (var index = 0; index < modsJson.length; index++) {
      final path = _indexPath(r'$.mods', index);
      final entry = reader.asObject(modsJson[index], path);
      reader.checkKeys(
        entry,
        path,
        allowed: const {'path', 'enabled'},
        required: const {'path', 'enabled'},
      );
      final modPath = reader.asString(entry['path'], '$path.path');
      final modPathError = relativePathError(modPath);
      if (modPathError != null) {
        reader.error('$path.path', 'invalidPath', modPathError);
      }
      final enabled = reader.asBool(entry['enabled'], '$path.enabled');
      if (!seenPaths.add(modPath.toLowerCase())) {
        reader.error('$path.path', 'duplicate', '重复的 Mod 路径：$modPath');
      }
      mods.add(ModEntry(path: modPath, enabled: enabled));
    }

    return ModLoaderConfig._(
      source: source,
      schemaVersion: schemaVersion,
      upstreamPath: upstreamPath,
      upstreamCommit: upstreamCommit,
      mods: List<ModEntry>.unmodifiable(mods),
    );
  }
}

class ModEntry {
  const ModEntry({required this.path, required this.enabled});

  final String path;
  final bool enabled;
}

class ModConfig {
  const ModConfig._({
    required this.source,
    required this.schemaVersion,
    required this.id,
    required this.version,
    required this.upstreamCommit,
    required this.toolNames,
    required this.registration,
    required this.touches,
    required this.patches,
    required this.copy,
    required this.vendored,
  });

  final String source;
  final int schemaVersion;
  final String id;
  final String version;
  final String upstreamCommit;
  final List<String> toolNames;
  final Registration? registration;
  final List<String> touches;
  final List<String> patches;
  final List<CopySpec> copy;
  final List<VendoredSpec> vendored;

  bool touchesAllows(String repoRelativePath) {
    final pathError = relativePathError(repoRelativePath);
    if (pathError != null) {
      throw ArgumentError.value(
        repoRelativePath,
        'repoRelativePath',
        pathError,
      );
    }
    for (final touch in touches) {
      if (repoRelativePath == touch ||
          repoRelativePath.startsWith('$touch$pathSeparator')) {
        return true;
      }
    }
    return false;
  }

  static ModConfig load(Directory modDirectory, {String? expectedId}) {
    final modDirectoryPath = stripTrailingSlashes(
      toPosixPath(modDirectory.path),
    );
    final source = joinPath(modDirectoryPath, 'mod.json');
    final file = File(source);
    final type = FileSystemEntity.typeSync(source, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw ConfigException(
        source: source,
        path: r'$',
        code: 'invalidPath',
        message: 'mod.json 不能是符号链接',
      );
    }
    if (type != FileSystemEntityType.file) {
      throw ConfigException(
        source: source,
        path: r'$',
        code: 'missingFile',
        message: '找不到 mod.json',
      );
    }
    return parse(
      file.readAsStringSync(),
      source: source,
      expectedId: expectedId,
    );
  }

  static ModConfig parse(
    String jsonText, {
    String source = 'mod.json',
    String? expectedId,
  }) {
    final reader = _Reader(source);
    final root = reader.asObject(reader.decode(jsonText), r'$');
    reader.checkKeys(
      root,
      r'$',
      allowed: const {
        'schemaVersion',
        'id',
        'version',
        'upstreamCommit',
        'toolNames',
        'registration',
        'touches',
        'patches',
        'copy',
        'vendored',
      },
      required: const {
        'schemaVersion',
        'id',
        'version',
        'upstreamCommit',
        'toolNames',
        'touches',
        'patches',
        'copy',
      },
    );

    final schemaVersion = reader.asInt(
      root['schemaVersion'],
      r'$.schemaVersion',
    );
    if (schemaVersion != supportedSchemaVersion) {
      reader.error(
        r'$.schemaVersion',
        'unsupportedSchema',
        '仅支持 schemaVersion $supportedSchemaVersion，实际为 $schemaVersion',
      );
    }

    final id = reader.asString(root['id'], r'$.id');
    if (!_modIdPattern.hasMatch(id)) {
      reader.error(r'$.id', 'invalidValue', 'Mod id 必须是小写字母开头的 snake_case：$id');
    }
    if (expectedId != null && id != expectedId) {
      reader.error(
        r'$.id',
        'idMismatch',
        'Mod id "$id" 与目录名 "$expectedId" 不一致',
      );
    }

    final version = reader.asString(root['version'], r'$.version');
    if (!_versionPattern.hasMatch(version)) {
      reader.error(r'$.version', 'invalidValue', 'Mod version 格式不合法：$version');
    }

    final upstreamCommit = _readCommit(
      reader,
      root['upstreamCommit'],
      r'$.upstreamCommit',
    );

    final toolNames = _readStringList(
      reader,
      root['toolNames'],
      r'$.toolNames',
      pattern: _toolNamePattern,
      patternDescription: '工具名必须是小写字母开头的 snake_case',
    );

    final Registration? registration;
    if (root.containsKey('registration')) {
      registration = _readRegistration(
        reader,
        root['registration'],
        r'$.registration',
      );
    } else {
      registration = null;
    }
    if (registration == null && toolNames.isNotEmpty) {
      reader.error(
        r'$.registration',
        'missingField',
        '声明了 toolNames 的 Mod 必须提供 registration',
      );
    }

    final touches = _readPathList(reader, root['touches'], r'$.touches');
    final patches = _readPathList(
      reader,
      root['patches'],
      r'$.patches',
      extensions: const {'.patch', '.diff'},
      extensionDescription: '补丁文件必须以 .patch 或 .diff 结尾',
    );
    final copy = _readCopyList(reader, root['copy'], r'$.copy');
    final vendored = root.containsKey('vendored')
        ? _readVendoredList(reader, root['vendored'], r'$.vendored')
        : const <VendoredSpec>[];

    return ModConfig._(
      source: source,
      schemaVersion: schemaVersion,
      id: id,
      version: version,
      upstreamCommit: upstreamCommit,
      toolNames: toolNames,
      registration: registration,
      touches: touches,
      patches: patches,
      copy: copy,
      vendored: vendored,
    );
  }
}

class Registration {
  const Registration({required this.importUri, required this.className});

  final String importUri;
  final String className;
}

class CopySpec {
  CopySpec({
    required this.from,
    required this.to,
    List<String> exclude = const <String>[],
  }) : exclude = List<String>.unmodifiable(exclude);

  final String from;
  final String to;
  final List<String> exclude;

  bool isExcluded(String relativePath) {
    if (isDefaultExcludedPath(relativePath)) return true;
    final pathError = relativePathError(relativePath);
    if (pathError != null) {
      throw ArgumentError.value(relativePath, 'relativePath', pathError);
    }
    for (final entry in exclude) {
      if (relativePath == entry ||
          relativePath.startsWith('$entry$pathSeparator')) {
        return true;
      }
    }
    return false;
  }
}

class VendoredSpec {
  const VendoredSpec({
    required this.path,
    required this.commit,
    required this.hash,
  });

  final String path;
  final String commit;
  final String hash;
}

class LoadedMod {
  const LoadedMod({
    required this.entry,
    required this.directory,
    required this.config,
  });

  final ModEntry entry;
  final Directory directory;
  final ModConfig config;

  String get id => config.id;
}

class ModSet {
  const ModSet._(this.config, this.mods);

  final ModLoaderConfig config;
  final List<LoadedMod> mods;

  static ModSet load(
    String privateRepoRoot, {
    String configFileName = 'mods.json',
    bool validateFiles = true,
  }) {
    final root = stripTrailingSlashes(toPosixPath(privateRepoRoot));
    final rootError = absolutePathError(root);
    if (rootError != null) {
      throw ConfigException(
        source: privateRepoRoot,
        path: r'$',
        code: 'invalidPath',
        message: '私有仓根路径不合法：$rootError',
      );
    }
    final configFileNameError = relativePathError(configFileName);
    if (configFileNameError != null) {
      throw ConfigException(
        source: privateRepoRoot,
        path: r'$',
        code: 'invalidPath',
        message: '配置文件名不合法：$configFileNameError',
      );
    }

    final configPath = joinPath(root, configFileName);
    final configFile = File(configPath);
    if (!configFile.existsSync()) {
      throw ConfigException(
        source: configPath,
        path: r'$',
        code: 'missingFile',
        message: '找不到 $configFileName',
      );
    }
    final config = ModLoaderConfig.parse(
      configFile.readAsStringSync(),
      source: configPath,
    );

    final loaded = <LoadedMod>[];
    final seenIds = <String>{};
    final toolOwners = <String, String>{};
    final copyTargets = <String, _TargetOwner>{};

    for (var index = 0; index < config.mods.length; index++) {
      final entry = config.mods[index];
      if (!entry.enabled) continue;
      final entryPath = _indexPath(r'$.mods', index);
      final modDirectoryPath = joinPath(root, entry.path);
      if (!isWithinDirectory(root, modDirectoryPath)) {
        throw ConfigException(
          source: configPath,
          path: '$entryPath.path',
          code: 'invalidPath',
          message: 'Mod 路径超出私有仓：${entry.path}',
        );
      }
      final modDirectory = Directory(modDirectoryPath);
      final modDirectoryType = FileSystemEntity.typeSync(
        modDirectoryPath,
        followLinks: false,
      );
      if (modDirectoryType == FileSystemEntityType.link) {
        throw ConfigException(
          source: configPath,
          path: '$entryPath.path',
          code: 'invalidPath',
          message: 'Mod 目录不能是符号链接：$modDirectoryPath',
        );
      }
      if (modDirectoryType != FileSystemEntityType.directory) {
        throw ConfigException(
          source: configPath,
          path: '$entryPath.path',
          code: 'missingDirectory',
          message: 'Mod 目录不存在：$modDirectoryPath',
        );
      }

      final modConfig = ModConfig.load(
        modDirectory,
        expectedId: basename(entry.path),
      );
      if (modConfig.upstreamCommit != config.upstreamCommit) {
        throw ConfigException(
          source: modConfig.source,
          path: r'$.upstreamCommit',
          code: 'upstreamCommitMismatch',
          message:
              'Mod ${modConfig.id} 的 upstreamCommit ${modConfig.upstreamCommit} '
              '与 mods.json 的 ${config.upstreamCommit} 不一致；请显式更新 Mod 基线',
        );
      }
      if (!seenIds.add(modConfig.id.toLowerCase())) {
        throw ConfigException(
          source: modConfig.source,
          path: r'$.id',
          code: 'duplicate',
          message: '重复的 Mod id：${modConfig.id}',
        );
      }
      for (final toolName in modConfig.toolNames) {
        final owner = toolOwners[toolName];
        if (owner != null) {
          throw ConfigException(
            source: modConfig.source,
            path: r'$.toolNames',
            code: 'duplicateToolName',
            message: '工具名 $toolName 同时被 $owner 和 ${modConfig.id} 声明',
          );
        }
        toolOwners[toolName] = modConfig.id;
      }
      for (var copyIndex = 0; copyIndex < modConfig.copy.length; copyIndex++) {
        final target = modConfig.copy[copyIndex].to;
        final targetKey = target.toLowerCase();
        for (final existing in copyTargets.values) {
          final existingKey = existing.path.toLowerCase();
          if (targetKey == existingKey ||
              targetKey.startsWith('$existingKey$pathSeparator') ||
              existingKey.startsWith('$targetKey$pathSeparator')) {
            throw ConfigException(
              source: modConfig.source,
              path: '\$.copy[$copyIndex].to',
              code: 'duplicateCopyTarget',
              message:
                  '复制目标 $target 与 ${existing.modId} 的目标 ${existing.path} 冲突',
            );
          }
        }
        copyTargets[targetKey] = _TargetOwner(target, modConfig.id);
      }

      if (validateFiles) {
        _validateModFiles(modConfig, modDirectoryPath);
      }

      loaded.add(
        LoadedMod(entry: entry, directory: modDirectory, config: modConfig),
      );
    }

    return ModSet._(config, List<LoadedMod>.unmodifiable(loaded));
  }

  List<hash.ModTreeHash> computeModTrees() {
    final trees = <hash.ModTreeHash>[];
    for (final mod in mods) {
      final modDirectoryPath = stripTrailingSlashes(
        toPosixPath(mod.directory.path),
      );
      final files = <hash.FileHash>[];
      final modJson = File(joinPath(modDirectoryPath, 'mod.json'));
      files.add(
        hash.FileHash(
          path: 'mod.json',
          sha256: hash.sha256File(modJson),
          size: modJson.lengthSync(),
        ),
      );
      for (final patch in mod.config.patches) {
        final patchFile = File(joinPath(modDirectoryPath, patch));
        files.add(
          hash.FileHash(
            path: patch,
            sha256: hash.sha256File(patchFile),
            size: patchFile.lengthSync(),
          ),
        );
      }
      for (var index = 0; index < mod.config.copy.length; index++) {
        final spec = mod.config.copy[index];
        final sourcePath = joinPath(modDirectoryPath, spec.from);
        final type = FileSystemEntity.typeSync(sourcePath, followLinks: false);
        if (type == FileSystemEntityType.file) {
          final sourceFile = File(sourcePath);
          files.add(
            hash.FileHash(
              path: 'copy[$index]/${basename(spec.from)}',
              sha256: hash.sha256File(sourceFile),
              size: sourceFile.lengthSync(),
            ),
          );
        } else if (type == FileSystemEntityType.directory) {
          for (final file in hash.hashDirectory(
            Directory(sourcePath),
            exclude: spec.isExcluded,
          )) {
            files.add(
              hash.FileHash(
                path: 'copy[$index]/${file.path}',
                sha256: file.sha256,
                size: file.size,
              ),
            );
          }
        } else {
          throw ConfigException(
            source: mod.config.source,
            path: '\$.copy[$index].from',
            code: 'missingCopySource',
            message: '复制源不存在或类型不支持：$sourcePath',
          );
        }
      }
      trees.add(
        hash.ModTreeHash(
          id: mod.config.id,
          version: mod.config.version,
          treeHash: hash.hashFileList(files),
        ),
      );
    }
    return List<hash.ModTreeHash>.unmodifiable(trees);
  }

  String computeModsetHash({required String loaderVersion}) {
    return hash.computeModsetHash(
      schemaVersion: config.schemaVersion,
      upstreamCommit: config.upstreamCommit,
      loaderVersion: loaderVersion,
      mods: computeModTrees(),
    );
  }
}

class _TargetOwner {
  const _TargetOwner(this.path, this.modId);

  final String path;
  final String modId;
}

void _validateModFiles(ModConfig config, String modDirectoryPath) {
  for (final patch in config.patches) {
    final patchFile = File(joinPath(modDirectoryPath, patch));
    final type = FileSystemEntity.typeSync(patchFile.path, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw ConfigException(
        source: config.source,
        path: r'$.patches',
        code: 'invalidPath',
        message: '补丁文件不能是符号链接：${patchFile.path}',
      );
    }
    if (type != FileSystemEntityType.file) {
      throw ConfigException(
        source: config.source,
        path: r'$.patches',
        code: 'missingFile',
        message: '补丁文件不存在：${patchFile.path}',
      );
    }
  }
  for (var index = 0; index < config.copy.length; index++) {
    final sourcePath = joinPath(modDirectoryPath, config.copy[index].from);
    final type = FileSystemEntity.typeSync(sourcePath, followLinks: false);
    if (type != FileSystemEntityType.file &&
        type != FileSystemEntityType.directory) {
      throw ConfigException(
        source: config.source,
        path: '\$.copy[$index].from',
        code: 'missingCopySource',
        message: '复制源不存在、是符号链接或类型不支持：$sourcePath',
      );
    }
  }
}

String _readCommit(_Reader reader, Object? value, String path) {
  final commit = reader.asString(value, path);
  if (!hash.isFullCommitSha(commit)) {
    reader.error(
      path,
      'invalidCommit',
      '必须是完整 40 位小写 commit SHA，不能使用分支、标签或短 SHA：$commit',
    );
  }
  return commit;
}

List<String> _readStringList(
  _Reader reader,
  Object? value,
  String path, {
  RegExp? pattern,
  String? patternDescription,
}) {
  final list = reader.asList(value, path);
  final result = <String>[];
  final seen = <String>{};
  for (var index = 0; index < list.length; index++) {
    final itemPath = _indexPath(path, index);
    final item = reader.asString(list[index], itemPath);
    if (pattern != null && !pattern.hasMatch(item)) {
      reader.error(
        itemPath,
        'invalidValue',
        '${patternDescription ?? '格式不合法'}：$item',
      );
    }
    if (!seen.add(item)) {
      reader.error(itemPath, 'duplicate', '重复的值：$item');
    }
    result.add(item);
  }
  return List<String>.unmodifiable(result);
}

List<String> _readPathList(
  _Reader reader,
  Object? value,
  String path, {
  Set<String>? extensions,
  String? extensionDescription,
}) {
  final list = reader.asList(value, path);
  final result = <String>[];
  final seen = <String>{};
  for (var index = 0; index < list.length; index++) {
    final itemPath = _indexPath(path, index);
    final item = reader.asString(list[index], itemPath);
    final pathError = relativePathError(item);
    if (pathError != null) {
      reader.error(itemPath, 'invalidPath', pathError);
    }
    if (isDefaultExcludedPath(item)) {
      reader.error(itemPath, 'invalidPath', '路径不能是默认排除路径：$item');
    }
    if (extensions != null && !extensions.any(item.endsWith)) {
      reader.error(
        itemPath,
        'invalidPath',
        extensionDescription ?? '文件扩展名不合法：$item',
      );
    }
    if (!seen.add(item.toLowerCase())) {
      reader.error(itemPath, 'duplicate', '重复的路径：$item');
    }
    result.add(item);
  }
  return List<String>.unmodifiable(result);
}

Registration _readRegistration(_Reader reader, Object? value, String path) {
  final map = reader.asObject(value, path);
  reader.checkKeys(
    map,
    path,
    allowed: const {'import', 'className'},
    required: const {'import', 'className'},
  );
  final importUri = reader.asString(map['import'], '$path.import');
  final importError = _importUriError(importUri);
  if (importError != null) {
    reader.error('$path.import', 'invalidValue', importError);
  }
  final className = reader.asString(map['className'], '$path.className');
  if (!_classNamePattern.hasMatch(className)) {
    reader.error(
      '$path.className',
      'invalidValue',
      '注册类名必须是合法 Dart 标识符：$className',
    );
  }
  return Registration(importUri: importUri, className: className);
}

String? _importUriError(String uri) {
  if (uri.startsWith('package:')) {
    final rest = uri.substring('package:'.length);
    final slash = rest.indexOf(pathSeparator);
    if (slash <= 0 || slash == rest.length - 1) {
      return 'package URI 必须包含包名和文件路径：$uri';
    }
    final packageName = rest.substring(0, slash);
    if (!_packageNamePattern.hasMatch(packageName)) {
      return 'package 名不合法：$packageName';
    }
    final filePath = rest.substring(slash + 1);
    final pathError = relativePathError(filePath);
    if (pathError != null) return pathError;
    if (!filePath.endsWith('.dart')) {
      return 'package URI 必须指向 .dart 文件：$uri';
    }
    return null;
  }
  if (uri.contains(':')) return '只支持 package: URI：$uri';
  final pathError = relativePathError(uri);
  if (pathError != null) return pathError;
  if (!uri.endsWith('.dart')) return '相对 import 必须指向 .dart 文件：$uri';
  return null;
}

List<CopySpec> _readCopyList(_Reader reader, Object? value, String path) {
  final list = reader.asList(value, path);
  final result = <CopySpec>[];
  final seenTargets = <String>{};
  for (var index = 0; index < list.length; index++) {
    final itemPath = _indexPath(path, index);
    final map = reader.asObject(list[index], itemPath);
    reader.checkKeys(
      map,
      itemPath,
      allowed: const {'from', 'to', 'exclude'},
      required: const {'from', 'to'},
    );
    final from = reader.asString(map['from'], '$itemPath.from');
    final fromError = relativePathError(from);
    if (fromError != null) {
      reader.error('$itemPath.from', 'invalidPath', fromError);
    }
    if (isDefaultExcludedPath(from)) {
      reader.error('$itemPath.from', 'invalidPath', '复制源不能是默认排除路径：$from');
    }
    final to = reader.asString(map['to'], '$itemPath.to');
    final toError = relativePathError(to);
    if (toError != null) {
      reader.error('$itemPath.to', 'invalidPath', toError);
    }
    if (isDefaultExcludedPath(to)) {
      reader.error('$itemPath.to', 'invalidPath', '复制目标不能是默认排除路径：$to');
    }
    if (!seenTargets.add(to.toLowerCase())) {
      reader.error('$itemPath.to', 'duplicate', '重复的复制目标：$to');
    }
    final exclude = map.containsKey('exclude')
        ? _readExcludeList(reader, map['exclude'], '$itemPath.exclude')
        : const <String>[];
    result.add(CopySpec(from: from, to: to, exclude: exclude));
  }
  return List<CopySpec>.unmodifiable(result);
}

List<String> _readExcludeList(_Reader reader, Object? value, String path) {
  final list = reader.asList(value, path);
  final result = <String>[];
  final seen = <String>{};
  for (var index = 0; index < list.length; index++) {
    final itemPath = _indexPath(path, index);
    final item = reader.asString(list[index], itemPath);
    if (containsGlobCharacters(item)) {
      reader.error(itemPath, 'invalidValue', '不支持通配符排除项，请使用相对路径前缀：$item');
    }
    final pathError = relativePathError(item);
    if (pathError != null) {
      reader.error(itemPath, 'invalidPath', pathError);
    }
    if (!seen.add(item.toLowerCase())) {
      reader.error(itemPath, 'duplicate', '重复的排除项：$item');
    }
    result.add(item);
  }
  return List<String>.unmodifiable(result);
}

List<VendoredSpec> _readVendoredList(
  _Reader reader,
  Object? value,
  String path,
) {
  final list = reader.asList(value, path);
  final result = <VendoredSpec>[];
  final seen = <String>{};
  for (var index = 0; index < list.length; index++) {
    final itemPath = _indexPath(path, index);
    final map = reader.asObject(list[index], itemPath);
    reader.checkKeys(
      map,
      itemPath,
      allowed: const {'path', 'commit', 'hash'},
      required: const {'path', 'commit', 'hash'},
    );
    final vendoredPath = reader.asString(map['path'], '$itemPath.path');
    final pathError = relativePathError(vendoredPath);
    if (pathError != null) {
      reader.error('$itemPath.path', 'invalidPath', pathError);
    }
    if (isDefaultExcludedPath(vendoredPath)) {
      reader.error(
        '$itemPath.path',
        'invalidPath',
        'vendored 路径不能是默认排除路径：$vendoredPath',
      );
    }
    final commit = _readCommit(reader, map['commit'], '$itemPath.commit');
    final hashValue = reader.asString(map['hash'], '$itemPath.hash');
    if (!hash.isSha256Hex(hashValue)) {
      reader.error(
        '$itemPath.hash',
        'invalidValue',
        'vendored 哈希必须是完整 64 位小写 SHA-256：$hashValue',
      );
    }
    if (!seen.add(vendoredPath.toLowerCase())) {
      reader.error(
        '$itemPath.path',
        'duplicate',
        '重复的 vendored 路径：$vendoredPath',
      );
    }
    result.add(
      VendoredSpec(path: vendoredPath, commit: commit, hash: hashValue),
    );
  }
  return List<VendoredSpec>.unmodifiable(result);
}

String _indexPath(String path, int index) => '$path[$index]';

class _Reader {
  _Reader(this.source);

  final String source;

  Never error(String path, String code, String message) {
    throw ConfigException(
      source: source,
      path: path,
      code: code,
      message: message,
    );
  }

  Object? decode(String text) {
    final normalized = text.startsWith('\uFEFF') ? text.substring(1) : text;
    try {
      return jsonDecode(normalized);
    } on FormatException catch (formatError) {
      final offset = (formatError.offset ?? 0).clamp(0, normalized.length);
      final line = '\n'.allMatches(normalized.substring(0, offset)).length + 1;
      final lastNewline = normalized.lastIndexOf('\n', offset - 1);
      final column = offset - lastNewline;
      error(
        r'$',
        'invalidJson',
        'JSON 语法错误（第 $line 行第 $column 列）：${formatError.message}',
      );
    }
  }

  Map<String, Object?> asObject(Object? value, String path) {
    if (value is! Map) error(path, 'invalidType', '必须是 JSON 对象');
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) error(path, 'invalidType', '对象键必须是字符串');
      result[key] = entry.value;
    }
    return result;
  }

  List<Object?> asList(Object? value, String path) {
    if (value is! List) error(path, 'invalidType', '必须是 JSON 数组');
    return List<Object?>.from(value);
  }

  String asString(Object? value, String path) {
    if (value is! String) error(path, 'invalidType', '必须是字符串');
    if (value.isEmpty) error(path, 'invalidValue', '不能为空字符串');
    for (final code in value.codeUnits) {
      if (code < 0x20 || code == 0x7f) {
        error(path, 'invalidValue', '不能包含控制字符');
      }
    }
    return value;
  }

  bool asBool(Object? value, String path) {
    if (value is! bool) error(path, 'invalidType', '必须是布尔值');
    return value;
  }

  int asInt(Object? value, String path) {
    if (value is! int) error(path, 'invalidType', '必须是整数');
    return value;
  }

  void checkKeys(
    Map<String, Object?> map,
    String path, {
    required Set<String> allowed,
    Set<String> required = const <String>{},
  }) {
    for (final key in map.keys) {
      if (!allowed.contains(key)) {
        error('$path.$key', 'unknownField', '未知字段 "$key"');
      }
    }
    for (final key in required) {
      if (!map.containsKey(key)) {
        error(path, 'missingField', '缺少必填字段 "$key"');
      }
    }
  }
}
