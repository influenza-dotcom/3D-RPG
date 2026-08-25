# NPC GOAP Brain

Goal-Oriented Action Planning AI is the sole NPC decision layer. It is a pure,
unit-testable planner over the existing NPC components, with runtime action
bodies delegated back through `NPC` facades into the components where movement,
animation, combat, and barks live (`NpcLocomotion`, `NpcCombat`, `NpcVoice`).

The planner owns combat and no-target decisions: idle, companion follow,
wandering, scavenging, stealth noise investigation, body discovery, detection,
engagement, and fleeing.

## Where It Plugs In

The per-frame `NPC._physics_process` flow is:

1. Acquire or retarget, then poll outline state.
2. Sense the environment. With no valid target, `_react_unaware` (its body now
   on `NpcDistraction`, behind the npc.gd facade) records stealth/body stimuli
   or clears invalid alerts before planning.
3. Tick `_executor.tick(self, delta)` when the executor exists.
4. The selected action delegates to the relevant NPC method.

Every NPC builds `_executor` in `_build_components`. The null guard exists for
partially constructed test instances.

**Invariant:** the executor ticks every frame, with or without a target. With no
valid `_target`, combat perception states cannot apply; a just-lost target is
`forget()`'d to UNAWARE so the planner picks the Idle floor (`Hold`) or, on a
sensed stealth stimulus, `Investigate`.

## Pieces

- **GoapWorldState** - fact blackboard (`StringName -> Variant`). `matches`,
  `apply` (immutable copy), and `key` are pure RefCounted logic.
- **GoapAction** - planning half (`name`, `preconditions`, `effects`, `cost`)
  plus execution half (`is_runtime_valid`, `act` returning
  `RUNNING|SUCCEEDED|FAILED`). `enter` and `exit` are reserved hooks; the
  executor currently calls `act()` only.
- **GoapGoal** - `desired_state` plus authored priority
  (`base_priority`, `hp_scale`, `temperament_scale`).
- **GoapPlanner** - `static plan()` (forward A*) plus
  `static select_goal()` (highest-priority feasible goal).
- **GoapProfile** - Resource hung off `NpcData`: per-archetype goal-priority
  and action-cost overrides applied over the defaults. The lookup tolerates
  String or StringName keys. The `goals` allow-list is enforced (empty = pursue
  all; a subset restricts the NPC, but `Idle` is always kept so the brain can't
  idle to a null goal). `validate()` runs at spawn + in the content validator.
- **GoapExecutor** - drives the brain. Pure methods: `decide`,
  `current_action`, and `advance`. In-tree methods: `tick` and
  `_build_world_state`.
