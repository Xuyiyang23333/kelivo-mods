# 下一次会话交接：Phone Agent VLM 验收证据

## 1. 新会话与仓库

请在 `V:/coding/kelivo-private` 新建会话，不要以 `V:/coding` 或 `V:/coding/kelivo` 作为 Tower 工作区。

- `V:/coding/kelivo` 是只读上游源码来源，不直接修改、不创建 Mod 工作分支。
- `V:/coding/kelivo-private` 是私有 Mod 工作区，包含 Loader、Phone Agent、中文文档与测试。
- 先阅读私有仓根目录 `AGENTS.md`。合成树位于 `.build/worktrees/`，不能手工修改其中源码来交付功能；契约变化先改中文文档，再改私有仓的 overlay/补丁，并通过 Loader 生成新合成树。
- 私有仓本地 Git email 已设置为 `xuyiyang23333@gmail.com`。
- 私有仓现有源码和文档必须完整保留；不要通过 reset、clean 或重新初始化覆盖它们。

## 2. 当前目标与阶段

第一阶段 Mod Loader 已完成。第二阶段 Phone Agent 的主要功能已完成，VLM 图片链路和固定任务已在 API 35 模拟器用本地模型验证；仍处于设备联调阶段，不能宣称全部验收完成。

本轮已完成：

1. 固化 API 35 模拟器本地 VLM 图片链路与固定任务验收记录。
2. 新增 2 项聚焦回归：真实 `PhoneAgentScreenshotResult` 产出的 `ClientToolResult`/metadata 经现有 `ToolResultContent.read`，在支持图片时产生非空图片引用，不支持图片时省略。
3. 通过 Loader 确定性合成新树，完成格式、静态分析和 Phone Agent 相关定向测试。

当前剩余：

1. 物理 API 30+ 真机上的 VLM 固定任务和坐标手势 UI 效果。
2. 新用户轮次再次请求时的历史图片回放。
3. 真实 `FLAG_SECURE`、旋转/切窗/锁屏/禁用服务/超时等异常路径。
4. 带合法签名配置的 release 构建。

首版输入仍只开放给测试包名 `com.psyche.kelivo.phoneagent`。不要扩大白名单、引入自动无障碍授权，或把发送/购买/删除确认描述成原生硬护栏。

## 3. 已有实现与交付基线

- 上游基线：`73afa4ec77cfc9af2efea2487fee8bba1362639d`。
- 当前 Mod 版本：`0.2.0`。
- 本轮合成树：`V:/coding/kelivo-private/.tower/worktrees/wt-6/.build/worktrees/5f0be65f98bb04e5`。
- 本轮 `modsetHash`：`5f0be65f98bb04e5613e372731215d7b577bbeb1b4ffa3bf9c14693e74757284`。
- 三个工具：`phone_agent_screenshot`、`phone_agent_tree`、`phone_agent_input`。
- 每助手独立 `localToolId='phone_agent'`；Mods 页提供关闭/原生手机控制/Phone Agent 三态单选，已有助手不自动迁移。
- 观察按需发生，不强制每步重新读取完整树；工具 schema 不暴露 `snapshot_id`。
- `supported` 只表示 API 30+ 截图能力；API 29 仍可 ready 并使用树/节点输入。

本轮已通过的检查：

- Loader `dart format`、`dart analyze tool test`、165 项测试、`dart tool/mod_loader.dart verify`。
- 新合成树 `dart format`、`dart analyze --fatal-infos lib test integration_test tool`。
- Phone Agent 105 项（新增 2 项截图 metadata → `ToolResultContent` 衔接测试）、Mods 16 项、settings 入口 2 项、上游 `tool_result_content` 回归。
- 插件 Dart 17 项、插件 Kotlin 66 项、上游 `PhoneControlServiceTest` 49 项沿用上一轮结果；本轮未修改插件。
- 本轮未重跑双 API 设备回归和全量 Flutter 套件。理由：只改中文文档和 phone_agent overlay 测试，未改产品代码、`mod.json`、schema、节点指纹或插件行为；新增测试在合成树中单独运行通过。
- 产品 debug APK（VLM 验收使用，本轮未重建）：`V:/coding/kelivo-private/.tower/worktrees/wt-1/.build/worktrees/7593c21b5f9da01f/build/app/outputs/flutter-apk/app-debug.apk`，181369230 字节，SHA-256 `3ea30ee9b46342305cf11e0574b76def9a42f23abe62dd3536b664dc4ec5caeb`。

API 29 真机结果、双 API 集成测试和任何后续改动后的数字以 `docs/phone-agent-plan.md` 9.3/9.4 与 `mods/phone_agent/README.md` 的最新记录为准，不得沿用旧结果冒充新实现通过。

