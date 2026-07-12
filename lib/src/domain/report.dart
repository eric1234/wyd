import 'task_tag.dart';

final class ReportSegment {
  ReportSegment({
    required this.taskText,
    required this.taskTextNormalized,
    required DateTime startedAtUtc,
    required DateTime endedAtUtc,
    required DateTime labelSeenAtUtc,
  }) : startedAtUtc = startedAtUtc.toUtc(),
       endedAtUtc = endedAtUtc.toUtc(),
       labelSeenAtUtc = labelSeenAtUtc.toUtc();

  final String taskText;
  final String taskTextNormalized;
  final DateTime startedAtUtc;
  final DateTime endedAtUtc;
  final DateTime labelSeenAtUtc;

  Duration get duration => endedAtUtc.difference(startedAtUtc);
}

final class ReportRow {
  const ReportRow({
    required this.taskText,
    required this.taskTextNormalized,
    required this.duration,
    this.tags = const [],
  });

  final String taskText;
  final String taskTextNormalized;
  final Duration duration;
  final List<TaskTag> tags;
}

final class ReportDateRange {
  ReportDateRange({
    required DateTime startLocalDateInclusive,
    required DateTime endLocalDateExclusive,
  }) : startLocalDateInclusive = DateTime(
         startLocalDateInclusive.year,
         startLocalDateInclusive.month,
         startLocalDateInclusive.day,
       ),
       endLocalDateExclusive = DateTime(
         endLocalDateExclusive.year,
         endLocalDateExclusive.month,
         endLocalDateExclusive.day,
       ) {
    if (!this.endLocalDateExclusive.isAfter(this.startLocalDateInclusive)) {
      throw ArgumentError.value(
        endLocalDateExclusive,
        'endLocalDateExclusive',
        'must be after startLocalDateInclusive',
      );
    }
  }

  final DateTime startLocalDateInclusive;
  final DateTime endLocalDateExclusive;
}

final class ActivityReport {
  const ActivityReport({required this.totalDuration, required this.rows});

  final Duration totalDuration;
  final List<ReportRow> rows;
}
