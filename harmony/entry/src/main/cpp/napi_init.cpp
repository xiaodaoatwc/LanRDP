#include "napi/native_api.h"
#include <freerdp/freerdp.h>
#include <freerdp/version.h>
#include <freerdp/settings.h>
#include <freerdp/gdi/gdi.h>
#include <freerdp/input.h>
#include <ace/xcomponent/native_interface_xcomponent.h>
#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <native_window/external_window.h>
#include <hilog/log.h>
#include "multimedia/image_framework/image_pixel_map_mdk.h"
#include <freerdp/codec/color.h>
#include <winpr/synch.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <mutex>
#include <thread>
#include <vector>
#include <cstring>

#include <arpa/inet.h>
#include <fcntl.h>
#include <netdb.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>
#include <cerrno>
#include <cstdlib>

#include <string>

static napi_value Add(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    double value0 = 0;
    double value1 = 0;
    napi_get_value_double(env, args[0], &value0);
    napi_get_value_double(env, args[1], &value1);

    napi_value sum;
    napi_create_double(env, value0 + value1, &sum);
    return sum;
}

static napi_value Version(napi_env env, napi_callback_info info)
{
    napi_value value;
    napi_create_string_utf8(env, "0.1.0", NAPI_AUTO_LENGTH, &value);
    return value;
}

static napi_value FreeRDPVersion(napi_env env, napi_callback_info info)
{
    napi_value value;
    napi_create_string_utf8(env, freerdp_get_version_string(), NAPI_AUTO_LENGTH, &value);
    return value;
}


enum SessionState {
    SESSION_IDLE = 0,
    SESSION_CONNECTING = 1,
    SESSION_CONNECTED = 2,
    SESSION_DISCONNECTED = 3,
    SESSION_FAILED = 4
};

struct Session {
    freerdp* instance = nullptr;
    rdpContext* context = nullptr;
    std::thread thread;
    std::mutex mutex;
    std::vector<uint8_t> pixels;
    napi_env frameEnv = nullptr;
    napi_ref frontRef = nullptr;
    napi_ref backRef = nullptr;
    napi_ref extraRef = nullptr;
    NativePixelMap* frontNative = nullptr;
    NativePixelMap* backNative = nullptr;
    NativePixelMap* extraNative = nullptr;
    int frontStride = 0;
    int backStride = 0;
    int extraStride = 0;
    int frameIndex = 0;
    int writeIndex = 1;
    int displayIndex = 0;
    bool nativeBound = false;
    double nativeWriteMs = 0;
    bool pendingNativeFrame = false;
    bool hasNativeFrameTime = false;
    std::chrono::steady_clock::time_point lastNativeFrameTime;
    int width = 0;
    int height = 0;
    uint64_t version = 0;
    std::atomic<int> state{ SESSION_IDLE };
    std::string lastError;
    std::atomic<bool> stop{ false };
};

struct SessionContext {
    rdpContext context;
    Session* session;
};

static std::mutex g_sessionMutex;
static Session* g_session = nullptr;

static Session* SessionFromContext(rdpContext* context)
{
    auto* sessionContext = reinterpret_cast<SessionContext*>(context);
    return sessionContext ? sessionContext->session : nullptr;
}

static std::atomic<uint64_t> g_connectGeneration{ 0 };
static std::atomic<bool> g_xComponentActive{ false };
static std::atomic<uint64_t> g_xRenderedFrames{ 0 };
static std::atomic<uint64_t> g_xUploadedFrames{ 0 };

static void UnbindNativePixelMaps(Session* session, napi_env env = nullptr)
{
    if (!session)
        return;
    napi_env useEnv = env ? env : session->frameEnv;
    if (useEnv) {
        if (session->frontRef) {
            napi_delete_reference(useEnv, session->frontRef);
            session->frontRef = nullptr;
        }
        if (session->backRef) {
            napi_delete_reference(useEnv, session->backRef);
            session->backRef = nullptr;
        }
        if (session->extraRef) {
            napi_delete_reference(useEnv, session->extraRef);
            session->extraRef = nullptr;
        }
    }
    session->frontNative = nullptr;
    session->backNative = nullptr;
    session->extraNative = nullptr;
    session->frontStride = 0;
    session->backStride = 0;
    session->extraStride = 0;
    session->frameIndex = 0;
    session->writeIndex = 1;
    session->displayIndex = 0;
    session->pendingNativeFrame = false;
    session->hasNativeFrameTime = false;
    session->nativeBound = false;
}

static void SetSessionState(Session* session, int state, const std::string& error = {})
{
    if (!session)
        return;
    std::lock_guard<std::mutex> lock(session->mutex);
    session->state.store(state);
    session->lastError = error;
}

static BOOL SessionBeginPaint(rdpContext* context)
{
    (void)context;
    return TRUE;
}

static BOOL SessionEndPaint(rdpContext* context)
{
    Session* session = SessionFromContext(context);
    if (!session)
        return TRUE;

    rdpGdi* gdi = context->gdi;
    if (!gdi || !gdi->primary_buffer || gdi->width <= 0 || gdi->height <= 0)
        return TRUE;

    const int width = gdi->width;
    const int height = gdi->height;
    const UINT32 stride = gdi->stride;
    const UINT32 format = gdi->dstFormat;
    if (stride < static_cast<UINT32>(width * 4))
        return TRUE;

    const BYTE* source = gdi->primary_buffer;
    std::lock_guard<std::mutex> lock(session->mutex);
    session->width = width;
    session->height = height;
    if (g_xComponentActive.load() || session->nativeBound) {
        session->pendingNativeFrame = true;
        return TRUE;
    }

    session->pixels.resize(static_cast<size_t>(width) * height * 4);
    const BOOL converted = freerdp_image_copy(
        session->pixels.data(), PIXEL_FORMAT_BGRA32, static_cast<UINT32>(width * 4),
        0, 0, static_cast<UINT32>(width), static_cast<UINT32>(height),
        source, format, stride, 0, 0, nullptr, FREERDP_FLIP_NONE);
    if (!converted)
        return TRUE;
    ++session->version;
    return TRUE;
}

