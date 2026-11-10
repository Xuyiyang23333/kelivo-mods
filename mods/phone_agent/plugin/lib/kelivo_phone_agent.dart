import 'src/phone_agent_client.dart';
import 'src/phone_agent_types.dart';

export 'src/phone_agent_types.dart';

/// 独立手机 Agent 插件的公开入口。
///
/// 该插件只负责原生能力，不依赖 `package:Kelivo/...`。Kelivo 适配层负责
/// 工具 schema、助手开关、图片落盘和错误文本。
class KelivoPhoneAgent {
  KelivoPhoneAgent._({PhoneAgentClient? client})
    : _client = client ?? PhoneAgentClient();

  static final KelivoPhoneAgent instance = KelivoPhoneAgent._();

  final PhoneAgentClient _client;

  /// 读取独立无障碍服务的启用和连接状态。
  Future<PhoneAgentStatus> status() => _client.status();

  /// 打开系统无障碍设置页，由用户手动启用独立服务。
  Future<void> openAccessibilitySettings() =>
      _client.openAccessibilitySettings();

  /// 截取当前屏幕。仅 Android API 30+ 可用。
  Future<PhoneAgentScreenshot> screenshot() => _client.screenshot();

  /// 清空原生侧最近一次截图坐标观测。
  ///
  /// 截图落盘或尺寸校验失败时由适配层调用，避免继续使用未保存图片的坐标。
  Future<void> clearScreenshot() => _client.clearScreenshot();

  /// 读取当前窗口节点。`offset == 0` 创建新观测并重新编号。
  Future<Map<String, dynamic>> readTree({
    int offset = 0,
    int maxNodes = 120,
    bool interactiveOnly = false,
  }) => _client.readTree(
    offset: offset,
    maxNodes: maxNodes,
    interactiveOnly: interactiveOnly,
  );

  /// 执行节点、坐标或系统输入。参数使用工具 schema 的 snake_case 键。
  Future<Map<String, dynamic>> input(Map<String, dynamic> arguments) =>
      _client.input(arguments);
}
