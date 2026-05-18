import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/application/application.dart';
import 'package:wyd/src/infrastructure/desktop/desktop.dart';

const _entries = [
  TrayMenuEntry(action: TrayMenuAction.updateTask, label: 'Update Task'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TrayManagerAdapter', () {
    const channel = MethodChannel('tray_manager');
    late List<MethodCall> calls;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return true;
          });
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('initialization sets the icon, tooltip, then context menu', () async {
      const iconAssets = TrayIconAssetSet(
        tracking: TrayIconAsset(path: 'assets/tracking-test.png'),
        idle: TrayIconAsset(path: 'assets/idle-test.png'),
      );
      final adapter = TrayManagerAdapter(
        iconAssets: iconAssets,
        supportsSecondaryClickMenu: false,
        supportsTooltip: true,
      );
      addTearDown(adapter.dispose);

      await adapter.initialize(
        _entries,
        iconStatus: TrayIconStatus.idle,
        tooltip: 'No current task',
      );

      expect(calls.map((call) => call.method).take(3), [
        'setIcon',
        'setToolTip',
        'setContextMenu',
      ]);
      expect(_iconPath(calls.first), endsWith('assets/idle-test.png'));
      expect(_isTemplate(calls.first), isFalse);
      expect(_toolTip(calls[1]), 'No current task');
    });

    test('idle uses the red PNG icon for Linux-style assets', () async {
      final adapter = TrayManagerAdapter(
        iconAssets: TrayIconAssetSet.linux,
        supportsSecondaryClickMenu: false,
      );
      addTearDown(adapter.dispose);

      await adapter.updateIcon(TrayIconStatus.idle);

      final iconCall = _setIconCalls(calls).single;
      expect(_iconPath(iconCall), endsWith('assets/tray_icon_idle.png'));
      expect(_isTemplate(iconCall), isFalse);
    });

    test('tracking uses the normal PNG icon for Linux-style assets', () async {
      final adapter = TrayManagerAdapter(
        iconAssets: TrayIconAssetSet.linux,
        supportsSecondaryClickMenu: false,
      );
      addTearDown(adapter.dispose);

      await adapter.updateIcon(TrayIconStatus.tracking);

      final iconCall = _setIconCalls(calls).single;
      expect(_iconPath(iconCall), endsWith('assets/tray_icon.png'));
      expect(_isTemplate(iconCall), isFalse);
    });

    test('tracking-to-idle and idle-to-tracking update the icon', () async {
      final adapter = TrayManagerAdapter(
        iconAssets: TrayIconAssetSet.linux,
        supportsSecondaryClickMenu: false,
        supportsTooltip: false,
      );
      addTearDown(adapter.dispose);
      await adapter.initialize(
        _entries,
        iconStatus: TrayIconStatus.tracking,
        tooltip: 'Write docs',
      );
      calls.clear();

      await adapter.updateIcon(TrayIconStatus.idle);
      await adapter.updateIcon(TrayIconStatus.tracking);

      final iconCalls = _setIconCalls(calls);
      expect(iconCalls, hasLength(2));
      expect(_iconPath(iconCalls[0]), endsWith('assets/tray_icon_idle.png'));
      expect(_iconPath(iconCalls[1]), endsWith('assets/tray_icon.png'));
    });

    test('repeated same-state updates do not reset the icon', () async {
      final adapter = TrayManagerAdapter(
        iconAssets: TrayIconAssetSet.linux,
        supportsSecondaryClickMenu: false,
        supportsTooltip: false,
      );
      addTearDown(adapter.dispose);
      await adapter.initialize(
        _entries,
        iconStatus: TrayIconStatus.idle,
        tooltip: 'No current task',
      );
      calls.clear();

      await adapter.updateIcon(TrayIconStatus.idle);
      await adapter.updateIcon(TrayIconStatus.idle);

      expect(_setIconCalls(calls), isEmpty);
    });

    test('unsupported tooltips do not call setToolTip', () async {
      final adapter = TrayManagerAdapter(
        iconAssets: TrayIconAssetSet.linux,
        supportsSecondaryClickMenu: false,
        supportsTooltip: false,
      );
      addTearDown(adapter.dispose);

      await adapter.initialize(
        _entries,
        iconStatus: TrayIconStatus.idle,
        tooltip: 'No current task',
      );
      await adapter.updateTooltip('Write docs');

      expect(calls.map((call) => call.method), isNot(contains('setToolTip')));
    });

    test('repeated same-tooltip updates do not reset the tooltip', () async {
      final adapter = TrayManagerAdapter(
        iconAssets: TrayIconAssetSet.linux,
        supportsSecondaryClickMenu: false,
        supportsTooltip: true,
      );
      addTearDown(adapter.dispose);
      await adapter.initialize(
        _entries,
        iconStatus: TrayIconStatus.idle,
        tooltip: 'No current task',
      );
      calls.clear();

      await adapter.updateTooltip('No current task');
      await adapter.updateTooltip('No current task');

      expect(_setToolTipCalls(calls), isEmpty);
    });

    test('changed tooltip calls setToolTip with toolTip', () async {
      final adapter = TrayManagerAdapter(
        iconAssets: TrayIconAssetSet.linux,
        supportsSecondaryClickMenu: false,
        supportsTooltip: true,
      );
      addTearDown(adapter.dispose);
      await adapter.initialize(
        _entries,
        iconStatus: TrayIconStatus.idle,
        tooltip: 'No current task',
      );
      calls.clear();

      await adapter.updateTooltip('Write docs');

      final tooltipCall = _setToolTipCalls(calls).single;
      expect(_toolTip(tooltipCall), 'Write docs');
    });

    test('macOS-style assets pass per-state template flags', () async {
      const iconAssets = TrayIconAssetSet(
        tracking: TrayIconAsset(
          path: 'assets/tracking-template-test.png',
          isTemplate: true,
        ),
        idle: TrayIconAsset(path: 'assets/idle-test.png'),
      );
      final adapter = TrayManagerAdapter(
        iconAssets: iconAssets,
        supportsSecondaryClickMenu: true,
      );
      addTearDown(adapter.dispose);

      await adapter.updateIcon(TrayIconStatus.tracking);
      await adapter.updateIcon(TrayIconStatus.idle);

      final iconCalls = _setIconCalls(calls);
      expect(iconCalls, hasLength(2));
      expect(
        _iconPath(iconCalls[0]),
        endsWith('assets/tracking-template-test.png'),
      );
      expect(_isTemplate(iconCalls[0]), isTrue);
      expect(_iconPath(iconCalls[1]), endsWith('assets/idle-test.png'));
      expect(_isTemplate(iconCalls[1]), isFalse);
    });

    test('Windows fallback assets include an idle ICO', () {
      expect(
        TrayIconAssetSet.windows.assetFor(TrayIconStatus.tracking).path,
        'assets/tray_icon.ico',
      );
      expect(
        TrayIconAssetSet.windows.assetFor(TrayIconStatus.idle).path,
        'assets/tray_icon_idle.ico',
      );
    });

    test(
      'secondary tray click opens the context menu when supported',
      () async {
        final adapter = TrayManagerAdapter(supportsSecondaryClickMenu: true);

        adapter.onTrayIconRightMouseDown();
        await Future<void>.delayed(Duration.zero);

        expect(calls.map((call) => call.method), contains('popUpContextMenu'));
      },
    );

    test(
      'primary tray click emits quick-entry action when secondary menu is supported',
      () async {
        final adapter = TrayManagerAdapter(supportsSecondaryClickMenu: true);
        final click = expectLater(adapter.primaryClicks, emits(null));

        adapter.onTrayIconMouseDown();

        await click;
      },
    );

    test(
      'primary tray click is left to native menu fallback without secondary support',
      () async {
        final adapter = TrayManagerAdapter(supportsSecondaryClickMenu: false);
        var primaryClicks = 0;
        final subscription = adapter.primaryClicks.listen((_) {
          primaryClicks += 1;
        });
        addTearDown(subscription.cancel);

        adapter.onTrayIconMouseDown();
        await Future<void>.delayed(Duration.zero);

        expect(primaryClicks, 0);
        expect(calls, isEmpty);
      },
    );

    test('secondary tray click is ignored without secondary support', () async {
      final adapter = TrayManagerAdapter(supportsSecondaryClickMenu: false);

      adapter.onTrayIconRightMouseDown();
      await Future<void>.delayed(Duration.zero);

      expect(calls, isEmpty);
    });
  });
}

List<MethodCall> _setIconCalls(List<MethodCall> calls) {
  return calls.where((call) => call.method == 'setIcon').toList();
}

List<MethodCall> _setToolTipCalls(List<MethodCall> calls) {
  return calls.where((call) => call.method == 'setToolTip').toList();
}

String _iconPath(MethodCall call) {
  return _arguments(call)['iconPath'] as String;
}

bool _isTemplate(MethodCall call) {
  return _arguments(call)['isTemplate'] as bool;
}

String _toolTip(MethodCall call) {
  return _arguments(call)['toolTip'] as String;
}

Map<dynamic, dynamic> _arguments(MethodCall call) {
  return call.arguments as Map<dynamic, dynamic>;
}
