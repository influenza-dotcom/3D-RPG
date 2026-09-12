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

The full GUT run went green again on 2026-09-09 (`48c81e73`, starting with a
stranded `Engine.time_scale`); the static count today is 432 `tests/test_*.gd`
files / 5,394 `func test_`. `tests/test_global_node_added_listeners.gd` skips
`res://scripts/tools` by design (`EXCLUDED_DIRS` — the probes there ship
nothing), so `__first_kill_hitch_probe.gd` is excluded, not tolerated. Headless
runs still print known orphan/resource and dummy-renderer noise; it does not fail
the suite, but it makes real regressions harder to notice, so quiet tests remain
worth treating as engineering polish.

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
  (`ui.gd`'s `_stamp_owed_row` has zero test coverage). ~~install a chip → it
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
