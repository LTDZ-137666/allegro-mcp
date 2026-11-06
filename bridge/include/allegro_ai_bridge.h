// allegro_ai_bridge.h — 主头文件
// Allegro AI Bridge DLL: 提供 Python MCP Server <-> SKILL Engine 之间的 TCP 桥接
//
// 基于 Cadence Allegro Plugin API (axlplugin.h)
// Ref: <CADENCE_INSTALL>/tools/dfII/samples/local/axlplugin/axlecho_plugin.c

#pragma once

#ifdef _WINDOWS
#include <windows.h>
#define AXL_DLL_EXPORT __declspec(dllexport)
#else
#define AXL_DLL_EXPORT
#endif

#include "axlplugin.h"

// ============================================================
// 导出函数 — 由 SKILL 通过 axlDllCall 调用
// 所有函数签名: int func(AXLPluginArgs *out, AXLPluginArgs *in)
// 返回值: 0=成功, 非零=错误
// ============================================================

#ifdef __cplusplus
extern "C" {
#endif

// bridge_start(port) → t/nil
// 启动 TCP 服务器在指定端口
AXL_DLL_EXPORT int bridge_start(AXLPluginArgs *out, AXLPluginArgs *in);

// bridge_stop() → t
// 停止 TCP 服务器并清理资源
AXL_DLL_EXPORT int bridge_stop(AXLPluginArgs *out, AXLPluginArgs *in);

// bridge_poll() → (id func_name arg1 arg2 ...) 或 nil
// 非阻塞轮询命令队列。如果没有待处理的命令返回 nil
AXL_DLL_EXPORT int bridge_poll(AXLPluginArgs *out, AXLPluginArgs *in);

// bridge_respond(id result_json) → t/nil
// 发送命令执行结果回 MCP Server
AXL_DLL_EXPORT int bridge_respond(AXLPluginArgs *out, AXLPluginArgs *in);

// bridge_status() → 0=未连接 1=已连接 -1=未初始化
AXL_DLL_EXPORT int bridge_status(AXLPluginArgs *out, AXLPluginArgs *in);

// bridge_chat_send(msg) → t/nil
// 从 Allegro 聊天框发送消息到 Python
AXL_DLL_EXPORT int bridge_chat_send(AXLPluginArgs *out, AXLPluginArgs *in);

// bridge_chat_has_pending() → t/nil
// 检查是否有待发聊天消息
AXL_DLL_EXPORT int bridge_chat_has_pending(AXLPluginArgs *out, AXLPluginArgs *in);

// bridge_display_get() → string/nil
// 获取 Python 发来要显示的消息
AXL_DLL_EXPORT int bridge_display_get(AXLPluginArgs *out, AXLPluginArgs *in);

// bridge_version() → "1.0.0"
AXL_DLL_EXPORT int bridge_version(AXLPluginArgs *out, AXLPluginArgs *in);

#ifdef __cplusplus
}
#endif
