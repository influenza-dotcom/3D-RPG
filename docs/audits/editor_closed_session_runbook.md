# EDITOR-CLOSED SESSION RUNBOOK
Consolidated apply order for all staged npc.gd patches + pending arch-remediation items.
Ground-truthed 2026-07-06 against HEAD `5333d80` ("popcorn"). Follow top-to-bottom.
Repo/Godot root: `C:/Users/dalla/3D RPG/rpg` (git repo IS this dir — always `git -C`).

If HEAD is no longer `5333d80` when you start, re-verify every verbatim anchor before applying anything (standing lesson: docs go stale).

---

## 0. PRE-FLIGHT (5 min)

- [ ] **CLOSE THE GODOT EDITOR.** Everything below assumes it stays closed until §7 step E.
- [ ] Confirm baseline:
  ```powershell
  git -C "C:/Users/dalla/3D RPG/rpg" log --oneline -3
  git -C "C:/Users/dalla/3D RPG/rpg" status
  ```
  Expect HEAD `5333d80 popcorn`. The dirty/untracked files listed below are the user's in-flight work — expected, leave them.

### DO-NOT-SWEEP LIST (never `git add` these; never `git add -A` / `git add .` at any point)
| Strand | Files |
|---|---|
| MoneyPurse (in-flight) | `managers/GameState.gd`, `scripts/inventory/character_inventory.gd`, `scripts/player/player.gd`, `scripts/ui/grid_tile.gd`, `scripts/ui/inventory_screen.gd`, `D scripts/ui/money_tile.gd(+.uid)`, `?? scripts/inventory/money_purse.gd(+.uid)`, `?? tests/test_money_purse.gd(+.uid)` |
| Customizer | `scripts/player/character_appearance_catalog.gd`, `?? resources/characters/PlayerAppearanceCatalog.tres` |
| Text dock + stat-text extraction | `addons/cybersunday_tools/cyber_panel.gd`, `tests/test_devtools_lazy_reveal.gd`, `scripts/ui/stat_info.gd`, `scripts/ui/stats_screen.gd`, `scripts/ui/character_creation.gd`, `?? addons/cybersunday_tools/dock_text/` (text_editor.gd + text_sources.gd), `?? scripts/ui/stat_text.gd(+.uid)`, `?? resources/stats/` (6 StatText .tres), `?? tests/test_stat_text.gd(+.uid)` |
| Item .tres batch (in-flight) | `resources/items/*.tres` (ammo_grenades/pistol/rifle/shells/smg, crate_item, healthpack, melee_item, pistol_item, rock_item, shotgun_item, smg_item, sniper_item, spray_paint_item, zorkmids) |
| MIXED docs | `docs/AUTHORING_GUIDE.md`, `docs/CURRENT_ARCHITECTURE.md` — contain user hunks. **Hunk-level staging only** (`git add -p`) if a patch edits them. |

**Catch-all rule (the tree drifts while the user works):** anything dirty/untracked at your §0 baseline snapshot that this runbook did not create is USER WORK — never stage it, never checkout it. Take the snapshot (`git status > baseline.txt`) and diff against it before every commit.

**Collision rule:** `managers/GameState.gd` and `scripts/player/player.gd` are user-dirty. No patch in this runbook may touch them. This DEFERS two items outright (see §2.3).

