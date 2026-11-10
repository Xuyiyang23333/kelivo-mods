import 'dart:convert';
import 'dart:io';

import 'hash.dart' as hash;
import 'paths.dart';

const int buildRecordSchemaVersion = 1;
const String buildRecordFileName = 'MOD_BUILD.json';

class BuildRecordException implements Exception {
  const BuildRecordException(this.message, {this.source});

  final String message;
  final String? source;

  @override
  String toString() => source == null ? message : '$source：$message';
}

class BuildModRecord {
  const BuildModRecord({
    required this.id,
    required this.version,
    required this.path,
    required this.treeHash,
  });

  final String id;
  final String version;
  final String path;
  final String treeHash;
}

class BuildRecord {
  BuildRecord({
    required this.schemaVersion,
    required this.loaderVersion,
    required this.modsetHash,
    required this.upstreamPath,
    required this.upstreamCommit,
    required this.indexDiffHash,
    required List<BuildModRecord> mods,
    required Map<String, String?> patchedFiles,
    required Map<String, String> copiedFiles,
    required Map<String, String> generatedFiles,
  }) : mods = List<BuildModRecord>.unmodifiable(mods),
       patchedFiles = Map<String, String?>.unmodifiable(patchedFiles),
       copiedFiles = Map<String, String>.unmodifiable(copiedFiles),
       generatedFiles = Map<String, String>.unmodifiable(generatedFiles);

  final int schemaVersion;
  final String loaderVersion;
  final String modsetHash;
  final String upstreamPath;
  final String upstreamCommit;
  final String indexDiffHash;
  final List<BuildModRecord> mods;
  final Map<String, String?> patchedFiles;
  final Map<String, String> copiedFiles;
  final Map<String, String> generatedFiles;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'loaderVersion': loaderVersion,
    'modsetHash': modsetHash,
    'upstream': <String, Object?>{
      'path': upstreamPath,
      'commit': upstreamCommit,
    },
    'indexDiffHash': indexDiffHash,
    'mods': <Map<String, Object?>>[
      for (final mod in mods)
        <String, Object?>{
          'id': mod.id,
          'version': mod.version,
          'path': mod.path,
          'treeHash': mod.treeHash,
        },
    ],
    'patchedFiles': patchedFiles,
    'copiedFiles': copiedFiles,
    'generatedFiles': generatedFiles,
  };

  void write(File file) {
    final type = FileSystemEntity.typeSync(file.path, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw BuildRecordException('构建记录不能是符号链接', source: file.path);
    }
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw BuildRecordException('构建记录路径不是普通文件', source: file.path);
    }
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n',
      flush: true,
    );
  }

  static BuildRecord read(File file) {
    final type = FileSystemEntity.typeSync(file.path, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw BuildRecordException('构建记录不能是符号链接', source: file.path);
    }
    if (type != FileSystemEntityType.file) {
      throw BuildRecordException('构建记录不存在或不是普通文件', source: file.path);
    }
    return parse(file.readAsStringSync(), source: file.path);
  }

  static BuildRecord parse(
    String jsonText, {
    String source = buildRecordFileName,
  }) {
    final reader = _Reader(source);
    final root = reader.object(reader.decode(jsonText), r'$');
    reader.checkKeys(
      root,
      r'$',
      allowed: const {
        'schemaVersion',
        'loaderVersion',
        'modsetHash',
        'upstream',
        'indexDiffHash',
        'mods',
        'patchedFiles',
        'copiedFiles',
        'generatedFiles',
      },
      required: const {
        'schemaVersion',
        'loaderVersion',
        'modsetHash',
        'upstream',
        'indexDiffHash',
        'mods',
        'patchedFiles',
        'copiedFiles',
        'generatedFiles',
      },
    );

    final schemaVersion = reader.integer(
      root['schemaVersion'],
      r'$.schemaVersion',
    );
    if (schemaVersion != buildRecordSchemaVersion) {
      reader.error(
        r'$.schemaVersion',
        '仅支持 schemaVersion $buildRecordSchemaVersion，实际为 $schemaVersion',
      );
    }
    final loaderVersion = reader.string(
      root['loaderVersion'],
      r'$.loaderVersion',
    );
    if (loaderVersion.contains(RegExp(r'\s'))) {
      reader.error(r'$.loaderVersion', '不能包含空白');
    }
    final modsetHash = reader.sha256(root['modsetHash'], r'$.modsetHash');
    final upstream = reader.object(root['upstream'], r'$.upstream');
    reader.checkKeys(
      upstream,
      r'$.upstream',
      allowed: const {'path', 'commit'},
      required: const {'path', 'commit'},
    );
    final upstreamPath = reader.string(upstream['path'], r'$.upstream.path');
    final upstreamPathError = absolutePathError(upstreamPath);
    if (upstreamPathError != null) {
      reader.error(r'$.upstream.path', upstreamPathError);
    }
    final upstreamCommit = reader.commit(
      upstream['commit'],
      r'$.upstream.commit',
    );
    final indexDiffHash = reader.sha256(
      root['indexDiffHash'],
      r'$.indexDiffHash',
    );

    final modsJson = reader.list(root['mods'], r'$.mods');
    final mods = <BuildModRecord>[];
    final ids = <String>{};
    final paths = <String>{};
    for (var index = 0; index < modsJson.length; index++) {
      final path = r'$.mods[' + '$index]';
      final mod = reader.object(modsJson[index], path);
      reader.checkKeys(
        mod,
        path,
        allowed: const {'id', 'version', 'path', 'treeHash'},
        required: const {'id', 'version', 'path', 'treeHash'},
      );
      final id = reader.string(mod['id'], '$path.id');
      if (id.contains(RegExp(r'\s'))) {
        reader.error('$path.id', '不能包含空白');
      }
      if (!ids.add(id)) reader.error('$path.id', '重复的 Mod id：$id');
      final version = reader.string(mod['version'], '$path.version');
      if (version.contains(RegExp(r'\s'))) {
        reader.error('$path.version', '不能包含空白');
      }
      final modPath = reader.relativePath(mod['path'], '$path.path');
      if (!paths.add(modPath.toLowerCase())) {
        reader.error('$path.path', '重复的 Mod 路径：$modPath');
      }
      final treeHash = reader.sha256(mod['treeHash'], '$path.treeHash');
      mods.add(
        BuildModRecord(
          id: id,
          version: version,
          path: modPath,
          treeHash: treeHash,
        ),
      );
    }

    final patchedFiles = reader.hashMap(
      root['patchedFiles'],
      r'$.patchedFiles',
      allowNull: true,
    );
    final copiedFiles = reader.hashMap(
      root['copiedFiles'],
      r'$.copiedFiles',
      allowNull: false,
    );
    final generatedFiles = reader.hashMap(
      root['generatedFiles'],
      r'$.generatedFiles',
      allowNull: false,
    );

    return BuildRecord(
      schemaVersion: schemaVersion,
      loaderVersion: loaderVersion,
      modsetHash: modsetHash,
      upstreamPath: upstreamPath,
      upstreamCommit: upstreamCommit,
      indexDiffHash: indexDiffHash,
      mods: mods,
      patchedFiles: patchedFiles,
      copiedFiles: <String, String>{
        for (final entry in copiedFiles.entries) entry.key: entry.value!,
      },
      generatedFiles: <String, String>{
        for (final entry in generatedFiles.entries) entry.key: entry.value!,
      },
    );
  }
}

