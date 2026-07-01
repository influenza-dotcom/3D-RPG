# CYBER SUNDAY — Final Architectural Review

**Project:** Godot 4.6 FPS/RPG prototype + `addons/cybersunday_tools` in-editor authoring plugin
**Date:** 2026-06-30
**Audience:** the solo developer (expert) and future AI agents editing this codebase
**Verdict basis:** subsystem maps, cross-cutting analyses, adversarially-verified findings, and a strengths catalog

---

## 1. Executive summary

This is a **mature, disciplined prototype**, not a pile of code that happens to run. The designer-first contract (behaviour = drop-in component, numbers = `.tres` tuning group, content = authored Resources) is genuinely honored across combat, effects, economy, difficulty, reputation, and NPC AI — I found **zero hardcoded-const leaks of designer-tunable gameplay numbers in gameplay scripts**, only cosmetic chrome the architecture explicitly excludes. The hardest hazard class in the project — the `@tool` editor/runtime boundary that has repeatedly baked junk into scenes — is defended in-code at the byte level, not just in memory. The test architecture is real (203 test files, a 3-gate CI, an opt-in soak harness) and the pure/off-tree discipline is enforced end-to-end.

**The single most important thing:** the one canonical autosave (`user://gamestate.cfg`) is written with a **non-atomic in-place overwrite and no backup** (F31). A crash or power-loss mid-write corrupts the only save in a one-slot, Dark-Souls-style design — total run loss. Everything else in this review is architecture-quality work; this one is a durability defect that costs a player their entire run and is ~10 lines to fix. Fix it before adding more save surface.

The rest of the findings cluster into three honest, mostly-known costs: **god-object pressure** on `npc.gd` (3135 lines) and `GameState.gd` (813 lines) where extraction stalled after the decision layer left; **dual sources of truth** where a central registry exists but consumers route around it (`EffectFactory`, `InputManager`, the overlay-exclusion lists); and **hand-maintained editor/game mirrors** in the plugin (catalog, gizmo chain, `own_recursive`) that drift silently because the coupling is one-directional. None of these is fatal; all are managed better by naming them than by chasing them to zero.

---

## 2. As-built architecture

The layering is clean and the dependency direction is correct: **the game never depends up on the plugin** (verified by reverse grep — zero hits in runtime code), and the shared `Character` base and `GameSettings` registry sit correctly as leaves that everyone reads and that read nothing back.

```
┌──────────────────────────────────────────────────────────────────────┐
│  EDITOR-ONLY (addons/cybersunday_tools)  — all @tool, one-way dep     │
│  ┌──────────┐ ┌───────────────┐ ┌──────────────┐ ┌────────┐          │
│  │ 1 gizmo  │ │ 1 bottom panel │ │ 5 inspectors │ │ toolbar │          │
│  │ plugin   │ │ (~20 tabs)     │ │              │ │         │          │
│  └────┬─────┘ └───────┬────────┘ └──────┬───────┘ └────────┘          │
│       └── pure ops (place_ops, *_edit_ops, scan_wiring, gizmo_shapes) │
│           + core/catalog.gd (68-row hand-mirror of components)         │
└───────────────────────────────┬──────────────────────────────────────┘
                                 │ reads game types by name (never imported back)
                    ─────────────┴─────────────  boundary
┌──────────────────────────────────────────────────────────────────────┐
│  AUTOLOADS (25) — 3 kinds, deliberately mixed:                        │
│   • data leaves:  GameSettings (26 preloaded tuning .tres)            │
│   • persistence:  GameState (profile save), Settings, Reputation      │
│   • coordinators: InputManager, DialogueManager, EffectFactory, TTS   │
│   • menu screens: Inventory/Shop/Heal/Stats/Journal/… (menu-as-global)│
└───────────────────────────────┬──────────────────────────────────────┘
┌──────────────────────────────────────────────────────────────────────┐
│  ACTORS         Character (base leaf → GameSettings only)             │
│                   ├── Player  (→ ~14 code-built + @export components) │
│                   └── NPC     (→ 11 components + GOAP brain)          │
│  BRAIN          GOAP planner/executor (pure RefCounted) → npc.gd bodies│
│  COMPONENTS     scripts/components/ (LookAtInteractable ×17, Ability)  │
│  WORLD          game.tscn → GameRoot → LevelData → PlayerSpawn/Door   │
│  DATA           resources/tuning|settings|input|factions/*.tres       │
└──────────────────────────────────────────────────────────────────────┘
```

**Game↔plugin boundary.** The plugin reads game types (by class and by name) to build gizmos, palettes, and audits, but nothing in the game tree references the addon. The single crossing is `scripts/tools/validate_all.gd` — a headless CI aggregator (`extends SceneTree`, CLI-only) that reuses the plugin's pure audit statics. The game can ship with the addon disabled and nothing runtime breaks.

