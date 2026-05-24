# Movement Depth Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the placeholder click-to-move controller with a momentum-driven hold-to-direct system that has Smash-Bros-level depth — heavy drift, cursor-as-stick steering, dash with impulse channel, and emergent skill expression.

**Architecture:** Single `CharacterBody3D` with two velocity channels: `input_velocity` (from cursor steering, integrated via `move_toward` toward a target derived from cursor offset) and `impulse_velocity` (from dash and future knockback, decays via `move_toward` toward zero). Channels sum, `move_and_slide()` applies the result.

**Tech Stack:** Godot 4.6, GDScript

**Spec:** `docs/superpowers/specs/2026-05-24-rts-movement-depth-design.md`

---

## Project-specific notes (READ FIRST)

- **Not a git repository.** Skip `git add`/`git commit` steps. Saving files IS the commit. If a git repo is initialized later, the commits can be retroactively logical.
- **No test framework installed.** Verification is observational — F5, play, observe behavior matches spec. Adding GUT/gdUnit4 is out of scope for a feel-iteration prototype.
- **Editor caches `project.godot` on startup.** After hand-editing `project.godot`, do Project → Reload Current Project before relying on UI panels (Input Map, etc.) to reflect changes. F5-launched game runs DO read fresh, so a forgot-to-reload won't break gameplay tests.
- **Embedded game tab can break window-mode operations.** Not directly relevant here, but if any input fails to register, detach the Game tab (Make Floating button) before testing.
- **MCP scene mutation hazard.** This plan uses USER ACTION steps for `.tscn` edits — safer than MCP `node` tools, which have a history of mutating the wrong scene in this project. If you do use MCP node tools, read the affected file from disk immediately after to verify.
- **Console output gotcha.** Use `mcp__godot-mcp__editor action=get_debug_output` (the "deprecated" one — its deprecation note is premature) to read game-side errors. `get_console_output` returns nothing for editor-launched scenes.

---

### Task 1: Add `dash` input action to `project.godot`

**Files:**
- Modify: `project.godot` (the `[input]` section, currently containing only `toggle_fullscreen`)

- [ ] **Step 1: Add the `dash` action**

Open `project.godot` and find the `[input]` section. After the closing `]` of `toggle_fullscreen`, add:

```
dash={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":32,"key_label":0,"unicode":32,"location":0,"echo":false,"script":null)
]
}
```

This mirrors the format of the existing `toggle_fullscreen` action, with `physical_keycode:32` for the Spacebar.

- [ ] **Step 2: Reload the project in the editor**

USER ACTION: In Godot editor, Project → Reload Current Project. The editor caches `project.godot` and won't show the new action in the Input Map panel until reload.

- [ ] **Step 3: Verify the action is registered**

USER ACTION: Project → Project Settings → Input Map → search "dash" in the action filter. Confirm a `dash` action exists, mapped to physical key Space.

---

### Task 2: Remove `NavigationAgent3D` from `scenes/player.tscn`

**Files:**
- Modify: `scenes/player.tscn`

The player no longer pathfinds. Pathfinding-around-obstacles is the wrong abstraction when directly steering velocity. The `NavigationRegion3D` in `main.tscn` and the baked nav mesh stay in place for future enemy AI.

- [ ] **Step 1: Delete the NavAgent node**

