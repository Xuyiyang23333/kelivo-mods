# Kelivo 私有 Mod Loader 实施计划

## 0. 文档状态

- 当前阶段：第一阶段，已完成并通过计划内自动化检查与 debug APK 构建验收。
- 本文只定义通用源码 Mod Loader，不包含具体手机自动化工具的实现。
- Phone Agent 是 Loader 完成后的第一个实际 Mod，另见 [Phone Agent 实施计划](phone-agent-plan.md)。
- 基线仓库：`V:/coding/kelivo`。
- 基线分支：`master`。
- 基线 commit：`73afa4ec77cfc9af2efea2487fee8bba1362639d`。
- 实施时将本文和 Phone Agent 计划一并移动到私有仓，随后恢复上游工作区完全干净。

## 1. 目标、原则与非目标

### 1.1 目标

1. 为开发者提供轻量的编译前源码合成工具。
2. 上游 Kelivo 仓只用于跟踪和检出源码，Loader 与 Mod 全部保存在独立私有仓。
3. 从指定上游 commit 创建 Git worktree，再叠加通用补丁、Mod 文件和静态注册表。
4. 用两个稳定的工具链接缝支持 Mod 扩展工具定义和工具调用，而不修改上游本地工具枚举与各个 switch。
5. 同一组上游与 Mod 内容能够确定性重建；上游更新时不兼容必须明确失败。
6. Loader 自身能够独立测试、独立验收，不依赖任何具体业务 Mod 才能证明可用。

### 1.2 原则

- 只做源码合成，不做运行时插件平台。
- 新增文件优先，补丁只用于绕不开的接缝。
- Loader 运行时只依赖 Dart SDK 和 Git，不引入 YAML、AST 或代码改写框架。
- 通过显式配置和固定加载顺序保持确定性，不做自动依赖求解。
- 失败时停止并保留清晰状态，不用破坏性 Git 命令强行修复。
- 每个阶段保持可构建、可测试、可回滚。
- 面向开发者的维护文档使用中文。

### 1.3 非目标

Loader 首版不做：

- 运行时下载、热加载、动态 Dart 加载、Mod 市场或第三方 Mod 沙箱。
- 通用 Mixin、AST 方法改写、自动语义合并或复杂版本范围求解。
- 自动 `fetch`、`pull`、切换上游分支或自动提交补丁。
- 自动处理所有上游冲突，或承诺未来上游版本零维护。
- 具体 Mod 的设置 UI、ARB 本地化、权限模型和业务安全策略。
- 具体 Mod 的功能验收，例如截图、无障碍输入或模型端到端任务。

## 2. 总体结构

```text
干净上游仓
  → 按固定 commit 创建 detached worktree
  → 应用 Loader 自有的通用工具接缝补丁
  → 按顺序应用各 Mod 补丁
  → 复制各 Mod 的新增文件
  → 生成静态 Mod 注册表与构建记录
  → 在合成树中执行标准 Flutter 分析和构建
```

开发目录约定：

```text
V:/coding/kelivo/                 # 上游仓
V:/coding/kelivo-private/         # 私有 Loader 与 Mod 仓
V:/coding/kelivo-private/.build/  # 合成 worktree 和状态，全部忽略
```

Loader 会写入上游仓的 `.git/worktrees/` 元数据，但不修改上游工作区的源码、索引或当前分支。

## 3. 私有仓结构

