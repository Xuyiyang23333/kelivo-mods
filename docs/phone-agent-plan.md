# Kelivo Phone Agent Mod 实施计划

## 0. 文档状态

- 当前阶段：第二阶段验收进行中（UI/选择契约改造已完成），Mod 版本 0.2.0。
- 本轮 M27（应用边界第 1 步：硬基线 + `WindowState.windowType`，2026-11-13）：只实现第 1 步，不做观察边界、用户白名单、批准交互和审计。新增 `AppBoundary.kt`（`WindowType`、`HARD_BASELINE_PACKAGES`、`KELIVO_PACKAGE`/`TEST_PACKAGE`、`RoleHolders`、纯函数 `PackagePolicy`）；`WindowState` 加 `windowType`，在 `windowState()` 内按 `windowId` 从 `windows` 匹配，解析失败 fail closed；`sameWindow()`、截图观测、`TreeObservation`、`CapturedScreenshot` 同步。`RoleManager.getRoleHolders` 为 @SystemApi 无法在公共 SDK 编译，改用 `TelecomManager.defaultDialerPackage` + `Telephony.Sms.getDefaultSmsPackage`（差异已写入 7.5.1 与 7.6）。最终合成树 `V:/coding/kelivo-private/.tower/worktrees/wt-27/.build/worktrees/1525e7263f6293d2`，`modsetHash` `1525e7263f6293d29f0775560d4d097e2cb4dd17b55dba31c92486687a555a8f`，`plan`/`apply`/`verify` 通过（前序重算树 `17007461ac82c427`、`eed71ae8a2984e02`、`3403a7239833ec63`、`7a2c1177fbc41351` 只作编译/测试迭代历史，不代表最终代码）；Loader format/analyze 通过、Loader 165、插件 Kotlin **120**（`--rerun-tasks` 强制重跑，0 失败 0 错误）、插件 Dart 17 全绿；**未接设备、未构建产品 APK、未跑 Flutter/上游回归**，`sameWindow()` 加 `windowType` 后是否产生新的 `stale_*` 仍属未验证假设。观察边界与其余各层**仍为零实现**。
- 上一轮 M26（应用边界与授权契约文档，2026-11-13）：只改中文文档，不改代码、测试、`mod.json`、白名单或上游。新增 7.5「应用边界与应用授权（设计提案）」与 7.6「实现前置风险与行为变更」，写入用户已定的三项决策（白名单全局共享、批准长期有效 + Mods 页显式撤销、审计落盘元数据滚动保留 30 天或 2000 条）、`permission_required` 契约和批准交互口径；同步更新 `AGENTS.md`、`mods/phone_agent/README.md` 与 `docs/next-session-handoff.md`。**该设计尚未实现**：当前代码仍是输入只允许 `com.psyche.kelivo.phoneagent`、读树与截图不检查包名或窗口类型。本轮未运行测试、未构建 APK、未接设备，未产生新 `modsetHash` 或 APK 记录。
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
- 首版只在显式测试包名中开放输入，不直接面向敏感应用。
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
- 运行时编辑测试包白名单或按应用配置策略（**首版**不做；运行时用户白名单与签名绑定的授权是 7.5 的设计提案，尚未实现）。
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
- `package_not_allowed`：目标包名不在测试白名单（**仅表示构建期硬禁止**，不表示“用户未批准”）；
- `permission_required`：目标应用尚未获得用户批准（**7.5 设计提案，尚未实现**）；立即返回、不排队、不静默降级；
- `system_window_denied`：系统窗口、硬基线或窗口类型拒绝（锁屏仍返回 `device_locked`，不会走本码）；
- `device_locked`：设备锁屏或息屏；
- `budget_exceeded`：本次生成的动作预算超限。

其余错误码以适配层和插件返回为准。错误信息应给出可执行的下一步，例如重新截图、重新读树、在 Mods 页重新选择工具或请用户检查无障碍服务。

输入路径的错误码优先级固定为：空包名 → `no_window`；系统包 → `system_window_denied`；其他非白名单包 → `package_not_allowed`；白名单内再校验句柄/截图，失效返回 `stale_handle` 或 `stale_observation`。因此系统窗口或非白名单应用在前台时，即使句柄已经失效，也先返回包名策略错误，而不是句柄错误。锁屏/息屏在包名策略之前检查，所有方法（含读树和截图）返回 `device_locked`。

