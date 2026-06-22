# Design-gap implementation plan — 2026-06-20 (reviewed)

A dependency-sequenced, phased plan to close the design-depth gaps from the [CYBER SUNDAY design-gap audit](2026-06-20-design-gap-audit.md), re-grounded against live code. Distinct from the now-complete [capability-gap plan](2026-06-19-capability-gap-plan.md) (which closed *designer-authoring reach*); this closes *game-design depth* — the engine is rich but the content and cross-wiring are empty. **41 specs across 8 domains, in 8 phases** (down from 46/9 after the cuts below). Built by a 10-agent grounding workflow (8 domain planners → sequence → staff-engineer review).

Each phase ends with a concrete **milestone a player or designer can reach**. Foundational fixes and cheap cross-wiring land first; the XL "new pillars" are planned but late, and several are honestly marked **don't ship unless a pillar is committed**.

## Staff-engineer review notes (what changed and why)

- **Ordering fix.** CA-2 (the GameRoot mis-wiring) is the hard prereq for the level half: `_place_player_at_entry` early-returns today because `game_root.gd` sits on a `GameRoot` *child* resolving `^"Player"`/`^"Level"` self-relative, so every `LevelDoor`/`PlayerSpawn` is inert. **CA-2 moved to P0** — a ~3-line/editor fix already tracked as USER task #8; nothing downstream that touches level flow is honest until it lands.
- **ML-2 (death=reload)** moved to P0 next to ML-1 so "death reloads last save" is reachable in the same phase saving is introduced.
- **Scope cuts for a solo dev (5):** ML-7 MERGED into GA-2 (same code, two lenses); **EL-5 weapon mods CUT** (clearest scope-creep for a content-empty game); **ML-9a NG+ carry-over CUT** (speculative); **CT-4 cover/flanking DEFERRED out of the numbered phases** (multi-week pillar that can quietly break all combat); **WR-6 trimmed** to its L core.
- **Save model at P0: correct** — rides the already path-parameterized `GameState.save_to_disk(path)`/`load_from_disk(path)`, so manual/quick/slot saves are thin wrappers.
- **FIRST commit: ML-1** (save wrappers + F5/F9) — dependency-free, unit-testable, the immersive-sim core loop. CA-2 is co-equal in P0 but it's a USER/editor scene edit.

## Strategy

The audit's decisive call shapes the sequence: **build the vertical-slice reference level — but not first.** The level is the validation keystone, not the foundation; built before the quick-wins it's an empty stage, built after it gives every cheap win somewhere to prove itself and forces the pacing/save/audio gaps. So: front-load (1) the invisible foundational fixes everything rides on (save model; NPC noise→alert; status-on-hit before chemistry; deep-copy `WeaponData`; the GameRoot fix gating all level flow); then (2) the cheap systemic quick-wins; then (3) the slice that composes them; then (4) at-most-one-or-two XL bets behind a playtest.

Three ordering forces: (1) **foundational fixes before dependents** (GA-2 noise is the stimulus GA-1 alert reacts to; CT-3 precedes chemistry; EL-3 precedes per-instance loot; ML-1 precedes death/NG+; CA-2 precedes the slice); (2) **shared seams land once** (WR-1+WR-3 collide on `DialogueView.set_choices`/`_apply_choice_effects` — one edit, the 6/7/22 lesson; `ShotResolver.scaled_damage` is the single seam PD-1/PD-2/ML-4 pay into); (3) **quick-wins early, big bets late, some not at all.**

## Critical path (foundational, in order)

1. **P0 · ML-1** — manual/quicksave + slots over the path-parameterized save/load. Gates ML-2.
2. **P0 · CA-2** — fix the dead `GameRoot` mis-wiring. Until it lands every `LevelDoor`/`PlayerSpawn` is inert. *(USER/editor.)*
3. **P0 · EL-3** — deep-copy `WeaponData` on acquire + serialize per-instance fields. Hard prereq for EL-4.
4. **P1 · GA-2 → GA-1** — NPC gunfire/death emit `&"noise"` (stimulus) → alert propagation to allies (reaction).
5. **P2 · CT-3** — `WeaponData.on_hit_effect` in the shared `DamageTrace.run_pellet` hit path. Substrate for chemistry.
6. **P3 · PD-1** — read `CharacterStats` in `ShotResolver.scaled_damage`. The keystone damage seam.
7. **P3 · WR-1 + WR-3** — the `set_choices`/`_apply_choice_effects` dialogue read/write cluster, one edit.
8. **P6 · CA-3** — the vertical-slice reference level, after the quick-wins so it composes real systems.

