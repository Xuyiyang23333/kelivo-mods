import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';

import 'package:Kelivo/core/services/mcp/mcp_image_snapshot.dart';
import 'package:Kelivo/features/phone_agent/phone_agent_service.dart';
import 'package:Kelivo/features/phone_agent/phone_agent_tools.dart';
import 'package:Kelivo/utils/mcp_structured_image.dart';

// 真实 FLAG_SECURE 与受控异常路径套件。
//
// 前置条件：
// - Android API 30+ 设备已解锁，系统无障碍设置中已启用 Kelivo Phone Agent；
// - Mods 页已为测试助手选择 Phone Agent；
// - 测试会打印 PHONE_AGENT_* 标记，宿主/CU 在标记后执行对应 adb 或系统 UI 操作；
// - 禁止用 settings put secure 写无障碍授权。
//
// flutter test integration_test/phone_agent_exception_test.dart -d <android-device-id>
const String _appPackage = 'com.psyche.kelivo.phoneagent';
const String _tapTarget = 'PHONE_AGENT_TAP_TARGET';
const String _fixtureText = 'PHONE_AGENT_SECURE_FIXTURE';
const String _fixtureActivity =
    'com.psyche.kelivo.phoneagent/com.kelivo.phoneagent.SecureWindowFixtureActivity';
// Different-UID fixture for real FLAG_SECURE. Both same-UID and different-UID
// secure windows returned successful black images on API35; the display
// takeScreenshot path has no secure check, so UID is not the cause.
const String _secureFixturePackage = 'com.kelivo.phoneagent.securefixture';
const String _secureFixtureActivity =
    'com.kelivo.phoneagent.securefixture/com.kelivo.phoneagent.securefixture.SecureFixtureActivity';

const Duration _pollInterval = Duration(milliseconds: 1500);
const Duration _screenshotInterval = Duration(milliseconds: 2200);
const Duration _hostTimeout = Duration(seconds: 120);

