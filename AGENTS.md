# AGENTS.md

## 仓库用途

本仓库是 Kelivo 的私有、编译前源码 Mod 工作区，不提交到上游（`V:/coding/kelivo`）。

- 第一阶段：通用 Mod Loader（`tool/`、`patches/`、`overlay/`），见 [Mod Loader 实施计划](docs/mod-loader-plan.md)。
- 第二阶段：`phone_agent` Mod（`mods/phone_agent/`），提供独立的 Android 无障碍手机控制能力。

## 目录与上游保护规则

- `tool/`、`test/`：Loader CLI 与其 Dart 测试。
- `patches/`、`overlay/`：Loader 通用上游接缝补丁与核心接口，不引入具体业务 Mod 依赖。
- `mods/phone_agent/`：`phone_agent` Mod 的配置、补丁、overlay 与独立 `kelivo_phone_agent` 插件。
- `.build/`：Loader 生成的合成 worktree 与产物，不提交、不手工修改源码。
- `V:/coding/kelivo`：上游仓，只作固定 commit 的源码来源；禁止在上游仓直接开发、提交或推送私有功能。
- 禁止使用 `git reset --hard`、`git clean -fd` 绕过冲突或漂移；禁止读取或提交 `.env`、签名密钥或 `lib/secrets/`。

## Loader 约定

- 运行时只依赖 Dart SDK 与 Git，不引入额外框架依赖。
- Windows 上 Loader 的 git 进程统一使用 `-c core.longpaths=true`，创建合成 worktree 时关闭 `core.autocrlf`。
- `plan` 只读不写；`apply` 幂等；`verify` 不跑 Flutter 构建，仅允许 `pubspec.lock` 与根项目 Flutter 生成注册文件变化。
- 补丁按 `mod.json` 顺序通过 `git apply --check` 后应用，不使用模糊补丁。

## Phone Agent 架构与边界

- **独立服务与插件**：使用独立 `kelivo_phone_agent` 插件、`kelivo/phone_agent` 通道与独立 `PhoneAgentService`，不修改上游 `PhoneControlService`。
- **助手级三态互斥**：`phone_agent` 与上游 `phone_control` 在 Mods 页互斥切换；`LocalToolNames.all` 不加入 `phone_agent`。
- **工具集合**：
  - `phone_agent_screenshot`（仅支持图片输入的视觉模型暴露，API 30+ 可用，密码字段涂黑）
  - `phone_agent_tree`（有界 DFS，密码节点及子树不输出）
  - `phone_agent_input`（`tap`、`long_press`、`set_text`、`scroll`、`swipe`、`back`、`home`、`recents`、`wait`、`list_apps`、`open_app`；坐标手势对所有模型开放，不依赖前置截图）
- **实用安全护栏（不做逐应用白名单审批或本地审计落盘）**：
  - `HARD_BASELINE_PACKAGES`（系统设置、权限控制器、包安装器、证书安装器、`systemui` 与承载包 `com.psyche.kelivo`）与默认电话/短信角色持有者禁止自动化操作。
  - 密码节点禁止 `performNodeAction`，密码区域截图前涂黑；操作前检查设备解锁状态与单次生成/分钟级频率上限。
  - 保留独立 `TYPE_ACCESSIBILITY_OVERLAY` 前台可视化叠加层（`PhoneAgentOverlay`），截图前自动隐藏。
- **体验优先**：功能与体验以**真机 + VLM 端到端实测**为准，不在纯文档与重复 Review 上空转；改动只需同步更新受影响的接口说明，不再维护多份冗长状态流水账。

## 代码风格与验证命令

- 遵循 Dart / Kotlin 官方格式化与项目静态分析规范；优先小文件、清晰职责，默认不写解释显而易见行为的注释。
- 修改 Loader 后运行：
  ```bash
  dart format --output=none --set-exit-if-changed tool test
  dart analyze tool test
  dart test
  ```
- 修改 `phone_agent` 插件后运行：
  - 插件 Dart：`cd mods/phone_agent/plugin && flutter test`
  - 插件 Kotlin（在合成树中）：`./gradlew :kelivo_phone_agent:testDebugUnitTest`（或本地 gradle）
- 合成与检查：
  ```bash
  dart tool/mod_loader.dart apply
  dart tool/mod_loader.dart verify
  ```
- 在合成树（`.build/worktrees/<hash16>/`）运行：
  ```bash
  flutter pub get
  dart analyze --fatal-infos lib test integration_test
  flutter test test/features/phone_agent test/features/mods test/features/settings/pages/mods_settings_entry_test.dart
  flutter test test/features/home/services/tool_handler_service_test.dart test/features/home/services/tool_handler_workspace_gating_test.dart test/request_consistency_test.dart
  ```
- 真实设备闭环测试：在合成树中用 `flutter test integration_test/phone_agent_test.dart -d <device>` 与真实 VLM 对话任务验证。
