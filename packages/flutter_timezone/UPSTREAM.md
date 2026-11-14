# flutter_timezone 5.1.1

- Published source: https://pub.dev/packages/flutter_timezone/versions/5.1.1
- Archive SHA-256: `7830bc64bef0b003468fc1f58fc3f3faf54817f8cd6e68fa818b306560410d68`.
- OHOS backend: https://gitcode.com/oh-flutter/flutter_timezone/commit/7f9d44b6dc3ca7558b3a1fd1389756b39583f000 (4.1.0).

The 5.1.1 Dart API and all original platform implementations are unchanged.
Only the OHOS platform declaration/backend is added. Its HAR dependency uses
the embedding path provided by the current OH-Flutter tooling. Native errors
are returned as `PlatformException`; detach clears the channel.

OHOS returns IANA identifiers, which 5.1.1 already converts into `TimezoneInfo`.
The optional localized display name is not provided on OHOS; requesting a locale
still returns identifiers. Device timezone changes need device validation.

Runtime source and original license are retained; Apache-2.0 for the OHOS
backend is included as `LICENSE-OHOS`. Upstream examples/tests/caches are omitted.