const Set<String> _systemPackages = <String>{
  'com.android.systemui',
  'com.android.permissioncontroller',
  'com.google.android.permissioncontroller',
  'com.android.packageinstaller',
  'com.google.android.packageinstaller',
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late PhoneAgentService service;

  setUpAll(() async {
    expect(
      Platform.isAndroid,
      isTrue,
      reason: 'Phone Agent 异常测试只能在 Android 真机上运行。',
    );
    service = PhoneAgentService.instance;
    await _waitForService(service);
  });

  testWidgets('FLAG_SECURE 截图行为与恢复', (tester) async {
    await _pumpHarness(tester);
    await _ensureAppForeground(service);

    final baseline = await _screenshot(service);
    final baselinePayload = _expectScreenshotOk(baseline, '基线截图');
    expect(baselinePayload['package_name'], _appPackage);

    final fixtureTree = await _waitForTreeText(
      service,
      marker: 'PHONE_AGENT_SECURE_ON',
      instruction:
          'adb shell am start -n $_secureFixtureActivity --ez secure true',
      text: _fixtureText,
    );
    expect(fixtureTree['package_name'], _secureFixturePackage);
    // API35 实测 secure 夹具树可读；这不是绝对保证，密码/自定义 View/窗口变化仍会影响树。
    expect(_nodeForText(fixtureTree, _fixtureText), isNotNull);

    final captured = await _screenshot(service);
    debugPrint(
      'PHONE_AGENT_SECURE_SCREENSHOT: ${captured.content.split('\n').first}',
    );
    final capturedPayload = _payload(captured);
    if (capturedPayload['type'] == 'tool_error') {
      // 平台明确报错时，不得把图片或图片 metadata 交给模型。
      _expectToolError(
        captured,
        'screenshot_blocked',
        messageContains: 'secure',
        step: 'secure 截图',
      );
      debugPrint('PHONE_AGENT_SECURE_EXPLICIT_ERROR');
    } else {
      // 历史：早期严格预期只有 screenshot_blocked；API35 整屏 takeScreenshot
      // 对 FLAG_SECURE 可能返回成功黑图，也可能返回成功内容图。契约只承诺
      // “可能黑化”，不保证黑图；严格失败历史保留在 plan 9.3.1。
      _expectScreenshotOk(captured, 'secure 截图');
      expect(capturedPayload['package_name'], _secureFixturePackage);
      final brightness = await _screenshotAverageBrightness(captured);
      if (brightness < 10) {
        debugPrint('PHONE_AGENT_SECURE_PLATFORM_BLACK_IMAGE');
      } else {
        debugPrint(
          'PHONE_AGENT_SECURE_PLATFORM_CONTENT_IMAGE: '
          'avg=${brightness.toStringAsFixed(1)}',
        );
      }
    }

    // 用同一包内的夹具切换窗口，让基线截图坐标失效；包名策略仍允许输入。
    final staleWindowTree = await _waitForTreeWhere(
      service,
      (tree) =>
          tree['package_name'] == _appPackage &&
          _nodeForText(tree, _fixtureText) != null,
      marker: 'PHONE_AGENT_STALE_WINDOW',
      instruction: 'adb shell am start -n $_fixtureActivity --ez secure false',
      timeout: const Duration(seconds: 60),
    );
    expect(
      staleWindowTree,
      isNotNull,
      reason: '没有切换到同包夹具，旧坐标无法验证 stale_observation。',
    );
    final staleCoordinates = await _input(service, <String, dynamic>{
      'action': 'tap',
      'x': 0.5,
      'y': 0.5,
    });
    _expectToolError(
      staleCoordinates,
      'stale_observation',
      step: 'secure 后旧坐标',
    );

    final restored = await _waitForScreenshotSuccess(
      service,
      marker: 'PHONE_AGENT_SECURE_OFF',
      instruction:
          'adb shell am start -n $_secureFixtureActivity --ez secure false',
      requiredPackage: _secureFixturePackage,
    );
    final restoredPayload = _expectScreenshotOk(restored, '恢复截图');
    expect(restoredPayload['package_name'], _secureFixturePackage);
    await _expectFixturePixels(restored);

    await _waitForTreeText(
      service,
      marker: 'PHONE_AGENT_RETURN_TO_APP',
      instruction:
          'adb shell am start -n $_appPackage/com.psyche.kelivo.MainActivity',
      text: _tapTarget,
    );
    final appTree = await _tree(service);
    expect(_nodeForText(appTree, _tapTarget), isNotNull);
    await Future<void>.delayed(_screenshotInterval);
    _expectScreenshotOk(await _screenshot(service), '返回应用截图');
  });

  testWidgets('旋转后旧句柄与旧截图失效', (tester) async {
    addTearDown(
      () => SystemChrome.setPreferredOrientations(DeviceOrientation.values),
    );
    await _pumpHarness(tester);
    await _ensureAppForeground(service);

    final before = await _tree(service);
    expect(
      (before['width'] as num) < (before['height'] as num),
      isTrue,
      reason: '旋转测试要求初始为竖屏。',
    );
    final tapNode = _nodeForText(before, _tapTarget);
    expect(tapNode, isNotNull, reason: '旋转前读树没有找到点击目标。');
    _expectScreenshotOk(await _screenshot(service), '旋转前截图');

    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
    ]);
    await Future<void>.delayed(const Duration(seconds: 1));
    await tester.pump();
    var rotated = await _waitForViewOrientation(
      tester,
      landscape: true,
      timeout: const Duration(seconds: 20),
    );
    if (!rotated) {
      _hostStep(
        'PHONE_AGENT_ROTATION_HOST_ACTION',
        'adb shell cmd window user-rotation lock 1',
      );
      rotated = await _waitForViewOrientation(
        tester,
        landscape: true,
        timeout: const Duration(seconds: 60),
      );
    }
    expect(rotated, isTrue, reason: '旋转后 Flutter 视图没有变成横屏。');

    final staleHandle = await _input(service, <String, dynamic>{
      'action': 'tap',
      'node_id': tapNode!['node_id'],
    });
    _expectToolError(staleHandle, 'stale_handle', step: '旋转后旧句柄');

    final staleScreenshot = await _input(service, <String, dynamic>{
      'action': 'tap',
      'x': 0.5,
      'y': 0.5,
    });
    _expectToolError(staleScreenshot, 'stale_observation', step: '旋转后旧截图坐标');

    await Future<void>.delayed(_screenshotInterval);
    _expectScreenshotOk(await _screenshot(service), '旋转后新截图');
    final rotatedTree = await _waitForTreeWhere(
      service,
      (tree) =>
          tree['package_name'] == _appPackage &&
          _nodeForText(tree, _tapTarget) != null,
      timeout: const Duration(seconds: 30),
    );
    expect(rotatedTree, isNotNull, reason: '旋转后 30 秒内没有在测试应用中重新找到点击目标。');

    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
    await Future<void>.delayed(const Duration(seconds: 1));
    await tester.pump();
    var portrait = await _waitForViewOrientation(
      tester,
      landscape: false,
      timeout: const Duration(seconds: 20),
    );
    if (!portrait) {
      _hostStep(
        'PHONE_AGENT_ROTATION_HOST_ACTION',
        'adb shell cmd window user-rotation lock 0',
      );
      portrait = await _waitForViewOrientation(
        tester,
        landscape: false,
        timeout: const Duration(seconds: 60),
      );
    }
    expect(portrait, isTrue, reason: '转回竖屏后 Flutter 视图没有恢复。');
    final portraitTree = await _waitForTreeWhere(
      service,
      (tree) =>
          tree['package_name'] == _appPackage &&
          _nodeForText(tree, _tapTarget) != null,
      timeout: const Duration(seconds: 30),
    );
    expect(portraitTree, isNotNull, reason: '转回竖屏后没有重新找到点击目标。');
    await Future<void>.delayed(_screenshotInterval);
    _expectScreenshotOk(await _screenshot(service), '转回竖屏截图');
  });

  testWidgets('home 与 recents 后输入被包名策略拒绝', (tester) async {
    await _pumpHarness(tester);
    await _ensureAppForeground(service);

    await _expectSystemNavigationDenied(
      service,
      action: 'home',
      marker: 'PHONE_AGENT_HOME',
    );
    await _waitForTreeText(
      service,
      marker: 'PHONE_AGENT_RETURN_TO_APP',
      instruction:
          'adb shell am start -n $_appPackage/com.psyche.kelivo.MainActivity',
      text: _tapTarget,
    );

    await _expectSystemNavigationDenied(
      service,
      action: 'recents',
      marker: 'PHONE_AGENT_RECENTS',
    );
    await _waitForTreeText(
      service,
      marker: 'PHONE_AGENT_RETURN_TO_APP',
      instruction:
          'adb shell am start -n $_appPackage/com.psyche.kelivo.MainActivity',
      text: _tapTarget,
    );
    final restored = await _tree(service);
    expect(_nodeForText(restored, _tapTarget), isNotNull);
  });

  testWidgets('权限窗口输入被拒绝', (tester) async {
    await _pumpHarness(tester);
    await _ensureAppForeground(service);
    final before = await _tree(service);
    final tapNode = _nodeForText(before, _tapTarget);
    expect(tapNode, isNotNull, reason: '权限测试前读树没有找到点击目标。');

    _hostStep(
      'PHONE_AGENT_PERMISSION_WINDOW',
      'adb shell am start -n $_fixtureActivity --ez requestPermission true',
    );
    final permissionTree = await _waitForTreeWhere(
      service,
      (tree) => _systemPackages.contains(tree['package_name']),
      timeout: const Duration(seconds: 90),
    );
    if (permissionTree == null) {
      _hostStep(
        'PHONE_AGENT_PERMISSION_WINDOW_UNVERIFIED',
        '系统权限弹窗没有出现；本场景记录为未验证，不写成通过。',
      );
      _hostStep('PHONE_AGENT_DISMISS_PERMISSION', 'adb shell input keyevent 4');
      await _returnToApp(service);
      markTestSkipped('系统权限弹窗没有出现，权限窗口场景未验证。');
      return;
    }
    final permissionPackage = permissionTree['package_name'] as String?;
    expect(
      <String>{
        'com.android.permissioncontroller',
        'com.google.android.permissioncontroller',
      },
      contains(permissionPackage),
      reason: '权限窗口前台包名不在预期集合：$permissionPackage',
    );

    final denied = await _input(service, <String, dynamic>{
      'action': 'tap',
      'node_id': tapNode!['node_id'],
    });
    _expectToolError(denied, 'system_window_denied', step: '权限窗口节点输入');
    final backDenied = await _input(service, <String, dynamic>{
      'action': 'back',
    });
    _expectToolError(backDenied, 'system_window_denied', step: '权限窗口 back');

    _hostStep('PHONE_AGENT_DISMISS_PERMISSION', 'adb shell input keyevent 4');
    await _returnToApp(service);
  });

  testWidgets('锁屏 device_locked 与解锁恢复', (tester) async {
    await _pumpHarness(tester);
    await _ensureAppForeground(service);
    final before = await _tree(service);
    final tapNode = _nodeForText(before, _tapTarget);
    expect(tapNode, isNotNull, reason: '锁屏测试前读树没有找到点击目标。');

    _hostStep('PHONE_AGENT_LOCK_SCREEN', '按一次电源键保持息屏，等待 device_locked');
    final locked = await _waitForToolError(
      service,
      'device_locked',
      timeout: const Duration(seconds: 60),
    );
    expect(locked, isTrue, reason: '锁屏后没有观察到 device_locked。');

    // 同一锁屏窗口分别验证 tree、screenshot、input，避免只靠共同 guard 推断。
    final lockedScreenshot = await _screenshot(service);
    _expectToolError(lockedScreenshot, 'device_locked', step: '锁屏截图');
    final lockedInput = await _input(service, <String, dynamic>{
      'action': 'back',
    });
    _expectToolError(lockedInput, 'device_locked', step: '锁屏输入');

    final lockedStatus = await service.status();
    expect(lockedStatus.ready, isTrue, reason: '锁屏不应让服务状态变成未就绪。');

    _hostStep('PHONE_AGENT_UNLOCK_SCREEN', '解锁设备（无密码或使用已配置的解锁方式）');
    await _waitForAppScreenshot(service);

    final staleHandle = await _input(service, <String, dynamic>{
      'action': 'tap',
      'node_id': tapNode!['node_id'],
    });
    _expectToolError(staleHandle, 'stale_handle', step: '解锁后旧句柄');
    final newTree = await _tree(service);
    expect(_nodeForText(newTree, _tapTarget), isNotNull);
    await Future<void>.delayed(_screenshotInterval);
    _expectScreenshotOk(await _screenshot(service), '解锁后新截图');
  });

  testWidgets('服务禁用中断与重新启用恢复', (tester) async {
    await _pumpHarness(tester);
    await _ensureAppForeground(service);
    final before = await _tree(service);
    final tapNode = _nodeForText(before, _tapTarget);
    expect(tapNode, isNotNull, reason: '服务禁用测试前读树没有找到点击目标。');

    _hostStep(
      'PHONE_AGENT_PREPARE_SERVICE_DISABLE',
      '打开 Kelivo Phone Agent 无障碍详情页并停留在开关前，不要关闭服务',
    );
    final detailTree = await _waitForTreeWhere(
      service,
      (tree) => tree['package_name'] == 'com.android.settings',
      timeout: const Duration(seconds: 30),
    );
    expect(detailTree, isNotNull, reason: '宿主没有打开无障碍设置页。');

    _hostStep(
      'PHONE_AGENT_OPEN_DISABLE_DIALOG',
      '点击 Kelivo Phone Agent 开关，打开关闭确认窗口',
    );
    final settingsTree = await _waitForTreeWhere(
      service,
      (tree) =>
          tree['package_name'] == 'com.android.settings' &&
          _nodeForText(tree, 'Turn off') != null,
      timeout: const Duration(seconds: 30),
    );
    expect(settingsTree, isNotNull, reason: '宿主没有打开无障碍关闭确认窗口。');

    // 先建立 Settings 观测，再启动一批只读分页请求并保留这些 Future。
    // 宿主在它们仍 pending 时关闭服务，验证原 Future 在超时前完成。
    await _tree(service);
    const batchSize = 1000;
    final pending = <Future<Map<String, dynamic>>>[
      for (var i = 0; i < batchSize; i++)
        service.readTree(offset: 1, maxNodes: 120),
    ];
    final startedAt = DateTime.now();
    _hostStep(
      'PHONE_AGENT_DISABLE_DURING_PENDING',
      '现在在已打开的无障碍详情页关闭 Kelivo Phone Agent',
    );

    final codes = await Future.wait(
      pending.map((future) async {
        try {
          await future;
          return 'ok';
        } on PhoneAgentToolFailure catch (failure) {
          return failure.code;
        } catch (_) {
          return 'error';
        }
      }),
    );
    final elapsed = DateTime.now().difference(startedAt);
    final observed = codes.toSet().toList()..sort();
    debugPrint(
      'PHONE_AGENT_SERVICE_PENDING_BATCH: size=$batchSize '
      'elapsed=${elapsed.inMilliseconds}ms codes=${observed.join(",")}',
    );
    expect(
      elapsed,
      lessThan(const Duration(seconds: 35)),
      reason: '禁用前启动的 pending 请求没有在超时前完成。',
    );
    expect(
      observed,
      isNot(contains('timeout')),
      reason: 'pending 出现了 timeout。',
    );
    expect(
      codes.any(
        (code) => code == 'interrupted' || code == 'service_unavailable',
      ),
      isTrue,
      reason: '禁用前启动的 pending 请求没有以 interrupted/service_unavailable 完成。',
    );

    final disabledStatus = await service.status();
    expect(disabledStatus.enabled, isFalse);
    expect(disabledStatus.ready, isFalse);

    _hostStep(
      'PHONE_AGENT_ENABLE_SERVICE_NOW',
      '在系统无障碍设置中重新启用 Kelivo Phone Agent',
    );
    await _waitForService(service);
    await _waitForAppScreenshot(service);

    final staleHandle = await _input(service, <String, dynamic>{
      'action': 'tap',
      'node_id': tapNode!['node_id'],
    });
    _expectToolError(staleHandle, 'stale_handle', step: '服务重启后旧句柄');
    final newTree = await _tree(service);
    expect(_nodeForText(newTree, _tapTarget), isNotNull);
    await Future<void>.delayed(_screenshotInterval);
    _expectScreenshotOk(await _screenshot(service), '服务重启后新截图');
  });
}

