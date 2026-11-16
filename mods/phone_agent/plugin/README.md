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
final PhoneAgentScreenshot shot = await agent.screenshot(
  assistantId: 'assistant-a',
  conversationId: 'conversation-1',
);
await agent.clearScreenshot();
final Map<String, dynamic> tree = await agent.readTree(
  offset: 0,
  maxNodes: 120,
  interactiveOnly: false,
  assistantId: 'assistant-a',
  conversationId: 'conversation-1',
);
final Map<String, dynamic> result = await agent.input({
  'action': 'tap',
  'node_id': 'n3',
}, assistantId: 'assistant-a', conversationId: 'conversation-1');

final List<PhoneAgentApprovedApp> approved = await agent.approvedApps();
await agent.approveApp('com.example.app', sourceAssistantId: 'assistant-a');
await agent.revokeApp('com.example.app');

final PhoneAgentApprovalRequest request = await agent.requestApproval(
  'com.example.app',
  toolCallId: 'round-1:tool-2',
  conversationId: 'c1',
  assistantId: 'assistant-a',
);
final List<PhoneAgentApprovalRequest> pending = await agent.approvalRequests();
final PhoneAgentApprovalRequest resolved = await agent.resolveApproval(
  requestId: request.requestId,
  approve: true,
);
final bool acknowledged = await agent.privacyNoticeAcknowledged();
await agent.acknowledgePrivacyNotice();
```

`PhoneAgentScreenshot` 字段：`bytes`、`imageWidth`、`imageHeight`、`screenWidth`、`screenHeight`、`packageName`。`PhoneAgentApprovedApp` 字段：`packageName`、`signingPrefix`、`approvedAt`、`lastApprovedAt`、`sourceAssistantId`。

`PhoneAgentException(code, message)` 映射原生结构化错误。`PhoneAgentClient` 不对外导出，Kelivo 适配层只依赖 `KelivoPhoneAgent`。

## MethodChannel 协议

通道名：`kelivo/phone_agent`。

| 方法 | 参数 | 结果 |
|---|---|---|
| `status` | 无 | `{supported, enabled, connected, androidSdkInt}` |
| `openAccessibilitySettings` | 无 | `null` |
| `screenshot` | `{assistant_id?, conversation_id?}` | `{bytes: ByteArray, imageWidth, imageHeight, screenWidth, screenHeight, packageName}` |
| `clearScreenshot` | 无 | `{cleared: true}` |
| `readTree` | `{offset, max_nodes, interactive_only, assistant_id?, conversation_id?}` | `{offset, next_offset, total, truncated, text_truncated, package_name, width, height, nodes}` |
| `input` | `{action, node_id?, text?, x?, y?, end_x?, end_y?, duration_ms?, direction?, assistant_id?, conversation_id?}` | `{success, action, message}` |
| `approvedApps` | 无 | `{apps: [{package_name, signing_prefix, approved_at, last_approved_at, source_assistant_id}]}` |
| `approveApp` | `{package_name, source_assistant_id?, expected_signing_sha256?}` | `{package_name, signing_prefix, approved_at, outcome: "approved"}` |
| `revokeApp` | `{package_name}` | `{package_name, revoked}` |
| `requestApproval` | `{package_name, tool_call_id?, conversation_id?, assistant_id?}` | 批准请求载荷（见下） |
| `approvalRequests` | 无 | `{requests: [载荷]}`（只含仍 pending 的） |
| `resolveApproval` | `{request_id, approve}` | 载荷 + `approve_result?: {approved, reason}` |
| `dismissApprovals` | `{conversation_id?}` | `{dismissed: true}` |
| `privacyNotice` | 无 | `{acknowledged}` |
| `acknowledgePrivacyNotice` | 无 | `{acknowledged: true}` |

批准请求载荷：`request_id`、`package_name`、`signing_prefix`（解析失败为 null）、`signing_available`、`display_name`、`tool_call_id`、`conversation_id`、`assistant_id`、`created_at`、`expires_at`、`state`。**不含**节点文本、窗口标题、截图或界面内容。

`permission_required` 的错误载荷（`PlatformException.details`）为同一身份字段的精简版：`package_name`、`signing_prefix`、`display_name`、`signing_available`、`observation`；其他错误码的 `details` 为 null。

`approvedApps` / `approveApp` / `revokeApp` 是应用白名单的原生通道面（M33），**不依赖无障碍服务是否连接**：`AppApprovals` 与其存储由插件进程持有，Mods 页在服务关闭时也必须能撤销。三者只处理身份元数据，不返回节点文本、截图或界面内容；完整签名哈希不离开原生侧，对外只给前 8 位十六进制字符。

- `approveApp` 写入幂等：同一 `(包名, 签名集合)` 重复批准只更新最后批准时间并保留首次来源，不产生第二条记录。写入前**重新解析当前签名**——解析失败返回 `signing_unavailable`，与 `expected_signing_sha256` 不一致返回 `signing_mismatch`，两者都**不写入**（fail closed）。不传 `expected_signing_sha256` 表示“按当前签名写入”。**构建期预批准成员返回 `pre_approved`**（不写用户白名单）。
- `revokeApp` 立即生效：下一次判定即重新读存储。撤销阻止新的读树（`offset == 0`）、全部截图与全部输入；但它不撤回已发出的动作，也不清理已建立的树观测——已建立观测在 TTL 内 `offset > 0` 分页仍会回放撤销前的旧树（见下方原生行为的分页条目）。撤销预批准成员返回 `revoked: false`。
- `requestApproval` / `approvalRequests` / `resolveApproval` / `dismissApprovals` 是 M34 的批准请求状态面，同样不依赖服务连接。`resolveApproval` 是**唯一**的批准/拒绝入口（聊天卡片与通知 action 共用），幂等：请求已是终态时只返回既有状态、不写白名单；请求不存在（进程重启后通知被重放）返回 `approval_not_found`。
- `privacyNotice` / `acknowledgePrivacyNotice` 是首次启用隐私确认的本地状态（`noBackupFilesDir`，值 `acknowledged-v1`）；读不到或格式不符视为**未确认**。它只是告知记录，不改变任何判定。

### 审计元数据（M35）

`readTree` / `screenshot` / `input` 的可选参数 `assistant_id`、`conversation_id` 只用于原生侧的**审计元数据**，不参与任何授权判定（批准是按应用、全局共享的，见应用白名单）。Dart 客户端只在非空时发送；原生侧缺失或畸形时记为未知（null），**不伪造**。身份只能来自宿主调用侧：`input()` 在展开模型参数之前剔除这两个键（与 `snapshot_id` 同一处防护），模型自带的同名参数不会存活，宿主值永远优先。

审计文件是 `noBackupFilesDir/phone_agent_audit.tsv`，每条记录**恰好七列**：时间戳、助手 id、会话 id、包名、签名证书 SHA-256 前 8 位、动作类型、结果码。

- 动作类型是固定 token：`readTree`、`screenshot`、`input.tap`、`input.long_press`、`input.set_text`、`input.scroll`、`input.swipe`、`input.back`、`input.home`、`input.recents`；未知的输入动作降级为 `input`。**工具参数不进入记录**——节点 id、输入文本、坐标、时长、方向都没有落脚点。
- **不记录**节点文本、输入文本、密码内容、截图或图片字节、界面内容摘要、坐标数值、窗口标题。
- 滚动保留 **30 天或最近 2000 条，先到者生效**（恰好 30 天仍保留）。损坏行被丢弃而不是被信任。
- 只在结果收口处记录一次：成功写 `ok`，失败写既有结构化错误码（如 `system_window_denied`、`permission_required`、`busy`、`timeout`），不新增审计专用错误码。取不到前台窗口的失败（`no_window`、`device_locked`）包名为空。
- **不产生记录的两类调用**：`interrupted`（服务中断、`onUnbind`、`onDestroy` 作废的调用，没有可归属的结果）与服务未连接（调用在建立审计上下文之前就返回，一条记录都没有）。白名单方法（`approvedApps` / `approveApp` / `revokeApp`）也不审计。
- 审计失败**不阻断工具主路径**：构建、签名解析、读取与写入全程不外抛，失败只在本地计数，工具结果、白名单判定与边界策略都不受影响。
- 本地状态：不进仓库、不进聊天备份、不进入工具结果、不发给模型、不上传、不同步。**没有读取审计的通道方法，也没有界面**。

节点字段：`node_id`、`bounds`、`class`、`parent_id?`、`text?`、`description?`、`hint?`、`state_description?`、`resource_id?`、`enabled`、`clickable?`、`long_clickable?`、`editable?`、`supports_set_text?`、`scrollable?`、`checkable?`、`checked?`、`focused?`、`selected?`、`password?`。密码节点不输出文本、描述、提示和状态描述，也不遍历子树。

所有坐标都是 `[0, 1]` 归一化值，原点为截图左上角。协议和结果中不出现 `snapshot_id`；Dart 客户端会拒绝包含该键的输入参数。

### 错误码

`service_unavailable`、`unsupported_platform`、`unsupported_os`、`device_locked`、`no_window`、`invalid_argument`、`stale_observation`、`stale_handle`、`screenshot_required`、`screenshot_blocked`、`screenshot_failed`、`rate_limited`、`busy`、`interrupted`、`gesture_failed`、`gesture_timeout`、`gesture_cancelled`、`gesture_rejected`、`action_unavailable`、`action_failed`、`password_node_denied`、`package_not_allowed`、`permission_required`、`system_window_denied`、`budget_exceeded`、`timeout`、`internal_error`；白名单通道另有写入失败码 `signing_unavailable`、`signing_mismatch`、`pre_approved`，批准请求通道另有 `approval_not_found`。

`package_not_allowed` 只表示**构建期**硬禁止：M33 起构建期范围是 deny 清单（`DENY_PACKAGES`，初始为空），它同时约束输入与观察、并排在用户白名单之前。`permission_required` 表示“这个应用还没被用户批准”，输入与观察都返回该码；观察侧只带应用身份（包名 + 签名前 8 位），不带树节点、截图或图片 metadata，且该次调用**不建立观测、不占读树预算、不调用 `takeScreenshot`**。`system_window_denied` 表示硬基线或不允许的窗口类型，输入与观察都会返回，与 `permission_required`（“可以批准”）语义严格区分。

错误消息包含下一步建议，例如重新读树、重新截图、解锁手机或启用服务。

## 原生行为

- 单 worker 串行执行；手势和截图完成前，后续请求返回 `busy`。
- 每次调用和实际执行前检查锁屏、息屏和服务代次。
- 服务断开、`onInterrupt`、`onUnbind` 和 `onDestroy` 会完成所有 pending 请求并清空观测。
- 树观测 TTL 120 秒。`offset == 0` 创建新观测并重新编号；`offset > 0` 只切片当前观测，不重新遍历。**授权门控只在 `offset == 0` 判定**（门控发生在 `treeBudget` 扣减与 `beginTree` 之前）：未批准时新建观测直接返回 `permission_required` 且不建立观测，而分页请求复用该观测，只比较完整 `WindowState`。由此**撤销的生效范围是**：下一次 `offset == 0` 读树、全部截图路径、全部输入动作都会重新判定并立即反映撤销；但**已建立的观测在 TTL 到期或窗口变化之前，`offset > 0` 分页仍会成功回放撤销前读出的旧树**（既不返回 `permission_required`，也不返回 `stale_observation`）。这不构成绕过——分页只回放撤销前已读到的内容，新的读树、截图与任何输入都会被拒绝——但文档不得把撤销写成“下一次调用一定 `permission_required`”。
- 句柄只在当前观测内有效。动作后保留树句柄；每次使用前执行 `refresh()`、可见性、可用性和指纹校验。指纹不包含 `isFocused` 和动作集合 `actions`，因此点击或聚焦后同一已刷新节点仍可继续输入，动作可用性由执行层按当前节点校验；`isSelected`、内容、稳定能力字段、窗口、包名、尺寸、旋转和 TTL 变化仍失效。目标失效返回 `stale_handle`（附带变化字段名，不含内容），不会按文本或 bounds 重新解析到另一个节点。前置重验失败按 `refresh()` → 可见性 → 可用性短路，消息只追加固定诊断标识 `refresh_failed`、`not_visible`、`not_enabled`，不含节点文本、类名或 viewId；诊断不改变通过条件。
- 截图使用独立观测。动作后清空截图观测，坐标输入必须重新截图；窗口、包名、尺寸或旋转变化返回 `stale_observation`。截图位图与捕获前屏幕宽高比不一致时同样返回 `stale_observation`，不发出错位遮挡的图片。
- 前台可视化叠加层：服务内新增 `TYPE_ACCESSIBILITY_OVERLAY` 窗口（`FLAG_NOT_TOUCHABLE | FLAG_NOT_FOCUSABLE`），不需要普通悬浮窗权限。读树显示无文本边缘脉冲；截图成功后显示短暂完成脉冲；节点动作在刷新后的 `bounds` 中心显示圆环；坐标手势按同一物理起点/终点和真实 `duration_ms` 显示移动圆点；系统动作显示无文本方向图形。只在 `perform`/`dispatchGesture`/`performGlobalAction` 返回 true 后显示，拒绝路径不产生动画；动画只表示系统接受动作，不代表业务成功或用户审批。不显示输入文本、密码、节点文本、包名或坐标数值。
- 叠加层在旋转、锁屏、`onInterrupt`/`onUnbind`/`onDestroy`、服务中断和前台窗口切换到其他包时清理；`addView` 失败只禁用本会话可视化，不改变工具结果。事件在主线程绘制前再次校验清理代次和手势/服务状态，清理先于绘制时旧动画不会重新出现；移除失败或附着状态未知时不再添加新窗口。
- 截图前在主线程移除叠加层并等待两帧加约 48ms 合成周期再调用 `takeScreenshot`；没有窗口时零等待，隐藏失败、附着状态未知或约 250ms 有界等待超时返回 `screenshot_failed`，不发送图片或图片 metadata。等待可被服务中断解除，迟到的帧回调不会触发第二次截图。隐藏等待结束后、`takeScreenshot` 前重新读取当前窗口并比较 `windowId`/包名/宽高/旋转，变化返回 `stale_observation` 且不发图；异步 `takeScreenshot` 回调后再次比较，不一致同样返回 `stale_observation` 且不处理、不发送图片。窗口为 null 按 `stale_observation`，读取抛异常按 `screenshot_blocked` fail closed。同一活动窗口内新出现密码字段、非活动分屏窗口变化和同窗口分屏 resize 不保证遮挡。读树不隐藏叠加层。
- 截图前遍历 `service.windows` 中所有可访问窗口的 root 收集密码 bounds；任一窗口 root 无法读取时截图失败，不在漏遮挡的情况下发出图片。遍历只跳过能可靠确认属于本服务自己的 `TYPE_ACCESSIBILITY_OVERLAY` 窗口（root 存在且 root 包名等于自身包）；root 包名未知或其他包名的窗口继续参与遮挡，不屏蔽其他服务或应用的窗口。
- 坐标手势的视觉 travel 复用真实 `duration_ms`（50–2000ms），尾段另算，不把真实时长改成更慢的视觉时长。
- **构建期范围是 deny 清单，应用访问由用户白名单决定**（M33）：`DENY_PACKAGES` 初始为空，只有 deny 成员返回 `package_not_allowed`；其余第三方应用走用户白名单，未批准返回 `permission_required`。构建配置的预批准条目（`com.psyche.kelivo.phoneagent` 恒预批准；`com.kelivo.phoneagent.securefixture` 仅 debuggable 构建预批准）直接放行，**不写用户白名单、不产生批准提示、不可撤销**。系统窗口（`com.android.systemui`、权限控制器、安装器、证书安装器、设置及厂商变体等硬基线包）一律返回 `system_window_denied`，用户无法通过批准绕过。输入与读树/截图使用同一套判定（观察层不查询电话/短信角色持有者）。
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

批准通知与 action 接收端也由 Manifest Merger 合并（M34）：

```xml
<receiver
    android:name="com.kelivo.phoneagent.PhoneAgentApprovalReceiver"
    android:exported="false" />
