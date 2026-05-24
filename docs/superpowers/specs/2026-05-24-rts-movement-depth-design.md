# Player Movement — Smash-Flavored Depth Redesign

**Date:** 2026-05-24
**Status:** Approved design, pre-implementation
**Supersedes:** `2026-05-23-player-controller-design.md` (placeholder click-to-move). The placeholder controller is in the repo and verified working; this redesign replaces its core mechanics with a momentum-driven hold-to-direct system.

## Purpose

Replace the placeholder click-to-move controller with a movement system that has Smash-Bros-level depth: heavy momentum, continuous directional input, dash with impulse channel, and emergent skill expression (drift, pivot, foxtrot, dash-curves, DI-through-impulses).

The goal is a movement system where a skilled player visibly moves better than an unskilled one — not because of unlocks, but because of input mastery.

## Game context (locked decisions)

| Dimension | Choice | Implication |
|---|---|---|
| Game shape | Solo / co-op vs. smart AI (ARPG family) | Depth comes from outplaying AI, not human opponents |
| Movement role | Movement **enables** combat | Movement positions and evades; combat is separate inputs |
| Momentum profile | Drifty / Smash-like | Heavy accel, long coast on release, sliding past targets is normal |
| Input model | Hold RMB to direct — cursor is the analog stick | Continuous directional input enables Smash-style depth mechanics |
| Architecture | Hybrid: kinematic core + impulse channel | Predictable steering velocity, separate channel for knockback/dash thrust |

## What this replaces

- `NavigationAgent3D` is removed from the player. Pathfinding-around-obstacles is the wrong abstraction when steering velocity directly. NavAgent stays in the project for future enemy AI.
- `target_position` / arrival-snap behavior — gone. There's no destination; there's a steering signal.
- Instant max-speed / instant-stop defaults — replaced by accel/friction integration.
- Right-click on press semantics — changed from "set destination once" to "start steering toward cursor (held)."

## Scene structure

### `scenes/player.tscn` — updated

```
Player (CharacterBody3D)              ← script: scripts/player.gd
├── Body (MeshInstance3D)             ← unchanged
├── Facing (MeshInstance3D)           ← unchanged
└── Collision (CollisionShape3D)      ← unchanged
```

The NavigationAgent3D child node is removed. All other visuals stay.

### `scenes/main.tscn` — unchanged

The `NavigationRegion3D` and baked nav mesh remain in place for future enemy AI use. The Player instance no longer interacts with them.

## Controller logic — `scripts/player.gd` (rewrite)

### State

```gdscript
extends CharacterBody3D

# Tunable exports — see "Tuning surface" section
@export var max_speed: float = 7.0
@export var accel: float = 24.0
@export var friction: float = 14.0
@export var turn_rate_deg: float = 540.0
@export var walk_threshold: float = 2.0
@export var dash_strength: float = 16.0
@export var dash_cooldown: float = 0.4
@export var impulse_decay: float = 50.0

# Internal channels
var input_velocity: Vector3 = Vector3.ZERO
var impulse_velocity: Vector3 = Vector3.ZERO

# Steering state
var _steering: bool = false           # RMB held this frame
var _cursor_world: Vector3 = Vector3.ZERO

# Dash state
var _dash_ready_at: float = 0.0       # absolute Time.get_ticks_msec / 1000.0
```

### Input handling

- `_input` listens for `InputEventMouseButton` with `BUTTON_RIGHT`:
  - On press → `_steering = true`
  - On release → `_steering = false`
- `_input` listens for the `dash` input action (mapped to Spacebar by default):
  - On press → attempt dash (see Dash mechanic).
- `_unhandled_input` is NOT used — RMB and dash are gameplay-level, not UI-overlay-passthrough.

### Cursor → world projection (every physics tick)

A helper `_refresh_cursor_world()` projects the current mouse position into the XZ plane (`y = 0`) using the active camera, and stores the hit point in `_cursor_world`. This is the same math as the placeholder's ray-vs-y=0 plane intersection, but performed every tick (not just on click) so steering tracks the cursor continuously.

Called from `_physics_process` only when `_steering` is true, and also from `_try_dash()` so a dash fired during steering uses a fresh cursor sample.

### Per-physics-tick integration

