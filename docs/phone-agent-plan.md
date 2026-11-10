# Kelivo Phone Agent Mod 实施计划

## 0. 文档状态

- 当前阶段：第二阶段最终验收完成（UI/选择契约改造已完成），Mod 版本 0.2.0。
- 本轮修正（节点重验）：`PhoneNode.fingerprint()` 不再包含 `isFocused` 和动作集合 `actions`；同一已刷新节点因点击/输入产生的焦点变化和动作增减不再让后续 `set_text` 返回 `stale_handle`；`isSelected`、内容、稳定能力字段、窗口/包名/尺寸/旋转和 120 秒 TTL 校验保持不变。指纹为结构化字段列表，`stale_handle` 只附带固定字段名，不从节点内容反解字段名。契约见 6.5.1。
- 当前最终合成树：`V:/coding/kelivo-private/.tower/worktrees/wt-1/.build/worktrees/7593c21b5f9da01f`，`modsetHash` 为 `7593c21b5f9da01fb8b8c4dfe167d892a940efe4a1caf591b772fbe83b6b6f7d`，`dart tool/mod_loader.dart verify` 通过。该树由本任务私有 worktree 生成；Windows 路径长度限制通过 `GIT_CONFIG_*` 环境变量注入 `core.longpaths=true` 解决，未修改任何 Git 配置文件。
- 当前最终自动检查：Loader format/analyze 通过、Loader 165 项通过；新合成树 `dart format`、`dart analyze --fatal-infos lib test integration_test tool` 通过；Phone Agent 103、Mods 16、settings 入口 2 通过；插件 Dart 17、插件 Kotlin 66（ObservationRegistryTest 24、NodeActionExecutorTest 3 等）、上游 PhoneControl 49 通过。
- 本地化：23 个键已由本机免费 Magpie llama-cpp 翻译，`translate.py check` 四个目标语言（ko、ru、tr、zh_Hant）均 0 pending；本轮无 UI/ARB 改动，未重跑翻译生成。
- 当前产品 APK：`V:/coding/kelivo-private/.tower/worktrees/wt-1/.build/worktrees/7593c21b5f9da01f/build/app/outputs/flutter-apk/app-debug.apk`，181369230 字节，SHA-256 `3ea30ee9b46342305cf11e0574b76def9a42f23abe62dd3536b664dc4ec5caeb`。
- 设备回归：API 35 模拟器与 API 29 真机官方集成测试均退出码 0，逐项结果见 9.3；该结果对应提交 `698cace` 的运行时语义。之后仅调整诊断编码、提取纯 JVM 前置校验接缝、补测试和文档，未重复双 API 设备回归（按 R1 审查意见）。
- 历史验收记录（焦点修正前，不代表当前实现）：最终合成树 `V:/coding/kelivo-private/.build/worktrees/4ed083cf5fe7dda8`，`modsetHash` 为 `4ed083cf5fe7dda8eec575588594831d9515cbd88429cb6f5b893c9ca6544331`；Flutter 255 项（254 通过 + 1 Windows 条件跳过）；插件 Kotlin 55；旧产品 APK 181354638 字节，SHA-256 `af67f4285bef9e3d1093c6433f42669a8c84b8bee99b6397f68dfd91e1c60ceb`；当时的未验证项包含 API 30+ 截图与坐标手势。
- 仍明确未验证：物理 API 30+ 真机的坐标手势 UI 效果（integration_test 绑定不转发设备指针事件）、VLM 固定任务与图片链路、真实 `FLAG_SECURE`、其他真机异常路径、签名 release。因此不宣称 Phone Agent 第二阶段全部完成。
- Mod Loader 的目录、命令、补丁机制和通用接缝见 [Mod Loader 实施计划](mod-loader-plan.md)。
- 本文只定义 `phone_agent` Mod，不重复 Loader 的通用实现。
- 基线仓库：`V:/coding/kelivo`。
- 基线 commit：`73afa4ec77cfc9af2efea2487fee8bba1362639d`。
- 本文与 Loader 计划均位于私有仓 `docs/`，上游仓只作为源码来源。

## 1. 目标、原则与非目标

### 1.1 目标

1. 在通用 Mod 接缝之上实现独立的 Android 手机 Agent。
2. 提供截图、按需无障碍树和基础输入三个基础工具。
3. 截图可以直接进入 Kelivo 现有的 VLM 工具图片链路。
4. 使用独立 Flutter path 插件和独立 `AccessibilityService`，不修改上游 `PhoneControlService`。
5. 模型不管理 `snapshot_id`；节点句柄、截图状态和时效由原生侧维护。
6. 允许模型在目标仍有效时复用节点句柄，按任务语义决定何时重新观察。
7. 保留可验证的原生技术护栏，同时如实说明业务安全和隐私边界。
8. 为每个助手提供独立 localToolId `phone_agent`，不再复用 `phone_control`。
9. 在 Mods 页提供助手选择和三态单选，并显示独立 `PhoneAgentService` 的服务状态。
10. 新增移动和桌面 Mods 设置入口，产品文案按上游标准进入 ARB 并同步所有目标语言。

### 1.2 原则

- 先完成只读闭环，再增加真实输入，最后验证 VLM 任务。
- 工具协议尽量少状态，原生执行层负责句柄和窗口管理。
- 节点输入优先，坐标输入作为视觉和自绘界面的补充。
- 观察按需发生，不强制每个动作后重新读取完整界面。
- 原生技术护栏尽量硬实现，业务风险识别不作虚假保证。
- 首版只在显式测试包名中开放输入，不直接面向敏感应用。
- 工具选择与服务授权分离。Mods 页的三态选择只决定助手使用哪套工具，不代表系统无障碍服务已经授权。
- 正常 UI 不允许原生手机控制和 Phone Agent 同时启用；两者互斥写入助手的 `localToolIds`。
- 已有仅启用 `phone_control` 的助手保持原生行为，不自动迁移，不批量改写 `localToolIds`。
- 两个 `AccessibilityService` 继续共存；启用其中一个不会自动启用、授权或切换另一个。
- 面向开发者和维护者的文档使用中文；工具 schema 和结构化错误沿用现有代码的英文风格；产品 UI 文案进入 ARB。

