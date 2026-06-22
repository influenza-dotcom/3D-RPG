# Designer-gap work-orders — 2026-06-19 (for Claude Code)

Paste-ready specs derived from the [designer-gap refresh](2026-06-19-designer-gap-refresh.md). Each block is self-contained: hand one to Claude Code as a prompt. They're ordered so the cheapest, highest-leverage work lands first. All specs assume the house rules in `CLAUDE.md` — **drop-in components** (`class_name` + `@export`), **no hardcoded consts** for anything a designer tunes (use an `@export` or a `resources/tuning/*.tres` group on `GameSettings`), **content as authored `.tres`**, id fields validated via `_validate_property` + `PROPERTY_HINT_ENUM_SUGGESTION`, **tabs not spaces**, commit `.gd.uid` sidecars, don't auto-run GUT, don't push.

Suggested order: **WO-1 → WO-2 → WO-3** (a half-day that makes everything already built actually usable), then pick a design direction (WO-4 progression / WO-5 navigation / WO-8 cinematics).

---

## WO-1 · Fix the level-flow wiring bug *(CRITICAL · H value / S effort)*

**Goal.** Make a `LevelDoor` actually swap levels and move the player at runtime. It's wired but dead today.

**Current state.** In `scenes/game.tscn` the root is `Game` (Node3D, no script); `game_root.gd` is attached to a **child** node `GameRoot` (`parent="."`), and `Player` is its **sibling** (`parent="."`). But `game_root.gd` resolves the player with GameRoot-relative paths: `get_node_or_null(^"Player")` (`game_root.gd:53`), `^"Player/Music"` (:76), `^"Player/Ambience"` (:81). These point at `GameRoot/Player`, which doesn't exist → null → `_place_player_at_entry` early-returns (no teleport, no `set_respawn` re-seed at :60) and `_apply_audio` no-ops. `TestLevel.tscn` also has no `PlayerSpawn`.

