# config.py — Allegro MCP Server 配置

import os
from pathlib import Path

# TCP 连接配置
BRIDGE_HOST = os.environ.get("ALLEGRO_BRIDGE_HOST", "127.0.0.1")
BRIDGE_PORT = int(os.environ.get("ALLEGRO_BRIDGE_PORT", "57123"))
BRIDGE_TIMEOUT = float(os.environ.get("ALLEGRO_BRIDGE_TIMEOUT", "30.0"))

# SKILL 函数文档路径 (可选 — 为空则跳过函数注册表自动生成)
SKILL_DOCS_DIR = os.environ.get("ALLEGRO_SKILL_DOCS")

# 是否启用调试日志
DEBUG = os.environ.get("ALLEGRO_MCP_DEBUG", "0") == "1"

# 最大 SKILL 执行超时 (秒)
MAX_EXECUTION_TIMEOUT = int(os.environ.get("ALLEGRO_MAX_TIMEOUT", "60"))

# 允许的敏感操作 (需要用户确认)
DANGEROUS_FUNCTIONS = [
    "axlSaveDesign",
    "axlShell",
    "axlDeleteObject",
    "axlDBCreateSymbol",
    "axlDBCreateVia",
    "axlDBCreatePath",
    "axlDBCreateLine",
    "axlDBCreateShape",
    "axlDBCreateCloseShape",
    "axlChangeLayer",
    "axlChangeNet",
    "axlChangeWidth",
]
