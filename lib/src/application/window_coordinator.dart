import 'platform_adapters.dart';

final class WindowCoordinator {
  WindowCoordinator(this._adapter);

  final WindowAdapter _adapter;
  final Map<WindowRole, WindowHandle> _openWindows = {};
  final Map<WindowRole, Future<void>> _preloadingWindows = {};

  Stream<WindowRole> get closeRequests {
    return _adapter.closeRequests
        .map(_removeClosedHandle)
        .where((role) => role != null)
        .cast<WindowRole>();
  }

  Future<WindowHandle> openOrFocus(
    WindowRole role, {
    WindowRoleConfiguration? configuration,
  }) async {
    final resolvedConfiguration =
        configuration ?? WindowRoleConfiguration.forRole(role);
    final preload = _preloadingWindows[role];
    if (preload != null) {
      await preload;
    }
    final existingHandle = _openWindows[role];
    if (existingHandle != null && await _adapter.isOpen(existingHandle)) {
      await _adapter.resize(existingHandle, resolvedConfiguration);
      await _adapter.focus(existingHandle);
      return existingHandle;
    }

    final handle = await _adapter.open(resolvedConfiguration);
    _openWindows[role] = handle;
    return handle;
  }

  Future<void> preload(WindowRole role) {
    final existingHandle = _openWindows[role];
    if (existingHandle != null) {
      return Future.value();
    }

    return _preloadingWindows[role] ??= _preload(role).whenComplete(() {
      _preloadingWindows.remove(role);
    });
  }

  Future<void> resize(
    WindowRole role,
    WindowRoleConfiguration configuration,
  ) async {
    final existingHandle = _openWindows[role];
    if (existingHandle == null || !await _adapter.isOpen(existingHandle)) {
      return;
    }

    await _adapter.resize(existingHandle, configuration);
  }

  Future<void> close(WindowRole role) async {
    final existingHandle = _openWindows.remove(role);
    if (existingHandle == null) {
      return;
    }

    if (await _adapter.isOpen(existingHandle)) {
      await _adapter.close(existingHandle);
    }
  }

  Future<void> closeAll() async {
    final roles = _openWindows.keys.toList();
    for (final role in roles) {
      await close(role);
    }
  }

  Future<bool> isOpen(WindowRole role) async {
    final handle = _openWindows[role];
    return handle != null && await _adapter.isOpen(handle);
  }

  Future<void> _preload(WindowRole role) async {
    final handle = await _adapter.preload(
      WindowRoleConfiguration.forRole(role),
    );
    _openWindows.putIfAbsent(role, () => handle);
  }

  WindowRole? _removeClosedHandle(WindowHandle handle) {
    WindowRole? closedRole;
    for (final entry in _openWindows.entries) {
      if (entry.value.id == handle.id) {
        closedRole = entry.key;
        break;
      }
    }

    if (closedRole != null) {
      _openWindows.remove(closedRole);
    }
    return closedRole;
  }
}
