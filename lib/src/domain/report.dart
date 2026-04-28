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
  });

  final String taskText;
  final String taskTextNormalized;
  final Duration duration;
}

final class DailyReport {
  const DailyReport({
    required this.localDate,
    required this.totalDuration,
    required this.rows,
  });

  final DateTime localDate;
  final Duration totalDuration;
  final List<ReportRow> rows;
}
