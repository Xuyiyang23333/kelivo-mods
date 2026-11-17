import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/home/services/local_tools_service.dart';
import 'package:Kelivo/features/mods/mods_page.dart';
import 'package:Kelivo/features/phone_agent/phone_agent_local_tool.dart';
import 'package:Kelivo/features/phone_agent/phone_agent_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/ios_checkbox.dart';
import 'package:Kelivo/shared/widgets/snackbar.dart';

import '../../support/business_test_harness.dart';

class _FakePhoneAgentClient implements PhoneAgentClient {
  PhoneAgentAvailability availability = const PhoneAgentAvailability(
    supported: true,
    enabled: true,
    connected: true,
    androidSdkInt: 33,
  );
  Object? statusError;
  Object? settingsError;
  int statusCalls = 0;
  int settingsCalls = 0;

  @override
  Future<PhoneAgentAvailability> status() async {
    statusCalls++;
    final error = statusError;
    if (error != null) throw error;
    return availability;
  }

  @override
  Future<void> openAccessibilitySettings() async {
    settingsCalls++;
    final error = settingsError;
    if (error != null) throw error;
  }

  @override
  Future<PhoneAgentCapture> screenshot() => throw UnimplementedError();

  @override
  Future<void> clearScreenshot() => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> readTree({
    int offset = 0,
    int maxNodes = 120,
    bool interactiveOnly = false,
  }) => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> input(Map<String, dynamic> arguments) =>
      throw UnimplementedError();
}

