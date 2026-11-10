import 'dart:io';

const String pathSeparator = '/';

final RegExp _driveRootPattern = RegExp(r'^[A-Za-z]:/$');
final RegExp _drivePrefixPattern = RegExp(r'^[A-Za-z]:');
final RegExp _drivePathPattern = RegExp(r'^[A-Za-z]:/');
final RegExp _uncRootPattern = RegExp(r'^//[^/]+/[^/]+$');
final RegExp _windowsInvalidCharacters = RegExp(r'[<>:"|?*]');
final RegExp _windowsReservedDevice = RegExp(r'^(COM|LPT)[1-9]$');
final RegExp _globCharacters = RegExp(r'[*?\[\]]');

bool get isWindows => Platform.isWindows;

String toPosixPath(String path) => path.replaceAll('\\', '/');

String stripTrailingSlashes(String path) {
  var result = toPosixPath(path);
  while (result.length > 1 && result.endsWith(pathSeparator)) {
    if (_driveRootPattern.hasMatch(result)) break;
    result = result.substring(0, result.length - 1);
  }
  return result;
}

bool isAbsolutePath(String path) {
  if (path.isEmpty) return false;
  final normalized = toPosixPath(path);
  if (normalized.startsWith(pathSeparator)) return true;
  return _drivePrefixPattern.hasMatch(normalized);
}

String normalizePath(String path) {
  final normalized = toPosixPath(path);
  if (normalized.isEmpty) return '';
  if (normalized == pathSeparator || _driveRootPattern.hasMatch(normalized)) {
    return normalized;
  }
  final isUnc = normalized.startsWith('//');
  final hasLeadingSlash = normalized.startsWith(pathSeparator);
  final parts = <String>[];
  for (final part in normalized.split(pathSeparator)) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (parts.isNotEmpty) parts.removeLast();
      continue;
    }
    parts.add(part);
  }
  final prefix = isUnc ? '//' : (hasLeadingSlash ? pathSeparator : '');
  if (parts.isEmpty) return prefix.isEmpty ? '' : prefix;
  return '$prefix${parts.join(pathSeparator)}';
}

String _comparable(String normalizedPath) =>
    isWindows ? normalizedPath.toLowerCase() : normalizedPath;

bool samePath(String left, String right) =>
    _comparable(normalizePath(left)) == _comparable(normalizePath(right));

bool isWithinDirectory(String parent, String child, {bool allowEqual = false}) {
  final normalizedParent = _comparable(normalizePath(parent));
  final normalizedChild = _comparable(normalizePath(child));
  if (normalizedParent == normalizedChild) return allowEqual;
  if (normalizedParent.isEmpty) return false;
  if (normalizedParent == pathSeparator) {
    return normalizedChild.startsWith(pathSeparator) &&
        normalizedChild.length > 1;
  }
  if (_driveRootPattern.hasMatch(normalizedParent)) {
    return normalizedChild.startsWith(normalizedParent) &&
        normalizedChild.length > normalizedParent.length;
  }
  return normalizedChild.startsWith('$normalizedParent$pathSeparator');
}

String? relativeTo(String parent, String child) {
  if (!isWithinDirectory(parent, child, allowEqual: true)) return null;
  final normalizedParent = stripTrailingSlashes(normalizePath(parent));
  final normalizedChild = stripTrailingSlashes(normalizePath(child));
  if (samePath(normalizedParent, normalizedChild)) return '';
  if (normalizedParent == pathSeparator) {
    return normalizedChild.substring(1);
  }
  if (_driveRootPattern.hasMatch(normalizedParent)) {
    return normalizedChild.substring(normalizedParent.length);
  }
  return normalizedChild.substring(normalizedParent.length + 1);
}

String joinPath(String base, String relative) {
  if (relative.isEmpty) return base;
  if (isAbsolutePath(relative)) {
    throw ArgumentError.value(relative, 'relative', '不能拼接绝对路径');
  }
  final normalizedBase = stripTrailingSlashes(base);
  if (normalizedBase.isEmpty) return relative;
  if (normalizedBase == pathSeparator) return '$pathSeparator$relative';
  if (_driveRootPattern.hasMatch(normalizedBase)) {
    return '$normalizedBase$relative';
  }
  return '$normalizedBase$pathSeparator$relative';
}

String basename(String path) {
  final normalized = stripTrailingSlashes(toPosixPath(path));
  if (normalized.isEmpty) return '';
  final index = normalized.lastIndexOf(pathSeparator);
  if (index < 0) return normalized;
  return normalized.substring(index + 1);
}

String dirname(String path) {
  final normalized = stripTrailingSlashes(toPosixPath(path));
  final index = normalized.lastIndexOf(pathSeparator);
  if (index < 0) return '';
  if (index == 0) return pathSeparator;
  if (index == 2 && _drivePrefixPattern.hasMatch(normalized)) {
    return normalized.substring(0, 3);
  }
  return normalized.substring(0, index);
}

