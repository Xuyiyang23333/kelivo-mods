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

> 本轮 M22（权限弹窗保守收尾，API35 模拟器）：按用户同意，不可识别权限弹窗仍返回 `no_window`，错误消息只做条件式人工提示（“如果看到系统权限弹窗，请人工处理/取消，再返回测试应用”），不声称识别具体权限弹窗；可取得系统包名的窗口仍返回 `system_window_denied`，错误优先级、读树/截图密码遮挡、输入边界和白名单不变。M20（窗口 root 补全）与 M21（事件来源包名）均已在 API35 设备上证伪并 abandoned，未合并生产代码。异常测试改为宿主 `dumpsys` 独立确认真实 `GrantPermissionsActivity` 后直接 tap/back/截图断言 `no_window` + 提示，不再因 `root=null` skip，也不把任意 `no_window` 当通过。记录见 `docs/phone-agent-plan.md` 9.3.4/9.3.5/9.3.6。
>
> 上一轮 M19（权限窗口真实验证，API35 模拟器）：真实 `com.google.android.permissioncontroller` 弹窗已出现；上一轮 90 秒未出现的原因是设备息屏时 `am start` 不获前台焦点，唤醒后立即出现。弹窗期间服务 `rootInActiveWindow` 为 null，读树实测返回 `no_window`，输入按 `currentWindow` 前置 guard 推导为 `no_window`（M19 未执行 tap/back），`system_window_denied` 未产生，输入仍被拒绝、权限未授予；历史记录见 `docs/phone-agent-plan.md` 9.3.3。
>
> 本轮物理 MIUI API31 验收（`llama-cpp/llama-cpp` 与 magpie `mistral/deepseek-v4-1-flash-1017`）：真实截图/读树/节点输入/滚动、物理 `FLAG_SECURE`（成功黑图，清除后恢复）、旋转失效均通过；`llama-cpp/llama-cpp` 用归一化坐标 tap 打开抽屉/Settings/Search，1017 用归一化坐标 swipe 让 Sponsor 从不可见变为可见，并完成图片请求与像素专属视觉确认；官方测试一次 `+1 -1`、EXIT=1（聚焦后 `set_text` `stale_handle`），一次 `+2`、EXIT=0，属间歇性、根因未确认；`llama-cpp/llama-cpp` 的完整坐标 swipe 仍未验证。M22 当前交付的合成树、`modsetHash`、APK 大小/SHA-256 和 manifest 检查记录在 `docs/phone-agent-plan.md` 9.3.6 与 `docs/next-session-handoff.md`；本段物理 MIUI 验收历史见 9.3.2/9.4.2。本 README 不参与 Mod treeHash（`tool/src/config.dart` 只散列 `mod.json`、声明的 patches 和 copy 源，根 README 不在 copy 列表），参与的是 `plugin/README.md`（`copy[7]/README.md`）；因此本文件不写当前数字只为避免与 docs 重复，而改动 plugin README 会改变交付哈希。
>
> 上一轮 M10（API35 FLAG_SECURE/异常路径）：完整异常套件 `+5 ~1`、EXIT=0；权限窗口未验证。整屏 `takeScreenshot` 不保证对 `FLAG_SECURE` 报错，可能返回成功黑图或内容图；不保证检测、不承诺不发送黑图。记录见 `docs/phone-agent-plan.md` 9.3.1。
>
> 上一轮 VLM 验收（历史，API35 模拟器）：使用当时的 debug APK 与 magpie `llama-cpp/llama-cpp` 完成截图 → 图片请求 → 应用内固定任务 → 跨新用户轮次历史图片回放；该轮沿用旧树 `V:/coding/kelivo-private/.tower/worktrees/wt-6/.build/worktrees/5f0be65f98bb04e5` 和旧 APK 181369230 字节 / SHA-256 `3ea30ee9b46342305cf11e0574b76def9a42f23abe62dd3536b664dc4ec5caeb`，只作历史记录，不代表当前实现。该轮未验证的真实 `FLAG_SECURE` 已由 M10 在 API35 模拟器补充；物理 API30+ 的 VLM 与坐标手势已由本轮物理 MIUI 验收覆盖；权限窗口、原生超时和签名 release 仍未验证。
>
> 上一轮节点重验修正（历史）：旧树 `V:/coding/kelivo-private/.tower/worktrees/wt-1/.build/worktrees/7593c21b5f9da01f`，Loader verify 通过；当时 Loader 165、插件 Kotlin 66、插件 Dart 17、上游 PhoneControl 49、Phone Agent 103、Mods 16、settings 入口 2 通过；API 35 模拟器与 API 29 真机官方集成测试均退出码 0。

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

