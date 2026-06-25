# RPG - first-person immersive-sim prototype (Godot 4.6)

A single-player FPS/RPG prototype built in **Godot 4.6**. The presentation is
deliberately crunchy: a low internal resolution, pixel/downscale post-process,
dither, film grain, night vision, and PS1-style material warping over a dense
first-person movement and combat sandbox.

Almost every number that affects feel lives in editable `.tres` resources or
Inspector exports, not hardcoded constants. The editor is the design surface.
The in-editor **CYBER SUNDAY** dev-tools plugin (`addons/cybersunday_tools/`)
is the front door for authoring: one-click generators for every content type,
a unified content browser, a component palette, level/scene/place tools, a
tuning browser, a faction matrix, project audits, and in-editor Dialogue /
Quest / LootTable editors. See the [authoring guide](docs/AUTHORING_GUIDE.md)
for the full Resource Authoring Map.

## Current Documentation

- [Current architecture](docs/CURRENT_ARCHITECTURE.md) - the live map for future
  humans and model passes.
- [Authoring guide](docs/AUTHORING_GUIDE.md) - how to make NPCs, levels,
  components, resources, saves, quests, stealth, UI, and content.
- [Component guide](scripts/components/README.md) - the drag-and-drop component
  idiom.
- [NPC GOAP brain](scripts/npc/goap/README.md) - current NPC decision layer and
  invariants.
- [Architecture review](ARCHITECTURE_REVIEW.md) - historical 2026-06-09 audit.
  Useful context, not current marching orders.
- `docs/audits/` - historical work orders and audit records. Treat them as
  provenance unless a current doc explicitly says otherwise.

## Running

1. Open `project.godot` in **Godot 4.6**.
2. Run `scenes/game.tscn`.
3. Let the editor finish any first-launch imports before judging missing assets.

`game.tscn` owns the persistent Player wrapper and `GameRoot`; `GameRoot` loads
the current `LevelData` as the runtime `Level` child. Run levels through
`game.tscn` unless you intentionally want a bare world scene with no player.

## Controls

| Action | Default |
| --- | --- |
| Move | `W` `A` `S` `D` |
| Look | Mouse |
| Jump | `Space` |
| Crouch / slide | `Shift` |
| Walk | configured through the action catalog |
| Attack / fire | Left mouse |
| Aim down sights | Right mouse |
| Reload | `R` |
| Pick up / throw / interact | `E` / configured actions |
| Flashlight | `F` |
| Night vision | `N` |
| Weapon slots | number keys |
| Quicksave / quickload | `F5` / `F9` |
| Debug reload scene | `End` |

Bindings are data-driven: defaults live in `project.godot` and
`managers/InputManager.gd`; rebindable rows live in
`resources/input/ActionCatalog.tres`.

## Project Layout

```text
rpg/
|-- project.godot                  autoloads, input map, render/window config
|-- scenes/
|   |-- game.tscn                  run scene: Player + GameRoot
|   |-- levels/                    level templates and level scenes
|   |-- TestLevel.tscn             current sample level content
|   |-- enemies/                   NPC/enemy/civilian scenes
|   |-- player/                    Player scene and player-side nodes
|   |-- components/                ready-made drop-in component prefabs
|   |-- effects/, decals/          visuals, gore, particles, post effects
|   |-- props/, throwable/         physical and throwable world objects
|   `-- projectiles/, weapons/     weapon/projectile scenes
|-- scripts/
|   |-- components/                editor-authored gameplay components
|   |-- npc/                       NPC, GOAP, perception helpers
|   |-- player/                    Player, movement, feedback, debug helpers
|   |-- combat/                    weapons, ammo, attacks, loot spawning
|   |-- world/                     GameRoot, LevelData, PlayerSpawn, groups
|   |-- items/, inventory/         item database and inventory model
|   |-- quests/, dialogue/         quest/dialogue resources and runtime
|   |-- ui/, input/, camera/       HUD, controls, view/camera systems
|   `-- tools/                     editor/run helpers
|-- managers/                      autoloads such as GameState and Settings
|-- resources/
|   |-- tuning/                    GameSettings resource groups
|   |-- settings/, input/          Options menu and keybind catalogs
|   |-- levels/                    LevelData resources
|   |-- characters/                NpcData archetypes
|   |-- items/, weapons/           Item and WeaponData resources
|   |-- factions/, dialogue/       authored RPG data
|   `-- materials/, shaders/, ui/  rendering and interface resources
|-- tests/                         GUT tests
|-- docs/                          current guide + historical audits
`-- addons/                        cybersunday_tools authoring plugin + GUT
```

