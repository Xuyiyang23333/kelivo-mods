import 'package:Kelivo/features/phone_agent/phone_agent_approval_service.dart';
import 'package:Kelivo/features/phone_agent/phone_agent_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelivo_phone_agent/kelivo_phone_agent.dart';

import 'phone_agent_test_support.dart';

const PhoneAgentPermissionIdentity _identity = PhoneAgentPermissionIdentity(
  packageName: 'com.example.app',
  signingPrefix: 'aaaaaaaa',
  signingAvailable: true,
  displayName: 'Example',
  observation: true,
);

void main() {
  late RecordingPhoneAgentClient client;
  late PhoneAgentService service;
  late PhoneAgentApprovalService approvals;

  setUp(() {
    client = RecordingPhoneAgentClient();
    service = PhoneAgentService(client: client);
    approvals = PhoneAgentApprovalService(
      service: service,
      sweepInterval: const Duration(hours: 1),
    );
    PhoneAgentApprovalService.instance.registerResumeHandler(null);
  });

  tearDown(() {
    approvals.dispose();
    PhoneAgentApprovalService.instance.registerResumeHandler(null);
  });

  test('registering a permission_required identity creates a pending request',
      () async {
    final entry = await approvals.register(
      _identity,
      toolCallId: 'call-1',
      conversationId: 'c1',
      approvalAssistantId: 'a1',
    );

    expect(entry, isNotNull);
    expect(approvals.hasPending, isTrue);
    expect(entry!.packageName, 'com.example.app');
    expect(entry.signingPrefix, 'aaaaaaaa');
    expect(entry.displayName, 'Example');

    final found = approvals.pendingFor(toolCallId: 'call-1', conversationId: 'c1');
    expect(found, isNotNull);
    expect(found!.requestId, entry.requestId);
  });

  test('an identity without a signing certificate never creates a card', () async {
    final entry = await approvals.register(
      const PhoneAgentPermissionIdentity(
        packageName: 'com.example.app',
        signingPrefix: null,
        signingAvailable: false,
      ),
      toolCallId: 'call-1',
    );

    expect(entry, isNull);
    expect(approvals.hasPending, isFalse);
    expect(client.approvalRequestsResult, isEmpty);
  });

  test('pendingFor ignores a different conversation', () async {
    await approvals.register(
      _identity,
      toolCallId: 'call-1',
      conversationId: 'c1',
    );

    expect(
      approvals.pendingFor(toolCallId: 'call-1', conversationId: 'c2'),
      isNull,
    );
  });

  test('approving writes the grant and clears the pending entry', () async {
    final entry = await approvals.register(
      _identity,
      toolCallId: 'call-1',
      conversationId: 'c1',
    );

    final outcome = await approvals.resolve(entry!.requestId, approve: true);

    expect(outcome, PhoneAgentResumeOutcome.approvalOnly);
    expect(approvals.hasPending, isFalse);
  });

  test('denying clears the entry and reports no resume', () async {
    final entry = await approvals.register(_identity, toolCallId: 'call-1');

    final outcome = await approvals.resolve(entry!.requestId, approve: false);

    // 拒绝必须区别于“已批准但无法续跑”：否则界面会显示成功。
    expect(outcome, PhoneAgentResumeOutcome.denied);
    expect(approvals.hasPending, isFalse);
    expect(approvals.pendingFor(toolCallId: 'call-1'), isNull);
  });

  test('allow and continue resumes only when an approved handler exists',
      () async {
    final entry = await approvals.register(
      _identity,
      toolCallId: 'call-1',
      conversationId: 'c1',
    );
    final resumed = <String>[];
    approvals.registerResumeHandler((conversationId, packageName) async {
      resumed.add('$conversationId:$packageName');
    });

    final outcome = await approvals.resolve(
      entry!.requestId,
      approve: true,
      resume: true,
    );
    await approvals.requestResume('c1', entry.packageName);

    expect(outcome, PhoneAgentResumeOutcome.resumed);
    expect(resumed, <String>['c1:com.example.app']);
  });

  test('resume without a registered handler degrades to approval only',
      () async {
    final entry = await approvals.register(
      _identity,
      toolCallId: 'call-1',
      conversationId: 'c1',
    );

    final outcome = await approvals.resolve(
      entry!.requestId,
      approve: true,
      resume: true,
    );

    expect(outcome, PhoneAgentResumeOutcome.approvalOnly);
    expect(approvals.hasResumeHandler, isFalse);
  });

  test('a denied request is never reported as resumed', () async {
    final entry = await approvals.register(_identity, toolCallId: 'call-1');

    final outcome = await approvals.resolve(
      entry!.requestId,
      approve: false,
      resume: true,
    );

    expect(outcome, PhoneAgentResumeOutcome.denied);
  });

  test('refresh adopts native pending requests and drops resolved ones',
      () async {
    final entry = await approvals.register(
      _identity,
      toolCallId: 'call-1',
      conversationId: 'c1',
    );
    await approvals.refresh();
    expect(approvals.hasPending, isTrue);

    client.approvalRequestsResult.clear();
    await approvals.refresh();

    expect(approvals.hasPending, isFalse);
    expect(approvals.pendingFor(toolCallId: 'call-1'), isNull);
    expect(entry, isNotNull);
  });

  test('dismissing a conversation clears only that conversation', () async {
    await approvals.register(_identity, toolCallId: 'c1', conversationId: 'c1');
    await approvals.register(
      const PhoneAgentPermissionIdentity(
        packageName: 'com.example.other',
        signingPrefix: 'bbbbbbbb',
        signingAvailable: true,
      ),
      toolCallId: 'c2',
      conversationId: 'c2',
    );

    await approvals.dismissForConversation('c1');

    expect(approvals.pendingFor(toolCallId: 'c1'), isNull);
    expect(approvals.pendingFor(toolCallId: 'c2'), isNotNull);
    expect(client.dismissedConversations, contains('c1'));
  });

  test('an expired request is swept locally without notifying the model',
      () async {
    approvals.dispose();
    approvals = PhoneAgentApprovalService(
      service: service,
      sweepInterval: const Duration(milliseconds: 10),
    );
    client.approvalRequestsResult.add(
      PhoneAgentApprovalRequest(
        requestId: 'expired',
        packageName: 'com.example.app',
        signingPrefix: 'aaaaaaaa',
        signingAvailable: true,
        toolCallId: 'call-1',
        conversationId: 'c1',
        createdAt: 0,
        expiresAt: DateTime.now().millisecondsSinceEpoch - 1,
        state: 'pending',
      ),
    );
    await approvals.refresh();
    expect(approvals.hasPending, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(approvals.hasPending, isFalse);
  });

  test('the tool failure carries the structured identity into the tool result',
      () async {
    const failure = PhoneAgentToolFailure(
      'permission_required',
      'Reading com.example.app needs approval.',
      identity: _identity,
    );

    final decoded = decodeToolResult(
      failure.toToolResult(tool: 'phone_agent_tree'),
    );

    expect(decoded['error'], 'permission_required');
    final identity = decoded['identity'] as Map<String, dynamic>;
    expect(identity['package_name'], 'com.example.app');
    expect(identity['signing_prefix'], 'aaaaaaaa');
    expect(identity['display_name'], 'Example');
    expect(identity['observation'], isTrue);
    expect(identity.containsKey('nodes'), isFalse);
  });

  test('errors without an identity add no identity field', () async {
    const failure = PhoneAgentToolFailure('no_window', 'Nothing to read.');

    final decoded = decodeToolResult(
      failure.toToolResult(tool: 'phone_agent_tree'),
    );

    expect(decoded.containsKey('identity'), isFalse);
  });
  test('a failed native write reports failed, never approvalOnly', () async {
    final entry = await approvals.register(_identity, toolCallId: 'call-1');
    client.resolveOutcomeState = 'failed';
    client.resolveFailureReason = 'signing_mismatch';

    final outcome = await approvals.resolve(entry!.requestId, approve: true);

    expect(outcome, PhoneAgentResumeOutcome.failed);
  });

  test('a denied request reports denied', () async {
    final entry = await approvals.register(_identity, toolCallId: 'call-1');

    final outcome = await approvals.resolve(entry!.requestId, approve: false);

    expect(outcome, PhoneAgentResumeOutcome.denied);
  });

  test('switching conversation dismisses only the previous conversation', () async {
    await approvals.register(_identity, toolCallId: 'c1', conversationId: 'c1');
    await approvals.register(
      const PhoneAgentPermissionIdentity(
        packageName: 'com.example.other',
        signingPrefix: 'bbbbbbbb',
        signingAvailable: true,
      ),
      toolCallId: 'c2',
      conversationId: 'c2',
    );

    await approvals.onForegroundConversationChanged('c1');
    await approvals.onForegroundConversationChanged('c2');

    expect(approvals.pendingFor(toolCallId: 'c1'), isNull);
    expect(approvals.pendingFor(toolCallId: 'c2'), isNotNull);
    expect(client.dismissedConversations, contains('c1'));
  });

  test('a refresh failure keeps pending cards instead of clearing them', () async {
    await approvals.register(_identity, toolCallId: 'call-1');
    client.approvalRequestsError = Exception('channel down');

    await approvals.refresh();

    expect(approvals.hasPending, isTrue);
  });

  test('service disconnect clears every pending request', () async {
    await approvals.register(_identity, toolCallId: 'call-1');

    await approvals.onServiceDisconnected();

    expect(approvals.hasPending, isFalse);
  });
}
