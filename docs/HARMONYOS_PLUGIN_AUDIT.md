# OH-Flutter 插件兼容性审计

检查日期：2026-11-13。目标：**OH-Flutter `3.47.9-ohos-1.0.0`，保留 Flutter 原生界面，产物为 HAP**。

本报告与 CSV 保留替换前的审计快照；后续 SDK 安装、依赖替换和验证结果见 [替换进度](HARMONYOS_PLUGIN_REPLACEMENTS.md) 与 [Linux 构建记录](HARMONYOS_LINUX_BUILD.md)。

## 结论与范围

当前依赖不能原样用于鸿蒙。已找到多款与锁定版本一致或接近的 OHOS 适配源，但这只证明存在源码候选，**没有完成 OH-Flutter 依赖求解、HAP 编译或真机功能验证，不能标记“全部兼容”**。

- 扫描 `.dart_tool/package_config.json`、所有已解析包的 `pubspec.yaml`、`lib/` 原生通道/FFI 信号、`hook/`、`rust/`，与 `pubspec.lock` 逐包对齐。
- 共 **467 个包（含应用自身，锁文件依赖 466 个）**；其中有 **176 个声明 Flutter plugin 的包**，包括 **57 个直接主依赖插件**。该数字包含其他系统实现和模板残留，不是需要移植的插件数量。
- 全部包和传递依赖结果在 [完整 CSV 清单](HARMONYOS_PLUGIN_AUDIT.csv)。下面列出所有直接插件、关键原生依赖链及 UI 平台问题；其他 Dart 包同样包含在 CSV 中，没有跳过本地包和 dev 依赖。
- 只读取公开仓库与本地缓存；没有替换 `pubspec.yaml`/锁文件、修改 pub cache、切换全局 Flutter 或安装 SDK。
- 本机没有已配置的 OH-Flutter、DevEco/ohpm/hvigorw/hdc 验证环境；仓库中的 `ohos/` 当前没有原生工程文件。

代码基线：`f95e283554d5210b889655c852a2bf0f3b29ecc6`。锁文件 SHA-256：`78641b115b02666dc5571367465cd62a418d5bd0c827cdf4f91caa54dd18d7a5`。

## 优先验证的同版来源

下列来源的包版本与当前锁定版本一致（有 OHOS 声明或已经核实的配套依赖链），适合优先做独立验证；“同版”不等于接口和运行行为全部一致。预发布后缀版另列于下表。

`device_info_plus 13.3.0`, `disk_space_2 1.0.13`, `file_saver 0.7.0`, `flutter_callkit_incoming 3.1.6`, `flutter_inappwebview 6.1.5`, `flutter_secure_storage 11.2.0`, `flutter_sharing_intent 2.0.4`, `gal 2.3.3`, `geolocator 14.1.2`, `in_app_review 2.0.12`, `irondash_engine_context 0.5.5`, `irondash_message_channel 0.7.0`, `just_audio 0.10.6`, `local_auth 3.0.2`, `media_kit_libs_video 1.0.7`, `native_exif 0.8.0`, `open_file 4.0.0`, `package_info_plus 10.2.2`, `pasteboard 0.6.0`, `sqflite 2.4.5`, `super_context_menu 0.9.1`, `super_native_extensions 0.9.1`, `url_launcher 6.3.3`, `video_thumbnail 0.5.6`, `webf 0.24.27`。

存储基础包另有 `shared_preferences 2.5.6-ohos.1`、`path_provider 2.1.6-ohos.2`、`permission_handler 13.0.2-ohos.1`。这些是独立 fork/预发布版本，需要显式来源或约束；不是执行普通 `pub upgrade` 就会得到的 pub.dev 兼容版。

## 直接插件与原生依赖

版本取自实际读取的 `pubspec.yaml`，不是分支名或聚合清单。开发分支在注意列中说明。链接指向读到该版本的仓库路径；CSV 还记录 ref、源码路径和已获得的 commit。