class _Reader {
  _Reader(this.source);

  final String source;

  Never error(String path, String message) {
    throw BuildRecordException('$path：$message', source: source);
  }

  Object? decode(String text) {
    final normalized = text.startsWith('\uFEFF') ? text.substring(1) : text;
    try {
      return jsonDecode(normalized);
    } on FormatException catch (formatError) {
      error(r'$', 'JSON 语法错误：${formatError.message}');
    }
  }

  Map<String, Object?> object(Object? value, String path) {
    if (value is! Map) error(path, '必须是 JSON 对象');
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) error(path, '对象键必须是字符串');
      result[entry.key as String] = entry.value;
    }
    return result;
  }

  List<Object?> list(Object? value, String path) {
    if (value is! List) error(path, '必须是 JSON 数组');
    return List<Object?>.from(value);
  }

  String string(Object? value, String path) {
    if (value is! String) error(path, '必须是字符串');
    if (value.isEmpty) error(path, '不能为空字符串');
    for (final code in value.codeUnits) {
      if (code < 0x20 || code == 0x7f) {
        error(path, '不能包含控制字符');
      }
    }
    return value;
  }

  int integer(Object? value, String path) {
    if (value is! int) error(path, '必须是整数');
    return value;
  }

  String sha256(Object? value, String path) {
    final text = string(value, path);
    if (!hash.isSha256Hex(text)) {
      error(path, '必须是完整 64 位小写 SHA-256');
    }
    return text;
  }

  String commit(Object? value, String path) {
    final text = string(value, path);
    if (!hash.isFullCommitSha(text)) {
      error(path, '必须是完整 40 位小写 commit SHA');
    }
    return text;
  }

  String relativePath(Object? value, String path) {
    final text = string(value, path);
    final errorText = relativePathError(text);
    if (errorText != null) error(path, errorText);
    return text;
  }

  Map<String, String?> hashMap(
    Object? value,
    String path, {
    required bool allowNull,
  }) {
    final map = object(value, path);
    final result = <String, String?>{};
    for (final entry in map.entries) {
      final keyError = relativePathError(entry.key);
      if (keyError != null) error('$path.${entry.key}', keyError);
      final item = entry.value;
      if (item == null) {
        if (!allowNull) error('$path.${entry.key}', '哈希不能为 null');
        result[entry.key] = null;
        continue;
      }
      if (item is! String || !hash.isSha256Hex(item)) {
        error('$path.${entry.key}', '必须是完整 64 位小写 SHA-256');
      }
      result[entry.key] = item;
    }
    return result;
  }

  void checkKeys(
    Map<String, Object?> map,
    String path, {
    required Set<String> allowed,
    Set<String> required = const <String>{},
  }) {
    for (final key in map.keys) {
      if (!allowed.contains(key)) {
        error('$path.$key', '未知字段 "$key"');
      }
    }
    for (final key in required) {
      if (!map.containsKey(key)) {
        error(path, '缺少必填字段 "$key"');
      }
    }
  }
}