```text
kelivo-private/
├── pubspec.yaml                 # 仅 Loader 开发/测试使用
├── mods.json                   # 上游路径、固定 commit、Mod 顺序
├── README.md                   # 中文使用与维护说明
├── docs/
│   ├── mod-loader-plan.md
│   └── phone-agent-plan.md
├── patches/
│   └── tool_mod_seams.patch    # Loader 自有的两个通用工具接缝
├── tool/
│   ├── mod_loader.dart         # CLI 入口
│   └── src/
│       ├── config.dart         # 配置解析与校验
│       ├── git.dart            # 参数数组形式的 Git 调用
│       ├── worktree.dart       # worktree 创建、校验与清理
│       ├── patch.dart          # 补丁路径检查和 fail-closed 应用
│       └── registry.dart       # 注册表、内容哈希与构建记录
├── test/
│   ├── mod_loader_test.dart
│   ├── worktree_test.dart
│   ├── patch_test.dart
│   └── registry_test.dart
├── mods/
│   └── <mod-id>/
│       ├── mod.json
│       ├── README.md
│       ├── patches/
│       ├── overlay/
│       └── plugin/             # 仅需要原生插件的 Mod 使用
└── .build/
```

Loader 运行时只 import Dart SDK。测试采用标准的 `package:test`，作为私有仓开发依赖，不维护自写测试框架。

## 4. 配置契约

### 4.1 `mods.json`

首版只保留：

- `schemaVersion`：固定为 `1`。
- `upstream.path`：本机上游仓路径。
- `upstream.commit`：完整 commit SHA。
- `mods[]`：按加载顺序排列的 Mod 相对路径和启用状态。

Loader 不自动解析分支，也不以浮动分支作为构建输入。构建必须来自完整 commit。

### 4.2 每个 Mod 的 `mod.json`

字段限定为：

- `schemaVersion`、`id`、`version`；
- `upstreamCommit`：该 Mod 已验证的上游基线；
- `toolNames`：该 Mod 声明拥有的工具名；
- `registration`：注册类 import 和构造方式；
- `touches`：补丁允许修改的上游相对路径白名单；
- `patches[]`：按顺序应用的补丁；
- `copy[]`：新增文件或目录的源路径、目标路径和排除项；
- `vendored[]`：可选，记录复制的上游实现来源、commit 和哈希，供更新时提醒人工审查。

首版不做 Mod 版本范围求解。`upstreamCommit` 与 `mods.json` 不一致时直接失败，要求开发者显式确认更新。

## 5. 命令与行为

```bash
cd V:/coding/kelivo-private

dart tool/mod_loader.dart plan
dart tool/mod_loader.dart apply
dart tool/mod_loader.dart verify
dart tool/mod_loader.dart rebase-drill --to <new-commit>
dart tool/mod_loader.dart clean --modset <hash>
```

| 命令 | 行为 |
|---|---|
| `plan` | 只读打印基线、Mod 顺序、补丁和复制目标，不写文件。 |
| `apply` | 创建或校验对应 worktree，应用补丁、复制文件、生成注册表和构建记录。 |
| `verify` | 校验 commit、文件哈希、注册表、工具名和 worktree 状态，不执行 Flutter 构建。 |
| `rebase-drill` | 在独立临时 worktree 验证新基线，不修改当前合成树或 `mods.json`。 |
| `clean` | 只删除明确指定且由 Loader 创建的 worktree；无参数时不做删除。 |

Flutter 构建直接在合成 worktree 中执行，不再包装一套 Loader 专属构建系统。

## 6. 确定性与 Worktree 规则

### 6.1 合成标识

- 根据上游 commit、Loader schema、Mod 顺序及各文件内容哈希计算 `modsetHash`。
- 合成目录为 `.build/worktrees/<modsetHash 前 16 位>/`。
- 内容变化产生新目录，旧版本仍可复用和回滚。
- 哈希路径统一使用 `/`，不把 Windows 路径分隔符带入哈希。
- 注册表不包含时间戳，import 和 Mod 顺序固定。
- 每次合成生成 `MOD_BUILD.json`，记录基线、Mod 版本、内容哈希和 Loader 版本。

### 6.2 创建与复用

创建方式：

```bash
git -C V:/coding/kelivo -c core.longpaths=true -c core.autocrlf=false worktree add --detach <合成目录> <固定commit>
```