## 4. 本轮 VLM 验收证据

环境与适用范围：

- 设备：API 35 模拟器 `emulator-5554`（Android 15，内部屏幕 1080x2424）。
- 模型：LM Studio 本地 `prism-ml/bonsai-27b`，identifier `bonsai-vlm`，模型 UI 勾选 Image 输入和 Tools 能力。
- 应用内 provider：`Local VLM`，地址 `http://10.0.2.2:1234/v1`，dummy key，未读取任何秘密。
- 上下文：4096 下复杂固定任务出现“截图 → 读树 → 再截图”循环，8192 后完成。这是本地测试经验，不是新增产品依赖。

证据 A：最小截图 → 图片 → 模型链路

- 工具结果：`image 713x1600`、`screen 1080x2424`、`package_name com.psyche.kelivo.phoneagent`。
- 后续请求包含 `phone_agent_screenshot` 工具结果和一条合成 user 消息：`image_url` 为 `data:image/png;base64,<omitted 163212 chars>`，`detail` 为 `high`。
- 产品 UI 的 Request Log ID18 显示 `Attachments: image/png · 47.7 KB · omitted`，Authorization 已脱敏。
- 模型回答 `10:47 / New Chat / bonsai-vlm (Local VLM)`，与截图中的时间、聊天标题和模型名称一致。

证据 B：固定任务（点击 + 输入 + 滚动尝试 + 确认）

- 工具顺序：`phone_agent_tree` 找到 `n3`（description `Search settings`）→ `tap n3` 成功 → 重新读树找到 `EditText n2` → `set_text n2 "Phone"` 成功 → 对 `n1` 执行 `scroll down` 返回结构化 `action_unavailable` → `phone_agent_screenshot` 确认。
- UI 最终状态：搜索框为 `Phone`，显示 `1 result`，唯一结果为 `Phone Control / Settings`；模型回答确认 `Phone Control` 存在。
- `action_unavailable` 是契约内可恢复错误：节点声明 `scrollable` 但当前动作集合不含对应滚动方向；产品没有把失败写成成功。

证据 C：补充滚动任务（`stale_handle` 恢复 + 真实滚动）

- 工具顺序：首次读树时前台仍在聊天页，`n1` 为可滚动 View → 对 `n1` 执行 `scroll forward` 返回 `stale_handle`（前台已切到 Settings）→ 重新读树，`n4` 为 `android.widget.ScrollView` → 对 `n4` 执行 `scroll forward` 成功 → 再次读树，最后一个可见设置为 `n21 Sponsor`。
- UI 可观察状态：Settings 页面真实滚到底部并显示 `Sponsor`；模型回答 `Sponsor`。

工具暴露：

- 请求工具列表为 `read_file` + `phone_agent_screenshot` / `phone_agent_tree` / `phone_agent_input`；`read_file` 是上游工具，不属于 Mod schema。
- 无原生 `phone_control`，无重复 `phone_agent_*`；三个 schema 均无 `snapshot_id`，均设置 `additionalProperties: false`。

证据边界：

- 同一生成轮的工具循环图片回放已验证；新用户轮次再次请求时的历史图片回放未验证。
- 本轮未使用坐标动作完成任务；坐标手势的 UI 效果仍受 integration_test 绑定限制，未在物理 API 30+ 真机验证。
- 本轮没有确认私有 Mod 硬缺陷。`action_unavailable` 和 `stale_handle` 都是契约内可恢复结果，不是产品假成功；Add Provider 表单的低置信度自动化焦点现象未被人工复现，不作为产品缺陷记录。
- 文档只记录脱敏后的请求形态和尺寸/长度，不记录 provider 密钥、完整会话文本或截图字节。

## 5. 本轮新增聚焦测试

文件：`mods/phone_agent/overlay/test/features/phone_agent/phone_agent_tool_result_test.dart`（合成树 `test/features/phone_agent/phone_agent_tool_result_test.dart`）。

- 使用真实 `PhoneAgentScreenshotResult.build` 和真实 `McpImageSnapshot.saveBytes` 落盘，不 mock 被验证的 metadata 衔接。
- 支持图片：`ToolResultContent.read` 返回 1 个 `data:image/png;base64,` 图片引用，正文移除 Markdown 图片行并保留工具 JSON。
- 不支持图片：`imageUrls` 为空，正文包含省略说明且不含 base64。
- 复用 `RecordingPhoneAgentClient` 和 `FakePathProviderPlatform`；未修改上游测试或 provider 序列化。
- 现有 `phone_agent_screenshot_test.dart` 的落盘尺寸校验、尺寸不一致、空字节、非法尺寸、保存失败和清理错误路径保持不变。

## 6. 设备、授权与环境

### 设备