**Save model (intentional).** `GameState` is a **profile/checkpoint** save, not a world snapshot. It persists progression, flags, quests, reputation, clock, and active-level identity; it deliberately does *not* snapshot doors/containers/dead NPCs. This is by design and is self-documenting in the header. The contract that matters — *a restored transform must carry its level identity* — is honored for the common case via `current_level_path`.

---

## 3. What's strong

Credit where the engineering is genuinely good:

- **Designer-first is real, not aspirational.** Every tunable traced routes through `GameSettings.<group>.<field>` (difficulty, reputation, economy, physics, AI). The 3-surface rule holds far more often than it leaks; the leaks below are specific fields, not a systemic collapse.
- **`@tool` boundary hygiene is first-class.** `npc.gd._ready`/`_physics_process` hard-return on `Engine.is_editor_hint()`; `place_ops.own_recursive`'s instanced-node stop-guard (`scene_file_path != "" → return`) prevents baking preview limbs into `.tscn`; `LookAtInteractable` ships a separate `_editor_fit_hitbox` that never `add_child`s a collider at edit time; effect spawners fall back to `CACHE_MODE_IGNORE` reloads when a preloaded scene baked empty. These are the exact hazards the project has been burned by, defended deliberately.
- **The GOAP brain is the cleanest boundary in the codebase.** Pure `RefCounted` planner/executor with a documented 6-fact host surface, the sentinel-fact goal pairing (a genuinely subtle GOAP trap) solved *and* explained, replan-only-on-invalid reactivity, and library↔dropdown drift that is **test-enforced**.
- **Corrupt-save robustness is thorough.** Every scalar read degrades through type-guarded `_cfg_*` helpers; every collection is `is Array`/`is Dictionary`-gated. A hand-edited junk file degrades field-by-field instead of crashing the autoload at boot — and it's pinned by tests.
- **Inventory identity model is careful.** One generic `Item`, one canonical weapon-vs-stackable seeding rule reused everywhere, stable stack `key`s that make drop/save robust, and a well-managed `world_prop` resource cycle (`@export_file` path + lazy `load()`).
- **Combat shares one hit seam.** Both hitscan and projectile paths funnel through `DamageApplier`/`ShotResolver`, so crit rules, backstab geometry, stat/perk/difficulty scaling, and the post-mitigation kill gate are written once and unit-testable off-tree.
- **The plugin's lifecycle discipline is textbook.** Every `_enter_tree` add is paired with an exactly-reversed, guarded, freed, nulled `_exit_tree` remove — the #1 hot-reload plugin bug, handled with the correct API-variant asymmetry (two-arg toolbar remove vs single-arg panel remove).
- **The overlay-suppression gate that actually matters is centralized.** `InputManager.gameplay_suppressed()` — the one gate deciding whether a menu eats gameplay input — is a true single source of truth with 11 disciplined callers. (The *modal-exclusion* concern is the one that's scattered; see F2/F53.)

**Checked and cleared** (do not treat as problems): `RespecScreen` **is** in `gameplay_suppressed()` and in `ray_cast`'s gate — the claimed "gameplay not suppressed during respec" gap does not exist (F88 refuted). The Inventory/Stats/Reputation/Journal "diverging guards" are an **intentional Pip-Boy tab group** that switches siblings via `PlayerMenus.close_others`, not accidental drift — they cannot stack (F77's headline refuted). Held props are correctly sight-transparent but bullet-solid. The plugin→game dependency is genuinely one-way.

---

## 4. Findings

Grouped by severity. Intentional tradeoffs are marked **[intentional]** where the *decision* is sound but carries a real unmanaged cost.

### CRITICAL

**None.** No finding rises to correctness-breaking-on-normal-play. The highest-impact item is a durability risk (below), not a live crash.

### HIGH

**H1 — Non-atomic single-file autosave: a crash mid-write corrupts the only save.** `managers/GameState.gd:245`
`save_to_disk` does `cfg.save(path)` directly over `user://gamestate.cfg` — no temp-then-rename, no backup, no versioned copy. This is the sole autosave in a one-slot design, written on a broad (coalesced) surface: wallet/level/upgrade/bonfire plus every world-state flush (`set_flag`, quest transitions, `mark_corpse_discovered`). `ConfigFile.save` truncates then writes; a crash between truncate and flush leaves a partial file, which `load_from_disk` treats as "no Continue." Total run loss, no recovery.
**Fix:** write to a sibling temp path, `DirAccess.rename` over the target (atomic on same volume), keep the previous file as `.bak`. ~10 lines. Turns "lost the run" into "lost the last write." **Do this first.**

