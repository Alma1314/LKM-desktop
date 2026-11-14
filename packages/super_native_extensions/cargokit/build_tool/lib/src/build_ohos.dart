import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

import 'artifacts_provider.dart';
import 'builder.dart';
import 'environment.dart';
import 'options.dart';
import 'target.dart';
import 'util.dart';
import 'logging.dart';

final _log = Logger('build_ohos');

class BuildOhos {
  BuildOhos({required this.userOptions});

  final CargokitUserOptions userOptions;


  Future<void> buildOhos() async {
    print(Environment.rootProjectDir);
    var script = Platform.isWindows ? 'build.bat' : './build.sh';
    runCommand(
      script,
      [],
      workingDirectory: path.join(
        Environment.rootProjectDir,
        'super_native_extensions',
        'ohos',
        'cpp',
        'code',
      ),
      runInShell: Platform.isWindows,
    );
  }

  Future<void> copyOutput() async {
    final superNativeExtensionsRoot = path.join(
      Environment.rootProjectDir,
      'super_native_extensions',
    );
    final targetDirPath = path.join(
      superNativeExtensionsRoot,
      'ohos',
      'libs',
      'arm64-v8a',
    );

    final targetDir = Directory(targetDirPath);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
      _log.info('Created directory: ${targetDir.path}');
    }
    final src1 = File(path.join(
      superNativeExtensionsRoot,
      'cargokit',
      'target',
      'build_tool',
      'target',
      'aarch64-unknown-linux-ohos',
      'debug',
      'libsuper_native_extensions.so',
    ));
    final dst1 = File(path.join(targetDirPath, 'libsuper_native_extensions.so'));
    await src1.copy(dst1.path);
    final src2 = File(path.join(
      superNativeExtensionsRoot,
      'ohos',
      'cpp',
      'code',
      'build',
      'libDragDropHelper.so',
    ));
    final dst2 = File(path.join(targetDirPath, 'libDragDropHelper.so'));
    await src2.copy(dst2.path);
  }

  Future<void> build() async {
    buildOhos();
    _log.info('compile ohos cpp code successfully');
    final targets = [ Target.forFlutterName('ohos')!].toList();
    final environment = BuildEnvironment.fromEnvironment(isAndroid: false);
    final provider =
        ArtifactProvider(environment: environment, userOptions: userOptions);
    final artifacts = await provider.getArtifacts(targets);
    _log.info('compile ohos rust code successfully');
    copyOutput();
    _log.info('copy ohos output successfully');
  }
}
