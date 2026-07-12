final class TaskTag {
  const TaskTag._({required this.text, required this.normalized});

  factory TaskTag.fromInput(String input) {
    final text = sanitizeForStorage(input);
    if (text.isEmpty) {
      throw const TaskTagValidationException('Tag cannot be empty.');
    }
    if (text.length > maxLength) {
      throw const TaskTagValidationException(
        'Tag must be 64 characters or fewer.',
      );
    }

    return TaskTag._(text: text, normalized: normalizeForEquality(text));
  }

  factory TaskTag.hydrate({required String text, required String normalized}) {
    return TaskTag._(text: text, normalized: normalized);
  }

  static const maxLength = 64;

  final String text;
  final String normalized;

  static String sanitizeForStorage(String input) {
    return trimAsciiWhitespace(removeNewlines(input));
  }

  static String normalizeForEquality(String input) {
    final sanitized = sanitizeForStorage(input);
    return sanitized.replaceAll(RegExp(r'[ \t]+'), ' ').toLowerCase();
  }

  static bool equalsNormalized(String left, String right) {
    return normalizeForEquality(left) == normalizeForEquality(right);
  }

  static String removeNewlines(String input) {
    final buffer = StringBuffer();

    for (final rune in input.runes) {
      if (_isNewlineRune(rune)) {
        continue;
      }

      buffer.writeCharCode(rune);
    }

    return buffer.toString();
  }

  static String trimAsciiWhitespace(String input) {
    var start = 0;
    var end = input.length;

    while (start < end && _isAsciiWhitespace(input.codeUnitAt(start))) {
      start += 1;
    }

    while (end > start && _isAsciiWhitespace(input.codeUnitAt(end - 1))) {
      end -= 1;
    }

    return input.substring(start, end);
  }

  @override
  bool operator ==(Object other) {
    return other is TaskTag &&
        text == other.text &&
        normalized == other.normalized;
  }

  @override
  int get hashCode => Object.hash(text, normalized);

  @override
  String toString() => text;

  static bool _isNewlineRune(int rune) {
    return rune == 0x0a ||
        rune == 0x0d ||
        rune == 0x85 ||
        rune == 0x2028 ||
        rune == 0x2029;
  }

  static bool _isAsciiWhitespace(int codeUnit) {
    return codeUnit == 0x20 || (codeUnit >= 0x09 && codeUnit <= 0x0d);
  }
}

final class TaskTagValidationException implements Exception {
  const TaskTagValidationException(this.message);

  final String message;

  @override
  String toString() => 'TaskTagValidationException: $message';
}
