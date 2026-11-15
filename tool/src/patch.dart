/// 补丁路径检查与 fail-closed 应用。
///
/// 只依赖 Dart SDK 和 Git。每个补丁先解析文件头、校验路径安全与
/// `touches` 白名单，再依次执行 `git apply --check --binary` 和
/// `git apply --index --binary --whitespace=nowarn`；任一失败立即中止。
library;

import 'dart:convert';
import 'dart:io';

/// 执行 Git 进程的函数签名；默认使用 [Process.run]，参数始终以数组传递。
typedef PatchGitProcess =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// 补丁检查或应用失败。
class PatchException implements Exception {
  const PatchException(
    this.message, {
    this.label,
    this.patchFile,
    this.paths = const <String>[],
    this.gitOutput,
  });

  /// 面向开发者的中文错误说明。
  final String message;

  /// 补丁所属的 Loader 接缝或 Mod id。
  final String? label;

  /// 补丁文件路径。
  final String? patchFile;

  /// 与失败相关的仓库相对路径。
  final List<String> paths;

  /// 失败时 Git 的标准输出与标准错误。
  final String? gitOutput;

  @override
  String toString() {
    final buffer = StringBuffer('补丁失败');
    if (label != null && label!.isNotEmpty) {
      buffer.write('[$label]');
    }
    buffer.write('：$message');
    if (patchFile != null && patchFile!.isNotEmpty) {
      buffer.write('\n  补丁：$patchFile');
    }
    if (paths.isNotEmpty) {
      buffer.write('\n  路径：${paths.join('、')}');
    }
    if (gitOutput != null && gitOutput!.isNotEmpty) {
      buffer.write('\n  git 输出：$gitOutput');
    }
    return buffer.toString();
  }
}

/// 一个待应用的补丁及其允许修改的上游路径白名单。
class PatchSpec {
  const PatchSpec({
    required this.patchFile,
    required this.touches,
    this.label = '',
  });

  /// 补丁文件路径，可以是绝对路径或相对当前目录。
  final String patchFile;

  /// 允许修改的上游相对路径；条目同时匹配自身及其子路径。
  final List<String> touches;

  /// 用于错误信息的标签，例如 Loader 接缝名或 Mod id。
  final String label;
}

/// 补丁解析与白名单检查的结果，供 `plan` 输出使用。
class PatchInspection {
  const PatchInspection({
    required this.spec,
    required this.patchPath,
    required this.paths,
    required this.newFiles,
    required this.binary,
  });

  final PatchSpec spec;

  /// 补丁文件的绝对路径。
  final String patchPath;

  /// 补丁涉及的仓库相对路径，按出现顺序去重。
  final List<String> paths;

  /// 补丁新建的文件路径。
  final List<String> newFiles;

  /// 补丁是否包含二进制变更。
  final bool binary;
}

/// 补丁检查与应用入口。
class PatchApplier {
  PatchApplier({
    required String worktree,
    String gitExecutable = 'git',
    PatchGitProcess runProcess = _runGitProcess,
  }) : worktree = _absoluteDirectory(worktree),
       _gitExecutable = gitExecutable,
       _runProcess = runProcess {
    if (worktree.trim().isEmpty) {
      throw const PatchException('worktree 路径为空');
    }
  }

  /// 合成 worktree 的本机绝对路径。
  final String worktree;

  final String _gitExecutable;
  final PatchGitProcess _runProcess;

  /// 只解析补丁并校验路径，不写任何文件。
  PatchInspection inspect(PatchSpec spec) {
    final patchPath = _resolvePatchFile(spec);
    final bytes = File(patchPath).readAsBytesSync();
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw PatchException(
        '补丁不是有效的 UTF-8 文本',
        label: spec.label,
        patchFile: patchPath,
      );
    }

