import 'dart:io';

import 'package:Kelivo/core/services/api/tool_result_content.dart';
import 'package:Kelivo/features/phone_agent/phone_agent_screenshot.dart';
import 'package:Kelivo/features/phone_agent/phone_agent_service.dart';
import 'package:Kelivo/utils/mcp_structured_image.dart';
import 'package:Kelivo/utils/sandbox_path_resolver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
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
    root = await Directory.systemTemp.createTemp('phone_agent_tool_result_');
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

  Future<ClientToolResult> screenshotResult() {
    return PhoneAgentScreenshotResult.build(
      PhoneAgentCapture(
        bytes: img.encodePng(img.Image(width: 40, height: 80)),
        imageWidth: 40,
        imageHeight: 80,
        screenWidth: 1080,
        screenHeight: 2160,
        packageName: 'com.psyche.kelivo.phoneagent',
      ),
      toolName: 'phone_agent_screenshot',
      service: service,
    );
  }

  test('截图 metadata 经 ToolResultContent 在支持图片时产生图片引用', () async {
    final result = await screenshotResult();

    final read = await ToolResultContent.read(
      'phone_agent_screenshot',
      result.content,
      metadata: result.metadata,
    );

    expect(read.imageUrls, hasLength(1));
    expect(read.imageUrls.single, startsWith('data:image/png;base64,'));
    expect(read.imageUrls.single.length, greaterThan(100));
    expect(read.text, isNot(contains('![](')));
    expect(read.text, contains('"tool":"phone_agent_screenshot"'));
    expect(
      read.text,
      contains('"package_name":"com.psyche.kelivo.phoneagent"'),
    );
  });

  test('截图 metadata 经 ToolResultContent 在不支持图片时省略图片', () async {
    final result = await screenshotResult();

    final read = await ToolResultContent.read(
      'phone_agent_screenshot',
      result.content,
      metadata: result.metadata,
      canImageInput: false,
    );

    expect(read.imageUrls, isEmpty);
    expect(read.text, contains('Image omitted'));
    expect(read.text, isNot(contains('![](')));
    expect(read.text, isNot(contains('base64')));
    expect(read.text, contains('"tool":"phone_agent_screenshot"'));
  });
}
