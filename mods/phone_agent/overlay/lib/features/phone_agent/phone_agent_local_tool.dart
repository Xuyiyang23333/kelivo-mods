import 'package:flutter/foundation.dart';

import '../../core/models/assistant.dart';
import '../../core/providers/assistant_provider.dart';
import '../home/services/local_tools_service.dart';

/// Which phone-control tool set an assistant uses.
enum PhoneAgentControlSelection { off, native, phoneAgent }

/// Assistant-level selection for the independent phone agent local tool.
///
/// [id] and the native `phone_control` tool are mutually exclusive in the
/// normal UI. Reading prefers [id] when both ids are present so the mod and the
/// Mods page agree on the active tool set until the user reselects.
class PhoneAgentLocalTool {
  const PhoneAgentLocalTool._();

  static const String id = 'phone_agent';

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static PhoneAgentControlSelection selectionForIds(
    Iterable<String> localToolIds,
  ) {
    final ids = localToolIds.toSet();
    if (ids.contains(id)) return PhoneAgentControlSelection.phoneAgent;
    if (ids.contains(LocalToolNames.phoneControl)) {
      return PhoneAgentControlSelection.native;
    }
    return PhoneAgentControlSelection.off;
  }

  static PhoneAgentControlSelection selectionFor(Assistant? assistant) =>
      selectionForIds(assistant?.localToolIds ?? const <String>[]);

  /// True when both ids are stored, for example after manual editing or the
  /// upstream local tools page. The Mods page asks the user to reselect.
  static bool hasConflict(Assistant? assistant) {
    final ids = assistant?.localToolIds ?? const <String>[];
    return ids.contains(id) && ids.contains(LocalToolNames.phoneControl);
  }

  /// Pure mapping from the current ids to the ids [selection] requires.
  ///
  /// Unrelated tool ids are preserved; the two phone-control ids are never
  /// returned together.
  static List<String> applySelection(
    Iterable<String> localToolIds,
    PhoneAgentControlSelection selection,
  ) {
    final ids = <String>{
      for (final toolId in localToolIds)
        if (toolId != id && toolId != LocalToolNames.phoneControl) toolId,
    };
    switch (selection) {
      case PhoneAgentControlSelection.off:
        break;
      case PhoneAgentControlSelection.native:
        ids.add(LocalToolNames.phoneControl);
        break;
      case PhoneAgentControlSelection.phoneAgent:
        ids.add(id);
        break;
    }
    return ids.toList(growable: false);
  }

  /// Writes [selection] for [assistantId] after re-reading the latest assistant.
  ///
  /// Only the id is trusted, so an edit made while the Mods page was open is
  /// not overwritten by a stale snapshot. Returns whether anything was written.
  static Future<bool> writeSelection(
    AssistantProvider provider, {
    required String assistantId,
    required PhoneAgentControlSelection selection,
  }) async {
    final current = provider.getById(assistantId);
    if (current == null) return false;
    final ids = applySelection(current.localToolIds, selection);
    if (setEquals(ids.toSet(), current.localToolIds.toSet())) return false;
    await provider.updateAssistant(current.copyWith(localToolIds: ids));
    return true;
  }
}