**H2 — `npc.gd` is 3135 lines / 183 functions after extraction; combat, locomotion core, hostility, death/loot, barks, and body-swap presentation all still live on the root.** `scripts/npc/npc.gd:2026,2116,2260,2441,1040,2905` **[intentional direction, unmanaged cost]**
Eleven components were extracted, but the root did not shrink to thin coordination. What remains is heavyweight: the ~85-line ranged combat dispatch `_act_alerted`, the full anti-stuck/nav-hop locomotion engine (`_move_toward`/`_update_stuck`/`_try_nav_hop`), the death/loot/corpse/XP/faction pipeline, ~19 bark constant arrays, and ~120 lines of per-part flash/outline machinery. The GOAP fire actions delegate *back* into `_act_alerted`, so the "sole decision layer" still calls giant methods on the root. Measured against the stated architecture ("`npc.gd` should SHRINK by extraction, not grow branches"), this is a real, unmanaged cost — the root did not grow branches, but it did not shrink the bodies either.
**Fix:** extract the two clearly-separable clusters next — (a) the combat firing dispatch (`_act_alerted`/`_act_unarmed`/`_punch`/dodge+charge bookkeeping) into an `NpcCombat` component the GOAP fire actions call; (b) the body-swap flash/outline machinery (`_apply_overlay_to_meshes`/`_build_part_overlay`/`_flash_part`, `:2905-3025`) into `NpcOutline`. Both are self-contained, ~350 lines, no new branches.

**H3 — `EffectFactory` is a dead central VFX registry; ~all combat/effect spawns bypass it, and `AUTHORING_GUIDE` promises "swap a slot, restyle everywhere" which is false for those effects.** `managers/EffectFactory.gd:41-67`; `docs/AUTHORING_GUIDE.md:1642`
`EffectFactory` declares 9 `@export PackedScene` slots and calls itself the "central spawner," but only `spawn_blood_particle` is ever called (3 sites). Every other effect re-preloads the *same UID* by hand and instantiates directly: `explosion_area` in `gun_fx`/`explosion`/`paint_projectile`/`explosive_barrel`; the blood-splat, dust, and bullet-hole decals across `bullet`/`character`/`projectile`/`blood_drop`/`Throwable`/`bloody_mess`. So **8 of 9 slots do nothing** — a designer who repoints `EffectFactory.explosion_area` in the inspector gets a silent no-op, directly contradicting the guide (which *is* the modding surface here). Consistency is coincidence, not enforcement.
**Nuance:** the guide's *primary* recommended workflow (line 1651: "edit the scene the slot points at") *does* propagate, because all sites share the same underlying `.tscn`. Only the "repoint a slot to a different scene" instruction is false.
**Fix:** pick one authority — either route the ~10 direct-preload sites through `EffectFactory.spawn_*`, or delete the dead slots and rewrite `AUTHORING_GUIDE.md:1642` to tell designers the true escape hatch (edit the `.tscn`).

### MEDIUM / BACKLOG

**M1 — `GameState` is an 813-line god-object mixing five responsibilities; the quest tracker is admittedly parked here by VCS friction.** `managers/GameState.gd:34-35,604-813` **[intentional co-location, real behavior mixing]**
One autoload owns: the disk codec, the manual quicksave/slot layer, the *entire live quest tracker* (start/advance/complete/fail + reward granting that reaches into the live Player inventory), the flags store, and the corpse ledger. The header openly states the quest tracker was placed here to "dodge a project.godot autoload edit." The *state* co-location (flags/quests/corpses persist as one profile blob) is spec-sanctioned and fine; the smell is mixing quest-tracker *behavior* + reward reach-ins with the ConfigFile codec and the slot-UX layer, plus ~37 files compiling against all five concerns.
**Fix (deferred):** treat the VCS admission as the trigger to make the autoload edit. Extract a `QuestTracker` autoload that `GameState` serializes via a `capture()`/`restore()` handshake — the seam `Reputation` already uses. Leaves quest logic unit-testable without the save layer.

**M2 — Components reach through `host` into ~37 "private" members of `npc.gd`/`Character`; the facade is partly a fiction.** `scripts/npc/weapon_stance.gd`, `npc_targeting.gd:37,45`, `npc_voice.gd:59` **[intentional cycle-break, unmanaged cost]**
Sibling components read/write ~37 leading-underscore "private" members and private methods across two class layers. **Important nuance:** 6 of 11 components declare `var host: NPC` (typed), so a rename of e.g. `_weapon` *would* raise a compile-time error there — the "no compile-time signal" hazard only applies to the 5 `Node`-typed components (the cycle-break). This maximizes the memory-noted "deleted a dead private → shipped a crash" failure mode for that subset.
**Fix (managed cost, not chase-to-zero):** add `scripts/npc/README.md` (currently absent, though `goap/` has one) tabling each component → the host members it depends on; add narrow public setters for the highest-churn writes (`set_last_attacker`, `drive_velocity`). Do **not** rename the 37 casually — grep `npc/` first.

