import 'package:flutter/foundation.dart';

import '../../application/application.dart';
import '../../domain/domain.dart';

abstract interface class QuickEntryClient {
  Future<AppStateSnapshot> submitTask(String taskText);

  Future<List<AutocompleteSuggestion>> autocompleteSuggestions(String query);
}

final class TrackerQuickEntryClient implements QuickEntryClient {
  const TrackerQuickEntryClient(this._trackerService);

  final TrackerService _trackerService;

  @override
  Future<AppStateSnapshot> submitTask(String taskText) {
    return _trackerService.submitTask(taskText);
  }

  @override
  Future<List<AutocompleteSuggestion>> autocompleteSuggestions(String query) {
    return _trackerService.autocompleteSuggestions(query);
  }
}

final class QuickEntryState {
  const QuickEntryState({
    this.isOpen = false,
    this.text = '',
    this.suggestions = const [],
    this.highlightedIndex,
    this.validationMessage,
    this.busy = false,
    this.selectAllOnOpen = false,
  });

  final bool isOpen;
  final String text;
  final List<AutocompleteSuggestion> suggestions;
  final int? highlightedIndex;
  final String? validationMessage;
  final bool busy;
  final bool selectAllOnOpen;

  AutocompleteSuggestion? get highlightedSuggestion {
    final index = highlightedIndex;
    if (index == null || index < 0 || index >= suggestions.length) {
      return null;
    }

    return suggestions[index];
  }

  QuickEntryState copyWith({
    bool? isOpen,
    String? text,
    List<AutocompleteSuggestion>? suggestions,
    int? highlightedIndex,
    bool clearHighlightedIndex = false,
    String? validationMessage,
    bool clearValidationMessage = false,
    bool? busy,
    bool? selectAllOnOpen,
  }) {
    return QuickEntryState(
      isOpen: isOpen ?? this.isOpen,
      text: text ?? this.text,
      suggestions: suggestions ?? this.suggestions,
      highlightedIndex: clearHighlightedIndex
          ? null
          : highlightedIndex ?? this.highlightedIndex,
      validationMessage: clearValidationMessage
          ? null
          : validationMessage ?? this.validationMessage,
      busy: busy ?? this.busy,
      selectAllOnOpen: selectAllOnOpen ?? this.selectAllOnOpen,
    );
  }
}

final class QuickEntryController extends ChangeNotifier {
  QuickEntryController({
    required QuickEntryClient client,
    required Future<void> Function(AppStateSnapshot snapshot) onSubmitted,
  }) : _client = client,
       _onSubmitted = onSubmitted;

  final QuickEntryClient _client;
  final Future<void> Function(AppStateSnapshot snapshot) _onSubmitted;

  QuickEntryState _state = const QuickEntryState();
  int _suggestionRequest = 0;

  QuickEntryState get state => _state;

  Future<void> open(AppStateSnapshot snapshot) async {
    if (_state.isOpen) {
      _setState(_state.copyWith(selectAllOnOpen: false));
      return;
    }

    final activeTask = snapshot.activeTask;
    final initialText = activeTask?.taskText ?? '';
    final initialSuggestions = snapshot.recentSuggestions;
    final shouldHighlightFirstSuggestion = initialText.isEmpty;
    _setState(
      QuickEntryState(
        isOpen: true,
        text: initialText,
        suggestions: initialSuggestions,
        highlightedIndex:
            shouldHighlightFirstSuggestion && initialSuggestions.isNotEmpty
            ? 0
            : null,
        selectAllOnOpen: initialText.isNotEmpty,
      ),
    );
    if (activeTask == null) {
      await refreshSuggestions();
    }
  }

  void close() {
    _suggestionRequest += 1;
    _setState(
      _state.copyWith(
        isOpen: false,
        busy: false,
        selectAllOnOpen: false,
        clearValidationMessage: true,
      ),
    );
  }

