# NPC decomposition — running status

Tracks the ongoing effort to break `scripts/npc/npc.gd` (the AI god object) into drop-in components. Updated by the
self-paced decomposition loop (workflows draft + adversarially verify each slice). See also the cross-session memory
note `npc-decomposition-plan`.

## Headline finding (2026-07-04, 13-agent re-map)

`npc.gd` is **~85% already decomposed** (2793 lines, down from 3135). The remaining bulk is NOT liftable behaviour —
it's dispatch-by-name Character/Weapon virtual **shells** that must stay, ~40 intentional cross-component **facades**,
two irreducible **coordination monoliths** (`_physics_process` tick hub + `apply_velocity`), and ONE genuine
un-extracted monolith: the **movement core** (Locomotor Phase B). Full roadmap + verdicts were produced by the re-map.

## Backlog / status

| # | Slice | Risk class | Status |
|---|---|---|---|
| ✅ | **CrippleCallout** — limb-cripple toast + "My arm!" bark → portable Type-1 drop-in | SAFE-NOW | **SHIPPED** to live files (`scripts/components/cripple_callout.gd` + test + docs). Cache-free wiring; static + 3-lens verified. Verify after next editor reimport. |
| 📦 | **Locomotor Phase B** — nav brain (`_move_toward`/`_update_stuck`/nav-hop/off-mesh) → `locomotor.gd` DRIVEN mode | PLAYTEST-GATED | **STAGED** (not applied). Ready-to-apply patch + 4-lens review + corrections + playtest checklist → [`locomotor_phase_b_migration.md`](locomotor_phase_b_migration.md). Frame-order + caller-signatures SOUND; one real bool bug fixed in the corrections. Apply + playtest in an editor-closed session. |
| 📦 | **NpcHeadAnchor** — head/skeleton resolve + swapped-head + `_head_position` → drop-in | EDITOR-LOCK + PLAYTEST | **STAGED but DEFER (marginal, ~18-22 lines).** Patch + 3-lens review + mandatory corrections → [`npc_head_anchor_migration.md`](npc_head_anchor_migration.md). Cache-free wiring clean; one HIGH build-ordering regression fixed in the corrections. All 3 reviewers: defer, don't drop. |

## Safe-now batch: ground-truthed EMPTY (2026-07-05)

A workflow drafted + self-verified every candidate for a GUT-coverable, editor-open-safe extraction into an existing
cached module. **Result: 0 net-positive lines.** Bark const pools are pinned as `NPC.<CONST>` anchors in 6 test files
(deliberately kept on NPC — NpcVoice's docstring says so). `_treats_as_enemy` nets ~12 raw lines but adds a
cross-component hop reaching back for `is_hostile_to`/`_protectee` (net-negative value). `_on_spotted` (signal handler,
no pure part), `_play_damage_thud`/`is_off_guard` (Character overrides), `_emit_gunfire_noise`/`_cry_wounded`/
`break_and_flee` (already thin facades over NoisePulser/NpcVoice) — all already at final shape. **There is no safe-now
extraction left to apply with the editor open.** (Third independent confirmation of the floor.)

## Full-teardown feasibility (2026-07-05)

Asked "can npc.gd be pushed to ~1000-1400 lines by moving more clusters into host-coupled modules?" A 12-agent
plan-only workflow (skeptic-verified) answered decisively: **no.** Honest floor is **~1550-1750**; applying every
feasible extraction lands **~2650-2730** (~all of it the two already-staged playtest patches). The "safe-now" batch
nets **≈0-5 lines** — the movable safe-now clusters are already thin facades over existing child modules, and the
cross-project public API (52 caller files) forces the facades to stay. The 2795 lines are the `@export` authoring
surface + facades + GOAP-contract helpers + the tick coordinator + protected comments — structural, not god-object
logic. Full analysis + corrected roadmap: [`npc_teardown_analysis.md`](npc_teardown_analysis.md).

## Loop outcome (2026-07-04)

The self-paced decomposition loop is **complete — the extractable backlog is exhausted.** One slice shipped
(CrippleCallout); the two remaining real targets are staged as reviewed, ready-to-apply patches (they can't be applied
this session — playtest + editor-lock gated). Everything else in npc.gd is dispatch-by-name shells, intentional
facades, or the irreducible coordination seam (see below) — not extractable.

**Recommended next session (editor closed + game runnable):** apply **Locomotor Phase B first** (the real de-bloat,
~45 lines + the flagship "make it a drag-drop mover" win), playtest movement, then optionally batch **NpcHeadAnchor**
into the same reimport + playtest cycle (it's marginal on its own — only worth it when the editor is already closed
and a playtest is already scheduled). Both docs carry their full patch + corrections + a playtest checklist.

## What is DELIBERATELY not being extracted (stays on the root)

- Dispatch-by-name virtual shells: `apply_velocity`, `_on_damaged_by`/`_on_damaged`/`_on_died`, `gore`,
  `_on_limb_crippled`, `_apply_overlay_to_meshes`/`_flash_damage`/`flash_red`, `get_aim_*`.
- Cross-component facades (bark triggers, `_drop_loot`/`_act_alerted`/`_loudest_noise`, `is_hostile`, …).
- The `_physics_process` tick hub + `apply_velocity` (the coordination seam; can't invert host↔component control).
- `_pick_wander_point` (pure math, off-tree test-pinned).

## Guardrails this loop honours

- Playtest-gated / movement changes are **staged as patches, never applied to live `npc.gd` unattended**.
- Only genuinely safe-now slices (GUT-coverable, no playtest, no editor-lock) are applied live.
- Every slice is adversarially verified (equivalence / frame-order / caller-signatures / test-cache) before staging.