- [ ] Class-cache sanity (open editor already imported these; expect all found):
  ```powershell
  Select-String -Path "C:\Users\dalla\3D RPG\rpg\.godot\global_script_class_cache.cfg" -Pattern "CrippleCallout|GroundMovement|Locomotor|NpcCombat|NpcOutline"
  ```
  `NpcTuning` / `NpcHeadAnchor` must NOT be there yet (their scripts don't exist until you apply).

---

## 1. DECISION GATE — NpcTuning GO / NO-GO (decide now)

`docs/audits/npc_exports_to_resource_migration.md` moves the 45 flat NPC tuning exports into an `NpcTuning` Resource with a `_get`/`_set` forwarder on npc.gd. The trade, corrected: it saves only **−71 lines in npc.gd while adding ~+320 lines to the project** (resource class + forwarder + tests + 6 scene edits). Its real payoff is not line count — it is **`.tres` tuning presets** (Raider/Sniper/etc. as shareable, per-instance-duplicated resources) and getting the export wall out of npc.gd's head. It is the riskiest of the three patches (forwarder under `@tool`, scene re-save default-freeze risk). If you don't want the presets workflow yet, NO-GO costs nothing: the doc is committed either way (§6 Commit 1) and can be applied in a later editor-closed session — Locomotor-first ordering keeps it cheap to apply later.

**The `laser_color` deletion rider ships in BOTH branches** (it's dead code: declared npc.gd:209 + npc_data.gd:115, stamped, zero consumers, no test pins it — grep-verified). GO branch: rider goes LAST, after NpcTuning (zero amendments that way). NO-GO branch: rider applies against live anchors at any point.

- [ ] **DECISION: GO / NO-GO** → follow §2 branch accordingly.

### Second decision (small): M13 `Landing` component
GroundMovement half of M13 already shipped in 5333d80. The `Landing` half would touch `scripts/player/player.gd` — **user-dirty ⇒ cannot be done this session.** Options: (a) formally close M13 as descoped (plan line 194 blesses shipping GroundMovement alone) with a one-line note in the plan doc, or (b) leave pending for a session after the money-purse work lands. Pick one; don't ship Landing today.

---

## 2. APPLY SEQUENCE (editor stays closed; no --import until §3)

Before EVERY step: re-verify the doc's verbatim BEFORE block against live text (`Grep`/editor-less diff). One anchor has already rotted (§2.2 delta) — assume others can.

### 2.1 Locomotor Phase B (~45 min apply)
Doc: `docs/audits/locomotor_phase_b_migration.md` — apply §1–§3 **plus its CORRECTIONS 1–3** (doc lines 1252–1341) on top. PLAYTEST-GATED: do not commit until playtest group A (§5) passes.
- All BEFORE blocks byte-match live npc.gd despite the doc's line numbers being stale by +11 (it read a 2795-line file; live is 2806). Apply by verbatim text, ignore line numbers.
- Lifts `_move_toward` (:1983), `_try_nav_hop` (:2054), `apply_velocity` (:2126), stuck cluster (:2163–2262), consts/state/statics into `scripts/components/locomotor.gd` DRIVEN mode; inserts `_build_locomotor()` after `_build_nav()` (:438–439). Does NOT touch `_build_components`.
- CORRECTION 1 = drive_move_to bool contract; CORRECTION 2 = nav-map-ready gating; CORRECTION 3 also edits `scripts/npc/npc_locomotion.gd:10-13` header — apply WITH the migration, not before. (C3 is correct as written: keep the shell's `allow_hop: bool = false` — matches live :1983; it is only the doc's residual-risk PROSE, which C3 itself flags, that mis-describes the form. Do not "fix" the shell.)
- Also edits `tests/test_npc.gd:124-135` (re-points the anti-stuck test).

- [ ] Applied + CORRECTIONS 1–3
- [ ] `_update_stuck` / `_try_nav_hop` no longer exist in npc.gd (grep = 0 hits)

### 2.2 NpcHeadAnchor (~30 min apply)
Doc: `docs/audits/npc_head_anchor_migration.md` — apply **plus its mandatory CORRECTIONS 1–3**, especially the `_pending_swapped_head` buffer (option (a)) and keeping `@tool` (doc lines 44–46). Creates `scripts/components/npc_head_anchor.gd`.
- Fully disjoint from Locomotor (H touches :322–329, insert after :777–779 CrippleCallout block, :2592–2640, :2722–2737) — no order-induced deltas.
- **ONE STALE ANCHOR (known):** Change 2c's BEFORE block no longer matches — live npc.gd:2593–2594 rewraps the `##` doc-comment (`"…its live global pose, so / ## the glint tracks…"` vs doc's `"…so the / ## glint tracks…"`). Re-derive that BEFORE block from live, anchoring on `func _head_position()` onward (code lines :2598–2608 match). All other anchors verified live — with one presentation note: Change 2a's BEFORE block prints the four state vars tab-indented while live npc.gd has them at column 0 (the doc's own note covers it); don't be surprised by that first non-byte match.

- [ ] Applied + CORRECTIONS (pending-swapped-head buffer in)
- [ ] Change 2c applied via re-derived anchor

### 2.3 Branch point