  Future<void> updateText(String text) async {
    _setState(
      _state.copyWith(
        text: text,
        suggestions: const [],
        clearHighlightedIndex: true,
        selectAllOnOpen: false,
        clearValidationMessage: true,
      ),
    );
    await refreshSuggestions();
  }

  Future<void> refreshSuggestions() async {
    final request = ++_suggestionRequest;
    final query = _state.text;
    final filteredSuggestions = await _client.autocompleteSuggestions(query);
    if (request != _suggestionRequest || !_state.isOpen) {
      return;
    }

    final showRecentTasks = _shouldShowRecentTasksForExactInput(
      query,
      filteredSuggestions,
    );
    final suggestions = showRecentTasks
        ? await _recentSuggestionsOrFallback(
            request: request,
            fallback: filteredSuggestions,
          )
        : filteredSuggestions;
    if (suggestions == null) {
      return;
    }

    final shouldHighlightFirstSuggestion =
        suggestions.isNotEmpty && !showRecentTasks;

    _setState(
      _state.copyWith(
        suggestions: suggestions,
        highlightedIndex: shouldHighlightFirstSuggestion ? 0 : null,
        clearHighlightedIndex: !shouldHighlightFirstSuggestion,
      ),
    );
  }

  void moveHighlight(int delta) {
    final suggestions = _state.suggestions;
    if (suggestions.isEmpty) {
      _setState(_state.copyWith(clearHighlightedIndex: true));
      return;
    }

    final current = _state.highlightedIndex;
    if (current == null) {
      _setState(
        _state.copyWith(
          highlightedIndex: delta < 0 ? suggestions.length - 1 : 0,
        ),
      );
      return;
    }

    final next = (current + delta) % suggestions.length;
    _setState(
      _state.copyWith(
        highlightedIndex: next < 0 ? next + suggestions.length : next,
      ),
    );
  }

  Future<void> acceptSuggestion(int index, {bool submitNow = false}) async {
    if (index < 0 || index >= _state.suggestions.length) {
      return;
    }

    _setState(
      _state.copyWith(
        text: _state.suggestions[index].taskText,
        highlightedIndex: index,
        clearValidationMessage: true,
      ),
    );

    if (submitNow) {
      await submit();
    }
  }

  Future<void> submit() async {
    if (_state.busy) {
      return;
    }

    final highlightedSuggestion = _state.highlightedSuggestion;
    final submittedText = highlightedSuggestion?.taskText ?? _state.text;

    try {
      TaskText.fromInput(submittedText);
    } on TaskTextValidationException catch (error) {
      _setState(_state.copyWith(validationMessage: error.message));
      return;
    }

    _setState(
      _state.copyWith(
        text: submittedText,
        busy: true,
        clearValidationMessage: true,
      ),
    );

    try {
      final snapshot = await _client.submitTask(submittedText);
      close();
      await _onSubmitted(snapshot);
    } on TaskTextValidationException catch (error) {
      _setState(_state.copyWith(busy: false, validationMessage: error.message));
    } catch (error) {
      _setState(
        _state.copyWith(busy: false, validationMessage: error.toString()),
      );
    }
  }

  void _setState(QuickEntryState state) {
    _state = state;
    notifyListeners();
  }

  bool _shouldShowRecentTasksForExactInput(
    String query,
    List<AutocompleteSuggestion> filteredSuggestions,
  ) {
    final queryNormalized = TaskText.normalizeForEquality(query);
    return queryNormalized.isNotEmpty &&
        filteredSuggestions.length == 1 &&
        filteredSuggestions.single.taskTextNormalized == queryNormalized;
  }

  Future<List<AutocompleteSuggestion>?> _recentSuggestionsOrFallback({
    required int request,
    required List<AutocompleteSuggestion> fallback,
  }) async {
    final recentSuggestions = await _client.autocompleteSuggestions('');
    if (request != _suggestionRequest || !_state.isOpen) {
      return null;
    }

    return recentSuggestions.isEmpty ? fallback : recentSuggestions;
  }
}