bool _isWindowsReservedName(String segment) {
  final dot = segment.indexOf('.');
  final base = (dot >= 0 ? segment.substring(0, dot) : segment).toUpperCase();
  if (base == 'CON' || base == 'PRN' || base == 'AUX' || base == 'NUL') {
    return true;
  }
  return _windowsReservedDevice.hasMatch(base);
}

String? relativePathError(String path) {
  if (path.isEmpty) return '路径不能为空';
  if (path.contains('\\')) return '仓库内路径必须使用 / 分隔符';
  if (isAbsolutePath(path)) return '必须是仓库内相对路径，不能是绝对路径';
  if (path.startsWith(pathSeparator) || path.endsWith(pathSeparator)) {
    return '不能以 / 开头或结尾';
  }
  if (path.contains('//')) return '不能包含连续的 /';
  for (final code in path.codeUnits) {
    if (code < 0x20 || code == 0x7f) return '不能包含控制字符';
  }
  if (_windowsInvalidCharacters.hasMatch(path)) {
    return '包含 Windows 不允许的字符 <>:"|?*';
  }
  for (final segment in path.split(pathSeparator)) {
    if (segment.isEmpty) return '不能包含空路径段';
    if (segment == '.' || segment == '..') return '不能包含 . 或 .. 路径段';
    if (segment.toLowerCase() == '.git') return '不能指向 .git';
    if (segment.endsWith('.') || segment.endsWith(' ')) {
      return '路径段不能以点或空格结尾';
    }
    if (_isWindowsReservedName(segment)) {
      return '不能使用 Windows 保留设备名 "$segment"';
    }
  }
  return null;
}

String? absolutePathError(String path) {
  if (path.isEmpty) return '路径不能为空';
  if (path.contains('\\')) return '路径必须使用 / 分隔符';
  if (!isAbsolutePath(path)) return '必须是本机绝对路径';
  if (path.contains('//') && !path.startsWith('//')) {
    return '不能包含连续的 /';
  }
  for (final code in path.codeUnits) {
    if (code < 0x20 || code == 0x7f) return '不能包含控制字符';
  }
  final normalized = stripTrailingSlashes(path);
  if ((normalized == pathSeparator && !isWindows) ||
      _driveRootPattern.hasMatch(normalized) ||
      _uncRootPattern.hasMatch(normalized)) {
    return null;
  }
  if (_drivePrefixPattern.hasMatch(normalized) &&
      !_drivePathPattern.hasMatch(normalized)) {
    return 'Windows 盘符路径必须包含 /';
  }
  final segments = normalized.split(pathSeparator);
  var start = 0;
  if (normalized.startsWith('//')) {
    final uncParts = normalized.substring(2).split(pathSeparator);
    if (uncParts.length < 2 || uncParts[0].isEmpty || uncParts[1].isEmpty) {
      return 'UNC 路径必须包含服务器和共享名';
    }
    start = 4;
  } else if (_drivePrefixPattern.hasMatch(normalized)) {
    start = 1;
  } else if (normalized.startsWith(pathSeparator)) {
    start = 1;
  }
  for (var i = start; i < segments.length; i++) {
    final segment = segments[i];
    if (segment.isEmpty) return '不能包含空路径段';
    if (segment == '.' || segment == '..') return '不能包含 . 或 .. 路径段';
    if (segment.toLowerCase() == '.git') return '不能指向 .git';
    if (segment.endsWith('.') || segment.endsWith(' ')) {
      return '路径段不能以点或空格结尾';
    }
    if (_windowsInvalidCharacters.hasMatch(segment)) {
      return '包含 Windows 不允许的字符 <>:"|?*';
    }
    if (_isWindowsReservedName(segment)) {
      return '不能使用 Windows 保留设备名 "$segment"';
    }
  }
  if (isWindows &&
      !_drivePathPattern.hasMatch(normalized) &&
      !normalized.startsWith('//')) {
    return 'Windows 绝对路径必须以盘符或 // 开头';
  }
  return null;
}

bool containsGlobCharacters(String path) => _globCharacters.hasMatch(path);

bool isDefaultExcludedPath(String relativePath) {
  if (relativePath.isEmpty) return false;
  final segments = relativePath.split(pathSeparator);
  for (final segment in segments) {
    if (segment == '.git' ||
        segment == '.dart_tool' ||
        segment == 'build' ||
        segment == '.gradle' ||
        segment == '.idea') {
      return true;
    }
  }
  final name = segments.last;
  if (name == '.env' || name.startsWith('.env.')) return true;
  if (name == 'key.properties') return true;
  if (name.endsWith('.lock')) return true;
  final lowerName = name.toLowerCase();
  for (final extension in const <String>[
    '.jks',
    '.keystore',
    '.p12',
    '.pfx',
    '.pem',
    '.key',
  ]) {
    if (lowerName.endsWith(extension)) return true;
  }
  if (relativePath == 'lib/secrets' ||
      relativePath.startsWith('lib/secrets$pathSeparator')) {
    return true;
  }
  return false;
}
