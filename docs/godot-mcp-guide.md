# Godot MCP Reference

For agents working in Godot projects with `@satelliteoflove/godot-mcp` + `@ryanmazzolini/minimal-godot-mcp` MCP servers and the `godot_mcp` addon (`addons/godot_mcp/`).

## The two servers

- **godot-mcp** — drives the editor via WebSocket bridge (port 6550). Tools: `scene`, `node`, `scene3d`, `editor`, `resource`, `project`, `input`, `godot_docs`, plus 2D (`tilemap`, `gridmap`), `animation`, `profiler`.
- **minimal-godot-mcp** — filesystem-based. Tools: GDScript diagnostics, runtime console output capture.

## Critical gotchas

- **Single-client WS bridge.** "Another MCP server connected and replaced this one" = another process holds the slot. Tell user to run `godot-mcp-clean` then `/mcp`.
- **`node.get_properties` returns edit-time state, not runtime.** A script flipping `Camera.current = true` at runtime won't show. Use screenshots + console for runtime verification.
- **`editor.run` ignores recent `project.godot` edits** — the editor caches settings in memory. Pass `scene_path` explicitly to `editor.run`.
- **`editor.run` / `editor.stop` reverts `current_scene` to the project's main scene** (the one in `project.godot`'s `run/main_scene`), even if a different scene was being edited. After a run/stop cycle, re-`scene.open` your working scene before further `node.*` calls — otherwise `parent_path: /root/YourScene` will fail with `NODE_NOT_FOUND`.
- **`scene.open` on a `.glb` silently no-ops.** The tool returns `Opened scene: ...` but `current_scene` and `open_scenes` are unchanged — `.glb`s are read-only PackedScene imports. To inspect their contents, instance the glb as a child of a regular `.tscn` and walk it with `node.find`.
- **Capture `print()` via `mcp__godot__get_console_output`**, not `editor.get_log_messages` (mostly LSP noise). **Gotcha 1:** print() output is captured under `category: "stdout"`, not `category: "console"` — calling with `category: "console"` returns `entries: []` even when `total_buffered > 0`. Omit the category filter or use `"stdout"`. **Gotcha 2:** there's a startup delay before the buffer populates — querying immediately after `editor.run` can return `total_buffered: 0` for ~1–2s even though the game has already printed. **Gotcha 3 (worse failure mode):** when the scene was launched via godot-mcp's `editor.run` (vs. F5 in-editor), `get_console_output` can return `{"entries": [], "total_buffered": 0, "error": "No active debug session..."}` even though `editor.get_state` reports `is_playing: true`. The minimal-godot-mcp session tracker doesn't register MCP-launched sessions. For these cases the (deprecated) `mcp__godot-mcp__editor get_debug_output` pulls via the in-engine bridge and works regardless of how the game was started.
- **Hand-authored `.tscn` `Transform3D` basis must be exactly orthonormal.** Drift like `(1.00009, 0.99966, 0.99997)` axis lengths can leave the game viewport rendering gray (no scene visible). After hand-authoring a scene, save it once via the editor (or `mcp__godot-mcp__scene save` after a `node.update`) to let Godot normalize the basis and add `unique_id`s.
- **Editor must be running** for any `godot-mcp__*` tool to work. `godot__*` tools are filesystem-only and don't need it.
- **Triggering Godot's FS scan after dropping a new asset.** A fresh `.glb` in `models/` is not picked up by the MCP-connected editor automatically — referencing it via `node.create scene_path=...` fails with `SCENE_NOT_FOUND` until the editor's FS watcher fires. On macOS: `osascript -e 'tell application "Godot" to activate'` from `Bash` wakes the watcher and triggers import in ~1s. Alternatives: reopen the project, or run `EditorInterface.get_resource_filesystem().scan()` from the Script editor (no direct MCP affordance).

## Reading errors when the scene fails to load

`mcp__godot__get_console_output` only sees stdout from a *running* game. If F5 fails or the user reports a parse error / "scene doesn't load", the buffer is just the engine boot banner — the actual cause is in the editor-side error log. Reach for these instead:

