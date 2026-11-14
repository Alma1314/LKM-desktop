# in_app_review 2.0.12

- Published source: https://pub.dev/packages/in_app_review/versions/2.0.12
- Archive SHA-256: `364db0c160b37fe7fad9cdaa18f968473924b17368869010af902760421b6bf8`.
- OHOS backend: https://gitcode.com/CPF-Flutter/fluttertpc_in_app_review/commit/70faf9d1cf592c392334f06adcffea5af85a3fc0 (`in_app_review/ohos`).

Original public method signatures, platform_interface 2.0.5 and all non-OHOS
implementations remain unchanged. The added Dart registration reuses the
current method-channel implementation, overriding only store listing routing
to the current OHOS application's bundle. No `url_launcher_ohos` or forked
platform interface is introduced; the existing URL launcher remains unique.

The native backend uses AppGalleryKit `showCommentDialog` (API 20+), awaits SDK
completion, and opens the current application's AppGallery listing via its
ability context. Local changes check the API level in `isAvailable`, encode
listing identifiers, remove debug logging and preserve asynchronous SDK errors.
The embedding HAR path is normalized for current OH-Flutter tooling.

Official API and listing guidance:
https://developer.huawei.com/consumer/cn/doc/harmonyos-references/appgallery-commentmanager/
https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/appgallery-comment/

`isAvailable` checks API/context availability, not Huawei account status, store
publication, quotas or whether a prompt is actually displayed. Reviews require
a physical device and appropriate AppGallery app/account configuration. A
successful SDK call does not mean the user submitted a review.

Original MIT license and runtime source are retained, and the OHOS backend's
Apache-2.0 license is included as `LICENSE-OHOS`. Examples/tests/caches omitted.