USER ACTION:
1. Open `scenes/player.tscn` in the Godot editor (double-click in the FileSystem dock).
2. In the Scene tree (left panel), right-click the `NavAgent` node (it's the last child of the Player root).
3. Click "Delete Node(s)" and confirm.
4. Save the scene (Ctrl+S).

- [ ] **Step 2: Verify on disk**

Read `scenes/player.tscn`. Confirm no lines contain `node name="NavAgent"` or `type="NavigationAgent3D"`. If still present, the editor save didn't persist — re-save in the editor (Ctrl+S) and re-check.

---

### Task 3: Rewrite `player.gd` — steering channel only

**Files:**
- Modify: `scripts/player.gd` (complete replacement)

This task replaces the placeholder controller with the full steering loop. The dash mechanic comes in Task 4. The reason for splitting: verifying steering feel in isolation makes feel-debugging easier than tuning two channels at once.

- [ ] **Step 1: Replace `scripts/player.gd` entirely**

Replace the file's complete contents with:

```gdscript
extends CharacterBody3D


# Tunable exports — see spec for rationale
@export var max_speed: float = 7.0
@export var accel: float = 24.0
@export var friction: float = 14.0
@export var turn_rate_deg: float = 540.0
@export var walk_threshold: float = 2.0

# Internal velocity channels
var input_velocity: Vector3 = Vector3.ZERO
var impulse_velocity: Vector3 = Vector3.ZERO

# Steering state
var _steering: bool = false
var _cursor_world: Vector3 = Vector3.ZERO


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_steering = mb.pressed


func _physics_process(delta: float) -> void:
	# 1. Compute target input_velocity from steering signal
	var target_v := Vector3.ZERO
	if _steering and _refresh_cursor_world():
		var to_cursor := _cursor_world - global_position
		to_cursor.y = 0.0
		var distance := to_cursor.length()
		if distance > 0.0001:
			var dir := to_cursor / distance
			var magnitude := clamp(distance / walk_threshold, 0.0, 1.0)
			target_v = dir * max_speed * magnitude

	# 2. Integrate input_velocity (accel toward target, friction toward zero)
	if target_v != Vector3.ZERO:
		input_velocity = input_velocity.move_toward(target_v, accel * delta)
	else:
		input_velocity = input_velocity.move_toward(Vector3.ZERO, friction * delta)

	# 3. impulse_velocity stays zero until Task 4 adds dash and decay

	# 4. Combine channels and apply
	velocity = input_velocity + impulse_velocity

	# 5. Facing follows velocity heading (smoothed)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length_squared() > 0.01:
		var target_yaw := atan2(horizontal.x, horizontal.z)
		var max_step := deg_to_rad(turn_rate_deg) * delta
		rotation.y = _step_angle(rotation.y, target_yaw, max_step)

	move_and_slide()


# Projects current mouse position onto the y=0 plane and stores hit in _cursor_world.
# Returns true if projection succeeded (camera exists, ray not parallel to plane,
# intersection is forward of camera).
func _refresh_cursor_world() -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return false
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)
	if absf(ray_dir.y) < 0.0001:
		return false
	var t := -ray_origin.y / ray_dir.y
	if t < 0.0:
		return false
	_cursor_world = ray_origin + ray_dir * t
	return true


static func _step_angle(from: float, to: float, max_delta: float) -> float:
	# Shortest-arc step from `from` to `to`, clamped to `max_delta`.
	var diff := wrapf(to - from, -PI, PI)
	if absf(diff) <= max_delta:
		return to
	return from + signf(diff) * max_delta
```

GDScript indentation is **tabs**, not spaces. If the file ends up with mixed indentation, the parser will complain.

- [ ] **Step 2: F5 and verify steering**

USER ACTION: Press F5. If the game is embedded in the editor tab, click "Make Floating" to detach it (`window_set_mode` and similar tools no-op when embedded — relevant for future tasks but worth knowing).

Verify each of the following — these are the steering behaviors in isolation, before dash exists:

1. Hold right-mouse anywhere on the ground. Character accelerates smoothly toward the cursor over ~300ms.
2. While still holding RMB, sweep the cursor around. Character curves to follow — the cursor is a continuous steering signal, not a destination.
3. Release RMB. Character coasts and decelerates over ~500ms. The slide direction matches velocity at the moment of release.
4. Hold RMB with cursor very close to the player (~0.5m away in world units). Character walks slowly.
5. Hold RMB with cursor far from player (10+ meters away). Character runs at full speed. Pulling the cursor between near and far modulates speed continuously.
6. Hold RMB toward NE, then sharply flick the cursor to SW. Character's `input_velocity` is forced through zero before building reverse — visible pivot skid.
7. The orange facing cone always points along velocity, smoothed with visible turn lag during sharp direction changes.

If any of these don't behave as expected, adjust the relevant `@export` in the Inspector during play (it's live-editable) before assuming a code bug. Defaults are starting points, not gospel.

