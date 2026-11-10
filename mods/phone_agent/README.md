# Phone Agent Mod

本目录是 Kelivo 的 `phone_agent` 源码 Mod，属于私有仓第二阶段实现。它通过 Mod Loader 合成到固定上游基线，提供截图、无障碍树和基础输入三个工具，并使用独立的 Flutter path 插件与独立 `AccessibilityService`，不修改上游 `PhoneControlService`。

- 上游基线：`73afa4ec77cfc9af2efea2487fee8bba1362639d`
- 设计范围与验收标准：`docs/phone-agent-plan.md`
- Loader 命令与合成规则：`docs/mod-loader-plan.md`
- 插件包名：`kelivo_phone_agent`
- MethodChannel：`kelivo/phone_agent`
- 公开单例：`KelivoPhoneAgent.instance`
- 助手级工具 ID：`phone_agent`
- Mod 版本：`0.2.0`

> 本轮节点重验修正后：合成树 `V:/coding/kelivo-private/.tower/worktrees/wt-1/.build/worktrees/7593c21b5f9da01f`，Loader verify 通过；Loader 165、插件 Kotlin 66、插件 Dart 17、上游 PhoneControl 49、Phone Agent 103、Mods 16、settings 入口 2 通过；API 35 模拟器与 API 29 真机官方集成测试均退出码 0。仍明确未验证物理 API 30+ 真机的坐标手势 UI 效果、VLM、真实 `FLAG_SECURE`、其他真机异常和签名 release，不宣称第二阶段全部完成。

## 目录与合成目标

```text
mods/phone_agent/
├── mod.json
├── README.md
├── patches/
│   ├── pubspec.patch
│   ├── application-id.patch
│   ├── local-tool-mutual-exclusion.patch
│   ├── settings-entry.patch
│   ├── l10n-source.patch
│   └── l10n-generated.patch
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
└── plugin/
```

当前 `mod.json` 声明的复制目标：

| 源 | 合成树目标 |
|---|---|
| `overlay/lib/features/phone_agent` | `lib/features/phone_agent` |
| `overlay/lib/features/mods` | `lib/features/mods` |
| `overlay/test/features/phone_agent` | `test/features/phone_agent` |
| `overlay/test/features/mods` | `test/features/mods` |
| `overlay/test/features/settings/pages/mods_settings_entry_test.dart` | `test/features/settings/pages/mods_settings_entry_test.dart` |
| `overlay/integration_test/phone_agent_test.dart` | `integration_test/phone_agent_test.dart` |
| `plugin` | `dependencies/kelivo_phone_agent` |

补丁职责：

- `patches/pubspec.patch`：只在上游 `pubspec.yaml` 的 `dependencies` 中增加 path 依赖。
- `patches/application-id.patch`：修改 `android/app/build.gradle.kts` 和宿主 Manifest，将私有测试包名设为 `com.psyche.kelivo.phoneagent`、启动名称设为 `Kelivo Agent`。
- `patches/local-tool-mutual-exclusion.patch`：修改 `lib/features/home/services/local_tool_toggle.dart`，在本地工具开关写入时保证 `phone_control` 与 `phone_agent` 互斥，并重读当前助手避免旧快照覆盖。它是 phone_agent Mod 自己声明的业务补丁，不是 Loader 通用接缝。
- `patches/settings-entry.patch`：在 `lib/features/settings/pages/settings_page.dart` 和 `lib/desktop/desktop_settings_page.dart` 增加 `ModsPage`/`ModsPane` 入口及桌面菜单注册，不修改 `lib/features/settings/search/settings_search_index.dart`。它是 phone_agent Mod 自己声明的业务补丁，不是 Loader 通用接缝；只增加入口和导入，不把 Mod 业务逻辑写进上游文件。
- `patches/l10n-source.patch`：在 `lib/l10n/app_en.arb` 和 `app_zh.arb` 增加产品文案键及英文描述。
- `patches/l10n-generated.patch`：包含本机免费 llama-cpp 翻译后的 ARB、`tool/l10n/state` 和生成的 Dart 输出；`translate.py check` 四目标语言 0 pending。

