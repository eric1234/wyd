import 'activity_log.dart';

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

final class ReportDeriver {
  const ReportDeriver._();

  static List<ReportSegment> deriveSegments({
    required Iterable<ActivityLogEvent> events,
    required DateTime nowUtc,
  }) {
    final segments = <ReportSegment>[];
    _OpenSegment? openSegment;

    void closeOpenSegment(DateTime endedAtUtc) {
      final current = openSegment;
      if (current == null) {
        return;
      }

      final normalizedEnd = endedAtUtc.toUtc();
      if (normalizedEnd.isAfter(current.startedAtUtc)) {
        segments.add(
          ReportSegment(
            taskText: current.taskText,
            taskTextNormalized: current.taskTextNormalized,
            startedAtUtc: current.startedAtUtc,
            endedAtUtc: normalizedEnd,
            labelSeenAtUtc: current.labelSeenAtUtc,
          ),
        );
      }
      openSegment = null;
    }

    for (final event in orderActivityEvents(events)) {
      if (event.opensTask && event.hasTaskText) {
        closeOpenSegment(event.occurredAtUtc);
        openSegment = _OpenSegment(
          taskText: event.taskText!,
          taskTextNormalized: event.taskTextNormalized!,
          startedAtUtc: event.occurredAtUtc,
          labelSeenAtUtc: event.occurredAtUtc,
        );
      } else if (event.eventType == ActivityEventType.stopTask) {
        closeOpenSegment(event.occurredAtUtc);
      }
    }

    closeOpenSegment(nowUtc);
    return segments;
  }

  static DailyReport buildDailyReport({
    required Iterable<ActivityLogEvent> events,
    required DateTime localDate,
    required DateTime nowUtc,
  }) {
    final selectedLocalDate = DateTime(
      localDate.year,
      localDate.month,
      localDate.day,
    );
    final nextLocalDate = DateTime(
      localDate.year,
      localDate.month,
      localDate.day + 1,
    );
    final dayStartUtc = selectedLocalDate.toUtc();
    final dayEndUtc = nextLocalDate.toUtc();
    final accumulators = <String, _ReportAccumulator>{};

    for (final segment in deriveSegments(events: events, nowUtc: nowUtc)) {
      final overlapStart = _maxDate(segment.startedAtUtc, dayStartUtc);
      final overlapEnd = _minDate(segment.endedAtUtc, dayEndUtc);

      if (!overlapEnd.isAfter(overlapStart)) {
        continue;
      }

      final duration = overlapEnd.difference(overlapStart);
      final accumulator = accumulators.putIfAbsent(
        segment.taskTextNormalized,
        () => _ReportAccumulator(
          taskText: segment.taskText,
          labelSeenAtUtc: segment.labelSeenAtUtc,
        ),
      );

      accumulator.duration += duration;
      if (!segment.labelSeenAtUtc.isBefore(accumulator.labelSeenAtUtc)) {
        accumulator.taskText = segment.taskText;
        accumulator.labelSeenAtUtc = segment.labelSeenAtUtc;
      }
    }

    final rows =
        accumulators.entries
            .map(
              (entry) => ReportRow(
                taskText: entry.value.taskText,
                taskTextNormalized: entry.key,
                duration: entry.value.duration,
              ),
            )
            .toList()
          ..sort((left, right) {
            final durationComparison = right.duration.compareTo(left.duration);
            if (durationComparison != 0) {
              return durationComparison;
            }

            return left.taskText.toLowerCase().compareTo(
              right.taskText.toLowerCase(),
            );
          });

    final totalDuration = rows.fold(
      Duration.zero,
      (total, row) => total + row.duration,
    );

    return DailyReport(
      localDate: selectedLocalDate,
      totalDuration: totalDuration,
      rows: rows,
    );
  }

  static DateTime _maxDate(DateTime left, DateTime right) {
    return left.isAfter(right) ? left : right;
  }

  static DateTime _minDate(DateTime left, DateTime right) {
    return left.isBefore(right) ? left : right;
  }
}

final class _OpenSegment {
  _OpenSegment({
    required this.taskText,
    required this.taskTextNormalized,
    required DateTime startedAtUtc,
    required DateTime labelSeenAtUtc,
  }) : startedAtUtc = startedAtUtc.toUtc(),
       labelSeenAtUtc = labelSeenAtUtc.toUtc();

  final String taskText;
  final String taskTextNormalized;
  final DateTime startedAtUtc;
  final DateTime labelSeenAtUtc;
}

final class _ReportAccumulator {
  _ReportAccumulator({required this.taskText, required this.labelSeenAtUtc});

  String taskText;
  DateTime labelSeenAtUtc;
  Duration duration = Duration.zero;
}