以上是**当前实现**的链。7.5 的设计提案会在 `no_window` 之后依次插入硬基线、窗口类型和用户白名单（新增 `permission_required`），并把构建期硬禁止 `package_not_allowed` 排在用户白名单之前；硬基线与窗口类型仍复用 `system_window_denied`，因此既有三段相对顺序不变。该提案尚未实现，不得当作当前行为引用。

权限弹窗的处理边界（M20/M21 设备证伪 + M22 保守收尾）：

- API35 真实 `GrantPermissionsActivity` 弹窗期间，`rootInActiveWindow` 为 null；活动/聚焦弹窗窗口 `hasRoot=false`、`pkg=null`，`AccessibilityWindowInfo` 没有包名字段，服务也没有收到 `permissioncontroller` 的 `TYPE_WINDOW_STATE_CHANGED`。因此窗口 root 补全和事件来源包名两种识别机制均不可用，不实现。
- 该场景读树、截图和输入统一返回 `no_window`，错误消息只做条件式人工提示（“如果看到系统权限弹窗，请人工处理/取消，再返回测试应用”），不声称识别具体权限弹窗，也不把 `no_window` 写成权限场景的通过条件。
- 可取得系统包名的系统窗口仍按 `PackagePolicy` 返回 `system_window_denied`；错误优先级、读树/截图密码遮挡、白名单和输入边界不扩大。
- 异常测试的宿主 `dumpsys` 确认是测试前提，不是产品检测能力；测试不能仅因任意 `no_window` 通过，也不能因 `root=null` skip。

`system_window_denied`、`package_not_allowed` 和 `screenshot_blocked` 的适用范围必须区分：

- `system_window_denied` / `package_not_allowed` 只约束**输入**（节点动作、坐标手势、系统动作）；读树和截图不检查包名，仍可观察当前前台窗口。
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
- 输入请求拒绝可取得包名的系统窗口（`system_window_denied`）；无可访问 root 的权限弹窗保持 `no_window` 并只做条件式人工提示；锁屏/息屏时读树、截图和输入都返回 `device_locked`；读树和截图不检查包名，仍可观察当前前台窗口；
- `home`/`recents` 执行后前台会离开白名单，后续输入（包括 `back`）会被拒绝；模型无法自行把测试应用切回前台，需要用户或宿主动作恢复；
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
- 系统窗口或权限弹窗会阻止读树和截图（只有输入被拒绝）；
- 权限弹窗一定能被识别为 `system_window_denied`（API35 实测无可访问 root 且无来源包名，读树/截图/输入仍为 `no_window`，只做条件式人工提示）；
- 可视化叠加层动画代表业务成功、任务进度或用户审批（它只表示系统接受或完成动作）；
- 可视化叠加层在所有 Android 厂商设备上都可用（`addView` 可能失败，失败时只禁用可视化）；
- 上游后台胶囊会被叠加层隐藏或免于干扰（Mod 无法操作其他 owner 的窗口）。

真正需要逐步授权时，应后续增加“每个动作均由原生确认”的模式，而不是依赖危险文本识别。

### 7.5 应用边界与应用授权（第 1 步已实现，其余仍为设计提案）

> **状态分层，不要混读。** **已实现（M27 第 1 步）**：输入路径的硬基线（静态系统包集合含 settings 与厂商变体、运行时 `RoleManager` 电话/短信持有者、精确包名 `com.psyche.kelivo`）与窗口类型判定（输入允许集 `{TYPE_APPLICATION}`），集中在纯函数 `PackagePolicy`（`mods/phone_agent/plugin/android/src/main/kotlin/com/kelivo/phoneagent/AppBoundary.kt`）与 `WindowState.windowType`。**仍为设计提案**：观察边界（读树与截图仍不检查包名或窗口类型）、用户白名单与签名校验、`permission_required`、批准交互、审计。当前读树与截图的行为与 M27 之前一致，`permission_required` 从未返回过。因此**不得**把本节的观察边界、白名单与批准描述引用为已生效，也不得据此宣称 9.3/9.4 的旧设备与 VLM 结果覆盖了新边界。

#### 7.5.1 方向

