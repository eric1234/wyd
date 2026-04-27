import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wyd/src/application/application.dart';
import 'package:wyd/src/domain/domain.dart';
import 'package:wyd/src/infrastructure/persistence/persistence.dart';

void main() {
  group('SettingsService', () {
    test('persists valid settings through TrackerService', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      final service = SettingsService(
        trackerService: harness.trackerService,
        startupAtLoginAdapter: harness.startupAtLogin,
      );

      final snapshot = await service.saveSettings(
        const AppSettings(
          reminderIntervalMinutes: 20,
          autocompleteLookbackDays: 7,
          responseTimeoutMinutes: 5,
          typingDeferralSeconds: 0,
        ),
      );

      expect(snapshot.settings.reminderIntervalMinutes, 20);
      expect(snapshot.settings.autocompleteLookbackDays, 7);
      expect(snapshot.settings.responseTimeoutMinutes, 5);
      expect(snapshot.settings.typingDeferralSeconds, 0);
    });

    test('coerces start-at-login off when unsupported', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      final service = SettingsService(
        trackerService: harness.trackerService,
        startupAtLoginAdapter: harness.startupAtLogin,
      );

      final snapshot = await service.saveSettings(
        const AppSettings(startAtLogin: true),
      );

      expect(snapshot.settings.startAtLogin, isFalse);
      expect(harness.startupAtLogin.enabledValues, isEmpty);
    });

    test('calls start-at-login adapter when supported', () async {
      final harness = await _Harness.create(
        capabilities: const PlatformCapabilities(supportsStartAtLogin: true),
      );
      addTearDown(harness.dispose);
      final service = SettingsService(
        trackerService: harness.trackerService,
        startupAtLoginAdapter: harness.startupAtLogin,
      );

      final snapshot = await service.saveSettings(
        const AppSettings(startAtLogin: true),
      );

      expect(snapshot.settings.startAtLogin, isTrue);
      expect(harness.startupAtLogin.enabledValues, [true]);
    });

    test('validates settings before changing start-at-login', () async {
      final harness = await _Harness.create(
        capabilities: const PlatformCapabilities(supportsStartAtLogin: true),
      );
      addTearDown(harness.dispose);
      final service = SettingsService(
        trackerService: harness.trackerService,
        startupAtLoginAdapter: harness.startupAtLogin,
      );

      await expectLater(
        () => service.saveSettings(
          const AppSettings(
            reminderIntervalMinutes: 1,
            responseTimeoutMinutes: 2,
            startAtLogin: true,
          ),
        ),
        throwsA(isA<AppSettingsValidationException>()),
      );

      expect(harness.startupAtLogin.enabledValues, isEmpty);
      expect(
        (await harness.trackerService.loadSnapshot()).settings,
        AppSettings.defaults,
      );
    });

    test(
      'does not persist settings when start-at-login adapter fails',
      () async {
        final harness = await _Harness.create(
          capabilities: const PlatformCapabilities(supportsStartAtLogin: true),
        );
        addTearDown(harness.dispose);
        harness.startupAtLogin.failOnSet = true;
        final service = SettingsService(
          trackerService: harness.trackerService,
          startupAtLoginAdapter: harness.startupAtLogin,
        );

        await expectLater(
          () => service.saveSettings(const AppSettings(startAtLogin: true)),
          throwsStateError,
        );

        final snapshot = await harness.trackerService.loadSnapshot();
        expect(snapshot.settings.startAtLogin, isFalse);
        expect(harness.startupAtLogin.enabledValues, isEmpty);
      },
    );
  });
}

final class _Harness {
  _Harness({
    required this.database,
    required this.trackerService,
    required this.startupAtLogin,
  });

  final AppDatabase database;
  final TrackerService trackerService;
  final _FakeStartupAtLoginAdapter startupAtLogin;

  static Future<_Harness> create({
    PlatformCapabilities capabilities = const PlatformCapabilities(),
  }) async {
    final database = await AppDatabase.openInMemory(
      databaseFactory: databaseFactoryFfi,
    );
    return _Harness(
      database: database,
      trackerService: TrackerService(
        transactions: SqliteTransactionRunner(database),
        clock: _FakeClock(DateTime.utc(2026, 1, 1, 9)),
        capabilities: capabilities,
      ),
      startupAtLogin: _FakeStartupAtLoginAdapter(),
    );
  }

  Future<void> dispose() => database.close();
}

final class _FakeClock implements Clock {
  const _FakeClock(this.current);

  final DateTime current;

  @override
  DateTime nowUtc() => current;
}

final class _FakeStartupAtLoginAdapter implements StartupAtLoginAdapter {
  final List<bool> enabledValues = [];
  bool failOnSet = false;

  @override
  Future<bool> isEnabled() async {
    return enabledValues.isEmpty ? false : enabledValues.last;
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    if (failOnSet) {
      throw StateError('start-at-login update failed');
    }
    enabledValues.add(enabled);
  }
}
