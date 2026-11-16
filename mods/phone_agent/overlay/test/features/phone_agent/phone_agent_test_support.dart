import 'dart:convert';

import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/models/model_spec.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/chat_api_helpers.dart';
import 'package:Kelivo/features/home/services/local_tools_service.dart';
import 'package:Kelivo/features/phone_agent/phone_agent_local_tool.dart';
import 'package:Kelivo/features/phone_agent/phone_agent_service.dart';
import 'package:Kelivo/modding/tool_mod.dart';
import 'package:Kelivo/utils/mcp_structured_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelivo_phone_agent/kelivo_phone_agent.dart';

import '../../support/business_test_harness.dart';

const Assistant enabledAssistant = Assistant(
  id: 'phone',
  name: 'Phone',
  localToolIds: <String>[PhoneAgentLocalTool.id],
);

const Assistant nativeAssistant = Assistant(
  id: 'phone',
  name: 'Phone',
  localToolIds: <String>[LocalToolNames.phoneControl],
);

const Assistant conflictAssistant = Assistant(
  id: 'phone',
  name: 'Phone',
  localToolIds: <String>[LocalToolNames.phoneControl, PhoneAgentLocalTool.id],
);

const Assistant disabledAssistant = Assistant(id: 'phone', name: 'Phone');

void runOnAndroid() {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
}

void runOnIos() {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
}

Future<SettingsProvider> createTestSettings() async {
  final settings = SettingsProvider(createBusinessTestPreferences());
  await settings.loaded;
  addTearDown(settings.dispose);
  return settings;
}

ModToolDefinitionContext definitionContextFor(
  SettingsProvider settings, {
  Assistant? assistant = enabledAssistant,
  bool supportsTools = true,
  bool supportsImageInput = true,
  String? conversationId = 'conv',
}) {
  return ModToolDefinitionContext(
    settings: settings,
    assistant: assistant,
    providerKey: 'test',
    modelId: 'test',
    conversationId: conversationId,
    supportsTools: supportsTools,
    inputModalities: supportsImageInput
        ? const <Modality>[Modality.text, Modality.image]
        : const <Modality>[Modality.text],
  );
}

ModToolExecutionContext executionContextFor({
  required ToolCallHandler originalHandler,
  Assistant? assistant = enabledAssistant,
  Assistant? Function()? readCurrentAssistant,
  String? conversationId = 'conv',
}) {
  return ModToolExecutionContext(
    assistant: assistant,
    conversationId: conversationId,
    approvalService: null,
    askUserService: null,
    originalHandler: originalHandler,
    readCurrentAssistant: readCurrentAssistant ?? () => assistant,
  );
}

Map<String, dynamic> functionDefinition(String name) {
  return <String, dynamic>{
    'type': 'function',
    'function': <String, dynamic>{
      'name': name,
      'parameters': <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{},
      },
    },
  };
}

List<String> definitionNames(List<Map<String, dynamic>> definitions) {
  return <String>[
    for (final definition in definitions)
      if (definition['function'] case final Map function)
        if (function['name'] case final String name) name,
  ];
}

Map<String, dynamic> decodeToolResult(Object? result) {
  expect(result, isA<ClientToolResult>());
  final content = (result as ClientToolResult).content;
  final decoded = jsonDecode(content);
  expect(decoded, isA<Map<String, dynamic>>());
  return decoded as Map<String, dynamic>;
}

class RecordingPhoneAgentClient implements PhoneAgentClient {
  PhoneAgentAvailability availability = const PhoneAgentAvailability(
    supported: true,
    enabled: true,
    connected: true,
    androidSdkInt: 34,
  );
  PhoneAgentCapture capture = PhoneAgentCapture(
    bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
    imageWidth: 100,
    imageHeight: 200,
    screenWidth: 1080,
    screenHeight: 2160,
    packageName: 'com.psyche.kelivo',
  );
  Map<String, dynamic> treeResult = <String, dynamic>{
    'nodes': <Map<String, dynamic>>[
      <String, dynamic>{'id': 'n0', 'text': 'Hello'},
    ],
    'has_more': false,
  };
  Map<String, dynamic> inputResult = <String, dynamic>{'ok': true};

  Object? screenshotError;
  Object? clearScreenshotError;
  Object? treeError;
  Object? inputError;
  Object? statusError;
  Object? openSettingsError;

  Duration treeDelay = Duration.zero;

