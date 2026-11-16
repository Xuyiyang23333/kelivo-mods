import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kelivo_phone_agent/kelivo_phone_agent.dart';

import 'phone_agent_service.dart';

/// 一条批准请求的 UI 视图：把原生记录与它关联的工具调用拼在一起。
///
/// 只含应用身份（包名、签名前缀、可选显示名）与关联 id，**不含**节点文本、
/// 窗口标题、截图或界面内容。
@immutable
class PhoneAgentPendingApproval {
  const PhoneAgentPendingApproval({
    required this.request,
    required this.identity,
  });

  final PhoneAgentApprovalRequest request;
  final PhoneAgentPermissionIdentity identity;

  String get requestId => request.requestId;
  String get packageName => request.packageName;
  String? get signingPrefix => request.signingPrefix;
  String? get displayName => request.displayName;
  String? get toolCallId => request.toolCallId;
  String? get conversationId => request.conversationId;
}

/// 处理一条批准请求的结果。
///
/// 必须区分「写入失败」与「已批准但无法续跑」：把 `failed` 塌缩成“已批准”会让界面
/// 对用户说谎（原生可能返回 `signing_mismatch` / `signing_unavailable`）。
enum PhoneAgentResumeOutcome {
  /// 已批准并请求继续；调用方应重新观察后再继续。
  resumed,

  /// 已批准，但该任务已不可恢复（会话已切走、任务已取消或已完成）。
  approvalOnly,

  /// 用户拒绝。
  denied,

  /// 白名单**没有**写入：签名解析失败、签名已变化，或目标属构建期预批准条目。
  failed,
}

/// 续跑入口：由首页注册，调用方只需提供会话 id 与目标包名。
///
/// 注册方式与 `local_tool_toggle` 的注入一致：通用接缝不 import 具体业务 Mod，
/// 由 Mod 的补丁在首页注册一个回调。回调内部负责“发送一条已批准的用户消息”，
/// 让模型重新观察后继续；**不重放**被拒绝时的点击/输入/手势。
typedef PhoneAgentResumeHandler =
    Future<void> Function(String conversationId, String packageName);

/// 手机 Agent 的应用批准请求状态（plan 7.5.6/7.5.13）。
///
/// **与上游 `ToolApprovalService` 的关系**：复用它的模式（`ChangeNotifier` +
/// pending 列表 + `notifyListeners()` 驱动卡片刷新），**不复用它的等待语义**。
/// 工具调用在未批准时已经同步返回 `permission_required`，没有人在 await 一个
/// Future；因此这里的请求是独立状态记录，自带 TTL、单终态与显式清理。
///
/// 判定入口只有一个：[resolve] 经原生 `resolveApproval`，由 `ApprovalRequests`
/// 校验终态并（仅在 pending 时）写入白名单。聊天卡片、通知栏 action 与 Mods 页
/// 撤销因此共用同一份状态与同一份存储。
class PhoneAgentApprovalService extends ChangeNotifier {
  PhoneAgentApprovalService({
    PhoneAgentService? service,
    Duration sweepInterval = const Duration(seconds: 20),
  }) : _service = service ?? PhoneAgentService.instance {
    _sweepInterval = sweepInterval;
  }

  static final PhoneAgentApprovalService instance = PhoneAgentApprovalService();

  final PhoneAgentService _service;
  late final Duration _sweepInterval;

  final Map<String, PhoneAgentPendingApproval> _pending = <String, PhoneAgentPendingApproval>{};
  final Map<String, PhoneAgentPermissionIdentity> _identityByRequest =
      <String, PhoneAgentPermissionIdentity>{};

  Timer? _sweeper;
  bool _disposed = false;
  PhoneAgentResumeHandler? _resumeHandler;
  String? _foregroundConversationId;
  Future<void>? _refreshing;

  /// 注册「允许并继续」的续跑入口（由首页在启动时注入一次）。
  ///
  /// 卡片只负责批准并触发该回调；真正的续跑（发送一条“已批准，请重新观察再继续”
  /// 的用户消息）由注册方实现。回调为空时卡片退化为只保存授权并如实提示。
  void registerResumeHandler(PhoneAgentResumeHandler? handler) {
    _resumeHandler = handler;
  }

  bool get hasResumeHandler => _resumeHandler != null;

  /// 触发一次续跑（由聊天卡片调用）。没有注册入口时什么也不做，由调用方提示。
  Future<void> requestResume(String conversationId, String packageName) async {
    final handler = _resumeHandler;
    if (handler == null) return;
    await handler(conversationId, packageName);
  }

