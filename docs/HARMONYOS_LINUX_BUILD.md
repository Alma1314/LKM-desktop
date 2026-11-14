# OH-Flutter Linux 本机构建记录

更新日期：2026-11-14。构建宿主必须是本机 Linux x64；应用继续使用同一套 Flutter 业务代码与依赖配置。

## 版本依据

Flutter 固定为 `.flutter-version` 中的 `3.47.9-ohos-1.0.0`，源码提交 `e5f752df3e25ec897da3c98a74bcced7c21b0bd3`。该发布的鸿蒙工件沿用 3.47.5 批次，实际对应 **Dart 3.13.4**，不是当前 Flutter 根 `DEPS` 中的 Dart 3.13.7。

`engine.ohos.version` 指向旧的 3.44.9 工件批次，其 Dart 为 3.12.2，也不能作为这次宿主工具的源码版本。引擎下载覆盖地址和发布说明才说明了当前 HAR 的实际来源。

本次本地源码组合：

| 部分 | 固定版本 |
| --- | --- |
| Dart 上游 | `b530c21f7de367b94fb04787bfed9d8e989d75e8`，tag `3.13.4` |
| 完整鸿蒙移植 | `oh-flutter/fluttertpc_dart_sdk` 的 `a1d8fe1963e5e4aa280a1d82f55db83df54f8c7c`，127 个文件 |
| 独立 SDK 的 GN 修复 | 同仓库 `e8c31beb6a54c8fb9de451d318d1e39e74cf6d48`，2 个文件，其中一个与前项重合 |
| VM flag 修复 | Flutter 源码中 `engine/src/flutter/attachment/patches/dart_ohos_removed_vm_flag.patch` |

移植源的 128 个最终文件均按官方提交提供的 Git blob SHA 校验后应用。Dart 3.13.3 → 3.13.4 的 8 个上游变更文件与这组移植文件没有交集；没有覆盖 3.13.4 的版本更新。

FFI 的运行时、SDK 和前端必须保持 `ohosArm=22`、`ohosArm64=23`、`ohosX64=24`，ARM64 指针为 64 位。当前移植已经包含前端 OHOS ABI 声明，不能盲目重复应用只匹配另一种源码排版的补丁；仍需用上游 `verify_ohos_ffi_abi.dart` 检查编译后的两个 platform kernel。

## 本机安装与验证

安装目录：`/home/alma/harmonyos/command-line-tools`。下载包已通过完整 ZIP CRC 检查，SHA-256 为 `e5fda7d37eef11263588203d724d1b72380273d3c07535bb7d361a1d0e95cf34`；这里记录的是本地计算值。

| 工具 | 已安装版本 / 状态 |
| --- | --- |
| Command Line Tools | Linux x64 26.0.0.865 |
| HarmonyOS SDK / NDK | 26.0.0.105，API 26 Release |
| JDK | Temurin 21.0.12.1 |
| 内置 Node.js | 24.14.1 |
| OHPM | 26.0.0.630 |
| Hvigor | 6.26.9 |
| HDC | 3.2.0f |
| NDK Clang / CMake | 15.0.4 / 3.28.2 |
| Rust | 已添加 `aarch64-unknown-linux-ohos` 标准库和 NDK linker 配置 |
| OH-Flutter | 3.47.9-ohos-1.0.0，默认命令已启动成功 |
| 定制 Dart | Linux 本地编译的 3.13.4，已安装进 Flutter 缓存 |

Bash 启动配置已引用唯一的 [环境脚本](../buildtools/env-ohos.sh)。当前终端可执行：

```bash
source buildtools/env-ohos.sh
flutter --version
flutter doctor -v
```

环境脚本可重复加载，配置内置 Node、JDK 21、SDK、NDK、OHPM、Hvigor、HDC，以及 Rust ARM64 OHOS 的 linker / C / C++ / ar。没有另建应用依赖配置。

已验证：

