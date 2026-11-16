# Kelivo Phone Agent Mod 实施计划

## 0. 文档状态

- 当前阶段：第二阶段验收进行中（UI/选择契约改造已完成），Mod 版本 0.2.0。
- 本轮 M33（白名单门控与签名绑定，2026-11-15，**实现**）：按 M32 契约实现第 2、3 步——插件 manifest 一次声明 `QUERY_ALL_PACKAGES`；新增 `AppWhitelist.kt`（签名身份、白名单存储、批准入口、预批准集合、deny 清单）；`PackagePolicy` 由 allowlist 改为 **deny 清单＋用户白名单**，观察与输入两条路径都判，未批准只回应用身份与 `permission_required`（不建立观测、不占 `treeBudget`、不截图）；通道新增 `approvedApps`/`approveApp`/`revokeApp`（幂等、写入前重解析签名、撤销立即生效、不依赖服务连接）；异常套件 helper 的接受集合同批同步。**不做批准 UI（M34）、审计（M35）、设备验证（M36）**（**审计已由 M35 补齐**，见 7.5.5「M35 实现事实」；本句是 M33 当轮的边界记录，保留不改写历史）。自检：Loader 165、插件 Kotlin 170、插件 Dart 25、合成树 `dart analyze --fatal-infos` 通过；**未构建 APK、未接设备、未跑 integration_test**。
- 本轮 M28（应用边界第 2 步：观察边界，2026-11-13）：基线 tag `phone-agent-m27-boundary-step1`（commit `f799b75`）。按用户要求的提交顺序，**第一个提交只改文档**（本节、7.5.4、7.5.3、7.6 风险 2/3/4/5、`AGENTS.md`、`mods/phone_agent/README.md`），把观察边界写成设计契约；**第二个提交**再提交代码、JVM 测试与异常测试改造。设计要点：新增纯函数 `PackagePolicy.requireObservable(packageName, windowType)`，判定顺序 `no_window` → 静态硬基线（与输入共用同一集合与 Kelivo 精确包名）→ 观察窗口类型 `{APPLICATION, INPUT_METHOD}`，命中返回 `system_window_denied` 并追加固定标识；**不判用户白名单、不查询角色持有者**（角色是输入边界，观察层若也依赖角色解析会在所有设备上随机失败）。接入点为 `PhoneAgentService.readTree()` 与 `captureScreenshot()` 各一次，分页不重复判定；截图顺序固定为取前台 `WindowState` → `requireObservable` → `collectPasswordBounds` 全窗口遍历 → 截图，三段独立，前台被拒时直接失败、不缩窄遮挡遍历。异常套件 5 处依赖同批改为“宿主 `dumpsys` 确认前台 + 测试断言错误码/观察边界标识”。**本提交不含代码、测试或设备结果**；设备结果与 APK 记录在第二个提交后补充到 9.3 的新增小节。
- 本轮 M32（应用批准契约修订，2026-11-15，**仅文档**）：按用户拍板把「批准 = 读＋操作一体」写成契约，**取消「未批准第三方应用也可观察」的旧方向**；未批准应用的 `readTree`/`screenshot` 改为只返回应用身份与 `permission_required` 授权请求，不返回树节点、截图或界面内容。用户本轮拍板原文：「一次声明 QUERY_ALL_PACKAGES（推荐）」「未批准只返回身份与授权请求（推荐）」；此前已定、不重开：systemui 等系统应用禁止、白名单全局共享、批准长期有效 + Mods 页撤销、审计元数据 30 天/2000 条、聊天卡片 + 通知栏两入口、不用叠加层做批准界面、首次隐私确认方案 B。改写 7.5.4（观察边界反向 + 当前实现事实分层），新增 7.5.9–7.5.14（应用身份与签名绑定、批准后的恢复与任务控制、结果未知语义、截图与手势范围与复杂多窗口、批准请求终态与防自我批准、首次启用隐私确认），同步 7.5.1/7.5.2/7.5.5/7.5.7/7.6 风险 5/10.2、`AGENTS.md`、`mods/phone_agent/README.md` 与本文件 §8。**本轮零产品代码、零测试代码、零 `mod.json`**：`modsetHash` 仍为 `474262a402cca985f216636ac8dbd0b8af9ffd31507acb7feb1614a103853fac`，未构建 APK、未接设备。所有新条目按来源分层标「已定（用户拍板）」/「已定（M32，tower 定论，用户可推翻）」/「已定契约（早期设计）」/「设计提案（tower 建议、待实现）」，全部未实现；**当前代码仍是观察不判白名单（M28 事实），不得写成已生效**。R1 返工（review p1-1items / fix-then-merge）已按 tower 定论把「观察侧也判 `package_not_allowed`」定死，并把 6.6/7.5.8 的适用范围改为输入与观察；设计提案部分的标注收窄到用户实际拍板范围之外。
- 上一轮 M27（应用边界第 1 步：硬基线 + `WindowState.windowType`，2026-11-13）：只实现第 1 步，不做观察边界、用户白名单、批准交互和审计。新增 `AppBoundary.kt`（`WindowType`、`HARD_BASELINE_PACKAGES`、`KELIVO_PACKAGE`/`TEST_PACKAGE`、`RoleHolders`、纯函数 `PackagePolicy`）；`WindowState` 加 `windowType`，在 `windowState()` 内按 `windowId` 从 `windows` 匹配，解析失败 fail closed；`sameWindow()`、截图观测、`TreeObservation`、`CapturedScreenshot` 同步。`RoleManager.getRoleHolders` 为 @SystemApi 无法在公共 SDK 编译，改用 `TelecomManager.defaultDialerPackage` + `Telephony.Sms.getDefaultSmsPackage`（差异已写入 7.5.1 与 7.6）。最终合成树 `V:/coding/kelivo-private/.tower/worktrees/wt-27/.build/worktrees/1525e7263f6293d2`，`modsetHash` `1525e7263f6293d29f0775560d4d097e2cb4dd17b55dba31c92486687a555a8f`，`plan`/`apply`/`verify` 通过（前序重算树 `17007461ac82c427`、`eed71ae8a2984e02`、`3403a7239833ec63`、`7a2c1177fbc41351` 只作编译/测试迭代历史，不代表最终代码）；Loader format/analyze 通过、Loader 165、插件 Kotlin **122**（`--rerun-tasks` 强制重跑，0 失败 0 错误；返工后 `PackagePolicyTest` 19 项）、插件 Dart 17 全绿；API35 模拟器（`emulator-5554`）与物理 MIUI API31（`1960cd68`）官方 `phone_agent_test.dart` 各 **`+2`、All tests passed!、EXIT=0**（截图/读树/节点点击/坐标滑动/滚动/聚焦后 `set_text`/二次读树全程无 `stale_*`，即 `sameWindow()` 加 `windowType` 未在两台设备上产生误报）。两台设备的无障碍授权均由宿主编排触摸在系统界面完成（点开 Kelivo Phone Agent → Allow / 「确定（5）」），**未使用 `settings put secure` 写授权**；`flutter test` 每次重装包都会撤销授权，首轮因此在 `setUpAll` 等待超时，授权后才通过。MIUI 轮结束后 `flutter test` 卸载了测试包（`pm list packages` 无 `com.psyche.kelivo.phoneagent`），授权位随之回到 `null`/`0`，不是用 settings 写回的。设备测试在 `1525e7263f6293d2` 树上运行；**R1 返工后**最终源码树为 `V:/coding/kelivo-private/.tower/worktrees/wt-27/.build/worktrees/2f6528a0e4e4c8d6`（`modsetHash` `2f6528a0e4e4c8d69b75b368b0850b599a360893765f841c3250d1b8cc042355`，`plan`/`apply`/`verify` 通过），设备结果来自返工前的树：返工有两处代码改动，需逐项说明设备结果为何仍可沿用。（1）补入 4 个厂商硬基线包名——**这确实改变了可观察行为**：`PackagePolicy` 的硬基线判定排在构建期 allowlist 之前，这 4 个包一旦成为前台窗口，错误码由 `package_not_allowed` **收紧为** `system_window_denied`（消息也换成硬基线文案）。设备结果可沿用的依据是**官方 `phone_agent_test.dart` 全程前台为测试包 `com.psyche.kelivo.phoneagent`，这 4 个包不会在该流程里成为前台**，与“错误码没变”无关。（2）`windowType()` 改为循环结束统一返回——只改回收时机，判定结果等价。据此**未重跑设备**。产品 debug APK 在该最终树上 `flutter clean` + `flutter pub get` + `flutter pub get --directory tool/l10n --enforce-lockfile` + 显式 `flutter build apk --debug` 生成：**181,408,190 字节**，SHA-256 `1c2b50967f2c2be0c432218ace3a3bd25f7ea4a932092e75c06af1fed48c387c`；debug merged manifest 含 `SecureWindowFixtureActivity`（1 处）与 `PhoneAgentService`（1 处），dex 中检出 4 个新增硬基线包名，未构建 release；构建后未再运行 integration_test。返工前的 181,407,582 / `5b706dd5…` 只作历史。**未跑 Flutter 根项目静态分析/上游 seam 回归与异常套件**。`sameWindow()` 加 `windowType` 是否会在其他场景误报仍属未验证假设（`sameWindow()` 比较是精确相等，只有窗口类型真的变化才失效）。**观察边界、用户白名单、签名校验、`permission_required`、批准交互与审计仍为零实现。**
- 上一轮 M26（应用边界与授权契约文档，2026-11-13）：只改中文文档，不改代码、测试、`mod.json`、白名单或上游。新增 7.5「应用边界与应用授权（设计提案）」与 7.6「实现前置风险与行为变更」，写入用户已定的三项决策（白名单全局共享、批准长期有效 + Mods 页显式撤销、审计落盘元数据滚动保留 30 天或 2000 条）、`permission_required` 契约和批准交互口径；同步更新 `AGENTS.md`、`mods/phone_agent/README.md` 与 `docs/next-session-handoff.md`。**M26 当时该设计尚未实现**（M27 随后实现了第 1 步）：M26 结束时代码是输入只允许 `com.psyche.kelivo.phoneagent`、读树与截图不检查包名或窗口类型；M26 本轮未运行测试、未构建 APK、未接设备，未产生新 `modsetHash` 或 APK 记录。
- 上一轮 M23（前台可视化叠加层，2026-11-12，历史；M24 当前状态见 9.3.2.1）：独立 `TYPE_ACCESSIBILITY_OVERLAY` 叠加层已实现并接入读树、截图、节点/手势/系统动作；reviewer round 1 的 6 项 findings、round 2 的窗口重校验/附件 fail-closed/代次窄窗口、round 3 的 `onSuccess` 回调窗口重校验和文档/JVM 矩阵修正已处理。round-4 设备运行树 `V:/coding/kelivo-private/.tower/worktrees/wt-23/.build/worktrees/9ebf2e991caa07ed`（`modsetHash` `9ebf2e991caa07ed3e8e5b4484649de84139e89a31ac8837f779ca34aa2d8c66`），最终源码树 `V:/coding/kelivo-private/.tower/worktrees/wt-23/.build/worktrees/dfcef53cfd77ea78`（`modsetHash` `dfcef53cfd77ea78fe898710efa92991fa15a140b8d0424193279f7ad21aac77`），与设备树仅 `plugin/README.md` 文档副本不同，`plan`/`verify` 通过：API35 独立 AVD `Kelivo_M23_API_35` 完整异常套件 **`+8`、`All tests passed!`、EXIT=0**（含旋转、锁屏、服务禁用/重启、权限窗口），官方 `phone_agent_test.dart` `+2`、EXIT=0；物理 MIUI API31 官方 `+2`、EXIT=0，「叠加层不污染产品截图」`+1`、EXIT=0。本地 Loader 165、插件 Kotlin 97、Flutter Mod/Phone Agent 126、根项目与 Loader 静态分析均通过。产品 debug APK 在最终树 `dfcef53cfd77ea78` 于全部设备测试后 `flutter clean` 显式构建：181,403,054 字节，SHA-256 `501d4a0087294258baa882e9a32856208805fcba88228ec34e15016ae89689fb`，debug merged manifest 含 `SecureWindowFixtureActivity`，release 不含且含 `PhoneAgentService`；构建后未再运行 integration_test。设备结果见 9.3.7。
- 上一轮 M22（权限弹窗保守收尾，2026-11-12）：用户明确同意“不可识别权限弹窗仍返回 `no_window`，消息条件式提示人工处理/取消并返回测试应用”。M20（窗口 root 补全）与 M21（事件来源包名）均已在 API35 设备上证伪并 abandoned，未合并生产代码；本轮整合其准确证据，只把 `PhoneAgentService` 三处无可访问窗口的英文提示改为条件式人工提示，错误码、guard、读树/截图密码遮挡、输入边界和白名单均不变。异常测试改为宿主 `dumpsys` 独立确认真实 `GrantPermissionsActivity` 后直接 tap/back/截图断言 `no_window` + 提示，不再因 `root=null` skip，也不把任意 `no_window` 当通过。设备结果与新树/APK 记录见 9.3.6。
- 上一轮 M21（权限弹窗事件来源评估，abandoned）：按 mission 先做临时事件诊断，不改生产代码。API35 真实 `GrantPermissionsActivity` 弹窗期间，服务已连接并持续收到应用和 systemui 事件，但没有收到任何 `permissioncontroller` 的 `TYPE_WINDOW_STATE_CHANGED`；只有 `pkg=null` 的 `TYPE_WINDOWS_CHANGED`（窗口 id 指向无 root 的弹窗）和后台 systemui 事件。活动/聚焦弹窗窗口仍没有可访问 root，无法取得包名，因此事件来源包名无法与活动/聚焦窗口 id 建立可靠匹配，该机制不可用。按 mission 停止条件停止，未提交生产代码或测试改动；临时诊断已从交付移除，证据见 9.3.5。
- 上一轮 M20（权限窗口输入路径诊断，abandoned）：只做设备诊断，不改生产代码。API35 真实 `GrantPermissionsActivity` 弹窗期间服务 `rootInActiveWindow` 为 null；临时诊断（已移除，不进交付）实测 `windows` 只有两个窗口：`com.android.systemui` 窗口 `active=false focused=false hasRoot=true`，权限弹窗窗口 `active=true focused=true hasRoot=false pkg=null`。活动/聚焦窗口没有可访问 root，无法取得包名；唯一有 root 的是后台 systemui 窗口。因此「用可确认的活动/聚焦系统窗口补全 WindowState 以返回 `system_window_denied`」在本设备不可实现；证据见 9.3.4。
- 上一轮 M19（权限窗口真实验证）：只改中文文档与 debug 异常测试，不改产品代码、schema、白名单或上游。已查明上一轮 API35 权限弹窗 90 秒未出现的原因是设备息屏（`mWakefulness=Asleep` 时 `am start` 不获前台焦点，唤醒后立即出现）；真实 `com.google.android.permissioncontroller` 弹窗已出现，但服务 `rootInActiveWindow` 为 null，**读树实测返回 `no_window`**；输入按 `currentWindow` 前置 guard 推导为 `no_window`（M19 未执行 tap/back，属代码路径推导），`system_window_denied` 未产生，输入仍被拒绝、权限未授予。最终合成树 `V:/coding/kelivo-private/.tower/worktrees/wt-19/.build/worktrees/75429900bf8fc452`，`modsetHash` `75429900bf8fc4526fb7005729da565f210eab3d9de922d94039e6399f808d11`，`verify` 通过；完整异常套件 `+5 ~1`、`All tests passed!`、EXIT=0。历史结果见 9.3.3。
- 上一轮 M17（节点重验诊断）：`stale_handle` 错误码不变；`ObservationRegistry` 把 `refresh()`、可见性和可用性前置失败拆成固定诊断标识 `refresh_failed`、`not_visible`、`not_enabled`，按该顺序短路判断，消息不含节点文本、类名、viewId 或其他内容，不改变任何通过条件、指纹字段或 TTL/窗口校验。契约见 6.5.1，设备诊断结果见 9.3.2。
- 上一轮修正（节点重验，历史）：`PhoneNode.fingerprint()` 不再包含 `isFocused` 和动作集合 `actions`；同一已刷新节点因点击/输入产生的焦点变化和动作增减不再让后续 `set_text` 返回 `stale_handle`；`isSelected`、内容、稳定能力字段、窗口/包名/尺寸/旋转和 120 秒 TTL 校验保持不变。指纹为结构化字段列表，`stale_handle` 只附带固定字段名，不从节点内容反解字段名。契约见 6.5.1。
- 上一轮 M16（物理 MIUI API31 验收记录，历史）：该轮只改中文文档，产品代码/测试/`mod.json`/schema/白名单/上游均未修改。最终源码 `modsetHash` `3d3cd25b4def35633dcf848373037cbe2c5200f795339c315b3ac9c3268a3174`，合成树 `V:/coding/kelivo-private/.tower/worktrees/wt-16/.build/worktrees/3d3cd25b4def3563`，`plan`/`apply`/`verify` 通过；该轮产品 debug APK 为 181,369,890 字节，SHA-256 `c6f20d250239bae223a4fdaa5ff1807ba34eab38bd8f9e7f9710e8c21747a58b`。设备证据来自此前相同代码/测试行为，未在新树重跑设备。结果见 9.3.2 与 9.4.2。
- 上一轮 M10（API35 FLAG_SECURE/异常路径）：最终源码 `modsetHash` `5b1cde0304e687b9e3a26935cf85b5a27d102c9ecb409ff0e8b1358075aa902d`，合成树 `V:/coding/kelivo-private/.tower/worktrees/wt-10/.build/worktrees/5b1cde0304e687b9`；完整异常套件实际运行于 `2c1513ecef3f2293` 树，`+5 ~1`、EXIT=0；当前 `5b1cde...` 是仅文档哈希变化后的最终源码/构建树，关键代码/测试一致，新树未重跑设备；权限窗口未验证；API35/API29 官方测试各 2 项通过。契约和结果见 9.3.1。
- 上一轮 magpie VLM 验收（历史，API35 模拟器）：使用当时的 debug APK 和 magpie 网关模型 `llama-cpp/llama-cpp`（provider `http://10.0.2.2:3425/v1`，UI Image + Tools；局域网访问由用户开启，未读取或记录密钥）完成真实图片链路、Kelivo 应用内固定任务和跨新用户轮次历史图片回放。证据见 9.4。该轮的合成树 `5f0be65f...` 和 APK 181369230 字节是历史记录，不代表当前实现。
- 历史 M23 产品 debug APK（最终树 `V:/coding/kelivo-private/.tower/worktrees/wt-23/.build/worktrees/dfcef53cfd77ea78`，全部设备测试后 `flutter clean` + 显式 `flutter build apk --debug`，构建后未再运行 integration_test）：**181,403,054 字节**，SHA-256 `501d4a0087294258baa882e9a32856208805fcba88228ec34e15016ae89689fb`；debug merged manifest 含 `SecureWindowFixtureActivity`（1 处），release merged manifest 不含该夹具（0 处）且含 `PhoneAgentService`（1 处，不宣称签名 release）。历史：此前 181,402,630 / `a72cac9b…` 在 `a460dcbc` 构建，随后被 17:29/17:32 的 integration_test 覆盖为 251,120,349 / `e3d9d22b…` 测试入口构建，不能作为产品；`b56fc97d` 的 181,403,426 / `f40b76cf…` 是不同 artifact，未采用。设备运行树 `9ebf2e991caa07ed` 的 `app-debug.apk` 是测试入口构建，只作设备/测试证据，不作为产品。「M23 尚未生成产品 APK」只适用于 round-2/3 历史，不代表当前。
- 历史产品 debug APK（M22 最终合成树 `V:/coding/kelivo-private/.tower/worktrees/wt-22/.build/worktrees/b9989da92f35bac8`，新建树后显式 `flutter build apk --debug` 生成，测试后未在该树运行 integration_test）：**181,370,434 字节**，SHA-256 `06b806e4ac80b998b2b3c114eacbd7971a34a5e16e8b1467b6450b5a2846a04a`；debug merged manifest 含 `SecureWindowFixtureActivity`（1 处），release merged manifest 不含该夹具（0 处，不宣称签名 release）。设备测试在 `d94f4165af9277d5` 树运行，其 clean 产品 APK 为 181,373,914 字节 / `5cc74cabf3fc02c9c0a7e79174ea5b9467523d25a72c760b65cb634daf69f0e3`，仅作设备证据；两树代码/测试一致，仅 `plugin/README.md` 文档副本不同，APK 二进制略有差异，未进一步归因，未把测试入口构建当产品。该 M22 APK 不代表 M23 代码。
- 当前 M22 自动检查：最终合成树 `V:/coding/kelivo-private/.tower/worktrees/wt-22/.build/worktrees/b9989da92f35bac8`，`modsetHash` `b9989da92f35bac8703cb5ed803499222886ec6bae15d5e8045a8e45b6689725`，`plan`/`apply`/`verify` 通过；Loader 165、插件 Kotlin 66、插件 Dart 17、根项目 seam 56（均在设备测试树运行，代码/测试与最终树一致）、根项目 `dart analyze --fatal-infos lib test integration_test tool` 通过（最终树已重跑，根分析前已运行 `flutter pub get --directory tool/l10n --enforce-lockfile`）。API35 官方 `phone_agent_test.dart` `+2`、完整异常套件 `+6`，均 EXIT=0（设备测试树 `d94f4165af9277d5` 与最终树仅 `plugin/README.md` 文档副本不同）；API29 不在线未运行。结果见 9.3.6。
- 上一轮自动检查（历史）：Loader 165、Phone Agent 105、Mods 16、settings 入口 2、上游 `tool_result_content` 回归、插件 Dart 17、插件 Kotlin 66 和上游 PhoneControl 49；M10 历史轮只改测试/文档，未重复这些静态套件，新增聚焦工具测试 32 项通过。
- 上一轮节点重验合成树（历史）：`V:/coding/kelivo-private/.tower/worktrees/wt-1/.build/worktrees/7593c21b5f9da01f`，`modsetHash` 为 `7593c21b5f9da01fb8b8c4dfe167d892a940efe4a1caf591b772fbe83b6b6f7d`；当时 Phone Agent 103、Mods 16、settings 入口 2、插件 Dart 17、插件 Kotlin 66、上游 PhoneControl 49 通过。
- 本地化：23 个键已由本机免费 Magpie llama-cpp 翻译，`translate.py check` 四个目标语言（ko、ru、tr、zh_Hant）均 0 pending；本轮无 UI/ARB 改动，未重跑翻译生成。
- 上一轮设备回归（历史）：API 35 模拟器与 API 29 真机官方集成测试均退出码 0，逐项结果见 9.3；该结果对应提交 `698cace` 的运行时语义。之后仅调整诊断编码、提取纯 JVM 前置校验接缝、补测试和文档，未重复双 API 设备回归（按 R1 审查意见）。
- 历史验收记录（焦点修正前，不代表当前实现）：最终合成树 `V:/coding/kelivo-private/.build/worktrees/4ed083cf5fe7dda8`，`modsetHash` 为 `4ed083cf5fe7dda8eec575588594831d9515cbd88429cb6f5b893c9ca6544331`；Flutter 255 项（254 通过 + 1 Windows 条件跳过）；插件 Kotlin 55；旧产品 APK 181354638 字节，SHA-256 `af67f4285bef9e3d1093c6433f42669a8c84b8bee99b6397f68dfd91e1c60ceb`；当时的未验证项包含 API 30+ 截图与坐标手势。
- 仍明确未验证：签名 release、原生超时、`stale_handle` 根因；物理 MIUI API31 未运行锁屏、home/recents、服务中断和权限弹窗，不能从 API35 模拟器结果推断；权限弹窗的保守拒绝只在 API35 模拟器验证（`no_window` + 条件式提示，未执行手势/系统导航），物理设备和其他 Android 版本未验证；`llama-cpp/llama-cpp` 的物理完整坐标 swipe 未完成。API35 模拟器已验证 secure 截图行为、旋转、home/recents、锁屏、服务禁用/重启和权限弹窗保守拒绝；物理 MIUI API31 已验证真实截图/读树/节点输入/滚动、物理 `FLAG_SECURE` 与旋转；跨新用户轮次历史图片回放已在 API35 模拟器通过，物理 MIUI 的真实图片请求与像素专属视觉确认见 9.4.2。以上只验证 magpie `llama-cpp/llama-cpp`、`mistral/deepseek-v4-1-flash-1017` 与这两台设备，不承诺任意模型或设备。因此不宣称 Phone Agent 第二阶段全部完成。
- Mod Loader 的目录、命令、补丁机制和通用接缝见 [Mod Loader 实施计划](mod-loader-plan.md)。
- 本文只定义 `phone_agent` Mod，不重复 Loader 的通用实现。
- 基线仓库：`V:/coding/kelivo`。
- 基线 commit：`73afa4ec77cfc9af2efea2487fee8bba1362639d`。
- 本文与 Loader 计划均位于私有仓 `docs/`，上游仓只作为源码来源。

## 1. 目标、原则与非目标

### 1.1 目标

1. 在通用 Mod 接缝之上实现独立的 Android 手机 Agent。
2. 提供截图、按需无障碍树和基础输入三个基础工具。
3. 截图可以直接进入 Kelivo 现有的 VLM 工具图片链路。
4. 使用独立 Flutter path 插件和独立 `AccessibilityService`，不修改上游 `PhoneControlService`。
5. 模型不管理 `snapshot_id`；节点句柄、截图状态和时效由原生侧维护。
6. 允许模型在目标仍有效时复用节点句柄，按任务语义决定何时重新观察。
7. 保留可验证的原生技术护栏，同时如实说明业务安全和隐私边界。
8. 为每个助手提供独立 localToolId `phone_agent`，不再复用 `phone_control`。
9. 在 Mods 页提供助手选择和三态单选，并显示独立 `PhoneAgentService` 的服务状态。
10. 新增移动和桌面 Mods 设置入口，产品文案按上游标准进入 ARB 并同步所有目标语言。

### 1.2 原则

- 先完成只读闭环，再增加真实输入，最后验证 VLM 任务。
- 工具协议尽量少状态，原生执行层负责句柄和窗口管理。
- 节点输入优先，坐标输入作为视觉和自绘界面的补充。
- 观察按需发生，不强制每个动作后重新读取完整界面。
- 原生技术护栏尽量硬实现，业务风险识别不作虚假保证。
- 首版只在显式测试包名中开放输入，不直接面向敏感应用（M32 已定（用户拍板）、未实现：用户按应用批准后，输入与观察都受同一批准约束，见 7.5.1/7.5.4）。
- 工具选择与服务授权分离。Mods 页的三态选择只决定助手使用哪套工具，不代表系统无障碍服务已经授权。
- 正常 UI 不允许原生手机控制和 Phone Agent 同时启用；两者互斥写入助手的 `localToolIds`。
- 已有仅启用 `phone_control` 的助手保持原生行为，不自动迁移，不批量改写 `localToolIds`。
- 两个 `AccessibilityService` 继续共存；启用其中一个不会自动启用、授权或切换另一个。
- 面向开发者和维护者的文档使用中文；工具 schema 和结构化错误沿用现有代码的英文风格；产品 UI 文案进入 ARB。

### 1.3 非目标

Phone Agent 首版不做：

- 自动识别并可靠拦截“发送、购买、删除”等业务动作。
- 通用逐步确认系统、危险文本分类器或第二个 LLM 风险审查器。
- 自动迁移已有助手，或把仅启用 `phone_control` 的助手批量改成 `phone_agent`。
- 自动授权无障碍服务、自动打开系统无障碍开关，或在两个服务之间自动切换。
- 把 Mods 页接入上游设置搜索索引。
- 上游工具目录集成、运行时 Mod 商店、动态 Dart 加载或运行时下载插件。
- 在正常 UI 中同时启用原生手机控制和 Phone Agent。
- 按应用配置任意策略，或以运行时编辑的方式修改**构建期**测试包白名单（**首版**不做）。M32 已把「用户按应用批准」的运行时白名单与签名绑定定为**已定（用户拍板）、未实现**（运行时白名单的批准方向为用户拍板；`(包名, 签名)` 绑定的细节为早期已定契约。见 7.5.2/7.5.9）：那是“授权或不授权某个应用”的开关，不是可编辑的任意策略；构建期硬禁止仍不可由运行时覆盖。
- `list_apps`、`open_app`、通知栏和快捷设置操作。
- 多显示器、折叠屏专项适配或 MediaProjection 截图后备方案。
- 自动上下文压缩、树差分、跨观测稳定节点 ID。
- Shell、root、Shizuku、录屏或任意文件访问。
- 对任意应用、任意模型或任意任务成功率的承诺。

## 2. 与 Kelivo 的集成边界

### 2.1 通用 Mod 接缝

Phone Agent 通过 Loader 生成的静态注册表实现：

- `decorateDefinitions`：按平台、助手工具选择和模型能力添加或移除工具定义；
- `wrapHandler`：处理 `phone_agent_*` 调用，其余调用原样委托给上游 handler。

`LocalToolNames.all` 不加入 `phone_agent`，避免上游按 `all` 生成原生工具定义、工具标签或本地工具开关。`phone_agent` 是 Mod 自有的助手级工具 ID，由 Mod overlay 中的常量定义；如果实现选择在上游类中增加常量，也必须不加入 `all`，且不得生成原生定义。

上游助手的“本地工具”页和对话工具菜单不新增 `phone_agent` 项。Phone Agent 的助手级选择只在 Mods 页完成；上游本地工具页仍按上游行为显示原生 `phone_control`。这些上游界面不显示 `phone_agent`；选择 Phone Agent 后，它们可能把手机控制显示为未启用，这是预期行为，以 Mods 页为准。

### 2.2 助手级工具选择：三态契约

Mods 页提供助手选择，并对当前助手提供三个互斥选项：

| 选择 | 写入 `assistant.localToolIds` | 上游授权页 | 工具定义 |
|---|---|---|---|
| 关闭 | 移除 `phone_control` 和 `phone_agent` | 不打开 | 不暴露原生手机控制和 Phone Agent 工具 |
| 原生手机控制 | 保留或加入 `phone_control`，移除 `phone_agent` | 继续打开上游手机控制授权页 | 使用上游 `phone_control` |
| Phone Agent | 加入 `phone_agent`，移除 `phone_control` | 不自动打开 | 使用 Mod 的 `phone_agent_*` |

规则：

- 三个选项是单选，正常 UI 不允许两者同时启用。写入一个选项时必须移除另一个 ID。
- 选择“原生手机控制”后，页面按上游现有流程进入手机控制授权页；授权是否完成由上游页面和系统设置决定。
- 选择“Phone Agent”只写入工具 ID，不自动授权、不自动打开系统无障碍设置；服务状态由 Mods 页单独显示。
- 选择“关闭”移除两个 ID，但不自动关闭系统无障碍服务。
- 已有仅启用 `phone_control` 的助手在 Mods 页显示为“原生手机控制”，不自动迁移。
- 如果历史数据、手工编辑或上游本地工具页导致两个 ID 同时存在，Mods 页显示冲突状态并要求重新选择；在用户处理前，`PhoneAgentMod` 以 `phone_agent` 为激活依据，并过滤原生 `phone_control` 定义，避免同时暴露两套工具。
- 上游本地工具开关与页面的互斥由 phone_agent Mod 自己的 `local-tool-mutual-exclusion.patch` 执行，不是 Loader 通用接缝。该补丁必须保证 `phone_control` 与 `phone_agent` 不会同时写成启用；如果无法隐藏或拦截 `phone_control`，Mods 页必须显示冲突并要求重新选择，执行层按 `phone_agent` 激活并过滤原生 `phone_control`，不能静默并存。
- 每次执行 Mod 工具前，通过 `AssistantProvider.getById` 重读当前助手的 `phone_agent`。生成途中撤销选择后，后续调用返回 `phone_agent_disabled`，不再继续操作。
- 选择只修改 `assistant.localToolIds`，不修改数据库 schema，不新增助手字段。

### 2.3 Mods 设置页与服务状态

新增移动和桌面 Mods 设置入口，宽窄屏共用同一个简单页面，不单独做桌面/移动两套布局，也不接入 `settings_search_index.dart`。

页面包含：

1. 助手选择器：列出助手并显示当前三态；切换助手时读取该助手的 `localToolIds`。
2. 三态单选：关闭、原生手机控制、Phone Agent，按 2.2 的规则互斥写入。
3. 独立 `PhoneAgentService` 状态面板：显示 supported、enabled、connected 和 sdk，并用 `enabled && connected` 派生 ready。
4. 刷新按钮：重新读取插件状态。
5. 打开无障碍设置按钮：调用插件的 `openAccessibilitySettings()`，失败时提示用户手动进入系统设置。
6. 能力与隐私说明：说明可读取屏幕、点击、输入、滚动和截图，屏幕内容会发送给当前对话配置的模型服务商并保存在工具结果中，密码字段会隐藏，服务不会持续录屏，用户可随时关闭工具或停用服务。

状态字段含义：

| 字段 | 含义 |
|---|---|
| `PhoneAgentAvailability.supported` | 仅表示 Android API 30+ 系统截图能力；false 不代表 Phone Agent 或平台不可用。 |
| `enabled` | 系统无障碍设置中是否已启用独立 `PhoneAgentService`。 |
| `connected` | 独立服务是否已连接并可以接收请求。 |
| `ready` | 由 `enabled && connected` 派生；表示服务可接收请求，树和节点输入可用。API 29 也可以 ready。 |
| `sdk`（`androidSdkInt`） | 当前 Android API 级别；`sdk >= 30` 时截图和坐标手势可用。 |

`PhoneAgentAvailability.supported` 只描述截图能力，不是 Phone Agent 的总体可用性。API 29 上 `supported=false`，但服务仍可 `enabled` 且 `connected`，即 ready，树和节点输入可用；截图返回 `unsupported_os`，页面显示截图和坐标手势限制。非 Android 平台不加载 Mod 工具，页面显示平台不支持；不要用 `supported=false` 表示平台不支持。

非 Android 平台仍可打开 Mods 页，但页面显示平台不支持，不添加任何 Mod 工具；这与 `supported=false` 的截图限制含义不同。

两个 `AccessibilityService` 继续共存：上游 `PhoneControlService` 和独立 `PhoneAgentService` 各自在 Manifest 中声明，各自在系统设置中授权。Mod 不自动授权、不自动切换、不在用户选择某个工具时修改系统无障碍开关。

### 2.4 图片链路

直接复用现有链路，不修改 provider：

```text
phone_agent_screenshot
  → Kelivo 适配层
  → McpImageSnapshot.saveBytes
  → ClientToolResult + metadata.mcpResult.imageUris
  → 工具循环与消息持久化
  → ToolResultContent
  → OpenAI / Claude / Gemini 请求
```

关键现有实现：

- `lib/utils/mcp_structured_image.dart:46`：图片元数据。
- `lib/utils/mcp_structured_image.dart:95`：`ClientToolResult`。
- `lib/core/services/mcp/mcp_image_snapshot.dart:54`：图片落盘及实际尺寸。
- `lib/core/services/api/generation/tool_loop_runner.dart:195`：工具结果接入。
- `lib/core/services/api/tool_result_content.dart:15`：按模型能力读取或省略图片。
- `lib/core/services/browser/browser_tools_service.dart:816`：现有图文工具结果示例。

视觉能力只在定义接缝中判断。执行 handler 不猜模型能力，图片是否进入请求继续由 `ToolResultContent` 决定。

### 2.5 后台悬浮胶囊

独立服务不会触发上游 `phoneControlStarted()`。用户开启后台胶囊时，胶囊可能出现在截图中或拦截坐标手势。

首版保留此限制，不增加 Android 宿主补丁。默认关闭胶囊的真机验收必须全部通过；开启胶囊的情况只记录，不宣称兼容。

本 Mod 自己的可视化叠加层（2.6）是另一个窗口，`FLAG_NOT_TOUCHABLE`，不会拦截手势；它也不能隐藏上游胶囊。

### 2.6 前台可视化叠加层

用户要求助手在后台操作时前台可见。实现为独立 `PhoneAgentOverlay`，只借上游 `BackgroundOverlay` 的视觉语言（深/浅色面、描边、强调色 `#008999`），不复用 `BackgroundRuntime`/`BackgroundOverlay` 代码，不修改上游宿主，也不需要普通悬浮窗权限。

- 窗口：`TYPE_ACCESSIBILITY_OVERLAY`、`FLAG_NOT_TOUCHABLE | FLAG_NOT_FOCUSABLE | FLAG_LAYOUT_IN_SCREEN`、`PixelFormat.TRANSLUCENT`；不申请 `SYSTEM_ALERT_WINDOW`，不调用 `Settings.canDrawOverlays`，不设 `FLAG_SECURE`。`FLAG_NOT_TOUCHABLE` 保证真实触摸注入不被拦截；`FLAG_NOT_FOCUSABLE` 保证叠加层不会成为 `rootInActiveWindow`，读树不受影响。窗口按需 add/remove，空闲时不存在，服务断连即随连接销毁。
- 显示时机（首版默认开启，不新增设置开关、`status` 字段或 ARB 文案）：读树成功进入遍历前显示观察脉冲；截图成功返回后显示短暂完成脉冲（此时图片已生成，不会进入图片）；节点动作在前置校验通过且 `perform` 返回 true 后，用刷新后的 `bounds` 中心显示圆环和边框；坐标手势在 `dispatchGesture` 返回 true 后，按同一物理起点/终点和真实 `duration_ms` 显示移动圆点；系统动作在 `performGlobalAction` 返回 true 后显示无文本方向图形。`perform=false`、`dispatch=false`、前置校验失败、`stale_handle`、`package_not_allowed`、`system_window_denied`、`device_locked` 等拒绝路径不产生任何视觉。
- 语义：动画只表示系统接受或完成动作，不代表业务成功、任务进度、模型思考或用户审批；不是安全护栏，也不改变任何工具结果和错误码。
- 隐私：只用无文本图形；不显示输入文字、密码、截图字节或缩略图、节点文本、包名和坐标数值；不写敏感日志。`set_text` 只画输入框边框和光标。
- 截图不污染：截图前在主线程 `removeViewImmediate` 并等待两帧（`Choreographer`），再额外等待约 48ms 合成周期后调用 `takeScreenshot`；没有窗口时零等待；隐藏失败或 250ms 有界等待超时返回 `screenshot_failed`，不发送图片或图片 metadata，不得跳过隐藏让截图成功。等待可被服务中断解除，迟到的帧回调不得触发第二次截图。隐藏等待结束后、`takeScreenshot` 前重新读取当前窗口并比较 `windowId`/包名/宽高/旋转，变化返回 `stale_observation` 且不发图；异步 `takeScreenshot` 回调返回后再次读取当前窗口做同样比较，不一致同样返回 `stale_observation` 且不处理、不发送图片，覆盖 gate 与回调之间同尺寸切应用的窗口。两次读取中 `currentWindow()` 返回 null 时按 `stale_observation` 处理；`currentWindow()` 抛异常时按 `screenshot_blocked` fail closed，不发送图片或图片 metadata。残余限制：异步间隔内同一活动窗口新出现密码字段、非活动分屏窗口变化、同窗口分屏 resize 无法原子闭合，不保证遮挡。读树不隐藏叠加层。API35 实测仅等两帧仍会抓到旧帧，因此保留 48ms 合成等待；总等待仍远小于 250ms 上限。
- 密码遮挡：截图前遍历 `service.windows` 时只跳过能可靠确认属于本服务自己的 accessibility overlay 窗口（root 存在且 root 包名等于自身包）；root 包名未知或其他包名的窗口继续参与密码遮挡，不能把未知身份当作自身窗口，也不得屏蔽其他服务或应用的窗口。
- 时序与 fail closed：事件在主线程真正绘制前再次校验清理代次和调用方的 `isActive`（手势 finished、服务代次），clear/release/旋转/切窗先于 show 时旧事件不得重新出现；动作开始时捕获清理代次并传给 `show`，动作后 clear/切窗使 node/gesture/system 旧视觉失效；窗口移除失败或附着状态未知时不得再添加新窗口，截图必须返回 `screenshot_failed`，动画结束回调按具体 View 清理，不能因 plan 已被清空而永久遗留窗口。
- 手势时长：视觉 travel 复用输入层已校验的真实 `duration_ms`（50–2000ms），尾段可以额外存在，但不得把真实时长改成更慢的视觉时长。
- 生命周期：所有窗口操作在主线程；旋转（`onConfigurationChanged`）、锁屏（`ensureUnlocked` 失败）、`onInterrupt`/`onUnbind`/`onDestroy`、`interruptPending` 和前台窗口状态切换到其他包时清理；每个视觉有边界时长（观察约 700ms、节点动作 450–900ms、手势按真实时长加尾段、系统动作 500ms、截图完成 500ms，硬上限约 2.5s）并自动隐藏；新事件替换旧事件，不堆叠。
- `addView` 失败（`BadTokenException`/`SecurityException`/`IllegalStateException`）只禁用本会话可视化，不改变工具结果，也不写成工具错误。
- 上游可触摸后台胶囊仍是已知兼容限制：Mod 无法隐藏其他 owner 的窗口；开启胶囊时截图可能包含胶囊、坐标手势可能被胶囊拦截。只记录和提示，不宣称兼容。

## 3. Mod 文件结构

以下为当前文件划分；职责和边界不变。`mod.json` 的 `patches`、`touches` 和 `copy` 必须与最终文件一致。

```text
mods/phone_agent/
├── mod.json
├── README.md                   # 中文安装、选择、授权、白名单、限制与维护说明
├── patches/
│   ├── pubspec.patch           # path 依赖
│   ├── application-id.patch    # 独立测试包名与启动名称
│   ├── local-tool-mutual-exclusion.patch  # 本地工具开关互斥
│   ├── settings-entry.patch    # 移动和桌面 Mods 设置入口
│   ├── l10n-source.patch       # 新增 ARB 键和英文描述
│   └── l10n-generated.patch    # 翻译后的 ARB、状态和生成 Dart
├── overlay/
│   ├── lib/features/phone_agent/
│   │   ├── phone_agent_mod.dart
│   │   ├── phone_agent_tools.dart
│   │   ├── phone_agent_service.dart
│   │   ├── phone_agent_screenshot.dart
│   │   └── phone_agent_local_tool.dart
│   ├── lib/features/mods/
│   │   └── mods_page.dart
│   ├── test/features/phone_agent/
│   ├── test/features/mods/
│   ├── test/features/settings/pages/
│   │   └── mods_settings_entry_test.dart
│   └── integration_test/phone_agent_test.dart
└── plugin/                     # 复制为 dependencies/kelivo_phone_agent/
```

文件职责：

- `phone_agent_local_tool.dart`：`PhoneAgentLocalTool.id`、`PhoneAgentControlSelection`、`applySelection`、`writeSelection` 和冲突检测。
- `mods_page.dart`：`ModsPage`、`ModsPane` 和共用 `ModsView`；助手选择、三态单选、服务状态、刷新、打开无障碍设置和能力/隐私说明。
- `local-tool-mutual-exclusion.patch`：修改 `lib/features/home/services/local_tool_toggle.dart`，在本地工具开关写入时保证 `phone_control` 与 `phone_agent` 互斥，并重读当前助手避免旧快照覆盖。它是 phone_agent Mod 自己声明的业务补丁，不是 Loader 通用接缝。
- `settings-entry.patch`：在 `lib/features/settings/pages/settings_page.dart` 和 `lib/desktop/desktop_settings_page.dart` 增加 `ModsPage`/`ModsPane` 入口及桌面菜单注册，不修改 `lib/features/settings/search/settings_search_index.dart`。它是 phone_agent Mod 自己声明的业务补丁，不是 Loader 通用接缝；只增加入口和导入，不把 Mod 业务逻辑写进上游文件。
- `l10n-source.patch`：在 `lib/l10n/app_en.arb` 和 `app_zh.arb` 增加产品文案键及 `@key.description`。
- `l10n-generated.patch`：包含本机免费 llama-cpp 翻译后的 ARB、`tool/l10n/state` 和生成的 Dart 输出；`translate.py check` 四目标语言 0 pending。
- `mod.json`：当前已声明 `local-tool-mutual-exclusion.patch`、`settings-entry.patch`、`l10n-source.patch`、`l10n-generated.patch`，以及 `touches`（含本地工具开关、移动/桌面设置页、`lib/l10n` 和 `tool/l10n/state`）、复制目标和工具名；修改时必须保持与最终文件一致。

Loader 通用 `lib/modding/tool_mod.dart` 和 `mod_registry` 生成逻辑不 import Phone Agent。`mod_registry.g.dart` 中的 Mod import 只来自 `mod.json` 的 `registration.import`，不是 Loader 通用代码的硬编码依赖。

`mod.json` 额外记录上游 `PhoneControlService.kt` 的来源 commit 和内容哈希，作为 vendored 参考实现的漂移提醒。Loader 只负责提示变化，是否吸收上游修复由人工审查决定。

## 4. Kelivo 适配层

由 `overlay/` 新增或更新：

| 文件 | 职责 |
|---|---|
| `lib/features/phone_agent/phone_agent_mod.dart` | 注册类；按 Android、助手 `phone_agent` 和工具能力激活；过滤原生 `phone_control` 与重复 `phone_agent_*`；包装 handler；执行前重查 ID。 |
| `lib/features/phone_agent/phone_agent_tools.dart` | 三个工具 schema、名称集合和调用分发。 |
| `lib/features/phone_agent/phone_agent_service.dart` | 调用独立插件、读取 supported/enabled/connected/sdk 状态并派生 ready、结构化错误。 |
| `lib/features/phone_agent/phone_agent_screenshot.dart` | 图片落盘、尺寸校验、`ClientToolResult` 元数据。 |
| `lib/features/phone_agent/phone_agent_local_tool.dart` | `PhoneAgentLocalTool`/`PhoneAgentControlSelection`；三态选择、`localToolIds` 互斥读写和冲突检测。 |
| `lib/features/mods/mods_page.dart` | `ModsPage`/`ModsPane`/`ModsView`；移动/桌面共用页面，不接设置搜索。 |

适配层可以 import Kelivo 和插件；独立插件不能反向 import `package:Kelivo/...`，避免循环依赖。

定义包装位于上游 schema override 之后，首版不支持用上游 schema override 修改 Mod 工具。执行包装位于上游 handler 之外，首版也不自动继承上游通用审批流程。

## 5. 独立 Flutter 插件

`plugin/` 在合成树中复制为 `dependencies/kelivo_phone_agent/`：

| 文件 | 职责 |
|---|---|
| `pubspec.yaml` | 声明 Android Flutter 插件。 |
| `lib/kelivo_phone_agent.dart` | 对外纯 Dart API。 |
| `lib/src/phone_agent_client.dart` | 独立 `MethodChannel('kelivo/phone_agent')`。 |
| `lib/src/phone_agent_types.dart` | 状态、截图、树页、输入结果和异常类型。 |
| `android/build.gradle` | Android library 与 Kotlin 配置，对齐宿主 SDK/JVM。 |
| `android/src/main/AndroidManifest.xml` | 声明独立无障碍服务，由 Manifest Merger 合并。 |
| `android/src/main/res/xml/kelivo_phone_agent_service.xml` | `canRetrieveWindowContent`、`canPerformGestures`、`canTakeScreenshot` 等配置。 |
| `android/src/main/res/values/strings.xml` | 独立服务名称和说明。 |
| `android/src/main/kotlin/com/kelivo/phoneagent/PhoneAgentPlugin.kt` | `FlutterPlugin` 注册和通道生命周期。 |
| `PhoneAgentService.kt` | 服务连接、串行 worker、锁屏/断连、请求分发。 |
| `ObservationRegistry.kt` | 树句柄、截图坐标观测、TTL 和失效管理。 |
| `NodeTreeReader.kt` | 有界 DFS、过滤、分页、密码文本隐藏。 |
| `NodeActionExecutor.kt` | 节点输入、坐标手势、系统导航和结果回调。 |
| `ScreenshotCapture.kt` | API 30+ 截图、缩放、密码区域遮挡、限频和错误映射。 |
| `PhoneAgentJson.kt` | 通道结果和错误构造。 |

插件状态 API 至少返回 `supported`、`enabled`、`connected` 和 `sdk`（`androidSdkInt`）四个字段，供 Mods 页显示；页面用 `enabled && connected` 派生 ready。`PhoneAgentAvailability.supported` 只表示 Android API 30+ 截图能力，不表示 Phone Agent 或平台是否可用。插件只读取状态和打开系统无障碍设置，不自动授权、不自动切换服务。

为与设备已安装的 Kelivo 并存，Mod 额外通过 `patches/application-id.patch` 修改 `android/app/build.gradle.kts` 和宿主 Manifest，使用包名 `com.psyche.kelivo.phoneagent`、启动名称 `Kelivo Agent`。

除新增 Mods 入口、本地工具开关互斥和 ARB 键外，不修改：

- `MainActivity.kt`、`KelivoApplication.kt`；
- `PhoneControlService.kt`、`DeviceLocalToolsHandler.kt`；
- `local_tools_service.dart` 的原生工具定义和 `LocalToolNames.all`。

## 6. 工具契约

### 6.1 工具列表

首版提供三个工具：

1. `phone_agent_screenshot`：截取当前画面，返回图片、图片尺寸、物理屏幕尺寸和前台包名。
2. `phone_agent_tree`：按需读取节点，支持分页和 `interactive_only`。
3. `phone_agent_input`：执行基础输入。

所有 schema 和结果均不出现 `snapshot_id`，均设置 `additionalProperties: false`。

`phone_agent_input` 首版动作：

- 节点：`tap`、`long_press`、`set_text`、`scroll`；
- 坐标：`tap`、`long_press`、`swipe`；
- 系统：`back`、`home`、`recents`。

### 6.2 激活、过滤与执行前重查

`PhoneAgentMod` 仅在以下条件同时满足时激活：

- 平台为 Android；
- 当前模型支持工具调用；
- 当前助手的 `localToolIds` 包含 `phone_agent`。

激活时：

- 从工具定义中移除原生 `phone_control`；
- 移除任何重复的 `phone_agent_*` 定义，避免与上游或其他 Mod 重复暴露；
- 添加本 Mod 的三个工具定义。

每次执行 Mod 工具前，重读当前助手的 `phone_agent`；撤销后返回 `phone_agent_disabled`。助手不存在或读取失败时按未启用处理，同样返回 `phone_agent_disabled`。未激活时完全保留上游定义，原生 `phone_control` 按上游行为工作。

`phone_agent` 不加入 `LocalToolNames.all`，因此上游不会为它生成原生定义、标签或开关。Mods 页是它的正常选择入口。

### 6.3 非视觉模型降级

- 不支持工具调用时，不添加任何 Mod 工具。
- 支持工具但不支持图片输入时，不暴露 `phone_agent_screenshot`。
- 非视觉模型只使用树和节点输入，不提供依赖截图的坐标输入。
- 若仍误调截图，返回结构化文本错误，不生成空图或无意义占位。

### 6.4 坐标约定

- 所有模型坐标均为 `[0, 1]` 的归一化值，原点为截图左上角。
- 模型不需要计算截图像素、物理像素或缩放比。
- 原生根据当前显示尺寸换算坐标。
- 坐标动作必须存在最近一次截图，否则返回 `screenshot_required`。
- API 29 无法截图，因此坐标动作不可用；树和节点输入仍可用。
- 截图与输入之间发生包名、窗口、尺寸或旋转变化时返回 `stale_observation`，不静默重试。
- 坐标手势不比较整棵树内容，以适应动态画面；模型被要求在不确定时重新截图。

### 6.5 节点句柄生命周期

- `phone_agent_tree(offset: 0)` 创建一份新观测并重新编号，旧句柄失效。
- `offset > 0` 只继续当前观测分页，不重新遍历或编号。
- 截图使用独立状态，不清空树句柄。
- 句柄和观测 ID 仅存在原生内存，模型只看到 `n0`、`n1` 等短 ID。
- 默认 TTL 为 120 秒，超时、服务断开、窗口/包名/尺寸/旋转变化都会失效。
- 动作后不一刀切清空全部句柄；每次节点动作前执行目标 `refresh()`、可见性、可用性和指纹校验。
- 目标失效时返回 `stale_handle`，要求重新读树；不自动点击重新解析出的相似节点。
- 新读取、输入失败和系统错误都不得把旧句柄误指向另一个节点。

#### 6.5.1 指纹重验契约

指纹用于判断“句柄是否仍指向同一个逻辑节点”，不用于判断节点当前是否处于某个交互状态。当前契约：

| 字段 | 是否进入指纹 | 说明 |
|---|---|---|
| `windowId`、`packageName`、`className`、`viewId` | 是 | 节点身份与归属变化必须失效。 |
| `text`、`contentDescription`、`hintText`、`stateDescription` | 是（密码节点除外） | 内容变化视为目标变化。 |
| `isEnabled`、`isPassword`、`isEditable`、`isClickable`、`isLongClickable`、`isScrollable`、`isCheckable`、`isChecked` | 是 | 稳定能力或语义状态变化视为目标变化。 |
| `isSelected` | 是 | 选中状态变化仍返回 `stale_handle`；本轮不一次性放宽全部指纹字段。 |
| `isFocused` | 否 | 点击、聚焦和输入本身会改变焦点；同一已刷新节点的焦点变化不构成节点替换。 |
| `actions` | 否 | 聚焦等交互会增减动作集合；动作可用性由执行层在动作前按当前节点重新校验，不可用返回 `action_unavailable`。 |
| `bounds` | 否 | 允许布局漂移，坐标仍由模型按需重新截图或读树确认。 |

规则：

- 焦点或动作集合变化不失效只表示句柄仍可用，不表示动作成功；`performAction` 返回值仍只表示系统接受动作。
- 节点被真正替换、内容变化、稳定能力字段变化、`isSelected` 变化、窗口/包名/尺寸/旋转变化和 120 秒 TTL 超时仍返回 `stale_handle` 或 `stale_observation`。
- `stale_handle` 的错误信息会附带发生变化的指纹字段名（只含固定字段名，不含文本内容）；指纹是结构化字段列表，值只参与相等比较，不会被反解为字段名。
- 前置重验失败与指纹变化使用同一错误码 `stale_handle`，但消息中的诊断标识可区分来源：`refresh()` 返回 false 时为 `refresh_failed`，刷新成功但 `isVisibleToUser` 为 false 时为 `not_visible`，前两者通过但 `isEnabled` 为 false 时为 `not_enabled`。三者按该顺序短路判断，只输出固定标识，不输出节点文本、类名、viewId 或其他内容；诊断不改变任何通过条件，也不把失败自动转成重新读树或重试。
- 节点重解析（M24）：`refresh()` 返回 false 时，先按读树时记录的“从根到该节点的子索引路径”在当前活动窗口重新解析一次。这是**双重闸门**：路径可能因同一窗口内滚动而指向别的节点，但紧随其后的指纹逐字段全等比较会拒绝，除非存在结构完全等价的孪生节点（同包同窗口、同步长、同层、全部能力字段与文本字段相同）。并要求重新解析出的节点指纹与读树时逐字段完全一致；路径解析失败、节点不存在或任一指纹字段不等时仍返回 `stale_handle`（路径解析失败的消息保留 `refresh_failed`），不返回新句柄。该重解析只处理“平台重建了节点对象、逻辑节点未变”的情况：不按文本、描述或相似度查找节点，不放宽任何指纹字段，不改变可见性、可用性、TTL 和窗口/包名/尺寸/旋转校验，也不自动重试动作。
- 该决定由 `ObservationRegistryTest` 的 focus-only 复用、action-only 复用、selected-only 拒绝、稳定能力变化拒绝、三项前置诊断和重解析用例固定；放宽更多字段必须先更新本节、`AGENTS.md` 和 `mods/phone_agent/README.md`，并补对应测试。
- 该契约不保证节点始终有效，也不保证业务结果成功；模型仍应在页面明显变化时重新读树。

该策略允许模型在同一页执行多个相互独立的操作，但是否需要重新观察由任务语义决定。它不保证节点始终有效，也不保证业务结果成功。

### 6.6 错误码

`phone_control_disabled` 已不再使用，统一改为 `phone_agent_disabled`。首版文档明确使用的错误码包括：

- `phone_agent_disabled`：当前助手已不再启用 `phone_agent`；
- `screenshot_required`：坐标动作缺少最近一次截图；
- `stale_observation`：截图与输入之间窗口、包名、尺寸或旋转变化；
- `stale_handle`：节点句柄失效或无法重验；消息中的固定诊断标识 `refresh_failed`、`not_visible`、`not_enabled` 区分前置重验失败来源，指纹变化仍报告字段名；
- `rate_limited`：系统截图或手势限频；
- `screenshot_blocked`：平台明确返回截图错误（如无无障碍截图权限、无效显示/窗口、窗口级 secure 错误等）；整屏 `takeScreenshot` 不保证对 FLAG_SECURE 报错；
- `image_input_unsupported`：当前模型不支持图片输入；
- `unsupported_platform`：非 Android 平台；
- `timeout`：通道或原生调用超时；
- `plugin_unavailable`：插件不可用；
- `package_not_allowed`：目标包名属本次构建的 deny 成员（**仅表示构建期硬禁止**，不表示“用户未批准”；M33 起构建期范围是 deny 清单、初始为空）；**约束输入与观察**，排在用户白名单之前；
- `permission_required`：目标应用尚未获得用户批准（**M33 已实现**）；输入与观察（读树/截图）都返回该码，观察侧只带应用身份、不带树节点或截图；立即返回、不排队、不静默降级；
- `system_window_denied`：系统窗口、硬基线或窗口类型拒绝（锁屏仍返回 `device_locked`，不会走本码）；
- `device_locked`：设备锁屏或息屏；
- `budget_exceeded`：本次生成的动作预算超限。

其余错误码以适配层和插件返回为准。错误信息应给出可执行的下一步，例如重新截图、重新读树、在 Mods 页重新选择工具或请用户检查无障碍服务。

**当前实现（M33）**的输入路径错误码优先级固定为：空包名 → `no_window`；系统包 → `system_window_denied`；构建期 deny 成员 → `package_not_allowed`；未获用户批准 → `permission_required`；白名单内再校验句柄/截图，失效返回 `stale_handle` 或 `stale_observation`。因此系统窗口、deny 成员或未批准应用在前台时，即使句柄已经失效，也先返回包名策略错误，而不是句柄错误。锁屏/息屏在包名策略之前检查，所有方法（含读树和截图）返回 `device_locked`。

以上是**当前实现**的链。7.5 的判定已全部插入 `no_window` 之后：**硬基线与输入窗口类型（M27 第 1 步，见 7.5.2/7.5.3）**、**观察边界（M28 第 2 步，见 7.5.4）**、**构建期 deny 清单与用户白名单（M33，见 7.5.1/7.5.4/7.5.9）**。M33 起读树与截图也判 `package_not_allowed` 与用户白名单，未批准返回 `permission_required` 且只带应用身份。**审计元数据已由 M35 实现**（见 7.5.5 的「M35 实现事实」）；**批准交互（卡片/通知）、首次隐私确认与任务控制仍未实现**。

权限弹窗的处理边界（M20/M21 设备证伪 + M22 保守收尾）：

- API35 真实 `GrantPermissionsActivity` 弹窗期间，`rootInActiveWindow` 为 null；活动/聚焦弹窗窗口 `hasRoot=false`、`pkg=null`，`AccessibilityWindowInfo` 没有包名字段，服务也没有收到 `permissioncontroller` 的 `TYPE_WINDOW_STATE_CHANGED`。因此窗口 root 补全和事件来源包名两种识别机制均不可用，不实现。
- 该场景读树、截图和输入统一返回 `no_window`，错误消息只做条件式人工提示（“如果看到系统权限弹窗，请人工处理/取消，再返回测试应用”），不声称识别具体权限弹窗，也不把 `no_window` 写成权限场景的通过条件。
- 可取得系统包名的系统窗口仍按 `PackagePolicy` 返回 `system_window_denied`；错误优先级、读树/截图密码遮挡、白名单和输入边界不扩大。
- 异常测试的宿主 `dumpsys` 确认是测试前提，不是产品检测能力；测试不能仅因任意 `no_window` 通过，也不能因 `root=null` skip。

`system_window_denied`、`package_not_allowed` 和 `screenshot_blocked` 的适用范围必须区分：

- `system_window_denied` 同时约束**输入**与**观察**，但触发来源不同：输入层由硬基线 + 输入窗口类型 `{TYPE_APPLICATION}` 触发，观察层由硬基线 + 观察窗口类型 `{TYPE_APPLICATION, TYPE_INPUT_METHOD}` 触发（M28 第 2 步已实现，见 7.5.4）。M33 起读树与截图也判构建期 deny 清单与用户白名单，未批准应用的读树/截图返回 `permission_required`。
- `package_not_allowed` **M33 起约束输入与观察**，只对构建期 deny 清单成员出现（清单初始为空），排在用户白名单之前。「读树和截图不检查构建期白名单是 VLM 需要的行为」曾作为旧实现（M28）的理由，**该理由已被 M32 作废**（新理由：申请授权只需要应用身份，见 7.5.4）。
- `screenshot_blocked` 只表示平台明确返回的截图失败；整屏 `takeScreenshot` 成功返回的黑图不算 `screenshot_blocked`，也不表示读树或输入不可用。
- `device_locked` 同时约束读树、截图和输入。

整屏截图与 FLAG_SECURE 的边界（按证据层级区分）：

- 官方文档事实：`TakeScreenshotCallback.onFailure` 列出的错误码不包含 `ERROR_TAKE_SCREENSHOT_SECURE_WINDOW`；该码是 API 34+ 窗口级 `takeScreenshotOfWindow` 使用的错误。
- AOSP 补充：整屏 `takeScreenshot(Display.DEFAULT_DISPLAY)` 路径（`WindowManagerService.captureDisplay` → `ScreenCapture.captureLayers`）没有 secure 检查；失败只可能是限频、无无障碍截图权限、无效显示/窗口或内部错误。
- 设备观察（API35 模拟器）：同 UID 和不同 UID 的 `FLAG_SECURE` 夹具都返回 `ok:true` 和黑图（平均 RGB 约 2,0,2 / 3,0,5），没有 `screenshot_blocked`。因此不根据像素猜 secure，不承诺不发送黑图，正常黑色页面保留；平台明确报错时仍不得把图片或图片 metadata 交给模型。

## 7. 截图、隐私与技术护栏

### 7.1 截图与隐私

- 仅支持 Android API 30+ 的 `AccessibilityService.takeScreenshot`。
- API 29 截图返回 `unsupported_os`，不影响树和节点输入；页面在 `supported=false` 时显示截图限制。
- 服务 XML 必须声明 `android:canTakeScreenshot="true"`。
- 原生先缩放到长边不超过 1600，再传给 Dart，降低通道和图片上下文成本。
- Dart 使用 `McpImageSnapshot.saveBytes` 落盘，并校验落盘尺寸与原生声明一致；不一致则返回错误，不更新坐标观测。
- 系统限频映射为 `rate_limited`；平台明确返回的截图错误映射为 `screenshot_blocked`。整屏 `takeScreenshot` 不保证对 `FLAG_SECURE` 报错：secure 内容可能以黑色区域出现在成功截图中；不做像素启发式，不承诺不发送黑图，正常黑色页面保留。
- 平台明确报错时不得把图片或图片 metadata 交给模型；成功黑图只作为普通截图返回，模型应优先读树、不要凭黑图猜坐标。
- `FLAG_SECURE` 只阻止截图；它不会隐藏无障碍树，也不会阻止读树和输入。输入边界由包名白名单决定，不能把 secure window 描述成“不可读、不可操作”。secure 窗口的树在 API35 夹具上可读，但不是绝对保证；密码字段、自定义 View 和窗口变化仍会影响树。
- `isPassword` 节点及其子树文本不进入树结果；直接节点输入默认拒绝密码节点。
- 截图前按密码节点 bounds 涂黑。该遮挡依赖应用正确标记，自定义 View/WebView 可能遗漏，只能称为“尽力而为”。
- 截图前必须移除本 Mod 自己的可视化叠加层并等待两帧；隐藏失败返回 `screenshot_failed`，不得发送可能带叠加层的图片。密码窗口遍历只排除自身 accessibility overlay 窗口，不屏蔽其他应用窗口。
- 截图字节和密码文本不得写入日志或崩溃报告。

### 7.2 首版必须实现的技术护栏

- 单 worker 串行执行和手势单飞；
- 每次调用及实际执行前的锁屏/息屏检查；
- 服务中断时完成所有 pending 请求，不再执行排队动作；
- 节点、窗口、包名、尺寸、旋转和时效校验；
- 有界节点遍历、分页和文本预算；
- 截图、读树、手势和通道调用超时；
- 每次生成过程中的动作预算和速率限制；
- 默认仅允许显式配置的测试包名，当前为独立测试应用 `com.psyche.kelivo.phoneagent`；开发者只能在私有 Mod 中编辑白名单；
- 输入与观察请求拒绝可取得包名的系统窗口、硬基线包与不允许的窗口类型（`system_window_denied`）；无可访问 root 的权限弹窗保持 `no_window` 并只做条件式人工提示；锁屏/息屏时读树、截图和输入都返回 `device_locked`；**当前实现**中读树和截图**不检查**构建期包名白名单，仍可观察普通第三方应用的前台窗口（M32 已定（用户拍板）、未实现：未批准应用的读树与截图改为返回 `permission_required` 与只含应用身份的结果，见 7.5.4）；
- `home`/`recents` 执行后前台会离开白名单，**后续输入（包括 `back`）被拒绝**，模型无法自行把测试应用切回前台，需要用户或宿主动作恢复。但**读树与截图仍会成功**：API35 实测 `home`/`recents` 后前台是启动器（`com.google.android.apps.nexuslauncher`，`TYPE_APPLICATION`），而观察边界不判构建期白名单，只判硬基线与窗口类型。反过来说，“前台是 systemui / `TYPE_SYSTEM` 所以读树被拒”只适用于**通知栏**场景；而且由于 `com.android.systemui` 本身就在硬基线集合内、硬基线判定先于窗口类型，该场景返回的标识是 `hard_baseline`，**不会**是 `window_type_system`（详见 7.6 风险 2 的实测修正）。
- 结构化错误包含可执行的下一步，而非只返回笼统失败。

### 7.3 工具选择与服务授权边界

- Mods 页的三态选择是工具配置，不是无障碍授权。选择 Phone Agent 不会自动启用 `PhoneAgentService`，选择原生手机控制也不会自动启用 `PhoneControlService`。
- 两个服务继续共存，各自在系统无障碍设置中独立授权；Mod 不自动打开系统开关、不静默提权、不绕过系统确认。
- 服务状态面板只读取状态，不修改系统设置；刷新失败或状态过期时，以系统设置和工具返回的结构化错误为准。
- 用户关闭工具选择不会自动关闭系统服务；用户停用系统服务也不会自动改写助手工具选择。
- 上游手机控制授权页继续由上游维护；Mod 不把 Phone Agent 的授权伪装成上游授权。

### 7.4 不属于硬保证的事项

- `performAction` 或手势回调代表业务成功；
- 密码遮挡覆盖所有应用；
- 异步截图间隔内同一活动窗口新出现密码字段、非活动分屏窗口变化或同窗口分屏 resize 仍被遮挡（gate 后和 `takeScreenshot` 回调后各比较一次窗口，但不保证窗口内容原子不变）；
- 节点校验消除所有竞态；
- 模型会遵守“发送/购买/删除前询问”的提示；
- 白名单应用内部不会发生危险操作；
- 已经发出的系统调用可以撤回；
- 两个服务同时启用时不会产生任何系统级干扰；
- `FLAG_SECURE` 会阻止读树或输入（它只阻止截图）；
- 整屏截图会检测 `FLAG_SECURE` 或不发送黑图（可能成功返回黑图）；
- `home`/`recents` 之后模型能自行回到测试应用（前台离开白名单后输入会被拒绝）；
- 观察层能准确识别每一个应被拒绝的窗口：窗口类型只能按 `windowId` 从 `windows` 解析，解析失败一律落 `UNKNOWN` 并拒绝观察（fail closed），代价是正常应用也可能被拒；
- 输入法窗口的读树结果对模型有用（该窗口可被观察，但拿到的可能是键盘与候选词，而非目标应用界面；未经实测）；
- 权限弹窗一定能被识别为 `system_window_denied` 或被观察层当作系统窗口拒绝（API35 实测无可访问 root 且无来源包名，读树/截图/输入仍为 `no_window`，只做条件式人工提示）；
- 批准某个应用之后，该应用界面里的危险操作会被阻止（批准只表示用户允许助手看与操作，不改变应用内部的安全语义）；
- 批准之后界面文本不会外发（已批准应用的读树与截图仍是工作前提，仍不承诺不泄漏其自身界面文本；M32 契约只把“不设防范围”收缩到已批准应用）；
- 首次隐私确认能阻止任何数据外发（它是告知，不是技术控制）；
- 撤销授权能撤回已经发出的动作或已注入的手势（系统层没有这个能力）；
- 可视化叠加层动画代表业务成功、任务进度或用户审批（它只表示系统接受或完成动作）；
- 可视化叠加层在所有 Android 厂商设备上都可用（`addView` 可能失败，失败时只禁用可视化）；
- 上游后台胶囊会被叠加层隐藏或免于干扰（Mod 无法操作其他 owner 的窗口）。

真正需要逐步授权时，应后续增加“每个动作均由原生确认”的模式，而不是依赖危险文本识别。

### 7.5 应用边界与应用授权（第 1–5 步、审计与批准交互均已实现；任务控制与结果未知语义未实现）

> **状态分层，不要混读。** 本节同时包含**四层不同状态**的内容，阅读时必须区分：
>
> - **已实现（M27 第 1 步）**：输入路径的硬基线（静态系统包集合含 settings 与厂商变体、运行时角色持有者解析、精确包名 `com.psyche.kelivo`）与窗口类型判定（输入允许集 `{TYPE_APPLICATION}`），集中在纯函数 `PackagePolicy`（`mods/phone_agent/plugin/android/src/main/kotlin/com/kelivo/phoneagent/AppBoundary.kt`）与 `WindowState.windowType`。
> - **已实现（M28 第 2 步）**：观察边界（静态硬基线 + 观察窗口类型 `{TYPE_APPLICATION, TYPE_INPUT_METHOD}`），接入 `readTree()` 与截图路径；异常套件对应的 5 处依赖同批改为宿主 `dumpsys` 确认。
> - **已实现（M33，契约落地）**：`QUERY_ALL_PACKAGES` 一次声明、`(包名, 签名集合)` 双匹配的用户白名单（本地存储、幂等写入、撤销立即生效）、构建期范围从 allowlist 转为 **deny 清单**（初始为空）、构建配置预批准条目（测试包恒预批准，debuggable 构建额外预批准跨 UID 夹具包）、观察与输入两条路径都判构建期 deny 清单并都返回 `permission_required`。**未批准时只返回应用身份，不建立观测、不占 `treeBudget`、不截图。** 原生批准/撤销/查询通道面已实现（`approvedApps` / `approveApp` / `revokeApp`），但**没有任何 UI**。
> - **已实现（M35，审计元数据）**：审计落盘只写七项元数据（时间戳、助手 id、会话 id、包名、签名哈希前 8 位、动作类型、结果码），滚动保留 30 天或最近 2000 条，写在 `noBackupFilesDir/phone_agent_audit.tsv`，不进入工具结果、不发给模型、不上传。助手/会话 id 由 Dart 调用侧传入，缺失记 null。**不得据此宣称审计不涉及隐私。** 详见 7.5.5 的「M35 实现事实」。
> - **M34 已实现（批准交互与首次隐私确认；无设备证据）**：聊天批准卡片、通知栏批准 action、pending 请求状态机（TTL 30 分钟、单终态、迟到回调不写白名单）、`permission_required` 的结构化身份、Mods 页“已批准的应用”管理页、首次启用隐私确认（方案 B）。**仍未实现**：任务控制（同时只一个任务控制手机）、结果未知语义的专门文案与错误码、多窗口首版策略。后者属**设计提案（tower 建议）**，不是用户拍板项，逐条来源见 7.5.9 的四档定义；审计已由 M35 实现。
>
> **批准 UI 在 M34 已接入两条渲染路径**（助手时间线的思考步骤 `_ChainOfThoughtToolStepState` 与独立工具消息 `_ToolCallItem`），两者都用 `PhoneAgentApprovalCard.pendingExists()` 参与内容区判定。但**它只有单元与 widget 测试证据，没有任何设备证据**：9.4/10.1 的旧 VLM 结果不能用于宣称新契约已验证。

#### 7.5.1 方向

- **默认拒绝**：任何未明确允许的目标一律拒绝，不做黑名单式放行。
- **批准 = 读＋操作一体（已定（用户拍板），M33 已实现）**：批准同时覆盖读树/截图与输入，不存在“只批准看”“只批准点”两种粒度。未批准应用的读树与截图只返回应用身份与授权请求，不返回树节点、截图或界面内容（见 7.5.4）。理由见 7.5.4：申请授权只需要应用身份，不需要先读内容。
- 白名单条目绑定 **`(包名, 签名证书哈希)`**，两者必须同时匹配；包名匹配但签名不符视为未批准。这样可避免“同名包换签名后继承旧授权”。M33 落地为**签名证书 SHA-256 的排序去重集合**：单签名包即一项，多签名包（实测 `com.android.vending` 为 2 项）必须整集合相等，任一枚新增或替换都算变化。
- 硬基线**不可由用户开关覆盖**，Mods 页不提供关闭硬基线的选项。
- 判定全部在**原生侧**完成，Dart 只做错误码映射与展示；Dart 侧不得成为可绕过的放行点。

判定顺序固定（插在既有链中，先命中者生效）：

`device_locked` → `no_window` → **硬基线** → **窗口类型** → 构建期硬禁止（`package_not_allowed`）→ **用户白名单**（`permission_required`）→ 句柄/截图校验（`stale_handle` / `stale_observation`）。

锁屏仍最优先，因为它在任何读窗口动作之前就要短路；`no_window` 仍是“拿不到可访问窗口”的统一出口，不由新层替代。构建期硬禁止不属于“三层判定”，它排在用户白名单之前：本次构建根本不支持的包不应被展示成“可以批准”。**M33 起整条链在输入与观察两条路径上都已生效**（观察层仍不查角色持有者）。

**M32 修订后的适用面（M33 已实现）**：上述顺序对**输入与观察两条路径都生效**，但两条路径各自只取自己需要的层——观察层仍**不查询角色持有者**（角色是输入边界，见 7.5.3/7.5.4），输入层仍不做截图相关校验。硬基线与窗口类型在两条路径上都排在用户白名单**之前**，因此「批准一个系统应用」既不必要也不可能：它在白名单判定前就被拒绝，且 `system_window_denied` 与 `permission_required` 语义不同（前者“永远不行”，后者“可以批准”）。

**观察侧也判构建期硬禁止（已定（M32，tower 定论，用户可推翻），M33 已实现）**：观察路径的顺序里**包含**构建期硬禁止（`package_not_allowed`），与输入路径一致。理由：批准 = 读＋操作一体（用户拍板），而本次构建根本不支持操作的应用**不应该产生批准提示**——让用户批准一个「批准了也操作不了」的应用是纯粹的误导。代价是 `package_not_allowed` 的适用范围从「仅输入」扩到「输入与观察」，6.6 与 7.5.8 已同步。该项由 tower 本轮定论，**用户可推翻**；推翻时须同时收回 7.5.4 观察顺序里的这一层、恢复 6.6/7.5.8/README 的「仅输入」表述，并改写本节。

**构建期范围已转为 deny 清单（已定（M32，tower 定论，用户可推翻），M33 已实现）**：构建期 allowlist 的语义**从「allowlist（只放测试包）」转为「deny 清单（只保留明确不支持或危险的包）」**。

- **规则**：`PackagePolicy` 的构建期判定改成 deny 成员判定——**`package_not_allowed` 只对 deny 清单成员出现**；其余第三方应用不因构建期范围被拒，直接进入用户白名单判定，未批准返回 `permission_required`。
- **理由（是可达性问题，不是风格问题）**：产品目标是操作真实应用，而「批准 = 读＋操作一体」又是用户拍板的方向。若维持「只允许测试包」的 allowlist 旧语义，则测试包被直接视为已批准、其他第三方包全部命中 `package_not_allowed`，**`permission_required` 在任何输入上都不可达**——批准卡片、通知栏批准、Mods 页撤销、「允许并继续」全部没有触发入口，P6 的完成条件（设备跑通「未批准 → 只回身份 → 批准 → 重新观察 → 撤销 → 重新 `permission_required`」）也就不可能达成。1.3 非目标又把「运行时编辑构建期测试包白名单」列为首版不做，等于没有运行时补救路径。
- **deny 清单保留什么**：只保留**明确不支持或危险**的包。硬基线（systemui、权限控制器、包安装器、证书安装器、settings 及厂商变体、电话/短信角色持有者、Kelivo 自身）**不在 deny 清单里**，它们由更早的硬基线层返回 `system_window_denied`，两套机制不要混为一谈。
- **具体成员尚未定稿（设计提案，待定）**：首版 deny 清单的成员清单需要在实现阶段确定并写进本文；tower 的建议是**初始为空**，只有确认某包必须硬禁止（例如已知会自我提权的工具类包）时才加入。**不得据此写成“deny 清单已确定”**，也不得把硬基线集合复制进来充数。**M33 实现为空的 `DENY_PACKAGES`**，并有 JVM 断言固定“初始为空、且不与硬基线集合重叠”；成员清单仍属未定稿的设计提案，不是用户决策。
- **与既有层的关系不变**：判定顺序仍是 `device_locked` → `no_window` → 硬基线 → 窗口类型 → 构建期硬禁止（此时即 deny 成员判定）→ 用户白名单。硬基线与窗口类型排在前面、系统窗口无条件拒绝这两点不受本项影响。
- **当前实现（M33）**：已是 deny 清单语义（`AppBoundary.kt` 的 `denyPackages` 默认 `DENY_PACKAGES`，初始为空）。因此除 deny 成员外的第三方应用都走到用户白名单，未批准返回 `permission_required`；构建配置的预批准条目（见下）直接放行。
- **构建配置预批准条目（M33 已实现）**：测试包 `com.psyche.kelivo.phoneagent` **恒为预批准**（任何构建）；跨 UID 的 `FLAG_SECURE` 夹具包 `com.kelivo.phoneagent.securefixture` **只在 debuggable 构建预批准**。两者都不写用户白名单、不产生批准提示、在 Mods 页不可撤销，也不影响其他应用 `permission_required` 的可达性。release 不预批准夹具包名，避免同名第三方包被静默放行。
- **来源与推翻连带**：tower 本轮定论，**不是**用户 AskUserQuestion 拍板项，**用户可推翻**。推翻时须同时：恢复 allowlist 语义、重写本段、改写 7.5.8/10.1/10.2 里「未批准 → `permission_required`」的表述为「仅对已在本构建支持集内、但未获用户批准的应用返回 `permission_required`」、同步 `AGENTS.md` 与 `README.md` 的错误码分界，并把 P6 的完成条件改成可达链路（例如把测试包从构建期范围移除、改走用户白名单）。

**第 1 步的实际实现顺序**（`PackagePolicy.requireInputAllowed`，先命中者生效，均有 JVM 断言）：

`no_window` → 静态硬基线（含 Kelivo 精确包名）→ 角色解析失败 → 角色持有者 → 窗口类型 → 构建期 deny 清单（`package_not_allowed`）→ 用户白名单（`permission_required`）。

与上图的两点差异如实记录：（a）“角色解析失败”被提前到角色持有者与窗口类型之前，因为解析失败时无法判断目标是不是电话/短信，宁可报 `system_window_denied`（标识 `role_resolution_failed`）；（b）静态硬基线与 Kelivo 自身放在同一判断里，都返回 `system_window_denied`，消息里分别带 `hard_baseline` 标识或用例可区分包名。**M33 起输入路径的用户白名单层存在**，未批准返回 `permission_required`。

#### 7.5.2 三层判定

| 层 | 判定依据 | 约束范围（M33 已实现） | 失败码 | 用户可否覆盖 |
|---|---|---|---|---|
| 1 硬基线 | 固定系统包名 + 角色解析结果 + 承载助手的 Kelivo 包 | 输入与观察 | `system_window_denied` | 否 |
| 2 窗口类型 | `AccessibilityWindowInfo.type` | 输入与观察（集合不同，见 7.5.3） | `system_window_denied` | 否 |
| 3 用户白名单 | `(包名, 签名证书集合哈希)` | **输入与观察（批准 = 读＋操作一体）** | `permission_required` | 是（原生撤销通道；Mods 页 UI 未实现） |

第 3 层的「约束范围」由 M32 修订为**输入与观察一体**（旧契约写「仅输入」），**M33 已按新契约实现**：观察路径与输入路径都判用户白名单，未批准时只返回应用身份。

**第 1 层 硬基线**（用户不可覆盖）：

- systemui、权限控制器（`com.android.permissioncontroller` / `com.google.android.permissioncontroller`）、包安装器（`com.android.packageinstaller` / `com.google.android.packageinstaller`）；
- **`com.android.settings` 及其厂商变体**（如 MIUI 的设置包）：该包是“用现有权限扩大权限”的入口，必须整包禁止；
- 电话/短信核心应用：按系统角色解析默认电话、默认短信持有者；
- 承载助手的 Kelivo 包 `com.psyche.kelivo`：批准卡片本身就在这个包里，允许输入等于让模型点自己的批准按钮。

硬基线失败仍返回 **`system_window_denied`**，**不新增错误码**。落地方式分三种，不能用一句“补进集合”概括：静态系统包集合补入 settings 及厂商变体；“电话/短信角色持有者”需要运行时解析默认电话/短信持有者；“Kelivo 自身”是按精确包名 `com.psyche.kelivo` 的硬编码判定，不需要也无法通过角色解析。后两类在策略层另行判定。现有 `PackagePolicyTest` 的**错误码断言不变**，但调用签名会随纯函数改造增加窗口类型（及白名单）参数。

**第 1 步已实现的部分（M27）**：

- 静态集合 `HARD_BASELINE_PACKAGES`（`AppBoundary.kt`）在原 5 个 AOSP 包基础上补入：
  - 权限控制器 `com.lbe.security.miui`（MIUI 持有 `GrantPermissionsActivity` / `ReviewPermissionsActivity`）；
  - 包安装器 `com.miui.packageinstaller`（MIUI 同时持有 `InstallStart` 与 `UninstallStart`）；
  - 证书安装器 `com.android.certinstaller`（`android.credentials.INSTALL`）；
  - 设置与变体 `com.android.settings`、`com.google.android.settings`、`com.samsung.android.settings`、`com.miui.securitycenter`、`com.xiaomi.misettings`、`com.coloros.settings`、`com.coloros.safecenter`、`com.oplus.settings`、`com.oplus.safecenter`、`com.vivo.settings`、`com.bbk.settings`、`com.huawei.systemmanager`、`com.hihonor.systemmanager`。
- **厂商枚举的补全流程（不是“尽力而为”就完了）**：新增厂商支持时必须在该机型的真机上用只读命令实测，把解析到安装、卸载、权限授予、证书安装或设置的包名逐个补进集合——`adb shell cmd package resolve-activity --brief -a android.intent.action.INSTALL_PACKAGE`、`-a android.intent.action.DELETE`、`-a android.intent.action.MAIN -c android.intent.category.LAUNCHER -n <settings>`、`-a android.credentials.INSTALL`，以及 `adb shell dumpsys package <pkg> | grep -i -E 'GrantPermissions|ReviewPermissions|InstallStart|UninstallStart|INSTALL'`。**只凭厂商命名习惯猜包名不算补全**。
- **风险要写醒目**：漏写一个入口 = 该入口在该构建里按普通应用处理。**M33 起构建期范围已是 deny 清单**（`DENY_PACKAGES` 初始为空），所以漏写的入口**今天不会**被 `package_not_allowed` 拒绝，而是落到用户白名单判定、返回 `permission_required`；已补进集合的入口返回 `system_window_denied`（硬基线判定排在构建期判定之前），两者错误码不同、语义也不同。而 `approveApp` 通道**已经上线**，因此这是一个**当下可达**的缺口：用户批准该厂商设置包后，它就能被读树、截图与输入——不是“等批准 UI 上线才出现”。批准 UI（M34）只是把这个缺口变得用户可操作、更容易踩到，不是它的起点。因此按上述流程把目标机型补全、并把已补包名列成清单，是**批准 UI 上线前必须完成的前置条件**，不是“以后再说”。
- 角色持有者按 `RoleHolders` 建模，只有 `Resolved(packages)` 与 `Unavailable` 两种。`PhoneAgentService.resolveRoleHolders()` **在所有 API 版本统一使用**公共等价接口 `TelecomManager.defaultDialerPackage`（对应 `ROLE_DIALER`）与 `Telephony.Sms.getDefaultSmsPackage(this)`（对应 `ROLE_SMS`），没有 `RoleManager` 分支，也没有版本分支。原因：`RoleManager.getRoleHolders` 是 @SystemApi（`MANAGE_ROLE_HOLDERS` 签名权限），公共 SDK 无法编译（实测 `Unresolved reference 'getRoleHolders'`）。
- 区分两种失败：查询抛异常或 `TelecomManager` 服务缺失表示“不知道”，返回 `Unavailable`，策略层据此**拒绝全部输入**（`system_window_denied`，消息标识 `role_resolution_failed`）；查询返回 null 表示系统明确回答“没有该角色的默认应用”（例如无短信能力的平板），归入 `Resolved(emptySet())`，不封死这类设备。不把“解析失败”当成“没有持有者”。
- Kelivo 自身按 `KELIVO_PACKAGE = "com.psyche.kelivo"` 精确比较，测试包 `TEST_PACKAGE = "com.psyche.kelivo.phoneagent"` 独立常量；有专门用例断言测试包不被前缀/contains 规则误伤。

权限弹窗不因本层改变：API35 实测该窗口 `hasRoot=false`、`pkg=null`，在到达硬基线判定前就以 `no_window` 退出（见 6.6 与 9.3.6）。硬基线只在能取得包名时生效，不能把 `no_window` 改写成 `system_window_denied`。

注意一个实现陷阱：私有测试应用 `com.psyche.kelivo.phoneagent` 是**构建期测试白名单成员**，不是硬基线成员。若把“Kelivo 自身”写成包名前缀匹配或按包名 `contains` 判断，测试应用会自我阻断，集成测试全线失败。两者必须按精确包名区分。

**第 2 层 窗口类型**：见 7.5.3。

**第 3 层 用户白名单**：

- 条目为 `(packageName, signingCertSha256)`，签名取该包当前签名证书的 SHA-256；应用身份的取得方式、同签名更新与签名变化的处理见 7.5.9。
- 未命中返回 **`permission_required`**（新码，见 7.5.7）：不执行、不排队、不静默降级。**观察路径（读树与截图）M33 起也走这一层**：未批准时同样返回 `permission_required`，结果里只有应用身份与授权请求，不含树节点、截图或界面内容（见 7.5.4）。
- `package_not_allowed` **保留为构建期硬禁止语义**——M33 起表示「本次构建明确拒绝的 deny 成员」（见 7.5.1）；不参与运行时用户白名单，两者不得混用，否则无法区分“用户还没批准”和“这个 build 根本不允许”。
- **观察侧也判 `package_not_allowed`（已定（M32，tower 定论，用户可推翻），M33 已实现，见 7.5.1）**：观察路径的顺序里包含构建期硬禁止，理由是"批准了也操作不了的应用不应产生批准提示"。因此 `package_not_allowed` 的适用范围是**输入与观察**，不再是"仅输入"；6.6/7.5.8/README 的错误码分界已同步。

#### 7.5.3 窗口类型两层判定的不对称性

| 窗口类型 | 允许输入 | 允许观察（读树/截图） |
|---|---|---|
| `TYPE_APPLICATION` | 是 | 是 |
| `TYPE_INPUT_METHOD` | **否** | 是 |
| `TYPE_SYSTEM` | **否** | **否** |
| `TYPE_ACCESSIBILITY_OVERLAY` | **否** | **否** |
| 其他类型 / 未知 | **否** | **否** |

即：**输入允许集 = `{TYPE_APPLICATION}`；观察允许集 = `{TYPE_APPLICATION, TYPE_INPUT_METHOD}`**。输入拒绝集严格大于观察拒绝集，多出的正是 `TYPE_INPUT_METHOD`。未知或厂商扩展类型按默认拒绝处理（等价于“不属于允许集”），不采用黑名单枚举。

失败码复用 `system_window_denied`，消息只追加固定标识 `window_type_system` / `window_type_ime` / `window_type_overlay`（与 6.5.1 的 `refresh_failed` 同风格），不含窗口标题、类名或节点内容。第 1 步另外定义了 `window_type_split_divider`（`TYPE_SPLIT_SCREEN_DIVIDER`）与 `window_type_unknown`（其他任何取值，含平台新增类型和匹配失败），两者都按默认拒绝处理；不采用黑名单枚举，因此新类型自动落入 `window_type_unknown` 而不是被放行。

**第 1 步已实现（M27）**：`WindowType`（`AppBoundary.kt`）把 `AccessibilityWindowInfo.TYPE_*` 整数常量映射为枚举，`fromPlatformType` 的 `else` 分支统一返回 `UNKNOWN`；`allowsInput` 只对 `APPLICATION` 为 true。判定在 `PackagePolicy.requireInputAllowed` 内完成，编号与平台常量一致（1/2/3/4/5），有 JVM 断言覆盖 `0` 与 `99` 两个未定义取值。

**第 2 步已实现（M28）**：同一 `WindowType` 增加 `allowsObservation`（仅 `APPLICATION` 与 `INPUT_METHOD` 为 true），判定由 `PackagePolicy.requireObservable` 在读树与截图路径各调用一次；观察拒绝消息复用 `denialTag` 的固定标识，对 `INPUT_METHOD` 不产生任何标识（它不在拒绝集内）。`allowsObservation` 与 `allowsInput` 是同一枚举上的两个独立属性，没有“观察允许集 = 输入允许集的补集”这类推导可替代：`INPUT_METHOD` 允许观察、拒绝输入，其余四类（`SYSTEM`、`ACCESSIBILITY_OVERLAY`、`SPLIT_SCREEN_DIVIDER`、`UNKNOWN`）两者都拒绝。

**为什么必须两层都判**：

- 只看包名会漏掉“类型敏感但包名普通”的窗口。典型是输入法：默认输入法窗口挂在自己的包名下，若用户或开发者把它加进白名单，仅靠包名就放行了输入；其他无障碍服务绘制的 overlay 窗口同样以普通应用包名出现。
- 只看类型会漏掉 `com.android.settings`：它是 `TYPE_APPLICATION`，类型层看来完全正常，必须靠硬基线拦。
- 两层是**交集关系**（都必须通过），不是二选一。

**为什么输入拒绝集可以比观察拒绝集大**：输入法窗口经常活动并覆盖在前台应用上。若观察也拒绝 `TYPE_INPUT_METHOD`，读树会直接失败、模型连正在输入的界面都看不到，这是典型反向误伤。反之，对输入法窗口本身做 tap / `set_text` 属于系统输入面操作，超出“操作目标应用”的边界，必须拒绝。

#### 7.5.4 受批准约束的观察边界（M32 修订契约；M33 已实现）

> **三层状态，必须逐条分清。**
>
> 1. **已实现（M33）**：**批准 = 读＋操作一体**。未批准第三方应用的 `readTree` 与 `screenshot` **只返回应用身份与 `permission_required` 授权请求**，不返回树节点、截图或界面内容；未批准时不再建立观测。
> 2. **已实现（M28 第 2 步）**：观察层判硬基线与窗口类型；M33 在其后追加构建期 deny 清单与用户白名单。
> 3. **不变**：硬基线与窗口类型仍排在白名单之前（系统窗口无条件拒绝，不因批准而放行）；`device_locked` → `no_window` 的既有优先级不变。

**为什么方向反过来（新理由，替换旧理由）**：旧理由写的是“模型必须先看到内容才能向用户解释为何需要授权”，因此观察不设白名单。M32 的关键判断是：**申请授权只需要应用身份，不需要先读内容**。前台窗口的包名（及签名哈希前缀）足以让用户判断“要不要让助手操作这个应用”，读到的界面文本对这次授权决策不是必要条件，反而是未被批准时最不该外发的东西——它与截图一样会被发送给用户配置的 provider。因此旧理由不成立，观察不再是白名单的豁免通道。

**契约细节（M33 已实现）**：

- **返回内容**：`readTree` 与 `screenshot` 在未批准时返回 `permission_required`，结果里只包含**应用身份**——前台包名、该包签名证书 SHA-256 的前 8 位十六进制字符（供用户核对是否同一应用），以及可选的由 `PackageManager` 取得的应用显示名（仅用于错误消息，不单独作为字段返回）。**不返回**节点树、节点文本、密码字段信息、截图字节或图片 metadata、窗口标题、类名、界面内容摘要。签名解析失败时消息只写 `signing_unavailable`，不写任何哈希。
- **不建立观测（已实现）**：门控在 `treeBudget` 扣减与 `registry.beginTree` **之前**抛出，因此未批准时不占用 `treeBudget`、不产生节点句柄；截图路径在 `takeScreenshot` 与 `collectPasswordBounds` **之前**抛出，不产生 `CapturedScreenshot` 槽位，也不会替换已有坐标观测。
- **不降级**：不返回空树、不返回“仅根节点”、不返回黑图或占位图。模型必须能从错误码区分“可以批准”（`permission_required`）与“永远不行”（`system_window_denied`）。
- **判定顺序（观察路径，M33 已实现）**：`device_locked` → `no_window` → 硬基线 → 窗口类型 → 构建期 deny 清单 → **用户白名单（未批准即 `permission_required`）**。硬基线与窗口类型命中时仍返回 `system_window_denied`，不会因为“用户没批准”而改报 `permission_required`——否则用户会以为批准就能看系统窗口。权限弹窗仍是 `no_window`（`rootInActiveWindow == null`，走不到白名单层），不得改成 `permission_required` 或 `system_window_denied`。
- **输入法窗口**：观察允许集仍含 `TYPE_INPUT_METHOD`，白名单门控对输入法窗口同样生效（按输入法自身包名判）。未批准时读树返回 `permission_required` 而不是输入法的键盘/候选词树；批准后行为与 M28 一致。**这条仍未实测**——输入法窗口成为 `rootInActiveWindow` 时读树结果是否有用仍未知（见本节末未验证假设）。
- **分页（`offset > 0`）：M33 实现为不重复判定**（沿用 M28 的接入点：门控只在 `offset == 0` 那次执行）。M32 曾把它列为「设计提案：分页也执行一次」，但**未定稿为契约**；M33 的实现选择沿用了既有接入点并保持 `registry.page()` 的完整 `WindowState` 比较。未批准时不存在可复用观测，所以 `offset > 0` 会落到 `stale_observation`（“No current tree observation”）而不是 `permission_required`；因为 `offset == 0` 已经给出 `permission_required`，模型不会通过翻页绕过门控。等 M34 之后若要改成分页也判定，需要同时改本节与 JVM 断言。
- **撤销的生效范围（必须先读清，不得写成“下一次调用一定 `permission_required`”）**：因为门控只在 `offset == 0`，撤销后的实际效果是——**`offset == 0` 的新读树、全部截图路径、全部输入动作**都会在下一次判定重新读存储并立即返回 `permission_required`；但**撤销前已建立的树观测，在 120 秒 TTL 到期或窗口变化之前，`offset > 0` 分页仍会成功回放那份旧树**（既不 `permission_required` 也不 `stale_observation`）。这不构成绕过：分页只回放撤销前已经读到的内容，不会读到撤销后的新内容，任何新的读树、截图或输入都会被拒。JVM 层未专门断言该分页路径（门控不在分页分支，属既有 M28 行为），已验证的是“撤销后 `offset == 0` 与输入立即 `permission_required`”。
- **截图顺序（已实现）**：取前台 `WindowState` → `requireObservable`（硬基线/窗口类型 → deny 清单 → 白名单）→ `collectPasswordBounds` 全窗口遍历 → 截图。遮挡遍历的范围与规则不因白名单门控改变；门控不读节点内容、不读密码 bounds，遮挡遍历也不感知白名单。

**实现事实（M33）**：

**实现入口**：`PackagePolicy.requireObservable(packageName, windowType)`（`AppBoundary.kt`）。它与 `requireInputAllowed` 共用同一个 `HARD_BASELINE_PACKAGES`、同一个 `denyPackages`、同一个 `preApprovedPackages` 与同一个 `AppApprovals`（白名单存储 + 当前签名解析），**不接收也不查询 `RoleHolders`**——电话/短信角色是“可操作哪些应用”的输入边界，与“能看到哪些窗口”无关；观察层因此不因角色解析失败而整体封死（那会让 `readTree` 在所有设备上随机失败）。判定顺序固定为：

`no_window` → 静态硬基线（含 Kelivo 精确包名）→ 观察窗口类型 `{APPLICATION, INPUT_METHOD}` → 构建期 deny 清单 → 用户白名单。

- 空包名或空白包名返回 `no_window`，与读树原有的“无可访问窗口”语义合并，不新增错误码。
- 硬基线命中返回 `system_window_denied`，消息带固定标识 `hard_baseline`，含包名（与输入层同格式）。
- 窗口类型不在观察允许集内返回 `system_window_denied`，消息只追加 `WindowType.denialTag` 的固定标识（`window_type_system` / `window_type_overlay` / `window_type_split_divider` / `window_type_unknown`），**不含窗口标题、类名、节点内容或坐标**。
- 构建期 deny 成员返回 `package_not_allowed`（标识 `build_denied`），排在用户白名单之前。
- 未批准（含签名变化、签名解析失败）返回 `permission_required`，消息只含包名与签名前缀（解析失败时是 `signing_unavailable`）。
- 构建配置预批准条目（测试包恒预批准，debuggable 构建额外预批准 `com.kelivo.phoneagent.securefixture`）直接放行，**不写用户白名单、不产生批准提示、不可撤销**。

**接入点（两处，各一次）**：

- `PhoneAgentService.readTree()`：在 `rootInActiveWindow` 取到 root 并构造出 `WindowState` 之后、`treeBudget` 扣减与 `registry.beginTree` 之前调用。**分页请求（`offset > 0`）不重复判定**（见上文分页条）。
- `PhoneAgentService.captureScreenshot()`：见下方顺序约束。

**当前的能力边界声明（M33 之后）**：

- **未批准应用不再把界面文本或截图送进模型与 provider。** “应用自身界面文本不设防”的范围收缩到**已批准应用**；对已批准应用，读树与截图仍是工作前提，因此**仍不承诺不泄漏已批准应用自身的界面文本**。
- 这不等于隐私默认安全：包名与签名哈希前缀仍会外发（作为身份），请求本身仍会到达用户配置的 provider；密码遮挡、`FLAG_SECURE`、叠加层等既有边界不受本契约影响。
- 通知栏本身被阻断，**不等于**通知内容不会泄漏——同一条通知的文字可能同时出现在第三方应用自己的界面里，而那属于应用自身界面（批准后同一应用的通知中心仍可读）。
- 密码节点文本仍按 7.1 隐藏，密码遮挡仍是“尽力而为”，本实现不把密码防护计入白名单方案的收益。
- 观察边界同样**不承诺**“输入法窗口一定能被观察到”：类型解析依赖 `windows` 枚举，解析失败落到 `UNKNOWN` 并拒绝（fail closed）。可观察不等于可用——输入仍只允许 `TYPE_APPLICATION`。
- 首次启用时的隐私提示（7.5.14）**仍未实现**；审计元数据（7.5.5）已由 M35 实现（七字段、30 天/2000 条滚动、本地文件、不进工具结果）。

**截图的前台判定必须先于且独立于全窗口密码遮挡遍历（已实现，不变）**：

- 顺序固定为：取前台 `WindowState` → **`requireObservable`** → 通过后才执行 `collectPasswordBounds` 全窗口遍历 → 截图。实现为 `captureScreenshot()` 里连续三段代码：`windowState(root)` → `requireObservable(...)` → `collectPasswordBounds(current)`。
- `collectPasswordBounds`（`PhoneAgentService.kt`）读的是**所有**窗口的 root，不能因为前台被拒就缩窄遍历范围，也不能把“前台不合格”当成“不用遮挡”。前台被拒时**根本不会进入**遮挡遍历（截图直接失败、不发图），遮挡遍历的输入参数与遍历范围保持原样，不因新增判定而收窄。
- 两者必须在代码上是独立步骤：遮挡遍历只按密码节点与自身 overlay 规则工作，不感知边界策略；边界策略也不读节点内容、不读密码 bounds。
- 入口判定之后不必再加一次类型判定：既有 `ScreenshotCapture` 的 gate 与 `onSuccess` 回调比较的是**完整 `WindowState`**（`OverlayVisuals.kt` 的 `windowChanged(original, latest) = latest != original`，`WindowState` 是 data class，逐字段比较 `windowId`、包名、宽高、旋转与 `windowType`），不一致即返回 `stale_observation` 且不发图。`windowType` 已在 M27 加入 `WindowState`，这处比较会自动覆盖类型变化，因此入口判定之外的补判并非必需。仍需实测的假设收窄为：同一 `windowId` 的窗口类型在正常使用中是否会发生变化；若确实会变，应让比较继续覆盖它，而不是取消入口判定。

**行为变更（M28 已生效的那一批，历史；用户与模型可见）**：

- 通知栏、状态栏、系统无障碍叠加层、分屏分隔条、未知类型窗口、硬基线窗口在前台时，读树与截图从“成功”变为 `system_window_denied`；消息给出固定标识与“请用户返回目标应用”的下一步。
- 输入法窗口在前台时读树与截图仍成功，这与输入层相反（输入法窗口的输入仍被拒，标识 `window_type_ime`）。
- `phone_agent_test.dart` 全程在测试应用自身前台（`TYPE_APPLICATION`），行为不变。
- 权限弹窗不受影响：它在 `rootInActiveWindow == null` 时就以 `no_window` 退出，到不了 `requireObservable`。

**M33 同批的测试影响（已实现，不是放宽断言）**：

- 构建期测试包 `com.psyche.kelivo.phoneagent` 作为**构建配置里的预批准条目**处理（不是用户白名单条目、不落盘、不可在 Mods 页撤销），因此 `phone_agent_test.dart` 与异常套件的应用自身前台路径行为不变。这条只影响测试包自身：它**不会产生批准提示**，也不影响其他应用 `permission_required` 的可达性。
- **跨 UID securefixture 夹具**：异常套件的 `FLAG_SECURE` 用例依赖宿主独立夹具包 `com.kelivo.phoneagent.securefixture`。M33 把它作为**仅 debuggable 构建生效**的预批准条目（`buildPreApprovedPackages(debuggable)`），否则该用例会收到 `permission_required`、红的理由与 secure 无关；release 构建不预批准该包名，避免同名第三方包被静默放行。有 JVM 断言覆盖这三点（debug 放行、release 拒绝、预批准不进用户白名单）。
- 异常套件的 home/recents 用例：`home`/`recents` 后前台实测是 launcher（`com.google.android.apps.nexuslauncher`，`TYPE_APPLICATION`），它属第三方、非 deny 成员、未批准，读树返回 **`permission_required`** 且只回身份。`_waitForForegroundLeftApp` 的接受集合已同步：读树成功且包名不是测试应用、`no_window`、带真实标识的 `system_window_denied`、以及**能从消息里解析出非本应用包名的 `permission_required`**。不带身份的 `permission_required` **不接受**——没有身份就无法证明前台已离开本应用，退化成“任意错误即通过”。四类都不含 `window_type_unknown`。
- 同一 helper 配套的 `_waitForStableWindow`（服务重启后等待前台恢复）把 `permission_required` 列入“窗口未就绪”的可重试子集：成功条件仍是 `package_name == 测试应用`，超时仍失败，不放宽任何通过条件。
- `_expectSystemNavigationDenied` 的输入错误码接受集合扩为 `{system_window_denied, package_not_allowed, permission_required}`（对应硬基线 / deny 成员 / 未批准第三方三种来源），仍要求节点输入与 `back` 两次判定**一致**。
- 异常套件的叠加层触摸用例断言 `system_window_denied` + `hard_baseline`，不涉及白名单层，**不受影响**。
- 异常套件的 settings 用例断言硬基线拒绝（`system_window_denied` + `hard_baseline`），硬基线排在 `package_not_allowed` 之前，**不受影响**。

**M28 同批的异常测试改造（历史记录，已实现）**：

观察边界收紧后，`phone_agent_exception_test.dart` 有 5 处依赖“读树能看到非本应用前台”，改法统一为**宿主 `dumpsys` 独立确认前台 + 测试断言错误码**，与权限弹窗用例既有的分工一致（宿主确认是测试前提，不是产品检测能力）：

- （a）服务禁用用例的 settings 树依赖（`:537`、`:549-550`）：改为宿主用 `dumpsys window` 确认前台是 `com.android.settings`（并转到 `PHONE_AGENT_OPEN_DISABLE_DIALOG` 标记）后，测试只等待宿主标记时序，不再读 settings 树判断页面；关闭确认弹窗是否出现由宿主 `dumpsys` 确认。测试侧改为**等待观察层的硬基线拒绝**（`system_window_denied` + `hard_baseline`）作为“宿主确实进了设置页”的证据。
- **pending 批次的形态（F1 修正，按实现描述）**：不再是“一次性发起 1000 个 `readTree(offset: 1)` 再 `Future.wait`”，而是**分块循环**——每块 `chunkSize = 200` 并发发起、累计结果码，然后检查 `service.status().enabled`，直到服务变为禁用或累计耗时达到 **35 秒上界**（`phone_agent_exception_test.dart:572-586`）。观测仍在**测试应用自身前台**建立（`offset: 1` 分页复用该观测），因为 settings 是硬基线包、`offset 0` 会被拒绝。**为什么改**：旧形态要求“1000 个请求恰好还在队列里”才有意义，宿主点击时机的抖动会让批次提前排空从而失去意义；分块循环改为“持续施压直到服务真的关掉”，断言（35 秒内完成、无 `timeout`、至少一个 `interrupted`/`service_unavailable`）不依赖排空时机。

- （b）叠加层触摸用例（`:195-245`）：宿主用 `dumpsys` 确认通知栏已打开并打印标记；测试的**核心断言是读树轮询**——20 秒截止内必须出现 `system_window_denied`，且消息带 `hard_baseline` **或** `window_type_system`（两者取其一，见下方实测修正：通知栏实际给的是 `hard_baseline`），同时保留叠加层可见性证据（触摸期间叠加层显示、截图无污染等既有断言）。**不再断言 `foreground != null`**（旧写法等“读到非本应用包名”，在 `TYPE_SYSTEM` 被拒后恒为 null）。
- 这一形态比旧断言**更强**，不是更弱：旧写法只要求“读到的包名不是测试应用”，新写法要求观察边界给出**固定的来源标识**，等于同时验证了“前台确实切换了”和“观察层确实按新边界拒绝”。

- （c）home/recents 用例（`:350-385` 经 `_expectSystemNavigationDenied`，helper 在 `:1010` 起）：**仍然读树**，但改用的是 `_waitForForegroundLeftApp`（`phone_agent_exception_test.dart:1108-1146`）——它轮询 `_tryTreePayload` 并接受三种结果之一：(1) 读树**成功**且 `package_name` 不是测试应用（实测 home/recents 落在启动器时的正常情况）；(2) `no_window`；(3) `system_window_denied` 且带真实观察标识（`hard_baseline` / `window_type_system` / `window_type_overlay` / `window_type_split_divider`）。**`window_type_unknown` 明确不在可接受集合内**，因为它表示窗口列表尚未稳定，把它当证据会吞掉真实时序缺陷。随后直接断言节点 `tap` 与 `back` 的错误码，并按“硬基线集合成员”区分 `system_window_denied` / `package_not_allowed`，要求两次判定一致；无法确定时不得退化成“只要报错就算通过”。
- **为什么不能写成“不再读树取包名”**：实测 home/recents 后前台是启动器（可观察、读树成功），所以“前台已离开本应用”的**正向证据恰恰来自读树返回的包名**；只有前台不可观察时才退化为标识断言。**注意这条只对 M28 的观察边界成立**：M32 契约（批准=读＋操作一体，未实现）落地后，启动器属第三方、非 deny 成员、未批准，读树会返回 `permission_required`（只回身份），该分支判据必须同步改写（见上文「契约实现时的测试影响」）。


不受影响、不得顺手改动：`phone_agent_test.dart`、异常套件的其余读树点（均在测试应用自身前台）、权限窗口用例（`no_window` 而非 `system_window_denied`）。

**未验证假设（不得写成已知事实）**：

- 观察允许 `TYPE_INPUT_METHOD` 在真实设备上是否会产生反向误伤：输入法窗口成为 `rootInActiveWindow` 时，读树拿到的是输入法自己的节点树（不是目标应用界面），模型可能只看到候选词与键盘。本步选择“允许观察”是照 7.5.3 的设计，但**输入法窗口的读树结果是否有用、是否会误导模型，尚未实测**。
- `windows` 枚举在某些 ROM 上能否稳定取到前台窗口类型：取不到或匹配失败即 `UNKNOWN` → 拒绝观察，表现为读树/截图在正常应用上也可能报 `system_window_denied`。M27 只在 API35 模拟器与 MIUI API31 上验证过官方测试路径不触发 `stale_*`，未覆盖所有 ROM。
- **M32 契约新增的未验证项**：未批准时返回“应用身份 + `permission_required`”是否足以让模型向用户解释授权请求（模型可能因为看不到内容而反复重试同一调用，只能靠 `permission_required` 文案里的“不要重复重试同一调用”约束）；包名与签名哈希前缀作为身份外发是否被用户接受；用户能否凭包名/应用显示名判断“这是不是我要授权的那个应用”（同名山寨应用、系统内置与第三方同名）。以上全部**未实测**。

**观察侧也判构建期硬禁止（已定（M32，tower 定论，用户可推翻），M33 已实现）**：观察路径的判定顺序里**包含**构建期硬禁止（`package_not_allowed`），命中时返回 `package_not_allowed` 而不是 `permission_required`。

- 理由：批准 = 读＋操作一体（用户拍板）。本次构建根本不支持操作的应用**不应该产生批准提示**——让用户批准一个「批准了也操作不了」的应用是纯粹的误导，而且会在用户批准后再给出一个与批准无关的拒绝，用户无从理解。
- 顺序：`package_not_allowed` 排在**用户白名单之前**。构建期范围已转 deny 清单（见 7.5.1），因此结果是确定的两分：**deny 成员的未批准应用报 `package_not_allowed`**（确定结论，不产生批准提示），**非 deny 成员的未批准应用走到 `permission_required`**。硬基线与窗口类型仍排在最前，系统窗口仍是 `system_window_denied`。
- 代价：`package_not_allowed` 的适用范围从「仅输入」扩到「输入与观察」（6.6 与 7.5.8 已同步），并已有「`package_not_allowed` 排在用户白名单之前」的同序断言（`PackagePolicyTest` 的 `the build deny list is judged before the user whitelist`）。
- 来源：tower 本轮定论，**不是**用户的 AskUserQuestion 拍板项。用户可推翻；推翻时须同时收回 7.5.1 与本节观察顺序里的这一层、恢复 6.6/7.5.8/README/AGENTS.md 的「仅输入」表述，并重写 10.1 的对应条目。

**测试影响（M33 已落地）**：跨 UID `securefixture` 在 debuggable 构建里预批准；home/recents 的 launcher 观察返回码由「读树成功」变为 `permission_required` 且只回身份。完整说明见上文「M33 同批的测试影响」列表。


#### 7.5.5 三项已定决策

三项由用户明确决定，不再作为开放问题（M32 未重开这三项；M32 修订的条目放在 7.5.9–7.5.14，来源逐条标注（用户拍板 / 早期已定契约 / tower 定论 / 设计提案，定义见 7.5.9 开头），其中「批准 = 读＋操作一体」见 7.5.1/7.5.4）：

**（1）白名单作用域 = 全局共享（不按助手隔离）**

- 理由：多数用户只有一两个助手，按助手隔离会让同一应用换个助手就重新弹批准，摩擦直接翻倍，正是要避免的成本。
- 代价：跨助手越权——“私人助手”批准的应用会被“工作助手”继承，两个助手的权限语义不同却共享一份授权。
- 缓解：每条白名单记录**首次批准来源助手 id**，Mods 页按来源分组展示；这为将来做助手级隔离留下迁移条件，不必重做存储结构。当前不提供“仅本助手”开关。

**（2）批准时效 = 长期有效 + Mods 页显式撤销**

- 不做一次性：一次性等于每动作都问，等于否定整个授权方向。
- **不做定时过期**：定时过期会让长任务在不可预期时刻（例如半夜）失败，比“授权沉底”更糟；用户也无法预知何时到期。
- 代价：授权沉底、长期无人复习。
- 缓解：Mods 页白名单管理页显示包名、签名哈希（可只显示前缀）、**批准时间与最近批准时间**、来源助手，并提供撤销；**没有使用时间埋点**，因此不显示“最后使用时间”（撤销与重新批准都会更新“最近批准”，但日常读树/输入不会记录时间）；撤销立即生效（下一次判定重新读存储，不缓存放行结果）。**生效范围的准确表述**：撤销阻止**新的读树（`offset == 0`）、全部截图与全部输入**；但撤销前已建立的树观测在 120 秒 TTL 或窗口变化之前，**`offset > 0` 分页仍会成功回放那份旧树**（见 7.5.4「撤销的生效范围」）。不得把撤销写成“下一次调用一定返回 `permission_required`”。
- 撤销不撤销“已发出的动作”：撤销只影响后续判定，不撤回已派发的点击、输入或手势。

**（3）审计 = 落盘元数据，滚动保留**

- 记录字段（仅此）：时间戳、助手 id、会话 id、包名、签名证书哈希前 8 个十六进制字符、动作类型（工具/动作名）、结果码。
- **明确不记录**：节点文本、输入文本、密码内容、截图或图片字节、界面内容摘要、坐标数值、窗口标题。
- 保留策略：滚动保留 **30 天或最近 2000 条**，先到者生效；超出即淘汰旧记录。
- 与“不写敏感日志”的口径划界：该条约束的是**内容**（不写截图字节、密码文本、节点文本到日志或崩溃报告）；审计只写**元数据**，元数据不是内容。两者不冲突，但不能据此把审计称为“不涉及隐私”——它仍能推断“用过哪些应用”，这是明确接受的代价。
- 不做上传、不做远端同步；审计文件属于本地状态，不进入仓库、不进入工具结果、不发给模型。

**M35 实现事实（落盘元数据，已实现；无设备证据）**：审计在插件原生侧，新增文件 `mods/phone_agent/plugin/android/src/main/kotlin/com/kelivo/phoneagent/AuditLog.kt`。

- **字段集合精确固定为七项**：`AuditRecord` 的七个属性（`occurredAtMillis`、`assistantId`、`conversationId`、`packageName`、`signingPrefix`、`action`、`resultCode`），`AuditRecord.FIELD_NAMES` 是同一顺序的落盘列序，TSV 每行恰好 7 列（带表头 `# kelivo phone agent audit v1`）。JVM 测试用反射断言「声明的字段集合 == `FIELD_NAMES`」，并逐个断言七项禁用字段（`text`/`inputText`/`password`/`screenshot`/`imageBytes`/`summary`/`x`、`y`、`endX`、`endY`、`coordinates`/`windowTitle`）不是字段。
- **七类禁内容没有进入记录的结构性路径**：`AuditAction.forCall(method, args)` 只读 `method` 与 `args["action"]`，输出固定 token（`readTree`、`screenshot`、`input.tap`、`input.set_text`、`input.swipe` 等）；未知输入动作降级为 `input`。记录构建器 `AuditRecorder.build(context, resultCode, now, signingPrefix)` **不接受参数对象**，节点 id、输入文本、坐标、持续时长、方向都无处落脚。签名前缀由调用方注入，生产实现在既有 `signingIdentity()` 上取 `signingPrefix`（前 8 位）；解析失败记 null，不阻断。
- **记录时机**：在 `PhoneAgentService.execute` 的 `reply` 收口处记录一次，**且只在这一处**，成功写 `ok`、失败写既有结构化错误码（不新增审计专用错误码，`AUDIT_OK` 只是成功字的常量）。因此排队超时（`timeout`）、`busy`、以及边界拒绝（`system_window_denied` / `permission_required` / `package_not_allowed`）都会留下一条带该码的记录。
- **两类调用不产生记录（按实现如实说明，不是遗漏）**：
  - `interrupted`：`reply` 只在 `epoch == generation.get() && !destroyed` 时记录，`interruptPending()` 先递增 `generation` 再遍历 `requests`，所以服务中断、`onUnbind`、`onDestroy` 作废的调用走 else 分支，**不留审计**——那条调用没有产生可归属的结果，写一条 `interrupted` 只会把“被打断”误记成一次完成。也就是说 `interrupted` 不出现在审计文件里。
  - **`service_unavailable` 一律不产生记录**（三个出口，都不是“有记录但包名为空”）：
    1. `dispatch()` 的 `connected == null` 提前返回；
    2. `execute()` 的 `destroyed` 提前返回；
    3. `execute()` 里 `worker.execute` 抛 `RejectedExecutionException` 后的 `reply(null, serviceUnavailable())`——`worker.shutdown()` 只在 `onDestroy()` 调用，而 `onDestroy()` 先置 `destroyed = true`、再经 `interruptPending()` 递增 `generation`，所以这个 `reply` 必然落进 else 分支（`epoch != generation.get()`），记录条件不成立。

    前两处都在 `AuditContext` 创建之前返回。同理，`PhoneAgentPlugin` 的 `approvedApps` / `approveApp` / `revokeApp` 也不审计（它们是白名单身份操作，不是手机操作）。
- **包名来源**：只在真正取到前台窗口的那一步写入 `readTree`（`windowState(root)` 之后）、`screenshot`（构造 `WindowState` 之后）、`input`（`currentWindow()` 之后）。因此 `no_window`、`device_locked` 这类取不到窗口的失败记录 `packageName` 与 `signingPrefix` 为空，**不猜测**。（服务未连接与 `interrupted` 属于上一条的“不产生记录”，不是“空包名记录”。）
- **助手/会话 id 由 Dart 调用侧传入**：`readTree` / `screenshot` / `input` 三个通道方法的参数新增可选 `assistant_id` / `conversation_id`；插件 Dart 客户端只在非空时发送，原生侧用 `AuditIdentity`（**从不抛错**，畸形值记 null）读取，缺失如实记为未知而不是伪造。**身份只能来自宿主调用侧**：`PhoneAgentClient.input()` 在展开模型参数**之前**剔除这两个键（与 `snapshot_id` 同一处防护），否则宿主取不到身份时模型自带的同名参数会直达原生侧被写成审计事实；宿主值永远优先。`PhoneAgentMod` 传 `context.readCurrentAssistant()?.id` 与 `context.conversationId`。助手 id 取的是当前助手快照，**只作审计标签，不参与任何授权判定**（批准是全局共享、按应用判定，见 7.5.5 第 1 项）。
- **保留策略**：`AuditLog` 每次追加后按「`occurredAtMillis < now - 30 天` 淘汰 → 仍超过 2000 条则从前淘汰」滚动；恰好 30 天的记录仍保留。**加载时也裁剪一次**：`ensureLoaded()` 在解码完成后按文件里**最新一条记录的时间戳**（不是当前时钟——否则应用长期未运行会让整份历史在下次启动时被一次性判为过旧）执行同一套 `prune`，因此外部写入、旧版本遗留或手工编辑的超限文件在读入路径上就收敛到「30 天 / 最近 2000 条」，不依赖后续是否还有一次追加。损坏行按“丢弃而非信任”处理：列数不是 7、时间戳不可解析、动作或结果码为空的记录直接忽略。
- **失败不阻断主路径**：`AuditLog.recordSafely()` 把构建、签名解析、读取、淘汰与写入全程包在 `try/catch` 内，失败只增加本地计数 `droppedWrites` 并返回 false；`PhoneAgentService.recordAudit()` 直接忽略返回值。审计失败不改变工具结果、不影响白名单判定、不写入日志、不发给模型。
- **存储位置与不外发**：`noBackupFilesDir/phone_agent_audit.tsv`（与白名单同目录策略），先写临时文件再改名；不进仓库、不进聊天备份、不上传、不同步、不进入任何工具结果或审计读取通道。**当前没有任何读取审计的通道方法**，文件只能由应用自身或 adb 读取。
- **未验证**：M35 未跑任何设备、未构建 APK；真实设备上的文件写入、进程重启后的追加与 2000 条滚动、多签名包的前缀取值均未实测。

#### 7.5.6 批准交互

- **两个入口，一套状态**：聊天内批准卡片 + 通知栏批准，共用同一个 pending 请求和同一份持久化白名单；任一端批准后，另一端自动消失，不会产生两条互相矛盾的记录。
- **摩擦单位是每个新应用一次**（绑定签名后 = 每个 `(包名, 签名)` 一次），不是每个动作、每个会话或每个任务。
- 聊天卡片**复用上游 `ToolApprovalService` 的模式与 UI 通知机制，不复用它的等待语义**。可复用部分：`Completer<ToolApprovalResult>` 的请求结构（`tool_approval_service.dart:34`）、pending 存储（`:64`）、创建方式（`:129`）和 `notifyListeners()` 驱动的卡片刷新。不可复用部分：`requestApproval` 返回的 `completer.future` 假定有调用方 `await` 它。本设计里工具调用**已经返回 `permission_required`**，没有人在 await 这个 Future，如果直接套用，pending 会一直留在 `_pending`、聊天卡片永不消失，与“任一端批准后另一端自动消失”直接冲突。
- 因此批准请求**不是由工具调用 await 的 Future 承载**：它是一条独立的状态记录，需要自己的生命周期规则——(a) TTL 到期自动失效（模型侧的 `permission_required` 早已返回，卡片过期不需要通知模型，模型下次调用会重新触发）；(b) 两端任一处批准或拒绝即**置终态**并同时撤下另一端（聊天卡片与通知）；(c) 服务断连、应用重启、切换会话时清理，不留下无法关闭的卡片。这些规则必须显式实现，不能靠“Future 被 await 后自然结束”。
- 通知栏**需要新建基础设施**：上游 `NotificationService` 只有 `onDidReceiveNotificationResponse`（`notification_service.dart:102`，点击打开会话），现有代码中 `AndroidNotificationAction` 零命中；宿主虽已有其他 `BroadcastReceiver`（如定时任务），但它们不是通知 action 通道，不能复用为批准链路。必须新增通知 action、`BroadcastReceiver` 与幂等写入。
- **不得写成“复用现有通知”**：通知 action 的点击语义、幂等去重、pending 失效清理都是新增工作。
- 批准写入必须幂等：同一 `(包名, 签名)` 重复批准不产生重复条目，只更新最后批准时间与来源（保留首次来源）。
- **不使用叠加层做批准界面**，三条理由：
  1. 叠加层是 `FLAG_NOT_TOUCHABLE | FLAG_NOT_FOCUSABLE`（见 2.6）。改成可触摸就是把“不可交互窗口”变成“可交互全屏窗口”，会引入触摸拦截、焦点窃取、点击穿透整条风险曲线，与 M23 的整个设计前提冲突。
  2. **批准通道不应由被批准的通道自己绘制。** 如果叠加层能画出批准按钮，它本身就已经越过了正在申请的边界——这是原则问题，不是实现难度问题。
  3. 叠加层在旋转、锁屏、切窗、服务中断时会被清理（见 2.6），而批准 UI 需要跨这些事件存续；把它当批准载体等于把“批准请求”变成会丢失的动画。
- 审批卡片与通知只是**交互载体**，不是安全护栏：模型无法自行批准（批准动作由用户手势触发），但“用户看都没看就点允许”不可防。
- **M32 追加（未实现）**：卡片与通知都提供“允许并继续”，其恢复语义见 7.5.10（**设计提案（tower 建议）**）；终态收敛、迟到回调与防自我批准见 7.5.13（**同为设计提案**）。
- **M33 现状（不得写成已有 UI）**：**没有任何批准界面**——聊天里没有卡片、通知栏没有批准按钮、Mods 页没有白名单管理页，也**没有 pending 请求状态**。已实现的是底层：原生白名单存储、`(包名, 签名集合)` 双匹配、幂等写入、写入前重解析签名、撤销立即生效，以及 `approvedApps` / `approveApp` / `revokeApp` 三个原生通道方法（供 M34 的卡片与通知共用）。因此本节描述的 TTL、单终态、迟到回调与「允许并继续」都还没有承载它们的请求对象。

**M34 实现事实（可与本节契约混读，但不得与 M33 的“无 UI”状态混读）**

M34（2026-11-16）实现了本节与 7.5.13/7.5.14 的交互面。**没有任何设备证据**：通知权限、通知 action 在 API 31–35 的真实行为、进程被杀后重放、跨 UID 前台包签名解析都仍未实测（见 10.2）。

- **请求状态机**：新增纯 JVM `ApprovalRequests`（`mods/phone_agent/plugin/android/src/main/kotlin/com/kelivo/phoneagent/ApprovalRequests.kt`）。七态：`pending` / `approved` / `denied` / `expired` / `superseded` / `dismissed` / `failed`，除 `pending` 外全是终态。
  - **TTL 30 分钟**（`DEFAULT_TTL_MILLIS`），到期置 `expired`；模型侧 `permission_required` 早已返回，**过期不通知模型**，下次调用会触发新请求。
  - **单终态**：终态记录不再接受 `resolve`；`resolve` 只在 `pending` 时调用 `AppApprovals.approve`，迟到回调（通知重放、连点、两端同时点）因此**不写白名单**。
  - **取代**：同一 `(包名, 签名集合)` 出现新请求时旧 pending 置 `superseded`；**签名变化不算同一目标**，不会取代旧请求（旧签名那条仍可由用户显式处理）。
  - **清理**：`dismissForConversation` / `dismissAll` 置 `dismissed`，是本地清理、**不是用户拒绝**。
  - 保留上限 64 条，终态记录先被淘汰。
- **`permission_required` 的结构化身份**：`PhoneAgentError` 新增 `details`，由 `PackagePolicy.requireApproved` 填 `package_name`、`signing_prefix`、`display_name`、`signing_available`、`observation` 五个字段，经 `MethodChannel.Result.error(code, message, details)` 传给 Dart，再进入工具结果的 `identity`。**字段严格限于 7.5.4 允许的应用身份**，有 JVM 断言固定字段集合（不含节点、窗口标题或界面内容）。签名解析失败时 `signing_prefix` 为 null 且 `signing_available=false`，不写哈希占位。
- **通道面（M34 新增，均不依赖无障碍服务连接）**：`requestApproval` / `approvalRequests` / `resolveApproval` / `dismissApprovals` / `privacyNotice` / `acknowledgePrivacyNotice`。身份由**原生侧**解析并保存，Dart 只传包名与关联上下文，**不传签名**——Dart 不是放行点。
  - **助手 id 有两个语义（与 M35 合并后）**：批准请求带 `approval_assistant_id`（**创建请求时的助手快照**，写入白名单“首次批准来源”供 Mods 页分组）；审计带 `assistant_id`（**实时重读**的当前助手，只是审计标签）。两者键名与用途都不同，不互相覆盖。
- **通知栏**：新增 `PhoneAgentApprovalNotifier`（独立渠道 `kelivo_phone_agent_approval`）+ `PhoneAgentApprovalReceiver`（`exported="false"`，`PendingIntent.getBroadcast`，两个 `Notification.Action`：“允许”与“拒绝”）。通知只显示包名、签名前缀与固定说明，文案在插件自己的 `strings.xml`（中英两套）；**未修改上游 `NotificationService`，也未使用 `AndroidNotificationAction`**——上游仍然只有“点击打开会话”。**通知是可选增强，不是主入口**：API 33+ 需运行时 `POST_NOTIFICATIONS`，M34 在选择 Phone Agent（隐私确认之后）请求一次；用户拒绝时通知发不出去，**聊天卡片是唯一入口**（这一点由 widget 测试锁定，不依赖通知权限）。API 24–25 没有通知渠道，同样只有卡片。
- **聊天卡片**：`PhoneAgentApprovalCard`（overlay）。上游接缝**两处两个文件**：`chat_message_widget.dart` 插入组件并用 `pendingExists()` 参与内容区判定（+ import），`home_page.dart` 注册/注销续跑回调、`resumed` 时 `refresh()`、切会话时清理旧会话（+ import）。
  - **渲染位置（R1 P1-1）**：卡片原先只插在 `content` 列里，而该列在“摘要关闭（默认）+ 无图片 + 无上游 pending”时为 `null`，导致**默认设置下卡片从不进入 widget 树**。现在 `PhoneAgentApprovalCard.pendingExists()` 同时参与 `content` 的非空判定与 `expectContent`，工具步骤本身也包在 `ListenableBuilder(listenable: PhoneAgentApprovalCard.listenable)` 里，因此卡片出现/消失都会让父级重算。**有 widget 测试锁定“默认设置下可见”，不依赖通知权限。**
  - 组件自身也监听 `PhoneAgentApprovalService.instance`，没有 pending 时返回 `SizedBox.shrink()`，因此不需要在上游 provider 树里注册。卡片只显示包名、签名前缀（或“签名证书不可用”）与可选显示名。
  - **不复用 `ToolApprovalService`**：它的 `requestApproval` 返回需要 `await` 的 Future，而本设计的工具调用已同步返回 `permission_required`；套用会让 pending 永驻。M34 的 `PhoneAgentApprovalService` 复用**模式**（`ChangeNotifier` + pending 列表 + `notifyListeners()` 刷新）而**不复用等待语义**。
- **「允许并继续」（M34 按 7.5.10 落地，仍属设计提案语义）**：卡片上的“允许并继续”先批准，再触发 `PhoneAgentApprovalService` 上**由首页注册**的回调；回调只向当前会话发送一条 `phoneAgentApprovalResumeMessage` 用户消息，要求模型**重新读取当前屏幕**并从真实界面状态继续，**不重放**批准前被拒绝的点击/输入/手势。会话已不是当前会话、发送被拒绝或没有注册回调时，只保存授权并提示“任务在等待批准时已中止，请让助手继续”——**不切换会话、不伪造续跑**。通知栏批准只能表达“批准”，因此那里的批准不续跑。
- **双向撤下与清理（R1 P1-3）**：卡片→通知由原生 `resolveApproval` 末尾 `cancel(requestId)` 实现；**通知→卡片**没有事件通道，改为**回到前台时 `refresh()`**（`home_page` 的 `didChangeAppLifecycleState`）重新对齐原生 pending，已处理的请求从卡片消失。**切会话**调 `onForegroundConversationChanged()`（只在真换会话时清理旧会话），**服务断连**由 Mods 页在 `connected` 由 true→false 时调 `onServiceDisconnected()`。`refresh()` 在通道失败时**保留**现有 pending（不清空），并发调用合并为一次。
- **Mods 页白名单管理**：`PhoneAgentApprovedAppsPage` 按**来源助手分组**（未知来源单列），逐条显示包名、签名前缀、批准时间、最后批准时间，并提供撤销；撤销后立即刷新（下一次判定重新读原生存储）。这是 7.5.5 第 (2) 项承诺的缓解措施。
- **首次启用隐私确认（方案 B）**：`PhoneAgentPrivacyNotice.ensureAcknowledged` 在 Mods 页选择 Phone Agent 时检查原生状态（`noBackupFilesDir/phone_agent_privacy_notice.tsv`，值为 `acknowledged-v1`），未确认则弹一次性对话框。取消**不写状态**，下次选择时再次提示；读不到状态按**未确认**处理（fail closed 到提示而不是跳过告知）。文案写明“只是告知，不是技术控制”，并说明密码涂黑与安全窗口黑屏是限制而不是保证。
- **批准失败不塌缩成成功（R1 P2）**：`resolve` 返回 `resumed` / `approvalOnly` / `denied` / `failed` 四值；原生 `approvalRequestPayload` 补 `failure_reason`（`signing_unavailable` / `signing_mismatch` / `pre_approved`），卡片对 `failed` 显示“无法保存批准”而不是“已批准”。
- **签名缺失 fail closed（R1 P2）**：签名从未解析成功的请求在批准时直接返回 `signing_unavailable`，**不再**把空集合退化成“按当前签名写入”。
- **过期/被取代的通知会被撤下（R1 P2）**：`ApprovalRequests` 注入 `onLeftPending` 回调，`expired` / `superseded` / `dismissed` / 终态都会 `cancel` 对应常驻通知，避免模型重试时堆叠无法关闭的通知。
- **预批准防护**：`AppApprovals` 新增 `preApprovedPackages` 参数，`approve`/`revoke` 对构建期预批准成员直接返回 `pre_approved`（撤销返回 false），不写用户白名单。`PackagePolicy` 仍然直接放行预批准成员，因此它们既不会产生批准提示，也没有不可撤销的冗余条目。
- **文案与 ARB**：新增 33 个键（含续跑提示语），英文与中文原文写在 `l10n-source` 增量补丁，四个目标语言（ko/ru/tr/zh_Hant）由本机网关 `mistral/deepseek-v4-1-flash-1017` 译出，`translate.py check` 四语言 **0 pending**。`llama-cpp/llama-cpp` 后端当轮不可用（网关报 Cloudflare 隧道不可达），**未使用付费服务**。
- **未验证**：通知权限与 action 的真实行为（含进程被杀后重放）、`POST_NOTIFICATIONS` 被拒时的表现、卡片在真实对话流中的布局、通知与卡片同时存在时的撤下时序、Mods 页在服务关闭时的撤销链路、`pre_approved` 之外的批准失败在 UI 上的表现。**M34 未跑任何设备**。

#### 7.5.7 `permission_required` 契约

- **立即返回，不阻塞**：检测到未批准时立刻返回 `permission_required`，不持有 `Completer` 等待、不排队重试、不静默降级为只读。与 7.5.6 的关系需要读清：我们复用 `ToolApprovalService` 的**请求结构与 UI 通知机制**，但批准请求**不挂在工具调用上**——工具调用拿到 `permission_required` 就结束，卡片/通知是独立的状态记录，有自己的 TTL 与终态收敛规则。因此“立即返回”与“复用该服务”并不互斥：互斥的只是“复用它的等待语义”。
- 理由是数字，不是偏好：Dart 通道超时 **35 秒**（`phone_agent_service.dart:149`），原生排队超时 **15 秒**（`PhoneAgentService.kt:35` 的 `QUEUE_TIMEOUT_MS`）。让工具调用等一封可能几小时后才来的批准，必然先把设计好的 `permission_required` 退化成 `timeout`，模型无法区分“用户拒绝”“用户不在场”和“系统卡住”。
- 明说取舍：批准未到时**当前任务停在此处**；用户批准后模型需要**重新观察**（旧句柄、旧截图会因时间与窗口变化失效），之前规划的步骤不能假设仍然有效。**长任务会中断**，不描述成无感体验，也不描述成“部分完成”。批准后如何继续见 7.5.10（该节的恢复机制是**设计提案**，不是用户拍板项）。
- **观察请求同样返回 `permission_required`（已定（用户拍板），M33 已实现）**：`readTree` 与 `screenshot` 在未批准时也走这个码，结果只带应用身份（包名、签名哈希前缀、可选显示名），不带节点、截图或界面内容。它**不是**“工具不可用”的错误，模型应把它当作“请用户授权”，并停止重试同一调用。
- 不自动批准、不自动重试、不在失败后循环弹批准卡片。**M33 不实现任何批准 UI**，因此当前没有任何入口能让用户“在 Kelivo 里批准”；批准只能通过原生通道写入（留给 M34 的 UI）。
- 模型可见文案（英文，与结构化错误风格一致；M33 已实现）。输入：

  `Input into <package> (signing cert <sha256-prefix>) needs the user's approval. The action was not executed and is not queued. Ask the user to approve this app in Kelivo, then decide whether to retry. Do not retry the same call repeatedly.`

- 观察（M33 已实现；同样只含包名与签名哈希前缀，不含节点文本、窗口标题或界面内容）：

  `Reading <package> (signing cert <sha256-prefix>) needs the user's approval. No screenshot or UI text was captured or sent. Ask the user to approve this app in Kelivo, then re-observe before acting. Do not retry the same call repeatedly.`

- 签名解析失败时两段文案都把身份写成 `<package>, signing_unavailable`，不写任何哈希占位。
- 该文案只含包名（观察文案额外含签名哈希前 8 位作为身份）与可选显示名，不含节点文本、输入内容或截图信息；`permission_required` 与 `system_window_denied` 必须可区分：前者“可以批准”，后者“永远不行”。输入与观察文案分别写明“动作未执行、未排队”与“没有截图、没有读取任何界面文本”。

#### 7.5.8 与既有错误码的关系

- 6.6 与 6.5.1 的既有码与优先级**继续有效**，本节只在其间插入三层判定，并新增 `permission_required`。
- 硬基线与窗口类型复用 `system_window_denied`，靠固定标识区分来源；不新增 `system_settings_denied` 之类的码，因为集合成员资格已经表达语义，新增码会稀释既有断言。
- `package_not_allowed` 表示构建期硬禁止，**语义有两层，M33 都已按新契约落地**：(a) **范围**——构建期范围已转 deny 清单，`package_not_allowed` 只对 deny 成员出现（见 7.5.1）；(b) **路径**——它同时用于输入与观察，观察侧排在用户白名单之前。错误码分界因此确定：deny 成员 → `package_not_allowed`；非 deny 成员但未获用户批准 → `permission_required`。已有“`package_not_allowed` 排在用户白名单之前”的同序断言（`PackagePolicyTest`）。**同一个码不同时表示“用户未批准”**。
- `system_window_denied` 也由观察层返回。读树/截图侧的 `system_window_denied` 只来自硬基线与观察窗口类型，**不会**来自 `package_not_allowed` 或角色持有者；观察层不查询角色，因此也不会产生 `role_resolution_failed`。
- **`permission_required`（M33 已实现）**：输入与观察都返回，观察侧只带应用身份。这不是新增错误码，而是把同一码用在同一语义上（“这个应用还没被用户批准”）。观察侧与输入侧的文案分别指明“没有读取任何内容/没有执行任何动作”。
- 本节不改变 `device_locked`、`no_window`、`stale_handle`、`stale_observation`、`screenshot_blocked` 的含义与范围。
- **白名单存储损坏或读取失败时按“没有批准记录”处理**（fail closed）：解析不了的行被丢弃，未批准即 `permission_required`，不会因为读不到记录而放行。

- 前台窗口类型有两个来源，**在同一有界预算内交替尝试**，都只认“就是这个窗口”：
  1. 节点自己的窗口 `root.window.type`。它与 `windowId`、包名同源，不存在跨读取竞态。
  2. `windows` 列表按 `windowId` 精确匹配。
- **实测证据（M28，API35，服务重连后首次截图，两种来源同时不可用）**：当时用临时调试版本打印了 `windowType attempt=0/1/2 rootWin=5902 nodeType=null entries=(5890, 3) resolved=UNKNOWN`（含 `nodeType=` 与 `resolved=`，**交付代码不打印这两个字段**；交付版本只在预算耗尽时打印 `windowType exhausted attempts=N rootWin=... entries=...`，见 `PhoneAgentService.kt:605-612`）。由此确认：`root.window` 返回 **null**，同时 `windows` 只有另一个窗口 id（5890），而 `rootInActiveWindow` 已属于窗口 5902。窗口列表要约 3 秒后才包含目标窗口。因此**既不能只依赖 `windows`，也不能假设 `root.window` 一定可用**；原“3 次 × 25/50ms（共 75ms）”预算在实测滞后面前必然失败，首次读树/截图会返回 `window_type_unknown`。该日志串是判断依据的**历史调试输出**，不能用交付构建复现；能复现的只有上面那行 `exhausted` 格式。
- 现实现为**总预算 2500ms、每次间隔 40ms** 的有界重试，交替读取两条来源；同时记录 `TYPE_WINDOWS_CHANGED` 到达时间，只有等待期间没有新窗口事件时才累加尝试计数（用于日志区分“平台没变化”与“我们没去读”）。预算刻意取实测滞后的量级，仍远小于读树/截图 35s 通道超时与 15s 排队超时；**只在两条来源都失败时才消耗**，正常路径无额外延迟。
- 预算内两条来源都拿不到才落 `UNKNOWN` 并由策略层拒绝（fail closed，消息带 `window_type_unknown`）。不放宽任何判定，不按包名、层级顺序或位置猜类型，也不为了让测试变绿延长等待。
- 该预算只是**缓解**，不是保证：**2500ms 短于实测的约 3 秒滞后**，只覆盖“窗口列表在两秒半内补上”的情形，不覆盖更长的滞后、其他 ROM 或任意极端时序；超过预算仍会返回 `window_type_unknown`，调用方应把它当作“窗口尚未稳定，稍后重试”。

#### 7.5.9 应用身份与签名绑定（来源分层，见下）

> **来源标注（覆盖 7.5.9–7.5.14 全段）**：本节起每个条目都带来源，四种标注含义固定如下，不得混用。
>
> - **已定（用户拍板）**：用户在 AskUserQuestion 或对话中明确选定的项，不再作为开放问题，不得重开。本轮范围内的拍板只有：`QUERY_ALL_PACKAGES` 一次声明、未批准只返回身份与授权请求；以及此前已定的 7.5.5 三项（白名单全局共享、批准长期有效 + Mods 页撤销、审计元数据滚动保留）、systemui 等系统应用禁止、批准两入口方向、不用叠加层做批准界面、首次隐私确认方案 B、产品定位（自用且可给朋友交付）。
> - **已定（M32，tower 定论，用户可推翻）**：本轮由 tower 定论、用户未直接拍板但可推翻的项，目前有两项——「观察侧也判 `package_not_allowed`」与「构建期范围在批准上线时转为 deny 清单」（均见 7.5.1/7.5.4）。**M33 已按契约实现这两项。**
> - **已定契约（早期设计，非本轮用户拍板）**：M26/M27 阶段确立、本轮沿用的契约（例如 `(包名, 签名)` 双匹配）；实现时须遵守，但来源不是本轮用户决策。
> - **设计提案（tower 建议、待实现）**：tower 的实现建议，**不是**用户决策。实现阶段可依证据调整，但调整必须回写本文，且不得拿来当作"用户已同意"的依据。

- **`QUERY_ALL_PACKAGES` 一次声明（已定，用户拍板：「一次声明 QUERY_ALL_PACKAGES（推荐）」；M33 已实现）**：在 Mod 插件的 manifest 里**一次**声明 `android.permission.QUERY_ALL_PACKAGES`，用它解析前台包的签名证书。不为每个新批准的应用动态添加 `<queries>`（那需要重新构建，等于把“用户批准”变成开发者动作）。声明位置是插件自己的 manifest（`mods/phone_agent/plugin/android/src/main/AndroidManifest.xml`），**不修改上游宿主 manifest**。
- **白名单条目 = `(包名, 签名证书 SHA-256)`（已定契约，早期设计，非本轮用户拍板；M33 已实现）**：两者必须同时匹配。包名匹配但签名不符视为**未批准**，不弹“签名不一致”的新错误码，仍返回 `permission_required` 并在身份里给出当前签名前缀，让用户自己判断是不是换了来源的应用。**多签名归一化（M29 实测 `com.android.vending` 返回 2 枚证书）**：条目存**排序去重后的 SHA-256 集合**，比较要求整集合相等；任一枚新增、替换或被去掉都算签名变化。
- **同签名更新保留授权（已定契约，早期设计；M33 已实现）**：应用升级只要签名证书不变，批准继续有效，不重新弹卡片。实现上只按“包名 + 签名集合”比对，不按版本号、`lastUpdateTime` 或安装时间。
- **签名变化或无法解析 → 重新批准（已定契约，早期设计；M33 已实现）**：签名变化（覆盖安装为另一签名的包、卸载重装为不同来源）视为未批准；签名解析失败（`PackageManager` 抛异常、包已被卸载、`GET_SIGNING_CERTIFICATES` 拿不到结果、返回空证书集）也视为未批准，**fail closed**，不因为“读不到”而放行。批准写入前同样重新解析一次，解析失败或与批准请求保存的签名不一致都**不写入**（标识 `signing_unavailable` / `signing_mismatch`）。
- **授权不随聊天备份迁移（已定契约，早期设计；M33 已实现）**：白名单是本地设备状态，不进聊天备份/同步；换设备或用聊天备份恢复后需要重新批准。实现落在 `context.noBackupFilesDir/phone_agent_whitelist.tsv`，文件格式是带表头的制表符分隔文本，损坏行被忽略而不是被信任。
- **应用分身 / 工作资料首版明确不支持（已定契约，早期设计；M33 未适配）**：Android 的 profile（工作资料、`user 10/11`）与厂商应用分身会给出同一包名的另一份签名或另一份用户空间。首版**明确不支持**，不为它们做多用户 `PackageManager` 查询（M33 的签名解析即 `PackageManager.getPackageInfo(packageName, …)`，天然作用于默认用户）；这类前台在首版视为未批准（或按其实际包名解析失败则 fail closed）。**不得写成“已适配分身”**。
- **批准/撤销/查询的原生通道面（M33 已实现，UI 未实现）**：`kelivo/phone_agent` 通道新增 `approvedApps`、`approveApp`、`revokeApp`。三者**不依赖无障碍服务连接**（Mods 页在服务关闭时也必须能撤销）。`approveApp` 幂等：同一 `(包名, 签名集合)` 重复批准只更新最后批准时间并保留首次来源；`revokeApp` 立即生效（下一次判定即重新读存储，返回 `permission_required`；**范围见 7.5.4「撤销的生效范围」**——阻止新的读树、全部截图与全部输入，已建立观测的 `offset > 0` 分页在 TTL 内仍回放旧树）；`approvedApps` 只回包名、签名前 8 位、批准时间与来源助手 id。
- **`QUERY_ALL_PACKAGES` 的实际能力仍未设备验证（设计提案，未验证）**：M29 在 API35 与物理 MIUI 上实测了“无声明 → `NameNotFound`、声明后 → `ok`”，但那是**探针 APK 的结论**：M33 的实现（无障碍服务进程内解析任意前台包签名）**尚未在设备上跑过**。Google Play 对该权限有政策限制，本 Mod 是私有、自用与朋友间交付，**不走 Play 分发**；这条只作说明，不构成对分发的承诺。
- **签名哈希的展示口径（M33 部分实现）**：`permission_required` 消息、`approvedApps` 结果与本地存储都只使用前 8 位十六进制字符；完整哈希只在本地存储与比较时使用，不进入工具结果、不进入聊天、不发往 provider。Mods 页白名单列表与批准卡片**尚未实现**。

#### 7.5.10 批准后的恢复与任务控制（设计提案（tower 建议、待实现））

> **来源**：本节全部为 **设计提案（tower 建议、待实现）**，**不是用户拍板项**。用户只表达过一条方向性约束（原文引用，作为需求依据保留，不删除）：
>
> > 「就是等待授权的交互设计要好好考虑下，如果每次都需要用户回到Kelivo操作，那摩擦就太大了」
>
> 该约束只说明「批准流程不能迫使每次操作都回 Kelivo 手动处理」，没有指定本节的恢复机制、任务控制或错误码。实现阶段可依证据调整，调整需回写本文。

**（1）「允许并继续」的恢复语义（设计提案，待实现）**

- 批准卡片/通知提供“允许并继续”动作。它**只恢复与该次批准相关联、且仍然可恢复的任务**，不恢复其他任务、不恢复与目标应用无关的任务、不批量恢复此前积压的请求。
- 恢复后**先重新观察**（读树或截图），**不重放**被拒绝时的点击、输入或手势。批准发生在过去，那时的句柄、截图、窗口与布局都不能假设仍然有效。
- 不允许“批准即自动重试原调用”：原调用已经返回 `permission_required`，重放属于模型决策，不属于批准通道的行为。批准通道只负责“让下一步变得可能”。
- 若批准时该任务已经被用户取消、会话已切换、服务已断连，则**不恢复**，卡片显示为过期终态（见 7.5.13），不报错给模型。

**（2）任务控制（设计提案，待实现）**

- **同时只允许一个任务控制手机**：手机是单一物理资源，两个任务同时驱动会产生互相打断的点击与手势。控制权按任务持有，不按助手持有；第二个任务发起工具调用时得到“当前有其他任务在控制手机”的结构化错误，不排队等待、不抢占。
- **停止 / 撤销后未执行的请求失效**：用户停止任务或在 Mods 页撤销授权后，该任务**尚未执行**的请求（排队中的读树、截图、动作）一律失效，不执行。已派发的动作见下条。
- **已派发的手势不承诺撤回**：`dispatchGesture` 已发出后，撤销、停止、断连都不能保证手势没有发生；系统层没有“撤回已注入的触摸”的能力。文档与模型文案都不得写成“撤销后什么都没发生”。
- 具体错误码与文案（**设计提案，未定稿**）：控制权冲突拟用一个现有码（如 `timeout`/`rate_limited`）之外的明确码，但**本轮不新增错误码**；实现前需在 6.6 定论，并同步 README。避免出现“模型以为只是慢，于是重试”的误导。

#### 7.5.11 结果未知语义（设计提案（tower 建议、待实现））

> **来源**：本节为设计提案（tower 建议、待实现），不是用户拍板项。其中的取舍理由来自既有契约（`performAction` 只表示系统接受动作，见 7.4），属于沿用而非新决策。

**已派发后的超时、取消或中断属于“结果未知”，不是“失败”，也不是“成功”。**

- **不盲目重试**：动作已经派发（`performAction` 已调用、`dispatchGesture` 已返回 true、系统动作已接受）而调用超时或被取消时，模型与产品都**不得**自动重试同一动作。重试可能在屏幕上产生第二次点击、第二次输入、第二次发送。
- **先重新观察**：正确顺序是“重新读树/截图确认界面状态 → 再决定下一步”。是否已经生效只能从界面推断，不能从调用返回值推断。
- **区分动作完成与业务成功**：`performAction` / `dispatchGesture` / `performGlobalAction` 的返回值只表示系统接受了调用，不表示点击命中了目标、输入写入了正确控件、消息已经发送。网络请求、动画、页面跳转都可能失败。
- **产品侧的实现要求（设计提案）**：超时发生时返回的错误消息必须明确“动作可能已执行，请重新观察，不要直接重试”，并带上已知的动作类型；不得只返回 `timeout` 让模型猜测。哪些码属于“结果未知”（`timeout` 在动作后、服务中断在动作后、取消在动作后）需要在实现时逐条列出，并写清哪些是“确定未执行”（例如排队中被打断、前置校验失败）。
- **不得承诺的能力**：撤销已执行的输入、回滚已发送的消息、判断服务端是否真的收到请求。这些在任何文档、README 与模型文案中都不得写成产品能力。

#### 7.5.12 截图与手势范围、复杂多窗口（设计提案（tower 建议、待实现））

> **来源**：本节为设计提案（tower 建议、待实现），不是用户拍板项。已实现部分（分屏分隔条拒绝观察、`stale_observation` 的窗口绑定）见 7.5.3 与 6.5，属既有契约。

- **范围与获准目标一致**：截图与坐标手势只针对**已获准的目标应用**。批准 A 应用不等于可以截取或操作 B 应用；前台切到未批准应用时，截图与该应用上的坐标手势都被 `permission_required` 拒绝（读树同理，见 7.5.4）。
- **坐标手势的窗口绑定**：坐标手势必须绑定最近一次截图的窗口；截图与手势之间发生包名、窗口、尺寸或旋转变化仍返回 `stale_observation`（现有契约不变）。提案新增一条：手势执行时前台若已不是截图时的**已批准**包，拒绝执行，不按旧坐标盲点。
- **首版不支持复杂多窗口**：分屏、画中画、自由窗口（`freeform`）、多显示器与折叠屏多窗口形态，首版**明确不支持**，不承诺在分屏里“只截半个屏幕”或“只操作其中一个应用”。分屏分隔条本来就按 `TYPE_SPLIT_SCREEN_DIVIDER` 拒绝观察（M28 已实现）。
- **失败码与文案（设计提案，未定稿）**：分屏/画中画/自由窗口时的失败优先用现有 `system_window_denied` + 固定标识表达（不新增错误码），文案说明“当前多窗口形态不受支持，请让目标应用占满屏幕”。本条**未定稿**：现有实现里分屏中已批准应用属于 `TYPE_APPLICATION` 时会正常观察，因此“首版不支持”与当前行为存在差异，实现前需要在本文定论是**拒绝**还是**仅记录不承诺**。**本轮不得把“首版不支持多窗口”写成已生效行为，也不得写成“多窗口拒绝”。**
- **不承诺的能力**：不承诺截图与手势在系统 UI 变化、悬浮窗遮挡、厂商分屏实现下保持一致语义；这些仍是 7.4 的“不属于硬保证”范围。

#### 7.5.13 批准请求终态校验与防自我批准（设计提案（tower 建议、待实现））

> **来源**：本节为设计提案（tower 建议、待实现），不是用户拍板项。其中"不得自动批准""不用叠加层做批准界面"沿用已定决策（后者为用户拍板），但本节的具体终态机、请求 id 幂等与签名重解析均为 tower 建议。

**终态收敛（设计提案）**

- 每条批准请求只有**一个终态**：已批准、已拒绝、已过期（TTL）、已撤销（本地清理）、已被取代（同一 `(包名, 签名)` 已有新请求或已批准）。终态一旦写入不再变更；重复的批准回调只更新“最后批准时间/来源保留首次”，不产生第二条记录、不把拒绝翻成批准。
- 通知栏动作、聊天卡片动作与 Mods 页撤销都走**同一个原生/本地判定入口**，写同一份存储，带幂等键（请求 id + `(包名, 签名)`）。
- 迟到回调必须按请求 id 校验：请求已有终态、或已过期、或已被服务断连清理时，迟到回调**不得**写入白名单。通知 action 在进程被杀后被重放、用户连点两次、两个入口同时点击，都必须落在这条规则下。
- 服务断连、应用重启、切换会话时清理 pending；清理不等于拒绝，模型侧早已拿到 `permission_required`，无需通知模型。

**防自我批准（设计提案；安全基础部分为已实现）**

- **批准动作只能由用户手势在 Kelivo 自己的界面或通知栏触发**，模型无法通过 `phone_agent_input` 触发：承载助手的 Kelivo 包 `com.psyche.kelivo` 在硬基线集合内，输入与观察都被拒绝（M27/M28 已实现），这是本条的既有技术基础。
- 批准写入前必须**重新解析**该包的当前签名，与请求里保存的签名比对；不一致时置终态为“已失效”，不写入。请求保存的签名不得由 Dart 侧传入（Dart 不是放行点，见 7.5.1）。
- **不得自动批准**：没有“记住这次选择”“总是允许”的隐式路径；没有超时自动放行；没有“模型声明可信”或“同一会话已批准过别的应用”之类的前置条件可以替代本次批准。
- **不得把批准状态塞进工具结果让模型改写**：批准状态只由用户动作改变；工具返回的 `permission_required` 是只读事实。
- 不是安全护栏的部分要写清：**用户不看内容就点“允许”不可防**；批准卡片/通知是交互载体，不是不可绕过的技术控制。

#### 7.5.14 首次启用隐私确认（方案 B：用户拍板；其余为设计提案）

- **方案 B（已定，用户拍板）**：用户**首次启用** Phone Agent 时，一次性提示：截图与界面文字会作为工具结果发送给用户自己配置的 provider（可能包含聊天记录、消息列表等界面内容）。**只在首次提示，不每张截图询问、不在每次任务前重复**。本轮不重开方案选择。
- 提示的**位置与形态（设计提案）**：放在启用路径上（Mods 页选择 Phone Agent 或首次授权合并提示），确认结果落本地状态；文案进 ARB 并同步目标语言，与上游文案规范一致。
- **不承诺的部分（必须写清）**：该确认是**告知**，不是技术控制；它不阻止用户在确认后授权任何应用，也不改变 7.5 的白名单判定。它不构成“数据不会外发”的承诺——恰恰相反，它说明会发生什么。
- **重新提示的条件（设计提案，未定稿）**：默认只在首次提示。若 provider 配置发生更换是否需要重新提示，本轮**不决定**；实现前需定论并写进本文。
- 与既有隐私口径的关系：密码遮挡、`FLAG_SECURE`、叠加层不显示内容等既有边界不变（7.1/2.6）；它们降低风险，不使界面内容变成“不会外发”。


### 7.6 实现前置风险与行为变更

本节列的是**动手前必须处理**的事项。**风险 1（`WindowState.windowType`）已由 M27 第 1 步处理**；**风险 2（观察边界的异常测试依赖）已由 M28 第 2 步处理**；**风险 3 与风险 5 的白名单部分已由 M33 处理（门控与签名绑定）**；**审计元数据已由 M35 处理**（7.5.5）；批准交互与首次隐私确认仍待处理（M34、M36）。**M32（2026-11-15）只修订契约**；**M33（2026-11-15）实现了 7.5.4 的观察反向、7.5.9 的签名绑定与 7.5.1 的 deny 清单语义**，7.5.10–7.5.13 仍是**设计提案（tower 建议）**、未实现，来源分层见 7.5.9 开头的说明。

**风险 1：`WindowState` 需要新增 `windowType`，波及 `sameWindow()` 与全部构造/调用点（M27 第 1 步已实现）**

- `WindowState`（`ObservationRegistry.kt`）原本只有 `windowId` / `packageName` / `width` / `height` / `rotation`，**没有窗口类型字段**；`AccessibilityNodeInfo` 不提供窗口类型，类型只能来自 `AccessibilityWindowInfo.type`，需要按 `windowId` 在 `windows` 里另行匹配。
- 因此 `PhoneAgentService.windowState(root)`（`WindowState` 的唯一构造点）必须多一次 `windows` 枚举与 id 匹配；`windowState(...)` 的直接调用点是读树、截图与 `currentWindow()`（输入路径经它进入）。实际 `WindowState(...)` 构造仍只有一处。
- 不得为了省事在策略层另读一次 `windows`：`rootInActiveWindow` 与 `windows` 是两次读取，中间可能切窗，会引入新的竞态。类型必须与 `WindowState` 同源、同一次读取，才能保证“判定用的窗口”就是“执行用的窗口”。**实现即按此规则：`windowType(windowId)` 在 `windowState()` 内部调用，策略层不接触 `windows`。**
- `sameWindow()` 与截图观测比较都加了 `windowType`；同一窗口 id 的类型在正常使用中不变，但这是**待实测假设**，不是已知事实，因此设备回归必须覆盖“正常场景不出现新的 `stale_*`”（见 9.3 的未验证项）。
- 类型解析失败（`windows` 不可读、找不到对应 `windowId`、或返回未知类型）**fail closed**：一律落到 `WindowType.UNKNOWN`，输入拒绝。
- 测试夹具里的 `WindowState(...)` 构造已同步，并用常量 `TEST_PACKAGE` / `KELIVO_PACKAGE` 取代散落的字符串；策略本身是纯函数，纯 JVM 覆盖，未引入 Robolectric 或新依赖。

**风险 2：`phone_agent_exception_test.dart` 因观察边界变红（M28 第 2 步已同批处理）**

观察边界收紧后，异常套件共有 **5 处** 依赖"读树能看到非本应用前台"的地方会失败，必须与产品代码同批改掉，否则套件无法变绿。M28 的处理原则是**统一改为“宿主 `dumpsys` 独立确认前台 + 测试断言错误码/时序”**，与权限弹窗用例既有的分工完全一致：宿主确认是测试前提，不是产品检测能力；测试不得为了变绿而放宽断言，也不得把“只要报错”当作通过。

**（a）settings 树依赖（服务禁用/中断/重启用例）**

- 原失败点：`phone_agent_exception_test.dart:537` 靠读 `com.android.settings` 树判断宿主已打开无障碍详情页，`:549-550` 靠读 settings 树并断言存在 `Turn off` 节点来判断关闭确认弹窗已出现；`:557` 的 `_tree(service)` 与随后 1000 个 `readTree(offset: 1)` 也在无障碍设置页前台建立观测（见 9.3.1 的“先建立 Settings 观测”）。观察边界收紧后这一步直接 `system_window_denied`，用例在到达禁用断言前就失败。
- 改法（本步实现）：两处 settings 树轮询删除，改为**宿主 `dumpsys window` 确认前台包名是 `com.android.settings`** 后由宿主推进到 `PHONE_AGENT_OPEN_DISABLE_DIALOG` 标记；测试侧改为等待观察层的**硬基线拒绝**（`system_window_denied` + `hard_baseline`）作为“宿主确实进了设置页”的证据。**pending 批次改在测试应用自身前台**（`TYPE_APPLICATION`）建立观测（`_tree(service)` 一次，`offset: 1` 分页复用该观测），随后按 `chunkSize = 200` **分块反复**发起 `readTree(offset: 1)` 并累计结果码，每块后检查 `service.status().enabled`，直到服务被禁用或达到 35 秒上界。分页请求复用同一观测，因此批次不再依赖 Settings 页面，也不因分页重复判定而失败（见 7.5.4 的“分页不重复判定”）。宿主在批次仍 pending 时切到设置页并关闭服务，断言（35 秒内完成、无 `timeout`、存在 `interrupted`/`service_unavailable`）在分块形态下不变，但不再依赖“1000 个请求恰好排空”的时机运气。
- 保留下来的含义：该用例仍验证“禁用服务会中断 pending 请求”，只是不再用读树判断宿主停在哪一页。

**（b）`:202-232`「叠加层可见时真实触摸不被拦截」**

- 原失败点：第 `219` 行 `final tree = await _tryTree(service);` 轮询等待前台包名 `!= _appPackage`（`:221-224`）；宿主 `adb shell input swipe` 触摸后打开的是通知栏（`com.android.systemui`，`TYPE_SYSTEM`）。`TYPE_SYSTEM` 拒观察后 `_tryTree`（`ok != true` 即返回 null）恒为 null，`:228` 的 `expect(foreground, isNotNull)` 必然失败。
- 改法（本步实现）：前台由**宿主 `dumpsys` 确认通知栏已打开**（`mCurrentFocus`/`mFocusedApp` 指向 `com.android.systemui`）并打印标记；测试侧的读树轮询改为“在触摸窗口期内继续读树并记录结果”，**核心证据换成产品能力的正向断言**——同一时段读树必须返回 `system_window_denied` 并带观察边界的固定标识。叠加层可见性证据（触摸期间叠加层显示、随后的截图无污染）保持原样。测试不再要求读到 `com.android.systemui` 的节点树。
- **设备实测修正（M28，API35）**：API35 上打开通知栏后 `mCurrentFocus` 实测为 `Window{... NotificationShade}` 而**不是** `com.android.systemui/...`，因此宿主确认不能只按 `mCurrentFocus` 精确匹配该包名。更要紧的是标识：`com.android.systemui` 本身就在 `HARD_BASELINE_PACKAGES` 里，而**硬基线判定排在窗口类型判定之前**，所以实际返回的标识是 `hard_baseline`，**`window_type_system` 不可能独立出现**。断言必须接受 `hard_baseline` 或 `window_type_system`，不能只等后者（只等后者会让该用例必然超时）。这一点容易误读，写死“通知栏 → `window_type_system`”是错的。

**（c）`:346-377`「home 与 recents 后输入被包名策略拒绝」**

- 原失败点：该用例经 `_expectSystemNavigationDenied`（`:1005-1040`）驱动，`:1019` 的 `_waitForTreeWhere`（内部同样走 `_tryTree`）读树等待前台离开白名单；`home`/`recents` 后前台通常是 systemui，读树被窗口类型拒绝后拿不到 `package_name`，在 `:1025` 的 `expect(foreground, isNotNull)` 处失败。
- 改法（本步实现）：读树取包名改为**“前台已不是本应用”的观测断言**，随后直接断言节点输入与 `back` 的错误码。期望值不依赖宿主提供包名：错误码按**硬基线集合成员**区分（systemui 等 → `system_window_denied`，其他包 → `package_not_allowed`），无法确定时只能接受这两种之一并要求两次判定一致。
- **设备实测修正（M28，API35）**：`home` 与 `recents` 后前台实测**不是** systemui，而是 `com.google.android.apps.nexuslauncher/.NexusLauncherActivity`（`TYPE_APPLICATION`），**读树成功返回包名**。因此“等读树被观察层拒绝”这一写法对 home/recents 会白等到 30 秒超时。正确断言是：读树成功时要求包名不是测试应用，读树被拒时要求带真实观察标识（`hard_baseline` / `window_type_system` / `window_type_overlay` / `window_type_split_divider`）。**`window_type_unknown` 明确不在可接受集合内**——它表示窗口列表尚未稳定，把它当作“已离开前台”的证据会吞掉真实的时序缺陷。

**（d）不受影响的部分（避免过度改动）**

- `phone_agent_test.dart` 不读 settings，全程测试应用前台，不受观察边界影响。
- `:116-127`、`:303`、`:334`、`:479` 等读树点都在测试应用自身前台（`TYPE_APPLICATION`），不需要改。
- 权限窗口用例读树得到 `no_window`（不只是"失败"），与本层无关，保持原样。

**（e）宿主确认是前提不是产品能力**

- 这不是推翻既有分工，而是把它补完整：`mods/phone_agent/README.md` 的故障排查与 9.3.1 的边界本就写明服务开关由宿主在系统界面操作、测试只轮询断言，以及权限弹窗由宿主 `dumpsys` 独立确认；M28 把（a）（b）（c）三类用例的前台确认补进了同一套分工。
- 反过来说：在测试依赖改完之前，不能宣称新边界“已通过异常套件”。本步的结果与未通过项见 9.3 的新增小节。

**风险 3：行为变更（收紧），不是纯新增（观察层 M28、白名单门控 M33 与批准 UI 的 M34 交互面均已实现，后者无设备证据）**

- 观察层已生效的部分（M28）：通知栏、状态栏、系统无障碍叠加层、分屏分隔条、未知类型窗口与硬基线窗口在前台时，读树与截图从“成功”变为 `system_window_denied`。
- **输入法窗口不受观察层影响**：`TYPE_INPUT_METHOD` 在观察允许集内，读树与截图仍成功；它只在输入层被拒（`window_type_ime`）。不得把“输入法窗口被拒绝输入”误写成“输入法窗口不可观察”。
- **M33 已生效的收紧**（用户与模型可见）：
  - 未批准应用的**读树与截图**从“成功”变为 `permission_required`，只返回应用身份（包名 + 签名前 8 位）。这是本轮最大的一处用户可见变更。
  - 输入从“只看是不是测试包”变为“要用户批准”（构建期 pre-approved 条目除外）。
  - 已安装用户升级后不会自动获得任何白名单条目（默认拒绝），首次调用即返回 `permission_required`——**包括读树与截图**。
  - 每次调用都重新解析当前签名，签名变化立即失效；白名单文件损坏或不可读时按未批准处理。
- **尚未生效的收紧**（M34、M36）：首次启用时的一次性隐私确认（7.5.14）。审计元数据（7.5.5）已由 M35 实现，**但只在本机落盘、没有读取界面**，因此也就不会有任何用户可见的审计视图。**批准界面已由 M34 提供**（聊天卡片 + 通知栏 action），但两者都只有单元与静态检查证据；本项目仍有“用户不看内容就允许”的不可防部分。

**风险 4：历史 VLM 结果不能用于宣称新边界已验证**

- 9.4 与 10.1 的 VLM 固定任务、坐标动作、像素专属确认全部来自**旧代码**（读树/截图无边界、输入限单测试包、无白名单门控）。
- M33 改了观察与输入两条路径的判定，**必须重跑**：API35 官方测试、完整异常套件、物理 MIUI 官方测试，以及至少一轮 VLM 固定任务（含“未批准 → 只回身份 → 批准 → 重新观察 → 撤销 → 重新 `permission_required`”的完整链路）。
- **M33 未跑任何设备测试**（属 M36）。因此现在所有设备结论仍是旧代码证据；重跑前只能写“新边界未验证”。
- 异常套件在 M33 只做了断言同步（helper 接受集合、`permission_required` 身份解析、重启等待的可重试子集），**没有在设备上跑过**。M36 必须实跑，并确认 `securefixture` 预批准确实让 `FLAG_SECURE` 用例回到“验证 secure”而不是“验证未批准拒绝”。

**风险 5：实现前需要设备实测确认的假设**

- **包可见性与签名解析（M33 已实现，能力仍未实测）**：manifest 已一次声明 `QUERY_ALL_PACKAGES`（7.5.9），实现在无障碍服务进程内用 `PackageManager.getPackageInfo(packageName, GET_SIGNING_CERTIFICATES)` 解析签名（API < 28 回退 `GET_SIGNATURES`）。M29 的探针证据只证明“声明后探针 APK 能解析”，**没有证明交付的服务进程能解析任意前台包**。**仍需实测**：声明后能否稳定解析**任意前台包**的签名证书 SHA-256（API 30/31/35 均无交付代码证据）；`PackageManager` 对已卸载/正在更新的包抛异常时的失败形态（代码按 fail closed 处理，但未实测）。
- 替代接口（`TelecomManager.defaultDialerPackage` / `Telephony.Sms.getDefaultSmsPackage`）与 `ROLE_DIALER` / `ROLE_SMS` 的语义等价性在 MIUI 等厂商 ROM 上是否成立，含“`getDefaultSmsPackage` 返回 null 表示系统明确没有默认短信应用”这一区分是否可靠；解析失败必须按最严拒绝。
- 厂商设置与安装入口变体（如 `com.miui.securitycenter`、`com.miui.packageinstaller`、`com.lbe.security.miui` 之外的实现）是否能被完整覆盖；漏写即等于没有硬基线，且在第 3 步白名单上线后会变成真实缺口。补全流程见 7.5.2。
- 通知 action + `BroadcastReceiver` 在 API 31–35 的行为（点击回调、进程被杀后重放、幂等）。**M32 追加**：迟到回调的请求 id 校验与终态收敛（7.5.13）**无任何实测证据**，进程被杀后重放的真实行为未知。
- `WindowState` 增加 `windowType` 后 `sameWindow()` 是否会让正常场景误报 `stale_*`（M27 在两台设备官方测试路径上未出现）。
- **M28 新增**：观察允许 `TYPE_INPUT_METHOD` 在真实设备上是否会产生反向误伤——输入法窗口成为 `rootInActiveWindow` 时读树拿到的是输入法自己的节点树（键盘与候选词），而非目标应用界面。
- **M28 新增**：`windows` 枚举在某些厂商 ROM 上能否稳定取到前台窗口类型；取不到或匹配失败即 `UNKNOWN` → 拒绝观察，表现为正常应用上的读树/截图也可能报 `system_window_denied`。
- **M32 新增**：应用分身 / 工作资料下的包名与签名形态（首版已定“明确不支持”，但**未实测**这些前台会解析成什么，可能表现为签名不符或解析失败）。首版不做多用户查询，不等于已知其行为。
- **M32 新增**：未批准时只回身份，模型是否会陷入“反复请求同一应用”的循环（文案约束“不要重复重试同一调用”的有效性未经实测）。

以上均**未实测**（除注明 M27 已验证的部分）；实现前不得在文档中写成“已知可行”。

**M32 实现顺序与必须先定论的前提（第 2、3 步 M33、第 4、5 步 M34、第 8 步审计 M35 均已实现；第 6、7 步仍未完整实现）**

1. **先定论、再写代码**：多窗口是否拒绝而非仅“不承诺”（7.5.12）；任务控制冲突是否新增错误码（7.5.10）；provider 更换是否重新提示隐私确认（7.5.14）。这三项不在本轮拍板范围内，不得在实现里静默二选一。观察侧判 `package_not_allowed` 已由 tower 定论（7.5.1/7.5.4，用户可推翻），M33 已照做；若用户推翻须先回写文档再改代码。
2. **测试包与夹具归属（✅ M33 已实现）**：构建期测试包 `com.psyche.kelivo.phoneagent` 是**构建配置的预批准条目**（不写用户白名单、不产生批准提示、不影响其他应用的可达性）；跨 UID `securefixture` 夹具包**只在 debuggable 构建**预批准，否则 `FLAG_SECURE` 用例会收到 `permission_required`。详见 7.5.4「M33 同批的测试影响」。
3. **实现顺序**：应用身份与签名解析（7.5.9，✅ M33）→ 白名单门控接入观察与输入（7.5.4/7.5.2，✅ M33）→ 批准交互与终态（7.5.13/7.5.6，✅ M34，无设备证据）→ 首次隐私确认（7.5.14，✅ M34，无设备证据）→ 任务控制与恢复（7.5.10，部分：仅续跑路径）→ 结果未知语义（7.5.11，未实现）→ 审计（7.5.5，✅ M35）。前一步不稳定不要开始后一步。
4. **重跑要求（未完成）**：见风险 4；另需为“未批准 → 只回身份”“批准 → 重新观察”“撤销 → 下轮重新 `permission_required`”三条链路各写设备断言，不能只靠单元测试。M33 **未跑任何设备**。

**M33 自检记录（2026-11-15/16，仅单元与静态检查，无设备证据）**：

- Loader：`dart format --output=none --set-exit-if-changed tool test`（0 变更）、`dart analyze tool test` 无问题、`dart test` **165 通过**。
- 插件 Kotlin：`:kelivo_phone_agent:testDebugUnitTest --rerun-tasks` **170 通过、0 失败**（其中 `PackagePolicyTest` 51 项、新增 `AppWhitelistTest` 16 项）。
- 合成树：`dart analyze --fatal-infos lib test integration_test tool` **No issues found**；插件 Dart `flutter test` **25 通过**（新增 `approvedApps`/`approveApp`/`revokeApp` 用例）。
- 最终合成树 `V:/coding/kelivo-private/.tower/worktrees/wt-33/.build/worktrees/57d1793ddb8bb89e`，`modsetHash` `57d1793ddb8bb89e86577fc526f1572b582ec9761a7602569307c6bf8d029167`，`plan`/`apply`/`verify` 通过。R1 返工（`p2-4items`）只改文档，其中 `mods/phone_agent/plugin/README.md` 属 modset 内容，因此哈希由 `0c7e320a7b47d901…` 经 R1 返工两次变为本值；代码与测试逻辑未改。**未构建 APK、未接设备、未跑 integration_test**，因此没有新的 APK 大小或 SHA-256 记录。
- 本机建树需要 `core.longpaths`：Loader 的 `git worktree add` 只传 `-c core.autocrlf=false`，而上游仓有超长路径（`ThreadedInputConnectionProxyAdapterView.java`），未开 `core.longpaths` 时 `apply` 会以 `Filename too long` + `Could not reset index file` 失败。M33 用一次性的进程级 `GIT_CONFIG_*` 环境变量绕过，**未修改上游或本仓库的 git 配置**；这是 Loader 侧缺口，已作为 finding 记录，不属于本 mission 的改动范围。

## 8. 分阶段实施

### 阶段 P1：只读闭环

1. 建立独立插件、服务和通道。
2. 实现服务状态、读树、分页、密码文本隐藏。
3. 实现 API 30+ 截图、缩放、密码区域遮挡和错误映射。
4. 实现 Kelivo 适配层、视觉能力门控和图片落盘。
5. 完成 Dart/Kotlin 单元测试和只读真机测试。

完成条件：真机能通过工具看到截图和树，历史轮次能按现有机制回放图片，非视觉模型不会收到图片。

### 阶段 P2：基础输入与端到端流程

1. 实现节点句柄注册、TTL 和目标重验。
2. 实现归一化坐标观测和输入。
3. 实现 `tap`、`long_press`、`set_text`、`scroll`、`swipe` 和系统返回。
4. 完成真实调用集成测试，而非只验证 import 或编译。

完成条件：在无账号测试界面完成“截图/读树 → 点击 → 输入 → 滑动 → 再观察并确认结果”。

### 阶段 P3：技术护栏与异常路径

1. 实现锁屏、断连、超时、预算、测试包白名单和系统窗口拦截。
2. 验证旋转、切窗、服务中断、截图限频和 secure window 错误。
3. 检查日志、图片落盘和历史回放中的隐私行为。
4. 运行上游手机控制回归测试。

完成条件：所有技术护栏均有自动化测试，异常路径不会挂起工具循环或误用旧目标。

### 阶段 P4：VLM 验证与中文维护文档

1. 使用同时支持工具调用和图片输入的已配置模型执行固定安全任务。
2. 验证模型不需要 `snapshot_id`，可在同一页复用有效句柄。
3. 验证原生 `phone_control` 不会与 Mod 工具同时暴露。
4. 使用 Loader 的 `rebase-drill` 检查新基线，并处理 vendored 漂移提醒。
5. 完善中文 README：选择、授权、白名单、限制、更新和故障排查。

本轮进展：第 1-3 项已在 API 35 模拟器用 magpie `llama-cpp/llama-cpp` 完成，并补充跨新用户轮次历史图片回放（见 9.4）；第 4 项 `rebase-drill` 未在本轮执行；第 5 项中文 README 已维护。物理 MIUI API31 真机由 `llama-cpp/llama-cpp` 完成归一化坐标 tap（打开抽屉/Settings/Search），由 magpie `mistral/deepseek-v4-1-flash-1017` 完成真实图片请求、归一化坐标 swipe 的 UI 效果和像素专属视觉确认（见 9.4.2）；`llama-cpp/llama-cpp` 的物理完整坐标 swipe 仍未完成。

完成条件：所有可用环境中的 Phone Agent 验收项通过；无法执行的硬件/模型项目明确记录为未验证。

### 阶段 P5：UI 与选择契约改造（已完成）

1. 新增独立 `phone_agent` localToolId 和三态选择状态；不加入 `LocalToolNames.all`。
2. 新增移动和桌面 Mods 设置入口，宽窄屏共用简单页面，不接设置搜索。
3. 实现三态互斥写入：关闭移除两者；原生保留 `phone_control`、移除 `phone_agent` 并继续走上游授权页；Phone Agent 写入 `phone_agent`、移除 `phone_control`。
4. 已有仅启用 `phone_control` 的助手保持原生，不自动迁移。
5. 实现服务状态面板：supported、enabled、connected、sdk 和由 `enabled && connected` 派生的 ready，以及刷新、打开无障碍设置、能力/隐私说明；API 29 显示截图限制但允许 ready。
6. 产品文案进入 ARB，补齐英文描述，运行 `translate.py sync` 和 `check`，同步所有目标语言和生成文件；标准 sync 已由本机免费 llama-cpp 完成，四目标语言 0 pending，`l10n-generated.patch` 已生成。
7. `PhoneAgentMod` 激活时过滤原生 `phone_control` 和重复 `phone_agent_*`；执行前重查 `phone_agent`；错误码改为 `phone_agent_disabled`。
8. 更新 `mod.json`、`local-tool-mutual-exclusion.patch`、`settings-entry.patch`、`l10n-source.patch`、`l10n-generated.patch`、overlay、测试和文档。

完成条件：三态选择、冲突处理、旧助手保持原生、服务状态、入口、ARB 和执行前重查均有自动化测试；最终 Flutter 255（254 通过 + 1 Windows 条件跳过）、插件 Dart 17、插件 Kotlin 55、上游 PhoneControl 49、Loader 165 通过；真机官方测试退出码 0；Loader verify 通过。仍不宣称第二阶段全部完成，未验证项见 10.2。

### 阶段 P6：应用批准契约（第 2–5 步与第 8 步审计已实现；第 6、7 步部分未实现；来源分层见 7.5.9）

> 契约全文见 7.5.4、7.5.9–7.5.14 与 7.6 末的「M32 实现顺序与必须先定论的前提」。
>
> **M33 完成第 2、3 步（含构建期 deny 清单与预批准条目）；M34（2026-11-16）完成第 4、5 步的交互面**（聊天卡片、通知栏批准、pending 请求状态机、首次隐私确认、Mods 页白名单管理）；**M35 完成第 8 步审计元数据**。三者都只有单元与静态检查证据。**仍未实现**：按任务的控制权、结果未知语义的专门文案与错误码、多窗口首版策略；**没有任何设备证据**，因此以上均不计入已完成验收。

1. **先定论三项未定稿**（7.5.12 多窗口是否拒绝、7.5.10 任务控制冲突的错误码、7.5.14 provider 更换是否重新提示），并回写本文，再动对应代码。观察侧判 `package_not_allowed` 与「构建期范围转 deny 清单」已定为 tower 定论（7.5.1/7.5.4），M33 已按契约实现；若用户推翻需先回写文档。**M33 没有因此改动这三项的任何一项**。
2. **应用身份与签名绑定（✅ M33 已实现）**：manifest 一次声明 `QUERY_ALL_PACKAGES`；`(包名, 签名 SHA-256 集合)` 双匹配；同签名更新保留授权；签名变化或无法解析 → 未批准；首版明确不支持应用分身与工作资料（不做多用户查询）。设备能力（服务进程内解析任意前台包签名）**未实测**。
3. **白名单门控接入观察与输入（✅ M33 已实现）**：构建期范围已从 allowlist 转为 deny 清单（初始为空）；非 deny 成员的未批准应用返回 `permission_required` 且只带应用身份，deny 成员返回 `package_not_allowed`；硬基线与窗口类型仍排在前面；测试包恒预批准、debuggable 构建额外预批准跨 UID 夹具包。
4. **批准交互与终态（✅ M34 已实现，无设备证据）**（7.5.6/7.5.13）：卡片 + 通知两入口、TTL、单终态、迟到回调按请求 id 校验、防自我批准；通知 action + `BroadcastReceiver` 是新增基础设施。实现细节见 7.5.6 的「M34 实现事实」。
5. **首次启用隐私确认（✅ M34 已实现，无设备证据）**（7.5.14，方案 B）：只在首次，不每张截图询问；文案进 ARB，四目标语言 0 pending。
6. **任务控制与恢复（部分实现）**（7.5.10）：「允许并继续」的续跑路径已接通（只发送一条要求重新观察的用户消息，不重放动作）；**同时只一个任务控制手机、停止后未执行请求失效**仍未实现。
7. **结果未知语义（未实现）**（7.5.11）：已派发的超时/取消不盲目重试，先重新观察，区分动作完成与业务成功。
8. **审计（✅ M35 已实现，无设备证据）**（7.5.5 第 3 项）：落盘七项元数据，滚动保留 30 天或最近 2000 条先到者生效；`AuditLog.kt` + `noBackupFilesDir/phone_agent_audit.tsv`；助手/会话 id 由通道可选参数传入，缺失记 null；审计失败静默计数、不阻断主路径；**没有任何读取通道或界面**。

完成条件（未达成，未验证）：上述每项都有明确错误码、英文模型文案、JVM/Dart 测试；设备上至少跑通“未批准 → 只回身份 → 批准 → 重新观察 → 撤销 → 重新 `permission_required`”完整链路，并按 7.6 风险 4 重跑官方测试、完整异常套件与 VLM 固定任务。在此之前只能写「批准契约仅实现门控与签名绑定，交互与设备验证未完成」。

## 9. 测试与验收

### 9.1 Kelivo 与 Mod Dart 测试

在合成 worktree 中：

```bash
flutter pub get
flutter pub get --directory tool/l10n --enforce-lockfile
dart format --output=none --set-exit-if-changed \
  lib/features/phone_agent lib/features/mods test/features/phone_agent \
  test/features/mods test/features/settings/pages/mods_settings_entry_test.dart
dart analyze --fatal-infos lib test integration_test tool
flutter test test/features/phone_agent
flutter test test/features/mods
flutter test test/features/settings/pages/mods_settings_entry_test.dart
flutter test test/features/home/services/phone_control_test.dart
flutter test test/features/home/services/tool_handler_service_test.dart
flutter test test/features/home/services/tool_handler_workspace_gating_test.dart
flutter test test/core/services/api/tool_result_content_test.dart
flutter test test/core/services/mcp/mcp_image_snapshot_test.dart
flutter test test/utils/mcp_structured_image_test.dart
flutter test test/core/services/api/request_image_context_test.dart
flutter test test/request_consistency_test.dart
```

ARB 同步与检查：

```bash
python3 tool/l10n/translate.py sync
python3 tool/l10n/translate.py check
flutter gen-l10n
```

标准 sync 已由本机免费 Magpie llama-cpp/llama-cpp 完成：23 个键已翻译，`translate.py check` 四个目标语言（ko、ru、tr、zh_Hant）均 0 pending，`l10n-generated.patch` 已生成；未使用付费服务。Magpie Python UA 适配只是临时进程环境，不属于 Mod 交付，文档不记录其临时路径作为依赖。

同时执行项目要求的 markstream 检查：

```bash
cd dependencies/markstream
flutter pub get
dart analyze --fatal-infos
```

新增适配测试至少覆盖：

- Android、助手 `phone_agent` 开关、工具能力和视觉能力门控；
- 激活时过滤原生 `phone_control`，未激活时恢复；
- 激活时过滤重复 `phone_agent_*` 定义，不重复暴露；
- 生成途中撤销 `phone_agent` 后返回 `phone_agent_disabled`；
- 未识别工具名和 `toolCallId` 原样透传；
- 三个 schema 不含 `snapshot_id`；
- 非视觉模型没有截图定义和坐标输入能力；
- 截图元数据、实际尺寸、尺寸不一致失败；
- `PhoneAgentScreenshotResult` 产出的 `ClientToolResult`/metadata 经现有 `ToolResultContent.read`：支持图片时产生非空图片引用，不支持图片时省略图片并保留文本；
- 错误信封、超时、服务断开和插件异常不终止聊天；
- 不调用 `app.device_tools`。

本轮 UI/选择契约新增测试至少覆盖：

- 三态单选互斥：关闭、原生、Phone Agent 写入后不会同时保留两个 ID；
- 选择原生时移除 `phone_agent` 并进入上游授权页；
- 选择 Phone Agent 时移除 `phone_control`，且不自动打开系统无障碍设置；
- 选择关闭时移除两者，且不自动关闭系统服务；
- 仅启用 `phone_control` 的助手显示为原生，打开 Mods 页不自动改写；
- 两个 ID 同时存在时显示冲突并要求选择；
- 服务状态 supported/enabled/connected/sdk 的加载、刷新和失败态；API 29 上 `supported=false` 但 `enabled && connected` 时 ready=true，树/节点输入可用，截图返回 `unsupported_os`；
- 打开无障碍设置失败时的提示；
- 移动和桌面入口都能打开同一个页面；
- 设置搜索索引不包含 Mods 页；
- ARB 键在英文和中文源文件中成对存在，描述完整；`translate.py check` 四目标语言 0 pending；`l10n-generated.patch` 已生成；
- 非 Android 平台显示平台不支持且不添加工具，不要用 `supported=false` 表示平台不支持。

### 9.2 Android 测试

先通过 `./gradlew projects` 确认插件模块名，再运行对应模块测试，不预先硬编码可能错误的 Gradle 路径。

测试覆盖：

- DFS、分页、字符上限、不可见节点和密码子树；
- 句柄重新编号、TTL、窗口变化和指纹变化；
- 同一已刷新节点仅 `isFocused` 变化（false→true 与 true→false）时句柄仍可复用并完成 `set_text`；
- 仅动作集合 `actions` 变化时句柄仍可复用，动作可用性由执行层按当前节点校验；
- 仅 `isSelected` 变化时仍返回 `stale_handle`，稳定能力字段（如 `isScrollable`）变化也仍返回 `stale_handle`，证明本轮没有一次性放宽全部指纹字段；
- 含 NUL 的文本变化只报告 `text` 字段名，`stale_handle` 不包含 NUL 后的内容；
- 前置重验三项精确诊断：`refresh()` 为 false 时消息含 `refresh_failed`、`isVisibleToUser` 为 false 时含 `not_visible`、`isEnabled` 为 false 时含 `not_enabled`，错误码均为 `stale_handle`，且消息不含节点文本；刷新失败优先于可见性和可用性判断；
- `performNodeAction` 在请求动作从当前节点移除后返回 `action_unavailable`，且不执行 `beforeAction` 或 `perform`；
- M24 路径重解析：`refresh()` 失败后按子索引路径重解析并要求指纹逐字段一致时句柄可继续用于 `set_text`；重解析出的节点指纹不同、路径缺失、无活动窗口 root 时仍返回 `stale_handle`（含 `refresh_failed`）；`refresh()` 成功时不触发重解析；重解析结果会被同一观测的后续动作复用；
- 读树记录每个节点的从根子索引路径（`TreeObservation.paths`），嵌套节点的路径与父 id 一致；
- 动作后有效句柄可复用，失效句柄不会重定向；
- 归一化坐标、越界、NaN、旋转和尺寸变化；
- 节点动作、系统导航、手势回调和并发 `busy`；
- 截图缩放、密码区域遮挡、限频和 secure window 错误；
- 锁屏/息屏、服务中断和 pending 请求完成；
- 白名单与系统窗口拒绝；
- 硬基线扩展（M27）：`com.android.settings` 与常见厂商变体（`com.miui.securitycenter`、`com.xiaomi.misettings`、`com.coloros.*`、`com.oplus.*`、`com.samsung.android.settings`、`com.huawei.systemmanager`）、厂商包安装器（`com.miui.packageinstaller`）、厂商权限控制器（`com.lbe.security.miui`）与证书安装器（`com.android.certinstaller`）均返回 `system_window_denied`；默认电话/短信角色持有者被拒；`RoleHolders.Unavailable` 时拒绝全部输入（`role_resolution_failed`）；Kelivo 自身 `com.psyche.kelivo` 被拒而测试包 `com.psyche.kelivo.phoneagent` 不被误伤（含 `com.psyche.kelivo.phoneagent.other` 前缀反例）；
- 窗口类型（M27）：`INPUT_METHOD`/`SYSTEM`/`ACCESSIBILITY_OVERLAY`/`SPLIT_SCREEN_DIVIDER`/`UNKNOWN` 均返回 `system_window_denied`，仅 `APPLICATION` 放行；平台常量映射含未定义值 0 与 99 回落 `UNKNOWN`；拒绝消息含固定标识 `window_type_*` 且不含包名；硬基线优先于窗口类型、窗口类型优先于构建期白名单；
- `WindowState.windowType` 变化使树分页、句柄和截图观测失效（`stale_observation` / `stale_handle`）；
- 输入错误码优先级（M33）：空包名 `no_window` → 硬基线/角色/窗口类型 `system_window_denied` → 构建期 deny 成员 `package_not_allowed` → 未批准 `permission_required` → 白名单内句柄/截图校验；
- 白名单与签名绑定（M33，`AppWhitelistTest` + `PackagePolicyTest`）：`(包名, 签名集合)` 双匹配；多签名包要求整集合相等（`com.android.vending` 实测 2 枚），仅集合顺序不同仍视为相同；签名变化、签名集合增删与签名解析失败（含批准写入前重解析）都按未批准处理且 fail closed；批准写入幂等（重复批准只更新最后批准时间、保留首次来源、不产生第二条记录）；签名变化后的迟到批准因 `expected_signing_sha256` 不符而不写入；撤销立即生效；白名单经文件往返后仍可读；损坏行被忽略而不是被信任；白名单全局共享（不同 store 实例读同一份存储）；
- 构建期范围（M33）：deny 清单初始为空且不与硬基线集合重叠；deny 成员在输入与观察两条路径都返回 `package_not_allowed`，且**排在用户白名单之前**（已批准也会被拒）；非 deny 成员未批准返回 `permission_required`；`package_not_allowed` 文案带固定标识 `build_denied`；
- 构建配置预批准（M33）：测试包恒为预批准且不写用户白名单；跨 UID `securefixture` 只在 debuggable 构建预批准（release 返回 `permission_required`）；预批准不影响其他应用 `permission_required` 的可达性；
- 观察侧白名单（M33）：未批准应用的读树/截图返回 `permission_required` 且消息含包名与签名前 8 位、明确“没有截图/没有读取界面文本”；签名解析失败时是 `signing_unavailable` 且不含哈希；批准后同包 `APPLICATION` 与 `INPUT_METHOD` 窗口可观察；硬基线与窗口类型仍排在白名单之前（已批准的系统包仍是 `system_window_denied`）；
- 审计元数据（M35，`AuditLogTest` 15 项 + `AuditRecorderTest` 10 项）：`AuditRecord` 声明的字段集合**恰为契约七项**（反射断言），七类禁字段（节点文本、输入文本、密码、截图/图片字节、界面摘要、坐标、窗口标题）逐个断言不存在；TSV 每行恰好 7 列且带表头；空身份列往返后仍为 null；超过 30 天的记录被淘汰而**恰好 30 天仍保留**；超过 2000 条时从前淘汰、保留最近 2000 条；超限的历史文件在加载后被裁剪；损坏行（时间戳不可解析、列数不足、动作或结果码为空）被丢弃而不是被信任；字段内的制表符与换行不能破坏列数；字段截断到固定长度；写入失败与读取失败都不外抛（写入失败只增加本地计数）；`recordSafely` 在签名解析抛异常时把该字段降级为 null 且仍写入成功；`AuditAction` 只输出固定 token，未知输入动作降级为 `input`，且动作名不含文本/节点 id/坐标；`AuditIdentity` 对畸形值（非字符串、空白、缺失）返回 null 而不抛错；`clearScreenshot`、`status`、白名单三方法不产生审计动作；
- debug 夹具 `SecureWindowFixtureActivity` 的 `FLAG_SECURE` 开关、纯色像素和权限请求（只请求、不授予、不使用敏感能力）；
- 独立服务状态 supported/enabled/connected/sdk 的通道返回；API 29 上截图能力为 false，但 ready 状态与树/节点输入仍可用。

同时运行上游既有测试：

```bash
cd android
./gradlew :app:testDebugUnitTest --tests com.psyche.kelivo.PhoneControlServiceTest
```

### 9.3 构建与真机

```bash
flutter build apk --debug
flutter test integration_test/phone_agent_test.dart -d <android-device-id>
```

## 9.3.0 M30（M28 设备回归补测）的测试侧诊断改动

M30 只验证与记录，不改产品代码、不放宽任何断言。`phone_agent_exception_test.dart` 的改动分两类：**只记录、不断言的诊断**，以及**测试夹具前提的等待/兜底**（后者已在此逐条说明其边界，不改变任何断言的通过条件）。

只记录、不断言的诊断：

- `_TreeProbe`（常量与 `_tryTree`/`_tryTreePayload` 附近）：记录最近一次读树的真实结果——包名、错误码、消息、节点数、是否含同包夹具文本、是否抛异常。`_waitForTreeText` 的失败消息从「最后前台包名：X」扩为「读树 N 次，最后前台包名：X，最后错误码：Y，最后消息：Z」。**轮询次数、超时、`fail` 条件、错误码断言全部不变。**
  理由：旧消息只拼包名，`_tryTree` 又把「被拒绝」和「抛异常」都折叠成 `null`，于是旧日志里 `exc8`/`exc9` 的「最后前台包名：未知」无法区分「读树被拒（什么错误码）」「调用异常」「读树成功但包名不符」。
- `PHONE_AGENT_STALE_COORDINATES`：在 secure 同包夹具切窗后的坐标输入处打印实际 `type`/`error`/`message`。历史 `exc5` 在此处实得 `screenshot_required`，而断言仍要求 `stale_observation`；先记录、后断言，不修改期望值。
- `PHONE_AGENT_RESTART_STALE_HANDLE`：服务重启后旧句柄输入的实际错误码与消息。
- 旋转用例补 `repump: () => _pumpHarness(tester)`（与锁屏用例同一机制，第 311 行附近）。这是**测试夹具**的既有兜底手段，不新增等待语义，也不改变任何断言。
- 服务重启用例在旧句柄输入前加入 `_waitForStableWindow`：用**截图**（只写 screenshot 观测，不触碰树观测）做有界前置等待（30 秒），并有独立断言「有界等待内无法取得前台窗口则失败」。**不重读树**（会重置 registry 里的旧句柄），**不循环重试输入**，`stale_handle` 的精确断言保持不变。可继续等待的错误码限定为 `no_window`、`rate_limited`、`stale_observation`（窗口已取得但截图期间切换，属瞬态），以及观察边界拒绝里**明确属于「前台还没回到应用」的子集**：`hard_baseline`、`window_type_system`、`window_type_overlay`、`window_type_split_divider`。**`window_type_unknown` 刻意排除**——它表示窗口列表尚未稳定、类型解析失败，把它当作「稍后会好」会让真实时序缺陷静默通过（与同文件 `_isObservationBoundaryMessage` 的取值规则一致）。其他错误立即停止并打印 `PHONE_AGENT_RESTART_WAIT_STOPPED`（含 `message`，便于区分实际来源）。
- `PHONE_AGENT_SERVICE_DISABLED_STATUS` 与有界状态等待：run10 的 `elapsed=1979ms` 那次读不到 false，run5/run9 的 `≈6000ms` 那次可读到。因此 `disabledStatus` 读取前加**只读状态查询**的有界等待（20 秒、500ms 间隔、仅当 `enabled` 仍为 true 时继续），不重发输入、不重试动作，`enabled isFalse` / `ready isFalse` 断言不变。注意这一条只是观测事实（禁用瞬间状态可能仍为 true），**不是**对「宿主确认关闭已完成」的因果证明。

- **启用来源唯一化（P2-4）**：`setUpAll` 通过 `_waitForService` 打印唯一的 `PHONE_AGENT_WAITING_FOR_SERVICE`；服务重启用例只打印 `PHONE_AGENT_ENABLE_SERVICE_NOW`，之后改调**不打印标记**的 `_waitForReady`。此前该用例还会调用 `_waitForService`，导致两个启用标记并发，宿主可能重复执行启用动作。阶段握手（ACK 通道）仍未实现，仍依赖固定等待；这是已知边界，不是已验证。

## 9.3.0.1 M30 设备结果（API35 `emulator-5554`，2026-11-14/15）

运行树共**三棵**，**产品代码零改动**（合成树内产品源码未手改，测试文件来自 wt-30 overlay）：

- `f26c1c7ed3238610`（`modsetHash` `f26c1c7ed3238610…`，与 M28 最终树同哈希）：`run17`/`run18` 两轮异常套件与 `official_api35.log` 官方测试。
- `b9ed56f89b3146c9`：`run19` 异常套件与 `official_final.log`。**该树不能作为 run19 的可复现基线**——run19 结束后，该树里的 `integration_test/phone_agent_exception_test.dart` 被就地改写为 LF（现 mtime 晚于 run19 结束时间），因此磁盘上现在的文件**不是** run19 实际执行的输入；run19 当轮的测试文件内容未留存。其 `+8`/`+2` 只作「又一棵树也是绿的」这一方向性记录。
- `8a44ec55a023185e`（`modsetHash` `8a44ec55a023185e58c89f4c7b40d4aa62cee2a6c402f22eebb8870f7a410102`，`plan`/`apply`/`verify` 通过）：`run20` 异常套件与 `official_lf.log` 官方测试跑在这棵树上；其测试文件（LF）与**返工前**分支 blob `72f5b605…` 一致。R1 返工改了测试文案，因此它**不再**是当前 tip 的测试文件；返工后的最终交付树见下方 blockquote。

Android 15 / API 35。

> **R1 返工后的最终交付树是 `474262a402cca985`**（`modsetHash` `474262a402cca985f216636ac8dbd0b8af9ffd31507acb7feb1614a103853fac`，`plan`/`apply`/`verify` 通过）。返工只改文档、测试文案与新增宿主脚本，**未重跑设备**；`run17`–`run20` 的设备结果对应返工前的测试文件。返工对测试的改动是：`_waitForStableWindow` 的可重试集合排除 `window_type_unknown`（收窄，不影响已通过的轮次——`RESTART_WAIT_STOPPED`/`TIMEOUT` 在 run17–run20 均为 0 次）、失败文案改为不写死 `no_window`、服务重启后用不打印标记的 `_waitForReady` 消除双触发。这些改动都不改变任何断言的通过条件。

**异常套件 `phone_agent_exception_test.dart`：四个绿轮、`+8`、`All tests passed!`、EXIT=0**——`run17.log`（477s）、`run18.log`（490s）在 `f26c1c7ed3238610`；`run19.log`（721s）在 `b9ed56f89b3146c9`；`run20.log`（574s）在 `8a44ec55a023185e`（返工前测试树）。即 **3 棵树 / 4 轮**全部 `+8`。可复现的基线是 `run17`/`run18`（同一棵树、同一份测试文件）与 `run20`（`8a44ec55a023185e`，其测试文件等于返工前分支 blob `72f5b605…`）。

| 用例 | 结果 | 设备证据 |
| --- | --- | --- |
| FLAG_SECURE 截图行为与恢复 | ✅ 通过 | `PHONE_AGENT_SECURE_PLATFORM_BLACK_IMAGE`（secure 夹具返回成功黑图，符合契约） |
| 叠加层不污染产品截图 | ✅ 通过 | 中心 60% 逐像素一致、强调色增量 < 50 |
| 叠加层可见时真实触摸不被拦截 | ✅ 通过 | `OVERLAY_HOST_TOUCH_RESULT: package=com.android.systemui error=system_window_denied`，消息含 `hard_baseline` |
| 旋转后旧句柄与旧截图失效 | ✅ 通过 | 旧句柄 `stale_handle`、旧坐标 `stale_observation`，转回竖屏后重新找到目标 |
| home 与 recents 后输入被包名策略拒绝 | ✅ 通过 | `SYSTEM_NAVIGATION_FOREGROUND: action=home/recents package=com.google.android.apps.nexuslauncher`，两种输入错误码一致 |
| 权限窗口输入被拒绝 | ✅ 通过 | `PERMISSION_TREE: package=null type=tool_error error=no_window`；宿主独立确认 `com.google.android.permissioncontroller/...GrantPermissionsActivity`，`POST_NOTIFICATIONS` 仍为 false |
| 锁屏 device_locked 与解锁恢复 | ✅ 通过 | 树/截图/输入三处均 `device_locked`；解锁后旧句柄 `stale_handle` |
| 服务禁用中断与重新启用恢复 | ⚠️ 部分 | **禁用与中断行为已验证**：`PENDING_BATCH: size=200/400 elapsed=4156–6572ms codes=interrupted,stale_observation`（含 `service_unavailable` 的轮次亦见）、`DISABLED_STATUS: enabled=false connected=false ready=false`。**重启后旧句柄不可用已验证**：`RESTART_STALE_HANDLE: error=stale_handle message=No current tree observation`。**但「服务重启清除了树」这一机制不可独立归因**——见下方「证明边界」 |

### 证明边界：「服务重启后旧句柄不可用」不等于「清树机制已被验证」

该组合用例最后那句 `stale_handle / No current tree observation` 与至少三种机制**完全兼容**，无法区分是哪一种（或哪几种）导致的：

1. **分页请求自己清树**。用例先在测试应用前台建旧树（`phone_agent_exception_test.dart` 的 `before = await _tree(service)`），随后轮询读树直到宿主已进入设置页并被观察边界拒绝，再循环发起 `_readTreeCode(service, offset: 1)`。分页走 `PhoneAgentService` → `registry.page()`，而 `ObservationRegistry.page()` 调 `requireTreeValid()`（`ObservationRegistry.kt:213-225`）：此刻前台是 `com.android.settings`，`sameWindow()` 必不相等 → **`clearTreeLocked()` 后抛 `stale_observation`**。也就是说，pending 批次的第一块请求在服务被禁用**之前**就已经把旧树清掉了。日志与这条路径一致：`run17.log`/`run18.log` 的 `codes=interrupted,stale_observation`，`run19.log`/`run20.log` 的 `codes=interrupted,service_unavailable,stale_observation`。
2. **120 秒 TTL 自然过期**。`ObservationRegistry.DEFAULT_TTL_MILLIS = 120_000`。从建旧树到旧句柄输入之间是一整段设置页交互 + pending 批次 + 重新启用 + 前台恢复，远超 120 秒。
3. **服务中断的 `invalidateAll()`**。`PhoneAgentService` 的 `interruptPending()` 会调 `registry.invalidateAll()`（同时清树与截图）——这正是该用例**想要**验证的那条路径，但它与上面两条不可分离。

因此本条只能断言：**禁用与中断行为已验证；重启后旧句柄不可用已验证；清树的具体机制不可独立归因**。窗口 id 变化同样能使旧树失效（`ObservationRegistry` 的 `sameWindow()` 比较 `windowId`），也无法排除。

要真正独立证明「服务重启清树」，需要把重启拆成独立子场景（宿主预定位详情页后返回应用、测试新建树并在读树前启动总预算、此后禁止任何 `offset 0/1` 读树、各阶段用 ACK 握手），并且总预算需显著小于 120 秒 TTL。M31 只读 survey（`.tower/comms/missions/M31-phone-agent-m30-restart-regression-evide.md` 与其 survey 报告）已给出该方案的完整设计与阶段预算，**本轮未实施**——它需要新的设备轮次，属另一个 mission，不是文档返工。

机制层面的支撑目前只有既有 JVM 测试 `ObservationRegistryTest` 的 `invalidateAll clears handles`（纯 JVM，不覆盖真实 Android 生命周期）；不得据此宣称真实服务重启的清算路径已通过设备验证。

**官方 `phone_agent_test.dart`：`+2`、`All tests passed!`、EXIT=0**（`official_api35.log` elapsed 334s，运行树 `f26c1c7ed3238610`；`official_lf.log`，运行树 `8a44ec55a023185e`）。覆盖截图 → 读树 → 节点点击 → 坐标滑动 → 节点滚动 → 聚焦后 `set_text` → 二次读树，以及 Mods 页三态选择。

**`exc5` 的 `screenshot_required` vs `stale_observation` 归因**：`PHONE_AGENT_STALE_COORDINATES` 在 run10/11/12/13/17/18 六轮一致给出 `error=stale_observation`、消息 `The screen changed since the screenshot`。产品侧的判定是 `ObservationRegistry.requireScreenshot` 里的两个**确定性分支**（同一把 `@Synchronized` 锁内顺序判断）：screenshot 槽位为 `null` → `screenshot_required`；槽位存在但 TTL 过期或窗口/包名/尺寸/旋转/窗口类型变化 → `stale_observation`（并清空槽位）。

- **已确认**：两个错误码语义不同，优先级由该 if 顺序固定；`exc5` 报 `screenshot_required` 说明进入那一刻**槽位已经是 null**，而不是「窗口变化被误判」。因此这不是错误码优先级缺陷，断言期望值本身没有过期。
- **槽位被清空的可能来源**（读代码确认存在，但 `exc5` 未留存是哪一条）：`ensureUnlocked()` 在锁屏/息屏时调 `invalidateAll()`（同时清树与截图，且它是**每个动作前**的 `beforeAction`）；`interruptPending()` 调 `invalidateAll()`；`executeNode` 在任意节点动作后调 `clearScreenshot()`。
- **未定性**：`exc5` 当轮究竟是「协作时序（息屏/服务中断/前一个节点动作）」还是「产品在无前置动作时自行清空」，**没有留存证据**（旧日志不含槽位状态与前置动作序列）。按 tower 的要求，**同树 `exc4` 通过、`exc5` 失败这一旁证不足以排除竞态回归**，本结论不据此断言「非缺陷」；要定性需要一轮在坐标输入前直接记录槽位状态与中间动作日志的复跑，尚未做。

## 9.3.0.2 M30 的关键归因：`最后前台包名：未知` 与两个用例的失败机制

### 已确认（有原始日志）

1. **`未知` 的直接成因是诊断缺失，不是产品缺陷**：`_waitForTreeText` 的失败句只拼 `last?['package_name']`，而 `_tryTree` 把「被观察边界拒绝」「payload 非 ok」「抛异常」都折叠成 `null`。加入 `_TreeProbe` 后，`run1.log` 记录到该轮 102 条探测结果为 `system_window_denied` + 消息 `(com.android.systemui, hard_baseline)`，`package_name` 为 null；其中**单次探测内连续 77 次**全是同一结果（该次数是单个 `_waitForTreeText` 内的计数，不是整轮总次数）。
2. **`run1` 那一轮通知栏占据前台是宿主驱动缺陷**（该轮设备 logcat 当轮观察到 `mCurrentFocus` 为通知栏窗口，**未留存**；`.build/diag` 中无该串，最早留存的 `NotificationShade` 出现在 `run10.log`）：旧驱动的 `open_shade()` 是固定 13 秒循环，`PHONE_AGENT_OVERLAY_HOST_TOUCH_RECOVER` 之后它仍在继续 `input swipe`，`keyevent 4` + `am start` 抵不过持续手势。修复为「检测到 `NotificationShade` 即停止 + 可取消 + `cmd statusbar collapse`」后，`run3` 起再未出现该模式。**该结论只解释 run1 这一轮，不能外推旧 `exc8`/`exc9`**——那两份原始日志已不在磁盘，其错误码无留存证据。
3. **旋转用例在 run9 的失败源自驱动误发 BACK**：`recover_from_shade()` 里有一句无条件 `keyevent 4`。`run9` 时 `cmd statusbar collapse` 已关闭通知栏，这一下 BACK 落到 `MainActivity` 并把它 finish。**该轮 logcat 当轮观察到任务被 finish（`Transition requested ... type = CLOSE`，紧随 `START ... LAUNCH_SINGLE_TASK`）与产品的窗口类型解析耗尽日志（`windowType exhausted ... rootWin=... entries=...`），但这些原文未留存**（`.build/diag/` 中 `Transition requested`、`rootWin=` 均零命中，`run9.log` 内 `PhoneAgentDiag` 计数为 0），因此只以「当轮观察到、未留存」口径引用，不作为可核对证据。可留存的旁证是 `run9.log` 的计数事实：读树返回 `window_type_unknown` 30 次，而 `run5` 为 0 次。改为**绝不发 BACK**后，`run10`–`run18` 该标识恒为 0；`run19` 在夹具→应用切窗的过渡中出现 **1 次瞬态**（下一轮读树即恢复、该轮仍通过），`run20` 为 0。说明它并非绝对不出现，只是不再成批出现。
4. **服务重启用例的多轮失败逐一归因到驱动或测试夹具**：`hard_baseline (com.android.settings)`（设置页在过渡中回到前台 / `ENABLE_SERVICE_NOW` 重新打开设置页）、前台确认过慢把 `am start` 拖到约 14 秒（超出测试自身 5 秒窗口）、`stale_observation`（窗口已取得但截图期间切换）、`status().enabled` 短暂抖动。修完后 `run17`/`run18` 稳定给出 `stale_handle`。

### 属于假设或未验证

- `window_type_unknown` 那次迟滞的具体成因（任务重启触发的窗口列表重建，还是模拟器时序）**没有独立证据**；只能确认它由驱动 finish 任务后出现、且不再出现于修正后的轮次。产品侧 2500ms 有界预算短于实测约 3 秒滞后，这一已知限制未变。
- `run16` 的 `am start` 耗时约 14 秒被归因到驱动的 3×0.8s 稳定确认，**属时间相关性推断**，不是直接剖面证据。

## 9.3.0.3 M30 物理 MIUI（`1960cd68`，Android 12 / API 31）

**官方 `phone_agent_test.dart`：`+2`、`All tests passed!`、EXIT=0**（`official_miui.log`，elapsed 107s）。这是 M28 遗留的「MIUI 官方测试只有通过迹象、无留存日志」一项的补齐：本次有留存日志。

- 运行树同 API35（`f26c1c7ed3238610`，产品代码零改动）。测试 APK 先用 `adb install -r` 预装（含 17 个 `arm64-v8a` 库），随后 `flutter test` 覆盖安装。
- 授权路径使用本机例外：`settings put secure enabled_accessibility_services` + `accessibility_enabled=1`，`dumpsys` 确认 `bound=True`。**当轮真实原值**：`enabled_accessibility_services=null`、`accessibility_enabled=0`、`stay_on_while_plugged_in=0`，运行结束后已逐一恢复为原值，并在设备上 `get` 复核得到 `null`/`0`/`0`。**保存与恢复动作本身未写进留存日志**（`.build/diag/` 中无 `Deleted`/`BEFORE:`/`AFTER:` 记录），这里只作操作者陈述 + 事后复核，不当作日志证据。
- 运行期间用 `svc power stayon true` 保持常亮（原值 `0`，已恢复）。此前一轮因 MIUI 中途休眠而得到 `device_locked`（截图用例），产品判定正确；该失败记录在 `official_miui.log` 历史轮次中，不当作产品缺陷。
- **未在 MIUI 上运行异常套件**：该设备未安装 `com.kelivo.phoneagent.securefixture`，而异常套件依赖 `SecureWindowFixtureActivity` 与跨 UID 安全窗口夹具。这是设备准备缺口，不是产品结论；异常套件只在 API35 有结果。
- 环境记录：MIUI 构建曾两次因 native-assets hook 下载预编译产物失败（`ClientException with SocketException ... address = github.com`），改用合成树中已构建的 APK 后正常。这与产品无关。


真机前置：

- Android 设备；截图与坐标手势需要 API 30 或更高；API 29 服务可 ready 并验证读树和节点输入，截图返回 `unsupported_os`，页面显示截图限制；
- 测试设备已解锁；
- 在 Mods 页为测试助手选择 Phone Agent；
- 在系统无障碍设置中启用独立的 Phone Agent 服务；
- 只使用无账号测试界面和显式测试包名；
- 默认关闭后台悬浮胶囊。

最终真机结果（官方测试退出码 0）：

1. 设置 → Mods → 真实 enabled/connected/API 29 状态 → 助手选择 Phone Agent 且与原生互斥。
2. 读树、节点点击、`set_text`、节点滚动、二次读树；截图按预期返回 `unsupported_os`。

上一轮节点重验修正后的设备结果（历史）：

- **M28 第 2 步（观察边界）设备结果（API35 `emulator-5554`，Android 15）**：合成树 `V:/coding/kelivo-private/.tower/worktrees/wt-28/.build/worktrees/0328aca335a3ceec`（`modsetHash` `0328aca335a3ceec71d00caa8beee688af26d317910ca9dcabcbc8948026fc24`），`flutter test integration_test/phone_agent_test.dart -d emulator-5554` → **`+2`、`All tests passed!`、EXIT=0**（截图 → 读树 → 节点点击 → 坐标滑动 → 节点滚动 → 聚焦后 `set_text` → 二次读树，以及 Mods 页三态选择）。
- **官方测试在最终树上也跑过（R2 F3 修正）**：`final2_official.log`（22:28）首行即 `loading .../worktrees/c3c760c0d4502878/integration_test/phone_agent_test.dart`，收口 **`+2: All tests passed!`、EXIT=0**。此前“最终树未重跑官方测试”的记录**与日志不符，已更正**。两树差异为 `PhoneAgentService.kt` 一行 KDoc（`WINDOW_TYPE_ATTEMPTS` → `WINDOW_TYPE_BUDGET_MS`）+ 2 条 JVM 用例，不改变行为；`0328aca3` 上那次 `+2` 是更早的独立证据。
- **M28 第 2 步异常套件结果（API35，如实记录，未取得绿色整轮）**：以下数字**逐条取自 `wt-28/.build/*.log`**，不再用“两次尝试”概括（R2 F1 修正——此前写“两次均为 `+1 -1`”只对上 `exc5.log`，而 `exc5` 跑的不是最终树）：

  | 日志 | 时间 | 运行树 | 结果 | 失败用例（`Failing tests:` 段） |
  | --- | --- | --- | --- | --- |
  | `exc5.log` | 21:58 | `e2d50da0`（非最终树） | `+1 -1` | `FLAG_SECURE 截图行为与恢复`（`Expected: 'stale_observation' / Actual: 'screenshot_required'`）+ 余下 **6** 例 `did not complete`（叠加层可见时真实触摸、旋转、home 与 recents、权限窗口、锁屏、服务禁用） |
  | `exc6.log` | 22:46 | `c3c760c0` | **`+1 -7`** | 叠加层不污染产品截图、叠加层可见时真实触摸不被拦截、旋转后旧句柄与旧截图失效、home 与 recents、权限窗口、锁屏、服务禁用 |
  | `exc7.log` | 23:01 | `c3c760c0` | **`+2 -6`** | 叠加层可见时真实触摸不被拦截、旋转、home 与 recents、权限窗口输入被拒绝、锁屏 device_locked、服务禁用 |
  | `exc8.log` | 23:22 | `c3c760c0` | **`+2 -6`** | 同 `exc7` 的 6 条 |
  | `exc9.log` | 23:50 | `c3c760c0` | **`+1 -7`** | 叠加层不污染产品截图、叠加层可见时真实触摸不被拦截、旋转、home 与 recents、权限窗口输入被拒绝、锁屏 device_locked、服务禁用 |

  - `exc5`（`e2d50da0`，非最终树）的失败**不是**叠加层问题：唯一失败用例 `FLAG_SECURE 截图行为与恢复` 报 `Expected: 'stale_observation' / Actual: 'screenshot_required'`（发生在 `PHONE_AGENT_STALE_WINDOW` 同包夹具切窗之后），另有 **6 例** `did not complete`（叠加层可见时真实触摸、旋转、home 与 recents、权限窗口、锁屏、服务禁用；另有 tearDownAll）。
  - **但该用例在最终树上是通过的（R4 F3 修正）**：四个最终树轮次 `exc6`/`exc7`/`exc8`/`exc9` 的计数都是 `FLAG_SECURE → +0`、下一条 `叠加层不污染产品截图 → +1`，两次计数之间没有其他用例，因此 `+0 → +1` 只能由 `FLAG_SECURE` 贡献，属**通过的直接计数证据**，不是推断。（`exc6`/`exc9` 的叠加层用例随后在 `+1` 基础上再 `-1` 失败，不影响 `+1` 已到手这一事实。）
  - **同代码 A/B**：`exc4`（21:43）与 `exc5`（21:58）**跑的是同一棵树 `e2d50da0`**——`exc4` 的 `FLAG_SECURE` 通过（`00:31 +0` → `01:00 +1`），`exc5` 失败（`00:41 +0 -1`）。同一份代码一次通过一次失败，说明 `screenshot_required` **不是 M28 的确定性回归**，更像时序或前置条件抖动。**这是判断（有同树 A/B 旁证），不是根因证据**；错误码优先级是否仍有问题未定位，已单独 file finding。
  - **失败模式要分开看，不能一律归为宿主时序**：
  - `exc6`/`exc7` 的多数失败是 `等待 PHONE_AGENT_TAP_TARGET 超时（标记 PHONE_AGENT_RETURN_TO_APP）。最后前台包名：com.psyche.kelivo.phoneagent`——**前台确实是测试应用**，但找不到点击目标节点，属 `_ensureAppForeground` 重 pump 的宿主时序。
  - `exc8`/`exc9` 的同一句变为 **`最后前台包名：未知`**。该串来自 `_waitForTreeText`（`phone_agent_exception_test.dart:901-916`）在超时后用 **最后一次** `_tryTree` 的结果报告，而 `_tryTree` 对“payload 非 `ok`”和“异常”都返回 `null`（`:766-780`），因此 `未知` 表示**该次读树整体失败**，而不是前台包名取不到的具体错误码——日志没有记录当时的 `error` 字段。**因此不能断言它一定是宿主时序**：它也可能是观察层持续返回 `system_window_denied`（或服务不可用）。同时也要注意反方向的证据：`exc9` 的通知栏用例打印了 `error=system_window_denied ... (com.android.systemui, hard_baseline)`，说明该轮读树路径本身是可用的。**结论：`未知` 的成因未定位，既未证明是产品缺陷，也未证明是宿主时序。**
  - `叠加层不污染产品截图` 的失败固定是像素断言 `518/409920`（`exc6` 与 `exc9` 均为此值）。
  - 0.13% 的判定：观察边界改的是**判定入口**（`requireObservable` 与截图前的前台检查），不参与 `_expectOverlayFree` 的像素比较，也没有改动遮挡遍历或叠加层的隐藏握手，因此**不认为由本步引入**。旁证是 M24 轮（未改 `OverlayVisuals`/`PhoneAgentOverlay`/`ScreenshotCapture`）记录的同一断言失败值**也是 `518/409920`**。**但该结论是判断（含历史旁证），不是本步的根因证据**，未进一步定位。
  - **归因更正（R2 F2）**：此前本节引用 logcat `Force stopping com.psyche.kelivo.phoneagent ... from pid 7541` 作为失败证据。**该串在 `wt-28/.build/*.log` 中零命中**，无法回溯，已删除该引用。第 1 轮“进程被杀”的说法**不再作为本轮证据**；`exc5` 的 `did not complete` 具体成因未留存证据。
  - 因此**旋转、home/recents、权限窗口、锁屏、服务禁用/重启用这几条用例在本次 M28 中没有取得通过结果**，只能写“未验证/未通过”，不得写成通过。
- **M28 第 2 步产品 debug APK（R1 返工后为当前产品）**：最终树 `V:/coding/kelivo-private/.tower/worktrees/wt-28/.build/worktrees/f26c1c7ed3238610`（`modsetHash` `f26c1c7ed32386105a763feeb3ea95accdd127b6041941b9f3d75f83abadafa9`，`plan`/`apply`/`verify` 通过），在全部设备测试与 R1 返工之后 `flutter clean` + `flutter pub get` + `flutter pub get --directory tool/l10n --enforce-lockfile` + 显式 `flutter build apk --debug`：**181,410,150 字节**，SHA-256 `a6c2e51b73435af1de4f74d5e95807a9688e95cb3d78be2f47521d715971b70f`；debug merged manifest 含 `SecureWindowFixtureActivity`（1 处）与 `PhoneAgentService`（1 处）。构建后未再运行 integration_test，未构建 release。该 APK **未被设备测试覆盖**（R1 只改了主线程预算判定与文档，未重跑设备），其字节数与 R1 前的 181,409,722 不同是预期的：`windowType()` 增加了主线程零预算分支。
- **R1 返工前的产品 debug APK（历史）**：树 `c3c760c0d4502878`（`modsetHash` `c3c760c0d45028785f3eb8a9792347cd01bf09be04124f6bb96a9d25a7ee7e93`）在全部设备测试后 `flutter clean` 构建：**181,409,722 字节**，SHA-256 `8cae3cd8ee92eedc1232fb6ffd41602209f6b6a9299707487f1e966991cd9c19`，manifest 含 `SecureWindowFixtureActivity`（1 处）。**可复现性**：该轮曾二次 `flutter clean` 重建并得到**完全相同**的字节数与哈希，可据此复核；期间出现过一次 181,409,334 / `9470004d…` 的中间产物（记录之后被其他流程写入），不作为产品 APK。该 APK 是**实际跑过设备测试的版本**（API35 官方 `+2`；MIUI 为“有通过迹象、无留存日志”，见下一条，**不要**当作已验证）。
- **M28 第 2 步物理 MIUI（`1960cd68`，Android 12 / API 31）——通过无留存日志（R2 F4 修正）**：对合成树 `c3c760c0d4502878` 的 debug APK 运行 `flutter test integration_test/phone_agent_test.dart -d 1960cd68`。
  - **唯一留存的日志 `miui_official.log`（23:35）结果是 `+0 -1`、EXIT=1**，失败在 `setUpAll`：`Phone Agent 服务未就绪（supported=true, enabled=false, connected=false, sdk=31）`。配套 `miui_official.log.miui_enable` 显示 `ENTRY_NOT_FOUND` → `BEFORE: null` → `AFTER: null`，即**授权启用本身失败**，一个用例都没有执行。此前把首轮失败写成“设备息屏后 `device_locked`”**与日志不符，已更正**（`device_locked` 发生在更早的一次尝试，不是这条留存日志）。
  - **之后有通过（`+2`）的设备侧操作，但没有留存日志**。旁证仅是设备侧痕迹：MIUI logcat 在 00:00–00:24 有测试包前台活动（晚于 23:35 的失败轮），且 `settings` 已恢复 `null`/`0`。**因此“MIUI 官方测试 `+2`、EXIT=0”目前无 artifact 支撑，只能写成“有通过迹象、无留存日志”**，不得作为已验证结论引用。
  - 该设备按既有例外用 `settings put secure` 预配置服务，**本轮真实原值为 `enabled_accessibility_services=null`、`accessibility_enabled=0`，结束时已恢复为该值**（`settings delete` + 置 0），并已 `svc power stayon false`。未在该设备运行异常套件。
- **M28 第 2 步自检**：Loader `dart format`（0 变更）、`dart analyze tool test` 无问题、`dart test` **165 通过**；插件 Kotlin `:kelivo_phone_agent:testDebugUnitTest --rerun-tasks` **140 通过、0 失败**（`PackagePolicyTest` 新增 2 条覆盖“窗口稍后才出现在列表中”与“`root.window` 为 null 时仍须精确匹配”）；合成树 `dart analyze --fatal-infos lib test integration_test tool` **无问题**；`plan`/`apply`/`verify` 通过。
- **`window_type_unknown` 的真实根因（M28 实测，API35，服务重连后首次截图）**：临时调试版本打印 `windowType attempt=0/1/2 rootWin=5902 nodeType=null entries=(5890, 3) resolved=UNKNOWN`（**交付代码不打印 `nodeType=`/`resolved=`**，只打印 `windowType exhausted attempts=N rootWin=... entries=...`，见 `PhoneAgentService.kt:605-612`；因此该串是历史调试输出，交付构建不可复现）。即 `root.window` 返回 **null**，同时 `windows` 只有另一个窗口 id（5890），而 `rootInActiveWindow` 已属于 5902；窗口列表约 3 秒后才包含目标窗口。因此“优先读 `root.window.type`”**不足以**修复冷启动，原 75ms 预算差约 40 倍。修正为 **2500ms 有界总预算、40ms 间隔**交替重试两条来源，并在 `onAccessibilityEvent` 记录 `TYPE_WINDOWS_CHANGED` 到达时间。**2500ms 仍短于实测 3 秒**，只是把失败窗口从 75ms 缩到 2.5s，不保证覆盖更长滞后。改后首次截图通过（对应 `final2_official.log` 的 `+2`）。该结果只覆盖这台模拟器的一条冷启动路径，**不承诺**覆盖其他 ROM；超预算仍返回 `window_type_unknown`。
- **重试预算只在 worker 线程生效（M28 R1 F5 修正）**：`windowType()` 会在**主线程**被一处路径调用——`ScreenshotCapture` 隐藏叠加层后的窗口重校验（`gate.hideForCapture` → `proceed` → `start()` → `currentWindow()` → `windowState()`）。该处若 sleep 2.5 秒会阻塞 UI，并超出文档承诺的约 250ms 有界隐藏握手。因此实现按调用线程决定预算：**主线程一律零预算**（只读一次 `root.window` 与一次 `windows` 快照，不 sleep），worker 线程才使用 2500ms 预算。零预算不会放宽任何判定——该处只做“窗口是否变了”的变更检测，`UNKNOWN` 本身就会让 `WindowState` 与观测不一致，从而返回 `stale_observation`，重试没有收益。主线程零预算路径不写诊断日志，避免每次截图刷噪声。R1 审查指出这是本步新增的最坏情况（可达性窄：需首个 `windowState()` 刚成功、随后列表退化或窗口在手势期间切换），**未见 ANR，属代码路径分析而非实测**；主线程阻塞是否仍会在极慢设备上造成可感 jank 仍未实测。
- **异常套件两处断言被设备证伪并已修正**：(1) `home`/`recents` 后前台实测是 `com.google.android.apps.nexuslauncher`（`TYPE_APPLICATION`），读树**成功**，旧写法“等观察拒绝”会白等 30 秒；(2) 通知栏 `mCurrentFocus` 是 `NotificationShade`，其包名 `com.android.systemui` 属硬基线，硬基线判定先于窗口类型，标识只会是 `hard_baseline`，不可能出现 `window_type_system`。`window_type_unknown` 已从可接受标识中移除，避免吞掉真实时序缺陷。
- API 35 模拟器（`emulator-5554`，Android 15；`flutter test --no-uninstall integration_test/phone_agent_test.dart -d emulator-5554`，退出码 0，2 个用例通过）：
  1. 真实截图（图片与屏幕尺寸有效）→ 读树 → 节点点击（回调计数 1）→ 坐标滑动（原生接受并完成手势）→ 节点滚动（`scrollController.offset > 0`，列表真实滚动）→ 聚焦输入框 → 同一观测句柄 `set_text` 成功并写入文本 → 二次读树返回节点。
  2. Mods 页真实服务状态与 Phone Agent 三态选择通过。
- API 29 真机（`357784090209204`，Android 10；`flutter test --no-uninstall integration_test/phone_agent_test.dart -d 357784090209204`，退出码 0，2 个用例通过）：
  1. 截图按预期返回 `unsupported_os` → 读树 → 节点点击（回调计数 1）→ 节点滚动（`scrollController.offset > 0`，列表真实滚动）→ 聚焦输入框 → 同一观测句柄 `set_text` 成功并写入文本 → 二次读树返回节点。
  2. Mods 页真实服务状态与 Phone Agent 三态选择通过。

集成测试的坐标手势验证边界：

- `flutter_test` 的 `LiveTestWidgetsFlutterBinding` 默认 `shouldPropagateDevicePointerEvents = false`，设备指针事件只进入诊断 dispatcher，不转发给 widget 树；绑定还会断言测试不得修改该开关。
- 因此集成测试只能验证坐标手势被原生接受并完成（`onGestureCompleted`），不能断言应用侧的滚动效果；API 35 用例在坐标滑动之后再用无障碍节点滚动验证列表真的滚动。该限制只影响测试可观测性，不改变产品行为。
- 安装测试包和部分收尾的 force-stop 可能清除系统无障碍授权；测试会打印 `PHONE_AGENT_WAITING_FOR_SERVICE` 并等待约 300 秒，需要在窗口内通过系统界面重新启用 Kelivo Phone Agent，并每轮检查真实绑定状态。

#### 9.3.1 异常路径集成测试（debug-only 夹具）

本轮新增 `integration_test/phone_agent_exception_test.dart`，使用真实 `PhoneAgentService` / `PhoneAgentTools` 和真实窗口，不使用 mock 替代原生截图、读树或输入。夹具 `com.kelivo.phoneagent.SecureWindowFixtureActivity` 只存在于插件 `android/src/debug`，不修改上游 `MainActivity`、`KelivoApplication`、`PhoneControlService`，不新增上游补丁或 `touches`，release 不编译、不合并。

夹具行为：

- `--ez secure true|false`：添加/清除 `WindowManager.LayoutParams.FLAG_SECURE`；同一 `singleTop` Activity 通过 `onNewIntent` 切换。
- `--ez requestPermission true`：只调用 `requestPermissions` 请求上游已声明的 `POST_NOTIFICATIONS`（API 33+），用于拉起系统权限窗口；不授予、不使用其他敏感能力。夹具只在 `checkSelfPermission` 不是 `GRANTED` 时请求，权限已允许时不会产生弹窗。
- 根布局为纯色 `#00C8FF` 和文本 `PHONE_AGENT_SECURE_FIXTURE`，作为前台就绪信号和截图像素校验。
- 权限窗口前置：设备必须处于唤醒且解锁状态。API35 实测设备息屏（`mWakefulness=Asleep`）时执行同一 `am start` 不会让权限弹窗获得前台焦点（`mCurrentFocus=null`），唤醒后弹窗立即出现；因此宿主在标记后先唤醒设备再启动夹具，并用 `dumpsys` 独立确认真实 `GrantPermissionsActivity`。测试在首次等待 45 秒未进入无窗口状态后打印 `PHONE_AGENT_PERMISSION_WINDOW_RETRY` 再给一次唤醒重试机会；重试后仍未进入则失败，不因 `root=null` skip，也不把任意 `no_window` 当作通过。宿主确认是测试前提，不是产品检测能力。

UID 与 secure 检测：API35 实测同 UID 和不同 UID 的 secure 夹具都返回成功黑图；UID 不是原因，整屏 `takeScreenshot` 路径本身没有 secure 检查。不同 UID 夹具 `com.kelivo.phoneagent.securefixture` 保留用于排除 UID 因素和验证文档化行为；该 APK 只是测试 harness，不属于 Mod 交付。插件内夹具继续用于权限窗口和同包切窗（旧坐标 `stale_observation`）。

宿主命令（测试只打印标记并轮询，不自己启动 Activity、不写系统授权）：

```bash
adb -s emulator-5554 shell am start -n com.kelivo.phoneagent.securefixture/com.kelivo.phoneagent.securefixture.SecureFixtureActivity --ez secure true
adb -s emulator-5554 shell am start -n com.kelivo.phoneagent.securefixture/com.kelivo.phoneagent.securefixture.SecureFixtureActivity --ez secure false
adb -s emulator-5554 shell am start -n com.psyche.kelivo.phoneagent/com.kelivo.phoneagent.SecureWindowFixtureActivity --ez secure false
adb -s emulator-5554 shell am start -n com.psyche.kelivo.phoneagent/com.kelivo.phoneagent.SecureWindowFixtureActivity --ez requestPermission true
adb -s emulator-5554 shell input keyevent 4
adb -s emulator-5554 shell am start -n com.psyche.kelivo.phoneagent/com.psyche.kelivo.MainActivity
```

不同 UID 夹具是宿主侧临时项目，不提交到仓库；用合成树的 Gradle wrapper 构建：

```bash
cd <合成树>/android
./gradlew -p <临时项目目录> assembleDebug
adb -s emulator-5554 install -r <临时项目目录>/app/build/outputs/apk/debug/app-debug.apk
```

测试场景与精确断言：

- FLAG_SECURE：普通截图成功 → 不同 UID 夹具前台（树出现 `PHONE_AGENT_SECURE_FIXTURE`，包名为 `com.kelivo.phoneagent.securefixture`）→ 截图分两种断言：若平台明确报错，断言 `tool_error` / `screenshot_blocked`、`metadata == null`、content 不含 `![](`、`data:image` 或 `image` 键；若成功，断言 `ok:true`、`package_name` 为夹具、图片可解码，并记录平台行为：平均亮度 <10 时打印 `PHONE_AGENT_SECURE_PLATFORM_BLACK_IMAGE`，否则打印 `PHONE_AGENT_SECURE_PLATFORM_CONTENT_IMAGE`；不要求全黑，不把黑图当安全检测。secure 期间断言读树仍成功（API35 实测可读，但不是绝对保证）→ 切到同包夹具使基线截图失效，坐标 `tap` 返回 `stale_observation` → 不同 UID 夹具清除 flag 并等待 ≥1.2 秒后截图成功，解码 PNG 断言非全黑且夹具纯色占比 >5% → 返回应用后新树/新截图成功。

历史严格预期与本轮修订：早期任务要求 secure 截图必须返回 `screenshot_blocked`；API35 实测同 UID/不同 UID 都曾返回成功黑图（后续也观察到成功内容图），严格测试失败。经用户同意，契约改为文档化行为：平台明确报错时无图片；成功黑图或内容图记录为平台行为，不当作安全检测。该历史失败保留，不删除。

本轮实际结果（设备运行树 `2c1513ecef3f2293`；当前最终源码/构建树 `5b1cde0304e687b9` 仅文档哈希变化，关键代码/测试一致，新树未重跑设备）：

- API35 完整异常套件（实际运行树 `2c1513ecef3f2293`）：**`+5 ~1`，`All tests passed!`，EXIT=0**。通过：FLAG_SECURE 截图行为与恢复、旋转、home/recents、锁屏、服务禁用/重启；跳过：权限窗口（明确未验证）。
- API35 `FLAG_SECURE 截图行为与恢复`：实际截图 `ok:true`、`image 713x1600`、`package_name=com.kelivo.phoneagent.securefixture`；本轮记录 `PHONE_AGENT_SECURE_PLATFORM_BLACK_IMAGE`（平均 RGB 约 2,0,2）。上一轮同一夹具曾返回成功内容图（平均亮度约 191），因此契约只承诺“可能黑化”，不保证黑图；测试记录黑图/内容图两种平台行为。secure 期间树可读；同包切窗后旧坐标返回 `stale_observation`；清除 flag 后恢复非黑夹具截图（纯色占比 >5%）。
- API35 锁屏 `device_locked`：同一锁屏窗口分别实际调用 `tree`、`screenshot`、`input`，三者均返回 `device_locked`；截图错误无图片 metadata；`status().ready` 仍为 true。解锁后旧句柄 `stale_handle`，新树/新截图成功。
- API35 服务禁用/中断/重启：先建立 Settings 观测并启动 1000 个只读 `readTree(offset:1)` 请求，保留同一批 Future，再由宿主在 pending 时关闭服务；日志 `PHONE_AGENT_SERVICE_PENDING_BATCH: size=1000 elapsed=3252ms codes=interrupted,ok`，无 `timeout`。重新启用后旧句柄 `stale_handle`，新树/新截图成功。
- 历史失败（保留）：`41e33b6f115e54bc` 完整套件为 `+2 ~1 -3`、EXIT=1；secure（切同包夹具只等文本未等包名，旧坐标得到 `package_not_allowed`）、锁屏（host driver 漏处理 lock 标记）、服务（未在窗口内完成系统 UI 禁用）失败。修正测试辅助与 host 协调后，实际运行树 `2c1513ecef3f2293` 完整套件 `+5 ~1`、EXIT=0；当前 `5b1cde...` 仅文档哈希变化，未重跑设备。
- API35 官方 `phone_agent_test.dart`：**2 项通过，EXIT=0**。
- API29 官方 `phone_agent_test.dart`：**2 项通过，EXIT=0**；截图返回 `unsupported_os`，树/节点输入回归通过。
- 当时产品 debug APK（历史，M10 最终源码/构建树 `5b1cde0304e687b9` 显式 `flutter build apk --debug`；设备套件实际运行于 `2c1513...`，未在新树重跑）：**181,373,590 字节**，SHA-256 `581d56fc03fe716c768f2554015115bffd8e2b0d610c71e74f5d3b21524703a3`；debug merged manifest 含 `SecureWindowFixtureActivity`，release merged manifest 不含该夹具（不宣称签名 release）。该 APK 已被 9.3.2 的 M16 产品 APK 取代，不能再当作当前产品。
- 权限窗口：实际运行树 `2c1513ecef3f2293` 完整套件明确跳过（90 秒内未检测到 permissioncontroller 前台），**未验证**，不写成通过。
- 未验证：签名 release、原生超时、权限窗口、`stale_handle` 根因；物理真机部分见 9.3.2。
- 旋转：旧树句柄 `tap` 返回 `stale_handle`；旧截图坐标 `tap` 返回 `stale_observation`；旋转后新树/新截图成功；转回后恢复。
- home/recents：执行后读树取实际前台包名；`com.android.systemui` 断言 `system_window_denied`，其他非白名单包断言 `package_not_allowed`，空包名或未知包名直接失败。`back` 同样被拒，证明 home/recents 后需要宿主恢复。
- 权限窗口：宿主先确保设备唤醒，启动夹具请求权限，并用 `dumpsys` 独立确认真实 `GrantPermissionsActivity`；随后测试直接调用节点 `tap`、截图和 `back`，三者都断言精确 `no_window` 与条件式人工提示，且 `back` 后读树仍为 `no_window`（证明没有执行系统导航）。首次等待 45 秒未进入无窗口状态时打印 `PHONE_AGENT_PERMISSION_WINDOW_RETRY`，宿主唤醒并重新启动夹具后再等 60 秒；重试后仍未进入则失败，不因 `root=null` skip，也不把任意 `no_window` 当作通过。宿主取消弹窗后确认 `POST_NOTIFICATIONS` 仍为 `granted=false`。
- 锁屏：宿主息屏再亮屏停在锁屏后，读树/截图/输入返回 `device_locked`，`status().ready` 仍为 true；解锁后旧句柄 `stale_handle`，新树/新截图成功。
- 服务禁用/中断：测试先建立 Settings 观测并启动一批有界只读 `readTree(offset:1)` 请求，保留同一批 Future；宿主在 pending 时通过系统 UI 关闭服务；等待原 Future 在 35 秒内完成，至少一个返回 `interrupted` 或 `service_unavailable`，不得返回 `timeout`；`status().enabled == false` 且 `ready == false`；重新启用后旧句柄 `stale_handle`，新树/新截图成功。

边界：

- 夹具启动、secure 切换、权限弹窗、锁屏和服务开关由宿主/CU 在打印标记后操作；测试自动断言结果，但不把宿主操作当成产品能力。
- 默认禁止用 `settings put secure enabled_accessibility_services` 写授权；服务开关只走系统界面。唯一例外是用户明确授权的物理 MIUI 测试设备 `1960cd68` 上仅对 Phone Agent 的测试预配置，见 9.3.2；结束必须恢复**当轮真实原值**（M16 历史轮为空串+0，M17 轮为 Phone Agent 组件 + `accessibility_enabled=1`），不能按历史记录强制关闭；产品不自动授权。
- 原生截图 10 秒、手势 duration+3 秒、插件 15/20 秒和 worker 15 秒排队超时无法在设备上确定性触发，只由 Dart 注入超时测试覆盖工具层映射，不写成真机证据。
- API 29 不适用 secure 截图和坐标场景，只跑原官方测试验证树/节点回归和 `unsupported_os`。

仍待验证：

- 物理真机的截图、坐标手势和 VLM 固定任务已由 9.3.2/9.4.2 覆盖（MIUI API31 + `mistral/deepseek-v4-1-flash-1017`）；`llama-cpp/llama-cpp` 的物理完整坐标 swipe 仍未完成。
- 其他 Android 版本/物理设备上的 `FLAG_SECURE` 行为（API35 模拟器与 MIUI API31 真机均已观察成功黑图，不代表所有设备）。
- 物理真机的锁屏、home/recents、服务禁用/重启和权限窗口仍未运行；API35 模拟器已验证锁屏、home/recents、服务禁用/重启三项。权限窗口在 API35 已真实触发并按 M22 保守收尾验收：读树/截图/输入均返回 `no_window` 与条件式人工提示，未执行手势/系统导航，通知权限未授予；`system_window_denied` 在无可访问 root 的权限弹窗场景不产生（M20/M21 已证伪识别机制），不再记为待实现（见 9.3.6）。原生截图/手势/通道/worker 排队超时仍未设备验证。
- 带合法签名配置的 release 构建。

因此不宣称 Phone Agent 第二阶段全部完成；未验证项不能用编译或单元测试代替真机结论。

#### 9.3.2 物理 MIUI API31 验收（真机）

设备与环境：

- Redmi K30 5G（`1960cd68`，picasso），Android 12 / API 31，1080x2400，density 440，MIUI V13.0.3.0.SGICNXM；用户提供该测试设备并授权安装应用、操作界面，设备无重要数据。
- 测试包 `com.psyche.kelivo.phoneagent` 安装成功，未覆盖上游 Kelivo；服务 enabled && connected；Mods 页三态选择与真实工具暴露一致。
- 授权例外：用户明确授权仅在该设备上用 `settings put secure` 预配置 Phone Agent 服务；M16 历史轮原始 `enabled_accessibility_services` 为空串、`accessibility_enabled=0`，M17 轮原始值为 Phone Agent 组件 + `accessibility_enabled=1`，每轮按当轮真实原值恢复。该例外只适用于本设备与 Phone Agent，不构成产品自动授权能力，其他设备默认仍禁止自动写系统授权。

实际结果：

- M16 历史结果：官方 `phone_agent_test.dart`（`flutter test --no-uninstall integration_test/phone_agent_test.dart -d 1960cd68`）在同一最终树、同一命令下两次结果不同：第一次 `+1 -1`、EXIT=1，聚焦后 `set_text` 返回 `stale_handle`（`The target node changed`，属 `ObservationRegistry` 的 refresh/isVisibleToUser/isEnabled 前置分支，不是旧聚焦指纹路径）；第二次 `+2`、EXIT=0。属间歇性，根因未确认、未修复，不能写成稳定通过。
- M17 诊断轮（当前，同一官方测试）：设备测试树为 `V:/coding/kelivo-private/.tower/worktrees/wt-17/.build/worktrees/8fe847cedc2ea513`；最终树 `.../1c1920e0e2b8bc7c` 仅 `plugin/README.md` 文档副本不同，代码/测试一致。本轮开始时设备授权原值为 `enabled_accessibility_services=com.psyche.kelivo.phoneagent/com.kelivo.phoneagent.PhoneAgentService`、`accessibility_enabled=1`，与上一条 M16 历史空串+0不同；每轮 `adb devices -l` 重查，安装测试包会清除组件，宿主 watcher 只恢复 Phone Agent 组件，轮末恢复当轮真实原值。4 轮结果均为 `+2`、`All tests passed!`、EXIT=0，未出现 `stale_handle`，也未触发新诊断标识。第 1 轮设备自动息屏导致约 3 分钟停顿，唤醒后继续并通过，不是测试失败。4 轮未复现历史间歇性失败，不能据此宣称根因修复；`refresh_failed`/`not_visible`/`not_enabled` 目前只有 JVM 单元测试覆盖，设备未触发。
- 物理 `FLAG_SECURE`：secure 夹具截图返回成功黑图（平台行为），不是 `screenshot_blocked`；清除 flag 后恢复真实截图。
- 旋转：旧句柄 `stale_handle`，旧截图坐标 `stale_observation`；旋转后新树/新截图成功。
- 坐标 UI 效果：`llama-cpp/llama-cpp` 轮用归一化坐标 tap 真实打开抽屉、Settings 和 Search，`set_text Phone` 成功；后续 swipe 因网关故障未完成，该模型的完整坐标 swipe 仍属未验证。
- 未在物理设备运行：锁屏、home/recents、服务禁用/重启、权限窗口；这些场景不能从 API35 模拟器结果推断为物理设备通过。
- 产品 APK 覆盖提醒：`flutter test` 会把树内 `build/app/outputs/flutter-apk/app-debug.apk` 覆盖为测试入口构建；产品 APK 必须在干净合成树显式 `flutter build apk --debug` 重新生成并重新计算大小与 SHA-256，不能沿用旧哈希，也不能把测试入口构建当产品。旧 M10 树 `5b1cde0304e687b9` 的 APK 就曾被覆盖为测试入口构建（249,642,846 字节，SHA-256 前缀 `1138b4d2`），之后才显式重建；因此旧 181,373,590 字节 / `581d56...` 与 249,642,846 字节 / `1138b4d2...` 都不能当作当前产品 APK。

#### 9.3.2.1 M24 聚焦后 `stale_handle` 复现与路径重解析修复

本轮目标：处理"聚焦后同一句柄 `set_text` 返回 `stale_handle`"这一长期未结问题，先复现、再解释机制、最后做最小修复。

自然循环复现（均未触发）：

- API35 `emulator-5554`：同一句柄 tap → 0/50/100/200/400ms → `set_text` 共 150 次；改为真实焦点切换（先点空白目标再点输入框）后 48 次；改为单次读树 + 6 档延迟后 60 次；再改为按官方序列（读树 → 点目标 → 滚动 → 读树 → 点输入框 → 400ms → `set_text`）循环 20 次。全部未出现 `stale_handle`，唯一稳定失败是 `delay=0` 时的 `action_unavailable`（tap 后语义树尚未更新出 `SET_TEXT` 动作）。
- 物理 MIUI `1960cd68`：同款焦点切换夹具 60 次、官方序列循环 20 次，均未出现 `stale_handle`；官方 `phone_agent_test.dart` 连续 4 轮 `+2`、`All tests passed!`、EXIT=0。
- 字段探针（聚焦后延迟读树并逐字段比较输入框）：API35 15 次、MIUI 15 次全部为 `same`，说明仅靠聚焦本身不重建语义节点。

受控机制验证（设备实测，非代码推断）：

- 夹具在第 2 步后强制重建输入框所在子树（`KeyedSubtree` 更换 key）。重建后旧句柄 `set_text` 连续 3/3 次返回 `stale_handle`，消息精确为 `The target node changed (refresh_failed)`；未重建的对照组 3/3 成功。
- 重建后重新读树可见同一逻辑节点仍在（同 `class`、`hint`、`bounds`，`editable=true`），说明是平台重建了 `AccessibilityNodeInfo` 对象、逻辑节点未变，`refresh()` 因此失败。
- A/B 对照（同一夹具 8 轮，含 `refocus=false`/`true` 各半）。**证据重心在启用组**：修复后 8/8 `set_text` 成功，且控件内容确实变为 `fix 0`…`fix 7`（与轮次严格对应）。旧句柄此时 `refresh()` 已为 false，文本能落进重建后的控件，唯一可能的路径就是按子索引路径重新取到了节点——这是「重解析真的被执行」的直接证据。禁用组（把 `resolveByPath` 短路为 `return null`）8/8 返回 `stale_handle(refresh_failed)`，但短路后必然抛错，属构造性结果，只作对照，不构成独立证据。
- A/B 所用树 `V:/coding/kelivo-private/.tower/worktrees/wt-24/.build/worktrees/dfcef53cfd77ea78` 是**手工注入** `dependencies/kelivo_phone_agent/` 的临时树，未走 `apply`，其 `.state.json` 里的 `modsetHash` 仍是 M23 基线 `dfcef53cfd77ea78…`，**不代表该树实际内容，不可作为可复现基线**；该树的 `verify` 结论也不可信。已验证其插件源码与 R1 前的 `fa251a4` 逐字节一致（34 个文件全等），故 A/B 测的是当时的交付代码；该树与最终 tip `6222d78` 有 4 个文件不同（`NodeTreeReader.kt`、`ObservationRegistry.kt`、`PhoneNode.kt`、`ObservationRegistryTest.kt`），差异仅限 F1/F2 的行为保持型重构，因此不能再写成「与最终分支一致」。本轮唯一可复现基线是 R1 返工后的 `29861376ffaa5e41`。残留临时夹具与脚本已删除。

修复边界（写清楚，不宣称彻底解决）：

- 只对"平台重建节点对象、逻辑节点未变且重建后的节点仍 advertise 所需动作"的情况生效。若重建后的语义节点不再 advertise `SET_TEXT`，执行层仍按当前节点返回 `action_unavailable`；本轮没有放宽 `performNodeAction` 的动作校验。
- 第一版验证时重建销毁了 `TextField` 并丢失焦点，重解析拿到的节点不 advertise `SET_TEXT`，结果从 `stale_handle` 变成 `action_unavailable`。因此改用显式 `FocusNode` 重建，模拟真实场景中"节点对象被重建但逻辑节点与焦点仍在"。这不是产品缺陷被掩盖，而是动作可用性校验按设计生效。
- 不按文本/描述/相似度查找节点，不放宽任何指纹字段，不改变可见性、可用性、TTL 和窗口/包名/尺寸/旋转校验，不自动重试动作。

自动检查（R1 返工后合成树 `29861376ffaa5e41`，`modsetHash` `29861376ffaa5e4123b8884b5a67cd07d102666acfdee83d0e1ed6f815afce2a`）：Loader format/analyze 通过、Loader 165、插件 Kotlin 106（新增 7 + R1 返工 2）、Flutter Mod/Phone Agent 126、上游 seam 56、`dart analyze --fatal-infos lib test integration_test tool` 无问题、`verify` 通过。

设备结果：

- API35 `emulator-5554` 官方 `phone_agent_test.dart` `+2`、`All tests passed!`、EXIT=0。
- API35 完整异常套件本轮未取得绿色整轮：最好一轮 `+6 -2`，最后一轮 `+5 -3`。逐条判定：叠加层截图污染（`518/409920` 像素差异，M24 未改 `OverlayVisuals`/`PhoneAgentOverlay`/`ScreenshotCapture`，属 M23 既有宿主/时序敏感断言）、权限窗口用例（宿主 `am start` 重建了 Activity 导致 harness 丢失）、服务禁用用例（宿主确认弹窗在 1000 个 pending 请求排空后才到达）。这三条均为宿主脚本时序，不是本轮产品断言失败；已通过的用例为 FLAG_SECURE、旋转、home/recents、锁屏、叠加层可见时宿主触摸。按收口规则不再为宿主脚本继续迭代，不写成全绿。
- 物理 MIUI `1960cd68` 官方 `phone_agent_test.dart` `+2`、`All tests passed!`、EXIT=0（R1 前树 `47675033b3d132e0`；R1 的 F1/F2 未重跑设备，见下）。
- API 29 真机 `357784090209204` 本轮离线，按用户决定记录为**未运行**，不以任何替代手段伪造。

产品 APK（R1 返工后最终树 `29861376ffaa5e41`，`flutter clean` 后的干净树 `flutter pub get` + `flutter pub get --directory tool/l10n --enforce-lockfile` + 显式 `flutter build apk --debug`，构建后未再运行 integration_test）：**181,403,918 字节**，SHA-256 `5a54cb3a459a9c8758033fce6eba14bdf098b0b6c02477be45e83e723bd41b43`；debug merged manifest 含 `SecureWindowFixtureActivity`（1 处）与 `PhoneAgentService`（1 处）。本轮未构建 release，不宣称签名 release。此前 R1 前树 `47675033b3d132e0` 的 APK 为 181,404,642 字节 / `677c26d9…`，已被 R1 的 F1/F2 重构取代，只作历史。

设备结果与代码版本的对应关系（如实标注）：API35 与 MIUI 的官方测试结果、异常套件结果均取自 **R1 前的树 `47675033b3d132e0`**。该树之后被就地改动过（插件源码在 02:34 同步为 R1 之后的 tip 版本，但其 `MOD_BUILD.json` 仍记录 R1 前哈希、`app-debug.apk` 仍是 01:07 的 R1 前代码 181,404,642 字节 / `677c26d9…`），因此该树的「源码 / 构建记录 / APK」三者不一致，`verify` 与 `MOD_BUILD.json` 不可信，**不能作为 R1 前代码的可复现样本**；它只用来标明上述设备结果对应的代码版本（同一份 R1 前逻辑）。R1 的 F1（`TreeObservation` 去 data class、句柄槽位封装）与 F2（去掉 `!==` 回收守卫、写清 `child()` 契约）是行为保持型重构，按审查结论不涉及运行时语义，因此未重跑设备；这两项只由插件 Kotlin 106 项单测（新增 2 项路径回收断言）覆盖。

未验证：`stale_handle` 真实自然触发仍属窄窗口间歇性，本轮只以受控夹具复现机制，不能写成"已彻底修复历史间歇性失败"；"重建后语义节点不接受所需动作"的情况仍返回 `action_unavailable`，属已知边界；API 29 未运行；签名 release 未验证；完整异常套件本轮未取得绿色整轮（原因见上）；物理设备未运行锁屏、home/recents、服务中断和权限弹窗。

#### 9.3.3 M19 权限窗口真实验证（API35 模拟器）

本轮只改中文文档、debug 异常测试和交接记录，不改产品代码、schema、白名单或上游。目标是查明上一轮 API35 异常套件中权限弹窗 90 秒未出现的原因，并真实验证权限窗口输入拒绝。

环境与前置：

- `emulator-5554`（Android 15 / API 35，AVD `Kelivo_Phone_Agent_API_35`，未 wipe data）；设备运行树 `V:/coding/kelivo-private/.tower/worktrees/wt-19/.build/worktrees/093f372e4d8513e5`（`modsetHash` `093f372e4d8513e556b4b2292045bb180a3b756a125543bbb34dbf2eceead3be`），最终树 `V:/coding/kelivo-private/.tower/worktrees/wt-19/.build/worktrees/75429900bf8fc452`（`modsetHash` `75429900bf8fc4526fb7005729da565f210eab3d9de922d94039e6399f808d11`）与运行树仅 `plugin/README.md` 文档副本和未验证标记/skip 文案不同，断言未变，`verify` 通过；未为文案重跑设备。
- 测试包 `com.psyche.kelivo.phoneagent`（versionCode 85，targetSdk 36），manifest 声明 `POST_NOTIFICATIONS`；实测 `granted=false`，flags 只有 `USER_SENSITIVE_WHEN_GRANTED|USER_SENSITIVE_WHEN_DENIED`，没有 `USER_SET`，说明从未被回答。
- 服务由系统无障碍界面启用（`Use Kelivo Phone Agent` → `Allow`），未使用 `settings put secure`；未授予任何权限、未撤销权限、未清应用数据。
- 未修改系统分辨率；宿主命令全部带 `-s emulator-5554`，每次先执行 `adb devices -l`。

诊断证据（上一轮 90 秒未出现的原因）：

- 设备唤醒时执行 `adb shell am start -n com.psyche.kelivo.phoneagent/com.kelivo.phoneagent.SecureWindowFixtureActivity --ez requestPermission true`，`dumpsys window` 显示 `mCurrentFocus=com.google.android.permissioncontroller/com.android.permissioncontroller.permission.ui.GrantPermissionsActivity`；uiautomator 树节点 package 均为 `com.google.android.permissioncontroller`，文案 "Allow Kelivo Agent to send you notifications?"；`dumpsys accessibility` 的 Active Window Id 指向该窗口（active=true、focused=true）。
- 设备息屏（`mWakefulness=Asleep`）时执行同一命令，`mCurrentFocus=null`，弹窗不会成为前台焦点；唤醒后弹窗立即出现。这是上一轮 90 秒内检测不到 permissioncontroller 的可复现条件，不是夹具或断言缺陷。
- 夹具只在 `checkSelfPermission` 不是 `GRANTED` 时调用 `requestPermissions`，因此“权限已允许导致无弹窗”不成立；`cmd package resolve-activity` 能解析 `SecureWindowFixtureActivity`。
- 取消弹窗只用 `adb shell input keyevent 4`，权限保持 `granted=false`。

实测结果（真实权限弹窗）：

- 弹窗确实出现，但 `PhoneAgentService` 的 `rootInActiveWindow` 在弹窗期间为 null：读树返回 `type=tool_error`、`error=no_window`（测试打印 `PHONE_AGENT_PERMISSION_TREE: package=null type=tool_error error=no_window`，45 秒 + 60 秒重试窗口内稳定复现）。这是本套件的直接设备证据。
- 输入 `no_window` 是代码路径推导，不是本轮直接设备调用证据：`PhoneAgentService.currentWindow()` 在 `rootInActiveWindow` 为 null 时返回 null，输入在包名策略和执行器之前以 `no_window` 拒绝；本套件在 `permissionTree == null` 时只读树和打印诊断，未执行 tap/back。输入仍被拒绝，没有执行任何手势，权限未授予。
- 文档契约仍要求 `system_window_denied`；本轮不把 `no_window` 改写成通过条件，该场景在套件中明确记录为未验证。根因和最小修复另开任务（M20：输入路径系统窗口识别），不在本轮修改生产代码。

测试改动（不放宽断言）：

- `PHONE_AGENT_PERMISSION_WINDOW` 标记要求宿主先唤醒设备；首次等待 45 秒超时（未检测到预期系统窗口）时打印 `PHONE_AGENT_PERMISSION_WINDOW_RETRY`（唤醒 + 重新启动夹具），再等 60 秒；重试后仍未检测到可访问的权限窗口才记录未验证。
- 未验证标记与 skip 原因写“服务未检测到可访问的权限窗口（读树返回 `no_window`）”，不断言系统弹窗不存在，避免与 `dumpsys` 已确认真实弹窗的事实矛盾。
- 未验证前打印 `PHONE_AGENT_PERMISSION_TREE`，只含 `package`/`type`/`error` 固定字段，不打印节点文本。
- 截图辅助在 `rate_limited` 时等待 1.2 秒重试一次，解决相邻用例间截图限频竞态；所有内容断言不变。

本轮完整异常套件（`093f372e4d8513e5` 树）：

- `flutter test integration_test/phone_agent_exception_test.dart -d emulator-5554`：**`+5 ~1`，`All tests passed!`，EXIT=0**。
- 通过：FLAG_SECURE 截图行为与恢复（secure 截图成功黑图，平台行为；同包切窗旧坐标 `stale_observation`；恢复后非黑夹具截图）、旋转（旧句柄 `stale_handle`、旧坐标 `stale_observation`）、home/recents（`system_window_denied`/`package_not_allowed`）、锁屏（tree/screenshot/input 均 `device_locked`）、服务禁用/中断/重启（`PHONE_AGENT_SERVICE_PENDING_BATCH: size=1000 elapsed=1112ms codes=interrupted,ok`）。
- 跳过：权限窗口（真实弹窗出现，读树实测 `no_window`；输入按 `currentWindow` guard 推导为 `no_window`，本套件未执行 tap/back；`system_window_denied` 未产生，按契约记录为未验证）。
- 历史失败保留：首次运行（`81a2da5132d0e975` 树）旋转用例因 `rate_limited` 失败、服务禁用用例因宿主未在约 2 秒批次内确认关闭而失败；修正测试等待与宿主反应后本轮 `+5 ~1`。两次失败都不是产品缺陷，也不是断言放宽。
- API 29 真机 `357784090209204` 本轮不在线，未运行；不写成通过。
- 自动检查：Loader `dart format --output=none --set-exit-if-changed tool test`、`dart analyze tool test`、`dart test`（165 项）通过；`plan`/`apply`/`verify` 通过；合成树 `dart analyze --fatal-infos lib test integration_test tool` 在 `flutter pub get --directory tool/l10n --enforce-lockfile` 后 `No issues found!`；插件 Dart 17 项、Phone Agent Flutter 108 项通过。本轮未改原生代码，因此未重建产品 APK；`flutter test` 已把运行树内 `app-debug.apk` 覆盖为测试入口构建，不能当作产品 APK，M17 产品 APK（181,373,530 字节 / `dc32c4a3...`）仍是当前产品；debug 夹具 manifest 本轮未改动，M17 的 debug/release 隔离结论不变。

M22 已按用户同意取消上述 skip：宿主 `dumpsys` 确认真实 `GrantPermissionsActivity` 后，测试直接调用 tap/back/截图并断言 `no_window` + 条件式提示，见 9.3.6。本节保留 M19 历史证据，不代表当前测试行为。

#### 9.3.4 M20 权限窗口输入路径诊断（API35 模拟器，abandoned）

本轮目标是验证 `AccessibilityService.windows` 能否在 `rootInActiveWindow=null` 时提供可确认的活动/聚焦系统窗口，并据此做最小修复让输入返回 `system_window_denied`。结论是**不可实现**：活动/聚焦的权限弹窗窗口没有可访问 root，无法取得包名；唯一有 root 的窗口是后台 systemui 窗口，不能当作前台。按 mission 停止条件停止，未提交生产代码或测试改动；该 branch 已 abandoned，未合并。

环境与前置：

- `emulator-5554`（Android 15 / API 35）；测试包 `com.psyche.kelivo.phoneagent` 重新安装；`POST_NOTIFICATIONS` 初始 `granted=false`，flags 只有 `USER_SENSITIVE_WHEN_GRANTED|USER_SENSITIVE_WHEN_DENIED`，没有 `USER_SET`。
- 服务通过系统无障碍界面启用（`Use Kelivo Phone Agent` → `Allow`），未使用 `settings put secure`，未授予或撤销任何权限。
- 诊断构建：合成树 `V:/coding/kelivo-private/.tower/worktrees/wt-20/.build/worktrees/b46ea4019595752d`（`modsetHash` `b46ea4019595752da9894fa35ebc3d7014decd71f470b4e8f0ae865936ff0219`），在 `PhoneAgentService.currentWindow()` 的 root 为 null 分支临时打印 `windows` 快照（只含 id/type/active/focused/hasRoot/packageName）；该日志和临时测试改动已全部移除，不在交付中。

真实弹窗与实测：

- 宿主执行 `adb -s emulator-5554 shell am start -n com.psyche.kelivo.phoneagent/com.kelivo.phoneagent.SecureWindowFixtureActivity --ez requestPermission true` 后，`dumpsys window` 的 `mCurrentFocus` 为 `com.google.android.permissioncontroller/com.android.permissioncontroller.permission.ui.GrantPermissionsActivity`，弹窗标题为 `Allow Kelivo Agent to send you notifications?`。
- 弹窗期间服务侧 `windows` 实测（固定字段）：`windows=2`；`w0 id=557 type=3 active=false focused=false hasRoot=true pkg=com.android.systemui`；`w1 id=563 type=1 active=true focused=true hasRoot=false pkg=null`。
- 读树实测 `no_window`（`PHONE_AGENT_PERMISSION_TREE: package=null type=tool_error error=no_window`）。
- 输入实测：测试轮询真实 `phone_agent_input tap`（使用弹窗前读到的节点句柄）45 秒 + 唤醒重试 60 秒，每次均返回 `no_window`（`PHONE_AGENT_PERMISSION_INPUT: type=tool_error error=no_window`），没有任何手势执行；用 `adb shell input keyevent 4` 取消弹窗后 `POST_NOTIFICATIONS` 仍 `granted=false` 且无 `USER_SET`。

为什么不能实现：

- mission 允许的最小修复要求「可确认的活动/聚焦系统窗口」；确认包名必须通过窗口 root（`AccessibilityWindowInfo` 没有包名字段）。本设备活动/聚焦窗口的 root 为 null，无法确认。
- 唯一有 root 的 `com.android.systemui` 窗口 `active=false focused=false`，把它当作前台就是 mission 明确禁止的「后台系统窗口误作前台」。
- 不使用 `dumpsys`/`uiautomator` 作为产品实现，不扫描任意节点推断前台，不按窗口标题猜包名。

交付与边界：未提交生产代码、Kotlin 测试或异常测试改动；M19 的异常套件当时仍把权限窗口记录为未验证（skip）。M22 已按用户同意改为保守收尾，见 9.3.6。

#### 9.3.5 M21 权限弹窗事件来源评估（API35 模拟器，abandoned）

本轮目标是评估 `TYPE_WINDOW_STATE_CHANGED` 事件来源包名能否与活动/聚焦窗口 id 可靠关联，从而在 `rootInActiveWindow=null` 时返回 `system_window_denied` 并提示人工处理。结论是**不可用**：真实权限弹窗期间服务没有收到任何 `permissioncontroller` 的窗口状态事件，无法取得来源包名。按 mission 停止条件停止，未提交生产代码或测试改动；该 branch 已 abandoned，未合并。

环境与前置：

- `emulator-5554`（Android 15 / API 35）；测试包 `com.psyche.kelivo.phoneagent`；`POST_NOTIFICATIONS` 实测 `granted=false`，flags 只有 `USER_SENSITIVE_WHEN_GRANTED|USER_SENSITIVE_WHEN_DENIED`，没有 `USER_SET`。
- 服务通过系统无障碍界面启用，未使用 `settings put secure`；未授予、撤销或清除任何权限。
- 诊断构建：合成树 `V:/coding/kelivo-private/.tower/worktrees/wt-21/.build/worktrees/34fe11ec8baa6bc6`，在 `PhoneAgentService.onAccessibilityEvent` 临时打印 `eventType/packageName/className/windowId/eventTime`，在 `currentWindow()` 的 root 为 null 分支临时打印 `windows` 快照；临时日志和临时测试已从交付移除，不在提交中。
- 真实弹窗由宿主执行 `adb -s emulator-5554 shell am start -n com.psyche.kelivo.phoneagent/com.kelivo.phoneagent.SecureWindowFixtureActivity --ez requestPermission true` 拉起；`dumpsys window` 的 `mCurrentFocus` 为 `com.google.android.permissioncontroller/com.android.permissioncontroller.permission.ui.GrantPermissionsActivity`。

实测事件（服务已连接并持续收到事件）：

- `EV type=32 pkg=com.psyche.kelivo.phoneagent wid=755`：应用窗口状态事件。
- `EV type=4194304 pkg=null wid=757`（多次）：`TYPE_WINDOWS_CHANGED`，没有来源包名；窗口 id 指向权限弹窗。
- `EV type=2048 pkg=com.android.systemui wid=715`：后台 systemui 窗口内容事件。
- **没有任何 `EV type=32 pkg=com.android.permissioncontroller` 或 `com.google.android.permissioncontroller`**；也没有 `pkg=null` 的 `type=32`。
- 弹窗期间 `windows` 快照：`id=715 type=3 active=false focused=false hasRoot=true pkg=com.android.systemui`；`id=757 type=1 active=true focused=true hasRoot=false pkg=null`。
- 读树和输入实测仍为 `no_window`；权限未授予。

为什么不可用：

- mission 要求「只处理明确 `permissioncontroller` 系统来源」；服务没有收到该来源的窗口状态事件，无法建立来源包名与活动/聚焦窗口 id 的匹配。
- 活动/聚焦的弹窗窗口没有可访问 root，`AccessibilityWindowInfo` 没有包名字段，不能用窗口 root 补全包名。
- 唯一有 root 的后台 systemui 窗口 `active=false focused=false`，不能当作前台；`TYPE_WINDOWS_CHANGED` 只有 `pkg=null`，不能作为来源包名。
- 不使用窗口标题、文本、任意窗口 root 或 `dumpsys`/`uiautomator` 猜测，不把 `no_window` 改写成通过条件。

交付与边界：未提交生产代码、Kotlin 测试或异常测试改动。M22 已按用户同意改为保守收尾，见 9.3.6。

#### 9.3.6 M22 权限弹窗保守收尾（API35 模拟器）

用户明确同意：“不可识别权限弹窗仍返回 `no_window`，消息条件式提示人工处理/取消并返回测试应用；不宣称识别具体权限弹窗，不要求 `system_window_denied` 出现在 root=null 场景。”本轮按此收尾，不追查新识别机制，不新增 overlay。

代码与契约：

- `PhoneAgentService` 三处无可访问窗口（读树、截图、输入）改用同一 helper，错误码保持 `no_window`；英文消息改为条件式提示：“No accessible window is available. If a system permission dialog is visible, ask the user to handle or cancel it, then return to the test app and retry.” 消息不声称识别具体权限弹窗，不添加事件跟踪、包名识别、原生截屏绕过或运行时回退。
- 可取得系统包名的系统窗口仍由 `PackagePolicy` 返回 `system_window_denied`；错误优先级、读树/截图密码遮挡、白名单和输入边界均不变。
- 异常测试删除 `root=null` 的 skip 分支：宿主在 `PHONE_AGENT_PERMISSION_WINDOW` 后唤醒、启动夹具并用 `dumpsys` 独立确认真实 `GrantPermissionsActivity`；测试轮询进入 `no_window` 后直接调用节点 `tap`、截图和 `back`，断言精确 `no_window` 与条件式提示；`back` 后读树仍为 `no_window`，证明没有执行系统导航；宿主取消弹窗后确认 `POST_NOTIFICATIONS` 仍 `granted=false`。首次 45 秒未进入时打印 `PHONE_AGENT_PERMISSION_WINDOW_RETRY` 再等 60 秒，仍未进入则失败，不把任意 `no_window` 当作通过。
- 宿主 `dumpsys` 确认是测试前提，不是产品检测能力；测试自身无法读取 `dumpsys`，文档和测试注释都明确这一点。

本轮结果（设备运行树 `V:/coding/kelivo-private/.tower/worktrees/wt-22/.build/worktrees/d94f4165af9277d5`，`modsetHash` `d94f4165af9277d5bbdc83c3c07bcc5bdce55cb4c241a284edfdcd5d5d0a2c9d`；R1 文档返工后最终源码树为 `V:/coding/kelivo-private/.tower/worktrees/wt-22/.build/worktrees/b9989da92f35bac8`，`modsetHash` `b9989da92f35bac8703cb5ed803499222886ec6bae15d5e8045a8e45b6689725`，与设备运行树仅 `plugin/README.md` 文档副本不同，代码/测试一致，未重跑设备）：

- API35 `emulator-5554` 官方 `phone_agent_test.dart`：**`+2`、`All tests passed!`、EXIT=0**（真实截图/读树/节点点击/坐标滑动/节点滚动/聚焦后 `set_text`/二次读树、Mods 页三态选择）。
- API35 完整异常套件 `phone_agent_exception_test.dart`：**`+6`、`All tests passed!`、EXIT=0**。权限场景：宿主 `dumpsys window` 实测 `mCurrentFocus=com.google.android.permissioncontroller/com.android.permissioncontroller.permission.ui.GrantPermissionsActivity`；测试打印 `PHONE_AGENT_PERMISSION_TREE: package=null type=tool_error error=no_window`；节点 tap、截图和 `back` 均断言 `no_window` + 条件式提示，`back` 后读树仍 `no_window`，未执行手势/系统导航；宿主取消弹窗后 `POST_NOTIFICATIONS` 仍 `granted=false`（无 `USER_SET`）。服务禁用/中断/重启：`PHONE_AGENT_SERVICE_PENDING_BATCH: size=1000 elapsed=670ms codes=interrupted,ok`，无 `timeout`。
- 自动检查：Loader `dart format`/`dart analyze` 通过、Loader 165 通过；合成树 `flutter pub get`、`flutter pub get --directory tool/l10n --enforce-lockfile` 通过，`dart analyze --fatal-infos lib test integration_test tool` 输出 `No issues found!`；根项目 seam 测试 56 通过；插件 Dart 17、插件 Kotlin 66 通过。
- 产品 debug APK：在最终树 `b9989da92f35bac8` 显式 `flutter build apk --debug` 生成（新建树，未在该树运行 integration_test），**181,370,434 字节**，SHA-256 `06b806e4ac80b998b2b3c114eacbd7971a34a5e16e8b1467b6450b5a2846a04a`；debug merged manifest 含 `SecureWindowFixtureActivity`（1 处），release merged manifest 不含该夹具（0 处，不宣称签名 release）。设备测试树 `d94f4165af9277d5` 的 clean APK 为 181,373,914 字节 / `5cc74cabf3fc02c9c0a7e79174ea5b9467523d25a72c760b65cb634daf69f0e3`，仅作设备证据；两树代码/测试一致，仅 `plugin/README.md` 文档副本不同。
- API29 真机 `357784090209204` 本轮不在线，未运行，不写成通过。

#### 9.3.7 M23 前台可视化叠加层（API35 模拟器 + 物理 MIUI API31）

代码与契约见 2.6。新增 `OverlayVisuals.kt`（纯 JVM：事件、几何、状态机、截图隐藏握手）和 `PhoneAgentOverlay.kt`（`TYPE_ACCESSIBILITY_OVERLAY` 窗口、无文本图形、主线程生命周期），接入 `PhoneAgentService`、`NodeActionExecutor` 和 `ScreenshotCapture`。首版不新增设置开关、`status` 字段、ARB 文案或插件通道方法。

JVM 测试（无 Robolectric、无新依赖）：

- 几何：偶数/奇数 bounds 中心、退化 bounds 不绘制、中心 clamp 到屏幕内、手势复用真实起点/终点与 `duration_ms`（50–2000ms 原样复用，尾段另算）。
- 状态机：`begin` 替换不堆叠、截图隐藏期间 `begin` 被抑制、`resume` 不恢复旧事件、`clear` 幂等、TTL 到期不可见。
- 时序：清理代次 bump 后旧事件不能绘制；手势 `isActive=false` 时不绘制；新事件使用新代次正常显示。动作开始时捕获代次并传给 `show` 的 `NodeActionExecutor` 接线由代码审查，未做 JVM 专项测试。
- 截图隐藏握手：无窗口零延迟、有窗口等两帧加 48ms settle 后才 `proceed`、隐藏失败不 `proceed` 且触发失败、250ms 超时失败、`resume` 前保存的迟到帧/settle/timeout 回调显式执行后不能 `proceed`/失败，也不能影响下一次 request、重复 `resume` 幂等且忽略迟到回调。
- 截图窗口重校验：纯函数 `OverlayVisuals.windowChanged` 覆盖 `windowId`、包名（含以密码应用包名模拟）、宽高、旋转变化和 null；`ScreenshotCapture` 在 gate 后和 `onSuccess` 回调里的 `stale_observation`/不发图分支是 Android 依赖代码，由代码审查和设备验证，未做 JVM 专项测试。
- 附着状态：移除失败进入未知状态，`hideResult` 为 `FAILED` 且不能继续添加窗口；成功移除后恢复 `NONE`；`addView` 失败视为未附着。
- 密码窗口过滤：只有 root 包名等于自身包才排除；root 包名未知、其他包名和非 overlay 窗口都继续参与遮挡。
- 动作拒绝不显示：`action_unavailable`、`password_node_denied`、`perform=false` 时可视化回调不被调用；接受时收到刷新后的 `bounds`；可视化回调抛异常不改变 `performNodeAction` 返回值（执行器路径由 `runCatching` 保护，未做设备级专项断言）。

设备矩阵（API35 模拟器 `emulator-5554`，物理 MIUI `1960cd68`）：

1. 观察动画：读树时出现无文本边缘脉冲，约 700ms 后消失；连续读树不堆叠。
2. 节点点击/长按/滚动：圆环出现在刷新后 bounds 中心；`set_text` 不显示文本。
3. 坐标手势：圆点按真实起点/终点和 `duration_ms` 移动；手势完成后自动隐藏。round-4 定向验证用 `phone_agent_input` 1500ms 滑动，宿主 `screenrecord` 30fps 帧检测到 `#008999` 圆点沿 x≈539 从 y≈1110 连续上移到 y≈462，约 42 帧/1.4s，末端环可见。
4. 触摸穿透：宿主在叠加层可见期间用 adb 注入独立真实触摸（`adb shell input swipe`，不是 `phone_agent_input`），确认通知栏或目标 UI 真实打开；JVM 只证 flag 位，宿主注入是设备证据。
5. 截图纯净性：debug 夹具 `SecureWindowFixtureActivity` 纯色 `#00C8FF`，在动作动画进行中立即截图，图片中心 60% 与基线截图逐像素一致，且与基线比较不新增叠加层强调色像素（状态栏隐私盾牌本身带强调色）；`adb screencap` 只用于观察叠加层本身，不替代产品截图链路。
6. 生命周期：服务停用后由宿主执行 `dumpsys window windows | grep -c PhoneAgentOverlay` 统计窗口数；round-4 API35 实测停用后 0、重新启用后 0（原始输出 `R5_OVERLAY_WINDOWS_AFTER_DISABLE: count=0`、`R5_OVERLAY_WINDOWS_AFTER_RESTART: count=0`）。旋转、锁屏、权限窗口的清理只有代码审查和测试行为断言，未做设备窗口计数；下一次动作正常；`device_locked`、`no_window` 等拒绝路径不产生动画。
7. MIUI：`addView` 兼容性、是否被 keyguard 遮挡、触摸穿透和截图无污染；保存并恢复当轮真实无障碍授权值，只恢复 Phone Agent 组件。
8. 上游胶囊开启：记录截图含胶囊、坐标手势被拦截的现象，不宣称兼容。

返工轮结果（2026-11-12，reviewer round 1 六项 findings）：

- 修复：
  1. 密码遮挡只排除能可靠确认属于本服务的 accessibility overlay（root 存在且 root 包名等于自身包）；root 包名未知或其他包名继续参与遮挡，回归测试固定该行为，不绕过 `FLAG_SECURE`。
  2. 事件在主线程绘制前校验清理代次和调用方 `isActive`（手势 finished、服务 epoch），覆盖 cancel/release/旋转/切窗先于 show。
  3. 新增 `OverlayAttachmentTracker`：移除失败或附着状态未知时 fail closed，结束回调按具体 View 清理，resume/到期/再次截图不会永久遗留窗口。
  4. 手势 travel 复用真实 50–2000ms duration，尾段另算。
  5. 触摸穿透改为宿主 adb 注入独立真实触摸（不是 `phone_agent_input`），测试只轮询前台包名。
  6. 迟到帧测试保存 resume 前回调并显式执行，覆盖迟到回调不能影响下一次 request。
- round 2 修复（reviewer-m23-overlay-r3）：
  7. 截图隐藏握手后、`takeScreenshot` 前重新读取当前窗口，比较 `windowId`/包名/宽高/旋转；变化或不可读返回 `stale_observation` 且不发图，避免同尺寸切应用时用旧密码 bounds。
  8. `OverlayAttachmentTracker` 格式修正，生产 `hideNow` 改用 `hideResult()`，fail-closed 路径不再只靠代码审查。
  9. 动作开始时捕获清理代次并传给 `show`，动作后 clear/切窗使 node/gesture/system 旧视觉失效。
  10. 补 `begin` 替换、`password_node_denied`、窗口变化（包名变化，含以密码应用包名模拟）和重复 resume JVM 测试；收窄矩阵中 `InputOutcome` 和 `ScreenshotCapture` 分支的表述；同步 plan/AGENTS 当前阶段与 round-2 实际失败测试名（旋转截图 timeout 与锁屏恢复）；round-1 的 `099843`/`e6de` 仅作历史。**round-2 当时**的基线为设备树 `f1b26a58`、最终树 `2445a838`、无产品 APK；round-4 当前基线见 plan:6（设备树 `9ebf2e99`、最终树 `dfcef53c`、产品 APK 181,403,054 / `501d4a00…`）。
- 自动检查（round 4 最终树 `V:/coding/kelivo-private/.tower/worktrees/wt-23/.build/worktrees/dfcef53cfd77ea78`，`modsetHash` `dfcef53cfd77ea78fe898710efa92991fa15a140b8d0424193279f7ad21aac77`；产品 APK 在最终树 `dfcef53c` 构建，`a460dcbc` 仅作设备测试构建树且其 APK 已被 integration_test 覆盖）：Loader `dart format`/`dart analyze` 通过、Loader 165、`verify` 通过；插件 Kotlin 97 项通过（新增重复 resume 测试）、`dart analyze --fatal-infos lib test integration_test tool` 无问题、Flutter Mod/Phone Agent 126 项通过；`flutter pub get` 与 `flutter pub get --directory tool/l10n --enforce-lockfile` 通过。设备运行树为 `9ebf2e991caa07ed`（`modsetHash` `9ebf2e991caa07ed3e8e5b4484649de84139e89a31ac8837f779ca34aa2d8c66`），与最终树仅 `plugin/README.md` 文档副本不同，代码/测试语义一致。
- 自动检查（round 2 最终树 `V:/coding/kelivo-private/.tower/worktrees/wt-23/.build/worktrees/2445a838f5b71e56`，`modsetHash` `2445a838f5b71e562fad471f0468abe62c467f08eef114e91f9a5d6cd502c82b`）：Loader `dart format`/`dart analyze` 通过、Loader 165、`verify` 通过；插件 Kotlin 96 项通过、`dart analyze --fatal-infos lib test integration_test tool` 无问题、Flutter Mod 126 项通过、上游 `PhoneControlServiceTest` 通过。设备运行树为 `f1b26a580b737e14`（`modsetHash` `f1b26a580b737e14117a22bd11b8304e3fe725c477dc3f90ad881b663432b824`），与最终树仅 `plugin/README.md` 文档副本不同，代码/测试语义一致。
- 物理 MIUI API31（`1960cd68`，返工树）：官方 `phone_agent_test.dart` **`+2`、EXIT=0**；「叠加层不污染产品截图」**`+1`、EXIT=0**；「叠加层可见时真实触摸不被拦截」**`+1`、EXIT=0**（`PHONE_AGENT_OVERLAY_HOST_TOUCH_RESULT: package=com.android.systemui`，宿主 `adb shell input swipe` 独立注入）。服务停用后 `dumpsys window windows` 中 `PhoneAgentOverlay` 窗口数为 0；已恢复 `enabled_accessibility_services=null`、`accessibility_enabled=0`、`stay_on_while_plugged_in=0`。
- round 2/3 历史（不代表 round-4 现状）：API35 模拟器（旧 AVD）：返工后多次整轮运行的真实退出码均为 1，未得到绿色整轮，不能写成通过：
  - 一次 `+6 -2`、EXIT=1：FLAG_SECURE、截图无污染、宿主真实触摸、旋转、home/recents、权限窗口通过；锁屏与服务禁用失败，期间模拟器 system_server 重启，`dumpsys` 出现 `Can't find service`。
  - 一次 `+7 -1`、EXIT=1：唯一失败为「服务禁用中断与重新启用恢复」（宿主打开无障碍设置页/关闭确认时序）。
  - 一次有界整轮在 `setUpAll` 失败、EXIT=1：模拟器持续 ANR，`dumpsys activity lastanr` 为 `Input dispatching timed out (Application does not have a focused window)`；ANR 发生在任何工具调用之前，应用进程存活、无障碍连接为 DEAD，属宿主/模拟器窗口焦点与输入分发问题，不是 overlay 主线程死锁。
- round 3 历史（不代表 round-4 现状）：API35 独立测试 AVD（`Kelivo_M23_API_35`，`.build/avd`，使用已有 android-35 google_apis_playstore x86_64 镜像，不 wipe 旧 AVD）：官方 `phone_agent_test.dart` **`+2`、EXIT=0**；完整异常套件最好 **`+7 -1`、EXIT=1**，唯一失败为「服务禁用中断与重新启用恢复」的宿主打开无障碍设置页/关闭确认时序；另一次 `+6 -2`（FLAG_SECURE/截图无污染在同包夹具切换步骤超时）。旧 AVD 另出现 `com.android.systemui` 的 `Input dispatching timed out ([Gesture Monitor] edge-swipe (server) is not responding)`，属系统 UI 手势监视器/宿主输入注入问题，无产品栈。旧 AVD 诊断保存在 `.build/diagnostics/` 并已正常关闭，未删除旧文件。round-4 同一 AVD 为 `+8`、EXIT=0（见下）。
- round 2 树 `f1b26a580b737e14` 的 API35 完整异常套件：**`+6 -2`、EXIT=1**。失败为「旋转后旧句柄与旧截图失效」（转回竖屏截图 10 秒 timeout，该用例单独重跑 `+1`、EXIT=0）和「锁屏 device_locked 与解锁恢复」（`_ensureAppForeground` 等待点击目标超时，宿主恢复时序，单独重跑 `+1`、EXIT=0）；「服务禁用中断与重新启用恢复」在该轮通过，且单独重跑 `+1`、EXIT=0（`PHONE_AGENT_SERVICE_PENDING_BATCH: size=1000 elapsed=1139ms codes=interrupted,ok`）。整轮未绿，不写成通过；round-2 当时未生成产品 APK（round-4 产品 APK 已生成，见 plan:16/929）。
- round 4 设备运行树 `9ebf2e991caa07ed` 的 API35 完整异常套件：**`+8`、`All tests passed!`、EXIT=0**。通过「FLAG_SECURE 截图行为与恢复」「叠加层不污染产品截图」「叠加层可见时真实触摸不被拦截」「旋转后旧句柄与旧截图失效」「home 与 recents 后输入被包名策略拒绝」「权限窗口输入被拒绝」（`PHONE_AGENT_PERMISSION_TREE: package=null type=tool_error error=no_window`）「锁屏 device_locked 与解锁恢复」「服务禁用中断与重新启用恢复」（`PHONE_AGENT_SERVICE_PENDING_BATCH: size=1000 elapsed=1667ms codes=interrupted,ok`）。这是返工后首次整轮绿色，不把分散通过拼成整轮通过。
- round 4 同一树官方 `phone_agent_test.dart`：**`+2`、`All tests passed!`、EXIT=0**。
- round 4 API35 叠加层清理证据（宿主，服务禁用用例在构建树 `a460dcbc` 单独重跑，代码/测试与设备树 `9ebf2e99` 一致，仅 README 副本不同）：`--plain-name "服务禁用中断与重新启用恢复"` **`+1`、All tests passed!、EXIT=0**；watcher 在关闭服务后执行 `dumpsys window windows | grep -c PhoneAgentOverlay`，原始输出 `R5_OVERLAY_WINDOWS_AFTER_DISABLE: count=0`，重新启用后 `R5_OVERLAY_WINDOWS_AFTER_RESTART: count=0`。旋转、锁屏、权限窗口没有设备窗口计数，只有代码审查和测试行为断言。
- round 4 API35 宿主 `screenrecord` 像素证据（构建树 `a460dcbc` 官方测试 `--no-uninstall`，代码/测试与设备树一致；视频 173s）：观察脉冲在约 121.5–121.9s 的 4 帧中可见，强调色 `#008999` 像素簇 bbox 约 34×34（`(522,462)-(556,576)`），位于顶部中央；节点点击圆环在约 125s 的帧中可见（文本框上方浅蓝圆环，强调色边缘像素 bbox `(496,372)-(502,400)`）。
- round 4 坐标滑动定向像素验证（构建树 `af52c6f7`，当时的最终树；现最终树为 `dfcef53c`，仅 README 副本不同。临时把官方测试 swipe `duration_ms` 改为 1500ms 仅用于本次运行，未提交；产品代码/测试源未改）：宿主 `screenrecord` 20s、30fps 提帧，检测到 `#008999` 圆点沿 x≈539 从 bbox `(522,1110)-(556,1146)` 连续上移到 `(522,462)-(556,496)`，约 42 帧/1.4s，末端环 bbox `(518,460)-(560,508)`；轨迹与 `phone_agent_input` 的 1500ms 坐标滑动一致，坐标滑动轨迹可见。此前 300ms 官方测试帧未检测到，属短动画采样/替换时序限制，不是产品未绘制。
- 宿主稳定性重试说明：`_screenshot` 对 `rate_limited`/`timeout` 最多重试 2 次，旋转用例的绿色不证明单次截图总能在 10 秒内完成；产品超时语义未改变。
- round 4 物理 MIUI API31（`1960cd68`）：官方 `phone_agent_test.dart` **`+2`、EXIT=0**；「叠加层不污染产品截图」**`+1`、EXIT=0**。测试期间设备曾自动息屏导致停顿，唤醒并 `svc power stayon true` 后继续通过；结束恢复 `enabled_accessibility_services=null`、`accessibility_enabled=0`、`stay_on_while_plugged_in=0`。
- round 4 API35 宿主侧一次性清理（审计记录）：授权阶段 watcher 固定坐标误触 TalkBack 授权弹窗，TalkBack 被短暂启用；宿主用 `settings put secure enabled_accessibility_services` 清空以移除误启用的 TalkBack，随后仍通过系统 UI 为 Kelivo Phone Agent 打开开关并点 Allow。该命令只清理宿主误操作，不是 Phone Agent 授权路径、不是产品能力、不是授权绕过，也不扩展到其他设备；Phone Agent 授权仍只走系统 UI。
- 产品 debug APK（最终树 `dfcef53cfd77ea78`，全部设备测试后 `flutter clean` + 显式 `flutter build apk --debug`，构建后未再运行 integration_test）：181,403,054 字节，SHA-256 `501d4a0087294258baa882e9a32856208805fcba88228ec34e15016ae89689fb`；debug merged manifest 含 `com.kelivo.phoneagent.SecureWindowFixtureActivity`（1 处），release merged manifest 不含该夹具（0 处）且含 `PhoneAgentService`（1 处，release 变体隔离检查，不等于签名 release 验证）。历史 181,402,630 / `a72cac9b…` 已被 `a460dcbc` 上 17:29/17:32 的 integration_test 覆盖为 251,120,349 / `e3d9d22b…` 测试入口构建，不再作为产品。
- 未验证：API29、签名 release、MIUI keyguard 遮挡、上游可触摸胶囊开启兼容；观察脉冲、节点点击圆环和坐标滑动轨迹均已获宿主 `screenrecord` 像素证据（滑动为 1500ms 定向验证），不把触发日志写成像素验证。

### 9.4 VLM 图片链路与固定任务验收（API 35 模拟器，magpie `llama-cpp/llama-cpp`）

以下为 API 35 模拟器上的历史 VLM 验收记录；M10 历史的 FLAG_SECURE/异常路径结果见 9.3.1，物理 MIUI API31 真机的 VLM 结果见 9.4.2。

该轮在 API 35 模拟器 `emulator-5554`（Android 15，内部屏幕 1080x2424）使用产品 debug APK（181369230 字节，SHA-256 `3ea30ee9b46342305cf11e0574b76def9a42f23abe62dd3536b664dc4ec5caeb`）和用户指定的 magpie 网关模型完成真实聊天、图片链路、Kelivo 应用内固定任务和跨新用户轮次历史图片回放。该轮未修改产品代码、`mod.json`、schema、节点指纹或插件行为，未重建 APK。

环境与适用范围：

- 模型：magpie 网关的 `llama-cpp/llama-cpp`（Text、Image → Text、Tools）；应用内 provider 地址 `http://10.0.2.2:3425/v1`，UI 勾选 Image 输入和 Tools。局域网访问由用户开启，密钥未修改、未读取、未记录。
- 设备：API 35 模拟器；Mods 页 Default Assistant 选择 Phone Agent，独立服务 enabled && connected，API 35 ready；未启用原生手机控制，未写系统无障碍授权。
- 适用范围：只验证该 magpie 模型与 API 35 模拟器，不承诺任意模型、任意网关或任意设备；物理真机的 VLM 结果见 9.4.2。

证据 A：工具暴露与最小截图 → 图片 → 模型链路

- REQ27（15:00:52）请求工具为 `read_file` + `phone_agent_screenshot` / `phone_agent_tree` / `phone_agent_input`；`read_file` 是上游工具，不属于 Mod schema。无原生 `phone_control`，无重复 `phone_agent_*`；三个 schema 均无 `snapshot_id`，均设置 `additionalProperties: false`。
- REQ28（15:00:58，Request Log ID28）携带 `phone_agent_screenshot` 工具结果：`image 713x1600`、`screen 1080x2424`、`package_name com.psyche.kelivo.phoneagent`；并包含一条合成 user 消息，`image_url` 为 `data:image/png;base64,<omitted 185028 chars>`，`detail` 为 `high`。
- 响应头 `x-magpie-model: llama-cpp/llama-cpp`、`x-magpie-provider: llama-cpp`；模型回答 `3:00 / New Chat / llama-cpp/llama-cpp (Magpie VLM)`，与截图中的时间、聊天标题和模型名称一致，属于对视觉细节的真实读取。

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
- 该轮未使用坐标动作完成任务；坐标手势的 UI 效果受 integration_test 绑定限制，物理真机的坐标 UI 效果由后续 9.3.2/9.4.2 补充。
- 该轮没有确认私有 Mod 硬缺陷；上述一次 `stale_handle` 证据有限，根因未查明。契约内的可恢复错误不写成产品假成功。
- 该轮仍明确未验证：物理真机的 VLM 固定任务与坐标手势 UI 效果、签名 release；真实 `FLAG_SECURE`、旋转、home/recents、锁屏、服务禁用/重启已由后续 M10 在 API35 模拟器补充（见 9.3.1），物理真机的 secure/旋转/VLM/坐标 UI 效果已由 9.3.2/9.4.2 补充，但不代表其他 Android 版本或设备。
- 该轮只验证 magpie `llama-cpp/llama-cpp` 与 API 35 模拟器，不承诺任意模型或设备。
- 文档只记录脱敏后的请求形态和尺寸/长度，不记录 provider 密钥、完整会话文本或截图字节。

#### 9.4.1 上一轮 LM Studio 补充环境（历史结果）

以下为上一轮使用 LM Studio `prism-ml/bonsai-27b`（identifier `bonsai-vlm`，Image + Tools，8192 上下文，provider `http://10.0.2.2:1234/v1`）的补充环境结果，不是本轮用户指定模型，不能取代 9.4 的结论：

- Request Log ID18 显示 `image/png · 47.7 KB · omitted`，Authorization 已脱敏；后续请求 `image_url` 为 `data:image/png;base64,<omitted 163212 chars>`，`detail` 为 `high`；模型读出 `10:47 / New Chat / bonsai-vlm (Local VLM)`。
- 固定任务完成 tree → tap `Search settings` → tree → `set_text Phone` → `n1 scroll down` 返回 `action_unavailable` → 截图确认；补充滚动先返回 `stale_handle`，重读树后 `n4` ScrollView `forward` 成功并显示 `Sponsor`。
- 同一生成轮的工具循环图片回放已验证：截图后的后续请求再次携带该图片。
- 4096 上下文下复杂任务出现截图/读树循环，8192 后完成；这是本地测试经验，不是产品运行时要求。

#### 9.4.2 物理 MIUI API31 VLM 验收（magpie `mistral/deepseek-v4-1-flash-1017`）

本轮在物理 MIUI API31 真机（见 9.3.2）上完成 VLM 图片链路、坐标 UI 效果和像素专属视觉确认：

- 模型选择：用户更正目标为 `mistral/deepseek-v4-1-flash-1017`（不是 0731）；magpie 路由的 16 个模型中没有 0731，Mistral 目录按 deepseek 筛选只有该 1017。Bonsai 备用环境已加载但未使用，不作为本轮证据。
- 能力标注与手动开启：magpie 侧该模型「支持图片输入」为关闭，Kelivo 目录标注文本→文本；在 Kelivo 手动勾选图片后，真实请求携带 `image_url`（`data:image/png;base64,<omitted>`，`detail=high`）且全部返回 200，响应头 `x-magpie-model` / `x-magpie-provider` 与请求一致。模型能力标注可能变化，每次都要实测图片与工具能力；手动勾选只是测试配置，不是模型能力保证。
- 工具暴露：`read_file` + 三个 `phone_agent_*`，无 `phone_control`、无重复、无 `snapshot_id`、`additionalProperties=false`。
- 截图尺寸：`image 720x1600`，`screen 1080x2400`，package `com.psyche.kelivo.phoneagent`。
- 坐标 swipe 的物理 UI 证据：实际工具序列进入 Kelivo 应用内 Settings 后，执行一次 `phone_agent_input` swipe `{x:0.5,y:0.8,end_x:0.5,end_y:0.3,duration_ms:400}`，前后 PNG 证实 Sponsor 从不可见变为可见。这是物理坐标 UI 效果，不是 integration_test 回调推断。
- 像素专属视觉证据：新建无历史会话，只允许一次 `phone_agent_screenshot`，禁止 tree/input，提示不透露颜色或文本；1017 回答 `bright cyan (light blue)` 和 `PHONE_AGENT_SECURE_FIXTURE`，与保存 PNG 的 rgb(0,200,255) 及完整文字一致。该轮请求只有一个截图 `tool_call`，`image_url` 为 `data:image/png;base64,<omitted 39204 chars>`，请求全文不含 `PHONE_AGENT`，构成后端视觉消费的直接支持证据，但不是对模型内部机制的绝对证明。
- 边界：第一轮过渡帧出现黑色区域和文本裁切，后续截图应等界面稳定；`llama-cpp/llama-cpp` 的完整坐标 swipe 未验证；网关 `api_error` / 空响应属外部故障，不写成产品缺陷；文档不记录密钥、完整会话或图片字节。

### 9.5 M35 审计元数据自检（2026-11-16，仅单元与静态检查，**无设备证据**）

- 改动：新增 `mods/phone_agent/plugin/android/src/main/kotlin/com/kelivo/phoneagent/AuditLog.kt`（七字段记录、固定动作 token、从不抛错的身份解析、30 天/2000 条滚动、文件存储、安全记录入口）；`PhoneAgentService` 在 `execute` 的 `reply` 收口处记录一次并只在取到前台窗口处填包名；通道 `readTree` / `screenshot` / `input` 新增可选 `assistant_id` / `conversation_id`；插件 Dart 客户端、`PhoneAgentService`（overlay 适配层，新增 `PhoneAgentAuditedClient` 能力接口）、`PhoneAgentTools.handleCall` 与 `PhoneAgentMod` 逐层转发。
- 合成树（R1 返工后最终源码树，已 rebase 到含 M37 的 `f70ba89`）`V:/coding/kelivo-private/.tower/worktrees/wt-35/.build/worktrees/d939b2353a71439b`，`modsetHash` `d939b2353a71439b2365b54f692e5c7f134b1fdac5445a5b8542adbbc9a137e5`；`plan`/`apply`/`verify` 通过。rebase 到 M37 后 Loader 的 longpaths 修复生效，**建树不再需要 `GIT_CONFIG_*` 绕过**。R1 返工前的树 `0073b68d56863418`（`modsetHash` `0073b68d…`）只作历史。
- 结果：插件 Kotlin `:kelivo_phone_agent:testDebugUnitTest --rerun-tasks` **195 通过、0 失败**（`AuditLogTest` 15 + `AuditRecorderTest` 10）；插件 Dart `flutter test` **33 通过**（新增 3 项身份注入防护测试）；合成树 `dart analyze --fatal-infos lib test integration_test tool` **No issues found**；合成树 Flutter `test/features/phone_agent` + `test/features/mods` + `test/features/settings/pages/mods_settings_entry_test.dart` **126 通过**；Loader `dart format` 0 变更、`dart analyze tool test` 无问题、`dart test` **173 通过**（M37 合并后从 165 增加到 173）。
- 首次运行的问题（如实记录，已修复）：`AuditLogTest` 的字段集合反射断言最初把 Kotlin data class 的 `componentN` 等生成成员算进字段集合，1 项失败；改为按静态/非合成过滤后通过。另一处非本分支问题的说明：只跑 `flutter pub get` 而不跑 `flutter pub get --directory tool/l10n --enforce-lockfile` 时，合成树 `dart analyze` 会在 `tool/l10n/validate.dart` 报 15 项 `undefined_identifier`（缺 l10n 子包依赖），这是既有的环境顺序要求，补齐后用 `No issues found!`。
- **R1 返工（reviewer `p2-5items` / fix-then-merge，reviewedCommit `3dc0f33`）**逐项：
  1. **身份字段可被模型注入（p2-1，最重要）**：`input()` 原先先展开模型参数再叠加 `auditArguments`，而后者只在非空时写键，宿主取不到身份时模型自带的 `assistant_id` / `conversation_id` 会存活到原生侧被写成审计事实。修法是在展开**之前**剔除这两个键（与 `snapshot_id` 同处防护），键名收敛为 `assistantIdKey` / `conversationIdKey` 静态常量。新增 3 项 Dart 测试：宿主无身份时模型值被剔除、宿主值覆盖模型值、模型伪造空白键也不出现。
  2. **`interrupted` 与服务未连接的文档对齐（p2-2）**：按实际行为改写 7.5.5 与插件 README，明确这两类调用**不产生记录**（`reply` 的 else 分支不记录；`dispatch`/`execute` 的提前返回在 `AuditContext` 创建之前），删掉原来自相矛盾的半句；同时说明白名单三方法也不审计。**不改运行行为。**
  3. **加载裁剪（p2-3）**：`ensureLoaded()` 原先只解码不裁剪，测试靠加载后再 `record` 才通过。现改为在解码末尾按**文件里最新记录的时间戳**调一次 `prune`（不用当前时钟，避免应用长期未运行后整份历史在下次启动被一次性判为过旧）；测试改为只加载不追加，并新增 30 天边界用例（基准取最新记录）。
  4. **文档同步（p2-4）**：`mods/phone_agent/README.md` 四处「审计未实现」改为 M35 已实现口径（状态分层的「已有/没有」、元数据条目、已知限制两处）；plan 7.5 小节标题、7.6 开头的待处理列表、P6 标题同步；plan:1048 与 AGENTS.md:10 的 M33 历史块保留原文并各加一句「审计已由 M35 补齐」。
  5. **首次 mkdir 移进 worker（p2-5）**：`recordAudit` 原先无条件执行 `auditLog(this)`，而 `Context.getNoBackupFilesDir()` 在目录不存在时会创建目录，主线程因此仍有一次 `mkdirs`。现把 `auditLog(this)` 移进 `Runnable` 内部，主线程只做投递。
- **未做**：未运行 integration_test、未构建 APK、未接设备；真实设备上的文件写入、进程重启后的追加与 2000 条滚动、多签名包前缀取值均未实测。审计没有读取通道，因此也没有任何用户可见视图。

## 10. Phone Agent 完成定义与已知限制

### 10.1 完成定义

只有满足以下条件，才能宣称 Phone Agent 第二阶段完成：

- Mod Loader 第一阶段已验收，且本 Mod 能确定性合成。
- 独立 `phone_agent` localToolId、Mods 三态选择、移动/桌面入口和服务状态页已实现。
- 服务状态面板区分 `supported`（仅 API 30+ 截图能力）与 ready（`enabled && connected`）；API 29 可 ready 并使用树/节点输入，截图返回 `unsupported_os`，页面显示截图限制。
- 正常 UI 不会同时启用原生手机控制和 Phone Agent；已有仅启用 `phone_control` 的助手保持原生。
- `PhoneAgentMod` 激活时过滤原生 `phone_control` 和重复 `phone_agent_*`，执行前重查 `phone_agent`，撤销后返回 `phone_agent_disabled`。
- 两个 `AccessibilityService` 共存，Mod 不自动授权、不自动切换系统无障碍开关。
- 产品文案进入 ARB，英文描述完整，所有目标语言同步；本机免费 llama-cpp 翻译 23 键，`translate.py check` 四目标语言 0 pending，`l10n-generated.patch` 已生成。
- Kelivo 适配层、插件 Dart 和 Android 相关检查通过。
- debug APK 构建成功，Manifest 合并正确。
- 真机基础输入闭环通过；真机官方测试退出码 0。
- VLM 图片链路、Kelivo 应用内固定任务和跨新用户轮次历史图片回放已在 API 35 模拟器用 magpie `llama-cpp/llama-cpp` 通过；物理 MIUI API31 真机由 `llama-cpp/llama-cpp` 通过归一化坐标 tap（打开抽屉/Settings/Search），由 magpie `mistral/deepseek-v4-1-flash-1017` 通过真实图片请求、归一化坐标 swipe 的物理 UI 效果和像素专属视觉确认；`llama-cpp/llama-cpp` 的完整坐标 swipe 仍未验证；不承诺任意模型或设备。
- 上一轮 VLM 文档轮只改中文文档，未重跑测试；该标签仅适用于该历史 VLM 文档轮，不代表当前 M17。M17 已重跑 Loader 165、插件 Kotlin 66、插件 Dart 17、根项目 `dart analyze --fatal-infos` 和 Flutter 182；历史 Phone Agent 105、Mods 16、settings 入口 2、上游 `tool_result_content` 14 通过 + 1 Windows 条件跳过、上游 PhoneControl 49 结果继续有效。
- Loader verify 通过；最终 APK 已生成。
- 前台可视化叠加层（M23）已实现：独立 `TYPE_ACCESSIBILITY_OVERLAY`、无文本图形、无设置开关；API35 模拟器和物理 MIUI API31 均验证官方测试、截图无污染和触摸穿透，未验证项见 10.2 和 9.3.7。
- 中文维护文档与真实行为一致。
- **应用批准契约（7.5.4/7.5.9）第 2、3 步已由 M33 实现**：`QUERY_ALL_PACKAGES` 一次声明、`(包名, 签名 SHA-256 集合)` 双匹配的用户白名单（本地存储、幂等写入、撤销立即生效、写入前重解析签名）、构建期 deny 清单（初始为空）与构建配置预批准条目、观察与输入两条路径的白名单门控、`permission_required`（输入与观察都返回，观察侧只带应用身份）、原生批准/撤销/查询通道方法。**M34 已实现批准交互与首次隐私确认**：聊天卡片、通知栏 action、pending 请求状态机（TTL + 单终态 + 迟到回调丢弃）、结构化身份、Mods 页白名单管理（按来源助手分组、逐条撤销）、首次启用隐私确认（方案 B）、预批准成员禁止写入用户白名单。**审计元数据已由 M35 实现**（七字段落盘、30 天/2000 条滚动、不进入工具结果与模型、无读取通道，见 7.5.5）。**仍未实现**：按任务的控制权、结果未知语义的专门文案与错误码、多窗口首版策略（拒绝方式未定稿）。**门控、签名绑定、批准交互与审计都没有任何设备证据**，因此不计入已完成验收项。

最终验收已完成（就 M32 之前的契约与 M32 的设备证据而言）；M33 的门控与签名绑定、M34 的批准交互与隐私确认**都只有单元测试与静态检查，没有任何设备证据**，因此仍不宣称第二阶段全部完成，未验证项见 10.2。

**M34 的检查结果（2026-11-16 R1 返工后，仅单元与静态检查）**：Loader `dart format --output=none --set-exit-if-changed tool test` 0 变更、`dart analyze tool test` 无问题、`dart test` **173 通过**；合成树 `dart analyze --fatal-infos lib test integration_test tool` **No issues found**；手机 Agent + Mods + 设置入口 Flutter **152 通过**；上游 seam（`tool_handler_service_test`、`tool_handler_workspace_gating_test`、`request_consistency_test`）**56 通过**；插件 Dart **33 通过**；插件 Kotlin `:kelivo_phone_agent:testDebugUnitTest --rerun-tasks` **223 通过、0 失败**（含 M35 的审计测试）；ARB 四目标语言 `translate.py check` **0 pending**；`modsetHash` `cde912d77ca6c81dd977d180ee0c54da8248c3c0fc5ccc9b8c54466d67c855d2`（合成树 `.build/worktrees/cde912d77ca6c81d`）的 `plan`/`apply`/`verify` 通过。本轮 R1 返工修了三项 P1（卡片渲染位置、通知权限可达性、双向撤下与清理接线）与九项 P2，新增卡片/隐私/失败态 widget 测试。**未运行 integration_test、未构建 APK、未接设备。**

### 10.2 已知限制

- 独立服务参考上游实现，需要 vendored 哈希和人工审查来避免安全修复分叉。
- Mods 页的选择是工具配置，不是无障碍授权；服务状态可能滞后于系统设置。
- 两个无障碍服务可以同时存在于系统中；正常 UI 只限制助手工具选择，不限制系统级服务开关。
- 已有仅启用 `phone_control` 的助手不会自动迁移，用户需要在 Mods 页手动选择 Phone Agent。
- 后台悬浮胶囊不在首版处理。
- 可视化叠加层是独立 `TYPE_ACCESSIBILITY_OVERLAY` 窗口，只借上游视觉风格；它不显示输入文本、密码、截图字节或节点文本，不代表业务成功、任务进度或用户审批，也不是安全护栏。
- 叠加层 `addView` 在部分厂商 ROM 上可能失败；失败时只禁用本会话可视化，工具行为不变。上游可触摸后台胶囊无法被 Mod 隐藏，开启胶囊时截图可能包含胶囊、坐标手势可能被拦截。
- 截图前隐藏叠加层会增加约两帧（约 33ms）等待和极少量 `screenshot_failed` 风险；隐藏失败时不发送图片，不静默跳过隐藏。
- 叠加层动画按工具事件触发，不表示模型思考过程；模型未调用工具时前台没有提示。
- Mod 工具不进入上游 schema override 和通用审批流程，自己的助手工具选择和限制必须自行执行。
- 截图密码遮挡、节点校验和窗口检查只能降低风险，不能提供绝对安全保证。
- 自动模式不承诺识别或阻止所有发消息、购买、删除等不可逆行为。
- 设置搜索不包含 Mods 页；用户需要从移动或桌面设置入口进入。
- 不进入上游工具目录或内置工具商店；Phone Agent 的助手级选择只在 Mods 页完成。
- `supported` 仅表示 API 30+ 截图能力；API 29 可以 ready 并使用树/节点输入，但截图返回 `unsupported_os`，页面显示截图限制。
- 非 Android 平台可以打开 Mods 页，但只显示平台不支持；不要用 `supported=false` 表示平台不可用。
- ARB 翻译质量依赖上游 l10n 工具和目标语言审查；新增键必须保持英文和中文源键集合一致。
- **批准交互没有设备证据（M34）**：通知权限（API 33+ `POST_NOTIFICATIONS`）与通知 action 的真实行为、系统在进程被杀后重放 action、通知与聊天卡片同时存在时的撤下时序、卡片在真实对话流中的布局、服务关闭时 Mods 页撤销链路、跨 UID 前台包签名解析，全部只经过单元测试与静态检查。没有通知权限时通知发不出去，判定不受影响，但这一点未在设备上验证。
- **「允许并继续」不重放动作**：它只发送一条要求模型重新观察的用户消息。会话已切走、消息发送被拒绝或没有注册回调时只保存授权并如实提示，**不会切换会话、不会伪造续跑**。它不能保证模型重新观察后一定能完成任务。
- **预批准成员不可写入用户白名单（M34）**：`approveApp` / `revokeApp` 对测试包与 debuggable 的 `securefixture` 返回 `pre_approved`，避免产生不可撤销的冗余条目。它们本来就直接放行，不需要批准。
- API 30+ 截图与坐标手势已在 API 35 模拟器验证；物理 MIUI API31 真机由 `llama-cpp/llama-cpp` 的归一化坐标 tap 与 `mistral/deepseek-v4-1-flash-1017` 的归一化坐标 swipe 证实坐标 UI 效果；integration_test 的坐标手势 UI 滚动效果仍受绑定限制（不转发设备指针事件），不能把回调成功当 UI 效果。
- VLM 图片链路、Kelivo 应用内固定任务和跨新用户轮次历史图片回放已在 API 35 模拟器用 magpie `llama-cpp/llama-cpp` 验证；物理 MIUI API31 真机用 magpie `mistral/deepseek-v4-1-flash-1017` 验证真实图片请求、坐标 swipe 的 UI 效果和像素专属视觉确认；`llama-cpp/llama-cpp` 的物理完整坐标 swipe 未验证；只验证这些模型与设备，不承诺任意模型或设备。
- 物理设备官方测试在 M16 出现一次间歇性 `set_text` `stale_handle`（`The target node changed`，`ObservationRegistry` 的 refresh/isVisibleToUser/isEnabled 前置分支），另一次全通过；M17 用同一官方测试连续 4 轮均为 `+2`、EXIT=0，未复现，也未触发 `refresh_failed`/`not_visible`/`not_enabled`。根因仍未确认、未修复，不能把 4 轮通过写成根因修复或稳定通过。
- magpie 的模型能力标注可能变化，图片与工具能力需每次实测；Kelivo 手动勾选图片只是测试配置，不构成模型能力保证。
- `settings put secure` 预配置仅限用户明确授权的该台 MIUI 测试设备，不是产品能力，也不代表其他设备可以自动写入无障碍授权；每轮开始必须记录并恢复当轮真实原值，不能按历史空串+0 强制关闭。M17 轮原值为 Phone Agent 组件 + `accessibility_enabled=1`。
- `flutter test` 会覆盖树内 `app-debug.apk` 为测试入口构建；产品 APK 必须显式 `flutter build apk --debug` 重新生成并重新计算大小/SHA-256。
- 一次 `stale_handle`（`No current tree observation`）在 tree 成功后紧接 tap 时出现，未复现、未找到 native 日志、根因未确认、未修复；重读树后恢复。可能来源只是假设，不写成事实。
- 整屏 `takeScreenshot` 不保证对 `FLAG_SECURE` 报错；secure 内容可能以黑色区域出现在成功截图中。不根据像素猜 secure，不承诺不发送黑图，正常黑色页面保留。
- 平台明确报错时不得把图片或图片 metadata 交给模型；成功黑图只作为普通截图，模型应优先读树、不凭黑图猜坐标。
- `FLAG_SECURE` 不阻止无障碍读树和输入；API35 夹具树可读，但不是绝对保证；密码字段、自定义 View、窗口变化仍会影响树；非白名单输入仍被拒绝。
- `system_window_denied` 同时约束输入与观察；`package_not_allowed` **M33 起也约束输入与观察**，只对构建期 deny 清单成员出现（清单初始为空），排在用户白名单之前。观察侧（读树与截图）允许 `TYPE_APPLICATION` 与 `TYPE_INPUT_METHOD`，其余类型返回 `system_window_denied` 并在消息里带 `window_type_*` 标识。**M33 起未批准应用的读树/截图返回 `permission_required` 且只带应用身份**（包名＋签名前 8 位），不建立观测、不占 `treeBudget`、不调用 `takeScreenshot`；签名解析失败时消息只写 `signing_unavailable`。无可访问 root 的权限弹窗读树/截图/输入均为 `no_window` 并带条件式人工提示。
- 应用白名单与批准：**第 2、3 步（签名绑定＋白名单门控）已由 M33 实现**（本地白名单、幂等写入、撤销即时、deny 清单、预批准条目）；**审计元数据已由 M35 实现**（七字段落盘、30 天/2000 条滚动、不进入工具结果与模型、无读取界面）；**批准交互（聊天卡片、通知栏 action、pending 状态机）与首次启用隐私确认已由 M34 实现**，Mods 页提供“已批准的应用”管理页与逐条撤销。**仍未实现**：任务控制（同时只一个任务控制手机）、结果未知语义的专门文案与错误码、多窗口首版策略。所有新语义**未经设备验证**；通知权限被拒时只有聊天卡片可用。
- `home`/`recents` 后前台离开本应用，**后续输入（包括 `back`）被拒绝**，模型无法自行恢复，需要用户或宿主切回测试应用。API35 实测 `home`/`recents` 后前台是启动器（`com.google.android.apps.nexuslauncher`，`TYPE_APPLICATION`）：M33 起它属**未批准第三方应用**，读树与输入都返回 `permission_required` 且只回身份（此前读树会成功）。**通知栏**这类窗口仍被观察层拒绝，且 systemui 属硬基线、硬基线先于窗口类型判定，标识是 `hard_baseline` 而非 `window_type_system`。
- 应用白名单与批准的**交互与设备验证未完成**：批准卡片/通知、首次启用隐私确认、任务控制与结果未知语义均未实现；审计已实现但没有设备证据，也没有读取界面；`QUERY_ALL_PACKAGES` 声明后交付代码能否在设备上解析任意前台包签名**未实测**（M29 只验证了探针 APK）。M33 契约全文见 `docs/phone-agent-plan.md` 7.5.4 与 7.5.9–7.5.14。
- `SecureWindowFixtureActivity` 只是 debug 测试夹具，不是产品能力；release 不包含该 Activity。
- API35 模拟器已验证旋转、home/recents、锁屏、服务禁用/重启；物理 MIUI API31 真机已验证旋转和物理 `FLAG_SECURE`，但锁屏、home/recents、服务禁用/重启未在物理设备运行，不能从模拟器结果推断；原生超时仍无法在设备上确定性触发。
- 未执行带合法签名配置的 release 构建。
- 因此不宣称 Phone Agent 第二阶段全部完成。
- Loader 更新演练通过不代表 Phone Agent 真机行为无需重新验证。