static void FlushNativeFrame(Session* session)
{
    if (!session)
        return;
    std::lock_guard<std::mutex> lock(session->mutex);
    if (!session->nativeBound || !session->pendingNativeFrame) {
        return;
    }
    const auto now = std::chrono::steady_clock::now();
    const int frameIntervalMs = g_xComponentActive.load() ? 16 : 8;
    if (session->hasNativeFrameTime &&
        std::chrono::duration_cast<std::chrono::milliseconds>(now - session->lastNativeFrameTime).count() < frameIntervalMs) {
        return;
    }
    SessionContext* sessionContext = reinterpret_cast<SessionContext*>(session->context);
    rdpContext* context = sessionContext ? &sessionContext->context : session->context;
    rdpGdi* gdi = context ? context->gdi : nullptr;
    if (!gdi || !gdi->primary_buffer || gdi->width <= 0 || gdi->height <= 0) {
        return;
    }
    const int width = gdi->width;
    const int height = gdi->height;
    const UINT32 stride = gdi->stride;
    const UINT32 format = gdi->dstFormat;
    if (session->width != width || session->height != height || stride < static_cast<UINT32>(width * 4)) {
        return;
    }
    if (g_xComponentActive.load()) {
        const auto writeStart = std::chrono::steady_clock::now();
        session->pixels.resize(static_cast<size_t>(width) * height * 4);
        const BOOL copied = freerdp_image_copy(
            session->pixels.data(), PIXEL_FORMAT_BGRA32, static_cast<UINT32>(width * 4),
            0, 0, static_cast<UINT32>(width), static_cast<UINT32>(height),
            gdi->primary_buffer, format, stride, 0, 0, nullptr, FREERDP_FLIP_NONE);
        const auto writeEnd = std::chrono::steady_clock::now();
        session->nativeWriteMs = std::chrono::duration<double, std::milli>(writeEnd - writeStart).count();
        if (copied) {
            session->pendingNativeFrame = false;
            session->hasNativeFrameTime = true;
            session->lastNativeFrameTime = writeEnd;
            ++session->version;
        }
        return;
    }
    int targetIndex = -1;
    for (int i = 0; i < 3; ++i) {
        if (i != session->displayIndex && i != session->frameIndex) {
            targetIndex = i;
            break;
        }
    }
    if (targetIndex < 0) {
        targetIndex = (session->displayIndex + 1) % 3;
    }
    NativePixelMap* target = targetIndex == 0 ? session->frontNative :
        (targetIndex == 1 ? session->backNative : session->extraNative);
    const int targetStride = targetIndex == 0 ? session->frontStride :
        (targetIndex == 1 ? session->backStride : session->extraStride);
    if (!target || targetStride < width * 4) {
        return;
    }
    void* targetPixels = nullptr;
    if (OH_PixelMap_AccessPixels(target, &targetPixels) != 0 || !targetPixels) {
        return;
    }
    const auto writeStart = std::chrono::steady_clock::now();
    const BOOL copied = freerdp_image_copy(
        static_cast<BYTE*>(targetPixels), PIXEL_FORMAT_BGRA32,
        static_cast<UINT32>(targetStride),
        0, 0, static_cast<UINT32>(width), static_cast<UINT32>(height),
        gdi->primary_buffer, format, stride, 0, 0, nullptr, FREERDP_FLIP_NONE);
    OH_PixelMap_UnAccessPixels(target);
    const auto writeEnd = std::chrono::steady_clock::now();
    session->nativeWriteMs = std::chrono::duration<double, std::milli>(writeEnd - writeStart).count();
    if (!copied) {
        return;
    }
    session->frameIndex = targetIndex;
    session->pendingNativeFrame = false;
    session->hasNativeFrameTime = true;
    session->lastNativeFrameTime = writeEnd;
    ++session->version;
}

static BOOL SessionDesktopResize(rdpContext* context)
{
    (void)context;
    return TRUE;
}

static void SessionLoop(Session* session)
{
    HANDLE handles[64];
    while (!session->stop.load()) {
        DWORD count = freerdp_get_event_handles(session->context, handles, 64);
        if (count == 0)
            break;
        DWORD status = WaitForMultipleObjects(count, handles, FALSE, 8);
        if (status == WAIT_FAILED)
            break;
        if (status != WAIT_TIMEOUT) {
            if (!freerdp_check_event_handles(session->context))
                break;
        }
        FlushNativeFrame(session);
    }

    if (!session->stop.load()) {
        std::string message = "连接已断开";
        if (session->context) {
            const UINT32 code = freerdp_get_last_error(session->context);
            const char* text = freerdp_get_last_error_string(code);
            if (text && *text)
                message = text;
        }
        SetSessionState(session, SESSION_DISCONNECTED, message);
    }
}

static void DestroySession(Session* session)
{
    if (!session)
        return;
    session->stop.store(true);
    if (session->instance && session->context)
        freerdp_abort_connect_context(session->context);
    if (session->thread.joinable())
        session->thread.join();
    SetSessionState(session, SESSION_IDLE);
    if (session->instance) {
        freerdp_disconnect(session->instance);
        if (session->instance->context && session->instance->context->gdi)
            gdi_free(session->instance);
        freerdp_context_free(session->instance);
        freerdp_free(session->instance);
    }
    delete session;
}

static BOOL SessionPostConnect(freerdp* instance)
{
    if (!instance || !instance->context)
        return FALSE;
    if (!gdi_init(instance, PIXEL_FORMAT_BGRA32))
        return FALSE;
    instance->context->update->BeginPaint = SessionBeginPaint;
    instance->context->update->EndPaint = SessionEndPaint;
    instance->context->update->DesktopResize = SessionDesktopResize;
    return TRUE;
}


