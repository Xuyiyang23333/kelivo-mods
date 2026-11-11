# kelivo_phone_agent 插件

独立 Android Flutter 插件，为 `phone_agent` Mod 提供截图、无障碍节点树和基础输入。插件不 import `package:Kelivo/...`，不修改上游 `PhoneControlService`，使用独立通道、Manifest、服务 XML 和资源名。

## 范围

首版只做三件事：

- `phone_agent_screenshot`：API 30+ 截图，长边缩放到不超过 1600，按密码节点 bounds 涂黑。
- `phone_agent_tree`：有界 DFS、分页、`interactive_only`、密码子树隐藏。
- `phone_agent_input`：节点 `tap` / `long_press` / `set_text` / `scroll`，坐标 `tap` / `long_press` / `swipe`，系统 `back` / `home` / `recents`。

不做设置页、`open_app`、`list_apps`、通知栏、快捷设置、危险语义识别或业务确认流程。

## Dart API

```dart
import 'package:kelivo_phone_agent/kelivo_phone_agent.dart';

final agent = KelivoPhoneAgent.instance;

final PhoneAgentStatus status = await agent.status();
await agent.openAccessibilitySettings();
final PhoneAgentScreenshot shot = await agent.screenshot();
await agent.clearScreenshot();
final Map<String, dynamic> tree = await agent.readTree(
  offset: 0,
  maxNodes: 120,
  interactiveOnly: false,
);
final Map<String, dynamic> result = await agent.input({
  'action': 'tap',
  'node_id': 'n3',
});
```

`PhoneAgentScreenshot` 字段：`bytes`、`imageWidth`、`imageHeight`、`screenWidth`、`screenHeight`、`packageName`。

`PhoneAgentException(code, message)` 映射原生结构化错误。`PhoneAgentClient` 不对外导出，Kelivo 适配层只依赖 `KelivoPhoneAgent`。

## MethodChannel 协议

通道名：`kelivo/phone_agent`。

| 方法 | 参数 | 结果 |
|---|---|---|
| `status` | 无 | `{supported, enabled, connected, androidSdkInt}` |
| `openAccessibilitySettings` | 无 | `null` |
| `screenshot` | 无 | `{bytes: ByteArray, imageWidth, imageHeight, screenWidth, screenHeight, packageName}` |
| `clearScreenshot` | 无 | `{cleared: true}` |
| `readTree` | `{offset, max_nodes, interactive_only}` | `{offset, next_offset, total, truncated, text_truncated, package_name, width, height, nodes}` |
| `input` | `{action, node_id?, text?, x?, y?, end_x?, end_y?, duration_ms?, direction?}` | `{success, action, message}` |

节点字段：`node_id`、`bounds`、`class`、`parent_id?`、`text?`、`description?`、`hint?`、`state_description?`、`resource_id?`、`enabled`、`clickable?`、`long_clickable?`、`editable?`、`supports_set_text?`、`scrollable?`、`checkable?`、`checked?`、`focused?`、`selected?`、`password?`。密码节点不输出文本、描述、提示和状态描述，也不遍历子树。

所有坐标都是 `[0, 1]` 归一化值，原点为截图左上角。协议和结果中不出现 `snapshot_id`；Dart 客户端会拒绝包含该键的输入参数。

### 错误码

`service_unavailable`、`unsupported_platform`、`unsupported_os`、`device_locked`、`no_window`、`invalid_argument`、`stale_observation`、`stale_handle`、`screenshot_required`、`screenshot_blocked`、`screenshot_failed`、`rate_limited`、`busy`、`interrupted`、`gesture_failed`、`gesture_timeout`、`gesture_cancelled`、`gesture_rejected`、`action_unavailable`、`action_failed`、`password_node_denied`、`package_not_allowed`、`system_window_denied`、`budget_exceeded`、`timeout`、`internal_error`。

错误消息包含下一步建议，例如重新读树、重新截图、解锁手机或启用服务。

## 原生行为

- 单 worker 串行执行；手势和截图完成前，后续请求返回 `busy`。
- 每次调用和实际执行前检查锁屏、息屏和服务代次。
- 服务断开、`onInterrupt`、`onUnbind` 和 `onDestroy` 会完成所有 pending 请求并清空观测。
- 树观测 TTL 120 秒。`offset == 0` 创建新观测并重新编号；`offset > 0` 只切片当前观测，不重新遍历。
- 句柄只在当前观测内有效。动作后保留树句柄；每次使用前执行 `refresh()`、可见性、可用性和指纹校验。指纹不包含 `isFocused` 和动作集合 `actions`，因此点击或聚焦后同一已刷新节点仍可继续输入，动作可用性由执行层按当前节点校验；`isSelected`、内容、稳定能力字段、窗口、包名、尺寸、旋转和 TTL 变化仍失效。目标失效返回 `stale_handle`（附带变化字段名，不含内容），不会按文本或 bounds 重新解析到另一个节点。前置重验失败按 `refresh()` → 可见性 → 可用性短路，消息只追加固定诊断标识 `refresh_failed`、`not_visible`、`not_enabled`，不含节点文本、类名或 viewId；诊断不改变通过条件。
- 截图使用独立观测。动作后清空截图观测，坐标输入必须重新截图；窗口、包名、尺寸或旋转变化返回 `stale_observation`。截图位图与捕获前屏幕宽高比不一致时同样返回 `stale_observation`，不发出错位遮挡的图片。
- 截图前遍历 `service.windows` 中所有可访问窗口的 root 收集密码 bounds；任一窗口 root 无法读取时截图失败，不在漏遮挡的情况下发出图片。
- 输入白名单初期只有 `com.psyche.kelivo.phoneagent`。系统窗口（`com.android.systemui`、权限控制器、安装器等）一律拒绝。系统导航动作与节点、坐标动作使用同一白名单。
- 动作预算：输入 120 次/分钟，读树 60 次/分钟，截图约 1 次/秒且最多 30 次/分钟。
- 截图失败映射：系统限频为 `rate_limited`；平台明确返回的无效窗口/截图错误为 `screenshot_blocked`；窗口读取、位图处理或遮挡准备失败为 `screenshot_failed`。整屏 `takeScreenshot` 不保证对 `FLAG_SECURE` 报错，secure 内容可能以黑色区域出现在成功截图中；不根据像素猜 secure，不承诺不发送黑图，正常黑色页面保留。
- `clearScreenshot` 只清空原生截图坐标观测，供适配层在图片落盘或尺寸校验失败时调用。

