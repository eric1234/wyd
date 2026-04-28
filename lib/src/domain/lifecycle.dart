import 'activity_log.dart';
import 'task_text.dart';

sealed class SubmitTaskResult {
  const SubmitTaskResult({required this.submittedTask});

  final TaskText submittedTask;

  ActivityLogEvent? get event;

  String get diagnosticName;

  bool get appendsActivityRow => event != null;
}

final class TaskStarted extends SubmitTaskResult {
  const TaskStarted({required super.submittedTask, required this.event});

  @override
  final ActivityLogEvent event;

  @override
  String get diagnosticName => 'start';
}

final class TaskConfirmed extends SubmitTaskResult {
  const TaskConfirmed({required super.submittedTask});

  @override
  ActivityLogEvent? get event => null;

  @override
  String get diagnosticName => 'confirm';
}

final class TaskSwitched extends SubmitTaskResult {
  const TaskSwitched({required super.submittedTask, required this.event});

  @override
  final ActivityLogEvent event;

  @override
  String get diagnosticName => 'switchTask';
}

sealed class StopTaskResult {
  const StopTaskResult();

  ActivityLogEvent? get event;

  bool get appendsActivityRow => event != null;
}

final class TaskStopped extends StopTaskResult {
  const TaskStopped(this.event);

  @override
  final ActivityLogEvent event;
}

final class NoActiveTaskToStop extends StopTaskResult {
  const NoActiveTaskToStop();

  @override
  ActivityLogEvent? get event => null;
}
