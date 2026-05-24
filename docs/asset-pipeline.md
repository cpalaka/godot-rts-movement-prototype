# Asset Pipeline Conventions

Workflow shape for the Blender → Godot asset pipeline. Scope: where source files live, what crosses, how to name things, and which repo owns what. Tool-specific gotchas live in `blender-mcp-guide.md` and `godot-mcp-guide.md` — this doc only covers conventions.

## Directory layout

**Recommended default for real projects:** Blender working tree lives *outside* the Godot project, in a sibling location. Only exported assets (`.glb` / `.gltf`) cross the boundary.

```
~/gamedev/
  blender/<game-name>/         # .blend files, references, intermediates, renders
    <game-name>.blend
    renders/                   # viewport renders, inspection artifacts
    refs/                      # reference images, concept art
    export.py                  # export script, writes ../../godot/<game-name>/models/*.glb
  godot/<game-name>/           # the game itself — Godot project
    models/                    # *.glb only; populated by Blender export script
    scenes/
    scripts/
    materials/
    ...
```

The Blender export script targets across with a relative path:

```python
# in ~/gamedev/blender/<game-name>/export.py
import bpy
import os
HERE = os.path.dirname(__file__)
GODOT_MODELS = os.path.abspath(os.path.join(HERE, "../../godot/<game-name>/models"))
bpy.ops.export_scene.gltf(filepath=os.path.join(GODOT_MODELS, "foo.glb"), ...)
```

Each tree is its own git repo. If you want them coupled, use a wrapper repo with submodules — but for a solo game project, two independent repos is simpler.

## Why parallel beats nested

