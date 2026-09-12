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

## Baseline, re-measured 2026-09-11

| | |
| --- | --- |
| Test suite | ~~3756 tests, 3753 passing, 3 failing~~ → ~~3769 tests, all passing (2026-08-13)~~ → a static count on 2026-09-11 gives **432 `tests/test_*.gd` files / 5,394 `func test_`**. The full suite was last run **green on 2026-09-09** (`48c81e73`, "The full GUT run is green again") |
| `git HEAD` | ~~`7f26405`~~ → ~~`0c2b11c`~~ → ~~`122c391`~~ → **`98b305fb`** (2026-09-11) — `122c391` is **40 commits back**; Phase 1.2 landed long since |
| Working tree | **A few dozen paths dirty at any time** — other Claude sessions edit this tree concurrently, so any pinned count is stale within the hour. It is ordinary churn on top of a committed tree, not the un-landed tangle Phase 1 was written against; see the concurrency warning below |
| Boot | ⚠ `scenes/game.tscn` headless is **not reliably 0 script errors**; the Phase 4 boot gate exists for exactly this |
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

- **Stale git worktrees.** 8.7 GB across four clones: gone. `git worktree list` now shows the main checkout plus
  seven under `.claude/worktrees/` — those are live Claude Code session worktrees, not stale clones; leave them alone.
- **NPC AI has no LOD (was H2).** `scripts/components/ai_lod.gd` landed while this plan was being
  written and `tests/test_ai_lod.gd` is **green** (21/21). It went from "the biggest unwritten
  performance risk" to done in a day. Both files are tracked now (they landed with Phase 1.2).

**Refuted — the assessment was wrong.**