| 包 | 当前锁定版 | 核实的适配包版本 | 状态 / 接入注意 |
| --- | --- | --- | --- |
| `audio_session` | 0.2.4 | [0.2.2](https://gitcode.com/CPF-Flutter/flutter_audio_session/blob/br_v0.2.2_ohos/pubspec.yaml) | 适配源 0.2.2 低于根依赖 ^0.2.4；与 just_audio 的 Git 来源需统一。 |
| `connectivity_plus` | 7.3.1 | [7.0.0](https://gitcode.com/CPF-Flutter/flutter_plus_plugins/blob/br_connectivity_plus-v7.0.0_ohos/packages/connectivity_plus/connectivity_plus/pubspec.yaml) | 有 7.0.0 适配分支，当前 7.3.1；需核对列表返回值、事件与接口版本。 |
| `desktop_drop` | 0.8.4 | [0.7.0](https://gitcode.com/CPF-Flutter/fluttertpc_desktop_drop/blob/main/packages/desktop_drop/pubspec.yaml) | 找到仓库，但读到的 0.7.0 pubspec 未声明 OHOS；手机端拖放按产品需求处理。 |
| `desktop_multi_window` | 0.3.1 | 未核实 | 当前仅 macOS/Windows/Linux；鸿蒙手机不应初始化桌面多窗口实现。 |
| `device_info_plus` | 13.3.0 | [13.3.0](https://gitcode.com/oh-flutter/device_info_plus/blob/main/packages/device_info_plus/device_info_plus/pubspec.yaml) | 同版 OHOS 实现；需验证设备标识、字段和权限。 |
| `disk_space_2` | 1.0.13 | [1.0.13](https://gitcode.com/oh-flutter/disk_space_2/blob/feat%2Fohos_disk_space_2_1.0.13/pubspec.yaml) | 同版 OHOS 实现；需验证沙箱磁盘容量单位。 |
| `drift` | 2.35.3 | 未核实 | 自身为 Dart 层；sqlite3 3.9.0 原生资产/构建 hook 未确认支持 OHOS。 |
| `drift_flutter` | 0.3.1 | 未核实 | 依赖 path_provider 与 sqlite3；不能用 sqflite 的兼容版证明 Drift 可用。 |
| `file_picker` | 13.3.2 | [13.1.0-ohos.2](https://gitcode.com/oh-flutter/file_picker/blob/main/pubspec.yaml) | 适配版 13.1.0-ohos.2 低于 13.3.2；需迁移或合并 OHOS 改动。 |
| `file_saver` | 0.7.0 | [0.7.0](https://gitcode.com/oh-flutter/file_saver/blob/feat%2Fohos_file_saver_0.7.0/pubspec.yaml) | 同版 OHOS 实现；文件 URI、用户选择与沙箱权限需真机验证。 |
| `firebase_analytics` | 13.0.1 | 未核实 | 未找到与当前版本对应的、已核实的 OHOS 实现；需鸿蒙统计方案或明确降级。 |
| `firebase_core` | 5.1.0 | [3.15.2](https://atomgit.com/Wangzhipeng520/firebase_core/blob/HEAD/pubspec.yaml) | 仅找到第三方 3.15.2 源码声明 OHOS；与当前 5.1.0 不同，不能证明 Messaging/Analytics 可用。 |
| `firebase_messaging` | 17.0.1 | 未核实 | 未找到与当前版本对应的、已核实的 OHOS 实现；鸿蒙推送还涉及服务端设备令牌和通道。 |
| `flutter_callkit_incoming` | 3.1.6 | [3.1.6](https://gitcode.com/oh-flutter/flutter_callkit_incoming/blob/feat%2Fohos_flutter_callkit_incoming_3.1.6/pubspec.yaml) | 同版 OHOS 实现；系统来电、后台与权限能力需单独验证。 |
| `flutter_image_compress` | 2.5.1 | 未核实 | 当前已引入 flutter_image_compress_ohos 0.0.3+1，并有 OHOS 注册声明；尚未实机构建。 |
| `flutter_inappwebview` | 6.1.5 | [6.1.5](https://gitcode.com/CPF-Flutter/flutter_inappwebview/blob/br_v6.1.5_ohos/flutter_inappwebview/pubspec.yaml) | 6.1.5 同版 fork；必须一起处理 OHOS 实现、platform_interface 及同仓库 path 依赖，不能只加一个 Git URL。 |
| `flutter_local_notifications` | 23.0.0 | [22.3.2](https://gitcode.com/oh-flutter/flutter_local_notifications/blob/main/flutter_local_notifications/pubspec.yaml) | 找到 22.3.2；当前为 23.0.0，需核对通知调度、动作和权限接口。 |
| `flutter_math_fork` | 0.7.4 | [0.7.4](https://gitcode.com/CPF-Flutter/flutter_math_fork/blob/HEAD/pubspec.yaml) | 本地 vendored 包的 switch 仅覆盖六平台；OHOS 下可能出现未初始化变量等编译问题，不能直接换旧 fork 丢掉字体补丁。 |
| `flutter_native_splash` | 2.4.8 | [2.3.1](https://gitcode.com/CPF-Flutter/fluttertpc_flutter_native_splash/blob/HEAD/pubspec.yaml) | 属于生成工具及启动页支持；需 OHOS 工程资源配置，不能把旧 fork 的存在算作当前运行时兼容。 |
| `flutter_nfc_kit` | 3.7.0 | [3.6.2](https://gitcode.com/CPF-Flutter/fluttertpc_flutter_nfc_kit/blob/br_3.41_dev/pubspec.yaml) | 开发分支读到 3.6.2，当前为 3.7.0；需核对 NFC tag/API 与权限。 |
| `flutter_quill` | 11.6.0 | [11.4.1](https://gitcode.com/CPF-Flutter/fluttertpc_flutter_quill/blob/master/pubspec.yaml) | 现有 11.6.0 依赖 quill_native_bridge 和 keyboard visibility fork；社区编辑器 fork 为 11.4.1，需避免直接降级编辑器。 |
| `flutter_secure_storage` | 11.2.0 | [11.2.0](https://gitcode.com/oh-flutter/flutter_secure_storage/blob/main/flutter_secure_storage/pubspec.yaml) | 11.2.0 wrapper + tag 11.2.0-ohos.1 的 OHOS 实现 1.2.2；需验证加密、持久性与密钥生命周期。 |
| `flutter_sharing_intent` | 2.0.4 | [2.0.4](https://gitcode.com/oh-flutter/flutter_sharing_intent/blob/main/pubspec.yaml) | 同版 OHOS 实现；需要在原生 Ability 配置接收分享的入口。 |
| `flutter_timezone` | 5.1.1 | [4.1.0](https://gitcode.com/oh-flutter/flutter_timezone/blob/main/pubspec.yaml) | OHOS 源为 4.1.0，当前为 5.1.1；项目使用 TimezoneInfo.identifier，需核对返回类型。 |
| `flutter_webrtc` | 1.6.3 | [0.9.48+hotfix.1](https://gitcode.com/CPF-Flutter/fluttertpc_flutter_webrtc/blob/br_v1.2.1_ohos/pubspec.yaml) | br_v1.2.1_ohos 的 pubspec 仍为 0.9.48+hotfix.1；不能仅凭分支名认定兼容当前 1.6.3。 |
| `gal` | 2.3.3 | [2.3.3](https://gitcode.com/oh-flutter/gal/blob/feat%2Fohos_gal_2.3.3/pubspec.yaml) | 同版 OHOS 实现；相册保存权限与格式需真机验证。 |
| `geocoding` | 5.0.1 | [4.0.0](https://gitcode.com/CPF-Flutter/fluttertpc_geocoding/blob/br_v5.0.1_ohos_dev/geocoding/pubspec.yaml) | br_v5.0.1_ohos_dev 的 pubspec 仍为 4.0.0；当前为 5.0.1，不能直接按同版替换。 |
| `geolocator` | 14.1.2 | [14.1.2](https://gitcode.com/oh-flutter/geolocator/blob/main/geolocator/pubspec.yaml) | 同版 OHOS 实现；定位权限、后台定位与服务状态需验证。 |
| `image_picker` | 1.2.4 | [1.2.1](https://gitcode.com/CPF-Flutter/flutter_packages/blob/br_image_picker-v1.2.1_ohos/packages/image_picker/image_picker/pubspec.yaml) | 找到 1.2.1 适配版；当前 1.2.4，需配套 image_picker_ohos 与权限配置。 |
| `image_picker_android` | 0.8.13+25 | 未核实 | Android 专用实现，OHOS 不应注册；保留 Android 的调用保护。 |
| `image_picker_platform_interface` | 2.11.2 | 未核实 | 接口包不是平台实现；配套 OHOS picker 仍需验证接口版本。 |
| `in_app_purchase` | 3.3.1 | [3.2.3](https://gitcode.com/CPF-Flutter/flutter_packages/blob/br_in_app_purchase-v3.2.3_ohos/packages/in_app_purchase/in_app_purchase/pubspec.yaml) | 找到 3.2.3 OHOS 实现入口；当前 3.3.1，商城商品、支付校验和后端不能照搬 Apple StoreKit。 |
| `in_app_purchase_storekit` | 0.4.17 | 未核实 | Apple 专用实现，不用于 HAP；现有 Apple 购买链应继续做平台隔离。 |
| `in_app_review` | 2.0.12 | [2.0.12](https://gitcode.com/CPF-Flutter/fluttertpc_in_app_review/blob/br_2.0.12_ohos_dev/in_app_review/pubspec.yaml) | 开发分支有 2.0.12 同版声明；需真机验证商店跳转及上架配置。 |
| `island_desktop_presence` | 0.0.1 | 未核实 | 自有桌面插件，仅 Linux/macOS/Windows；手机端需禁用桌面 idle/media 监听或另做原生实现。 |
| `just_audio` | 0.10.6 | [0.10.6](https://gitcode.com/oh-flutter/just_audio/blob/main/just_audio/pubspec.yaml) | 同版 0.10.6；但 fork 锁了 audio_session Git 0.2.2，当前应用要求 ^0.2.4，整图不能直接解析。 |
| `liquid_glass_renderer` | 1.0.0-dev.2 | 未核实 | 含 Flutter GPU、shader 构建 hook；需验证 OH-Flutter Impeller/impellerc 与原生资产，不算纯 Dart 已兼容。 |
| `livekit_client` | 2.13.2 | [2.1.0](https://gitcode.com/CPF-Flutter/fluttertpc_livekit_client/blob/br_v2.6.0_ohos/pubspec.yaml) | br_v2.6.0_ohos 的 pubspec 仍为 2.1.0，并锁旧版 WebRTC/设备/网络 fork；与当前 2.13.2 有明显差距。 |
| `local_auth` | 3.0.2 | [3.0.2](https://gitcode.com/oh-flutter/local_auth/blob/feat%2Fohos_local_auth_3.0.2/pubspec.yaml) | 同版 OHOS 实现；生物识别、错误码和可用性需真机验证。 |
| `map_launcher` | 7.0.0 | [4.4.2](https://gitcode.com/CPF-Flutter/fluttertpc_map_launcher/blob/br_4.4.2_ohos/pubspec.yaml) | 找到 4.4.2，当前 7.0.0；需核对地图应用枚举与 URI 协议。 |
| `material_ui` | 1.10.0 | 未核实 | 1.10.0 中有只覆盖六个平台的 switch 表达式；OH-Flutter 增加 TargetPlatform.ohos 后需修复穷尽分支。 |
| `media_kit` | 1.2.6 | [1.2.1](https://gitcode.com/CPF-Flutter/fluttertpc_flutter_media_kit/blob/main/media_kit/pubspec.yaml) | 找到 1.2.1 OHOS 实现；当前 1.2.6，播放内核/FFI 打包需与 video/libs 同步。 |
| `media_kit_libs_video` | 1.0.7 | [1.0.7](https://gitcode.com/CPF-Flutter/fluttertpc_flutter_media_kit/blob/main/libs/universal/media_kit_libs_video/pubspec.yaml) | 1.0.7 fork 增加 media_kit_libs_ohos_video；仍需对应播放器、arm64 原生库与许可证核验。 |
| `media_kit_video` | 2.0.1 | [1.3.1](https://gitcode.com/CPF-Flutter/fluttertpc_flutter_media_kit/blob/main/media_kit_video/pubspec.yaml) | 找到 1.3.1，当前 2.0.1；播放器与纹理渲染接口需迁移验证。 |
| `mobile_scanner` | 7.5.0 | [7.1.4](https://gitcode.com/CPF-Flutter/fluttertpc_mobile_scanner/blob/br_v7.4.2_ohos_dev/pubspec.yaml) | br_v7.4.2_ohos_dev 的 pubspec 仍为 7.1.4，当前 7.5.0；相机和扫码格式需核对。 |
| `native_exif` | 0.8.0 | [0.8.0](https://gitcode.com/CPF-Flutter/fluttertpc_native_exif/blob/br_3.41_dev/pubspec.yaml) | br_3.41_dev 有 0.8.0 同版 OHOS 声明；属于开发分支，需验证图片格式与写入。 |
| `native_glass_navbar` | 1.2.0 | 未核实 | 当前仅 iOS；鸿蒙应使用 Flutter 导航栏回退，不应调用 iOS channel。 |
| `open_file` | 4.0.0 | [4.0.0](https://gitcode.com/CPF-Flutter/fluttertpc_open_file/blob/br_v4.0.0_ohos_dev/open_file/pubspec.yaml) | br_v4.0.0_ohos_dev 已核实 4.0.0 同版 OHOS 入口；需配套 open_file_ohos，并验证文件 URI 与外部应用唤起。 |
| `openmls` | 3.3.0 | 未核实 | 未找到已核实的 OHOS 适配源；当前 hook 不支持 OHOS，需 Rust/SQLCipher/FRB 与 arm64 编译链一起移植。 |
| `package_info_plus` | 10.2.2 | [10.2.2](https://gitcode.com/oh-flutter/package_info_plus/blob/main/pubspec.yaml) | 同版 OHOS 实现；仓库带本地 platform_interface 路径，接入需一起处理。 |
| `passkeys` | 2.24.1 | 未核实 | 未找到已核实的 OHOS 同版实现；不能依赖 Android/iOS Passkeys 自动覆盖鸿蒙。 |
| `pasteboard` | 0.6.0 | [0.6.0](https://gitcode.com/oh-flutter/pasteboard/blob/feat%2Fohos_pasteboard_0.5.0/pubspec.yaml) | 同版 0.6.0 OHOS 源；分支名还写 0.5.0，须以实际 pubspec 为准。 |
| `path_provider` | 2.1.6 | [2.1.6-ohos.2](https://gitcode.com/oh-flutter/path_provider/blob/main/pubspec.yaml) | 找到 2.1.6-ohos.2；需明确预发布版本的依赖约束，并验证各沙箱路径。 |
| `permission_handler` | 13.0.2 | [13.0.2-ohos.1](https://gitcode.com/oh-flutter/permission_handler/blob/main/pubspec.yaml) | 找到 13.0.2-ohos.1；需要 OHOS module.json5 权限与运行时请求共同配置。 |
| `protocol_handler` | 0.2.0 | 未核实 | 未找到已核实的 OHOS 兼容版；当前主要用于桌面，HAP deeplink 需 Ability 的 Want/回调处理。 |
| `quick_actions` | 1.1.1 | [1.1.0](https://gitcode.com/CPF-Flutter/flutter_packages/blob/br_quick_actions-v1.1.0_ohos_dev/packages/quick_actions/quick_actions/pubspec.yaml) | 找到 1.1.0 开发分支；当前 1.1.1，需验证鸿蒙桌面快捷入口。 |
| `record` | 7.1.2 | [6.1.2](https://gitcode.com/CPF-Flutter/fluttertpc_record/blob/br_v6.1.2_ohos/record/pubspec.yaml) | 找到 6.1.2，当前 7.1.2；其 platform_interface ^1.4.0 与当前 2.1.0 不同，不能只换原生实现。 |
| `shake` | 3.0.0 | [3.0.0](https://gitcode.com/CPF-Flutter/fluttertpc_shake/blob/HEAD/pubspec.yaml) | 自身 Dart 层，受 sensors_plus 兼容性约束。 |
| `share_plus` | 13.3.1 | [12.0.1](https://gitcode.com/CPF-Flutter/flutter_plus_plugins/blob/br_share_plus-v12.0.1_ohos/packages/share_plus/share_plus/pubspec.yaml) | 找到 12.0.1，当前 13.3.1；需核对文件 URI、分享结果及接口版本。 |
| `shared_preferences` | 2.5.6 | [2.5.6-ohos.1](https://gitcode.com/oh-flutter/shared_preferences/blob/main/pubspec.yaml) | 找到 2.5.6-ohos.1；预发布后缀需显式选源/约束，需验证重启与多 isolate 存储行为。 |
| `shared_preferences_platform_interface` | 2.4.2 | 未核实 | 接口包，可随 wrapper 复用，但不是 OHOS 实现。 |
| `sign_in_with_apple` | 8.2.0 | [6.1.3](https://gitcode.com/CPF-Flutter/fluttertpc_dart_packages/blob/br_6.1.3_ohos/packages/sign_in_with_apple/sign_in_with_apple/pubspec.yaml) | 找到 6.1.3，当前 8.2.0；HAP 登录回调与 OAuth 配置需要单独处理。 |
| `snow_fall_animation` | 0.0.1+3 | 未核实 | pubspec 留有 some_platform 模板声明，但未发现原生 channel；应清理/核对声明后编译，不能算已适配原生插件。 |
| `super_context_menu` | 0.9.1 | [0.9.1](https://gitcode.com/CPF-Flutter/fluttertpc_super_native_extensions/blob/br_v0.9.1_ohos/super_context_menu/pubspec.yaml) | 0.9.1 同版 fork 依赖配套 super_native_extensions/Irondash 和旧设备信息 Git 源，需要统一来源。 |
| `tray_manager` | 0.8.3 | 未核实 | 0.8.3 不再是简单 channel 插件，传递依赖 cnativeapi 不支持 OHOS 的 hook；需构建时隔离，单做 if 判断不足。 |
| `url_launcher` | 6.3.3 | [6.3.3](https://gitcode.com/oh-flutter/url_launcher/blob/feat%2Fohos_url_launcher_6.3.3/pubspec.yaml) | 同版 OHOS 实现；URL 白名单与唤起权限需验证。 |
| `video_thumbnail` | 0.5.6 | [0.5.6](https://gitcode.com/CPF-Flutter/fluttertpc_video_thumbnail/blob/br_0.5.6_ohos/pubspec.yaml) | 0.5.6 同版 OHOS 分支；需验证文件路径、格式和大视频内存。 |
| `wakelock_plus` | 1.8.0 | [1.1.4](https://gitcode.com/CPF-Flutter/fluttertpc_wakelock_plus/blob/HEAD/wakelock_plus/pubspec.yaml) | 默认分支读到 1.1.4，未声明 OHOS，且限制 package_info_plus <6，与当前 10.2.2 冲突；尚不能确认可直接接入的兼容版。 |
| `webf` | 0.24.27 | [0.24.27](https://gitcode.com/CPF-Flutter/fluttertpc_webf/blob/br_3.44_dev/pubspec.yaml) | br_3.44_dev 已核实 0.24.27 同版 OHOS 声明；属于 3.44 开发线，仍需在 OH-Flutter 3.47 验证原生库、桥接和 Flutter API。 |
| `window_manager` | 0.5.1 | 未核实 | 项目固定自有 Git fork；候选仓库有线索但包未核实，桌面窗口管理不应在 HAP 手机路径初始化。 |
| `windows_notification` | 1.3.0 | 未核实 | 仅 Windows；鸿蒙不能复用 Windows 通知实现。 |

## 间接依赖与配套实现

Android、iOS、桌面、Web 的实现包无需全部移植到 OHOS，但必须避免错误注册/调用，并检查构建 hook 是否会提前运行。下表列出会影响核心功能的传递链；全部 176 个 plugin 声明包逐项在 CSV 中。

| 包 | 当前锁定版 | 核实的适配包版本 | 状态 / 接入注意 |
| --- | --- | --- | --- |
| `cnativeapi` | 0.5.10 | 未核实 | 构建 hook 的 OS switch 显式拒绝 OHOS；仅运行时禁用托盘仍可能过不了构建。 |
| `cupertino_ui` | 1.1.6 | 未核实 | 包含六平台 switch，需核对 OHOS 分支及交互回退。 |
| `flutter_app_update` | 3.2.4 | [3.2.2](https://gitcode.com/CPF-Flutter/fluttertpc_flutter_app_update/blob/HEAD/pubspec.yaml) | 项目使用本地 Android/iOS 更新插件；社区 fork 不能直接替换本地补丁，HAP 更新也不同于 APK。 |
| `flutter_keyboard_visibility_temp_fork` | 0.1.6 | [0.1.5](https://gitcode.com/guanxia/flutter_keyboard_visibility_temp_fork/blob/master/flutter_keyboard_visibility_temp_fork/pubspec.yaml) | 找到 0.1.5 OHOS 源；当前 0.1.6，需要核对差异与注册。 |
| `flutter_rust_bridge` | 2.13.0 | [2.14.0-beta.1](https://gitcode.com/oh-flutter/flutter_rust_bridge/blob/master/frb_dart/pubspec.yaml) | OH 社区 master 读到 2.14.0-beta.1；openmls 精确要求 >=2.13.0 <2.13.1，不能直接覆盖 runtime。 |
| `irondash_engine_context` | 0.5.5 | [0.5.5](https://gitcode.com/CPF-Flutter/fluttertpc_irondash/blob/br_v0.5.5_ohos/engine_context/dart/pubspec.yaml) | 0.5.5 同版 OHOS 源；需与上层 native extensions 一起验证。 |
| `irondash_message_channel` | 0.7.0 | [0.7.0](https://gitcode.com/CPF-Flutter/fluttertpc_irondash/blob/br_v0.5.5_ohos/message_channel/dart/pubspec.yaml) | 0.7.0 同版 Dart 包依赖 Irondash 原生通道；需配套引擎上下文。 |
| `nativeapi` | 0.5.10 | 未核实 | 经 cnativeapi 使用原生资产；OHOS 需隔离依赖或移植完整底层。 |
| `nativeapi_flutter` | 0.5.10 | 未核实 | 依赖 nativeapi/cnativeapi 原生资产，不能视为纯 Flutter 层。 |
| `quill_native_bridge` | 11.2.0 | [11.0.1](https://gitcode.com/CPF-Flutter/fluttertpc_quill_native_bridge/blob/master/quill_native_bridge/pubspec.yaml) | 找到 11.0.1 的 OHOS 入口，当前 11.2.0；需配套 quill_native_bridge_ohos 及接口。 |
| `sensors_plus` | 6.1.2 | [6.1.1](https://gitcode.com/CPF-Flutter/flutter_plus_plugins/blob/br_sensors_plus-v6.1.1_ohos/packages/sensors_plus/sensors_plus/pubspec.yaml) | 找到 6.1.1，当前 6.1.2；shake 3.0.0 的 OHOS fork 已指定此分支。 |
| `sqflite` | 2.4.5 | [2.4.5](https://gitcode.com/oh-flutter/sqflite/blob/main/sqflite/pubspec.yaml) | 同版 2.4.5 wrapper 与 sqflite_ohos；用于缓存等依赖，不能覆盖 Drift 的 sqlite3 FFI 链。 |
| `sqlite3` | 3.9.0 | 未核实 | 3.9.0 含 native-assets hook；预编译目标没有 OHOS，需移植编译/装载配置。旧 sqlite3_flutter_libs 不能直接替代 3.x hook。 |
| `super_native_extensions` | 0.9.1 | [0.9.1](https://gitcode.com/CPF-Flutter/fluttertpc_super_native_extensions/blob/br_v0.9.1_ohos/super_native_extensions/pubspec.yaml) | 0.9.1 同版 OHOS 源；Rust/Irondash 和二进制打包仍需验证。 |

此外，已读取配套实现：`flutter_inappwebview_ohos 1.1.3`、该仓库的 `flutter_inappwebview_platform_interface 1.3.0+1`、`flutter_secure_storage_ohos 1.2.2`（tag `11.2.0-ohos.1`）、`sqflite_ohos 2.4.5`。它们是新增的 OHOS 依赖，不在当前原始锁文件中；接入时需一并纳入锁文件。

## 不能直接替换的依赖关系

1. **WebF**：`br_3.44_dev` 的实际 pubspec 是 **0.24.27**，与当前版本一致并声明 OHOS，优先验证它可以保留现有 WebF 小程序容器。该分支属于 3.44 开发线，尚无本项目在 OH-Flutter 3.47 的编译和真机证据；需要确认 arm64 原生库、桥接、离线资源及 Flutter API。已找到的 InAppWebView 6.1.5 可作为容器候选，但本次没有擅自切换架构。
2. **WebView 同仓库路径依赖**：6.1.5 适配源把平台接口、Android/iOS/macOS/Web/Windows/OHOS 包设为相邻 `path` 依赖。不能只改主包 Git URL 后假设解析成功，需统一 vendoring 或逐项正确引用同一版本。
3. **数据库**：`drift_flutter → path_provider + sqlite3 3.9.0`，以及缓存库的 `sqflite 2.4.5` 是两条不同的链。后者有 OHOS wrapper/实现，不代表前者的 native-assets hook 已适配；旧版 `sqlite3_flutter_libs` 也不能直接代替 sqlite3 3.x 的 hook。
4. **加密聊天**：`openmls 3.3.0 → flutter_rust_bridge >=2.13.0 <2.13.1`，而 OH 社区 master 的 FRB 是 2.14.0-beta.1；直接覆盖会违背精确 runtime/codegen 约束。OpenMLS 的 Rust 库、数据库依赖、ABI 和 hook 需要一起移植。
5. **音频**：`just_audio 0.10.6` 虽同版，但其适配 fork 使用 `audio_session` Git 0.2.2，与本项目根依赖 `^0.2.4` 冲突。需要把 OHOS 实现移到当前基础版本，或审查并统一依赖来源/约束。
6. **RTC 与录音**：LiveKit/WebRTC 的分支名与 pubspec 版本不一致；录音适配版 `record 6.1.2` 使用 `record_platform_interface ^1.4.0`，当前为 2.1.0。禁止仅靠 override 隐藏接口差异。
7. **原生菜单与托盘**：菜单有配套 0.9.1 源，但引用旧设备信息 Git 源，需统一依赖。`tray_manager 0.8.3 → nativeapi → cnativeapi` 的构建 hook 显式拒绝 OHOS；运行时不调用托盘不一定能避开构建错误，需要构建时隔离或底层移植。
8. **Firebase、Passkeys、应用内购买**：未核实到当前 Messaging/Analytics/Passkeys 的同版 OHOS 实现。第三方 Firebase Core fork 不证明整套 Firebase 可用；鸿蒙推送、认证、商店支付与服务端也需要对应方案。

## UI 与应用自身的平台分支

OH-Flutter 扩展 `TargetPlatform.ohos`。纯 Dart/Flutter 包也可能因此无法编译，不能仅按“无原生目录”判定兼容。

- `material_ui 1.10.0`：例如 `lib/src/typography.dart` 的 switch 表达式只覆盖六个平台及 null，新增枚举后需要处理 OHOS；页面过渡、菜单和文本选择等也有类似分支。
- `cupertino_ui 1.1.6`：有平台 switch，需要按 OHOS 交互策略处理。
- 本地 `packages/flutter_math_fork`：光标/选择相关 switch 只覆盖六个平台，部分局部变量可能失去确定赋值；需保留本地字体补丁再适配。
- 应用 `lib/core/widgets/content/cloud_file_lightbox.dart` 的平台 switch 没有默认返回；`lib/core/theme.dart` 的平台映射和 `lib/firebase_options.dart` 也需要处理 OHOS。
- `liquid_glass_renderer → flutter_gpu_shaders/Flutter GPU`：还需验证 Impeller、shader hook 和目标引擎的编译工具，不属于仅替换平台插件即可完成的部分。

## 自有原生通道

这些不在 pub.dev 插件清单中，也没有 OHOS 实现：

| 通道 | 当前用途 | OHOS 处理 |
| --- | --- | --- |
| `ltd.lkmahz.desktop/deeplink` | Apple 侧深链回调 | HAP Ability 接收 Want 并转发 Flutter；现有平台判断不覆盖 OHOS |
| `dev.solsynth.solian/native_call` | Android 原生来电桥 | 需要鸿蒙来电/后台方案，不能只替换 CallKit 插件 |
| `dev.solsynth.solian/widget` | Android/iOS 桌面组件同步 | 当前手机判断会跳过 OHOS；鸿蒙卡片需另做原生入口 |
| `dev.solsynth.solian/app_icon` | Apple 更换图标 | 维持平台保护或提供明确回退 |
| `dev.solsynth.solian/cache` | iOS 缓存统计/清理 | 维持平台保护，鸿蒙使用对应沙箱实现 |
| `dev.solsynth.solian/store_purchase` | Apple 商店购买环境 | 维持 Apple 保护；鸿蒙商店链单独实现 |
| `dev.solsynth.solian/share_suggestions` | iOS 分享建议 | 维持 iOS 保护或另做鸿蒙方案 |
| `dev.solsynth.solian/local_communication_notification` | iOS 通信通知 | 维持 iOS 保护，鸿蒙通知按其自身实现验证 |

`WindowMethodChannel('island/call')` 属于桌面多窗口调用，同样不应直接套到手机端。

## 后续适配顺序与验收

1. 独立准备固定 tag 的 OH-Flutter 工具链，先验证基础 Flutter 页面和平台 enum；不覆盖其他平台的标准 SDK。
2. 统一 SharedPreferences、路径、安全存储、包信息、设备信息、URL、权限的来源；解决 UI 的 OHOS 分支与会提前运行的 hook，完成依赖求解和最小 HAP。
3. 逐链验证 sqlite3/Drift、WebF 或 WebView 小程序容器、文件/图片功能。数据读写与密钥持久化必须测应用重启，不能仅测首次打开。
4. 再验证音视频、RTC、推送、登录、扫码、支付和后台能力。仍未适配的功能需明确标记能力缺口，不能把禁用功能算成完整迁移成功。

此 tag 的维护者发布说明要求 DevEco/CLI 26、**最低运行 API 26**、Dart 3.13.4；若要覆盖更旧系统，必须另外选择兼容的 SDK/引擎版本，不能只下调工程的 minimum API。

当前已完成：本地依赖全量静态盘点、适配仓库/分支版本核对、锁文件一致性检查。未完成：OH-Flutter 下的 pub solve、analyze、HAP 编译、安装和真机测试。

## 上游依据与限制

- [OH-Flutter 3.47.9 发布说明](https://gitcode.com/oh-flutter/flutter_flutter/blob/3.47.9-ohos-1.0.0/release-notes/Flutter%203.47.9-ohos%201.0.0%20ReleaseNote.md)
- [OH-Flutter 插件组织](https://gitcode.com/oh-flutter)：本次额外读取了当前公开仓库目录；没有把组织中的任意 fork 自动算成已验证兼容。
- [社区聚合适配清单](https://gitcode.com/oh-flutter/flutter-ohos-adaptation-checklist)：其快照为 2026-10-17，只作发现候选来源，不作为同版兼容结论。
- [CPF 三方库清单](https://gitcode.com/CPF-Flutter/docs/blob/main/ThirdpartyLibrarites.md)及各仓库 branches API：继续读取实际 pubspec，避免把旧默认分支和分支名当成当前版本。
- 读取遇到的 401/403/404、超时和访问频率限制均视为“未核实”，不推断仓库不存在。对未核实项只给出线索，不给出兼容承诺。

CSV 是本次锁文件的审计快照；后续依赖或 fork 分支发生变化需要重新检查。没有运行 HAP 构建，因此不以其他平台的测试通过作为鸿蒙兼容证据。
