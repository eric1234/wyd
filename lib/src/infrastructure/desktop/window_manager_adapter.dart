import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../application/application.dart';

abstract interface class WindowAttentionAdapter {
  Future<bool> presentForInput();

  Future<void> setUrgent(bool urgent);
}

final class MethodChannelLinuxWindowAttentionAdapter
    implements WindowAttentionAdapter {
  const MethodChannelLinuxWindowAttentionAdapter({
    MethodChannel channel = const MethodChannel(_channelName),
  }) : _channel = channel;

  static const _channelName = 'dev.wyd.tracker/linux_window_attention';

  final MethodChannel _channel;

  @override
  Future<bool> presentForInput() async {
    if (!Platform.isLinux) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>('presentForInput') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> setUrgent(bool urgent) async {
    if (!Platform.isLinux) {
      return;
    }

    try {
      await _channel.invokeMethod<bool>('setUrgent', {'urgent': urgent});
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}

final class SingleFlutterWindowAdapter
    with WindowListener
    implements WindowAdapter {
  SingleFlutterWindowAdapter({
    WindowManager? windowManager,
    WindowAttentionAdapter? windowAttentionAdapter,
  }) : _windowManager = windowManager ?? windowManagerInstance,
       _configurator = DesktopWindowConfigurator(
         windowManager: windowManager,
         windowAttentionAdapter:
             windowAttentionAdapter ??
             const MethodChannelLinuxWindowAttentionAdapter(),
       );

  final WindowManager _windowManager;
  final DesktopWindowConfigurator _configurator;
  final StreamController<WindowHandle> _closeRequests =
      StreamController<WindowHandle>.broadcast();
  WindowHandle? _currentHandle;
  bool _closeInterceptionReady = false;
  bool _handlingClose = false;

  @override
  Stream<WindowHandle> get closeRequests => _closeRequests.stream;

  @override
  Future<WindowHandle> open(WindowRoleConfiguration configuration) async {
    await _windowManager.ensureInitialized();
    await _ensureCloseInterception();
    final options = WindowOptions(
      size: Size(configuration.width, configuration.height),
      center: true,
      alwaysOnTop: configuration.alwaysOnTop,
      skipTaskbar: configuration.role == WindowRole.quickEntry,
      title: configuration.title,
    );

    await _windowManager.waitUntilReadyToShow(options);
    await _configurator.apply(configuration);
    await _configurator.showAndFocus();

    final handle = WindowHandle(configuration.role.name);
    _currentHandle = handle;
    return handle;
  }

  @override
  Future<WindowHandle> preload(WindowRoleConfiguration configuration) {
    return open(configuration);
  }

  @override
  Future<bool> isOpen(WindowHandle handle) {
    return _windowManager.isVisible();
  }

  @override
  Future<void> focus(WindowHandle handle) {
    return _configurator.showAndFocusInPlace();
  }

  @override
  Future<void> resize(
    WindowHandle handle,
    WindowRoleConfiguration configuration,
  ) {
    return _configurator.apply(configuration);
  }

  @override
  Future<void> close(WindowHandle handle) async {
    if (_currentHandle?.id == handle.id) {
      _currentHandle = null;
    }
    await _configurator.clearAttention();
    await _windowManager.hide();
  }

  Future<void> hideResidentWindow() async {
    if (_currentHandle != null) {
      return;
    }

    await _windowManager.ensureInitialized();
    await _windowManager.hide();
  }

  @override
  void onWindowClose() {
    unawaited(_handleNativeClose());
  }

  Future<void> _ensureCloseInterception() async {
    if (_closeInterceptionReady) {
      return;
    }

    _windowManager.addListener(this);
    await _windowManager.setPreventClose(true);
    _closeInterceptionReady = true;
  }

  Future<void> _handleNativeClose() async {
    if (_handlingClose) {
      return;
    }
    _handlingClose = true;

    try {
      if (!await _windowManager.isPreventClose()) {
        return;
      }

      final handle = _currentHandle;
      await _configurator.clearAttention();
      await _windowManager.hide();
      if (handle != null && !_closeRequests.isClosed) {
        _currentHandle = null;
        _closeRequests.add(handle);
      }
    } finally {
      _handlingClose = false;
    }
  }
}

final class DesktopWindowConfigurator {
  DesktopWindowConfigurator({
    WindowManager? windowManager,
    WindowAttentionAdapter? windowAttentionAdapter,
  }) : _windowManager = windowManager ?? windowManagerInstance,
       _windowAttentionAdapter = windowAttentionAdapter;

  static const _unconstrainedMaximumSize = Size(10000, 10000);
  static const _focusStateDelay = Duration(milliseconds: 100);

  final WindowManager _windowManager;
  final WindowAttentionAdapter? _windowAttentionAdapter;

  Future<void> apply(WindowRoleConfiguration configuration) async {
    final size = Size(configuration.width, configuration.height);
    if (await _windowManager.isFullScreen()) {
      await _windowManager.setFullScreen(false);
    }
    if (await _windowManager.isMaximized()) {
      await _windowManager.unmaximize();
    }
    if (await _windowManager.isMinimized()) {
      await _windowManager.restore();
    }

    await _windowManager.setTitle(configuration.title);
    await _windowManager.setResizable(true);
    await _windowManager.setMinimumSize(Size.zero);
    await _windowManager.setMaximumSize(_unconstrainedMaximumSize);
    await _windowManager.setSize(size);
    if (!configuration.resizable) {
      await _windowManager.setMinimumSize(size);
      await _windowManager.setMaximumSize(size);
      await _windowManager.setSize(size);
    }
    await _windowManager.setResizable(configuration.resizable);
    await _windowManager.setAlwaysOnTop(configuration.alwaysOnTop);
    await _windowManager.setSkipTaskbar(
      configuration.role == WindowRole.quickEntry,
    );
  }

  Future<void> showAndFocus() async {
    await _windowManager.center();
    await showAndFocusInPlace();
  }

  Future<void> showAndFocusInPlace() async {
    await clearAttention();
    await _windowManager.show();
    final presentedForInput =
        await _windowAttentionAdapter?.presentForInput() ?? false;
    if (!presentedForInput) {
      await _windowManager.focus();
    }
    await Future<void>.delayed(_focusStateDelay);

    if (!await _windowManager.isVisible()) {
      await clearAttention();
      return;
    }
    if (await _windowManager.isFocused()) {
      await clearAttention();
      return;
    }

    await _windowAttentionAdapter?.setUrgent(true);
  }

  Future<void> clearAttention() async {
    await _windowAttentionAdapter?.setUrgent(false);
  }

  Future<void> close() {
    return _windowManager.close();
  }
}

final class HideOnCloseWindowHandler with WindowListener {
  HideOnCloseWindowHandler({
    WindowManager? windowManager,
    Future<void> Function()? onBeforeHide,
  }) : _windowManager = windowManager ?? windowManagerInstance,
       _onBeforeHide = onBeforeHide;

  final WindowManager _windowManager;
  final Future<void> Function()? _onBeforeHide;
  bool _forceClose = false;

  Future<void> initialize() async {
    _windowManager.addListener(this);
    await _windowManager.setPreventClose(true);
  }

  @override
  void onWindowClose() {
    unawaited(_handleWindowClose());
  }

  Future<void> forceClose() async {
    _forceClose = true;
    await _windowManager.setPreventClose(false);
    _windowManager.removeListener(this);
    await _windowManager.close();
  }

  Future<void> _handleWindowClose() async {
    if (_forceClose) {
      return;
    }
    if (await _windowManager.isPreventClose()) {
      await _onBeforeHide?.call();
      await _windowManager.hide();
    }
  }
}

final windowManagerInstance = windowManager;