- **默认拒绝**：任何未明确允许的输入目标一律拒绝，不做黑名单式放行。
- 白名单条目绑定 **`(包名, 签名证书哈希)`**，两者必须同时匹配；包名匹配但签名不符视为未批准。这样可避免“同名包换签名后继承旧授权”。
- 硬基线**不可由用户开关覆盖**，Mods 页不提供关闭硬基线的选项。
- 判定全部在**原生侧**完成，Dart 只做错误码映射与展示；Dart 侧不得成为可绕过的放行点。

判定顺序固定（插在既有链中，先命中者生效）：

`device_locked` → `no_window` → **硬基线** → **窗口类型** → 构建期硬禁止（`package_not_allowed`）→ **用户白名单**（`permission_required`，未实现）→ 句柄/截图校验（`stale_handle` / `stale_observation`）。

锁屏仍最优先，因为它在任何读窗口动作之前就要短路；`no_window` 仍是“拿不到可访问窗口”的统一出口，不由新层替代。构建期硬禁止不属于“三层判定”，它排在用户白名单之前：本次构建根本不支持的包不应被展示成“可以批准”。

**第 1 步的实际实现顺序**（`PackagePolicy.requireInputAllowed`，先命中者生效，均有 JVM 断言）：

`no_window` → 静态硬基线（含 Kelivo 精确包名）→ 角色解析失败 → 角色持有者 → 窗口类型 → 构建期白名单（`package_not_allowed`）。

与上图的两点差异如实记录：（a）“角色解析失败”被提前到角色持有者与窗口类型之前，因为解析失败时无法判断目标是不是电话/短信，宁可报 `system_window_denied`（标识 `role_resolution_failed`）；（b）静态硬基线与 Kelivo 自身放在同一判断里，都返回 `system_window_denied`，消息里分别带 `hard_baseline` 标识或用例可区分包名。用户白名单层不存在，因此本步没有任何路径返回 `permission_required`。

#### 7.5.2 三层判定

| 层 | 判定依据 | 约束范围 | 失败码 | 用户可否覆盖 |
|---|---|---|---|---|
| 1 硬基线 | 固定系统包名 + 角色解析结果 + 承载助手的 Kelivo 包 | 输入与观察 | `system_window_denied` | 否 |
| 2 窗口类型 | `AccessibilityWindowInfo.type` | 输入与观察（集合不同，见 7.5.3） | `system_window_denied` | 否 |
| 3 用户白名单 | `(包名, 签名证书哈希)` | 仅输入 | `permission_required` | 是（Mods 页撤销） |

**第 1 层 硬基线**（用户不可覆盖）：

- systemui、权限控制器（`com.android.permissioncontroller` / `com.google.android.permissioncontroller`）、包安装器（`com.android.packageinstaller` / `com.google.android.packageinstaller`）；
- **`com.android.settings` 及其厂商变体**（如 MIUI 的设置包）：该包是“用现有权限扩大权限”的入口，必须整包禁止；
- 电话/短信核心应用：按系统角色解析默认电话、默认短信持有者；
- 承载助手的 Kelivo 包 `com.psyche.kelivo`：批准卡片本身就在这个包里，允许输入等于让模型点自己的批准按钮。

硬基线失败仍返回 **`system_window_denied`**，**不新增错误码**。落地方式分三种，不能用一句“补进集合”概括：静态系统包集合补入 settings 及厂商变体；“电话/短信角色持有者”需要运行时 `RoleManager` 解析；“Kelivo 自身”是按精确包名 `com.psyche.kelivo` 的硬编码判定，不需要也无法通过角色解析。后两类在策略层另行判定。现有 `PackagePolicyTest` 的**错误码断言不变**，但调用签名会随纯函数改造增加窗口类型（及白名单）参数。

**第 1 步已实现的部分（M27）**：

- 静态集合 `HARD_BASELINE_PACKAGES`（`AppBoundary.kt`）在原 5 个 AOSP 包基础上补入 `com.android.settings`、`com.google.android.settings`、`com.samsung.android.settings`、`com.miui.securitycenter`、`com.coloros.settings`、`com.coloros.safecenter`、`com.oplus.settings`、`com.oplus.safecenter`、`com.vivo.settings`、`com.bbk.settings`、`com.huawei.systemmanager`、`com.hihonor.systemmanager`。**这是尽力枚举，不是完整清单**；漏写的厂商设置包等同于该入口没有硬基线。
- 角色持有者按 `RoleHolders` 建模，只有 `Resolved(packages)` 与 `Unavailable` 两种。`PhoneAgentService.resolveRoleHolders()` 在 API 29+ 用 `RoleManager.getRoleHolders(ROLE_DIALER / ROLE_SMS)`，更低版本退回 `TelecomManager.defaultDialerPackage` 与 `TelephonyManager.defaultSmsPackage`。**任何异常都返回 `Unavailable`，策略层据此拒绝全部输入**（`system_window_denied`，消息标识 `role_resolution_failed`），不把“解析失败”当成“没有持有者”。
- Kelivo 自身按 `KELIVO_PACKAGE = "com.psyche.kelivo"` 精确比较，测试包 `TEST_PACKAGE = "com.psyche.kelivo.phoneagent"` 独立常量；有专门用例断言测试包不被前缀/contains 规则误伤。

