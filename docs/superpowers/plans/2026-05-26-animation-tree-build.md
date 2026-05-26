# Animation State Machine — AnimationTree Resource Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. This plan is editor-driven (AnimationTree dock + Inspector), so subagent-driven-development is a poor fit — each task is "user clicks X, agent reads `player.tscn` to verify Y." Use inline execution.

**Goal:** Build the `AnimationTree` resource in `scenes/player.tscn` per the topology in the animation state machine spec. Add the node, configure the BlendTree, populate the StateMachine + sub-StateMachine + BlendSpaces + OneShot, wire all transitions. Leave the binding script (`player_anim.gd`) for Step 6.

**Architecture:** Single scene edit. The `AnimationTree` node is added to `scenes/player.tscn` as a sibling of the imported model and `Collision`. Its `tree_root` is a `BlendTree` containing a top-level `StateMachine` (named `Top`) that drives a sub-`StateMachine` (`Locomotion`) plus a sibling `Hit` state, fed through a `OneShot` (named `DashShot`) for additive dash flair. The node names matter — `player_anim.gd` (Step 6) references parameter paths like `parameters/Top/Locomotion/Move/blend_position`, so naming must be exact.

**Tech Stack:** Godot 4.6.2 editor (AnimationTree dock + Inspector). No GDScript in this plan.

**Spec:** `docs/superpowers/specs/2026-05-24-animation-state-machine-design.md` (sections "AnimationTree topology", "Interface contract")

---

## Project-specific notes (READ FIRST)

- **This is editor work.** All structural changes go through the AnimationTree dock (bottom panel when the `AnimationTree` node is selected) and the Inspector. Hand-editing `.tscn` for tree structure is a known fragility — see `docs/godot-gotchas.md`. Property-tweak hand-edits (e.g., setting a fade time) are fine post-editor.
- **Godot 4.6.2 dock UI affordances** (see `docs/godot-gotchas.md` entry "AnimationTree dock UI shifted in Godot 4.6.2"):
  - Enter a sub-editor (StateMachine, SubStateMachine, BlendTree, BlendSpace1D/2D): click the **Open Editor** button in the node header. (Double-click does not enter.)
  - Rename a node: edit the inline name field on the node itself. (No right-click → Rename menu.)
  - Set Start state of a StateMachine: drag from the green `Start` node to the desired state via the Connect Nodes tool. (No "Set as Start" menu.)
- **DO NOT use `mcp__godot-mcp__node` to mutate the scene.** Historical bug in this project. Read-only MCP tools (`mcp__godot-mcp__editor get_state`, `mcp__godot-mcp__animation list_players` / `get_info`, `mcp__godot-mcp__scene open`) are safe for verification. The user clicks in the editor; the agent reads `player.tscn` and uses MCP read-only tools to verify.
- **Don't attach `scripts/player_anim.gd`.** That's Step 6. The `script` slot on the AnimationTree node stays empty for this plan.
- **Don't set `active = true`.** Default is `false`; leave it. Step 6's `_ready()` flips it on.
- **Don't remove `@warning_ignore("unused_signal")` from `player.gd`.** Those suppressions are removed in Step 6 when `player_anim.gd` connects.
- **Don't add a `Death` state.** The spec marks Death as a future slot. Its peer position in the topology is architecturally reserved; no node is added now. (Adding an empty Animation node here would either reference an empty clip or warn. Step 6+ adds Death properly when the health system arrives.)
- **The spec text says "13 clips" but the unique-name count is 12.** `idle` is double-counted: once as Move's `(0, 0)` anchor and once as Drift's `0` anchor (single clip serving both roles). The `.glb` exposes exactly 12 unique clips. Fix the spec text as Task 10 of this plan.
- **Embedded game tab gotcha.** Not used in this plan — F5 verification confirms the scene loads, but the AnimationTree won't be "live" until Step 6. If the user does F5 anyway and input fails, click "Make Floating" on the Game tab.
- **Save the scene after each editor task** (`Cmd+S`). The `.tscn` doesn't update on disk until save; agent's verification reads stale state otherwise.
- **Commit cadence.** Each task ends with a `git add scenes/player.tscn && git commit -m <conventional>` step. Matches the per-task discipline from Step 1.

---

## Pre-flight already done

- `assets/models/player.glb` imported (commit `8d8966a`). AnimationPlayer exposes all 12 clips.
- `scenes/player_inherited.tscn` is the inherited scene wrapping the `.glb` — instances it as `player`. This is what Task 1 below instances into `scenes/player.tscn`.
- Steps 1-4 of the 7-step roadmap are complete. Step 5 is this plan. Step 6 is the next session.

---

### Task 1: Replace cone placeholder with player model instance in `player.tscn`

**Files:**
- Modify: `scenes/player.tscn`