static bool ProbeTcp(const std::string& host, uint32_t port, std::string& error)
{
    struct addrinfo hints = {};
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;

    struct addrinfo* result = nullptr;
    const std::string service = std::to_string(port);
    if (getaddrinfo(host.c_str(), service.c_str(), &hints, &result) != 0 || !result) {
        error = "DNS failed";
        return false;
    }

    bool success = false;
    for (struct addrinfo* ai = result; ai && !success; ai = ai->ai_next) {
        int fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
        if (fd < 0) {
            error = "socket failed " + std::to_string(errno);
            continue;
        }
        const int flags = fcntl(fd, F_GETFL, 0);
        fcntl(fd, F_SETFL, flags | O_NONBLOCK);
        int rc = connect(fd, ai->ai_addr, ai->ai_addrlen);
        if (rc < 0 && errno == EINPROGRESS) {
            struct pollfd pfd = { fd, POLLOUT, 0 };
            rc = poll(&pfd, 1, 8000);
            if (rc > 0) {
                int socketError = 0;
                socklen_t len = sizeof(socketError);
                getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &len);
                success = socketError == 0;
                if (!success)
                    error = "TCP error " + std::to_string(socketError);
            } else {
                error = "TCP timeout";
            }
        } else if (rc == 0) {
            success = true;
        } else {
            error = "TCP error " + std::to_string(errno);
        }
        close(fd);
    }
    freeaddrinfo(result);
    return success;
}

static bool StartSession(Session* session, const std::string& host, uint32_t port,
                         const std::string& username, const std::string& password,
                         const std::string& domain, uint32_t desktopWidth,
                         uint32_t desktopHeight, uint32_t desktopScale,
                         uint32_t deviceScale, std::string& error)
{
    SetSessionState(session, SESSION_CONNECTING);
    if (!ProbeTcp(host, port, error)) {
        SetSessionState(session, SESSION_FAILED, error);
        return false;
    }

#if defined(__aarch64__)
    setenv("OPENSSL_MODULES", "/data/storage/el1/bundle/libs/arm64", 1);
#else
    setenv("OPENSSL_MODULES", "/data/storage/el1/bundle/libs/x86_64", 1);
#endif

    freerdp* instance = freerdp_new();
    if (!instance) {
        error = "freerdp_new failed";
        SetSessionState(session, SESSION_FAILED, error);
        return false;
    }

    instance->ContextSize = sizeof(SessionContext);
    if (!freerdp_context_new(instance)) {
        error = "freerdp_context_new failed";
        freerdp_free(instance);
        SetSessionState(session, SESSION_FAILED, error);
        return false;
    }

    auto* sessionContext = reinterpret_cast<SessionContext*>(instance->context);
    sessionContext->session = session;
    session->instance = instance;
    session->context = instance->context;

    rdpSettings* settings = instance->context->settings;
    freerdp_settings_set_string(settings, FreeRDP_ServerHostname, host.c_str());
    freerdp_settings_set_uint32(settings, FreeRDP_ServerPort, port);
    freerdp_settings_set_string(settings, FreeRDP_Username, username.c_str());
    freerdp_settings_set_string(settings, FreeRDP_Password, password.c_str());
    if (!domain.empty())
        freerdp_settings_set_string(settings, FreeRDP_Domain, domain.c_str());
    freerdp_settings_set_bool(settings, FreeRDP_IgnoreCertificate, TRUE);
    freerdp_settings_set_bool(settings, FreeRDP_NetworkAutoDetect, TRUE);
    freerdp_settings_set_bool(settings, FreeRDP_SupportGraphicsPipeline, TRUE);
    freerdp_settings_set_bool(settings, FreeRDP_GfxProgressive, TRUE);
    freerdp_settings_set_bool(settings, FreeRDP_GfxProgressiveV2, TRUE);
    freerdp_settings_set_bool(settings, FreeRDP_GfxH264, FALSE);
    freerdp_settings_set_bool(settings, FreeRDP_GfxAVC444, FALSE);
    freerdp_settings_set_bool(settings, FreeRDP_GfxCodecAV1, FALSE);
    freerdp_settings_set_bool(settings, FreeRDP_RemoteFxCodec, TRUE);
    freerdp_settings_set_uint32(settings, FreeRDP_TcpConnectTimeout, 15000);
    const uint32_t width = (desktopWidth >= 640 && desktopWidth <= 4096) ? desktopWidth : 1024;
    const uint32_t height = (desktopHeight >= 480 && desktopHeight <= 4096) ? desktopHeight : 768;
    freerdp_settings_set_uint32(settings, FreeRDP_DesktopWidth, width);
    freerdp_settings_set_uint32(settings, FreeRDP_DesktopHeight, height);
    if (desktopScale >= 100 && desktopScale <= 500)
        freerdp_settings_set_uint32(settings, FreeRDP_DesktopScaleFactor, desktopScale);
    if (deviceScale == 100 || deviceScale == 140 || deviceScale == 180)
        freerdp_settings_set_uint32(settings, FreeRDP_DeviceScaleFactor, deviceScale);

    instance->PostConnect = SessionPostConnect;

    if (!freerdp_connect(instance)) {
        UINT32 code = freerdp_get_last_error(instance->context);
        const char* name = freerdp_get_last_error_name(code);
        const char* text = freerdp_get_last_error_string(code);
        error = "RDP " + std::to_string(code) + " " + (name ? name : "") + " " + (text ? text : "");
        SetSessionState(session, SESSION_FAILED, error);
        return false;
    }

    SetSessionState(session, SESSION_CONNECTED);
    session->thread = std::thread(SessionLoop, session);
    return true;
}

struct ConnectWork {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::string host;
    std::string username;
    std::string password;
    std::string domain;
    uint32_t port = 3389;
    uint32_t width = 1024;
    uint32_t height = 768;
    uint32_t desktopScale = 100;
    uint32_t deviceScale = 100;
    uint64_t generation = 0;
    bool connected = false;
    std::string error;
};

static std::string GetString(napi_env env, napi_value value)
{
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok)
        return {};
    std::string result(length, '\0');
    if (length > 0)
        napi_get_value_string_utf8(env, value, result.data(), length + 1, &length);
    result.resize(length);
    return result;
}

static void ExecuteConnect(napi_env env, void* data)
{
    auto* work = static_cast<ConnectWork*>(data);
    auto* session = new Session();
    if (StartSession(session, work->host, work->port, work->username, work->password, work->domain,
                     work->width, work->height, work->desktopScale, work->deviceScale, work->error)) {
        std::lock_guard<std::mutex> lock(g_sessionMutex);
        if (work->generation != g_connectGeneration.load()) {
            work->error = "cancelled";
            work->connected = false;
            DestroySession(session);
            return;
        }
        if (g_session)
            DestroySession(g_session);
        g_session = session;
        work->connected = true;
    } else {
        DestroySession(session);
    }
}

