# tests/test_bridge_client.py — Tests for TCP Bridge Client
# 需要 Allegro 正在运行且 ai_server_start 已启动

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from bridge_client import AllegroBridgeClient, BridgeError
from protocol import MCPBridgeProtocol, AllegroBridgeError


def test_connection():
    """测试基本连接"""
    client = AllegroBridgeClient()
    try:
        connected = client.connect(timeout=3.0)
        print(f"Connection: {'OK' if connected else 'FAILED'}")
        return client if connected else None
    except Exception as e:
        print(f"Connection error: {e}")
        return None


def test_ping(client):
    """测试 ping"""
    req = MCPBridgeProtocol.build_raw_request("1+1")
    try:
        resp = client.send_command(req)
        result = MCPBridgeProtocol.parse_response(resp)
        print(f"Ping: {'OK' if result.get('success') else 'FAILED'}")
        print(f"  1+1 = {result.get('data')}")
    except Exception as e:
        print(f"Ping error: {e}")


def test_design_info(client):
    """测试获取设计信息"""
    req = MCPBridgeProtocol.build_raw_request(
        "(axlDBGetDesign())->name"
    )
    try:
        resp = client.send_command(req)
        result = MCPBridgeProtocol.parse_response(resp)
        print(f"Design info: {'OK' if result.get('success') else 'FAILED'}")
        print(f"  Design name: {result.get('data')}")
    except Exception as e:
        print(f"Design info error: {e}")


def test_net_list(client):
    """测试获取网表"""
    req = MCPBridgeProtocol.build_raw_request(
        "(axlDBGetDesign())->nets~>name"
    )
    try:
        resp = client.send_command(req)
        result = MCPBridgeProtocol.parse_response(resp)
        print(f"Net list: {'OK' if result.get('success') else 'FAILED'}")
        print(f"  Data: {result.get('data', 'N/A')[:200]}")
    except Exception as e:
        print(f"Net list error: {e}")


def test_error_handling(client):
    """测试错误处理"""
    req = MCPBridgeProtocol.build_raw_request(
        "this_is_not_a_valid_skill_function()"
    )
    try:
        resp = client.send_command(req)
        result = MCPBridgeProtocol.parse_response(resp)
        print(f"Error handling: OK (unexpected success)")
    except AllegroBridgeError as e:
        print(f"Error handling: OK (got expected error: {e})")
    except BridgeError as e:
        print(f"Error handling: Connection error: {e}")


def run_all():
    print("=" * 50)
    print("Allegro AI Bridge — Client Tests")
    print("=" * 50)

    client = test_connection()
    if not client:
        print("\nAll tests skipped (not connected)")
        return

    print()
    test_ping(client)
    print()
    test_design_info(client)
    print()
    test_net_list(client)
    print()
    test_error_handling(client)

    client.disconnect()
    print("\nDone.")


if __name__ == "__main__":
    run_all()
