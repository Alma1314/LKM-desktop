import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart' as legacy;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:island/mini_apps/mini_app_manifest.dart';
import 'package:island/mini_apps/mini_apps_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets(
    'the catalog renders a newly registered app without host changes',
    (tester) async {
      final apps = parseMiniAppCatalog(
        File('assets/webf/manifest.json').readAsStringSync(),
      );
      final extra = MiniAppManifest.fromJson({
        'id': 'new-tool',
        'apiVersion': 1,
        'version': '1.0.0',
        'icon': '🔧',
        'name': {'en-US': 'New tool'},
        'description': {'en-US': 'Discovered from a manifest'},
      });
      var currentApps = apps;
      final container = ProviderContainer(
        overrides: [
          miniAppCatalogProvider.overrideWith((ref) async => currentApps),
        ],
      );
      addTearDown(container.dispose);
      final screenshotKey = GlobalKey();
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        final bytes = File('assets/fonts/Nunito-Regular.ttf').readAsBytesSync();
        await (FontLoader(
          'Nunito',
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        final emoji = File('/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf');
        if (emoji.existsSync()) {
          await (FontLoader('Noto Color Emoji')..addFont(
                Future.value(ByteData.sublistView(emoji.readAsBytesSync())),
              ))
              .load();
        }
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: EasyLocalization(
              supportedLocales: const [Locale('en', 'US')],
              path: 'assets/i18n',
              saveLocale: false,
              child: Builder(
                builder: (context) => MaterialApp(
                  theme: ThemeData(
                    fontFamily: 'Nunito',
                    fontFamilyFallback: const ['Noto Color Emoji'],
                  ),
                  locale: context.locale,
                  supportedLocales: context.supportedLocales,
                  localizationsDelegates: [
                    ...context.localizationDelegates,
                    ...GlobalMaterialLocalizations.delegates,
                    legacy.GlobalMaterialLocalizations.delegate,
                    legacy.GlobalCupertinoLocalizations.delegate,
                  ],
                  home: RepaintBoundary(
                    key: screenshotKey,
                    child: const MiniAppsScreen(),
                  ),
                ),
              ),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      for (final name in ['StarHope', 'Notes', 'Focus timer']) {
        expect(find.text(name), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      final screenshot = Platform.environment['MINI_APPS_SCREENSHOT'];
      if (screenshot != null) {
        await tester.runAsync(() async {
          final boundary =
              screenshotKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File(screenshot).parent.createSync(recursive: true);
          File(screenshot).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      currentApps = [...apps, extra];
      container.invalidate(miniAppCatalogProvider);
      await tester.pumpAndSettle();
      expect(find.text('New tool'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
