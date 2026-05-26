# Player Controller — Click-to-Move (Placeholder)

**Date:** 2026-05-23
**Status:** Approved design, pre-implementation
**Convention update (2026-05-25):** This spec describes the placeholder Facing cone as pointing along local **+Z**, and the controller followed that convention. On 2026-05-25 the project flipped to Godot's canonical **-Z forward** (see `docs/godot-gotchas.md`). References to "+Z" below are historical; the current code in `scripts/player.gd` uses -Z forward.

## Purpose

Scaffold a placeholder player avatar with click-to-move (Dota/MOBA-style) controls, then use this session to iterate on movement feel. The real 3D model, rig, and animations come later — visuals are stand-in geometry.

## Goals (in scope)

- A `Player.tscn` scene that can be dropped into any world scene.
- Right-click on the ground → character pathfinds and walks there.
- Character auto-rotates to face the direction of travel (smoothed, not snap).
- All feel-relevant values exposed in the Inspector for live tuning.
- Navigation handled via `NavigationAgent3D` against a baked `NavigationRegion3D` — architecturally "real" from day one so obstacles can be added later without rewriting.

## Non-goals (deferred)

- Real character model, rig, AnimationTree, animations.
- Camera follow (camera stays fixed at world origin; player visible because they stay within the 100×100 plane).
- Attack-move, queued commands, formation movement.
- Stop / hold-position commands.
- Health, combat, hitboxes.
- Pathfinding around obstacles (no obstacles in the scene yet — the architecture supports them but we don't add any here).

## Scene structure

### New: `scenes/player.tscn`

```
Player (CharacterBody3D)              ← script: scripts/player.gd
├── Body (MeshInstance3D)             ← CapsuleMesh, radius 0.4, height 1.8
├── Facing (MeshInstance3D)           ← CylinderMesh (cone), points along +Z
├── Collision (CollisionShape3D)      ← CapsuleShape3D matching Body
└── NavAgent (NavigationAgent3D)
```

- `Player` root sits at scene origin so its position represents foot-ground contact.
- `Body` capsule has local position y = 0.9 so the feet are at y = 0 when the Player root is at y = 0.
- `Facing` is a separate `MeshInstance3D` (not painted into the capsule material) so its mesh and material can be swapped freely without touching the body.

### Updates to `scenes/main.tscn`

- Wrap the existing `Ground` (MeshInstance3D) inside a new `NavigationRegion3D` node so the nav mesh bakes from the ground geometry.
- Instance `Player.tscn` at the world origin.

The Sun, Env, and Camera_Dota nodes are unchanged.

## Placeholder visuals

### Body — CapsuleMesh
- `radius = 0.4`
- `height = 1.8`
- Position: `(0, 0.9, 0)` (puts feet at y = 0)
- Material: light-gray StandardMaterial3D (~`Color(0.7, 0.7, 0.75)`)

### Facing indicator — CylinderMesh used as a cone
- `top_radius = 0.0`
- `bottom_radius = 0.12`
- `height = 0.5`
- Rotation: `-90°` around the X axis so the cone's point travels along `+Z` (Godot's forward convention)
- Position: roughly `(0, 1.5, 0.35)` — base embedded near the top of the head, point cantilevered forward like a directional nose
- Material: bright orange StandardMaterial3D (~`Color(1.0, 0.45, 0.0)`) so it pops against the dark grid from the Dota camera angle

### Collision — CapsuleShape3D
- `radius = 0.4`, `height = 1.8` — matches the Body visual exactly
- CollisionShape3D position: `(0, 0.9, 0)` to align with Body

## Controller logic — `scripts/player.gd`

### Input handling

- Listen for `InputEventMouseButton` with `BUTTON_RIGHT` pressed.
- On press, build a world-space ray from the active Camera3D through the mouse cursor:
  - `Camera3D.project_ray_origin(mouse_pos)` + `Camera3D.project_ray_normal(mouse_pos)`
- Intersect that ray mathematically with the plane `y = 0` (no physics raycast — the ground has no StaticBody3D and we don't need one for a flat plane).
- Assign the intersection point to `nav_agent.target_position`.

### Per-physics-frame movement

In `_physics_process(delta)`:

1. If `nav_agent.is_navigation_finished()`, set `velocity = Vector3.ZERO` and skip the rest.
2. Otherwise, compute `next_pos = nav_agent.get_next_path_position()`; project the offset onto the horizontal plane (`var to_next = next_pos - global_position; to_next.y = 0`); then `desired_dir = to_next.normalized()`.
3. **Turning:** smoothly rotate the player's Y rotation toward `atan2(desired_dir.x, desired_dir.z)`, clamped by `turn_rate_deg * delta` per frame.
4. **Translation:** set `velocity = desired_dir * max_speed`, then call `move_and_slide()`.

Turning is decoupled from translation — the player can move while still rotating to align, which produces a natural arc rather than a snap.

### Exported tunables (live-editable in the Inspector during play)

```gdscript
@export var max_speed: float = 6.0            # m/s
@export var turn_rate_deg: float = 720.0      # degrees / second
```

NavigationAgent3D's `path_desired_distance` and `target_desired_distance` are left at the Godot defaults (1.0 each) initially — they affect arrival-snap feel and may be tuned during the session.

## NavigationRegion3D setup

- Add `NavigationRegion3D` as a sibling of `Sun`/`Env`/`Camera_Dota` in `main.tscn`.
- Reparent the existing `Ground` (MeshInstance3D) underneath it.
- Bake the nav mesh once in the editor (one-time UI action). With no obstacles, this produces a single rectangle covering the 100×100 plane.
- NavigationAgent3D on the Player picks up this region automatically by being in the same world.

## File changes

| Path | Action |
|---|---|
| `scenes/player.tscn` | Create |
| `scripts/player.gd` | Create |
| `scenes/main.tscn` | Modify — wrap Ground in NavigationRegion3D, instance Player |

No changes to `project.godot`, autoloads, the fullscreen toggle, the camera, or any of the materials/shaders ported earlier.

## Verification

The implementation is done when, after F5:

1. The player capsule appears at world origin with the orange cone pointing along +Z.
2. Right-clicking anywhere on the visible ground causes the player to walk to that point in a straight line.
3. The player rotates smoothly to face the direction of travel (no instant snap; turning lag is visible at sharp direction changes).
4. The player stops when it reaches the destination.
5. The orange cone always points in the direction of travel — useful as a debug check that facing tracks heading.
6. Tweaking `max_speed` and `turn_rate_deg` in the Inspector during a play session changes feel live, without restarting.

## Open tuning surface (for the iteration phase that follows implementation)

These are the dials we will turn during the feel-finetuning portion of this session:

- `max_speed` (currently 6.0)
- `turn_rate_deg` (currently 720.0)
- NavigationAgent3D `path_desired_distance` (currently 1.0)
- NavigationAgent3D `target_desired_distance` (currently 1.0)
- Whether to add an acceleration ramp (currently: none — instant max speed)
- Whether to add a deceleration ramp on arrival (currently: instant stop when `is_navigation_finished()`)