**M3 — Level-identity fallback re-applies the saved transform into the WRONG level.** `scripts/world/game_root.gd:65-72`; `scripts/player/player.gd:493-495`
`resolve_boot_level` falls back to the *exported* level when a loaded game's saved path is blank/unresolvable/scene-less, but the Player unconditionally re-applies `respawn_position` on any loaded game with no check that the booted level is the one the respawn belongs to. So a renamed/deleted `LevelData.tres` (the exact drift this project expects during authoring) boots the export level and teleports the player to coordinates authored for a different level — out of bounds, inside geometry, or mid-air. `respawn_position` and `current_level_path` are two decoupled fields with an unenforced invariant. Degrades gracefully (recoverable bad position, not a crash), and requires a live save whose `.tres` is *then* deleted — hence medium.
**Fix:** when `resolve_boot_level` falls back to the export for a *loaded* game, treat the respawn as invalid — force placement at the export level's `PlayerSpawn`, or gate the `player.gd:493` restore on the boot level matching the saved path. Add a test for the missing-`.tres` case.

**M4 — Action names have three authorities that already disagree; `InputManager` is stale and mostly bypassed.** `managers/InputManager.gd:3-6`; `scripts/player/player.gd:1339,1390` **[partly intentional]**
`InputManager` claims action strings "live in one place," but `Walk` and `NightVision` exist in `ActionCatalog.tres` + `project.godot` with **no** `InputManager` var, and the hot loop polls `Input` directly with literals (`get_vector("left","right",…)`, `&"Walk"`, `crouch.gd`, `grapple_hook.gd`, `jump_buffer.gd`). Nothing malfunctions *today* — the risk is a future rename silently missing the literals the abstraction was built to protect.
**Fix:** promote `ActionCatalog.tres` (already test-drift-checkable and driving the Controls UI) to canonical; add a test asserting `InputManager` vars == `ActionCatalog.rebindable_actions()`; add the missing `Walk`/`NightVision` rows now; correct the `InputManager` header so it stops over-promising.

**M5 — "Which overlays are open" is a hand-maintained list duplicated across ~11 sites that have drifted.** `managers/InputManager.gd:94`; each screen's `open()`; `ray_cast.gd:56` **[real maintenance cost, refuted correctness claim]**
The gate that matters (`gameplay_suppressed()`) is centralized and complete. The *modal-exclusion* guards are not: ~10 screens re-list a hand-ordered subset inline, `ray_cast` is a third partial copy, and the subsets diverge. The alleged "two mutually-exclusive menus co-open" bug is largely **refuted** (the Pip-Boy tab group switches by design). The one genuine residual: the pausing modals (shop/heal/levelup) omit `QuestJournal` from their guards while `QuestJournal.open()` blocks *them* — a one-directional asymmetry, hard to hit because those flows gate on `DialogueManager.is_active()`. Plus `ray_cast` lets the interact key fire while player menus are open (minor leakage).
**Fix:** one small `ModalRegistry` (or extend `gameplay_suppressed` with an `except` param) exposing `any_modal_open(exclude)` / `any_pausing_open()`; route every guard + `ray_cast` through it.

**M6 — "The human player (not a companion)" is resolved by a copy-pasted group-scan reimplemented ~11 times across ~9 subsystems, each also coupling that subsystem to the `NPC` class.** `scripts/world/groups.gd:8-12`; `npc.gd:1660`; three UI screens; `dialogue_view.gd`; components
`groups.gd` documents the rule as *prose* but ships no accessor. So `get_nodes_in_group(&"Player") + not (p is NPC)` is re-implemented in `npc.gd`, `dialogue_view`, `stats/inventory/options` screens, and `music_director`/`prop_follow`/`reward_stinger`/`Throwable`. Two compounding costs: UI screens now import the enemy AI class purely to say "not an NPC," and the rule lives only as convention — the exact identity-by-string-scan class that produced the memory-noted lowercase-`"player"` silent kill-XP bug. `dialogue_manager.gd` even uses a *different* idiom (`is Player`), so it's not even consistent.
**Fix:** add `Groups.human_player(tree) -> Node` (one non-NPC filter, optionally cached); route all ~11 sites through it. Removes the incidental `NPC`-class dependency from UI/dialogue and gives the invariant one testable home. ~3-line extraction.

