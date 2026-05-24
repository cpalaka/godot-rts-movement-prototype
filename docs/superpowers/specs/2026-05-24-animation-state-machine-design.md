# Player Animation — State Machine Design

**Date:** 2026-05-24
**Status:** Approved design, pre-implementation
**Related:**
- Movement spec: `2026-05-24-rts-movement-depth-design.md` (this spec extends it with the animation layer)
- Authoring reference: `docs/animation-authoring-guide.html` (per-clip Blender notes)

## Purpose

Define the animation state machine that drives the player character's visual representation. Scoped to locomotion + dash + pivot + hit-reaction-room. Combat, jump, and death are out of scope but architecturally accommodated.

The animation system must mirror the depth of the movement controller (drift, pivot, dash-decay-with-steering) without losing the snap that makes the controller feel responsive.

## Game context

Inherits from the movement spec. Same game shape: top-down ARPG, momentum-driven hold-to-direct movement, dash via impulse channel. The character is bipedal humanoid; no 3D model exists yet — model and clips are authored after this spec is approved.

## Locked decisions

| Dimension | Choice | Reason |
|---|---|---|
| Scope | Depth-matching | Full SM mirroring controller depth; some clips stubbed but no future restructure |
| Dash shape | Layered additive OneShot | Steering stays active during impulse decay; legs continue locomotion underneath |
| Move blending | BlendSpace2D (turn rate × speed) | Lean-into-turns reads at oblique camera angles |
| Drift blending | BlendSpace1D (speed only) | No active steering during drift → lean reads less; saves 4 clips |
| Pivot detection | Controller-emitted signal | Game logic owns "what counts as a pivot"; tree consumes events |
| Hit recovery | Returns to `Locomotion/Idle` | Clean recovery beat after hit-stun; not a sub-SM resume |
| `is_slow` mechanism | Condition (controller-thresholded) | Threshold lives in `player.gd` as a tunable export, not in tree expressions |
| Tree topology | Nested: Locomotion sub-SM + Hit + Death-slot | Top-level reactions don't pollute locomotion transitions; one global "→ Hit" wins over N per-state transitions |
| Binding script | Dedicated `player_anim.gd` on the AnimationTree node | Anim concerns separated from physics controller; satisfies the small-unit principle |

## Scope — in and out

**In scope (this spec):**
- Animation state machine topology and transitions
- Clip list with role-in-tree (per-clip authoring details live in the HTML guide)
- AnimationTree parameter interface
- Controller-side additions to `player.gd` (signals, `is_steering()`, pivot detection, three new exports)
- `player_anim.gd` binding script

**Out of scope (deferred):**
- Damage system / `hit_received` signal (slot reserved)
- Health / Death state (slot reserved)
- Combat / attack animations
- Jump / aerial states (game is ground-only)
- Footstep / VFX event dispatch (will use Method Tracks)
- 3D model acquisition, rig, and animation authoring (separate session — uses the HTML guide)
- AnimationTree resource construction in the Godot editor (downstream of this spec and model availability)

## Required clips

Total: **13 clips**, all hand-authored in Blender. This section documents names and roles only. Per-clip authoring expectations — length, loop discipline, pose blocking, sync siblings — live in `docs/animation-authoring-guide.html`.

### Locomotion BlendSpace2D anchors — `Move` state (7 clips)

Axes: X = turn rate `[-1, +1]`, Y = normalized speed `[0, 1]`.

| Position | Clip | Role |
|---|---|---|
| (0, 0) | `idle` | Center anchor — standing pose, subtle breath |
| (0, 0.5) | `walk_fwd` | Forward walk at half speed |
| (-1, 0.5) | `walk_lean_L` | Forward walk with left torso lean |
| (+1, 0.5) | `walk_lean_R` | Forward walk with right torso lean |
| (0, 1) | `run_fwd` | Forward run at full speed |
| (-1, 1) | `run_lean_L` | Forward run with left lean |
| (+1, 1) | `run_lean_R` | Forward run with right lean |

No "idle-turn" clips — the controller never turns in place (rotation always accompanies movement).

### Drift BlendSpace1D anchors — `Drift` state (3 clips)

Axis: normalized speed `[0, 1]`.

| Position | Clip | Role |
|---|---|---|
| 0 | `idle` (shared with Move) | Settle anchor — prevents hard cut entering Idle |
| 0.5 | `drift_walk` | Coast at walk speed (upper body lean-back, arms trailing) |
| 1 | `drift_run` | Coast at run speed |

### One-shots (3 clips)

