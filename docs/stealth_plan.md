# Historical Stealth System Improvement Plan

> **Historical plan.** This document captures the planning state before several stealth slices landed. Do not treat
> its "currently missing" claims as authoritative without checking code. Current code now includes GOAP as the sole
> NPC brain, no-target GOAP ticking, `NoiseSource`, thrown decoy noise, combat/death noise bursts, `Corpse` markers,
> body-discovery hooks, suspicion tiers, and search settings. Use `docs/AUTHORING_GUIDE.md` and
> `scripts/npc/goap/README.md` for current behavior; keep this file as reasoning/provenance for future stealth work.

## Intro

The game already ships a competent three-tier stealth foundation: an enemy **Perception** sense/awareness state machine, a player **NoiseEmitter**, and a **GOAP** brain mid-migration alongside the legacy FSM. This plan **extends** that foundation — it does not rebuild it. Every item below was checked against the actual source; where the draft roadmap over-claimed ("reuses X wholesale, zero new action"), the code disagrees, and those items are re-scoped here with the real prerequisite called out.

The single most important correction: **noise cannot currently initiate awareness.** `Perception.sense()` is the only caller of `can_hear()`, and `npc.gd._physics_process` early-returns into idle *before* `sense()` runs whenever there is no acquired enemy target (`npc.gd:1399`). Target acquisition (`npc_targeting.gd`) is purely position + `_treats_as_enemy` based and ignores noise entirely. So a patrolling/neutral guard literally cannot hear a thrown decoy today. That gate (**Slice 0**) is the gating dependency for the whole distraction/consequence cluster and is sequenced before it.

We lead with the lowest-risk, highest-value slice (the detection meter) and split it so the pure data backbone lands first.

---

## What already exists (build on this, do not replace)

**Perception** (`scenes/enemies/perception.gd`, `class_name Perception`, a `Node3D` child of the NPC):
- A `detection` float (0..1) awareness meter that fills/drains every tick, and a 4-state machine `UNAWARE / DETECTING / ALERTED / INVESTIGATING` (`perception.gd:52-53`, `sense()` at `62-111`).
- `can_see()` = range + horizontal FOV cone + a **single** `eye_height` LOS ray (`136-158`); `_effective_sight_range()` already duck-type-reads the target's `crouch.crouch_t` and lerps to `crouch_sight_mult` (`163-175`).
- `can_hear()` = duck-typed read of `target.noise_radius`, distance-only, **ignores cone and walls** (`179-187`).
- `last_known_position`, `alert_to(pos)` (force-ALERTED seam, `125-133`), `refresh_investigation()` (holds the give-up clock while traveling, `118-120`), `just_spotted` / `just_alerted` signals.
- Tunables are `@export` (sight_range, fov_degrees, eye_height, crouch_sight_mult, time_to_detect, forget_time, hearing).

**Noise** (`scripts/player/noise_emitter.gd`, `class_name NoiseEmitter`): writes `host.noise_radius` each frame = `max(decaying gunfire spike, ground_speed * noise_move_per_speed * (1 - crouch.crouch_t))`; airborne is silent (`tick()` at `23-29`). The `noise_*` tunables and `noise_radius` live on `player.gd:155-163`. `gunfire()` is poked from `Player.on_weapon_fired`. Crouch (`scripts/player/crouch.gd`) lerps `crouch_t` driven by `GameSettings.player_crouch`.

**GOAP** (`scripts/npc/goap/`, the sole NPC brain since the Phase-4 FSM cutover): `GoapExecutor._build_world_state(host)` snapshots `Perception.state` into 3 bool facts `state_detecting/alerted/investigating` + `threat_noticed` (`goap_executor.gd:73-92`). Goals are `GoapGoal` (data: `desired_state` dict + `base_priority`); the planner is A* with an **integer `unmet_count` heuristic** (`goap_goal.gd:25-30`, `goap_planner.gd:24,45`) and `key()` dedup. Actions subclass `GoapAction` and re-check live perception in `is_runtime_valid`. Per-archetype authoring is `GoapProfile.tres`. `GoapActionInvestigate` walks to the last-known spot then sweeps (the search behaviour Slice 8 extends).