**M7 — NPC content twin (`NpcData`) requires three hand-synced ~55-entry lists; the drift test covers only one direction.** `scripts/npc/npc.gd:475-486,518+`; `npc_data.gd:24-191` **[intentional twin, partial enforcement]**
`NpcData` (~55 `@export`s), `_stamp_profile_full` (~55 assignments), and `PROFILE_STAMPED_FIELDS` (55 names, used by the additive-merge snapshot/restore) must stay lockstep. The test only asserts every `PROFILE_STAMPED_FIELDS` name resolves — not the reverse. A field added to `NpcData` + `_stamp_profile_full` but forgotten in the array compiles and passes the full-clobber path, yet silently breaks *only* the additive-merge path (an inline tweak gets clobbered with no signal).
**Fix:** extend the test to assert set-equality in the unchecked direction; ideally drive `_stamp_profile_full` from `PROFILE_STAMPED_FIELDS` via `get()/set()` so there's one list, not three.

**M8 — NPC hostility is authorable from four overlapping surfaces with precedence only in comments.** `scripts/npc/npc_data.gd:52-60`; `npc.gd:463-471` **[intentional FNV model, missing @tool warning]**
`faction_id`, the `faction` slot, standalone `disposition`, and `disposition_overrides_faction` partly shadow each other; `_resolve_faction` silently overwrites the authored slot when `faction_id` is set, with no warning. Unlike the faction internal-id case, there's no `@tool` warning when two are set contradictorily.
**Fix:** add a `_get_configuration_warnings` when `faction_id` AND `faction` are both set, or when `disposition_overrides_faction` is set with a null faction; document precedence once in the authoring guide.

**M9 — Blast damage is a single global const while blast force/radius are per-weapon.** `scripts/components/explosion_area.gd:129`
`WeaponData` authors `max_explosion_force` + `explosion_radius` per weapon, but blast *damage* reads a lone `GameSettings.physics_damage.explosion_damage` for every explosion — a rocket, grenade, and barrel all deal identical blast damage. You can author a big-radius weak-force rocket but not a hard-hitting one. A specific leak of the "per-weapon tunable → content Resource" rule.
**Fix:** add `explosion_damage` to `WeaponData`, forward it via `ProjectileSpawner`, keep the global as the fallback for environmental blasts.

**M10 — `EffectFactory` doc-drift** — see H3 (the `AUTHORING_GUIDE:1642` "repoint a slot" promise is the doc half of that finding).

**M11 — Hitscan and projectile paths re-implement the same hit orchestration in parallel, with load-bearing asymmetries.** `scripts/projectiles/projectile.gd:93-194`; `damage_trace.run_pellet`
The core math is shared, but the surrounding sequence (mitigation re-read, status-on-hit, scaling, collateral bounty, knockback, impact SFX) is written twice and kept in sync by ~8 "mirrors damage_trace" comments. Real divergences already exist: projectiles pass no `hit_pos` (no directional/limb damage on a Character), hitstop fires only on the hitscan path, and the collateral kill-latches are separate.
**Fix:** extract the post-`take_damage` sequence into a shared static both callers invoke with a small param struct, making the intentional asymmetries (`hit_pos`, hitstop) explicit parameters rather than silent omissions.

**M12 — `Engine.time_scale` is co-owned by four systems, coordinated only by convention.** `freeze_frame.gd:22`; `bullet_time.gd`; `player.gd` death cinematic; `GameState` quickload **[known, tested tradeoff]**
Four writers of one global; recovery hardcodes `1.0` rather than restoring the underlying scale, so a `FreezeFrame` during bullet-time yanks the world to full speed mid-slowmo. Tested and bounded, but every new time-scale effect must re-learn the informal protocol.
**Fix (optional):** a small `TimeScale` arbiter autoload that stacks/prioritizes requests (freeze > death > bullet-time) and restores the correct underlying scale.

**M13 — `_physics_process` still inlines the player's most important behaviour (movement/jump/edge-friction/footsteps) that the extraction left behind.** `scripts/player/player.gd:1325-1516`
Despite an otherwise-strong component split, the ~190-line loop still owns the target-speed multiplier stack, ground/air smoothing, Quake edge-friction, bhop, landing→camera/gun/shake/sfx/dust/fall-damage, and footstep cadence — mixing movement math with audio/camera/VFX side effects. The one big slice not extracted like `Slide`/`WallClimb` were.
**Fix:** extract a `GroundMovement` component (speed stack + smoothing + edge friction) and a `Landing`/footstep component, mirroring the idiom already in use.

