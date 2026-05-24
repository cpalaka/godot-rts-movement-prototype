# Blender MCP Reference

For agents driving Blender 5.x from a Godot project with the `blender-mcp` server. Companion to `godot-mcp-guide.md` for Blender→Godot asset authoring.

## The server

One MCP server, tool prefix `mcp__blender-mcp__`, bridges to a running Blender instance over **TCP `localhost:9876`** (not the godot-mcp port 6550). Blender must be running with the MCP add-on enabled and connected. Single-client bridge.

Tools fall into five groups:

- **Inspection**: `get_objects_summary`, `get_object_detail_summary`, `get_blendfile_summary_*`
- **Visual feedback**: `get_screenshot_of_window_as_json`, `*_as_image` variants, `render_viewport_to_path`, `render_thumbnail_to_path`
- **Navigation**: `jump_to_tab_*`, `jump_to_view3d_object_*`
- **Docs**: `search_manual_docs`, `search_api_docs`, `get_python_api_docs`
- **Escape hatch**: `execute_blender_code` — runs `bpy` code, returns stdout + JSON

## The cardinal rules

1. **Prefer the data API.** `obj.location = ...`, `obj.scale = ...`, `obj.modifiers.new(...)` via `bpy.data.objects[name]`. No selection dependency, predictable targeting.
2. **`bpy.ops.transform.*` follows current selection, not arguments.** "Scale Cube" without managing selection scales whatever is active. Reserve `bpy.ops` for ops that genuinely need selection context.
3. **Derived reads are stale after mutation.** `matrix_world`, modifier output, parent-relative reads: call `bpy.context.view_layer.update()` or `obj.evaluated_get(depsgraph)`. Direct property reads (`.location`) are immediate.
4. **In Edit Mode, `obj.data.vertices/.edges/.polygons` are FROZEN** at pre-edit-mode snapshot. Bmesh is the live source of truth. `bmesh.update_edit_mesh()` does NOT resync them — `bpy.ops.object.mode_set(mode='OBJECT')` does.
5. **Don't trust default selection.** `obj.select_set(True)` and set `view_layer.objects.active` explicitly before selection-dependent ops. `primitive_*_add` deselects all then selects+activates the new object.

## Critical gotchas

### Schema inconsistencies (all surface as pydantic validation errors)
- `get_object_detail_summary` → `name` (not `object_name`)
- `render_viewport_to_path` / `render_thumbnail_to_path` → `output_path` (not `filepath`)
- `get_screenshot_of_area_as_image` → `area_ui_type` (the `Area.ui_type` enum, e.g. `VIEW_3D`)
- `get_python_api_docs` → `identifier` (exact qualified name, not a query)
- When unsure: call with no args, read the validation error to learn required fields.

### `render_*_to_path` ignores the directory you pass
- Only the basename of `output_path` is honored. Files land in `/var/folders/.../T/blender_<id>/blender_mcp/`.
- Response returns the actual `filepath` so you can copy/move it post-hoc.
- **Canonical fix:** `execute_blender_code` with `bpy.context.scene.render.filepath = "<absolute>"` then `bpy.ops.render.opengl(write_still=True)` (or `render.render(...)` for EEVEE/Cycles).

### Image-returning screenshot tools are flaky
- `get_screenshot_of_area_as_image` failed on `VIEW_3D` with `"Unterminated string at char 60"` — bridge JSON framing breaks for larger base64 payloads.
- Use `get_screenshot_of_window_as_json` for layout intel (no pixels, always reliable).
- Use the render-to-disk pattern + `Read` for actual visual verification.

### bmesh objects don't survive the bridge
- bmesh refs returned from `execute_blender_code` come back as `"<BMVert dead at 0x...>"` strings. Do all bmesh work in a single call; don't try to return live geom.

### glTF importer crashes on `read_homefile(use_empty=True)` + import
- Blender 5.1.2's `bpy.ops.import_scene.gltf` raises `AttributeError: 'Context' object has no attribute 'object'` when invoked into an empty scene — `armature_display` tries to link `bpy.context.object` and it's `None`.
- **Workaround for round-trip verification:** parse the .glb's JSON chunk directly (it's just `struct.unpack` + `json.loads` of the first chunk). Faster, no Blender bug, and what really matters anyway is what Godot will see — Blender re-importing its own export proves little.
- Snippet:
  ```python
  import struct, json
  with open(glb_path, "rb") as f:
      magic, version, total = struct.unpack("<4sII", f.read(12))
      chunk_len, chunk_type = struct.unpack("<I4s", f.read(8))
      gltf = json.loads(f.read(chunk_len))
  # gltf["animations"], gltf["nodes"], gltf["skins"], gltf["meshes"]
  ```

