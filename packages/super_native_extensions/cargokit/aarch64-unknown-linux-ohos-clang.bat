@echo off

echo sdk home is %DEVECO_SDK_HOME%
set DEVECO_SDK_HOME_SHELL=%DEVECO_SDK_HOME:\=/%

set clangPath="%DEVECO_SDK_HOME_SHELL%/default/openharmony/native/llvm/bin/clang"
echo clangPath is %clangPath%

set sysrootPath="%DEVECO_SDK_HOME_SHELL%/default/openharmony/native/sysroot"
echo sysrootPath is %sysrootPath%

call %clangPath% -target aarch64-linux-ohos --sysroot=%sysrootPath% -D__MUSL__  %*