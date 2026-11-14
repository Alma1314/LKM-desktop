# wakelock_plus 1.8.0

- Published source: https://pub.dev/packages/wakelock_plus/versions/1.8.0
- Archive SHA-256: `22b3e7e937721de70e63c85e7139f4ac781dc22863b9262431a53ac030eb074b`.
- OHOS backend: https://gitcode.com/CPF-Flutter/fluttertpc_wakelock_plus/commit/a5ae85fe13d7b92ad9d48bdabd69e4117f665be6 (`wakelock_plus/ohos`, 1.6.1).

The 1.8.0 Dart API, original platforms (including tvOS), dependencies and
Pigeon 28 / platform_interface 1.7.0 remain unchanged. Only the OHOS platform
declaration/backend is added; its embedding HAR path is normalized for the
current OH-Flutter tooling.

The native codec matches the current channel names, custom tags 129/130 and
list envelopes. It awaits `setWindowKeepScreenOn`, reads actual window state,
and reports SDK errors or a detached ability as errors. This controls the
foreground window's screen, not background execution. Device lifecycle and
screen behavior still require device validation.

Runtime source and original BSD license are retained; Apache-2.0 for the OHOS
backend is included as `LICENSE-OHOS`. Upstream examples/tests/caches are omitted.