### 1.3 非目标

Phone Agent 首版不做：

- 自动识别并可靠拦截“发送、购买、删除”等业务动作。
- 通用逐步确认系统、危险文本分类器或第二个 LLM 风险审查器。
- 自动迁移已有助手，或把仅启用 `phone_control` 的助手批量改成 `phone_agent`。
- 自动授权无障碍服务、自动打开系统无障碍开关，或在两个服务之间自动切换。
- 把 Mods 页接入上游设置搜索索引。
- 上游工具目录集成、运行时 Mod 商店、动态 Dart 加载或运行时下载插件。
- 在正常 UI 中同时启用原生手机控制和 Phone Agent。
- 运行时编辑测试包白名单或按应用配置策略。
- `list_apps`、`open_app`、通知栏和快捷设置操作。
- 多显示器、折叠屏专项适配或 MediaProjection 截图后备方案。
- 自动上下文压缩、树差分、跨观测稳定节点 ID。
- Shell、root、Shizuku、录屏或任意文件访问。
- 对任意应用、任意模型或任意任务成功率的承诺。

## 2. 与 Kelivo 的集成边界

### 2.1 通用 Mod 接缝

Phone Agent 通过 Loader 生成的静态注册表实现：

- `decorateDefinitions`：按平台、助手工具选择和模型能力添加或移除工具定义；
- `wrapHandler`：处理 `phone_agent_*` 调用，其余调用原样委托给上游 handler。

`LocalToolNames.all` 不加入 `phone_agent`，避免上游按 `all` 生成原生工具定义、工具标签或本地工具开关。`phone_agent` 是 Mod 自有的助手级工具 ID，由 Mod overlay 中的常量定义；如果实现选择在上游类中增加常量，也必须不加入 `all`，且不得生成原生定义。

上游助手的“本地工具”页和对话工具菜单不新增 `phone_agent` 项。Phone Agent 的助手级选择只在 Mods 页完成；上游本地工具页仍按上游行为显示原生 `phone_control`。这些上游界面不显示 `phone_agent`；选择 Phone Agent 后，它们可能把手机控制显示为未启用，这是预期行为，以 Mods 页为准。

### 2.2 助手级工具选择：三态契约

Mods 页提供助手选择，并对当前助手提供三个互斥选项：

| 选择 | 写入 `assistant.localToolIds` | 上游授权页 | 工具定义 |
|---|---|---|---|
| 关闭 | 移除 `phone_control` 和 `phone_agent` | 不打开 | 不暴露原生手机控制和 Phone Agent 工具 |
| 原生手机控制 | 保留或加入 `phone_control`，移除 `phone_agent` | 继续打开上游手机控制授权页 | 使用上游 `phone_control` |
| Phone Agent | 加入 `phone_agent`，移除 `phone_control` | 不自动打开 | 使用 Mod 的 `phone_agent_*` |

规则：

- 三个选项是单选，正常 UI 不允许两者同时启用。写入一个选项时必须移除另一个 ID。
- 选择“原生手机控制”后，页面按上游现有流程进入手机控制授权页；授权是否完成由上游页面和系统设置决定。
- 选择“Phone Agent”只写入工具 ID，不自动授权、不自动打开系统无障碍设置；服务状态由 Mods 页单独显示。
- 选择“关闭”移除两个 ID，但不自动关闭系统无障碍服务。
- 已有仅启用 `phone_control` 的助手在 Mods 页显示为“原生手机控制”，不自动迁移。
- 如果历史数据、手工编辑或上游本地工具页导致两个 ID 同时存在，Mods 页显示冲突状态并要求重新选择；在用户处理前，`PhoneAgentMod` 以 `phone_agent` 为激活依据，并过滤原生 `phone_control` 定义，避免同时暴露两套工具。
- 上游本地工具开关与页面的互斥由 phone_agent Mod 自己的 `local-tool-mutual-exclusion.patch` 执行，不是 Loader 通用接缝。该补丁必须保证 `phone_control` 与 `phone_agent` 不会同时写成启用；如果无法隐藏或拦截 `phone_control`，Mods 页必须显示冲突并要求重新选择，执行层按 `phone_agent` 激活并过滤原生 `phone_control`，不能静默并存。
- 每次执行 Mod 工具前，通过 `AssistantProvider.getById` 重读当前助手的 `phone_agent`。生成途中撤销选择后，后续调用返回 `phone_agent_disabled`，不再继续操作。
- 选择只修改 `assistant.localToolIds`，不修改数据库 schema，不新增助手字段。

### 2.3 Mods 设置页与服务状态

新增移动和桌面 Mods 设置入口，宽窄屏共用同一个简单页面，不单独做桌面/移动两套布局，也不接入 `settings_search_index.dart`。

页面包含：

1. 助手选择器：列出助手并显示当前三态；切换助手时读取该助手的 `localToolIds`。
2. 三态单选：关闭、原生手机控制、Phone Agent，按 2.2 的规则互斥写入。
3. 独立 `PhoneAgentService` 状态面板：显示 supported、enabled、connected 和 sdk，并用 `enabled && connected` 派生 ready。
4. 刷新按钮：重新读取插件状态。
5. 打开无障碍设置按钮：调用插件的 `openAccessibilitySettings()`，失败时提示用户手动进入系统设置。
6. 能力与隐私说明：说明可读取屏幕、点击、输入、滚动和截图，屏幕内容会发送给当前对话配置的模型服务商并保存在工具结果中，密码字段会隐藏，服务不会持续录屏，用户可随时关闭工具或停用服务。

状态字段含义：

| 字段 | 含义 |
|---|---|
| `PhoneAgentAvailability.supported` | 仅表示 Android API 30+ 系统截图能力；false 不代表 Phone Agent 或平台不可用。 |
| `enabled` | 系统无障碍设置中是否已启用独立 `PhoneAgentService`。 |
| `connected` | 独立服务是否已连接并可以接收请求。 |
| `ready` | 由 `enabled && connected` 派生；表示服务可接收请求，树和节点输入可用。API 29 也可以 ready。 |
| `sdk`（`androidSdkInt`） | 当前 Android API 级别；`sdk >= 30` 时截图和坐标手势可用。 |