**M14 — DialogueManager is a de-facto transaction hub reaching down into 8 subsystems, held together by duck-typing to hide a compile cycle.** `scripts/dialogue/dialogue_manager.gd:180-398` **[reasonable cycle-break, no compile-time check]**
Beyond running conversations it opens Shop/Heal/LevelUp/Loot screens, rests at bonfires, recruits companions, writes flags/quests/rewards, and grants reputation — scanning speaker children via `has_method()` specifically to avoid a `Merchant↔ShopScreen↔DialogueManager` compile cycle. Renaming `Healer.heal_cost` silently drops the "Heal" option with no error.
**Fix:** move consequence-application + sub-menu routing behind a small typed `SpeakerServices`/`Transactable` interface so the contracts are compile-checked; at minimum add a per-method-pair contract test.

**M15 — A chained quest with a FLAG objective on the flag that triggered the chain won't auto-advance.** `managers/GameState.gd:563-568,631-632,648-649` *(unverified lead)*
`set_flag(F)` sets the flag, runs the objective hook, and can auto-complete → chain the next quest — but that quest's FLAG objective on `F` stays at 0 because `F`'s hook already fired. Flag objectives are edge-triggered, not level-triggered.
**Fix:** on `start_quest`, back-fill any FLAG objective whose target flag is already set. Add the chain test.

**M16 — No save schema/version field, so future migrations have only heuristics.** `managers/GameState.gd:210` *(unverified lead)*
Back-compat is inferred structurally (section presence). Fine for additive changes; any change to an existing key's *meaning* silently mis-reads old files.
**Fix:** stamp `[meta] version` on write, read it (default 0) on load. Costs nothing today, makes the first breaking change survivable.

