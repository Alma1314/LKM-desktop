# 跨平台插件替换进度

更新日期：2026-11-14。要求：同一套业务代码、同一份 `pubspec.yaml`、同一套跨平台插件实现；不建立鸿蒙专用依赖配置或应用副本。

## 已修改的配置

在根 `pubspec.yaml` 的 `dependency_overrides` 中统一选择 **25 个主适配包和 12 个配套实现/接口包**。这些覆盖对直接依赖和 vendored 包中的传递依赖同时生效，避免同一插件被不同调用方选到不同来源。原有 `hooks`、`flat_buffers` 和本地 `protocol_handler_windows` 修复保留。另为现有 Material/Cupertino、PIN、富文本库统一选择同版本的本地兼容源，见下文。

所有新增 Git 来源固定到 40 位 commit，而不是浮动的 `main`/开发分支。已逐项对照源 pubspec，确认主适配包保留了原包声明的 Android、iOS、桌面、Web 平台；这只是配置和声明核对，尚不能代替构建、运行测试。

实际 `flutter pub get` 已成功，37 个适配包及配套包均由 Pub 写入唯一的 `pubspec.lock`，`.dart_tool` 已更新为新来源。HTTP 418 和 WebF 大仓库断流的处理见 [Linux 构建记录](HARMONYOS_LINUX_BUILD.md)。依赖解析成功不代表运行功能全部兼容，analyze/test 与业务 HAP 仍需分别验证。

## 主适配包