| Concern | Nested (.gdignore'd) | Parallel (recommended) |
|---|---|---|
| `.gdignore` discipline | Required in every Blender subdir; easy to forget | Not needed |
| Godot's native `.blend` importer | Always at risk of auto-importing | Never triggers |
| Repo bloat | `.blend1` backups, autosaves, renders all in game repo | Stays separate |
| Source vs engine asset distinction | Implicit | Explicit, enforced by filesystem |
| Sharing assets across projects | Hard — coupled to one game | Easy — one Blender dir, many Godot consumers |

## When nested *is* defensible

- **Single-repo solo workflow** where you genuinely never share. Two dirs to keep in sync is overhead.
- **Sandboxes / probes** that intentionally exercise the `.gdignore` discipline. Don't carry the nested layout into real projects.

If you go nested anyway, you owe `.gdignore` in every Blender working dir and a memory of which subtrees Godot's importer will eat.

## Naming discipline

Naming defaults from Blender leak into Godot in surprising ways. Fix them at export time, not after the fact.

| Layer | Default (bad) | Fix |
|---|---|---|
| Blender object name | `Cube`, `Cube.001` | Rename to semantic (`Pillar`, `Hero`, `Sword`) — this is what becomes the `MeshInstance3D` *node name* in Godot. |
| Blender mesh-data name | Inherited / auto-numeric | Does NOT survive as a stable resource ID — Godot generates a hash-suffixed ID like `ArrayMesh_nyvfv`. The Blender mesh-data name *does* appear as the resource's *display name* (formatted as `<glb_basename>_<mesh_data_name>`), but you can't reference the resource by that name in code. If you need a stable handle, save it as a standalone `.tres` after import. |
| Material name | `Material.001` | Rename — survives as the *material name* on the imported `StandardMaterial3D` (e.g. `HeroBody`), but the unique sub-resource ID is still hash-suffixed (`StandardMaterial3D_<hash>`). Same name-vs-ID distinction as mesh-data. |
| Action name | `Action`, `Action.001` | Name per animation (`Idle`, `Walk`, `Attack`) — drives the `AnimationPlayer` track names |
| Armature name | `Armature` | Rename to model name + `_Skel` or similar |
| Bone names | Defaults from rigify / manual | Use a stable convention; Godot is permissive but `AnimationTree` parameter paths break on rename |
| `.glb` filename | `<whatever>` | Match the in-game concept name, not the working-file name |

For rigged models: action and bone names matter more than mesh names because they end up in `AnimationTree` parameter paths (e.g. `parameters/StateMachine/Walk/blend_position`). Rename pain compounds.

## Export-time discipline (rigged models)

When exporting an armature + actions to glTF:

- `export_apply=True` bakes modifiers — usually what you want for game assets.
- `export_animations=True` is default-on; verify it survives if you tweak settings.
- Actions are exported per their NLA / action slot — orphaned actions (not assigned, not in NLA) may be skipped depending on Blender version. Push to NLA strips to guarantee export.
- `export_yup=True` (default) — Godot is Y-up, Blender is Z-up. The axis conversion is handled by glTF; don't pre-rotate.
- Validate the exported `.glb` by previewing in Blender (re-import) or with `gltf-validator` before assuming Godot's import will succeed.

## Animation: author where?

Short answer: **author clips in Blender, orchestrate them in Godot.**

| Concern | Blender | Godot |
|---|---|---|
| Authoring keyframes / poses | ✅ DCC purpose-built (graph editor, dope sheet, NLA, onion skinning) | Weaker tooling |
| IK rigging, constraints, drivers | ✅ Bake out at export | Possible but more manual |
| Combining clips by game state | Can't — no input concept | ✅ AnimationTree state machines, blend spaces, sync groups |
| Procedural overlays (look-at, foot IK, ragdoll blends) | Authored as rigid clips | ✅ Runtime-aware |
| Iteration speed | Re-export every change | ✅ Tweak live |
| Source-of-truth simplicity | ✅ One `.blend` owns rig + clips | Risk of overwrite on re-import (unless "Save to file") |

Dividing line is **runtime context**. Blender doesn't know the player pressed W or what's under the character's feet — it produces fixed clips. Godot does know, so anything driven by gameplay belongs in Godot.

**Practical split:**
- Idle, Walk, Run, Attack, Death, etc. → Blender
- State machine deciding which plays → Godot (`AnimationTree`)
- Procedural overlays (look-at, foot IK to terrain, ragdoll blends) → Godot

**Exception:** for primitives with no rig (a spinning coin, a moving platform, UI tween), animating node transforms directly in Godot's `AnimationPlayer` is fine — no DCC value-add when there's no skeleton.

## Bone-attached props: BoneAttachment3D is automatic

Validated in a sandbox probe: a prop cube parented to a bone via Blender's bone-parent mechanism (`object.parent_type = 'BONE'` + `object.parent_bone = '<BoneName>'`), re-exported, and the imported Godot scene tree inspected.

**Blender side:**
- Object's `parent` = the armature, `parent_type = 'BONE'`, `parent_bone = '<bone_name>'`.
- The object is NOT skinned (no vertex weights to the bone) — it's a rigid child of the bone.
- In glTF, this becomes a regular node hierarchy: the prop node is a child of the bone node, alongside other bones.

**Godot side (no manual wiring):**
- The bone-parented object becomes a `MeshInstance3D` under an auto-generated `BoneAttachment3D`.
- The `BoneAttachment3D` is named after the bone (e.g. `RightHand`), positioned as a child of `Skeleton3D`.
- Its `bone_name` and `bone_idx` properties are pre-populated; `override_pose = false` (read-only — it follows the bone, doesn't drive it).
- The structure looks like:
  ```
  Hero (inherited .glb root)
   └─ Hero_Skel
       └─ Skeleton3D
           ├─ RightHand               (BoneAttachment3D, auto-created)
           │   └─ Sword               (MeshInstance3D)
           └─ Hero                    (MeshInstance3D, skinned)
  ```

The prop follows the bone through animation automatically — no script, no manual `BoneAttachment3D` setup, no `bone_name` configuration. Works for arbitrary props (weapons, equipment, attachments).

**Caveat with naming:** the auto-generated `BoneAttachment3D` is named *after the bone*, which can shadow expectations if your scene tree has other nodes with that name. Reading animation track paths like `Skeleton3D:<bone_name>`, Godot disambiguates: `:` is property syntax (bone name), `/` is child-node syntax (BoneAttachment3D). No collision in practice — but rename the BoneAttachment3D to something unambiguous (e.g. `RightHand_Attach`) if you want clarity.

## Live iteration loop: Blender re-export → Godot reimport

Empirically validated in a sandbox probe (a new action added to a rigged mesh's .blend, re-exported, with Godot's response observed):

1. **`editor.run` does NOT trigger an FS scan.** A fresh `.glb` on disk is still served as the old cached `.scn` to the launched game process. Confirmed: a re-exported rigged .glb with a new animation continued to serve the pre-export animation list to the launched game.
2. **Focusing the editor window IS the trigger.** `osascript -e 'tell application "Godot" to activate'` (macOS) wakes the FS watcher within ~1-2s. After that, `editor.run` returns the updated animation list.
3. **Open scenes do NOT need to be closed/reopened.** The `.tscn` referencing the .glb's PackedScene picks up the new structure on next instantiation. AnimationPlayer's animation list, Skeleton3D bones, etc. all reflect the new import.
4. **Existing `.tscn` references survive backward-compatible additions.** AnimationTree configured against a subset of animations continues working unchanged after the .glb gains additional ones. Adding animations is safe; renaming would invalidate the references.

**Iteration loop cost:** Blender re-export (~20ms for small models) + osascript focus (~1s) + Godot reimport (~1s) + `editor.run` (~1s) ≈ 3-4 seconds per cycle. Acceptable for tight iteration.

**Open issue:** the focus trigger is OS-dependent and cumbersome in headless / CI contexts. No first-class MCP affordance for triggering an FS scan today.

## Inherited-scene pattern for rigged characters

Recommended shape for any rigged character that has an `.glb` source plus engine-side logic (AnimationTree, scripts, physics):

```
scenes/characters/<char>.tscn      # inherited from <char>.glb
  └─ <Char root> (Node3D, inherited; can attach script)
      ├─ AnimationPlayer (inherited from .glb)
      ├─ <Skel> (inherited from .glb)
      └─ AnimationTree (NEW; sibling of AnimationPlayer)
          tree_root = <StateMachine sub-resource>
          anim_player = NodePath("../AnimationPlayer")
          active = true
```

Game scenes then `instance` the character `.tscn`, never the raw `.glb`. Validated in a sandbox probe.

**Why inherited beats instanced** (compared to the instanced pattern):

| Concern | `.glb` instanced as child of `.tscn` | `.glb` as inherited root |
|---|---|---|
| AnimationPlayer access from `AnimationTree.anim_player` | `NodePath("../<glb_root>/AnimationPlayer")` — traverses INTO an instanced subtree | `NodePath("../AnimationPlayer")` — sibling, direct |
| NodePath picker dialog | AnimationPlayer hidden behind "Editable Children" toggle (instanced subtree is collapsed) | AnimationPlayer visible directly (it's part of the current scene) |
| Re-importing the .glb (e.g. re-export from Blender) | Preserves config; AnimationTree lives outside the .glb | Preserves config; AnimationTree lives outside the .glb |
| Scene structure mental model | Two siblings (instanced .glb + AnimationTree), AnimationTree paths *into* the .glb | One unified subtree, AnimationTree is just a regular sibling node |
| Multi-instance variation (e.g. different AnimationTree per character class) | Each variant needs its own `.tscn` with its own instanced .glb | Each variant inherits from the same .glb, same shape |

**Tcsn syntax for inherited root:**
```tscn
[ext_resource type="PackedScene" path="res://models/<char>.glb" id="1_glb"]

[node name="<CharRootName>" instance=ExtResource("1_glb")]
script = ExtResource("2_script")   # optional, attaches to inherited root

[node name="AnimationTree" type="AnimationTree" parent="."]
tree_root = SubResource("sm_root")
anim_player = NodePath("../AnimationPlayer")
active = true
```

The `[node name="..." instance=...]` form at the document root creates the inherited scene; the root inherits all children from the parent .glb. Additional `[node ... parent="."]` blocks add new siblings to the inherited root.

**Reimport behavior:** Tested by deleting `.godot/imported/<char>.glb-<hash>.{md5,scn}` and re-focusing the editor. The .glb is reimported; the inherited .tscn's AnimationTree, sub-resources (StateMachine, transitions), and node paths all survive intact because they live in the .tscn, not the .glb.

## How PBR materials survive the .glb

Validated end-to-end in a sandbox probe (sphere + Principled BSDF + 5 PNG textures → glTF → Godot import; plus an ORM-packed variant):

| Authored in Blender | In the .glb | In Godot `StandardMaterial3D` |
|---|---|---|
| Base Color image | `baseColorTexture` | `albedo_texture` |
| Normal Map node + image | `normalTexture` | `normal_texture` (`normal_enabled=true`, `normal_scale=1.0`) |
| Roughness image (separate) | merged → `metallicRoughnessTexture` | `roughness_texture` (channel `G`=1) |
| Metallic image (separate) | merged → `metallicRoughnessTexture` (same as above) | `metallic_texture` (channel `B`=2), pointing at same texture |
| Single ORM-packed PNG (R=AO, G=Roughness, B=Metallic) wired to Roughness+Metallic on Principled BSDF *and* to a `glTF Material Output` node group's `Occlusion` input | one texture shared by `metallicRoughnessTexture` *and* `occlusionTexture` (same index) | `ao_texture` + `metallic_texture` + `roughness_texture` all point to the *same* extracted PNG; channel masks: ao=R(0), roughness=G(1), metallic=B(2); `ao_enabled=true`. **Note:** Godot does NOT populate the consolidated `orm_texture` slot — it uses the three individual slots with channel masks. Equivalent runtime behaviour, different field. |
| Emission Color image | `emissiveTexture` | `emission_texture` (`emission_enabled=true`) |
| Emission Strength scalar | `KHR_materials_emissive_strength.emissiveStrength` | `emission_energy_multiplier` |
| Default opaque + alpha=1 | (no transparency extension) | `transparency=0` |
| Backface culling off (default in Blender) | `doubleSided=true` | `cull_mode=2` ("Disabled") |

**Authoring the AO/Occlusion channel:** Blender's Principled BSDF has no AO socket. The glTF exporter looks for a custom node group **literally named `glTF Material Output`** with an input named `Occlusion`; whatever Image Texture is connected there becomes the glTF `occlusionTexture` (R channel). The node group's internal contents don't render in Blender — it's a pure metadata marker for the exporter. To produce ORM-packed output, wire the same Image Texture to Roughness (G), Metallic (B), and the Occlusion node-group input; Blender's exporter detects the reuse and emits a single shared texture. (Cosmetic export warning `"More than one shader node tex image used for a texture"` fires even with one Image Texture node, because the exporter walks multiple chains — safe to ignore.)

## Multi-material mesh slot mapping

Validated in a sandbox probe (cube with two material slots: 1 polygon assigned to slot 0, 5 polygons to slot 1, two distinct materials):

- A Blender mesh with N material slots and per-polygon `material_index` values exports as one glTF mesh with N primitives, one per used material slot. Polygons sharing a `material_index` go into the same primitive.
- Godot imports this as **one `MeshInstance3D`** whose `mesh` has `get_surface_count() == N`. `mesh.surface_get_material(i)` returns the i-th material.
- **Surface index ↔ material mapping is stable and matches Blender's `mesh.materials` slot order.** Slot 0 → surface 0, slot 1 → surface 1, etc.
- Across re-exports, the mapping is preserved as long as Blender's slot order doesn't change. Reordering slots in Blender (or removing one) breaks downstream code referencing fixed surface indices — pin material slot order at the Blender side or look up by material *name* in Godot if you need resilience.

This is why scripts that swap materials at runtime (e.g. damage flash) typically reference `surface_get_material(0)` for a single-material mesh but need explicit indices for multi-material meshes.

**Imported texture paths** are `res://models/<glb_basename>_<image_name>.png` — and these PNGs actually exist on disk in the project tree (extracted from the .glb alongside the source file) when `gltf/embedded_image_handling=1` ("Extract Textures") is set, which is the default. The compiled `.ctex` siblings live in `.godot/imported/`. So your `models/` directory will accumulate `<glb_basename>_*.png` files for each embedded image after import — that's expected. **Materials** are a separate concern controlled by `materials/extract` (default `0` = embedded as sub-resources of the imported scene); set `materials/extract=1` to extract `.tres` material files into the project tree.

The `mcp__godot-mcp__resource get_info` tool only reports a subset of `StandardMaterial3D` properties — for full introspection, attach a GDScript and `print()` the values at runtime.

## How animation survives the .glb

glTF stores animations as pure numeric data. No Blender concepts cross the boundary.

```
Animation "Wave"
├── Channel 0: target=Upper.rotation,    sampler=0
├── Channel 1: target=Upper.translation, sampler=1
├── Channel 2: target=Upper.scale,       sampler=2
├── Channel 3..5: same paths for Root bone
│
├── Sampler 0: input=[0.0, 0.967], output=[quat, quat], interpolation=LINEAR
└── ...
```

- **Channel** = "what to animate" (target node + property: `translation` / `rotation` / `scale` / `weights`).
- **Sampler** = timestamps array + values array + interpolation type (`LINEAR`, `STEP`, `CUBICSPLINE`).
- Rotations are stored as **quaternions** regardless of Blender's rotation mode.
- The .glb's animation namespace is flat — action names become animation names; NLA structure is dropped.

**Captured:** baked transforms per channel, mesh geometry, skin (joints + inverse-bind-matrices), per-vertex `JOINTS_0` + `WEIGHTS_0` attributes.

**Not captured:** Blender NLA structure, bone constraints, drivers, IK rigs (unless baked), modifiers (unless `export_apply=True` at export time). The .glb is the *result*, not the recipe.

This is why .glbs play identically in Godot, three.js, Unity, Unreal, and any glTF viewer — the animation is described in universal math, not DCC-specific concepts.

## What crosses the boundary

| Direction | Crosses | Stays |
|---|---|---|
| Blender → Godot | `.glb` / `.gltf` exports | `.blend`, `.blend1` backups, references, intermediate renders |
| Godot → Blender | Nothing automatic — Godot doesn't write back. | All Godot project state |

If you find yourself wanting to round-trip (export from Godot back to Blender), stop — that's a workflow smell. Keep authoring upstream.

## Git strategy

- **Two independent repos** is simplest for solo work.
- **Single wrapper repo with two submodules** if you want atomic commits across both sides (e.g. "added the pillar mesh + the scene that uses it" as one commit). Adds submodule complexity.
- **One repo, two top-level dirs** (`blender/`, `godot/`) only if you're certain the project stays solo and small.

Don't commit `.blend1` backups (gitignore `*.blend1`, `*.blend@`). Do commit `.blend` files — they're binary but versioned changes are useful.

## Cross-references

- **Blender tool reference + gotchas:** `blender-mcp-guide.md`
- **Godot tool reference + gotchas:** `godot-mcp-guide.md`
- **GDScript idioms:** `godot-gdscript-patterns` skill
- **AnimationTree gotchas:** `godot-animation-tree-mastery` skill