整屏 `takeScreenshot` 不保证对 `FLAG_SECURE` 报错：secure 内容可能以黑色区域出现在成功截图中。工具不检测 secure window，也不根据像素猜黑图；正常黑色页面保留。黑图时优先读树，不要凭黑图猜坐标。平台明确报错时返回 `screenshot_blocked`，不发送图片或图片 metadata。

### `phone_agent_tree`

按需读取无障碍节点，支持：

- `offset`：默认 0。`offset: 0` 创建新观测并重新编号，旧句柄失效；`offset > 0` 只继续当前观测分页。
- `max_nodes`：默认 120，范围 1–200，用于有界遍历和文本预算。
- `interactive_only`：默认 false，只返回可交互节点。

模型只看到 `n0`、`n1` 等短句柄。`isPassword` 节点及其子树文本不会进入结果。句柄默认 TTL 为 120 秒；服务断开、窗口/包名/尺寸/旋转变化都会使其失效。secure 窗口的树在 API35 夹具上可读，但不是绝对保证；密码字段、自定义 View 和窗口变化仍会影响树。截图黑化时优先读树。

### `phone_agent_input`

首版动作：

- 节点：`tap`、`long_press`、`set_text`、`scroll`；
- 坐标：`tap`、`long_press`、`swipe`；
- 系统：`back`、`home`、`recents`。

节点动作使用 `node_id`；`set_text` 需要 `text`，`scroll` 需要 `direction`（`forward`、`backward`、`up`、`down`、`left`、`right`）。坐标动作使用归一化 `x`、`y`，`swipe` 还需要 `end_x`、`end_y`。可选 `duration_ms` 范围为 50–2000，但 `long_press` 至少为 500。`tap` 和 `long_press` 只能二选一：提供 `node_id` 或归一化坐标，不能同时提供。

节点动作前会重新校验目标可见性、可用性和指纹；目标失效返回 `stale_handle`，要求重新读树，不会自动点击重新解析出的相似节点。密码节点默认拒绝直接输入。

指纹只判断“句柄是否仍指向同一个逻辑节点”：`isFocused` 和动作集合 `actions` 不进入指纹，因此点击或聚焦输入框后，同一已刷新节点仍可直接 `set_text`，动作是否可用仍由执行层按当前节点校验；`isSelected`、内容（text/description/hint/state）、稳定能力（enabled/editable/clickable/long-clickable/scrollable/checkable/checked）、password、类名、viewId、窗口、包名、尺寸、旋转和 120 秒 TTL 变化仍会让句柄失效。`stale_handle` 会附带发生变化的字段名（只含字段名，不含文本内容）。焦点或动作集合变化不失效不等于动作成功，原生 `performAction` 返回值仍只表示系统接受动作。

`stale_handle` 的前置重验失败会按 `refresh()` → 可见性 → 可用性短路，并在消息中追加固定诊断标识 `refresh_failed`、`not_visible` 或 `not_enabled`；标识不含节点文本、类名、viewId 或其他内容，错误码和通过条件都不变。诊断只用于区分失败来源，不代表根因已修复，也不会自动重读或重试。