Future<void> _pumpHarness(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text(_tapTarget))),
    ),
  );
  await tester.pump();
  await Future<void>.delayed(const Duration(milliseconds: 500));
}

Future<void> _waitForService(PhoneAgentService service) async {
  var status = await service.status();
  if (!status.ready) {
    debugPrint('PHONE_AGENT_WAITING_FOR_SERVICE');
    for (var i = 0; i < 600 && !status.ready; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      status = await service.status();
    }
  }
  expect(
    status.ready,
    isTrue,
    reason:
        'Phone Agent 服务未就绪（supported=${status.supported}, '
        'enabled=${status.enabled}, connected=${status.connected}, '
        'sdk=${status.androidSdkInt}）。请解锁设备并在系统无障碍设置中启用服务。',
  );
}

void _hostStep(String marker, String instruction) {
  debugPrint('$marker: $instruction');
}

Future<void> _ensureAppForeground(PhoneAgentService service) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    final tree = await _tryTree(service);
    if (tree != null &&
        tree['package_name'] == _appPackage &&
        _nodeForText(tree, _tapTarget) != null) {
      return;
    }
    await Future<void>.delayed(_pollInterval);
  }
  await _waitForTreeText(
    service,
    marker: 'PHONE_AGENT_RETURN_TO_APP',
    instruction:
        'adb shell am start -n $_appPackage/com.psyche.kelivo.MainActivity',
    text: _tapTarget,
  );
}

