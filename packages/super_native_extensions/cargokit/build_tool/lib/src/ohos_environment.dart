import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:path/path.dart' as path;
import 'package:version/version.dart';

import 'target.dart';
import 'util.dart';

class OhosEnvironment {
  OhosEnvironment();

  Future<Map<String, String>> buildEnvironment() async {
    final pkgConfig = 'PKG_CONFIG_SYSROOT_DIR';
    final ccKey = 'CC_aarch64_unknown_linux_ohos';
    final arKey = 'AR_aarch64_unknown_linux_ohos';
    final cargoOhosLinkerKey = 'CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER';
    final cargoOhosArKey = 'CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_AR';
    final cargoRustFlagsKey = 'CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_RUSTFLAGS';
    return {
      pkgConfig: Platform.environment[pkgConfig]!,
      ccKey: Platform.environment[ccKey]!,
      arKey: Platform.environment[arKey]!,
      cargoOhosLinkerKey: Platform.environment[cargoOhosLinkerKey]!,
      cargoOhosArKey: Platform.environment[cargoOhosArKey]!,
      cargoRustFlagsKey: Platform.environment[cargoRustFlagsKey]!,
    };
  }

}
