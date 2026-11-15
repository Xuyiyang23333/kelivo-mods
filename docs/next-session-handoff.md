# 下一次会话交接：Phone Agent 前台可视化叠加层

> **M35（2026-11-16，实现，无设备证据）**：审计元数据已落地——新增 `mods/phone_agent/plugin/android/src/main/kotlin/com/kelivo/phoneagent/AuditLog.kt`（`AuditRecord` 七字段、`AuditAction` 固定 token、`AuditIdentity` 从不抛错、`AuditLog` 30 天/2000 条滚动、`AuditStorage`/`FileAuditStorage`、`AuditRecorder`）。`PhoneAgentService.execute` 在 `reply` 收口处记录一次（成功 `ok`、失败写既有结构化错误码），包名只在真正取到前台窗口处写入；助手/会话 id 由通道可选参数 `assistant_id` / `conversation_id` 从 Dart 侧传入，缺失记 null。审计失败静默计数、**不阻断工具主路径**。存储 `noBackupFilesDir/phone_agent_audit.tsv`，**没有读取通道、没有界面**。自检：插件 Kotlin `--rerun-tasks` **194 通过**（新增 `AuditLogTest` 14 + `AuditRecorderTest` 10）、插件 Dart **30 通过**、合成树 `dart analyze --fatal-infos lib test integration_test tool` **No issues found**（树 `0073b68d56863418`，`modsetHash` `0073b68d568634186819f8b16bbd49ce836bca5b1d45662faaa02355d599fffa`）；**未构建 APK、未接设备、未跑 integration_test**。批准卡片/通知（M34）、首次隐私确认、任务控制与恢复仍未实现。

> **M33（2026-11-15，实现）**：应用批准契约的**第 2、3 步已落地**——插件 manifest 一次声明 `QUERY_ALL_PACKAGES`；新增 `AppWhitelist.kt`（`SigningIdentity`、`WhitelistStore`+`FileWhitelistStorage`、`SigningResolver`、`AppApprovals`、`buildPreApprovedPackages`、`DENY_PACKAGES`）；`PackagePolicy` 从 allowlist 改为 **deny 清单＋用户白名单**，观察与输入两条路径都判，未批准只回应用身份与 `permission_required`（不建立观测、不占 `treeBudget`、不截图）；通道新增 `approvedApps`/`approveApp`/`revokeApp`（幂等、写入前重解析签名、撤销立即生效、不依赖服务连接）。**批准卡片/通知、Mods 页白名单页、审计、首次隐私确认、任务控制与恢复仍未实现**；**未跑任何设备**，异常套件只做了断言同步（helper 接受集合、`permission_required` 身份解析、重启等待的可重试子集）。详见 `docs/phone-agent-plan.md` 7.5.4/7.5.9 与 7.6 的 M33 自检记录。本节以下各节的设备与 APK 记录仍对应 M33 之前的代码。

> **M32（2026-11-15，仅文档）**：应用批准契约已修订为「批准 = 读＋操作一体」（未批准应用的读树/截图只返回应用身份与 `permission_required`），并新增应用身份（`QUERY_ALL_PACKAGES`）、批准后恢复与任务控制、结果未知语义、多窗口首版不支持、批准终态与防自我批准、首次隐私确认（方案 B）；观察侧也判 `package_not_allowed`，且构建期范围在批准上线时转为 deny 清单（两项均为 tower 定论，用户可推翻）。来源分层：用户拍板项、已定契约（早期设计）、tower 定论与设计提案（tower 建议）四档，不要把设计提案读成用户已同意。第 8 节是实现入口，含三项仍未定稿的取舍。

## 0. M27 当前状态（2026-11-13，第 1 步实现）

- 本轮目标：只做第 8 节**第 1 步**——硬基线集合 + `WindowState.windowType`。不含观察边界、用户白名单、批准交互和审计（M35 后来补齐了审计，见开头 M35 段）。
- 新增 `mods/phone_agent/plugin/android/src/main/kotlin/com/kelivo/phoneagent/AppBoundary.kt`：`WindowType`（平台常量→枚举，`else` 一律 `UNKNOWN`，`allowsInput` 仅 `APPLICATION`）、`HARD_BASELINE_PACKAGES`（原 5 个 AOSP 包 + 证书安装器 + settings 及其厂商变体 + MIUI 包安装器与权限授予界面，返工后共 21 项）、`KELIVO_PACKAGE` / `TEST_PACKAGE` 精确常量、`RoleHolders`（`Resolved` / `Unavailable`）、纯函数 `PackagePolicy.requireInputAllowed(packageName, windowType, roleHolders)`。
- 判定顺序（先命中者生效，均有 JVM 断言）：`no_window` → 静态硬基线（含 Kelivo 精确包名）→ 角色解析失败 → 角色持有者 → 窗口类型 → `package_not_allowed`。**本步没有任何路径返回 `permission_required`。**
- `WindowState` 加 `windowType`；`PhoneAgentService.windowState()` 内部按 `windowId` 从 `windows` 匹配 `AccessibilityWindowInfo.type`（同一次读取，策略层不另读 `windows`），解析失败落到 `UNKNOWN` 并拒绝；`sameWindow()`、截图观测、`TreeObservation`、`CapturedScreenshot` 全部带上类型。
- 角色持有者：`RoleManager.getRoleHolders` 是 **@SystemApi**（`MANAGE_ROLE_HOLDERS` 签名权限），公共 SDK 编译不过，实测报 `Unresolved reference 'getRoleHolders'`。改用公共等价接口 `TelecomManager.defaultDialerPackage` + `Telephony.Sms.getDefaultSmsPackage`；查询抛异常或 `TelecomManager` 缺失才返回 `Unavailable`（策略层拒绝全部输入），返回 null 视为“系统明确没有该角色默认应用”，不封死无短信能力的设备。
- **与原计划的差异**（已回写 plan 7.5.1）：原定 `RoleManager` 角色解析改为公共等价接口；`RoleHolders.Unavailable` 被提前到角色持有者判定之前。
- **R1 返工（reviewer `p2-6items` / `fix-then-merge`）**：硬基线集合补入 `com.miui.packageinstaller`、`com.lbe.security.miui`、`com.android.certinstaller`、`com.xiaomi.misettings`（reviewer 与 tower 均在 `1960cd68` 用 `dumpsys package` / `resolve-activity` 实证这些包持有安装、卸载、权限授予、证书安装入口）；`windowType()` 改为记录命中结果后循环结束统一返回，修复命中点之后窗口未 `recycle()` 的泄漏；plan 7.5.2 的角色解析描述改为与代码一致（无 `RoleManager`/版本分支），并把厂商枚举写成「按真机 `resolve-activity`/`dumpsys package` 实测补全」的流程与「第 3 步白名单上线前必须补全」的硬要求；同步 README 的两处输入层状态、AGENTS.md 未验证假设对象、本节 §8 第 1 步的设备结果。返工后未重跑设备，理由按改动分别说明：补入的 4 个厂商包**确实改变可观察行为**——硬基线判定排在构建期 allowlist 之前，这些包成为前台时错误码由 `package_not_allowed` **收紧为** `system_window_denied`；设备结果可沿用的依据是**官方 `phone_agent_test.dart` 全程前台为测试包，这 4 个包不会在该流程里成为前台**（不是“错误码没变”）。`windowType()` 的 `recycle` 改造只改回收时机，判定结果等价。插件 Kotlin 122 项全绿。
- 测试：`PackagePolicyTest` 原有 5 条错误码断言**未改**（仅调用签名加窗口类型与角色参数），新增 settings、厂商变体、角色持有者、`Unavailable`、Kelivo 自身、测试包不误伤（含 `com.psyche.kelivo.phoneagent.other` 反例）、5 种非 `APPLICATION` 窗口类型、拒绝消息固定标识且不含包名、硬基线优先于窗口类型、窗口类型优先于构建期白名单、平台常量映射（含 0 与 99）；`ObservationRegistryTest` 新增窗口类型变化使句柄/分页/截图失效。
- **设备结果**：API35 模拟器（`emulator-5554`）与物理 MIUI API31（`1960cd68`）官方 `phone_agent_test.dart` 各 **`+2`、All tests passed!、EXIT=0**——截图、读树、节点点击、坐标滑动、滚动、聚焦后 `set_text`、二次读树全程没有出现 `stale_*`，验证 `sameWindow()` 加 `windowType` 比较未在两台设备上产生误报。无障碍授权由宿主编排触摸在系统界面完成（点开 Kelivo Phone Agent → Allow / 「确定（5）」），**未用 `settings put secure` 写授权**；`flutter test` 每次重装包都会撤销授权，两台设备首轮均因此在 `setUpAll` 超时，授权后重跑通过。MIUI 结束后 `flutter test` 卸载了测试包，授权位随之回到 `null`/`0`。
- **未做/未验证（M27 当轮）**：观察边界（M28 随后实现；M27 当轮读树与截图仍不检查包名或窗口类型）、用户白名单、签名校验、`permission_required`、批准交互、审计全部未实现。完整异常套件、VLM 固定任务未运行。**R1 返工后**最终源码树 `V:/coding/kelivo-private/.tower/worktrees/wt-27/.build/worktrees/2f6528a0e4e4c8d6`（`modsetHash` `2f6528a0e4e4c8d69b75b368b0850b599a360893765f841c3250d1b8cc042355`，`plan`/`apply`/`verify` 通过），产品 APK 在该树 `flutter clean` + 显式 `flutter build apk --debug` 生成：**181,408,190 字节**，SHA-256 `1c2b50967f2c2be0c432218ace3a3bd25f7ea4a932092e75c06af1fed48c387c`，merged manifest 含 `SecureWindowFixtureActivity`（1 处）与 `PhoneAgentService`（1 处），dex 含 4 个新增硬基线包名，未构建 release，构建后未再运行 integration_test（返工前 APK 181,407,582 / `5b706dd5…` 只作历史）；根项目 `dart analyze`/上游 seam 回归未跑（本轮只改插件 Kotlin 与文档，未触及 Dart 侧接缝）。
- Windows 环境记录：`git worktree add` 在本机因 260 字符路径上限失败（`Filename too long`，fail 在 `dependencies/flutter_inappwebview_android/.../ThreadedInputConnectionProxyAdapterView.java`）。解决方式是在 Loader 进程环境注入 `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.longpaths GIT_CONFIG_VALUE_0=true`，**未修改上游 git 配置**，也未改 Loader 代码。失败的 `17007461ac82c427` 状态文件已用 `clean --modset` 精确清理。

