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
plays and calls `GameState.reveal_name`, after which `known_names` carries the
character across saves (wiped on New Game). The single display seam is
`GameState.public_name(real_name)` — the dialogue speaker label, look-at readout
(`Talkable.look_name`), corpse loot header, death card, takedown prompt, and cripple
toast all route through it; identity/quest matching (`notify_kill` / `notify_talk`)
keys on the stable identity (below), so masking is display-only and never breaks an
objective.

**Stable NPC identity (save v4).** Display names are no longer identity keys:
`NpcData.id` (optional `StringName`; blank falls back to the authored
`display_name`, so nothing existing changes key) feeds `NPC.identity_key()`, which
`notify_kill` / `notify_talk` / `reveal_name` key on — with the live display string
passed alongside as the legacy fallback so pre-identity quest `.tres` authored
against display names keep matching unedited. The key is latched in `NPC._ready`
(post-profile-stamp), so a runtime rename (a claimed pet's player-typed name via
`Claimable`) can no longer stall that NPC's KILL/TALK objectives, and two
characters may share one `display_name` without merging identities. `known_names`
now stores identity keys; the v3 → v4 migration is **lazy** (legacy name-string
entries stay readable via accept-either membership; unmatched ones degrade to
"not yet introduced" — see the load-site comment in `GameState.gd`), and
`reveal_name` also records the display string when it differs from the id (the
display-compat bridge for the string-keyed `public_name` surfaces).

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
"exchanging"). Corpses aren't saved, so their coin tiles re-seed from the
authored/earned `money` on the next spawn; a CONTAINER's coin tile is real loot and
DOES ride the exact-snapshot tier (`serialize_stacks` skips only a MIRRORED
player-wallet tile), so a quickload restores exactly the cash you left in the crate —
it re-seeds from `money` only on the profile/Continue tier. The `CharacterInventory.is_mirrored(item)` guard
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
is unreadable. Every save stamps `[meta].version` (`SAVE_VERSION`, now **4**) —
read into `save_version`. Three schema migrations exist. **v2** (2026-07-09)
renamed the `persuasion` stat to `streetwise`, folding a pre-v2 save's
`persuasion` points into `streetwise`. **v3** (2026-07-16) consolidated the
`stealth` and `pickpocket` stats into one `larceny` stat, folding a pre-v3 save's
`stealth` **and** `pickpocket` points into `larceny`. (The stat-load loop only
reads the current stat names, so without each migration those points would
silently vanish.) v2 and v3 are separate load-time branches, so an ancient save
runs both in one load; re-saving stamps the current version and neither re-runs.
**v4** (2026-07-26) re-keyed `[world].known_names` from display-name strings onto
stable identity keys and is deliberately **lazy** — no load-time fold at all
(legacy entries stay readable via accept-either matching; see *Stable NPC
identity* above, and the load-site comment in `GameState.gd` for why an eager
rewrite is impossible).

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
(**2**), decoupled from `SAVE_VERSION`. The snapshot shape has only ever grown
ADDITIVELY, so the load gate is RANGED (`SNAPSHOT_MIN_COMPAT`..`SNAPSHOT_VERSION`
— an older quicksave keeps its world state on update); a version outside the range
(a downgraded install) is ignored while the profile still loads. On a manual
quickload `GameRoot.load_level` applies it via
`GameState.consume_world_snapshot()` (a one-shot, so Continue or a death-respawn
reload never re-applies it).

The player-facing face of this manual tier is the **`SaveLoadScreen`** autoload
(`scripts/ui/save_load_screen.gd`), a non-pausing slot menu registered in the
`InputManager` modal registry: a load-only quicksave row (F5 owns writing it)
plus slots 1..`SLOT_COUNT`, each showing the saved level's authored
`LevelData.display_name` and the file's modified time. In-game it opens from the
Options menu's *Save / Load* button (Options closes first — modals never stack)
with Save (overwrite-confirmed on an occupied slot) and Load per slot; at the
start menu the *Load Game* button opens it load-only, booting the chosen file
through `load_from_disk` + the same boot path Continue uses. It lists ONLY the
quicksave/slot files — the lean autosave/Continue profile is deliberately not a
row there, keeping the two save products distinct.

