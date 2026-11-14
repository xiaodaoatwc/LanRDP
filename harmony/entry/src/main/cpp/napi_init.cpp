#include "napi/native_api.h"
#include <freerdp/freerdp.h>
#include <freerdp/version.h>
#include <freerdp/settings.h>
#include <freerdp/gdi/gdi.h>
#include <freerdp/input.h>
#include <freerdp/update.h>
#include <freerdp/codec/color.h>
#include <winpr/synch.h>

#include <algorithm>
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

static constexpr int kTileSize = 64;

struct Session {
    freerdp* instance = nullptr;
    rdpContext* context = nullptr;
    std::thread thread;
    std::mutex mutex;
    std::vector<uint8_t> pixels;
    std::vector<uint8_t> pendingTiles;
    std::vector<uint8_t> unreadTiles;
    int tilesX = 0;
    int tilesY = 0;
    bool fullFrame = true;
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

static void EnsureDirtyGrid(Session* session)
{
    if (!session || session->width <= 0 || session->height <= 0)
        return;
    const int tilesX = (session->width + kTileSize - 1) / kTileSize;
    const int tilesY = (session->height + kTileSize - 1) / kTileSize;
    const size_t count = static_cast<size_t>(tilesX) * tilesY;
    if (session->tilesX != tilesX || session->tilesY != tilesY ||
        session->pendingTiles.size() != count || session->unreadTiles.size() != count) {
        session->tilesX = tilesX;
        session->tilesY = tilesY;
        session->pendingTiles.assign(count, 0);
        session->unreadTiles.assign(count, 0);
        session->fullFrame = true;
    }
}

static void MarkDirtyLocked(Session* session, int x, int y, int width, int height)
{
    if (!session || width <= 0 || height <= 0)
        return;
    EnsureDirtyGrid(session);
    if (session->tilesX <= 0 || session->tilesY <= 0)
        return;
    const int left = std::max(0, x);
    const int top = std::max(0, y);
    const int right = std::min(session->width, x + width);
    const int bottom = std::min(session->height, y + height);
    if (right <= left || bottom <= top)
        return;
    const int tx0 = left / kTileSize;
    const int ty0 = top / kTileSize;
    const int tx1 = (right - 1) / kTileSize;
    const int ty1 = (bottom - 1) / kTileSize;
    for (int ty = ty0; ty <= ty1; ++ty) {
        for (int tx = tx0; tx <= tx1; ++tx) {
            session->pendingTiles[static_cast<size_t>(ty) * session->tilesX + tx] = 1;
        }
    }
}

static void MarkDirty(Session* session, int x, int y, int width, int height)
{
    if (!session)
        return;
    std::lock_guard<std::mutex> lock(session->mutex);
    MarkDirtyLocked(session, x, y, width, height);
}

static void MarkAllDirty(Session* session)
{
    if (!session)
        return;
    std::lock_guard<std::mutex> lock(session->mutex);
    EnsureDirtyGrid(session);
    session->fullFrame = true;
    std::fill(session->pendingTiles.begin(), session->pendingTiles.end(), 1);
}

static pBitmapUpdate g_originalBitmapUpdate = nullptr;
static pSurfaceBits g_originalSurfaceBits = nullptr;
static pRefreshRect g_originalRefreshRect = nullptr;

static Session* SessionFromContext(rdpContext* context)
{
    auto* sessionContext = reinterpret_cast<SessionContext*>(context);
    return sessionContext ? sessionContext->session : nullptr;
}

static BOOL SessionBitmapUpdate(rdpContext* context, const BITMAP_UPDATE* bitmap)
{
    const BOOL result = g_originalBitmapUpdate ? g_originalBitmapUpdate(context, bitmap) : TRUE;
    Session* session = SessionFromContext(context);
    if (session && bitmap) {
        for (UINT32 i = 0; i < bitmap->number; ++i) {
            const BITMAP_DATA& data = bitmap->rectangles[i];
            MarkDirty(session, static_cast<int>(data.destLeft), static_cast<int>(data.destTop),
                      static_cast<int>(data.width), static_cast<int>(data.height));
        }
    }
    return result;
}

static BOOL SessionSurfaceBits(rdpContext* context, const SURFACE_BITS_COMMAND* command)
{
    const BOOL result = g_originalSurfaceBits ? g_originalSurfaceBits(context, command) : TRUE;
    Session* session = SessionFromContext(context);
    if (session && command) {
        const int width = static_cast<int>(command->destRight) - static_cast<int>(command->destLeft);
        const int height = static_cast<int>(command->destBottom) - static_cast<int>(command->destTop);
        MarkDirty(session, static_cast<int>(command->destLeft), static_cast<int>(command->destTop),
                  width, height);
    }
    return result;
}

static BOOL SessionRefreshRect(rdpContext* context, BYTE count, const RECTANGLE_16* areas)
{
    const BOOL result = g_originalRefreshRect ? g_originalRefreshRect(context, count, areas) : TRUE;
    Session* session = SessionFromContext(context);
    if (session && areas) {
        for (BYTE i = 0; i < count; ++i) {
            const RECTANGLE_16& area = areas[i];
            MarkDirty(session, static_cast<int>(area.left), static_cast<int>(area.top),
                      static_cast<int>(area.right) - static_cast<int>(area.left),
                      static_cast<int>(area.bottom) - static_cast<int>(area.top));
        }
    }
    return result;
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
    session->width = width;
    session->height = height;
    EnsureDirtyGrid(session);

    const size_t fullSize = static_cast<size_t>(width) * height * 4;
    const bool needFull = session->fullFrame || session->pixels.size() != fullSize;
    if (needFull) {
        session->pixels.resize(fullSize);
        const BOOL converted = freerdp_image_copy(
            session->pixels.data(), PIXEL_FORMAT_BGRA32, static_cast<UINT32>(width * 4),
            0, 0, static_cast<UINT32>(width), static_cast<UINT32>(height),
            source, format, stride, 0, 0, nullptr, FREERDP_FLIP_NONE);
        if (!converted)
            return TRUE;
        std::fill(session->unreadTiles.begin(), session->unreadTiles.end(), 1);
        std::fill(session->pendingTiles.begin(), session->pendingTiles.end(), 0);
        session->fullFrame = false;
        ++session->version;
        return TRUE;
    }

    bool anyDirty = false;
    for (size_t i = 0; i < session->pendingTiles.size(); ++i) {
        if (!session->pendingTiles[i])
            continue;
        anyDirty = true;
        session->unreadTiles[i] = 1;
        const int tx = static_cast<int>(i) % session->tilesX;
        const int ty = static_cast<int>(i) / session->tilesX;
        const int x = tx * kTileSize;
        const int y = ty * kTileSize;
        const int tileWidth = std::min(kTileSize, width - x);
        const int tileHeight = std::min(kTileSize, height - y);
        if (format == PIXEL_FORMAT_BGRA32) {
            const BYTE* src = source + static_cast<size_t>(y) * stride + static_cast<size_t>(x) * 4;
            BYTE* dst = session->pixels.data() +
                (static_cast<size_t>(y) * width + x) * 4;
            for (int row = 0; row < tileHeight; ++row) {
                std::memcpy(dst + static_cast<size_t>(row) * width * 4,
                            src + static_cast<size_t>(row) * stride,
                            static_cast<size_t>(tileWidth) * 4);
            }
        } else {
            freerdp_image_copy(
                session->pixels.data(), PIXEL_FORMAT_BGRA32, static_cast<UINT32>(width * 4),
                x, y, static_cast<UINT32>(tileWidth), static_cast<UINT32>(tileHeight),
                source, format, stride, 0, 0, nullptr, FREERDP_FLIP_NONE);
        }
    }
    std::fill(session->pendingTiles.begin(), session->pendingTiles.end(), 0);
    if (!anyDirty)
        return TRUE;

    ++session->version;
    return TRUE;
}

static BOOL SessionDesktopResize(rdpContext* context)
{
    Session* session = SessionFromContext(context);
    if (session) {
        MarkAllDirty(session);
    }
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
    rdpUpdate* update = instance->context->update;
    update->BeginPaint = SessionBeginPaint;
    update->EndPaint = SessionEndPaint;
    update->DesktopResize = SessionDesktopResize;
    g_originalBitmapUpdate = update->BitmapUpdate;
    g_originalSurfaceBits = update->SurfaceBits;
    g_originalRefreshRect = update->RefreshRect;
    update->BitmapUpdate = SessionBitmapUpdate;
    update->SurfaceBits = SessionSurfaceBits;
    update->RefreshRect = SessionRefreshRect;
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
    if (g_session) {
        std::lock_guard<std::mutex> frameLock(g_session->mutex);
        state = g_session->state.load();
        error = g_session->lastError;
        version = g_session->version;
        width = g_session->width;
        height = g_session->height;
    }

    napi_value object;
    napi_value jsState;
    napi_value jsError;
    napi_value jsVersion;
    napi_value jsWidth;
    napi_value jsHeight;
    napi_create_object(env, &object);
    napi_create_int32(env, state, &jsState);
    napi_create_string_utf8(env, error.c_str(), NAPI_AUTO_LENGTH, &jsError);
    napi_create_double(env, static_cast<double>(version), &jsVersion);
    napi_create_int32(env, width, &jsWidth);
    napi_create_int32(env, height, &jsHeight);
    napi_set_named_property(env, object, "state", jsState);
    napi_set_named_property(env, object, "error", jsError);
    napi_set_named_property(env, object, "version", jsVersion);
    napi_set_named_property(env, object, "width", jsWidth);
    napi_set_named_property(env, object, "height", jsHeight);
    return object;
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
    EnsureDirtyGrid(session);

    size_t unreadCount = 0;
    for (uint8_t dirty : session->unreadTiles) {
        if (dirty)
            ++unreadCount;
    }
    if (unreadCount == 0)
        return result;

    const size_t tileCount = session->pendingTiles.size();
    const bool full = unreadCount * 2 >= tileCount;
    std::vector<uint8_t> frameData;
    std::vector<int> tileInfo;
    if (full) {
        frameData = session->pixels;
        std::fill(session->unreadTiles.begin(), session->unreadTiles.end(), 0);
    } else {
        frameData.reserve(unreadCount * kTileSize * kTileSize * 4);
        for (size_t i = 0; i < session->unreadTiles.size(); ++i) {
            if (!session->unreadTiles[i])
                continue;
            const int tx = static_cast<int>(i) % session->tilesX;
            const int ty = static_cast<int>(i) / session->tilesX;
            const int x = tx * kTileSize;
            const int y = ty * kTileSize;
            const int tileWidth = std::min(kTileSize, session->width - x);
            const int tileHeight = std::min(kTileSize, session->height - y);
            const int offset = static_cast<int>(frameData.size());
            const int stride = tileWidth * 4;
            const size_t oldSize = frameData.size();
            frameData.resize(oldSize + static_cast<size_t>(stride) * tileHeight);
            const uint8_t* src = session->pixels.data() +
                (static_cast<size_t>(y) * session->width + x) * 4;
            uint8_t* dst = frameData.data() + oldSize;
            for (int row = 0; row < tileHeight; ++row) {
                std::memcpy(dst + static_cast<size_t>(row) * stride,
                            src + static_cast<size_t>(row) * session->width * 4,
                            static_cast<size_t>(stride));
            }
            tileInfo.push_back(x);
            tileInfo.push_back(y);
            tileInfo.push_back(tileWidth);
            tileInfo.push_back(tileHeight);
            tileInfo.push_back(offset);
            tileInfo.push_back(stride);
        }
        std::fill(session->unreadTiles.begin(), session->unreadTiles.end(), 0);
    }

    void* bufferData = nullptr;
    napi_value buffer;
    if (napi_create_arraybuffer(env, frameData.size(), &bufferData, &buffer) != napi_ok)
        return result;
    std::memcpy(bufferData, frameData.data(), frameData.size());

    napi_value object;
    napi_value width;
    napi_value height;
    napi_value version;
    napi_value fullValue;
    napi_value tiles;
    napi_create_object(env, &object);
    napi_create_int32(env, session->width, &width);
    napi_create_int32(env, session->height, &height);
    napi_create_double(env, static_cast<double>(session->version), &version);
    napi_get_boolean(env, full, &fullValue);
    napi_create_array_with_length(env, tileInfo.size() / 6, &tiles);
    for (size_t i = 0; i < tileInfo.size() / 6; ++i) {
        napi_value tile;
        napi_value value;
        napi_create_object(env, &tile);
        napi_create_int32(env, tileInfo[i * 6 + 0], &value);
        napi_set_named_property(env, tile, "x", value);
        napi_create_int32(env, tileInfo[i * 6 + 1], &value);
        napi_set_named_property(env, tile, "y", value);
        napi_create_int32(env, tileInfo[i * 6 + 2], &value);
        napi_set_named_property(env, tile, "width", value);
        napi_create_int32(env, tileInfo[i * 6 + 3], &value);
        napi_set_named_property(env, tile, "height", value);
        napi_create_int32(env, tileInfo[i * 6 + 4], &value);
        napi_set_named_property(env, tile, "offset", value);
        napi_create_int32(env, tileInfo[i * 6 + 5], &value);
        napi_set_named_property(env, tile, "stride", value);
        napi_set_element(env, tiles, static_cast<uint32_t>(i), tile);
    }
    napi_set_named_property(env, object, "width", width);
    napi_set_named_property(env, object, "height", height);
    napi_set_named_property(env, object, "version", version);
    napi_set_named_property(env, object, "full", fullValue);
    napi_set_named_property(env, object, "tiles", tiles);
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