## 0.1 M26 状态（2026-11-13，仅文档；以下为 M26 当时状态，第 1 步已由 M27 实现）

- 本轮目标：把 M25 调研结论 + 用户三项决策写成可执行的契约文档；**只改四个文档文件**（`docs/phone-agent-plan.md`、`docs/next-session-handoff.md`、`AGENTS.md`、`mods/phone_agent/README.md`），不改代码、测试、`mod.json`、白名单或上游。
- 新增 `docs/phone-agent-plan.md` **7.5 应用边界与应用授权**（M26 当时标题为「设计提案」；M32 后当前标题为「第 1、2 步已实现；M32 修订的批准契约未实现」）：默认拒绝；三层判定（硬基线 → 窗口类型 → 用户白名单），顺序插在 `no_window` 之后、句柄/截图校验之前；`(包名, 签名证书哈希)` 双匹配；`com.android.settings` 及厂商变体进硬基线且仍返回 `system_window_denied`（不新增错误码）；`package_not_allowed` 保留为构建期硬禁止语义。
- 窗口类型双层判定写成不对称集：输入允许集 `{TYPE_APPLICATION}`；观察允许集 `{TYPE_APPLICATION, TYPE_INPUT_METHOD}`。文档写清了两层都判的必要性（只看包名漏输入法/overlay 窗口，只看类型漏 `TYPE_APPLICATION` 的 settings）与未知类型 fail closed。
- 观察边界只判硬基线与窗口类型、不判白名单，理由与代价都写明：**不承诺读树不泄漏第三方应用自身界面文本**；截图的前台判定先于且独立于全窗口密码遮挡遍历。
- 新增 `docs/phone-agent-plan.md` **7.6 实现前置风险与行为变更**：`WindowState` 加 `windowType` 的影响面、`phone_agent_exception_test.dart` 5 处会红的观察边界依赖（settings 树 `:537`/`:549-550`/`:557`、叠加层触摸 `:202-232`、home/recents `:346-377`）、收紧型行为变更、历史 VLM 结果不可复用、五项待实测假设。
- 同步 `AGENTS.md`（8 条契约条目）、`mods/phone_agent/README.md`（用户可读的「应用白名单与批准」小节，M26 当时标题为「设计提案，尚未实现」，M32 改为「已定契约，尚未实现」）+ 错误码表分界、本文件（本节 + 第 8 节下一阶段入口）。
- **重要边界（M26 当时）**：M26 未改一行产品代码，**未运行任何测试、未构建 APK、未接设备**，未产生新 `modsetHash` 或 APK 记录；M26 结束时所有“会被拒绝”的描述都只是设计意图，当时代码是输入只允许 `com.psyche.kelivo.phoneagent`、读树与截图不检查包名或窗口类型。**M27 已实现第 1 步（输入硬基线 + 输入窗口类型），观察层与其余各层仍未实现**，当前状态见第 0 节。
- 写文档时修正了 M25 草稿的三处不准确：`WindowState` 实际只有 `PhoneAgentService.kt:512` 一个构造点（M25 写“四个构造点”，实为 1 个定义 + `:294/:340/:434` 三个调用点 + 三个测试夹具）；补充了“Kelivo 自身进硬基线”与测试包 `com.psyche.kelivo.phoneagent` 的精确包名区分陷阱；M25 说“README 与 9.3.7 本来就写着宿主确认、属实现落后于文档”不成立——现有文档只规定了权限弹窗的宿主 `dumpsys` 确认与“服务开关由宿主在系统界面操作”，**没有**规定服务禁用用例的前台页面由宿主确认，实现时必须补齐这一条。

## 0.2 M24 状态（2026-11-13）

- 本轮目标：处理"聚焦后同一句柄 `set_text` 返回 `stale_handle`"的长期未结问题——先在设备上复现与解释机制，再做最小修复，并跑双 API 与物理 MIUI 回归。
- **自然循环未复现**（如实记录，不写成已复现）：API35 四版夹具共 278 次迭代、MIUI 80 次迭代、MIUI 官方 `phone_agent_test.dart` 连续 4 轮，均未出现 `stale_handle`。唯一稳定失败是 `delay=0` 的 `action_unavailable`（tap 后语义树尚未更新出 `SET_TEXT`）。
- **受控机制验证成功**：读树拿句柄 → tap 聚焦 → 强制重建输入框语义子树（`KeyedSubtree` 换 key）→ 旧句柄 `set_text` 连续 3/3 返回 `stale_handle`，消息精确为 `The target node changed (refresh_failed)`；不重建的对照组 3/3 成功。重建后新树里逻辑节点仍在（同 class/hint/bounds、`editable=true`），说明平台重建了节点对象、逻辑节点未变。
- **修复（`520de30`）**：`NodeTreeReader` 记录每个节点的"根→节点子索引路径"；`ObservationRegistry` 在 `refresh()` 失败时按该路径在当前活动窗口重解析一次，并要求指纹**逐字段完全一致**才继续。路径缺失、节点不存在或任一字段不等仍返回 `stale_handle`（路径失败保留 `refresh_failed`）。
- **A/B 设备证据**（API35，同一夹具 8 轮，含 `refocus=false/true`）：**重心在启用组**——修复后 8/8 `set_text` 成功且控件内容变为 `fix 0`…`fix 7`；旧句柄此时 `refresh()` 已为 false，文本能落进重建后的控件，唯一可能路径就是按路径重取，这直接证明重解析被执行。禁用组 8/8 `refresh_failed` 属构造性对照（短路后必然抛错），不构成独立证据。
- **A/B 树的证据卫生**：A/B 在 `wt-24/.build/worktrees/dfcef53cfd77ea78` 上跑，该树是手工注入 `dependencies/kelivo_phone_agent/` 的临时树，**未走 `apply`**，`.state.json` 的 `modsetHash` 仍是 M23 基线 `dfcef53cfd77ea78…`，不代表实际内容，`verify` 结论不可信，**不可作为可复现基线**。已核对其插件源码与 R1 前的 `fa251a4` 逐字节一致（34 个文件全等），故 A/B 测的是当时的交付代码；与最终 tip `6222d78` 有 4 个文件不同（`NodeTreeReader.kt`、`ObservationRegistry.kt`、`PhoneNode.kt`、`ObservationRegistryTest.kt`），差异仅限 F1/F2 的行为保持型重构，不能写成「与最终分支一致」。设备结果对应的行为等价树为 R1 前的 `47675033b3d132e0`（该树后被就地改动：插件源码已同步为 R1 后版本，但 `MOD_BUILD.json` 与 `app-debug.apk` 仍是 R1 前记录，三者不一致，`verify` 不可信，不能作为 R1 前代码的可复现样本）；R1 返工后唯一可复现基线是 `29861376ffaa5e41`。该临时树的残留夹具与脚本已删除。
- **修复的真实边界**（不得写成"彻底解决"）：只对"平台重建节点对象、逻辑节点未变且重建后的节点仍 advertise 所需动作"生效。若重建后语义节点不再 advertise `SET_TEXT`，执行层仍返回 `action_unavailable`——本轮没有放宽 `performNodeAction`。第一版验证时重建销毁了 `TextField` 并丢焦点，结果从 `stale_handle` 变成 `action_unavailable`；改用显式 `FocusNode` 重建后才对应真实场景。
- 自动检查：Loader format/analyze 通过、Loader 165、插件 Dart 17、插件 Kotlin 106（新增 7 + R1 返工 2）、Flutter 126、上游 seam 56、`dart analyze --fatal-infos` 无问题、`verify` 通过（R1 返工后树 `29861376ffaa5e41`）。
- 设备结果：API35 官方 `phone_agent_test.dart` `+2`、EXIT=0；物理 MIUI `1960cd68` 官方 `+2`、EXIT=0。API35 完整异常套件**未取得绿色整轮**（最好 `+6 -2`，最后一轮 `+5 -3`），三条失败均为宿主脚本时序（叠加层截图 518/409920 像素差异属 M23 既有断言、权限用例宿主重建 Activity 丢 harness、服务禁用用例确认弹窗晚于 pending 排空），不是 M24 产品断言失败；已通过 FLAG_SECURE、旋转、home/recents、锁屏、叠加层宿主触摸。按收口规则不再迭代宿主脚本，不写成全绿。
- API 29 `357784090209204` 本轮离线，按用户决定记录为**未运行**。
- 产品 APK（R1 返工后最终树 `29861376ffaa5e41`，干净树 `flutter clean` + `pub get` + `pub get --directory tool/l10n --enforce-lockfile` + 显式 `flutter build apk --debug`，构建后未再运行 integration_test）：**181,403,918 字节**，SHA-256 `5a54cb3a459a9c8758033fce6eba14bdf098b0b6c02477be45e83e723bd41b43`；debug merged manifest 含 `SecureWindowFixtureActivity`（1 处）与 `PhoneAgentService`（1 处）；未构建 release。R1 前树 `47675033b3d132e0` 的 181,404,642 / `677c26d9…` 只作历史。
- R1 返工：F1 把 `TreeObservation` 从 data class 改为普通类并把句柄槽位封装为 `handleAt`/`replaceHandle`；F2 去掉 `recycle` 的 `!==` 守卫、改为按「`child()` 每次返回独立引用」契约无条件回收，并在 `PhoneNode` 写明契约、补 2 项路径回收断言。两项均为行为保持型重构，**未重跑设备**；设备结果（API35/MIUI 官方测试、异常套件）对应 R1 前的树 `47675033b3d132e0`。
- 环境记录（本机）：`C:/Users/David/AppData/Local/Pub/Cache` 曾有 36 个空包目录（含 `window_manager`、`dynamic_color`、`file_picker` 等），导致 `flutter build apk --debug` 在 `compileFlutterBuildDebug` 失败；删除空目录后 `flutter pub get` 重新拉取即恢复。另：`flutter test` 生成的 `app-debug.apk` 只含 x86_64 的 `libflutter.so`，直接装到 arm 设备会 `Could not find 'libflutter.so'` 崩溃，`flutter test -d 1960cd68` 会自行按 ABI 构建。

