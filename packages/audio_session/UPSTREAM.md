# audio_session 0.2.4

Base: pub.dev audio_session 0.2.4, archive SHA-256 `f9e7711a0e24ca8b40f5d7ac374c3c6e55016f3157912badd18199cdbbca5c4d`.
The existing Dart core is retained byte-for-byte as a subsequence: the OHOS
changes are additions only. Original Android/Apple/Web sources stay at 0.2.4.

OHOS code: https://gitcode.com/CPF-Flutter/flutter_audio_session
Commit: `62af3718564bca39e8eba77c9cf8a75aeebfd43e` (0.2.2 OHOS port).
Only OHOS additions in core.dart, ohos.dart and the native ohos directory are
ported; the package API/version is not downgraded. The port's Apache 2.0
license is retained in LICENSE-OHOS and its copyright headers.

All application platforms select this one implementation.
