# AGENTS.md

## 仓库用途

本仓库是 Kelivo 的私有、编译前源码 Mod 工作区，不提交到上游，也不面向最终用户提供运行时插件平台。

当前任务分为两个独立阶段：

1. 先实现并验收通用 Mod Loader，见 `docs/mod-loader-plan.md`。
2. Loader 验收后再实现 `phone_agent` Mod，见 `docs/phone-agent-plan.md`。UI/选择契约改造已完成并通过最终验收；当前 `phone_agent` Mod 版本 0.2.0，VLM 图片链路、Kelivo 应用内固定任务和跨新用户轮次历史图片回放已在 API 35 模拟器用 magpie `llama-cpp/llama-cpp` 验证；物理 MIUI API31 真机由 `llama-cpp/llama-cpp` 验证归一化坐标 tap（打开抽屉/Settings/Search），由 magpie `mistral/deepseek-v4-1-flash-1017` 验证真实图片请求、归一化坐标 swipe 的 UI 效果和像素专属视觉确认，`llama-cpp/llama-cpp` 的完整坐标 swipe 未验证。M17 已为 `stale_handle` 增加 `refresh_failed`/`not_visible`/`not_enabled` 前置诊断，并在物理 MIUI 上用同一官方测试连续 4 轮通过、未复现历史间歇性失败，诊断标识未在设备触发，根因仍未确认；未验证项见计划。

不要把两个阶段的原则、非目标或验收标准混写。完成当前阶段前，不要提前扩张下一阶段范围。

## 目录与修改边界

- `tool/`：Loader CLI 与实现。
- `test/`：Loader 自身的 Dart 测试。
- `patches/`：Loader 自有的通用上游接缝补丁。
- `overlay/`：Loader 通用运行接口等需要新增到合成树的文件。
- `mods/<id>/`：各 Mod 的配置、文档、补丁、overlay 和可选 Flutter 插件。
- `docs/`：中文设计、实施和维护文档。
- `.build/`：Loader 生成的 worktree、状态和临时产物，不提交、不手工编辑其中的源码。
- `V:/coding/kelivo`：上游仓，只作为固定 commit 的源码来源，不是本仓库功能的直接修改位置。

新增功能优先放在私有新增文件中。只有确实无法通过新增文件完成的接缝，才允许以补丁修改上游文件。

## 上游保护规则

- 不直接在上游仓实现私有功能，不向上游提交或推送本仓库内容。
- Loader 不自动执行 `fetch`、`pull`、分支切换、reset、clean 或 rebase。
- 构建必须固定到完整上游 commit，不能依赖浮动分支。
- 不在上游或合成树中执行 `git reset --hard`、`git clean -fd` 来绕过失败。
- 发现补丁冲突、内容漂移或 worktree 状态异常时必须停止并报告，不做静默模糊应用。
- 只有明确由 Loader 创建且位于 `.build/worktrees/` 的目录才允许清理；清理必须接受精确目标。
- 不读取、复制或提交 `.env`、签名文件、`key.properties`、SSH 密钥或 `lib/secrets/` 中的秘密。
- `pubspec.lock` 和根项目 Flutter 生成注册文件由合成树中的 Flutter 工具更新，不手工制作对应补丁。

## Loader 开发约定

- Loader 运行时只使用 Dart SDK 和 Git，不引入 YAML、AST、代码改写或 CLI 框架依赖。
- 测试使用开发依赖 `package:test`，不要自写测试框架。
- Git 和 Flutter 进程调用使用参数数组；需要 shell 时仅限 Windows `.bat` 查找等明确原因，不拼接用户输入。
- Windows 上创建合成 worktree 时显式使用 `git -c core.autocrlf=false worktree add`，按仓库存储的 LF 检出；不修改上游 Git 配置，也不重写已有合成树。
- `verify` 只允许 `pubspec.lock` 和根项目 Flutter 生成注册文件这几类精确构建产物变化，其他已跟踪漂移必须失败。
- 所有仓库路径在配置、哈希和补丁中使用 `/`；进程参数保留合法的本机绝对路径。
- `plan` 不得写文件；`apply` 必须幂等；`verify` 不执行 Flutter 构建；`rebase-drill` 不改变当前配置和主合成树。
- 不使用 AST/Mixin、自动依赖求解、运行时下载或动态 Dart 加载。
- 保持实现与 `docs/mod-loader-plan.md` 一致。若确需改变契约，先更新文档，再修改代码和测试。

