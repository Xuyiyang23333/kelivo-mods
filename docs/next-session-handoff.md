# 下一次会话交接：Phone Agent VLM 验收证据

## 0. M10 当前状态（2026-11-11）

- 本轮目标：API35 真实 `FLAG_SECURE` 与受控异常路径。按 M11 公开 API 审查结论，契约已收缩为：整屏 `takeScreenshot` 不保证对 `FLAG_SECURE` 报错，secure 内容可能以黑色区域出现在成功截图中；不做像素启发式，不承诺不发送黑图，正常黑色页面保留；平台明确报错时 `screenshot_blocked` 且不发送图片/metadata。
- 最终源码 `modsetHash`：`5b1cde0304e687b9e3a26935cf85b5a27d102c9ecb409ff0e8b1358075aa902d`；合成树：`V:/coding/kelivo-private/.tower/worktrees/wt-10/.build/worktrees/5b1cde0304e687b9`；`plan`/`verify` 通过。
- 提交：`c4fa61b`（实现检查点）、`09b5c11`（首次结果文档）、`2ca0888`（首次整套件协调）；本轮 reviewer findings 返工与最新结果见最新 commit。
- 已通过：Loader 165（历史）、聚焦工具测试 32、最终树 `dart analyze --fatal-infos`、插件 Dart 17、插件 Kotlin 66、上游 PhoneControl 49（历史；本轮 Kotlin 仅注释改动，由 APK 构建编译）。
- API35 完整异常套件（实际运行树 `2c1513ecef3f2293`；当前 `5b1cde0304e687b9` 仅文档哈希变化，关键代码/测试一致，新树未重跑设备）：**`+5 ~1`，`All tests passed!`，EXIT=0**；通过 secure、旋转、home/recents、锁屏、服务禁用/重启；权限窗口明确跳过（未验证）。服务禁用前启动 1000 个只读 pending 请求，日志 `PHONE_AGENT_SERVICE_PENDING_BATCH: size=1000 elapsed=3252ms codes=interrupted,ok`；锁屏分别调用 tree/screenshot/input 并断言 `device_locked`。历史 `41e33b...` 的 `+2 ~1 -3`、EXIT=1 失败保留在 plan 9.3.1。
- API35 官方测试 2 项通过、EXIT=0；API29 官方测试 2 项通过、EXIT=0（截图 `unsupported_os`）。
- 当前产品 debug APK（在最终源码/构建树 `5b1cde0304e687b9` 构建；设备套件实际运行于 `2c1513...`）：**181,373,590 字节**，SHA-256 `581d56fc03fe716c768f2554015115bffd8e2b0d610c71e74f5d3b21524703a3`；debug merged manifest 含 `SecureWindowFixtureActivity`，release merged manifest 不含该夹具（不宣称签名 release）。
- secure 观察：本轮记录成功黑图；上一轮同一夹具曾返回成功内容图（平均亮度约 191），因此契约只承诺“可能黑化”，不保证黑图或检测。
- 未验证：权限窗口、物理 API30+、签名 release、原生超时、`stale_handle` 根因。
- 临时不同 UID 夹具 `.build/secure_fixture_app/` 和 host driver `.build/host_exception_driver.sh` 仅在 `.build`，不提交。

## 1. 新会话与仓库

请在 `V:/coding/kelivo-private` 新建会话，不要以 `V:/coding` 或 `V:/coding/kelivo` 作为 Tower 工作区。

- `V:/coding/kelivo` 是只读上游源码来源，不直接修改、不创建 Mod 工作分支。
- `V:/coding/kelivo-private` 是私有 Mod 工作区，包含 Loader、Phone Agent、中文文档与测试。
- 先阅读私有仓根目录 `AGENTS.md`。合成树位于 `.build/worktrees/`，不能手工修改其中源码来交付功能；契约变化先改中文文档，再改私有仓的 overlay/补丁，并通过 Loader 生成新合成树。
- 私有仓本地 Git email 已设置为 `xuyiyang23333@gmail.com`。
- 私有仓现有源码和文档必须完整保留；不要通过 reset、clean 或重新初始化覆盖它们。

## 2. 当前目标与阶段

第一阶段 Mod Loader 已完成。第二阶段 Phone Agent 的主要功能已完成，当前 M10 已在 API 35 模拟器验证真实 `FLAG_SECURE` 行为、旋转、home/recents、锁屏、服务禁用/重启；权限窗口、物理 API30+、原生超时和签名 release 仍未验证，不能宣称全部验收完成。

本轮（M10）已完成：

1. 按用户批准的契约记录整屏 `takeScreenshot` 的 `FLAG_SECURE` 行为：可能成功返回黑图或内容图，不保证检测、不承诺不发送黑图；平台明确报错时 `screenshot_blocked` 且无图片/metadata。
2. 完整异常套件实际运行于 `2c1513ecef3f2293` 树：`+5 ~1`、EXIT=0；服务用例验证禁用前同一批 pending Future 被中断，锁屏分别验证 tree/screenshot/input。
3. 当前 `5b1cde0304e687b9` 是仅文档哈希变化后的最终源码/构建树；关键代码/测试与 `2c1513...` 逐字一致，新树未重跑设备。当前 APK 只在 `5b1cde...` 构建。
4. 更新契约、工具描述、debug 夹具、异常套件与中文文档；未修改生产行为（仅 `ScreenshotCapture.kt` 注释）、未扩大白名单、Mod 版本保持 0.2.0。

