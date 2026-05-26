# Godot 4.x Gotchas

Project-level catalog of Godot engine, editor, and tooling quirks that bit us during development. Add entries here as new gotchas surface so any developer (human or LLM) cloning this project benefits.

Each entry: **symptom → cause → fix**. Optional: how to detect proactively.

---

## Embedded game tab blocks `window_set_mode` (Godot 4.6)

**Symptom:** Calling `DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)` or `WINDOWED` from a running game produces no visible change — no error, no log entry, just nothing happens.

**Cause:** Godot 4.6's editor embeds the running game inside the editor's "Game" tab by default. The embedded child viewport is not a real OS window, so window-mode operations no-op silently.

**Fix:**
- One-shot: click "Make Floating" on the Game tab during play to detach it into a real OS window.
- Persistent: Editor Settings → Run → Embed Game On Next Play → uncheck.

**Detect proactively:** If a window-mode toggle binding "doesn't work" in the editor but the bound action fires correctly (verify via `print` in the input handler), check whether the game is embedded.

---

## GDScript `:=` inference fails on `clamp`/`min`/`max`/etc. with warnings-as-errors

**Symptom:** GDScript parse error on lines like `var x := clamp(a, 0.0, 1.0)`:

> Parser Error: The variable type is being inferred from a Variant value, so it will be typed as Variant.

**Cause:** Godot 4's global `clamp`, `min`, `max`, `abs`, `sign`, `floor`, `ceil`, `round` are *overloaded* across numeric types — they accept Variant arguments and return Variant. With `gdscript/warnings/untyped_declaration` enabled and `treat_warnings_as_errors` on (defaults in many configs), `:=` inference on a Variant return becomes a hard error.

**Fix:** Use the explicitly-typed variants. They return `float` or `int` directly so `:=` resolves cleanly.

| Variant return | Float variant | Int variant |
|---|---|---|
| `clamp(x, a, b)` | `clampf(x, a, b)` | `clampi(x, a, b)` |
| `min(a, b)` | `minf(a, b)` | `mini(a, b)` |
| `max(a, b)` | `maxf(a, b)` | `maxi(a, b)` |
| `abs(x)` | `absf(x)` | `absi(x)` |
| `sign(x)` | `signf(x)` | `signi(x)` |
| `floor(x)` | `floorf(x)` | `floori(x)` |
| `ceil(x)` | `ceilf(x)` | `ceili(x)` |
| `round(x)` | `roundf(x)` | `roundi(x)` |

**Detect proactively:** When writing new GDScript, default to the typed variants. Grep existing GDScript for `clamp\(|min\(|max\(|abs\(|sign\(` inside `var ... :=` expressions.

---

## `.tscn` null overrides silently zero typed exports

**Symptom:** After a play session involving live Inspector tuning, the affected `.tscn` file contains lines like:

```
[node name="Player" ...]
script = ExtResource("...")
max_speed = null
turn_rate_deg = null
```

Current session works fine because the Inspector still holds live values. But on a fresh checkout / fresh editor session / fresh F5 by a different developer, the player's `max_speed` and `turn_rate_deg` load as `0.0`, freezing it.

**Cause:** When the Inspector "clears" an override on an exported property (right-click → Reset, or manual deletion of the override entry), Godot may write back `property = null` instead of removing the line. The apparent intent is "fall back to script default," but the on-disk representation is a destructive `null` override. On scene load, Godot applies the override and silently coerces `null` to `0.0` for typed numeric exports — overriding the script default.

**Fix:** Hand-edit the `.tscn` to remove the `= null` lines entirely. The script's default then applies on load. (Alternative: set the property to its intended value rather than leaving it null.)

**Detect proactively:** After any live-Inspector-tuning session, grep affected `.tscn` files:

```bash
grep ' = null' scenes/*.tscn
```

Hits are suspicious — investigate whether they're stale clear-overrides.

---

## Forward axis is canonical -Z (flipped from +Z on 2026-05-25)

**Convention:** The player character's forward direction is **local -Z** — Godot's canonical convention. `_resolve_dash_dir` falls back to `-transform.basis.z`, and `_physics_process` step 5 computes `target_yaw = atan2(-horizontal.x, -horizontal.z)` so that `rotation.y` aligns the player's local -Z with the velocity vector.

**Historical note:** Before commit `41939bd` (2026-05-25), the controller used **local +Z** as forward. This was a coincidence of how the placeholder gray cone in `player.tscn` was originally oriented (the cone's tip pointed along +Z in `2026-05-23-player-controller-design.md`). The first real character rigged in Blender (authored facing +Y, exported via glTF Y-up → faces -Z in Godot, glTF's "front") would have appeared to run butt-first under the old convention. The flip aligns the project with Godot/glTF idiom so imported assets work without per-asset rotation.

**What references the new convention:**
- `scripts/player.gd` — `target_yaw` formula, `_resolve_dash_dir` fallback
- `scenes/player.tscn` — Facing cone is now positioned at `(0, 1.5, -0.35)` with basis rotated 180° around Y so the tip points along local -Z
- All Blender-authored characters: author facing **+Y in Blender**; glTF Y-up conversion makes this face **-Z in Godot** = the canonical and now-project-correct forward.

**Stale references in historical docs** (kept for time-stamp fidelity; do not act on them):
- `docs/superpowers/specs/2026-05-23-player-controller-design.md` — describes cone pointing +Z (original design)
- `docs/superpowers/specs/2026-05-24-rts-movement-depth-design.md` — quotes the old `_resolve_dash_dir` comment
- `docs/superpowers/plans/2026-05-23-player-controller.md`, `docs/superpowers/plans/2026-05-24-movement-depth.md` — reference the +Z fallback

If you find a `_resolve_dash_dir` snippet or commentary mentioning "+Z forward" or "override for visual consistency" in any doc, treat it as historical unless the doc was written on or after 2026-05-25.

---

## (Existing project-level gotchas)

These also exist but live in their own dedicated docs — listed here for discoverability:

- **Godot MCP tool quirks** — see `docs/godot-mcp-guide.md`. Covers: single-client WS bridge, leaked processes, runtime-vs-edit-time state, scene-mutation-on-wrong-scene risk, `get_debug_output` vs `get_console_output`.
- **Blender MCP tool quirks** — see `docs/blender-mcp-guide.md`. Covers: schema inconsistencies, data-API-over-`bpy.ops`, depsgraph staleness, edit-mode bmesh, glTF Material Output AO pattern, Blender 5.x API drift.
- **Asset pipeline shape** — see `docs/asset-pipeline.md`.

---

## Adding new gotchas

When you hit something the engine does that surprised you, add an entry above using the same shape: symptom → cause → fix → (optional) detect-proactively. Keep entries terse — the goal is fast scan-ability, not exhaustive prose. Cross-link to `docs/godot-mcp-guide.md` or `docs/blender-mcp-guide.md` for tool-specific surfaces.
