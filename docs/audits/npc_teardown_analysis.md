# npc.gd full-teardown analysis (2026-07-05)

> **PLAN ONLY — no code changed.** Ran to answer "how can we be done at ~2700 lines?" — i.e. can npc.gd be driven
> to a ~1000-1400 line coordinator by pushing more clusters into host-coupled modules? Method: 7 cluster planners +
> a floor-accounting agent → synthesis → 3 adversarial skeptics (over-claimed-savings / mis-scoped-shells /
> apply-order-hazards). All ground-truthed against the live 2795-line file.

## Bottom line (verified by all 3 skeptics)

**~1000-1400 is NOT reachable, and neither is a big reduction.** The honest floor is **~1550-1750 lines**, and that
floor is only reachable by deleting things explicit project contracts protect (the designer `@export` surface, the
cross-project public API, CLAUDE.md-mandated comments). Applying every *feasible* extraction lands the root at
**~2650-2730** — a **~65-145 line** reduction from 2795, essentially all of it in the already-staged, playtest-gated
Locomotor Phase B + NpcHeadAnchor patches (~63-67 net).

**The "safe-now, editor-open" batch nets ≈0-5 lines** (skeptic-corrected down from the synthesis's ~35-60). Every
"movable" safe-now cluster (perception predicates, bark residue, faction) is *already a thin facade over an existing
child module* — moving a 1-line `return _perception.x` body into a module and leaving `return _senses.x` on the root
is a net-zero relabel, and the cross-project public API (52 caller files) *forces* the named facade to stay anyway.

## Why the line count is misleading (the floor, by category — floor agent, skeptic-confirmed)

npc.gd is **not** 2795 lines of god-object logic — it is **~85% already decomposed** into 16 child modules. The length is:

| Category | ~lines | Can it leave? |
|---|---|---|
| `@export` inspector surface (75 exports, 13 groups) + their designer doc-comments | ~200 | **No** — Godot shows exports only on the instanced script; this IS the modding UI |
| Public-API facades (~40) called across **52 files / 167 sites** | ~180 | **No** — every module method the project calls needs a named root facade |
| GOAP-host-contract helpers (`_aim_point`, `_shot_interval`, `_treats_as_enemy`, `_move_toward`…) modules read on the host by name | ~180 | **No** — a module reading `host._aim_point()` pins `_aim_point` to the host |
| `_physics_process` tick hub + `_react_unaware`/`_react_music` orchestration | ~230 | **No** — the frame-order coordination monolith; can't invert host↔component control |
| Member-var declarations (81) — host state the tick/modules read | ~110 | **No** |
| Dispatch-by-name virtual shells (~13: `apply_velocity`, `_on_died`, `gore`, `get_aim_*`…) | ~55 | Shells stay; bodies already moved |
| `_build_components` wiring hub — **GROWS** with each extraction | ~135 | **No** (gets longer, not shorter) |
| Blank lines + section dividers + class header/consts | ~230 | Structural |

Roughly **50-65%** of the export block, member vars, tick hub, and facades ARE comments — and CLAUDE.md explicitly
protects them ("comments are semantic context… keep them"). A line target that assumes comment deletion is invalid here.

## The two rejected traps (skeptics confirmed BOTH — do NOT move these)

- **`_stamp_profile_full`** — `test_npc_data.gd:127-133` reads npc.gd as text and set-equality-greps the stamp body. Moving it silently breaks the drift guard.
- **`_on_damaged_by`** — called off-tree on a bare NPC (no `_mortality`) by `test_hostility.gd:106/119/145/158`; its provoke/target mutations can't hide behind a null-module guard.

## What real levers exist (honest tradeoffs) — see the roadmap below for the ordered detail

1. **Apply the two staged patches** (Locomotor Phase B + NpcHeadAnchor, ~65 net) — the ONLY real de-bloat; editor-closed + playtest.
2. **Finish the bark const pools → NpcVoice** (~25, safe-now, marginal).
3. **`@export` tuning → a Resource** (~70-150) — breaks the "tune inline" default on every existing scene; needs your sign-off + a scene migration.
4. **An `NpcBrain` module owning the tick body** (~230) — the only place a big chunk could move, but high-risk (playtest-gated, load-bearing frame order) and mostly relabelling (the brain reads everything back through the host).

None gets npc.gd near 1000. The realistic end state is a **~2400-2700 line root** that is a coordinator + the NPC
authoring surface + the cross-project API — long by line count, but not a behaviour god object.

---

# Synthesis roadmap (as generated) + corrections

> The skeptics corrected the synthesis's SAFE-NOW line savings DOWN to ~0-5 (A1 is a net-zero facade relabel; drop or
> treat as portability-only) and flagged the B2 accounting double-counted `_build_components` wiring. Read the roadmap
> below with those corrections; the headline (unreachable below ~1400) is verified true.

---

I have everything I need. The CrippleCallout wiring block (lines 755-768) is the exact cache-free idiom to mirror, `_build_components` visibly GROWS with each extraction (every module is a `.new()` + `host = self` + `add_child` triplet, ~4 lines, or the ~9-line path-load block for a new class_name). All FLOOR-agent numbers and cluster verdicts are ground-truthed. Writing the roadmap now.

---

# NPC.GD FULL TEARDOWN ROADMAP (plan only — no code changes)

Target: `C:/Users/dalla/3D RPG/rpg/scripts/npc/npc.gd` — verified **2795 lines** live this session. All staged docs, module list, test anchors, and the CrippleCallout cache-free idiom (npc.gd:755-768) ground-truthed.

## 0. Headline (read first)

**The ~1000–1400 target is NOT reachable and this roadmap will not pretend otherwise.** The project's own `docs/audits/npc_decomposition_status.md` (13-agent re-map, 2026-07-04) declares the extractable backlog **exhausted**: npc.gd is ~85% decomposed, and everything left is dispatch-by-name shells, ~40 cross-component facades, the ~110 lines of irreducible host state, the two coordination monoliths (`_physics_process` + `apply_velocity`), the ~200-line commented `@export` designer surface, and a CLAUDE.md-protected comment budget. The two genuine remaining targets are already staged as reviewed patches worth **~63–67 net lines combined** (Locomotor Phase B ~45, NpcHeadAnchor ~18–22 — both confirmed from the doc bodies this session).

The per-cluster plans in the prompt, cross-checked against the live file and tests, are **mostly "0 net / do-not-move" verdicts** — the movable bodies inside them are marginal (weapon-mesh builders ~30, allegiance alert-scan ~30, `_on_died` body ~35, profile-stamp ~55-but-test-risky, perception predicates ~35). Applying every marginal move on top of the two staged patches lands the root at **~1600–1750**, not below 1400.

---

## 1. DEPENDENCY-ORDERED APPLY SEQUENCE

Ordering rule: **SAFE-NOW GUT-coverable slices first** (editor stays open, applied this session), **then the editor-closed + playtest batch** (the two staged patches + anything that touches a new class_name or per-frame movement/aim visuals). Within each batch, resolve `depends_on`.

### BATCH A — SAFE-NOW (editor open, GUT-coverable, apply this session)