当前剩余：

1. 权限窗口 `system_window_denied` 未触发，未验证。
2. 物理 API 30+ 真机上的 VLM 固定任务、截图和坐标手势 UI 效果。
3. 原生截图/手势/通道/worker 排队超时未设备验证。
4. 带合法签名配置的 release 构建。
5. 一次未复现的 `stale_handle`（`No current tree observation`）根因未确认；重读树后恢复，未修复，只记录有限证据。

首版输入仍只开放给测试包名 `com.psyche.kelivo.phoneagent`。不要扩大白名单、引入自动无障碍授权，或把发送/购买/删除确认描述成原生硬护栏。

## 3. 已有实现与交付基线

- 上游基线：`73afa4ec77cfc9af2efea2487fee8bba1362639d`。
- 当前 Mod 版本：`0.2.0`。
- 当前 M10 合成树：`V:/coding/kelivo-private/.tower/worktrees/wt-10/.build/worktrees/5b1cde0304e687b9`。
- 当前 M10 `modsetHash`：`5b1cde0304e687b9e3a26935cf85b5a27d102c9ecb409ff0e8b1358075aa902d`（`plan`/`verify` 通过）。
- 当前 M10 产品 debug APK：`V:/coding/kelivo-private/.tower/worktrees/wt-10/.build/worktrees/5b1cde0304e687b9/build/app/outputs/flutter-apk/app-debug.apk`，181,373,590 字节，SHA-256 `581d56fc03fe716c768f2554015115bffd8e2b0d610c71e74f5d3b21524703a3`；debug merged manifest 含 `SecureWindowFixtureActivity`，release merged manifest 不含该夹具（不宣称签名 release）。
- 三个工具：`phone_agent_screenshot`、`phone_agent_tree`、`phone_agent_input`。
- 每助手独立 `localToolId='phone_agent'`；Mods 页提供关闭/原生手机控制/Phone Agent 三态单选，已有助手不自动迁移。
- 观察按需发生，不强制每步重新读取完整树；工具 schema 不暴露 `snapshot_id`。
- `supported` 只表示 API 30+ 截图能力；API 29 仍可 ready 并使用树/节点输入。

本轮 M10 已通过的检查：

- 只读 `dart tool/mod_loader.dart plan`：`modsetHash` 与最终树一致；`verify` 校验通过。
- API35 完整异常套件：`+5 ~1`、`All tests passed!`、EXIT=0；权限窗口明确 skip。
- API35/API29 官方 `phone_agent_test.dart` 各 2 项通过、EXIT=0（按指示未重复运行）。
- 既有 Loader 165、聚焦工具测试 32、`dart analyze --fatal-infos`、插件 Dart 17、插件 Kotlin 66、上游 PhoneControl 49 结果保留，本轮未重复。
- 历史 VLM 轮（magpie `llama-cpp/llama-cpp`）使用旧树 `V:/coding/kelivo-private/.tower/worktrees/wt-6/.build/worktrees/5f0be65f98bb04e5` 和旧 APK 181369230 字节 / SHA-256 `3ea30ee9b46342305cf11e0574b76def9a42f23abe62dd3536b664dc4ec5caeb`，只作历史记录，不代表当前实现。

API 29 真机结果、双 API 集成测试和任何后续改动后的数字以 `docs/phone-agent-plan.md` 9.3/9.4 与 `mods/phone_agent/README.md` 的最新记录为准，不得沿用旧结果冒充新实现通过。

## 4. 上一轮 VLM 验收证据（历史，magpie `llama-cpp/llama-cpp`）

环境与适用范围：

- 设备：API 35 模拟器 `emulator-5554`（Android 15，内部屏幕 1080x2424）。
- 模型：magpie 网关的 `llama-cpp/llama-cpp`（Text、Image → Text、Tools）；应用内 provider 地址 `http://10.0.2.2:3425/v1`，UI 勾选 Image 输入和 Tools。局域网访问由用户开启，密钥未修改、未读取、未记录。
- 服务：Mods 页 Default Assistant 选择 Phone Agent，独立服务 enabled && connected，API 35 ready；未启用原生手机控制，未写系统无障碍授权。
- 适用范围：只验证该 magpie 模型与 API 35 模拟器，不承诺任意模型或设备；物理 API 30+ 真机 VLM 仍未验证。

证据 A：工具暴露与最小截图 → 图片 → 模型链路

