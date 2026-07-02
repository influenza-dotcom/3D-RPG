# CYBER SUNDAY — Master Remediation Plan

Fixing every finding from the 2026-06-30 architectural review of the Godot 4.6 FPS/RPG + CYBER SUNDAY authoring plugin.

---

## 1. Overview

This plan sequences the 37 verified fix specs into **nine dependency-ordered waves**, do-first to do-last. Each wave is a coherent, shippable batch; front-loaded waves are the small, safe, high-impact durability + drift fixes, and the risky extractions (NpcCombat, NpcOutline, player movement, hit-path unify, QuestTracker) are quarantined into their own late waves with test-first de-risking.

**Finding accounting (37 items):**

- **Confirmed, full work required:** H1, H1b, H2, H2b, H3, M1, M3, M6, M9, M11, M13, M15, PL1–PL6, T1, XC1, B-F24, B-F19, B-F62, B-F63, B-F7 — plus doc/test-only confirmations (B-F38, B-F40, B-F59, B-F61, B-F5/F57).
- **Partial (real residual is narrower than the headline; some of the finding is already shipped):** H2 (NpcCombat cluster only — see the H2 scope note below), H2b (NpcOutline component already exists; only the per-part cluster moves), M2 (doc half real, `drive_velocity` setter refuted), M4 (Walk/NightVision rows already shipped), M5 (co-open bug refuted; Journal asymmetry + ray_cast leak real), M7 (lists in sync; add reverse drift test only), M8 (2 of 3 items already shipped), M14 (typed-interface remedy refuted; drift test instead), B-F7 (tab group already shared; 7 modals real), B-F5/F57 (perf already handled; only the "no third listener" invariant is missing), B-F61 (GameRoot seam already live; only door-travel dormant), XC1 (both halves are consistency gaps, no live bug).
- **Refuted sub-claims excluded from the work (documented, not built):** `M2.drive_velocity` setter, `M5` co-open bug, `M14` typed `SpeakerServices` interface, `M8` `_get_configuration_warnings` on a Resource (impossible — Node-only), `B-F88` respec-suppression gap (already cleared in review §3), `B-F77` tab-group co-open (already cleared).

### H2 scope note (partial retirement — read before marking H2 "done")

The review's H2 headline names *"combat, locomotion core, hostility, death/loot, barks, body-swap all still on root."* This plan **only** extracts the **combat firing-dispatch cluster** (H2, WAVE 5) and the **per-part body-swap flash** (H2b, WAVE 6). The following god-object bulk is **deliberately deferred, not covered**, and H2 must NOT be recorded as fully resolving the root-file bloat:

- **Locomotion core** (`_move_toward`/`_update_stuck`/`_try_nav_hop`) — test-pinned and shared with pursuit; extracting it now would churn the GOAP nav path. Deferred.
- **Death / loot / corpse / XP / faction pipeline** — large, save-adjacent, no verified fix spec in the review. Deferred.
- **Barks** — already partially componentized (`npc_bark_ui`); no residual specced. Deferred.

These three are logged as **open backlog** (same tier as M12), to be specced in a follow-up review pass.

### Checked, no action (refuted / already-fixed / design-decision, no code change)

| Item | Why no work |
|---|---|
| F88 respec not suppressed | **Refuted** in review §3 — RespecScreen *is* in `gameplay_suppressed()` and the ray_cast gate. |
| F77 Stats/Inventory co-open | **Refuted** — intentional Pip-Boy tab group via `PlayerMenus.close_others`. |
| M2 `drive_velocity` setter | **Refuted** — no Node-typed component writes `host.velocity`; `_move_toward` is already the drive seam. |
| M14 typed `SpeakerServices`/`Transactable` | **Refuted as the fix** — would recreate the Merchant↔ShopScreen↔DialogueManager cycle the duck-typing exists to break. Drift test instead (M14 work). |
| M8 "add `_get_configuration_warnings` to NpcData" | **Not implementable** — Node-only method; the profile equivalent (`conflicts()` static) is what M8 extends. |
| B-F38 TALK on box-open | **By design** — doc-only (B-F38 work item; no runtime change). |
| M12 `TimeScale` arbiter | **No verified fix spec** (review labels the fix "optional"). Deferred to open backlog — see the M12 sign-off note below. |

