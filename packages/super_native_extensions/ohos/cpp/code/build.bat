@echo off

echo sdk home is %DEVECO_SDK_HOME%
set DEVECO_SDK_HOME_SHELL=%DEVECO_SDK_HOME:\=/%

set clangPath="%DEVECO_SDK_HOME_SHELL%/default/openharmony/native/llvm/bin/clang++"
echo clangPath is %clangPath%

set sysrootPath="%DEVECO_SDK_HOME_SHELL%/default/openharmony/native/sysroot"
echo sysrootPath is %sysrootPath%

%clangPath% DragDropHelper.cpp --shared -o libDragDropHelper.so -Wall -std=c++17 -target aarch64-linux-ohos --sysroot=%sysrootPath% -D__MUSL__  -lace_napi.z -lace_ndk.z -lnative_drawing -lpixelmap -ludmf

mkdir build
move /y .\libDragDropHelper.so build\