`PhoneAgentAvailability.supported` 只描述截图能力，不是 Phone Agent 的总体可用性。API 29 上 `supported=false`，但服务仍可 `enabled` 且 `connected`，即 ready，树和节点输入可用；截图返回 `unsupported_os`，页面显示截图和坐标手势限制。非 Android 平台不加载 Mod 工具，页面显示平台不支持；不要用 `supported=false` 表示平台不支持。

非 Android 平台仍可打开 Mods 页，但页面显示平台不支持，不添加任何 Mod 工具；这与 `supported=false` 的截图限制含义不同。

两个 `AccessibilityService` 继续共存：上游 `PhoneControlService` 和独立 `PhoneAgentService` 各自在 Manifest 中声明，各自在系统设置中授权。Mod 不自动授权、不自动切换、不在用户选择某个工具时修改系统无障碍开关。

### 2.4 图片链路

直接复用现有链路，不修改 provider：

```text
phone_agent_screenshot
  → Kelivo 适配层
  → McpImageSnapshot.saveBytes
  → ClientToolResult + metadata.mcpResult.imageUris
  → 工具循环与消息持久化
  → ToolResultContent
  → OpenAI / Claude / Gemini 请求
```

关键现有实现：

- `lib/utils/mcp_structured_image.dart:46`：图片元数据。
- `lib/utils/mcp_structured_image.dart:95`：`ClientToolResult`。
- `lib/core/services/mcp/mcp_image_snapshot.dart:54`：图片落盘及实际尺寸。
- `lib/core/services/api/generation/tool_loop_runner.dart:195`：工具结果接入。
- `lib/core/services/api/tool_result_content.dart:15`：按模型能力读取或省略图片。
- `lib/core/services/browser/browser_tools_service.dart:816`：现有图文工具结果示例。

视觉能力只在定义接缝中判断。执行 handler 不猜模型能力，图片是否进入请求继续由 `ToolResultContent` 决定。

### 2.5 后台悬浮胶囊

独立服务不会触发上游 `phoneControlStarted()`。用户开启后台胶囊时，胶囊可能出现在截图中或拦截坐标手势。

首版保留此限制，不增加 Android 宿主补丁。默认关闭胶囊的真机验收必须全部通过；开启胶囊的情况只记录，不宣称兼容。

## 3. Mod 文件结构

以下为当前文件划分；职责和边界不变。`mod.json` 的 `patches`、`touches` 和 `copy` 必须与最终文件一致。

```text
mods/phone_agent/
├── mod.json
├── README.md                   # 中文安装、选择、授权、白名单、限制与维护说明
├── patches/
│   ├── pubspec.patch           # path 依赖
│   ├── application-id.patch    # 独立测试包名与启动名称
│   ├── local-tool-mutual-exclusion.patch  # 本地工具开关互斥
│   ├── settings-entry.patch    # 移动和桌面 Mods 设置入口
│   ├── l10n-source.patch       # 新增 ARB 键和英文描述
│   └── l10n-generated.patch    # 翻译后的 ARB、状态和生成 Dart
├── overlay/
│   ├── lib/features/phone_agent/
│   │   ├── phone_agent_mod.dart
│   │   ├── phone_agent_tools.dart
│   │   ├── phone_agent_service.dart
│   │   ├── phone_agent_screenshot.dart
│   │   └── phone_agent_local_tool.dart
│   ├── lib/features/mods/
│   │   └── mods_page.dart
│   ├── test/features/phone_agent/
│   ├── test/features/mods/
│   ├── test/features/settings/pages/
│   │   └── mods_settings_entry_test.dart
│   └── integration_test/phone_agent_test.dart
└── plugin/                     # 复制为 dependencies/kelivo_phone_agent/
```

文件职责：

- `phone_agent_local_tool.dart`：`PhoneAgentLocalTool.id`、`PhoneAgentControlSelection`、`applySelection`、`writeSelection` 和冲突检测。
- `mods_page.dart`：`ModsPage`、`ModsPane` 和共用 `ModsView`；助手选择、三态单选、服务状态、刷新、打开无障碍设置和能力/隐私说明。
- `local-tool-mutual-exclusion.patch`：修改 `lib/features/home/services/local_tool_toggle.dart`，在本地工具开关写入时保证 `phone_control` 与 `phone_agent` 互斥，并重读当前助手避免旧快照覆盖。它是 phone_agent Mod 自己声明的业务补丁，不是 Loader 通用接缝。
- `settings-entry.patch`：在 `lib/features/settings/pages/settings_page.dart` 和 `lib/desktop/desktop_settings_page.dart` 增加 `ModsPage`/`ModsPane` 入口及桌面菜单注册，不修改 `lib/features/settings/search/settings_search_index.dart`。它是 phone_agent Mod 自己声明的业务补丁，不是 Loader 通用接缝；只增加入口和导入，不把 Mod 业务逻辑写进上游文件。
- `l10n-source.patch`：在 `lib/l10n/app_en.arb` 和 `app_zh.arb` 增加产品文案键及 `@key.description`。
- `l10n-generated.patch`：包含本机免费 llama-cpp 翻译后的 ARB、`tool/l10n/state` 和生成的 Dart 输出；`translate.py check` 四目标语言 0 pending。
- `mod.json`：当前已声明 `local-tool-mutual-exclusion.patch`、`settings-entry.patch`、`l10n-source.patch`、`l10n-generated.patch`，以及 `touches`（含本地工具开关、移动/桌面设置页、`lib/l10n` 和 `tool/l10n/state`）、复制目标和工具名；修改时必须保持与最终文件一致。

Loader 通用 `lib/modding/tool_mod.dart` 和 `mod_registry` 生成逻辑不 import Phone Agent。`mod_registry.g.dart` 中的 Mod import 只来自 `mod.json` 的 `registration.import`，不是 Loader 通用代码的硬编码依赖。

`mod.json` 额外记录上游 `PhoneControlService.kt` 的来源 commit 和内容哈希，作为 vendored 参考实现的漂移提醒。Loader 只负责提示变化，是否吸收上游修复由人工审查决定。

## 4. Kelivo 适配层

由 `overlay/` 新增或更新：

