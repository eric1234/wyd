import 'dart:async';

import '../../application/application.dart';

final class UnsupportedTrayAdapter implements TrayAdapter {
  UnsupportedTrayAdapter({
    this.reason = 'System tray support is unavailable in this build.',
  });

  final String reason;
  final StreamController<TrayMenuAction> _menuActions =
      StreamController<TrayMenuAction>.broadcast();
  final StreamController<void> _primaryClicks =
      StreamController<void>.broadcast();

  @override
  Stream<TrayMenuAction> get menuActions => _menuActions.stream;

  @override
  Stream<void> get primaryClicks => _primaryClicks.stream;

  @override
  Future<void> initialize(
    List<TrayMenuEntry> entries, {
    required TrayIconStatus iconStatus,
    required String tooltip,
  }) {
    throw UnsupportedError(reason);
  }

  @override
  Future<void> updateMenu(List<TrayMenuEntry> entries) async {}

  @override
  Future<void> updateIcon(TrayIconStatus iconStatus) async {}

  @override
  Future<void> updateTooltip(String tooltip) async {}

  @override
  Future<void> dispose() async {
    await _menuActions.close();
    await _primaryClicks.close();
  }
}
