# Cohesion refactor backlog (2026-06-22)

Roadmap for the `/loop refactor for cohesion` pass. Built from a 5-agent seam-map of the codebase.
One seam consolidated per loop pass, behavior-preserving, GUT green, one commit each. Check items off as they land.

**The shape of the problem:** `npc.gd` is a ~3,063-line god-script, and a handful of tree-walk / duck-type idioms
are copy-pasted across 5–7 files each. Sequence: pure DRY/idiom wins first (ranks 1–9, auto-safe), then god-script
splits (10–16, low-risk but structural — surface per commit), then competing-system unifications (17–22, **design
calls — never an autonomous pass**).

## Auto-safe DRY / idiom (loop does these)
- [x] **1. Unify destruction signal to `destroyed`** — Throwable `destroy` → `destroyed`; one connect + warning in SpawnOnDestroy; updated gore_gib.tscn. (commit 24c5ce0)
- [ ] **2. Central `Groups` const registry** — 25+ raw group strings; ⚠ the `player`/`Player` case split is intentional in places (capital-P = combat/identity) — document, don't blind-merge.
- [ ] **3. `NavigationUtils.is_nav_map_ready(map)`** — the `is_valid() && iteration_id != 0` guard, 3 sites (npc.gd ×2, companion_follow). Purest small win.
- [ ] **4. `HostMethodHelper.try_call_bool/int/float`** — duck-typed `has_method+call` probe; body_model_swap, fall_scream, character. Keep explicit defaults (airborne = NOT is_on_floor, default true).
- [ ] **5. `NodeFinder.find_first(node, klass)` / `find_first_by_name`** — 7 copies of depth-first find-by-type (npc, ragdoll, gun_visuals, muzzle_rig, nav_blocker). Confirm skip-self vs include-self per caller.
- [ ] **6. Consolidate mesh collection onto `TalkHelpers.collect_meshes(node, skip)`** — character/Throwable/npc twins (Throwable includes self — preserve).
- [ ] **7. Fold `nav_debug_overlay._collect_agents` into a generic `collect_by_class`** (after 6).
- [ ] **8. Callback mesh walker `walk_meshes(node, cb, skip)`** — gun_visuals ×3 + body_model_swap `_walk_meshes` (capture keep/vis in the closure).
- [ ] **9. `ComponentWarnings` helpers** — uniform parent-type / missing-signal config-warning text across ~43 sites.

## God-script splits (low-risk, structural — SURFACE per commit, `auto_safe=false`)
- [ ] **10. `NpcBarkUi` child** — ~132 lines of head-popup presentation (npc.gd:1588-1720).
- [ ] **11. `NpcPerceptionBrain` child** — ~205 lines spot/bark (npc.gd:1245-1450).
- [ ] **12. `NpcDamageVisuals` child** — ~106 lines part-flash (npc.gd:2833-2939); after rank 6.
- [ ] **13. `NpcStuckSteering` child** — anti-stuck + stranded (npc.gd:2370-2456 + consts).
- [ ] **14. `NpcAimComputer`** — pure aim/fire math (npc.gd:2581-2651).
- [ ] **15. `NpcMeleeStrike` child** — unarmed/punch/dodge (npc.gd:2107-2208); after 14.
- [ ] **16. Grow `NpcTargeting` + `NpcHeadMount`** — threat/grudge/social + head/skeleton (most entangled; last).

## Design calls — DEFER to the user, never an autonomous pass (`auto_safe=false`)
- [ ] **17. NPC loot/inventory: profile-or-fallback** — memory: profile/loot twins kept warned-only on purpose.
- [ ] **18. Single appearance path (NpcLook over inline/profile)** — needs in-editor verification.
- [ ] **19. Single `light_exposure` writer (ShadowVolume vs PlayerLightLevel)** — changes stealth numbers.
- [ ] **20. Single spawn path (SpawnDefinition/EncounterSpawner)** — hand-placed NPCs are intentionally supported.
- [ ] **21. Collapse faction/disposition trio** — HIGH risk; memory: deliberately left warned-only. Touches save data.
- [ ] **22. Unify level/XP/perk progression** — HIGH risk; touches save migration + respec semantics.
