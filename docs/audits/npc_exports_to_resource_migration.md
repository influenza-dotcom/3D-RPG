# npc.gd exports → NpcTuning Resource — staged migration (NOT applied)

> **STATUS: STAGED, AWAITING USER GO/NO-GO — EDITOR-CLOSED APPLY.** Drafted + 4-lens adversarially verified
> 2026-07-05 (10-agent workflow: 4 recon → design → patch → 4 skeptics). Moves 45 pure-tuning `@export`s off
> npc.gd into a new `NpcTuning` Resource with a `_get`/`_set` forwarder. **The verified math says this is NOT a
> de-god-objecting play** — read "The corrected numbers" before deciding. Nothing has been applied.

## The corrected numbers (line-accounting skeptic, recomputed edit-by-edit)

| Claim | Draft said | **Verified** |
|---|---|---|
| npc.gd net savings | −104 (−3.7%) | **−71 (2806 → ~2735, −2.5%)** — the draft omitted ~half its own 50-line forwarder from the ledger |
| Project total | +~95 | **≈ +320 lines** (scenes +~122 were ignored; npc_tuning.gd is ~177; new test +~80) |
| Scene inventory | 6 files / 12 nodes / 106 lines | **6 files / 13 nodes / 108 override lines** (payloads themselves verified byte-exact) |

**Verdicts:** duck-reader-breakage ✅ SOUND · scene-and-inspector ✅ SOUND · test-and-drift ⚠️ NEEDS-FIX (minor)
· line-accounting ⚠️ NEEDS-FIX (the numbers above). All code edits, anchors, and scene payloads verified
apply-ready; every correction is in the *claims/prose*, folded in below.

## What it actually buys vs costs (the honest trade)

**Buys:** (1) **tuning presets as `.tres`** — a `Sniper.tres`/`Raider.tres` NpcTuning assignable in one Inspector
click (serves the OPEN "Raider/Sniper presets" authoring-friction backlog item); (2) one collapsible tuning
surface per NPC instead of a 260-line scroll; (3) the duck-read surface becomes *enumerated and test-pinned*
(new forwarding suite) instead of implicit.