**Lighter backlog (unverified minor leads, present as such):** unplaced grid stacks are invisible/unrecoverable in the loot UI (F24); two autoloads install tree-global `node_added` listeners that fire for every spawned node (F5/F57 — acceptable at scale, don't add a third); ~11 menu screens duplicate open/close/mouse-restore boilerplate with no shared base (F7); the `func_godot` trenchboom level is a syntactically-valid but unvalidated boot target with no `PlayerSpawn`/navmesh — currently an unreachable orphan, so low (F59); `LevelDoor` runtime swap `free()`s the old level synchronously mid-signal (F62 — latent, untriggered because no door is placed in content); the whole multi-level flow is built + unit-tested but wired into zero content (F61); a stray `stupidbody` instance rides on top of every level in `game.tscn` (F63); quest/TALK objective completes on dialogue-box-open regardless of outcome (F38 — by design, document it); quest persistence keys on `resource_path` so a moved `.tres` drops in-flight progress (F40 — matches the profile contract, surface load-skips as a toast).

---

## 5. The plugin (CYBER SUNDAY Tools)

The plugin is the strongest-engineered *subsystem* in the repository on lifecycle and testability, and its weaknesses are all one shape: **hand-maintained mirrors of the game that drift silently because the coupling is one-directional.**

**Lifecycle / hot-reload safety — excellent.** `plugin.gd` pairs every one of the 8 `_enter_tree` adds (gizmo, bottom panel, 5 inspectors, toolbar) with an exactly-reversed, guarded, freed, nulled `_exit_tree` remove, using the correct API variant for each. The header names the hot-reload leak as the #1 plugin bug. The bottom-panel-not-docks decision is deliberate and documented (right docks force editor min-height and restore saved sizes on relaunch, clipping short/HiDPI displays).

**`@tool` boundary — first-class.** `place_ops.own_recursive`'s instanced-node stop-guard is the load-bearing defense that prevents baking `BodyModelSwap`'s unowned `@tool` preview limbs into saved `.tscn` — the exact shipped regression from memory, now pinned by `test_devtools_placer`. Pure logic (place ops, gizmo line-math, `scan_wiring` resolvers, catalog paths) is extracted from `EditorInterface`/tree so GUT pins it headlessly.

**Read-only vs write contract — mostly honored, one asymmetry.** Inspectors are read-only and re-check type in both `_can_handle` and `_parse_begin`. The audit batch-fixer is a model write-with-preview-confirm-report flow (`ConfirmationDialog` listing every change, `fix_ops` admits only idempotent KNOWN_KINDS, reports Changed/Skipped). The **content editors** (Dialogue/Quest/Loot) are the asymmetry: they mutate the loaded Resource on every keystroke and `Save` does a bare `ResourceSaver.save` with no diff/confirm and no `EditorUndoRedoManager` — so a mis-save is unrecoverable except via VCS, while the audit tab treats the same class of write with full ceremony (F76/F87). Defensible for a live form editor; at minimum route these saves through undo/redo.

**Plugin↔game coupling — correct direction, verified.** Zero game references to the addon. Game ships fine with the plugin disabled. The one crossing (`validate_all.gd`) is CLI-only; the mild layering note (F82) is that the *pure* validators it reuses live inside the editor addon rather than in `scripts/tools/`, so the CI gate technically depends on the addon.

**Catalog-as-source-of-truth — the real drift risk.** `core/catalog.gd` is a hand-authored 68-row mirror the palette/placers read, but:
- **Coverage isn't tested.** Real drop-ins are absent — `Readable`, `SwitchLever`, `Claimable`, `FallImmunity` (all the *same idioms* as cataloged siblings) — so they're invisible to a designer browsing the palette, defeating the catalog's whole purpose. `test_devtools_core` only asserts existing rows' paths resolve, never that the catalog *covers* the droppable set (F68/F90/F95).
- **Field descriptions aren't validated.** `key_exports`/`extends`/`description` hand-mirror the scripts and are correct *today*, but nothing checks a listed export exists — renaming `CanPickUp.loot_table` leaves the palette advertising a ghost field with a green suite (F72/F96).
- **The gizmo `is Type` chain is a second registry** (`_has_gizmo`/`_redraw`) that must be hand-kept in sync, uncovered by any test (F69/F100) — low blast radius (visualization only).
- **`scan_wiring` omits `Readable.set_flag_on_read`** from `FLAG_WRITE_FIELDS`, so a flag written *only* by a Readable and read by a dialogue gate is mis-flagged as a dead gate — a false-positive from the one tool whose job is catching wiring typos (F97). Add the field; ideally derive the vocabulary by scanning.

**Duplicated `own_recursive` — the sharpest plugin finding.** The safety-critical routine with a documented data-corruption history exists in **two copies**: the tested static `PlaceOps.own_recursive`, and an untested instance twin `item_placer_dock._own_recursive` that is the copy actually wired into the item-placer's undo/redo write path (F75/F83/F98/F104). Both carry the critical `scene_file_path != ""` stop-guard today (so no *live* corruption), but the twin lacks the null top-guard and has no test — a fix to the tested copy won't reach the live one. **Fix: delete the twin, route through `PlaceOps.own_recursive`** (as `scene_placer` already does). Low severity today, but this is the exact routine that corrupted a scene once; two copies is a re-divergence trap.

**Eager tab construction (F70):** all 20 docks are built in `cyber_panel._init` and several do disk-touching refreshes at construction, even though `content_browser` demonstrates the correct lazy `visibility_changed` + first-reveal latch. The good pattern exists but is applied to one dock — adopt it uniformly for disk-touching tabs.

---

## 6. Cross-cutting themes

Five patterns recur across subsystems. Naming them is worth more than any single fix:

1. **The `@tool` editor/runtime boundary is the project's defining hazard — and it's genuinely well-defended.** The empty-reimport and owned-preview-baked classes each have load-bearing, byte-accurate defenses. The residual gaps are *consistency* of the defense, not its existence: the editor early-out is re-paid per `LookAtInteractable` subclass rather than inherited from the base (F85 — a future subclass author who forgets the guard spawns an unowned collider), and three edit-time instancing sites guard `null` but not the count-0 empty-reimport transient (F84). Hoist the guard into the base; add one shared edit-time-safe instantiate helper.

2. **God-object pressure where extraction stalled.** `npc.gd` (3135) and `GameState.gd` (813) both had their *decision/orchestration* layer extracted cleanly but kept the heavy bodies. The direction is right and documented; the cost is that the biggest, highest-churn, least-tested code sits on the coordinators. This is the #1 place to spend the next refactor.

3. **Dual sources of truth where a registry exists but consumers route around it.** `EffectFactory` (bypassed), `InputManager` action names (bypassed + stale), the modal-exclusion lists (duplicated), `Groups.human_player` (prose, no accessor). The fix is always the same shape: make the registry the *only* path, or delete it and fix the doc — never leave a documented single-source that 3-of-11 consumers obey.

4. **Hand-maintained editor↔game mirrors that drift silently.** The catalog, the gizmo chain, `scan_wiring`'s field vocabulary, the `NpcData` triple-list, the Dialogue-editor field map. Every one is correct *today* and rots on the *next* game change with zero test signal. The uniform fix is cheap: a drift test that fails when the mirror and the source diverge, exactly as `GoapLibrary`↔dropdowns and `PROFILE_STAMPED_FIELDS`↔properties already demonstrate. This is a solved problem in this codebase; it just isn't applied everywhere.

5. **Untested behaviour bodies below well-tested decision seams.** GOAP dispatch, save resolvers, and plugin ops are pinned; the combat/locomotion/flee bodies they dispatch into, and the field write-back projections the plugin saves, are playtest-only (F14/F101/F102/F103/F105). This is a **documented, deliberate** tradeoff (byte-for-byte frame ordering; "don't run NPC `_ready` in a unit test"), managed by convention — but it means a combat regression is catchable only by a human playing. A tiny in-tree combat smoke harness (one armed NPC + a dummy target on `NavSandbox`, assert "shots land / NPC converges / no crash") would close the widest coverage-vs-blast-radius gap in the project.

---

## 7. Prioritized recommendations

Sequenced highest-leverage first. Effort: **S** ≈ <½ day, **M** ≈ 1-2 days, **L** ≈ 3+ days.

1. **Atomic autosave: temp-write → rename, keep one `.bak`.** **(S)** — retires H1 total-run-loss. *Do before adding any save surface.*
2. **Add a save `[meta] version` stamp.** **(S)** — retires M16; makes the first breaking migration survivable. Bundle with #1.
3. **Fix the level-identity fallback: force spawn-placement (or refuse Continue) when the saved `.tres` is unresolvable, and add the missing-`.tres` test.** **(S)** — retires M3 + F101 transform-orphan.
4. **Consolidate `EffectFactory` OR delete its dead slots + fix `AUTHORING_GUIDE:1642`.** **(M)** — retires H3 designer-first violation and doc-as-contract drift.
5. **Delete `item_placer_dock._own_recursive`; route through the tested `PlaceOps.own_recursive`.** **(S)** — retires the corruption-prone routine's re-divergence trap (F75/F98/F104).
6. **Add plugin drift tests: catalog coverage of the droppable set + `key_exports`/`extends` validation; gizmo type-chain; `scan_wiring` field vocabulary (`OBJ_TYPE_FLAG == QuestObjective.Type.FLAG`, add `set_flag_on_read`).** **(M)** — retires F68/F72/F74/F90/F95/F96/F97; converts silent editor drift into red tests. Highest-leverage plugin work.
7. **Add `Groups.human_player(tree)` and route the ~11 scan sites through it.** **(S)** — retires M6 duplication + the incidental UI→`NPC`-class coupling + the memory-noted identity-bug class.
8. **Introduce one `ModalRegistry` (or `gameplay_suppressed(except)`); route every `open()` guard + `ray_cast` through it.** **(M)** — retires M5 + F54 + the Journal-vs-pausing-modal asymmetry.
9. **Extract `NpcCombat` (firing dispatch) and move body-swap flash/outline into `NpcOutline`; add `scripts/npc/README.md` tabling host reads.** **(L)** — retires H2 root bulk + M2 leaky-facade documentation. The doc alone (S) is worth doing immediately.
10. **Stand up a tiny in-tree combat smoke harness (sibling to `soak_harness`).** **(M)** — retires the widest test blind spot (F14/F102).
11. **Promote `ActionCatalog.tres` to the input authority; add the `InputManager`==catalog drift test + `Walk`/`NightVision` rows; fix the header.** **(S)** — retires M4 rename hazard.
12. **Hoist the `@tool` editor early-out into `LookAtInteractable._ready`; add one shared edit-time-safe instantiate helper.** **(S)** — retires F84/F85 (unowned-collider / empty-reimport by-convention gap).
13. **Backlog, as budget allows:** extract `GroundMovement`/`Landing` from `player._physics_process` (M13, M); per-weapon blast damage (M9, S); `NpcData` reverse-direction drift test (M7, S); hostility `@tool` warning (M8, S); shared post-`take_damage` static for the two hit paths (M11, M); `TimeScale` arbiter (M12, M); `QuestTracker` autoload split (M1, L — trigger on the next `project.godot` edit); route plugin content-editor saves through undo/redo (F76/F87, S).

---

## 8. What was verified vs not

The **Findings** and **Plugin** sections lean on adversarially-verified analysis: each High/Medium finding here was traced to specific file:line evidence, and claims that failed the trace were **refuted and excluded** (notably the "gameplay not suppressed during respec" and "Stats/Inventory can co-open" claims — both disproven and noted as *cleared* in §3, not presented as problems). Where verification **downgraded** a claim (e.g. H2/H3 stayed high; several "high" claims fell to medium once the intended tradeoff or the mitigating code path was found), I carried the *corrected* severity and the nuance, not the original over-claim. The **Strengths** section is drawn from the same traced evidence and should be trusted at the same level.

The **lighter backlog** items (F5, F7, F15–F18, F24–F29, F32–F40, F55–F73, and the rest of the minor set) were **not individually re-verified** — they are cross-cutting-analysis leads, presented as such, and should be treated as "trace before fixing," per this project's own standing rule that review findings are leads until confirmed against runtime. Their *direction* is reliable; their exact severity and line numbers deserve a confirming glance before you act on them.

Confidence: **high** on §2 (as-built map), §3 (strengths), and the High + verified-Medium findings; **medium** on the unverified backlog. The one item to act on with no further verification is the atomic-save fix — it is mechanically confirmed and the downside of the current code is catastrophic and unambiguous.