# Kelivo Phone Agent Mod 实施计划

## 0. 文档状态

- 当前阶段：第二阶段验收进行中（UI/选择契约改造已完成），Mod 版本 0.2.0。
- 当前 M22（权限弹窗保守收尾，2026-11-12）：用户明确同意“不可识别权限弹窗仍返回 `no_window`，消息条件式提示人工处理/取消并返回测试应用”。M20（窗口 root 补全）与 M21（事件来源包名）均已在 API35 设备上证伪并 abandoned，未合并生产代码；本轮整合其准确证据，只把 `PhoneAgentService` 三处无可访问窗口的英文提示改为条件式人工提示，错误码、guard、读树/截图密码遮挡、输入边界和白名单均不变。异常测试改为宿主 `dumpsys` 独立确认真实 `GrantPermissionsActivity` 后直接 tap/back/截图断言 `no_window` + 提示，不再因 `root=null` skip，也不把任意 `no_window` 当通过。设备结果与新树/APK 记录见 9.3.6。
- 上一轮 M21（权限弹窗事件来源评估，abandoned）：按 mission 先做临时事件诊断，不改生产代码。API35 真实 `GrantPermissionsActivity` 弹窗期间，服务已连接并持续收到应用和 systemui 事件，但没有收到任何 `permissioncontroller` 的 `TYPE_WINDOW_STATE_CHANGED`；只有 `pkg=null` 的 `TYPE_WINDOWS_CHANGED`（窗口 id 指向无 root 的弹窗）和后台 systemui 事件。活动/聚焦弹窗窗口仍没有可访问 root，无法取得包名，因此事件来源包名无法与活动/聚焦窗口 id 建立可靠匹配，该机制不可用。按 mission 停止条件停止，未提交生产代码或测试改动；临时诊断已从交付移除，证据见 9.3.5。
- 上一轮 M20（权限窗口输入路径诊断，abandoned）：只做设备诊断，不改生产代码。API35 真实 `GrantPermissionsActivity` 弹窗期间服务 `rootInActiveWindow` 为 null；临时诊断（已移除，不进交付）实测 `windows` 只有两个窗口：`com.android.systemui` 窗口 `active=false focused=false hasRoot=true`，权限弹窗窗口 `active=true focused=true hasRoot=false pkg=null`。活动/聚焦窗口没有可访问 root，无法取得包名；唯一有 root 的是后台 systemui 窗口。因此「用可确认的活动/聚焦系统窗口补全 WindowState 以返回 `system_window_denied`」在本设备不可实现；证据见 9.3.4。
- 上一轮 M19（权限窗口真实验证）：只改中文文档与 debug 异常测试，不改产品代码、schema、白名单或上游。已查明上一轮 API35 权限弹窗 90 秒未出现的原因是设备息屏（`mWakefulness=Asleep` 时 `am start` 不获前台焦点，唤醒后立即出现）；真实 `com.google.android.permissioncontroller` 弹窗已出现，但服务 `rootInActiveWindow` 为 null，**读树实测返回 `no_window`**；输入按 `currentWindow` 前置 guard 推导为 `no_window`（M19 未执行 tap/back，属代码路径推导），`system_window_denied` 未产生，输入仍被拒绝、权限未授予。最终合成树 `V:/coding/kelivo-private/.tower/worktrees/wt-19/.build/worktrees/75429900bf8fc452`，`modsetHash` `75429900bf8fc4526fb7005729da565f210eab3d9de922d94039e6399f808d11`，`verify` 通过；完整异常套件 `+5 ~1`、`All tests passed!`、EXIT=0。历史结果见 9.3.3。
- 上一轮 M17（节点重验诊断）：`stale_handle` 错误码不变；`ObservationRegistry` 把 `refresh()`、可见性和可用性前置失败拆成固定诊断标识 `refresh_failed`、`not_visible`、`not_enabled`，按该顺序短路判断，消息不含节点文本、类名、viewId 或其他内容，不改变任何通过条件、指纹字段或 TTL/窗口校验。契约见 6.5.1，设备诊断结果见 9.3.2。
- 上一轮修正（节点重验，历史）：`PhoneNode.fingerprint()` 不再包含 `isFocused` 和动作集合 `actions`；同一已刷新节点因点击/输入产生的焦点变化和动作增减不再让后续 `set_text` 返回 `stale_handle`；`isSelected`、内容、稳定能力字段、窗口/包名/尺寸/旋转和 120 秒 TTL 校验保持不变。指纹为结构化字段列表，`stale_handle` 只附带固定字段名，不从节点内容反解字段名。契约见 6.5.1。
- 上一轮 M16（物理 MIUI API31 验收记录，历史）：该轮只改中文文档，产品代码/测试/`mod.json`/schema/白名单/上游均未修改。最终源码 `modsetHash` `3d3cd25b4def35633dcf848373037cbe2c5200f795339c315b3ac9c3268a3174`，合成树 `V:/coding/kelivo-private/.tower/worktrees/wt-16/.build/worktrees/3d3cd25b4def3563`，`plan`/`apply`/`verify` 通过；该轮产品 debug APK 为 181,369,890 字节，SHA-256 `c6f20d250239bae223a4fdaa5ff1807ba34eab38bd8f9e7f9710e8c21747a58b`。设备证据来自此前相同代码/测试行为，未在新树重跑设备。结果见 9.3.2 与 9.4.2。
- 上一轮 M10（API35 FLAG_SECURE/异常路径）：最终源码 `modsetHash` `5b1cde0304e687b9e3a26935cf85b5a27d102c9ecb409ff0e8b1358075aa902d`，合成树 `V:/coding/kelivo-private/.tower/worktrees/wt-10/.build/worktrees/5b1cde0304e687b9`；完整异常套件实际运行于 `2c1513ecef3f2293` 树，`+5 ~1`、EXIT=0；当前 `5b1cde...` 是仅文档哈希变化后的最终源码/构建树，关键代码/测试一致，新树未重跑设备；权限窗口未验证；API35/API29 官方测试各 2 项通过。契约和结果见 9.3.1。
- 上一轮 magpie VLM 验收（历史，API35 模拟器）：使用当时的 debug APK 和 magpie 网关模型 `llama-cpp/llama-cpp`（provider `http://10.0.2.2:3425/v1`，UI Image + Tools；局域网访问由用户开启，未读取或记录密钥）完成真实图片链路、Kelivo 应用内固定任务和跨新用户轮次历史图片回放。证据见 9.4。该轮的合成树 `5f0be65f...` 和 APK 181369230 字节是历史记录，不代表当前实现。
- 当前产品 debug APK（在 M17 最终合成树 `V:/coding/kelivo-private/.tower/worktrees/wt-17/.build/worktrees/1c1920e0e2b8bc7c` 显式 `flutter build apk --debug` 生成）：**181,373,530 字节**，SHA-256 `dc32c4a30533c4195f0392f5533a316bbf096177b653f0623c78645d5f116026`；debug merged manifest 含 `SecureWindowFixtureActivity`。设备测试树 `8fe847...` 的 clean APK 为 181,373,066 字节 / `d7138f06...`，仅作设备证据；两树代码/测试一致，仅 `plugin/README.md` 文档副本不同。测试后仅增量构建曾复用约 249 MB 测试入口 APK，已用 clean 构建排除；release merged manifest 不含该夹具（不宣称签名 release）。
- 当前 M17 自动检查：最终合成树 `V:/coding/kelivo-private/.tower/worktrees/wt-17/.build/worktrees/1c1920e0e2b8bc7c`，`modsetHash` `1c1920e0e2b8bc7c397b02e2e908e59d27f979a5ddee3b263da348aa3c1ceaf3`，`plan`/`apply`/`verify` 通过；该树相对设备测试树 `V:/coding/kelivo-private/.tower/worktrees/wt-17/.build/worktrees/8fe847cedc2ea513` 仅 `plugin/README.md` 文档副本不同，代码/测试一致。Loader 165、插件 Kotlin 66（含 refresh/visible/enabled 三项前置诊断）、插件 Dart 17、根项目 `dart analyze --fatal-infos lib test integration_test tool`、Flutter 182 通过。根分析前必须先运行 `flutter pub get --directory tool/l10n --enforce-lockfile`，否则 `tool/l10n/validate.dart` 会因缺 `flutter_tools` 包解析报 15 个既有错误；这不是本 Mod 改动。
- 上一轮自动检查（历史）：Loader 165、Phone Agent 105、Mods 16、settings 入口 2、上游 `tool_result_content` 回归、插件 Dart 17、插件 Kotlin 66 和上游 PhoneControl 49；M10 历史轮只改测试/文档，未重复这些静态套件，新增聚焦工具测试 32 项通过。
- 上一轮节点重验合成树（历史）：`V:/coding/kelivo-private/.tower/worktrees/wt-1/.build/worktrees/7593c21b5f9da01f`，`modsetHash` 为 `7593c21b5f9da01fb8b8c4dfe167d892a940efe4a1caf591b772fbe83b6b6f7d`；当时 Phone Agent 103、Mods 16、settings 入口 2、插件 Dart 17、插件 Kotlin 66、上游 PhoneControl 49 通过。
- 本地化：23 个键已由本机免费 Magpie llama-cpp 翻译，`translate.py check` 四个目标语言（ko、ru、tr、zh_Hant）均 0 pending；本轮无 UI/ARB 改动，未重跑翻译生成。
- 上一轮设备回归（历史）：API 35 模拟器与 API 29 真机官方集成测试均退出码 0，逐项结果见 9.3；该结果对应提交 `698cace` 的运行时语义。之后仅调整诊断编码、提取纯 JVM 前置校验接缝、补测试和文档，未重复双 API 设备回归（按 R1 审查意见）。
- 历史验收记录（焦点修正前，不代表当前实现）：最终合成树 `V:/coding/kelivo-private/.build/worktrees/4ed083cf5fe7dda8`，`modsetHash` 为 `4ed083cf5fe7dda8eec575588594831d9515cbd88429cb6f5b893c9ca6544331`；Flutter 255 项（254 通过 + 1 Windows 条件跳过）；插件 Kotlin 55；旧产品 APK 181354638 字节，SHA-256 `af67f4285bef9e3d1093c6433f42669a8c84b8bee99b6397f68dfd91e1c60ceb`；当时的未验证项包含 API 30+ 截图与坐标手势。
- 仍明确未验证：权限窗口、签名 release、原生超时、`stale_handle` 根因；物理 MIUI API31 未运行锁屏、home/recents、服务中断，不能从 API35 模拟器结果推断；`llama-cpp/llama-cpp` 的物理完整坐标 swipe 未完成。API35 模拟器已验证 secure 截图行为、旋转、home/recents、锁屏、服务禁用/重启；物理 MIUI API31 已验证真实截图/读树/节点输入/滚动、物理 `FLAG_SECURE` 与旋转；跨新用户轮次历史图片回放已在 API35 模拟器通过，物理 MIUI 的真实图片请求与像素专属视觉确认见 9.4.2。以上只验证 magpie `llama-cpp/llama-cpp`、`mistral/deepseek-v4-1-flash-1017` 与这两台设备，不承诺任意模型或设备。因此不宣称 Phone Agent 第二阶段全部完成。
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
- 前置重验失败与指纹变化使用同一错误码 `stale_handle`，但消息中的诊断标识可区分来源：`refresh()` 返回 false 时为 `refresh_failed`，刷新成功但 `isVisibleToUser` 为 false 时为 `not_visible`，前两者通过但 `isEnabled` 为 false 时为 `not_enabled`。三者按该顺序短路判断，只输出固定标识，不输出节点文本、类名、viewId 或其他内容；诊断不改变任何通过条件，也不把失败自动转成重新读树或重试。
- 该决定由 `ObservationRegistryTest` 的 focus-only 复用、action-only 复用、selected-only 拒绝、稳定能力变化拒绝和三项前置诊断用例固定；放宽更多字段必须先更新本节、`AGENTS.md` 和 `mods/phone_agent/README.md`，并补对应测试。
- 该契约不保证节点始终有效，也不保证业务结果成功；模型仍应在页面明显变化时重新读树。

