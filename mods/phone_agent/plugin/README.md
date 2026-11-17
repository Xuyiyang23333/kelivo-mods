# kelivo_phone_agent 插件

独立 Android Flutter 插件，为 `phone_agent` Mod 提供截图、无障碍节点树、输入控制与应用启动能力。插件不 import `package:Kelivo/...`，不修改上游 `PhoneControlService`。

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

## MethodChannel 协议

通道名：`kelivo/phone_agent`。

| 方法 | 参数 | 结果 |
|---|---|---|
| `status` | 无 | `{supported, enabled, connected, androidSdkInt}` |
| `openAccessibilitySettings` | 无 | `null` |
| `screenshot` | 无 | `{bytes: ByteArray, imageWidth, imageHeight, screenWidth, screenHeight, packageName}` |
| `clearScreenshot` | 无 | `{cleared: true}` |
| `readTree` | `{offset, max_nodes, interactive_only}` | `{offset, next_offset, total, truncated, text_truncated, package_name, width, height, nodes}` |
| `input` | `{action, node_id?, text?, package_name?, x?, y?, end_x?, end_y?, duration_ms?, direction?}` | 动作结果或 `{apps: [{name, package_name}]}` |

## 原生行为与错误码

- 协议不暴露 `snapshot_id`，节点句柄与 120 秒 TTL 由原生侧 `ObservationRegistry` 维护；`windowType` 短暂滞后、可编辑框文本变化与 `isChecked`/`isSelected` 状态切换不会使有效句柄失效，坐标手势直接按当前窗口尺寸映射、不依赖前置未消费截图。
- 密码节点不输出文本、描述、提示与状态描述，也不遍历子树；密码节点禁止输入；截图前遮挡所有可见密码区域。
- 常用结构化错误码：`service_unavailable`、`unsupported_platform`、`unsupported_os`、`device_locked`、`no_window`、`invalid_argument`、`app_not_found`、`stale_observation`、`stale_handle`、`screenshot_blocked`、`screenshot_failed`、`rate_limited`、`busy`、`interrupted`、`gesture_failed`、`gesture_timeout`、`gesture_cancelled`、`gesture_rejected`、`action_unavailable`、`action_failed`、`password_node_denied`、`system_window_denied`、`budget_exceeded`、`timeout`、`internal_error`。
