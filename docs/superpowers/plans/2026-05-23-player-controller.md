# Player Controller Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a click-to-move placeholder player avatar per the [2026-05-23 spec](../specs/2026-05-23-player-controller-design.md) — capsule + cone facing indicator + NavigationAgent3D + right-click destination.

**Architecture:** New `scenes/player.tscn` is a CharacterBody3D root containing a body capsule (placeholder), a cone facing indicator (placeholder), a matching capsule collision shape, and a NavigationAgent3D. New `scripts/player.gd` handles right-click → ground-plane raycast → set nav target, then per-physics-frame reads the agent's next path position, smoothly turns toward it, and calls `move_and_slide`. `scenes/main.tscn` wraps the existing `Ground` in a `NavigationRegion3D` (so the nav mesh bakes from the plane) and instances `Player.tscn` at the origin.

**Tech Stack:** Godot 4.6, GDScript (static typing), Jolt Physics, NavigationAgent3D + NavigationRegion3D, godot-mcp tools (`scene`, `node`, `editor`, `godot__get_diagnostics`) for construction and verification.

**Verification model:** "Tests" in this plan are observation steps using godot-mcp — open scene → check node tree → run scene → screenshot → read console. The MCP `input` tool does not support mouse-coordinate clicks, so the final right-click-to-move behavior is verified by the user manually pressing right-click during a play session.

**Editor preconditions (already in place this session):**
- Godot 4.6.2 editor running, project open at `/Users/chaipalaka/gamedev/godot/3d-prototype-1/3d-proto-1/`
- `Editor Settings → Run → Embed Game on Next Play` is **disabled** (the embedded-game gotcha would otherwise prevent live testing — see `gotcha_embedded_game_blocks_window_mode.md` memory)

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `scripts/player.gd` | Create | CharacterBody3D logic: right-click → nav target, per-frame path-following + smooth turn |
| `scenes/player.tscn` | Create | Player scene tree (CharacterBody3D + Body + Facing + Collision + NavAgent) with placeholder visuals |
| `scenes/main.tscn` | Modify | Reparent `Ground` under a new `NavigationRegion3D`; instance `Player.tscn` at world origin |

No changes to `project.godot`, autoloads, fullscreen toggle, camera, materials, or shaders.

---

## Task 1: Create `scripts/player.gd` skeleton (typed exports, empty bodies)

Create the script file first so it can be attached as the scene is built. Bodies are stubs in this task — filled in Tasks 5 and 6. This separation lets us verify each layer in isolation.

**Files:**
- Create: `scripts/player.gd`

- [ ] **Step 1: Write the script file**

```gdscript
extends CharacterBody3D


@export var max_speed: float = 6.0
@export var turn_rate_deg: float = 720.0

@onready var nav_agent: NavigationAgent3D = $NavAgent


func _input(event: InputEvent) -> void:
	pass


func _physics_process(delta: float) -> void:
	pass
```

- [ ] **Step 2: Verify it parses cleanly**

Run via MCP:
```
mcp__godot__get_diagnostics file_path=/Users/chaipalaka/gamedev/godot/3d-prototype-1/3d-proto-1/scripts/player.gd
```

Expected: `diagnostics` is `[]` (empty array). The `@onready` reference to `$NavAgent` will not yet exist, but `@onready` resolves at scene-load time, so the script parses fine on its own.

---

## Task 2: Build `scenes/player.tscn` via MCP scene/node tools

Construct the scene tree programmatically through the editor. This avoids hand-authoring rotation matrices for the cone and lets the editor format the `.tscn` file canonically. The CLAUDE.md preference is editor-based scene construction.

**Files:**
- Create: `scenes/player.tscn`

- [ ] **Step 1: Create the scene with a CharacterBody3D root**

```
mcp__godot-mcp__scene action=create scene_path=res://scenes/player.tscn root_type=CharacterBody3D root_name=Player
```

Expected: response confirms scene created. After this, the scene is open and `/root/Player` exists.

