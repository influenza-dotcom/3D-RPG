# Capability-gap implementation plan — 2026-06-19

A dependency-sequenced, phased plan to close the remaining gaps from the
[designer capability-gap audit](2026-06-19-designer-capability-gaps.md). Each gap was re-grounded against the
live code by a per-domain planner (12 agents) and sequenced by a synthesis pass. **Rank 1 (the perk-grant bug)
is already DONE** (commit `b080336`) and excluded. 34 specs across 12 domains, grouped into 9 phases.

Each phase ends with a concrete **milestone a designer can reach by inspector alone**. Phases are ordered so
shared infrastructure and dependencies land first; the L-effort "big rocks" are planned but late.

## Strategy

Sequencing follows three forces:

1. **Shared infrastructure first.** A tiny `ItemIds` registry + the config-warning/breadcrumb sweep (ranks 14/3) de-risk every later validation gap for almost nothing. And the rank-6/7/8/22 dialogue work all collide on **one seam** (`DialogueView.set_choices` binding the whole choice + `DialogueManager._on_choice_pressed(choice)`), so they must land as a single coordinated cluster, not piecemeal.
2. **Autoload-reachability shims deliver the most capability per line.** Thin inspector exports on `TriggerVolume` / `DialogueChoice` / `CutsceneAction` onto APIs that *already work* (`start_quest`, `complete_quest`, `set_flag`, `push_toast`, `load_level`) are foundational and go early.
3. **Atomic clusters + persistence ordering.** The level-flow cluster (4/5/26 + GameRoot wiring) must land together to unlock "ship more than one level by inspector." Persistence (rank 10) underpins anything that must survive a reload, so it precedes the progression big-rocks (29) and the perk-gate (15). The big rocks — cinematics (11/12), schedules (28), compass (30), HUD tuning (31), respec/XP (29) — are late because they're L-effort and depend on the seams the early phases establish. The **EditorPlugin dock (32) is dead last**: it's pure aggregation over the validator (14) and prefabs (24).

## Critical path (foundational, in order)

1. **P0 · rank 14** — `ItemIds` registry + id dropdowns (dep for the validator, the give-item field, several warnings).
2. **P0 · rank 3** — wiring config-warnings/breadcrumb (cheap safety net before new exports land).
3. **P1 · rank 6** — TriggerVolume quest exports + the `DialogueView`/`DialogueManager` `bind(choice)` refactor (the shared dialogue seam every other dialogue rank extends).
4. **P1 · rank 7** — dialogue consequences on that same `_on_choice_pressed(choice)` seam.
5. **P2 · ranks 4+5** — GameRoot wiring + LevelDoor + PlayerSpawn (atomic; unlocks multi-level by inspector).
6. **P3 · rank 10** — perk/quest/XP persistence (underpins all progression that must survive a reload).
7. **P8 · rank 14-validator → rank 32** — the validator feeds the EditorPlugin dock, which is dead last.

---

## P0 — Authoring guardrails: id registry, dropdowns, wiring warnings
**Goal:** land the shared validation infrastructure every later phase leans on, and stop silent-no-op typos at their three worst sites, before any new exports are added. **Effort: S** (2 items).
**Milestone:** selecting a `Lock`/`Door`/`QuestObjective` shows real item-id dropdowns instead of free text; a `TriggerVolume`/`CutscenePlayer` with a typo'd method/target shows a scene-tree warning before Play and a named `push_warning` at runtime; boot logs warn on blank/duplicate item ids and ammo with no caliber.

- **14 · ItemIds registry + id dropdowns + blank/dup boot warning** — new `scripts/items/item_ids.gd` (DirAccess scan of `resources/items/`) feeding `PROPERTY_HINT_ENUM_SUGGESTION` on `Lock.requires_item_id` (add `@tool`), `Door.requires_item_id`, `QuestObjective.target_id`; extend `ItemDb._ready` to flag empty id + ammo-without-caliber. *(deps: none — reused by ranks 3, 14-validator, 7)*
- **3 · Trigger/cutscene wiring config-warnings + breadcrumb** — `TriggerVolume._get_configuration_warnings` resolves `action`/`target`; `@tool` + warnings on `CutscenePlayer` walking `CALL_METHOD` steps; runtime `push_warning` when a node resolves but lacks the method. *(deps: none)*

