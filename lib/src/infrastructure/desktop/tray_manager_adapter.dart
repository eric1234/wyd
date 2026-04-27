import 'dart:async';
import 'dart:io';

import 'package:tray_manager/tray_manager.dart' as tray;

import '../../application/application.dart';

final class TrayManagerAdapter with tray.TrayListener implements TrayAdapter {
  TrayManagerAdapter({String? iconPath, tray.TrayManager? trayManager})
    : iconPath = iconPath ?? _defaultIconPath,
      _trayManager = trayManager ?? tray.trayManager;

  static String get _defaultIconPath {
    if (Platform.isMacOS) {
      return 'assets/tray_icon_template.png';
    }
    if (Platform.isWindows) {
      return 'assets/tray_icon.ico';
    }
    return 'assets/tray_icon.png';
  }

  final String iconPath;
  final tray.TrayManager _trayManager;
  final StreamController<TrayMenuAction> _menuActions =
      StreamController<TrayMenuAction>.broadcast();
  final StreamController<void> _primaryClicks =
      StreamController<void>.broadcast();

  @override
  Stream<TrayMenuAction> get menuActions => _menuActions.stream;

  @override
  Stream<void> get primaryClicks => _primaryClicks.stream;

  @override
  Future<void> initialize(List<TrayMenuEntry> entries) async {
    _trayManager.addListener(this);
    await _trayManager.setIcon(iconPath, isTemplate: Platform.isMacOS);
    await updateMenu(entries);
  }

  @override
  Future<void> updateMenu(List<TrayMenuEntry> entries) async {
    await _trayManager.setContextMenu(
      tray.Menu(items: entries.map(_toMenuItem).toList(growable: false)),
    );
  }

  @override
  Future<void> dispose() async {
    _trayManager.removeListener(this);
    await _trayManager.destroy();
    await _menuActions.close();
    await _primaryClicks.close();
  }

  @override
  void onTrayIconMouseDown() {
    _primaryClicks.add(null);
  }

  @override
  void onTrayMenuItemClick(tray.MenuItem menuItem) {
    final action = _actionFromKey(menuItem.key);
    if (action != null) {
      _menuActions.add(action);
    }
  }

  tray.MenuItem _toMenuItem(TrayMenuEntry entry) {
    return tray.MenuItem(
      key: entry.action.name,
      label: entry.label,
      disabled: !entry.enabled,
    );
  }

  TrayMenuAction? _actionFromKey(String? key) {
    if (key == null) {
      return null;
    }

    for (final action in TrayMenuAction.values) {
      if (action.name == key) {
        return action;
      }
    }

    return null;
  }
}