坐标一律为 `[0, 1]` 归一化值，原点为截图左上角。模型不需要计算截图像素、物理像素或缩放比。坐标动作必须存在最近一次截图，否则返回 `screenshot_required`；截图与输入之间发生包名、窗口、尺寸或旋转变化时返回 `stale_observation`，不静默重试。secure 窗口可能产生黑图；不要用黑图坐标，改用 `phone_agent_tree` 的节点句柄。

输入错误码优先级固定为：空包名 `no_window` → 系统包 `system_window_denied` → 非白名单包 `package_not_allowed` → 白名单内句柄/截图校验（`stale_handle` / `stale_observation`）。因此系统窗口或非白名单应用在前台时，即使句柄已失效，也先返回包名策略错误。`home`/`recents` 执行后前台会离开白名单，后续输入（包括 `back`）会被拒绝，模型无法自行回到测试应用，需要用户或宿主把应用切回前台。

权限弹窗在 API35 实测没有可访问 root：活动/聚焦弹窗窗口 `hasRoot=false`、`pkg=null`，`AccessibilityWindowInfo` 没有包名字段，服务也收不到 `permissioncontroller` 的 `TYPE_WINDOW_STATE_CHANGED`（M20/M21 已证伪窗口 root 与事件来源包名两种识别机制）。因此该场景读树、截图和输入保持 `no_window`，错误消息只做条件式人工提示（“如果看到系统权限弹窗，请人工处理/取消，再返回测试应用”），不声称识别具体权限弹窗；可取得系统包名的窗口仍返回 `system_window_denied`。该保守收尾不改变错误优先级、读树/截图密码遮挡或输入边界。

插件把原生结构化错误映射为 `PhoneAgentException(code, message)`。`phone_control_disabled` 已不再使用，统一改为 `phone_agent_disabled`。首版文档明确使用的错误码包括 `phone_agent_disabled`、`screenshot_required`、`stale_observation`、`stale_handle`、`rate_limited`、`screenshot_blocked`、`image_input_unsupported`、`unsupported_platform`、`timeout`、`plugin_unavailable`、`package_not_allowed`、`system_window_denied`、`device_locked` 和 `budget_exceeded`。其余错误码以适配层和插件返回为准。错误信息应给出可执行的下一步，例如重新截图、重新读树、在 Mods 页重新选择工具或请用户检查无障碍服务。

## 测试包白名单

首版只在显式配置的测试包名中开放输入，默认白名单只有私有测试应用的 `com.psyche.kelivo.phoneagent`。该应用与上游正式包 `com.psyche.kelivo` 并存，启动名称为 `Kelivo Agent`，不会覆盖设备上已安装的 Kelivo。白名单位于私有 Mod 的插件 Kotlin 实现中，开发者只能在本仓库修改，不通过设置页或运行时参数开放。