该策略允许模型在同一页执行多个相互独立的操作，但是否需要重新观察由任务语义决定。它不保证节点始终有效，也不保证业务结果成功。

### 6.6 错误码

`phone_control_disabled` 已不再使用，统一改为 `phone_agent_disabled`。首版文档明确使用的错误码包括：

- `phone_agent_disabled`：当前助手已不再启用 `phone_agent`；
- `screenshot_required`：坐标动作缺少最近一次截图；
- `stale_observation`：截图与输入之间窗口、包名、尺寸或旋转变化；
- `stale_handle`：节点句柄失效或无法重验；消息中的固定诊断标识 `refresh_failed`、`not_visible`、`not_enabled` 区分前置重验失败来源，指纹变化仍报告字段名；
- `rate_limited`：系统截图或手势限频；
- `screenshot_blocked`：平台明确返回截图错误（如无无障碍截图权限、无效显示/窗口、窗口级 secure 错误等）；整屏 `takeScreenshot` 不保证对 FLAG_SECURE 报错；
- `image_input_unsupported`：当前模型不支持图片输入；
- `unsupported_platform`：非 Android 平台；
- `timeout`：通道或原生调用超时；
- `plugin_unavailable`：插件不可用；
- `package_not_allowed`：目标包名不在测试白名单；
- `system_window_denied`：系统窗口、权限弹窗或锁屏窗口被拒绝；
- `device_locked`：设备锁屏或息屏；
- `budget_exceeded`：本次生成的动作预算超限。

其余错误码以适配层和插件返回为准。错误信息应给出可执行的下一步，例如重新截图、重新读树、在 Mods 页重新选择工具或请用户检查无障碍服务。

输入路径的错误码优先级固定为：空包名 → `no_window`；系统包 → `system_window_denied`；其他非白名单包 → `package_not_allowed`；白名单内再校验句柄/截图，失效返回 `stale_handle` 或 `stale_observation`。因此系统窗口或非白名单应用在前台时，即使句柄已经失效，也先返回包名策略错误，而不是句柄错误。锁屏/息屏在包名策略之前检查，所有方法（含读树和截图）返回 `device_locked`。

权限弹窗的处理边界（M20/M21 设备证伪 + M22 保守收尾）：

- API35 真实 `GrantPermissionsActivity` 弹窗期间，`rootInActiveWindow` 为 null；活动/聚焦弹窗窗口 `hasRoot=false`、`pkg=null`，`AccessibilityWindowInfo` 没有包名字段，服务也没有收到 `permissioncontroller` 的 `TYPE_WINDOW_STATE_CHANGED`。因此窗口 root 补全和事件来源包名两种识别机制均不可用，不实现。
- 该场景读树、截图和输入统一返回 `no_window`，错误消息只做条件式人工提示（“如果看到系统权限弹窗，请人工处理/取消，再返回测试应用”），不声称识别具体权限弹窗，也不把 `no_window` 写成权限场景的通过条件。
- 可取得系统包名的系统窗口仍按 `PackagePolicy` 返回 `system_window_denied`；错误优先级、读树/截图密码遮挡、白名单和输入边界不扩大。
- 异常测试的宿主 `dumpsys` 确认是测试前提，不是产品检测能力；测试不能仅因任意 `no_window` 通过，也不能因 `root=null` skip。

`system_window_denied`、`package_not_allowed` 和 `screenshot_blocked` 的适用范围必须区分：

- `system_window_denied` / `package_not_allowed` 只约束**输入**（节点动作、坐标手势、系统动作）；读树和截图不检查包名，仍可观察当前前台窗口。
- `screenshot_blocked` 只表示平台明确返回的截图失败；整屏 `takeScreenshot` 成功返回的黑图不算 `screenshot_blocked`，也不表示读树或输入不可用。
- `device_locked` 同时约束读树、截图和输入。

整屏截图与 FLAG_SECURE 的边界（按证据层级区分）：

- 官方文档事实：`TakeScreenshotCallback.onFailure` 列出的错误码不包含 `ERROR_TAKE_SCREENSHOT_SECURE_WINDOW`；该码是 API 34+ 窗口级 `takeScreenshotOfWindow` 使用的错误。
- AOSP 补充：整屏 `takeScreenshot(Display.DEFAULT_DISPLAY)` 路径（`WindowManagerService.captureDisplay` → `ScreenCapture.captureLayers`）没有 secure 检查；失败只可能是限频、无无障碍截图权限、无效显示/窗口或内部错误。
- 设备观察（API35 模拟器）：同 UID 和不同 UID 的 `FLAG_SECURE` 夹具都返回 `ok:true` 和黑图（平均 RGB 约 2,0,2 / 3,0,5），没有 `screenshot_blocked`。因此不根据像素猜 secure，不承诺不发送黑图，正常黑色页面保留；平台明确报错时仍不得把图片或图片 metadata 交给模型。

## 7. 截图、隐私与技术护栏

### 7.1 截图与隐私

