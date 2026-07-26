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
effects, clock, respawn transform, current level identity, lightweight
discovered `Corpse` markers, and the set of **learned NPC names**
(`GameState.known_names`, in `[world].known_names`) that drives the
"Stranger until introduced" masking.

**Stranger-until-introduced naming.** Every NPC's `display_name` is shown to the
player as `PlayerText.STRANGER` until a `DialogueLine` with `reveals_name = true`
plays and calls `GameState.reveal_name`, after which `known_names` carries the real
name across saves (wiped on New Game). The single display seam is
`GameState.public_name(real_name)` — the dialogue speaker label, look-at readout
(`Talkable.look_name`), corpse loot header, death card, takedown prompt, and cripple
toast all route through it; identity/quest matching (`notify_kill` / `notify_talk`)
keeps the true name, so masking is display-only and never breaks an objective.

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

**All loot cash is a coin tile now — there is no "Take N zm" button anywhere.** A dead
NPC's / crate's wallet is seeded as a real `zorkmids` coin tile in the loot bag
(`LootableCorpse.setup`, `ItemContainer._seed_money_coins` — a fixed 1×1, so it always
places), taken by clicking it (`LootScreen._take` converts the stack to real `add_money`,
never a loose backpack stack) and deposited as a tile (`_deposit_coins_to_source`). NPCs
themselves keep an abstract `money` float (no `MoneyPurse`), so a **live pickpocket**
target's wallet is FROZEN into a coin tile in its pockets on open (`_freeze_live_wallet`)
and THAWED back into that float on close (`_refloat_live_wallet`, folding in any un-taken
or planted coins) — so it loots as a clickable tile while you're in its pockets but stores
as a plain float between robberies (it still drops as loot on death, funds its shopping). A
grid-full pocket may freeze only part; the un-fit remainder stays on the float and thaws
back untouched. `LootScreen` wallet modes are now just `TILE` (every cash source) and
`NONE` (gear exchange — a cash deposit is refused, since gifting a friend's wallet isn't
"exchanging"). Corpses/containers aren't saved, so their coin tiles re-seed from the
authored/earned `money` on the next spawn. The `CharacterInventory.is_mirrored(item)` guard
still protects `LootScreen._take`: taking a non-mirrored coin tile must never also debit a
`money` float on the source — `is_mirrored` is true only on the player's own MoneyPurse
mirror (never a loot source), so a loot take can never destroy cash by double-debiting.

**Player abilities are microchip upgrades.** Each unlockable mechanic (wall-climb,
grapple, slide, air-dash, laser-sight, fall-immunity, board-visualizer, and the
**silent takedown** stealth kill) is a drag-drop `Ability` node
whose presence grants it; a fresh game now starts with **none** (`Player.tscn`
`starting_unlocks` is empty). The player earns each by finding/buying a **chip Item**
(`Item.installs_ability`, `resources/items/chip_*.tres`, all sharing the `microchip.glb`
look) and paying a `ChipInstaller` mechanic (`scripts/components/chip_installer.gd` →
`ChipInstallScreen`) to install it — the installer consumes the chip, charges through
`add_money`, and calls `player.unlock_mechanic`, which persists in `GameState.unlocks`
(re-applied via `set_unlocks` on load). The instant-grant `UpgradePickup` remains for
special "online immediately" pickups.

