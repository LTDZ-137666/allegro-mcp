# function_registry.py — axl 函数注册表
# 解析 DOC/FUNCS/*.txt 文件, 提取函数签名、参数、返回值等元数据
# 支持批量自动生成 MCP Tool 定义

import re
import os
import json
from pathlib import Path
from typing import Dict, List, Optional, Any
from dataclasses import dataclass, field, asdict


@dataclass
class FunctionParam:
    name: str
    param_type: str = "string"  # dbid, string, number, boolean, xy, list, symbol
    required: bool = False
    description: str = ""
    enum_values: List[str] = field(default_factory=list)


@dataclass
class FunctionMeta:
    name: str
    category: str = "other"
    description: str = ""
    synopsis: str = ""
    params: List[FunctionParam] = field(default_factory=list)
    returns: str = "t/nil"
    example: str = ""
    version_added: str = ""
    tier: int = 3  # 1=core, 2=common, 3=specialized


FUNCTION_REGISTRY: Dict[str, FunctionMeta] = {}


# ============================================================
# DOC/FUNCS/*.txt 解析器
# ============================================================

def parse_func_file(filepath: Path) -> Optional[FunctionMeta]:
    """解析单个 FUNCS/*.txt 文件为 FunctionMeta"""
    try:
        text = filepath.read_text(encoding="utf-8", errors="replace")
    except Exception:
        return None

    meta = FunctionMeta(name=filepath.stem)

    # 提取 NAME
    m = re.search(r'NAME\s*\n\s+(\w+)\s+-?\s*(.*)', text)
    if m:
        meta.name = m.group(1)
        meta.description = m.group(2).strip()

    # 提取 SYNOPSIS
    m = re.search(
        r'SYNOPSIS\s*\n(.*?)(?=^\s{2}(?:FUNCTION|NEEDS|RETURNS|EXAMPLE|SEE|CAUTION|TIPS))',
        text, re.DOTALL | re.MULTILINE)
    if not m:
        m = re.search(r'SYNOPSIS\s*\n(.*?)(?=\n\s{2}[A-Z])', text, re.DOTALL)
    if m:
        meta.synopsis = m.group(1).strip()

    # 提取 NEEDS (参数)
    m = re.search(
        r'NEEDS\s*\n(.*?)(?=^\s{2}(?:RETURNS|EXAMPLE|SEE|CAUTION|TIPS|APPLICATION))',
        text, re.DOTALL | re.MULTILINE)
    if m:
        meta.params = _parse_needs(m.group(1))

    # 提取 RETURNS
    m = re.search(
        r'RETURNS\s*\n(.*?)(?=^\s{2}(?:EXAMPLE|SEE|CAUTION|TIPS|APPLICATION))',
        text, re.DOTALL | re.MULTILINE)
    if m:
        meta.returns = m.group(1).strip()[:200]

    # 提取 EXAMPLE
    m = re.search(
        r'EXAMPLE\s*\n(.*?)(?=\n\s{2}[A-Z]|\Z)',
        text, re.DOTALL | re.MULTILINE)
    if m:
        meta.example = m.group(1).strip()[:500]

    # 确定分类
    meta.category = _categorize_function(meta.name)

    # 确定 Tier
    meta.tier = _determine_tier(meta.name, meta.category)

    return meta


def _parse_needs(needs_text: str) -> List[FunctionParam]:
    """解析 NEEDS 部分为参数列表"""
    params = []
    lines = needs_text.strip().split('\n')
    for line in lines:
        line = line.strip()
        if not line:
            continue
        # 匹配: o_name - description 或 t_name - description
        m = re.match(r'(\w+)\s*-\s*(.*)', line)
        if m:
            name = m.group(1)
            desc = m.group(2).strip()
            param_type = _infer_type_from_name(name)
            required = not 'optional' in line.lower()
            params.append(FunctionParam(
                name=name,
                param_type=param_type,
                required=required,
                description=desc[:100]
            ))
    return params


