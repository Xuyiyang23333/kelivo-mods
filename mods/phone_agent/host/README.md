# Phone Agent 宿主测试脚本

本目录放**宿主侧**（操作设备的那一端）测试脚本，仅用于复现 `phone_agent` 的
集成测试结果。它不是产品代码：

- 不被 `mod.json` 的 `patches` / `copy` 引用，不进合成树，不参与 APK 构建；
- 不修改通用 Kelivo 接缝，也不 import 任何 `package:Kelivo/...`；
- 只能执行测试文档已经要求的宿主动作（启动夹具、注入真实触摸、开关无障碍、
  切前台），**不能绕过系统 UI 授予无障碍权限**（见下文的 MIUI 例外）。

`app` 侧的 `integration_test/phone_agent_exception_test.dart` 会打印
`PHONE_AGENT_*` 标记，脚本按标记执行对应动作。这是「测试打印、宿主执行」的
既定分工，不是产品能力。

## 文件

| 文件 | 用途 |
| --- | --- |
| `driver.py` | 异常套件（`phone_agent_exception_test.dart`）的宿主驱动 |
| `run_official.py` | 官方测试（`phone_agent_test.dart`）的最小宿主包装，只负责授权并拒绝随后的通知权限弹窗 |
| `run_approval_chain.py` | 应用批准链路（`phone_agent_approval_chain_test.dart`）的宿主驱动：负责前台与授权编排（`KEYCODE_HOME`、`enable_service` 点系统 Allow、`svc power stayon`、`KEYCODE_WAKEUP`、`wm dismiss-keyguard`）与证据抓取 |
| `_runs/` | 运行日志与 UI dump 输出目录（已 gitignore） |

`run_approval_chain.py` 的 `evidence()` 抓的 PNG/XML 可能拍在 `KEYCODE_HOME` 落定
之前（实测拿到的是测试应用自己的界面），因此它们只作「应用内状态」旁证，**不作为
launcher 前台证据**。目标前台的真正证据是测试打印
`PHONE_AGENT_APPROVAL_OBSERVED: package=<目标包> nodes=<N>`（断言读树的
`package_name` 等于目标包且节点非空）。目标包默认 Pixel Launcher，可用
`--dart-define=PHONE_AGENT_TARGET_PACKAGE=<包名>` 覆盖（放进 `TEST_ARGS`）。

证据文件名：本轮留存的是 `approval-launcher-foreground.png/.xml`（真实存在）；
R1 之后默认前缀已改为 `approval-chain-app-state`，但**没有再跑过**，新名文件
下次运行起才生效。

## 用法

```bash
# 异常套件（需要已通过 Loader 合成的树）
APP_TREE=/path/to/.build/worktrees/<modsetHash> \
SERIAL=emulator-5554 \
python3 mods/phone_agent/host/driver.py

# 官方测试（API35：授权走系统 UI）
APP_TREE=... SERIAL=emulator-5554 \
python3 mods/phone_agent/host/run_official.py

# 官方测试（物理 MIUI 例外设备：允许 settings put secure）
APP_TREE=... SERIAL=1960cd68 USE_SETTINGS_PUT=1 \
python3 mods/phone_agent/host/run_official.py

# 应用批准链路（宿主负责前台与授权编排 + 证据抓取）
APP_TREE=... SERIAL=emulator-5554 \
python3 mods/phone_agent/host/run_approval_chain.py
```

环境变量（`run_official.py` / `driver.py` 同 `run_approval_chain.py`）：`APP_TREE`（必填）、`SERIAL`、`DRIVER_LOG`、`OUT_DIR`、
`FLUTTER_BIN`、`TEST_ARGS`（正则测试名要放这里，多个 `--plain-name` 是 AND
语义）、`TEST_FILE`、`USE_SETTINGS_PUT`。

## M36 的四处补充修正（都是宿主/测试侧，产品未改）

对应 `docs/phone-agent-plan.md` 9.3.8 的逐条失败：