static void CompleteConnect(napi_env env, napi_status status, void* data)
{
    auto* work = static_cast<ConnectWork*>(data);
    napi_value result;
    std::string text = work->connected ? "connected" : ("failed: " + work->error);
    napi_create_string_utf8(env, text.c_str(), NAPI_AUTO_LENGTH, &result);

    if (status == napi_ok)
        napi_resolve_deferred(env, work->deferred, result);
    else
        napi_reject_deferred(env, work->deferred, result);

    napi_delete_async_work(env, work->work);
    delete work;
}

static napi_value Connect(napi_env env, napi_callback_info info)
{
    size_t argc = 9;
    napi_value args[9] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    napi_value promise;
    auto* work = new ConnectWork();
    napi_create_promise(env, &work->deferred, &promise);

    if (argc >= 5) {
        work->host = GetString(env, args[0]);
        int32_t port = 3389;
        napi_get_value_int32(env, args[1], &port);
        work->port = port > 0 && port <= 65535 ? static_cast<uint32_t>(port) : 3389;
        work->username = GetString(env, args[2]);
        work->password = GetString(env, args[3]);
        work->domain = GetString(env, args[4]);
        int32_t width = 1024;
        int32_t height = 768;
        if (argc >= 7) {
            napi_get_value_int32(env, args[5], &width);
            napi_get_value_int32(env, args[6], &height);
        }
        work->width = width > 0 ? static_cast<uint32_t>(width) : 1024;
        work->height = height > 0 ? static_cast<uint32_t>(height) : 768;
        int32_t desktopScale = 100;
        int32_t deviceScale = 100;
        if (argc >= 9) {
            napi_get_value_int32(env, args[7], &desktopScale);
            napi_get_value_int32(env, args[8], &deviceScale);
        }
        work->desktopScale = desktopScale > 0 ? static_cast<uint32_t>(desktopScale) : 100;
        work->deviceScale = deviceScale > 0 ? static_cast<uint32_t>(deviceScale) : 100;
    }

    napi_value resourceName;
    work->generation = ++g_connectGeneration;
    napi_create_string_utf8(env, "LanRDPConnect", NAPI_AUTO_LENGTH, &resourceName);
    napi_create_async_work(env, nullptr, resourceName, ExecuteConnect, CompleteConnect, work, &work->work);
    napi_queue_async_work(env, work->work);
    return promise;
}

static napi_value StopSession(napi_env env, napi_callback_info info)
{
    ++g_connectGeneration;
    std::lock_guard<std::mutex> lock(g_sessionMutex);
    if (g_session) {
        DestroySession(g_session);
        g_session = nullptr;
    }
    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}

static napi_value GetSessionInfo(napi_env env, napi_callback_info info)
{
    std::lock_guard<std::mutex> lock(g_sessionMutex);
    int state = SESSION_IDLE;
    std::string error;
    uint64_t version = 0;
    int width = 0;
    int height = 0;
    int frameIndex = 0;
    bool nativeBound = false;
    double nativeWriteMs = 0;
    if (g_session) {
        std::lock_guard<std::mutex> frameLock(g_session->mutex);
        state = g_session->state.load();
        error = g_session->lastError;
        version = g_session->version;
        width = g_session->width;
        height = g_session->height;
        frameIndex = g_session->frameIndex;
        nativeBound = g_session->nativeBound;
        nativeWriteMs = g_session->nativeWriteMs;
    }

    napi_value object;
    napi_value jsState;
    napi_value jsError;
    napi_value jsVersion;
    napi_value jsWidth;
    napi_value jsHeight;
    napi_value jsFrameIndex;
    napi_value jsNativeBound;
    napi_value jsNativeWriteMs;
    napi_create_object(env, &object);
    napi_create_int32(env, state, &jsState);
    napi_create_string_utf8(env, error.c_str(), NAPI_AUTO_LENGTH, &jsError);
    napi_create_double(env, static_cast<double>(version), &jsVersion);
    napi_create_int32(env, width, &jsWidth);
    napi_create_int32(env, height, &jsHeight);
    napi_create_int32(env, frameIndex, &jsFrameIndex);
    napi_get_boolean(env, nativeBound, &jsNativeBound);
    napi_create_double(env, nativeWriteMs, &jsNativeWriteMs);
    napi_set_named_property(env, object, "state", jsState);
    napi_set_named_property(env, object, "error", jsError);
    napi_set_named_property(env, object, "version", jsVersion);
    napi_set_named_property(env, object, "width", jsWidth);
    napi_set_named_property(env, object, "height", jsHeight);
    napi_set_named_property(env, object, "frameIndex", jsFrameIndex);
    napi_set_named_property(env, object, "nativeBound", jsNativeBound);
    napi_set_named_property(env, object, "nativeWriteMs", jsNativeWriteMs);
    return object;
}

