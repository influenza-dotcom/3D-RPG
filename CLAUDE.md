# Project conventions — Godot 4.6 FPS/RPG

Working notes for this repo. Keep it short and current.

## Comments are semantic context
The user intentionally wants rich comments: they are breadcrumbs for future humans and future AI passes reading
the project cold. Keep them, but keep them true.
- Prefer comments that explain intent, invariants, editor-authoring rules, and cross-system contracts.
- Good comments answer "why is this shaped this way?", "what must a designer wire in the Inspector?", and
  "what other system relies on this behavior?"
- Do not narrate obvious single lines. Spend comment budget on save/load, scene hierarchy, signals, autoloads,
  Resources, test seams, and known limitations.
- When changing code, update or delete nearby comments/docs that no longer match reality. Stale prose is worse
  than no prose because future agents will trust it.

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

## System contracts matter more than isolated green tests
This codebase is strongest when small systems compose cleanly. Before large changes, identify the contract being
touched: prefab scene wiring, Resource identity, save/load round-trip, level transition, input action, signal, or
autoload state.
- Add focused contract tests for authored scenes and resources when a bug depends on Inspector wiring
  (`PackedScene.instantiate()`, exported NodePaths, required children, group membership).
- For save/load work, test identity as well as coordinates or values: e.g. active `LevelData` path, equipped item,
  quest id, container id, or scene path.
- For level-flow work, cover the seam between `LevelDoor`, `GameRoot`, `LevelData`, `PlayerSpawn`, and `GameState`.
- Do not rely on "playtested" for a seam that can be checked cheaply off-tree or with a tiny in-tree harness.

## Save semantics must be explicit
Keep one clear answer for what a save means. If it is a profile/checkpoint save, UI and docs should not imply an
exact world snapshot. If it is an exact snapshot, persist the active level plus per-level object state.
- At minimum, saves that restore a player transform must also restore the level identity that transform belongs to.
- Object state such as opened doors, looted containers, corpse discovery, dead NPCs, and spawned pickups needs a
  stable id before it can be saved. If it is intentionally not persisted, document that near the system.

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

## Navmesh bake policy (levels)
NPCs path on a baked `NavigationRegion3D`. The recurring "stuck on roofs / pacing in place" bug was a BAKE fault,
not the AI (TestLevel audited at 83 islands, 1901/2470 polys elevated).
- Start every level from `scenes/levels/LevelTemplate.tscn` (or File→Run `scripts/tools/new_level.gd`) — NOT a copy
  of `TestLevel.tscn`, whose `NavigationMesh` omits `agent_max_climb` and so falls back to the engine default 0.9.
- Keep `agent_max_climb` ~`0.4` and `agent_max_slope` ~`30` on the region's `NavigationMesh`. Raising climb is the
  exact regression that bakes walkable polys onto props/car roofs.
- Carve solid props with a `NavBlocker(CARVE)` child (movables use `AVOID`); re-bake after any geometry/CARVE change.
- After baking, File→Run `scripts/tools/audit_navmesh.gd` — target ~1 island / ~0 elevated (the `NavSandbox.tscn`
  baseline). The `LevelRoot` inspector validator also flags islands>1 / elevated>0 / climb>0.5.

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
- Prefer narrow contract tests for risky scene/resource seams: prefab exported NodePaths, required children,
  save/load round-trips, level identity, and input/action catalog sync.

## Docs hygiene
- README links must point at files that exist. If an architecture/audit doc is historical, label it historical.
- Keep one current status/architecture entry point for future agents; old audits are useful context, not marching
  orders.
- When a planned seam becomes real (`LevelData`, `NpcData`, `LootTable`, etc.), update docs that still describe it
  as missing.

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