    final parsed = _parsePatch(text, spec, patchPath);
    final whitelist = _Whitelist.parse(spec, patchPath);
    for (final path in parsed.paths) {
      whitelist.check(path, spec, patchPath);
    }
    return PatchInspection(
      spec: spec,
      patchPath: patchPath,
      paths: parsed.paths,
      newFiles: parsed.newFiles,
      binary: parsed.binary,
    );
  }

  /// 按顺序检查并应用全部补丁，任一失败立即停止。
  List<PatchInspection> inspectAll(Iterable<PatchSpec> specs) {
    return <PatchInspection>[for (final spec in specs) inspect(spec)];
  }

  /// 检查并应用单个补丁。
  ///
  /// 先执行 `git apply --check --binary`，成功后执行
  /// `git apply --index --binary --whitespace=nowarn`。
  Future<PatchInspection> apply(PatchSpec spec) async {
    final inspection = inspect(spec);
    _requireWorktree(spec);

    final check = await _runProcess(_gitExecutable, <String>[
      '-c',
      'core.longpaths=true',
      '-C',
      worktree,
      'apply',
      '--check',
      '--binary',
      inspection.patchPath,
    ]);
    if (check.exitCode != 0) {
      throw PatchException(
        'git apply --check 失败，补丁与当前工作树不兼容',
        label: spec.label,
        patchFile: inspection.patchPath,
        paths: inspection.paths,
        gitOutput: _gitOutput(check),
      );
    }

    final applied = await _runProcess(_gitExecutable, <String>[
      '-c',
      'core.longpaths=true',
      '-C',
      worktree,
      'apply',
      '--index',
      '--binary',
      '--whitespace=nowarn',
      inspection.patchPath,
    ]);
    if (applied.exitCode != 0) {
      throw PatchException(
        'git apply 应用失败',
        label: spec.label,
        patchFile: inspection.patchPath,
        paths: inspection.paths,
        gitOutput: _gitOutput(applied),
      );
    }
    return inspection;
  }

  /// 按声明顺序逐个应用补丁，失败即停，不返回部分成功结果。
  Future<List<PatchInspection>> applyAll(Iterable<PatchSpec> specs) async {
    final applied = <PatchInspection>[];
    for (final spec in specs) {
      applied.add(await apply(spec));
    }
    return applied;
  }

  void _requireWorktree(PatchSpec spec) {
    final type = FileSystemEntity.typeSync(worktree, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw PatchException(
        'worktree 目录不存在',
        label: spec.label,
        patchFile: File(spec.patchFile).absolute.path,
      );
    }
    if (type == FileSystemEntityType.link) {
      throw PatchException(
        'worktree 不能是符号链接',
        label: spec.label,
        patchFile: File(spec.patchFile).absolute.path,
      );
    }
    if (type != FileSystemEntityType.directory) {
      throw PatchException(
        'worktree 不是目录',
        label: spec.label,
        patchFile: File(spec.patchFile).absolute.path,
      );
    }
  }
}

Future<ProcessResult> _runGitProcess(
  String executable,
  List<String> arguments,
) {
  return Process.run(
    executable,
    arguments,
    runInShell: false,
    stdoutEncoding: const Utf8Codec(allowMalformed: true),
    stderrEncoding: const Utf8Codec(allowMalformed: true),
  );
}

String _absoluteDirectory(String path) => Directory(path).absolute.path;

String _resolvePatchFile(PatchSpec spec) {
  if (spec.patchFile.trim().isEmpty) {
    throw PatchException('补丁路径为空', label: spec.label);
  }
  final absolute = File(spec.patchFile).absolute.path;
  final type = FileSystemEntity.typeSync(absolute, followLinks: false);
  if (type == FileSystemEntityType.notFound) {
    throw PatchException('补丁文件不存在', label: spec.label, patchFile: absolute);
  }
  if (type == FileSystemEntityType.link) {
    throw PatchException('补丁文件不能是符号链接', label: spec.label, patchFile: absolute);
  }
  if (type != FileSystemEntityType.file) {
    throw PatchException('补丁路径不是普通文件', label: spec.label, patchFile: absolute);
  }
  return absolute;
}

String _gitOutput(ProcessResult result) {
  final stdout = result.stdout.toString().trim();
  final stderr = result.stderr.toString().trim();
  return <String>[
    if (stdout.isNotEmpty) stdout,
    if (stderr.isNotEmpty) stderr,
  ].join('\n');
}

class _Section {
  final List<String> paths = <String>[];
  final Set<int> modes = <int>{};
  bool fromDiffGit = false;
  bool isNew = false;
  bool binary = false;
}

class _ParsedPatch {
  const _ParsedPatch(this.paths, this.newFiles, this.binary);

  final List<String> paths;
  final List<String> newFiles;
  final bool binary;
}