static napi_value BindFrameMaps(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3] = {nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    napi_value result;
    napi_get_boolean(env, false, &result);
    if (argc < 3) {
        return result;
    }

    std::lock_guard<std::mutex> lock(g_sessionMutex);
    Session* session = g_session;
    if (!session) {
        return result;
    }

    NativePixelMap* front = OH_PixelMap_InitNativePixelMap(env, args[0]);
    NativePixelMap* back = OH_PixelMap_InitNativePixelMap(env, args[1]);
    NativePixelMap* extra = OH_PixelMap_InitNativePixelMap(env, args[2]);
    if (!front || !back || !extra) {
        return result;
    }
    OhosPixelMapInfos frontInfo = {};
    OhosPixelMapInfos backInfo = {};
    OhosPixelMapInfos extraInfo = {};
    int32_t frontStride = 0;
    int32_t backStride = 0;
    int32_t extraStride = 0;
    if (OH_PixelMap_GetImageInfo(front, &frontInfo) != 0 ||
        OH_PixelMap_GetImageInfo(back, &backInfo) != 0 ||
        OH_PixelMap_GetImageInfo(extra, &extraInfo) != 0 ||
        OH_PixelMap_GetBytesNumberPerRow(front, &frontStride) != 0 ||
        OH_PixelMap_GetBytesNumberPerRow(back, &backStride) != 0 ||
        OH_PixelMap_GetBytesNumberPerRow(extra, &extraStride) != 0) {
        return result;
    }
    if (frontInfo.width <= 0 || frontInfo.height <= 0 ||
        frontInfo.width != backInfo.width || frontInfo.height != backInfo.height ||
        frontInfo.width != extraInfo.width || frontInfo.height != extraInfo.height ||
        frontStride < static_cast<int32_t>(frontInfo.width * 4) ||
        backStride < static_cast<int32_t>(frontInfo.width * 4) ||
        extraStride < static_cast<int32_t>(frontInfo.width * 4)) {
        return result;
    }

    std::lock_guard<std::mutex> frameLock(session->mutex);
    UnbindNativePixelMaps(session, env);
    if (napi_create_reference(env, args[0], 1, &session->frontRef) != napi_ok ||
        napi_create_reference(env, args[1], 1, &session->backRef) != napi_ok ||
        napi_create_reference(env, args[2], 1, &session->extraRef) != napi_ok) {
        UnbindNativePixelMaps(session, env);
        return result;
    }
    session->frameEnv = env;
    session->frontNative = front;
    session->backNative = back;
    session->extraNative = extra;
    session->frontStride = frontStride;
    session->backStride = backStride;
    session->extraStride = extraStride;
    session->frameIndex = 0;
    session->writeIndex = 1;
    session->displayIndex = 0;
    session->pendingNativeFrame = false;
    session->hasNativeFrameTime = false;
    session->nativeBound = true;
    napi_get_boolean(env, true, &result);
    return result;
}

static napi_value AckFrame(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t index = -1;
    if (argc >= 1) {
        napi_get_value_int32(env, args[0], &index);
    }
    napi_value result;
    napi_get_boolean(env, false, &result);
    if (index < 0 || index > 1) {
        return result;
    }
    std::lock_guard<std::mutex> lock(g_sessionMutex);
    Session* session = g_session;
    if (session) {
        std::lock_guard<std::mutex> frameLock(session->mutex);
        if (session->nativeBound) {
            session->displayIndex = index;
            napi_get_boolean(env, true, &result);
        }
    }
    return result;
}

static napi_value UnbindFrameMaps(napi_env env, napi_callback_info info)
{
    (void)info;
    napi_value result;
    napi_get_boolean(env, true, &result);
    std::lock_guard<std::mutex> lock(g_sessionMutex);
    Session* session = g_session;
    if (session) {
        std::lock_guard<std::mutex> frameLock(session->mutex);
        UnbindNativePixelMaps(session, env);
    }
    return result;
}

static napi_value GetFrame(napi_env env, napi_callback_info info)
{
    std::lock_guard<std::mutex> lock(g_sessionMutex);
    Session* session = g_session;
    napi_value result;
    napi_get_null(env, &result);
    if (!session)
        return result;

    std::lock_guard<std::mutex> frameLock(session->mutex);
    if (session->pixels.empty() || session->width <= 0 || session->height <= 0)
        return result;

    size_t size = session->pixels.size();
    void* data = nullptr;
    napi_value buffer;
    if (napi_create_arraybuffer(env, size, &data, &buffer) != napi_ok)
        return result;
    std::memcpy(data, session->pixels.data(), size);

    napi_value width, height, version, object;
    napi_create_int32(env, session->width, &width);
    napi_create_int32(env, session->height, &height);
    napi_create_double(env, static_cast<double>(session->version), &version);
    napi_create_object(env, &object);
    napi_set_named_property(env, object, "width", width);
    napi_set_named_property(env, object, "height", height);
    napi_set_named_property(env, object, "version", version);
    napi_set_named_property(env, object, "data", buffer);
    return object;
}


static napi_value SendMouse(napi_env env, napi_callback_info info)
{
    size_t argc = 4;
    napi_value args[4] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int32_t x = 0;
    int32_t y = 0;
    int32_t button = 0;
    bool down = false;
    if (argc >= 4) {
        napi_get_value_int32(env, args[0], &x);
        napi_get_value_int32(env, args[1], &y);
        napi_get_value_int32(env, args[2], &button);
        napi_get_value_bool(env, args[3], &down);
    }

    std::lock_guard<std::mutex> lock(g_sessionMutex);
    bool sent = false;
    if (g_session && g_session->context && g_session->context->input) {
        rdpInput* input = g_session->context->input;
        UINT16 flags = 0;
        if (button <= 0) {
            flags = PTR_FLAGS_MOVE;
        } else {
            switch (button) {
                case 2: flags = PTR_FLAGS_BUTTON2; break;
                case 3: flags = PTR_FLAGS_BUTTON3; break;
                case 1:
                default: flags = PTR_FLAGS_BUTTON1; break;
            }
            if (down)
                flags |= PTR_FLAGS_DOWN;
        }

        const int width = g_session->width > 0 ? g_session->width : 1024;
        const int height = g_session->height > 0 ? g_session->height : 768;
        if (x < 0) x = 0;
        if (y < 0) y = 0;
        if (x >= width) x = width - 1;
        if (y >= height) y = height - 1;
        if (button > 0 && down)
            freerdp_input_send_mouse_event(input, PTR_FLAGS_MOVE, static_cast<UINT16>(x),
                                           static_cast<UINT16>(y));
        sent = freerdp_input_send_mouse_event(input, flags, static_cast<UINT16>(x),
                                              static_cast<UINT16>(y));
    }

    napi_value result;
    napi_get_boolean(env, sent, &result);
    return result;
}


static napi_value SendWheel(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t delta = 120;
    if (argc >= 1)
        napi_get_value_int32(env, args[0], &delta);

    std::lock_guard<std::mutex> lock(g_sessionMutex);
    bool sent = false;
    if (g_session && g_session->context && g_session->context->input) {
        UINT16 flags = PTR_FLAGS_WHEEL;
        if (delta < 0)
            flags |= PTR_FLAGS_WHEEL_NEGATIVE;
        const int magnitude = delta < 0 ? -delta : delta;
        flags |= static_cast<UINT16>(magnitude > 0xFF ? 0xFF : magnitude);
        sent = freerdp_input_send_mouse_event(g_session->context->input, flags, 0, 0);
    }
    napi_value result;
    napi_get_boolean(env, sent, &result);
    return result;
}

