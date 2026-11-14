#!/bin/bash
set -e

BASEDIR=$(dirname "$0")

# Workaround for https://github.com/dart-lang/pub/issues/4010
BASEDIR=$(cd "$BASEDIR" ; pwd -P)

if [[ "$(uname -s)" == "Darwin" ]]; then
    export NDK_HOST_TAG="darwin-x86_64"
elif [[ "$(uname -s)" == "Linux" ]]; then
    export NDK_HOST_TAG="linux-x86_64"
else
    echo "Unsupported OS."
    exit
fi

export TARGET_TEMP_DIR=./target

# Platform name (macosx, iphoneos, iphonesimulator)
export CARGOKIT_DARWIN_PLATFORM_NAME=$PLATFORM_NAME

# Arctive architectures (arm64, armv7, x86_64), space separated.
export CARGOKIT_DARWIN_ARCHS=$ARCHS

# Current build configuration (Debug, Release)
export CARGOKIT_CONFIGURATION=Debug

# Path to directory containing Cargo.toml.
export CARGOKIT_MANIFEST_DIR=$BASEDIR/../rust

# Temporary directory for build artifacts.
export CARGOKIT_TARGET_TEMP_DIR=$TARGET_TEMP_DIR

# Output directory for final artifacts.
export CARGOKIT_OUTPUT_DIR=$TARGET_TEMP_DIR/out

# Directory to store built tool artifacts.
export CARGOKIT_TOOL_TEMP_DIR=$TARGET_TEMP_DIR/build_tool

# Directory inside root project. Not necessarily the top level directory of root project.
export CARGOKIT_ROOT_PROJECT_DIR=$BASEDIR/../../


#compiler_path
COMPILER_DIR="$DEVECO_SDK_HOME/default/openharmony/native/llvm/bin"
export PATH="$COMPILER_DIR:$PATH"

#ohos sysroot
export PKG_CONFIG_SYSROOT_DIR="$DEVECO_SDK_HOME/default/openharmony/native/llvm"

export CC_aarch64_unknown_linux_ohos=$COMPILER_DIR/aarch64-unknown-linux-ohos-clang
export AR_aarch64_unknown_linux_ohos=$COMPILER_DIR/llvm-ar
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER=$COMPILER_DIR/aarch64-unknown-linux-ohos-clang
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_AR=$COMPILER_DIR/llvm-ar

export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_RUSTFLAGS="-L$BASEDIR/../ohos/cpp/code/build"

sh "$BASEDIR/run_build_tool.sh" build-ohos "$@"