- 仅支持 Android API 30+ 的 `AccessibilityService.takeScreenshot`。
- API 29 截图返回 `unsupported_os`，不影响树和节点输入；页面在 `supported=false` 时显示截图限制。
- 服务 XML 必须声明 `android:canTakeScreenshot="true"`。
- 原生先缩放到长边不超过 1600，再传给 Dart，降低通道和图片上下文成本。
- Dart 使用 `McpImageSnapshot.saveBytes` 落盘，并校验落盘尺寸与原生声明一致；不一致则返回错误，不更新坐标观测。
- 系统限频映射为 `rate_limited`；平台明确返回的截图错误映射为 `screenshot_blocked`。整屏 `takeScreenshot` 不保证对 `FLAG_SECURE` 报错：secure 内容可能以黑色区域出现在成功截图中；不做像素启发式，不承诺不发送黑图，正常黑色页面保留。
- 平台明确报错时不得把图片或图片 metadata 交给模型；成功黑图只作为普通截图返回，模型应优先读树、不要凭黑图猜坐标。
- `FLAG_SECURE` 只阻止截图；它不会隐藏无障碍树，也不会阻止读树和输入。输入边界由包名白名单决定，不能把 secure window 描述成“不可读、不可操作”。secure 窗口的树在 API35 夹具上可读，但不是绝对保证；密码字段、自定义 View 和窗口变化仍会影响树。
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
- 输入请求拒绝可取得包名的系统窗口（`system_window_denied`）；无可访问 root 的权限弹窗保持 `no_window` 并只做条件式人工提示；锁屏/息屏时读树、截图和输入都返回 `device_locked`；读树和截图不检查包名，仍可观察当前前台窗口；
- `home`/`recents` 执行后前台会离开白名单，后续输入（包括 `back`）会被拒绝；模型无法自行把测试应用切回前台，需要用户或宿主动作恢复；
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
- 两个服务同时启用时不会产生任何系统级干扰；
- `FLAG_SECURE` 会阻止读树或输入（它只阻止截图）；
- 整屏截图会检测 `FLAG_SECURE` 或不发送黑图（可能成功返回黑图）；
- `home`/`recents` 之后模型能自行回到测试应用（前台离开白名单后输入会被拒绝）；
- 系统窗口或权限弹窗会阻止读树和截图（只有输入被拒绝）；
- 权限弹窗一定能被识别为 `system_window_denied`（API35 实测无可访问 root 且无来源包名，读树/截图/输入仍为 `no_window`，只做条件式人工提示）。

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

本轮进展：第 1-3 项已在 API 35 模拟器用 magpie `llama-cpp/llama-cpp` 完成，并补充跨新用户轮次历史图片回放（见 9.4）；第 4 项 `rebase-drill` 未在本轮执行；第 5 项中文 README 已维护。物理 MIUI API31 真机由 `llama-cpp/llama-cpp` 完成归一化坐标 tap（打开抽屉/Settings/Search），由 magpie `mistral/deepseek-v4-1-flash-1017` 完成真实图片请求、归一化坐标 swipe 的 UI 效果和像素专属视觉确认（见 9.4.2）；`llama-cpp/llama-cpp` 的物理完整坐标 swipe 仍未完成。

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
- `PhoneAgentScreenshotResult` 产出的 `ClientToolResult`/metadata 经现有 `ToolResultContent.read`：支持图片时产生非空图片引用，不支持图片时省略图片并保留文本；
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
- 前置重验三项精确诊断：`refresh()` 为 false 时消息含 `refresh_failed`、`isVisibleToUser` 为 false 时含 `not_visible`、`isEnabled` 为 false 时含 `not_enabled`，错误码均为 `stale_handle`，且消息不含节点文本；刷新失败优先于可见性和可用性判断；
- `performNodeAction` 在请求动作从当前节点移除后返回 `action_unavailable`，且不执行 `beforeAction` 或 `perform`；
- 动作后有效句柄可复用，失效句柄不会重定向；
- 归一化坐标、越界、NaN、旋转和尺寸变化；
- 节点动作、系统导航、手势回调和并发 `busy`；
- 截图缩放、密码区域遮挡、限频和 secure window 错误；
- 锁屏/息屏、服务中断和 pending 请求完成；
- 白名单与系统窗口拒绝；
- 输入错误码优先级：空包名 `no_window` → 系统包 `system_window_denied` → 非白名单 `package_not_allowed` → 白名单内句柄/截图校验；
- debug 夹具 `SecureWindowFixtureActivity` 的 `FLAG_SECURE` 开关、纯色像素和权限请求（只请求、不授予、不使用敏感能力）；
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

上一轮节点重验修正后的设备结果（历史）：

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

#### 9.3.1 异常路径集成测试（debug-only 夹具）

本轮新增 `integration_test/phone_agent_exception_test.dart`，使用真实 `PhoneAgentService` / `PhoneAgentTools` 和真实窗口，不使用 mock 替代原生截图、读树或输入。夹具 `com.kelivo.phoneagent.SecureWindowFixtureActivity` 只存在于插件 `android/src/debug`，不修改上游 `MainActivity`、`KelivoApplication`、`PhoneControlService`，不新增上游补丁或 `touches`，release 不编译、不合并。

夹具行为：

- `--ez secure true|false`：添加/清除 `WindowManager.LayoutParams.FLAG_SECURE`；同一 `singleTop` Activity 通过 `onNewIntent` 切换。
- `--ez requestPermission true`：只调用 `requestPermissions` 请求上游已声明的 `POST_NOTIFICATIONS`（API 33+），用于拉起系统权限窗口；不授予、不使用其他敏感能力。夹具只在 `checkSelfPermission` 不是 `GRANTED` 时请求，权限已允许时不会产生弹窗。
- 根布局为纯色 `#00C8FF` 和文本 `PHONE_AGENT_SECURE_FIXTURE`，作为前台就绪信号和截图像素校验。
- 权限窗口前置：设备必须处于唤醒且解锁状态。API35 实测设备息屏（`mWakefulness=Asleep`）时执行同一 `am start` 不会让权限弹窗获得前台焦点（`mCurrentFocus=null`），唤醒后弹窗立即出现；因此宿主在标记后先唤醒设备再启动夹具，并用 `dumpsys` 独立确认真实 `GrantPermissionsActivity`。测试在首次等待 45 秒未进入无窗口状态后打印 `PHONE_AGENT_PERMISSION_WINDOW_RETRY` 再给一次唤醒重试机会；重试后仍未进入则失败，不因 `root=null` skip，也不把任意 `no_window` 当作通过。宿主确认是测试前提，不是产品检测能力。

UID 与 secure 检测：API35 实测同 UID 和不同 UID 的 secure 夹具都返回成功黑图；UID 不是原因，整屏 `takeScreenshot` 路径本身没有 secure 检查。不同 UID 夹具 `com.kelivo.phoneagent.securefixture` 保留用于排除 UID 因素和验证文档化行为；该 APK 只是测试 harness，不属于 Mod 交付。插件内夹具继续用于权限窗口和同包切窗（旧坐标 `stale_observation`）。

宿主命令（测试只打印标记并轮询，不自己启动 Activity、不写系统授权）：

```bash
adb -s emulator-5554 shell am start -n com.kelivo.phoneagent.securefixture/com.kelivo.phoneagent.securefixture.SecureFixtureActivity --ez secure true
adb -s emulator-5554 shell am start -n com.kelivo.phoneagent.securefixture/com.kelivo.phoneagent.securefixture.SecureFixtureActivity --ez secure false
adb -s emulator-5554 shell am start -n com.psyche.kelivo.phoneagent/com.kelivo.phoneagent.SecureWindowFixtureActivity --ez secure false
adb -s emulator-5554 shell am start -n com.psyche.kelivo.phoneagent/com.kelivo.phoneagent.SecureWindowFixtureActivity --ez requestPermission true
adb -s emulator-5554 shell input keyevent 4
adb -s emulator-5554 shell am start -n com.psyche.kelivo.phoneagent/com.psyche.kelivo.MainActivity
```

不同 UID 夹具是宿主侧临时项目，不提交到仓库；用合成树的 Gradle wrapper 构建：

```bash
cd <合成树>/android
./gradlew -p <临时项目目录> assembleDebug
adb -s emulator-5554 install -r <临时项目目录>/app/build/outputs/apk/debug/app-debug.apk
```

测试场景与精确断言：

- FLAG_SECURE：普通截图成功 → 不同 UID 夹具前台（树出现 `PHONE_AGENT_SECURE_FIXTURE`，包名为 `com.kelivo.phoneagent.securefixture`）→ 截图分两种断言：若平台明确报错，断言 `tool_error` / `screenshot_blocked`、`metadata == null`、content 不含 `![](`、`data:image` 或 `image` 键；若成功，断言 `ok:true`、`package_name` 为夹具、图片可解码，并记录平台行为：平均亮度 <10 时打印 `PHONE_AGENT_SECURE_PLATFORM_BLACK_IMAGE`，否则打印 `PHONE_AGENT_SECURE_PLATFORM_CONTENT_IMAGE`；不要求全黑，不把黑图当安全检测。secure 期间断言读树仍成功（API35 实测可读，但不是绝对保证）→ 切到同包夹具使基线截图失效，坐标 `tap` 返回 `stale_observation` → 不同 UID 夹具清除 flag 并等待 ≥1.2 秒后截图成功，解码 PNG 断言非全黑且夹具纯色占比 >5% → 返回应用后新树/新截图成功。

历史严格预期与本轮修订：早期任务要求 secure 截图必须返回 `screenshot_blocked`；API35 实测同 UID/不同 UID 都曾返回成功黑图（后续也观察到成功内容图），严格测试失败。经用户同意，契约改为文档化行为：平台明确报错时无图片；成功黑图或内容图记录为平台行为，不当作安全检测。该历史失败保留，不删除。

本轮实际结果（设备运行树 `2c1513ecef3f2293`；当前最终源码/构建树 `5b1cde0304e687b9` 仅文档哈希变化，关键代码/测试一致，新树未重跑设备）：

