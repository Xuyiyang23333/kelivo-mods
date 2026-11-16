import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:kelivo_phone_agent/kelivo_phone_agent.dart';

import '../../utils/mcp_structured_image.dart';

/// Native screenshot normalized for the Kelivo adapter.
///
/// The plugin types stay behind [PhoneAgentClient] so tests and the tool layer
/// never depend on channel wire details.
class PhoneAgentCapture {
  const PhoneAgentCapture({
    required this.bytes,
    required this.imageWidth,
    required this.imageHeight,
    required this.screenWidth,
    required this.screenHeight,
    this.packageName,
  });

  final Uint8List bytes;
  final int imageWidth;
  final int imageHeight;
  final int screenWidth;
  final int screenHeight;
  final String? packageName;
}

/// Native service availability normalized for the adapter.
class PhoneAgentAvailability {
  const PhoneAgentAvailability({
    required this.supported,
    required this.enabled,
    required this.connected,
    required this.androidSdkInt,
  });

  final bool supported;
  final bool enabled;
  final bool connected;
  final int androidSdkInt;

  bool get ready => enabled && connected;
}

/// Structured failure returned to the model as a tool error.
class PhoneAgentToolFailure implements Exception {
  const PhoneAgentToolFailure(
    this.code,
    this.message, {
    this.instruction,
    this.identity,
  });

  final String code;
  final String message;
  final String? instruction;

  /// `permission_required` 的应用身份。只有该错误码会带它；其余错误为 null。
  ///
  /// 它进入工具结果的 `identity` 字段，聊天卡片据此渲染批准卡片。字段严格限于
  /// plan 7.5.4 允许的身份（包名、签名前缀、可选显示名），不含界面内容。
  final PhoneAgentPermissionIdentity? identity;

  ClientToolResult toToolResult({required String tool}) {
    return ClientToolResult(
      jsonEncode(<String, dynamic>{
        'type': 'tool_error',
        'error': code,
        'message': message,
        if (instruction != null) 'instruction': instruction,
        if (identity != null)
          'identity': <String, dynamic>{
            'package_name': identity!.packageName,
            'signing_prefix': identity!.signingPrefix,
            if (identity!.displayName != null) 'display_name': identity!.displayName,
            'observation': identity!.observation,
          },
        'tool': tool,
      }),
    );
  }

  @override
  String toString() => 'PhoneAgentToolFailure($code): $message';
}

/// Execution surface of the independent `kelivo_phone_agent` plugin.
abstract interface class PhoneAgentClient {
  Future<PhoneAgentAvailability> status();

  Future<void> openAccessibilitySettings();

  Future<PhoneAgentCapture> screenshot();

  /// Drop the native screenshot observation so coordinates from a screenshot
  /// that never reached the model cannot be used afterwards.
  Future<void> clearScreenshot();

  Future<Map<String, dynamic>> readTree({
    int offset = 0,
    int maxNodes = 120,
    bool interactiveOnly = false,
  });

  Future<Map<String, dynamic>> input(Map<String, dynamic> arguments);

  /// 已获用户批准的应用；白名单管理页据此渲染。
  Future<List<PhoneAgentApprovedApp>> approvedApps();

  /// 撤销一条批准记录。撤销立即生效：下一次判定重新读存储。
  Future<void> revokeApp(String packageName);

  /// 创建一条待用户处理的批准请求（原生同时发通知）。
  ///
  /// [approvalAssistantId] 是创建请求时的助手快照，作为“首次批准来源”写入白名单；
  /// 它与审计用的实时助手 id 语义不同、键名也不同。
  Future<PhoneAgentApprovalRequest> requestApproval(
    String packageName, {
    String? toolCallId,
    String? conversationId,
    String? approvalAssistantId,
  });

  /// 当前仍待处理的批准请求。
  Future<List<PhoneAgentApprovalRequest>> approvalRequests();

  /// 处理一条批准请求，返回处理后的状态。幂等。
  Future<PhoneAgentApprovalRequest> resolveApproval({
    required String requestId,
    required bool approve,
  });

  /// 清理待处理请求（切换会话或应用重启）。
  Future<void> dismissApprovals({String? conversationId});

  /// 首次启用隐私确认是否已读（方案 B，仅首次提示一次）。
  Future<bool> privacyNoticeAcknowledged();

  /// 记录用户已读首次启用隐私确认。只是告知记录，不改变任何判定。
  Future<void> acknowledgePrivacyNotice();
}

/// Optional capability: forward the executor identity that native code writes
/// into its local audit metadata.
///
/// Audit identity is deliberately **not** part of [PhoneAgentClient]: a client
/// that cannot carry it simply leaves the columns empty, and native code records
/// them as unknown instead of inventing a value. Only the production client
/// implements this.
abstract interface class PhoneAgentAuditedClient implements PhoneAgentClient {
  Future<PhoneAgentCapture> screenshotAudited({
    String? assistantId,
    String? conversationId,
  });

