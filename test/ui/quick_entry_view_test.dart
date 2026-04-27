import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/application/application.dart';
import 'package:wyd/src/domain/domain.dart';
import 'package:wyd/src/ui/quick_entry/quick_entry.dart';

void main() {
  testWidgets('focuses and selects active task text on open', (tester) async {
    final controller = QuickEntryController(
      client: _FakeQuickEntryClient(),
      onSubmitted: (_) async {},
    );
    await controller.open(_snapshot(activeTask: _activeTask('Write docs')));

    await tester.pumpWidget(
      MaterialApp(home: QuickEntryView(controller: controller)),
    );
    await tester.pump();

    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);
    expect(editable.controller.selection.baseOffset, 0);
    expect(editable.controller.selection.extentOffset, 'Write docs'.length);
  });

  testWidgets('shows validation message for empty submit', (tester) async {
    final controller = QuickEntryController(
      client: _FakeQuickEntryClient(),
      onSubmitted: (_) async {},
    );
    await controller.open(_snapshot(activeTask: null));

    await tester.pumpWidget(
      MaterialApp(home: QuickEntryView(controller: controller)),
    );
    await tester.tap(find.text('Submit'));
    await tester.pump();

    expect(find.text('Task text cannot be empty.'), findsOneWidget);
  });

  testWidgets('renders suggestions and submits the highlighted suggestion', (
    tester,
  ) async {
    final client = _FakeQuickEntryClient(suggestions: [_suggestion('Fix bug')]);
    final controller = QuickEntryController(
      client: client,
      onSubmitted: (_) async {},
    );
    await controller.open(_snapshot(activeTask: null));

    await tester.pumpWidget(
      MaterialApp(home: QuickEntryView(controller: controller)),
    );
    await tester.enterText(find.byType(TextField), 'fi');
    await tester.pump();
    await tester.tap(find.text('Submit'));
    await tester.pump();

    expect(find.text('Fix bug'), findsWidgets);
    expect(client.submittedTexts, ['Fix bug']);
  });
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