- API35 完整异常套件（实际运行树 `2c1513ecef3f2293`）：**`+5 ~1`，`All tests passed!`，EXIT=0**。通过：FLAG_SECURE 截图行为与恢复、旋转、home/recents、锁屏、服务禁用/重启；跳过：权限窗口（明确未验证）。
- API35 `FLAG_SECURE 截图行为与恢复`：实际截图 `ok:true`、`image 713x1600`、`package_name=com.kelivo.phoneagent.securefixture`；本轮记录 `PHONE_AGENT_SECURE_PLATFORM_BLACK_IMAGE`（平均 RGB 约 2,0,2）。上一轮同一夹具曾返回成功内容图（平均亮度约 191），因此契约只承诺“可能黑化”，不保证黑图；测试记录黑图/内容图两种平台行为。secure 期间树可读；同包切窗后旧坐标返回 `stale_observation`；清除 flag 后恢复非黑夹具截图（纯色占比 >5%）。
- API35 锁屏 `device_locked`：同一锁屏窗口分别实际调用 `tree`、`screenshot`、`input`，三者均返回 `device_locked`；截图错误无图片 metadata；`status().ready` 仍为 true。解锁后旧句柄 `stale_handle`，新树/新截图成功。
- API35 服务禁用/中断/重启：先建立 Settings 观测并启动 1000 个只读 `readTree(offset:1)` 请求，保留同一批 Future，再由宿主在 pending 时关闭服务；日志 `PHONE_AGENT_SERVICE_PENDING_BATCH: size=1000 elapsed=3252ms codes=interrupted,ok`，无 `timeout`。重新启用后旧句柄 `stale_handle`，新树/新截图成功。
- 历史失败（保留）：`41e33b6f115e54bc` 完整套件为 `+2 ~1 -3`、EXIT=1；secure（切同包夹具只等文本未等包名，旧坐标得到 `package_not_allowed`）、锁屏（host driver 漏处理 lock 标记）、服务（未在窗口内完成系统 UI 禁用）失败。修正测试辅助与 host 协调后，实际运行树 `2c1513ecef3f2293` 完整套件 `+5 ~1`、EXIT=0；当前 `5b1cde...` 仅文档哈希变化，未重跑设备。
- API35 官方 `phone_agent_test.dart`：**2 项通过，EXIT=0**。
- API29 官方 `phone_agent_test.dart`：**2 项通过，EXIT=0**；截图返回 `unsupported_os`，树/节点输入回归通过。
- 当时产品 debug APK（历史，M10 最终源码/构建树 `5b1cde0304e687b9` 显式 `flutter build apk --debug`；设备套件实际运行于 `2c1513...`，未在新树重跑）：**181,373,590 字节**，SHA-256 `581d56fc03fe716c768f2554015115bffd8e2b0d610c71e74f5d3b21524703a3`；debug merged manifest 含 `SecureWindowFixtureActivity`，release merged manifest 不含该夹具（不宣称签名 release）。该 APK 已被 9.3.2 的 M16 产品 APK 取代，不能再当作当前产品。
- 权限窗口：实际运行树 `2c1513ecef3f2293` 完整套件明确跳过（90 秒内未检测到 permissioncontroller 前台），**未验证**，不写成通过。
- 未验证：签名 release、原生超时、权限窗口、`stale_handle` 根因；物理真机部分见 9.3.2。
- 旋转：旧树句柄 `tap` 返回 `stale_handle`；旧截图坐标 `tap` 返回 `stale_observation`；旋转后新树/新截图成功；转回后恢复。
- home/recents：执行后读树取实际前台包名；`com.android.systemui` 断言 `system_window_denied`，其他非白名单包断言 `package_not_allowed`，空包名或未知包名直接失败。`back` 同样被拒，证明 home/recents 后需要宿主恢复。
- 权限窗口：宿主先确保设备唤醒，启动夹具请求权限，并用 `dumpsys` 独立确认真实 `GrantPermissionsActivity`；随后测试直接调用节点 `tap`、截图和 `back`，三者都断言精确 `no_window` 与条件式人工提示，且 `back` 后读树仍为 `no_window`（证明没有执行系统导航）。首次等待 45 秒未进入无窗口状态时打印 `PHONE_AGENT_PERMISSION_WINDOW_RETRY`，宿主唤醒并重新启动夹具后再等 60 秒；重试后仍未进入则失败，不因 `root=null` skip，也不把任意 `no_window` 当作通过。宿主取消弹窗后确认 `POST_NOTIFICATIONS` 仍为 `granted=false`。
- 锁屏：宿主息屏再亮屏停在锁屏后，读树/截图/输入返回 `device_locked`，`status().ready` 仍为 true；解锁后旧句柄 `stale_handle`，新树/新截图成功。
- 服务禁用/中断：测试先建立 Settings 观测并启动一批有界只读 `readTree(offset:1)` 请求，保留同一批 Future；宿主在 pending 时通过系统 UI 关闭服务；等待原 Future 在 35 秒内完成，至少一个返回 `interrupted` 或 `service_unavailable`，不得返回 `timeout`；`status().enabled == false` 且 `ready == false`；重新启用后旧句柄 `stale_handle`，新树/新截图成功。

边界：

- 夹具启动、secure 切换、权限弹窗、锁屏和服务开关由宿主/CU 在打印标记后操作；测试自动断言结果，但不把宿主操作当成产品能力。
- 默认禁止用 `settings put secure enabled_accessibility_services` 写授权；服务开关只走系统界面。唯一例外是用户明确授权的物理 MIUI 测试设备 `1960cd68` 上仅对 Phone Agent 的测试预配置，见 9.3.2；结束必须恢复**当轮真实原值**（M16 历史轮为空串+0，M17 轮为 Phone Agent 组件 + `accessibility_enabled=1`），不能按历史记录强制关闭；产品不自动授权。
- 原生截图 10 秒、手势 duration+3 秒、插件 15/20 秒和 worker 15 秒排队超时无法在设备上确定性触发，只由 Dart 注入超时测试覆盖工具层映射，不写成真机证据。
- API 29 不适用 secure 截图和坐标场景，只跑原官方测试验证树/节点回归和 `unsupported_os`。

仍待验证：

- 物理真机的截图、坐标手势和 VLM 固定任务已由 9.3.2/9.4.2 覆盖（MIUI API31 + `mistral/deepseek-v4-1-flash-1017`）；`llama-cpp/llama-cpp` 的物理完整坐标 swipe 仍未完成。
- 其他 Android 版本/物理设备上的 `FLAG_SECURE` 行为（API35 模拟器与 MIUI API31 真机均已观察成功黑图，不代表所有设备）。
- 物理真机的锁屏、home/recents、服务禁用/重启和权限窗口仍未运行；API35 模拟器已验证锁屏、home/recents、服务禁用/重启三项。权限窗口在 API35 已真实触发并按 M22 保守收尾验收：读树/截图/输入均返回 `no_window` 与条件式人工提示，未执行手势/系统导航，通知权限未授予；`system_window_denied` 在无可访问 root 的权限弹窗场景不产生（M20/M21 已证伪识别机制），不再记为待实现（见 9.3.6）。原生截图/手势/通道/worker 排队超时仍未设备验证。
- 带合法签名配置的 release 构建。

因此不宣称 Phone Agent 第二阶段全部完成；未验证项不能用编译或单元测试代替真机结论。

#### 9.3.2 物理 MIUI API31 验收（真机）

设备与环境：

- Redmi K30 5G（`1960cd68`，picasso），Android 12 / API 31，1080x2400，density 440，MIUI V13.0.3.0.SGICNXM；用户提供该测试设备并授权安装应用、操作界面，设备无重要数据。
- 测试包 `com.psyche.kelivo.phoneagent` 安装成功，未覆盖上游 Kelivo；服务 enabled && connected；Mods 页三态选择与真实工具暴露一致。
- 授权例外：用户明确授权仅在该设备上用 `settings put secure` 预配置 Phone Agent 服务；M16 历史轮原始 `enabled_accessibility_services` 为空串、`accessibility_enabled=0`，M17 轮原始值为 Phone Agent 组件 + `accessibility_enabled=1`，每轮按当轮真实原值恢复。该例外只适用于本设备与 Phone Agent，不构成产品自动授权能力，其他设备默认仍禁止自动写系统授权。

实际结果：