> **M12 sign-off (task-owner attention required).** M12 was one of the original 37 ids, but the review provided **no verified fix spec** and explicitly marked its fix *optional*. It is the **sole** id in the 37-item set left as pure backlog with zero deliverable in this plan. This is a scoping decision, not a drop: **the task owner should explicitly confirm M12-out-of-scope** before this plan is considered complete. If M12 must ship, it needs a spec-first mini-review (define the arbiter's authority order over `Engine.time_scale` writers) before it can be waved.
>
> **M10** (EffectFactory doc drift) is folded into **H3** — the only other roadmap entry without a standalone build, subsumed rather than deferred.

### Wave model

Waves are ordered by (a) hard dependency, (b) blast-radius isolation, and (c) leverage. Only **M1 (QuestTracker autoload split)** has a true ordering dependency on an autoload registration; everything else is independent, so waves 1–3 are internally parallelizable. Extractions that touch the same hot file (`npc.gd`) are serialized into adjacent waves to avoid merge churn. **T1 (combat smoke harness) is pulled forward to WAVE 4** so the standing combat gate exists *before* the H2 NpcCombat extraction it is meant to de-risk (correcting the draft, which landed T1 two waves late).

---

## 2. Waves

### WAVE 1 — Save durability + level-identity (do first; retires the only run-loss risk)

*Theme: make the one-slot save crash-safe and stop the respawn teleport-into-wrong-level bug. All S, all independent, all pure plumbing.*

| id | title | eff | files | tests | docs | deps |
|---|---|---|---|---|---|---|
| **H1** | Atomic autosave: temp→rename, keep `.bak` | S | `managers/GameState.gd`, `tests/test_game_save.gd` | 2× round-trip: target present + no `.tmp` residue + `.bak` holds prior write; OK return + load round-trips | `CURRENT_ARCHITECTURE.md` | — |
| **H1b** | Stamp `[meta].version` on save, read (default 0) on load | S | `managers/GameState.gd`, `tests/test_game_save.gd` | `test_save_stamps_meta_version`; `test_legacy_save_without_meta_reads_version_0` | `CURRENT_ARCHITECTURE.md` | — |
| **M3** | Level-identity fallback: gate respawn restore on booted level == saved | S | `scripts/world/game_root.gd`, `managers/GameState.gd`, `scripts/player/player.gd` | see M3 test note below (positive + negative + missing-`.tres` branches) | `CURRENT_ARCHITECTURE.md` | — |

**H1 steps:** in `save_to_disk` replace `cfg.save(path)` (line 269) with `cfg.save(path+".tmp")`; on failure remove partial tmp + return err; on success, if target exists `rename_absolute(path, path+".bak")` then `rename_absolute(tmp, path)`; guard first-ever save (only rotate when target exists). Update doc comment (227-231) + `after_each` to remove `.tmp`/`.bak` siblings. *Optional bulletproofing (not required): `load_from_disk` falls back to `.bak` when primary missing.*

**H1b steps:** `const SAVE_VERSION := 1`; `var save_version := 0`; write `cfg.set_value("meta","version",SAVE_VERSION)` first in `save_to_disk`; read via `_cfg_int(cfg,"meta","version",0)` in `load_from_disk`; `save_version = SAVE_VERSION` in `reset_for_new_game`. **Do NOT gate any existing read on `save_version` yet** — record only.

**M3 steps:** add pure static `boot_used_saved_level(loaded, saved_path)` mirroring `resolve_boot_level`'s success branch (single-source the fallback decision); set `GameState.respawn_level_matches` synchronously at top of `GameRoot._ready()` (before deferred `load_level`, before `Player._ready`); add `var respawn_level_matches := true` (reset true in `reset_for_new_game`); gate `player.gd:498-500` on `has_respawn and respawn_level_matches`. **Ordering dependency:** GameRoot precedes Player in `game.tscn` sibling order — keep flag set at very top of `_ready`, add a code comment asserting it.

**M3 test note (both branches — the gate must not become always-false):** M3 alters the documented save/level-identity restore contract in `CURRENT_ARCHITECTURE.md`, so the test must pin **both** sides of the gate:
- **Positive:** matching booted level ⇒ `respawn_level_matches == true` ⇒ `player.gd:498-500` **still applies** `respawn_position` (guards against accidentally wiring the gate always-false).
- **Negative:** mismatched booted level ⇒ flag false ⇒ respawn restore skipped, level export loaded.
- **Missing-`.tres`:** `test_level_boot_lifecycle.gd` asserts export loaded + flag false.
The pure `boot_used_saved_level` predicate is unit-tested directly for both true/false in `test_level_flow.gd`.

---

### WAVE 2 — Plugin drift tests + own_recursive twin + editor-save safety (highest-leverage editor safety; converts silent drift to red tests)

*Theme: kill the re-divergence trap, blanket the plugin's hand-maintained mirrors with drift tests, and make the content-editor Save recoverable. All plugin-editor-only, no game-runtime code touched. After each plugin script edit, toggle CYBER SUNDAY Tools off/on in Project Settings → Plugins.*

| id | title | eff | files | tests | docs | deps |
|---|---|---|---|---|---|---|
| **PL1** | Delete `item_placer_dock._own_recursive`; route through `PlaceOps.own_recursive` | S | `addons/…/placer/item_placer_dock.gd`, `tests/test_devtools_placer.gd` | source-scan: item_placer contains `PlaceOps.own_recursive`/`add_do_method(PlaceOps` and NOT `func _own_recursive` | `CYBER_SUNDAY_PLUGIN_QA.md` | — |
| **PL2** | Catalog coverage + key_exports/extends drift tests | S | `addons/…/core/catalog.gd`, `tests/test_devtools_core.gd`, QA + AUTHORING docs | key_exports-exist-on-script; extends-matches-base-chain; covers-known-droppables (adds Readable/Switch/Claimable/FallImmunity rows) | `CYBER_SUNDAY_PLUGIN_QA.md`, `AUTHORING_GUIDE.md` | — |
| **PL3** | Pin gizmo `is-Type` chain via `gizmo_types.gd` static + drift test | S | create `addons/…/gizmos/gizmo_types.gd` (+.uid), edit `cybersunday_gizmo_plugin.gd`, create `tests/test_devtools_gizmo_types.gd` | is_gizmo_target true for all 17 GIZMO_CLASSES; false for Node3D/Lock; no dupes + size==17; every name but NPC maps to a Catalog row | `CYBER_SUNDAY_PLUGIN_QA.md` | — |
| **PL4** | scan_wiring FLAG_WRITE_FIELDS += `set_flag_on_read`, `flag_name`; **pin `OBJ_TYPE_FLAG` to the live enum ordinal** | S | `addons/…/panel_audit/scan_wiring.gd`, `tests/test_devtools_audit_wiring.gd` | vocabulary-covers-exports; Readable-flag-not-a-false-dead-gate round-trip; **`OBJ_TYPE_FLAG == QuestObjective.Type.FLAG` ordinal drift assert** | `CYBER_SUNDAY_PLUGIN_QA.md` | — |
| **PL5** | Content-editor Save recoverable: pre-save `.tres.bak` + overwrite confirm via shared `content_save_guard.gd` | S | create `addons/…/core/content_save_guard.gd` (+.uid), edit 3 content editors, `.gitignore`, `tests/test_devtools_save_guard.gd` | pre-save writes `<name>.tres.bak` holding prior bytes; overwrite path prompts confirm; null/first-save no-ops | `CYBER_SUNDAY_PLUGIN_QA.md` | — |
| **PL6** | Lazy first-reveal latch for the 8 disk-scanning tabs (mirror content_browser) | M | 8 dock scripts, `tests/test_devtools_lazy_reveal.gd` | `_revealed == false` post-construction; first reveal scans once; loot_editor's 3 scan calls stay in one latch body | `CYBER_SUNDAY_PLUGIN_QA.md` | — |

**PL1:** add `const PlaceOps := preload("res://addons/cybersunday_tools/dock_place/place_ops.gd")`; change line 103 `add_do_method` target `self,"_own_recursive"` → `PlaceOps,"own_recursive"`; delete the twin body (124-137). Mirrors `scene_placer.gd:15,247` exactly. PlaceOps adds a null guard the twin lacked = strict improvement.

**PL2:** the real class_name is **`Switch`** (not the reviewer's "SwitchLever"). Rows: Readable (extends LookAtInteractable, child mode), Switch (LookAtInteractable, child), Claimable (Area3D, child), FallImmunity (Ability, instance, has FallImmunity.tscn). key_exports test does `.new()` off-tree (no add_child — Area3D/Node bases don't touch tree in `_init`).

**PL3:** 17 types: TriggerVolume, AudioZone, HazardZone, ShadowVolume, NavBlocker, PatrolPath, PlayerSpawn, EncounterSpawner, ExplosiveBarrel, NPC, InvestigatePoint, NoiseSource, WorldMarker, AlarmPanel, AmbientSound, Radio, Door. `_redraw` per-type dispatch stays; only membership extracts. NPC is the sole non-catalog gizmo type.

**PL4:** two missed writers — `Readable.set_flag_on_read` and `CutsceneAction.flag_name`. Regex `^\s*<field>\s*=` won't false-match `set_flag`→`set_flag_on_read` (next char is `_`). **Do NOT** implement "derive by scanning" (write args are dotted sub-resource access). **Ordinal pin (per review rec #6):** `scan_wiring.gd:30` hardcodes `const OBJ_TYPE_FLAG := 5`, a hand-mirror of the FLAG enum ordinal (its own comment at :28 admits it). Add `test_obj_type_flag_matches_enum` asserting `scan_wiring.OBJ_TYPE_FLAG == QuestObjective.Type.FLAG` (load `QuestObjective` off-tree). Without it, an enum reorder mis-fires **every** FLAG-objective wiring check with a green suite.

**PL5:** shared `content_save_guard.gd` static: before any content editor overwrites an existing `.tres`, copy current bytes to `<path>.bak` and route the write through an overwrite-confirm prompt. **Reject `EditorUndoRedoManager`** (wrong tool for file-byte restore). Add `*.tres.bak` to `.gitignore`.

**PL6:** the 8 disk-scanning tabs each get a `_revealed` latch (scan on first visibility, not on construction), mirroring `content_browser`. **Preserve loot_editor's ordering invariant** — all 3 of its scan calls stay in one latch body, in order. Test asserts `_revealed == false` immediately post-construction.

---

### WAVE 3 — Registry consolidation + designer-first leaks (dual-source-of-truth cleanup)

*Theme: make the registry the only path, or delete it and fix the doc. Independent of waves 1–2. Groups accessor + input authority + modal registry + blast damage. Run `--import` (editor closed) before GUT after M6 (widely-referenced RefCounted gains a class dependency).*

| id | title | eff | files | tests | docs | deps |
|---|---|---|---|---|---|---|
| **H3** | EffectFactory: delete 8 dead slots, keep blood_particle, fix AUTHORING lie (folds M10) | S | `managers/EffectFactory.gd`, `tests/test_autoload_order.gd`, `tests/test_managers_tuning.gd`, `AUTHORING_GUIDE.md` | retarget slot/wrapper asserts to `[blood_particle]`/`[spawn_blood_particle]`; delete dead-slot asserts | `AUTHORING_GUIDE.md`, `CURRENT_ARCHITECTURE.md` | — |
| **M6** | `Groups.human_player(tree)` accessor; route ~10 non-NPC scans through it | S | `scripts/world/groups.gd` + npc.gd + 3 UI + dialogue_view + 3 components + Throwable | `test_groups_human_player.gd` (returns non-NPC Node3D; skips off-tree NPC; null tree→null) | `CURRENT_ARCHITECTURE.md` | — |
| **M4** | Promote ActionCatalog canonical; InputManager↔catalog drift test; fix header | S | `managers/InputManager.gd`, `scripts/player/player.gd`, `tests/test_camera_input_ui.gd` | subset drift: every `action_*` var ∈ InputMap ∧ ∈ `rebindable_actions()` | `CURRENT_ARCHITECTURE.md` | — |
| **M5** | Centralize modal guards into InputManager helpers; fix Journal asymmetry + ray_cast leak | M | `managers/InputManager.gd`, `ray_cast.gd`, shop/heal/level_up/respec screens, `tests/test_modal_registry.gd` | `any_pausing_open`; identity-excluded `any_modal_open`; Shop.open refused while Journal open; gameplay_suppressed true per-modal | `CURRENT_ARCHITECTURE.md`, `components/README.md` | — |
| **M9** | Per-weapon `explosion_damage` override (−1 sentinel = global fallback) | S | explosion_area.gd, weapon_data.gd, explosion.gd, projectile_spawner.gd | `test_explosion_damage_override.gd` (−1→global, 0/7 override); weapon_data default −1; barrel keeps −1 fallback | `AUTHORING_GUIDE.md`, `CURRENT_ARCHITECTURE.md` | — |

**H3:** keep `spawn_at` public + `blood_particle`. Delete 8 slots + 5 dead wrappers. **Do NOT** choose Option A (routing direct sites through `spawn_at`) — it strips per-instance config (explosion force/radius/instigator) + `CACHE_MODE_IGNORE` recovery. Rewrite `AUTHORING_GUIDE:1642` to the true escape hatch (edit the `.tscn` per UID).

**M6:** accessor takes `SceneTree` param (NOT internal `get_tree()`) to preserve off-tree `is_inside_tree` guards. Leave any-member scans + `dialogue_manager`'s `is Player` idiom + `Throwable:828` untouched.

**M4:** Walk/NightVision catalog rows **already shipped** (verified `ActionCatalog.tres` lines 42-86) — skip "add rows." Add `action_walk`/`action_nightvision` vars; retarget player.gd:1344/1396/1160 literals; **subset** assertion (not strict ==), controller-only `look_*` allowlist starts empty.

**M5:** co-open bug **refuted** — do NOT add blocking between tab-group siblings. Add `any_pausing_open()` + `any_modal_open(exclude)` to InputManager; `exclude` compares by object identity. `gameplay_suppressed()` is the load-bearing gate — keep its truth set byte-identical (still includes CutscenePlayer + NameEntryDialog).

---

### WAVE 4 — NPC facade docs + drift tests + dialogue contracts + combat gate (S-effort NPC hardening, precedes the extractions)

*Theme: document the host-facade contract and add the drift/contract tests before the risky NpcCombat/NpcOutline moves land in waves 5–6. T1 (the standing combat harness) is pulled forward here so it exists before the H2 extraction it de-risks.*

| id | title | eff | files | tests | docs | deps |
|---|---|---|---|---|---|---|
| **M2** | `scripts/npc/README.md` host-facade table + `set_last_attacker` setter | S | create `scripts/npc/README.md`, edit npc.gd, npc_targeting.gd | `test_npc_facade_contract.gd` (each Node-typed component `host` defaults null; npc.gd has_method `set_last_attacker`/`_set_target`) | `scripts/npc/README.md`, `CURRENT_ARCHITECTURE.md` | — |
| **M7** | Reverse-direction drift test for `_stamp_profile_full` ↔ `PROFILE_STAMPED_FIELDS` | S | `tests/test_npc_data.gd`, npc.gd (1-line comment) | `test_stamp_profile_full_fields_match_stamped_array` (source-parse both directions + count>50 guard) | npc.gd inline comment | — |
| **M8** | Mirror hostility warnings onto NpcData `conflicts()`; fix stale precedence comment | S | `addons/…/inspectors/npcdata_inspector.gd`, `tests/test_devtools_inspectors.gd` | inert-disposition-under-faction flagged + cleared by tick; pointless-override flagged; existing size==1 stays green | `AUTHORING_GUIDE.md`, `CYBER_SUNDAY_PLUGIN_QA.md` | — |
| **M14** | Dialogue speaker-service contract drift test (typed-interface remedy refuted) | S | create `tests/test_dialogue_speaker_contracts.gd`; breadcrumb comments in dialogue_manager | every duck-typed method/signal DialogueManager scans still exists on the real component (Merchant buy/sell, Healer do_heal/heal_cost, Bonfire rest, LevelUp level_up_stat/cost) + Player add_money/notify_toast + each screen open-call/`closed` signal | `CURRENT_ARCHITECTURE.md` | — |
| **T1** | In-tree combat smoke harness (armed NPC + opposed dummy on NavSandbox) | M | create `scripts/tools/combat_smoke_harness.gd`, `combat_smoke_report.gd`, `tests_soak/test_combat_smoke.gd` | asserts damage_landed + shooter_converged + not errored + orphan_delta slack; nav-never-synced→inconclusive | `tests_soak/README.md`, `CURRENT_ARCHITECTURE.md` | — |

**M2:** 5 Node-typed components (npc_bark_ui, npc_locomotion, npc_scavenge, npc_targeting, npc_voice) = no compile signal on rename; 6 NPC-typed = compile error. Add `set_last_attacker(node)` after `_set_target`; route `npc_targeting.gd:37,45` writes through it (leave the read at :42). `drive_velocity` setter **refuted** — not built.

**M7:** lists currently in sync (55==55) — prevention, not a fix. Source-scan `_stamp_profile_full` body, assert set-equality both directions. **Do NOT** do the get()/set() refactor (would trade 55 typed assignments for reflection + special-case the `threat_response` enum cast).

**M8:** `_get_configuration_warnings` is Node-only — extend the plugin's pure `conflicts()` static instead. 2 of 3 recommended items already shipped (faction_id+faction warning; precedence docs). Also fix inverted comment at `npcdata_inspector.gd:256` (`faction_id` WINS, not the resource).

**M14:** create `tests/test_dialogue_speaker_contracts.gd` asserting every duck-typed method/signal DialogueManager scans still exists on the real component, the NPC speaker contract, and each screen's open-call + `closed` signal. Load SCRIPTS (not live autoloads), instantiate off-tree. Typed-interface remedy **refuted** (would recreate the Merchant↔ShopScreen↔DialogueManager cycle). Add breadcrumb comments above each duck-scan pointing at the test.

**T1 (pulled forward from draft WAVE 7):** OPT-IN under `tests_soak/` (NOT `tests/`) — `soak.gutconfig` already globs it. Spawn a real armed NPC + real opposed-faction dummy; acquisition flows through the NPC's own perception (do NOT hand-set `_target`). SMOKE-level asserts only (≥1 shot landed / net distance decreased). `miss_chance` only rolls vs Player-group, so an NPC dummy is never miss-rolled. INCONCLUSIVE (not fail) when navmesh never syncs. **Rationale for the move:** the draft scheduled T1 in WAVE 7, two waves *after* the H2 NpcCombat extraction it is meant to de-risk. Landing it here gives H2 and H2b a standing combat gate to run against manually the moment they land.

---

### WAVE 5 — NpcCombat extraction (risky; own wave, test-first)

*Theme: extract the firing dispatch off npc.gd's root behind thin facades. Depends on WAVE 4's README (M2) so the host-facade contract is documented before the move, and on T1 (WAVE 4) as the manual combat gate. De-risk: verbatim body move, thin `_act_alerted`/`_act_unarmed` facades preserved (test_enemies asserts `has_method`; GOAP fire actions call `host._act_*`).*

| id | title | eff | files | tests | docs | deps |
|---|---|---|---|---|---|---|
| **H2** | Extract `NpcCombat` drop-in; keep thin `_act_alerted`/`_act_unarmed` facades | M | create `scripts/npc/npc_combat.gd` (+.uid), `tests/test_npc_combat.gd` (+.uid), `scripts/npc/README.md`; edit npc.gd | `test_npc_combat.gd` (act_alerted/act_unarmed surface; scavenge early-return; dodge opens burst + re-arms `_dodge_cd`; degenerate dodge skipped). Existing test_enemies + test_goap_action_fire_* stay green unchanged | `CURRENT_ARCHITECTURE.md`, `scripts/npc/README.md`, `goap/README.md` | M2 (README), T1 (gate) |

**Scope reminder:** H2 retires the **combat firing cluster only**. Locomotion, death/loot, and barks stay on root (see the §1 H2 scope note); do not mark the god-object bloat "resolved."

**Steps:** `class_name NpcCombat extends Node`, `var host: Node = null` (breaks cycle), migrate `_dodge_*` state + `DODGE_MIN_INTERVAL`. Move bodies of `_act_alerted`→`act_alerted`, `_act_unarmed`→`act_unarmed`, `_punch`, `_maybe_dodge` driving everything through `host.*`. `_fire_timer`/`_charging`/`_warned`/`_shot_miss` STAY on host (component reads/writes them). Add `_combat` to `_build_components()`. Replace root bodies with facades; delete `_punch`/`_maybe_dodge` from root (grep first). **Leave GOAP fire actions untouched.** `_move_toward`/`_update_stuck`/static locomotion helpers stay on root (test-pinned, shared with pursuit). Run T1 manually after landing.

---

### WAVE 6 — NpcOutline extraction + @tool base guard (per-part flash into existing component; base hazard hoist)

*Theme: finish the second H2 cluster (into the component that already exists) + harden the @tool boundary base. Serialized after WAVE 5 (both touch npc.gd — avoid concurrent edits to the same 3000-line file). Run `--import` with editor CLOSED (new class member surface changes the cache).*

| id | title | eff | files | tests | docs | deps |
|---|---|---|---|---|---|---|
| **H2b** | Move per-part body-swap flash into existing `NpcOutline`; keep 3 virtual-override shells on NPC | M | npc.gd, npc_outline.gd; create `tests/test_npc_outline.gd`, `scripts/npc/README.md` | `_build_part_overlay` isolation; `_part_flash_material` idempotent; `_hit_part_key`/`_nearer_side_key` resolve nearer side; **regression:** NPC still DEFINES `_flash_damage`/`flash_red`/`_apply_overlay_to_meshes` (virtual dispatch pin) | `scripts/npc/README.md`, `CURRENT_ARCHITECTURE.md` | H2 (same file) |
| **XC1** | Hoist @tool early-out into `LookAtInteractable._ready`; one count-0-safe instantiate helper | S | look_at_interactable.gd, model_resource.gd, switch_lever.gd, readable.gd, container.gd, `tests/test_look_at_interactable.gd`; create `tests/test_model_resource.gd` | model_resource: empty childless-scriptless-meshless root→null; scene-with-child→root; Mesh→MeshInstance3D; null→null. look_at: `_editor_fit_hitbox` creates 0 children | `CURRENT_ARCHITECTURE.md`, `components/README.md` | — |

**H2b (critical constraint):** `_apply_overlay_to_meshes`, `_flash_damage`, `flash_red` are **virtual overrides** the base `Character` dispatches by name — they **CANNOT** leave the NPC class. Keep 3 one-line shells that delegate into `_outline` (each guards `_outline != null` for off-tree tests). Move state (`_part_flash`, `_part_flash_tweens`) + pure helpers into NpcOutline with `apply_part_overlays`/`flash_damage`/`flash_all_parts` entrypoints. **Scope:** this is the body-swap-flash cluster of H2 only; H2's death/loot/bark bulk remains deferred backlog.

**XC1:** both halves are **consistency gaps, not live bugs**. Base `_ready` gets `if Engine.is_editor_hint(): _editor_fit_hitbox(); return`. Dedup **only** the 3 pure-delegate subclasses (switch_lever/readable/container). **Keep** explicit guards on money_pickup/can_pick_up/upgrade_pickup (pre-super runtime work) and the inline-runtime-body stations. Count-0 guard goes in the single `ModelResourceUtil.instantiate` chokepoint, narrowed to the empty-reimport signature (script-less + child-less + mesh-less Node3D root).

---

### WAVE 7 — Combat + player-movement extractions (backlog refactors; each its own tested batch)

*Theme: the remaining M-effort extraction/refactor bodies. Independent of each other and of waves 5–6, but scheduled after the HIGH work. Each lands behind a manual playtest, gated by T1 (now standing since WAVE 4).*

| id | title | eff | files | tests | docs | deps |
|---|---|---|---|---|---|---|
| **M11** | Extract shared post-`take_damage` per-victim block into `HitResolution` static; explicit `hit_pos`+`do_hitstop` params | M | create `scripts/combat/hit_resolution.gd` (+.uid), `tests/test_hit_resolution.gd`; edit damage_trace.gd, projectile.gd | non-lethal→no collateral; lethal+prior_kill pays bounty/headshot; hit_pos forwarded to apply; do_hitstop gates FreezeFrame; **projectile caller preserves `Vector3.INF` position-agnostic default** (see M11 contract note) | `CURRENT_ARCHITECTURE.md`, `scripts/combat/hit_resolution.gd` inline | T1 (gate) |
| **M13** | Extract `GroundMovement` static + `Landing` component from `player._physics_process` | M | create `scripts/player/ground_movement.gd`, `landing.gd`, `tests/test_ground_movement.gd`; edit player.gd + player .tscn | `target_speed` multiplier math off-tree; Landing on_land/tick_footsteps no-op with null host | `CURRENT_ARCHITECTURE.md`, `AUTHORING_GUIDE.md` | — |

**M11 (extract-only; behavior preserved by default — corrects the draft):** extract **only** the inner per-victim block — the segment-walk loop (hitscan) and RigidBody-continues-flying (projectile) control flows stay in their callers. `resolve_character_hit` takes `hit_pos` as an **explicit parameter**.

> **Contract note — projectile damage semantics MUST NOT change silently.** `projectile.gd:97-99` documents the `Vector3.INF` `hit_pos` default as *"a deliberate, preserved asymmetry vs the raycast path"* — projectiles intentionally deal **position-agnostic** damage (no directional/zone modifiers). The **default M11 behavior is preserve**: the projectile caller passes `Vector3.INF` so this is a pure refactor. Making projectiles directional is a **gameplay change, not a refactor**, and MUST NOT ride inside an "extract shared static" commit. If the user *explicitly* elects the directional change, it ships as a **separate follow-up commit** that also updates the `projectile.gd:97-99` comment.
>
> **Required test:** `test_hit_resolution.gd` includes an assertion that the projectile path **still passes `Vector3.INF`** (position-agnostic preserved). If the directional change is deliberately taken later, that test flips to assert the new behavior **and** the comment update lands in the same commit.

Playtest: fire projectiles into a stack of NPCs (confirm no new directional/zone damage appears).

**M13:** **do NOT** do the wholesale ~190-line lift — mirror the Slide/WallClimb hook idiom. `GroundMovement` = statics (never instantiated). Keep jump/bhop/blast/slide-jump/grapple/edge-friction interleave **on the root, in order** (byte-order-critical). `Landing` = typed `var host: Player` (avoids the M2 leaky-facade trap), null-guarded. Safest sub-win if descoped: ship `GroundMovement.target_speed` alone (S, zero physics risk).

---

### WAVE 8 — QuestTracker autoload split + quest correctness (the L; autoload registration gates it)

*Theme: the big deferred structural extraction + the two quest-behavior fixes it should carry. M1 is the only true autoload-ordering change (QuestTracker before GameState in project.godot). M15 must land inside the extracted `start_quest`, so M1 goes first.*

| id | title | eff | files | tests | docs | deps |
|---|---|---|---|---|---|---|
| **M1** | Extract `QuestTracker` autoload; GameState serializes via `capture()`/`restore()` | L | create `managers/QuestTracker.gd` (+.uid); edit project.godot, GameState.gd + ~13 caller files; `tests/test_quest_tracker.gd`, update `test_dialogue.gd` | tracker transitions without save layer; `restore(capture())` identity; path-keyed skip of code-built quest | `CURRENT_ARCHITECTURE.md` | — (but see caveat) |
| **M15** | `start_quest` back-fills FLAG objectives whose flag is already set (chained quests) | S | GameState.gd (or QuestTracker after M1), `tests/test_quests.gd` | back-fill already-set flag; chained quest advances on shared flag; falsey flag NOT satisfied | `CURRENT_ARCHITECTURE.md` | M1 (land inside extracted `start_quest`) |
| **B-F40** | Surface quest load-skip as a HUD toast instead of silent progress loss | S | GameState.gd, `scripts/ui/ui.gd` | load-skip records warning + empty dict; valid load → no warning (pure codec tests) | `CURRENT_ARCHITECTURE.md`, `AUTHORING_GUIDE.md` | — (composes with M1; field moves with tracker) |

**M1 (atomic single commit — autoload reg + ~23 caller renames are interdependent):** move quest signals + 3 dicts + all tracker methods + `_grant_quest_rewards` + `notify_*` hooks to QuestTracker. Route the ~5 `_autosave_world_state()` calls through a `state_changed` signal GameState connects (preserves coalescing). `capture()`/`restore()` mirror Reputation, keying by `resource_path` with **identical cfg section names/shapes** (live-save compat is the #1 risk). Register `QuestTracker="*res://managers/QuestTracker.gd"` **before** GameState. **Diff the `[autoload]` hunk** — user has uncommitted `project.godot` work; never sweep.

> **M1 scheduling caveat:** the review DEFERRED this (trigger = the next `project.godot` edit). If the user's uncommitted `project.godot` work makes the autoload edit costly now, **park WAVE 8's M1**, land **M15** and **B-F40** inside the current GameState (both compose cleanly with a later split), and treat M1 as a standalone follow-up.

---

### WAVE 9 — Content/scene cleanup + backlog leads (small, mostly independent; batch last)

*Theme: the low-severity, latent, and doc-only leads. All independent; several are doc/test-only. Confirm `git diff` on each hand-edited `.tscn` before staging (user is actively authoring scenes).*

| id | title | eff | files | tests | docs | deps |
|---|---|---|---|---|---|---|
| **B-F63** | Remove stray floating `stupidbody` instance from game.tscn | S | `scenes/game.tscn` (3 lines) | — (asset stays; instance removed) | none | — |
| **B-F62** | Defer old-level free in `GameRoot.load_level` (detach+rename+`queue_free`) | S | game_root.gd, `tests/test_level_flow.gd` | swap defers free (old still valid post-call, detached, new named `Level`) | `CURRENT_ARCHITECTURE.md` | — |
| **B-F19** | Ragdoll corpse-light: class-based `NodeFinder` lookup + null guards | S | ragdoll.gd, `components/README.md`; create `tests/test_ragdoll_scene.gd` | scene has OmniLight3D + PhysicalBoneSimulator3D (drift guard) | `components/README.md` | — |
| **B-F24** | Render unplaced (x<0) grid stacks in an overflow strip (shared GridInventoryView) | M | `scripts/ui/grid_inventory_view.gd`; create `tests/test_grid_inventory_view_unplaced.gd` | model yields x==−1 row; view creates visible tile for unplaced key; activate/hover fire | `CURRENT_ARCHITECTURE.md`, `AUTHORING_GUIDE.md` | — |
| **B-F59** | Trenchboom LevelData: add LevelRoot+PlayerSpawn+NavRegion; contract test | S | `scenes/levels/trenchboom_test_level.tscn`, `tests/test_level_data.gd` | every `resources/levels/*.tres` scene references a PlayerSpawn (off-tree text-parse) | `CURRENT_ARCHITECTURE.md`, `AUTHORING_GUIDE.md` | — |
| **B-F61** | Document LevelDoor travel as dormant-by-design; prefab wiring test | S | docs; create `tests/test_level_door_prefab.gd` | prefab root Area3D+LevelDoor script+CollisionShape3D child; `can_be_talked_to()` false w/o target | `CURRENT_ARCHITECTURE.md`, `AUTHORING_GUIDE.md` | — |
| **B-F7** | Extract shared mouse/pause helper `modal_menu.gd` for 7 standalone modals | S | create `scripts/ui/modal_menu.gd`, `tests/test_modal_menu.gd`; edit 7 modal screens | grab_mouse/restore_mouse/set_paused behavior + null-tree no-op | `CURRENT_ARCHITECTURE.md` | — |
| **B-F38** | Document TALK completes on box-open (by design) | S | `AUTHORING_GUIDE.md` | — (no code change; existing test_quests:193 pins behavior) | `AUTHORING_GUIDE.md` | — |
| **B-F5/F57** | Add "exactly two node_added listeners; don't add a third" invariant + count test | S | `CURRENT_ARCHITECTURE.md`; create `tests/test_global_node_added_listeners.gd` | star_sky + menu_style each 1 connect; project-wide count == 2 | `CURRENT_ARCHITECTURE.md` | — |

**B-F63:** delete node lines (~60-61) + orphaned `ext_resource 6_p57ef` (~11). Asset (`.blend`, `torso.tscn`, enemy.tscn usage) **stays**. `git diff scenes/game.tscn` = exactly 3 deleted lines before staging.

**B-F62:** replace `existing.free()` with `existing.name = &"_LevelFreeing"; host.remove_child(existing); existing.queue_free()` — detach/rename before the new node is added so the deferred free can't collide the `"Level"` name. Latent (no door placed yet). The actual free lives in `GameRoot.load_level`, **not** `level_door.gd`.

**B-F24:** defect + fix both live in the **shared** GridInventoryView (fixes loot screen AND player InventoryScreen; **zero** loot_screen.gd change). One `_tiles` dict + one seen set spanning placed+unplaced loops; keep strip tiles click-only (not draggable); `cell_from_local` must keep returning (−1,−1) for the strip region.

**B-F59 / B-F61:** navmesh cannot be baked headless — author re-bakes in-editor (validator shows transient "not baked"). B-F59 higher-leverage half = the all-LevelData contract test. F61's GameRoot seam is **already the live boot path** — only door *travel* is dormant.

---

## 3. Cross-cutting test & doc work

Gathered so nothing is forgotten across waves.

### Drift-test pattern rollout (the review's cross-cutting theme #4)
The `GoapLibrary↔dropdowns` / `PROFILE_STAMPED_FIELDS↔properties` idiom, applied everywhere a hand-mirror rots:
- **PL2** catalog coverage + key_exports/extends (WAVE 2)
- **PL3** gizmo type-chain (WAVE 2)
- **PL4** scan_wiring flag vocabulary **+ `OBJ_TYPE_FLAG` ordinal pin** (WAVE 2)
- **M4** InputManager ↔ ActionCatalog subset (WAVE 3)
- **M7** `_stamp_profile_full` reverse direction (WAVE 4)
- **M14** dialogue speaker-service contracts (WAVE 4)
- **M2** Node-typed component `host` + npc.gd seam methods (WAVE 4)
- **B-F5/F57** node_added listener count (WAVE 9)
- **B-F59** all-LevelData-has-PlayerSpawn (WAVE 9)

### Combat smoke harness
**T1** (WAVE 4 — pulled forward) is the standing in-tree combat gate — the review's widest coverage-vs-blast-radius gap (theme #5). It de-risks the H2 NpcCombat extraction (WAVE 5), H2b (WAVE 6), and M11 (WAVE 7); run it manually after each of those lands.

### Doc updates (every wave carries its own; consolidated checklist)
- **`CURRENT_ARCHITECTURE.md`** — atomic-save + `[meta].version` (W1); respawn↔level invariant, **both gate branches** (W1); modal registry, human_player accessor, input authority (W3); combat smoke harness (W4); NpcCombat/NpcOutline component list (W5/W6); @tool base guard + count-0 chokepoint (W6); HitResolution seam **+ projectile position-agnostic contract** (W7); GroundMovement/Landing (W7); QuestTracker autoload (W8); quest FLAG back-fill + load-skip toast (W8); level-swap deferred free (W9); grid overflow strip (W9); LevelData contract + dormant LevelDoor (W9); node_added invariant (W9).
- **`AUTHORING_GUIDE.md`** — EffectFactory true escape hatch (W3); per-weapon blast damage (W3); hostility precedence gotcha (W4); Landing component (W7); grid overflow (W9); wire-a-second-level recipe (W9); TALK-on-box-open gotcha (W9); quest .tres rename warning (W8).
- **`CYBER_SUNDAY_PLUGIN_QA.md`** — own_recursive shared (W2); catalog/gizmo/scan_wiring drift acceptance checks **incl. OBJ_TYPE_FLAG ordinal** (W2); content-editor save backup + confirm (PL5) + lazy-reveal latch (PL6) (W2); NpcData inspector conflict flags (W4).
- **`scripts/npc/README.md`** (new) — host-facade table (W4), extended with NpcCombat (W5) + NpcOutline (W6) host reads/writes.
- **`scripts/components/README.md`** — modal gating (W3); @tool base guard + model_resource chokepoint (W6); ragdoll class-based light (W9).
- **`tests_soak/README.md`** — combat smoke harness (W4).
- **`projectile.gd:97-99` inline comment** — left **unchanged** by M11's default (behavior preserved); updated **only** if the directional-damage change is deliberately elected in a separate follow-up commit (W7).

### Refuted-remedy breadcrumbs
Where a review-suggested fix was refuted, the drift/contract test carries a one-line comment saying why the typed remedy was rejected, so a future agent doesn't re-propose it: M14 (typed `SpeakerServices` recreates the DialogueManager cycle), M2 (`drive_velocity` setter — no component writes `host.velocity`), M8 (`_get_configuration_warnings` is Node-only), M7 (get()/set() reflection refactor rejected).

---

## 4. Coverage table (all 37 items)

| id | title (short) | wave |
|---|---|---|
| H1 | atomic save | **W1** |
| H1b | save version stamp | **W1** |
| M3 | level-identity fallback | **W1** |
| PL1 | own_recursive twin delete | **W2** |
| PL2 | catalog drift tests | **W2** |
| PL3 | gizmo chain drift test | **W2** |
| PL4 | scan_wiring flag vocab + OBJ_TYPE_FLAG ordinal | **W2** |
| PL5 | editor Save backup+confirm | **W2** |
| PL6 | lazy disk-scanning tabs | **W2** |
| H3 | EffectFactory dead slots (folds **M10**) | **W3** |
| M6 | Groups.human_player | **W3** |
| M4 | input authority + drift test | **W3** |
| M5 | modal registry helpers | **W3** |
| M9 | per-weapon blast damage | **W3** |
| M2 | npc facade README + setter | **W4** |
| M7 | NpcData reverse drift test | **W4** |
| M8 | hostility conflict warnings | **W4** |
| M14 | dialogue speaker contract test | **W4** |
| T1 | combat smoke harness | **W4** *(pulled forward from draft W7)* |
| H2 | NpcCombat extraction (combat cluster only) | **W5** |
| H2b | NpcOutline flash extraction | **W6** |
| XC1 | @tool base guard + count-0 helper | **W6** |
| M11 | HitResolution shared static (behavior-preserving) | **W7** |
| M13 | GroundMovement + Landing | **W7** |
| M1 | QuestTracker autoload split | **W8** |
| M15 | quest FLAG back-fill | **W8** |
| B-F40 | quest load-skip toast | **W8** |
| B-F63 | stray stupidbody instance | **W9** |
| B-F62 | deferred level-swap free | **W9** |
| B-F19 | ragdoll class-based light | **W9** |
| B-F24 | grid overflow strip | **W9** |
| B-F59 | trenchboom LevelData validate | **W9** |
| B-F61 | LevelDoor dormant + prefab test | **W9** |
| B-F7 | shared modal mouse/pause helper | **W9** |
| B-F38 | TALK-on-open doc | **W9** |
| B-F5/F57 | node_added invariant + count test | **W9** |
| M10 | EffectFactory doc drift | **folded into H3 (W3)** |
| M12 | TimeScale arbiter | **no action: no fix spec — task-owner sign-off required (§1)** |
| F88 / F77 | respec / co-open claims | **no action: refuted in review §3** |

**All 37 finding ids are accounted for**: 36 waved (M10 folded into H3), plus M12 as the sole explicitly-signed-off backlog omission, plus the refuted F88/F77 pair. The H2 headline's **locomotion, death/loot, and barks** sub-scopes are logged as deferred backlog in §1 (H2 waves only the combat + body-swap-flash clusters).

---

## 5. Sequencing rationale & risks

**Why this order.**
- **W1 first, unconditionally** — H1 is the only finding that costs a player their entire run, mechanically confirmed, ~10 lines. The review says "do this first, before adding any save surface." M3 rides along (same save/boot subsystem, S).
- **W2 second** — highest-leverage *plugin* work per the review (#6): converts silent editor drift into red tests, kills the own_recursive re-divergence trap, and makes the content-editor Save recoverable. Independent of everything, editor-only, zero game-runtime risk.
- **W3** — the dual-source-of-truth cleanup; independent registry consolidations, mostly S.
- **W4 before W5/W6** — the host-facade README (M2) + NPC/dialogue drift tests (M7/M8/M14) must exist *before* the NpcCombat/NpcOutline extractions so the extractions have a written, tested contract to preserve. **T1 lands here** so the standing combat gate precedes the H2 extraction it de-risks (was mis-scheduled two waves late in the draft).
- **W5 → W6 serialized** — both edit the 3000-line `npc.gd`; running them concurrently invites merge churn. W5 (NpcCombat) then W6 (NpcOutline + XC1).
- **W7** — M-effort backlog refactors, scheduled after the HIGH work; run against the T1 gate standing since W4.
- **W8 last-but-one** — M1 is the only autoload-ordering change and the review explicitly defers it to "the next project.godot edit"; M15 must land inside the extracted `start_quest`.
- **W9** — low-severity, latent, and doc-only leads batched last.

**Parallelizable / independent.** W1, W2, W3 have **zero** inter-dependencies and can run in any order or in parallel by different agents. Within W9, every item is independent. The real dependencies: **M2→H2** (README contract), **T1→H2/H2b/M11** (combat gate), **H2→H2b** (same file serialization), **M1→M15** (M15 lands in the extracted method).

**The three changes most likely to regress, and how each is de-risked:**

1. **M1 QuestTracker split (L, hot autoload, ~23 callers, live-save compat).** *Top risk: a moved/renamed cfg section shape loses in-flight quest progress on Continue; a missed caller silently breaks quest advancement.* De-risk: **keep cfg section names/shapes byte-identical** (round-trip identity test); exhaustive grep before the single atomic commit; register QuestTracker **before** GameState (Nil-autoload crash otherwise); preserve autosave coalescing via the `state_changed` signal. The review defers it; **park it if `project.godot` work is uncommitted** and land M15/B-F40 in the current GameState.

2. **M11 HitResolution + M13 GroundMovement (hot untested combat/movement bodies).** *Risk: reordering byte-critical frame beats; the projectile `Vector3.INF` position-agnostic contract silently flipping to directional damage — a gameplay change, not a refactor.* De-risk: **T1 gate + first-ever behavioral test** for each; **verbatim body moves** with the ordering-critical interleave left on the root; **small diff** (extract only the inner block / mirror the Slide hook idiom, not the wholesale lift); **M11 defaults to behavior-preserving** — the projectile caller passes `Vector3.INF`, pinned by test; any directional change ships as a **separate, explicitly-elected commit** that updates the `projectile.gd:97-99` comment. Manual playtest after each.

3. **H2/H2b NPC extractions (3000-line hot file, virtual-dispatch trap).** *Risk: `_flash_damage`/`flash_red`/`_apply_overlay_to_meshes` are base-dispatched-by-name and CANNOT leave the NPC class; a facade rename breaks GOAP fire dispatch.* De-risk: **thin facades preserved** (pinned by test_enemies `has_method` + a regression test asserting the overrides stay on NPC); GOAP fire actions untouched; verbatim moves; `--import` with editor closed; T1 gate standing since W4. **Scope discipline:** H2 retires only the combat + body-swap-flash clusters — locomotion/death/loot/barks stay on root as logged backlog, so "npc.gd is still large" is expected, not a regression.

---

## 6. Suggested commit boundaries

One commit per item (or the tight coherent batch noted), staging **only explicitly-changed paths** — never sweep the tree; the user is actively authoring scenes. Every message ends `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. Commit `.gd.uid` sidecars alongside new scripts. Write messages with backticks/`@`/`$` via `git commit -F <file>` (shell-mangling guard).

**Wave 1** — `H1` (GameState.gd + test_game_save.gd + CURRENT_ARCHITECTURE.md) · `H1b` (GameState.gd + test_game_save.gd) · `M3` (game_root.gd + GameState.gd + player.gd + 2 level tests + doc). *3 commits.*

**Wave 2** — `PL1` · `PL2` · `PL3` · `PL4` (incl. OBJ_TYPE_FLAG ordinal test) · `PL5` (content_save_guard.gd + .uid + 3 editors + .gitignore + test + docs) · `PL6` (8 docks + test + docs). *6 commits. Toggle the plugin off/on after each script edit.*

**Wave 3** — `H3` · `M6` · `M4` · `M5` · `M9`. *5 commits.*

**Wave 4** — `M2` · `M7` · `M8` · `M14` · `T1` (combat_smoke_harness.gd + combat_smoke_report.gd + tests_soak/test_combat_smoke.gd + tests_soak/README.md + doc). *5 commits.*

**Wave 5** — `H2` (npc_combat.gd + .uid + test + .uid + npc.gd + README + docs). *1 commit.*

**Wave 6** — `H2b` (npc.gd + npc_outline.gd + test + README + doc) · `XC1` (look_at_interactable.gd + model_resource.gd + 3 subclasses + 2 tests + docs). *2 commits.*

**Wave 7** — `M11` (hit_resolution.gd + .uid + test + damage_trace.gd + projectile.gd — behavior-preserving; projectile passes Vector3.INF) · `M13`. *2 commits. (A directional-projectile change, if elected, is a separate 3rd commit updating projectile.gd:97-99.)*

**Wave 8** — `M1` (**single atomic commit**: QuestTracker.gd + .uid + project.godot [autoload] hunk + GameState.gd + ~13 callers + tests + doc — diff the `[autoload]` hunk to confirm only your line) · `M15` · `B-F40`. *3 commits.*

**Wave 9** — `B-F63` (game.tscn, exactly 3 lines) · `B-F62` · `B-F19` · `B-F24` · `B-F59` · `B-F61` · `B-F7` · `B-F38` (doc-only) · `B-F5/F57`. *9 commits.*

**Total: ~36 commits across 9 waves** (T1 moved from W7 to W4; M11's optional directional change is an out-of-band follow-up, not counted). Do not push without an explicit request (user works on `main`; branch first if the session is on the default branch). Run GUT only when the user asks.