import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

// Other platforms retain the existing Cargokit integration.
void main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    if (!input.config.buildCodeAssets ||
        input.config.code.targetOS != OS.ohos) {
      return;
    }
    if (!Platform.isLinux ||
        input.config.code.targetArchitecture != Architecture.arm64) {
      throw StateError('OHOS native extensions require Linux and ARM64.');
    }
    final compiler = input.config.code.cCompiler?.compiler;
    if (compiler == null) throw StateError('Missing OHOS NDK compiler.');
    final bin = compiler.resolve('.');
    final linker = bin.resolve('aarch64-unknown-linux-ohos-clang').toFilePath();
    final target = input.outputDirectoryShared.resolve('ohos-arm64/cargo/');
    final process = await Process.start(
      'cargo',
      [
        'build',
        '--locked',
        '--release',
        '--lib',
        '-j',
        '4',
        '--target',
        'aarch64-unknown-linux-ohos',
        '--manifest-path',
        input.packageRoot.resolve('rust/Cargo.toml').toFilePath(),
        '--target-dir',
        target.toFilePath(),
      ],
      environment: {
        'CARGO_NET_GIT_FETCH_WITH_CLI': 'true',
        'CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER': linker,
        'CC_aarch64_unknown_linux_ohos': linker,
        'CXX_aarch64_unknown_linux_ohos': '$linker++',
        'AR_aarch64_unknown_linux_ohos': bin.resolve('llvm-ar').toFilePath(),
      },
    );
    await Future.wait([
      process.stdout.forEach(stdout.add),
      process.stderr.forEach(stderr.add),
    ]);
    if (await process.exitCode != 0) {
      throw StateError('OHOS native extensions build failed.');
    }
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'super_native_extensions',
        linkMode: DynamicLoadingBundled(),
        file: target.resolve(
          'aarch64-unknown-linux-ohos/release/libsuper_native_extensions.so',
        ),
      ),
    );
    for (final directory in ['rust/', 'ohos/cpp/code/']) {
      for (final file in Directory.fromUri(
        input.packageRoot.resolve(directory),
      ).listSync(recursive: true).whereType<File>()) {
        if (RegExp(r'\.(rs|toml|lock|cpp|h|json)$').hasMatch(file.path)) {
          output.dependencies.add(file.uri);
        }
      }
    }
  });
}
