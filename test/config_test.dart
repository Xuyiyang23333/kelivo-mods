import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/src/config.dart';
import '../tool/src/hash.dart' as content_hash;
import '../tool/src/paths.dart';

const String _commit = '0123456789abcdef0123456789abcdef01234567';
const String _otherCommit = 'fedcba9876543210fedcba9876543210fedcba98';
const String _hashA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _hashB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const String _upstreamPath = 'V:/coding/kelivo';

String _json(Object? value) =>
    const JsonEncoder.withIndent('  ').convert(value);

Map<String, Object?> _modsJson({
  String commit = _commit,
  List<Map<String, Object?>> mods = const [],
  String upstreamPath = _upstreamPath,
}) => <String, Object?>{
  'schemaVersion': 1,
  'upstream': <String, Object?>{'path': upstreamPath, 'commit': commit},
  'mods': mods,
};

Map<String, Object?> _modJson({
  String id = 'alpha',
  String version = '1.0.0',
  String commit = _commit,
  List<String> toolNames = const ['alpha_tool'],
  Map<String, Object?>? registration = const <String, Object?>{
    'import': 'package:Kelivo/features/alpha/alpha_mod.dart',
    'className': 'AlphaMod',
  },
  List<String> touches = const [
    'lib/features/home/controllers/generation_controller.dart',
  ],
  List<String> patches = const ['patches/alpha.patch'],
  List<Map<String, Object?>> copy = const [],
  List<Map<String, Object?>>? vendored,
}) => <String, Object?>{
  'schemaVersion': 1,
  'id': id,
  'version': version,
  'upstreamCommit': commit,
  'toolNames': toolNames,
  if (registration != null) 'registration': registration,
  'touches': touches,
  'patches': patches,
  'copy': copy,
  if (vendored != null) 'vendored': vendored,
};

void _expectModsError(
  Object? json, {
  required String code,
  required String path,
}) {
  expect(
    () => ModLoaderConfig.parse(json is String ? json : _json(json)),
    throwsA(
      isA<ConfigException>()
          .having((error) => error.code, 'code', code)
          .having((error) => error.path, 'path', path),
    ),
  );
}

void _expectModError(
  Object? json, {
  required String code,
  required String path,
  String? expectedId,
}) {
  expect(
    () => ModConfig.parse(
      json is String ? json : _json(json),
      expectedId: expectedId,
    ),
    throwsA(
      isA<ConfigException>()
          .having((error) => error.code, 'code', code)
          .having((error) => error.path, 'path', path),
    ),
  );
}