| 包 | 适配源版本 | 固定提交 |
| --- | --- | --- |
| `device_info_plus` | 13.3.0 | [52879a0f52fe](https://gitcode.com/oh-flutter/device_info_plus/commit/52879a0f52fea60c4d14823c4140ae065982678e) |
| `disk_space_2` | 1.0.13 | [eec45e7de908](https://gitcode.com/oh-flutter/disk_space_2/commit/eec45e7de9082cac3216b379ebf0b16d3f8a7080) |
| `file_saver` | 0.7.0 | [ebe542b8ab47](https://gitcode.com/oh-flutter/file_saver/commit/ebe542b8ab4703ebd72fd23c3e61e5252b978a2a) |
| `flutter_callkit_incoming` | 3.1.6 | [f4a86b447c4d](https://gitcode.com/oh-flutter/flutter_callkit_incoming/commit/f4a86b447c4dc222feb592e80050d7e0a4191c4d) |
| `flutter_inappwebview` | 6.1.5 | [389cf40dbb64](https://gitcode.com/CPF-Flutter/flutter_inappwebview/commit/389cf40dbb647f1df7272de5ea6b3401efe27a75) |
| `flutter_secure_storage` | 11.2.0 | [d3667ff4f3c8](https://gitcode.com/oh-flutter/flutter_secure_storage/commit/d3667ff4f3c8f259093a20dee88b50fff247626d) |
| `flutter_sharing_intent` | 2.0.4 | [6a07f1fa55f4](https://gitcode.com/oh-flutter/flutter_sharing_intent/commit/6a07f1fa55f4e87133f8c04b75868a40f9273724) |
| `gal` | 2.3.3 | [e9258df9e420](https://gitcode.com/oh-flutter/gal/commit/e9258df9e420b2876657ffb60a49357698b445ad) |
| `geolocator` | 14.1.2 | [5e2b849051a8](https://gitcode.com/oh-flutter/geolocator/commit/5e2b849051a877cb3b5174ee2e38da1ac33a0ef7) |
| `local_auth` | 3.0.2 | [a97947befc0a](https://gitcode.com/oh-flutter/local_auth/commit/a97947befc0a58882d342770152548beabbad76a) |
| `native_exif` | 0.8.0 | [f146d0ac4540](https://gitcode.com/CPF-Flutter/fluttertpc_native_exif/commit/f146d0ac4540f4a02ac264a5abc16d5d46706dd8) |
| `open_file` | 4.0.0 | [7095c2a7a865](https://gitcode.com/CPF-Flutter/fluttertpc_open_file/commit/7095c2a7a8650af5c83e057b42272ef0ef71b200) |
| `package_info_plus` | 10.2.2 | [db214283719c](https://gitcode.com/oh-flutter/package_info_plus/commit/db214283719caf7805b6d7a2e6df8b75e8fc8830) |
| `pasteboard` | 0.6.0 | [57575ecc0911](https://gitcode.com/oh-flutter/pasteboard/commit/57575ecc0911d3dc9f5c7c13f2adc3976da39ea9) |
| `path_provider` | 2.1.6-ohos.2 | [d591cd20ddeb](https://gitcode.com/oh-flutter/path_provider/commit/d591cd20ddebc226c7f498792a98d461fba2898d) |
| `permission_handler` | 13.0.2-ohos.1 | [807158357a93](https://gitcode.com/oh-flutter/permission_handler/commit/807158357a9343ec7c89e544b334ca518cc59486) |
| `shared_preferences` | 2.5.6-ohos.1 | [3269f9c73462](https://gitcode.com/oh-flutter/shared_preferences/commit/3269f9c73462509d31362b4154cbedb8f5e49503) |
| `sqflite` | 2.4.5 | [e2de4314e91b](https://gitcode.com/oh-flutter/sqflite/commit/e2de4314e91bdab028feda71274ad30d9b072d00) |
| `url_launcher` | 6.3.3 | [a1ec14ffbcc9](https://gitcode.com/oh-flutter/url_launcher/commit/a1ec14ffbcc91d082880418c010a37cb6cf47c57) |
| `video_thumbnail` | 0.5.6 | [9c77dc064391](https://gitcode.com/CPF-Flutter/fluttertpc_video_thumbnail/commit/9c77dc064391320fd5911bacda29fa1fcbfba2d9) |
| `irondash_engine_context` | 0.5.5 | [838edcfaf008](https://gitcode.com/CPF-Flutter/fluttertpc_irondash/commit/838edcfaf008b2d9e19b2ad55d14a4ad96252acc) |
| `irondash_message_channel` | 0.7.0 | [838edcfaf008](https://gitcode.com/CPF-Flutter/fluttertpc_irondash/commit/838edcfaf008b2d9e19b2ad55d14a4ad96252acc) |
| `super_context_menu` | 0.9.1 | [6f3d0caa84cb](https://gitcode.com/CPF-Flutter/fluttertpc_super_native_extensions/commit/6f3d0caa84cb26e0d8c39d2868af1998ee80cc99) |
| `super_native_extensions` | 0.9.1 | [6f3d0caa84cb](https://gitcode.com/CPF-Flutter/fluttertpc_super_native_extensions/commit/6f3d0caa84cb26e0d8c39d2868af1998ee80cc99) |
| `webf` | 0.24.27 | [ccdf8a05222a](https://gitcode.com/CPF-Flutter/fluttertpc_webf/commit/ccdf8a05222a408938e51e2b58413355ff2aab7d) |

## 配套实现与接口

| 包 | 适配源版本 | 固定提交 |
| --- | --- | --- |
| `flutter_inappwebview_android` | 1.1.3 | [389cf40dbb64](https://gitcode.com/CPF-Flutter/flutter_inappwebview/commit/389cf40dbb647f1df7272de5ea6b3401efe27a75) |
| `flutter_inappwebview_internal_annotations` | 1.1.1 | [389cf40dbb64](https://gitcode.com/CPF-Flutter/flutter_inappwebview/commit/389cf40dbb647f1df7272de5ea6b3401efe27a75) |
| `flutter_inappwebview_ios` | 1.1.2 | [389cf40dbb64](https://gitcode.com/CPF-Flutter/flutter_inappwebview/commit/389cf40dbb647f1df7272de5ea6b3401efe27a75) |
| `flutter_inappwebview_macos` | 1.1.2 | [389cf40dbb64](https://gitcode.com/CPF-Flutter/flutter_inappwebview/commit/389cf40dbb647f1df7272de5ea6b3401efe27a75) |
| `flutter_inappwebview_ohos` | 1.1.3 | [389cf40dbb64](https://gitcode.com/CPF-Flutter/flutter_inappwebview/commit/389cf40dbb647f1df7272de5ea6b3401efe27a75) |
| `flutter_inappwebview_platform_interface` | 1.3.0+1 | [389cf40dbb64](https://gitcode.com/CPF-Flutter/flutter_inappwebview/commit/389cf40dbb647f1df7272de5ea6b3401efe27a75) |
| `flutter_inappwebview_web` | 1.1.2 | [389cf40dbb64](https://gitcode.com/CPF-Flutter/flutter_inappwebview/commit/389cf40dbb647f1df7272de5ea6b3401efe27a75) |
| `flutter_inappwebview_windows` | 0.6.0 | [389cf40dbb64](https://gitcode.com/CPF-Flutter/flutter_inappwebview/commit/389cf40dbb647f1df7272de5ea6b3401efe27a75) |
| `flutter_secure_storage_ohos` | 1.2.2 | [d3667ff4f3c8](https://gitcode.com/oh-flutter/flutter_secure_storage/commit/d3667ff4f3c8f259093a20dee88b50fff247626d) |
| `open_file_ohos` | 1.1.0 | [7095c2a7a865](https://gitcode.com/CPF-Flutter/fluttertpc_open_file/commit/7095c2a7a8650af5c83e057b42272ef0ef71b200) |
| `package_info_plus_platform_interface` | 4.1.0 | [db214283719c](https://gitcode.com/oh-flutter/package_info_plus/commit/db214283719caf7805b6d7a2e6df8b75e8fc8830) |
| `sqflite_ohos` | 2.4.5 | [e2de4314e91b](https://gitcode.com/oh-flutter/sqflite/commit/e2de4314e91bdab028feda71274ad30d9b072d00) |

WebView 的主包、接口、所有原平台实现、OHOS 实现及 internal annotations 使用同一仓库和同一提交；安全存储、包信息、文件打开和 sqflite 的同仓库实现也统一固定。这些覆盖用于明确选择 fork 中相邻 `path` 依赖的来源；实际 Pub 解析已成功，配套来源已进入锁文件。

WebView 的 `internal_annotations` 配套包在该 fork 中标为 1.1.1，原锁文件为 1.3.0。本次按 fork 的整套源码选择配套版本，尚未完成其接口兼容验证；主适配包的基础版本一致不代表所有传递依赖都没有版本变化。

`shared_preferences`、`path_provider`、`permission_handler` 是同基础版本的 `-ohos` 预发布 fork，通过统一 override 明确选用；原来的依赖约束保留作 API 基线。本次没有通过降级 RTC、录音或加密依赖来掩盖接口差异。

## SDK 与统一实现

本次使用 OH-Flutter 验证鸿蒙目标。`Platform.isOhos` 和 `TargetPlatform.ohos` 属于该适配工具链中的平台接口，不能因为标准 Flutter 不识别就判定适配版不能用于 OH-Flutter。因此 WebF 0.24.27 和同版菜单/Irondash 适配源已纳入这一份统一配置。

这不表示其他目标已经验证通过：目前 WebF 与原生菜单适配源的上述调用在标准 Dart/Flutter SDK 下仍会产生编译错误，需要在同一依赖实现中统一处理平台检测，或使用经验证支持相应目标的工具链。尚未验证 OH-Flutter 对本项目所有非鸿蒙目标的构建结果，不声称任意 SDK 可无修改编译这些源。

## 纯 Flutter UI 的平台分支

真实业务 HAP 与测试编译暴露出 93 处 `TargetPlatform.ohos` 穷尽分支错误；这些纯 UI 包不能仅凭“不含原生插件”认定兼容。已对下列版本保留原 API，OHOS 采用既有 Android UI 行为：

| 包 | 唯一实现来源 |
| --- | --- |
| `material_ui 1.10.0` | `packages/material_ui` |
| `cupertino_ui 1.1.6` | `packages/cupertino_ui` |
| `pinput 7.0.0` | `packages/pinput` |
| `flutter_quill 11.6.0` | `packages/flutter_quill` |
| `flutter_math_fork` | 原有本地包增加 OHOS 分支 |

新增本地包保留实际解析的发布版本、运行时代码和许可证，来源归档 SHA-256 记录于各自 `UPSTREAM.md`；不复制上游示例和测试工程。所有平台使用同一份 override，不维护鸿蒙专用包副本。它们使用 OH-Flutter 的平台枚举，仍不宣称标准 Flutter 可直接编译。

集中回归为 `test/shared/ohos_ui_compatibility_test.dart`，覆盖 OHOS 主题、PIN 输入、数学组件和富文本编辑器；该集中回归已实际运行通过。全量测试结果为 868 通过、22 失败、3 跳过；业务 HAP 的原生资产目标阻塞另见 Linux 构建记录，不能把 UI 测试等同于全功能验证。

## 尚未切换的依赖

| 依赖 | 保留原因 | 后续处理 |
| --- | --- | --- |
| `just_audio`、`audio_session` | audio_session fork 仍为 0.2.2，与当前 ^0.2.4 不一致；其 SDK 专属调用另作跨 SDK 兼容检查 | 把 OHOS 支持合入同一版本的 audio_session，实现统一后再替换音频链 |
| `in_app_review` | 同版 fork 引入旧 `url_launcher_ohos`，当前选定的 url_launcher 已内置 OHOS 实现 | 统一 URL launcher 实现，避免两个插件重复处理同一能力 |
| `media_kit_libs_video` / 播放器链 | libs wrapper 虽同版，但配套 media_kit/video 的适配源版本与当前接口不同 | 整条播放器链验证后统一替换 |
| WebRTC、LiveKit、record、通知、文件选择等异版适配 | 当前适配源有版本或接口差异，尚未通过回归验证 | 保留现有 API 基线，逐项移植或选择已验证版本 |
| OpenMLS、sqlite3 原生资产、Firebase Messaging/Analytics、Passkeys | 尚未确认与当前 API 兼容的 OHOS 实现 | 仍是 HAP 完整迁移的缺口 |

### 需要跨 SDK 检查的调用

这些是实际读到的代码，不是根据仓库名称推断：

- [WebF 的平台检测](https://gitcode.com/CPF-Flutter/fluttertpc_webf/blob/ccdf8a05222a408938e51e2b58413355ff2aab7d/lib/src/bridge/dynamic_library.dart)
- [原生菜单的库装载](https://gitcode.com/CPF-Flutter/fluttertpc_super_native_extensions/blob/6f3d0caa84cb26e0d8c39d2868af1998ee80cc99/super_native_extensions/lib/src/native/context.dart)
- [audio_session 的 OHOS 分支](https://gitcode.com/CPF-Flutter/flutter_audio_session/blob/br_v0.2.2_ohos/lib/src/core.dart)

修正这些依赖时，应继续维护每个包的一套跨平台实现，不额外创建一份仅供鸿蒙使用的业务代码。

## 验证状态

- 已检查 YAML 可解析、Git 提交格式、主包与配套包的来源一致性，以及原平台声明未被删除。
- 源码获取：此前详细日志确认 WebF 等 Git clone 返回 HTTP 418；按两个官方域名配置 User-Agent 后，真实 Git 克隆已恢复，原来的固定提交保持不变。
- 实际依赖解析：已成功；锁文件由 Pub 自动生成，37 个适配包及配套包的 Git 提交均与 override 一致。
- analyze：修复图片预览的平台穷尽分支后，0 个 error、7 个 warning、58 个 info；命令因现有诊断项返回 1，未称全绿。
- Flutter tests：使用系统 Clang 后首次编译暴露 93 处 UI 平台分支错误；已停止这次失败的全量测试。统一源码修复后，集中 OHOS UI 回归已通过；配套 Linux 测试引擎也已修复，全量测试已完成：868 通过、22 失败、3 跳过。
- OHOS 宿主：已由固定 SDK 模板建立，复用现有 `lib/`，bundleName 为 `ltd.lkmahz.desktop`，API 26；业务 debug HAP 已实际尝试，确认原生资产被 SDK 映射成 Linux，已停止并记录该阻塞。最小工程三种模式的 HAP 已成功，业务 HAP 与真机测试尚未完成。

## SDK 切换状态

- 本机 `$HOME/flutter` 已切到 OH-Flutter 的本地 `oh-3.47-dev` 分支，固定在发布 tag `3.47.9-ohos-1.0.0`，上游提交 `e5f752df3e25ec897da3c98a74bcced7c21b0bd3`。这是该维护线的发布快照，不声称跟随了远端分支的最新 HEAD。
- 最初因 Git 传输返回 HTTP 418，改用发布页提供的官方源码归档。已核对文件树 `3742768584b8324de38ca68b1cf6e48257da44d7` 和原始提交对象；SDK 已跟踪源码未改写；后续本机依赖 override 的配置单独记录如下。
- `flutter`、`dart` 命令入口已指向新 SDK；原标准 SDK 保存在 `$HOME/flutter-standard-3.47.9-backup-20261113`。
- 本机为 Linux x64。已源码编译并安装 Dart 3.13.4 定制 SDK、Linux 前端运行时和 snapshot，默认 `flutter --version` 已成功。原标准 Dart 和 Mach-O 运行时保留为备份。
- 针对两个官方域名设置 Git User-Agent 后，真实克隆已成功。SDK 已撤销本地临时 override、恢复原始 Git 依赖并完成解析；业务插件已按原有固定提交获取并解析。
- 官方 Linux Command Line Tools 26.0.0.865 已安装，包含 API 26 SDK / NDK；OHPM、Hvigor、HDC、JDK 21、内置 Node 和 Rust ARM64 OHOS 已配置。最小 Flutter debug、profile、release HAP 均已在本机编译成功；均未签名，尚未做真机验证。
- 现有 GitHub Actions 的标准 Flutter 安装步骤尚未迁移；本机完整版本、校验和产物见 [Linux 本机构建记录](HARMONYOS_LINUX_BUILD.md)。

### Linux 本机构建路径

项目要求 **在 Linux 本机完成构建**，保持同一套业务代码与 `pubspec.yaml`。具体版本依据、当前本机进度和验收条件见 [Linux 本机构建记录](HARMONYOS_LINUX_BUILD.md)。

1. 为发布工件实际使用的 Dart 3.13.4 应用完整鸿蒙移植及 ABI 修复，在 Linux 编译定制 Dart SDK、运行时和目标 AOT 生成器，并验证它们与目标引擎配套。必要时从同一份源码重建目标引擎。
2. 获取官方 Linux Command Line Tools，配置 API 26 SDK、OHPM、Hvigor 和 NDK，先验证最小 Flutter 工程的 HAP 构建。
3. 通过可用的官方 Git 传输或经对象哈希校验的本地缓存恢复 SDK 自身依赖和应用插件下载，再更新唯一的应用锁文件，完成本项目检查和 HAP 构建。

不能用 macOS/Windows 二进制或旧版 OHOS 引擎文件替代 Linux 工件，也不能只修改下载地址就视为工具链修复完成。

工件依据：[该 tag 的官方发布清单](https://api.gitcode.com/api/v5/repos/oh-flutter/flutter_flutter/releases/tags/3.47.9-ohos-1.0.0)。以上是该版本和本机的验证结果，不推断所有 OH-Flutter 版本都不能在 Linux 使用。

Git 传输已恢复，项目 `flutter pub get` 已更新唯一锁文件；集中静态检查、OHOS UI 回归和业务 OHOS Dart 编译通过，全量测试结果为 868 通过、22 失败、3 跳过。原有插件兼容性全量盘点见 [审计报告](HARMONYOS_PLUGIN_AUDIT.md)；其中 CSV 是替换前的锁文件快照。