### M23 历史状态（2026-11-12）

- 本轮目标：按 M18 只读设计实现首版前台可视化叠加层（V1 原生核心），不新增设置开关、`status` 字段、ARB 文案或插件通道方法；不改 schema、白名单、上游宿主和 `mod.json`。
- 契约：独立 `PhoneAgentOverlay` 使用 `TYPE_ACCESSIBILITY_OVERLAY` + `FLAG_NOT_TOUCHABLE | FLAG_NOT_FOCUSABLE`，不申请普通悬浮窗权限，不复用上游 `BackgroundRuntime`/`BackgroundOverlay`。只在真实工具观察（读树、截图完成后）和允许包内已接受的动作（`perform`/`dispatchGesture`/`performGlobalAction` 返回 true）时短暂显示；拒绝路径不产生动画；动画不代表业务成功、任务进度、模型思考或用户审批。
- 隐私：只用无文本图形，不显示输入文字、密码、截图字节或缩略图、节点文本、包名和坐标数值。截图前移除自身窗口并等待两帧加 48ms 合成周期，隐藏失败或附着状态未知返回 `screenshot_failed` 且不发图；读树不隐藏叠加层。密码窗口遍历只跳过能可靠确认属于本服务的 accessibility overlay（root 存在且 root 包名等于自身包）；root 包名未知或其他包名继续参与遮挡。
- 代码：新增 `OverlayVisuals.kt`（纯 JVM 事件、几何、状态机、截图隐藏握手、`OverlayShowGate`、`OverlayAttachmentTracker`）和 `PhoneAgentOverlay.kt`（窗口、无文本图形、主线程生命周期、按 View 清理）；接入 `PhoneAgentService`、`NodeActionExecutor`、`ScreenshotCapture`；新增 `OverlayVisualsTest.kt` 并扩展 `NodeActionExecutorTest.kt`。
- 返工（reviewer round 1，6 项 findings）：密码遮挡未知包名不再排除；show 在主线程绘制前校验清理代次和 `isActive`（手势 finished、服务 epoch）；移除失败/未知附着 fail closed 且按具体 View 清理；手势 travel 复用真实 50–2000ms；触摸穿透改为宿主 adb 独立触摸；迟到帧测试保存 resume 前回调并显式执行。
- 返工（reviewer round 2）：截图隐藏握手后、`takeScreenshot` 前重新读取当前窗口并比较 `windowId`/包名/宽高/旋转，变化返回 `stale_observation` 且不发图；两次读取中窗口为 null 均按 `stale_observation`，`currentWindow()` 抛异常按 `screenshot_blocked` fail closed；`onSuccess` 回调里再比较一次当前窗口，不一致不处理/不发送图片。同一活动窗口内新出现密码字段、非活动分屏窗口变化和同窗口分屏 resize 不保证遮挡，已在 plan 2.6/7.4 与 README 写成已知限制。`OverlayAttachmentTracker` 格式修正且生产 `hideNow` 使用 `hideResult()`；动作开始时捕获清理代次并传给 `show`，动作后 clear/切窗使旧视觉失效；补 `begin` 替换、`password_node_denied`、窗口变化和重复 resume JVM 测试；round-1 的 `099843`/`e6de` 仅作历史。**round-2 当时**的基线为设备树 `f1b26a58`、最终树 `2445a838`、无产品 APK；round-4 当前基线见第 0 节（设备树 `9ebf2e99`、最终树 `dfcef53c`、产品 APK 181,403,054 / `501d4a00…`）。
- 已知限制：上游可触摸后台胶囊无法被 Mod 隐藏，开启胶囊时截图可能含胶囊、坐标手势可能被拦截；`addView` 在部分厂商 ROM 上可能失败，失败时只禁用本会话可视化；截图隐藏握手增加约两帧加 48ms 合成等待和极少量 `screenshot_failed` 风险。
- round 4 结果（2026-11-12，源码树 `V:/coding/kelivo-private/.tower/worktrees/wt-23/.build/worktrees/9ebf2e991caa07ed`，`modsetHash` `9ebf2e991caa07ed3e8e5b4484649de84139e89a31ac8837f779ca34aa2d8c66`）：API35 独立 AVD `Kelivo_M23_API_35` 完整异常套件 **`+8`、`All tests passed!`、EXIT=0**（含旋转、锁屏、服务禁用/重启、权限窗口 `no_window`），官方 `phone_agent_test.dart` `+2`、EXIT=0；物理 MIUI API31 官方 `+2`、EXIT=0，「叠加层不污染产品截图」`+1`、EXIT=0；本地 Loader 165、插件 Kotlin 97、Flutter Mod/Phone Agent 126、Loader/根项目静态分析和 `verify` 通过。产品 debug APK 在最终树 `dfcef53cfd77ea78` 于全部设备测试后 `flutter clean` 显式构建：181,403,054 字节，SHA-256 `501d4a0087294258baa882e9a32856208805fcba88228ec34e15016ae89689fb`；构建后未再运行 integration_test。
- API35 结果（返工后，2026-11-12）：官方 `phone_agent_test.dart` `+2`、EXIT=0（返工树）。完整异常套件多次整轮运行的真实退出码均为 1，未得到绿色整轮：旧 AVD 一次 `+6 -2`（锁屏/服务禁用失败，期间模拟器 system_server 重启），一次 `+7 -1`（唯一失败为「服务禁用中断与重新启用恢复」的宿主设置页时序），最后一次有界整轮在 `setUpAll` 失败（`dumpsys activity lastanr` 为 `Input dispatching timed out (Application does not have a focused window)`，ANR 发生在任何工具调用之前、应用进程存活、无障碍连接为 DEAD，属宿主/模拟器窗口焦点与输入分发问题，不是 overlay 主线程死锁）。独立测试 AVD `Kelivo_M23_API_35`（`.build/avd`，已有 android-35 google_apis_playstore x86_64 镜像，不 wipe 旧 AVD）官方 `+2`、EXIT=0，完整异常套件最好 `+7 -1`、EXIT=1（唯一失败同为服务禁用宿主时序），另一次 `+6 -2`；旧 AVD 另出现 `com.android.systemui` 的 `Input dispatching timed out ([Gesture Monitor] edge-swipe (server) is not responding)`，无产品栈。round 2 树 `f1b26a580b737e14` 的完整异常套件为 `+6 -2`、EXIT=1：失败为「旋转后旧句柄与旧截图失效」（转回竖屏截图 10 秒 timeout，单独重跑 `+1`、EXIT=0）和「锁屏 device_locked 与解锁恢复」（宿主恢复等待点击目标超时，单独重跑 `+1`、EXIT=0）；「服务禁用中断与重新启用恢复」该轮通过且单独重跑 `+1`、EXIT=0（`codes=interrupted,ok`）。round-2/3 历史轮未生成产品 APK；round-4 产品 APK 已生成，见第 3 节。
- MIUI 结果（返工树，2026-11-12，`1960cd68`）：官方 `phone_agent_test.dart` `+2`、EXIT=0；「叠加层不污染产品截图」`+1`、EXIT=0；「叠加层可见时真实触摸不被拦截」`+1`、EXIT=0（`PHONE_AGENT_OVERLAY_HOST_TOUCH_RESULT: package=com.android.systemui`，宿主 `adb shell input swipe` 独立注入）。服务停用后 `dumpsys window windows` 中叠加层窗口数为 0；已恢复 `enabled_accessibility_services=null`、`accessibility_enabled=0`、`stay_on_while_plugged_in=0`。
- API35 宿主侧一次性清理（审计记录）：授权阶段 watcher 固定坐标误触 TalkBack 授权弹窗，TalkBack 被短暂启用；宿主用 `settings put secure enabled_accessibility_services` 清空以移除误启用的 TalkBack，随后仍通过系统 UI 为 Kelivo Phone Agent 打开开关并点 Allow。该命令只清理宿主误操作，不是 Phone Agent 授权路径、不是产品能力、不是授权绕过，也不扩展到其他设备；Phone Agent 授权仍只走系统 UI。
- round 4 API35 叠加层清理与像素证据（构建树 `a460dcbc`，代码/测试与设备树 `9ebf2e99` 一致，仅 README 副本不同）：服务禁用用例单独重跑 `+1`、All tests passed!、EXIT=0；宿主 `dumpsys window windows | grep -c PhoneAgentOverlay` 原始输出 `R5_OVERLAY_WINDOWS_AFTER_DISABLE: count=0`、`R5_OVERLAY_WINDOWS_AFTER_RESTART: count=0`。宿主 `screenrecord` 帧确认观察脉冲（约 121.5–121.9s，强调色 `#008999` bbox 约 34×34）和节点点击圆环（约 125s，浅蓝圆环）。
- 坐标滑动定向像素验证（构建树 `af52c6f7`，当时的最终树；现最终树为 `dfcef53c`，仅 README 副本不同。临时把官方测试 swipe `duration_ms` 改为 1500ms 仅用于本次运行，未提交；产品代码/测试源未改）：宿主 `screenrecord` 20s、30fps 提帧，检测到 `#008999` 圆点沿 x≈539 从 bbox `(522,1110)-(556,1146)` 连续上移到 `(522,462)-(556,496)`，约 42 帧/1.4s，末端环 bbox `(518,460)-(560,508)`；轨迹与 `phone_agent_input` 的 1500ms 坐标滑动一致，坐标滑动轨迹可见。此前 300ms 官方测试帧未检测到，属短动画采样/替换时序限制，不是产品未绘制。
- 宿主稳定性重试：`_screenshot` 对 `rate_limited`/`timeout` 最多重试 2 次；旋转用例绿色不证明单次截图总能在 10 秒内完成，产品超时语义未改变。
- 交付树（round 4）：设备运行树 `V:/coding/kelivo-private/.tower/worktrees/wt-23/.build/worktrees/9ebf2e991caa07ed`（`modsetHash` `9ebf2e991caa07ed3e8e5b4484649de84139e89a31ac8837f779ca34aa2d8c66`）；最终源码树 `V:/coding/kelivo-private/.tower/worktrees/wt-23/.build/worktrees/dfcef53cfd77ea78`（`modsetHash` `dfcef53cfd77ea78fe898710efa92991fa15a140b8d0424193279f7ad21aac77`），与设备树仅 `plugin/README.md` 文档副本不同；产品 APK 在最终树 `dfcef53c` 构建（`a460dcbc` 仅作设备测试构建树且其 APK 已被 integration_test 覆盖）。`plan`/`verify`、format、Loader 165、Kotlin 97、Flutter 126 和静态分析通过；产品 debug APK 在最终树 `dfcef53cfd77ea78` 于全部设备测试后 `flutter clean` 显式构建：181,403,054 字节，SHA-256 `501d4a0087294258baa882e9a32856208805fcba88228ec34e15016ae89689fb`；debug merged manifest 含 `SecureWindowFixtureActivity`（1 处），release merged manifest 不含该夹具（0 处）且含 `PhoneAgentService`（1 处）；构建后未再运行 integration_test。round 2 历史树：设备运行树 `f1b26a580b737e14`、最终源码树 `2445a838f5b71e56`。
- 未验证：API29、签名 release、MIUI keyguard 遮挡、上游胶囊开启兼容；观察脉冲、节点点击圆环和坐标滑动轨迹均已获宿主 `screenrecord` 像素证据（滑动为 1500ms 定向验证），不把触发日志写成像素验证。

