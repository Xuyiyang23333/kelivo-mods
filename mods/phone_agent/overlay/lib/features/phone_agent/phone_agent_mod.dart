import 'package:flutter/foundation.dart';

import '../../core/models/assistant.dart';
import '../../core/services/api/chat_api_helpers.dart';
import '../../core/services/api/tool_call_cancellation.dart';
import '../../modding/tool_mod.dart';
import '../home/services/local_tools_service.dart';
import 'phone_agent_local_tool.dart';
import 'phone_agent_service.dart';
import 'phone_agent_tools.dart';

/// Kelivo-side registration for the independent phone agent plugin.
///
/// Active only on Android, when the current assistant enables the
/// `phone_agent` local tool, and when the model supports tool calls. While
/// active it replaces the native `phone_control` definition and any duplicate
/// `phone_agent_*` definitions with the mod tools; otherwise definitions are
/// left untouched and native phone control keeps working.
class PhoneAgentMod extends ToolMod {
  const PhoneAgentMod({this.service});

  final PhoneAgentService? service;

  /// Image capability is only known while building definitions for a request.
  /// The handler is built for the same conversation right after, so the value
  /// is keyed by conversation to reject screenshot or coordinate calls from a
  /// non-visual model that still invokes the tool.
  static final Map<String, bool> _imageSupportByConversation = <String, bool>{};

  static const int _maxTrackedConversations = 64;

  static const int _maxInputCallsPerGeneration = 60;

  static void _rememberImageSupport(String conversationId, bool supported) {
    if (!_imageSupportByConversation.containsKey(conversationId) &&
        _imageSupportByConversation.length >= _maxTrackedConversations) {
      _imageSupportByConversation.remove(
        _imageSupportByConversation.keys.first,
      );
    }
    _imageSupportByConversation[conversationId] = supported;
  }

  PhoneAgentService get _resolvedService =>
      service ?? PhoneAgentService.instance;

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static const PhoneAgentToolFailure _unsupportedPlatform =
      PhoneAgentToolFailure(
        'unsupported_platform',
        'Phone Agent tools are only available on Android.',
        instruction:
            'Use another tool or tell the user that phone control requires '
            'an Android device.',
      );

  static bool _allowsPhoneAgent(Assistant? assistant) =>
      PhoneAgentLocalTool.selectionFor(assistant) ==
      PhoneAgentControlSelection.phoneAgent;

  static bool _isActive(ModToolDefinitionContext context) =>
      _isAndroid &&
      context.supportsTools &&
      _allowsPhoneAgent(context.assistant);

  @override
  List<Map<String, dynamic>> decorateDefinitions(
    List<Map<String, dynamic>> definitions,
    ModToolDefinitionContext context,
  ) {
    if (!_isActive(context)) return definitions;
    _rememberImageSupport(
      context.conversationId ?? '',
      context.supportsImageInput,
    );
    return <Map<String, dynamic>>[
      for (final definition in definitions)
        if (!_isReplacedDefinition(_definitionName(definition))) definition,
      ...PhoneAgentTools.buildDefinitions(
        supportsImageInput: context.supportsImageInput,
      ),
    ];
  }

  @override
  ToolCallHandler wrapHandler(
    ToolCallHandler handler,
    ModToolExecutionContext context,
  ) {
    var inputCalls = 0;
    return (name, args, {toolCallId}) async {
      if (name == LocalToolNames.phoneControl) {
        if (_allowsPhoneAgent(context.readCurrentAssistant())) {
          if (!_isAndroid) {
            return _unsupportedPlatform.toToolResult(tool: name);
          }
          return PhoneAgentToolFailure(
            'phone_control_unavailable',
            'The native phone_control tool is not available because this '
                'assistant uses Phone Agent.',
            instruction:
                'Use ${PhoneAgentToolNames.all.join(', ')} instead. Do not '
                'call phone_control.',
          ).toToolResult(tool: name);
        }
        return handler(name, args, toolCallId: toolCallId);
      }
      if (!PhoneAgentToolNames.all.contains(name)) {
        return handler(name, args, toolCallId: toolCallId);
      }
      try {
        if (!_isAndroid) {
          throw _unsupportedPlatform;
        }
        if (!_allowsPhoneAgent(context.readCurrentAssistant())) {
          throw const PhoneAgentToolFailure(
            'phone_agent_disabled',
            'The current assistant no longer enables Phone Agent.',
            instruction:
                'Ask the user to select Phone Agent for this assistant in the '
                'Mods settings before retrying.',
          );
        }
        if (name == PhoneAgentToolNames.input) {
          inputCalls++;
          if (inputCalls > _maxInputCallsPerGeneration) {
            throw PhoneAgentToolFailure(
              'budget_exceeded',
              'phone_agent_input was called more than '
                  '$_maxInputCallsPerGeneration times in this generation.',
              instruction:
                  'Stop calling phone_agent_input and report the current '
                  'progress to the user.',
            );
          }
        }
        return await PhoneAgentTools.handleCall(
          name: name,
          args: args,
          service: _resolvedService,
          supportsImageInput:
              _imageSupportByConversation[context.conversationId ?? ''] ??
              false,
          // 审计元数据的助手/会话身份：助手 id 取**实时重读**（M35 语义），
          // 只是审计标签，不参与任何授权判定。
          assistantId: context.readCurrentAssistant()?.id,
          conversationId: context.conversationId,
          // 批准来源的助手 id 取**创建请求时的快照**（M34 语义）：它写进白名单记录的
          // “首次批准来源”，必须反映发起请求时的助手，而不是批准时的当前助手。
          toolCallId: toolCallId,
          approvalAssistantId: context.assistant?.id,
          // 与审计 id 分开传：上面的 assistantId 只喂审计，这里只写批准来源。
        );
      } on PhoneAgentToolFailure catch (failure) {
        return failure.toToolResult(tool: name);
      } catch (error) {
        if (ToolCallCancellation.current?.isCancelled() ?? false) rethrow;
        return PhoneAgentToolFailure(
          'phone_agent_error',
          'The phone agent tool failed: $error',
          instruction:
              'Do not retry the same call blindly. Inform the user if the '
              'error persists.',
        ).toToolResult(tool: name);
      }
    };
  }

  static bool _isReplacedDefinition(String? name) {
    if (name == null) return false;
    return name == LocalToolNames.phoneControl ||
        name.startsWith('${PhoneAgentLocalTool.id}_');
  }

  static String? _definitionName(Map<String, dynamic> definition) {
    final function = definition['function'];
    if (function is Map) {
      final name = function['name'];
      if (name is String) return name;
    }
    return null;
  }

  @visibleForTesting
  static void debugResetImageSupport() => _imageSupportByConversation.clear();
}