- 非白名单包名下的输入请求返回 `package_not_allowed`，不执行手势或文本输入。
- 可取得系统包名的系统窗口和权限弹窗下的输入请求返回 `system_window_denied`；无可访问 root 的权限弹窗读树、截图和输入保持 `no_window`，消息只做条件式人工提示；锁屏/息屏时读树、截图和输入都返回 `device_locked`。
- 白名单和系统窗口拒绝只约束输入；读树和截图仍可观察当前前台窗口，这是 VLM 需要的行为，不能写成“系统窗口不可读、不可截图”。
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
- 系统限频映射为 `rate_limited`；平台明确返回的截图错误映射为 `screenshot_blocked`。整屏 `takeScreenshot` 不保证对 `FLAG_SECURE` 报错，secure 内容可能以黑色区域出现在成功截图中；不做像素启发式，不承诺不发送黑图，正常黑色页面保留。
- 平台明确报错时不得把图片或图片 metadata 交给模型；成功黑图只作为普通截图，模型应优先读树、不凭黑图猜坐标。
- `FLAG_SECURE` 只阻止截图，不隐藏无障碍树，也不阻止读树和输入；输入边界由包名白名单决定。secure 窗口的树在 API35 夹具上可读，但不是绝对保证。
- debug 构建包含仅供测试的 `SecureWindowFixtureActivity`，用于权限弹窗、同包切窗和纯色像素校验；它不修改上游宿主文件，release 不编译、不合并。宿主侧不同 UID 的独立夹具 APK（`com.kelivo.phoneagent.securefixture`，不属于 Mod 交付）用于排除 UID 因素并验证文档化行为；API35 实测同 UID/不同 UID 都返回成功黑图，UID 不是原因。
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
- 整屏 `takeScreenshot` 不保证对 `FLAG_SECURE` 报错；secure 内容可能以黑色区域出现在成功截图中。不根据像素猜 secure，不承诺不发送黑图，正常黑色页面保留。
- 平台明确报错时不得把图片或 metadata 交给模型；成功黑图只作为普通截图，模型应优先读树、不凭黑图猜坐标。
- `FLAG_SECURE` 不阻止读树和输入；API35 夹具树可读，但不是绝对保证；密码字段、自定义 View、窗口变化仍会影响树；非白名单输入仍被拒绝。
- `system_window_denied` / `package_not_allowed` 只约束输入；读树和截图仍可观察系统窗口、权限弹窗和其他应用。无可访问 root 的权限弹窗读树/截图/输入均为 `no_window` 并带条件式人工提示；`system_window_denied` 仍用于可取得系统包名的窗口。
- `home`/`recents` 后前台离开白名单，后续输入（包括 `back`）被拒绝，模型无法自行恢复，需要用户或宿主切回测试应用。
- `SecureWindowFixtureActivity` 只是 debug 测试夹具，不是产品能力；release 不包含该 Activity。
- API35 模拟器已验证旋转、home/recents、锁屏、服务禁用/重启和权限弹窗保守拒绝（读树/截图/输入均 `no_window` + 条件式人工提示，未执行手势/系统导航）；物理 MIUI API31 真机已验证旋转和物理 `FLAG_SECURE`，但锁屏、home/recents、服务禁用/重启和权限弹窗未在物理设备运行，不能从模拟器结果推断；原生超时仍无法在设备上确定性触发。
- VLM 图片链路、Kelivo 应用内固定任务和跨新用户轮次历史图片回放已在 API 35 模拟器用 magpie `llama-cpp/llama-cpp` 验证；物理 MIUI API31 真机由 `llama-cpp/llama-cpp` 验证归一化坐标 tap（打开抽屉/Settings/Search），由 magpie `mistral/deepseek-v4-1-flash-1017` 验证真实图片请求、归一化坐标 swipe 的 UI 效果和像素专属视觉确认；`llama-cpp/llama-cpp` 的物理完整坐标 swipe 未验证；只验证这些模型与设备，不承诺任意模型或设备。
- 物理设备官方测试在 M16 出现一次间歇性 `set_text` `stale_handle`（`The target node changed`，refresh/可见/可用前置分支），另一次全通过；M17 用同一官方测试连续 4 轮均为 `+2`、EXIT=0，未复现，也未触发 `refresh_failed`/`not_visible`/`not_enabled`。根因未确认、未修复，不写成稳定通过或根因修复。
- magpie 的模型能力标注可能变化，图片与工具能力需每次实测；Kelivo 手动勾选图片只是测试配置，不构成模型能力保证。
- `settings put secure` 预配置仅限用户明确授权的该台测试设备，不是产品能力，也不代表其他设备可以自动写入无障碍授权；每轮必须记录并恢复当轮真实原值，不能按历史空串+0 强制关闭。
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