**Combat / feedback seams:**
- `StealthStatus.of_player(player, npcs) -> Level` is pure, returns only `HIDDEN/DETECTED/DANGER`, early-returns on ALERTED (`stealth_status.gd:12-22`); `PlayerHud.set_stealth_level(level, sneaking)` draws a crouch-gated top-centre label (`player_hud.gd:99-119`); driven from `player.gd:1166-1168`.
- Sneak bonus is **state-based, not positional**: `DamageApplier.off_guard_for(collider)` → `Character.is_off_guard()` (state != ALERTED, `npc.gd:865`) → `ShotResolver.scaled_damage(base, crit_mult, sneak_mult, was_crit, off_guard)` (`shot_resolver.gd:32-35`). Neither `off_guard_for` nor `scaled_damage` has any access to attacker direction or victim facing.
- Death witnesses: `npc.gd:_on_died` → `NpcVoice._announce_death_to_witnesses` (radius-only, **no LOS**, `npc_voice.gd:150-157`) → `witness._witness_death` (bark only). Gated on `_hit_by_player`.
- Corpses are spawned **two ways**: a ragdoll-attached `LootableCorpse` via GoreSpawner, OR a free-standing one via `_drop_loot()` (only when `ragdoll_scene == null` AND there is loot/money, `npc.gd:827-844`). Neither is in a discoverable group — there is **no reliable corpse marker** today.
- `AimIndicators.report(source, world_pos, charge, …)` (`scripts/ui/aim_indicators.gd`) is an existing **directional-arc** overlay that projects world positions to crosshair-relative arcs — directly reusable for a "who/where is detecting me" cue.
- `Throwable` (`scripts/components/Throwable.gd`, `class_name`, rich `@export`s + `ThrowableData`) already has `on_impact(speed)` and `mark_thrown_by(by)` — it credits a thrower and aggros on hit. A thrown prop that MISSES still calls `on_impact()`.

**Designer-first idiom:** `GameSettings` autoload `preload()`s `resources/tuning/*.tres` (`managers/GameSettings.gd:96-110`). Keybinds register in `managers/InputManager.gd` + `project.godot [input]` + a `Keybind` `SettingSpec` row in `resources/settings/SettingsCatalog.tres` (the data-driven Options menu, which already lists Crouch/Throw/Light/NightVision). Player-facing tunables persist via the `Settings` autoload (add a typed `var`+setter there, then one catalog row).

### Two foundation defects this plan must fix in-pass
1. **`_build_perception()` copies a fixed field list** (`npc.gd:969-978`: sight_range, fov_degrees, time_to_detect, forget_time, eye_height, hearing). `crouch_sight_mult` is **not** copied and has **no NPC mirror @export** — so it is silently un-tunable per-NPC today. *Any* new Perception `@export` is therefore NOT designer-reachable unless wired the same way. See Slice 0b.
2. **Noise cannot initiate awareness** (see Intro). See Slice 0a.

---

## Enhancement roadmap (prioritized)

### Slice 0a — Foundational fix: noise can initiate awareness *(prerequisite, not optional)*

