# Architecture Review

This is the current code-health review. It is intentionally short and
actionable; use [docs/CURRENT_ARCHITECTURE.md](docs/CURRENT_ARCHITECTURE.md) for
the system map and [docs/AUTHORING_GUIDE.md](docs/AUTHORING_GUIDE.md) for
designer workflows.

For the Save Model (what `GameState` persists) and the scene/system contracts,
see [docs/CURRENT_ARCHITECTURE.md](docs/CURRENT_ARCHITECTURE.md); this file only
tracks the transient rough edges below.

## Current Rough Edges

### NPC Gravity

`scripts/npc/npc.gd` is still the largest coordination point. It already delegates
to components and helpers (`NpcVoice`, `NpcTargeting`, `NpcLocomotion`, `NpcCombat`,
GOAP, bark UI, audio cues, scavenge helpers), but new NPC behaviour should avoid
adding more branches to the root script. Prefer a Resource, component, or helper
with a narrow facade back into `NPC`.

Aim computation (`_aim_point` / `get_aim_origin` / `get_aim_direction`) stays on
the root **by contract** (the DEFER verdict of the 2026-08 extraction review),
not as debt — do not re-flag it. Melee strike handling and the combat firing
dispatch already moved out into `NpcCombat`; stuck steering and the give-up
machine moved to `Locomotor` (`scripts/components/locomotor.gd`, Phase B);
damage visuals moved to `NpcOutline` (`scripts/npc/npc_outline.gd`); bark
EMISSION moved into `NpcVoice.emit`, and the unaware/distraction reaction bodies
onto `NpcDistraction` (`scripts/npc/npc_distraction.gd`) — `npc.gd` keeps only
thin forwarding facades for all of those.

### Test Noise

**The GUT suite is NOT green** (measured 2026-09-02): **8 failing tests** out of
5,231 in 426 scripts, in six files — `test_fp_body_arms`, `test_fp_torso`,
`test_global_node_added_listeners`, `test_groups`, `test_lean` (3) and
`test_weapon_bench`. **Six** are real behavioural assertions (a lean claim
surviving the posture gate, a bench refusal reason coming back `slot_taken`
instead of `bag_full`), not harness noise. The other **two are source-SCAN
architecture guards** that never exercise runtime behaviour: `test_groups` greps
production source for raw group literals (tripped by
`scripts/tools/view_model_tonemap_qa_shots.gd`) and
`test_global_node_added_listeners` counts `node_added.connect` sites (tripped by
the leftover probe `scripts/tools/__first_kill_hitch_probe.gd`). Both are debug
scaffolding under `scripts/tools/`, not gameplay — so do not read them as a
behaviour regression, but fix the source either way; do not re-baseline the
tests. Separately, headless runs still print known orphan/resource and
dummy-renderer noise. That noise does not fail the suite, but it makes real
regressions harder to notice. Quiet tests are worth treating as engineering
polish, especially around UI lifecycle and smoke-test cleanup.

### Manual-Playtest Seams

Some in-tree behaviours are still verified mainly by playtest: physics/raycast
interactions, GOAP action bodies outside combat, UI lifecycle, and some
cutscene/pickup flows. The combat firing chain
(perceive → aim → fire → hit → take_damage) is now locked down in-tree by
`scripts/tools/combat_smoke_harness.gd` (`tests_soak/test_combat_smoke.gd`), and
the level-flow lifecycle (GameRoot boot, saved-vs-export resolution, the runtime
`load_level()` swap) by `tests/test_level_boot_lifecycle.gd`. (LevelDoor
door-to-door travel is dormant by design — no door is placed in a shipping
level; its wiring contract is pinned by `tests/test_level_door_prefab.gd`.) That
is normal for Godot, but any cheap in-tree harness that locks a contract down
should replace "playtested" over time.

### Completed Extractions

The extractions this file used to park are done. Kept as a short record
because each one established an idiom the next extraction should copy.