  /// 当前仍待处理的批准请求，按创建顺序。
  List<PhoneAgentPendingApproval> get pending =>
      List<PhoneAgentPendingApproval>.unmodifiable(_pending.values);

  bool get hasPending => _pending.isNotEmpty;

  /// 某个工具调用对应的待处理请求。聊天卡片据此决定是否渲染。
  PhoneAgentPendingApproval? pendingFor({
    required String toolCallId,
    String? conversationId,
  }) {
    if (toolCallId.isEmpty) return null;
    for (final entry in _pending.values) {
      if (entry.toolCallId != toolCallId) continue;
      if (conversationId != null &&
          entry.conversationId != null &&
          entry.conversationId != conversationId) {
        continue;
      }
      return entry;
    }
    return null;
  }

  /// 工具调用返回 `permission_required` 时登记一条请求。
  ///
  /// 身份来自工具结果的 `identity` 字段（原生解析），这里**只转交**，不重新判断。
  /// 同一 `(包名, 签名)` 的旧 pending 请求由原生置为 `superseded`。
  Future<PhoneAgentPendingApproval?> register(
    PhoneAgentPermissionIdentity identity, {
    String? toolCallId,
    String? conversationId,
    String? approvalAssistantId,
  }) async {
    if (!identity.signingAvailable) {
      // 解析不到签名时批准必然以 `signing_unavailable` 失败：不创建卡片，
      // 让模型按错误文案提示用户稍后重试。
      return null;
    }
    final request = await _service.requestApproval(
      identity.packageName,
      toolCallId: toolCallId,
      conversationId: conversationId,
      approvalAssistantId: approvalAssistantId,
    );
    return _adopt(request, identity);
  }

  /// 当前前台会话发生变化时调用（首页在切换会话时通知）。
  ///
  /// 只在**确实换了会话**时清理旧会话的 pending 请求；同一会话重复调用是无操作。
  /// 清理是本地行为，不写白名单、不通知模型（模型早已拿到 `permission_required`）。
  Future<void> onForegroundConversationChanged(String? conversationId) async {
    final next = conversationId?.trim();
    final previous = _foregroundConversationId;
    _foregroundConversationId = next;
    if (previous == null || previous == next) return;
    if (_pending.values.any((entry) => entry.conversationId == previous)) {
      await dismissForConversation(previous);
    }
  }

  /// 服务断连时清理全部 pending 请求（首页订阅服务状态时调用）。
  Future<void> onServiceDisconnected() async {
    if (_pending.isEmpty) return;
    await dismissAll();
  }

  /// 重新读取原生 pending 列表（应用回到前台、切换会话、服务状态变化时调用）。
  ///
  /// 这是「通知栏批准后聊天卡片随即消失」的实现点：通知 action 走原生
  /// `resolveApproval`，Dart 侧没有事件通道，因此回到前台/切会话时重新对齐。
  /// 并发调用合并成一次，避免重复通道往返。
  Future<void> refresh() async {
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight;
    final future = _refreshOnce();
    _refreshing = future;
    try {
      await future;
    } finally {
      if (identical(_refreshing, future)) _refreshing = null;
    }
  }

  Future<void> _refreshOnce() async {
    final List<PhoneAgentApprovalRequest> requests;
    try {
      requests = await _service.approvalRequests();
    } catch (_) {
      // 通道暂时不可用（服务重启中、插件缺失）：保留现有 pending，不清空。
      // 清空会让仍在等用户处理的卡片凭空消失；下次 refresh 会重新对齐。
      return;
    }
    final seen = <String>{};
    for (final request in requests) {
      if (!request.isPending) continue;
      seen.add(request.requestId);
      final identity =
          _identityByRequest[request.requestId] ??
          PhoneAgentPermissionIdentity(
            packageName: request.packageName,
            signingPrefix: request.signingPrefix,
            signingAvailable: request.signingAvailable,
            displayName: request.displayName,
            observation: false,
          );
      _identityByRequest[request.requestId] = identity;
      _pending[request.requestId] = PhoneAgentPendingApproval(
        request: request,
        identity: identity,
      );
    }
    for (final id in _pending.keys.toList()) {
      if (seen.contains(id)) continue;
      // 已不在原生 pending 里：通知栏批准/拒绝、TTL 过期或本地清理。
      _pending.remove(id);
      _identityByRequest.remove(id);
    }
    _ensureSweeper();
    _notify();
  }

