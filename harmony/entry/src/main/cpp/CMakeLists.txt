cmake_minimum_required(VERSION 3.5.0)
project(lanrdp)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})
set(OHOS_DEPS_ROOT "${NATIVERENDER_ROOT_PATH}/../../../../../.build/ohos" CACHE PATH "OHOS dependency prefix root")

if(OHOS_ARCH STREQUAL "x86_64")
    set(FREERDP_PREFIX "${OHOS_DEPS_ROOT}/prefix-freerdp-x86_64")
    set(OPENSSL_PREFIX "${OHOS_DEPS_ROOT}/prefix-x86_64")
    set(FFMPEG_PREFIX "${OHOS_DEPS_ROOT}/prefix-ffmpeg-arm64")
else()
    set(FREERDP_PREFIX "${OHOS_DEPS_ROOT}/prefix-freerdp-arm64-ffmpeg")
    set(OPENSSL_PREFIX "${OHOS_DEPS_ROOT}/prefix-arm64")
    set(FFMPEG_PREFIX "${OHOS_DEPS_ROOT}/prefix-ffmpeg-arm64")
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
    libace_ndk.z.so
    libpixelmap_ndk.z.so
    libnative_window.so
    libEGL.so
    libGLESv3.so
    libhilog_ndk.z.so
    -Wl,--start-group
    ${FREERDP_PREFIX}/lib/libfreerdp3.a
    -Wl,--whole-archive
    ${FREERDP_PREFIX}/lib/libfreerdp-client3.a
    -Wl,--no-whole-archive
    ${OHOS_DEPS_ROOT}/build-freerdp-arm64/channels/remdesk/common/libremdesk-common.a
    ${OHOS_DEPS_ROOT}/build-freerdp-arm64/channels/rdpsnd/common/librdpsnd-common.a
    ${FREERDP_PREFIX}/lib/libwinpr3.a
    ${OPENSSL_PREFIX}/lib/libssl.a
    ${OPENSSL_PREFIX}/lib/libcrypto.a
    -Wl,--end-group
    ${FFMPEG_PREFIX}/lib/libavcodec.so
    ${FFMPEG_PREFIX}/lib/libavutil.so
    ${FFMPEG_PREFIX}/lib/libswscale.so
    z
    dl
)

if(EXISTS "${OPENSSL_PREFIX}/lib/ossl-modules/legacy.so")
    add_custom_command(TARGET lanrdp POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${OPENSSL_PREFIX}/lib/ossl-modules/legacy.so"
            "$<TARGET_FILE_DIR:lanrdp>/legacy.so")
endif()

# Bundle the LGPL FFmpeg shared libraries next to liblanrdp.so so the HAP
# contains them. The linker records the SONAME (libavcodec.so.63 etc.).
add_custom_command(TARGET lanrdp POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${FFMPEG_PREFIX}/lib/libavcodec.so.63" "$<TARGET_FILE_DIR:lanrdp>/libavcodec.so.63"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${FFMPEG_PREFIX}/lib/libavutil.so.61" "$<TARGET_FILE_DIR:lanrdp>/libavutil.so.61"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${FFMPEG_PREFIX}/lib/libswscale.so.10" "$<TARGET_FILE_DIR:lanrdp>/libswscale.so.10")