## Mod 开发约定

- 每个 Mod 必须有 `mod.json` 和中文 `README.md`。
- `mod.json` 显式声明基线、工具名、注册入口、补丁白名单、复制目标和 vendored 来源。
- 工具名使用 Mod 独立前缀，避免与上游和其他 Mod 冲突。
- overlay 只能新增文件，不能覆盖上游或其他 Mod 已有文件。
- 补丁按声明顺序逐个执行 `git apply --check` 和应用，不使用模糊补丁绕过不兼容。
- Mod 的注册逻辑必须位于其自有文件中，通用 Kelivo 接缝不得 import 具体业务 Mod。
- Mod 不会自动继承上游专属权限、审批和 schema override；需要的行为必须由 Mod 自己实现并测试。

## Phone Agent 特别约定

以下规则仅在第二阶段适用，详细范围见 `docs/phone-agent-plan.md`：

- 使用独立 Flutter path 插件和独立 `AccessibilityService`，不修改上游 `PhoneControlService`。
- 每个助手使用独立 localToolId `phone_agent`，不复用 `phone_control`；`LocalToolNames.all` 不加入 `phone_agent`，避免生成原生定义、标签或开关。
- Mods 页提供助手选择和三态单选：关闭、原生手机控制、Phone Agent。正常 UI 不允许两者同时启用。
- 选择原生手机控制时保留 `phone_control`、移除 `phone_agent`，并继续走上游授权页；选择 Phone Agent 时写入 `phone_agent`、移除 `phone_control`；选择关闭时移除两者。
- 已有仅启用 `phone_control` 的助手保持原生行为，不自动迁移，不批量改写 `localToolIds`。
- Mods 页显示独立 `PhoneAgentService` 的 `PhoneAgentAvailability` 状态：supported、enabled、connected、sdk（`androidSdkInt`），并用 `enabled && connected` 派生 ready；`PhoneAgentAvailability.supported` 仅表示 Android API 30+ 截图能力，不表示 Phone Agent 或平台是否可用。
- API 29 服务可 ready 并支持树/节点输入；截图返回 `unsupported_os`，页面显示截图限制；非 Android 平台显示平台不支持，不添加 Mod 工具。
- Mods 页的选择是工具配置，不代表服务已授权；两个 `AccessibilityService` 继续共存，不自动授权、不自动切换系统无障碍开关。
- 新增移动和桌面 Mods 设置入口，宽窄屏共用简单页面，不接入设置搜索。
- `local-tool-mutual-exclusion.patch` 和 `settings-entry.patch` 是 phone_agent Mod 自己声明的业务补丁，不是 Loader 通用接缝；Loader 通用 `tool_mod.dart` 和 `mod_registry` 生成逻辑不 import Phone Agent，`mod_registry.g.dart` 中的 Mod import 只来自 `mod.json` 的 `registration` 字段。
- 产品文案按上游标准进入 ARB，并同步所有目标语言；标准 sync 已由本机免费 llama-cpp 完成，`translate.py check` 四目标语言 0 pending；工具 schema 和结构化错误继续使用英文。
- `PhoneAgentMod` 仅在助手启用 `phone_agent` 时激活；激活时过滤原生 `phone_control` 定义和重复的 `phone_agent_*` 定义；每次执行前重查当前助手的 `phone_agent`，撤销后返回 `phone_agent_disabled`。
- 插件不得 import `package:Kelivo/...`，避免循环依赖；Kelivo 侧适配代码放在 Mod overlay。
- 使用独立 MethodChannel、Manifest、服务 XML 和资源名，不修改上游 Android 宿主文件。
- 工具 schema 不暴露 `snapshot_id`；节点句柄、截图状态和 TTL 由原生侧管理。
- 节点重验契约：句柄每次使用前执行 `refresh()`、可见性、可用性和指纹校验；同一已刷新节点仅 `isFocused` 变化（点击和输入本身就会改变焦点）或动作集合 `actions` 变化（聚焦会增减动作，动作可用性在动作前按当前节点重新校验）不失效；真正的节点替换、内容变化、稳定能力字段（`isEnabled`、`isEditable`、`isClickable`、`isLongClickable`、`isScrollable`、`isCheckable`、`isChecked`）、`isSelected` 变化以及窗口/包名/尺寸/旋转变化仍返回 `stale_handle`；不得一次性放宽全部指纹字段。焦点或动作集合变化不失效不等于动作成功，`performAction` 返回值仍只表示系统接受动作。
- 节点重验诊断：`stale_handle` 保持原错误码；`refresh()`、可见性和可用性前置失败按该顺序短路判断，消息只追加固定诊断标识 `refresh_failed`、`not_visible`、`not_enabled`，不含节点文本、类名、viewId 或其他内容，不改变任何通过条件，也不替代指纹字段名。诊断标识用于区分失败来源，不等于根因已修复。
- 模型坐标统一为 `[0, 1]` 归一化坐标，原点为截图左上角。
- 截图复用 Kelivo 现有 `ClientToolResult` 与 `McpImageSnapshot` 链路，不修改 provider 序列化。
- 首版只在显式测试包名中开放输入，不操作支付、社交等敏感应用。私有测试应用使用 `com.psyche.kelivo.phoneagent` 和启动名称 `Kelivo Agent`，不得覆盖设备已安装的上游 Kelivo。
- 输入边界必须精确表述：`system_window_denied` 和 `package_not_allowed` 只约束输入；读树和截图不检查包名，仍可观察当前前台窗口。`FLAG_SECURE` 只阻止截图，不阻止读树和输入。`device_locked` 同时约束读树、截图和输入。
- 整屏 `AccessibilityService.takeScreenshot(Display.DEFAULT_DISPLAY)` 不保证对 `FLAG_SECURE` 报错：secure 内容可能以黑色区域出现在成功截图中。不得根据像素猜 secure、不得承诺不发送黑图；正常黑色页面保留。平台明确报错时返回 `screenshot_blocked`，不得发送图片或图片 metadata；成功黑图只作为普通截图，工具描述要求优先读树、不凭黑图猜坐标。
- secure 窗口的树在 API35 夹具上可读，但不是绝对保证；密码字段、自定义 View、窗口变化仍会影响树；非白名单输入仍被拒绝。
- 输入错误码优先级固定为 `no_window` → `system_window_denied` → `package_not_allowed` → 白名单内句柄/截图校验；测试必须断言精确错误码，前台包名未知时失败，不能“只要报错就算通过”。
- `home`/`recents` 后前台离开白名单，后续输入（包括 `back`）被拒绝，模型无法自行恢复；文档和测试必须记录需要用户或宿主切回测试应用。
- 真实 `FLAG_SECURE`、权限弹窗和异常路径使用插件 `android/src/debug` 的 `SecureWindowFixtureActivity` 测试夹具：只新增 debug 源码和 manifest，不修改上游 `MainActivity`、`KelivoApplication`、`PhoneControlService`，不新增上游补丁或 `touches`，release 不编译、不合并。夹具只请求上游已声明的权限用于拉起系统窗口，不授予、不录音、不使用其他敏感能力。
- 异常集成测试的夹具启动、secure 切换、权限弹窗、锁屏和服务开关由宿主/CU 在打印标记后操作；测试只轮询并断言结果。禁止用 `settings put secure enabled_accessibility_services` 写授权；服务开关只走系统界面。
- 例外：用户已明确授权在指定的 MIUI 物理测试设备（Redmi K30 5G，`1960cd68`）上用 `settings put secure` 预配置 Phone Agent 服务，仅限该设备与 Phone Agent，且必须保存并在结束时恢复**当轮真实原始值**，不能按历史记录强制写成空串+0；历史轮原值为空串+0，M17 轮原值为 Phone Agent 组件 + `accessibility_enabled=1`。该授权不改变产品自动授权边界，不得写成产品能力、默认许可或其他设备的通用做法。
- magpie 的模型能力标注可能变化：即使型号看起来支持视觉，也必须每次实测图片输入与工具调用；Kelivo 手动勾选图片只是测试配置，不能当作模型能力保证。网关 `api_error`/空响应属外部故障，与产品坐标动作失败分开记录。
- `flutter test`（含集成测试）会把合成树内 `build/app/outputs/flutter-apk/app-debug.apk` 覆盖为测试入口构建；产品 APK 必须在干净合成树显式 `flutter build apk --debug` 重新生成并重新计算大小与 SHA-256，不能沿用旧哈希，也不能把测试入口构建当产品；在产品构建后若再运行 integration_test，必须重新构建产品 APK。测试后仅做增量 `flutter build apk --debug` 可能仍复用约 249 MB 的测试入口 APK；必须用 `flutter clean` 后重建，并以约 181 MB 的产品大小和 manifest 复核。
- 物理设备上的官方测试在 M16 出现过一次间歇性 `set_text` `stale_handle`（`The target node changed`，属 `ObservationRegistry` 的 refresh/isVisibleToUser/isEnabled 前置分支），另一次全通过；M17 用同一官方测试连续 4 轮均为 `+2`、EXIT=0，未复现，也未触发 `refresh_failed`/`not_visible`/`not_enabled`。根因未确认、未修复，只能如实记录为间歇性和有限样本未复现，不得写成稳定通过、根因修复或擅自放宽节点校验。
- 原生截图、手势、插件通道和 worker 排队超时无法在设备上确定性触发时，只能由 Dart 注入超时测试覆盖工具层映射，不得伪造设备场景或写成真机证据。
- 密码遮挡、节点校验、窗口校验和手势回调都有边界，不得在文档中写成绝对安全保证。
- “发送、购买、删除前确认”不得被描述为原生可可靠识别的硬护栏。
- 先更新本文件、`docs/phone-agent-plan.md` 和 `mods/phone_agent/README.md`，再修改代码、测试和 `mod.json`。最终验收结果以计划文档和 README 为准，未验证项不得写成已完成。

