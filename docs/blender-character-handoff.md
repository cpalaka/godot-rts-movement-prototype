# Player Character — Blender Modeling, Rigging & Animation Handoff

**Purpose:** Standalone context briefing for an external agent (e.g., Claude Desktop) helping the developer model, rig, and animate the player character in Blender. The agent's job is to walk the developer through Blender work and produce a reference document; this file gives the agent everything it needs about the receiving Godot project's constraints.

**Audience:** An agent that does NOT have access to this Godot project's files or repo. Treat this doc as complete on its own.

---

## Game shape (relevant to character design)

- **Engine:** Godot 4.6.
- **Camera:** Top-down, slightly oblique angle — the character is seen mostly from above with a small front bias. Silhouette and head/shoulder shape matter more than face detail.
- **Genre:** ARPG prototype. Solo project, early stage.
- **Character:** Single bipedal humanoid (the player). No NPCs, no enemies in scope yet. Current placeholder in-engine is a gray cone — this character replaces it.
- **Movement model:** Momentum-driven hold-to-direct. Right-mouse-button held → player steers toward the cursor. Release → momentum carries forward, friction decays to rest. A dash mechanic (Space) overrides momentum with a brief impulse burst.
- **Combat:** Not yet implemented. The animation system reserves a slot for a hit-reaction (`hit_flinch`); no attack clips needed.
- **Jump / aerial:** Out of scope — the game is ground-only.
- **Death:** Not yet implemented. Slot reserved at the animation-system level; no death clip needed in this authoring pass.

This is a prototype. The user has signaled a preference for **low-poly stylized over realistic**. Confirm style direction with the user before settling.

---

## The 13 animation clips this rig must support