除新增 Mods 入口、本地工具开关互斥和 ARB 键外，Mod 不修改 `MainActivity.kt`、`KelivoApplication.kt`、`PhoneControlService.kt`、`DeviceLocalToolsHandler.kt`、`local_tools_service.dart` 的原生工具定义或 `LocalToolNames.all`。

Loader 通用 `lib/modding/tool_mod.dart` 和 `mod_registry` 生成逻辑不 import Phone Agent。`mod_registry.g.dart` 中的 Mod import 只来自 `mod.json` 的 `registration.import`，不是 Loader 通用代码的硬编码依赖。

当前 `mod.json` 已声明 `local-tool-mutual-exclusion.patch`、`settings-entry.patch`、`l10n-source.patch`、`l10n-generated.patch`，以及对应 `touches` 和复制目标；修改时必须保持文档、补丁和 `mod.json` 一致。

## 安装、选择与授权

### 前置条件

- Android 测试设备，系统已解锁。截图和坐标手势需要 API 30 或更高；API 29 服务可 ready 并验证读树和节点输入，截图返回 `unsupported_os`，页面显示截图限制。
- 上游仓位于 `mods.json` 声明的路径，且已跟踪文件干净。
- 已按上游要求安装 Flutter 与 Android 工具链。
- 只使用无账号测试界面；首版不面向日常主力机或敏感应用。

### 合成与构建

在私有仓根目录执行：

```bash
dart tool/mod_loader.dart plan
dart tool/mod_loader.dart apply
```

`apply` 会创建或复用 `.build/worktrees/<modsetHash 前 16 位>/`，应用 Loader 接缝补丁和 Mod 补丁，复制 overlay 与插件，并生成静态注册表 `lib/modding/mod_registry.g.dart`。随后在合成树中执行：

```bash
flutter pub get
flutter build apk --debug
```

### Mods 页三态选择

安装 debug APK 后，从移动端“设置 → Mods”或桌面端“设置 → Mods”打开同一个页面；宽窄屏共用这个简单页面，不拆分布局。页面先选择助手，再为该助手选择三态之一：

| 选择 | 行为 |
|---|---|
| 关闭 | 从 `assistant.localToolIds` 移除 `phone_control` 和 `phone_agent`，不自动关闭系统无障碍服务。 |
| 原生手机控制 | 保留或加入 `phone_control`，移除 `phone_agent`，并继续进入上游手机控制授权页。 |
| Phone Agent | 加入 `phone_agent`，移除 `phone_control`，不自动打开系统无障碍设置。 |

规则：

- 三个选项互斥，正常 UI 不允许原生手机控制和 Phone Agent 同时启用。
- 已有仅启用 `phone_control` 的助手显示为“原生手机控制”，打开 Mods 页不会自动迁移或改写。
- 如果历史数据、手工编辑或上游本地工具页导致两个 ID 同时存在，页面显示冲突并要求重新选择；在用户处理前，`PhoneAgentMod` 以 `phone_agent` 为激活依据，并过滤原生 `phone_control` 定义，避免同时暴露两套工具。
- 上游本地工具开关与页面的互斥由本 Mod 的 `local-tool-mutual-exclusion.patch` 执行，不是 Loader 通用接缝。该补丁必须保证两者不会同时写成启用；如果无法隐藏或拦截 `phone_control`，Mods 页显示冲突并要求重新选择，执行层按 `phone_agent` 激活并过滤原生 `phone_control`，不能静默并存。
- 选择只修改助手的 `localToolIds`，不修改数据库 schema。
- 上游助手的“本地工具”页和对话工具菜单不新增 `phone_agent` 项；Phone Agent 的助手级选择只在 Mods 页完成。这些上游界面不显示 `phone_agent`；选择 Phone Agent 后，它们可能把手机控制显示为未启用，这是预期行为，以 Mods 页为准。

### 服务授权

Mods 页的选择是工具配置，不代表服务已授权。选择 Phone Agent 后，还需要人工完成：

1. 在系统“设置 → 无障碍”中启用本 Mod 的独立服务（服务名称以插件的 `strings.xml` 为准）。
2. 保持设备解锁，并在 Mods 页刷新服务状态。