Future<void> _returnToApp(PhoneAgentService service) async {
  await _waitForTreeText(
    service,
    marker: 'PHONE_AGENT_RETURN_TO_APP',
    instruction:
        'adb shell am start -n $_appPackage/com.psyche.kelivo.MainActivity',
    text: _tapTarget,
  );
}

/// Wait for the app foreground without creating a new tree observation.
/// Used after lock/service invalidation so an old handle is still stale when
/// it is exercised.
Future<void> _waitForAppScreenshot(PhoneAgentService service) async {
  _hostStep(
    'PHONE_AGENT_RETURN_TO_APP',
    'adb shell am start -n $_appPackage/com.psyche.kelivo.MainActivity',
  );
  final deadline = DateTime.now().add(_hostTimeout);
  while (DateTime.now().isBefore(deadline)) {
    final result = await _screenshot(service);
    final payload = _payload(result);
    if (payload['ok'] == true && payload['package_name'] == _appPackage) {
      return;
    }
    await Future<void>.delayed(_screenshotInterval);
  }
  fail('等待测试应用前台截图超时。');
}

Future<ClientToolResult> _callResult(
  PhoneAgentService service,
  String name, [
  Map<String, dynamic> args = const <String, dynamic>{},
]) async {
  final result = await PhoneAgentTools.handleCall(
    name: name,
    args: args,
    service: service,
    supportsImageInput: true,
  );
  expect(
    result,
    isA<ClientToolResult>(),
    reason: '$name 没有返回 ClientToolResult。',
  );
  return result as ClientToolResult;
}

