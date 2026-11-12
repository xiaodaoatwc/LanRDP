#include "napi/native_api.h"
#include <freerdp/freerdp.h>
#include <freerdp/version.h>
#include <freerdp/settings.h>
#include <freerdp/gdi/gdi.h>
#include <freerdp/input.h>
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


struct Session {
    freerdp* instance = nullptr;
    rdpContext* context = nullptr;
    std::thread thread;
    std::mutex mutex;
    std::vector<uint8_t> pixels;
    int width = 0;
    int height = 0;
    uint64_t version = 0;
    std::atomic<bool> stop{ false };
};

struct SessionContext {
    rdpContext context;
    Session* session;
};

static std::mutex g_sessionMutex;
static Session* g_session = nullptr;

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
    session->pixels.resize(static_cast<size_t>(width) * height * 4);
    const BOOL converted = freerdp_image_copy(
        session->pixels.data(), PIXEL_FORMAT_RGBA32, static_cast<UINT32>(width * 4),
        0, 0, static_cast<UINT32>(width), static_cast<UINT32>(height),
        source, format, stride, 0, 0, nullptr, FREERDP_FLIP_NONE);
    if (!converted)
        return TRUE;

    /* OHOS PixelMap RGBA_8888 expects R,G,B,A while the FreeRDP
     * compatibility path on this platform produces B,G,R,A. */
    for (size_t i = 0; i + 3 < session->pixels.size(); i += 4) {
        std::swap(session->pixels[i], session->pixels[i + 2]);
    }

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
    if (!gdi_init(instance, PIXEL_FORMAT_RGBA32))
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
                         const std::string& domain, std::string& error)
{
    if (!ProbeTcp(host, port, error))
        return false;

#if defined(__aarch64__)
    setenv("OPENSSL_MODULES", "/data/storage/el1/bundle/libs/arm64", 1);
#else
    setenv("OPENSSL_MODULES", "/data/storage/el1/bundle/libs/x86_64", 1);
#endif

    freerdp* instance = freerdp_new();
    if (!instance) {
        error = "freerdp_new failed";
        return false;
    }

    instance->ContextSize = sizeof(SessionContext);
    if (!freerdp_context_new(instance)) {
        error = "freerdp_context_new failed";
        freerdp_free(instance);
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
    freerdp_settings_set_uint32(settings, FreeRDP_DesktopWidth, 1024);
    freerdp_settings_set_uint32(settings, FreeRDP_DesktopHeight, 768);

    instance->PostConnect = SessionPostConnect;

    if (!freerdp_connect(instance)) {
        UINT32 code = freerdp_get_last_error(instance->context);
        const char* name = freerdp_get_last_error_name(code);
        const char* text = freerdp_get_last_error_string(code);
        error = "RDP " + std::to_string(code) + " " + (name ? name : "") + " " + (text ? text : "");
        return false;
    }

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
    if (StartSession(session, work->host, work->port, work->username, work->password, work->domain, work->error)) {
        std::lock_guard<std::mutex> lock(g_sessionMutex);
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
    size_t argc = 5;
    napi_value args[5] = {nullptr};
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
    }

    napi_value resourceName;
    napi_create_string_utf8(env, "LanRDPConnect", NAPI_AUTO_LENGTH, &resourceName);
    napi_create_async_work(env, nullptr, resourceName, ExecuteConnect, CompleteConnect, work, &work->work);
    napi_queue_async_work(env, work->work);
    return promise;
}

static napi_value StopSession(napi_env env, napi_callback_info info)
{
    std::lock_guard<std::mutex> lock(g_sessionMutex);
    if (g_session) {
        DestroySession(g_session);
        g_session = nullptr;
    }
    napi_value result;
    napi_get_boolean(env, true, &result);
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
            down ? KBD_FLAGS_DOWN : KBD_FLAGS_RELEASE,
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
        UINT16 flags = down ? KBD_FLAGS_DOWN : KBD_FLAGS_RELEASE;
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