两个无障碍服务继续共存：上游 `PhoneControlService` 和独立 `PhoneAgentService` 各自在 Manifest 中声明，各自在系统设置中授权。Mod 不自动授权、不自动打开系统无障碍开关、不静默提权、不绕过系统确认，也不会因为用户选择某个工具而切换另一个服务。

无障碍权限可以读取屏幕内容并执行点击、输入等操作，属于高权限授权。只在明确知情的测试设备上启用；不需要时应在系统设置中关闭服务。

### 服务状态

Mods 页显示独立 `PhoneAgentService` 的状态，并用 `enabled && connected` 派生 ready：

| 字段 | 含义 |
|---|---|
| `PhoneAgentAvailability.supported` | 仅表示 Android API 30+ 系统截图能力；false 不代表 Phone Agent 或平台不可用。 |
| `enabled` | 系统无障碍设置中是否已启用独立 `PhoneAgentService`。 |
| `connected` | 独立服务是否已连接并可以接收请求。 |
| `ready` | 由 `enabled && connected` 派生；表示服务可接收请求，树和节点输入可用。API 29 也可以 ready。 |
| `sdk`（`androidSdkInt`） | 当前 Android API 级别；`sdk >= 30` 时截图和坐标手势可用。 |

`PhoneAgentAvailability.supported` 只描述截图能力，不是 Phone Agent 的总体可用性。API 29 上 `supported=false`，但服务仍可 `enabled` 且 `connected`，即 ready，树和节点输入可用；截图返回 `unsupported_os`，页面显示截图和坐标手势限制。

页面提供刷新按钮和打开无障碍设置按钮，并展示能力与隐私说明。说明会明确：助手可以读取当前屏幕、点击、输入、滚动、截图和导航；屏幕内容会发送给当前对话配置的模型服务商并保存在工具结果中；密码字段会隐藏；服务不会持续录屏；用户可以随时关闭助手工具或在系统设置中停用服务；首版只允许测试包名。

状态面板只读取状态，不修改系统设置；状态可能滞后于系统设置，刷新失败时以系统设置和工具返回的结构化错误为准。

非 Android 平台仍可打开 Mods 页，但页面显示平台不支持，不添加任何 Mod 工具；这与 `supported=false` 的截图限制含义不同。

### 故障排查

- 已实测该 Sharp 设备（SG803SH）重装 APK 会撤销无障碍授权。`--no-uninstall` 只避免测试结束时卸载应用，不能避免安装阶段的授权撤销。
- 集成测试打印 `PHONE_AGENT_WAITING_FOR_SERVICE` 表示服务未就绪：安装测试包会撤销无障碍授权，需要在测试包安装完成后到系统“设置 → 无障碍”重新启用本 Mod 的精确服务（`Kelivo Phone Agent`），测试会等待约 300 秒，仍未就绪则以服务状态失败。
- 工具返回 `phone_agent_disabled` 表示当前助手已不再启用 `phone_agent`：回到 Mods 页重新选择 Phone Agent。
- 工具返回 `unsupported_platform` 表示当前不是 Android 或插件不可用；检查构建平台和插件复制目标。
- 工具返回 `unsupported_os` 表示当前设备低于 API 30，截图不可用；服务仍可 ready，树和节点输入可用，页面会显示截图限制。
- Mod 不会自动授权、静默提权或恢复已撤销的服务；授权状态以系统无障碍设置和工具返回的结构化错误为准。

## Loader 命令

```bash
cd V:/coding/kelivo-private

dart tool/mod_loader.dart plan
dart tool/mod_loader.dart apply
dart tool/mod_loader.dart verify
dart tool/mod_loader.dart rebase-drill --to <完整 commit>
dart tool/mod_loader.dart clean --modset <完整哈希或 16 位前缀>
```

