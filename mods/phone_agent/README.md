# Phone Agent Mod

本目录是 Kelivo 的 `phone_agent` 编译前源码 Mod，通过 Mod Loader 合成到固定上游基线，提供独立、低摩擦的 Android 手机控制能力，不修改上游 `PhoneControlService`。

- 上游基线：`73afa4ec77cfc9af2efea2487fee8bba1362639d`
- 插件包名：`kelivo_phone_agent`
- MethodChannel：`kelivo/phone_agent`
- 助手级工具 ID：`phone_agent`

## 工具能力

通过 [phone_agent_tools.dart](overlay/lib/features/phone_agent/phone_agent_tools.dart) 暴露三个工具：

- `phone_agent_screenshot`（视觉模型可用，API 30+）：整屏截图，长边缩放到不超过 1600，自动涂黑密码节点区域。
- `phone_agent_tree`：有界无障碍节点树（支持分页 `offset` 与 `interactive_only`），自动过滤密码节点及其子树。
- `phone_agent_input`：
  - 节点动作：`tap`、`long_press`、`set_text`、`scroll`
  - 坐标手势（所有模型可用，归一化 `[0, 1]`，无需前置截图、不因动作消费清空）：`tap`、`long_press`、`swipe`
  - 系统与辅助动作：`back`、`home`、`recents`、`wait`（`duration_ms` 100..5000，默认 1000）
  - 应用控制：`list_apps`（枚举可启动第三方应用，排除自身宿主包）、`open_app`（通过 `package_name` 直接启动应用）

## 目录与补丁

- `patches/pubspec.patch`：在上游 `pubspec.yaml` 中加入 `kelivo_phone_agent` path 依赖。
- `patches/application-id.patch`：将私有测试构建包名设为 `com.psyche.kelivo.phoneagent`、应用名设为 `Kelivo Agent`。
- `patches/local-tool-mutual-exclusion.patch`：保证助手的 `phone_control` 与 `phone_agent` 互斥。
- `patches/settings-entry.patch`：在设置页增加 Mods 入口。
- `patches/l10n-source.patch` / `patches/l10n-generated.patch`：Mods 页文案与多语言生成文件。
- `overlay/`：Kelivo 侧 Mod 注册、工具定义、Mods 设置页及测试。
- `plugin/`：独立 `kelivo_phone_agent` Flutter 插件及 Android 原生实现。

## 实用安全边界

- **密码保护**：读树跳过 `password` 节点及其子树，禁止对密码节点执行 `performNodeAction`，截图前对全屏可见密码节点区域涂黑。
- **敏感系统入口保护**：`HARD_BASELINE_PACKAGES`（系统设置、权限控制器、包安装器、证书安装器、`systemui`、承载包 `com.psyche.kelivo`）禁止观察、输入与 `open_app`；默认电话/短信应用禁止输入；输入操作仅允许 `TYPE_APPLICATION` 窗口。
- **第三方普通应用零门槛**：不再逐应用拦截审批或要求签名白名单，任何已安装的第三方应用（含桌面 Launcher）均可直接观察、启动与操作。
- **前台可视化反馈**：通过独立 `TYPE_ACCESSIBILITY_OVERLAY`（`FLAG_NOT_TOUCHABLE | FLAG_NOT_FOCUSABLE`）在读树、点击、滑动、截图时给出轻量图形反馈，截图前自动隐藏。

## 合成与使用

```bash
cd V:/coding/kelivo-private
dart tool/mod_loader.dart plan
dart tool/mod_loader.dart apply
dart tool/mod_loader.dart verify
```

然后在 `.build/worktrees/<hash16>/` 中运行 `flutter pub get` 与 `flutter build apk --debug`（或 `flutter test`）。安装后在 Kelivo「设置 → Mods」中为助手启用 `Phone Agent`，并在 Android 系统无障碍设置中开启 `Kelivo Phone Agent` 服务。