#### GO branch: NpcTuning (~60 min apply)
Doc: `docs/audits/npc_exports_to_resource_migration.md` (untracked — committed in §6 regardless). Apply with header-corrections 1–7 **and these order-induced deltas** (because Locomotor+HeadAnchor went first):
- **DROP E24, E25, E26, E27 entirely** — their anchor code moved into `Locomotor._compute_desired`/`_try_hop`, which already read `jump_velocity` via `_tuning(body, &"jump_velocity", 0.0)` = `body.get()` → resolves through the new `NPC._get` forwarder unchanged. Nothing moves into locomotor.gd. Instead add a code comment on `Locomotor._host_jump_velocity`/`_tuning`: *"resolves through NPC._get forwarder — do not repoint to body.tuning.x"* (this replaces the doc's §7.1 doc-edit).
- **E30 applies unchanged** (`var rate := move_accel if is_on_floor() else air_accel` survives verbatim in Locomotor's rewritten `apply_velocity`, still unique).
- **E40 applies unchanged** (HeadAnchor's facade keeps the identical `return global_position + Vector3.UP * eye_height` fallback, still unique).
- Everything else (E1–E23, E28/29, E31–E39, E41, §1/§3–§6 scenes+tests) applies as written — but re-verify E39/E40-region anchors (:2552/:2608) by text since HeadAnchor shifted that area.
- Touches 6 scenes (NPC.tscn, medicine_person, TestLevel, TestLevel_2, NavSandbox, SliceTestLevel) + `weapon_stance.gd`, `talk_approach.gd`, tests.
- Doc edits to `docs/AUTHORING_GUIDE.md` / `docs/CURRENT_ARCHITECTURE.md`: these files carry user hunks — make the edits but stage BY HUNK in §6, or defer the doc edits entirely.

Then **laser_color rider** (5 min, own commit): delete the 2 decl lines from npc_tuning.gd (§1 block), the `tuning.laser_color = profile.laser_color` stamp line, the `&"laser_color"` PROFILE_STAMPED_FIELDS entry, and npc_data.gd:115 + its doc line. Stamp line + array entry MUST go together (drift test set-equality). Field count 55→54, still above the >50 floor (test_npc_data.gd:143).

#### NO-GO branch
Skip NpcTuning. **laser_color rider against live anchors** (order-independent): delete npc.gd :208–209 (`## Laser sight colour.` + decl), `&"laser_color"` at :481, stamp line :557, npc_data.gd:115 + doc line. Laser export block shrinks to `@export_group("Laser")` + `show_laser` — harmless to both applied patches. HeadAnchor's bare `eye_height` fallback stays valid; Locomotor's duck read resolves the still-declared export.

### 2.4 Remediation leftovers (all verified still pending; ~40 min total)

- [ ] **B-F63 stray stupidbody** (5 min): delete exactly 3 lines from `scenes/game.tscn` — ext_resource line 11 (`stupidbody.blend`, id `6_p57ef`) + node lines 60–61 (floating at y=5951). `6_p57ef` occurs exactly twice; after the edit, zero. `git diff` must show exactly −3 lines.
- [ ] **B-F19 ragdoll corpse-light** (15 min): `scripts/components/ragdoll.gd:4` — replace the hardcoded Sketchfab NodePath `@onready var corpse_light` with a NodeFinder lookup (pattern already in-file at :129 for the skeleton) + null-guard the :51 dereference. Add `tests/test_ragdoll_scene.gd`.
- [ ] **B-F59 test half ONLY** (10 min): first read `tests/test_level_data.gd` (80 lines, GameRoot/LevelData basics — confirmed no PlayerSpawn contract yet). Add the "every `resources/levels/*.tres` scene has a PlayerSpawn" contract test. It WILL fail red on trenchboom (`scenes/levels/trenchboom_test_level.tscn` has no PlayerSpawn/LevelRoot/NavRegion) — land it intentionally-red with a comment, OR gate it to skip trenchboom with a TODO. **The scene half + navmesh bake is EDITOR-OPEN work — explicitly out of scope today**; note it as the follow-up.
- [ ] **B-F24 grid overflow strip — DECIDE: likely DEFER.** `scripts/ui/grid_inventory_view.gd:163,:362` still skip unplaced (x<0) stacks. The file is clean but sits in the middle of the in-flight money-purse cluster (grid_tile/inventory_screen/character_inventory all dirty). Only do it if you're confident the purse work doesn't touch unplaced-stack rendering; otherwise defer to after the purse lands.
- [ ] **M1 QuestTracker split — DEFERRED (mandatory).** It moves code out of `managers/GameState.gd`, which is user-dirty. Do not touch. (Its Wave-8 riders M15 + B-F40 are already live in GameState — remaining scope is only the split itself.)
- [ ] **M13 Landing — per §1 decision** (descope note or defer; `player.gd` is user-dirty either way).

---

## 3. ONE-SHOT VERIFICATION BATCH (editor still closed)

### 3.1 Headless import — once, after ALL elected patches, before GUT
```powershell
& "C:\Users\dalla\bin\godot.cmd" --headless --path "C:/Users/dalla/3D RPG/rpg" --import
```
(ABSOLUTE `--path` mandatory — bare `.` silently fails on the spaced path.)

Confirm registration + sidecars:
```powershell
Select-String -Path "C:\Users\dalla\3D RPG\rpg\.godot\global_script_class_cache.cfg" -Pattern "NpcTuning|NpcHeadAnchor"
git -C "C:/Users/dalla/3D RPG/rpg" status --short scripts/components/ scripts/npc/ tests/
```
Expect NEW `.gd.uid` sidecars: `npc_head_anchor.gd.uid`, `test_npc_head_anchor.gd.uid`, and (GO) `npc_tuning.gd.uid`, `test_npc_tuning_forwarding.gd.uid`, plus `test_ragdoll_scene.gd.uid`. Each commits WITH its script in §6.

### 3.2 (GO only) `in`-operator scratch check
Write `rpg/scratch_in_check.gd` per the NpcTuning doc §9.4 **as amended by its header-correction 2** — the §9.4
block AS PRINTED does not compile (`Object.set()` returns void, illegal inside a ternary); use plain sequential
statements (`npc.set("sight_range", 42.0)` then print `npc.get("sight_range")` etc.). Note this check already
PASSED once on this machine (Godot v4.6.3, per the doc's "empirically resolved" section) — it is belt-and-braces.
```powershell
& "C:\Users\dalla\bin\godot.cmd" --headless --path "C:/Users/dalla/3D RPG/rpg" -s "res://scratch_in_check.gd"
```
Expect `true / 25.0 / 42.0`. If `false` → apply the doc's §8 `_get_property_list` contingency. **Delete the scratch file after.**

### 3.3 GUT fast suite (you run it — this session IS the user-asked run)
```powershell
& "C:\Users\dalla\bin\godot.cmd" --headless --path "C:/Users/dalla/3D RPG/rpg" -s addons/gut/gut_cmdln.gd -gexit
```
Expected green (this run retroactively gates Waves 5–9 + the popcorn payload):
- `test_cripple_callout.gd` (CrippleCallout verification debt — first GUT run ever)
- `test_locomotor.gd` + re-pointed `test_npc.gd` anti-stuck test (Phase B)
- `test_enemies.gd` (holds 11 of the 14 static-forwarding asserts the Locomotor doc pins — a regression here is a Phase B failure, not noise)
- `test_npc_head_anchor.gd` (new) + `test_npc_head_look.gd` (must STAY green — head-anchor doc checklist step 1)
- `test_npc_combat.gd`, `test_npc_outline.gd` (Waves 5/6, never empirically gated)
- `test_ground_movement.gd`, `test_hit_resolution.gd` (popcorn/Wave 7)
- `test_ragdoll_scene.gd` (B-F19, new)
- `test_level_data.gd` — RED on the B-F59 contract test if you landed it intentionally-red (expected; everything else in it green)
- GO only: `test_npc_tuning_forwarding.gd` + rewritten `test_npc_data.gd` dual-regex (54 fields post-rider)
- `test_money_purse.gd` may run (it's in tests/) — its result is the USER'S in-flight work; note failures, don't fix.

### 3.4 T1 combat smoke + soak (Waves 5–9 empirical gate)
```powershell
& "C:\Users\dalla\bin\godot.cmd" --headless --path "C:/Users/dalla/3D RPG/rpg" -s addons/gut/gut_cmdln.gd -gconfig=res://tests_soak/soak.gutconfig.json -gexit
```
(`tests_soak\run_soak.cmd` also works but invokes bare `godot` — needs PATH; prefer the absolute form.) Runs BOTH `test_soak.gd` and `test_combat_smoke.gd` (perceive→plan→aim→fire→hit→take_damage; damage_landed/converged/not-leaking). **Gotcha:** nav-not-synced ⇒ PENDING "INCONCLUSIVE — re-run", not failed. Re-run; never ship on a pending.

---

## 4. UNIONED PLAYTEST (one drive; TestLevel or SliceTestLevel + a NavSandbox glance)

**A. Movement seams (Locomotor Phase B — the commit gate):**
- [ ] 1. RVO: several NPCs converging on you don't pile/jitter
- [ ] 2. Combat nav-hop: pursuer hops a crate/ledge; futile pogo → give-up + HOLD (no machine-gun pogo, no pacing)
- [ ] 3. Anti-stuck/wall-slide: NPC pressed into wall/prop/NPC veers along it, then gives up + holds
- [ ] 4. Off-mesh recovery: knock an NPC off the navmesh; it steers back to walkable floor
- [ ] 5. Companion follow: recruit tails + hidden-teleports
- [ ] 6. Facing: smooth turn to travel/aim, NO twitch-fight (face_travel=false; `_face_yaw` sole facer)
- [ ] 7. Give-up bool: blocked wanderer re-picks; pursuer at unreachable target holds (CORRECTION 1)
- [ ] 7b. Hop sanity note (GO only): hop still fires (jump_velocity now a per-frame `_get`-forwarded read); jump_velocity=0 NPCs never hop

**B. Head/glint (NpcHeadAnchor):**
- [ ] 8. Rigged NPC aiming → glint blooms AT THE HEAD, tracks head yaw/animation
- [ ] 9. BodyModelSwap NPC → glint follows the SWAPPED head; head-look turns the swapped head (pending-buffer CORRECTION proof)
- [ ] 10. Mesh-less/degenerate NPC → glint falls back to capsule-top/eye-height; no NaN, no bloom at feet

**C. Tuning spot-checks (GO only):**
- [ ] 11. NavSandbox: three raiders wander INDEPENDENTLY — and for a positive proof (wander-independence alone can false-pass a shared resource), temporarily print `npc.tuning.get_instance_id()` per raider and confirm three DIFFERENT ids (the NpcTuning doc's §9.8 check)
- [ ] 12. A raider still perceives/paths/fires with authored numbers

**D. CrippleCallout debt (piggybacks on any firefight):**
- [ ] 13. Cripple a live NPC's arm/leg (non-lethal, player is attacker) → amber HUD toast "Crippled <name>'s arm/leg" AND the NPC's "My arm!"/"My leg!" bark. Lethal crippling hit → toast yes, bark suppressed. Torso → silence.

If group A fails → §7 rollback for Locomotor before committing anything that depends on it.

---

## 5. COMMIT PLAN (explicit paths ONLY; message via `-F` temp file)

Convention: write each message to a scratch file, then
```powershell
git -C "C:/Users/dalla/3D RPG/rpg" commit -F <msgfile>
```
Last line of every message exactly as CLAUDE.md specifies (its trailer names `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` — follow CLAUDE.md verbatim). Before EVERY commit: `git -C ... diff --cached --stat` and confirm nothing from the DO-NOT-SWEEP list is staged.

1. **Bookkeeping (do FIRST, independent of GO/NO-GO):** `docs/audits/npc_exports_to_resource_migration.md` (untracked) + `docs/audits/npc_decomposition_status.md` (its +13-line hunk is that file's whole diff) + this runbook file.
2. **Locomotor Phase B** (only after playtest group A passes): `scripts/npc/npc.gd`, `scripts/components/locomotor.gd`, `tests/test_npc.gd`, `scripts/npc/npc_locomotion.gd`, `scripts/components/README.md`, `scripts/npc/README.md`. (No new .uid — locomotor.gd.uid already committed.)
3. **NpcHeadAnchor:** `scripts/components/npc_head_anchor.gd` **+ .uid**, `scripts/npc/npc.gd`, `tests/test_npc_head_anchor.gd` **+ .uid**, READMEs.
4. **(GO) NpcTuning — single atomic commit:** `scripts/npc/npc_tuning.gd` **+ .uid**, `scripts/npc/npc.gd`, `scripts/npc/weapon_stance.gd`, `scripts/npc/talk_approach.gd`, `tests/test_npc_data.gd`, `tests/test_ranged_behavior.gd`, `tests/test_npc_tuning_forwarding.gd` **+ .uid**, the 6 scenes, `scripts/npc/README.md`, `docs/audits/locomotor_phase_b_migration.md` (§7.1 note if you edited the doc instead of the code comment). **`docs/AUTHORING_GUIDE.md` / `docs/CURRENT_ARCHITECTURE.md`: `git add -p` hunk-staging only, or defer.**
5. **laser_color rider** (both branches, own commit): npc.gd + npc_data.gd (+ npc_tuning.gd in GO branch) + test_npc_data.gd count if touched.
6. **B-F63:** `scenes/game.tscn` (diff must be exactly −3 lines).
7. **B-F19:** `scripts/components/ragdoll.gd`, `tests/test_ragdoll_scene.gd` **+ .uid**, `scripts/components/README.md`.
8. **B-F59 test half:** `tests/test_level_data.gd` (+ note in commit msg: scene fix + navmesh bake = editor-open follow-up).
9. **(If elected) B-F24:** `scripts/ui/grid_inventory_view.gd` + new test **+ .uid** — only after the in-flight-inventory coordination check.
10. **(If elected) M13 descope note:** `docs/audits/architecture-remediation-plan-2026-07-01.md` one-liner.

---

## 6. EDITOR-REOPEN SPOT-CHECKS (after all commits)

- [ ] NPC.tscn root shows the Tuning foldout (7-value payload) — GO only; faction_id dropdown populates; no new config warnings
- [ ] SliceTestLevel: gizmo sight-cone + alert-ring still draw for YardGuard (forwarder under `@tool`) — GO only
- [ ] TestLevel: Enemy3 tuning shows fire_range 500 / sight_range 500 / move_speed 0 — GO only
- [ ] Risk check: open + re-save `enemy.tscn`, then INSPECT THE DIFF for a spurious embedded `tuning = SubResource(...)` default-freeze BEFORE committing any editor re-save — GO only
- [ ] General: no import errors in the output panel; new components visible in Add Node dialog
- [ ] Editor-open follow-ups queued: B-F59 scene fix (PlayerSpawn/LevelRoot/NavRegion into trenchboom_test_level.tscn) + navmesh re-bake

---

## 7. ABORT / ROLLBACK (per step; steps are independent unless noted)

General: nothing is committed until its playtest/GUT gate passes, so rollback = discard working-tree files **by explicit path** (NEVER `git checkout .` — it would nuke the user's in-flight work):
```powershell
git -C "C:/Users/dalla/3D RPG/rpg" checkout -- <paths>
```
plus delete any new untracked files (`Remove-Item`).

- **Locomotor fails (compile/GUT/playtest A):** `checkout -- scripts/npc/npc.gd scripts/components/locomotor.gd tests/test_npc.gd scripts/npc/npc_locomotion.gd`. This CASCADES: HeadAnchor and NpcTuning were applied on top of the same npc.gd — if they're already in, either fix-forward Locomotor or checkout npc.gd and re-apply H (its anchors are Locomotor-independent) and T (restore E24–E27 if Locomotor is out!). Cheapest insurance: sanity-compile npc.gd after EACH patch (`--check-only` proves compilation only, not warnings): `& "C:\Users\dalla\bin\godot.cmd" --headless --path "C:/Users/dalla/3D RPG/rpg" --check-only -s scripts/npc/npc.gd`... in practice just proceed patch-by-patch and grep the seams.
- **HeadAnchor fails:** `checkout -- scripts/npc/npc.gd` + delete `scripts/components/npc_head_anchor.gd(.uid)` + `tests/test_npc_head_anchor.gd(.uid)` — then RE-APPLY Locomotor (same-file cascade). If Locomotor already passed, prefer fix-forward on the head region only (it's disjoint: :2592–2640 area).
- **NpcTuning fails:** delete `npc_tuning.gd(.uid)` + `test_npc_tuning_forwarding.gd(.uid)`, `checkout -- scripts/npc/npc.gd scripts/npc/weapon_stance.gd scripts/npc/talk_approach.gd tests/test_npc_data.gd tests/test_ranged_behavior.gd scenes/enemies/NPC.tscn scenes/medicine_person.tscn scenes/TestLevel.tscn scenes/TestLevel_2.tscn scenes/levels/NavSandbox.tscn scenes/levels/SliceTestLevel.tscn` — then re-apply Locomotor + HeadAnchor to npc.gd. (This is why NpcTuning commits ATOMICALLY and LAST.) NO-GO later stays available.
- **laser_color rider fails (drift test):** the stamp line and the PROFILE_STAMPED_FIELDS entry went out of sync — they must be deleted together; `checkout -- scripts/npc/npc.gd scripts/npc/npc_data.gd` and redo.
- **B-F63 / B-F19 / B-F24 / B-F59:** each fully independent, single-file(+test) checkouts; abort any one without affecting the rest.
- **--import produced weirdness (empty PackedScenes etc.):** should not happen with the editor closed; if it does, do NOT reopen the editor mid-session — delete `.godot/imported` artifacts is overkill; just re-run the `--import` once. Never run `--import` after reopening the editor.
- **Soak/T1 goes PENDING:** re-run (nav-not-synced inconclusive), don't rollback.
- **Anything touches a DO-NOT-SWEEP file by accident:** `git -C ... reset` (unstage, mixed) — never checkout those paths.
