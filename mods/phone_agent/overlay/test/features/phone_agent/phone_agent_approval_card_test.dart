import 'package:Kelivo/features/home/services/tool_approval_service.dart';
import 'package:Kelivo/features/phone_agent/phone_agent_approval_card.dart';
import 'package:Kelivo/features/phone_agent/phone_agent_approval_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelivo_phone_agent/kelivo_phone_agent.dart';
import 'package:provider/provider.dart';

/// 卡片的存在性不能依赖上游设置（`showToolResultSummary` 默认 false）或图片。
/// 这里锁定两条：**默认设置下能渲染**、**请求消失后不留占位**。
///
/// 卡片读的是生产单例 `PhoneAgentApprovalService.instance`，因此测试劫持插件通道
/// （`kelivo/phone_agent`）而不是替换单例：走的是与真实运行一致的路径。
void main() {
  const channel = MethodChannel('kelivo/phone_agent');
  final pending = <Map<String, dynamic>>[];
  var nextId = 0;
  String resolveState = 'approved';
  String? resolveFailureReason;

  Map<String, dynamic> request(String packageName, String toolCallId) {
    final id = 'r${++nextId}';
    final map = <String, dynamic>{
      'request_id': id,
      'package_name': packageName,
      'signing_prefix': 'aaaaaaaa',
      'signing_available': true,
      'display_name': 'Example',
      'tool_call_id': toolCallId,
      'conversation_id': 'c1',
      'approval_assistant_id': null,
      'created_at': 0,
      'expires_at':
          DateTime.now().millisecondsSinceEpoch + 30 * 60 * 1000,
      'state': 'pending',
    };
    pending.add(map);
    return map;
  }

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
              return request(
                args['package_name'] as String,
                (args['tool_call_id'] as String?) ?? '',
              );
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

  tearDown(() async {
    // 卡片会为 pending 请求启动 20 秒 TTL 清扫 timer；测试结束前清掉，避免
    // “timers pending” 断言。
    await PhoneAgentApprovalService.instance.dismissAll();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    PhoneAgentApprovalService.instance.registerResumeHandler(null);
  });

  Future<void> pumpCard(WidgetTester tester, {required Widget child}) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ToolApprovalService>(
            create: (_) => ToolApprovalService(),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
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


  /// 清空单例的 pending 请求，让 20 秒 TTL 清扫 timer 停止（否则 widget 测试会在
  /// 销毁后判定“Timer is still pending”）。
  Future<void> clearPending(WidgetTester tester) async {
    await PhoneAgentApprovalService.instance.dismissAll();
    await tester.pump();
  }

  const card = PhoneAgentApprovalCard(
    toolCallId: 'call-1',
    conversationId: 'c1',
  );

  testWidgets('renders in the default settings when a request is pending', (
    tester,
  ) async {
    await registerCall();

    expect(
      PhoneAgentApprovalCard.pendingExists(
        toolCallId: 'call-1',
        conversationId: 'c1',
      ),
      isTrue,
    );

    await pumpCard(tester, child: card);

    expect(find.text('Allow "Example"?'), findsOneWidget);
    expect(find.text('com.example.app'), findsOneWidget);
    expect(find.textContaining('aaaaaaaa'), findsOneWidget);
    expect(find.text('Allow'), findsOneWidget);
    expect(find.text('Deny'), findsOneWidget);

    await clearPending(tester);
  });

  testWidgets('an unrelated tool call renders nothing', (tester) async {
    await registerCall();

    await pumpCard(
      tester,
      child: const PhoneAgentApprovalCard(
        toolCallId: 'other',
        conversationId: 'c1',
      ),
    );

    expect(find.textContaining('com.example.app'), findsNothing);

    await clearPending(tester);
  });

  testWidgets('denying reports denial and removes the card', (tester) async {
    await registerCall();
    await pumpCard(tester, child: card);

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
    await pumpCard(tester, child: card);

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
    await pumpCard(tester, child: card);

    await tester.tap(find.text('Allow and continue'));
    await tester.pumpAndSettle();

    expect(resumed, <String>['c1:com.example.app']);

    await clearPending(tester);
  });
}
