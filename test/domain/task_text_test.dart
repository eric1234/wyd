import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/domain/domain.dart';

void main() {
  group('TaskText', () {
    test('removes pasted newlines and trims ASCII whitespace for storage', () {
      final taskText = TaskText.fromInput(' \tFix\nbug\rnow\t ');

      expect(taskText.value, 'Fixbugnow');
      expect(taskText.normalized, 'fixbugnow');
    });

    test('collapses internal ASCII spaces and tabs only for equality', () {
      final taskText = TaskText.fromInput('  Write\t \tDocs  ');

      expect(taskText.value, 'Write\t \tDocs');
      expect(taskText.normalized, 'write docs');
    });

    test('preserves punctuation and non-ASCII characters', () {
      final taskText = TaskText.fromInput('  !!!Café\u00a0\u200b  ');

      expect(taskText.value, '!!!Café\u00a0\u200b');
      expect(taskText.normalized, '!!!café\u00a0\u200b');
    });

    test('does not trim non-breaking spaces as ASCII whitespace', () {
      final taskText = TaskText.fromInput('\u00a0');

      expect(taskText.value, '\u00a0');
      expect(taskText.normalized, '\u00a0');
    });

    test('rejects text that is empty after newline removal and ASCII trim', () {
      expect(
        () => TaskText.fromInput(' \t\n\r '),
        throwsA(isA<TaskTextValidationException>()),
      );
    });

    test('compares normalized task text case-insensitively', () {
      expect(TaskText.equalsNormalized(' Fix\tBug ', 'fix bug'), isTrue);
    });
  });
}