static napi_value SendUnicode(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t code = 0;
    bool down = false;
    if (argc >= 2) {
        napi_get_value_int32(env, args[0], &code);
        napi_get_value_bool(env, args[1], &down);
    }

    std::lock_guard<std::mutex> lock(g_sessionMutex);
    bool sent = false;
    if (g_session && g_session->context && g_session->context->input) {
        sent = freerdp_input_send_unicode_keyboard_event(
            g_session->context->input,
            down ? 0 : KBD_FLAGS_RELEASE,
            static_cast<UINT16>(code));
    }
    napi_value result;
    napi_get_boolean(env, sent, &result);
    return result;
}


static napi_value SendKey(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t code = 0;
    bool down = false;
    bool extended = false;
    if (argc >= 3) {
        napi_get_value_int32(env, args[0], &code);
        napi_get_value_bool(env, args[1], &down);
        napi_get_value_bool(env, args[2], &extended);
    }

    std::lock_guard<std::mutex> lock(g_sessionMutex);
    bool sent = false;
    if (g_session && g_session->context && g_session->context->input) {
        UINT16 flags = down ? 0 : KBD_FLAGS_RELEASE;
        if (extended)
            flags |= KBD_FLAGS_EXTENDED;
        sent = freerdp_input_send_keyboard_event(g_session->context->input, flags,
                                                 static_cast<UINT8>(code));
    }
    napi_value result;
    napi_get_boolean(env, sent, &result);
    return result;
}


static napi_value SendMouseMove(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t x = 0;
    int32_t y = 0;
    int32_t button = 0;
    if (argc >= 3) {
        napi_get_value_int32(env, args[0], &x);
        napi_get_value_int32(env, args[1], &y);
        napi_get_value_int32(env, args[2], &button);
    }

    std::lock_guard<std::mutex> lock(g_sessionMutex);
    bool sent = false;
    if (g_session && g_session->context && g_session->context->input) {
        UINT16 flags = PTR_FLAGS_MOVE;
        switch (button) {
            case 2: flags |= PTR_FLAGS_BUTTON2; break;
            case 3: flags |= PTR_FLAGS_BUTTON3; break;
            case 1: flags |= PTR_FLAGS_BUTTON1; break;
            default: break;
        }
        const int width = g_session->width > 0 ? g_session->width : 1024;
        const int height = g_session->height > 0 ? g_session->height : 768;
        if (x < 0) x = 0;
        if (y < 0) y = 0;
        if (x >= width) x = width - 1;
        if (y >= height) y = height - 1;
        sent = freerdp_input_send_mouse_event(g_session->context->input, flags,
                                              static_cast<UINT16>(x), static_cast<UINT16>(y));
    }
    napi_value result;
    napi_get_boolean(env, sent, &result);
    return result;
}

static std::atomic<float> g_xViewScale{ 1.0f };
static std::atomic<float> g_xOffsetX{ 0.0f };
static std::atomic<float> g_xOffsetY{ 0.0f };

static GLuint CompileShader(GLenum type, const char* source)
{
    GLuint shader = glCreateShader(type);
    glShaderSource(shader, 1, &source, nullptr);
    glCompileShader(shader);
    GLint compiled = 0;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &compiled);
    if (!compiled) {
        char info[512] = {0};
        GLsizei length = 0;
        glGetShaderInfoLog(shader, sizeof(info) - 1, &length, info);
        OH_LOG_Print(LOG_APP, LOG_ERROR, 0xFF00, "LanRDPX", "shader: %{public}s", info);
        glDeleteShader(shader);
        return 0;
    }
    return shader;
}

struct XTestRenderer {
    std::atomic<bool> running{ false };
    std::atomic<int> width{ 1280 };
    std::atomic<int> height{ 800 };
    std::thread thread;
    GLuint program = 0;
    GLuint texture = 0;
    GLuint vbo = 0;
    GLuint vao = 0;
    GLint textureUniform = -1;
    GLint quadUniform = -1;
    int textureWidth = 0;
    int textureHeight = 0;
    uint64_t textureVersion = 0;

    void ResetGlState()
    {
        program = 0;
        texture = 0;
        vbo = 0;
        vao = 0;
        textureUniform = -1;
        quadUniform = -1;
        textureWidth = 0;
        textureHeight = 0;
        textureVersion = 0;
    }

    void Start(void* window)
    {
        Stop();
        ResetGlState();
        running.store(true);
        thread = std::thread(&XTestRenderer::RenderLoop, this, window);
    }

    void Stop()
    {
        running.store(false);
        if (thread.joinable()) {
            thread.join();
        }
        ResetGlState();
    }

    void SetSize(int w, int h)
    {
        if (w > 0 && h > 0) {
            width.store(w);
            height.store(h);
        }
    }

    GLuint CreateProgram()
    {
        static const char* vertexSource =
            "attribute vec2 aPos;\n"
            "void main() {\n"
            "  gl_Position = vec4(aPos, 0.0, 1.0);\n"
            "}\n";
        static const char* fragmentSource =
            "precision mediump float;\n"
            "uniform sampler2D uTexture;\n"
            "uniform vec4 uQuad;\n"
            "void main() {\n"
            "  vec2 uv = vec2((gl_FragCoord.x - uQuad.x) / uQuad.z,\n"
            "                 1.0 - (gl_FragCoord.y - uQuad.y) / uQuad.w);\n"
            "  vec4 color = texture2D(uTexture, uv);\n"
            "  gl_FragColor = vec4(color.b, color.g, color.r, color.a);\n"
            "}\n";
        GLuint vs = CompileShader(GL_VERTEX_SHADER, vertexSource);
        GLuint fs = CompileShader(GL_FRAGMENT_SHADER, fragmentSource);
        if (!vs || !fs) {
            if (vs) glDeleteShader(vs);
            if (fs) glDeleteShader(fs);
            return 0;
        }
        GLuint prog = glCreateProgram();
        glAttachShader(prog, vs);
        glAttachShader(prog, fs);
        glBindAttribLocation(prog, 0, "aPos");
        glLinkProgram(prog);
        glDeleteShader(vs);
        glDeleteShader(fs);
        GLint linked = 0;
        glGetProgramiv(prog, GL_LINK_STATUS, &linked);
        if (!linked) {
            char info[512] = {0};
            GLsizei length = 0;
            glGetProgramInfoLog(prog, sizeof(info) - 1, &length, info);
            OH_LOG_Print(LOG_APP, LOG_ERROR, 0xFF00, "LanRDPX", "program: %{public}s", info);
            glDeleteProgram(prog);
            return 0;
        }
        return prog;
    }

