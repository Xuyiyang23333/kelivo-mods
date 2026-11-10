# 下一次会话交接：Phone Agent 节点输入修正

## 1. 新会话与仓库

请在 `V:/coding/kelivo-private` 新建会话，不要以 `V:/coding` 或 `V:/coding/kelivo` 作为 Tower 工作区。

- `V:/coding/kelivo` 是只读上游源码来源，不直接修改、不创建 Mod 工作分支。
- `V:/coding/kelivo-private` 是私有 Mod 工作区，包含 Loader、Phone Agent、中文文档与测试。
- 先阅读私有仓根目录 `AGENTS.md`。合成树位于 `.build/worktrees/`，不能手工修改其中源码来交付功能；契约变化先改中文文档，再改私有仓的 overlay/补丁，并通过 Loader 生成新合成树。
- 私有仓本地 Git email 已设置为 `xuyiyang23333@gmail.com`。此前没有执行提交或推送。
- 私有仓现有源码和文档必须完整保留；不要通过 reset、clean 或重新初始化覆盖它们。若启用 Tower，应让它接管现有私有仓，按其工具返回的结果处理未提交工作。

下一次会话可直接使用：

> 继续 Phone Agent 的 API 35 联调。先阅读 `AGENTS.md` 和 `docs/next-session-handoff.md`，处理聚焦后 `set_text` 返回 `stale_handle` 的问题，补测试并进行 API 35 / API 29 回归。遵守文档中的私有 Mod 边界，不修改上游。

## 2. 当前目标与阶段

第一阶段 Mod Loader 已完成。第二阶段 Phone Agent 的主要功能已完成，但仍处于设备联调阶段，不能宣称全部验收完成。

当前优先任务不是重做 Loader、Mods 页面或模拟器，而是：

1. 修正节点聚焦后输入被过度判为失效的问题。
2. 跑通 API 35 模拟器的完整 `integration_test/phone_agent_test.dart`。
3. 回归 API 29 真机，确保原有点击、输入、节点滚动不退化。
4. 再补 VLM 图片链路、真实固定任务及其他异常路径验证。

首版输入仍只开放给测试包名 `com.psyche.kelivo.phoneagent`。不要在本任务中扩大白名单、引入自动无障碍授权，或把发送/购买/删除确认描述成原生硬护栏。

## 3. 已有实现与交付基线

- 上游基线：`73afa4ec77cfc9af2efea2487fee8bba1362639d`。
- 当前 Mod 版本：`0.2.0`。
- 当前完整 modset：`4ed083cf5fe7dda8eec575588594831d9515cbd88429cb6f5b893c9ca6544331`。
- 当前合成树：`V:/coding/kelivo-private/.build/worktrees/4ed083cf5fe7dda8`。
- 三个工具：`phone_agent_screenshot`、`phone_agent_tree`、`phone_agent_input`。
- 每助手独立 `localToolId='phone_agent'`；Mods 页提供关闭/原生手机控制/Phone Agent 三态单选，已有助手不自动迁移。
- 两个无障碍服务可共存，Mods 页只显示独立 `PhoneAgentService` 的真实状态，正常 UI 只约束工具选择。
- 观察按需发生，不强制每步重新读取完整树。没有 `snapshot_id` 暴露在工具 schema 中。
- `supported` 只表示 API 30+ 截图能力；API 29 仍可 ready 并使用树/节点输入。

此前已经通过的检查不要无目的重跑：

- Flutter 相关测试共 255 项：254 通过，1 项 Windows 符号链接条件跳过；Phone Agent 103、Mods 16、设置入口 2。
- 插件 Dart 17、插件 Kotlin 55、上游 `PhoneControlServiceTest` 49、Loader 165。
- 根项目、markstream、插件和 Loader 静态分析通过；最终 Loader verify 通过。
- 23 个 ARB key 已同步，ko/ru/tr/zh_Hant 均 `0 pending`。
- API 29 真机官方测试退出码 0，覆盖 Mods 选择、真实状态、读树、节点点击、`set_text`、节点滚动、二次读树；截图按预期返回 `unsupported_os`。

上述是修正前的验收记录。若修改节点校验，需要重新运行受影响测试，不得沿用旧结果冒充新实现通过。

## 4. 已确认的问题与最小修正方向

API 35 最新测试已真正执行到工具调用，结果如下：

- 首次截图通过，返回真实图片与有效屏幕尺寸。
- 节点点击通过，测试回调计数为 1。
- 点击输入框成功，但随后 `set_text` 返回 `stale_handle`：`The target node changed. Call phone_agent_tree with offset 0.`。
- 测试因此在 `integration_test/phone_agent_test.dart` 的文本输入断言处失败；坐标滑动尚未执行到。
- 第二个“Mods 页真实服务状态与 Phone Agent 选择”场景通过。

已定位到代码层面的直接原因：

- `mods/phone_agent/plugin/android/src/main/kotlin/com/kelivo/phoneagent/PhoneNode.kt` 的 `fingerprint()` 包含 `isFocused` 和 `isSelected`。
- `ObservationRegistry.kt` 的 `handle()` 调用 `refresh()` 后比较指纹；点击输入框使焦点状态变化，于是拒绝后续输入。
- 当前错误来自指纹变化，不是节点点击没有生效。

