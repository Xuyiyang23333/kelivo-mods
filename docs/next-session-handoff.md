# 下一次会话交接：Phone Agent 节点重验修正

## 1. 新会话与仓库

请在 `V:/coding/kelivo-private` 新建会话，不要以 `V:/coding` 或 `V:/coding/kelivo` 作为 Tower 工作区。

- `V:/coding/kelivo` 是只读上游源码来源，不直接修改、不创建 Mod 工作分支。
- `V:/coding/kelivo-private` 是私有 Mod 工作区，包含 Loader、Phone Agent、中文文档与测试。
- 先阅读私有仓根目录 `AGENTS.md`。合成树位于 `.build/worktrees/`，不能手工修改其中源码来交付功能；契约变化先改中文文档，再改私有仓的 overlay/补丁，并通过 Loader 生成新合成树。
- 私有仓本地 Git email 已设置为 `xuyiyang23333@gmail.com`。
- 私有仓现有源码和文档必须完整保留；不要通过 reset、clean 或重新初始化覆盖它们。

## 2. 当前目标与阶段

第一阶段 Mod Loader 已完成。第二阶段 Phone Agent 的主要功能已完成，仍处于设备联调阶段，不能宣称全部验收完成。

本轮已完成：

1. 修正点击/聚焦后 `set_text` 返回 `stale_handle` 的问题。
2. API 35 模拟器（`emulator-5554`）官方集成测试退出码 0。
3. 更新节点重验契约、测试和中文验收记录。

当前剩余：

1. API 29 真机 `357784090209204` 回归（安装测试包会清除无障碍授权，需要人工在手机上重新启用服务）。
2. VLM 图片链路和固定任务验证。
3. 真实 `FLAG_SECURE`、旋转/切窗/锁屏/禁用服务/超时等异常路径。
4. 带合法签名配置的 release 构建。

首版输入仍只开放给测试包名 `com.psyche.kelivo.phoneagent`。不要扩大白名单、引入自动无障碍授权，或把发送/购买/删除确认描述成原生硬护栏。

## 3. 已有实现与交付基线

- 上游基线：`73afa4ec77cfc9af2efea2487fee8bba1362639d`。
- 当前 Mod 版本：`0.2.0`。
- 本轮合成树：`V:/coding/kelivo-private/.tower/worktrees/wt-1/.build/worktrees/4e072ae5edcd23b6`。
- 本轮 `modsetHash`：`4e072ae5edcd23b6ad9aa081263ecb9c02ed967e0e091fab03d32aee5255f92b`。
- 三个工具：`phone_agent_screenshot`、`phone_agent_tree`、`phone_agent_input`。
- 每助手独立 `localToolId='phone_agent'`；Mods 页提供关闭/原生手机控制/Phone Agent 三态单选，已有助手不自动迁移。
- 观察按需发生，不强制每步重新读取完整树；工具 schema 不暴露 `snapshot_id`。
- `supported` 只表示 API 30+ 截图能力；API 29 仍可 ready 并使用树/节点输入。

本轮已通过的检查：

- Loader `dart format`、`dart analyze tool test`、165 项测试、`dart tool/mod_loader.dart verify`。
- 新合成树 `dart format`、`dart analyze --fatal-infos lib test integration_test tool`。
- Phone Agent 103 项、Mods 16 项、settings 入口 2 项。
- 插件 Dart 17 项、插件 Kotlin 62 项、上游 `PhoneControlServiceTest` 49 项。
- API 35 模拟器官方集成测试退出码 0，2 个用例通过。
- 产品 debug APK：`V:/coding/kelivo-private/.tower/worktrees/wt-1/.build/worktrees/4e072ae5edcd23b6/build/app/outputs/flutter-apk/app-debug.apk`，213415604 字节，SHA-256 `436f6f56c50b4da8a1bf6bc6c8610aea9521858e4283f6d2489a3eef27095860`。

API 29 真机结果和任何后续改动后的数字以 `docs/phone-agent-plan.md` 9.3 与 `mods/phone_agent/README.md` 的最新记录为准，不得沿用旧结果冒充新实现通过。

## 4. 本轮修正内容与契约

问题：`PhoneNode.fingerprint()` 曾包含 `isFocused` 和 `isSelected`，`ObservationRegistry.handle()` 在 `refresh()` 后比较完整指纹；点击输入框造成焦点变化，使后续 `set_text` 返回 `stale_handle`。

设备取证结果（API 35）：

- 移除 `isFocused` 后 `set_text` 仍失败，诊断信息为 `stale_handle The target node changed (actions)`。
- 说明聚焦还会增减节点动作集合；`actions` 是执行期能力，不是节点身份。

最终契约（详见 `docs/phone-agent-plan.md` 6.5.1）：

- 指纹不包含 `bounds`、`isFocused`、`actions`。
- `isSelected`、内容（text/description/hint/state）、稳定能力字段（enabled/editable/clickable/long-clickable/scrollable/checkable/checked）、password、类名、viewId、窗口、包名、尺寸、旋转和 120 秒 TTL 变化仍失效。
- 动作可用性由 `NodeActionExecutor` 在动作前按当前节点重新校验，不可用返回 `action_unavailable`。
- 指纹改为 `name=value` 形式；`stale_handle` 附带发生变化的字段名（只含字段名，不含文本内容）。

