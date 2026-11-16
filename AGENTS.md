# AGENTS.md

## 仓库用途

本仓库是 Kelivo 的私有、编译前源码 Mod 工作区，不提交到上游，也不面向最终用户提供运行时插件平台。

当前任务分为两个独立阶段：

1. 先实现并验收通用 Mod Loader，见 `docs/mod-loader-plan.md`。
2. Loader 验收后再实现 `phone_agent` Mod，见 `docs/phone-agent-plan.md`。UI/选择契约改造已完成并通过最终验收；当前 `phone_agent` Mod 版本 0.2.0，VLM 图片链路、Kelivo 应用内固定任务和跨新用户轮次历史图片回放已在 API 35 模拟器用 magpie `llama-cpp/llama-cpp` 验证；物理 MIUI API31 真机由 `llama-cpp/llama-cpp` 验证归一化坐标 tap（打开抽屉/Settings/Search），由 magpie `mistral/deepseek-v4-1-flash-1017` 验证真实图片请求、归一化坐标 swipe 的 UI 效果和像素专属视觉确认，`llama-cpp/llama-cpp` 的完整坐标 swipe 未验证。M17 已为 `stale_handle` 增加 `refresh_failed`/`not_visible`/`not_enabled` 前置诊断，并在物理 MIUI 上用同一官方测试连续 4 轮通过、未复现历史间歇性失败，诊断标识未在设备触发，根因仍未确认。M19 在 API35 真实触发权限弹窗，但弹窗期间服务 `rootInActiveWindow` 为 null；M20（窗口 root 补全）与 M21（事件来源包名）均已在设备上证伪并 abandoned，未合并生产代码。M22 按用户同意保守收尾：不可识别权限弹窗仍返回 `no_window`，错误消息只做条件式人工提示（“如果看到系统权限弹窗，请人工处理/取消，再返回测试应用”），不声称识别具体权限弹窗；可取得系统包名的窗口仍返回 `system_window_denied`，错误优先级、读树/截图密码遮挡和输入边界不变。异常测试改由宿主 `dumpsys` 独立确认真实 `GrantPermissionsActivity` 后直接 tap/back 断言 `no_window` 与提示，不再因 `root=null` skip，也不把任意 `no_window` 当作通过。API35 官方测试 `+2`、完整异常套件 `+6`，均 EXIT=0；权限场景按真实弹窗上的保守拒绝验收。M23 已实现独立 `TYPE_ACCESSIBILITY_OVERLAY` 前台可视化叠加层并完成 reviewer 返工（密码遮挡只排除可确认自身窗口、show 代次/动作代次校验、隐藏失败 fail closed、真实手势时长、宿主独立触摸、gate 后与异步 `takeScreenshot` 回调后窗口重校验）；round-4 设备运行树 `9ebf2e991caa07ed`（最终源码树 `dfcef53cfd77ea78`，仅 `plugin/README.md` 副本不同）的 API35 完整异常套件 **`+8`、EXIT=0**（含旋转、锁屏、服务禁用/重启、权限窗口），官方 `phone_agent_test.dart` `+2`、EXIT=0，物理 MIUI 官方 `+2`、截图无污染 `+1`、EXIT=0；产品 debug APK 在最终树 `dfcef53cfd77ea78` 于全部设备测试后 `flutter clean` 显式构建：181,403,054 字节，SHA-256 `501d4a0087294258baa882e9a32856208805fcba88228ec34e15016ae89689fb`，debug merged manifest 含 `SecureWindowFixtureActivity`、release 不含且含 `PhoneAgentService`；构建后未再运行 integration_test。此前 181,402,630 / `a72cac9b…` 已被 `a460dcbc` 上 17:29/17:32 的 integration_test 覆盖为 251,120,349 / `e3d9d22b…` 测试入口构建，仅作历史，不代表产品。M24 处理长期未结的「聚焦后同句柄 `set_text` 返回 `stale_handle`」：自然循环未复现（API35 278 次迭代、MIUI 80 次、MIUI 官方测试 4 轮全绿），改用受控夹具确认机制——Flutter 重建输入框语义子树会让持有的 `AccessibilityNodeInfo` 无法 `refresh()`，落点正是 `refresh_failed`（3/3 复现，不重建的对照组 3/3 成功）。修复为「读树记录根→节点子索引路径，`refresh()` 失败时按路径重解析一次并要求指纹逐字段完全一致」，收窄而非放宽：不放宽任何指纹字段，不按文本/相似度找节点，不改可见性/可用性/TTL/窗口校验，且重建后语义节点不接受所需动作时仍返回 `action_unavailable`。API35 官方 `phone_agent_test.dart` `+2`、EXIT=0；物理 MIUI 官方 `+2`、EXIT=0；API35 完整异常套件未取得绿色整轮（最好 `+6 -2`，失败均为宿主脚本时序，已通过 FLAG_SECURE、旋转、home/recents、锁屏、叠加层宿主触摸）；API29 离线按未运行记录。M24 返工后最终树 `29861376ffaa5e41`（`modsetHash` `29861376ffaa5e4123b8884b5a67cd07d102666acfdee83d0e1ed6f815afce2a`；设备结果取自 R1 前的行为等价树 `47675033b3d132e0`），产品 debug APK 在干净树上显式构建：181,403,918 字节，SHA-256 `5a54cb3a459a9c8758033fce6eba14bdf098b0b6c02477be45e83e723bd41b43`，debug merged manifest 含 `SecureWindowFixtureActivity` 与 `PhoneAgentService`，未构建 release；构建后未再运行 integration_test。R1 前树 `47675033` 的 181,404,642 字节 / `677c26d9…` 与 M23 的 181,403,054 字节 / `501d4a00…` 都只作历史。未验证项见计划 9.3.2.1 与 9.3.7。M32（2026-11-15）只修订应用批准契约文档：批准=读＋操作一体（未批准应用的读树/截图只返回应用身份与 `permission_required`）、manifest 一次声明 `QUERY_ALL_PACKAGES` 与 `(包名, 签名)` 双匹配、批准后的恢复与任务控制、结果未知语义、多窗口首版不支持、批准终态与防自我批准、首次启用隐私确认（方案 B）；观察侧也判构建期 `package_not_allowed`，且构建期范围在批准上线时转为 deny 清单（两项均为 tower 定论，用户可推翻）。**M32 全部未实现**，并按来源分层（用户拍板 / 早期已定契约 / tower 定论 / 设计提案），设计提案不是用户决策。M33（2026-11-15）实现第 2、3 步：插件 manifest 一次声明 `QUERY_ALL_PACKAGES`、`(包名, 签名证书 SHA-256 集合)` 双匹配的本地白名单（`noBackupFilesDir`、幂等写入、撤销即时、写入前重解析签名）、构建期范围转 deny 清单（初始为空）、构建配置预批准条目（测试包恒有、`securefixture` 仅 debuggable）、观察与输入双路径门控（未批准只回身份＋`permission_required`，不建立观测、不截图）、原生 `approvedApps`/`approveApp`/`revokeApp` 通道面；同批同步了异常套件 helper 的接受集合。**批准卡片/通知、审计、首次隐私确认、任务控制与恢复、结果未知语义仍未实现，且 M33 未跑任何设备**（**审计已由 M35 补齐**；本句是 M33 当轮记录，不改写历史）（Loader 165、插件 Kotlin 170、插件 Dart 25、合成树 `dart analyze --fatal-infos` 通过）。

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
- Windows 上创建合成 worktree 时显式使用 `git -c core.longpaths=true -c core.autocrlf=false worktree add`，按仓库存储的 LF 检出；两个 `-c` 都只对当前 git 进程生效，不修改上游、仓库或全局 Git 配置。
- Windows 超长路径：Loader 的每个 git 进程都追加 `-c core.longpaths=true`（不只 `worktree add`；`worktree remove`、`diff`、`status` 在同一条长路径上同样会失败或误报）。`worktree add` 因 `Filename too long` 失败时必须给出可执行提示，不得裸抛 `Could not reset index file`。该情况下若未留下目录和 Git 登记，Loader 撤销本次状态文件，重试即可；留下目录或登记时才保留 `failed` 记录，需 `clean` 后重试。
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
- 节点重解析（M24）：`refresh()` 返回 false 时，先按读树时记录的“从根到该节点的子索引路径”在当前活动窗口重新解析一次，并要求重新解析出的节点指纹与读树时逐字段完全一致；路径解析失败、节点不存在或任一指纹字段不等时仍返回 `stale_handle`（路径解析失败的消息保留 `refresh_failed`），不返回新句柄。该重解析不按文本、描述或相似度查找节点，不放宽任何指纹字段，不改变可见性、可用性、TTL 和窗口/包名/尺寸/旋转校验，也不自动重试动作；但它只对“平台重建节点对象、逻辑节点未变且重建后仍 advertise 所需动作”生效，重建后语义节点不接受所需动作时仍返回 `action_unavailable`，不得为此放宽动作校验。设备机制与 A/B 证据见 `docs/phone-agent-plan.md` 9.3.2.1。
- 模型坐标统一为 `[0, 1]` 归一化坐标，原点为截图左上角。
- 截图复用 Kelivo 现有 `ClientToolResult` 与 `McpImageSnapshot` 链路，不修改 provider 序列化。
- 首版只在显式测试包名中开放输入，不操作支付、社交等敏感应用。私有测试应用使用 `com.psyche.kelivo.phoneagent` 和启动名称 `Kelivo Agent`，不得覆盖设备已安装的上游 Kelivo。
- 输入边界必须精确表述：`system_window_denied` 同时约束**输入与观察**但来源不同；`package_not_allowed` **M33 起同时约束输入与观察**，只对构建期 deny 清单成员出现（清单初始为空），排在用户白名单之前。**M33 起观察路径也判构建期 deny 清单与用户白名单**：未批准应用的读树与截图返回 `permission_required` 且只带应用身份，不再返回树节点或截图。`FLAG_SECURE` 只阻止截图，不阻止读树和输入。`device_locked` 同时约束读树、截图和输入。
- 应用边界与应用授权（**第 1 步硬基线与输入窗口类型 M27、第 2 步观察边界 M28、第 3 步用户白名单与签名绑定 M33、审计元数据 M35 均已实现；批准交互、隐私确认未实现**，完整契约见 `docs/phone-agent-plan.md` 7.5/7.6）：默认拒绝，不做黑名单式放行；白名单条目为 `(包名, 签名证书 SHA-256 集合)`，两者必须同时匹配，包名匹配但签名不符视为未批准。判定顺序为 `device_locked` → `no_window` → 硬基线 → 窗口类型 → 构建期硬禁止 → 用户白名单 → 句柄/截图校验，全部在原生侧判定，Dart 只做错误码映射与展示。硬基线（systemui、权限控制器含厂商变体、包安装器含厂商变体、证书安装器、`com.android.settings` 及厂商设置变体、电话/短信默认应用、承载助手的 Kelivo 包 `com.psyche.kelivo`）与窗口类型失败仍返回 `system_window_denied`，**不新增错误码**；未批准返回 `permission_required`（输入与观察都返回）。**权限弹窗仍是 `no_window`**（无可访问 root、取不到包名），硬基线只在能取得包名时生效，不得把 `no_window` 改写成 `system_window_denied`。`package_not_allowed` 只表示构建期硬禁止，排在用户白名单之前，不与运行时白名单混用。测试包 `com.psyche.kelivo.phoneagent` 是构建配置的预批准条目而非硬基线成员，不得用包名前缀匹配“Kelivo 自身”，否则测试应用会自我阻断。
- 应用批准契约（**M32 修订契约，M33 已实现第 2、3 步，M35 已实现审计元数据；批准 UI、隐私确认、任务控制仍未实现**；逐条来源分层见下方 88–95 条——用户拍板 / 早期已定契约 / tower 定论 / 设计提案，**不要把设计提案读成已定**；契约全文见 `docs/phone-agent-plan.md` 7.5.4 与 7.5.9–7.5.14）：**批准 = 读＋操作一体**（已定，用户拍板，已实现）。未批准第三方应用的 `readTree`/`screenshot` 只返回应用身份（包名、签名证书 SHA-256 前 8 位、可选显示名）与 `permission_required` 授权请求，**不返回**树节点、节点文本、截图或图片 metadata、窗口标题、界面内容摘要；不建立观测（不 `beginTree`、不占用 `treeBudget`、不调用 `takeScreenshot`）、不返回空树或黑图占位。判定顺序在观察路径为 `device_locked` → `no_window` → 硬基线 → 窗口类型 → 构建期硬禁止 → 用户白名单（未批准即 `permission_required`），硬基线与窗口类型**仍在白名单之前**（系统窗口无条件拒绝，批准不改变），权限弹窗仍是 `no_window`。旧理由（“模型必须先看到内容才能解释为何需要授权”）已作废，新理由是**申请授权只需要应用身份**。**当前没有任何批准 UI**：聊天卡片、通知栏批准、Mods 页白名单页都不存在，批准只能经原生通道写入（留给 M34）。
- 应用身份与签名绑定（`QUERY_ALL_PACKAGES` 一次声明为**已定（用户拍板）**；`(包名, 签名)` 双匹配等为**已定契约（早期设计，非本轮用户拍板）**；**均已于 M33 实现**）：manifest **一次**声明 `QUERY_ALL_PACKAGES`（插件自己的 manifest，不改上游宿主），用它解析前台包签名；白名单条目 `(包名, 签名证书 SHA-256 集合)` 双匹配，多签名包（实测 `com.android.vending` 2 枚）要求整集合相等；同签名更新保留授权；签名变化或无法解析 → 未批准（fail closed）；授权不随聊天备份迁移（落在 `noBackupFilesDir`）；**首版明确不支持应用分身与工作资料**，不做多用户 `PackageManager` 查询，不得写成“已适配分身”。**交付代码在设备上解析任意前台包签名的能力未实测**（M29 只验证了探针 APK）。
- 原生批准通道（M33 已实现，UI 未实现）：`kelivo/phone_agent` 的方法 `approvedApps` / `approveApp` / `revokeApp` **不依赖无障碍服务连接**；批准写入幂等（只更新最后批准时间、保留首次来源）、写入前重新解析当前签名（解析失败 `signing_unavailable`、与请求保存值不一致 `signing_mismatch`，两种情况都不写入）、撤销后下一次判定即重新读存储（阻止新的读树 `offset == 0`、全部截图与全部输入；已建立观测的 `offset > 0` 分页在 TTL 内仍回放旧树，见 plan 7.5.4）；结果只含包名、签名前 8 位、批准时间与来源助手 id。
- 批准后的恢复与任务控制（**设计提案（tower 建议、待实现），不是用户拍板项**；用户原文只有方向性约束「如果每次都需要用户回到Kelivo操作，那摩擦就太大了」）：「允许并继续」**只恢复与该次批准关联且仍可恢复的任务**，恢复后**先重新观察**，**不重放**被拒绝时的点击/输入/手势；批准不自动重试原调用。**同时只允许一个任务控制手机**（按任务持有，不按助手）；停止或撤销后未执行的请求失效；**已派发的 `dispatchGesture`/`performAction` 不承诺撤回**。任务控制冲突的错误码与文案尚未定稿，本轮不新增错误码。
- 结果未知语义（**设计提案（tower 建议、待实现），不是用户拍板项**）：动作已派发后的超时、取消或中断是**结果未知**，不是失败也不是成功；**不盲目重试**（可能产生第二次点击/输入/发送），必须先重新观察再从界面推断；`performAction`/`dispatchGesture`/`performGlobalAction` 的返回值只表示系统接受调用，**不表示业务成功**。不得承诺撤销已执行输入、回滚已发送消息或判断服务端是否收到。
- 截图与手势范围（**设计提案（tower 建议、待实现），不是用户拍板项**）：截图与坐标手势只针对**已获准的目标应用**；手势执行时前台若已不是截图时的已批准包则拒绝，不按旧坐标盲点；分屏、画中画、自由窗口、多显示器、折叠屏多窗口**首版明确不支持**，但“拒绝还是仅记录不承诺”尚未定稿，不得写成已生效行为。
- 批准请求终态与防自我批准（**设计提案（tower 建议、待实现），不是用户拍板项**）：每条请求只有一个终态（已批准/已拒绝/已过期/已撤销/已被取代），重复批准不产生第二条记录、不把拒绝翻成批准；通知 action、聊天卡片与 Mods 页撤销走同一判定入口，按请求 id 幂等；迟到回调在请求已有终态、已过期或已清理时**不得写入白名单**；批准写入前重新解析当前签名，与请求保存的签名不一致即置为失效。批准只能由用户在 Kelivo 界面或通知栏手势触发（Kelivo 包在硬基线内，模型输入不可达）；**不自动批准、不超时放行、不允许模型改写批准状态**。用户不看内容就点允许不可防，不是安全护栏。
- 首次启用隐私确认（方案 B，**已定（用户拍板）**，未实现）：只在**首次启用** Phone Agent 时一次性提示“截图与界面文字会作为工具结果发送给用户配置的 provider”，**不每张截图询问、不在每次任务前重复**；它是告知而非技术控制，不改变白名单判定，也不构成“内容不外发”的承诺。provider 更换是否重新提示未定稿。
- 观察侧也判构建期 `package_not_allowed`（**已定（M32，tower 定论，用户可推翻）；M33 已实现**）：观察路径顺序 `device_locked` → `no_window` → 硬基线 → 窗口类型 → 构建期硬禁止 → 用户白名单，`package_not_allowed` 排在用户白名单之前。理由：批准 = 读＋操作一体，本构建无法操作的应用不应产生批准提示。因此 `package_not_allowed` 的适用范围是**输入与观察**（6.6/7.5.8/README 已同步），并有“排在用户白名单之前”的同序 JVM 断言；用户推翻时须连带收回该层与 6.6/7.5.8/AGENTS/README 的适用范围表述。
- 构建期范围已转为 **deny 清单**（已定（M32，tower 定论，用户可推翻），M33 已实现）：构建期 allowlist 改为只保留明确不支持或危险的包的 deny 清单，**`package_not_allowed` 只对 deny 成员出现**；其余第三方应用不因构建期范围被拒，按用户白名单判定，未批准返回 `permission_required`。理由是可达性：维持“只允许测试包”会让 `permission_required` 不可达，批准卡片/通知/撤销/「允许并继续」全无触发入口，P6 完成条件走不通。硬基线不在 deny 清单里（由更早的硬基线层返回 `system_window_denied`）；**deny 清单的具体成员尚未定稿**（设计提案，M33 实现为**空集合**，并以 JVM 断言固定“初始为空、不与硬基线重叠”，不得拿硬基线集合充数）。推翻时须恢复 allowlist 语义，并同步改写 7.5.8/10.1/10.2/AGENTS/README 的「未批准 → `permission_required`」表述与 P6 完成条件。
- 构建配置预批准条目（M33 已实现）：测试包 `com.psyche.kelivo.phoneagent` **恒为预批准**；跨 UID 的 `FLAG_SECURE` 夹具包 `com.kelivo.phoneagent.securefixture` **只在 debuggable 构建预批准**（release 不预批准，避免同名第三方包被静默放行）。两者都不写用户白名单、不产生批准提示、不可撤销、不影响其他应用 `permission_required` 的可达性。
- 仍未定论的交叉点（不得擅自二选一，实现前必须先在文档定论）：多窗口是拒绝还是仅不承诺；任务控制冲突是否新增错误码；provider 更换是否重新提示隐私确认。另有一项已由 M33 处理、但**观察分页行为**仍属未定稿：(a) 两项实现前提（测试包与 `securefixture` 的预批准）已在 M33 落地；(b) 观察门控对 `offset > 0` **M33 实现为不重复判定**（沿用 M28 接入点），因此未批准时分页返回 `stale_observation` 而不是 `permission_required`；M32 曾把它列为未定稿的设计提案，若后续改为“分页也判定”，须同时改 plan 7.5.4 与 JVM 断言。

