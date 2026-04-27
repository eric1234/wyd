import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/application/application.dart';
import 'package:wyd/src/domain/domain.dart';
import 'package:wyd/src/ui/settings/settings.dart';

void main() {
  group('SettingsController', () {
    test('loads settings from client', () async {
      final client = _FakeSettingsClient(
        snapshot: _snapshot(
          settings: const AppSettings(reminderIntervalMinutes: 25),
        ),
      );
      final controller = _controller(client);

      await controller.open();

      expect(controller.state.reminderIntervalMinutes, '25');
      expect(controller.state.autocompleteLookbackDays, '3');
      expect(controller.state.loading, isFalse);
    });

    test('reports parse errors before saving', () async {
      final client = _FakeSettingsClient(snapshot: _snapshot());
      final controller = _controller(client);
      await controller.open();

      controller.updateReminderInterval('abc');
      await controller.commitChanges();

      expect(client.savedSettings, isEmpty);
      expect(
        controller.state.messageFor(SettingsField.reminderIntervalMinutes),
        'Reminder interval must be a whole number.',
      );
    });

    test('reports cross-field validation errors', () async {
      final client = _FakeSettingsClient(snapshot: _snapshot());
      final controller = _controller(client);
      await controller.open();

      controller.updateReminderInterval('5');
      controller.updateResponseTimeout('10');
      await controller.commitChanges();

      expect(client.savedSettings, isEmpty);
      expect(
        controller.state.messageFor(SettingsField.reminderIntervalMinutes),
        'Reminder interval must be greater than or equal to timeout.',
      );
    });

    test('saves valid settings and invokes callback', () async {
      AppStateSnapshot? savedSnapshot;
      final client = _FakeSettingsClient(snapshot: _snapshot());
      final controller = _controller(
        client,
        onSaved: (snapshot) async => savedSnapshot = snapshot,
      );
      await controller.open();

      controller.updateReminderInterval('30');
      await controller.commitChanges();

      expect(client.savedSettings.single.reminderIntervalMinutes, 30);
      expect(controller.state.saved, isTrue);
      expect(savedSnapshot, isNotNull);
    });

    test('commits valid draft when closed', () async {
      final client = _FakeSettingsClient(snapshot: _snapshot());
      final controller = _controller(client);
      await controller.open();

      controller.updateReminderInterval('30');
      await controller.close();

      expect(client.savedSettings.single.reminderIntervalMinutes, 30);
      expect(controller.state.isOpen, isFalse);
    });

    test('ignores start-at-login toggle when unsupported', () async {
      final client = _FakeSettingsClient(snapshot: _snapshot());
      final controller = _controller(client);
      await controller.open();

      await controller.updateStartAtLogin(true);

      expect(controller.state.startAtLogin, isFalse);
      expect(client.savedSettings, isEmpty);
    });

    test('saves supported start-at-login toggle immediately', () async {
      final client = _FakeSettingsClient(
        snapshot: _snapshot(
          capabilities: const PlatformCapabilities(supportsStartAtLogin: true),
        ),
      );
      final controller = _controller(client);
      await controller.open();

      await controller.updateStartAtLogin(true);

      expect(client.savedSettings.single.startAtLogin, isTrue);
      expect(controller.state.startAtLogin, isTrue);
    });

    test('queues a newer committed draft while saving', () async {
      final client = _FakeSettingsClient(
        snapshot: _snapshot(),
        delaySaves: true,
      );
      final controller = _controller(client);
      await controller.open();

      controller.updateReminderInterval('30');
      final firstCommit = controller.commitChanges();
      await _waitForSaveCompleters(client, 1);

      controller.updateReminderInterval('45');
      final secondCommit = controller.commitChanges();
      client.saveCompleters[0].complete();
      await _waitForSaveCompleters(client, 2);
      client.saveCompleters[1].complete();
      await Future.wait([firstCommit, secondCommit]);

      expect(
        client.savedSettings.map(
          (settings) => settings.reminderIntervalMinutes,
        ),
        [30, 45],
      );
      expect(controller.state.reminderIntervalMinutes, '45');
      expect(controller.state.saving, isFalse);
    });
  });
}

SettingsController _controller(
  _FakeSettingsClient client, {
  Future<void> Function(AppStateSnapshot snapshot)? onSaved,
}) {
  return SettingsController(client: client, onSaved: onSaved ?? (_) async {});
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

Future<void> _waitForSaveCompleters(
  _FakeSettingsClient client,
  int count,
) async {
  for (
    var attempt = 0;
    attempt < 20 && client.saveCompleters.length < count;
    attempt += 1
  ) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(client.saveCompleters.length, count);
}

final class _FakeSettingsClient implements SettingsClient {
  _FakeSettingsClient({required this.snapshot, this.delaySaves = false});

  AppStateSnapshot snapshot;
  final bool delaySaves;
  final List<AppSettings> savedSettings = [];
  final List<Completer<void>> saveCompleters = [];

  @override
  Future<AppStateSnapshot> loadSettingsSnapshot() async => snapshot;

  @override
  Future<AppStateSnapshot> saveSettings(AppSettings settings) async {
    savedSettings.add(settings);
    if (delaySaves) {
      final completer = Completer<void>();
      saveCompleters.add(completer);
      await completer.future;
    }
    snapshot = snapshot.copyWith(settings: settings);
    return snapshot;
  }
}