- [ ] **Step 2: Add the Body (CapsuleMesh) child**

```
mcp__godot-mcp__node action=create parent_path=/root/Player node_name=Body node_type=MeshInstance3D
```

Then set the Body's mesh, material, and position with one update:

```
mcp__godot-mcp__node action=update node_path=/root/Player/Body properties={
  "mesh": {"$type": "CapsuleMesh", "radius": 0.4, "height": 1.8},
  "position": {"x": 0, "y": 0.9, "z": 0}
}
```

Note: if the inline `$type` shorthand isn't supported by the addon, create the CapsuleMesh resource separately. Confirm by reading back `mcp__godot-mcp__node action=get_properties node_path=/root/Player/Body` and checking `mesh` is non-null with `radius=0.4`, `height=1.8`. If `mesh` is null, fall back to:

a. Create the resource manually by editing `scenes/player.tscn` to insert a `[sub_resource type="CapsuleMesh" id="CapsuleMesh_body"]` with `radius = 0.4` and `height = 1.8`, then re-open via `mcp__godot-mcp__scene action=open`.

b. Reassign material via a `StandardMaterial3D` sub-resource with `albedo_color = Color(0.7, 0.7, 0.75, 1)` set on `surface_material_override/0` in the Body node.

- [ ] **Step 3: Add the Facing (cone) child**

```
mcp__godot-mcp__node action=create parent_path=/root/Player node_name=Facing node_type=MeshInstance3D
```

Set the mesh, rotation (-90° around X = -π/2 rad ≈ -1.5707963), and position:

```
mcp__godot-mcp__node action=update node_path=/root/Player/Facing properties={
  "mesh": {"$type": "CylinderMesh", "top_radius": 0.0, "bottom_radius": 0.12, "height": 0.5},
  "rotation": {"x": -1.5707963, "y": 0, "z": 0},
  "position": {"x": 0, "y": 1.5, "z": 0.35}
}
```

