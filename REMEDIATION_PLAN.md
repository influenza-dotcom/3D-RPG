# Remediation Plan — the independent assessment, re-verified

**This is a temporary working file. Delete it when the last box is ticked.** Per `CLAUDE.md`'s docs
hygiene rule, task and review files that no longer match the code get removed, not archived.

**How to use it.** Every item is written to be handed to one AI session on its own. Work top-down —
the phases are ordered by hard dependency, not by importance, and Phase 0 and Phase 1 genuinely block
most of what follows. Tick boxes as you go.

**Every finding below was re-verified against the code as it stands today**, not against the
assessment text. Statuses changed in both directions; two findings closed themselves, one was
refuted, and three problems were found that the assessment never saw.

---

## Baseline, re-measured 2026-09-02

| | |
| --- | --- |
| Test suite | ~~3756 tests, 3753 passing, 3 failing~~ → **3769 tests, all passing** (2026-08-13 23:57). ⚠ Long stale: a static count on 2026-09-02 gives **426 `tests/test_*.gd` files / 5,191 `func test_`** — the suite has grown ~38% and has **not** been re-run for this plan, so treat "all passing" as unverified |
| `git HEAD` | ~~`7f26405`~~ → ~~`0c2b11c`~~ → **`122c391`** ("Docs: catch AUTHORING_GUIDE, CURRENT_ARCHITECTURE and SYSTEM_MAP up", 2026-08-28) — `0c2b11c` is **36 commits back**; Phase 1.2 has since landed |
| Working tree | **224 paths dirty** (175 modified, 47 untracked, 2 deleted) — ordinary churn on top of a committed tree, not the un-landed tangle Phase 1 was written against. It still *moves* — it grew 166 → 224 in a day; see the concurrency warning below |
| Boot | ⚠ `scenes/game.tscn` headless is **not reliably 0 script errors**; see Phase 4 note |
| Text debt | `scripts/tools/text_debt.gd` reports `TOTAL: 0` |

> ### ⚠ Concurrency: this plan is being worked by more than one session at once
>
> On 2026-08-13 at ~23:30 three other Claude sessions were editing this repo simultaneously (one running a
> `phase1-dialogue-consequences` workflow = item 3.2). The dirty-file count moved 195 → 220 → 219 inside
> five minutes, and at 23:45 the working tree **could not boot at all** — `first_person_body.gd` referenced
> two identifiers nothing declared, cascading through `player.gd` into `InputManager.gd`. The 3769-test
> suite was green at the time; only a boot check saw it.
>
> Two consequences for anyone picking this up:
> - **Phase 1's whole-tree commit cannot be done while this is true.** It would sweep other sessions'
>   half-written files into your commits, and `CLAUDE.md` forbids sweeping for exactly this reason. Do it
>   when the tree is quiet, and verify quietness by sampling `git status` twice a minute apart.
> - **A green suite is not a working game.** That is what Phase 4.2's boot gate is for, and it earned its
>   place the first time it ran.

---

## What changed since the assessment

**Closed — do not spend time here.**

- **Stale git worktrees.** 8.7 GB across four clones: gone. `git worktree list` is 1.
- **NPC AI has no LOD (was H2).** `scripts/components/ai_lod.gd` landed while this plan was being
  written and `tests/test_ai_lod.gd` is **green** (21/21). It went from "the biggest unwritten
  performance risk" to done in a day. It is still uncommitted — that is Phase 1's problem, not H2's.

**Refuted — the assessment was wrong.**

