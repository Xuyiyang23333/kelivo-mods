# Phone Agent Mod 实施与验收说明

## 当前状态

- 当前采用**精简实用方案（方案 A）**，Mod 版本 `0.2.0`。
- 通用 Mod Loader 已完成验收；Phone Agent 的独立插件、工具链接入、Mods 设置页和 Android 无障碍能力均已实现。
- 用户已确认真机功能正常，当前版本作为稳定可用版本保留。
- 本文只记录当前契约和维护方式，不再保留逐轮里程碑、审查与设备日志。历史实现和验收记录可从 Git 历史查阅。

上游基线：`73afa4ec77cfc9af2efea2487fee8bba1362639d`。安装与使用说明见 [Phone Agent README](../mods/phone_agent/README.md)，插件通道说明见 [插件 README](../mods/phone_agent/plugin/README.md)。

## 架构边界

- Phone Agent 是编译前源码 Mod，由 Loader 按固定上游 commit 合成，不是运行时插件平台。
- 使用独立 `kelivo_phone_agent` Flutter 插件、`kelivo/phone_agent` MethodChannel 和 `PhoneAgentService`，不修改上游 `PhoneControlService`。
- Kelivo 侧通过通用 `ToolMod` 接缝添加工具定义并包装 handler；Loader 通用代码不依赖 Phone Agent。
- 助手级工具 ID 为 `phone_agent`，不加入 `LocalToolNames.all`。Mods 页在关闭、原生手机控制和 Phone Agent 之间三态互斥切换。
- 工具选择不自动修改系统无障碍授权；上游和 Mod 的两个无障碍服务仍由系统独立管理。
- `application-id.patch` 使用独立包名和应用名，便于与主线 Kelivo 共存测试；不再需要共存时可单独评估移除。

## 工具契约

### `phone_agent_screenshot`

- 仅向支持图片输入的视觉模型暴露，要求 Android API 30+。
- 使用无障碍整屏截图，长边缩放到不超过 1600，并复用 Kelivo 现有图片工具结果链路。
- 截图前隐藏本 Mod 的可视化叠加层，并涂黑可识别的密码区域。

### `phone_agent_tree`

- 按需读取有界无障碍节点树，支持 `offset` 分页、`max_nodes` 和 `interactive_only`。
- 密码节点及其子树不输出，避免密码文本进入模型上下文。
- 节点句柄由原生侧维护，模型只使用 `n0`、`n1` 等短 ID，不管理 `snapshot_id`。

### `phone_agent_input`

- 节点动作：`tap`、`long_press`、`set_text`、`scroll`。
- 坐标动作：`tap`、`long_press`、`swipe`，使用归一化 `[0, 1]` 坐标，对所有支持工具调用的模型开放，不要求前置截图。
- 系统与辅助动作：`back`、`home`、`recents`、`wait`。
- 应用动作：`list_apps` 枚举可启动第三方应用，`open_app` 按 `package_name` 启动应用。

所有 schema 使用 `additionalProperties: false`。节点或窗口失效时返回结构化错误，要求重新观察，不自动点击相似节点或盲目重试。

## 原生状态与安全护栏

- 单 worker 串行处理请求，手势单飞；服务中断时取消待执行请求。
- 操作前检查设备解锁状态、窗口归属、句柄或观测有效性，并执行生成级动作预算和频率限制。
- 节点句柄默认 TTL 为 120 秒；支持节点路径重解析和指纹重验，避免平台重建节点对象造成不必要的 `stale_handle`。
- `HARD_BASELINE_PACKAGES` 禁止自动化系统设置、权限控制器、包安装器、证书安装器、`systemui` 和承载包 `com.psyche.kelivo`；默认电话/短信角色持有者禁止输入。
- 输入只允许普通应用窗口；观察侧容忍 `windows` 列表短暂滞后，不因暂时无法解析窗口类型阻断普通应用。
- 密码节点禁止直接输入，读树过滤密码内容，截图遮挡密码区域。
- 独立 `TYPE_ACCESSIBILITY_OVERLAY` 提供无文本操作反馈，窗口不可触摸、不可聚焦，截图前自动隐藏。

当前版本**不包含**逐应用签名白名单、批准卡片或通知、首次隐私弹窗、本地审计落盘和 `QUERY_ALL_PACKAGES` 权限。普通第三方应用不需要逐应用批准。

## 验证与维护

Loader 检查：

```bash
dart format --output=none --set-exit-if-changed tool test
dart analyze tool test
dart test
dart tool/mod_loader.dart apply
dart tool/mod_loader.dart verify
```

插件与合成树检查：

```bash
cd mods/phone_agent/plugin
flutter test

# 在 .build/worktrees/<hash16>/ 中执行
gradle -p android :kelivo_phone_agent:testDebugUnitTest  # 或本地 Gradle 8.14 的等价路径
dart analyze --fatal-infos lib test integration_test
flutter test test/features/phone_agent test/features/mods test/features/settings/pages/mods_settings_entry_test.dart
flutter test test/features/home/services/tool_handler_service_test.dart test/features/home/services/tool_handler_workspace_gating_test.dart test/request_consistency_test.dart
flutter build apk --debug
```

自动化检查不能替代真实设备体验。后续修改应根据真机和真实模型任务反馈进行，不恢复多份历史流水账文档；只更新受影响的接口、使用说明和当前状态。

更新上游时先运行 `dart tool/mod_loader.dart rebase-drill --to <完整 commit>`，再人工处理补丁冲突与 vendored 来源漂移，不自动切换基线。

## 已知边界

- 密码遮挡和窗口检查是技术护栏，不保证覆盖所有自定义 View、WebView 或厂商系统行为。
- 不自动识别并阻止所有发消息、购买、删除等业务层面的不可逆操作。
- `FLAG_SECURE` 内容可能在成功截图中呈黑色；不要把黑图当作可靠的坐标依据。
- 上游后台悬浮胶囊可能进入截图或拦截坐标手势，本 Mod 不处理其他 owner 的窗口。
- 可视化叠加层只表示系统接受或完成动作，不代表业务成功；厂商 ROM 可能拒绝添加叠加窗口。
- 非 Android 平台不加载 Phone Agent 工具；API 29 可使用树和节点输入，但截图不可用。
- 当前真机验收不表示所有设备、Android 版本和模型组合均已验证，也不等同于签名 release 发布验收。
