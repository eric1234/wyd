import 'package:flutter/material.dart';

import '../application/application.dart';
import 'quick_entry/quick_entry.dart';
import 'report/report.dart';
import 'settings/settings.dart';
import 'wyd_app_controller.dart';

const _wydSeedColor = Color(0xff2563eb);

ThemeData buildWydTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: _wydSeedColor),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
  );
}

class WydApp extends StatefulWidget {
  const WydApp({super.key, this.controller});

  final WydAppController? controller;

  @override
  State<WydApp> createState() => _WydAppState();
}

class WydChildWindowApp extends StatelessWidget {
  const WydChildWindowApp({
    super.key,
    required this.role,
    this.reportController,
    this.settingsController,
  });

  final WindowRole role;
  final ReportController? reportController;
  final SettingsController? settingsController;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'wyd',
      theme: buildWydTheme(),
      home: switch (role) {
        WindowRole.report =>
          reportController == null
              ? const _PlaceholderRolePage(
                  title: 'Report',
                  message: 'Report window is unavailable.',
                )
              : ReportView(controller: reportController!),
        WindowRole.settings =>
          settingsController == null
              ? const _PlaceholderRolePage(
                  title: 'Settings',
                  message: 'Settings window is unavailable.',
                )
              : SettingsView(controller: settingsController!),
        WindowRole.quickEntry => const _PlaceholderRolePage(
          title: 'Update Task',
          message: 'Quick entry is managed by the tray process.',
        ),
      },
    );
  }
}

class _WydAppState extends State<WydApp> {
  WydAppController? get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller?.addListener(_controllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller?.initialize();
    });
  }

  @override
  void didUpdateWidget(WydApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) {
      return;
    }

    oldWidget.controller?.removeListener(_controllerChanged);
    widget.controller?.addListener(_controllerChanged);
  }

  @override
  void dispose() {
    _controller?.removeListener(_controllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return MaterialApp(
      title: 'wyd',
      theme: buildWydTheme(),
      home: controller == null
          ? const WydHomePage()
          : WydRolePage(controller: controller),
    );
  }

  void _controllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }
}

class WydHomePage extends StatelessWidget {
  const WydHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('wyd')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("What's ya doin?", style: textTheme.headlineMedium),
                const SizedBox(height: 12),
                const Text(
                  'Domain core is ready. Tray, persistence, scheduling, and '
                  'desktop windows will be layered on top in later milestones.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class WydRolePage extends StatelessWidget {
  const WydRolePage({super.key, required this.controller});

  final WydAppController controller;

  @override
  Widget build(BuildContext context) {
    final startupError = controller.startupError;
    if (startupError != null) {
      return _StartupErrorPage(message: startupError);
    }

    final page = switch (controller.activeRole) {
      WindowRole.quickEntry => QuickEntryView(
        controller: controller.quickEntry,
      ),
      WindowRole.report =>
        controller.reportController == null
            ? const _PlaceholderRolePage(
                title: 'Report',
                message: 'Report window is unavailable.',
              )
            : ReportView(controller: controller.reportController!),
      WindowRole.settings =>
        controller.settingsController == null
            ? const _PlaceholderRolePage(
                title: 'Settings',
                message: 'Settings window is unavailable.',
              )
            : SettingsView(controller: controller.settingsController!),
      null => const _TrayResidentPage(),
    };

    return page;
  }
}

class _TrayResidentPage extends StatelessWidget {
  const _TrayResidentPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('wyd is running in the tray.')),
    );
  }
}

class _PlaceholderRolePage extends StatelessWidget {
  const _PlaceholderRolePage({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

class _StartupErrorPage extends StatelessWidget {
  const _StartupErrorPage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('wyd startup error')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Unable to start tray app',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(message),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