**Costs:** ~zero god-object relief (−2.5%); +320 project lines; a permanent `_get`/`_set` seam in the @tool root;
Make-Unique friction for per-instance tweaks; **frozen base-scene inheritance** (risk #0 below); editor-closed
apply + 6-scene hand migration.

**Recommendation (echoing the design's own):** approve ONLY if you want the preset workflow. As a line-count
play it fails its own goal — the staged Locomotor Phase B / behavior extractions remain the higher-yield path.

## Empirically RESOLVED risk (skeptic ran it on your engine build, Godot v4.6.3.stable)

A project-less scratch test confirmed the forwarder semantics on the shipping build: `"name" in obj` → true;
`get("name")`, `get(&"name")`, dot-access via Variant AND Node-typed refs all forward; `set()`/dot-assign land in
`_set`; forwarded names do NOT appear in `get_property_list()`. Consequences: the two `in`-operator test sites
(test_goap_action_search.gd:192, test_provoke_on_attack.gd:111) pass; **the §8 `_get_property_list` contingency is
PROVEN UNNECESSARY — do not ship it** (it would re-grow a flat Inspector surface and eat the savings); the new
test's `npc_props.merge(_prop_names(n.tuning))` line is load-bearing (forwarded names are absent from the list).

## REQUIRED CORRECTIONS (apply ON TOP of the drafted patch below)

1. **Risk #0 — frozen base-scene inheritance (DISCLOSURE, inherent to the design):** today a derived node's
   non-overridden field tracks NPC.tscn LIVE (retune NPC.tscn's `sight_range`, every instance follows). The
   whole-resource override bakes NPC.tscn's 7-value base payload as FROZEN copies into ~10 derived sub-resources
   (worst: the 3 NavSandbox raiders whose only override was `wanders = true` each gain a 12-line frozen block).
   Behavior-identical at apply time; silently divergent the first time NPC.tscn is retuned. Unavoidable under
   design C-minimal — accept it knowingly or reject the migration.
2. **Fix the §9.4 scratch script** (it wouldn't compile — `Object.set()` returns void, illegal in a ternary):
   use plain sequential statements. Note the check already PASSED this session (see above); keep it as apply-time
   belt-and-braces only.
3. **Editor re-save churn:** `@export var tuning: NpcTuning = NpcTuning.new()` is a constructor default — the
   first editor re-save of ANY NPC-bearing scene without an authored tuning (enemy.tscn, civilian.tscn,
   trenchboom, …) may bake a `tuning = SubResource(...)` block freezing then-current defaults. Values identical,
   churn only — diff-review the first re-save of EVERY NPC scene, not just the 6 migrated ones.
4. **Apply strictly by verbatim OLD-text anchors, not absolute lines** — npc.gd drifted 2804 → 2806 during the
   run (the user live-edits it); every anchor still matches exactly. weapon_stance.gd's function spans 102–106.
5. **Also commit `tests/test_npc_tuning_forwarding.gd.uid`** (§7.6 lists only the npc_tuning.gd sidecar).
6. **Loosen the NpcTuning class-doc** — 8 of its 45 fields (Group-AI noise five + `alert_radius` + 2 stealth
   opt-ins) are NOT NpcData-stamped; the "owns every field an archetype stamps" sentence over-claims.
7. Headline arithmetic per the corrected-numbers table (108 override lines / 13 nodes / −71 / +320).

## Pre-apply checklist (editor CLOSED)

1. Apply the §1–§7 patch + corrections above (verbatim-anchor matching; TABS).
2. `godot --headless --import` (absolute path) → registers `class_name NpcTuning` + both new `.gd.uid` sidecars.
3. GUT: expect green incl. the rewritten drift test (dual-shape regex, 55-entry lockstep), the updated
   property-list test, and the NEW forwarding suite; then the soak/combat-smoke harnesses (their pre-add_child
   `set()` calls forward — verified).
4. In-editor spot-checks: Inspector shows ONE "Tuning" foldout (no flat duplicates); a migrated scene (TestLevel
   Enemy3) keeps `sight_range = 500`; `_validate_property` faction dropdown intact; save a scene and diff-review
   (correction 3).
5. Playtest spot-check: a raider still perceives/paths/fires with authored numbers (perception copies + noise
   radii read through the forwarder / tuning).

---

# Design (as generated; read with the corrected numbers)

All ground-truthing needed for the design decision is confirmed: no `_get`/`_set`/`_get_property_list` exists anywhere in `scripts/` (clean namespace for a forwarder), the 75 `@export`-prefixed lines decompose as 62 vars + 13 group markers exactly as the census said, and the stamp body/`PROFILE_STAMPED_FIELDS` (npc.gd:473–484, 519–574) match the recon reads. The design follows.

---

# DESIGN: npc.gd tuning-export migration — shape decision

Repo: `C:/Users/dalla/3D RPG/rpg`. Target: `scripts/npc/npc.gd` (2804 lines, verified).

## 1. Shapes weighed

### Shape A — FULL MOVE (all 49 candidates + generic `_get`/`_set` forwarder) — REJECTED: does not compile
A forwarder rescues duck reads (`host.<name>` on Node-typed hosts, `body.get(&"name")`, harness `set()`), but **five compile-time readers hard-error the moment the declared properties vanish**: `weapon_stance.gd:63,105-106`, `talk_approach.gd:59,66,86`, `npc_audio_cues.gd:44`, `npc_outline.gd:40,54,56,66` (all `host: NPC`), and `tests/test_ranged_behavior.gd:12-35` (`var e: NPC`). GDScript's analyzer does not consult `_get` for typed access. Pure A is not a real option — it silently degenerates into C. Additionally, `_get` alone fails `tests/test_npc_data.gd:120-121` (`get_property_list()` resolution), so "A with no test changes" doesn't exist either.

### Shape B — PARTIAL MOVE (zero-external-reader exports only) — REJECTED: honest math is negative
The free set is 6 exports: `muzzle_offset`, `weapon_mesh_rotation`, `combat_noise_decay`, `hearing`, `outline_color`, `laser_color` (~20 decl+doc lines). But "no forwarder needed" is false even here:
- 5 of the 6 are stamp-written (`X = profile.X` at npc.gd:536/537/551/555/528 — a bare assignment to an undeclared member is a **compile error**), so the stamp body, `PROFILE_STAMPED_FIELDS`, the drift test (test_npc_data.gd:127-150) and the property-list test (104-124) all get rewritten anyway.
- `muzzle_offset`/`weapon_mesh_rotation` are scene-overridden (NPC.tscn:10, medicine_person.tscn:110, TestLevel*.tscn Enemy2) → scene migration is still required.
Cost: a new Resource class + reflective-machinery rewrite + scene migration + test rewrites, to delete ~20 lines and add ~15 of glue. Net npc.gd savings ≈ **5 lines**. All of the tax, none of the payoff. Reject.

### Shape C — HYBRID (chosen, in a specific "C-minimal" variant)
Full move of a **curated 45-export set** + generic `_get`/`_set` forwarder + rewrite of the (now only two) typed component readers. Details in §2.

Also weighed for honesty — **Shape D, don't do this at all**: the export block is 5.4% of npc.gd at absolute ceiling; the god-object problem is the other 2500 lines of logic, and the standing NPC-decomposition plan (memory: `npc-decomposition-plan`) shrinks that with zero forwarder tax. D is a legitimate answer; §5 prices C against it.

## 2. Chosen design: C-minimal

### 2.1 The move set — 45 of the 49 candidates, with 4 deliberate exclusions
**Excluded, stay inline on NPC (beyond the 13 must-stays):**
1. **`threat_response`** — it is runtime-MUTATED state, not pure tuning (`break_and_flee()` npc.gd:1172 writes it; PanicOnDamage triggers that). Keeping it inline removes: 2 typed readers (`npc_audio_cues.gd:44`, `weapon_stance.gd:63`), the enum-cycle wart (NpcTuning typing `NPC.ThreatResponse` would recreate the exact NpcData↔NPC cycle npc.gd:514-515 documents avoiding), the shared-resource FLEE-contagion hazard, and 1 line of the typed-test rewrite. Stamp line 566 (`as ThreatResponse` cast) stays as-is. Design rule this encodes: **runtime-written fields are state; state lives on the node**.
2. **`has_outline`, `outline_color`, `outline_width`** — cosmetic per-character identity (kin to `display_name`/`look`, not gameplay numbers), and 2 of the 3 are typed-read by `npc_outline.gd`. Excluding the trio takes npc_outline.gd out of the blast radius entirely.

**Moved (45):** friendly_aggro_threshold; Weapon×8 (muzzle_offset, weapon_mesh_rotation, rate_of_fire_factor, miss_chance, fire_range, target_height, immune_to_weapon_knockback, starts_unloaded); Group-AI×6; Perception×11; Laser×2; Movement×9; Behavior×8 (temperament, wanders, wander_radius, wander_dwell_min/max, flee_distance, talk_approach_distance/timeout).

**Deprecation rider (separate user decision, not bundled by default):** `laser_color` is dead — declared, stamped, listed, consumed by nothing (npc_laser.gd colors from `_outline_color_for_disposition()`). Recommend deleting it from NPC + NpcData + stamp + array instead of migrating it; no .tres sets it. If the user declines, it migrates like the rest.

### 2.2 New file: `scripts/npc/npc_tuning.gd` (~180-200 lines)
```gdscript
@tool
class_name NpcTuning
extends Resource
```
- All 45 `@export var`s **with their full doc-comments relocated verbatim** (CLAUDE.md: comments move with their fields), preserving the `@export_group` structure (Weapon/Group AI/Perception/Laser/Movement/Behavior) so the Inspector foldout reads exactly like the old flat block.
- Defaults live HERE — single home. npc.gd keeps zero tuning defaults.
- `func _init(): resource_local_to_scene = true` — every scene instantiation duplicates the sub-resource per instance. This is the load-bearing line: it makes profile-stamping, `break_and_flee`-class runtime writes (none in the 45 today, but future-proof), and harness `set()` calls per-instance instead of cross-NPC contamination.

### 2.3 npc.gd changes
- **Remove** the 45 declarations + docs (~132 lines) + 4 fully-emptied group headers (Group AI 145, Perception 178, Laser 205, Movement 211) + ~5 blank separators ≈ **141 lines out**. Behavior header stays (threat_response + enum + popup_positive remain under it — recon correction #2 honored).
- **Add** (~40 lines in):
  - `@export var tuning: NpcTuning = NpcTuning.new()` + rich doc-comment (the field initializer is a hard requirement: `_apply_profile` is line 1 of `_ready`, harnesses and .tscn loaders `set()` BEFORE add_child, and the static defaults probe `NPC.new()` at npc.gd:581 must see real defaults — a lazily-built resource poisons the static `_stamped_field_defaults` cache for every NPC thereafter).
  - A cached moved-name set derived from `NpcTuning.new().get_property_list()` (filter `PROPERTY_USAGE_SCRIPT_VARIABLE`) — no hand-maintained 45-name list to drift.
  - `_get(prop)` → `return tuning.get(prop)` when prop is in the set (null-guard tuning); `_set(prop, v)` → forward likewise. This keeps every duck contract alive **unchanged**: NpcCombat/NpcLocomotion/NpcTargeting/NpcVoice `host.<name>` reads, GOAP `host.temperament`/`host.search_sweep_rate`, `attack.gd:385` + `npc_combat.gd:171` `.get(&"immune_to_weapon_knockback")` (the highest-stakes silent-failure site), gizmo `_getf` editor reads, soak/combat-smoke `set()`, `_apply_profile`'s reflective `get(f)`/`set(f)`, and — decisively — the **staged Locomotor Phase B** `_tuning(body, &"jump_velocity", 0.0)` reads, which now survive with a one-line doc note instead of a repoint.
  - A 3-line defensive copy at the top of `_stamp_profile_full`: if `tuning.resource_path != "" and not tuning.resource_local_to_scene: tuning = tuning.duplicate()` — belt-and-suspenders for a designer who assigns a shared saved .tres and unchecks local_to_scene.
- **Rewrite in place** (no line-count delta): all ~40 internal reader/writer sites become `tuning.X` (bare `sight_range` inside the class is a compile error once undeclared — every site must be touched: `_build_perception` 1264-1270, `_ready` 444/451, `_shot_interval`, `_aim_range`, `_alert_allies`, noise emitters, `_move_toward`/`_try_nav_hop`, `_face_yaw`, `_pick_wander_point`, opt-in getters, `_aim_laser_at`, `apply_velocity`, `_current_move_speed`, temperament seed 757, noise-pulser copies 782-784). The 45 stamp lines become `tuning.X = profile.X`.
- **NO `_get_property_list()`** in the base design. Rationale: re-listing 45 flat names in the Inspector recreates the dual-authoring-surface trap (memory: `authoring-multiple-sources-of-truth`) — two places to edit the same value, with the flat one writing into a possibly-shared sub-resource pre-Make-Unique. Single surface = the nested resource foldout. Contingency below if the `in`-operator verification fails.

### 2.4 NpcData reconciliation — NpcData stays FLAT (no third source of truth)
The truth-source count is **unchanged at two**: NpcData remains the archetype default layer; NpcTuning becomes the per-instance live layer — the exact relationship that exists today, with only the stamp *destination* moved off the node onto its sub-resource. Nesting an NpcTuning inside NpcData (the "elegant" one-line-stamp option) was rejected: it compile-breaks `test_devtools_blueprint.gd:33-39` (typed NpcData), breaks `test_npc_data.gd:15-26/34-39/200-202` and the Scaffold/inspector-plugin writers, and forces data migration of 3 .tres + 3 inline NpcData sub-resources — roughly doubling the blast radius for zero behavioral gain, since the additive merge needs per-field granularity anyway. It remains available as a later, independent phase.

### 2.5 Scene migration — 7 files, 13 nodes, 112 lines (inventory already complete in recon)
Each affected node's flat lines are replaced with one `tuning = SubResource("NpcTuning_<n>")` plus a `[sub_resource]` block whose payload is the **derived-scene MERGE** (a Resource override replaces the whole resource): NPC.tscn root gets the 7-value default payload; every NPC.tscn-derived level node's payload = those 7 merged with its own overrides (recon's per-node "effective inherited" lists are exactly this). ~8 unique payloads cover all 13 nodes. Apply method: **hand-authored text patch** (not PackedScene re-save — preserves the nonstandard `unique_id=` node-header attributes recon flagged), editor closed. Safety net worth stating: because `_set` forwards, an accidentally-missed legacy .tscn still *loads* correctly (flat override lands in the per-instance initializer resource) — it only loses the values on a later editor re-save. The migration converts "silent revert" into "correct," but the safety net means a missed scene fails soft, not silent-at-runtime.

### 2.6 Test plan (deliberate rewrites: 2 files edited, 1 added; the rest pass through the forwarder)
- `tests/test_npc_data.gd:127-150` (drift test) — dual-arm regex: `^\t(\w+) = profile\.\w+` UNION `^\ttuning\.(\w+) = profile\.\w+`; keep the >50 sanity floor and both-ways set-equality. The three-way lockstep pin (NpcData ↔ stamp body ↔ array) survives in the new shape.
- `tests/test_npc_data.gd:104-124` — assert each stamped name is a real property of `npc` **or** of `npc.tuning` (property-list union). NpcData side (:122) unchanged.
- `tests/test_ranged_behavior.gd` — rewrite `e.wanders`/`e.wander_radius` to `e.tuning.*` (`e.threat_response` untouched — it stayed inline).
- **New** `tests/test_npc_tuning_forwarding.gd` — loops every NpcTuning script-variable name against a real off-tree `load(npc.gd).new()`: asserts `npc.get(name)` type-matches `NpcTuning.new().get(name)` and a `npc.set(name, probe)` round-trips. One loop pins all 45 forwarded names at once, closing recon §9's unpinned-name gap (flee_distance, dwell bounds, talk_approach_*, dodge quartet, muzzle_offset, …).
- Everything else in the recon summary table (test_enemies 17 default pins, test_npc, test_alert_propagation, test_combat_noise, test_hostility, test_npc_perception_config, test_stealth_sense_optin, the two `in`-guards, soak harnesses) is *designed* to pass unmodified via forwarder + initializer defaults. `test_authoring_warnings.gd:16-19` passes because the export defaults to a constructed resource and adds **no** configuration warning. `test_faction.gd:140-151` passes because there is no `_get_property_list` to shadow `faction_id`.

### 2.7 Other file touches
`weapon_stance.gd` (2 sites → `host.tuning.move_speed`), `talk_approach.gd` (3 sites → `host.tuning.*`), one-line note in `docs/audits/locomotor_phase_b_migration.md`, doc updates (`docs/CURRENT_ARCHITECTURE.md`, `docs/AUTHORING_GUIDE.md` — the "tune an NPC" designer steps now go through the tuning foldout + Make Unique for per-placed-instance tweaks — and `scripts/npc/README.md`). Total: **~16 files** (npc.gd, npc_tuning.gd NEW, 2 components, 2 test edits + 1 new test, 7 .tscn, 3-4 docs).

### 2.8 Apply gate + verify-at-apply checklist (stated plainly per the brief)
The new `class_name NpcTuning`, referenced as a typed `@export` in @tool npc.gd, must enter `global_script_class_cache.cfg` — **applying with the editor open risks the known empty-PackedScene / "Could not find type" cascade. The patch is EDITOR-CLOSED-gated: close editor → apply files → `godot --headless --import` (absolute --path) → headless compile → GUT (with user's go-ahead) → reopen editor.** At-apply verifications (all flagged unverifiable statically by recon): (1) 5-line scratch test that `"name" in npc` is satisfied by `_get` — if NOT, add the contingency `_get_property_list()` (~12 lines, EDITOR-usage-flag-free names, appended AFTER default enumeration so test_faction's first-match `faction_id` lookup stays correct); (2) gizmo sight-cone/alert-ring draws in-editor (forwarder under @tool); (3) two NPC.tscn instances side-by-side get isolated tuning (local_to_scene duplication); (4) soak/combat-smoke harness stamping lands; (5) re-read all written files post-apply (memory: writes can revert).

## 3. Honest math

| | Shape A | Shape B | **Shape C-minimal** |
|---|---|---|---|
| npc.gd lines removed | ~150 | ~20 | ~141 |
| npc.gd glue added | ~35-55 (+_get_property_list mandatory for tests) | ~15 | ~40 |
| **npc.gd net** | n/a — doesn't compile | **≈ −5** | **≈ −100 (2804 → ~2704, 3.6%)** |
| New file | ~205 lines | ~45 lines | ~190 lines (docs relocate here, they don't vanish) |
| Project net LOC | +~90 | +~40 | **+~90 — the project gets BIGGER** |
| Scenes | 7 files/13 nodes | 4 files | 7 files / 13 nodes / 112 lines |
| Code files touched | ~20 | ~10 | ~16 |
| In-place npc.gd edit sites | ~85 | ~10 | ~85 (40 readers + 45 stamp lines) |

No optimistic rounding: **C-minimal shrinks npc.gd by ~100 lines (3.6%) and grows the project by ~90.** The forwarder tax does not fully collapse the savings, but it reduces "shrink the god-object" to a rounding error against a 2804-line file whose real weight is logic, not declarations.

## 4. What C-minimal actually buys (the honest reason to do it)
Not line count. (a) **Tuning presets as .tres** — a "Sniper.tres"/"Raider.tres" NpcTuning payload becomes assignable/duplicable in one Inspector click, directly serving the OPEN "Raider/Sniper presets" item in the authoring-friction backlog and matching the SettingsCatalog data-driven pattern; (b) one designer surface for all combat/perception/movement numbers instead of a 260-line scroll; (c) the duck-read surface becomes *enumerated and pinned* (the new forwarding test) instead of implicit.

## 5. Cost of NOT doing it
Zero functional cost. The alternative use of the same risk budget — continuing the NpcDecomposition plan (extract behavior *functions* into drop-ins, flagship Locomotor Phase B) — removes several hundred logic lines with no forwarder, no scene migration, and no editor-closed gate.

---

**CHOSEN DESIGN:** Shape C-minimal — move 45 of 49 candidate exports into a new `NpcTuning` Resource (`scripts/npc/npc_tuning.gd`, `resource_local_to_scene = true`, defaults + relocated doc-comments live there), keep `threat_response` + the outline trio inline (runtime-state / cosmetic-identity rule), single `@export var tuning: NpcTuning = NpcTuning.new()` + generic `_get`/`_set` forwarder on npc.gd (no `_get_property_list`; single authoring surface), NpcData stays flat (still exactly two truth sources: archetype → per-instance), stamp body retargeted to `tuning.X = profile.X` with the drift test deliberately rewritten dual-regex, 2 typed components rewritten (`weapon_stance`, `talk_approach`), 7 scenes / 13 nodes / 112 override lines migrated to merged per-node sub-resources by hand-authored text patch, 1 new forwarding-pin test, editor-closed apply.

**NET NPC.GD SAVINGS (honest): ~100 lines, 2804 → ~2704 (−3.6%); project total grows by ~90 lines.**

**RECOMMENDATION:** Approve this only if you want what the Resource *is* — assignable/shareable NpcTuning presets (.tres) and a single collapsible tuning surface per NPC — because as a line-count play it is a bad trade: ~100 net lines off a 2804-line file, bought with a permanent `_get`/`_set` forwarder in an @tool god-object, resource-lifecycle subtleties (local_to_scene, copy-on-write stamping), a 16-file / 13-scene-node blast radius, an editor-closed apply window, and a Make-Unique step added to per-placed-instance tweaking. If your actual goal was shrinking npc.gd, reject this and spend the same budget on the standing decomposition plan (extracting behavior functions), which removes several times more lines with none of this tax; if the preset/authoring value appeals on its own, the design above is safe to build, and I'll draft the exact apply-ready patch (npc_tuning.gd, npc.gd diff, both component diffs, all 13 scene sub-resource payloads, and the three test changes) next.
---

# The apply-ready patch (as generated; apply with the header corrections)

All ground-truthing is complete (every edit-site read verbatim this session; Character declares none of the 45 names; npc.gd has no `_get`/`_set`/`_get_property_list`; civilian.tscn's only tuning-name override is `threat_response`, which stays inline — it **drops out of the scene migration**, correcting the inventory to **6 files / 12 nodes / 106 override lines**). The complete apply-ready patch follows.

---

# STAGED PATCH — NpcTuning migration (C-minimal). APPLY WITH THE EDITOR CLOSED.

**Why editor-closed:** `class_name NpcTuning`, referenced as a typed `@export` (and constructed at parse time via the field initializer) in @tool npc.gd, must enter `.godot/global_script_class_cache.cfg` before npc.gd can parse. Applying with the editor open risks the known empty-PackedScene / "Could not find type" cascade (npc.gd:766-770 documents this exact hazard class). Apply order and verification are in §9.

**Files touched (15):** `scripts/npc/npc_tuning.gd` (NEW), `scripts/npc/npc.gd`, `scripts/npc/weapon_stance.gd`, `scripts/npc/talk_approach.gd`, `tests/test_npc_data.gd`, `tests/test_ranged_behavior.gd`, `tests/test_npc_tuning_forwarding.gd` (NEW), 6 scenes (`scenes/enemies/NPC.tscn`, `scenes/medicine_person.tscn`, `scenes/TestLevel.tscn`, `scenes/TestLevel_2.tscn`, `scenes/levels/NavSandbox.tscn`, `scenes/levels/SliceTestLevel.tscn`), 2+ docs. **NOT touched (verified unnecessary):** `civilian.tscn` (its only override, `threat_response = 1`, stays a declared NPC export), `enemy.tscn`, `trenchboom_test_level.tscn`, `npc_outline.gd`, `npc_audio_cues.gd` (their typed reads — `has_outline`/`outline_width`/`threat_response` — all stayed inline), `npc_data.gd` (NpcData stays flat; still exactly two truth sources), `PROFILE_STAMPED_FIELDS` (array unchanged — the additive merge reaches moved names through the forwarder).

All line numbers = npc.gd as read this session (2,804 lines). All GDScript below uses TABS.

---

## §1. NEW FILE — `rpg/scripts/npc/npc_tuning.gd` (complete, 187 lines)

```gdscript
@tool
class_name NpcTuning
extends Resource

## An NPC's gameplay NUMBERS — weapon cadence/range, group-AI noise, perception, laser, movement and
## behavior knobs — split off the npc.gd root into ONE nested, assignable resource (the tuning-export
## migration). npc.gd keeps identity/content wiring (profile, look, faction, weapon_data, item_stacks,
## loot, popup_positive), runtime-mutated state (threat_response — break_and_flee() writes it), and the
## cosmetic outline trio; THIS resource owns every pure-tuning field an NpcData archetype stamps.
## Author a preset .tres ("Sniper", "Raider") once and assign it to many NPCs in one click, or tweak
## the nested sub-resource on a placed instance (Make Unique first if the editor shows a shared one).
##
## CONTRACTS (load-bearing — read before editing):
##   - DEFAULTS LIVE HERE, and they are THE NPC defaults (npc.gd declares no tuning defaults anymore).
##     They must keep matching NpcData's defaults — tests/test_npc_data.gd pins the parity.
##   - Components, GOAP actions, harnesses and tests still read/write these BY BARE NAME ON THE NPC
##     (host.sight_range, victim.get(&"immune_to_weapon_knockback"), npc.set(&"wanders", true)):
##     NPC._get/_set forwards every script variable declared here into this resource, and
##     tests/test_npc_tuning_forwarding.gd pins the round-trip for EVERY field. Adding a field here
##     auto-extends the forwarder (it enumerates this script's properties) — but a profile-driven field
##     also needs the matching NpcData export + a `tuning.X = profile.X` stamp line + a
##     PROFILE_STAMPED_FIELDS entry in npc.gd (the M7 lockstep contract).
##   - _init forces resource_local_to_scene ON (scene instantiation duplicates the payload per scene
##     instance) and NPC._ensure_tuning() additionally duplicates any runtime resource that still has a
##     resource_path — so profile stamping never mutates a shared .tres or another NPC's numbers.
##     Do not turn either guard off.
##   - Runtime-MUTATED per-NPC state does NOT belong here (that is why threat_response stayed on
##     npc.gd): fields here are written only by the Inspector and by profile stamping.

func _init() -> void:
	resource_local_to_scene = true  # every scene instantiation gets its OWN copy (see contract above)

@export_group("Hostility")
## Cumulative PLAYER damage a FRIENDLY NPC absorbs before it turns hostile. An ally forgives incidental
## hits (stray friendly-fire) — only being hurt past this much flips it; a neutral still aggros on the
## first hit. Higher = a more forgiving ally; 0 = turns on the first point of damage.
@export var friendly_aggro_threshold: float = 8.0

@export_group("Weapon")
## Local offset of the held gun's grip from the NPC origin — where the weapon view-model hangs (and
## the shot/laser origin when the model has no barrel marker of its own). This model faces +Z.
@export var muzzle_offset: Vector3 = Vector3(0.0, 0.0, 0.0)
## Corrective local rotation (degrees) for the held weapon model. View-models point their barrel down
## +X (e.g. ak_472), while this NPC faces +Z, so the default -90 deg yaw maps the gun's +X onto the
## NPC's forward. Tune per scene if a particular weapon needs a different grip pose.
@export var weapon_mesh_rotation: Vector3 = Vector3(0.0, -90.0, 0.0)
## Multiplies how long each shot takes: the NPC's fire cadence is the equipped WEAPON's attack_speed
## times this (1 = the weapon's own rate, >1 slower, <1 faster). The weapon is the single source of truth
## for the rate — tune per-NPC difficulty here instead of a duplicate cooldown. (Replaced fire_cooldown.)
@export var rate_of_fire_factor: float = 1.0
## Chance [0..1] that each shot AT THE PLAYER deflects wide and misses (plays a ricochet). 0 = never miss.
@export var miss_chance: float = 0.0
## Engagement-range FALLBACK for a weapon that sets NO effective_range (e.g. the thrown rock leaves it 0) —
## the engage distance is then min(this, GameSettings.npc_ai.unranged_aim_fallback). A weapon that DOES set effective_range
## scales the standoff itself (see NPC._engage_range), so this no longer caps a ranged weapon's reach.
@export var fire_range: float = 30.0
## Vertical nudge on the aim point (centre of the target's collision capsule). 0 = dead centre.
@export var target_height: float = 0.0
## Immune to this NPC's OWN weapon recoil (the weapon's self_knockback). Lets a heavy / anchored NPC
## fire a high-recoil weapon (e.g. the sniper) without being shoved around by it. Only the wielder's
## recoil is ignored — blasts, rams, and being shot by others still knock it back normally.
@export var immune_to_weapon_knockback: bool = false
## Start with an EMPTY clip, so the NPC must reload before its first shot — it keeps its gun unloaded
## until it engages. Off = starts loaded, as usual.
@export var starts_unloaded: bool = false

@export_group("Group AI (allies)")
## ALERT PROPAGATION (GA-1): on first-hand contact (this NPC goes ALERTED on a live target), it tells
## same-faction allies within this radius (m) to converge + investigate the threat — so a squad reacts
## together instead of fighting as solo islands. Latched once per engagement; an alerted ally does NOT
## re-broadcast (it only investigates), so there's no alert storm. 0 = OFF (no propagation — the default, so
## existing encounters are unchanged until a designer opts a guard in).
@export var alert_radius: float = 0.0
## Audible radius (m) of this NPC's GUNFIRE on the shared &"noise" channel — lets a guard two rooms away HEAR
## the firefight and come investigate, so combat is no longer silent to off-screen allies. INERT until a
## listener opts in (GameSettings.npc_ai.hearing_initiates, default off); 0 = this NPC's gunfire is silent.
@export var gunfire_noise_radius: float = 18.0
## Audible radius (m) of this NPC's DEATH on the &"noise" channel (a cry / thud allies can hear). 0 = silent.
@export var death_noise_radius: float = 12.0
## Min seconds between gunfire-noise pulses, so a full-auto burst emits a steady pulse instead of one
## NoiseSource per bullet. The death cry is one-shot and ignores this.
@export var combat_noise_interval: float = 0.4
## How fast each gunfire/death noise burst fades (m/s) and how long it lives (s) — keep it short, it's a
## momentary cue. lifetime is floored just above 0 so the source is always one-shot (never a leaking persistent one).
@export var combat_noise_decay: float = 0.0
@export var combat_noise_lifetime: float = 0.35

@export_group("Perception")
## How far the NPC can see.
@export var sight_range: float = 25.0
## Full view-cone angle (degrees). Outside this off its facing it simply can't see you.
@export var fov_degrees: float = 110.0
## Multiplier on sight_range while you're fully crouched — stealth: 1.0 = crouch doesn't help; 0.5 = spotted
## only at half range when fully crouched. Mirrored onto Perception in NPC._build_perception (the per-archetype fix).
@export_range(0.0, 1.0) var crouch_sight_mult: float = 0.5
## Seconds in view before it's fully alerted — your reaction window.
@export var time_to_detect: float = 1.0
## Seconds it stays wary at your last-known spot before giving up.
@export var forget_time: float = 4.0
## Eye height the sight / LOS rays start from.
@export var eye_height: float = 1.4
## Hear the player's noise (gunfire, fast movement) even outside the cone? Crouch is silent.
@export var hearing: bool = true
## How fast it rotates to face what it's looking at.
@export var turn_speed: float = 8.0
## The investigation look-around: once arrived at the last-known spot, the facing sweeps in a slow circle
## hunting for the target (rad/s — at 0.8 a full turn takes ~8s, so a 4s forget_time reads as a half-circle
## scan before giving up). Designer-tunable per NPC in the inspector, like the Perception ranges.
@export var search_sweep_rate: float = 0.8
## Per-NPC STEALTH-SENSE opt-in, OR'd with the global GameSettings.npc_ai gates: turn this ONE NPC's body-
## discovery / noise-hearing on by itself, leaving the rest of the cast oblivious. Off = follow the global flag.
@export var body_discovery_opt_in: bool = false
@export var hearing_initiates_opt_in: bool = false

@export_group("Laser")
## Draw a laser sight that brightens as it detects / locks onto you (combatants only).
@export var show_laser: bool = true
## Laser sight colour.
@export var laser_color: Color = Color(1.0, 0.1, 0.1)

@export_group("Movement")
## How fast it walks / chases (m/s).
@export var move_speed: float = 4.0
## Ground acceleration — also how fast it sheds knockback / brakes to a stop (m/s^2).
@export var move_accel: float = 25.0
## Air acceleration (low, so a blast carries it before it recovers) (m/s^2).
@export var air_accel: float = 2.0
## Alerted: closes until the target is within this fraction of the weapon's effective range,
## then holds and fires (so it actually gets in range to hit).
@export var engage_range_fraction: float = 0.9
## Minimum upward impulse (m/s) for vaulting onto a higher spot the NPC can't walk up -- chiefly YOU perched on a low
## crate/ledge the navmesh treats as unreachable (also a baked ledge or up navigation-link, if a level provides one).
## Default 4.5 matches the Player's basic jump; when the target is higher, the NPC computes the stronger launch
## needed to reach that height plus a small clearance margin. Set 0 to disable jumping for this NPC. Only a
## THREATENING-pursuit NPC hops (chasing/searching/escorting, not a passing civilian), only AT the step, on the
## floor, and behind a cooldown, so it chases you up a ledge without jump-spamming while it is still running in.
@export var jump_velocity: float = 4.5
## Combat dodge (Feature #5): while ALERTED on a live target, every dodge_interval seconds the enemy
## rolls dodge_chance to break into a brief lateral STRAFE (left or right relative to the target) for
## dodge_duration, instead of standing still — so it's a harder target without constant jittering. The
## strafe drives _desired_velocity at dodge_speed_fraction of move_speed through the normal locomotion
## (pathing is untouched — pursuit resumes the instant the burst ends). 0 chance disables it entirely.
## Seconds between combat-dodge ROLLS. NpcCombat floors it to its DODGE_MIN_INTERVAL so an over-tuned value (e.g. 1.0
## on a "raider") can't make the NPC strafe almost every second — constant pacing, the exact thing this feature is
## meant to AVOID. Set dodge_chance = 0 for none.
@export var dodge_interval: float = 2.5
## Probability [0..1] each dodge roll fires, breaking into a lateral strafe to be a harder target. 0 = never dodge (disables the combat dodge entirely).
@export_range(0.0, 1.0) var dodge_chance: float = 0.5
## How long (seconds) each dodge strafe lasts before pursuit resumes. Higher = longer side-steps.
@export var dodge_duration: float = 0.35
## Strafe speed during a dodge, as a fraction of move_speed. 1.0 = full speed sideways; lower = a slower shuffle.
@export var dodge_speed_fraction: float = 1.0

@export_group("Behavior")
## How readily this NPC BREAKS and flees once it takes damage in a fight [0..1]. 0 = fearless (never
## flees from being hurt); 1 = cowardly. The flee chance per damaging hit scales with how hurt it is
## (temperament * fraction of HP lost), so a coward bolts as the fight turns against it. This SEEDS the
## auto-built PanicOnDamage drop-in (panic_on_damage.gd), which owns the actual roll; drop a configured
## PanicOnDamage in the scene to override it per-NPC.
@export var temperament: float = 0.0
## Roam near the spawn point while idle (no hostile target) instead of standing still.
@export var wanders: bool = false
## How far from the spawn point wandering may stray (metres).
@export var wander_radius: float = 6.0
## Seconds to linger at each wander stop before picking a new spot (randomised across this range).
@export var wander_dwell_min: float = 1.5
## Upper bound (seconds) of the wander-stop linger; the actual dwell is random between wander_dwell_min and this. Wider gap = less predictable pacing.
@export var wander_dwell_max: float = 4.0
## When fleeing, how far ahead (metres) to aim each step away from the threat.
@export var flee_distance: float = 12.0
## When the player talks to this (non-hostile) NPC, it walks to within this distance of the player
## before speaking, so the conversation is adequately framed (see prompt_talk -> the TalkApproach child).
## 0 => speak in place (no approach). Keep <= the ray's TALK_REACH (3.5 m) or it never needs to move.
@export var talk_approach_distance: float = 2.5
## Safety cap (seconds) on the pre-talk approach: if the path is blocked / the player keeps backing
## away, the NPC gives up closing and speaks from wherever it got to, rather than chasing forever.
@export var talk_approach_timeout: float = 4.0
```

*(Every doc-comment above is relocated verbatim from npc.gd, per CLAUDE.md; the only text changes are `_engage_range`→`NPC._engage_range` and `_build_perception`→`NPC._build_perception` cross-references, which would otherwise dangle.)*

**Deprecation rider (separate decision, NOT applied by this patch):** `laser_color` is dead — declared, stamped, listed, consumed by nothing (npc_laser.gd tints from `_outline_color_for_disposition()`; no .tres or .tscn sets it). Recommend deleting it from NpcTuning above + NpcData + the stamp line + PROFILE_STAMPED_FIELDS in a follow-up. This patch migrates it as-is so the migration stays behavior-neutral.

---

## §2. `rpg/scripts/npc/npc.gd`

### E1 — Tuning export (INSERT after line 26 `@export var goap_profile: GoapProfile = null`, before line 27's blank + `@export_group("Body & Head")`)

```gdscript

@export_group("Tuning")
## ALL of this NPC's gameplay NUMBERS — weapon cadence/range, group-AI noise radii, perception, laser,
## movement, wander/flee/talk-approach behavior — live on this ONE nested resource (npc_tuning.gd),
## stamped by an NpcData profile exactly like the old flat exports were. Every NPC gets its OWN copy at
## spawn (resource_local_to_scene + _ensure_tuning), so profile stamping / per-instance tweaks never
## bleed across NPCs. Authoring: expand the foldout to tune THIS NPC (on a placed instance, Make Unique
## first if the editor shows a shared resource), or assign a saved preset .tres ("Sniper", "Raider") to
## reuse one payload across many NPCs. Components / GOAP / harnesses / tests keep reading these fields
## off the NPC itself by bare name (host.sight_range, npc.set(&"wanders", true)) — see the NpcTuning
## forwarding block below _validate_property.
@export var tuning: NpcTuning = NpcTuning.new()
```

The field **initializer is load-bearing**: `_apply_profile` is line 1 of `_ready`; harnesses and legacy .tscn overrides `set()` moved names BEFORE `add_child`; and the static defaults probe (`NPC.new()` at `_npc_stamped_defaults`) must see real defaults — a lazily-built resource would poison the static `_stamped_field_defaults` cache for every NPC thereafter.

### E2 — class-doc freshness (REPLACE lines 57–58)

OLD:
```gdscript
## Designer surface: drop the scene in, optionally point weapon_data at a .tres, set faction /
## disposition / threat_response / wanders, and tune the perception + firing values in the inspector.
```
NEW:
```gdscript
## Designer surface: drop the scene in, optionally point weapon_data at a .tres, set faction /
## disposition / threat_response, and tune the perception + firing + wander numbers on the nested
## `tuning` resource (NpcTuning) in the inspector — or assign a saved NpcTuning preset .tres.
```

### E3 — DELETE `friendly_aggro_threshold` (lines 102–105) and repoint the `_player_aggression` comment (106–107)

DELETE these 4 lines exactly (relocated to npc_tuning.gd §1):
```gdscript
## Cumulative PLAYER damage a FRIENDLY NPC absorbs before it turns hostile. An ally forgives incidental
## hits (stray friendly-fire) — only being hurt past this much flips it; a neutral still aggros on the
## first hit. Higher = a more forgiving ally; 0 = turns on the first point of damage.
@export var friendly_aggro_threshold: float = 8.0
```
REPLACE the two comment lines that followed (106–107):
```gdscript
## Cumulative player damage taken WHILE FRIENDLY, counting toward friendly_aggro_threshold; once it crosses, the
## NPC is provoked. Not used in npc.gd itself — the ProvokeOnAttack component (provoke_on_attack.gd) accumulates it.
```
WITH:
```gdscript
## Cumulative player damage taken WHILE FRIENDLY, counting toward tuning.friendly_aggro_threshold; once it
## crosses, the NPC is provoked. Not used in npc.gd itself — the ProvokeOnAttack component
## (provoke_on_attack.gd) accumulates it, reading both off the host (the threshold via the NpcTuning forwarder).
```

### E4 — Weapon group: DELETE lines 118–143 (everything after `@export var weapon_data: WeaponData = null` at 117, from `## Local offset of the held gun's grip…` through `@export var starts_unloaded: bool = false`). All 26 lines relocated to §1.

### E5 — DELETE lines 144–164 (the blank line + the entire `@export_group("Group AI (allies)")` block through `@export var combat_noise_lifetime: float = 0.35`). 21 lines → §1.
*(Inventory group 166–170 and Loot group 172–176 stay untouched.)*

### E6 — DELETE lines 177–203 (the blank line + the entire `@export_group("Perception")` block through `@export var hearing_initiates_opt_in: bool = false`). 27 lines → §1.

### E7 — DELETE lines 204–209 (blank + entire `@export_group("Laser")` block). 6 lines → §1.

### E8 — DELETE lines 210–242 (blank + entire `@export_group("Movement")` block through `@export var dodge_speed_fraction: float = 1.0`). 33 lines → §1.

### E9 — Behavior group tail: DELETE lines 251–273 (from `## How readily this NPC BREAKS and flees…` through `@export var talk_approach_timeout: float = 4.0`). 23 lines → §1. **KEEP** lines 244–250 (the `@export_group("Behavior")` header, the `enum ThreatResponse` + both docs, and `@export var threat_response: ThreatResponse = ThreatResponse.FIGHT`) — `threat_response` is runtime-mutated state (`break_and_flee()` writes it at what is now ~line 1172) and stays declared. `popup_positive` (309) keeps displaying under Behavior because this header survives.

### E10 — Forwarder + `_ensure_tuning` (INSERT after `_validate_property`, i.e. after line 422 `property.hint_string = Factions.ids_csv()`, before the blank line + `func _ready()`)

```gdscript

## --- NpcTuning forwarding (the tuning-export migration seam) ------------------------------------------
## The gameplay numbers moved off this root onto the nested `tuning` resource (npc_tuning.gd), but a wide
## duck-typed surface still reads/writes them ON THE NPC by bare name: Node-typed components (npc_combat /
## npc_locomotion / npc_targeting read host.miss_chance / host.wanders / host.sight_range), GOAP actions
## (host.temperament, host.search_sweep_rate), attack.gd + npc_combat.gd's .get(&"immune_to_weapon_knockback"),
## the editor gizmo's _getf(npc, &"sight_range", ...), harness npc.set(&"sight_range", ...) BEFORE add_child,
## legacy .tscn flat overrides applied at scene load, and _apply_profile's own reflective get(f)/set(f).
## _get/_set forward every name NpcTuning declares into the resource so ALL of those keep resolving
## unchanged. Godot calls _get/_set only for UNDECLARED names, so declared NPC properties (and their
## performance) are untouched; only moved names pay the one-hop forward. The name set is enumerated from
## NpcTuning itself (script variables), so adding a field there auto-extends this — no list to drift.
## All NpcTuning fields are value types (float/bool/Vector3/Color), so a non-nil return from _get is
## guaranteed for a known name and nil cleanly means "not handled". Pinned end-to-end by
## tests/test_npc_tuning_forwarding.gd.
static var _tuning_prop_names: Dictionary = {}

static func _tuning_props() -> Dictionary:
	if _tuning_prop_names.is_empty():
		var probe := NpcTuning.new()
		for p in probe.get_property_list():
			if (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
				_tuning_prop_names[StringName(p.name)] = true
	return _tuning_prop_names

func _get(property: StringName) -> Variant:
	if tuning != null and _tuning_props().has(property):
		return tuning.get(property)
	return null  # nil = "not handled" -> normal lookup / error semantics for genuinely unknown names

func _set(property: StringName, value: Variant) -> bool:
	if tuning != null and _tuning_props().has(property):
		tuning.set(property, value)
		return true
	return false

## The tuning resource must ALWAYS exist and be THIS NPC's own. The export's field initializer covers
## bare .new() (off-tree tests, the _npc_stamped_defaults probe, harnesses) and scene loads; this guard
## covers the designer who nulls the slot, and duplicates any runtime resource that still carries a
## resource_path — a saved preset .tres OR a scene-embedded sub-resource other nodes in the level may
## reference (resource_local_to_scene duplicates per SCENE INSTANCE, not per node within one scene) — so
## profile stamping / runtime writes never bleed across NPCs or back into an asset. duplicate() clears
## the path, so this runs at most once per NPC. Called from _ready (runtime only — the editor keeps
## editing the authored resource) and from _stamp_profile_full (off-tree tests call _apply_profile
## directly, with no _ready).
func _ensure_tuning() -> void:
	if tuning == null:
		tuning = NpcTuning.new()
		return
	if tuning.resource_path != "":
		tuning = tuning.duplicate()
```

### E11 — `_ready` (REPLACE line 427)

OLD:
```gdscript
	_apply_profile()  # stamp an assigned NpcData archetype onto our exports FIRST — before super() seeds hp from max_hp, and before the components / perception / weapon branch read the rest
```
NEW:
```gdscript
	_ensure_tuning()  # the per-instance tuning copy must exist BEFORE anything stamps into or reads it
	_apply_profile()  # stamp an assigned NpcData archetype onto our exports FIRST — before super() seeds hp from max_hp, and before the components / perception / weapon branch read the rest
```

### E12 — `_ready` weapon branch (REPLACE lines 446 and 453)

OLD → NEW:
```gdscript
		_muzzle.position = muzzle_offset
```
```gdscript
		_muzzle.position = tuning.muzzle_offset
```
OLD → NEW:
```gdscript
		if starts_unloaded and _weapon.ammo:
```
```gdscript
		if tuning.starts_unloaded and _weapon.ammo:
```

### E13 — `PROFILE_STAMPED_FIELDS` doc (REPLACE lines 473–474; the array body 475–486 is UNCHANGED)

OLD:
```gdscript
## The NPC fields an NpcData profile stamps. The additive merge (profile_fills_blanks_only) snapshots/restores
## these; the full-clobber path sets them in _stamp_profile_full. Keep in sync with _stamp_profile_full.
```
NEW:
```gdscript
## The NPC fields an NpcData profile stamps. The additive merge (profile_fills_blanks_only) snapshots/restores
## these; the full-clobber path sets them in _stamp_profile_full. Keep in sync with _stamp_profile_full.
## Names that moved onto the NpcTuning sub-resource still resolve here through the _get/_set forwarder,
## so this array stays FLAT StringNames — do not prefix entries with "tuning.".
```

### E14 — `_stamp_profile_full` (REPLACE the doc lines 514–520 AND the whole body 521–576)

NEW doc + body (order of assignments preserved exactly — including `goap_profile` between `dodge_interval` and `dodge_chance`, and `threat_response` between `dodge_speed_fraction` and `temperament` — so review diffs stay 1:1):

```gdscript
## Copy every stamped field from the profile onto us -- the authoritative full-clobber path (also the body the
## additive merge runs before restoring overrides). Reached only with profile != null (both callers guard).
## threat_response copies int -> the ThreatResponse enum (NpcData stores it as an int to avoid an NpcData <-> NPC
## class cycle). Pure-tuning fields live on the NpcTuning sub-resource, so their lines are `tuning.X = profile.X`
## (never into a shared resource — _ensure_tuning below); identity/content/state fields stay bare `X = profile.X`.
## M7: keep this body's assignments and PROFILE_STAMPED_FIELDS a MATCHED SET — the additive merge iterates
## that array, so a field stamped here but missing from it silently drops the inline override. tests/test_npc_data.gd
## asserts the set-equality BOTH ways (its regex captures BOTH line shapes).
func _stamp_profile_full() -> void:
	_ensure_tuning()  # never stamp into a shared saved .tres / scene sub-resource (off-tree callers skip _ready's ensure)
	display_name = profile.display_name
	popup_positive = profile.popup_positive
	max_hp = profile.max_hp
	armor_flat = profile.armor_flat            # CT-2 mitigation mirror
	damage_reduction = profile.damage_reduction
	zone_damage_mult = profile.zone_damage_mult
	stats = profile.stats  # archetype stat sheet -> _apply_stats (in super() below) stamps endurance/strength
	has_outline = profile.has_outline
	outline_color = profile.outline_color
	outline_width = profile.outline_width
	faction_id = profile.faction_id
	faction = profile.faction
	disposition = profile.disposition
	disposition_overrides_faction = profile.disposition_overrides_faction
	tuning.friendly_aggro_threshold = profile.friendly_aggro_threshold
	weapon_data = profile.weapon_data
	tuning.muzzle_offset = profile.muzzle_offset
	tuning.weapon_mesh_rotation = profile.weapon_mesh_rotation
	tuning.rate_of_fire_factor = profile.rate_of_fire_factor
	tuning.miss_chance = profile.miss_chance
	tuning.fire_range = profile.fire_range
	tuning.target_height = profile.target_height
	tuning.immune_to_weapon_knockback = profile.immune_to_weapon_knockback
	tuning.starts_unloaded = profile.starts_unloaded
	item_stacks = profile.item_stacks
	tuning.sight_range = profile.sight_range
	tuning.fov_degrees = profile.fov_degrees
	tuning.crouch_sight_mult = profile.crouch_sight_mult
	tuning.time_to_detect = profile.time_to_detect
	tuning.forget_time = profile.forget_time
	tuning.eye_height = profile.eye_height
	tuning.hearing = profile.hearing
	tuning.turn_speed = profile.turn_speed
	tuning.search_sweep_rate = profile.search_sweep_rate
	tuning.show_laser = profile.show_laser
	tuning.laser_color = profile.laser_color
	tuning.move_speed = profile.move_speed
	tuning.move_accel = profile.move_accel
	tuning.air_accel = profile.air_accel
	tuning.engage_range_fraction = profile.engage_range_fraction
	tuning.jump_velocity = profile.jump_velocity
	tuning.dodge_interval = profile.dodge_interval
	goap_profile = profile.goap_profile
	tuning.dodge_chance = profile.dodge_chance
	tuning.dodge_duration = profile.dodge_duration
	tuning.dodge_speed_fraction = profile.dodge_speed_fraction
	threat_response = profile.threat_response as ThreatResponse
	tuning.temperament = profile.temperament
	tuning.wanders = profile.wanders
	tuning.wander_radius = profile.wander_radius
	tuning.wander_dwell_min = profile.wander_dwell_min
	tuning.wander_dwell_max = profile.wander_dwell_max
	tuning.flee_distance = profile.flee_distance
	tuning.talk_approach_distance = profile.talk_approach_distance
	tuning.talk_approach_timeout = profile.talk_approach_timeout
```
(18 bare lines + 37 `tuning.` lines = 55 assignments, matching the unchanged 55-entry array.)

### E15–E31 — internal reader rewrites (each OLD line → NEW line, verbatim)

| # | Line | OLD | NEW |
|---|---|---|---|
| E15 | 759 | `p.panic_scale = temperament  # \`temperament\` stays the authored fear source; it seeds the auto-added component` | `p.panic_scale = tuning.temperament  # \`temperament\` (on the tuning resource) stays the authored fear source; it seeds the auto-added component` |
| E16 | 784 | `_noise_pulser.decay = combat_noise_decay` | `_noise_pulser.decay = tuning.combat_noise_decay` |
| E17 | 785 | `_noise_pulser.lifetime = combat_noise_lifetime` | `_noise_pulser.lifetime = tuning.combat_noise_lifetime` |
| E18 | 786 | `_noise_pulser.min_interval = combat_noise_interval  # the throttle now lives on the pulser` | `_noise_pulser.min_interval = tuning.combat_noise_interval  # the throttle now lives on the pulser` |
| E19 | 1015 | `_noise_pulser.pulse(gunfire_noise_radius, true)  # throttled: fold rapid shots into one pulse` | `_noise_pulser.pulse(tuning.gunfire_noise_radius, true)  # throttled: fold rapid shots into one pulse` |
| E20 | 1019 | `_noise_pulser.pulse(death_noise_radius, false)  # a one-off death cry/thud allies can hear — never throttled` | `_noise_pulser.pulse(tuning.death_noise_radius, false)  # a one-off death cry/thud allies can hear — never throttled` |
| E21 | 1266–1272 | `_perception.sight_range = sight_range` … `_perception.hearing = hearing` (7 lines) | `_perception.sight_range = tuning.sight_range` / `_perception.fov_degrees = tuning.fov_degrees` / `_perception.crouch_sight_mult = tuning.crouch_sight_mult  # Slice 0b: was never copied -> silently stuck at 0.5` / `_perception.time_to_detect = tuning.time_to_detect` / `_perception.forget_time = tuning.forget_time` / `_perception.eye_height = tuning.eye_height` / `_perception.hearing = tuning.hearing` |
| E22 | 1520 | `if alert_radius <= 0.0 or not is_inside_tree():` | `if tuning.alert_radius <= 0.0 or not is_inside_tree():` |
| E23 | 1527 | `if should_alert_ally(faction, global_position, alert_radius, ally.faction, ally.global_position, not ally._dead and ally.hp > 0.0):` | `if should_alert_ally(faction, global_position, tuning.alert_radius, ally.faction, ally.global_position, not ally._dead and ally.hp > 0.0):` |
| E24 | 2045 | `if should_nav_hop(allow_hop, jump_velocity, is_on_floor(), _jump_cd, hop_climb, hop_horizontal):` | `if should_nav_hop(allow_hop, tuning.jump_velocity, is_on_floor(), _jump_cd, hop_climb, hop_horizontal):` |
| E25 | 2046 | `velocity.y = jump_velocity_for_climb(hop_climb, get_gravity().y, jump_velocity)` | `velocity.y = jump_velocity_for_climb(hop_climb, get_gravity().y, tuning.jump_velocity)` |
| E26 | 2055 | `if not should_nav_hop(allow_hop, jump_velocity, is_on_floor(), _jump_cd, climb, horizontal_distance):` | `if not should_nav_hop(allow_hop, tuning.jump_velocity, is_on_floor(), _jump_cd, climb, horizontal_distance):` |
| E27 | 2057 | `velocity.y = jump_velocity_for_climb(climb, get_gravity().y, jump_velocity)` | `velocity.y = jump_velocity_for_climb(climb, get_gravity().y, tuning.jump_velocity)` |
| E28 | 2083 | `var r := sqrt(randf()) * wander_radius` | `var r := sqrt(randf()) * tuning.wander_radius` |
| E29 | 2085 | `return _snap_to_navmesh(p, wander_radius + 2.0)` | `return _snap_to_navmesh(p, tuning.wander_radius + 2.0)` |
| E30 | 2149 | `var rate := move_accel if is_on_floor() else air_accel` | `var rate := tuning.move_accel if is_on_floor() else tuning.air_accel` |
| E31 | 2273 | `rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))` | `rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-tuning.turn_speed * delta))` |
| E32 | 2315 | `return GameSettings.npc_ai.hearing_initiates or hearing_initiates_opt_in` | `return GameSettings.npc_ai.hearing_initiates or tuning.hearing_initiates_opt_in` |
| E33 | 2325 | `return GameSettings.npc_ai.body_discovery or body_discovery_opt_in` | `return GameSettings.npc_ai.body_discovery or tuning.body_discovery_opt_in` |
| E34 | 2403 | `return node.global_position + Vector3.UP * target_height` | `return node.global_position + Vector3.UP * tuning.target_height` |
| E35 | 2434 | `return minf(fire_range, GameSettings.npc_ai.unranged_aim_fallback)` | `return minf(tuning.fire_range, GameSettings.npc_ai.unranged_aim_fallback)` |
| E36 | 2443 | `return maxf(0.05, FISTS.attack_speed * rate_of_fire_factor)` | `return maxf(0.05, FISTS.attack_speed * tuning.rate_of_fire_factor)` |
| E37 | 2446 | `return maxf(0.05, base * rate_of_fire_factor)` | `return maxf(0.05, base * tuning.rate_of_fire_factor)` |
| E38 | 2488 | `_weapon_mesh.rotation_degrees = weapon_mesh_rotation` | `_weapon_mesh.rotation_degrees = tuning.weapon_mesh_rotation` |
| E39 | 2552 | `var base: float = _stance.current_move_speed() if _stance != null else move_speed` | `var base: float = _stance.current_move_speed() if _stance != null else tuning.move_speed` |
| E40 | 2608 | `return global_position + Vector3.UP * eye_height` | `return global_position + Vector3.UP * tuning.eye_height` |
| E41 | 2762 | `if not show_laser or _laser == null or not _current_weapon_has_laser_sight():` | `if not tuning.show_laser or _laser == null or not _current_weapon_has_laser_sight():` |

That is the **complete** set of internal sites — verified by an exhaustive 45-name grep of npc.gd this session; every other hit is a comment, the stamp body (E14), or the array (unchanged). Any bare name left behind is a **compile error** (loud, not silent), so the headless compile in §9 is the backstop.

---

## §3. `rpg/scripts/npc/weapon_stance.gd` (host: NPC — typed, compile-coupled)

REPLACE lines 103–106:
```gdscript
func current_move_speed() -> float:
	if host._weapon != null and not host._weapon.attack.holstered and host._weapon.equipped_weapon:
		return host.move_speed * host._weapon.equipped_weapon.move_speed_multiplier
	return host.move_speed
```
WITH:
```gdscript
func current_move_speed() -> float:
	if host._weapon != null and not host._weapon.attack.holstered and host._weapon.equipped_weapon:
		return host.tuning.move_speed * host._weapon.equipped_weapon.move_speed_multiplier
	return host.tuning.move_speed
```
Line 63 (`host.threat_response == NPC.ThreatResponse.FIGHT`) is UNCHANGED — `threat_response` stayed on the root. Lines 22/32/67/97 mention `starts_unloaded` in comments only (verified) — leave them.

## §4. `rpg/scripts/npc/talk_approach.gd` (host: NPC — typed)

REPLACE line 59:
```gdscript
	if host.is_on_floor() and (host.talk_approach_distance <= 0.0 or host.global_position.distance_to(player.global_position) <= host.talk_approach_distance):
```
WITH:
```gdscript
	if host.is_on_floor() and (host.tuning.talk_approach_distance <= 0.0 or host.global_position.distance_to(player.global_position) <= host.tuning.talk_approach_distance):
```
REPLACE line 66:
```gdscript
	_timeout = host.talk_approach_timeout
```
WITH:
```gdscript
	_timeout = host.tuning.talk_approach_timeout
```
REPLACE line 86:
```gdscript
	if host.talk_approach_distance > 0.0 and flat.length() > host.talk_approach_distance:
```
WITH:
```gdscript
	if host.tuning.talk_approach_distance > 0.0 and flat.length() > host.tuning.talk_approach_distance:
```

---

## §5. Tests

### 5a. `rpg/tests/test_npc_data.gd` — REPLACE `test_profile_stamped_fields_all_resolve_on_npc_and_npcdata` (lines 112–124)

```gdscript
func test_profile_stamped_fields_all_resolve_on_npc_and_npcdata() -> void:
	# The additive merge snapshots/restores PROFILE_STAMPED_FIELDS by name via get()/set(); a typo or renamed
	# field would silently fail to preserve an override. Pin every name to a real property on the NpcData it
	# reads from, and on the NPC side to either a declared NPC property or an NpcTuning property — the moved
	# tuning names reach the NPC through its _get/_set forwarder, whose end-to-end round-trip is pinned
	# separately in tests/test_npc_tuning_forwarding.gd.
	var n = load(NPC_PATH).new()
	var d := NpcData.new()
	var npc_props := _prop_names(n)
	npc_props.merge(_prop_names(n.tuning))  # forwarded names are real properties of the nested tuning resource
	var nd_props := _prop_names(d)
	for f in NPC.PROFILE_STAMPED_FIELDS:
		assert_true(npc_props.has(String(f)), "stamped field '%s' must be a real NPC (or NPC.tuning) property" % f)
		assert_true(nd_props.has(String(f)), "stamped field '%s' must be a real NpcData property" % f)
	n.free()
	d = null
```

### 5b. `rpg/tests/test_npc_data.gd` — the drift test (lines 127–150): ONE line + its comment change

REPLACE the comment block lines 128–132 with:
```gdscript
	# M7: three lists must stay in lockstep — NpcData exports, _stamp_profile_full's assignments, and
	# PROFILE_STAMPED_FIELDS (which the additive-merge snapshot/restore iterates). The test above pins array ->
	# property; THIS pins _stamp_profile_full <-> PROFILE_STAMPED_FIELDS by SET-EQUALITY. Since the tuning
	# migration the stamp body has TWO line shapes — `X = profile.X` (fields still declared on the NPC root)
	# and `tuning.X = profile.X` (fields moved onto the NpcTuning sub-resource) — and the regex captures the
	# field name from EITHER. A field added to NpcData + the stamp body but forgotten in the array compiles +
	# passes the full-clobber path, yet silently DROPS the inline override on the additive-merge path (no
	# signal). Both directions catch it.
```
REPLACE line 139:
```gdscript
	re.compile("(?m)^\\t(\\w+) = profile\\.\\w+")  # every `<field> = profile.<field>` assignment in the stamp body
```
WITH:
```gdscript
	re.compile("(?m)^\\t(?:tuning\\.)?(\\w+) = profile\\.\\w+")  # both stamp shapes; group 1 = the field name either way
```
Everything else in the function — including the `> 50` sanity floor (still true: 55 captured assignments) and both set-equality loops — is UNCHANGED. The three-way lockstep pin (NpcData ↔ stamp body ↔ array) survives at full strength.

### 5c. `rpg/tests/test_ranged_behavior.gd` — 4 line edits (typed `e: NPC` → must go through the declared `tuning`)

| Line | OLD | NEW |
|---|---|---|
| 15 | `assert_false(e.wanders, "wandering is opt-in; default off so plain enemies hold their post")` | `assert_false(e.tuning.wanders, "wandering is opt-in; default off so plain enemies hold their post")` |
| 21 | `e.wander_radius = 6.0` | `e.tuning.wander_radius = 6.0` |
| 26 | `assert_true(flat.length() <= e.wander_radius + 0.001,` | `assert_true(flat.length() <= e.tuning.wander_radius + 0.001,` |
| 35 | `e.wander_radius = 0.0` | `e.tuning.wander_radius = 0.0` |

Line 13 (`e.threat_response`) is UNCHANGED (stayed declared).

### 5d. NEW FILE — `rpg/tests/test_npc_tuning_forwarding.gd`

```gdscript
extends GutTest

## NpcTuning forwarding contract — the tuning-export migration's load-bearing seam. Every gameplay number
## that moved off npc.gd onto the nested NpcTuning resource is STILL read/written on the NPC itself by
## bare name across the codebase (Node-typed components: host.miss_chance / host.wanders / host.sight_range;
## GOAP: host.temperament / host.search_sweep_rate; attack.gd + npc_combat.gd:
## .get(&"immune_to_weapon_knockback"); harnesses: npc.set(&"sight_range", ...) BEFORE add_child; the
## editor gizmo's _getf). Those resolve through NPC._get/_set — and a forwarder MISS is a SILENT failure
## (get() returns nil, set() no-ops), so this suite enumerates EVERY NpcTuning script variable against a
## real off-tree NPC (load().new(), no _ready — the standard pattern) and pins the round-trip. One loop
## covers all names, so a field added to NpcTuning is pinned automatically.

const NPC_PATH := "res://scripts/npc/npc.gd"

func _tuning_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for p in NpcTuning.new().get_property_list():
		if (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			names.append(StringName(p.name))
	return names

## A same-type value guaranteed != the current one, per forwarded field type.
func _probe_value_for(current: Variant) -> Variant:
	match typeof(current):
		TYPE_FLOAT:
			return (current as float) + 17.5
		TYPE_BOOL:
			return not current
		TYPE_VECTOR3:
			return (current as Vector3) + Vector3(1.0, 2.0, 3.0)
		TYPE_COLOR:
			return Color(0.123, 0.456, 0.789, 1.0)
		_:
			return current  # unreached for today's field set; extend when NpcTuning gains a new type

func test_every_tuning_field_reads_through_the_npc() -> void:
	var npc = load(NPC_PATH).new()
	var defaults := NpcTuning.new()
	var names := _tuning_names()
	assert_gt(names.size(), 40, "sanity: NpcTuning should declare the ~45 migrated fields")
	for name in names:
		var via_npc: Variant = npc.get(name)
		var expected: Variant = defaults.get(name)
		assert_eq(typeof(via_npc), typeof(expected),
			"npc.get(&\"%s\") must forward into tuning (nil = forwarder miss -> a silent duck-read failure)" % name)
		assert_eq(via_npc, expected,
			"npc.get(&\"%s\") must return the NpcTuning default off-tree (components read it pre-_ready)" % name)
	npc.free()
	defaults = null

func test_every_tuning_field_writes_through_the_npc() -> void:
	# set() BEFORE add_child is the harness + legacy-.tscn-override path (soak_harness.gd:101-102,
	# combat_smoke_harness.gd:101/:105, a missed scene's flat override at load) — a _set miss silently
	# no-ops there, so pin the write round-trip per name.
	var npc = load(NPC_PATH).new()
	for name in _tuning_names():
		var probe: Variant = _probe_value_for(npc.get(name))
		npc.set(name, probe)
		assert_eq(npc.get(name), probe,
			"npc.set(&\"%s\") must land on npc.tuning (a silent no-op loses harness/scene overrides)" % name)
		assert_eq(npc.tuning.get(name), probe,
			"npc.set(&\"%s\") must store the value on the tuning resource itself" % name)
	npc.free()

func test_tuning_is_per_instance_not_shared() -> void:
	# resource_local_to_scene + the export field initializer + _ensure_tuning must give every NPC its OWN
	# tuning: profile stamping / harness writes on one NPC must never bleed into another (the shared-.tres
	# contamination hazard the migration design guards against).
	assert_true(NpcTuning.new().resource_local_to_scene,
		"_init must force resource_local_to_scene ON (per-scene-instance duplication at instantiate)")
	var a = load(NPC_PATH).new()
	var b = load(NPC_PATH).new()
	assert_not_null(a.tuning, "the tuning export field-initializes (never null off-tree)")
	assert_not_null(b.tuning, "the tuning export field-initializes (never null off-tree)")
	assert_ne(a.tuning, b.tuning, "two bare NPCs must not share one NpcTuning instance")
	a.tuning.sight_range = 123.0
	assert_almost_eq(float(b.tuning.sight_range), 25.0, 0.0001,
		"a write on one NPC's tuning must not leak into another's")
	a.free()
	b.free()
```

### 5e. Tests that pass UNMODIFIED (by design — do not touch)
`test_enemies.gd:253-295` (17 default pins read the forwarder → NpcTuning defaults, identical values, incl. `hearing` :277), `test_npc.gd` (outline trio stayed declared; `immune_to_weapon_knockback` forwards), `test_alert_propagation.gd`, `test_combat_noise.gd`, `test_hostility.gd:291/346/383`, `test_npc_perception_config.gd` (writes forward via `_set`; `_build_perception` copies from `tuning.*`), `test_stealth_sense_optin.gd`, `test_npc_data.gd:29-101` (stamp/merge via reflective get/set → forwarder), `test_authoring_warnings.gd:16-19` (the export defaults to a constructed resource; **no** new configuration warning is added), `test_faction.gd:140-151` (no `_get_property_list` → no duplicate/earlier `faction_id` entry), `test_goap_action_search.gd:192` + `test_provoke_on_attack.gd:111` (the `in`-guards — **expected** to pass via `_get`; verified at apply, §9 item 4, with the contingency in §8), soak/combat-smoke harnesses (pre-add_child `set()` forwards into the field-initializer resource, preserved through `_ready`'s `_ensure_tuning` since the initializer resource has no `resource_path`), `test_devtools_*` (NpcData untouched).

---

## §6. Scene migration — 6 files, 12 nodes, 106 override lines

**Rules used below (read first):**
- A Resource override REPLACES the whole resource, so each derived/instanced node's payload is the **MERGE** of NPC.tscn's 7 base values with the node's own moved overrides. Non-moved overrides (`threat_response`, `outline_width`, Character exports, identity fields) stay flat on the node.
- Every `[sub_resource]` block goes with the file's other sub_resources, i.e. after the last existing `[sub_resource]` block (or after the ext_resources when there are none), always **before the first `[node]`**.
- `ext_resource` id strings and `sub_resource` ids below were chosen to be collision-free; **before applying each file, text-search it for the id string** and re-pick if it already exists. Do NOT add a `uid="..."` attribute to the new Script ext_resource (never hand-write uids — the editor fills it in on next save; path-only ext_resources already exist in these files). Same reason: no `metadata/_custom_type_script` line on the new sub_resources (the editor re-adds it on save).
- Headers: none of these six files carry a `load_steps=` count in `[gd_scene ...]` except civilian.tscn (untouched) — verified — so no header edits are needed. If you find one anyway, bump it by (new ext_resources + new sub_resources).
- Keep every `unique_id=` node-header attribute byte-identical (hand-edit only; no editor re-save during apply).
- `resource_local_to_scene = true` is written explicitly in each block (redundant with `_init`, deliberate: self-documenting and robust if someone later removes the `_init`).

### 6.1 `rpg/scenes/enemies/NPC.tscn` — full new file content (19 → 27 lines)

```
[gd_scene format=3 uid="uid://ca6nf5pmht55t"]

[ext_resource type="PackedScene" uid="uid://c733c8r3f3cqi" path="res://scenes/enemies/enemy.tscn" id="1_base"]
[ext_resource type="Texture2D" uid="uid://ci7tw8iy73xs6" path="res://assets/textures/w_friend.png" id="3_a74nk"]
[ext_resource type="Resource" uid="uid://ddqnc1majlp2r" path="res://resources/weapons/melee.tres" id="3_d5ppq"]
[ext_resource type="PackedScene" path="res://scenes/props/loot_bag.tscn" id="4_yiki0"]
[ext_resource type="Script" path="res://scripts/npc/npc_tuning.gd" id="5_tune"]

[sub_resource type="Resource" id="NpcTuning_npcbase"]
script = ExtResource("5_tune")
resource_local_to_scene = true
muzzle_offset = Vector3(0, 0, 0.45)
rate_of_fire_factor = 1.136
fire_range = 0.5
sight_range = 500.0
time_to_detect = 0.1
forget_time = 1.0
turn_speed = 20.0

[node name="NPC" unique_id=1507492598 instance=ExtResource("1_base")]
weapon_data = ExtResource("3_d5ppq")
tuning = SubResource("NpcTuning_npcbase")
popup_positive = ExtResource("3_a74nk")
ragdoll_scene = ExtResource("4_yiki0")
```
These 7 values are the "NPC.tscn base payload" merged into every derived node below. The npc.gd:21 precedence comment ("NPC.tscn pre-sets combat fields that would then win over the profile") stays true: under the additive merge, `get(f)` now reads `tuning.X` = this payload ≠ the NpcTuning default, so it still registers as an inline override and wins — same semantics as the old flat 500.0 vs default 25.0.

### 6.2 `rpg/scenes/enemies/civilian.tscn` — **NO CHANGE** (its only tuning-name override, `threat_response = 1`, stayed a declared NPC export).

### 6.3 `rpg/scenes/medicine_person.tscn` (inherits enemy.tscn directly → payload = script defaults + its 12 moved overrides; no NPC.tscn merge)

(a) ADD after line 22 (`[ext_resource ... id="91_sentry"]`):
```
[ext_resource type="Script" path="res://scripts/npc/npc_tuning.gd" id="92_tune"]
```
(b) ADD after the last `[sub_resource]` block (after line 102, `metadata/_custom_type_script = "uid://cqq5cs6lb45h0"` of `StockEntry_mp2`), before the `[node name="Medicine Person"...]` line:
```

[sub_resource type="Resource" id="NpcTuning_medic"]
script = ExtResource("92_tune")
resource_local_to_scene = true
muzzle_offset = Vector3(0, 0, 0.45)
rate_of_fire_factor = 1.136
fire_range = 0.5
sight_range = 150.0
time_to_detect = 3.0
forget_time = 1.0
turn_speed = 7.5
engage_range_fraction = 1.2
dodge_interval = 1.0
dodge_chance = 0.8
dodge_duration = 0.1
talk_approach_distance = 0.0
```
(c) REPLACE the root-node block (lines 104–125) with:
```
[node name="Medicine Person" unique_id=1507492598 instance=ExtResource("1_c1yfn")]
transform = Transform3D(1, 0, -2.9802322e-08, 0, 1, 0, 2.9802322e-08, 0, 1, 0, 0, 0)
profile = SubResource("Resource_7vp7c")
outline_width = 2.0
disposition = 1
weapon_data = ExtResource("9_fhws5")
item_stacks = Array[ExtResource("90_istk")]([SubResource("ItemStack_mp1")])
threat_response = 1
tuning = SubResource("NpcTuning_medic")
popup_positive = ExtResource("10_eyg5m")
ragdoll_scene = ExtResource("11_5a577")
```
(The inline NpcData `Resource_7vp7c` — show_laser/temperament/talk_approach_distance/threat_response/outline_width — is UNTOUCHED; it stamps at runtime through the new `tuning.X = profile.X` path. Since `profile_fills_blanks_only` is off here, the profile clobbers at spawn exactly as today.)

### 6.4 `rpg/scenes/TestLevel.tscn`

(a) ADD one ext_resource after the last existing `[ext_resource ...]` line:
```
[ext_resource type="Script" path="res://scripts/npc/npc_tuning.gd" id="97_tune"]
```
(b) ADD after the file's last `[sub_resource]` block, before the first `[node]`:
```

[sub_resource type="Resource" id="NpcTuning_e4"]
script = ExtResource("97_tune")
resource_local_to_scene = true
muzzle_offset = Vector3(0, 0, 0.45)
rate_of_fire_factor = 3.333
fire_range = 20.0
sight_range = 150.0
time_to_detect = 3.0
forget_time = 1.0
turn_speed = 7.5
engage_range_fraction = 1.2
dodge_interval = 1.0
dodge_chance = 0.8
dodge_duration = 0.5
wanders = true

[sub_resource type="Resource" id="NpcTuning_e2"]
script = ExtResource("97_tune")
resource_local_to_scene = true
muzzle_offset = Vector3(0, 0, 0.45)
weapon_mesh_rotation = Vector3(0, 90, -90)
rate_of_fire_factor = 3.409
fire_range = 20.0
sight_range = 150.0
time_to_detect = 3.0
forget_time = 1.0
turn_speed = 7.5
wanders = true
wander_radius = 1000.0

[sub_resource type="Resource" id="NpcTuning_e3"]
script = ExtResource("97_tune")
resource_local_to_scene = true
muzzle_offset = Vector3(0, 0, 0.45)
rate_of_fire_factor = 5.988
fire_range = 500.0
immune_to_weapon_knockback = true
starts_unloaded = true
sight_range = 500.0
fov_degrees = 85.0
time_to_detect = 5.0
forget_time = 0.1
turn_speed = 5.0
move_speed = 0.0
move_accel = 0.0
air_accel = 0.0
engage_range_fraction = 0.0
jump_velocity = 0.0
dodge_interval = 0.0
dodge_chance = 0.0
dodge_duration = 0.0
dodge_speed_fraction = 0.0
wander_radius = 0.0
wander_dwell_min = 0.0
wander_dwell_max = 0.0
flee_distance = 0.0
talk_approach_distance = 0.0
talk_approach_timeout = 0.0
```
(Enemy3's `sight_range = 500.0` is the recon-flagged INHERITED value it silently rode on from NPC.tscn — it must be written explicitly here or the sniper drops to the NpcTuning default 25 m.)

(c) REPLACE the Enemy4 node block (lines 309–327) with:
```
[node name="Enemy4" parent="Characters" unique_id=1507492598 instance=ExtResource("8_40jy2")]
transform = Transform3D(1, 0, -2.9802322e-08, 0, 1, 0, 2.9802322e-08, 0, 1, -5.7000003, 0.9999999, 4.7000003)
profile = SubResource("Resource_6jx65")
goap_profile = ExtResource("5_ktuiq")
look = ExtResource("90_kyl")
display_name = "Kyle"
faction = ExtResource("5_p3doa")
disposition = 2
weapon_data = ExtResource("4_2sboe")
tuning = SubResource("NpcTuning_e4")
```
(d) REPLACE the Enemy2 node block (lines 334–346) with:
```
[node name="Enemy2" parent="Characters" unique_id=1589844148 instance=ExtResource("8_40jy2")]
transform = Transform3D(-0.7071068, 0, -0.70710677, 0, 1, 0, 0.70710677, 0, -0.7071068, -4.9, 0.9999999, 2.9000003)
profile = ExtResource("9_dcwjr")
display_name = "Dial"
faction = ExtResource("9_p3doa")
tuning = SubResource("NpcTuning_e2")
```
(e) REPLACE the Enemy3 node block (lines 353–384) with:
```
[node name="Enemy3" parent="Characters" unique_id=783645483 instance=ExtResource("8_40jy2")]
transform = Transform3D(-0.49999994, 0, 0.86602545, 0, 1, 0, -0.86602545, 0, -0.49999994, -18.500002, 37.500004, 12.900001)
display_name = "Von Lime"
disposition_overrides_faction = true
weapon_data = ExtResource("10_2sboe")
tuning = SubResource("NpcTuning_e3")
blast_damp_divisor = 8000.0
max_hp = 2.0
fall_damage_min_speed = 8.0
fall_damage_per_speed = 100.0
```
(f) The "Medicine Person" node (line 386) has NO tuning-name overrides → UNCHANGED.

### 6.5 `rpg/scenes/TestLevel_2.tscn`

(a) ADD after line 14 (`[ext_resource ... id="17_3cemv"]`):
```
[ext_resource type="Script" path="res://scripts/npc/npc_tuning.gd" id="18_tune"]
```
(b) ADD after the file's last `[sub_resource]` block, before the first `[node]`:
```

[sub_resource type="Resource" id="NpcTuning_e4"]
script = ExtResource("18_tune")
resource_local_to_scene = true
muzzle_offset = Vector3(0, 0, 0.45)
rate_of_fire_factor = 3.333
fire_range = 20.0
sight_range = 150.0
time_to_detect = 3.0
forget_time = 1.0
turn_speed = 7.5
engage_range_fraction = 1.2
dodge_interval = 1.0
dodge_chance = 0.8
dodge_duration = 0.5
wanders = true

[sub_resource type="Resource" id="NpcTuning_e2"]
script = ExtResource("18_tune")
resource_local_to_scene = true
muzzle_offset = Vector3(0, 0, 0.45)
weapon_mesh_rotation = Vector3(0, 90, -90)
rate_of_fire_factor = 3.409
fire_range = 20.0
sight_range = 150.0
time_to_detect = 3.0
forget_time = 1.0
turn_speed = 7.5
wanders = true
wander_radius = 1000.0

[sub_resource type="Resource" id="NpcTuning_e5"]
script = ExtResource("18_tune")
resource_local_to_scene = true
muzzle_offset = Vector3(0, 0, 0.45)
rate_of_fire_factor = 3.333
fire_range = 20.0
sight_range = 150.0
time_to_detect = 3.0
forget_time = 1.0
turn_speed = 7.5
engage_range_fraction = 1.2
dodge_interval = 1.0
dodge_chance = 0.8
dodge_duration = 0.1
wanders = true
wander_radius = 50.0
```
(c) REPLACE the Enemy4 block (lines 134–149) with:
```
[node name="Enemy4" parent="Characters" unique_id=1507492598 instance=ExtResource("3_apdap")]
transform = Transform3D(1, 0, -2.9802322e-08, 0, 1, 0, 2.9802322e-08, 0, 1, -5.7000003, 0.9999999, 4.7000003)
display_name = "Kyle"
faction = ExtResource("4_emawr")
disposition = 2
weapon_data = ExtResource("5_a4bwh")
tuning = SubResource("NpcTuning_e4")
```
(d) REPLACE the Enemy2 block (lines 156–168) with:
```
[node name="Enemy2" parent="Characters" unique_id=1589844148 instance=ExtResource("3_apdap")]
transform = Transform3D(-0.7071068, 0, -0.70710677, 0, 1, 0, 0.70710677, 0, -0.7071068, -4.9, 0.9999999, 2.9000003)
profile = ExtResource("9_r7qd4")
display_name = "Dial"
faction = ExtResource("11_yj2uf")
tuning = SubResource("NpcTuning_e2")
```
(e) REPLACE the Enemy5 block (lines 175–190) with:
```
[node name="Enemy5" parent="Characters" unique_id=439620973 instance=ExtResource("3_apdap")]
transform = Transform3D(1, 0, -2.9802322e-08, 0, 1, 0, 2.9802322e-08, 0, 1, -3.7000003, 0.9999999, 4.7000003)
display_name = "Murray Chen"
disposition = 1
threat_response = 1
tuning = SubResource("NpcTuning_e5")
```
(`threat_response = 1` stays flat — not moved.)

### 6.6 `rpg/scenes/levels/NavSandbox.tscn`

(a) ADD after line 13 (`[ext_resource ... id="10_dqds7"]`):
```
[ext_resource type="Script" path="res://scripts/npc/npc_tuning.gd" id="11_tune"]
```
(b) ADD after the last `[sub_resource]` block (after line 75, `metadata/... "uid://cw2vckrk4mua3"` of `Resource_dqds7`), before `[node name="Level" ...]`. Three separate blocks — one per raider — so a designer can retune one raider in the editor without touching the other two (matching today's per-node flat overrides):
```

[sub_resource type="Resource" id="NpcTuning_r1"]
script = ExtResource("11_tune")
resource_local_to_scene = true
muzzle_offset = Vector3(0, 0, 0.45)
rate_of_fire_factor = 1.136
fire_range = 0.5
sight_range = 500.0
time_to_detect = 0.1
forget_time = 1.0
turn_speed = 20.0
wanders = true

[sub_resource type="Resource" id="NpcTuning_r2"]
script = ExtResource("11_tune")
resource_local_to_scene = true
muzzle_offset = Vector3(0, 0, 0.45)
rate_of_fire_factor = 1.136
fire_range = 0.5
sight_range = 500.0
time_to_detect = 0.1
forget_time = 1.0
turn_speed = 20.0
wanders = true

[sub_resource type="Resource" id="NpcTuning_r3"]
script = ExtResource("11_tune")
resource_local_to_scene = true
muzzle_offset = Vector3(0, 0, 0.45)
rate_of_fire_factor = 1.136
fire_range = 0.5
sight_range = 500.0
time_to_detect = 0.1
forget_time = 1.0
turn_speed = 20.0
wanders = true
```
(c) REPLACE the three raider node blocks (lines 96–112) with:
```
[node name="Raider1" parent="Characters" unique_id=1391275044 instance=ExtResource("5")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 14, 0, 0)
display_name = "Raider 1"
faction = ExtResource("6")
tuning = SubResource("NpcTuning_r1")

[node name="Raider2" parent="Characters" unique_id=1496314158 instance=ExtResource("5")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -12, 0, 9)
display_name = "Raider 2"
faction = ExtResource("6")
tuning = SubResource("NpcTuning_r2")

[node name="Raider3" parent="Characters" unique_id=1973299865 instance=ExtResource("5")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, -14)
display_name = "Raider 3"
faction = ExtResource("6")
tuning = SubResource("NpcTuning_r3")
```

### 6.7 `rpg/scenes/levels/SliceTestLevel.tscn`

(a) ADD one ext_resource after the last existing `[ext_resource ...]` line:
```
[ext_resource type="Script" path="res://scripts/npc/npc_tuning.gd" id="99_tune"]
```
(b) ADD after the file's last `[sub_resource]` block, before the first `[node]`:
```

[sub_resource type="Resource" id="NpcTuning_guard"]
script = ExtResource("99_tune")
resource_local_to_scene = true
muzzle_offset = Vector3(0, 0, 0.45)
rate_of_fire_factor = 1.136
fire_range = 0.5
alert_radius = 10.0
gunfire_noise_radius = 16.0
sight_range = 11.0
fov_degrees = 95.0
time_to_detect = 0.9
forget_time = 4.0
turn_speed = 20.0
wanders = true
wander_radius = 5.0

[sub_resource type="Resource" id="NpcTuning_lookout"]
script = ExtResource("99_tune")
resource_local_to_scene = true
muzzle_offset = Vector3(0, 0, 0.45)
rate_of_fire_factor = 1.136
fire_range = 0.5
alert_radius = 10.0
gunfire_noise_radius = 16.0
sight_range = 24.0
fov_degrees = 95.0
time_to_detect = 0.9
forget_time = 4.0
turn_speed = 20.0
wanders = true
wander_radius = 5.0
```
(c) REPLACE the YardGuard block (lines 206–218) with:
```
[node name="YardGuard" parent="Characters" unique_id=1636006877 instance=ExtResource("6_npc")]
transform = Transform3D(0.866025, 0, -0.5, 0, 1, 0, 0.5, 0, 0.866025, -7, 0, -8.5)
display_name = "Yard Guard"
faction = ExtResource("7_raiders")
item_stacks = Array[ExtResource("6_hqkmj")]([SubResource("Resource_tttcu")])
tuning = SubResource("NpcTuning_guard")
```
(d) REPLACE the YardLookout block (lines 220–231) with:
```
[node name="YardLookout" parent="Characters" unique_id=961519384 instance=ExtResource("6_npc")]
transform = Transform3D(0.766044, 0, 0.642788, 0, 1, 0, -0.642788, 0, 0.766044, 7, 0, -10)
display_name = "Yard Lookout"
faction = ExtResource("7_raiders")
tuning = SubResource("NpcTuning_lookout")
```
NOTE: the stealth-slice detection timings documented in `docs/SLICE_TEST_LEVEL_GUIDE.md` are preserved by these payloads — verify that doc's numbers still read correctly (§7).

**Default-instance story:** a node with NO tuning-name overrides needs NOTHING — `trenchboom_test_level.tscn`'s NPC and TestLevel's Medicine Person instance inherit their base scene's `tuning` sub-resource; `civilian.tscn`/`enemy.tscn` instances get the npc.gd field-initializer defaults, exactly matching today's flat defaults. **Safety net:** because `_set` forwards, any legacy .tscn missed by this inventory still LOADS correctly (its flat override lands in the per-instance initializer resource at scene load); it only loses those values if later re-saved from the editor — a soft failure, not a silent runtime one. **Latent-locomotor check (recon §6.4):** no scene parents a `Locomotor` to an NPC (the repo-wide tuning-name .tscn grep that produced this inventory would have surfaced its exports), so the `locomotor.gd` `_tuning()` reads stay latent; when Locomotor Phase B lands, its `_tuning(body, &"jump_velocity"/&"move_speed", ...)` `body.get()` calls resolve through this forwarder unchanged.

---

## §7. Docs (same commit)

1. **`docs/audits/locomotor_phase_b_migration.md`** — immediately after the `_host_jump_velocity` snippet (lines ~353–357), add:
   > NOTE (NpcTuning migration, 2026-07): `jump_velocity` / `move_speed` / `move_accel` / `air_accel` / `turn_speed` now live on `NPC.tuning` (NpcTuning), but `_tuning(body, &"...")` uses `body.get()`, which NPC forwards via `_get` — these reads work UNCHANGED. Do not "fix" them to `body.tuning.x`; the duck read is the contract (pinned by tests/test_npc_tuning_forwarding.gd).
2. **`docs/AUTHORING_GUIDE.md`** — update the "tune an NPC" designer steps: perception/movement/weapon/behavior numbers now live in the **Tuning** foldout (NpcTuning); per-placed-instance tweak = expand `tuning` → edit (Make Unique first if the editor shows it shared); reusable payloads = save an NpcTuning `.tres` preset and assign it. Locate stale mentions: `rg -n "sight_range|move_speed|wanders|dodge_" docs/AUTHORING_GUIDE.md`.
3. **`docs/CURRENT_ARCHITECTURE.md`** — in the NPC section: NPC tuning = `NpcTuning` sub-resource on `NPC.tuning` (per-instance via `resource_local_to_scene` + `_ensure_tuning`); NpcData remains the archetype layer stamping INTO it (`tuning.X = profile.X`); duck reads reach it through `NPC._get/_set`. Still exactly two truth sources.
4. **`scripts/npc/README.md`** — add the forwarding contract note (components keep reading `host.<name>`; new tuning fields go in npc_tuning.gd and are auto-forwarded; runtime-mutated fields stay on npc.gd).
5. Sweep: `rg -n "npc\.gd" docs/ | rg -i "export|tuning"` and `git diff --check` after all edits.
6. Commit `scripts/npc/npc_tuning.gd.uid` (generated by `--import`) alongside the new script; commit message via `-F` file; stage ONLY the paths listed in this patch (never sweep — the user authors scenes concurrently).

---

## §8. Behavior-equivalence argument, annotation checks, residual risks

**Equivalence, per reader form (every value bit-identical pre/post):**
- **npc.gd internal reads (40 sites)** — mechanical `X` → `tuning.X` on the same per-instance resource the stamp writes; copy-once sites (`_build_perception`, NoisePulser seeds, `panic_scale`, `_muzzle.position`) read at the same `_ready` moment; live sites read the same storage every frame.
- **Duck `host.<name>` / `body.get(&"name")` / `.get(&"immune_to_weapon_knockback")`** — `_get` fires for undeclared names on BOTH `obj.prop` and `obj.get()` paths and returns `tuning.get(name)`; all 45 are value types so nil unambiguously means "unknown name". Pinned per-name by the new test.
- **Pre-add_child `set()` (harnesses, legacy scenes)** — `_set` writes into the field-initializer resource (exists from `_init`); `_ensure_tuning` in `_ready` does NOT duplicate it away (initializer resource has empty `resource_path`), so the values survive into play.
- **Profile stamping** — full-clobber writes the same 55 values to the same logical fields; the additive merge's `get(f) != defaults.get(f)` comparison forwards on both sides (probe defaults come from the probe's own initializer NpcTuning = script defaults, identical to the old export defaults). The NPC.tscn "pre-set fields win over the profile" precedence survives (§6.1).
- **Scene values** — every flat override line was transcribed into a payload merged with NPC.tscn's base 7 (payload tables §6); nodes with zero moved overrides inherit unchanged.
- **Typed readers** — the only two components typed-reading moved names (`weapon_stance`, `talk_approach`) were rewritten to `host.tuning.X` (same resource, same values); `npc_outline`/`npc_audio_cues` untouched because their fields didn't move.

**`:=` / Variant annotation checks (memory: no `:=` inference from Variant chains):** every rewritten npc.gd/component site accesses `tuning`/`host.tuning` through the **typed** `NpcTuning` export, so `tuning.move_accel` is statically `float` — the two `:=` sites touched (E28 `var r :=`, E30 `var rate :=`) still infer `float`. The forwarder itself returns `Variant` by contract; its consumers (`get()` callers) were already Variant-tolerant. No new `host.*` Variant-chain inference is introduced in the drop-ins (their reads stay dynamic).

**Residual risks (ranked):**
1. **`in`-operator vs `_get`** (two guard tests) — expected to pass (Variant OP_IN on Object uses the getvar valid-flag, which a non-nil `_get` satisfies) but **unverified on this engine build**; §9 item 4 proves it empirically. CONTINGENCY if it fails — add to npc.gd (after `_set`):
```gdscript
func _get_property_list() -> Array[Dictionary]:
	# CONTINGENCY: publish the forwarded names so `in` / get_property_list() resolve them. Deliberately NO
	# editor usage flags — the Inspector must not grow a second flat authoring surface for these (the nested
	# tuning foldout is the single surface). Appended AFTER default enumeration, so test_faction.gd's
	# first-match faction_id lookup still hits the real export entry.
	var out: Array[Dictionary] = []
	for name in _tuning_props():
		out.append({ "name": String(name), "type": typeof(tuning.get(name)) if tuning != null else TYPE_NIL, "usage": PROPERTY_USAGE_NONE })
	return out
```
   (If applied, also re-run 5a/5e expectations — they remain valid.)
2. **`_get`/`_set` under @tool in-editor** (gizmo `_getf` fallbacks draw nothing on a miss — silent editor regression) — §9 item 7 spot-check.
3. **local_to_scene duplication semantics** — deliberately NOT load-bearing: `_ensure_tuning`'s path-based duplicate guarantees per-NPC isolation even if the engine shares a duplicate across nodes within one scene instance; §9 item 8 verifies live.
4. **Editor re-save churn** — the first editor save of a migrated scene will add uids/`metadata/_custom_type_script` and may reorder properties; expected, one-time, review that diff before committing it.
5. **Make-Unique workflow** — per-placed-instance tweaking now requires expanding the tuning foldout (and Make Unique when shared); accepted in the design, documented in §7.2.
6. **Line-count honesty:** npc.gd 2,804 → ~2,700 (−~104); the project grows ~+95 lines (npc_tuning.gd 187 + glue + tests − removals). This patch's value is the preset/authoring surface and the now-pinned duck contract, not shrinkage.

---

## §9. PRE-APPLY CHECKLIST (in order; editor CLOSED throughout 1–6)

1. **Close the Godot editor.** Confirm no `godot` process is running.
2. Apply files in this order: `scripts/npc/npc_tuning.gd` (new) → `scripts/npc/npc.gd` → `weapon_stance.gd` → `talk_approach.gd` → tests (5a–5d) → scenes (§6, checking each new ext/sub-resource id for collisions first).
3. `& "C:\Users\dalla\bin\godot.cmd" --headless --path "C:/Users/dalla/3D RPG/rpg" --import` (ABSOLUTE --path; generates `npc_tuning.gd.uid` + registers `NpcTuning` — then confirm with a grep for `NpcTuning` in `.godot/global_script_class_cache.cfg`).
4. **`in`-operator scratch check** — write `rpg/scratch_in_check.gd`:
```gdscript
extends SceneTree
func _initialize() -> void:
	var npc = load("res://scripts/npc/npc.gd").new()
	print("IN sees forwarded name: ", "sight_range" in npc)
	print("GET forwards: ", npc.get("sight_range"))
	print("SET forwards: ", npc.set("sight_range", 42.0) if false else (func(): npc.set("sight_range", 42.0); return npc.get("sight_range")).call())
	npc.free()
	quit()
```
   Run `godot --headless --path "C:/Users/dalla/3D RPG/rpg" -s scratch_in_check.gd`. Expect `true / 25.0 / 42.0`. If the first prints `false` → apply the §8 contingency `_get_property_list`, re-run. Delete the scratch file afterward.
5. **Re-read every written file** (memory: writes can revert) — at minimum re-grep npc.gd for a bare `sight_range =` outside the array/comments (expect none) and each scene for leftover flat moved-name lines (expect none in the 12 nodes).
6. **With the user's explicit go-ahead** (CLAUDE.md: never unprompted): full GUT run headless. Expected deltas: the 3 edited/new test files pass; zero other changes.
7. Reopen the editor. Spot-checks: (a) select NPC.tscn's root — the **Tuning** foldout shows the 7-value payload, `faction_id` dropdown still populates, `_get_configuration_warnings` shows nothing new; (b) open SliceTestLevel — the gizmo sight-cone + alert-ring still draw for YardGuard (forwarder under @tool); (c) open TestLevel — Enemy3's tuning shows fire_range 500 / sight_range 500 / move_speed 0.
8. Runtime isolation check: run NavSandbox (or the soak harness) and confirm the three raiders wander independently and a `print(npc.tuning.get_instance_id())` differs per raider (per-instance duplication + harness `set()` landing).
9. Do NOT run `--import` again while the editor is open (empty-PackedScene trap). Commit only the §-listed paths, message via `git commit -F`, ending with the project's Co-Authored-By line.

**Bottom line honest math:** npc.gd −~104 lines (2,804 → ~2,700, −3.7%); project +~95 lines; 15 files; 6 scenes / 12 nodes / 106 override lines migrated (civilian.tscn dropped out because `threat_response` stayed inline). The buy is NpcTuning presets-as-.tres, one collapsible designer surface, and an enumerated, test-pinned duck-read contract — not size.
---

# Adversarial verdicts (4 lenses, verbatim)



=========== VERDICT 1 ===========

All verification complete. Final findings below.

# Skeptic pass — duck-reader-breakage lens — VERIFIED AGAINST LIVE FILES

## Reader-by-reader audit (every one ground-truthed this session)

**Internal npc.gd sites (E12, E15–E41):** every cited line matches the live file verbatim (`scripts/npc/npc.gd:446,453,759,784-786,1015,1019,1266-1272,1520,1527,2045-2057,2083-2085,2149,2273,2315,2325,2403,2434,2443-2446,2488,2552,2608,2762`). An exhaustive 45-name grep of npc.gd confirms **no missed bare read** — every remaining hit is a comment, the stamp body (E14), or PROFILE_STAMPED_FIELDS (unchanged). Leftovers would be compile errors, as claimed.

**Duck readers (forwarder-covered, all verified untyped):**
- `npc_combat.gd:22` `host: Node` → reads at 38,98-100,131,171,195-212 all forward. `npc_combat.gd:171` and `attack.gd:385` use `.get(&"immune_to_weapon_knockback")` — the **only two** `.get(&"moved-name")` sites in the repo (swept).
- `npc_locomotion.gd:19`, `npc_targeting.gd:19`, `npc_voice.gd:19`, `npc_senses.gd:16` — all `host: Node`. npc_voice/npc_senses read **no** moved names (comments / `_perception.*` only), matching the patch's no-touch claim.
- GOAP: `goap_executor.gd:52/78` (`host.temperament`) and `goap_action_search.gd:35/54` (`host.search_sweep_rate`) — untyped `host` params → forwarder. All other GOAP hits are comments/stub-locals.
- `locomotor.gd:167-168` `_tuning()` = `body.get(prop)` + null fallback → forwarder, latent (no scene parents a Locomotor to an NPC — confirmed by the .tscn sweep). Phase B doc anchor `_host_jump_velocity` verified at `docs/audits/locomotor_phase_b_migration.md:356`.
- Gizmo `cybersunday_gizmo_plugin.gd:191-193,199` uses `_getf` → `o.get()` (line 292) → forwarder under @tool (tuning non-null via field initializer).
- `provoke_on_attack.gd:21/30` (`host: Variant`), `panic_on_damage.gd:20` (reads NO moved names — seeding is npc.gd E15). Harnesses `soak_harness.gd:101-102`, `combat_smoke_harness.gd:101/105` = pre-add_child `set()` → `_set` → initializer resource, preserved (empty resource_path). All correct.

**Typed (compile-coupled) readers:** exactly two components typed `NPC` read moved names — `weapon_stance.gd:103-106` and `talk_approach.gd:59/66/86`; patch §3/§4 OLD text matches byte-for-byte. `npc_audio_cues.gd:36` is typed but its only hit is a comment (line 70) — no-touch claim correct. `character.gd` declares **none** of the 45 names; npc.gd has **no** existing `_get`/`_set`/`_get_property_list`.

**Godot 4.6 forwarding semantics:** `obj.prop` and `obj.get()` on undeclared names both route through script-instance get → `_get` (members checked first, so declared props unaffected); `in` on Object resolves via the getvar valid-flag, which a non-nil `_get` satisfies — the patch's §9.4 empirical scratch check + §8 `_get_property_list` contingency is exactly the right posture for the only two `in` sites (`test_goap_action_search.gd:192`, `test_provoke_on_attack.gd:111` — repo-wide sweep found no others).

**Tests:** every test reading moved names off an NPC uses untyped `var n = load(...).new()` (test_enemies:254, test_alert_propagation:19, test_combat_noise:15, test_hostility:282+, test_npc:60, test_npc_perception_config:14, test_stealth_sense_optin:24) → forwarder. The `p.*` reads in test_enemies/test_held_prop_los/test_perception_* are on **Perception**, not NPC. The only typed-NPC test touching moved names is test_ranged_behavior (patch 5c covers all 4 lines; line 13 `threat_response` correctly untouched). test_npc_vs_npc/test_ammo_reserve/test_camera_input_ui/test_npc_inventory/test_world_components are typed but read no moved names. `test_devtools_generators.gd:63` reads NpcData (untouched). **5b is mandatory, not optional**: the current regex (`test_npc_data.gd:139`) would capture only the 18 bare assignments and fail the `>50` floor — the patch's two-shape regex fixes it correctly; 5a's `merge(_prop_names(n.tuning))` is likewise required (forwarded names don't appear in `get_property_list()`).

**Stamp/array math:** current stamp body = 55 assignments in exactly the order E14 preserves (`goap_profile` at 564, `threat_response` at 568); 18 bare + 37 `tuning.` = 55; the 8 non-stamped NpcTuning fields (6 group-AI + 2 stealth opt-ins) are correctly absent from the array today. All 45 NpcTuning §1 defaults match the live npc.gd export defaults value-for-value.

**Scenes:** repo-wide `.tscn` sweep returns **exactly the 6 files** in the inventory — civilian.tscn (threat_response only), enemy.tscn, trenchboom confirmed clean. All five level/prefab ext_resources resolve to `NPC.tscn` (so the 7-value base-merge is required and correctly applied everywhere, including Enemy3's inherited `sight_range = 500` trap and the guards' inherited `turn_speed = 20`). Every payload value matches the live flat override; every node-block replacement preserves every non-moved line (Enemy3's trailing `blast_damp_divisor/max_hp/fall_damage_*`, Enemy5's `threat_response = 1`, YardGuard's `item_stacks`, medicine's `outline_width/profile/disposition`). No id collisions; none of the 6 files has a `load_steps` header; all textual anchors (medicine_person:22/102/104, TestLevel_2:14, NavSandbox:13/75) exact. The `laser_color`-dead rider checks out (npc.gd:2766 tints from `_outline_color_for_disposition()`).

## Corrections (all prose-level; no edit is wrong)

1. **Override-line count: 106 → 108.** Per-node recount: NPC 7, medicine 12, TL 10+8+**23** (Enemy3 has 23 own flat lines, not 24 — no `sight_range` line, it's inherited, which the patch itself handles), TL2 10+8+11, Nav 3, Slice 8+8 = 108. The per-file listings and payloads are all correct; only the headline number is off.
2. **npc.gd is 2,806 lines, not 2,804** — yet every stated anchor verifies at its stated number, so no edit is mis-anchored; §9.5's re-read covers it.
3. **ADD a risk (PLAUSIBLE): editor-save default-embedding churn.** `@export var tuning: NpcTuning = NpcTuning.new()` — a constructed-object export default is generally not comparable/recoverable as "default" at scene-save, so the first editor re-save of ANY NPC-bearing scene without an authored `tuning` (enemy.tscn, civilian.tscn, trenchboom, future placements) will likely serialize a `tuning = SubResource(...)` block, **freezing then-current NpcTuning defaults into that scene** (later script-default changes stop propagating — the "silently stuck" hazard class). Behavior-identical at freeze time, but add it to §8 and extend §9.7: open + save enemy.tscn, inspect the diff, and decide accept-vs-author-explicit-base-payload.

## Verdict: **PATCH-SOUND**

No duck reader is missed; no reader resolves to a different value; both typed readers are rewritten; the scene inventory is complete and value-exact; the two `in`-operator sites are the only genuinely unproven seam and the patch already gates them behind an empirical pre-apply check with a correct contingency. The three corrections above are prose/risk-register items, not edit changes — fold them in and apply per §9 (editor closed).

Key files verified: `C:\Users\dalla\3D RPG\rpg\scripts\npc\npc.gd`, `scripts\npc\weapon_stance.gd`, `scripts\npc\talk_approach.gd`, `scripts\npc\npc_combat.gd`, `scripts\npc\npc_locomotion.gd`, `scripts\npc\npc_targeting.gd`, `scripts\components\locomotor.gd`, `scripts\components\provoke_on_attack.gd`, `scripts\combat\attack.gd`, `addons\cybersunday_tools\gizmos\cybersunday_gizmo_plugin.gd`, `tests\test_npc_data.gd`, `tests\test_ranged_behavior.gd`, `scenes\enemies\NPC.tscn`, `scenes\medicine_person.tscn`, `scenes\TestLevel.tscn`, `scenes\TestLevel_2.tscn`, `scenes\levels\NavSandbox.tscn`, `scenes\levels\SliceTestLevel.tscn`, `docs\audits\locomotor_phase_b_migration.md`.

=========== VERDICT 2 ===========

GOAP `host` is an untyped parameter — forwarder covers it. Verification complete; here is my report.

---

# SKEPTIC VERIFICATION — scene-and-inspector lens, all claims ground-truthed against the repo this session

## 1. Scene inventory: COMPLETE (independently re-derived)

I ran my own repo-wide grep of all 45 moved names as `^name = ` lines across `**/*.tscn`. Every hit reconciles:

- **The 6 files / 12 nodes are exactly right.** No seventh file, no thirteenth node.
- The only hits outside the inventory are **NpcData sub-resource fields, correctly excluded**: `scenes/TestLevel.tscn:134` (`wanders = true` inside `Resource_6jx65`, the "Ms. Vile" NpcData profile, script `5_7vp7c`) and `scenes/medicine_person.tscn:51/53/54` (`show_laser`/`temperament`/`talk_approach_distance` inside the inline NpcData `Resource_7vp7c`). NpcData stays flat — these need nothing.
- `scenes/levels/trenchboom_test_level.tscn:315` NPC overrides only `profile` + `look` — inherits NPC.tscn's tuning ✓. `scenes/character_customizer_setup.tscn` mentions enemy.tscn only in a comment (authoring-only scene) — nothing to do.
- `civilian.tscn` drop-out re-confirmed: its only tuning-name line is `threat_response = 1`, which stays a declared NPC export.
- **Base chains verified**: TestLevel/TestLevel_2/NavSandbox/SliceTestLevel enemies all `instance=` NPC.tscn (`uid://ca6nf5pmht55t`); medicine_person instances enemy.tscn directly; enemy.tscn root (read in full) sets NO tuning-name overrides. So the merge rules used to build each payload are correct.

## 2. Value fidelity: byte-identical, every payload re-derived independently

I re-computed each drafted sub-resource as (base-scene payload ⊕ node's flat overrides) and compared field-by-field against the actual .tscn lines. **All 12 payloads match exactly**, including the three traps: Enemy3's inherited `sight_range = 500.0` written explicitly (TestLevel.tscn has no such line in its block — omitting it would have silently dropped the sniper to 25 m); `forget_time = 1.0` carried from the NPC.tscn base into every level payload; SliceTestLevel's `turn_speed = 20.0` base carry. Kept-flat lines (`threat_response = 1` at TestLevel_2:188 and medicine_person:122, `item_stacks` at SliceTestLevel:212 and medicine_person:113, Enemy3's Character exports at TestLevel:381–384) are all preserved in the drafted node blocks. Insertion anchors (`91_sentry` @ medicine_person:22, `17_3cemv` @ TestLevel_2:14, `10_dqds7` @ NavSandbox:13, `Resource_dqds7` block ending :75) all verified. No `load_steps` header on any of the six files ✓. No id collisions with `5_tune/92_tune/97_tune/18_tune/11_tune/99_tune` or any `NpcTuning_*` sub-resource id ✓.

## 3. THE CRUX, settled empirically on this exact build (Godot v4.6.3.stable)

I ran a project-less scratch (`scratchpad/in_check.gd`, headless, editor untouched) with a Node class exposing `_get`/`_set` over undeclared names. Results: `"name" in obj` → **true**; `get("name")`, `get(&"name")`, dot-access via a **Variant** ref AND via a **Node-typed** ref all return the forwarded value; `set()` and dot-assignment both land in `_set`; unknown names give `in`=false / get()=null; forwarded names do **NOT** appear in `get_property_list()`. Consequences:

- **Residual risk 1 is RESOLVED**: `test_goap_action_search.gd:192` and `test_provoke_on_attack.gd:111` `in`-guards will pass; the §8 contingency `_get_property_list` is unnecessary and should not ship (so it eats zero lines, and the Inspector never grows a second flat surface).
- The absent-from-property-list fact is exactly why test 5a's `npc_props.merge(_prop_names(n.tuning))` line is load-bearing — the draft already has it.
- **Unmigrated-scene story confirmed as non-catastrophic**: the runtime scene loader applies flat overrides via `set()` → `_set` forwards into the field-initializer resource → **no silent default revert in play**. The only lossy path is an editor re-save, per the draft.

## 4. Typed-reader completeness: CONFIRMED

Codebase-wide dot-access grep of all 45 names, typing checked at every site: the ONLY typed-`NPC` readers of moved names are `weapon_stance.gd` (`host: NPC`, reads at 105–106), `talk_approach.gd` (`host: NPC`, reads at 59/66/86 — exactly the draft's three edits), and `tests/test_ranged_behavior.gd` (`e: NPC`, exactly the draft's four lines; line 13's `threat_response` stays valid). Everything else is duck-typed and forwarder-safe: npc_combat/npc_locomotion/npc_targeting (`host: Node`), provoke_on_attack (`host: Variant`), GOAP (`func tick(host, ...)` untyped), locomotor.gd `_tuning(body.get())` at scripts/components/locomotor.gd:134/151/162, gizmo `_getf(npc, &"sight_range"/&"fov_degrees")` at cybersunday_gizmo_plugin.gd:191–192, `character.get(&"immune_to_weapon_knockback")` at **scripts/combat/attack.gd:385** and npc_combat.gd:171, harness `set()` at soak_harness.gd:101 / combat_smoke_harness.gd:101. Test doubles (`_HostStub`, `_InvestigateHostStub`, `StubHost`) own their fields; `test_enemies.gd`'s `p` is `Perception` (own declared props); addons content_scaffold/npcdata_inspector read NpcData.

## 5. npc.gd edits: anchors and completeness verified — with one drift caveat

- **The file is now 2,806 lines (draft read 2,804).** Every cited anchor (E1–E14 through line 576, and all of E15–E41: 759, 784–786, 1015, 1019, 1266–1272, 1520, 1527, 2045/2046/2055/2057, 2083/2085, 2149, 2273, 2315, 2325, 2403, 2434, 2443/2446, 2488, 2552, 2608, 2762) re-verified **exact** this session — the +2 growth sits after 2762 (tail region; no tuning reads there; `_get_configuration_warnings` now at 2796 reads only unmoved fields). The user edits concurrently: re-verify anchors at apply time as §9 already prescribes.
- **My independent exhaustive bare-name grep of npc.gd found zero reader sites missing from E15–E41** (sole extra hit: a comment at 1755). Leftovers would be loud compile errors anyway.
- `_stamp_profile_full` (521–576) is a perfect 1:1 with the drafted E14: 55 assignments, 37 moved + 18 bare, `goap_profile` at 564 and `threat_response` at 568 interleaved exactly as drafted; the 8 non-stamped moved fields (Group-AI six + two stealth opt-ins) are correctly absent from both the drafted body and the unchanged array.
- Additive merge (507–512) is reflective `get(f)/set(f)` → forwarder-compatible, and `_npc_stamped_defaults` probes `NPC.new()` → E1's field initializer is indeed load-bearing.
- npc.gd declares no `_get`/`_set`/`_get_property_list` today (only `_setup_outline`/`_set_target`/`_get_configuration_warnings`) — no collision.
- **All 45 drafted NpcTuning defaults are byte-identical** to the current export block, including both `@export_range(0.0, 1.0)` annotations.
- tests/test_npc_data.gd current text matches the draft's replacement basis (5a at 112–124; drift test 127–150; regex at line 139); the `(?:tuning\\.)?` fix captures both shapes and the >50 floor holds at 55.

## 6. Inspector answer

Per-instance tuning survives: `tuning` is a declared typed `@export` → nested foldout in the Inspector, editable per placed instance (Make Unique when shared), presets assignable as `.tres`. With the contingency correctly dropped (see §3), no flat tuning properties reappear and no line savings are eaten.

## CORRECTIONS (all minor — none block apply)

1. **Override-line count is 108, not 106** (NPC.tscn 7 + medicine_person 12 + TestLevel 41 + TestLevel_2 29 + NavSandbox 3 + SliceTestLevel 16). Narrative arithmetic only; every payload is complete. Fix the two "106" mentions.
2. **npc.gd line-count claims**: state 2,806 → ~2,702 (file grew +2 since the draft's read; all anchors still exact, but this proves live drift — keep §9's re-verify step mandatory).
3. **§9.4 scratch check**: keep as apply-time belt-and-braces, but record that it was already run project-less this session on v4.6.3 with result `true / 25.0 / 42.0` — and **delete the §8 contingency from the patch text** (or mark it "proven unnecessary") so nobody applies it reflexively.
4. **Path precision**: "attack.gd" is `scripts/combat/attack.gd:385`; weapon_stance's function spans **102–106** (draft says replace 103–106 — the quoted OLD text is unique so string-match apply is unaffected, but fix the cited range and include the `func` line's doc comment boundary check).
5. **Residual risk 4 (editor re-save churn) — strengthen**: because exported-Resource constructor defaults compare by reference, the first editor re-save of ANY scene containing an NPC without an authored tuning override (enemy.tscn, civilian.tscn, trenchboom, dog-adjacent scenes) may bake in a per-instance `tuning` sub-resource with default values. Values identical — churn only — but the diff-review note should cover all NPC scenes, not just the six migrated ones.

## VERDICT: **PATCH-SOUND** (apply the five narrative corrections above; no payload, edit-site, or test change required)

The two failure modes this pass exists to catch — a missed scene override silently reverting, and a forwarder miss silently zeroing a duck read — are both affirmatively excluded: the inventory is grep-complete with every value byte-accounted (including the two inherited-value traps written explicit), and the forwarding semantics are no longer a paper argument but an empirical result on the shipping engine build. The honest math stands as drafted: this buys presets, one designer surface, and a test-pinned duck contract — not size.

Key files verified: `C:\Users\dalla\3D RPG\rpg\scripts\npc\npc.gd`, `scripts\npc\weapon_stance.gd`, `scripts\npc\talk_approach.gd`, `scripts\combat\attack.gd`, `scripts\components\locomotor.gd`, `scripts\npc\goap\goap_executor.gd`, `tests\test_npc_data.gd`, `tests\test_ranged_behavior.gd`, `scenes\enemies\NPC.tscn`, `scenes\enemies\enemy.tscn`, `scenes\enemies\civilian.tscn`, `scenes\medicine_person.tscn`, `scenes\TestLevel.tscn`, `scenes\TestLevel_2.tscn`, `scenes\levels\NavSandbox.tscn`, `scenes\levels\SliceTestLevel.tscn`, `scenes\levels\trenchboom_test_level.tscn`.

=========== VERDICT 3 ===========

All verification complete. Every claimed edit site, test, harness, scene block, and reader was re-read this session. Findings:

## Test-and-drift verification results

**Verified sound (ground-truthed, no action needed):**

1. **Drift test rewrite (5b) keeps the guard at full strength.** `tests/test_npc_data.gd:139` regex `^\t(\w+) = profile\.\w+` cannot match `tuning.X = profile.X` (`\w+` stops at `.`), so WITHOUT the fix the suite fails loudly (18 captures < the `> 50` floor at :143, plus 37 both-ways set-equality failures) — the drafted regex `^\t(?:tuning\.)?(\w+) = profile\.\w+` is necessary and sufficient. The relaxed regex does not weaken the guard: a future bare `X = profile.X` for a moved field is a compile error in npc.gd (undeclared identifier assignment — _get/_set don't rescue bare identifiers), so the wrong shape can't silently pass. Body extraction (`find("func _stamp_profile_full")` → next `\nfunc `) survives the inserted `_ensure_tuning()` line. Stamp-body math re-verified: 18 bare + 37 `tuning.` = 55 = the array (counted at npc.gd:475–486).
2. **Every bare-NPC export-read test is untyped and forwards.** `test_enemies.gd:254` (`var n = load(...)`, 17 default pins all match NpcTuning §1 defaults), `test_combat_noise.gd:15-19`, `test_alert_propagation.gd:19-20`, `test_hostility.gd:346/383` (`n.rate_of_fire_factor`, `n.fire_range`), `test_npc.gd:60-62`, `test_npc_perception_config.gd:14-16` (writes via `_set`, `_build_perception` reads `tuning.*` per E21), `test_stealth_sense_optin.gd:24-38`, `test_npc_data.gd:29-101` (stamp/merge/no-op tests all reflective or dynamic). The ONLY statically-typed test file is `test_ranged_behavior.gd` (`var e: NPC`, lines 12/19/33) and the drafted 5c covers exactly its 4 moved-name sites (13 `threat_response` correctly untouched).
3. **5a rewrite** (`npc_props.merge(_prop_names(n.tuning))`) is correct and does not weaken the resolve pin — a forwarder deletion would still fail loudly in the new 5d suite.
4. **All duck readers confirmed dynamic:** `npc_combat.gd/npc_targeting.gd/npc_locomotion.gd/npc_voice.gd` are `var host: Node` (:22/:19/:19/:19), GOAP `act(_host)`/`_build_world_state(host)` untyped (goap_executor.gd:52/72), `locomotor.gd:168 body.get()`, `attack.gd:385` + `npc_combat.gd:171` `.get(&"immune_to_weapon_knockback")`, gizmo `_getf` = `o.get(prop)` (cybersunday_gizmo_plugin.gd:292), `soak_harness.gd:101-102` and `combat_smoke_harness.gd:101/105` pre-add_child `set()`. Typed hosts reading moved names are ONLY `weapon_stance.gd:104-105` and `talk_approach.gd:59/66/86` — both drafted. `npc_outline.gd`/`companion_follow.gd`/`npc_laser.gd`/`npc_audio_cues.gd` (all `host: NPC`) read zero moved names (comment-only hits). `Character` declares none of the 45 names. npc.gd internal bare uses outside the export block are exactly the E-table lines — re-grepped exhaustively, zero stragglers.
5. **Scene inventory content is correct.** Every drafted payload reconciles field-for-field against the real override lines + the NPC.tscn 7-value base merge (Enemy3's inherited `sight_range = 500` correctly written explicitly; TL2 Enemy5/medicine_person `threat_response = 1` correctly left flat; all non-moved node lines — Kyle's profile/goap_profile/look, Enemy3's blast_damp/max_hp/fall_damage pair, Slice item_stacks, medic's inline NpcData `Resource_7vp7c` — preserved in the replacement blocks). `civilian.tscn`/`enemy.tscn` confirmed override-free for moved names. Ext-resource anchors verified (NavSandbox `ExtResource("5")` = NPC.tscn, etc.).
6. `_get_configuration_warnings` (npc.gd:2796-2806) and `_validate_property` (:418-423) read only must-stay fields; `test_authoring_warnings.gd` and `test_faction.gd:140-151` unaffected as drafted. `test_component_tuning_exports.gd` is unrelated (Throwable/Ragdoll/Character knobs).

## NEEDS-FIX — corrections (no blockers, no silent-revert defects found)

1. **§9.4 scratch script won't compile** — `npc.set("sight_range", 42.0) if false else (...)`: `Object.set()` returns void; a void expression inside a ternary is a GDScript analyzer error, so the very check that gates the `in`-operator contingency would itself fail. Fix: plain sequential statements — `npc.set("sight_range", 42.0)` then `print("SET forwards: ", npc.get("sight_range"))`.
2. **Inventory arithmetic: 108 override lines, not 106** (TestLevel 10+8+23=41, TestLevel_2 10+8+11=29, NPC.tscn 7, NavSandbox 1×3=3, SliceTestLevel 8+8=16, medicine_person 12). The migrated content is line-complete regardless — only the headline count is wrong; correct it since the deliverable claims exactness.
3. **Line-number drift**: npc.gd is 2,806 lines today (draft says 2,804; every E-anchor re-verified exact, so the +2 sits between :2762 and :2796); `weapon_stance.gd` `current_move_speed` is at :102-105, not :103-106. Apply strictly by the verbatim OLD-text anchors (which all match), and state the deletes (E4–E9) as text-bounded ranges, not absolute lines.
4. **Commit the new test's `.uid` too** — §7.6 lists only `scripts/npc/npc_tuning.gd.uid`; `tests/test_npc_tuning_forwarding.gd.uid` is also generated by `--import` and is tracked per CLAUDE.md.
5. **NpcTuning class-doc over-claims** ("THIS resource owns every pure-tuning field an NpcData archetype stamps"): 8 of its 45 fields (the Group-AI noise five + `alert_radius` + both stealth opt-ins) are NOT NpcData-stamped (absent from NpcData and the 55-entry array — verified). Loosen the sentence so the prose stays true (CLAUDE.md: stale prose is worse than none).

Residual risk ranking unchanged: the `in`-operator behavior (test_goap_action_search.gd:192, test_provoke_on_attack.gd:111) remains the one empirically-gated unknown, and the draft's gate + `_get_property_list` contingency is the right treatment — provided correction #1 so the gate actually runs.

**VERDICT: NEEDS-FIX (minor)** — apply corrections 1–5 above and the patch is sound. No test breaks without a drafted fix; no drafted fix weakens a guard; the drift test survives at full 3-way lockstep strength and the new forwarding suite adds a per-name pin the old flat layout never had.

=========== VERDICT 4 ===========

All anchors ground-truthed. Final recount below.

---

## Line-accounting audit of the NpcTuning migration patch

**Anchor freshness:** npc.gd is **2,806** lines today (patch says 2,804 — drifted +2, but every cited edit range re-verified exact: export block 12–273, `_validate_property` 418–422, `_ready` 424/427/446/453, `PROFILE_STAMPED_FIELDS` 473–486, stamp doc+body 514–576, all E15–E41 sites 759→2762, weapon_stance.gd:103–106, talk_approach.gd:59/66/86, test_npc_data.gd:112–150). The scene-override inventory is **complete** — a repo-wide grep of all 45 moved names across `**/*.tscn` found zero node overrides outside the 6 listed files; the two stray hits (TestLevel.tscn:134, medicine_person.tscn:51–54) sit inside inline **NpcData** sub-resources, which the patch correctly leaves flat. No silent-revert candidates were missed. The `-104` anchors are sound; the **arithmetic on top of them is not**.

### Defect 1 — npc.gd net savings is −71, not −104 (claim overstates the shrink by 46%)
Recomputed from the patch's own edits against the real file:

| | lines |
|---|---|
| Deleted: E3(4: 102–105) + E4(26: 118–143) + E5(21: 144–164) + E6(27: 177–203) + E7(6: 204–209) + E8(33: 210–242) + E9(23: 251–273) | **−140** |
| Added: E1 tuning export (12) + E2 doc (+1) + E3 comment (+1) + E10 forwarder/`_ensure_tuning` (**50**, counted line-by-line from the patch block) + E11 (+1) + E13 (+2) + E14 doc 7→8 & body 56→57 (+2) | **+69** |
| **Net npc.gd** | **−71** (2,806 → 2,735, **−2.5%**, not −3.7%) |

If the §8 `_get_property_list` contingency lands, net falls to ~−61. **Fix:** replace "npc.gd −~104 (2,804 → ~2,700)" in §8.6 and the bottom line with "−71 (2,806 → ~2,735, −2.5%); −61 if the `in`-operator contingency is needed". The likely error: the draft counted the 140 deletions against only ~36 of the 69 added lines — i.e. it partially omitted its own 50-line forwarder block from the ledger.

### Defect 2 — project growth is ~+320, not "+~95" (3.4× understated)
- npc.gd −71; npc_tuning.gd **+177** (recounted §1 block; the stated "187" is itself ~10 high); test_npc_tuning_forwarding.gd +~80; test_npc_data.gd +7; weapon_stance/talk_approach/test_ranged 0.
- **Scenes +~122 net** — the claim ignores scenes entirely. Each sub-resource adds 4 boilerplate lines (blank/header/`script`/`resource_local_to_scene`) and, worse, the merge rule **duplicates NPC.tscn's 7-value base payload into derived sub-resources**: NPC.tscn 18→27 (+9, not "19→27"), medicine_person +7, TestLevel +25, TestLevel_2 +24, NavSandbox **+37** (three raiders whose ONLY override was `wanders = true` each get a 12-line block), SliceTestLevel +20.
- Docs +~12.
**Fix:** state "project ≈ +320 lines" in §8.6/bottom line.

### Defect 3 — inventory arithmetic: 13 nodes / 108 override lines, not 12 / 106
Counted from the live scenes: NPC.tscn root 7 + medicine_person 12 + TestLevel (E4 10, E2 8, E3 23) + TestLevel_2 (E4 10, E2 8, E5 11) + SliceTestLevel (8+8) + NavSandbox (1+1+1) = **108 lines across 13 nodes** (1+1+3+3+3+2). **Fix:** the headline "6 files / 12 nodes / 106 override lines".

### Defect 4 — undisclosed authoring regression: merged payloads FREEZE base-scene inheritance
Not a line count, but it falls straight out of the merge rule and §8's equivalence argument omits it. Today a derived node's non-overridden field tracks NPC.tscn **live** (edit NPC.tscn's `sight_range`, every instance follows). Post-migration, the whole `tuning` resource is replaced per node, so NPC.tscn's base values (`muzzle_offset 0.45`, `forget_time 1.0`, `turn_speed 20`, `sight_range 500`, …) are **baked as frozen copies** into ~10 derived sub-resources across TestLevel/TestLevel_2/NavSandbox/SliceTestLevel — most egregiously the three NavSandbox raiders, which currently override nothing but `wanders`. Behavior-identical at apply time; silently divergent the first time the user retunes NPC.tscn. Unavoidable under whole-resource override (inherent to design C-minimal), so the **fix is disclosure**: add it as residual risk #0 in §8 and a NOTE in §6's rules.

### Worth-it, with honest math
Gross deletion 140; forwarder/glue tax 69; **true npc.gd relief −71** — above the <50 triviality bar, but only −2.5% of a 2,806-line file that stays a god object. As a "shrink the root" measure this migration **fails its own stated goal**; the patch half-concedes this, but its −104/+95 figures still flatter it on both axes. The real purchase is: NpcTuning presets-as-.tres, one collapsible Inspector group, and the duck-read contract finally enumerated and test-pinned — bought with a permanent `_get`/`_set` seam, ~+320 project lines, Make-Unique workflow friction, and frozen base-payload inheritance in 4 level scenes. That trade is defensible **only** if the user actively wants the preset workflow; if the motivation was primarily de-god-objecting npc.gd, this patch delivers almost none of that, and moving whole *behaviors* (not exports) into components per the NPC-decomposition plan remains the higher-yield path.

## Verdict: **NEEDS-FIX**
Code edits, anchors, and scene inventory are apply-ready and complete (no silent-revert candidates found). Required corrections before user sign-off — all in the deliverable's claims, none in the code:
1. §8.6 + bottom line: npc.gd net **−71** (2,806 → ~2,735, −2.5%); ~−61 with the `in` contingency.
2. §8.6 + bottom line: project net **≈ +320 lines** (scenes +~122 were omitted).
3. Headline inventory: **13 nodes / 108 override lines**; §6.1 "18 → 27 (+9)"; §1 "~177 lines".
4. Add the frozen-inheritance disclosure (Defect 4) to §8 residual risks and §6 rules.
5. Re-present the worth-it decision to the user under the corrected numbers, explicitly framed as "presets + pinned contract, ~zero god-object relief".

Key files: `C:\Users\dalla\3D RPG\rpg\scripts\npc\npc.gd` (2,806 lines; export block 12–273 verified), `C:\Users\dalla\3D RPG\rpg\scenes\enemies\NPC.tscn` (18 lines), `C:\Users\dalla\3D RPG\rpg\tests\test_npc_data.gd:127–150` (drift test regex at :139 as quoted), `C:\Users\dalla\3D RPG\rpg\scripts\npc\weapon_stance.gd:103–106`, `C:\Users\dalla\3D RPG\rpg\scripts\npc\talk_approach.gd:59/66/86`.