Assign a bright-orange material: create a StandardMaterial3D sub-resource with `albedo_color = Color(1.0, 0.45, 0.0, 1)` and set it on `surface_material_override/0`. (If the `$type` shorthand isn't supported, fall back to the hand-edit + reopen pattern from Step 2.)

- [ ] **Step 4: Add the Collision child**

```
mcp__godot-mcp__node action=create parent_path=/root/Player node_name=Collision node_type=CollisionShape3D
```

```
mcp__godot-mcp__node action=update node_path=/root/Player/Collision properties={
  "shape": {"$type": "CapsuleShape3D", "radius": 0.4, "height": 1.8},
  "position": {"x": 0, "y": 0.9, "z": 0}
}
```

- [ ] **Step 5: Add the NavAgent child**

```
mcp__godot-mcp__node action=create parent_path=/root/Player node_name=NavAgent node_type=NavigationAgent3D
```

Leave all NavigationAgent3D properties at defaults. The spec keeps `path_desired_distance` and `target_desired_distance` at 1.0 each for now.

- [ ] **Step 6: Attach the script to the Player root**

```
mcp__godot-mcp__node action=attach_script node_path=/root/Player script_path=res://scripts/player.gd
```

- [ ] **Step 7: Save the scene**

```
mcp__godot-mcp__scene action=save scene_path=res://scenes/player.tscn
```

- [ ] **Step 8: Verify the tree**

```
mcp__godot-mcp__node action=find root_path=/root/Player name_pattern=*
```

Expected output lists exactly these five nodes:
- `/root/Player` (CharacterBody3D)
- `/root/Player/Body` (MeshInstance3D)
- `/root/Player/Facing` (MeshInstance3D)
- `/root/Player/Collision` (CollisionShape3D)
- `/root/Player/NavAgent` (NavigationAgent3D)

If the tree is correct but the meshes/materials were not applied via MCP updates, hand-fix `scenes/player.tscn` per the fallback noted in Steps 2/3 and re-open the scene.

- [ ] **Step 9: Visual spot-check**

```
mcp__godot-mcp__editor action=screenshot_editor viewport=3d max_width=1200
```

Expected: capsule and orange cone visible at origin in the editor viewport (you may need to focus the editor camera on the origin first — if the editor camera is far away, this is okay, just confirm via the node tree that the scene is structurally correct).

---

## Task 3: Wrap `Ground` in a `NavigationRegion3D` in `scenes/main.tscn`

The NavigationAgent3D on the player needs a `NavigationRegion3D` somewhere in the same scene to provide a baked nav mesh. We reparent the existing Ground under a new NavigationRegion3D so the region's bake uses the plane geometry as the source.

**Files:**
- Modify: `scenes/main.tscn`

- [ ] **Step 1: Open the main scene**

```
mcp__godot-mcp__scene action=open scene_path=res://scenes/main.tscn
```

- [ ] **Step 2: Create the NavigationRegion3D as a child of Main**

```
mcp__godot-mcp__node action=create parent_path=/root/Main node_name=NavRegion node_type=NavigationRegion3D
```

- [ ] **Step 3: Reparent Ground under NavRegion**

```
mcp__godot-mcp__node action=reparent node_path=/root/Main/Ground new_parent_path=/root/Main/NavRegion
```

- [ ] **Step 4: Save the scene**

```
mcp__godot-mcp__scene action=save scene_path=res://scenes/main.tscn
```

- [ ] **Step 5: USER ACTION — bake the nav mesh in the editor**

NavigationRegion3D requires a `NavigationMesh` resource to be assigned and baked. This is a Godot editor UI action that the MCP addon does not expose:

1. In the editor's Scene panel, select `/root/Main/NavRegion`.
2. In the Inspector, find the `Navigation Mesh` property and click `[empty]` → `New NavigationMesh`.
3. With the NavRegion still selected, click the **"Bake NavigationMesh"** button in the top toolbar of the 3D viewport (it appears when a NavigationRegion3D is selected).
4. The viewport should show a translucent overlay over the ground plane indicating the baked region.

Save the scene again after baking.

- [ ] **Step 6: Verify the tree**

```
mcp__godot-mcp__node action=find root_path=/root/Main name_pattern=*
```

Expected order of nodes under `/root/Main`:
- `Sun` (DirectionalLight3D)
- `Env` (WorldEnvironment)
- `NavRegion` (NavigationRegion3D)
  - `Ground` (MeshInstance3D) — now a child of NavRegion
- `Camera_Dota` (Camera3D)

---

## Task 4: Instance `Player.tscn` into `scenes/main.tscn` at origin

**Files:**
- Modify: `scenes/main.tscn`

- [ ] **Step 1: Ensure main.tscn is open**

If switched away during Task 2's verification:
```
mcp__godot-mcp__scene action=open scene_path=res://scenes/main.tscn
```

- [ ] **Step 2: Instance Player.tscn as a child of Main**

```
mcp__godot-mcp__node action=create parent_path=/root/Main node_name=Player scene_path=res://scenes/player.tscn
```

- [ ] **Step 3: Confirm Player position is at origin**

```
mcp__godot-mcp__node action=get_properties node_path=/root/Main/Player
```

Expected: `position` is `{"x": 0, "y": 0, "z": 0}`. If not, set it:

```
mcp__godot-mcp__node action=update node_path=/root/Main/Player properties={"position": {"x": 0, "y": 0, "z": 0}}
```

- [ ] **Step 4: Save**

```
mcp__godot-mcp__scene action=save scene_path=res://scenes/main.tscn
```

- [ ] **Step 5: Visual verification — run the scene and screenshot**

```
mcp__godot-mcp__editor action=run scene_path=res://scenes/main.tscn
mcp__godot-mcp__editor action=screenshot_game max_width=1200
mcp__godot-mcp__editor action=stop
```

Expected screenshot: the grid plane visible at the Dota camera angle, with a gray capsule standing at the world origin and an orange cone protruding forward from the top of the capsule. The capsule's feet touch the grid (y=0). The cone points along +Z (which, given Camera_Dota at `(0, 18, 18)` looking down-and-back, will appear pointing roughly "down-screen" toward the camera).

If the player is not visible: re-check that the Player position is `(0,0,0)`, that `Body` y is `0.9`, and that `Player.tscn` was saved before being instanced.

---

## Task 5: Implement right-click input → nav target in `player.gd`

Fill in the `_input` body. Reads right mouse-button press, projects the camera ray to the y=0 plane, sets `nav_agent.target_position`.

**Files:**
- Modify: `scripts/player.gd`

- [ ] **Step 1: Replace the script with the input-handling version**

```gdscript
extends CharacterBody3D


@export var max_speed: float = 6.0
@export var turn_rate_deg: float = 720.0

@onready var nav_agent: NavigationAgent3D = $NavAgent


func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_RIGHT or not mb.pressed:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var ray_origin := camera.project_ray_origin(mb.position)
	var ray_dir := camera.project_ray_normal(mb.position)
	# Intersect with the horizontal plane y=0
	if absf(ray_dir.y) < 0.0001:
		return  # ray is parallel to ground
	var t := -ray_origin.y / ray_dir.y
	if t < 0.0:
		return  # plane is behind the camera
	var hit := ray_origin + ray_dir * t
	nav_agent.target_position = hit


func _physics_process(delta: float) -> void:
	pass
```

- [ ] **Step 2: Verify diagnostics clean**

```
mcp__godot__get_diagnostics file_path=/Users/chaipalaka/gamedev/godot/3d-prototype-1/3d-proto-1/scripts/player.gd
```

Expected: `[]`.

- [ ] **Step 3: Smoke test — confirm script attaches and reads input without errors**

```
mcp__godot-mcp__editor action=run scene_path=res://scenes/main.tscn
```

Then read console:
```
mcp__godot-mcp__editor action=get_debug_output
```

Expected: no errors, no "null instance" messages. Movement won't happen yet (no `_physics_process` logic), but the scene should run cleanly. Stop the run:

```
mcp__godot-mcp__editor action=stop
```

---

## Task 6: Implement path-following movement in `player.gd`

Fill in `_physics_process`. Reads NavigationAgent3D's next path position, computes desired horizontal direction, smoothly rotates the player's Y to face it (capped by `turn_rate_deg * delta`), sets velocity, calls `move_and_slide`.

**Files:**
- Modify: `scripts/player.gd`

- [ ] **Step 1: Replace the script with the full version**

```gdscript
extends CharacterBody3D


@export var max_speed: float = 6.0
@export var turn_rate_deg: float = 720.0

@onready var nav_agent: NavigationAgent3D = $NavAgent


func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_RIGHT or not mb.pressed:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var ray_origin := camera.project_ray_origin(mb.position)
	var ray_dir := camera.project_ray_normal(mb.position)
	if absf(ray_dir.y) < 0.0001:
		return
	var t := -ray_origin.y / ray_dir.y
	if t < 0.0:
		return
	var hit := ray_origin + ray_dir * t
	nav_agent.target_position = hit


func _physics_process(delta: float) -> void:
	if nav_agent.is_navigation_finished():
		velocity = Vector3.ZERO
		move_and_slide()
		return
	var next_pos := nav_agent.get_next_path_position()
	var to_next := next_pos - global_position
	to_next.y = 0.0
	if to_next.length_squared() < 0.0001:
		velocity = Vector3.ZERO
		move_and_slide()
		return
	var desired_dir := to_next.normalized()
	# Smooth Y-axis rotation toward the heading
	var target_yaw := atan2(desired_dir.x, desired_dir.z)
	var max_step := deg_to_rad(turn_rate_deg) * delta
	rotation.y = _step_angle(rotation.y, target_yaw, max_step)
	velocity = desired_dir * max_speed
	move_and_slide()


static func _step_angle(from: float, to: float, max_delta: float) -> float:
	# Shortest-arc step from `from` to `to`, clamped to `max_delta`.
	var diff := wrapf(to - from, -PI, PI)
	if absf(diff) <= max_delta:
		return to
	return from + signf(diff) * max_delta
```

- [ ] **Step 2: Verify diagnostics clean**

```
mcp__godot__get_diagnostics file_path=/Users/chaipalaka/gamedev/godot/3d-prototype-1/3d-proto-1/scripts/player.gd
```

Expected: `[]`.

---

## Task 7: End-to-end manual verification (user-driven)

The MCP `input` tool only supports action-based input (not mouse coordinates), so the right-click-to-move behavior must be verified by the user with a real mouse.

**Files:** none — this is observation only.

- [ ] **Step 1: Launch the scene**

```
mcp__godot-mcp__editor action=run scene_path=res://scenes/main.tscn
```

- [ ] **Step 2: USER ACTION — right-click on the grid in five places**

User performs:
1. Right-click near the player → expect short walk, immediate stop on arrival.
2. Right-click far across the plane → expect smooth straight-line walk to that point.
3. Right-click behind the player (in the opposite direction) → expect the cone to rotate smoothly through ~180°, not snap; player turns while/then walks.
4. Right-click while the player is mid-walk → expect immediate retargeting; player smoothly redirects toward the new point.
5. Right-click *off* the grid (in the sky / background) → expect no movement (the ray misses the y=0 plane in front of the camera, or hits well outside the baked nav region).

- [ ] **Step 3: Check the console for runtime errors**

```
mcp__godot-mcp__editor action=get_debug_output
```

Expected: no errors. Possible benign warnings: NavigationAgent3D may emit `Navigation agent has no NavigationServer3D map` for one frame at startup before the region is registered — this is fine.

- [ ] **Step 4: USER ACTION — live-tune max_speed and turn_rate_deg**

With the scene still running:
1. In the editor's Scene panel, click on the running player (Remote Scene Tree → Main → Player).
2. In the Inspector, change `Max Speed` to 12.0 → player should move twice as fast on the next click.
3. Change `Turn Rate Deg` to 90.0 → player should turn very slowly (visibly lag while walking around a wide arc).
4. Restore to defaults (6.0, 720.0) when satisfied.

Verifying this works confirms the iteration-loop the spec was designed to support.

- [ ] **Step 5: Stop the run**

```
mcp__godot-mcp__editor action=stop
```

- [ ] **Step 6: Verify each spec acceptance criterion**

From the spec's Verification section, confirm each:

1. Player capsule appears at world origin with orange cone pointing along +Z. ✓ (Task 4 screenshot)
2. Right-click moves player to that point. ✓ (Task 7 Step 2.1, 2.2)
3. Smooth rotation, no snap. ✓ (Task 7 Step 2.3)
4. Stops on arrival. ✓ (Task 7 Step 2.1)
5. Cone tracks heading. ✓ (Task 7 Steps 2.1–2.4)
6. Inspector live-edit works. ✓ (Task 7 Step 4)

If any item fails, capture the symptom (screenshot + console excerpt) and add it as a new diagnostic task before declaring done.

---

## Out-of-band notes (not tasks, but read before executing)

- **No git commits per task.** Project is not a git repository (per session env). If `git init` happens later, retroactive commits per task are fine but not required.
- **MCP scene/node tool quirks.** Some property setters (especially `mesh = { $type: ... }` shorthand) may not be supported by the godot-mcp addon and require hand-editing `.tscn` followed by `scene action=open` to reload. Task 2 has fallback notes for this.
- **Editor state caching.** If you hand-edit `project.godot` or autoloads, the editor must reload the project for the change to take effect at edit time — though game runs always read the file fresh.
- **NavigationAgent3D async path.** Setting `target_position` triggers an async path computation; for one physics frame after a new click, the agent may report stale data. This is harmless for click-to-move (one frame ≈ 16 ms) and the spec accepts it.
