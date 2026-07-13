# Architecture & Code Review — 2026-07-11

Successor to `architecture-review-2026-06-30.md`. That review's headline defect
(non-atomic autosave, F31) is **fixed** — the save is now atomic (`.tmp`/`.bak`
rotation) with a version stamp. This pass focuses on what the last ~10 days of
work added: the microchip-install economy, blindfold chess, hotbar holdables,
the MoneyPurse coin-tile mirror, the tetris inventory grid, the 6-stat overhaul,
and the global Ps1Warp autoload.

**Method.** 9 subsystem mappers → 11 scoped finders (correctness + cohesion) +
2 architecture reviewers → adversarial verification of every finding (a "refute"
skeptic on all; a second "reproduce" skeptic on high/critical) → completeness
critic → 3 gap finders. 124 agents. **68 findings survived verification; 16 were
refuted; 1 is unresolved.** The refuted list is at the end so they aren't
re-reported.

---

## The cohesive story

The codebase is still the disciplined, designer-first prototype the last review
described. The strengths hold: GOAP is the cleanest boundary in the project, the
`@tool` byte-level hazard defenses are intact, the combat hit-seam is shared and
tested, corrupt-save reads degrade field-by-field. **Almost none of the 68
findings are "this system is wrong."** They are the *seams between* systems —
and they cluster into a handful of recurring classes. Fixing the class is worth
far more than fixing each instance.

The dominant class, by a wide margin:

> **A new player-facing screen has to be hand-registered in 4–5 different places.
> The registries are hand-maintained lists with no drift test. Every new feature
> forgets at least one.** ChessScreen (the newest) was correctly added to all
> three `InputManager` lists but missed `Player._close_open_modals`, `OptionsMenu`,
> and `LootScreen` — 2 of 5 registries, in one week. This one root cause generates
> ~12 of the findings below.

The second and third classes are the same shape — a convention that lives as
N hand-copied call-sites instead of one chokepoint, so the two newest systems
composed a hole into it:

- **No death/liveness gate.** The player stays in-tree through the multi-second
  in-place-revive cinematic (by design). `die()` disables only `MouseInput` and
  trusts "the rest gate on `_dead`" — but PickupRay, the Attack coroutine, the
  hotbar, and quick-save/load don't.
- **The zorkmids coin tile.** "Special-case `Zorkmids.ITEM_ID`" is copied across
  6 surfaces instead of being one predicate; the hotbar-hold path and the
  MoneyPurse mirror (both 2026-07-09) are the two that don't have the guard.

Everything else is genuine but narrower: save-fidelity gaps in the *new* fields,
the invisible-unplaced-grid-stack problem the tetris rollout made reachable,
a few chess/chip money bugs, and a batch of duplication/designer-first leaks.

---

## Priority 0 — run & feature integrity (fix first)

### P0-1 · New Game grants every ability for free — the chip economy is bypassed
`scenes/game.tscn:38` · **verified by direct inspection**

The 2026-07-09 overhaul's core promise is a fresh game starts with **zero**
abilities and you pay a `ChipInstaller` for each. `Player.tscn:55` correctly has
`starting_unlocks = []`. But `game.tscn` — the scene `StartMenu` boots for New
Game — overrides it:

```
starting_unlocks = Array[String](["laser_sight","wall_climb","air_dash","slide","grapple_hook","grapple"])
```

So a new game hands the player the whole movement kit up front and the entire
chip-install loop is dead content. (`grapple_hook` also looks bogus — not an
`AbilityRegistry` id; `grapple` is the real one.) No test caught it because
nothing pins the zero-ability contract.
**Fix:** empty the `game.tscn` override; add a scene-contract test that
instantiates `game.tscn`, finds the Player, and asserts `starting_unlocks.is_empty()`
(and that any id present is a real `AbilityRegistry` id).

### P0-2 · A New-Game session's next autosave can overwrite the run with a fresh build
`scripts/player/player.gd:2378` · save-load