| 文件 | 职责 |
|---|---|
| `lib/features/phone_agent/phone_agent_mod.dart` | 注册类；按 Android、助手 `phone_agent` 和工具能力激活；过滤原生 `phone_control` 与重复 `phone_agent_*`；包装 handler；执行前重查 ID。 |
| `lib/features/phone_agent/phone_agent_tools.dart` | 三个工具 schema、名称集合和调用分发。 |
| `lib/features/phone_agent/phone_agent_service.dart` | 调用独立插件、读取 supported/enabled/connected/sdk 状态并派生 ready、结构化错误。 |
| `lib/features/phone_agent/phone_agent_screenshot.dart` | 图片落盘、尺寸校验、`ClientToolResult` 元数据。 |
| `lib/features/phone_agent/phone_agent_local_tool.dart` | `PhoneAgentLocalTool`/`PhoneAgentControlSelection`；三态选择、`localToolIds` 互斥读写和冲突检测。 |
| `lib/features/mods/mods_page.dart` | `ModsPage`/`ModsPane`/`ModsView`；移动/桌面共用页面，不接设置搜索。 |

适配层可以 import Kelivo 和插件；独立插件不能反向 import `package:Kelivo/...`，避免循环依赖。

定义包装位于上游 schema override 之后，首版不支持用上游 schema override 修改 Mod 工具。执行包装位于上游 handler 之外，首版也不自动继承上游通用审批流程。

## 5. 独立 Flutter 插件

`plugin/` 在合成树中复制为 `dependencies/kelivo_phone_agent/`：

| 文件 | 职责 |
|---|---|
| `pubspec.yaml` | 声明 Android Flutter 插件。 |
| `lib/kelivo_phone_agent.dart` | 对外纯 Dart API。 |
| `lib/src/phone_agent_client.dart` | 独立 `MethodChannel('kelivo/phone_agent')`。 |
| `lib/src/phone_agent_types.dart` | 状态、截图、树页、输入结果和异常类型。 |
| `android/build.gradle` | Android library 与 Kotlin 配置，对齐宿主 SDK/JVM。 |
| `android/src/main/AndroidManifest.xml` | 声明独立无障碍服务，由 Manifest Merger 合并。 |
| `android/src/main/res/xml/kelivo_phone_agent_service.xml` | `canRetrieveWindowContent`、`canPerformGestures`、`canTakeScreenshot` 等配置。 |
| `android/src/main/res/values/strings.xml` | 独立服务名称和说明。 |
| `android/src/main/kotlin/com/kelivo/phoneagent/PhoneAgentPlugin.kt` | `FlutterPlugin` 注册和通道生命周期。 |
| `PhoneAgentService.kt` | 服务连接、串行 worker、锁屏/断连、请求分发。 |
| `ObservationRegistry.kt` | 树句柄、截图坐标观测、TTL 和失效管理。 |
| `NodeTreeReader.kt` | 有界 DFS、过滤、分页、密码文本隐藏。 |
| `NodeActionExecutor.kt` | 节点输入、坐标手势、系统导航和结果回调。 |
| `ScreenshotCapture.kt` | API 30+ 截图、缩放、密码区域遮挡、限频和错误映射。 |
| `PhoneAgentJson.kt` | 通道结果和错误构造。 |

插件状态 API 至少返回 `supported`、`enabled`、`connected` 和 `sdk`（`androidSdkInt`）四个字段，供 Mods 页显示；页面用 `enabled && connected` 派生 ready。`PhoneAgentAvailability.supported` 只表示 Android API 30+ 截图能力，不表示 Phone Agent 或平台是否可用。插件只读取状态和打开系统无障碍设置，不自动授权、不自动切换服务。

为与设备已安装的 Kelivo 并存，Mod 额外通过 `patches/application-id.patch` 修改 `android/app/build.gradle.kts` 和宿主 Manifest，使用包名 `com.psyche.kelivo.phoneagent`、启动名称 `Kelivo Agent`。

除新增 Mods 入口、本地工具开关互斥和 ARB 键外，不修改：

- `MainActivity.kt`、`KelivoApplication.kt`；
- `PhoneControlService.kt`、`DeviceLocalToolsHandler.kt`；
- `local_tools_service.dart` 的原生工具定义和 `LocalToolNames.all`。

## 6. 工具契约

### 6.1 工具列表

首版提供三个工具：

1. `phone_agent_screenshot`：截取当前画面，返回图片、图片尺寸、物理屏幕尺寸和前台包名。
2. `phone_agent_tree`：按需读取节点，支持分页和 `interactive_only`。
3. `phone_agent_input`：执行基础输入。

所有 schema 和结果均不出现 `snapshot_id`，均设置 `additionalProperties: false`。

`phone_agent_input` 首版动作：

- 节点：`tap`、`long_press`、`set_text`、`scroll`；
- 坐标：`tap`、`long_press`、`swipe`；
- 系统：`back`、`home`、`recents`。

### 6.2 激活、过滤与执行前重查

`PhoneAgentMod` 仅在以下条件同时满足时激活：

- 平台为 Android；
- 当前模型支持工具调用；
- 当前助手的 `localToolIds` 包含 `phone_agent`。

激活时：

- 从工具定义中移除原生 `phone_control`；
- 移除任何重复的 `phone_agent_*` 定义，避免与上游或其他 Mod 重复暴露；
- 添加本 Mod 的三个工具定义。

每次执行 Mod 工具前，重读当前助手的 `phone_agent`；撤销后返回 `phone_agent_disabled`。助手不存在或读取失败时按未启用处理，同样返回 `phone_agent_disabled`。未激活时完全保留上游定义，原生 `phone_control` 按上游行为工作。

`phone_agent` 不加入 `LocalToolNames.all`，因此上游不会为它生成原生定义、标签或开关。Mods 页是它的正常选择入口。

### 6.3 非视觉模型降级

- 不支持工具调用时，不添加任何 Mod 工具。
- 支持工具但不支持图片输入时，不暴露 `phone_agent_screenshot`。
- 非视觉模型只使用树和节点输入，不提供依赖截图的坐标输入。
- 若仍误调截图，返回结构化文本错误，不生成空图或无意义占位。

### 6.4 坐标约定

