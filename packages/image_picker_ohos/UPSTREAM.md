# image_picker_ohos 0.8.13+7

Source: https://gitcode.com/CPF-Flutter/flutter_packages/commit/1af98579e1a95d4fca19e422d26f5b6856ac38ba
Path: `packages/image_picker/image_picker_ohos`.

This local implementation retains the fork's CameraPicker / PhotoViewPicker
operations and file/image processing source, adapted to the current
image_picker 1.2.4 / platform_interface 2.11.2 API. The fork's old Pigeon
transport/delegate/cache are replaced by the existing shared interface's
method-channel implementation, plus the current multi-video call. This avoids
a second Dart API implementation and fixes cancellation, overwritten concurrent
requests, incomplete multi-video results and detached callbacks. The native
channel uses ordinary lists, with no custom codec or forked interface.

Provider URIs are copied into UUID directories in the private cache and every
FD is closed once. Resizing preserves aspect ratio, writes complete JPEG bytes
to a `.jpg` cache path and supports dimensions/quality where the SDK codec
supports them. Original files remain untouched. Camera output is sandboxed and
removed after copying. CameraPicker is user mediated; no broad camera or photo
library permission is added. Optional full metadata is platform dependent.
Only Android provides the public lost-data recovery contract; OHOS returns an
empty response and does not promise recovery after process termination.

Gallery selection follows the SDK limit (at most 500); video maxDuration applies
to camera recording, not trimming existing videos. Hardware, URI grants,
metadata/orientation and real camera lifecycle still need device validation.

Official camera picker guidance:
https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V13/camera-picker-V13/

Original BSD `LICENSE`, `LICENSE_ODID` and `LICENSE_HW` retained. Runtime sources
only; upstream example/tests/caches and obsolete transport are omitted.
