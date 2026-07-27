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
- Object state such as opened doors, looted containers, dead NPCs, and spawned pickups needs a stable id before
  it can be saved. If it is intentionally not persisted, document that near the system.
- The additive per-object ledger is `GameState.world_objects` (keyed by level + `WorldSaveId.key_for`): `Door`
  open/locked and consumed-`CanPickUp` / `MoneyPickUp` / `UpgradePickup` / destroyed-`CanDestroy` "gone" bits
  persist there (a code-spawned pickup opts out — `MoneyPickUp`/`UpgradePickup` via `persist_collected = false`, a
  loot-dropped `CanPickUp` via `build_model_from_item`). Extend it for a new
  object type via `record_object_state`/`object_state` + a `save_id` export; it stays additive (never rebrand the
  profile save as an exact snapshot). Containers, dead NPCs, and dynamic spawns are deliberately still excluded.
- Corpse discovery is the narrow exception already handled: `Corpse.discovered` persists through
  `GameState.discovered_corpses`, keyed by authored `Corpse.save_id` when available and by a fallback
  level/path/position marker otherwise. Use `save_id` for important hand-placed bodies.

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
  consumers that poll the action name keep working. `InputManager` cross-validates these three name-surfaces at
  boot (dev builds) via `validate_action_sources()` and pushes a warning per drifted name, so a mismatch surfaces
  the first time you run — not just under GUT (`tests/test_input_manager.gd` + `tests/test_input_action_catalog.gd`
  pin it). To show a key in UI/prompts, query `InputManager.get_action_binding(action)` — the single binding-query
  seam (`display_key()` is a kept alias); never read the `InputMap` events yourself.
- **New tunable** (volume, sensitivity, FOV, accessibility, screen shake, …) → add a typed `var` **and** a
  named `set_*` setter to the `Settings` autoload (it owns storage / apply / persist — keep it typed; do
  NOT move it to a Variant dict, gameplay reads `Settings.<field>` directly and a test instantiates it bare),
  **then** add ONE `SettingSpec` row to the catalog bound to that setter by name. No `OptionsMenu` code.

## Player-facing text and identity
- Player-facing strings go through `PlayerText` (`scripts/ui/player_text.gd`) or an authored resource field —
  never a raw literal at a paint site (`label.text = "…"`, `notify_toast(...)`, `MenuStyle.make_title(...)`).
  `tests/test_player_text.gd` is a shrink-only ratchet over the audit panel's paint-site scanner: a new
  literal fails the suite; moving one into `PlayerText` means ratcheting the BASELINE **down** in the same
  change. `[PH] ` marks unauthored placeholder copy; only `PlayerText.prefixed`/`strip_prefix` touch the prefix.