All 13 are required for the Godot AnimationTree to function. Name them in Blender **exactly as listed below** (Blender Action names export verbatim into Godot's AnimationPlayer; renaming after the fact propagates pain into AnimationTree parameter paths).

### Locomotion BlendSpace2D — `Move` state (7 clips)

These seven clips are positioned on a 2D blend space. **X axis = turn rate `[-1, +1]`** (negative = turning left, positive = turning right). **Y axis = normalized speed `[0, 1]`**. Authoring constraint: the seven clips form a coherent grid — each must look natural when the player is partway between two anchors.

| Blend position | Clip name | Role |
|---|---|---|
| (0, 0) | `idle` | Center anchor — standing pose, subtle breath cycle |
| (0, 0.5) | `walk_fwd` | Forward walk at half speed |
| (-1, 0.5) | `walk_lean_L` | Forward walk with left torso lean (turning while walking) |
| (+1, 0.5) | `walk_lean_R` | Forward walk with right torso lean |
| (0, 1) | `run_fwd` | Forward run at full speed |
| (-1, 1) | `run_lean_L` | Forward run with left lean |
| (+1, 1) | `run_lean_R` | Forward run with right lean |

**No "idle-turn" or strafe clips** — the controller never turns in place; rotation always accompanies movement. Don't author idle-turn-left / idle-turn-right.

### Drift BlendSpace1D — `Drift` state (3 clips)

Plays when the player releases steering and coasts on momentum. **Axis = normalized speed `[0, 1]`**. Upper body distinct from Move — should read as "no longer driving the motion."

| Blend position | Clip name | Role |
|---|---|---|
| 0 | `idle` (shared with Move) | Settle anchor — prevents hard cut when transitioning to Idle |
| 0.5 | `drift_walk` | Coast at walk speed — upper body lean-back, arms trailing |
| 1 | `drift_run` | Coast at run speed — same posture, more body language of "decelerating" |

### One-shots (3 clips)

| Clip name | Role |
|---|---|
| `pivot_skid` | Plays when the player sharply reverses steering at speed (skid through zero, accelerate the new direction). Auto-advances back to Move at clip end. Should phase-sync with the gait cycle — the foot-plant moment should read as a real skid. |
| `dash_burst` | Plays additively on top of locomotion when the player dashes. Upper-body explosion of motion; the legs keep cycling underneath. Short — duration on the order of 320ms / 0.32s to match the impulse decay envelope. |
| `hit_flinch` | Stub for now. Brief flinch / recoil — half a second or so. Will be replaced when the damage system arrives. Author something simple that can ship as a placeholder. |

**Total clip count: 13** (the `idle` clip is counted once but used by both Move and Drift state machines).

---

## Hard constraints — alignment checks BEFORE modeling and rigging

These decisions leak from Blender into Godot in ways that are painful to reverse. Settle them with the user **before opening Blender for serious authoring**.

### 1. Rig choice — Rigify vs. Mixamo vs. custom (UNDECIDED — settle first)

This dominates everything downstream. The choice determines bone naming, which determines what Godot's `Skeleton3D` will expose.

| Option | When it fits | Trade-off |
|---|---|---|
| **Rigify** | Solo author comfortable with Blender's rigify add-on. IK controls during animation. Deform bones (`DEF-spine`, `DEF-shoulder.L`) are what Godot sees. | Native Blender workflow; the deform bone names are stable but specific to Rigify. |
| **Mixamo-compatible** | Author wants to test/preview Mixamo animations or use the Mixamo bone library. Names are `mixamorig:Hips`, `mixamorig:Spine`, etc. | Locks in a naming convention but opens the door to library motion. |
| **Custom skeleton** | Stylized prototype with intentional bone count reduction (e.g., 20 bones not 60). Hand-name every bone. | Most freedom, most discipline required. Each bone name is permanent for the duration of the project. |

**Recommend asking the user to commit to one.** Once chosen, all 13 clip authoring uses the same bone names. Renaming a bone mid-project breaks AnimationTree parameter paths in Godot.

### 2. Bone naming — stability matters more than style

Whatever rig you pick, **the deform bone names that survive the glTF export are what Godot binds to**. AnimationTree parameter paths reference bone names indirectly through the AnimationPlayer track names; rename a bone after authoring clips and every clip's track must be updated.

Rule of thumb: pick names, write them down, never change them.

### 3. Action naming — VERBATIM from the list above

Blender Action names export to glTF `animation.name`, which becomes the AnimationPlayer track name in Godot. The Godot AnimationTree binds to these names through its state machine. If the developer names a Blender action `Walk` instead of `walk_fwd`, the AnimationTree state machine will silently fail to find it.

Use **exactly**: `idle`, `walk_fwd`, `walk_lean_L`, `walk_lean_R`, `run_fwd`, `run_lean_L`, `run_lean_R`, `drift_walk`, `drift_run`, `pivot_skid`, `dash_burst`, `hit_flinch`.

Note casing: lowercase with underscores, `_L` and `_R` for left/right variants (uppercase L/R).

### 4. Forward axis — local +Z forward, not -Z

**Critical and easy to miss.** This project's player controller treats the character's **local +Z** as the forward direction, not Godot's canonical -Z. This is a deliberate override for visual consistency with how the existing placeholder cone is oriented.

Comment from the project's `scripts/player.gd`:

> "The Facing cone in player.tscn is oriented along local +Z, so transform.basis.z is where the player visually points. (Godot's canonical forward is -basis.z; we override for visual consistency.)"

**Practical implication for Blender:** Author the character such that, when the glTF reaches Godot with the standard Y-up convention, the character's face/chest points along **local +Z**. The standard Blender export pipeline is `+Y up` in glTF (Blender's +Z up rotates to glTF's +Y up), with `-Z forward` as the default. The user will need to either:

- Rotate the character 180° before export so its face points along glTF +Z, OR
- Author the character facing +Y in Blender (which becomes +Z in Godot after the Y-up conversion).

This is fiddly. Walk through it with the developer carefully, and have them test in Godot with one clip (the `idle` is fine) before authoring all 13.

### 5. Multi-material slot ordering

If the character has multiple materials (body, hair, clothing, eyes, etc.), the **order of material slots in Blender determines the order Godot sees them** as `surface_0`, `surface_1`, etc.

If the developer expects to swap materials at runtime in Godot (e.g., for different outfits or damage states), the slot order needs to be fixed at the time of authoring — adding a new material slot at index 0 later means every surface index in Godot shifts.

**Recommend:** decide on a slot order with the developer early, write it down, and stick to it. Even if there's only one material at first, leave the convention documented.

### 6. glTF export discipline

The project's asset pipeline uses **`.glb`** files (glTF binary). Key export settings:

- **`export_apply=True`** — bake modifiers at export. Game assets want the modified mesh, not the modifier stack.
- **`export_animations=True`** — default-on, but verify if any settings are tweaked.
- **Action export via NLA** — push each of the 13 actions to NLA strips. Orphan actions (created but not in NLA, not assigned) can be skipped depending on Blender version. NLA-strip-push is the safe default.
- **`export_yup=True`** — default, leave alone. Godot is Y-up, Blender is Z-up; glTF handles the conversion.
- **Validate after export** — re-import the `.glb` in Blender, or use `gltf-validator`, before assuming Godot will load it correctly.

### 7. Blender 5.x slotted actions caveat

If the developer is on Blender 5.x: the new "slotted actions" feature changes how actions are organized and can complicate the glTF export. If using Blender 5.x, surface this to the developer and verify exports work end-to-end with the `idle` clip before authoring the full set.

### 8. Mesh / object naming (lower-priority but worth fixing at authoring time)

| Blender entity | Becomes in Godot | Convention to use |
|---|---|---|
| Object name (the `MeshInstance3D` parent) | Node name in scene tree | `Player` or `Hero` — semantic, not `Cube.001` |
| Mesh data name | Display name on the imported `ArrayMesh` resource | `PlayerBody` or similar — semantic |
| Material name | Display name on the imported `StandardMaterial3D` | `PlayerBody`, `PlayerHair` — semantic |
| Armature name | The `Skeleton3D` parent node name | `Player_Skel` or similar |
| `.glb` filename | The imported scene resource filename | `player.glb` |

None of these break the game if defaulted — but if any of them later need to be referenced by name in Godot, retroactively renaming triggers cache invalidation.

### 9. Directory layout (Blender vs. Godot trees)

The project's recommended layout is **parallel sibling directories**, not nested:

```
~/gamedev/
  blender/<game-name>/          # .blend files, references, intermediates, renders
    player.blend
    refs/                       # reference imagery
    export.py                   # exports to ../../godot/<game-name>/models/
  godot/<game-name>/            # the Godot project itself
    models/                     # *.glb only; populated by Blender export
    scenes/
    scripts/
    ...
```

Each tree is its own git repo (or just one — solo project). Export script lives in the Blender side and writes across into Godot's `models/` directory.

**Don't nest the Blender working tree inside the Godot project** unless the developer explicitly wants the single-repo simplicity and accepts the `.gdignore` discipline burden.

---

## Open decisions the user should settle EARLY

| Decision | Why it matters | Suggested default |
|---|---|---|
| Rig: Rigify, Mixamo, or custom | Bone naming locks in everything downstream | **Ask user first** — this is the highest-leverage decision |
| Polycount budget | Affects modeling effort | <3000 tris is plenty for prototype-stage stylized; <10000 if going semi-realistic |
| Style direction | Affects authoring time and visual cohesion | Low-poly stylized (user's stated lean) |
| Single mesh vs modular | Affects material slot organization and future swap-ability | Single mesh for prototype |
| Texture pipeline: unlit, simple PBR, or full PBR | Affects material setup and lighting needs | Unlit or simple PBR for prototype |
| Skeleton: full humanoid with IK rig, or simplified FK | Affects rigging complexity | Rigify provides IK rig controls for authoring; for a prototype this is fine and worth the setup time |
| Forward-axis convention in Blender | The +Z-forward override is a project quirk that the rig must accommodate | Author facing local +Y in Blender (becomes +Z in Godot after Y-up conversion) — test with `idle` first |

---

## What's already shipped on the Godot side

So that the rigging/animation agent knows the receiving system is already in place:

- The Godot `Player` node (currently a gray cone) is a `CharacterBody3D` with a complete movement controller.
- The controller exposes the public surface the AnimationTree binding will consume:
  - `signal dash_fired` — emitted on successful dash
  - `signal pivot_started` — emitted on sharp steering reversal
  - `is_steering() -> bool` — accessor for whether the player is holding RMB
  - `@export var pivot_reversal_threshold: float = -0.5` — dot product cutoff
  - `@export var pivot_min_speed: float = 2.0` — speed gate for pivot detection
  - `@export var idle_threshold: float = 0.1` — speed below which Drift transitions to Idle
- These are committed to the project (commits `56cb245`, `f3d4794`, `1b657e6`).
- The AnimationTree resource itself, the `player_anim.gd` binding script, and the actual `.tscn` integration are **future work** — they happen after the model + clips exist.

The character authoring work does not need to coordinate with this controller-side code. It only needs to produce a rigged `.glb` with 13 correctly-named actions.

---

## Per-clip authoring detail (existing reference doc)

This project has a detailed per-clip Blender authoring guide at `docs/animation-authoring-guide.html` in the Godot project repo. It covers per-clip length, loop discipline, pose blocking, sync siblings (e.g., `walk_lean_L` and `walk_lean_R` must share frame count for symmetric blending), and other gotchas.

If your walkthrough needs per-clip authoring depth (clip lengths in frames, loop start/end requirements, how to make BlendSpace clips blend cleanly), ask the developer to share that HTML file. It's the existing reference for Step 3 (clip authoring) — don't re-invent it.

---

## Anti-pitfalls — things to surface to the developer early

1. **Don't author the full 13 clips before testing one in Godot.** Author `idle`, export, import in Godot, confirm it shows up correctly (orientation, materials, scale, bone names) before investing time in the other 12. The forward-axis quirk in particular is easy to miss until import.

2. **Don't rename bones once clips are authored.** Even one bone rename forces re-authoring every clip's track.

3. **Don't rename Blender Actions once exported.** The Godot AnimationTree state machine binds to the action names listed above. Renames break those bindings silently.

4. **Don't author clips with mismatched frame counts across sync-siblings.** `walk_lean_L` and `walk_lean_R` (and `run_lean_L` / `run_lean_R`) must share frame count for the BlendSpace2D to interpolate cleanly. Same for `drift_walk` and `drift_run` (they share a BlendSpace1D, smaller risk but worth noting).

5. **Don't skip the NLA push.** Orphan actions can fail to export. Push every action to an NLA strip before running the export script.

6. **Don't ship without a placeholder hit_flinch.** Even though the damage system isn't built, the AnimationTree needs the clip to exist so the state machine has a target. A 0.5s recoil is enough.

7. **Don't pre-rotate the character mesh in object mode** to fix the forward-axis quirk. Do it via the export-time rotation or by authoring facing +Y in Blender. Object-mode rotations leak weird transforms into the export.

---

## Summary handoff in one paragraph

> The developer needs a rigged bipedal humanoid character for a top-down ARPG prototype in Godot 4.6, replacing a gray cone placeholder. The animation system requires 13 specifically-named clips (7 locomotion BlendSpace2D anchors, 3 drift BlendSpace1D anchors, 3 one-shots for pivot/dash/hit). The highest-leverage decision is rig flavor (Rigify vs Mixamo vs custom) — settle this with the developer before authoring. The project uses local +Z as forward (overrides Godot's canonical -Z), so the character must face +Z in the final exported orientation. Detailed per-clip authoring guidance lives in `docs/animation-authoring-guide.html` in the Godot project. The Godot side is already prepared with signals and exports for the future AnimationTree binding — that work happens after this Blender pass completes.
