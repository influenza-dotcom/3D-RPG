# Current Architecture

This is the living architecture entry point. Keep it current with the code; if a
seam changes, update this file in the same change.

## Core Shape

The project is an editor-authored FPS/RPG prototype. Gameplay should usually be
expressed as one of three surfaces:

- a drop-in component with `class_name` and `@export` fields,
- an authored Resource (`NpcData`, `WeaponData`, `LootTable`, `LevelData`, etc.),
- or a global tuning resource under `resources/tuning/` exposed through
  `GameSettings`.

That rule matters more than file organization. The designer should be able to
build content in the Godot editor without adding code branches.

## Run And Level Flow

`scenes/game.tscn` is the run wrapper. It owns the Player and a `GameRoot`.
`GameRoot` loads a `LevelData` resource, instances its scene as the runtime
`Level` child, applies optional music/ambience overrides, and places the Player
at a `PlayerSpawn`.

Runtime level travel uses `LevelDoor`, which calls `GameRoot.load_level()` with
a target `LevelData` and destination `entry_id`. `GameState` records the current
`LevelData.resource_path`, so Continue/quickload can restore the level identity
before the saved player transform is applied. **Door-to-door travel is dormant by
design** — no `LevelDoor` is placed in a shipping level yet; the LIVE level-flow seam
is the `GameRoot` boot + `PlayerSpawn` placement above (`load_level` is also reachable
from a `TriggerVolume`/cutscene). The `LevelDoor` prefab wiring is pinned by
`tests/test_level_door_prefab.gd` so the dormant path can't silently rot.

The level scene itself does not contain the Player. Play levels through
`game.tscn` unless you are intentionally inspecting a bare level.

## Save Model

`GameState` is a profile/checkpoint save, not a full world snapshot. It persists
player progression, stats, inventory, equipped item, money, reputation, story
flags, quests, perks, ability unlocks (installed microchip upgrades), XP, status
effects, clock, respawn transform, current level identity, and lightweight
discovered `Corpse` markers.

Dota-style **passive item buffs** (`PassiveItemBuffs`, built on every `Character`) are
deliberately **NOT** serialized: any carried Item's `held_passive_effect` grants its
`stat_modifiers` / `speed_multiplier` while held, and since the inventory is already
saved the buffs re-derive themselves on load (the pool recomputes as each stack
restores). `max_hp`/`carry_capacity` aren't stored as numbers either — they re-derive
from the stat sheet at spawn and the held delta is re-added on top — so a `+HP` trinket
cannot double-count across a save. The buff folds through the same
`Character.status_stat_modifier` / `status_move_multiplier` seams as timed
`StatusEffect`s (both are summed/multiplied together); `strength` is the
one channel it re-stamps directly onto `max_hp`/`carry_capacity` (a held `strength`
buff also re-stamps both; strength's melee-damage component, like the other live stats,
folds through the multiplier seams instead). That `strength`→`max_hp`/`carry_capacity`
re-stamp (plus the `endurance`→stamina re-seed) runs through **one**
`CharacterStats.restamp_derived` chokepoint shared by `LevelUp`, `PerkManager`, and
`PassiveItemBuffs`, so their clamp/floor/heal-on-gain/HUD-refresh semantics can't drift
apart (a level-up, a perk, and a carried trinket all move HP/carry identically).

The player's **zorkmids show up as a real coin Item** in the backpack, but the wallet
itself stays the authoritative fractional `Character.money` float (what the whole
economy — merchants, pickups, bounties, death transfer — reads). `MoneyPurse`
(`scripts/inventory/money_purse.gd`, built on the Player) mirrors that float into a
single `zorkmids` stack (one unit = one `Zorkmids.QUANTUM`, so the integer stack stays
fractional), self-healing against any external bag change. That coin stack is therefore
**excluded from the save** (`GameState.capture` skips `Zorkmids.ITEM_ID`): `money`
already persists as the `[player]` wallet float, and the purse rebuilds the stack from it
on load — so, like the passive buffs above, the mirror can't double-count across a save.
`MoneyPurse._ready` also calls `CharacterInventory.register_mirror(Zorkmids.ITEM_ID)` on the
player's backpack, so `CharacterInventory.is_mirrored(item)` is the single predicate — true
only on the player — for "this coin tile is a wallet VIEW, not real cash." And because the
purse listens to `inventory.changed`, `CharacterInventory.transfer_to` now **coalesces its
own `changed` across the remove + rollback** and checks `add()`'s return (restoring any
un-refit remainder via `restore_stack`), emitting once at the end: a mirror listener can
never fire on the intermediate post-remove state and grab the freed cells before a bounced
loot stack is rolled back (which would leave the loot unplaced/lost).