void main() {
  late AssistantProvider provider;
  late SettingsProvider settings;

  setUp(() async {
    final preferences = createBusinessTestPreferences();
    settings = SettingsProvider(preferences);
    await settings.loaded;
    addTearDown(settings.dispose);
  });

  Future<AssistantProvider> createProvider(
    List<Assistant> assistants, {
    String currentId = 'a',
  }) async {
    final preferences = createBusinessTestPreferences();
    await preferences.load();
    await preferences.setString(
      'assistants_v1',
      Assistant.encodeList(assistants),
    );
    await preferences.setString('current_assistant_id_v1', currentId);
    final created = AssistantProvider(preferences: preferences);
    await created.loaded;
    addTearDown(created.dispose);
    return created;
  }

  Future<AppLocalizations> pumpMods(
    WidgetTester tester, {
    required PhoneAgentService service,
    NativePhoneControlRequest? onNative,
    Widget? page,
    Size size = const Size(400, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AssistantProvider>.value(value: provider),
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AppSnackBarOverlay(
            child:
                page ??
                ModsPage(
                  service: service,
                  onRequestNativePhoneControl: onNative,
                ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return AppLocalizations.of(tester.element(find.byType(ModsView)))!;
  }

  bool checkboxValue(WidgetTester tester, int index) =>
      tester.widget<IosCheckbox>(find.byType(IosCheckbox).at(index)).value;

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('shows the service status and Android API level', (tester) async {
    provider = await createProvider([const Assistant(id: 'a', name: 'Alpha')]);
    final client = _FakePhoneAgentClient();
    final l10n = await pumpMods(
      tester,
      service: PhoneAgentService(client: client),
    );

    expect(find.text(l10n.phoneAgentStatusReady), findsOneWidget);
    expect(find.text('API 33'), findsOneWidget);
    expect(find.text(l10n.phoneAgentConflict), findsNothing);
    expect(client.statusCalls, 1);
  });

  testWidgets(
    'API 29 keeps the connected status and adds the screenshot hint',
    (tester) async {
      provider = await createProvider([
        const Assistant(id: 'a', name: 'Alpha'),
      ]);
      final client = _FakePhoneAgentClient()
        ..availability = const PhoneAgentAvailability(
          supported: false,
          enabled: true,
          connected: true,
          androidSdkInt: 29,
        );
      final l10n = await pumpMods(
        tester,
        service: PhoneAgentService(client: client),
      );

      expect(find.text(l10n.phoneAgentStatusReady), findsOneWidget);
      expect(find.text(l10n.phoneAgentScreenshotUnavailable), findsOneWidget);
      expect(find.text('API 29'), findsOneWidget);
      expect(find.text(l10n.phoneAgentUnsupportedPlatform), findsNothing);
    },
  );

  testWidgets('supported only gates screenshots, not the service status', (
    tester,
  ) async {
    provider = await createProvider([const Assistant(id: 'a', name: 'Alpha')]);
    final client = _FakePhoneAgentClient()
      ..availability = const PhoneAgentAvailability(
        supported: false,
        enabled: false,
        connected: false,
        androidSdkInt: 33,
      );
    final l10n = await pumpMods(
      tester,
      service: PhoneAgentService(client: client),
    );

    expect(find.text(l10n.phoneAgentStatusDisabled), findsOneWidget);
    expect(find.text(l10n.phoneAgentUnsupportedPlatform), findsNothing);
    expect(find.text(l10n.phoneAgentScreenshotUnavailable), findsNothing);
    expect(find.text('API 33'), findsOneWidget);
  });

  testWidgets('refresh re-reads the service status', (tester) async {
    provider = await createProvider([const Assistant(id: 'a', name: 'Alpha')]);
    final client = _FakePhoneAgentClient()
      ..availability = const PhoneAgentAvailability(
        supported: true,
        enabled: false,
        connected: false,
        androidSdkInt: 31,
      );
    final l10n = await pumpMods(
      tester,
      service: PhoneAgentService(client: client),
    );
    expect(find.text(l10n.phoneAgentStatusDisabled), findsOneWidget);

    client.availability = const PhoneAgentAvailability(
      supported: true,
      enabled: true,
      connected: true,
      androidSdkInt: 31,
    );
    await tester.tap(find.text(l10n.phoneAgentRefreshStatus));
    await tester.pumpAndSettle();

    expect(find.text(l10n.phoneAgentStatusReady), findsOneWidget);
    expect(client.statusCalls, 2);
  });

  testWidgets('resuming the app refreshes the service status', (tester) async {
    provider = await createProvider([const Assistant(id: 'a', name: 'Alpha')]);
    final client = _FakePhoneAgentClient()
      ..availability = const PhoneAgentAvailability(
        supported: true,
        enabled: false,
        connected: false,
        androidSdkInt: 31,
      );
    final l10n = await pumpMods(
      tester,
      service: PhoneAgentService(client: client),
    );
    expect(find.text(l10n.phoneAgentStatusDisabled), findsOneWidget);

    client.availability = const PhoneAgentAvailability(
      supported: true,
      enabled: true,
      connected: true,
      androidSdkInt: 31,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text(l10n.phoneAgentStatusReady), findsOneWidget);
    expect(client.statusCalls, 2);
  });

  testWidgets('a status failure shows the unavailable state', (tester) async {
    provider = await createProvider([const Assistant(id: 'a', name: 'Alpha')]);
    final client = _FakePhoneAgentClient()
      ..statusError = const PhoneAgentToolFailure(
        'plugin_unavailable',
        'missing',
      );
    final l10n = await pumpMods(
      tester,
      service: PhoneAgentService(client: client),
    );

    expect(find.text(l10n.phoneAgentStatusUnavailable), findsOneWidget);
    expect(find.text(l10n.phoneAgentStatusReady), findsNothing);
  });

  testWidgets('a generic status failure also shows the unavailable state', (
    tester,
  ) async {
    provider = await createProvider([const Assistant(id: 'a', name: 'Alpha')]);
    final client = _FakePhoneAgentClient()..statusError = StateError('boom');
    final l10n = await pumpMods(
      tester,
      service: PhoneAgentService(client: client),
    );

    expect(find.text(l10n.phoneAgentStatusUnavailable), findsOneWidget);
  });

  testWidgets('opening accessibility settings failure shows a snackbar', (
    tester,
  ) async {
    provider = await createProvider([const Assistant(id: 'a', name: 'Alpha')]);
    final client = _FakePhoneAgentClient()
      ..settingsError = const PhoneAgentToolFailure(
        'plugin_unavailable',
        'missing',
      );
    final l10n = await pumpMods(
      tester,
      service: PhoneAgentService(client: client),
    );

    await tester.tap(find.text(l10n.phoneAgentOpenAccessibilitySettings));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(client.settingsCalls, 1);
    expect(
      find.descendant(
        of: find.byType(NotificationWidget),
        matching: find.text(l10n.phoneAgentSettingsUnavailable),
      ),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('off and Phone Agent write mutually exclusive tool ids', (
    tester,
  ) async {
    provider = await createProvider([const Assistant(id: 'a', name: 'Alpha')]);
    final client = _FakePhoneAgentClient();
    final nativeRequests = <String>[];
    await pumpMods(
      tester,
      service: PhoneAgentService(client: client),
      onNative: (context, assistant) async => nativeRequests.add(assistant.id),
    );

    expect(checkboxValue(tester, 0), isTrue);

    await tester.tap(find.byType(IosCheckbox).at(2));
    await tester.pumpAndSettle();
    expect(provider.getById('a')!.localToolIds, [PhoneAgentLocalTool.id]);

    await tester.tap(find.byType(IosCheckbox).at(0));
    await tester.pumpAndSettle();
    expect(provider.getById('a')!.localToolIds, isEmpty);
    expect(nativeRequests, isEmpty);
  });

  testWidgets(
    'native selection forwards the latest assistant without writing',
    (tester) async {
      provider = await createProvider([
        const Assistant(
          id: 'a',
          name: 'Alpha',
          localToolIds: [PhoneAgentLocalTool.id, LocalToolNames.phoneControl],
        ),
      ]);
      final client = _FakePhoneAgentClient();
      final nativeRequests = <List<String>>[];
      await pumpMods(
        tester,
        service: PhoneAgentService(client: client),
        onNative: (context, assistant) async =>
            nativeRequests.add(assistant.localToolIds),
      );

      await tester.tap(find.byType(IosCheckbox).at(1));
      await tester.pumpAndSettle();

      expect(nativeRequests, hasLength(1));
      expect(nativeRequests.single, contains(PhoneAgentLocalTool.id));
      expect(nativeRequests.single, contains(LocalToolNames.phoneControl));

      // Cancelling the upstream authorization page must not change the ids.
      final ids = provider.getById('a')!.localToolIds;
      expect(ids, contains(PhoneAgentLocalTool.id));
      expect(ids, contains(LocalToolNames.phoneControl));
    },
  );

  testWidgets('native authorization success leaves only native phone control', (
    tester,
  ) async {
    provider = await createProvider([
      const Assistant(
        id: 'a',
        name: 'Alpha',
        localToolIds: [PhoneAgentLocalTool.id, LocalToolNames.phoneControl],
      ),
    ]);
    final client = _FakePhoneAgentClient();
    final nativeRequests = <List<String>>[];
    await pumpMods(
      tester,
      service: PhoneAgentService(client: client),
      onNative: (context, assistant) async {
        nativeRequests.add(assistant.localToolIds);
        await PhoneAgentLocalTool.writeSelection(
          provider,
          assistantId: assistant.id,
          selection: PhoneAgentControlSelection.native,
        );
      },
    );

    await tester.tap(find.byType(IosCheckbox).at(1));
    await tester.pumpAndSettle();

    expect(nativeRequests.single, contains(PhoneAgentLocalTool.id));
    final ids = provider.getById('a')!.localToolIds;
    expect(ids, contains(LocalToolNames.phoneControl));
    expect(ids, isNot(contains(PhoneAgentLocalTool.id)));
  });

  testWidgets('conflicting ids show a conflict notice until reselected', (
    tester,
  ) async {
    provider = await createProvider([
      const Assistant(
        id: 'a',
        name: 'Alpha',
        localToolIds: [PhoneAgentLocalTool.id, LocalToolNames.phoneControl],
      ),
    ]);
    final client = _FakePhoneAgentClient();
    final l10n = await pumpMods(
      tester,
      service: PhoneAgentService(client: client),
    );

    expect(find.text(l10n.phoneAgentConflict), findsOneWidget);

    await tester.tap(find.byType(IosCheckbox).at(0));
    await tester.pumpAndSettle();

    expect(provider.getById('a')!.localToolIds, isEmpty);
    expect(find.text(l10n.phoneAgentConflict), findsNothing);
  });

  testWidgets('switching assistants reads that assistant selection', (
    tester,
  ) async {
    provider = await createProvider([
      const Assistant(id: 'a', name: 'Alpha'),
      const Assistant(
        id: 'b',
        name: 'Beta',
        localToolIds: [LocalToolNames.phoneControl],
      ),
    ]);
    final client = _FakePhoneAgentClient();
    await pumpMods(tester, service: PhoneAgentService(client: client));

    expect(checkboxValue(tester, 0), isTrue);

    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();
    expect(checkboxValue(tester, 1), isTrue);

    await tester.tap(find.byType(IosCheckbox).at(2));
    await tester.pumpAndSettle();

    expect(provider.getById('b')!.localToolIds, [PhoneAgentLocalTool.id]);
    expect(provider.getById('a')!.localToolIds, isEmpty);
  });

  testWidgets('non-Android disables native and Phone Agent selection', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      provider = await createProvider([
        const Assistant(
          id: 'a',
          name: 'Alpha',
          localToolIds: [LocalToolNames.phoneControl],
        ),
      ]);
      final client = _FakePhoneAgentClient();
      final nativeRequests = <String>[];
      final l10n = await pumpMods(
        tester,
        service: PhoneAgentService(client: client),
        onNative: (context, assistant) async =>
            nativeRequests.add(assistant.id),
      );

      expect(find.text(l10n.phoneAgentUnsupportedPlatform), findsNWidgets(3));
      expect(client.statusCalls, 0);

      await tester.tap(find.byType(IosCheckbox).at(1));
      await tester.pumpAndSettle();
      expect(nativeRequests, isEmpty);
      expect(provider.getById('a')!.localToolIds, [
        LocalToolNames.phoneControl,
      ]);

      await tester.tap(find.byType(IosCheckbox).at(2));
      await tester.pumpAndSettle();
      expect(provider.getById('a')!.localToolIds, [
        LocalToolNames.phoneControl,
      ]);

      await tester.tap(find.byType(IosCheckbox).at(0));
      await tester.pumpAndSettle();
      expect(provider.getById('a')!.localToolIds, isEmpty);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('ModsPage renders a scaffold and ModsPane does not', (
    tester,
  ) async {
    provider = await createProvider([const Assistant(id: 'a', name: 'Alpha')]);
    final client = _FakePhoneAgentClient();
    final service = PhoneAgentService(client: client);

    final l10n = await pumpMods(tester, service: service);
    expect(find.byType(Scaffold), findsOneWidget);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AssistantProvider>.value(value: provider),
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Material(
            child: ModsPane(service: PhoneAgentService(client: client)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Scaffold), findsNothing);
    expect(find.text(l10n.modsPageTitle), findsOneWidget);
    expect(find.byType(ModsView), findsOneWidget);
  });

  testWidgets('ModsView keeps a 640 max width on wide windows', (tester) async {
    provider = await createProvider([const Assistant(id: 'a', name: 'Alpha')]);
    final client = _FakePhoneAgentClient();
    await pumpMods(
      tester,
      service: PhoneAgentService(client: client),
      page: Material(
        child: ModsPane(service: PhoneAgentService(client: client)),
      ),
      size: const Size(1200, 800),
    );

    final constrained = find
        .descendant(
          of: find.byType(ModsView),
          matching: find.byType(ConstrainedBox),
        )
        .first;
    expect(tester.getSize(constrained).width, 640);
  });
}