## Architecture At A Glance

- **Editor-first authoring.** Gameplay features should appear as a drop-in
  component, an authored Resource, or a tuning `.tres`.
- **Level seam.** `GameRoot` loads a `LevelData` resource, instantiates its scene
  as `Level`, applies level music/ambience, and places the player at a
  `PlayerSpawn`. `LevelDoor` swaps levels at runtime.
- **Profile save model.** `GameState` saves player progression, inventory,
  reputation, flags, quests, perks, status effects, clock, respawn transform, and
  active level identity. It is not a full per-object world snapshot.
- **NPCs are data-driven.** `NpcData`, `BarkSet`, `GoapProfile`, factions,
  loadouts, and `LootTable` resources turn repeated inspector work into
  reusable archetypes.
- **GOAP is the only NPC brain.** The old FSM is gone. The planner handles
  combat, idle, flee, and no-target stealth investigation.
- **LookAtInteractable is the interaction family.** Pickups, merchants,
  containers, corpses, doors, radios, bonfires, and other interactables share
  the talk-layer hitbox/outline contract.
- **Tests favor seams.** Unit tests cover pure logic; focused contract tests
  should cover authored scene wiring, exported NodePaths, save/load identity,
  level flow, and data catalog sync.

## Common Workflows

**Author content fast:** open the **CYBER SUNDAY** bottom panel in the editor.
Its Content tab scaffolds any content `.tres` (quest, NPC, weapon, item,
faction, dialogue, loot table, perk, status effect, encounter, schedule,
cutscene, bark set, loadout, grapple, map) with one click, seeded and opened in
the Inspector; the Browse tab finds and opens any existing resource by type with
a live search filter. See the [authoring guide](docs/AUTHORING_GUIDE.md) for
which fields drive what.

**Make a level:** start from `scenes/levels/LevelTemplate.tscn` or
`scripts/tools/new_level.gd`, bake navigation, create a `LevelData`, then point
`GameRoot.level` or a `LevelDoor.target_level` at it.

**Make an NPC archetype:** author an `NpcData` in `resources/characters/`, set
its faction, stats, weapon, barks, GOAP profile, perception, movement, and loot,
then assign it to an NPC's `profile`.

**Add loot:** author `Item` resources in `resources/items/`, use `ItemStack` for
fixed contents, and use `LootTable` for random drops on containers, pickups, and
NPC archetypes.

**Add a player-facing option or keybind:** add the input/default in
`project.godot` and `InputManager.gd`, then add the `ActionSpec` or
`SettingSpec` resource row. Do not hand-build Options menu UI.

**Change save behavior:** update `GameState`, then test both value round-trips
and identity round-trips such as `LevelData.resource_path`.

## Tests

Per `CLAUDE.md`, do **not** run the full GUT suite automatically. When the user
asks for it, run:

```cmd
godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit
```

Prefer narrow validation while working: scene-instancing tests for prefabs,
ConfigFile round-trips for saves, Resource validation for data catalogs, and
off-tree pure tests for planner/combat/math logic.

## Current Rough Edges

- Save/load preserves profile and active level identity, but not every placed
  object's state. Doors, containers, corpse discovery, spawned pickups, and dead
  NPCs need stable world IDs before they can become exact snapshot data.
- Authored scene wiring matters. Prefab exported `NodePath`s and required
  children deserve contract tests because code-only unit tests will not catch a
  bad inspector assignment.
- Some old audit docs intentionally remain in the repo. Read the current docs
  first; old audits are context and historical reasoning.
