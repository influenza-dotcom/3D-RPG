# scripts/tools/probes — runtime probes and QA-shot scripts

Hand-run instruments, not shipped code and not GUT tests. Each one boots the REAL game (or a synthetic scene),
drives it, and either measures something or shoots PNGs so a change can be judged by sight. They were moved here
from `scripts/tools/` on 2026-09-14 so the real tooling (validators, bakes, the nav-link planner, the soak and
smoke harnesses, the debt scanners) is no longer mixed with them.

**They are kept on purpose.** A `__` prefix means the file calls itself disposable, but nearly every probe here is
the LIVE proof of a feature the unit tests cannot build in-tree (`Player` and `NPC` cannot run `_ready()` under
GUT), so a probe is deleted only when the feature it proves is gone. Before deleting one, grep `docs/`, the
memory notes and the comments of the script it exercises — most are cited as "the real proof".

## Running one

- A `SceneTree` probe runs headless or windowed with `-s`:
  `godot --path "<absolute project path>" -s scripts/tools/probes/<name>.gd -- --shots-dir=<dir>`
- A `Node` probe has a sibling `.tscn` and runs as the boot scene:
  `godot --path "<absolute project path>" res://scripts/tools/probes/<name>.tscn -- --run=<tag>`
- Anything that shoots a frame or measures the renderer must run **windowed** — headless never compiles shaders,
  never renders a shadow map and skips the effect prewarm entirely. Each header says which it needs.

## Conventions

- `__<name>_probe.gd` measures; `<name>_qa_shots.gd` shoots PNGs; `preview_*` renders framing stills.
- Shared walks and image diffs live in `qa_shot_helpers.gd` here — preload it BY PATH
  (`const QaShots := preload("res://scripts/tools/probes/qa_shot_helpers.gd")`); it has no `class_name` on purpose
  so a probe never depends on the editor having rescanned the global class cache.
- Probes that reach into the debug console's world actions preload `scripts/components/debug_actions_world.gd`
  and its family files by path (`__lens_probe.gd` reads `DOF_AUTHORED` / `LENS_AUTHORED` from the view file).
- New probes go here, not in `scripts/tools/`. The debt scanners (`text_debt.gd`, `menu_sound_debt.gd`) stay in
  `scripts/tools/` because `CLAUDE.md` and CI name them by that path.
