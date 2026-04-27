final class TaskText {
  TaskText._({required this.value, required this.normalized});

  factory TaskText.fromInput(String input) {
    final value = sanitizeForStorage(input);
    if (value.isEmpty) {
      throw const TaskTextValidationException('Task text cannot be empty.');
    }

    return TaskText._(value: value, normalized: normalizeForEquality(value));
  }

  final String value;
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

  @override
  String toString() => value;
}

final class TaskTextValidationException implements Exception {
  const TaskTextValidationException(this.message);

  final String message;

  @override
  String toString() => 'TaskTextValidationException: $message';
}