| Clip | Role |
|---|---|
| `pivot_skid` | Plays on Move → Pivot; auto-advances back to Move at end |
| `dash_burst` | Additive on top of locomotion via OneShot at the BlendTree root |
| `hit_flinch` | Stub; replaced when damage system arrives |

## AnimationTree topology

Root: `BlendTree`.

```
BlendTree (root)
 ├─ Top: StateMachine                    ← input A
 │   ├─ Locomotion: SubStateMachine      ← default
 │   │   ├─ Idle                         ← sub-SM default
 │   │   ├─ Move    (BlendSpace2D)
 │   │   ├─ Drift   (BlendSpace1D)
 │   │   └─ Pivot   (single clip)
 │   ├─ Hit                              ← single clip, stub
 │   └─ Death                            ← FUTURE, slot reserved, no clip
 └─ DashShot: OneShot                    ← input B, additive on A
```

### Top-level StateMachine transitions

| From | To | Trigger | Switch mode | XFade | Priority |
|---|---|---|---|---|---|
| Locomotion | Hit | `is_hit` (one-frame pulse) | Immediate | 0.05s | High |
| Hit | `Locomotion/Idle` | Auto-advance | At-end | 0.15s | — |
| (any) | Death | `is_dead` (latching) | Immediate | 0.10s | Highest (future) |

`Hit → Locomotion/Idle` targets the sub-state explicitly (Godot allows sub-state targeting via `/`) — per the locked decision, hit recovery is a clean reset beat, not a sub-SM resume.

### Locomotion sub-SM transitions

| From | To | Trigger | Switch mode | XFade | Priority |
|---|---|---|---|---|---|
| Idle | Move | `is_steering` true | Immediate | 0.10s | — |
| Move | Drift | `is_steering` false | Immediate | 0.15s | Low |
| Drift | Move | `is_steering` true | Immediate | 0.10s | — |
| Drift | Idle | `is_slow` true | Immediate | 0.20s | — |
| Move | Pivot | `is_pivoting` (one-frame pulse) | Sync | 0.05s | High |
| Pivot | Move | Auto-advance | At-end | 0.10s | — |

**Why no Drift → Pivot:** pivot fires only on sharp `target_v` reversal, and `target_v` is zero while drifting (no steering input). The condition cannot fire from Drift.

**Why Move → Pivot uses the Sync switch mode:** the skid clip must start phase-aligned with the running gait cycle so the foot-plant reads as a real skid, not a teleport.

### DashShot OneShot

| Setting | Value | Reason |
|---|---|---|
| Mix mode | Add | Additive layering — legs keep cycling underneath |
| `fadein_time` | 0.05s | Snappy reaction to dash input |
| `fadeout_time` | 0.20s | Matches tail of impulse decay (~320ms) |
| `autorestart` | false | Re-dash is gated by the controller's cooldown anyway |
| Trigger | `parameters/DashShot/request` fired on `dash_fired` signal | Event-driven, not polled |

### Active flag

`AnimationTree.active = true` set in `_ready()` of `player_anim.gd`. Default is false; missing this is a top "never forget" per the AnimationTree skill.

## Interface contract

The boundary between `player.gd` and the AnimationTree, mediated by `player_anim.gd`.

### Conditions (set per physics frame)

| Parameter path | Source | Pulse type |
|---|---|---|
| `parameters/conditions/is_steering` | `player.is_steering()` | Sustained |
| `parameters/conditions/is_slow` | `player.velocity.length() < player.idle_threshold` | Sustained |
| `parameters/conditions/is_pivoting` | Set by `pivot_started` handler, cleared next frame | **One-frame pulse** |
| `parameters/conditions/is_hit` | Set by `hit_received` handler (FUTURE), cleared next frame | **One-frame pulse** |
| `parameters/conditions/is_dead` | Set by `died` handler (FUTURE) | Latching, never cleared |

One-frame pulse pattern: signal handler sets a boolean flag in `player_anim.gd`; the next `_physics_process` writes the flag to the condition, then sets the flag to false so the next frame writes false. This produces a single-frame `true` window that the StateMachine's advance condition catches.

### Blend positions (set per physics frame)

| Parameter path | Type | Computation |
|---|---|---|
| `parameters/Top/Locomotion/Move/blend_position` | `Vector2` | `(turn_rate, normalized_speed)` |
| `parameters/Top/Locomotion/Drift/blend_position` | `float` | `normalized_speed` |

Derivation:
- `normalized_speed = clampf(velocity.length() / max_speed, 0.0, 1.0)`
- `turn_rate = clampf((rotation.y - prev_rotation_y) / delta / deg_to_rad(turn_rate_deg), -1.0, 1.0)`