---

### Task 4: Add dash mechanic and impulse channel

**Files:**
- Modify: `scripts/player.gd`

- [ ] **Step 1: Add dash exports**

In `scripts/player.gd`, after the existing `@export var walk_threshold: float = 2.0` line, add:

```gdscript
@export var dash_strength: float = 16.0
@export var dash_cooldown: float = 0.4
@export var impulse_decay: float = 50.0
```

- [ ] **Step 2: Add dash readiness state**

Below `var _cursor_world: Vector3 = Vector3.ZERO`, add:

```gdscript
var _dash_ready_at: float = 0.0
```

- [ ] **Step 3: Wire the dash input**

Inside `_input(event)`, after the existing mouse-button block, add:

```gdscript
	if event.is_action_pressed("dash"):
		_try_dash()
```

The full updated `_input` should now look like:

```gdscript
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_steering = mb.pressed
	if event.is_action_pressed("dash"):
		_try_dash()
```

- [ ] **Step 4: Add dash methods**

Add these two functions just before the existing `_step_angle` static function:

```gdscript
func _try_dash() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _dash_ready_at:
		return
	var dir := _resolve_dash_dir()
	if dir == Vector3.ZERO:
		return
	impulse_velocity = dir * dash_strength
	_dash_ready_at = now + dash_cooldown


func _resolve_dash_dir() -> Vector3:
	# Priority: active steering → current velocity → current facing
	if _steering and _refresh_cursor_world():
		var to_cursor := _cursor_world - global_position
		to_cursor.y = 0.0
		if to_cursor.length_squared() > 0.0001:
			return to_cursor.normalized()
	var v := Vector3(velocity.x, 0.0, velocity.z)
	if v.length_squared() > 0.01:
		return v.normalized()
	# Fall back to current facing — basis.z is +Z forward, but in Godot
	# the "forward" of a transformed node is -basis.z. The cone visual
	# points along +Z in local space (see player_controller spec), which
	# is the same vector here.
	return transform.basis.z

```

Wait — note on the last line: in Godot, `-transform.basis.z` is the conventional "forward" vector for a node. But the facing cone in this prototype is configured to point along `+Z` (per the placeholder spec). For consistency with the cone's visual direction, use `transform.basis.z` (positive). If the visual ends up flipped, change to `-transform.basis.z`.

- [ ] **Step 5: Add impulse decay to the integration loop**

In `_physics_process`, find the comment `# 3. impulse_velocity stays zero until Task 4 adds dash and decay`. Replace that single comment line with:

```gdscript
	# 3. Decay impulse_velocity toward zero
	impulse_velocity = impulse_velocity.move_toward(Vector3.ZERO, impulse_decay * delta)
```

The block 4 (`velocity = input_velocity + impulse_velocity`) stays unchanged — it already combines both channels.

- [ ] **Step 6: F5 and verify dash**

USER ACTION: Press F5. Verify:

1. Press Spacebar while standing still. Character bursts forward (along current facing) for ~320ms then naturally stops.
2. Hold RMB toward east (right side of screen). Tap Space. Character dashes east.
3. Tap Space, then immediately swing RMB to north during the dash decay. Character's path curves from east toward north — the dash impulse decays while steering builds north velocity. Curved-arc behavior.
4. Tap Space, then 0.2s later tap Space again. Second dash is ignored (cooldown still active).
5. Tap Space, wait ~0.5s, tap Space again. Both dashes fire. Each redirects the impulse channel (overwrites, not stacks).
6. Tap Space mid-run. The dash impulse stacks WITH `input_velocity` (they sum) — so a steered + dash produces faster initial burst than a steered-alone or dash-from-rest.

If item 1 dashes the WRONG direction (e.g., backward), swap `transform.basis.z` → `-transform.basis.z` in `_resolve_dash_dir`. The convention is sensitive to how the cone was originally oriented in `player.tscn`.