- `plan` 只读打印基线、`modsetHash`、合成目录、Loader overlay、补丁和 Mod 复制目标，不写文件。
- `apply` 幂等创建或复用合成树；补丁逐个 `git apply --check` 后应用，复制目标已存在时失败，不覆盖上游文件。
- `verify` 校验 HEAD、`MOD_BUILD.json`、注册表、补丁结果和复制文件，不执行 Flutter 构建。
- `rebase-drill` 在 `.build/drills/` 的临时 worktree 验证新基线，不修改 `mods.json` 或主合成树。
- `clean` 必须显式提供 `--modset`，只删除带 Loader 状态记录的精确合成目录。

## 工具契约

三个工具名固定为 `phone_agent_screenshot`、`phone_agent_tree`、`phone_agent_input`，均声明在 `mod.json` 的 `toolNames` 中。所有 schema 和结果都不出现 `snapshot_id`，并设置 `additionalProperties: false`。节点句柄、截图状态和 TTL 只存在于原生内存。

### 激活与过滤

`PhoneAgentMod` 仅在 Android、当前模型支持工具调用、且当前助手启用 `phone_agent` 时激活。激活时：

- 从工具定义中移除原生 `phone_control`；
- 移除重复的 `phone_agent_*` 定义，避免与上游或其他 Mod 重复暴露；
- 添加本 Mod 的三个工具定义。

每次执行 Mod 工具前，重读当前助手的 `phone_agent`；撤销后返回 `phone_agent_disabled`。助手不存在或读取失败时按未启用处理，同样返回 `phone_agent_disabled`。`phone_agent` 不加入 `LocalToolNames.all`，因此上游不会为它生成原生定义、标签或开关。未激活时完全保留上游定义，原生 `phone_control` 按上游行为工作。

### `phone_agent_screenshot`

截取当前画面，返回图片、图片尺寸、物理屏幕尺寸和前台包名。图片通过 Kelivo 现有的 `McpImageSnapshot` 与 `ClientToolResult` 链路进入工具循环，不修改 provider 序列化。原生先缩放到长边不超过 1600，再经通道传给 Dart；Dart 落盘后校验实际尺寸与原生声明一致，不一致则返回错误，且不更新坐标观测。API 29 返回 `unsupported_os`；树和节点输入不受影响，页面显示截图限制。

### `phone_agent_tree`

按需读取无障碍节点，支持：

- `offset`：默认 0。`offset: 0` 创建新观测并重新编号，旧句柄失效；`offset > 0` 只继续当前观测分页。
- `max_nodes`：默认 120，范围 1–200，用于有界遍历和文本预算。
- `interactive_only`：默认 false，只返回可交互节点。

模型只看到 `n0`、`n1` 等短句柄。`isPassword` 节点及其子树文本不会进入结果。句柄默认 TTL 为 120 秒；服务断开、窗口/包名/尺寸/旋转变化都会使其失效。

### `phone_agent_input`

首版动作：

- 节点：`tap`、`long_press`、`set_text`、`scroll`；
- 坐标：`tap`、`long_press`、`swipe`；
- 系统：`back`、`home`、`recents`。

节点动作使用 `node_id`；`set_text` 需要 `text`，`scroll` 需要 `direction`（`forward`、`backward`、`up`、`down`、`left`、`right`）。坐标动作使用归一化 `x`、`y`，`swipe` 还需要 `end_x`、`end_y`。可选 `duration_ms` 范围为 50–2000，但 `long_press` 至少为 500。`tap` 和 `long_press` 只能二选一：提供 `node_id` 或归一化坐标，不能同时提供。

节点动作前会重新校验目标可见性、可用性和指纹；目标失效返回 `stale_handle`，要求重新读树，不会自动点击重新解析出的相似节点。密码节点默认拒绝直接输入。

指纹只判断“句柄是否仍指向同一个逻辑节点”：`isFocused` 和动作集合 `actions` 不进入指纹，因此点击或聚焦输入框后，同一已刷新节点仍可直接 `set_text`，动作是否可用仍由执行层按当前节点校验；`isSelected`、内容（text/description/hint/state）、稳定能力（enabled/editable/clickable/long-clickable/scrollable/checkable/checked）、password、类名、viewId、窗口、包名、尺寸、旋转和 120 秒 TTL 变化仍会让句柄失效。`stale_handle` 会附带发生变化的字段名（只含字段名，不含文本内容）。焦点或动作集合变化不失效不等于动作成功，原生 `performAction` 返回值仍只表示系统接受动作。