**Loot cash is a coin tile too, not a "Take N zm" button.** A dead NPC's / crate's
wallet is seeded as a real `zorkmids` coin tile in the loot bag (`LootableCorpse.setup`,
`ItemContainer._seed_money_coins` — a fixed 1×1, so it always places), taken by clicking
it (`LootScreen._take` converts the stack to real `add_money`, never a loose backpack
stack) and deposited as a tile (`_deposit_coins_to_source`). NPCs themselves keep an
abstract `money` float (no `MoneyPurse` — a bounded NPC bag can't safely hold a mirrored
pile), so the money button survives in exactly one place: **pickpocketing a live NPC**,
whose wallet is a `FLOAT`-mode source (`LootScreen` wallet modes: `TILE` static loot /
`FLOAT` live pocket / `NONE` gear exchange). Corpses/containers aren't saved, so their
coin tiles re-seed from the authored/earned `money` on the next spawn. A loot source's
coin tile is **real loot**: its separate `money` float is distinct pocket cash (taken via
the `FLOAT` "Take N zm" button), so `LootScreen._take` only mirror-debits that float when
`CharacterInventory.is_mirrored(item)` is true — which it never is for a corpse, container,
or live-pickpocket NPC (none has a purse). Debiting it there would destroy the cash (player
gets the tile, the source loses tile AND float); the guard makes that impossible.

**Player abilities are microchip upgrades.** Each unlockable mechanic (wall-climb,
grapple, slide, air-dash, laser-sight, fall-immunity) is a drag-drop `Ability` node
whose presence grants it; a fresh game now starts with **none** (`Player.tscn`
`starting_unlocks` is empty). The player earns each by finding/buying a **chip Item**
(`Item.installs_ability`, `resources/items/chip_*.tres`, all sharing the `microchip.glb`
look) and paying a `ChipInstaller` mechanic (`scripts/components/chip_installer.gd` →
`ChipInstallScreen`) to install it — the installer consumes the chip, charges through
`add_money`, and calls `player.unlock_mechanic`, which persists in `GameState.unlocks`
(re-applied via `set_unlocks` on load). The instant-grant `UpgradePickup` remains for
special "online immediately" pickups.

The autosave is written **atomically**: `save_to_disk` writes a sibling `.tmp`,
rotates the previous good file to `.bak`, then renames the temp over the target,
so a crash mid-write can no longer corrupt the one-slot save. `load_from_disk`
falls back to `.tmp` (the interrupted newest write) then `.bak` when the primary
is unreadable. Every save stamps `[meta].version` (`SAVE_VERSION`, now **2**) —
read into `save_version`. v2 added the first version-gated migration: the
2026-07-09 stat overhaul renamed the `persuasion` stat to `streetwise`, so a
pre-v2 save's `persuasion` points are folded into `streetwise` on load (the
stat-load loop only reads the current stat names, so without the migration those
points would silently vanish). Re-saving stamps v2 and the migration never re-runs.

Level-identity restore is guarded (`respawn_level_matches`): on boot, if a loaded
game's saved `current_level_path` can't be resolved to a scene-bearing `LevelData`
(its `.tres` was deleted/renamed), `GameRoot` boots the exported level and sets
`respawn_level_matches = false`. The Player then skips restoring the saved respawn
(it belongs to the missing level) and `GameRoot` places/re-seeds it in the booted
level — even when that level has no `PlayerSpawn` — so a mismatched boot never
teleports the first death into the level that no longer loads. A blank saved path
(a legacy/pre-`[level]` save) is not a mismatch and keeps its restored respawn.