Loader 的所有 git 进程都带 `-c core.longpaths=true`（见 6.3），上面的命令是等价的手工写法。

规则：

1. 默认要求上游已跟踪文件干净，检查 `git status --porcelain --untracked-files=no`。
2. 创建后校验 worktree 的 `HEAD` 等于指定 commit。
3. 同一 `modsetHash` 已存在且状态、哈希均一致时，`apply` 幂等返回。
4. 发现手工改动或状态不一致时拒绝覆盖，提示先 `clean` 指定合成树。
5. 不使用 `git reset --hard`、`git clean -fd` 或自动检出覆盖已有工作。
6. 创建失败且没有留下目录和 Git 登记时，Loader 撤销这次写入的状态文件，修好根因后直接重试 `apply` 即可；只有留下了目录或 Git 登记才标记 `failed`，那类记录必须显式 `clean` 才能复用。
7. `clean` 只处理 `.build/worktrees/` 下且存在 Loader 状态记录的目录。
8. Windows 文件锁导致清理失败时报告路径，不扩大删除范围。
9. Git 调用全部使用参数数组，支持路径含空格，不拼接 shell 命令。
10. 不自动复制 `.env`、密钥、`key.properties`、签名文件或 `lib/secrets/` 内容。
11. Windows 上创建 worktree 时显式使用 `-c core.autocrlf=false`，按仓库存储的 LF 检出，避免 shell、checksum 等脚本被 CRLF 污染；不修改上游 Git 配置，也不重写已有合成树。

`flutter pub get`、`flutter build` 和 Flutter 工具链会在合成树中更新 `pubspec.lock` 以及根项目的 Flutter 生成注册文件：

- `linux/flutter/generated_plugin_registrant.cc`
- `linux/flutter/generated_plugin_registrant.h`
- `linux/flutter/generated_plugins.cmake`
- `macos/Flutter/GeneratedPluginRegistrant.swift`
- `windows/flutter/generated_plugin_registrant.cc`
- `windows/flutter/generated_plugin_registrant.h`
- `windows/flutter/generated_plugins.cmake`

`verify` 只把上述精确路径和任意嵌套包的 `pubspec.lock` 视为构建产物；其他已跟踪文件的意外变化仍然失败。依赖目录中的示例工程注册文件不在允许范围内。已跟踪变更以 `git diff` / `git diff --cached` 的实际差异路径为准，因此 Flutter 在 Windows 上造成的纯 CRLF 行尾重写不会误报，真实内容、删除和重命名仍会失败。

### 6.3 Windows 超长路径

上游含长到接近 Windows 路径上限的绝对路径。当前已知最长项是
`dependencies/flutter_inappwebview_android/android/src/main/java/com/pichillilorenzo/flutter_inappwebview_android/webview/in_app_webview/ThreadedInputConnectionProxyAdapterView.java`，相对路径 180 字符。合成目录 `.build/worktrees/<16 位哈希>` 本身又占几十个字符，因此私有仓所在绝对路径稍长，检出就会达到 Windows 的 260 字符上限（`MAX_PATH`，含终止符）。

处理方式：Loader 在**每个** git 进程上追加 `-c core.longpaths=true`。这是进程级参数，只对那一次 git 调用生效：

- 不写仓库、全局或上游 git 配置，不改用户环境变量；
- 不需要 `git config core.longpaths true`，不改动上游工作树；
- 对 `worktree add`、`worktree remove`、`diff`、`status` 等所有 Loader 发起的 git 命令一致生效；
- `patch.dart` 的 `git apply --check` / `git apply --index` 走独立进程助手，同样带该参数。

只改 `worktree add` 不够。在同一棵超长路径的合成树（深层文件绝对路径 260 字符起）上：

