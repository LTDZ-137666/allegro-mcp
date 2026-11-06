# protocol.py — JSON 通信协议
# 定义 Python MCP Server <-> Allegro Bridge DLL 之间的请求/响应格式

import json
from typing import Dict, Any, Optional


class AllegroBridgeError(Exception):
    """SKILL 执行层错误"""
    def __init__(self, error_info: Dict[str, Any]):
        self.code = error_info.get("code", -1)
        self.message = error_info.get("message", "Unknown error")
        self.details = error_info
        super().__init__(f"[{self.code}] {self.message}")


class MCPBridgeProtocol:
    """构建和解析 Bridge 通信消息"""

    _counter = 0

    @classmethod
    def _next_id(cls) -> str:
        cls._counter += 1
        return f"req-{cls._counter:04d}"

    @classmethod
    def build_raw_request(cls, expression: str) -> Dict[str, Any]:
        """构建 raw 模式请求 — 直接执行 SKILL 表达式"""
        req_id = cls._next_id()
        return {
            "id": req_id,
            "method": "raw",
            "params": {
                "expression": expression
            }
        }

    @classmethod
    def build_eval_request(cls, expression: str) -> Dict[str, Any]:
        """构建 evalstring 模式请求"""
        req_id = cls._next_id()
        return {
            "id": req_id,
            "method": "evalstring",
            "params": {
                "expression": expression
            }
        }

    @classmethod
    def build_call_request(cls, function: str,
                           args: list = None,
                           kwargs: dict = None) -> Dict[str, Any]:
        """构建 call_function 模式请求"""
        req_id = cls._next_id()
        return {
            "id": req_id,
            "method": "call_function",
            "params": {
                "function": function,
                "args": args or [],
                "kwargs": kwargs or {},
            }
        }

    @classmethod
    def parse_response(cls, response: Dict[str, Any]) -> Dict[str, Any]:
        """解析 Bridge 响应, 提取结果或抛出异常

        Returns:
            {"success": bool, "data": str}

        Raises:
            AllegroBridgeError: SKILL 执行错误
        """
        if response.get("error"):
            raise AllegroBridgeError(response["error"])

        result = response.get("result", {})
        if isinstance(result, dict) and not result.get("success", False):
            return {"success": False, "data": result.get("data", str(result))}

        return result if isinstance(result, dict) else {"success": True, "data": str(result)}
