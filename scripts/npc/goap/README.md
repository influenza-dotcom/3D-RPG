# NPC GOAP brain

Goal-Oriented Action Planning AI for NPCs, replacing the old FSM (`NPC._fsm_tick`'s `match _perception.state`)
with a **pure, unit-testable planner** over the existing NPC components. Introduced by a strangler-fig migration:
every NPC carries a `use_goap` flag (default **false** = the FSM). The planner has been built and tested goal by
goal; flipping `use_goap` on is gated only on a manual-playtest A/B against the FSM (see **Playtest gate** below).

The win: the FSM's *decision layer* was manual-playtest-only. The planner is a pure function of a fact snapshot,
so the whole brain's decisions are off-tree unit-tested (`tests/test_goap_*.gd`, 60+ tests).

## Where it plugs in (`NPC._physics_process`)

The per-frame flow, in order:

1. Acquire/retarget, poll outline, `_perception.sense()`.
2. **No-target early-return**: `if not is_instance_valid(_target): _idle(delta, false); ...; return`. The
   common idle case (and companion-follow with no enemy) lives here — **outside GOAP entirely**.
3. **FLEE pre-seam**: `if not use_goap and threat_response == FLEE and state != UNAWARE: _act_flee(); return`.
   Under `use_goap` this is gated off — the Survive goal owns fleeing instead.
4. **The seam**: `if use_goap and _executor != null: _executor.tick(self, delta) else: _fsm_tick(delta)`.

**Invariant:** the executor only ever ticks with a **valid `_target`** (step 2 returned otherwise). So the GOAP
brain only ever decides among states reached *with* a target: DETECTING, ALERTED, INVESTIGATING, and the narrow
target-valid-but-UNAWARE window (which falls to the Idle floor).

## Pieces (`scripts/npc/goap/`)

- **GoapWorldState** — the fact blackboard (`StringName -> Variant`). `matches` / `apply` (immutable copy) /
  `key` (canonical string for A* dedup). Pure RefCounted.
- **GoapAction** — planning half (`name` / `preconditions` / `effects` / `cost`) + execution half
  (`is_runtime_valid` / `act` returning `Status` RUNNING|SUCCEEDED|FAILED). `enter`/`exit` exist but are **not
  wired** (the executor calls `act` only) — reserved for Phase-5 bark/telegraph hooks.
- **GoapGoal** — `desired_state` + authored `priority` (`base_priority` + `hp_scale`/`temperament_scale`).
- **GoapPlanner** — `static plan()` (forward A*) + `static select_goal()` (highest-priority *feasible* goal).
- **GoapProfile** — Resource hung off `NpcData`: per-archetype goal-priority + action-cost overrides (applied
  in `_build_goap_goals/_actions` over the defaults below — raise `goal_priorities[Survive]` for a coward, lower
  an action's cost for a brawler; the lookup tolerates String *or* StringName keys) + `validate()`. The
  `goals` subset filter is intentionally not wired yet (dropping a combat goal would idle a fighter mid-combat).
- **GoapExecutor** — drives the brain. PURE: `decide` / `current_action` / `advance`. IN-TREE: `tick` +
  `_build_world_state`. Held as a plain RefCounted on the NPC; built in `_build_components`.
- **actions/** — `GoapActionHold / Detect / Investigate / FireArmed / FireUnarmed / Flee`.

## World-state facts (`GoapExecutor._build_world_state`)

| Fact | Source | Meaning |
|---|---|---|
| `has_target` | `is_instance_valid(host._target)` | always true at the seam (sanity only) |
| `hp_frac` | `host.hp / max_hp` | for goal priority scaling |
| `state_detecting/alerted/investigating` | `host._perception.state` | the combat-arm selector |
| `can_fight_with_gun` | `host._can_fight_with_gun()` | armed AND (ammo OR a spare clip) — **not** `is_armed` |
| `threat_noticed` | any non-UNAWARE state | the FLEE "bolt now" condition |
| `is_fleeing` | `host.is_fleeing()` | FLEE archetype OR a temperament runtime-flip |

## Goals & actions (the FSM dispatch, migrated)

Highest-priority **feasible** goal wins. Each combat goal is feasible only in its perception state (its action's
precondition); Idle is the always-feasible floor. Each action delegates to the existing `npc.gd` body for
byte-for-byte parity and stays RUNNING.

| Goal (priority) | Action | Precondition | Effect (sentinel) | Delegates to |
|---|---|---|---|---|
| Survive (3.0) | Flee | `is_fleeing, threat_noticed` | `fled` | `_act_flee` + hide laser |
| Engage (2.0) | FireArmed | `state_alerted, can_fight_with_gun:true` | `target_engaged` | `_ensure_armed_from_backpack` → `_act_alerted` |
| Engage (2.0) | FireUnarmed | `state_alerted, can_fight_with_gun:false` | `target_engaged` | `_ensure_armed_from_backpack` → `_act_unarmed` |
| Investigate (0.4) | Investigate | `state_investigating` | `spot_searched` | move-to-last-known / sweep |
| Detect (0.3) | Detect | `state_detecting` | `threat_faced` | `_face_point(last_known)` + hide laser |
| Idle (0.1) | Hold | `{}` (always) | `idle_done` | scavenge else `_idle` |

"Escort" is **not** a goal: companion-follow is an idle sub-behaviour inside `_idle`, reached via the no-target
early-return or the Idle floor; "a following NPC with a target fights" falls out of Engage outranking Idle.

## Key invariants (read before adding a goal/action)

1. **Sentinel goal pairing.** `GoapPlanner.plan()` returns `[]` for BOTH *satisfied* and *unreachable* goals,
   and `select_goal` skips an empty plan. So never key a goal on an already-true fact (e.g. `has_target`) — it
   self-satisfies and is silently skipped. Pair each goal with a sentinel fact its action *sets* and
   `_build_world_state` *never* senses (`idle_done` / `threat_faced` / `target_engaged` / `spot_searched` /
   `fled`). An empty-effect action also fails — forward A* needs the effect to reach the sentinel.
2. **`act()` only.** The executor never calls `enter`/`exit`. Per-frame side-effects (e.g.
   `_ensure_armed_from_backpack`, mirroring the FSM's per-ALERTED-frame call) go at the top of `act()`.
3. **`is_runtime_valid` re-checks LIVE state.** `tick()` replans ONLY when the current action is null or
   invalid. So every action must invalidate itself when it's no longer the right choice: combat arms gate on
   live `perception.state`; the Hold floor gates on UNAWARE (else it sticks and the NPC idles through a fight
   starting); and a lower-priority action must ALSO gate on a higher-priority INTERRUPT's fact — FireArmed/
   FireUnarmed gate `and not is_fleeing()` so a temperament FIGHT→FLEE flip (which doesn't change perception)
   replans to Flee the same tick.
4. **Monolith for parity.** Each combat action delegates to the whole existing body (`FireArmed` literally calls
   `_act_alerted`), preserving within-frame interleaving (reload-while-closing, dodge-weave, charge-bleed).
   Decomposing into primitives (Arm/Reload/Close/Fire) was shown to *regress* combat — it's deferred to Phase 5.

Two latent parity bugs were caught by adversarial design workflows *before* shipping: the Hold-stickiness (#3),
and combat arms not yielding on `is_fleeing` (#3). Both are now regression-tested in `test_goap_combat_brain.gd`.

## Testing

Off-tree, duck-typed recording stubs — no tree, no `get_tree` (CLAUDE.md forbids running NPC `_ready` in tests):

- `test_goap_planner.gd` — the pure core (world-state, goal priority, plan/select_goal, profile validate).
- `test_goap_action_*.gd` — each action's `act()` delegation + `is_runtime_valid` gating.
- `test_goap_action_contracts.gd` — pins every action's name/cost/preconditions/effects against drift.
- `test_goap_executor.gd` — `_build_world_state` fact sensing + the pure decide/advance core.
- `test_goap_combat_selection.gd` — the full decision matrix (pure `decide()` over the real library).
- `test_goap_combat_brain.gd` — the capstone: tick-driven dispatch, same-tick replan on a perception/flee flip.
- `test_npc_goap_library.gd` — `_build_goap_actions/_goals` assemble the full set at the right priorities.

The heavy `_act_alerted`/`_act_unarmed`/`_idle` bodies and the in-tree `tick` stepping are **manual-playtest**.

## Playtest gate (A/B vs the FSM) — the one thing blocking cutover

Set `use_goap = true` on a combatant archetype's `NpcData` (and a coward + a FLEE archetype), play, and confirm
GOAP is indistinguishable from `use_goap = false`:

- **Idle/UNAWARE** — wanders/returns-to-post, raids a better-gun crate, a companion tails its leader.
- **DETECTING** — turns to face the last-known spot, **no** laser.
- **ALERTED, armed** — closes to engage range, laser charges, incoming beep a beat before the shot, fires on
  cadence, **reloads the instant it runs dry** (+ "reloading" bark), dodge-weaves.
- **ALERTED, unarmed/disarmed** — closes and punches with the same charge telegraph; grabs a nearby gun;
  **handed a gun mid-fight → draws it and switches to shooting** next moment.
- **INVESTIGATING** — walks to the last-known spot, slow-sweeps, gives up after `forget_time`, **no** laser.
- **FLEE archetype** — runs from any noticed threat, never fires; idles/wanders when UNAWARE.
- **Coward (temperament > 0)** — flips to flee mid-fight and **bolts immediately** (does NOT keep firing — this
  was the bug we fixed).
- **Lose line-of-sight mid-fight** — stops firing, hides the laser, switches to the investigate sweep.

A convenience worth adding for this (your call when home): a global `GameSettings.npc_ai.force_goap` debug flag
that the seam ORs into `use_goap`, so you can A/B the *same* scene by toggling one value instead of editing each
archetype. It's a one-line seam change behind a default-false flag — but it lives in the playtest-only seam, so
it can't be GUT-verified; I left it for you to add/approve rather than ship it unvalidated.

## Roadmap

- **Phase 4 — cutover** (after the playtest passes): delete `_fsm_tick` and the FLEE pre-seam's FSM branch,
  flip `use_goap` to default true, then drop the flag. The per-state bodies (`_act_alerted` etc.) **stay** —
  the actions call them.
- **Phase 5 — new behaviors as GOAP actions/goals** (the original AI ask): decompose FireArmed into
  Aim/Wind/Shoot; wire `enter`/`exit` for barks ("I need to reload", a panic line when a coward breaks);
  stealth-awareness facts; an Equip/upgrade goal wrapping `NpcScavenge`; a defend-the-leader goal. These are
  additive — they bolt on behind the validated parity seam without reopening the cutover.
