import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';

import '../../application/application.dart';

final class RoleWindowProtocol {
  const RoleWindowProtocol._();

  static const kind = 'wyd-role-window';
  static const configureMethod = 'configure';
  static const showAndFocusMethod = 'showAndFocus';
  static const pingMethod = 'ping';
  static const closeMethod = 'close';
}

String encodeRoleWindowArguments(WindowRole role, {required bool showOnReady}) {
  return jsonEncode({
    'kind': RoleWindowProtocol.kind,
    'role': role.name,
    'showOnReady': showOnReady,
  });
}

WindowRole? decodeRoleWindowRole(String arguments) {
  if (arguments.isEmpty) {
    return null;
  }

  try {
    final decoded = jsonDecode(arguments);
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    if (decoded['kind'] != RoleWindowProtocol.kind) {
      return null;
    }
    final roleName = decoded['role'];
    if (roleName is! String) {
      return null;
    }
    return WindowRole.values.cast<WindowRole?>().firstWhere(
      (role) => role?.name == roleName,
      orElse: () => null,
    );
  } catch (_) {
    return null;
  }
}

bool decodeRoleWindowShowOnReady(String arguments) {
  if (arguments.isEmpty) {
    return true;
  }

  try {
    final decoded = jsonDecode(arguments);
    if (decoded is! Map<String, Object?>) {
      return true;
    }
    return decoded['showOnReady'] as bool? ?? true;
  } catch (_) {
    return true;
  }
}

Map<String, Object?> encodeRoleWindowConfiguration(
  WindowRoleConfiguration configuration,
) {
  return {
    'role': configuration.role.name,
    'title': configuration.title,
    'width': configuration.width,
    'height': configuration.height,
    'resizable': configuration.resizable,
    'alwaysOnTop': configuration.alwaysOnTop,
  };
}

WindowRoleConfiguration decodeRoleWindowConfiguration(Object? arguments) {
  if (arguments is! Map) {
    throw const FormatException('Expected role window configuration map.');
  }

  final decoded = Map<Object?, Object?>.from(arguments);
  return WindowRoleConfiguration(
    role: _decodeWindowRole(_requiredString(decoded, 'role')),
    title: _requiredString(decoded, 'title'),
    width: _requiredNumber(decoded, 'width').toDouble(),
    height: _requiredNumber(decoded, 'height').toDouble(),
    resizable: _optionalBool(decoded, 'resizable', defaultValue: true),
    alwaysOnTop: _optionalBool(decoded, 'alwaysOnTop', defaultValue: false),
  );
}

WindowRole _decodeWindowRole(String value) {
  try {
    return WindowRole.values.byName(value);
  } on ArgumentError {
    throw FormatException('Unknown role window role: $value');
  }
}

String _requiredString(Map<Object?, Object?> decoded, String key) {
  final value = decoded[key];
  if (value is String) {
    return value;
  }
  throw FormatException('Expected string role window field: $key');
}

num _requiredNumber(Map<Object?, Object?> decoded, String key) {
  final value = decoded[key];
  if (value is num) {
    return value;
  }
  throw FormatException('Expected numeric role window field: $key');
}

bool _optionalBool(
  Map<Object?, Object?> decoded,
  String key, {
  required bool defaultValue,
}) {
  final value = decoded[key];
  if (value == null) {
    return defaultValue;
  }
  if (value is bool) {
    return value;
  }
  throw FormatException('Expected boolean role window field: $key');
}

final class DesktopMultiWindowAdapter implements WindowAdapter {
  DesktopMultiWindowAdapter({required WindowAdapter primaryWindowAdapter})
    : _primaryWindowAdapter = primaryWindowAdapter {
    _primaryCloseSubscription = _primaryWindowAdapter.closeRequests.listen(
      _closeRequests.add,
    );
    _childWindowSubscription = onWindowsChanged.listen(
      (_) => unawaited(_emitClosedChildWindows()),
    );
  }

  final WindowAdapter _primaryWindowAdapter;
  final StreamController<WindowHandle> _closeRequests =
      StreamController<WindowHandle>.broadcast();
  final Map<String, WindowRole> _childWindowRoles = {};
  late final StreamSubscription<WindowHandle> _primaryCloseSubscription;
  late final StreamSubscription<void> _childWindowSubscription;

