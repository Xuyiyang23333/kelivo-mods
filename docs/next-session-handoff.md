# 下一次会话交接：Phone Agent 前台可视化叠加层

## 0. M23 当前状态（2026-11-12）

- 本轮目标：按 M18 只读设计实现首版前台可视化叠加层（V1 原生核心），不新增设置开关、`status` 字段、ARB 文案或插件通道方法；不改 schema、白名单、上游宿主和 `mod.json`。
- 契约：独立 `PhoneAgentOverlay` 使用 `TYPE_ACCESSIBILITY_OVERLAY` + `FLAG_NOT_TOUCHABLE | FLAG_NOT_FOCUSABLE`，不申请普通悬浮窗权限，不复用上游 `BackgroundRuntime`/`BackgroundOverlay`。只在真实工具观察（读树、截图完成后）和允许包内已接受的动作（`perform`/`dispatchGesture`/`performGlobalAction` 返回 true）时短暂显示；拒绝路径不产生动画；动画不代表业务成功、任务进度、模型思考或用户审批。
- 隐私：只用无文本图形，不显示输入文字、密码、截图字节或缩略图、节点文本、包名和坐标数值。截图前移除自身窗口并等待两帧加 48ms 合成周期，隐藏失败或附着状态未知返回 `screenshot_failed` 且不发图；读树不隐藏叠加层。密码窗口遍历只跳过能可靠确认属于本服务的 accessibility overlay（root 存在且 root 包名等于自身包）；root 包名未知或其他包名继续参与遮挡。
- 代码：新增 `OverlayVisuals.kt`（纯 JVM 事件、几何、状态机、截图隐藏握手、`OverlayShowGate`、`OverlayAttachmentTracker`）和 `PhoneAgentOverlay.kt`（窗口、无文本图形、主线程生命周期、按 View 清理）；接入 `PhoneAgentService`、`NodeActionExecutor`、`ScreenshotCapture`；新增 `OverlayVisualsTest.kt` 并扩展 `NodeActionExecutorTest.kt`。
- 返工（reviewer round 1，6 项 findings）：密码遮挡未知包名不再排除；show 在主线程绘制前校验清理代次和 `isActive`（手势 finished、服务 epoch）；移除失败/未知附着 fail closed 且按具体 View 清理；手势 travel 复用真实 50–2000ms；触摸穿透改为宿主 adb 独立触摸；迟到帧测试保存 resume 前回调并显式执行。
- 返工（reviewer round 2）：截图隐藏握手后、`takeScreenshot` 前重新读取当前窗口并比较 `windowId`/包名/宽高/旋转，变化返回 `stale_observation` 且不发图；两次读取中窗口为 null 均按 `stale_observation`，`currentWindow()` 抛异常按 `screenshot_blocked` fail closed；`onSuccess` 回调里再比较一次当前窗口，不一致不处理/不发送图片。同一活动窗口内新出现密码字段、非活动分屏窗口变化和同窗口分屏 resize 不保证遮挡，已在 plan 2.6/7.4 与 README 写成已知限制。`OverlayAttachmentTracker` 格式修正且生产 `hideNow` 使用 `hideResult()`；动作开始时捕获清理代次并传给 `show`，动作后 clear/切窗使旧视觉失效；补 `begin` 替换、`password_node_denied`、窗口变化和重复 resume JVM 测试；round-1 的 `099843`/`e6de` 仅作历史。**round-2 当时**的基线为设备树 `f1b26a58`、最终树 `2445a838`、无产品 APK；round-4 当前基线见第 0 节（设备树 `9ebf2e99`、最终树 `af52c6f7`、产品 APK 181,402,630 / `a72cac9b…`）。
- 已知限制：上游可触摸后台胶囊无法被 Mod 隐藏，开启胶囊时截图可能含胶囊、坐标手势可能被拦截；`addView` 在部分厂商 ROM 上可能失败，失败时只禁用本会话可视化；截图隐藏握手增加约两帧加 48ms 合成等待和极少量 `screenshot_failed` 风险。
- round 4 结果（2026-11-12，源码树 `V:/coding/kelivo-private/.tower/worktrees/wt-23/.build/worktrees/9ebf2e991caa07ed`，`modsetHash` `9ebf2e991caa07ed3e8e5b4484649de84139e89a31ac8837f779ca34aa2d8c66`）：API35 独立 AVD `Kelivo_M23_API_35` 完整异常套件 **`+8`、`All tests passed!`、EXIT=0**（含旋转、锁屏、服务禁用/重启、权限窗口 `no_window`），官方 `phone_agent_test.dart` `+2`、EXIT=0；物理 MIUI API31 官方 `+2`、EXIT=0，「叠加层不污染产品截图」`+1`、EXIT=0；本地 Loader 165、插件 Kotlin 97、Flutter Mod/Phone Agent 126、Loader/根项目静态分析和 `verify` 通过。产品 debug APK 在最终树 `flutter clean` 后显式构建：181,402,630 字节，SHA-256 `a72cac9bf90029e21cc569e04cac8abfcc656a044643c6b096e6b6270ea70eca`。
- API35 结果（返工后，2026-11-12）：官方 `phone_agent_test.dart` `+2`、EXIT=0（返工树）。完整异常套件多次整轮运行的真实退出码均为 1，未得到绿色整轮：旧 AVD 一次 `+6 -2`（锁屏/服务禁用失败，期间模拟器 system_server 重启），一次 `+7 -1`（唯一失败为「服务禁用中断与重新启用恢复」的宿主设置页时序），最后一次有界整轮在 `setUpAll` 失败（`dumpsys activity lastanr` 为 `Input dispatching timed out (Application does not have a focused window)`，ANR 发生在任何工具调用之前、应用进程存活、无障碍连接为 DEAD，属宿主/模拟器窗口焦点与输入分发问题，不是 overlay 主线程死锁）。独立测试 AVD `Kelivo_M23_API_35`（`.build/avd`，已有 android-35 google_apis_playstore x86_64 镜像，不 wipe 旧 AVD）官方 `+2`、EXIT=0，完整异常套件最好 `+7 -1`、EXIT=1（唯一失败同为服务禁用宿主时序），另一次 `+6 -2`；旧 AVD 另出现 `com.android.systemui` 的 `Input dispatching timed out ([Gesture Monitor] edge-swipe (server) is not responding)`，无产品栈。round 2 树 `f1b26a580b737e14` 的完整异常套件为 `+6 -2`、EXIT=1：失败为「旋转后旧句柄与旧截图失效」（转回竖屏截图 10 秒 timeout，单独重跑 `+1`、EXIT=0）和「锁屏 device_locked 与解锁恢复」（宿主恢复等待点击目标超时，单独重跑 `+1`、EXIT=0）；「服务禁用中断与重新启用恢复」该轮通过且单独重跑 `+1`、EXIT=0（`codes=interrupted,ok`）。round-2/3 历史轮未生成产品 APK；round-4 产品 APK 已生成，见第 3 节。
- MIUI 结果（返工树，2026-11-12，`1960cd68`）：官方 `phone_agent_test.dart` `+2`、EXIT=0；「叠加层不污染产品截图」`+1`、EXIT=0；「叠加层可见时真实触摸不被拦截」`+1`、EXIT=0（`PHONE_AGENT_OVERLAY_HOST_TOUCH_RESULT: package=com.android.systemui`，宿主 `adb shell input swipe` 独立注入）。服务停用后 `dumpsys window windows` 中叠加层窗口数为 0；已恢复 `enabled_accessibility_services=null`、`accessibility_enabled=0`、`stay_on_while_plugged_in=0`。
- API35 宿主侧一次性清理（审计记录）：授权阶段 watcher 固定坐标误触 TalkBack 授权弹窗，TalkBack 被短暂启用；宿主用 `settings put secure enabled_accessibility_services` 清空以移除误启用的 TalkBack，随后仍通过系统 UI 为 Kelivo Phone Agent 打开开关并点 Allow。该命令只清理宿主误操作，不是 Phone Agent 授权路径、不是产品能力、不是授权绕过，也不扩展到其他设备；Phone Agent 授权仍只走系统 UI。
- round 4 API35 叠加层清理与像素证据（构建树 `a460dcbc`，代码/测试与设备树 `9ebf2e99` 一致，仅 README 副本不同）：服务禁用用例单独重跑 `+1`、All tests passed!、EXIT=0；宿主 `dumpsys window windows | grep -c PhoneAgentOverlay` 原始输出 `R5_OVERLAY_WINDOWS_AFTER_DISABLE: count=0`、`R5_OVERLAY_WINDOWS_AFTER_RESTART: count=0`。宿主 `screenrecord` 帧确认观察脉冲（约 121.5–121.9s，强调色 `#008999` bbox 约 34×34）和节点点击圆环（约 125s，浅蓝圆环），坐标滑动轨迹在 30fps 帧中未检测到，仍属未验证。
- 宿主稳定性重试：`_screenshot` 对 `rate_limited`/`timeout` 最多重试 2 次；旋转用例绿色不证明单次截图总能在 10 秒内完成，产品超时语义未改变。
- 交付树（round 4）：设备运行树 `V:/coding/kelivo-private/.tower/worktrees/wt-23/.build/worktrees/9ebf2e991caa07ed`（`modsetHash` `9ebf2e991caa07ed3e8e5b4484649de84139e89a31ac8837f779ca34aa2d8c66`）；最终源码树 `V:/coding/kelivo-private/.tower/worktrees/wt-23/.build/worktrees/af52c6f7b3a9dba4`（`modsetHash` `af52c6f7b3a9dba405ab63379aa8579489533f669e70a5a1ca9e31e5cdb38132`），与设备树仅 `plugin/README.md` 文档副本不同；产品 APK 构建树 `a460dcbcab5c166e` 与当前最终树仅 `plugin/README.md` 副本不同（README 不进入 APK）。`plan`/`verify`、format、Loader 165、Kotlin 97、Flutter 126 和静态分析通过；产品 debug APK 在构建树 `flutter clean` 后显式构建：181,402,630 字节，SHA-256 `a72cac9bf90029e21cc569e04cac8abfcc656a044643c6b096e6b6270ea70eca`；debug merged manifest 含 `SecureWindowFixtureActivity`，release merged manifest 不含该夹具。round 2 历史树：设备运行树 `f1b26a580b737e14`、最终源码树 `2445a838f5b71e56`。
- 未验证：API29、签名 release、MIUI keyguard 遮挡、上游胶囊开启兼容；观察脉冲和节点点击圆环已获宿主 `screenrecord` 像素证据，坐标滑动轨迹仍未获像素捕获（30fps 帧未检测到强调色圆点/轨迹），不能写成像素级验证。

