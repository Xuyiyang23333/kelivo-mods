import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'paths.dart';

final RegExp fullCommitPattern = RegExp(r'^[0-9a-f]{40}$');
final RegExp sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
final RegExp _modIdPattern = RegExp(r'^[a-z][a-z0-9_]*$');

bool isFullCommitSha(String value) => fullCommitPattern.hasMatch(value);

bool isSha256Hex(String value) => sha256Pattern.hasMatch(value);

class HashException implements Exception {
  HashException(this.path, this.message);

  final String path;
  final String message;

  @override
  String toString() => '哈希计算失败：$path：$message';
}

class FileHash {
  const FileHash({
    required this.path,
    required this.sha256,
    required this.size,
  });

  final String path;
  final String sha256;
  final int size;
}

class ModTreeHash {
  const ModTreeHash({
    required this.id,
    required this.version,
    required this.treeHash,
  });

  final String id;
  final String version;
  final String treeHash;
}

String sha256Hex(List<int> bytes) {
  final digest = _sha256Digest(bytes);
  final buffer = StringBuffer();
  for (final byte in digest) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

String sha256Text(String text) => sha256Hex(utf8.encode(text));

String sha256File(File file) {
  if (!file.existsSync()) throw HashException(file.path, '文件不存在');
  return sha256Hex(file.readAsBytesSync());
}

List<FileHash> hashDirectory(
  Directory root, {
  bool Function(String relativePath)? exclude,
}) {
  final rootType = FileSystemEntity.typeSync(root.path, followLinks: false);
  if (rootType == FileSystemEntityType.link) {
    throw HashException(root.path, '不允许符号链接目录');
  }
  if (rootType != FileSystemEntityType.directory) {
    throw HashException(root.path, '目录不存在或不是目录');
  }
  final rootPath = stripTrailingSlashes(toPosixPath(root.path));
  final files = <FileHash>[];
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    final entityPath = toPosixPath(entity.path);
    final relative = relativeTo(rootPath, entityPath);
    if (relative == null || relative.isEmpty) {
      throw HashException(entity.path, '无法计算相对于目录根的路径');
    }
    if (entity is Link) {
      throw HashException(entity.path, '不允许符号链接');
    }
    if (entity is Directory) continue;
    if (entity is! File) {
      throw HashException(entity.path, '不支持的文件类型');
    }
    if (isDefaultExcludedPath(relative)) continue;
    if (exclude != null && exclude(relative)) continue;
    final pathError = relativePathError(relative);
    if (pathError != null) {
      throw HashException(entity.path, '路径不合法：$pathError');
    }
    files.add(
      FileHash(
        path: relative,
        sha256: sha256File(entity),
        size: entity.lengthSync(),
      ),
    );
  }
  return _sortedUnique(files);
}

String hashFileList(Iterable<FileHash> files) {
  final sorted = _sortedUnique(files.toList());
  final buffer = StringBuffer();
  for (final file in sorted) {
    buffer.writeln('${file.sha256}  ${file.path}');
  }
  return sha256Text(buffer.toString());
}

String computeModsetHash({
  required int schemaVersion,
  required String upstreamCommit,
  required String loaderVersion,
  required List<ModTreeHash> mods,
}) {
  if (schemaVersion <= 0) {
    throw ArgumentError.value(schemaVersion, 'schemaVersion', '必须为正整数');
  }
  if (!isFullCommitSha(upstreamCommit)) {
    throw ArgumentError.value(
      upstreamCommit,
      'upstreamCommit',
      '必须是完整 40 位小写 commit SHA',
    );
  }
  if (loaderVersion.isEmpty || loaderVersion.contains(RegExp(r'\s'))) {
    throw ArgumentError.value(loaderVersion, 'loaderVersion', '不能为空或包含空白');
  }
  final seenIds = <String>{};
  final buffer = StringBuffer()
    ..writeln('kelivo-modset-v1')
    ..writeln('schema $schemaVersion')
    ..writeln('loader $loaderVersion')
    ..writeln('upstream $upstreamCommit');
  for (final mod in mods) {
    if (!_modIdPattern.hasMatch(mod.id)) {
      throw ArgumentError.value(mod.id, 'mods.id', 'Mod id 不合法');
    }
    if (!seenIds.add(mod.id)) {
      throw ArgumentError.value(mod.id, 'mods.id', '重复的 Mod id');
    }
    if (mod.version.isEmpty || mod.version.contains(RegExp(r'\s'))) {
      throw ArgumentError.value(mod.version, 'mods.version', '不能为空或包含空白');
    }
    if (!isSha256Hex(mod.treeHash)) {
      throw ArgumentError.value(
        mod.treeHash,
        'mods.treeHash',
        '必须是完整 64 位小写 SHA-256',
      );
    }
    buffer.writeln('mod ${mod.id} ${mod.version} ${mod.treeHash}');
  }
  return sha256Text(buffer.toString());
}

String modsetDirectoryName(String modsetHash) {
  if (!isSha256Hex(modsetHash)) {
    throw ArgumentError.value(modsetHash, 'modsetHash', '必须是完整 64 位小写 SHA-256');
  }
  return modsetHash.substring(0, 16);
}