## 代码风格

- Dart 遵循现有 Kelivo 的命名、结构和 `dart format` 风格；优先小文件、清晰职责和最少抽象。
- 默认不写解释显而易见行为的注释；复杂路径、失败策略和兼容性约束应通过清晰结构、错误信息和测试表达。
- 不为未来假想 Mod 预先增加通用框架。只有当前测试 Mod 或 Phone Agent 真正需要的能力才进入 Loader。
- 不添加向后兼容层、运行时回退或静默降级来掩盖配置和补丁错误。
- 新测试放在对应实现附近；不修改上游测试来迁就私有 Mod。

## 验证要求

Loader 改动至少运行：

```bash
dart format --output=none --set-exit-if-changed tool test
dart analyze tool test
dart test
```

通用 Kelivo 接缝或合成行为改动，还必须在对应合成 worktree 中运行：

```bash
flutter pub get
flutter pub get --directory tool/l10n --enforce-lockfile
dart analyze --fatal-infos lib test integration_test tool
flutter test test/features/home/services/tool_handler_service_test.dart
flutter test test/features/home/services/tool_handler_workspace_gating_test.dart
flutter test test/request_consistency_test.dart
flutter build apk --debug
```

同时按上游要求检查 markstream：

```bash
cd dependencies/markstream
flutter pub get
dart analyze --fatal-infos
```