- 所有模型坐标均为 `[0, 1]` 的归一化值，原点为截图左上角。
- 模型不需要计算截图像素、物理像素或缩放比。
- 原生根据当前显示尺寸换算坐标。
- 坐标动作必须存在最近一次截图，否则返回 `screenshot_required`。
- API 29 无法截图，因此坐标动作不可用；树和节点输入仍可用。
- 截图与输入之间发生包名、窗口、尺寸或旋转变化时返回 `stale_observation`，不静默重试。
- 坐标手势不比较整棵树内容，以适应动态画面；模型被要求在不确定时重新截图。

### 6.5 节点句柄生命周期

- `phone_agent_tree(offset: 0)` 创建一份新观测并重新编号，旧句柄失效。
- `offset > 0` 只继续当前观测分页，不重新遍历或编号。
- 截图使用独立状态，不清空树句柄。
- 句柄和观测 ID 仅存在原生内存，模型只看到 `n0`、`n1` 等短 ID。
- 默认 TTL 为 120 秒，超时、服务断开、窗口/包名/尺寸/旋转变化都会失效。
- 动作后不一刀切清空全部句柄；每次节点动作前执行目标 `refresh()`、可见性、可用性和指纹校验。
- 目标失效时返回 `stale_handle`，要求重新读树；不自动点击重新解析出的相似节点。
- 新读取、输入失败和系统错误都不得把旧句柄误指向另一个节点。

#### 6.5.1 指纹重验契约

指纹用于判断“句柄是否仍指向同一个逻辑节点”，不用于判断节点当前是否处于某个交互状态。当前契约：

| 字段 | 是否进入指纹 | 说明 |
|---|---|---|
| `windowId`、`packageName`、`className`、`viewId` | 是 | 节点身份与归属变化必须失效。 |
| `text`、`contentDescription`、`hintText`、`stateDescription` | 是（密码节点除外） | 内容变化视为目标变化。 |
| `isEnabled`、`isPassword`、`isEditable`、`isClickable`、`isLongClickable`、`isScrollable`、`isCheckable`、`isChecked` | 是 | 稳定能力或语义状态变化视为目标变化。 |
| `isSelected` | 是 | 选中状态变化仍返回 `stale_handle`；本轮不一次性放宽全部指纹字段。 |
| `isFocused` | 否 | 点击、聚焦和输入本身会改变焦点；同一已刷新节点的焦点变化不构成节点替换。 |
| `actions` | 否 | 聚焦等交互会增减动作集合；动作可用性由执行层在动作前按当前节点重新校验，不可用返回 `action_unavailable`。 |
| `bounds` | 否 | 允许布局漂移，坐标仍由模型按需重新截图或读树确认。 |

规则：

- 焦点或动作集合变化不失效只表示句柄仍可用，不表示动作成功；`performAction` 返回值仍只表示系统接受动作。
- 节点被真正替换、内容变化、稳定能力字段变化、`isSelected` 变化、窗口/包名/尺寸/旋转变化和 120 秒 TTL 超时仍返回 `stale_handle` 或 `stale_observation`。
- `stale_handle` 的错误信息会附带发生变化的指纹字段名（只含固定字段名，不含文本内容）；指纹是结构化字段列表，值只参与相等比较，不会被反解为字段名。
- 该决定由 `ObservationRegistryTest` 的 focus-only 复用、action-only 复用、selected-only 拒绝和稳定能力变化拒绝用例固定；放宽更多字段必须先更新本节、`AGENTS.md` 和 `mods/phone_agent/README.md`，并补对应测试。
- 该契约不保证节点始终有效，也不保证业务结果成功；模型仍应在页面明显变化时重新读树。

该策略允许模型在同一页执行多个相互独立的操作，但是否需要重新观察由任务语义决定。它不保证节点始终有效，也不保证业务结果成功。

### 6.6 错误码

`phone_control_disabled` 已不再使用，统一改为 `phone_agent_disabled`。首版文档明确使用的错误码包括：

- `phone_agent_disabled`：当前助手已不再启用 `phone_agent`；
- `screenshot_required`：坐标动作缺少最近一次截图；
- `stale_observation`：截图与输入之间窗口、包名、尺寸或旋转变化；
- `stale_handle`：节点句柄失效或无法重验；
- `rate_limited`：系统截图或手势限频；
- `screenshot_blocked`：secure window 等截图失败；
- `image_input_unsupported`：当前模型不支持图片输入；
- `unsupported_platform`：非 Android 平台；
- `timeout`：通道或原生调用超时；
- `plugin_unavailable`：插件不可用；
- `package_not_allowed`：目标包名不在测试白名单；
- `system_window_denied`：系统窗口、权限弹窗或锁屏窗口被拒绝；
- `device_locked`：设备锁屏或息屏；
- `budget_exceeded`：本次生成的动作预算超限。

其余错误码以适配层和插件返回为准。错误信息应给出可执行的下一步，例如重新截图、重新读树、在 Mods 页重新选择工具或请用户检查无障碍服务。

## 7. 截图、隐私与技术护栏

### 7.1 截图与隐私

- 仅支持 Android API 30+ 的 `AccessibilityService.takeScreenshot`。
- API 29 截图返回 `unsupported_os`，不影响树和节点输入；页面在 `supported=false` 时显示截图限制。
- 服务 XML 必须声明 `android:canTakeScreenshot="true"`。
- 原生先缩放到长边不超过 1600，再传给 Dart，降低通道和图片上下文成本。
- Dart 使用 `McpImageSnapshot.saveBytes` 落盘，并校验落盘尺寸与原生声明一致；不一致则返回错误，不更新坐标观测。
- 系统限频映射为 `rate_limited`，secure window 等失败映射为 `screenshot_blocked`，不发送黑图。
- `isPassword` 节点及其子树文本不进入树结果；直接节点输入默认拒绝密码节点。
- 截图前按密码节点 bounds 涂黑。该遮挡依赖应用正确标记，自定义 View/WebView 可能遗漏，只能称为“尽力而为”。
- 截图字节和密码文本不得写入日志或崩溃报告。

### 7.2 首版必须实现的技术护栏

