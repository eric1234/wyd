import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/application/application.dart';
import 'package:wyd/src/ui/about/about.dart';
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

  testWidgets('about child window displays app metadata and launches link', (
    tester,
  ) async {
    Uri? launchedUrl;

    await tester.pumpWidget(
      WydChildWindowApp(
        role: WindowRole.about,
        aboutInfoLoader: () async {
          return const AboutAppInfo(
            version: '1.2.3',
            buildNumber: '4',
            snapshotCommit: 'a8e03a3123456789',
          );
        },
        aboutLinkLauncher: (url) async {
          launchedUrl = url;
          return true;
        },
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text(WydAboutMetadata.appName), findsOneWidget);
    expect(find.text(WydAboutMetadata.description), findsOneWidget);
    expect(find.text('Author: Eric Anderson'), findsOneWidget);
    expect(find.text('Version 1.2.3'), findsOneWidget);
    expect(find.text('Build 4'), findsOneWidget);
    expect(find.text('Snapshot a8e03a3'), findsOneWidget);
    expect(find.text(WydAboutMetadata.website), findsOneWidget);

    await tester.tap(find.text(WydAboutMetadata.website));

    expect(launchedUrl, WydAboutMetadata.websiteUri);
  });

  testWidgets('about child window omits snapshot metadata for releases', (
    tester,
  ) async {
    await tester.pumpWidget(
      WydChildWindowApp(
        role: WindowRole.about,
        aboutInfoLoader: () async {
          return const AboutAppInfo(version: '1.2.3', buildNumber: '4');
        },
      ),
    );
    await tester.pump();

    expect(find.textContaining('Snapshot '), findsNothing);
  });

  testWidgets('about link launcher failures show an error message', (
    tester,
  ) async {
    await tester.pumpWidget(
      WydChildWindowApp(
        role: WindowRole.about,
        aboutInfoLoader: () async {
          return const AboutAppInfo(version: '1.2.3', buildNumber: '4');
        },
        aboutLinkLauncher: (_) async {
          throw PlatformException(code: 'channel-error');
        },
      ),
    );
    await tester.pump();

    await tester.tap(find.text(WydAboutMetadata.website));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Unable to open website.'), findsOneWidget);
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