    void UploadTexture(const uint8_t* data, int frameWidth, int frameHeight, uint64_t version)
    {
        if (!texture) {
            glGenTextures(1, &texture);
        }
        glBindTexture(GL_TEXTURE_2D, texture);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        if (frameWidth != textureWidth || frameHeight != textureHeight) {
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, frameWidth, frameHeight, 0,
                         GL_RGBA, GL_UNSIGNED_BYTE, data);
            textureWidth = frameWidth;
            textureHeight = frameHeight;
        } else {
            glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, frameWidth, frameHeight,
                            GL_RGBA, GL_UNSIGNED_BYTE, data);
        }
        textureVersion = version;
        g_xUploadedFrames.fetch_add(1);
    }

    void RenderLoop(void* window)
    {
        EGLDisplay display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
        if (display == EGL_NO_DISPLAY) return;
        if (!eglInitialize(display, nullptr, nullptr)) return;
        const EGLint configAttribs[] = {
            EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
            EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
            EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
            EGL_NONE
        };
        EGLConfig config = nullptr;
        EGLint numConfigs = 0;
        if (!eglChooseConfig(display, configAttribs, &config, 1, &numConfigs) || numConfigs < 1) {
            eglTerminate(display);
            return;
        }
        EGLSurface surface = eglCreateWindowSurface(display, config,
            reinterpret_cast<EGLNativeWindowType>(window), nullptr);
        if (surface == EGL_NO_SURFACE) {
            eglTerminate(display);
            return;
        }
        const EGLint contextAttribs[] = { EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE };
        EGLContext context = eglCreateContext(display, config, EGL_NO_CONTEXT, contextAttribs);
        if (context == EGL_NO_CONTEXT) {
            eglDestroySurface(display, surface);
            eglTerminate(display);
            return;
        }
        if (!eglMakeCurrent(display, surface, surface, context)) {
            eglDestroyContext(display, context);
            eglDestroySurface(display, surface);
            eglTerminate(display);
            return;
        }
        eglSwapInterval(display, 1);
        OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "LanRDPX", "GL=%{public}s",
            reinterpret_cast<const char*>(glGetString(GL_VERSION)));
        program = CreateProgram();
        if (!program) {
            OH_LOG_Print(LOG_APP, LOG_ERROR, 0xFF00, "LanRDPX", "shader program failed");
            eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
            eglDestroyContext(display, context);
            eglDestroySurface(display, surface);
            eglTerminate(display);
            return;
        }
        textureUniform = glGetUniformLocation(program, "uTexture");
        quadUniform = glGetUniformLocation(program, "uQuad");
        glGenVertexArrays(1, &vao);
        glBindVertexArray(vao);
        glGenBuffers(1, &vbo);
        glUseProgram(program);
        glUniform1i(textureUniform, 0);
        OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "LanRDPX", "renderer ready");
        bool force_draw = true;
        float last_scale = -1.0f;
        float last_offset_x = 0.0f;
        float last_offset_y = 0.0f;
        int last_width = 0;
        int last_height = 0;

        while (running.load()) {
            const int w = width.load();
            const int h = height.load();
            if (w <= 0 || h <= 0) {
                std::this_thread::sleep_for(std::chrono::milliseconds(16));
                continue;
            }
            int frameWidth = 0;
            int frameHeight = 0;
            bool uploaded = false;
            {
                std::lock_guard<std::mutex> sessionLock(g_sessionMutex);
                Session* session = g_session;
                if (session) {
                    std::lock_guard<std::mutex> frameLock(session->mutex);
                    frameWidth = session->width;
                    frameHeight = session->height;
                    if (!session->pixels.empty() && session->version != textureVersion &&
                        frameWidth > 0 && frameHeight > 0) {
                        UploadTexture(session->pixels.data(), frameWidth, frameHeight, session->version);
                        uploaded = true;
                    }
                }
            }

            const float scale = g_xViewScale.load();
            const float offsetX = g_xOffsetX.load();
            const float offsetY = g_xOffsetY.load();
            const bool changed = force_draw || uploaded || w != last_width || h != last_height ||
                scale != last_scale || offsetX != last_offset_x || offsetY != last_offset_y;
            if (!changed) {
                std::this_thread::sleep_for(std::chrono::milliseconds(2));
                continue;
            }
            force_draw = false;
            last_width = w;
            last_height = h;
            last_scale = scale;
            last_offset_x = offsetX;
            last_offset_y = offsetY;
            glViewport(0, 0, w, h);
            glClearColor(242.0f / 255.0f, 242.0f / 255.0f, 247.0f / 255.0f, 1.0f);
            glClear(GL_COLOR_BUFFER_BIT);
            if (texture != 0 && textureWidth > 0 && textureHeight > 0) {
                const float base = std::min(static_cast<float>(w) / textureWidth,
                    static_cast<float>(h) / textureHeight);
                const float drawWidth = textureWidth * base * scale;
                const float drawHeight = textureHeight * base * scale;
                const float left = (w - drawWidth) * 0.5f + offsetX;
                const float top = (h - drawHeight) * 0.5f + offsetY;
                const float x0 = 2.0f * left / w - 1.0f;
                const float x1 = 2.0f * (left + drawWidth) / w - 1.0f;
                const float y0 = 1.0f - 2.0f * top / h;
                const float y1 = 1.0f - 2.0f * (top + drawHeight) / h;
                const float vertices[] = {
                    x0, y0,
                    x0, y1,
                    x1, y1,
                    x0, y0,
                    x1, y1,
                    x1, y0
                };
                const float bottom = h - (top + drawHeight);
                glUseProgram(program);
                glActiveTexture(GL_TEXTURE0);
                glBindTexture(GL_TEXTURE_2D, texture);
                glUniform4f(quadUniform, left, bottom, drawWidth, drawHeight);
                glBindVertexArray(vao);
                glBindBuffer(GL_ARRAY_BUFFER, vbo);
                glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_DYNAMIC_DRAW);
                glEnableVertexAttribArray(0);
                glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(float), nullptr);
                glDrawArrays(GL_TRIANGLES, 0, 6);
                glDisableVertexAttribArray(0);
                GLenum glError = glGetError();
                if (glError != GL_NO_ERROR) {
                    OH_LOG_Print(LOG_APP, LOG_ERROR, 0xFF00, "LanRDPX",
                        "draw error=%{public}u quad=%{public}f,%{public}f,%{public}f,%{public}f",
                        static_cast<unsigned>(glError), x0, y0, x1, y1);
                }
            }
            if (!eglSwapBuffers(display, surface)) {
                break;
            }
            g_xRenderedFrames.fetch_add(1);
        }

        if (vbo) glDeleteBuffers(1, &vbo);
        if (vao) glDeleteVertexArrays(1, &vao);
        if (texture) glDeleteTextures(1, &texture);
        if (program) glDeleteProgram(program);
        eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        eglDestroyContext(display, context);
        eglDestroySurface(display, surface);
        eglTerminate(display);
    }
};

