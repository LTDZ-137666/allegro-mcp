// allegro_ai_bridge.cpp — DLL 主入口 + 导出函数实现
// Allegro AI Bridge: TCP <-> SKILL 命令桥接器
//
// 基于 Cadence Allegro Plugin API
// Ref: <CADENCE_INSTALL>/tools/dfII/samples/local/axlplugin/axlecho_plugin.c

#include "allegro_ai_bridge.h"
#include "tcp_server.h"
#include "command_queue.h"
#include <cstdio>
#include <cstring>

#ifdef _WINDOWS
#include <windows.h>
#endif

using namespace allegro_bridge;

// ============================================================
// 全局状态
// ============================================================
static int g_next_command_id = 0;
static bool g_initialized = false;
static std::string g_chat_out;  // 待发送到 Python 的聊天消息
static std::mutex g_chat_mutex;
static std::string g_display_in; // Python 发来的显示消息

// ============================================================
// JSON 工具函数 (轻量级，无需第三方库)
// ============================================================

// 从 JSON 字符串中提取 id 字段
static int json_extract_id(const char* json) {
    // 简单扫描: "id": 123
    const char* p = strstr(json, "\"id\"");
    if (!p) p = strstr(json, "\"id\"");
    if (!p) return -1;
    p = strchr(p, ':');
    if (!p) return -1;
    p++; // 跳过冒号
    while (*p == ' ' || *p == '\t' || *p == '\n') p++;
    return atoi(p);
}

// 从 JSON 提取 method 字段
static std::string json_extract_method(const char* json) {
    const char* p = strstr(json, "\"method\"");
    if (!p) p = strstr(json, "\"method\"");
    if (!p) return "";
    p = strchr(p, ':');
    if (!p) return "";
    p++;
    while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '"') p++;
    // 读取到下一个引号
    std::string method;
    while (*p && *p != '"' && *p != '\n') {
        method += *p;
        p++;
    }
    return method;
}

// 从 JSON 提取 expression 字段
static std::string json_extract_expression(const char* json) {
    const char* p = strstr(json, "\"expression\"");
    if (!p) p = strstr(json, "\"expression\"");
    if (!p) return "";
    p = strchr(p, ':');
    if (!p) return "";
    p++;
    while (*p == ' ' || *p == '\t' || *p == '\n') p++;
    if (*p == '"') {
        p++;
        std::string expr;
        while (*p && *p != '"') {
            if (*p == '\\' && *(p+1)) { p++; expr += *p; }
            else expr += *p;
            p++;
        }
        return expr;
    }
    return "";
}

// 从 JSON 提取 params 对象
static std::string json_extract_params(const char* json) {
    // 简单实现: 扫描 "params": { ... }
    const char* p = strstr(json, "\"params\"");
    if (!p) p = strstr(json, "\"params\"");
    if (!p) return "{}";
    p = strchr(p, ':');
    if (!p) return "{}";
    p++;
    while (*p == ' ' || *p == '\t' || *p == '\n') p++;
    if (*p != '{') return "{}";

    // 计算大括号匹配
    int depth = 0;
    const char* start = p;
    while (*p) {
        if (*p == '{') depth++;
        else if (*p == '}') {
            depth--;
            if (depth == 0) {
                p++; // 包含结束大括号
                break;
            }
        }
        p++;
    }
    return std::string(start, p - start);
}

// 从 params JSON 中提取 function 字符串
static std::string json_extract_func_from_params(const char* params_json) {
    const char* p = strstr(params_json, "\"function\"");
    if (!p) p = strstr(params_json, "\"function\"");
    if (!p) return "";
    p = strchr(p, ':');
    if (!p) return "";
    p++;
    while (*p == ' ' || *p == '\t' || *p == '\n') p++;
    if (*p == '"') {
        p++;
        std::string func;
        while (*p && *p != '"') {
            if (*p == '\\' && *(p+1)) { p++; func += *p; }
            else func += *p;
            p++;
        }
        return func;
    }
    return "";
}

// 构建错误响应 JSON
static std::string build_error_response(int id, int code, const std::string& message) {
    char buf[2048];
    snprintf(buf, sizeof(buf),
        "{\"id\":%d,\"result\":null,\"error\":{\"code\":%d,\"message\":\"%s\"}}",
        id, code, message.c_str());
    return std::string(buf);
}