- **"Annotation markers leak into `AUTHORING_GUIDE.md` as headings."** They do not. The four `## @`
  lines at 2776-2779 sit inside a ` ```gdscript ` fence opened at 2775. It is a worked example.
  I reported this as a doc-generator defect; it isn't one.

**Reduced — smaller than reported.**

- **"132 unwritten strings."** The `[PH]` marker does not mean unwritten. It marks *unblessed*
  copy, and much of what carries it — the Ledger's credit bands and filed reasons — is the best
  writing in the project. The real writing backlog is much smaller than the count. **What to do
  about the marker is your call, not an engineering one** (see the Do-Not-Do list).

**New — found during re-verification, not in the assessment.**

- **A third failing test nobody owned.** `test_cyber_bridge::test_parse_request_rejects_malformed_lines`.
- **C1 is materially worse than reported.** See Phase 2.
- **The nav-link regenerator silently deletes hand-placed links.** See Phase 3.4.

---

## Sequencing rules

Four constraints. Breaking them costs real rework.

1. **Phase 1 (commit) before any Phase 3 work.** Every level fix touches files that are already
   dirty. Landing them on top of ~190 uncommitted files makes the result unreviewable and
   unrevertable.
2. **The four level edits are serialized, in the given order, with a commit between each.**
   `scenes/levels/trenchboom_test_level.tscn` is a 1.1 MB func_godot scene; concurrent edits will not merge, and
   the nav re-bake rewrites its largest node block.
3. **Never hand-edit that level.** Use the editor. External writes get clobbered.
4. **Phase 2's internal order is load-bearing.** Clean the music folder *before* unsetting the
   radio's pinned track, or `radio.gd:45` falls through to a folder scan and shuffles the remaining
   commercial tracks — strictly worse than doing nothing.

---

## Phase 0 — get to green (~1 h)

Three red tests. None are yours from the assessment; all are in-flight work.

- [x] **0.1 — `bridge_server.gd:284` pushes an engine error on bad JSON.** DONE. ⚠ **The path in this
  plan was wrong**: the file is `addons/cybersunday_tools/dock_bridge/bridge_server.gd`, not
  `scripts/tools/` — `tests/test_cyber_bridge.gd:37` pins the real path. Line 284 was exact. Only ONE of
  the test's five bad lines (`"not json at all"`) actually reached the parser; the array / bare-string /
  `args: 5` rows are valid JSON caught by the `is Dictionary` check, which is why that check had to stay.
  The `parsed == null` disjunct also stays: `JSON.new().parse("null")` returns OK with `data == null`.
  Test green, 34/34. Original text follows. `JSON.parse_string()`
  raises an engine error on malformed input, and GUT 9.6 fails a test on unexpected engine errors —
  this project's own documented trap. The function's *behaviour* is correct; the engine noise is what
  fails it. Swap to `var j := JSON.new(); if j.parse(trimmed) != OK: return error_response(...)`.
  *(0.25 h)*

- [x] **0.2 — DONE, patched to `Groups.NPC`** (not deleted — the probe documents the 40-NPC A/B that
  justifies `ai_lod.gd`). All six lines were exactly as stated; lines 467 and 557 already used the const,
  and line 282's `part.begins_with("npc")` is not a group call and was left alone. `test_groups` green,
  4/4. Original text follows. **`scripts/tools/__perf_probe.gd` uses 6 raw `&"npc"` literals** (`:255,396,406,416,431,670`),
  failing `test_groups::test_no_raw_group_literals_in_production_source`. **Decide once:** either
  patch them to `Groups.NPC`, or delete the probe. Gitignoring does **not** work —
  `tests/test_groups.gd:10` walks the filesystem with `DirAccess`, not the git index, so an
  ignored-but-present file fails forever. If you still want the 40-NPC A/B for the AI-LOD work,
  patch now and delete after. *(0.25 h)*

- [x] **0.3 — DONE.** ⚠ Note for anyone re-running this: a concurrent session regenerated the doc at
  23:36 and it came out at **16 systems / 34 entries with `ai_lod` still absent** — a regeneration run
  against a tree mid-write produces a *smaller* map, not a fresher one, and the staleness test still fails.
  Re-running it on a settled tree gave 20 systems / 38 entries. Check the counter line, don't trust the
  mtime. Original text follows. **Regenerate the System Map.** Stale because `ai_lod.gd` added a new `@system` block and
  `scripts/effects/ink_outline.gd`'s `@risk` text was extended. Do this **last** of the three, since 0.1 and 0.2 can
  still move annotated source. *(0.25 h)*

  ```bash
  "C:/Users/dalla/bin/godot.cmd" --headless --path "C:/Users/dalla/3D RPG/rpg" -s scripts/tools/gen_arch_doc.gd
  ```

---

## Phase 1 — commit the tree (8–10 h)

**⚠ 1.2 is DONE — this section is history, not work.** Re-measured 2026-09-01: **36 commits have landed**
since this plan's stated HEAD, and every file the commit-group table below names is tracked. What follows
is kept only as the record of how it was split. **Only 1.1 is still open.** The tree is dirty again
(224 paths on 2026-09-02: 175 modified, 47 untracked, 2 deleted) but that is ordinary post-commit churn,
not the eight-feature tangle this item was written against.

*Original text follows.* **This is the highest-value item in the plan and the least interesting.** ~190
dirty files, zero commits, eight tangled features. Right now a single bad edit loses a day's work with no
way back, and nobody — including you in a month — can tell which change caused which behaviour.

- [ ] **1.1 — Land the export preset first.** `export_presets.cfg` is gitignored (`.gitignore:5`,
  inherited from the stock GitHub Godot template). Un-ignore it, point `export_path` at a
  repo-relative `build/`, fill `product_name`/`version`/`copyright`, add the new `icon.ico`. Ignore
  `export_credentials.cfg` instead — that split is exactly what it exists for. **Then produce a
  build.** You have never made one, and Phase 5 depends on measuring it. *(1.5 h)*

- [ ] **1.2 — Commit in these groups**, running the suite between each. Use `git add -p`; several
  files carry two features at once.

  | # | Group | Notes |
  | --- | --- | --- |
  | 1 | Rename to CYBERSUNDAY | `project.godot`, `icon.png/.ico`, README, docs |
  | 2 | Wait feature (`T`) | `WaitSettings`, `wait_screen.*`, `scripts/ui/hud_clock.gd` — Wait is on **T** (the Fallout 3/NV key); `B` is `Claim`/Befriend Pet, which was moved off T precisely to free it (`InputManager.gd:125-133`) |
  | 3 | AI LOD | `ai_lod.gd`, `scripts/npc/npc.gd`, `scripts/npc/npc_combat.gd`, `NpcAiSettings` |
  | 4 | Ink outline | `resources/shaders/ink_outline.gdshader`, `ink_outline.gd` |
  | 5 | Flashlight (the laser-sight deletions — **since reversed**) | the 8 tracked deletions landed, then the laser sight came back 2026-08-31 as its own chip-gated rig (`scripts/components/abilities/laser_sight.gd`, `scenes/player/laser_sight_rig.gd`, `resources/items/chip_laser_sight.tres`, the `LaserMesh`/`LaserSight`/`LaserSightSub` nodes at `scenes/player/camera_rig.tscn:104,112,123`). **Both ship** — the flashlight did not replace it |
  | 6 | Rent notice + grace | `scripts/components/rent_collector.gd`, the level, `DESIGN.md` |
  | 7 | Audio/light fixes | `volume_db`/`max_db`, the light-buzz wash |
  | 8 | `cyber` CLI + Bridge tab | includes the 0.1 fix |
  | 9 | Editor plugin / audit panel | `panel_audit`, `addons/cybersunday_tools/panel_audit/scan_cache.gd` |
  | 10 | Docs + `DESIGN.md` | `DESIGN.md` *was* untracked, not a doc edit (it is tracked now) |

- [ ] **1.3 — Do not commit** the dev probes (`__perf_probe.*`) unless you fix 0.2 by patching.
  **Decided: patched, keep.** ⚠ `scripts/tools/__npc_cost_probe.gd` **does not exist** — this plan
  invented it. `scripts/tools/` holds **18** `__`-prefixed probes today (`__applause_probe`,
  `__death_skip_probe`, `__first_kill_hitch_probe`, `__ghost_align_probe`, `__ink_cb_ring_shots`,
  `__ink_gap_probe`, `__ink_occlusion_shots`, `__ink_seam_shots`, `__kill_shake_probe`, `__lens_probe`,
  `__perf_probe`, `__shadow_probe`, `__shirt_qa`, `__stamina_ring_probe`, `__tts_dll_probe`,
  `__verify_shirt`, `__verify_shirt_tools`, `__viewmodel_ring_shot`). There is no `__ink_mask_probe.gd`
  either — the correction had a phantom of its own.

> **One note on the rename:** `config/name` *is* the `user://` path. Renaming to CYBERSUNDAY orphaned
> `user://RPG/` — your old `gamestate.cfg` is still sitting there, dated before the rename. A new
> `CYBERSUNDAY/gamestate.cfg` already exists, so you have played past it. If anything in the old
> profile mattered, copy it across before you forget the folder exists.

