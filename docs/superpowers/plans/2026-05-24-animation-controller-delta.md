# Animation State Machine — Controller Delta Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the controller-side interface (signals, exports, public accessor, pivot detection) that the future AnimationTree binding will consume. No behavior changes to movement — pure additive.

**Architecture:** All changes land in `scripts/player.gd`. Three new tunable `@export` vars, three new signals (`dash_fired`, `pivot_started`), one public accessor (`is_steering()`), and one pivot-detection block inserted between the existing steps 1 and 2 of `_physics_process`. No new files, no scene changes, no AnimationTree work (that's blocked on the 3D model — future session).

**Tech Stack:** Godot 4.6, GDScript

**Spec:** `docs/superpowers/specs/2026-05-24-animation-state-machine-design.md`

---

## Project-specific notes (READ FIRST)

- **Not a git repository.** Skip `git add`/`git commit` steps. Saving files IS the commit. If a repo is initialized later, commits can be reconstructed logically.
- **No test framework installed.** Verification is observational — F5, play, observe behavior. Matches the prior movement-depth plan's pattern.
- **Reading game console output.** Use `mcp__godot-mcp__editor action=get_debug_output` (the "deprecated" one — its deprecation note is premature). `get_console_output` returns nothing for editor-launched scenes.
- **No `clamp/min/max/abs/sign` calls in this plan.** All new code uses typed variants (`clampf`, `absf`, `wrapf`) per the project's GDScript-Variant-inference gotcha. No code in this plan triggers that issue, but be aware if extending.
- **`unused_signal` warnings expected.** The two new signals (`dash_fired`, `pivot_started`) have no consumers in this plan — the consumer (`player_anim.gd`) ships in a future session after the 3D model exists. Each signal is declared with `@warning_ignore("unused_signal")` to suppress the warning until then. Project does not have warnings-as-errors enabled (confirmed via `project.godot` inspection), so even without the suppression the warning is non-fatal — but suppressing keeps the editor's warnings panel clean.
- **Embedded game tab gotcha.** Not directly relevant here (no window-mode operations), but if input fails to register during F5 tests, click "Make Floating" on the Game tab to detach.
- **No `.tscn` or `.tres` edits in this plan.** All work is in `scripts/player.gd`. The AnimationTree node and `player.tscn` changes happen in a future session.

---

### Task 1: Add three new `@export` tuning vars and `is_steering()` accessor

**Files:**
- Modify: `scripts/player.gd`

These are pure declarations — no logic changes. Bundling them because they're all additive metadata at the top/bottom of the file.

- [ ] **Step 1: Add the three new `@export` vars**

In `scripts/player.gd`, find the existing block of `@export` declarations (lines 6–12 in current state, ending with `@export var impulse_decay: float = 50.0`). Insert the following three lines immediately after `@export var impulse_decay: float = 50.0`:

```gdscript
# Tuning exports for the animation interface (see animation state machine spec)
@export var pivot_reversal_threshold: float = -0.5  # dot product cutoff (~120° reversal)
@export var pivot_min_speed: float = 2.0            # below this speed, reversal too soft to register
@export var idle_threshold: float = 0.1             # below this speed, future Drift→Idle transition fires
```

- [ ] **Step 2: Add the `is_steering()` public accessor**

In `scripts/player.gd`, find the existing `apply_impulse` function (around line 116). Immediately after `apply_impulse` (after the closing of its body — before `static func _step_angle`), insert:

```gdscript


# Public accessor for animation binding (player_anim.gd in future session).
func is_steering() -> bool:
	return _steering
```

(Note the two blank lines before the function — matches the existing spacing convention between top-level definitions in this file.)

- [ ] **Step 3: Verify in Godot editor**

USER ACTION: Open the project in Godot. Select the Player node in `scenes/player.tscn` (or open `player.tscn` and click the root node). In the Inspector, scroll to the script's tunable section.

Expected:
- Three new editable properties appear: `Pivot Reversal Threshold` (-0.5), `Pivot Min Speed` (2.0), `Idle Threshold` (0.1).
- No parser errors in the bottom editor panel.
- The Inspector grouping shows them alongside the existing `Max Speed`, `Accel`, etc.

If parser errors fire: confirm the inserted exports use `float` typing (not bare numerics), and no commas/semicolons crept in. If Inspector shows the properties as `= 0.0` instead of the typed defaults: that's the **.tscn null-override gotcha** from the personal-gotchas skill — check `scenes/player.tscn` and grep for ` = null` on any of the new property names; remove if present.

---

### Task 2: Add `dash_fired` signal and emission in `_try_dash`

**Files:**
- Modify: `scripts/player.gd`

- [ ] **Step 1: Declare the `dash_fired` signal**

In `scripts/player.gd`, find the top of the file (after `extends CharacterBody3D`, before the `@export` block). Insert at line 3 (immediately after `extends CharacterBody3D` and one blank line):

```gdscript


# Signals for the animation binding (player_anim.gd, future session).
@warning_ignore("unused_signal")
signal dash_fired
```

The `@warning_ignore` is required because no consumer connects to this signal until `player_anim.gd` ships.

- [ ] **Step 2: Emit the signal at the end of `_try_dash`**

In `scripts/player.gd`, find the `_try_dash` function. The current body ends with:

```gdscript
	impulse_velocity = dir * dash_strength
	_dash_ready_at = now + dash_cooldown
```

Add one line at the very end of the function (after `_dash_ready_at = now + dash_cooldown`):

```gdscript
	dash_fired.emit()
```

The final `_try_dash` body should look like:

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
	dash_fired.emit()
```

- [ ] **Step 3: Add a temporary debug print to verify emission**

Temporarily replace the new `dash_fired.emit()` line with:

```gdscript
	print("[player] dash_fired"); dash_fired.emit()
```

(The print stays only for this task's verification — removed in step 5.)

- [ ] **Step 4: F5 and verify dash emits the signal**

USER ACTION: Press F5 to launch the game. Hold RMB to steer the player into motion. Press Space (the `dash` input). Observe the console.

Expected: Each successful dash prints `[player] dash_fired` exactly once. Dashing while on cooldown produces no print (the early `return` skips emission, which is correct).

If no print appears on dash:
- Confirm `dash` input is registered (Project → Project Settings → Input Map → search "dash").
- Confirm the print is in the right path: the `return` early-exit cases (`now < _dash_ready_at`, `dir == Vector3.ZERO`) deliberately skip the print.
- Confirm the dash works at all — gray cone should burst with momentum on Space.

If `get_debug_output` is needed (when running headless or for log inspection): `mcp__godot-mcp__editor action=get_debug_output`.

- [ ] **Step 5: Remove the temporary print**

Once verified, edit the line back to just:

```gdscript
	dash_fired.emit()
```

---

### Task 3: Add `pivot_started` signal and pivot detection block

**Files:**
- Modify: `scripts/player.gd`

- [ ] **Step 1: Declare the `pivot_started` signal**

In `scripts/player.gd`, immediately after the `signal dash_fired` line from Task 2, add:

```gdscript
@warning_ignore("unused_signal")
signal pivot_started
```

The signals block should now read:

```gdscript
# Signals for the animation binding (player_anim.gd, future session).
@warning_ignore("unused_signal")
signal dash_fired
@warning_ignore("unused_signal")
signal pivot_started
```

- [ ] **Step 2: Insert the pivot detection block in `_physics_process`**

In `scripts/player.gd`, find `_physics_process`. Identify the boundary between **step 1** (computes `target_v`) and **step 2** (integrates `input_velocity`):

Current code (around lines 33–49):

```gdscript
func _physics_process(delta: float) -> void:
	# 1. Compute target input_velocity from steering signal
	var target_v := Vector3.ZERO
	if _steering and _refresh_cursor_world():
		var to_cursor := _cursor_world - global_position
		to_cursor.y = 0.0
		var distance := to_cursor.length()
		if distance > 0.0001:
			var dir := to_cursor / distance
			var magnitude := clampf(distance / walk_threshold, 0.0, 1.0)
			target_v = dir * max_speed * magnitude

	# 2. Integrate input_velocity (accel toward target, friction toward zero)
	if target_v != Vector3.ZERO:
		input_velocity = input_velocity.move_toward(target_v, accel * delta)
	else:
		input_velocity = input_velocity.move_toward(Vector3.ZERO, friction * delta)
```

Insert the pivot detection block between step 1 and step 2 — after the `target_v = dir * max_speed * magnitude` block closes (i.e., after the blank line following step 1, before the `# 2. Integrate...` comment):

```gdscript
	# 1.5 Detect pivot: sharp reversal of steering target vs current motion.
	#     Uses pre-mutation input_velocity and freshly computed target_v.
	if _steering and target_v.length_squared() > 0.0 and input_velocity.length() > pivot_min_speed:
		var prev_dir := input_velocity.normalized()
		var new_dir := target_v.normalized()
		if prev_dir.dot(new_dir) < pivot_reversal_threshold:
			pivot_started.emit()

```

(Note the trailing blank line — preserves the spacing before `# 2. Integrate`.)

The complete `_physics_process` prefix should now read:

```gdscript
func _physics_process(delta: float) -> void:
	# 1. Compute target input_velocity from steering signal
	var target_v := Vector3.ZERO
	if _steering and _refresh_cursor_world():
		var to_cursor := _cursor_world - global_position
		to_cursor.y = 0.0
		var distance := to_cursor.length()
		if distance > 0.0001:
			var dir := to_cursor / distance
			var magnitude := clampf(distance / walk_threshold, 0.0, 1.0)
			target_v = dir * max_speed * magnitude

	# 1.5 Detect pivot: sharp reversal of steering target vs current motion.
	#     Uses pre-mutation input_velocity and freshly computed target_v.
	if _steering and target_v.length_squared() > 0.0 and input_velocity.length() > pivot_min_speed:
		var prev_dir := input_velocity.normalized()
		var new_dir := target_v.normalized()
		if prev_dir.dot(new_dir) < pivot_reversal_threshold:
			pivot_started.emit()

	# 2. Integrate input_velocity (accel toward target, friction toward zero)
	if target_v != Vector3.ZERO:
		input_velocity = input_velocity.move_toward(target_v, accel * delta)
	else:
		input_velocity = input_velocity.move_toward(Vector3.ZERO, friction * delta)
```

- [ ] **Step 3: Add a temporary debug print to verify emission**

Temporarily change the emission line `pivot_started.emit()` to:

```gdscript
			print("[player] pivot_started"); pivot_started.emit()
```

(Same pattern as Task 2 step 3 — print stays only for this task's verification.)

- [ ] **Step 4: F5 and verify pivot detection fires correctly**

USER ACTION: Press F5. Test these three scenarios in one play session:

| Scenario | How to trigger | Expected console |
|---|---|---|
| **Sharp reversal at speed** | Hold RMB, steer player into a run (cursor far to the right), then quickly snap cursor to the opposite side (far left) while still holding RMB | `[player] pivot_started` prints once at the reversal moment |
| **Gentle curve** | Hold RMB, steer into a run, then slowly arc the cursor around the player | No `pivot_started` print — direction change is too gradual to cross `pivot_reversal_threshold` |
| **Reversal from low speed** | Hold RMB at the cursor near the player, then jerk to opposite side. Player is moving slowly (below `pivot_min_speed`). | No print — the speed gate suppresses pivots at near-stop |

If the sharp reversal scenario doesn't fire:
- Try snapping the cursor faster (the reversal must be near-instant — slow arcs won't cross the dot threshold).
- Confirm `input_velocity` actually reached `pivot_min_speed` (2.0) — if `max_speed` was tuned down recently, this gate might be too high. Temporarily print `input_velocity.length()` to confirm.

If the gentle curve fires (false positive):
- The threshold `pivot_reversal_threshold = -0.5` corresponds to ~120° reversal. A wider arc shouldn't cross it. If it does, the cursor snap was sharper than intended — re-test with a deliberately slow arc.

If reversal from low speed fires (false positive):
- The `pivot_min_speed` gate isn't suppressing. Confirm the export value is 2.0 in the Inspector (could have been edited to 0 by the `.tscn null-override` gotcha; grep `scenes/player.tscn` for `pivot_min_speed = null` if so).

- [ ] **Step 5: Remove the temporary print**

Once all three scenarios verify correctly, change the line back to:

```gdscript
			pivot_started.emit()
```

---

### Task 4: Integration verification — controller feel regression check

**Files:** (no changes — verification only)

This task confirms the controller delta is purely additive: no movement, dash, or steering behavior should feel different from before the delta.

- [ ] **Step 1: Reload and clean-launch**

USER ACTION: In the Godot editor: Project → Reload Current Project. Then F5 to launch the game.

(The reload ensures any cached script state is flushed — particularly important after multiple `@export` additions, which can leave stale `.tscn` references if Inspector was used to set values mid-iteration.)

- [ ] **Step 2: Movement feel pass — verify no regressions**

USER ACTION: Run through these scenarios. None should feel different from the controller pre-delta:

1. **Walk:** RMB held with cursor just outside player → smooth walk, no judder.
2. **Run:** RMB held with cursor far from player → smooth acceleration to full run.
3. **Drift on release:** RMB held in run, then release → momentum carries player forward, friction decays to rest.
4. **Hard pivot:** RMB held in run, snap cursor to opposite side → character skids through zero velocity, accelerates the new direction. (No `pivot_started` print expected since prints were removed in Task 3 step 5 — but the *feel* of the skid should be unchanged from the pre-delta controller.)
5. **Dash:** Tap Space while running → impulse burst, decays over ~320ms, steering remains responsive during decay.
6. **Dash on cooldown:** Tap Space twice in quick succession → second tap silently no-ops until cooldown elapses.

Expected: All scenarios feel identical to the controller before this plan was applied. No new judder, lag, missed inputs, or behavior changes.

- [ ] **Step 3: Inspector tuning sanity check**

USER ACTION: With the game stopped, select Player in `scenes/player.tscn`. In the Inspector:
- Confirm `Pivot Reversal Threshold` = -0.5, `Pivot Min Speed` = 2.0, `Idle Threshold` = 0.1.
- Hover each field; tooltip should be empty (we didn't add tooltips — that's fine).
- Try editing one (e.g., set `Pivot Min Speed` to 5.0). Save the scene (Ctrl+S).
- Open `scenes/player.tscn` in a text editor (or use Read tool). Confirm the change persisted as `pivot_min_speed = 5.0` — **not as `pivot_min_speed = null`**. (Per the `.tscn null-override` gotcha; the personal-gotchas skill catalogs this.)
- Revert the edit (set back to 2.0, save again, re-confirm the file shows `pivot_min_speed = 2.0` — or absent entirely if it matches the default and Godot strips it).

- [ ] **Step 4: Final cleanup check**

USER ACTION: Open `scripts/player.gd` and confirm:
- No `print("[player] dash_fired")` or `print("[player] pivot_started")` calls remain (both were removed in their respective tasks).
- The `@warning_ignore("unused_signal")` lines are still present above both signals.
- File compiles cleanly (no red error markers in the editor's bottom panel).

Also confirm the Godot editor's "Warnings" panel (bottom dock) shows no warnings related to `player.gd` — specifically, `unused_signal` warnings for `dash_fired` and `pivot_started` should be suppressed.

If warnings appear despite the `@warning_ignore`: confirm the spelling (`unused_signal`, not `unused-signal` or other variant), and that the annotation is on the line immediately above the signal declaration.

---

## Scope reminder — what this plan does NOT do

Per the spec's "Implementation order," this plan covers **Step 1 only**. The remaining six steps are out of scope here because they depend on prerequisites that don't exist yet:

| Step | Prerequisite | When |
|---|---|---|
| 2. Model + rig in Blender | 3D modeling session | Next session (uses `docs/animation-authoring-guide.html`) |
| 3. Author 13 clips | Model exists | After model |
| 4. Export & import to Godot | Clips authored | After clips |
| 5. Build AnimationTree resource | Model imported in Godot | After import |
| 6. Create `player_anim.gd` | AnimationTree exists | After Step 5 |
| 7. Integration verify + tune | Everything wired | After Step 6 |

Each of those steps will get its own plan when the prerequisites are met. After this plan ships, the controller is ready for any future binding script to connect to its signals and read its public state.