建议先明确中文契约：允许同一节点的临时焦点变化，同时继续拒绝真正的节点替换、内容/能力异常变化及窗口变化。至少为 focus-only 变化添加单元测试；是否处理 selected-only 应由语义和测试决定，不要一次性放宽全部指纹检查。

必须保留并回归：

- `refresh()` 失败、不可见、禁用、未知句柄的拒绝。
- 内容变化、能力变化、密码节点限制。
- 包名、窗口、尺寸、旋转及 120 秒 TTL 校验。
- 动作后不强制清空树句柄；只有截图观测按现有规则清除。
- 不要求每次动作后自动读树，避免重新引入快照膨胀。

关键实现：

- `PhoneNode.kt`：节点抽象与指纹。
- `ObservationRegistry.kt`：树/截图观测、句柄及 TTL。
- `NodeActionExecutor.kt`：节点动作与输入白名单。
- `plugin/android/src/test/kotlin/com/kelivo/phoneagent/ObservationRegistryTest.kt`：失效测试。
- `mods/phone_agent/overlay/integration_test/phone_agent_test.dart`：设备闭环。

如果改变契约，先同步 `AGENTS.md`、`docs/phone-agent-plan.md`、`mods/phone_agent/README.md`，再改实现和测试。本任务不需要新 UI 文案，因此通常不需要改 ARB。

## 5. Android Studio、模拟器与设备状态

已通过 Android Studio Device Manager 创建：

- AVD：`Kelivo_Phone_Agent_API_35`，显示名为 `Kelivo Phone Agent API 35`。
- Pixel 9a、Android 15、API 35、Google Play x86_64 镜像。
- ADB 设备 ID 当时为 `emulator-5554`，内部屏幕为 `1080x2424`。
- WHPX 硬件加速可用。
- Android Studio 已打开上述合成工程，但 Flutter 命令行测试仍是当前标准验收方式。

Windows 模拟器窗口大于屏幕只是宿主显示问题，不改变 Android 内部截图、无障碍树或归一化坐标。拖小窗口即可，无需修改 AVD 或产品代码。

为避免安装 Android Studio 后自动选用 JDK 25 导致 Gradle 8.14 构建失败，Flutter 已全局配置使用本机 JDK 17：

```bash
flutter config --jdk-dir="C:/Users/David/scoop/apps/openjdk17/current"
```

不要恢复为 JDK 25。`flutter doctor -v` 已确认使用 JDK 17。

Sharp SG803SH / API 29 的 ADB ID 当时为 `357784090209204`。执行任何安装、授权或测试前都用 `adb devices -l` 重新确认设备，命令必须带 `-s`，避免误操作另一台设备。

### 无障碍授权注意事项

- 仅向 `enabled_accessibility_services` 写入组件名不足以保证 Android 15 真正启用服务。
- 在模拟器系统无障碍设置中选择 **Kelivo Phone Agent**，通过系统对话框授权；不要启用 **Kelivo phone control**。
- 服务组件精确值为 `com.psyche.kelivo.phoneagent/com.kelivo.phoneagent.PhoneAgentService`。
- 安装/重装测试包以及测试结束可能撤销授权。应等最新测试包启动后，再在系统界面启用服务，并及时返回测试应用。
- 若测试输出 `PHONE_AGENT_WAITING_FOR_SERVICE`，先检查 `settings get secure enabled_accessibility_services` 和 `dumpsys accessibility` 的真实状态，不要仅看界面开关。
- 不要把测试环境中的这些人工授权步骤变成产品的自动授权功能。

API 35 模拟器命令示例：

```bash
flutter test --no-uninstall integration_test/phone_agent_test.dart -d emulator-5554
```

API 29 回归命令示例：

```bash
flutter test --no-uninstall integration_test/phone_agent_test.dart -d 357784090209204
```

## 6. 验证顺序与后续交付

1. 中文文档与最小单元测试先行，再修改原生实现。
2. 运行插件 Kotlin 测试，并针对焦点变化、内容变化和失效边界检查覆盖情况。
3. 通过 Loader 合成新树，执行 Loader 自身的格式、分析、测试及 verify；不要手工编辑已有合成树源码作为交付。
4. 在新合成树运行相关 Flutter 测试、静态分析和插件测试。
5. 完成 API 35 全量 Phone Agent 集成测试，再回归 API 29。
6. 验证此前被阻塞的坐标滑动、二次读树，并视进度补旋转/切窗/禁用服务/超时。
7. 另起明确的小任务验证真实 VLM 图片链路和固定场景。当前 `llama-cpp/llama-cpp` 是否支持图片、是否真正降低快照数量均尚未验证。
8. 更新中文验收记录，重建并重新计算产品 debug APK 哈希。

当前合成树里的 APK 已被集成测试构建覆盖，是测试 kernel 版本，不是此前记录的产品 APK。旧大小 `181354638` 字节和旧 SHA-256 `af67f4285bef9e3d1093c6433f42669a8c84b8bee99b6397f68dfd91e1c60ceb` 只能作为历史记录，不能用于当前文件。若交付产品包，必须在最终树上重新构建并复核。

仍未完成或不能宣称完成：完整 API 35 工具闭环、坐标手势、VLM 固定任务与图片链路、真实 `FLAG_SECURE`、完整异常路径、签名 release。上游仓保持只读；不向上游提交或推送私有实现。
