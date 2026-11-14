# Source this file before building HarmonyOS HAPs on Linux.
# Override LKM_HARMONYOS_HOME / LKM_OHOS_JAVA_HOME for another installation.
export LKM_HARMONYOS_HOME="${LKM_HARMONYOS_HOME:-$HOME/harmonyos/command-line-tools}"
export DEVECO_SDK_HOME="$LKM_HARMONYOS_HOME/sdk"
export DEVECO_NODE_HOME="$LKM_HARMONYOS_HOME/tool/node"
export OHOS_NDK_HOME="$DEVECO_SDK_HOME/default/openharmony/native"
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER="$OHOS_NDK_HOME/llvm/bin/aarch64-unknown-linux-ohos-clang"
export CC_aarch64_unknown_linux_ohos="$CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER"
export CXX_aarch64_unknown_linux_ohos="$OHOS_NDK_HOME/llvm/bin/aarch64-unknown-linux-ohos-clang++"
export AR_aarch64_unknown_linux_ohos="$OHOS_NDK_HOME/llvm/bin/llvm-ar"

if [ -n "${LKM_OHOS_JAVA_HOME:-}" ]; then
    export JAVA_HOME="$LKM_OHOS_JAVA_HOME"
else
    for lkm_java_candidate in "$HOME"/.sdkman/candidates/java/21*; do
        if [ -x "$lkm_java_candidate/bin/java" ]; then
            export JAVA_HOME="$lkm_java_candidate"
        fi
    done
    unset lkm_java_candidate
fi

for lkm_tool_dir in "${JAVA_HOME:-/usr}/bin" "$DEVECO_NODE_HOME/bin" \
    "$DEVECO_SDK_HOME/default/openharmony/toolchains" \
    "$LKM_HARMONYOS_HOME/bin"; do
    case ":$PATH:" in
        *":$lkm_tool_dir:"*) ;;
        *) export PATH="$lkm_tool_dir:$PATH" ;;
    esac
done
unset lkm_tool_dir
