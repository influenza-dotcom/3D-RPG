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

### Parked Extractions

- **QuestTracker autoload split (M1).** Quest state still lives on `GameState`
  (the B-F40 `_load_warnings` note in `managers/GameState.gd` even anchors it:
  "this field would move with the tracker"). Parked because `GameState.gd` is
  frequently user-dirty — do it in a quiet window.
- **`Landing` component (M13 residual).** The `GroundMovement` statics half
  shipped (`scripts/player/ground_movement.gd` + `tests/test_ground_movement.gd`);
  the `Landing` drop-in (`scripts/player/landing.gd` — on_land / footstep
  ticking, typed `host: Player`, null-guarded) was never created. The
  jump/bhop/blast/slide-jump/edge-friction interleave stays on the Player root
  in order — it is byte-order-critical.

### Pending One-Time Playtest Sweep (2026-07-11 remediation)

The 2026-07-11 review remediation shipped (GUT-verified, commit `aa0fdd0`), but
these in-tree behaviours were never play-verified. Drive `game.tscn` (New Game),
check each once, then delete this section.

- [ ] New Game → NO abilities; install a chip → it grants. Die under
  RELOAD_CHECKPOINT_FRESH → respawn keeps the run (stats/unlocks/money).
- [ ] Loot a corpse whose coin tile overflows a full grid → coin shows in the
  overflow strip (click to take); corpse drains and the ragdoll fades.
- [ ] Guard has you in sight-range but unnoticed: throw a decoy → it
  investigates; hide a body in that state → it gets discovered.
- [ ] Die with Chess / a pet-naming box open → both close during the cinematic.
  F9 under an open backpack/loot/options → no reload.
- [ ] Grab a prop during the death cinematic → not still-carried after revive.
  A wind-up shot interrupted by holster/carry/death → doesn't resolve. Hotbar
  keys inert during a cutscene / name box.
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
