cmake_minimum_required(VERSION 3.5.0)
project(lanrdp)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

include_directories(
    ${NATIVERENDER_ROOT_PATH}
    ${NATIVERENDER_ROOT_PATH}/include
)

add_library(lanrdp SHARED napi_init.cpp)
target_link_libraries(lanrdp PUBLIC libace_napi.z.so)
