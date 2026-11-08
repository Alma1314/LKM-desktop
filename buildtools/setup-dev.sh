#!/usr/bin/env bash
#
# LKM desktop development bootstrap.
#
# Checks the Flutter toolchain, checks out the quickjs bridge submodule, runs
# `flutter pub get` (the shared Solsynth packages are vendored in `packages/`),
# and reports the system packages a Linux desktop build still needs.
#
# Usage: ./buildtools/setup-dev.sh
#
set -euo pipefail

REQUIRED_FLUTTER="${REQUIRED_FLUTTER:-3.47.9}"
MIN_DART="${MIN_DART:-3.13.0}"

# Linux desktop build dependencies from the README. Runtime libs are checked
# too because a missing libgtk-3 / mpv only shows up when the bundle starts.
LINUX_APT_PACKAGES=(
    ninja-build
    cmake
    clang
    pkg-config
    libgtk-3-dev
    libmpv-dev
    mpv
    libayatana-appindicator3-dev
    keybinder-3.0
    libnotify-dev
    libgstreamer1.0-dev
    libgstreamer-plugins-base1.0-dev
    gstreamer1.0-plugins-base
)

cd "$(dirname "$0")/.."

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!!\033[0m %s\n' "$*"; }

# --- Flutter toolchain -------------------------------------------------------
if ! command -v flutter >/dev/null 2>&1; then
    if [ -x "$HOME/flutter/bin/flutter" ]; then
        export PATH="$HOME/flutter/bin:$PATH"
    else
        warn "flutter not found. Install it first, for example:"
        warn "  git clone -b stable https://github.com/flutter/flutter.git \"\$HOME/flutter\""
        warn "  export PATH=\"\$HOME/flutter/bin:\$PATH\""
        exit 1
    fi
fi

log "Flutter $(flutter --version 2>/dev/null | head -n 1)"
log "Expected Flutter ${REQUIRED_FLUTTER} or newer (pubspec.lock pins Dart >= ${MIN_DART})"

# --- Submodules --------------------------------------------------------------
# The shared Solsynth packages are vendored under `packages/`; the quickjs
# bridge is a Linux-only plugin submodule used by the release bundle.
log "Checking out submodules"
git submodule update --init --recursive \
    linux/third_party/quickjs_c_bridge

# --- Dart/Flutter packages ---------------------------------------------------
log "Resolving packages (flutter pub get)"
flutter pub get

# --- Linux system dependencies ----------------------------------------------
if [ "$(uname -s)" = "Linux" ] && command -v dpkg >/dev/null 2>&1; then
    missing=()
    for pkg in "${LINUX_APT_PACKAGES[@]}"; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            missing+=("$pkg")
        fi
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        warn "Missing Linux build dependencies: ${missing[*]}"
        warn "Install them with:"
        warn "  sudo apt-get install -y ${missing[*]}"
    else
        log "Linux build dependencies present"
    fi

    log "Note: release Linux bundles need the quickjs bridge plugin:"
    log "  cmake -B build_qjs -S linux/third_party/quickjs_c_bridge/linux/ -DCMAKE_BUILD_TYPE=Release"
    log "  cp build_qjs/libquickjs_c_bridge_plugin.so build/linux/x64/release/bundle/lib/"
fi

log "Done. Next: flutter run -d linux (or flutter build linux)"
