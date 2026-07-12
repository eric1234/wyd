import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/domain/domain.dart';

void main() {
  group('TaskTag', () {
    test('sanitizes display text and normalizes equality key', () {
      final tag = TaskTag.fromInput('  Customer   Fire  ');

      expect(tag.text, 'Customer   Fire');
      expect(tag.normalized, 'customer fire');
    });

    test('removes newlines before storage', () {
      final tag = TaskTag.fromInput('Bug\nFix\rTag');

      expect(tag.text, 'BugFixTag');
      expect(tag.normalized, 'bugfixtag');
    });

    test('compares normalized casing and spacing', () {
      expect(TaskTag.equalsNormalized('  Bug   Fix ', 'bug fix'), isTrue);
      expect(TaskTag.equalsNormalized('bug', 'feature'), isFalse);
    });

    test('rejects empty tags', () {
      expect(
        () => TaskTag.fromInput(' \t\n '),
        throwsA(isA<TaskTagValidationException>()),
      );
    });

    test('rejects tags longer than max length', () {
      expect(
        () => TaskTag.fromInput(''.padRight(TaskTag.maxLength + 1, 'a')),
        throwsA(isA<TaskTagValidationException>()),
      );
    });
  });
}
