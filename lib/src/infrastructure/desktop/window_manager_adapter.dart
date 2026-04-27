import 'dart:async';
import 'dart:ui';

import 'package:window_manager/window_manager.dart';

import '../../application/application.dart';

final class SingleFlutterWindowAdapter
    with WindowListener
    implements WindowAdapter {
  SingleFlutterWindowAdapter({WindowManager? windowManager})
    : _windowManager = windowManager ?? windowManagerInstance,
      _configurator = DesktopWindowConfigurator(windowManager: windowManager);

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
  Future<void> focus(WindowHandle handle) async {
    await _windowManager.show();
    await _windowManager.focus();
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
  DesktopWindowConfigurator({WindowManager? windowManager})
    : _windowManager = windowManager ?? windowManagerInstance;

  static const _unconstrainedMaximumSize = Size(10000, 10000);

  final WindowManager _windowManager;

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
    await _windowManager.show();
    await _windowManager.focus();
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