Future<Map<String, dynamic>> _tree(PhoneAgentService service) async {
  final result = await _callResult(
    service,
    PhoneAgentToolNames.tree,
    <String, dynamic>{'offset': 0},
  );
  final payload = _payload(result);
  _expectOk(payload, '读树');
  final tree = payload['result'];
  expect(tree, isA<Map>(), reason: '读树结果缺少 result。');
  return Map<String, dynamic>.from(tree as Map);
}

Future<Map<String, dynamic>?> _tryTree(PhoneAgentService service) async {
  try {
    final result = await _callResult(
      service,
      PhoneAgentToolNames.tree,
      <String, dynamic>{'offset': 0},
    );
    final payload = _payload(result);
    if (payload['ok'] != true) return null;
    final tree = payload['result'];
    if (tree is! Map) return null;
    return Map<String, dynamic>.from(tree);
  } catch (_) {
    return null;
  }
}

Future<ClientToolResult> _screenshot(PhoneAgentService service) {
  return _callResult(
    service,
    PhoneAgentToolNames.screenshot,
    const <String, dynamic>{},
  );
}

Future<ClientToolResult> _input(
  PhoneAgentService service,
  Map<String, dynamic> args,
) {
  return _callResult(service, PhoneAgentToolNames.input, args);
}

