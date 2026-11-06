# Allegro AI Bridge — 中件化打包方案

## Context

当前 Allegro AI Bridge 已验证可工作（三层架构：Python MCP ↔ C++ DLL/TCP ↔ SKILL），但部署高度依赖开发者环境——硬编码路径、手动复制文件、手动编辑配置。用户希望将其打包为"中件"：**一个安装包，在任意电脑上运行安装脚本后即可实现 Allegro 接入 AI**。

## 目标

将以下零散组件整合为**一键安装、一键卸载**的中件：

| 组件 | 当前状态 | 目标 |
|------|---------|------|
| C++ DLL | 手动编译 + 手动复制到 `pcbenv/` | 预编译 x86 DLL 随包分发，安装器自动复制 |
| SKILL 脚本 | 手动 `load("ai_bridge.il")` | 安装器写入 `allegro.ilinit` 自动加载，Allegro 启动即 ready |
| Python MCP Server | 硬编码用户路径 | 改为 pip 可安装的 Python 包，通过 `pyproject.toml` 声明入口点 |
| MCP 配置 | 手动编辑 `mcp.json` | 安装器自动发现 Python 路径并写入 Proma 的 `mcp.json` |
| 配置参数 | 硬编码绝对路径 | 全部改为环境变量 + 自动发现 |

## 中件结构

```
allegro-ai-bridge/                    # 分发包根目录
├── install.ps1                       # 一键安装脚本 (PowerShell)
├── uninstall.ps1                     # 一键卸载脚本
├── pyproject.toml                    # Python 包定义 (PEP 621)
├── README.md                         # 安装说明
│
├── dll/                              # 预编译 DLL (按 Allegro 版本)
│   ├── x86/
│   │   └── allegro_ai_bridge.dll    # 32-bit (Allegro 17.x/22.x/23.x/24.x)
│   └── x64/
│       └── allegro_ai_bridge.dll    # 64-bit (备用，当前 Cadence 全系仍为 32-bit)
│
├── skill/                            # SKILL 脚本
│   ├── ai_bridge.il                  # 主桥接脚本 (DLL 加载 + TCP + 聊天 + 命令执行)
│   └── layout.il                     # 自动布局扩展
│
├── src/                              # Python MCP Server 源码
│   └── allegro_mcp/
│       ├── __init__.py               # 包标识 + __version__
│       ├── server.py                 # FastMCP 服务器 (26 MCP Tools)
│       ├── bridge_client.py          # TCP 客户端 + 后台读取线程
│       ├── protocol.py               # JSON 通信协议
│       ├── config.py                 # 集中配置 (去掉硬编码路径)
│       ├── skill_types.py            # SKILL ↔ Python 类型转换
│       ├── function_registry.py      # axl 函数注册表
│       └── generated/
│           └── __init__.py
│
└── bridge_src/                       # C++ DLL 源码 (可选，供高级用户自行编译)
    ├── CMakeLists.txt
    ├── include/
    │   ├── axlplugin.h
    │   ├── allegro_ai_bridge.h
    │   ├── tcp_server.h
    │   └── command_queue.h
    └── src/
        ├── allegro_ai_bridge.cpp
        ├── tcp_server.cpp
        └── command_queue.cpp
```

## 实施计划

### Phase 1: Python MCP Server → pip 可安装包

**目标**: `pip install allegro-ai-bridge` 即可获得 MCP Server

**改动**:

1. **新建 `pyproject.toml`**（放到 `allegro_mcp/` 同级目录）：
   ```toml
   [project]
   name = "allegro-ai-bridge"
   version = "1.0.0"
   requires-python = ">=3.10"
   dependencies = ["mcp>=1.0.0"]
   
   [project.scripts]
   allegro-mcp = "allegro_mcp.server:main"
   ```

2. **`server.py` 末尾添加 `main()` 入口**：
   ```python
   def main():
       mcp.run(transport="stdio")
   
   if __name__ == "__main__":
       main()
   ```

3. **`config.py` 去掉硬编码路径**：`SKILL_DOCS_DIR` 默认值改为 `None`（函数注册表为可选功能），其余配置保持环境变量覆盖。

4. **`function_registry.py` 第 331 行硬编码路径**：改为先检查 `config.SKILL_DOCS_DIR`，为 `None` 时跳过解析，不报错。

5. **创建 `src/allegro_mcp/` 目录**，将 Python 文件移入（保持 `server.py` 作为入口）。

### Phase 2: 安装脚本 `install.ps1`

**目标**: 一键完成所有部署步骤

**功能**:

