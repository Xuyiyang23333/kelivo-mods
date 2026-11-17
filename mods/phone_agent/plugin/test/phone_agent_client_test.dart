import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelivo_phone_agent/kelivo_phone_agent.dart';
import 'package:kelivo_phone_agent/src/phone_agent_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(PhoneAgentClient.channelName);
  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  void mock(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return handler(call);
        });
  }

  test('status parses native fields', () async {
    mock(
      (call) async => <String, dynamic>{
        'supported': true,
        'enabled': true,
        'connected': true,
        'androidSdkInt': 34,
      },
    );

    final status = await PhoneAgentClient().status();

    expect(status.supported, isTrue);
    expect(status.enabled, isTrue);
    expect(status.connected, isTrue);
    expect(status.androidSdkInt, 34);
    expect(status.ready, isTrue);
    expect(calls.single.method, 'status');
  });

  test('API 29 can use tree and node input when connected', () {
    const status = PhoneAgentStatus(
      supported: false,
      enabled: true,
      connected: true,
      androidSdkInt: 29,
    );

    expect(status.ready, isTrue);
    expect(status.supported, isFalse);
  });

  test('the public singleton uses the same channel', () async {
    mock(
      (call) async => <String, dynamic>{
        'supported': true,
        'enabled': true,
        'connected': true,
        'androidSdkInt': 30,
      },
    );

    final status = await KelivoPhoneAgent.instance.status();

    expect(status.ready, isTrue);
    expect(calls.single.method, 'status');
  });

  test('status rejects a malformed payload', () async {
    mock((call) async => <String, dynamic>{'supported': true});

    await expectLater(
      PhoneAgentClient().status(),
      throwsA(
        isA<PhoneAgentException>().having(
          (error) => error.code,
          'code',
          'invalid_response',
        ),
      ),
    );
  });

  test('openAccessibilitySettings forwards the call', () async {
    mock((call) async => null);

    await PhoneAgentClient().openAccessibilitySettings();

    expect(calls.single.method, 'openAccessibilitySettings');
  });

  test('screenshot parses bytes and dimensions', () async {
    final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
    mock(
      (call) async => <String, dynamic>{
        'bytes': bytes,
        'imageWidth': 800,
        'imageHeight': 600,
        'screenWidth': 1080,
        'screenHeight': 2400,
        'packageName': 'com.psyche.kelivo',
      },
    );

    final shot = await PhoneAgentClient().screenshot();

    expect(shot.bytes, bytes);
    expect(shot.imageWidth, 800);
    expect(shot.imageHeight, 600);
    expect(shot.screenWidth, 1080);
    expect(shot.screenHeight, 2400);
    expect(shot.packageName, 'com.psyche.kelivo');
  });

  test('screenshot rejects empty bytes', () async {
    mock(
      (call) async => <String, dynamic>{
        'bytes': Uint8List(0),
        'imageWidth': 800,
        'imageHeight': 600,
        'screenWidth': 1080,
        'screenHeight': 2400,
      },
    );

    await expectLater(
      PhoneAgentClient().screenshot(),
      throwsA(
        isA<PhoneAgentException>().having(
          (error) => error.code,
          'code',
          'invalid_response',
        ),
      ),
    );
  });

  test('clearScreenshot forwards the call', () async {
    mock((call) async => <String, dynamic>{'cleared': true});

    await PhoneAgentClient().clearScreenshot();

    expect(calls.single.method, 'clearScreenshot');
  });

  test(
    'the public singleton clears the native screenshot observation',
    () async {
      mock((call) async => <String, dynamic>{'cleared': true});

      await KelivoPhoneAgent.instance.clearScreenshot();

      expect(calls.single.method, 'clearScreenshot');
    },
  );

  test('readTree sends the documented defaults', () async {
    mock(
      (call) async => <String, dynamic>{
        'offset': 0,
        'next_offset': null,
        'total': 0,
        'truncated': false,
        'text_truncated': false,
        'package_name': 'com.psyche.kelivo',
        'width': 1080,
        'height': 2400,
        'nodes': <dynamic>[],
      },
    );

    final page = await PhoneAgentClient().readTree();

    expect(calls.single.method, 'readTree');
    expect(calls.single.arguments, <String, dynamic>{
      'offset': 0,
      'max_nodes': 120,
      'interactive_only': false,
    });
    expect(page['nodes'], isEmpty);
  });

  test('readTree validates local arguments before invoking', () async {
    mock((call) async => <String, dynamic>{});

    await expectLater(
      PhoneAgentClient().readTree(maxNodes: 0),
      throwsA(
        isA<PhoneAgentException>().having(
          (error) => error.code,
          'code',
          'invalid_argument',
        ),
      ),
    );
    await expectLater(
      PhoneAgentClient().readTree(offset: -1),
      throwsA(isA<PhoneAgentException>()),
    );
    expect(calls, isEmpty);
  });

  test('input forwards snake_case arguments', () async {
    mock(
      (call) async => <String, dynamic>{
        'success': true,
        'action': 'tap',
        'message': 'Action accepted.',
      },
    );

    final result = await PhoneAgentClient().input(<String, dynamic>{
      'action': 'tap',
      'node_id': 'n3',
    });

    expect(calls.single.method, 'input');
    expect(calls.single.arguments, <String, dynamic>{
      'action': 'tap',
      'node_id': 'n3',
    });
    expect(result['success'], isTrue);
  });

  test('input rejects snapshot_id without invoking', () async {
    mock((call) async => <String, dynamic>{});

    await expectLater(
      PhoneAgentClient().input(<String, dynamic>{
        'action': 'tap',
        'snapshot_id': 'legacy',
      }),
      throwsA(
        isA<PhoneAgentException>()
            .having((error) => error.code, 'code', 'invalid_argument')
            .having(
              (error) => error.message,
              'message',
              contains('snapshot_id'),
            ),
      ),
    );
    expect(calls, isEmpty);
  });

  test('input requires an action', () async {
    mock((call) async => <String, dynamic>{});

    await expectLater(
      PhoneAgentClient().input(<String, dynamic>{}),
      throwsA(isA<PhoneAgentException>()),
    );
    expect(calls, isEmpty);
  });

  test('platform errors become structured exceptions', () async {
    mock(
      (call) async => throw PlatformException(
        code: 'stale_handle',
        message: 'The target node changed.',
      ),
    );

    await expectLater(
      PhoneAgentClient().input(<String, dynamic>{'action': 'tap'}),
      throwsA(
        isA<PhoneAgentException>()
            .having((error) => error.code, 'code', 'stale_handle')
            .having(
              (error) => error.message,
              'message',
              'The target node changed.',
            ),
      ),
    );
  });

  test('missing plugin becomes unsupported_platform', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => throw MissingPluginException(),
        );

    await expectLater(
      PhoneAgentClient().status(),
      throwsA(
        isA<PhoneAgentException>().having(
          (error) => error.code,
          'code',
          'unsupported_platform',
        ),
      ),
    );
  });

  test('a slow native call times out with an actionable error', () async {
    mock((call) async => Completer<Object?>().future);

    await expectLater(
      PhoneAgentClient(timeout: const Duration(milliseconds: 20)).status(),
      throwsA(
        isA<PhoneAgentException>().having(
          (error) => error.code,
          'code',
          'timeout',
        ),
      ),
    );
  });
}
