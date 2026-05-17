import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/domain/domain.dart';

void main() {
  group('AppSettings', () {
    test('defaults are valid and match the spec', () {
      const settings = AppSettings.defaults;

      expect(settings.reminderIntervalMinutes, 15);
      expect(settings.autocompleteLookbackDays, 30);
      expect(settings.responseTimeoutMinutes, 1);
      expect(settings.typingDeferralSeconds, 5);
      expect(settings.startAtLogin, isFalse);
      expect(settings.validate(), isEmpty);
    });

    test('allows inclusive validation boundaries', () {
      const settings = AppSettings(
        reminderIntervalMinutes: AppSettings.maxReminderIntervalMinutes,
        autocompleteLookbackDays: AppSettings.maxAutocompleteLookbackDays,
        responseTimeoutMinutes: AppSettings.maxResponseTimeoutMinutes,
        typingDeferralSeconds: AppSettings.minTypingDeferralSeconds,
      );

      expect(settings.validate(), isEmpty);
    });

    test('reports range validation issues', () {
      const settings = AppSettings(
        reminderIntervalMinutes: 0,
        autocompleteLookbackDays: 366,
        responseTimeoutMinutes: 0,
        typingDeferralSeconds: 31,
      );

      final fields = settings.validate().map((issue) => issue.field).toSet();

      expect(fields, contains(SettingsField.reminderIntervalMinutes));
      expect(fields, contains(SettingsField.autocompleteLookbackDays));
      expect(fields, contains(SettingsField.responseTimeoutMinutes));
      expect(fields, contains(SettingsField.typingDeferralSeconds));
    });

    test('requires reminder interval to be at least response timeout', () {
      const settings = AppSettings(
        reminderIntervalMinutes: 5,
        responseTimeoutMinutes: 10,
      );

      expect(
        settings.validate().map((issue) => issue.field),
        contains(SettingsField.reminderIntervalMinutes),
      );
    });
  });
}
