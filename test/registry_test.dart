import 'dart:io';

import 'package:test/test.dart';

import '../tool/src/registry.dart';

ModRegistration _mod(
  String id, {
  String? importUri,
  String className = 'TestMod',
  List<String> toolNames = const <String>[],
}) {
  return ModRegistration(
    id: id,
    importUri: importUri ?? 'features/$id/${id}_mod.dart',
    className: className,
    toolNames: toolNames,
  );
}

void main() {
  group('renderModRegistry', () {
    test('空 Mod 集合只生成空列表和接口 import', () {
      final content = renderModRegistry(const <ModRegistration>[]);

      expect(content, contains("import 'tool_mod.dart';"));
      expect(content, contains('final List<ToolMod> kToolMods = <ToolMod>[];'));
      expect(content, isNot(contains(' as mod_')));
      expect(content, isNot(contains('PhoneAgent')));
      expect(content, contains('GENERATED CODE'));
      expect(content, contains('// dart format off'));
    });

    test('单个 Mod 生成稳定 import 和构造调用', () {
      final content = renderModRegistry(<ModRegistration>[
        _mod(
          'phone_agent',
          importUri: 'features/phone_agent/phone_agent_mod.dart',
          className: 'PhoneAgentMod',
          toolNames: const <String>['phone_agent_screenshot'],
        ),
      ]);

      expect(
        content,
        contains(
          "import '../features/phone_agent/phone_agent_mod.dart' "
          'as mod_phone_agent;',
        ),
      );
      expect(content, contains('  mod_phone_agent.PhoneAgentMod(),'));
    });

    test('package import 原样保留', () {
      for (final uri in <String>[
        'package:Kelivo/features/demo/demo_mod.dart',
        'package:other/demo/demo_mod.dart',
      ]) {
        final content = renderModRegistry(<ModRegistration>[
          _mod('demo', importUri: uri, className: 'DemoMod'),
        ]);

        expect(content, contains("import '$uri' as mod_demo;"), reason: uri);
      }
    });

    test('Mod 顺序决定列表顺序，import 行按字母排序', () {
      final content = renderModRegistry(<ModRegistration>[
        _mod('zeta', importUri: 'features/zeta/zeta_mod.dart'),
        _mod('alpha', importUri: 'features/alpha/alpha_mod.dart'),
      ]);

      final zeta = content.indexOf('  mod_zeta.TestMod(),');
      final alpha = content.indexOf('  mod_alpha.TestMod(),');
      expect(zeta, greaterThan(0));
      expect(alpha, greaterThan(0));
      expect(zeta, lessThan(alpha));

      final alphaImport = content.indexOf("import '../features/alpha/");
      final zetaImport = content.indexOf("import '../features/zeta/");
      expect(alphaImport, lessThan(zetaImport));
    });

    test('相同输入生成完全相同的内容', () {
      final mods = <ModRegistration>[
        _mod('b', importUri: 'features/b/b_mod.dart'),
        _mod('a', importUri: 'features/a/a_mod.dart'),
      ];

      expect(renderModRegistry(mods), renderModRegistry(mods));
    });

    test('id 中的非标识符字符会规范化为 import 前缀', () {
      final content = renderModRegistry(<ModRegistration>[
        _mod('phone-agent', importUri: 'features/phone/phone_mod.dart'),
      ]);

      expect(content, contains('as mod_phone_agent;'));
      expect(content, contains('  mod_phone_agent.TestMod(),'));
    });

    test('规范化后前缀冲突时追加序号', () {
      final content = renderModRegistry(<ModRegistration>[
        _mod('a-b', importUri: 'features/ab/ab_mod.dart'),
        _mod('a_b', importUri: 'features/a_b/a_b_mod.dart'),
      ]);

      expect(content, contains('as mod_a_b;'));
      expect(content, contains('as mod_a_b_2;'));
      expect(content, contains('  mod_a_b.TestMod(),'));
      expect(content, contains('  mod_a_b_2.TestMod(),'));
    });

    test('相对 import 按 lib/ 解析并转换为注册表相对路径', () {
      final content = renderModRegistry(<ModRegistration>[
        _mod('direct', importUri: 'features/direct_mod.dart'),
        _mod('root', importUri: 'lib/features/root_mod.dart'),
        _mod('sibling', importUri: 'modding/sibling_mod.dart'),
      ]);

      expect(
        content,
        contains("import '../features/direct_mod.dart' as mod_direct;"),
      );
      expect(
        content,
        contains("import '../features/root_mod.dart' as mod_root;"),
      );
      expect(content, contains("import 'sibling_mod.dart' as mod_sibling;"));
    });
  });

  group('validateModRegistrations', () {
    test('重复 Mod id 失败', () {
      expect(
        () => renderModRegistry(<ModRegistration>[
          _mod('same', importUri: 'features/a/a_mod.dart'),
          _mod('same', importUri: 'features/b/b_mod.dart'),
        ]),
        throwsA(
          isA<ModRegistryException>().having(
            (e) => e.message,
            'message',
            contains('重复的 Mod id'),
          ),
        ),
      );
    });

    test('跨 Mod 重复工具名失败并列出双方', () {
      expect(
        () => renderModRegistry(<ModRegistration>[
          _mod('a', toolNames: const <String>['shared_tool']),
          _mod('b', toolNames: const <String>['shared_tool']),
        ]),
        throwsA(
          isA<ModRegistryException>().having(
            (e) => e.message,
            'message',
            allOf(contains('shared_tool'), contains('a'), contains('b')),
          ),
        ),
      );
    });

    test('单个 Mod 内重复工具名失败', () {
      expect(
        () => renderModRegistry(<ModRegistration>[
          _mod('a', toolNames: const <String>['same_tool', 'same_tool']),
        ]),
        throwsA(
          isA<ModRegistryException>().having(
            (e) => e.message,
            'message',
            contains('重复声明工具名'),
          ),
        ),
      );
    });

    test('空白工具名失败', () {
      expect(
        () => renderModRegistry(<ModRegistration>[
          _mod('a', toolNames: const <String>[' ']),
        ]),
        throwsA(isA<ModRegistryException>()),
      );
    });

    test('非法类名失败', () {
      expect(
        () => renderModRegistry(<ModRegistration>[
          _mod('a', className: 'Demo(); evil()'),
        ]),
        throwsA(
          isA<ModRegistryException>().having(
            (e) => e.message,
            'message',
            contains('Dart 标识符'),
          ),
        ),
      );
    });

    test('绝对路径、反斜杠、..、.git 和非法 package 的 import 失败', () {
      for (final uri in <String>[
        '/lib/features/a/a_mod.dart',
        r'..\features\a\a_mod.dart',
        '../outside.dart',
        'features/.git/config.dart',
        'features//a_mod.dart',
        'dart:io',
        'https://example.com/a.dart',
        'package:Kelivo',
        'package:/a.dart',
        'package:Kelivo/../escape.dart',
        'package:Kelivo/.git/config.dart',
        'package:Kelivo/features//a.dart',
        'features/a_mod',
      ]) {
        expect(
          () => renderModRegistry(<ModRegistration>[_mod('a', importUri: uri)]),
          throwsA(isA<ModRegistryException>()),
          reason: uri,
        );
      }
    });

    test('指向注册表自身的 import 失败', () {
      expect(
        () => renderModRegistry(<ModRegistration>[
          _mod('a', importUri: 'modding/mod_registry.g.dart'),
        ]),
        throwsA(isA<ModRegistryException>()),
      );
    });
  });

  group('patches/tool_mod_seams.patch', () {
    late String patch;

    setUpAll(() {
      final file = File('patches/tool_mod_seams.patch');
      expect(file.existsSync(), isTrue, reason: '接缝补丁必须存在');
      patch = file.readAsStringSync();
    });

    test('只修改 generation_controller.dart', () {
      final diffs = RegExp(
        r'^diff --git a/(\S+) b/(\S+)$',
        multiLine: true,
      ).allMatches(patch).toList();

      expect(diffs, hasLength(1));
      expect(
        diffs.single.group(1),
        'lib/features/home/controllers/generation_controller.dart',
      );
      expect(diffs.single.group(2), diffs.single.group(1));
      expect(patch, isNot(contains('new file mode')));
      expect(patch, isNot(contains('deleted file mode')));
      expect(patch, isNot(contains('--- /dev/null')));
    });

    test('包含一个 import hunk 和四个工具委托 hunk', () {
      final hunks = RegExp(
        r'^@@ -(\d+),(\d+) \+(\d+),(\d+) @@',
        multiLine: true,
      ).allMatches(patch).toList();

      expect(hunks, hasLength(5));
      final starts = hunks.map((hunk) => int.parse(hunk.group(1)!)).toList()
        ..sort();
      expect(starts.where((start) => start < 100), hasLength(1));
      for (final start in starts.where((start) => start >= 100)) {
        expect(start, inInclusiveRange(100, 180));
      }
    });

    test('调用注册表与通用接口，不包含具体业务 Mod', () {
      expect(patch, contains('composeToolDefinitions('));
      expect(patch, contains('composeToolCallHandler('));
      expect(patch, contains('kToolMods'));
      expect(patch, contains('ModToolDefinitionContext('));
      expect(patch, contains('ModToolExecutionContext('));
      expect(patch, contains('readCurrentAssistant'));

      for (final forbidden in <String>[
        'phone_agent',
        'phone_control',
        'PhoneAgent',
        'LocalToolNames',
        'pubspec',
      ]) {
        expect(patch, isNot(contains(forbidden)), reason: forbidden);
      }
    });

    test('新增 import 仅限通用接口与助手重读所需', () {
      final addedImports = patch
          .split('\n')
          .where((line) => line.startsWith('+import '))
          .map((line) => line.substring(1).trim())
          .toList();

      expect(
        addedImports,
        unorderedEquals(<String>[
          "import '../../../core/providers/assistant_provider.dart';",
          "import '../../../modding/mod_registry.g.dart';",
          "import '../../../modding/tool_mod.dart';",
        ]),
      );
    });

    test('补丁规模保持为小范围接缝', () {
      final lines = patch.split('\n');
      final added = lines
          .where((line) => line.startsWith('+') && !line.startsWith('+++'))
          .length;
      final removed = lines
          .where((line) => line.startsWith('-') && !line.startsWith('---'))
          .length;

      expect(added, lessThan(80));
      expect(removed, lessThan(30));
    });
  });
}