---

## Phase 2 — the legal problem (10 h, with an open tail)

**This got worse on inspection, in three ways.** It remains the only item that becomes *impossible*
rather than merely harder with time.

**It is not dev-only.** I scoped this wrong in the assessment. `ItemDb` is an autoload that
folder-scans and `load()`s every `.tres` in `resources/items/` at boot →`resources/items/rock_item.tres` →
`resources/weapons/rock_weapon.tres` → `scenes/weapons/grenade_launcher.tscn` → the 7.27 MB Call of Duty model. **It is pulled into
memory on every boot of the shipping game.**

**It is not one asset.** Live third-party content includes: the CoD model; `Secret Shop.mp3`
(a Dota 2 OST track) autoplaying from `game.tscn:51`; `hotline_miami_lr.mp3` as the death sting on
every player death; a Freesound export as the dialogue music bed; a Pixabay export in
`scenes/computerroom.tscn` — the first thing a player ever hears; a Wikimedia texture on `scenes/player/Player.tscn`; and
**twenty Sketchfab-origin GLBs**, confirmed by a literal `Sketchfab` marker inside the binaries,
including the player's own weapons (`shotgun`, `sniper_rifle`, `knife`, `hammer`, `silenced`,
`spraycan`) and `scenes/player/view_model.tscn`. A meaningful share of Sketchfab models are CC-BY-NC.

