**English** · [简体中文](README.zh-CN.md)

---

# Allegro AI Bridge

**An MCP bridge that lets AI agents drive Cadence Allegro PCB Editor directly.**

Cadence Allegro is closed-source commercial EDA with no public API: every operation must go through the SKILL interpreter inside a running GUI process. This project injects a small C++ plugin DLL that accepts TCP commands, and wraps it as [MCP](https://modelcontextprotocol.io) tools so any MCP client (Claude Code, Codex, Cursor, ...) can read and modify the design you currently have open.

```text
AI Agent  ──MCP/stdio──►  Python MCP Server (FastMCP)
                                    │ TCP 127.0.0.1:57123
                          C++ Bridge DLL (loaded via axlDllCall)
                                    │ axl* Plugin API
                          Allegro SKILL Engine → PCB database
```

## Why this exists

Open-source EDA already has agent tooling (KiCad, EasyEDA). Closed-source ones do not:

1. **In-process only.** `.brd` is a proprietary binary format; the sole entry point is the SKILL interpreter in the GUI.
2. **SKILL is an orphan language.** A Lisp dialect that lives only inside Allegro — no package manager, no LSP, almost absent from LLM training data.
3. **API churn.** axl function signatures change across major versions.

So the only realistic path is an in-process plugin fed from outside. That is what this does.

## Requirements

- Cadence Allegro PCB Editor (32-bit plugin host) — <!-- TODO: tested version -->
- Windows 10/11 (verified). A Linux branch exists in CMake but is untested.
- Python 3.10+
- Visual Studio 2017+ (32-bit toolchain) to build the DLL

> `axlplugin.h` is Copyright (c) Cadence Design Systems and is **not** shipped here. Point `-DCADENCE_INCLUDE_DIR` at your own installation.

## Quick start

```batch
cd bridge
cmake -B build -G "Visual Studio 17 2022" -A Win32 ^
      -DCADENCE_INCLUDE_DIR="C:/Cadence/SPB_17.4/tools/dfII/include"
cmake --build build --config Release
```

```powershell
powershell -ExecutionPolicy Bypass -File scripts/install.ps1
```

Then in Allegro run `ai_server_start`. You should see `TCP server listening on 127.0.0.1:57123`.

Register the server in your MCP client using `scripts/mcp_config_template.json`.

## Tools (25)

| Group | Tools |
|---|---|
| Connection | `allegro_connect` `allegro_disconnect` `allegro_status` |
| Execution | `allegro_eval` `allegro_call` `allegro_chat_reply` |
| Design read | `allegro_design_info` `allegro_get_nets` `allegro_get_net_info` `allegro_get_components` `allegro_get_component_info` |
| Layers | `allegro_get_layers` `allegro_get_active_layer` `allegro_set_active_layer` `allegro_layer_visible` |
| Selection | `allegro_get_selection` `allegro_clear_selection` `allegro_select_all` `allegro_select_by_name` `allegro_select_at_point` |
| View / measure | `allegro_design_visible` `allegro_zoom_fit` `allegro_design_refresh` `allegro_measure_distance` `allegro_get_object_properties` |

`allegro_eval` runs arbitrary SKILL — that is both the ceiling of this tool and its main risk.

## Safety

- Binds to `127.0.0.1` only.
- `DANGEROUS_FUNCTIONS` in `python/allegro_mcp/config.py` lists mutating calls so an upstream layer can require confirmation.
- Validate on a scratch board first. Agent mistakes on a PCB are not undoable.

## How it works

The SKILL side loads the DLL with `axlDllCall`, starts a TCP listener via `bridge_start(57123)`, and registers an `axlUIWTimerAdd` timer. Each tick calls the non-blocking `bridge_poll()`; the command is executed with `evalstring` and the result goes back through `bridge_respond()`.

A timer is used instead of a blocking socket read on purpose: blocking would freeze Allegro's GUI thread.

## License

MIT, see [LICENSE](LICENSE).

`axlplugin.h` remains Cadence property and is not redistributed. This is an independent unofficial integration, not affiliated with or endorsed by Cadence. Allegro is a trademark of Cadence Design Systems, Inc.