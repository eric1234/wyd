import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/domain/domain.dart';

void main() {
  group('ActivityTimeline lifecycle', () {
    test('starts a task when idle', () {
      final occurredAt = DateTime.utc(2026, 1, 1, 9);
      final decision = ActivityTimeline(
        const [],
      ).submitTask(taskText: ' Write docs ', occurredAtUtc: occurredAt, id: 1);

      expect(decision, isA<TaskStarted>());
      expect(decision.appendsActivityRow, isTrue);
      expect(decision.event!.eventType, ActivityEventType.startTask);
      expect(decision.event!.taskText, 'Write docs');
      expect(decision.event!.taskTextNormalized, 'write docs');
      expect(decision.event!.occurredAtUtc, occurredAt);
    });

    test('confirmation does not append an activity row', () {
      final events = [
        ActivityLogEvent.startTask(
          id: 1,
          occurredAtUtc: DateTime.utc(2026, 1, 1, 9),
          taskText: 'Write   Docs',
        ),
      ];

      final decision = ActivityTimeline(events).submitTask(
        taskText: 'write\tdocs',
        occurredAtUtc: DateTime.utc(2026, 1, 1, 9, 15),
      );

      expect(decision, isA<TaskConfirmed>());
      expect(decision.appendsActivityRow, isFalse);
      expect(decision.event, isNull);
    });

    test('switches when submitted normalized text differs', () {
      final events = [
        ActivityLogEvent.startTask(
          id: 1,
          occurredAtUtc: DateTime.utc(2026, 1, 1, 9),
          taskText: 'Write docs',
        ),
      ];

      final decision = ActivityTimeline(events).submitTask(
        taskText: 'Fix bug',
        occurredAtUtc: DateTime.utc(2026, 1, 1, 10),
        id: 2,
      );

      expect(decision, isA<TaskSwitched>());
      expect(decision.event!.eventType, ActivityEventType.switchTask);
      expect(decision.event!.taskText, 'Fix bug');
      expect(decision.event!.source, ActivitySource.manualSubmit);
    });

    test('explicit stop appends a manual stop only while active', () {
      final events = [
        ActivityLogEvent.startTask(
          id: 1,
          occurredAtUtc: DateTime.utc(2026, 1, 1, 9),
          taskText: 'Write docs',
        ),
      ];

      final activeDecision = ActivityTimeline(events).stopTask(
        occurredAtUtc: DateTime.utc(2026, 1, 1, 10),
        source: ActivitySource.manualStop,
        id: 2,
      );
      final idleDecision = ActivityTimeline([...events, activeDecision.event!])
          .stopTask(
            occurredAtUtc: DateTime.utc(2026, 1, 1, 11),
            source: ActivitySource.manualStop,
            id: 3,
          );

      expect(activeDecision, isA<TaskStopped>());
      expect(activeDecision.event!.eventType, ActivityEventType.stopTask);
      expect(activeDecision.event!.source, ActivitySource.manualStop);
      expect(idleDecision, isA<NoActiveTaskToStop>());
      expect(idleDecision.event, isNull);
    });

    test('timeout stop uses the prompt shown timestamp and source', () {
      final promptShownAt = DateTime.utc(2026, 1, 1, 10);
      final events = [
        ActivityLogEvent.startTask(
          id: 1,
          occurredAtUtc: DateTime.utc(2026, 1, 1, 9),
          taskText: 'Write docs',
        ),
      ];

      final decision = ActivityTimeline(events).stopTask(
        occurredAtUtc: promptShownAt,
        source: ActivitySource.nagTimeout,
        id: 2,
      );

      expect(decision.event!.occurredAtUtc, promptShownAt);
      expect(decision.event!.source, ActivitySource.nagTimeout);
    });

    test('exit stop uses exit source', () {
      final events = [
        ActivityLogEvent.startTask(
          id: 1,
          occurredAtUtc: DateTime.utc(2026, 1, 1, 9),
          taskText: 'Write docs',
        ),
      ];

      final decision = ActivityTimeline(events).stopTask(
        occurredAtUtc: DateTime.utc(2026, 1, 1, 10),
        source: ActivitySource.exit,
      );

      expect(decision.event!.source, ActivitySource.exit);
    });

    test('derives current active task from ordered events using id ties', () {
      final sameTime = DateTime.utc(2026, 1, 1, 9);
      final events = [
        ActivityLogEvent.switchTask(
          id: 3,
          occurredAtUtc: sameTime,
          taskText: 'Fix bug',
        ),
        ActivityLogEvent.startTask(
          id: 1,
          occurredAtUtc: sameTime,
          taskText: 'Write docs',
        ),
        ActivityLogEvent.stopTask(
          id: 2,
          occurredAtUtc: sameTime,
          source: ActivitySource.manualStop,
        ),
      ];

      final activeTask = ActivityTimeline(events).activeTask;

      expect(activeTask, isNotNull);
      expect(activeTask!.taskText, 'Fix bug');
    });
  });
}