- M16 历史结果：官方 `phone_agent_test.dart`（`flutter test --no-uninstall integration_test/phone_agent_test.dart -d 1960cd68`）在同一最终树、同一命令下两次结果不同：第一次 `+1 -1`、EXIT=1，聚焦后 `set_text` 返回 `stale_handle`（`The target node changed`，属 `ObservationRegistry` 的 refresh/isVisibleToUser/isEnabled 前置分支，不是旧聚焦指纹路径）；第二次 `+2`、EXIT=0。属间歇性，根因未确认、未修复，不能写成稳定通过。
- M17 诊断轮（当前，同一官方测试）：设备测试树为 `V:/coding/kelivo-private/.tower/worktrees/wt-17/.build/worktrees/8fe847cedc2ea513`；最终树 `.../1c1920e0e2b8bc7c` 仅 `plugin/README.md` 文档副本不同，代码/测试一致。本轮开始时设备授权原值为 `enabled_accessibility_services=com.psyche.kelivo.phoneagent/com.kelivo.phoneagent.PhoneAgentService`、`accessibility_enabled=1`，与上一条 M16 历史空串+0不同；每轮 `adb devices -l` 重查，安装测试包会清除组件，宿主 watcher 只恢复 Phone Agent 组件，轮末恢复当轮真实原值。4 轮结果均为 `+2`、`All tests passed!`、EXIT=0，未出现 `stale_handle`，也未触发新诊断标识。第 1 轮设备自动息屏导致约 3 分钟停顿，唤醒后继续并通过，不是测试失败。4 轮未复现历史间歇性失败，不能据此宣称根因修复；`refresh_failed`/`not_visible`/`not_enabled` 目前只有 JVM 单元测试覆盖，设备未触发。
- 物理 `FLAG_SECURE`：secure 夹具截图返回成功黑图（平台行为），不是 `screenshot_blocked`；清除 flag 后恢复真实截图。
- 旋转：旧句柄 `stale_handle`，旧截图坐标 `stale_observation`；旋转后新树/新截图成功。
- 坐标 UI 效果：`llama-cpp/llama-cpp` 轮用归一化坐标 tap 真实打开抽屉、Settings 和 Search，`set_text Phone` 成功；后续 swipe 因网关故障未完成，该模型的完整坐标 swipe 仍属未验证。
- 未在物理设备运行：锁屏、home/recents、服务禁用/重启、权限窗口；这些场景不能从 API35 模拟器结果推断为物理设备通过。
- 产品 APK 覆盖提醒：`flutter test` 会把树内 `build/app/outputs/flutter-apk/app-debug.apk` 覆盖为测试入口构建；产品 APK 必须在干净合成树显式 `flutter build apk --debug` 重新生成并重新计算大小与 SHA-256，不能沿用旧哈希，也不能把测试入口构建当产品。旧 M10 树 `5b1cde0304e687b9` 的 APK 就曾被覆盖为测试入口构建（249,642,846 字节，SHA-256 前缀 `1138b4d2`），之后才显式重建；因此旧 181,373,590 字节 / `581d56...` 与 249,642,846 字节 / `1138b4d2...` 都不能当作当前产品 APK。

#### 9.3.3 M19 权限窗口真实验证（API35 模拟器）

本轮只改中文文档、debug 异常测试和交接记录，不改产品代码、schema、白名单或上游。目标是查明上一轮 API35 异常套件中权限弹窗 90 秒未出现的原因，并真实验证权限窗口输入拒绝。

环境与前置：

- `emulator-5554`（Android 15 / API 35，AVD `Kelivo_Phone_Agent_API_35`，未 wipe data）；设备运行树 `V:/coding/kelivo-private/.tower/worktrees/wt-19/.build/worktrees/093f372e4d8513e5`（`modsetHash` `093f372e4d8513e556b4b2292045bb180a3b756a125543bbb34dbf2eceead3be`），最终树 `V:/coding/kelivo-private/.tower/worktrees/wt-19/.build/worktrees/75429900bf8fc452`（`modsetHash` `75429900bf8fc4526fb7005729da565f210eab3d9de922d94039e6399f808d11`）与运行树仅 `plugin/README.md` 文档副本和未验证标记/skip 文案不同，断言未变，`verify` 通过；未为文案重跑设备。
- 测试包 `com.psyche.kelivo.phoneagent`（versionCode 85，targetSdk 36），manifest 声明 `POST_NOTIFICATIONS`；实测 `granted=false`，flags 只有 `USER_SENSITIVE_WHEN_GRANTED|USER_SENSITIVE_WHEN_DENIED`，没有 `USER_SET`，说明从未被回答。
- 服务由系统无障碍界面启用（`Use Kelivo Phone Agent` → `Allow`），未使用 `settings put secure`；未授予任何权限、未撤销权限、未清应用数据。
- 未修改系统分辨率；宿主命令全部带 `-s emulator-5554`，每次先执行 `adb devices -l`。

诊断证据（上一轮 90 秒未出现的原因）：

- 设备唤醒时执行 `adb shell am start -n com.psyche.kelivo.phoneagent/com.kelivo.phoneagent.SecureWindowFixtureActivity --ez requestPermission true`，`dumpsys window` 显示 `mCurrentFocus=com.google.android.permissioncontroller/com.android.permissioncontroller.permission.ui.GrantPermissionsActivity`；uiautomator 树节点 package 均为 `com.google.android.permissioncontroller`，文案 "Allow Kelivo Agent to send you notifications?"；`dumpsys accessibility` 的 Active Window Id 指向该窗口（active=true、focused=true）。
- 设备息屏（`mWakefulness=Asleep`）时执行同一命令，`mCurrentFocus=null`，弹窗不会成为前台焦点；唤醒后弹窗立即出现。这是上一轮 90 秒内检测不到 permissioncontroller 的可复现条件，不是夹具或断言缺陷。
- 夹具只在 `checkSelfPermission` 不是 `GRANTED` 时调用 `requestPermissions`，因此“权限已允许导致无弹窗”不成立；`cmd package resolve-activity` 能解析 `SecureWindowFixtureActivity`。
- 取消弹窗只用 `adb shell input keyevent 4`，权限保持 `granted=false`。

实测结果（真实权限弹窗）：

- 弹窗确实出现，但 `PhoneAgentService` 的 `rootInActiveWindow` 在弹窗期间为 null：读树返回 `type=tool_error`、`error=no_window`（测试打印 `PHONE_AGENT_PERMISSION_TREE: package=null type=tool_error error=no_window`，45 秒 + 60 秒重试窗口内稳定复现）。这是本套件的直接设备证据。
- 输入 `no_window` 是代码路径推导，不是本轮直接设备调用证据：`PhoneAgentService.currentWindow()` 在 `rootInActiveWindow` 为 null 时返回 null，输入在包名策略和执行器之前以 `no_window` 拒绝；本套件在 `permissionTree == null` 时只读树和打印诊断，未执行 tap/back。输入仍被拒绝，没有执行任何手势，权限未授予。
- 文档契约仍要求 `system_window_denied`；本轮不把 `no_window` 改写成通过条件，该场景在套件中明确记录为未验证。根因和最小修复另开任务（M20：输入路径系统窗口识别），不在本轮修改生产代码。

测试改动（不放宽断言）：

- `PHONE_AGENT_PERMISSION_WINDOW` 标记要求宿主先唤醒设备；首次等待 45 秒超时（未检测到预期系统窗口）时打印 `PHONE_AGENT_PERMISSION_WINDOW_RETRY`（唤醒 + 重新启动夹具），再等 60 秒；重试后仍未检测到可访问的权限窗口才记录未验证。
- 未验证标记与 skip 原因写“服务未检测到可访问的权限窗口（读树返回 `no_window`）”，不断言系统弹窗不存在，避免与 `dumpsys` 已确认真实弹窗的事实矛盾。
- 未验证前打印 `PHONE_AGENT_PERMISSION_TREE`，只含 `package`/`type`/`error` 固定字段，不打印节点文本。
- 截图辅助在 `rate_limited` 时等待 1.2 秒重试一次，解决相邻用例间截图限频竞态；所有内容断言不变。

本轮完整异常套件（`093f372e4d8513e5` 树）：

- `flutter test integration_test/phone_agent_exception_test.dart -d emulator-5554`：**`+5 ~1`，`All tests passed!`，EXIT=0**。
- 通过：FLAG_SECURE 截图行为与恢复（secure 截图成功黑图，平台行为；同包切窗旧坐标 `stale_observation`；恢复后非黑夹具截图）、旋转（旧句柄 `stale_handle`、旧坐标 `stale_observation`）、home/recents（`system_window_denied`/`package_not_allowed`）、锁屏（tree/screenshot/input 均 `device_locked`）、服务禁用/中断/重启（`PHONE_AGENT_SERVICE_PENDING_BATCH: size=1000 elapsed=1112ms codes=interrupted,ok`）。
- 跳过：权限窗口（真实弹窗出现，读树实测 `no_window`；输入按 `currentWindow` guard 推导为 `no_window`，本套件未执行 tap/back；`system_window_denied` 未产生，按契约记录为未验证）。
- 历史失败保留：首次运行（`81a2da5132d0e975` 树）旋转用例因 `rate_limited` 失败、服务禁用用例因宿主未在约 2 秒批次内确认关闭而失败；修正测试等待与宿主反应后本轮 `+5 ~1`。两次失败都不是产品缺陷，也不是断言放宽。
- API 29 真机 `357784090209204` 本轮不在线，未运行；不写成通过。
- 自动检查：Loader `dart format --output=none --set-exit-if-changed tool test`、`dart analyze tool test`、`dart test`（165 项）通过；`plan`/`apply`/`verify` 通过；合成树 `dart analyze --fatal-infos lib test integration_test tool` 在 `flutter pub get --directory tool/l10n --enforce-lockfile` 后 `No issues found!`；插件 Dart 17 项、Phone Agent Flutter 108 项通过。本轮未改原生代码，因此未重建产品 APK；`flutter test` 已把运行树内 `app-debug.apk` 覆盖为测试入口构建，不能当作产品 APK，M17 产品 APK（181,373,530 字节 / `dc32c4a3...`）仍是当前产品；debug 夹具 manifest 本轮未改动，M17 的 debug/release 隔离结论不变。

