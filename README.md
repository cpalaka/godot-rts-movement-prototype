# Godot RTS Movement Prototype

A 3D player movement prototype in Godot 4.6, exploring Smash-Bros-style heavy-momentum movement adapted to a top-down ARPG / Dota-style context. The intent is a movement system where skill expression — drifts, pivots, foxtrot patterns, dash-curves — emerges from the architecture rather than from explicit unlocks.

**Live demo:** https://cpalaka.github.io/godot-rts-movement-prototype/ *(deployed via GitHub Actions on push to main)*

## Controls

| Input | Action |
|---|---|
| Hold RMB | Steer toward cursor |
| Move cursor | Set direction & speed (closer cursor = slower) |
| Space | Dash (directional impulse channel, ~320ms decay) |
| O | Toggle fullscreen |
| Esc | Quit |

## Design

Two spec documents capture the rationale:

- [`docs/superpowers/specs/2026-05-24-rts-movement-depth-design.md`](docs/superpowers/specs/2026-05-24-rts-movement-depth-design.md) — momentum + steering + impulse channel architecture, the emergent depth that falls out of it (drift, pivot, foxtrot, DI), and the tuning surface.
- [`docs/superpowers/specs/2026-05-24-animation-state-machine-design.md`](docs/superpowers/specs/2026-05-24-animation-state-machine-design.md) — the AnimationTree topology (BlendTree → Top → Locomotion sub-SM + OneShot dash + Hit slot), threshold-gated transitions, and parameter wiring.

Both shipped through Step 7 (live-feel tuning) on 2026-05-26.

## Local development

1. Install [Godot 4.6.2 stable](https://godotengine.org/download/).
2. Open `project.godot` in the editor.
3. Press **F5** to run.

The `addons/godot_mcp/` plugin is vendored for [Claude Code](https://claude.com/claude-code) MCP integration during development. It's not required to run or build the game.

## Building from source

Export presets for Web, macOS, and Windows are committed in `export_presets.cfg`. Export templates for the matching Godot version must be installed first (Editor → Manage Export Templates → Download and Install).

From the editor: **Project → Export → pick a preset → Export Project**.

From the CLI:

```sh
godot --headless --export-release "Web" builds/web/index.html
godot --headless --export-release "macOS" builds/macos/3d-proto-1.zip
godot --headless --export-release "Windows Desktop" builds/windows/3d-proto-1.exe
```

The `builds/` directory is gitignored except for `.gdignore` (which keeps Godot from auto-importing build outputs).

## License

MIT. See [LICENSE](LICENSE).
