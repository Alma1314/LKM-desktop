# Vendored Solsynth packages

These packages were imported from **[Socommon](https://github.com/LKM-AHZ/LKM-socommon)** —
the LKM fork of [Solsynth's Socommon](https://src.solsynth.dev/SoSYS/Socommon) — at commit
`2f3b2b4`, which is the revision the former `socommon` submodule pointed at.

They are ordinary path dependencies (`packages/<name>`), so `flutter pub get` works without
any submodule checkout. The packages depend on each other through relative `../<name>` paths,
so the tree must stay together.

| Package | Purpose |
| --- | --- |
| `solar_network_sdk` | Solar Network API SDK — networking, auth, cloud file services |
| `solar_network_foundation` | Presentation primitives, cloud drive service, step-up (sudo) flow |
| `island_ui_foundation` | Desktop window frame, overlay systems, responsive helpers |
| `island_desktop_presence` | Desktop idle presence and local RPC transport (Linux/macOS/Windows) |
| `solsynth_express` | Solsynth Express marketplace / release / artifact client |
| `flutter_app_update` | Vendored fork of `azhon/flutter_app_update` |
| `flutter_math_fork` | Vendored fork of `simpleclub/flutter_math` (KaTeX fonts loaded lazily) |
| `protocol_handler_windows` | Vendored fork of `leanflutter/protocol_handler` |
| `material_ui` / `cupertino_ui` | Current published UI versions with OH-Flutter platform cases |
| `pinput` / `flutter_quill` | Current published input/editor versions with OH-Flutter platform cases |
| `code_assets` / `native_toolchain_c` | Current native-assets versions with real OHOS targets / NDK compilation |
| `cnativeapi` / `openmls` | Existing versions with explicit OHOS hook handling |
| `audio_session` / `connectivity_plus` / `file_picker` | Current API versions with OHOS native backends |
| `flutter_timezone` / `wakelock_plus` / `in_app_review` | Current API versions with OHOS timezone, screen wake and AppGallery review backends |
| `image_picker` / `image_picker_ohos` / `share_plus` | Current image/video picker and sharing APIs with OHOS system backends |
| `super_native_extensions` | Pinned cross-platform fork with a reproducible OHOS Rust build |

The UI/input packages retain their current APIs and original platforms. All app
targets use the same source, with OHOS following their Android UI behavior.
Each new package's `UPSTREAM.md` records its original archive hash and local
change; runtime source and licenses are retained, upstream examples/tests omitted.

## Why vendored

LKM-desktop diverges from Solian on both branding and backend (LKM-service replaces
`api.solian.app`), so the SDK layer is modified in place. Keeping the packages in this
repository makes those changes atomic with the app: no submodule pointer bump, no second
checkout, one CI run.

Licensing is unchanged: the application and Socommon are both AGPL-3.0, and each vendored
third-party fork carries its own license file.

## Updating from upstream

Treat this directory as a fork of the LKM-socommon repo. To pull upstream changes:

```bash
# 1. Fetch upstream Socommon next to the app repo
git clone --filter=blob:none https://github.com/LKM-AHZ/LKM-socommon /tmp/lkm-socommon
git -C /tmp/lkm-socommon fetch https://src.solsynth.dev/SoSYS/Socommon.git main:upstream

# 2. Diff upstream against the vendored baseline, from the app repository root
git -C /tmp/lkm-socommon diff 2f3b2b4 upstream -- packages > /tmp/socommon.patch
git apply --reject --whitespace=nowarn /tmp/socommon.patch

# 3. Resolve any *.rej files, then verify
flutter pub get && flutter analyze lib
```

Record the new upstream commit here (replace `2f3b2b4`) once the update lands, so the next
diff starts from the right baseline.

OHOS backend licenses are listed under each local package's `flutter.licenses`
so the additional notices are bundled in the app, alongside the original licenses.
