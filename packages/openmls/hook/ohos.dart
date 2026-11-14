import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

/// Build the same locked Rust sources against the OHOS NDK, on Linux.
Future<Uri> buildOhosLibrary(
  BuildInput input,
  BuildOutputBuilder output,
) async {
  if (!Platform.isLinux ||
      input.config.code.targetArchitecture != Architecture.arm64) {
    throw StateError(
      'OpenMLS OHOS currently requires a Linux host and ARM64 target.',
    );
  }
  final compiler = input.config.code.cCompiler?.compiler;
  if (compiler == null)
    throw StateError('OpenMLS OHOS requires the NDK compiler.');
  final llvmBin = compiler.resolve('.');
  final linker = llvmBin
      .resolve('aarch64-unknown-linux-ohos-clang')
      .toFilePath();
  final archiver = llvmBin.resolve('llvm-ar').toFilePath();
  if (!File(linker).existsSync())
    throw StateError('Missing OHOS linker: $linker');

  final rustRoot = input.packageRoot.resolve('rust/');
  final targetDir = input.outputDirectoryShared.resolve('ohos-arm64/cargo/');
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
      rustRoot.resolve('Cargo.toml').toFilePath(),
      '--target-dir',
      targetDir.toFilePath(),
    ],
    environment: {
      'CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER': linker,
      'CC_aarch64_unknown_linux_ohos': linker,
      'CXX_aarch64_unknown_linux_ohos': '$linker++',
      'AR_aarch64_unknown_linux_ohos': archiver,
    },
  );
  await Future.wait([
    process.stdout.forEach(stdout.add),
    process.stderr.forEach(stderr.add),
  ]);
  if (await process.exitCode != 0)
    throw StateError('OpenMLS OHOS source build failed.');

  final library = targetDir.resolve(
    'aarch64-unknown-linux-ohos/release/libopenmls_frb.so',
  );
  if (!File.fromUri(library).existsSync())
    throw StateError('Missing built library: $library');
  for (final file in Directory.fromUri(
    rustRoot,
  ).listSync(recursive: true).whereType<File>()) {
    if (file.path.endsWith('.rs') ||
        file.path.endsWith('Cargo.toml') ||
        file.path.endsWith('Cargo.lock')) {
      output.dependencies.add(file.uri);
    }
  }
  return library;
}