**M33 实现事实（不得与上述设计混读）**：白名单核心在新增文件 `mods/phone_agent/plugin/android/src/main/kotlin/com/kelivo/phoneagent/AppWhitelist.kt`（`SigningIdentity`、`WhitelistEntry`、`WhitelistStore`、`WhitelistStorage`/`FileWhitelistStorage`/`InMemoryWhitelistStorage`、`SigningResolver`、`AppApprovals`、`buildPreApprovedPackages`、`DENY_PACKAGES`）；策略层在 `AppBoundary.kt` 的 `PackagePolicy`（新增 `denyPackages`/`preApprovedPackages`/`approvals` 参数，删除了 `allowedPackages`）。观察顺序实际为 `no_window` → 静态硬基线 → 观察窗口类型 → 构建期 deny 清单（`package_not_allowed`，标识 `build_denied`）→ 用户白名单（`permission_required`）；输入顺序为 `no_window` → 静态硬基线 → 角色解析失败 → 角色持有者 → 窗口类型 → deny 清单 → 用户白名单。接入点仍是 `readTree()` 的 `offset == 0` 分支（在 `treeBudget` 扣减与 `beginTree` 之前）与 `captureScreenshot()`（取前台 `WindowState` 之后、`collectPasswordBounds` 之前），**分页 `offset > 0` 不重复判定**。签名解析用 `PackageManager.getPackageInfo(pkg, GET_SIGNING_CERTIFICATES)`（API < 28 回退 `GET_SIGNATURES`），签名集合排序去重后整集合比对；白名单写在 `context.noBackupFilesDir/phone_agent_whitelist.tsv`（制表符分隔、带表头，损坏行被丢弃而不是被信任）；判定每次都重新解析当前签名、不做正缓存，因此签名变化立即生效、撤销在下一次判定立即反映（准确范围见 plan 7.5.4「撤销的生效范围」）。通道新增 `approvedApps`/`approveApp`/`revokeApp`，且在 companion 上构造 `AppApprovals`，所以**不依赖无障碍服务连接**（Mods 页在服务关闭时也能撤销）。预批准集合由 `PhoneAgentService.preApprovedPackages(context)` 按 `FLAG_DEBUGGABLE` 计算。JVM 覆盖：新增 `AppWhitelistTest`（16 项）与重写的 `PackagePolicyTest`（51 项），并固定“deny 清单初始为空、不与硬基线重叠”。**未验证**：设备上交付代码能否解析任意前台包签名；`FLAG_SECURE` 夹具在新门控下的实机行为；`permission_required` 文案能否让模型停止重试。M33 未跑任何设备。

