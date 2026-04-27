import 'task_text.dart';

enum ActivityEventType { startTask, switchTask, stopTask }

enum ActivitySource {
  manualSubmit,
  manualStop,
  nagTimeout,
  systemLock,
  systemSleep,
  exit,
  recovery,
}

final class ActivityLogEvent {
  ActivityLogEvent({
    this.id = 0,
    required DateTime occurredAtUtc,
    required this.eventType,
    this.taskText,
    String? taskTextNormalized,
    required this.source,
    DateTime? createdAtUtc,
  }) : occurredAtUtc = occurredAtUtc.toUtc(),
       taskTextNormalized =
           taskTextNormalized ??
           (taskText == null ? null : TaskText.normalizeForEquality(taskText)),
       createdAtUtc = (createdAtUtc ?? occurredAtUtc).toUtc();

  factory ActivityLogEvent.startTask({
    int id = 0,
    required DateTime occurredAtUtc,
    required String taskText,
    ActivitySource source = ActivitySource.manualSubmit,
    DateTime? createdAtUtc,
  }) {
    return ActivityLogEvent._taskBoundary(
      id: id,
      occurredAtUtc: occurredAtUtc,
      eventType: ActivityEventType.startTask,
      taskText: taskText,
      source: source,
      createdAtUtc: createdAtUtc,
    );
  }

  factory ActivityLogEvent.switchTask({
    int id = 0,
    required DateTime occurredAtUtc,
    required String taskText,
    ActivitySource source = ActivitySource.manualSubmit,
    DateTime? createdAtUtc,
  }) {
    return ActivityLogEvent._taskBoundary(
      id: id,
      occurredAtUtc: occurredAtUtc,
      eventType: ActivityEventType.switchTask,
      taskText: taskText,
      source: source,
      createdAtUtc: createdAtUtc,
    );
  }

  factory ActivityLogEvent.stopTask({
    int id = 0,
    required DateTime occurredAtUtc,
    required ActivitySource source,
    DateTime? createdAtUtc,
  }) {
    return ActivityLogEvent(
      id: id,
      occurredAtUtc: occurredAtUtc,
      eventType: ActivityEventType.stopTask,
      source: source,
      createdAtUtc: createdAtUtc,
    );
  }

  factory ActivityLogEvent._taskBoundary({
    required int id,
    required DateTime occurredAtUtc,
    required ActivityEventType eventType,
    required String taskText,
    required ActivitySource source,
    DateTime? createdAtUtc,
  }) {
    final parsedTaskText = TaskText.fromInput(taskText);
    return ActivityLogEvent(
      id: id,
      occurredAtUtc: occurredAtUtc,
      eventType: eventType,
      taskText: parsedTaskText.value,
      taskTextNormalized: parsedTaskText.normalized,
      source: source,
      createdAtUtc: createdAtUtc,
    );
  }

  final int id;
  final DateTime occurredAtUtc;
  final ActivityEventType eventType;
  final String? taskText;
  final String? taskTextNormalized;
  final ActivitySource source;
  final DateTime createdAtUtc;

  bool get opensTask {
    return eventType == ActivityEventType.startTask ||
        eventType == ActivityEventType.switchTask;
  }

  bool get hasTaskText {
    return taskText != null &&
        taskText!.isNotEmpty &&
        taskTextNormalized != null &&
        taskTextNormalized!.isNotEmpty;
  }

  ActivityLogEvent withId(int id) {
    return ActivityLogEvent(
      id: id,
      occurredAtUtc: occurredAtUtc,
      eventType: eventType,
      taskText: taskText,
      taskTextNormalized: taskTextNormalized,
      source: source,
      createdAtUtc: createdAtUtc,
    );
  }
}

int compareActivityEvents(ActivityLogEvent left, ActivityLogEvent right) {
  final timeComparison = left.occurredAtUtc.compareTo(right.occurredAtUtc);
  if (timeComparison != 0) {
    return timeComparison;
  }

  return left.id.compareTo(right.id);
}

List<ActivityLogEvent> orderActivityEvents(Iterable<ActivityLogEvent> events) {
  return events.toList()..sort(compareActivityEvents);
}

extension ActivityEventTypeStorageName on ActivityEventType {
  String get storageName {
    return switch (this) {
      ActivityEventType.startTask => 'start_task',
      ActivityEventType.switchTask => 'switch_task',
      ActivityEventType.stopTask => 'stop_task',
    };
  }
}

extension ActivitySourceStorageName on ActivitySource {
  String get storageName {
    return switch (this) {
      ActivitySource.manualSubmit => 'manual_submit',
      ActivitySource.manualStop => 'manual_stop',
      ActivitySource.nagTimeout => 'nag_timeout',
      ActivitySource.systemLock => 'system_lock',
      ActivitySource.systemSleep => 'system_sleep',
      ActivitySource.exit => 'exit',
      ActivitySource.recovery => 'recovery',
    };
  }
}