## P1 — Quest & dialogue shims on the working APIs (the reachability cluster)
**Goal:** expose the working GameState quest/flag API + new dialogue logic through inspector exports, landing the shared `DialogueView`/`DialogueManager` bind refactor **exactly once**. **Effort: L** (6 items).
**Milestone:** a designer starts/finishes/advances/chains quests entirely from TriggerVolumes, DialogueChoices, and a QuestStarter drop-in; choices write consequences (flags/quests/money/items), fail-branch instead of dead-buttoning, and an NPC speaks different conversations by quest/flag state — all in the inspector, journal updating with no wiring.

- **6 · QuestStarter + TriggerVolume quest exports + DialogueChoice quest field** — new `QuestStarter` (Area3D → `GameState.start_quest`); `@export_group Quest` (start/complete/advance) on `TriggerVolume.fire()`; `start_quest_on_choice` on `DialogueChoice`; **the shared `cb.bind(choice)` + `_on_choice_pressed(choice)` rebind.** *(deps: P0/14; benefits from rank-24 example Quest)*
- **7 · Dialogue choices write consequences** — `@export_group Consequences` on `DialogueChoice` (set_flag, start_quest, advance, give_item, give_money) applied in `_apply_choice_effects(choice)` before `_jump_to`. *(deps: shares the bind refactor with 6 — land together; soft dep on 14)*
- **22 · Fail branch for gated choices** — `target_on_fail` (default END) on `DialogueChoice`; `set_choices` keeps a failed-gate button enabled and binds it to the fail target. *(deps: same `set_choices`/bind seam — sequence after 6/7)*
- **8 · An NPC can say more than one conversation** — new `DialogueSelector`/`DialogueSelectorRow` (flag/quest-gated rows → default); optional `dialogue_selector` export on `Talkable`/`DialogueNPC`. *(deps: synergises with 6/7; no hard dep)*
- **23 · Designer-fireable toast** — static `UI.toast(text,color)`; `toast_text`/`toast_color` on `TriggerVolume.fire()` + a `TOAST` `CutsceneAction` type. *(deps: none — `push_toast` exists; shares the enum pattern with 13)*
- **21 · Quest area/use hooks + turn-in + prereq/chaining** — `GameState.notify_enter`/`notify_use` (mirror `notify_kill`); ENTER_AREA from a `TriggerVolume.quest_area_id`, USE_ITEM from `Player.use_consumable`; `prereq_quest_id` guard + `next_quest` chain in start/complete. *(deps: builds on rank-6's quest group — land after 6)*

## P2 — Multi-level flow (the GameRoot/LevelData cluster)
**Goal:** wire the already-coded `GameRoot.load_level` seam so a designer can ship more than one level by inspector. **Effort: M-L** (3 items — **must land atomically**).
**Milestone:** attach `GameRoot` to `game.tscn`'s root, drop a `LevelDoor` with a target `LevelData` + `entry_id`, walk through it → levels swap with the Player surviving (HP/inventory/abilities) and arriving at the matching `PlayerSpawn`; dying returns there. A blank `LevelTemplate.tscn` with the load-bearing groups pre-wired is the clone source.

- **4 · LevelDoor / portal** — attach `game_root.gd` to `game.tscn` (group `game_root`); `LevelDoor` (LookAtInteractable) with `target_level`/`entry_id` → `GameRoot.load_level`; no-arg `load_assigned_level()` + `teleport_player_to_entry`. *(deps: coupled with 5)*
- **5 · PlayerSpawn / entry marker** — `PlayerSpawn` (Marker3D, group `player_spawn`, `entry_id`); `GameRoot.find_spawn` (deferred) teleports the Player and **re-seeds `GameState.set_respawn`** (closes rank-4's stale-respawn risk). *(deps: same change as 4)*
- **26 · Blank LevelTemplate.tscn** — `scenes/LevelTemplate.tscn` (Level root + navmesh/world_environment groups, light, buckets, a PlayerSpawn) + optional `@tool` group validator; guide note to duplicate it. *(deps: 5; benefits from 4)*

## P3 — Persistence + build-expression gates
**Goal:** make perks/quests/XP survive a reload, and let designers gate doors/locks/triggers by stat/perk/ability. **Effort: L** (2 items).
**Milestone:** learn a perk + advance a quest, quit, relaunch → Continue restores the perk bonuses + granted ability + objective progress with no double-counting; a `BuildGate` under a Door refuses a weak character (toast) but opens for a strong/perked one, and the same gate works on TriggerVolumes.

- **10 · Persist perks + quest progress** — store the `Perk` in `PerkManager._unlocked` + `unlocked_paths()`/`restore_paths()`; serialize `[perks]`/`[quests_active]`/`[quests_completed]` (resource-path keyed) through GameState capture/save/load with type-guards; restore in `Player._ready` after `_discover_abilities`; renamed paths degrade to a skipped `push_warning`. *(deps: rank 1 — done)*
- **15 · BuildGate component** — `BuildGate` Node (`of(host)`, `passes(opener)`, `deny_reason`) with stat/perk/ability dropdowns; consulted first in `Door._try_unlock`, `Lock.try_unlock`, `TriggerVolume._gate`; duck-typed, fail-closed. *(deps: a perk-gated door only persists once 10 lands)*

## P4 — Encounter clearing + audio zones + restock + inert-export cleanup
**Goal:** round out the mid-weight standalone gaps that need no big new subsystem. **Effort: M-L** (5 items).
**Milestone:** a wait-for-clear multi-wave arena whose exit unlocks on `cleared`; always-on `AmbientSound` beds + a cross-fading `AudioZone` that obeys the audio sliders (not Master); a `Restocker` that tops a vendor back to baseline (never doubling) on a timer/visit; a Quest's `reward_reputation` actually drops faction standing, and typo'd perk/quest keys show warnings.

- **9 · Encounter-cleared signal** — `EncounterSpawner` tracks `_alive` (connect each spawn's `died`+`tree_exited`), emits `cleared`/`alive_count_changed`; `WaveManager.wait_for_clear` awaits `cleared`. *(deps: standalone; pairs with rank-4 as a consumer)*
- **16 · AmbientSound drop-in** — `@tool AmbientSound` (Node3D) auto-creating a child `AudioStreamPlayer3D` on a real bus (default `ambient`), looping, with a `stream==null` warning — fixes the Master-bus footgun. *(deps: none)*
- **17 · AudioZone Area3D** — `@tool AudioZone` (ref-counted player-body) cross-fading a child player while inside, `PROCESS_MODE_ALWAYS`. *(deps: shares the body-detect idiom with 16)*
- **20 · Vendor restock / container refill** — `Restocker` Node (TIMER/ON_VISIT, interval from `EconomySettings`) driving `Merchant.refill()`/`ItemContainer.refill()` that tops up only the shortfall vs the authored baseline. *(deps: none; day-tick deferred to rank 28)*
- **25 · Wire/warn the four inert progression exports** — Perk `stat_bonuses` key warning; **wire `Quest.reward_reputation`** → `Reputation.add_reputation`; honour-or-remove `Cutscene.auto_end`; warn on inert `GoapProfile.goals`. *(deps: shipped APIs)*

## P5 — Cinematics: actor verbs, cinematic camera, captions
**Goal:** give cutscenes real staging power, extending the `CutsceneAction` enum + `_run_action` **once**. **Effort: L** (3 items).
**Milestone:** a `Cutscene` `.tres` that walks an NPC to a marker and faces a target without its AI jittering, keeps a moving subject framed with a smooth FOV zoom (and a snap-cut on another step), and shows a clean "Three days later…" caption — all fired from a TriggerVolume, no GDScript.

- **13 · CAPTION action** — `Type.CAPTION` + `caption_text`; `_ensure_caption()` (outlined Label above the fade rect) + a `_run_action` arm. *(deps: shares the enum/`_run_action` seam with 11/12/23 — extend once)*
- **12 · Cinematic camera look-at/follow + FOV + snap + easing** — `look_at_path`/`follow_node`/`camera_fov`/`snap`/`ease`/`trans` on the Camera Move group; one `tween_method(0→1)` computing pos+follow+look_at per step. *(deps: pairs with 11; shares the seam)*
- **11 · CutsceneActor: move/face/pose with the brain suppressed** — `WALK_TO`/`FACE`/`PLAY_ANIM` + an Actor group; a **brain-suppress gate** at the top of `npc.gd._physics_process` + public `walk_to`/`face` facades; `CutsceneActor` Node; `PLAY_ANIM` scoped to an optional `AnimationPlayer` NodePath. *(deps: shares the seam; **PLAY_ANIM's rig is an out-of-scope art task**; `_finish` must always clear the suppress flag)*

## P6 — NPC authoring depth: per-NPC stealth, guard duty, light-stealth
**Goal:** opt single NPCs into stealth senses, assign bodyguard duty + precise spawns, and turn on the authored-but-dead light/shadow stealth. **Effort: L** (6 items).
**Milestone:** tick stealth-sense on ONE guard while others stay oblivious and send it to investigate a marker via a trigger; assign `GuardDuty` + spawn-point markers so a wave arrives guarding a VIP; paint a `ShadowVolume` so the player fills detection meters slower in the dark, tuned by one `LightStealthSettings` curve.

- **27.4 · LightStealthSettings.tres + starter curve** — `light_falloff` Curve + `.tres`, registered as `GameSettings.light_stealth`; the shared default for the rest. *(deps: none — foundational for the stealth slice)*
- **27.2 · Per-NPC `light_falloff` via global-curve fallback** — `Perception` falls back to `GameSettings.light_stealth.light_falloff` when the export is null, flipping the feature on game-wide with one curve. *(deps: 27.4)*
- **27.1 · ShadowVolume Area3D** — `@tool ShadowVolume` ref-counting Player overlap, duck-writing `player.light_exposure` while inside. *(deps: observable only with 27.2+27.4)*
- **27.3 · Attach the light-level writer + ship `player_light_level.tscn`** — make `ShadowVolume` the default writer (no Player.tscn edit); add a live-sampling child only if scene lights are grouped. *(deps: 27.1/27.2/27.4)*
- **18 · Per-NPC stealth-sense opt-in + public `investigate()`** — `body_discovery_opt_in`/`hearing_initiates_opt_in` exports OR'd into the global gates; public `investigate(point, alerted)` + an `InvestigatePoint` marker. *(deps: none)*
- **19 · GuardDuty + spawner markers/attach-scenes** — `GuardDuty` Node (`get_parent().guard()`); `spawn_points`/`attach_scenes` on `EncounterSpawner._spawn_one`. *(deps: pairs with 18's marker + PatrolBehavior payloads)*

## P7 — Big-rock progression, schedules, navigation UI
**Goal:** the L-effort subsystems that depend on the now-stable persistence/idle/HUD seams. **Effort: XL** (3 items).
**Milestone:** a LevelUp station shows a prereq-aware "choose 1 of N" perk picker on level-up; a `RespecStation` refunds for a fee; an NPC follows a `Schedule` (market by day, home by night) interrupted by combat; a `WorldMarker`/objective shows a screen-edge compass chevron that clears on completion.

- **29 · Level-up perk picker + XP curve + RespecStation** — perk-pick section in `LevelUpScreen` → `PerkManager.unlock_perk` (filtered by `can_unlock`); `XpSettings` curve + `Player.xp`/`add_xp` (persisted) with kill/quest award hooks; `RespecStation` + `PerkManager.respec()` reversing deltas + freeing abilities. *(deps: rank 10 + rank 1; **respec is the hard part**)*
- **28 · WorldClock + Schedule + ScheduleBehavior** — `WorldClock` autoload (`time_of_day`, `phase_changed`) + `Schedule`/`ScheduleEntry` resources + a `ScheduleBehavior` hooked into `NpcLocomotion._idle` below companion-follow, above patrol/wander. *(deps: reuses the PatrolBehavior idle seam; new class_names need an editor rescan before GUT)*
- **30 · Quest markers/compass + minimap channel** — `WorldMarker` (groups `compass`/`minimap`), a `Compass` Control with a pure `project_to_edge()`, `QuestObjective.marker_position`/`show_marker` + a `QuestMarkerSync` driven by quest signals. *(deps: compass none; quest channel pairs with rank 6)*

## P8 — Tooling polish: starter content, HUD tuning, validator, plugin dock
**Goal:** package the authoring experience. **Effort: XL** (4 items). The EditorPlugin is **last** — it only aggregates what the earlier phases built.
**Milestone:** drag in `PerkStation`/`CutscenePlayer` prefabs and clone an annotated `example_*.tres` for every authored type; tune the HUD live from `HudSettings.tres`; one-click a content-validation report; and from a "Cyber Sunday" editor dock create resources, validate, open the guide, and instance components — never touching GDScript.

- **24 · Prefabs + one annotated starter `.tres` per never-shipped type** — `perk_station.tscn` + `cutscene_player.tscn` + `example_*.tres` for Quest/Cutscene/StatusEffect/Perk/MapData — **created in the editor so uids are valid**. *(deps: example_quest reads best after rank-14's dropdown)*
- **31 · HudSettings tuning group** — `HudSettings` resource + `.tres` on `GameSettings`, replacing the ~30 hardcoded `ui.gd` consts; **grep `tests/` for `HP_SEG_`/`MONEY_`/`REP_TOAST_`/`HUD_FONT_SIZE` first** and migrate any test-pinned const alongside. *(deps: none — EffectsSettings precedent)*
- **14 · Designer-runnable content validator** — `@tool scripts/tools/validate_content.gd` (EditorScript) aggregating existing checks (dup ids, faction id==filename, weapon↔ammo, GoapProfile.validate, perk keys) via a shared static `run()`. *(deps: reuses rank-14 registry + Calibers/Factions)*
- **32 · First-party EditorPlugin dock** — `addons/cyber_sunday/` (plugin.cfg + EditorPlugin + dock): new-content buttons, a Validate button calling the static `run()`, a guide-open button, optional component palette. *(deps: rank 14 validator + rank 24 prefabs; ship buttons before the palette stretch)*

---

## Risks

- **The dialogue bind refactor** (`set_choices` / `_on_choice_pressed(choice)`) is touched by ranks 6, 7, 22 — landing them out of order or separately risks a merge conflict and breaks the companion/extra-choice paths and `test_dialogue.gd`. Coordinate all three into P1 with **one** rebind.
- **The level-flow cluster (4/5/26) is only correct if landed atomically** — an in-place `load_level` keeps the Player but leaves `GameState.respawn_position` pointing into the freed old level; rank-5's deferred teleport must re-seed `set_respawn` or a post-swap death drops the Player into stale space.
- **Persistence (10) keys by `resource_path`** — a renamed/moved `.tres` 404s on load; must degrade to a skipped `push_warning`, never a boot crash; perk restore must reuse `unlock_perk`'s private-sheet duplicate so bonuses aren't double-applied.
- **New `class_name`s / autoloads** (Schedule/WorldClock in P7, the P8 plugin) can cascade GUT failures if the editor hasn't rescanned `global_script_class_cache` — rescan before running the suite, never `--import` with the editor open.
- **HUD const migration (31) is test-pinned** — grep `tests/` for the consts before migrating (the EffectsSettings lesson).
- **Hand-authored `.tres`/`.gd.uid` for starter content (24)** are malformed if hand-written — create them in the editor.
- **RespecStation's refund (29) is the riskiest single item** — `PerkManager` has no removal path today; reversing stat deltas and freeing a hot-path-referenced Ability (e.g. `_wall_climb`/`_slide`) is error-prone — scope to `stat_bonuses` + ability-id removal and unit-test the delta round-trip.
- **Light-stealth (P6 27.x) is inert** until 27.4's curve + 27.2's fallback + a writer all land — sequence 27.4 first or designers see a feature that silently does nothing; prefer `ShadowVolume` as the default writer (a live-sampling `PlayerLightLevel` on an empty `&lights` group pins exposure to a misleading flat value).

## Explicitly deferred

- **`PLAY_ANIM` built-in animations** (part of 11) — actors have no AnimationPlayer/rig (procedural `BodyModelSwap`); ship only the optional-NodePath shim, flag the rig as a separate art task.
- **Per-archetype `NpcData` light-falloff mirroring** (27.2 stretch) — the global-curve fallback flips it on for free; defer the per-NPC variety polish.
- **The "day-tick" restock trigger** (20) — no `WorldClock` until rank 28; ship TIMER + ON_VISIT now, add day-tick after P7.
- **`HudLayout.tscn`** (31 tail) — once numbers live in `HudSettings` the elements are still code-built; a layout scene buys little. Ship the `HudSettings` half only.
- **Runtime HUD tuning via Options** (31) — HUD numbers are author-time; a `GameSettings` resource is the right home, not a Settings/SettingsCatalog row.
- **`Cutscene.auto_end` honour branch** (25) — recommend removing it (+ its test assertion); "always restores" is the real behaviour, unless P5 specifically wants a hold-frame.
- **The EditorPlugin component palette** (32) — fiddliest, lowest-value; ship launcher/validate/guide buttons first, double-click-to-instance is a stretch.
- **`GoapProfile.goals` wiring** (25) — intentionally inert (dropping a combat goal idles a fighting NPC); ship only a config-warning, don't implement subset filtering.