### Coordinate spaces in window JSON
- `get_screenshot_of_window_as_json` returns area coordinates in **OS pixel space** (HiDPI doubled) but `window_width/height` in logical units. Don't naively map between.

### No first-class save tool
- Save via `execute_blender_code`: `bpy.ops.wm.save_as_mainfile(filepath=...)` or `bpy.ops.wm.save_mainfile()`.

### Float32 storage
- `mod.width = 0.1` stores as `0.10000000149011612`. Don't equality-check; use tolerance.

### Rotation reporting
- `get_object_detail_summary` returns rotation as a 3-tuple of **radians**, and does NOT expose `rotation_mode` (Euler order, quaternion, axis-angle). If you need to round-trip rotations, read `obj.rotation_mode` via `execute_blender_code`.

### Mode strings: two flavors
- `bpy.context.mode` is granular: `OBJECT`, `EDIT_MESH`, `EDIT_ARMATURE`, `SCULPT`, etc.
- `obj.mode` is simpler: `OBJECT`, `EDIT`, `SCULPT`, etc.

## Tool surface — when to use what

### Inspection
| Tool | Returns | Use for |
|---|---|---|
| `get_objects_summary` | Scene topology: collections, parents, types, selected/visible flags | "What's in the scene?" |
| `get_object_detail_summary` (`name=`) | Transform (rotation in radians), modifier/constraint/material *names*, three visibility flags | "Where is X and what's attached?" |
| `get_blendfile_summary_path_info` | Filepath, is_saved, is_dirty, age, backups | "Is this saved?" |
| `execute_blender_code` | Anything | **Required** for type-specific properties (camera FOV, light energy, mesh vertex count, modifier params, material shader graph) — no structured tool exposes them. |

### Visual feedback
| Tool | Status | Use for |
|---|---|---|
| `get_screenshot_of_window_as_json` | reliable | Area layout + live view3d state (perspective, view_location, shading). **Hidden gem.** |
| `get_screenshot_of_*_as_image` | flaky | Avoid; bridge framing failures on larger images |
| `render_viewport_to_path` / `render_thumbnail_to_path` | partial | Basename-only path control. Recover file from response. |
| `execute_blender_code` + `scene.render.filepath` + `render.opengl(write_still=True)` + `Read` | canonical | **The verification pattern.** Full path control. |

### Docs
| Tool | Param | Use when |
|---|---|---|
| `search_manual_docs` | `query` | Conceptual / UI / "how does this work" — ranked RST chunks from the user manual |
| `search_api_docs` | `query` | Fuzzy-find the Python API for a concept |
| `get_python_api_docs` | `identifier` | Exact lookup — full signature + typed param docs for a known qualified name |

## Common patterns

### Save the working .blend
```python
bpy.ops.wm.save_as_mainfile(filepath="/abs/path/file.blend")  # first time
bpy.ops.wm.save_mainfile()                                     # subsequent
```

### Render to a controlled path and verify
```python
target = "/abs/path/render.png"
bpy.context.scene.render.filepath = target
bpy.context.scene.render.image_settings.file_format = 'PNG'
bpy.ops.render.opengl(write_still=True)         # fast OpenGL viewport
# or for shaded:
# bpy.ops.render.render(write_still=True)        # EEVEE/Cycles
```
Then `Read` the PNG.

### Edit-mode geometry change (single `execute_blender_code` call)
```python
import bpy, bmesh
obj = bpy.data.objects['Target']
bpy.context.view_layer.objects.active = obj
bpy.ops.object.mode_set(mode='EDIT')

bm = bmesh.from_edit_mesh(obj.data)
# ... bmesh.ops.* edits ...
bmesh.update_edit_mesh(obj.data)   # viewport refresh only

bpy.ops.object.mode_set(mode='OBJECT')   # only now is obj.data resynced
```

### Modifier add + read evaluated result
```python
obj = bpy.data.objects['Target']
mod = obj.modifiers.new(name="Bevel", type='BEVEL')
mod.width = 0.1
mod.segments = 4

print(len(obj.data.vertices))    # raw, unchanged

deps = bpy.context.evaluated_depsgraph_get()
mesh_eval = obj.evaluated_get(deps).data
print(len(mesh_eval.vertices))   # post-modifier
```