### M22 历史状态（2026-11-12）

- 本轮目标：按用户同意做权限弹窗保守收尾，不追查新识别机制。只改中文文档、`PhoneAgentService` 无可访问窗口的英文提示和 debug 异常测试；不改 schema、白名单、上游、读树/截图密码遮挡或输入边界。
- 契约：不可识别权限弹窗仍返回 `no_window`，读树/截图/输入共用条件式人工提示（“如果看到系统权限弹窗，请人工处理/取消，再返回测试应用”），不声称识别具体权限弹窗；可取得系统包名的窗口仍返回 `system_window_denied`；错误优先级和输入边界不变。宿主 `dumpsys` 确认是测试前提，不是产品检测能力。
- M20/M21 证据（均 abandoned，未合并生产代码）：API35 真实 `GrantPermissionsActivity` 期间活动/聚焦弹窗窗口 `hasRoot=false`、`pkg=null`，`AccessibilityWindowInfo` 没有包名字段；唯一有 root 的是后台 `com.android.systemui`（`active=false focused=false`）；服务没有收到任何 `permissioncontroller` 的 `TYPE_WINDOW_STATE_CHANGED`，只有 `pkg=null` 的 `TYPE_WINDOWS_CHANGED`。窗口 root 补全和事件来源包名两种机制均不可用。
- 测试改动：删除 `root=null` 的 skip 分支；宿主在 `PHONE_AGENT_PERMISSION_WINDOW` 后唤醒、启动夹具并用 `dumpsys` 确认真实弹窗，测试轮询进入 `no_window` 后直接调用节点 `tap`、截图和 `back`，断言精确 `no_window` 与条件式提示；`back` 后读树仍为 `no_window`，证明没有执行系统导航；宿主取消弹窗后确认 `POST_NOTIFICATIONS` 仍 `granted=false`。首次 45 秒未进入时打印 `PHONE_AGENT_PERMISSION_WINDOW_RETRY` 再等 60 秒，仍未进入则失败，不把任意 `no_window` 当作通过。
- 本轮结果：设备运行树 `V:/coding/kelivo-private/.tower/worktrees/wt-22/.build/worktrees/d94f4165af9277d5`，`modsetHash` `d94f4165af9277d5bbdc83c3c07bcc5bdce55cb4c241a284edfdcd5d5d0a2c9d`；R1 文档返工后最终源码树为 `V:/coding/kelivo-private/.tower/worktrees/wt-22/.build/worktrees/b9989da92f35bac8`，`modsetHash` `b9989da92f35bac8703cb5ed803499222886ec6bae15d5e8045a8e45b6689725`，两树仅 `plugin/README.md` 文档副本不同，代码/测试一致，未重跑设备。API35 官方 `phone_agent_test.dart` `+2`、EXIT=0；完整异常套件 `+6`、EXIT=0，权限场景宿主 `dumpsys` 确认 `GrantPermissionsActivity`，测试打印 `PHONE_AGENT_PERMISSION_TREE: package=null type=tool_error error=no_window`，tap/截图/back 均 `no_window` + 条件式提示，back 后仍 `no_window`，`POST_NOTIFICATIONS` 仍 `granted=false`；服务禁用批次 `size=1000 elapsed=670ms codes=interrupted,ok`。Loader 165、根项目 seam 56、插件 Dart 17、插件 Kotlin 66 通过（设备测试树；代码/测试与最终树一致），最终树静态分析 `No issues found!`。产品 APK 与最终树记录见第 3 节。
- 下一阶段：可视化叠加层设计已获批准，但不在本 mission 实现；本 mission 不新增 overlay、不改 UI。
- 未验证：签名 release、原生截图/手势/通道/worker 排队超时、`stale_handle` 根因；API29 真机 `357784090209204` 本轮不在线；物理 MIUI API31 未运行锁屏、home/recents、服务中断和权限弹窗；`llama-cpp/llama-cpp` 的物理完整坐标 swipe 未完成。
- 环境注意：本 worktree 为 LF（`core.autocrlf=false`）。Windows 上创建合成 worktree 需 `core.longpaths=true`；本轮（M22 当时）是用 `GIT_CONFIG_COUNT/KEY_0/VALUE_0` 进程环境变量手工绕过，未修改上游 Git 配置，属于已废弃的临时手法——M37 起 Loader 自带的每个 git 进程都传 `-c core.longpaths=true`，不再需要手工设置。当时未加该设置时 `git worktree add` 会因长路径失败，Loader 会留下状态文件，需 `clean --modset <hash>` 后重试。API35 模拟器 `emulator-5554` 本轮由工作代理启动（AVD `Kelivo_Phone_Agent_API_35`）。

### M19 历史状态（2026-11-11）