**The commercial assets are not stripped at export.** `export_presets.cfg` uses
`export_filter="all_resources"` (`:11`) with an empty `include_filter` (`:12`), and `exclude_filter`
(`:13`) already carries `tests/*,tests_soak/*,docs/*,maps/autosave/*,addons/text_to_speech/example*,addons/text_to_speech/README.md`
— so **2.6 must EXTEND that list, not replace it**. Nothing under `assets/` is covered, so even the
orphaned commercial files land in the `.pck` verbatim.

**The one piece of good news:** `C:/Users/dalla/Desktop/my fps/` does not exist. Nothing was ever
distributed. This is a repo cleanup, not a recall.

- [ ] **2.1 — Delete the CoD model** (+ `.import` + **16 orphan PNG sidecars and their 16 `.import`
  files** — there are TWO duplicate texture sets, one under `assets/models/` and one under
  `assets/textures/`; none of the 16 is referenced by anything) and replace the `Sketchfab_Scene` node in
  `grenade_launcher.tscn` with a `MeshInstance3D` + `BoxMesh` at the same transform.
  **Leave the `Muzzle` Marker3D alone** — ⚠ not because `rock_weapon.tres` consumes it (it doesn't; that
  resource only stores the PackedScene as `view_model`), but because `MuzzleRig.align_to()` finds it by
  NAME at runtime (`muzzle_rig.gd:39` → `NodeFinder.find_first_by_name(node, "muzzle")`), as does
  `npc.gd:3207`. The instruction is right; the stated reason was not.
  ⚠ **Do not "fix" the hardcoded `Sketchfab_Scene` NodePaths** in `gun_mesh.gd:56,128`,
  `muzzle_rig.gd:28,36` and `weapon_model_swapper.gd:71-72` — they resolve against `view_model.tscn`'s
  identically-named node, not against this scene. Also: the 7.27 MB GLB imports to a **12.0 MB `.scn`**,
  which is what actually loads; and it is *loaded, not instantiated*, so expect no visible node at boot.
- [ ] **2.2 — Purge the music/sfx folder**: `Secret Shop.mp3`, `Secret Shop v3.mp3`,
  `Jakub's Ladder.mp3`, `hotline_miami_lr.mp3`, and **two files this plan missed**:
  `resources/weapons/Secret Shop.flac` (**19.4 MB** — the same Dota 2 track in lossless, referenced by
  nothing; ⚠ read `tests/test_devtools_browser.gd:91` first, it names this file as the non-resource that
  must be filtered out) and `resources/weapons/seamless-cracked-asphalt-texture-J009-03.avif` (1.35 MB,
  unreferenced, commercial-looking slug).
  `Secret Shop v3.mp3` and `Jakub's Ladder.mp3` are **orphans — delete, no rewire needed**; they are
  reachable only through the radio's folder scan. Rewire `game.tscn:9/51` and
  `resources/levels/TestLevel.tres:4` (⚠ qualify the path — `scenes/levels/TestLevel.tscn` also exists). Set
  `PlayerFeedbackSettings` `death_sting` to **null** — `death_mix.gd:36` documents null as inert by
  design and `test_death_mix.gd:158` already covers that path.
- [ ] **2.3 — Only now** delete `RIP Granny 😔🙏.mp3` and **repoint** (do not merely unset)
  `scenes/throwable/radiothrowable.tscn`'s `track`. Unsetting it triggers the folder scan.
  ⚠ **This step has no target as written, and that is a content decision, not an engineering one.**
  `assets/audio/music/` holds 6 files today; 2.2 + 2.3 delete four, and **two** survive — neither cleared:
  `569856__danlucaz__hip-hop-loop-2.wav` (the Freesound export flagged below, already wired as the dialogue
  music bed, still needing its own attribution) and `BEST OF CORY SONG (ORIGINAL VERSION).mp3` (added
  2026-08-22, pinned on the trenchboom level's radio — provenance **UNKNOWN**, licence TODO, see
  `ATTRIBUTION.md` table C; its ID3 tag is a bare FFmpeg `TSSE` frame with every title/artist frame
  stripped). So there is still no cleared in-folder track to point at — the conclusion is unchanged, but
  it no longer rests on the folder emptying to a single file.
  Two ways out: commission/record one original loop, or point `track` at an already-cleared clip
  as a stopgap. `track` is a plain `@export var track: AudioStream` (`radio.gd:38`) and a pinned track
  bypasses the scan entirely (`:453-454`), so it may point anywhere under `res://` — not just inside
  `music_folder`. Also set `fallback_audio` on `scenes/components/radio.tscn`, or the next designer-placed
  Radio has the same hole. And note `radio.gd:460-461` can resolve the folder to `Settings.music_folder` —
  the **player's own music directory** — so an unset track can pull in arbitrary user audio.
  ⚠ The trenchboom radio's pin is an **editable-children override** in
  `scenes/levels/trenchboom_test_level.tscn` (`[node name="Radio" parent="Radio" index="3"]` +
  `[editable path="Radio"]` at EOF), NOT the prefab — so deleting that mp3 needs BOTH the prefab's `track`
  and that override repointed. Grep for `[editable path=` before assuming a prefab edit covers every radio.