### M22 历史状态（2026-11-12）

- 本轮目标：按用户同意做权限弹窗保守收尾，不追查新识别机制。只改中文文档、`PhoneAgentService` 无可访问窗口的英文提示和 debug 异常测试；不改 schema、白名单、上游、读树/截图密码遮挡或输入边界。
- 契约：不可识别权限弹窗仍返回 `no_window`，读树/截图/输入共用条件式人工提示（“如果看到系统权限弹窗，请人工处理/取消，再返回测试应用”），不声称识别具体权限弹窗；可取得系统包名的窗口仍返回 `system_window_denied`；错误优先级和输入边界不变。宿主 `dumpsys` 确认是测试前提，不是产品检测能力。
- M20/M21 证据（均 abandoned，未合并生产代码）：API35 真实 `GrantPermissionsActivity` 期间活动/聚焦弹窗窗口 `hasRoot=false`、`pkg=null`，`AccessibilityWindowInfo` 没有包名字段；唯一有 root 的是后台 `com.android.systemui`（`active=false focused=false`）；服务没有收到任何 `permissioncontroller` 的 `TYPE_WINDOW_STATE_CHANGED`，只有 `pkg=null` 的 `TYPE_WINDOWS_CHANGED`。窗口 root 补全和事件来源包名两种机制均不可用。
- 测试改动：删除 `root=null` 的 skip 分支；宿主在 `PHONE_AGENT_PERMISSION_WINDOW` 后唤醒、启动夹具并用 `dumpsys` 确认真实弹窗，测试轮询进入 `no_window` 后直接调用节点 `tap`、截图和 `back`，断言精确 `no_window` 与条件式提示；`back` 后读树仍为 `no_window`，证明没有执行系统导航；宿主取消弹窗后确认 `POST_NOTIFICATIONS` 仍 `granted=false`。首次 45 秒未进入时打印 `PHONE_AGENT_PERMISSION_WINDOW_RETRY` 再等 60 秒，仍未进入则失败，不把任意 `no_window` 当作通过。
- 本轮结果：设备运行树 `V:/coding/kelivo-private/.tower/worktrees/wt-22/.build/worktrees/d94f4165af9277d5`，`modsetHash` `d94f4165af9277d5bbdc83c3c07bcc5bdce55cb4c241a284edfdcd5d5d0a2c9d`；R1 文档返工后最终源码树为 `V:/coding/kelivo-private/.tower/worktrees/wt-22/.build/worktrees/b9989da92f35bac8`，`modsetHash` `b9989da92f35bac8703cb5ed803499222886ec6bae15d5e8045a8e45b6689725`，两树仅 `plugin/README.md` 文档副本不同，代码/测试一致，未重跑设备。API35 官方 `phone_agent_test.dart` `+2`、EXIT=0；完整异常套件 `+6`、EXIT=0，权限场景宿主 `dumpsys` 确认 `GrantPermissionsActivity`，测试打印 `PHONE_AGENT_PERMISSION_TREE: package=null type=tool_error error=no_window`，tap/截图/back 均 `no_window` + 条件式提示，back 后仍 `no_window`，`POST_NOTIFICATIONS` 仍 `granted=false`；服务禁用批次 `size=1000 elapsed=670ms codes=interrupted,ok`。Loader 165、根项目 seam 56、插件 Dart 17、插件 Kotlin 66 通过（设备测试树；代码/测试与最终树一致），最终树静态分析 `No issues found!`。产品 APK 与最终树记录见第 3 节。
- 下一阶段：可视化叠加层设计已获批准，但不在本 mission 实现；本 mission 不新增 overlay、不改 UI。
- 未验证：签名 release、原生截图/手势/通道/worker 排队超时、`stale_handle` 根因；API29 真机 `357784090209204` 本轮不在线；物理 MIUI API31 未运行锁屏、home/recents、服务中断和权限弹窗；`llama-cpp/llama-cpp` 的物理完整坐标 swipe 未完成。
- 环境注意：本 worktree 为 LF（`core.autocrlf=false`）。Windows 上创建合成 worktree 需 `core.longpaths=true`，本轮通过 `GIT_CONFIG_COUNT/KEY_0/VALUE_0` 进程环境传入，未修改上游 Git 配置；未加该设置时 `git worktree add` 会因长路径失败，Loader 会留下状态文件，需 `clean --modset <hash>` 后重试。API35 模拟器 `emulator-5554` 本轮由工作代理启动（AVD `Kelivo_Phone_Agent_API_35`）。

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

