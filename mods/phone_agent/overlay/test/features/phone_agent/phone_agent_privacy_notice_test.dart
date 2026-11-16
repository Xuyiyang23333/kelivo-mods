import 'package:Kelivo/features/phone_agent/phone_agent_privacy_notice.dart';
import 'package:Kelivo/features/phone_agent/phone_agent_service.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'phone_agent_test_support.dart';

/// 方案 B：只在首次启用时提示一次；取消不写状态；文案如实说明是告知不是技术控制。
void main() {
  late RecordingPhoneAgentClient client;
  late PhoneAgentService service;

  setUp(() {
    client = RecordingPhoneAgentClient();
    service = PhoneAgentService(client: client);
  });

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => PhoneAgentPrivacyNotice.ensureAcknowledged(
                  context,
                  service: service,
                ),
                child: const Text('enable'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the notice once and records acknowledgement', (
    tester,
  ) async {
    await pumpHost(tester);
    await tester.tap(find.text('enable'));
    await tester.pumpAndSettle();

    expect(find.text('Before you enable Phone Agent'), findsOneWidget);
    // 文案必须写明“告知不是技术控制”，不能暗示内容不外发。
    final body = tester.widget<Text>(
      find.textContaining('It is information, not a technical control'),
    );
    expect(body.data, contains('does not mean screen content stays'));

    await tester.tap(find.text('I understand'));
    await tester.pumpAndSettle();

    expect(client.privacyAcknowledged, isTrue);
    expect(client.acknowledgeCalls, 1);
  });

  testWidgets('cancelling writes no state so the notice returns', (
    tester,
  ) async {
    await pumpHost(tester);
    await tester.tap(find.text('enable'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(client.acknowledgeCalls, 0);
    expect(client.privacyAcknowledged, isFalse);

    await tester.tap(find.text('enable'));
    await tester.pumpAndSettle();
    expect(find.text('Before you enable Phone Agent'), findsOneWidget);
  });

  testWidgets('an already acknowledged user sees no dialog', (tester) async {
    client.privacyAcknowledged = true;

    await pumpHost(tester);
    await tester.tap(find.text('enable'));
    await tester.pumpAndSettle();

    expect(find.text('Before you enable Phone Agent'), findsNothing);
    expect(client.acknowledgeCalls, 0);
  });
}