It now persists an ADDITIVE per-object ledger (`GameState.world_objects`, keyed by
level + `WorldSaveId.key_for`): a `Door`'s open/locked state, and a consumed
`CanPickUp` / `MoneyPickUp` / `UpgradePickup` / destroyed `CanDestroy` prop's "gone"
bit — set an authored `save_id` on hand-placed objects that must survive layout
edits (else a level/path/position fallback is used). Code-spawned pickups (a
dropped money bag's reclaim child) set `persist_collected = false` to stay out of
the ledger — a dynamic spawn has no stable identity. It still does NOT persist looted/refilled containers, killed
NPCs, dynamically-spawned entities (loot drops / encounter NPCs), or NPC
positions, and it is NOT an exact snapshot — only touched, authored objects are in
the ledger. This ledger is additive: it does not rebrand the profile save as an
"exact quicksave." Any future exact-snapshot must extend that identity layer, not
stretch the profile-save language.

## Content Data

Repeated content should live in Resources:

- `LevelData` for level scene, display name, music, and ambience.
- `NpcData` for reusable NPC archetypes.
- `BarkSet` and `GoapProfile` for NPC voice and decision tuning.
- `WeaponData` and `Item` for equipment and inventory.
- `LootTable` and `ItemStack` for random and fixed loot.
- `ActionCatalog` and `SettingsCatalog` for player-facing controls/options.

Use folder scans and catalogs where possible so adding a `.tres` does not require
editing a hardcoded path list.

## Components

`scripts/components/` is for nodes a designer can drag into a scene. The common
interaction base is `LookAtInteractable`, which supplies the talk-layer hitbox
and look-at outline contract. Subclasses include pickups, money, merchants,
healers, chip installers (the upgrade mechanic), containers, lootable corpses,
doors, radios, bonfires, upgrade pickups, and other interactable world objects.

Standalone drop-ins such as `Lock`, `CanDestroy`, `SpawnOnDestroy`,
`TriggerVolume`, `EncounterSpawner`, `NoiseSource`, and `ScheduleBehavior` add
behavior through exported fields instead of bespoke scene code.

**Cinematic damage immunity.** `InputManager.world_frozen()` (cutscene playing OR a
conversation engaged, via `CutscenePlayer.is_active()` / `DialogueManager.is_engaged()`)
is the single control-lock predicate for damage immunity. `Player.take_damage` returns
early when it is true, so a control-locked player takes NO hazard/DoT/NPC-fire damage —
a cutscene never pauses the tree (staged actors keep moving) so immunity rides the
predicate, and the predicate also covers the ~0.5s unpaused dialogue-intro beat. The
ambient damage sources gate on the same predicate so durations don't burn: `HazardZone`
stops ticking (no catch-up burst afterward) and `StatusEffectManager` pauses both DoT
damage and the duration countdown, resuming effects intact after the freeze. This is
DISTINCT from `gameplay_suppressed()`, which also counts the real-time Pip-Boy/loot/shop
overlays that keep the player at risk and must NOT grant immunity. A cutscene that wants
to script player damage must use a dedicated kill path, not incidental `take_damage`.

**Dialogue-suspend contract.** A dialogue option that opens a sub-menu (Trade/Install/Chess)
routes through `DialogueManager._suspend_for_menu`, which hides the box and connects the
sub-menu's `closed` as a `CONNECT_ONE_SHOT` resume BEFORE calling the open. So every one of
those screens (`ShopScreen`/`ChipInstallScreen`/`ChessScreen`) MUST emit `closed` on EVERY
refuse path — each funnels its guard early-returns through a private `_refuse_open()` that just
`closed.emit()`s. A refuse that returns silently would strand the conversation `_suspended`
forever (box hidden, tree paused, no way to advance). On the standalone open path nothing
listens to `closed`, so the emit is a harmless no-op there.

## Effect And Audio Seams

`AudioManager` (autoload) is the one-shot SFX seam: `play_sfx` / `play_2d_sfx`
route through the `sfx` bus so the audio-options sliders apply, and `play_applause`
is the single shared reward cheer. Player one-shot SFX now go through it.

`EffectFactory` (autoload) is **not** a VFX registry — it is only the blood-particle
gameplay seam (`spawn_blood_particle`) plus a generic `spawn_at(scene, pos)` helper.
Every other effect preloads its own scene by UID, so restyle an effect by editing its
`.tscn`, not by repointing a factory slot.

**Global `SceneTree.node_added` listeners — keep the count tight.** Three subsystems
connect to the tree-wide `node_added` signal: `star_sky` (sky FX when a `WorldEnvironment`
enters), `menu_style` (button SFX for `BaseButton`s under menu roots), and `ps1_warp` (the
Ps1Warp autoload, added 2026-07-08, parents the PS1 applier under each `LevelRoot` as it
enters). All early-out cheaply on a non-matching node. Because the signal fires for EVERY
node entering the tree, each listener taxes all instantiation project-wide — don't add a
fourth without first weighing a scoped signal or a deferred init. (Ps1Warp is arguably the
one that should have used a scoped hook — GameRoot could apply the warp on level load
instead — so treat three as the ceiling, not license to grow.)
`tests/test_global_node_added_listeners.gd` fails if the count drifts from three.

## NPC Brain

GOAP is the sole NPC decision layer. Read
`scripts/npc/goap/README.md` for planner invariants before adding goals/actions.

The high-level flow is:

- acquire/retarget,
- sense the environment,
- tick the `GoapExecutor`,
- delegate action bodies back to the NPC's existing combat/idle/locomotion
  methods where frame ordering matters.

The no-target branch is planner-owned too: the full no-target branch routes
through GOAP rather than a separate pre-seam path — see
`scripts/npc/goap/README.md` for the canonical behaviour/goal/action roster.

## Testing Strategy

Tests should match the risk:

- pure off-tree tests for math, planner logic, Resources, and save codecs,
- small in-tree harnesses where Godot transforms or groups are required,
- scene-instancing contract tests for prefab wiring and exported NodePaths,
- save/load tests that cover identity, not just scalar values.

Do not run the full GUT suite automatically; `CLAUDE.md` is the source of truth
for test-running etiquette.

### Menu/UI layout QA

The real UI canvas is **792x444** at 16:9 — the 396x216 base viewport is doubled by
`window/stretch/scale=0.5`, and `aspect="expand"` varies it with monitor shape
(height 432 minimum, 495 at 16:10, wider than 792 on ultrawide). Menu code must lay
out against that, never against 396x216. `scripts/ui/menu_style.gd` documents the same
fact at the code seam, and `MenuSkin` (`resources/ui/menu_skin.tres`) carries the shared
layout constants (`content_separation`, `dialog_button_min_width`, `tab_min_width`, …).

`scripts/tools/menu_qa_shots.tscn` is the menu screenshot harness: one windowed run
opens every menu screen (faking merchant/healer/corpse context off-tree like the GUT
tests do) and saves a PNG per screen —
`godot --path . res://scripts/tools/menu_qa_shots.tscn -- --shots-dir="<dir>"`.
Use it before/after any menu-layout change.

## Documentation Contract

Documentation is part of the architecture because future humans and AI agents
use it to choose the next change. Keep each doc focused:

- `README.md` is the project overview and common workflow index.
- `docs/CURRENT_ARCHITECTURE.md` is the live system map and contract list.
- `docs/AUTHORING_GUIDE.md` is the designer-facing field and workflow manual.
- `docs/CYBER_SUNDAY_PLUGIN_QA.md` is the acceptance checklist for editor-plugin
  changes.
- Subsystem READMEs hold local invariants that must be read before editing that
  subsystem.
- `CLAUDE.md` holds agent behavior rules, test etiquette, and repo conventions.

Any change to a Resource type, component, scene contract, plugin workflow,
setting, input action, save field, level-flow seam, or test policy should update
the matching doc in the same diff. Docs should describe current behavior,
current paths, and current field names.

## Current Design Risks

- Scene wiring can regress silently without contract tests.
- Profile saves and exact world snapshots are different products; avoid UI/docs
  that blur them.
- Persisted corpse discovery is the exception to general object-state reset:
  authored bodies should use `Corpse.save_id`; fallback path/position keys are
  only stable enough for unchanged hand-placed markers.
- Docs drift quickly when review notes are kept around. Prefer current risk
  lists and delete artifacts that no longer match the code.
