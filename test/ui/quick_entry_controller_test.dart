import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/application/application.dart';
import 'package:wyd/src/domain/domain.dart';
import 'package:wyd/src/ui/quick_entry/quick_entry.dart';

void main() {
  group('QuickEntryController', () {
    test('opens idle with empty text and no select-all intent', () async {
      final client = _FakeQuickEntryClient();
      final controller = _controller(client);

      await controller.open(_snapshot(activeTask: null));

      expect(controller.state.isOpen, isTrue);
      expect(controller.state.text, isEmpty);
      expect(controller.state.selectAllOnOpen, isFalse);
    });

    test('opens active task with selected current text', () async {
      final client = _FakeQuickEntryClient();
      final controller = _controller(client);

      await controller.open(_snapshot(activeTask: _activeTask('Write docs')));

      expect(controller.state.text, 'Write docs');
      expect(controller.state.selectAllOnOpen, isTrue);
    });

    test('reopening while open preserves partial input', () async {
      final client = _FakeQuickEntryClient();
      final controller = _controller(client);

      await controller.open(_snapshot(activeTask: _activeTask('Write docs')));
      await controller.updateText('Partially typed');
      await controller.open(_snapshot(activeTask: _activeTask('Write docs')));

      expect(controller.state.text, 'Partially typed');
      expect(controller.state.selectAllOnOpen, isFalse);
    });

    test('loads suggestions and auto-highlights the first result', () async {
      final client = _FakeQuickEntryClient(
        suggestions: [_suggestion('Fix bug'), _suggestion('Fix docs')],
      );
      final controller = _controller(client);

      await controller.open(_snapshot(activeTask: null));
      await controller.updateText('fix');

      expect(
        controller.state.suggestions.map((suggestion) => suggestion.taskText),
        ['Fix bug', 'Fix docs'],
      );
      expect(controller.state.highlightedIndex, 0);
    });

    test('moves highlighted suggestion with wrapping', () async {
      final client = _FakeQuickEntryClient(
        suggestions: [_suggestion('One'), _suggestion('Two')],
      );
      final controller = _controller(client);
      await controller.open(_snapshot(activeTask: null));

      controller.moveHighlight(1);
      controller.moveHighlight(1);
      controller.moveHighlight(-1);

      expect(controller.state.highlightedIndex, 1);
    });

    test('rejects empty submissions without calling the client', () async {
      final client = _FakeQuickEntryClient();
      final controller = _controller(client);
      await controller.open(_snapshot(activeTask: null));

      await controller.submit();

      expect(controller.state.validationMessage, 'Task text cannot be empty.');
      expect(client.submittedTexts, isEmpty);
    });

    test(
      'submits highlighted suggestion text and closes after success',
      () async {
        AppStateSnapshot? submittedSnapshot;
        final client = _FakeQuickEntryClient(
          suggestions: [_suggestion('Fix bug')],
        );
        final controller = _controller(
          client,
          onSubmitted: (snapshot) async => submittedSnapshot = snapshot,
        );
        await controller.open(_snapshot(activeTask: null));
        await controller.updateText('fi');

        await controller.submit();

        expect(client.submittedTexts, ['Fix bug']);
        expect(controller.state.isOpen, isFalse);
        expect(submittedSnapshot, isNotNull);
      },
    );

    test('submits raw text when no suggestion is highlighted', () async {
      final client = _FakeQuickEntryClient();
      final controller = _controller(client);
      await controller.open(_snapshot(activeTask: null));
      await controller.updateText('Write docs');

      await controller.submit();

      expect(client.submittedTexts, ['Write docs']);
    });

    test('ignores stale autocomplete responses after newer input', () async {
      final client = _DelayedQuickEntryClient();
      final controller = _controller(client);
      await controller.open(_snapshot(activeTask: _activeTask('Existing')));

      final firstUpdate = controller.updateText('f');
      await client.waitForRequests(1);
      final secondUpdate = controller.updateText('fi');
      await client.waitForRequests(2);

      client.completeRequest(0, [_suggestion('Old result')]);
      await firstUpdate;
      expect(controller.state.suggestions, isEmpty);

      client.completeRequest(1, [_suggestion('Fresh result')]);
      await secondUpdate;
      expect(controller.state.suggestions.single.taskText, 'Fresh result');
    });

    test('ignores stale autocomplete responses after close', () async {
      final client = _DelayedQuickEntryClient();
      final controller = _controller(client);
      await controller.open(_snapshot(activeTask: _activeTask('Existing')));

      final update = controller.updateText('f');
      await client.waitForRequests(1);
      controller.close();
      client.completeRequest(0, [_suggestion('Ignored result')]);
      await update;

      expect(controller.state.isOpen, isFalse);
      expect(controller.state.suggestions, isEmpty);
    });
  });
}

QuickEntryController _controller(
  QuickEntryClient client, {
  Future<void> Function(AppStateSnapshot snapshot)? onSubmitted,
}) {
  return QuickEntryController(
    client: client,
    onSubmitted: onSubmitted ?? (_) async {},
  );
}

AppStateSnapshot _snapshot({ActiveTask? activeTask}) {
  return AppStateSnapshot(
    activeTask: activeTask,
    runtimeState: RuntimeState(),
    settings: AppSettings.defaults,
  );
}

ActiveTask _activeTask(String text) {
  return ActiveTask(
    taskText: text,
    taskTextNormalized: TaskText.normalizeForEquality(text),
    startedAtUtc: DateTime.utc(2026, 1, 1, 9),
    sourceEventId: 1,
  );
}

AutocompleteSuggestion _suggestion(String text) {
  return AutocompleteSuggestion(
    taskText: text,
    taskTextNormalized: TaskText.normalizeForEquality(text),
    lastUsedAtUtc: DateTime.utc(2026, 1, 1, 9),
    matchType: AutocompleteMatchType.prefix,
  );
}

final class _FakeQuickEntryClient implements QuickEntryClient {
  _FakeQuickEntryClient({this.suggestions = const []});

  final List<AutocompleteSuggestion> suggestions;
  final List<String> submittedTexts = [];

  @override
  Future<List<AutocompleteSuggestion>> autocompleteSuggestions(
    String query,
  ) async {
    return suggestions;
  }

  @override
  Future<AppStateSnapshot> submitTask(String taskText) async {
    submittedTexts.add(taskText);
    return _snapshot(activeTask: _activeTask(taskText));
  }
}

final class _DelayedQuickEntryClient implements QuickEntryClient {
  final List<_SuggestionRequest> requests = [];
  final List<String> submittedTexts = [];

  @override
  Future<List<AutocompleteSuggestion>> autocompleteSuggestions(String query) {
    final request = _SuggestionRequest(query);
    requests.add(request);
    return request.completer.future;
  }

  @override
  Future<AppStateSnapshot> submitTask(String taskText) async {
    submittedTexts.add(taskText);
    return _snapshot(activeTask: _activeTask(taskText));
  }

  Future<void> waitForRequests(int count) async {
    for (
      var attempt = 0;
      attempt < 20 && requests.length < count;
      attempt += 1
    ) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(requests, hasLength(count));
  }

  void completeRequest(int index, List<AutocompleteSuggestion> suggestions) {
    requests[index].completer.complete(suggestions);
  }
}

final class _SuggestionRequest {
  _SuggestionRequest(this.query);

  final String query;
  final Completer<List<AutocompleteSuggestion>> completer = Completer();
}