权限弹窗不因本层改变：API35 实测该窗口 `hasRoot=false`、`pkg=null`，在到达硬基线判定前就以 `no_window` 退出（见 6.6 与 9.3.6）。硬基线只在能取得包名时生效，不能把 `no_window` 改写成 `system_window_denied`。

注意一个实现陷阱：私有测试应用 `com.psyche.kelivo.phoneagent` 是**构建期测试白名单成员**，不是硬基线成员。若把“Kelivo 自身”写成包名前缀匹配或按包名 `contains` 判断，测试应用会自我阻断，集成测试全线失败。两者必须按精确包名区分。

**第 2 层 窗口类型**：见 7.5.3。

**第 3 层 用户白名单**：

- 条目为 `(packageName, signingCertSha256)`，签名取该包当前签名证书的 SHA-256。
- 未命中返回 **`permission_required`**（新码，见 7.5.7）：不执行、不排队、不静默降级。
- `package_not_allowed` **保留为构建期硬禁止语义**，表示“本次构建只允许这些包”，不参与运行时用户白名单；两者不得混用，否则无法区分“用户还没批准”和“这个 build 根本不允许”。

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

**第 1 步已实现（M27）**：`WindowType`（`AppBoundary.kt`）把 `AccessibilityWindowInfo.TYPE_*` 整数常量映射为枚举，`fromPlatformType` 的 `else` 分支统一返回 `UNKNOWN`；`allowsInput` 只对 `APPLICATION` 为 true。判定在 `PackagePolicy.requireInputAllowed` 内完成，编号与平台常量一致（1/2/3/4/5），有 JVM 断言覆盖 `0` 与 `99` 两个未定义取值。**观察边界（读树/截图）本步尚未接入。**

**为什么必须两层都判**：

- 只看包名会漏掉“类型敏感但包名普通”的窗口。典型是输入法：默认输入法窗口挂在自己的包名下，若用户或开发者把它加进白名单，仅靠包名就放行了输入；其他无障碍服务绘制的 overlay 窗口同样以普通应用包名出现。
- 只看类型会漏掉 `com.android.settings`：它是 `TYPE_APPLICATION`，类型层看来完全正常，必须靠硬基线拦。
- 两层是**交集关系**（都必须通过），不是二选一。

**为什么输入拒绝集可以比观察拒绝集大**：输入法窗口经常活动并覆盖在前台应用上。若观察也拒绝 `TYPE_INPUT_METHOD`，读树会直接失败、模型连正在输入的界面都看不到，这是典型反向误伤。反之，对输入法窗口本身做 tap / `set_text` 属于系统输入面操作，超出“操作目标应用”的边界，必须拒绝。

#### 7.5.4 观察边界（读树与截图）

**观察只判硬基线与窗口类型，不判用户白名单。** 理由：如果未授权应用的读树/截图也被拒绝，模型在未授权应用里看不到任何内容，就无法向用户说明“我需要这个应用的授权”，用户也无从判断要不要批准。批准应当发生在模型已经说明意图之后，而不是发生在模型完全盲视时。

因此必须如实声明能力边界：

- **不承诺读树不泄漏第三方应用自身界面文本。** 应用自身界面内容（消息列表、聊天记录、应用内的通知中心等）仍会进入工具结果（结果继续带 `untrusted_content` 标记与内容边界声明）。本设计只承诺：`TYPE_SYSTEM`（通知栏/状态栏）窗口与硬基线窗口不可被观察，输入法窗口可被观察但不可输入。
- 这里有个容易误读的地方：通知栏本身被阻断，**不等于**通知内容不会泄漏——同一条通知的文字可能同时出现在第三方应用自己的界面里，而那属于应用自身界面。因此不能把“通知栏不可观察”宣传成“通知内容不会进入模型”。
- 密码节点文本仍按 7.1 隐藏，密码遮挡仍是“尽力而为”，本设计不把密码防护计入白名单方案的收益。

