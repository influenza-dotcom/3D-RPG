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
- `itch_shots.gd` is the one deliberate exception to that naming: it shoots PNGs but they are **marketing**
  stills for the itch.io store page, not a QA comparison, so it is not called `*_qa_shots.gd`. It lives here
  anyway because it is the same animal — a windowed run that boots the real game and photographs it. Two modes:
  `--mode=recon` rings every point of interest in the main level and composites the candidates into one
  contact sheet (plus a `contact_sheet.txt` legend giving each tile's exact eye position), `--mode=final`
  shoots the hand-picked `SHOTS` list at 1920x1080. Re-pick framings from a fresh recon after the level
  changes; the `SHOTS` entries are recon values copied verbatim, so they go stale when the geometry does.
- Shared walks and image diffs live in `qa_shot_helpers.gd` here — preload it BY PATH
  (`const QaShots := preload("res://scripts/tools/probes/qa_shot_helpers.gd")`); it has no `class_name` on purpose
  so a probe never depends on the editor having rescanned the global class cache.
- Probes that reach into the debug console's world actions preload `scripts/components/debug_actions_world.gd`
  and its family files by path (`__lens_probe.gd` reads `DOF_AUTHORED` / `LENS_AUTHORED` from the view file).
- A probe that exists to judge a LOOK gets a synthetic stage, not the level: `__skyscraper_void_look_probe.gd`
  builds a bare roof slab + this project's real sky + the `SkyscraperVoid` drop, because the live level's HUD,
  sky title and colour grade sit on top of everything and no palette question can be settled through them. Its
  twin `__skyscraper_void_probe.gd` then drops the same component on the LIVE level to prove the integration
  (what the auto fit measured, and that Ps1Warp did not repaint the drop). ⭐Both print NUMBERS beside the
  frames — the look probe reports the lower-half luminance and the share of the frame that has already
  collapsed to pure haze, because "too dark to read" and "already total haze" are the two failure modes and
  neither is settleable by eye alone.
- New probes go here, not in `scripts/tools/`. The debt scanners (`text_debt.gd`, `menu_sound_debt.gd`) stay in
  `scripts/tools/` because `CLAUDE.md` and CI name them by that path.
