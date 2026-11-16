import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'phone_agent_service.dart';

/// 首次启用隐私确认（方案 B，用户拍板；plan 7.5.14）。
///
/// 只在**首次启用** Phone Agent 时一次性提示：截图与界面文字会作为工具结果发送给
/// 用户自己配置的 provider，可能包含聊天记录、消息列表等界面内容。
///
/// 明确的口径：
/// - **只在首次提示**，不每张截图询问、不在每次任务前重复。
/// - 它是**告知**，不是技术控制：不阻止用户随后批准任何应用，也不改变
///   `PackagePolicy` 的任何判定；不构成“数据不会外发”的承诺——恰恰相反，它说明会
///   发生什么。
/// - provider 更换是否重新提示**未定稿**（plan 7.5.14），因此这里只在从未确认过时
///   提示，不跟踪 provider。
class PhoneAgentPrivacyNotice {
  const PhoneAgentPrivacyNotice._();

  /// 如果用户从未确认过，弹出一次性提示。
  ///
  /// 返回 true 表示已经确认（此前确认过，或本次确认）。取消/关闭对话框不写状态，
  /// 下次启用时会再次提示——**不静默放行**。写状态失败也不放行，由调用方决定是否
  /// 继续选择；提示本身从不阻断工具选择。
  static Future<bool> ensureAcknowledged(
    BuildContext context, {
    PhoneAgentService? service,
  }) async {
    final resolved = service ?? PhoneAgentService.instance;
    var acknowledged = false;
    try {
      acknowledged = await resolved.privacyNoticeAcknowledged();
    } catch (_) {
      // 读不到状态时按“未确认”处理（fail closed 到提示，而不是跳过告知）。
      acknowledged = false;
    }
    if (acknowledged) return true;
    if (!context.mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext)!;
        return AlertDialog(
          title: Text(l10n.phoneAgentPrivacyNoticeTitle),
          content: Text(l10n.phoneAgentPrivacyNoticeBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.phoneAgentPrivacyNoticeCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.phoneAgentPrivacyNoticeConfirm),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return false;
    try {
      await resolved.acknowledgePrivacyNotice();
    } catch (_) {
      // 记录失败时不重试、不阻断选择：提示已经显示过，如实告知的目标已达成。
    }
    return true;
  }
}
