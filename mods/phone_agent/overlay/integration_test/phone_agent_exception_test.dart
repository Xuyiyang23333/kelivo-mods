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
// - Android API 30+ 设备已解锁并保持唤醒，系统无障碍设置中已启用 Kelivo Phone Agent；
// - Mods 页已为测试助手选择 Phone Agent；
// - 测试会打印 PHONE_AGENT_* 标记，宿主/CU 在标记后执行对应 adb 或系统 UI 操作；
// - 权限窗口场景要求设备唤醒：息屏时权限弹窗不会获得前台焦点；宿主必须先用
//   dumpsys 独立确认真实 GrantPermissionsActivity，再让测试断言 no_window 与
//   条件式人工提示；宿主确认是测试前提，不是产品检测能力；
// - 禁止用 settings put secure 写无障碍授权，禁止 grant/revoke/clear 权限或数据。
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

/// 读树诊断：`_tryTree` 把「被观察边界拒绝」和「调用抛异常」都折叠成 null，
/// 早期失败句因此只能打印「最后前台包名：未知」，丢掉了真实错误码。这里只记录
/// 最近一次读树的原始结果，供失败消息引用；不改变任何断言或轮询行为。
class _TreeProbe {
  int attempts = 0;
  String? packageName;
  int nodeCount = 0;
  bool fixtureText = false;
  String? error;
  String? message;
  String? exception;

  void reset() {
    attempts = 0;
    packageName = null;
    nodeCount = 0;
    fixtureText = false;
    error = null;
    message = null;
    exception = null;
  }

  void recordPayload(Map<String, dynamic> payload) {
    attempts++;
    final tree = payload['result'];
    packageName = tree is Map ? tree['package_name'] as String? : null;
    if (tree is Map) {
      final nodes = tree['nodes'];
      // 只记节点数量和测试自己定义的夹具标记，不记录界面文本内容。
      nodeCount = nodes is List ? nodes.length : 0;
      fixtureText =
          _nodeForText(Map<String, dynamic>.from(tree), _fixtureText) != null;
    }
    error = payload['error'] as String?;
    message = payload['message'] as String?;
    exception = null;
  }

  void recordException(Object error) {
    attempts++;
    packageName = null;
    nodeCount = 0;
    fixtureText = false;
    this.error = null;
    message = null;
    exception = error.toString();
  }

  /// 失败消息后缀：区分「读树被拒（带错误码）」「调用抛异常」「读树成功但包名不符」
  /// 「同包夹具 Activity 仍在栈顶」「读到了树但没有目标节点」。
  String describe() {
    final parts = <String>['读树 $attempts 次', '最后前台包名：${packageName ?? '未知'}'];
    if (exception != null) {
      parts.add('最后调用异常：$exception');
    } else if (error != null) {
      parts.add('最后错误码：$error');
    }
    if (nodeCount > 0) {
      parts.add('最后节点数：$nodeCount');
    }
    if (fixtureText) {
      parts.add('最后一棵树含同包夹具文本');
    }
    if (message != null && message!.isNotEmpty) {
      parts.add('最后消息：$message');
    }
    return parts.join('，');
  }
}