- `flutter doctor -v` 的 Flutter、HarmonyOS toolchain、Linux toolchain 项通过。此结果不代表其他目标的 SDK 均已安装，也不等于真机验证。
- NDK C 和 Rust 均实际交叉编译出 ARM64 ELF 动态库。
- 默认 `dart` 可执行 `Platform.isOhos`、`Abi.ohosArm64` 探针；Linux 宿主返回 `false` 和 `ohos_arm64`，符合预期。
- 两个缓存的 Flutter platform kernel 都通过上游 FFI 检查：25 个 ABI 的 IntPtr / UintPtr / Size 宽度一致，OHOS ARM64 为索引 23、64 位。
- Dart SDK、前端 AOT snapshot 和 runtime 已换为 Linux 产物，旧标准 Dart 与 Mach-O 文件已保留为备份。
- 本地 VM 源码、Linux 生成器、官方 ARM64 release 引擎的 snapshot hash 均为 `4459fbb50b22bed94948a609d66f261e`。
- Linux → OHOS ARM64 release 生成器已生成探针 AOT ELF，记录的目标特征为 `arm64 ohos compressed-pointers`，已安装到 Flutter 的 release 缓存。profile 生成器也已完成编译并安装；两者均通过实际 HAP 构建验证。旧的 Dart 3.12.2 生成器已保留为备份。

### 最小原生 Flutter HAP

当时的验证工程：`/tmp/lkm-linux-ohos/smoke`，由当前 SDK 的 `flutter create --platforms=ohos` 生成，保持 Flutter 原生界面。

```bash
flutter build hap --debug --no-codesign --target-platform ohos-arm64
```

debug、profile、release 三种模式均已在 Linux 本机成功编译，HAP 的完整 ZIP CRC 检查通过。debug 包含 Flutter kernel 与 ARM64 引擎，profile / release 包含 ARM64 AOT `libapp.so`。未使用 `--no-tree-shake-icons`。

产物已持久保存在 `/home/alma/harmonyos/validation/`：

| 文件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| `lkm-ohos-smoke-debug-unsigned.hap` | 102466502 | `f675cd6c342e42a80c105b2dddc559c3666b7f4fe38deb4c776d57565c28e1a4` |
| `lkm-ohos-smoke-profile-unsigned.hap` | 27214402 | `1e7b8b0eb98bcfd0258ac345c57a53093af525fe74b5b50044ce8fee8c0ab890` |
| `lkm-ohos-smoke-release-unsigned.hap` | 21279691 | `c3908d2a6ca3aeef87cf540be0197c598f9cfb47f0acb3fd9e321be3c81de922` |

profile / release 使用对应的 `--profile` / `--release` 参数。签名已关闭，不需要为工具链检查登录 AGC；这些包尚未签名或安装到设备。

release 检查发现原缓存的 `const_finder` 使用另一 Dart SDK hash，已用同一套 Dart / Kernel 源码重建，图标裁剪默认开启的 release 构建随后成功。日志为 `/tmp/lkm-linux-ohos/build-smoke-{hap,profile,release}.log`。

业务应用未据此宣称迁移完成：此前的 `flutter pub get` 超时，详细日志显示 WebF 等官方 Git clone 返回 HTTP 418。现已应用下述传输修复，业务项目 `flutter pub get` 成功并更新唯一锁文件；应用侧集中静态检查、OHOS UI 回归和业务 OHOS Dart 编译已通过；此前全量测试结果为 868 通过、22 失败、3 跳过。随后首个业务 debug HAP 已在 Linux 本机构建成功；当前继续补齐插件和运行时原生库，尚未真机验证。

### Linux 测试引擎配套

业务 UI 修复后，`flutter test` 暴露出 `Invalid SDK hash`：当前标准 Linux `flutter_tester` 是 Dart 3.13.7，而本机定制 SDK / platform kernel 与 OHOS 目标仍为 3.13.4。已将 Linux `flutter_tester` 和 ICU 数据换为官方 Flutter 3.47.5 的 Linux x64 工件，匹配 Dart 3.13.4；随后 OHOS UI 集中回归已实际运行通过。