_ParsedPatch _parsePatch(String text, PatchSpec spec, String patchPath) {
  final lines = const LineSplitter().convert(text);
  final sections = <_Section>[];
  _Section? section;
  var oldRemaining = 0;
  var newRemaining = 0;
  var inHunk = false;

  void startSection({bool fromDiffGit = false}) {
    section = _Section()..fromDiffGit = fromDiffGit;
    sections.add(section!);
    inHunk = false;
  }

  void addPath(String raw) {
    final path = _normalizePatchPath(raw, spec, patchPath);
    final current = section!;
    if (!current.paths.contains(path)) {
      current.paths.add(path);
    }
  }

  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];

    if (line.startsWith('diff --git ')) {
      startSection(fromDiffGit: true);
      final header = line.substring('diff --git '.length);
      for (final path in _parseDiffGitHeader(header, spec, patchPath)) {
        addPath(path);
      }
      continue;
    }

    if (line.startsWith('@@')) {
      if (section == null) {
        throw PatchException(
          '补丁缺少文件头',
          label: spec.label,
          patchFile: patchPath,
        );
      }
      final counts = _parseHunkHeader(line, spec, patchPath);
      oldRemaining = counts.$1;
      newRemaining = counts.$2;
      inHunk = oldRemaining > 0 || newRemaining > 0;
      continue;
    }

    if (inHunk) {
      if (line.startsWith('\\')) {
        continue;
      }
      if (line.startsWith('+')) {
        newRemaining--;
      } else if (line.startsWith('-')) {
        oldRemaining--;
      } else if (line.startsWith(' ') || line.isEmpty) {
        oldRemaining--;
        newRemaining--;
      } else {
        throw PatchException(
          '无法解析补丁 hunk 行：${_preview(line)}',
          label: spec.label,
          patchFile: patchPath,
        );
      }
      if (oldRemaining <= 0 && newRemaining <= 0) {
        inHunk = false;
      }
      continue;
    }

    if (line.startsWith('--- ') &&
        index + 1 < lines.length &&
        lines[index + 1].startsWith('+++ ')) {
      if (section == null ||
          (section!.paths.isNotEmpty && !section!.fromDiffGit)) {
        startSection();
      }
      final path = _headerPath(line.substring(4), 'a/', spec, patchPath);
      if (path != null) {
        addPath(path);
      }
      continue;
    }

    if (line.startsWith('+++ ')) {
      if (section == null) {
        continue;
      }
      final path = _headerPath(line.substring(4), 'b/', spec, patchPath);
      if (path != null) {
        addPath(path);
      }
      continue;
    }

    if (section == null) {
      continue;
    }

    if (_addRenamePath(line, section!, spec, patchPath)) {
      continue;
    }

    if (line.startsWith('new file mode ')) {
      section!.modes.add(_parseMode(line.substring(14), spec, patchPath));
      section!.isNew = true;
      continue;
    }
    if (line.startsWith('deleted file mode ')) {
      section!.modes.add(_parseMode(line.substring(18), spec, patchPath));
      continue;
    }
    if (line.startsWith('old mode ') || line.startsWith('new mode ')) {
      section!.modes.add(_parseMode(line.substring(9), spec, patchPath));
      continue;
    }
    if (line.startsWith('index ')) {
      final last = line.split(' ').last;
      if (RegExp(r'^\d{6}$').hasMatch(last)) {
        section!.modes.add(int.parse(last));
      }
      continue;
    }
    if (line.startsWith('GIT binary patch')) {
      section!.binary = true;
      continue;
    }
    if (line.startsWith('Binary files ')) {
      final match = RegExp(
        r'^Binary files (.+?) and (.+?) differ$',
      ).firstMatch(line);
      if (match != null) {
        addPath(
          _stripPrefix(
            _decodePathToken(match.group(1)!, spec, patchPath),
            'a/',
          ),
        );
        addPath(
          _stripPrefix(
            _decodePathToken(match.group(2)!, spec, patchPath),
            'b/',
          ),
        );
      }
      section!.binary = true;
      continue;
    }
  }

  if (sections.isEmpty) {
    throw PatchException(
      '补丁不包含任何文件变更',
      label: spec.label,
      patchFile: patchPath,
    );
  }

  final paths = <String>[];
  final newFiles = <String>[];
  var binary = false;
  for (final current in sections) {
    if (current.paths.isEmpty) {
      throw PatchException(
        '无法解析补丁文件路径',
        label: spec.label,
        patchFile: patchPath,
      );
    }
    for (final mode in current.modes) {
      if (mode == 120000) {
        throw PatchException(
          '补丁包含符号链接变更，拒绝应用',
          label: spec.label,
          patchFile: patchPath,
          paths: current.paths,
        );
      }
      if (mode == 160000) {
        throw PatchException(
          '补丁包含 submodule 变更，拒绝应用',
          label: spec.label,
          patchFile: patchPath,
          paths: current.paths,
        );
      }
    }
    for (final path in current.paths) {
      if (!paths.contains(path)) {
        paths.add(path);
      }
      if (current.isNew && !newFiles.contains(path)) {
        newFiles.add(path);
      }
    }
    binary = binary || current.binary;
  }
  return _ParsedPatch(paths, newFiles, binary);
}