- [x] **2.4 — DONE, committed `0c2b11c`.** `LICENSE` (all-rights-reserved — the only honest position while
  the table has UNKNOWN rows) and `ATTRIBUTION.md`, pre-populated with the full verified inventory: every
  path checked to resolve, every size measured, every wiring site cited.
- [ ] **2.5 — Fill the table.** ⚠ **22** Sketchfab-marked GLBs, not ~20 (21 project-owned + 1 GUT test
  fixture at `addons/gut/old_japanese_store__lowpoly.glb`, which is vendored and needs nothing).
  ⚠ **And a tail no GLB deletion reaches:** `scenes/weapons/silenced.tscn`, `scenes/weapons/spraycan.tscn`
  and — by inheritance — `scenes/player/view_model.tscn`, **the player's own default gun rig**, have their
  Sketchfab geometry **baked inline as `sub_resource` ArrayMeshes** with no `.glb` `ext_resource` at all
  (the origin survives in `resource_name`, e.g. `silenced.tscn:9`
  `resource_name = "Sketchfab_Scene_Cylinder_Material_004_0"`). No binary grep finds these. Replacing them
  means re-authoring mesh data inside a `.tscn`, and the `Sketchfab_Scene` **node name must survive** — it
  is a hardcoded NodePath in three scripts (see 2.1).
  **This is the open tail: 6 h is a floor, not an estimate.** Re-finding a model by slug from a GLB
  binary is not reliably possible, and anything unfindable — or CC-BY-NC — needs *replacing*, not
  documenting. Start here; it only gets harder.
- [ ] **2.6 — *Extend* the existing `exclude_filter`** (six entries already, quoted above — do not
  overwrite them) so orphaned third-party files stop shipping. Fold into the same `export_presets.cfg`
  pass as 1.1.
- [ ] **2.7 — Verify windowed, not headless.** A broken material loads clean headlessly and passes
  every test. You must look at the grenade launcher and the radio.

---

## Phase 3 — the level, serialized (≈8 h + an uncosted tail)

One at a time, commit between each, in the editor.

- [ ] **3.1 — Give the four shipping NPCs stable identity.** `save_id` count in the level is **zero**,
  and three of the four are named `@CharacterBody3D@82210`, `@CharacterBody3D@47885` and
  `_CharacterBody3D_47885`. `NPC.snapshot_key()` falls back to `level|node_path`, so those
  auto-generated names *are* the save keys; recreating a node changes the number and silently orphans
  its death record. **Rename and set `save_id` in one edit** — the change is itself save-invalidating,
  so do it once. Do this first: it renames the node whose `Talkable` 3.2 then edits. *(1 h)*

- [ ] **3.2 — Make the two offers do something.** Still zero consequence fields authored in the whole
  level. The only gate is `required_stat = &"streetwise"` at `:2011-2017`, branching to
  `Resource_5ulgd` — which has **no `choices` key at all**, so the conversation just ends. Wire
  `start_quest_on_choice` on the old man's 56-Zorkmid ask and `complete_quest_id` + `give_money` on
  the raider's contract. The systems are finished; this is authoring. *(3 h)*

- [ ] **3.3 — Give `payment_missed` a real consequence.** Its only listener today is the debug overlay
  (`scripts/components/debug_event_ticker.gd:616` → `_on_rent_missed` at `:729`, instanced via
  `scenes/game.tscn:18`) — a printed line is not a consequence, and nothing in the game reacts to a
  missed rent. Two cautions from the code:
  - Copy the guards from `ledger_accrual.gd:41-45` (`profile_active`, `reload_pending()`,
    `is_alive()`). `RentCollector.collect()` has none, so a dev boot or a test-level dawn would dock
    a profile that isn't running.
  - **An arrears penalty already exists** at `ledger_accrual.gd:52`. A player both in debt and short
    on rent would take two hits per day. That may be what you want — decide it deliberately.

  Code half (the export) lands before the scene half (arming it). *(1.5 h)*

