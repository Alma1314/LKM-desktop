import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solsynth_express/solsynth_express.dart';

/// The package ships no translations of its own; the host app does. This loader
/// supplies the keys the sheet reads.
class _TestLoader extends AssetLoader {
  const _TestLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async =>
      Map<String, dynamic>.of(_strings);
}

const _strings = <String, dynamic>{
  'updateAvailable': 'Update available',
  'installUpdate': 'Install update',
  'openReleasePage': 'Open release page',
  'noChangelogProvided': 'No changelog provided.',
  'updateInstalledVersion': 'Installed',
  'updateChannelLabel': '{} channel',
  'updateDownloadSize': '{} download',
  'whatsNew': "What's new",
  'ok': 'OK',
};

DistributionReleaseInfo _release({String body = 'Fixed a few things.'}) {
  return DistributionReleaseInfo(
    id: 'r1',
    tagName: 'v3.3.0+144',
    name: 'MaidKit 3.3.0',
    body: body,
    htmlUrl: 'https://example.com/release',
    createdAt: DateTime(2026, 10, 18),
    publishedAt: DateTime(2026, 10, 18),
    channel: 'stable',
    forceUpdate: false,
    metadata: const {},
    artifacts: const [],
  );
}

const _artifact = DistributionArtifact(
  id: 'a1',
  platform: 'macos',
  architecture: 'arm64',
  fileName: 'MaidKit.zip',
  mimeType: 'application/zip',
  size: 42 * 1024 * 1024,
  hash: 'abc',
  downloadUrl: 'https://example.com/MaidKit.zip',
  expired: false,
);

Widget _host(Widget sheet) {
  return EasyLocalization(
    supportedLocales: const [Locale('en', 'US')],
    path: 'unused',
    assetLoader: const _TestLoader(),
    // Host applications forward these to MaterialApp; without them the
    // delegate never loads and every key renders as itself.
    child: Builder(
      builder: (context) {
        final localization = EasyLocalization.of(context)!;
        return MaterialApp(
          theme: ThemeData(useMaterial3: true),
          supportedLocales: localization.supportedLocales,
          localizationsDelegates: localization.delegates,
          home: Scaffold(body: sheet),
        );
      },
    ),
  );
}

void main() {
  setUpAll(() async {
    // EasyLocalization resolves the device locale through the platform
    // dispatcher before the widget tree exists; in tests both the preferences
    // channel and the locale channel need stand-ins.
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('update sheet renders release facts and install action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        UpdateSheet(
          release: _release(),
          currentVersion: '3.2.0+120',
          artifact: _artifact,
          onInstall: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Update available'), findsOneWidget);
    expect(find.text('MaidKit 3.3.0'), findsOneWidget);
    expect(find.text('Installed'), findsOneWidget);
    expect(find.text('3.2.0+120'), findsOneWidget);
    expect(find.text('Fixed a few things.'), findsOneWidget);
    expect(find.text('Install update'), findsOneWidget);
    expect(find.text('42.00 MB download'), findsOneWidget);
    expect(find.text('stable channel'), findsOneWidget);
    expect(find.text('2026-10-18'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('install disables while the callback runs', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var calls = 0;
    final pending = Completer<void>();

    await tester.pumpWidget(
      _host(
        UpdateSheet(
          release: _release(),
          artifact: _artifact,
          onInstall: () {
            calls++;
            return pending.future;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Install update'));
    await tester.pump();
    // A second tap while the callback is in flight must not start it again.
    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await tester.pump();

    expect(calls, 1);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    pending.complete();
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('no artifact falls back to the release page', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(UpdateSheet(release: _release(body: ''))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Install update'), findsNothing);
    expect(find.text('Open release page'), findsOneWidget);
    expect(find.text('No changelog provided.'), findsOneWidget);
  });

  testWidgets('long release body scrolls instead of overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final body = List.generate(
      60,
      (i) => '- item $i with a reasonably long line of changelog text',
    ).join('\n');

    await tester.pumpWidget(
      _host(
        UpdateSheet(
          release: _release(body: body),
          currentVersion: '3.2.0+120',
          artifact: _artifact,
          onInstall: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('update sheet has a surfaceContainerLow background Material', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        UpdateSheet(
          release: _release(),
          currentVersion: '3.2.0+120',
          artifact: _artifact,
          onInstall: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final material = tester.widget<Material>(
      find.descendant(
        of: find.byType(UpdateSheet),
        matching: find.byType(Material),
      ).first,
    );
    expect(material.color, isNotNull);
  });

  testWidgets('whats new sheet renders changelog and calls dismiss', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var dismissed = false;
    await tester.pumpWidget(
      _host(
        WhatsNewSheet(
          release: _release(),
          previousVersion: '3.2.0+120',
          onDismiss: () => dismissed = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("What's new"), findsOneWidget);
    expect(find.text('MaidKit 3.3.0'), findsOneWidget);
    expect(find.text('Installed'), findsOneWidget);
    expect(find.text('3.2.0+120'), findsOneWidget);
    expect(find.text('Fixed a few things.'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);

    final material = tester.widget<Material>(
      find.descendant(
        of: find.byType(WhatsNewSheet),
        matching: find.byType(Material),
      ).first,
    );
    expect(material.color, isNotNull);

    await tester.tap(find.text('OK'));
    expect(dismissed, isTrue);
  });
}
