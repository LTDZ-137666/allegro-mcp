# 架构说明

## 三层结构

| 层 | 组件 | 职责 |
|---|---|---|
| L1 协议层 | `python/allegro_mcp/server.py` (FastMCP) | 把 25 个 MCP tool 暴露给任意 MCP 客户端 |
| L2 传输层 | `python/allegro_mcp/bridge_client.py` + `bridge/src/tcp_server.cpp` | 双向 TCP，`127.0.0.1:57123`，JSON 行协议 |
| L3 执行层 | `bridge/src/allegro_ai_bridge.cpp` + `skill/ai_bridge.il` | 在 Allegro 进程内 `evalstring` 执行 SKILL |

## 为什么是"定时器 + 命令队列"

Allegro 的 SKILL 运行在 GUI 主线程。任何阻塞式 socket 读取都会冻结界面，用户会看到"未响应"。

所以设计成：

1. C++ 侧起一个后台线程跑 `recv()`，收到的命令进 `std::queue<Command>`（加锁）。
2. SKILL 侧用 `axlUIWTimerAdd` 注册定时器，每 tick 调 `bridge_poll()`。
3. `bridge_poll()` 非阻塞取一条命令，返回成 SKILL list。
4. SKILL 执行后调 `bridge_respond(id, result_json)` 把结果推回。

代价：每条命令至少一个 tick 的延迟。换来的是 GUI 全程不冻结。

## 协议

请求（Python → SKILL，经 C++ 队列）：

```json
{"id": "req-0001", "method": "eval", "params": {"expression": "axlDBGetDesign()->name"}}
```

响应（SKILL → Python）：

```json
{"id": "req-0001", "result": {"ok": true, "value": "board.brd"}, "error": null}
```

`method` 支持：

- `eval` — 原样执行表达式字符串
- `call` — 具名 axl 函数 + 参数列表，由 `function_registry.py` 拼装成表达式

## 类型转换

`skill_types.py` 负责 SKILL 与 Python 的对应：

| SKILL | Python |
|---|---|
| `nil` | `None` |
| `t` | `True` |
| integer / float | int / float |
| string | str |
| list | list |
| `axlDBGetDesign()` 等对象句柄 | 不透明字符串（回传 `eval` 使用） |

对象句柄不能跨进程持有——Allegro 重启后句柄全部失效。

## 版本耦合点

升级 Allegro 后可能失效的地方，按排查顺序：

1. `skill/ai_bridge.il` 里 `axlDllCall` / `axlUIWTimerAdd` 的签名。
2. `function_registry.py` 里 axl 函数名与参数个数。
3. Plugin API 结构体 `AXLPluginArgs` 的 ABI（`bridge/include/allegro_ai_bridge.h`）。

## 数组 / 对象句柄的常见坑

- SKILL 返回的 `axlDBGetDesign()` 这类对象在 Python 侧只是字符串形式的引用，必须原样传回。
- 列表嵌套超过两层时，`skill_types.py` 的递归转换可能丢失类型，尽量在 `allegro_eval` 里先 `->name` 之类降维。
- 执行耗时超过超时阈值（`ALLEGRO_MAX_TIMEOUT`）时 SKILL 侧不会中断，只会让本次响应丢失——长操作请拆成多步。