def _infer_type_from_name(name: str) -> str:
    """根据参数名前缀推断类型"""
    name_lower = name.lower()
    if name_lower.startswith('o_') or name_lower.startswith('lo_'):
        return 'dbid'  # object/lisp object
    if name_lower.startswith('t_'):
        return 'string'  # text
    if name_lower.startswith('f_'):
        return 'number'  # float
    if name_lower.startswith('x_'):
        return 'number'
    if name_lower.startswith('n_'):
        return 'number'
    if name_lower.startswith('l_'):
        return 'list'  # list
    if name_lower.startswith('s_'):
        return 'symbol'
    if name_lower.startswith('g_'):
        return 'boolean'  # general
    return 'string'


def _categorize_function(name: str) -> str:
    """根据函数名确定分类"""
    lower = name.lower()
    if lower.startswith('axldbget') or lower.startswith('axldbis'):
        return 'database_read'
    if lower.startswith('axldbcreate'):
        return 'database_create'
    if lower.startswith('axldb'):
        return 'database'
    if lower.startswith('axlcns'):
        return 'constraints'
    if lower.startswith('axlform'):
        return 'forms'
    if lower.startswith('axluiw'):
        return 'ui_window'
    if lower.startswith('axluimenu'):
        return 'ui_menu'
    if lower.startswith('axlui'):
        return 'ui'
    if lower.startswith('axlsetfindfilter') or lower.startswith('axlgetselfilter'):
        return 'selection'
    if lower.startswith('axladdselect') or lower.startswith('axlsingleselect'):
        return 'selection'
    if lower.startswith('axlgetsel') or lower.startswith('axlclearsel'):
        return 'selection'
    if lower.startswith('axlenter'):
        return 'interactive'
    if lower.startswith('axlpath'):
        return 'geometry_path'
    if lower.startswith('axlpoly') or lower.startswith('axlgeo'):
        return 'geometry'
    if lower.startswith('axlchange') or lower.startswith('axldelete') or lower.startswith('axlcopy'):
        return 'edit'
    if lower.startswith('axlcmd') or lower.startswith('axlshell'):
        return 'commands'
    if lower.startswith('axlgetparam') or lower.startswith('axlsetparam'):
        return 'parameters'
    if lower.startswith('axlis') or lower.startswith('axlok') or lower.startswith('axlcheck'):
        return 'predicates'
    if lower.startswith('axlzoom'):
        return 'display'
    if lower.startswith('axlvisible'):
        return 'display'
    if lower.startswith('axltrigger'):
        return 'triggers'
    if lower.startswith('axldll'):
        return 'plugin'
    if lower.startswith('axlairgap') or lower.startswith('axlmath'):
        return 'geometry'
    if lower.startswith('axlbackdrill'):
        return 'manufacturing'
    if lower.startswith('axlbga'):
        return 'manufacturing'
    return 'other'


def _determine_tier(name: str, category: str) -> int:
    """确定函数的重要性层级"""
    tier1_categories = {
        'database_read', 'database_create', 'selection',
        'display', 'edit', 'commands'
    }
    tier1_functions = {
        'axlDBGetDesign', 'axlGetSelSet', 'axlClearSelSet',
        'axlSetFindFilter', 'axlAddSelectAll', 'axlVisibleDesign',
        'axlVisibleLayer', 'axlGetActiveLayer', 'axlSetActiveLayer',
        'axlDBCreateLine', 'axlDBCreatePath', 'axlDBCreateVia',
        'axlDBCreateSymbol', 'axlDBCreateShape', 'axlDeleteObject',
        'axlCmdRegister', 'axlShell', 'axlZoomFit', 'axlAirGap',
    }
    if name in tier1_functions:
        return 1
    if category in tier1_categories:
        return 2
    return 3


# ============================================================
# 批量加载
# ============================================================