The grant/revoke/persistence plumbing behind those calls lives in a **Player-owned
`AbilityManager`** (`scripts/components/abilities/ability_manager.gd`, a `RefCounted`
built at the Player's var-init and wired in `Player._init`), not inside `player.gd`. The
Player exposes thin forwarders (`has_mechanic`, `unlock_mechanic`, `grant_ability`,
`revoke_ability`, `can_grant_mechanic`, `unlocked_list`, `set_unlocks`) that every caller
duck-types, and keeps only the three typed hot-path refs (`_wall_climb` / `_slide` /
`_grapple_ability`) its physics step drives each frame — those stay on the Player because
the movement feel depends on their exact call order. A runtime grant is rebuilt from the
id by the shared `AbilityRegistry` snake_case naming convention (scene ↔ `ability_id()` ↔
script), so there is no hand-maintained id→script table.

The autosave is written **atomically**: `save_to_disk` writes a sibling `.tmp`,
rotates the previous good file to `.bak`, then renames the temp over the target,
so a crash mid-write can no longer corrupt the one-slot save. `load_from_disk`
falls back to `.tmp` (the interrupted newest write) then `.bak` when the primary
is unreadable. Every save stamps `[meta].version` (`SAVE_VERSION`, now **3**) —
read into `save_version`. Two version-gated migrations exist, each a separate
branch so an ancient save runs both in one load. **v2** (2026-07-09) renamed the
`persuasion` stat to `streetwise`, folding a pre-v2 save's `persuasion` points
into `streetwise`. **v3** (2026-07-16) consolidated the `stealth` and `pickpocket`
stats into one `larceny` stat, folding a pre-v3 save's `stealth` **and**
`pickpocket` points into `larceny`. (The stat-load loop only reads the current
stat names, so without each migration those points would silently vanish.)
Re-saving stamps the current version and each migration never re-runs.

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
"exact quicksave."

Those omissions describe the PROFILE ledger. A separate **exact-snapshot tier**
already ships on top of it, riding the **manual quicksave/slot** layer ONLY (the
lean Dark-Souls autosave / Continue never carries one). It is a `WorldSnapshot`
(`scripts/world/world_snapshot.gd`) built in `GameState._capture_and_write` and
written as a sibling `[world_snapshot]` cfg section with its OWN `SNAPSHOT_VERSION`
(**1**), decoupled from `SAVE_VERSION` — a snapshot the running code doesn't
understand is ignored while the profile still loads. **Phase 1** captures, for the
level you saved in, which AUTHORED NPCs are alive plus their position/yaw/hp, and
folds every visited level's authored-NPC death ledger (`GameState._dead_authored`)
so cross-level kills stay dead on reload. On a manual quickload
`GameRoot.load_level` applies it via `GameState.consume_world_snapshot()` (a
one-shot, so Continue or a death-respawn reload never re-applies it). Later phases
grow the same `capture()` / `apply()` entry points with containers, corpses, loot
drops, and dynamic (encounter-spawner) NPCs. Further exact-snapshot work extends
THIS tier, not the profile-save language.

## Content Data

Repeated content should live in Resources:

- `LevelData` for level scene, display name, music, and ambience.
- `NpcData` for reusable NPC archetypes.
- `BarkSet` and `GoapProfile` for NPC voice and decision tuning.
- `WeaponData` and `Item` for equipment and inventory.
- `LootTable` and `ItemStack` for random and fixed loot.
- `ActionCatalog` and `SettingsCatalog` for player-facing controls/options.
- `BootQuotes` and `TermsOfService` for the boot intro quote and the first-launch
  Terms-of-Service gate (both under `resources/ui/`; both degrade to a baked-in
  fallback so the menu boots even with the `.tres` missing).

Use folder scans and catalogs where possible so adding a `.tres` does not require
editing a hardcoded path list.

The **startup warning gate** is a boot-flow contract worth noting: `start_menu.gd`
queues `INTERNET_WARNING_CARDS` every normal project launch before the TOS, the
computer-room intro, or the menu. In the hosted `computerroom.tscn` path, the menu is
made visible immediately as the black warning card, while the room timer/audio stay
stopped until the menu emits `startup_gate_finished`. Both the room intro and menu
reveal arm short input shields so the click/key that skipped the warning cannot also
power the monitor or activate a menu button.

The **first-launch consent gate** follows that warning: `start_menu.gd` shows the
`TermsOfService` overlay (`scripts/ui/terms_of_service_screen.gd`) whenever
`Settings.tos_accepted` is false, and records consent via `Settings.accept_tos()`. That
flag lives in `user://settings.cfg` (per-install, survives New Game) — deliberately NOT
in the `gamestate.cfg` profile (wiped on New Game) and deliberately NOT a `SettingSpec`
row (it is a one-time gate, not a tunable). So the TOS shows exactly once per install.

## Components

`scripts/components/` is for nodes a designer can drag into a scene. The common
interaction base is `LookAtInteractable` (`extends Area3D`), which supplies the
talk-layer hitbox and look-at outline contract, and a duck-typed talk-handler
surface — `look_name()` / `start_talk()` / `can_be_talked_to()` / `host_npc()` —
that the player's interaction ray (`PickupRay`) calls by name, so a new subclass
needs zero ray changes. Nineteen scripts extend it (plus `DogPickup`, which
extends `CanPickUp`, so the tree is three levels deep): pickups (`CanPickUp`,
`MoneyPickUp`, `UpgradePickup`), loot/trade screens (`ItemContainer`,
`LootableCorpse`, `Merchant`), service stations (`Healer`, `Bonfire`, `LevelUp`,
`PerkStation`, `RespecStation`, `ChipInstaller`, `ChessMatch`), and world objects
(`Door`, `LevelDoor`, `Radio`, `Readable`, `Switch`, `QuestStarter`). The full
inheritance tree, base contract, and "add a new interactable" recipe live in
[`scripts/components/README.md`](../scripts/components/README.md#the-lookatinteractable-hierarchy);
per-component `@export` knobs are in `docs/AUTHORING_GUIDE.md`. Note `Corpse`
(`scripts/npc/corpse.gd`, `extends Node3D`) is a separate AI discovery marker,
NOT this loot interactable — the lootable body is `LootableCorpse`.

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
`spawn_at` is the shared point-spawn idiom (instantiate → position → emit → auto-free) and
the one place a future global "effects off" / pooling hook belongs; `spawn_blood_particle`
and `Throwable._spawn_destroy_particle` route through it. The richer effects (explosions,
oriented decals, host-driven gibs) carry per-instance config a point-spawn can't and preload
their own scene by UID — so restyle one by editing its `.tscn`, not by repointing a factory slot.

**Global `SceneTree.node_added` listeners — keep the count tight.** Two subsystems
connect to the tree-wide `node_added` signal: `star_sky` (sky FX when a `WorldEnvironment`
enters) and `menu_style` (button SFX for `BaseButton`s under menu roots). Both early-out
cheaply on a non-matching node. Because the signal fires for EVERY node entering the tree,
each listener taxes all instantiation project-wide — don't add a third without first weighing
a scoped signal or a deferred init. (`ps1_warp` used to be a third listener; it now uses a
scoped hook — `GameRoot` owns the level-load seam and calls `Ps1Warp.cover()` from
`load_level`, so the PS1 warp is applied exactly on level load and costs zero per-node tax.)
`tests/test_global_node_added_listeners.gd` fails if the count drifts from two.

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

### Going home (the leash) — `NpcHomeReturn`

`scripts/npc/npc_home_return.gd` is a drop-in every NPC auto-builds (seeded from
`GameSettings.npc_ai`, group *Home return (leash)*; a configured instance placed
under the NPC wins). It returns an NPC to its authored post — `_spawn_position` /
`_spawn_yaw`, the same anchor wander/return-to-post re-centre on — on two cues:

- **`GameState.player_died`**, emitted from
  `Player._on_death_screen_covered()` — a tween callback on the death
  cinematic's **fully black frame**, right before the "You were killed by X"
  card fades in. The timing is the contract, not an implementation detail:
  listeners rearrange the world, so firing at `die()` time (≈1.6 s earlier, mid
  vignette-close) lets the player watch the cast teleport away. A world-reset
  CUE, not save state: the default `CHECKPOINT_RESPAWN` death mode revives the
  player in an untouched world, so without it an encounter never resets. It
  composes with the killer-aware `Character._on_killed_by` hook
  (`HostilityHelpers.settle_provoked_grudges`), which runs *earlier* in the same
  death and settles provoked **hostility** — positions here, grudges there.
- **an off-screen timer** (`off_screen_delay`), gated by default on the NPC
  being calm (perception `UNAWARE`, no target) so the clock doesn't run
  mid-firefight.

An NPC with **aggro** — `_engaged()`: perception past `UNAWARE`, *or* holding a
live target (`NpcTargeting` acquires by pure proximity, so a hostile locks the
player before perception notices them) — is never teleported by the off-screen
trigger. That refusal lives in `_may_blink()` and is deliberately **not** behind
`off_screen_requires_calm`, which only paces the clock: opening the leash up for
a hard-leash level still can't make an enemy evaporate when the player breaks
line of sight, it only stands it down and walks it back. A blink additionally
requires `min_blink_distance` of separation. Only the player-death reset (on the
black frame) passes both.

The return mechanism is `CompanionFollow`'s hidden blink pointed at the spawn
spot instead of at the player, and it inherits that component's hard rule: never
teleport a body the player can see (wide dot-cone + an optional occlusion ray).
A refused blink still calls the new **`NPC.stand_down()`** write seam (target +
attacker lock cleared, `Perception.forget()`, laser hidden), so the GOAP Idle
floor's existing return-to-post walks the NPC home on foot. `stand_down()`
deliberately leaves `_provoked` / `_npc_grudges` / faction standing alone —
standing down is not forgiveness. Companions, `GuardDuty` bodyguards,
cutscene-driven and mid-talk NPCs are exempt.

### NPC pooling (optional reuse of encounter enemies)

`NpcPool` (`scripts/components/npc_pool.gd`) is an **opt-in** drop-in that lets an
`EncounterSpawner` (its `pool` NodePath) **reuse** NPC bodies instead of
instancing per spawn / freeing on death. A fixed fleet is built + fully
`_ready()`'d at load, then handed out on spawn and **parked out-of-tree** on
death for reuse — eliminating the per-spawn `_ready` hitch and keeping the body
count flat. Bodies bucket by **loadout** (`npc_scene` + `profile` +
`faction_override` + `weapon_override`), so reuse never re-stamps a profile or
re-swaps a mesh; a bucket-miss instances + adopts a fresh body (the pool grows,
never fails a spawn).

The contract that makes reuse correct:

- **`die()` is the single seam.** `NPC.die()` still `emit`s `died` (so the full
  death payload — loot corpse, XP, faction rep, witness barks, the spawner's
  clear-gate de-track — runs unchanged), then, when pooled, calls
  `_pool.reclaim(self)` instead of `queue_free()`. Non-pooled NPCs free exactly
  as before.
- **`reset_for_reuse()` is the reset surface, owned per component.**
  `Character.reset_for_reuse()` (vitals/`_dead`/limbs/blast/flash/status/
  process/visible) → `NPC.reset_for_reuse()` (targeting, provoke, combat + bark
  latches, cutscene, nav intents, `_fire_timer` re-seeded to `_shot_interval()`,
  the panicked `threat_response` put back from `_pre_panic_threat_response`,
  wallet baseline, backpack **clear + re-seed authored loadout**) → each
  stateful child's own `reset_for_reuse()` (`Perception`, `Locomotor`,
  `NpcLocomotion`, `GoapExecutor`, `NpcCombat`, `WeaponStance`, `NpcOutline`,
  `NpcLaser`, `NpcHomeReturn`, `Ammo`, `CharacterInventory.clear()`). Components own their reset
  (no central hand-list) to avoid list drift. It **never** re-runs
  `_apply_stats` / `_build_*` (that would double-stamp strength into `max_hp` and
  duplicate child nodes).
- **Death-freeze is skipped for pooled NPCs** (`death_freezes()` gates on
  `_pool == null`): the freeze-in-place beat disables processing + `ALWAYS`
  descendants irreversibly and arms a timer that would re-fire death on the
  reused body.
- **Save tier:** pooled bodies are dynamic spawns — excluded from the exact-save
  ledger (`_record_snapshot_death` no-ops when pooled), consistent with the
  existing "encounter NPCs don't persist" rule below.

Verified by `tests_soak/test_npc_pool_reuse.gd` (real `_ready` + death + reuse)
and `tests/test_npc_pool.gd` (the pure reset surface).

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
- `docs/SYSTEM_MAP.md` is a GENERATED index (system → seam / risk / contract-test)
  built from `## @system / @seam / @risk / @test` annotation blocks at the code
  seams; never hand-edit it — change the annotation and run
  `scripts/tools/gen_arch_doc.gd`.
- `docs/AUTHORING_GUIDE.md` is the designer-facing field and workflow manual.
- `docs/CYBER_SUNDAY_PLUGIN_QA.md` is the acceptance checklist for editor-plugin
  changes.
- Subsystem READMEs hold local invariants that must be read before editing that
  subsystem.
- `CLAUDE.md` holds agent behavior rules, test etiquette, and repo conventions.

The System Map keeps a seam's one-line contract + risk AT the code so they can't
drift from it: `tests/test_arch_doc_sync.gd` re-renders the map from the current
annotations and fails if `docs/SYSTEM_MAP.md` is stale (the same check runs
headless as `gen_arch_doc.gd -- --check`). This file stays the home for the
connective narrative the annotations can only point at.

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
