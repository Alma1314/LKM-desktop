import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app_update/azhon_app_update.dart';
import 'package:flutter_app_update/result_model.dart';
import 'package:flutter_app_update/update_model.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:logging/logging.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:process_run/process_run.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/models.dart';
import '../api/solsynth_express_api.dart';
import '../ui/update_sheet.dart';
import '../ui/whats_new_sheet.dart';

const bool kEnableBuiltInUpdate = true;
const kDefaultDistributionApiBaseUrl = 'https://dx.solsynth.dev/api';
const kDefaultDistributionProductId = '5260a14a-97f3-431c-9c2a-b174a4de7d97';

/// Runs an extracted installer executable with [arguments]. Test seam for
/// [UpdateService.runWindowsInstaller]; production uses [_runInstaller].
typedef WindowsInstallerRunner =
    Future<ProcessResult> Function(
      String executablePath,
      List<String> arguments,
    );

Future<ProcessResult> _runInstaller(
  String executablePath,
  List<String> arguments,
) => Process.run(executablePath, arguments);

/// Information about an app version upgrade check.
class VersionUpgradeInfo {
  const VersionUpgradeInfo({
    required this.currentVersion,
    required this.previousVersion,
    required this.isUpgrade,
    required this.isFirstRun,
  });

  /// The version currently executing in this process.
  final String currentVersion;

  /// The version previously recorded in preferences, or null on first run.
  final String? previousVersion;

  /// True if a previous version was stored and it differs from [currentVersion].
  final bool isUpgrade;

  /// True if no previous version was stored yet.
  final bool isFirstRun;

  @override
  String toString() =>
      'VersionUpgradeInfo(current: $currentVersion, previous: $previousVersion, isUpgrade: $isUpgrade, isFirstRun: $isFirstRun)';
}

/// High-level update facade for Flutter applications.
class UpdateService {
  UpdateService({
    SolsynthExpressApi? api,
    Dio? dio,
    String? apiBaseUrl,
    String? productId,
    this.channel = 'stable',
    this.enabled = true,
  }) : _api =
           api ??
           SolsynthExpressApi(
             baseUrl:
                 apiBaseUrl ??
                 const String.fromEnvironment(
                   'DISTRIBUTION_API_BASE_URL',
                   defaultValue: kDefaultDistributionApiBaseUrl,
                 ),
             productId:
                 productId ??
                 const String.fromEnvironment(
                   'DISTRIBUTION_PRODUCT_ID',
                   defaultValue: kDefaultDistributionProductId,
                 ),
             dio: dio,
           );

  final SolsynthExpressApi _api;
  final String channel;
  final bool enabled;

  /// Strips the ABI version-code offset Flutter's Gradle plugin adds when an
  /// Android app is built with `--split-per-abi`.
  ///
  /// The plugin overrides each split APK's version code with
  /// `ABI_VERSION[abi] * 1000 + versionCode` (see `FlutterPluginConstants` in
  /// flutter_tools): armeabi-v7a adds 1,000, arm64-v8a 2,000, and x86_64
  /// 4,000. `package_info_plus` then reports the overridden value, so the
  /// build number must be normalized before comparing against releases, which
  /// use the canonical version code. Builds below the offset (non-split) and
  /// non-Android platforms are returned unchanged.
  @visibleForTesting
  static int normalizeBuildNumber(
    int buildNumber,
    String platform,
    String architecture,
  ) {
    if (platform != 'android') return buildNumber;
    final offset = switch (architecture) {
      'armeabi-v7a' => 1000,
      'arm64' => 2000,
      'x86_64' => 4000,
      _ => 0,
    };
    if (offset == 0 || buildNumber < offset) return buildNumber;
    return buildNumber - offset;
  }

