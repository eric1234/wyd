import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/ui/layout_metrics.dart';

void main() {
  group('WydTextScaleAdjustment', () {
    test('leaves non-Linux platforms unchanged', () {
      final adjustment = WydTextScaleAdjustment.resolve(
        isLinux: false,
        environment: const {'XDG_CURRENT_DESKTOP': 'KDE'},
        devicePixelRatio: 2,
        textScale: 2,
      );

      expect(adjustment.adjusted, isFalse);
      expect(adjustment.adjustedTextScale, 2);
    });

    test('leaves non-KDE Linux desktops unchanged', () {
      final adjustment = WydTextScaleAdjustment.resolve(
        isLinux: true,
        environment: const {'XDG_CURRENT_DESKTOP': 'X-Cinnamon'},
        devicePixelRatio: 2,
        textScale: 2,
      );

      expect(adjustment.adjusted, isFalse);
      expect(adjustment.adjustedTextScale, 2);
    });

    test('leaves independent text scaling unchanged', () {
      final adjustment = WydTextScaleAdjustment.resolve(
        isLinux: true,
        environment: const {'XDG_CURRENT_DESKTOP': 'KDE'},
        devicePixelRatio: 2,
        textScale: 1.2,
      );

      expect(adjustment.adjusted, isFalse);
      expect(adjustment.adjustedTextScale, 1.2);
    });

    test('normalizes KDE duplicated display scale', () {
      final adjustment = WydTextScaleAdjustment.resolve(
        isLinux: true,
        environment: const {'XDG_CURRENT_DESKTOP': 'KDE'},
        devicePixelRatio: 2,
        textScale: 2,
      );

      expect(adjustment.adjusted, isTrue);
      expect(adjustment.adjustedTextScale, 1);
      expect(adjustment.reason, 'kde-duplicates-display-scale');
    });

    test('preserves text scaling beyond duplicated KDE display scale', () {
      final adjustment = WydTextScaleAdjustment.resolve(
        isLinux: true,
        environment: const {'XDG_SESSION_DESKTOP': 'plasma'},
        devicePixelRatio: 2,
        textScale: 2.4,
      );

      expect(adjustment.adjusted, isTrue);
      expect(adjustment.adjustedTextScale, 1.2);
    });
  });
}