- `git worktree remove` 会以 `error: failed to delete '<路径>': Filename too long` 失败并残留目录，`clean` 因此失败；
- `git apply --check` 直接以 `Filename too long` 失败，补丁层无法应用；
- `git diff --name-status` 对长路径文件**静默漏报**：退出码 0 但 stdout 为空。人为修改长路径文件后，不带 longpaths 的 `diff` 输出 0 条，带 longpaths 输出 1 条——这是会让 `verify` 对真实漂移误判通过的**决定性**证据（Loader 的 `trackedChanges()` 与 `cachedDiff()` 都走 `git diff`）；
- 不带 longpaths 的 `git status` 对同一批长路径文件给出**错误状态**：260 字符起多为 ` M`（误报已修改），更长路径上又出现 ` D`（误报已删除），具体形态随长度和平台 stat 行为变化，不能当作固定阈值。Loader 代码本身不调用 `git status`（上游干净检查与漂移检查都走 `git diff`），因此这条只作为「其他 git 子命令同样受该限制影响」的旁证，不作为漂移判据。

`git worktree add` 失败且 stderr 含 `Filename too long` 时，Loader 不再裸抛 Git 的
`fatal: Could not reset index file to revision 'HEAD'`（这句只是检出中途失败后的收尾报错，不是索引或上游损坏），改为给出明确提示：说明是 Windows 路径长度限制、Loader 已传 `-c core.longpaths=true`、给出可执行处理方式（把私有仓或合成目录换到更短的绝对路径），并明确注册表 `LongPathsEnabled` 不能修复 Git 的这条失败。

`LongPathsEnabled` 实测无法代替 `core.longpaths`：本机该值为 `1`，不带 `-c core.longpaths=true` 的 `git worktree add` 仍在同一路径上失败。因此 Loader 只依赖进程级 `-c core.longpaths=true`，不检测、不修改该注册表项；注册表项只对声明了 `longPathAware` 的程序生效，与 Git 无关。

已知边界：

- Loader 不校验最终路径长度，也不做路径映射或缩短；git 在 `core.longpaths=true` 下能处理就能合成。
- 长度阈值实测：深层文件绝对路径 259 字符时，不带 flag 的 `git status`/`git diff` 仍正确；260 字符起开始出错（与该路径含终止符的 `MAX_PATH=260` 语义一致）。我覆盖到 320 字符（此处不带 flag 的 `status` 报 ` D`）；审查者在 305–350 也观察到 ` D`，说明 ` M`→` D` 的转折点随平台 stat 行为浮动，未精确定位。
- 本机 git 2.55 在约 400 字符时 `worktree add` 自身即失败（`'$GIT_DIR' too big`，由 R1 审查者实测），与 `core.longpaths` 无关；更长的路径、厂商 Git 构建与非 Windows 环境未验证。

## 7. 补丁、复制与注册表

### 7.1 补丁

Loader 自有的 `tool_mod_seams.patch` 先应用，之后按 `mods.json` 顺序应用 Mod。

每个补丁必须：

- 解析路径并确认位于 `touches` 白名单；
- 拒绝绝对路径、`..`、`.git`、符号链接和 submodule；
- 先执行 `git apply --check --binary`；
- 成功后执行 `git apply --index --binary --whitespace=nowarn`；
- 后续补丁依赖前一个补丁时，仍逐个 check、逐个 apply；
- 任一失败立即中止，不生成 ready 状态。

正常构建不使用模糊应用，也不以 `--3way` 自动猜测合并。冲突由开发者在更新流程中人工处理。

### 7.2 新增文件复制

- 只允许复制到 `mod.json` 声明的新文件或新目录。
- 目标已存在时失败，不能覆盖上游文件或其他 Mod 文件。
- 排除 `.git`、`.dart_tool`、`build`、`.gradle`、锁文件和本地密钥。
- 拒绝路径穿越、符号链接及 Windows 大小写冲突。
- 复制后校验文件内容和目标路径。

### 7.3 静态 Mod 注册表

Loader 生成 `lib/modding/mod_registry.g.dart`，并配套新增稳定的 `lib/modding/tool_mod.dart`。

