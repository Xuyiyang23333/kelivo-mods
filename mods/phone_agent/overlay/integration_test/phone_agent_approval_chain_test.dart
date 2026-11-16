import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:Kelivo/utils/mcp_structured_image.dart';
import 'package:Kelivo/features/phone_agent/phone_agent_approval_card.dart';
import 'package:Kelivo/features/phone_agent/phone_agent_approval_service.dart';
import 'package:Kelivo/features/phone_agent/phone_agent_service.dart';
import 'package:Kelivo/features/phone_agent/phone_agent_tools.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

// 应用批准链路端到端（plan 7.5.4/7.5.6，M36）：
//
//   未批准 → 读树只回应用身份 + permission_required
//          → 聊天卡片出现（真实卡片 widget）
//          → 点「允许」写入白名单
//          → 重新观察返回真实树
//          → Mods 页撤销（原生 revokeApp）
//          → 再次 permission_required
//
// 前置条件：Android 设备已解锁，Kelivo Phone Agent 服务 enabled && connected，
// 前台是测试包（`com.psyche.kelivo.phoneagent`，属构建配置预批准条目）。
// 目标应用用 launcher（第三方、未批准、非 deny 成员）：宿主先按 HOME 把测试
// 应用切到后台，测试只在 launcher 成为前台后观察。
//
// 本文件只断言**产品契约**（错误码、身份字段、白名单生效/撤销），不伪造设备
// 场景；宿主切换前台的标记由宿主脚本执行。
//
// flutter test integration_test/phone_agent_approval_chain_test.dart -d <device>
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final service = PhoneAgentService.instance;
  final approvals = PhoneAgentApprovalService.instance;

  /// 未批准目标：默认 Pixel Launcher（M28/M30 实测 `home` 后前台是它）。
  ///
  /// 其他设备/ROM 的 launcher 包名不同，因此允许用
  /// `--dart-define=PHONE_AGENT_TARGET_PACKAGE=<包名>` 覆盖；找不到目标时
  /// 用例会明确报「等待目标前台超时」，而不是把 ROM 差异伪装成产品失败。
  const targetPackage = String.fromEnvironment(
    'PHONE_AGENT_TARGET_PACKAGE',
    defaultValue: 'com.google.android.apps.nexuslauncher',
  );

  setUpAll(() async {
    expect(Platform.isAndroid, isTrue, reason: '只在 Android 设备上运行。');
    debugPrint('PHONE_AGENT_WAITING_FOR_SERVICE');
    await Future<void>.delayed(const Duration(seconds: 20));
    var status = await service.status();
    for (var i = 0; i < 600 && !status.ready; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      status = await service.status();
    }
    expect(status.ready, isTrue, reason: 'Phone Agent 服务未就绪。');
    // 起点必须是干净的：上一次运行残留的批准会让第一次读树直接成功。
    try {
      await service.revokeApp(targetPackage);
    } catch (_) {}
    await approvals.dismissAll();
    await approvals.refresh();
  });

  tearDownAll(() async {
    // 不在设备上留下批准状态：本用例自己写入的授权要撤掉。
    try {
      await service.revokeApp(targetPackage);
    } catch (_) {}
    try {
      await approvals.dismissAll();
    } catch (_) {}
  });

  testWidgets('批准链路：只回身份 → 卡片 → 批准 → 重新观察 → 撤销 → 再次拒绝',
      (tester) async {
    // 1. 宿主按 HOME，让未批准的 launcher 成为前台。产品自己执行 home 动作是
    //    被允许的（系统导航不需要白名单），但随后读树的**目标**是 launcher。
    _hostStep(
      'PHONE_AGENT_APPROVAL_TARGET_FOREGROUND',
      'adb shell input keyevent KEYCODE_HOME；等待 launcher 成为前台 '
          '(dumpsys window | grep mCurrentFocus)',
    );
    final onLauncher = await _waitForForegroundPackage(
      service,
      packageName: targetPackage,
      timeout: const Duration(seconds: 60),
    );
    expect(
      onLauncher,
      isTrue,
      reason: '等待 launcher 成为前台超时；无法在没有未批准前台时验证门控。',
    );

    // 2. 未批准：读树只回应用身份与 permission_required。
    final denied = await _tree(service);
    final deniedPayload = _payload(denied);
    expect(
      deniedPayload['error'],
      'permission_required',
      reason: '未批准的 launcher 读树必须返回 permission_required。',
    );
    final identity = deniedPayload['identity'];
    expect(identity, isA<Map>(), reason: 'permission_required 必须带结构化身份。');
    final identityMap = Map<String, dynamic>.from(identity as Map);
    expect(identityMap['package_name'], targetPackage);
    final prefix = identityMap['signing_prefix'];
    if (prefix is String && prefix.isNotEmpty) {
      expect(prefix, hasLength(8), reason: '签名前缀必须是 SHA-256 前 8 位。');
    } else {
      // 解析不到签名时消息只写 signing_unavailable，且此时不创建卡片。
      expect(
        deniedPayload['message'].toString(),
        contains('signing_unavailable'),
        reason: '签名缺失时必须如实标 signing_unavailable。',
      );
    }
    // 不返回任何界面内容。
    expect(deniedPayload.containsKey('result'), isFalse);
    expect(identityMap.containsKey('nodes'), isFalse);
    expect(identityMap.containsKey('window_title'), isFalse);
    expect(
      deniedPayload['message'].toString().toLowerCase(),
      contains('no screenshot'),
      reason: '观察侧文案必须明确没有截图/没有读取界面文本。',
    );
    debugPrint(
      'PHONE_AGENT_APPROVAL_DENIED: package=${identityMap['package_name']} '
      'signing=${identityMap['signing_prefix']} '
      'display=${identityMap['display_name']}',
    );

    // 3. 聊天卡片：走真实工具入口，让 `_registerApproval` 登记 pending 请求。
    const toolCallId = 'm36-approval-chain-call';
    const conversationId = 'm36-approval-chain-conversation';
    final toolResult = await PhoneAgentTools.handleCall(
      name: PhoneAgentToolNames.tree,
      args: const <String, dynamic>{'offset': 0},
      service: service,
      supportsImageInput: true,
      conversationId: conversationId,
      toolCallId: toolCallId,
      approvalAssistantId: 'm36-assistant',
    );
    final toolPayload = _payload(toolResult!);
    if (toolPayload['error'] != 'permission_required') {
      final probeTree = toolPayload['result'];
      debugPrint(
        'PHONE_AGENT_APPROVAL_PROBE: foregroundChanged error='
        '${toolPayload['error']} package='
        '${probeTree is Map ? probeTree['package_name'] : null}',
      );
    }
    expect(toolPayload['error'], 'permission_required');

    await approvals.refresh();
    final pending = approvals.pendingFor(
      toolCallId: toolCallId,
      conversationId: conversationId,
    );
    expect(
      pending,
      isNotNull,
      reason: 'permission_required 后必须登记一条可展示的 pending 请求。',
    );
    expect(pending!.packageName, targetPackage);
    expect(pending.signingPrefix, identityMap['signing_prefix']);
    debugPrint(
      'PHONE_AGENT_APPROVAL_PENDING: request=${pending.requestId} '
      'package=${pending.packageName} signing=${pending.signingPrefix}',
    );

    // 4. 真实卡片 widget 必须在默认设置下渲染（R1 p1 修复点）。
    if (pending.signingPrefix == null) {
      // 签名缺失时产品**刻意不创建卡片**（批准必然失败），此处不伪造卡片场景。
      debugPrint('PHONE_AGENT_APPROVAL_CARD: skipped (no signing prefix)');
    } else {
      await _pumpCard(
        tester,
        toolCallId: toolCallId,
        conversationId: conversationId,
      );
      expect(
        find.textContaining('Allow'),
        findsWidgets,
        reason: '卡片没有渲染出批准按钮。',
      );
      expect(find.text(targetPackage), findsOneWidget);
      debugPrint('PHONE_AGENT_APPROVAL_CARD: visible');

      // 5. 点「允许」：写入白名单（`resolve` 走原生 resolveApproval）。
      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      final remaining = approvals.pendingFor(
        toolCallId: toolCallId,
        conversationId: conversationId,
      );
      expect(remaining, isNull, reason: '批准后卡片必须消失。');
    }

    final approved = await service.approvedApps();
    expect(
      approved.map((app) => app.packageName),
      contains(targetPackage),
      reason: '批准后白名单必须包含目标包。',
    );
    debugPrint(
      'PHONE_AGENT_APPROVAL_APPROVED: prefix='
      '${approved.firstWhere((app) => app.packageName == targetPackage).signingPrefix}',
    );

    // 6. 重新观察：已批准 → 返回真实树（含 launcher 自己的节点）。
    //    点卡片会回到本应用（批准是应用内动作），所以重新观察前必须让宿主把
    //    未批准→已批准的那个应用重新切到前台。
    _hostStep(
      'PHONE_AGENT_APPROVAL_TARGET_FOREGROUND',
      'adb shell input keyevent KEYCODE_HOME；重新把 launcher 切到前台后再观察',
    );
    expect(
      await _waitForForegroundPackage(
        service,
        packageName: targetPackage,
        timeout: const Duration(seconds: 60),
      ),
      isTrue,
      reason: '批准后无法把 launcher 重新切到前台，无法验证已批准观察。',
    );
    final granted = await _tree(service);
    final grantedPayload = _payload(granted);
    expect(
      grantedPayload['error'],
      isNull,
      reason: '批准后读树必须成功，实际：${grantedPayload['error']} '
          '${grantedPayload['message']}',
    );
    final tree = Map<String, dynamic>.from(grantedPayload['result'] as Map);
    expect(tree['package_name'], targetPackage);
    final nodes = tree['nodes'];
    expect(nodes, isA<List>());
    expect(
      (nodes as List),
      isNotEmpty,
      reason: '批准后读树必须返回真实节点，而不是空树占位。',
    );
    debugPrint(
      'PHONE_AGENT_APPROVAL_OBSERVED: package=${tree['package_name']} '
      'nodes=${nodes.length}',
    );

    // 7. Mods 页撤销（同一原生入口，UI 页只是它的视图）。
    await service.revokeApp(targetPackage);
    final afterRevoke = await service.approvedApps();
    expect(
      afterRevoke.map((app) => app.packageName),
      isNot(contains(targetPackage)),
      reason: '撤销后白名单必须不再包含目标包。',
    );

    // 8. 撤销后再次读树：必须回到 permission_required 且仍然只回身份。
    final deniedAgain = await _tree(service);
    final deniedAgainPayload = _payload(deniedAgain);
    expect(
      deniedAgainPayload['error'],
      'permission_required',
      reason: '撤销后读树必须重新返回 permission_required。',
    );
    expect(deniedAgainPayload.containsKey('result'), isFalse);
    final againIdentity = deniedAgainPayload['identity'];
    expect(againIdentity, isA<Map>());
    expect(
      Map<String, dynamic>.from(againIdentity as Map)['package_name'],
      targetPackage,
    );
    debugPrint('PHONE_AGENT_APPROVAL_REVOKED: permission_required again');
  });
}

