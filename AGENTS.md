# AGENTS.md

## 仓库用途

本仓库是 Kelivo 的私有、编译前源码 Mod 工作区，不提交到上游，也不面向最终用户提供运行时插件平台。

当前任务分为两个独立阶段：

1. 先实现并验收通用 Mod Loader，见 `docs/mod-loader-plan.md`。
2. Loader 验收后再实现 `phone_agent` Mod，见 `docs/phone-agent-plan.md`。UI/选择契约改造已完成并通过最终验收；当前 `phone_agent` Mod 版本 0.2.0，VLM 图片链路、Kelivo 应用内固定任务和跨新用户轮次历史图片回放已在 API 35 模拟器用用户指定的 magpie `llama-cpp/llama-cpp` 验证，未验证项见计划。

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
- 模型坐标统一为 `[0, 1]` 归一化坐标，原点为截图左上角。
- 截图复用 Kelivo 现有 `ClientToolResult` 与 `McpImageSnapshot` 链路，不修改 provider 序列化。
- 首版只在显式测试包名中开放输入，不操作支付、社交等敏感应用。私有测试应用使用 `com.psyche.kelivo.phoneagent` 和启动名称 `Kelivo Agent`，不得覆盖设备已安装的上游 Kelivo。
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

本轮 magpie VLM 验收（当前实现）：合成树沿用 `V:/coding/kelivo-private/.tower/worktrees/wt-6/.build/worktrees/5f0be65f98bb04e5`，`modsetHash` 为 `5f0be65f98bb04e5613e372731215d7b577bbeb1b4ffa3bf9c14693e74757284`；本轮只改中文文档，只读 `plan` 重新计算得到同一哈希，`verify` 通过，未重建合成树或 APK。API 35 模拟器 `emulator-5554` 使用产品 APK（181369230 字节，SHA-256 `3ea30ee9b46342305cf11e0574b76def9a42f23abe62dd3536b664dc4ec5caeb`）和用户指定的 magpie 网关模型 `llama-cpp/llama-cpp`（provider `http://10.0.2.2:3425/v1`，UI Image + Tools；局域网访问由用户开启，未读取或记录密钥）完成真实图片链路、Kelivo 应用内固定任务和跨新用户轮次历史图片回放：REQ27 工具为 `read_file` + 三个 `phone_agent_*`，无 `phone_control`、无重复、无 `snapshot_id`、`additionalProperties=false`；REQ28（Request Log ID28）携带 `image 713x1600`、`screen 1080x2424`、package `com.psyche.kelivo.phoneagent` 和 `image_url=data:image/png;base64,<omitted 185028 chars>`、`detail=high`，响应头 `x-magpie-model=llama-cpp/llama-cpp`，模型读出 `3:00 / New Chat / llama-cpp/llama-cpp (Magpie VLM)`。固定任务在 Kelivo 应用内 Settings（不是 Android 系统设置）完成，全程 package 为 `com.psyche.kelivo.phoneagent`，未用 adb 代替模型输入：tree 22 节点 → 首次 tap n3 返回一次 `stale_handle`（No current tree observation）→ 重读树后 tap 成功 → `set_text n2 Phone` 成功 → UI `1 result / Phone Control / Settings`；随后 n4 ScrollView `forward` 成功，UI 滚到 `Sponsor`。新用户消息 REQ42（15:36:58）未调用工具、未重新截图，请求从历史工具 metadata 带回同一 `image_url`（185028 omitted chars），模型回答输入框占位 `Type a message for AI` 和蓝色圆形内白色方块按钮，并与保存的 713x1600 PNG 像素核对一致，跨用户轮次图片回放通过；图片进入上下文后上游额外暴露 `read_chat_image`，不是 Mod 重复或 `phone_control`。一次 `stale_handle` 异常（tree 成功后紧接 tap 报 No current tree observation，代码路径为 tree==null）未复现、未找到 native 日志、根因未确认、未修复；重读树后恢复，可能来源只是假设，不写成事实。本轮未修改产品代码，未重建 APK、未产生新哈希。

上一轮 VLM 验收（补充环境，历史结果）：API 35 模拟器使用 LM Studio `bonsai-vlm`（`prism-ml/bonsai-27b`，Image + Tools，8192 上下文）完成图片链路和固定任务（Request Log ID18，`<omitted 163212 chars>`，模型读出 `10:47 / New Chat / bonsai-vlm (Local VLM)`）。该结果只作补充环境记录，不能取代本轮用户指定 magpie 模型的结论。

无法执行的真机 VLM、`FLAG_SECURE`、完整异常路径或签名 release 验证必须明确报告为未验证，不能宣称完成。测试或构建生成的临时文件不提交；不得删除来源不明的已有文件。

## 文档与交付

- 维护文档、README、故障排查和交付总结使用中文。
- 修改命令、目录、配置字段、安全边界、工具选择契约或验收流程时，同步更新对应计划、README 和本文件。
- Loader 与 Phone Agent 分别更新各自文档，不把手机功能写回 Loader 通用原则。
- 最终交付必须说明实际完成项、执行的检查、未验证项和剩余限制；不得把未验证项写成已完成。