  int statusCalls = 0;
  int openSettingsCalls = 0;
  int screenshotCalls = 0;
  int clearScreenshotCalls = 0;
  final List<({int offset, int maxNodes, bool interactiveOnly})> treeCalls =
      <({int offset, int maxNodes, bool interactiveOnly})>[];
  final List<Map<String, dynamic>> inputCalls = <Map<String, dynamic>>[];

  /// 白名单与批准请求的假实现状态，供 Mods 页与批准服务测试使用。
  final List<PhoneAgentApprovedApp> approvedAppsResult =
      <PhoneAgentApprovedApp>[];
  final List<PhoneAgentApprovalRequest> approvalRequestsResult =
      <PhoneAgentApprovalRequest>[];
  final List<String> revokedPackages = <String>[];
  final List<String?> dismissedConversations = <String?>[];
  bool privacyAcknowledged = false;
  int acknowledgeCalls = 0;
  String? requestedSigningPrefix = 'aaaaaaaa';
  String? requestedDisplayName = 'Example';

  @override
  Future<PhoneAgentAvailability> status() async {
    statusCalls++;
    final error = statusError;
    if (error != null) throw error;
    return availability;
  }

  @override
  Future<void> openAccessibilitySettings() async {
    openSettingsCalls++;
    final error = openSettingsError;
    if (error != null) throw error;
  }

  @override
  Future<PhoneAgentCapture> screenshot() async {
    screenshotCalls++;
    final error = screenshotError;
    if (error != null) throw error;
    return capture;
  }

  @override
  Future<void> clearScreenshot() async {
    clearScreenshotCalls++;
    final error = clearScreenshotError;
    if (error != null) throw error;
  }

  @override
  Future<Map<String, dynamic>> readTree({
    int offset = 0,
    int maxNodes = 120,
    bool interactiveOnly = false,
  }) async {
    treeCalls.add((
      offset: offset,
      maxNodes: maxNodes,
      interactiveOnly: interactiveOnly,
    ));
    if (treeDelay > Duration.zero) await Future<void>.delayed(treeDelay);
    final error = treeError;
    if (error != null) throw error;
    return treeResult;
  }

  @override
  Future<Map<String, dynamic>> input(Map<String, dynamic> arguments) async {
    inputCalls.add(Map<String, dynamic>.from(arguments));
    final error = inputError;
    if (error != null) throw error;
    return inputResult;
  }

  @override
  Future<List<PhoneAgentApprovedApp>> approvedApps() async =>
      List<PhoneAgentApprovedApp>.of(approvedAppsResult);

  @override
  Future<void> revokeApp(String packageName) async {
    revokedPackages.add(packageName);
    approvedAppsResult.removeWhere((app) => app.packageName == packageName);
  }

  @override
  Future<PhoneAgentApprovalRequest> requestApproval(
    String packageName, {
    String? toolCallId,
    String? conversationId,
    String? assistantId,
  }) async {
    final request = PhoneAgentApprovalRequest(
      requestId: 'r${approvalRequestsResult.length + 1}',
      packageName: packageName,
      signingPrefix: requestedSigningPrefix,
      signingAvailable: requestedSigningPrefix != null,
      displayName: requestedDisplayName,
      toolCallId: toolCallId,
      conversationId: conversationId,
      assistantId: assistantId,
      createdAt: 0,
      expiresAt: DateTime.now().millisecondsSinceEpoch + 60000,
      state: 'pending',
    );
    approvalRequestsResult.add(request);
    return request;
  }

  @override
  Future<List<PhoneAgentApprovalRequest>> approvalRequests() async =>
      List<PhoneAgentApprovalRequest>.of(approvalRequestsResult);

  @override
  Future<PhoneAgentApprovalRequest> resolveApproval({
    required String requestId,
    required bool approve,
  }) async {
    final index = approvalRequestsResult.indexWhere(
      (entry) => entry.requestId == requestId,
    );
    if (index < 0) {
      throw const PhoneAgentToolFailure(
        'approval_not_found',
        'This approval request is no longer pending.',
      );
    }
    final resolved = approvalRequestsResult[index].copyWith(
      state: approve ? 'approved' : 'denied',
    );
    approvalRequestsResult.removeAt(index);
    return resolved;
  }

  @override
  Future<void> dismissApprovals({String? conversationId}) async {
    dismissedConversations.add(conversationId);
    approvalRequestsResult.removeWhere(
      (entry) =>
          conversationId == null || entry.conversationId == conversationId,
    );
  }

  @override
  Future<bool> privacyNoticeAcknowledged() async => privacyAcknowledged;

  @override
  Future<void> acknowledgePrivacyNotice() async {
    privacyAcknowledged = true;
    acknowledgeCalls++;
  }
}