- 官方 [3.47.5 引擎 revision](https://raw.githubusercontent.com/flutter/flutter/3.47.5/bin/internal/engine.version)：`af7e796e161ae0bb1ff0758c71a7105418bd9ded`。
- 官方 [Linux x64 工件 ZIP](https://storage.googleapis.com/flutter_infra_release/flutter/af7e796e161ae0bb1ff0758c71a7105418bd9ded/linux-x64/artifacts.zip)：完整 CRC 通过，本地 SHA-256 `b2e6e1e6b95866297b77580d04dbebcd45863585ad9f484108101c7c2f427a4a`。
- 原文件在 `bin/cache/artifacts/engine/linux-x64/` 下以 `.dart-3.13.7-backup` 后缀保留；其他宿主目标的构建尚未据此验证。
- 如果清除 Flutter SDK 缓存或强制重新 precache，需要重新校准这些配套文件；不要只替换 Dart 后沿用不同版本的测试引擎。

### 业务应用验证

业务应用使用仓库中的 `ohos/` 原生宿主，来自固定 SDK 模板。它通过 FlutterAbility / FlutterPage 加载现有 Flutter 引擎与 `lib/main.dart`，不是 WebView 应用；没有另一份业务实现。bundleName 为 `ltd.lkmahz.desktop`，兼容/目标 API 为 26。

```bash
source buildtools/env-ohos.sh
flutter pub get
# 本机 Lean 的 clang 位于 PATH 前部；测试时优先使用完整的系统 Clang。
PATH="/usr/bin:$PATH" "$HOME/flutter/bin/flutter" test --no-pub
flutter analyze --no-pub
PATH="/usr/bin:$PATH" "$HOME/flutter/bin/flutter" build hap \
  --debug --no-pub --no-codesign --target-platform ohos-arm64
```

此前实际结果：Pub 解析成功，初始 37 个 override 与锁文件的 Git SHA 逐项一致；应用静态检查修复了图片预览遗漏 OHOS 的平台分支，余下 7 个 warning / 58 个 info，0 个 error。本次应用改动的集中静态检查与 OHOS UI 测试均已通过；该阶段全量测试结果为 868 通过、22 失败、3 跳过。原生资产修复后已有成功的业务 debug HAP，见下文。

业务应用 OHOS Dart 编译已单独通过（不包含原生资产和 HAP 打包）：

```bash
flutter assemble --no-version-check \
  --output /tmp/lkm-linux-ohos/app-kernel-validated \
  -dTargetFile=lib/main.dart -dTargetPlatform=ohos \
  -dBuildMode=debug -dOhosArchs=arm64-v8a kernel_snapshot_program
```

本次输出为 `.dart_tool/flutter_build/b8d37cb656102bf157dd2f4a27bd5d88/app.dill`，259660064 字节；日志为 `/tmp/lkm-linux-ohos/app-ohos-kernel.log`，命令退出码 0。随后的原生资产修复和 HAP 进度见下文。

### 最新应用检查结果

- `flutter analyze --no-pub`：0 error、7 warning、59 info，退出码 1；集中检查本轮适配与新增测试为 0 issue。
- 新增图片选择/分享的 2 项回归通过；原有时区、常亮、评价、音频、文件选择、菜单及 OHOS UI 回归包含于本轮全量测试且通过。真实 ArkTS 后端逻辑检查通过，原生库和 NDK 探针记录见下文。
- `flutter test --no-pub --reporter expanded`：877 通过、21 失败、3 跳过，退出码 1。新增 2 项回归通过；逐项比较第四阶段日志，失败清单完全一致，没有新增失败（下列 8 个文件）。尚未用替换前工具链做基线对照。
- 失败涉及主题/消息截图、链接解析、页面断言、聊天布局/状态与音频探测超时；日志也有远程字体获取失败。没有将全量测试标为成功。

| 测试文件 | 失败用例数 |
| --- | ---: |
| `test/chat/message_avatar_alignment_test.dart` | 4 |
| `test/chat/message_bubble_shape_test.dart` | 1 |
| `test/chat/message_post_link_test.dart` | 1 |
| `test/drive/s3_direct_upload_test.dart` | 1 |
| `test/misc/settings_explore_category_test.dart` | 1 |
| `test/posts/post_link_embed_test.dart` | 9 |
| `test/shared/widgets/markdown_selection_test.dart` | 1 |
| `test/theme_preview_test.dart` | 3 |

完整日志与机器可读结果持久保存在 `/home/alma/harmonyos/validation/`，本轮文件名以 `lkm-desktop-phase5-` 开头；先前验证记录仍保留。

### 业务原生资产与 HAP

SDK 原先将 `OhosAssetTarget` 的 hook OS 映射成 `linux`，导致 OHOS ARM64 构建错误选择 GTK 或 Linux 预编译库。已提供 [SDK 补丁](../buildtools/patches/flutter-ohos-native-assets.patch) 和可重复运行的 [安装脚本](../buildtools/patch-ohos-sdk.sh)，保留真实 `OS.ohos`。`setup-dev.sh` 会应用该补丁并触发 Flutter tool 重新编译；本机 SDK 因而有这一项受记录的源码修改。

```bash
bash buildtools/patch-ohos-sdk.sh "$HOME/flutter"
source buildtools/env-ohos.sh
PATH="/usr/bin:$PATH" dart run buildtools/verify-ohos-native-assets.dart
```

应用统一使用同版本本地 `code_assets 2.2.0`、`native_toolchain_c 0.19.6`，补齐 OHOS ABI、NDK target/sysroot 和链接规则。上述探针实际生成 ARM64 C++ 动态库，检查 ELF 及依赖，并拒绝错误架构。

- `cnativeapi 0.5.10` 只服务于桌面托盘；OHOS hook 不构建桌面库，托盘入口使用 Windows/macOS/Linux 白名单。
- `sqlite3 3.9.0` 使用官方 SQLite 3.54.0 amalgamation，在 OHOS 从源码构建；其他平台仍走原默认路径。源码及校验记录位于 `buildtools/native/sqlite3/`。
- `openmls 3.3.0` 保持现有 Dart/FRB API，在 OHOS 用包内锁定 Rust 源码和 NDK 编译 ARM64 库。实际产物仅依赖 OHOS `libc.so`。
- `super_native_extensions 0.9.1` 上游鸿蒙 CMake 没有生成 ArkTS/Dart 所加载的库。现已补接锁定 Rust 源码及 C++ 拖放辅助代码构建；菜单复用既有 Flutter renderer。N-API 与 FFI 导出已检查，设备上的加载、拖放仍待验证。

首个业务 debug HAP 已在 Linux 构建成功：`build/ohos/hap/entry-default-unsigned.hap`，390819539 字节，SHA-256 `f9f6023cfd65a34c901125ac5f962277b9590ae01f3b4ef7a88ab69c5e4c5a5e`。持久备份为 `/home/alma/harmonyos/validation/lkm-desktop-initial-debug-unsigned.hap`；ZIP CRC 检查通过，7 个动态库均为 ARM64，包括 WebF、QuickJS、SQLite、OpenMLS。该初始包尚未包含后续音频/网络/文件选择适配及菜单 Rust 库，不能据此认定所有插件可运行。

随后包含音频、网络状态、文件选择和菜单原生库的业务 debug HAP 再次构建成功，392173764 字节，SHA-256 `f6e82a8eb98bc5ef73a1e27ef86c4fd48e1c884338eef7e4191125360ba8d691`。持久产物为 `/home/alma/harmonyos/validation/lkm-desktop-debug-unsigned.hap`。8 个动态库均为 ARM64，CRC、DT_NEEDED 依赖存在性及菜单 N-API / FFI 导出检查通过；生成的 Dart registrant 包含 `FilePickerOhos.registerWith()`，ArkTS registrant 包含音频、网络和文件选择插件。

```bash
source buildtools/env-ohos.sh
python3 buildtools/verify-ohos-hap.py build/ohos/hap/entry-default-unsigned.hap
```

检查脚本验证当前业务需要的 8 个库，拒绝 GNU/Linux 依赖和错误 ELF 架构；输出 JSON 的 SHA-256 与库依赖用于复查。这项检查不证明未适配插件已能运行。HDC 设备查询返回 `[Empty]`。

业务 **release HAP** 也已在 Linux 本机构建成功，使用默认图标裁剪与 ARM64 AOT，96143173 字节（96.1 MB），SHA-256 `925163221ced34997c6d379b80fc3d334f0bcb1d0a6d608f11caae3ddef30376`。持久产物为 `/home/alma/harmonyos/validation/lkm-desktop-release-unsigned.hap`。9 个动态库包含 AOT `libapp.so` 和上述 8 个运行库，CRC、架构、动态依赖及 N-API / FFI 导出检查通过。

```bash
PATH="/usr/bin:$PATH" flutter build hap \
  --release --no-pub --no-codesign --target-platform ohos-arm64
python3 buildtools/verify-ohos-hap.py --require-aot
```

RTC、播放器、Firebase 等功能缺口仍见 [插件替换进度](HARMONYOS_PLUGIN_REPLACEMENTS.md)。所有业务构建均未签名，尚未在设备运行。

### 第四阶段插件接入

在保持 `flutter_timezone 5.1.1`、`wakelock_plus 1.8.0`、`in_app_review 2.0.12` 现有 API / 非鸿蒙实现的基础上，统一加入已有 OHOS 后端，没有降级 Pigeon / 平台接口或额外引入旧 URL launcher。三个插件均由正式的 OHOS 注册器注册，非 dev-only；评价同时接入既有共享提示策略。

- 时区：系统 IANA ID 继续由当前 API 转成 `TimezoneInfo.identifier`；可选本地化名称在 OHOS 上为空。调用失败回传异常，不让 Dart 挂起。
- 常亮：原生 codec 与当前 Pigeon 28 的类型码 129/130 和消息封装一致；等待窗口操作完成才返回，读取实际窗口状态；无 Ability / SDK 失败不假报成功。只控制屏幕常亮，不提供后台执行保证。
- 评价：API 20+ 的 AppGalleryKit，打开当前应用 bundle 的商店页；原有 Android/iOS/macOS/Windows 实现和公开方法签名不变。账号、上架配置和配额仍是运行条件，实际评论服务需要真机。

```bash
node buildtools/verify-ohos-timezone-wakelock.mjs
node buildtools/verify-ohos-review.mjs
PATH="/usr/bin:$PATH" flutter test --no-pub \
  test/core/ohos_timezone_wakelock_test.dart test/core/ohos_review_test.dart
```

原生逻辑检查与新增 3 项 Dart 回归通过；集中静态检查为 0 issue。来源提交、归档哈希和移植边界记录于各包 `UPSTREAM.md`。本轮记录以 `/home/alma/harmonyos/validation/lkm-desktop-phase4-` 为前缀。最终 release HAP 已通过 CRC、ARM64 动态依赖、N-API/FFI 导出和 AOT 检查；额外核对了 AOT 中的最新共享评价处理和 ArkTS 中的三个新增插件。固定备份为 `lkm-desktop-phase4-release-unsigned.hap`，第三阶段 release 保留为 `lkm-desktop-phase3-release-unsigned.hap`。debug 仍是第三阶段产物，本轮以 release 验证新增插件。

### 第五阶段插件接入

`image_picker 1.2.4` / `share_plus 13.3.1` 的 Dart API 与原平台保持当前发布版，统一使用本地 OHOS 后端。图片选择复用当前 interface 2.11.2 的 MethodChannel，原生返回可读的私有缓存路径；系统相机输出复制后清理。图库取消返回 null/空列表、重复请求报 already_active，多视频完整返回。缩放使用同一个比例，同时修正 JPEG 路径、部分写入和 FD 生命周期。

分享保留 interface 7.2.0，修正旧后端与当前统一 share map 不匹配的问题。文本、URI、文件和旧 Share API 都经过原有 Dart 入口；文件复制完成后打开系统面板。关闭事件仅返回 unavailable，不伪造分享成功。无 Ability、拷贝/显示错误和并发请求均显式回复；不删除其他接收应用可能仍在读取的缓存。

```bash
node buildtools/verify-ohos-image-picker-share.mjs
PATH="/usr/bin:$PATH" flutter test --no-pub test/core/ohos_image_picker_share_test.dart
```

上述原生逻辑与新增 2 项 Dart 回归通过，插件已进入正式原生注册器，均非 dev-only。首次真实 Linux release 构建成功，CRC、ARM64 AOT / 原生依赖和编译后的两个插件及通道名称检查通过。附加许可证按 Flutter manifest 声明进入产物。最终 release HAP 为 96143173 字节，固定保存为 `/home/alma/harmonyos/validation/lkm-desktop-phase5-release-unsigned.hap`，SHA-256 `925163221ced34997c6d379b80fc3d334f0bcb1d0a6d608f11caae3ddef30376`。最终包重新通过 CRC / ARM64 / AOT / 原生依赖检查，额外解压并逐文件核对 9 份附加许可证均已进入 NOTICES。旧版产物保持各自阶段备份。本轮日志及报告以 `lkm-desktop-phase5-` 为前缀；debug 仍是第三阶段产物。后续仍需真机相机、URI 授权和跨应用分享验收。

### 本地构建依赖和修复

源码构建时的现场：`/tmp/lkm-linux-ohos/dart-build/sdk`。Clang 固定为官方 CIPD 的 `deb6854eec93529b2bd30178d400ad2ee7665cd4`；DevTools 固定为 `12d595649f189f1896722623f72599077f476848`。源码构建依赖的 196 个包已解析。

### GitCode HTTP 418 修复

本机实测普通 Git User-Agent 返回 418，单独改用 `Mozilla/5.0` 后，`ls-remote` 与实际镜像克隆均成功；无需修改协议版本。已持久设置：

```bash
git config --global http.https://gitcode.com/.userAgent Mozilla/5.0
git config --global http.https://atomgit.com/.userAgent Mozilla/5.0
```

设置只匹配这两个官方域名。原 Git 配置保存在 `/home/alma/.gitconfig.lkm-before-gitcode-user-agent`。这是一项经本机验证的客户端兼容配置，不保证服务端策略以后保持不变。

修复后 SDK 已恢复原始 Git 依赖并完成 `pub get`，默认 `flutter --version` 正常。先前的 SDK 本地 override 已撤销，备份为 `/home/alma/harmonyos/validation/flutter-tools-pubspec-overrides-418-backup.yaml`；受校验的旧本地依赖作为回退保留，不再是 SDK 当前依赖来源。主项目的依赖地址、固定提交和统一 `pubspec.yaml` 保持原样，实际 `flutter pub get` 已成功。

### WebF 大仓库断流

418 修复后，WebF 全量镜像克隆仍遇到 `curl 18` / `early EOF`。本机按 `pubspec.yaml` 中的固定提交 `ccdf8a05222a408938e51e2b58413355ff2aab7d` 做真实 Git 浅获取，约 7.8 MB，`git fsck --full --strict` 通过后放入 Pub 的标准 bare 缓存。没有改依赖 URL、提交或手工编造锁文件。

可在该缓存缺失或无效时重新准备（有效缓存无需重复执行；先移开失效目录保留备份）：

```bash
webf_url=https://gitcode.com/CPF-Flutter/fluttertpc_webf.git
webf_commit=ccdf8a05222a408938e51e2b58413355ff2aab7d
webf_cache="$HOME/.pub-cache/git/cache/fluttertpc_webf-d20964bca5b6fee17fe1e9363e818d5199752aa3"
git init --bare "$webf_cache"
git -C "$webf_cache" remote add origin "$webf_url"
git -C "$webf_cache" -c http.version=HTTP/1.1 fetch --depth=1 origin "$webf_commit"
git -C "$webf_cache" update-ref refs/heads/lkm-pinned "$webf_commit"
git -C "$webf_cache" symbolic-ref HEAD refs/heads/lkm-pinned
git -C "$webf_cache" config remote.origin.fetch "+$webf_commit:refs/heads/lkm-pinned"
git -C "$webf_cache" fsck --full --strict
flutter pub get
```

该缓存只获取这个固定提交；以后升级 WebF 的 pin 时，应同步更改缓存 fetch refspec 并获取新提交，或移开此缓存让 Pub 重新克隆。其他依赖使用正常的 Git 缓存。

[GitCode 官方状态码说明](https://docs.gitcode.com/docs/apis/)将 418 归为请求被拒绝、疑似不安全。该说明没有公开本次请求具体触发了哪条规则；上述根因定位来自本机对照测试。


使用本机系统头文件和 glibc：

- [sysroot 修复](../buildtools/patches/dart-linux-no-sysroot.patch) 使未启用 CIPD sysroot 时不再读取其元数据，不伪造版本文件。
- [快照目标修复](../buildtools/patches/dart-linux-ohos-snapshot.patch) 允许 Linux 宿主生成 OHOS 目标快照，保持同一份 Dart 源码。

宿主 SDK 使用 `create_most_sdk` 构建，未构建额外的 sanitizer runtime 和 `wasm-opt` 优化器：

```bash
python3 tools/gn.py --mode release --arch x64 --no-rbe \
  --gn-args='dart_sysroot="" dart_include_wasm_opt=false'
ninja -C out/ReleaseX64 -j4 create_most_sdk
```

引导阶段使用标准 Dart 3.13.7 运行构建脚本和 Pub，实际安装产物来自固定的 Dart 3.13.4 加完整鸿蒙移植。使用本机 glibc 构建，不代表二进制已验证可分发到其他 Linux 发行版。`/tmp` 清理会丢失源码构建现场，已安装的工具不依赖该目录运行。

## 完成条件

1. `file` 确认宿主 `dart`、`dartaotruntime`、`gen_snapshot` 为可执行的 Linux x86-64 ELF；实际运行平台接口探针。
2. 检查编译后 platform kernel 的 FFI 映射，检查 AOT 生成器与目标引擎的 VM snapshot hash、架构、运行模式和指针压缩配置；不配套时重建目标引擎。
3. 配置官方 Linux API 26 SDK，在本机生成并编译最小 Flutter HAP，再处理应用插件和原生资产的实际构建错误。
4. 成功运行本项目 `flutter pub get`、`flutter analyze`、`flutter test` 及 HAP 构建，记录产物路径；签名和真机测试另按实际设备条件记录，不能与编译成功混同。

## 官方来源

- [3.47.9 发布清单](https://api.gitcode.com/api/v5/repos/oh-flutter/flutter_flutter/releases/tags/3.47.9-ohos-1.0.0)
- [3.47.5 重建工件的版本依据](https://atomgit.com/oh-flutter/flutter_flutter/blob/3.47.9-ohos-1.0.0/release-notes/Flutter%203.47.5-ohos%201.0.0%20ReleaseNote.md)
- [鸿蒙 Dart 移植源码](https://gitcode.com/oh-flutter/fluttertpc_dart_sdk/tree/flutter_3.47.4_deps)
- [华为 Linux 命令行构建指导](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-command-line-building-app/)
