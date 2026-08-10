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

Aim computation is the remaining section with a clear noun and contract
(`_aim_point` / `get_aim_origin` / `get_aim_direction` still live on the root).
Melee strike handling and the combat firing dispatch already moved out into
`NpcCombat`; stuck steering and the give-up machine moved to `Locomotor`
(`scripts/components/locomotor.gd`, Phase B); damage visuals moved to
`NpcOutline` (`scripts/npc/npc_outline.gd`) — `npc.gd` keeps only thin
forwarding facades for those.

### Test Noise

The GUT suite is green, but headless runs still print known orphan/resource and
dummy-renderer noise. That does not currently fail the suite, but it makes real
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

Both of the extractions this file used to park are done. Kept as a short record
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

### Payment Rails

The ledger's point-of-sale surface is closed. `Character.quote()` / `Player.quote()`
expose the two-part quote (base + service charge) that ShopScreen paints as an
all-in total; `Merchant.accepts_ledger` gives cash-only vendors a single
`can_afford` / `take_payment` / `quoted_total` predicate trio the till and the UI
dim share; the HUD carries an OWED row; `scenes/components/atm.tscn` is the
drop-in world terminal; and the DEBIT/CREDIT choice is available **at every point
of sale**, not just at an ATM.

That last piece is `PaymentRailButton` (`scripts/ui/payment_rail_button.gd`) — one
drop-in authored into all five paid screens (shop, heal, level-up, chip-install,
respec). It owns the toggle, the caption, and the persist-on-flip; the host screen
connects `rail_changed` to its own repaint.

> ⭐ **The signal is the contract, not garnish.** The armed rail changes what
> `Player._split` may draw on, so it changes the affordability dim and the quoted
> total *on the same card*. A screen that carried the button but ignored
> `rail_changed` would flip the rail and leave a row greyed out that the till would
> now serve — exactly the divergence the payment seam exists to prevent.
> `tests/test_payment_rail_selector.gd` pins the connection in all five screens by
> source-grep, because it is made at runtime in `_bind_ui`.

One asymmetry left deliberately: only ShopScreen paints the **all-in** total. The
healer / level-up / chip-installer / respec cards still show the vendor's base
price, while `charge` adds the account's service charge when the purchase is
ledger-funded. The gate is honest everywhere (all five read `can_pay`), so nothing
is refused unexpectedly — but a ledger-funded buy can debit slightly more than the
card quoted. Closing it means routing four more price labels through `quote()`.

### Pending One-Time Playtest Sweep (2026-07-11 remediation)

The 2026-07-11 review remediation shipped (GUT-verified, commit `aa0fdd0`), but
these in-tree behaviours were never play-verified. Drive `game.tscn` (New Game),
check each once, then delete this section.

- [ ] New Game → NO abilities beyond implants bought on credit (empty cart = zero;
  since 2026-08-05 creation's Begin leads to the purchase screen, and the bill
  starts the wallet NEGATIVE — check the HUD reads a signed balance); install a
  chip → it grants. Die under RELOAD_CHECKPOINT_FRESH → respawn keeps the run
  (stats/unlocks/money, debt included).
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