---

### Task 5: Add public `apply_impulse` API

**Files:**
- Modify: `scripts/player.gd`

This defines the surface for external systems (future enemies, explosions, knockback effects) to push the player without coupling to internal state.

- [ ] **Step 1: Add the method**

After `_resolve_dash_dir` and before `_step_angle`, add:

```gdscript
# Public API for external systems to push the player.
# Knockback callers should pass a 3D impulse; only XZ components are used.
# Note: this is ADDITIVE (unlike dash, which OVERWRITES). See spec asymmetry note.
func apply_impulse(impulse: Vector3) -> void:
	impulse_velocity += Vector3(impulse.x, 0.0, impulse.z)

```

- [ ] **Step 2: Smoke-test via the debugger**

USER ACTION:
1. F5.
2. In the editor (running play session), switch to the "Remote" tab in the Scene dock (next to "Local").
3. Click the Player node.
4. Below the scene tree, click "Debug" → switch to the Debugger panel.
5. In the "Expressions" sub-panel, evaluate: `apply_impulse(Vector3(20.0, 0.0, 0.0))`
6. Observe: player slides east, then friction-bleeds via `impulse_decay`.

Alternative if the Expressions panel is unfamiliar: skip this verification entirely. The API is exercised when an enemy/knockback system is wired up later, and a non-zero argument will produce visible motion at that point. The method body is two lines; the risk of latent bugs is low.

---

### Task 6: Final verification pass against spec

**Files:**
- None (verification only)

- [ ] **Step 1: Walk through all 8 spec verification criteria**

Open `docs/superpowers/specs/2026-05-24-rts-movement-depth-design.md` and find the Verification section. Run through each of the 8 numbered criteria via F5 play session:

1. Holding right-click toward a direction → smooth accel.
2. Releasing right-click → ~500ms coast.
3. Cursor distance modulates speed.
4. Sharp cursor reversal produces visible pivot skid.
5. Spacebar fires dash; steering during dash decay curves the arc.
6. Two dashes in 0.4s → second ignored; two with 0.5s gap → both fire, second redirects.
7. All `@export` values in Inspector change feel live, no restart.
8. Walking into walls slides along them via `move_and_slide`.

- [ ] **Step 2: Flag any failures**

For each failed criterion, classify and act:
- **Tuning issue** (feels slightly off but mechanism is right): adjust the relevant `@export` in Inspector during play. Don't change code yet — this is the feel-iteration phase.
- **Mechanism bug** (behavior is wrong, not just off): identify the code path, fix in `player.gd`, re-verify.
- **Spec mismatch** (the criterion isn't possible with the current architecture): note it. Don't quietly change either spec or code without discussion.

- [ ] **Step 3: Capture new gotchas (optional)**

If implementation surfaced new Godot editor or engine quirks, add them to the `godot-personal-gotchas` skill via the memory system — symptom → cause → fix format.

---

## Self-review pass (planner-side, before handing off)

Quick check the planner runs on themselves before this plan ships:

- **Spec coverage:** Scene structure (Task 2) · Controller state (Tasks 3, 4) · Input handling (Tasks 3, 4) · Cursor projection (Task 3) · Integration loop (Tasks 3, 4) · Dash mechanic (Task 4) · `apply_impulse` (Task 5) · `_step_angle` (Task 3) · Input map (Task 1) · Tuning surface as `@export`s (Tasks 3, 4) · Verification criteria (Task 6). All covered.
- **Placeholders:** None. Every code block is concrete. No "add error handling" hand-waves.
- **Type consistency:** `input_velocity` / `impulse_velocity` (`Vector3`) · `_steering` (`bool`) · `_cursor_world` (`Vector3`) · `_dash_ready_at` (`float`) · `apply_impulse(Vector3) -> void` — all consistent across tasks.
- **Tab indentation in code blocks:** All GDScript uses tab indentation. If pasting into the editor produces a parse error, the indent got converted to spaces — re-do with tabs.
