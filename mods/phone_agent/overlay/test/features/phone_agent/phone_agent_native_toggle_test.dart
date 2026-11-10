import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/features/home/services/local_tool_toggle.dart';
import 'package:Kelivo/features/home/services/local_tools_service.dart';
import 'package:Kelivo/features/phone_agent/phone_agent_local_tool.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

import '../../support/business_test_harness.dart';

const _channel = MethodChannel('app.device_tools');

Widget _app(Widget home) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    messenger.setMockMethodCallHandler(
      _channel,
      (_) async => <String, bool>{'enabled': false, 'connected': false},
    );
  });

  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  Future<(AssistantProvider, String)> createProvider(
    List<String> localToolIds,
  ) async {
    final provider = AssistantProvider(
      preferences: createBusinessTestPreferences(),
    );
    addTearDown(provider.dispose);
    await provider.loaded;
    final id = await provider.addAssistant(name: 'Original');
    await provider.updateAssistant(
      provider.getById(id)!.copyWith(localToolIds: localToolIds),
    );
    return (provider, id);
  }

  Future<void> pumpToggle(
    WidgetTester tester,
    AssistantProvider provider, {
    required Assistant Function() assistant,
    required String toolId,
  }) {
    return tester.pumpWidget(
      ChangeNotifierProvider<AssistantProvider>.value(
        value: provider,
        child: _app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => setLocalToolEnabled(
                  context,
                  assistant: assistant(),
                  toolId: toolId,
                  value: true,
                ),
                child: const Text('Enable'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'cancelling native authorization keeps the stored ids unchanged',
    (tester) async {
      final (provider, id) = await createProvider(<String>[
        PhoneAgentLocalTool.id,
        LocalToolNames.phoneControl,
      ]);
      await pumpToggle(
        tester,
        provider,
        assistant: () => provider.getById(id)!,
        toolId: LocalToolNames.phoneControl,
      );

      await tester.tap(find.text('Enable'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(provider.getById(id)!.localToolIds, <String>[
        PhoneAgentLocalTool.id,
        LocalToolNames.phoneControl,
      ]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'authorizing native control keeps edits and removes phone_agent',
    (tester) async {
      final (provider, id) = await createProvider(<String>[
        PhoneAgentLocalTool.id,
      ]);
      await pumpToggle(
        tester,
        provider,
        assistant: () => provider.getById(id)!,
        toolId: LocalToolNames.phoneControl,
      );

      await tester.tap(find.text('Enable'));
      await tester.pumpAndSettle();
      await provider.updateAssistant(
        provider
            .getById(id)!
            .copyWith(
              name: 'Updated',
              localToolIds: <String>[
                PhoneAgentLocalTool.id,
                LocalToolNames.calculate,
              ],
            ),
      );
      final allow = find.text('Allow this assistant to use phone control');
      await tester.scrollUntilVisible(allow, 250);
      await tester.pumpAndSettle();
      await tester.tap(allow);
      await tester.pumpAndSettle();

      final latest = provider.getById(id)!;
      expect(latest.name, 'Updated');
      expect(latest.localToolIds, contains(LocalToolNames.calculate));
      expect(latest.localToolIds, isNot(contains(PhoneAgentLocalTool.id)));
      expect(latest.localToolIds, contains(LocalToolNames.phoneControl));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('ordinary local tool write re-reads the latest assistant', (
    tester,
  ) async {
    final (provider, id) = await createProvider(const <String>[]);
    final stale = provider.getById(id)!;
    await pumpToggle(
      tester,
      provider,
      assistant: () => stale,
      toolId: LocalToolNames.calculate,
    );
    await provider.updateAssistant(
      provider
          .getById(id)!
          .copyWith(localToolIds: <String>[PhoneAgentLocalTool.id]),
    );

    await tester.tap(find.text('Enable'));
    await tester.pumpAndSettle();

    final latest = provider.getById(id)!;
    expect(
      latest.localToolIds,
      containsAll(<String>[PhoneAgentLocalTool.id, LocalToolNames.calculate]),
    );
  });
}
