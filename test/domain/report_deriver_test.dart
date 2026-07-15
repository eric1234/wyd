import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/domain/domain.dart';

void main() {
  group('ActivityTimeline reports', () {
    test('splits a segment that crosses local midnight', () {
      final startLocal = DateTime(2026, 1, 1, 23, 30);
      final stopLocal = DateTime(2026, 1, 2, 0, 30);
      final events = [
        ActivityLogEvent.startTask(
          id: 1,
          occurredAtUtc: startLocal.toUtc(),
          taskText: 'Write docs',
        ),
        ActivityLogEvent.stopTask(
          id: 2,
          occurredAtUtc: stopLocal.toUtc(),
          source: ActivitySource.manualStop,
        ),
      ];

      final firstDay = ActivityTimeline(events).buildReport(
        dateRange: _dayRange(DateTime(2026, 1, 1)),
        nowUtc: stopLocal.toUtc(),
      );
      final secondDay = ActivityTimeline(events).buildReport(
        dateRange: _dayRange(DateTime(2026, 1, 2)),
        nowUtc: stopLocal.toUtc(),
      );

      expect(firstDay.totalDuration, const Duration(minutes: 30));
      expect(secondDay.totalDuration, const Duration(minutes: 30));
    });

    test('ends an active current-day segment at injected now', () {
      final startLocal = DateTime(2026, 1, 2, 10);
      final nowLocal = DateTime(2026, 1, 2, 11, 15);
      final report =
          ActivityTimeline([
            ActivityLogEvent.startTask(
              id: 1,
              occurredAtUtc: startLocal.toUtc(),
              taskText: 'Write docs',
            ),
          ]).buildReport(
            dateRange: _dayRange(DateTime(2026, 1, 2)),
            nowUtc: nowLocal.toUtc(),
          );

      expect(report.totalDuration, const Duration(minutes: 75));
      expect(report.rows.single.taskText, 'Write docs');
    });

    test('aggregates normalized task rows and uses most recent raw label', () {
      final day = DateTime(2026, 1, 2);
      final events = [
        ActivityLogEvent.startTask(
          id: 1,
          occurredAtUtc: DateTime(2026, 1, 2, 9).toUtc(),
          taskText: 'Write Docs',
        ),
        ActivityLogEvent.switchTask(
          id: 2,
          occurredAtUtc: DateTime(2026, 1, 2, 10).toUtc(),
          taskText: 'Other',
        ),
        ActivityLogEvent.switchTask(
          id: 3,
          occurredAtUtc: DateTime(2026, 1, 2, 11).toUtc(),
          taskText: 'write   docs',
        ),
        ActivityLogEvent.stopTask(
          id: 4,
          occurredAtUtc: DateTime(2026, 1, 2, 12).toUtc(),
          source: ActivitySource.manualStop,
        ),
      ];

      final report = ActivityTimeline(events).buildReport(
        dateRange: _dayRange(day),
        nowUtc: DateTime(2026, 1, 2, 12).toUtc(),
      );

      expect(report.totalDuration, const Duration(hours: 3));
      expect(report.rows.first.taskTextNormalized, 'write docs');
      expect(report.rows.first.taskText, 'write   docs');
      expect(report.rows.first.duration, const Duration(hours: 2));
      expect(report.rows.last.taskText, 'Other');
    });

    test('sorts report rows by duration descending', () {
      final report =
          ActivityTimeline([
            ActivityLogEvent.startTask(
              id: 1,
              occurredAtUtc: DateTime(2026, 1, 2, 9).toUtc(),
              taskText: 'Short',
            ),
            ActivityLogEvent.switchTask(
              id: 2,
              occurredAtUtc: DateTime(2026, 1, 2, 9, 30).toUtc(),
              taskText: 'Long',
            ),
            ActivityLogEvent.stopTask(
              id: 3,
              occurredAtUtc: DateTime(2026, 1, 2, 11).toUtc(),
              source: ActivitySource.manualStop,
            ),
          ]).buildReport(
            dateRange: _dayRange(DateTime(2026, 1, 2)),
            nowUtc: DateTime(2026, 1, 2, 11).toUtc(),
          );

      expect(report.rows.map((row) => row.taskText), ['Long', 'Short']);
    });

    test('orders same-timestamp events by id when deriving segments', () {
      final switchTime = DateTime.utc(2026, 1, 2, 10);
      final report =
          ActivityTimeline([
            ActivityLogEvent.switchTask(
              id: 3,
              occurredAtUtc: switchTime,
              taskText: 'Task B',
            ),
            ActivityLogEvent.startTask(
              id: 1,
              occurredAtUtc: DateTime.utc(2026, 1, 2, 9),
              taskText: 'Task A',
            ),
            ActivityLogEvent.stopTask(
              id: 2,
              occurredAtUtc: switchTime,
              source: ActivitySource.manualStop,
            ),
          ]).buildReport(
            dateRange: _dayRange(DateTime(2026, 1, 2)),
            nowUtc: DateTime.utc(2026, 1, 2, 11),
          );

      expect(report.rows.map((row) => row.taskText), ['Task A', 'Task B']);
      expect(report.rows.map((row) => row.duration), [
        const Duration(hours: 1),
        const Duration(hours: 1),
      ]);
    });

    test('handles malformed sequences without failing', () {
      final report =
          ActivityTimeline([
            ActivityLogEvent.stopTask(
              id: 1,
              occurredAtUtc: DateTime(2026, 1, 2, 8).toUtc(),
              source: ActivitySource.manualStop,
            ),
            ActivityLogEvent.switchTask(
              id: 2,
              occurredAtUtc: DateTime(2026, 1, 2, 9).toUtc(),
              taskText: 'Recovered active task',
            ),
            ActivityLogEvent.startTask(
              id: 3,
              occurredAtUtc: DateTime(2026, 1, 2, 10).toUtc(),
              taskText: 'Replacement task',
            ),
            ActivityLogEvent.stopTask(
              id: 4,
              occurredAtUtc: DateTime(2026, 1, 2, 11).toUtc(),
              source: ActivitySource.manualStop,
            ),
          ]).buildReport(
            dateRange: _dayRange(DateTime(2026, 1, 2)),
            nowUtc: DateTime(2026, 1, 2, 11).toUtc(),
          );

      expect(report.totalDuration, const Duration(hours: 2));
      expect(report.rows, hasLength(2));
    });

    test('clips segments to a multi-day report range', () {
      final report =
          ActivityTimeline([
            ActivityLogEvent.startTask(
              id: 1,
              occurredAtUtc: DateTime(2026, 1, 1, 12).toUtc(),
              taskText: 'Long task',
            ),
            ActivityLogEvent.stopTask(
              id: 2,
              occurredAtUtc: DateTime(2026, 1, 5, 12).toUtc(),
              source: ActivitySource.manualStop,
            ),
          ]).buildReport(
            dateRange: ReportDateRange(
              startLocalDateInclusive: DateTime(2026, 1, 2),
              endLocalDateExclusive: DateTime(2026, 1, 5),
            ),
            nowUtc: DateTime(2026, 1, 5, 12).toUtc(),
          );

      expect(report.totalDuration, const Duration(days: 3));
      expect(report.rows.single.taskText, 'Long task');
    });

    test('normalizes report date range inputs to local dates', () {
      final range = ReportDateRange(
        startLocalDateInclusive: DateTime(2026, 1, 2, 13, 30),
        endLocalDateExclusive: DateTime(2026, 1, 4, 8),
      );

      expect(range.startLocalDateInclusive, DateTime(2026, 1, 2));
      expect(range.endLocalDateExclusive, DateTime(2026, 1, 4));
    });
  });
}

ReportDateRange _dayRange(DateTime date) => ReportDateRange(
  startLocalDateInclusive: date,
  endLocalDateExclusive: DateTime(date.year, date.month, date.day + 1),
);
