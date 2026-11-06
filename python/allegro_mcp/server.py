# allegro_mcp — Python MCP Server for Allegro PCB Editor
# 通过 TCP 连接 Allegro AI Bridge DLL, 将 SKILL 函数暴露为 MCP Tools

# server.py — FastMCP 服务器主入口

import sys
import os

# 将当前目录加入路径
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from mcp.server.fastmcp import FastMCP
from bridge_client import AllegroBridgeClient, BridgeError
from protocol import MCPBridgeProtocol, AllegroBridgeError

# ============================================================
# FastMCP 服务器
# ============================================================
mcp = FastMCP(
    "Allegro PCB Editor",
    instructions="""
    You are connected to Cadence Allegro PCB Editor via the AI Bridge.

    You can:
    - Read PCB design data (nets, components, layers, properties)
    - Create/modify PCB objects (lines, shapes, vias, symbols)
    - Query design rules and constraints
    - Execute any SKILL expression directly

    IMPORTANT:
    - Call allegro_connect() first before any other tool.
    - Use object references by name (e.g. "U1", "GND", "R5.2") not raw DBIDs.
    - Coordinates are [x, y] pairs in design units.
    - Layers are strings like "ETCH/TOP", "BOARD GEOMETRY/OUTLINE".
    - After making changes, call allegro_design_refresh() to update the display.
    """,
)

# 全局 Bridge 客户端
bridge = AllegroBridgeClient()

# ============================================================
# 连接管理工具
# ============================================================

@mcp.tool()
def allegro_connect(port: int = 57123) -> str:
    """Connect to an Allegro PCB Editor instance.

    Before using any other tools, you must call this to establish
    the connection. Allegro must be running with the AI Bridge loaded
    (ai_server_start command in Allegro).

    Args:
        port: TCP port number (default 57123, must match Allegro side)
    """
    if bridge.connected:
        bridge.disconnect()

    try:
        ok = bridge.connect(port=port, timeout=5.0)
        if ok:
            # Ping 验证
            result = bridge.send_command(
                MCPBridgeProtocol.build_raw_request("1+1")
            )
            return f"Connected to Allegro PCB Editor on localhost:{port}"
        else:
            return f"Connection failed. Is Allegro running with ai_server_start?"
    except Exception as e:
        return f"Connection error: {e}"

@mcp.tool()
def allegro_disconnect() -> str:
    """Disconnect from Allegro PCB Editor."""
    bridge.disconnect()
    return "Disconnected from Allegro"

@mcp.tool()
def allegro_status() -> str:
    """Check the current connection status to Allegro."""
    msgs = bridge.pop_chat_messages() if bridge.connected else []
    status = "Connected to Allegro" if bridge.connected else "Not connected. Use allegro_connect() to connect."
    if msgs:
        status += f"\n\n**Chat messages from Allegro:**"
        for m in msgs:
            status += f"\n> {m}"
        status += "\n\n*Respond to these using allegro_chat_reply()*"
    return status

@mcp.tool()
def allegro_chat_reply(reply: str) -> str:
    """Send a reply message to the Allegro AI Chat window.

    Args:
        reply: The message to display in Allegro's chat window
    """
    if not bridge.connected:
        return "Error: Not connected"
    try:
        bridge.send_display(reply)
        return f"Sent to Allegro: {reply}"
    except Exception as e:
        return f"Error: {e}"

# ============================================================
# Tier 3: 通用执行工具
# ============================================================

@mcp.tool()
def allegro_eval(expression: str) -> str:
    """Execute an arbitrary SKILL expression directly in Allegro.
    Also checks for and processes any chat messages from the Allegro chat window.

    Args:
        expression: A valid SKILL Lisp expression to evaluate.
    """
    if not bridge.connected:
        return "Error: Not connected. Use allegro_connect() first."

    try:
        request = MCPBridgeProtocol.build_raw_request(expression)
        response = bridge.send_command(request)
        result = MCPBridgeProtocol.parse_response(response)

        # 检查是否有来自 Allegro 聊天框的消息
        msgs = bridge.pop_chat_messages()
        chat_info = ""
        if msgs:
            chat_info = "\n\n**Allegro User says:**"
            for m in msgs:
                chat_info += f"\n> {m}"
            chat_info += "\n\n*Use allegro_chat_reply() to respond, or execute SKILL commands to help.*"

        if result.get("success"):
            return str(result.get("data", "null")) + chat_info
        else:
            return f"SKILL Error: {result.get('data', 'Unknown')}" + chat_info
    except AllegroBridgeError as e:
        return f"Error (code {e.code}): {e.message}"
    except BridgeError as e:
        return f"Connection Error: {e}"