- 单 worker 串行执行和手势单飞；
- 每次调用及实际执行前的锁屏/息屏检查；
- 服务中断时完成所有 pending 请求，不再执行排队动作；
- 节点、窗口、包名、尺寸、旋转和时效校验；
- 有界节点遍历、分页和文本预算；
- 截图、读树、手势和通道调用超时；
- 每次生成过程中的动作预算和速率限制；
- 默认仅允许显式配置的测试包名，当前为独立测试应用 `com.psyche.kelivo.phoneagent`；开发者只能在私有 Mod 中编辑白名单；
- 拒绝系统窗口、权限弹窗和锁屏窗口；
- 结构化错误包含可执行的下一步，而非只返回笼统失败。

### 7.3 工具选择与服务授权边界

- Mods 页的三态选择是工具配置，不是无障碍授权。选择 Phone Agent 不会自动启用 `PhoneAgentService`，选择原生手机控制也不会自动启用 `PhoneControlService`。
- 两个服务继续共存，各自在系统无障碍设置中独立授权；Mod 不自动打开系统开关、不静默提权、不绕过系统确认。
- 服务状态面板只读取状态，不修改系统设置；刷新失败或状态过期时，以系统设置和工具返回的结构化错误为准。
- 用户关闭工具选择不会自动关闭系统服务；用户停用系统服务也不会自动改写助手工具选择。
- 上游手机控制授权页继续由上游维护；Mod 不把 Phone Agent 的授权伪装成上游授权。

### 7.4 不属于硬保证的事项

- `performAction` 或手势回调代表业务成功；
- 密码遮挡覆盖所有应用；
- 节点校验消除所有竞态；
- 模型会遵守“发送/购买/删除前询问”的提示；
- 白名单应用内部不会发生危险操作；
- 已经发出的系统调用可以撤回；
- 两个服务同时启用时不会产生任何系统级干扰。

真正需要逐步授权时，应后续增加“每个动作均由原生确认”的模式，而不是依赖危险文本识别。

## 8. 分阶段实施

### 阶段 P1：只读闭环

1. 建立独立插件、服务和通道。
2. 实现服务状态、读树、分页、密码文本隐藏。
3. 实现 API 30+ 截图、缩放、密码区域遮挡和错误映射。
4. 实现 Kelivo 适配层、视觉能力门控和图片落盘。
5. 完成 Dart/Kotlin 单元测试和只读真机测试。

完成条件：真机能通过工具看到截图和树，历史轮次能按现有机制回放图片，非视觉模型不会收到图片。

### 阶段 P2：基础输入与端到端流程

1. 实现节点句柄注册、TTL 和目标重验。
2. 实现归一化坐标观测和输入。
3. 实现 `tap`、`long_press`、`set_text`、`scroll`、`swipe` 和系统返回。
4. 完成真实调用集成测试，而非只验证 import 或编译。

完成条件：在无账号测试界面完成“截图/读树 → 点击 → 输入 → 滑动 → 再观察并确认结果”。

### 阶段 P3：技术护栏与异常路径

1. 实现锁屏、断连、超时、预算、测试包白名单和系统窗口拦截。
2. 验证旋转、切窗、服务中断、截图限频和 secure window 错误。
3. 检查日志、图片落盘和历史回放中的隐私行为。
4. 运行上游手机控制回归测试。

完成条件：所有技术护栏均有自动化测试，异常路径不会挂起工具循环或误用旧目标。

### 阶段 P4：VLM 验证与中文维护文档

1. 使用同时支持工具调用和图片输入的已配置模型执行固定安全任务。
2. 验证模型不需要 `snapshot_id`，可在同一页复用有效句柄。
3. 验证原生 `phone_control` 不会与 Mod 工具同时暴露。
4. 使用 Loader 的 `rebase-drill` 检查新基线，并处理 vendored 漂移提醒。
5. 完善中文 README：选择、授权、白名单、限制、更新和故障排查。

完成条件：所有可用环境中的 Phone Agent 验收项通过；无法执行的硬件/模型项目明确记录为未验证。

### 阶段 P5：UI 与选择契约改造（已完成）

1. 新增独立 `phone_agent` localToolId 和三态选择状态；不加入 `LocalToolNames.all`。
2. 新增移动和桌面 Mods 设置入口，宽窄屏共用简单页面，不接设置搜索。
3. 实现三态互斥写入：关闭移除两者；原生保留 `phone_control`、移除 `phone_agent` 并继续走上游授权页；Phone Agent 写入 `phone_agent`、移除 `phone_control`。
4. 已有仅启用 `phone_control` 的助手保持原生，不自动迁移。
5. 实现服务状态面板：supported、enabled、connected、sdk 和由 `enabled && connected` 派生的 ready，以及刷新、打开无障碍设置、能力/隐私说明；API 29 显示截图限制但允许 ready。
6. 产品文案进入 ARB，补齐英文描述，运行 `translate.py sync` 和 `check`，同步所有目标语言和生成文件；标准 sync 已由本机免费 llama-cpp 完成，四目标语言 0 pending，`l10n-generated.patch` 已生成。
7. `PhoneAgentMod` 激活时过滤原生 `phone_control` 和重复 `phone_agent_*`；执行前重查 `phone_agent`；错误码改为 `phone_agent_disabled`。
8. 更新 `mod.json`、`local-tool-mutual-exclusion.patch`、`settings-entry.patch`、`l10n-source.patch`、`l10n-generated.patch`、overlay、测试和文档。

完成条件：三态选择、冲突处理、旧助手保持原生、服务状态、入口、ARB 和执行前重查均有自动化测试；最终 Flutter 255（254 通过 + 1 Windows 条件跳过）、插件 Dart 17、插件 Kotlin 55、上游 PhoneControl 49、Loader 165 通过；真机官方测试退出码 0；Loader verify 通过。仍不宣称第二阶段全部完成，未验证项见 10.2。

## 9. 测试与验收

### 9.1 Kelivo 与 Mod Dart 测试

在合成 worktree 中：

