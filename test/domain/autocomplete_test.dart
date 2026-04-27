import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/domain/domain.dart';

void main() {
  group('AutocompleteEngine', () {
    test('deduplicates by normalized text and keeps most recent raw label', () {
      final now = DateTime.utc(2026, 1, 10, 12);
      final suggestions = AutocompleteEngine.suggestions(
        events: [
          ActivityLogEvent.startTask(
            id: 1,
            occurredAtUtc: now.subtract(const Duration(days: 2)),
            taskText: 'Fix   Bug',
          ),
          ActivityLogEvent.switchTask(
            id: 2,
            occurredAtUtc: now.subtract(const Duration(hours: 1)),
            taskText: 'fix bug',
          ),
        ],
        query: 'fi',
        nowUtc: now,
        lookbackDays: 3,
      );

      expect(suggestions, hasLength(1));
      expect(suggestions.single.taskText, 'fix bug');
      expect(suggestions.single.taskTextNormalized, 'fix bug');
    });

    test('ranks prefix matches before newer substring matches', () {
      final now = DateTime.utc(2026, 1, 10, 12);
      final suggestions = AutocompleteEngine.suggestions(
        events: [
          ActivityLogEvent.startTask(
            id: 1,
            occurredAtUtc: now.subtract(const Duration(hours: 3)),
            taskText: 'Bug triage',
          ),
          ActivityLogEvent.switchTask(
            id: 2,
            occurredAtUtc: now.subtract(const Duration(minutes: 10)),
            taskText: 'Investigate bug',
          ),
        ],
        query: 'bug',
        nowUtc: now,
        lookbackDays: 3,
      );

      expect(suggestions.map((suggestion) => suggestion.taskText), [
        'Bug triage',
        'Investigate bug',
      ]);
      expect(suggestions.first.matchType, AutocompleteMatchType.prefix);
      expect(suggestions.last.matchType, AutocompleteMatchType.substring);
    });

    test('orders matches by recency within the same match class', () {
      final now = DateTime.utc(2026, 1, 10, 12);
      final suggestions = AutocompleteEngine.suggestions(
        events: [
          ActivityLogEvent.startTask(
            id: 1,
            occurredAtUtc: now.subtract(const Duration(hours: 4)),
            taskText: 'Fix docs',
          ),
          ActivityLogEvent.switchTask(
            id: 2,
            occurredAtUtc: now.subtract(const Duration(hours: 1)),
            taskText: 'Fix bug',
          ),
        ],
        query: 'fix',
        nowUtc: now,
        lookbackDays: 3,
      );

      expect(suggestions.map((suggestion) => suggestion.taskText), [
        'Fix bug',
        'Fix docs',
      ]);
    });

    test('ignores stop events and events outside the lookback window', () {
      final now = DateTime.utc(2026, 1, 10, 12);
      final suggestions = AutocompleteEngine.suggestions(
        events: [
          ActivityLogEvent.startTask(
            id: 1,
            occurredAtUtc: now.subtract(const Duration(days: 4)),
            taskText: 'Old task',
          ),
          ActivityLogEvent.stopTask(
            id: 2,
            occurredAtUtc: now.subtract(const Duration(minutes: 5)),
            source: ActivitySource.manualStop,
          ),
          ActivityLogEvent.switchTask(
            id: 3,
            occurredAtUtc: now.subtract(const Duration(minutes: 1)),
            taskText: 'New task',
          ),
        ],
        query: 'task',
        nowUtc: now,
        lookbackDays: 3,
      );

      expect(suggestions.map((suggestion) => suggestion.taskText), [
        'New task',
      ]);
    });

    test('limits results to five suggestions', () {
      final now = DateTime.utc(2026, 1, 10, 12);
      final events = List.generate(
        6,
        (index) => ActivityLogEvent.startTask(
          id: index + 1,
          occurredAtUtc: now.subtract(Duration(minutes: index)),
          taskText: 'Task $index',
        ),
      );

      final suggestions = AutocompleteEngine.suggestions(
        events: events,
        query: '',
        nowUtc: now,
        lookbackDays: 3,
      );

      expect(suggestions, hasLength(5));
    });
  });
}