概念接口只有两个方向：

```text
decorateDefinitions(原始定义, 定义上下文) → 新定义
wrapHandler(原始处理器, 执行上下文)       → 新处理器
```

- 定义按 `mods.json` 顺序依次处理。
- Handler 按相反顺序包装，使配置中第一个 Mod 最先看到自己的工具调用。
- 无 Mod 时原样返回上游定义和 handler。
- Loader 根据 `toolNames` 检查 Mod 之间的声明冲突；实际 schema 是否匹配声明由 Mod 测试验证。
- Handler 可以返回现有工具链支持的 `ClientToolResult`，Loader 不另建结果协议。

## 8. 通用 Kelivo 接缝

目标接缝位于 `lib/features/home/controllers/generation_controller.dart`：

- `buildToolDefinitions`：基线第 110–131 行；
- `buildToolCallHandler`：基线第 135–153 行。

定义上下文包含：

- `SettingsProvider`、`Assistant`、provider/model ID、conversation ID；
- 模型是否支持工具调用；
- 通过 `ModelSpecResolver` 计算的输入能力。

执行上下文包含：

- 当前助手快照、conversation ID；
- `ToolApprovalService`、`AskUserInteractionService`；
- 原始 `ToolCallHandler`；
- 供 Mod 重读当前助手配置的回调。

补丁只构造上下文并调用注册表，不包含任何具体 Mod 的 import 或业务逻辑。

需要明确：Mod 在基础 handler 之外包装，因此不会自动继承上游的本地工具审批、schema override 或专属权限逻辑。通用接口只提供上下文，具体 Mod 必须自行实现所需策略。

## 9. 分阶段实施

### 阶段 L1：私有仓、配置与 Worktree

1. 创建私有仓和中文 README，并移动两份计划文档。
2. 实现 `mods.json`/`mod.json` 解析、路径检查和 `plan`。
3. 实现 worktree 创建、幂等 `apply`、`verify` 和受限 `clean`。
4. 用临时 Git fixture 覆盖成功、错误基线、脏 worktree 和回滚。

完成条件：空 Mod 集合能够从固定基线生成与上游已跟踪内容一致的 worktree，上游工作区无源码改动。

### 阶段 L2：补丁、复制与构建记录

1. 实现补丁白名单、逐个 check/apply 和冲突中止。
2. 实现 overlay 复制、路径安全和内容哈希。
3. 实现确定性 `modsetHash` 与 `MOD_BUILD.json`。
4. 覆盖目标冲突、路径穿越、Windows 路径和失败清理。

完成条件：相同输入可重复合成，任何不兼容均有非零退出和明确错误，不留下 ready 状态。

### 阶段 L3：通用工具接缝与测试 Mod

1. 添加 `tool_mod.dart` 和注册表生成。
2. 编写 `tool_mod_seams.patch`，只修改两个委托方法及必要 import。
3. 增加仓库内测试专用的空 Mod 和包装 Mod，验证定义顺序、handler 透传及工具名冲突。
4. 验证无 Mod 时行为与上游一致。
5. 执行格式检查、静态分析、受影响工具测试和 debug 构建。

完成条件：测试 Mod 合成树可分析、可测试、可构建，原始工具行为不变。

### 阶段 L4：更新演练与中文维护文档

1. 实现 `rebase-drill`，验证新基线不影响当前合成树。
2. 演练补丁无冲突、补丁冲突和 vendored 来源漂移。
3. 演练恢复旧配置并重建旧合成树。
4. 完善中文 README：配置、命令、更新、回滚和故障排查。

完成条件：Loader 的所有通用能力均有测试和文档，不需要 Phone Agent 参与验收。

## 10. 测试与构建验收

### 10.1 Loader 自身

```bash
cd V:/coding/kelivo-private
dart pub get
dart format --output=none --set-exit-if-changed tool test
dart analyze tool test
dart test
```