```gdscript
func _physics_process(delta: float) -> void:
    var now := Time.get_ticks_msec() / 1000.0

    # 1. Compute target input_velocity from steering signal
    var target_v := Vector3.ZERO
    if _steering:
        _refresh_cursor_world()  # project cursor → XZ plane, stores _cursor_world
        var to_cursor := _cursor_world - global_position
        to_cursor.y = 0.0
        var distance := to_cursor.length()
        if distance > 0.0001:
            var dir := to_cursor / distance
            var magnitude := clamp(distance / walk_threshold, 0.0, 1.0)
            target_v = dir * max_speed * magnitude

    # 2. Integrate input_velocity (accel toward target, friction toward zero)
    # Note: `target_v` is non-zero only when `_steering` is true (set in step 1),
    # so guarding only on `target_v != Vector3.ZERO` is sufficient.
    if target_v != Vector3.ZERO:
        input_velocity = input_velocity.move_toward(target_v, accel * delta)
    else:
        input_velocity = input_velocity.move_toward(Vector3.ZERO, friction * delta)

    # 3. Decay impulse_velocity
    impulse_velocity = impulse_velocity.move_toward(Vector3.ZERO, impulse_decay * delta)

    # 4. Combine and apply
    velocity = input_velocity + impulse_velocity

    # 5. Facing follows velocity heading (smoothed)
    var horizontal := Vector3(velocity.x, 0.0, velocity.z)
    if horizontal.length_squared() > 0.01:
        var target_yaw := atan2(horizontal.x, horizontal.z)
        var max_step := deg_to_rad(turn_rate_deg) * delta
        rotation.y = _step_angle(rotation.y, target_yaw, max_step)

    move_and_slide()
```

### Dash mechanic

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
    if _steering:
        var to_cursor := _cursor_world - global_position
        to_cursor.y = 0.0
        if to_cursor.length_squared() > 0.0001:
            return to_cursor.normalized()
    var v := Vector3(velocity.x, 0.0, velocity.z)
    if v.length_squared() > 0.01:
        return v.normalized()
    # Fall back to facing. The Facing cone is oriented along local +Z (per
    # placeholder spec), so transform.basis.z is where the player visually
    # points. (Godot's canonical forward is -basis.z; overridden here for
    # visual consistency.)
    return transform.basis.z
```

### Public API for external impulses

```gdscript
func apply_impulse(impulse: Vector3) -> void:
    impulse_velocity += Vector3(impulse.x, 0.0, impulse.z)
