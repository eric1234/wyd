import 'dart:async';

import 'package:desktop_screenstate/desktop_screenstate.dart';
import 'package:flutter/foundation.dart';

import '../../application/application.dart';

typedef ScreenStateListenableFactory = ValueListenable<ScreenState> Function();

final class DesktopScreenStatePowerEventAdapter implements PowerEventAdapter {
  DesktopScreenStatePowerEventAdapter({
    ScreenStateListenableFactory? stateListenableFactory,
    ValueListenable<ScreenState>? stateListenable,
  }) : _stateListenableFactory =
           stateListenableFactory ??
           (() => stateListenable ?? DesktopScreenState.instance.isActive);

  final ScreenStateListenableFactory _stateListenableFactory;

  @override
  Stream<PowerEvent> get events {
    late final StreamController<PowerEvent> controller;
    ValueListenable<ScreenState>? activeListenable;

    void handleStateChanged() {
      final event = powerEventForScreenState(activeListenable!.value);
      if (event != null) {
        controller.add(event);
      }
    }

    controller = StreamController<PowerEvent>.broadcast(
      onListen: () {
        activeListenable = _stateListenableFactory();
        activeListenable!.addListener(handleStateChanged);
      },
      onCancel: () {
        activeListenable?.removeListener(handleStateChanged);
        activeListenable = null;
      },
    );
    return controller.stream;
  }

  static PowerEvent? powerEventForScreenState(ScreenState state) {
    return switch (state) {
      ScreenState.sleep => PowerEvent.sleep,
      ScreenState.locked => PowerEvent.lock,
      ScreenState.awaked || ScreenState.unlocked => null,
    };
  }
}
