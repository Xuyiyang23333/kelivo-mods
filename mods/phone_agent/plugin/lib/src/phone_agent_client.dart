import 'dart:async';

import 'package:flutter/services.dart';

import 'phone_agent_types.dart';

/// 独立 MethodChannel 客户端。UI 层通常直接使用 `KelivoPhoneAgent.instance`。
class PhoneAgentClient {
  PhoneAgentClient({
    MethodChannel? channel,
    Duration timeout = const Duration(seconds: 30),
  }) : _channel = channel ?? const MethodChannel(channelName),
       _timeout = timeout;

  static const String channelName = 'kelivo/phone_agent';

  final MethodChannel _channel;
  final Duration _timeout;

  Future<PhoneAgentStatus> status() async {
    final map = await _invokeMap('status');
    return PhoneAgentStatus.fromMap(map);
  }

  Future<void> openAccessibilitySettings() async {
    await _invoke('openAccessibilitySettings');
  }

  Future<PhoneAgentScreenshot> screenshot({
    String? assistantId,
    String? conversationId,
  }) async {
    final map = await _invokeMap(
      'screenshot',
      auditArguments(assistantId, conversationId),
    );
    return PhoneAgentScreenshot.fromMap(map);
  }

  /// 清空原生侧最近一次截图坐标观测。适配层在图片落盘失败时调用。
  Future<void> clearScreenshot() async {
    await _invoke('clearScreenshot');
  }

  /// 读取当前窗口节点。`offset == 0` 创建新观测并重新编号。
  ///
  /// [assistantId] / [conversationId] 只用于原生侧审计元数据；调用方拿不到就传 null，
  /// 原生侧如实记为缺失，不伪造。
  Future<Map<String, dynamic>> readTree({
    int offset = 0,
    int maxNodes = 120,
    bool interactiveOnly = false,
    String? assistantId,
    String? conversationId,
  }) async {
    if (offset < 0) {
      throw const PhoneAgentException(
        'invalid_argument',
        'offset must be zero or greater.',
      );
    }
    if (maxNodes < 1 || maxNodes > 200) {
      throw const PhoneAgentException(
        'invalid_argument',
        'maxNodes must be between 1 and 200.',
      );
    }
    return _invokeMap('readTree', <String, dynamic>{
      'offset': offset,
      'max_nodes': maxNodes,
      'interactive_only': interactiveOnly,
      ...auditArguments(assistantId, conversationId),
    });
  }

  Future<Map<String, dynamic>> input(
    Map<String, dynamic> arguments, {
    String? assistantId,
    String? conversationId,
  }) async {
    if (arguments.containsKey('snapshot_id')) {
      throw const PhoneAgentException(
        'invalid_argument',
        'snapshot_id is not part of the phone agent protocol. '
            'Use node_id from phone_agent_tree or normalized coordinates.',
      );
    }
    final action = arguments['action'];
    if (action is! String || action.isEmpty) {
      throw const PhoneAgentException(
        'invalid_argument',
        'action is required.',
      );
    }
    return _invokeMap('input', <String, dynamic>{
      ...Map<String, dynamic>.from(arguments),
      ...auditArguments(assistantId, conversationId),
    });
  }

  /// 已获用户批准的应用列表（不含构建配置的预批准条目）。
  Future<List<PhoneAgentApprovedApp>> approvedApps() async {
    final map = await _invokeMap('approvedApps');
    final apps = map['apps'];
    if (apps is! List) {
      throw const PhoneAgentException(
        'invalid_response',
        'approvedApps returned an unexpected payload.',
      );
    }
    return apps
        .whereType<Map>()
        .map(
          (entry) =>
              PhoneAgentApprovedApp.fromMap(Map<String, dynamic>.from(entry)),
        )
        .toList(growable: false);
  }

  /// 写入批准记录。原生侧在写入前重新解析当前签名，解析失败或与
  /// [expectedSigningSha256] 不一致都不会写入。
  Future<PhoneAgentApprovedApp> approveApp(
    String packageName, {
    String? sourceAssistantId,
    List<String>? expectedSigningSha256,
  }) async {
    if (packageName.trim().isEmpty) {
      throw const PhoneAgentException(
        'invalid_argument',
        'packageName is required.',
      );
    }
    final map = await _invokeMap('approveApp', <String, dynamic>{
      'package_name': packageName,
      if (sourceAssistantId != null) 'source_assistant_id': sourceAssistantId,
      if (expectedSigningSha256 != null)
        'expected_signing_sha256': expectedSigningSha256,
    });
    return PhoneAgentApprovedApp.fromMap(map);
  }

  /// 撤销批准记录，立即生效。
  Future<void> revokeApp(String packageName) async {
    if (packageName.trim().isEmpty) {
      throw const PhoneAgentException(
        'invalid_argument',
        'packageName is required.',
      );
    }
    await _invoke('revokeApp', <String, dynamic>{'package_name': packageName});
  }

  Future<Map<String, dynamic>> _invokeMap(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    final result = await _invoke(method, arguments);
    if (result is Map) return Map<String, dynamic>.from(result);
    throw PhoneAgentException(
      'invalid_response',
      '$method returned an unexpected payload.',
    );
  }

  Future<Object?> _invoke(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    try {
      return await _channel
          .invokeMethod<Object?>(method, arguments)
          .timeout(_timeout);
    } on TimeoutException {
      throw PhoneAgentException(
        'timeout',
        'The phone agent did not answer $method in time. Check that the '
            'accessibility service is enabled and the phone is unlocked, then '
            'retry.',
      );
    } on MissingPluginException {
      throw const PhoneAgentException(
        'unsupported_platform',
        'The phone agent plugin is not available on this platform.',
      );
    } on PlatformException catch (error) {
      throw PhoneAgentException(
        error.code,
        error.message ?? 'The phone agent failed without a message.',
      );
    }
  }

  /// 审计身份参数。两项都只在非空时发送；原生侧缺失即如实记为未知，
  /// 由原生侧自行截断与清洗，这里不做内容识别。
  static Map<String, dynamic> auditArguments(
    String? assistantId,
    String? conversationId,
  ) {
    return <String, dynamic>{
      if (assistantId != null && assistantId.trim().isNotEmpty)
        'assistant_id': assistantId,
      if (conversationId != null && conversationId.trim().isNotEmpty)
        'conversation_id': conversationId,
    };
  }
}