```bash
flutter pub get
flutter pub get --directory tool/l10n --enforce-lockfile
dart format --output=none --set-exit-if-changed \
  lib/features/phone_agent lib/features/mods test/features/phone_agent \
  test/features/mods test/features/settings/pages/mods_settings_entry_test.dart
dart analyze --fatal-infos lib test integration_test tool
flutter test test/features/phone_agent
flutter test test/features/mods
flutter test test/features/settings/pages/mods_settings_entry_test.dart
flutter test test/features/home/services/phone_control_test.dart
flutter test test/features/home/services/tool_handler_service_test.dart
flutter test test/features/home/services/tool_handler_workspace_gating_test.dart
flutter test test/core/services/api/tool_result_content_test.dart
flutter test test/core/services/mcp/mcp_image_snapshot_test.dart
flutter test test/utils/mcp_structured_image_test.dart
flutter test test/core/services/api/request_image_context_test.dart
flutter test test/request_consistency_test.dart
```

ARB 同步与检查：

```bash
python3 tool/l10n/translate.py sync
python3 tool/l10n/translate.py check
flutter gen-l10n
```

标准 sync 已由本机免费 Magpie llama-cpp/llama-cpp 完成：23 个键已翻译，`translate.py check` 四个目标语言（ko、ru、tr、zh_Hant）均 0 pending，`l10n-generated.patch` 已生成；未使用付费服务。Magpie Python UA 适配只是临时进程环境，不属于 Mod 交付，文档不记录其临时路径作为依赖。

同时执行项目要求的 markstream 检查：

```bash
cd dependencies/markstream
flutter pub get
dart analyze --fatal-infos
```

新增适配测试至少覆盖：

- Android、助手 `phone_agent` 开关、工具能力和视觉能力门控；
- 激活时过滤原生 `phone_control`，未激活时恢复；
- 激活时过滤重复 `phone_agent_*` 定义，不重复暴露；
- 生成途中撤销 `phone_agent` 后返回 `phone_agent_disabled`；
- 未识别工具名和 `toolCallId` 原样透传；
- 三个 schema 不含 `snapshot_id`；
- 非视觉模型没有截图定义和坐标输入能力；
- 截图元数据、实际尺寸、尺寸不一致失败；
- 错误信封、超时、服务断开和插件异常不终止聊天；
- 不调用 `app.device_tools`。

本轮 UI/选择契约新增测试至少覆盖：

- 三态单选互斥：关闭、原生、Phone Agent 写入后不会同时保留两个 ID；
- 选择原生时移除 `phone_agent` 并进入上游授权页；
- 选择 Phone Agent 时移除 `phone_control`，且不自动打开系统无障碍设置；
- 选择关闭时移除两者，且不自动关闭系统服务；
- 仅启用 `phone_control` 的助手显示为原生，打开 Mods 页不自动改写；
- 两个 ID 同时存在时显示冲突并要求选择；
- 服务状态 supported/enabled/connected/sdk 的加载、刷新和失败态；API 29 上 `supported=false` 但 `enabled && connected` 时 ready=true，树/节点输入可用，截图返回 `unsupported_os`；
- 打开无障碍设置失败时的提示；
- 移动和桌面入口都能打开同一个页面；
- 设置搜索索引不包含 Mods 页；
- ARB 键在英文和中文源文件中成对存在，描述完整；`translate.py check` 四目标语言 0 pending；`l10n-generated.patch` 已生成；
- 非 Android 平台显示平台不支持且不添加工具，不要用 `supported=false` 表示平台不支持。

### 9.2 Android 测试

先通过 `./gradlew projects` 确认插件模块名，再运行对应模块测试，不预先硬编码可能错误的 Gradle 路径。

测试覆盖：

- DFS、分页、字符上限、不可见节点和密码子树；
- 句柄重新编号、TTL、窗口变化和指纹变化；
- 同一已刷新节点仅 `isFocused` 变化（false→true 与 true→false）时句柄仍可复用并完成 `set_text`；
- 仅动作集合 `actions` 变化时句柄仍可复用，动作可用性由执行层按当前节点校验；
- 仅 `isSelected` 变化时仍返回 `stale_handle`，稳定能力字段（如 `isScrollable`）变化也仍返回 `stale_handle`，证明本轮没有一次性放宽全部指纹字段；
- 含 NUL 的文本变化只报告 `text` 字段名，`stale_handle` 不包含 NUL 后的内容；
- `performNodeAction` 在请求动作从当前节点移除后返回 `action_unavailable`，且不执行 `beforeAction` 或 `perform`；
- 动作后有效句柄可复用，失效句柄不会重定向；
- 归一化坐标、越界、NaN、旋转和尺寸变化；
- 节点动作、系统导航、手势回调和并发 `busy`；
- 截图缩放、密码区域遮挡、限频和 secure window 错误；
- 锁屏/息屏、服务中断和 pending 请求完成；
- 白名单与系统窗口拒绝；
- 独立服务状态 supported/enabled/connected/sdk 的通道返回；API 29 上截图能力为 false，但 ready 状态与树/节点输入仍可用。

同时运行上游既有测试：

```bash
cd android
./gradlew :app:testDebugUnitTest --tests com.psyche.kelivo.PhoneControlServiceTest
```

### 9.3 构建与真机

```bash
flutter build apk --debug
flutter test integration_test/phone_agent_test.dart -d <android-device-id>
```

真机前置：

- Android 设备；截图与坐标手势需要 API 30 或更高；API 29 服务可 ready 并验证读树和节点输入，截图返回 `unsupported_os`，页面显示截图限制；
- 测试设备已解锁；
- 在 Mods 页为测试助手选择 Phone Agent；
- 在系统无障碍设置中启用独立的 Phone Agent 服务；
- 只使用无账号测试界面和显式测试包名；
- 默认关闭后台悬浮胶囊。

最终真机结果（官方测试退出码 0）：

1. 设置 → Mods → 真实 enabled/connected/API 29 状态 → 助手选择 Phone Agent 且与原生互斥。
2. 读树、节点点击、`set_text`、节点滚动、二次读树；截图按预期返回 `unsupported_os`。

本轮节点重验修正后的设备结果：

- API 35 模拟器（`emulator-5554`，Android 15；`flutter test --no-uninstall integration_test/phone_agent_test.dart -d emulator-5554`，退出码 0，2 个用例通过）：
  1. 真实截图（图片与屏幕尺寸有效）→ 读树 → 节点点击（回调计数 1）→ 坐标滑动（原生接受并完成手势）→ 节点滚动（`scrollController.offset > 0`，列表真实滚动）→ 聚焦输入框 → 同一观测句柄 `set_text` 成功并写入文本 → 二次读树返回节点。
  2. Mods 页真实服务状态与 Phone Agent 三态选择通过。