**Fix (pick the cleaner of these — Claude Code's call).** Either (a) move `game_root.gd` onto the actual scene root so `^"Player"`/`^"Level"` resolve, or (b) keep GameRoot as a child but change the three lookups to `^"../Player"`, `^"../Player/Music"`, `^"../Player/Ambience"`. Then add a `PlayerSpawn` (Marker3D, group `player_spawn`, an `entry_id`) to `TestLevel.tscn` so there's a spawn to match.

**Done when.** Dropping a `LevelDoor` (target `LevelData` + `entry_id`) and walking through it swaps the level, teleports the Player to the matching `PlayerSpawn`, re-seeds respawn there, and a death afterward returns to the new level — all without GDScript.

**Watch-out.** The in-place swap keeps the Player alive but frees the old level; the deferred teleport **must** re-seed `GameState.set_respawn` or a post-swap death (`player.gd:1574 reload_current_scene()`) drops the player into the old scene. Add a unit test only if asked.

---

## WO-2 · Ship starter content to clone *(H value / S effort)*

**Goal.** Stop designers authoring whole categories from a blank inspector. Today `resources/` has **zero** `example_*.tres` for the authored types and no component prefabs.

**Build (create these IN the editor so uids/`.tres` are valid — don't hand-write them).**
- One annotated example each: `example_quest.tres` (multi-objective + reward + `next_quest` chain), `example_cutscene.tres` (WAIT → CAPTION → TOAST → CAMERA_MOVE → FADE), `example_status_effect.tres`, `example_perk.tres`, `example_mapdata.tres`, plus a `DialogueSelector` sample and one `example_dialogue_with_consequences.tres` (skill-check + `target_on_fail` + set-flag/give-item).
- Prefabs: `perk_station.tscn`, `cutscene_player.tscn`, `ambient_sound.tscn`, `player_light_level.tscn`.
- A `resources/levels/` folder with one real `LevelData.tres` (the only one today is an inline SubResource trapped in `game.tscn`).

**Done when.** A designer can right-click → duplicate a `.tres` (or drag a prefab) for every authored type and edit from a working example. Add a one-line "clone this" pointer per type to the guide.

---

## WO-3 · De-stale the authoring guide *(H value / M effort · docs only, no code)*

**Goal.** The guide is the designer's discovery surface; 12 of today's 15 systems are undocumented and a few lines are now actively wrong. (If you'd rather I — the non-Claude-Code assistant — just apply these edits to the markdown, say so; it isn't GDScript.)

**Delete / correct these now-false lines in `docs/AUTHORING_GUIDE.md`:**
- `:1528` & `:1932` — "quest progress is **not** save-persisted yet." False; `GameState.gd:238-261` persists it. Replace with the real caveat: state round-trips by `resource_path`, so a renamed/moved `.tres` is skipped.
- `:1446` & `:1527` — "`reward_reputation` … NOT granted yet … Don't rely on it." False; granted at `GameState.gd:433`.
- `:1490`, `:1526` — "`ENTER_AREA`/`USE_ITEM` have no auto-hook." Stale; `notify_area_entered`/`notify_use` fire them now.
- `:331` — CutsceneAction enum is missing the shipped `TOAST` and `CAPTION`.
- `:705` — the `DialogueChoice` field table omits the whole Consequences group, `target_on_fail`, and flag-gates.
- `:195` — reframe the level seam (it ships portals now, but is mis-wired — see WO-1).

**Add new sections / catalogue entries for:** LevelDoor + PlayerSpawn (+ a worked "two-level" example), BuildGate, QuestStarter, dialogue Consequences (the biggest no-code jump — give it a full subsection), DialogueSelector, designer toast, quest chaining/prereq + area/use hooks, `EncounterSpawner.cleared`/`wait_for_clear`, AmbientSound, AudioZone, Restocker, and the ItemIds dropdowns + ItemDb boot warnings.

**Done when.** Every system shipped today is discoverable from the guide, and no line tells a designer to avoid a working feature.

---

## WO-4 · A real progression loop *(H value / L effort)*

**Goal.** Growth today is buy-stats-with-cash or find-a-shrine only — there is **no XP system at all** (zero grep hits) and `LevelUp.available_perks` (`level_up.gd:29-31`) is exported but never read (a new silent-dead export). Give designers an earnable arc.

**Build, in dependency order.** (1) An `XpSettings` curve `.tres` on `GameSettings` + `Player.xp`/`add_xp` (persisted via the existing perk/quest save path) with kill- and quest-completion award hooks. (2) A pick-1-of-N perk picker in `level_up_screen.gd` that reads `LevelUp.available_perks`, filtered by `PerkManager.can_unlock`, routed through `host.grant_ability` (the path the rank-1 fix established — don't raw `add_child`). (3) A `RespecStation` drop-in + `PerkManager.respec()`.

**Done when.** A designer authors "kill grunts / finish a quest → level up → choose 1 of 3 perks," it persists across reload, and a RespecStation refunds for a fee — no GDScript.

**Watch-out.** Respec is the risky part: `PerkManager` has no removal path today; reversing stat deltas and freeing a hot-path ability (e.g. `_wall_climb`) is error-prone — scope to `stat_bonuses` + ability-id removal and unit-test the round-trip.

---

## WO-5 · Quest navigation (markers / compass) *(H value / M effort)*

**Goal.** The journal is pure text (`quest_journal.gd` renders only labels); `QuestObjective` has no world anchor and nothing emits a waypoint channel, so the only way to point a player at an objective is prose.

**Build.** A `WorldMarker` (groups `compass`/`minimap`) + a `Compass` Control with a pure `project_to_edge()`, an optional `marker_position`/`show_marker` on `QuestObjective`, and a `QuestMarkerSync` driven by the existing quest signals. Feed the existing minimap a marker channel.

**Done when.** Setting a marker on an objective shows a screen-edge chevron that clears on completion, inspector-only.

---

## WO-6 · Barter / bribe in dialogue *(H value / M effort)*

**Goal.** A choice can charge a "fee" but can't refuse a broke player or take an item — so bribes/barter aren't authorable. Root causes: `add_money` (`character.gd:39`) has **no floor** (wallet goes negative), there's no `required_money`/`required_item` gate, and `give_item` only adds (`dialogue_manager.gd:224` requires count > 0).

**Build.** Add `cost_money` / `required_item_id` (+ count) gate fields to `DialogueChoice`, evaluated alongside `passed`; an inventory-remove path for consuming the item; and clamp `add_money` at 0. Reuse the `target_on_fail` branch when the player can't afford it.

**Done when.** "Pay 500 to pass" and "hand over the keycard" both work as inspector-authored choices that fail gracefully when the player lacks the funds/item.

---

## WO-7 · Fire a cutscene from dialogue *(H value / S effort)*

**Goal.** `cutscene_player.gd:7` advertises being driven "from a TriggerVolume **or a dialogue**," but `DialogueChoice` has no cutscene field, so "talk → cinematic" needs code.

**Build.** Add a `Cutscene` export (+ optional `play_on_choice` target) to the `DialogueChoice` Consequences group, fired in `DialogueManager` alongside the other effects.

**Done when.** A dialogue choice can trigger an authored `Cutscene` with no script.

---

## WO-8 · Cinematic depth: actors + tracking camera *(H value / L effort)*

**Goal.** Cutscenes can't stage characters. The only actor verb is generic `CALL_METHOD`, nothing suppresses the GOAP brain (posed NPCs jitter), and the camera can't follow a moving subject.

**Build (extend the `CutsceneAction` enum + `_run_action` ONCE).** A `CutsceneActor` component + a brain-suppress gate at the top of `npc.gd._physics_process` + public `walk_to`/`face` facades + `WALK_TO`/`FACE`/`PLAY_ANIM` actions (PLAY_ANIM scoped to an optional AnimationPlayer NodePath — the rig itself is a separate art task). Plus camera `look_at_path`/`follow_node`/`camera_fov`/`snap`/`ease` on the Camera Move group.

**Done when.** A `Cutscene` walks an NPC to a marker, faces a target without jitter, and keeps a moving subject framed with a FOV zoom and an optional hard cut — fired from a TriggerVolume, no GDScript.

**Watch-out.** `_finish` must always clear the brain-suppress flag, or a skipped/interrupted cutscene leaves the NPC frozen.

---

## WO-9 · A designer-runnable content validator *(H value / M effort)*

**Goal.** No one-click "is my content valid?" before handoff. The `ItemIds` registry shipped, but there's no aggregate checker.

**Build.** A `@tool scripts/tools/validate_content.gd` (EditorScript) with a shared static `run()` aggregating existing checks: duplicate item ids, faction `id == filename`, weapon↔ammo caliber match, `GoapProfile.validate`, perk `stat_bonuses` keys, and (new) unresolved quest/flag ids. Emit a readable report.

**Done when.** A non-coder runs one EditorScript and gets a pass/fail list of content problems. (This later feeds the WO-12 editor dock.)

---

## Compact specs (lower tier — same format, briefer)

- **WO-10 · Id validation for quest/flag/entry fields** *(M/M+S)* — `complete_quest_id`/`advance_*`/`set_flag` on choices+triggers, `DialogueSelectorRow` gates, and `entry_id`/`quest_area_id` are free-text `StringName`; a typo silently no-ops. Add `quest_ids.gd`/`flag_ids.gd` folder-scan registries + `PROPERTY_HINT_ENUM_SUGGESTION` (mirror `item_ids.gd`).
- **WO-11 · `HudSettings` tuning group** *(M/S)* — `ui.gd` hardcodes ~30 consts (crosshair size, HP-bar geometry/colors, fonts, toast timing), breaking the no-const rule. Move them to a `HudSettings` `.tres` on `GameSettings`. **Grep `tests/` for `HP_SEG_`/`MONEY_`/`REP_TOAST_`/`HUD_FONT_SIZE` first** and migrate any test-pinned const alongside.
- **WO-12 · First-party EditorPlugin dock** *(M/L · build last)* — `addons/cyber_sunday/`: new-content buttons, a Validate button calling WO-9's `run()`, a guide-open button, optional component palette. Pure aggregation over WO-2 + WO-9.
- **WO-13 · Per-level world state persistence** *(H/L)* — only the player profile saves; on a full reload every looted crate refills and dead enemy returns. Add per-level container/enemy/door state to the save, keyed by level + node path.
- **WO-14 · Stealth slice** *(M/S–M)* — `LightStealthSettings.tres` + curve on `GameSettings`, a `Perception.light_falloff` global fallback (so the shipped `PlayerLightLevel` isn't inert), a `ShadowVolume` Area3D, per-NPC stealth-sense opt-in bools OR'd into the global gates, a public `investigate(point, alerted)` + `InvestigatePoint` marker.
- **WO-15 · Encounter authoring depth** *(M/M)* — `spawn_points`/`attach_scenes` on `EncounterSpawner` (precise markers + compose components onto spawns) + a `GuardDuty` drop-in.
- **WO-16 · AudioZone polish** *(M/S)* — add a non-Master-bus config-warning (mirror `AmbientSound`) and a `priority` export so overlapping zones don't both play.
- **WO-17 · WorldClock + schedules** *(M/L)* — `WorldClock` autoload + `Schedule`/`ScheduleEntry` resources + a `ScheduleBehavior` on the `NpcLocomotion` idle seam (day/night routines; also unlocks day-tick restock).
- **WO-18 · Loose ends** *(L)* — quest turn-in affordance in the journal for `auto_complete=false`; a `LETTERBOX` cutscene option; wire `LevelData.display_name` to a level-select or drop it; decide whether `GoapProfile.goals` should filter (currently inert by design).

---

*Source: `2026-06-19-designer-gap-refresh.md`, grounded against HEAD `854884c`. Line/symbol references were accurate at that commit — Claude Code should re-confirm before editing, since the tree moves fast.*
