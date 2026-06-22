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
- [x] **3. `NavigationUtils.is_nav_map_ready(map)`** — the `is_valid() && iteration_id != 0` guard, 3 sites (npc.gd ×2, companion_follow). Purest small win.
- [x] **4. `HostMethodHelper.try_call_bool`** — duck-typed `has_method+call` probe; body_model_swap, fall_scream, character. Keep explicit defaults (airborne = NOT is_on_floor, default true).
- [x] **5. `NodeFinder.find_first_of_class` / `find_first_by_name`** — folded the 2 `_find_skeleton` (include-self by-class) + 3 `_find_muzzle_marker` + `_find_named_marker` (children-only by-name) into one util; the finders became one-line delegates. (`nav_blocker._find_shape` left — single copy with a `.shape != null` predicate.)
- [x] **6. Consolidate mesh collection onto `TalkHelpers.collect_meshes(node, skip, include_root)`** — character/Throwable/npc twins (Throwable includes self — preserve).
- [x] **7. `NodeFinder.collect_by_class`** — folded `nav_debug_overlay._collect_agents` into the generic collector.
- [~] **8. Callback mesh walker — SKIPPED (not a clean fit).** The 4 walkers are heterogeneous: `_apply_rim_recursive` returns a count, `_apply_outline_skipping` prunes subtrees by name-hint substrings, `_disable_shadows_recursive` sets two props, `body_model_swap._walk_meshes` skips a keep-node. A unified walker (predicate + callback + accumulator) adds indirection, not cohesion — left as distinct, legitimately-different walks.
- [~] **9. `ComponentWarnings` helpers — DEFERRED (low value).** ~43 config-warning strings; standardizing the wording is subjective, high-churn, editor-only. Optional; not worth an autonomous mass-edit. Do opportunistically if/when those files are touched.

## God-script splits (low-risk, structural — SURFACE per commit, `auto_safe=false`)
- [x] **10. `NpcBarkUi` child** — moved the bark bubble + head-icon build/fade/free + popup consts + `_bubble_bg_texture` (~130 lines) to a Node3D child; npc.gd keeps thin facades (`_popup_text`/`_popup_icon`/`_clear_bark_bubble`) so call sites incl. cross-NPC `saved._popup_icon` are unchanged.
- [~] **11. `NpcPerceptionBrain` — SKIPPED (already componentized).** The bark/perception system already lives in `NpcVoice` (+ `NpcAudioCues` + `NpcBarkUi`); `npc.gd`'s `_on_spotted` and `_try_*_bark`/`_cry_wounded`/`greet` are already thin facades delegating to `_voice`. A new brain layer would add indirection, not cohesion. The audit over-counted (the ~205 lines are mostly already-split facades).
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
