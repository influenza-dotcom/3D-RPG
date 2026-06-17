# Project conventions — Godot 4.6 FPS/RPG

Working notes for this repo. Keep it short and current.

## Designer-first: the editor is the modding surface
The user builds the game IN THE EDITOR, like modding or a level editor. Every feature must be reachable
without touching code:
- **Behaviour** → a drag-drop component (`class_name` Node/Area3D + `@export` config; the
  LookAtInteractable / Ability / MusicDirector idiom). Never a branch buried in a big script.
- **Gameplay numbers** (bounties, costs, rates, ranges, durations) → either an `@export` on the component
  (per-instance tuning) or a `resources/tuning/*.tres` group on the `GameSettings` registry (global
  tuning, e.g. `EconomySettings`). **Never a hardcoded const** for anything a designer might tune.
- **Content** (stock lists, loadouts, loot, stats) → authored Resources (`StockEntry`, `Loadout`,
  `NpcData`, `Item` .tres), editable in the inspector.

## Keep the settings menu in sync with features (don't stop at gameplay code)
When you add anything player-facing, wire it into the in-game settings menu too:
The Options menu is **data-driven**: every row is a `SettingSpec` in `resources/settings/SettingsCatalog.tres`
(consumed by `scripts/ui/options_menu.gd`). Don't hand-build rows — add a spec.
- **New keybind** → add the keyboard/mouse default to `project.godot` `[input]` (the editor Input Map panel)
  + the controller default in `managers/InputManager.gd`, **and** add ONE `ActionSpec` row to
  `resources/input/ActionCatalog.tres` (`action`, `label`, `section`, `rebindable`). The Options → Controls
  tab's section headers + rebind rows are GENERATED from that catalog (`ActionCatalog.keybind_specs()`, which
  OptionsMenu appends to the SettingsCatalog) — do NOT hand-author a `Keybind` `SettingSpec` in
  `SettingsCatalog.tres`. The action *name* is the stable key — rebinding only swaps the bound event, so
  consumers that poll the action name keep working.
- **New tunable** (volume, sensitivity, FOV, accessibility, screen shake, …) → add a typed `var` **and** a
  named `set_*` setter to the `Settings` autoload (it owns storage / apply / persist — keep it typed; do
  NOT move it to a Variant dict, gameplay reads `Settings.<field>` directly and a test instantiates it bare),
  **then** add ONE `SettingSpec` row to the catalog bound to that setter by name. No `OptionsMenu` code.

## Tests (GUT)
- **Do NOT run the GUT suite automatically** — not after edits, not before commits. Only run it when the
  user explicitly asks. When asked, run headless:
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