  @override
  Stream<WindowHandle> get closeRequests => _closeRequests.stream;

  @override
  Future<WindowHandle> open(WindowRoleConfiguration configuration) async {
    if (_usesPrimaryWindow(configuration.role)) {
      return _primaryWindowAdapter.open(configuration);
    }

    return _createChildWindow(configuration.role, showOnReady: true);
  }

  @override
  Future<WindowHandle> preload(WindowRoleConfiguration configuration) async {
    if (_usesPrimaryWindow(configuration.role)) {
      return _primaryWindowAdapter.preload(configuration);
    }

    final handle = await _createChildWindow(
      configuration.role,
      showOnReady: false,
    );
    await _waitForChildWindowReady(handle);
    return handle;
  }

  Future<WindowHandle> _createChildWindow(
    WindowRole role, {
    required bool showOnReady,
  }) async {
    final controller = await WindowController.create(
      WindowConfiguration(
        arguments: encodeRoleWindowArguments(role, showOnReady: showOnReady),
        hiddenAtLaunch: true,
      ),
    );
    _childWindowRoles[controller.windowId] = role;
    return WindowHandle(controller.windowId);
  }

  @override
  Future<bool> isOpen(WindowHandle handle) async {
    if (_usesPrimaryHandle(handle)) {
      return _primaryWindowAdapter.isOpen(handle);
    }

    return _isChildWindowOpen(handle.id);
  }

  @override
  Future<void> focus(WindowHandle handle) async {
    if (_usesPrimaryHandle(handle)) {
      await _primaryWindowAdapter.focus(handle);
      return;
    }

    await _invokeChildWindow<void>(
      handle,
      RoleWindowProtocol.showAndFocusMethod,
    );
  }

  @override
  Future<void> resize(
    WindowHandle handle,
    WindowRoleConfiguration configuration,
  ) async {
    if (_usesPrimaryHandle(handle)) {
      await _primaryWindowAdapter.resize(handle, configuration);
      return;
    }

    await _invokeChildWindow<void>(
      handle,
      RoleWindowProtocol.configureMethod,
      encodeRoleWindowConfiguration(configuration),
    );
  }

  @override
  Future<void> close(WindowHandle handle) async {
    if (_usesPrimaryHandle(handle)) {
      await _primaryWindowAdapter.close(handle);
      return;
    }

    if (await _isChildWindowOpen(handle.id)) {
      await _invokeChildWindow<void>(handle, RoleWindowProtocol.closeMethod);
    }
    _childWindowRoles.remove(handle.id);
  }

  Future<void> dispose() async {
    await _primaryCloseSubscription.cancel();
    await _childWindowSubscription.cancel();
    await _closeRequests.close();
  }

  bool _usesPrimaryWindow(WindowRole role) {
    return role == WindowRole.quickEntry;
  }

  bool _usesPrimaryHandle(WindowHandle handle) {
    return handle.id == WindowRole.quickEntry.name;
  }

  Future<bool> _isChildWindowOpen(String windowId) async {
    final windows = await WindowController.getAll();
    return windows.any((window) => window.windowId == windowId);
  }

  Future<T?> _invokeChildWindow<T>(
    WindowHandle handle,
    String method, [
    Object? arguments,
  ]) async {
    final controller = WindowController.fromWindowId(handle.id);
    return controller.invokeMethod<T>(method, arguments);
  }

  Future<void> _waitForChildWindowReady(WindowHandle handle) async {
    Object? lastError;
    for (var attempt = 0; attempt < 40; attempt += 1) {
      try {
        final ready = await _invokeChildWindow<bool>(
          handle,
          RoleWindowProtocol.pingMethod,
        );
        if (ready ?? false) {
          return;
        }
      } catch (error) {
        lastError = error;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    throw StateError('Timed out warming child window ${handle.id}: $lastError');
  }

  Future<void> _emitClosedChildWindows() async {
    final windows = await WindowController.getAll();
    final openWindowIds = windows.map((window) => window.windowId).toSet();
    final closedWindowIds = _childWindowRoles.keys
        .where((windowId) => !openWindowIds.contains(windowId))
        .toList();

    for (final windowId in closedWindowIds) {
      _childWindowRoles.remove(windowId);
      if (!_closeRequests.isClosed) {
        _closeRequests.add(WindowHandle(windowId));
      }
    }
  }
}
