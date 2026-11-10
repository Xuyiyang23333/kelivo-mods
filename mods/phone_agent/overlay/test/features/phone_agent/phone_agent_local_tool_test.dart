import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/features/home/services/local_tools_service.dart';
import 'package:Kelivo/features/phone_agent/phone_agent_local_tool.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/business_test_harness.dart';
import 'phone_agent_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('三态读取', () {
    test('未启用任何手机工具时为关闭', () {
      expect(
        PhoneAgentLocalTool.selectionFor(disabledAssistant),
        PhoneAgentControlSelection.off,
      );
    });

    test('仅启用 phone_control 时为原生', () {
      expect(
        PhoneAgentLocalTool.selectionFor(nativeAssistant),
        PhoneAgentControlSelection.native,
      );
    });

    test('启用 phone_agent 时为 Phone Agent', () {
      expect(
        PhoneAgentLocalTool.selectionFor(enabledAssistant),
        PhoneAgentControlSelection.phoneAgent,
      );
    });

    test('双 ID 同时存在时优先 phoneAgent', () {
      expect(
        PhoneAgentLocalTool.selectionFor(conflictAssistant),
        PhoneAgentControlSelection.phoneAgent,
      );
    });

    test('没有助手时为关闭', () {
      expect(
        PhoneAgentLocalTool.selectionFor(null),
        PhoneAgentControlSelection.off,
      );
    });
  });

  group('三态互斥写入', () {
    test('关闭移除两个 ID 并保留其他工具', () {
      expect(
        PhoneAgentLocalTool.applySelection(<String>[
          LocalToolNames.timeInfo,
          LocalToolNames.phoneControl,
          PhoneAgentLocalTool.id,
        ], PhoneAgentControlSelection.off),
        <String>[LocalToolNames.timeInfo],
      );
    });

    test('原生只保留 phone_control', () {
      final ids = PhoneAgentLocalTool.applySelection(<String>[
        LocalToolNames.timeInfo,
        PhoneAgentLocalTool.id,
      ], PhoneAgentControlSelection.native);
      expect(
        ids,
        containsAll(<String>[
          LocalToolNames.timeInfo,
          LocalToolNames.phoneControl,
        ]),
      );
      expect(ids, isNot(contains(PhoneAgentLocalTool.id)));
    });

    test('Phone Agent 只保留 phone_agent', () {
      final ids = PhoneAgentLocalTool.applySelection(<String>[
        LocalToolNames.timeInfo,
        LocalToolNames.phoneControl,
      ], PhoneAgentControlSelection.phoneAgent);
      expect(
        ids,
        containsAll(<String>[LocalToolNames.timeInfo, PhoneAgentLocalTool.id]),
      );
      expect(ids, isNot(contains(LocalToolNames.phoneControl)));
    });

    test('重复 ID 被去重', () {
      final ids = PhoneAgentLocalTool.applySelection(<String>[
        LocalToolNames.timeInfo,
        LocalToolNames.timeInfo,
        PhoneAgentLocalTool.id,
        PhoneAgentLocalTool.id,
      ], PhoneAgentControlSelection.phoneAgent);
      expect(ids, <String>[LocalToolNames.timeInfo, PhoneAgentLocalTool.id]);
    });
  });

  group('冲突检测', () {
    test('双 ID 同时存在时报告冲突', () {
      expect(PhoneAgentLocalTool.hasConflict(conflictAssistant), isTrue);
    });

    test('单个 ID 时不报告冲突', () {
      expect(PhoneAgentLocalTool.hasConflict(nativeAssistant), isFalse);
      expect(PhoneAgentLocalTool.hasConflict(enabledAssistant), isFalse);
      expect(PhoneAgentLocalTool.hasConflict(disabledAssistant), isFalse);
    });
  });

  group('平台判断', () {
    test('Android 为 true', () {
      runOnAndroid();
      expect(PhoneAgentLocalTool.isAndroid, isTrue);
    });

    test('非 Android 为 false', () {
      runOnIos();
      expect(PhoneAgentLocalTool.isAndroid, isFalse);
    });
  });

  group('写入前重读', () {
    late BusinessTestHarness harness;
    late AssistantProvider provider;

    setUp(() async {
      harness = await createBusinessTestHarness(
        initial: <String, Object?>{
          'assistants_v1': Assistant.encodeList(<Assistant>[
            const Assistant(
              id: 'a',
              name: 'Original',
              localToolIds: <String>[LocalToolNames.timeInfo],
            ),
            const Assistant(id: 'b', name: 'Other'),
          ]),
        },
      );
      provider = AssistantProvider(preferences: harness.preferences);
      await provider.loaded;
      addTearDown(provider.dispose);
    });

    test('按 assistantId 重读最新助手，不覆盖旧快照后的改动', () async {
      final stale = provider.getById('a')!;
      await provider.updateAssistant(
        provider.getById('a')!.copyWith(name: 'Renamed', searchEnabled: true),
      );

      final written = await PhoneAgentLocalTool.writeSelection(
        provider,
        assistantId: stale.id,
        selection: PhoneAgentControlSelection.phoneAgent,
      );

      expect(written, isTrue);
      final latest = provider.getById('a')!;
      expect(latest.name, 'Renamed');
      expect(latest.searchEnabled, isTrue);
      expect(latest.localToolIds, contains(PhoneAgentLocalTool.id));
      expect(latest.localToolIds, contains(LocalToolNames.timeInfo));
      expect(latest.localToolIds, isNot(contains(LocalToolNames.phoneControl)));
    });

    test('选择原生时移除 phone_agent', () async {
      await PhoneAgentLocalTool.writeSelection(
        provider,
        assistantId: 'a',
        selection: PhoneAgentControlSelection.phoneAgent,
      );
      await PhoneAgentLocalTool.writeSelection(
        provider,
        assistantId: 'a',
        selection: PhoneAgentControlSelection.native,
      );

      final latest = provider.getById('a')!;
      expect(latest.localToolIds, contains(LocalToolNames.phoneControl));
      expect(latest.localToolIds, isNot(contains(PhoneAgentLocalTool.id)));
    });

    test('选择关闭时移除两个 ID', () async {
      await PhoneAgentLocalTool.writeSelection(
        provider,
        assistantId: 'a',
        selection: PhoneAgentControlSelection.phoneAgent,
      );
      await PhoneAgentLocalTool.writeSelection(
        provider,
        assistantId: 'a',
        selection: PhoneAgentControlSelection.off,
      );

      final latest = provider.getById('a')!;
      expect(latest.localToolIds, <String>[LocalToolNames.timeInfo]);
    });

    test('助手不存在时不写入', () async {
      final written = await PhoneAgentLocalTool.writeSelection(
        provider,
        assistantId: 'missing',
        selection: PhoneAgentControlSelection.phoneAgent,
      );

      expect(written, isFalse);
      expect(provider.getById('a')!.localToolIds, <String>[
        LocalToolNames.timeInfo,
      ]);
    });

    test('选择未变化时不写入', () async {
      var notifications = 0;
      provider.addListener(() => notifications++);

      final written = await PhoneAgentLocalTool.writeSelection(
        provider,
        assistantId: 'a',
        selection: PhoneAgentControlSelection.off,
      );

      expect(written, isFalse);
      expect(notifications, 0);
    });

    test('写入结果持久化到偏好存储', () async {
      await PhoneAgentLocalTool.writeSelection(
        provider,
        assistantId: 'a',
        selection: PhoneAgentControlSelection.phoneAgent,
      );

      final reloaded = AssistantProvider(preferences: harness.preferences);
      await reloaded.loaded;
      addTearDown(reloaded.dispose);
      expect(
        reloaded.getById('a')!.localToolIds,
        contains(PhoneAgentLocalTool.id),
      );
    });
  });
}