`GameState.loaded` is set true **only** in `load_from_disk`. `reset_for_new_game`
sets it false, and nothing in a New-Game session flips it back. Every restore in
`Player._ready` (unlocks/perks/xp/level/inventory/money/reputation/respawn) is
gated on `loaded`. The `RELOAD_CHECKPOINT_FRESH` death mode calls
`reload_current_scene()` with no `load_from_disk`, its comment claiming "the
in-memory profile carries over" — but in a New-Game session `loaded` is still
false, so the fresh Player reseeds a default build and the next milestone
autosave writes it to disk. Latent run loss.
**Fix:** separate "a profile is authoritative in memory" from "a file was read
from disk" — set a `profile_active` flag both in `load_from_disk` and after
character creation, and gate `_ready`'s restores on that (or have
`RELOAD_CHECKPOINT_FRESH` call `load_from_disk` first).

### P0-3 · An unplaceable coin tile makes a corpse unlootable and its ragdoll never fades
`scripts/ui/grid_inventory_view.gd:380` · inventory-economy · **HIGH**

`CharacterInventory` deliberately keeps stacks that don't fit the grid "in the
bag but unplaced (x<0)". `GridInventoryView` gives unplaced stacks **no surface
at all** — `_sync_tiles` skips `x<0`, `_key_at_cell` ignores them, no list
fallback — so they can't be clicked, dragged, taken, or dropped. Because
LootableCorpse rebuilds a corpse copy and seeds its wallet as a coin tile, a
corpse whose coin tile doesn't fit is permanently unlootable, and the
drain-check that fades the ragdoll never completes. This is the planned-but-never-built
`B-F24` overflow strip; turning grids on for everyone (tetris rollout, 2026-07-09)
made the unplaced state far more reachable.
**Fix:** ship the overflow strip (render unplaced stacks in a click-only strip
under the grid), or re-run placement when cells free, or at minimum let
corpse/container drain-checks ignore unplaced-only remainders so ragdolls fade.

### P0-4 · Stealth, thrown-decoy noise, and body-discovery go dead exactly when the player is in sight range
`scripts/npc/npc.gd:1805` · npc-ai · **HIGH**

`_react_unaware` is the **only** consumer of the `&"noise"` channel (thrown
decoys, gunfire/death-cry pings) and of `Corpse` body-discovery, and it runs
**only in the no-target branch**. But `NpcTargeting` binds a target by pure
proximity (hostile + within `sight_range`, no LOS/perception gate), so every
hostile guard holds the player as `_target` the moment the player is inside
`sight_range` (default 25 m) — even while perception is UNAWARE. The has-target
branch never scans the `&"noise"` group or corpses. Net effect: throwing a decoy
to distract a guard, or hiding a body, does nothing whenever you're within sight
range — which is exactly when you'd want to. (Same shape as the known
"idle/UNAWARE reactions must run BOTH physics branches" lesson.)
**Fix:** run the distraction/body sensing in the has-target branch too while
`_perception.state == UNAWARE` (mirror the `_react_music` both-branches fix).

---

## Theme 1 — the modal-registry / hand-list drift (highest-leverage fix)

**Root cause:** adding a pausing screen requires editing up to 5 hand-lists:
`InputManager.gameplay_suppressed()`, `._modal_screens()`, `.any_pausing_open()`,
`Player._close_open_modals()`, plus surviving inline gates in `OptionsMenu.open()`
and `LootScreen._open`. None cross-checks the others.

**The one fix that kills the class:** make `InputManager._modal_screens()` the
single registry consumed by all surfaces (suppression, pause query, death-close,
per-screen open-gate), then add a drift test asserting every entry appears in
each derived list and in `player.gd`'s close-sweep as `<Name>.close()`. Rewrite
`_close_open_modals` as `for m in InputManager._modal_screens(): if m.is_open(): m.close()`.

Instances (all confirmed):

- **C15/C19/C29** `player.gd:2256` — `_close_open_modals` omits **ChessScreen**
  (newest pausing modal) and **NameEntryDialog**. The pet-naming box is real-time
  by design, so an enemy killing you mid-name leaves the box floating over the
  death cinematic *and* the revive. The function's own comments record this exact
  miss happening twice before (QuestJournal, ChipInstallScreen).