```

Used by future enemy attacks, explosions, etc. Defined now, no caller yet. The additive merge means knockback layers on top of any in-flight dash impulse, capped only by `impulse_decay`. The steering channel is unaffected — players retain DI through knockback.

**Asymmetry note:** Dash *overwrites* the impulse channel (`= dir * dash_strength`); external callers *add* to it (`+=`). This is intentional. A player dash is a deliberate commitment — it takes full ownership of the impulse channel and discards any prior impulse. External impulses (knockback, explosions) layer on top of whatever's there, so multiple environmental forces can stack. The result: dashing during knockback redirects you cleanly; getting knocked during a dash extends and angles the existing trajectory.

### `_step_angle` helper

Unchanged from the placeholder controller — shortest-arc step from `from` to `to`, clamped to `max_delta`.

## Input map additions

`project.godot` needs a new input action:

```
dash = [InputEventKey { keycode = KEY_SPACE }]
```

The name `dash` (not `ui_dash`) follows the project convention documented in the previous handoff (custom actions avoid the `ui_*` prefix to remain visible in the Input Map editor panel).

## Tuning surface

All values are `@export` and live-editable in the Inspector during play. The numbers below are starting points for the feel-iteration phase — the entire point of this spec is to make these dials available.

| Export | Default | Units | Effect |
|---|---|---|---|
| `max_speed` | 7.0 | m/s | Top sustained speed when input is at full magnitude |
| `accel` | 24.0 | m/s² | How fast `input_velocity` ramps toward `target_v`. ~300ms to reach max_speed |
| `friction` | 14.0 | m/s² | How fast `input_velocity` bleeds toward zero when no input. ~500ms coast |
| `turn_rate_deg` | 540.0 | deg/s | Facing rotation rate. Lower = more visible turn lag (depth tell) |
| `walk_threshold` | 2.0 | m | Cursor distance at which speed saturates to full. Below this, target velocity scales linearly with distance — so a cursor 1m from the player at walk_threshold=2.0 gives 50% speed. Above this, saturated at 1.0 (further-away cursor doesn't go faster) |
| `dash_strength` | 16.0 | m/s | Initial magnitude of `impulse_velocity` on dash. ~2.3× max_speed |
| `dash_cooldown` | 0.4 | s | Minimum gap between dashes |
| `impulse_decay` | 50.0 | m/s² | Rate at which `impulse_velocity` bleeds toward zero. ~320ms decay from full dash |

## Emergent depth — what comes for free from the architecture

These are not separately coded mechanics; they fall out of Sections "Per-physics-tick integration" and "Dash mechanic":

- **Drift slides** — heavy friction means RMB release leaves residual velocity. Skill = aim the slide.
- **Pivot skids** — sharp cursor reversal forces `input_velocity` through zero. Visible skid; skilled players time pivots to retain speed.
- **Cursor-jiggle / dash-dance equivalent** — small cursor oscillations near the player produce twitchy micro-positioning (walk_threshold gradient amplifies this).
- **DI through impulses** — knockback via `apply_impulse` does NOT block steering. Player drifts knockback trajectory by holding cursor off-axis. (Activates when enemies exist.)
- **Curved dashes** — dash fires impulse in one direction; steering during the ~320ms decay angles the trajectory. Same shape as Smash wavedash arcs.
- **Foxtrot-style burst-stop** — very brief RMB taps build partial velocity, then coast. Chainable.
- **Facing-velocity tells** — facing follows velocity, smoothed. Pros stay smooth; over-corrections are visible.
- **Slope sliding** *(future, no code change needed)* — when terrain has slopes, sample gravity component and add via `apply_impulse`.
- **Wall-cancel slide** *(future, free from move_and_slide)* — sliding along walls preserves tangential velocity. Combine with steering to ride or escape walls.

## Verification

The implementation is done when, after F5:

1. Holding right-click toward a direction causes the character to accelerate smoothly toward that direction.
2. Releasing right-click causes the character to coast and decelerate over roughly half a second; the longer the prior hold, the longer the slide.
3. Cursor distance from the player visibly modulates speed: cursor very close = walk; cursor far = full run.
4. Sharp reversal of cursor direction produces a visible pivot skid (character momentarily moves in old direction while turning).
5. Tapping spacebar fires a directional burst (the dash). During the dash, steering still affects trajectory — pressing dash and then steering 30° off the dash axis produces a curved arc.
6. Two dashes in rapid succession do not stack — the second redirects the impulse channel. A dash during cooldown is ignored.
7. All tunable values in the Inspector change feel live during play, without restarting.
8. Walking into a wall: the player slides along it without snagging (CharacterBody3D + move_and_slide behavior).

## Out of scope (designed-in, deferred)

- **Knockback callers** — `apply_impulse` exists, no caller. Wire when enemies arrive.
- **Animation cancels** — needs combat first.
- **Stamina / resource gating dashes** — cooldown is sufficient for v1.
- **WASD secondary input** — explicitly chose hold-to-direct exclusively.
- **Slope handling** — flat plane only.
- **Multi-charge dash, dash-into-attack cancels** — none in v1.
- **Aerial state, jump, fast-fall** — top-down ground-only game.
- **Stop / hold-position command** — RMB release with friction is the stop.

## File changes

| Path | Action |
|---|---|
| `scripts/player.gd` | Rewrite (placeholder is 57 lines; new will be ~80-100) |
| `scenes/player.tscn` | Remove NavigationAgent3D child node |
| `project.godot` | Add `dash` input action (Spacebar) |

`scenes/main.tscn`, `scripts/fullscreen_toggle.gd`, the camera, the ground, the nav region, the autoloads — all unchanged.

## Open questions for the iteration phase

These are intentionally NOT decided in this spec. They surface during feel-tuning:

- Whether `walk_threshold` should be a hard cutoff or a softened curve.
- Whether facing should optionally follow cursor instead of velocity once a combat-aim system exists.
- Whether dashes during cooldown should *queue* (fire as soon as cooldown ends) or *drop*. Current: drop.
- Whether the impulse channel should clamp magnitude or be unbounded.
- Whether to add a brief "lockout" window after dash where steering is dampened, for clearer commitment feel.
