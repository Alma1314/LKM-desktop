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
| `island_plugin_foundation` | JavaScript plugin runtime — discovery, lifecycle, sandbox, host hooks |
| `island_desktop_presence` | Desktop idle presence and local RPC transport (Linux/macOS/Windows) |
| `solsynth_express` | Solsynth Express marketplace / release / artifact client |
| `flutter_app_update` | Vendored fork of `azhon/flutter_app_update` |
| `flutter_math_fork` | Vendored fork of `simpleclub/flutter_math` (KaTeX fonts loaded lazily) |
| `protocol_handler_windows` | Vendored fork of `leanflutter/protocol_handler` |

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