- [ ] **3.4 — Re-bake navigation. ⚠ Read this before running the generator.**
  `generate_nav_links.gd:99-100` does `region.remove_child(old); old.free()` on the entire
  `GeneratedNavLinks` container — and **10 hand-placed links live inside it**: the
  `_NavigationLink3D_492xx` nodes, as distinct from the generator's own `Link_dn_` / `Link_tw_` /
  `Link_wk_` names, at `:4714, 4728, 4749, 4896, 4903, 4910, 4945, 4966, 5008, 5148` (re-located
  2026-09-01 — the level has been re-authored, so grep `_NavigationLink3D_` rather than trusting these).
  Regenerating without moving them out first **deletes them silently**. Move them to a sibling node,
  then re-bake, then regenerate — and note ⚠⚠ `const APPLY := true` at `:35`: it **WRITES by default**.
  The file's own header at `:9` now says "DESTRUCTIVE BY DEFAULT" and the const carries an inline
  `SHIPS TRUE` note, so the source no longer misleads you — but the *behaviour* is unchanged. Set
  `APPLY = false` yourself before any exploratory run, or the `if not APPLY or
  specs.is_empty(): return` guard at `:93` falls straight through into the wipe.

  **Honest framing: this is a 3 h investigation, not a 3 h fix.** The bake parameters are already
  correct to policy (`parsed_geometry_type = 1`, `agent_radius = 0.6`, `agent_max_climb = 0.4`), so
  the likely outcome is a re-bake that changes little and a decision about authored brush geometry
  that is not costed here. The level has 94 baked islands stitched by 113 links and **no automated
  navigation coverage** — `tests_soak` pins `scenes/levels/NavSandbox.tscn`, not this level — so regressions are
  playtest-only. Do it last.

---

## Phase 4 — infrastructure (2.5 h) — **DONE, committed `610b4bc`**

All four landed as one path-scoped commit (every target file was clean and uncontested). Two notes that
change what the plan said:

- **4.2's stated rationale was wrong.** The soak tier is *not* blind to script errors — GUT 9.6 installs
  an error tracker (`gut_config.gd:57 failure_error_types = ["engine","gut","push_error"]`) that fails a
  test on any engine error raised **while one of its own tests is running**. `SoakReport.ok()` is blind
  (it reads only nav sync / strand cycles / node drift), but the tier is not. The real justification is
  **coverage**: `tests_soak` only ever boots `NavSandbox.tscn`, so `game.tscn`'s boot chain had none, and
  errors outside a running test are bucketed under NO_TEST and vanish. Two traps the step is shaped
  around: `--quit-after` exits **0 regardless**, so the exit code proves nothing, and Godot writes script
  errors to **stderr**, so the log must be captured `2>&1`. The grep is the gate. It is deliberately
  narrow (`SCRIPT ERROR` only) — `Cannot open file` also matches benign import noise and would flake.
  **It paid for itself immediately**: the first local run caught a live parse-error cascade that the
  3769-test suite was green through.
- ⚠ **A bigger finding, and a NEW plan item: CI has never seen the real assets.** `.gitattributes` routes
  `*.glb/*.png/*.jpg/*.wav/*.ogg/*.avif` through **Git LFS**, and `actions/checkout@v4` does **not** fetch LFS
  objects by default. Verified: `git cat-file -p HEAD:assets/models/psx_style_tree.glb` returns a 131-byte
  pointer. So every CI step has always run against pointer files — `--import` imports stubs and
  `validate_all.gd` validates a project whose models, textures and audio are text files. The unit suite never
  noticed because it tests off-tree logic. **Treat a green CI as "the logic compiles and passes", not "the
  game runs".** Do **not** fix this with a bare `lfs: true`: `assets/models/dog.glb` alone is **409 MB** and
  referenced by nothing, so a naive fetch burns the LFS bandwidth quota on every push. The fix is ordered —
  drop the unreferenced giants and populate `exclude_filter` (**2.6**) *first*, then enable LFS here. Because
  of this, the boot gate landed **`continue-on-error: true`**; flip it to blocking after one green CI run.
- **A bug the plan never saw.** `tests/run.cmd`, `tests_soak/run_soak.cmd` and
  `scripts/tools/validate.cmd` all ended with a bare `popd`. A `.cmd` exits with the status of its **last**
  command, so every one of them **reported success for a failing run** — including `validate.cmd`, which
  advertises itself as CI-gateable. Verified empirically (old shape returns 0 for a command that exited 3;
  new shape returns 3) and fixed in the same commit.