- `mcp__godot-mcp__editor get_errors` — full error log with `file` + `line` for parser errors, plus engine cpp errors. **Primary tool when scene won't start.**
- `mcp__godot-mcp__editor get_stack_trace` — most recent debugger crash with frames.
- `mcp__godot-mcp__editor get_log_messages source="editor"` — editor-side log: script load failures, library conflicts, etc.

These work whether or not anything is running.

**`mcp__godot__get_diagnostics` is not authoritative.** It catches LSP-visible errors in a single file but misses engine-side parse failures that involve cross-script symbol resolution. Example: `_player.is_steering()` where `_player` is typed `CharacterBody3D` and `player.gd` has no `class_name` — `is_steering()` resolves to Variant at engine parse time, breaks `:=` inference, fails to load the script. `get_diagnostics` reports the file clean. **After writing GDScript that touches another script's exports / methods / signals, cross-check `get_errors` before declaring success.**

Proactively reach for `get_errors` when the user reports failure — don't wait to be asked.

## Property formats (`node.update properties={...}`)

- Vector3/Vector2: dict `{"x":,"y":,"z":}` / `{"x":,"y":}`
- Color: dict `{"r":,"g":,"b":,"a":}`
- Resource refs (`mesh`, `material_override`, `environment`, ...): plain path string `"res://..."` — auto-loaded
- Enums: integers (Camera3D `projection`: 0=perspective, 1=orthographic)
- `rotation_degrees` as Vector3; default Euler order is YXZ (rotation_order=2)

## Read-only MCP tools (use file Write/Edit instead)

- `resource` (only `get_info`). Create shaders/materials/meshes as `.tres` via `Write`. **Gotcha:** `get_info` on `StandardMaterial3D` (and probably other resources) underreports — it omits texture-channel masks, `emission_energy_multiplier`, `normal_enabled`/`normal_scale`, `metallic_texture`/`roughness_texture` slots, etc. For full introspection, run the scene and dump `mesh.surface_get_material(i)` properties via GDScript `print()`. Treat runtime as authoritative.
- `project` (only `get_info`, `get_settings`, `addon_status`). Edit `project.godot` directly for main_scene, input map, autoloads, plugins.

## Input testing

`mcp__godot-mcp__input` injects **named actions** from the Input Map, not raw keycodes. To support both MCP testing and direct user keypresses, check both `event.is_action_pressed("foo")` AND `event.keycode == KEY_X` in the handler.

## Common `.tres` patterns

```
[gd_resource type="PlaneMesh" format=3]
[resource]
size = Vector2(100, 100)
```

```
[gd_resource type="ShaderMaterial" load_steps=2 format=3]
[ext_resource type="Shader" path="res://shaders/grid.gdshader" id="1"]
[resource]
shader = ExtResource("1")
```

```
[gd_resource type="Environment" load_steps=3 format=3]
[sub_resource type="ProceduralSkyMaterial" id="m"]
[sub_resource type="Sky" id="s"]
sky_material = SubResource("m")
[resource]
background_mode = 2
sky = SubResource("s")
```

## Recommended directory layout

`scenes/` `scripts/` `scripts/shaders/` `materials/` `meshes/` `environments/`

For the Blender → Godot pipeline (where source files live, what crosses, naming discipline): see `asset-pipeline.md`.

## New-project setup checklist

1. `.mcp.json` with both servers
2. `addons/godot_mcp/` present; enabled in `[editor_plugins]`
3. `MCPGameBridge` autoload registered
4. This guide copied to `docs/godot-mcp-guide.md`; `CLAUDE.md` references it
5. `docs/blender-mcp-guide.md` copied if the project uses Blender as a DCC source
6. `docs/asset-pipeline.md` copied for Blender → Godot pipeline conventions
7. `godot-gdscript-patterns` skill installed globally; `CLAUDE.md` references it for GDScript context
8. `godot-animation-tree-mastery` skill installed globally; `CLAUDE.md` references it for AnimationTree context