Phone Agent 的额外测试以 `docs/phone-agent-plan.md` 为准。path 插件测试不会被根包测试自动覆盖，必须单独运行。

真实 `FLAG_SECURE` 和异常路径使用 debug-only 夹具，必须单独构建并运行：

```bash
flutter build apk --debug
flutter test integration_test/phone_agent_test.dart -d <android-device-id>
flutter test integration_test/phone_agent_exception_test.dart -d <android-device-id>
```

debug merged manifest 必须包含 `com.kelivo.phoneagent.SecureWindowFixtureActivity`；release 不包含该 Activity 只作为 debug/release 变体隔离检查，不等于签名 release 验证。异常套件的夹具启动、secure 切换、权限弹窗、锁屏和服务开关由宿主/CU 在打印标记后操作，测试只轮询并断言。

Phone Agent UI/选择契约改造还必须在合成树中同步和检查 ARB：

```bash
flutter pub get --directory tool/l10n --enforce-lockfile
python3 tool/l10n/translate.py sync
python3 tool/l10n/translate.py check
flutter gen-l10n
```

标准 sync 已由本机免费 Magpie llama-cpp/llama-cpp 完成：23 个键已翻译，`translate.py check` 四个目标语言（ko、ru、tr、zh_Hant）均 0 pending，`l10n-generated.patch` 已生成；未使用付费服务。Magpie Python UA 适配只是临时进程环境，不属于 Mod 交付，不把临时路径写成依赖。

