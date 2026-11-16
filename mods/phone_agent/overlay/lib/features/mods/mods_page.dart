import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/models/assistant.dart';
import '../../core/providers/assistant_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/ios_checkbox.dart';
import '../../shared/widgets/ios_settings_rows.dart';
import '../../shared/widgets/ios_tactile.dart';
import '../../shared/widgets/section_card.dart';
import '../../shared/widgets/snackbar.dart';
import '../../theme/app_font_weights.dart';
import '../home/services/local_tool_toggle.dart';
import '../home/services/local_tools_service.dart';
import '../phone_agent/phone_agent_approved_apps_page.dart';
import '../phone_agent/phone_agent_local_tool.dart';
import '../phone_agent/phone_agent_privacy_notice.dart';
import '../phone_agent/phone_agent_service.dart';

/// Opens the upstream phone control authorization flow for the assistant.
typedef NativePhoneControlRequest =
    Future<void> Function(BuildContext context, Assistant assistant);

/// Mobile Mods page: the shared body inside a normal settings scaffold.
class ModsPage extends StatelessWidget {
  const ModsPage({super.key, this.service, this.onRequestNativePhoneControl});

  final PhoneAgentService? service;
  final NativePhoneControlRequest? onRequestNativePhoneControl;

  static Future<void> open(BuildContext context) {
    return Navigator.of(
      context,
      rootNavigator: true,
    ).push<void>(MaterialPageRoute(builder: (_) => const ModsPage()));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(l10n.modsPageTitle),
        leading: IosIconButton(
          icon: LucideIcons.arrowLeft,
          color: cs.onSurface,
          size: 22,
          minSize: 44,
          semanticLabel: l10n.settingsPageBackButton,
          tooltip: l10n.settingsPageBackButton,
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: ModsView(
        service: service,
        onRequestNativePhoneControl: onRequestNativePhoneControl,
      ),
    );
  }
}

/// Desktop Mods pane: the same body without a nested scaffold.
class ModsPane extends StatelessWidget {
  const ModsPane({super.key, this.service, this.onRequestNativePhoneControl});

  final PhoneAgentService? service;
  final NativePhoneControlRequest? onRequestNativePhoneControl;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Text(
            l10n.modsPageTitle,
            style: TextStyle(
              fontSize: 20,
              fontWeight: AppFontWeights.semibold,
              color: cs.onSurface.withValues(alpha: 0.95),
            ),
          ),
        ),
        Expanded(
          child: ModsView(
            service: service,
            onRequestNativePhoneControl: onRequestNativePhoneControl,
          ),
        ),
      ],
    );
  }
}

/// Shared Mods body for phones and wide windows.
class ModsView extends StatefulWidget {
  const ModsView({super.key, this.service, this.onRequestNativePhoneControl});

  final PhoneAgentService? service;
  final NativePhoneControlRequest? onRequestNativePhoneControl;

  @override
  State<ModsView> createState() => _ModsViewState();
}

class _ModsViewState extends State<ModsView> with WidgetsBindingObserver {
  PhoneAgentAvailability? _status;
  bool _loading = true;
  bool _unavailable = false;
  int _request = 0;
  String? _selectedAssistantId;

  PhoneAgentService get _service =>
      widget.service ?? PhoneAgentService.instance;

  bool get _androidPlatform => PhoneAgentLocalTool.isAndroid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refresh({bool notify = false}) async {
    if (!mounted) return;
    final request = ++_request;
    if (!_androidPlatform) {
      setState(() {
        _status = null;
        _loading = false;
        _unavailable = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _unavailable = false;
    });
    try {
      final status = await _service.status();
      if (!mounted || request != _request) return;
      setState(() {
        _status = status;
        _loading = false;
        _unavailable = false;
      });
    } on PhoneAgentToolFailure {
      _markUnavailable(request, notify);
    } catch (_) {
      _markUnavailable(request, notify);
    }
  }

  void _markUnavailable(int request, bool notify) {
    if (!mounted || request != _request) return;
    setState(() {
      _status = null;
      _loading = false;
      _unavailable = true;
    });
    if (notify) {
      showAppSnackBar(
        context,
        message: AppLocalizations.of(context)!.phoneAgentStatusUnavailable,
        type: NotificationType.warning,
      );
    }
  }

  Future<void> _openAccessibilitySettings() async {
    try {
      await _service.openAccessibilitySettings();
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: AppLocalizations.of(context)!.phoneAgentSettingsUnavailable,
        type: NotificationType.warning,
      );
    }
  }

