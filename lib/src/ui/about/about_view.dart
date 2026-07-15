import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../layout_metrics.dart';

typedef AboutAppInfoLoader = Future<AboutAppInfo> Function();
typedef AboutLinkLauncher = Future<bool> Function(Uri url);

const _snapshotCommit = String.fromEnvironment('WYD_SNAPSHOT_COMMIT');

final class WydAboutMetadata {
  const WydAboutMetadata._();

  static const appName = 'wyd';
  static const description = 'Time tracking that nags you';
  static const author = 'Eric Anderson';
  static const legalese = 'Public domain under the Unlicense.';
  static const website = 'https://github.com/eric1234/wyd';
  static final websiteUri = Uri.parse(website);
}

final class AboutAppInfo {
  const AboutAppInfo({
    required this.version,
    required this.buildNumber,
    this.snapshotCommit = '',
  });

  factory AboutAppInfo.fromPackageInfo(PackageInfo packageInfo) {
    return AboutAppInfo(
      version: packageInfo.version,
      buildNumber: packageInfo.buildNumber,
      snapshotCommit: _snapshotCommit,
    );
  }

  final String version;
  final String buildNumber;
  final String snapshotCommit;

  String get versionLabel =>
      version.isEmpty ? 'Version unknown' : 'Version $version';

  String get buildLabel =>
      buildNumber.isEmpty ? 'Build unknown' : 'Build $buildNumber';

  String get snapshotLabel {
    final commit = snapshotCommit.length > 7
        ? snapshotCommit.substring(0, 7)
        : snapshotCommit;
    return 'Snapshot $commit';
  }
}

Future<AboutAppInfo> loadWydAboutAppInfo() async {
  return AboutAppInfo.fromPackageInfo(await PackageInfo.fromPlatform());
}

Future<bool> launchWydAboutLink(Uri url) {
  return launchUrl(url, mode: LaunchMode.externalApplication);
}

class AboutView extends StatefulWidget {
  const AboutView({
    super.key,
    this.infoLoader = loadWydAboutAppInfo,
    this.linkLauncher = launchWydAboutLink,
  });

  final AboutAppInfoLoader infoLoader;
  final AboutLinkLauncher linkLauncher;

  @override
  State<AboutView> createState() => _AboutViewState();
}

class _AboutViewState extends State<AboutView> {
  late Future<AboutAppInfo> _infoFuture;

  @override
  void initState() {
    super.initState();
    _infoFuture = widget.infoLoader();
  }

  @override
  void didUpdateWidget(AboutView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.infoLoader != widget.infoLoader) {
      _infoFuture = widget.infoLoader();
    }
  }

  @override
  Widget build(BuildContext context) {
    final metrics = WydLayoutMetrics.of(context);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: metrics.insetsAll(1.5),
          child: _AboutContent(
            infoFuture: _infoFuture,
            onOpenWebsite: _openWebsite,
          ),
        ),
      ),
    );
  }

  Future<void> _openWebsite() async {
    final bool launched;
    try {
      launched = await widget.linkLauncher(WydAboutMetadata.websiteUri);
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showWebsiteError();
      return;
    }
    if (launched || !mounted) {
      return;
    }

    _showWebsiteError();
  }

  void _showWebsiteError() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Unable to open website.')));
  }
}

class _AboutContent extends StatelessWidget {
  const _AboutContent({required this.infoFuture, required this.onOpenWebsite});

  final Future<AboutAppInfo> infoFuture;
  final VoidCallback onOpenWebsite;

  @override
  Widget build(BuildContext context) {
    final metrics = WydLayoutMetrics.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Image.asset(
              'assets/app_icon.png',
              width: metrics.size(3),
              height: metrics.size(3),
              errorBuilder: (context, error, stackTrace) {
                return Icon(Icons.access_time, size: metrics.size(3));
              },
            ),
            SizedBox(width: metrics.space(1)),
            Expanded(
              child: Text(
                WydAboutMetadata.appName,
                style: textTheme.headlineSmall,
              ),
            ),
          ],
        ),
        SizedBox(height: metrics.space(1)),
        const Text(WydAboutMetadata.description),
        SizedBox(height: metrics.space(1)),
        const _AboutDetail(label: 'Author', value: WydAboutMetadata.author),
        SizedBox(height: metrics.space(0.5)),
        FutureBuilder<AboutAppInfo>(
          future: infoFuture,
          builder: (context, snapshot) {
            final version = switch (snapshot.connectionState) {
              ConnectionState.done when snapshot.hasData =>
                snapshot.data!.versionLabel,
              ConnectionState.done => 'Version unavailable',
              _ => 'Version loading...',
            };
            final build = switch (snapshot.connectionState) {
              ConnectionState.done when snapshot.hasData =>
                snapshot.data!.buildLabel,
              ConnectionState.done => 'Build unavailable',
              _ => 'Build loading...',
            };
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(version),
                SizedBox(height: metrics.space(0.5)),
                Text(build),
                if (snapshot.data?.snapshotCommit.isNotEmpty ?? false) ...[
                  SizedBox(height: metrics.space(0.5)),
                  Text(snapshot.data!.snapshotLabel),
                ],
              ],
            );
          },
        ),
        SizedBox(height: metrics.space(1)),
        _AboutLink(label: WydAboutMetadata.website, onActivate: onOpenWebsite),
        SizedBox(height: metrics.space(1)),
        Text(
          WydAboutMetadata.legalese,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _AboutDetail extends StatelessWidget {
  const _AboutDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }
}

class _AboutLink extends StatelessWidget {
  const _AboutLink({required this.label, required this.onActivate});

  final String label;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: color,
      decoration: TextDecoration.underline,
      decorationColor: color,
    );

    return Semantics(
      link: true,
      label: label,
      onTap: onActivate,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              onActivate();
              return null;
            },
          ),
        },
        child: Builder(
          builder: (context) {
            final focused = Focus.of(context).hasFocus;
            return DecoratedBox(
              decoration: focused
                  ? BoxDecoration(
                      border: Border.all(color: color),
                      borderRadius: BorderRadius.circular(2),
                    )
                  : const BoxDecoration(),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onActivate,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(label, style: style),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