**截图的前台判定必须先于且独立于全窗口密码遮挡遍历**：

- 顺序固定为：取前台 `WindowState` → **观察边界判定**（硬基线 + 窗口类型）→ 通过后才执行 `collectPasswordBounds` 全窗口遍历 → 截图。
- `collectPasswordBounds`（`PhoneAgentService.kt:454`）读的是**所有**窗口的 root，不能因为前台被拒就缩窄遍历范围，也不能把“前台不合格”当成“不用遮挡”。
- 两者必须在代码上是独立步骤：遮挡遍历只按密码节点与自身 overlay 规则工作，不感知边界策略；边界策略也不读节点内容。
- 入口判定之后不必再加一次类型判定：既有 `ScreenshotCapture` 的 gate 与 `onSuccess` 回调比较的是**完整 `WindowState`**（`OverlayVisuals.kt:136` 的 `windowChanged(original, latest) = latest != original`，`WindowState` 是 data class，逐字段比较 `windowId`/包名/宽高/旋转），不一致即返回 `stale_observation` 且不发图。把 `windowType` 加入 `WindowState` 后，这处比较会自动覆盖类型变化，因此入口判定之外的补判并非必需。仍需实测的假设收窄为：同一 `windowId` 的窗口类型在正常使用中是否会发生变化；若确实会变，应让比较继续覆盖它，而不是取消入口判定。

#### 7.5.5 三项已定决策

三项由用户明确决定，不再作为开放问题：

**（1）白名单作用域 = 全局共享（不按助手隔离）**

- 理由：多数用户只有一两个助手，按助手隔离会让同一应用换个助手就重新弹批准，摩擦直接翻倍，正是要避免的成本。
- 代价：跨助手越权——“私人助手”批准的应用会被“工作助手”继承，两个助手的权限语义不同却共享一份授权。
- 缓解：每条白名单记录**首次批准来源助手 id**，Mods 页按来源分组展示；这为将来做助手级隔离留下迁移条件，不必重做存储结构。当前不提供“仅本助手”开关。

**（2）批准时效 = 长期有效 + Mods 页显式撤销**

- 不做一次性：一次性等于每动作都问，等于否定整个授权方向。
- **不做定时过期**：定时过期会让长任务在不可预期时刻（例如半夜）失败，比“授权沉底”更糟；用户也无法预知何时到期。
- 代价：授权沉底、长期无人复习。
- 缓解：Mods 页白名单管理页显示包名、签名哈希（可只显示前缀）、批准时间、最后使用时间、来源助手，并提供撤销；撤销立即生效（下一次调用重新判定，不缓存放行结果）。
- 撤销不撤销“已发出的动作”：撤销只影响后续调用。

**（3）审计 = 落盘元数据，滚动保留**

- 记录字段（仅此）：时间戳、助手 id、会话 id、包名、签名证书哈希前 8 个十六进制字符、动作类型（工具/动作名）、结果码。
- **明确不记录**：节点文本、输入文本、密码内容、截图或图片字节、界面内容摘要、坐标数值、窗口标题。
- 保留策略：滚动保留 **30 天或最近 2000 条**，先到者生效；超出即淘汰旧记录。
- 与“不写敏感日志”的口径划界：该条约束的是**内容**（不写截图字节、密码文本、节点文本到日志或崩溃报告）；审计只写**元数据**，元数据不是内容。两者不冲突，但不能据此把审计称为“不涉及隐私”——它仍能推断“用过哪些应用”，这是明确接受的代价。
- 不做上传、不做远端同步；审计文件属于本地状态，不进入仓库、不进入工具结果、不发给模型。

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

#### 7.5.7 `permission_required` 契约

