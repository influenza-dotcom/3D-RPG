# Architecture Review

This is the current code-health review. It is intentionally short and
actionable; use [docs/CURRENT_ARCHITECTURE.md](docs/CURRENT_ARCHITECTURE.md) for
the system map and [docs/AUTHORING_GUIDE.md](docs/AUTHORING_GUIDE.md) for
designer workflows.

## Current Health

The project has a strong editor-first architecture. Most gameplay systems expose
one of the three intended authoring surfaces:

- drop-in components with `class_name` and `@export` fields,
- authored `.tres` Resources such as `NpcData`, `LootTable`, `WeaponData`,
  `LevelData`, `Loadout`, `StatusEffect`, and `MapData`,
- global tuning Resources under `resources/tuning/` exposed through
  `GameSettings`.

The best parts of the codebase are the seams that make these surfaces compose:
`GameRoot`/`LevelData` for level flow, `LookAtInteractable` for aim-at world
interaction, `ItemDb` folder scans for content discovery, GOAP Resources for NPC
decision tuning, and focused test coverage around save codecs, data registries,
and pure combat/planner math.

## Current Rough Edges

### Save Scope

`GameState` is a profile/checkpoint save, not an exact world snapshot. It
persists player progression, inventory, reputation, flags, quests, perks, status
effects, clock, level identity, respawn transform, and discovered `Corpse`
markers.

It does not persist arbitrary placed-object state. Doors, looted/refilled
containers, dead NPCs, spawned pickups, and broader object mutations still need
stable world ids before they can become exact snapshot data. Authored corpse
markers should use `Corpse.save_id`; the fallback key is only stable while the
level path, node path, and position stay stable.

### Scene Contracts

Scene wiring remains one of the easiest places to regress silently. Exported
`NodePath`s, required children, required groups, and `.tres` resource paths
should get focused contract tests whenever a bug depends on inspector wiring.
Code-only unit tests will not catch a missing child node or a missing resource
reference.

### NPC Gravity

`scripts/npc/npc.gd` is still the largest coordination point. It already delegates
to components and helpers (`NpcVoice`, `NpcTargeting`, `NpcLocomotion`, GOAP,
bark UI, audio cues, scavenge helpers), but new NPC behaviour should avoid
adding more branches to the root script. Prefer a Resource, component, or helper
with a narrow facade back into `NPC`.

Good future extractions are sections with a clear noun and contract, such as
damage visuals, stuck steering, aim computation, or melee strike handling.

### Test Noise

The GUT suite is green, but headless runs still print known orphan/resource and
dummy-renderer noise. That does not currently fail the suite, but it makes real
regressions harder to notice. Quiet tests are worth treating as engineering
polish, especially around UI lifecycle and smoke-test cleanup.

### Manual-Playtest Seams

Some in-tree behaviours are still verified mainly by playtest: physics/raycast
interactions, full GOAP action bodies, level transitions, UI lifecycle, and some
cutscene/pickup flows. That is normal for Godot, but any cheap in-tree harness
that locks a contract down should replace "playtested" over time.

## Review Rules

- Keep docs current; replace review artifacts that no longer match the code.
- When a planned seam becomes real, update README, CURRENT_ARCHITECTURE,
  AUTHORING_GUIDE, CLAUDE, and nearby code comments in the same change.
- Treat doc quality as a review finding. If code changes behavior, authoring,
  Resources, plugin workflow, save semantics, settings, inputs, or subsystem
  invariants without updating the matching docs, call that out.
- Prefer small current risk lists over broad roadmaps.
- Treat this file as a living review. If it stops matching the code, edit it or
  delete the mismatched section.