- **actions/** - `GoapActionHold`, `Detect`, `Investigate` (class
  `GoapActionSearch`), `FireArmed`, `FireUnarmed`, and `Flee`.

## World-State Facts

| Fact | Source | Meaning |
|---|---|---|
| `has_target` | `is_instance_valid(host._target)` | gates combat vs no-target idle/stealth decisions |
| `hp_frac` | `host.hp / max_hp` | for goal priority scaling |
| `temperament` | `host.temperament` | dynamic-priority knob; `priority() += temperament_scale * temperament` (a coward weights Survive up) |
| `state_detecting/alerted/investigating` | `host._perception.state` | combat arm selector |
| `can_fight_with_gun` | `host._can_fight_with_gun()` | armed and either loaded or carrying a spare clip |
| `threat_noticed` | any non-UNAWARE state | Flee condition |
| `is_fleeing` | `host.is_fleeing()` | flee archetype or temperament runtime flip |

## Goals And Actions

Highest-priority **feasible** goal wins. Each combat goal is feasible only in
its perception state. Idle is the always-feasible floor. Each action delegates
to an `NPC` behaviour facade (`host._act_*`, which forwards into `NpcCombat` /
`NpcLocomotion`) and usually stays RUNNING.

| Goal (priority) | Action | Precondition | Effect (sentinel) | Delegates to |
|---|---|---|---|---|
| Survive (3.0) | Flee | `is_fleeing, threat_noticed` | `fled` | `_act_flee` + hide laser |
| Engage (2.0) | FireArmed | `state_alerted, can_fight_with_gun:true` | `target_engaged` | `_ensure_armed_from_backpack` -> `_act_alerted` |
| Engage (2.0) | FireUnarmed | `state_alerted, can_fight_with_gun:false` | `target_engaged` | `_ensure_armed_from_backpack` -> `_act_unarmed` |
| Investigate (0.4) | Investigate | `state_investigating` | `spot_searched` | move-to-last-known / sweep |
| Detect (0.3) | Detect | `state_detecting` | `threat_faced` | `_face_point(last_known)` + hide laser |
| Idle (0.1) | Hold | `{}` | `idle_done` | scavenge else `_idle` |

Escort/follow is not its own goal. Companion-follow is an idle sub-behaviour
inside `_idle`, reached through the Hold action. A following NPC with a target
fights because Engage outranks Idle.

### Canonical name roster (executable spec)

This block is the ONE machine-verified copy of the goal/action vocabulary. It is
diffed against `GoapLibrary` by `tests/test_goap_docs_roster.gd`, which fails
loudly if the two ever disagree — so this doc can't silently rot when a goal or
action is added or renamed (the prose tables above are illustrative; THIS block
is the checked one). When the roster changes, update `goap_library.gd` first
(the `test_npc_goap_library.gd` drift test forces that), then edit the two lines
below to match. Never hand-edit a name here just to green the test — that hides a
real divergence from the library.

<!-- GOAP_ROSTER:BEGIN — parsed by tests/test_goap_docs_roster.gd; keep the two `- Goals:` / `- Actions:` lines below in this exact shape (comma-separated names). -->
- Goals: Survive, Engage, Investigate, Detect, Idle
- Actions: Hold, Detect, Investigate, FireArmed, FireUnarmed, Flee
<!-- GOAP_ROSTER:END -->

## Key Invariants

1. **Sentinel goal pairing.** `GoapPlanner.plan()` returns `[]` for both
   satisfied and unreachable goals, and `select_goal` skips an empty plan. Never
   key a goal on an already-true sensed fact such as `has_target`. Pair each
   goal with a sentinel fact that its action sets and `_build_world_state` never
   senses (`idle_done`, `threat_faced`, `target_engaged`, `spot_searched`,
   `fled`).
2. **`act()` only.** The executor does not call `enter` or `exit`. Per-frame
   side effects belong at the top of `act()`.
3. **`is_runtime_valid` re-checks live state.** `tick()` replans only when the
   current action is null or invalid. Every action must invalidate itself when
   it is no longer the right choice. Lower-priority actions must also yield to
   higher-priority interrupts, such as `is_fleeing()`.
4. **Delegate bodies preserve frame ordering.** Combat actions call the NPC
   behaviour bodies (`_act_alerted`, `_act_unarmed`, `_act_flee`, `_idle`) so
   reloads, dodges, target-facing, barks, and movement stay in their authored
   order. Split an action only with focused tests and a playtest pass.
5. **Regression coverage matters.** `test_goap_combat_brain.gd` covers the
   Hold invalidation path and the same-tick replan when flee state flips.

## Testing

Off-tree, duck-typed recording stubs cover planner logic without running NPC
`_ready`:

- `test_goap_planner.gd` - world state, goal priority, plan/select goal, profile validation.
- `test_goap_action_*.gd` - each action's `act()` delegation and runtime gating.
- `test_goap_action_contracts.gd` - action name/cost/precondition/effect contracts.
- `test_goap_executor.gd` - fact sensing and pure decide/advance logic.
- `test_goap_combat_selection.gd` - full decision matrix over the real library.
- `test_goap_combat_brain.gd` - tick-driven dispatch and same-tick replans.
- `test_npc_goap_library.gd` - action/goal assembly at the right priorities, plus the `GoapLibrary` roster vs the built library.
- `test_goap_docs_roster.gd` - this README's canonical-roster block vs `GoapLibrary` (docs-as-executable-spec; catches a stale doc).

The heavyweight `_act_alerted`, `_act_unarmed`, `_act_flee`, and `_idle` bodies
still need scene or playtest coverage when changed.

## Behaviour Spec

Every NPC must satisfy these behaviours:

- **Idle/UNAWARE** - wanders or returns to post, raids a better-gun crate, and a
  companion tails its leader.
- **DETECTING** - turns to face the last-known spot with no laser.
- **ALERTED, armed** - closes to engage range (a projectile gun with a positive
  `effective_range` already fires while closing through the grace band beyond
  it - `npc_ai.fire_grace_range`, see `NpcCombat.attempt_fire_range`; the
  unranged rock lob gets no band), laser charges, incoming beep plays before
  the shot, fires on cadence, reloads as soon as it runs dry, and dodge-weaves.
  Every ranged shot it takes is a LIVE projectile (enemies never hitscan -
  `ShotResolver.ai_fires_live_projectile`; melee swings keep the trace), spread
  by its gunplay-scaled aim-error cone (`npc.gd aim_error_spread`), so incoming
  fire has travel time and can genuinely be dodged.
- **ALERTED, unarmed/disarmed** - closes and punches with the same charge
  telegraph, grabs a nearby gun, and switches to shooting after receiving one.
- **INVESTIGATING** - walks to the last-known spot, slow-sweeps, gives up after
  `forget_time`, and uses no laser.
- **FLEE archetype** - runs from any noticed threat, never fires, and
  idles/wanders when UNAWARE.
- **Coward temperament** - flips to flee mid-fight and immediately runs.
- **Lose line of sight mid-fight** - stops firing, hides the laser, and switches
  to the investigate sweep.