坐标一律为 `[0, 1]` 归一化值，原点为截图左上角。模型不需要计算截图像素、物理像素或缩放比。坐标动作必须存在最近一次截图，否则返回 `screenshot_required`；截图与输入之间发生包名、窗口、尺寸或旋转变化时返回 `stale_observation`，不静默重试。

插件把原生结构化错误映射为 `PhoneAgentException(code, message)`。`phone_control_disabled` 已不再使用，统一改为 `phone_agent_disabled`。首版文档明确使用的错误码包括 `phone_agent_disabled`、`screenshot_required`、`stale_observation`、`stale_handle`、`rate_limited`、`screenshot_blocked`、`image_input_unsupported`、`unsupported_platform`、`timeout`、`plugin_unavailable`、`package_not_allowed`、`system_window_denied`、`device_locked` 和 `budget_exceeded`。其余错误码以适配层和插件返回为准。错误信息应给出可执行的下一步，例如重新截图、重新读树、在 Mods 页重新选择工具或请用户检查无障碍服务。

## 测试包白名单

首版只在显式配置的测试包名中开放输入，默认白名单只有私有测试应用的 `com.psyche.kelivo.phoneagent`。该应用与上游正式包 `com.psyche.kelivo` 并存，启动名称为 `Kelivo Agent`，不会覆盖设备上已安装的 Kelivo。白名单位于私有 Mod 的插件 Kotlin 实现中，开发者只能在本仓库修改，不通过设置页或运行时参数开放。

- 非白名单包名下的输入请求返回 `package_not_allowed`，不执行手势或文本输入。
- 系统窗口、权限弹窗和锁屏窗口会被拒绝，例如返回 `system_window_denied` 或 `device_locked`。
- 白名单只限制输入目标，不代表应用内部操作安全；它不能识别“发送、购买、删除”等业务语义。

## 非视觉模型降级

- 模型不支持工具调用时，不添加任何 Mod 工具。
- 支持工具但不支持图片输入时，不暴露 `phone_agent_screenshot`，只保留树和节点输入；依赖截图的坐标动作会被拒绝并返回 `image_input_unsupported`。
- 若仍误调截图，返回结构化文本错误，不生成空图、黑图或无意义占位。
- 视觉能力只在定义接缝中判断；执行 handler 不猜模型能力，图片是否进入请求继续由上游 `ToolResultContent` 决定。

## 隐私与技术护栏

- 仅使用 Android API 30+ 的 `AccessibilityService.takeScreenshot`；服务 XML 声明 `canTakeScreenshot`。
- 截图前按密码节点 bounds 涂黑。该遮挡依赖应用正确标记，自定义 View 或 WebView 可能遗漏，只能称为“尽力而为”。
- 截图字节和密码文本不写入日志或崩溃报告。
- 单 worker 串行执行和手势单飞；每次调用及实际执行前检查锁屏/息屏。
- 服务中断时完成所有 pending 请求，不再执行排队动作。
- 截图、读树、手势和通道调用都有超时；每个生成 handler 最多派发 60 次 `phone_agent_input`，超限返回 `budget_exceeded`，原生另有限速。
- 截图落盘、解码或尺寸校验失败时，适配层会尽力调用 `clearScreenshot` 清理原生坐标观测；清理失败不会覆盖原始截图错误。
- 系统截图限频映射为 `rate_limited`，secure window 等失败映射为 `screenshot_blocked`，不发送黑图。
- Mods 页选择是工具配置，不是无障碍授权；两个服务各自授权、各自启停，Mod 不自动修改系统设置。

这些是降低风险的技术措施，不是绝对安全保证。`performAction` 或手势回调只表示系统调用完成，不表示业务成功；节点校验不能消除所有竞态；已经发出的系统调用无法撤回。

## 本地化

Mods 页、三态选项、服务状态、能力/隐私说明等产品文案按上游标准进入 ARB，并同步所有当前目标语言：

