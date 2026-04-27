import 'active_task.dart';
import 'activity_log.dart';
import 'task_text.dart';

enum SubmitTaskAction { start, confirm, switchTask }

final class SubmitTaskDecision {
  const SubmitTaskDecision({
    required this.action,
    required this.submittedTask,
    this.event,
  });

  final SubmitTaskAction action;
  final TaskText submittedTask;
  final ActivityLogEvent? event;

  bool get appendsActivityRow => event != null;
}

enum StopTaskAction { appendStop, noOp }

final class StopTaskDecision {
  const StopTaskDecision({required this.action, this.event});

  final StopTaskAction action;
  final ActivityLogEvent? event;

  bool get appendsActivityRow => event != null;
}

final class TaskLifecycle {
  const TaskLifecycle._();

  static ActiveTask? deriveActiveTask(Iterable<ActivityLogEvent> events) {
    ActiveTask? activeTask;

    for (final event in orderActivityEvents(events)) {
      if (event.opensTask && event.hasTaskText) {
        activeTask = ActiveTask.fromEvent(event);
      } else if (event.eventType == ActivityEventType.stopTask) {
        activeTask = null;
      }
    }

    return activeTask;
  }

  static SubmitTaskDecision submitTask({
    required Iterable<ActivityLogEvent> events,
    required String taskText,
    required DateTime occurredAtUtc,
    DateTime? createdAtUtc,
    int id = 0,
  }) {
    final submittedTask = TaskText.fromInput(taskText);
    final activeTask = deriveActiveTask(events);

    if (activeTask == null) {
      return SubmitTaskDecision(
        action: SubmitTaskAction.start,
        submittedTask: submittedTask,
        event: ActivityLogEvent.startTask(
          id: id,
          occurredAtUtc: occurredAtUtc,
          taskText: submittedTask.value,
          createdAtUtc: createdAtUtc,
        ),
      );
    }

    if (activeTask.taskTextNormalized == submittedTask.normalized) {
      return SubmitTaskDecision(
        action: SubmitTaskAction.confirm,
        submittedTask: submittedTask,
      );
    }

    return SubmitTaskDecision(
      action: SubmitTaskAction.switchTask,
      submittedTask: submittedTask,
      event: ActivityLogEvent.switchTask(
        id: id,
        occurredAtUtc: occurredAtUtc,
        taskText: submittedTask.value,
        createdAtUtc: createdAtUtc,
      ),
    );
  }

  static StopTaskDecision stopTask({
    required Iterable<ActivityLogEvent> events,
    required DateTime occurredAtUtc,
    required ActivitySource source,
    DateTime? createdAtUtc,
    int id = 0,
  }) {
    final activeTask = deriveActiveTask(events);
    if (activeTask == null) {
      return const StopTaskDecision(action: StopTaskAction.noOp);
    }

    return StopTaskDecision(
      action: StopTaskAction.appendStop,
      event: ActivityLogEvent.stopTask(
        id: id,
        occurredAtUtc: occurredAtUtc,
        source: source,
        createdAtUtc: createdAtUtc,
      ),
    );
  }
}