  Future<void> _selectMode(
    Assistant assistant,
    PhoneAgentControlSelection selection,
  ) async {
    final provider = context.read<AssistantProvider>();
    final current = provider.getById(assistant.id);
    if (current == null) return;
    if (selection == PhoneAgentControlSelection.native) {
      if (!_androidPlatform) return;
      // The upstream authorization flow owns the write: it removes
      // `phone_agent` only after the user grants access, so cancelling keeps
      // the previous selection untouched.
      if (!mounted) return;
      final request =
          widget.onRequestNativePhoneControl ?? _requestNativePhoneControl;
      await request(context, current);
      return;
    }
    if (selection == PhoneAgentControlSelection.phoneAgent &&
        !_androidPlatform) {
      return;
    }
    if (selection == PhoneAgentControlSelection.phoneAgent) {
      // 首次启用时一次性告知：截图与界面文字会作为工具结果发送给用户配置的
      // provider。取消则不写入选择；确认后照常写入。
      final acknowledged = await PhoneAgentPrivacyNotice.ensureAcknowledged(
        context,
        service: _service,
      );
      if (!acknowledged || !mounted) return;
    }
    await PhoneAgentLocalTool.writeSelection(
      provider,
      assistantId: assistant.id,
      selection: selection,
    );
  }

  Assistant? _resolveSelected(AssistantProvider provider) {
    final assistants = provider.assistants;
    if (assistants.isEmpty) return null;
    final selectedId = _selectedAssistantId;
    if (selectedId != null) {
      final match = provider.getById(selectedId);
      if (match != null) return match;
    }
    return provider.currentAssistant ?? assistants.first;
  }

  String _modeLabel(
    AppLocalizations l10n,
    PhoneAgentControlSelection selection,
  ) {
    switch (selection) {
      case PhoneAgentControlSelection.off:
        return l10n.phoneAgentControlOff;
      case PhoneAgentControlSelection.native:
        return l10n.phoneAgentControlNative;
      case PhoneAgentControlSelection.phoneAgent:
        return l10n.phoneAgentControlMod;
    }
  }

