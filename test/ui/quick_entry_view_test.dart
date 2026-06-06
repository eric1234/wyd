import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

    expect(find.text('Recent Tasks'), findsOneWidget);
    expect(find.text('Fix bug'), findsWidgets);
    expect(client.submittedTexts, ['Fix bug']);
  });

  testWidgets('Enter submits active task text with visible recent tasks', (
    tester,
  ) async {
    final client = _FakeQuickEntryClient();
    final controller = QuickEntryController(
      client: client,
      onSubmitted: (_) async {},
    );
    await controller.open(
      _snapshot(
        activeTask: _activeTask('Write docs'),
        recentSuggestions: [_suggestion('Fix bug')],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: QuickEntryView(controller: controller)),
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.text('Recent Tasks'), findsOneWidget);
    expect(find.text('Fix bug'), findsOneWidget);
    expect(client.submittedTexts, ['Write docs']);
  });

  testWidgets('does not overflow with five recent tasks in compact height', (
    tester,
  ) async {
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    await tester.binding.setSurfaceSize(
      const Size(WindowRoleConfiguration.quickEntryWidth, 304),
    );
    final controller = QuickEntryController(
      client: _FakeQuickEntryClient(),
      onSubmitted: (_) async {},
    );
    await controller.open(
      _snapshot(
        activeTask: _activeTask('Write docs'),
        recentSuggestions: List.generate(
          defaultAutocompleteSuggestionLimit,
          (index) => _suggestion('Task $index'),
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: QuickEntryView(controller: controller)),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Recent Tasks'), findsOneWidget);
  });

  testWidgets('does not overflow with high text scaling', (tester) async {
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    await tester.binding.setSurfaceSize(
      const Size(420, WindowRoleConfiguration.quickEntryHeight),
    );
    final controller = QuickEntryController(
      client: _FakeQuickEntryClient(),
      onSubmitted: (_) async {},
    );
    await controller.open(
      _snapshot(
        activeTask: _activeTask('Write docs'),
        recentSuggestions: List.generate(
          defaultAutocompleteSuggestionLimit,
          (index) => _suggestion('Task $index'),
        ),
      ),
    );

    await tester.pumpWidget(
      _scaledMaterialApp(home: QuickEntryView(controller: controller)),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Recent Tasks'), findsOneWidget);
  });

  testWidgets('stacks top controls when text scaling needs more width', (
    tester,
  ) async {
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    await tester.binding.setSurfaceSize(
      const Size(
        WindowRoleConfiguration.quickEntryWidth,
        WindowRoleConfiguration.quickEntryHeight,
      ),
    );
    final controller = QuickEntryController(
      client: _FakeQuickEntryClient(),
      onSubmitted: (_) async {},
    );
    await controller.open(_snapshot(activeTask: null));

    await tester.pumpWidget(
      _scaledMaterialApp(home: QuickEntryView(controller: controller)),
    );
    await tester.pump();

    final textFieldRect = tester.getRect(find.byType(TextField));
    final buttonRect = tester.getRect(find.byType(FilledButton));
    expect(buttonRect.top, greaterThan(textFieldRect.bottom));
  });

  testWidgets('pressing Enter submits raw task text from the field', (
    tester,
  ) async {
    final client = _FakeQuickEntryClient();
    final controller = QuickEntryController(
      client: client,
      onSubmitted: (_) async {},
    );
    await controller.open(_snapshot(activeTask: null));

    await tester.pumpWidget(
      MaterialApp(home: QuickEntryView(controller: controller)),
    );
    await tester.enterText(find.byType(TextField), 'Write docs');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(client.submittedTexts, ['Write docs']);
  });

  testWidgets('arrow keys move the highlighted suggestion', (tester) async {
    final client = _FakeQuickEntryClient(
      suggestions: [_suggestion('Fix bug'), _suggestion('Fix docs')],
    );
    final controller = QuickEntryController(
      client: client,
      onSubmitted: (_) async {},
    );
    await controller.open(_snapshot(activeTask: null));

    await tester.pumpWidget(
      MaterialApp(home: QuickEntryView(controller: controller)),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(controller.state.highlightedIndex, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();

    expect(controller.state.highlightedIndex, 0);
  });

  testWidgets('Enter accepts the highlighted suggestion and submits', (
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
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(client.submittedTexts, ['Fix bug']);
  });

  testWidgets('Escape clears highlighted suggestion before Enter submit', (
    tester,
  ) async {
    final client = _FakeQuickEntryClient(
      suggestions: [_suggestion('SPHY-494 - PR Review')],
    );
    final controller = QuickEntryController(
      client: client,
      onSubmitted: (_) async {},
    );
    await controller.open(_snapshot(activeTask: null));

    await tester.pumpWidget(
      MaterialApp(home: QuickEntryView(controller: controller)),
    );
    await tester.enterText(find.byType(TextField), 'PR Review');
    await tester.pump();

    expect(controller.state.highlightedIndex, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(controller.state.highlightedIndex, isNull);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(client.submittedTexts, ['PR Review']);
  });

  testWidgets('tapping a suggestion submits it immediately', (tester) async {
    final client = _FakeQuickEntryClient(suggestions: [_suggestion('Fix bug')]);
    final controller = QuickEntryController(
      client: client,
      onSubmitted: (_) async {},
    );
    await controller.open(_snapshot(activeTask: null));

    await tester.pumpWidget(
      MaterialApp(home: QuickEntryView(controller: controller)),
    );
    await tester.tap(find.text('Fix bug'));
    await tester.pump();

    expect(client.submittedTexts, ['Fix bug']);
  });
}

AppStateSnapshot _snapshot({
  ActiveTask? activeTask,
  List<AutocompleteSuggestion> recentSuggestions = const [],
}) {
  return AppStateSnapshot(
    activeTask: activeTask,
    runtimeState: RuntimeState(),
    settings: AppSettings.defaults,
    recentSuggestions: recentSuggestions,
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

Widget _scaledMaterialApp({required Widget home}) {
  return MaterialApp(
    builder: (context, child) {
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
        child: child ?? const SizedBox.shrink(),
      );
    },
    home: home,
  );
}
