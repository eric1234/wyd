import '../domain/domain.dart';
import 'clock.dart';
import 'repositories.dart';

abstract interface class ActivityReportLoader {
  DateTime todayLocalDate();

  Future<ActivityReport> loadReport(ReportDateRange dateRange);

  Future<TaskTag> addTaskTag({
    required String taskTextNormalized,
    required String tagText,
  });

  Future<void> removeTaskTag({
    required String taskTextNormalized,
    required String tagTextNormalized,
  });
}

final class ReportService implements ActivityReportLoader {
  const ReportService({
    required TransactionRunner transactions,
    required Clock clock,
  }) : _transactions = transactions,
       _clock = clock;

  final TransactionRunner _transactions;
  final Clock _clock;

  @override
  DateTime todayLocalDate() {
    final nowLocal = _clock.nowUtc().toLocal();
    return DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
  }

  @override
  Future<ActivityReport> loadReport(ReportDateRange dateRange) {
    final rangeStartUtc = dateRange.startLocalDateInclusive.toUtc();
    final rangeEndUtc = dateRange.endLocalDateExclusive.toUtc();
    final nowUtc = _clock.nowUtc();
    final reportEndUtc = nowUtc.isBefore(rangeEndUtc) ? nowUtc : rangeEndUtc;

    if (!reportEndUtc.isAfter(rangeStartUtc)) {
      return Future.value(
        ActivityReport(totalDuration: Duration.zero, rows: const []),
      );
    }

    return _transactions.run((transaction) async {
      final priorEvent = await transaction.activityLog.latestEventBefore(
        rangeStartUtc,
      );
      final events = await transaction.activityLog.eventsBetween(
        fromUtc: rangeStartUtc,
        throughUtc: reportEndUtc,
      );
      final report = ActivityTimeline([
        ?priorEvent,
        ...events,
      ]).buildReport(dateRange: dateRange, nowUtc: reportEndUtc);
      final tagsByTask = await transaction.taskTags.tagsForTasks(
        report.rows.map((row) => row.taskTextNormalized),
      );

      return ActivityReport(
        totalDuration: report.totalDuration,
        rows: [
          for (final row in report.rows)
            ReportRow(
              taskText: row.taskText,
              taskTextNormalized: row.taskTextNormalized,
              duration: row.duration,
              tags: tagsByTask[row.taskTextNormalized] ?? const [],
            ),
        ],
      );
    });
  }

  @override
  Future<TaskTag> addTaskTag({
    required String taskTextNormalized,
    required String tagText,
  }) {
    return _transactions.run((transaction) {
      return transaction.taskTags.addTag(
        taskTextNormalized: taskTextNormalized,
        tagText: tagText,
      );
    });
  }

  @override
  Future<void> removeTaskTag({
    required String taskTextNormalized,
    required String tagTextNormalized,
  }) {
    return _transactions.run((transaction) {
      return transaction.taskTags.removeTag(
        taskTextNormalized: taskTextNormalized,
        tagTextNormalized: tagTextNormalized,
      );
    });
  }
}