void main() {
  group('paths', () {
    test('accepts repository-relative POSIX paths', () {
      expect(relativePathError('lib/features/alpha/alpha_mod.dart'), isNull);
      expect(relativePathError('mods/alpha'), isNull);
      expect(relativePathError('lib/foo[1].dart'), isNull);
    });

    test('rejects unsafe relative paths', () {
      expect(relativePathError(''), isNotNull);
      expect(relativePathError('/absolute'), isNotNull);
      expect(relativePathError('C:/absolute'), isNotNull);
      expect(relativePathError(r'lib\windows'), isNotNull);
      expect(relativePathError('lib/../escape'), isNotNull);
      expect(relativePathError('lib/./same'), isNotNull);
      expect(relativePathError('lib/.git/config'), isNotNull);
      expect(relativePathError('lib/.GIT/config'), isNotNull);
      expect(relativePathError('lib/foo.'), isNotNull);
      expect(relativePathError('lib/foo '), isNotNull);
      expect(relativePathError('lib/CON'), isNotNull);
      expect(relativePathError('lib/com1.txt'), isNotNull);
      expect(relativePathError('lib/foo:bar'), isNotNull);
      expect(relativePathError('lib//double'), isNotNull);
      expect(relativePathError('lib/trailing/'), isNotNull);
    });

    test('validates absolute upstream paths', () {
      final valid = Platform.isWindows ? 'C:/coding/kelivo' : '/coding/kelivo';
      expect(absolutePathError(valid), isNull);
      expect(absolutePathError('coding/kelivo'), isNotNull);
      expect(absolutePathError(r'C:\coding\kelivo'), isNotNull);
      expect(absolutePathError('C:/coding/../kelivo'), isNotNull);
      expect(absolutePathError('C:'), isNotNull);
      expect(absolutePathError('C:relative'), isNotNull);
      expect(absolutePathError('//server//share'), isNotNull);
      if (Platform.isWindows) {
        expect(absolutePathError('/'), isNotNull);
      }
      expect(absolutePathError('C:/coding/.git'), isNotNull);
      expect(absolutePathError('C:/coding/kelivo/'), isNull);
      expect(absolutePathError('C:/coding/kelivo '), isNotNull);
    });

    test('normalizes and compares paths', () {
      expect(stripTrailingSlashes('C:/coding/kelivo/'), 'C:/coding/kelivo');
      expect(stripTrailingSlashes('C:/'), 'C:/');
      expect(stripTrailingSlashes('/'), '/');
      expect(samePath('C:/coding/kelivo/', 'C:/coding/kelivo'), isTrue);
      expect(
        samePath('C:/coding/kelivo', 'C:/CODING/KELIVO'),
        Platform.isWindows,
      );
      expect(isWithinDirectory('C:/coding', 'C:/coding/kelivo'), isTrue);
      expect(isWithinDirectory('C:/', 'C:/coding/kelivo'), isTrue);
      expect(isWithinDirectory('C:/', 'C:/coding'), isTrue);
      expect(isWithinDirectory('C:/', 'C:/'), isFalse);
      expect(isWithinDirectory('C:/coding', 'C:/coding-other'), isFalse);
      expect(isWithinDirectory('C:/coding', 'C:/coding'), isFalse);
      expect(
        isWithinDirectory('C:/coding', 'C:/coding', allowEqual: true),
        isTrue,
      );
      expect(relativeTo('C:/coding', 'C:/coding/kelivo/lib'), 'kelivo/lib');
      expect(relativeTo('C:/', 'C:/coding'), 'coding');
      expect(relativeTo('C:/coding', 'C:/other'), isNull);
      expect(
        joinPath('C:/coding/kelivo', 'lib/foo.dart'),
        'C:/coding/kelivo/lib/foo.dart',
      );
      expect(joinPath('C:/', 'coding'), 'C:/coding');
      expect(joinPath('/', 'tmp'), '/tmp');
      expect(basename('mods/alpha/'), 'alpha');
      expect(dirname('mods/alpha/mod.json'), 'mods/alpha');
    });
  });

  group('content hash', () {
    test('matches SHA-256 test vectors', () {
      expect(
        content_hash.sha256Hex(const <int>[]),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
      expect(
        content_hash.sha256Text('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      expect(
        content_hash.sha256Text('hello'),
        '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
      );
    });

    test('hashes file lists deterministically and rejects collisions', () {
      final first = content_hash.FileHash(
        path: 'b.dart',
        sha256: _hashA,
        size: 1,
      );
      final second = content_hash.FileHash(
        path: 'a.dart',
        sha256: _hashB,
        size: 2,
      );
      expect(
        content_hash.hashFileList([first, second]),
        content_hash.hashFileList([second, first]),
      );
      expect(
        () => content_hash.hashFileList([
          content_hash.FileHash(path: 'A.dart', sha256: _hashA, size: 1),
          content_hash.FileHash(path: 'a.dart', sha256: _hashB, size: 1),
        ]),
        throwsA(isA<content_hash.HashException>()),
      );
      expect(
        () => content_hash.hashFileList([
          first,
          content_hash.FileHash(path: 'b.dart', sha256: _hashB, size: 1),
        ]),
        throwsA(isA<content_hash.HashException>()),
      );
    });

    test('hashes directories with default build and secret exclusions', () {
      final root = Directory.systemTemp.createTempSync('kelivo_hash_');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      File(joinPath(toPosixPath(root.path), 'a.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('a');
      File(joinPath(toPosixPath(root.path), 'sub/b.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('b');
      File(joinPath(toPosixPath(root.path), '.git/config'))
        ..createSync(recursive: true)
        ..writeAsStringSync('git');
      File(joinPath(toPosixPath(root.path), 'build/out.txt'))
        ..createSync(recursive: true)
        ..writeAsStringSync('out');
      File(joinPath(toPosixPath(root.path), '.env'))
        ..createSync(recursive: true)
        ..writeAsStringSync('secret');

      final files = content_hash.hashDirectory(root);
      expect(files.map((file) => file.path), ['a.dart', 'sub/b.dart']);
      final excluded = content_hash.hashDirectory(
        root,
        exclude: (path) => path.startsWith('sub/'),
      );
      expect(excluded.map((file) => file.path), ['a.dart']);
    });

    test('rejects symlinks in hashed directories', () {
      final root = Directory.systemTemp.createTempSync('kelivo_hash_link_');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      final file = File(joinPath(toPosixPath(root.path), 'a.dart'))
        ..writeAsStringSync('a');
      try {
        Link(joinPath(toPosixPath(root.path), 'link')).createSync(file.path);
      } on FileSystemException {
        return;
      }
      expect(
        () => content_hash.hashDirectory(root),
        throwsA(isA<content_hash.HashException>()),
      );
    });

    test('computes stable modset hashes and directory names', () {
      final first = content_hash.computeModsetHash(
        schemaVersion: 1,
        upstreamCommit: _commit,
        loaderVersion: '1.0.0',
        mods: const [
          content_hash.ModTreeHash(
            id: 'alpha',
            version: '1.0.0',
            treeHash: _hashA,
          ),
          content_hash.ModTreeHash(
            id: 'beta',
            version: '1.0.0',
            treeHash: _hashB,
          ),
        ],
      );
      final same = content_hash.computeModsetHash(
        schemaVersion: 1,
        upstreamCommit: _commit,
        loaderVersion: '1.0.0',
        mods: const [
          content_hash.ModTreeHash(
            id: 'alpha',
            version: '1.0.0',
            treeHash: _hashA,
          ),
          content_hash.ModTreeHash(
            id: 'beta',
            version: '1.0.0',
            treeHash: _hashB,
          ),
        ],
      );
      final reordered = content_hash.computeModsetHash(
        schemaVersion: 1,
        upstreamCommit: _commit,
        loaderVersion: '1.0.0',
        mods: const [
          content_hash.ModTreeHash(
            id: 'beta',
            version: '1.0.0',
            treeHash: _hashB,
          ),
          content_hash.ModTreeHash(
            id: 'alpha',
            version: '1.0.0',
            treeHash: _hashA,
          ),
        ],
      );
      final otherCommit = content_hash.computeModsetHash(
        schemaVersion: 1,
        upstreamCommit: _otherCommit,
        loaderVersion: '1.0.0',
        mods: const [
          content_hash.ModTreeHash(
            id: 'alpha',
            version: '1.0.0',
            treeHash: _hashA,
          ),
        ],
      );
      expect(first, same);
      expect(first, isNot(reordered));
      expect(otherCommit, isNot(first));
      expect(content_hash.modsetDirectoryName(first).length, 16);
      expect(first, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(
        () => content_hash.modsetDirectoryName('short'),
        throwsArgumentError,
      );
    });
  });

  group('mods.json', () {
    test('parses empty mod sets and preserves order', () {
      final config = ModLoaderConfig.parse(
        _json(
          _modsJson(
            mods: const [
              <String, Object?>{'path': 'mods/alpha', 'enabled': true},
              <String, Object?>{'path': 'mods/beta', 'enabled': false},
            ],
          ),
        ),
      );
      expect(config.schemaVersion, 1);
      expect(config.upstreamPath, _upstreamPath);
      expect(config.upstreamCommit, _commit);
      expect(config.mods.map((mod) => mod.path), ['mods/alpha', 'mods/beta']);
      expect(config.enabledMods.map((mod) => mod.path), ['mods/alpha']);
    });

    test('rejects unknown and missing fields', () {
      _expectModsError(
        <String, Object?>{..._modsJson(), 'extra': true},
        code: 'unknownField',
        path: r'$.extra',
      );
      final missingSchema = _modsJson()..remove('schemaVersion');
      _expectModsError(missingSchema, code: 'missingField', path: r'$');
      final missingUpstream = _modsJson()..remove('upstream');
      _expectModsError(missingUpstream, code: 'missingField', path: r'$');
    });

    test('rejects unsupported schema versions and wrong types', () {
      _expectModsError(
        <String, Object?>{..._modsJson(), 'schemaVersion': 2},
        code: 'unsupportedSchema',
        path: r'$.schemaVersion',
      );
      _expectModsError(
        <String, Object?>{..._modsJson(), 'schemaVersion': '1'},
        code: 'invalidType',
        path: r'$.schemaVersion',
      );
      _expectModsError(
        <String, Object?>{..._modsJson(), 'mods': <String, Object?>{}},
        code: 'invalidType',
        path: r'$.mods',
      );
    });

    test('rejects unsafe upstream paths and floating commits', () {
      _expectModsError(
        _modsJson(upstreamPath: 'coding/kelivo'),
        code: 'invalidPath',
        path: r'$.upstream.path',
      );
      _expectModsError(
        _modsJson(upstreamPath: r'C:\coding\kelivo'),
        code: 'invalidPath',
        path: r'$.upstream.path',
      );
      _expectModsError(
        _modsJson(upstreamPath: 'C:/coding/../kelivo'),
        code: 'invalidPath',
        path: r'$.upstream.path',
      );
      _expectModsError(
        _modsJson(commit: '73afa4e'),
        code: 'invalidCommit',
        path: r'$.upstream.commit',
      );
      _expectModsError(
        _modsJson(commit: 'master'),
        code: 'invalidCommit',
        path: r'$.upstream.commit',
      );
      _expectModsError(
        _modsJson(commit: _commit.toUpperCase()),
        code: 'invalidCommit',
        path: r'$.upstream.commit',
      );
    });

    test('rejects invalid mod entries and duplicate paths', () {
      _expectModsError(
        _modsJson(
          mods: const [
            <String, Object?>{'path': 'mods/alpha'},
          ],
        ),
        code: 'missingField',
        path: r'$.mods[0]',
      );
      _expectModsError(
        _modsJson(
          mods: const [
            <String, Object?>{'path': 'mods/alpha', 'enabled': true, 'x': 1},
          ],
        ),
        code: 'unknownField',
        path: r'$.mods[0].x',
      );
      _expectModsError(
        _modsJson(
          mods: const [
            <String, Object?>{'path': '/abs', 'enabled': true},
          ],
        ),
        code: 'invalidPath',
        path: r'$.mods[0].path',
      );
      _expectModsError(
        _modsJson(
          mods: const [
            <String, Object?>{'path': 'mods/../escape', 'enabled': true},
          ],
        ),
        code: 'invalidPath',
        path: r'$.mods[0].path',
      );
      _expectModsError(
        _modsJson(
          mods: const [
            <String, Object?>{'path': 'mods/alpha', 'enabled': true},
            <String, Object?>{'path': 'MODS/ALPHA', 'enabled': false},
          ],
        ),
        code: 'duplicate',
        path: r'$.mods[1].path',
      );
    });

    test('reports JSON syntax errors with a location', () {
      expect(
        () => ModLoaderConfig.parse('{"schemaVersion": 1,'),
        throwsA(
          isA<ConfigException>()
              .having((error) => error.code, 'code', 'invalidJson')
              .having((error) => error.path, 'path', r'$'),
        ),
      );
    });
  });

  group('mod.json', () {
    test('parses all declared fields', () {
      final config = ModConfig.parse(
        _json(
          _modJson(
            copy: const [
              <String, Object?>{
                'from': 'overlay/lib/features/alpha',
                'to': 'lib/features/alpha',
                'exclude': ['tmp'],
              },
            ],
            vendored: const [
              <String, Object?>{
                'path': 'lib/features/phone/phone_control_service.dart',
                'commit': _commit,
                'hash': _hashA,
              },
            ],
          ),
        ),
        expectedId: 'alpha',
      );
      expect(config.id, 'alpha');
      expect(config.version, '1.0.0');
      expect(config.upstreamCommit, _commit);
      expect(config.toolNames, ['alpha_tool']);
      expect(config.registration?.className, 'AlphaMod');
      expect(config.touches, [
        'lib/features/home/controllers/generation_controller.dart',
      ]);
      expect(config.patches, ['patches/alpha.patch']);
      expect(config.copy.single.from, 'overlay/lib/features/alpha');
      expect(config.copy.single.to, 'lib/features/alpha');
      expect(config.copy.single.exclude, ['tmp']);
      expect(config.vendored.single.hash, _hashA);
    });

    test('allows registration to be omitted for mods without tools', () {
      final config = ModConfig.parse(
        _json(_modJson(toolNames: const [], registration: null)),
      );
      expect(config.registration, isNull);
      expect(config.toolNames, isEmpty);
      expect(config.vendored, isEmpty);
    });

    test('rejects unknown, missing and mistyped fields', () {
      _expectModError(
        <String, Object?>{..._modJson(), 'extra': true},
        code: 'unknownField',
        path: r'$.extra',
      );
      final missing = _modJson()..remove('toolNames');
      _expectModError(missing, code: 'missingField', path: r'$');
      _expectModError(
        <String, Object?>{..._modJson(), 'schemaVersion': 2},
        code: 'unsupportedSchema',
        path: r'$.schemaVersion',
      );
      _expectModError(
        <String, Object?>{..._modJson(), 'version': 1},
        code: 'invalidType',
        path: r'$.version',
      );
    });

    test('rejects invalid ids and directory mismatches', () {
      _expectModError(
        _modJson(id: 'Alpha'),
        code: 'invalidValue',
        path: r'$.id',
      );
      _expectModError(
        _modJson(id: 'alpha-beta'),
        code: 'invalidValue',
        path: r'$.id',
      );
      _expectModError(
        _modJson(id: 'beta'),
        code: 'idMismatch',
        path: r'$.id',
        expectedId: 'alpha',
      );
    });

    test('rejects floating commits and invalid versions', () {
      _expectModError(
        _modJson(commit: 'HEAD'),
        code: 'invalidCommit',
        path: r'$.upstreamCommit',
      );
      _expectModError(
        _modJson(version: ''),
        code: 'invalidValue',
        path: r'$.version',
      );
      _expectModError(
        _modJson(version: '1.0 beta'),
        code: 'invalidValue',
        path: r'$.version',
      );
    });

    test('validates tool names and cross-mod declarations', () {
      _expectModError(
        _modJson(toolNames: const ['Alpha-Tool']),
        code: 'invalidValue',
        path: r'$.toolNames[0]',
      );
      _expectModError(
        _modJson(toolNames: const ['alpha_tool', 'alpha_tool']),
        code: 'duplicate',
        path: r'$.toolNames[1]',
      );
      _expectModError(
        _modJson(toolNames: const ['alpha_tool'], registration: null),
        code: 'missingField',
        path: r'$.registration',
      );
    });

    test('validates registration imports and class names', () {
      _expectModError(
        _modJson(
          registration: const <String, Object?>{
            'import': 'dart:async',
            'className': 'AlphaMod',
          },
        ),
        code: 'invalidValue',
        path: r'$.registration.import',
      );
      _expectModError(
        _modJson(
          registration: const <String, Object?>{
            'import': 'package:Kelivo/features/alpha/alpha_mod',
            'className': 'AlphaMod',
          },
        ),
        code: 'invalidValue',
        path: r'$.registration.import',
      );
      _expectModError(
        _modJson(
          registration: const <String, Object?>{
            'import': 'package:Kelivo/../escape.dart',
            'className': 'AlphaMod',
          },
        ),
        code: 'invalidValue',
        path: r'$.registration.import',
      );
      _expectModError(
        _modJson(
          registration: const <String, Object?>{
            'import': 'package:Kelivo/features/alpha/alpha_mod.dart',
            'className': 'Alpha-Mod',
          },
        ),
        code: 'invalidValue',
        path: r'$.registration.className',
      );
      _expectModError(
        _modJson(
          registration: const <String, Object?>{
            'import': 'package:Kelivo/features/alpha/alpha_mod.dart',
            'className': 'AlphaMod',
            'extra': true,
          },
        ),
        code: 'unknownField',
        path: r'$.registration.extra',
      );
    });

    test('validates touches, patches, copy and vendored entries', () {
      _expectModError(
        _modJson(touches: const ['../escape']),
        code: 'invalidPath',
        path: r'$.touches[0]',
      );
      _expectModError(
        _modJson(touches: const ['lib/a.dart', 'LIB/A.DART']),
        code: 'duplicate',
        path: r'$.touches[1]',
      );
      _expectModError(
        _modJson(patches: const ['patches/alpha.txt']),
        code: 'invalidPath',
        path: r'$.patches[0]',
      );
      _expectModError(
        _modJson(patches: const ['/abs/alpha.patch']),
        code: 'invalidPath',
        path: r'$.patches[0]',
      );
      _expectModError(
        _modJson(
          copy: const [
            <String, Object?>{'to': 'lib/alpha'},
          ],
        ),
        code: 'missingField',
        path: r'$.copy[0]',
      );
      _expectModError(
        _modJson(
          copy: const [
            <String, Object?>{'from': '../escape', 'to': 'lib/alpha'},
          ],
        ),
        code: 'invalidPath',
        path: r'$.copy[0].from',
      );
      _expectModError(
        _modJson(
          copy: const [
            <String, Object?>{'from': 'overlay/alpha', 'to': '/abs'},
          ],
        ),
        code: 'invalidPath',
        path: r'$.copy[0].to',
      );
      _expectModError(
        _modJson(
          copy: const [
            <String, Object?>{'from': 'overlay/a', 'to': 'lib/a'},
            <String, Object?>{'from': 'overlay/b', 'to': 'LIB/A'},
          ],
        ),
        code: 'duplicate',
        path: r'$.copy[1].to',
      );
      _expectModError(
        _modJson(
          copy: const [
            <String, Object?>{
              'from': 'overlay/a',
              'to': 'lib/a',
              'exclude': ['*.dart'],
            },
          ],
        ),
        code: 'invalidValue',
        path: r'$.copy[0].exclude[0]',
      );
      _expectModError(
        _modJson(
          vendored: const [
            <String, Object?>{
              'path': 'lib/a.dart',
              'commit': 'master',
              'hash': _hashA,
            },
          ],
        ),
        code: 'invalidCommit',
        path: r'$.vendored[0].commit',
      );
      _expectModError(
        _modJson(
          vendored: const [
            <String, Object?>{
              'path': 'lib/a.dart',
              'commit': _commit,
              'hash': 'abc',
            },
          ],
        ),
        code: 'invalidValue',
        path: r'$.vendored[0].hash',
      );
      _expectModError(
        _modJson(
          vendored: const [
            <String, Object?>{
              'path': '../a.dart',
              'commit': _commit,
              'hash': _hashA,
            },
          ],
        ),
        code: 'invalidPath',
        path: r'$.vendored[0].path',
      );
    });

    test('rejects default-excluded paths in patches, touches and copy', () {
      _expectModError(
        _modJson(touches: const ['build/generated.dart']),
        code: 'invalidPath',
        path: r'$.touches[0]',
      );
      _expectModError(
        _modJson(patches: const ['build/alpha.patch']),
        code: 'invalidPath',
        path: r'$.patches[0]',
      );
      _expectModError(
        _modJson(
          copy: const [
            <String, Object?>{'from': '.env', 'to': 'lib/alpha'},
          ],
        ),
        code: 'invalidPath',
        path: r'$.copy[0].from',
      );
      _expectModError(
        _modJson(
          copy: const [
            <String, Object?>{'from': 'overlay/a', 'to': 'lib/secrets/a'},
          ],
        ),
        code: 'invalidPath',
        path: r'$.copy[0].to',
      );
      _expectModError(
        _modJson(
          vendored: const [
            <String, Object?>{
              'path': 'lib/secrets/token.dart',
              'commit': _commit,
              'hash': _hashA,
            },
          ],
        ),
        code: 'invalidPath',
        path: r'$.vendored[0].path',
      );
    });

    test('matches touches by exact path or directory prefix', () {
      final config = ModConfig.parse(
        _json(
          _modJson(
            touches: const ['lib/features/alpha', 'lib/features/beta.dart'],
          ),
        ),
      );
      expect(config.touchesAllows('lib/features/alpha'), isTrue);
      expect(config.touchesAllows('lib/features/alpha/file.dart'), isTrue);
      expect(config.touchesAllows('lib/features/beta.dart'), isTrue);
      expect(config.touchesAllows('lib/features/beta.dart.extra'), isFalse);
      expect(
        config.touchesAllows('lib/features/alpha_other/file.dart'),
        isFalse,
      );
      expect(() => config.touchesAllows('../escape'), throwsArgumentError);
    });

    test('applies built-in copy exclusions', () {
      final spec = CopySpec(
        from: 'overlay',
        to: 'lib/alpha',
        exclude: const ['generated'],
      );
      expect(spec.isExcluded('lib/alpha.dart'), isFalse);
      expect(spec.isExcluded('generated/file.dart'), isTrue);
      expect(spec.isExcluded('generated'), isTrue);
      expect(spec.isExcluded('generated_other/file.dart'), isFalse);
      expect(spec.isExcluded('.git/config'), isTrue);
      expect(spec.isExcluded('.dart_tool/package_config.json'), isTrue);
      expect(spec.isExcluded('build/out.txt'), isTrue);
      expect(spec.isExcluded('.gradle/cache'), isTrue);
      expect(spec.isExcluded('.env'), isTrue);
      expect(spec.isExcluded('.env.local'), isTrue);
      expect(spec.isExcluded('key.properties'), isTrue);
      expect(spec.isExcluded('pubspec.lock'), isTrue);
      expect(spec.isExcluded('release.jks'), isTrue);
      expect(spec.isExcluded('lib/secrets/token.dart'), isTrue);
      expect(spec.isExcluded('lib/secrets_other/token.dart'), isFalse);
    });
  });

  group('ModSet', () {
    late _ModSetFixture fixture;

    setUp(() {
      fixture = _ModSetFixture.create();
    });

    tearDown(() {
      fixture.dispose();
    });

    test('loads enabled mods in order and computes deterministic hashes', () {
      fixture.writeModsJson(
        mods: const [
          <String, Object?>{'path': 'mods/alpha', 'enabled': true},
          <String, Object?>{'path': 'mods/beta', 'enabled': true},
        ],
      );
      fixture.writeMod(
        'alpha',
        copy: const [
          <String, Object?>{'from': 'overlay/lib/alpha', 'to': 'lib/alpha'},
        ],
      );
      fixture.writeMod(
        'beta',
        copy: const [
          <String, Object?>{'from': 'overlay/lib/beta', 'to': 'lib/beta'},
        ],
      );

      final set = ModSet.load(fixture.path);
      expect(set.mods.map((mod) => mod.id), ['alpha', 'beta']);
      final first = set.computeModsetHash(loaderVersion: '1.0.0');
      final second = ModSet.load(
        fixture.path,
      ).computeModsetHash(loaderVersion: '1.0.0');
      expect(first, second);
      expect(first, matches(RegExp(r'^[0-9a-f]{64}$')));

      fixture.writeCopyFile('alpha', 'overlay/lib/alpha/file.dart', 'changed');
      final changed = ModSet.load(
        fixture.path,
      ).computeModsetHash(loaderVersion: '1.0.0');
      expect(changed, isNot(first));
    });

    test('hash changes with mod order, patch content and baseline', () {
      fixture.writeModsJson(
        mods: const [
          <String, Object?>{'path': 'mods/alpha', 'enabled': true},
          <String, Object?>{'path': 'mods/beta', 'enabled': true},
        ],
      );
      fixture.writeMod('alpha');
      fixture.writeMod('beta');
      final first = ModSet.load(
        fixture.path,
      ).computeModsetHash(loaderVersion: '1.0.0');

      fixture.writeModsJson(
        mods: const [
          <String, Object?>{'path': 'mods/beta', 'enabled': true},
          <String, Object?>{'path': 'mods/alpha', 'enabled': true},
        ],
      );
      final reordered = ModSet.load(
        fixture.path,
      ).computeModsetHash(loaderVersion: '1.0.0');
      expect(reordered, isNot(first));

      fixture.writeModsJson(
        mods: const [
          <String, Object?>{'path': 'mods/alpha', 'enabled': true},
          <String, Object?>{'path': 'mods/beta', 'enabled': true},
        ],
      );
      fixture.writePatch('alpha', 'changed patch');
      final patchChanged = ModSet.load(
        fixture.path,
      ).computeModsetHash(loaderVersion: '1.0.0');
      expect(patchChanged, isNot(first));

      fixture.writeModsJson(
        commit: _otherCommit,
        mods: const [
          <String, Object?>{'path': 'mods/alpha', 'enabled': true},
          <String, Object?>{'path': 'mods/beta', 'enabled': true},
        ],
      );
      fixture.writeMod('alpha', commit: _otherCommit);
      fixture.writeMod('beta', commit: _otherCommit);
      final baselineChanged = ModSet.load(
        fixture.path,
      ).computeModsetHash(loaderVersion: '1.0.0');
      expect(baselineChanged, isNot(first));
    });

    test('ignores README and excluded copy files in the hash', () {
      fixture.writeModsJson(
        mods: const [
          <String, Object?>{'path': 'mods/alpha', 'enabled': true},
        ],
      );
      fixture.writeMod(
        'alpha',
        copy: const [
          <String, Object?>{'from': 'overlay/lib/alpha', 'to': 'lib/alpha'},
        ],
      );
      final first = ModSet.load(
        fixture.path,
      ).computeModsetHash(loaderVersion: '1.0.0');

      fixture.writeModFile('alpha', 'README.md', 'documentation');
      fixture.writeCopyFile('alpha', 'overlay/lib/alpha/.env', 'secret');
      fixture.writeCopyFile('alpha', 'overlay/lib/alpha/build/out.txt', 'out');
      final second = ModSet.load(
        fixture.path,
      ).computeModsetHash(loaderVersion: '1.0.0');
      expect(second, first);
    });

    test('skips disabled mods even when their directories are missing', () {
      fixture.writeModsJson(
        mods: const [
          <String, Object?>{'path': 'mods/alpha', 'enabled': true},
          <String, Object?>{'path': 'mods/missing', 'enabled': false},
        ],
      );
      fixture.writeMod('alpha');
      final set = ModSet.load(fixture.path);
      expect(set.mods.map((mod) => mod.id), ['alpha']);
    });

    test('rejects baseline mismatches', () {
      fixture.writeModsJson(
        mods: const [
          <String, Object?>{'path': 'mods/alpha', 'enabled': true},
        ],
      );
      fixture.writeMod('alpha', commit: _otherCommit);
      expect(
        () => ModSet.load(fixture.path),
        throwsA(
          isA<ConfigException>().having(
            (error) => error.code,
            'code',
            'upstreamCommitMismatch',
          ),
        ),
      );
    });

    test('rejects duplicate tool names across mods', () {
      fixture.writeModsJson(
        mods: const [
          <String, Object?>{'path': 'mods/alpha', 'enabled': true},
          <String, Object?>{'path': 'mods/beta', 'enabled': true},
        ],
      );
      fixture.writeMod('alpha', toolNames: const ['shared_tool']);
      fixture.writeMod('beta', toolNames: const ['shared_tool']);
      expect(
        () => ModSet.load(fixture.path),
        throwsA(
          isA<ConfigException>().having(
            (error) => error.code,
            'code',
            'duplicateToolName',
          ),
        ),
      );
    });

    test('rejects duplicate and nested copy targets across mods', () {
      fixture.writeModsJson(
        mods: const [
          <String, Object?>{'path': 'mods/alpha', 'enabled': true},
          <String, Object?>{'path': 'mods/beta', 'enabled': true},
        ],
      );
      fixture.writeMod(
        'alpha',
        copy: const [
          <String, Object?>{'from': 'overlay/a', 'to': 'lib/shared'},
        ],
      );
      fixture.writeMod(
        'beta',
        copy: const [
          <String, Object?>{'from': 'overlay/b', 'to': 'lib/shared/file.dart'},
        ],
      );
      expect(
        () => ModSet.load(fixture.path),
        throwsA(
          isA<ConfigException>().having(
            (error) => error.code,
            'code',
            'duplicateCopyTarget',
          ),
        ),
      );
    });

    test('rejects missing mod directories, patches and copy sources', () {
      fixture.writeModsJson(
        mods: const [
          <String, Object?>{'path': 'mods/missing', 'enabled': true},
        ],
      );
      expect(
        () => ModSet.load(fixture.path),
        throwsA(
          isA<ConfigException>().having(
            (error) => error.code,
            'code',
            'missingDirectory',
          ),
        ),
      );

      fixture.writeModsJson(
        mods: const [
          <String, Object?>{'path': 'mods/alpha', 'enabled': true},
        ],
      );
      fixture.writeMod('alpha', createPatch: false);
      expect(
        () => ModSet.load(fixture.path),
        throwsA(
          isA<ConfigException>().having(
            (error) => error.code,
            'code',
            'missingFile',
          ),
        ),
      );

      fixture.writeMod(
        'alpha',
        copy: const [
          <String, Object?>{'from': 'overlay/missing', 'to': 'lib/alpha'},
        ],
        createCopy: false,
      );
      expect(
        () => ModSet.load(fixture.path),
        throwsA(
          isA<ConfigException>().having(
            (error) => error.code,
            'code',
            'missingCopySource',
          ),
        ),
      );
    });

    test('can skip file existence checks for plan-only use', () {
      fixture.writeModsJson(
        mods: const [
          <String, Object?>{'path': 'mods/alpha', 'enabled': true},
        ],
      );
      fixture.writeMod(
        'alpha',
        createPatch: false,
        copy: const [
          <String, Object?>{'from': 'overlay/missing', 'to': 'lib/alpha'},
        ],
        createCopy: false,
      );
      final set = ModSet.load(fixture.path, validateFiles: false);
      expect(set.mods.single.id, 'alpha');
    });

    test('rejects relative private repo roots', () {
      expect(
        () => ModSet.load('relative/path'),
        throwsA(
          isA<ConfigException>().having(
            (error) => error.code,
            'code',
            'invalidPath',
          ),
        ),
      );
    });
  });
}

class _ModSetFixture {
  _ModSetFixture(this.root);

  final Directory root;

  String get path => toPosixPath(root.path);

  static _ModSetFixture create() => _ModSetFixture(
    Directory.systemTemp.createTempSync('kelivo_loader_config_'),
  );

  void dispose() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  }

  void writeModsJson({
    List<Map<String, Object?>> mods = const [],
    String commit = _commit,
  }) {
    _writeJson(
      File(joinPath(path, 'mods.json')),
      _modsJson(commit: commit, mods: mods),
    );
  }

  void writeMod(
    String id, {
    String? modId,
    String commit = _commit,
    List<String>? toolNames,
    List<String> patches = const [],
    List<Map<String, Object?>> copy = const [],
    bool createPatch = true,
    bool createCopy = true,
  }) {
    final directory = joinPath(path, 'mods/$id');
    Directory(directory).createSync(recursive: true);
    final resolvedPatches = patches.isEmpty ? ['patches/$id.patch'] : patches;
    _writeJson(
      File(joinPath(directory, 'mod.json')),
      _modJson(
        id: modId ?? id,
        commit: commit,
        toolNames: toolNames ?? ['${id}_tool'],
        patches: resolvedPatches,
        copy: copy,
      ),
    );
    if (createPatch) {
      for (final patch in resolvedPatches) {
        final file = File(joinPath(directory, patch));
        file.parent.createSync(recursive: true);
        file.writeAsStringSync('diff --git a/file b/file\n');
      }
    }
    if (createCopy) {
      for (final spec in copy) {
        final from = spec['from']! as String;
        final source = joinPath(directory, from);
        if (from.endsWith('.dart') || from.endsWith('.txt')) {
          File(source)
            ..createSync(recursive: true)
            ..writeAsStringSync('source');
        } else {
          Directory(source).createSync(recursive: true);
          File(joinPath(source, 'file.dart')).writeAsStringSync('source');
        }
      }
    }
  }

  void writePatch(String id, String content) {
    File(
      joinPath(path, 'mods/$id/patches/$id.patch'),
    ).writeAsStringSync(content);
  }

  void writeModFile(String id, String relativePath, String content) {
    final file = File(joinPath(path, 'mods/$id/$relativePath'));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  void writeCopyFile(String id, String relativePath, String content) {
    final file = File(joinPath(path, 'mods/$id/$relativePath'));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }
}

void _writeJson(File file, Object? value) {
  file.parent.createSync(recursive: true);
  file.writeAsStringSync('${_json(value)}\n');
}