- 本轮目标：查明上一轮 API35 异常套件中权限弹窗 90 秒未出现的原因，并真实验证权限窗口输入拒绝；只改中文文档与 debug 异常测试，不改产品代码、schema、白名单或上游。
- 最终源码 `modsetHash`：`75429900bf8fc4526fb7005729da565f210eab3d9de922d94039e6399f808d11`；最终合成树：`V:/coding/kelivo-private/.tower/worktrees/wt-19/.build/worktrees/75429900bf8fc452`；`plan`/`apply`/`verify` 通过。设备运行树为 `V:/coding/kelivo-private/.tower/worktrees/wt-19/.build/worktrees/093f372e4d8513e5`；两树仅 `plugin/README.md` 文档副本和未验证标记/skip 文案不同，断言未变，未为文案重跑设备。
- 诊断结论：上一轮 90 秒未出现不是夹具或断言缺陷。设备唤醒时 `am start ... --ez requestPermission true` 会真实拉起 `com.google.android.permissioncontroller/...GrantPermissionsActivity`（`dumpsys window`、uiautomator 树、`dumpsys accessibility` 的 Active Window Id 三方一致）；设备息屏（`mWakefulness=Asleep`）时同一命令 `mCurrentFocus=null`，弹窗不获前台焦点，唤醒后立即出现。`POST_NOTIFICATIONS` 全程 `granted=false` 且无 `USER_SET`，说明从未被回答；夹具只在未授予时请求，因此“已允许导致无弹窗”不成立。
- 真实结果：弹窗出现，但 `PhoneAgentService.rootInActiveWindow` 在弹窗期间为 null，读树实测返回 `type=tool_error`、`error=no_window`，不会产生文档契约中的 `system_window_denied`。输入 `no_window` 是代码路径推导而非本轮直接设备调用：`currentWindow()` 在空 root 时返回 null，输入在包名策略与执行器之前以 `no_window` 拒绝；本套件在 `permissionTree == null` 时只读树并打印诊断，未执行 tap/back。输入仍被拒绝，没有执行手势，权限未授予。测试打印 `PHONE_AGENT_PERMISSION_TREE: package=null type=tool_error error=no_window`（45 秒 + 60 秒重试窗口内稳定复现）。
- 本轮完整异常套件（`093f372e4d8513e5` 树，`flutter test integration_test/phone_agent_exception_test.dart -d emulator-5554`）：**`+5 ~1`，`All tests passed!`，EXIT=0**。通过：FLAG_SECURE、旋转、home/recents、锁屏、服务禁用/中断/重启（`PHONE_AGENT_SERVICE_PENDING_BATCH: size=1000 elapsed=1112ms codes=interrupted,ok`）；跳过：权限窗口（真实弹窗出现，读树实测 `no_window`；输入按 `currentWindow` guard 推导为 `no_window`，本套件未执行 tap/back；`system_window_denied` 未产生）。M22 已取消该 skip，见本节上方。
- 自动检查：Loader `dart format`/`dart analyze` 通过、Loader 165 通过、`verify` 通过；合成树 `dart analyze --fatal-infos lib test integration_test tool` 在 `flutter pub get --directory tool/l10n --enforce-lockfile` 后 `No issues found!`；插件 Dart 17 项、Phone Agent Flutter 108 项通过。

### M17 历史状态（2026-11-11）

- 本轮目标：为 `stale_handle` 增加可区分诊断（`refresh_failed`/`not_visible`/`not_enabled`），不放宽 refresh/可见/可用校验，不改变错误码、指纹契约或 TTL/窗口校验；只做可区分诊断和有限复现，不宣称根因修复。
- 代码：`ObservationRegistry.handle()` 把合并前置条件拆成 refresh → visible → enabled 三个顺序判断，统一 `targetChanged(detail)`；指纹分支消息格式不变。`ObservationRegistryTest` 新增三项精确用例，断言错误码、对应标识、无节点文本、无其它标识；refresh 用例同时验证短路优先级。
- 最终源码 `modsetHash`：`1c1920e0e2b8bc7c397b02e2e908e59d27f979a5ddee3b263da348aa3c1ceaf3`；最终合成树：`V:/coding/kelivo-private/.tower/worktrees/wt-17/.build/worktrees/1c1920e0e2b8bc7c`；`plan`/`apply`/`verify` 通过。设备测试树为 `V:/coding/kelivo-private/.tower/worktrees/wt-17/.build/worktrees/8fe847cedc2ea513`，两树仅 `plugin/README.md` 文档副本不同，代码/测试一致。
- 自动检查：Loader format/analyze 通过、Loader 165、插件 Kotlin 66（含三项新诊断）、插件 Dart 17、根项目 `dart analyze --fatal-infos`、Flutter 182 通过。根分析前必须先跑 `flutter pub get --directory tool/l10n --enforce-lockfile`，否则 `tool/l10n/validate.dart` 会因缺 `flutter_tools` 包解析报 15 个既有错误。
- 当前产品 debug APK（在最终树 `V:/coding/kelivo-private/.tower/worktrees/wt-17/.build/worktrees/1c1920e0e2b8bc7c` 显式 `flutter build apk --debug` 生成）：**181,373,530 字节**，SHA-256 `dc32c4a30533c4195f0392f5533a316bbf096177b653f0623c78645d5f116026`；debug merged manifest 含 `SecureWindowFixtureActivity`，release merged manifest 不含该夹具（不宣称签名 release）。设备测试树 `8fe847...` 的 clean APK 为 181,373,066 字节 / `d7138f06...`，仅作设备证据；两树代码/测试一致，仅 `plugin/README.md` 文档副本不同。测试后仅增量构建曾复用约 249 MB 测试入口 APK，已用 clean 构建排除。
- 设备：MIUI `1960cd68` 同一官方 `phone_agent_test.dart` 连续 4 轮均为 `+2`、`All tests passed!`、EXIT=0，未出现 `stale_handle`，也未触发新诊断标识。每轮 `adb devices -l` 重查；安装会清除组件，宿主 watcher 只恢复 Phone Agent 组件；轮末恢复当轮真实原值（组件 + `accessibility_enabled=1`）。第 1 轮设备自动息屏导致约 3 分钟停顿，唤醒后继续并通过，不是测试失败。
- 结论边界：4 轮未复现不等于根因修复；`refresh_failed`/`not_visible`/`not_enabled` 目前只有 JVM 单元测试覆盖，设备未触发；历史 `No current tree observation` 与 `The target node changed` 仍是未确认根因。
- 未验证：权限窗口、原生超时、签名 release、`stale_handle` 根因；物理设备未运行锁屏、home/recents、服务中断；`llama-cpp/llama-cpp` 的物理完整坐标 swipe 未完成。API35 emulator-5554 本轮不在线，未运行。

### M16 历史状态（2026-11-11）

- 本轮目标：把物理 MIUI API31 真机（Redmi K30 5G，`1960cd68`）的验收结果写入中文文档；只改 `AGENTS.md`、`docs/phone-agent-plan.md`、本文件、`mods/phone_agent/README.md` 和 `mods/phone_agent/plugin/README.md`，不改产品代码、测试、`mod.json`、schema、白名单或上游。
- 最终源码 `modsetHash`：`3d3cd25b4def35633dcf848373037cbe2c5200f795339c315b3ac9c3268a3174`；合成树：`V:/coding/kelivo-private/.tower/worktrees/wt-16/.build/worktrees/3d3cd25b4def3563`；`plan`/`apply`/`verify` 通过。
- 产品 debug APK（在该新树显式 `flutter build apk --debug` 生成，未在该树随后运行 integration_test）：**181,369,890 字节**，SHA-256 `c6f20d250239bae223a4fdaa5ff1807ba34eab38bd8f9e7f9710e8c21747a58b`；debug merged manifest 含 `SecureWindowFixtureActivity`，release merged manifest 不含该夹具（不宣称签名 release）。
- 设备证据来自此前相同代码/测试行为，未在新树重跑设备；新树只包含文档变化。
- 物理 MIUI API31 已通过：独立测试包安装与服务 enabled && connected、Mods 三态选择、真实截图/读树/节点输入/滚动、物理 `FLAG_SECURE`（成功黑图，清除后恢复）、旋转失效（`stale_handle` / `stale_observation`）、`llama-cpp/llama-cpp` 的坐标 tap 真实打开抽屉/Settings/Search 与 `set_text Phone`、magpie `mistral/deepseek-v4-1-flash-1017` 的真实图片请求、坐标 swipe 前后 PNG 证实 Sponsor 可见、像素专属视觉确认（`bright cyan` + `PHONE_AGENT_SECURE_FIXTURE`，与 PNG rgb(0,200,255) 一致）。
- 官方测试间歇性：同一最终树、同一命令两次结果不同，第一次 `+1 -1`、EXIT=1（聚焦后 `set_text` 返回 `stale_handle`，`The target node changed`，属 `ObservationRegistry` 的 refresh/isVisibleToUser/isEnabled 前置分支，不是旧聚焦指纹路径），第二次 `+2`、EXIT=0。根因未确认、未修复，需要后续诊断与统计，不能写成稳定通过。
- 授权例外：用户明确授权仅在该 MIUI 测试设备上用 `settings put secure` 预配置 Phone Agent；M16 历史轮原始 `enabled_accessibility_services` 为空串、`accessibility_enabled=0`，每轮结束恢复。该例外不改变产品自动授权边界，其他设备默认仍禁止自动写系统授权。
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

第一阶段 Mod Loader 已完成。第二阶段 Phone Agent 的主要功能已完成。M22 按用户同意完成权限弹窗保守收尾：不可识别权限弹窗仍返回 `no_window`，错误消息只做条件式人工提示；M20（窗口 root）与 M21（事件来源包名）均已在 API35 设备上证伪并 abandoned，未合并生产代码；可取得系统包名的窗口仍返回 `system_window_denied`。M23 按 M18 设计实现首版前台可视化叠加层（独立 `TYPE_ACCESSIBILITY_OVERLAY`，无设置开关）。

本轮（M23）已完成：

1. 先更新中文契约（`AGENTS.md`、`docs/phone-agent-plan.md`、本文件、两个 README），写入 2.6 节和 9.3.7 测试矩阵。
2. 新增 `OverlayVisuals.kt`（纯 JVM：事件、几何、状态机、截图隐藏握手）和 `PhoneAgentOverlay.kt`（窗口、无文本图形、主线程生命周期）。
3. 接入 `PhoneAgentService`（读树/截图观察、密码窗口过滤、生命周期清理）、`NodeActionExecutor`（只在系统接受动作后显示）、`ScreenshotCapture`（截图前隐藏并等两帧，失败关闭）。
4. 新增 `OverlayVisualsTest.kt` 并扩展 `NodeActionExecutorTest.kt`；官方和异常集成测试增加叠加层宿主标记与截图纯净性断言。

本轮（M22，历史）已完成：

