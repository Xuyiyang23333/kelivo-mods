import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/src/build_artifacts.dart';
import '../tool/src/git.dart';
import '../tool/src/paths.dart';
import '../tool/src/worktree.dart';

const String _hashA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _hashB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  late _GitFixture fixture;
  late WorktreeManager manager;

  setUp(() async {
    fixture = await _GitFixture.create();
    manager = WorktreeManager(
      privateRepoRoot: fixture.privateRepoPath,
      upstreamPath: fixture.upstreamPath,
      upstreamCommit: fixture.commit,
    );
  });

  tearDown(() async {
    await fixture.dispose();
  });

  group('createOrReuse', () {
    test('creates a detached worktree at the pinned commit', () async {
      final handle = await manager.createOrReuse(
        modsetHash: _hashA,
        synthesize: (_) async {},
      );
      expect(handle.reused, isFalse);
      expect(handle.path, manager.worktreePathFor(_hashA));
      expect(Directory(handle.path).existsSync(), isTrue);
      expect(
        await Git(workingDirectory: handle.path).headCommit(),
        fixture.commit,
      );
      expect(
        File(joinPath(handle.path, 'README.md')).readAsStringSync(),
        'hello\n',
      );

      final stateFile = File('${handle.path}.state.json');
      expect(stateFile.existsSync(), isTrue);
      final state = jsonDecode(stateFile.readAsStringSync()) as Map;
      expect(state['status'], 'ready');
      expect(state['modsetHash'], _hashA);
      expect(
        state['worktreePath'],
        '.build/worktrees/${_hashA.substring(0, 16)}',
      );
    });

    test(
      'creates LF worktree content when repository autocrlf is true',
      () async {
        final shell =
            File(joinPath(fixture.upstreamPath, 'tool/fetch_proot.sh'))
              ..createSync(recursive: true)
              ..writeAsStringSync('#!/usr/bin/env bash\necho ok\n');
        final checksums = File(
          joinPath(fixture.upstreamPath, 'tool/proot_checksums.txt'),
        )..writeAsStringSync('abc123  file.tar.xz\n');
        await _runGit(fixture.upstreamPath, <String>[
          'config',
          'core.autocrlf',
          'true',
        ]);
        await _runGit(fixture.upstreamPath, <String>['add', '-A']);
        await _runGit(fixture.upstreamPath, <String>[
          '-c',
          'user.email=test@example.com',
          '-c',
          'user.name=Kelivo Test',
          'commit',
          '-m',
          'lf scripts',
        ]);
        final newCommit = (await _runGit(fixture.upstreamPath, <String>[
          'rev-parse',
          'HEAD',
        ])).trim();
        final lfManager = WorktreeManager(
          privateRepoRoot: fixture.privateRepoPath,
          upstreamPath: fixture.upstreamPath,
          upstreamCommit: newCommit,
        );

        final handle = await lfManager.createOrReuse(
          modsetHash: _hashA,
          synthesize: (_) async {},
        );

        final shellBytes = File(
          joinPath(handle.path, 'tool/fetch_proot.sh'),
        ).readAsBytesSync();
        final checksumBytes = File(
          joinPath(handle.path, 'tool/proot_checksums.txt'),
        ).readAsBytesSync();
        expect(shellBytes.contains(0x0d), isFalse);
        expect(checksumBytes.contains(0x0d), isFalse);
        expect(shellBytes, shell.readAsBytesSync());
        expect(checksumBytes, checksums.readAsBytesSync());
      },
    );

    test('runs synthesis before marking the worktree ready', () async {
      var calls = 0;
      final handle = await manager.createOrReuse(
        modsetHash: _hashA,
        synthesize: (handle) async {
          calls++;
          File(
            joinPath(handle.path, 'synthesized.txt'),
          ).writeAsStringSync('ok');
        },
      );
      expect(calls, 1);
      expect(
        File(joinPath(handle.path, 'synthesized.txt')).readAsStringSync(),
        'ok',
      );
    });

    test('reuses a ready worktree without rerunning synthesis', () async {
      final first = await manager.createOrReuse(
        modsetHash: _hashA,
        synthesize: (_) async {},
      );
      var calls = 0;
      final second = await manager.createOrReuse(
        modsetHash: _hashA,
        synthesize: (_) async {
          calls++;
        },
      );
      expect(second.reused, isTrue);
      expect(second.path, first.path);
      expect(calls, 0);
      final entries = await Git(
        workingDirectory: fixture.upstreamPath,
      ).worktreeList();
      expect(
        entries.where((entry) => samePath(entry.path, first.path)).length,
        1,
      );
    });

    test('creates distinct directories for distinct modset hashes', () async {
      final first = await manager.createOrReuse(
        modsetHash: _hashA,
        synthesize: (_) async {},
      );
      final second = await manager.createOrReuse(
        modsetHash: _hashB,
        synthesize: (_) async {},
      );
      expect(first.path, isNot(second.path));
      expect(Directory(first.path).existsSync(), isTrue);
      expect(Directory(second.path).existsSync(), isTrue);
    });

    test('rejects a dirty upstream tracked file', () async {
      File(
        joinPath(fixture.upstreamPath, 'README.md'),
      ).writeAsStringSync('dirty\n');
      await expectLater(
        manager.createOrReuse(modsetHash: _hashA, synthesize: (_) async {}),
        throwsA(isA<UpstreamDirtyException>()),
      );
      expect(Directory(manager.worktreePathFor(_hashA)).existsSync(), isFalse);
    });

    test('allows untracked upstream files', () async {
      File(
        joinPath(fixture.upstreamPath, 'scratch.txt'),
      ).writeAsStringSync('scratch');
      final handle = await manager.createOrReuse(
        modsetHash: _hashA,
        synthesize: (_) async {},
      );
      expect(handle.reused, isFalse);
    });

    test('rejects a missing pinned commit', () async {
      final bad = WorktreeManager(
        privateRepoRoot: fixture.privateRepoPath,
        upstreamPath: fixture.upstreamPath,
        upstreamCommit: '0' * 40,
      );
      await expectLater(
        bad.createOrReuse(modsetHash: _hashA, synthesize: (_) async {}),
        throwsA(isA<UpstreamException>()),
      );
    });

    test('rejects short commits in the constructor', () {
      expect(
        () => WorktreeManager(
          privateRepoRoot: fixture.privateRepoPath,
          upstreamPath: fixture.upstreamPath,
          upstreamCommit: fixture.commit.substring(0, 12),
        ),
        throwsArgumentError,
      );
    });

    test('rejects a non-repository upstream path', () async {
      final notRepository = Directory(joinPath(fixture.rootPath, 'not-repo'))
        ..createSync(recursive: true);
      final bad = WorktreeManager(
        privateRepoRoot: fixture.privateRepoPath,
        upstreamPath: toPosixPath(notRepository.path),
        upstreamCommit: fixture.commit,
      );
      await expectLater(
        bad.createOrReuse(modsetHash: _hashA, synthesize: (_) async {}),
        throwsA(isA<UpstreamException>()),
      );
    });

    test(
      'rejects an upstream subdirectory instead of the repository root',
      () async {
        final subdirectory = Directory(joinPath(fixture.upstreamPath, 'sub'))
          ..createSync(recursive: true);
        final bad = WorktreeManager(
          privateRepoRoot: fixture.privateRepoPath,
          upstreamPath: toPosixPath(subdirectory.path),
          upstreamCommit: fixture.commit,
        );
        await expectLater(
          bad.createOrReuse(modsetHash: _hashA, synthesize: (_) async {}),
          throwsA(isA<UpstreamException>()),
        );
      },
    );

    test('rejects a private repo inside the upstream repository', () {
      expect(
        () => WorktreeManager(
          privateRepoRoot: joinPath(fixture.upstreamPath, 'private'),
          upstreamPath: fixture.upstreamPath,
          upstreamCommit: fixture.commit,
        ),
        throwsArgumentError,
      );
    });

    test('rejects tracked drift on reuse', () async {
      final handle = await manager.createOrReuse(
        modsetHash: _hashA,
        synthesize: (_) async {},
      );
      File(joinPath(handle.path, 'lib/keep.txt')).writeAsStringSync('drift\n');
      await expectLater(
        manager.createOrReuse(modsetHash: _hashA, synthesize: (_) async {}),
        throwsA(isA<WorktreeStateException>()),
      );
    });

    test('allows pubspec.lock changes on reuse', () async {
      final handle = await manager.createOrReuse(
        modsetHash: _hashA,
        synthesize: (_) async {},
      );
      File(
        joinPath(handle.path, 'pubspec.lock'),
      ).writeAsStringSync('generated\n');
      final reused = await manager.createOrReuse(
        modsetHash: _hashA,
        synthesize: (_) async {},
      );
      expect(reused.reused, isTrue);
    });

    test('allows Flutter generated registrant changes on reuse', () async {
      final handle = await manager.createOrReuse(
        modsetHash: _hashA,
        synthesize: (_) async {},
      );
      for (final path in flutterGeneratedBuildArtifacts) {
        File(
          joinPath(handle.path, path),
        ).writeAsStringSync('changed by flutter\n');
      }
      File(
        joinPath(handle.path, 'pubspec.lock'),
      ).writeAsStringSync('changed by flutter\n');

      final reused = await manager.createOrReuse(
        modsetHash: _hashA,
        synthesize: (_) async {},
      );
      expect(reused.reused, isTrue);
      final verification = await manager.verify(modsetHash: _hashA);
      expect(
        verification.isValid,
        isTrue,
        reason: verification.issues.join('\n'),
      );
    });

    test('can reuse with expected tracked changes', () async {
      final handle = await manager.createOrReuse(
        modsetHash: _hashA,
        synthesize: (_) async {},
      );
      File(
        joinPath(handle.path, 'lib/keep.txt'),
      ).writeAsStringSync('expected patch\n');
      final reused = await manager.createOrReuse(
        modsetHash: _hashA,
        synthesize: (_) async {},
        allowTrackedChanges: true,
      );
      expect(reused.reused, isTrue);
      final verification = await manager.verify(
        modsetHash: _hashA,
        allowTrackedChanges: true,
      );
      expect(
        verification.isValid,
        isTrue,
        reason: verification.issues.join('\n'),
      );
    });

    test('refuses an existing directory without a state record', () async {
      Directory(manager.worktreePathFor(_hashA)).createSync(recursive: true);
      await expectLater(
        manager.createOrReuse(modsetHash: _hashA, synthesize: (_) async {}),
        throwsA(isA<WorktreeStateException>()),
      );
    });

    test('refuses a non-directory target', () async {
      File(manager.worktreePathFor(_hashA)).createSync(recursive: true);
      await expectLater(
        manager.createOrReuse(modsetHash: _hashA, synthesize: (_) async {}),
        throwsA(isA<WorktreeStateException>()),
      );
    });

    test('a failed add that leaves nothing behind heals on retry', () async {
      final failing = WorktreeManager(
        privateRepoRoot: fixture.privateRepoPath,
        upstreamPath: fixture.upstreamPath,
        upstreamCommit: fixture.commit,
        git: _FailingGit(workingDirectory: fixture.upstreamPath),
      );
      await expectLater(
        failing.createOrReuse(modsetHash: _hashA, synthesize: (_) async {}),
        throwsA(
          isA<WorktreeCreationException>().having(
            (error) => error.toString(),
            'message',
            isNot(contains('clean --modset')),
          ),
        ),
      );
      final stateFile = File('${failing.worktreePathFor(_hashA)}.state.json');
      expect(stateFile.existsSync(), isFalse);

      final handle = await manager.createOrReuse(
        modsetHash: _hashA,
        synthesize: (_) async {},
      );
      expect(handle.reused, isFalse);
    });

    test('keeps a failed record when the target directory exists', () async {
      final failing = WorktreeManager(
        privateRepoRoot: fixture.privateRepoPath,
        upstreamPath: fixture.upstreamPath,
        upstreamCommit: fixture.commit,
        git: _PartialAddGit(workingDirectory: fixture.upstreamPath),
      );
      await expectLater(
        failing.createOrReuse(modsetHash: _hashA, synthesize: (_) async {}),
        throwsA(
          isA<WorktreeCreationException>().having(
            (error) => error.toString(),
            'message',
            contains('clean --modset $_hashA'),
          ),
        ),
      );
      final stateFile = File('${failing.worktreePathFor(_hashA)}.state.json');
      expect(stateFile.existsSync(), isTrue);
      final state = jsonDecode(stateFile.readAsStringSync()) as Map;
      expect(state['status'], 'failed');

      await expectLater(
        manager.createOrReuse(modsetHash: _hashA, synthesize: (_) async {}),
        throwsA(isA<WorktreeStateException>()),
      );
      final result = await manager.clean(modsetHash: _hashA);
      expect(result.removedState, isTrue);
      final handle = await manager.createOrReuse(
        modsetHash: _hashA,
        synthesize: (_) async {},
      );
      expect(handle.reused, isFalse);
    });

    test('keeps a failed record when Git still registers the path', () async {
      final failing = WorktreeManager(
        privateRepoRoot: fixture.privateRepoPath,
        upstreamPath: fixture.upstreamPath,
        upstreamCommit: fixture.commit,
        git: _RegisteredWithoutDirectoryGit(
          workingDirectory: fixture.upstreamPath,
          pendingPath: manager.worktreePathFor(_hashA),
        ),
      );
      await expectLater(
        failing.createOrReuse(modsetHash: _hashA, synthesize: (_) async {}),
        throwsA(
          isA<WorktreeCreationException>().having(
            (error) => error.toString(),
            'message',
            contains('clean --modset $_hashA'),
          ),
        ),
      );
      final stateFile = File('${failing.worktreePathFor(_hashA)}.state.json');
      expect(stateFile.existsSync(), isTrue);
      expect(
        (jsonDecode(stateFile.readAsStringSync()) as Map)['status'],
        'failed',
      );
      expect(
        Directory(failing.worktreePathFor(_hashA)).existsSync(),
        isFalse,
        reason: '该分支模拟“已登记但目录不存在”，目录本身必须不残留',
      );
    });

    test('keeps a failed record when listing worktrees fails', () async {
      final failing = WorktreeManager(
        privateRepoRoot: fixture.privateRepoPath,
        upstreamPath: fixture.upstreamPath,
        upstreamCommit: fixture.commit,
        git: _UnlistableGit(workingDirectory: fixture.upstreamPath),
      );
      await expectLater(
        failing.createOrReuse(modsetHash: _hashA, synthesize: (_) async {}),
        throwsA(
          isA<WorktreeCreationException>().having(
            (error) => error.toString(),
            'message',
            contains('clean --modset $_hashA'),
          ),
        ),
      );
      final stateFile = File('${failing.worktreePathFor(_hashA)}.state.json');
      expect(stateFile.existsSync(), isTrue);
      expect(
        (jsonDecode(stateFile.readAsStringSync()) as Map)['status'],
        'failed',
      );
    });

    test('refuses a non-directory worktrees root', () async {
      File(manager.worktreesRoot).createSync(recursive: true);
      await expectLater(
        manager.createOrReuse(modsetHash: _hashA, synthesize: (_) async {}),
        throwsA(isA<WorktreeStateException>()),
      );
      await expectLater(
        manager.clean(modsetHash: _hashA),
        throwsA(isA<WorktreeCleanException>()),
      );
    });

    test('rejects malformed modset hashes', () async {
      await expectLater(
        manager.createOrReuse(modsetHash: 'short', synthesize: (_) async {}),
        throwsArgumentError,
      );
      expect(() => manager.worktreePathFor('short'), throwsArgumentError);
    });
  });

  group('verify', () {
    test('accepts a ready worktree', () async {
      await manager.createOrReuse(modsetHash: _hashA, synthesize: (_) async {});
      final verification = await manager.verify(modsetHash: _hashA);
      expect(
        verification.isValid,
        isTrue,
        reason: verification.issues.join('\n'),
      );
      expect(verification.headCommit, fixture.commit);
    });

    test('reports a missing worktree', () async {
      final verification = await manager.verify(modsetHash: _hashB);
      expect(verification.isValid, isFalse);
      expect(verification.issues, isNotEmpty);
    });

    test('reports tracked drift', () async {
      final handle = await manager.createOrReuse(
        modsetHash: _hashA,
        synthesize: (_) async {},
      );
      File(joinPath(handle.path, 'lib/keep.txt')).writeAsStringSync('drift\n');
      final verification = await manager.verify(modsetHash: _hashA);
      expect(verification.isValid, isFalse);
      expect(
        verification.issues.any((issue) => issue.contains('lib/keep.txt')),
        isTrue,
      );
    });

    test('reports a HEAD that differs from the pinned commit', () async {
      final handle = await manager.createOrReuse(
        modsetHash: _hashA,
        synthesize: (_) async {},
      );
      final secondCommit = await fixture.createSecondCommit();
      await _runGit(handle.path, ['checkout', '--detach', secondCommit]);
      final verification = await manager.verify(modsetHash: _hashA);
      expect(verification.isValid, isFalse);
      expect(
        verification.issues.any((issue) => issue.contains('HEAD')),
        isTrue,
      );
    });

    test('verifyOrThrow throws a verification exception', () async {
      await expectLater(
        manager.verifyOrThrow(modsetHash: _hashB),
        throwsA(isA<WorktreeVerificationException>()),
      );
    });
  });

  group('long paths', () {
    test('every git process carries core.longpaths=true', () async {
      final git = Git(workingDirectory: fixture.upstreamPath);
      final result = await git.run(<String>['--version']);
      expect(result.succeeded, isTrue, reason: result.stderr);
      expect(result.args.take(2), <String>['-c', 'core.longpaths=true']);
      expect(result.commandLine, contains('core.longpaths=true'));
    });

    test('worktree add keeps the autocrlf and longpaths flags', () async {
      final recorded = _RecordingGit(workingDirectory: fixture.upstreamPath);
      final recording = WorktreeManager(
        privateRepoRoot: fixture.privateRepoPath,
        upstreamPath: fixture.upstreamPath,
        upstreamCommit: fixture.commit,
        git: recorded,
      );
      await recording.createOrReuse(
        modsetHash: _hashB,
        synthesize: (_) async {},
      );

      final add = recorded.calls.firstWhere(
        (args) => args.contains('add'),
        orElse: () =>
            throw StateError('missing worktree add call: ${recorded.calls}'),
      );
      expect(add.take(4).toList(), <String>[
        '-c',
        'core.longpaths=true',
        '-c',
        'core.autocrlf=false',
      ]);
    });

    test(
      'explains a Filename too long failure instead of a bare reset error',
      () {
        final message = worktreeAddFailureMessage(
          const GitResult(
            args: <String>[
              '-c',
              'core.longpaths=true',
              '-c',
              'core.autocrlf=false',
              'worktree',
              'add',
              '--detach',
              'V:/repo/.build/worktrees/abc',
              '73afa4ec77cfc9af2efea2487fee8bba1362639d',
            ],
            workingDirectory: 'V:/upstream',
            exitCode: 128,
            stdout: '',
            stderr:
                'Preparing worktree (detached HEAD 73afa4e)\n'
                'error: unable to create file dependencies/.../Long.java: '
                'Filename too long\n'
                "fatal: Could not reset index file to revision 'HEAD'.",
          ),
        );
        expect(message, contains('Filename too long'));
        expect(message, contains('core.longpaths=true'));
        expect(message, contains('更短的绝对路径'));
        expect(message, contains('不能修复 Git'));
        expect(message, contains('不是上游仓库损坏'));
        expect(message, isNot(contains('Could not reset index')));
      },
    );

    test('keeps a generic message for unrelated worktree add failures', () {
      final message = worktreeAddFailureMessage(
        const GitResult(
          args: <String>['worktree', 'add'],
          workingDirectory: 'V:/upstream',
          exitCode: 128,
          stdout: '',
          stderr: 'fatal: invalid reference: 73afa4e',
        ),
      );
      expect(message, 'worktree add 失败（退出码 128）');
    });
  });

  group('trackedChanges', () {
    test('ignores CRLF-only rewrites when core.autocrlf is true', () async {
      final handle = await manager.createOrReuse(
        modsetHash: _hashA,
        synthesize: (_) async {},
      );
      await _runGit(fixture.upstreamPath, <String>[
        'config',
        'core.autocrlf',
        'true',
      ]);
      File(joinPath(handle.path, 'lib/keep.txt')).writeAsStringSync('keep\r\n');

      final status = await _runGit(handle.path, <String>[
        'status',
        '--porcelain',
        '--untracked-files=no',
      ]);
      expect(status, contains('lib/keep.txt'));

      final changes = await Git(workingDirectory: handle.path).trackedChanges();
      expect(changes, isEmpty);
      final verification = await manager.verify(modsetHash: _hashA);
      expect(
        verification.isValid,
        isTrue,
        reason: verification.issues.join('\n'),
      );
      final reused = await manager.createOrReuse(
        modsetHash: _hashA,
        synthesize: (_) async {},
      );
      expect(reused.reused, isTrue);
    });

    test('reports real content changes when core.autocrlf is true', () async {
      final handle = await manager.createOrReuse(
        modsetHash: _hashA,
        synthesize: (_) async {},
      );
      await _runGit(fixture.upstreamPath, <String>[
        'config',
        'core.autocrlf',
        'true',
      ]);
      File(
        joinPath(handle.path, 'lib/keep.txt'),
      ).writeAsStringSync('changed\r\n');

      final changes = await Git(workingDirectory: handle.path).trackedChanges();
      expect(changes, hasLength(1));
      expect(changes.single.path, 'lib/keep.txt');
      expect(changes.single.status, ' M');
      final verification = await manager.verify(modsetHash: _hashA);
      expect(verification.isValid, isFalse);
      expect(
        verification.issues.any((issue) => issue.contains('lib/keep.txt')),
        isTrue,
      );
    });

    test('reports staged modifications and deletions', () async {
      final handle = await manager.createOrReuse(
        modsetHash: _hashA,
        synthesize: (_) async {},
      );
      File(joinPath(handle.path, 'lib/keep.txt')).writeAsStringSync('staged\n');
      File(joinPath(handle.path, 'README.md')).deleteSync();
      await _runGit(handle.path, <String>['add', '-A']);

      final changes = await Git(workingDirectory: handle.path).trackedChanges();
      expect(
        changes.map((change) => '${change.status}:${change.path}'),
        containsAll(<String>['M :lib/keep.txt', 'D :README.md']),
      );
      final verification = await manager.verify(modsetHash: _hashA);
      expect(verification.isValid, isFalse);
    });

    test('reports unstaged deletions', () async {
      final handle = await manager.createOrReuse(
        modsetHash: _hashA,
        synthesize: (_) async {},
      );
      File(joinPath(handle.path, 'README.md')).deleteSync();

      final changes = await Git(workingDirectory: handle.path).trackedChanges();
      expect(changes.single.path, 'README.md');
      expect(changes.single.status, ' D');
    });

    test('reports staged renames', () async {
      final handle = await manager.createOrReuse(
        modsetHash: _hashA,
        synthesize: (_) async {},
      );
      await _runGit(handle.path, <String>[
        'mv',
        'lib/keep.txt',
        'lib/renamed.txt',
      ]);

      final changes = await Git(workingDirectory: handle.path).trackedChanges();
      expect(changes.single.path, 'lib/renamed.txt');
      expect(changes.single.status, 'R ');
      expect(changes.single.isRenameOrCopy, isTrue);
      final verification = await manager.verify(modsetHash: _hashA);
      expect(verification.isValid, isFalse);
    });
  });

  group('clean', () {
    test('removes the worktree and its state record', () async {
      final handle = await manager.createOrReuse(
        modsetHash: _hashA,
        synthesize: (_) async {},
      );
      final result = await manager.clean(modsetHash: _hashA);
      expect(result.removedDirectory, isTrue);
      expect(result.removedState, isTrue);
      expect(Directory(handle.path).existsSync(), isFalse);
      expect(File('${handle.path}.state.json').existsSync(), isFalse);
      final entries = await Git(
        workingDirectory: fixture.upstreamPath,
      ).worktreeList();
      expect(
        entries.any((entry) => samePath(entry.path, handle.path)),
        isFalse,
      );
    });

    test(
      'removes Git metadata when the directory was deleted manually',
      () async {
        final handle = await manager.createOrReuse(
          modsetHash: _hashA,
          synthesize: (_) async {},
        );
        Directory(handle.path).deleteSync(recursive: true);
        final result = await manager.clean(modsetHash: _hashA);
        expect(result.removedDirectory, isFalse);
        expect(result.removedState, isTrue);
        final entries = await Git(
          workingDirectory: fixture.upstreamPath,
        ).worktreeList();
        expect(
          entries.any((entry) => samePath(entry.path, handle.path)),
          isFalse,
        );
      },
    );

    test('accepts a 16 character directory prefix', () async {
      await manager.createOrReuse(modsetHash: _hashA, synthesize: (_) async {});
      final result = await manager.clean(modsetHash: _hashA.substring(0, 16));
      expect(result.modsetHash, _hashA);
      expect(result.removedDirectory, isTrue);
    });

    test('refuses unknown hashes', () async {
      await expectLater(
        manager.clean(modsetHash: _hashB),
        throwsA(isA<WorktreeCleanException>()),
      );
    });

    test('refuses a directory without a state record', () async {
      final path = manager.worktreePathFor(_hashA);
      Directory(path).createSync(recursive: true);
      File(joinPath(path, 'keep.txt')).writeAsStringSync('keep');
      await expectLater(
        manager.clean(modsetHash: _hashA),
        throwsA(isA<WorktreeCleanException>()),
      );
      expect(Directory(path).existsSync(), isTrue);
    });

    test('refuses a state record whose hash does not match', () async {
      final handle = await manager.createOrReuse(
        modsetHash: _hashA,
        synthesize: (_) async {},
      );
      final stateFile = File('${handle.path}.state.json');
      final state = jsonDecode(stateFile.readAsStringSync()) as Map;
      state['modsetHash'] = _hashB;
      stateFile.writeAsStringSync(jsonEncode(state));
      await expectLater(
        manager.clean(modsetHash: _hashA),
        throwsA(isA<WorktreeCleanException>()),
      );
      expect(Directory(handle.path).existsSync(), isTrue);
    });

    test('removes a stale state record when the directory is gone', () async {
      _writeStateFile(fixture, manager, _hashA, status: 'failed');
      final result = await manager.clean(modsetHash: _hashA);
      expect(result.removedDirectory, isFalse);
      expect(result.removedState, isTrue);
      expect(
        File('${manager.worktreePathFor(_hashA)}.state.json').existsSync(),
        isFalse,
      );
    });

    test('removes a failed directory that Git does not know about', () async {
      final path = manager.worktreePathFor(_hashA);
      Directory(path).createSync(recursive: true);
      File(joinPath(path, 'partial.txt')).writeAsStringSync('partial');
      _writeStateFile(fixture, manager, _hashA, status: 'failed');
      final result = await manager.clean(modsetHash: _hashA);
      expect(result.removedDirectory, isTrue);
      expect(Directory(path).existsSync(), isFalse);
    });

    test('does not delete sibling directories', () async {
      final handle = await manager.createOrReuse(
        modsetHash: _hashA,
        synthesize: (_) async {},
      );
      final sibling = Directory(manager.worktreePathFor(_hashB))
        ..createSync(recursive: true);
      File(joinPath(sibling.path, 'keep.txt')).writeAsStringSync('keep');
      await manager.clean(modsetHash: _hashA);
      expect(Directory(handle.path).existsSync(), isFalse);
      expect(sibling.existsSync(), isTrue);
      expect(File(joinPath(sibling.path, 'keep.txt')).existsSync(), isTrue);
    });

    test('rejects malformed hashes', () async {
      await expectLater(manager.clean(modsetHash: 'abc'), throwsArgumentError);
    });
  });
}