- **What:** Add an idle-time hearing pass so an NPC with **no acquired enemy target** can still react to noise. In `npc.gd`'s no-target branch (`1399-1409`), before `_idle`, call a lightweight `_perception.hear_only()` (a new method that scans world noise sources — see Slice 4 — and, on a heard source above threshold, sets `last_known_position` to the source point and forces `state = INVESTIGATING`). Decouple "investigate a noise point" from "have an enemy target."
- **Why:** Verified blocker. `sense()` is target-gated; `_perception.target` is bound only via `_set_target` (`npc.gd:1859-1866`), which only the targeting path calls; `can_hear()` returns false on its `is_instance_valid(target)` guard with no target. Without this, the distraction system (Slice 4) and any "alert on gunfire across the level" behaviour are **no-ops for their primary use case** (a guard who hasn't already spotted you).
- **Designer-first surface:** `@export hearing_initiates: bool` on Perception (default reproduces today: false until opted in) + the same hearing thresholds Slice 4 introduces. Neutral NPCs gated by a `can_be_distracted`/hostility-agnostic flag so a townsperson can be lured without treating the player as an enemy.
- **GOAP:** Once `hear_only()` flips `state` to INVESTIGATING, `_build_world_state` reads `_perception.state` → `state_investigating`/`threat_noticed` flip → the existing Investigate goal runs. **But** the executor only ticks with a valid `_target` (the seam sits past the no-target early-return), so idle-time hearing must ALSO drive a minimal investigate from the no-target branch — `_react_unaware` does this (it scans the noise channel and walks/searches toward the loudest source without any target).
- **Effort:** M · **Risk:** Medium — touches the perception/targeting gate, the most load-bearing seam. Keep behaviour-preserving by default (`hearing_initiates=false`).
- **Depends on:** none (but Slice 4's noise-source scan lands here).

### Slice 0b — Foundational fix: make new Perception tunables designer-reachable

- **What:** Either (a) refactor `_build_perception()` to copy **all** matching fields generically, or (b) for each new per-archetype Perception tunable do the 4-point wiring: Perception `@export` + `npc.gd` mirror `@export` + `_build_perception` copy + `_apply_profile` (`npc.gd:399-404`) + `NpcData` field. Fix the existing `crouch_sight_mult` leak in the same pass. For **global** knobs (range/peripheral curves, light multipliers, hearing attenuation), prefer a `*Settings.tres` on `GameSettings` read directly inside Perception — no per-NPC mirror chain.
- **Why:** The draft's "new @export on Perception = full designer control" is false given the copy-list construction path; `crouch_sight_mult` proves the leak. Required for Slices 2/3/7 to be inspector-tunable as claimed (CLAUDE.md no-hardcoded-const rule).
- **Effort:** S · **Risk:** Low.
- **Depends on:** none.

### 1. Detection meter as a graded fact + per-NPC suspicion feedback *(FIRST shippable value)*

- **What:** Surface the already-computed `Perception.detection` (0..1) and a derived suspicion tier (`CALM/WARY/SUSPICIOUS/ALERTED`) to both the player HUD and the planner, replacing the current 3 binary states for feedback purposes. Add `Perception.suspicion()` from state + detection with two inspector thresholds. Change `StealthStatus.of_player` to return a small **Dictionary/struct** `{level, meter, spotter}` (not a mutated enum). HUD draws a small fill-bar/eye that rises with the worst meter.
- **Why:** Highest-value, lowest-risk slice — the meter already fills every frame but is invisible to the player (only categorical) and the planner (only 3 bools). It is the data backbone every later feature reads. Zero perception-logic change.
- **Designer-first surface:** `StealthHudSettings.tres` (bar size/colors, tier thresholds, `show_per_npc_pips`, `max_pip_distance`) on `GameSettings`. An OptionsMenu "Interface/Accessibility" toggle "Show detection meter" persisted via `Settings`. `@export suspicion_wary_threshold / suspicion_suspicious_threshold` on Perception (use the Slice 0b path so they are reachable). **Directional cue:** reuse the existing `AimIndicators.report(...)` arc overlay for "who/where is detecting me" instead of a brand-new pip system — nearly free, already projects world→screen.
- **GOAP:** `_build_world_state` sets `&"detection"` (float) and `&"suspicion_tier"` (int) as **read-only priority facts only**. **Hard invariant (document next to the SENTINEL-FACTS note at `goap_executor.gd:69`):** these must NEVER appear in a goal `desired_state` — the A* heuristic is integer `unmet_count` with `key()` dedup (`goap_goal.gd:25`, `goap_planner.gd:24,45`); a continuous float in `desired_state` would explode the search and break admissibility. The HUD reads the meter directly, independent of the planner.
- **Effort:** S · **Risk:** Low — main risk is HUD clutter (mitigated by the toggle + crouch-gating like the existing label). Update the pure `StealthStatus` unit test in the same commit as the signature change; update the `player.gd:1168` caller.
- **Depends on:** Slice 0b (for the threshold exports).

### 2. Distance + angle detection falloff

- **What:** Make `can_see()` scale how fast the meter fills by distance-into-range and angle-off-centre instead of a hard binary inside the cone. Add `Perception.visibility_factor(dist, angle) -> 0..1` from two falloff curves; the DETECTING fill rate (`perception.gd:79-80`) multiplies by it. Centre/close fills fast; edge/far fills slowly.
- **Why:** Fixes the foundation's biggest realism gap (40 m == 2 m; sharp 110° cutoff). Pure multiplier on existing meter math; composes with Slice 1's exposed meter.
- **Designer-first surface:** `@export peripheral_falloff: Curve` + `range_falloff: Curve` (or near/far + min/max-angle pairs), grouped under "Sight". Defaults = 1.0 everywhere → reproduces today exactly. **Reachability via Slice 0b** (global curves on a `SightSettings.tres` is the cheapest correct path).
- **GOAP:** No new fact/goal/action — it changes how fast `&"detection"` rises, consumed via Slice 1. Lives inside Perception, below the planner → it's consumed automatically.
- **Effort:** S · **Risk:** Low — clamp a floor so a valid sighting still reaches 1.0 eventually.
- **Depends on:** Slice 1, Slice 0b.

### 3. Light & shadow visibility modifier

- **What:** A drop-in `PlayerLightLevel` (Node3D) writes `player.light_exposure` (0..1); Perception folds it into `visibility_factor` (dark → slower fill / shorter effective range), duck-typed exactly like the existing `crouch_t` / `noise_radius` reads (`perception.gd:166-187`). Default sampling = designer-painted `ShadowVolume` Area3Ds (cheap overlap test), not live light probing.
- **Why:** Most-requested missing pillar (enemies "see through darkness"). Reuses the exact duck-typed neutral-fallback pattern (absent component → behaves as today). Pairs with the existing NightVision/Light keybind as the player's counter-tool.
- **Designer-first surface:** `class_name PlayerLightLevel` + `class_name ShadowVolume` (Area3D) drop-ins; `LightStealthSettings.tres` for global dark/lit multipliers + min-visible floor; `@export light_sensitivity` on Perception (Slice 0b path).
- **GOAP:** Feeds the same `&"detection"` fact via the falloff multiplier — no planner change. Optional `&"target_in_shadow"` bool for a future "flush them out" action (not required v1). Automatic — no planner change.
- **Effort:** M · **Risk:** Medium — light sampling can be perf-heavy; default to ShadowVolume overlap to keep it cheap.
- **Depends on:** Slice 2.

### 3b. Slow-walk movement tier *(added — low-cost pillar the draft missed)*

- **What:** A walk/sneak-walk speed tier between crouch and run. Noise already scales with `ground_speed` (`noise_emitter.gd:28`), so a slow-walk is essentially one more multiplier (or a held modifier that caps ground speed), giving a "quiet but mobile" option that crouch (slow) and run (loud) don't.
- **Why:** Pairs with the graded meter (Slice 1) far more cheaply than light sampling — the draft adds light but never touches movement-state nuance the foundation already hints at.
- **Designer-first surface:** `@export walk_speed_mult` / `walk_noise_mult` on the movement/noise components or a tuning `.tres`; optional "Walk" hold keybind via the InputManager/OptionsMenu idiom (or reuse a speed modifier).
- **GOAP:** None — it only changes `noise_radius`, consumed by existing hearing.
- **Effort:** S · **Risk:** Low.
- **Depends on:** Slice 1 (so the player can see the payoff).

### 4. Thrown distraction / noise lure

- **What:** Let the player throw an object that emits a decaying audible radius **at its landing point**, drawing NPCs to investigate there. Add `class_name NoiseSource` (Node3D): `@export radius, decay, lifetime, one_shot`. Generalize hearing so `can_hear()`/the new `hear_only()` consider the loudest nearby `NoiseSource`, writing `last_known_position` to **its** world position (not the player's). **Cheapest MVP:** a thrown `Throwable` already calls `on_impact(speed)` even on a miss (`Throwable.gd:282`) and credits a thrower — wire a `NoiseSource` (or `ThrowableData.noise_on_land`) off that impact, so "lob a crate to lure" needs no new throw verb.
- **Why:** The classic missing active tool and top expansion pick. The "investigate a point" half (last_known_position + INVESTIGATING + search) already exists.
- **Re-scoped from the draft:** this is **NOT** "zero new action." It requires Slice 0a (noise must initiate awareness) plus the multi-source scan. Without Slice 0a it only works on an NPC already in combat with you — the least useful case. Neutral NPCs additionally need the hostility-agnostic distractibility flag from Slice 0a, since `_acquire_target` only ever returns a `_treats_as_enemy` node.
- **Designer-first surface:** `NoiseSource` drop-in (also placeable as ambient lures — a beeping machine); `Throwable`/`ThrowableData` gains an optional noise-on-land; `DistractionSettings.tres` for default decoy radius/decay. Reuses the Throw keybind.
- **GOAP:** Once `hear_only()`/`sense()` flips `state` to INVESTIGATING at the decoy point, the existing Investigate goal/action walks the NPC there. Optional `&"heard_decoy"` lets a wary archetype prioritize Investigate harder. Reuses the no-target investigate from Slice 0a.
- **Open implementation choice:** multi-source lookup = a `&"noise"` SceneTree group (O(NPCs×sources), fights the throttled-retarget design) **or** a small `NoiseRegistry` autoload (cheaper per-NPC, adds global state). Recommend the autoload, frame-throttled. (See Open Questions.)
- **Effort:** M (the headline behaviour) + the Slice 0a structural fix · **Risk:** Medium.
- **Depends on:** Slice 0a.

### 5. Body discovery + alert propagation

- **What:** A dead NPC leaves a **dedicated** `class_name Corpse` (Area3D, its own `&"corpse"` group) spawned **unconditionally on every death** — independent of loot/ragdoll. A living NPC that **sees** a corpse (LOS check, not the radius-only witness loop) escalates via `_perception.alert_to(corpse_pos)` and barks "There's a body!". Per-corpse already-discovered cooldown to avoid re-alert spam.
- **Why:** Closes the loop: today a stealth kill has no follow-on cost unless a witness is within 18 m at the instant of death and `_hit_by_player` (`npc_voice.gd:150-157`). Makes patrol routes and corpse-hiding matter; reuses INVESTIGATING + `alert_to` wholesale.
- **Re-scoped from the draft:** the existing `LootableCorpse` is **not** a reliable marker — it's built two ways and skipped entirely for an empty-bagged NPC with no ragdoll (`npc.gd:827-844`). So Slice 5 needs a **new** dedicated marker, not reuse of LootableCorpse.
- **Designer-first surface:** `class_name Corpse` drop-in + a `CorpseDiscovery` component (`@export discovery_range, requires_los, escalate_to`); `BodyDiscoverySettings.tres` (radius/cooldown). Optional "CheckBody" bark lines added to the existing `BarkSet` (precedent: `death_question`).
- **GOAP:** `_build_world_state` sets `&"corpse_in_view"` (LOS-checked nearest corpse) + its position fact; new `GoapActionCheckBody` (precond `corpse_in_view`, effect `body_checked`) walks there and calls `_perception.alert_to(corpse_pos)`; new `GoapGoal('CheckBody')` between Investigate and Idle, barking via `NpcVoice` on discovery (as the existing no-target `_discover_corpse` path already does).
- **Consequence-pipeline rule (resolves the #4↔#6 double-fire):** define ONE pipeline. A **silent** takedown (Slice 6) must **suppress** the legacy radius-bark `_announce_death_to_witnesses` (it was supposed to be silent) and let body-discovery be the delayed cost. Otherwise a "silent" takedown loudly alerts 18 m of witnesses, defeating its purpose.
- **Effort:** M · **Risk:** Medium — corpse lifetime/cleanup + per-corpse discovered-cooldown; must not regress the existing instant-witness barks.
- **Depends on:** Slice 6 (for the suppression rule + the body to discover).

### 6. Silent takedown + positional backstab

- **What:** Two parts. (a) **Backstab math** (ship first, fully unit-testable): a behind-arc multiplier. (b) **Takedown action**: hold a dedicated key behind an UNAWARE/DETECTING enemy for a quiet/instant kill.
- **Why:** The foundation has the sneak **damage** multiplier but no takedown **mechanic** and no positional component (sneak is angle-agnostic flat ×). Converts "undetected" from a passive buff into an active verb and makes positioning matter.
- **Synergy (called out per the critique):** `is_off_guard()` is true for UNAWARE/DETECTING/INVESTIGATING (`npc.gd:865`), so an NPC lured by a decoy (Slice 4) is already off-guard and eligible — a strong emergent combo. A thrown prop that *hits* an off-guard NPC already gets the bonus, making "lure-then-strike" work without new code.
- **Required signature change (verified):** `ShotResolver.scaled_damage` and `DamageApplier.off_guard_for(collider)` have **no** access to attacker direction or victim facing. Add a `behind: bool` computed in `DamageApplier` from `attacker.global_position` vs `(collider as Character)` facing, threaded into `scaled_damage` as a third multiplier flag beside crit/sneak. Pure static math, unit-testable.
- **Designer-first surface:** `class_name SilentTakedown` (Node on player): `@export hold_time, max_range, behind_arc_degrees, noise_radius_on_kill, require_crouch`. `@export backstab_multiplier + backstab_arc_degrees` on `WeaponData` (beside `sneak_attack_multiplier`/`headshot_multiplier`). **Input — dedicated "Takedown" action** registered in `InputManager.gd` + `project.godot [input]` + a `Keybind` row in `resources/settings/SettingsCatalog.tres` (same as Throw/Light/NightVision), persisted via Settings.
- **Input-disambiguation (verified conflict):** the takedown context ("crouched behind an UNAWARE/DETECTING enemy") is a **strict subset** of the pickpocket context: `Talkable._can_pickpocket` requires `player.is_crouching()` AND `npc.is_off_guard()` (`talkable.gd:147-155`) and `start_talk` routes Interact straight to `LootScreen.pickpocket` (`118-124`). **Do not overload Interact** — use the dedicated key. If overload is ever required, define explicit precedence (behind-arc + hold = takedown; front/tap = pickpocket) and make `Talkable.can_pickpocket` / `look_name_for` arc-aware so the look-at prompt and the action always agree (the file insists on this at `talkable.gd:69-70`).
- **GOAP:** NPC side is reactive — it dies via the existing damage path; `off_guard` already read in `DamageApplier`. No GOAP branch for the math. The takedown feeds Slice 5 (leaves a body) and must trip the suppression rule there.
- **Effort:** M (backstab math = S, shippable first) · **Risk:** Medium — needs an animation/feedback beat; gate so you can't takedown an ALERTED foe.
- **Depends on:** Slice 1.

### 7. Sound occlusion for hearing

- **What:** Walls dampen sound: when `can_hear()`/the NoiseSource scan considers a noise, attenuate effective radius by occluders between source and listener — a few rays, each solid hit subtracting `@export wall_attenuation`.
- **Why:** Hearing currently travels through walls identically to open air. Makes interiors tactical; natural partner to the distraction system (a decoy through a doorway carries; one behind a thick wall doesn't).
- **Designer-first surface:** `@export occlusion_enabled (default false → behaviour-preserving), wall_attenuation, max_occlusion_rays` on Perception (Hearing group, Slice 0b path); a `HearingSettings.tres` could globalize later.
- **GOAP:** Only changes whether `can_hear()` returns true and where `last_known_position` lands — the planner consumes it already. No new fact/goal/action; lives inside Perception.
- **Effort:** M · **Risk:** Medium — throttle (every N frames), cap ray count, short-circuit when source is in range with clear LOS.
- **Depends on:** Slice 4.

### 8. Search nuance: uncertainty radius, breadcrumbs, intensity falloff *(capstone, last)*

- **What:** Make investigation feel like searching: grow an uncertainty radius around `last_known_position` over time, sweep a few sample points within it (instead of the single hardcoded `* 4.0` sine/cos at `npc.gd:1487-1488`), keep a short breadcrumb trail, and ramp intensity DOWN over `forget_time` (frantic look first, then a giving-up wander).
- **Why:** The current search is a near-degenerate fixed-point stare. This is the payoff that makes everything upstream (distraction, body discovery, light) read well, and is best done once the meter, facts, noise points, and corpses all exist to be hunted around.
- **Designer-first surface:** `@export uncertainty_grow_rate, max_search_radius, sample_points, intensity_curve` on a new `GoapActionSearch` / Perception (`search_sweep_rate` is the precedent export); `SearchSettings.tres`. All inspector-authored.
- **GOAP-only (the FSM was removed at Phase 4):** author this as `GoapActionSearch` (precond `state_investigating`, effect `spot_searched`, expose `&"search_progress"` 0..1), replacing the move+sweep currently inlined in `GoapActionInvestigate`. No FSM mirror — the planner is the only path. Keep `refresh_investigation`'s travel-vs-search decoupling intact.
- **Effort:** L · **Risk:** Medium — touches the most-tuned behaviour; keep `refresh_investigation`'s travel-vs-search decoupling intact.
- **Depends on:** Slice 5.

---

## Phasing (independently shippable; first slice first)

**SHIP-1 — data backbone, zero perception-logic risk (split into 2 commits):**
- *Commit 1 (pure, off-tree testable):* `Perception.suspicion()` + two threshold exports (Slice 0b for reachability); change `StealthStatus.of_player` to return `{level, meter, spotter}`; update its pure unit test + the `player.gd:1168` caller in the same commit.
- *Commit 2 (player-facing):* drive a detection fill-bar/eye in `PlayerHud` off the meter (reuse the crouch-gated visibility pattern in `set_stealth_level`), behind an OptionsMenu toggle persisted via Settings. Reuse `AimIndicators` for the directional "who/where" cue. Defer per-NPC pips.
- This is Slice 1 (+ 0b). Touches no perception/targeting logic, no GOAP edits, and surfaces the `StealthStatus` signature change early while it's cheap.

**SHIP-2 — sensory depth, all inside Perception, below the planner:** Slice 2 (distance/angle falloff), then Slice 3 (light/shadow) and the cheap Slice 3b (slow-walk). All default to behaviour-preserving values; unit-test `visibility_factor(dist, angle, light)` as a pure function. Needs Slice 0b done.

**SHIP-3 — the structural prerequisite, then the lure:** **Slice 0a first** (noise initiates awareness — the real gating dependency the draft omitted), then Slice 4 (thrown distraction), with the `Throwable.on_impact` path as the MVP. Decide the NoiseRegistry-vs-group lookup here.

**SHIP-4 — player verbs, combat-math first:** Slice 6 — ship the positional **backstab multiplier first** (pure `ShotResolver`/`DamageApplier` math + the `behind` signature change, fully unit-testable), then layer the takedown action + dedicated keybind + feedback.

**SHIP-5 — consequence + occlusion:** Slice 5 (body discovery — new dedicated `Corpse` marker, `GoapActionCheckBody`, the suppression rule binding it to Slice 6), then Slice 7 (sound occlusion, makes Slice 4 tactical).

**SHIP-6 — capstone:** Slice 8 (search nuance), authored as a GOAP action — no FSM mirror (the FSM is gone).

**CROSS-CUTTING RULE:** the GOAP planner is the only NPC brain (the FSM was removed at Phase 4), so every *behaviour* slice (0a, 4, 5, 8) lands as a GOAP action/goal only — **do not** add or mirror an `_fsm_tick` branch (there isn't one). *Sensory* slices (2, 3, 7) live inside Perception and feed the planner's world-state for free. All new tunables = `@export` (via the Slice 0b reachability path) or a `*Settings.tres` on `GameSettings`; the Takedown keybind + the HUD toggle wire into InputManager/project.godot/OptionsMenu+Settings per CLAUDE.md.

---

## Risks & non-goals

**Risks:**
- **Dual-path tax is gone (Phase 4 removed the FSM).** Each behaviour slice (0a/4/5/8) now adds a single GOAP fact/goal/action — no mirrored `_fsm_tick` branch. The earlier ~2× authoring tax and the per-slice A/B against the FSM no longer apply.
- **GOAP planner invariant.** `detection`/`suspicion_tier` (and any future continuous fact) must stay read-only priority facts — never a goal `desired_state` (the heuristic is integer `unmet_count` with `key()` dedup). Document this at `goap_executor.gd:69`.
- **Perception construction leak.** New Perception `@export`s are invisible to the inspector through the NPC until Slice 0b is done; `crouch_sight_mult` is the standing proof. Do 0b before 2/3/7.
- **Perf.** Light probing (Slice 3), multi-source hearing (Slice 4), and occlusion rays (Slice 7) all add per-NPC/per-frame cost. Mitigate with designer-painted `ShadowVolume` overlaps, a frame-throttled `NoiseRegistry`, and capped/short-circuited occlusion rays respectively.
- **Consequence double-fire.** A takedown kill currently trips the radius-only witness bark (`_hit_by_player` → `_announce_death_to_witnesses`). If Slice 5 also escalates on the same kill you double-react; the suppression rule (silent takedown suppresses the instant bark, body-discovery is the delayed cost) must land with Slice 5.

**Non-goals (this plan deliberately does NOT do):**
- Rebuild Perception, NoiseEmitter, or the GOAP planner — every slice extends existing seams.
- Reopen the GOAP cutover — Phases 3/4 are done (the FSM is removed; the planner is the only brain). Stealth slices bolt onto the planner, not onto the migration.
- Vertical/elevation stealth (crouching never hides you on height by design — `perception.gd:147-148`), and full per-surface acoustic materials — out of scope; `wall_attenuation` is a single flat knob for now.
- Companion stealth aggregation and a non-lethal de-escalation verb are flagged as open questions below, not committed.

---

## Open questions for the user
(captured in the structured field)
