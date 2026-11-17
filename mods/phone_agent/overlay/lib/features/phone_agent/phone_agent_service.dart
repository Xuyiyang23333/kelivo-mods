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
  const PhoneAgentToolFailure(this.code, this.message, {this.instruction});

  final String code;
  final String message;
  final String? instruction;

  ClientToolResult toToolResult({required String tool}) {
    return ClientToolResult(
      jsonEncode(<String, dynamic>{
        'type': 'tool_error',
        'error': code,
        'message': message,
        if (instruction != null) 'instruction': instruction,
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
}

class PluginPhoneAgentClient implements PhoneAgentClient {
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
  Future<PhoneAgentCapture> screenshot() async {
    final capture = await KelivoPhoneAgent.instance.screenshot();
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
  Future<Map<String, dynamic>> input(Map<String, dynamic> arguments) =>
      KelivoPhoneAgent.instance.input(arguments);
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

  Future<PhoneAgentCapture> screenshot() =>
      _run(client.screenshot, 'screenshot');

  Future<void> clearScreenshot() =>
      _run(client.clearScreenshot, 'clear the screenshot observation');

  Future<Map<String, dynamic>> readTree({
    int offset = 0,
    int maxNodes = 120,
    bool interactiveOnly = false,
  }) {
    return _run(
      () => client.readTree(
        offset: offset,
        maxNodes: maxNodes,
        interactiveOnly: interactiveOnly,
      ),
      'read the screen tree',
    );
  }

  Future<Map<String, dynamic>> input(Map<String, dynamic> arguments) =>
      _run(() => client.input(arguments), 'input');

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
