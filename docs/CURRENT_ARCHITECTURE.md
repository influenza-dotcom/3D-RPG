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

**Debug save sandbox (2026-08-18).** `GameState.resolve_save_path(path)` is an allowlist rewrite applied at
the six sites that touch the five canonical files (`gamestate.cfg`, `quicksave.cfg`, `save_slot_1..3.cfg`):
while `enable_sandbox()` has armed `_sandbox_dir`, ONLY those five basenames map into `user://sandbox/`
(any other path — a test's scratch file, a dump — passes through unchanged). `enable_sandbox` forks the real
files in (skipping `.tmp`/`.bak` rungs), `commit_sandbox` copies them back over the real paths through the
same atomic rotate as a normal write, `disable_sandbox` only clears the latch — the console's `sandbox off`
command is what reloads the real profile so a cheated in-memory run cannot leak into the next real write.
Session-only by design: a crash or relaunch boots the REAL profile. `_write_atomic` also now counts every
attempt (`save_count` / `save_fail_count` / `last_save_*`) and emits `saved(path, err)`, which the F3 overlay
paints as a disk-write line — the autosave-storm bug class made visible. Pinned by `tests/test_debug_sandbox.gd`.

`GameState` is a profile/checkpoint save, not a full world snapshot. It persists
player progression, stats, inventory, equipped item, money, reputation, story
flags, quests, perks, ability unlocks (installed microchip upgrades), XP, status
effects, clock, respawn transform, current level identity, lightweight
discovered `Corpse` markers, the set of **learned NPC names**
(`GameState.known_names`, in `[world].known_names`) that drives the
"Stranger until introduced" masking, and the player's own **map waypoints**.

**Waypoints (`[waypoints].data`, additive — no `SAVE_VERSION` migration).**
`GameState.waypoints` is `{ level_path -> Array[Dictionary] }`, keyed per level exactly like
`world_objects` beside it, each record `{pos: Vector3, name, note, icon: int, tint: int}` — plus an
**optional `tracked: true`** — shaped and clamped by `scripts/world/waypoint_book.gd`. The API is
`add_waypoint` / `update_waypoint` / `remove_waypoint` / `clear_waypoints` / `waypoints_for` /
`waypoint_at` / `waypoints_full` / `set_tracked_waypoint` / `tracked_waypoint`; every
mutation funnels through one write barrier that bumps `waypoints_rev`, emits `waypoints_changed`, and
queues the same coalesced world-state autosave a door uses. A record stores a **palette index**, never
a `Color`, and an **icon ordinal**, never a shape — so an artist restyling
`HudSkin.minimap_waypoint_palette` restyles every pin already in every profile, and the enum's order is
an append-only compatibility contract. The load path re-runs `WaypointBook.sanitize` (drop records with
no position, re-clamp both text fields, truncate past `MAX_PER_LEVEL` = 32) because the file is
hand-editable; a profile that placed no pins writes no section at all. Cleared on New Game.
**The text is PLAYER-TYPED**, so every Control that paints it sets
`auto_translate_mode = AUTO_TRANSLATE_MODE_DISABLED` — never a msgid.

⭐**At most ONE pin in the whole ledger carries `tracked`** — the profile's single active navigation
marker (the pin the HUD corner box rim-pins and rings, and the one the top-centre `HudCompass` tape
draws a pip for). The flag is therefore a fact about the LEDGER, not about a record, and nothing
outside `GameState` may write it: `WaypointBook.make` stays deliberately 5-field, `is_tracked` is the
one definition of how the key reads (absent = false, and a hand-edited `tracked=1` counts), and
`update_waypoint` — which rebuilds the record through `make` to keep a pin's position immutable —
carries the old flag across the rebuild by hand. `set_tracked_waypoint(level, index, on)` **moves**
the flag: it clears every other tracked pin across **every** level first (on the untrack path too),
returns false only for a bad index, and does no work at all when the pin is already in the asked-for
state. `tracked_waypoint()` walks the ledger and answers `{"level":…, "index":…}` (or `{}`) rather
than caching an index, because an index is exactly what goes stale when a pin below it is deleted.
The invariant is enforced on LOAD as well — `_fold_tracked` runs per level as each sanitized list is
folded in and **first wins**, since `sanitize` only ever sees one level's list while the rule spans
the whole ledger.

**Quests live on the `QuestTracker` autoload, but persist through `GameState` (M1).**
The tracker dicts (active / completed / failed + objective progress), the four quest
signals, reward granting, and the `[quests_active]` / `[quests_completed]` /
`[quests_failed]` cfg round-trip all belong to `managers/QuestTracker.gd`;
`GameState._save_perks_and_quests` / `_load_perks_and_quests` delegate their quest
halves to `save_into` / `load_from`, so quest progress is still part of the one
profile save. `GameState` keeps **one-line forwarders** for the quest *function* API
(`start_quest`, `advance_objective`, `complete_quest`, `fail_quest`, the `is_*`
queries, and the `notify_*` world hooks) because ~70 authored call sites — dialogue
choices, `TriggerVolume`s, `QuestStarter`s, `Readable`s — reach for them; new code
should call `QuestTracker` directly. **The four SIGNALS did not stay behind**: connect
to `QuestTracker.quest_started` / `objective_advanced` / `quest_completed` /
`quest_failed`. The single inbound edge is `GameState.set_flag`, which calls
`QuestTracker.notify_flag_set` — that one call both advances matching FLAG objectives
and expires (auto-fails) any quest whose `expire_on_flag` matches.

> ⭐ **Pairing is decided by identity, not by a default.** `GameState._qt()` returns the
> `QuestTracker` autoload only when `self == GameState`; **any other** GameState instance
> builds its OWN private tracker as a child (freed with it). That is what preserves unit-test
> isolation — quest state used to live on `GameState`, so a bare `GameState.new()` gave each
> test a private journal, and pointing every instance at the singleton leaked quest state
> between tests. `QuestTracker.game_state` is the mirror seam. `tests/test_quest_tracker.gd`
> pins both directions.

**Stranger-until-introduced naming.** Every NPC's `display_name` is shown to the
player as `PlayerText.STRANGER` until the player **talks to them**:
`DialogueManager.start` calls `GameState.reveal_name` on any real character
speaker as the conversation opens (gated on `_speaker_is_character`, so a
terminal / sign / note never enters the ledger), after which `known_names`
carries the character across saves (wiped on New Game). `DialogueLine.reveals_name`
still fires the same call from `_show_line` but is redundant for a character. The single display seam is
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

**The player's zorkmids are NOT an inventory item.** The wallet is the authoritative
fractional `Character.money` float (what the whole economy — merchants, pickups, bounties,
the death settlement — reads), and it is SHOWN, never stored, in the bag: the HUD readout
plus a **wallet row** above the backpack grid (`InventoryScreen._paint_wallet`) and under
your column in the loot screen. Dying MOVES that float rather than destroying it:
`Player._bequeath_wallet` hands `economy.death_purse_loss_fraction` (all of it, by default)
to whoever killed you — where it rides their wallet into their corpse's loot bag — or, when
nobody is credited, spills it on the ground as a physics `MoneyBag` (`_spill_death_purse`,
deferred out of the physics flush and the gore burst). A `RELOAD_*` death mode settles
nothing, since the rebuilt world would hold neither.

The two gestures that used to live on a coin tile in the grid live on that wallet row, via
the shared **`AmountPrompt`** (`scripts/ui/amount_prompt.gd`, code-built into both screens
like `GridInventoryView`): **Drop…** spills a chosen slice of the purse as a `MoneyBag`
(`Player.drop_money`), and **Stash…** in the loot screen deposits a chosen amount into the
source as a coin tile (`LootScreen._deposit_coins_to_source`). The prompt seeds itself with
the full wallet and clamps to it, so Enter alone still means "all of it".

(HISTORY, because the seams it left are still load-bearing: `money` was for a while
*mirrored* into a real `zorkmids` stack in the backpack by a `MoneyPurse` component, whose
grid footprint grew with the amount — a fat purse ate 1×1..3×3 cells of backpack. That
component is gone. `GameState.capture` still **skips `Zorkmids.ITEM_ID`** as belt-and-braces
— no live path puts a coin tile in the player's bag, and one that slipped in would restore
as cash the wallet never counted. `CharacterInventory.transfer_to` still **coalesces its own
`changed` across the remove + rollback** and checks `add()`'s return, restoring any un-refit
remainder via `restore_stack`: a listener that writes back into the bag on `changed` — the
pickpocket wallet freeze below is the shipped one — must never fire on the intermediate
post-remove state and grab the freed cells before a bounced loot stack is rolled back.)

**All loot cash is a coin tile now — there is no "Take N zm" button anywhere.** A dead
NPC's / crate's wallet is seeded as a real `zorkmids` coin tile in the loot bag
(`LootableCorpse.setup`, `ItemContainer._seed_money_coins` — a fixed 1×1, so it always
places), taken by clicking it (`LootScreen._take` converts the stack to real `add_money`,
never a loose backpack stack) and deposited as a tile (`_deposit_coins_to_source`). NPCs
themselves keep an abstract `money` float, so a **live pickpocket**
target's wallet is FROZEN into a coin tile in its pockets on open (`_freeze_live_wallet`)
and THAWED back into that float on close (`_refloat_live_wallet`, folding in any un-taken
or planted coins) — so it loots as a clickable tile while you're in its pockets but stores
as a plain float between robberies (it still drops as loot on death, funds its shopping). A
grid-full pocket may freeze only part; the un-fit remainder stays on the float and thaws
back untouched. `LootScreen` wallet modes are now just `TILE` (every cash source) and
`NONE` (gear exchange — a cash deposit is refused, since gifting a friend's wallet isn't
"exchanging"). Corpses aren't saved, so their coin tiles re-seed from the
authored/earned `money` on the next spawn; a CONTAINER's coin tile is real loot and
DOES ride the exact-snapshot tier (`serialize_stacks`), so a quickload restores exactly the
cash you left in the crate — it re-seeds from `money` only on the profile/Continue tier.
`LootScreen._take` credits the player through `add_money` and debits **nothing else**: a
corpse / container has no `money` float at all, and a pickpocket target's is already 0
(frozen into the very tile being lifted), so there is no second ledger a take could
double-charge.

**Player abilities are microchip upgrades.** Each unlockable mechanic (wall-climb,
grapple, slide, air-dash, fall-immunity, board-visualizer, the **bunny-hop** jump-chain
speed boost, and the **silent takedown** stealth kill) is a drag-drop `Ability` node
whose presence grants it; a fresh game starts with **none** (`Player.tscn`
`starting_unlocks` is empty) beyond any implants **bought on credit** at New Game's
implant-purchase step (`scripts/ui/implant_choice.gd`, raised by StartMenu after
character creation's Begin; an empty cart keeps the zero-ability start). The step runs a
**credit check** — *the Underwriting Sheet*: StartMenu presents the pending stat sheet
(`present_build`), and the screen rates it through the pure
`EconomySettings.credit_rating_for` / `credit_limit_for` curves. The rating reads four
normalized lines off an AUTHORED per-stat actuarial table (`credit_underwriting`, one
`StatUnderwriting` row per stat) — CAPACITY and VIABILITY and TRADE from invested points,
minus EXPOSURE from pledged (dumped) ones — over a `credit_baseline_fraction` floor,
yielding a 300..850 score, a band key, a filed-reason key, and a limit capped at
`credit_limit_max` (shipped 2100 zm). Unchecked chip rows grey the moment their price
stops fitting the remaining credit — the cart can never bill past the limit plus
`player_starting_money`, so Begin stays never-gated by construction.
⭐**Positives feed only the additive lines and negatives only the subtractive one, so
investing can never lower a rating and dumping can never raise it, for any authored
table.** That structural property is the fix for the model this replaced: the creation
budget is zero-sum, so a flat per-dump penalty was algebraically a tax on spending the
budget — the all-zero non-character rated the ceiling and took the full cap while a
committed build was fined. The scorer normalizes against `StatBudget.STAT_MIN/STAT_MAX`
(forwarded by the screen), which is why those bounds live on the allocator and
`CharacterCreation` derives them: the bank reads the builder, never the reverse. An EMPTY
sheet is the ABSENCE of an application and fails OPEN to the ceiling (the bare-scene
default); the all-zero SIX-KEY sheet is a filed-but-empty form and is rated normally. StartMenu stamps
the cart into `GameState.unlocks` after `reset_for_new_game`, and `Player._ready`'s
fresh-boot escape hatch (a non-empty `GameState.unlocks` while `loaded` is false — the
`stat_values` idiom) applies it at spawn. The BILL is debited straight
from `GameState.money` (reset had just re-seeded it to the `player_starting_money` base)
— the balance is ALLOWED to go negative, so a loaded build starts the run in debt and
every paid service refuses until the wallet recovers; every wallet readout (the HUD's
signed top-left, the shop / level-up / chip-install headers, the implant tally) tints
red while negative (`HudSettings.money_debt_color` / `MenuStyle.wallet_color`). `GameState.money` is the ONE home
of that balance: `Player._ready`'s wallet settle reads it not only when `loaded` but also
on the `profile_active` fresh branch, so every loaded=false boot of a created run (the
New Game boot, a menu-and-back Continue, a no-save death reload) re-applies the debt
together with the unlocks the escape hatch re-grants — the goods and the bill can never
separate. Every other ability the player earns by finding/buying a **chip Item**
(`Item.installs_ability`, `resources/items/chip_*.tres`, all sharing the `microchip.glb`
look) and paying a `ChipInstaller` mechanic (`scripts/components/chip_installer.gd` →
`ChipInstallScreen`) to install it — the installer consumes the chip, charges through
`add_money`, and calls `player.unlock_mechanic`, which persists in `GameState.unlocks`
(re-applied via `set_unlocks` on load). The instant-grant `UpgradePickup` remains for
special "online immediately" pickups.

**Weapon modifications ride the EXISTING `weapon_delta` — no new save key.** A weapon part is
an ordinary `Item` carrying a `WeaponMod` payload (`resources/items/mod_*.tres`), and a
`WeaponBench` fits it into one of six FO4 slots. What persists is **six `@export_storage`
`StringName` fields on `WeaponData`** (`mod_receiver`/`mod_barrel`/`mod_magazine`/`mod_sight`/
`mod_muzzle`/`mod_stock`, indexed through `WeaponData.mod_id` / `set_mod_id` off
`MOD_SLOT_PROPS`), each holding the fitted part's `Item.id`. `@export_storage` is the keystone
and both halves of it are load-bearing: the STORAGE usage is what makes `Resource.duplicate()`
carry the value (a bare `var` is silently dropped, so every `ItemDb.make_weapon_item` /
`clone_unique` would hand back a stock gun with no error anywhere), and the SCRIPT_VARIABLE
usage is what `ItemDb._is_saved_weapon_property` requires — so all three existing write sites
(`GameState.capture`'s bag stack loop, its held-item fold, and
`CharacterInventory.serialize_stacks`) diff the slot ids automatically through
`ItemDb.weapon_delta_for`. Hiding them from the inspector is what stops a designer typing an id
into a TEMPLATE `.tres` and giving every instance of that gun a permanent non-empty delta
(`tests/test_weapon_mods.gd` pins all three properties).

⭐**On load the CATALOG is authoritative, not the saved numbers.** `restore_item_from_save` ends
`return rebuild_weapon_mods(item)` (`ItemDb.rebuild_weapon_mods` → `WeaponModKit.rebuild`), which
throws away the restored scalars and re-derives the whole stat block from the live weapon
template plus the live part `.tres`. That is a **deliberate, patch-note-worthy trade**: retuning
`mod_long_barrel.tres` or `pistol.tres` reaches guns already sitting in existing save files, so a
balance pass changes a player's modded gun under them — and in exchange the two halves of the
delta (the ids and the numbers they produced) can never drift apart, and the seven
resource-valued overrides (`view_model_override`, `fire_sound_override`, `projectile_scene_override`,
`on_hit_effect_override`, the two other sounds, `caliber_override`) survive a quickload at all,
which storing numbers could never do — `_is_weapon_delta_type` rejects those types by design. The
derived scalars are still written alongside the ids, redundantly and on purpose, so a save written
today stays restorable by a build without `rebuild_weapon_mods`. A part id deleted from the game
resolves to null, is dropped with a `push_warning` naming it, and the slot is re-stamped blank —
the save self-heals. `rebuild_weapon_mods` is a strict no-op for an unmodded weapon and must never
return `null` where it previously returned an item; a modded gun whose template has left
`resources/items/` keeps its restored scalars with a warning rather than being nulled.

What survives where follows the ordinary rules: a modded gun in the player's bag or hands rides
the **profile** tier (autosave, Continue, quicksave, slots); one in an authored `ItemContainer` or
stash rides the **manual quicksave/slot** tier only (`WorldSnapshot`); one dropped as a `WorldItem`
is persisted by neither, exactly like every other dropped item. The parts themselves are plain
stacking `Item`s keyed on `Item.id` — no special case anywhere.

The grant/revoke/persistence plumbing behind those calls lives in a **Player-owned
`AbilityManager`** (`scripts/components/abilities/ability_manager.gd`, a `RefCounted`
built at the Player's var-init and wired in `Player._init`), not inside `player.gd`. The
Player exposes thin forwarders (`has_mechanic`, `mechanic_installed`, `unlock_mechanic`,
`grant_ability`, `revoke_ability`, `can_grant_mechanic`, `set_mechanic_active`,
`unlocked_list`, `installed_list`, `disabled_list`, `set_unlocks`, `set_disabled_unlocks`)
that every caller duck-types, and keeps only the three typed hot-path refs (`_wall_climb` /
`_slide` / `_grapple_ability`) its physics step drives each frame — those stay on the Player
because the movement feel depends on their exact call order. A runtime grant is rebuilt from
the id by the shared `AbilityRegistry` snake_case naming convention (scene ↔ `ability_id()` ↔
script), so there is no hand-maintained id→script table. The player's cosmetic first-person
body (the FP legs+torso+arms rig, the separate carry-hands / bare-fists view-model rig, and
their motion) is likewise a
component, not `player.gd` code: **`FirstPersonBody`** (`scripts/player/first_person_body.gd`),
a scene-wired Player.tscn child on the Landing `host = NodePath("..")` idiom, which also
carries the authored `fp_*` pose overrides (see `ARCHITECTURE_REVIEW.md`, Completed
Extractions, for the ordering invariants). The stamina/sprint economy lives in a
**Player-owned `StaminaManager`** (`scripts/player/stamina_manager.gd`, a `RefCounted` on
the same built-at-var-init / wired-in-`_init` idiom, preloaded by path — no class_name):
the Player keeps the `stamina_changed` signal, a raw `stamina` property alias, and 1-line
forwarders for the whole old surface, while its `_physics_process` drive beats stay at
their exact positions; every stamina RATE and per-verb COST remains on
`GameSettings.player_movement` — the one exception is the RANGED SHOT price, which is DERIVED
per weapon: `WeaponData.stamina_effort()` (damage, pellets, blast payload) sets how much a
trigger pull is worth, `stamina_shot_cost` prices one unit of it, `WeaponData.stamina_cost_mult`
trims the result, and `stamina_shot_drain_ceiling` clamps it so no weapon can out-drain sprinting.

**Installed vs active (the Implants tab's on/off switch).** An `Ability` node's presence is
INSTALLED; its `enabled` flag is ACTIVE. The player switches an installed implant off from
the Implants tab (`Player.set_mechanic_active` → `AbilityManager.set_active`, which fires
each node's `on_deactivated()` hygiene hook so a live slide ends and a live grapple rope
severs, then emits `mechanic_toggled`). A switched-off implant reads FALSE from
`has_mechanic` — so every gameplay gate turns off — while `mechanic_installed` stays true, so
the `ChipInstaller` guards (`_distinct_installable`, `install_carried`, `buy_and_install`,
all keyed on `mechanic_installed`) never re-sell an implant the player already owns. **New
gameplay gates should ask `has_mechanic`; only economy/UI "do they own it" questions ask
`mechanic_installed`.** Because `unlocked_list()` is the ACTIVE projection, the off state
needs its own persistence or one autosave would delete the implant: it rides the separate
additive `[player].disabled_unlocks` key (`GameState.disabled_unlocks`, captured from
`player.disabled_list()`, restored by `set_disabled_unlocks` right after `set_unlocks` — that
call BUILDS a missing node then disables it, since `set_unlocks` only builds ids it enables).
No `SAVE_VERSION` bump: an older save simply lacks the key and reads as nothing switched off.
Pinned by `tests/test_implant_toggle.gd`.

The autosave is written **atomically**: `save_to_disk` writes a sibling `.tmp`,
rotates the previous good file to `.bak`, then renames the temp over the target,
so a crash mid-write can no longer corrupt the one-slot save. `load_from_disk`
falls back to `.tmp` (the interrupted newest write) then `.bak` when the primary
is unreadable — where **unreadable** means three things, because a broken file
does not reliably fail to parse: it did not load, or it parsed but shows none of
the recognised profile sections (a 0-byte or shredded file parses `OK` with no
sections at all), or it parsed as one of ours but lacks the terminal `[eof]`
marker that `save_to_disk` stamps as its **last** section — i.e. a tail-truncated
write, which keeps `[meta]`/`[player]` and silently loses `[perks]`/`[quests]`.
Each rung gets its own `ConfigFile`, so a rejected rung can never blend its
residue into the one that succeeds. A save written before the marker existed
carries none, so a marker-less primary is still kept whenever no sibling
verifiably has one. The first write after a fallback-recovered load does **not**
rotate that path's primary onto `.bak` (it is the file the ladder just refused);
the exception is tracked per save path, since quicksave and the named slots write
through the same routine. Every save stamps `[meta].version` (`SAVE_VERSION`, now
**5**) — read into `save_version`. Four schema migrations exist. **v2** (2026-07-09)
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
rewrite is impossible). **v5** (2026-08-09) versioned the pre-ATM negative-wallet
fold. Saves written before the ledger carried the implant debt as a **negative
wallet**; the wallet is cash-only now, so a negative one can only be that legacy
debt and it moves onto `account`, where the ATM can actually repay it. The fold
shipped unversioned on the argument that it was idempotent by construction (after
one save `money >= 0`, so it could never fire twice) — but that rests on the
cash-only invariant, and `DialogueChoice.give_money` is documented as accepting a
**negative** amount and applies it unclamped. A designer authoring one fee would
have turned a live wallet into interest-bearing bank debt on the next load, so the
fold is now gated on `save_version < 5` instead of on the data.

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
(`scripts/ui/save_load_screen.gd`), a slot menu registered in the
`InputManager` modal registry (like every screen it does not pause the tree —
only `DialogueManager` still does): a load-only quicksave row (F5 owns writing it)
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
- `WeaponMod` and `WeaponStatDelta` for weapon PARTS — the slot/fitment/overrides payload
  and the one-arithmetic-line stat change it applies. A part is an ordinary `Item` `.tres`
  carrying a `WeaponMod` in an inline `SubResource` (`resources/items/mod_*.tres`), exactly
  as a weapon Item carries a `WeaponData`, so `ItemDb`'s boot scan of `resources/items/`
  registers it for free — **no new folder, no new registry, no new folder scan**. The
  `property` field of a delta is dropdown-suggested from `WeaponData`'s own scalar exports
  (`scripts/items/weapon_fields.gd`), so a designer cannot author a change the save cannot
  carry. All fold math lives in the one const-preloaded `scripts/items/weapon_mod_kit.gd`.
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
needs zero ray changes. Twenty-one scripts extend it (plus `DogPickup`, which
extends `CanPickUp`, so the tree is three levels deep): pickups (`CanPickUp`,
`MoneyPickUp`, `UpgradePickup`), loot/trade screens (`ItemContainer`,
`LootableCorpse`, `Merchant`), service stations (`Healer`, `Bonfire`, `LevelUp`,
`PerkStation`, `RespecStation`, `ChipInstaller`, `WeaponBench`, `ChessMatch`, `Atm`), and
world objects (`Door`, `LevelDoor`, `Radio`, `Readable`, `Switch`, `QuestStarter`). The full
inheritance tree, base contract, and "add a new interactable" recipe live in
[`scripts/components/README.md`](../scripts/components/README.md#the-lookatinteractable-hierarchy);
per-component `@export` knobs are in `docs/AUTHORING_GUIDE.md`. The eight dual-mode
stations also carry the two-method dialogue-station contract
(`dialogue_station_option()` / `open_dialogue_station()`) that grows their dialogue
option — documented in that same README. Note `Corpse`
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

**OS focus and input (2026-08-18).** An unfocused window is NOT a control-lock predicate —
`gameplay_suppressed()`'s truth set is unchanged (modal registry + cutscene + name-entry). The OS
stops routing keyboard and clicks to an unfocused window; Godot itself releases held keys and
every pressed action on focus loss (`Input.release_pressed_events`, called from `SceneTree`'s
`NOTIFICATION_APPLICATION_FOCUS_OUT` handler before the notification reaches any node, and again
from the display server's deactivate path); and the pad — which SDL keeps reporting through an
alt-tab while `Input.mouse_mode` still reads `CAPTURED` — is silenced by the engine flag
`input_devices/joypads/ignore_joypad_on_unfocused_application = true` in `project.godot`, which
makes `Input` drop joypad events and release held joy buttons/axes/actions. No input reader gates
on focus; `tests/test_focus_input_lock.gd` pins the flag ON (the ProjectSettings value + the live
`Input` property). The one seam the flag can't cover — Windows delivers the click that re-focuses
the window as a real press — is `MouseInput`'s refocus fire latch: one latch per fire button
(`Attack`, `alt_attack_action`), both armed in its `_notification` on
`NOTIFICATION_APPLICATION_FOCUS_IN/OUT` (app-level: dispatched synchronously from `WM_ACTIVATEAPP`
BEFORE the activating click is flushed, whereas the window-level pair's deactivate half is
timer-deferred; both pairs flap harmlessly when the native Options music picker opens — a modal),
each cleared by its own button's release (the release event in `_input`, or the next poll reading
it up) — so the activating click is eaten, a fresh click fires even when it lands in the same
frame as the release, and holding ADS after a left-click activation cannot swallow the next shot.
`PickupRay`'s left-click alternate throw honours the primary latch. Known residuals, accepted: the
mouse WHEEL is the one input Windows'
hover-scroll still delivers to an unfocused window (Godot doesn't filter it, so Hotbar Next/Prev
can cycle in the background); a pad trigger held across the focus edge reads released after
refocus (the flag released it and the axis is only re-reported on its next value change), so its
next movement is a fresh pull that fires; a fire key rebound to the KEYBOARD can re-press through
OS autorepeat after a keyboard alt-tab. Same test file pins the latch.

**Contextual-key contract (lean vs. the verb already on Q).** `LeanLeft` shares the Q binding with
`Takedown` (which `PetInteraction` already shared). `LeanRight` shares nothing — `PickUp` (Interact)
moved off E onto its own key, F — so the right peek is unconditional. One arbiter resolves the
sharing, on the PRESS only:

- Each contextual verb driver answers `pending_verb_action() -> StringName` — the action it has a
  live target for, or `&""`. Today that is `SilentTakedown`, `PetInteraction` (both report
  `Takedown`) and `PickupRay` (`PickUp`, from `interact_available()`, which mirrors the three
  outcomes of its own `PickUp` input branch). `Player.pending_verb_actions()` duck-type-scans its
  children for that method plus the ray off the camera rig, so a NEW verb driver is picked up by
  implementing the method — there is no hand-written list to keep in step.
- `Lean._side_held` asks, once per press, whether any reported action
  `InputManager.actions_share_binding()`s with the lean action. If so the verb owns the press and
  no lean starts. Otherwise the lean CLAIMS the key for the whole hold, and
  `SilentTakedown`/`PetInteraction` `_can_run()` stand down on `Player.lean_owns_action()`.
- Deciding once (not per frame) is deliberate: a lean must not collapse the instant it peeks a
  target into the crosshair, and the claim is what stops that same peek charging a hold-verb
  underneath itself.
- Because the arbitration reads the LIVE InputMap, rebinding a lean side onto its own key in
  Options → Controls removes the sharing and makes that side unconditional. Nothing hardcodes the
  key. `Lean` runs at `process_physics_priority = 1` so a press reads the same frame's verb state.
- ⭐The lean's two gates are DIFFERENT KINDS. `_input_is_ours()` is HARD (dead / dialogue / a modal owns
  the keyboard) and releases the claims — the verbs must get their key back. `_posture_allows()` is SOFT
  (airborne past `ground_grace`, climbing, sliding) and only zeroes the lean target, KEEPING the claim,
  because the claim is re-decided on `just_pressed` alone: releasing it mid-hold strands a still-held key
  with nothing to re-arm it. This is load-bearing — every weapon's `WeaponData.self_knockback` lands in
  `explosion_velocity` → `velocity` on fire, so a downward-aimed shot un-grounds the player for a few
  frames; as a hard gate that made one trigger pull permanently kill the peek ("i cant shoot and lean at
  the same time", 2026-08-20). `ground_grace` (coyote-time idiom) absorbs the hop so it does not even dip.
- The lean itself writes only the head rig's local X + Z (`Crouch` owns that node's Y); the
  `CharacterBody3D` capsule never moves, so no movement, navmesh or hit-shape assumption changes.
  `tests/test_lean.gd` pins the binding-share seam, the claim, and the pose math.

**Dialogue-suspend contract.** The station options themselves (Trade/Heal/Rest/Level Up/
Install/Modify/Chess/Bank) are discovered via the **dialogue-station contract**: `DialogueManager`
scans the speaker's direct children by `has_method` for the
`dialogue_station_option()`/`open_dialogue_station()` pair and paints the options sorted by
each component's explicit `DIALOGUE_ORDER` key (`10..70` incl. `WeaponBench`'s `55` = the fixed
Trade → Bank sequence; see `scripts/components/README.md`). Seven of the eight suspend through
the unchanged
`DialogueManager._suspend_for_menu`, which hides the box and connects the sub-menu's `closed`
as a `CONNECT_ONE_SHOT` resume BEFORE calling the open; `Bonfire` is the one act-and-close
station (its contract omits `closed` — rest, then the conversation ends, no suspension).
So every suspending screen (`ShopScreen`/`LootScreen`/`HealScreen`/`LevelUpScreen`/
`ChipInstallScreen`/`WeaponBenchScreen`/`ChessScreen`/`AtmScreen`) MUST emit `closed` on EVERY refuse path — each
funnels its guard early-returns through a private `_refuse_open()` that just `closed.emit()`s
(`AtmScreen` emits inline at each guard, same contract; `RespecScreen` keeps the same funnel
as insurance although nothing dialogue-hosts it yet). A refuse that returns silently would
strand the conversation `_suspended` forever (box hidden, tree paused, no way to advance). On
the standalone open path nothing listens to `closed`, so the emit is a harmless no-op there.

## Effect And Audio Seams

`AudioManager` (autoload) is the one-shot SFX seam: `play_sfx` / `play_2d_sfx`
default to the diegetic `world` bus (which sends into `sfx`, so the audio-options
sliders apply — and which carries the indoor room echo the roof duck toggles); a
non-diegetic caller passes `&"sfx"` explicitly, and `play_applause`
is the single shared reward cheer. Player one-shot SFX now go through it — with one
deliberate carve-out, the death sting (below): `AudioManager` one-shots are parented to
`get_tree().root` with no `process_mode`, so they are pausable and would outlive a scene
reload into the next life, neither of which a death-cinematic sound can afford.

**Station music** (`managers/StationMusic.gd`, autoload) is the machine's own radio: while a self-serve
terminal's screen is open — shop / ATM / heal / level-up / respec / chip-install / weapon-bench / chess — one looping shop
theme plays through the `station_music` bus, a parameter-for-parameter clone of the `StationSpeaker` chirp's
filter chain that sends into `music` rather than `world` (the chain is the tinny character; the send decides
which volume slider owns it, and a minute-long loop is music). The seam has three properties worth knowing:

* **It POLLS the modal registry, it does not hook the screens.** `InputManager.any_station_music_open()` reads
  a `station_music` flag authored on every registry row — the registry now derives **five** surfaces, not four.
  Hooking `opened`/`closed` is not merely unnecessary but *wrong* here: every station screen emits `closed` on
  its REFUSE path (so a dialogue-hosted open that suspended the conversation on that one-shot is never
  stranded) while `opened` fires only on success, so a refcount would decrement without incrementing. A poll
  asks the current truth, which self-heals across a refused open, the death sweep, a quickload and a level
  swap with no repair code — and touches zero screen files.
* **It never writes a bus**, only its own node volume, so it does not contend with the `music` bus's
  single-owner protocol (`DeathMix`, honoured by `MusicDucker` and the ADS duck).
* **Two other music layers stand down for it**, both through the flag it publishes (`is_bed_wanted()`) rather
  than through its volume, so every handover is a real crossfade: `MusicDirector` collapses both combat tiers
  (`yield_to_station_music`, the same precedence it already gives a diegetic `Radio`), and `DialogueMusicBed`
  ducks by a third summed level (`dialogue_music_menu_duck_db`) so a shop hosted inside a conversation sounds
  identical to a bare kiosk. The forced-loop logic both beds need now lives in one place,
  `scripts/audio/loopable_stream.gd`.
* **And the conversation's BUS duck stands down for it** — the other half of that "identical to a bare kiosk"
  rule, through a **second, tighter** published flag: `is_screen_open()`. `MusicDucker` used to have one input
  ("a conversation is up") and therefore stayed armed through a dialogue-hosted Trade, which suspends the
  conversation rather than ending it — so the machine's radio played `music_duck_amount_db` (-12 dB) under the
  kiosk two metres away, with nobody speaking over it. It now composes `talking AND NOT station_radio`
  (`MusicDucker.wants_duck`, pure and pinned by `tests/test_music_ducker.gd`), fed per-frame through
  `DialogueManager.note_station_screen()` beside the bed's existing `note_menu_music()`. **The two flags are
  deliberately not the same signal:** the bed reads `is_bed_wanted()`, which rides the `hold_seconds` grace
  window out so it does not stutter back in over the shop tune's tail; the duck reads `is_screen_open()`, which
  drops the instant the screen closes so the resumed line still lands over ducked music. `MusicDucker.reset()`
  (Player.die) clears both composed **inputs**, not just the latch — StationMusic keeps asserting straight
  through the death cinematic, and a `_talking` left armed would re-duck the bus that reset just handed to
  `DeathMix`.

**The wandering bed** (`scripts/components/wander_music.gd`, an authored `AudioStreamPlayer` in
`scenes/game.tscn` under `Player`) is the quiet exploration score. **It currently ships INERT** — its
playlist (`WanderMusicSettings.tracks`) is deliberately empty, which by design means no bed, no tier flag,
and every other audio layer behaving exactly as it did before the layer existed; authoring a track is the
only step needed to switch it on. The design is defined as the **exact complement of `MusicDirector`**: it is audible in precisely the moments the combat score is silent, and stands down in
precisely the moments the combat score swells. Three properties follow from that framing:

* **The complement is computed from ONE answer, not two opinions.** The NPC-awareness walk that decides
  "is anybody fighting or hunting?" moved out of `MusicDirector` into `scripts/audio/soundscape.gd`
  (`Soundscape.scan` returns the raw combat/caution pair the score has always kept; `Soundscape.alert_level`
  collapses it worst-first for the bed), along with the "is a diegetic `Radio` audible from here?" distance
  scan. Two copies of that logic would not drift into a cosmetic bug — they would drift into a **gap** where
  neither layer plays or an **overlap** where both do. `MusicDirector._scan_alert_levels` and
  `._radio_audible_to_player` keep their names as delegations so their test seams are unchanged.
* **The two envelopes have to interlock, and the arithmetic is pinned.** `WanderMusicSettings.fade_out` must
  stay under `MusicDirector.fade_in_time` (the bed has to be gone before the score is loud), and
  `resume_delay` must cover `combat_linger + fade_out_time` (the bed must not rise under a fight that is still
  fading out). `tests/test_wander_music.gd` asserts both against the live tuning values, because a retune
  breaks them silently and only a playtest would notice.
* **It yields to everything and is yielded to by nothing** — combat, caution, dialogue, station music, and an
  audible in-world `Radio`, the last two read from the flags those layers already publish. It is the bottom
  layer of the mix. Like every other bed it writes only its own `volume_db`, never the `music` bus.

Its one non-obvious behaviour is the **rest window**: after a track plays through, the bed goes quiet for a
random `rest_seconds_min`..`max` before picking again, because a wandering theme that never stops becomes
wallpaper. That rest is scheduled off the player's `finished` signal, which is why `LoopableStream` now forces
the loop flag in **both** directions (`non_looping_copy` as well as `looping_copy`) — a track someone imported
with Loop ticked would never emit `finished`, and the layer would silently become continuous with nothing
logged. Debug readout: the `wandermusic` console command, whose first line is *who owns the moment*.

**Every sound the game WORLD makes varies slightly in pitch on every play**, and it is one seam:
`AudioManager.vary_pitch(base_pitch)`, driven by the single knob
`GameSettings.audio.global_pitch_spread` (default `0.15` — deliberately the same number as
`interactable_impact_pitch_spread`, this project's own impact spread; `0.0` switches the whole effect
off). Sizing matters more than it looks: the first cut shipped at `0.04` and was **inaudible**, six
consecutive enemy hits spanning ~1.2 semitones in total. Two entry points apply it:

* **Spawned one-shots** get it by default — `play_sfx` / `play_2d_sfx` call `vary_pitch` on the
  caller's `pitch_scale` unless the caller passes `vary = false`.
* **Node-driven world sites** — the places that retrigger a persistent authored `AudioStreamPlayer`
  living in a scene (gunfire, the dry-fire click, the shell tink, the reload, an NPC death cry, the
  explosion, the flashlight click, a radio's on/off switch) — call
  **`AudioManager.play_varied(player, base_pitch := 1.0)`** instead of `player.play()`.

### The boundary is DIEGETIC, and it is the whole design

Variation exists so a sound that is **happening in the world** stops reading as one sample
machine-gunned at the player. It is **not** applied to anything the world isn't making, at any value
of the knob:

| Varies | Stays exact |
| --- | --- |
| Footsteps, landings, gunfire, reloads, shell tinks | **Menu / UI chrome** — hover, click, open, back, tab, commit, the refusal buzz |
| Bullet + melee impacts, explosions, the bullet whiz | **Non-diegetic stings and HUD cues** — the MGS "!" alert, the aim/charge sting, the incoming-shot beep, the hitmarker ding |
| Gore splashes, cripple cracks, the dog's bite | **Reward jingles** — the cha-ching bounty, the pickup chime, the applause cheer, the station-terminal chirp |
| **Every voice** — the NPC hurt cry (fires on *every* damage tick), death screams, falling yells, a dog's yap / purr, a claim bark | **Music, ambience and every loop** — the score, `AmbientSound`, the radio's track, the CRT hum + fan, the falling-air / slide wind, the held-prop pant, the heartbeat |
| Doors, switches, levers, destructibles, thrown props | |
| | **Music, ambience and every loop** — the score, `AmbientSound`, the radio's track, the CRT hum + fan, the falling-air / slide wind, the held-prop pant, the heartbeat |

**Voices are in, and the MULTIPLY is what makes that safe.** A creature with an authored voice keeps it:
`Throwable.sound_pitch_mult` is the animal's rolled **body size** (`RandomSize.pitch_mult_for_size` writes
it, and `SpawnOnDestroy` propagates it so a dog crate barks at the size of the dog inside), and because the
variation multiplies, that base stays the **centre** of the roll. A big dog still yaps low; it just never
fires the identical sample twice. A few percent is nowhere near the pitch ratio that separates a small dog
from a large one.

The highest-value voice site is `scripts/npc/damage.gd`: it fires on **every damage tick**, so a shotgun
blast is one yell per pellet and a burst is one per round. Unvaried it was the loudest machine-gun in the
mix.

Three different mechanisms hold that line, and it is worth knowing which is which:

1. **`MenuStyle` never routes through `AudioManager` at all** — its pooled voices are a separate seam
   (see below), so menu chrome is structurally out of reach. `_pitch_for(kind)` is written verbatim.
2. **Non-diegetic one-shots pass `vary = false`** to `play_sfx` / `play_2d_sfx`. Note the flag is
   *never* inferred from 2D-vs-3D: the bullet whiz, the ram thud and the grapple all play 2D and *are*
   world sounds, while the "!" sting and the cha-ching are not.
3. **Loops and stings just call `player.play()`.** A bed restarts itself on `finished`, so a per-play
   roll would re-tune it every lap.

The reasoning behind each exclusion differs, which is why the rule is "is the world making it?", not
"is it loud or repeated?": on UI a random wobble reads as a **defect** rather than as life; on a melodic
jingle it simply sounds out of tune; on the hitmarker the pitch *is the data* (it deepens with the
target's remaining HP), so a jitter would blur the exact signal the cue exists to carry; and on a
**voice** it changes *who is speaking*.

That last one is the sharpest, and it is where the exertion/identity split bites, because some voices
already carry an **authored per-creature pitch**:
`Throwable.sound_pitch_mult` is the animal's rolled **body size** (`RandomSize.pitch_mult_for_size`
writes it, and `SpawnOnDestroy` propagates it so a dog crate barks at the size of the dog inside). The
global variation *multiplies*, so applying it there would re-roll how big the creature sounds every
time it speaks — actively fighting the system that exists to pin that down. A pain cry carries no such
multiplier, which is exactly why it is free to vary.

The highest-value site of all is `scripts/npc/damage.gd`: it fires on **every damage tick**, so a shotgun
blast is one yell per pellet and a burst is one per round. Unvaried it was the loudest machine-gun in the
mix.

`vary_pitch` **multiplies** the caller's pitch rather than replacing it, which is what makes it safe
across every world site: the ammo-driven fire sag (`fire_pitch_*`), the HP-driven enemy-hit deepening
(`enemy_hit_pitch_*`), and the older, wider per-site spreads (player + NPC footsteps, landing thump,
bullet impacts, muzzle whiz, throwable impacts, blood drops) all still read as authored. It is also
floored at `AudioManager.MIN_PITCH` — `pitch_scale` 0 never advances a stream, so `finished` never
fires and a self-freeing one-shot would **leak**, not merely go silent.

Two ways to regress this: a new **world** site that calls `player.play()` directly (it sounds fine
alone and only reads as fatiguing once it fires two or three times a second), or a new **UI/sting**
site that forgets `vary = false` (which is the louder mistake — a wobbling alarm or menu blip reads as
broken). `tests/test_audio_pitch_variation.gd` pins the multiply-not-replace contract, the
`vary = false` exact passthrough on both helpers, the vary-by-default asymmetry, the zero-spread
passthrough, and the never-returns-zero floor.

`DeathMix` (`scripts/player/death_mix.gd`, a code-built child of the Player) owns the
death cinematic's MIX. The cinematic used to fade the global **Master** bus to silence;
because every bus chain in Godot terminates at Master, that left no route for a sound to
survive the player's own death. The duck therefore moved down onto the four **world** buses
(`GameSettings.player_feedback.death_cinematic_buses` = `ambient` / `sfx` / `music` /
`voice`, which covers all authored audio since `radio` and `station_music` send into
`music`, `ambient_bed` into `ambient`, and the diegetic `world` trunk — fed by `speaker`
and the `gunshots` echo — sends into `sfx`), and the death sting plays on `sting` — a bus
deliberately absent from that list, sending straight to Master. The Player's cinematic
reaches it through exactly four seams (`begin` / `set_world_duck` / `restore_world` /
`begin_revive`), one on each
death-exit path; `restore_world` iterates the designer's bus list rather than a captured
snapshot, so adding a bus can never leave one death mode stale. No level is captured
anywhere: every write recomputes from `Settings.current_bus_db(bus)` scaled by one duck
factor, which is what makes the "re-trigger snapshots the ducked level and ratchets the mix
quieter" bug inexpressible. **Consequence for authoring: an `AudioStreamPlayer` with no
`bus` set lands on Master, which is no longer ducked — it plays at full volume under the
death card.** `tests/test_audio_bus_hygiene.gd` guards the scene side; every `.new()` site
already assigns a bus.

**Menu audio is a SEPARATE seam from `AudioManager`, and deliberately so.** Every menu cue plays on
`MenuStyle`'s OWN pool of `AudioStreamPlayer`s, not through `AudioManager.play_2d_sfx` — because
`AudioManager` parents its one-shots to the root at the default process mode, and menu cues have to
survive a **tree-pause**: the station screens (shop / heal / atm / respec / level-up / chip-install /
chess) are real-time themselves, but one opened out of a **conversation** runs under `DialogueManager`'s
pause — as does anything reached through `FreezeFrame` on death — where an inherit-mode player's `play()`
is **silently dropped**. `MenuStyle` therefore owns `_hover_player`, `_click_player`, `_denied_player`
and a **four-voice semantic pool**, all `PROCESS_MODE_ALWAYS` and all on the `sfx` bus (so the SFX
slider applies, and so the death cinematic's world duck covers them). Four voices because the 1.7 s open
sting can still be ringing while the player tabs and then commits — one spare keeps the long cue from
being stolen mid-ring; hover, click and denied keep single self-cutting voices on purpose, which is the
desired behaviour for a repeated blip (and, for the denial, stops a spam-clicked refusal stacking four
overlapping buzzes and then stealing the open sting's voice).

**Refusal is a first-class cue.** `denied` answers "the game did not do what you asked": can't afford it,
out of stock, bag full, nothing to withdraw, an illegal move, a failed save. It is the only slot with a
**derived fallback** — leave `denied_sound` null (as the shipped skin does; there is no ninth clip) and
`_stream_for` resolves it to `back_sound`, detuned by `denied_pitch_scale`. That derivation is deliberate
policy: a refusal cue that only exists once an artist ships a clip is a cue nobody wires, and until it
existed roughly twenty screens gated a commit on a success bool and answered the false branch with
silence — a refused purchase was indistinguishable from a dead button. **`denied` is never a substitute
for `back`**: back means "this closed / I honoured your cancel", which is exactly the confusion the
denial ends. `pitch_scale` is written on *every* play, not only the pitched one, because pool voices are
reused round-robin and a stray detune would silently transpose the next cue.

The vocabulary lives on `MenuSkin` (one `AudioStream` slot per semantic event, all optional), and screens
call `MenuStyle.play_open/back/tab/select/commit/denied/hover/step/slider_step` — never a preload. Three
invariants:
(1) **no cue may be reachable from a `_ready()`** — every screen autoload builds at boot, and the
structural backstop is that every `play_*` early-outs while the pool is empty, so anything firing before
`_build_sound()` is silent by construction (which is also why audio construction must stay OUT of
`rebuild()`, whose bare-`.new()` test path never calls `_ready`); (2) **no double-sounding** — every
`BaseButton` under a menu root is auto-click-wired by the `node_added` hook, so a button with a more
specific meaning must be re-pointed or muted through `MenuStyle.set_button_sound`, the one sanctioned
way; (3) **throttles use `Time.get_ticks_msec()`, never a delta**, since a paused tree freezes delta.
Three seams carry the whole system: `ModalMenu.grab_mouse/restore_mouse` cue open/close for all eight
standalone modals (they sit *past* every refusal guard, unlike the `closed` signal, which fires even for
a screen that never appeared), `PlayerMenus.enter/leave` distinguish a cold group open from a sibling tab
swap, and `InputManager.close_all_modals` holds `MenuStyle.set_quiet` so the death/quickload sweep does
not fire a wall of close cues at once.

Two things those seams cannot reach, so they are covered explicitly. **Non-`BaseButton` surfaces** get
`MenuStyle.play_hover(id)` — the same throttles the auto-wired button hover uses, exposed for a widget
that paints its own hover state; `GridInventoryView` (the shared surface of backpack / loot / shop, which
contains no button at all) uses it plus its own lift / land / refused-landing / rotate / cancel cues, and
deliberately stays silent on everything it merely *reports* — a click, a right-click drop and a
cross-grid transfer are the host's to sound, because only the host knows whether the action was honoured,
refused, or cost money. And **the pairing rule is enforced, not remembered**: `if act(): play_commit()
else: play_denied()`. A branch-gated success cue with no denial anywhere in its function is a *silent
refusal path*, scanned as audit Domain E
(`addons/cybersunday_tools/panel_audit/scan_menu_sound.gd`), reported by
`godot --headless -s scripts/tools/menu_sound_debt.gd`, and held at **zero** by
`tests/test_menu_sound_coverage.gd`. An unconditional cue at a function's base indent is exempt by
construction — it already fires on every path — which is what lets a shared success tail
(`ChipInstaller._grant`) and a never-gated act (StartMenu's run stamp) pass with no exemption list.

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

**The PIN kill — a lethal thrown blade staples the struck limb to the wall.** A thrown weapon that opts in
(`WeaponData.thrown_pins_body_part` → `Throwable.pins_body_part`, shipped ON for `melee.tres` only) does not add a
new object to the death: it **re-routes one of the six limbs that already fly**. The decision cannot be passed as
an argument — `Throwable._try_damage_character` → `Character.take_damage` → `_begin_death` → *(a SceneTree timer,
for the NPC death-freeze beat)* → `_complete_death` → `gore()` → `GoreSpawner` is a dozen signatures across a timer
boundary — so it is **stashed**, the `NPC.mark_silent_takedown` idiom: `Character.mark_pin_hit(contact, dir, blade)`
immediately before the lethal hit, `take_pin_hit()` consuming it in `GoreSpawner._resolve_pin`. ⚠️ **The marker
carries an ALREADY-PROBED wall**, found by `Throwable._probe_pin_surface` inside `body_entered`, and that split is
mandatory rather than tidy: `PhysicsDirectSpaceState3D` is only valid to query *during a physics frame*, and the
death burst is not one — an NPC's `gore()` runs off the death-freeze `SceneTreeTimer`, whose timeout lands on the
idle frame, where `intersect_ray` returns empty however solid the wall is. The first cut of this feature raycast
from `GoreSpawner` and was therefore inert in every kill, with every other seam correct; `_is_airborne` was the
precedent proving a ray query from `body_entered` is fine. That marker is
**per-life state and is cleared in three places** — the consuming read, `take_damage`'s survive branch (a non-lethal
knife hit must not pin on some later death), and `Character.reset_for_reuse` (a pooled body must not pin from its
previous life). Four contracts beyond that:
(1) **The limb flies on rails.** Both collision layers and gravity go to zero for the whole pin, so it travels the
exact ray the probe already cleared and stops by arithmetic (`PartPinner.reached`, a half-space test that survives
an overshoot), never by collision. That removes self-damage on arrival, the need for collision exceptions against
the five limbs bursting beside it, and tunneling — and it makes the seated trophy **inert**: no NPC line-of-sight
blocking, no shoving the player, nothing for an editor-baked navmesh to be wrong about.
(2) **Nothing unfreezes in place.** Both the limb and the blade are deliberately buried in static geometry;
clearing `freeze` on an overlapping body lets solver depenetration fire it across the room, so `_release_pin` and
`Throwable.unpin` restore a clear pose *first*.
(3) **The blade holds the limb up.** Pull the knife (`PickupRay._pick_up` unpins before it snapshots physics state)
and the limb drops off the wall — polled in `_physics_process`, because the blade can also leave by being freed.
(4) **The trophy belongs to its wall.** Gore is parented under the tree root and survives a level swap, which frees
only the `Level` child — so a seated pin watches the collider it is stapled to and takes itself with it.
Geometry and policy are pure statics in `PartPinner` (`scripts/effects/part_pinner.gd`, pinned by
`tests/test_part_pinner.gd`); it picks the limb by **nearest live part centre**, not `Character.body_part_at`,
because that classifier has no left/right and desyncs by ~0.28 m on a seated actor. Feel numbers: the
`pinned_part_*` group on `EffectsSettings`, which also quiets the rest of the burst on a pin kill — the staple only
reads if it is the only thing moving. Not persisted in either save tier, like all gore.

**The thrown-weapon tracer — a white streak, drawn OUTSIDE the prop it follows.** EVERY weapon
(`WeaponData.thrown_trail` → a `ThrowTrail` child stamped on the drop by `WorldItem._make_throwable`; the flag
defaults **ON**, so the whole roster streaks and the field is a per-weapon opt-OUT) drags a tapering, fading
ribbon behind it for the length of a real throw. It shipped knife-only, on the theory that a tracer on a tossed
gun would read as a bug; it reads as a throw, so it went game-wide. Four contracts carry it, and three of them
are counter-intuitive enough to be worth stating:
(1) **The arm is a THROW, not a speed.** `Throwable.mark_thrown_for_trail` is called only from the `is_throw`
branch of `PickupRay._release` (and the grapple fling) — the same decision that selects the throw sound and the
thrown facing — so a tap-drop, a max-hold auto-drop and the forced death/quickload release never streak, however
fast the prop is moving. It is read back through `is_trailing()`, **duck-typed** by the component, because
`Throwable` sits on the actor parse path via `Character` and a mutual `class_name` edge there is a parse cycle.
The arm survives a bounce (a knife skipping off a wall is still in flight); what stops the DRAWING is the
component's own speed gate, after which the tail ages out. The arm itself is released when the prop comes to rest
(`sleeping`, the engine's own at-rest signal — a bare speed test would fire at the apex of a vertical throw).
That release is not tidiness: without it a thrown-and-abandoned knife stays armed for the level, and the next
thing to shove it — a blast, a grapple reel-in, a fall off a ledge — draws a streak with no throw behind it,
which is exactly what `require_thrown` promises cannot happen.
(2) **The ribbon is parented to the tree ROOT, never under the prop.** Two sweeps over a `Throwable`'s descendants
would otherwise dress it as part of the prop, both through `TalkHelpers.collect_meshes` — `_setup_overlay_chain`
(the outline ring's tint duplicate **and** the `InkOutline` actor-mask bit, i.e. two extra scene renders of the streak)
and `_set_carried_transparency`. Child `_ready` runs before the parent's, so an eagerly-built ribbon would always
be there in time to be caught. (`Ps1Applier` is *not* one of them — its walk returns on `node is Throwable` before
recursing — so do not cite it as a reason here.) Root-parenting also puts the geometry in plain world space against an identity
transform, which is why this effect needs no `top_level` and no `reset_for_reuse` (contrast `NpcLaser`).
(3) **Its material must stay transparent.** `TRANSPARENCY_ALPHA` with the default depth-draw mode writes neither
depth nor normal-roughness, and that — not any render layer — is the only reason `ink_outline.gdshader`'s edge
detect cannot see the streak and ring it in black. It is the same trick `bulletmat.tres` plays for bullet tracers.
(4) **Two independently-sensible tuning numbers gate the whole effect, and they live in different resources.**
`EffectsSettings.throw_trail_min_speed` is a floor the prop must be moving to lay streak; `PhysicsDamageSettings
.pickup_throw_impulse` (12 m/s) is the speed `PickupRay._release` sets on an ordinary throw outright. While the
effect was knife-only the two had slack — the knife's `2.5×` `thrown_impulse_mult` launches it at ~30 m/s — so
the floor could drift anywhere under 30 without anyone noticing. Game-wide, the floor has to stay under **12** or
every weapon except the hurled knife throws bare, which looks like "the feature was reverted" rather than like a
mistuned number. `tests/test_managers_tuning.gd` pins the ordering across both resources. (The arc itself is safe
once the release clears the floor: a thrown prop speeds UP, gravity adding vertical speed faster than drag eats
the horizontal, so the streak never gaps mid-flight.) A related non-issue, worth recording because it looks like
one: guns do not set `thrown_faces_travel`, so a thrown gun TUMBLES — but `_make_throwable` stamps the
`ThrowTrail` at the body **origin** with no offset, and a sample point on the axis of spin traces a smooth line.
Only a hand-placed, deliberately offset trail (a blade tip) needs the prop's facing pinned.
Geometry is pure statics on the component (`taper` / `fade` / `side_vector` / `width_compensation`, the last being
the `GunFX.spawn_tracer` never-thinner-than-authored perspective clamp); feel numbers are the `throw_trail_*` group
on `EffectsSettings`. Pinned by `tests/test_throw_trail.gd`, which drives a real thrown `Throwable` in-tree
because, like the PIN kill above, the failure mode of this class of effect is "every piece correct, the chain
never runs", and walks the whole weapon-item roster through `WorldItem.build` so a drop that stops getting the
child is a red test. Not persisted: a streak is a moment, not world state.

**Gore carries an owner, and the player's revive undoes its own.** `CHECKPOINT_RESPAWN` brings the player back
in an **untouched world** — which is right for enemies and loot, and wrong for the player's own remains: without
a sweep you are revived standing in your own guts, and every further death piles on another burst. So
`Character.death_gore_group()` is an overridable tag: the base (and so every NPC) returns `&""` and tags
**nothing**, because NPC gore is world dressing that must stay where it fell; `Player` returns
`Groups.PLAYER_GORE`. `GoreSpawner` stamps that group onto everything it puts in the world — meat chunks, body
parts, the floor splat, the ragdoll/loot corpse — and `clear_tagged_gore()` (facade:
`Character.clear_death_gore()`) frees exactly the tagged nodes, so a firefight's other corpses survive the
revive untouched. The tag also **propagates down the secondary-gore chain**, which is the part that is easy to
miss: a gib bleeds when it pops, so `bloody_mess.gd` inherits the tag off the gib body it hangs under and passes
it to `BloodDropEmitter` → `BloodDrop` → the landed decal — a player gib that pops minutes later still leaves
tagged stains. `Player._respawn_at_checkpoint` calls the sweep **before `_fade_in_from_black`** (still fully
black, so nothing is seen to vanish), gated on `GameSettings.effects.clear_player_gore_on_respawn`. The
`RELOAD_*` death modes need none of it — they rebuild the scene. Deliberately **not** tagged: the death purse
`MoneyBag`, which is the wallet you must walk back and reclaim. Pinned by
`tests/test_player_death_gore_cleanup.gd`.

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

**There is ONE outline technique and it runs as TWO passes on one node.** Both live on `InkOutline`
(`scripts/effects/ink_outline.gd`, a quad childed to the player camera in `camera_rig.tscn`), and
neither is authored per mesh:

- **The world's INK** — `resources/shaders/ink_outline.gdshader`, a screen-space depth + normal edge
  detect over whatever that camera renders. This is the art style, and it is per-*camera*.
- **Everything else's RING** — the same shader's second half, dilating a flat ID buffer
  (`resources/shaders/ink_tint.gdshader`, rendered into a tint `SubViewport`) into a constant-PIXEL-width
  coloured outline. NPCs, props, gibs, corpses, the look-at hover and the first-person view model all
  wear this and nothing else. A consumer opts in by stamping an ID —
  `InkOutline.apply_tint(root, id)` / `apply_tint_mesh(mesh, id)` — never by building a material.

**The inverted hull that used to own actors is DELETED (2026-08-27).** `resources/shaders/outline.gdshader`,
`resources/materials/outline_black.tres` and `TalkHelpers.make_outline_material()` are all gone, on the
brief "replace all the shitty existing outlines with the new outline shader we added for enemies — this
includes view models and everything". The reasons were already on the record: a constant-screen-width
shell's WORLD thickness grows with distance until it out-thickens the ~10 cm Lego limbs and shatters
into confetti (which is what retired it for NPCs on 2026-08-25); it costs a second draw call per mesh;
it contends for the ONE `material_overlay` slot per mesh, which is why the look-at highlight needed a
stash-and-restore dance; and being a transparent-pass material it wrote no depth, so the actor mask got
coverage it could not place in space. The ring has none of those properties. The hull was never applied
to the WORLD either, and would not have been: it shatters along the unwelded func_godot brush mesh's
hard edges instead of forming a silhouette, contends with `ps1_applier`'s surface overrides on every
piece of level geometry, and fills the screen with black when the camera stands inside an extruded room.
Borderlands' own ink was a post-process filter, which is what the screen-space pass is.

**Actors are EXCLUDED from the ink, and the exclusion is the load-bearing part.** An actor's opaque
body is a depth discontinuity like any other, so the edge detect draws a line straddling its
silhouette — which lands half on the actor's own outline and half on the world, reading as a smeared
second outline hugging the clean one (the round-2 playtest complaint; a first attempt that merely made
the *resting* rims transparent still double-lined the coloured signal rims). It is also the wrong LOOK:
the ink's crease treatment on small organic bodies reads scribbly next to a clean constant-width line.
So everything ringed also renders on the reserved `InkOutline.ACTOR_INK_MASK_LAYER` (render layer 20), the
bit stamped inside the same overlay walks that dress actors — `Character._apply_overlay_to_meshes`,
`NpcOutline.apply_part_overlays` (BodyModelSwap resets `layers` on spawned parts, so the part walk
must restamp), `Throwable._setup_overlay_chain`, `body_part_gib`'s strip pass,
`BodyModelSwap._apply_actor_outline` and `ExplosionMesh._ready` — which means body
swaps and rebuilds re-register automatically. `InkOutline` renders that layer plus the view-model
layer into a mask `SubViewport` sharing the main world (camera-synced each frame, clear-color
environment per the godot#84930 sky-under-transparent-bg lesson), and the shader discards any pixel
the mask covers. A new actor path that dresses meshes WITHOUT those walks gets inked over its ring with
no error anywhere — that is the regression to watch.

**The ring and the stamp are one contract**, which the fifth stamper exists to make unbreakable. The
player's own first-person body had NEITHER of them until 2026-08-15: `Character`'s walk is scoped to
`mesh`, and the Player's `mesh` resolves to the `GunMesh`, so the `FirstPersonLegs` rig — a sibling
subtree childed straight to the Player — was outside the contract entirely and wore the WORLD's ink
line while every NPC beside it wore its own. Stamping the mask bit alone would have left it with no
outline at all, so `BodyModelSwap` owns both halves behind one designer switch (`actor_outline`,
default OFF because on an NPC the outline belongs to `NpcOutline`'s disposition colouring). The ID it
stamps follows what the rig IS: a rig forced onto `view_model_layer` takes `TINT_ID_VIEW_MODEL` (the
same slot the weapon in your other hand wears), anything else takes `TINT_ID_NEUTRAL`. It applies
inside `_rebuild`, beside `_apply_cast_shadow` / `_apply_view_model_layer`, because that rig
re-instances its parts on any model reassignment — and the duplicates die with the parts, so a stamp
applied from OUTSIDE is silently lost on the next appearance swap.
⭐ **The dissolve is the one place the ring is measurably WORSE than the hull, and it is accepted.** The
hull carried a per-material `outline_color.a`, so `BodyModelSwap` could fade a part's outline
continuously with `body_transparency` / `arm_transparency` / `leg_transparency`. A ring's colour comes
from a global LUT and its buffer's alpha channel is COVERAGE, not opacity, so there is no per-instance
alpha to turn down. `_apply_outline_visibility` therefore SWITCHES the duplicate off at the halfway
point of the dissolve (`InkOutline.set_tint_visible`). A hard cut at half-dissolved beats the
alternative the original export was added to prevent: a solid black silhouette of your own chest
hanging under the camera after the chest itself has faded away.

**The view model is the third shape of the same contract: excluded by LAYER, not by stamp — so its ring
has to stand alone.** The gun renders on `ViewModelCamera.VIEW_MODEL_LAYER`, the mask camera culls that
layer, and the ink is discarded over the weapon on purpose. `GunVisuals.dress()` stamps
`TINT_ID_VIEW_MODEL` on every gun mesh — of the rig and of each swapped-in weapon model — skipping the
Muzzle subtree (the flash stamps its own) and any `outline_skip_name_hints` match, which is why it uses
the non-walking `apply_tint_mesh`. Miss a mesh and it has NO outline at all.
Two geometry facts make it work, and both are easy to break:
- **The gun is NOT drawn by the main camera.** `Head._setup_view_model_camera` sets
  `ViewModelCamera.enabled = true` unconditionally (the `@export` default of `false` is dead for the
  player — the node is code-built, so there is no `.tscn` to check), and that pass strips
  `VIEW_MODEL_LAYER` from the main camera's `cull_mask` and composites its own SubViewport over the
  frame. The TINT camera, meanwhile, clones the MAIN camera. They line up only because the gun camera
  copies fov/near/far verbatim and **`ViewModelCamera.fov_offset` ships `0.0`** — a coincidence of
  tuning, not a construction. Give that offset a value and the weapon's outline slides off the weapon
  with no error anywhere; `tests/test_ink_outline.gd` pins the default at 0. The classic "longer gun"
  FOV needs its own view-model tint viewport first, because one camera cannot hold two projections.
- **The view-model ID is exempt from the ring's occlusion test** (`id == 10` in
  `ink_outline.gdshader`). The main depth buffer contains no gun, so the depth behind the weapon would
  read as "the gun is hidden" every time you walk up to a wall, and the outline would blink off while
  the weapon is plainly still drawn on top.
History worth keeping: from 2026-06-03 to 2026-08-18 the gun's hull shipped at `outline_width 0.02`, a
metres-era leftover that measured FIVE rim pixels on a whole pistol (988 at the `2.0` it was eventually
corrected to). Nobody noticed for two months because the weapon had no other outline to compare against.
A constant-pixel ring cannot have that failure mode.

**…but the layer is not actor-only, and the sixth stamper is the case that says so.** `ExplosionMesh`
(the flash on every explosion, bullet-impact spark, paint pop and muzzle flash) builds an OPAQUE
emissive sphere — a `StandardMaterial3D` with transparency disabled, so its alpha pulse never reaches
the blend state — which meant it wrote depth like a wall and the edge detect ringed every blast in
black (reported 2026-08-16). Nothing could have reached it either: an `Explosion` is spawned under the
SCENE ROOT, not under any actor's `mesh`. It now stamps the bit in its own `_ready`, unconditionally.
The half-set failure reads differently here than it does on an actor: a mesh carrying the bit with no
ring is asking for NO line at all, which is wrong for a body and right for light — so `has_outline`
stays the flash's only line (OFF for a blast, ON for the muzzle flash, which then wears
`TINT_ID_NEUTRAL` like everything else black). Read
`ACTOR_INK_MASK_LAYER` as "the ink does not own this pixel", and the rim-plus-stamp contract as the
rule for ACTORS specifically.

**The mask knows how far away its actors are, and that is what stops the ink reporting people through
walls.** The mask camera renders only actors, so nothing in that viewport can occlude them: a masked
actor behind a wall used to stamp its full silhouette into the mask anyway and bite that shape out of
every ink line it overlapped — clean person-shaped holes punched through stair nosings and building
corners with nobody visibly there. `resources/shaders/actor_mask_resolve.gdshader` is a second quad
parked *inside* the mask viewport that reads that viewport's own depth buffer and stamps it into the
mask's colour (`G` = the actor's distance, log-encoded across `MASK_DEPTH_NEAR..FAR`; `B` = "this
pixel's depth is mine"; alpha stays coverage). `ink_outline.gdshader` compares that against the depth
of what the main pass actually draws at the same pixel, per-pixel, so a body half behind a railing is
handled a pixel at a time. Three things make it work and each is a trap if changed:
- The resolve quad sits on `InkOutline.MASK_INTERNAL_LAYER` (render **bit 21**, above the twenty a
  default `cull_mask` carries). The mask viewport shares the main `World3D`, so anything visual inside
  it registers with the MAIN scenario too — on an ordinary layer this quad paints raw depth-encoding
  colour over the whole game.
- The depth is a NUMBER in an sRGB colour target. It survives only because the resolve shader
  pre-compensates for that transfer and `_build_mask_environment` pins the mask camera to the LINEAR
  tonemapper at exposure 1 / white 1 with glow and adjustments off. Re-grade any of that and the
  comparison silently starts answering wrongly. It is packed across TWO channels (G coarse, R fine,
  decoded `G + R/255`) because one 8-bit channel spends a step every ~3% of the distance — which alone
  meant an NPC had to stand a full metre behind a wall at 6 m before the ink noticed, the reason hidden
  NPCs kept showing faintly indoors. That pack is only sound because the write path is exact:
  `to_target()` inverts the target transfer, so a value lands as `round(v * 255)/255`.
  Calibrated with `scripts/tools/__ink_gap_probe.gd`, which sweeps actors at increasing clearances
  behind one wall and diffs each against a reference: **detection now holds down to 2 cm of clear air at
  6 m**, against 1.0 m before the split.
- **Coverage without depth still has to be resolved.** Any masked pixel the resolve pass cannot place
  in space falls into the "cannot vouch → keep suppressing" branch, so an occluded actor stops punching
  a solid hole and starts punching a person-shaped *outline* instead ("an O shape around it"). The
  historical source was the inverted hull — a transparent-pass material writing no depth, measured at
  23 px of mask alpha against 19 px of mask depth on a real box. That shader is deleted and the ring's
  duplicates are opaque, so the common case now agrees by construction, but the same shape still arises
  from a `transparency`-faded prop, a coarse-LOD silhouette or an actor at the edge of the encoding
  window — so the ink shader still SEARCHES outward (`mask_rim_search_px`, 12 px; five cheap gate taps
  decide whether the search runs at all). That search must stay on the INK side: the resolve pass can
  only widen the mask's depth by widening its alpha, and the mask's alpha is coverage, and coverage is
  suppressed ink — repairing the ring there buys a bare halo around every VISIBLE actor instead.

Every case the resolve pass cannot vouch for — a `transparency`-faded prop, a rim wider than the
dilation, an actor past the encoding window — keeps the old unconditional suppression, so the failure
direction is always "suppress", never a doubled outline. `occlusion_aware_mask` is the A/B switch;
`scripts/tools/__ink_occlusion_shots.gd` shoots both states of a purpose-built scene. Two earlier
attempts are recorded in `InkOutline`'s header and must not be rebuilt: stencil on the ink quad (a
silent no-op — `depth_test_disabled` drops the depth-stencil attachment) and a CPU raycast cull (it
broke the world ink outright).

**That mask is a SECOND SCENE RENDER, and it has to stay a cheap one.** Every ringed thing in a
level carries the mask layer — each NPC body part, each `Throwable` prop, the gibs, the view model —
and each draws base + flash `next_pass`, so the mask pass re-pays the per-object cost of
a prop-heavy level. The first build did that at the frame's full internal resolution *and* inherited
`rendering/scaling_3d/scale` (2.0) from project settings, so it was rendering 1584×888 — a 4× supersample
of an image nobody ever looks at — with a per-viewport shadow atlas and full mesh detail. That is what
made the game crawl the moment the exclusion shipped. The shader reads this texture only as coverage,
so `InkOutline._strip_mask_viewport` refuses the supersample and every AA / TAA / debanding /
occlusion-culling / shadow-atlas default — a straight 4× with nothing given up. **Anything that puts
those frills back, or lets the viewport inherit the 3D supersample again, buys nothing visible and
costs real frames.**

**The mask's RESOLUTION is the one saving here that is not free, and the suppression window must never
be derived from it.** The shader kills ink within half a line-width of an actor's silhouette — the line
that would otherwise straddle it, i.e. the doubled outline the hull already owns — and nothing past
that. A version that instead widened its taps to a whole mask texel (a `mask_texel` uniform, since
removed) erased world ink **3 px out from every actor** at a half-resolution mask: a bare ring that does
not shrink with distance, so a far-off NPC sat in a void larger than itself and you could pick people
out by it. The honest version samples the mask `filter_linear` — a coverage *field* whose 0.5 crossing
is the true silhouette, sub-texel — and sizes suppression off `width_px` alone, so nothing
resolution-derived is pushed to the shader at all (`tests/test_ink_outline.gd` pins that the uniform set
is identical at every `mask_resolution`). Measured halo, ink-loss bounding box against a reference frame
with the mask off: **1.0 → 1 px, 0.5 → 2 px, 0.25 → 2 px but under-suppressing.** `mask_resolution` ships
at `1.0` for that reason; it is a real authorable perf trade, just not a free one.

**Level geometry inks as ONE solid, not as its pieces — the seam merge + the junction dial
(2026-08-18).** A blockout or brush level is many boxes, and the user wants the union outlined, not the
parts. What the ink on the shipped map actually is was measured three ways (per-pixel raycast attribution
over 72k ink px, a sub-pixel-motion flicker sweep, and a parse of `maps/alive.map`): ~35 % silhouettes,
~34 % real creases at the level's 0.5 m module (slab-on-slab roofs and eaves, risers/treads, pilasters,
setbacks, floor/wall), ~31 % the alpha-scissor fence and trees inked wire-by-wire, and **0 px on coplanar
brush seams** — a flush or interpenetrating join has neither a depth step nor a normal change, and the
brush mesh's 816 T-junctions leave no pinholes the ink can see, with or without the PS1 warp. Two things
therefore make up "the pieces are outlined", and each got its own knob on `InkOutline`:
- **Misalignment slivers → `crease_min_feature_px`** (ships 4, 0 = off). A box a few *centimetres* out
  of line leaves a sub-pixel sliver of perpendicular face along the join — invisible in the art, a full 90°
  corner to the crease term, which had no notion of feature width — so one surface came away split by a
  faint dotted line that crawls. On the shipped map that is the 6 cm plank trims seen edge-on (470 px of
  dashed line, all gone at the default) and a 4 mm decal-plate brush; on hand-placed blockout it is every
  join. The crease is re-measured on two wider Roberts crosses whose taps sit `crease_min_feature_px` px
  either side (diagonal + axis, the weaker wins — one cross alone leaves a dotted trail wherever a sliver
  runs along its diagonal), and the result scales the narrow crease as a RATIO of it (`smoothstep(0.15,
  0.4, wide/narrow)`), never as a second absolute threshold — that version dimmed every shallow crease (a
  ramp meeting the floor, a kerb chamfer) to ~22 % at axis/diagonal screen angles, because an
  axis-aligned crease straddles both narrow diagonals but only one pair of the wide axis cross; a straight
  crease of any dihedral keeps ≥ ½ the narrow sum at every angle once the reach clears one line width, a
  sliver keeps ~0. The reach is floored at `width_px` in the shader (inside the narrow cross's own
  footprint the wide pass is only a second sampling of the same edge and thins real lines — measured
  ragged at 4 with the old ×2 units, clean at 8). Screen-space on purpose: a small real feature keeps its
  interior lines up close and loses them at distance (its silhouette stays), which is the accepted
  collateral; it only ever removes ink.
- **Piece junctions → `concave_crease_strength`** (ships 1.0 = the look unchanged). Every real "junction
  between two pieces" on a box-built level is a CONCAVE crease, and the sketch's own case — a slab lying
  on another — is inked by design at the junction. Convexity is read from the depth taps' view-space
  positions with the standard sign test, `dot(dN, dP)` (normals diverge along the offset = convex,
  converge = concave), softened over ±0.15 so it cannot pop; concave creases are scaled by the knob. 0.0
  draws only convex edges + silhouettes (a slab on a wall, a tread against a riser, the floor/wall line
  and the inside corner of an L all lose their line together — same crease), 0.4–0.6 keeps them lighter
  than edges. Measured on the porch stairs: 21.5k → 20.0k ink px at 0, every nosing kept.
- **Pieces that touch → `contact_merge_m`** (ships 1.0 m, 0 = off). The half neither crease knob can
  reach, and the one the user's screenshot was about: a flight of stairs is a stack of slabs, and every
  step drew a line. Measured on the porch steps, the risers are not visible from eye height at all — the
  raycast normal is `(0,1,0)` on both sides of each edge, so a step is a PURE depth discontinuity between
  two treads and `crease_strength = 0` left every line intact. The user's rule was "not where the two
  actually are touching", which is measurable: at an edge pixel the two taps that found it land on two
  surfaces, and `distance(pa, pb)` in view space is how far apart the pieces are along the view ray — a
  step gives its riser height (~0.95 m for the 0.5 m module, independent of how grazing the view is,
  because the far tread starts at the foot of the riser), a box on the floor its own height, a facade
  against one 10 m behind 10 m, and the sky the far plane (so a sky silhouette can never merge — that is
  why `view_pos` places a sky sample at `SKY_DEPTH` *along its own ray*). It multiplies the silhouette
  edge by `smoothstep(t, 2t, gap)`, so it only ever removes, and it measures the diagonal THAT FOUND the
  edge (the other one can lie along it and measure nothing). Measured on the street view: 117 px change
  at 1.0 — buildings, the fence and every sky edge untouched, the stair lines gone. It is the one term
  here in WORLD metres, so it does not relax with distance, and it deletes real silhouettes by design.
The user's authored look is the resting state for the crease dial, so that ships at 1.0. What none of this is:
the PS1 vertex-snap tear (measured with `Ps1Warp.cover` applied at six close viewpoints — the warp shifts
real edges by a pixel and adds no seam lines or specks), and neither knob touches the depth (silhouette)
term at all.

`tests/test_ink_outline.gd` pins the layer value, the stamp walks, the shader's mask uniforms, the
coverage-only viewport contract + mask resolution policy, the restored black rim defaults, and the seam
merge's script→shader seam plus its source rules (two crosses MIN-ed, ratio not threshold, reach floored at width_px, reach not scaled by the intensity dial, VIEWPORT_SIZE only in fragment()) and the junction dial's push + dot(dN,dP) test;
it also pins the script↔shader uniform names, whose only failure mode is a `set_shader_parameter` that
goes nowhere and a line that quietly stops being drawn.

The pass draws inside the **3D** frame (the quad is a camera child), not on the HUD `CanvasLayer`, so
the lines are posterised, ordered-dithered and grained by `post_process.gdshader` along with the world instead
of floating over it as crisp modern vector art — and when far-DOF is live (ADS only: the resting camera ships
without far blur since 2026-08-24) distant ink blurs together with the geometry it belongs to. Its strength is the live `Settings.ink_outline_intensity`
(Options → Video → "Ink Outline"), the `ps1_warp_intensity` idiom: polled each frame, 0% hides the
quad entirely so "off" costs nothing.

**The ink is fog-matched, and must stay that way.** A level that runs volumetric fog is lit BY it (TestLevel
and the other sandboxes still are; the main level dropped its fog on 2026-08-24), so there "how far you can
see" is set by fog density, not the far plane — but the ink quad renders
`fog_disabled` at 1 m from the lens, so the engine's own fog can never dim the lines (fog attenuates by
the *fragment's* depth, and our fragments all sit at 1 m). Left alone, the pass draws crisp black lines
over buildings the fog has fully swallowed — outlines advertising geometry the player cannot see (the
first playtest complaint). So `InkOutline` reads the live `WorldEnvironment`'s fog density each frame
(the `world_environment` group — the StarSky / camera_effects lookup) and pushes a matching Beer-Lambert
extinction (`fog_extinction = density × fog_match`); the shader multiplies the edge term by
`exp(-extinction × depth)`, making ink lose contrast at exactly the rate the surface it sits on does.
The `fade_start/fade_end` window is the backstop for fogless scenes — which, since the main level dropped
its volumetric fog (2026-08-24), makes that window the whole distance treatment on the main level.

### HUD ghosting — the second viewer on the HUD canvas (`HudGhost`)

`scripts/ui/hud_ghost.gd` gives the HUD CRT phosphor persistence: moving readouts drag a soft decaying
tail, and while the camera turns the whole ghost image lags a couple of pixels behind the live HUD so the
screen-locked reticle participates too. Built last in `UI._ready` (`_build_ghost`), driven once a frame
from `UI._process` right after the sway spring, scaled 0–1 by `Settings.hud_ghost_scale`
(Options → Accessibility → "HUD Ghosting"), amplitudes on `GameSettings.hud`'s "HUD ghosting" group.

**The seam is a canvas with two viewers, not a node refactor.** `RenderingServer.viewport_attach_canvas`
attaches the HUD `CanvasLayer`'s existing canvas RID to an extra offscreen `SubViewport` as well as to the
window, so the same HUD renders twice per frame with **nothing reparented** — no z-order change, no element
losing its screen sampler, and a pixel-identical HUD at scale 0 (the accumulation pass stops rendering
outright). That accumulator is `transparent_bg` + `CLEAR_MODE_NEVER`, so a `blend_mul` decay quad in its own
World2D canvas (stacking layer 0, below the HUD canvas at 1) fades what is already there before this frame's
HUD draws over it; a `TextureRect` on the HUD layer draws the result behind every readout.

**That display rect's seat is an INDEX, not a `z_index`** (`HudGhost._place_display`). It must be *below*
every readout and *above* the layer's screen-space post-process `ColorRect`, and no single z can say both —
the pass and the readouts share z 0..2. It shipped at `z_index -1`, which is below the pass, so the ghost was
INPUT to that shader rather than a HUD element. Harmless while the pass was per-pixel; a bug the moment
`post_process.gdshader` grew `lens_barrel`, because a warp MOVES pixels — the echo was bent by a world lens
its own source never sees and stood clear of its readout with the camera dead still (measured: the minimap's
ghost at the shipped 0.12). Seated after the pass, no screen-space effect can drag a HUD echo off its readout.

Four constraints are load-bearing and were each established by a rendered probe, not by reading docs:
- **Premultiplied display.** A transparent `SubViewport` stores premultiplied colour, so the display shader
  is `blend_premul_alpha`. Ordinary alpha blending double-multiplies and rims the whole HUD in dark fringes.
- **The 8-bit decay fixed point.** Multiplying an RGBA8 target by *d* each frame stalls once
  `round(n·d) == n` (~8/255), leaving a permanent faint smear wherever the HUD has ever been. The display
  shader subtracts `hud_ghost_residue_floor` and renormalises. `use_hdr_2d` is NOT the fix — an HDR render
  target with a never-cleared target hard-crashes the D3D12 backend on 4.7.1.
- **`CLEAR_MODE_ONCE`, not `NEVER`, on build / resize / re-enable.** A never-cleared target starts full of
  undefined garbage, and a resized one's contents are undefined. The stretch aspect is `expand`, so the
  canvas size is not a constant and the accumulator re-matches it every frame.
- **Opt-out is `visibility_layer`, and it carries to children.** The accumulator's `canvas_cull_mask` is
  bit 1, which every `CanvasItem` defaults to — so a HUD element is captured *by default* and runtime-built
  children (a toast, a rebuilt HP segment, a new minimap glyph) ghost with no wiring. Moving an item to
  bit 2 keeps it on screen (the window's mask is every bit) and takes it and its whole subtree out of the
  capture.

**The trail is a colour ramp, not a faded copy.** The buffer's alpha *is* each trail pixel's age (every
frame multiplies the whole buffer down), so the display shader un-premultiplies the source colour and uses
that age to look up `HudSkin.ghost_gradient` — cyan when a pixel has just left the HUD, travelling through
blue and violet to magenta as it dies. A red HP bar and a gold money readout therefore leave the SAME
coloured trail, which is what makes it read as a signal artefact instead of smudged UI. The ramp is a LOOK
so it lives on the skin (null = `HudGhost.default_gradient`); the two AMOUNTS live on `GameSettings.hud` —
`hud_ghost_tint` (how far the ramp replaces the source colour) and `hud_ghost_tail_lift` (a gamma on the
displayed alpha, below 1, without which the exponential fade makes the ramp's cold end invisible and the
gradient collapses to its hot end). The ramp's stops are deliberately bunched toward the fresh end and the
freshest stop is deliberately SATURATED: the freshest pixel is the brightest part of any trail, so a
near-white one makes the whole effect look like a translucent copy however colourful the rest is.

**The ghost rule** — an instrument readout ghosts; a full-screen wash, a world-direction annotation and the
VIEW MODEL do not — is written out at `UI._build_ghost` and applied there, in `PlayerHud._apply_ghost_rule`
and in `ViewModelCamera._attach_container`. Four things must stay opted out or they break rather than merely
look wrong: the layer's own state post-process `ColorRect` and the reticle's `BackBufferCopy` (inside the
capture the "screen" is the HUD-only buffer); the **scoped** inverting reticle, which `UI.set_scoped` drops
out of the capture for the duration of the ADS hold and puts back on the way out; and the **view model** —
the gun pass is its own camera into its own `SubViewport`, composited back through a full-rect
`SubViewportContainer` that merely *lives* on the HUD layer, so left in, the whole weapon smears behind
itself on every turn. (The display rect used to draw *under* the gun composite as a side effect of its old
`z_index -1`; seated above the post-process pass it no longer does, which is the consistent reading — the
hotbar and the corner cluster themselves draw over the weapon, so their echo does too, and masking the trail
out of the gun would mean sampling its coverage through the very lens warp the new seat exists to ignore.)

`tests/test_hud_ghost.gd` pins the maths and the two mask bits; the look is
`scripts/tools/hud_ghost_qa_shots.gd`, a windowed harness (headless never compiles shaders, and no assertion
can see a trail) that shoots the effect off / at rest / mid-turn / with each half isolated / overdriven /
after the tail should have expired.

### HUD curve — the instrument panel on curved glass (`hud_curve.gdshader`)

`ui.gd`'s `_apply_hud_curve` renders the HUD-weight carrier (`_weighted` — every corner readout: HP and
stamina bars, ammo, money, toasts, quest tracker, minimap, clock, hotbar) into a canvas-sized transparent
`SubViewport`, then composites it back through `resources/shaders/hud_curve.gdshader`, a per-axis
cylindrical warp. The panel wraps TOWARD the viewer at its edges — the inside of a curved monitor, not the
outside of a CRT bulge; one sign in `warp()` is the whole difference. Polled once a frame from
`UI._process` beside the minimap row, scaled 0–1 by `Settings.hud_curve_scale` (Options → Accessibility →
"HUD Curve"), amplitudes on `GameSettings.hud`'s "HUD curve" group.

WHAT CURVES is not a new list: it is exactly the carrier, i.e. the same moved-vs-pinned split the HUD-weight
spring already uses. The reticle, the stamina ring that orbits it, the look-at name, the directional
damage/aim arcs, the sniper glints, the hitmarker and the two scope overlays all stay direct children of the
layer and dead flat — a node that may not MOVE may not be WARPED either, for the same reason: it annotates
the aim point or a world bearing, and a displaced one lies. The post-process `ColorRect` stays out too, on
harder grounds — its shader reads `hint_screen_texture`, which inside a `SubViewport` resolves to that
viewport's own contents rather than the frame.

Five things are load-bearing and each has a comment at its site:

- **`render_mode blend_premul_alpha`.** A viewport render target stores PREMULTIPLIED alpha (measured on
  4.7.1: red at alpha 0.5 reads back `(0.498, 0, 0, 0.498)`). Compositing that under the default mix blend
  multiplies by alpha twice and lands every partially-transparent HUD pixel ~25% too dark while leaving
  opaque ones alone — dark halos on outlined glyphs, not a uniformly dim HUD, which is why it is easy to
  miss. This is the first use of that render mode in the project.
- **The bend is CROSS-COUPLED and FITTED.** Each axis is bent by the square of the OTHER (x by `y*y`, y by
  `x*x`), which is what makes it a cylinder rather than a fisheye: with only the Y term live, horizontals
  bow while every vertical stays upright. It is then divided by its own value at the extreme, pinning the
  CORNERS to the screen corners — without that, a concave bend projects to a pincushion whose corners flare
  out and the bottom-left HP bar leaves the canvas. The transparent slivers this leaves sit at the EDGE
  MIDPOINTS, which is what the bowed edge of a curved screen actually looks like; they early-out to
  transparent rather than trusting clamp-to-edge, which would smear an edge-touching readout down the border.
- **`OFF` is the old tree.** At strength 0 the viewport is freed and the carrier is reparented back onto the
  layer in its old draw slot, so a player who turns it off pays nothing — the `hud_ghost_scale` promise.
- **A `SubViewport` is not a `CanvasItem`,** so `hide_hud_for_death`'s direct-child sweep skips it and hides
  the composite instead; the panel still goes down for the death cinematic as ONE unit, exactly as the bare
  carrier did. The build/teardown paths hand the hidden state and the seat in `_death_hidden_hud` across as
  they swap, so toggling the dial mid-cinematic cannot pop the HUD back over the fade.
- **The carrier goes DEAF inside the viewport, and `UI._unhandled_input` is what un-deafens it.** The root
  `Window` pumps only its OWN `_unhandled_input` group; a nested `SubViewport` hears nothing unless a
  `SubViewportContainer` forwards into it, and this composite is hand-built, so there is none. When the
  carrier first moved inside, every child on it stopped receiving input — nothing errored and nothing
  rendered wrong, but the **hotbar died outright**: its slot keys (1-0) and the weapon wheel are
  `_unhandled_input`, and the curve defaults ON. `UI._unhandled_input` now forwards into `_curve_viewport`
  with `push_input(event, true)` and re-raises `is_input_handled()` on the outer viewport, so a consumer
  inside the curve still STOPS the event instead of letting it double-fire into gameplay. It forwards
  unconditionally — a hidden `CanvasItem` still gets unhandled input, so the death sweep never silenced the
  bar before and must not start to. Every OTHER HUD widget survived the break only because it polls
  `Input.is_action_just_pressed` (the minimap's zoom key) rather than listening; polling ignores viewports.
  **Anything parented onto the carrier that LISTENS for input depends on this forwarder.**

It composes with `HudGhost` without wiring: the accumulator watches this layer's canvas, the carrier's
children move to the viewport's canvas, but the composite is on this one — so the phosphor tail is of the
CURVED panel.

`tests/test_hud_curve_input.gd` pins the input contract behaviourally — it pushes a real key at the real
main window and asserts a real `Control` on the carrier heard it, with the curve both up and down, because
no off-tree assertion can see this class of break. `tests/test_hud_curve.gd` pins the shader by source text (uniform names, the blend mode, `repeat_disable` +
`filter_nearest`, literal defaults, the warp sign) and the structural build/teardown; the look is
`scripts/tools/hud_curve_qa_shots.gd`, a windowed harness (headless never compiles shaders, and no assertion
can see a curve) that shoots the bend off / shipped / overdriven / cylindrical / with each trimming, plus
the death sweep taking the panel down and the teardown restoring the flat tree.

### World ghosting — a temporal average of the finished frame (`WorldGhost`)

`scripts/effects/world_ghost.gd` extends the same persistence, very faintly, to the picture behind the HUD.
Built and driven from `UI` alongside the HUD ghost (`_build_world_ghost` / `_process`), scaled 0–1 by
`Settings.world_ghost_scale` (Options → Accessibility → "World Ghosting"), amplitudes on
`GameSettings.effects`'s "World ghost" group.

**The canvas trick has no equivalent here** — the world is 3D, there is no canvas to lend a second viewer,
and re-rendering it through another `Camera3D` would double the frame cost for an effect meant to be almost
invisible. So this takes the other road open to a screen-space pass:

    ACCUMULATE   A ← mix(A, last_frame, k),  k = 1 − exp(−dt / tau)
    COMPOSITE    out = now + (A − now) × strength

The accumulator is an opaque, never-cleared `SubViewport` holding one full-rect draw of the **root viewport's
own `ViewportTexture`** at alpha `k` — a SubViewport renders before its parent, so that samples the previous
finished frame, and the one-frame lag is what the ghost is made of. Writing the composite as a DIFFERENCE
rather than a cross-fade is the whole "very subtly" promise: at rest `A` converges on the frame, `A − now` is
zero, and the pass re-emits the picture unchanged — it cannot tint, darken or soften a still image.

**It is literal video feedback, and it is stable on purpose.** The composite is part of the frame the
accumulator then averages. Substituting it in gives `A' = A(1 − k(1−s)) + k(1−s)F` — a contraction for any
s < 1, converging on the un-ghosted frame. A SUM (`A' = A·decay + frame`) instead of a mix multiplies the
picture by 1/(1−decay) and blows to white within a second. `tests/test_world_ghost.gd` pins the contraction
at the shipped knobs; do not turn the mix into a sum.

Three things it deliberately does not touch:
- **The view model.** Masked per pixel by the gun pass's own alpha (`ViewModelCamera.coverage_texture` — the
  gun `SubViewport` clears transparent, so its alpha *is* the weapon's screen coverage). Verified at 0.75
  strength: the world smears and the barrel stays crisp.
- **Menus, dialogue, cutscenes.** The accumulator averages the whole window but the composite only sees the
  layers under `DISPLAY_LAYER` (5), so anything at 90+ would be in the average and not in the live sample and
  the difference would paint a ghost of the menu across the world. `WorldGhost.suppressed()` switches the
  pass off and the buffer re-clears on the way back in.
- **A still frame.** A never-cleared 8-bit buffer chasing a target stalls a few steps short (round-to-
  nearest), so the difference never quite reaches zero; `world_ghost_dead_zone` clips that per channel.
  Measured in the QA harness against a matched-gap control: 0.87/255 mean with the pass on versus 0.13/255
  for the world's own churn over the same three frames — under a twentieth of one 16-step quantisation step.

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

### AI level of detail — the tick-cadence gate (`AiLod`)

NPC count is the frame budget's cliff, and it is **CPU on the main thread**.
Measured 2026-08-13 (GTX 1660 / i5-9400F, 40 spawned NPCs): 66.7 ms/frame, and
**12.5 ms with only `npc.gd`'s own `_physics_process` disabled** — so ~81% of a
crowd's cost is this script's tick, not its ~91-node component entourage and not
navigation (NavigationServer measured 0.1–0.4 ms). RVO avoidance, `sight_range`
as a direct cost, and pathing were each measured and **refuted**; do not re-blame
them.

`AiLod` (`scripts/components/ai_lod.gd`) is the ONE gate. Contracts:

- **It sits ABOVE `_desired_velocity = Vector3.ZERO`.** A skipped tick must
  preserve last think's steering; below that line, skipping would zero the
  velocity and throttled NPCs would stutter-walk.
- **Movement is never gated.** The skip path still calls
  `super._physics_process(tick_delta)` with the REAL delta. The two in-branch
  `super` calls take `tick_delta`, never the banked think delta — handing them
  the bank would teleport a throttled NPC forward on each think.
- **The think delta is real elapsed time**, so `_fire_timer` / `_retarget_timer`
  / perception / GOAP stay in true seconds. Throttled NPCs react less *often*,
  never in slow motion.
- **`_ai_force_full_think` gates on PERCEPTION state, not on holding a
  `_target`.** `_acquire_target` locks the nearest foe by pure proximity with no
  perception gate, and `NPC.tscn` ships `sight_range = 500` — so every hostile
  holds the player as `_target` from level load, and exempting target-holders
  would switch the feature off for the whole cast.
- **No human player (INF distance) means FULL rate, not the far band** — that
  keeps `tests_soak` (which boots a playerless level and counts each NPC's
  `_stranded_cycles`) measuring what it always did.
- **Band distance uses `Groups.human_player`, not a `Groups.PLAYER` scan** — a
  recruited companion joins `&"Player"`, so a raw scan would pin every NPC near
  a wandering companion to full rate. The handle is cached; a per-tick group
  scan allocates and would refund the savings.
- **Staggered by a HASH of `instance_id`,** not a modulo: Godot hands out
  consecutive ids to a spawn wave, and `id % N` leaves that wave inside one
  narrow slice — a convoy that spikes. `tests/test_ai_lod.gd` pins the spread.

Measured effect at 40 spread NPCs: 66.7 ms → ~36 ms (15 → 28 fps). It cannot
help a crowd that is genuinely all engaging you at once, by construction.

### See-through geometry — the `SightRay` seam

**The rule:** a chain-link fence, a wire grille, a shop window or a foliage
card stops neither SIGHT nor GUNFIRE, while staying a solid you cannot walk
through. Physics knows nothing about a texture, so before this an NPC behind a
fence was as blind as one behind concrete — you could stand in plain view
through the wire and never be noticed — and neither side could shoot through it.

**The marking contract** is one group, `Groups.SEE_THROUGH`, tested by the pure
`SightRay.is_see_through_hit(hit)` (Dictionary in, bool out — unit-tested with
no physics space). ⭐**Members must be whole BODIES.** A flying round collides
with a body, and both `collision_mask` and `add_collision_exception_with` are
per-body, so there is no way to let a round through one shape of a body and stop
it on the next. Everything below follows from that constraint.

**Three consumers, three routes to the same rule:**
1. **Perception** — every "can this NPC SEE / HEAR past that?" ray is cast by
   `SightRay.cast(world, query)` (`scripts/npc/sight_ray.gd`), never by
   `intersect_ray` directly. Same query the caller built (mask, exclude,
   from/to untouched); a see-through hit does not stop the ray, the cast resumes
   `SKIN` (1 cm) past it, and what returns is the first genuinely OPAQUE hit.
   `query.from` is walked forward during the passes and restored before
   returning, so a reused query is unchanged. Callers: `Perception.can_see`,
   `can_see_node`, `_wall_between` (hearing occlusion),
   `NpcSenses._corpse_occluded`, `NpcHomeReturn._occluded`, `NPC._aim_laser_at`
   (the AIM ray — see below), and `Player._check_aim_remark`.
2. **Hitscan** — `DamageTrace.run_pellet` skips see-through hits inside its own
   pierce walk (it needs the segment bookkeeping, so it calls
   `is_see_through_hit` rather than `cast`). The pellet carries on with no
   spark, no damage and **no penetration spent** — passing a fence is not an
   overkill pierce — under its own `pass_throughs` backstop.
3. **Live rounds** — `Projectile._pass_see_through_geometry` (called from
   `_ready`, before the first physics step) adds a collision exception with
   every `CollisionObject3D` in the group. This covers the NPC ranged path,
   since enemies never hitscan.

⭐**`NPC._aim_laser_at` is on list 1 on purpose.** Its hit feeds
`NpcCombat.act_attack`'s `clear` test: an enemy that can see you through a fence
can also shoot you through it, so it must read the shot as clear and stand and
fire. Leave it on a raw `intersect_ray` and enemies see you through the wire but
refuse to shoot, and `should_chase_while_alerted` walks them in circles.

**Still BLOCKED by a fence**, deliberately: walking into it, thrown/dropped
props bouncing off it, the player's look-at interaction ray (`ray_cast.gd` — no
looting through the wire), `SilentTakedown`'s reach ray, the grapple hook, and
the navmesh bake.

**Who does the marking.** `SeeThrough`
(`scripts/components/see_through.gd`) is the prop drop-in — the `MinimapHide`
marks-its-parent idiom, extended to every `CollisionObject3D` in the subtree.
`SeeThroughBrushes` (`scripts/components/see_through_brushes.gd`) handles
func_godot map geometry, where one `StaticBody3D` carries the entire map (558
`CollisionShape3D` children on `alive.map`): at `_ready` it walks its parent's
subtree, and for each body with a `MeshInstance3D` child it collects the
vertices of every surface whose material has
`transparency != TRANSPARENCY_DISABLED`, finds each brush whose convex hull has
EVERY corner on one of those vertices (a 0.05 m-tolerant spatial hash; "every
corner" is what keeps a wall sharing an edge with a fence opaque), and
**reparents those shapes into a fresh sibling `StaticBody3D`** in the group. The
new body copies the source body's collision layer, mask and physics material, so
the fence is exactly as solid as before to everything outside the three
consumers. On `alive.map` that resolves to the 13 `fence1_a` brushes plus 4
`tree` brushes, with no authored ids and no dependence on brush order or node
names.

⭐**The split is RUNTIME-ONLY** — the component is deliberately not `@tool`, so
the saved `.tscn`, the editor and the navmesh bake never see it, and a func_godot
rebuild needs no re-authoring. Put the node under the LEVEL ROOT, never under
`FuncGodotMap`: a rebuild deletes everything func_godot generated.

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
independent. The node's THIRD authored property is
`light_volumetric_fog_energy = 0.0`, written by nobody at runtime and load-bearing:
volumetric fog is a temporally-accumulated froxel grid whose reprojection (engine
default `0.9`, unoverridden by every level Environment) carries the previous frame's
in-scattering forward in WORLD space with no per-light motion vectors, so a lamp
riding the player leaves its glow ~1.8 m behind at a sprint — a cyan will-o'-the-wisp
chasing them, with hard block edges because `project.godot` sets
`environment/volumetric_fog/use_filter=0`. Keeping the glow out of the fog costs the
meter nothing (it weighs `light_energy` / range / `visible`, never fog energy).
Designer-tunable: `LightStealthSettings.tres`, the
`CrouchLightDouse` / `PlayerLightLevel` / `ShadowVolume` `@export`s, and the
`&"stealth_light_exempt"` group (`Groups.STEALTH_LIGHT_EXEMPT`) that drops a
decorative lamp out of the meter — never tag `PlayerEmittingLight`, that is the
liability half of the trade. Code-level: the per-archetype
`Perception.light_falloff` and `min_visibility`, since `npc.gd`'s
`_build_perception()` builds `Perception` at spawn and mirrors only the
sight/hearing fields, so no scene or `NpcData` reaches them. Designer surface:
**"Light & shadow: making darkness hide you"** (under *Stealth and detection*)
in `docs/AUTHORING_GUIDE.md`.

### The flashlight penalty — the `carried_light` seam

The seam above can only ever SLOW detection: `light_exposure` clamps at `1.0` —
the same value standing under a streetlamp reads — and
`Perception.visibility_factor()` clamps its result at `1.0` too. So being lit
cancels the darkness discount but can never push a target past baseline, which
means the player's flashlight (a `Light3D` riding just off the camera) would be
stealth-free. `carried_light` is the second, independent field that charges for
it. Same one-field duck-typed shape as `light_exposure`, and the same writer:
`PlayerLightLevel._sample_carried()` stamps `Player.carried_light` (`0..1`,
default `0.0`) each throttled tick from the **`&"carried_light"` group**
(`Groups.CARRIED_LIGHT`) — scanned directly rather than off the auto-collected
list, so it works with `auto_collect` off and costs no LOS ray. Strength is the
STRONGEST member's `light_energy / carried_light_full_energy` (`1.0`), flat
inside `carried_light_radius` (`3.0` m) and `0` outside it; an *invisible* lamp
contributes nothing, which is exactly how `flash_light.gd`'s toggle (it drives
`visible`) and death switch the penalty off with no extra bookkeeping.
`scenes/player/flash_light.gd` joins the group in `_ready()` when
`reveals_you` — the same group-membership idiom as the `&"stealth_light_exempt"`
opt-out it joins instead when `reveals_you` is false, so "who feeds detection"
keeps one home. **The consumer** is `Perception`, which applies it on BOTH sides
of detection: `_effective_sight_range()` is now
`sight_range * _crouch_range_mult() * _carried_light_range_mult()` (a beacon is
spotted further off, and the two multiply, so crouching no longer hides a lit
torch), and `sense()` multiplies the DETECTING fill rate by
`_carried_light_detect_mult()` — deliberately OUTSIDE `visibility_factor()`,
which clamps at `1.0`, and gated on `seen` so it never speeds the drain up.
Both multipliers come from `GameSettings.light_stealth`
(`carried_light_sight_mult` `1.6`, `carried_light_detect_mult` `2.0`) via the
pure `carried_sight_mult()` / `carried_detect_mult()` accessors, and both read
exactly `1.0` at strength `0` — so every NPC target (no such field) and every
torch-off player detect precisely as before. Unlike the rest of this pillar it
ships LIVE rather than inert; `1.0`/`1.0` restores the free flashlight.
Covered by `tests/test_carried_light_stealth.gd`.

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
  This cue also carries the **full heal** (`heal_on_player_death`, seeded from
  `home_return_heal_on_player_death`): `restore_full_health()` tops every
  surviving NPC back to `max_hp` through `Character.heal()` and clears its limb
  damage, so a re-attempted fight is the same fight. It is independent of
  `return_on_player_death` (heal-only and move-only are both valid), and is
  gated on **aliveness alone**, not `_eligible()` — the move exemptions
  (companion, bodyguard, cutscene, mid-talk) are reasons not to relocate a body,
  not reasons to leave it wounded. The dead are never revived.
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

### Presentation: High Fidelity / Retro

The game has two presentation modes, chosen on Options -> Video ("Presentation", a
`Settings.presentation` index — 0 High Fidelity, 1 Retro) and applied live by
`Settings.apply_video()` via `Window.content_scale_mode`:

- **High Fidelity (the shipped default)** — `canvas_items` stretch: the root viewport
  renders at the NATIVE window resolution while every Control keeps laying out against
  the same logical ~792x444 canvas (Godot's size-2d override — `get_visible_rect()`
  still reports the logical canvas, and dynamic fonts oversample crisp automatically).
  3D renders at native x `render_scale`.
- **Retro** — the original pipeline: `viewport` stretch renders everything into the
  ~792x444 buffer and the window nearest-upscales it (the chunky pixel look),
  bit-identical to the pre-presentation-setting game.

The contract (also the `@risk` header on `managers/Settings.gd`): effect knobs
authored in canvas pixels convert through **`Settings.native_scale()`** (render px per
logical canvas px — 1.0 in Retro/off-tree, ~2.42 at 1080p HF) and screen-matching
buffers size from **`Settings.render_size()`** — both read LIVE per frame, never
cached, so a mid-session toggle bites the consumers' next poll. Compensated consumers:
the screen post-process (`pixel_scale` dither/grain cell + the pixelation-grid no-op
push in `player.gd _update_low_hp`), `InkOutline` (px-unit uniforms + mask viewport),
`HudGhost`/`WorldGhost` (accumulators + capture transforms), the HUD-curve SubViewport
(`ui.gd`, sized native with a `size_2d_override` pinning layout to the canvas, and a
`filter_linear` HF twin of `hud_curve.gdshader`), the view-model pass
(`view_model_camera.gd` — the container is re-rected native and `Control.scale`d back
onto the canvas; its `stretch` flag must stay TRUE, see the feedback-loop warning
there), and the minimap hairline strokes (`FloorplanSection.stroke_width`'s
`native_scale` parameter). The PS1 vertex warp deliberately takes NO compensation (its
NDC grid is screen-proportional; scaling it would delete the wobble).

Two second-order corrections landed after the first playtest (2026-08-25):

- **Ink px units are RETRO-BUFFER pixels, not canvas pixels.** `InkOutline`'s width/
  reach knobs were tuned against the 1584-wide buffer (canvas x the authored
  `scaling_3d/scale` 2.0), and the migration seeds HF at `render_scale` 1.0 — so a
  bare `native_scale()` multiply DOUBLED every knob's on-screen fraction (fat halo
  outlines floating off distant NPCs; thin features dropped their lines because the
  Roberts tap spacing doubled with the width). `InkOutline._px_unit_scale()` is the
  correction: `native_scale() x live_supersample / AUTHORED_SUPERSAMPLE` in HF,
  `native_scale()` verbatim in RETRO. Its mask also sizes from `render_size()`
  exactly — a scalar-rounded 1920x1076 mask skews the mask camera's aspect against
  the main render.
- **Screen annotations must go through the lens.** The world barrel warp bends the
  PICTURE only; anything drawn from `Camera3D.unproject_position` (sniper glints,
  compass markers, the sky-title overlay) sits above it and detaches by the warp
  displacement — always true, but invisible under RETRO's chunky upscale and plainly
  wrong on a crisp native frame ("the glint is completely misaligned").
  `CameraSettings.lens_display_point()` (pure static, Newton-inverts the shader's
  `lens_warp`) maps an unprojected point to where the warp displays it; measured
  sub-pixel in both modes by the QA probe's differential marker test, and pinned by
  round-trip tests in `tests/test_camera_input_ui.gd`. Any NEW screen-space world
  annotation must call it.
- **EVERY outline is SCREEN-SPACE now; the inverted hull is DELETED (2026-08-27).**
  The hull shell extruded a constant SCREEN fraction, so its WORLD thickness grew
  with distance until it out-thickened the ~10 cm Lego limbs (~4 m) and the per-part
  shells shattered into colored confetti — probed on a real NPC, unfixable by
  cap/fade tuning alone, and exactly why no shipped game (L4D2 glow, League, Deep
  Rock's stencil IDs) draws long-range team outlines with geometry. That retired it
  for NPCs on 2026-08-25; the user's "replace all the shitty existing outlines with
  the new outline shader we added for enemies — this includes view models and
  everything" retired it everywhere else two days later. The replacement is that
  shipped architecture:
  - **The world ink NEVER draws on actors** (user-affirmed contract; a brief
    ink-outlines-NPCs experiment was reverted). NPCs stay on
    `ACTOR_INK_MASK_LAYER`; `InkOutline.hull_handoff_*` ships neutralized
    (290/299 m — inside the encode window on purpose: values past 300 m encode
    equal and degenerate the smoothstep). The tint RING below is an NPC's ONLY
    outline, which is why NEUTRAL maps to id 4 (a black ring matching the classic
    black rim) instead of having no id. The ring is computed BEFORE the ink's
    actor-exclusion and gates its `discard` (`&& ring_a <= 0.0` — `return` is
    illegal in a fragment processor), or the suppression band would erase it.
  - **Disposition color** = the TINT buffer: `NpcOutline._sync_tint_duplicates`
    parents an invisible flat duplicate under each part mesh
    (`InkOutline.ACTOR_TINT_LAYER`, one shared material —
    `InkOutline.tint_material()`), whose shader (`resources/shaders/ink_tint.gdshader`)
    encodes per-fragment log depth (the resolve pass's two-byte pack, THIRD copy —
    keep all identical) + `disposition_id` (instance uniform, packed as
    `id / TINT_ID_SPAN` where the SPAN is a **literal 16 in three files** —
    `InkOutline.TINT_ID_SPAN`, `ink_tint.gdshader`'s divide and
    `ink_outline.gdshader`'s decode; a drift re-reads every id as a different one
    with no error, and a test pins all three. Ids: 1 hostile / 2 friendly /
    3 companion / 4 neutral-black / 5 prop / 6 claimed prop / 7..8 the continuous
    engaged-hostile band / 9 look-at hover / 10 view model. It was 8 wide until the
    hull's retirement needed 9 and 10).
    `ink_outline.gdshader` ring-dilates that buffer (`highlight_width_px`, LUT
    exports `highlight_hostile/friendly/companion` — keep in step with
    `NPC.OUTLINE_*`; with `Settings.colorblind_safe_cues` ON, `_params` pushes
    `CBPalette.SAFE_HOSTILE/SAFE_FRIENDLY` over the hostile/friendly slots —
    accessibility wins over per-scene tuning, live on the toggle flip) into a
    constant-pixel ring. The CLOSE-RANGE COLOR BLOOM
    (`highlight_color_near_m/far_m`, 8/22, pushed pre-encoded) renders every ring
    neutral-black at range and fades the disposition color in as the ACTOR closes
    — full color inside `near`, black past `far`; constant color instead = raise
    `near` toward the window top. **THE LOCK-ON OVERRIDE (2026-08-27):** a hostile
    that is TARGETING the player (`NPC.is_alerted_on_player()` — ALERTED with the
    player as its live target; `_target` alone is a proximity lock and would light
    every hostile from spawn) stamps the CONTINUOUS 7..8 band
    (`TINT_ID_HOSTILE_ENGAGED + mix`, `InkOutline.apply_tint`'s `blend` arg)
    instead of plain id 1, and the shader FLOORS the bloom by the fraction past 7
    (`max`, never replace) — full red at ANY distance while locked on.
    `NpcOutline._drive_engaged_mix` (from the same `poll(delta)` — fed the BANKED
    AiLod think delta, invariant 2 of the LOD gate, and still polled under
    cutscene control so a scene that pacifies an enemy fades its ring on camera)
    ramps the mix over `NPC.outline_target_fade_s` (export, profile-stamped from
    `NpcData`; 0.4 s; 0 = snap) both in and out, so the red fades rather than
    pops; the mix is per-life state (`reset_for_reuse` zeroes it AND restamps the
    duplicates — the dead life's ~8.0 stamp would otherwise render full-red at
    the spawn point until the AiLod-staggered first think). ⭐ The ring follows
    Colorblind-Safe Cues (gap closed 2026-08-27): `NpcOutline._disposition_id()`
    resolves the tint id off `is_following()`/`resolved_disposition()` directly
    — never by comparing the resolver's color, which CBPalette shifts under the
    toggle (the old exact-color compare degraded every hostile/friendly to the
    black ring and the promotion never fired) — and the engaged band shares the
    `highlight_hostile` LUT slot, so the any-distance glow paints orange in safe
    mode (windowed A/B: `scripts/tools/__ink_cb_ring_shots.gd`). All parts merge into ONE raster
    silhouette (confetti structurally impossible), overlapping enemies resolve
    nearest-wins by the duplicates' own z-test, and the ring depth-compares against
    the scene so it never shows through walls.
- **World props (weapons, crates, the claimed dog) ring UNCONDITIONALLY.** The
  mechanism is shared: `InkOutline.apply_tint(root, id)` / `apply_tint_mesh(mesh, id)`
  / `clear_tint(root)` are the generic API, and `Throwable._tint_id()` resolves the
  precedence fresh on every re-stamp — CLAIMED (blue, `TINT_ID_PROP_CLAIMED`) beats
  HOVER (white, `TINT_ID_HOVER`) beats REST (black, `TINT_ID_PROP_REST`), so a claimed
  dog reads as yours whether or not you happen to be aiming at it. Only the
  DISPOSITION ids (1..4 and the 7..8 band) take the close-range colour bloom; props,
  the hover and the view model paint their LUT slot flat at every range.
  ⭐ Until 2026-08-27 the prop ring was the FAR half of a crossfade with the hull
  (`highlight_prop_near_m/far_m`, matched to the hull's `rim_fade_start_m/end_m`).
  Both knobs are DELETED with the shader: a surviving distance gate would now leave
  every crate and dropped weapon with no outline at exactly the range the player
  inspects it — the mirror image of the dead zone the crossfade was built to close.
- **The look-at / talk hover BORROWS an id rather than owning one.**
  `InkOutline.set_tint_highlight(meshes, on)` stamps `TINT_ID_HOVER` and remembers
  what each duplicate was wearing (`TINT_BASE_META`), putting it back on look-away —
  the same stash-and-restore shape the old `material_overlay` swap had, one layer
  down, and idempotent in both directions because the interaction ray drives it every
  time the target changes. Scenery with no ring of its own (a terminal, a car) gets a
  duplicate CREATED for the hover and FREED again (`TINT_HOVER_OWNED_META`), which is
  what stops a hover stranding a permanent white ring on the level. Because a ring
  resolves one id to one GLOBAL LUT slot, the per-component `highlight_color` on
  `Talkable` / `DialogueNPC` / `LookAtInteractable` no longer picks the hue — the hue
  is `InkOutline.highlight_hover`. Those exports survive as the VISIBILITY switch they
  already doubled as: alpha 0 or width 0 still means "this one gets no hover outline"
  (the shipping ATM relies on it), and the component then never borrows at all.
- **The one consumer with no route to the ring:** `shell_drop.tscn`'s ejected brass is
  a `GPUParticles3D` draw pass, and `apply_tint` parents a child `MeshInstance3D`
  under a `MeshInstance3D` — there is nothing to parent it to. It authors no `layers`,
  so it keeps the WORLD's ink line, which is the same black it had. The
  physical-casing variant (`bullet_casing.tscn`) is an ordinary body and does get the
  ring; it also gained the mask stamp it never had, which removes a doubled line
  nobody had noticed.
  Duplicates are invisible to every mesh-walker via the `npc_tint_dup` meta skip —
  centrally in `TalkHelpers.collect_meshes` (root AND children) and individually in
  the raw walkers that bypass it (`BodyModelSwap` x6, `WorldItem`, `GunVisuals` x3,
  `WeaponModelSwapper`, `Ps1Applier`, `MeshCoat`, `BodyPartGib`).
  ⭐ Renaming that meta un-shields all of them with no compile or runtime error.
- **Skinned meshes are MIRRORED, not skipped** (reversed 2026-08-27). `apply_tint`
  used to refuse `m.skin != null` — survivable only while the hull covered for those
  bodies. With the hull gone, the corpse `Ragdoll` spawns, the bare `Man.glb` fallback
  and three of the seven weapon view models would have had NO outline at all. The
  plumbing is two properties on the duplicate: copy `skin`, and re-express `skeleton`
  as a path from the DUPLICATE (it is a child of the mesh, so the source's own
  relative path resolves one level short).
- **The ring does NOT ride `Settings.ink_outline_intensity`.** While the hull existed,
  Options → Video → "Ink Outline" at 0% left every gameplay outline intact, because
  the rims were not part of this pass. Now that the ring IS every outline in the game,
  scaling it by that slider would silently make a video option the master switch for
  hostile red, the colourblind-safe palette, claimed-prop blue, every hover cue and
  the weapon's line. So the slider owns the WORLD ink alone; the quad stays visible
  for the ring even at 0% (with `ink_opacity`/`width_px` zeroed), and both
  SubViewports are gated — the mask with the ink, the tint pass with the ring
  (`InkOutline.ring_enabled()`). That tint gate is new too: the pass rendered
  unconditionally until the migration was about to multiply what it draws.
  Pinned in `tests/test_ink_outline.gd`.
  ⭐ Probe gotcha: a bare `enemy.tscn` spawn has NO body (looks come from authored
  NpcData), so outline QA must photograph level-authored NPCs, never raw spawns.

A settings.cfg from before the split migrates once via `Settings.read_presentation`:
no `presentation` key -> High Fidelity with `render_scale` forced to 1.0 (the saved
2.0 supersampled the retro buffer; against a native target it would be 4K-on-1080p).
Verification is the windowed harness `scripts/tools/presentation_qa_shots.tscn`
(QA_CANVAS must stay logical in both modes; QA_BUFFERS must track `render_size()`;
the PNG sizes themselves prove the split); `menu_qa_shots` / `hud_curve_qa_shots`
pin RETRO so the artist reference packs stay deterministic.

### Menu/UI layout QA

The real UI canvas is **792x444** at 16:9 in BOTH presentation modes — the 396x216
base viewport is doubled by `window/stretch/scale=0.5`, and `aspect="expand"` varies
it with monitor shape (height 432 minimum, 495 at 16:10, wider than 792 on
ultrawide); High Fidelity renders it at native resolution without changing its
coordinates. Menu code must lay out against that, never against 396x216 (and never
against the window). `scripts/ui/menu_style.gd` documents the same
fact at the code seam, and `MenuSkin` (`resources/ui/menu_skin.tres`) carries the shared
layout constants (`content_separation`, `dialog_button_min_width`, `tab_min_width`, …).

`MenuSkin` is also the **UI artist's drop-in surface**: its "Widget art" groups hold
optional per-widget, per-state `StyleBox`/texture slots (buttons, toggles, sliders,
text fields, meters, tabs, scrollbars, separators, tooltips) that `MenuStyle` consumes
when building the one shared `Theme` — each null slot falls back to the generated flat
look, artist boxes are DUPLICATED into the theme (theme-side mutation never bleeds into
the saved `.tres`), and the same tab slots feed both the Options `TabContainer` and the
hand-built player-menu strip (`make_active_tab_style`/`make_hover_tab_style`/
`make_inactive_tab_style` — the third exists so shipped BUTTON art can never dress the
strip's rest state in button-body chrome). Per-state `button_font_*_color` ink knobs
(alpha-0 = palette-derived) ride beside the button art slots; `button_focus` art must
stay a transparent-centred ring (Godot overlays the focus box ON TOP of the state box);
a missing `button_disabled` derives a dimmed copy of the rest art; and empty-text
LIST-ROW buttons opt out of button-body art via `MenuStyle.style_list_row()`.

**Scrollbars are the one widget whose skin slot is also a LAYOUT budget.** A `ScrollBar`
takes its cross-axis size from its track box's CONTENT MARGINS and nothing else, so
`skin.scrollbar_width` (default 8px) is stamped onto whichever box the bar wears —
generated or artist art — by `MenuStyle._scrollbar_box`. Before 2026-08-27 no box carried
margins and every bar in the game drew ZERO px wide, which is why four screens silently
hid most of their rows (Options→Controls 4 of 44 bindings, Accessibility 14 of 33,
character creation 4 of 6 stats, the Stats tab cut mid-word). ⚠ A `ScrollContainer`
RESERVES that width beside its content, so a page with no width to spare buys the gutter
out of its own margin instead of out of its rows — `options_menu._add_tab` subtracts it
from the page's right inset and runs every tab at `SCROLL_MODE_SHOW_ALWAYS` so the
affordance is up before the player wheels and every tab reserves the same rail.
`scrollbar_track_color` / `scrollbar_grabber_color` (alpha-0 = derived from `text_color`)
ink the generated pair; the thumb goes ACCENT under the mouse. Pinned by
`tests/test_menu_skin_art.gd` + `tests/test_options_menu.gd`.

**One light, two halves.** The art PNGs carry a drop shadow BAKED into a transparent pad
that rides in each box's expand margins (draw-only, so no layout metric moves with a
shadow), and it falls STRAIGHT DOWN — `scripts/tools/bake_ui_shadows.gd` owns that bake and
re-aims it in place, sampling each texture's existing shadow colour/strength so an artist's
weight survives a re-run. `MenuSkin`'s "Text drop shadow" group (`text_shadow_color` with the
alpha-0 unset sentinel, `text_shadow_offset`, `text_shadow_blur`) is the type half of the same
light. ⚠ Its reach is capped by the engine: Godot 4.7 exposes font-shadow theme items on
`Label`, `RichTextLabel` and `TooltipLabel` only, so **Button captions, `TabBar` and `LineEdit`
stay flat** — setting `font_shadow_color` on the `Button` type succeeds silently and draws
nothing. The in-viewport cursor tip takes the shadow by hand in `MenuStyle._style_tip` because
it hangs off the autoload's own `CanvasLayer`, where no `Theme` reaches it.

Pinned by `tests/test_menu_skin_art.gd` (including a pixel-level check that each baked shadow
casts nothing above its body and spills equally either side); artist workflow in
`AUTHORING_GUIDE.md` §"Reskinning the menus". Because the look flows through the Theme, a menu converted to an authored
`.tscn` scene later inherits the same art with no extra wiring.

Two art slots deliberately do NOT flow through the Theme, and a consumer must read them
by name: `panel_style` does (it IS the theme `Panel`/`PanelContainer` box), but the
COMPACT confirm cards ask for `MenuStyle.make_plain_panel_style()` instead because the
screen-card art is nearly all torn border at popup scale — and `dialogue_panel` (the
bottom conversation box) has no theme entry at all. `DialogueView._build_ui` reads it
through `MenuStyle.make_dialogue_panel_style()`, which returns **null** when the slot is
empty OR gated off by `MenuSkin.dialogue_panel_enabled` — the SHIPPED state since the
08-24 box-less dialogue pass: the slot keeps the artist's authored art (and its tests /
shadow-bake target) while the box wears a `StyleBoxEmpty` and the conversation reads as
left-aligned outlined subtitles + a left-gutter response column of translucent per-row
beds between the letterbox bars, the speaker held dead-centre by the camera
(`dialogue_frame_offset_deg` 0). The response rows
carry their OWN skin slots (`dialogue_choice_normal`/`_hover`, generated fallbacks in
`MenuStyle.make_dialogue_choice_*`) — the old plain-panel backing behind the choice list
is gone. The box art's transparent corner cut still constrains its own margins for
whoever re-enables it; see THE NOTCH RULE in `AUTHORING_GUIDE.md`. The box-less layout
itself (subtitle block + response column at the left gutter + scrim, digit selection
riding the hotbar-slot bindings while the tree is paused, the pinned Goodbye row) lives
in `DialogueView`/`DialogueManager` with
its geometry on `GameSettings.dialogue`; judge changes with
`scripts/tools/dialogue_ui_qa_shots.tscn` (a windowed QA-shot harness — no unit test
can see a layout).

The in-game HUD has the same seam: `HudSkin` (`resources/ui/hud_skin.tres`,
`scripts/ui/hud_skin.gd`), exposed as `MenuStyle.hud` beside `MenuStyle.skin` (swap via
`set_hud_skin`, null-fallback in `rebuild()`), carries every look value the gameplay HUD
scripts used to hardcode — hitmarker/damage-arc/aim-arc/sniper-glint paint, compass and
minimap fallback tints, HUD label + hotbar chrome, plus optional crosshair/hitmarker/
compass-marker art slots (null = the code-drawn look); defaults equal the former
literals so an untouched skin is pixel-identical (`tests/test_hud_skin.gd`), while
gameplay-tuning numbers stay on `GameSettings.hud` and semantic/accessibility colours
stay on `CBPalette`/`Settings`.

**The HUD minimap** (`scripts/ui/minimap.gd`, an AUTHORED SCENE — `scenes/ui/hud_minimap.tscn` —
instanced by `ui.gd` into the `_weighted` carrier, top-right) is a PROCEDURAL vector floorplan —
no authored texture and no second 3D pass. The scene is the artist surface (the "menus are scenes"
rule, applied to a HUD widget): it owns the box's anchors/offsets/`z_index`/`clip`/texture filter,
and it wraps the widget's single `_draw` in two empty full-rect art slots whose TREE ORDER is the
render order — `%MapUnder` (forced `show_behind_parent` in `_ready`, so the slot name is the
contract) renders behind the whole plan, `%MapOver` in front of plan, markers, caret and rim. Both
ship with zero children, so the shipped map is pixel-identical. `_ready` also sweeps every authored
art node to `MOUSE_FILTER_IGNORE` (an authored `TextureRect`/`ColorRect` defaults to STOP and would
re-open the "the HUD eats clicks in the corner" bug) and hides the editor-only alignment fill.
Art children need no repaint wiring — each is its own `CanvasItem`, so nothing an artist adds can
reach the idle gate. The contract, end to end: the level's `Groups.NAVMESH` region -> `FloorplanSource`
(walks the level ONCE, turning every STATIC collider into a world-space solid) +
`FloorplanSection` (pure statics: the navmesh triangle fan, the chest-height section cut,
the view matrix) -> a per-floor "deck" cached in the widget -> ONE `draw_multiline` plus one
`canvas_item_add_triangle_array`, both under a single `view_transform`, so the plan, an
optional `MapData` underlay and every marker dot share one projection and cannot fork.

**Two hosts, one widget.** Since the MAP TAB landed (`scripts/ui/map_screen.gd` +
`scenes/ui/map_screen.tscn`, the sixth Pip-Boy tab, default **M**) this script also draws the
page-sized map, as a second instance filling a menu panel. Everything above is shared — the same
gather, the same deck cache, the same marker channels, the same skin, the same idle gate — and the
ONLY difference is the per-instance `@export`s in the widget's **Instance view** group, all inert
by default so the HUD box and the ~39 bare `.new()` sites in `tests/test_minimap.gd` are untouched:
`world_span_override` (0 = follow `HudSettings.minimap_world_span`; the tab pushes `map_world_span`),
`zoom_override` (0 = follow `Settings.minimap_zoom`; the tab pushes `Settings.map_zoom`), `heading`
(FOLLOW_SETTING / NORTH_UP / HEADING_UP; the tab forces NORTH_UP), `zoom_key_enabled` (off on the
tab, so one `MinimapZoom` press can never move two maps), `view_offset` (the PAN, in world metres on
XZ — ZERO and gestureless on the player-centred HUD box, written by the map screen's drag / movement
axes and re-zeroed on every open), and the three waypoint knobs `waypoint_labels` /
`waypoint_pin_offscreen` / `selected_waypoint` (all off/-1 on the HUD box, all pushed on by the tab:
that surface is where pins are EDITED, so it names every pin and rim-pins the ones off the view,
while the 108 px box draws only the pins actually on it — plus the tracked one, which always pins).
⭐**The invariant that makes this safe is
that every paint site and every drawn-options stamp reads `effective_world_span()` /
`effective_zoom()` / `effective_rotates()`, never `Settings.minimap_*` directly.** A stamp taken
against the raw Settings row on a widget that draws an override is a mismatch no repaint can resolve
— it pins the idle gate open forever while a change to the value actually drawn asks for nothing, so
the map's zoom moves and the picture does not. `_drawn_span` and `_drawn_view_offset` are the fifth
and sixth members of that stamp family, added for the same reason. ⭐**The pan is a VIEW term, added
to `_centre_xz` INSIDE `view_matrix()`** — the widget's single projection construction site — so the
plan, the click-to-world inverse used by the tab's placement and every marker's screen point (the
player's own caret included, which is projected rather than assumed to be the box centre) all move
together and cannot fork. The map tab also gates on the same registry row / mid-death /
`has_player` guards as its sibling tabs and never pauses the tree.

The wall layer is a **boolean union, drawn as lines** (`FloorplanSection.silhouette`, knobs
`GameSettings.hud.minimap_merge_solids` / `minimap_merge_weld`). A level is built out of
overlapping boxes and a floorplan must not be drawn as one, so every cut ring is DIFFERENCED
against the other solids' outlines with `Geometry2D.clip_polyline_with_polygon` and only the
union boundary is inked. Three things about that pass are load-bearing: it runs on the LINES
rather than on the areas, because `merge_polygons` returns outer rings and holes told apart
only by winding and that distinction cannot survive being folded over N rings two at a time
(a desk would be unioned into its room's interior hole and vanish); the weld tolerance is not
a fudge factor, because a line lying exactly ON a clip polygon's boundary survives the
difference, which is precisely the abutting-brush case; and rejection runs BEFORE the merge,
because a void-seal brush promoted to an occluder would erase the whole level silently. A
solid wholly inside another is skipped as an occluder, which is what stops a duplicated brush
from clipping itself out of existence. Trimesh cuts (a CSG bake) are unordered segments, so
they are trimmed by the rings but never trim them — chaining them into loops would let a
hollow shell's outer loop swallow every wall inside it.

Four things about it are load-bearing and easy to undo by accident:
- **A level swap is detected from the navmesh region's INSTANCE ID**, not a `GameRoot` signal.
  A freed region leaves the group by itself, so the deck cache self-heals and `game_root.gd`
  is untouched by this feature.
- **The vertical reference is the last GROUNDED player height, and the floor band is sticky**
  (`FloorplanSection.sticky_band_key`, margin `GameSettings.hud.minimap_band_hysteresis`).
  Keying off live Y instead makes a jump near a band boundary swap the whole floorplan
  mid-air; a stair riser does the same every frame. Both guards are needed — grounding fixes
  jumping, the margin fixes slopes and risers.
- **The static gate is `is StaticBody3D and not is AnimatableBody3D`, a TYPE and never a
  physics layer.** Not because characters and geometry share a layer — they do not.
  Characters are `collision_layer 2` (`Player.tscn`, `enemy.tscn`) and level brush geometry is
  `collision_layer 1, collision_mask 0` (func_godot's `worldspawn` / `func_geo` / `func_detail`;
  the whole main level is one `entity_0_worldspawn` StaticBody3D), so a mask *could* tell a body
  from a wall. It is the wrong tool for a different reason: **layer 1 is the ENGINE DEFAULT**, so
  it is where every static thing that never touches the field lands — world brushes, scenery
  props and door bodies alike (`door.tscn`'s `DoorPivot/DoorBody` is a bare `StaticBody3D` with
  no layer override). A mask therefore cannot make the ONE distinction this picture needs, solid
  wall vs. movable leaf, and it would silently drop any future prefab an author puts on another
  layer. A type gate states the intent directly and asks no layer discipline of level authors.
  The exclusion is the load-bearing half: `AnimatableBody3D` INHERITS `StaticBody3D`, so the
  obvious `is StaticBody3D` gate bakes a moving leaf into the map in whatever pose it held.
- **`_process` bails on `is_visible_in_tree()` before doing anything.** That is what makes the
  Options toggle, the dialogue hide and the death hide genuinely free rather than a hidden
  node still slicing and redrawing.

**THREE MARKER CHANNELS** (2026-08-13), painted back-to-front, each with its own group and its
own rules — a node in two channels is drawn by both on purpose, because a shop riding a dialogue
NPC is two different facts about one body:

| Channel | Group | Shape | Pins to the rim? |
|---|---|---|---|
| POI beacons (`WorldMarker`, `QuestMarkerSync`) | `Groups.MINIMAP` | a plain dot at `marker_radius` | always |
| Stations (`StationMarker`) | `Groups.MINIMAP_STATION` | a STROKED kind glyph | per `StationMarker.pin_offscreen`, defaulted from the station's own `standalone` |
| Bodies | `Groups.NPC` | a FILLED allegiance glyph | never — that would be a radar |

- **SHAPE is the primary channel and HUE the secondary one** (`MapGlyph`, pure statics). At a ~4 px
  radius hue alone cannot carry hostile-vs-neutral, and `Settings.colorblind_safe_cues` exists
  because hue is contested even at size. Bodies are FILLED and small, stations STROKED and larger;
  that contrast is what lets the two alphabets share the triangle. Trainer stations are additionally
  INVERTED, because "hostile" is the one reading that must never be ambiguous.
- **The neutral body tint is its own skin slot** (`MenuStyle.hud.minimap_neutral_color`). It used to
  fall back to `minimap_npc_color`, a salmon RED indistinguishable from `CBPalette.hostile()` at a
  4 px glyph faded to 0.3 alpha — the map called every civilian a threat. `minimap_npc_color` keeps
  its real job as the POI-beacon fallback, which `tests/test_hud_skin.gd` still depends on.
- **The hostile alert ring** reads `NPC.suspicion_of(player)` — a new facade beside `awareness_of` /
  `detection_of`, target-gated the same way, so a guard fighting a stray dog never rings. It is
  additionally gated on HOSTILE (`Minimap.alert_tier`): a companion tracks the player as its follow
  target and is permanently ALERTED on them, so without that gate every ally would wear a threat
  halo. The ring GROWS one step per `Perception.SuspicionTier` rather than recolouring, so the
  threat level survives the colourblind palette swap.
- **⭐Never draw a sight cone here.** `Perception.can_see()` raycasts, and `_draw` / `_process` run
  OFF the physics frame where `direct_space_state` returns empty *silently* — a cone would pass
  every test and report "sees nothing" in play. It would also be a wallhack.
- **The idle gate probes `Groups.NPC` for BOTH body channels and never `Groups.MINIMAP_STATION`.**
  A fixed station cannot move, so scanning its group would pin the gate open forever for nothing;
  but 7 of the 8 stations placed in this project ride a dialogue NPC, so their glyphs DO move — and
  that body is already in `Groups.NPC`. Gating the NPC scan on the NPC toggle alone froze a walking
  shopkeeper's glyph for any player who turned body dots off. The gate no longer reads either switch
  directly: it reads `_scan_r`, the ONE sampled field the paint site reads, which already folds in all
  three owners of the body channel (`dot_npcs`, `Settings.minimap_show_npcs`, and the scanner implant).
  It previously forced a full repaint every frame for bodies the player had already switched off, which
  was the exact cost that row exists to remove — and the same now holds for the far more common case, a
  player with no scanner chip standing in a level full of bodies.
- **⭐The body channel is IMPLANT-GATED (`Minimap._sample_scan_range` -> `Player.body_scan_range`).**
  Bodies are dotted only inside an installed, switched-on scanner's radius in METRES — `bio_scanner`
  22 m, `deep_scanner` 55 m, widest enabled wins — and with no chip the channel draws nothing at all.
  The limit had to be in metres rather than in box-pixels because the Map tab is the same widget at
  120 m, zoomable to 240 and pannable 400: a limit the player's zoom slider can widen is not a limit.
  The rim fades over `HudSettings.minimap_scan_fade_m` so a walking body does not blink on and off.
  ⭐The range lives on the ability SCRIPT's export default, never on its `.tscn` — `AbilityManager._build`
  reconstructs an ability from `load(script_path).new()` for every runtime grant (chip install, save
  load, pickup) and never reads the scene, so a scene-only range installs as 0 m, silently.
- **⭐That gate needs TRAILING EDGES, not just live facts.** A `CanvasItem` repaints only on
  `queue_redraw()`, so "is anything live NOW" is the wrong tense: the frame a fact STOPS being true is
  the frame the picture most needs repainting, and it is exactly the frame the gate goes quiet. For a
  standing, still player the last painted frame then stayed on the map indefinitely — the dot of a body
  that is gone, the beacon of a quest already handed in, the glyphs the player just switched off in
  Options (those rows carry no apply step by design, so nothing else was ever going to ask; the same
  went for the zoom slider and the zoom key; and the same went for the ARTIST's `hud_skin.tres`, since
  `MenuStyle.set_hud_skin` assigns and calls `rebuild()` but emits nothing and touches no HUD widget).
  Three terms in `Minimap._needs_repaint` exist purely to
  close that: `_painted` (did the two channels `_has_live_markers()` probes put art on the canvas last
  paint), the drawn-options stamps (`_drawn_zoom` / `_rotates` / `_show_npcs` / `_show_stations`,
  re-stamped inside `_draw`), and the drawn-SKIN stamp (`_drawn_skin_id`, an instance-id compare so the
  per-frame check never allocates). The skin has a second half the id compare cannot see — an artist
  editing a slot on the SAME `.tres` through Godot's Remote inspector against a running game — so
  `_sync_skin_signal` also wires `Resource.changed` straight to `queue_redraw`, re-pointed on every
  paint and guarded against a duplicate connect (an engine error would fail the whole GUT suite).
  All are re-stamped by the very repaint they ask for, so none can pin
  the gate open — which is why `_painted` is set from the gate-watched channels ONLY and a fixed
  station never sets it. Same defect and same fix as the stuck aim arc (`aim_indicators.gd`'s own
  `_painted`). **A new painted channel added without a trailing edge strands its art on the map
  forever.**
- **The NOISE RING is the fourth painted channel, and the only one that is a function of TIME.**
  A circle around the caret at `Player.noise_radius` metres — the scalar enemy `Perception.can_hear()`
  tests against — drawn in true WORLD METRES (every other marker is a fixed pixel size) so a body dot
  inside it is a body that can hear you. It is centred at `size * 0.5` with no projection, which is
  exact rather than approximate: `view_transform` builds `origin = rect * 0.5 - basis_xform(centre_xz)`
  and `_centre_xz` IS the player's XZ, so the caret and the ring cannot drift.
  - **It needs no clock, and that is the design.** `NoiseEmitter` recomputes the radius every physics
    frame and decays a gunshot spike at 45 m/s (and a jump/landing spike at 50 m/s after a 0.35 s
    full-radius hold), so the ring bursts past the box edge and collapses back over ~0.6 s driven
    entirely by world state — no phase, no ring pool, no `Time.get_ticks_msec()`, no `process_mode`
    override, nothing to strand when the tree pauses. What timing the spikes need lives in the EMITTER's
    own physics tick, on the far side of the `noise_radius` scalar; the minimap still only ever samples a
    number. It keeps the same shape as every other channel here and sidesteps the whole class of
    animated-channel bugs. (During a spike's hold the radius is CONSTANT, so the `_drawn_noise_r` stamp
    matches and no repaint is asked for — the already-painted ring simply persists, which is correct:
    `CanvasItem` keeps its last paint until something queues a redraw.)
  - **⭐`Minimap.NOISE_STEP_M` (0.25 m) is load-bearing, not cosmetic.** Ground deceleration is an
    EXPONENTIAL lerp, so it asymptotes and `noise_radius` never reaches exactly `0.0` for a player who
    has ever walked. Without the `snappedf`, the gate's float compare mismatches in the last bits every
    frame and pins a full floorplan repaint open at frame rate, in a silent room, with nothing on
    screen — and every test still passes. `tests/test_minimap_noise.gd` is the only tripwire.
  - **Its gate term is a STATE STAMP (`_drawn_noise_r`), not a probe + `_painted` latch.** The stamp is
    both halves at once: it holds the gate open while the radius moves, and the mismatch when the sound
    stops buys exactly ONE clearing repaint. It is deliberately kept OUT of `_has_live_markers()` /
    `_painted` — those two are a matched pair, and folding it in would drag a per-frame
    `Groups.human_player` scan into the one term documented as allocating. The two-owner switch
    (`ring_noise and Settings.minimap_show_noise`) is read inside `_sample_noise_radius` and nowhere
    else, so the gate and the paint site ask literally the same question and no `_drawn_show_noise`
    stamp is needed — switching the row off collapses the sample to 0.0, which IS the clearing edge.
  - **It draws sound YOU made, never sound made AT you.** NPC gunfire and death pulses ride the same
    `&"noise"` channel and are deliberately not drawn: the player has no hearing model at all
    (`Perception` is instantiated only by NPCs), so an enemy's pulse would be a new sense granted
    silently, and it would report a firefight through three walls. The ring cannot reveal a body that
    `minimap_show_npcs` was not already drawing — it is a mirror of your own state, not a sensor. The
    `debug_noise` export shows the whole channel for TUNING and ships off, an inspector switch rather
    than an Options row (the `NavDebugOverlay` convention); it is the one gate term that is not
    self-clearing, and pins the gate open on purpose while it is on.
- **An authored `MapData.npc_marker` reaches the POI channel ONLY.** It used to be handed to the body
  loop as well, so a level that authored a blip silently retextured every quest beacon — and one
  texture cannot carry an allegiance, which is the distinction the body channel exists to make.

Layout: the top-right corner is a THREE-ROW STACK — the minimap, the HUD clock under it, then
the objective tracker — and each row's top is derived from the row above it
(`ui.gd.hud_clock_top_for` / `ui.gd.quest_tracker_top_for`, both pure statics pinned by
`tests/test_minimap_hud_layout.gd`). The MAP's own row is measured out of the instanced scene by
`UI.minimap_box()` / `minimap_box_from` (fed the four anchor offsets, never `size` — an unparented
Control is 0x0 until the first layout sort), so dragging the box in the editor reflows the clock
and the tracker. A degenerate box falls back to `GameSettings.hud.minimap_inset`/`minimap_size`,
which is how a bare `UI.new()` in a test and a failed instantiate both keep the historical layout;
`tests/test_minimap_scene.gd` pins that the authored box and those knobs describe one rectangle,
which is what keeps every clearance invariant pinned against the knobs still true of the real corner. Every row can be switched off independently by the player,
so the reflow is the contract: map off lifts the clock into the corner, clock off returns the
tracker to exactly the top it had before the clock existed (the clock's parameters are ADDITIVE
trailing arguments defaulting to "no clock", which is why the pre-clock pins still describe the
live rule), and both off restores the historical bare 8 px corner.
Geometry knobs are on `GameSettings.hud`, paint on `MenuStyle.hud`, and the player's own
on/off + rotate + zoom + NPC dots on `Settings`, polled live — and the poll is only half of it,
because a Control repaints solely on `queue_redraw`: the live value is compared against the stamp
the last `_draw` left behind (see the trailing-edges bullet above), or a standing player never sees
the row move. **The `MapData` underlay is
authored per level** — `LevelData.map_data` (an authored image drawn under the plan through
the same matrix via its `world_bounds`) is PULLED by the widget itself, never pushed:
`Minimap.rebake()` calls `_resolve_level_underlay()`, which reads `Groups.GAME_ROOT`'s
`level` and stamps the result EVEN WHEN NULL, so a swap into a level without an authored
map clears the previous level's art instead of drawing it in the new world space. Because
`rebake()` rides the same region-instance-id staleness hook as the deck cache, the
underlay self-heals across a LevelDoor transition with no wiring in `game_root.gd` or
`ui.gd`. `Minimap.map_data` (the widget export) stays a per-instance override that wins
when set; the shipped code-built HUD widget leaves it null, and `active_map_data()` is
the one precedence seam every draw site reads. The CYBER SUNDAY Content dock's New Map
row scaffolds `MapData` `.tres` into `resources/maps/`; assigning one to a `LevelData`
is the whole authoring workflow. `tests/test_minimap.gd` pins the stamp, the clear, the
precedence, and the off-tree degrade; `tests/test_level_data.gd` pins the null default.

**The HUD clock** (`scripts/ui/hud_clock.gd`, code-built by `ui.gd` directly under the map) is
row 2 of that stack: a `Label` that renders `WorldClock.time_of_day` as a digits face. It exists
because the day/night cycle's LIGHTING is otherwise the only time signal, and lighting is a poor
instrument — `DayNightSky`'s moon deliberately keeps midnight legible, interiors are lit by their
own fixtures around the clock, and "is the shop open yet" should not require walking outside to
squint at the sun.

- **It is a READER only.** Nothing in the widget writes the clock; `WorldClock` stays the single
  source of truth that `DayNightSky` drives the sun from, so the digits and the daylight cannot
  disagree.
- **It persists for free.** `GameState.time_of_day` already snapshots `WorldClock` and re-applies
  it on load, so the face shows the hour the save was taken at with no persistence of its own.
- **The whole conversion is pure statics** (`minute_of_day` / `hour_12` / `face_text` /
  `time_text`), pinned off-tree by `tests/test_hud_clock.gd` — the `DayNightSky.sun_elevation`
  idiom. `minute_of_day` FLOORS rather than rounds, or the last ~20 seconds of every day would
  print "24:00".
- **The face is composed from whole `PlayerText` templates** (`CLOCK_24_HOUR` /
  `CLOCK_12_HOUR_AM` / `CLOCK_12_HOUR_PM`), selected on the player's 12/24-hour choice and the
  half of the day. The AM/PM marker and the `:` separator live INSIDE the templates because both
  are locale-dependent; a suffix appended in code is exactly the untranslatable fragment
  `TextFormat`'s rule forbids. Zero-padding goes through `TextFormat.pad2`.
- **A minute gate, not a per-frame stamp.** `time_of_day` moves every frame but the face changes
  1440 times a day, so the widget caches the last minute-of-day it painted and re-stamps only on
  a change (or when the 12/24-hour choice flips) — one int compare per frame, the minimap's
  idle-gate idiom. Like the map, `_process` bails on `is_visible_in_tree()` first, so OFF is a
  real cost win rather than a hidden node still working.
- **It pauses with the tree**, so the face freezes during a dialogue. That is correct — in-game
  time genuinely is not advancing — but it is why a player watching the clock through a long
  conversation sees no movement.

**The HUD compass** (`scripts/ui/hud_compass.gd`, code-built by `ui.gd`) is the top-CENTRE instrument, and
the other half of the same reasoning as the clock: it exists because the minimap in its shipped HEADING-UP
mode carries no fixed bearing at all — the plan turns under a fixed caret, so spinning on the spot moves
every landmark and nothing on screen answers "which way am I facing". (Its north tick is a spoke on a 108 px
rim; `minimap.gd` records why a LETTER there would be a smudge.) The tape is a horizontal heading scale
across the top of the screen: the eight rose letters and their degree ticks sliding under a fixed index
caret, plus a chevron for every `Groups.COMPASS` marker at its bearing.

- **It rides the weight carrier, and that is a deliberate exception.** `ui.gd`'s moved-vs-pinned header rule
  puts world-direction annotations on the layer rather than on `_weighted`, and clause 3 of the ghost rule
  (`_build_ghost`) excludes them from the phosphor capture: a lagging bearing is a bearing that lies. The
  tape would have been the purest case of both — and it is nonetheless on the carrier, swaying, ghosting and
  bending through the HUD curve with the map and the clock, on a user call that it should read as part of the
  instrument panel. The cost is bounded and worth naming: the rose lags the turn by the spring's settle, so a
  bearing read mid-flick is a beat stale. That is affordable *here* precisely because a compass point that
  arrives a frame late still names the same place in the world, which is exactly what is NOT true of the
  damage arcs — so this is an exception, not a precedent for them.
- **Two things the reparent breaks, both handled.** (1) `_weighted` is moved INTO a `SubViewport` whenever
  the HUD curve is up, and that viewport holds no `Camera3D` — so `get_viewport().get_camera_3d()` answers
  null and the tape would silently freeze at its last bearing whenever an unrelated Options row was on.
  `HudCompass._active_camera()` falls back to the root viewport's camera. (`Minimap._camera_yaw` has the same
  exposure and degrades to the player BODY's rotation instead, which is near enough for a floorplan but would
  be wrong for a readout that reports where you are LOOKING.) (2) The tape now MOVES while the centre-top
  column under it stays pinned, so `compass_column_gap` is a **sway budget**, not breathing room — it must
  absorb `hud_sway_max` plus the lens-breath scale's pull toward canvas centre, or the rose lands on the
  enemy health bar on the next hard flick. `tests/test_hud_compass.gd` pins that sum against the LIVE sway
  knobs, so raising either one fails there rather than shipping an overlap. `compass_top` is the same budget
  in the other direction and is deliberately spent right down to the screen edge, because overrunning it only
  CROPS a few px of tick row on a hard flick where overrunning the gap COLLIDES. The only floor there is that
  the band must never leave the screen entirely, which is what that suite pins instead.
- **It has no backing plate.** `compass_track_color` ships at alpha 0, so the rose floats on the world like
  every other readout here (the ammo line, the money rail, the quest tracker are all bare outlined text; the
  minimap's backing is the exception because it is a WINDOW, not a label). Legibility is carried entirely by
  the black-outline dialect — `compass_outline_size` for the glyphs and `compass_rim_px` for the LINE art.
  That second knob exists because removing the plate left the degree ticks and the index caret invisible
  against a bright backdrop; the letters were already covered and the line art was not.
- **It OWNS THE TOP BAND, and the centre-top column reflows under it.** This is the layout contract, and it
  is the top-right stack's derived-row rule applied to the other column. `ui.gd` owns a full-rect
  `_centre_column` carrier (the `_weighted` idiom, one offset write) that `player_hud.gd` parents its whole
  centre-top ladder into — the enemy health bar, then the stealth badge → detection meter → claim →
  takedown/pet rows. `UI.centre_column_top_for` (pure static, pinned by `tests/test_hud_compass.gd`) answers
  how far that carrier drops: `compass_top + compass_size.y + compass_column_gap` with the tape up, and
  **exactly 0** with it off, so switching the compass off in Options reproduces the pre-compass canvas
  byte-for-byte rather than approximating it. PlayerHud's hand-tuned, outline-tight offsets
  (18 → 40 → 56 → 78 → 96 → 118, enemy bar above at `enemy_hp_top`) are therefore unchanged and measured
  from the COLUMN's top: the reflow is common-mode, so the 2 px clearances inside the ladder survive it.
  The carrier's `z_index = 1` is load-bearing — it is born in `UI._ready` while the full-screen flashes it
  must composite over are added later from `PlayerHud.build`, so tree order alone would bury the column.
- **One marker channel, two surfaces.** The tape reads `Groups.COMPASS` — the same group the screen-edge
  `Compass` component draws chevrons for and the same one `QuestMarkerSync` feeds. The two answer different
  questions about one set of markers ("where on screen is it" vs "what bearing is it on"), and a second
  registry would let them disagree; a `WorldMarker`'s authored `color` drives both.
- **The bearing basis is shared, not re-derived.** World north is `-Z`, east is `+X`, and the yaw convention
  (`camera_yaw`) is `Minimap._camera_yaw`'s verbatim — so the tape and the floorplan's north tick cannot
  disagree. That basis is the thing `tests/test_hud_compass.gd` spends most of its asserts on: a sign flip
  does not error, it produces a compass that is confidently, silently wrong.
- **The whole projection is pure statics** (`bearing_from_yaw` / `bearing_between` / `delta_deg` / `tape_x` /
  `on_tape` / `edge_alpha` / `graduations` / `cardinal_index`), pinned off-tree — the `FloorplanSection` /
  `Compass.project_to_edge` idiom. `delta_deg`'s wrap is what makes the 360→0 seam invisible.
- **The rose letters are COPY.** `PlayerText.compass_cardinal` selects between eight whole templates, because
  a compass rose is initialled from the LOCAL direction words (French writes O for west, and NO/SO follow it).
  Contrast the minimap's north tick, which is a drawn spoke precisely so it owes `PlayerText` nothing.
- **A heading gate, not a per-frame repaint**, and `_process` bails on `is_visible_in_tree()` first — the
  clock's minute-gate idiom, so OFF is a real cost win rather than a hidden node still working.
- **`_draw` never runs headless**, so `scripts/tools/hud_compass_qa_shots.gd` is the other half of the
  verification: a windowed run that shoots the band at five headings plus a 4x nearest crop, over a backdrop
  split dark/near-white so contrast is judged both ways at once. It is what caught the index caret cutting
  into a centred rose letter, and then the un-rimmed ticks vanishing on the bright half once the track was
  removed — neither of which any assert in the suite can see.

**The Wait screen** (`scripts/ui/wait_screen.gd`, autoload = `scenes/ui/wait_screen.tscn`, opened by
`InputManager.action_wait`, default **T**) is the clock's other half, and the asymmetry is the contract worth
recording: **HudClock only READS the clock; WaitScreen is the game's only clock WRITER** outside `WorldClock`'s
own `_process` and the save restore — and it writes through the EMITTING seam.

- **`advance_hours`, never `set_time_of_day`.** `WorldClock` deliberately offers two ways to move: a silent
  SEEK (`set_time_of_day` — a save restore, a debug jump, nothing may react) and a walk (`advance_by` /
  `advance_hours`) that emits `phase_changed` once per day/night boundary crossed, in order. Waiting has to be
  the walk, because `RentCollector` and `LedgerAccrual` both count DAWN crossings: a wait that seeked would let
  the player skip every dawn forever (no rent, no interest), and one that emitted a single transition would
  charge one day for three. `tests/test_world_clock.gd` pins the crossing counts, including the three-day case.
  The corollary subscribers must honour: **several transitions can arrive in one frame**, so a dawn handler
  must be idempotent-per-crossing and must not assume a frame elapses between calls.
- **Refusal reuses `StealthStatus.of_player`** — the same aggregate the stealth HUD reads — so "someone is
  hunting you" means one thing across the game. The threshold is `Level.CAUTION` or worse; a merely-filling
  detection meter deliberately does not block, or waiting would be impossible anywhere patrolled. It refuses to
  OPEN rather than opening a disabled card, because the screen frees the mouse and doing that mid-firefight
  would be worse than the missing panel; the reason goes out as a toast so the key never reads as dead.
- **A frozen clock refuses too.** `day_length_seconds = 0` is the authored way to pin a level to one hour, and
  the day/night docs promise that no dawn (and so no rent) ever fires there. That guard lives in the SCREEN,
  not in `advance_by`: the clock supplies the mechanism, and whether waiting is legal is policy.
- **Waiting is not resting.** It pays only a capped trickle (`GameSettings.wait`) and never mends limbs; the
  `Bonfire` keeps sole ownership of the full heal and the respawn checkpoint.

`scripts/tools/menu_qa_shots.tscn` is the menu screenshot harness: one windowed run
opens every menu screen (faking merchant/healer/corpse context off-tree like the GUT
tests do) and saves a PNG per screen —
`godot --path . res://scripts/tools/menu_qa_shots.tscn -- --shots-dir="<dir>"`.
Use it before/after any menu-layout change.

**A menu card is a fixed frame, not a box that grows.** A Control whose combined
*minimum* size beats its anchor band is not clipped or scrolled — Godot grows it past
the anchors and re-centres it, so the whole panel swells (off-screen at worst). Two
rules keep that from reaching the player: `MenuStyle.apply()` pins
`use_hidden_tabs_for_min_size = true` on every `TabContainer` under a menu root, so a
tab block reports the MAX page minimum instead of the current page's (switching tabs can
no longer resize the card); and each page must still fit *band − panel stylebox content
margins (the artist frame costs 72x76px) − pinned chrome − ~24px tab bar*.
`tests/test_menu_layout_stability.gd` measures both at 792x432 (the shortest real canvas)
for every tabbed screen; `scripts/tools/menu_size_probe.gd` prints the per-node
minimums when it fails. The budget math lives beside the code it constrains —
`character_creation.gd SHIRT_PAGE_HEIGHT_BUDGET`, `MenuSkin.slider_width_dense`.

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
- **Hotbar KIND dedupe degrades for a modded gun.** `hotbar.gd`'s "is this the same
  weapon?" comparisons are `slotted.weapon == it.weapon`, i.e. WeaponData object identity.
  A bench refit deliberately produces a NEW `WeaponData` object (that is what makes the
  swap chain re-run and the view model rebuild), so a modded pistol is no longer the same
  KIND as a stock one and may claim its own hotbar slot. This is **accepted, not
  overlooked** — a modded pistol genuinely IS a distinct weapon — but it means same-kind
  duplicates fall back to exact-instance matching. If it bites, the fix is to re-key
  `_slot_holds_weapon_kind` / `_is_equipped_kind` onto `Item.id` rather than to make the
  refit mutate in place.
- Docs drift quickly when review notes are kept around. Prefer current risk
  lists and delete artifacts that no longer match the code.