class _GitFixture {
  _GitFixture._(this.root, this.upstream, this.privateRepo, this.commit);

  final Directory root;
  final Directory upstream;
  final Directory privateRepo;
  final String commit;

  String get rootPath => toPosixPath(root.path);

  String get upstreamPath => toPosixPath(upstream.path);

  String get privateRepoPath => toPosixPath(privateRepo.path);

  static Future<_GitFixture> create() async {
    final root = Directory.systemTemp.createTempSync('kelivo_loader_worktree_');
    final upstreamPath = joinPath(toPosixPath(root.path), 'upstream');
    final privateRepoPath = joinPath(toPosixPath(root.path), 'private repo');
    final upstream = Directory(upstreamPath)..createSync(recursive: true);
    final privateRepo = Directory(privateRepoPath)..createSync(recursive: true);

    await _runGit(upstreamPath, ['init', '-b', 'main']);
    await _runGit(upstreamPath, ['config', 'user.email', 'test@example.com']);
    await _runGit(upstreamPath, ['config', 'user.name', 'Kelivo Test']);
    await _runGit(upstreamPath, ['config', 'core.autocrlf', 'false']);
    File(joinPath(upstreamPath, 'README.md')).writeAsStringSync('hello\n');
    File(joinPath(upstreamPath, 'pubspec.lock')).writeAsStringSync('lock\n');
    File(joinPath(upstreamPath, 'lib/keep.txt'))
      ..createSync(recursive: true)
      ..writeAsStringSync('keep\n');
    for (final path in flutterGeneratedBuildArtifacts) {
      File(joinPath(upstreamPath, path))
        ..createSync(recursive: true)
        ..writeAsStringSync('generated\n');
    }
    await _runGit(upstreamPath, ['add', '-A']);
    await _runGit(upstreamPath, ['commit', '-m', 'initial']);
    final commit = (await _runGit(upstreamPath, ['rev-parse', 'HEAD'])).trim();
    return _GitFixture._(root, upstream, privateRepo, commit);
  }

