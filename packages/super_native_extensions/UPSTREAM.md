# super_native_extensions 0.9.1

Source: https://gitcode.com/CPF-Flutter/fluttertpc_super_native_extensions
Commit: `6f3d0caa84cb26e0d8c39d2868af1998ee80cc99`, package `super_native_extensions`.
Runtime sources, Cargokit, native platform implementations and licenses retained.
Build caches, upstream tests/CI, editor settings and machine-specific files omitted.

Local change: build the existing OHOS Rust implementation and drag helper on
Linux through a native-assets hook. Other targets retain Cargokit. Rust Git
dependencies are pinned and Cargo.lock is checked in. The hook bundles the
library required by both ArkTS N-API and Dart FFI.

OHOS reuses the existing Flutter menu implementation, also used on Android and
Windows; upstream OHOS native menu display reports UnsupportedOperation.
Irondash engine integration and native drag/drop still need device validation.
Compiling and packaging the library alone is not runtime acceptance.
