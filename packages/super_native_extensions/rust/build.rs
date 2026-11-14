#[path = "keyboard_map/gen_keyboard_map.rs"]
mod gen_keyboard_map;

fn main() {
    println!("cargo:rerun-if-changed=keyboard_map");
    let target_system = std::env::var("CARGO_CFG_TARGET_OS").unwrap();
    let target_arch = std::env::var("CARGO_CFG_TARGET_ARCH").unwrap();

    if std::env::var("CARGO_CFG_TARGET_ENV").as_deref() == Ok("ohos") {
        build_ohos_drag_helper();
    }

    // keyboard map is currently only supported on desktop.
    match target_system.as_str() {
        "macos" | "linux" | "windows" => {
            gen_keyboard_map::generate_keyboard_map(&target_system).unwrap();
        }
        _ => {}
    }

    // Add support for the maximum page size of 16 KB for Android (only on the arm64 and x86_64 platforms).
    // see: https://developer.android.com/guide/practices/page-sizes#other-build-systems
    if target_system == "android" && (target_arch == "aarch64" || target_arch == "x86_64") {
        println!("cargo:rustc-link-arg=-Wl,-z,max-page-size=16384");
    }
}

fn build_ohos_drag_helper() {
    use std::{env, path::PathBuf, process::Command};
    let source = PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").unwrap())
        .join("../ohos/cpp/code/DragDropHelper.cpp");
    let out = PathBuf::from(env::var_os("OUT_DIR").unwrap());
    let object = out.join("DragDropHelper.o");
    let compiler = env::var("CXX_aarch64_unknown_linux_ohos")
        .expect("Missing OHOS NDK C++ compiler");
    let status = Command::new(compiler)
        .args(["-c", "-fPIC", "-O2", "-std=c++17"])
        .arg(&source).arg("-o").arg(&object).status().unwrap();
    assert!(status.success(), "OHOS drag helper compilation failed");
    let status = Command::new(env::var("AR_aarch64_unknown_linux_ohos").unwrap())
        .arg("rcs").arg(out.join("libDragDropHelper.a")).arg(object)
        .status().unwrap();
    assert!(status.success(), "OHOS drag helper archive failed");
    println!("cargo:rerun-if-changed={}", source.display());
    println!("cargo:rerun-if-changed={}", source.with_extension("h").display());
    println!("cargo:rustc-link-search=native={}", out.display());
    // Resolve platform symbols explicitly; do not leave load-time dependencies
    // on whichever libraries happen to have been loaded by another plugin.
    for library in ["ace_napi.z", "ace_ndk.z", "native_drawing", "pixelmap", "udmf", "pasteboard", "hilog_ndk.z"] {
        println!("cargo:rustc-link-lib={library}");
    }
    println!("cargo:rustc-link-arg=-Wl,--no-undefined");
}