Future<void> _pumpCard(
  WidgetTester tester, {
  required String toolCallId,
  required String conversationId,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ListView(
          children: [
            PhoneAgentApprovalCard(
              toolCallId: toolCallId,
              conversationId: conversationId,
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 轮询读树，直到前台包名等于 [packageName]（读树成功）或身份里就是它。
Future<bool> _waitForForegroundPackage(
  PhoneAgentService service, {
  required String packageName,
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final payload = _payload(await _tryTree(service));
    if (payload['error'] == null) {
      final tree = payload['result'];
      if (tree is Map && tree['package_name'] == packageName) return true;
    } else if (payload['error'] == 'permission_required') {
      final identity = payload['identity'];
      if (identity is Map && identity['package_name'] == packageName) return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1000));
  }
  return false;
}

Future<Object?> _tree(PhoneAgentService service) =>
    PhoneAgentTools.handleCall(
      name: PhoneAgentToolNames.tree,
      args: const <String, dynamic>{'offset': 0},
      service: service,
      supportsImageInput: true,
    );

Future<Object?> _tryTree(PhoneAgentService service) async {
  try {
    return await _tree(service);
  } catch (error) {
    debugPrint('PHONE_AGENT_APPROVAL_TREE_PROBE: threw $error');
    return null;
  }
}

Map<String, dynamic> _payload(Object? result) {
  if (result == null) fail('工具没有返回结果。');
  final content = ClientToolResult.fromHandler(result).content;
  final decoded = jsonDecode(content.split('\n').first);
  if (decoded is Map<String, dynamic>) return decoded;
  fail('工具结果不是预期的 JSON 信封：$decoded');
}

void _hostStep(String marker, String instruction) {
  debugPrint('$marker: $instruction');
}