List<FileHash> _sortedUnique(List<FileHash> files) {
  final exactPaths = <String>{};
  final lowerPaths = <String, String>{};
  for (final file in files) {
    final pathError = relativePathError(file.path);
    if (pathError != null) {
      throw HashException(file.path, '路径不合法：$pathError');
    }
    if (!isSha256Hex(file.sha256)) {
      throw HashException(file.path, '哈希必须是完整 64 位小写 SHA-256');
    }
    if (!exactPaths.add(file.path)) {
      throw HashException(file.path, '重复的文件路径');
    }
    final lower = file.path.toLowerCase();
    final existing = lowerPaths[lower];
    if (existing != null) {
      throw HashException(file.path, '与 "$existing" 仅大小写不同，存在 Windows 路径冲突');
    }
    lowerPaths[lower] = file.path;
  }
  final sorted = List<FileHash>.of(files)
    ..sort((left, right) => left.path.compareTo(right.path));
  return List<FileHash>.unmodifiable(sorted);
}

const List<int> _sha256K = <int>[
  0x428a2f98,
  0x71374491,
  0xb5c0fbcf,
  0xe9b5dba5,
  0x3956c25b,
  0x59f111f1,
  0x923f82a4,
  0xab1c5ed5,
  0xd807aa98,
  0x12835b01,
  0x243185be,
  0x550c7dc3,
  0x72be5d74,
  0x80deb1fe,
  0x9bdc06a7,
  0xc19bf174,
  0xe49b69c1,
  0xefbe4786,
  0x0fc19dc6,
  0x240ca1cc,
  0x2de92c6f,
  0x4a7484aa,
  0x5cb0a9dc,
  0x76f988da,
  0x983e5152,
  0xa831c66d,
  0xb00327c8,
  0xbf597fc7,
  0xc6e00bf3,
  0xd5a79147,
  0x06ca6351,
  0x14292967,
  0x27b70a85,
  0x2e1b2138,
  0x4d2c6dfc,
  0x53380d13,
  0x650a7354,
  0x766a0abb,
  0x81c2c92e,
  0x92722c85,
  0xa2bfe8a1,
  0xa81a664b,
  0xc24b8b70,
  0xc76c51a3,
  0xd192e819,
  0xd6990624,
  0xf40e3585,
  0x106aa070,
  0x19a4c116,
  0x1e376c08,
  0x2748774c,
  0x34b0bcb5,
  0x391c0cb3,
  0x4ed8aa4a,
  0x5b9cca4f,
  0x682e6ff3,
  0x748f82ee,
  0x78a5636f,
  0x84c87814,
  0x8cc70208,
  0x90befffa,
  0xa4506ceb,
  0xbef9a3f7,
  0xc67178f2,
];

List<int> _sha256Digest(List<int> message) {
  final bitLength = message.length * 8;
  final paddedLength = ((message.length + 9 + 63) ~/ 64) * 64;
  final data = Uint8List(paddedLength)..setRange(0, message.length, message);
  data[message.length] = 0x80;
  final view = ByteData.sublistView(data);
  view.setUint32(
    paddedLength - 8,
    (bitLength ~/ 0x100000000) & 0xffffffff,
    Endian.big,
  );
  view.setUint32(paddedLength - 4, bitLength & 0xffffffff, Endian.big);

  final hash = Uint32List.fromList(<int>[
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  ]);
  final words = Uint32List(64);

  for (var offset = 0; offset < paddedLength; offset += 64) {
    for (var index = 0; index < 16; index++) {
      words[index] = view.getUint32(offset + index * 4, Endian.big);
    }
    for (var index = 16; index < 64; index++) {
      final s0 =
          _rotateRight(words[index - 15], 7) ^
          _rotateRight(words[index - 15], 18) ^
          (words[index - 15] >> 3);
      final s1 =
          _rotateRight(words[index - 2], 17) ^
          _rotateRight(words[index - 2], 19) ^
          (words[index - 2] >> 10);
      words[index] =
          (words[index - 16] + s0 + words[index - 7] + s1) & 0xffffffff;
    }

    var a = hash[0];
    var b = hash[1];
    var c = hash[2];
    var d = hash[3];
    var e = hash[4];
    var f = hash[5];
    var g = hash[6];
    var h = hash[7];

    for (var index = 0; index < 64; index++) {
      final s1 = _rotateRight(e, 6) ^ _rotateRight(e, 11) ^ _rotateRight(e, 25);
      final choose = (e & f) ^ ((~e & 0xffffffff) & g);
      final temp1 =
          (h + s1 + choose + _sha256K[index] + words[index]) & 0xffffffff;
      final s0 = _rotateRight(a, 2) ^ _rotateRight(a, 13) ^ _rotateRight(a, 22);
      final majority = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = (s0 + majority) & 0xffffffff;

      h = g;
      g = f;
      f = e;
      e = (d + temp1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & 0xffffffff;
    }

    hash[0] = (hash[0] + a) & 0xffffffff;
    hash[1] = (hash[1] + b) & 0xffffffff;
    hash[2] = (hash[2] + c) & 0xffffffff;
    hash[3] = (hash[3] + d) & 0xffffffff;
    hash[4] = (hash[4] + e) & 0xffffffff;
    hash[5] = (hash[5] + f) & 0xffffffff;
    hash[6] = (hash[6] + g) & 0xffffffff;
    hash[7] = (hash[7] + h) & 0xffffffff;
  }

  final digest = Uint8List(32);
  final digestView = ByteData.sublistView(digest);
  for (var index = 0; index < 8; index++) {
    digestView.setUint32(index * 4, hash[index], Endian.big);
  }
  return digest;
}

int _rotateRight(int value, int amount) =>
    ((value >> amount) | (value << (32 - amount))) & 0xffffffff;