- **立即返回，不阻塞**：检测到未批准时立刻返回 `permission_required`，不持有 `Completer` 等待、不排队重试、不静默降级为只读。与 7.5.6 的关系需要读清：我们复用 `ToolApprovalService` 的**请求结构与 UI 通知机制**，但批准请求**不挂在工具调用上**——工具调用拿到 `permission_required` 就结束，卡片/通知是独立的状态记录，有自己的 TTL 与终态收敛规则。因此“立即返回”与“复用该服务”并不互斥：互斥的只是“复用它的等待语义”。
- 理由是数字，不是偏好：Dart 通道超时 **35 秒**（`phone_agent_service.dart:149`），原生排队超时 **15 秒**（`PhoneAgentService.kt:35` 的 `QUEUE_TIMEOUT_MS`）。让工具调用等一封可能几小时后才来的批准，必然先把设计好的 `permission_required` 退化成 `timeout`，模型无法区分“用户拒绝”“用户不在场”和“系统卡住”。
- 明说取舍：批准未到时**当前任务停在此处**；用户批准后模型需要**重新观察**（旧句柄、旧截图会因时间与窗口变化失效），之前规划的步骤不能假设仍然有效。**长任务会中断**，不描述成无感体验，也不描述成“部分完成”。
- 不自动批准、不自动重试、不在失败后循环弹批准卡片。
- 模型可见文案（英文，与结构化错误风格一致）：

  `Input into <package> needs the user's approval. The action was not executed and is not queued. Ask the user to approve this app in Kelivo, then decide whether to retry. Do not retry the same call repeatedly.`

- 该文案只含包名，不含节点文本、输入内容或截图信息；`permission_required` 与 `system_window_denied` 必须可区分：前者“可以批准”，后者“永远不行”。

#### 7.5.8 与既有错误码的关系

- 6.6 与 6.5.1 的既有码与优先级**继续有效**，本节只在其间插入三层判定，并新增 `permission_required`。
- 硬基线与窗口类型复用 `system_window_denied`，靠固定标识区分来源；不新增 `system_settings_denied` 之类的码，因为集合成员资格已经表达语义，新增码会稀释既有断言。
- `package_not_allowed` 仅表示构建期硬禁止（当前即“只允许测试包”）；实现运行时白名单后，**不要让同一个码同时表示“用户未批准”**。
- 本节不改变 `device_locked`、`no_window`、`stale_handle`、`stale_observation`、`screenshot_blocked` 的含义与范围。

### 7.6 实现前置风险与行为变更（尚未实现）

本节列的是**动手前必须处理**的事项，不是已完成工作。

**风险 1：`WindowState` 需要新增 `windowType`，波及 `sameWindow()` 与全部构造/调用点（M27 第 1 步已实现）**

- `WindowState`（`ObservationRegistry.kt`）原本只有 `windowId` / `packageName` / `width` / `height` / `rotation`，**没有窗口类型字段**；`AccessibilityNodeInfo` 不提供窗口类型，类型只能来自 `AccessibilityWindowInfo.type`，需要按 `windowId` 在 `windows` 里另行匹配。
- 因此 `PhoneAgentService.windowState(root)`（`WindowState` 的唯一构造点）必须多一次 `windows` 枚举与 id 匹配；`windowState(...)` 的直接调用点是读树、截图与 `currentWindow()`（输入路径经它进入）。实际 `WindowState(...)` 构造仍只有一处。
- 不得为了省事在策略层另读一次 `windows`：`rootInActiveWindow` 与 `windows` 是两次读取，中间可能切窗，会引入新的竞态。类型必须与 `WindowState` 同源、同一次读取，才能保证“判定用的窗口”就是“执行用的窗口”。**实现即按此规则：`windowType(windowId)` 在 `windowState()` 内部调用，策略层不接触 `windows`。**
- `sameWindow()` 与截图观测比较都加了 `windowType`；同一窗口 id 的类型在正常使用中不变，但这是**待实测假设**，不是已知事实，因此设备回归必须覆盖“正常场景不出现新的 `stale_*`”（见 9.3 的未验证项）。
- 类型解析失败（`windows` 不可读、找不到对应 `windowId`、或返回未知类型）**fail closed**：一律落到 `WindowType.UNKNOWN`，输入拒绝。
- 测试夹具里的 `WindowState(...)` 构造已同步，并用常量 `TEST_PACKAGE` / `KELIVO_PACKAGE` 取代散落的字符串；策略本身是纯函数，纯 JVM 覆盖，未引入 Robolectric 或新依赖。

**风险 2：`phone_agent_exception_test.dart` 会因观察边界变红，必须同批改宿主 `dumpsys` 确认**