### glTF export for Godot
```python
obj = bpy.data.objects['Target']
obj.data.name = "TargetMesh"     # controls Godot import name (see pipeline notes)

bpy.ops.object.select_all(action='DESELECT')
obj.select_set(True)
bpy.context.view_layer.objects.active = obj

bpy.ops.export_scene.gltf(
    filepath="/abs/path/target.glb",
    export_format='GLB',
    use_selection=True,
    export_apply=True,        # bake modifiers
    export_yup=True,          # default; Godot is Y-up
)
```

**Timeout fallback for large meshes:** the MCP bridge can time out on `export_scene.gltf` for larger assets (tens of thousands of verts or above). If the call hangs or returns a transport error, fall back to invoking Blender's headless CLI directly — `blender --background <file>.blend --python <export_script>.py` — rather than routing through `execute_blender_code`. Headless CLI is the canonical escape hatch for export operations that the bridge can't sustain.

## Blender → Godot pipeline notes

- **PBR material export packs metallic + roughness into ONE texture.** If you author separate Image Texture nodes for `Metallic` and `Roughness` inputs on the Principled BSDF, the glTF exporter merges them into a single `metallicRoughnessTexture` (G=roughness, B=metallic per glTF spec) named `<metal_image>-<rough_image>.png` with a hyphen. Godot then points both `metallic_texture` and `roughness_texture` slots at this packed texture with `metallic_texture_channel=2` (blue) and `roughness_texture_channel=1` (green). Authoring separately is fine — just expect the storage merger downstream, and an export warning `"More than one shader node tex image used for a texture. The resulting glTF sampler will behave like the first shader node tex image."` (about which Image Texture node's sampler config wins). The same warning also fires (cosmetically) when a *single* Image Texture node is reused across multiple shader chains — e.g. ORM-packed where one Image is wired to both `Separate Color → Roughness/Metallic` and to a `glTF Material Output.Occlusion` input. Output is correct.
- **AO/Occlusion has no Principled BSDF socket** — the glTF exporter requires a custom node group **literally named `glTF Material Output`** with an input named `Occlusion`. The Image Texture connected there is exported as `occlusionTexture` (R channel). The node group's internal contents don't render; it's a metadata marker. UI affordance: enable `Preferences → Add-ons → Shader Editor Add-ons` to get `Add → Output → glTF Material Output`. Programmatic creation:
  ```python
  ng = bpy.data.node_groups.new(name="glTF Material Output", type='ShaderNodeTree')
  ng.interface.new_socket(name="Occlusion", in_out='INPUT', socket_type='NodeSocketColor')
  ng.nodes.new('NodeGroupInput')   # tree needs at least one input node to be valid
  ng.nodes.new('NodeGroupOutput')
  # Then in your material: nt.nodes.new('ShaderNodeGroup'); inst.node_tree = ng; link Image.Color → inst.inputs['Occlusion']
  ```
  For ORM-packed (R=AO, G=Roughness, B=Metallic), wire the **same** Image Texture to all three uses; Blender's exporter detects the reuse and writes a single shared texture referenced by both `metallicRoughnessTexture` and `occlusionTexture` (same index). The image must be `colorspace='Non-Color'` — data, not sRGB.
- **`emission_strength` survives via `KHR_materials_emissive_strength` glTF extension** and arrives in Godot as `StandardMaterial3D.emission_energy_multiplier`. The `Emission Color` input becomes `emission_texture`, `emission_enabled=true`.
- **Generating PNG textures procedurally in Blender:** `bpy.data.images.new(name, w, h, alpha=True)` + `img.pixels = [r,g,b,a, ...]` (row-major, bottom-row-first per OpenGL convention) + `img.filepath_raw=...` + `img.file_format='PNG'` + `img.save()`. No PIL needed.
- Godot 4.x has a **native Blender importer** — `.blend` files dropped into the project tree get auto-imported as PackedScenes. Often not what you want; prefer explicit glTF export so you control what crosses.
- **Always drop a `.gdignore` (empty file) into the Blender working dir** if the Blender tree lives inside the Godot project. Otherwise the .blend, intermediates, and any rendered PNGs all get imported (PNGs → CompressedTexture2D), polluting `.godot/imported/`. The parallel layout (see `asset-pipeline.md`) avoids this entirely.
- **Mesh datablock name ≠ object name.** The imported MeshInstance3D and `.mesh` resource use the *mesh-data* name (often auto-generated like `Cube.001`). Set `obj.data.name = "X"` before export for clean Godot names.
- **Z-up → Y-up axis conversion** is applied on import (Blender's `+Z` becomes Godot's `+Y`). Account for it when scripting target positions on the Godot side.
- **No MCP-exposed "rescan filesystem" action.** After exporting a new `.glb`, if the editor doesn't pick it up automatically (Godot's FS watcher usually does, but not always — esp. after focus loss), the options are: focus the Godot editor window (cheapest), run `EditorInterface.get_resource_filesystem().scan()` from a one-shot in the Script editor, or reopen the project. The `mcp__godot-mcp__editor` action set doesn't include scan.