测试：

- 修正前用同一套插件测试复现：61 项中 2 项 focus 用例失败。
- 新增：focus false→true 后复用句柄并 `set_text`、focus true→false 后复用、action-only 变化可复用、selected-only 变化拒绝、`isScrollable` 变化拒绝、禁用节点、句柄 TTL。
- 集成测试：聚焦后使用同一观测句柄 `set_text`；坐标滑动放在聚焦之前；随后用无障碍节点滚动验证列表真的滚动。

集成测试的坐标手势边界：

- `flutter_test` 的 `LiveTestWidgetsFlutterBinding` 默认 `shouldPropagateDevicePointerEvents = false`，设备指针事件只进入诊断 dispatcher，不转发给 widget 树；绑定还会断言测试不得修改该开关。
- 因此集成测试只能验证坐标手势被原生接受并完成（`onGestureCompleted`），不能断言应用侧滚动效果；不要把这个限制写成产品缺陷，也不要宣称坐标手势 UI 效果已验证。

## 5. 设备、授权与环境

### 设备

- API 35 模拟器：`emulator-5554`，AVD `Kelivo_Phone_Agent_API_35`，Android 15，内部屏幕 `1080x2424`。
- API 29 真机：Sharp SG803SH，ADB ID `357784090209204`。
- 执行任何设备命令前用 `adb devices -l` 重新确认，命令必须带 `-s`。

### 无障碍授权流程（重要）

- 安装测试包会清除系统无障碍授权；测试结束时的 force-stop 也会清除授权。
- 集成测试在 `setUpAll` 打印 `PHONE_AGENT_WAITING_FOR_SERVICE` 后等待约 300 秒（600 × 500ms），需要在安装完成后通过系统界面重新启用服务。
- 服务组件：`com.psyche.kelivo.phoneagent/com.kelivo.phoneagent.PhoneAgentService`；只启用 **Kelivo Phone Agent**，不要启用 **Kelivo phone control**。
- 启用后把 `Kelivo Agent` 应用切回前台并保持，直到测试结束。
- 不要用 `settings put secure` 写入授权绕过系统确认。
- 若需要人工操作，通过 TowerSend 报告具体设备、包名、等待窗口和步骤。

### Windows 环境

- Flutter 全局使用 JDK 17：`flutter config --jdk-dir="C:/Users/David/scoop/apps/openjdk17/current"`；不要切回 JDK 25。
- 私有仓 `core.autocrlf=true`，Tower 创建的 worktree 会以 CRLF 检出全部文件，导致 Loader 补丁无法应用、`dart format` 失败。处理方式：在 worktree 内执行 `git ls-files -z | xargs -0 perl -pi -e 's/\r\n/\n/g'` 就地转 LF，不改仓库 config。转换后 `git status` 会把大量文件标为 M（stat 噪声），但 `git diff --name-only` 只显示真实改动。
- 本任务 worktree 路径较长，合成树会超过 Windows `MAX_PATH`。生成时使用环境变量注入 Git 长路径支持（不修改任何配置文件）：

```bash
cd V:/coding/kelivo-private/.tower/worktrees/wt-1
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.longpaths GIT_CONFIG_VALUE_0=true
dart tool/mod_loader.dart plan
dart tool/mod_loader.dart apply
dart tool/mod_loader.dart verify
```

- 合成树内 `android/gradlew` 由 Flutter 生成：先执行 `flutter build apk --debug --config-only`，再运行 `./gradlew :kelivo_phone_agent:testDebugUnitTest`。模块名已通过 `./gradlew projects` 确认为 `:kelivo_phone_agent`。
- 提交时只精确暂存实际交付文件，避免把无内容差异的 CRLF stat 噪声加入提交。

## 6. 验证顺序与后续交付

1. 改动契约时先更新 `AGENTS.md`、`docs/phone-agent-plan.md`、`mods/phone_agent/README.md`，再改实现和测试。
2. 插件 Kotlin 测试：`cd android && ./gradlew :kelivo_phone_agent:testDebugUnitTest`。
3. Loader：`dart format --output=none --set-exit-if-changed tool test`、`dart analyze tool test`、`dart test`、`dart tool/mod_loader.dart verify`。
4. 合成树：`flutter pub get`、`flutter pub get --directory tool/l10n --enforce-lockfile`、`dart format`、`dart analyze --fatal-infos lib test integration_test tool`、Phone Agent/Mods/settings 测试、插件 Dart 测试、上游 `PhoneControlTest`。
5. 设备：先 API 35（`-d emulator-5554`），再 API 29（`-d 357784090209204`）；安装后按第 5 节流程授权。
6. 构建产品 APK 并重新计算大小与 SHA-256；不要沿用旧哈希。
7. 更新中文验收记录和本交接文档，如实写明未验证项。

仍未完成或不能宣称完成：API 29 本轮回归结果、物理 API 30+ 真机的坐标手势 UI 效果、VLM 固定任务与图片链路、真实 `FLAG_SECURE`、完整异常路径、签名 release。上游仓保持只读；不向上游提交或推送私有实现。
