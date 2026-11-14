cmake_minimum_required(VERSION 3.7.1)
 
project(DragDropHelper)
 
# find_package(LLVM REQUIRED CONFIG)
 
set(SOURCE_FILES DragDropHelper.cpp)
 
message(STATUS "This is BINARY dir " ${PROJECT_BINARY_DIR})
message(STATUS "This is SOURCE dir " ${PROJECT_SOURCE_DIR})
message(STATUS "Found LLVM ${LLVM_PACKAGE_VERSION}")
message(STATUS "Using LLVMConfig.cmake in: ${LLVM_DIR}")
 
# Set your project compile flags.
# E.g. if using the C++ header files
# you will need to enable C++11 support
# for your compiler.
 
include_directories(${LLVM_INCLUDE_DIRS})
add_definitions(${LLVM_DEFINITIONS})
 
# Now build our tools
add_library(DragDropHelper SHARED ${SOURCE_FILES})
 
 
# Find the libraries that correspond to the LLVM components
# that we wish to use
#llvm_map_components_to_libnames(llvm_libs support core irreader)
 
# Link against LLVM libraries
#target_link_libraries(ffrt_test ${llvm_libs})
target_link_libraries(DragDropHelper libace_napi.z.so)
target_link_libraries(DragDropHelper libace_ndk.z.so)
target_link_libraries(DragDropHelper libnative_drawing.so)
target_link_libraries(DragDropHelper libpixelmap.so)
target_link_libraries(DragDropHelper libudmf.so)
