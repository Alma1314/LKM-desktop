# file_picker 13.3.2

Base: pub.dev file_picker 13.3.2, archive SHA-256 `c64036857780d7125f011d543f89eedcb5df61da473668bace4eee9ab875284d`.
The current public wrapper and existing platform dependencies are retained.

OHOS backend: https://gitcode.com/oh-flutter/file_picker
Commit: `a845c22b0c444d1724f1d6be9600b5795358c327` (13.1.0-ohos.2).
Only the OHOS backend and native directory are ported to this same package.

Local corrections: use the real folder channel, cache selected provider files
for Dart IO, handle selection status/cancellation, close descriptors and honor
byte views/partial writes when saving. Provider directory URIs cannot be
returned as absolute filesystem paths; this capability reports UnsupportedError.
