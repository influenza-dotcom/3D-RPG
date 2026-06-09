# Architecture Review — Content Pipeline · Data-Orientation · SRP

*Holistic multi-agent review (2026-06-09): 8 subsystem mappers → 3 concern analysts → 1 architect synthesis. 114 scripts, ~15.4k lines of GDScript.*

## TL;DR

The architecture is **bimodal**, and the boundary is consistent across every subsystem: **where data and components were extracted, the code is excellent** (the 9 tuning `.tres` behind `GameSettings`; `WeaponData`/`ThrowableData`/`Faction`/`Item`; `ItemDb` as a shared registry; the `GunMesh` and `NPC` `_build_components()` splits with null-guarded off-tree facades). **Where they weren't, it's a hand-built monolith** (one 1509-line `Level.tscn` with no loader; `npc.gd`@2027 carrying ~11 responsibilities and ~55 exports re-tuned per instance; 10 hardcoded bark arrays; loot fixed to weapon+ammo).

Two **empty scaffold dirs** — `resources/characters/` and `resources/effects/` — are the smoking gun that entity-data and effect-data extraction were *planned and abandoned*.

**The single most leveraged move is an `NpcData` Resource.** It sits at the intersection of all three goals (biggest content-pipeline win, keystone data-extraction, *and* it removes the largest config chunk from the worst god-object) and it is the prerequisite that unblocks loot tables, spawn/encounter data, and a second level. **Crucially, nothing here requires inventing a new pattern** — every initiative replicates `GunMesh`/`NPC` component splits, the `Faction.tres`/`WeaponData` data model, or the `GameSettings` registry that already exist.

## Overall health

Healthy and unusually self-aware for a solo project — the hard architectural thinking is already done and partially executed; what remains is **finishing it**. Real, load-bearing strengths: a complete const→`.tres` tuning migration, a single shared `ItemDb` registry unifying player/NPC/loot/merchant item resolution, a clean abstract `Character` base with `Player`/`NPC` as parallel siblings (not subclassed), polymorphic weapon-host aim, pure stateless logic libs (`HostilityHelpers`, `ShotResolver`, `MovementHelpers`, `FallDamage`), and a documented, test-friendly component idiom (`.new()` + `host` + null-guarded facades).

The debt is **concentrated, not diffuse**: five oversized roots (`npc.gd`@2027, `player.gd`@1158, `character.gd`@532, `attack.gd`@530, `Throwable.gd`@502) hold extractable, *nameable* seams, and the content pipeline has no level-authoring scaffold and no entity/loot/spawn data layer. Risk is **low** because the fixes are mechanical replications of existing patterns, with the existing smoke/unit tests as a safety net. The main hazard is **sequencing**: build `NpcData` before the spawn/level layer, or the later work has nothing to instantiate.

## Cross-cutting themes

1. **A data-driven entity definition (`NpcData`) is the single keystone serving all three goals at once.** Extracting `npc.gd`'s ~55 exports + bark arrays into an `.tres` (mirroring `Faction.tres`) simultaneously: collapses 12–30 inspector clicks to one resource assignment (pipeline), fills the empty `resources/characters/` migration (data), and pulls the largest config block off the worst god-object (SRP). It's also the prerequisite for `LootTable`, `EncounterData`, and a second level.
2. **The proven component-split idiom (`_build_components()` + `.new()` + `host` + null-guarded facade) is the universal SRP tool *and* it keeps off-tree tests working.** Already verified in `gun_mesh.gd`@79 and `npc.gd`@417. Every remaining extraction is a mechanical replication, not a redesign — so SRP debt is cheap to pay down incrementally rather than via a big-bang rewrite.
3. **Hardcoded content strings + hand-maintained registries are the same anti-pattern in three places.** The 10 bark arrays (`npc.gd`:750-784), `RECKLESS_LINES`/`AIM_LINES` in `player.gd`, and `ItemDb`'s two const path arrays all bypass the data layer the project otherwise mandates — raiders and townsfolk shout identical lines, content isn't localizable, and a forgotten item `.tres` silently fails at runtime.
4. **Duplicated *application* logic across parallel paths is the strongest pull toward shared seams that also shrink the god-objects.** Crit/sneak/overkill/HP-pitch damage application is copy-pasted between `attack.gd` (~322-408) and `projectile.gd` (~71-118) and must be hand-synced; ~35 lines of `_ready`+talk-handler boilerplate are duplicated across `container`/`can_pick_up`/`merchant`/`lootable_corpse`.
5. **Authoring new levels and new objects is blocked by the same missing seam: no data layer between a *definition* and a *placed instance*.** Exactly one level (`Level.tscn`@1509), hardcoded as a child of a scriptless `game.tscn`, with no `scenes/levels/` and no loader. The flagship "shoot crate → loot" must be reassembled per crate because `cube.tscn` omits `SpawnOnDestroy`.

