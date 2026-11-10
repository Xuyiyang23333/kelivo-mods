import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/models/assistant.dart';
import '../core/models/model_spec.dart';
import '../core/providers/settings_provider.dart';
import '../core/services/api/chat_api_helpers.dart';
import '../core/services/api/tool_call_cancellation.dart';
import '../features/home/services/ask_user_interaction_service.dart';
import '../features/home/services/tool_approval_service.dart';
import '../utils/mcp_structured_image.dart';

/// 装饰工具定义时可读取的只读上下文。
class ModToolDefinitionContext {
  const ModToolDefinitionContext({
    required this.settings,
    required this.assistant,
    required this.providerKey,
    required this.modelId,
    required this.conversationId,
    required this.supportsTools,
    required this.inputModalities,
  });

  final SettingsProvider settings;
  final Assistant? assistant;
  final String providerKey;
  final String modelId;
  final String? conversationId;
  final bool supportsTools;
  final List<Modality> inputModalities;

  bool get supportsImageInput => inputModalities.contains(Modality.image);
}

/// 包装工具处理器时可读取的上下文。
class ModToolExecutionContext {
  const ModToolExecutionContext({
    required this.assistant,
    required this.conversationId,
    required this.approvalService,
    required this.askUserService,
    required this.originalHandler,
    required this.readCurrentAssistant,
  });

  /// 构建处理器时的助手快照，可能已过期。
  final Assistant? assistant;

  final String? conversationId;
  final ToolApprovalService? approvalService;
  final AskUserInteractionService? askUserService;

  /// 上游原始处理器，不包含任何 Mod 包装。
  final ToolCallHandler originalHandler;

  /// 按 id 重读当前助手配置；助手快照为空时返回 null。
  final Assistant? Function() readCurrentAssistant;
}

/// 通用 Mod 工具接口。
///
/// 定义按配置顺序依次装饰；处理器按相反顺序包装，使配置中第一个 Mod
/// 最先收到工具调用。未覆盖的方向原样透传。
abstract class ToolMod {
  const ToolMod();

  List<Map<String, dynamic>> decorateDefinitions(
    List<Map<String, dynamic>> definitions,
    ModToolDefinitionContext context,
  ) => definitions;

  ToolCallHandler wrapHandler(
    ToolCallHandler handler,
    ModToolExecutionContext context,
  ) => handler;
}

/// 按配置顺序装饰定义；没有 Mod 时返回原始列表。
///
/// 单个 Mod 装饰失败时记录错误并跳过该 Mod，保留之前的定义。
List<Map<String, dynamic>> composeToolDefinitions(
  List<ToolMod> mods,
  List<Map<String, dynamic>> definitions,
  ModToolDefinitionContext context,
) {
  var result = definitions;
  for (final mod in mods) {
    try {
      result = mod.decorateDefinitions(result, context);
    } catch (error, stack) {
      debugPrint(
        'Kelivo mod ${mod.runtimeType} failed to decorate tool definitions: '
        '$error\n$stack',
      );
    }
  }
  return result;
}

/// 按相反顺序包装处理器；没有 Mod 时返回原始处理器。
///
/// Mod 包装层抛出的异常会转换为结构化工具错误，避免中断聊天流程。
ToolCallHandler composeToolCallHandler(
  List<ToolMod> mods,
  ToolCallHandler handler,
  ModToolExecutionContext context,
) {
  if (mods.isEmpty) return handler;
  var result = handler;
  for (final mod in mods.reversed) {
    result = mod.wrapHandler(result, context);
  }
  return (name, args, {toolCallId}) async {
    try {
      return await result(name, args, toolCallId: toolCallId);
    } catch (error) {
      if (ToolCallCancellation.current?.isCancelled() == true) rethrow;
      return ClientToolResult(
        jsonEncode(<String, dynamic>{
          'type': 'tool_error',
          'error': 'mod_execution_error',
          'message': error.toString(),
          'tool': name,
          'instruction':
              'The tool call failed inside a mod wrapper. Retry only after '
              'correcting the request, or inform the user.',
        }),
      );
    }
  };
}
