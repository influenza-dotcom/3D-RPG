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

Good future extractions are sections with a clear noun and contract, such as
damage visuals, stuck steering, or aim computation. (Melee strike handling and
the combat firing dispatch already moved out into `NpcCombat`.)

### Test Noise

The GUT suite is green, but headless runs still print known orphan/resource and
dummy-renderer noise. That does not currently fail the suite, but it makes real
regressions harder to notice. Quiet tests are worth treating as engineering
polish, especially around UI lifecycle and smoke-test cleanup.

### Manual-Playtest Seams

Some in-tree behaviours are still verified mainly by playtest: physics/raycast
interactions, GOAP action bodies outside combat, level transitions, UI lifecycle,
and some cutscene/pickup flows. The combat firing chain
(perceive → aim → fire → hit → take_damage) is now locked down in-tree by
`scripts/tools/combat_smoke_harness.gd` (`tests_soak/test_combat_smoke.gd`). That is
normal for Godot, but any cheap in-tree harness that locks a contract down should
replace "playtested" over time.