- **C40/C48** `options_menu.gd:71` & `loot_screen.gd:137` — pre-M5 inline
  stack-guard lists never extended to ChessScreen/ChipInstallScreen. Currently
  masked only by autoload registration order deciding Esc delivery — fragile, not
  safe.
- **C23** `tests/test_modal_registry.gd:75` — the drift guard that exists to pin
  this was never extended to the two newest modals, and the invariant it guards
  has already drifted.
- **C58/C60** `InputManager.gd:101`, `project.godot:26` — three parallel
  hand-lists with no consistency test; the screen-as-autoload pattern (29
  autoloads, ~15 screens) taxes every feature with 4–5 registrations and rests on
  unasserted registration-order contracts.
- **C26** `player.gd:1747` — `_update_save_input()` (F5/F9 poll) runs *before*
  the suppression gate; `GameState._load_and_reload` closes no modals, so
  quickload reloads the scene under open autoload screens now holding freed refs.

## Theme 2 — no death/liveness gate on input & interaction during the cinematic

**Root cause:** `die()` disables only `MouseInput`; the player node stays in-tree
and its children keep processing through the revive cinematic. Several surfaces
don't check `_dead`/`_dying`.

- **C9** `ray_cast.gd:53` — PickupRay has no death gate; a prop grabbed during
  the cinematic survives the in-place revive with the carry draw-lock cleared but
  still carrying. (SilentTakedown/Pet/Claim/Hotbar all *do* gate on death.)
- **C14** `ray_cast.gd:54` — the E-interact has no liveness gate; a dead player
  can open shop/heal/chess mid-cinematic, and those pausing screens freeze the
  cinematic.
- **C10** `attack.gd:292` — the fire coroutine's post-`await` guards check only
  `current_weapon`/`is_inside_tree`; a queued shot still fires after holster,
  carry-lock, dialogue start, or player death (posthumous muzzle flash/damage).
- **C11** `hotbar.gd:134` — hotbar (weapon swap / medkit / hold) and PickupRay
  E/Z grabs stay live during cutscenes and the name-entry dialog, unlike every
  other combat input (which gates on `gameplay_suppressed()`).
- **C18** `player.gd:408` — dying mid-carry force-releases a bag-pulled prop into
  the world and clears its inventory reservation; the death-milestone autosave
  then writes a profile without it → quit before re-collecting loses it. Stash it
  back instead of releasing.

**Fix for the class:** a single `player.is_alive()` bail at the top of
PickupRay/Hotbar input, and re-check `holstered/draw_locked/is_alive` after every
`await` in the fire coroutine.

## Theme 3 — the zorkmids coin tile composes badly with the two newest systems

**Root cause:** "special-case `Zorkmids.ITEM_ID`" is 6 per-surface copies, not a
chokepoint. `zorkmids.tres` is a MISC item with a `world_model` (so its tile
renders the bag mesh), which makes `Item.is_holdable()` true.

- **C13/C28** `item.gd:138`, `hotbar.gd:207` — the coin tile is hotbar-assignable
  and holdable; assigning + activating mints a physics money-bag prop from nothing
  while MoneyPurse instantly re-mints the debit.
- **C37** `loot_screen.gd:269` — taking a zorkmids tile from a *live pickpocket*
  target also debits the NPC's separate `money` float (NPCs have no MoneyPurse) —
  the two wallets aren't mirrors, so loot is destroyed.
- **C12** `character_inventory.gd:416` — `transfer_to`'s "atomic" rollback
  ignores its `add()` return; MoneyPurse re-fitting the grid mid-transfer (its
  latch only guards its own writes) can consume the freed cells and silently
  destroy the rolled-back item.

**Fix for the class:** put the guard at the chokepoint — `Item.is_holdable()`
returns false for `Zorkmids.ITEM_ID`; add a `CharacterInventory.is_mirrored(item)`
predicate the purse registers so every transfer surface asks one place; make
`transfer_to` restore by captured key/placement before emitting `changed`.

## Theme 4 — save/load fidelity of the *new* fields

The atomic-save fix landed, but fields added since aren't all covered.

