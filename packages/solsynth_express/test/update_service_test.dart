import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solsynth_express/solsynth_express.dart';

class _RecordingApi extends SolsynthExpressApi {
  _RecordingApi()
    : super(
        baseUrl: 'https://distribution.example/api',
        productId: 'product-id',
      );

  String? requestedCurrentVersion;
  String? requestedClientVersion;
  String? requestedOSVersion;
  String? requestedLocale;

  @override
  Future<DistributionUpdateCheck> checkForUpdate({
    required String currentVersion,
    required String platform,
    required String architecture,
    String channel = 'stable',
    String? installationId,
    String? osVersion,
    String? clientVersion,
    String? locale,
  }) async {
    requestedCurrentVersion = currentVersion;
    requestedClientVersion = clientVersion;
    requestedOSVersion = osVersion;
    requestedLocale = locale;
    return DistributionUpdateCheck(
      updateAvailable: false,
      currentVersion: currentVersion,
      release: null,
    );
  }
}

void main() {
  testWidgets('update checks include the package build number', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'MaidKit',
      packageName: 'dev.solsynth.maidkit',
      version: '1.3.0',
      buildNumber: '20',
      buildSignature: '',
    );
    final api = _RecordingApi();
    final service = UpdateService(api: api);
    late BuildContext context;

    // The macOS host in the test environment has no native plugin registered;
    // mock the platform channel so the OS version is resolved synchronously.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/device_info'),
      (MethodCall call) async {
        if (call.method != 'getDeviceInfo') return null;
        return <String, dynamic>{
          'computerName': 'Test Mac',
          'hostName': 'test.local',
          'arch': 'arm64',
          'model': 'MacBookPro18,3',
          'modelName': 'MacBook Pro',
          'kernelVersion': 'Darwin Kernel Version 24.3.0',
          'osRelease': '24.3',
          'majorVersion': 24,
          'minorVersion': 3,
          'patchVersion': 0,
          'activeCPUs': 10,
          'memorySize': 17179869184,
          'cpuFrequency': 0,
          'systemGUID': 'TEST-GUID',
        };
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await service.checkForUpdates(context);

    expect(api.requestedCurrentVersion, '1.3.0+20');
    expect(api.requestedClientVersion, '1.3.0+20');
    // The MaterialApp default locale is en_US, which must be sent as a BCP-47
    // language tag for the metrics by_locale breakdown.
    expect(api.requestedLocale, 'en-US');
    expect(api.requestedOSVersion, '24.3');
  });

  group('Windows installer launch', () {
    test('runs Setup with the unattended upgrade flags', () async {
      final requests = <List<String>>[];
      final succeeded = await UpdateService().runWindowsInstaller(
        r'C:\Users\Test User\AppData\Local\Temp\windows-x86_64-setup.exe',
        runner: (executablePath, arguments) async {
          requests.add([executablePath, ...arguments]);
          return ProcessResult(4242, 0, '', '');
        },
      );
      expect(succeeded, isTrue);
      // The path arrives as one argument, not split at its space, and Setup is
      // told to install without showing the wizard.
      expect(requests.single, [
        r'C:\Users\Test User\AppData\Local\Temp\windows-x86_64-setup.exe',
        '/SP-',
        '/SILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
        '/CLOSEAPPLICATIONS',
        '/LOG',
      ]);
    });

    test('treats a non-zero Setup exit code as a failed update', () async {
      // Inno returns 1 when the user cancels before installation starts, which
      // includes dismissing the UAC prompt an admin install requires.
      final succeeded = await UpdateService().runWindowsInstaller(
        'setup.exe',
        runner: (_, __) async => ProcessResult(4242, 1, '', ''),
      );
      expect(succeeded, isFalse);
    });

    test('treats a Setup that cannot start as a failed update', () async {
      final succeeded = await UpdateService().runWindowsInstaller(
        'setup.exe',
        runner: (_, __) async => throw ProcessException('setup.exe', const []),
      );
      expect(succeeded, isFalse);
    });
  });

  group('Android split-per-abi build number normalization', () {
    test('strips the ABI offset from split APK version codes', () {
      expect(
        UpdateService.normalizeBuildNumber(1020, 'android', 'armeabi-v7a'),
        20,
      );
      expect(
        UpdateService.normalizeBuildNumber(2020, 'android', 'arm64'),
        20,
      );
      expect(
        UpdateService.normalizeBuildNumber(4020, 'android', 'x86_64'),
        20,
      );
    });

    test('strips the offset when the canonical build number is large', () {
      expect(
        UpdateService.normalizeBuildNumber(3520, 'android', 'arm64'),
        1520,
      );
    });

    test('leaves non-split builds untouched', () {
      expect(UpdateService.normalizeBuildNumber(20, 'android', 'arm64'), 20);
      expect(
        UpdateService.normalizeBuildNumber(20, 'android', 'armeabi-v7a'),
        20,
      );
      // x86 has no ABI offset (its Flutter support was removed), so a build
      // at or above an offset magnitude is not attributable to splitting.
      expect(UpdateService.normalizeBuildNumber(4020, 'android', 'x86'), 4020);
    });

    test('leaves non-Android platforms untouched', () {
      expect(UpdateService.normalizeBuildNumber(2020, 'macos', 'arm64'), 2020);
      expect(
        UpdateService.normalizeBuildNumber(2020, 'windows', 'amd64'),
        2020,
      );
    });
  });

  group('Version tracking and upgrade detection', () {
    setUp(() {
      PackageInfo.setMockInitialValues(
        appName: 'MaidKit',
        packageName: 'dev.solsynth.maidkit',
        version: '2.0.0',
        buildNumber: '50',
        buildSignature: '',
      );
    });

    test('detects first run when no version is saved', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = UpdateService();

      final upgrade = await service.checkVersionUpgrade(preferences: prefs);
      expect(upgrade.isFirstRun, isTrue);
      expect(upgrade.isUpgrade, isFalse);
      expect(upgrade.previousVersion, isNull);
      expect(upgrade.currentVersion, '2.0.0+50');
    });

    test('detects upgrade when stored version differs from current', () async {
      SharedPreferences.setMockInitialValues({
        UpdateService.kDefaultLastKnownVersionKey: '1.9.0+40',
      });
      final prefs = await SharedPreferences.getInstance();
      final service = UpdateService();

      final upgrade = await service.checkVersionUpgrade(preferences: prefs);
      expect(upgrade.isFirstRun, isFalse);
      expect(upgrade.isUpgrade, isTrue);
      expect(upgrade.previousVersion, '1.9.0+40');
      expect(upgrade.currentVersion, '2.0.0+50');
    });

    test('detects no upgrade when stored version equals current', () async {
      SharedPreferences.setMockInitialValues({
        UpdateService.kDefaultLastKnownVersionKey: '2.0.0+50',
      });
      final prefs = await SharedPreferences.getInstance();
      final service = UpdateService();

      final upgrade = await service.checkVersionUpgrade(preferences: prefs);
      expect(upgrade.isFirstRun, isFalse);
      expect(upgrade.isUpgrade, isFalse);
      expect(upgrade.previousVersion, '2.0.0+50');
      expect(upgrade.currentVersion, '2.0.0+50');
    });

    test('saveCurrentVersion records the running version to preferences', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = UpdateService();

      await service.saveCurrentVersion(preferences: prefs);
      expect(
        prefs.getString(UpdateService.kDefaultLastKnownVersionKey),
        '2.0.0+50',
      );
    });
  });
}
