import 'dart:math' as math;

import 'package:flutter/material.dart';

final class WydTextScaleAdjustment {
  const WydTextScaleAdjustment._({
    required this.adjustedTextScale,
    required this.reason,
  });

  factory WydTextScaleAdjustment.resolve({
    required bool isLinux,
    required Map<String, String> environment,
    required double devicePixelRatio,
    required double textScale,
  }) {
    if (!isLinux ||
        !_isKde(environment) ||
        devicePixelRatio < 1.25 ||
        textScale < 1.1 ||
        textScale < devicePixelRatio * 0.9) {
      return WydTextScaleAdjustment._unchanged(textScale);
    }

    return WydTextScaleAdjustment._(
      adjustedTextScale: math.max(1, textScale / devicePixelRatio),
      reason: 'kde-duplicates-display-scale',
    );
  }

  factory WydTextScaleAdjustment._unchanged(double textScale) {
    return WydTextScaleAdjustment._(adjustedTextScale: textScale, reason: null);
  }

  final double adjustedTextScale;
  final String? reason;

  bool get adjusted => reason != null;

  static bool _isKde(Map<String, String> environment) {
    return [
      environment['XDG_CURRENT_DESKTOP'],
      environment['XDG_SESSION_DESKTOP'],
      environment['DESKTOP_SESSION'],
    ].whereType<String>().any((value) {
      final normalized = value.toLowerCase();
      return normalized
          .split(':')
          .any((part) => part == 'kde' || part == 'plasma');
    });
  }
}

final class WydLayoutMetrics {
  const WydLayoutMetrics._({required this.rem});

  factory WydLayoutMetrics.of(BuildContext context) {
    final baseFontSize = Theme.of(context).textTheme.bodyLarge?.fontSize ?? 16;
    final rem = MediaQuery.textScalerOf(context).scale(baseFontSize);
    return WydLayoutMetrics._(rem: rem);
  }

  final double rem;

  double space(double rems) => rem * rems;

  double size(double rems) => rem * rems;

  double atLeast(double minLogicalPixels, double rems) {
    return math.max(minLogicalPixels, size(rems));
  }

  double maxWidth(double rems, {double min = 0}) {
    return atLeast(min, rems);
  }

  EdgeInsets insetsAll(double rems) {
    return EdgeInsets.all(space(rems));
  }

  EdgeInsets insetsSymmetric({double horizontal = 0, double vertical = 0}) {
    return EdgeInsets.symmetric(
      horizontal: space(horizontal),
      vertical: space(vertical),
    );
  }
}
