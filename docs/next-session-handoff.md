# 下一次会话交接：Phone Agent 物理 MIUI 验收

## 0. M16 当前状态（2026-11-11）

- 本轮目标：把物理 MIUI API31 真机（Redmi K30 5G，`1960cd68`）的验收结果写入中文文档；只改 `AGENTS.md`、`docs/phone-agent-plan.md`、本文件、`mods/phone_agent/README.md` 和 `mods/phone_agent/plugin/README.md`，不改产品代码、测试、`mod.json`、schema、白名单或上游。
- 最终源码 `modsetHash`：`3d3cd25b4def35633dcf848373037cbe2c5200f795339c315b3ac9c3268a3174`；合成树：`V:/coding/kelivo-private/.tower/worktrees/wt-16/.build/worktrees/3d3cd25b4def3563`；`plan`/`apply`/`verify` 通过。
- 产品 debug APK（在该新树显式 `flutter build apk --debug` 生成，未在该树随后运行 integration_test）：**181,369,890 字节**，SHA-256 `c6f20d250239bae223a4fdaa5ff1807ba34eab38bd8f9e7f9710e8c21747a58b`；debug merged manifest 含 `SecureWindowFixtureActivity`，release merged manifest 不含该夹具（不宣称签名 release）。
- 设备证据来自此前相同代码/测试行为，未在新树重跑设备；新树只包含文档变化。
- 物理 MIUI API31 已通过：独立测试包安装与服务 enabled && connected、Mods 三态选择、真实截图/读树/节点输入/滚动、物理 `FLAG_SECURE`（成功黑图，清除后恢复）、旋转失效（`stale_handle` / `stale_observation`）、`llama-cpp/llama-cpp` 的坐标 tap 真实打开抽屉/Settings/Search 与 `set_text Phone`、magpie `mistral/deepseek-v4-1-flash-1017` 的真实图片请求、坐标 swipe 前后 PNG 证实 Sponsor 可见、像素专属视觉确认（`bright cyan` + `PHONE_AGENT_SECURE_FIXTURE`，与 PNG rgb(0,200,255) 一致）。
- 官方测试间歇性：同一最终树、同一命令两次结果不同，第一次 `+1 -1`、EXIT=1（聚焦后 `set_text` 返回 `stale_handle`，`The target node changed`，属 `ObservationRegistry` 的 refresh/isVisibleToUser/isEnabled 前置分支，不是旧聚焦指纹路径），第二次 `+2`、EXIT=0。根因未确认、未修复，需要后续诊断与统计，不能写成稳定通过。
- 授权例外：用户明确授权仅在该 MIUI 测试设备上用 `settings put secure` 预配置 Phone Agent；原始 `enabled_accessibility_services` 为空串、`accessibility_enabled=0`，每轮结束恢复。该例外不改变产品自动授权边界，其他设备默认仍禁止自动写系统授权。
- `flutter test` 会把树内 `build/app/outputs/flutter-apk/app-debug.apk` 覆盖为测试入口构建；产品 APK 必须显式 `flutter build apk --debug` 重新生成并重新计算大小/SHA-256，不能沿用旧哈希。
- 未验证：权限窗口、原生超时、签名 release、`stale_handle` 根因；物理设备未运行锁屏、home/recents、服务中断；`llama-cpp/llama-cpp` 的物理完整坐标 swipe 未完成。不能从 API35 模拟器结果推断物理设备。

## 1. 新会话与仓库

请在 `V:/coding/kelivo-private` 新建会话，不要以 `V:/coding` 或 `V:/coding/kelivo` 作为 Tower 工作区。

- `V:/coding/kelivo` 是只读上游源码来源，不直接修改、不创建 Mod 工作分支。
- `V:/coding/kelivo-private` 是私有 Mod 工作区，包含 Loader、Phone Agent、中文文档与测试。
- 先阅读私有仓根目录 `AGENTS.md`。合成树位于 `.build/worktrees/`，不能手工修改其中源码来交付功能；契约变化先改中文文档，再改私有仓的 overlay/补丁，并通过 Loader 生成新合成树。
- 私有仓本地 Git email 已设置为 `xuyiyang23333@gmail.com`。
- 私有仓现有源码和文档必须完整保留；不要通过 reset、clean 或重新初始化覆盖它们。

## 2. 当前目标与阶段