| Step | Slice | Why it's safe-now |
|---|---|---|
| **A1** | **Perception predicate bodies → NpcTargeting (hostility preds) + NpcSenses (sense-gate preds)** — move bodies of `_treats_as_enemy`, `_is_unaligned_hostile`, `awareness_of`, `detection_of`, `has_sensed_foe`, `is_alerted_on_player`, `is_hunting`, `_hearing_initiates_on`, `_noise_initiates_on`, `_body_discovery_on`, `can_see_node` into their **existing, already-cached** consumer modules; keep root facades. | Every one is pure forwarding logic, off-tree GUT-pinned (`test_stealth_status`, `test_stealth_sense_optin`), destinations are **existing** class_names (no new-class cascade). **Do NOT create a new NpcPerception** — route into NpcTargeting/NpcSenses where the callers already live, avoiding a cross-component hop. |
| **A2** | **Bark/voice const-pool finish → NpcVoice** (optional, ~25 lines) — move the default `*_LINES` const pools onto NpcVoice as the terminal fallback; keep `NPC.*_LINES` as thin `const X := NpcVoice.X` aliases so `test_default_barks`/`test_npc_data` static reads stay green. | Existing cached class; pure data; GUT-coverable. **Marginal** — flag as optional; the reverse-dependency trap (NpcVoice's own 14 sites call `host._emit_bark`) means the emitter/statics MUST stay on root. Only the const pools move. |

**Everything else in the prompt's clusters is a verified 0-net or do-not-move** (see §3 landmines). In particular the "Damage/death" `_on_damaged_by` body and the "Profile/stamp" `_stamp_profile_full` body are **NOT** in Batch A — see the blockers below.

### BATCH B — STAGED (editor closed + `--import` + playtest; one reimport/playtest window)

| Step | Slice | Gate |
|---|---|---|
| **B1** | **Locomotor Phase B** (already staged: `docs/audits/locomotor_phase_b_migration.md`) — `_move_toward`/`_update_stuck`/nav-hop/off-mesh bodies → `locomotor.gd` DRIVEN mode. Apply FIRST — it's the real de-bloat and the flagship "drag-drop mover" win. | Playtest movement (nav-hop, stuck recovery, off-mesh). Frame-order + caller-signatures already 4-lens reviewed; one bool bug fixed in the doc's corrections. **Prereq for B4.** |
| **B2** | **NpcHeadAnchor** (already staged: `docs/audits/npc_head_anchor_migration.md`) — head/skeleton resolve + swapped-head + `_head_position` + `_capsule_top` → `scripts/components/npc_head_anchor.gd`. Batch into the SAME reimport/playtest as B1 (marginal alone). | Editor-lock + playtest (glint origin, sniper aim-radial). Option-B facades mandatory. **Owns `_capsule_top` — do not move it elsewhere.** |
| **B3** | **Weapon-mesh builders → new NpcWeaponMesh** (OPTIONAL, ~30 net) — move `_build_weapon_mesh` body / `_build_muzzle_fx` / `_find_muzzle_marker`; keep the aim contract (`get_aim_*`), `_aim_laser_at`, and all aim-math on root. | NEW class_name → **cache-free CrippleCallout wiring required** (mirror npc.gd:760-768). Playtest: in-hand view-model at muzzle_offset, tracers/laser from Muzzle marker, re-equip frees old mesh. **Only if the user wants the marginal win.** |
| **B4** | **Cutscene tick body → new NpcCutsceneControl** (OPTIONAL, ~18 net) — move `_tick_cutscene_movement` body; keep `set_cutscene_control`/`walk_to`/`face` facades + the `_cutscene_control` tick gate on root. | NEW class_name → cache-free wiring. **Depends on B1** (moved body calls `host._move_toward`/`_face_*`, which Locomotor Phase B owns). Playtest a WALK_TO→FACE cutscene. |

**Steps explicitly REJECTED from any batch** (blockers, see §3):
- **`_on_damaged_by` body move** → REJECTED. `test_hostility` calls it off-tree on a bare NPC where `_mortality` is null; the provoke/target/perception mutations cannot live behind a `_mortality != null` guard. Keep body on root. (Only `_on_died`'s body is even a candidate, ~35 lines — defer as marginal + policy-reversal, needs sign-off since the status doc lists `_on_died` as "deliberately not extracted".)
- **`_stamp_profile_full` body move** → REJECTED. `tests/test_npc_data.gd` does `FileAccess.get_file_as_string(NPC_PATH)` + greps `func _stamp_profile_full` (confirmed line 128). Moving the body silently breaks the drift guard. Stays on root.
- **A dedicated NpcAllegiance module** → NOT WORTH IT. Resolution math already lives in `HostilityHelpers`; the facades are already 1-liners. Only `_alert_allies`/`_resolve_faction` bodies (~30) are movable and they're playtest-gated (in-tree group scan). Fold into Batch B only if the user insists; otherwise skip.

---

## 2. CUMULATIVE LINE ACCOUNTING

Starting root: **2795**. Estimates are net (body removed − shell/facade/wiring re-added). `_build_components` GROWS on every new-class step (confirmed: each module is a `.new()`+`host=self`+`add_child` triplet or a ~9-line path-load block).

| Step | Slice | Lines removed (net) | `_build_components` delta | Running total removed | **Root size** |
|---|---|---:|---:|---:|---:|
| — | start | — | — | 0 | **2795** |
| A1 | Perception preds → NpcTargeting/NpcSenses | −35 | 0 (existing modules) | 35 | **2760** |
| A2 | Bark const pools → NpcVoice (optional) | −25 | 0 | 60 | **2735** |
| B1 | Locomotor Phase B (staged) | −45 | +2 (nav injection) | 103 | **2692** |
| B2 | NpcHeadAnchor (staged) | −20 | +13 (path-load block) | 136 (−13 wiring) | **~2672** |
| B3 | NpcWeaponMesh (optional, new class) | −30 | +9 (cache-free block) | 157 | **~2651** |
| B4 | NpcCutsceneControl (optional, new class) | −18 | +9 (cache-free block) | 166 | **~2642** |

**Projected final root after the FULL optional sweep: ~2640.** After only the confirmed-worthwhile work (A1 + B1 + B2, skipping the marginal/optional A2/B3/B4): **~2705–2720.**

### Reconciliation against the FLOOR

The FLOOR agent's irreducible-core budget is **~1550–1750** (200 exports + 180 facades + 180 GOAP-host helpers + 230 tick hub + 110 member state + ~90 consts + ~120 comment/structure). **This roadmap's ~2640 final undershoots that floor by ~900 lines — meaning ~900 lines of the current 2795 are STILL "dead-weight bodies already delegating to modules" that neither this roadmap nor the exhausted backlog can lift**, because moving them breaks a test contract, a designer surface, or a per-frame coordination invariant.

**Stated honestly: the sum badly undershoots the 1000–1400 target.** Even the theoretical irreducible floor (~1550–1750) is above 1400. The realistic executable result is **~2640–2720**. There is no ~1000-lines-worth of movable behaviour left to find — the delta between "current 2795" and "floor ~1650" is the comment budget + facade tax + the two coordination monoliths, all of which are protected or irreducible.

---

## 3. PER-STEP DETAIL (destination · risk · shells kept · test to add · top landmine)

### A1 — Perception predicate bodies → NpcTargeting + NpcSenses
- **Destination:** EXISTING `npc_targeting.gd` (hostility preds `_treats_as_enemy`/`_is_unaligned_hostile` — co-located with `_acquire_target` which already calls them) + EXISTING `npc_senses.gd` (sense-gate preds). No new class → **no cache-free wiring.**
- **Risk:** safe-now.
- **Shells/facades kept on root:** all 11 named methods (`_treats_as_enemy`, `awareness_of`, `detection_of`, `has_sensed_foe`, `is_alerted_on_player`, `is_hunting`, `_hearing_initiates_on`, `_noise_initiates_on`, `_body_discovery_on`, `can_see_node`, `_is_unaligned_hostile`). `_build_perception`, `_on_spotted`, `head_look_point` STAY on root untouched.
- **Test to add:** `test_npc_perception.gd` — bare-`.new()` NPC, assert `_treats_as_enemy` protectee-defence branch, `_noise_initiates_on == is_hostile && hearing_initiates`, `awareness_of`/`detection_of` return int/float null-safe. Existing pins (`test_stealth_status`, `test_stealth_sense_optin`, `test_hostility`) must stay green through the facades.
- **Top landmine:** `_treats_as_enemy` has THREE hot callers on the host (`_acquire_target` ×5, tick line ~1734, `head_look_point`). Move the body into **NpcTargeting** (same module as its callers) not a fresh module, or you add a cross-component hop on the retarget path. `:=`-off-`host.<Variant>` is a compile error — annotate every `host.` read explicitly.

### A2 — Bark const pools → NpcVoice (optional)
- **Destination:** EXISTING `npc_voice.gd`. No cache-free wiring.
- **Risk:** safe-now.
- **Shells/facades kept:** `NPC.*_LINES` become `const X := NpcVoice.X` aliases; `_pick_bark`/`_bark_pool` **statics** stay on NPC (called `NPC._pick_bark(...)` in `test_attack_reactions`/`test_body_discovery`/`test_npc_data`); `_emit_bark` stays on root (owns `_bark_until_msec`).
- **Test to add:** none new — `test_default_barks.gd:26` (`b.greet == NPC.GREET_LINES`) already pins the alias equality; keep it green.
- **Top landmine:** REVERSE-DEPENDENCY — NpcVoice's own bodies call `host._emit_bark(host._pick_bark(host.BARK_LINES,...))` at 14 sites. Moving the emitter or statics inverts the shipped contract and breaks `test_bark_gates`'s StubHost. **Move ONLY the const data**, nothing else. Marginal — recommend skipping unless the user wants the tidy-up.

### B1 — Locomotor Phase B (staged, `docs/audits/locomotor_phase_b_migration.md`)
- **Destination:** `locomotor.gd` DRIVEN mode. Ready-to-apply patch + 4-lens review + corrections + playtest checklist in the doc.
- **Risk:** playtest-gated.
- **Shells/facades kept:** static forwarders `jump_velocity_for_climb`/`should_nav_hop`/`wall_slide_dir`/`collision_bottom_y` + const aliases (`STUCK_TIME` etc. — test-pinned) + `_stranded_*` state stay; `apply_velocity`/`_build_nav`/`_on_avoidance_velocity` stay.
- **Test to add:** none — pure-math statics stay pinned; movement is playtest-verified.
- **Top landmine:** frame-order in the tick's has-target/no-target branches is load-bearing; the doc's corrections already fixed one bool bug — apply the corrected patch verbatim. **Apply FIRST** (B4 depends on its `_move_toward`/`_face_*` host shells).

### B2 — NpcHeadAnchor (staged, `docs/audits/npc_head_anchor_migration.md`)
- **Destination:** NEW `scripts/components/npc_head_anchor.gd` → **cache-free wiring** (doc's `_build_components` block is ~13 lines).
- **Risk:** editor-lock + playtest.
- **Shells/facades kept:** Option-B facades `head_visual`/`register_swapped_head`/`_head_position` on root (external consumers `body_model_swap.gd:364/911`, `npc_head_look_mount.gd:148` call on the host root and guard `is Node3D`). `head_look_point` STAYS on root (perception glue, not anchor machinery — doc line 380).
- **Test to add:** none new — off-tree head-resolve is thin; glint origin is playtest-only.
- **Top landmine:** the doc's corrections fixed a HIGH build-ordering regression — `_build_components` must build the anchor and **flush the swapped-head buffer** in the right order. Owns `_capsule_top`; do not let B3 touch it.

### B3 — NpcWeaponMesh (optional, new class)
- **Destination:** NEW `scripts/npc/npc_weapon_mesh.gd` → **cache-free CrippleCallout wiring** (mirror npc.gd:760-768 exactly).
- **Risk:** playtest-gated.
- **Shells/facades kept:** `get_aim_origin`/`get_aim_direction`/`get_aim_basis` (WeaponHost contract, called BY NAME by `attack.gd:197/201/327/329/330/488`), `_build_weapon_mesh` shell (writes `host._weapon_mesh`/`_gun_muzzle` + re-points `_weapon.attack.muzzle`), `_aim_laser_at`, `_report_aim`, `aim_distance`. All aim-math (`_shot_interval`/`_engage_range*`/`_attack_damage`) STAYS on root (off-tree test-pinned in `test_hostility`).
- **Test to add:** none new — the moved builders are in-tree FX; keep `test_enemies`'s `has_method("_aim_laser_at"/"get_aim_*")` green.
- **Top landmine:** `_build_weapon_mesh` is called from `_ready` (line 453) AND `_on_equip_weapon_requested` (line 629) and WRITES canonical host state — the moved body must write `host._weapon_mesh`/`_gun_muzzle` back and re-point the muzzle, or tracers fire from the bare hand. Preserve the intentionally-untyped `var spark =` (SparkAttack not yet cached). **~30 net — genuinely optional.**

### B4 — NpcCutsceneControl (optional, new class)
- **Destination:** NEW `scripts/npc/npc_cutscene_control.gd` → cache-free wiring. **Depends on B1.**
- **Risk:** playtest-gated (per-frame nav — not GUT-coverable).
- **Shells/facades kept:** `set_cutscene_control`/`walk_to`/`face` (duck-called by `cutscene_actor.gd:19-52` + `test_cutscene_actor.gd`), and the `if _cutscene_control:` tick gate (npc.gd:1673) — `_cutscene_control` stays a host member read before any dispatch.
- **Test to add:** keep `test_cutscene_actor.gd` green; add one assert that after `set_cutscene_control(true)+walk_to(p)` the host still reports `_cutscene_control == true`.
- **Top landmine:** `set_cutscene_control(false)` zeroes `host._desired_velocity` so AI resumes from standstill — that write must stay wired to the host member even if the flags move into the module. Moved `_tick` body calls `host._move_toward`/`_face_*` → **must land after B1.**

---

## 4. SAFE-NOW vs STAGED SPLIT (crisp)

**SAFE-NOW BATCH (apply this session, editor open, GUT only when the user asks):**
- **A1** — perception predicate bodies → existing NpcTargeting/NpcSenses (~35 lines). No new class_name, off-tree pinned.
- **A2** — bark const pools → NpcVoice (~25 lines, **optional/marginal**).
- Net safe-now: **~35–60 lines**, root → **~2735–2760**.

**STAGED BATCH (editor CLOSED → `& "C:\Users\dalla\bin\godot.cmd" --headless --path <abs> --import` to register any new class_name → GUT green → manual playtest):**
- **B1 Locomotor Phase B** (apply first) → **B2 NpcHeadAnchor** (same reimport/playtest window) → optionally **B3 NpcWeaponMesh** → **B4 NpcCutsceneControl** (after B1).
- New class_names (B2/B3/B4) MUST use the cache-free CrippleCallout idiom; verify `.godot/global_script_class_cache.cfg` contains the new class (or restart the editor) before GUT to dodge the Nil-autoload cascade.
- Net staged: **~65–113 lines** depending on how many optionals you take.

**Hard rule from CLAUDE.md honoured throughout:** never run `NPC._ready` in a unit test; playtest-gated/movement/aim-visual slices are staged as patches, never applied unattended; only genuinely GUT-coverable slices go live with the editor open.

---

## 5. HONEST BOTTOM LINE

- **Realistic final root size: ~2640 (full optional sweep) to ~2705–2720 (confirmed-worthwhile only: A1 + B1 + B2).** Below ~1400 is **not achievable** by extraction; even the theoretical irreducible floor (~1550–1750) sits above 1400.
- **What sets the floor** (all verified against the live file + tests):
  1. **~200-line commented `@export` designer surface** — Godot shows exports only on the instanced root script; moving them to a Resource breaks every shipped scene (`profile == null` default). CLAUDE.md protects the doc-comments.
  2. **~180 lines of public facades** — the API is called across ~52 caller files (`is_hostile`, `resolved_disposition`, `set_cutscene_control`, `head_look_point`, `awareness_of`, …); each keeps a named shell + mandatory comment.
  3. **~180 lines of GOAP-host-contract helpers** — `goap/` actions read `host._aim_point`/`_move_toward`/`_can_fight_with_gun`/`_shot_interval` by name; those can't leave the host.
  4. **~230-line tick hub** (`_physics_process` + `_react_unaware` + `_react_music`) + `apply_velocity` — the coordination seam; you cannot invert host↔component control, and ~60% is frame-order-invariant comments.
  5. **~110 lines of irreducible member state** + **~55 dispatch shells** (`_on_died` body alone is still ~42 lines of ordered facade orchestration that won't thin to 2).
  6. **The CLAUDE.md comment budget** woven through all of it — not free to cut.
- **To get below ~1000 you would need TWO extra moves the current backlog deliberately excludes, and both break explicit project contracts:**
  1. **Move the ~55 tuning `@export`s to a mandatory `NpcData`/`NpcAiSettings` Resource** — kills the one-click inline inspector authoring on every existing scene (designer-first contract).
  2. **Split the `_physics_process` tick + `apply_velocity` monolith** across components — requires inverting host-owned frame order, the one thing the status doc says is impossible without regressions.
- **Recommendation:** execute **A1** live this session, then schedule the **B1+B2** editor-closed playtest window (the real, already-reviewed de-bloat). Treat A2/B3/B4 as optional marginal tidy-ups. Do **not** move `_on_damaged_by` or `_stamp_profile_full` (test-contract blockers), and do **not** stand up an NpcAllegiance module (the math already lives in HostilityHelpers). Update `docs/audits/npc_decomposition_status.md` + `scripts/npc/README.md` in the same diff as any move so the next agent doesn't trust stale "not extractable" prose.

Grounding docs (all verified present this session): `docs/audits/npc_decomposition_status.md`, `docs/audits/locomotor_phase_b_migration.md`, `docs/audits/npc_head_anchor_migration.md`. Cache-free wiring template to mirror: `scripts/npc/npc.gd:755-768`.All verified. 75 `@export` fields, 53 top-level consts, 81 member vars, 13 group headers, 1 enum. Now I have precise, ground-truthed numbers to build the floor budget.

---

# FLOOR AGENT DELIVERABLE — the irreducible core of `npc.gd`

All line numbers/counts verified by reading the live file (2795 lines, 174 funcs, 75 `@export`, 53 consts, 81 member vars) this session. Path: `C:/Users/dalla/3D RPG/rpg/scripts/npc/npc.gd`.

## Bottom line up front

**~1000–1400 is NOT achievable. The realistic post-teardown floor is ~1550–1750 lines** (with the two staged migrations applied, ~1500–1700). npc.gd is **already ~85% decomposed** — the project's own 13-agent re-map (`docs/audits/npc_decomposition_status.md`) reached the same conclusion and declared the extractable backlog **exhausted**. The remaining bulk is not liftable behaviour; it is the designer inspector surface, host state, the tick/velocity coordination monoliths, ~55 dispatch shells + facades, and a rich comment budget CLAUDE.md forbids deleting. What's left to extract is the two already-staged patches (Locomotor Phase B + NpcHeadAnchor), worth **~63–67 lines net combined**, not the ~1400 the ~1000-line target would require.

## The line budget (irreducible floor, by category)

| # | Cluster | Live range(s) | Lines | Can it leave? |
|---|---|---|---|---|
| 1 | File header: `@tool`/class/TODO + 2 preloads + class doc-blocks | 1–11, 37–59 | ~35 | **STAYS** (class identity + the archetype doc block) |
| 2 | `@export` block (75 exports, 13 groups, 1 enum) **with their rich doc-comments** | 12–273 (interleaved) | **~200** | Mostly STAYS — see §A |
| 3 | Class consts (53): outline colours, popup, audio-cue timing, bark pools, stuck/hop tuning, scene paths, FISTS/MQ | scattered 75–83, 280–312, 368–377, 594, 1307–1367, 1922-margin | **~90** | Partly movable — see §B |
| 4 | Member var declarations (81) — host state the tick + modules read | 109–410, 314–397, 1292–1370 | **~110** (incl. their comments) | **STAYS** — see §C |
| 5 | `_ready()` + `_validate_property` + `_get_configuration_warnings` + faction/profile stamping | 416–585, 2785–2795 | **~150** | Body of profile-stamp is movable (§D); `_ready`/`_validate`/`_get_config` STAY |
| 6 | `_build_components()` (GROWS post-teardown) | 683–797 + new wiring | **~120 → ~135** | **STAYS + GROWS** — see §E |
| 7 | `_physics_process` tick hub + `_react_unaware` + `_react_music` orchestration | 1667–1774, 1784–1832, 1848–1881 | **~230** | **STAYS** (the coordination monolith) — see §F |
| 8 | `apply_velocity()` — the sole `move_and_slide` writer | 2115–2150 | ~36 | **STAYS** (frame-order load-bearing) |
| 9 | Dispatch-by-name virtual SHELLS (~13) | see §G | **~55** (bodies mostly already gone) | Shells STAY, bodies already moved |
| 10 | Public-API facades (~40) + cross-component facades | scattered | **~180** (incl. mandatory doc-comments) | **STAY** — see §H |
| 11 | Small pure host helpers the tick/modules read by member (`_aim_point`, `_shot_interval`, `_engage_range*`, `_current_move_speed`, `_face_point/_yaw`, `_treats_as_enemy`, `_protectee`, `_real_player`…) | scattered | **~180** | **STAYS** — read by tick + GOAP host contract, §I |
| 12 | Blank lines + section-divider comments between funcs | throughout | **~120** | Structural, stays |

**Sum of the irreducible floor: ~1550–1750 lines** after both staged migrations land. Without them: ~1600–1750.

## Detail on the load-bearing categories

### §A — The `@export` block (~200 lines) is the single biggest floor item, and it's ~70% comments
75 exports across 13 groups (Profile, Body & Head, Identity & Outline, Hostility, Weapon, Group AI, Inventory, Loot, Perception, Laser, Movement, Behavior). Each carries a 2–5 line designer doc-comment (CLAUDE.md: "the editor is the modding surface"; comments are "semantic context" — **not free to delete**). This is the designer inspector surface and **must stay on the root** — Godot only shows `@export`s declared on the instanced script; you cannot move them to a component without losing the one-click authoring contract.

- **What COULD move to a Resource (NpcData/NpcAiSettings) but is deliberately kept:** the ~55 pure-tuning exports (perception ranges, movement, dodge, noise radii, laser colour) are ALREADY mirror-able — `NpcData` exists and `_stamp_profile_full` (519–574) copies 50+ of them. But they stay as inline exports because `profile == null` is the default and every shipped scene tunes inline. Moving them to a mandatory Resource would break every existing scene. So they are **floor by design**, not by necessity.
- **What MUST stay regardless:** `profile`, `look`, `weapon_data`, `faction`/`faction_id`/`disposition` (the `_validate_property` dropdown + `_get_configuration_warnings` read these), `display_name`. ~20 exports.

Realistic reducible portion here: near zero without a designer-workflow change the user hasn't sanctioned.

### §B — Consts (~90 lines): the only real reduction candidate
- **Movable:** the bark line pools (`BARK_LINES`, `THANKS_LINES`, `DEATH_*`, `HURT_*`, `GREET_*`, `RELOAD_*`, `COMBAT_END_*`, `LOST_INTEREST_*`, `SEARCH_*`, `FLEE_*`, `CHECK_BODY_*`, `WARN_ATTACK_*`, `AGGRO_*`, `MUSIC_*_LINES`) at 1307–1367 — **~30 lines**. But `_music_lines()` (1441–1451) and the `_bark_pool`/`_pick_bark` statics read them; the bodies already delegate to NpcVoice, yet the const pools themselves are still referenced on the root as the fallback anchor. These are the residue of a *finished* extraction (NpcVoice) — could be finished off for ~25 lines, but NpcVoice would need the default pools moved onto it. Low-risk, GUT-coverable.
- **STAYS (test/dispatch anchors):** `ALERT_COOLDOWN_MS`, `AIM_COOLDOWN_MS`, `AIM_SFX_DELAY` (unit tests pin `NPC.ALERT_COOLDOWN_MS`); the stuck/hop consts (`STUCK_TIME`, `JUMP_COOLDOWN`, `HOP_*` — test_npc/test_enemies read `NPC.STUCK_TIME`; Locomotor Phase B keeps them as **aliases** `const STUCK_TIME := Locomotor.STUCK_TIME`, so they don't leave); `WEAPON_SCENE_PATH`/`SPARK_FX_SCENE_PATH`/`SHELL_FX_SCENE_PATH`, `FISTS`, `MQ`, `POPUP_*`, `OUTLINE_*`, `PICKPOCKET_*`, `PROFILE_STAMPED_FIELDS`.

### §C — Member vars (~110 lines) all STAY — this is the hard floor
81 declarations. Every one is host state the tick or a module reads through `host.<var>`:
- Read by `_physics_process`/`apply_velocity` directly: `_target`, `_target_body`, `_perception`, `_weapon`, `_nav`, `_desired_velocity`, `_avoid_velocity`/`_avoid_ready`, `_fire_timer`, `_aim_sfx_delay`, `_retarget_timer`, `_cutscene_*`, all the `_stuck_*`/`_jump_cd`/`_hopping`/`_stranded_*` (Locomotor writes these **back through the host** — they stay), `_attending_radio`/`_music_*`.
- Read by GOAP actions/executor through the host (grep-confirmed): `_perception`, `_target`, `_search_sweep_t`, `_scavenge`, `_leader`/`_guarding`.
- The 16 child handles (`_outline`, `_laser`, `_audio_cues`, `_talk`, `_follow`, `_voice`, `_targeting`, `_locomotion`, `_scavenge`, `_combat`, `_stance`, `_noise_pulser`, `_mortality`, `_senses`, `_bark_ui`, `_self_healer`/`_panic`/`_provoke_on_attack`/`_cripple_callout`/`_executor`) — these are the *result* of decomposition; they are the coordinator's fan-out and cannot be removed.

Each var carries an inline comment explaining the invariant (CLAUDE.md-mandated). This ~110 is genuinely irreducible.

### §D — Profile stamping (~90 lines, 495–585): body movable, marginal
`_apply_profile`/`_stamp_profile_full`/`_npc_stamped_defaults` + `PROFILE_STAMPED_FIELDS`. `_stamp_profile_full` is 55 lines of `X = profile.X`. This COULD move to a `NpcProfileStamper` helper, BUT: `test_npc_data.gd` asserts set-equality between `PROFILE_STAMPED_FIELDS` and the stamp body both ways; `_apply_profile` runs as line 1 of `_ready` before `super()`; and the field list mirrors the exports. Movable for ~55 lines but with real test-contract risk and near-zero architectural gain (it's already a self-contained cluster). Not in the current backlog for good reason.

### §E — `_build_components()` GROWS to ~135 lines
Currently 683–797 (~114 lines incl. comments). It is the wiring hub — every extraction ADDS a `.new()` + `host = self` + `add_child()` triplet (or the CrippleCallout path-load idiom for a new class_name, ~8 lines each). Applying Locomotor Phase B adds the `external_nav` injection wiring; NpcHeadAnchor adds the buffer+flush + path-load block (~10 lines, per its CORRECTION 1). **Net: this function gets LONGER, not shorter, as you decompose.** Estimate post-teardown: **~130–140 lines.**

### §F — The `_physics_process` tick hub (~230 lines) is the irreducible coordination monolith
1667–1774 (`_physics_process`, ~108 lines with its heavy comments) + `_react_unaware` (1784–1832) + `_react_music` (1848–1881). This is the frame-order seam: cutscene gate → weapon-stance reconcile → talk-approach → aim-sfx countdown → `_desired_velocity` reset → fire-charge bleed → retarget → outline poll → no-target vs has-target branch → perception.sense → give-up barks → `_executor.tick` → `_react_music` → `super._physics_process`. You **cannot invert host↔component control** here — the host must own tick order. `_react_unaware`/`_react_music` delegate their *primitives* to NpcSenses already, but the *stateful orchestration* (INVESTIGATING promotion, give-up bookkeeping, the music body-turn side-effect on the perception cone) is coordinator logic. ~60% of these lines are comments documenting the frame-order invariants — CLAUDE.md-protected.

### §G — Dispatch-by-name virtual shells STAY (~55 lines; bodies already extracted)
Confirmed by grep that base/weapon call these by name; each keeps a 2–3 line shell:
`apply_velocity` (§8, special — has a real body), `_on_damaged`/`_play_damage_thud` (no-op shells), `_on_died` (still ~42 lines — orchestrates ordered facade calls, hard to thin further), `gore` (roll+super), `_on_limb_crippled` (super+delegate), `_apply_overlay_to_meshes`/`_flash_damage`/`flash_red` (super+delegate to NpcOutline), `get_aim_origin`/`get_aim_direction`/`get_aim_basis` (WeaponHost contract — called by `attack.gd`, 6 hits), `_on_equip_weapon_requested`, `_validate_property`. The `_on_died` body (1006–1047) is the one shell still carrying real orchestration weight — it's a facade-caller, not a leaf, so it can't shrink to 2 lines.

### §H — Public-API facades STAY (~180 lines incl. comments)
Grep confirms the public surface is called across **~52 files / 167 sites** (first grep) — `is_hostile`, `resolved_disposition`, `is_hostile_to` (16 hits in test_hostility alone, 21 in test_npc_vs_npc), `is_in_combat`, `is_following`/`start_following`/`stop_following`, `investigate` (investigate_point.gd, cutscene, goap), `provoke`/`forgive_provoke`, `guard`, `prompt_talk`, `greet`, `react_music`/`react_remark`, `set_cutscene_control`/`walk_to`/`face` (cutscene_actor.gd, 6 hits), `head_look_point`/`head_visual` (npc_head_look_mount.gd), `can_see_node`, `set_in_dialogue` (dialogue_manager.gd), `awareness_of`/`detection_of` (stealth_status.gd), `mark_silent_takedown` (silent_takedown.gd). Each keeps a 1-line body + its mandatory doc-comment (~3–4 lines each). ~40 facades × ~4 lines ≈ 160–180 lines. **This is the tax of being a coordinator** — every module method the rest of the project calls needs a named facade on the root.

### §I — Small pure host helpers the GOAP contract reads (~180 lines) STAY
Grep of `scripts/npc/goap/` confirms the executor + actions read these on the host by name: `_perception`, `_target`, `_can_fight_with_gun`, `is_fleeing`, `_move_toward`, `_face_travel`, `_face_point`, `_hide_laser`, `_search_sweep_t`, `search_sweep_rate`, `_idle`, `_scavenge`, `_ensure_armed_from_backpack`, `_act_alerted`/`_act_unarmed`, `_perception.last_known_position`. Plus the aim/weapon math the shells need: `_aim_point`, `_aim_range`, `_engage_range`/`_engage_range_for`, `_shot_interval`, `_attack_damage`, `_deflect_for_miss`, `_current_move_speed`, `_treats_as_enemy`, `_protectee`, `_real_player`, `_set_target`, `set_last_attacker`, `aim_distance`. These are the **host-coupling contract** — a module reading `host._aim_point()` means `_aim_point` cannot leave the host. Genuinely irreducible.

## What the two staged migrations actually buy (reconciling with the ~1000 target)

- **Locomotor Phase B** (`locomotor_phase_b_migration.md`): moves `_move_toward`/`_update_stuck`/nav-hop/off-mesh recovery bodies to `locomotor.gd`. Net **~45 lines** off the root (the doc's own estimate), because forwarding static shells (`jump_velocity_for_climb`, `should_nav_hop`, `wall_slide_dir`, `collision_bottom_y`) + the const aliases + `_stranded_*` **stay** for the tests, and `apply_velocity`/`_build_nav`/`_on_avoidance_velocity` stay.
- **NpcHeadAnchor** (`npc_head_anchor_migration.md`): net **~18–22 lines** — and all 3 reviewers said DEFER (marginal); Option-B facades are mandatory because two external consumers call on the host root.

Combined: **~63–67 lines**. That takes 2795 → ~2728 of *current* code, but the *floor* (stripping the already-delegated bodies that are dead weight) lands at **~1550–1750**. To hit 1000 you would have to delete ~550–750 lines of protected comments and/or collapse the export/facade surface — both of which break explicit project contracts (designer authoring, the cross-project caller API, CLAUDE.md comment policy).

## Verdict for the plan

- **~1000–1400 is NOT reachable.** State it plainly: the honest floor is **~1550–1750 lines**, dominated by (a) the ~200-line commented export surface that must stay on the root for editor authoring, (b) ~180 lines of public facades the project's 52 caller files depend on, (c) ~180 lines of GOAP-host-contract helpers, (d) the ~230-line tick coordination monolith, (e) ~110 lines of irreducible member state, and (f) the CLAUDE.md-protected comment budget woven through all of it.
- The comment budget is **not free to cut** — CLAUDE.md explicitly values rich intent/invariant comments, and ~50–65% of the export block, member vars, tick hub, and facades ARE comments. Any line-count target that assumes comment deletion is invalid for this repo.
- The extraction backlog is **exhausted** except the two staged, playtest-/editor-lock-gated patches worth ~65 lines net. There is no ~1000-line-worth of movable behaviour left to find.

Grounding docs: `docs/audits/npc_decomposition_status.md`, `docs/audits/locomotor_phase_b_migration.md`, `docs/audits/npc_head_anchor_migration.md`.

=========== VERDICT 1 ===========

Both blockers confirmed:

1. **`_stamp_profile_full`** (test_npc_data.gd:127-133): `FileAccess.get_file_as_string(NPC_PATH)` + greps the stamp body by set-equality. Moving the body silently breaks the drift guard. Plan's rejection is CORRECT.

2. **`_on_damaged_by`** (test_hostility.gd:106,119,145,158): called off-tree on a bare `load(NPC_PATH).new()` NPC where `_mortality` is null. The provoke/target mutations can't hide behind a null-guard. Plan's rejection is CORRECT.

I have everything needed. Here's my verdict.

---

# SKEPTIC VERDICT — over-claimed-savings lens

Ground-truthed against live `npc.gd` (**2795 lines** confirmed), the three staged docs, and every caller/test cited. The plan's *strategic* honesty is exemplary — it leads with "1000-1400 is NOT reachable" and lands at ~2640-2720. But the skeptic lens found **one genuine line-accounting overclaim** and **one arithmetic double-count**, both inside the A1/B2 rows. The plan does not under-promise; it slightly *over*-promises on the one batch it markets as "apply this session."

## Confirmed-sound (no correction)
- **Wiring idiom** npc.gd:755-768 — the CrippleCallout cache-free block is exactly as described (path-string + `get_script().resource_path` scan + `load().new()`). Correct template.
- **`_treats_as_enemy` → NpcTargeting** — all 8 "external" refs are `host._treats_as_enemy` from `npc_targeting.gd` (the callers ARE the destination); its deps `is_hostile_to` (npc.gd:885) and `_protectee` (npc.gd:1232) stay on host. The move is real and nets ~11 lines. **This is the only substantial body in A1.**
- **Both OVER-SCOPED rejections are correct.** `_stamp_profile_full` is grep-pinned by `test_npc_data.gd:127-133` (`get_file_as_string` + set-equality on the stamp body). `_on_damaged_by` is called off-tree on a bare NPC with null `_mortality` at `test_hostility.gd:106/119/145/158`. Neither body can move. Plan nails both.
- **`_on_died` deferral** — status doc line 36 lists it as "deliberately not extracted"; plan correctly flags moving it as a policy reversal needing sign-off.
- **B1 Locomotor −45** — reconciles with `_update_stuck` (2160-2222, ~62 del) + `_move_toward` (~50 del) minus the DRIVEN-mode shell, the `const X := Locomotor.X` forwarder aliases (doc line 35), and retained state (`_stranded_cycles`/`_tick_stranded`/`_current_move_speed` STAY, doc lines 55-56). −45 is honest.

## NEEDS-FIX — corrections

**FIX 1 — A1 net removal is overclaimed: −35 → realistically −18 to −22.**
Cited: plan §2 table row A1 ("−35") and §4 ("~35 lines").
Ground truth (bodies read at npc.gd:1117-1182, 2303-2314, 2331-2354, 2708-2709):

| predicate | body lines | facade cost | net |
|---|---|---|---|
| `_treats_as_enemy` | 12 | 1 | **11** |
| `_is_unaligned_hostile` | 4 | 1 | 3 |
| `awareness_of` / `detection_of` / `is_hunting` | 3 each | 1 | 2 each = 6 |
| `is_alerted_on_player` / `has_sensed_foe` / `_hearing_initiates_on` / `_noise_initiates_on` / `_body_discovery_on` | 1 each | 1 | **0 each** |
| `can_see_node` (npc.gd:2708) | **already a 1-line facade** to `_perception` | — | **0** |

Total ≈ **20 net**, ceiling. The overclaim comes from counting doc-comments as removable — but CLAUDE.md ("Comments are semantic context… keep them") protects them, and constraint 2 mandates a named facade for all 11 (every one has external callers: `awareness_of`/`detection_of` are duck-called by `stealth_status.gd:27` + test-pinned `test_stealth_status.gd:77`; `can_see_node` already delegates). **Correction: A1 removes ~20, not 35. `can_see_node` should be struck from A1 entirely — it's a zero-net facade→facade move.**

**FIX 2 — B2 row double-subtracts the wiring; the running-total math is internally inconsistent.**
Cited: plan §2 table, B2 row: "−20 removed · +13 build_components · running 136 (−13 wiring) · root ~2672".
The head-anchor doc line 466 states the **≈−18 to −22 is already NET of the +13 `_build_components` block**. The plan lists −20 AND +13 as separate columns, then annotates "(−13 wiring)" as if subtracting it a second time. Whether you read the row as net −7 (per the visible arithmetic) or net −20 (per the doc), the two disagree by 13 lines. **Correction: B2 is a flat ≈−18 to −22 net, wiring already included. Drop the separate +13 column for B2 (and re-check B1's "+2" and B3/B4's "+9" columns for the same double-count — the staged docs' net figures already fold in their own wiring).**

**FIX 3 — Cumulative total is optimistic by the A1 delta.** With A1 at ~20 (not 35), the "confirmed-worthwhile A1+B1+B2" endpoint is **~2718-2735**, not the plan's "~2705-2720." Minor, but it's the number the user executes against. The full-sweep ~2640 is likewise ~15 lines optimistic. **The plan's *conclusion* survives — still nowhere near 1400 — so this is a precision fix, not a strategy failure.**

## What the plan got RIGHT that a lazy review would miss
- It does **not** claim to hit 1000-1400 — it opens by refuting that target and quantifies the floor (~1550-1750) as still above 1400. The over-scope risk here is inverted from the usual: the plan is honest about the ceiling and only slips on per-batch precision.
- It correctly keeps every dispatch-by-name shell and public facade on the root, and correctly refuses to stand up an NpcAllegiance module (HostilityHelpers already owns the math).

## VERDICT: **NEEDS-FIX** (3 corrections, all line-accounting; strategy is sound)
1. A1 net **−35 → ~20**; strike `can_see_node` (npc.gd:2708) as a zero-net facade→facade.
2. B2 row **double-subtracts wiring** — the doc's −18 to −22 already includes the +13 block; fix the table column and re-audit B1/B3/B4 for the same pattern.
3. Propagate: confirmed-worthwhile endpoint **~2718-2735**, full-sweep **~2655**. Below ~1400 remains unreachable — that headline stands.

No cluster is mis-scoped as movable-when-pinned (the two real traps, `_stamp_profile_full` and `_on_damaged_by`, are already correctly rejected). The plan over-promises **line savings on A1/B2 only** — fix the two tables and it is execution-ready.

=========== VERDICT 2 ===========

Confirmed decisively: after Locomotor Phase B, `_move_toward` KEEPS its exact-signature shell on npc.gd (doc line 624: "delegate to Locomotor, KEEP the exact signature"). So B4's dependency on B1 is real (cutscene body calls `host._move_toward`) but the shell survives — the plan's B4→B1 ordering is correctly justified, not a mis-scope.

I have enough to render a verdict. The plan's core claims are all ground-truthed against real code. Let me do one final check on the `:=` Variant-host trap mention and cache-free wiring for the new class_names the plan proposes (B2/B3/B4).

The evidence is complete. Summary of verification:

**Dispatch/contract/public MOVE audit — the core skeptic lens (all PASS):**
- `get_aim_origin/direction/basis` (WeaponHost contract): grepped 6+ external by-name callers (silent_takedown.gd:60-61, pet_interaction.gd:63, claim_interaction.gd:113, character.gd:712-718) + 2 test contracts (test_enemies.gd:387-392, test_character.gd:443-463). **Plan B3 correctly keeps these as root shells and moves ONLY `_build_weapon_mesh`/muzzle-FX bodies.** No mis-scope.
- `_on_damaged_by`: off-tree callers in test_hostility.gd (106/119/145/158), test_npc_vs_npc.gd (127/139/151), asserted present at test_hostility.gd:186. **Plan correctly REJECTS the body-move** (would sit behind a null `_mortality` guard the tests defeat).
- `_stamp_profile_full`: source-text grepped by test_npc_data.gd:134 (`src.find(...)`). **Plan correctly REJECTS the move.**
- `walk_to`/`set_cutscene_control`/`face`: verified as duck-called facades; plan B4 keeps them + the `_cutscene_control` tick gate on root.
- `_move_toward` shell survives Phase B with exact signature (locomotor doc:624) — B4→B1 dependency is real but non-breaking.
- A1 perception predicates: external `.awareness_of`/`.detection_of` callers are radio.gd, stealth_status.gd, test_stealth_status.gd — all call on the NPC root, so **root facades are mandatory**; plan keeps all 11 named shells. Correct.

**Staged-doc net-line claims verified:** head_anchor doc states "≈ −18 to −22 net" (plan cites ~18-22 ✓, and mandatory Option-B facades ✓). Locomotor doc corroborates `_stranded_cycles`/`_tick_stranded`/facing STAY on root — plan's B1 shell list matches.

---

## VERDICT: PLAN-SOUND (with one scope caveat, not a correctness defect)

The plan does **NOT** commit the mis-scoped-shell error I was hunting for. Every dispatch-by-name virtual, every WeaponHost-contract method (`get_aim_*`), and every cross-project public API method is correctly kept as a root shell/facade with only the *body* proposed for movement. I traced the callers of each and found no case where the plan moves a by-name-dispatched method whole off the root. The two most dangerous candidates (`_on_damaged_by`, `_stamp_profile_full`) are explicitly and correctly REJECTED with the right reasons (off-tree null-`_mortality` guard defeat; source-text drift-guard grep). The `:=`-off-Variant trap is called out per-step (A1, B1), and cache-free CrippleCallout wiring is correctly required for all three new class_names (B2/B3/B4) — mirroring the real idiom at npc.gd:760-768, which I confirmed exists verbatim.

**The one thing to flag — this is a scoping honesty point, not a shell defect:** the plan's headline is its own strongest correction. It refuses the prompt's ~1000-1400 target and states plainly that the realistic floor is **~2640-2720**, undershooting even the theoretical irreducible floor (~1550-1750). That is the correct call and it is well-defended: the residual ~900 lines are protected exports, the ~180-line facade tax (which the shell-preservation discipline *forces* — you cannot both keep the facades and hit 1400), the GOAP host-contract helpers, and the two coordination monoliths. **A plan that hit 1400 would have to be mis-scoping shells** — so the plan's refusal to promise it is the direct evidence that it is not over-scoping.

Minor OVER-SCOPED reclassifications the plan already self-flags (I concur, no change needed): A2 (bark const pools, reverse-dependency risk), B3 (weapon-mesh, ~30 net), B4 (cutscene, ~18 net), and the rejected NpcAllegiance module. These are correctly marked optional/marginal rather than promised.

No corrections required. Execute A1 live; stage B1+B2 for the editor-closed playtest window; treat A2/B3/B4 as optional. Do not move `_on_damaged_by` or `_stamp_profile_full`.

=========== VERDICT 3 ===========

All constraints verified. `get_aim_*` are called by-name via `character.get_aim_direction()` etc. in attack.gd — so per HARD CONSTRAINT 1 the shells MUST stay on the root even if B3 moves the mesh-builder body. The roadmap correctly keeps them. `_build_weapon_mesh` body is ~32 lines (2462→2494), matching the roadmap's "~30 net" claim.

I have ground-truthed every load-bearing claim. Here is my verdict.

---

## SKEPTIC VERDICT — apply-order-hazards lens

**Ground-truth pass complete.** Live file = **2795 lines** (roadmap correct; status-doc's "2793" is stale from the user's live edits). Cache-free idiom at **npc.gd:755–768** verified. All three grounding docs present. Every cited caller and both rejected-blocker test contracts confirmed against source.

### What the roadmap gets RIGHT (no correction needed)

1. **The two rejected blockers are correctly rejected — both verified.**
   - `_stamp_profile_full`: `tests/test_npc_data.gd:133` does `FileAccess.get_file_as_string(NPC_PATH)` + set-equality greps the stamp body (`test_stamp_profile_full_matches_stamped_array_both_ways`, line 127). Moving the body silently breaks the drift guard. **Confirmed do-not-move.**
   - `_on_damaged_by` (npc.gd:930–983): `test_hostility.gd:12` exercises the provoke/target-lock path off-tree on a bare NPC with `_mortality == null`. The body mutates `_last_attacker`/`_set_target`/`_perception.alert_to`/`_npc_grudges` — none can hide behind a `_mortality != null` guard. **Confirmed do-not-move.**

2. **Apply order B1 → B4 is correct.** `_tick_cutscene_movement` (npc.gd:2289) calls `_move_toward`/`_face_travel`/`_face_point`. Since Locomotor Phase B (B1) takes ownership of `_move_toward`, B4's moved body depends on B1's host shells existing first. Ordering B4 after B1 is right. **No hazard.**

3. **Constraint-1 aim shells correctly retained.** `attack.gd:197/201/327/329/330/488` call `character.get_aim_origin/direction/basis()` by name. B3 keeps these shells on the root. `_build_weapon_mesh` body is genuinely ~32 lines (2462→2494). **Correct.**

4. **The staged-doc numbers check out.** NpcHeadAnchor doc states **≈−18 to −22 net** (line 466), exactly as the roadmap cites. Locomotor's ~45 is the roadmap's own extrapolation of a large movement-core move — defensible but not doc-stated (see FIX-2).

5. **Headline honesty is correct and important.** Status doc line 24: *"the extractable backlog is exhausted."* Line 9: *"~85% already decomposed."* The roadmap's refusal to promise 1000–1400 is the single most valuable thing in it, and it is TRUE. The floor genuinely sits above 1400.

### NEEDS-FIX (corrections required before execution)

**FIX-1 — A1 is OVER-SCOPED; its "−35 net" is fictional. Reclassify to ~0-net / drop.**
Every A1 predicate is ALREADY a 1–3 line facade over the **`_perception` child** (not an NpcXxx module):
- `can_see_node` (npc.gd:2708) = 1 line: `return _perception != null and _perception.can_see_node(node)`
- `has_sensed_foe` (1152) = 1 line; `is_alerted_on_player` (1117) = 1 line; `is_hunting` (1140), `awareness_of` (1170), `detection_of` (1178) = 3 lines each.
- `_is_unaligned_hostile` (2331) already delegates to `HostilityHelpers.is_unaligned_hostile` — its only non-npc.gd reference lives in hostility_helpers.gd itself.

All six are cross-project public API (verified callers: `stealth_status.gd:27/36`, `radio.gd:404`, `player.gd:1174`, `detection_stinger.gd:70`, `body_model_swap.gd:188`), so **Constraint-2 forces a named facade to stay**. Moving a 1-line `return _perception.x` body into NpcSenses and leaving `return _senses.x` on the root is a **net INCREASE** in total code and **~0 root reduction**. The roadmap's own §3 landmine even notes `_treats_as_enemy` is read inline by the tick at 1734 — but doesn't reconcile that this makes the "move" a pure relabel. **Correction: drop A1 from Batch A, or scope it honestly as "0-net tidy, portability only."** The real Batch-A safe-now win is close to zero, not ~35.

**FIX-2 — Locomotor's "−45 net" is unsourced.** The doc (verified) states no headline net; it's a large movement-core move with a mandatory const-duplication tax (10 consts aliased on BOTH scripts, line 61) and static forwarding shells for 14 test asserts (line 57). ~45 is plausible for the body but the re-added shell/alias/const tax is non-trivial. **Correction: mark ~45 as an estimate, not a doc figure, and subtract the const-alias + static-shell re-adds explicitly.**

**FIX-3 — A2 tripping the @tool cache: not a hazard, but the framing is loose.** A2/A1 target EXISTING cached class_names (NpcVoice/NpcSenses/NpcTargeting), so no new-class parse cascade — the roadmap says this and it's correct. But labeling A1/A2 "apply this session, editor open" while they yield ~0 root lines means the safe-now batch delivers almost nothing. The genuinely safe-now, cache-free work is empty of real de-bloat. **Say so.**

### Net effect on the accounting
With A1 corrected to ~0 and A2 already flagged marginal, the **entire safe-now batch nets ≈0–5 root lines**, not 35–60. The real de-bloat is 100% in the staged/playtest batch (B1+B2 ≈ −63 to −67), exactly as the status doc says. The roadmap's final ~2640–2720 projection still holds; only the safe-now sub-total was inflated.

---

## VERDICT: **NEEDS-FIX**

The plan is **structurally sound and refreshingly honest about the 1000–1400 target being unreachable** — that headline is verified true. Apply order (B1→B4 dependency, aim/cutscene shells, both test-contract rejections) is correct with no stranding hazard: nothing the tick reads by member (`_target`, `_perception.is_hostile = _treats_as_enemy(...)`, `_desired_velocity`) is moved off the host.

But it **over-promises the SAFE-NOW batch**:
1. **A1 nets ≈0, not −35** — every predicate is already a thin facade over the `_perception` child, and Constraint-2 forces the facade to stay. Reclassify as portability-only or drop.
2. **Locomotor's −45 is an unsourced estimate** carrying an unaccounted const-alias/static-shell re-add tax.
3. Correct the accounting so the safe-now sub-total reads ≈0–5, and state plainly that all real de-bloat is in the staged playtest window.

Fix those three and the plan is execution-ready. Do NOT let the "safe-now, editor-open, −60 lines" framing survive — it will have the user apply A1 expecting a win and get a net-zero relabel.