  Future<String> createSecondCommit() async {
    File(joinPath(upstreamPath, 'second.txt')).writeAsStringSync('second\n');
    await _runGit(upstreamPath, ['add', '-A']);
    await _runGit(upstreamPath, ['commit', '-m', 'second']);
    return (await _runGit(upstreamPath, ['rev-parse', 'HEAD'])).trim();
  }

  Future<void> dispose() async {
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        if (root.existsSync()) root.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}

class _RecordingGit extends Git {
  _RecordingGit({required super.workingDirectory});

  final List<List<String>> calls = <List<String>>[];

  @override
  Future<GitResult> run(
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final result = await super.run(
      args,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    calls.add(result.args);
    return result;
  }
}

class _FailingGit extends Git {
  _FailingGit({required super.workingDirectory});

  @override
  Future<void> worktreeAddDetached({
    required String path,
    required String commit,
  }) async {
    throw GitException(
      GitResult(
        args: ['worktree', 'add', '--detach', path, commit],
        workingDirectory: workingDirectory,
        exitCode: 1,
        stdout: '',
        stderr: 'simulated failure',
      ),
      'simulated failure',
    );
  }
}

/// 模拟“检出到一半失败”：目标目录仍然存在，Git 也没有登记它。
class _PartialAddGit extends _FailingGit {
  _PartialAddGit({required super.workingDirectory});

