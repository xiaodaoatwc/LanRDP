#include "napi/native_api.h"
#include <freerdp/freerdp.h>
#include <freerdp/version.h>
#include <freerdp/settings.h>

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


struct ConnectWork {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::string host;
    std::string username;
    std::string password;
    std::string domain;
    uint32_t port = 3389;
    bool connected = false;
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
    freerdp* instance = freerdp_new();
    if (!instance)
        return;

    if (!freerdp_context_new(instance)) {
        freerdp_free(instance);
        return;
    }

    rdpSettings* settings = instance->context->settings;
    freerdp_settings_set_string(settings, FreeRDP_ServerHostname, work->host.c_str());
    freerdp_settings_set_uint32(settings, FreeRDP_ServerPort, work->port);
    freerdp_settings_set_string(settings, FreeRDP_Username, work->username.c_str());
    freerdp_settings_set_string(settings, FreeRDP_Password, work->password.c_str());
    if (!work->domain.empty())
        freerdp_settings_set_string(settings, FreeRDP_Domain, work->domain.c_str());
    freerdp_settings_set_bool(settings, FreeRDP_IgnoreCertificate, TRUE);
    freerdp_settings_set_bool(settings, FreeRDP_NetworkAutoDetect, TRUE);
    freerdp_settings_set_uint32(settings, FreeRDP_TcpConnectTimeout, 5000);

    if (freerdp_connect(instance)) {
        work->connected = true;
        freerdp_disconnect(instance);
    }

    freerdp_context_free(instance);
    freerdp_free(instance);
}

static void CompleteConnect(napi_env env, napi_status status, void* data)
{
    auto* work = static_cast<ConnectWork*>(data);
    napi_value result;
    napi_create_string_utf8(env, work->connected ? "connected" : "failed", NAPI_AUTO_LENGTH, &result);

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

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        { "add", nullptr, Add, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "version", nullptr, Version, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "freerdpVersion", nullptr, FreeRDPVersion, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "connect", nullptr, Connect, nullptr, nullptr, nullptr, napi_default, nullptr }
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