  /// 批准或拒绝。**幂等**：请求已是终态时原生只返回既有状态，不写白名单。
  ///
  /// 返回值必须区分三种情况：拒绝 → [PhoneAgentResumeOutcome.denied]；原生没有写入
  /// 白名单（`signing_mismatch` / `signing_unavailable` / `pre_approved`）→
  /// [PhoneAgentResumeOutcome.failed]；写入成功 → 有续跑入口时 [resumed]，否则
  /// [approvalOnly]。**不得**把失败报成“已批准”。
  ///
  /// [resume] 为 true 表示「允许并继续」：返回 [resumed] 让调用方去续跑。续跑**由
  /// 聊天侧执行**（发送一条“已批准，请重新观察再继续”的用户消息），原生不会重放被
  /// 拒绝时的点击/输入/手势（plan 7.5.10）。
  ///
  /// 通知栏 action 只能表达“批准”，那里的批准 `resume` 恒为 false——用户处理完通知
  /// 只会看到授权已生效，需要模型重新观察。这是如实行为，不伪造续跑。
  Future<PhoneAgentResumeOutcome> resolve(
    String requestId, {
    required bool approve,
    bool resume = false,
  }) async {
    final resolved = await _service.resolveApproval(
      requestId: requestId,
      approve: approve,
    );
    _pending.remove(requestId);
    _identityByRequest.remove(requestId);
    final outcome = _outcomeFor(resolved, approve: approve, resume: resume);
    _notify();
    return outcome;
  }

  PhoneAgentResumeOutcome _outcomeFor(
    PhoneAgentApprovalRequest resolved, {
    required bool approve,
    required bool resume,
  }) {
    if (!approve) return PhoneAgentResumeOutcome.denied;
    if (resolved.state == 'failed') return PhoneAgentResumeOutcome.failed;
    if (!resolved.isApproved) {
      // 终态不是 approved 也不是 failed（例如请求已被取代或被清理）：批准没有生效，
      // 不能报成成功。
      return PhoneAgentResumeOutcome.failed;
    }
    if (resume && hasResumeHandler) return PhoneAgentResumeOutcome.resumed;
    return PhoneAgentResumeOutcome.approvalOnly;
  }

  /// 切换会话或应用重启时的本地清理：不写白名单、不通知模型。
  Future<void> dismissForConversation(String conversationId) async {
    if (conversationId.isEmpty) return;
    await _service.dismissApprovals(conversationId: conversationId);
    _pending.removeWhere((_, entry) => entry.conversationId == conversationId);
    _identityByRequest.removeWhere(
      (id, _) => !_pending.containsKey(id),
    );
    _ensureSweeper();
    _notify();
  }

  /// 服务断连时的清理。清理不等于拒绝，模型侧早已拿到 `permission_required`。
  Future<void> dismissAll() async {
    await _service.dismissApprovals();
    _pending.clear();
    _identityByRequest.clear();
    _ensureSweeper();
    _notify();
  }

  Future<void> revoke(String packageName) => _service.revokeApp(packageName);

  Future<List<PhoneAgentApprovedApp>> approvedApps() =>
      _service.approvedApps();

  PhoneAgentPendingApproval _adopt(
    PhoneAgentApprovalRequest request,
    PhoneAgentPermissionIdentity identity,
  ) {
    _identityByRequest[request.requestId] = identity;
    final entry = PhoneAgentPendingApproval(request: request, identity: identity);
    _pending[request.requestId] = entry;
    _ensureSweeper();
    _notify();
    return entry;
  }

  void _ensureSweeper() {
    if (_pending.isEmpty) {
      _sweeper?.cancel();
      _sweeper = null;
      return;
    }
    _sweeper ??= Timer.periodic(_sweepInterval, (_) => _sweep());
  }

  /// 本地 TTL 清扫：原生也会在读取时把到期请求置为 `expired`。这里只负责让卡片
  /// 在用户一直停留在聊天页时也能消失。
  Future<void> _sweep() async {
    if (_pending.isEmpty) {
      _ensureSweeper();
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final expired = _pending.values
        .where((entry) => entry.request.expiresAt <= now)
        .map((entry) => entry.requestId)
        .toList();
    if (expired.isEmpty) return;
    for (final id in expired) {
      _pending.remove(id);
      _identityByRequest.remove(id);
    }
    _ensureSweeper();
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sweeper?.cancel();
    _sweeper = null;
    super.dispose();
  }
}