bool _addRenamePath(
  String line,
  _Section section,
  PatchSpec spec,
  String patchPath,
) {
  const prefixes = <String>[
    'rename from ',
    'rename to ',
    'copy from ',
    'copy to ',
  ];
  for (final prefix in prefixes) {
    if (line.startsWith(prefix)) {
      final path = _normalizePatchPath(
        _decodePathToken(line.substring(prefix.length), spec, patchPath),
        spec,
        patchPath,
      );
      if (!section.paths.contains(path)) {
        section.paths.add(path);
      }
      return true;
    }
  }
  return false;
}

(int, int) _parseHunkHeader(String line, PatchSpec spec, String patchPath) {
  final match = RegExp(
    r'^@@ -\d+(?:,(\d+))? \+\d+(?:,(\d+))? @@',
  ).firstMatch(line);
  if (match == null) {
    throw PatchException(
      '无法解析 hunk 头：${_preview(line)}',
      label: spec.label,
      patchFile: patchPath,
    );
  }
  return (
    int.tryParse(match.group(1) ?? '1') ?? 1,
    int.tryParse(match.group(2) ?? '1') ?? 1,
  );
}

int _parseMode(String raw, PatchSpec spec, String patchPath) {
  final mode = int.tryParse(raw.trim());
  if (mode == null) {
    throw PatchException(
      '无法解析文件模式：${_preview(raw)}',
      label: spec.label,
      patchFile: patchPath,
    );
  }
  return mode;
}

List<String> _parseDiffGitHeader(
  String rest,
  PatchSpec spec,
  String patchPath,
) {
  if (rest.startsWith('"')) {
    final first = _readQuoted(rest, 0, spec, patchPath);
    var index = first.$2;
    while (index < rest.length && rest[index] == ' ') {
      index++;
    }
    if (index >= rest.length) {
      throw PatchException(
        '无法解析 diff --git 头：${_preview(rest)}',
        label: spec.label,
        patchFile: patchPath,
      );
    }
    final second = _readToken(rest, index, spec, patchPath);
    return <String>[
      _stripPrefix(first.$1, 'a/'),
      _stripPrefix(second.$1, 'b/'),
    ];
  }

  final marker = rest.lastIndexOf(' b/');
  if (marker > 0) {
    return <String>[
      _stripPrefix(rest.substring(0, marker), 'a/'),
      _stripPrefix(rest.substring(marker + 1), 'b/'),
    ];
  }

  final parts = rest.split(' ');
  if (parts.length == 2) {
    return <String>[_stripPrefix(parts[0], 'a/'), _stripPrefix(parts[1], 'b/')];
  }
  throw PatchException(
    '无法解析 diff --git 头：${_preview(rest)}',
    label: spec.label,
    patchFile: patchPath,
  );
}

(String, int) _readToken(
  String source,
  int start,
  PatchSpec spec,
  String patchPath,
) {
  if (source[start] == '"') {
    return _readQuoted(source, start, spec, patchPath);
  }
  var end = start;
  while (end < source.length && source[end] != ' ') {
    end++;
  }
  return (source.substring(start, end), end);
}

(String, int) _readQuoted(
  String source,
  int start,
  PatchSpec spec,
  String patchPath,
) {
  const escapedBytes = <String, int>{
    'a': 7,
    'b': 8,
    't': 9,
    'n': 10,
    'v': 11,
    'f': 12,
    'r': 13,
    '"': 34,
    '\\': 92,
  };
  final bytes = <int>[];
  var index = start + 1;
  while (index < source.length) {
    final char = source[index];
    if (char == '"') {
      final String value;
      try {
        value = utf8.decode(bytes);
      } on FormatException {
        throw PatchException(
          '补丁路径不是有效的 UTF-8 文本',
          label: spec.label,
          patchFile: patchPath,
        );
      }
      return (value, index + 1);
    }
    if (char == '\\') {
      index++;
      if (index >= source.length) {
        break;
      }
      final escape = source[index];
      final mapped = escapedBytes[escape];
      if (mapped != null) {
        bytes.add(mapped);
        index++;
        continue;
      }
      final code = escape.codeUnitAt(0);
      if (code >= 0x30 && code <= 0x37) {
        var octal = '';
        var cursor = index;
        while (cursor < source.length &&
            cursor < index + 3 &&
            source.codeUnitAt(cursor) >= 0x30 &&
            source.codeUnitAt(cursor) <= 0x37) {
          octal += source[cursor];
          cursor++;
        }
        bytes.add(int.parse(octal, radix: 8));
        index = cursor;
        continue;
      }
      throw PatchException(
        '无法解析补丁路径转义：\\$escape',
        label: spec.label,
        patchFile: patchPath,
      );
    }
    bytes.addAll(utf8.encode(char));
    index++;
  }
  throw PatchException('补丁路径引号未闭合', label: spec.label, patchFile: patchPath);
}