**The exact-snapshot tier roadmap** (this section is the written design brief the
code comments point at — keep it current as phases land):

- **DONE — authored-NPC death + position** (v1): for the level you saved in, which
  AUTHORED NPCs are alive plus their position/yaw/hp, keyed by the POSITION-FREE
  `NPC.snapshot_key` (`save_id` else level|node_path).
- **DONE — cross-level deaths** (v1): `fold_dead_ledger` folds every visited
  level's authored-NPC death ledger (`GameState._dead_authored`) so cross-level
  kills stay dead on reload; `GameRoot.load_level` also suppresses the dead on
  EVERY load from the live ledger (door A→B→A needs no save).
- **DONE — container contents** (v2): every authored `ItemContainer`'s exact bag
  (stacks incl. its REAL coin tile + per-instance `weapon_delta`, the
  grid-bounded bit + cell layout, a `Lock` child's locked state), keyed by
  `ItemContainer.snapshot_key`. Restore REPLACES the fresh `_ready` seed via
  `restore_snapshot_contents` — a looted crate stays looted, a random
  `loot_table` never re-rolls, a stash survives, and child `Restocker`s are
  marked spent (`note_restored`) so quickload is never a free instant restock.
  Runtime-spawned containers (`@`-pathed, no `save_id`) are excluded like
  dynamic NPCs.
- **REMAINING — NPC backpacks** (a known consequence of shipping containers
  first): NPC bags are in NEITHER tier. `NpcScavenge` moves real items OUT of an
  `ItemContainer` into an NPC's bag, so if an NPC loots a crate and you then
  quicksave and quickload, the crate correctly restores to its save-time
  (emptied) contents while the NPC respawns with only its authored loadout — the
  scavenged item is gone. Before containers persisted, the crate re-seeded
  instead, which duplicated it. Neither is right; serializing NPC bags (the same
  `serialize_stacks` shape) is the fix, and it pairs naturally with the
  dynamic-spawn item below.
- **REMAINING — containers outside the saved level**: capture walks only the live
  level and `apply()` is a one-shot for the boot level, so a crate you looted in
  another level re-seeds from its authored exports on quickload. Lands with the
  multi-level live-position item below (both need per-level buckets retained
  across door swaps).
- **REMAINING — corpse rebuild**: a dead authored NPC currently just VANISHES on
  quickload (`WorldSnapshot.apply` silently frees the fresh spawn — no corpse, no
  loot). Rebuilding = capture runtime `LootableCorpse` state (position + bag via
  the same `serialize_stacks` shape) and re-instantiate on apply; must first WIPE
  root-parented gore/corpses (they deliberately survive `reload_current_scene`)
  or quickload duplicates them. Keep keys aligned with the profile-tier
  `GameState.discovered_corpses` (`Corpse.save_id`).
- **REMAINING — loot drops + money bags**: dropped `CanPickUp`s / money bags are
  re-INSTANTIATE-on-drop props (live state in `Item` meta + `preset_*`), which is
  the natural serialization surface; restore live weapon CLIP ammo AFTER the
  fresh-mag rebuild.
- **REMAINING — dynamic (encounter-spawner) NPCs**: needs spawn-definition +
  runtime state serialization (an ephemeral `@`-path key matches nothing on
  reload) plus `NpcPool` interplay (per-life fields reset via `reset_for_reuse`).
- **REMAINING — multi-level live positions**: positions/hp are captured only for
  the level you save IN; other visited levels contribute dead KEYS only, so a
  moved-but-alive NPC elsewhere snaps back to its authored spot. Extending =
  retain per-level `authored_npcs` buckets across door swaps (capture the
  outgoing level in `GameRoot.load_level` before freeing it).

Further exact-snapshot work extends THIS tier, not the profile-save language.

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

- `CharacterPartOption` for one seated character part (head / body / arm / leg:
  model + the `scale`/`position`/`rotation`/`texture` that fit it to the rig).
  Authored one-per-file under `resources/parts/<slot>/`, where the **filename is
  the id**. `PlayerAppearanceCatalog.tres` references those same files by
  `ext_resource`, so the player character creator and NPC authoring share one
  source of truth (`tests/test_part_library.gd` pins that; re-inlining a
  `[sub_resource]` into the catalog fails it).

Use folder scans and catalogs where possible so adding a `.tres` does not require
editing a hardcoded path list.

`PartLibrary` (`scripts/components/part_library.gd`) is the folder scan behind the
`apply_*_part` pick dropdowns on `BodyModelSwap` and `NpcLook` — the seam that
replaced "drag a `.glb` in from the file explorer, then hand-dial its scale,
position and rotation" with choosing a name. It is deliberately **authoring-time
only**: a pick is *stamped* (it copies the part's model + seat into the target's
own existing exports and forgets the id), so there is no runtime resolution
layer, no new load path, no save-format change, and no extra precedence rule on
`BodyModelSwap._host_part`. The pick fields are momentary — they always read back
`""`, so Godot's default-value skip keeps them out of every saved `.tscn`/`.tres`.
Consequences to preserve: renaming or deleting a part file can never retroactively
change an already-authored NPC, and deleting `resources/parts/` entirely leaves
every NPC rendering exactly as it does today. The known cost is that a stamp has
no per-property undo, so it prints the outgoing values to the Output panel first.

The **startup warning gate** is a boot-flow contract worth noting: `start_menu.gd`
queues `INTERNET_WARNING_CARDS` every normal project launch before the TOS, the
computer-room intro, or the menu. In the hosted `scenes/computerroom.tscn` path, the menu is
made visible immediately as the black warning card, while the room timer/audio stay
stopped until the menu emits `startup_gate_finished`. Both the room intro and menu
reveal arm short input shields so the click/key that skipped the warning cannot also
power the monitor or activate a menu button. The skip itself is gated on
`Settings.tos_accepted`: on a genuine first launch the cards are **unskippable** (the
press is swallowed but ignored) so a first-time player reads them before consenting.

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
is the single shared reward cheer. Player one-shot SFX now go through it — with one
deliberate carve-out, the death sting (below): `AudioManager` one-shots are parented to
`get_tree().root` with no `process_mode`, so they are pausable and would outlive a scene
reload into the next life, neither of which a death-cinematic sound can afford.

`DeathMix` (`scripts/player/death_mix.gd`, a code-built child of the Player) owns the
death cinematic's MIX. The cinematic used to fade the global **Master** bus to silence;
because every bus chain in Godot terminates at Master, that left no route for a sound to
survive the player's own death. The duck therefore moved down onto the four **world** buses
(`GameSettings.player_feedback.death_cinematic_buses` = `ambient` / `sfx` / `music` /
`voice`, which covers all authored audio since `radio` sends into `music` and `ambient_bed`
into `ambient`), and the death sting plays on `sting` — a bus deliberately absent from that
list, sending straight to Master. The Player's cinematic reaches it through exactly four
seams (`begin` / `set_world_duck` / `restore_world` / `begin_revive`), one on each
death-exit path; `restore_world` iterates the designer's bus list rather than a captured
snapshot, so adding a bus can never leave one death mode stale. No level is captured
anywhere: every write recomputes from `Settings.current_bus_db(bus)` scaled by one duck
factor, which is what makes the "re-trigger snapshots the ducked level and ratchets the mix
quieter" bug inexpressible. **Consequence for authoring: an `AudioStreamPlayer` with no
`bus` set lands on Master, which is no longer ducked — it plays at full volume under the
death card.** `tests/test_audio_bus_hygiene.gd` guards the scene side; every `.new()` site
already assigns a bus.

`EffectFactory` (autoload) is **not** a VFX registry — it is only the blood-particle
gameplay seam (`spawn_blood_particle`) plus a generic `spawn_at(scene, pos)` helper.
`spawn_at` is the shared point-spawn idiom (instantiate → position → emit → auto-free) and
the one place a future global "effects off" / pooling hook belongs; `spawn_blood_particle`
and `Throwable._spawn_destroy_particle` route through it. The richer effects (explosions,
oriented decals, host-driven gibs) carry per-instance config a point-spawn can't and preload
their own scene by UID — so restyle one by editing its `.tscn`, not by repointing a factory slot.

**Body-part gibs — the gore burst reads the victim's own body.** On death `GoreSpawner` (a code-built
child of every `Character`) throws two kinds of gib: generic meat chunks from `Character.gib_scene`, and
one `BodyPartGib` per part of the dying actor's **`BodyModelSwap`** — its actual head, torso, arms and legs,
launched from exactly where they sat, so the silhouette is still the character for the frame the burst
starts. Three contracts hold it together. (1) **The parts are duplicated, never taken.** `BodyModelSwap`'s
six part nodes are the same instances a pooled NPC reuses for its next life and nothing rebuilds them, so
the burst may only ever `duplicate()`. (2) **The transform is split, not copied.** `BodyPartGib`'s static
`mount_placement` puts a proper rotation (orthonormal, det +1) on the RigidBody and leaves scale — plus the
right limbs' det = -1 mirror — on the mounted child: a physics body ignores scale and renders a reflected
basis with inverted normals. (3) **The duplicate is cut loose from its host** — its inherited
`material_overlay` chains to the NPC's PERSISTENT per-limb flash material, which a recycled body keeps
driving. The per-actor override is the `BodyPartGibs` drop-in, found DUCK-TYPED on `body_part_gib_config()`
because `gore_spawner.gd` is on `Character`'s parse path and cannot afford a class_name that the editor has
not registered yet. Feel numbers: the `body_part_gib_*` group on `EffectsSettings`. Both gib kinds share the
`&"gib"` group, its oldest-first world cap (`gib_max_active`), and `gore_gib_data.tres`.

