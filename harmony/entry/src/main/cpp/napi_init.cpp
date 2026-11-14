#include "napi/native_api.h"
#include <freerdp/freerdp.h>
#include <freerdp/version.h>
#include <freerdp/settings.h>
#include <freerdp/gdi/gdi.h>
#include <freerdp/input.h>
#include "multimedia/image_framework/image_pixel_map_mdk.h"
#include <freerdp/codec/color.h>
#include <winpr/synch.h>

#include <atomic>
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
static std::atomic<uint64_t> g_connectGeneration{ 0 };

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
    auto* sessionContext = reinterpret_cast<SessionContext*>(context);
    Session* session = sessionContext ? sessionContext->session : nullptr;
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
    if (session->nativeBound) {
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
        if (target && targetStride >= width * 4 &&
            session->width == width && session->height == height) {
            void* targetPixels = nullptr;
            if (OH_PixelMap_AccessPixels(target, &targetPixels) == 0 && targetPixels) {
                const auto writeStart = std::chrono::steady_clock::now();
                const BOOL copied = freerdp_image_copy(
                    static_cast<BYTE*>(targetPixels), PIXEL_FORMAT_BGRA32,
                    static_cast<UINT32>(targetStride),
                    0, 0, static_cast<UINT32>(width), static_cast<UINT32>(height),
                    source, format, stride, 0, 0, nullptr, FREERDP_FLIP_NONE);
                OH_PixelMap_UnAccessPixels(target);
                const auto writeEnd = std::chrono::steady_clock::now();
                session->nativeWriteMs = std::chrono::duration<double, std::milli>(writeEnd - writeStart).count();
                if (copied) {
                    session->frameIndex = targetIndex;
                    ++session->version;
                    return TRUE;
                }
            }
        }
    }
    session->pixels.resize(static_cast<size_t>(width) * height * 4);
    const BOOL converted = freerdp_image_copy(
        session->pixels.data(), PIXEL_FORMAT_BGRA32, static_cast<UINT32>(width * 4),
        0, 0, static_cast<UINT32>(width), static_cast<UINT32>(height),
        source, format, stride, 0, 0, nullptr, FREERDP_FLIP_NONE);
    if (!converted)
        return TRUE;

    session->width = width;
    session->height = height;
    ++session->version;
    return TRUE;
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
        DWORD status = WaitForMultipleObjects(count, handles, FALSE, 100);
        if (status == WAIT_FAILED)
            break;
        if (!freerdp_check_event_handles(session->context))
            break;
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
        { "sendMouseMove", nullptr, SendMouseMove, nullptr, nullptr, nullptr, napi_default, nullptr }
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
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
