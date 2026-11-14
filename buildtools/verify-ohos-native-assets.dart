import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

Future<void> main() async {
  final ndk = Platform.environment['OHOS_NDK_HOME'];
  if (ndk == null) throw StateError('Source buildtools/env-ohos.sh first.');
  if (Architecture.fromAbi(ffi.Abi.ohosArm64) != Architecture.arm64 ||
      OS.fromString('ohos') != OS.ohos ||
      OS.ohos.dylibFileName('probe') != 'libprobe.so') {
    throw StateError('OHOS asset protocol or ABI mapping is incorrect.');
  }

  final work = Directory.systemTemp.createTempSync('lkm-ohos-native-');
  try {
    final source = File('${work.path}/probe.cpp')
      ..writeAsStringSync('''
#include <string>
extern "C" int lkm_probe() { return std::string("OHOS").size(); }
''');
    final llvm = Directory('$ndk/llvm/bin').uri;
    await testCodeBuildHook(
      targetOS: OS.ohos,
      targetArchitecture: Architecture.arm64,
      cCompiler: CCompilerConfig(
        compiler: llvm.resolve('clang'),
        linker: llvm.resolve('ld.lld'),
        archiver: llvm.resolve('llvm-ar'),
      ),
      mainMethod: (args) => build(args, (input, output) async {
        await CBuilder.library(
          name: 'probe',
          assetName: 'probe',
          sources: [source.path],
          language: Language.cpp,
          std: 'c++17',
          flags: ['-Wl,--no-undefined'],
        ).run(input: input, output: output);
      }),
      check: (input, output) async {
        final library = output.assets.code.single.file!;
        final header = File.fromUri(library).readAsBytesSync();
        if (ByteData.sublistView(header).getUint16(18, Endian.little) != 183) {
          throw StateError('Expected an ARM64 ELF library.');
        }
        final dynamicSection = await Process.run('readelf', [
          '-d',
          library.toFilePath(),
        ]);
        if (dynamicSection.exitCode != 0 ||
            RegExp(
              r'libc\.so\.6|libstdc\+\+|libc\+\+_shared',
            ).hasMatch('${dynamicSection.stdout}')) {
          throw StateError(
            'Unexpected OHOS dependencies: ${dynamicSection.stdout} ${dynamicSection.stderr}',
          );
        }
        final wrongJson =
            jsonDecode(jsonEncode(input.json)) as Map<String, dynamic>;
        wrongJson['config']['extensions']['code_assets']['target_architecture'] =
            'x64';
        final validator = CodeAssetExtension(
          targetOS: OS.ohos,
          targetArchitecture: Architecture.x64,
          linkModePreference: LinkModePreference.dynamic,
        )..setupLogger(Logger.detached('probe'));
        final rejected = await validator.validateBuildOutput(
          BuildInput(wrongJson),
          output,
        );
        if (!rejected.any((e) => e.contains('target architecture is x64'))) {
          throw StateError(
            'OHOS validator accepted a library for the wrong architecture: $rejected',
          );
        }
        final saved = File('build/ohos-native-probe/libprobe.so');
        saved.parent.createSync(recursive: true);
        File.fromUri(library).copySync(saved.path);
        stdout.writeln(
          'OHOS ARM64 C++ build, static C++ runtime, ABI mapping and wrong-architecture rejection passed.',
        );
      },
    );
  } finally {
    work.deleteSync(recursive: true);
  }
}