final _TreeProbe _treeProbe = _TreeProbe();

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
    // 历史 `exc5` 在此处实得 `screenshot_required` 而非 `stale_observation`。
    // 两者都表示「没有可用的截图坐标观测」，区别只在 screenshot 槽位是空
    // （`requireScreenshot` 的第一个分支）还是被窗口变化/TTL 清空。旧日志没有
    // 记录当时的截图槽位，所以这里先记录实际错误码与消息，断言保持不变。
    debugPrint(
      'PHONE_AGENT_STALE_COORDINATES: type=${_payload(staleCoordinates)['type']} '
      'error=${_payload(staleCoordinates)['error']} '
      'message=${_payload(staleCoordinates)['message']}',
    );
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

  testWidgets('叠加层不污染产品截图', (tester) async {
    await _pumpHarness(tester);
    await _ensureAppForeground(service);

    final fixtureTree = await _waitForTreeText(
      service,
      marker: 'PHONE_AGENT_OVERLAY_FIXTURE',
      instruction: 'adb shell am start -n $_fixtureActivity --ez secure false',
      text: _fixtureText,
    );
    expect(fixtureTree['package_name'], _appPackage);
    final baseline = await _screenshot(service);
    _expectScreenshotOk(baseline, '叠加层基线截图');
    expect(_payload(baseline)['package_name'], _appPackage);

    // 截图限频约 1 次/秒；等待后先触发一次坐标 tap 让叠加层出现，再立即截图。
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    _hostStep(
      'PHONE_AGENT_OVERLAY_ANIMATION',
      '坐标 tap 后约 350ms 内可用 adb exec-out screencap 观察叠加层；'
          '该截图只作宿主证据，产品截图由测试自身通过 Phone Agent 调用。',
    );
    final tap = await _input(service, <String, dynamic>{
      'action': 'tap',
      'x': 0.5,
      'y': 0.5,
    });
    _expectOk(_payload(tap), '叠加层动作');
    final during = await _screenshot(service);
    _expectScreenshotOk(during, '叠加层期间截图');
    await _expectOverlayFree(during, baseline);

    final afterTree = await _tree(service);
    expect(_nodeForText(afterTree, _fixtureText), isNotNull);
  });

  testWidgets('叠加层可见时真实触摸不被拦截', (tester) async {
    await _pumpHarness(tester);
    await _ensureAppForeground(service);

    // 宿主用 adb 注入独立真实触摸（不是 phone_agent_input）。观察边界（M28）之后
    // 通知栏（com.android.systemui，TYPE_SYSTEM）不再可观察，因此前台由宿主
    // dumpsys 确认；测试改用产品错误码作为“前台已切到通知栏”的证据。
    _expectScreenshotOk(await _screenshot(service), '宿主触摸前截图');
    _hostStep(
      'PHONE_AGENT_OVERLAY_HOST_TOUCH',
      '在接下来约 12 秒内，宿主必须用 adb 注入真实触摸（不是 phone_agent_input）：'
          'adb shell input swipe 540 5 540 1200 300；可重复多次。'
          '触摸后执行 adb shell dumpsys window | grep -E "mCurrentFocus|mFocusedApp" '
          '确认前台是 com.android.systemui（通知栏已打开）。'
          '测试会在每次读树时显示约 700ms 的观察叠加层。',
    );
    Map<String, dynamic>? shadeDenied;
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline) && shadeDenied == null) {
      // 读树会显示观察脉冲，宿主的真实触摸应落在叠加层可见期间。
      // 通知栏打开后这里必须被观察层拒绝。注意标识：com.android.systemui
      // 本身是硬基线成员，而硬基线判定排在窗口类型之前，所以来源标识是
      // hard_baseline 而不是 window_type_system；只接受这两个之一。
      final payload = await _tryTreePayload(service);
      final message = payload?['message'] as String? ?? '';
      if (payload?['error'] == 'system_window_denied' &&
          (message.contains('hard_baseline') ||
              message.contains('window_type_system'))) {
        shadeDenied = payload;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    expect(
      shadeDenied,
      isNotNull,
      reason:
          '宿主 adb 真实触摸没有打开通知栏（读树 20 秒内没有返回 '
          'system_window_denied + hard_baseline/window_type_system），'
          '不能证明叠加层不拦截宿主触摸。',
    );
    debugPrint(
      'PHONE_AGENT_OVERLAY_HOST_TOUCH_RESULT: '
      'package=com.android.systemui error=${shadeDenied!['error']} '
      'message=${shadeDenied['message']}',
    );

    _hostStep(
      'PHONE_AGENT_OVERLAY_HOST_TOUCH_RECOVER',
      'adb shell input keyevent 4 关闭通知栏，然后执行 '
          'adb shell am start -n $_appPackage/com.psyche.kelivo.MainActivity',
    );
    await _waitForTreeText(
      service,
      marker: 'PHONE_AGENT_OVERLAY_HOST_TOUCH_RETURN',
      instruction:
          'adb shell am start -n $_appPackage/com.psyche.kelivo.MainActivity',
      text: _tapTarget,
    );
  });

  testWidgets('旋转后旧句柄与旧截图失效', (tester) async {
    addTearDown(
      () => SystemChrome.setPreferredOrientations(DeviceOrientation.values),
    );
    await _pumpHarness(tester);
    // M30：该用例此前没传 repump（锁屏用例传了）。上一用例把前台交给夹具/
    // 通知栏后，单纯 pump 一次的语义树可能还没刷新，`_ensureAppForeground`
    // 只能看到「包名对但没有目标节点」。补上与锁屏用例相同的重 pump 兜底，
    // 不新增等待语义、不改任何断言。
    await _ensureAppForeground(service, repump: () => _pumpHarness(tester));

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

    // 宿主确认是本场景的测试前提：测试自身无法读取 dumpsys，也不能把任意
    // no_window 当作真实权限弹窗。宿主必须先确认真实 GrantPermissionsActivity，
    // 再让测试断言拒绝结果。
    _hostStep(
      'PHONE_AGENT_PERMISSION_WINDOW',
      '确保设备已唤醒并解锁，执行：'
          'adb shell am start -n $_fixtureActivity --ez requestPermission true；'
          '然后用 adb shell dumpsys window 确认 mCurrentFocus 为 '
          'com.google.android.permissioncontroller/...GrantPermissionsActivity。'
          '只有确认真实弹窗后才继续；权限必须保持未授予。',
    );
    var permissionState = await _waitForNoWindowState(
      service,
      timeout: const Duration(seconds: 45),
    );
    if (permissionState == null) {
      // API35 实测：设备息屏时 am start 不会让权限弹窗获得前台焦点
      // （mCurrentFocus=null），唤醒后弹窗立即出现。这里给宿主一次唤醒重试；
      // 仍然没有进入无窗口状态就失败，不因 root=null 跳过。
      _hostStep(
        'PHONE_AGENT_PERMISSION_WINDOW_RETRY',
        'adb shell input keyevent KEYCODE_WAKEUP && '
            'adb shell wm dismiss-keyguard && '
            'adb shell am start -n $_fixtureActivity --ez requestPermission true',
      );
      permissionState = await _waitForNoWindowState(
        service,
        timeout: const Duration(seconds: 60),
      );
    }
    expect(
      permissionState,
      isNotNull,
      reason:
          '未观察到权限弹窗期间的无窗口状态。宿主需先用 dumpsys 确认真实 '
          'GrantPermissionsActivity，并确认 POST_NOTIFICATIONS 未授予；'
          '不能把任意 no_window 当作本场景通过，也不因 root=null 跳过。',
    );
    debugPrint(
      'PHONE_AGENT_PERMISSION_TREE: package=${permissionState?['package_name']} '
      'type=${permissionState?['type']} error=${permissionState?['error']}',
    );
    _expectManualPermissionHint(permissionState!, step: '权限窗口读树');

    final denied = await _input(service, <String, dynamic>{
      'action': 'tap',
      'node_id': tapNode!['node_id'],
    });
    _expectToolError(
      denied,
      'no_window',
      messageContains: 'system permission dialog',
      step: '权限窗口节点输入',
    );
    _expectManualPermissionHint(_payload(denied), step: '权限窗口节点输入');

    final deniedScreenshot = await _screenshot(service);
    _expectToolError(
      deniedScreenshot,
      'no_window',
      messageContains: 'system permission dialog',
      step: '权限窗口截图',
    );
    _expectManualPermissionHint(_payload(deniedScreenshot), step: '权限窗口截图');

    final backDenied = await _input(service, <String, dynamic>{
      'action': 'back',
    });
    _expectToolError(
      backDenied,
      'no_window',
      messageContains: 'system permission dialog',
      step: '权限窗口 back',
    );
    _expectManualPermissionHint(_payload(backDenied), step: '权限窗口 back');

    // back 若被系统执行会关闭弹窗并让窗口重新可访问；这里再读一次树，
    // 仍为 no_window 才说明系统导航没有执行。
    final afterBack = await _tryTreePayload(service);
    expect(
      afterBack?['error'],
      'no_window',
      reason: 'back 后窗口重新可访问，说明系统导航被执行；权限窗口场景失败。',
    );
    _expectManualPermissionHint(afterBack!, step: '权限窗口 back 后读树');

    _hostStep(
      'PHONE_AGENT_DISMISS_PERMISSION',
      'adb shell input keyevent 4；随后执行 '
          'adb shell dumpsys package $_appPackage 并确认 POST_NOTIFICATIONS '
          '仍为 granted=false（不得 grant/revoke/clear）。',
    );
    await _returnToApp(service);
    final restored = await _tree(service);
    expect(restored['package_name'], _appPackage);
    expect(_nodeForText(restored, _tapTarget), isNotNull);
  });

  testWidgets('锁屏 device_locked 与解锁恢复', (tester) async {
    await _pumpHarness(tester);
    await _ensureAppForeground(service, repump: () => _pumpHarness(tester));
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

    // 观察边界（M28）之后测试不再读 settings 树：settings 属于硬基线包，
    // 读树会返回 system_window_denied。前台由宿主用 dumpsys 独立确认，
    // 测试只用“测试应用中建立的观测”与产品错误码作为时序信号。
    _hostStep(
      'PHONE_AGENT_PREPARE_SERVICE_DISABLE',
      '打开 Kelivo Phone Agent 无障碍详情页并停留到能看到开关，不要关闭服务；'
          '用 adb shell dumpsys window | grep -E "mCurrentFocus|mFocusedApp" '
          '确认前台是 com.android.settings',
    );
    final settingsDenied = await _waitForObservationDenied(
      service,
      timeout: const Duration(seconds: 60),
      messageContains: 'hard_baseline',
    );
    expect(settingsDenied, isNotNull, reason: '宿主没有进入设置页：读树在 60 秒内没有返回硬基线拒绝。');
    debugPrint(
      'PHONE_AGENT_SETTINGS_OBSERVATION_DENIED: '
      'error=${settingsDenied?['error']}',
    );

    _hostStep(
      'PHONE_AGENT_OPEN_DISABLE_DIALOG',
      '点击 Kelivo Phone Agent 开关打开关闭确认窗口；用 '
          'adb shell dumpsys window | grep -E "mCurrentFocus|mFocusedApp" '
          '确认确认弹窗在前台，然后停留在确认按钮前',
    );
    // 宿主确认弹窗存在后，测试给出一次有界等待，让宿主走到确认按钮前。
    await Future<void>.delayed(const Duration(seconds: 8));

    // 观测已在测试应用前台建立（第 527 行的 _tree），分页请求复用该观测。
    // 观察边界（M28）之后不能再用“在 settings 前台建立观测”：settings 是硬基线包，
    // offset 0 会被拒绝。这里改为在宿主关闭服务的期间持续发起分页请求，
    // 直到服务状态变为禁用；禁用瞬间仍在队列中的请求才会以
    // interrupted/service_unavailable 完成。这样断言不再依赖“1000 个请求恰好
    // 在宿主点击前后排空”的时序运气。
    const chunkSize = 200;
    final codes = <String>[];
    final startedAt = DateTime.now();
    _hostStep(
      'PHONE_AGENT_DISABLE_DURING_PENDING',
      '现在在已打开的无障碍详情页关闭 Kelivo Phone Agent（确认弹窗已打开就直接确认）',
    );
    var disabled = false;
    while (!disabled &&
        DateTime.now().difference(startedAt) < const Duration(seconds: 35)) {
      final chunk = await Future.wait(<Future<String>>[
        for (var i = 0; i < chunkSize; i++) _readTreeCode(service, offset: 1),
      ]);
      codes.addAll(chunk);
      disabled = !(await service.status()).enabled;
    }

    final elapsed = DateTime.now().difference(startedAt);
    final observed = codes.toSet().toList()..sort();
    debugPrint(
      'PHONE_AGENT_SERVICE_PENDING_BATCH: size=${codes.length} '
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

    // M30 实测（run10）：宿主确认关闭后，第一块 pending 请求立刻以
    // `service_unavailable` 完成（`size=200 elapsed=1979ms`），但紧接着读到的
    // `status().enabled` 仍为 true——无障碍开关的系统状态在确认弹窗关闭后还会
    // 短暂抖动。这里是**只读状态查询**的有界等待，不重发输入、不重试动作，
    // 断言仍是 `enabled isFalse` / `ready isFalse`。
    var disabledStatus = await service.status();
    final settleDeadline = DateTime.now().add(const Duration(seconds: 20));
    while (disabledStatus.enabled && DateTime.now().isBefore(settleDeadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      disabledStatus = await service.status();
    }
    debugPrint(
      'PHONE_AGENT_SERVICE_DISABLED_STATUS: enabled=${disabledStatus.enabled} '
      'connected=${disabledStatus.connected} ready=${disabledStatus.ready}',
    );
    expect(disabledStatus.enabled, isFalse);
    expect(disabledStatus.ready, isFalse);

    _hostStep(
      'PHONE_AGENT_ENABLE_SERVICE_NOW',
      '在系统无障碍设置中重新启用 Kelivo Phone Agent',
    );
    // 只触发一次启用：`_hostStep` 已打印 `PHONE_AGENT_ENABLE_SERVICE_NOW`，
    // 宿主据此完成启用并等待绑定；这里改为等待状态就绪，不再调用会重复打印
    // `PHONE_AGENT_WAITING_FOR_SERVICE` 的 [_waitForService]（后者只用于
    // setUpAll 的首次授权，两处同时触发会让宿主并发执行启用动作）。
    await _waitForReady(service);
    await _waitForAppScreenshot(service);

    // 旧句柄必须在服务重启后失效。产品 `input()` 先取 `currentWindow()`
    // （`PhoneAgentService.kt:464`），`rootInActiveWindow` 为 null 时返回
    // `no_window`，这**先于**句柄校验，是文档化优先级；因此不能把
    // `no_window` 当成 `stale_handle`。这里只做有界前置等待，判定信号用
    // **截图**（截图只写 screenshot 观测，不触碰树观测，不会重置 registry），
    // 不重读树、也不循环重试输入。等待超时与最终错误码各自有明确断言。
    final rootReady = await _waitForStableWindow(service);
    expect(
      rootReady,
      isTrue,
      reason:
          '服务重启后有界等待内无法取得可稳定截图的前台窗口；'
          '逐次错误见 PHONE_AGENT_RESTART_WAIT_STOPPED/TIMEOUT '
          '（实测出现过 no_window、hard_baseline、stale_observation），'
          '旧句柄失效在该前提下无法验证。',
    );

    final staleHandle = await _input(service, <String, dynamic>{
      'action': 'tap',
      'node_id': tapNode!['node_id'],
    });
    debugPrint(
      'PHONE_AGENT_RESTART_STALE_HANDLE: type=${_payload(staleHandle)['type']} '
      'error=${_payload(staleHandle)['error']} '
      'message=${_payload(staleHandle)['message']}',
    );
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
  // 安装测试包会撤销无障碍授权。先给宿主留出通过系统界面重新启用的时间，
  // 避免在服务未启用时立即轮询状态（慢速模拟器上可能拖住主线程）。
  debugPrint('PHONE_AGENT_WAITING_FOR_SERVICE');
  await Future<void>.delayed(const Duration(seconds: 20));
  var status = await service.status();
  if (!status.ready) {
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

/// 等待服务就绪，**不打印任何宿主标记**。
///
/// 用于「宿主已被告知重新启用」之后的等待：`_hostStep` 已经发出唯一一次启用
/// 请求，这里若再打印 `PHONE_AGENT_WAITING_FOR_SERVICE`，宿主会并发执行第二
/// 条启用动作（M31 与 P2-4 都点到过这一点）。
Future<void> _waitForReady(
  PhoneAgentService service, {
  Duration timeout = const Duration(seconds: 120),
}) async {
  final deadline = DateTime.now().add(timeout);
  var status = await service.status();
  while (!status.ready && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    status = await service.status();
  }
  expect(
    status.ready,
    isTrue,
    reason:
        'Phone Agent 服务未就绪（supported=${status.supported}, '
        'enabled=${status.enabled}, connected=${status.connected}, '
        'sdk=${status.androidSdkInt}）。宿主需在系统无障碍设置中重新启用服务。',
  );
}

void _hostStep(String marker, String instruction) {
  debugPrint('$marker: $instruction');
}

Future<void> _ensureAppForeground(
  PhoneAgentService service, {
  Future<void> Function()? repump,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  var repumped = false;
  while (DateTime.now().isBefore(deadline)) {
    final tree = await _tryTree(service);
    if (tree != null &&
        tree['package_name'] == _appPackage &&
        _nodeForText(tree, _tapTarget) != null) {
      return;
    }
    // 应用已在前台但语义树没有点击目标时，重新 pump 一次测试 harness，
    // 覆盖后台恢复后 Flutter 语义树未刷新的宿主时序；不改变任何断言。
    if (!repumped &&
        repump != null &&
        tree != null &&
        tree['package_name'] == _appPackage) {
      repumped = true;
      await repump();
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
    _treeProbe.recordPayload(payload);
    if (payload['ok'] != true) return null;
    final tree = payload['result'];
    if (tree is! Map) return null;
    return Map<String, dynamic>.from(tree);
  } catch (error) {
    _treeProbe.recordException(error);
    return null;
  }
}

Future<Map<String, dynamic>?> _tryTreePayload(PhoneAgentService service) async {
  try {
    final result = await _callResult(
      service,
      PhoneAgentToolNames.tree,
      <String, dynamic>{'offset': 0},
    );
    final payload = _payload(result);
    _treeProbe.recordPayload(payload);
    return payload;
  } catch (error) {
    _treeProbe.recordException(error);
    return null;
  }
}

Future<ClientToolResult> _screenshot(PhoneAgentService service) async {
  var result = await _callResult(
    service,
    PhoneAgentToolNames.screenshot,
    const <String, dynamic>{},
  );
  var error = _payload(result)['error'];
  var attempts = 0;
  // 截图限频约一次/秒；慢速模拟器在旋转/窗口过渡后也可能超过产品 10 秒 timeout。
  // 这是宿主稳定性重试，不改变产品超时语义，最终仍要求成功截图。
  while ((error == 'rate_limited' || error == 'timeout') && attempts < 2) {
    attempts++;
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    result = await _callResult(
      service,
      PhoneAgentToolNames.screenshot,
      const <String, dynamic>{},
    );
    error = _payload(result)['error'];
  }
  return result;
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

/// 断言无可访问窗口时的条件式人工提示：只建议检查/处理权限弹窗，
/// 不声称识别具体权限弹窗。
void _expectManualPermissionHint(
  Map<String, dynamic> payload, {
  required String step,
}) {
  final message = (payload['message'] as String? ?? '').toLowerCase();
  expect(
    message,
    contains('system permission dialog'),
    reason: '$step 提示缺少条件式权限弹窗说明。',
  );
  expect(message, contains('handle or cancel'), reason: '$step 提示缺少人工处理/取消指引。');
  expect(
    message,
    contains('return to the test app'),
    reason: '$step 提示缺少返回测试应用指引。',
  );
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
  _treeProbe.reset();
  Map<String, dynamic>? last;
  while (DateTime.now().isBefore(deadline)) {
    last = await _tryTree(service);
    if (last != null && _nodeForText(last, text) != null) return last;
    // 只打印轮询诊断，不含节点文本；用于区分「被拒」「抛异常」「包名不符」。
    debugPrint('PHONE_AGENT_TREE_PROBE: ${_treeProbe.describe()}');
    await Future<void>.delayed(_pollInterval);
  }
  fail('等待 $text 超时（标记 $marker）。${_treeProbe.describe()}');
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

/// 轮询读树直到返回 no_window（权限弹窗期间没有可访问 root），超时返回 null。
/// 调用方必须由宿主独立确认弹窗真实存在，不能把任意 no_window 当作通过。
Future<Map<String, dynamic>?> _waitForNoWindowState(
  PhoneAgentService service, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final payload = await _tryTreePayload(service);
    if (payload?['error'] == 'no_window') return payload;
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

/// 服务重启后的有界前置等待：用**截图**（只写 screenshot 观测，不触碰树观测）
/// 确认前台窗口可取得，避免把 `no_window` 的瞬时状态误判成句柄缺陷。
/// 不重读树（会重置 registry 里的旧句柄），不重试输入。
Future<bool> _waitForStableWindow(
  PhoneAgentService service, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  String? lastError;
  while (DateTime.now().isBefore(deadline)) {
    final payload = _payload(await _screenshot(service));
    if (payload['ok'] == true && payload['package_name'] == _appPackage) {
      return true;
    }
    lastError = payload['error'] as String?;
    final lastMessage = payload['message'] as String? ?? '';
    // 值得继续等的都是「前台窗口暂时不可用/未就绪/正在变化」这一类：
    // - `no_window`：还没拿到 root；
    // - `rate_limited`：截图限频；
    // - `stale_observation`：**窗口已经取得**，只是截图期间发生了切换
    //   （服务重启会让窗口重建、叠加层收起、输入法起落），属瞬态；
    // - 宿主还在设置页时的观察边界拒绝，且仅限「前台没回到应用」这个子集：
    //   `hard_baseline` 与 `window_type_system`/`overlay`/`split_divider`
    //   （见 `_isRetryableObservationDenial`）。**不含 `window_type_unknown`**：
    //   那是窗口列表尚未稳定、类型解析失败，当作「稍后会好」会让真实时序缺陷
    //   静默通过。
    // 这里只是把同一有界预算用在等待上，不放宽任何断言——超时仍失败，
    // 旧句柄的 `stale_handle` 断言也保持不变。
    final windowNotReady =
        lastError == 'no_window' ||
        lastError == 'rate_limited' ||
        lastError == 'stale_observation' ||
        // 批准门控（M33）：前台若不是本应用且未获批准（例如重启后宿主把
        // launcher 留在前台），观察返回 `permission_required`。这与「前台还没
        // 回到应用」是同一个状态，仍属可重试的窗口未就绪；成功条件
        // （`package_name == _appPackage`）不变，超时仍失败。
        lastError == 'permission_required' ||
        (lastError == 'system_window_denied' &&
            _isRetryableObservationDenial(lastMessage));
    if (!windowNotReady) {
      debugPrint(
        'PHONE_AGENT_RESTART_WAIT_STOPPED: error=$lastError message=$lastMessage',
      );
      return false;
    }
    await Future<void>.delayed(_screenshotInterval);
  }
  debugPrint('PHONE_AGENT_RESTART_WAIT_TIMEOUT: error=$lastError');
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

  // 观察边界（M28）之后前台不一定是不可观察的：`home` 与 `recents` 实测落在
  // launcher（`com.google.android.apps.nexuslauncher`，TYPE_APPLICATION），读树
  // 仍然成功。因此不能用“读树被拒”作为前台已离开的证据，也不能等一个可能
  // 永远不会出现的拒绝（会白等 30 秒）。这里只要求前台已经不是本应用：
  // 读树成功则包名必须不同，读树被拒则必须是观察边界的精确标识。
  _hostStep(
    marker,
    '已执行 $action。可用 adb shell dumpsys window | grep -E '
    '"mCurrentFocus|mFocusedApp" 独立确认前台已离开 $_appPackage',
  );
  final foreground = await _waitForForegroundLeftApp(
    service,
    timeout: const Duration(seconds: 30),
  );
  expect(
    foreground,
    isNotNull,
    reason:
        '$action 后前台仍停留在 $_appPackage（读树成功且包名未变），'
        '无法证明导航已离开白名单应用。',
  );
  debugPrint(
    'PHONE_AGENT_SYSTEM_NAVIGATION_FOREGROUND: action=$action '
    'package=${foreground!.packageName} error=${foreground.error} '
    'message=${foreground.message}',
  );

  // 输入错误码按门控层区分：硬基线包（systemui 等）→ system_window_denied；
  // 构建期 deny 成员 → package_not_allowed；其余第三方未批准应用（实测 launcher）
  // → permission_required（M33：批准 = 读＋操作一体）。三者都只接受精确码，
  // 不接受“任意错误”；并要求两次判定一致，否则说明前台在两次调用之间变了。
  const acceptedCodes = <String>[
    'system_window_denied',
    'package_not_allowed',
    'permission_required',
  ];
  final nodeDenied = await _input(service, <String, dynamic>{
    'action': 'tap',
    'node_id': tapNode!['node_id'],
  });
  final nodeCode = _payload(nodeDenied)['error'] as String?;
  expect(
    nodeCode,
    isIn(acceptedCodes),
    reason: '$action 后节点输入返回了预期之外的错误码：$nodeCode。',
  );
  final backDenied = await _input(service, <String, dynamic>{'action': 'back'});
  final backCode = _payload(backDenied)['error'] as String?;
  expect(
    backCode,
    isIn(acceptedCodes),
    reason: '$action 后 back 返回了预期之外的错误码：$backCode。',
  );
  final expectedCodes = <String>{nodeCode!, backCode!};
  expect(
    expectedCodes.length,
    1,
    reason:
        '$action 后节点输入与 back 的错误码不一致（$expectedCodes），'
        '说明两次判定之间前台发生了变化。',
  );
}

/// 发起一次分页读树并归类结果，用于服务禁用用例的“排队中断”断言。
Future<String> _readTreeCode(
  PhoneAgentService service, {
  required int offset,
}) async {
  try {
    await service.readTree(offset: offset, maxNodes: 120);
    return 'ok';
  } on PhoneAgentToolFailure catch (failure) {
    return failure.code;
  } catch (_) {
    return 'error';
  }
}

/// 一次前台观测的结果：读树成功给出包名，读树被拒给出错误码与消息。
typedef _ForegroundProbe = ({
  String? packageName,
  String? error,
  String message,
});

/// 轮询读树，直到前台不再是测试应用本身。超时返回 null。
///
/// 不能只等“读树被拒”：观察边界（M28）后 `home`/`recents` 实测落在 launcher
/// （`TYPE_APPLICATION`），而批准门控（M33）让未批准的 launcher 读树返回
/// `permission_required` 且只回身份。因此这里接受三类结果：
///
/// 1. 读树**成功**且 `package_name` 不是测试应用（测试包是构建配置预批准条目）；
/// 2. `no_window`；
/// 3. `system_window_denied` 且带真实观察边界标识；
/// 4. `permission_required` 且消息能确认前台已不是测试应用（未批准应用的唯一
///    可见信息就是身份，因此以“消息含包名且不是测试应用”为准）。
///
/// **刻意排除 `window_type_unknown`**，也**不接受**不带身份的 `permission_required`
/// ——没有身份就无法证明前台已离开本应用，退化成“任意错误即通过”。
Future<_ForegroundProbe?> _waitForForegroundLeftApp(
  PhoneAgentService service, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final payload = await _tryTreePayload(service);
    if (payload != null) {
      final error = payload['error'] as String?;
      final message = payload['message'] as String? ?? '';
      if (error == null) {
        final tree = payload['result'];
        final packageName = tree is Map
            ? tree['package_name'] as String?
            : null;
        if (packageName != null &&
            packageName.isNotEmpty &&
            packageName != _appPackage) {
          return (packageName: packageName, error: null, message: '');
        }
      } else if (error == 'no_window') {
        return (packageName: null, error: error, message: message);
      } else if (error == 'permission_required' &&
          _permissionRequiredIdentity(message) != null) {
        return (
          packageName: _permissionRequiredIdentity(message),
          error: error,
          message: message,
        );
      } else if (error == 'system_window_denied' &&
          _isObservationBoundaryMessage(message)) {
        // 硬基线先于窗口类型判定，所以通知栏/systemui 的来源标识是
        // hard_baseline 而不是 window_type_system；两者都算观察边界。
        return (packageName: null, error: error, message: message);
      }
    }
    await Future<void>.delayed(_pollInterval);
  }
  return null;
}

/// 从 `permission_required` 消息里取出前台包名（未批准应用唯一可见的信息）。
/// 只认“`Reading <package> (signing cert …)` / `signing_unavailable`”这种身份句式，
/// 且包名必须不是测试应用本身；其他形态一律返回 null，不做模糊匹配。
String? _permissionRequiredIdentity(String message) {
  final match = RegExp(
    r'^Reading ([A-Za-z0-9_.]+) \(signing cert [0-9a-f]{8}\)',
  ).firstMatch(message);
  final unavailable = RegExp(
    r'^Reading ([A-Za-z0-9_.]+), signing_unavailable',
  ).firstMatch(message);
  final packageName = match?.group(1) ?? unavailable?.group(1);
  if (packageName == null || packageName.isEmpty) return null;
  if (packageName == _appPackage) return null;
  return packageName;
}

/// 观察边界拒绝中「前台还没回到应用」这一可重试子集。
///
/// **刻意排除 `window_type_unknown`**：它表示窗口列表还没稳定、类型解析失败，
/// 把它当作「稍后会好」的等待理由会让真实的时序缺陷静默通过——这与
/// [_isObservationBoundaryMessage] 的取值规则必须一致。
bool _isRetryableObservationDenial(String message) =>
    message.contains('hard_baseline') ||
    message.contains('window_type_system') ||
    message.contains('window_type_overlay') ||
    message.contains('window_type_split_divider');

/// 只接受观察边界实际会产生的固定标识，不接受任意 system_window_denied。
/// 特别地，`window_type_unknown` 不在此列：它表示窗口列表还没稳定，
/// 列入可接受会让时序缺陷静默通过。
bool _isObservationBoundaryMessage(String message) =>
    message.contains('hard_baseline') ||
    message.contains('window_type_system') ||
    message.contains('window_type_overlay') ||
    message.contains('window_type_split_divider');

/// 轮询读树，直到观察层以指定来源标识拒绝（例如宿主进入设置页后要求
/// `hard_baseline`）。超时返回 null；不接受标识不符的拒绝。
Future<Map<String, dynamic>?> _waitForObservationDenied(
  PhoneAgentService service, {
  required Duration timeout,
  required String messageContains,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final payload = await _tryTreePayload(service);
    if (payload != null &&
        payload['error'] == 'system_window_denied' &&
        (payload['message'] as String? ?? '').contains(messageContains)) {
      return payload;
    }
    await Future<void>.delayed(_pollInterval);
  }
  return null;
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

/// 叠加层隐藏后截图必须与基线一致：中心 60% 逐像素相同，且整图不含强调色。
Future<void> _expectOverlayFree(
  ClientToolResult during,
  ClientToolResult baseline,
) async {
  final after = await _readScreenshotImage(during);
  final before = await _readScreenshotImage(baseline);
  expect(after.width, before.width, reason: '叠加层截图宽度与基线不一致。');
  expect(after.height, before.height, reason: '叠加层截图高度与基线不一致。');

  final left = (before.width * 0.2).round();
  final right = (before.width * 0.8).round();
  final top = (before.height * 0.2).round();
  final bottom = (before.height * 0.8).round();
  var compared = 0;
  var mismatches = 0;
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      final a = before.getPixel(x, y);
      final b = after.getPixel(x, y);
      compared++;
      if (a.r != b.r || a.g != b.g || a.b != b.b) mismatches++;
    }
  }
  expect(compared, greaterThan(0));
  expect(
    mismatches,
    0,
    reason: '叠加层可见期间截图中心 60% 与基线不一致（$mismatches/$compared）。',
  );

  var accent = 0;
  for (var y = 0; y < after.height; y += 2) {
    for (var x = 0; x < after.width; x += 2) {
      final pixel = after.getPixel(x, y);
      if ((pixel.r.toInt() - 0).abs() <= 12 &&
          (pixel.g.toInt() - 137).abs() <= 12 &&
          (pixel.b.toInt() - 153).abs() <= 12) {
        accent++;
      }
    }
  }
  var baselineAccent = 0;
  for (var y = 0; y < before.height; y += 2) {
    for (var x = 0; x < before.width; x += 2) {
      final pixel = before.getPixel(x, y);
      if ((pixel.r.toInt() - 0).abs() <= 12 &&
          (pixel.g.toInt() - 137).abs() <= 12 &&
          (pixel.b.toInt() - 153).abs() <= 12) {
        baselineAccent++;
      }
    }
  }
  // 状态栏的隐私/无障碍指示图标本身带强调色，因此与基线比较新增像素，
  // 而不是要求整图零强调色。
  expect(
    accent - baselineAccent,
    lessThan(50),
    reason: '截图新增了叠加层强调色像素（during=$accent baseline=$baselineAccent），说明隐藏失败。',
  );
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
