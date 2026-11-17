# Kelivo 私有 Mod 工作区

本仓库用于在上游 Kelivo 源码之外维护编译前 Mod。通用 Mod Loader 已完成验收；`phone_agent` Mod 已实现精简实用方案，并经用户真机确认功能正常。

- 上游源码：`V:/coding/kelivo`
- 当前固定基线：`73afa4ec77cfc9af2efea2487fee8bba1362639d`
- Loader 实施计划：`docs/mod-loader-plan.md`
- Phone Agent 实施计划：`docs/phone-agent-plan.md`
- 协作与验证规则：`AGENTS.md`

`mods.json` 当前启用 `mods/phone_agent`。该 Mod 的合成、工具契约、测试包白名单和未验证项见 `mods/phone_agent/README.md`；真机与 VLM 验收不能由自动化测试替代。

## 命令

在私有仓根目录执行：

```bash
dart tool/mod_loader.dart plan
dart tool/mod_loader.dart apply
dart tool/mod_loader.dart verify
dart tool/mod_loader.dart rebase-drill --to <完整 commit>
dart tool/mod_loader.dart clean --modset <完整哈希或 16 位前缀>
```

- `plan` 只读打印基线、`modsetHash`、合成目录、Loader overlay、接缝补丁、Mod 顺序、补丁和复制目标，不写文件。
- `apply` 在 `.build/worktrees/<modsetHash 前 16 位>/` 创建或复用 detached worktree，创建时显式使用 `git -c core.longpaths=true -c core.autocrlf=false worktree add`，保证按仓库存储的 LF 检出并支持 Windows 超长路径。随后复制 `overlay/`，应用 `patches/tool_mod_seams.patch`，再按顺序应用各 Mod 补丁和 copy，生成 `lib/modding/mod_registry.g.dart` 与 `MOD_BUILD.json`。相同 `modsetHash` 且状态一致时幂等复用。
- `verify` 校验 worktree 状态、HEAD、暂存区补丁哈希、`MOD_BUILD.json`、注册表、复制文件和补丁结果，不执行 Flutter 构建。只允许 `pubspec.lock` 和根项目 Flutter 生成注册文件变化，其他已跟踪漂移失败。
- `rebase-drill` 在 `.build/drills/` 下的独立临时 worktree 验证新 commit，不修改 `mods.json` 或主合成树；结束后清理临时 worktree。
- `clean` 必须显式提供 `--modset`，只删除 `.build/worktrees/` 下带 Loader 状态记录的精确目标；缺少参数时不删除任何内容。

`MOD_BUILD.json` 记录 Loader 版本、基线、`modsetHash`、每个 Mod 的版本与内容哈希、补丁文件哈希、复制文件哈希、注册表哈希和暂存区 diff 哈希。`modsetHash` 同时包含上游 commit、Loader schema/版本、Loader overlay、接缝补丁和 Mod 内容；任一内容变化都会产生新的合成目录。Loader 不自动执行 `fetch`、`pull`、分支切换、`reset` 或 `clean -fd`。


## 环境要求

- Windows 与 Git Bash；
- Dart SDK 3.12.1 或更高兼容版本；
- Git；
- 合成 Kelivo 后，按上游要求使用 Flutter 和 Android 工具链。

Windows 上即使本机或仓库配置了 `core.autocrlf=true`，Loader 创建合成 worktree 时也会显式关闭自动换行转换，按仓库存储的 LF 检出。不要为此修改上游 Git 配置。

`verify` 允许变化的构建产物只有任意嵌套包的 `pubspec.lock`，以及根项目的以下 Flutter 生成注册文件：

```text
linux/flutter/generated_plugin_registrant.cc
linux/flutter/generated_plugin_registrant.h
linux/flutter/generated_plugins.cmake
macos/Flutter/GeneratedPluginRegistrant.swift
windows/flutter/generated_plugin_registrant.cc
windows/flutter/generated_plugin_registrant.h
windows/flutter/generated_plugins.cmake
```

依赖目录中的示例工程注册文件不在允许范围内。

## 开发检查

```bash
dart pub get
dart format --output=none --set-exit-if-changed tool test
dart analyze tool test
dart test
```

合成 Kelivo 后的完整检查见 `AGENTS.md` 和 Loader 计划。所有生成产物位于 `.build/`，不提交。
