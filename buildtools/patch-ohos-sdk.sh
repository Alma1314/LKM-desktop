#!/usr/bin/env bash
# Preserve the OHOS target when the Flutter tool invokes application hooks.
set -euo pipefail

lkm_patch="$(cd "$(dirname "$0")" && pwd)/patches/flutter-ohos-native-assets.patch"
if [ "$#" -gt 0 ]; then
    lkm_flutter_root="$1"
else
    lkm_flutter_bin="$(readlink -f "$(command -v flutter)")"
    lkm_flutter_root="$(dirname "$(dirname "$lkm_flutter_bin")")"
fi

if git -C "$lkm_flutter_root" apply --reverse --check "$lkm_patch" 2>/dev/null; then
    echo "OHOS native-asset SDK patch already applied."
elif git -C "$lkm_flutter_root" apply --check "$lkm_patch"; then
    git -C "$lkm_flutter_root" apply "$lkm_patch"
    # Force the normal Flutter bootstrap to rebuild its tool snapshot.
    rm -f "$lkm_flutter_root/bin/cache/flutter_tools.stamp"
    echo "Applied OHOS native-asset SDK patch; Flutter will rebuild its tool."
else
    echo "SDK does not match the recorded OH-Flutter patch: $lkm_flutter_root" >&2
    exit 1
fi