```

它只接收本应用自己的 `PendingIntent`；批准/拒绝的幂等与终态校验在 `ApprovalRequests` 内完成，不依赖 intent 来源。通知渠道为 `kelivo_phone_agent_approval`，文案在插件自己的 `strings.xml`（中英两套），**不复用上游 `NotificationService`**。

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

Dart 测试覆盖通道参数、默认值、错误映射、超时、`clearScreenshot`、`snapshot_id` 拒绝，白名单通道 `approvedApps` / `approveApp` / `revokeApp`（含畸形载荷、可选参数、本地校验与 `signing_mismatch` 映射），审计身份参数转发（含空白值不发送、无身份时载荷与旧协议一致），以及批准请求通道与结构化身份。Kotlin 测试覆盖有界 DFS、密码子树、文本预算、分页、TTL、窗口失效、句柄重验、清空截图后句柄复用、坐标换算、边界策略（硬基线、窗口类型两层、deny 清单、用户白名单、预批准）、签名身份与白名单存储（多签名、幂等、撤销即时、损坏行丢弃）、批准请求状态机（TTL 到期、单终态、取代、按会话清理、预批准拒绝写入、签名缺失 fail closed）、隐私确认状态、预算、截图限频、涂黑坐标、宽高比校验、多窗口密码收集和截图错误映射，以及审计日志（字段集合精确断言含七项禁用字段、TSV 列数、30 天与 2000 条滚动、损坏行丢弃、写入/读取失败不阻断、签名解析抛异常降级为 null）。
## 未验证项与限制

- M23 前台可视化叠加层（round 4 设备运行树 `9ebf2e991caa07ed`，最终源码树仅本 README 副本不同，hash 见 `docs/phone-agent-plan.md` 9.3.7）：API35 独立 AVD `Kelivo_M23_API_35` 完整异常套件 **`+8`、`All tests passed!`、EXIT=0**（含旋转、锁屏、服务禁用/重启、权限窗口），官方测试 `+2`、EXIT=0；物理 MIUI API31 官方测试 `+2`、截图无污染 `+1`，均 EXIT=0；服务停用后无孤儿窗口。API35 服务禁用用例单独 `+1`、EXIT=0，宿主 `dumpsys` 原始输出 `R5_OVERLAY_WINDOWS_AFTER_DISABLE: count=0`、`R5_OVERLAY_WINDOWS_AFTER_RESTART: count=0`；宿主 `screenrecord` 帧确认观察脉冲、节点点击圆环和坐标滑动轨迹（1500ms 定向验证，`#008999` 圆点沿 x≈539 从 y≈1110 上移到 y≈462，约 42 帧/1.4s）。返工期间旧 AVD 曾出现 `Input dispatching timed out (Application does not have a focused window)` 与 `com.android.systemui` 的 edge-swipe 手势监视器 ANR，均无产品栈，属宿主/模拟器窗口焦点与输入分发问题，不是 overlay 主线程死锁；round 2 树 `f1b26a580b737e14` 的历史 `+6 -2` 见计划 9.3.7。产品 APK 大小/hash 与 manifest 隔离见 `docs/phone-agent-plan.md` 9.3.7；API29、签名 release 未验证；观察脉冲、节点点击圆环和坐标滑动轨迹均已获宿主 `screenrecord` 像素证据（滑动为 1500ms 定向验证），不写成像素级验证。
- 物理 MIUI API31 真机（Redmi K30 5G，`1960cd68`）已验证真实截图、读树、节点点击/输入、节点滚动、旋转失效和物理 `FLAG_SECURE`（secure 夹具返回成功黑图，清除后恢复）；坐标手势的物理 UI 效果由产品 UI 中的真实 tap/swipe 证实，不是本插件单元测试或 integration_test 回调。锁屏、home/recents、服务中断未在物理设备运行，不能从 API35 模拟器结果推断。
- 物理设备官方测试在 M16 出现一次间歇性 `set_text` `stale_handle`（`The target node changed`，`ObservationRegistry` 的 refresh/isVisibleToUser/isEnabled 前置分支），另一次全通过；M17 用同一官方测试连续 4 轮均为 `+2`、EXIT=0，未复现，也未触发 `refresh_failed`/`not_visible`/`not_enabled`。根因仍未确认、未修复，不写成稳定通过或根因修复。
- 原生截图/手势/通道/worker 排队超时和带合法签名配置的 release 构建仍未验证；权限弹窗的保守拒绝已在 API35 模拟器验证（`no_window` + 条件式提示，未执行手势/系统导航），物理设备和其他 Android 版本未验证；超时只由 Dart 注入测试覆盖工具层映射，不是设备证据。
- 权限弹窗（API35 实测）：真实 `com.google.android.permissioncontroller` 弹窗出现时，`rootInActiveWindow` 为 null；活动/聚焦弹窗窗口 `hasRoot=false`、`pkg=null`，`AccessibilityWindowInfo` 没有包名字段，服务也收不到 `permissioncontroller` 的 `TYPE_WINDOW_STATE_CHANGED`（M20/M21 已证伪两种识别机制）。读树、截图和输入均返回 `no_window`，错误消息只做条件式人工提示（“如果看到系统权限弹窗，请人工处理/取消，再返回测试应用”），不声称识别具体权限弹窗；可取得系统包名的窗口仍返回 `system_window_denied`。该保守收尾不改变错误优先级、密码遮挡或输入边界，也不把 `no_window` 写成通过条件。
- 读树依赖目标应用的 `AccessibilityNodeInfo` IPC。极端情况下单次读树可能被目标应用阻塞；通道超时会让模型收到错误，但原生 worker 只能等待该调用返回，随后按队列超时跳过积压请求。
- 整屏 `AccessibilityService.takeScreenshot(Display.DEFAULT_DISPLAY)` 不保证对 `FLAG_SECURE` 报错：官方 `TakeScreenshotCallback.onFailure` 文档列出的错误码不含 `ERROR_TAKE_SCREENSHOT_SECURE_WINDOW`；该码是 API 34+ 窗口级 `takeScreenshotOfWindow` 的错误，AOSP 整屏路径没有 secure 检查。API35 模拟器实测同 UID/不同 UID 的 secure 夹具曾返回成功黑图，也观察到成功内容图；插件不根据像素猜 secure，不承诺不发送黑图，正常黑色页面保留；平台明确报错时仍映射为 `screenshot_blocked`，不发送图片。
- secure 窗口的树在 API35 夹具上可读，但不是绝对保证；密码字段、自定义 View 和窗口变化仍会影响树。
- 密码遮挡依赖应用正确标记 `isPassword`；自定义 View 和 WebView 可能遗漏，只能称为尽力而为。
- **审计元数据（M35）没有设备证据**：真实设备上的文件写入、进程重启后的追加与 2000 条滚动、多签名包的前缀取值均未实测；M35 未构建 APK、未接设备。审计只写七项元数据，但**不得据此宣称审计不涉及隐私**——它仍能推断“用过哪些应用”。
- **白名单同时限制输入与观察**（M33 起）：未批准应用的读树与截图返回 `permission_required` 且只回应用身份，不建立观测、不截图；批准后可以读树、截图并输入，同一 `(包名, 签名集合)` 一次批准覆盖这三种能力。已批准应用内部仍可能发生不可逆业务操作。
- 手势 `onCompleted` 只代表系统接受并完成手势，不代表业务成功。
- 后台悬浮胶囊可能出现在截图中或拦截坐标手势，首版不处理。
- 前台可视化叠加层是 `TYPE_ACCESSIBILITY_OVERLAY` 窗口，`addView` 在部分厂商 ROM 上可能失败；失败时只禁用本会话可视化，工具行为不变。叠加层无法隐藏上游胶囊，截图隐藏握手会增加约两帧等待并可能返回 `screenshot_failed`；动画不代表业务成功或用户审批。
- 白名单通道（M33）的签名解析能力**未在设备上验证**：`QUERY_ALL_PACKAGES` 声明后交付服务进程能否解析任意前台包签名，只在 M29 用探针 APK 验证过；解析失败的形态按 fail closed 处理（`permission_required`），但真实失败形态未实测。
- **批准交互（M34）完全没有设备证据**：通知权限（API 33+ `POST_NOTIFICATIONS`）与通知 action 的真实行为、进程被杀后系统重放 action、跨 UID 前台包签名解析、`Resolution` 在真实对话流中的卡片布局、通知与卡片同时存在时的撤下时序、服务关闭时 Mods 页撤销链路，全部只经过单元测试与静态检查。`pre_approved` 之外的批准失败在 UI 上的表现也未实测。
- 本插件不提供绝对安全保证，也不识别“发送、购买、删除”等业务语义。
