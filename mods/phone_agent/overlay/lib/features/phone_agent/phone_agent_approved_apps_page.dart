import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kelivo_phone_agent/kelivo_phone_agent.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/providers/assistant_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/ios_settings_rows.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/snackbar.dart';
import '../phone_agent/phone_agent_service.dart';

/// 已批准应用的白名单管理页（plan 7.5.5 第 2 项 / 7.5.6）。
///
/// 显示包名、签名前缀、批准时间、最后批准时间与来源助手，并按**来源助手分组**
/// （白名单全局共享，分组的用途是让用户看见跨助手越权）。
///
/// 撤销立即生效：下一次判定重新读原生存储，不需要重建观测；但撤销**不撤回**已发出的
/// 动作，也不清理已建立的树观测（`offset > 0` 分页在 TTL 内仍回放旧树，见 plan 7.5.4）。
class PhoneAgentApprovedAppsPage extends StatefulWidget {
  const PhoneAgentApprovedAppsPage({super.key, this.service});

  final PhoneAgentService? service;

  static Future<void> open(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(builder: (_) => const PhoneAgentApprovedAppsPage()),
    );
  }

  @override
  State<PhoneAgentApprovedAppsPage> createState() =>
      _PhoneAgentApprovedAppsPageState();
}

class _PhoneAgentApprovedAppsPageState
    extends State<PhoneAgentApprovedAppsPage> {
  List<PhoneAgentApprovedApp>? _apps;
  bool _loading = true;
  bool _unavailable = false;
  int _request = 0;
  String? _revoking;

  PhoneAgentService get _service =>
      widget.service ?? PhoneAgentService.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final request = ++_request;
    setState(() => _loading = true);
    try {
      final apps = await _service.approvedApps();
      if (!mounted || request != _request) return;
      setState(() {
        _apps = apps;
        _loading = false;
        _unavailable = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _apps = null;
        _loading = false;
        _unavailable = true;
      });
    }
  }

  Future<void> _revoke(PhoneAgentApprovedApp app) async {
    if (_revoking != null) return;
    setState(() => _revoking = app.packageName);
    final l10n = AppLocalizations.of(context);
    try {
      await _service.revokeApp(app.packageName);
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n?.phoneAgentApprovedAppRevoked(app.packageName) ?? '',
      );
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n?.phoneAgentApprovedAppRevokeFailed ?? '',
        type: NotificationType.warning,
      );
    } finally {
      if (mounted) setState(() => _revoking = null);
      await _refresh();
    }
  }

  /// 按来源助手分组；没有来源时归入“未知来源”一组。
  Map<String?, List<PhoneAgentApprovedApp>> _grouped(
    List<PhoneAgentApprovedApp> apps,
  ) {
    final groups = <String?, List<PhoneAgentApprovedApp>>{};
    for (final app in apps) {
      groups.putIfAbsent(app.sourceAssistantId, () => []).add(app);
    }
    return groups;
  }

  String _groupLabel(
    AppLocalizations l10n,
    String? assistantId,
    AssistantProvider? assistants,
  ) {
    if (assistantId == null) return l10n.phoneAgentApprovedAppUnknownSource;
    final name = assistants?.getById(assistantId)?.name;
    return name ?? assistantId;
  }

  String _timestamp(AppLocalizations l10n, int millis) {
    if (millis <= 0) return l10n.phoneAgentApprovedAppNever;
    final date = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final apps = _apps;
    final assistants = context.watch<AssistantProvider?>();
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(l10n.phoneAgentApprovedAppsTitle),
        actions: [
          IconButton(
            tooltip: l10n.phoneAgentRefreshStatus,
            icon: const Icon(LucideIcons.refreshCw, size: 20),
            onPressed: _loading ? null : () => unawaited(_refresh()),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: _buildBody(context, l10n, apps, assistants),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    List<PhoneAgentApprovedApp>? apps,
    AssistantProvider? assistants,
  ) {
    if (_loading && apps == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_unavailable) {
      return _Message(
        icon: LucideIcons.triangleAlert,
        title: l10n.phoneAgentApprovedAppsUnavailable,
        body: l10n.phoneAgentApprovedAppsUnavailableBody,
        action: TextButton(
          onPressed: () => unawaited(_refresh()),
          child: Text(l10n.phoneAgentRefreshStatus),
        ),
      );
    }
    if (apps == null || apps.isEmpty) {
      return _Message(
        icon: LucideIcons.shieldCheck,
        title: l10n.phoneAgentApprovedAppsEmpty,
        body: l10n.phoneAgentApprovedAppsEmptyBody,
      );
    }
    final groups = _grouped(apps);
    final entries = groups.entries.toList()
      ..sort((a, b) => (a.key ?? '').compareTo(b.key ?? ''));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text(
          l10n.phoneAgentApprovedAppsHint,
          style: TextStyle(
            fontSize: 13,
            height: 1.45,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        for (final group in entries) ...[
          IosSectionHeader(text: _groupLabel(l10n, group.key, assistants)),
          SectionCard(
            dividers: true,
            children: [
              for (final app in group.value)
                _ApprovedAppRow(
                  app: app,
                  approvedAt: _timestamp(l10n, app.approvedAt),
                  lastApprovedAt: _timestamp(l10n, app.lastApprovedAt),
                  revoking: _revoking == app.packageName,
                  onRevoke: _revoking == null
                      ? () => unawaited(_revoke(app))
                      : null,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ApprovedAppRow extends StatelessWidget {
  const _ApprovedAppRow({
    required this.app,
    required this.approvedAt,
    required this.lastApprovedAt,
    required this.revoking,
    this.onRevoke,
  });

  final PhoneAgentApprovedApp app;
  final String approvedAt;
  final String lastApprovedAt;
  final bool revoking;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.packageName,
                  style: TextStyle(fontSize: 13, color: cs.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.phoneAgentApprovedAppSigning(app.signingPrefix),
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.phoneAgentApprovedAppApprovedAt(approvedAt),
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
                Text(
                  l10n.phoneAgentApprovedAppLastUsedAt(lastApprovedAt),
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (revoking)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: onRevoke,
              child: Text(l10n.phoneAgentApprovedAppRevoke),
            ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: cs.onSurface),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: cs.onSurfaceVariant,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}