## Engine notes (Blender 5.x)

- Available render engines: `BLENDER_EEVEE`, `BLENDER_WORKBENCH`, `CYCLES`. **`BLENDER_EEVEE_NEXT` is gone in 5.x** — the rewrite was consolidated back into `BLENDER_EEVEE`. Code targeting 4.2–4.5 needs an update.
- EEVEE renders at 800×600 / 16 samples in ~0.2s. Usable inline.

## Blender 5.x API drift (vs 4.x training data)

These attributes/operators changed between 4.x and 5.x and trip up `execute_blender_code` snippets written from memory:

- **`Action.id_root` removed.** Was an enum hint (`'OBJECT'`, `'ARMATURE'`, etc.) telling the editor what kind of ID the action targets. Now inferred from the action's slots. Setting it raises `AttributeError: 'Action' object has no attribute 'id_root'`. **Safe to skip** — exporters / editors figure out the right binding from the slot system.
- **`Action.fcurves` removed.** F-curves are now under the slotted-action structure: `action.layers[].strips[].channelbag(slot).fcurves`. Direct iteration over `action.fcurves` raises `AttributeError`. **Workaround:** use `keyframe_insert()` on the bone/object (which writes through the new structure) instead of reading raw fcurves. If you need fcurve introspection, walk `action.layers` → strips → channelbags.
- **`bpy.ops.wm.read_factory_settings(use_empty=True)` blocked by the MCP sandbox** with a hint to use `read_homefile(use_empty=True, use_factory_startup=True)`. After that, `bpy.context.active_object` is `None`, which breaks downstream `bpy.ops.export_scene.gltf(...)` because the exporter reads `context.active_object`. **Workaround:** don't `read_homefile` — work on the currently-loaded `.blend` (delete unwanted objects + clear orphan data manually if you need a clean slate).
- **`bpy.ops.wm.open_mainfile(...)` leaves `bpy.context.active_object` as `None` too.** Same issue as `read_homefile` — even though `view_layer.objects.active = obj` succeeds, `bpy.context.active_object` raises `AttributeError` until the screen/area context is refreshed. **Workaround for operators that read context.active_object (notably `export_scene.gltf`):** wrap the call in `bpy.context.temp_override(window=..., screen=..., area=..., active_object=obj, selected_objects=[...])` after `open_mainfile` — that injects a synthetic context. Pattern:
  ```python
  window = bpy.context.window_manager.windows[0]
  screen = window.screen
  area = next((a for a in screen.areas if a.type == 'VIEW_3D'), screen.areas[0])
  with bpy.context.temp_override(window=window, screen=screen, area=area, active_object=arm, selected_objects=[arm, mesh]):
      bpy.ops.export_scene.gltf(filepath=..., use_selection=True, ...)
  ```

## Animation gotchas

- **Mixing rotation_mode within an armature silently corrupts on export.** A pose bone has one global `rotation_mode` property (per-bone, not per-action). If one action authors keyframes for `rotation_quaternion` (after setting `bone.rotation_mode = 'QUATERNION'`) and another action authors keyframes for `rotation_euler`, the exporter warns `"Multiple rotation mode detected for <bone>"` and produces broken data: the action whose fcurves don't match the current `rotation_mode` exports with **identity keyframes only**, regardless of the source data. The fcurves stay in the .blend but become orphaned.
  - Symptom in Godot: animation runs but the bone never moves (always at identity rotation). Bone tracks have only 1 keyframe at t=0 with value `(0, 0, 0, 1)`.
  - **Fix:** keep all actions on the same `rotation_mode` for a given bone. The exporter's warning is the only hint; the export "succeeds" with no visible error.
- **Pushing existing actions to NLA strips can affect their playback range on export.** New NLA strips default to a 1-frame range (frame 1 to 2) regardless of the action's actual frame range. Verify `strip.frame_start` and `strip.frame_end` cover the intended animation length; the exporter samples the strip's range, not the action's range.

## Layout

For the directory layout (Blender tree location, what crosses into Godot, naming discipline), see `asset-pipeline.md`. The parallel layout (Blender tree outside the Godot project) is the recommended default.
