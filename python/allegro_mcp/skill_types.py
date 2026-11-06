# skill_types.py — SKILL ↔ Python 类型转换层

from typing import Any, Union, List, Dict, Optional

# ============================================================
# Python → SKILL 参数转换
# ============================================================

def py_to_skill_value(val: Any) -> str:
    """将 Python 值转换为 SKILL 字面量字符串

    用于构建 SKILL 表达式
    """
    if val is None:
        return "nil"
    if isinstance(val, bool):
        return "t" if val else "nil"
    if isinstance(val, int):
        return str(val)
    if isinstance(val, float):
        return f"{val:g}"
    if isinstance(val, str):
        # 转义双引号
        escaped = val.replace("\\", "\\\\").replace("\"", "\\\"")
        return f'"{escaped}"'
    if isinstance(val, (list, tuple)):
        if len(val) == 2 and all(isinstance(v, (int, float)) for v in val):
            # XY 坐标对
            return f"{val[0]}:{val[1]}"
        # 普通列表
        items = [py_to_skill_value(v) for v in val]
        return f"list({' '.join(items)})"
    if isinstance(val, dict):
        # 关键字参数
        pairs = [f"?{k} {py_to_skill_value(v)}" for k, v in val.items()]
        return " ".join(pairs)
    # 默认
    return f'"{val}"'

# ============================================================
# SKILL 结果 → Python 解析 (基础)
# ============================================================

def skill_result_to_py(result_str: str) -> Any:
    """尝试将 SKILL 返回的字符串解析为 Python 值

    由于结果已经由 DLL 的 build_success_response 序列化,
    返回的是字符串。这里尝试解析为 JSON。
    """
    import json
    if result_str is None:
        return None
    result_str = result_str.strip()
    if result_str == "null":
        return None
    if result_str == "true":
        return True
    if result_str == "nil":
        return None
    # 尝试 JSON 解析
    try:
        return json.loads(result_str)
    except (json.JSONDecodeError, ValueError):
        pass
    # 尝试作为数字
    try:
        return int(result_str)
    except ValueError:
        pass
    try:
        return float(result_str)
    except ValueError:
        pass
    # 返回原始字符串
    return result_str

# ============================================================
# SKILL 表达式构建器
# ============================================================

def build_skill_expression(func_name: str,
                           args: Optional[List[Any]] = None,
                           kwargs: Optional[Dict[str, Any]] = None) -> str:
    """构建一个 SKILL 函数调用表达式"""
    parts = [func_name]
    if args:
        parts.extend(py_to_skill_value(a) for a in args)
    if kwargs:
        parts.extend(f"?{k} {py_to_skill_value(v)}" for k, v in kwargs.items())
    return f"({' '.join(parts)})"

# ============================================================
# SKILL 常用常量映射
# ============================================================

SKILL_TRUE = "t"
SKILL_NIL = "nil"
SKILL_FALSE = "nil"

# 常用查找过滤器
FIND_FILTER_ALL = 'list("noall" "alltypes")'
FIND_FILTER_SYMBOLS = 'list("noall" "symbols")'
FIND_FILTER_NETS = 'list("noall" "nets")'
FIND_FILTER_PINS = 'list("noall" "pins")'
FIND_FILTER_VIAS = 'list("noall" "vias")'
FIND_FILTER_CLINES = 'list("noall" "clines")'
FIND_FILTER_SHAPES = 'list("noall" "shapes")'
FIND_FILTER_TEXT = 'list("noall" "text")'
