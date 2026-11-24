import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/core/services/api/tool_call_cancellation.dart';
import 'package:Kelivo/core/services/mcp/mcp_image_snapshot.dart';
import 'package:Kelivo/features/phone_agent/phone_agent_screenshot.dart';
import 'package:Kelivo/features/phone_agent/phone_agent_service.dart';
import 'package:Kelivo/utils/mcp_structured_image.dart';
import 'package:Kelivo/utils/sandbox_path_resolver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kelivo_phone_agent/kelivo_phone_agent.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../support/claude_test_api.dart';
import 'phone_agent_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late PathProviderPlatform originalPaths;
  late RecordingPhoneAgentClient client;
  late PhoneAgentService service;

  setUp(() async {
    client = RecordingPhoneAgentClient();
    service = PhoneAgentService(client: client);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    root = await Directory.systemTemp.createTemp('phone_agent_shot_');
    await Directory('${root.path}/images').create();
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = FakePathProviderPlatform(root.path);
    SandboxPathResolver.debugSetDirs(docsDir: root.path);
  });

  tearDown(() async {
    PathProviderPlatform.instance = originalPaths;
    SandboxPathResolver.debugSetDirs();
    debugDefaultTargetPlatformOverride = null;
    await root.delete(recursive: true);
  });

  PhoneAgentCapture captureFor(
    Uint8List bytes, {
    int imageWidth = 40,
    int imageHeight = 80,
    int screenWidth = 1080,
    int screenHeight = 2160,
    String? packageName = 'com.psyche.kelivo',
    List<PhoneAgentTapMarker> recentTaps = const <PhoneAgentTapMarker>[],
  }) {
    return PhoneAgentCapture(
      bytes: bytes,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      screenWidth: screenWidth,
      screenHeight: screenHeight,
      packageName: packageName,
      recentTaps: recentTaps,
    );
  }

  Uint8List pngBytes({int width = 40, int height = 80}) {
    return img.encodePng(img.Image(width: width, height: height));
  }

  test('截图落盘并返回 mcpResult 图片元数据', () async {
    final result = await PhoneAgentScreenshotResult.build(
      captureFor(pngBytes()),
      toolName: 'phone_agent_screenshot',
      service: service,
    );

    final mcpResult = readMcpResultMetadata(result.metadata);
    expect(mcpResult, isNotNull);
    final uris = mcpResultImageUris(mcpResult);
    expect(uris, hasLength(1));
    expect(result.content, contains('![]('));

    final file = await McpImageSnapshot.localFile(uris.single);
    expect(file, isNotNull);
    final stored = img.decodeImage(await file!.readAsBytes());
    expect(stored, isNotNull);
    expect(stored!.width, 40);
    expect(stored.height, 80);

    final payload =
        jsonDecode(result.content.split('\n').first) as Map<String, dynamic>;
    expect(payload['ok'], isTrue);
    expect(payload['tool'], 'phone_agent_screenshot');
    expect(payload['image'], <String, dynamic>{'width': 40, 'height': 80});
    expect(payload['screen'], <String, dynamic>{'width': 1080, 'height': 2160});
    expect(payload['package_name'], 'com.psyche.kelivo');
    expect(payload.containsKey('recent_taps'), isFalse);
    expect(payload['coordinate_space'], contains('[0,1]'));
    expect(payload['untrusted_content'], isTrue);
    expect(client.clearScreenshotCalls, 0);
  });

  test('存在近期坐标点击时在截图结果中透传 recent_taps', () async {
    final result = await PhoneAgentScreenshotResult.build(
      captureFor(
        pngBytes(),
        recentTaps: const <PhoneAgentTapMarker>[
          PhoneAgentTapMarker(index: 1, action: 'tap', x: 0.42, y: 0.35),
          PhoneAgentTapMarker(index: 2, action: 'long_press', x: 0.42, y: 0.55),
        ],
      ),
      toolName: 'phone_agent_screenshot',
      service: service,
    );

    final payload =
        jsonDecode(result.content.split('\n').first) as Map<String, dynamic>;
    expect(payload['recent_taps'], <Map<String, dynamic>>[
      <String, dynamic>{'index': 1, 'action': 'tap', 'x': 0.42, 'y': 0.35},
      <String, dynamic>{
        'index': 2,
        'action': 'long_press',
        'x': 0.42,
        'y': 0.55,
      },
    ]);
  });

  test('空截图字节返回结构化错误并清理原生观测', () async {
    await expectLater(
      PhoneAgentScreenshotResult.build(
        captureFor(Uint8List(0)),
        toolName: 'phone_agent_screenshot',
        service: service,
      ),
      throwsA(
        isA<PhoneAgentToolFailure>().having(
          (error) => error.code,
          'code',
          'screenshot_empty',
        ),
      ),
    );
    expect(client.clearScreenshotCalls, 1);
  });

  test('非法图片尺寸返回结构化错误并清理原生观测', () async {
    await expectLater(
      PhoneAgentScreenshotResult.build(
        captureFor(pngBytes(), imageWidth: 0),
        toolName: 'phone_agent_screenshot',
        service: service,
      ),
      throwsA(
        isA<PhoneAgentToolFailure>().having(
          (error) => error.code,
          'code',
          'screenshot_invalid_size',
        ),
      ),
    );
    expect(client.clearScreenshotCalls, 1);
  });

  test('非法物理屏幕尺寸返回结构化错误并清理原生观测', () async {
    await expectLater(
      PhoneAgentScreenshotResult.build(
        captureFor(pngBytes(), screenHeight: 0),
        toolName: 'phone_agent_screenshot',
        service: service,
      ),
      throwsA(
        isA<PhoneAgentToolFailure>().having(
          (error) => error.code,
          'code',
          'screenshot_invalid_size',
        ),
      ),
    );
    expect(client.clearScreenshotCalls, 1);
  });

  test('落盘尺寸与原生声明不一致时失败并清理原生观测', () async {
    await expectLater(
      PhoneAgentScreenshotResult.build(
        captureFor(pngBytes(), imageWidth: 41),
        toolName: 'phone_agent_screenshot',
        service: service,
      ),
      throwsA(
        isA<PhoneAgentToolFailure>()
            .having((error) => error.code, 'code', 'screenshot_size_mismatch')
            .having((error) => error.instruction, 'instruction', isNotEmpty),
      ),
    );
    expect(client.clearScreenshotCalls, 1);
  });

  test('无法解码的截图返回保存失败并清理原生观测', () async {
    await expectLater(
      PhoneAgentScreenshotResult.build(
        captureFor(Uint8List.fromList(<int>[1, 2, 3, 4])),
        toolName: 'phone_agent_screenshot',
        service: service,
      ),
      throwsA(
        isA<PhoneAgentToolFailure>().having(
          (error) => error.code,
          'code',
          'screenshot_save_failed',
        ),
      ),
    );
    expect(client.clearScreenshotCalls, 1);
  });

  test('清理失败不覆盖原始截图错误', () async {
    client.clearScreenshotError = StateError('cleanup failed');

    await expectLater(
      PhoneAgentScreenshotResult.build(
        captureFor(Uint8List.fromList(<int>[1, 2, 3, 4])),
        toolName: 'phone_agent_screenshot',
        service: service,
      ),
      throwsA(
        isA<PhoneAgentToolFailure>().having(
          (error) => error.code,
          'code',
          'screenshot_save_failed',
        ),
      ),
    );
    expect(client.clearScreenshotCalls, 1);
  });

  test('生成取消时跳过原生清理', () async {
    var cancelled = false;
    final token = ToolCallCancellation(
      isCancelled: () => cancelled,
      cancelled: Completer<void>().future,
    );

    await expectLater(
      token.run(() async {
        cancelled = true;
        return PhoneAgentScreenshotResult.build(
          captureFor(pngBytes()),
          toolName: 'phone_agent_screenshot',
          service: service,
        );
      }),
      throwsA(isA<StateError>()),
    );
    expect(client.clearScreenshotCalls, 0);
  });
}