  /// Checks for a newer release and presents [UpdateSheet] when one exists.
  Future<void> checkForUpdates(BuildContext context) async {
    if (!enabled || !kEnableBuiltInUpdate || kIsWeb || !_api.isConfigured) {
      return;
    }
    // Resolve synchronously so the locale survives the async gaps below.
    final localeTag = Localizations.localeOf(context).toLanguageTag();
    try {
      final info = await PackageInfo.fromPlatform();
      final target = await _currentTarget();
      if (target == null) return;
      final parsedBuildNumber = int.tryParse(info.buildNumber);
      final currentVersion = parsedBuildNumber == null
          ? '${info.version}+${info.buildNumber}'
          : '${info.version}+${normalizeBuildNumber(
              parsedBuildNumber,
              target.platform,
              target.architecture,
            )}';
      final result = await _api.checkForUpdate(
        currentVersion: currentVersion,
        platform: target.platform,
        architecture: target.architecture,
        channel: channel,
        clientVersion: currentVersion,
        osVersion: target.osVersion.isEmpty ? null : target.osVersion,
        locale: localeTag,
      );
      if (!result.updateAvailable ||
          result.release == null ||
          !context.mounted) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (context.mounted) await showUpdateSheet(context, result.release!);
    } catch (error, stackTrace) {
      Logger.root.severe(
        '[Solsynth Express] Update check failed',
        error,
        stackTrace,
      );
    }
  }

  /// Presents a release without checking the network.
  Future<void> showUpdateSheet(
    BuildContext context,
    DistributionReleaseInfo release,
  ) async {
    if (!context.mounted) return;
    final target = await _currentTarget();
    if (!context.mounted) return;
    final artifact = target == null
        ? null
        : release.artifactFor(target.platform, target.architecture);
    final currentVersion = await _runningVersion(target);
    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (_) => UpdateSheet(
        release: release,
        currentVersion: currentVersion,
        artifact: artifact,
        onInstall: artifact == null
            ? null
            : switch (target!.platform) {
                'android' => () => installAndroidUpdate(
                  artifact.downloadUrl,
                  apkName: 'solian-update-${release.tagName}.apk',
                ),
                'windows' => () => performAutomaticWindowsUpdate(
                  context,
                  artifact.downloadUrl,
                ),
                'linux' => () => performAutomaticLinuxUpdate(
                  context,
                  artifact.downloadUrl,
                ),
                _ => null,
              },
      ),
    );
  }

  /// Key in [SharedPreferences] used to store the last known app version.
  static const kDefaultLastKnownVersionKey =
      'solsynth_express_last_known_version';

  /// Returns the current running version string for this platform/process,
  /// e.g. "3.3.0+144".
  Future<String?> getRunningVersion() async {
    final target = await _currentTarget();
    return _runningVersion(target);
  }

  /// Retrieves the version string stored in [SharedPreferences], or null.
  Future<String?> getLastKnownVersion({
    String key = kDefaultLastKnownVersionKey,
    SharedPreferences? preferences,
  }) async {
    final prefs = preferences ?? await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  /// Records [version] (or the currently running version if omitted) into
  /// [SharedPreferences] so future launches can compare against it.
  Future<void> saveCurrentVersion({
    String? version,
    String key = kDefaultLastKnownVersionKey,
    SharedPreferences? preferences,
  }) async {
    final ver = version ?? await getRunningVersion();
    if (ver == null || ver.isEmpty) return;
    final prefs = preferences ?? await SharedPreferences.getInstance();
    await prefs.setString(key, ver);
  }

  /// Compares the currently running version against the version saved in
  /// [SharedPreferences].
  ///
  /// Returns a [VersionUpgradeInfo] indicating if an upgrade occurred,
  /// if this is the first recorded run, and the versions involved.
  Future<VersionUpgradeInfo> checkVersionUpgrade({
    String key = kDefaultLastKnownVersionKey,
    SharedPreferences? preferences,
  }) async {
    final current = await getRunningVersion() ?? '';
    final previous = await getLastKnownVersion(
      key: key,
      preferences: preferences,
    );

    if (previous == null || previous.isEmpty) {
      return VersionUpgradeInfo(
        currentVersion: current,
        previousVersion: null,
        isUpgrade: false,
        isFirstRun: true,
      );
    }

    final isUpgrade = current.isNotEmpty && current != previous;
    return VersionUpgradeInfo(
      currentVersion: current,
      previousVersion: previous,
      isUpgrade: isUpgrade,
      isFirstRun: false,
    );
  }

  /// Searches published releases for one matching [version] (or tag).
  /// Falls back to the latest release if no exact match is found.
  Future<DistributionReleaseInfo?> fetchReleaseForVersion(
    String version, {
    String? platform,
    String? architecture,
  }) async {
    if (!enabled || !_api.isConfigured) return null;
    final target = await _currentTarget();
    final p = platform ?? target?.platform;
    final a = architecture ?? target?.architecture;

    try {
      final page = await _api.listReleases(
        channel: channel,
        platform: p,
        architecture: a,
        limit: 10,
      );
      final cleanVersion = version.trim();
      for (final rel in page.data) {
        if (rel.tagName == cleanVersion ||
            rel.tagName == 'v$cleanVersion' ||
            'v${rel.tagName}' == cleanVersion ||
            cleanVersion.startsWith(rel.tagName) ||
            rel.tagName.startsWith(cleanVersion)) {
          return rel;
        }
      }
      return page.data.isNotEmpty ? page.data.first : null;
    } catch (e) {
      Logger.root.warning(
        '[Solsynth Express] Failed to fetch release for version $version: $e',
      );
      return null;
    }
  }

  /// Presents the [WhatsNewSheet] for [release].
  Future<void> showWhatsNewSheet(
    BuildContext context,
    DistributionReleaseInfo release, {
    String? previousVersion,
    VoidCallback? onDismiss,
  }) async {
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (_) => WhatsNewSheet(
        release: release,
        previousVersion: previousVersion,
        onDismiss: onDismiss,
      ),
    );
  }

  /// Version of the running build, in the same shape the update check sends.
  /// Null when the platform package is unavailable (tests, unsupported hosts).
  Future<String?> _runningVersion(_UpdateTarget? target) async {
    try {
      final info = await PackageInfo.fromPlatform();
      final parsedBuildNumber = int.tryParse(info.buildNumber);
      if (parsedBuildNumber == null || target == null) {
        return '${info.version}+${info.buildNumber}';
      }
      return '${info.version}+${normalizeBuildNumber(
        parsedBuildNumber,
        target.platform,
        target.architecture,
      )}';
    } catch (error) {
      Logger.root.fine('[Solsynth Express] Running version unavailable: $error');
      return null;
    }
  }

  Future<DistributionReleaseInfo?> fetchLatestRelease({
    String? platform,
    String? architecture,
  }) async {
    if (!enabled || !_api.isConfigured) return null;
    return _api.fetchLatestRelease(
      channel: channel,
      platform: platform,
      architecture: architecture,
    );
  }

  Future<List<DistributionChannel>> fetchChannels() {
    if (!_api.isConfigured) return Future.value(const []);
    return _api.listChannels();
  }

  Future<int> cleanupPreviousUpdateArtifacts() async {
    final tempDir = await getTemporaryDirectory();
    var deleted = 0;
    for (final entity in tempDir.listSync(followLinks: false)) {
      final fileName = path.basename(entity.path);
      final removableFile =
          entity is File &&
          ((fileName.startsWith('solian-update-') &&
                  fileName.endsWith('.apk')) ||
              (fileName.startsWith('solian-installer-') &&
                  fileName.endsWith('.zip')) ||
              (fileName.startsWith('solian-linux-') &&
                  (fileName.endsWith('.zip') ||
                      fileName.endsWith('.AppImage'))));
      final removableDirectory =
          entity is Directory &&
          (fileName.startsWith('solian-installer-') ||
              fileName.startsWith('solian-linux-'));
      if (!removableFile && !removableDirectory) continue;
      try {
        await entity.delete(recursive: entity is Directory);
        deleted++;
      } catch (error) {
        Logger.root.warning(
          '[Solsynth Express] Failed to clean $fileName: $error',
        );
      }
    }
    return deleted;
  }

  Future<void> installAndroidUpdate(
    String url, {
    required String apkName,
  }) async {
    if (!Platform.isAndroid) return;
    AzhonAppUpdate.dispose();
    AzhonAppUpdate.listener((ResultModel result) {
      if (result.type == ResultType.done) {
        unawaited(
          Future<void>.delayed(const Duration(seconds: 10), () async {
            await _cleanupFile(result.apk);
          }),
        );
      }
    });
    try {
      await AzhonAppUpdate.update(
        UpdateModel(
          url,
          apkName,
          'launcher_icon',
          'https://apps.apple.com/us/app/solian/id6499032345',
        ),
      );
    } catch (error) {
      AzhonAppUpdate.dispose();
      Logger.root.warning('[Solsynth Express] Android update failed: $error');
      rethrow;
    }
  }

  Future<void> performAutomaticWindowsUpdate(
    BuildContext context,
    String url,
  ) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _InstallProgressDialog(service: this, updateUrl: url, linux: false),
    );
  }

  Future<void> performAutomaticLinuxUpdate(
    BuildContext context,
    String url,
  ) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _InstallProgressDialog(service: this, updateUrl: url, linux: true),
    );
  }

  Future<_UpdateTarget?> _currentTarget() async {
    if (kIsWeb) return null;
    final platform = Platform.isAndroid
        ? 'android'
        : Platform.isWindows
        ? 'windows'
        : Platform.isLinux
        ? 'linux'
        : Platform.isMacOS
        ? 'macos'
        : Platform.isIOS
        ? 'ios'
        : '';
    final architecture = await _currentArchitecture();
    final osVersion = await _currentOSVersion();
    if (platform.isEmpty || architecture.isEmpty) return null;
    return _UpdateTarget(platform, architecture, osVersion);
  }

  /// Best-effort OS version for update-check telemetry. Platform channels are
  /// unavailable in some environments (tests, web), so failures degrade to an
  /// empty string rather than blocking the update check.
  Future<String> _currentOSVersion() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        return (await deviceInfo.androidInfo).version.release;
      }
      if (Platform.isIOS) {
        return (await deviceInfo.iosInfo).systemVersion;
      }
      if (Platform.isMacOS) {
        return (await deviceInfo.macOsInfo).osRelease;
      }
      if (Platform.isLinux) {
        return (await deviceInfo.linuxInfo).version ?? '';
      }
      if (Platform.isWindows) {
        final info = await deviceInfo.windowsInfo;
        return '${info.majorVersion}.${info.minorVersion}.${info.buildNumber}';
      }
    } catch (error) {
      Logger.root.fine('[Solsynth Express] OS version unavailable: $error');
    }
    return '';
  }

  Future<String> _currentArchitecture() async {
    if (Platform.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      for (final abi in info.supportedAbis) {
        switch (abi) {
          case 'arm64-v8a':
            return 'arm64';
          case 'armeabi-v7a':
            return 'armeabi-v7a';
          case 'x86_64':
            return 'x86_64';
          case 'x86':
            return 'x86';
        }
      }
    }
    if (Platform.isWindows) {
      final value =
          Platform.environment['PROCESSOR_ARCHITEW6432'] ??
          Platform.environment['PROCESSOR_ARCHITECTURE'];
      if (value != null) {
        return switch (value.toUpperCase()) {
          'AMD64' || 'X86_64' => 'amd64',
          'ARM64' => 'arm64',
          _ => value.toLowerCase(),
        };
      }
    }
    if (Platform.isLinux) return 'amd64';
    if (Platform.isMacOS || Platform.isIOS) return 'arm64';
    return '';
  }

  Future<String?> _download(
    String url,
    String prefix,
    String extension, {
    void Function(int received, int total)? onProgress,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final filePath = path.join(
        tempDir.path,
        '$prefix${DateTime.now().millisecondsSinceEpoch}$extension',
      );
      final response = await Dio().download(
        url,
        filePath,
        onReceiveProgress: onProgress,
      );
      return response.statusCode == 200 ? filePath : null;
    } catch (error, stackTrace) {
      Logger.root.severe(
        '[Solsynth Express] Download failed',
        error,
        stackTrace,
      );
      return null;
    }
  }

  Future<String?> _extractWindows(String zipPath) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final extractDir = path.join(
        tempDir.path,
        'solian-installer-${DateTime.now().millisecondsSinceEpoch}',
      );
      final archive = ZipDecoder().decodeBytes(
        await File(zipPath).readAsBytes(),
      );
      for (final entry in archive) {
        final filePath = path.join(extractDir, entry.name);
        if (entry.isFile) {
          await Directory(path.dirname(filePath)).create(recursive: true);
          await File(filePath).writeAsBytes(entry.content as List<int>);
        } else {
          await Directory(filePath).create(recursive: true);
        }
      }
      return extractDir;
    } catch (error, stackTrace) {
      Logger.root.severe(
        '[Solsynth Express] Windows extraction failed',
        error,
        stackTrace,
      );
      return null;
    }
  }

  /// Inno Setup switches for an unattended, in-place upgrade.
  ///
  /// `/SILENT` skips every wizard page and shows only the progress window,
  /// `/SP-` drops the initial confirmation prompt, `/SUPPRESSMSGBOXES` answers
  /// the confirmations that remain with their documented default, `/NORESTART`
  /// never reboots, and `/CLOSEAPPLICATIONS` lets Setup close this running
  /// instance through the Restart Manager before it replaces the executable.
  /// `/LOG` leaves a trace in the user's TEMP directory, the only diagnostic
  /// available when an unattended install fails after this process was closed.
  static const windowsInstallArguments = <String>[
    '/SP-',
    '/SILENT',
    '/SUPPRESSMSGBOXES',
    '/NORESTART',
    '/CLOSEAPPLICATIONS',
    '/LOG',
  ];

  /// Runs an extracted Inno Setup installer and reports whether it succeeded.
  ///
  /// The arguments travel as a list instead of a joined command line, so an
  /// install directory containing spaces (`C:\Program Files\MaidKit`) survives.
  /// A non-zero exit code covers both a failed install and a dismissed UAC
  /// prompt, after which Setup stops on its own.
  Future<bool> runWindowsInstaller(
    String executablePath, {
    WindowsInstallerRunner? runner,
  }) async {
    try {
      final result = await (runner ?? _runInstaller)(
        executablePath,
        windowsInstallArguments,
      );
      return result.exitCode == 0;
    } catch (error) {
      Logger.root.severe('[Solsynth Express] Windows install failed: $error');
      return false;
    }
  }

  Future<bool> _runWindowsInstaller(String extractDir) async {
    try {
      final executable = Directory(extractDir)
          .listSync()
          .whereType<File>()
          .firstWhere((file) => file.path.endsWith('.exe'));
      return await runWindowsInstaller(executable.path);
    } catch (error) {
      Logger.root.severe('[Solsynth Express] Windows install failed: $error');
      return false;
    }
  }

  Future<bool> _installLinux(String zipPath) async {
    String? extractDir;
    try {
      final tempDir = await getTemporaryDirectory();
      extractDir = path.join(
        tempDir.path,
        'solian-linux-${DateTime.now().millisecondsSinceEpoch}',
      );
      final archive = ZipDecoder().decodeBytes(
        await File(zipPath).readAsBytes(),
      );
      String? appImage;
      for (final entry in archive) {
        final filePath = path.join(extractDir, entry.name);
        if (entry.isFile) {
          await Directory(path.dirname(filePath)).create(recursive: true);
          await File(filePath).writeAsBytes(entry.content as List<int>);
          if (entry.name.endsWith('.AppImage')) appImage = filePath;
        } else {
          await Directory(filePath).create(recursive: true);
        }
      }
      if (appImage == null) return false;
      await Shell().run('chmod +x "$appImage"');
      final home = Platform.environment['HOME'];
      if (home == null || home.isEmpty) return false;
      final destinationDir = path.join(home, '.local', 'bin');
      await Directory(destinationDir).create(recursive: true);
      await File(appImage).copy(path.join(destinationDir, 'solian.AppImage'));
      return true;
    } catch (error) {
      Logger.root.severe('[Solsynth Express] Linux install failed: $error');
      return false;
    } finally {
      await _cleanupDirectory(extractDir);
    }
  }

  static Future<void> _cleanupFile(String? filePath) async {
    if (filePath == null || filePath.isEmpty) return;
    try {
      final file = File(filePath);
      if (await file.exists()) await file.delete();
    } catch (error) {
      Logger.root.warning('[Solsynth Express] Failed to delete file: $error');
    }
  }

  static Future<void> _cleanupDirectory(String? dirPath) async {
    if (dirPath == null || dirPath.isEmpty) return;
    try {
      final directory = Directory(dirPath);
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (error) {
      Logger.root.warning(
        '[Solsynth Express] Failed to delete directory: $error',
      );
    }
  }
}