---

## P0 — Foundations: save model + level-flow gate + item instancing
**Goal:** land the invisible fixes the rest rides on. **Effort: M+S+M+L.**
**Milestone:** F5 mid-run, F9 reloads exactly; death-mode set to reload → death reloads last save; a `LevelDoor` swaps levels with the player surviving; two of the same weapon don't share stats across save→reload.

- **ML-1 · Manual save / quicksave + named slots** — `save_to_slot`/`load_from_slot`/`quicksave`/`quickload` over `GameState.save_to_disk(path)`/`load_from_disk(path)` (`managers/GameState.gd:89,147`); F5/F9 ActionSpec; quickload re-applies via `GameState.loaded=true`+`reload_current_scene()` (never mutate a live player). Ship quicksave + 3-slot list first. ***FIRST COMMIT.*** *(deps: none)*
- **CA-2 · Fix the `GameRoot` mis-wiring** — move `game_root.gd` onto `game.tscn`'s real root (or repoint the `^"Player"`/`^"Level"` lookups) so `_place_player_at_entry` stops early-returning. Tracked as USER task #8. *(deps: none; HARD prereq for CA-3; USER/editor)*
- **ML-2 · Death-meaning knob + death card** — a `mode` enum (CHECKPOINT_RESPAWN=today / RELOAD_LAST_SAVE / RELOAD_CHECKPOINT_FRESH) branched in `_on_death_sequence_done`; RELOAD reuses ML-1's load + `reload_current_scene()` (**must reset `Engine.time_scale` + re-run `_reset_screen_post_process`** or respawn-slow-mo-on-black); a death-card Label over the black hold whose text is a **designer-editable `death_message: String` (default "You were killed.")** on the death config `.tres` (NOT hardcoded — tunable like every other string), so it can be changed or themed without code. *(deps: ML-1)*
- **EL-3 · Per-instance Item state** — one `Item.clone_unique()` deep-copying the `weapon` sub-resource, routing all five acquire paths (LootTable.grant, ItemDb.make_weapon_item/restore_item, Merchant._seed_stock, ItemStack.seed_into, refill_to_baseline); capture/restore a per-instance delta. Ship WITHOUT rarity/mods. *(deps: none; hard prereq for EL-4)*

## P1 — Group AI emergence (highest emergence-per-hour)
**Goal:** make a firefight perceivable + connect the cast. **Effort: M+M+S+M.**
**Milestone:** fire near a guard two rooms away → it investigates; shoot one of three allies → the others converge; trip an alarm → faction aggro + a reinforcement wave; an alerted squad searches coordinated sectors.

