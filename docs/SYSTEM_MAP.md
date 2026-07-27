# System Map

<!-- GENERATED FILE - DO NOT EDIT BY HAND.
     Regenerate:  godot --headless --path . -s scripts/tools/gen_arch_doc.gd
     Source of truth: `## @system / @seam / @risk / @test` blocks above class_name / autoload scripts
     under scripts/, managers/ + resources/. tests/test_arch_doc_sync.gd fails if this file is stale.
     Companion to the hand-written ARCHITECTURE_REVIEW.md + docs/CURRENT_ARCHITECTURE.md. -->

This index is generated from `@system` annotations in the code, so it cannot drift from the source.
For the deep narrative see [CURRENT_ARCHITECTURE.md](CURRENT_ARCHITECTURE.md); for current rough edges
see [ARCHITECTURE_REVIEW.md](../ARCHITECTURE_REVIEW.md).

_13 system(s), 27 entries - scanned scripts/, managers/ + resources/._

- [Control-Lock And Immunity](#control-lock-and-immunity)
- [Derived Stats](#derived-stats)
- [Economy](#economy)
- [Effect And Audio Seams](#effect-and-audio-seams)
- [Interaction](#interaction)
- [NPC Brain](#npc-brain)
- [Options Settings](#options-settings)
- [Passive Item Buffs](#passive-item-buffs)
- [Player Abilities](#player-abilities)
- [PS1 Warp](#ps1-warp)
- [Run And Level Flow](#run-and-level-flow)
- [Save Model](#save-model)
- [Save Model — the EXACT-snapshot tier (authored-NPC death/position + cross-level deaths + container contents)](#save-model--the-exact-snapshot-tier-authored-npc-deathposition--cross-level-deaths--container-contents)

## Control-Lock And Immunity

### `autoload InputManager` - `managers/InputManager.gd`

world_frozen() (cutscene OR dialogue engaged) is the sole cinematic damage-immunity predicate, distinct from gameplay_suppressed()'s control gate.

- **Risk:** Merging world_frozen() with gameplay_suppressed() silently grants immunity inside real-time menus, or strips it mid-cutscene — no crash, just wrong damage.
- **Risk:** A new control-lock added only to gameplay_suppressed() leaves the frozen player takeable; adding only to world_frozen leaks immunity — both silent.
- **Risk:** Immunity lives at 3 call sites (player.gd:2068, hazard_zone.gd:52, status_effect_manager.gd:31); a rename missing one silently un-gates that damage source.
- **Test:** `tests/test_world_frozen.gd`

### `class CutscenePlayer` - `scripts/components/cutscene_player.gd`

Static is_active() is the cutscene control-lock read by gameplay_suppressed() and world_frozen(); _finish() and _exit_tree() must always clear it (the tree never pauses).

- **Risk:** A mid-cutscene free (RELOAD respawn, level swap) leaving static `_active` set locks input all session with no cutscene visible — a silent, unrecoverable soft-lock.
- **Risk:** Any exit path (finish, skip, teardown) that skips _release_actors() leaves a staged NPC brain-suppressed / frozen forever with no error.
- **Test:** `tests/test_cutscene.gd` `tests/test_cutscene_actor.gd`

### `autoload DialogueManager` - `scripts/dialogue/dialogue_manager.gd`

is_engaged() (_active != null) = a conversation exists at all — the unpaused intro beat + the menu-suspension that is_active() hides — feeding world_frozen() immunity, Player.die() teardown, and _suspend_for_menu's box-hide + CONNECT_ONE_SHOT closed->resume one-shot.

- **Risk:** Dropping is_engaged() from world_frozen() (InputManager.gd:151) loses immunity in the unpaused intro beat — an enemy shoots the frozen player with no error (C66).
- **Risk:** die() gating on is_active() not is_engaged() skips abort() during a sub-menu suspension — the menu's close then re-pauses + re-opens the box over the death cinematic.
- **Risk:** A suspending sub-menu (Shop/Install/Chess) refuse path that returns WITHOUT emitting `closed` strands the convo _suspended forever — box hidden, tree paused, soft-lock, no crash.
- **Risk:** Speaker menus are duck-typed via has_method/has_signal scans (buy/sell, do_heal, install_carried, ai_search_depth, set_in_dialogue/died); a rename silently drops the option with no compile error.
- **Test:** `tests/test_dialogue.gd` `tests/test_dialogue_suspend_closed.gd` `tests/test_dialogue_speaker_contracts.gd`

## Derived Stats

### `class CharacterStats` - `scripts/player/character_stats.gd`

restamp_derived is the one strength/endurance re-stamp path LevelUp/PerkManager/PassiveItemBuffs funnel through; STAT_NAMES is the master stat-name const.

- **Risk:** Banking the ideal delta, not restamp_derived's returned post-floor delta, over-restores max_hp/carry on reverse once a value hit its floor — silent, permanent inflation.
- **Risk:** A new derived formula omitting baseline-0 neutrality or its maxf(0.0,..) floor slips the hand-listed baseline test and silently shifts balance for all baseline Characters.
- **Risk:** Dropping restamp_derived's guarded `damaged` emit leaves the HP HUD showing a stale max after a level-up/perk/trinket; no test asserts the emit, so it fails silently.
- **Test:** `tests/test_player_stats.gd`

## Economy

### `class MoneyPurse` - `scripts/inventory/money_purse.gd`

Mirrors `Character.money` into one derived `zorkmids` coin stack (1 unit = QUANTUM) in the player-only bag, self-heals it on any external bag touch, and register_mirror's it as a VIEW.

- **Risk:** If GameState.capture stops skipping `Zorkmids.ITEM_ID`, the coin stack is double-persisted; on load sync() reconciles the reloaded tile to `money` so the wallet does NOT inflate (push-only mirror) — only the single-source invariant breaks.
- **Risk:** If `is_mirrored` wrongly reads TRUE for a real loot source carrying a separate `money` float (corpse/container/pickpocket NPC), taking its coin tile ALSO debits that float -> that cash silently destroyed (F-C37 test guards it).
- **Risk:** If the `_syncing` latch breaks, each external bag touch fires a redundant second sync + extra changed/autosave churn (idempotent set_item_count stops it short of infinite recursion).
- **Test:** `tests/test_money_purse.gd` `tests/test_loot_drop.gd`

### `autoload LootScreen` - `scripts/ui/loot_screen.gd`

`_take` on a zorkmids tile credits real `add_money` (never `transfer_to`) and debits the source's `money` float only if `is_mirrored(item)`.

- **Risk:** Drop the `is_mirrored` guard: taking a live-pickpocket NPC's coin tile also debits its separate pocket float — that cash is destroyed silently.
- **Risk:** `transfer_to`'ing a zorkmids tile (vs `add_money`) lets the player's purse trim it back to the wallet value — the take silently evaporates.
- **Test:** `tests/test_loot_drop.gd`

## Effect And Audio Seams

### `autoload AudioManager` - `managers/AudioManager.gd`

One-shot SFX seam: play_sfx/play_2d_sfx spawn self-freeing players on the sfx bus (default) so volume sliders apply; play_applause is the shared kill+pet cheer; stop_sfx cuts all sfx-bus players, freeing only ONE_SHOT_META ones.

- **Risk:** A sound spawned bare (not via play_sfx) lands on Master and silently ignores the SFX volume slider — no error; the bus=&"sfx" default is the only guard.
- **Risk:** Re-adding a local applause copy in death.gd/pettable.gd instead of calling play_applause drifts the kill vs pet cheer apart, and no test asserts they delegate.
- **Test:** `tests/test_audio_manager_spawn.gd` `tests/test_autoload_order.gd`

### `autoload EffectFactory` - `managers/EffectFactory.gd`

EffectFactory autoload owns ONE gameplay spawn (spawn_blood_particle) over a null-safe spawn_at that auto-emits+frees particles; it is NOT a VFX registry.

- **Risk:** Re-adding a per-effect slot or spawn_* wrapper is a silent no-op unless it routes through spawn_at AND a call site reads it (the removed slots failed exactly this way).
- **Risk:** The instantiate()-null guard returns null with NO log at all (only the null-scene path warns) — an empty/broken effect scene yields zero VFX silently, no crash, easy to miss.
- **Test:** `tests/test_managers_tuning.gd` `tests/test_autoload_order.gd`

## Interaction

### `class LookAtInteractable` - `scripts/components/look_at_interactable.gd`

Owns the duck-typed talk-handler surface (start_talk/can_be_talked_to/look_name/host_npc/set_look_highlight) + TALK_LAYER hitbox + outline that PickupRay resolves and calls by name, so every interactable subclass plugs into the ray unchanged.

- **Risk:** Rename or re-signature a talk-handler method (start_talk/can_be_talked_to/look_name/set_look_highlight): PickupRay's has_method calls silently no-op, so the subclass stops interacting/highlighting with no error or failing call-site test.
- **Risk:** A subclass overrides _ready without super() or without setting collision_layer=TALK_LAYER (Merchant-style): the talk ray never hits the hitbox (base _ready:40 is the only thing joining the talk layer) and the object is silently un-interactable.
- **Test:** `tests/test_look_at_interactable.gd`

### `class PickupRay` - `scripts/components/ray_cast.gd`

_query_talk_handler is THE line-of-sight wall-gate for every look-at interactable (pickup/loot/talk/doors): its talk-ray is gated by _interaction_occluded (a second solid-body ray, target's own bodies excluded).

- **Risk:** Broaden the occlusion mask or drop the target-own-body exclusion (ray_cast.gd:442-443): silent interact-through-walls, or a dropped item self-occludes and is unpickable on open floor.
- **Risk:** Break the closer-prop block (ray_cast.gd:77-83, 306-309): a covered NPC lights up/reads out through a crate, or a dual item's own body blocks its own stash.
- **Risk:** Remove the liveness bail (ray_cast.gd:60-62): a mid-death-cinematic E/Z/click grabs/interacts/throws — the prop survives the revive or freezes the cinematic.
- **Test:** `tests/test_interaction_occlusion.gd` `tests/test_pickup_ray_liveness.gd` `tests/test_interact_prompts.gd` `tests/test_carry_step_over.gd`

## NPC Brain

### `class GoapExecutor` - `scripts/npc/goap/goap_executor.gd`

tick() replans only when the current action is null/invalid, else steps act(); FAILED drops the plan; _build_world_state never senses sentinel facts.

- **Risk:** If _build_world_state senses a sentinel fact, its goal self-satisfies -> plan()=[] -> select_goal skips it, so that behaviour silently never runs.
- **Risk:** decide() resets index=0, so if tick() replanned every frame a multi-step plan (reload->shoot) would never advance past step 0 - silent, no error.
- **Risk:** advance() must drop the plan on FAILED (goap_executor.gd:42-45), else a still-valid failing action is re-stepped every tick - the NPC sticks, no error.
- **Test:** `tests/test_goap_executor.gd` `tests/test_goap_combat_brain.gd` `tests/test_goap_combat_selection.gd`

### `class NPC` - `scripts/npc/npc.gd`

_build_components builds one GoapExecutor per NPC; _physics_process ticks it as the sole AI decision layer in both physics branches (npc.gd:814,1832,1873).

- **Risk:** An early-return or reorder before _executor.tick in either _physics_process branch (npc.gd:1831/1872) silently stops that NPC deciding, no error.
- **Risk:** _perception.sense (1845) must precede the has-target tick (1872); the executor reads _perception.state (goap_executor.gd:83), so reordering picks the wrong arm silently.
- **Risk:** In-tree tick and _act_* delegate bodies have no automated coverage (tick is playtest-only per README) — a broken build/ordering shows only in playtest.
- **Test:** `tests/test_npc_goap_library.gd` `tests/test_npc.gd`

## Options Settings

### `autoload InputManager` - `managers/InputManager.gd`

get_action_binding(action) is the sole binding-query seam (display_key is a kept alias); validate_action_sources() cross-checks the three action-name surfaces (project.godot [input] / action_* vars / ActionCatalog) and _warn_on_action_drift() push-warns per drifted name at boot on dev builds.

- **Risk:** A new action_* var without an ActionCatalog row (or a catalog row on a dead InputMap action) still needs the catalog / _CONTROLLER_ONLY fixed by hand — the boot audit REPORTS the drift, it does not auto-repair it.
- **Test:** `tests/test_input_manager.gd`

### `autoload Settings` - `managers/Settings.gd`

Each option = a typed var + a set_* setter that applies live (DisplayServer/AudioServer/GameSettings) and re-saves settings.cfg; gameplay reads Settings.<field> directly.

- **Risk:** A field left out of apply_all (or a setter skipping apply) persists but never takes effect on boot; nothing round-trips save->load (tests set _loaded=false).
- **Risk:** A bus fade/duck that samples the live AudioServer bus instead of current_bus_db() ratchets volume down on rapid re-trigger — silent audio drift.
- **Risk:** Moving a typed field into a Variant dict silently breaks gameplay's direct Settings.<field> reads and the bare-instance test that reads them.
- **Test:** `tests/test_settings.gd` `tests/test_difficulty.gd`

### `class SettingSpec` - `resources/settings/SettingSpec.gd`

One Options row as DATA (widget + getter/setter names); OptionsMenu emits each value row from SettingsCatalog.tres, resolving each spec's getter/setter on the Settings autoload BY NAME.

- **Risk:** getter/setter resolve on Settings BY NAME (options_menu.gd:281-296): a typo or renamed setter breaks that one row only at menu-open; caught by test_settings_catalog if run.
- **Risk:** A generic DROPDOWN loses its options on an editor .tres re-save -> empty in-game menu; window_mode/colorblind/difficulty stay CUSTOM (code-built) to dodge it (a recurred bug).
- **Risk:** Hand-authoring a KEYBIND row in the catalog instead of ActionCatalog.tres double-authors the Controls tab (keybind rows are appended from the ActionCatalog).
- **Test:** `tests/test_settings_catalog.gd` `tests/test_options_menu.gd` `tests/test_difficulty.gd`

### `class ActionCatalog` - `scripts/input/action_catalog.gd`

keybind_specs() turns its ActionSpec rows into the Controls-tab SECTION+KEYBIND SettingSpecs OptionsMenu appends to SettingsCatalog; the action name is the stable rebind key.

- **Risk:** A dropped/renamed ActionSpec silently drops its Controls rebind row (no runtime error) since keybind_specs skips it; caught only at test time by the EXPECTED_REBINDABLE pin.
- **Risk:** Keybinds bind LIVE in _input via Settings.rebind_action, bypassing the _pending/Apply staging other rows use — the key-press IS the confirmation, not an Apply-staged value.
- **Risk:** project.godot [input], InputManager action_* vars, and ActionCatalog.tres must stay in lockstep; drift yields an un-rebindable action or a catalog row on a dead InputMap action — now caught at boot (dev builds) by InputManager.validate_action_sources()'s push_warning, not only at test time.
- **Test:** `tests/test_action_catalog.gd` `tests/test_input_action_catalog.gd` `tests/test_input_manager.gd`

## Passive Item Buffs

### `class PassiveItemBuffs` - `scripts/components/passive_item_buffs.gd`

Exposes a stat_modifier/speed_multiplier/apply_effect surface Character sums/multiplies; held strength re-stamps via CharacterStats.restamp_derived; serializes nothing.

- **Risk:** If max_hp is ever serialized as a stored number, the held +HP/+carry delta double-counts each reload; the carrier silently gains stats, no error.
- **Risk:** If _restamp tracked the ideal delta instead of restamp_derived's real post-floor return, dropping a negative-strength item silently inflates max_hp/carry above base.
- **Risk:** If apply_effect or the method names drift from Character's has_method scanner, every held buff silently stops folding into live stats/speed, no crash.
- **Test:** `tests/test_passive_item_buffs.gd`

## Player Abilities

### `class Ability` - `scripts/components/abilities/ability.gd`

An enabled Ability child grants the mechanic keyed by ability_id(); has_mechanic, unlocked_list (save) and the runtime rebuild all match that id. The grant/revoke/persistence bookkeeping lives in AbilityManager (a Player-owned RefCounted); the Player keeps only the typed hot-path refs + physics beats.

- **Risk:** A subclass that forgets to override ability_id() defaults to &"" (ability.gd:22-24): present but grants no queryable mechanic — silent, no crash.
- **Risk:** An id whose ability script is absent from disk (breaks the AbilityRegistry snake_case naming convention) can't be rebuilt on save-load or paid install (AbilityManager._build -> null, silently grants nothing); AbilityRegistry.can_build + the drift test guard it.
- **Test:** `tests/test_upgrades.gd`

### `class ChipInstaller` - `scripts/components/chip_installer.gd`

Paid-install chokepoint: a chip Item (installs_ability) -> permanent mechanic via can_grant guard -> charge -> consume -> unlock_mechanic + autosave.

- **Risk:** Drop the pre-charge can_grant_mechanic guard (chip_installer.gd:162,182): a typo'd installs_ability then silently takes money + eats the chip for nothing.
- **Risk:** Rename install_carried/install_fee (chip_installer.gd:95,154): the DialogueManager/ChipInstallScreen has_method duck-type check fails silently and the 'Install' option just vanishes.
- **Test:** `tests/test_chip_install.gd`

## PS1 Warp

### `file ps1_applier.gd` - `scripts/effects/ps1_applier.gd`

Runtime ShaderMaterial overrides on opaque BaseMaterial3D surfaces only, skipping Character/Throwable/Camera3D; live-scaled by Settings.ps1_warp_intensity, and 0% restores originals.

- **Risk:** If _warp's Character/Throwable/Camera3D skip regresses, actor outline/hit-flash and the FP view-model warp silently — no test covers the subtree walk.
- **Risk:** If _restore stops clearing overrides or restoring cast_shadow, 0% no longer returns the world to normal — an accessibility regression with no round-trip test.
- **Test:** `tests/test_ps1_applier.gd` `tests/test_effects.gd`

### `autoload Ps1Warp` - `scripts/effects/ps1_warp.gd`

GameRoot drives Ps1Warp.cover() on level load; cover() parents ONE ps1_applier under the LevelRoot (freed with it), not a global SceneTree.node_added listener.

- **Risk:** If the LevelRoot gate breaks or GameRoot stops calling cover(), levels get no applier and the PS1 look silently disappears; test_level_data.gd::test_game_root_load_level_covers_a_levelroot_with_the_ps1_warp asserts the applier attaches on load.
- **Test:** `tests/test_global_node_added_listeners.gd` `tests/test_level_data.gd`

## Run And Level Flow

### `class GameRoot` - `scripts/world/game_root.gd`

GameRoot is game.tscn's level-load seam: resolve_boot_level picks the boot level (saved-by-path beats export); load_level swaps the single "Level" child and seeds PlayerSpawn + respawn.

- **Risk:** resolve_boot_level diverging from the line-38 respawn_level_matches gate boots the WRONG level yet keeps the saved respawn — silent, no crash (game_root.gd:38, :93-96).
- **Risk:** A should_place_at_spawn regression either clobbers a loaded game's restored respawn with the export spawn, or strands the player at stale wrong-level coords (game_root.gd:44, :157-172).
- **Risk:** If the load_level detach-rename-queue_free swap regresses, two "Level" children stack or refs to the freed level dangle mid-frame — silent stale geometry (game_root.gd:108-120).
- **Test:** `tests/test_level_flow.gd` `tests/test_level_boot_lifecycle.gd` `tests/test_level_data.gd`

### `class LevelData` - `scripts/world/level_data.gd`

resource_path persists as GameState.current_level_path for Continue; a non-null `scene` gates boot-viability, else GameRoot uses the exported level.

- **Risk:** A LevelData with a blank/unstable resource_path persists no resolvable path, so Continue silently boots the export, losing the saved level (game_root.gd:83, :106).
- **Risk:** A saved LevelData whose `scene` is null is rejected by resolve_boot_level, which silently boots the export instead of the saved level (game_root.gd:86, :93-96).
- **Test:** `tests/test_level_data.gd` `tests/test_level_flow.gd`

## Save Model

### `autoload GameState` - `managers/GameState.gd`

The additive per-object ledger world_objects[level][key]=state (record_object_state/object_state/has_object_state, :779-797) persists Door open/locked + consumed-pickup/destroyed-prop 'gone' bits per authored object.

- **Risk:** A changed WorldSaveId key or a stricter :247-258 Dictionary-shape filter silently drops ledger entries — pickups respawn (free money), doors revert, smashed props un-smash; load still returns true.
- **Risk:** Reading a 'gone' bit with bare truthiness instead of GameState.as_bool falsely despawns a fresh pickup (or crashes via bool(<String>)) on a hand-edited String value.
- **Risk:** A new persistable object type not wired through record_object_state + a save_id export silently never enters the ledger — its state just doesn't persist.
- **Test:** `tests/test_game_save.gd`

### `autoload GameState` - `managers/GameState.gd`

capture() -> save_to_disk atomically write the versioned user://gamestate.cfg; load_from_disk restores it and sets loaded/profile_active, the flags gating Player._ready — a checkpoint, not a world snapshot.

- **Risk:** Breaking _write_atomic's tmp->bak->rename rotation (e.g. dropping the Windows remove-before-rename guard) only loses the sole save on a real crash; the happy path keeps succeeding, so tests never surface it.
- **Risk:** A field wired into only some of capture/save_to_disk/load_from_disk silently defaults on Continue; a STAT_NAMES rename with no SAVE_VERSION migration drops those points (cf. :228).
- **Risk:** Dropping capture()'s Zorkmids.ITEM_ID skip (:420) double-counts money on load; applying respawn_position while ignoring respawn_level_matches teleports the player into the wrong level.
- **Test:** `tests/test_game_save.gd` `tests/test_save_slots.gd`

### `file world_save_id.gd` - `scripts/world/world_save_id.gd`

WorldSaveId.key_for(node, save_id): an authored save_id is the whole key 'id:<x>' (survives moves), else a level|path|position (_round_cm) fallback — the shared GameState.world_objects key generalizing Corpse.save_key().

- **Risk:** Changing the fallback shape (node_path source or _round_cm precision) silently re-keys every un-authored object, so its saved state stops matching on reload — no error.
- **Risk:** Moving/renaming a hand-placed node between saves silently orphans its fallback-keyed state; give important objects/bodies a save_id or their world-state is lost after any layout edit.
- **Test:** `tests/test_game_save.gd`

## Save Model — the EXACT-snapshot tier (authored-NPC death/position + cross-level deaths + container contents)

### `file world_snapshot.gd` - `scripts/world/world_snapshot.gd`

Rides the MANUAL quicksave/slot layer ONLY: built in GameState._capture_and_write, written as a sibling

- **Risk:** This is a SEPARATE product from the profile save. Never merge it into GameState's profile fields / capture()
- **Risk:** NPC identity is POSITION-INDEPENDENT (NPC.snapshot_key), NOT WorldSaveId.key_for — an NPC moves, so a
- **Test:** `tests/test_world_snapshot.gd`
