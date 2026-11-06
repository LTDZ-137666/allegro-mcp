[English](README.md) · **简体中文**

---

# Allegro AI Bridge

**让 AI Agent 直接操作 Cadence Allegro PCB Editor 的 MCP 桥接系统。**

Cadence Allegro 是闭源商业 EDA，没有公开 API，所有操作必须经过运行中的 GUI 进程里的 SKILL 解释器。本项目用一层 C++ 插件 DLL 把 TCP 命令送进 Allegro 进程，再由 Python 侧包装成 [MCP](https://modelcontextprotocol.io) 工具，让 Claude Code / Codex / Cursor / 任意 MCP 客户端可以读写当前打开的设计。

```text
┌─────────────────┐   MCP (JSON-RPC/stdio)   ┌────────────────────┐
│    AI Agent     │ ───────────────────────► │ Python MCP Server  │
│ (Claude/Codex)  │ ◄─────────────────────── │     (FastMCP)      │
└─────────────────┘                          └─────────┬──────────┘
                                                       │ TCP 127.0.0.1:57123
                                             ┌─────────▼──────────┐
                                             │  C++ Bridge DLL    │
                                             │ (axlDllCall 加载)  │
                                             └─────────┬──────────┘
                                                       │ axl* Plugin API
                                             ┌─────────▼──────────┐
                                             │ Allegro SKILL      │
                                             │ Engine → PCB DB    │
                                             └────────────────────┘
```

## 为什么需要这个

开源 EDA 已经有成熟的 AI 生态（KiCad、EasyEDA 都有 agent skills），闭源的没有——因为：

1. **必须进程内操作。** `.brd` 是私有二进制格式，唯一入口是 GUI 进程内的 SKILL 解释器。
2. **SKILL 是孤儿语言。** Lisp 方言，只活在 Allegro 里，没有包管理、没有 LSP，LLM 训练数据里几乎没有。
3. **每个大版本 API 都变。** axl 函数签名在版本之间会变，写好的桥接升级就断。

所以现实做法只有一条：在 Allegro 进程内加载一个插件，从外部把命令喂进去。本项目就是这条路线。

## 前置条件

- **Cadence Allegro PCB Editor**（32 位插件宿主）
  <!-- TODO: 填写你实际验证过的版本，例如 17.4 -->
- **Windows 10/11**（已验证；Linux 分支代码存在但未测试）
- **Python 3.10+**
- **编译 DLL 时**：Visual Studio 2017+（需 32 位工具链）

> `axlplugin.h` 是 Cadence 版权头文件，**本仓库不包含**。请指向你自己的 Cadence 安装目录，见下文。

## 快速开始

### 1. 编译 Bridge DLL

```batch
cd bridge
cmake -B build -G "Visual Studio 17 2022" -A Win32 ^
      -DCADENCE_INCLUDE_DIR="C:/Cadence/SPB_17.4/tools/dfII/include"
cmake --build build --config Release
```

产物：`bridge/build/Release/allegro_ai_bridge.dll`

### 2. 安装到 Allegro

```powershell
powershell -ExecutionPolicy Bypass -File scripts/install.ps1
```

安装器会：

- 复制 `allegro_ai_bridge.dll` 和全部 `.il` 到 `%HOME%/pcbenv/`
- 在 `allegro.ilinit` 里追加自动加载，Allegro 启动即 ready
- 探测 Python 路径并生成 MCP 配置片段

### 3. 在 Allegro 里启动桥接

打开 Allegro，命令行输入：

```text
ai_server_start
```

看到 `TCP server listening on 127.0.0.1:57123` 即成功。

### 4. 配置 MCP 客户端

把服务信息填进你的 MCP 配置（参考 `scripts/mcp_config_template.json`）：

```json
{
  "mcpServers": {
    "allegro-mcp": {
      "command": "<PYTHON_EXE>",
      "args": ["<REPO>/python/allegro_mcp/server.py"],
      "timeout": 1800
    }
  }
}
```

### 5. 开始用

```text
你: 连接 Allegro
AI:  [allegro_connect]
你: 这块板有多少个网络？GND 上有多少个过孔？
AI:  [allegro_get_nets] → [allegro_get_net_info name="GND"]
```

## MCP 工具（25 个）

| 分组 | 工具 |
|---|---|
| 连接 | `allegro_connect` `allegro_disconnect` `allegro_status` |
| 执行 | `allegro_eval` `allegro_call` `allegro_chat_reply` |
| 设计读取 | `allegro_design_info` `allegro_get_nets` `allegro_get_net_info` `allegro_get_components` `allegro_get_component_info` |
| 层 | `allegro_get_layers` `allegro_get_active_layer` `allegro_set_active_layer` `allegro_layer_visible` |
| 选择 | `allegro_get_selection` `allegro_clear_selection` `allegro_select_all` `allegro_select_by_name` `allegro_select_at_point` |
| 视图 / 测量 | `allegro_design_visible` `allegro_zoom_fit` `allegro_design_refresh` `allegro_measure_distance` `allegro_get_object_properties` |

`allegro_eval` 可执行任意 SKILL 表达式——这是能力上限，也是风险所在。

## 安全设计

- **只绑回环。** TCP 服务固定 `127.0.0.1`，不监听外部网卡。
- **危险函数清单。** `python/allegro_mcp/config.py` 里的 `DANGEROUS_FUNCTIONS` 枚举了会改动数据库的操作（`axlSaveDesign`、`axlDeleteObject`、`axlDBCreateVia`、`axlChangeNet`…），便于上层做二次确认。
- **建议的工作方式。** 先在副板上验证；改动类操作前用 `allegro_eval` 做只读预演；不要让 agent 直接持有 `axlSaveDesign` 的调用权。

> Agent 会犯错，而且 PCB 上的错误不可撤销。开放写权限前请自行评估。

## 目录结构

```text
bridge/            C++ Bridge DLL
  include/         allegro_ai_bridge.h / tcp_server.h / command_queue.h
  src/             DLL 入口、TCP 服务器、线程安全命令队列
  CMakeLists.txt   需 -DCADENCE_INCLUDE_DIR
python/
  allegro_mcp/     MCP server (FastMCP)、TCP 客户端、协议、类型转换、25 个工具
  tests/           单元测试
skill/             SKILL 脚本（DLL 加载、定时轮询、命令分发、扩展工具）
scripts/           install.ps1 / uninstall.ps1 / MCP 配置模板
docs/              架构与打包方案
```

## 工作方式

1. SKILL 侧用 `axlDllCall` 加载 DLL，调 `bridge_start(57123)` 起 TCP 服务器。
2. `axlUIWTimerAdd` 注册定时器，每 tick 调 `bridge_poll()` 取一条待执行命令。
3. SKILL 用 `evalstring` 执行，结果经 `bridge_respond()` 写回。
4. Python 侧把 JSON-RPC(MCP) 翻译成 `{id, method, params}`，同步等待结果。

必须用定时器而不是阻塞读 socket，否则 Allegro 主线程会卡死。详见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 卸载

```powershell
powershell -ExecutionPolicy Bypass -File scripts/uninstall.ps1
```

## 已知限制

- **强依赖 Allegro 版本。** axl 函数签名变了要改 `function_registry.py`。
- **32 位宿主。** 64 位 Allegro 需重编（CMake 的 x64 分支可用但未验证）。
- **单连接。** 一个 Allegro 进程同时只服务一个 MCP 客户端。
- **未做并发写保护。** AI 的连续调用之间请确认落库。

## License 与免责

MIT，见 [LICENSE](LICENSE)。

- `axlplugin.h` 版权属 Cadence Design Systems，不在本仓库内分发。
- 本项目为独立第三方集成，与 Cadence 无隶属、授权或背书关系。
- Allegro 是 Cadence Design Systems, Inc. 的商标。
- 使用需自有的合法 Cadence 授权。作者不对因误操作导致的版图损坏负责。