1. 先更新中文契约（`AGENTS.md`、`docs/phone-agent-plan.md`、本文件、两个 README），整合 M20/M21 的准确设备证据。
2. `PhoneAgentService` 三处无可访问窗口改用同一 helper，错误码保持 `no_window`，消息改为条件式人工提示；未添加事件跟踪、包名识别、截屏绕过或运行时回退。
3. 异常测试删除 `root=null` skip；宿主 `dumpsys` 确认真实 `GrantPermissionsActivity` 后直接 tap/back/截图断言 `no_window` + 提示，back 后仍 `no_window`，通知权限仍 `granted=false`。
4. API35 官方 `+2`、完整异常 `+6`，均 EXIT=0；Loader/静态分析/插件/Flutter 测试通过；API29 不在线未运行。

当前剩余：

1. 可视化叠加层的设备验收结果与产品 APK 记录见计划 9.3.7 和本文件第 3 节；未验证项不得写成通过。
2. 物理设备未运行锁屏、home/recents、服务中断和权限弹窗；不能从 API35 模拟器结果推断。
3. 原生截图/手势/通道/worker 排队超时未设备验证。
4. 带合法签名配置的 release 构建。
5. `stale_handle` 根因仍未确认；M17 4 轮未复现，新诊断标识未在设备触发，不能据此宣称修复。
6. `llama-cpp/llama-cpp` 的物理完整坐标 swipe 未完成（网关故障）。
7. 上游可触摸后台胶囊无法被 Mod 隐藏；开启胶囊时截图可能含胶囊、坐标手势可能被拦截，不宣称兼容。

首版输入仍只开放给测试包名 `com.psyche.kelivo.phoneagent`。**M27 已实现应用边界第 1 步（硬基线 + `WindowState.windowType`），M28/M30 完成第 2 步（观察边界）的代码与设备回归；第 3–5 步（用户白名单与签名、批准交互、审计）以及 M32 修订的批准契约（批准 = 读＋操作一体、`QUERY_ALL_PACKAGES` 应用身份、批准后恢复与任务控制、结果未知语义、多窗口不支持、终态与防自我批准、首次隐私确认）全部未实现**，下一阶段入口见第 8 节；在实现落地前，不要扩大白名单、引入自动无障碍授权，或把发送/购买/删除确认描述成原生硬护栏。

## 3. 已有实现与交付基线

- 上游基线：`73afa4ec77cfc9af2efea2487fee8bba1362639d`。
- 当前 Mod 版本：`0.2.0`。
- M23 历史设备运行树：`V:/coding/kelivo-private/.tower/worktrees/wt-23/.build/worktrees/9ebf2e991caa07ed`（`modsetHash` `9ebf2e991caa07ed3e8e5b4484649de84139e89a31ac8837f779ca34aa2d8c66`）。
- M23 历史最终源码树：`V:/coding/kelivo-private/.tower/worktrees/wt-23/.build/worktrees/dfcef53cfd77ea78`（`modsetHash` `dfcef53cfd77ea78fe898710efa92991fa15a140b8d0424193279f7ad21aac77`），与设备运行树仅 `plugin/README.md` 文档副本不同，代码/测试语义一致；`plan`/`apply`/`verify` 通过。产品 APK 在最终树 `dfcef53c` 于全部设备测试后构建（`a460dcbc` 仅作 round-4 设备测试构建树，其产品 APK 已被 17:29/17:32 integration_test 覆盖为 251,120,349 / `e3d9d22b…` 测试入口构建）。
- M23 历史产品 debug APK（最终树 `dfcef53cfd77ea78`，全部设备测试后 `flutter clean` + 显式 `flutter build apk --debug`，构建后未再运行 integration_test）：**181,403,054 字节**，SHA-256 `501d4a0087294258baa882e9a32856208805fcba88228ec34e15016ae89689fb`；debug merged manifest 含 `SecureWindowFixtureActivity`（1 处），release merged manifest 不含该夹具（0 处）且含 `PhoneAgentService`（1 处，不宣称签名 release）。历史：此前 181,402,630 / `a72cac9b…` 在 `a460dcbc` 构建，随后被 17:29/17:32 的 integration_test 覆盖为 251,120,349 / `e3d9d22b…` 测试入口构建，不能作为产品；`b56fc97d` 的 181,403,426 / `f40b76cf…` 是不同 artifact，未采用。设备运行树 `9ebf2e99` 的 `app-debug.apk` 是测试入口构建，只作设备/测试证据，不作为产品。round-2/3 的「产品 APK 未生成」仅为历史，不代表当前。以上三条均为 M23 历史；M24 当前产品 APK 见 §0 与 `docs/phone-agent-plan.md` 9.3.2.1（最终树 `29861376ffaa5e41`，181,403,918 字节 / `5a54cb3a…`）。
- 三个工具：`phone_agent_screenshot`、`phone_agent_tree`、`phone_agent_input`。
- 每助手独立 `localToolId='phone_agent'`；Mods 页提供关闭/原生手机控制/Phone Agent 三态单选，已有助手不自动迁移。
- 观察按需发生，不强制每步重新读取完整树；工具 schema 不暴露 `snapshot_id`。
- `supported` 只表示 API 30+ 截图能力；API 29 仍可 ready 并使用树/节点输入。

本轮 M22 已通过的检查：

- `dart run tool/mod_loader.dart plan`：`modsetHash` 与最终树一致；`apply` 新建合成树；`verify` 校验通过。
- Loader `dart format --output=none --set-exit-if-changed tool test`、`dart analyze tool test`、`dart test`（165 项）通过。
- 合成树 `flutter pub get`、`flutter pub get --directory tool/l10n --enforce-lockfile` 通过；`dart analyze --fatal-infos lib test integration_test tool` 输出 `No issues found!`。
- 根项目 seam 测试 56 通过；插件 Dart 17、插件 Kotlin 66 通过。
- 设备：API35 `emulator-5554` 官方 `phone_agent_test.dart` `+2`、EXIT=0；完整异常套件 `+6`、`All tests passed!`、EXIT=0；权限场景宿主 `dumpsys` 确认 `GrantPermissionsActivity`，测试打印 `PHONE_AGENT_PERMISSION_TREE: package=null type=tool_error error=no_window`，tap/截图/back 均 `no_window` + 条件式提示，back 后仍 `no_window`，`POST_NOTIFICATIONS` 仍 `granted=false`；服务禁用批次 `size=1000 elapsed=670ms codes=interrupted,ok`。
- 构建环境备注：Kotlin 增量缓存跨盘仍会打印 `Could not close incremental caches ... different roots` / `Daemon compilation failed: null`，Gradle 回退后构建成功；这是缓存问题，不是产品缺陷。
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
- 授权例外：用户明确授权仅在该设备用 `settings put secure` 预配置 Phone Agent；M16 历史轮原始 `enabled_accessibility_services` 为空串、`accessibility_enabled=0`，每轮结束恢复。该例外不改变产品自动授权边界。
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

该轮只改中文文档，未新增或修改测试；该标签仅适用于该历史 VLM 文档轮，不代表当前 M17（M10 历史轮已新增并运行异常/聚焦测试）。以下为上一轮新增的测试，保留作回归说明。

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
- 默认不要用 `settings put secure` 写入授权绕过系统确认。唯一例外：用户已明确授权在物理 MIUI 测试设备 `1960cd68` 上用 `settings put secure` 预配置 Phone Agent，仅限该设备与 Phone Agent；必须保存并恢复**当轮真实原始值**，不能按历史记录强制写成空串+0。M16 历史轮原值为空串+0，M17 轮原值为 Phone Agent 组件 + `accessibility_enabled=1`。该例外不是产品能力，也不适用于其他设备。
- 物理设备测试期间保持屏幕常亮（`adb shell svc power stayon true`），并在 watcher 中检查 `mWakefulness`，避免自动息屏让测试停顿；测试结束恢复 `svc power stayon false`。M17 第 1 轮曾因息屏停顿约 3 分钟，唤醒后继续并通过，不是测试失败。

### 本地 VLM 环境（测试经验，不是产品依赖）

- 物理 MIUI 本轮指定模型：magpie 的 `mistral/deepseek-v4-1-flash-1017`（不是 0731）；magpie 侧未标图片输入，需在 Kelivo 手动勾选图片，真实请求全部 200。模型能力标注可能变化，每次都要实测。
- 历史环境：magpie 网关的 `llama-cpp/llama-cpp`，应用内 provider 地址 `http://10.0.2.2:3425/v1`，UI 勾选 Image 输入和 Tools；局域网访问由用户开启，密钥未修改、未读取、未记录。
- 补充环境（历史）：LM Studio `prism-ml/bonsai-27b`，identifier `bonsai-vlm`，建议 `-c 8192`，模拟器地址 `http://10.0.2.2:1234/v1`；该结果不能取代 magpie 模型结论。
- 应用内模型需同时勾选 Image 输入和 Tools 能力，否则 Mod 不激活或截图工具不暴露。
- 测试结束后停止本地网关/LM Studio、卸载模型；设备上的 provider 和测试会话是测试状态，不是仓库交付物。

### Windows 环境