- [x] **4.1 — Bump CI to Godot `4.7.1`.** Done; mismatch step added and tested in both directions
  (4.7.1 passes, 4.6.3 correctly fails). The `4.7.1-stable` tag and its `linux.x86_64` asset both resolve,
  so no URL-shape change was needed. `.github/workflows/ci.yml:24` pins `4.6.3`; the project has
  declared 4.7 since July and your binary is 4.7.1. The download URL is built from that variable, so
  use the exact string `4.7.1`. Add a step that greps `config/features` from `project.godot` and
  fails on a major.minor mismatch. Land this **after** Phase 0, or the bump gets blamed for
  pre-existing failures. *(0.5 h)*

- [x] **4.2 — Make the soak tier fail on engine errors.** Done (see the rationale correction above). It currently reports `ok=true` through
  frame-spamming script errors — I saw exactly that happen on one run. Add a boot gate that runs
  `game.tscn --quit-after` and fails on `SCRIPT ERROR` in stdout. Five lines, and it upgrades your
  best test tier into a real gate. *(0.5 h)*

- [x] **4.3 — Move `tests_soak/` onto push in CI.** Done; the `if:` gate is gone and `workflow_dispatch` stays for manual runs. (The "27 s" figure is an observation, not a repo fact.) It is gated to `workflow_dispatch` and runs in
  27 s. It is the only automated thing that touches the real runtime. *(0.5 h)*

- [x] **4.4 — Fix the README's first instruction.** Done **and committed**: `README.md:56` reads "The main scene is `scenes/computerroom.tscn`" and `:60` flags `scenes/game.tscn` as a level-authoring shortcut, not the way in. (`README.md` is still `M` in `git status`, but on unrelated later edits — the fix itself is in.) Confirmed the error was README-only; `AUTHORING_GUIDE.md` already documents `computerroom.tscn` correctly. The old text said "Run
  `scenes/game.tscn`"; `project.godot:14` boots `computerroom.tscn`. Following the old README skipped the
  warning card, the TOS gate, character creation and the implant purchase — all four are
  `StartMenu`-owned, not autoloads. One sentence. *(0.25 h)*

---

## Phase 5 — gated and deferred

- [ ] **5.1 — Boot time (H1). Do not start this until you have measured an exported build.**
  38 autoloads, 20 of them UI `.tscn` screens. The lazy-shim conversion is ~18 h — but the measured
  saving is **GDScript compilation of the screen scripts**, and `export_presets.cfg` sets
  `script_export_mode=2` (binary tokens, precompiled). In a shipped build that cost largely does not
  exist. Phase 1.1 makes an export possible; measure that first, then decide.

  Two things to know if you do it: `managers/InputManager.gd:250` (`gameplay_suppressed()`) calls
  `NameEntryDialog.is_open()` *directly*, outside the modal registry (a second direct call sits at `:325`),
  and `any_modal_open()` at `:276` iterates all **19** `_modal_reg` rows — this is the per-frame source
  of truth for movement/fire suppression, so a shim that answers wrong unfreezes the player under an
  open menu. And you would be trading a boot cost for the in-game hitch `PreloadManager` exists to
  prevent.

  **Free win available now:** deleting the CoD asset (2.1) removes a 7.27 MB GLB + 8 textures from
  the boot path. Measure after Phase 2, before costing this at all.

- [ ] **5.2 — Docs.** **189 occurrences of a bogus `rpg/` path prefix** in `docs/AUTHORING_GUIDE.md`
  (re-counted 2026-09-02; the guide is live and its line numbers drift weekly — re-derive these rather
  than trusting them).
  ⚠ **"One sed pass" is the bug — 186 are bogus, 3 are legitimate prose** about the
  repo root, at `:133` ("all under the repo's `rpg/` folder"), `:4195` ("from `rpg/` --", a cwd
  instruction) and `:5360` ("the project root is `rpg/`"). A blind `s|rpg/||g` turns those into empty
  backticks. Anchoring on a leading backtick under-matches too: `:4418` and `:4427` are headings where the
  prefix is not backticked. Use a **segment-anchored** pass, verified by executing it on a scratch copy —
  it leaves exactly the 3 prose mentions and nothing else:

  ```bash
  sed -i -E 's#\brpg/(scripts|resources|scenes|managers|tests|addons|docs|project\.godot|CLAUDE\.md)#\1#g' docs/AUTHORING_GUIDE.md
  ```

  Then verify with `grep -o 'rpg/' docs/AUTHORING_GUIDE.md | wc -l` — must be **3**, on lines 133, 4195,
  5360. Do **not** use `grep -c`; it counts lines, not occurrences (this plan's own earlier text made that
  mistake — it returns 3 here only because the survivors happen to sit on 3 distinct lines). Human-read
  `:133` afterward: it keeps one legitimate mention while four paths on the same line get stripped.
  Land it with commit group 10. *(0.5 h)*

  **Recommendation: freeze, don't shrink.** `AUTHORING_GUIDE.md` is 5,402 lines / ~1.03 MB and its
  423 over-long lines hold half its bytes — but rewriting it is days of work on something that is not
  the product, and its factual accuracy is genuinely high (every `res://` path in it resolves). Add
  no new sections until the pipeline being documented has produced one shipping asset.