观察边界收紧后，异常套件共有 **5 处** 依赖"读树能看到非本应用前台"的地方会失败，实现观察边界时必须同批改掉，否则套件无法变绿：

**（a）settings 树依赖（服务禁用/中断/重启用例）**

- `phone_agent_exception_test.dart:537` 靠读 `com.android.settings` 树判断宿主已打开无障碍详情页，`:549-550` 靠读 settings 树并断言存在 `Turn off` 节点来判断关闭确认弹窗已出现。
- 同一用例的 pending 批次也在该页面上建立观测：`:557` 的 `_tree(service)` 与随后 1000 个 `readTree(offset: 1)` 都是在无障碍设置页前台时发出的（见 9.3.1 的“先建立 Settings 观测”）。观察边界一收紧，这一步会直接返回 `system_window_denied`，用例在到达禁用断言前就失败。
- 改法：这三处全部改为**宿主 `dumpsys` 独立确认**（`dumpsys window` / `dumpsys activity` 判断前台是设置页或确认弹窗）；pending 批次改在测试应用自身前台（`TYPE_APPLICATION`）上建立观测，不再依赖 Settings 页面。

**（b）`:202-232`「叠加层可见时真实触摸不被拦截」**

- 第 `219` 行 `final tree = await _tryTree(service);` 轮询等待前台包名 `!= _appPackage`（`:221-224`），宿主 `adb shell input swipe` 触摸后打开的是通知栏（`com.android.systemui`，`TYPE_SYSTEM`）。`TYPE_SYSTEM` 拒观察后 `_tryTree`（`:759-773`，`ok != true` 即返回 null）恒为 null，`:228` 的 `expect(foreground, isNotNull)` 必然失败——而且失败点正是"证明叠加层不拦截宿主触摸"这个核心断言。
- 改法：前台由**宿主 `dumpsys` 确认通知栏已打开**并打印标记，测试侧只保留叠加层可见性证据（叠加层是否在触摸期间显示、截图无污染等既有断言），不再用读树取前台包名。

**（c）`:346-377`「home 与 recents 后输入被包名策略拒绝」**

- 该用例经 `_expectSystemNavigationDenied`（`:1005-1040`）驱动：`:1019` 的 `_waitForTreeWhere`（`:913-928`，内部同样走 `_tryTree`）读树等待前台离开白名单。`home`/`recents` 后前台通常是 systemui，读树被窗口类型拒绝后拿不到 `package_name`，在 `:1025` 的 `expect(foreground, isNotNull)` 处失败，根本到不了 `:1037`/`:1039` 的输入错误码断言。
- 改法：由**宿主确认前台已离开白名单**，测试直接断言输入与 `back` 的错误码（`system_window_denied` / `package_not_allowed`），不再依赖读树取包名；`_systemPackages` 的期望值改由宿主提供的包名或固定期望给出。

**（d）不受影响的部分（避免过度改动）**

- `phone_agent_test.dart` 不读 settings，不受观察边界影响。
- `:116-127`、`:303`、`:334`、`:479` 等读树点都在测试应用自身前台（`TYPE_APPLICATION`），不需要改。
- 权限窗口用例读树得到 `no_window`（不只是"失败"），与本层无关，保持原样。

**（e）宿主确认是前提不是产品能力**

- 这不是推翻既有分工，而是把它补完整：`mods/phone_agent/README.md` 的故障排查与 9.3.1 的边界本就写明服务开关由宿主在系统界面操作、测试只轮询断言，以及权限弹窗由宿主 `dumpsys` 独立确认；但**没有**规定（a）（b）（c）三类用例的前台也要由宿主独立确认。实现本提案时必须补上，否则测试无法在不读 settings 树、通知栏或系统窗口的前提下知道自己在哪一页。
- 反过来说：在测试依赖改完之前，不能宣称新边界“已通过异常套件”。

**风险 3：行为变更（收紧），不是纯新增**

- 读设置页、通知栏、输入法窗口、被其他无障碍层覆盖的前台，将从“成功”变为 `system_window_denied`（输入、观察或两者）。
- 白名单内应用与非硬基线第三方应用的读树/截图行为不变，但输入从“只看是不是测试包”变为“要用户批准”，这是**用户可见的行为变更**，需要 Mods 页白名单管理页与文案同步。
- 已安装用户升级后不会自动获得任何白名单条目（默认拒绝），首次调用即返回 `permission_required`。

