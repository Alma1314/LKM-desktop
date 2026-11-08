import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:island/accounts/account_screen.dart';
import 'package:island/community/notification_pod.dart';
import 'package:island/community/user_pod.dart';
import 'package:island/core/api/auth_api.dart';
import 'package:island/core/config.dart';
import 'package:island/core/theme.dart';
import 'package:island/discovery/widgets/pill_app_bar.dart';
import 'package:island/shared/widgets/page_app_bar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _account = LkmAccount(
  id: 'account-1',
  username: 'alice',
  accountLevel: 'member',
  role: 'member',
  nickname: 'Alice',
);

Future<ThemeData> _windowsTheme() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWith((ref) => prefs)],
  );
  final theme = createAppTheme(
    Brightness.light,
    container.read(appSettingsProvider),
  );
  container.dispose();
  return theme.copyWith(platform: TargetPlatform.windows);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  // The title lives in the app bar's own title slot, so it starts right of the
  // drawer toggle and shares its vertical center instead of being centered by
  // the platform default.
  testWidgets('account header left aligns its title on Windows', (
    tester,
  ) async {
    final theme = await _windowsTheme();
    final prefs = await SharedPreferences.getInstance();
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWith((ref) => prefs),
            developerModeProvider.overrideWithValue(false),
            lkmMeProvider.overrideWith((ref) async => _account),
            lkmUnreadNotificationsProvider.overrideWith((ref) async => 0),
            myFollowingProvider.overrideWith((ref) async => const []),
          ],
          child: EasyLocalization(
            supportedLocales: const [Locale('en', 'US')],
            path: 'assets/i18n',
            saveLocale: false,
            child: Builder(
              builder: (context) => MaterialApp(
                locale: const Locale('en', 'US'),
                supportedLocales: const [Locale('en', 'US')],
                localizationsDelegates: context.localizationDelegates,
                theme: theme,
                home: const AccountFeatureWidget(),
              ),
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final appBar = find.byType(PillAppBar);
    expect(appBar, findsOneWidget);
    final leading = find.byType(SolDrawerButton);
    expect(leading, findsOneWidget);
    final title = find.descendant(of: appBar, matching: find.text('Account'));
    expect(title, findsOneWidget);

    expect(
      tester.getTopLeft(title).dx,
      greaterThan(tester.getTopRight(leading).dx),
      reason: 'the title must start after the leading drawer button',
    );
    expect(
      tester.getTopLeft(title).dx,
      lessThan(tester.getCenter(find.byType(Scaffold)).dx),
      reason: 'the title must follow the app-wide left alignment',
    );
    expect(
      tester.getCenter(title).dy,
      closeTo(tester.getCenter(leading).dy, 1.0),
      reason: 'the title must be vertically centered against the toggle',
    );

    // The page shows the LKM identity, not the old Solian profile block.
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('@alice'), findsOneWidget);
    expect(find.text('Logout'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
