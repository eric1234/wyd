import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/application/application.dart';
import 'package:wyd/src/infrastructure/desktop/desktop.dart';

void main() {
  group('role window argument encoding', () {
    test('round-trips role and show-on-ready flag', () {
      final arguments = encodeRoleWindowArguments(
        WindowRole.report,
        showOnReady: false,
      );

      expect(decodeRoleWindowRole(arguments), WindowRole.report);
      expect(decodeRoleWindowShowOnReady(arguments), isFalse);
    });

    test('returns null role for invalid arguments', () {
      expect(decodeRoleWindowRole(''), isNull);
      expect(decodeRoleWindowRole('not-json'), isNull);
      expect(decodeRoleWindowRole('{"kind":"other","role":"report"}'), isNull);
      expect(
        decodeRoleWindowRole('{"kind":"wyd-role-window","role":"missing"}'),
        isNull,
      );
    });

    test('defaults show-on-ready to true for invalid arguments', () {
      expect(decodeRoleWindowShowOnReady(''), isTrue);
      expect(decodeRoleWindowShowOnReady('not-json'), isTrue);
      expect(decodeRoleWindowShowOnReady('{"kind":"wyd-role-window"}'), isTrue);
    });
  });

  group('role window configuration encoding', () {
    test('round-trips window configuration maps', () {
      final configuration = WindowRoleConfiguration.quickEntry();

      final decoded = decodeRoleWindowConfiguration(
        encodeRoleWindowConfiguration(configuration),
      );

      expect(decoded.role, configuration.role);
      expect(decoded.title, configuration.title);
      expect(decoded.width, configuration.width);
      expect(decoded.height, configuration.height);
      expect(decoded.resizable, configuration.resizable);
      expect(decoded.alwaysOnTop, configuration.alwaysOnTop);
    });
  });
}
