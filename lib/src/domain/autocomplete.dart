const defaultAutocompleteSuggestionLimit = 5;

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