Map<String, dynamic> _expectScreenshotOk(ClientToolResult result, String step) {
  final payload = _payload(result);
  _expectOk(payload, step);
  expect(result.metadata, isNotNull, reason: '$step 没有图片 metadata。');
  final image = payload['image'];
  expect(image, isA<Map>(), reason: '$step 缺少 image。');
  final imageMap = image as Map;
  expect(imageMap['width'], greaterThan(0));
  expect(imageMap['height'], greaterThan(0));
  final screen = payload['screen'];
  expect(screen, isA<Map>(), reason: '$step 缺少 screen。');
  final screenMap = screen as Map;
  expect(screenMap['width'], greaterThan(0));
  expect(screenMap['height'], greaterThan(0));
  return payload;
}

Map<String, dynamic> _payload(ClientToolResult result) {
  final decoded = jsonDecode(result.content.split('\n').first);
  expect(decoded, isA<Map<String, dynamic>>(), reason: '工具结果不是 JSON。');
  return decoded as Map<String, dynamic>;
}

void _expectOk(Map<String, dynamic> payload, String step) {
  if (payload['ok'] == true) return;
  fail(
    '$step 失败：${payload['error']} ${payload['message']} '
    '${payload['instruction'] ?? ''}',
  );
}

void _expectToolError(
  ClientToolResult result,
  String code, {
  String? messageContains,
  required String step,
}) {
  final payload = _payload(result);
  expect(payload['type'], 'tool_error', reason: '$step 不是 tool_error。');
  expect(payload['error'], code, reason: '$step 错误码不符。');
  if (messageContains != null) {
    expect(
      (payload['message'] as String? ?? '').toLowerCase(),
      contains(messageContains.toLowerCase()),
      reason: '$step 错误信息缺少 $messageContains。',
    );
  }
  expect(payload.containsKey('image'), isFalse, reason: '$step 不应包含 image。');
  expect(result.metadata, isNull, reason: '$step 不应包含图片 metadata。');
  expect(result.content.contains('![]('), isFalse);
  expect(result.content.contains('data:image'), isFalse);
}