## 集成

在合成树的 `pubspec.yaml` 中通过 path 依赖引入：

```yaml
dependencies:
  kelivo_phone_agent:
    path: ./dependencies/kelivo_phone_agent
```

Manifest Merger 会合并独立服务：

```xml
<service
    android:name="com.kelivo.phoneagent.PhoneAgentService"
    android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE"
    android:exported="true">
    <intent-filter>
        <action android:name="android.accessibilityservice.AccessibilityService" />
    </intent-filter>
    <meta-data
        android:name="android.accessibilityservice"
        android:resource="@xml/kelivo_phone_agent_service" />
</service>
```

用户需要在系统无障碍设置中单独启用 “Kelivo Phone Agent”。该服务与上游 “Kelivo phone control” 相互独立，现有设置页不显示本服务状态。

## 测试

```bash
# Dart
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test

# Kotlin（模块名以实际合成树 ./gradlew projects 为准）
./gradlew :kelivo_phone_agent:testDebugUnitTest
```

Dart 测试覆盖通道参数、默认值、错误映射、超时、`clearScreenshot` 和 `snapshot_id` 拒绝。Kotlin 测试覆盖有界 DFS、密码子树、文本预算、分页、TTL、窗口失效、句柄重验、清空截图后句柄复用、坐标换算、白名单、预算、截图限频、涂黑坐标、宽高比校验、多窗口密码收集和截图错误映射。

## 未验证项与限制

- 物理 MIUI API31 真机（Redmi K30 5G，`1960cd68`）已验证真实截图、读树、节点点击/输入、节点滚动、旋转失效和物理 `FLAG_SECURE`（secure 夹具返回成功黑图，清除后恢复）；坐标手势的物理 UI 效果由产品 UI 中的真实 tap/swipe 证实，不是本插件单元测试或 integration_test 回调。锁屏、home/recents、服务中断未在物理设备运行，不能从 API35 模拟器结果推断。
- 物理设备官方测试在 M16 出现一次间歇性 `set_text` `stale_handle`（`The target node changed`，`ObservationRegistry` 的 refresh/isVisibleToUser/isEnabled 前置分支），另一次全通过；M17 用同一官方测试连续 4 轮均为 `+2`、EXIT=0，未复现，也未触发 `refresh_failed`/`not_visible`/`not_enabled`。根因仍未确认、未修复，不写成稳定通过或根因修复。
- 权限窗口、原生截图/手势/通道/worker 排队超时和带合法签名配置的 release 构建仍未验证；超时只由 Dart 注入测试覆盖工具层映射，不是设备证据。
- 权限弹窗（API35 实测）：真实 `com.google.android.permissioncontroller` 弹窗出现时，`rootInActiveWindow` 为 null，读树实测返回 `no_window`；按 `currentWindow` 前置 guard 推导输入也会返回 `no_window`（弹窗期间未直接执行输入），不会返回文档契约中的 `system_window_denied`。输入仍被拒绝，未执行手势。该偏差待后续最小修复（输入路径系统窗口识别），本轮不改生产代码，也不把 `no_window` 写成通过条件。
- 读树依赖目标应用的 `AccessibilityNodeInfo` IPC。极端情况下单次读树可能被目标应用阻塞；通道超时会让模型收到错误，但原生 worker 只能等待该调用返回，随后按队列超时跳过积压请求。
- 整屏 `AccessibilityService.takeScreenshot(Display.DEFAULT_DISPLAY)` 不保证对 `FLAG_SECURE` 报错：官方 `TakeScreenshotCallback.onFailure` 文档列出的错误码不含 `ERROR_TAKE_SCREENSHOT_SECURE_WINDOW`；该码是 API 34+ 窗口级 `takeScreenshotOfWindow` 的错误，AOSP 整屏路径没有 secure 检查。API35 模拟器实测同 UID/不同 UID 的 secure 夹具曾返回成功黑图，也观察到成功内容图；插件不根据像素猜 secure，不承诺不发送黑图，正常黑色页面保留；平台明确报错时仍映射为 `screenshot_blocked`，不发送图片。
- secure 窗口的树在 API35 夹具上可读，但不是绝对保证；密码字段、自定义 View 和窗口变化仍会影响树。
- 密码遮挡依赖应用正确标记 `isPassword`；自定义 View 和 WebView 可能遗漏，只能称为尽力而为。
- 白名单只限制输入，不限制读树和截图；白名单应用内部仍可能发生不可逆业务操作。
- 手势 `onCompleted` 只代表系统接受并完成手势，不代表业务成功。
- 后台悬浮胶囊可能出现在截图中或拦截坐标手势，首版不处理。
- 本插件不提供绝对安全保证，也不识别“发送、购买、删除”等业务语义。