## Prioritized initiatives

### #1 — Extract an `NpcData` Resource (+ `BarkSet` sub-resource); drive `enemy.tscn` from one profile slot · **effort L / impact HIGH** · pipeline + data + SRP
THE keystone. `npc.gd`@2027 carries ~55 `@export`s across 6 groups + 10 bark arrays, and the only way to author an NPC is instancing `enemy.tscn` and overriding inspector fields (Level.tscn's "Psycho Sniper" has ~30 overrides mostly zeroing defaults; the two "Kyle" enemies share nothing but the scene file). The empty `resources/characters/` dir proves this was the intended design.

First steps:
- `scripts/npc/npc_data.gd` (`class_name NpcData extends Resource`) bundling the ~55 tuning fields by `@export_group` + `max_hp` + `weapon_data` (`WeaponData`) + `faction` (`Faction`).
- `scripts/npc/bark_set.gd` (`class_name BarkSet extends Resource`), one `Array[String]` per category; move the 10 const arrays onto it; `NpcData.bark_set` with a default fallback.
- Add `@export var profile: NpcData` to `npc.gd`; in `_ready` apply it as **defaults before** per-instance exports override (existing scenes keep working).
- Author `raider.tres` / `townsperson.tres` / `shopkeeper.tres` / `stationary_sniper.tres` from values currently inlined on Level.tscn; re-point a couple of instances to prove the collapse.

Risk: largest single change. Mitigate by making **instance exports always win** over the profile (additive), keeping every scene valid, landing behind the off-tree test pattern, and testing a `BarkSet` array round-trip save/load (Godot-4 typed-array `.tres` quirk, already documented in `item.gd`).

### #2 — Quick data-extraction sweep · **effort S / impact MEDIUM** · data + pipeline
Five small, independent, zero-architecture wins that remove documented foot-guns and land **before** the keystone to de-risk the data layer (see Quick Wins).

### #3 — Introduce a `LootTable` Resource; route NPC/crate/container drops through it · **effort M / impact HIGH** · data + pipeline
There is *no* loot-table anywhere today — an NPC can only drop its weapon + fixed ammo; `CanPickUp`/`SpawnOnDestroy` are single fixed item/scene with no chance or quantity. An RPG can't ship without "this raider carries a keycard / rare 10% drop." Reuses the `Item`/`ItemDb` backbone and slots onto `NpcData.loot`.

First steps: `scripts/items/loot_table.gd` (`Array of {item, weight, min, max, chance}` + a pure `roll(rng)` resolving through `ItemDb`); add `loot` to `NpcData`; let `CanPickUp`/`SpawnOnDestroy`/`ItemContainer` optionally take one. Keep "drops what it carries" — loot is **additive**.

### #4 — Add a level-loading seam: `GameRoot` on `game.tscn` + `LevelData`/catalog + `scenes/levels/` · **effort M / impact HIGH** · pipeline + data
There is literally no way to ship a second level: `game.tscn` is scriptless and hardcodes the single `Level` child; `start_menu.gd` hardcodes `res://scenes/game.tscn`; death = `reload_current_scene`. A second map today means duplicating a 1509-line `.tscn`. Doesn't require streaming — just decouple "which level" from a hardcoded instance.

First steps: `GameRoot` script taking `@export var level: PackedScene` (or a `LevelData` resource with scene + spawn points + ambience/music); move `Level.tscn` into `scenes/levels/`; a tiny `LevelManager` to `change_scene` via the catalog. Stretch (after #1): a `SpawnPoint` marker + `EncounterData` ("spawn N of `NpcData` X"). **Preserve the Ambience/Music wiring under Player and the death→reload flow.**

### #5 — Composite prefabs (`LootCrate`/`Chest`/`AmmoPickup`) + `LookAtInteractable` base + `@tool` auto-fit colliders · **effort M / impact HIGH** · pipeline + SRP + data
`cube.tscn` omits `SpawnOnDestroy` so "shoot crate → loot" is reassembled every time; the 6 world scripts duplicate ~35 lines of talk-handler boilerplate with no base; world component scenes ship a placeholder 1m `SphereShape3D` needing hand-sizing — yet `Throwable.gd._autofit_collision_shape()`@88 already proves the fix (it's the only `@tool` script).

First steps: extract `scripts/world/look_at_interactable.gd` (`extends Area3D`) for the shared `TALK_LAYER` setup + 5 talk-handler methods; reparent the 4 components onto it; make it `@tool` + reuse the auto-fit; author `loot_crate.tscn`/`chest.tscn`/`ammo_pickup.tscn`. **Preserve the exact talk-handler signatures `PickupRay` duck-types against.**

### #6 — Finish `npc.gd`: extract `NpcVoice` / `NpcLocomotion` / `NpcTargeting` · **effort L / impact MEDIUM** · SRP + data
After #1 removes the config bulk, the behaviour splits cleanly via the proven idiom: the ~350-line bark/social system (`:744-1127`, self-contained, routes only to `SpeechTts`) → `NpcVoice` (reads the `BarkSet` off the profile); locomotion+anti-stuck (`~1438-1628`) → `NpcLocomotion`; target acquisition (`~1630-1761`) → `NpcTargeting`. Root stays the coordinator.

Sequence: `NpcVoice` first (most isolated); `NpcLocomotion` last (touches nav, most behaviour-sensitive — A/B the movement feel).

### #7 — Lift a shared `DamageApplier`; split `attack.gd` into `ShotPolicy` + `DamageTrace` · **effort L / impact MEDIUM** · SRP
`attack.gd`@530's own header falsely calls it "a thin coordinator"; `_on_mouse_input_attack` fuses six responsibilities in ~240 lines, and damage *application* is copy-pasted with `projectile.gd`. `ShotResolver` already proves the stateless-static home.

Sequence: extract `DamageApplier` **first** (pure dedup, behaviour-identical, easy to verify), then split the policy/trace. Combat feel is player-sensitive — lean on tests; add a hit-result golden test.

## Recommended sequence — four waves

Each wave makes the next cheaper.

- **Wave 0 — immediate, parallel (~days):** the #2 data sweep + the `@tool` auto-fit colliders + the `LookAtInteractable` base (#5b/5c). Touch nothing structural; fix documented foot-guns; prove the data layer extends cleanly.
- **Wave 1 — the keystone:** land `NpcData` + `BarkSet` (#1). The gate — must precede loot, levels, and the NPC SRP split.
- **Wave 2 — compound on the keystone (together):** `LootTable` (#3, plugs into `NpcData.loot`) + the level-loading seam (#4) + the composite prefabs (#5a). **At the end of Wave 2 the content goals are met** — a designer authors a level via a catalog, drops in drag-and-drop loot prefabs, and spawns NPCs by assigning one profile.
- **Wave 3 — SRP cleanup (no longer urgent for content):** finish `npc.gd` (#6: `NpcVoice` → `NpcTargeting` → `NpcLocomotion`), then the combat slice (#7: `DamageApplier` first, then the split).

## Quick wins (do immediately — Wave 0)

- **`ItemDb` folder scan:** replace the two hardcoded const path arrays with a `DirAccess` scan of `resources/items/` at boot — new item `.tres` auto-register instead of silently failing. Self-contained.
- **`is_infinite_ammo` flag:** add `@export var is_infinite_ammo: bool` to `WeaponData`, set on `melee.tres`, check it in `ammo.gd` instead of the `INT_MIN` two's-complement overflow sentinel (its own TODO asks for this). Removes a latent overflow bug.
- **`use_hitscan`:** wire it into `attack.gd`/`projectile_spawner.gd` **or delete it + its test** — authored, documented, unit-tested, but read by *zero* runtime code (`weapon_data.gd:11`). Textbook data-drift that misleads weapon authors.
- **`@tool` auto-fit colliders:** add `@tool` + reuse `Throwable.gd._autofit_collision_shape()` on the world interactable components so colliders fit the host AABB in-editor, replacing the placeholder 1m sphere.
- **`LookAtInteractable` base:** extract the ~35 duplicated `_ready`+talk-handler lines shared by `container`/`can_pick_up`/`merchant`/`lootable_corpse`. No behaviour change; removes copy-paste drift; gives the auto-fit one home.
- **`Loadout.tres`:** move the player's hardcoded `swap_weapons.gd` loadout (a `preload()` array mixing `res://` and bare `uid://`) + `START_CLIPS_PER_CALIBER=4` + `money=100` into one resource — lets you set difficulty/scenario kits without code.