1. 在 `lib/l10n/app_en.arb` 和 `app_zh.arb` 增加同名键，并给每个英文键写 `@key.description`，说明 UI 位置、含义和占位符。
2. 保持英文和中文源键集合一致。
3. 在合成树执行：

```bash
flutter pub get --directory tool/l10n --enforce-lockfile
python3 tool/l10n/translate.py sync
python3 tool/l10n/translate.py check
flutter gen-l10n
```

标准 sync 已由本机免费 Magpie llama-cpp/llama-cpp 完成：23 个键已翻译，`translate.py check` 四个目标语言（ko、ru、tr、zh_Hant）均 0 pending；未使用付费服务。Magpie Python UA 适配只是临时进程环境，不属于 Mod 交付，文档不记录其临时路径作为依赖。

4. 提交或纳入 Mod 输出的内容包含翻译后的 ARB、翻译状态和生成的 Dart 文件；本 Mod 通过 `l10n-generated.patch` 纳入。

工具 schema 和结构化错误继续使用英文，不进入 ARB。

## 已知限制

- 两个无障碍服务可以同时存在于系统中；正常 UI 只限制助手工具选择，不限制系统级服务开关。
- Mods 页的选择是工具配置，不是无障碍授权；服务状态可能滞后于系统设置。
- 已有仅启用 `phone_control` 的助手不会自动迁移，用户需要在 Mods 页手动选择 Phone Agent。
- 后台悬浮胶囊不会触发上游 `phoneControlStarted()`。开启胶囊时，胶囊可能出现在截图中或拦截坐标手势；首版不处理该情况，默认关闭胶囊的验收不代表开启后兼容。
- 密码遮挡、节点校验和窗口检查只能降低风险，不能提供绝对安全保证。
- 不自动识别或可靠拦截“发送、购买、删除”等业务动作；模型是否遵守确认提示不属于硬护栏。
- Mod 工具不进入上游 schema override 和通用审批流程，助手工具选择与限制由 Mod 自己执行。
- 设置搜索不包含 Mods 页；用户需要从移动或桌面设置入口进入。
- 不进入上游工具目录或内置工具商店；Phone Agent 的助手级选择只在 Mods 页完成。
- `supported` 仅表示 API 30+ 截图能力；API 29 可以 ready 并使用树/节点输入，但截图返回 `unsupported_os`，页面显示截图限制。
- 非 Android 平台可以打开 Mods 页，但只显示平台不支持；不要用 `supported=false` 表示平台不可用。
- 首版不支持 `list_apps`、`open_app`、通知栏、快捷设置、多显示器、折叠屏专项适配、MediaProjection 后备截图、树差分或跨观测稳定节点 ID。
- 不支持 Shell、root、Shizuku、录屏或任意文件访问。
- 不承诺任意应用、任意模型或任意任务的成功率。
- `FLAG_SECURE` 的真实窗口测试需要可重复的安全测试界面；若只有错误映射单元测试，必须标记为“真机未验证”。
- ARB 翻译质量依赖上游 l10n 工具和目标语言审查；新增键必须保持英文和中文源键集合一致。

## 维护

### 更新上游基线

```bash
git -C V:/coding/kelivo fetch --prune origin
cd V:/coding/kelivo-private
dart tool/mod_loader.dart rebase-drill --to <新完整 commit>
```

演练通过后，显式更新根 `mods.json` 的 `upstream.commit` 和本目录 `mod.json` 的 `upstreamCommit`，再执行 `plan`、`apply`。Loader 不会自动修改配置，也不会自动执行 `fetch`、`pull`、分支切换、`reset` 或 `clean -fd`。补丁冲突时必须人工处理，不使用模糊补丁或 `--3way` 猜测合并。

### vendored 来源

`mod.json` 的 `vendored` 记录上游参考实现：

```text
android/app/src/main/kotlin/com/psyche/kelivo/PhoneControlService.kt
commit 73afa4ec77cfc9af2efea2487fee8bba1362639d
sha256 3e3ddc9f8c0ca03e5941ee610de8a56e230fd7e5bf78b6659818b9a21b62a1c0
```

