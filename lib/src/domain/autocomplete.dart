import 'activity_log.dart';
import 'task_text.dart';

enum AutocompleteMatchType { prefix, substring }

final class AutocompleteSuggestion {
  AutocompleteSuggestion({
    required this.taskText,
    required this.taskTextNormalized,
    required DateTime lastUsedAtUtc,
    required this.matchType,
  }) : lastUsedAtUtc = lastUsedAtUtc.toUtc();

  final String taskText;
  final String taskTextNormalized;
  final DateTime lastUsedAtUtc;
  final AutocompleteMatchType matchType;
}

final class AutocompleteEngine {
  const AutocompleteEngine._();

  static const defaultSuggestionLimit = 5;

  static List<AutocompleteSuggestion> suggestions({
    required Iterable<ActivityLogEvent> events,
    required String query,
    required DateTime nowUtc,
    required int lookbackDays,
    int limit = defaultSuggestionLimit,
  }) {
    if (limit <= 0) {
      return const [];
    }

    final now = nowUtc.toUtc();
    final cutoff = now.subtract(Duration(days: lookbackDays));
    final queryNormalized = TaskText.normalizeForEquality(query);
    final mostRecentByTask = <String, _AutocompleteCandidate>{};
    final recentEvents = orderActivityEvents(events).reversed;

    for (final event in recentEvents) {
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
          eventId: event.id,
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
}

final class _AutocompleteCandidate {
  _AutocompleteCandidate({
    required this.taskText,
    required this.taskTextNormalized,
    required this.lastUsedAtUtc,
    required this.eventId,
  });

  final String taskText;
  final String taskTextNormalized;
  final DateTime lastUsedAtUtc;
  final int eventId;
}
