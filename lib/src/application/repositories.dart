import '../domain/domain.dart';

abstract interface class ActivityLogRepository {
  Future<ActivityLogEvent> append(ActivityLogEvent event);

  Future<List<ActivityLogEvent>> allEvents();

  Future<ActivityLogEvent?> latestEvent();

  Future<ActivityLogEvent?> latestEventBefore(DateTime beforeUtc);

  Future<List<ActivityLogEvent>> eventsBetween({
    required DateTime fromUtc,
    required DateTime throughUtc,
  });

  Future<List<ActivityLogEvent>> taskEventsBetween({
    required DateTime fromUtc,
    required DateTime throughUtc,
  });
}

abstract interface class RuntimeStateRepository {
  Future<RuntimeState> read();

  Future<void> save(RuntimeState state);
}

abstract interface class SettingsRepository {
  Future<AppSettings> read();

  Future<void> save(AppSettings settings);
}

abstract interface class AppTransaction {
  ActivityLogRepository get activityLog;

  RuntimeStateRepository get runtimeState;

  SettingsRepository get settings;
}

abstract interface class TransactionRunner {
  Future<T> run<T>(Future<T> Function(AppTransaction transaction) action);
}
