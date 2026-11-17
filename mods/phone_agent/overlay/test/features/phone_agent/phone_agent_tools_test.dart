import 'dart:convert';

import 'package:Kelivo/features/phone_agent/phone_agent_service.dart';
import 'package:Kelivo/features/phone_agent/phone_agent_tools.dart';
import 'package:Kelivo/utils/mcp_structured_image.dart';
import 'package:flutter_test/flutter_test.dart';

import 'phone_agent_test_support.dart';

void main() {
  late RecordingPhoneAgentClient client;
  late PhoneAgentService service;

  setUp(() {
    client = RecordingPhoneAgentClient();
    service = PhoneAgentService(client: client);
  });

  Map<String, dynamic> functionOf(
    List<Map<String, dynamic>> definitions,
    String name,
  ) {
    final definition = definitions.firstWhere(
      (item) => (item['function'] as Map)['name'] == name,
    );
    return Map<String, dynamic>.from(definition['function'] as Map);
  }

  Map<String, dynamic> parametersOf(
    List<Map<String, dynamic>> definitions,
    String name,
  ) {
    return Map<String, dynamic>.from(
      functionOf(definitions, name)['parameters'] as Map,
    );
  }

  group('schema', () {
    test('工具名固定', () {
      expect(PhoneAgentToolNames.all, <String>[
        'phone_agent_screenshot',
        'phone_agent_tree',
        'phone_agent_input',
      ]);
    });

    test('视觉模型获得三个工具且不暴露 snapshot_id', () {
      final definitions = PhoneAgentTools.buildDefinitions(
        supportsImageInput: true,
      );
      expect(definitionNames(definitions), <String>[
        PhoneAgentToolNames.screenshot,
        PhoneAgentToolNames.tree,
        PhoneAgentToolNames.input,
      ]);
      final encoded = jsonEncode(definitions);
      expect(encoded.contains('snapshot_id'), isFalse);
      for (final definition in definitions) {
        final parameters = parametersOf(
          definitions,
          (definition['function'] as Map)['name'] as String,
        );
        expect(parameters['additionalProperties'], isFalse);
      }
    });

    test('截图与读树描述披露 secure 黑图限制且不暴露 snapshot_id', () {
      final definitions = PhoneAgentTools.buildDefinitions(
        supportsImageInput: true,
      );
      final screenshot = functionOf(
        definitions,
        PhoneAgentToolNames.screenshot,
      );
      final screenshotDescription = (screenshot['description'] as String)
          .toLowerCase();
      expect(screenshotDescription, contains('secure'));
      expect(screenshotDescription, contains('black'));
      expect(screenshotDescription, contains('not a security check'));
      expect(screenshotDescription, contains('phone_agent_tree'));
      expect(screenshotDescription, contains('normal black'));

      final tree = functionOf(definitions, PhoneAgentToolNames.tree);
      final treeDescription = (tree['description'] as String).toLowerCase();
      expect(treeDescription, contains('secure'));
      expect(treeDescription, contains('not guaranteed'));
      expect(treeDescription, contains('prefer the tree'));

      final input = functionOf(definitions, PhoneAgentToolNames.input);
      final inputDescription = (input['description'] as String).toLowerCase();
      expect(inputDescription, contains('black'));
      expect(inputDescription, contains('phone_agent_tree'));

      expect(jsonEncode(definitions).contains('snapshot_id'), isFalse);
    });

    test('非视觉模型没有截图工具但保留坐标输入', () {
      final definitions = PhoneAgentTools.buildDefinitions(
        supportsImageInput: false,
      );
      expect(definitionNames(definitions), <String>[
        PhoneAgentToolNames.tree,
        PhoneAgentToolNames.input,
      ]);
      final parameters = parametersOf(definitions, PhoneAgentToolNames.input);
      final properties = parameters['properties'] as Map<String, dynamic>;
      expect(properties.containsKey('x'), isTrue);
      expect(properties.containsKey('y'), isTrue);
      expect(properties.containsKey('end_x'), isTrue);
      expect(properties.containsKey('end_y'), isTrue);
      final actions = (properties['action'] as Map)['enum'] as List;
      expect(actions, contains('swipe'));
      expect(
        actions,
        containsAll(<String>[
          'tap',
          'long_press',
          'set_text',
          'scroll',
          'wait',
          'list_apps',
          'open_app',
        ]),
      );
      expect(properties.containsKey('package_name'), isTrue);
      expect(jsonEncode(definitions).contains('snapshot_id'), isFalse);
    });

    test('视觉模型的输入动作包含坐标滑动', () {
      final definitions = PhoneAgentTools.buildDefinitions(
        supportsImageInput: true,
      );
      final parameters = parametersOf(definitions, PhoneAgentToolNames.input);
      final properties = parameters['properties'] as Map<String, dynamic>;
      final actions = (properties['action'] as Map)['enum'] as List;
      expect(actions, contains('swipe'));
      for (final key in <String>['x', 'y', 'end_x', 'end_y']) {
        final schema = properties[key] as Map;
        expect(schema['type'], 'number');
        expect(schema['minimum'], 0);
        expect(schema['maximum'], 1);
      }
    });

    test('读树参数有边界和默认值说明', () {
      final definitions = PhoneAgentTools.buildDefinitions(
        supportsImageInput: false,
      );
      final properties =
          parametersOf(definitions, PhoneAgentToolNames.tree)['properties']
              as Map<String, dynamic>;
      expect((properties['offset'] as Map)['minimum'], 0);
      expect((properties['max_nodes'] as Map)['maximum'], 200);
      expect((properties['interactive_only'] as Map)['type'], 'boolean');
    });
  });

  group('读树分发', () {
    test('默认参数转发并包裹结果', () async {
      final result = await PhoneAgentTools.handleCall(
        name: PhoneAgentToolNames.tree,
        args: <String, dynamic>{},
        service: service,
        supportsImageInput: true,
      );

      expect(client.treeCalls.single, (
        offset: 0,
        maxNodes: 120,
        interactiveOnly: false,
      ));
      final decoded = decodeToolResult(result);
      expect(decoded['ok'], isTrue);
      expect(decoded['tool'], PhoneAgentToolNames.tree);
      expect(decoded['untrusted_content'], isTrue);
      expect(decoded['result'], isA<Map>());
    });

    test('自定义参数转发', () async {
      await PhoneAgentTools.handleCall(
        name: PhoneAgentToolNames.tree,
        args: <String, dynamic>{
          'offset': 120,
          'max_nodes': 40,
          'interactive_only': true,
        },
        service: service,
        supportsImageInput: false,
      );

      expect(client.treeCalls.single, (
        offset: 120,
        maxNodes: 40,
        interactiveOnly: true,
      ));
    });

    test('整数值的 double 分页参数被接受', () async {
      await PhoneAgentTools.handleCall(
        name: PhoneAgentToolNames.tree,
        args: <String, dynamic>{'offset': 10.0, 'max_nodes': 20.0},
        service: service,
        supportsImageInput: false,
      );

      expect(client.treeCalls.single, (
        offset: 10,
        maxNodes: 20,
        interactiveOnly: false,
      ));
    });

    test('非整数分页参数返回结构化错误', () async {
      final result = decodeToolResult(
        await PhoneAgentTools.handleCall(
          name: PhoneAgentToolNames.tree,
          args: <String, dynamic>{'offset': 1.5},
          service: service,
          supportsImageInput: false,
        ),
      );

      expect(result['error'], 'invalid_arguments');
      expect(client.treeCalls, isEmpty);
    });

    test('非法分页参数返回结构化错误', () async {
      final result = decodeToolResult(
        await PhoneAgentTools.handleCall(
          name: PhoneAgentToolNames.tree,
          args: <String, dynamic>{'max_nodes': 500},
          service: service,
          supportsImageInput: true,
        ),
      );

      expect(result['error'], 'invalid_arguments');
      expect(result['tool'], PhoneAgentToolNames.tree);
      expect(client.treeCalls, isEmpty);
    });
  });

  group('输入分发', () {
    test('节点点击原样转发参数', () async {
      final result = await PhoneAgentTools.handleCall(
        name: PhoneAgentToolNames.input,
        args: <String, dynamic>{'action': 'tap', 'node_id': 'n3'},
        service: service,
        supportsImageInput: false,
      );

      expect(client.inputCalls.single, <String, dynamic>{
        'action': 'tap',
        'node_id': 'n3',
      });
      expect(decodeToolResult(result)['ok'], isTrue);
    });

    test('系统返回不需要截图', () async {
      await PhoneAgentTools.handleCall(
        name: PhoneAgentToolNames.input,
        args: <String, dynamic>{'action': 'back'},
        service: service,
        supportsImageInput: false,
      );

      expect(client.inputCalls.single, <String, dynamic>{'action': 'back'});
    });

    test('set_text 缺少 node_id 时拒绝', () async {
      final result = decodeToolResult(
        await PhoneAgentTools.handleCall(
          name: PhoneAgentToolNames.input,
          args: <String, dynamic>{'action': 'set_text', 'text': 'hello'},
          service: service,
          supportsImageInput: true,
        ),
      );

      expect(result['error'], 'invalid_arguments');
      expect(result['message'], contains('node_id'));
      expect(client.inputCalls, isEmpty);
    });

    test('set_text 缺少 text 时拒绝', () async {
      final result = decodeToolResult(
        await PhoneAgentTools.handleCall(
          name: PhoneAgentToolNames.input,
          args: <String, dynamic>{'action': 'set_text', 'node_id': 'n1'},
          service: service,
          supportsImageInput: true,
        ),
      );

      expect(result['error'], 'invalid_arguments');
      expect(result['message'], contains('text'));
      expect(client.inputCalls, isEmpty);
    });

    test('scroll 缺少方向时拒绝', () async {
      final result = decodeToolResult(
        await PhoneAgentTools.handleCall(
          name: PhoneAgentToolNames.input,
          args: <String, dynamic>{'action': 'scroll', 'node_id': 'n1'},
          service: service,
          supportsImageInput: true,
        ),
      );

      expect(result['error'], 'invalid_arguments');
      expect(result['message'], contains('direction'));
    });

    test('非视觉模型也可以使用坐标点击', () async {
      final result = decodeToolResult(
        await PhoneAgentTools.handleCall(
          name: PhoneAgentToolNames.input,
          args: <String, dynamic>{'action': 'tap', 'x': 0.5, 'y': 0.5},
          service: service,
          supportsImageInput: false,
        ),
      );

      expect(result['ok'], isTrue);
      expect(client.inputCalls, hasLength(1));
    });

    test('非视觉模型也可以滑动', () async {
      final result = decodeToolResult(
        await PhoneAgentTools.handleCall(
          name: PhoneAgentToolNames.input,
          args: <String, dynamic>{
            'action': 'swipe',
            'x': 0.5,
            'y': 0.8,
            'end_x': 0.5,
            'end_y': 0.2,
          },
          service: service,
          supportsImageInput: false,
        ),
      );

      expect(result['ok'], isTrue);
      expect(client.inputCalls, hasLength(1));
    });

    test('坐标越界时拒绝', () async {
      final result = decodeToolResult(
        await PhoneAgentTools.handleCall(
          name: PhoneAgentToolNames.input,
          args: <String, dynamic>{'action': 'tap', 'x': 1.5, 'y': 0.5},
          service: service,
          supportsImageInput: true,
        ),
      );

      expect(result['error'], 'invalid_arguments');
      expect(result['message'], contains('[0,1]'));
    });

    test('NaN 坐标时拒绝', () async {
      final result = decodeToolResult(
        await PhoneAgentTools.handleCall(
          name: PhoneAgentToolNames.input,
          args: <String, dynamic>{'action': 'tap', 'x': double.nan, 'y': 0.5},
          service: service,
          supportsImageInput: true,
        ),
      );

      expect(result['error'], 'invalid_arguments');
    });

    test('同时给出 node_id 和坐标时拒绝', () async {
      final result = decodeToolResult(
        await PhoneAgentTools.handleCall(
          name: PhoneAgentToolNames.input,
          args: <String, dynamic>{
            'action': 'tap',
            'node_id': 'n1',
            'x': 0.5,
            'y': 0.5,
          },
          service: service,
          supportsImageInput: true,
        ),
      );

      expect(result['error'], 'invalid_arguments');
    });

    test('未知动作时拒绝', () async {
      final result = decodeToolResult(
        await PhoneAgentTools.handleCall(
          name: PhoneAgentToolNames.input,
          args: <String, dynamic>{'action': 'unknown_action'},
          service: service,
          supportsImageInput: true,
        ),
      );

      expect(result['error'], 'invalid_arguments');
      expect(result['instruction'], isNotEmpty);
    });

    test('手势时长越界时拒绝', () async {
      final result = decodeToolResult(
        await PhoneAgentTools.handleCall(
          name: PhoneAgentToolNames.input,
          args: <String, dynamic>{
            'action': 'tap',
            'node_id': 'n1',
            'duration_ms': 10,
          },
          service: service,
          supportsImageInput: true,
        ),
      );

      expect(result['error'], 'invalid_arguments');
    });

    test('wait 动作支持 100..5000ms 并拒绝越界时长', () async {
      final defaultWait = decodeToolResult(
        await PhoneAgentTools.handleCall(
          name: PhoneAgentToolNames.input,
          args: <String, dynamic>{'action': 'wait'},
          service: service,
          supportsImageInput: false,
        ),
      );
      expect(defaultWait['ok'], isTrue);

      final boundedWait = decodeToolResult(
        await PhoneAgentTools.handleCall(
          name: PhoneAgentToolNames.input,
          args: <String, dynamic>{'action': 'wait', 'duration_ms': 3000},
          service: service,
          supportsImageInput: false,
        ),
      );
      expect(boundedWait['ok'], isTrue);
      expect(client.inputCalls, hasLength(2));

      final tooShort = decodeToolResult(
        await PhoneAgentTools.handleCall(
          name: PhoneAgentToolNames.input,
          args: <String, dynamic>{'action': 'wait', 'duration_ms': 50},
          service: service,
          supportsImageInput: false,
        ),
      );
      expect(tooShort['error'], 'invalid_arguments');

      final tooLong = decodeToolResult(
        await PhoneAgentTools.handleCall(
          name: PhoneAgentToolNames.input,
          args: <String, dynamic>{'action': 'wait', 'duration_ms': 6000},
          service: service,
          supportsImageInput: false,
        ),
      );
      expect(tooLong['error'], 'invalid_arguments');
    });

    test('坐标 long_press 低于 500ms 时拒绝', () async {
      final result = decodeToolResult(
        await PhoneAgentTools.handleCall(
          name: PhoneAgentToolNames.input,
          args: <String, dynamic>{
            'action': 'long_press',
            'x': 0.5,
            'y': 0.5,
            'duration_ms': 499,
          },
          service: service,
          supportsImageInput: true,
        ),
      );

      expect(result['error'], 'invalid_arguments');
      expect(result['message'], contains('500'));
      expect(client.inputCalls, isEmpty);
    });

    test('节点 long_press 低于 500ms 时拒绝', () async {
      final result = decodeToolResult(
        await PhoneAgentTools.handleCall(
          name: PhoneAgentToolNames.input,
          args: <String, dynamic>{
            'action': 'long_press',
            'node_id': 'n1',
            'duration_ms': 300,
          },
          service: service,
          supportsImageInput: false,
        ),
      );

      expect(result['error'], 'invalid_arguments');
      expect(result['message'], contains('500'));
      expect(client.inputCalls, isEmpty);
    });

    test('long_press 使用 500ms 时接受', () async {
      await PhoneAgentTools.handleCall(
        name: PhoneAgentToolNames.input,
        args: <String, dynamic>{
          'action': 'long_press',
          'node_id': 'n1',
          'duration_ms': 500,
        },
        service: service,
        supportsImageInput: false,
      );

      expect(client.inputCalls.single['duration_ms'], 500);
    });

    test('tap 允许低于 500ms 的时长', () async {
      await PhoneAgentTools.handleCall(
        name: PhoneAgentToolNames.input,
        args: <String, dynamic>{
          'action': 'tap',
          'node_id': 'n1',
          'duration_ms': 300,
        },
        service: service,
        supportsImageInput: false,
      );

      expect(client.inputCalls.single['duration_ms'], 300);
    });
  });

  group('应用列举与启动', () {
    test('list_apps 直接转发，即使非视觉模型也可用', () async {
      final result = decodeToolResult(
        await PhoneAgentTools.handleCall(
          name: PhoneAgentToolNames.input,
          args: <String, dynamic>{'action': 'list_apps'},
          service: service,
          supportsImageInput: false,
        ),
      );

      expect(result['ok'], isTrue);
      expect(client.inputCalls.single, <String, dynamic>{
        'action': 'list_apps',
      });
    });

    test('open_app 需要 package_name', () async {
      final rejected = decodeToolResult(
        await PhoneAgentTools.handleCall(
          name: PhoneAgentToolNames.input,
          args: <String, dynamic>{'action': 'open_app'},
          service: service,
          supportsImageInput: true,
        ),
      );

      expect(rejected['type'], 'tool_error');
      expect(rejected['error'], 'invalid_arguments');
      expect(client.inputCalls, isEmpty);

      final launched = decodeToolResult(
        await PhoneAgentTools.handleCall(
          name: PhoneAgentToolNames.input,
          args: <String, dynamic>{
            'action': 'open_app',
            'package_name': 'com.example.notes',
          },
          service: service,
          supportsImageInput: false,
        ),
      );

      expect(launched['ok'], isTrue);
      expect(client.inputCalls.single, <String, dynamic>{
        'action': 'open_app',
        'package_name': 'com.example.notes',
      });
    });
  });

  group('截图分发', () {
    test('非视觉模型误调截图时返回结构化错误', () async {
      final result = decodeToolResult(
        await PhoneAgentTools.handleCall(
          name: PhoneAgentToolNames.screenshot,
          args: <String, dynamic>{},
          service: service,
          supportsImageInput: false,
        ),
      );

      expect(result['type'], 'tool_error');
      expect(result['error'], 'image_input_unsupported');
      expect(result['tool'], PhoneAgentToolNames.screenshot);
      expect(client.screenshotCalls, 0);
    });

    test('未知工具返回 unknown_tool', () async {
      final result = decodeToolResult(
        await PhoneAgentTools.handleCall(
          name: 'phone_agent_launch',
          args: <String, dynamic>{},
          service: service,
          supportsImageInput: true,
        ),
      );

      expect(result['error'], 'unknown_tool');
      expect(result['instruction'], contains('phone_agent_tree'));
    });
  });

  test('错误信封包含可执行说明', () async {
    final result = await PhoneAgentTools.handleCall(
      name: PhoneAgentToolNames.input,
      args: <String, dynamic>{'action': 'nope'},
      service: service,
      supportsImageInput: true,
    );

    expect(result, isA<ClientToolResult>());
    final decoded = decodeToolResult(result);
    expect(decoded['type'], 'tool_error');
    expect(decoded['error'], isNotEmpty);
    expect(decoded['message'], isNotEmpty);
    expect(decoded['instruction'], isNotEmpty);
    expect(decoded['tool'], PhoneAgentToolNames.input);
  });

  group('超时映射', () {
    test('截图超时返回 tool_error timeout 且无图片 metadata', () async {
      final slow = _SlowScreenshotClient();
      final shortService = PhoneAgentService(
        client: slow,
        timeout: const Duration(milliseconds: 50),
      );

      final result = await PhoneAgentTools.handleCall(
        name: PhoneAgentToolNames.screenshot,
        args: <String, dynamic>{},
        service: shortService,
        supportsImageInput: true,
      );

      expect(result, isA<ClientToolResult>());
      final clientResult = result as ClientToolResult;
      final decoded = decodeToolResult(clientResult);
      expect(decoded['type'], 'tool_error');
      expect(decoded['error'], 'timeout');
      expect(decoded['tool'], PhoneAgentToolNames.screenshot);
      expect(decoded.containsKey('image'), isFalse);
      expect(clientResult.metadata, isNull);
      expect(clientResult.content.contains('![]('), isFalse);
      expect(clientResult.content.contains('data:image'), isFalse);
      expect(slow.screenshotCalls, 1);
    });

    test('读树超时返回 tool_error timeout', () async {
      client.treeDelay = const Duration(milliseconds: 200);
      final shortService = PhoneAgentService(
        client: client,
        timeout: const Duration(milliseconds: 50),
      );

      final decoded = decodeToolResult(
        await PhoneAgentTools.handleCall(
          name: PhoneAgentToolNames.tree,
          args: <String, dynamic>{},
          service: shortService,
          supportsImageInput: true,
        ),
      );

      expect(decoded['type'], 'tool_error');
      expect(decoded['error'], 'timeout');
      expect(decoded['tool'], PhoneAgentToolNames.tree);
    });
  });
}

class _SlowScreenshotClient extends RecordingPhoneAgentClient {
  @override
  Future<PhoneAgentCapture> screenshot() async {
    screenshotCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return capture;
  }
}