- API 35 模拟器：`emulator-5554`，AVD `Kelivo_Phone_Agent_API_35`，Android 15，内部屏幕 `1080x2424`。
- API 29 真机：Sharp SG803SH，ADB ID `357784090209204`。
- 执行任何设备命令前用 `adb devices -l` 重新确认，命令必须带 `-s`。

### 无障碍授权流程（重要）

- 安装测试包和部分收尾的 force-stop **可能**清除系统无障碍授权；每轮都要用 `settings get secure enabled_accessibility_services` 和 `dumpsys accessibility` 检查真实状态，不要假设一定被清除或一定保留。
- 集成测试在 `setUpAll` 打印 `PHONE_AGENT_WAITING_FOR_SERVICE` 后等待约 300 秒（600 × 500ms），需要在该窗口内通过系统界面重新启用服务。
- 服务组件：`com.psyche.kelivo.phoneagent/com.kelivo.phoneagent.PhoneAgentService`；只启用 **Kelivo Phone Agent**，不要启用 **Kelivo phone control**。
- 启用后把 `Kelivo Agent` 应用切回前台并保持，直到测试结束。
- 不要用 `settings put secure` 写入授权绕过系统确认。

### 本地 VLM 环境（测试经验，不是产品依赖）

- LM Studio server 默认 1234 端口；本轮使用 `prism-ml/bonsai-27b`，identifier `bonsai-vlm`，建议 `-c 8192`。
- 模拟器访问宿主机使用 `http://10.0.2.2:1234/v1`；provider 使用 dummy key，不读取或提交秘密。
- 应用内模型需同时勾选 Image 输入和 Tools 能力，否则 Mod 不激活或截图工具不暴露。
- 测试结束后停止 LM Studio、卸载模型；设备上的 provider 和测试会话是测试状态，不是仓库交付物。

### Windows 环境

- Flutter 全局使用 JDK 17：`flutter config --jdk-dir="C:/Users/David/scoop/apps/openjdk17/current"`；不要切回 JDK 25。
- 私有仓 `core.autocrlf=true`，Tower 创建的 worktree 会以 CRLF 检出全部文件，导致 Loader 补丁无法应用、`dart format` 失败。处理方式：在 worktree 内执行 `git ls-files -z | xargs -0 perl -pi -e 's/\r\n/\n/g'` 就地转 LF，不改仓库 config。转换后 `git status` 会把大量文件标为 M（stat 噪声），但 `git diff --name-only` 只显示真实改动。
- 本任务 worktree 路径较长，合成树会超过 Windows `MAX_PATH`。生成时使用环境变量注入 Git 长路径支持（不修改任何配置文件）：

```bash
cd V:/coding/kelivo-private/.tower/worktrees/wt-6
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.longpaths GIT_CONFIG_VALUE_0=true
dart tool/mod_loader.dart plan
dart tool/mod_loader.dart apply
dart tool/mod_loader.dart verify
```

- 合成树内 `android/gradlew` 由 Flutter 生成：先执行 `flutter build apk --debug --config-only`，再运行 `./gradlew :kelivo_phone_agent:testDebugUnitTest`。模块名已通过 `./gradlew projects` 确认为 `:kelivo_phone_agent`。
- 提交时只精确暂存实际交付文件，避免把无内容差异的 CRLF stat 噪声加入提交。

## 7. 验证顺序与后续交付

1. 改动契约时先更新 `AGENTS.md`、`docs/phone-agent-plan.md`、`mods/phone_agent/README.md`，再改实现和测试。
2. Loader：`dart format --output=none --set-exit-if-changed tool test`、`dart analyze tool test`、`dart test`、`dart tool/mod_loader.dart verify`。
3. 合成树：`flutter pub get`、`flutter pub get --directory tool/l10n --enforce-lockfile`、`dart format`、`dart analyze --fatal-infos lib test integration_test tool`、Phone Agent/Mods/settings 测试、上游 `tool_result_content` 回归。
4. 插件 Kotlin 测试（修改插件时）：`cd android && ./gradlew :kelivo_phone_agent:testDebugUnitTest`。
5. 设备：先 API 35（`-d emulator-5554`），再 API 29（`-d 357784090209204`）；安装后按第 6 节流程授权。
6. 修改产品代码或插件后重新构建 APK 并计算大小与 SHA-256；不要沿用旧哈希。只改文档/测试时不要重建 APK。
7. 更新中文验收记录和本交接文档，如实写明未验证项。

仍未完成或不能宣称完成：物理 API 30+ 真机的 VLM 固定任务和坐标手势 UI 效果、新用户轮次历史图片回放、真实 `FLAG_SECURE`、完整异常路径、签名 release。上游仓保持只读；不向上游提交或推送私有实现。