上一轮定向验证（历史）：Phone Agent 105、Mods 16、settings 入口 2、上游 `tool_result_content` 14 通过 + 1 Windows 条件跳过；该轮未重跑全量 Flutter 套件和双 API 设备回归，理由是该轮只改文档和 overlay 测试。以下命令仍为当前验证入口。

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
flutter test integration_test/phone_agent_exception_test.dart -d <android-device-id>
```

异常套件需要宿主/CU 在测试打印标记后启动 debug 夹具、切换 `FLAG_SECURE`、拉起权限弹窗、锁屏和开关无障碍服务；测试只轮询并断言结果，不写系统授权。夹具命令和场景见 `docs/phone-agent-plan.md` 9.3.1。

真机至少需要确认：Manifest 合并后出现独立服务及 `canTakeScreenshot`，上游手机控制服务仍存在；Mods 页三态选择与真实工具暴露一致；截图与树为真实工具结果；节点点击、文本输入、滚动和坐标滑动真实生效；旋转、切窗、锁屏、禁用服务和超时返回结构化错误且不挂起；密码树结果不含秘密且截图对应区域已遮挡；日志无密码、截图字节和完整屏幕文本；原始 `phone_control` 单元测试与功能不受影响。

## 验证状态

### 本轮物理 MIUI API31 验收（magpie `mistral/deepseek-v4-1-flash-1017`）

本轮在用户提供的物理设备上完成 Phone Agent 的物理验收。M22 当前交付的合成树、`modsetHash`、APK 大小/SHA-256 和 manifest 隔离记录在 `docs/phone-agent-plan.md` 9.3.6 与 `docs/next-session-handoff.md`；本段物理 MIUI 验收历史见 9.3.2/9.4.2。本 README 不参与 Mod treeHash（`tool/src/config.dart` 只散列 `mod.json`、声明的 patches 和 copy 源，根 README 不在 copy 列表）；参与的是 `plugin/README.md`（`copy[7]/README.md`），改动它会改变交付哈希。

- 设备：Redmi K30 5G（`1960cd68`，picasso），Android 12 / API 31，1080x2400，density 440，MIUI V13.0.3.0.SGICNXM。用户提供该测试设备并授权安装应用、操作界面。
- 授权边界：用户明确授权仅在该测试设备上用 `settings put secure` 预配置 Phone Agent 服务；M16 历史轮原始 `enabled_accessibility_services` 为空串、`accessibility_enabled=0`，M17 轮原始值为 Phone Agent 组件 + `accessibility_enabled=1`。每轮必须记录并恢复当轮真实原值，不能按历史空串+0 强制关闭。该例外只适用于本设备与 Phone Agent，不改变产品自动授权边界，其他设备默认仍禁止自动写系统授权。
- 安装与状态：独立测试包 `com.psyche.kelivo.phoneagent` 安装成功，未覆盖上游 Kelivo；服务 enabled && connected；Mods 页三态选择与真实工具暴露一致。
- 官方 `phone_agent_test.dart` 在 M16 物理 API31 上两次结果不同：第一次 `+1 -1`、EXIT=1，聚焦后 `set_text` 返回 `stale_handle`（`The target node changed`，属 `ObservationRegistry` 的 refresh/isVisibleToUser/isEnabled 前置分支，不是旧聚焦指纹路径）；第二次 `+2`、EXIT=0。属间歇性，根因未确认、未修复，不能写成稳定通过。
- M17 诊断轮：同一官方测试连续 4 轮均为 `+2`、`All tests passed!`、EXIT=0，未出现 `stale_handle`，也未触发 `refresh_failed`/`not_visible`/`not_enabled`。每轮安装后组件被清除，宿主只恢复 Phone Agent 组件，轮末恢复当轮真实原值。4 轮未复现不等于根因修复；新诊断标识目前只有 JVM 单元测试覆盖。
- 物理 `FLAG_SECURE`：secure 夹具截图返回成功黑图（平台行为），清除 flag 后恢复真实截图；旋转后旧句柄 `stale_handle`、旧截图坐标 `stale_observation`，新树/新截图成功。
- 坐标 UI 效果（真实产品 UI，不是 integration_test 回调）：在 `llama-cpp/llama-cpp` 轮，归一化坐标 tap 真实打开抽屉、Settings 和 Search，`set_text Phone` 成功；后续 swipe 因网关故障未完成，该模型的完整坐标 swipe 仍属未验证。
- 指定模型 `mistral/deepseek-v4-1-flash-1017`（不是 0731，也不是 Bonsai）：magpie 侧该模型未标图片输入，Kelivo 手动勾选图片后真实请求全部 200，响应头 `x-magpie-model` / `x-magpie-provider` 与请求一致；工具集为 `read_file` + 三个 `phone_agent_*`，无 `snapshot_id`、无 `phone_control`；截图 720x1600，screen 1080x2400。
- 坐标 swipe：`{x:0.5,y:0.8,end_x:0.5,end_y:0.3,duration_ms:400}` 一次后 Sponsor 从不可见变为可见，前后 PNG 证实，属物理坐标 UI 效果，不是回调推断。
- 像素专属视觉证据：新建无历史会话，只允许一次截图、禁止 tree/input，提示不透露颜色或文本；1017 回答 `bright cyan (light blue)` 和 `PHONE_AGENT_SECURE_FIXTURE`，与保存 PNG 的 rgb(0,200,255) 及完整文字一致。该轮请求只有一个截图 tool_call，`image_url` 为 `data:image/png;base64,<omitted 39204 chars>`，请求全文不含 `PHONE_AGENT`，构成后端视觉消费的直接支持证据，但不是对模型内部机制的绝对证明。
- 边界：magpie 的模型能力标注可能变化，每次都要实测图片与工具能力；网关故障（`api_error` / 空响应）与坐标动作失败分开记录，不把外部网关失败写成产品缺陷；第一轮过渡帧可能出现黑色区域或文本裁切，后续截图应等界面稳定。
- 产品 APK：`flutter test` 会覆盖树内 `build/app/outputs/flutter-apk/app-debug.apk` 为测试入口构建；产品 APK 必须在干净合成树显式 `flutter build apk --debug` 重新生成并重新计算大小与 SHA-256，不能沿用旧哈希，也不能把测试入口构建当产品。
- 未验证：`llama-cpp/llama-cpp` 的完整坐标 swipe、权限窗口、原生超时、签名 release、`stale_handle` 根因；物理设备未运行锁屏、home/recents、服务中断，不能从模拟器结果推断。

### API35 FLAG_SECURE/异常路径（上一轮）

- 该轮交付的合成树、`modsetHash`、APK 大小/SHA-256 和 manifest 隔离记录在 `docs/phone-agent-plan.md` 9.3.1 与 `docs/next-session-handoff.md`。本 README 不参与 Mod treeHash（根 README 不在 `mod.json` 的 copy 列表）；参与的是 `plugin/README.md`（`copy[7]/README.md`）。
- 契约：整屏 `takeScreenshot` 不保证对 `FLAG_SECURE` 报错；API35 实测 secure 夹具该轮返回成功黑图（平均 RGB 约 2,0,2），更早一轮也曾返回成功内容图（平均亮度约 191）；契约只承诺“可能黑化”，不保证黑图或检测；不做像素启发式；平台明确报错时 `screenshot_blocked` 且无图片。
- API35 完整异常套件：**`+5 ~1`，`All tests passed!`，EXIT=0**；通过 secure、旋转、home/recents、锁屏、服务禁用/重启；权限窗口明确跳过（未验证）。
- 服务禁用：禁用前启动 1000 个只读 pending 请求，日志 `PHONE_AGENT_SERVICE_PENDING_BATCH: size=1000 elapsed=3252ms codes=interrupted,ok`，原 Future 在超时前以 `interrupted` 完成。
- 锁屏：同一锁屏窗口分别调用 tree/screenshot/input，均断言 `device_locked`；截图错误无图片 metadata；解锁后旧句柄 `stale_handle`，新树/新截图成功。
- 历史失败（保留）：`41e33b6f115e54bc` 完整套件 `+2 ~1 -3`、EXIT=1（secure/锁屏/服务因测试辅助/宿主协调失败）；修正后完整套件 `+5 ~1`、EXIT=0。
- API35 官方测试：2 项通过，EXIT=0；API29 官方测试：2 项通过，EXIT=0（截图 `unsupported_os`）。
- debug/release manifest 隔离：debug 含 `SecureWindowFixtureActivity`，release 不含该夹具；具体构建记录见上述不参与 Mod treeHash 的文档。
- 该轮未验证：权限窗口、物理真机、签名 release、原生超时、`stale_handle` 根因；物理真机部分已由本轮物理 MIUI 验收覆盖（锁屏、home/recents、服务中断仍未在物理设备运行）。

### 上一轮节点重验修正（历史结果）

以下为节点重验修正轮的结果；当前物理 MIUI 验收见“本轮物理 MIUI API31 验收”一节。

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
- 前置重验诊断测试覆盖：`refresh()` 为 false 时 `stale_handle` 消息含 `refresh_failed`、`isVisibleToUser` 为 false 时含 `not_visible`、`isEnabled` 为 false 时含 `not_enabled`；三项均断言不含节点文本和另外两个标识，刷新失败优先于可见性/可用性判断。
- API 35 模拟器（`emulator-5554`）官方集成测试退出码 0，2 个用例通过：真实截图、读树、节点点击、坐标滑动（原生接受并完成手势）、节点滚动（列表真实滚动）、聚焦后同一句柄 `set_text`、二次读树，以及 Mods 页真实服务状态与三态选择。
- API 29 真机（`357784090209204`）官方集成测试退出码 0，2 个用例通过：截图按预期返回 `unsupported_os`、读树、节点点击、节点滚动（列表真实滚动）、聚焦后同一句柄 `set_text`、二次读树，以及 Mods 页真实服务状态与三态选择。
- 设备结果对应提交 `698cace` 的运行时语义；R1 审查后仅调整诊断编码、提取纯 JVM 前置校验接缝、补测试和文档，未重复双 API 设备回归。
- 产品 debug APK：`V:/coding/kelivo-private/.tower/worktrees/wt-1/.build/worktrees/7593c21b5f9da01f/build/app/outputs/flutter-apk/app-debug.apk`，181369230 字节，SHA-256 `3ea30ee9b46342305cf11e0574b76def9a42f23abe62dd3536b664dc4ec5caeb`。

集成测试的坐标手势验证边界：`flutter_test` 的 `LiveTestWidgetsFlutterBinding` 默认 `shouldPropagateDevicePointerEvents = false`，设备指针事件不转发给 widget 树，因此测试只能断言坐标手势被原生接受并完成，不能断言应用侧滚动效果；API 35 用例在坐标滑动后用无障碍节点滚动验证列表真的滚动。该限制只影响测试可观测性，不改变产品行为。

安装测试包和部分收尾的 force-stop 可能清除系统无障碍授权，测试会打印 `PHONE_AGENT_WAITING_FOR_SERVICE` 并等待约 300 秒，需要在窗口内通过系统界面重新启用 Kelivo Phone Agent；每轮都要检查真实绑定状态，不要假设一定被清除或一定保留。

### 上一轮 VLM 验收（历史，API 35 模拟器，magpie `llama-cpp/llama-cpp`）

- 设备：API 35 模拟器 `emulator-5554`（Android 15，内部屏幕 1080x2424）；该轮产品 APK 为 181369230 字节，SHA-256 `3ea30ee9b46342305cf11e0574b76def9a42f23abe62dd3536b664dc4ec5caeb`（该轮未重建）。
- 模型：magpie 网关 `llama-cpp/llama-cpp`（Text、Image → Text、Tools）；应用内 provider 地址 `http://10.0.2.2:3425/v1`，UI 勾选 Image 输入和 Tools；局域网访问由用户开启，密钥未修改、未读取、未记录。Mods 页 Default Assistant 选择 Phone Agent，服务 enabled && connected，API 35 ready。
- 工具暴露：REQ27 为 `read_file` + 三个 `phone_agent_*`，无 `phone_control`、无重复、无 `snapshot_id`、`additionalProperties=false`。
- 图片链路：REQ28（Request Log ID28）携带 `image 713x1600`、`screen 1080x2424`、package `com.psyche.kelivo.phoneagent`，`image_url=data:image/png;base64,<omitted 185028 chars>`、`detail=high`；响应头 `x-magpie-model=llama-cpp/llama-cpp`；模型读出 `3:00 / New Chat / llama-cpp/llama-cpp (Magpie VLM)`。
- 固定任务：在 Kelivo 应用内 Settings（不是 Android 系统设置）完成，全程 package 为 `com.psyche.kelivo.phoneagent`，未用 adb 代替模型输入；tree 22 节点 → 首次 tap n3 返回一次 `stale_handle`（No current tree observation）→ 重读树后 tap 成功 → `set_text n2 Phone` 成功 → UI `1 result / Phone Control / Settings`；随后 n4 ScrollView `forward` 成功，UI 滚到 `Sponsor`，模型回答 `Sponsor`。
- 跨新用户轮次历史图片回放：REQ42（15:36:58）未调用工具、未重新截图，请求从历史工具 metadata 带回同一 `image_url`（185028 omitted chars）；模型回答输入框占位 `Type a message for AI` 和蓝色圆形内白色方块按钮，与保存的 713x1600 PNG 像素核对一致。图片进入上下文后上游额外暴露 `read_chat_image`，不是 Mod 重复或 `phone_control`。
- 异常：一次 `stale_handle`（`No current tree observation`，代码路径 tree==null）未复现、未找到 native 日志、根因未确认、未修复；重读树后恢复，可能来源只是假设，不写成事实。
- 证据边界：跨用户轮次回放已通过；该轮未验证物理真机 VLM、坐标手势 UI 效果和签名 release；真实 `FLAG_SECURE`、旋转、home/recents、锁屏、服务禁用/重启已由后续 M10 在 API35 模拟器补充（见“API35 FLAG_SECURE/异常路径（上一轮）”），物理真机的 VLM 与坐标手势已由本轮物理 MIUI 验收覆盖，但不代表其他 Android 版本或设备。
- 该轮自动检查：只读 `plan` 得到同一 `modsetHash`，Loader verify 通过；未修改产品代码、测试、`mod.json`、schema 或插件，未重跑测试、未重建合成树或 APK；更早一轮的 Phone Agent 105、Mods 16、settings 入口 2、上游 `tool_result_content` 14 通过 + 1 Windows 条件跳过继续有效。

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