def load_function_registry(funcs_dir: str) -> Dict[str, FunctionMeta]:
    """从 DOC/FUNCS/ 目录加载所有函数元数据"""
    funcs_path = Path(funcs_dir)
    if not funcs_path.exists():
        print(f"WARNING: FUNCS directory not found: {funcs_dir}")
        return FUNCTION_REGISTRY

    count = 0
    for txt_file in sorted(funcs_path.glob("*.txt")):
        meta = parse_func_file(txt_file)
        if meta:
            FUNCTION_REGISTRY[meta.name] = meta
            count += 1

    print(f"Loaded {count} function definitions from {funcs_dir}")
    return FUNCTION_REGISTRY


def get_function(name: str) -> Optional[FunctionMeta]:
    """获取单个函数的元数据"""
    return FUNCTION_REGISTRY.get(name)


def get_functions_by_category(category: str) -> List[FunctionMeta]:
    """获取指定分类的所有函数"""
    return [m for m in FUNCTION_REGISTRY.values() if m.category == category]


def get_functions_by_tier(tier: int) -> List[FunctionMeta]:
    """获取指定层级的所有函数"""
    return [m for m in FUNCTION_REGISTRY.values() if m.tier == tier]


def list_categories() -> List[str]:
    """列出所有函数分类"""
    cats = set(m.category for m in FUNCTION_REGISTRY.values())
    return sorted(cats)


# ============================================================
# MCP Tool 代码生成
# ============================================================

def generate_tool_code(meta: FunctionMeta) -> str:
    """为单个函数生成 MCP Tool Python 代码"""
    params = []
    doc_lines = [f'    """{meta.description}']
    doc_lines.append(f"")
    if meta.synopsis:
        doc_lines.append(f"    Synopsis: {meta.synopsis[:200]}")
    if meta.params:
        doc_lines.append(f"")
        doc_lines.append(f"    Args:")
        for p in meta.params:
            req = "Required" if p.required else "Optional"
            doc_lines.append(f"        {p.name}: ({p.param_type}, {req}) {p.description}")
    if meta.returns:
        doc_lines.append(f"")
        doc_lines.append(f"    Returns: {meta.returns}")
    doc_lines.append(f'    """')

    # 参数列表
    for p in meta.params:
        default = '""' if p.param_type == 'string' else "0" if p.param_type in ('number', 'int') else "None"
        if not p.required:
            params.append(f"{p.name}: str = {default}")
        else:
            params.append(f"{p.name}: str")

    param_str = ", ".join(params) if params else ""

    code = f'''
@mcp.tool()
def {meta.name}({param_str}) -> str:
{doc_lines}
    args = [{', '.join(f'"{p.name}"' for p in meta.params)}]
    kwargs = {{}}
    return allegro_call("{meta.name}", *args)
'''
    return code.strip()


def generate_all_tools(output_dir: str, tier_filter: Optional[int] = None):
    """为所有注册函数生成 MCP Tool 代码文件"""
    import os
    os.makedirs(output_dir, exist_ok=True)

    for category in list_categories():
        funcs = get_functions_by_category(category)
        if tier_filter:
            funcs = [f for f in funcs if f.tier <= tier_filter]
        if not funcs:
            continue

        path = os.path.join(output_dir, f"{category}_tools.py")
        with open(path, "w", encoding="utf-8") as fp:
            fp.write(f'# Auto-generated MCP Tools: {category}\n')
            fp.write(f'# Do not edit manually\n\n')
            fp.write(f'from server import mcp\n\n')
            for f in funcs:
                fp.write(generate_tool_code(f) + "\n\n")

        print(f"  Generated {len(funcs)} tools → {path}")


# ============================================================
# 初始加载 (如果 FUNCS 目录存在)
# ============================================================
import config as _config

funcs_dir = _config.SKILL_DOCS_DIR
if funcs_dir and os.path.isdir(funcs_dir):
    print(f"Loading function registry from {funcs_dir} ...")
    load_function_registry(funcs_dir)
    print(f"  Total: {len(FUNCTION_REGISTRY)} functions, "
          f"{len(list_categories())} categories")