焦点修正前的验收记录（历史结果，不代表当前实现）：Loader verify 通过；Flutter 255 项（254 通过 + 1 Windows 条件跳过；Phone Agent 103、Mods 16、settings 入口 2）；插件 Dart 17、插件 Kotlin 55、上游 PhoneControl 49、Loader 165；根项目、markstream 和插件静态分析通过；API 29 真机官方测试退出码 0。当时的合成树为 `V:/coding/kelivo-private/.build/worktrees/4ed083cf5fe7dda8`。

节点重验修正后（上一轮，历史结果）：合成树为 `V:/coding/kelivo-private/.tower/worktrees/wt-1/.build/worktrees/7593c21b5f9da01f`，`modsetHash` 为 `7593c21b5f9da01fb8b8c4dfe167d892a940efe4a1caf591b772fbe83b6b6f7d`，Loader verify 通过；Loader 165、插件 Kotlin 66、插件 Dart 17、上游 PhoneControl 49、Phone Agent 103、Mods 16、settings 入口 2 通过；根项目和插件静态分析通过；API 35 模拟器与 API 29 真机官方集成测试均退出码 0（截图、读树、节点点击、坐标手势原生成功、节点滚动、聚焦后 `set_text`、二次读树、Mods 场景）。设备结果对应提交 `698cace` 的运行时语义；R1 审查后仅调整诊断编码、提取纯 JVM 前置校验接缝、补测试和文档，未重复双 API 设备回归。