`turn_rate` sign: positive = turning right (clockwise from above), consistent with this project's +Z-forward convention. See the existing comment in `_resolve_dash_dir` (`scripts/player.gd`) for why +Z is forward here.

`prev_rotation_y` is tracked inside `player_anim.gd` — the consumer's concern, not exposed by `player.gd`.

### One-shot triggers

| Parameter path | Trigger | Value to set |
|---|---|---|
| `parameters/DashShot/request` | `dash_fired` signal handler | `AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE` |

### Update discipline

All `set()` calls go through a change-guard: cache the last-written value, compare, skip the write if unchanged. Per the AnimationTree skill's `sync_parameter_manager.gd` pattern — writing the same value every frame invalidates the parameter cache and can cause stutter. Exception: one-frame-pulse writes always fire because the explicit `true → false` transition is intentional.

## Controller-side delta

### `scripts/player.gd` — additions

```gdscript
# Signals (new)
signal dash_fired
signal pivot_started

# Tuning exports (new)
@export var pivot_reversal_threshold: float = -0.5  # dot product cutoff (~120° reversal)
@export var pivot_min_speed: float = 2.0            # below this, reversal is too soft to register
@export var idle_threshold: float = 0.1             # speed below which Drift → Idle fires

# Public accessor (new)
func is_steering() -> bool:
    return _steering
```