- Flutter 全局使用 JDK 17：`flutter config --jdk-dir="C:/Users/David/scoop/apps/openjdk17/current"`；不要切回 JDK 25。
- 私有仓 `core.autocrlf=true`，Tower 创建的 worktree 会以 CRLF 检出全部文件，导致 Loader 补丁无法应用、`dart format` 失败。处理方式（M19 实践）：在该 worktree 内执行 `git config core.autocrlf false`（仅 worktree 本地，不修改全局或上游配置），再用 `git ls-files --eol | grep 'w/crlf'` 列出 CRLF 文件并逐个 `sed -i 's/\r$//'` 就地转 LF。转换后 `git status` 会把大量文件标为 M（stat 噪声），但 `git diff --name-only` 只显示真实改动。未转 LF 时 `plan` 的 `modsetHash` 也会因 CRLF 字节不同而偏差；比对哈希前先转 LF。
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
6. 修改产品代码或插件后重新构建 APK 并计算大小与 SHA-256；不要沿用旧哈希。只改文档时仍要显式 `flutter build apk --debug` 生成当前产品 APK，因为 `flutter test` 会把树内 `app-debug.apk` 覆盖为测试入口构建；产品构建后不要在同一树运行 integration_test 而不重建。若测试后增量构建仍得到约 249 MB 的测试入口 APK，必须 `flutter clean` 后重新 `flutter pub get`、`flutter pub get --directory tool/l10n --enforce-lockfile` 和 `flutter build apk --debug`，以约 181 MB 的产品大小和 manifest 复核。
7. 更新中文验收记录和本交接文档，如实写明未验证项。

仍未完成或不能宣称完成：签名 release、原生超时、`stale_handle` 根因；权限弹窗的保守拒绝只在 API35 模拟器验证（`no_window` + 条件式提示，未执行手势/系统导航），物理设备和其他 Android 版本未验证；物理设备未运行锁屏、home/recents、服务中断和权限弹窗，不能从 API35 模拟器结果推断；`llama-cpp/llama-cpp` 的物理完整坐标 swipe 未完成。物理 MIUI API31 已验证真实截图/读树/节点输入/滚动、物理 `FLAG_SECURE`、旋转，以及 `mistral/deepseek-v4-1-flash-1017` 的真实图片请求、坐标 swipe 的 UI 效果和像素专属视觉确认。API35 模拟器已验证 secure 截图行为、旋转、home/recents、锁屏、服务禁用/重启和权限弹窗保守拒绝；跨新用户轮次历史图片回放已在 API 35 模拟器通过。只验证 magpie `llama-cpp/llama-cpp`、`mistral/deepseek-v4-1-flash-1017` 与这些设备，不承诺任意模型。上游仓保持只读；不向上游提交或推送私有实现。

## 8. 下一阶段入口：实现应用边界与应用授权

契约全文见 `docs/phone-agent-plan.md` 7.5 与 7.6；`AGENTS.md` 有对应条目；用户可读说明见 `mods/phone_agent/README.md`「构建期白名单与预批准条目」与「应用白名单与批准（门控已实现，界面未实现）」。**第 1 步（硬基线 + `WindowState.windowType`）已完成**（代码 + JVM 测试 + 两台设备官方测试，见第 0 节与下方第 1 条）；**第 2 步（观察边界）已完成并补齐设备回归**；**第 3 步（用户白名单与签名绑定）已由 M33 实现，只有单元与静态检查证据**；**第 8 步（审计）已由 M35 实现，只有单元与静态检查证据、没有读取界面**；**第 4–7 步（批准交互、隐私确认、任务控制、结果未知语义）尚未实现**。

**M32（2026-11-15，仅文档）修订了第 3 步及之后的契约，实现时必须按新契约、不要按旧文字：**

- **批准 = 读＋操作一体（M33 已实现）**：未批准第三方应用的 `readTree`/`screenshot` 只返回应用身份（包名、签名 SHA-256 前 8 位、可选显示名）与 `permission_required`，不返回树节点、截图或界面内容；硬基线与窗口类型仍排在白名单之前，`no_window`/`device_locked` 优先级不变。旧理由「模型必须先看到内容才能解释」已作废。
- **已定（用户拍板）**：`QUERY_ALL_PACKAGES` 一次声明（M33 已实现）；未批准只返回身份与授权请求（M33 已实现）；方案 B 首次隐私确认（只在首次提示，不每张截图询问；**未实现**）。
- **已定契约（早期设计，非本轮用户拍板；M33 已实现）**：`(包名, 签名证书 SHA-256 集合)` 双匹配、同签名更新保留授权、签名变化或无法解析 → 重新批准、授权不随聊天备份迁移、应用分身/工作资料首版不支持。
- **已定（M32，tower 定论，用户可推翻；M33 已实现）**：观察侧**也判**构建期 `package_not_allowed`，排在用户白名单之前（理由：本构建无法操作的应用不应产生批准提示）。该码适用范围因此是**输入与观察**；推翻时须连带收回该层与 6.6/7.5.8/AGENTS/README 的适用范围表述。
- **构建期范围已转为 deny 清单（已定（M32，tower 定论，用户可推翻）；M33 已实现）**：`package_not_allowed` 只对 deny 成员出现，其余第三方应用走用户白名单、未批准返回 `permission_required`。**deny 清单成员尚未定稿**（设计提案，M33 实现为**空集合**，并以 JVM 断言固定“不与硬基线重叠”）。推翻时须恢复 allowlist 语义并同步改写 7.5.8/10.1/10.2/AGENTS/README 的「未批准 → `permission_required`」表述与 P6 完成条件。
- **设计提案（tower 建议、待实现），不是用户拍板项**：批准后「允许并继续」只恢复关联且仍可恢复的任务、恢复后先重新观察不重放动作；同时只一个任务控制手机、停止/撤销后未执行请求失效、已派发手势不承诺撤回；结果未知语义（不盲目重试、重新观察、区分动作完成与业务成功）；截图与手势范围与获准目标一致；批准终态校验与防自我批准。用户只给过方向性约束「如果每次都需要用户回到Kelivo操作，那摩擦就太大了」，不是对这些机制的决策。
- 已定决策不重开：白名单全局共享、批准长期有效 + Mods 页撤销、审计元数据 30 天/2000 条、systemui 等系统应用硬禁止、不用叠加层做批准界面、聊天卡片 + 通知两入口。
- **仍未定论（写代码前必须先在文档定论）**：多窗口是拒绝还是仅不承诺（10.1/10.2 已按「首版不支持、拒绝方式未定稿」表述）；任务控制冲突是否新增错误码；provider 更换是否重新提示隐私确认。
- **两项实现前提（✅ M33 已实现）**：(a) 构建期测试包 `com.psyche.kelivo.phoneagent` 作为**构建配置的预批准条目**（不写用户白名单、不产生批准提示、不影响其他应用的可达性）；(b) 跨 UID `securefixture` 夹具包**只在 debuggable 构建**预批准（release 不预批准，避免同名第三方包被静默放行）。另外 home/recents 用例的读树成功分支前提已改变（launcher 属第三方、非 deny 成员、未批准，返回 `permission_required` 而非 `package_not_allowed`），helper 接受集合已同步。

实现时按以下顺序，前一步不稳定不要开始后一步：