- 该历史时点物理真机的截图与坐标手势未验证；后续 M10 在 API35 模拟器补齐截图与异常路径，本轮物理 MIUI 验收补齐物理真机的截图、节点输入、坐标 tap/swipe 的 UI 效果。
- 该历史时点物理真机的 VLM 固定任务未验证；API 35 模拟器已用 magpie `llama-cpp/llama-cpp` 完成图片链路、应用内固定任务和跨新用户轮次历史图片回放，本轮物理 MIUI 用 `mistral/deepseek-v4-1-flash-1017` 完成真实图片请求与像素专属视觉确认。
- 当时真实 `FLAG_SECURE` 窗口未验证；后续 M10 已在 API35 模拟器补充，物理 MIUI 也已验证物理 secure 行为，见“API35 FLAG_SECURE/异常路径（上一轮）”与“本轮物理 MIUI API31 验收”。
- 该历史时点真机旋转、切窗、锁屏、禁用服务、超时等异常路径未验证；物理 MIUI 已补齐旋转，锁屏、home/recents、服务中断仍未在物理设备运行，原生超时仍未设备验证。
- 一次 `stale_handle`（`No current tree observation`）未复现、根因未确认、未修复；重读树后恢复。M16 物理设备又出现一次间歇性 `set_text` `stale_handle`（`The target node changed`），同样未确认根因；M17 连续 4 轮官方测试未复现，也未触发新诊断标识，不能据此宣称根因修复。
- 未执行带合法签名配置的 release 构建。
- 只验证 magpie `llama-cpp/llama-cpp`、`mistral/deepseek-v4-1-flash-1017` 与对应设备，不承诺任意模型或设备。

以上未验证项不能用编译或单元测试代替真机结论。