  Future<Map<String, dynamic>> readTreeAudited({
    int offset = 0,
    int maxNodes = 120,
    bool interactiveOnly = false,
    String? assistantId,
    String? conversationId,
  });

  Future<Map<String, dynamic>> inputAudited(
    Map<String, dynamic> arguments, {
    String? assistantId,
    String? conversationId,
  });
}

class PluginPhoneAgentClient implements PhoneAgentAuditedClient {
  const PluginPhoneAgentClient();

  @override
  Future<PhoneAgentAvailability> status() async {
    final status = await KelivoPhoneAgent.instance.status();
    return PhoneAgentAvailability(
      supported: status.supported,
      enabled: status.enabled,
      connected: status.connected,
      androidSdkInt: status.androidSdkInt,
    );
  }

  @override
  Future<void> openAccessibilitySettings() =>
      KelivoPhoneAgent.instance.openAccessibilitySettings();

  @override
  Future<PhoneAgentCapture> screenshot() =>
      screenshotAudited();

  @override
  Future<PhoneAgentCapture> screenshotAudited({
    String? assistantId,
    String? conversationId,
  }) async {
    final capture = await KelivoPhoneAgent.instance.screenshot(
      assistantId: assistantId,
      conversationId: conversationId,
    );
    return PhoneAgentCapture(
      bytes: capture.bytes,
      imageWidth: capture.imageWidth,
      imageHeight: capture.imageHeight,
      screenWidth: capture.screenWidth,
      screenHeight: capture.screenHeight,
      packageName: capture.packageName,
    );
  }

  @override
  Future<void> clearScreenshot() => KelivoPhoneAgent.instance.clearScreenshot();

  @override
  Future<Map<String, dynamic>> readTree({
    int offset = 0,
    int maxNodes = 120,
    bool interactiveOnly = false,
  }) {
    return KelivoPhoneAgent.instance.readTree(
      offset: offset,
      maxNodes: maxNodes,
      interactiveOnly: interactiveOnly,
    );
  }

  @override
  Future<Map<String, dynamic>> readTreeAudited({
    int offset = 0,
    int maxNodes = 120,
    bool interactiveOnly = false,
    String? assistantId,
    String? conversationId,
  }) {
    return KelivoPhoneAgent.instance.readTree(
      offset: offset,
      maxNodes: maxNodes,
      interactiveOnly: interactiveOnly,
      assistantId: assistantId,
      conversationId: conversationId,
    );
  }

  @override
  Future<Map<String, dynamic>> input(Map<String, dynamic> arguments) =>
      KelivoPhoneAgent.instance.input(arguments);

  @override
  Future<Map<String, dynamic>> inputAudited(
    Map<String, dynamic> arguments, {
    String? assistantId,
    String? conversationId,
  }) => KelivoPhoneAgent.instance.input(
    arguments,
    assistantId: assistantId,
    conversationId: conversationId,
  );

  @override
  Future<List<PhoneAgentApprovedApp>> approvedApps() =>
      KelivoPhoneAgent.instance.approvedApps();

  @override
  Future<void> revokeApp(String packageName) =>
      KelivoPhoneAgent.instance.revokeApp(packageName);

  @override
  Future<PhoneAgentApprovalRequest> requestApproval(
    String packageName, {
    String? toolCallId,
    String? conversationId,
    String? approvalAssistantId,
  }) => KelivoPhoneAgent.instance.requestApproval(
    packageName,
    toolCallId: toolCallId,
    conversationId: conversationId,
    approvalAssistantId: approvalAssistantId,
  );

  @override
  Future<List<PhoneAgentApprovalRequest>> approvalRequests() =>
      KelivoPhoneAgent.instance.approvalRequests();

  @override
  Future<PhoneAgentApprovalRequest> resolveApproval({
    required String requestId,
    required bool approve,
  }) => KelivoPhoneAgent.instance.resolveApproval(
    requestId: requestId,
    approve: approve,
  );

  @override
  Future<void> dismissApprovals({String? conversationId}) =>
      KelivoPhoneAgent.instance.dismissApprovals(
        conversationId: conversationId,
      );

  @override
  Future<bool> privacyNoticeAcknowledged() =>
      KelivoPhoneAgent.instance.privacyNoticeAcknowledged();

  @override
  Future<void> acknowledgePrivacyNotice() =>
      KelivoPhoneAgent.instance.acknowledgePrivacyNotice();
}

/// Kelivo-side adapter around the independent phone agent plugin.
class PhoneAgentService {
  PhoneAgentService({
    this.client = const PluginPhoneAgentClient(),
    this.timeout = const Duration(seconds: 35),
  });

  static final PhoneAgentService instance = PhoneAgentService();

  final PhoneAgentClient client;
  final Duration timeout;

  Future<PhoneAgentAvailability> status() => _run(client.status, 'status');

  Future<void> openAccessibilitySettings() =>
      _run(client.openAccessibilitySettings, 'open accessibility settings');

