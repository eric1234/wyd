import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/application/application.dart';
import 'package:wyd/src/domain/domain.dart';
import 'package:wyd/src/ui/settings/settings.dart';
import 'package:wyd/src/ui/wyd_app.dart';

void main() {
  testWidgets('renders settings and disabled unsupported controls', (
    tester,
  ) async {
    final controller = SettingsController(
      client: _FakeSettingsClient(snapshot: _snapshot()),
      onSaved: (_) async {},
    );
    await controller.open();

    await _pumpSettingsView(tester, controller);

    expect(find.text('Reminder interval'), findsOneWidget);
    expect(find.text('Autocomplete lookback'), findsOneWidget);
    expect(find.text('Unanswered timeout'), findsOneWidget);
    expect(find.text('Activity deferral'), findsOneWidget);
    expect(find.text('Allowed: 1-240'), findsNothing);
    expect(find.text('Unsupported on this platform'), findsNWidgets(2));
    expect(find.text('Save'), findsNothing);

    final reminderField = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Reminder interval'),
    );
    expect(reminderField.keyboardType, TextInputType.number);
    expect(
      reminderField.inputFormatters,
      contains(FilteringTextInputFormatter.digitsOnly),
    );
    expect(reminderField.decoration?.suffixText, 'min');

    final startAtLogin = tester.widget<SwitchListTile>(
      find.byType(SwitchListTile),
    );
    expect(startAtLogin.onChanged, isNull);
  });

  testWidgets(
    'shows validation only after commit and autosaves valid changes',
    (tester) async {
      final client = _FakeSettingsClient(snapshot: _snapshot());
      final controller = SettingsController(
        client: client,
        onSaved: (_) async {},
      );
      await controller.open();

      await _pumpSettingsView(tester, controller);
      await tester.enterText(
        find.widgetWithText(TextField, 'Reminder interval'),
        '0',
      );
      await tester.pump();

      expect(
        find.text('Reminder interval must be between 1 and 240.'),
        findsNothing,
      );

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(
        find.text('Reminder interval must be between 1 and 240.'),
        findsOneWidget,
      );
      expect(client.savedSettings, isEmpty);

      await tester.enterText(
        find.widgetWithText(TextField, 'Reminder interval'),
        '30',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(client.savedSettings.single.reminderIntervalMinutes, 30);
      expect(find.text('Settings saved.'), findsNothing);
    },
  );

  testWidgets('saves run on login switch immediately when supported', (
    tester,
  ) async {
    final client = _FakeSettingsClient(
      snapshot: _snapshot(
        capabilities: const PlatformCapabilities(supportsStartAtLogin: true),
      ),
    );
    final controller = SettingsController(
      client: client,
      onSaved: (_) async {},
    );
    await controller.open();

    await _pumpSettingsView(tester, controller);
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.pump();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();

    expect(client.savedSettings.single.startAtLogin, isTrue);
    expect(find.text('Run on Login'), findsOneWidget);
  });
}

Future<void> _pumpSettingsView(
  WidgetTester tester,
  SettingsController controller,
) {
  return tester.pumpWidget(
    MaterialApp(
      theme: buildWydTheme(),
      home: SettingsView(controller: controller),
    ),
  );
}

AppStateSnapshot _snapshot({
  AppSettings settings = AppSettings.defaults,
  PlatformCapabilities capabilities = const PlatformCapabilities(),
}) {
  return AppStateSnapshot(
    activeTask: null,
    runtimeState: RuntimeState(),
    settings: settings,
    capabilities: capabilities,
  );
}

final class _FakeSettingsClient implements SettingsClient {
  _FakeSettingsClient({required this.snapshot});

  AppStateSnapshot snapshot;
  final List<AppSettings> savedSettings = [];

  @override
  Future<AppStateSnapshot> loadSettingsSnapshot() async => snapshot;

  @override
  Future<AppStateSnapshot> saveSettings(AppSettings settings) async {
    savedSettings.add(settings);
    snapshot = snapshot.copyWith(settings: settings);
    return snapshot;
  }
}