- **C16** `money_pickup.gd:47` — MoneyPickUp and UpgradePickup never record a
  `world_objects` "gone" bit (CanPickUp/CanDestroy do), so consumed pickups
  respawn on every Continue → infinite-money quit/reload loop.
- **C17** `GameState.gd:190` — `String()`/`float()` constructor casts on persisted
  Variants in the load path (violating the file's own "read through `_cfg_*`"
  contract); one junk-typed key raises "invalid constructor," aborts
  `load_from_disk` before `loaded = true`, and the first autosave then overwrites
  the save with a fresh profile. Use `str()` + numeric guards.
- **C42** `hotbar.gd:18` — hotbar layout is not serialized at all; manually
  assigned holdable props drop off the bar on reload and custom arrangements
  revert, contradicting the in-file save claim.
- **C43** `GameState.gd:211` — no migration for the stat overhaul: pre-2026-07-09
  saves' `persuasion` points are silently dropped (streetwise loads 0) with no
  refund and no `SAVE_VERSION` bump. This is the first real use for the H1b
  version seam — fold the legacy key and bump to v2.
- **C44** `GameState.gd:651` — `reset_for_new_game` doesn't clear `_load_warnings`,
  so a failed boot-load's quest warnings toast on a brand-new game.
- **C45** `can_pick_up.gd:55` — reads the "gone" ledger bit by Variant truthiness
  instead of `GameState.as_bool` (Door does it right); inconsistent guarding.

## Theme 5 — chess & chip money seams (new feature, untested money paths)

- **C20/C27** `chess_screen.gd:129` — a wagered match against a **White** opponent
  auto-plays the AI's first move into `_san_log`; `close()` forfeits on
  "any move exists," so opening such a table and pressing Esc without moving costs
  the full wager. Track a *player*-move flag; move settlement out of `close()`.