1. **`adb()` 超时不再抛出**（`adb()`）。单次 `uiautomator dump` 超过 45 秒时
   原先从 `run_official.py` 的 enable 线程抛出 `TimeoutExpired`，线程静默死亡，
   测试只能一直等 `setUpAll`。现在记录日志并返回空串，调用方按需重试。
2. **`_find_service_entry` 的前台判断与回顶**。服务详情页与列表页同属一个
   Settings 任务，`am start -a ACCESSIBILITY_SETTINGS` 只把任务带到前台
   （`Activity not started, its current task has been brought to the front`），
   因此必须 BACK 才能回到列表；但无条件 BACK 会落到被测应用上（一轮把它 ANR），
   在列表页 BACK 会退出无障碍设置。现在只在 **`com.android.settings` 且
   `SubSettings` 聚焦**时 BACK，并用 8 次短拖真正回到列表顶部。
3. **导航代次**（`_nav_generation` / `bump_navigation()`）。产品自己执行
   `home`/`recents` 时递增代次，在途的 `ensure_app_foreground` 立即放弃；
   没有它时残留的 `am start` 会在 `HOME` 之后把应用拉回前台（1 秒内实测），
   让 `recents` 用例与批准链路的「未批准前台」都看到本应用。
4. **隐私确认与通知权限**（`run_official.py`）。M34 首次启用会先弹一次性隐私
   确认（测试侧按 l10n 取按钮文案点击，不硬编码英文），随后产品请求
   `POST_NOTIFICATIONS`。宿主按约定**拒绝**它（保持 `granted=false`，异常套件
   需要该权限未授予），不 grant、不 revoke、不 clear。
   **因果边界**：`run_official.py` 的 `dismiss_notification_prompt()` 是 240 秒
   守护线程，只在 `permissioncontroller` 处于前台时动作（否则空转），因此理论上
   可能碰到无关的权限弹窗，本轮日志只有 1 次命中、未造成干扰。r10 的真实时序是
   Mods 断言（`00:40 +1`）**早于** `16:16:48` 的拒绝动作约 10 秒，所以「弹窗会
   挡住 `writeSelection`」只是**代码路径**（`phone_agent_privacy_notice.dart` 的
   `await _ensureNotificationPermission()`）支持的推断，**不由该轮日志证明**；
   该轮日志能证明的只有「弹窗真实出现并被拒绝、权限保持 `granted=false`」。

## 六处行为修正（都是宿主侧，产品未改）

这些是让 M30 拿到绿色轮次的实际修正。每一条都对应过一次真实失败；改的都是
脚本行为，**没有放宽任何测试断言或观察边界**。

1. **通知栏循环可取消，且检测到即停**（`open_shade` / `recover_from_shade` /
   `_shade_stop`）。旧的固定 13 秒 swipe 循环在测试打印
   `PHONE_AGENT_OVERLAY_HOST_TOUCH_RECOVER` 之后仍在继续滑，`keyevent 4` +
   `am start` 抵不过持续手势，通知栏被重新拉下；随后每次读树都
   `system_window_denied (com.android.systemui, hard_baseline)`，失败句只剩
   「最后前台包名：未知」。现在达到焦点即停、可被取消，恢复改用
   `cmd statusbar collapse`。

2. **恢复路径绝不发 BACK**（`recover_from_shade`）。旧实现无条件 `keyevent 4`；
   当通知栏已被 `cmd statusbar collapse` 关闭时，这一下落在 `MainActivity` 上把
   它 finish 掉，随后的 `am start` 建了新任务。任务重启之后产品有一段时间无法
   解析窗口类型，读树连续返回 `window_type_unknown`（可留存旁证：`run9` 该标识
   30 次，`run5` 为 0 次）。现在只用 `cmd statusbar collapse`。

3. **标记精确匹配**（`scan_line`）。只接受两种形状：整行等于标记，或行首是
   `标记:`。测试自己的失败文本里含标记名（`等待 ... 超时（标记
   PHONE_AGENT_RETURN_TO_APP）`），旧实现会在行内任意位置匹配，于是在测试仍在
   运行时误发一次 `am start`。