Future<Map<String, dynamic>> _waitForTreeText(
  PhoneAgentService service, {
  required String marker,
  required String instruction,
  required String text,
  Duration timeout = _hostTimeout,
}) async {
  _hostStep(marker, instruction);
  final deadline = DateTime.now().add(timeout);
  Map<String, dynamic>? last;
  while (DateTime.now().isBefore(deadline)) {
    last = await _tryTree(service);
    if (last != null && _nodeForText(last, text) != null) return last;
    await Future<void>.delayed(_pollInterval);
  }
  fail(
    '等待 $text 超时（标记 $marker）。最后前台包名：'
    '${last?['package_name'] ?? '未知'}',
  );
}

Future<Map<String, dynamic>?> _waitForTreeWhere(
  PhoneAgentService service,
  bool Function(Map<String, dynamic> tree) predicate, {
  String? marker,
  String? instruction,
  Duration timeout = const Duration(seconds: 60),
}) async {
  if (marker != null) _hostStep(marker, instruction ?? '');
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final tree = await _tryTree(service);
    if (tree != null && predicate(tree)) return tree;
    await Future<void>.delayed(_pollInterval);
  }
  return null;
}

Future<bool> _waitForViewOrientation(
  WidgetTester tester, {
  required bool landscape,
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final size = tester.view.physicalSize;
    if ((size.width > size.height) == landscape) return true;
    await tester.pump(const Duration(milliseconds: 200));
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  return false;
}

Future<ClientToolResult> _waitForScreenshotSuccess(
  PhoneAgentService service, {
  required String marker,
  required String instruction,
  String? requiredPackage,
}) async {
  _hostStep(marker, instruction);
  final deadline = DateTime.now().add(_hostTimeout);
  ClientToolResult? last;
  while (DateTime.now().isBefore(deadline)) {
    final current = await _screenshot(service);
    last = current;
    final payload = _payload(current);
    if (payload['ok'] == true &&
        (requiredPackage == null ||
            payload['package_name'] == requiredPackage)) {
      return current;
    }
    await Future<void>.delayed(_screenshotInterval);
  }
  final payload = last == null ? null : _payload(last);
  fail(
    '等待截图恢复超时（标记 $marker）。最后错误：'
    '${payload?['error']} ${payload?['message']}',
  );
}

Future<bool> _waitForToolError(
  PhoneAgentService service,
  String code, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final payload = _payload(
      await _callResult(service, PhoneAgentToolNames.tree, <String, dynamic>{
        'offset': 0,
      }),
    );
    if (payload['error'] == code) return true;
    await Future<void>.delayed(_pollInterval);
  }
  return false;
}