**M28 第 2 步实现事实（历史，已被 M33 扩展；不得与上述设计混读）**：观察边界当时落地为同一 `AppBoundary.kt` 中的 `WindowType.allowsObservation`（仅 `APPLICATION` 与 `INPUT_METHOD` 为 true）与 `PackagePolicy.requireObservable(packageName, windowType)`；当时的判定顺序是 `no_window` → 静态硬基线 → 观察窗口类型，**不判构建期 deny 清单与用户白名单**。M33 在该顺序尾部追加了这两层，签名与接入点位置未变。

**M27 第 1 步实现事实（不得与上述设计混读）**：硬基线与输入窗口类型已落地在 `mods/phone_agent/plugin/android/src/main/kotlin/com/kelivo/phoneagent/AppBoundary.kt` 的纯函数 `PackagePolicy.requireInputAllowed(packageName, windowType, roleHolders)`；实际顺序为 `no_window` → 静态硬基线（含 Kelivo 精确包名 `com.psyche.kelivo`）→ 角色解析失败 → 角色持有者 → 窗口类型 → `package_not_allowed`，**没有任何路径返回 `permission_required`**。`RoleManager.getRoleHolders` 是 @SystemApi（`MANAGE_ROLE_HOLDERS`），公共 SDK 编译不过，改用公共等价接口 `TelecomManager.defaultDialerPackage` + `Telephony.Sms.getDefaultSmsPackage`；只有查询抛异常或系统服务缺失才算解析失败（`role_resolution_failed` → 拒绝全部输入），返回 null 视为系统明确没有该角色默认应用，不得据此封死无短信能力的设备。厂商入口枚举**必须按真机 `cmd package resolve-activity` / `dumpsys package` 实测补全**（安装、卸载、权限授予、证书安装、设置），不能只凭命名习惯猜；漏写等于该入口没有硬基线。M27 当时构建期范围还是 allowlist（只有测试包），所以漏写的入口暂被 `package_not_allowed` 拒绝、不可达；**M33 起构建期范围已转为 deny 清单**，该缓冲消失——漏写入口直接走用户白名单并返回 `permission_required`，用户批准后即可被读树、截图与输入，**因此补全已成为批准 UI 上线前的前置条件**（详见 plan 7.5.2）。已知实测补入的 MIUI 入口：`com.miui.packageinstaller`（`InstallStart` / `UninstallStart`）、`com.lbe.security.miui`（`GrantPermissionsActivity` / `ReviewPermissionsActivity`）、`com.android.certinstaller`、`com.xiaomi.misettings`。
- 窗口类型双层判定不对称，必须两层都判：`TYPE_INPUT_METHOD`、`TYPE_SYSTEM`、`TYPE_ACCESSIBILITY_OVERLAY` 拒绝输入；`TYPE_SYSTEM`、`TYPE_ACCESSIBILITY_OVERLAY` 拒绝观察；未知或厂商扩展类型默认拒绝。**两层均已实现**：输入层（M27）为 `WindowType.allowsInput` 仅对 `APPLICATION` 为 true；观察层（M28）为 `WindowType.allowsObservation` 仅对 `APPLICATION` 与 `INPUT_METHOD` 为 true，`TYPE_SPLIT_SCREEN_DIVIDER` 与其他取值两层都拒绝，标识为 `window_type_split_divider` / `window_type_unknown`。输入允许集严格小于观察允许集（输入法窗口可观察、不可输入）。只看包名会漏掉挂在普通包名下的输入法/overlay 窗口，只看类型会漏掉 `TYPE_APPLICATION` 的 settings。类型标识 `window_type_system`/`window_type_ime`/`window_type_overlay` 只做固定追加，不含窗口标题、类名或节点内容；类型解析失败必须 fail closed。
- 观察边界（读树与截图，M28 第 2 步建立、M33 扩展为含 deny 清单与用户白名单）判硬基线、窗口类型、构建期 deny 清单与用户白名单，**不查询角色持有者**；观察层不接收 `RoleHolders`（角色是输入边界，若观察层也依赖角色解析，`readTree` 会在角色查询失败时对所有设备失败）。**M33 起未批准应用的读树与截图返回 `permission_required` 且只带应用身份**，见上方「应用批准契约」条目；旧理由「模型必须先看到内容才能解释为何需要授权」已作废。因此“不承诺读树泄漏应用自身界面文本”的范围已收缩到**已批准应用**；对已批准应用仍不承诺，不得把“通知栏不可观察”写成“通知内容不会进入模型”。截图的前台判定必须先于且独立于既有的全窗口密码遮挡遍历，不得因前台被拒而缩窄遮挡范围，也不得把边界判定塞进遮挡遍历。
- 已定决策（用户明确决定，不再作为开放问题）：白名单**全局共享**、不按助手隔离（理由：按助手隔离会让同一应用换助手重复弹批准，摩擦翻倍；代价是跨助手越权，缓解是记录首次批准来源助手并分组展示）；批准**长期有效 + Mods 页显式撤销**，不做一次性、**不做定时过期**（会让长任务在不可预期时刻失败），撤销只影响后续调用；审计**落盘元数据**（时间、助手 id、会话 id、包名、签名哈希前 8 位、动作类型、结果码），**不记**节点文本、输入文本、密码内容、截图或图片字节、界面内容摘要、坐标数值、窗口标题（7 项，与 plan 7.5.5 完全一致），滚动保留 30 天或最近 2000 条，先到者生效。“不写敏感日志”约束的是内容，审计只写元数据，两者不冲突，但不得据此宣称审计不涉及隐私。
- 审计元数据（**已定（用户拍板），M35 已实现；无设备证据、无读取界面**）：字段集合**精确七项**——时间戳、助手 id、会话 id、包名、签名证书 SHA-256 前 8 位、动作类型、结果码，`AuditRecord.FIELD_NAMES` 即落盘列序，TSV 每行恰好 7 列。**明确不记录**节点文本、输入文本、密码内容、截图或图片字节、界面内容摘要、坐标数值、窗口标题；结构性保证是 `AuditAction` 只输出固定 token（`readTree` / `screenshot` / `input.<action>`）且记录构建器不接受工具参数对象，新增字段等于扩大外发与推断面，必须先改文档与 JVM 断言。滚动保留 **30 天或最近 2000 条，先到者生效**（恰好 30 天仍保留）。存储为 `noBackupFilesDir/phone_agent_audit.tsv`，与白名单同目录策略，**不进仓库、不进工具结果、不发给模型、不上传不同步，也没有任何读取通道或界面**。助手 id 与会话 id 由 Dart 调用侧经通道可选参数 `assistant_id` / `conversation_id` 传入（原生 `AuditIdentity` 从不抛错，缺失如实记 null，不伪造；助手 id 只是审计标签，不参与任何授权判定）。审计失败静默丢弃并只做本地计数，**不得阻断工具主路径、改变工具结果或影响白名单判定**。元数据不是内容，但**不得据此宣称审计不涉及隐私**——它仍能推断“用过哪些应用”。
- 批准交互：聊天内卡片 + 通知栏两入口共用同一 pending 请求与同一持久化白名单，任一端批准后另一端消失，写入幂等（重复批准不产生重复条目，保留首次来源）。摩擦单位是每个新应用一次（绑定签名后为每个 `(包名, 签名)` 一次），不是每动作、每会话或每任务。聊天卡片复用上游 `ToolApprovalService` 的**模式与 UI 通知机制，不复用其等待语义**：可复用 `Completer<ToolApprovalResult>` 请求结构（`tool_approval_service.dart:34`）、pending 存储（`:64`）、创建方式（`:129`）与 `notifyListeners()` 刷新；但 `requestApproval` 返回的 Future 假定有调用方 await，而本设计的工具调用已返回 `permission_required`，直接套用会让 pending 永驻、卡片不消失。批准请求必须作为独立状态记录，自带 TTL 过期、任一端批准/拒绝即置终态并撤下另一端、断连/重启/切会话清理。通知栏**必须新增**通知 action 与 `BroadcastReceiver`：上游 `NotificationService` 只有 `onDidReceiveNotificationResponse`（`notification_service.dart:102`，点击打开会话），`AndroidNotificationAction` 在交付代码中零命中，**不得写成复用现有通知**。不得用叠加层做批准界面：叠加层是 `FLAG_NOT_TOUCHABLE | FLAG_NOT_FOCUSABLE`，改可触摸会引入触摸拦截/焦点窃取整条风险；批准通道不应由被批准的通道自己绘制（能画批准按钮就已越过它正在申请的边界）；叠加层在旋转/锁屏/切窗/服务中断时被清理，无法承载需存续的批准 UI。
- 用户不在场时立即返回 `permission_required`：不持有 `Completer` 等待、不排队重试、不静默降级为只读。Dart 通道超时 35s（`phone_agent_service.dart:149`）与原生排队超时 15s（`PhoneAgentService.kt:35` 的 `QUEUE_TIMEOUT_MS`）使“等待批准”必然退化为 `timeout`，模型无法区分拒绝与不在场。必须如实写明长任务会中断、用户批准后需重新观察再继续，不描述成无感体验，也不描述成“部分完成”。模型可见文案用英文，只含包名（观察侧额外只含签名哈希前 8 位作为身份）；`permission_required`（可以批准）与 `system_window_denied`（永远不行）必须可区分；**M33 已实现**观察侧文案明确写“没有读取任何内容/没有截图”，不复用输入文案让用户以为截图已经发生。
- 实现前置风险：`WindowState` 已按 M27 加上 `windowType`（`ObservationRegistry.kt`），`AccessibilityNodeInfo` 本身不直接给出“窗口类型”，必须解析。**M28 实测修正**：两条来源都会失败——服务重连后首次截图实测 `root.window` 返回 **null**，同时 `windows` 只列出别的窗口 id（临时调试输出 `rootWin=5902 nodeType=null entries=(5890, 3)`；交付代码只打印 `windowType exhausted attempts=N rootWin=... entries=...`），窗口列表要约 3 秒后才包含目标窗口。因此 `windowType(root)` 在**一个有界总预算（2500ms、间隔 40ms）内交替重试** `root.window.type` 与 `windows` 按 `windowId` 精确匹配，并记录 `TYPE_WINDOWS_CHANGED` 到达时间；只有等待期间没有新窗口事件才累加尝试计数。原“3 次 × 25/50ms（共 75ms）”预算不足，会导致首次读树/截图返回 `window_type_unknown`。**不得退回“用列表里唯一的那个窗口的类型”**，也不得按包名、层级顺序或位置猜类型。预算刻意取实测滞后量级，仍远小于 35s 通道超时与 15s 排队超时，只在两条来源都失败时才消耗；超出预算仍是 `UNKNOWN` 并拒绝（fail closed），不得为了让测试变绿延长等待。**2500ms 短于实测的约 3 秒滞后**，只能缩小失败窗口、不保证覆盖更长滞后或其他 ROM 时序。**主线程调用一律零预算**：截图隐藏叠加层后的窗口重校验（`hideForCapture` → `start` → `currentWindow` → `windowState`）在主线程执行，那里 sleep 2.5 秒会阻塞 UI 并超出约 250ms 的有界隐藏握手；该处只做变更检测，`UNKNOWN` 已足以产生 `stale_observation`，重试无收益，因此不 sleep、只读一次（R1 F5，代码路径分析，未见 ANR）。`windowState()` 是 `WindowState` 的唯一构造点，其内部完成解析，不得在策略层另读一次 `windows`；`sameWindow()`、截图观测、`TreeObservation`、`CapturedScreenshot` 都已同步。两条来源都失败才落 `WindowType.UNKNOWN` 并拒绝。**`sameWindow()` 加入 `windowType` 比较后是否会在正常场景产生新的 `stale_*`：M27 已在 API35 模拟器用官方 `phone_agent_test.dart`（`+2`、EXIT=0）验证截图/读树/节点点击/坐标滑动/滚动/聚焦后 `set_text`/二次读树全程无 `stale_*`；这只是一条路径的样本，物理设备与其他场景仍需回归。**`phone_agent_exception_test.dart` 观察边界收紧后共有 5 处会红：settings 树依赖（`:537`、`:549-550`，且 `:557` 起 1000 个 pending 读树就在该页面建立观测）、叠加层触摸用例（`:202-232`，`_tryTree` 等 systemui 前台恒为 null）、home/recents 用例（`:346-377` 经 `_expectSystemNavigationDenied` `:1019` 读树取包名）。**M28 已同批改为宿主 `dumpsys` 独立确认 + 观察边界错误码断言**（见 plan 7.6 风险 2）。**设备实测修正两处断言假设**：(1) `home`/`recents` 后前台实测是 launcher（`TYPE_APPLICATION`），读树**成功**，不能等观察拒绝（会白等 30 秒）；(2) 通知栏包名 `com.android.systemui` 属硬基线且**硬基线判定先于窗口类型**，标识只会是 `hard_baseline`，**`window_type_system` 不可能独立出现**；`window_type_unknown` 不得列为可接受标识（那是“窗口列表未稳定”，会吞掉真实时序缺陷）。**M28 设备结果与未验证项**：API35 官方 `phone_agent_test.dart` `+2`、EXIT=0（`final2_official.log` 在最终树 `c3c760c0` 上）。**M28 当轮异常套件从未取得绿色整轮**（M30 已在 API35 补齐：3 棵树 / 4 轮 `+8`、EXIT=0，见 plan 9.3.0.1），数字须逐轮取自 `wt-28/.build/*.log`：`exc5`(e2d50da0)=`+1 -1`、`exc6`(c3c760c0)=`+1 -7`、`exc7`=`+2 -6`、`exc8`=`+2 -6`、`exc9`(c3c760c0，最终)=`+1 -7`；**不得概括成“两次 `+1 -1`”**。`exc8`/`exc9` 的失败句为 `最后前台包名：未知`，该串来自 `_waitForTreeText` 对最后一次 `_tryTree` 返回 null 的兜底，日志未记录当时 `error`，**其成因未定位，既未证明是产品缺陷也未证明是宿主时序**。因此旋转、home/recents、权限窗口、锁屏、服务禁用在该步**未取得通过结果**。**物理 MIUI `1960cd68`（M28 当轮）：有通过迹象但无留存日志**——唯一留存的 `miui_official.log` 是 `+0 -1`、EXIT=1，失败于 `setUpAll` 服务未就绪（`miui_enable` 显示 `ENTRY_NOT_FOUND`/`AFTER: null`），不是 `device_locked`。**M30 已补齐这一项**：官方 `phone_agent_test.dart` `+2`、EXIT=0（`official_miui.log`，107s），当轮真实原值 `null`/`0`/`0` 已恢复；异常套件未在 MIUI 运行（该设备缺跨 UID 安全窗口夹具）。产品 debug APK（R1 返工后的当前产品）在最终树 `f26c1c7ed3238610` 于设备测试与返工后 `flutter clean` 重建：**181,410,150 字节**，SHA-256 `a6c2e51b73435af1de4f74d5e95807a9688e95cb3d78be2f47521d715971b70f`，manifest 含 `SecureWindowFixtureActivity` 与 `PhoneAgentService`；构建后未再跑 integration_test，该 APK 未被设备测试覆盖（R1 只改主线程预算与文档）。跑过设备测试的是 R1 前的 `c3c760c0d4502878` 树：181,409,722 字节 / `8cae3cd8…`（历史，已二次 clean 构建逐字节复现）。**诊断串注意**：`windowType attempt=... nodeType=... resolved=...` 是临时调试输出，**交付代码不可复现**，只打印 `windowType exhausted attempts=N rootWin=... entries=...`。9.4 与 10.1 的 VLM 结果来自旧代码，**不能用于宣称新边界已验证**，重跑前只能写“新边界未验证”。
- 该设计的未验证假设（不得写成已知可行）：**`QUERY_ALL_PACKAGES` 声明后能否稳定解析任意前台包的签名证书 SHA-256**（M32 已定“一次声明”，能力仍未实测）；已卸载/更新中包签名解析失败的具体形态；替代接口（`TelecomManager.getDefaultDialerPackage` / `Telephony.Sms.getDefaultSmsPackage`）与 `ROLE_DIALER` / `ROLE_SMS` 的语义等价性在厂商 ROM 上的可靠性，含 `getDefaultSmsPackage` 返回 null 的区分是否成立；厂商设置与安装入口变体是否覆盖完整；通知 action + `BroadcastReceiver` 在 API 31–35 的行为（含进程被杀后重放与迟到回调的请求 id 校验，**无任何实测证据**）；`WindowState` 加 `windowType` 后 `sameWindow()` 是否会让正常场景误报 `stale_*`；**观察允许 `TYPE_INPUT_METHOD` 是否会造成反向误伤**（输入法窗口成为 `rootInActiveWindow` 时读树拿到键盘与候选词而非目标应用界面）；**`windows` 枚举在厂商 ROM 上能否稳定取到前台窗口类型**（取不到即 `UNKNOWN` → 拒绝观察，表现为正常应用上的读树/截图也可能 `system_window_denied`）；**应用分身/工作资料下的包名与签名形态**（首版已定不支持，但其前台解析成什么未实测）；**未批准时只回身份是否足以让模型停止重试同一调用**（文案约束的有效性未实测）。
- M30 设备回归的证明边界（不得写成已验证）：异常套件里「服务禁用中断与重新启用恢复」是**组合用例**，它最后返回 `stale_handle / No current tree observation` 与三种机制完全兼容——① 用例自己发的分页请求在宿主进入设置页后即 `clearTreeLocked()`（`ObservationRegistry.page()` → `requireTreeValid()`）；② `DEFAULT_TTL_MILLIS = 120_000` 自然过期；③ 服务中断的 `invalidateAll()`。因此只能写「禁用与中断行为已验证、重启后旧句柄不可用已验证」，**清树机制不可独立归因**。要独立证明需把重启拆成带 ACK 握手的独立子场景（M31 survey 已给设计），并为另一 mission。同一原则适用于 `window_type_unknown`：它是窗口列表未稳定时的 fail-closed 结果，**不得当作可重试的就绪信号**，也不得写成「恒为 0」。
- M30 的绿色轮次依赖宿主脚本 `mods/phone_agent/host/driver.py` 与 `run_official.py`（宿主测试脚本，不是产品代码、不进合成树、不被 `mod.json` 引用）。复跑前必须阅读该目录 README 的六处行为修正；这些修正只改宿主动作，**不得借此放宽任何测试断言或观察边界**。「测试打印标记、宿主执行动作」是既定分工，不是产品能力。
- 整屏 `AccessibilityService.takeScreenshot(Display.DEFAULT_DISPLAY)` 不保证对 `FLAG_SECURE` 报错：secure 内容可能以黑色区域出现在成功截图中。不得根据像素猜 secure、不得承诺不发送黑图；正常黑色页面保留。平台明确报错时返回 `screenshot_blocked`，不得发送图片或图片 metadata；成功黑图只作为普通截图，工具描述要求优先读树、不凭黑图猜坐标。
- secure 窗口的树在 API35 夹具上可读，但不是绝对保证；密码字段、自定义 View、窗口变化仍会影响树；未批准目标的输入被拒绝（`permission_required`），deny 成员被拒绝（`package_not_allowed`）。
- 输入错误码优先级固定为 `no_window` → `system_window_denied` → `package_not_allowed` → `permission_required` → 白名单内句柄/截图校验；测试必须断言精确错误码，前台包名未知时失败，不能“只要报错就算通过”。
- 权限弹窗在 API35 实测没有可访问 root：活动/聚焦弹窗窗口 `hasRoot=false`、`pkg=null`，`AccessibilityWindowInfo` 没有包名字段，服务也收不到 `permissioncontroller` 的 `TYPE_WINDOW_STATE_CHANGED`（M20/M21 已证伪窗口 root 与事件来源包名两种识别机制）。因此该场景读树、截图和输入保持 `no_window`，消息只做条件式人工提示，不声称识别具体权限弹窗；可取得系统包名的窗口仍按 `PackagePolicy` 返回 `system_window_denied`。异常测试内部断言精确 `no_window`、条件式提示和导航未执行（`back` 后读树仍 `no_window`）；真实弹窗和通知权限 `granted=false` 由宿主用 `dumpsys` 独立确认，不是测试内断言或产品检测能力；不能把任意 `no_window` 当作通过。
- `home`/`recents` 后前台离开白名单，后续输入（包括 `back`）被拒绝，模型无法自行恢复；文档和测试必须记录需要用户或宿主切回测试应用。
- 前台可视化使用独立 `PhoneAgentOverlay`：`TYPE_ACCESSIBILITY_OVERLAY` + `FLAG_NOT_TOUCHABLE | FLAG_NOT_FOCUSABLE`，不申请也不需要 `SYSTEM_ALERT_WINDOW`/`Settings.canDrawOverlays`，不复用或修改上游 `BackgroundOverlay`/`BackgroundRuntime`，服务断连即随连接销毁。首版默认随工具调用显示，不新增设置开关、`status` 字段或 ARB 文案。
- 可视化只在真实工具观察（读树、截图完成后）和允许包内已接受的动作上短暂显示：节点动作要求前置校验通过且 `perform` 返回 true，坐标手势要求 `dispatchGesture` 返回 true，系统动作要求 `performGlobalAction` 返回 true；`perform=false`/`dispatch=false`、被拒绝或前置校验失败的动作不产生任何动画。动画只表示系统接受或完成动作，不代表业务成功、任务进度、模型思考或用户审批，也不是安全护栏。
- 叠加层只用无文本图形，不显示输入文字、密码、截图字节或缩略图、节点文本、包名和坐标数值，不写敏感日志。截图前必须移除自身窗口并至少等待两帧（API35 实测还需约 48ms 合成周期）再调用 `takeScreenshot`；隐藏失败或 250ms 有界等待超时返回 `screenshot_failed` 且不发图片或图片 metadata，不得跳过隐藏让截图成功。读树不需要隐藏叠加层（`FLAG_NOT_FOCUSABLE` 保证它不会成为活动窗口）。
- 截图前的密码窗口遍历只排除能可靠确认属于本服务自己的 accessibility overlay 窗口（root 存在且 root 包名等于自身包）；root 包名未知或其他包名的窗口继续参与遮挡，不能把未知身份当作自身窗口，也不得屏蔽其他服务或应用的窗口。
- 叠加层事件在主线程真正绘制前再次校验清理代次和调用方的 `isActive`（手势 finished、服务代次）；clear/release/旋转/切窗先于 show 时旧事件不得重新出现。窗口移除失败或附着状态未知时不得再添加新窗口，截图必须 fail closed；动画结束回调按具体 View 清理，不能因 plan 已被清空而永久遗留窗口。
- 手势视觉复用真实 `duration_ms`（输入层已校验 50–2000ms）；尾段可以额外存在，但不得把真实时长改成更慢的视觉 travel 时长。
- 上游可触摸后台胶囊仍是已知兼容限制：Mod 无法隐藏其他 owner 的窗口，开启胶囊时截图可能包含胶囊、坐标手势可能被拦截，只能记录和提示，不宣称兼容。
- 叠加层在旋转、锁屏、`onInterrupt`/`onUnbind`/`onDestroy`、服务中断和前台窗口切换到其他包时清理；截图隐藏握手有界（约 250ms）且可被服务中断解除，迟到的帧回调不得触发第二次截图或恢复旧动画。几何、状态机和握手用纯 JVM 测试覆盖，不引入 Robolectric 或新依赖。
- 真实 `FLAG_SECURE`、权限弹窗和异常路径使用插件 `android/src/debug` 的 `SecureWindowFixtureActivity` 测试夹具：只新增 debug 源码和 manifest，不修改上游 `MainActivity`、`KelivoApplication`、`PhoneControlService`，不新增上游补丁或 `touches`，release 不编译、不合并。夹具只请求上游已声明的权限用于拉起系统窗口，不授予、不录音、不使用其他敏感能力。
- 异常集成测试的夹具启动、secure 切换、权限弹窗、锁屏和服务开关由宿主/CU 在打印标记后操作；测试只轮询并断言结果。禁止用 `settings put secure enabled_accessibility_services` 写授权；服务开关只走系统界面。
- 权限弹窗要求设备唤醒：API35 实测息屏时 `am start` 不会让弹窗获得前台焦点（`mCurrentFocus=null`），唤醒后立即出现；宿主在 `PHONE_AGENT_PERMISSION_WINDOW` 标记后先唤醒、启动夹具并用 `dumpsys` 独立确认真实 `GrantPermissionsActivity`，测试在首次等待 45 秒未进入无窗口状态后打印 `PHONE_AGENT_PERMISSION_WINDOW_RETRY`，重试后仍未进入则失败，不因 `root=null` skip。夹具只在 `POST_NOTIFICATIONS` 未授予时请求，已允许时不会产生弹窗；不得 grant/revoke/clear。
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

M33 白名单门控与签名绑定（2026-11-15/16，仅单元与静态检查，**无设备证据**）：Loader `dart format --output=none --set-exit-if-changed tool test` 0 变更、`dart analyze tool test` 无问题、`dart test` **165 通过**；合成树 `dart analyze --fatal-infos lib test integration_test tool` **No issues found**；插件 Kotlin `:kelivo_phone_agent:testDebugUnitTest --rerun-tasks` **170 通过、0 失败**（新增 `AppWhitelistTest` 16 项、重写 `PackagePolicyTest` 51 项）；插件 Dart `flutter test` **25 通过**。**未运行 integration_test、未构建 APK、未接设备**；异常套件的断言已按新错误码同步（helper 接受集合、`permission_required` 身份解析、重启等待的可重试子集），但实机结果属 M36。本机建树需要 `core.longpaths`（Loader 只传 `-c core.autocrlf=false`，上游含超长路径），M33 用进程级 `GIT_CONFIG_*` 绕过，未改任何 git 配置。

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