4. **`HOME` / `RECENTS` 等纯信息标记不进入有序动作队列**（`_NOOP`）。它们是产品
   自己执行的动作，标记只是通知宿主。旧实现把它排进 FIFO 队列占了一个时间槽，
   排在 `am start` 之后执行，反而把应用又踢回后台。

5. **重新启用不重开设置页**（`wait_for_binding`）。`PHONE_AGENT_ENABLE_SERVICE_NOW`
   时期望开关已经是打开状态，脚本只等绑定 + 确认前台，不再 `am start` 设置页。
   旧实现会在测试已经回到应用之后重新打开设置页并把它留在最上层，产品紧接着的
   调用就返回 `hard_baseline (com.android.settings)`。

6. **确认关闭后立即回应用**（`confirm_disable`）。点掉确认按钮后直接
   `am start` 主 Activity，不把设置页留在前台——否则产品下一次调用读到的前台
   仍是被硬基线拒绝的设置页。

另外两个较小但相关的处理：`enable_service` 结束后一律确认前台（应用被后台化会
被系统冻结，用例会静默卡住）；`_find_service_entry` 先把设置列表滚回顶部再逐屏
查找（列表会保留上次滚动位置，条目可能在视野外被误判为「不存在」）。

## 与产生绿轮的实跑版本的差异（交付版行为披露）

交付版脚本**不是**逐字节等于产生 `run17`–`run20` 的那一份；与实跑版相比有两处行为差异（其余为 docstring、`OUT_DIR` 与注释）：

| 位置 | 实跑版 | 交付版 | 影响 |
| --- | --- | --- | --- |
| `MARKERS["PHONE_AGENT_OVERLAY_ANIMATION"]` | `lambda: None`（会排进 FIFO 并执行，白占一个队列槽 + 两次 adb 查询） | `_NOOP` 信息标记（直接跳过队列） | 只减少空转，不改变任何断言；**未单独设备复跑** |
| `run_official.py` 的 flutter 可执行文件解析 | `FLUTTER_BIN` 或字面 `flutter.bat` | `FLUTTER_BIN` → `shutil.which("flutter")` → `flutter.bat` | 只影响查找顺序，不改变执行内容；**未单独设备复跑** |

两处都是无害或更保守的方向，但它们意味着「交付脚本原样复跑」与当时的实跑版本并非同一份。复现绿轮时若发现差异，先看这两处。

## 已知边界

- 脚本**不是阶段握手**：它按标记串行执行动作，但测试侧仍有固定等待
  （例如禁用确认前的 8 秒）。M31 survey 指出真正需要的是带 ACK 的阶段握手，
  本轮未实现（测试侧已先消除 `ENABLE_SERVICE_NOW` / `WAITING_FOR_SERVICE`
  的双触发，见下）。
- `confirm_disable()` 会自己 `am start` 回应用，属宿主动作，不是产品的系统导航。
- `open_permission_dialog()` 只用 `dumpsys window` 确认权限弹窗出现，作为宿主的
  独立确认；测试本身不声称能识别权限弹窗。
- **MIUI 例外**：只有 AGENTS.md 明确记录的物理设备（Redmi K30 5G，`1960cd68`）
  允许用 `settings put secure` 预配置服务，且必须保存并恢复**当轮真实原值**。
  该例外不改变产品自动授权边界，不适用于模拟器或其他设备。

## 与测试侧的对应关系

- 测试侧只保留一个「要求启用」的来源：`setUpAll` 的
  `PHONE_AGENT_WAITING_FOR_SERVICE`，服务重启用例使用
  `PHONE_AGENT_ENABLE_SERVICE_NOW` 并在之后改调不打印标记的 `_waitForReady`。
  因此本脚本的两条启用路径（导航 vs 只等绑定）不会并发。
- 测试侧刻意区分「可重试的观察边界拒绝」（`hard_baseline`、
  `window_type_system`/`overlay`/`split_divider`）与 `window_type_unknown`；
  后者表示窗口列表尚未稳定，不会被当作「稍后会好」而继续等待。