M22 已按用户同意取消上述 skip：宿主 `dumpsys` 确认真实 `GrantPermissionsActivity` 后，测试直接调用 tap/back/截图并断言 `no_window` + 条件式提示，见 9.3.6。本节保留 M19 历史证据，不代表当前测试行为。

#### 9.3.4 M20 权限窗口输入路径诊断（API35 模拟器，abandoned）

本轮目标是验证 `AccessibilityService.windows` 能否在 `rootInActiveWindow=null` 时提供可确认的活动/聚焦系统窗口，并据此做最小修复让输入返回 `system_window_denied`。结论是**不可实现**：活动/聚焦的权限弹窗窗口没有可访问 root，无法取得包名；唯一有 root 的窗口是后台 systemui 窗口，不能当作前台。按 mission 停止条件停止，未提交生产代码或测试改动；该 branch 已 abandoned，未合并。

环境与前置：

- `emulator-5554`（Android 15 / API 35）；测试包 `com.psyche.kelivo.phoneagent` 重新安装；`POST_NOTIFICATIONS` 初始 `granted=false`，flags 只有 `USER_SENSITIVE_WHEN_GRANTED|USER_SENSITIVE_WHEN_DENIED`，没有 `USER_SET`。
- 服务通过系统无障碍界面启用（`Use Kelivo Phone Agent` → `Allow`），未使用 `settings put secure`，未授予或撤销任何权限。
- 诊断构建：合成树 `V:/coding/kelivo-private/.tower/worktrees/wt-20/.build/worktrees/b46ea4019595752d`（`modsetHash` `b46ea4019595752da9894fa35ebc3d7014decd71f470b4e8f0ae865936ff0219`），在 `PhoneAgentService.currentWindow()` 的 root 为 null 分支临时打印 `windows` 快照（只含 id/type/active/focused/hasRoot/packageName）；该日志和临时测试改动已全部移除，不在交付中。

真实弹窗与实测：

- 宿主执行 `adb -s emulator-5554 shell am start -n com.psyche.kelivo.phoneagent/com.kelivo.phoneagent.SecureWindowFixtureActivity --ez requestPermission true` 后，`dumpsys window` 的 `mCurrentFocus` 为 `com.google.android.permissioncontroller/com.android.permissioncontroller.permission.ui.GrantPermissionsActivity`，弹窗标题为 `Allow Kelivo Agent to send you notifications?`。
- 弹窗期间服务侧 `windows` 实测（固定字段）：`windows=2`；`w0 id=557 type=3 active=false focused=false hasRoot=true pkg=com.android.systemui`；`w1 id=563 type=1 active=true focused=true hasRoot=false pkg=null`。
- 读树实测 `no_window`（`PHONE_AGENT_PERMISSION_TREE: package=null type=tool_error error=no_window`）。
- 输入实测：测试轮询真实 `phone_agent_input tap`（使用弹窗前读到的节点句柄）45 秒 + 唤醒重试 60 秒，每次均返回 `no_window`（`PHONE_AGENT_PERMISSION_INPUT: type=tool_error error=no_window`），没有任何手势执行；用 `adb shell input keyevent 4` 取消弹窗后 `POST_NOTIFICATIONS` 仍 `granted=false` 且无 `USER_SET`。

为什么不能实现：

- mission 允许的最小修复要求「可确认的活动/聚焦系统窗口」；确认包名必须通过窗口 root（`AccessibilityWindowInfo` 没有包名字段）。本设备活动/聚焦窗口的 root 为 null，无法确认。
- 唯一有 root 的 `com.android.systemui` 窗口 `active=false focused=false`，把它当作前台就是 mission 明确禁止的「后台系统窗口误作前台」。
- 不使用 `dumpsys`/`uiautomator` 作为产品实现，不扫描任意节点推断前台，不按窗口标题猜包名。

交付与边界：未提交生产代码、Kotlin 测试或异常测试改动；M19 的异常套件当时仍把权限窗口记录为未验证（skip）。M22 已按用户同意改为保守收尾，见 9.3.6。

#### 9.3.5 M21 权限弹窗事件来源评估（API35 模拟器，abandoned）

本轮目标是评估 `TYPE_WINDOW_STATE_CHANGED` 事件来源包名能否与活动/聚焦窗口 id 可靠关联，从而在 `rootInActiveWindow=null` 时返回 `system_window_denied` 并提示人工处理。结论是**不可用**：真实权限弹窗期间服务没有收到任何 `permissioncontroller` 的窗口状态事件，无法取得来源包名。按 mission 停止条件停止，未提交生产代码或测试改动；该 branch 已 abandoned，未合并。

环境与前置：

- `emulator-5554`（Android 15 / API 35）；测试包 `com.psyche.kelivo.phoneagent`；`POST_NOTIFICATIONS` 实测 `granted=false`，flags 只有 `USER_SENSITIVE_WHEN_GRANTED|USER_SENSITIVE_WHEN_DENIED`，没有 `USER_SET`。
- 服务通过系统无障碍界面启用，未使用 `settings put secure`；未授予、撤销或清除任何权限。
- 诊断构建：合成树 `V:/coding/kelivo-private/.tower/worktrees/wt-21/.build/worktrees/34fe11ec8baa6bc6`，在 `PhoneAgentService.onAccessibilityEvent` 临时打印 `eventType/packageName/className/windowId/eventTime`，在 `currentWindow()` 的 root 为 null 分支临时打印 `windows` 快照；临时日志和临时测试已从交付移除，不在提交中。
- 真实弹窗由宿主执行 `adb -s emulator-5554 shell am start -n com.psyche.kelivo.phoneagent/com.kelivo.phoneagent.SecureWindowFixtureActivity --ez requestPermission true` 拉起；`dumpsys window` 的 `mCurrentFocus` 为 `com.google.android.permissioncontroller/com.android.permissioncontroller.permission.ui.GrantPermissionsActivity`。

实测事件（服务已连接并持续收到事件）：

- `EV type=32 pkg=com.psyche.kelivo.phoneagent wid=755`：应用窗口状态事件。
- `EV type=4194304 pkg=null wid=757`（多次）：`TYPE_WINDOWS_CHANGED`，没有来源包名；窗口 id 指向权限弹窗。
- `EV type=2048 pkg=com.android.systemui wid=715`：后台 systemui 窗口内容事件。
- **没有任何 `EV type=32 pkg=com.android.permissioncontroller` 或 `com.google.android.permissioncontroller`**；也没有 `pkg=null` 的 `type=32`。
- 弹窗期间 `windows` 快照：`id=715 type=3 active=false focused=false hasRoot=true pkg=com.android.systemui`；`id=757 type=1 active=true focused=true hasRoot=false pkg=null`。
- 读树和输入实测仍为 `no_window`；权限未授予。

为什么不可用：

- mission 要求「只处理明确 `permissioncontroller` 系统来源」；服务没有收到该来源的窗口状态事件，无法建立来源包名与活动/聚焦窗口 id 的匹配。
- 活动/聚焦的弹窗窗口没有可访问 root，`AccessibilityWindowInfo` 没有包名字段，不能用窗口 root 补全包名。
- 唯一有 root 的后台 systemui 窗口 `active=false focused=false`，不能当作前台；`TYPE_WINDOWS_CHANGED` 只有 `pkg=null`，不能作为来源包名。
- 不使用窗口标题、文本、任意窗口 root 或 `dumpsys`/`uiautomator` 猜测，不把 `no_window` 改写成通过条件。

交付与边界：未提交生产代码、Kotlin 测试或异常测试改动。M22 已按用户同意改为保守收尾，见 9.3.6。

#### 9.3.6 M22 权限弹窗保守收尾（API35 模拟器）

用户明确同意：“不可识别权限弹窗仍返回 `no_window`，消息条件式提示人工处理/取消并返回测试应用；不宣称识别具体权限弹窗，不要求 `system_window_denied` 出现在 root=null 场景。”本轮按此收尾，不追查新识别机制，不新增 overlay。

代码与契约：