**风险 4：历史 VLM 结果不能用于宣称新边界已验证**

- 9.4 与 10.1 的 VLM 固定任务、坐标动作、像素专属确认全部来自**旧代码**（读树/截图无边界、输入限单测试包）。
- 实现新边界后必须重新跑：API35 官方测试、完整异常套件、物理 MIUI 官方测试，以及至少一轮 VLM 固定任务（含一次 `permission_required` → 批准 → 重试的完整链路）。
- 在重跑之前，文档只能写“新边界未验证”。

**风险 5：实现前需要设备实测确认的假设**

- Android 11+ 包可见性限制下，能否解析**任意前台包**的签名证书哈希（是否必须声明 `QUERY_ALL_PACKAGES` 或按包名查询；后者与“任意前台包”天然矛盾）。
- `RoleManager` 角色解析在 MIUI 等厂商 ROM 上能否稳定解析默认电话/短信/设置持有者；解析失败必须按最严拒绝。
- 厂商设置包变体（如 `com.miui.securitycenter` 之外的设置实现）是否能被完整覆盖；漏写即等于没有硬基线。
- 通知 action + `BroadcastReceiver` 在 API 31–35 的行为（点击回调、进程被杀后重放、幂等）。
- `WindowState` 增加 `windowType` 后 `sameWindow()` 是否会让正常场景误报 `stale_*`。

以上均**未实测**；实现前不得在文档中写成“已知可行”。

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
- 硬基线扩展（M27）：`com.android.settings` 与常见厂商变体（`com.miui.securitycenter`、`com.coloros.*`、`com.oplus.*`、`com.samsung.android.settings`、`com.huawei.systemmanager`）均返回 `system_window_denied`；默认电话/短信角色持有者被拒；`RoleHolders.Unavailable` 时拒绝全部输入（`role_resolution_failed`）；Kelivo 自身 `com.psyche.kelivo` 被拒而测试包 `com.psyche.kelivo.phoneagent` 不被误伤（含 `com.psyche.kelivo.phoneagent.other` 前缀反例）；
- 窗口类型（M27）：`INPUT_METHOD`/`SYSTEM`/`ACCESSIBILITY_OVERLAY`/`SPLIT_SCREEN_DIVIDER`/`UNKNOWN` 均返回 `system_window_denied`，仅 `APPLICATION` 放行；平台常量映射含未定义值 0 与 99 回落 `UNKNOWN`；拒绝消息含固定标识 `window_type_*` 且不含包名；硬基线优先于窗口类型、窗口类型优先于构建期白名单；
- `WindowState.windowType` 变化使树分页、句柄和截图观测失效（`stale_observation` / `stale_handle`）；
- 输入错误码优先级：空包名 `no_window` → 硬基线/角色/窗口类型 `system_window_denied` → 非白名单 `package_not_allowed` → 白名单内句柄/截图校验；
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

最终验收已完成；仍不宣称第二阶段全部完成，未验证项见 10.2。

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
- `system_window_denied` 和 `package_not_allowed` 只约束输入；**当前实现**下读树和截图仍可观察系统窗口、权限弹窗和其他应用（7.5 的设计提案会让系统窗口与硬基线窗口不可观察，尚未实现，见该节状态块）。
- 应用边界与应用授权（7.5/7.6）**只是设计提案，尚未实现**：当前版本没有用户白名单、签名绑定、批准卡片、通知栏批准、`permission_required`、窗口类型判定和审计；输入仍只允许测试包，读树与截图仍不检查包名或窗口类型。该设计未经任何设备或测试验证，不得写成已生效能力。
- `home`/`recents` 执行后前台离开白名单，后续输入（包括 `back`）会被拒绝，模型无法自行回到测试应用，需要用户或宿主恢复。
- `SecureWindowFixtureActivity` 只是 debug 测试夹具，不是产品能力；release 不包含该 Activity。
- API35 模拟器已验证旋转、home/recents、锁屏、服务禁用/重启；物理 MIUI API31 真机已验证旋转和物理 `FLAG_SECURE`，但锁屏、home/recents、服务禁用/重启未在物理设备运行，不能从模拟器结果推断；原生超时仍无法在设备上确定性触发。
- 未执行带合法签名配置的 release 构建。
- 因此不宣称 Phone Agent 第二阶段全部完成。
- Loader 更新演练通过不代表 Phone Agent 真机行为无需重新验证。