  @override
  Future<void> worktreeAddDetached({
    required String path,
    required String commit,
  }) async {
    Directory(path).createSync(recursive: true);
    File(joinPath(path, 'partial.txt')).writeAsStringSync('partial');
    await super.worktreeAddDetached(path: path, commit: commit);
  }
}

/// 模拟“Git 仍登记该路径、但目录已不存在”：不得当作无痕失败自愈。
class _RegisteredWithoutDirectoryGit extends _FailingGit {
  _RegisteredWithoutDirectoryGit({
    required super.workingDirectory,
    required this.pendingPath,
  });

  final String pendingPath;

  @override
  Future<List<GitWorktreeEntry>> worktreeList() async {
    return <GitWorktreeEntry>[
      GitWorktreeEntry(
        path: pendingPath,
        head: null,
        branch: null,
        detached: true,
        locked: false,
        prunable: false,
      ),
    ];
  }
}

/// 模拟“无法列举 worktree”：查询失败必须 fail closed，保留 failed 记录。
class _UnlistableGit extends _FailingGit {
  _UnlistableGit({required super.workingDirectory});

  @override
  Future<List<GitWorktreeEntry>> worktreeList() async {
    throw GitException(
      const GitResult(
        args: ['worktree', 'list', '--porcelain'],
        workingDirectory: '',
        exitCode: 1,
        stdout: '',
        stderr: 'simulated list failure',
      ),
      'simulated list failure',
    );
  }
}

void _writeStateFile(
  _GitFixture fixture,
  WorktreeManager manager,
  String modsetHash, {
  required String status,
}) {
  final path = manager.worktreePathFor(modsetHash);
  final stateFile = File('$path.state.json');
  stateFile.parent.createSync(recursive: true);
  stateFile.writeAsStringSync(
    '${jsonEncode(<String, Object?>{'schemaVersion': 1, 'modsetHash': modsetHash, 'upstreamPath': fixture.upstreamPath, 'upstreamCommit': fixture.commit, 'worktreePath': '.build/worktrees/${modsetHash.substring(0, 16)}', 'status': status, if (status == 'failed') 'failure': 'simulated'})}\n',
  );
}

Future<String> _runGit(String workingDirectory, List<String> args) async {
  final result = await Process.run(
    'git',
    args,
    workingDirectory: workingDirectory,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) {
    throw StateError('git ${args.join(' ')} failed: ${result.stderr}');
  }
  return result.stdout as String;
}
