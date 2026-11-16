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
  ///
  /// [assistantId] / [conversationId] 只用于原生侧审计元数据，拿不到时传 null。
  Future<PhoneAgentScreenshot> screenshot({
    String? assistantId,
    String? conversationId,
  }) => _client.screenshot(
    assistantId: assistantId,
    conversationId: conversationId,
  );

  /// 清空原生侧最近一次截图坐标观测。
  ///
  /// 截图落盘或尺寸校验失败时由适配层调用，避免继续使用未保存图片的坐标。
  Future<void> clearScreenshot() => _client.clearScreenshot();

  /// 读取当前窗口节点。`offset == 0` 创建新观测并重新编号。
  ///
  /// [assistantId] / [conversationId] 只用于原生侧审计元数据，拿不到时传 null。
  Future<Map<String, dynamic>> readTree({
    int offset = 0,
    int maxNodes = 120,
    bool interactiveOnly = false,
    String? assistantId,
    String? conversationId,
  }) => _client.readTree(
    offset: offset,
    maxNodes: maxNodes,
    interactiveOnly: interactiveOnly,
    assistantId: assistantId,
    conversationId: conversationId,
  );

  /// 执行节点、坐标或系统输入。参数使用工具 schema 的 snake_case 键。
  ///
  /// [assistantId] / [conversationId] 只用于原生侧审计元数据，拿不到时传 null。
  Future<Map<String, dynamic>> input(
    Map<String, dynamic> arguments, {
    String? assistantId,
    String? conversationId,
  }) => _client.input(
    arguments,
    assistantId: assistantId,
    conversationId: conversationId,
  );

  /// 已获用户批准的应用列表（不含构建配置的预批准条目）。
  Future<List<PhoneAgentApprovedApp>> approvedApps() => _client.approvedApps();

  /// 写入一条批准记录（幂等）。写入前原生侧会重新解析当前签名。
  Future<PhoneAgentApprovedApp> approveApp(
    String packageName, {
    String? sourceAssistantId,
    List<String>? expectedSigningSha256,
  }) => _client.approveApp(
    packageName,
    sourceAssistantId: sourceAssistantId,
    expectedSigningSha256: expectedSigningSha256,
  );

  /// 撤销一条批准记录。立即生效；已发出的动作不受影响。
  Future<void> revokeApp(String packageName) => _client.revokeApp(packageName);

  /// 创建一条待用户处理的批准请求（同时发通知）。
  Future<PhoneAgentApprovalRequest> requestApproval(
    String packageName, {
    String? toolCallId,
    String? conversationId,
    String? approvalAssistantId,
  }) => _client.requestApproval(
    packageName,
    toolCallId: toolCallId,
    conversationId: conversationId,
    approvalAssistantId: approvalAssistantId,
  );

  /// 当前仍待处理的批准请求。
  Future<List<PhoneAgentApprovalRequest>> approvalRequests() =>
      _client.approvalRequests();

  /// 处理一条批准请求。幂等；请求已不存在时抛 `approval_not_found`。
  Future<PhoneAgentApprovalRequest> resolveApproval({
    required String requestId,
    required bool approve,
  }) => _client.resolveApproval(requestId: requestId, approve: approve);

  /// 清理待处理请求（切换会话或应用重启）。
  Future<void> dismissApprovals({String? conversationId}) =>
      _client.dismissApprovals(conversationId: conversationId);

  /// 首次启用隐私确认是否已读（方案 B）。
  Future<bool> privacyNoticeAcknowledged() =>
      _client.privacyNoticeAcknowledged();

  /// 记录用户已读首次启用隐私确认。只是告知记录，不改变任何判定。
  Future<void> acknowledgePrivacyNotice() =>
      _client.acknowledgePrivacyNotice();
}
