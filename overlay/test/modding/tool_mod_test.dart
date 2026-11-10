import 'dart:async';

import 'package:Kelivo/core/models/model_spec.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/chat_api_helpers.dart';
import 'package:Kelivo/core/services/api/tool_call_cancellation.dart';
import 'package:Kelivo/modding/tool_mod.dart';
import 'package:Kelivo/utils/mcp_structured_image.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/business_test_harness.dart';

class _RecordingMod extends ToolMod {
  _RecordingMod(this.id, this.log, {this.fail = false});

  final String id;
  final List<String> log;
  final bool fail;

  @override
  List<Map<String, dynamic>> decorateDefinitions(
    List<Map<String, dynamic>> definitions,
    ModToolDefinitionContext context,
  ) {
    log.add('define:$id:${context.supportsImageInput}');
    return <Map<String, dynamic>>[
      ...definitions,
      <String, dynamic>{
        'type': 'function',
        'function': <String, dynamic>{'name': id},
      },
    ];
  }

  @override
  ToolCallHandler wrapHandler(
    ToolCallHandler handler,
    ModToolExecutionContext context,
  ) {
    return (name, args, {toolCallId}) async {
      log.add('call:$id');
      if (fail) throw StateError('boom');
      return handler(name, args, toolCallId: toolCallId);
    };
  }
}

class _ThrowingDefinitionMod extends ToolMod {
  @override
  List<Map<String, dynamic>> decorateDefinitions(
    List<Map<String, dynamic>> definitions,
    ModToolDefinitionContext context,
  ) => throw StateError('define boom');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsProvider settings;
  late ModToolDefinitionContext definitionContext;
  late ModToolExecutionContext executionContext;

  setUp(() async {
    settings = SettingsProvider(createBusinessTestPreferences());
    await settings.loaded;
    addTearDown(settings.dispose);
    definitionContext = ModToolDefinitionContext(
      settings: settings,
      assistant: null,
      providerKey: 'test',
      modelId: 'test',
      conversationId: 'conv',
      supportsTools: true,
      inputModalities: const <Modality>[Modality.text, Modality.image],
    );
    executionContext = ModToolExecutionContext(
      assistant: null,
      conversationId: 'conv',
      approvalService: null,
      askUserService: null,
      originalHandler: (name, args, {toolCallId}) async => 'base',
      readCurrentAssistant: () => null,
    );
  });

  test('空 Mod 原样返回定义和 handler', () {
    final definitions = <Map<String, dynamic>>[
      <String, dynamic>{'type': 'function'},
    ];
    expect(
      identical(
        composeToolDefinitions(
          const <ToolMod>[],
          definitions,
          definitionContext,
        ),
        definitions,
      ),
      isTrue,
    );

    Future<Object?> handler(
      String name,
      Map<String, dynamic> args, {
      String? toolCallId,
    }) async => 'base';
    expect(
      identical(
        composeToolCallHandler(const <ToolMod>[], handler, executionContext),
        handler,
      ),
      isTrue,
    );
  });

  test('定义按配置顺序装饰，并读取输入能力', () {
    final log = <String>[];
    final definitions = composeToolDefinitions(
      <ToolMod>[_RecordingMod('a', log), _RecordingMod('b', log)],
      <Map<String, dynamic>>[
        <String, dynamic>{'type': 'function'},
      ],
      definitionContext,
    );

    expect(log, <String>['define:a:true', 'define:b:true']);
    expect(
      definitions
          .map((d) => d['function'])
          .whereType<Map>()
          .map((f) => f['name'])
          .whereType<String>()
          .toList(),
      <String>['a', 'b'],
    );
  });

  test('定义装饰异常被记录并跳过，不阻断后续 Mod', () {
    final log = <String>[];
    final definitions = composeToolDefinitions(
      <ToolMod>[_ThrowingDefinitionMod(), _RecordingMod('a', log)],
      <Map<String, dynamic>>[
        <String, dynamic>{'type': 'function'},
      ],
      definitionContext,
    );

    expect(log, <String>['define:a:true']);
    expect(
      definitions
          .map((d) => d['function'])
          .whereType<Map>()
          .map((f) => f['name'])
          .whereType<String>()
          .toList(),
      <String>['a'],
    );
  });

  test('handler 反向包装，第一个 Mod 最先收到调用', () async {
    final log = <String>[];
    final handler = composeToolCallHandler(
      <ToolMod>[_RecordingMod('a', log), _RecordingMod('b', log)],
      (name, args, {toolCallId}) async {
        log.add('base:$name:${args['x']}:$toolCallId');
        return 'done';
      },
      executionContext,
    );

    final result = await handler('unknown_tool', <String, dynamic>{
      'x': 1,
    }, toolCallId: 'call-1');

    expect(result, 'done');
    expect(log, <String>['call:a', 'call:b', 'base:unknown_tool:1:call-1']);
  });

  test('Mod 异常转换为工具错误，不向外抛出', () async {
    final log = <String>[];
    final handler = composeToolCallHandler(
      <ToolMod>[_RecordingMod('a', log, fail: true)],
      (name, args, {toolCallId}) async => 'base',
      executionContext,
    );

    final result = await handler('demo_tool', <String, dynamic>{});

    expect(result, isA<ClientToolResult>());
    final content = (result as ClientToolResult).content;
    expect(content, contains('mod_execution_error'));
    expect(content, contains('demo_tool'));
  });

  test('ClientToolResult 原样透传', () async {
    const expected = ClientToolResult(
      'markdown',
      metadata: <String, dynamic>{'k': 'v'},
    );
    final handler = composeToolCallHandler(
      <ToolMod>[_RecordingMod('a', <String>[])],
      (name, args, {toolCallId}) async => expected,
      executionContext,
    );

    expect(await handler('demo_tool', <String, dynamic>{}), same(expected));
  });

  test('取消信号继续向上传递', () async {
    var cancelled = false;
    final cancellation = ToolCallCancellation(
      isCancelled: () => cancelled,
      cancelled: Completer<void>().future,
    );
    final handler = composeToolCallHandler(
      <ToolMod>[_RecordingMod('a', <String>[])],
      (name, args, {toolCallId}) async {
        cancelled = true;
        throw StateError('tool_call_cancelled');
      },
      executionContext,
    );

    await cancellation.run(
      () => expectLater(
        handler('demo_tool', <String, dynamic>{}),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'tool_call_cancelled',
          ),
        ),
      ),
    );
  });
}