首版输入仍只开放给测试包名 `com.psyche.kelivo.phoneagent`。不要扩大白名单、引入自动无障碍授权，或把发送/购买/删除确认描述成原生硬护栏。

## 3. 已有实现与交付基线

- 上游基线：`73afa4ec77cfc9af2efea2487fee8bba1362639d`。
- 当前 Mod 版本：`0.2.0`。
- 当前 M23 设备运行树：`V:/coding/kelivo-private/.tower/worktrees/wt-23/.build/worktrees/9ebf2e991caa07ed`（`modsetHash` `9ebf2e991caa07ed3e8e5b4484649de84139e89a31ac8837f779ca34aa2d8c66`）。
- 当前 M23 最终源码树：`V:/coding/kelivo-private/.tower/worktrees/wt-23/.build/worktrees/af52c6f7b3a9dba4`（`modsetHash` `af52c6f7b3a9dba405ab63379aa8579489533f669e70a5a1ca9e31e5cdb38132`），与设备运行树仅 `plugin/README.md` 文档副本不同，代码/测试语义一致；`plan`/`apply`/`verify` 通过。产品 APK 构建树为 `a460dcbcab5c166e`，与当前最终树仅 `plugin/README.md` 副本不同（README 不进入 APK）。
- 当前 M23 产品 debug APK（最终树 `flutter clean` 后显式 `flutter build apk --debug`，测试后未在该树运行 integration_test）：**181,402,630 字节**，SHA-256 `a72cac9bf90029e21cc569e04cac8abfcc656a044643c6b096e6b6270ea70eca`；debug merged manifest 含 `SecureWindowFixtureActivity`（1 处），release merged manifest 不含该夹具（0 处，不宣称签名 release）。设备运行树 `9ebf2e99` 的 `app-debug.apk` 是 219,614,552 字节的测试入口构建，只作设备/测试证据，不作为产品。round-2/3 的「产品 APK 未生成」仅为历史，不代表当前。
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