- [x] **5.3 — MEASURED, committed `c2f8f9b`.** ⚠ **"Verifying is cheap" was wrong.** The 13 bullets pack
  **45 sub-checks**; each was searched against `tests/`, and every "covered" answer was then adversarially
  re-checked by opening the cited assertion. **24 of 45 first-pass answers were downgraded on that second
  read.** Final: **6 genuinely closed by a test, 10 partial (inputs pinned, outcome not), 29 need a driven
  game.** The recurring error was counting a **source-string grep** as coverage — e.g. the dry-click-SFX
  item is "pinned" by asserting a substring exists in `weapon_stance.gd`, which cannot see the branch
  reordered around a still-present gate. This is not a gap to close with more tests: `CLAUDE.md` forbids
  running `Player._ready`/`NPC._ready` under GUT **by design**, so in-tree runtime behaviour is
  playtest-verified on purpose, and the remainder is timing, audio mixing, visual fades and input feel.
  One item's *wording* was also stale (the wallet-negative clause — see the commit). The measurement is
  now recorded in a header block in `ARCHITECTURE_REVIEW.md` so nobody repeats the analysis.
  **The answer to this item is: play the game.**

---

## Do NOT do these

Each one looks like an obvious cleanup and each one breaks something.

- **Do not fill the empty bark arrays.** 21 pools are empty, and **14 assertions across FIVE test files**
  pin `size() == 0` — `test_attack_reactions.gd:17,18,44`, `test_hostility.gd:580-582,623,634,635,636`,
  `test_body_discovery.gd:61`, `test_default_barks.gd:95,96`, `test_npc.gd:627` (the plan's "12+ across two
  files" under-counted the blast radius). Emptiness is a deliberate contract from the AI-text scrub.
  ⚠ **But it is not an absolute block on shipping barks**, which the original wording implied: `bark_set.gd`
  exposes the same categories as designer-authored `@export` arrays, and `npc.gd:2223 _pick_bark(fallback,
  override)` is the seam. **Authoring a `BarkSet` `.tres` adds barks and breaks nothing** — all 14
  assertions read the `NPC.*_LINES` const fallback. That is the supported route; editing the consts is not.
- **Do not bulk-strip `[PH]` markers.** ⚠ The rule is right; the stated reason is wrong. It is **not**
  "zero test signal": `test_player_text.gd:103-106` only checks that a *present* marker is well-formed, but
  separately **~58 assertions across 21 test files embed the literal `"[PH] "` in an expected value**
  (e.g. `player_text.gd:47 PROMPT_OPEN_DOOR` is pinned by `test_door.gd:55`). So a bulk strip fails the
  suite **loudly and unevenly** — the worst of both, not a silent convention break. Anyone removing a
  marker must grep `tests/` for the literal string first, and that is necessary but not sufficient: the
  marker also appears mid-expression (`player_text.gd:479`), not only in const declarations.
- **Do not gitignore `__perf_probe.gd` to silence `test_groups`.** The test walks the filesystem.
  Delete it or fix it.
- **Do not run `scripts/tools/generate_nav_links.gd` before rescuing the 10 hand-placed links.** It ships
  `APPLY := true` — there is no harmless "just to see" run. See 3.4.
- **Do not hand-edit `trenchboom_test_level.tscn`.** Editor only.
- **Do not extract anything from `scripts/player/player.gd` or `npc.gd`.** The extractions work — I checked — but
  the marginal one buys almost nothing. Resume only when a specific feature is blocked by file size.

---

## Effort summary

| Phase | Work | Hours |
| --- | --- | --- |
| 0 | Get to green | 1 |
| 1 | Export preset + commit the tree | 8–10 |
| 2 | Legal cleanup + attribution | 10 *(open tail)* |
| 3 | Level: identity, consequence, rent, nav | 8 *(open tail on nav)* |
| 4 | CI, soak gate, README | 2.5 |
| 5 | Docs sed + playtest checklist | 1 |
| | **Total, excluding gated H1** | **≈31–33 h** |
| 5.1 | Boot time — **gated on measuring a build** | 18 |

**If you only do three things:** Phase 0 (an hour, and green tests are worth more than they cost),
Phase 1 (your work is currently one bad edit from gone), and item 2.1 (delete the Call of Duty model
— it is on your boot path and it takes ten minutes).