第一阶段 Mod Loader 已完成。第二阶段 Phone Agent 的主要功能已完成。当前 M16 把物理 MIUI API31 真机的验收结果写入文档：`llama-cpp/llama-cpp` 的归一化坐标 tap 与 `mistral/deepseek-v4-1-flash-1017` 的归一化坐标 swipe 的真实 UI 效果、1017 的图片请求与像素专属视觉确认、物理 `FLAG_SECURE` 和旋转已验证；权限窗口、原生超时、签名 release、`stale_handle` 根因仍未验证，不能宣称全部验收完成。

本轮（M16）已完成：

1. 只改中文文档（`AGENTS.md`、`docs/phone-agent-plan.md`、本文件、两个 README），产品代码/测试/`mod.json`/schema/白名单/上游均未修改。
2. 记录物理 MIUI API31 的设备、授权例外、官方测试间歇性、物理 secure/旋转、`llama-cpp/llama-cpp` 归一化坐标 tap 与 1017 归一化坐标 swipe 的真实 UI 证据、1017 的图片请求与像素专属视觉证据。
3. 按 LF/`core.longpaths` 重新确定性 `plan`/`apply`/`verify`，在新干净合成树显式构建产品 debug APK，并检查 debug/release 夹具隔离。
4. 明确 `flutter test` 会覆盖树内 `app-debug.apk`，产品 APK 必须显式重建；不沿用旧大小/哈希。

当前剩余：

1. 权限窗口 `system_window_denied` 未触发，未验证。
2. 物理设备未运行锁屏、home/recents、服务中断；不能从 API35 模拟器结果推断。
3. 原生截图/手势/通道/worker 排队超时未设备验证。
4. 带合法签名配置的 release 构建。
5. 官方测试在物理设备上出现一次间歇性 `set_text` `stale_handle`（`The target node changed`，refresh/可见/可用前置分支）；根因未确认、未修复，需要诊断与统计。
6. `llama-cpp/llama-cpp` 的物理完整坐标 swipe 未完成（网关故障）。

首版输入仍只开放给测试包名 `com.psyche.kelivo.phoneagent`。不要扩大白名单、引入自动无障碍授权，或把发送/购买/删除确认描述成原生硬护栏。

## 3. 已有实现与交付基线

- 上游基线：`73afa4ec77cfc9af2efea2487fee8bba1362639d`。
- 当前 Mod 版本：`0.2.0`。
- 当前 M16 合成树：`V:/coding/kelivo-private/.tower/worktrees/wt-16/.build/worktrees/3d3cd25b4def3563`。
- 当前 M16 `modsetHash`：`3d3cd25b4def35633dcf848373037cbe2c5200f795339c315b3ac9c3268a3174`（`plan`/`apply`/`verify` 通过）。
- 当前 M16 产品 debug APK：`V:/coding/kelivo-private/.tower/worktrees/wt-16/.build/worktrees/3d3cd25b4def3563/build/app/outputs/flutter-apk/app-debug.apk`，181,369,890 字节，SHA-256 `c6f20d250239bae223a4fdaa5ff1807ba34eab38bd8f9e7f9710e8c21747a58b`；debug merged manifest 含 `SecureWindowFixtureActivity`，release merged manifest 不含该夹具（不宣称签名 release）。该树只含文档变化，未在其后运行 integration_test。
- 三个工具：`phone_agent_screenshot`、`phone_agent_tree`、`phone_agent_input`。
- 每助手独立 `localToolId='phone_agent'`；Mods 页提供关闭/原生手机控制/Phone Agent 三态单选，已有助手不自动迁移。
- 观察按需发生，不强制每步重新读取完整树；工具 schema 不暴露 `snapshot_id`。
- `supported` 只表示 API 30+ 截图能力；API 29 仍可 ready 并使用树/节点输入。

本轮 M16 已通过的检查：