- API 29 真机（`357784090209204`，Android 10；`flutter test --no-uninstall integration_test/phone_agent_test.dart -d 357784090209204`，退出码 0，2 个用例通过）：
  1. 截图按预期返回 `unsupported_os` → 读树 → 节点点击（回调计数 1）→ 节点滚动（`scrollController.offset > 0`，列表真实滚动）→ 聚焦输入框 → 同一观测句柄 `set_text` 成功并写入文本 → 二次读树返回节点。
  2. Mods 页真实服务状态与 Phone Agent 三态选择通过。

集成测试的坐标手势验证边界：

- `flutter_test` 的 `LiveTestWidgetsFlutterBinding` 默认 `shouldPropagateDevicePointerEvents = false`，设备指针事件只进入诊断 dispatcher，不转发给 widget 树；绑定还会断言测试不得修改该开关。
- 因此集成测试只能验证坐标手势被原生接受并完成（`onGestureCompleted`），不能断言应用侧的滚动效果；API 35 用例在坐标滑动之后再用无障碍节点滚动验证列表真的滚动。该限制只影响测试可观测性，不改变产品行为。
- 安装测试包和部分收尾的 force-stop 可能清除系统无障碍授权；测试会打印 `PHONE_AGENT_WAITING_FOR_SERVICE` 并等待约 300 秒，需要在窗口内通过系统界面重新启用 Kelivo Phone Agent，并每轮检查真实绑定状态。

仍待验证：

- 物理 API 30+ 真机上的截图与坐标手势（API 35 模拟器已验证截图、坐标手势原生接受和节点滚动；坐标手势的 UI 效果受测试绑定限制）。
- VLM 固定任务和 VLM 图片链路。
- 真实 `FLAG_SECURE` 窗口。
- 真机旋转、切窗、锁屏、禁用服务、超时等其他异常路径。
- 带合法签名配置的 release 构建。

因此不宣称 Phone Agent 第二阶段全部完成；未验证项不能用编译或单元测试代替真机结论。

## 10. Phone Agent 完成定义与已知限制

### 10.1 完成定义

只有满足以下条件，才能宣称 Phone Agent 第二阶段完成：

- Mod Loader 第一阶段已验收，且本 Mod 能确定性合成。
- 独立 `phone_agent` localToolId、Mods 三态选择、移动/桌面入口和服务状态页已实现。
- 服务状态面板区分 `supported`（仅 API 30+ 截图能力）与 ready（`enabled && connected`）；API 29 可 ready 并使用树/节点输入，截图返回 `unsupported_os`，页面显示截图限制。
- 正常 UI 不会同时启用原生手机控制和 Phone Agent；已有仅启用 `phone_control` 的助手保持原生。
- `PhoneAgentMod` 激活时过滤原生 `phone_control` 和重复 `phone_agent_*`，执行前重查 `phone_agent`，撤销后返回 `phone_agent_disabled`。
- 两个 `AccessibilityService` 共存，Mod 不自动授权、不自动切换系统无障碍开关。
- 产品文案进入 ARB，英文描述完整，所有目标语言同步；本机免费 llama-cpp 翻译 23 键，`translate.py check` 四目标语言 0 pending，`l10n-generated.patch` 已生成。
- Kelivo 适配层、插件 Dart 和 Android 相关检查通过。
- debug APK 构建成功，Manifest 合并正确。
- 真机基础输入闭环通过；真机官方测试退出码 0。
- VLM 固定任务通过，或明确记录缺少模型/设备而未验证。
- 最终 Flutter 255（254 通过 + 1 Windows 条件跳过；Phone Agent 103、Mods 16、settings 入口 2）、插件 Dart 17、插件 Kotlin 55、上游 PhoneControl 49、Loader 165 通过；根项目、markstream 和插件静态分析通过。
- Loader verify 通过；最终 APK 已生成。
- 中文维护文档与真实行为一致。

最终验收已完成；仍不宣称第二阶段全部完成，未验证项见 10.2。

### 10.2 已知限制

- 独立服务参考上游实现，需要 vendored 哈希和人工审查来避免安全修复分叉。
- Mods 页的选择是工具配置，不是无障碍授权；服务状态可能滞后于系统设置。
- 两个无障碍服务可以同时存在于系统中；正常 UI 只限制助手工具选择，不限制系统级服务开关。
- 已有仅启用 `phone_control` 的助手不会自动迁移，用户需要在 Mods 页手动选择 Phone Agent。
- 后台悬浮胶囊不在首版处理。
- Mod 工具不进入上游 schema override 和通用审批流程，自己的助手工具选择和限制必须自行执行。
- 截图密码遮挡、节点校验和窗口检查只能降低风险，不能提供绝对安全保证。
- 自动模式不承诺识别或阻止所有发消息、购买、删除等不可逆行为。
- 设置搜索不包含 Mods 页；用户需要从移动或桌面设置入口进入。
- 不进入上游工具目录或内置工具商店；Phone Agent 的助手级选择只在 Mods 页完成。
- `supported` 仅表示 API 30+ 截图能力；API 29 可以 ready 并使用树/节点输入，但截图返回 `unsupported_os`，页面显示截图限制。
- 非 Android 平台可以打开 Mods 页，但只显示平台不支持；不要用 `supported=false` 表示平台不可用。
- ARB 翻译质量依赖上游 l10n 工具和目标语言审查；新增键必须保持英文和中文源键集合一致。
- API 30+ 截图与坐标手势已在 API 35 模拟器验证；坐标手势的 UI 滚动效果受 integration_test 绑定限制（不转发设备指针事件），未在物理 API 30+ 真机验证。
- VLM 固定任务和 VLM 图片链路未验证。
- 真实 `FLAG_SECURE` 窗口未验证。
- 真机旋转、切窗、锁屏、禁用服务、超时等其他异常路径未验证。
- 未执行带合法签名配置的 release 构建。
- 因此不宣称 Phone Agent 第二阶段全部完成。
- Loader 更新演练通过不代表 Phone Agent 真机行为无需重新验证。
