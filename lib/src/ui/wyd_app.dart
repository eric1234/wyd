import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../application/application.dart';
import 'layout_metrics.dart';
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
      builder: _buildWithScalingAdjustment,
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

class WydFatalStartupApp extends StatelessWidget {
  const WydFatalStartupApp({
    super.key,
    required this.message,
    required this.onExit,
  });

  final String message;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'wyd',
      theme: buildWydTheme(),
      builder: _buildWithScalingAdjustment,
      home: _StartupErrorPage(message: message, onExit: onExit),
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
      builder: _buildWithScalingAdjustment,
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

Widget _buildWithScalingAdjustment(BuildContext context, Widget? child) {
  final content = child ?? const SizedBox.shrink();
  final mediaQuery = MediaQuery.of(context);
  final textScale = mediaQuery.textScaler.scale(1);
  final adjustment = WydTextScaleAdjustment.resolve(
    isLinux: Platform.isLinux,
    environment: Platform.environment,
    devicePixelRatio: mediaQuery.devicePixelRatio,
    textScale: textScale,
  );
  final adjustedContent = adjustment.adjusted
      ? MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(adjustment.adjustedTextScale),
          ),
          child: content,
        )
      : content;

  return adjustedContent;
}

class WydHomePage extends StatelessWidget {
  const WydHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final metrics = WydLayoutMetrics.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('wyd')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: metrics.insetsAll(1.5),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: metrics.maxWidth(32.5, min: 520),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("What's ya doin?", style: textTheme.headlineMedium),
                  SizedBox(height: metrics.space(0.75)),
                  const Text(
                    'Domain core is ready. Tray, persistence, scheduling, and '
                    'desktop windows will be layered on top in later milestones.',
                  ),
                ],
              ),
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
      return _StartupErrorPage(
        message: startupError,
        onExit: () => unawaited(controller.exitAfterStartupError()),
      );
    }

    final runtimeError = controller.runtimeErrorMessage;
    if (runtimeError != null) {
      return _RuntimeErrorPage(
        message: runtimeError,
        onDismiss: () => unawaited(controller.dismissRuntimeError()),
      );
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
    final metrics = WydLayoutMetrics.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: metrics.insetsAll(1.5),
            child: Text(message, textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }
}

class _StartupErrorPage extends StatelessWidget {
  const _StartupErrorPage({required this.message, required this.onExit});

  final String message;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final metrics = WydLayoutMetrics.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('wyd startup error')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: metrics.insetsAll(1.5),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: metrics.maxWidth(32.5, min: 520),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Unable to start tray app',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  SizedBox(height: metrics.space(0.75)),
                  Text(message),
                  SizedBox(height: metrics.space(1.5)),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: onExit,
                      child: const Text('Exit'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RuntimeErrorPage extends StatelessWidget {
  const _RuntimeErrorPage({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final metrics = WydLayoutMetrics.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('wyd error')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: metrics.insetsAll(1.5),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: metrics.maxWidth(32.5, min: 520),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Operation failed',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  SizedBox(height: metrics.space(0.75)),
                  Text(message),
                  SizedBox(height: metrics.space(1.5)),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: onDismiss,
                      child: const Text('Dismiss'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
