import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_font_weights.dart';
import 'phone_agent_approval_service.dart';

/// 聊天内批准卡片（plan 7.5.6）。
///
/// 上游接缝只有一处：`chat_message_widget.dart` 在工具结果摘要位置插入本组件。
/// 卡片**只显示应用身份**（包名、签名证书 SHA-256 前 8 位、可选显示名），
/// 不显示节点文本、窗口标题、截图或界面内容——那些正是尚未获批时最不该出现的东西。
///
/// 与工具调用结果的关系：工具调用早已返回 `permission_required` 并结束，本卡片是
/// **独立状态记录**的视图，不是 await 中的 Future。因此它有 TTL，任一端处理完即消失。
///
/// 自身监听 [PhoneAgentApprovalService.instance]，因此不需要在上游 provider 树里注册：
/// 没有待处理请求时渲染 `SizedBox.shrink()`，不会占位。
///
/// 「允许并继续」只触发 [onResume]：恢复由聊天侧发送一条“已批准，请重新观察再继续”
/// 的用户消息，**不重放**被拒绝时的点击/输入/手势（plan 7.5.10）。
class PhoneAgentApprovalCard extends StatelessWidget {
  const PhoneAgentApprovalCard({
    super.key,
    required this.toolCallId,
    required this.conversationId,
  });

  final String toolCallId;
  final String? conversationId;

  /// 该工具调用是否还有待处理请求。
  ///
  /// 上游用它决定是否为工具步骤分配内容区（`content`）：只依赖 `showToolResultSummary`
  /// 或图片会让卡片在默认设置下永不渲染（默认关闭摘要、`permission_required` 无图片）。
  static bool pendingExists({
    required String toolCallId,
    String? conversationId,
  }) {
    return PhoneAgentApprovalService.instance.pendingFor(
          toolCallId: toolCallId,
          conversationId: conversationId,
        ) !=
        null;
  }

  /// pending 状态变化时通知上游重建（通知栏批准后卡片要立即消失）。
  static Listenable get listenable => PhoneAgentApprovalService.instance;

  @override
  Widget build(BuildContext context) {
    final service = PhoneAgentApprovalService.instance;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final approval = service.pendingFor(
          toolCallId: toolCallId,
          conversationId: conversationId,
        );
        if (approval == null) return const SizedBox.shrink();
        return _PhoneAgentApprovalBody(
          approval: approval,
          canResume: service.hasResumeHandler,
        );
      },
    );
  }
}

class _PhoneAgentApprovalBody extends StatefulWidget {
  const _PhoneAgentApprovalBody({
    required this.approval,
    required this.canResume,
  });

  final PhoneAgentPendingApproval approval;
  final bool canResume;

  @override
  State<_PhoneAgentApprovalBody> createState() => _PhoneAgentApprovalBodyState();
}

class _PhoneAgentApprovalBodyState extends State<_PhoneAgentApprovalBody> {
  bool _busy = false;

  Future<void> _resolve({required bool approve, required bool resume}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final entry = widget.approval;
    try {
      final outcome = await PhoneAgentApprovalService.instance.resolve(
        entry.requestId,
        approve: approve,
        resume: resume,
      );
      if (!approve) {
        _toast(messenger, l10n?.phoneAgentApprovalDenied);
        return;
      }
      if (outcome == PhoneAgentResumeOutcome.resumed) {
        final conversationId = entry.conversationId;
        final handler = PhoneAgentApprovalService.instance;
        if (conversationId != null && handler.hasResumeHandler) {
          _toast(messenger, l10n?.phoneAgentApprovalResumed);
          await _resume(conversationId, entry.packageName);
          return;
        }
        // 没有续跑入口（例如通知栏批准后回到聊天）：只保存了授权，如实提示需要
        // 重新观察，不假装任务已经继续。
        _toast(messenger, l10n?.phoneAgentApprovalResumeUnavailable);
        return;
      }
      _toast(messenger, l10n?.phoneAgentApprovalApproved);
    } catch (_) {
      _toast(messenger, l10n?.phoneAgentApprovalFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resume(String conversationId, String packageName) async {
    if (!mounted) return;
    final service = PhoneAgentApprovalService.instance;
    if (!service.hasResumeHandler) return;
    await service.requestResume(conversationId, packageName);
  }

  void _toast(ScaffoldMessengerState? messenger, String? message) {
    if (messenger == null || message == null) return;
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    if (l10n == null) return const SizedBox.shrink();
    final entry = widget.approval;
    final prefix = entry.signingPrefix;
    final signing = prefix == null
        ? l10n.phoneAgentApprovalSigningUnavailable
        : l10n.phoneAgentApprovalSigning(prefix);
    final title = entry.displayName == null
        ? l10n.phoneAgentApprovalCardTitle
        : l10n.phoneAgentApprovalCardTitleNamed(entry.displayName!);
    final canResume = widget.canResume && entry.conversationId != null;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: AppFontWeights.semibold,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            entry.packageName,
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: cs.onSurfaceVariant,
            ),
          ),
          Text(
            signing,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.phoneAgentApprovalCardBody,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            alignment: WrapAlignment.end,
            children: [
              TextButton(
                onPressed: _busy
                    ? null
                    : () => unawaited(_resolve(approve: false, resume: false)),
                child: Text(l10n.phoneAgentApprovalDeny),
              ),
              if (canResume)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => unawaited(_resolve(approve: true, resume: true)),
                  child: Text(l10n.phoneAgentApprovalAllowAndContinue),
                ),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => unawaited(_resolve(approve: true, resume: false)),
                child: Text(l10n.phoneAgentApprovalAllow),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