- **C21** `chip_installer.gd:158` — install charges money, consumes the chip,
  toasts "installed," and autosaves even when `unlock_mechanic` resolves the id to
  nothing (typo'd `installs_ability` enum-suggestion string). Two divergent
  ability registries: runtime uses `Player.ABILITY_SCRIPTS`, tests check
  `AbilityRegistry.ids()`. Verify the grant is resolvable *before* charging; add a
  drift test that every `AbilityRegistry` id maps in `ABILITY_SCRIPTS`.
- **C25** `chess_screen.gd:226` — the engine/AI are perft-verified, but wager
  settlement (win/lose payout, forfeit deduction, refuse-when-broke) has **zero**
  tests. Extract `amount = f(result, wager, moves_played, finished)` and unit-test it.
- **C24** `test_dialogue_speaker_contracts.gd:16` — the duck-type contract test
  pins only 2 of the 5 methods `ChessScreen.open_match` calls on a ChessMatch
  (`ai_blunder`/`player_is_white`/`wager_amount` unpinned) → a rename passes the
  suite and crashes at match start.

## Theme 6 — pause / cutscene propagation to ALWAYS-process side effects

- **C34** `cutscene_player.gd:47` — cutscenes mark the game "logically paused"
  via a static flag only; they never set `get_tree().paused` (dialogue and every
  pausing menu do). So hazard damage, DoT, and NPC fire keep hitting a
  control-locked, fully-damageable player through a cutscene. Pause the tree for
  the cutscene (keep the player ALWAYS), or add a shared `world_frozen()` helper.
- **C66** `dialogue_manager.gd:139` — the ~0.5 s dialogue intro locks player
  control before pausing the tree, so a hazard/DoT tick can land during the intro
  of any conversation started while standing in a hazard. Sub-second; document or
  gate.

## Theme 7 — NPC AI edge cases (beyond P0-4)

- **C6** `npc_locomotion.gd:121` — a scripted `investigate()` on a FLEE-response
  NPC null-derefs `_aim_point()` (Flee has no target precondition) → per-frame
  errors + frozen NPC. Guard `_aim_point`, or flee from `last_known_position`.
- **C7** `npc.gd:1906` — `_discover_corpse` during a stale-DETECTING drain
  permanently marks a corpse discovered (persisted) without any investigation.
  Restrict the corpse fallback to UNAWARE.
- **C8** `npc.gd:1790` — the retarget throttle is defeated for every *target-less*
  NPC (`_target_invalid()` is true when `_target` is null), so the full O(n)
  acquire scan runs every physics frame for most of the cast. Treat "no target" as
  valid-idle.
- **C5** `weapon_stance.gd:91` — an NPC with a partial clip but empty reserve
  spams the empty-click SFX every frame and never holsters (out-of-combat reload
  branch missing a `has_reload_supply()` gate).
- **C35** `goap_profile.gd:100` — `validate()` skips the `hp_scales`/
  `temperament_scales` rows, so a typo'd row silently no-ops.
- **C36** `npc.gd:1834` — give-up flags leak across engagements when the target
  dies/frees while engaged; the "combat over" bark fires at the *start* of the
  next engagement (invisible today only because bark pools ship empty).

## Theme 8 — faction / reputation (a gap the last review didn't cover)

- **C32** `npc.gd:940` — `forgive_provoke()` clears the `_provoked` flag but not
  the rep it dropped; for a **factioned** NPC, disposition reads faction rep, and
  with shipped tuning (`provoke_penalty=30`, `hostile_threshold=-25`) the *first*
  provoke pushes the whole faction permanently hostile — holstering can never
  de-escalate. Restore the penalty on forgive, or correct the "stand down" docs.
- **C33** `encounter_spawner.gd:80` — `auto_aggro` calls `provoke()` per squad
  member with `apply_rep=true`, so spawning N enemies drops faction rep by
  N × penalty in one trigger — the exact multiplication `provoke()`'s own docstring
  warns about (alarm_panel guards it; this doesn't). Provoke with `apply_rep=false`.
- **C64** `neutral_wildlife.tres:1` — hand-written malformed UID
  (`uid://faction_wild000`); let the editor regenerate it.
- **C65** `test_npc_vs_npc.gd:19` — no test pins that shipped `raiders.tres` is
  HOSTILE-on-sight at rep 0 (tests build synthetic NEUTRAL raiders), so a content
  flip to NEUTRAL would silently pass.

## Theme 9 — duplication & designer-first leaks (cohesion)

- **C61** `level_up.gd:92` — the strength→max_hp/carry re-stamp algorithm is
  triplicated across LevelUp / PerkManager / PassiveItemBuffs and has **already
  drifted**: LevelUp moves `hp` raw (no clamp, no `damaged` signal), PerkManager
  clamps but no signal, PassiveItemBuffs clamps + emits + tracks post-floor delta.
  Extract one `CharacterStats.restamp_derived(...)`.
- **C63** `weapon_audio.gd:21` — `NPC_IMPACT_VOLUME_DB` is a designer-tunable
  audio-mix value shipped as a hardcoded const duplicated in two files (violates
  both the designer-first and single-source rules). Move to the `GameSettings.audio`
  group.
- **C31** `pet_interaction.gd:18` — Pet/Claim hardcode `RAY_REACH=4.0` while their
  `@export_range` sliders advertise 6.0/8.0, so a designer setting max_range above
  4 gets a silently dead verb (the takedown twin reads range from a tuning
  resource — inconsistent). Probe to the slider max, or clamp the export hint.
- **C62** `gun_fx.gd:21` — the explosion-scene reimport-recovery idiom is
  copy-pasted verbatim into 3 files (two byte-identical, one hand-rolled variant).
  One `Explosion.instantiate_recovering()` static.
- **C-P1 (unresolved)** `GameState.gd:36` — the stat-name list is hand-mirrored in
  **4 files** (`character_stats.stat_names()` which claims to be "the single
  source," `GameState.STAT_NAMES`, `level_up.STAT_NAMES`, and the stats UI). A
  stat missing from `GameState.STAT_NAMES` is silently dropped from every save —
  the same drift that reportedly lost `agility` once. Verifiers split on whether
  it's currently exploitable; treat as a real latent hazard. Make the others
  derive from `CharacterStats.stat_names()`.

## Theme 10 — physics layer bitmask/index confusion (held-prop contract)

- **C67** `PhysicsDamageSettings.gd:62` — `pickup_held_collision_layer: int = 4`
  is the pivot of the entire held-prop-sight-transparent contract; PickupRay writes
  it as a raw bitmask and every perception ray masks it out as one, but the export
  doc calls it "A layer index" — the opposite of what `TalkHelpers` warns. Reword
  (value 4 = editor layer 3, a mask); consider renaming to `..._mask`.
- **C68** `ray_cast.gd:349` — the talk-LOS occlusion ray (the chokepoint wall-gate
  for every look-at interactable) omits the held-prop bit its own comment claims to
  mirror from Pet/Claim. Harmless today (path unreachable while carrying), but the
  comment is wrong. Add the mask for defense-in-depth or fix the comment.

## Theme 11 — new-system polish

- **C49** `ps1_applier.gd:140` — `_ps1ify` only understands `BaseMaterial3D`; any
  ShaderMaterial surface is replaced with flat opaque white. Pre-2026-07-08 this
  was opt-in per scene; the Ps1Warp autoload now applies it under **every**
  LevelRoot with no idempotence guard, so the hazard is global. Skip non-BaseMaterial3D
  (and already-ps1) surfaces.
- **C50** `chess_ai.gd:120` — the anti-determinism tie-window is `0.5` centipawns,
  not the documented half-pawn (50.0), so games against the same NPC replay
  near-identically. Change to 50.0.
- **C51** `chip_installer.gd:129` — a 0-value chip renders a permanently-disabled
  "0 zm" row, contradicting `install_fee`'s "the screen won't offer those" contract.
  Skip `fee <= 0` in the list filter.
- **C52** `chip_chess_visualizer.tres:8` — the only chip without a baked inventory
  icon (falls to heavier live-mesh render). Run the CLI icon baker.

## Theme 12 — miscellaneous confirmed

- **C39** `quest_journal.gd:33` — QuestJournal (J) and ReputationScreen (V) open
  over the start menu / character creation (no no-player bail, unlike Inventory/Stats).
- **C41** `hotbar.gd:134` — the controller d-pad equips weapons / consumes medkits
  while the pet-naming dialog is open (a focused LineEdit doesn't consume joypad
  events).
- **C38** `player.gd:1663` — F5/F9 fire while any *non-pausing* overlay is open
  (loot/inventory/options/name-entry); quickload reloads the scene under them.
- **C46** `options_menu.gd:386` — the music-folder FileDialog callback is a lambda
  capturing a freeable row button (native non-blocking dialog + `_rebuild_tabs`
  frees the button) → the pick is silently lost and the dialog leaks. Bind a
  guarded method instead.
- **C47** `shop_screen.gd:44` — the dialogue-suspend `closed` contract: Shop/
  ChipInstall/Chess guard-path early returns can bail without emitting `closed`,
  which would strand a suspended conversation forever (ChessScreen honors it on
  one path only). Route every refuse path through a single `_refuse_open()` that
  emits `closed`.

---

## Remediation-plan status (correction: the plan now misstates reality)

The 2026-07-01 nine-wave plan is **~85% silently executed** but carries zero
completion markers, so the doc and the standing memory note materially misstate
what's done.

**Verified DONE in code:** H1, H1b, M3, PL1–PL6, H3, M4, M5, M6, M9, M2, M7, M8,
M14, T1, H2 (`npc.gd` 3135→2731), H2b, XC1, M11, M15, B-F40, B-F62, B-F61, B-F7.

**Still open (the ~6-item remainder):**
- ~~**C22/B-F24** — the invisible-unplaced-grid-stack overflow strip (this is P0-3).~~
  **SHIPPED (P0-3b, 2026-07-11):** `GridInventoryView` now renders every unplaced stack in a
  click-only overflow strip below the grid (`_strip_rect`/`_strip_key_at_local`; left-click →
  `activate_requested`, right-click → `drop_requested`), so a coin too big for a full corpse grid
  is takeable and the corpse drains. Paired with `CharacterInventory._rehome_unplaced` (P0-3a) for
  the free-cell case. In-tree click/layout is playtest-gated.
- **C53/M1** — QuestTracker autoload split; the "next `project.godot` edit"
  trigger has fired 3× without riding along; GameState grew 813→991 lines.
- **C57/M13** — only the GroundMovement speed statics shipped; the Landing/footstep
  component was never extracted (mark PARTIAL).
- **C54/B-F19** — half done: ragdoll corpse light still bound via a brittle deep
  NodePath with no null guard; the planned scene drift test is missing.
- **C56/B-F63** — the stray `stupidbody` instance is still in `game.tscn:60`.
- **C58/M5** — three parallel InputManager hand-lists with no consistency drift
  test (this feeds Theme 1).

**Action:** either annotate the plan with per-item DONE markers and fold the
remainder into a short open-backlog note in `CURRENT_ARCHITECTURE.md`, or delete
it and refresh the memory entry. `C55/C59` are doc-prose drift (plan and a test
header misstate counts).

---

## Editor-plugin risks (map-surfaced, not individually bug-verified)

Lower confidence — surfaced by the plugin mapper, worth a look:
- Cross-tab resource aliasing: quest/dialogue/loot/text editors mutate the
  `load()`-cached live resource per keystroke; if any other surface saves that
  `.tres`, unsaved half-edits ride along. `faction_matrix` and `fix_ops` loot-clamp
  save with a bare `ResourceSaver.save` (no `.bak`), unlike the guarded editors.
- `audit_panel._render` only renders severities exactly `ERROR`/`WARN`; an `info`
  or lowercase finding (promised in the plugin QA doc) is silently dropped.
- `fix_ops._apply_player_group` rewrites `.gd` bytes while the file may be dirty in
  the script editor (the known writes-can-revert failure mode).

---

## Refuted (do NOT re-report — verified non-issues)

- Corpse discovery "ignores view cone" — by design, distance-only sensing is
  documented, not a cone.
- Perception sight math triplicated / crouch-range drift — the raw-range use in
  the target-agnostic `can_see_node` is forced, not divergent.
- Three interaction verbs triplicate ~450 lines — duplication real but no defect
  (takedown ray leaves `collide_with_areas` false; TALK_LAYER mask would be redundant).
- Drop-in/GOAP components write host privates — real, but the two "typed host"
  cases resolve at compile time; the Node-typed ones are the documented, accepted
  posture.
- `Merchant.sell` missing the Zorkmids guard — the coin row is value 0.0 and
  disabled; no pump.
- Two pre-M5 inline modal lists "expose stacking" — real drift, but both entry
  paths are guarded upstream (not currently reachable). (Kept as C40/C48 for the
  *cleanup*, downgraded from "exploit.")
- `Settings` overwrites GameSettings tuning — false; `Settings._ready` seeds from
  the authored values before load.
- Group/InputManager literals bypass the registries — true but the registry
  convention explicitly scopes itself to *new* code; pre-existing literals resolve
  correctly, no defect.
- DialogueLine END/CONTINUE sentinels mirrored in plugin — deliberate and
  documented (avoids a `class_name` dep in a `@tool` script).
- M14 speaker-contract "missed new seams," dialogue-suspend "strands conversation,"
  B-F59 "trenchboom gap" — each traced to an existing guard/test; non-issues.

---

## What this means for sequencing

1. **P0-1 and P0-2** are the run/feature-integrity fixes — small diffs, large
   consequence. Do them first.
2. **Theme 1 (one modal registry + drift test)** is the single highest-leverage
   structural fix; it retires ~12 findings and stops the class recurring. Do it
   before adding the next screen.
3. **Themes 2 and 3** are the same "convention-as-N-copies → chokepoint" refactor
   at smaller scale; batch them.
4. **P0-3 / B-F24** (overflow strip) unblocks the tetris grid's worst failure mode.
5. Everything else is genuine backlog, severity-ranked above.

The architecture is not in trouble. The recurring theme is that **conventions
enforced by discipline instead of by a chokepoint + drift test drift the moment a
new feature ships** — and four features shipped in ten days. The fix is to
convert the top two or three conventions into single registries with tests, which
the codebase already does well elsewhere (GOAP dropdowns, catalog reflection,
`gameplay_suppressed`).