@mcp.tool()
def allegro_call(function: str, *args: str) -> str:
    """Call a named Allegro SKILL function with string arguments.

    Args:
        function: The axl function name (e.g. "axlGetActiveLayer", "axlGetSelSet")
        *args: String arguments to pass to the function
    """
    if not bridge.connected:
        return "Error: Not connected. Use allegro_connect() first."

    try:
        # 构建 SKILL 函数调用表达式
        skill_args = " ".join(args) if args else ""
        expr = f"({function} {skill_args})"

        request = MCPBridgeProtocol.build_raw_request(expr)
        response = bridge.send_command(request)
        result = MCPBridgeProtocol.parse_response(response)

        if result.get("success"):
            return str(result.get("data", "null"))
        else:
            return f"SKILL Error: {result.get('data', 'Unknown')}"
    except AllegroBridgeError as e:
        return f"Error (code {e.code}): {e.message}"
    except BridgeError as e:
        return f"Connection Error: {e}"

# ============================================================
# Tier 1: 核心数据库读取工具
# ============================================================

@mcp.tool()
def allegro_design_info() -> str:
    """Get basic information about the currently open PCB design.

    Returns design name, units, accuracy, extents, and layer count.
    """
    expr = """
    (let (dsn)
        dsn = axlDBGetDesign()
        strcat("Design: " dsn->name "\\n"
               "Units: " symbolToString(axlDBGetDesignUnits()) "\\n"
               "Accuracy: " axlDBGetDesignAccuracy() "\\n"
               "Extents: " axlDBGetExtents() "\\n"
               "Layers: " length(axlGetAllLayers()) "\\n"
               "Nets: " length(dsn->nets) "\\n"
               "Components: " length(dsn->symbols)
        )
    )
    """
    return allegro_eval(expr.strip())

@mcp.tool()
def allegro_get_nets() -> str:
    """Get a list of all net names in the current PCB design."""
    expr = "(axlDBGetDesign())->nets~>name"
    return allegro_eval(expr)

@mcp.tool()
def allegro_get_net_info(net_name: str) -> str:
    """Get detailed information about a specific net.

    Args:
        net_name: The net name (e.g. "GND", "VCC", "CLK")
    """
    expr = f"""
    (let (net dsn)
        dsn = axlDBGetDesign()
        net = nil
        foreach(n dsn->nets
            when(n->name == "{net_name}"
                net = n
                return()
            )
        )
        if(net then
            strcat("Name: " net->name "\\n"
                   "Branches: " length(net->branches) "\\n"
                   "TotalEtchLength: " axlDBGetLength(net) "\\n"
                   "DifferentialPair: " if(net->diffPair then "yes" else "no")
            )
        else
            "Net '{net_name}' not found"
        )
    )
    """
    return allegro_eval(expr.strip())

@mcp.tool()
def allegro_get_components() -> str:
    """Get a list of all component reference designators (RefDes) in the design."""
    expr = "(axlDBGetDesign())->symbols~>name"
    return allegro_eval(expr)

@mcp.tool()
def allegro_get_component_info(refdes: str) -> str:
    """Get detailed information about a specific component.

    Args:
        refdes: Component reference designator (e.g. "U1", "R5")
    """
    expr = f"""
    (let (sym dsn)
        dsn = axlDBGetDesign()
        sym = nil
        foreach(s dsn->symbols
            when(s->name == "{refdes}"
                sym = s
                return()
            )
        )
        if(sym then
            strcat("RefDes: " sym->name "\\n"
                   "Location: " sym->xy "\\n"
                   "Rotation: " sym->rotation "\\n"
                   "Mirrored: " sym->isMirrored "\\n"
                   "Package: " sym->package "\\n"
                   "Pins: " length(sym->pins)
            )
        else
            "Component '{refdes}' not found"
        )
    )
    """
    return allegro_eval(expr.strip())

@mcp.tool()
def allegro_get_layers() -> str:
    """Get a list of all layers in the current design."""
    expr = "axlGetAllLayers()"
    return allegro_eval(expr)

