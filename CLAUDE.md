# Project conventions — Godot 4.6 FPS/RPG

Working notes for this repo. Keep it short and current.

## Keep the settings menu in sync with features (don't stop at gameplay code)
When you add anything player-facing, wire it into the in-game settings menu too:
- **New keybind** → register the action in `managers/InputManager.gd` **and** `project.godot` `[input]`,
  **and** add it to `OptionsMenu.REBINDABLE` (`scripts/ui/options_menu.gd`) so players can rebind it.
  The action *name* is the stable key — rebinding only swaps the bound event, so consumers that poll the
  action name keep working.
- **New tunable** (volume, sensitivity, FOV, accessibility, screen shake, …) → expose it on the matching
  `OptionsMenu` tab **and** persist it through the `Settings` autoload — never leave it a hardcoded const.

## Tests (GUT)
- Validate headless before every commit:
  `& "C:\Users\dalla\bin\godot.cmd" --headless --path . -s addons/gut/gut_cmdln.gd -gexit`
- `tests/*.gd`, `extends GutTest`, `func test_*() -> void`, verbose assert messages.
- Resources (RefCounted) → `.new()` then release with `= null`. Nodes → `.new()` + `.free()` (or
  `add_child_autofree`).
- **Do NOT run an NPC's / Player's `_ready()` in a unit test** — it instantiates weapon.tscn, nav, audio,
  FreezeFrame, and mutates shared statics. Build actors off-tree via `load(path).new()` WITHOUT
  `add_child` and assert pure logic / method surface; in-tree behaviour is verified by manual playtest.

## GDScript / editor
- **TABS** for indentation, never spaces. `class_name` is global.
- `.gd.uid` sidecars ARE tracked — commit them alongside new scripts (`godot --headless --import`
  generates one if it's missing).
- The user usually has the editor open; right after edits it reimports and can briefly yield empty
  PackedScenes ("node count is 0") or "File not found" in headless runs — retry after a few seconds, it
  clears. Not a code bug.

## Git
- Commit only the paths you explicitly changed — never sweep the working tree (the user is actively
  authoring scenes like `Level.tscn`).
- End commit messages with: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
- Do **not** push without an explicit request. The user works on `main`.