1. **硬基线集合 + `WindowState.windowType` —— ✅ M27 已完成（代码 + JVM 测试 + 两台设备官方测试）**。落地位置改为新增 `AppBoundary.kt`（原计划未指定文件）：`WindowType`、`HARD_BASELINE_PACKAGES`、`KELIVO_PACKAGE`/`TEST_PACKAGE`、`RoleHolders`、纯函数 `PackagePolicy`。settings 及厂商变体补进静态集合；Kelivo 自身按精确包名判定；电话/短信持有者改用 **公共等价接口** `TelecomManager.defaultDialerPackage` + `Telephony.Sms.getDefaultSmsPackage`（`RoleManager.getRoleHolders` 是 @SystemApi，公共 SDK 编译不过，实测 `Unresolved reference`），查询异常才视为解析失败。`WindowState` 已加 `windowType`，在 `windowState()` 内按 `windowId` 从 `windows` 匹配（同一次读取），解析失败落到 `UNKNOWN` 即拒绝；`sameWindow()`、截图观测、`TreeObservation`、`CapturedScreenshot` 已同步。`PackagePolicyTest` 原 5 条错误码断言未改，只加参数。设备回归已在 API35（`emulator-5554`）与物理 MIUI（`1960cd68`）各跑官方 `phone_agent_test.dart`，均 `+2`、EXIT=0、全程无 `stale_*`（详见第 0 节）。**待办：完整异常套件（旋转/锁屏/服务禁用重启/权限窗口/叠加层）未跑，那是窗口类型抖动最容易出现的地方。**
2. **观察边界 —— ✅ M30 已补齐设备回归（API35 异常套件 3 棵树 / 4 轮 `+8`、EXIT=0；API35 与物理 MIUI 官方测试均 `+2`、EXIT=0），但服务重启清树机制不可独立归因（见下方「证明边界」）**。`PackagePolicy.requireObservable(packageName, windowType)`（`AppBoundary.kt`）判定顺序 `no_window` → 静态硬基线 → 观察窗口类型（`{APPLICATION, INPUT_METHOD}`），**当前代码不判用户白名单、不查询角色**（M32 契约将加入白名单门控，未实现）；接入点是 `readTree`（仅 `offset == 0`）与 `captureScreenshot`（取前台 `WindowState` → 边界 → `collectPasswordBounds` 全窗口遍历 → 截图，三段独立）。异常套件 5 处已同批改为宿主 `dumpsys` 确认 + 产品错误码/观察标识断言。**M28 当时异常套件从未取得绿色整轮**：`exc5`(e2d50da0)=`+1 -1`、`exc6`(c3c760c0)=`+1 -7`、`exc7`=`+2 -6`、`exc8`=`+2 -6`、`exc9`(最终)=`+1 -7`；`exc8`/`exc9` 的失败句是 `最后前台包名：未知`，日志未记录 `error`。

   **M30 结论（详见 plan 9.3.0.1–9.3.0.3）**：`未知` 的成因已定位为**测试诊断缺陷 + 宿主驱动缺陷**，不是产品缺陷——`_waitForTreeText` 的失败句只拼包名、`_tryTree` 把拒绝与异常都折叠成 `null`；`run1.log` 用新增的 `_TreeProbe` 记录到该轮 102 条探测为 `system_window_denied (com.android.systemui, hard_baseline)`（其中单次探测内连续 77 次），前台确实是通知栏。驱动另有 5 个缺陷已逐个修掉（通知栏固定 13 秒循环无法取消、服务授权后不回应用、`HOME`/`RECENTS` 信息标记占用有序动作队列、设置页在重启后残留前台、前台确认过慢），以及一处**误发 BACK 导致 `MainActivity` 被 finish**、任务重启后产品一度无法解析窗口类型（该轮 logcat 观察到 `windowType exhausted ...` 与任务 CLOSE 过渡，**原文未留存**；可核对旁证是 `run9.log` 内 `window_type_unknown` 30 次、`run5.log` 0 次）。修正后该标识为 0–1 次（`run19` 有 1 次瞬态），并非恒为 0。

   **设备结果**：API35（`emulator-5554`）异常套件***3 棵树 / 4 轮* `+8`、`All tests passed!`、EXIT=0**（`run17.log` 477s、`run18.log` 490s 在 `f26c1c7ed3238610`；`run19.log` 721s 在 `b9ed56f89b3146c9`；`run20.log` 574s 在 `8a44ec55a023185e`（返工前测试树）），8 个用例逐条通过并有原始证据。可复现基线是 `run17`/`run18`（同树同文件）与 `run20`（`8a44ec55a023185e`）；`b9ed56f89b3146c9` **不能作 run19 的基线**——该树测试文件在 run19 结束后被就地改写为 LF，磁盘现状不代表 run19 的输入。API35 官方 `phone_agent_test.dart` **`+2`、EXIT=0**（`official_api35.log` 与 `8a44ec55a023185e` 上的 `official_lf.log` 各一次）；物理 MIUI（`1960cd68`）官方 **`+2`、EXIT=0**（`official_miui.log`，107s；此前「有通过迹象、无留存日志」已补齐）。MIUI 异常套件**未运行**：该设备未安装 `com.kelivo.phoneagent.securefixture`，属设备准备缺口。

   **证明边界（必读）**：上面那个「服务禁用中断与重新启用恢复」是**组合用例**，其最终 `stale_handle / No current tree observation` 与三种机制完全兼容——① 用例自己发的分页请求在宿主进入设置页后即 `clearTreeLocked()`（`ObservationRegistry.kt:213-225`）；② `DEFAULT_TTL_MILLIS = 120_000` 自然过期；③ 服务中断的 `invalidateAll()`。因此只能断言「禁用与中断行为已验证、重启后旧句柄不可用已验证」，**清树机制不可独立归因**；窗口 id 变化同样无法排除。要独立证明需拆成带 ACK 握手的独立子场景（M31 survey 已给设计），属另一 mission。复跑绿色轮次依赖 `mods/phone_agent/host/` 下的宿主脚本。**`exc5` 归因**：`screenshot_required` 与 `stale_observation` 是 `requireScreenshot` 的两个确定性分支（槽位为 null vs 槽位存在但窗口/TTL 变化），语义不同、优先级由 if 顺序固定，不是优先级缺陷，期望值也没有过期。槽位为 null 的**可能来源**（代码确认存在）是 `ensureUnlocked()` 的 `invalidateAll()`、`interruptPending()` 的 `invalidateAll()`、或任意节点动作后的 `clearScreenshot()`。**`exc5` 当轮具体是哪一条没有留存证据**；同树一次通过一次失败**不足以排除竞态回归**，因此记录为「错误码语义已查清，当轮触发来源未定性」。

   **R1 返工后最终交付树 `474262a402cca985`**（`modsetHash` `474262a402cca985f216636ac8dbd0b8af9ffd31507acb7feb1614a103853fac`，`plan`/`apply`/`verify` 通过）：返工只改文档、测试文案与新增宿主脚本 `mods/phone_agent/host/`，**未重跑设备**；设备结果对应返工前测试文件，测试侧改动都是收窄或文案修正（排除 `window_type_unknown`、消除启用双触发），不放宽任何断言。

   **产品 debug APK（当前产品，未改动）**：最终树 `f26c1c7ed3238610`（`modsetHash` `f26c1c7ed32386105a763feeb3ea95accdd127b6041941b9f3d75f83abadafa9`），**181,410,150 字节**，SHA-256 `a6c2e51b73435af1de4f74d5e95807a9688e95cb3d78be2f47521d715971b70f`（M30 已复核未变）。M30 未改产品代码，因此未重建；integration_test 入口构建只在测试树内，不作为产品。
3. **应用身份与签名校验 —— ✅ M33 已实现（无设备证据）**。插件 manifest 一次声明 `QUERY_ALL_PACKAGES`；实现用 `PackageManager.getPackageInfo(pkg, GET_SIGNING_CERTIFICATES)`（API < 28 回退 `GET_SIGNATURES`）解析前台包签名，`(包名, 签名证书 SHA-256 集合)` 双匹配，未命中（含签名变化、签名解析失败）返回 `permission_required`。多签名包要求整集合相等（M29 实测 `com.android.vending` 2 枚）。同签名更新保留授权；授权不随聊天备份迁移（`noBackupFilesDir`）；应用分身与工作资料首版不支持。**签名解析能力仍需设备实测**（见 7.6 风险 5），不得先写成“任意前台包都能解析”。
4. **白名单门控接入观察与输入 —— ✅ M33 已实现（无设备证据）**。观察路径顺序 `device_locked` → `no_window` → 硬基线 → 窗口类型 → 构建期 deny 清单 → 用户白名单；未批准时结果只含应用身份，不建立观测、不占 `treeBudget`、不截图。**分页 `offset > 0` 沿用 M28 接入点不重复判定**（M32 曾把“分页也判定”列为未定稿设计提案），因此未批准时翻页返回 `stale_observation`；若后续改成分页也判定，须同时改 plan 7.5.4 与 JVM 断言。异常套件 home/recents 与跨 UID `securefixture` 相关断言已按新错误码同步（不是放宽）；settings 断言走硬基线、未改。
5. **批准交互与终态（两入口方向为已定（用户拍板）；终态机制为设计提案。未实现）**。先做聊天内卡片（复用 `ToolApprovalService` 的请求结构、pending 存储与 `notifyListeners()` 刷新，**不复用其等待语义**——工具调用已返回 `permission_required`，卡片须自带 TTL 与“任一端批准即置终态”的收敛），再做通知栏（必须新增通知 action + `BroadcastReceiver`，现有 `NotificationService` 只有点击打开会话）。同批实现单终态、请求 id 幂等、迟到回调不写白名单、写入前重新解析签名（7.5.13）。
6. **首次启用隐私确认（方案 B，已定（用户拍板），未实现）**。只在首次启用时一次性提示截图与界面文字会发往用户配置的 provider；不每张截图询问。文案进 ARB。provider 更换是否重新提示待定论。
7. **任务控制与恢复、结果未知语义（设计提案（tower 建议、待实现），不是用户拍板项）**。「允许并继续」只恢复关联且仍可恢复的任务、恢复后先重新观察不重放动作；同时只一个任务控制手机，停止/撤销后未执行请求失效，已派发手势不承诺撤回；已派发后的超时/取消属结果未知，不盲目重试、先重新观察、区分动作完成与业务成功。
8. **审计 —— ✅ M35 已实现（无设备证据）**。`AuditLog.kt` 落盘七项元数据（时间戳、助手 id、会话 id、包名、签名哈希前 8 位、动作类型、结果码），滚动保留 30 天或最近 2000 条先到者生效，写在 `noBackupFilesDir/phone_agent_audit.tsv`；助手/会话 id 由通道可选参数从 Dart 侧传入，缺失记 null；审计失败静默计数、不阻断主路径；**没有读取通道也没有界面**，因此也没有任何用户可见的审计视图。字段集合由 JVM 反射断言固定，七类禁内容没有进入记录的路径。

实现后必须重跑并把结果写入 9.3/9.4：API35 官方测试、完整异常套件、物理 MIUI 官方测试，以及至少一轮 VLM 固定任务（含“未批准 → 只回身份 → 批准 → 重新观察 → 撤销 → 重新 `permission_required`”的完整链路）。重跑前，9.4 与 10.1 的 VLM 结果**只能作为旧代码证据**，不得用于宣称新边界已验证。**M33 未跑任何设备**，因此现在能声明的只有“单元与静态检查通过”；官方测试、异常套件与 VLM 都必须重跑才能宣称门控生效。

已定决策不要重新讨论：白名单全局共享、批准长期有效 + Mods 页显式撤销、审计落盘元数据滚动保留、systemui 等系统应用硬禁止、批准 = 读＋操作一体、`QUERY_ALL_PACKAGES` 一次声明、方案 B 首次隐私确认、聊天卡片 + 通知两入口、不用叠加层做批准界面。若实现中发现某项不可行，需要回写文档并请用户确认，不得静默改向。**M32 遗留的三项未定稿仍在（多窗口拒绝方式、任务控制冲突错误码、provider 更换是否重新提示）；观察侧判 `package_not_allowed` 与「构建期范围转 deny 清单」已由 M33 实现；分页门控属 M32 未定稿的设计提案，M33 选择了不重复判定并把选择写进了 plan 7.5.4。**
