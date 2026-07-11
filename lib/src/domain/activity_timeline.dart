import 'active_task.dart';
import 'activity_log.dart';
import 'autocomplete.dart';
import 'lifecycle.dart';
import 'report.dart';
import 'task_text.dart';

final class ActivityTimeline {
  ActivityTimeline(Iterable<ActivityLogEvent> events)
    : events = List.unmodifiable(orderActivityEvents(events));

  final List<ActivityLogEvent> events;

  ActiveTask? get activeTask {
    ActiveTask? activeTask;

    for (final event in events) {
      if (event.opensTask && event.hasTaskText) {
        activeTask = ActiveTask.fromEvent(event);
      } else if (event.eventType == ActivityEventType.stopTask) {
        activeTask = null;
      }
    }

    return activeTask;
  }

  SubmitTaskResult submitTask({
    required String taskText,
    required DateTime occurredAtUtc,
    DateTime? createdAtUtc,
    int id = 0,
  }) {
    final submittedTask = TaskText.fromInput(taskText);
    final currentTask = activeTask;

    if (currentTask == null) {
      return TaskStarted(
        submittedTask: submittedTask,
        event: ActivityLogEvent.startTask(
          id: id,
          occurredAtUtc: occurredAtUtc,
          taskText: submittedTask.value,
          createdAtUtc: createdAtUtc,
        ),
      );
    }

    if (currentTask.taskTextNormalized == submittedTask.normalized) {
      return TaskConfirmed(submittedTask: submittedTask);
    }

    return TaskSwitched(
      submittedTask: submittedTask,
      event: ActivityLogEvent.switchTask(
        id: id,
        occurredAtUtc: occurredAtUtc,
        taskText: submittedTask.value,
        createdAtUtc: createdAtUtc,
      ),
    );
  }

  StopTaskResult stopTask({
    required DateTime occurredAtUtc,
    required ActivitySource source,
    DateTime? createdAtUtc,
    int id = 0,
  }) {
    if (activeTask == null) {
      return const NoActiveTaskToStop();
    }

    return TaskStopped(
      ActivityLogEvent.stopTask(
        id: id,
        occurredAtUtc: occurredAtUtc,
        source: source,
        createdAtUtc: createdAtUtc,
      ),
    );
  }

  List<ReportSegment> deriveSegments({required DateTime nowUtc}) {
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

    for (final event in events) {
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

  ActivityReport buildReport({
    required ReportDateRange dateRange,
    required DateTime nowUtc,
  }) {
    final rangeStartUtc = dateRange.startLocalDateInclusive.toUtc();
    final rangeEndUtc = dateRange.endLocalDateExclusive.toUtc();
    final accumulators = <String, _ReportAccumulator>{};

    for (final segment in deriveSegments(nowUtc: nowUtc)) {
      final overlapStart = _maxDate(segment.startedAtUtc, rangeStartUtc);
      final overlapEnd = _minDate(segment.endedAtUtc, rangeEndUtc);

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

    return ActivityReport(totalDuration: totalDuration, rows: rows);
  }

  List<AutocompleteSuggestion> autocompleteSuggestions({
    required String query,
    required DateTime nowUtc,
    required int lookbackDays,
    int limit = defaultAutocompleteSuggestionLimit,
  }) {
    if (limit <= 0) {
      return const [];
    }

    final now = nowUtc.toUtc();
    final cutoff = now.subtract(Duration(days: lookbackDays));
    final queryNormalized = TaskText.normalizeForEquality(query);
    final mostRecentByTask = <String, _AutocompleteCandidate>{};

    for (final event in events.reversed) {
      if (!event.opensTask || !event.hasTaskText) {
        continue;
      }
      if (event.occurredAtUtc.isAfter(now) ||
          event.occurredAtUtc.isBefore(cutoff)) {
        continue;
      }

      final normalized = event.taskTextNormalized!;
      mostRecentByTask.putIfAbsent(
        normalized,
        () => _AutocompleteCandidate(
          taskText: event.taskText!,
          taskTextNormalized: normalized,
          lastUsedAtUtc: event.occurredAtUtc,
        ),
      );
    }

    final matches = <AutocompleteSuggestion>[];
    for (final candidate in mostRecentByTask.values) {
      final matchType = _matchType(
        candidate.taskTextNormalized,
        queryNormalized,
      );
      if (matchType == null) {
        continue;
      }

      matches.add(
        AutocompleteSuggestion(
          taskText: candidate.taskText,
          taskTextNormalized: candidate.taskTextNormalized,
          lastUsedAtUtc: candidate.lastUsedAtUtc,
          matchType: matchType,
        ),
      );
    }

    matches.sort((left, right) {
      final matchComparison = left.matchType.index.compareTo(
        right.matchType.index,
      );
      if (matchComparison != 0) {
        return matchComparison;
      }

      final recencyComparison = right.lastUsedAtUtc.compareTo(
        left.lastUsedAtUtc,
      );
      if (recencyComparison != 0) {
        return recencyComparison;
      }

      return left.taskText.toLowerCase().compareTo(
        right.taskText.toLowerCase(),
      );
    });

    return matches.take(limit).toList();
  }

  static AutocompleteMatchType? _matchType(
    String candidateNormalized,
    String queryNormalized,
  ) {
    if (queryNormalized.isEmpty ||
        candidateNormalized.startsWith(queryNormalized)) {
      return AutocompleteMatchType.prefix;
    }

    if (candidateNormalized.contains(queryNormalized)) {
      return AutocompleteMatchType.substring;
    }

    return null;
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

final class _AutocompleteCandidate {
  _AutocompleteCandidate({
    required this.taskText,
    required this.taskTextNormalized,
    required this.lastUsedAtUtc,
  });

  final String taskText;
  final String taskTextNormalized;
  final DateTime lastUsedAtUtc;
}