  /// Screenshot with optional audit identity.
  ///
  /// [assistantId] / [conversationId] only feed the native audit metadata. They
  /// never reach the model, the tool result, or any upload; a client that cannot
  /// carry them leaves the columns unknown rather than inventing a value.
  Future<PhoneAgentCapture> screenshot({
    String? assistantId,
    String? conversationId,
  }) {
    final audited = client;
    return _run(
      () => audited is PhoneAgentAuditedClient
          ? audited.screenshotAudited(
              assistantId: assistantId,
              conversationId: conversationId,
            )
          : audited.screenshot(),
      'screenshot',
    );
  }

  Future<void> clearScreenshot() =>
      _run(client.clearScreenshot, 'clear the screenshot observation');

  Future<List<PhoneAgentApprovedApp>> approvedApps() =>
      _run(client.approvedApps, 'read the approved apps');

  Future<void> revokeApp(String packageName) =>
      _run(() => client.revokeApp(packageName), 'revoke the app');

  Future<PhoneAgentApprovalRequest> requestApproval(
    String packageName, {
    String? toolCallId,
    String? conversationId,
    String? assistantId,
  }) {
    return _run(
      () => client.requestApproval(
        packageName,
        toolCallId: toolCallId,
        conversationId: conversationId,
        assistantId: assistantId,
      ),
      'create the approval request',
    );
  }

  Future<List<PhoneAgentApprovalRequest>> approvalRequests() =>
      _run(client.approvalRequests, 'read the approval requests');

  Future<PhoneAgentApprovalRequest> resolveApproval({
    required String requestId,
    required bool approve,
  }) {
    return _run(
      () => client.resolveApproval(requestId: requestId, approve: approve),
      'resolve the approval request',
    );
  }

  Future<void> dismissApprovals({String? conversationId}) => _run(
    () => client.dismissApprovals(conversationId: conversationId),
    'dismiss the approval requests',
  );

  Future<bool> privacyNoticeAcknowledged() =>
      _run(client.privacyNoticeAcknowledged, 'read the privacy notice state');

  Future<void> acknowledgePrivacyNotice() => _run(
    client.acknowledgePrivacyNotice,
    'record the privacy notice state',
  );

  Future<Map<String, dynamic>> readTree({
    int offset = 0,
    int maxNodes = 120,
    bool interactiveOnly = false,
    String? assistantId,
    String? conversationId,
  }) {
    final audited = client;
    return _run(
      () => audited is PhoneAgentAuditedClient
          ? audited.readTreeAudited(
              offset: offset,
              maxNodes: maxNodes,
              interactiveOnly: interactiveOnly,
              assistantId: assistantId,
              conversationId: conversationId,
            )
          : audited.readTree(
              offset: offset,
              maxNodes: maxNodes,
              interactiveOnly: interactiveOnly,
            ),
      'read the screen tree',
    );
  }

  Future<Map<String, dynamic>> input(
    Map<String, dynamic> arguments, {
    String? assistantId,
    String? conversationId,
  }) {
    final audited = client;
    return _run(
      () => audited is PhoneAgentAuditedClient
          ? audited.inputAudited(
              arguments,
              assistantId: assistantId,
              conversationId: conversationId,
            )
          : audited.input(arguments),
      'input',
    );
  }

  Future<T> _run<T>(Future<T> Function() call, String operation) async {
    try {
      return await call().timeout(timeout);
    } on PhoneAgentToolFailure {
      rethrow;
    } on TimeoutException {
      throw PhoneAgentToolFailure(
        'timeout',
        'The phone agent $operation call did not finish within '
            '${timeout.inSeconds} seconds.',
        instruction:
            'Do not repeat the call immediately. Ask the user to check that the '
            'screen is unlocked and the Phone Agent accessibility service is '
            'enabled, then retry.',
      );
    } on PhoneAgentException catch (error) {
      throw PhoneAgentToolFailure(
        error.code,
        error.message,
        instruction:
            'Follow the error message. If the service is unavailable, ask the '
            'user to enable the Kelivo Phone Agent accessibility service in '
            'Android settings.',
        identity: error.permissionIdentity,
      );
    } on MissingPluginException {
      throw const PhoneAgentToolFailure(
        'plugin_unavailable',
        'The Kelivo Phone Agent plugin is not available in this build.',
        instruction:
            'Phone Agent tools require the Android build with the '
            'kelivo_phone_agent plugin. Use another tool or inform the user.',
      );
    } on PlatformException catch (error) {
      throw PhoneAgentToolFailure(
        error.code.isEmpty ? 'platform_error' : error.code,
        error.message ?? 'The phone agent channel call failed.',
        instruction:
            'Retry only after correcting the request, or ask the user to check '
            'the Phone Agent accessibility service.',
      );
    } catch (error) {
      throw PhoneAgentToolFailure(
        'phone_agent_error',
        'The phone agent $operation call failed: $error',
        instruction:
            'Do not retry the same call blindly. Inform the user if the error '
            'persists.',
      );
    }
  }
}