必须覆盖：

- 固定 commit、错误 commit、上游脏文件；
- `plan` 无写入、`apply` 幂等、内容变化产生新 `modsetHash`；
- 补丁顺序、上下文冲突、未声明路径、路径穿越；
- overlay 不覆盖已有文件，排除构建目录和密钥；
- 重复工具名、空 Mod 注册表、生成代码格式正确；
- 非 ready worktree 不复用，`clean` 不越界；
- 每个 git 进程都带 `-c core.longpaths=true`，`worktree add` 同时保留 `core.autocrlf=false`；
- `Filename too long` 失败给出可执行提示，其他 `worktree add` 失败保持通用文案；
- 创建失败未留目录和 Git 登记时撤销状态文件（可直接重试），留下目录时保留 `failed`（需 `clean`）；
- 新基线演练不影响当前合成树；
- 恢复旧配置可重建旧合成树。

### 10.2 合成 Kelivo

```bash
flutter pub get
flutter pub get --directory tool/l10n --enforce-lockfile
dart analyze --fatal-infos lib test integration_test tool
flutter test test/features/home/services/tool_handler_service_test.dart
flutter test test/features/home/services/tool_handler_workspace_gating_test.dart
flutter test test/request_consistency_test.dart
flutter build apk --debug
```

同时执行项目要求的 markstream 检查：

```bash
cd dependencies/markstream
flutter pub get
dart analyze --fatal-infos
```

测试 Mod 的新增测试还必须验证：

- 定义顺序和 handler 包装顺序；
- 未识别工具名及 `toolCallId` 原样透传；
- Mod 异常不会无处理地终止聊天；
- 无 Mod 时返回原始定义和 handler；
- 通用注册表可以传递 `ClientToolResult`。

## 11. 上游更新与回滚

### 11.1 更新

```bash
git -C V:/coding/kelivo fetch --prune origin
cd V:/coding/kelivo-private
dart tool/mod_loader.dart rebase-drill --to <new-commit>
```

- 不自动修改 `mods.json`。
- 无冲突后，由开发者显式更新基线和各 Mod 的 `upstreamCommit`。
- 有冲突时只更新受影响的补丁或适配代码，不做模糊应用。
- vendored 来源哈希变化时提示人工审查，不自动复制新版本。
- 更新后重新执行分析、相关测试和 debug 构建。

### 11.2 回滚

1. 用私有仓 Git 历史恢复上一版 `mods.json`、Mod 和补丁。
2. 执行 `apply`，按旧内容哈希复用或重建旧 worktree。
3. 执行 `verify` 和必要测试。
4. 需要清理时只对指定 `modsetHash` 执行 `clean`。

Loader 不修改上游源码，因此不需要在上游执行 reset 或 clean。

## 12. Loader 完成定义与限制

### 12.1 完成定义

只有满足以下条件，才能宣称 Loader 第一阶段完成：

- Loader 自有测试全部通过。
- 空 Mod 与测试 Mod 均可确定性合成。
- 通用工具接缝、冲突检测和失败状态均有测试。
- 合成 Kelivo 的分析、相关测试和 debug APK 构建通过。
- 上游更新演练与旧版本回滚演练通过。
- 上游工作区未发生源码改动。
- 中文维护文档与真实命令和行为一致。

### 12.2 已知限制

- 上游更新仍可能需要人工适配，Loader 只负责尽早、明确地暴露不兼容。
- 路径白名单和复制检查用于防误操作，不是恶意 Mod 沙箱。
- Mod 不会自动继承上游专属工具策略，必须自行处理所需权限和审批。
- `pubspec.lock` 和根项目 Flutter 生成注册文件由合成树中的 Flutter 工具更新，不作为手工补丁维护；`verify` 只允许这些精确路径变化。
- Loader 第一阶段完成不代表任何业务 Mod 已实现或可用。
