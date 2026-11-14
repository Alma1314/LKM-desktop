# share_plus 13.3.1

Published source: https://pub.dev/packages/share_plus/versions/13.3.1
Archive SHA-256: `db40767f130189d53f3ae8a6393c217ff4a492da1baff718a9873679c0c00224`.
OHOS source: https://gitcode.com/CPF-Flutter/flutter_plus_plugins/commit/bfd882da6893c4c8bfa1648ac637c2d557e6f4fa
Path: `packages/share_plus/share_plus/ohos` (12.0.1).

The current Dart API, platform_interface 7.2.0, all dependencies and original
platform implementations are unchanged. The OHOS platform/backend is added.
The handler is adapted to the current unified `share` map so text, URI and
files work through both SharePlus and legacy Share calls. Native file arrays
are ordinary lists. All private-cache copies finish before opening the system
sheet; FDs close on success/failure and names use separate UUID directories.
The cache remains available to asynchronous receivers until OS cache cleanup.

Show/copy errors propagate; overlapping requests are rejected. Detach releases
the pending call and event subscription, and stale asynchronous work cannot
reply to a newer request. Panel dismissal returns ShareResult.unavailable:
closing the sheet alone cannot confirm a selection or actual delivery. The
existing Cupertino exclusions / iPad origin are platform-specific and are not
applied on OHOS. System-share targets and actual URI handoff need device tests.

Official system-share API:
https://developer.huawei.com/consumer/en/doc/harmonyos-references/share-system-share/

Original BSD license and OHOS Apache-2.0 license (`LICENSE-OHOS`) retained.
Runtime source retained; upstream examples/tests/caches omitted.