- 只读 `dart tool/mod_loader.dart plan`：`modsetHash` 与最终树一致；`apply` 新建合成树；`verify` 校验通过。
- 新合成树 `flutter pub get`、`flutter pub get --directory tool/l10n --enforce-lockfile` 通过；`dart analyze --fatal-infos lib test integration_test tool` 输出 `No issues found!`、EXIT=0；显式 `flutter build apk --debug` 成功（`√ Built build\app\outputs\flutter-apk\app-debug.apk`，EXIT=0），生成上条 APK。
- debug merged manifest 含 `com.kelivo.phoneagent.SecureWindowFixtureActivity` 与 `PhoneAgentService`；release merged manifest（`:app:processReleaseMainManifest`）含 `PhoneAgentService`、不含该夹具，夹具隔离通过（不宣称签名 release）。
- 构建环境备注：首次构建因 Kotlin 增量缓存跨盘报 `Could not close incremental caches ... different roots` / `Daemon compilation failed: null`，`./gradlew --stop` 并删除树内 `build/` 后重建成功；这是构建缓存问题，不是产品缺陷。
- 设备证据沿用此前相同代码/测试行为（`docs/phone-agent-plan.md` 9.3.2、9.4.2），新树未重跑设备；不要求重跑未改变的设备/静态套件。
- 既有 Loader 165、聚焦工具测试 32、插件 Dart 17、插件 Kotlin 66、上游 PhoneControl 49、API35 完整异常套件 `+5 ~1`、API35/API29 官方测试各 2 项结果保留，本轮未重复。
- 历史 VLM 轮（magpie `llama-cpp/llama-cpp`）使用旧树 `V:/coding/kelivo-private/.tower/worktrees/wt-6/.build/worktrees/5f0be65f98bb04e5` 和旧 APK 181369230 字节 / SHA-256 `3ea30ee9b46342305cf11e0574b76def9a42f23abe62dd3536b664dc4ec5caeb`，只作历史记录，不代表当前实现。

API 29 真机结果、双 API 集成测试和任何后续改动后的数字以 `docs/phone-agent-plan.md` 9.3/9.4 与 `mods/phone_agent/README.md` 的最新记录为准，不得沿用旧结果冒充新实现通过。

## 4. VLM 验收证据

### 4.1 历史（API 35 模拟器，magpie `llama-cpp/llama-cpp`）

环境与适用范围：

- 设备：API 35 模拟器 `emulator-5554`（Android 15，内部屏幕 1080x2424）。
- 模型：magpie 网关的 `llama-cpp/llama-cpp`（Text、Image → Text、Tools）；应用内 provider 地址 `http://10.0.2.2:3425/v1`，UI 勾选 Image 输入和 Tools。局域网访问由用户开启，密钥未修改、未读取、未记录。
- 服务：Mods 页 Default Assistant 选择 Phone Agent，独立服务 enabled && connected，API 35 ready；未启用原生手机控制，未写系统无障碍授权。
- 适用范围：只验证该 magpie 模型与 API 35 模拟器，不承诺任意模型或设备；物理真机的 VLM 结果见 4.2。

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

### 4.2 当前（物理 MIUI API31，magpie `mistral/deepseek-v4-1-flash-1017`）

环境与适用范围：

- 设备：Redmi K30 5G（`1960cd68`，picasso），Android 12 / API 31，1080x2400，density 440，MIUI V13.0.3.0.SGICNXM；用户提供并授权测试，无重要数据。
- 模型：magpie 的 `mistral/deepseek-v4-1-flash-1017`（用户更正目标为 1017，不是 0731；Bonsai 未使用）。magpie 侧该模型未标图片输入，Kelivo 手动勾选图片后真实请求全部 200，响应头 `x-magpie-model` / `x-magpie-provider` 与请求一致。
- 服务：Mods 页选择 Phone Agent，独立服务 enabled && connected；测试包 `com.psyche.kelivo.phoneagent`，未覆盖上游 Kelivo。
- 授权例外：用户明确授权仅在该设备用 `settings put secure` 预配置 Phone Agent；原始 `enabled_accessibility_services` 为空串、`accessibility_enabled=0`，每轮结束恢复。该例外不改变产品自动授权边界。
- 适用范围：只验证该模型与这台物理设备，不承诺任意模型或设备。

证据 A：工具暴露与截图尺寸

- 工具集为 `read_file` + 三个 `phone_agent_*`，无 `phone_control`、无重复、无 `snapshot_id`、`additionalProperties=false`。
- 截图 `image 720x1600`，`screen 1080x2400`，package `com.psyche.kelivo.phoneagent`。

证据 B：坐标动作的物理 UI 效果