static XTestRenderer g_xTestRenderer;

static void OnXSurfaceCreated(OH_NativeXComponent* component, void* window)
{
    uint64_t width = 0;
    uint64_t height = 0;
    if (component && window) {
        OH_NativeXComponent_GetXComponentSize(component, window, &width, &height);
        g_xTestRenderer.SetSize(static_cast<int>(width), static_cast<int>(height));
        g_xComponentActive.store(true);
        {
            std::lock_guard<std::mutex> sessionLock(g_sessionMutex);
            Session* session = g_session;
            if (session) {
                std::lock_guard<std::mutex> frameLock(session->mutex);
                session->pendingNativeFrame = true;
                session->hasNativeFrameTime = false;
            }
        }
        g_xTestRenderer.Start(window);
    }
}

static void OnXSurfaceChanged(OH_NativeXComponent* component, void* window)
{
    uint64_t width = 0;
    uint64_t height = 0;
    if (component && window) {
        OH_NativeXComponent_GetXComponentSize(component, window, &width, &height);
        g_xTestRenderer.SetSize(static_cast<int>(width), static_cast<int>(height));
    }
}

static void OnXSurfaceDestroyed(OH_NativeXComponent* component, void* window)
{
    (void)component;
    (void)window;
    g_xComponentActive.store(false);
    g_xTestRenderer.Stop();
}

static void OnXDispatchTouch(OH_NativeXComponent* component, void* window)
{
    (void)component;
    (void)window;
}

static OH_NativeXComponent_Callback g_xComponentCallback = {
    OnXSurfaceCreated,
    OnXSurfaceChanged,
    OnXSurfaceDestroyed,
    OnXDispatchTouch
};

static napi_value SetXViewTransform(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3] = {nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    double scale = 1.0;
    double offsetX = 0.0;
    double offsetY = 0.0;
    if (argc >= 3) {
        napi_get_value_double(env, args[0], &scale);
        napi_get_value_double(env, args[1], &offsetX);
        napi_get_value_double(env, args[2], &offsetY);
    }
    if (scale <= 0.0) scale = 1.0;
    g_xViewScale.store(static_cast<float>(scale));
    g_xOffsetX.store(static_cast<float>(offsetX));
    g_xOffsetY.store(static_cast<float>(offsetY));
    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}

static napi_value ForceXFrame(napi_env env, napi_callback_info info)
{
    (void)info;
    std::lock_guard<std::mutex> lock(g_sessionMutex);
    Session* session = g_session;
    if (session) {
        std::lock_guard<std::mutex> frameLock(session->mutex);
        session->pendingNativeFrame = true;
        session->hasNativeFrameTime = false;
    }
    napi_value result;
    napi_get_boolean(env, session != nullptr, &result);
    return result;
}

static napi_value GetXUploadedFrames(napi_env env, napi_callback_info info)
{
    (void)info;
    napi_value result;
    napi_create_double(env, static_cast<double>(g_xUploadedFrames.load()), &result);
    return result;
}

static napi_value GetXRenderFrames(napi_env env, napi_callback_info info)
{
    (void)info;
    napi_value result;
    napi_create_double(env, static_cast<double>(g_xRenderedFrames.load()), &result);
    return result;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        { "add", nullptr, Add, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "version", nullptr, Version, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "freerdpVersion", nullptr, FreeRDPVersion, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "connect", nullptr, Connect, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "stopSession", nullptr, StopSession, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getSessionInfo", nullptr, GetSessionInfo, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getFrame", nullptr, GetFrame, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "bindFrameMaps", nullptr, BindFrameMaps, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "unbindFrameMaps", nullptr, UnbindFrameMaps, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "ackFrame", nullptr, AckFrame, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "sendMouse", nullptr, SendMouse, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "sendWheel", nullptr, SendWheel, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "sendUnicode", nullptr, SendUnicode, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "sendKey", nullptr, SendKey, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "sendMouseMove", nullptr, SendMouseMove, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setXViewTransform", nullptr, SetXViewTransform, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "forceXFrame", nullptr, ForceXFrame, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getXRenderFrames", nullptr, GetXRenderFrames, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getXUploadedFrames", nullptr, GetXUploadedFrames, nullptr, nullptr, nullptr, napi_default, nullptr }
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    napi_value exportInstance = nullptr;
    if (napi_get_named_property(env, exports, OH_NATIVE_XCOMPONENT_OBJ, &exportInstance) == napi_ok) {
        OH_NativeXComponent* nativeXComponent = nullptr;
        napi_unwrap(env, exportInstance, reinterpret_cast<void**>(&nativeXComponent));
        if (nativeXComponent) {
            OH_NativeXComponent_RegisterCallback(nativeXComponent, &g_xComponentCallback);
        }
    }
    return exports;
}
EXTERN_C_END

static napi_module lanrdpModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "lanrdp",
    .nm_priv = ((void*)0),
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterLanrdpModule(void)
{
    napi_module_register(&lanrdpModule);
}
