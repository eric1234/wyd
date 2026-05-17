enum SettingsField {
  reminderIntervalMinutes,
  autocompleteLookbackDays,
  responseTimeoutMinutes,
  typingDeferralSeconds,
  startAtLogin,
}

final class SettingsValidationIssue {
  const SettingsValidationIssue({required this.field, required this.message});

  final SettingsField field;
  final String message;
}

final class AppSettings {
  const AppSettings({
    this.reminderIntervalMinutes = defaultReminderIntervalMinutes,
    this.autocompleteLookbackDays = defaultAutocompleteLookbackDays,
    this.responseTimeoutMinutes = defaultResponseTimeoutMinutes,
    this.typingDeferralSeconds = defaultTypingDeferralSeconds,
    this.startAtLogin = defaultStartAtLogin,
  });

  static const defaultReminderIntervalMinutes = 15;
  static const defaultAutocompleteLookbackDays = 30;
  static const defaultResponseTimeoutMinutes = 1;
  static const defaultTypingDeferralSeconds = 5;
  static const defaultStartAtLogin = false;

  static const minReminderIntervalMinutes = 1;
  static const maxReminderIntervalMinutes = 240;
  static const minAutocompleteLookbackDays = 1;
  static const maxAutocompleteLookbackDays = 365;
  static const minResponseTimeoutMinutes = 1;
  static const maxResponseTimeoutMinutes = 60;
  static const minTypingDeferralSeconds = 0;
  static const maxTypingDeferralSeconds = 30;

  static const defaults = AppSettings();

  final int reminderIntervalMinutes;
  final int autocompleteLookbackDays;
  final int responseTimeoutMinutes;
  final int typingDeferralSeconds;
  final bool startAtLogin;

  List<SettingsValidationIssue> validate() {
    final issues = <SettingsValidationIssue>[];

    _validateRange(
      issues,
      field: SettingsField.reminderIntervalMinutes,
      value: reminderIntervalMinutes,
      min: minReminderIntervalMinutes,
      max: maxReminderIntervalMinutes,
      label: 'Reminder interval',
    );
    _validateRange(
      issues,
      field: SettingsField.autocompleteLookbackDays,
      value: autocompleteLookbackDays,
      min: minAutocompleteLookbackDays,
      max: maxAutocompleteLookbackDays,
      label: 'Autocomplete lookback',
    );
    _validateRange(
      issues,
      field: SettingsField.responseTimeoutMinutes,
      value: responseTimeoutMinutes,
      min: minResponseTimeoutMinutes,
      max: maxResponseTimeoutMinutes,
      label: 'Response timeout',
    );
    _validateRange(
      issues,
      field: SettingsField.typingDeferralSeconds,
      value: typingDeferralSeconds,
      min: minTypingDeferralSeconds,
      max: maxTypingDeferralSeconds,
      label: 'Activity deferral',
    );

    if (reminderIntervalMinutes < responseTimeoutMinutes) {
      issues.add(
        const SettingsValidationIssue(
          field: SettingsField.reminderIntervalMinutes,
          message:
              'Reminder interval must be greater than or equal to timeout.',
        ),
      );
    }

    return issues;
  }

  bool get isValid => validate().isEmpty;

  AppSettings copyWith({
    int? reminderIntervalMinutes,
    int? autocompleteLookbackDays,
    int? responseTimeoutMinutes,
    int? typingDeferralSeconds,
    bool? startAtLogin,
  }) {
    return AppSettings(
      reminderIntervalMinutes:
          reminderIntervalMinutes ?? this.reminderIntervalMinutes,
      autocompleteLookbackDays:
          autocompleteLookbackDays ?? this.autocompleteLookbackDays,
      responseTimeoutMinutes:
          responseTimeoutMinutes ?? this.responseTimeoutMinutes,
      typingDeferralSeconds:
          typingDeferralSeconds ?? this.typingDeferralSeconds,
      startAtLogin: startAtLogin ?? this.startAtLogin,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AppSettings &&
        reminderIntervalMinutes == other.reminderIntervalMinutes &&
        autocompleteLookbackDays == other.autocompleteLookbackDays &&
        responseTimeoutMinutes == other.responseTimeoutMinutes &&
        typingDeferralSeconds == other.typingDeferralSeconds &&
        startAtLogin == other.startAtLogin;
  }

  @override
  int get hashCode {
    return Object.hash(
      reminderIntervalMinutes,
      autocompleteLookbackDays,
      responseTimeoutMinutes,
      typingDeferralSeconds,
      startAtLogin,
    );
  }

  static void _validateRange(
    List<SettingsValidationIssue> issues, {
    required SettingsField field,
    required int value,
    required int min,
    required int max,
    required String label,
  }) {
    if (value < min || value > max) {
      issues.add(
        SettingsValidationIssue(
          field: field,
          message: '$label must be between $min and $max.',
        ),
      );
    }
  }
}