- `PhoneAgentService` 三处无可访问窗口（读树、截图、输入）改用同一 helper，错误码保持 `no_window`；英文消息改为条件式提示：“No accessible window is available. If a system permission dialog is visible, ask the user to handle or cancel it, then return to the test app and retry.” 消息不声称识别具体权限弹窗，不添加事件跟踪、包名识别、原生截屏绕过或运行时回退。
- 可取得系统包名的系统窗口仍由 `PackagePolicy` 返回 `system_window_denied`；错误优先级、读树/截图密码遮挡、白名单和输入边界均不变。
- 异常测试删除 `root=null` 的 skip 分支：宿主在 `PHONE_AGENT_PERMISSION_WINDOW` 后唤醒、启动夹具并用 `dumpsys` 独立确认真实 `GrantPermissionsActivity`；测试轮询进入 `no_window` 后直接调用节点 `tap`、截图和 `back`，断言精确 `no_window` 与条件式提示；`back` 后读树仍为 `no_window`，证明没有执行系统导航；宿主取消弹窗后确认 `POST_NOTIFICATIONS` 仍 `granted=false`。首次 45 秒未进入时打印 `PHONE_AGENT_PERMISSION_WINDOW_RETRY` 再等 60 秒，仍未进入则失败，不把任意 `no_window` 当作通过。
- 宿主 `dumpsys` 确认是测试前提，不是产品检测能力；测试自身无法读取 `dumpsys`，文档和测试注释都明确这一点。

本轮结果（设备运行树 `V:/coding/kelivo-private/.tower/worktrees/wt-22/.build/worktrees/d94f4165af9277d5`，`modsetHash` `d94f4165af9277d5bbdc83c3c07bcc5bdce55cb4c241a284edfdcd5d5d0a2c9d`）：

- API35 `emulator-5554` 官方 `phone_agent_test.dart`：**`+2`、`All tests passed!`、EXIT=0**（真实截图/读树/节点点击/坐标滑动/节点滚动/聚焦后 `set_text`/二次读树、Mods 页三态选择）。
- API35 完整异常套件 `phone_agent_exception_test.dart`：**`+6`、`All tests passed!`、EXIT=0**。权限场景：宿主 `dumpsys window` 实测 `mCurrentFocus=com.google.android.permissioncontroller/com.android.permissioncontroller.permission.ui.GrantPermissionsActivity`；测试打印 `PHONE_AGENT_PERMISSION_TREE: package=null type=tool_error error=no_window`；节点 tap、截图和 `back` 均断言 `no_window` + 条件式提示，`back` 后读树仍 `no_window`，未执行手势/系统导航；宿主取消弹窗后 `POST_NOTIFICATIONS` 仍 `granted=false`（无 `USER_SET`）。服务禁用/中断/重启：`PHONE_AGENT_SERVICE_PENDING_BATCH: size=1000 elapsed=670ms codes=interrupted,ok`，无 `timeout`。
- 自动检查：Loader `dart format`/`dart analyze` 通过、Loader 165 通过；合成树 `flutter pub get`、`flutter pub get --directory tool/l10n --enforce-lockfile` 通过，`dart analyze --fatal-infos lib test integration_test tool` 输出 `No issues found!`；根项目 seam 测试 56 通过；插件 Dart 17、插件 Kotlin 66 通过。
- 产品 debug APK：在最终树 `flutter clean` 后显式 `flutter build apk --debug` 生成，**181,373,914 字节**，SHA-256 `5cc74cabf3fc02c9c0a7e79174ea5b9467523d25a72c760b65cb634daf69f0e3`；debug merged manifest 含 `SecureWindowFixtureActivity`（1 处），release merged manifest 不含该夹具（0 处，不宣称签名 release）。
- API29 真机 `357784090209204` 本轮不在线，未运行，不写成通过。

### 9.4 VLM 图片链路与固定任务验收（API 35 模拟器，magpie `llama-cpp/llama-cpp`）

以下为 API 35 模拟器上的历史 VLM 验收记录；M10 历史的 FLAG_SECURE/异常路径结果见 9.3.1，物理 MIUI API31 真机的 VLM 结果见 9.4.2。

该轮在 API 35 模拟器 `emulator-5554`（Android 15，内部屏幕 1080x2424）使用产品 debug APK（181369230 字节，SHA-256 `3ea30ee9b46342305cf11e0574b76def9a42f23abe62dd3536b664dc4ec5caeb`）和用户指定的 magpie 网关模型完成真实聊天、图片链路、Kelivo 应用内固定任务和跨新用户轮次历史图片回放。该轮未修改产品代码、`mod.json`、schema、节点指纹或插件行为，未重建 APK。

环境与适用范围：

- 模型：magpie 网关的 `llama-cpp/llama-cpp`（Text、Image → Text、Tools）；应用内 provider 地址 `http://10.0.2.2:3425/v1`，UI 勾选 Image 输入和 Tools。局域网访问由用户开启，密钥未修改、未读取、未记录。
- 设备：API 35 模拟器；Mods 页 Default Assistant 选择 Phone Agent，独立服务 enabled && connected，API 35 ready；未启用原生手机控制，未写系统无障碍授权。
- 适用范围：只验证该 magpie 模型与 API 35 模拟器，不承诺任意模型、任意网关或任意设备；物理真机的 VLM 结果见 9.4.2。

证据 A：工具暴露与最小截图 → 图片 → 模型链路

- REQ27（15:00:52）请求工具为 `read_file` + `phone_agent_screenshot` / `phone_agent_tree` / `phone_agent_input`；`read_file` 是上游工具，不属于 Mod schema。无原生 `phone_control`，无重复 `phone_agent_*`；三个 schema 均无 `snapshot_id`，均设置 `additionalProperties: false`。
- REQ28（15:00:58，Request Log ID28）携带 `phone_agent_screenshot` 工具结果：`image 713x1600`、`screen 1080x2424`、`package_name com.psyche.kelivo.phoneagent`；并包含一条合成 user 消息，`image_url` 为 `data:image/png;base64,<omitted 185028 chars>`，`detail` 为 `high`。
- 响应头 `x-magpie-model: llama-cpp/llama-cpp`、`x-magpie-provider: llama-cpp`；模型回答 `3:00 / New Chat / llama-cpp/llama-cpp (Magpie VLM)`，与截图中的时间、聊天标题和模型名称一致，属于对视觉细节的真实读取。

证据 B：Kelivo 应用内固定任务（点击 + 输入 + 确认）

- 任务在 Kelivo 自己的 Settings 页面（不是 Android 系统设置）中完成；每次 tree/input 的前台包名均为 `com.psyche.kelivo.phoneagent`，未使用 adb 代替模型输入。
- 实际工具顺序（REQ30-37）：`phone_agent_tree` 返回 22 个节点并找到 `n3`（description `Search settings`）→ 首次 `tap n3` 返回一次 `stale_handle`（`No current tree observation`）→ 重新读树后 `tap n3` 成功 → 重新读树找到 `EditText n2` → `set_text n2 "Phone"` 成功 → 再次读树确认。
- UI 最终状态：搜索框为 `Phone`，显示 `1 result`，唯一结果为 `Phone Control / Settings`；模型回答同时确认 `1 result` 和 `Phone Control`。

证据 C：应用内 Settings 滚动确认

- 实际工具顺序（REQ38-41）：`phone_agent_tree` → 对 `n4`（`android.widget.ScrollView`）执行 `scroll forward` 成功 → 再次读树。
- UI 可观察状态：Settings 页面真实滚到底部并显示 `Sponsor`；模型回答 `Sponsor`。

证据 D：跨新用户轮次历史图片回放

- 新用户消息 REQ42（15:36:58）要求不调用任何工具、不重新截图，只回答第一张截图独有的视觉信息。
- 该请求确实从持久化的历史工具 metadata 带回同一 `image_url`（`<omitted 185028 chars>`，`detail` 为 `high`），该轮没有新的 `tool_call`。
- 模型回答输入框占位为 `Type a message for AI`，发送按钮为蓝色圆形内白色方块（停止状态）；拉取保存的 713x1600 PNG 逐像素核对，蓝色圆形与白色方块位置/颜色一致。
- 图片进入上下文后，上游额外暴露 `read_chat_image` 工具；这是上游行为，不是 Mod 重复暴露，也不是 `phone_control`。

异常记录：一次未复现的 `stale_handle`

- 在证据 B 中，`phone_agent_tree` 成功返回 22 个节点后紧接的 `tap n3` 返回一次 `stale_handle`，消息为 `No current tree observation`；代码路径显示 `tree == null`。
- 重读树后同一目标点击成功，后续任务未再出现；未找到对应 native 日志，未复现，未确认缺陷，未修复。
- 可能来源（例如服务中断或观测失效）只是假设，不写成事实；该事件不改变 6.5.1 的指纹契约，也不作为产品缺陷记录。

证据边界：

- 跨用户轮次历史图片回放已通过，不再列为未验证；同轮工具循环回放见证据 A（REQ28）。
- 该轮未使用坐标动作完成任务；坐标手势的 UI 效果受 integration_test 绑定限制，物理真机的坐标 UI 效果由后续 9.3.2/9.4.2 补充。
- 该轮没有确认私有 Mod 硬缺陷；上述一次 `stale_handle` 证据有限，根因未查明。契约内的可恢复错误不写成产品假成功。
- 该轮仍明确未验证：物理真机的 VLM 固定任务与坐标手势 UI 效果、签名 release；真实 `FLAG_SECURE`、旋转、home/recents、锁屏、服务禁用/重启已由后续 M10 在 API35 模拟器补充（见 9.3.1），物理真机的 secure/旋转/VLM/坐标 UI 效果已由 9.3.2/9.4.2 补充，但不代表其他 Android 版本或设备。
- 该轮只验证 magpie `llama-cpp/llama-cpp` 与 API 35 模拟器，不承诺任意模型或设备。
- 文档只记录脱敏后的请求形态和尺寸/长度，不记录 provider 密钥、完整会话文本或截图字节。