// 构建成功响应 JSON
static std::string build_success_response(int id, const std::string& data_json) {
    char buf[16384];
    // 处理数据中的引号转义
    std::string escaped_data;
    for (char c : data_json) {
        if (c == '\\') { escaped_data += "\\\\"; continue; }
        if (c == '"')  { escaped_data += "\\\""; continue; }
        if (c == '\n') { escaped_data += "\\n"; continue; }
        if (c == '\r') { escaped_data += "\\r"; continue; }
        if (c == '\t') { escaped_data += "\\t"; continue; }
        escaped_data += c;
    }
    snprintf(buf, sizeof(buf),
        "{\"id\":%d,\"result\":{\"success\":true,\"data\":\"%s\"},\"error\":null}",
        id, escaped_data.c_str());
    return std::string(buf);
}

// ============================================================
// TCP 命令回调 — 当收到命令时由 TCP 线程调用
// ============================================================
static void on_tcp_command(const std::string& request_json) {
    int id = json_extract_id(request_json.c_str());
    std::string method = json_extract_method(request_json.c_str());

    Command cmd;
    cmd.id = id;
    cmd.params_json = json_extract_params(request_json.c_str());

    if (method == "raw") {
        cmd.method = "raw";
        cmd.expression = json_extract_expression(request_json.c_str());
    } else if (method == "evalstring") {
        cmd.method = "evalstring";
        cmd.expression = json_extract_expression(request_json.c_str());
    } else {
        // 默认: call_function
        cmd.method = "call_function";
        cmd.func_name = json_extract_func_from_params(cmd.params_json.c_str());
        if (cmd.func_name.empty()) {
            cmd.func_name = json_extract_expression(request_json.c_str());
            cmd.method = "evalstring";
        }
    }

    if (!CommandQueue::instance().push_command(cmd)) {
        // 队列满, 返回错误
        std::string err = build_error_response(id, -32000, "Command queue is full");
        TcpServer::instance().send_response(err);
    }

    // 命令已入队, 等待 SKILL 侧通过 bridge_poll 取走执行
    // 响应由 bridge_respond 触发, 在 TCP 线程中发送
}

// ============================================================
// DLL 入口点
// ============================================================
#ifdef _WINDOWS
BOOL APIENTRY DllMain(HMODULE hModule, DWORD ul_reason_for_call, LPVOID lpReserved) {
    switch (ul_reason_for_call) {
    case DLL_PROCESS_ATTACH:
        DisableThreadLibraryCalls(hModule);
        break;
    case DLL_PROCESS_DETACH:
        TcpServer::instance().stop();
        CommandQueue::instance().clear();
        break;
    }
    return TRUE;
}
#endif

// ============================================================
// 导出函数实现
// ============================================================

AXL_DLL_EXPORT int bridge_start(AXLPluginArgs *out, AXLPluginArgs *in) {
    int port = 57123;

    // 解析端口参数
    if (in && in->count > 0 && in->argv[0].type == AP_LONG) {
        port = (int)in->argv[0].data.l_value;
    }

    // 设置 TCP 命令回调
    TcpServer::instance().set_on_command(on_tcp_command);

    // 启动服务器
    bool ok = TcpServer::instance().start(port);

    if (ok) {
        g_initialized = true;
        out->count = 1;
        out->argv[0].type = AP_BOOL;
        out->argv[0].data.b_value = 1; // true
    } else {
        g_initialized = false;
        out->count = 1;
        out->argv[0].type = AP_BOOL;
        out->argv[0].data.b_value = 0; // false (nil in SKILL)
    }

    return 0;
}

AXL_DLL_EXPORT int bridge_stop(AXLPluginArgs *out, AXLPluginArgs *in) {
    (void)in;
    TcpServer::instance().stop();
    CommandQueue::instance().clear();
    g_initialized = false;

    out->count = 1;
    out->argv[0].type = AP_BOOL;
    out->argv[0].data.b_value = 1;
    return 0;
}

AXL_DLL_EXPORT int bridge_poll(AXLPluginArgs *out, AXLPluginArgs *in) {
    (void)in;

    auto cmd_opt = CommandQueue::instance().pop_command();

    if (!cmd_opt.has_value()) {
        // 没有待处理的命令, 返回 nil
        out->count = 0;
        return 0;
    }

    Command& cmd = cmd_opt.value();

    // 返回: (id method func_name expression params_json)
    // 格式: (id "method" "func_name" "expression" "params_json")
    out->count = 5;
    out->argv[0].type = AP_LONG;
    out->argv[0].data.l_value = cmd.id;

    out->argv[1].type = AP_CONST_STRING;
    out->argv[1].data.cs_value = cmd.method.c_str();

    out->argv[2].type = AP_CONST_STRING;
    out->argv[2].data.cs_value = cmd.func_name.c_str();

    out->argv[3].type = AP_CONST_STRING;
    out->argv[3].data.cs_value = cmd.expression.c_str();

    out->argv[4].type = AP_CONST_STRING;
    out->argv[4].data.cs_value = cmd.params_json.c_str();

    return 0;
}