**Pivot detection** — inserted between step 1 (`target_v` computation) and step 2 (`input_velocity` integration) of the existing `_physics_process`. Requires both `target_v` (newly computed) and the pre-mutation `input_velocity` (last frame's value):

```gdscript
# After step 1, before step 2 — uses current target_v and last-frame input_velocity
if _steering and target_v.length_squared() > 0.0 and input_velocity.length() > pivot_min_speed:
    var prev_dir := input_velocity.normalized()
    var new_dir := target_v.normalized()
    if prev_dir.dot(new_dir) < pivot_reversal_threshold:
        pivot_started.emit()
```

**Dash signal** — single line at the end of `_try_dash`, after `impulse_velocity` is assigned:

```gdscript
dash_fired.emit()
```

That's the entire delta — three signals, three exports, one accessor, two emit calls. No physics behavior changes; no controller feel changes.

### `scripts/player_anim.gd` — new file

```gdscript
class_name PlayerAnimBinding extends AnimationTree

@onready var _player: CharacterBody3D = get_parent()  # Player

var _prev_rotation_y: float = 0.0
var _is_pivoting_pulse: bool = false
var _is_hit_pulse: bool = false  # wired when damage system exists

# Change-guard caches
var _cached_move_blend: Vector2 = Vector2.INF
var _cached_drift_blend: float = INF
var _cached_is_steering: bool = false
var _cached_is_slow: bool = false

func _ready() -> void:
    active = true
    _prev_rotation_y = _player.rotation.y
    _player.dash_fired.connect(_on_dash_fired)
    _player.pivot_started.connect(_on_pivot_started)
    # Future: _player.hit_received.connect(_on_hit_received)

func _physics_process(delta: float) -> void:
    # Clear one-frame pulses set last frame (always-write — intentional false transition)
    set("parameters/conditions/is_pivoting", _is_pivoting_pulse)
    _is_pivoting_pulse = false
    set("parameters/conditions/is_hit", _is_hit_pulse)
    _is_hit_pulse = false

    # Sustained conditions with change-guard
    var steering := _player.is_steering()
    if steering != _cached_is_steering:
        set("parameters/conditions/is_steering", steering)
        _cached_is_steering = steering

    var speed := _player.velocity.length()
    var slow := speed < _player.idle_threshold
    if slow != _cached_is_slow:
        set("parameters/conditions/is_slow", slow)
        _cached_is_slow = slow

    # Blend positions
    var normalized_speed := clampf(speed / _player.max_speed, 0.0, 1.0)
    var rotation_delta := (_player.rotation.y - _prev_rotation_y) / delta
    var turn_rate := clampf(
        rotation_delta / deg_to_rad(_player.turn_rate_deg), -1.0, 1.0
    )
    _prev_rotation_y = _player.rotation.y

    var move_blend := Vector2(turn_rate, normalized_speed)
    if move_blend != _cached_move_blend:
        set("parameters/Top/Locomotion/Move/blend_position", move_blend)
        _cached_move_blend = move_blend

    if normalized_speed != _cached_drift_blend:
        set("parameters/Top/Locomotion/Drift/blend_position", normalized_speed)
        _cached_drift_blend = normalized_speed

func _on_dash_fired() -> void:
    set("parameters/DashShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

func _on_pivot_started() -> void:
    _is_pivoting_pulse = true
```

### `scenes/player.tscn` — additions

- Add `AnimationTree` node as a sibling of `Body` / `Facing` / `Collision`.
- Attach `scripts/player_anim.gd` to it.
- `tree_root`: BlendTree resource (built in the Godot AnimationTree editor dock per the topology section above).
- `anim_player`: NodePath to the AnimationPlayer (which will live on the imported rigged model — wired after the model-import session).
- `parameters/conditions/*` defaults: all `false`.

Edits to `player.tscn` for the AnimationTree node and its sub-resources go through the Godot editor (Inspector + AnimationTree dock). Hand-editing `.tscn` for tree structure is fragile per project gotchas (`docs/godot-gotchas.md`).

## Deferred-room (future-proofing)

### Hit reaction

Slot is active; `hit_flinch` ships as stub. When damage system arrives:
- Add `signal hit_received` and `apply_damage(amount)` method to `player.gd`.
- Wire `_player.hit_received.connect(_on_hit_received)` in `player_anim.gd._ready()`; the `_on_hit_received` handler sets `_is_hit_pulse = true`.
- Optionally promote `Hit` to a BlendSpace2D for directional variants (`hit_front` / `hit_back` / `hit_L` / `hit_R`) using a hit-direction parameter. Interface stays the same.

### Death

Slot reserved at top level (no clip authored). When health system arrives:
- Add `Death` state as peer of `Locomotion` / `Hit`.
- Add `signal died` on `player.gd` (emitted once at zero HP).
- Add `is_dead` condition wire-up in `player_anim.gd`; the `_on_died` handler latches a flag that never clears.
- Highest-priority transition `(any) → Death`. Terminal — no outgoing transition.

### Combat / attacks

Two viable shapes — decision belongs in the combat spec, not here:

| Approach | When it fits |
|---|---|
| **Top-level peer states** (`Attack1`, `Attack2`, combo via auto-advance) | Full-body attacks; player can't move while attacking |
| **Upper-body BlendTree layer** (Add2 with bone mask) | Attack-while-moving; legs keep cycling |

The current tree supports either without restructure — adding peers is additive; adding a layer means wrapping the BlendTree root in another BlendTree.

### Jump / aerial

Explicitly out per movement spec. If ever added: new `Airborne` sub-SM (Jump / Fall / Land) as peer of `Locomotion`, transition `Locomotion → Airborne` on `is_airborne`.

### Footstep / event hooks

`AnimationPlayer.Method Track` keyframes call a generalized `dispatch_event(name, metadata)` method on a dispatcher node. Audio / VFX systems subscribe to the signal. Per the AnimationTree skill's `Animation-Event-Dispatcher` pattern. Not built here; attaches without modifying the tree.

### Performance

Single player character — AnimationTree cost is negligible. When NPCs reuse this tree at scale, the AnimationTree skill's `Tree-Complexity-Culler` pattern (swap `tree_root` between detailed/simplified via `VisibleOnScreenNotifier3D`) applies. Don't pre-optimize.

## Implementation order (for the plan that follows this spec)

1. **Controller delta** — add signals, pivot detection, `is_steering()`, three exports to `player.gd`. Verify with F5: signals fire (print on emit), no regressions to controller feel. **Doable now without a model.**
2. **Model + rig in Blender** — separate session. Uses `docs/animation-authoring-guide.html` as the rig brief.
3. **Author 13 clips in Blender** — uses `docs/animation-authoring-guide.html` as per-clip blueprint.
4. **Export & import to Godot** — per `docs/asset-pipeline.md`.
5. **Build AnimationTree resource** in the Godot editor (BlendTree → StateMachine + sub-SM + OneShot per the topology section above).
6. **Create `player_anim.gd`**, attach to AnimationTree node, wire signals.
7. **Verify in F5 play:** locomotion blends correctly across speed × turn, drift coast plays on release, pivot snaps on cursor flip, dash flair layers over locomotion. Tune `idle_threshold`, `pivot_reversal_threshold`, `pivot_min_speed` live.

Step 1 is independent of art and can proceed immediately after this spec is approved. Steps 2–7 are sequential.

## Related docs

- `docs/superpowers/specs/2026-05-24-rts-movement-depth-design.md` — movement controller spec (this spec extends it)
- `docs/animation-authoring-guide.html` — per-clip Blender authoring reference (the brief for steps 2–3 above)
- `docs/asset-pipeline.md` — Blender → Godot import discipline
- `docs/blender-mcp-guide.md` — Blender MCP conventions (if MCP-assisted authoring is used)
- `docs/godot-gotchas.md` — project-portable Godot quirks (AnimationTree `active` flag, `.tscn` null-override trap relevant during Inspector tuning of new exports)