#### 9.4.1 上一轮 LM Studio 补充环境（历史结果）

以下为上一轮使用 LM Studio `prism-ml/bonsai-27b`（identifier `bonsai-vlm`，Image + Tools，8192 上下文，provider `http://10.0.2.2:1234/v1`）的补充环境结果，不是本轮用户指定模型，不能取代 9.4 的结论：

- Request Log ID18 显示 `image/png · 47.7 KB · omitted`，Authorization 已脱敏；后续请求 `image_url` 为 `data:image/png;base64,<omitted 163212 chars>`，`detail` 为 `high`；模型读出 `10:47 / New Chat / bonsai-vlm (Local VLM)`。
- 固定任务完成 tree → tap `Search settings` → tree → `set_text Phone` → `n1 scroll down` 返回 `action_unavailable` → 截图确认；补充滚动先返回 `stale_handle`，重读树后 `n4` ScrollView `forward` 成功并显示 `Sponsor`。
- 同一生成轮的工具循环图片回放已验证：截图后的后续请求再次携带该图片。
- 4096 上下文下复杂任务出现截图/读树循环，8192 后完成；这是本地测试经验，不是产品运行时要求。

#### 9.4.2 物理 MIUI API31 VLM 验收（magpie `mistral/deepseek-v4-1-flash-1017`）

本轮在物理 MIUI API31 真机（见 9.3.2）上完成 VLM 图片链路、坐标 UI 效果和像素专属视觉确认：

- 模型选择：用户更正目标为 `mistral/deepseek-v4-1-flash-1017`（不是 0731）；magpie 路由的 16 个模型中没有 0731，Mistral 目录按 deepseek 筛选只有该 1017。Bonsai 备用环境已加载但未使用，不作为本轮证据。
- 能力标注与手动开启：magpie 侧该模型「支持图片输入」为关闭，Kelivo 目录标注文本→文本；在 Kelivo 手动勾选图片后，真实请求携带 `image_url`（`data:image/png;base64,<omitted>`，`detail=high`）且全部返回 200，响应头 `x-magpie-model` / `x-magpie-provider` 与请求一致。模型能力标注可能变化，每次都要实测图片与工具能力；手动勾选只是测试配置，不是模型能力保证。
- 工具暴露：`read_file` + 三个 `phone_agent_*`，无 `phone_control`、无重复、无 `snapshot_id`、`additionalProperties=false`。
- 截图尺寸：`image 720x1600`，`screen 1080x2400`，package `com.psyche.kelivo.phoneagent`。
- 坐标 swipe 的物理 UI 证据：实际工具序列进入 Kelivo 应用内 Settings 后，执行一次 `phone_agent_input` swipe `{x:0.5,y:0.8,end_x:0.5,end_y:0.3,duration_ms:400}`，前后 PNG 证实 Sponsor 从不可见变为可见。这是物理坐标 UI 效果，不是 integration_test 回调推断。
- 像素专属视觉证据：新建无历史会话，只允许一次 `phone_agent_screenshot`，禁止 tree/input，提示不透露颜色或文本；1017 回答 `bright cyan (light blue)` 和 `PHONE_AGENT_SECURE_FIXTURE`，与保存 PNG 的 rgb(0,200,255) 及完整文字一致。该轮请求只有一个截图 `tool_call`，`image_url` 为 `data:image/png;base64,<omitted 39204 chars>`，请求全文不含 `PHONE_AGENT`，构成后端视觉消费的直接支持证据，但不是对模型内部机制的绝对证明。
- 边界：第一轮过渡帧出现黑色区域和文本裁切，后续截图应等界面稳定；`llama-cpp/llama-cpp` 的完整坐标 swipe 未验证；网关 `api_error` / 空响应属外部故障，不写成产品缺陷；文档不记录密钥、完整会话或图片字节。

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
- VLM 图片链路、Kelivo 应用内固定任务和跨新用户轮次历史图片回放已在 API 35 模拟器用 magpie `llama-cpp/llama-cpp` 通过；物理 MIUI API31 真机由 `llama-cpp/llama-cpp` 通过归一化坐标 tap（打开抽屉/Settings/Search），由 magpie `mistral/deepseek-v4-1-flash-1017` 通过真实图片请求、归一化坐标 swipe 的物理 UI 效果和像素专属视觉确认；`llama-cpp/llama-cpp` 的完整坐标 swipe 仍未验证；不承诺任意模型或设备。
- 上一轮 VLM 文档轮只改中文文档，未重跑测试；该标签仅适用于该历史 VLM 文档轮，不代表当前 M17。M17 已重跑 Loader 165、插件 Kotlin 66、插件 Dart 17、根项目 `dart analyze --fatal-infos` 和 Flutter 182；历史 Phone Agent 105、Mods 16、settings 入口 2、上游 `tool_result_content` 14 通过 + 1 Windows 条件跳过、上游 PhoneControl 49 结果继续有效。
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
- API 30+ 截图与坐标手势已在 API 35 模拟器验证；物理 MIUI API31 真机由 `llama-cpp/llama-cpp` 的归一化坐标 tap 与 `mistral/deepseek-v4-1-flash-1017` 的归一化坐标 swipe 证实坐标 UI 效果；integration_test 的坐标手势 UI 滚动效果仍受绑定限制（不转发设备指针事件），不能把回调成功当 UI 效果。
- VLM 图片链路、Kelivo 应用内固定任务和跨新用户轮次历史图片回放已在 API 35 模拟器用 magpie `llama-cpp/llama-cpp` 验证；物理 MIUI API31 真机用 magpie `mistral/deepseek-v4-1-flash-1017` 验证真实图片请求、坐标 swipe 的 UI 效果和像素专属视觉确认；`llama-cpp/llama-cpp` 的物理完整坐标 swipe 未验证；只验证这些模型与设备，不承诺任意模型或设备。
- 物理设备官方测试在 M16 出现一次间歇性 `set_text` `stale_handle`（`The target node changed`，`ObservationRegistry` 的 refresh/isVisibleToUser/isEnabled 前置分支），另一次全通过；M17 用同一官方测试连续 4 轮均为 `+2`、EXIT=0，未复现，也未触发 `refresh_failed`/`not_visible`/`not_enabled`。根因仍未确认、未修复，不能把 4 轮通过写成根因修复或稳定通过。
- magpie 的模型能力标注可能变化，图片与工具能力需每次实测；Kelivo 手动勾选图片只是测试配置，不构成模型能力保证。
- `settings put secure` 预配置仅限用户明确授权的该台 MIUI 测试设备，不是产品能力，也不代表其他设备可以自动写入无障碍授权；每轮开始必须记录并恢复当轮真实原值，不能按历史空串+0 强制关闭。M17 轮原值为 Phone Agent 组件 + `accessibility_enabled=1`。
- `flutter test` 会覆盖树内 `app-debug.apk` 为测试入口构建；产品 APK 必须显式 `flutter build apk --debug` 重新生成并重新计算大小/SHA-256。
- 一次 `stale_handle`（`No current tree observation`）在 tree 成功后紧接 tap 时出现，未复现、未找到 native 日志、根因未确认、未修复；重读树后恢复。可能来源只是假设，不写成事实。
- 整屏 `takeScreenshot` 不保证对 `FLAG_SECURE` 报错；secure 内容可能以黑色区域出现在成功截图中。不根据像素猜 secure，不承诺不发送黑图，正常黑色页面保留。
- 平台明确报错时不得把图片或图片 metadata 交给模型；成功黑图只作为普通截图，模型应优先读树、不凭黑图猜坐标。
- `FLAG_SECURE` 不阻止无障碍读树和输入；API35 夹具树可读，但不是绝对保证；密码字段、自定义 View、窗口变化仍会影响树；非白名单输入仍被拒绝。
- `system_window_denied` 和 `package_not_allowed` 只约束输入；读树和截图仍可观察系统窗口、权限弹窗和其他应用。
- `home`/`recents` 执行后前台离开白名单，后续输入（包括 `back`）会被拒绝，模型无法自行回到测试应用，需要用户或宿主恢复。
- `SecureWindowFixtureActivity` 只是 debug 测试夹具，不是产品能力；release 不包含该 Activity。
- API35 模拟器已验证旋转、home/recents、锁屏、服务禁用/重启；物理 MIUI API31 真机已验证旋转和物理 `FLAG_SECURE`，但锁屏、home/recents、服务禁用/重启未在物理设备运行，不能从模拟器结果推断；原生超时仍无法在设备上确定性触发。
- 未执行带合法签名配置的 release 构建。
- 因此不宣称 Phone Agent 第二阶段全部完成。
- Loader 更新演练通过不代表 Phone Agent 真机行为无需重新验证。
