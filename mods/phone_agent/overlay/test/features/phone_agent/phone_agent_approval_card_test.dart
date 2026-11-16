import 'dart:convert';

import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/chat/widgets/chat_message_widget.dart';
import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/features/phone_agent/phone_agent_approval_card.dart';
import 'package:Kelivo/features/phone_agent/phone_agent_approval_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelivo_phone_agent/kelivo_phone_agent.dart';
import 'package:provider/provider.dart';

import '../../support/business_test_harness.dart';

/// 卡片必须在**真实渲染路径**上出现：`ChatMessageWidget` 解析工具消息 → 工具步骤
/// → 内容区。直接渲染 `PhoneAgentApprovalCard` 会绕过“内容区是否为 null”的判定，
/// 上一轮正是因此漏网（默认设置下 content 为 null，卡片从不进入 widget 树）。
///
/// 这里锁定：默认设置（`showToolResultSummary=false`、无图片、无上游 pending）下，
/// 工具消息里的批准卡片仍然可见。
void main() {
  const channel = MethodChannel('kelivo/phone_agent');
  final pending = <Map<String, dynamic>>[];
  var nextId = 0;
  String resolveState = 'approved';
  String? resolveFailureReason;

  setUp(() {
    pending.clear();
    nextId = 0;
    resolveState = 'approved';
    resolveFailureReason = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'requestApproval':
              final args = call.arguments as Map;
              final map = <String, dynamic>{
                'request_id': 'r${++nextId}',
                'package_name': args['package_name'],
                'signing_prefix': 'aaaaaaaa',
                'signing_available': true,
                'display_name': 'Example',
                'tool_call_id': args['tool_call_id'],
                'conversation_id': args['conversation_id'],
                'approval_assistant_id': args['approval_assistant_id'],
                'created_at': 0,
                'expires_at':
                    DateTime.now().millisecondsSinceEpoch + 30 * 60 * 1000,
                'state': 'pending',
              };
              pending.add(map);
              return map;
            case 'approvalRequests':
              return <String, dynamic>{
                'requests': pending
                    .where((entry) => entry['state'] == 'pending')
                    .toList(),
              };
            case 'resolveApproval':
              final args = call.arguments as Map;
              final id = args['request_id'] as String;
              final index = pending.indexWhere(
                (entry) => entry['request_id'] == id,
              );
              if (index < 0) {
                throw PlatformException(code: 'approval_not_found');
              }
              final approve = args['approve'] == true;
              final resolved = Map<String, dynamic>.from(pending[index])
                ..['state'] = approve ? resolveState : 'denied'
                ..['failure_reason'] = approve ? resolveFailureReason : null;
              pending.removeAt(index);
              return resolved;
            case 'dismissApprovals':
              pending.clear();
              return <String, dynamic>{'dismissed': true};
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    PhoneAgentApprovalService.instance.registerResumeHandler(null);
  });

  Future<void> clearPending(WidgetTester tester) async {
    await PhoneAgentApprovalService.instance.dismissAll();
    await tester.pump();
  }

  /// 渲染一条真实的工具消息：`_buildToolMessage` 用 `message.id` 作为工具步骤 id，
  /// 因此它必须与登记时的 `toolCallId` 一致。
  Future<SettingsProvider> pumpToolMessage(
    WidgetTester tester, {
    String toolCallId = 'call-1',
  }) async {
    final preferences = createBusinessTestPreferences();
    final settings = SettingsProvider(preferences);
    await settings.loaded;
    addTearDown(settings.dispose);

    final message = ChatMessage(
      id: toolCallId,
      role: 'tool',
      conversationId: 'c1',
      content: jsonEncode(<String, dynamic>{
        'tool': 'phone_agent_tree',
        'arguments': <String, dynamic>{'offset': 0},
        'result':
            '{"type":"tool_error","error":"permission_required",'
            '"tool":"phone_agent_tree"}',
      }),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<ToolApprovalService>(
            create: (_) => ToolApprovalService(),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ListView(
              children: [ChatMessageWidget(message: message)],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return settings;
  }

  Future<void> registerCall({
    String toolCallId = 'call-1',
    String conversationId = 'c1',
  }) async {
    await PhoneAgentApprovalService.instance.register(
      const PhoneAgentPermissionIdentity(
        packageName: 'com.example.app',
        signingPrefix: 'aaaaaaaa',
        signingAvailable: true,
        displayName: 'Example',
      ),
      toolCallId: toolCallId,
      conversationId: conversationId,
    );
  }

  testWidgets(
    'the card is visible through ChatMessageWidget in the default settings',
    (tester) async {
      await registerCall();
      final settings = await pumpToolMessage(tester);

      // 默认设置：不显示工具结果摘要、不隐藏图片——内容区仍须为卡片保留。
      expect(settings.showToolResultSummary, isFalse);

      expect(find.byType(PhoneAgentApprovalCard), findsOneWidget);
      expect(find.text('Allow "Example"?'), findsOneWidget);
      expect(find.text('com.example.app'), findsOneWidget);
      expect(find.textContaining('aaaaaaaa'), findsOneWidget);
      expect(find.text('Allow'), findsOneWidget);
      expect(find.text('Deny'), findsOneWidget);

      await clearPending(tester);
    },
  );

  testWidgets('no card appears for a different tool call id', (tester) async {
    await registerCall(toolCallId: 'other-call');
    await pumpToolMessage(tester);

    expect(find.byType(PhoneAgentApprovalCard), findsOneWidget);
    expect(find.textContaining('com.example.app'), findsNothing);

    await clearPending(tester);
  });

  testWidgets('denying removes the card from the chat message', (tester) async {
    await registerCall();
    await pumpToolMessage(tester);

    await tester.tap(find.text('Deny'));
    await tester.pumpAndSettle();

    expect(find.textContaining('com.example.app'), findsNothing);
    expect(
      PhoneAgentApprovalCard.pendingExists(
        toolCallId: 'call-1',
        conversationId: 'c1',
      ),
      isFalse,
    );

    await clearPending(tester);
  });

  testWidgets('a failed approval never reports success', (tester) async {
    await registerCall();
    resolveState = 'failed';
    resolveFailureReason = 'signing_mismatch';
    await pumpToolMessage(tester);

    await tester.tap(find.text('Allow'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Approved.'), findsNothing);
    expect(find.textContaining('Could not save'), findsOneWidget);

    await clearPending(tester);
  });

  testWidgets('Allow and continue resumes only with a registered handler', (
    tester,
  ) async {
    final resumed = <String>[];
    PhoneAgentApprovalService.instance.registerResumeHandler((
      conversationId,
      packageName,
    ) async {
      resumed.add('$conversationId:$packageName');
    });
    await registerCall();
    await pumpToolMessage(tester);

    await tester.tap(find.text('Allow and continue'));
    await tester.pumpAndSettle();

    expect(resumed, <String>['c1:com.example.app']);

    await clearPending(tester);
  });
  testWidgets('removing the request leaves no residual blank in the tool message', (
    tester,
  ) async {
    await registerCall();
    await pumpToolMessage(tester);

    final heightWithCard = tester.getSize(find.byType(ChatMessageWidget)).height;
    expect(find.byType(PhoneAgentApprovalCard), findsOneWidget);

    // 通知栏批准等外部路径直接改原生状态：本地 refresh 后卡片消失，
    // 内容区必须回到“只有头部”的高度，而不是留一块空白。
    pending.clear();
    await PhoneAgentApprovalService.instance.refresh();
    // 服务层是异步的：让 microtask 与 ListenableBuilder 一起跑完再断言。
    await tester.pump();
    await tester.pumpAndSettle();

    // 卡片 widget 仍挂在树上（内部渲染 SizedBox.shrink），关键是没有残留空白：
    // 消息高度必须收缩回只有头部的高度。
    expect(find.textContaining('com.example.app'), findsNothing);
    final heightWithoutCard = tester
        .getSize(find.byType(ChatMessageWidget))
        .height;
    expect(heightWithoutCard, lessThan(heightWithCard));

    await clearPending(tester);
  });
}
