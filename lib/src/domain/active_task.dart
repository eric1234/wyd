import 'activity_log.dart';

final class ActiveTask {
  ActiveTask({
    required this.taskText,
    required this.taskTextNormalized,
    required DateTime startedAtUtc,
    required this.sourceEventId,
  }) : startedAtUtc = startedAtUtc.toUtc();

  factory ActiveTask.fromEvent(ActivityLogEvent event) {
    if (!event.opensTask || !event.hasTaskText) {
      throw ArgumentError.value(event, 'event', 'Event does not open a task.');
    }

    return ActiveTask(
      taskText: event.taskText!,
      taskTextNormalized: event.taskTextNormalized!,
      startedAtUtc: event.occurredAtUtc,
      sourceEventId: event.id,
    );
  }

  final String taskText;
  final String taskTextNormalized;
  final DateTime startedAtUtc;
  final int sourceEventId;
}