class _UpdateTarget {
  const _UpdateTarget(this.platform, this.architecture, this.osVersion);
  final String platform;
  final String architecture;
  final String osVersion;
}

class _InstallProgressDialog extends StatefulWidget {
  const _InstallProgressDialog({
    required this.service,
    required this.updateUrl,
    required this.linux,
  });

  final UpdateService service;
  final String updateUrl;
  final bool linux;

  @override
  State<_InstallProgressDialog> createState() => _InstallProgressDialogState();
}

class _InstallProgressDialogState extends State<_InstallProgressDialog> {
  double? progress;
  String? message;
  bool finished = false;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    String? downloaded;
    String? extracted;
    try {
      // On Windows Setup closes this process to replace its own executable, so
      // the `finally` cleanup below never runs and the artifacts of every
      // unattended upgrade would pile up in TEMP. Reclaim them before the new
      // download adds to them.
      await widget.service.cleanupPreviousUpdateArtifacts();
      downloaded = await widget.service._download(
        widget.updateUrl,
        widget.linux ? 'solian-linux-' : 'solian-installer-',
        widget.linux ? '.zip' : '.zip',
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() => progress = total <= 0 ? null : received / total);
        },
      );
      if (downloaded == null) throw const _UpdateInstallFailure();
      if (!mounted) return;
      setState(() {
        message = widget.linux
            ? 'updateInstallingAppImage'.tr()
            : 'updateExtractingInstaller'.tr();
        progress = null;
      });
      final success = widget.linux
          ? await widget.service._installLinux(downloaded)
          : await (() async {
              extracted = await widget.service._extractWindows(downloaded!);
              return extracted != null &&
                  await widget.service._runWindowsInstaller(extracted!);
            })();
      if (!mounted) return;
      if (!success) throw const _UpdateInstallFailure();
      setState(() {
        message = 'updateComplete'.tr();
        progress = 1;
        finished = true;
      });
      await Future<void>.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      Navigator.of(context).pop();
      await showAttentionModal(
        id: 'solsynth-express-install-error',
        replaceIfExists: true,
        barrierDismissible: true,
        builder: (context, dismiss) => AttentionModalScaffold(
          titleText: 'updateFailed'.tr(),
          onDismiss: dismiss,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  error is _UpdateInstallFailure
                      ? 'updateFailedHint'.tr()
                      : '$error',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FilledButton(
                      onPressed: dismiss,
                      child: Text('ok'.tr()),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    } finally {
      await UpdateService._cleanupFile(downloaded);
      await UpdateService._cleanupDirectory(extracted);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _InstallProgressModal(
      progress: progress,
      message: message ?? 'updateDownloadingInstaller'.tr(),
      finished: finished,
    );
  }
}

/// Raised when the download or the installer step fails, so the error surface
/// can say what happened instead of echoing an exception's `toString()`.
class _UpdateInstallFailure implements Exception {
  const _UpdateInstallFailure();

  @override
  String toString() => 'Update install failed';
}


class _InstallProgressModal extends StatelessWidget {
  const _InstallProgressModal({
    required this.progress,
    required this.message,
    required this.finished,
  });

  final double? progress;
  final String message;
  final bool finished;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    finished ? Symbols.check_circle : Symbols.download,
                    size: 22,
                    color: finished ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      finished
                          ? 'updateComplete'.tr()
                          : 'updateInstalling'.tr(),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (progress != null)
                LinearProgressIndicator(
                  value: progress,
                  borderRadius: BorderRadius.circular(4),
                )
              else
                const LinearProgressIndicator(
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                ),
              const SizedBox(height: 12),
              Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