- `llama-cpp/llama-cpp` 轮：归一化坐标 tap 真实打开应用抽屉、Settings 和 Search，`set_text Phone` 成功并确认 Phone Control；后续 swipe 因网关故障未完成，该模型完整坐标 swipe 仍属未验证。
- `mistral/deepseek-v4-1-flash-1017` 轮：实际工具序列进入 Kelivo 应用内 Settings 后，一次 `phone_agent_input` swipe `{x:0.5,y:0.8,end_x:0.5,end_y:0.3,duration_ms:400}`，前后 PNG 证实 Sponsor 从不可见变为可见。这是物理坐标 UI 效果，不是 integration_test 回调推断。

证据 C：像素专属视觉确认

- 新建无历史会话，只允许一次 `phone_agent_screenshot`，禁止 tree/input，提示不透露颜色或文本。
- 1017 回答 `bright cyan (light blue)` 和 `PHONE_AGENT_SECURE_FIXTURE`，与保存 PNG 的 rgb(0,200,255) 及完整文字一致。
- 该轮请求只有一个截图 `tool_call`，`image_url` 为 `data:image/png;base64,<omitted 39204 chars>`，请求全文不含 `PHONE_AGENT`，构成后端视觉消费的直接支持证据，但不是对模型内部机制的绝对证明。

证据边界：

- 第一轮过渡帧出现黑色区域和文本裁切，后续截图应等界面稳定。
- 网关 `api_error` / 空响应属外部故障，与产品坐标动作失败分开记录，不写成产品缺陷。
- 只记录脱敏后的请求形态和尺寸/长度，不记录密钥、完整会话或图片字节。

## 5. 上一轮新增聚焦测试（历史，该轮未改测试）

该轮只改中文文档，未新增或修改测试；该标签仅适用于该历史 VLM 文档轮，不代表当前 M16（M10 历史轮已新增并运行异常/聚焦测试）。以下为上一轮新增的测试，保留作回归说明。

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
- 物理 MIUI 真机：Redmi K30 5G（picasso），ADB ID `1960cd68`，Android 12 / API 31，`1080x2400`，density 440，MIUI V13.0.3.0.SGICNXM；用户提供并授权测试，安装的测试包为 `com.psyche.kelivo.phoneagent`。
- 执行任何设备命令前用 `adb devices -l` 重新确认，命令必须带 `-s`。

### 无障碍授权流程（重要）

- 安装测试包和部分收尾的 force-stop **可能**清除系统无障碍授权；每轮都要用 `settings get secure enabled_accessibility_services` 和 `dumpsys accessibility` 检查真实状态，不要假设一定被清除或一定保留。
- 集成测试在 `setUpAll` 打印 `PHONE_AGENT_WAITING_FOR_SERVICE` 后等待约 300 秒（600 × 500ms），需要在该窗口内通过系统界面重新启用服务。
- 服务组件：`com.psyche.kelivo.phoneagent/com.kelivo.phoneagent.PhoneAgentService`；只启用 **Kelivo Phone Agent**，不要启用 **Kelivo phone control**。
- 启用后把 `Kelivo Agent` 应用切回前台并保持，直到测试结束。
- 默认不要用 `settings put secure` 写入授权绕过系统确认。唯一例外：用户已明确授权在物理 MIUI 测试设备 `1960cd68` 上用 `settings put secure` 预配置 Phone Agent，仅限该设备与 Phone Agent；必须保存原始 `enabled_accessibility_services`（空串）和 `accessibility_enabled`（0），结束时恢复。该例外不是产品能力，也不适用于其他设备。

### 本地 VLM 环境（测试经验，不是产品依赖）

- 物理 MIUI 本轮指定模型：magpie 的 `mistral/deepseek-v4-1-flash-1017`（不是 0731）；magpie 侧未标图片输入，需在 Kelivo 手动勾选图片，真实请求全部 200。模型能力标注可能变化，每次都要实测。
- 历史环境：magpie 网关的 `llama-cpp/llama-cpp`，应用内 provider 地址 `http://10.0.2.2:3425/v1`，UI 勾选 Image 输入和 Tools；局域网访问由用户开启，密钥未修改、未读取、未记录。
- 补充环境（历史）：LM Studio `prism-ml/bonsai-27b`，identifier `bonsai-vlm`，建议 `-c 8192`，模拟器地址 `http://10.0.2.2:1234/v1`；该结果不能取代 magpie 模型结论。
- 应用内模型需同时勾选 Image 输入和 Tools 能力，否则 Mod 不激活或截图工具不暴露。
- 测试结束后停止本地网关/LM Studio、卸载模型；设备上的 provider 和测试会话是测试状态，不是仓库交付物。

