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

  Future<PhoneAgentScreenshot> screenshot() async {
    final map = await _invokeMap('screenshot');
    return PhoneAgentScreenshot.fromMap(map);
  }

  /// 清空原生侧最近一次截图坐标观测。适配层在图片落盘失败时调用。
  Future<void> clearScreenshot() async {
    await _invoke('clearScreenshot');
  }

  Future<Map<String, dynamic>> readTree({
    int offset = 0,
    int maxNodes = 120,
    bool interactiveOnly = false,
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
    });
  }

  Future<Map<String, dynamic>> input(Map<String, dynamic> arguments) async {
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
    return _invokeMap('input', Map<String, dynamic>.from(arguments));
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
}