上一轮 magpie VLM 验收（历史结果，不代表当前实现）：合成树沿用 `V:/coding/kelivo-private/.tower/worktrees/wt-6/.build/worktrees/5f0be65f98bb04e5`，`modsetHash` 为 `5f0be65f98bb04e5613e372731215d7b577bbeb1b4ffa3bf9c14693e74757284`；该轮只改中文文档，只读 `plan` 重新计算得到同一哈希，`verify` 通过，未重建合成树或 APK。API 35 模拟器 `emulator-5554` 使用当时的产品 APK（181369230 字节，SHA-256 `3ea30ee9b46342305cf11e0574b76def9a42f23abe62dd3536b664dc4ec5caeb`）和用户指定的 magpie 网关模型 `llama-cpp/llama-cpp`（provider `http://10.0.2.2:3425/v1`，UI Image + Tools；局域网访问由用户开启，未读取或记录密钥）完成真实图片链路、Kelivo 应用内固定任务和跨新用户轮次历史图片回放：REQ27 工具为 `read_file` + 三个 `phone_agent_*`，无 `phone_control`、无重复、无 `snapshot_id`、`additionalProperties=false`；REQ28（Request Log ID28）携带 `image 713x1600`、`screen 1080x2424`、package `com.psyche.kelivo.phoneagent` 和 `image_url=data:image/png;base64,<omitted 185028 chars>`、`detail=high`，响应头 `x-magpie-model=llama-cpp/llama-cpp`，模型读出 `3:00 / New Chat / llama-cpp/llama-cpp (Magpie VLM)`。固定任务在 Kelivo 应用内 Settings（不是 Android 系统设置）完成，全程 package 为 `com.psyche.kelivo.phoneagent`，未用 adb 代替模型输入：tree 22 节点 → 首次 tap n3 返回一次 `stale_handle`（No current tree observation）→ 重读树后 tap 成功 → `set_text n2 Phone` 成功 → UI `1 result / Phone Control / Settings`；随后 n4 ScrollView `forward` 成功，UI 滚到 `Sponsor`。新用户消息 REQ42（15:36:58）未调用工具、未重新截图，请求从历史工具 metadata 带回同一 `image_url`（185028 omitted chars），模型回答输入框占位 `Type a message for AI` 和蓝色圆形内白色方块按钮，并与保存的 713x1600 PNG 像素核对一致，跨用户轮次图片回放通过；图片进入上下文后上游额外暴露 `read_chat_image`，不是 Mod 重复或 `phone_control`。一次 `stale_handle` 异常（tree 成功后紧接 tap 报 No current tree observation，代码路径为 tree==null）未复现、未找到 native 日志、根因未确认、未修复；重读树后恢复，可能来源只是假设，不写成事实。该轮未修改产品代码，未重建 APK、未产生新哈希。

M16 历史物理 MIUI API31 验收（历史结果，不代表当前实现）：该轮只改中文文档，产品代码/测试/`mod.json`/schema/白名单/上游均未修改。最终源码 `modsetHash` `3d3cd25b4def35633dcf848373037cbe2c5200f795339c315b3ac9c3268a3174`，合成树 `V:/coding/kelivo-private/.tower/worktrees/wt-16/.build/worktrees/3d3cd25b4def3563`，`plan`/`apply`/`verify` 通过；产品 debug APK 在该新树显式 `flutter build apk --debug` 生成（未在该树随后运行 integration_test）：181,369,890 字节，SHA-256 `c6f20d250239bae223a4fdaa5ff1807ba34eab38bd8f9e7f9710e8c21747a58b`；debug merged manifest 含 `SecureWindowFixtureActivity`，release merged manifest 不含该夹具（不宣称签名 release）。设备：Redmi K30 5G（`1960cd68`，picasso），Android 12 / API 31，1080x2400，density 440，MIUI V13.0.3.0.SGICNXM；用户提供并授权测试，测试包 `com.psyche.kelivo.phoneagent` 未覆盖上游 Kelivo。授权例外：用户明确授权仅在该设备用 `settings put secure` 预配置 Phone Agent，M16 历史轮原始 `enabled_accessibility_services` 为空串、`accessibility_enabled=0`，每轮结束恢复；不是产品能力，其他设备默认仍禁止。物理结果：真实截图/读树/节点输入/滚动、Mods 三态选择通过；物理 `FLAG_SECURE` 返回成功黑图，清除后恢复；旋转旧句柄 `stale_handle`、旧坐标 `stale_observation`；`llama-cpp/llama-cpp` 的坐标 tap 真实打开抽屉/Settings/Search 并 `set_text Phone` 成功，后续 swipe 因网关故障未完成。magpie `mistral/deepseek-v4-1-flash-1017`（不是 0731，Bonsai 未使用）在 Kelivo 手动开启图片后真实请求全部 200，工具集为 `read_file` + 三个 `phone_agent_*`，无 `snapshot_id`、无 `phone_control`，截图 `image 720x1600` / `screen 1080x2400`；一次 swipe `{x:0.5,y:0.8,end_x:0.5,end_y:0.3,duration_ms:400}` 前后 PNG 证实 Sponsor 从不可见到可见。像素专属确认：新建无历史会话、只允许一次 screenshot、禁止 tree/input，1017 回答 `bright cyan (light blue)` + `PHONE_AGENT_SECURE_FIXTURE`，与保存 PNG 的 rgb(0,200,255) 及完整文字一致，请求只有一个截图 `tool_call`、`image_url` omitted 39204 chars、全文不含 `PHONE_AGENT`。官方测试间歇性：同一树同一命令第一次 `+1 -1`、EXIT=1（聚焦后 `set_text` 返回 `stale_handle` `The target node changed`，`ObservationRegistry` refresh/isVisibleToUser/isEnabled 前置分支，不是旧聚焦指纹路径），第二次 `+2`、EXIT=0；根因未确认、未修复。未验证：权限窗口、原生超时、签名 release、`stale_handle` 根因；物理设备未运行锁屏/home/recents/服务中断；`llama-cpp/llama-cpp` 的物理完整坐标 swipe。