### Windows 环境

- Flutter 全局使用 JDK 17：`flutter config --jdk-dir="C:/Users/David/scoop/apps/openjdk17/current"`；不要切回 JDK 25。
- 私有仓 `core.autocrlf=true`，Tower 创建的 worktree 会以 CRLF 检出全部文件，导致 Loader 补丁无法应用、`dart format` 失败。处理方式：在 worktree 内执行 `git ls-files -z | xargs -0 perl -pi -e 's/\r\n/\n/g'` 就地转 LF，不改仓库 config。转换后 `git status` 会把大量文件标为 M（stat 噪声），但 `git diff --name-only` 只显示真实改动。未转 LF 时 `plan` 的 `modsetHash` 也会因 CRLF 字节不同而偏差；比对哈希前先按上述方式转 LF。
- 本任务 worktree 路径较长，合成树会超过 Windows `MAX_PATH`。生成时使用环境变量注入 Git 长路径支持（不修改任何配置文件）：

```bash
cd V:/coding/kelivo-private/.tower/worktrees/wt-16
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.longpaths GIT_CONFIG_VALUE_0=true
dart tool/mod_loader.dart plan
dart tool/mod_loader.dart apply
dart tool/mod_loader.dart verify
```

- 合成树内 `android/gradlew` 由 Flutter 生成：先执行 `flutter build apk --debug --config-only`，再运行 `./gradlew :kelivo_phone_agent:testDebugUnitTest`。模块名已通过 `./gradlew projects` 确认为 `:kelivo_phone_agent`。
- 若 `flutter build apk --debug` 报 Kotlin `Could not close incremental caches ... different roots` 或 `Daemon compilation failed: null`（pub cache 在 `C:`、合成树在 `V:` 时常见），先 `cd android && ./gradlew --stop`，再删除合成树的 `build/` 后重试；这是构建缓存问题，不是产品缺陷，也不要为此修改源码。
- 提交时只精确暂存实际交付文件，避免把无内容差异的 CRLF stat 噪声加入提交。

## 7. 验证顺序与后续交付

1. 改动契约时先更新 `AGENTS.md`、`docs/phone-agent-plan.md`、`mods/phone_agent/README.md`，再改实现和测试。
2. Loader：`dart format --output=none --set-exit-if-changed tool test`、`dart analyze tool test`、`dart test`、`dart tool/mod_loader.dart verify`。
3. 合成树：`flutter pub get`、`flutter pub get --directory tool/l10n --enforce-lockfile`、`dart format`、`dart analyze --fatal-infos lib test integration_test tool`、Phone Agent/Mods/settings 测试、上游 `tool_result_content` 回归。
4. 插件 Kotlin 测试（修改插件时）：`cd android && ./gradlew :kelivo_phone_agent:testDebugUnitTest`。
5. 设备：API 35（`-d emulator-5554`）、API 29（`-d 357784090209204`）、物理 MIUI（`-d 1960cd68`）；安装后按第 6 节流程授权。
6. 修改产品代码或插件后重新构建 APK 并计算大小与 SHA-256；不要沿用旧哈希。只改文档时仍要显式 `flutter build apk --debug` 生成当前产品 APK，因为 `flutter test` 会把树内 `app-debug.apk` 覆盖为测试入口构建；产品构建后不要在同一树运行 integration_test 而不重建。
7. 更新中文验收记录和本交接文档，如实写明未验证项。

仍未完成或不能宣称完成：权限窗口、签名 release、原生超时、`stale_handle` 根因；物理设备未运行锁屏、home/recents、服务中断，不能从 API35 模拟器结果推断；`llama-cpp/llama-cpp` 的物理完整坐标 swipe 未完成。物理 MIUI API31 已验证真实截图/读树/节点输入/滚动、物理 `FLAG_SECURE`、旋转，以及 `mistral/deepseek-v4-1-flash-1017` 的真实图片请求、坐标 swipe 的 UI 效果和像素专属视觉确认。API35 模拟器已验证 secure 截图行为、旋转、home/recents、锁屏、服务禁用/重启；跨新用户轮次历史图片回放已在 API 35 模拟器通过。只验证 magpie `llama-cpp/llama-cpp`、`mistral/deepseek-v4-1-flash-1017` 与这些设备，不承诺任意模型。上游仓保持只读；不向上游提交或推送私有实现。
