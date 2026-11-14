@echo off

SET "BASEDIR=%~dp0"
SET "BASEDIR=%BASEDIR:~0,-1%"

echo BASEDIR is %BASEDIR%


set TARGET_TEMP_DIR=.\target

set FLUTTER_ROOT=%FLUTTER_HOME%

set CARGOKIT_DARWIN_ARCHS=%ARCHS%
set CARGOKIT_CONFIGURATION=Debug
for %%i in ("%BASEDIR%\..\rust") do set "CARGOKIT_MANIFEST_DIR=%%~fi"

set CARGOKIT_TARGET_TEMP_DIR=%TARGET_TEMP_DIR%
set CARGOKIT_OUTPUT_DIR="%TARGET_TEMP_DIR%\out"
set CARGOKIT_TOOL_TEMP_DIR="%TARGET_TEMP_DIR%\build_tool"

for %%i in ("%BASEDIR%\..\..") do set CARGOKIT_ROOT_PROJECT_DIR=%%~fi


echo sdk home is %DEVECO_SDK_HOME%
set DEVECO_SDK_HOME_SHELL=%DEVECO_SDK_HOME:\=/%

for %%i in ("%BASEDIR%\..\cargokit\aarch64-unknown-linux-ohos-clang.bat") do set "CC_aarch64_unknown_linux_ohos=%%~fi"

set AR_aarch64_unknown_linux_ohos="%DEVECO_SDK_HOME_SHELL%/default/openharmony/native/llvm/bin/llvm-ar"
set CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER=%CC_aarch64_unknown_linux_ohos%
set CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_AR="%DEVECO_SDK_HOME_SHELL%/default/openharmony/native/llvm/bin/llvm-ar"

set CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_RUSTFLAGS=-L../ohos/cpp/code/build

@REM ohos sysroot
set PKG_CONFIG_SYSROOT_DIR=%DEVECO_SDK_HOME%\default\openharmony\native\llvm


echo "super--> cargo build start" &
"%BASEDIR%\run_build_tool.cmd" build-ohos %*
echo "super--> cargo build finished" &