上一轮 API35 FLAG_SECURE/异常路径（历史结果）：最终源码 `modsetHash` `5b1cde0304e687b9e3a26935cf85b5a27d102c9ecb409ff0e8b1358075aa902d`，合成树 `V:/coding/kelivo-private/.tower/worktrees/wt-10/.build/worktrees/5b1cde0304e687b9`，`plan`/`verify` 通过。契约按 M11 结论收缩为：整屏 `takeScreenshot` 不保证对 `FLAG_SECURE` 报错，API35 实测 secure 夹具本轮返回成功黑图（平均 RGB 约 2,0,2），上一轮也曾返回成功内容图（平均亮度约 191）；只承诺“可能黑化”，不做像素启发式，不承诺不发送黑图，正常黑色页面保留；平台明确报错时 `screenshot_blocked` 且无图片/metadata；secure 树在夹具上可读但不是绝对保证。设备结果：API35 完整异常套件实际运行于 `2c1513ecef3f2293` 树，`+5 ~1`、`All tests passed!`、EXIT=0；当前 `5b1cde0304e687b9` 是仅文档哈希变化后的最终源码/构建树，关键代码/测试一致，新树未重跑设备；通过 secure、旋转、home/recents、锁屏、服务禁用/重启；权限窗口明确跳过（未验证）。服务禁用前启动 1000 个只读 pending 请求，日志 `PHONE_AGENT_SERVICE_PENDING_BATCH: size=1000 elapsed=3252ms codes=interrupted,ok`；锁屏分别调用 tree/screenshot/input 并断言 `device_locked`。历史 `41e33b6f115e54bc` 完整套件 `+2 ~1 -3`、EXIT=1 的失败保留在 plan 9.3.1。API35 和 API29 官方测试各 2 项通过、EXIT=0（API29 截图 `unsupported_os`）。当时产品 debug APK（在 `5b1cde0304e687b9` 构建；设备套件实际运行于 `2c1513...`）181,373,590 字节，SHA-256 `581d56fc03fe716c768f2554015115bffd8e2b0d610c71e74f5d3b21524703a3`，已被本轮新树 APK 取代。

上一轮 VLM 验收（补充环境，历史结果）：API 35 模拟器使用 LM Studio `bonsai-vlm`（`prism-ml/bonsai-27b`，Image + Tools，8192 上下文）完成图片链路和固定任务（Request Log ID18，`<omitted 163212 chars>`，模型读出 `10:47 / New Chat / bonsai-vlm (Local VLM)`）。该结果只作补充环境记录，不能取代本轮用户指定 magpie 模型的结论。

无法执行的真机 VLM、`FLAG_SECURE`、完整异常路径或签名 release 验证必须明确报告为未验证，不能宣称完成。测试或构建生成的临时文件不提交；不得删除来源不明的已有文件。

## 文档与交付

- 维护文档、README、故障排查和交付总结使用中文。
- 修改命令、目录、配置字段、安全边界、工具选择契约或验收流程时，同步更新对应计划、README 和本文件。
- Loader 与 Phone Agent 分别更新各自文档，不把手机功能写回 Loader 通用原则。
- 最终交付必须说明实际完成项、执行的检查、未验证项和剩余限制；不得把未验证项写成已完成。