- **GA-2 · NPC gunfire + death emit the `&"noise"` channel** *(absorbs ML-7)* — `_emit_combat_noise(radius)` spawning a one-shot `NoiseSource` into `get_parent()` (not under self), after `try_fire()` in `_act_alerted` and in `_on_died`; radii via `@export`. Inert until a listener opts in. *(deps: none)*
- **GA-1 · Alert propagation to same-faction allies** — `_alert_allies(point, alerting)` (copy the `_announce_death_to_witnesses` template), `_is_ally_of` filter, routes to the shipped `investigate()`; fire only from first-hand contact, latched once/engagement (reset in `forget()`); relays never re-broadcast; `alert_radius` per-NPC. *(deps: GA-2)*
- **GA-3 · Alarm panel + reinforcement** — drop-in `AlarmPanel` (`spawner_path`+`alarm_faction`+`sound_alarm`) calling `EncounterSpawner.trigger_spawn` + a faction-wide aggro; one-shot guard; **apply `provoke()` rep ONCE.** *(deps: GA-1)*
- **GA-4 · Coordinated group search** — `begin_search` gains optional `sector_phase` (NAN=today's default); GA-1 distributes a shared origin + `TAU*i/n` sectors. *(deps: GA-1)*

## P2 — Combat texture: recoil, mitigation, status-on-hit
**Goal:** weapons get handling, enemies a second defense axis, + the status-on-hit substrate. **Effort: M+M+M (parallel).**
**Milestone:** an SMG climbs/blooms while a sniper kicks hard; a front-armored enemy shrugs flat damage but its core takes 3×; a poison weapon stacks a visible DoT.

- **CT-1 · Per-weapon recoil + firing bloom** — `@export_group "Recoil & Bloom"` on `WeaponData` (0=inert); `AimSway._recoil`/`_bloom` + `add_recoil(weapon)` once per shot from `Player.on_weapon_fired`; fold into `_offset` after scope/gunplay scaling. NPCs never touch AimSway. *(deps: none)*
- **CT-2 · Mitigation: armor/DR + weakpoint mults** — `@export_group "Mitigation"` on `Character` (`armor_flat`, `damage_reduction` 0..0.95) at the top of `take_damage`; `zone_damage_mult` Dict in `DamageTrace.run_pellet`; gate on `hit_pos.is_finite()`, never re-introduce a player head-one-shot. Mirrored onto `NpcData`. *(deps: none)*
- **CT-3 · Status-on-hit** — `@export_group "On-Hit Effect"` on `WeaponData` (0=inert), applied in `DamageTrace.run_pellet` after `DamageApplier.apply`, `hp_before>0` gated; refactor `Player._apply_status_effect` → public `Character.apply_status_effect` so weapons+consumables+NPCs share it. v1 hitscan; roll once per shot. **PREREQ for chemistry.** *(deps: soft — an authored test `.tres`)*

## P3 — Progression + world-reactivity hooks
**Goal:** stats/perks change the verbs; reputation/dialogue read+write state. **Effort: M+M+S+M+S.**
**Milestone:** a gunner build does visibly more DPS; a choice locked behind a perk; a rude line sours a faction + turns the speaker hostile on exit; a door opens only at Town +25 and a friendly vendor charges less.

- **PD-1 · Combat stats in the damage math** — `ShotResolver.scaled_damage` (`shot_resolver.gd:33`, optional-arg idiom) gains optional `stats`; multiply by `weapon_damage_mult()`/fold `headshot_damage_bonus()`. **First combat stat deterministic (NO RNG)** to protect seeded-spread tests. Baseline=1.0. *(deps: none — keystone)*
- **WR-1 · `required_reputation` gate on `DialogueChoice` + `BuildGate`** — `required_faction_id` (dropdown) + `required_reputation` arm, evaluated in `set_choices` on the same `passed` accumulation + `BuildGate.passes`/`deny_reason`. *(deps: none; coordinate with WR-3)*
- **WR-3 · Dialogue reads rep/perk/item/quest + writes rep/aggro** — same two seams: reads folded into the one `passed` bool; writes (`add_reputation`, `aggro_speaker`→`provoke`) in `_apply_choice_effects`. **Land WR-1+WR-3 as ONE edit.** *(deps: WR-1)*
- **WR-2 · Faction discount in Merchant pricing** — `faction_id` + `reputation_discount_curve: Curve` (null=inert) folded into the per-buyer mult in `buy_price`/`sell_price`. *(deps: none)*
- **PD-5 · Opportunity-cost in stat-spend** — `LevelUp.level_up_cost` rises with THAT stat's value (curve `@export`/`XpSettings.tres`); grep `tests/` for pinned flat-cost first. *(deps: PD-1)*

## P4 — (removed: the player menu is real-time BY DESIGN)
The draft proposed a world-freezing pause (CA-7). Per the designer this is **intentionally absent**: the player's
own menus (inventory / stats / reputation / journal) run in REAL TIME — you stay vulnerable while in them (an
immersive-sim choice). The modal NPC-interaction screens (shop / heal / level-up / dialogue) DO freeze the world
via `get_tree().paused` because you're "in" a transaction — that's deliberate and stays as-is. So there is **no
"add a pause" work item**; CA-7 is cut (see Explicitly deferred). The other phases keep their numbers.

## P5 — Pacing/difficulty framework + authored content
**Goal:** the difficulty knob the critique names as the central miss, wired into the now-existing seams; fill the empty consumable/perk/hazard layers. **Effort: M×3+S+content×4.**
**Milestone:** Easy/Normal/Hard visibly changes TTK/density/money; ~6 consumables usable; 8–10 perks across Gunner+Sneak diverge; shoot a red barrel and it chains; stand in fire and take ticks.

- **ML-3 · `DifficultySettings` group + one Options row** — Resource at `GameSettings.difficulty` (mults default 1.0) + `difficulty_level`/`set_difficulty` on `Settings` + one `SettingsCatalog.tres` row. Read LIVE. *(deps: none — foundational for ML-4/5)*
- **ML-4 · Apply difficulty mults** — damage-taken/dealt on PLAYER branches only (`self is Player`), `enemy_count_mult` in `EncounterSpawner`, `loot`/`money` mults in the reward hooks. Grep `tests/` first. *(deps: ML-3)*
- **ML-5 · Difficulty-scaled XP curve** — `xp_gain_mult` at the single `Player.add_xp` inflow (the GRANT, not the total). *(deps: ML-3)*
- **EL-1 · Author ~6 consumable/StatusEffect `.tres`** — stim/medkit/adrenaline/painkiller(HoT)/antidote, in the editor; prefer speed/heal/DoT (`stat_modifiers` not yet consumed). *(deps: partners CT-3)*
- **EL-2 · Recurring money sinks** — ammo into merchant stock + per-clip price; a drop-in `RentCollector` (WorldClock day-tick, OFF by default); move RespecStation/Healer costs to `EconomySettings`; repair gated behind EL-3. *(deps: soft WorldClock/EL-3)*
- **SE-1 · ExplosiveBarrel** — `class_name ExplosiveBarrel extends CanDestroy`; `destroyed`→`_detonate()` spawns `explosion_area.tscn`; chaining already free (Explosion mask hits CanDestroy); `_destroyed` latch. *(deps: none — cheapest spectacle)*
- **SE-2 · HazardZone** — `@tool Area3D` ticking `take_damage` on overlapping bodies + optional status; numbers from a `HazardSettings` group; ship damage-first, `is_instance_valid` guarded, `attributable` so ambient fire blames no one. *(deps: status half soft-needs CT-3)*
- **PD-2 · Rule-changing perk effects** — `combat_bonuses: Dictionary` on `Perk` (crit/damage/pierce/reload) summed in `PerkManager`, read at the `scaled_damage` path (second source). **respec() must reverse them — round-trip test.** *(deps: PD-1)*
- **PD-3 · Authored perk content** — 8–10 `Perk .tres` in `resources/perks/` (editor): stat/combat-rule/ability-granting, a 3-tier `requires_perks` chain, Gunner vs Sneak branches. *(deps: PD-2)*

## P6 — The vertical-slice reference level (validation keystone)
**Goal:** the audit's #1 — ONE level that composes the kit, proving P0–P5 + surfacing pacing/audio in practice. **Effort: L+S×4+S (mostly EDITOR authoring).**
**Milestone:** locked door → fight a guarded container for a keycard → `cleared`/flag opens a shortcut → a `ShadowVolume` alt stealth route → a `LevelDoor` to area 2; you find a traversal ability you didn't start with; tutorial prompts teach the verbs.

- **CA-6 · Extract a real `LevelData.tres`** into `resources/levels/` (untrap from game.tscn's inline SubResource), re-point `GameRoot.level`. *(deps: CA-3; editor)*
- **CA-5 · Blank `LevelTemplate.tscn` clone-source** — load-bearing groups pre-wired + an optional `@tool` validator. *(deps: CA-2)*
- **CA-3 · Author the slice** — PURE EDITOR: PlayerSpawn → Door+Lock(keycard) → ItemContainer + EncounterSpawner wave via TriggerVolume → `cleared`→shortcut Door via `unlock_flag` → ShadowVolume alt route → LevelDoor to slice_02. *(deps: CA-2, CA-6)*
- **CA-8 · Traversal abilities as found `UpgradePickup`s** — trim `Player.starting_unlocks`, place pickups behind verticality. *(deps: CA-3; editor)*
- **CA-9 · Tutorialization** — `TutorialPrompt` (TriggerVolume subclass, `seen_flag`, live key labels) + a Controls card in the **OptionsMenu** (there's no pause menu — see P4) from `ActionCatalog.keybind_specs()`. *(deps: CA-3)*
- **SE-4 · Emergent hazard verbs** — lure (Throwable `noise_on_land` near a hazard), push (knockback/throw into a HazardZone — already works), sabotage (shoot a barrel — SE-1 is the verb). DEFER NPC hazard-avoidance. *(deps: SE-1+SE-2)*

## P7 — First big bets (gated behind a playtest)
**Goal:** the first L/XL bets after P1–P6 prove out. **Build at most one.** **Effort: M+XL.**
**Milestone:** a firefight shifts music to combat with a "you've been seen" stinger; (if taken) a costed slow-mo spends a regenerating Focus pool.

- **ML-8 · Audio/music states** — `DetectionStinger` polling the `MusicDirector` group, one-shot on the →ALERTED edge for an NPC targeting the PLAYER (latch+cooldown); optional INVESTIGATING caution bed. *(deps: GA-2)*
- **PD-4 · Active, costed abilities (BIG BET — scope to pool+base+ONE ability)** — `FocusPool` (regenerating, persisted), `ActiveAbility extends Ability` (cost/cooldown/`activate()` + an "Ability" action), first `ManualSlow` **sharing BulletTime's single time_scale owner/latch.** Cloak/hack are follow-ons. *(deps: ML-1)*

## P8 — Deferrable big bets (build only if a pillar is committed)
**Goal:** the loot/world XLs the critique calls OMITTABLE. **Pick AT MOST one, after the slice proves the loop.** **Effort: L×3 — most should NOT ship.**

- **WR-6 · Quest fail/expire (L core)** — `GameState.fail_quest` (persisted `[quests_failed]`), `expire_on_flag` on `Quest`, a `FAILED` dialogue state. NPC "memory" = flags. *(deps: WR-3)*
- **WR-5 · Rep-gated merchant stock** — `StockEntry.required_reputation` skipped in `_seed_stock` + `refill()`. *(deps: WR-1)*
- **EL-4 · Loot rarity (BIG BET — OMITTABLE)** — `rarity` enum + tier→tint/value/variance rolled in the seeded LootTable on the now-unique WeaponData; **must persist via EL-3's per-instance delta.** Hold at tint+variance+value. *(deps: EL-3 HARD; critique says omit for a content-empty game)*

---

## Risks
- **GA-1 alert storm / O(n²)** — relays never re-broadcast; latch once/engagement (reset in `forget()`); fire only on first-hand ALERTED.
- **GA-3 reputation multiplication** — `provoke()` applies rep per call; apply ONCE; one-shot `_triggered` or infinite waves.
- **Status-on-hit chain** — any chemistry HARD-deps CT-3; don't build chemistry until CT-3 ships.
- **EL-3 silent-aliasing trap** — one missed acquire path re-shares `WeaponData`; round-trip-test the save. EL-4 is cosmetic-and-reset without it.
- **The dialogue `set_choices` seam (WR-1+WR-3)** — one coordinated edit or you break the fail-branch/companion paths + `test_dialogue.gd` (the 6/7/22 lesson).
- **Shared damage-seam determinism (PD-1/PD-2/ML-4)** — hottest path, per-pellet for every wielder incl. NPC-vs-NPC; baseline args MUST be a pure 1.0 no-op; first combat stat deterministic; gate damage mults on `self is Player`; grep `tests/` before each migration.
- **New `class_name`s cascade GUT** (`DifficultySettings`, `FocusPool`/`ActiveAbility`) — rescan `global_script_class_cache` before the suite; use the absolute `--path`; never `--import` with the editor open.
- **Hand-authored `.tres`/`.gd.uid` malformed** (EL-1, PD-3, CA-3/5/6, ML-3) — create in the EDITOR for valid uids.
- **ML-2 death-reload time_scale dirt** — reset `Engine.time_scale` + re-run `_reset_screen_post_process` or respawn slow-mo on black.
- **CA-2 + game.tscn/project.godot edits collide with active authoring** — flag every one a USER/editor step (task #8); never sweep the file.
- **Off-tree world reads fail GUT** (SE-2 tick) — world-guard, unit-test the pure accumulator via injected seams.

## Explicitly deferred (and CUT)
- **Real world-freezing pause (CA-7) — CUT (design pillar).** The player's menus do NOT pause by design — real-time vulnerability is intentional. The transaction screens (shop / heal / level-up / dialogue) pause via `get_tree().paused` *because* they're NPC interactions, and that stays. Not a gap; do not re-propose.
- **Weapon mods (EL-5) — CUT.** Multi-week stat-reroute; EL-1/EL-2 give the money-sink cheaper. Revisit only if a build-space pillar is committed.
- **NG+ carry-over machine (ML-9a) — CUT.** Ship only one authored permanent early-choice flag folded into content.
- **Full cover/flanking (CT-4) — DEFERRED out of numbered phases.** Decomposing `_act_alerted` can break all combat; at most one playtest-gated bet behind a profile opt-in.
- **Element chemistry beyond ONE reaction** — one wet/burning pair, one rule (wet cancels burning), folded into `StatusEffectManager.apply_effect`, not a new class. HARD-deps CT-3.
- **Loot rarity (EL-4)** — P8 big bet behind EL-3 + a proven loop.
- **NPC hazard-avoidance, Cloak/Hack abilities, projectile-parity for status/zone, `stat_modifiers` consumables, WorldClock quest-expiry + per-NPC memory store, the polished slot-save screen, encounter-budget authoring (ML-6, overlaps ML-4)** — all deferred tails.
