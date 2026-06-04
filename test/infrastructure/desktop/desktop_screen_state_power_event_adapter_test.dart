import 'package:desktop_screenstate/desktop_screenstate.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/application/application.dart';
import 'package:wyd/src/infrastructure/desktop/desktop.dart';

void main() {
  group('DesktopScreenStatePowerEventAdapter', () {
    test('maps away screen states to power events', () {
      expect(
        DesktopScreenStatePowerEventAdapter.powerEventForScreenState(
          ScreenState.sleep,
        ),
        PowerEvent.sleep,
      );
      expect(
        DesktopScreenStatePowerEventAdapter.powerEventForScreenState(
          ScreenState.locked,
        ),
        PowerEvent.lock,
      );
    });

    test('ignores wake and unlock screen states', () {
      expect(
        DesktopScreenStatePowerEventAdapter.powerEventForScreenState(
          ScreenState.awaked,
        ),
        isNull,
      );
      expect(
        DesktopScreenStatePowerEventAdapter.powerEventForScreenState(
          ScreenState.unlocked,
        ),
        isNull,
      );
    });

    test('emits only away states from listenable changes', () async {
      final states = ValueNotifier(ScreenState.awaked);
      addTearDown(states.dispose);
      final adapter = DesktopScreenStatePowerEventAdapter(
        stateListenable: states,
      );
      final expectation = expectLater(
        adapter.events,
        emitsInOrder([PowerEvent.sleep, PowerEvent.lock]),
      );

      await Future<void>.delayed(Duration.zero);
      states.value = ScreenState.sleep;
      states.value = ScreenState.awaked;
      states.value = ScreenState.unlocked;
      states.value = ScreenState.locked;

      await expectation;
    });
  });
}
