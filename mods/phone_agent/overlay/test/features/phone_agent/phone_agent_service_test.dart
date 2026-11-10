import 'package:Kelivo/features/phone_agent/phone_agent_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelivo_phone_agent/kelivo_phone_agent.dart';

import 'phone_agent_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RecordingPhoneAgentClient client;
  late PhoneAgentService service;

  setUp(() {
    client = RecordingPhoneAgentClient();
    service = PhoneAgentService(client: client);
  });

  test('状态和设置委托给客户端', () async {
    final availability = await service.status();
    await service.openAccessibilitySettings();

    expect(availability.ready, isTrue);
    expect(availability.androidSdkInt, 34);
    expect(client.statusCalls, 1);
    expect(client.openSettingsCalls, 1);
  });

  test('读树默认参数', () async {
    final result = await service.readTree();

    expect(client.treeCalls.single, (
      offset: 0,
      maxNodes: 120,
      interactiveOnly: false,
    ));
    expect(result, client.treeResult);
  });

  test('读树和输入参数原样转发', () async {
    await service.readTree(offset: 30, maxNodes: 50, interactiveOnly: true);
    await service.input(<String, dynamic>{'action': 'tap', 'node_id': 'n2'});

    expect(client.treeCalls.single, (
      offset: 30,
      maxNodes: 50,
      interactiveOnly: true,
    ));
    expect(client.inputCalls.single, <String, dynamic>{
      'action': 'tap',
      'node_id': 'n2',
    });
  });

  test('截图字段转换为适配层类型', () async {
    final capture = await service.screenshot();

    expect(client.screenshotCalls, 1);
    expect(capture.imageWidth, 100);
    expect(capture.imageHeight, 200);
    expect(capture.screenWidth, 1080);
    expect(capture.screenHeight, 2160);
    expect(capture.packageName, 'com.psyche.kelivo');
    expect(capture.bytes, isNotEmpty);
  });

  test('清理截图观测委托给客户端', () async {
    await service.clearScreenshot();

    expect(client.clearScreenshotCalls, 1);
  });

  test('插件结构化异常保留 code 和 message', () async {
    client.treeError = PhoneAgentException(
      'stale_handle',
      'Node handle expired; read the tree again.',
    );

    await expectLater(
      service.readTree(),
      throwsA(
        isA<PhoneAgentToolFailure>()
            .having((error) => error.code, 'code', 'stale_handle')
            .having((error) => error.message, 'message', contains('expired'))
            .having((error) => error.instruction, 'instruction', isNotEmpty),
      ),
    );
  });

  test('PlatformException 转换为结构化失败', () async {
    client.inputError = PlatformException(
      code: 'locked',
      message: 'Unlock the device first.',
    );

    await expectLater(
      service.input(<String, dynamic>{'action': 'back'}),
      throwsA(
        isA<PhoneAgentToolFailure>()
            .having((error) => error.code, 'code', 'locked')
            .having((error) => error.message, 'message', contains('Unlock')),
      ),
    );
  });

  test('插件缺失转换为 plugin_unavailable', () async {
    client.screenshotError = MissingPluginException('no plugin');

    await expectLater(
      service.screenshot(),
      throwsA(
        isA<PhoneAgentToolFailure>().having(
          (error) => error.code,
          'code',
          'plugin_unavailable',
        ),
      ),
    );
  });

  test('超时转换为 timeout', () async {
    final fast = PhoneAgentService(
      client: client,
      timeout: const Duration(milliseconds: 10),
    );
    client.treeDelay = const Duration(milliseconds: 200);

    await expectLater(
      fast.readTree(),
      throwsA(
        isA<PhoneAgentToolFailure>()
            .having((error) => error.code, 'code', 'timeout')
            .having((error) => error.instruction, 'instruction', isNotEmpty),
      ),
    );
  });

  test('未知异常转换为 phone_agent_error', () async {
    client.treeError = StateError('boom');

    await expectLater(
      service.readTree(),
      throwsA(
        isA<PhoneAgentToolFailure>()
            .having((error) => error.code, 'code', 'phone_agent_error')
            .having((error) => error.message, 'message', contains('boom')),
      ),
    );
  });

  test('工具错误信封结构稳定', () {
    const failure = PhoneAgentToolFailure(
      'stale_observation',
      'The screen changed.',
      instruction: 'Take a new screenshot.',
    );

    final result = failure.toToolResult(tool: 'phone_agent_input');
    final decoded = decodeToolResult(result);

    expect(decoded, <String, dynamic>{
      'type': 'tool_error',
      'error': 'stale_observation',
      'message': 'The screen changed.',
      'instruction': 'Take a new screenshot.',
      'tool': 'phone_agent_input',
    });
  });

  group('真实插件通道', () {
    const channel = MethodChannel('kelivo/phone_agent');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<MethodCall> calls;

    setUp(() {
      calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'status':
            return <String, dynamic>{
              'supported': true,
              'enabled': true,
              'connected': true,
              'androidSdkInt': 34,
            };
          case 'screenshot':
            return <String, dynamic>{
              'bytes': Uint8List.fromList(<int>[1, 2, 3, 4]),
              'imageWidth': 800,
              'imageHeight': 600,
              'screenWidth': 1080,
              'screenHeight': 2400,
              'packageName': 'com.psyche.kelivo',
            };
          case 'readTree':
            return <String, dynamic>{
              'offset': 0,
              'next_offset': null,
              'total': 1,
              'truncated': false,
              'text_truncated': false,
              'package_name': 'com.psyche.kelivo',
              'width': 1080,
              'height': 2400,
              'nodes': <dynamic>[
                <String, dynamic>{
                  'node_id': 'n0',
                  'text': 'Hello',
                  'bounds': <int>[0, 0, 10, 10],
                  'class': 'android.widget.TextView',
                  'enabled': true,
                },
              ],
            };
          case 'input':
            return <String, dynamic>{
              'success': true,
              'action': 'tap',
              'message': 'Action accepted.',
            };
          default:
            return null;
        }
      });
    });

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('状态读取真实字段', () async {
      final status = await PhoneAgentService().status();

      expect(calls.single.method, 'status');
      expect(status.supported, isTrue);
      expect(status.enabled, isTrue);
      expect(status.connected, isTrue);
      expect(status.androidSdkInt, 34);
      expect(status.ready, isTrue);
    });

    test('读树使用 snake_case 参数并返回节点', () async {
      final tree = await PhoneAgentService().readTree(
        offset: 10,
        maxNodes: 20,
        interactiveOnly: true,
      );

      expect(calls.single.method, 'readTree');
      expect(calls.single.arguments, <String, dynamic>{
        'offset': 10,
        'max_nodes': 20,
        'interactive_only': true,
      });
      final nodes = tree['nodes'] as List;
      expect(nodes.single['node_id'], 'n0');
      expect(tree['package_name'], 'com.psyche.kelivo');
    });

    test('输入参数原样经过插件通道', () async {
      final result = await PhoneAgentService().input(<String, dynamic>{
        'action': 'tap',
        'node_id': 'n0',
      });

      expect(calls.single.method, 'input');
      expect(calls.single.arguments, <String, dynamic>{
        'action': 'tap',
        'node_id': 'n0',
      });
      expect(result['success'], isTrue);
    });

    test('截图解析真实通道字段', () async {
      final capture = await PhoneAgentService().screenshot();

      expect(calls.single.method, 'screenshot');
      expect(capture.bytes, <int>[1, 2, 3, 4]);
      expect(capture.imageWidth, 800);
      expect(capture.imageHeight, 600);
      expect(capture.screenWidth, 1080);
      expect(capture.screenHeight, 2400);
      expect(capture.packageName, 'com.psyche.kelivo');
    });

    test('清理截图观测经过真实通道', () async {
      await PhoneAgentService().clearScreenshot();

      expect(calls.single.method, 'clearScreenshot');
    });

    test('原生错误码经过插件保留', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(
          code: 'stale_handle',
          message: 'The target node changed.',
        );
      });

      await expectLater(
        PhoneAgentService().input(<String, dynamic>{'action': 'tap'}),
        throwsA(
          isA<PhoneAgentToolFailure>()
              .having((error) => error.code, 'code', 'stale_handle')
              .having(
                (error) => error.message,
                'message',
                'The target node changed.',
              ),
        ),
      );
    });
  });
}