  String _statusText(AppLocalizations l10n) {
    if (!_androidPlatform) return l10n.phoneAgentUnsupportedPlatform;
    if (_loading) return l10n.phoneAgentStatusChecking;
    final status = _status;
    if (_unavailable || status == null) {
      return l10n.phoneAgentStatusUnavailable;
    }
    if (status.connected) return l10n.phoneAgentStatusReady;
    if (status.enabled) return l10n.phoneAgentStatusDisconnected;
    return l10n.phoneAgentStatusDisabled;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<AssistantProvider>();
    final assistants = provider.assistants;
    final selected = _resolveSelected(provider);
    final selection = selected == null
        ? null
        : PhoneAgentLocalTool.selectionFor(selected);
    final conflict =
        selected != null && PhoneAgentLocalTool.hasConflict(selected);
    final status = _status;
    final sdk = status?.androidSdkInt;
    final connected = status?.connected ?? false;
    final showScreenshotHint = sdk != null && sdk > 0 && sdk < 30;

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Text(
                l10n.phoneAgentTitle,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: AppFontWeights.semibold,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.phoneAgentSubtitle,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
              ),
              IosSectionHeader(
                text: l10n.phoneAgentAssistantSectionTitle,
                first: true,
              ),
              if (assistants.isEmpty)
                SectionCard(
                  children: [
                    IosNavRow(
                      icon: LucideIcons.bot,
                      label: l10n.phoneAgentNoAssistants,
                      subtitleMaxLines: null,
                    ),
                  ],
                )
              else
                SectionCard(
                  dividers: true,
                  children: [
                    for (final assistant in assistants)
                      IosNavRow(
                        icon: LucideIcons.bot,
                        label: assistant.name,
                        subtitle: _modeLabel(
                          l10n,
                          PhoneAgentLocalTool.selectionFor(assistant),
                        ),
                        trailing: assistant.id == selected?.id
                            ? Icon(
                                LucideIcons.circleCheck,
                                size: 20,
                                color: cs.primary,
                              )
                            : null,
                        onTap: () =>
                            setState(() => _selectedAssistantId = assistant.id),
                      ),
                  ],
                ),
              IosSectionHeader(text: l10n.phoneAgentControlLabel),
              SectionCard(
                children: [
                  if (conflict)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            LucideIcons.triangleAlert,
                            size: 20,
                            color: cs.error,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              l10n.phoneAgentConflict,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.45,
                                color: cs.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  _modeRow(
                    label: l10n.phoneAgentControlOff,
                    selected: selection == PhoneAgentControlSelection.off,
                    onTap: selected == null
                        ? null
                        : () => unawaited(
                            _selectMode(
                              selected,
                              PhoneAgentControlSelection.off,
                            ),
                          ),
                  ),
                  _modeRow(
                    label: l10n.phoneAgentControlNative,
                    selected: selection == PhoneAgentControlSelection.native,
                    subtitle: _androidPlatform
                        ? null
                        : l10n.phoneAgentUnsupportedPlatform,
                    onTap: selected == null || !_androidPlatform
                        ? null
                        : () => unawaited(
                            _selectMode(
                              selected,
                              PhoneAgentControlSelection.native,
                            ),
                          ),
                  ),
                  _modeRow(
                    label: l10n.phoneAgentControlMod,
                    selected:
                        selection == PhoneAgentControlSelection.phoneAgent,
                    subtitle: _androidPlatform
                        ? null
                        : l10n.phoneAgentUnsupportedPlatform,
                    onTap: selected == null || !_androidPlatform
                        ? null
                        : () => unawaited(
                            _selectMode(
                              selected,
                              PhoneAgentControlSelection.phoneAgent,
                            ),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SectionCard(
                children: [
                  IosNavRow(
                    icon: LucideIcons.accessibility,
                    label: l10n.phoneAgentTitle,
                    subtitle: _statusText(l10n),
                    subtitleMaxLines: null,
                    detailText: sdk == null ? null : 'API $sdk',
                    trailing: Icon(
                      connected ? LucideIcons.circleCheck : LucideIcons.circle,
                      size: 20,
                      color: connected ? cs.primary : cs.onSurfaceVariant,
                    ),
                  ),
                  IosNavRow(
                    icon: LucideIcons.refreshCw,
                    label: l10n.phoneAgentRefreshStatus,
                    onTap: () => unawaited(_refresh(notify: true)),
                  ),
                  IosNavRow(
                    icon: LucideIcons.settings,
                    label: l10n.phoneAgentOpenAccessibilitySettings,
                    onTap: _androidPlatform
                        ? () => unawaited(_openAccessibilitySettings())
                        : null,
                  ),
                ],
              ),
              if (showScreenshotHint)
                IosSectionFooter(text: l10n.phoneAgentScreenshotUnavailable),
              const SizedBox(height: 16),
              SectionCard(
                children: [
                  IosNavRow(
                    icon: LucideIcons.shieldCheck,
                    label: l10n.phoneAgentApprovedAppsTitle,
                    subtitle: l10n.phoneAgentApprovedAppsRowSubtitle,
                    subtitleMaxLines: null,
                    onTap: _androidPlatform
                        ? () => PhoneAgentApprovedAppsPage.open(context)
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SectionCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.phoneAgentDisclosureTitle,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.phoneAgentDisclosure,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeRow({
    required String label,
    required bool selected,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return IosNavRow(
      label: label,
      subtitle: subtitle,
      subtitleMaxLines: null,
      onTap: onTap,
      trailing: IosCheckbox(
        value: selected,
        onChanged: onTap == null ? null : (_) => onTap(),
      ),
    );
  }
}

Future<void> _requestNativePhoneControl(
  BuildContext context,
  Assistant assistant,
) {
  return setLocalToolEnabled(
    context,
    assistant: assistant,
    toolId: LocalToolNames.phoneControl,
    value: true,
  );
}
