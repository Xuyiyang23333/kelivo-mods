# Kelivo Mod Loader & Phone Agent

[Kelivo](<UPSTREAM_KELIVO_REPO_URL>) 的编译前源码 Mod Loader 与 `phone_agent` Mod 仓库。

在不直接修改或污染上游 Kelivo 仓库的前提下，通过独立的 `overlay/`、`patches/` 与插件目录，将定制功能合成为可构建的独立 Git worktree。

- 默认上游路径：`../kelivo`（可在 [mods.json](mods.json) 中调整）
- 当前固定上游基线：`73afa4ec77cfc9af2efea2487fee8bba1362639d`
- 开源协议：[MPL-2.0](LICENSE)

## 仓库包含内容

- **通用 Mod Loader（`tool/`、`overlay/`、`patches/`）**
  - 仅依赖 Dart SDK 与 Git，通过 `git worktree` + `git apply --check` + 内容哈希校验，在 `.build/worktrees/<hash16>/` 中幂等合成上游源码。
  - 支持 `plan`、`apply`、`verify`、`rebase-drill`、`clean` 命令。
- **Phone Agent Mod（`mods/phone_agent/`）**
  - 独立的 `kelivo_phone_agent` Flutter 插件与 Android 无障碍服务（`PhoneAgentService`），不修改上游 `PhoneControlService`。
  - 与上游原生 `phone_control` 在助手维度互斥切换。
  - 提供 `phone_agent_screenshot`（视觉模型可用，支持密码区域涂黑与点击准星标注）、`phone_agent_tree`（有界节点树，过滤密码子树）和 `phone_agent_input`（节点动作、归一化坐标手势、系统导航、`wait`、`list_apps`、`open_app` 与 `batch` 批量动作）。
  - 保留系统敏感入口硬基线（`HARD_BASELINE_PACKAGES`）、默认电话/短信保护、密码节点防护及轻量前台可视化叠加层。
  - 默认包含 [application-id.patch](mods/phone_agent/patches/application-id.patch)，将包名设为 `com.psyche.kelivo.phoneagent`、应用名设为 `Kelivo Agent`，以便与官方 Kelivo 并存安装测试；如不需要共存，可从 [mods/phone_agent/mod.json](mods/phone_agent/mod.json) 中移除该补丁。

详细信息见 [mods/phone_agent/README.md](mods/phone_agent/README.md)、[docs/mod-loader-plan.md](docs/mod-loader-plan.md) 与 [docs/phone-agent-plan.md](docs/phone-agent-plan.md)。

## 快速开始

### 1. 准备环境

- Dart SDK 3.12.1 或更高版本
- Git
- Flutter 与 Android 构建工具链（用于构建合成后的 Kelivo）

### 2. 克隆上游与本仓库

将上游 Kelivo 与本仓库放在同一父目录下（默认 `mods.json` 读取 `../kelivo`）：

```bash
git clone <UPSTREAM_KELIVO_REPO_URL> kelivo
git -C kelivo checkout 73afa4ec77cfc9af2efea2487fee8bba1362639d

git clone <THIS_REPO_URL> kelivo-mods
cd kelivo-mods
```

> 如果你的上游目录不在 `../kelivo`，请修改 [mods.json](mods.json) 中的 `upstream.path`。

### 3. 合成并构建

```bash
dart pub get
dart tool/mod_loader.dart plan
dart tool/mod_loader.dart apply
dart tool/mod_loader.dart verify
```

`apply` 会在 `.build/worktrees/<modsetHash 前 16 位>/` 生成合成后的 Kelivo 工作树。进入该目录后即可按上游方式获取依赖并构建：

```bash
cd .build/worktrees/<hash16>
flutter pub get
flutter build apk --debug
```

安装后，在 Kelivo「设置 → Mods」中为对应助手启用 `Phone Agent`，并在 Android 系统无障碍设置中开启 `Kelivo Phone Agent` 服务即可使用。

## Loader 命令说明

```bash
dart tool/mod_loader.dart plan
dart tool/mod_loader.dart apply
dart tool/mod_loader.dart verify
dart tool/mod_loader.dart rebase-drill --to <完整 commit>
dart tool/mod_loader.dart clean --modset <完整哈希或 16 位前缀>
```

- `plan`：只读输出基线、`modsetHash`、合成目录、补丁与复制目标，不写文件。
- `apply`：创建或复用 detached worktree（Windows 上显式使用 `-c core.longpaths=true -c core.autocrlf=false`），依次应用接缝补丁、Mod 补丁与 `overlay`，生成 `lib/modding/mod_registry.g.dart` 与 `MOD_BUILD.json`。
- `verify`：校验 worktree 状态、HEAD、暂存区补丁哈希、`MOD_BUILD.json`、注册表及文件完整性（不执行 Flutter 构建）。
- `rebase-drill`：在 `.build/drills/` 下临时验证新上游 commit 是否兼容，不修改 `mods.json` 或主合成树。
- `clean`：按 `--modset` 精确清理 `.build/worktrees/` 下由 Loader 管理的合成目录。

## 开发与测试

```bash
# Loader 格式化、静态分析与单元测试
dart format --output=none --set-exit-if-changed tool test
dart analyze tool test
dart test

# Phone Agent 插件 Dart 测试
cd mods/phone_agent/plugin && flutter test
```

更多合成后验证命令见 [AGENTS.md](AGENTS.md)。

## 协议

本项目采用 [Mozilla Public License 2.0 (MPL-2.0)](LICENSE) 开源。
