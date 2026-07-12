import '../../domain/domain.dart';

String serializeUtc(DateTime value) => value.toUtc().toIso8601String();

DateTime? parseNullableUtc(Object? value) {
  if (value == null) {
    return null;
  }

  return DateTime.parse(value as String).toUtc();
}

DateTime parseUtc(Object? value) {
  final parsed = parseNullableUtc(value);
  if (parsed == null) {
    throw const FormatException('Expected a non-null UTC timestamp.');
  }

  return parsed;
}

int boolToSqlite(bool value) => value ? 1 : 0;

bool boolFromSqlite(Object? value) => (value as int) == 1;

Map<String, Object?> activityEventToRow(ActivityLogEvent event) {
  return {
    'occurred_at_utc': serializeUtc(event.occurredAtUtc),
    'event_type': event.eventType.storageName,
    'task_text': event.taskText,
    'task_text_normalized': event.taskTextNormalized,
    'source': event.source.storageName,
    'created_at_utc': serializeUtc(event.createdAtUtc),
  };
}

ActivityLogEvent activityEventFromRow(Map<String, Object?> row) {
  return ActivityLogEvent.hydrate(
    id: row['id'] as int,
    occurredAtUtc: parseUtc(row['occurred_at_utc']),
    eventType: activityEventTypeFromStorage(row['event_type'] as String),
    taskText: row['task_text'] as String?,
    taskTextNormalized: row['task_text_normalized'] as String?,
    source: activitySourceFromStorage(row['source'] as String),
    createdAtUtc: parseUtc(row['created_at_utc']),
  );
}

ActivityEventType activityEventTypeFromStorage(String value) {
  return switch (value) {
    'start_task' => ActivityEventType.startTask,
    'switch_task' => ActivityEventType.switchTask,
    'stop_task' => ActivityEventType.stopTask,
    _ => throw FormatException('Unknown activity event type: $value'),
  };
}

ActivitySource activitySourceFromStorage(String value) {
  return switch (value) {
    'manual_submit' => ActivitySource.manualSubmit,
    'manual_stop' => ActivitySource.manualStop,
    'nag_timeout' => ActivitySource.nagTimeout,
    'system_lock' => ActivitySource.systemLock,
    'system_sleep' => ActivitySource.systemSleep,
    'exit' => ActivitySource.exit,
    'recovery' => ActivitySource.recovery,
    _ => throw FormatException('Unknown activity source: $value'),
  };
}

Map<String, Object?> runtimeStateToRow(RuntimeState state) {
  return {
    'id': 1,
    'last_confirmation_at_utc': state.lastConfirmationAtUtc == null
        ? null
        : serializeUtc(state.lastConfirmationAtUtc!),
    'pending_prompt_shown_at_utc': state.promptState.shownAtUtc == null
        ? null
        : serializeUtc(state.promptState.shownAtUtc!),
    'pending_prompt_expired': boolToSqlite(state.promptState.expired),
    'clean_shutdown': boolToSqlite(state.cleanShutdown),
  };
}

RuntimeState runtimeStateFromRow(Map<String, Object?> row) {
  final shownAt = parseNullableUtc(row['pending_prompt_shown_at_utc']);
  final expired = boolFromSqlite(row['pending_prompt_expired']);

  return RuntimeState(
    lastConfirmationAtUtc: parseNullableUtc(row['last_confirmation_at_utc']),
    promptState: shownAt == null
        ? const PromptState.none()
        : expired
        ? PromptState.expired(shownAt)
        : PromptState.visible(shownAt),
    cleanShutdown: boolFromSqlite(row['clean_shutdown']),
  );
}

Map<String, Object?> settingsToRow(AppSettings settings) {
  return {
    'id': 1,
    'reminder_interval_minutes': settings.reminderIntervalMinutes,
    'autocomplete_lookback_days': settings.autocompleteLookbackDays,
    'response_timeout_minutes': settings.responseTimeoutMinutes,
    'typing_deferral_seconds': settings.typingDeferralSeconds,
    'start_at_login': boolToSqlite(settings.startAtLogin),
  };
}

AppSettings settingsFromRow(Map<String, Object?> row) {
  return AppSettings(
    reminderIntervalMinutes: row['reminder_interval_minutes'] as int,
    autocompleteLookbackDays: row['autocomplete_lookback_days'] as int,
    responseTimeoutMinutes: row['response_timeout_minutes'] as int,
    typingDeferralSeconds: row['typing_deferral_seconds'] as int,
    startAtLogin: boolFromSqlite(row['start_at_login']),
  );
}

Map<String, Object?> taskTagToRow({
  required String taskTextNormalized,
  required TaskTag tag,
  required DateTime createdAtUtc,
}) {
  return {
    'task_text_normalized': taskTextNormalized,
    'tag_text': tag.text,
    'tag_text_normalized': tag.normalized,
    'created_at_utc': serializeUtc(createdAtUtc),
  };
}

TaskTag taskTagFromRow(Map<String, Object?> row) {
  return TaskTag.hydrate(
    text: row['tag_text'] as String,
    normalized: row['tag_text_normalized'] as String,
  );
}