- REQ27（15:00:52）请求工具为 `read_file` + `phone_agent_screenshot` / `phone_agent_tree` / `phone_agent_input`；`read_file` 是上游工具，不属于 Mod schema。无原生 `phone_control`，无重复 `phone_agent_*`；三个 schema 均无 `snapshot_id`，均设置 `additionalProperties: false`。
- REQ28（15:00:58，Request Log ID28）携带 `phone_agent_screenshot` 工具结果：`image 713x1600`、`screen 1080x2424`、`package_name com.psyche.kelivo.phoneagent`；并包含一条合成 user 消息，`image_url` 为 `data:image/png;base64,<omitted 185028 chars>`，`detail` 为 `high`。
- 响应头 `x-magpie-model: llama-cpp/llama-cpp`、`x-magpie-provider: llama-cpp`；模型回答 `3:00 / New Chat / llama-cpp/llama-cpp (Magpie VLM)`，与截图中的时间、聊天标题和模型名称一致。

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
- 本轮未使用坐标动作完成任务；坐标手势的 UI 效果仍受 integration_test 绑定限制，未在物理 API 30+ 真机验证。
- 本轮没有确认私有 Mod 硬缺陷；上述一次 `stale_handle` 证据有限，根因未查明。契约内的可恢复错误不写成产品假成功。
- 该轮仍明确未验证：物理 API 30+ 真机的 VLM 固定任务与坐标手势 UI 效果、签名 release；真实 `FLAG_SECURE`、旋转、home/recents、锁屏、服务禁用/重启已由后续 M10 在 API35 模拟器补充（见第 0 节），但不代表物理 API30+ 或其他 Android 版本。
- 本轮只验证 magpie `llama-cpp/llama-cpp` 与 API 35 模拟器，不承诺任意模型或设备。
- 文档只记录脱敏后的请求形态和尺寸/长度，不记录 provider 密钥、完整会话文本或截图字节。

上一轮 LM Studio 补充环境（历史结果，不能取代本轮结论）：

- Request Log ID18 显示 `image/png · 47.7 KB · omitted`，Authorization 已脱敏；后续请求 `image_url` 为 `data:image/png;base64,<omitted 163212 chars>`，`detail` 为 `high`；模型读出 `10:47 / New Chat / bonsai-vlm (Local VLM)`。
- 固定任务完成 tree → tap `Search settings` → tree → `set_text Phone` → `n1 scroll down` 返回 `action_unavailable` → 截图确认；补充滚动先返回 `stale_handle`，重读树后 `n4` ScrollView `forward` 成功并显示 `Sponsor`。
- 4096 上下文下复杂任务出现截图/读树循环，8192 后完成；这是本地测试经验，不是产品运行时要求。

## 5. 上一轮新增聚焦测试（历史，该轮未改测试）

该轮只改中文文档，未新增或修改测试；该标签仅适用于该历史 VLM 文档轮，不代表当前 M10；M10 已新增并运行异常/聚焦测试。以下为上一轮新增的测试，保留作回归说明。

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

- 本轮指定环境：magpie 网关的 `llama-cpp/llama-cpp`，应用内 provider 地址 `http://10.0.2.2:3425/v1`，UI 勾选 Image 输入和 Tools；局域网访问由用户开启，密钥未修改、未读取、未记录。
- 补充环境（上一轮）：LM Studio `prism-ml/bonsai-27b`，identifier `bonsai-vlm`，建议 `-c 8192`，模拟器地址 `http://10.0.2.2:1234/v1`；该结果不能取代本轮指定模型结论。
- 应用内模型需同时勾选 Image 输入和 Tools 能力，否则 Mod 不激活或截图工具不暴露。
- 测试结束后停止本地网关/LM Studio、卸载模型；设备上的 provider 和测试会话是测试状态，不是仓库交付物。

### Windows 环境

- Flutter 全局使用 JDK 17：`flutter config --jdk-dir="C:/Users/David/scoop/apps/openjdk17/current"`；不要切回 JDK 25。
- 私有仓 `core.autocrlf=true`，Tower 创建的 worktree 会以 CRLF 检出全部文件，导致 Loader 补丁无法应用、`dart format` 失败。处理方式：在 worktree 内执行 `git ls-files -z | xargs -0 perl -pi -e 's/\r\n/\n/g'` 就地转 LF，不改仓库 config。转换后 `git status` 会把大量文件标为 M（stat 噪声），但 `git diff --name-only` 只显示真实改动。未转 LF 时 `plan` 的 `modsetHash` 也会因 CRLF 字节不同而偏差；比对哈希前先按上述方式转 LF。
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

仍未完成或不能宣称完成：物理 API 30+ 真机的 VLM 固定任务和坐标手势 UI 效果、权限窗口、签名 release、原生超时；一次未复现的 `stale_handle` 根因未确认，重读树后恢复，未修复。API35 模拟器已验证 secure 截图行为、旋转、home/recents、锁屏、服务禁用/重启；真实 `FLAG_SECURE` 已从“未验证”移出，但只代表 API35 模拟器，不代表所有 Android 版本/设备。跨新用户轮次历史图片回放已在 API 35 模拟器通过，不再列为未验证。只验证 magpie `llama-cpp/llama-cpp` 与 API 35 模拟器，不承诺任意模型。上游仓保持只读；不向上游提交或推送私有实现。