```
install.ps1 执行流程:
│
├─ 1. 检测环境
│   ├─ 检查 Python 3.10+ 是否可用
│   ├─ 检查 pip 是否可用
│   └─ 从注册表检测 Allegro 安装:
│       HKLM\SOFTWARE\Cadence Design Systems\...
│       或 HKLM\SOFTWARE\WOW6432Node\Cadence Design Systems\...
│
├─ 2. 部署 DLL
│   ├─ 复制 dll/x86/allegro_ai_bridge.dll → %HOME%\pcbenv\
│   └─ 复制 dll/x86/allegro_ai_bridge.dll → %CDSROOT%\tools\bin\ (备选)
│
├─ 3. 部署 SKILL 脚本
│   ├─ 复制 skill/ai_bridge.il → %HOME%\pcbenv\
│   ├─ 复制 skill/layout.il → %HOME%\pcbenv\
│   └─ 检查 allegro.ilinit:
│       ├─ 不存在 → 创建并写入 loadi("ai_bridge.il")
│       └─ 存在但无 ai_bridge → 追加 loadi 行
│
├─ 4. 安装 Python 包
│   ├─ pip install .  (安装 allegro-ai-bridge 包)
│   └─ 记录安装的 python.exe 路径
│
├─ 5. 注册 MCP 配置
│   ├─ 查找 Proma 工作区 mcp.json
│   │   (遍历 %USERPROFILE%\.proma\agent-workspaces\*\mcp.json)
│   ├─ 若已有 allegro-mcp 条目 → 更新
│   └─ 若无 → 添加条目:
│       {
│         "allegro-mcp": {
│           "command": "<python_path>",
│           "args": ["-m", "allegro_mcp.server"],
│           "timeout": 1800,
│           "type": "stdio",
│           "enabled": true
│         }
│       }
│
├─ 6. 验证
│   ├─ pip show allegro-ai-bridge
│   ├─ 检查 DLL 存在于 pcbenv
│   ├─ 检查 ai_bridge.il 存在于 pcbenv
│   └─ 输出: "安装成功！请在 Allegro 中输入 ai_server_start 启动桥接"
│
└─ 7. (可选) 安装到其他 Proma 工作区
    └─ 提示用户选择目标工作区
```

### Phase 3: 卸载脚本 `uninstall.ps1`

```
uninstall.ps1 执行流程:
│
├─ 1. pip uninstall allegro-ai-bridge
├─ 2. 从 pcbenv 删除 ai_bridge.il, layout.il, allegro_ai_bridge.dll
├─ 3. 从 allegro.ilinit 移除 loadi("ai_bridge.il") 行
├─ 4. 从 mcp.json 移除 allegro-mcp 条目
└─ 5. 从 CDSROOT\tools\bin 删除 DLL (如有)
```

### Phase 4: 配置去硬编码

**`config.py` 改动**:

```python
# 当前硬编码
SKILL_DOCS_DIR = os.environ.get(
    "ALLEGRO_SKILL_DOCS",
    r"<YOUR_SKILL_DOCS_DIR>"  # <- moved to ALLEGRO_SKILL_DOCS env var
)

# 改为
SKILL_DOCS_DIR = os.environ.get("ALLEGRO_SKILL_DOCS")  # None = 不加载文档
```

**`function_registry.py` 改动**: 模块级 `_load_all()` 调用加保护：
```python
def _load_all():
    if not SKILL_DOCS_DIR or not os.path.isdir(SKILL_DOCS_DIR):
        return  # 静默跳过，函数注册表为空，不影响 MCP Server 运行
    # ... 原有解析逻辑
```

### Phase 5: README 文档

包含：
- 系统要求（Windows 10+, Python 3.10+, Cadence Allegro 17.2+）
- 安装步骤（解压 → 右键 `install.ps1` → "使用 PowerShell 运行"）
- 使用步骤（启动 Allegro → `ai_server_start` → 在 Proma 中对话）
- 常见问题（端口被占用、DLL 加载失败、防火墙）

## 关键技术决策

| 决策点 | 选择 | 理由 |
|--------|------|------|
| 分发格式 | ZIP + install.ps1 | 不需要额外构建工具，PowerShell 是 Windows 内置 |
| Python 打包 | `pyproject.toml` + `pip install` | 标准 Python 打包，一条命令安装 |
| DLL 架构 | 仅 x86 (32-bit) | Cadence Allegro 全系为 32-bit 进程 |
| MCP 注册 | 自动发现 Proma 工作区 | 遍历 `%USERPROFILE%\.proma\agent-workspaces\*\mcp.json` |
| SKILL 自动加载 | 追加到 allegro.ilinit | 非侵入式，用户已有的 ilinit 不受影响 |
| 端口冲突 | 使用默认 57123，支持环境变量覆盖 | DLL 和 Python 两侧都可通过参数/环境变量改端口 |
| 不打包 Python | 要求用户已安装 Python 3.10+ | 避免体积膨胀（embed Python ~30MB+），用户通常已有 Python |

## 不在此次范围内的改进

- **自动启动 AI Bridge**（Allegro 启动时自动 `ai_server_start`）：可作为后续选项，当前保持用户手动控制
- **Linux 支持**：DLL 改为 .so + 构建脚本适配，后续独立迭代
- **GUI 安装向导**：当前为命令行安装，后续可用 NSIS 包装
- **DLL 数字签名**：当前 DLL 未签名，企业部署可能需要

## 验证方案

1. **打包验证**：将整个目录打包为 ZIP，在另一台电脑（或 VM）解压
2. **安装验证**：运行 `install.ps1`，确认：
   - DLL 复制到 `%HOME%\pcbenv\`
   - SKILL 脚本复制并注册到 `allegro.ilinit`
   - Python 包安装成功（`pip show allegro-ai-bridge`）
   - MCP 配置写入 `mcp.json`
3. **运行验证**：
   - 启动 Allegro → 确认 `ai_bridge.il` 自动加载
   - `ai_server_start` → 确认 TCP 端口 57123 监听
   - Proma 中 `allegro_connect()` → 确认能获取设计信息
4. **卸载验证**：运行 `uninstall.ps1`，确认所有文件/配置已清理