**The gib despawn fade is an overridable seam, and it depends on `mesh_instance` being wired.**
`Throwable.begin_gib_lifetime` awaits `_fade_out_for_despawn(fade)` before `queue_free`; the base tweens
`mesh_instance.transparency`, so a chassis that leaves that export unwired fades nothing and the gib POPS
(`gore_gib.tscn` shipped that way until it was wired). `BodyPartGib` overrides the seam to tween every mesh in
its mounted subtree, because `GeometryInstance3D.transparency` is per-instance and does not propagate to
children. Wiring `mesh_instance` also arms `Throwable._autofit_collision_shape`, which is why the meat chunk
carries `auto_fit_collider = false`: the auto-fit rewrites the shape's size but never the `CollisionShape3D`'s
transform, so a deliberately tilted/raised collider (that gib's) would be grown to the mesh bounds off-centre.
The body-part chassis keeps the auto-fit ON — its mount point is empty, so the box tracks the real limb.
Pinned by `tests/test_gore_gib_prefab.gd`.

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

### Darkness stealth — the `light_exposure` seam

Shadow-slows-detection is a one-field duck-typed contract, not a subsystem.
**Writers** stamp `light_exposure` (0 = pitch dark, 1 = fully lit) on the player
— `PlayerLightLevel` (`scripts/player/player_light_level.gd`, shipped on
`Player.tscn` with `host` = the Player) sums an `ambient` floor (`0.2`) plus
every scene `Light3D`'s contribution at the player's position on each
throttled `sample_interval` tick (`0.1` s — NOT every frame), skipping any
light tagged `&"pickup_beacon"` (cosmetic `PickupBeacon` glows) or
`&"stealth_light_exempt"`; the painted `ShadowVolume`
(`scripts/components/shadow_volume.gd`) writes its `shadow_exposure` on enter
and `1.0` on exit. Use one writer per level — the sampler overwrites a painted
value on its next tick. The field is plain `Player.light_exposure`, default
`1.0`, so an unwritten target detects exactly as before. **The consumer** is
`Perception._target_light_factor()` (`scripts/npc/perception.gd`): it reads that
field duck-typed (absent/non-numeric → `1.0`), samples it through the NPC's own
`Perception.light_falloff` if set, else the global
`GameSettings.light_stealth.falloff()`
(`resources/tuning/LightStealthSettings.tres` — an authored curve, else a ramp
from `dark_visibility` `0.25` at dark to `1.0` at lit), and multiplies the
result into `visibility_factor()`, which scales how fast the DETECTING meter
fills and is floored at `min_visibility` (`0.15`) so a genuine sighting still
reaches ALERTED. **`CrouchLightDouse`** (`scripts/player/crouch_light_douse.gd`,
also shipped on `Player.tscn`; `host` = the Player, `light` =
`PlayerEmittingLight`) is what makes the pillar bite: the HP glow is a real
`Light3D` at the player's own origin, so STANDING it saturates the sampler and
pins `light_exposure` at `1.0`. The drop-in reads crouch depth duck-typed off
`host.crouch.crouch_t` (the same seam `crouch_sight_mult` uses — no signal
wiring) and moves the light's `light_energy` toward `crouched_energy` over
`fade_time`; because the sampler weights each lamp by its LIVE energy, a doused
glow contributes ~nothing and exposure falls to what the ENVIRONMENT casts. It
touches energy only — `player.gd`'s HP `light_color` blend on the same node is
independent. Designer-tunable: `LightStealthSettings.tres`, the
`CrouchLightDouse` / `PlayerLightLevel` / `ShadowVolume` `@export`s, and the
`&"stealth_light_exempt"` group (`Groups.STEALTH_LIGHT_EXEMPT`) that drops a
decorative lamp out of the meter — never tag `PlayerEmittingLight`, that is the
liability half of the trade. Code-level: the per-archetype
`Perception.light_falloff` and `min_visibility`, since `npc.gd`'s
`_build_perception()` builds `Perception` at spawn and mirrors only the
sight/hearing fields, so no scene or `NpcData` reaches them. Designer surface:
**"Light & shadow: making darkness hide you"** (under *Stealth and detection*)
in `docs/AUTHORING_GUIDE.md`.

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

## Localization Readiness

The game ships English-only. This section records the contracts that keep a
future locale pass mechanical instead of archaeological — what is done, what is
guarded, and what is deliberately deferred.

- **`PlayerText` (`scripts/ui/player_text.gd`) is the chokepoint for
  player-facing strings.** UI code paints `PlayerText.<CONST>` /
  `PlayerText.<func>()`, never a raw literal. A `[PH] ` prefix marks a const as
  an UNAUTHORED placeholder (do not extract or translate it); `PlayerText.prefixed`
  / `strip_prefix` are the only manipulators of that prefix.
  `tests/test_player_text.gd` pins the const conventions (non-empty, exact
  `"[PH] "` prefix on marked consts, no `.gd` paths in player copy).
- **The ratchet, now at ZERO (2026-07-27).** Every raw literal at a paint site
  has been moved into `PlayerText`: `tests/test_player_text.gd`'s per-file
  `BASELINE` is empty and `BASELINE_HIGH_WATER` is `0`, so a new literal at a
  paint site (`label.text = "…"`, `notify_toast("…")`,
  `MenuStyle.make_title("…")`, …) fails the suite outright — there is no
  allowance left to hide behind. The guard runs the paint-site scanner
  (`addons/cybersunday_tools/panel_audit/scan_text.gd` — the same scanner the
  CYBER SUNDAY Audit tab runs live as its Text domain, and which
  `scripts/tools/validate_all.gd` now also reports headlessly). Re-measure any
  time with `godot --headless -s scripts/tools/text_debt.gd`, which prints the
  `BASELINE` table's exact shape. Three non-prose stragglers were fixed at the
  root rather than registered as copy: the chess move-log's `"\n"` line
  separator composes into a local, the bark bubble's tail glyph became the
  `NpcBarkUi.bubble_tail_glyph` `@export` (art, not copy), and the F3 developer
  HUD joined `ScanText.SKIP_FILES` (the dev-surface twin of the existing
  `scripts/tools` skip; the test and `text_debt.gd` honour that const too, so
  the three consumers can never disagree). The `tr()` sweep PROPER is still
  deferred — what this buys is that when it happens, `PlayerText` is the only
  file it has to touch.
- **Designer templates substitute named tokens, never the `%` operator.**
  `{amount}` (`RentCollector.paid_message`), `{part}`
  (`CrippleCallout.self_bark_template`), `[mph]`
  (`PlayerFeedbackSettings.death_message_fall`). Substitution is token-replace
  (`String.replace`), so a literal `%` in authored text can never raise a format
  error; a legacy `%s`/`%d`/`%f` in an old template still substitutes, code-side.
- **`TextFormat` (`scripts/ui/text_format.gd`) is the substitution/number/plural
  seam, and its header states THE RULE: substitute values into ONE whole authored
  template via `{named}` tokens (`TextFormat.subst`), or SELECT between whole
  templates (bool/enum/key) — never concatenate prose pieces or accept a prose
  fragment as an argument (fragments can't be translated). `PlayerText` bodies
  now follow it: `reputation_changed` / `alignment_changed` / `chess_checkmate` /
  the radio on-off toasts / `heal_status` / `inventory_weight` select whole
  templates, and every counted line (`level_up`, `respec_refunded`,
  `perks_header`, `quest_rewards_full`, `inventory_full`) picks a whole
  singular/plural variant through `TextFormat.plural` (the future `tr_n()` seam —
  the two-form signature is the English source shape). `TextFormat.num` is the
  ONE number formatter — every historic per-file copy delegates now
  (`Zorkmids.fmt`, `StatInfo._num`, `ItemInfo._num`, the stats screen's
  `_stat_num`) — and the future decimal-separator seam; `Zorkmids.money_text`
  owns the single `"{amount} zm"` currency template, and every `" zm"` paint
  site substitutes it whole (shop / chip-install price columns, the HUD wallet,
  level-up costs, item-value footers, the PlayerText money toasts). The
  `requires_*` deny toasts resolve authored display names BY ID inside
  `PlayerText` (`StatInfo.title` / `Perks.display_label` / `Factions.by_id`,
  capitalized-id degrade) — `BuildGate` passes raw ids, never pre-resolved
  labels. `tests/test_text_format.gd` pins subst/num/plural;
  `tests/test_player_text.gd` pins the selected-template outputs and the
  requires_* resolution. The old `EQUIPPED_SUFFIX` append became the whole
  `EQUIPPED_ROW` template (`PlayerText.equipped_row`, the composed row rides in
  as a value token). Known holdout fragments, deferred to the phase that owns
  their callers: `CHESS_CHECK_SUFFIX` (ChessScreen), `loot_title`'s heading
  `kind`, the `DEATH_MESSAGE_KILLED_BY*` legacy `%s` resource defaults, and the
  stats screen's hand-rolled summary plural (`stats_screen.gd
  _refresh_summary`).
- **Display strings are never behaviour keys.** Every seam where a shown string
  used to double as an identifier now has a stable key beside the label:
  `CompanionRecruiter.following(speaker)` is the follow-state predicate (its
  `label_for()` is display-only); player-menu tabs route on `PlayerMenus.TABS`
  `StringName` keys with `PlayerText` labels; Options tab pages are NAMED by the
  stable `SettingSpec.tab` key and titled via `set_tab_title`
  (`SettingSpec.tab_label`); keybind section headers key on
  `ActionSpec.section_key`; and NPC identity is `NpcData.id` (see *Stable NPC
  identity (save v4)* under Save Model).
- **Authored display names, not capitalized ids.** Anywhere the player reads a
  domain object's name, an authored field resolves it through one accessor per
  domain, and `String(id).capitalize()` survives only as the blank/missing
  degrade INSIDE that accessor (never a blank, never a raw id): stats via
  `StatInfo.title` (the `StatText` `.tres` — shared by the stats screen,
  character creation, level-up rows, item-tooltip stat lines, the
  `requires_stat` deny toast, and the dialogue stat-gate label
  `DialogueView.stat_gate_label`, so a stat has ONE name game-wide); factions
  via `Faction.display_name` (HUD reputation toasts through
  `UI._faction_name`, the `requires_standing` deny toast); abilities via the
  scene-root `Ability.display_name` `@export`, resolved by id through
  `AbilityRegistry.display_name_for()` (e.g. the upgrade-chip tooltip's
  "Installs …" line); perks via `Perk.display_name` through the `Perks`
  registry (`scripts/player/perks.gd`, id == `.tres` filename, mirroring
  `Factions`). Display-only in every case — behaviour/saves still key on the
  ids. `tests/test_display_names.gd` pins authored-wins verbatim, the
  capitalize fallback shapes, and (by source pin) that the retired
  capitalize-at-the-call-site bypasses can't return.
- **Casing chokepoint.** `MenuStyle.title_text()` is the ONLY place menu code
  uppercases, and it consults `MenuSkin.uppercase_titles` — a per-locale skin
  can switch the tracked-uppercase look off wholesale.
- **Text-column pixel budgets live on `MenuSkin`.** The fixed/clip_text widths
  the screens pin text columns to (options slider readout + rebind buttons +
  label rails, shop sort button + price columns, level-up row group + stat-name
  cell, reputation disposition column, character-creation cyclers) are
  `MenuSkin` `@export`s under "Layout budgets (English-measured px)", not
  per-screen consts — each is measured against ENGLISH strings (German runs
  +30-40% longer and will clip), so a locale retunes them in its remapped
  `menu_skin.tres` alongside `uppercase_titles`. They must NOT be grown
  globally to cure a clipped string: the fixed widths are what prevent runtime
  text from resizing/shifting controls (the `make_dialog` card-hop class of
  bug).
- **User-typed text never enters translation lookup.** Controls that echo typed
  input — name entry, character-creation name, the chess move box/log/hint, the
  CYBER SUNDAY dock, and the labels that paint a renamed pet's name (look-at
  readout, toasts, hotbar slots, item tooltips) — set
  `auto_translate_mode = AUTO_TRANSLATE_MODE_DISABLED`, so a player's text is
  never looked up as a message id. A no-op today (no Translations ship), a guard
  the moment one does.
- **Script-scope decision (recorded 2026-07): CJK is a possible future SKU, and
  it cannot be "just add a font".** The UI renders at 792x444 (396x216 base,
  stretch scale 0.5) with 11–15 px type and tracked uppercase titles — CJK is
  illegible at that scale. A CJK locale requires a per-locale `MenuSkin` remap
  (bigger sizes, `uppercase_titles = false`, `title_tracking = 0`) plus a
  legibility pass. `MenuSkin.uppercase_titles` is the first such knob. Do not
  "fix" `title_tracking` without knowing this.
- **Known gaps, deliberately deferred (recorded as gaps, not TODOs):** the
  locale seam itself does not exist yet (no `[internationalization]` config, no
  `Settings.locale`, no CSV export tool); `item_info.gd` composes tooltips from
  English-shaped fragments pending a target language; chess SAN input parses
  English piece letters only; the boot level's sign texture
  (`tb_textures/textures/sign.png`) is Swedish-language art; the TOS prose ships
  from `resources/ui/terms_of_service.gd`'s baked-in default (no authored
  `.tres` exists); and **no bundled font has CJK coverage** — the only game font
  (`resources/ui/futura_system_font.tres`) is a `SystemFont` listing Latin-only
  face names, so the in-scope CJK SKU needs a real `FontFile` shipped before the
  `MenuSkin` remap above can even be evaluated.
  CLOSED 2026-07-27: `LineEdit` right-click context menus (engine-provided
  English) are now disabled at all three fields we build — name entry, character
  creation, and the chess move box — alongside their existing `atr` opt-outs.

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
