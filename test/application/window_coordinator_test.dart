import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/application/application.dart';
import 'package:wyd/src/domain/domain.dart';

void main() {
  group('TrayMenuPresenter', () {
    test('disables stop task when idle', () {
      final snapshot = AppStateSnapshot(
        activeTask: null,
        runtimeState: RuntimeState(),
        settings: AppSettings.defaults,
      );
      final menu = TrayMenuPresenter.build(snapshot);

      final stopTask = menu.singleWhere(
        (entry) => entry.action == TrayMenuAction.stopTask,
      );

      expect(stopTask.enabled, isFalse);
      expect(TrayMenuPresenter.buildIconStatus(snapshot), TrayIconStatus.idle);
      expect(menu.map((entry) => entry.label), [
        'Update Task',
        'Stop Task',
        'Report',
        'Settings',
        'Exit',
      ]);
    });

    test('enables stop task while tracking', () {
      final snapshot = AppStateSnapshot(
        activeTask: ActiveTask(
          taskText: 'Write docs',
          taskTextNormalized: 'write docs',
          startedAtUtc: DateTime.utc(2026, 1, 1, 9),
          sourceEventId: 1,
        ),
        runtimeState: RuntimeState(),
        settings: AppSettings.defaults,
      );
      final menu = TrayMenuPresenter.build(snapshot);

      final stopTask = menu.singleWhere(
        (entry) => entry.action == TrayMenuAction.stopTask,
      );

      expect(stopTask.enabled, isTrue);
      expect(
        TrayMenuPresenter.buildIconStatus(snapshot),
        TrayIconStatus.tracking,
      );
    });
  });

  group('WindowCoordinator', () {
    test('opens each role with role-specific configuration', () async {
      final adapter = _FakeWindowAdapter();
      final coordinator = WindowCoordinator(adapter);

      await coordinator.openOrFocus(WindowRole.quickEntry);
      await coordinator.openOrFocus(WindowRole.report);

      expect(adapter.openedConfigurations.map((config) => config.role), [
        WindowRole.quickEntry,
        WindowRole.report,
      ]);
      expect(adapter.openedConfigurations.first.resizable, isFalse);
      expect(adapter.openedConfigurations.first.alwaysOnTop, isTrue);
      expect(
        adapter.openedConfigurations.first.height,
        WindowRoleConfiguration.quickEntryHeight,
      );
    });

    test(
      'focuses an already-open role instead of stacking another window',
      () async {
        final adapter = _FakeWindowAdapter();
        final coordinator = WindowCoordinator(adapter);

        final firstHandle = await coordinator.openOrFocus(
          WindowRole.quickEntry,
        );
        final secondHandle = await coordinator.openOrFocus(
          WindowRole.quickEntry,
        );

        expect(firstHandle.id, secondHandle.id);
        expect(adapter.openedConfigurations, hasLength(1));
        expect(adapter.resizedConfigurations, hasLength(1));
        expect(adapter.focusedHandles.map((handle) => handle.id), [
          firstHandle.id,
        ]);
      },
    );

    test('reopens a role when the previous handle is closed', () async {
      final adapter = _FakeWindowAdapter();
      final coordinator = WindowCoordinator(adapter);

      final firstHandle = await coordinator.openOrFocus(WindowRole.settings);
      adapter.openHandles.remove(firstHandle.id);
      final secondHandle = await coordinator.openOrFocus(WindowRole.settings);

      expect(firstHandle.id, isNot(secondHandle.id));
      expect(adapter.openedConfigurations, hasLength(2));
    });

    test('closes a known role only when its handle is open', () async {
      final adapter = _FakeWindowAdapter();
      final coordinator = WindowCoordinator(adapter);
      final handle = await coordinator.openOrFocus(WindowRole.report);

      await coordinator.close(WindowRole.report);
      await coordinator.close(WindowRole.report);

      expect(adapter.closedHandles.map((closed) => closed.id), [handle.id]);
      expect(await coordinator.isOpen(WindowRole.report), isFalse);
    });

    test('forgets native-closed roles and emits close requests', () async {
      final adapter = _FakeWindowAdapter();
      final coordinator = WindowCoordinator(adapter);
      await coordinator.openOrFocus(WindowRole.settings);

      final closeRequest = expectLater(
        coordinator.closeRequests,
        emits(WindowRole.settings),
      );
      adapter.emitCloseRequest(WindowRole.settings);
      await closeRequest;

      expect(await coordinator.isOpen(WindowRole.settings), isFalse);
    });

    test('preloads a role and focuses it when opened later', () async {
      final adapter = _FakeWindowAdapter();
      final coordinator = WindowCoordinator(adapter);

      await coordinator.preload(WindowRole.report);
      final handle = await coordinator.openOrFocus(WindowRole.report);

      expect(adapter.preloadedConfigurations.map((config) => config.role), [
        WindowRole.report,
      ]);
      expect(adapter.openedConfigurations, isEmpty);
      expect(adapter.focusedHandles.map((focused) => focused.id), [handle.id]);
    });
  });
}

final class _FakeWindowAdapter implements WindowAdapter {
  int nextId = 1;
  final Set<String> openHandles = {};
  final List<WindowRoleConfiguration> openedConfigurations = [];
  final List<WindowRoleConfiguration> preloadedConfigurations = [];
  final List<WindowRoleConfiguration> resizedConfigurations = [];
  final List<WindowHandle> focusedHandles = [];
  final List<WindowHandle> closedHandles = [];
  final StreamController<WindowHandle> _closeRequests =
      StreamController<WindowHandle>.broadcast();

  @override
  Stream<WindowHandle> get closeRequests => _closeRequests.stream;

  @override
  Future<WindowHandle> open(WindowRoleConfiguration configuration) async {
    openedConfigurations.add(configuration);
    final handle = WindowHandle('${configuration.role.name}-${nextId++}');
    openHandles.add(handle.id);
    return handle;
  }

  @override
  Future<WindowHandle> preload(WindowRoleConfiguration configuration) async {
    preloadedConfigurations.add(configuration);
    final handle = WindowHandle('${configuration.role.name}-${nextId++}');
    openHandles.add(handle.id);
    return handle;
  }

  @override
  Future<bool> isOpen(WindowHandle handle) async =>
      openHandles.contains(handle.id);

  @override
  Future<void> focus(WindowHandle handle) async {
    focusedHandles.add(handle);
  }

  @override
  Future<void> resize(
    WindowHandle handle,
    WindowRoleConfiguration configuration,
  ) async {
    resizedConfigurations.add(configuration);
  }

  @override
  Future<void> close(WindowHandle handle) async {
    openHandles.remove(handle.id);
    closedHandles.add(handle);
  }

  void emitCloseRequest(WindowRole role) {
    final handle = WindowHandle('${role.name}-1');
    openHandles.remove(handle.id);
    _closeRequests.add(handle);
  }
}