- **"Annotation markers leak into `AUTHORING_GUIDE.md` as headings."** They do not. The `## @system NPC Brain`
  block (under "Keeping the System Map in sync" — `rg -n '@system NPC Brain' docs/AUTHORING_GUIDE.md`, ~`:3283`
  today) sits inside a ` ```gdscript ` fence. It is a worked example.
  I reported this as a doc-generator defect; it isn't one.

**Reduced — smaller than reported.**

- **"132 unwritten strings."** The `[PH]` marker does not mean unwritten. It marks *unblessed*
  copy, and much of what carries it — the Ledger's credit bands and filed reasons — is the best
  writing in the project. The real writing backlog is much smaller than the count. **What to do
  about the marker is your call, not an engineering one** (see the Do-Not-Do list).

**New — found during re-verification, not in the assessment.**

- **A third failing test nobody owned.** `test_cyber_bridge::test_parse_request_rejects_malformed_lines` (fixed, Phase 0).
- **C1 is materially worse than reported.** See Phase 2.
- **The nav-link regenerator silently deletes hand-placed links.** It did — see Phase 3.4.

---

## Sequencing rules

Four constraints. Breaking them costs real rework.

1. **Land each Phase 3 level fix on a quiet, committed tree.** Phase 1.2 (the big commit) is done; the
   rule survives because the level file is always dirty in someone's session, and a level edit landed on
   top of another session's half-written change is unreviewable and unrevertable.
2. **The four level edits are serialized, in the given order, with a commit between each.**
   `scenes/levels/trenchboom_test_level.tscn` is a 1.1 MB func_godot scene; concurrent edits will not merge, and
   the nav re-bake rewrites its largest node block.
3. **Never hand-edit that level.** Use the editor. External writes get clobbered.
4. **Phase 2's internal order is load-bearing.** Clean the music folder *before* unsetting the
   radio's pinned track, or the radio's `_load_playlist()` falls through to a folder scan and shuffles the remaining
   commercial tracks — strictly worse than doing nothing.

---

## Phase 0 — get to green

**Done** — all three red tests fixed (`bridge_server.gd` JSON parse, `__perf_probe.gd` patched to
`Groups.NPC`, System Map regenerated on a settled tree); the suite has been green since, last confirmed
2026-09-09 (`48c81e73`).

---

## Phase 1 — commit the tree (8–10 h)

**⚠ 1.2 is DONE — only 1.1 is still open** (1.3 below is a decision record, kept for the probe census).
The tree is always a little dirty (a few dozen paths, moving with the concurrent sessions), but that is
ordinary post-commit churn, not the eight-feature tangle this phase was written against.

- [ ] **1.1 — Land the export preset first.** `export_presets.cfg` is gitignored (`.gitignore:5`,
  inherited from the stock GitHub Godot template). Un-ignore it, point `export_path` at a
  repo-relative `build/`, fill `product_name`/`version`/`copyright`, add the new `icon.ico`. Ignore
  `export_credentials.cfg` instead — that split is exactly what it exists for. **Then produce a
  build.** You have never made one, and Phase 5 depends on measuring it. *(1.5 h)*

- [x] **1.2 — Done** — the ~190-file tangle was committed in ten path-scoped groups (36 commits landed by
  2026-09-01; every file the group table named is tracked).

- [ ] **1.3 — Do not commit** the dev probes (`__perf_probe.*`) unless you fix 0.2 by patching.
  **Decided: patched, keep.** ⚠ `scripts/tools/__npc_cost_probe.gd` **does not exist** — this plan
  invented it. `scripts/tools/` holds **18** `__`-prefixed probes today (re-listed 2026-09-11: `__applause_probe`,
  `__death_skip_probe`, `__first_kill_hitch_probe`, `__ghost_align_probe`, `__hitmarker_warm_probe`,
  `__ink_cb_ring_shots`, `__ink_gap_probe`, `__ink_occlusion_shots`, `__ink_seam_shots`, `__kill_shake_probe`,
  `__lens_probe`, `__perf_probe`, `__prewarm_visibility_probe`, `__respawn_viewmodel_probe`, `__shadow_probe`,
  `__stamina_ring_probe`, `__tts_dll_probe`, `__viewmodel_ring_shot` — the `__shirt_qa` / `__verify_shirt*`
  trio an earlier census listed is gone). There is no `__ink_mask_probe.gd`
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
(a Dota 2 OST track) autoplaying from the `Player/Music` AudioStreamPlayer3D in `game.tscn`; `hotline_miami_lr.mp3` as the death sting on
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
  NAME at runtime (`muzzle_rig.gd`'s `_find_muzzle_marker()` → `NodeFinder.find_first_by_name(node, "muzzle")`),
  as does `npc.gd`'s `_find_muzzle_marker()`. The instruction is right; the stated reason was not.
  ⚠ **Do not "fix" the hardcoded `Sketchfab_Scene/PlayerMuzzle` NodePaths** in `gun_mesh.gd` (the muzzle
  getter and the muzzle-FX pass), `muzzle_rig.gd` (`_ready` / `align_to`) and `weapon_model_swapper.gd`
  (`_set_placeholder_hidden`) — they resolve against `view_model.tscn`'s
  identically-named node, not against this scene. Also: the 7.27 MB GLB imports to a **12.0 MB `.scn`**,
  which is what actually loads; and it is *loaded, not instantiated*, so expect no visible node at boot.
- [ ] **2.2 — Purge the music/sfx folder**: `Secret Shop.mp3`, `Secret Shop v3.mp3`,
  `Jakub's Ladder.mp3`, `hotline_miami_lr.mp3`, and **two files this plan missed**:
  `resources/weapons/Secret Shop.flac` (**19.4 MB** — the same Dota 2 track in lossless, referenced by
  nothing; ⚠ read the `Secret Shop.flac` comment in `tests/test_devtools_browser.gd` first, it names this
  file as the non-resource that must be filtered out) and `resources/weapons/seamless-cracked-asphalt-texture-J009-03.avif` (1.35 MB,
  unreferenced, commercial-looking slug).
  `Secret Shop v3.mp3` and `Jakub's Ladder.mp3` are **orphans — delete, no rewire needed**; they are
  reachable only through the radio's folder scan. Rewire `game.tscn` (the `Secret Shop.mp3` ext_resource and
  `Player/Music`'s `stream =`) and
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
  bypasses the scan entirely (`_load_playlist()`'s `if track != null:` early return), so it may point anywhere
  under `res://` — not just inside `music_folder`. Also set `fallback_audio` on `scenes/components/radio.tscn`, or the next designer-placed
  Radio has the same hole. And note `radio.gd`'s `_effective_folder()` can resolve the folder to
  `Settings.music_folder` — the **player's own music directory** — so an unset track can pull in arbitrary user audio.
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

- [ ] **3.1 — Give the seven shipping NPCs stable identity.** `save_id` count in the level is **zero**
  (re-checked 2026-09-11), and six of the seven `NPC.tscn` instances carry editor auto-names
  (`@CharacterBody3D@82210`, `@CharacterBody3D@47885`, `_CharacterBody3D_47885`, `_CharacterBody3D_47886`,
  `_CharacterBody3D_45429`, `@CharacterBody3D@46794`); only the first is called `NPC`. `NPC.snapshot_key()`
  falls back to `level|node_path`, so those auto-generated names *are* the save keys; recreating a node changes the number and silently orphans
  its death record. **Rename and set `save_id` in one edit** — the change is itself save-invalidating,
  so do it once. Do this first: it renames the node whose `Talkable` 3.2 then edits. *(1 h)*

- [ ] **3.2 — Make the two offers do something.** Still zero consequence fields authored in the whole
  level. The only gate is the `required_stat = &"streetwise"` line (grep it; ~`:2946` today), branching to
  `Resource_5ulgd` — which has **no `choices` key at all**, so the conversation just ends. Wire
  `start_quest_on_choice` on the old man's 56-Zorkmid ask and `complete_quest_id` + `give_money` on
  the raider's contract. The systems are finished; this is authoring. *(3 h)*

- [ ] **3.3 — Give `payment_missed` a real consequence.** Its only listener today is the debug overlay
  (`scripts/components/debug_event_ticker.gd`'s `_connect_if(found, &"payment_missed", _on_rent_missed)` →
  `_on_rent_missed`, on `scenes/game.tscn`'s `DebugEventTicker` CanvasLayer) — a printed line is not a consequence, and nothing in the game reacts to a
  missed rent. Two cautions from the code:
  - Copy the guards from `ledger_accrual.gd:41-45` (`profile_active`, `reload_pending()`,
    `is_alive()`). `RentCollector.collect()` has none, so a dev boot or a test-level dawn would dock
    a profile that isn't running.
  - **An arrears penalty already exists** at `ledger_accrual.gd:52`. A player both in debt and short
    on rent would take two hits per day. That may be what you want — decide it deliberately.

  Code half (the export) lands before the scene half (arming it). *(1.5 h)*

- [x] **3.4 — Re-bake navigation. CLOSED 2026-09-03 (`02afb858`, "359 regenerated nav links") — and the
  hazard this item warned about FIRED.** The ten hand-placed `_NavigationLink3D_492xx` links that lived inside
  `GeneratedNavLinks` are **gone**: `generate_nav_links.gd` does `region.remove_child(old); old.free()` on the
  whole container, ships `const APPLY := true` (its header says "DESTRUCTIVE BY DEFAULT"), and the regeneration
  swept them along with the generator's own `Link_dn_` / `Link_tw_` / `Link_wk_` nodes. **Standing rule from
  that: hand-authored links live OUTSIDE `GeneratedNavLinks`** — siblings of it under the `NavigationRegion3D`,
  never children — and set `APPLY = false` before any exploratory run. Today the level holds **449
  `NavigationLink3D` nodes, all under `GeneratedNavLinks`**. The bake parameters were already correct to
  policy (`parsed_geometry_type = 1`, `agent_radius = 0.6`, `agent_max_climb = 0.4`), and there is still
  **no automated navigation coverage** of this level — `tests_soak` pins `scenes/levels/NavSandbox.tscn` — so
  nav regressions here remain playtest-only.

---

## Phase 4 — infrastructure

**Done** — committed `610b4bc` (CI on Godot 4.7.1 with a version-mismatch step, `tests_soak` on push, a
`game.tscn --quit-after` boot gate grepping `SCRIPT ERROR` from `2>&1`, the README's first instruction fixed,
and the bare-`popd` `.cmd` exit-code bug); the CI-red-on-LFS-pointers finding it surfaced was resolved
2026-09-10 (both jobs `git lfs pull` through an `actions/cache`). **One residual:** the boot gate still runs
`continue-on-error: true` — flip it to blocking after the first green CI run.

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
  (re-counted 2026-09-11 with `rg -o 'rpg/' | wc -l`, on 95 lines; the guide is live and its line numbers
  drift weekly — re-derive these rather than trusting them).
  ⚠ **"One sed pass" is the bug — 186 are bogus, 3 are legitimate prose** about the
  repo root, at `:133` ("all under the repo's `rpg/` folder"), `:4314` ("from `rpg/` --", a cwd
  instruction) and `:5483` ("the project root is `rpg/`"). A blind `s|rpg/||g` turns those into empty
  backticks. Anchoring on a leading backtick under-matches too: the `#### ShadowVolume (rpg/scripts/...)` and
  `#### PlayerLightLevel (rpg/scripts/...)` headings (`:4537`, `:4546`) carry the prefix un-backticked. Use a
  **segment-anchored** pass, verified by executing it on a scratch copy — it leaves exactly the 3 prose mentions and nothing else:

  ```bash
  sed -i -E 's#\brpg/(scripts|resources|scenes|managers|tests|addons|docs|project\.godot|CLAUDE\.md)#\1#g' docs/AUTHORING_GUIDE.md
  ```

  Then verify with `grep -o 'rpg/' docs/AUTHORING_GUIDE.md | wc -l` — must be **3**, on lines 133, 4314,
  5483. Do **not** use `grep -c`; it counts lines, not occurrences (this plan's own earlier text made that
  mistake — it returns 3 here only because the survivors happen to sit on 3 distinct lines). Human-read
  `:133` afterward: it keeps one legitimate mention while four paths on the same line get stripped.
  Land it with commit group 10. *(0.5 h)*

  **Recommendation: freeze, don't shrink.** `AUTHORING_GUIDE.md` is 5,525 lines / ~1.06 MB and its
  hundreds of over-long lines hold half its bytes — but rewriting it is days of work on something that is not
  the product, and its factual accuracy is genuinely high (every `res://` path in it resolves). Add
  no new sections until the pipeline being documented has produced one shipping asset.

- [x] **5.3 — Done** — measured and committed `c2f8f9b`: of the 45 playtest sub-checks, 6 are closed by a test,
  10 partial, 29 need a driven game; the table lives in `ARCHITECTURE_REVIEW.md` so nobody repeats the analysis.
  **The answer to this item is: play the game.**

---

## Do NOT do these

Each one looks like an obvious cleanup and each one breaks something.

- **Do not fill the empty bark arrays.** 21 pools are empty, and **14 assertions across FIVE test files**
  pin `size() == 0` — `test_attack_reactions.gd:17,18,44`, `test_hostility.gd:580-582,623,634,635,636`,
  `test_body_discovery.gd:61`, `test_default_barks.gd:95,96`, `test_npc.gd:627` (the plan's "12+ across two
  files" under-counted the blast radius). Emptiness is a deliberate contract from the AI-text scrub.
  ⚠ **But it is not an absolute block on shipping barks**, which the original wording implied: `bark_set.gd`
  exposes the same categories as designer-authored `@export` arrays, and `npc.gd`'s `_pick_bark(fallback,
  override)` is the seam. **Authoring a `BarkSet` `.tres` adds barks and breaks nothing** — all 14
  assertions read the `NPC.*_LINES` const fallback. That is the supported route; editing the consts is not.
- **Do not bulk-strip `[PH]` markers.** ⚠ The rule is right; the stated reason is wrong. It is **not**
  "zero test signal": `test_player_text.gd:103-106` only checks that a *present* marker is well-formed, but
  separately **69 assertions across 19 test files embed the literal `"[PH] "` in an expected value**
  (re-counted 2026-09-11; e.g. `player_text.gd`'s `PROMPT_OPEN_DOOR` is pinned by `test_door.gd`'s `look_name()`
  assert). So a bulk strip fails the suite **loudly and unevenly** — the worst of both, not a silent convention break. Anyone removing a
  marker must grep `tests/` for the literal string first, and that is necessary but not sufficient: the
  marker also appears mid-expression (the `TextFormat.subst("[PH] {name} …")` calls in `player_text.gd`), not
  only in const declarations.
- **Do not gitignore `__perf_probe.gd` to silence `test_groups`.** The test walks the filesystem.
  Delete it or fix it.
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

**If you only do two things:** item 1.1 (you have never produced a build, and Phase 5 waits on measuring
one) and item 2.1 (delete the Call of Duty model — it is on your boot path and it takes ten minutes).
