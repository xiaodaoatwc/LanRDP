cmake_minimum_required(VERSION 3.5.0)
project(lanrdp)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})
set(OHOS_DEPS_ROOT "${NATIVERENDER_ROOT_PATH}/../../../../../.build/ohos" CACHE PATH "OHOS dependency prefix root")

if(OHOS_ARCH STREQUAL "x86_64")
    set(FREERDP_PREFIX "${OHOS_DEPS_ROOT}/prefix-freerdp-x86_64")
    set(OPENSSL_PREFIX "${OHOS_DEPS_ROOT}/prefix-x86_64")
else()
    set(FREERDP_PREFIX "${OHOS_DEPS_ROOT}/prefix-freerdp-arm64")
    set(OPENSSL_PREFIX "${OHOS_DEPS_ROOT}/prefix-arm64")
endif()

if(NOT EXISTS "${FREERDP_PREFIX}/lib/libfreerdp3.a")
    message(FATAL_ERROR "FreeRDP OHOS libraries not found at ${FREERDP_PREFIX}; build them first")
endif()

include_directories(
    ${NATIVERENDER_ROOT_PATH}
    ${NATIVERENDER_ROOT_PATH}/include
    ${FREERDP_PREFIX}/include/freerdp3
    ${FREERDP_PREFIX}/include/winpr3
    ${OPENSSL_PREFIX}/include
)

add_library(lanrdp SHARED napi_init.cpp)
target_link_libraries(lanrdp PUBLIC
    libace_napi.z.so
    -Wl,--start-group
    ${FREERDP_PREFIX}/lib/libfreerdp3.a
    ${FREERDP_PREFIX}/lib/libwinpr3.a
    ${OPENSSL_PREFIX}/lib/libssl.a
    ${OPENSSL_PREFIX}/lib/libcrypto.a
    -Wl,--end-group
    z
    dl
)