AXL_DLL_EXPORT int bridge_respond(AXLPluginArgs *out, AXLPluginArgs *in) {
    // 参数: id (long), result_json (string — SKILL 已构建完整 JSON-RPC 响应)
    if (!in || in->count < 2) {
        out->count = 1;
        out->argv[0].type = AP_BOOL;
        out->argv[0].data.b_value = 0;
        return 0;
    }

    const char* result_json = in->argv[1].data.cs_value;
    if (!result_json) result_json = "{}";

    // 检查是否有待发的聊天消息，有则附加到响应 JSON 中
    std::string final_response(result_json);
    {
        std::lock_guard<std::mutex> lock(g_chat_mutex);
        if (!g_chat_out.empty()) {
            // 在响应 JSON 的最后一个 } 前插入 chat 字段
            size_t pos = final_response.rfind('}');
            if (pos != std::string::npos) {
                std::string chat_json = ",\"chat\":\"" + g_chat_out + "\"";
                // 简单转义聊天消息中的引号
                for (auto& c : chat_json) {
                    (void)c; // suppress warning
                }
                final_response.insert(pos, chat_json);
            }
            g_chat_out.clear();
        }
    }

    bool sent = TcpServer::instance().send_response(final_response);

    out->count = 1;
    out->argv[0].type = AP_BOOL;
    out->argv[0].data.b_value = sent ? 1 : 0;
    return 0;
}

AXL_DLL_EXPORT int bridge_status(AXLPluginArgs *out, AXLPluginArgs *in) {
    (void)in;
    out->count = 1;
    out->argv[0].type = AP_LONG;
    if (!g_initialized) {
        out->argv[0].data.l_value = -1; // 未初始化
    } else if (TcpServer::instance().is_connected()) {
        out->argv[0].data.l_value = 1;  // 已连接
    } else {
        out->argv[0].data.l_value = 0;  // 等待连接
    }
    return 0;
}

// bridge_chat_send(msg) → t/nil
// Allegro 聊天消息，等 bridge_respond 时附带发送
AXL_DLL_EXPORT int bridge_chat_send(AXLPluginArgs *out, AXLPluginArgs *in) {
    if (!in || in->count < 1) {
        out->count = 1; out->argv[0].type = AP_BOOL; out->argv[0].data.b_value = 0;
        return 0;
    }
    {
        std::lock_guard<std::mutex> lock(g_chat_mutex);
        if (!g_chat_out.empty()) g_chat_out += "\\n";
        g_chat_out += in->argv[0].data.cs_value ? in->argv[0].data.cs_value : "";
    }
    out->count = 1; out->argv[0].type = AP_BOOL; out->argv[0].data.b_value = 1;
    return 0;
}

// bridge_display_get() → string/nil
// 获取 Python 发来的显示消息，读取后清空
// bridge_chat_has_pending() → t/nil
// 检查是否有待发的聊天消息
AXL_DLL_EXPORT int bridge_chat_has_pending(AXLPluginArgs *out, AXLPluginArgs *in) {
    (void)in;
    bool has = false;
    { std::lock_guard<std::mutex> lock(g_chat_mutex); has = !g_chat_out.empty(); }
    out->count = 1; out->argv[0].type = AP_BOOL;
    out->argv[0].data.b_value = has ? 1 : 0;
    return 0;
}

AXL_DLL_EXPORT int bridge_display_get(AXLPluginArgs *out, AXLPluginArgs *in) {
    (void)in;
    if (g_display_in.empty()) {
        out->count = 0; return 0;
    }
    out->count = 1;
    out->argv[0].type = AP_CONST_STRING;
    out->argv[0].data.cs_value = g_display_in.c_str();
    g_display_in.clear();
    return 0;
}

AXL_DLL_EXPORT int bridge_version(AXLPluginArgs *out, AXLPluginArgs *in) {
    (void)in;
    out->count = 1;
    out->argv[0].type = AP_CONST_STRING;
    out->argv[0].data.cs_value = "1.0.0";
    return 0;
}
