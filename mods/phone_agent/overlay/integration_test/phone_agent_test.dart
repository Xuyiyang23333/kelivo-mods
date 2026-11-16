import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/database/app_database.dart';
import 'package:Kelivo/core/database/business_preferences.dart';
import 'package:Kelivo/core/database/business_repository.dart';
import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/models/model_spec.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/home/services/local_tools_service.dart';
import 'package:Kelivo/features/phone_agent/phone_agent_local_tool.dart';
import 'package:Kelivo/features/phone_agent/phone_agent_service.dart';
import 'package:Kelivo/features/phone_agent/phone_agent_tools.dart';
import 'package:Kelivo/features/settings/pages/settings_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/modding/mod_registry.g.dart';
import 'package:Kelivo/modding/tool_mod.dart';
import 'package:Kelivo/shared/widgets/ios_checkbox.dart';
import 'package:Kelivo/utils/mcp_structured_image.dart';

// 真机闭环：读树 → 节点点击 → 节点输入 → 滚动；API 30+ 另测截图与坐标滑动。
//
// 前置条件：
// - Android 设备已解锁；截图和坐标手势需要 API 30 或更高；
// - 系统无障碍设置中已启用 Kelivo Phone Agent 服务；
// - 默认关闭后台悬浮胶囊，前台包名为 com.psyche.kelivo.phoneagent。
//
// flutter test integration_test/phone_agent_test.dart -d <android-device-id>
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late PhoneAgentAvailability status;

  setUpAll(() async {
    expect(
      Platform.isAndroid,
      isTrue,
      reason: 'Phone Agent 集成测试只能在 Android 真机上运行。',
    );
    // 安装测试包会撤销无障碍授权。先给宿主留出通过系统界面重新启用的时间，
    // 避免在服务未启用时立即轮询状态（慢速模拟器上可能拖住主线程）。
    debugPrint('PHONE_AGENT_WAITING_FOR_SERVICE');
    await Future<void>.delayed(const Duration(seconds: 20));
    status = await PhoneAgentService.instance.status();
    if (!status.ready) {
      for (var i = 0; i < 600 && !status.ready; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        status = await PhoneAgentService.instance.status();
      }
    }
    expect(
      status.ready,
      isTrue,
      reason:
          'Phone Agent 服务未就绪（supported=${status.supported}, '
          'enabled=${status.enabled}, connected=${status.connected}, '
          'sdk=${status.androidSdkInt}）。请解锁设备并在系统无障碍设置中启用服务。',
    );
  });

  testWidgets('Phone Agent 真机闭环', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final preferences = BusinessPreferences(BusinessRepository(database));
    await preferences.load();
    final settings = SettingsProvider(preferences);
    await settings.loaded;
    addTearDown(() async {
      settings.dispose();
      await database.close();
    });

    const conversationId = 'phone-agent-integration';
    const assistant = Assistant(
      id: 'phone-agent-integration',
      name: 'Phone Agent',
      localToolIds: <String>[PhoneAgentLocalTool.id],
    );
    final definitions = composeToolDefinitions(
      kToolMods,
      <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'function',
          'function': <String, dynamic>{'name': LocalToolNames.phoneControl},
        },
      ],
      ModToolDefinitionContext(
        settings: settings,
        assistant: assistant,
        providerKey: 'integration',
        modelId: 'integration',
        conversationId: conversationId,
        supportsTools: true,
        inputModalities: const <Modality>[Modality.text, Modality.image],
      ),
    );
    expect(_definitionNames(definitions), <String>[
      PhoneAgentToolNames.screenshot,
      PhoneAgentToolNames.tree,
      PhoneAgentToolNames.input,
    ]);

    Future<Object?> originalHandler(
      String name,
      Map<String, dynamic> args, {
      String? toolCallId,
    }) async {
      return ClientToolResult('unexpected tool: $name');
    }

    final handler = composeToolCallHandler(
      kToolMods,
      originalHandler,
      ModToolExecutionContext(
        assistant: assistant,
        conversationId: conversationId,
        approvalService: null,
        askUserService: null,
        originalHandler: originalHandler,
        readCurrentAssistant: () => assistant,
      ),
    );

    var taps = 0;
    final textController = TextEditingController();
    final scrollController = ScrollController();
    addTearDown(textController.dispose);
    addTearDown(scrollController.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              GestureDetector(
                onTap: () => taps++,
                child: const SizedBox(
                  width: double.infinity,
                  height: 120,
                  child: Center(child: Text('PHONE_AGENT_TAP_TARGET')),
                ),
              ),
              TextField(
                controller: textController,
                decoration: const InputDecoration(
                  labelText: 'PHONE_AGENT_TEXT_FIELD',
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: 60,
                  itemBuilder: (_, index) => SizedBox(
                    height: 80,
                    child: Text('PHONE_AGENT_ITEM_$index'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    if (status.supported) {
      final screenshot = _payload(
        await handler(PhoneAgentToolNames.screenshot, <String, dynamic>{}),
        '截图',
      );
      _expectOk(screenshot, '截图');
      final image = screenshot['image'] as Map;
      final screen = screenshot['screen'] as Map;
      expect(image['width'], greaterThan(0));
      expect(image['height'], greaterThan(0));
      expect(screen['width'], greaterThan(0));
      expect(screen['height'], greaterThan(0));
      expect(screenshot['package_name'], 'com.psyche.kelivo.phoneagent');
    } else {
      final unsupported = _payload(
        await handler(PhoneAgentToolNames.screenshot, <String, dynamic>{}),
        '旧系统截图降级',
      );
      expect(unsupported['type'], 'tool_error');
      expect(unsupported['error'], 'unsupported_os');
    }

    final firstTree = _treePayload(
      await handler(PhoneAgentToolNames.tree, <String, dynamic>{'offset': 0}),
    );
    expect(firstTree['package_name'], 'com.psyche.kelivo.phoneagent');
    expect(firstTree['width'], greaterThan(0));
    expect(firstTree['height'], greaterThan(0));
    final tapNode = _nodeForText(firstTree, 'PHONE_AGENT_TAP_TARGET');
    expect(tapNode, isNotNull, reason: '读树结果中没有找到点击目标节点。');
    // 宿主标记：读树观察脉冲和节点点击圆环是叠加层证据，可用 adb exec-out screencap
    // 观察叠加层本身；产品截图链路不依赖宿主截图。
    debugPrint(
      'PHONE_AGENT_OVERLAY_NODE_TAP: 节点点击后约 600ms 内可在设备上观察叠加层圆环；'
      'adb 截图只作宿主证据，不是产品能力。',
    );
    _expectInputOk(
      _payload(
        await handler(PhoneAgentToolNames.input, <String, dynamic>{
          'action': 'tap',
          'node_id': tapNode!['node_id'],
        }),
        '节点点击',
      ),
      '节点点击',
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(taps, 1, reason: '节点点击未触发测试界面回调。');

    if (status.supported) {
      // 系统截图限频约 1 次/秒，第二次截图前等待足够间隔。
      await tester.pump(const Duration(milliseconds: 1500));
      _expectOk(
        _payload(
          await handler(PhoneAgentToolNames.screenshot, <String, dynamic>{}),
          '滑动前截图',
        ),
        '滑动前截图',
      );
      _expectInputOk(
        _payload(
          await handler(PhoneAgentToolNames.input, <String, dynamic>{
            'action': 'swipe',
            'x': 0.5,
            'y': 0.5,
            'end_x': 0.5,
            'end_y': 0.2,
            'duration_ms': 300,
          }),
          '坐标滑动',
        ),
        '坐标滑动',
      );
    }
    // integration_test 绑定默认不转发设备指针事件（shouldPropagateDevicePointerEvents=false），
    // 坐标滑动的 UI 效果无法在测试内断言；用无障碍滚动动作验证列表真的滚动。
    final scrollTree = _treePayload(
      await handler(PhoneAgentToolNames.tree, <String, dynamic>{'offset': 0}),
    );
    final scrollNode = _firstScrollable(scrollTree);
    expect(scrollNode, isNotNull, reason: '读树结果中没有找到滚动节点。');
    _expectInputOk(
      _payload(
        await handler(PhoneAgentToolNames.input, <String, dynamic>{
          'action': 'scroll',
          'node_id': scrollNode!['node_id'],
          'direction': 'forward',
        }),
        '节点滚动',
      ),
      '节点滚动',
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(scrollController.offset, greaterThan(0), reason: '输入未滚动测试列表。');

    final fieldTree = _treePayload(
      await handler(PhoneAgentToolNames.tree, <String, dynamic>{'offset': 0}),
    );
    final fieldNode = _firstEditable(fieldTree);
    expect(fieldNode, isNotNull, reason: '读树结果中没有找到可编辑节点。');
    _expectInputOk(
      _payload(
        await handler(PhoneAgentToolNames.input, <String, dynamic>{
          'action': 'tap',
          'node_id': fieldNode!['node_id'],
        }),
        '聚焦输入框',
      ),
      '聚焦输入框',
    );
    await tester.pump(const Duration(milliseconds: 400));

    // 聚焦会改变 isFocused 和动作集合，但同一观测内的句柄必须仍可用于 set_text。
    _expectInputOk(
      _payload(
        await handler(PhoneAgentToolNames.input, <String, dynamic>{
          'action': 'set_text',
          'node_id': fieldNode['node_id'],
          'text': 'phone agent',
        }),
        '文本输入',
      ),
      '文本输入',
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(textController.text, 'phone agent', reason: '节点输入未写入测试输入框。');

    final secondTree = _treePayload(
      await handler(PhoneAgentToolNames.tree, <String, dynamic>{'offset': 0}),
    );
    expect(_nodes(secondTree), isNotEmpty, reason: '动作后重新读树没有返回节点。');
  });

  testWidgets('Mods 页真实服务状态与 Phone Agent 选择', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final preferences = BusinessPreferences(BusinessRepository(database));
    await preferences.load();
    final settings = SettingsProvider(preferences);
    await settings.loaded;
    final assistants = AssistantProvider(preferences: preferences);
    await assistants.loaded;
    final assistantId = await assistants.addAssistant(name: 'Phone Agent UI');
    await assistants.updateAssistant(
      assistants
          .getById(assistantId)!
          .copyWith(localToolIds: <String>[LocalToolNames.phoneControl]),
    );
    addTearDown(() async {
      assistants.dispose();
      settings.dispose();
      await database.close();
    });

    final lifecycle = <AppLifecycleState>[];
    final observer = _LifecycleRecorder(lifecycle);
    WidgetsBinding.instance.addObserver(observer);
    addTearDown(() => WidgetsBinding.instance.removeObserver(observer));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<AssistantProvider>.value(value: assistants),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final modsEntry = find.text('Mods');
    await tester.scrollUntilVisible(modsEntry, 300);
    await tester.pumpAndSettle();
    await tester.tap(modsEntry);
    await tester.pumpAndSettle();

    for (
      var i = 0;
      i < 40 && find.text('Enabled and connected').evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Mods'), findsOneWidget);
    expect(find.text('Enabled and connected'), findsOneWidget);
    expect(find.text('API ${status.androidSdkInt}'), findsOneWidget);
    if (status.androidSdkInt < 30) {
      expect(status.supported, isFalse);
      expect(
        find.text(
          'Screenshots and coordinate actions require Android 11 or later.',
        ),
        findsOneWidget,
      );
    }

    final phoneAgentMode = find.byType(IosCheckbox).at(2);
    await tester.ensureVisible(phoneAgentMode);
    await tester.tap(phoneAgentMode);
    await tester.pumpAndSettle();
    // M34：首次启用 Phone Agent 会先弹出一次性隐私确认（方案 B）。未确认时选择
    // **不会**写入，所以这里必须走完真实弹窗，而不是绕过它。弹窗要等原生
    // `privacyNotice` 通道返回后才出现，`pumpAndSettle` 不等平台通道，因此有界轮询。
    //
    // 文案不硬编码英文：从 l10n 按 harness 固定的 `en` locale 取，键改名/译文改动会
    // 跟着走。诊断串必须区分「此前已确认」与「超时仍未出现」——把两者合并会让非英文
    // locale 下的真实问题（找不到按钮）伪装成“选择没生效”。
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final privacyConfirm = find.text(l10n.phoneAgentPrivacyNoticeConfirm);
    for (var i = 0; i < 60 && privacyConfirm.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (privacyConfirm.evaluate().isNotEmpty) {
      expect(find.text(l10n.phoneAgentPrivacyNoticeTitle), findsOneWidget);
      await tester.tap(privacyConfirm);
      await tester.pumpAndSettle();
      debugPrint(
        'PHONE_AGENT_PRIVACY_DIALOG: shown keyed on '
        '${l10n.localeName} l10n label',
      );
    } else if (await PhoneAgentService.instance.privacyNoticeAcknowledged()) {
      debugPrint('PHONE_AGENT_PRIVACY_DIALOG: already acknowledged');
    } else {
      fail(
        '隐私确认弹窗 6 秒内没有出现，但原生记录仍是“未确认”。'
        '这不是选择失败，而是测试找不到弹窗（locale/文案键或平台通道问题）。',
      );
    }
    for (
      var i = 0;
      i < 40 &&
          !assistants
              .getById(assistantId)!
              .localToolIds
              .contains(PhoneAgentLocalTool.id);
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final updated = assistants.getById(assistantId)!;
    expect(updated.localToolIds, contains(PhoneAgentLocalTool.id));
    expect(updated.localToolIds, isNot(contains(LocalToolNames.phoneControl)));
    expect(lifecycle, isNot(contains(AppLifecycleState.paused)));
    expect(find.text('Enabled and connected'), findsOneWidget);
  });
}

class _LifecycleRecorder extends WidgetsBindingObserver {
  _LifecycleRecorder(this.states);

  final List<AppLifecycleState> states;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    states.add(state);
  }
}

List<String> _definitionNames(List<Map<String, dynamic>> definitions) {
  return <String>[
    for (final definition in definitions)
      if (definition['function'] case final Map function)
        if (function['name'] case final String name) name,
  ];
}

Map<String, dynamic> _payload(Object? result, String step) {
  expect(
    result,
    isA<ClientToolResult>(),
    reason: '$step 没有返回 ClientToolResult。',
  );
  final content = (result as ClientToolResult).content;
  final decoded = jsonDecode(content.split('\n').first);
  expect(decoded, isA<Map<String, dynamic>>(), reason: '$step 返回内容不是 JSON。');
  return decoded as Map<String, dynamic>;
}

Map<String, dynamic> _treePayload(Object? result) {
  final payload = _payload(result, '读树');
  _expectOk(payload, '读树');
  final tree = payload['result'];
  expect(tree, isA<Map>(), reason: '读树结果缺少 result。');
  return Map<String, dynamic>.from(tree as Map);
}

void _expectOk(Map<String, dynamic> payload, String step) {
  if (payload['ok'] == true) return;
  fail(
    '$step 失败：${payload['error']} ${payload['message']} '
    '${payload['instruction'] ?? ''}',
  );
}

void _expectInputOk(Map<String, dynamic> payload, String step) {
  _expectOk(payload, step);
  final result = payload['result'];
  expect(result, isA<Map>(), reason: '$step 缺少 result。');
  expect((result as Map)['success'], isTrue, reason: '$step 未被原生接受。');
}

List<Map<String, dynamic>> _nodes(Map<String, dynamic> tree) {
  final nodes = tree['nodes'];
  if (nodes is! List) return const <Map<String, dynamic>>[];
  return <Map<String, dynamic>>[
    for (final node in nodes)
      if (node is Map) Map<String, dynamic>.from(node),
  ];
}

Map<String, dynamic>? _nodeForText(Map<String, dynamic> tree, String text) {
  for (final node in _nodes(tree)) {
    final values = <Object?>[
      node['text'],
      node['description'],
      node['hint'],
      node['state_description'],
    ];
    if (!values.any((value) => value is String && value.contains(text))) {
      continue;
    }
    return node;
  }
  return null;
}

Map<String, dynamic>? _firstEditable(Map<String, dynamic> tree) {
  for (final node in _nodes(tree)) {
    if (node['editable'] == true) return node;
  }
  return null;
}

Map<String, dynamic>? _firstScrollable(Map<String, dynamic> tree) {
  for (final node in _nodes(tree)) {
    if (node['scrollable'] == true) return node;
  }
  return null;
}