String _decodePathToken(String raw, PatchSpec spec, String patchPath) {
  var token = raw;
  final tab = token.indexOf('\t');
  if (tab >= 0) {
    token = token.substring(0, tab);
  }
  token = token.trim();
  if (token.startsWith('"')) {
    return _readQuoted(token, 0, spec, patchPath).$1;
  }
  return token;
}

String? _headerPath(
  String raw,
  String prefix,
  PatchSpec spec,
  String patchPath,
) {
  var token = raw;
  final tab = token.indexOf('\t');
  if (tab >= 0) {
    token = token.substring(0, tab);
  }
  token = token.trim();
  if (token == '/dev/null') {
    return null;
  }
  final value = token.startsWith('"')
      ? _readQuoted(token, 0, spec, patchPath).$1
      : token;
  return _stripPrefix(value, prefix);
}

String _stripPrefix(String value, String prefix) {
  return value.startsWith(prefix) ? value.substring(prefix.length) : value;
}

String _normalizePatchPath(String raw, PatchSpec spec, String patchPath) {
  final path = raw.trim();
  if (path.isEmpty) {
    throw PatchException('补丁包含空路径', label: spec.label, patchFile: patchPath);
  }
  if (path.contains('\\')) {
    throw PatchException(
      '补丁路径包含反斜杠：$path',
      label: spec.label,
      patchFile: patchPath,
      paths: <String>[path],
    );
  }
  if (path.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(path)) {
    throw PatchException(
      '补丁路径不能是绝对路径：$path',
      label: spec.label,
      patchFile: patchPath,
      paths: <String>[path],
    );
  }
  if (path.contains(':')) {
    throw PatchException(
      '补丁路径包含冒号：$path',
      label: spec.label,
      patchFile: patchPath,
      paths: <String>[path],
    );
  }
  for (final segment in path.split('/')) {
    if (segment.isEmpty) {
      throw PatchException(
        '补丁路径包含空路径段：$path',
        label: spec.label,
        patchFile: patchPath,
        paths: <String>[path],
      );
    }
    if (segment == '.' || segment == '..') {
      throw PatchException(
        '补丁路径包含路径穿越：$path',
        label: spec.label,
        patchFile: patchPath,
        paths: <String>[path],
      );
    }
    if (segment.toLowerCase() == '.git') {
      throw PatchException(
        '补丁路径不能指向 .git：$path',
        label: spec.label,
        patchFile: patchPath,
        paths: <String>[path],
      );
    }
    if (segment.codeUnits.any((unit) => unit < 0x20)) {
      throw PatchException(
        '补丁路径包含控制字符：${_preview(path)}',
        label: spec.label,
        patchFile: patchPath,
      );
    }
  }
  return path;
}

class _Whitelist {
  const _Whitelist(this.entries);

  final List<String> entries;

  static _Whitelist parse(PatchSpec spec, String patchPath) {
    final entries = <String>[];
    for (final raw in spec.touches) {
      var touch = raw.trim();
      while (touch.endsWith('/')) {
        touch = touch.substring(0, touch.length - 1);
      }
      if (touch.isEmpty) {
        throw PatchException(
          'touches 包含空条目',
          label: spec.label,
          patchFile: patchPath,
        );
      }
      entries.add(_normalizePatchPath(touch, spec, patchPath));
    }
    return _Whitelist(entries);
  }

  bool allows(String path) {
    return entries.any((entry) => path == entry || path.startsWith('$entry/'));
  }

  void check(String path, PatchSpec spec, String patchPath) {
    if (allows(path)) {
      return;
    }
    final folded = path.toLowerCase();
    for (final entry in entries) {
      final entryFolded = entry.toLowerCase();
      if (folded == entryFolded || folded.startsWith('$entryFolded/')) {
        throw PatchException(
          '补丁路径大小写与 touches 白名单不一致：$path（白名单条目：$entry）',
          label: spec.label,
          patchFile: patchPath,
          paths: <String>[path],
        );
      }
    }
    throw PatchException(
      '补丁路径不在 touches 白名单内：$path',
      label: spec.label,
      patchFile: patchPath,
      paths: <String>[path],
    );
  }
}

String _preview(String value) {
  const limit = 60;
  final singleLine = value.replaceAll(RegExp(r'[\r\n]'), ' ');
  return singleLine.length <= limit
      ? singleLine
      : '${singleLine.substring(0, limit)}…';
}
