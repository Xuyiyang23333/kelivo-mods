import 'dart:async';

import 'package:Kelivo/core/services/api/tool_call_cancellation.dart';
import 'package:Kelivo/features/home/services/local_tools_service.dart';
import 'package:Kelivo/features/phone_agent/phone_agent_mod.dart';
import 'package:Kelivo/features/phone_agent/phone_agent_service.dart';
import 'package:Kelivo/features/phone_agent/phone_agent_tools.dart';
import 'package:Kelivo/utils/mcp_structured_image.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelivo_phone_agent/kelivo_phone_agent.dart';

import 'phone_agent_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RecordingPhoneAgentClient client;
  late PhoneAgentService service;
  late PhoneAgentMod mod;

  setUp(() {
    PhoneAgentMod.debugResetImageSupport();
    client = RecordingPhoneAgentClient();
    service = PhoneAgentService(client: client);
    mod = PhoneAgentMod(service: service);
  });

  Future<Object?> originalHandler(
    String name,
    Map<String, dynamic> args, {
    String? toolCallId,
  }) async {
    return 'base:$name';
  }

  group('定义门控', () {
    test('非 Android 平台原样返回定义', () async {
      runOnIos();
      final definitions = <Map<String, dynamic>>[
        functionDefinition('phone_control'),
        functionDefinition('get_time_info'),
      ];
      final result = mod.decorateDefinitions(
        definitions,
        definitionContextFor(await createTestSettings()),
      );
      expect(identical(result, definitions), isTrue);
    });

    test('模型不支持工具调用时原样返回定义', () async {
      runOnAndroid();
      final definitions = <Map<String, dynamic>>[
        functionDefinition('phone_control'),
      ];
      final result = mod.decorateDefinitions(
        definitions,
        definitionContextFor(await createTestSettings(), supportsTools: false),
      );
      expect(identical(result, definitions), isTrue);
    });

    test('助手未开启 phone_agent 时原样返回定义', () async {
      runOnAndroid();
      final definitions = <Map<String, dynamic>>[
        functionDefinition('phone_control'),
      ];
      final result = mod.decorateDefinitions(
        definitions,
        definitionContextFor(
          await createTestSettings(),
          assistant: disabledAssistant,
        ),
      );
      expect(identical(result, definitions), isTrue);
    });

    test('仅开启原生 phone_control 的助手保持原生定义', () async {
      runOnAndroid();
      final definitions = <Map<String, dynamic>>[
        functionDefinition(LocalToolNames.phoneControl),
        functionDefinition('get_time_info'),
      ];
      final result = mod.decorateDefinitions(
        definitions,
        definitionContextFor(
          await createTestSettings(),
          assistant: nativeAssistant,
        ),
      );
      expect(identical(result, definitions), isTrue);
      expect(definitionNames(result), <String>[
        LocalToolNames.phoneControl,
        'get_time_info',
      ]);
    });

    test('没有助手时原样返回定义', () async {
      runOnAndroid();
      final definitions = <Map<String, dynamic>>[
        functionDefinition('phone_control'),
      ];
      final result = mod.decorateDefinitions(
        definitions,
        definitionContextFor(await createTestSettings(), assistant: null),
      );
      expect(identical(result, definitions), isTrue);
    });

    test('视觉模型激活时移除 phone_control 并添加三个工具', () async {
      runOnAndroid();
      final definitions = <Map<String, dynamic>>[
        functionDefinition('phone_control'),
        functionDefinition('get_time_info'),
      ];
      final result = mod.decorateDefinitions(
        definitions,
        definitionContextFor(await createTestSettings()),
      );
      expect(definitionNames(result), <String>[
        'get_time_info',
        PhoneAgentToolNames.screenshot,
        PhoneAgentToolNames.tree,
        PhoneAgentToolNames.input,
      ]);
    });

    test('非视觉模型激活时没有截图工具', () async {
      runOnAndroid();
      final definitions = <Map<String, dynamic>>[
        functionDefinition('phone_control'),
      ];
      final result = mod.decorateDefinitions(
        definitions,
        definitionContextFor(
          await createTestSettings(),
          supportsImageInput: false,
        ),
      );
      expect(definitionNames(result), <String>[
        PhoneAgentToolNames.tree,
        PhoneAgentToolNames.input,
      ]);
    });

    test('两个 ID 同时存在时按 phone_agent 激活并过滤原生定义', () async {
      runOnAndroid();
      final definitions = <Map<String, dynamic>>[
        functionDefinition(LocalToolNames.phoneControl),
        functionDefinition('get_time_info'),
      ];
      final result = mod.decorateDefinitions(
        definitions,
        definitionContextFor(
          await createTestSettings(),
          assistant: conflictAssistant,
        ),
      );
      expect(definitionNames(result), <String>[
        'get_time_info',
        PhoneAgentToolNames.screenshot,
        PhoneAgentToolNames.tree,
        PhoneAgentToolNames.input,
      ]);
    });

    test('激活时过滤重复的 phone_agent_* 定义', () async {
      runOnAndroid();
      final definitions = <Map<String, dynamic>>[
        functionDefinition('phone_control'),
        functionDefinition(PhoneAgentToolNames.tree),
        functionDefinition('phone_agent_custom'),
        functionDefinition('get_time_info'),
      ];
      final result = mod.decorateDefinitions(
        definitions,
        definitionContextFor(await createTestSettings()),
      );
      expect(definitionNames(result), <String>[
        'get_time_info',
        PhoneAgentToolNames.screenshot,
        PhoneAgentToolNames.tree,
        PhoneAgentToolNames.input,
      ]);
    });
  });

  group('handler 透传', () {
    test('未识别的工具名、参数和 toolCallId 原样透传', () async {
      runOnAndroid();
      final expected = const ClientToolResult('base');
      final calls = <String>[];
      Future<Object?> original(
        String name,
        Map<String, dynamic> args, {
        String? toolCallId,
      }) async {
        calls.add('$name|${args['x']}|$toolCallId');
        return expected;
      }

      final wrapped = mod.wrapHandler(
        original,
        executionContextFor(originalHandler: original),
      );
      final result = await wrapped('get_time_info', <String, dynamic>{
        'x': 1,
      }, toolCallId: 'call-1');

      expect(result, same(expected));
      expect(calls, <String>['get_time_info|1|call-1']);
    });

    test('仅开启原生 phone_control 时原样透传', () async {
      runOnAndroid();
      final expected = const ClientToolResult('native');
      final calls = <String>[];
      Future<Object?> original(
        String name,
        Map<String, dynamic> args, {
        String? toolCallId,
      }) async {
        calls.add('$name|$toolCallId');
        return expected;
      }

      final wrapped = mod.wrapHandler(
        original,
        executionContextFor(
          originalHandler: original,
          assistant: nativeAssistant,
        ),
      );
      final result = await wrapped(
        LocalToolNames.phoneControl,
        <String, dynamic>{},
        toolCallId: 'call-native',
      );

      expect(result, same(expected));
      expect(calls, <String>['phone_control|call-native']);
    });

    test('Mod 工具不会调用原始 handler', () async {
      runOnAndroid();
      final calls = <String>[];
      Future<Object?> original(
        String name,
        Map<String, dynamic> args, {
        String? toolCallId,
      }) async {
        calls.add(name);
        return 'base';
      }

      final settings = await createTestSettings();
      mod.decorateDefinitions(
        <Map<String, dynamic>>[],
        definitionContextFor(settings),
      );
      final wrapped = mod.wrapHandler(
        original,
        executionContextFor(originalHandler: original),
      );
      await wrapped(PhoneAgentToolNames.tree, <String, dynamic>{});

      expect(calls, isEmpty);
      expect(client.treeCalls, hasLength(1));
    });

    test('非 Android 执行时返回结构化错误', () async {
      runOnIos();
      final wrapped = mod.wrapHandler(
        originalHandler,
        executionContextFor(originalHandler: originalHandler),
      );
      final result = decodeToolResult(
        await wrapped(PhoneAgentToolNames.tree, <String, dynamic>{}),
      );

      expect(result['type'], 'tool_error');
      expect(result['error'], 'unsupported_platform');
      expect(result['tool'], PhoneAgentToolNames.tree);
      expect(client.treeCalls, isEmpty);
    });
  });

  group('原生调用拦截', () {
    test('phone_agent 选中时拦截 phone_control，不执行原生 handler', () async {
      runOnAndroid();
      final calls = <String>[];
      Future<Object?> original(
        String name,
        Map<String, dynamic> args, {
        String? toolCallId,
      }) async {
        calls.add(name);
        return 'base';
      }

      final wrapped = mod.wrapHandler(
        original,
        executionContextFor(originalHandler: original),
      );
      final result = decodeToolResult(
        await wrapped(
          LocalToolNames.phoneControl,
          <String, dynamic>{},
          toolCallId: 'call-native',
        ),
      );

      expect(calls, isEmpty);
      expect(result['type'], 'tool_error');
      expect(result['error'], 'phone_control_unavailable');
      expect(result['tool'], LocalToolNames.phoneControl);
      expect(result['instruction'], contains(PhoneAgentToolNames.tree));
    });

    test('双 ID 同时存在时仍拦截 phone_control', () async {
      runOnAndroid();
      final calls = <String>[];
      Future<Object?> original(
        String name,
        Map<String, dynamic> args, {
        String? toolCallId,
      }) async {
        calls.add(name);
        return 'base';
      }

      final wrapped = mod.wrapHandler(
        original,
        executionContextFor(
          originalHandler: original,
          assistant: conflictAssistant,
        ),
      );
      final result = decodeToolResult(
        await wrapped(LocalToolNames.phoneControl, <String, dynamic>{}),
      );

      expect(calls, isEmpty);
      expect(result['error'], 'phone_control_unavailable');
    });

    test('非 Android 上拦截 phone_control 时返回 unsupported_platform', () async {
      runOnIos();
      final calls = <String>[];
      Future<Object?> original(
        String name,
        Map<String, dynamic> args, {
        String? toolCallId,
      }) async {
        calls.add(name);
        return 'base';
      }

      final wrapped = mod.wrapHandler(
        original,
        executionContextFor(originalHandler: original),
      );
      final result = decodeToolResult(
        await wrapped(LocalToolNames.phoneControl, <String, dynamic>{}),
      );

      expect(calls, isEmpty);
      expect(result['type'], 'tool_error');
      expect(result['error'], 'unsupported_platform');
      expect(result['tool'], LocalToolNames.phoneControl);
      expect(result['message'], contains('Android'));
      expect(result['instruction'], isNot(contains('phone_agent_')));
    });
  });

  group('助手开关重读', () {
    test('生成途中撤销 phone_agent 后不再执行', () async {
      runOnAndroid();
      final settings = await createTestSettings();
      mod.decorateDefinitions(<Map<String, dynamic>>[
        functionDefinition('phone_control'),
      ], definitionContextFor(settings));
      final wrapped = mod.wrapHandler(
        originalHandler,
        executionContextFor(
          originalHandler: originalHandler,
          readCurrentAssistant: () => disabledAssistant,
        ),
      );

      final result = decodeToolResult(
        await wrapped(PhoneAgentToolNames.tree, <String, dynamic>{}),
      );

      expect(result['type'], 'tool_error');
      expect(result['error'], 'phone_agent_disabled');
      expect(result['instruction'], isNotEmpty);
      expect(client.treeCalls, isEmpty);
    });

    test('当前助手已被删除时拒绝执行', () async {
      runOnAndroid();
      final wrapped = mod.wrapHandler(
        originalHandler,
        executionContextFor(
          originalHandler: originalHandler,
          readCurrentAssistant: () => null,
        ),
      );

      final result = decodeToolResult(
        await wrapped(PhoneAgentToolNames.tree, <String, dynamic>{}),
      );

      expect(result['error'], 'phone_agent_disabled');
      expect(client.treeCalls, isEmpty);
    });
  });

  group('视觉能力重读', () {
    test('同一会话切换到非视觉模型后仍拒绝截图但允许坐标输入', () async {
      runOnAndroid();
      final settings = await createTestSettings();
      final wrapped = mod.wrapHandler(
        originalHandler,
        executionContextFor(originalHandler: originalHandler),
      );

      mod.decorateDefinitions(
        <Map<String, dynamic>>[],
        definitionContextFor(settings, supportsImageInput: true),
      );
      await wrapped(PhoneAgentToolNames.screenshot, <String, dynamic>{});
      expect(client.screenshotCalls, 1);

      mod.decorateDefinitions(
        <Map<String, dynamic>>[],
        definitionContextFor(settings, supportsImageInput: false),
      );
      final blockedScreenshot = decodeToolResult(
        await wrapped(PhoneAgentToolNames.screenshot, <String, dynamic>{}),
      );
      final coordTap = decodeToolResult(
        await wrapped(PhoneAgentToolNames.input, <String, dynamic>{
          'action': 'tap',
          'x': 0.5,
          'y': 0.5,
        }),
      );

      expect(blockedScreenshot['error'], 'image_input_unsupported');
      expect(client.screenshotCalls, 1);
      expect(coordTap['ok'], isTrue);
      expect(client.inputCalls, hasLength(1));
    });

    test('不同会话的视觉能力互不影响', () async {
      runOnAndroid();
      final settings = await createTestSettings();

      mod.decorateDefinitions(
        <Map<String, dynamic>>[],
        definitionContextFor(
          settings,
          conversationId: 'visual',
          supportsImageInput: true,
        ),
      );
      mod.decorateDefinitions(
        <Map<String, dynamic>>[],
        definitionContextFor(
          settings,
          conversationId: 'text-only',
          supportsImageInput: false,
        ),
      );

      final visual = mod.wrapHandler(
        originalHandler,
        executionContextFor(
          originalHandler: originalHandler,
          conversationId: 'visual',
        ),
      );
      final textOnly = mod.wrapHandler(
        originalHandler,
        executionContextFor(
          originalHandler: originalHandler,
          conversationId: 'text-only',
        ),
      );

      await visual(PhoneAgentToolNames.screenshot, <String, dynamic>{});
      final rejected = decodeToolResult(
        await textOnly(PhoneAgentToolNames.screenshot, <String, dynamic>{}),
      );

      expect(client.screenshotCalls, 1);
      expect(rejected['error'], 'image_input_unsupported');
    });
  });

  group('输入预算', () {
    test('同一生成内第 61 次 input 返回 budget_exceeded', () async {
      runOnAndroid();
      final wrapped = mod.wrapHandler(
        originalHandler,
        executionContextFor(originalHandler: originalHandler),
      );

      for (var index = 0; index < 60; index++) {
        final result = decodeToolResult(
          await wrapped(PhoneAgentToolNames.input, <String, dynamic>{
            'action': 'back',
          }),
        );
        expect(result['ok'], isTrue);
      }
      final rejected = decodeToolResult(
        await wrapped(PhoneAgentToolNames.input, <String, dynamic>{
          'action': 'back',
        }),
      );

      expect(rejected['type'], 'tool_error');
      expect(rejected['error'], 'budget_exceeded');
      expect(rejected['instruction'], isNotEmpty);
      expect(client.inputCalls, hasLength(60));
    });

    test('不同 handler 的输入预算互不影响', () async {
      runOnAndroid();
      final first = mod.wrapHandler(
        originalHandler,
        executionContextFor(originalHandler: originalHandler),
      );
      final second = mod.wrapHandler(
        originalHandler,
        executionContextFor(originalHandler: originalHandler),
      );

      for (var index = 0; index < 60; index++) {
        await first(PhoneAgentToolNames.input, <String, dynamic>{
          'action': 'back',
        });
      }
      final rejected = decodeToolResult(
        await first(PhoneAgentToolNames.input, <String, dynamic>{
          'action': 'back',
        }),
      );
      final accepted = decodeToolResult(
        await second(PhoneAgentToolNames.input, <String, dynamic>{
          'action': 'back',
        }),
      );

      expect(rejected['error'], 'budget_exceeded');
      expect(accepted['ok'], isTrue);
      expect(client.inputCalls, hasLength(61));
    });

    test('读树不计入输入预算', () async {
      runOnAndroid();
      final wrapped = mod.wrapHandler(
        originalHandler,
        executionContextFor(originalHandler: originalHandler),
      );

      for (var index = 0; index < 60; index++) {
        await wrapped(PhoneAgentToolNames.tree, <String, dynamic>{});
      }
      final result = decodeToolResult(
        await wrapped(PhoneAgentToolNames.input, <String, dynamic>{
          'action': 'back',
        }),
      );

      expect(result['ok'], isTrue);
      expect(client.inputCalls, hasLength(1));
    });

    test('batch 每个子动作计入 60 次生成预算并在超限时短路回报进度', () async {
      runOnAndroid();
      final wrapped = mod.wrapHandler(
        originalHandler,
        executionContextFor(originalHandler: originalHandler),
      );

      for (var index = 0; index < 58; index++) {
        await wrapped(PhoneAgentToolNames.input, <String, dynamic>{
          'action': 'back',
        });
      }
      final result = decodeToolResult(
        await wrapped(PhoneAgentToolNames.input, <String, dynamic>{
          'action': 'batch',
          'interval_ms': 0,
          'actions': <Map<String, dynamic>>[
            <String, dynamic>{'action': 'tap', 'node_id': 'n1'},
            <String, dynamic>{'action': 'tap', 'node_id': 'n2'},
            <String, dynamic>{'action': 'tap', 'node_id': 'n3'},
            <String, dynamic>{'action': 'tap', 'node_id': 'n4'},
          ],
        }),
      );

      expect(result['type'], 'tool_error');
      expect(result['error'], 'budget_exceeded');
      expect(result['action'], 'batch');
      expect(result['completed'], 2);
      expect(result['total'], 4);
      expect(result['failed_index'], 2);
      expect(client.inputCalls, hasLength(60));
    });

    test('batch 执行途中关闭 phone_agent 时在下一步中止', () async {
      runOnAndroid();
      var currentAssistant = enabledAssistant;
      client.onInput = (arguments) async {
        currentAssistant = disabledAssistant;
        return <String, dynamic>{'success': true};
      };
      final wrapped = mod.wrapHandler(
        originalHandler,
        executionContextFor(
          originalHandler: originalHandler,
          readCurrentAssistant: () => currentAssistant,
        ),
      );

      final result = decodeToolResult(
        await wrapped(PhoneAgentToolNames.input, <String, dynamic>{
          'action': 'batch',
          'interval_ms': 0,
          'actions': <Map<String, dynamic>>[
            <String, dynamic>{'action': 'tap', 'node_id': 'n1'},
            <String, dynamic>{'action': 'tap', 'node_id': 'n2'},
          ],
        }),
      );

      expect(result['type'], 'tool_error');
      expect(result['error'], 'phone_agent_disabled');
      expect(result['completed'], 1);
      expect(result['failed_index'], 1);
      expect(client.inputCalls, hasLength(1));
    });
  });

  group('异常处理', () {
    test('插件结构化异常转换为工具错误', () async {
      runOnAndroid();
      client.treeError = PhoneAgentException(
        'service_disabled',
        'Enable the Phone Agent accessibility service.',
      );
      final wrapped = mod.wrapHandler(
        originalHandler,
        executionContextFor(originalHandler: originalHandler),
      );

      final result = decodeToolResult(
        await wrapped(PhoneAgentToolNames.tree, <String, dynamic>{}),
      );

      expect(result['type'], 'tool_error');
      expect(result['error'], 'service_disabled');
      expect(result['message'], contains('accessibility'));
      expect(result['instruction'], isNotEmpty);
    });

    test('未知异常转换为 phone_agent_error，不向外抛出', () async {
      runOnAndroid();
      client.treeError = StateError('boom');
      final wrapped = mod.wrapHandler(
        originalHandler,
        executionContextFor(originalHandler: originalHandler),
      );

      final result = decodeToolResult(
        await wrapped(PhoneAgentToolNames.tree, <String, dynamic>{}),
      );

      expect(result['error'], 'phone_agent_error');
      expect(result['message'], contains('boom'));
    });

    test('取消信号不被 catch-all 吞掉', () async {
      runOnAndroid();
      final settings = await createTestSettings();
      mod.decorateDefinitions(
        <Map<String, dynamic>>[],
        definitionContextFor(settings),
      );
      final wrapped = mod.wrapHandler(
        originalHandler,
        executionContextFor(originalHandler: originalHandler),
      );
      var cancelled = false;
      final token = ToolCallCancellation(
        isCancelled: () => cancelled,
        cancelled: Completer<void>().future,
      );

      await expectLater(
        token.run(() async {
          cancelled = true;
          return wrapped(PhoneAgentToolNames.screenshot, <String, dynamic>{});
        }),
        throwsA(isA<StateError>()),
      );
      expect(client.clearScreenshotCalls, 0);
    });

    test('Mod 工具不调用 app.device_tools 通道', () async {
      runOnAndroid();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(
        const MethodChannel('app.device_tools'),
        (call) async {
          calls.add(call);
          return '{}';
        },
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel('app.device_tools'),
          null,
        ),
      );

      final settings = await createTestSettings();
      mod.decorateDefinitions(
        <Map<String, dynamic>>[],
        definitionContextFor(settings),
      );
      final wrapped = mod.wrapHandler(
        originalHandler,
        executionContextFor(originalHandler: originalHandler),
      );
      await wrapped(PhoneAgentToolNames.tree, <String, dynamic>{});
      await wrapped(PhoneAgentToolNames.input, <String, dynamic>{
        'action': 'back',
      });

      expect(calls, isEmpty);
      expect(client.treeCalls, hasLength(1));
      expect(client.inputCalls, hasLength(1));
    });
  });
}