`vendored` 是人工审查记录。当前 Loader 只解析该字段，不会自动比对上游文件或阻止基线更新；维护者在更新基线时需要自行检查该文件的 commit 与哈希是否变化，并审查上游修复是否涉及安全、生命周期或错误映射，再决定是否吸收到独立插件。不要为了消除记录差异而直接改哈希。

### 回滚

1. 用私有仓 Git 历史恢复上一版 `mods.json`、`mod.json`、补丁和 overlay/plugin。
2. 执行 `apply`，按旧 `modsetHash` 复用或重建旧合成树。
3. 执行 `verify` 与相关测试。
4. 需要清理时只对指定 `modsetHash` 执行 `clean`，不扩大删除范围。

### 验证命令

Loader 自身：

```bash
dart format --output=none --set-exit-if-changed tool test
dart analyze tool test
dart test
```

合成树内：

```bash
flutter pub get
flutter pub get --directory tool/l10n --enforce-lockfile
dart format --output=none --set-exit-if-changed lib/features/phone_agent lib/features/mods test/features/phone_agent test/features/mods test/features/settings/pages/mods_settings_entry_test.dart integration_test/phone_agent_test.dart
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

最终全量 Flutter 测试为 255 项（254 通过 + 1 Windows 条件跳过）；其中 Phone Agent 103、Mods 16、settings 入口 2。以下命令对应最终合成树验证。

ARB 同步与检查：

```bash
python3 tool/l10n/translate.py sync
python3 tool/l10n/translate.py check
flutter gen-l10n
```

插件是 path 包，根包测试不会自动覆盖，必须单独执行：

```bash
cd dependencies/kelivo_phone_agent
flutter pub get
flutter test
```

Android 测试先确认 Gradle 模块名，再运行对应模块，不预先硬编码可能错误的路径：

```bash
cd android
./gradlew projects
./gradlew :<插件模块>:testDebugUnitTest
./gradlew :app:testDebugUnitTest --tests com.psyche.kelivo.PhoneControlServiceTest
```

真机闭环：

```bash
flutter build apk --debug
flutter test integration_test/phone_agent_test.dart -d <android-device-id>
```

真机至少需要确认：Manifest 合并后出现独立服务及 `canTakeScreenshot`，上游手机控制服务仍存在；Mods 页三态选择与真实工具暴露一致；截图与树为真实工具结果；节点点击、文本输入、滚动和坐标滑动真实生效；旋转、切窗、锁屏、禁用服务和超时返回结构化错误且不挂起；密码树结果不含秘密且截图对应区域已遮挡；日志无密码、截图字节和完整屏幕文本；原始 `phone_control` 单元测试与功能不受影响。

## 验证状态

### 本轮节点重验修正（当前实现）

- 合成树：`V:/coding/kelivo-private/.tower/worktrees/wt-1/.build/worktrees/7593c21b5f9da01f`
- `modsetHash`：`7593c21b5f9da01fb8b8c4dfe167d892a940efe4a1caf591b772fbe83b6b6f7d`
- Mod 版本：`0.2.0`
- Loader verify：通过

已通过：

- Loader format/analyze 通过；Loader 165 项测试通过。
- 新合成树 `dart format` 与 `dart analyze --fatal-infos lib test integration_test tool` 通过。
- Phone Agent 103 项、Mods 16 项、settings 入口 2 项通过。
- 插件 Dart 17 项；插件 Kotlin 66 项；上游 `PhoneControlServiceTest` 49 项。
- 修正前用同一套插件测试复现问题：61 项中 2 项 focus 用例失败（`gaining focus keeps a handle reusable for set_text`、`losing focus keeps a handle reusable`）。
- 新增插件测试覆盖：focus false→true 后复用句柄并 `set_text`、focus true→false 后复用、action-only 变化仍可复用、selected-only 变化仍返回 `stale_handle`、稳定能力字段（`isScrollable`）变化仍拒绝、禁用节点、句柄 TTL、含 NUL 文本只报告 `text` 字段名，以及 `performNodeAction` 在动作从当前节点移除时返回 `action_unavailable` 且不执行 `beforeAction`/`perform`。
- API 35 模拟器（`emulator-5554`）官方集成测试退出码 0，2 个用例通过：真实截图、读树、节点点击、坐标滑动（原生接受并完成手势）、节点滚动（列表真实滚动）、聚焦后同一句柄 `set_text`、二次读树，以及 Mods 页真实服务状态与三态选择。
- API 29 真机（`357784090209204`）官方集成测试退出码 0，2 个用例通过：截图按预期返回 `unsupported_os`、读树、节点点击、节点滚动（列表真实滚动）、聚焦后同一句柄 `set_text`、二次读树，以及 Mods 页真实服务状态与三态选择。
- 设备结果对应提交 `698cace` 的运行时语义；R1 审查后仅调整诊断编码、提取纯 JVM 前置校验接缝、补测试和文档，未重复双 API 设备回归。
- 产品 debug APK：`V:/coding/kelivo-private/.tower/worktrees/wt-1/.build/worktrees/7593c21b5f9da01f/build/app/outputs/flutter-apk/app-debug.apk`，181369230 字节，SHA-256 `3ea30ee9b46342305cf11e0574b76def9a42f23abe62dd3536b664dc4ec5caeb`。

集成测试的坐标手势验证边界：`flutter_test` 的 `LiveTestWidgetsFlutterBinding` 默认 `shouldPropagateDevicePointerEvents = false`，设备指针事件不转发给 widget 树，因此测试只能断言坐标手势被原生接受并完成，不能断言应用侧滚动效果；API 35 用例在坐标滑动后用无障碍节点滚动验证列表真的滚动。该限制只影响测试可观测性，不改变产品行为。

安装测试包和部分收尾的 force-stop 可能清除系统无障碍授权，测试会打印 `PHONE_AGENT_WAITING_FOR_SERVICE` 并等待约 300 秒，需要在窗口内通过系统界面重新启用 Kelivo Phone Agent；每轮都要检查真实绑定状态，不要假设一定被清除或一定保留。

### 焦点修正前的历史验收记录（不代表当前实现）

- Loader 165 项测试；`dart tool/mod_loader.dart verify` 通过。
- Flutter 255 项：254 通过，1 项 Windows 符号链接测试按条件跳过；其中 Phone Agent 103、Mods 16、settings 入口 2。
- 插件 Dart 17 项；插件 Kotlin 55 项；上游 `PhoneControlServiceTest` 49 项。
- 根项目、markstream 和插件静态分析通过。
- 本地化：本机免费 Magpie llama-cpp/llama-cpp 翻译 23 个键；`translate.py check` 四个目标语言（ko、ru、tr、zh_Hant）均 0 pending；`l10n-generated.patch` 已生成；未使用付费服务。Magpie Python UA 适配只是临时进程环境，不属于 Mod 交付，文档不记录其临时路径作为依赖。
- API 29 真机官方测试退出码 0，两个场景：
  1. 设置 → Mods → 真实 enabled/connected/API 29 状态 → 助手选择 Phone Agent 且与原生互斥。
  2. 读树、节点点击、`set_text`、节点滚动、二次读树；截图按预期返回 `unsupported_os`。
- 当时合成树为 `V:/coding/kelivo-private/.build/worktrees/4ed083cf5fe7dda8`；旧产品 APK 为 181354638 字节，SHA-256 `af67f4285bef9e3d1093c6433f42669a8c84b8bee99b6397f68dfd91e1c60ceb`，仅作历史记录。

仍明确未验证，不宣称第二阶段全部完成：

- 物理 API 30+ 真机上的截图与坐标手势未验证；API 35 模拟器已验证截图、坐标手势原生接受和节点滚动，坐标手势的 UI 滚动效果受 integration_test 绑定限制。
- VLM 固定任务和 VLM 图片链路未验证。
- 真实 `FLAG_SECURE` 窗口未验证。
- 真机旋转、切窗、锁屏、禁用服务、超时等其他异常路径未验证。
- 未执行带合法签名配置的 release 构建。

以上未验证项不能用编译或单元测试代替真机结论。
