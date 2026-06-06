import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/application/application.dart';
import 'package:wyd/src/ui/wyd_app.dart';

void main() {
  testWidgets('home page does not overflow with high text scaling', (
    tester,
  ) async {
    await tester.pumpWidget(_scaledMaterialApp(home: const WydHomePage()));

    expect(tester.takeException(), isNull);
    expect(find.text("What's ya doin?"), findsOneWidget);
  });

  testWidgets('startup error page does not overflow with high text scaling', (
    tester,
  ) async {
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    addTearDown(() {
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue();
    });
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    final configuration = WindowRoleConfiguration.startupError();
    await tester.binding.setSurfaceSize(
      Size(configuration.width, configuration.height),
    );

    await tester.pumpWidget(
      _scaledFatalStartupApp(message: 'Could not initialize the tray.'),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Unable to start tray app'), findsOneWidget);
  });

  testWidgets('placeholder page does not overflow with high text scaling', (
    tester,
  ) async {
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    final configuration = WindowRoleConfiguration.quickEntry();
    await tester.binding.setSurfaceSize(
      Size(configuration.width, configuration.height),
    );

    await tester.pumpWidget(
      _scaledMaterialApp(
        home: const WydChildWindowApp(role: WindowRole.quickEntry),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      find.text('Quick entry is managed by the tray process.'),
      findsOneWidget,
    );
  });
}

Widget _scaledFatalStartupApp({required String message}) {
  return WydFatalStartupApp(message: message, onExit: () {});
}

Widget _scaledMaterialApp({required Widget home}) {
  return MaterialApp(
    theme: buildWydTheme(),
    builder: (context, child) {
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
        child: child ?? const SizedBox.shrink(),
      );
    },
    home: home,
  );
}
