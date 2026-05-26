# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Godot project. See `project.godot` for engine and feature configuration.

## Working in this repo

- **For any work involving the Godot MCP tools, read `docs/godot-mcp-guide.md` first.** It documents the connection quirks (single-client WS bridge, leaked processes), property formats, runtime-vs-edit-time state, and the read-only tool surfaces (`resource`, `project`) that are easy to trip on.
- **For any work involving the Blender MCP tools, read `docs/blender-mcp-guide.md` first.** It documents the schema inconsistencies (`name` vs `object_name`, `output_path` basename-only), the data-API-over-`bpy.ops` rule, depsgraph staleness on derived reads, edit-mode bmesh discipline, the `glTF Material Output` node group pattern for AO, and Blender 5.x API drift gotchas (slotted actions, `open_mainfile` context bug).
- **For Blender → Godot asset pipeline shape (directory layout, naming, what crosses), read `docs/asset-pipeline.md`.** It documents the parallel-vs-nested decision (parallel is recommended for real projects), naming discipline that leaks from Blender into Godot (mesh-data, action, bone names), PBR material survival mapping, multi-material slot ordering, and rigged-model export-time rules.
- **For GDScript work, lean on the `godot-gdscript-patterns` skill.** It covers Godot 4.x idioms — state machines, signals, autoloads, resource-based data, object pooling, static typing conventions, allocation-free hot paths, and worked examples (health/damage, hitbox/hurtbox, async scene loading). Installed once per machine via the bootstrap; activates automatically on GDScript context.
- **For AnimationTree work (3D character animation, state-machine-driven blending), lean on the `godot-animation-tree-mastery` skill.** It covers StateMachine transitions, BlendSpace1D/2D/Blend2, parameter path discipline, sync groups, TimeScale, root motion, advance expressions, AnimationTree vs AnimationPlayer conflicts, and cutscene interruption patterns. Anti-pattern-focused — assumes familiarity with basic Godot animation. Activates only on AnimationTree context.
- **For Godot engine/editor quirks** (Inspector behavior, `.tscn` file format gotchas, parser warnings, embedded-game-tab oddities), check `docs/godot-gotchas.md` first. This is the project-level catalog of "we hit this and here's the fix." It's the portable counterpart to per-machine personal-gotchas skills — add new entries here so any developer (human or LLM, any machine) cloning the project benefits.
- **Invoke the `godot-personal-gotchas` skill proactively, not just reactively.** It's a per-machine symptom-to-fix index that complements `docs/godot-gotchas.md`. Specifically invoke it when:
  - A Godot operation produces a silent no-op (call returns, no error, no visible change).
  - A GDScript parser warning fires and it's not immediately obvious why.
  - An Inspector edit doesn't take effect, or `.tscn` content looks off after a session.
  - About to do something that has historically been fragile: hand-edit `.tscn`/`.tres`, change window/display state from script, write GDScript using `clamp`/`min`/`max`/`abs`/`sign`, mutate scenes via MCP tools.
  - Before assuming "I know what's happening" on an unexpected Godot behavior — check the skill FIRST, not after spending time debugging.
  When you discover a new Godot gotcha, add it to BOTH `docs/godot-gotchas.md` (portable, project-wide) and the personal skill (per-machine fast lookup). The two layers serve different scopes.
- **For periodic parity audits between this project's docs/memory and the source skills** (`init-godot-claude-project`, `godot-personal-gotchas`), invoke the `sync-godot-skills` skill. Run it after adding entries to `docs/godot-gotchas.md`, the MCP guides, or memory `gotcha_*.md` files so the learnings propagate to future Godot projects.
- **Project-local subagents live in `.claude/agents/`** — dispatch them via the `Agent` tool to offload heavy reference docs from main context: `godot-gotcha-reviewer` (read-only diff scan against the gotcha catalog, use before commits or after live-Inspector tuning), `gotcha-curator` (files a new gotcha consistently across `docs/godot-gotchas.md` + memory + `MEMORY.md`), `godot-mcp-operator` (multi-step godot-mcp work — scene manipulation, runtime verification, error diagnosis; loads `docs/godot-mcp-guide.md` so main context doesn't have to).
- Edits to scenes (`.tscn`) and resources (`.tres`) should normally be done through the Godot editor; hand-editing is possible but easy to corrupt. Prefer opening the project in Godot when changing scene structure.
- `.godot/` is the editor's generated cache and is gitignored — never edit files in it directly; regenerate by opening the project in the editor.
- **Git: standard commit discipline applies.** This project is under version control as of 2026-05-24. Stage specific files, commit with descriptive messages. If you encounter older plan/handoff docs that say "saving files IS the commit" or "no git repository," that guidance is stale — they were written before the repo was initialized.

## Running

Open the project in the Godot editor and press F5. From the CLI, `godot --path .` runs the main scene defined in `project.godot`.