Future<void> _expectSystemNavigationDenied(
  PhoneAgentService service, {
  required String action,
  required String marker,
}) async {
  final before = await _tree(service);
  final tapNode = _nodeForText(before, _tapTarget);
  expect(tapNode, isNotNull, reason: '$action 前读树没有找到点击目标。');

  final navigation = await _input(service, <String, dynamic>{'action': action});
  final navigationPayload = _payload(navigation);
  _expectOk(navigationPayload, action);

  _hostStep(marker, '已执行 $action，等待前台离开白名单');
  final foreground = await _waitForTreeWhere(service, (tree) {
    final packageName = tree['package_name'];
    return packageName is String &&
        packageName.isNotEmpty &&
        packageName != _appPackage;
  }, timeout: const Duration(seconds: 30));
  expect(foreground, isNotNull, reason: '$action 后前台仍停留在白名单应用。');
  final packageName = foreground!['package_name'] as String?;
  expect(packageName, isNotNull, reason: '$action 后无法读取前台包名，不能把未知包名当作通过。');
  expect(packageName, isNotEmpty, reason: '$action 后前台包名为空。');

  final expectedCode = _systemPackages.contains(packageName)
      ? 'system_window_denied'
      : 'package_not_allowed';
  final denied = await _input(service, <String, dynamic>{
    'action': 'tap',
    'node_id': tapNode!['node_id'],
  });
  _expectToolError(denied, expectedCode, step: '$action 后节点输入');
  final backDenied = await _input(service, <String, dynamic>{'action': 'back'});
  _expectToolError(backDenied, expectedCode, step: '$action 后 back');
}

Future<img.Image> _readScreenshotImage(ClientToolResult result) async {
  final content = result.content;
  final imageLine = content
      .split('\n')
      .firstWhere((line) => line.startsWith('![]('));
  final rawDestination = imageLine.substring(4, imageLine.length - 1);
  final uri = decodeMarkdownImageDestination(rawDestination);
  final file = await McpImageSnapshot.localFile(uri);
  expect(file, isNotNull, reason: '截图没有落盘文件。');
  final bytes = await file!.readAsBytes();
  final decoded = img.decodePng(bytes);
  expect(decoded, isNotNull, reason: '截图不是可解码 PNG。');
  return decoded!;
}

Future<double> _screenshotAverageBrightness(ClientToolResult result) async {
  final image = await _readScreenshotImage(result);
  var total = 0;
  var sum = 0;
  for (var y = 0; y < image.height; y += 4) {
    for (var x = 0; x < image.width; x += 4) {
      final pixel = image.getPixel(x, y);
      sum += pixel.r.toInt() + pixel.g.toInt() + pixel.b.toInt();
      total++;
    }
  }
  expect(total, greaterThan(0));
  return sum / (total * 3);
}

Future<void> _expectFixturePixels(ClientToolResult result) async {
  final image = await _readScreenshotImage(result);
  var total = 0;
  var nonBlack = 0;
  var fixture = 0;
  for (var y = 0; y < image.height; y += 4) {
    for (var x = 0; x < image.width; x += 4) {
      final pixel = image.getPixel(x, y);
      final r = pixel.r.toInt();
      final g = pixel.g.toInt();
      final b = pixel.b.toInt();
      total++;
      if (r + g + b > 30) nonBlack++;
      if ((r - 0).abs() <= 16 &&
          (g - 200).abs() <= 16 &&
          (b - 255).abs() <= 16) {
        fixture++;
      }
    }
  }
  expect(total, greaterThan(0));
  expect(nonBlack / total, greaterThan(0.5), reason: '恢复截图接近全黑，不能证明真实截图恢复。');
  expect(fixture / total, greaterThan(0.05), reason: '恢复截图中没有夹具纯色区域。');
}

List<Map<String, dynamic>> _nodes(Map<String, dynamic> tree) {
  final nodes = tree['nodes'];
  if (nodes is! List) return const <Map<String, dynamic>>[];
  return <Map<String, dynamic>>[
    for (final node in nodes)
      if (node is Map) Map<String, dynamic>.from(node),
  ];
}

Map<String, dynamic>? _nodeForText(Map<String, dynamic> tree, String text) {
  for (final node in _nodes(tree)) {
    final values = <Object?>[
      node['text'],
      node['description'],
      node['hint'],
      node['state_description'],
    ];
    if (values.any((value) => value is String && value.contains(text))) {
      return node;
    }
  }
  return null;
}
