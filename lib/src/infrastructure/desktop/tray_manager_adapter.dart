import 'dart:async';
import 'dart:io';

import 'package:tray_manager/tray_manager.dart' as tray;

import '../../application/application.dart';

final class TrayManagerAdapter with tray.TrayListener implements TrayAdapter {
  TrayManagerAdapter({
    TrayIconAssetSet? iconAssets,
    tray.TrayManager? trayManager,
    bool? supportsSecondaryClickMenu,
    bool? supportsTooltip,
  }) : iconAssets = iconAssets ?? TrayIconAssetSet.forCurrentPlatform(),
       supportsSecondaryClickMenu =
           supportsSecondaryClickMenu ??
           (Platform.isMacOS || Platform.isWindows),
       supportsTooltip =
           supportsTooltip ?? (Platform.isMacOS || Platform.isWindows),
       _trayManager = trayManager ?? tray.trayManager;

  final TrayIconAssetSet iconAssets;
  final bool supportsSecondaryClickMenu;
  final bool supportsTooltip;
  final tray.TrayManager _trayManager;
  final StreamController<TrayMenuAction> _menuActions =
      StreamController<TrayMenuAction>.broadcast();
  final StreamController<void> _primaryClicks =
      StreamController<void>.broadcast();

  TrayIconStatus? _lastIconStatus;
  String? _lastTooltip;

  @override
  Stream<TrayMenuAction> get menuActions => _menuActions.stream;

  @override
  Stream<void> get primaryClicks => _primaryClicks.stream;

  @override
  Future<void> initialize(
    List<TrayMenuEntry> entries, {
    required TrayIconStatus iconStatus,
    required String tooltip,
  }) async {
    _trayManager.addListener(this);
    await updateIcon(iconStatus);
    await updateTooltip(tooltip);
    await updateMenu(entries);
  }

  @override
  Future<void> updateMenu(List<TrayMenuEntry> entries) async {
    await _trayManager.setContextMenu(
      tray.Menu(items: entries.map(_toMenuItem).toList(growable: false)),
    );
  }

  @override
  Future<void> updateIcon(TrayIconStatus iconStatus) async {
    if (_lastIconStatus == iconStatus) {
      return;
    }

    final icon = iconAssets.assetFor(iconStatus);
    await _trayManager.setIcon(icon.path, isTemplate: icon.isTemplate);
    _lastIconStatus = iconStatus;
  }

  @override
  Future<void> updateTooltip(String tooltip) async {
    if (!supportsTooltip || _lastTooltip == tooltip) {
      return;
    }

    await _trayManager.setToolTip(tooltip);
    _lastTooltip = tooltip;
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
    if (!supportsSecondaryClickMenu) {
      return;
    }

    _primaryClicks.add(null);
  }

  @override
  void onTrayIconRightMouseDown() {
    if (!supportsSecondaryClickMenu) {
      return;
    }

    unawaited(_trayManager.popUpContextMenu());
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

final class TrayIconAssetSet {
  const TrayIconAssetSet({required this.tracking, required this.idle});

  static const linux = TrayIconAssetSet(
    tracking: TrayIconAsset(path: 'assets/tray_icon.png'),
    idle: TrayIconAsset(path: 'assets/tray_icon_idle.png'),
  );

  static const macOS = TrayIconAssetSet(
    tracking: TrayIconAsset(
      path: 'assets/tray_icon_template.png',
      isTemplate: true,
    ),
    idle: TrayIconAsset(path: 'assets/tray_icon_idle.png'),
  );

  static const windows = TrayIconAssetSet(
    tracking: TrayIconAsset(path: 'assets/tray_icon.ico'),
    idle: TrayIconAsset(path: 'assets/tray_icon_idle.ico'),
  );

  static TrayIconAssetSet forCurrentPlatform() {
    if (Platform.isMacOS) {
      return macOS;
    }
    if (Platform.isWindows) {
      return windows;
    }
    return linux;
  }

  final TrayIconAsset tracking;
  final TrayIconAsset idle;

  TrayIconAsset assetFor(TrayIconStatus status) {
    return switch (status) {
      TrayIconStatus.tracking => tracking,
      TrayIconStatus.idle => idle,
    };
  }
}

final class TrayIconAsset {
  const TrayIconAsset({required this.path, this.isTemplate = false});

  final String path;
  final bool isTemplate;
}