- Designer-authored templates substitute **named tokens** by replace — `{amount}`, `{part}`, `[mph]` — never
  the `%` format operator (a designer's literal `%` must not error; legacy `%s`/`%d` still substitute).
- `TextFormat` (`scripts/ui/text_format.gd`) owns substitution/plural/number formatting: whole templates with
  `{named}` tokens (`subst`), real singular/plural template pairs (`plural`), one number trim (`num`), money
  via `Zorkmids.money_text` — never the `%` operator or a hand-rolled `(s)` in player prose, never fragment appends.
- Display names come from authored resources — `StatInfo.title` (StatText), `Faction.display_name`,
  `Ability.display_name` (via `AbilityRegistry.display_name_for`), `Perks.display_label` — never
  `.capitalize()` on an id; capitalize is only the blank/missing degrade INSIDE those accessors.
- Display strings are never behaviour keys. Stable NPC identity is `NpcData.id` (blank falls back to
  `display_name`; `NPC.identity_key()` is the accessor) — quests/known-names key on it, save v4. Never branch
  on a shown label; add a key beside it (the `ActionSpec.section_key` / `SettingSpec.tab` idiom).

## Navmesh bake policy (levels)
NPCs path on a baked `NavigationRegion3D`. Treat "stuck on roofs / pacing in place" as a bake-health problem first.
- Start every level from `scenes/levels/LevelTemplate.tscn` or File→Run `scripts/tools/new_level.gd`; templates carry
  the required `NavigationMesh` parameters.
- Keep `geometry_parsed_geometry_type = 1` (**Static Colliders**) on the region's `NavigationMesh`. The engine default
  is `2` (**Both**), which also bakes from VISUAL `MeshInstance3D` geometry — so decorative meshes with no collider get
  baked walkable and NPCs stick on "meshes, not just collision". Walkability here is authored as COLLISION (floor
  `StaticBody`, CSG `use_collision`, `NavBlocker` CARVE), so parse colliders only. (Solid props that DO have colliders
  still bake a walkable top — that's the separate `NavBlocker(CARVE)` / `agent_max_climb` issue below.)
- Keep `agent_max_climb` ~`0.4` and `agent_max_slope` ~`30` on the region's `NavigationMesh`. Raising climb (or omitting
  the field — it falls back to the engine default `0.9`) is the exact regression that bakes walkable polys onto props/car roofs.
- Carve solid props with a `NavBlocker(CARVE)` child (movables use `AVOID`); re-bake after any geometry/CARVE change.
- After baking, File→Run `scripts/tools/audit_navmesh.gd` — target ~1 island / ~0 elevated (the `NavSandbox.tscn`
  baseline). The `LevelRoot` inspector validator also flags islands>1 / elevated>0 / climb>0.5.
- **Deliberate cross-ledge traversal (a drop/climb taller than `agent_max_climb`, which the bake leaves as a
  *disconnected island*) is authored with a `NavLink` drop-in (`scripts/components/nav_link.gd`,
  `extends NavigationLink3D`), NOT a bake change.** Child it to the level at the ledge, drag the two endpoints onto the
  lower/upper surfaces (`auto_project` snaps them); `TWO_WAY` = climb+drop, `ONE_WAY_DOWN` = drop-only cliff. **No
  re-bake** (a link is a runtime routing edge). NPCs get the upward launch from the `Locomotor` link-ascent driver
  (`_on_link_reached`), which is decoupled from the combat `allow_hop` gate so *idle* NPCs climb. Without a `NavLink`,
  no NPC will ever walk off or climb a ledge — A* has no route across the island gap.
- **Stairs are the special case of that island gap.** This project's brush stairs have **0.5 m risers > `agent_max_climb`
  0.4**, so every flight bakes as disconnected islands. NPCs cross them with two pieces: (1) `Locomotor.enable_step_up`
  (ON for every NPC via `_build_locomotor`, OFF for a bare mob) — a host-agnostic port of the Player's `_try_step_up`
  that lets a `CharacterBody3D` physically climb a riser (`move_and_slide` alone can't — that's why the Player always
  needed its own step-up); called from `npc.gd apply_velocity` around `move_and_slide`. (2) A **`NavLink` with
  `traversal = WALK`** across each flight for the A* routing edge — WALK suppresses the ballistic launch
  (`_on_link_reached` reads `walk_traversal()` duck-typed) so the NPC *walks* the steps instead of leaping. Combat
  pursuers climb stairs even *without* the link (the unreachable-target straight-line charge + step-up). Do NOT "fix"
  stairs by raising `agent_max_climb` (regresses prop/roof baking + trips the `LevelRoot` validator) or with a ramp
  collider (changes player stair-feel) unless you intend those trade-offs.
- **Auto-generate links instead of hand-placing them: File→Run `scripts/tools/generate_nav_links.gd`.** It scans the
  region for disconnected islands within a jump/drop budget and emits a `NavLink` per gap (brain = `NavLinkPlanner`,
  which mirrors `NavMeshAudit`'s island detection; unit-tested). PREVIEW-first (`APPLY = false` prints, writes nothing;
  set `APPLY = true` + Ctrl+S to insert). Idempotent — replaces only its `GeneratedNavLinks` container, so hand-placed
  links survive; **re-run after every re-bake**. It auto-classifies each gap: bare ledge→`LAUNCH`, cliff→`ONE_WAY_DOWN`,
  and — via a physics raycast probe (a self-built `PhysicsServer3D` space over the scene's colliders, so it works in
  File→Run) between the island rims — a **staircase/ramp**→`WALK` link (continuous ground rising in ≤`step_up_height`
  steps). So stairs are handled automatically. It also RESCUES sinks: a *small* drop-only island (only one-way-down
  links arrive, no walk/two-way/drop-out leaves) would strand a pursuing/falling NPC forever (no A* route back up), so
  its cheapest incoming drop is promoted to a climbable `TWO_WAY` (the link-ascent launch scales to any height); only
  pure sinks smaller than the main floor qualify, so a legit one-way cliff to the ground floor is left alone. Caveat:
  bake first (bad islands → bad links) and eyeball the result.
- **Blockout shell geometry = CSG (native).** Carve floors/walls/rooms as `CSGBox3D`/`CSGCombiner3D` under
  `Geometry/Blockout` instead of hand-aligning `MeshInstance3D`+`CollisionShape3D` boxes. Verified in Godot 4.6.3:
  CSG with `use_collision` feeds the `navmesh`-group bake in every parser mode, so it drops straight into this same
  bake + audit + validator — no new pipeline. The CYBER SUNDAY **Place** tab has one-click buttons
  (Building Shell / Floor / Wall / Ramp) via `addons/cybersunday_tools/dock_place/csg_blockout.gd`.
- **Seamless interiors: doorways need ≥ ~2.4 m clear.** With `agent_radius` 0.6 the bake erodes openings; a narrower
  door pinches shut and the interior bakes as its OWN island (NPCs can't enter). `build_room_shell()` floors the door
  to 2.4 m. This is the #1 gotcha for an open map with enter-able buildings on one navmesh.

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
- README links must point at files that exist.
- Keep docs current-only. Do not preserve review or task files that no longer match the code; delete or replace
  them with up-to-date guidance.
- When a planned seam becomes real (`LevelData`, `NpcData`, `LootTable`, corpse-discovery persistence, etc.),
  update docs that still describe it as missing.
- Treat documentation as part of "done" for every non-trivial change. Before final response, decide whether the
  change affects docs; if it does, update them in the same diff. If it does not, say "docs impact: none" in your
  working notes or final summary.
- Update the right surface:
  - `README.md` for project overview, setup, common workflows, and user-facing feature summaries.
  - `docs/CURRENT_ARCHITECTURE.md` for system contracts, save model, level flow, data/resource seams, and risks.
  - `docs/AUTHORING_GUIDE.md` for designer-facing steps, exported fields, resource folders, plugin workflows,
    content examples, and gotchas.
  - `docs/CYBER_SUNDAY_PLUGIN_QA.md` for acceptance checks when editing `addons/cybersunday_tools/`.
  - Subsystem READMEs such as `scripts/npc/goap/README.md` or `scripts/components/README.md` for local invariants
    an agent must read before editing that subsystem.
  - Nearby code comments for invariants that are easiest to understand at the call site.
- Documentation must name the current script/resource paths and field names. When renaming, moving, deleting, or
  changing behavior, search the docs with `rg` and update every affected mention.
- Good docs are operational: they tell a future human or AI what to click, what resource to author, what contract
  must hold, what gets saved, what gets tested, and what will fail softly.
- Bad docs are vibes, plans without implementation, orphaned links, duplicated source-of-truth, or prose that
  conflicts with code. Replace those with current guidance.
- After doc edits, run `rg` for removed paths/symbols when relevant and always run `git diff --check`.

## CYBER SUNDAY plugin work
- Before editing `addons/cybersunday_tools/`, read `docs/CYBER_SUNDAY_PLUGIN_QA.md`.
- Plugin features that write files must preview, confirm, and report changed paths.
- Read-only tabs must stay read-only unless the UI label and authoring docs make the write behavior explicit.
- After plugin script edits, toggle **CYBER SUNDAY Tools** off/on in Project Settings → Plugins so Godot reloads it.

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
- End commit messages with: `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`
- Do **not** push without an explicit request. The user works on `main`.