- **QuestTracker autoload split (M1).** DONE. The tracker dicts, the four quest
  signals, reward granting and the cfg round-trip live on `managers/QuestTracker.gd`;
  `GameState` keeps one-line FORWARDERS for the function API (~70 authored call
  sites use them) but the SIGNALS moved — connect to `QuestTracker.quest_started`
  / `objective_advanced` / `quest_completed` / `quest_failed`.
  - ⭐ The load-bearing detail is **bidirectional injection**
    (`GameState.quest_tracker` ↔ `QuestTracker.game_state`). Quest state used to
    live on `GameState`, so a bare `GameState.new()` gave a unit test a private
    journal for free. Pointing every GameState at the singleton would have leaked
    quest state between tests — `test_game_save` proved it within minutes. A bare
    GameState now builds its OWN tracker as a *child* (freed with it, no orphan);
    only the autoload pairs with the autoload. `tests/test_quest_tracker.gd` pins
    all of this; copy the pattern for the next autoload split.
  - Made public in passing: `GameState.autosave_world_state()` and
    `GameState.live_player()` (both were already being called cross-file as
    privates by `ledger_accrual.gd` / `player.gd`).
- **`Landing` component (M13 residual).** DONE — `scripts/player/landing.gd`,
  a scene-wired drop-in (`host = NodePath("..")` + the Player's `landing` export)
  owning the touchdown burst and the footstep cadence. Both beats run AFTER
  `apply_velocity()` and feed only presentation + fall damage, which is exactly
  why they were safe to lift. The jump/bhop/blast/slide-jump/edge-friction
  interleave still stays on the Player root **in order** — it is
  byte-order-critical and must not follow. The two pure curves (`impact_for` /
  `interval_for`) are statics so the feel math is testable without a Player, the
  way `GroundMovement` already is; `tests/test_landing.gd` pins the wiring and
  the curves.
- **`FirstPersonBody` component.** DONE — `scripts/player/first_person_body.gd`,
  a scene-wired drop-in on the Landing idiom (`host = NodePath("..")` + the
  Player's `fp_body` back-export) owning the whole cosmetic first-person self:
  the FP legs+torso rig, the carry-hands / bare-fists rig, the draw / stow /
  guard / punch machinery and the fists' procedural bob. The Player KEEPS the
  weapon-lock half of the carry dance (`_on_carry_changed`: the `_carrying`
  latch, holster capture/restore, `draw_locked`, release bookkeeping),
  `_rewield_in_flight`, the `FISTS` fallback const, and the death/revive ORDER
  (die() / the revive call `set_legs_visible` + `refresh_unarmed_hands` at
  their authored beats). Three ⭐ invariants:
  - The 11 authored `fp_*` overrides in Player.tscn moved onto the new node
    **byte-exact** — every historic FP bug (the stow mis-anchor, the guard
    framing) was invisible at script defaults and only real at the authored
    pose. `tests/test_first_person_body_wiring.gd` pins them on the child AND
    their absence from the root (a move, not a copy).
  - The carry relay is **ONE connection**: the Player's `_on_carry_changed`
    tails into `fp_body.on_carry_changed`, so the synchronous holster restore
    always precedes the fists decision reading `attack.holstered`. Splitting it
    into two connections on `carry_changed` re-opens a connection-order
    dependency (children connect in `_ready` before their parent — the wrong
    side would win).
  - `process_priority = -1` (plus authoring the node before Head) keeps the
    component's pose ease ahead of the arms rig's strike re-pose — the
    setter-ordering fix the monolith got free from parent-before-child ticking.
  The four pure statics (`fp_arm_stow_target` / `bob_cadence` / `bob_lean` /
  `advance_bob_phase`) moved whole with their contract comments;
  `tests/test_fists_view_model.gd` and `tests/test_fp_torso.gd` re-pin against
  the component. One deliberate non-shipped-config behavior change: the
  `carry_changed` connect is now unconditional (made in `Player._ready`, not
  inside the arms build), so `first_person_arms = false` still holsters + locks
  the gun mid-carry — the intent the relay's comment always documented; shipped
  Player.tscn has arms ON, so shipped behavior is identical.
- **NpcVoice bark EMISSION (`emit`).** DONE — the awaited `_emit_bark` body
  (empty-line skip → no-overlap latch stamp → reaction-delay await → dead/hp/
  in-tree bail → bubble → earshot-gated TTS) moved onto
  `scripts/npc/npc_voice.gd` as `emit()`, with `_speak()` private beside it
  (the old `NPC._speak_bark`, which had no other consumer); `NPC._emit_bark` is
  now the null-guarded 1-line facade.
  - ⭐ The NpcVoice triggers must KEEP routing `host._emit_bark(...)` — never
    `self.emit()`. `tests/test_bark_gates.gd`'s stub hosts implement
    `_emit_bark` to count emissions and `tests/test_npc.gd` pins `_emit_bark`
    as the single bark emitter — a future "simplification" of the round-trip
    breaks ~6 stub tests and the seam.
  - ⭐ `_speak` passes the HOST as the SpeechTts source. `NPC._on_died` stops
    our bark via `SpeechTts.stop_bark_from(self)` keyed on the NPC node — pass
    the child instead and the stop silently never matches (dead NPCs keep
    talking).
  - ⭐ The latch (`host._bark_until_msec` — still host-owned and bare-NPC
    test-poked) is stamped BEFORE the reaction-delay await, so two same-beat
    bark requests can't both pass (stacked bubbles). The post-await
    dead/hp/in-tree guard order covers the POOLED host (reused in place); a
    non-pooled host frees the child (and the coroutine) with itself.
    `tests/test_npc_facade_contract.gd` pins the facade + the source identity
    by source-grep.
- **`NpcDistraction` (unaware/distraction reactions).** DONE —
  `scripts/npc/npc_distraction.gd` owns the `_react_unaware` /
  `_scan_distractions` / `_react_distraction` / `_react_music` bodies plus
  corpse discovery, with the scan throttles and the once-per-attend
  music-comment latch as component state (its own `reset_for_reuse` joins the
  pool cascade). Built BY SCRIPT PATH into a Node-typed `_distraction`
  (the CrippleCallout / NpcHomeReturn @tool-parse idiom).
  - ⭐ The `_physics_process` call sites stayed put in byte order:
    `_react_unaware` BEFORE the no-target `_executor.tick` (the executor reads
    the Perception state it sets/decays), `_react_distraction` / `_react_music`
    AFTER the tick (the face overrides the idle facing) — the facades must not
    shift position, and `_react_unaware`'s first line
    (`host._alerted_allies = false`, the GA-1 re-arm) travels with the body.
  - ⭐ Host-owned vs component-owned state split: `_alerted_allies` /
    `_was_distracted` / `_scripted_investigating` / `_attending_radio` /
    `_desired_velocity` stay on the host (cross-consumed by the settle-barks
    helper, the has-target branch, `investigate()`, the head-look, and bare-NPC
    test pokes); only `_distraction_scan_t` / `_music_scan_t` /
    `_music_commented_radio` moved. `tests/test_npc_pool.gd` pins the component
    reset; `tests/test_npc_facade_contract.gd` pins the path build and the
    facade surface.
- **`StaminaManager` (stamina/sprint economy).** DONE —
  `scripts/player/stamina_manager.gd`, a `RefCounted` on the AbilityManager
  idiom (built at the Player's var-init, host + signal relay wired in
  `Player._init`, so bare-`Player.new()` tests drive it with no `_ready`). The
  pool, spend/drain, the regen curve + post-spend delay, and the sprint lockout
  moved; the Player keeps the `stamina_changed` signal (the manager's same-shape
  signal is relayed by `_on_stamina_changed`), a RAW `stamina` property alias
  (no clamp/emit — ui.gd's `player.get(&"stamina")` poll and the tests' raw
  overdraw writes keep bare-var semantics), `is_sprinting()`'s verbatim one-line
  body (it reads the host's `input_dir`), and 1-line forwarders for the whole
  old surface — public and private names unchanged, so every duck-typed caller
  and white-box test line survived. One pure static, `recovery_rate_for` (the
  Landing `impact_for` precedent), carries the regen tier pick hostlessly.
  - ⭐ The drive beats stayed in `Player._physics_process` **byte-identical at
    their positions**: `_update_sprint_lockout` before the dialogue gate, and
    `_update_stamina_recovery` in BOTH branches — the dialogue-frozen early-out
    AND the live tail (the NPC idle/UNAWARE both-branches rule, player
    edition). Do not "simplify" them into a manager-side tick: `die()`'s
    `set_physics_process(false)` must freeze regen and the lockout countdown.
    `die()` writes no stamina state; the revive beats (the `_set_stamina`
    refill at its authored position — it EMITS for the HUD ring — then
    `clear_sprint_lockout()`, the one rewritten beat line) stay in
    `_respawn_at_checkpoint`.
  - ⭐ `host: Character`, never `Player` — a preload-by-path script naming the
    Player class is the class_name↔preload parse-cycle trap. Character covers
    the hot path typed; the Player-script-only surface (`input_dir`, `crouch`,
    `_is_scoped`, the climb/slide/grapple predicates) is read dynamically with
    null-guards, so a bare manager degrades to bare-Player defaults instead of
    crashing (`tests/test_player_core.gd` pins the table).
  - ⭐ NO `class_name`, by choice: player.gd is the sole runtime consumer and
    preloads it by path (`StaminaManagerRef`, the StatBudget idiom) — a fresh
    class_name is the stale-class-cache cascade in the next headless run. All
    tuning stays on `GameSettings.player_movement` / `weapon_general` — bar the
    RANGED SHOT price, which is derived per weapon from `WeaponData.stamina_effort()`
    and trimmed by `stamina_cost_mult`; the manager holds zero knobs.
  - Two `tests/test_player_core.gd` migrations only: the `_sprint_lockout_left`
    white-box read now goes through `p._stamina_mgr`, and the
    `"if sprint_blocked_by_scope():"` source pin greps the manager file (the
    fragment is unchanged). Every other stamina pin — including
    `is_sprinting()`'s body grep against player.gd — survived untouched.

### Payment Rails

The ledger's point-of-sale surface is closed. `Character.quote()` / `Player.quote()`
expose the two-part quote (base + service charge) that ShopScreen paints as an
all-in total; `Merchant.accepts_ledger` gives cash-only vendors a single
`can_afford` / `take_payment` / `quoted_total` predicate trio the till and the UI
dim share; the HUD carries an OWED row; `scenes/components/atm.tscn` is the
drop-in world terminal; and the DEBIT/CREDIT choice is available **at every point
of sale** that honours both rails, not just at an ATM.

That last piece is `PaymentRailButton` (`scripts/ui/payment_rail_button.gd`) — one
drop-in authored into all six paid screens (shop, heal, level-up, chip-install,
respec, gunsmith bench). It owns the toggle, the caption, and the
persist-on-flip; the host screen connects `rail_changed` to its own repaint.

> ⭐ **One till refuses the credit rail on purpose: `LevelUp` (`accepts_credit`,
> default off).** It is the only counter that sells entries on the permanent stat
> sheet, and `Player.credit_limit()` re-rates that sheet live — so a stat point
> bought on credit raises the line that funded it (1 zm buys 100 zm of new line at
> the shipped knobs; the ladder ends at total level 51 / 2022 zm owed for every
> build), erasing the creation choice. The refusal rides a new `allow_credit`
> parameter on the payment seam (`can_pay` / `charge` / `charge_total` / `quote` /
> `spendable`, defaulted true so every other caller is unchanged), NOT a UI change —
> hiding the selector alone would be cosmetic, since the rail is global persisted
> state.
>
> ⭐ **And the rail refusal alone is not enough**, which is why `LevelUp` also ships
> `requires_settled_account = true`. The credit line is fungible into CASH at any
> ledger vendor — `Merchant.take_payment` funds the buy on the armed rail while
> `Merchant.sell` pays out in cash, and `sell_price` is clamped to one coin under
> `buy_price` — so a buy/sell round trip converts the line at ~97% and walks the
> proceeds to a cash-taking till. The shipped Medicine Person carries both
> components. Refusing a PAID raise while the account is negative closes that
> arithmetically. **That credit-to-cash conversion is itself an open defect against
> `Atm.withdraw`'s stated invariant** and is not fixed here.
>
> Not a die-and-keep-it loop, despite an earlier framing: the debt is death-safe
> too (`GameState.account` — "you cannot die your way out of the Ledger").
> `tests/test_level_up_credit.gd` pins both gates.

> ⭐ **The signal is the contract, not garnish.** The armed rail changes what
> `Player._split` may draw on, so it changes the affordability dim and the quoted
> total *on the same card*. A screen that carried the button but ignored
> `rail_changed` would flip the rail and leave a row greyed out that the till would
> now serve — exactly the divergence the payment seam exists to prevent.
> `tests/test_payment_rail_selector.gd` pins the connection in all six screens by
> source-grep, because it is made at runtime in `_bind_ui`.

That asymmetry is CLOSED (2026-08-11): all six paid cards now paint the **all-in**
total through `charge_total`, and the heal / respec / level-up funds readouts paint
`spendable()` rather than raw `money`. The gate still runs on the RAW sticker —
`can_pay` / `charge` fold the service charge in themselves, so wrapping the gate's
argument in `charge_total` would double-apply it.

### Pending One-Time Playtest Sweep (2026-07-11 remediation)

The 2026-07-11 review remediation shipped (GUT-verified, commit `aa0fdd0`), but
these in-tree behaviours were never play-verified. Drive `game.tscn` (New Game),
check each once, then delete this section.

> **Measured 2026-08-14 — do not re-run this analysis.** The 13 bullets below pack **45 distinct
> sub-checks**. Every one was searched against `tests/`, and every "already covered" answer was then
> adversarially re-checked by opening the cited assertion. The result:
>
> | | |
> | --- | --- |
> | Genuinely closed by a test | **6** |
> | Partially covered (inputs pinned, outcome not) | **10** |
> | Genuinely need a driven game | **29** |
>
> **24 of the 45 first-pass answers were downgraded on re-check** — the common failure was treating a
> source-string grep, or an assertion on an off-tree helper, as coverage of live per-frame behaviour.
> So `REMEDIATION_PLAN.md` 5.3's "verifying is cheap" is **wrong**: this list is mostly not
> automatable, largely because `CLAUDE.md` forbids running `Player._ready()` / `NPC._ready()` under
> GUT by design. Timing, audio mixing, visual fades and input feel are the bulk of what remains.
> **Play the game to close these.** Where a sub-check IS covered, it is annotated inline below.

- [ ] New Game → NO abilities beyond implants bought on credit. **Inputs pinned, outcome not:**
  `test_new_game_contract.gd:25-26` and `test_implant_choice.gd:390-391` assert
  `starting_unlocks` and `GameState.unlocks` are empty, but ⚠ **`starting_unlocks` is not the
  only grant surface** — `ability_manager.gd:6` says an editor-placed `Ability` child of the
  Player is itself the grant ("presence + `enabled` IS the grant"), and nothing pins that none
  exists. `Player.tscn` has none today; a designer dropping one in leaves every assertion green
  while the run boots with a free ability. ~~since 2026-08-05 creation's Begin leads to the
  purchase screen~~ **covered** (`test_implant_choice.gd:338-342`, on a real StartMenu instance);
  ~~the bill starts the wallet NEGATIVE~~ **STALE — do not look for this.** The ledger
  refactor moved the bill off `money` onto the one signed `GameState.account`;
  `test_implant_choice.gd:378-379` pins that the wallet is untouched and stays ≥ 0.
  **Still needs a human:** check the HUD's OWED row actually paints a signed balance
  (`ui.gd:1724 _stamp_owed_row` has zero test coverage). ~~install a chip → it
  grants~~ **covered** (`test_chip_install.gd:119-129`). Die under
  RELOAD_CHECKPOINT_FRESH → respawn keeps the run (stats/unlocks/money, debt included).
- [ ] Loot a corpse whose coin tile overflows a full grid → coin shows in the
  overflow strip (click to take); corpse drains and the ragdoll fades.
- [ ] Guard has you in sight-range but unnoticed: throw a decoy → it
  investigates; hide a body in that state → it gets discovered.
- [ ] Die with Chess / a pet-naming box open → both close during the cinematic.
  F9 under an open backpack/loot/options → no reload.
- [ ] Grab a prop during the death cinematic → not still-carried after revive.
  A wind-up shot interrupted by holster/carry/death → doesn't resolve. Hotbar
  keys inert during a cutscene / name box.
- [ ] Death sting: the world drains while the sting holds level, then cross-fades
  back on the revive. Every `death_mode` boots the next life at FULL volume on all
  four world buses. Die mid-conversation / while scoped → the music bus doesn't
  jump. ADS repeatedly during the revive fade → music never staircases down.
  Drag a volume slider behind the death card → the world stays ducked.
- [ ] Hotbar-assign / hold the zorkmids coin tile → refused. Pickpocket a
  zorkmids tile off a live NPC → pocket float isn't double-debited.
- [ ] Esc out of a wagered chess match vs a White opponent before moving → NOT
  charged. Install a chip whose ability id doesn't resolve → not charged.
- [ ] Standing in a hazard / poisoned, start a cutscene → no damage ticks
  through the control-locked window.
- [ ] Fleeing townsperson given a scripted investigate → no per-frame errors.
  Partial-clip / empty-reserve NPC → no dry-click SFX spam; it stands down.
- [ ] Provoke then holster near a factioned NPC → it can de-escalate (rep
  restored). Auto-aggro squad spawn → faction rep drops once, not ×N.
- [ ] Author a Pettable/Claimable `max_range` of 5–8 → the verb works at that
  range (no silent 4 m cap).
- [ ] A level with a ShaderMaterial surface under Ps1Warp → not painted flat
  white.