The current `player.tscn` has `Body` (capsule) and `Facing` (cone) as visual placeholders, and a `Collision` capsule. We replace the visual placeholders with an instance of `scenes/player_inherited.tscn` (which contains the imported `.glb`'s scene tree, including the `AnimationPlayer`). `Collision` stays. The new instance must be named `Model` so subsequent NodePath references are stable.

- [ ] **Step 1: Open `scenes/player.tscn` in the editor**

USER ACTION: In Godot, open `scenes/player.tscn` (FileSystem dock → double-click). The Scene panel should show: `Player (CharacterBody3D) → Body, Facing, Collision`.

- [ ] **Step 2: Delete the `Body` and `Facing` placeholder nodes**

USER ACTION: In the Scene panel:
1. Right-click `Body` → Delete Node (or select and press Delete).
2. Right-click `Facing` → Delete Node.

Expected: Scene panel now shows `Player → Collision` only.

- [ ] **Step 3: Instance `player_inherited.tscn` as child of `Player`, rename to `Model`**

USER ACTION:
1. Right-click `Player` (the root) → Instantiate Child Scene → select `res://scenes/player_inherited.tscn`.
2. The new child appears named `player` (lowercase, from the inherited scene's root name).
3. Rename it: right-click → Rename → `Model`.

Expected: Scene panel shows `Player → Model, Collision`. `Model` is a scene instance (chain-link icon next to its name).

- [ ] **Step 4: Save and verify `.tscn`**

USER ACTION: `Cmd+S` to save.

AGENT ACTION: Read `scenes/player.tscn`. Verify:
- `Body` and `Facing` nodes are gone (no `MeshInstance3D` with those names, no `CapsuleMesh`/`CylinderMesh` sub_resources).
- A new `Model` node exists with `instance = ExtResource(...)` pointing to `player_inherited.tscn`.
- `Collision` node and its `CapsuleShape3D` sub_resource are unchanged.

If `Body` or `Facing` sub_resources (`CapsuleMesh_body`, `StandardMaterial3D_body`, `CylinderMesh_facing`, `StandardMaterial3D_facing`, `CapsuleShape3D_collision` — keep the collision one) still appear in the `.tscn` header, they're orphan sub_resources — open and re-save the scene to clean them. (Godot does this automatically on save.)

- [ ] **Step 5: F5 sanity check**

USER ACTION: Press F5. Pick `scenes/main.tscn` if prompted.

Expected:
- Scene runs without parser/import errors.
- The player character renders (model visible — possibly at the wrong vertical offset since the `.glb`'s pivot may differ from the old cone's offset, that's fine for now and tuned later).
- Movement still works (WASD/RMB or whatever the project uses).

If parser errors fire, check the editor's bottom panel ("Output" or "Errors") for the specific message. Likely culprits: invalid path on the `instance` ExtResource (check the UID matches `scenes/player_inherited.tscn`).

ESC to stop.

- [ ] **Step 6: Commit**

```bash
git add scenes/player.tscn
git commit -m "feat(player.tscn): replace cone placeholder with imported player model

Removes Body/Facing capsule+cone debug meshes; instances
scenes/player_inherited.tscn as 'Model' child of Player. Collision shape
unchanged. Unblocks Step 5 AnimationTree wiring (anim_player NodePath
needs the AnimationPlayer reachable via Model/AnimationPlayer)."
```

---

### Task 2: Add `AnimationTree` node with `anim_player` NodePath wired

**Files:**
- Modify: `scenes/player.tscn`

Add the `AnimationTree` node as a sibling of `Model` and `Collision`. Set its `anim_player` NodePath to point to the imported `AnimationPlayer`. Leave `tree_root` null, `active` false, and `script` empty — those are populated in later tasks / Step 6.

- [ ] **Step 1: Add `AnimationTree` node**

USER ACTION: In the Scene panel for `player.tscn`:
1. Right-click `Player` → Add Child Node → search "AnimationTree" → Create.
2. The new node appears as `AnimationTree` (default name — keep it).

Expected: Scene panel shows `Player → Model, Collision, AnimationTree`.

- [ ] **Step 2: Set `anim_player` NodePath**

USER ACTION:
1. Select `AnimationTree` in the Scene panel.
2. In the Inspector, find the `Anim Player` property (under the AnimationTree section).
3. Click the dropdown / browser button → navigate the scene tree → select `Model/AnimationPlayer`.
4. Verify the NodePath in the Inspector now reads `Model/AnimationPlayer` (or equivalent relative path).

Expected: No red error on the property; the Inspector shows the path resolves.

- [ ] **Step 3: Save and verify `.tscn`**

USER ACTION: `Cmd+S`.

AGENT ACTION: Read `scenes/player.tscn`. Verify a new node block:

```
[node name="AnimationTree" type="AnimationTree" parent="."]
anim_player = NodePath("Model/AnimationPlayer")
```

Confirm:
- No `tree_root = SubResource(...)` line yet (that's Task 3).
- No `script = ...` line.
- No `active = true` line (default `false` is implicit; absence is correct).
- No `parameters/...` lines.

- [ ] **Step 4: Commit**

```bash
git add scenes/player.tscn
git commit -m "feat(player.tscn): add empty AnimationTree node, wire anim_player

Adds AnimationTree as sibling of Model/Collision. anim_player NodePath
points to Model/AnimationPlayer. tree_root, active, and script are
intentionally unset — Tasks 3-9 build tree_root via the editor; Step 6
attaches player_anim.gd and sets active=true."
```

---

### Task 3: Build root BlendTree shell — `Top` (StateMachine) + `DashShot` (OneShot)

**Files:**
- Modify: `scenes/player.tscn`

Set `tree_root` to a new `BlendTree`. Inside it: add a `StateMachine` node named `Top`, a `OneShot` node named `DashShot`, and an `Animation` node referencing the `dash_burst` clip. Wire them: `Top → DashShot.in`, `dash_burst → DashShot.shot`, `DashShot → Output`. Configure DashShot mix mode and fade times per spec.

The Godot 4 `OneShot` has two inputs (`in` for the underlying loop, `shot` for the one-shot clip) and a `mix_mode` (Blend or Add). `Add` is what the spec wants: when fired, `dash_burst` is added on top of the StateMachine's output.

- [ ] **Step 1: Create the BlendTree as `tree_root`**

USER ACTION:
1. Select `AnimationTree` in the Scene panel.
2. The bottom panel auto-opens the "AnimationTree" tab. (If not: click the AnimationTree tab in the bottom-of-screen tab bar.)
3. In the AnimationTree dock, at the top, the "Root" dropdown shows `[empty]`. Click it → select `New BlendTree`.

Expected: The dock now shows a BlendTree visual editor with a single `Output` node.

- [ ] **Step 2: Add the `Top` StateMachine node**

USER ACTION (inside the BlendTree visual editor):
1. Right-click in the empty grid → Add Node → StateMachine.
2. A new `StateMachine` node appears. Rename it to `Top`: right-click the node → Rename → `Top`.

Expected: A `Top` node visible in the BlendTree grid.

- [ ] **Step 3: Add the `DashShot` OneShot node**

USER ACTION:
1. Right-click in the grid → Add Node → OneShot.
2. Rename to `DashShot`.

Expected: `DashShot` node visible with two input ports (`in`, `shot`) and one output.

- [ ] **Step 4: Add the `dash_burst` Animation node**

USER ACTION:
1. Right-click in the grid → Add Node → Animation.
2. The new `Animation` node appears with a dropdown of available clips. Select `dash_burst`.
3. Leave its name as `Animation` (only one Animation node lives at the root level; collision-free).

Expected: An `Animation` node showing `dash_burst` as its clip.

- [ ] **Step 5: Wire the connections**

USER ACTION (drag from output port to input port in the visual editor):
1. `Top.output → DashShot.in` (drag from Top's right side to DashShot's "in" input).
2. `Animation.output → DashShot.shot` (drag from the dash_burst Animation node's output to DashShot's "shot" input).
3. `DashShot.output → Output.in` (drag from DashShot's output to the Output node's input).

Expected: Three connection lines visible. No "orphan" red highlights.

- [ ] **Step 6: Configure DashShot parameters**

USER ACTION:
1. Select the `DashShot` node in the BlendTree (click once on it).
2. Inspector now shows OneShot properties.
3. Set:
   - `Mix Mode`: `Add` (dropdown)
   - `Fadein Time`: `0.05`
   - `Fadeout Time`: `0.20`
   - `Autorestart`: `false` (unchecked)

Expected: Inspector values match. The DashShot node in the BlendTree grid may render slightly differently (Add mode often shown with a `+` icon).

- [ ] **Step 7: Save and verify `.tscn`**

USER ACTION: `Cmd+S`.

AGENT ACTION: Read `scenes/player.tscn`. Verify:
- A new sub_resource of type `AnimationNodeBlendTree` is present and assigned as `tree_root` on the AnimationTree node.
- The BlendTree's `nodes/Top/node` references an `AnimationNodeStateMachine` sub_resource.
- The BlendTree's `nodes/DashShot/node` references an `AnimationNodeOneShot` sub_resource with `mix_mode = 1` (Add), `fadein_time = 0.05`, `fadeout_time = 0.2`, `autorestart = false`.
- The BlendTree's `nodes/Animation/node` references an `AnimationNodeAnimation` with `animation = &"dash_burst"`.
- `node_connections` array contains entries linking `Top→DashShot input 0`, `Animation→DashShot input 1`, and `DashShot→output input 0` (or equivalent serialization).

If `node_connections` is missing, the wiring step (Step 5) didn't actually create connections — go back and drag the connections.

- [ ] **Step 8: Commit**

```bash
git add scenes/player.tscn
git commit -m "feat(player.tscn): build AnimationTree root BlendTree shell

Sets tree_root to BlendTree containing Top (StateMachine, input A),
DashShot (OneShot, additive layer with 0.05s fadein / 0.20s fadeout /
no autorestart), and an Animation node referencing dash_burst. Wired:
Top→DashShot.in, dash_burst→DashShot.shot, DashShot→Output. States and
transitions inside Top come next."
```

---

### Task 4: Top-level StateMachine — add `Locomotion` (sub-SM) + `Hit` (clip)

**Files:**
- Modify: `scenes/player.tscn`

Inside the `Top` StateMachine, add two peer states: `Locomotion` (a nested `SubStateMachine`) and `Hit` (a single Animation node referencing `hit_flinch`). Set `Locomotion` as the Start state. Death is deliberately omitted (deferred per spec).

- [ ] **Step 1: Enter the `Top` StateMachine editor**

USER ACTION: In the AnimationTree dock, click the **Open Editor** button in the `Top` node header. (4.6.2 UI — double-click no longer enters sub-editors.) The view switches to the StateMachine editor with a green `Start` node visible.

Expected: A grid showing the `Start` node.

- [ ] **Step 2: Add the `Locomotion` sub-StateMachine**

USER ACTION:
1. Right-click in the empty grid → Add → StateMachine (creates a nested SubStateMachine).
2. Click into the new node's inline name field; type `Locomotion`.

Expected: A `Locomotion` node visible in the grid.

- [ ] **Step 3: Add the `Hit` state**

USER ACTION:
1. Right-click in the grid → Add Animation → `hit_flinch`.
2. Click the new node's inline name field; rename from `hit_flinch` to `Hit`.

Expected: A `Hit` node showing `hit_flinch` as its clip.

- [ ] **Step 4: Make `Locomotion` the Start state**

USER ACTION: Using the default Connect Nodes tool, drag from the green `Start` node to `Locomotion`. (4.6.2 UI — no "Set as Start" menu; connect Start→target instead.)

Expected: A connection line `Start → Locomotion`. Serializes as `transitions = ["Start", "Locomotion", SubResource(...)]` with `advance_mode = 2` and no condition, functionally equivalent to "Locomotion is the Start state."

- [ ] **Step 5: Save and verify `.tscn`**

USER ACTION: `Cmd+S`.

AGENT ACTION: Read `scenes/player.tscn`. The `Top` StateMachine sub_resource should now contain:
- `states/Locomotion/node` referencing an `AnimationNodeStateMachine` sub_resource (the nested one).
- `states/Hit/node` referencing an `AnimationNodeAnimation` with `animation = &"hit_flinch"`.
- `graph_offset` and `state_machine_type` properties on the Top SM.
- A `transitions` array — likely empty at this point (Task 5 adds Locomotion↔Hit).
- A `start_node = &"Locomotion"` line (or similar serialization of the Start designation).

- [ ] **Step 6: Commit**

```bash
git add scenes/player.tscn
git commit -m "feat(player.tscn): add top-level StateMachine peer states

Inside the Top StateMachine: Locomotion (nested SubStateMachine,
populated by Task 6) and Hit (Animation node → hit_flinch, stub for
future damage system). Locomotion is the Start state. Death is
intentionally omitted — spec marks it as future, no clip exists."
```

---

### Task 5: Top-level transitions — `Locomotion ↔ Hit`

**Files:**
- Modify: `scenes/player.tscn`

Two transitions per spec:
- `Locomotion → Hit`: advance condition `is_hit`, switch mode `Immediate`, xfade `0.05s`, priority `High` (2).
- `Hit → Locomotion/Idle`: switch mode `At End` (auto-advance), xfade `0.15s`.

Targeting `Locomotion/Idle` (a sub-state) is supported via the `/` separator.

- [ ] **Step 1: Create transition `Locomotion → Hit`**

USER ACTION (still in the Top StateMachine editor):
1. Use the "Connect Nodes" tool (default cursor). Drag from `Locomotion` to `Hit`.
2. The transition appears as an arrow. Click the arrow to select it.
3. In the Inspector, set:
   - `Switch Mode`: `Immediate`
   - `Xfade Time`: `0.05`
   - `Priority`: `2` (High)
   - `Advance Mode`: `Enabled`
   - `Advance Condition`: `is_hit`

Expected: Arrow now labeled with the condition text (Godot's dock shows transition properties).

- [ ] **Step 2: Create transition `Hit → Locomotion/Idle`**

USER ACTION:
1. Drag from `Hit` to `Locomotion`. (Godot may auto-target sub-state via `/` — if a sub-state picker opens, choose `Idle`. If not, you'll set the path via Inspector below.)
2. Click the new arrow.
3. In the Inspector, set:
   - `Switch Mode`: `At End`
   - `Xfade Time`: `0.15`
   - `Priority`: `1` (default, no change needed)
   - `Advance Mode`: `Auto`
4. If the target shows as `Locomotion` (not `Locomotion/Idle`), edit it: the transition's target path lives in the `.tscn` as `Hit -> Locomotion/Idle` once Task 6 creates `Idle`. If Godot won't accept `Locomotion/Idle` as a target at this point (because `Idle` doesn't exist yet), leave it as `Locomotion` for now — we'll edit to `Locomotion/Idle` after Task 6 via a hand-edit (`.tscn` property tweak, OK per project gotchas).

Expected: A new arrow `Hit → Locomotion` (or `Locomotion/Idle` if it accepted the sub-path).

- [ ] **Step 3: Save and verify `.tscn`**

USER ACTION: `Cmd+S`.

AGENT ACTION: Read `scenes/player.tscn`. The Top StateMachine's `transitions` array should contain two entries:
- `"Locomotion"`, `"Hit"`, SubResource(...) with `switch_mode = 0`, `advance_mode = 2`, `advance_condition = &"is_hit"`, `xfade_time = 0.05`, `priority = 2`.
- `"Hit"`, `"Locomotion"` (or `"Locomotion/Idle"`), SubResource(...) with `switch_mode = 2`, `advance_mode = 1` (Auto), `xfade_time = 0.15`.

Switch_mode values: `0 = Immediate`, `1 = Sync`, `2 = At End`. Advance_mode values: `0 = Disabled`, `1 = Auto`, `2 = Enabled` (condition-checked).

If the `Hit → Locomotion` target still reads `"Locomotion"`, leave it for now — Task 6's verification step revisits this once `Idle` exists.

- [ ] **Step 4: Commit**

```bash
git add scenes/player.tscn
git commit -m "feat(player.tscn): wire top-level Locomotion↔Hit transitions

Locomotion→Hit: Immediate, 0.05s xfade, priority 2 (High), advance on
is_hit condition. Hit→Locomotion: At End, 0.15s xfade, auto-advance.
Target may currently read 'Locomotion' (sub-path Locomotion/Idle is
patched in Task 6 once Idle exists)."
```

---

### Task 6: Locomotion sub-SM — add `Idle`, `Move`, `Drift`, `Pivot` peer states

**Files:**
- Modify: `scenes/player.tscn`

Inside the `Locomotion` sub-StateMachine, add four peer states: `Idle` (Animation: `idle`), `Move` (empty BlendSpace2D — populated in Task 7), `Drift` (empty BlendSpace1D — populated in Task 8), `Pivot` (Animation: `pivot_skid`). Set `Idle` as the sub-SM Start.

Also, if Task 5's `Hit → Locomotion` transition didn't accept the `/Idle` sub-path, patch it now via a `.tscn` hand-edit.

- [ ] **Step 1: Enter the `Locomotion` sub-StateMachine editor**

USER ACTION: In the AnimationTree dock, navigate back to the Top StateMachine (breadcrumb). Click the **Open Editor** button in the `Locomotion` node header. (4.6.2 UI: double-click no longer enters sub-editors — see `docs/godot-gotchas.md`.)

Expected: New empty StateMachine grid for the sub-SM with a green `Start` node.

- [ ] **Step 2: Add `Idle` state**

USER ACTION: Right-click → Add Animation → `idle`. Click the new node's inline name field and rename from `idle` to `Idle` (capital I — matches the spec/topology).

- [ ] **Step 3: Add `Move` state (BlendSpace2D)**

USER ACTION: Right-click → Add → BlendSpace2D. Edit inline name field → `Move`. (Anchors added in Task 7.)

- [ ] **Step 4: Add `Drift` state (BlendSpace1D)**

USER ACTION: Right-click → Add → BlendSpace1D. Inline name field → `Drift`. (Anchors added in Task 8.)

- [ ] **Step 5: Add `Pivot` state**

USER ACTION: Right-click → Add Animation → `pivot_skid`. Inline name field → `Pivot`.

- [ ] **Step 6: Set `Idle` as Start**

USER ACTION: Using the default Connect Nodes tool, drag from the green `Start` node to `Idle`. (4.6.2 has no "Set as Start" menu — connect Start→target instead.) Godot will serialize this as `transitions = ["Start", "Idle", SubResource(...)]` with `advance_mode = 2`, functionally equivalent to "Idle is the Start state."

Expected: Connection line from `Start` → `Idle`.

- [ ] **Step 7: Save and verify `.tscn`**

USER ACTION: `Cmd+S`.

AGENT ACTION: Read `scenes/player.tscn`. The `Locomotion` sub-StateMachine sub_resource should now contain `states/Idle`, `states/Move`, `states/Drift`, `states/Pivot`, each referencing the appropriate sub_resource type. `start_node = &"Idle"`.

- [ ] **Step 8: Patch `Hit → Locomotion/Idle` target if needed**

AGENT ACTION: If Task 5's transition still has `Hit -> Locomotion` (not `Locomotion/Idle`), hand-edit `scenes/player.tscn`: find the `transitions` array on the Top StateMachine and change the target string `"Locomotion"` to `"Locomotion/Idle"` on the entry whose `from` is `"Hit"`.

Verify: re-read the file. Open the editor and confirm the Top StateMachine arrow `Hit → Locomotion` now reads `Hit → Locomotion/Idle` (the dock may need a scene reload — close and re-open `player.tscn` in the editor).

If the editor refuses the path or marks it red, that means the sub-state targeting via `/` syntax isn't supported in this Godot version — fall back to plain `Locomotion` target and document the limitation; sub-SM will fall back to its own Start state (`Idle`) which is the desired outcome anyway. Note this in the commit message.

- [ ] **Step 9: Commit**

```bash
git add scenes/player.tscn
git commit -m "feat(player.tscn): populate Locomotion sub-SM with peer states

Adds Idle (Animation: idle), Move (empty BlendSpace2D), Drift (empty
BlendSpace1D), Pivot (Animation: pivot_skid). Idle is the Start state.
Move/Drift anchors are configured in subsequent tasks. Also patches
Hit→Locomotion/Idle sub-state target if not accepted by the editor in
Task 5."
```

---

### Task 7: Configure `Move` BlendSpace2D anchors

**Files:**
- Modify: `scenes/player.tscn`

Add the 7 anchors at exact positions per spec:

| Position | Clip |
|---|---|
| (0, 0) | `idle` |
| (0, 0.5) | `walk_fwd` |
| (-1, 0.5) | `walk_lean_L` |
| (+1, 0.5) | `walk_lean_R` |
| (0, 1) | `run_fwd` |
| (-1, 1) | `run_lean_L` |
| (+1, 1) | `run_lean_R` |

Axes: X = turn rate `[-1, +1]`, Y = normalized speed `[0, 1]`.

- [ ] **Step 1: Enter the `Move` BlendSpace2D editor**

USER ACTION: From the Locomotion sub-SM view, click the **Open Editor** button in the `Move` node header.

Expected: BlendSpace2D editor opens — a 2D grid with axes. Default range may be `-1 to +1` on both axes.

- [ ] **Step 2: Set axis ranges**

USER ACTION: In the Inspector (or the dock's settings panel), confirm/set:
- `Min Space`: `(-1, 0)`
- `Max Space`: `(1, 1)`
- `Snap`: `(0.1, 0.1)` (optional, helps placement precision)

(Godot defaults usually `(-1, -1)` to `(1, 1)`. Y axis lower bound of `0` matters because we have no negative-speed anchors.)

- [ ] **Step 3: Add the 7 anchors**

For each row in the table above, USER ACTION:
1. Right-click on the grid at the approximate position → Add BlendPoint → select the clip from the list.
2. After placement, fine-tune the position via the Inspector when the anchor is selected (a `position` Vector2 property).

Recommended order (anchor at intended position, exact coordinates set via Inspector):
1. (0, 0): `idle`
2. (0, 0.5): `walk_fwd`
3. (-1, 0.5): `walk_lean_L`
4. (1, 0.5): `walk_lean_R`
5. (0, 1): `run_fwd`
6. (-1, 1): `run_lean_L`
7. (1, 1): `run_lean_R`

Expected: 7 dots visible in the grid at the listed positions.

- [ ] **Step 4: Set blend mode**

USER ACTION: With nothing selected (click empty grid), the BlendSpace2D's own properties show in the Inspector. Confirm/set:
- `Blend Mode`: `Interpolated` (default; alternatives are `Discrete` / `Carry` — we want smooth blending).
- `Sync`: `false` (unchecked) — feet shouldn't sync across walk/run since cycle lengths differ.

- [ ] **Step 5: Save and verify `.tscn`**

USER ACTION: `Cmd+S`.

AGENT ACTION: Read `scenes/player.tscn`. The `Move` BlendSpace2D sub_resource should contain:
- `blend_points/0/node`, `/1/node`, ... `/6/node` each referencing an `AnimationNodeAnimation` sub_resource with the correct clip.
- `blend_points/0/position`, `/1/position`, ... matching the table.
- `min_space = Vector2(-1, 0)`, `max_space = Vector2(1, 1)`, `blend_mode = 0` (Interpolated).

Spot-check the 7 (position, clip) pairings against the table; any mismatch needs re-edit.

- [ ] **Step 6: Commit**

```bash
git add scenes/player.tscn
git commit -m "feat(player.tscn): configure Move BlendSpace2D with 7 anchors

X axis: turn rate [-1, +1]; Y axis: normalized speed [0, 1]. Anchors:
(0,0)=idle, (0,0.5)=walk_fwd, (-1,0.5)=walk_lean_L, (1,0.5)=walk_lean_R,
(0,1)=run_fwd, (-1,1)=run_lean_L, (1,1)=run_lean_R. Interpolated
blend mode; Sync off (gait cycles differ across speeds)."
```

---

### Task 8: Configure `Drift` BlendSpace1D anchors

**Files:**
- Modify: `scenes/player.tscn`

Add the 3 anchors per spec:

| Position | Clip |
|---|---|
| 0 | `idle` (shared with Move) |
| 0.5 | `drift_walk` |
| 1 | `drift_run` |

Axis: normalized speed `[0, 1]`.

- [ ] **Step 1: Enter the `Drift` BlendSpace1D editor**

USER ACTION: Navigate back to Locomotion sub-SM (breadcrumb). Click the **Open Editor** button in the `Drift` node header.

Expected: BlendSpace1D editor — a horizontal axis.

- [ ] **Step 2: Set axis range**

USER ACTION: In the Inspector, set:
- `Min Space`: `0`
- `Max Space`: `1`
- `Snap`: `0.1` (optional)

- [ ] **Step 3: Add the 3 anchors**

USER ACTION, for each row:
1. Right-click on the axis at the position → Add BlendPoint → select the clip.
2. Fine-tune position in the Inspector.

Order:
1. `0`: `idle`
2. `0.5`: `drift_walk`
3. `1`: `drift_run`

- [ ] **Step 4: Save and verify `.tscn`**

USER ACTION: `Cmd+S`.

AGENT ACTION: Read `scenes/player.tscn`. The `Drift` BlendSpace1D sub_resource should contain `blend_points/0..2/node` with the correct clips and positions, `min_space = 0`, `max_space = 1`.

- [ ] **Step 5: Commit**

```bash
git add scenes/player.tscn
git commit -m "feat(player.tscn): configure Drift BlendSpace1D with 3 anchors

Axis: normalized speed [0, 1]. Anchors: 0=idle (shared with Move's
center), 0.5=drift_walk, 1=drift_run. Idle anchor at 0 prevents hard
cut entering the Drift→Idle transition."
```

---

### Task 9: Locomotion sub-SM transitions (all 6)

**Files:**
- Modify: `scenes/player.tscn`

Per the spec table:

| From | To | Trigger | Switch mode | XFade | Priority |
|---|---|---|---|---|---|
| Idle | Move | `is_steering` true | Immediate | 0.10s | 1 (default) |
| Move | Drift | `is_steering` false | Immediate | 0.15s | 0 (Low) |
| Drift | Move | `is_steering` true | Immediate | 0.10s | 1 |
| Drift | Idle | `is_slow` true | Immediate | 0.20s | 1 |
| Move | Pivot | `is_pivoting` (one-frame pulse) | Sync | 0.05s | 2 (High) |
| Pivot | Move | (auto-advance) | At End | 0.10s | 1 |

Notes on advance conditions:
- `is_steering` is set sustained (true while steering, false otherwise) — used both positively (Idle→Move, Drift→Move) and negatively (Move→Drift).
- For the *negative* check (`is_steering` false), Godot's StateMachine transitions in 4.6 typically use an "Advance Condition" expression. Two equivalent ways:
  1. Use the dedicated `Advance Condition` field with name `is_steering` (which checks for `true`) — won't work for the negative case.
  2. Use the `Advance Expression` field (a GDScript expression evaluated each frame) — e.g., `not parameters.conditions.is_steering`.
- The spec describes condition names as boolean parameters. The cleanest pattern is: positive checks use `Advance Condition = is_steering` (or `is_slow`, `is_pivoting`); the single negative check (Move→Drift on `is_steering false`) uses the `Advance Expression` field.

Switch mode values (Inspector dropdown): `Immediate`, `Sync`, `At End`.

- [ ] **Step 1: Navigate to Locomotion sub-SM**

USER ACTION: Breadcrumb back to `Locomotion` (the sub-StateMachine editor with Idle/Move/Drift/Pivot).

- [ ] **Step 2: Create `Idle → Move`**

USER ACTION:
1. Drag from `Idle` to `Move`. Click the new arrow.
2. Inspector:
   - `Switch Mode`: `Immediate`
   - `Xfade Time`: `0.10`
   - `Priority`: `1`
   - `Advance Mode`: `Enabled`
   - `Advance Condition`: `is_steering`

- [ ] **Step 3: Create `Move → Drift`**

USER ACTION:
1. Drag from `Move` to `Drift`. Click the new arrow.
2. Inspector:
   - `Switch Mode`: `Immediate`
   - `Xfade Time`: `0.15`
   - `Priority`: `0` (Low — lower number = lower priority in Godot 4)
   - `Advance Mode`: `Enabled`
   - `Advance Condition`: (leave empty)
   - `Advance Expression`: `not is_steering`

Note: `Advance Expression` is evaluated by Godot's GDScript Expression engine; the condition variables registered under `parameters/conditions/*` are accessible directly by their short name (`is_steering`, etc.).

- [ ] **Step 4: Create `Drift → Move`**

USER ACTION:
1. Drag from `Drift` to `Move`.
2. Inspector:
   - `Switch Mode`: `Immediate`
   - `Xfade Time`: `0.10`
   - `Priority`: `1`
   - `Advance Mode`: `Enabled`
   - `Advance Condition`: `is_steering`

- [ ] **Step 5: Create `Drift → Idle`**

USER ACTION:
1. Drag from `Drift` to `Idle`.
2. Inspector:
   - `Switch Mode`: `Immediate`
   - `Xfade Time`: `0.20`
   - `Priority`: `1`
   - `Advance Mode`: `Enabled`
   - `Advance Condition`: `is_slow`

- [ ] **Step 6: Create `Move → Pivot`**

USER ACTION:
1. Drag from `Move` to `Pivot`.
2. Inspector:
   - `Switch Mode`: `Sync`  ← important: phase-aligns the skid clip with the gait cycle
   - `Xfade Time`: `0.05`
   - `Priority`: `2`
   - `Advance Mode`: `Enabled`
   - `Advance Condition`: `is_pivoting`

- [ ] **Step 7: Create `Pivot → Move`**

USER ACTION:
1. Drag from `Pivot` to `Move`.
2. Inspector:
   - `Switch Mode`: `At End`
   - `Xfade Time`: `0.10`
   - `Priority`: `1`
   - `Advance Mode`: `Auto`
   - (No condition / expression — At End auto-advances.)

- [ ] **Step 8: Save and verify `.tscn`**

USER ACTION: `Cmd+S`.

AGENT ACTION: Read `scenes/player.tscn`. The `Locomotion` sub-StateMachine's `transitions` array should contain 6 entries with from/to/SubResource triples matching the table. Verify each transition sub_resource's `switch_mode` (0/1/2), `xfade_time`, `priority`, and `advance_mode` (1/2) plus `advance_condition` or `advance_expression`.

Reference encoding:
- `switch_mode`: 0=Immediate, 1=Sync, 2=At End
- `advance_mode`: 0=Disabled, 1=Auto, 2=Enabled

If `advance_expression` field is absent from the Move→Drift transition's sub_resource, the editor may have stored a different syntax — search the file for `not is_steering` and confirm.

**Also: record the actual condition parameter paths for Step 6.** Each StateMachine in Godot 4 owns its own `conditions` namespace, prefixed by the path to that StateMachine. With our `BlendTree → Top → Locomotion` structure, the condition paths likely serialize as:
- `parameters/Top/conditions/is_hit` (referenced by the top-level Locomotion→Hit transition)
- `parameters/Top/Locomotion/conditions/is_steering` / `is_slow` / `is_pivoting` (referenced by sub-SM transitions)

The spec's "Interface contract" uses the simpler `parameters/conditions/*` form, which assumes a single root-level StateMachine. Our nested structure changes this. AGENT ACTION: after this task's save, grep the saved `.tscn` for `conditions/` and record the exact paths Godot generated. Pass them forward in the Step 6 handoff so `player_anim.gd` writes to the right paths.

If Godot turns out to unify conditions at `parameters/conditions/*` regardless of nesting (some versions did, some didn't), great — the spec stands as-is. Either way, the empirically observed paths are the source of truth for Step 6.

- [ ] **Step 9: Commit**

```bash
git add scenes/player.tscn
git commit -m "feat(player.tscn): wire Locomotion sub-SM transitions (6)

Per spec: Idle↔Move (is_steering), Move→Drift (!is_steering, Low),
Drift→Idle (is_slow), Move→Pivot (is_pivoting, Sync, High), Pivot→Move
(auto-advance, At End). Sync mode on Move→Pivot phase-aligns the skid
clip with the gait cycle so foot-plant reads as a real skid."
```

---

### Task 10: Final defaults verification, spec text fix, F5 sanity

**Files:**
- Modify: `scenes/player.tscn` (conditions defaults only, if needed)
- Modify: `docs/superpowers/specs/2026-05-24-animation-state-machine-design.md` (clip count fix)

The AnimationTree now has all its conditions referenced by transitions: `is_steering`, `is_slow`, `is_pivoting`, `is_hit`. Godot 4 auto-creates `parameters/conditions/<name>` entries when transitions reference them, but their default is `false` — which is what we want. Verify they exist with `false` defaults.

Also: fix the spec's "13 clips" miscount to "12 clips (idle is shared)".

- [ ] **Step 1: Verify `parameters/conditions/*` defaults**

AGENT ACTION: Read `scenes/player.tscn`. Look for `parameters/conditions/is_steering`, `parameters/conditions/is_slow`, `parameters/conditions/is_pivoting`, `parameters/conditions/is_hit` lines on the `AnimationTree` node block.

Two acceptable outcomes:
1. The lines are present with values `false` — done, conditions are explicit.
2. The lines are absent — Godot will auto-create them at runtime with `false` defaults; also acceptable per Godot's parameter inference.

If any line shows a value other than `false` (i.e., `true`), hand-edit to set it to `false`.

If lines are absent and the user wants them explicit for clarity, USER ACTION: Select the `AnimationTree` node in the Inspector, scroll to the bottom "Parameters" section, and the 4 conditions should be listed as checkboxes — all unchecked. Toggling them on and back off forces the explicit `false` entry into the `.tscn`.

- [ ] **Step 2: Verify `active = false`, `script` empty**

AGENT ACTION: Read `scenes/player.tscn`. On the AnimationTree node block, confirm:
- No `active = true` line (absence ⇒ default `false`).
- No `script = ExtResource(...)` line on the AnimationTree node specifically (the Player node still has its `script = ExtResource("1_tuyoq")` — that's fine, separate node).

- [ ] **Step 3: F5 sanity — scene loads, no parser errors**

USER ACTION: F5 the project. Expected:
- Scene loads.
- No parser/resource errors in the Output or Errors panel.
- Movement still works (controller is unaffected).
- The character does NOT animate (AnimationTree.active = false; Step 6 turns it on).
- ESC to stop.

If errors fire about missing animation references, double-check that all 12 clip names in the BlendTree match exactly (case-sensitive, underscore-sensitive) the names in the AnimationPlayer's library.

- [ ] **Step 4: Fix spec "13 clips" miscount**

AGENT ACTION: Edit `docs/superpowers/specs/2026-05-24-animation-state-machine-design.md`. Find and replace:

- Line ~53: `Total: **13 clips**, all hand-authored in Blender.` → `Total: **12 unique clips**, all hand-authored in Blender. (\`idle\` is shared between Move's \`(0, 0)\` anchor and Drift's \`0\` anchor — counted once.)`
- Line ~71 (the Drift section heading "### Drift BlendSpace1D anchors — `Drift` state (3 clips)"): change `(3 clips)` to `(2 new + 1 shared)`.

These are documentation cleanups; the topology and behavior described elsewhere in the spec are unchanged.

- [ ] **Step 5: Commit (final)**

Two commits — one for the scene defaults verification (if any explicit changes), one for the spec fix:

```bash
# If Step 1 produced any explicit hand-edit to player.tscn:
git add scenes/player.tscn
git commit -m "chore(player.tscn): explicit false defaults on AnimationTree conditions

Materializes parameters/conditions/{is_steering,is_slow,is_pivoting,is_hit}
as explicit false on the AnimationTree node. Godot infers these from
transition references with false defaults — making them explicit
prevents the .tscn null-override gotcha if these are ever toggled in
the Inspector and reset."

# Always:
git add docs/superpowers/specs/2026-05-24-animation-state-machine-design.md
git commit -m "docs(spec): fix clip count — 12 unique, not 13

The animation state machine spec said 'Total: 13 clips' by adding
7 (Move) + 3 (Drift) + 3 (one-shots), but idle is listed in both Move's
(0, 0) anchor and Drift's 0 anchor — same clip, two roles. Actual unique
count is 12. The .glb produced by Steps 2-4 has exactly 12 clips,
consistent with this corrected count."
```

---

## Success criteria (verify before claiming Step 5 complete)

Use `superpowers:verification-before-completion` before the final report. Evidence required:

- [ ] `scenes/player.tscn` contains:
  - [ ] `AnimationTree` node sibling of `Model` + `Collision`.
  - [ ] `tree_root` → BlendTree with `Top` (StateMachine input A), `DashShot` (OneShot input B with Add mix, 0.05 fadein, 0.20 fadeout, no autorestart), and the `dash_burst` Animation node.
  - [ ] Inside `Top`: `Locomotion` (sub-SM, Start), `Hit` (Animation: `hit_flinch`). No `Death`.
  - [ ] Inside `Locomotion`: `Idle` (Start, Animation: `idle`), `Move` (BlendSpace2D with 7 anchors), `Drift` (BlendSpace1D with 3 anchors), `Pivot` (Animation: `pivot_skid`).
  - [ ] Top-level transitions match the spec table (Locomotion→Hit + Hit→Locomotion/Idle).
  - [ ] Locomotion transitions match the spec table (6 entries).
  - [ ] `anim_player` → `Model/AnimationPlayer`.
  - [ ] `parameters/conditions/*` all `false` (or absent ⇒ implicit `false`).
  - [ ] `active` not set true (default `false`).
  - [ ] `script` not attached.
- [ ] F5 loads the scene without parser/import errors.
- [ ] Spec line ~53 reads "12 unique clips" not "13".
- [ ] All 10 task commits land on `main` (verify with `git log --oneline -15`).

When all checked, Step 5 is complete. Step 6 (`scripts/player_anim.gd`) becomes unblocked.