@mcp.tool()
def allegro_get_active_layer() -> str:
    """Get the currently active layer."""
    return allegro_call("axlGetActiveLayer")

@mcp.tool()
def allegro_set_active_layer(layer: str) -> str:
    """Set the active layer.

    Args:
        layer: Layer name (e.g. "ETCH/TOP", "BOARD GEOMETRY/OUTLINE")
    """
    return allegro_eval(f"axlSetActiveLayer(\"{layer}\")")

# ============================================================
# Tier 1: 选择工具
# ============================================================

@mcp.tool()
def allegro_get_selection() -> str:
    """Get the current selection set (objects currently selected in Allegro)."""
    return allegro_eval("axlGetSelSet()")

@mcp.tool()
def allegro_clear_selection() -> str:
    """Clear the current selection set."""
    return allegro_eval("axlClearSelSet()")

@mcp.tool()
def allegro_select_all() -> str:
    """Select all objects in the design."""
    return allegro_eval("axlAddSelectAll()")

@mcp.tool()
def allegro_select_by_name(refdes: str) -> str:
    """Select a component by its reference designator.

    Args:
        refdes: Component RefDes (e.g. "U1", "U1.5" for a specific pin)
    """
    expr = f"""
    axlClearSelSet()
    axlSetFindFilter(?enabled list("noall" "alltypes") ?onButtons list("alltypes"))
    axlSingleSelectName("REFDES" "{refdes}")
    axlGetSelSet()
    """
    return allegro_eval(expr.strip())

@mcp.tool()
def allegro_select_at_point(x: float, y: float) -> str:
    """Select objects at a specific coordinate point.

    Args:
        x: X coordinate in design units
        y: Y coordinate in design units
    """
    expr = f"""
    axlClearSelSet()
    axlSetFindFilter(?enabled list("noall" "alltypes") ?onButtons list("alltypes"))
    axlSingleSelectPoint({x}:{y})
    axlGetSelSet()
    """
    return allegro_eval(expr.strip())

# ============================================================
# Tier 1: 可见性与显示
# ============================================================

@mcp.tool()
def allegro_design_visible(visible: bool = True) -> str:
    """Show or hide the entire design.

    Args:
        visible: True to show, False to hide all objects
    """
    skill_bool = "t" if visible else "nil"
    return allegro_eval(f"axlVisibleDesign({skill_bool})")

@mcp.tool()
def allegro_layer_visible(layer: str, visible: bool = True) -> str:
    """Set the visibility of a specific layer.

    Args:
        layer: Layer name (e.g. "ETCH/TOP")
        visible: True to show, False to hide
    """
    skill_bool = "t" if visible else "nil"
    return allegro_eval(f"axlVisibleLayer(\"{layer}\" {skill_bool})")

@mcp.tool()
def allegro_zoom_fit() -> str:
    """Zoom to fit the entire design."""
    return allegro_eval("axlZoomFit()")

@mcp.tool()
def allegro_design_refresh() -> str:
    """Refresh the display (redraw everything)."""
    return allegro_eval("axlUIWRedraw(nil)")

# ============================================================
# Tier 1: 测量与几何
# ============================================================

@mcp.tool()
def allegro_measure_distance(x1: float, y1: float, x2: float, y2: float) -> str:
    """Measure the distance between two points.

    Args:
        x1, y1: First point coordinates
        x2, y2: Second point coordinates
    """
    expr = f"sqrt((({x2}-{x1})**2 + ({y2}-{y1})**2))"
    return allegro_eval(expr)

@mcp.tool()
def allegro_get_object_properties(refdes: str) -> str:
    """Get all properties of a component.

    Args:
        refdes: Component reference designator (e.g. "U1")
    """
    expr = f"""
    (let (sym)
        axlClearSelSet()
        axlSetFindFilter(?enabled list("noall" "symbols") ?onButtons list("symbols"))
        axlSingleSelectName("REFDES" "{refdes}")
        sym = car(axlGetSelSet())
        axlClearSelSet()
        if(sym then
            sym->prop->??
        else
            nil
        )
    )
    """
    return allegro_eval(expr.strip())

# ============================================================
# 启动入口
# ============================================================
def main():
    """Entry point for 'allegro-mcp' console script."""
    mcp.run(transport="stdio")

if __name__ == "__main__":
    main()
