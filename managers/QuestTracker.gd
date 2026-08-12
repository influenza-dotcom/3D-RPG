extends Node
## @system Quests
## @seam QuestTracker OWNS the live quest tracker (active/completed/failed + objective progress) and the four quest signals; GameState keeps one-line forwarders so authored content and old call sites keep working.
## @seam save_into/load_from write and restore the [quests_active]/[quests_completed]/[quests_failed] cfg sections; GameState._save_perks_and_quests / _load_perks_and_quests delegate their quest halves here.
## @seam notify_kill/pickup/talk/enter/use + notify_flag_set are the world's hooks INTO quests — one shared _advance_objectives_matching body behind all of them.
## @risk A quest transition that forgets _gs().autosave_world_state() leaves progress unpersisted until an unrelated money/xp event happens to coincide — the classic "Continue lost my progress" bug.
## @risk _grant_quest_rewards early-returns off-tree, so a bare test grants NOTHING (not even reputation); asserting rewards without a live player silently passes for the wrong reason.
## @risk Restoring a quest whose .tres moved drops it SILENTLY — the _load_warnings array is the only surface that tells the player, and it is consume-once.
## @test res://tests/test_quests.gd
## @test res://tests/test_quest_tracker.gd

## QuestTracker — the live quest tracker, split out of GameState (M1).
##
## WHY IT IS ITS OWN AUTOLOAD: quest state is world state, so it has to persist with the profile, but it is not
## *player build* state and it does not belong in the save god-object. GameState.gd was the largest coordination
## point in the project and every quest change dirtied it. The tracker now owns its own dicts, its own signals and
## its own two cfg sections; GameState keeps thin one-line forwarders (see its "Quests" region) so the ~70 authored
## call sites — dialogue choices, TriggerVolumes, QuestStarters, Readables — keep working unedited.
##
## WHAT LIVES WHERE:
##   • Here — the tracker dicts, the four signals, the whole quest API, reward granting, the cfg round-trip.
##   • GameState — story FLAGS (quests only *read* them, via notify_flag_set), the autosave pump
##     (autosave_world_state), and the live-player lookup (live_player) that reward granting needs.
## The dependency runs ONE way at call time (tracker -> GameState), so autoload order does not matter; nothing here
## touches GameState during _ready.
##
## PERSISTENCE: a quest round-trips by `resource_path`, so a code-built Quest with no path cannot be saved and is
## skipped with a warning naming it. A path that no longer loads (the .tres was moved/renamed/deleted) is skipped
## with a warning rather than crashing the boot load — degrade, never hard-fail — and appends a player-facing
## line to _load_warnings.

## Faction registry — resolves a quest's reward_reputation faction ids to live Faction resources for the grant.
## Preloaded, NOT a class_name reference: no global-class-cache dependency, so headless GUT compiles this autoload
## without a prior --import. Mirrors the same const GameState carries.
const Factions := preload("res://scripts/faction/factions.gd")

## A quest just started (a QuestStarter, a dialogue choice, a TriggerVolume, or a completed quest's next_quest chain).
signal quest_started(quest: Quest)
## An active quest's objective ticked toward its required_count. Emitted on EVERY advance, including the final one.
signal objective_advanced(quest: Quest, objective: QuestObjective)
## A quest finished — rewards are already granted when this fires, so a listener can read the new money/xp.
signal quest_completed(quest: Quest)
## WR-6: a quest was FAILED (explicit fail_quest, or its expire_on_flag fired). Wire a journal strike-through / toast.
signal quest_failed(quest: Quest)

## THE LIVE TRACKER. _quests_active: quest_id -> { quest: Quest, progress: { objective_id(String): int } }.
var _quests_active: Dictionary = {}
## Finished quest ids -> the Quest resource (stored whole, not just a flag, so the journal can show completed titles).
var _quests_completed: Dictionary = {}
## WR-6: failed/expired quest ids -> the Quest resource (mirrors _quests_completed). A failed quest can't be
## re-started or completed; a FAILED dialogue gate + the journal read this.
var _quests_failed: Dictionary = {}
## B-F40: user-facing warnings from the LAST profile load — one line per saved quest whose .tres failed to load
## (the resource was moved/renamed/deleted), which would otherwise drop the quest SILENTLY (progress lost). The HUD
## (ui.gd) consumes these on _ready via take_load_warnings() and toasts them. Repopulated each load; empty on a clean one.
var _load_warnings: Array[String] = []

## The GameState this tracker reads story flags from, pumps autosaves through, and finds the live player with.
## Null (the normal case) means "the GameState autoload" — production never sets this.
##
## ⭐ IT EXISTS FOR TEST ISOLATION. Quest state used to live on GameState, so `tests/test_quests.gd` could build a
## bare off-tree `GameState.new()` per test and get a private tracker for free. An autoload is a singleton, which
## would have made every quest test share one journal and leak into the next. Instead a test builds its OWN bare
## `QuestTracker.new()` and points it at its own bare GameState — same isolation, and it now exercises the real
## owner. Never read this field directly; go through `_gs()`.
var game_state: Node = null

## The GameState to talk to: the injected one in a test, the autoload in the game.
func _gs() -> Node:
	return game_state if game_state != null else GameState


# --- Lifecycle ------------------------------------------------------------------------------------------------

## Forget every tracked quest — a New Game. Called by GameState.reset_for_new_game so a fresh run never inherits
## the previous run's journal (or its stale load warnings, which would toast over the new game's first frame).
func reset() -> void:
	_quests_active.clear()
	_quests_completed.clear()
	_quests_failed.clear()  # WR-6
	_load_warnings.clear()  # C44: forget any prior boot-load's quest-restore warnings so a fresh game doesn't toast them


# --- Starting / advancing / closing ---------------------------------------------------------------------------

## Begin tracking `quest` — no-op if it's null/idless, already active, or already completed. Seeds each
## objective's progress to 0 and emits quest_started.
func start_quest(quest: Quest) -> void:
	if quest == null or quest.id == &"" or is_quest_active(quest.id) or is_quest_completed(quest.id) or is_quest_failed(quest.id):
		return  # WR-6: a failed quest is closed for good — it can't be re-started
	if quest.prereq_quest_id != &"" and not is_quest_completed(quest.prereq_quest_id):
		return  # a prerequisite quest hasn't been finished yet — this one can't start
	var progress := {}
	for obj in quest.objectives:
		if obj != null and obj.id != &"":
			progress[String(obj.id)] = 0
	_quests_active[quest.id] = {"quest": quest, "progress": progress}
	quest_started.emit(quest)
	# M15: back-fill FLAG objectives whose flag is ALREADY set — a CHAINED quest that keys on a flag an earlier quest
	# (or any trigger/dialogue) already flipped. set_flag won't fire again, so without this the objective stalls at 0.
	# Mirror the live set_flag hook (advance_objective, same call as _advance_flag_objectives) so it advances / auto-
	# completes identically to a flag set while active. get_flag defaults false, so a falsey/unset flag is NOT satisfied.
	for obj in quest.objectives:
		if obj != null and obj.id != &"" and obj.type == QuestObjective.Type.FLAG and _gs().get_flag(obj.target_id):
			advance_objective(quest.id, obj.id, 1)
	_gs().autosave_world_state()  # a started quest is world state — persist it

## Bump an active quest's objective toward its required_count (clamped). Auto-completes the quest once every
## non-optional objective is met (when the quest auto_completes). No-op for an unknown quest/objective.
func advance_objective(quest_id: StringName, objective_id: StringName, amount: int = 1) -> void:
	if not is_quest_active(quest_id):
		return
	var entry: Dictionary = _quests_active[quest_id]
	var quest: Quest = entry["quest"]
	var obj := _quest_objective(quest, objective_id)
	if obj == null:
		return
	var key := String(objective_id)
	var progress: Dictionary = entry["progress"]
	progress[key] = mini(int(progress.get(key, 0)) + amount, obj.required_count)
	objective_advanced.emit(quest, obj)
	if quest.auto_complete and _all_required_done(quest, progress):
		complete_quest(quest_id)  # this autosaves via complete_quest, so don't double-save below
	else:
		_gs().autosave_world_state()  # objective progress is world state — persist it

## Finish an active quest: move it to completed, grant its rewards, emit quest_completed. Works as an explicit
## turn-in or via auto-complete.
func complete_quest(quest_id: StringName) -> void:
	if not is_quest_active(quest_id):
		return
	var entry: Dictionary = _quests_active[quest_id]
	var quest: Quest = entry["quest"]
	_quests_active.erase(quest_id)
	_quests_completed[quest_id] = quest  # store the Quest (not just a flag) so the journal can show completed titles
	_grant_quest_rewards(quest)
	quest_completed.emit(quest)
	_gs().autosave_world_state()  # quest finished + rewards granted — a milestone; persist the run
	if quest.next_quest != null:
		start_quest(quest.next_quest)  # chain: finishing this quest auto-starts the next stage

## WR-6: FAIL an active quest — move it to failed, emit quest_failed. No rewards, no chaining (a failed quest is
## a dead end). No-op for a quest that isn't active (already completed/failed/never started). Drives the FAILED
## dialogue gate + a journal strike-through. Called explicitly (a dialogue consequence) or by an expire_on_flag.
func fail_quest(quest_id: StringName) -> void:
	if not is_quest_active(quest_id):
		return
	var entry: Dictionary = _quests_active[quest_id]
	var quest: Quest = entry["quest"]
	_quests_active.erase(quest_id)
	_quests_failed[quest_id] = quest  # store the Quest (like completed) so the journal can show failed titles
	quest_failed.emit(quest)
	_gs().autosave_world_state()  # a failed quest is a permanent world-state change — persist it


# --- Queries --------------------------------------------------------------------------------------------------

func is_quest_active(quest_id: StringName) -> bool:
	return _quests_active.has(quest_id)

func is_quest_completed(quest_id: StringName) -> bool:
	return _quests_completed.has(quest_id)

func is_quest_failed(quest_id: StringName) -> bool:
	return _quests_failed.has(quest_id)

func active_quest_ids() -> Array:
	return _quests_active.keys()

## The Quest resource for an ACTIVE quest id (null if it isn't active) — for the journal UI.
func active_quest(quest_id: StringName) -> Quest:
	var entry: Variant = _quests_active.get(quest_id)
	return entry["quest"] if entry != null else null

## The completed Quest resources (for the journal's "done" list).
func completed_quests() -> Array:
	var out: Array = []
	for q in _quests_completed.values():
		if q is Quest:
			out.append(q)
	return out

## WR-6: the failed Quest resources (for the journal's "failed" list).
func failed_quests() -> Array:
	var out: Array = []
	for q in _quests_failed.values():
		if q is Quest:
			out.append(q)
	return out

## An active objective's current count (0 when the quest/objective isn't active).
func objective_progress(quest_id: StringName, objective_id: StringName) -> int:
	if not is_quest_active(quest_id):
		return 0
	return int(_quests_active[quest_id]["progress"].get(String(objective_id), 0))

## Is an objective satisfied (count >= required)? A completed quest reports all its objectives done.
func is_objective_done(quest_id: StringName, objective_id: StringName) -> bool:
	if is_quest_completed(quest_id):
		return true
	if not is_quest_active(quest_id):
		return false
	var obj := _quest_objective(_quests_active[quest_id]["quest"], objective_id)
	return obj != null and int(_quests_active[quest_id]["progress"].get(String(objective_id), 0)) >= obj.required_count

func _quest_objective(quest: Quest, objective_id: StringName) -> QuestObjective:
	if quest == null:
		return null
	for obj in quest.objectives:
		if obj != null and obj.id == objective_id:
			return obj
	return null

func _all_required_done(quest: Quest, progress: Dictionary) -> bool:
	for obj in quest.objectives:
		if obj == null or obj.optional:
			continue
		if int(progress.get(String(obj.id), 0)) < obj.required_count:
			return false
	return true


# --- Rewards --------------------------------------------------------------------------------------------------

## Grant a completed quest's rewards: faction reputation (global), then the player's money / xp / items. Requires
## an in-tree GameState with a live player; off-tree (a bare test / no SceneTree) it early-returns and grants
## NOTHING (not even reputation — the group lookup behind live_player needs get_tree()). In real play this always runs in-tree.
func _grant_quest_rewards(quest: Quest) -> void:
	if not _gs().is_inside_tree() or _gs().get_tree() == null:
		return
	# Reputation rewards are GLOBAL standing (faction_id -> delta), applied via the Reputation autoload.
	for fid in quest.reward_reputation:
		var faction := Factions.by_id(str(fid))
		if faction != null:
			Reputation.add_reputation(faction, float(quest.reward_reputation[fid]))
	# The HUMAN player, not a companion (the &"Player" group also holds recruited companions, which ARE NPCs).
	# Annotated, not inferred: _gs() is typed only as Node, so live_player() reads back as Variant and `:=` can't
	# infer a type from it (the project-wide "no := off a duck-typed seam" rule).
	var player: Node = _gs().live_player()
	if player == null:
		return
	if quest.reward_money != 0.0 and player.has_method(&"add_money"):
		player.add_money(quest.reward_money)
	if quest.reward_xp != 0.0 and player.has_method(&"add_xp"):
		player.add_xp(quest.reward_xp)
	if not quest.rewards.is_empty():
		var inv: Variant = player.get(&"inventory")
		if inv is CharacterInventory:
			# The bag may be spatial-capped (opt-in Tetris grid) and silently drop overflow — surface the shortfall
			# rather than vanishing reward items. Compare the placed item count before/after seeding; if fewer items
			# landed than the rewards total, toast/log it so the player knows to make room (the items aren't refunded —
			# seed_into stops at the first full add, matching the rest of the loot pipeline).
			var bag := inv as CharacterInventory
			var before := _reward_item_total(bag)
			ItemStack.seed_into(bag, quest.rewards)
			var wanted := 0
			for r in quest.rewards:
				if r != null and r.item != null and r.count > 0:
					wanted += r.count
			var placed := _reward_item_total(bag) - before
			if placed < wanted:
				var msg := PlayerText.quest_rewards_full(wanted - placed)
				if player.has_method(&"notify_toast"):
					player.notify_toast(msg, Color(1.0, 0.6, 0.3))
				else:
					push_warning("QuestTracker: " + msg)

## Total item UNITS currently in `bag` (summed stack counts) — used to measure how many quest reward items
## actually fit after seed_into, so a spatial-capped bag's silent overflow can be surfaced to the player.
func _reward_item_total(bag: CharacterInventory) -> int:
	var total := 0
	for s in bag.placed_contents():
		total += int(s["count"])
	return total


# --- The world's hooks into quests ----------------------------------------------------------------------------

## Advance every active objective of `obj_type` whose target_id matches `target` — the shared body behind the
## FLAG (set_flag) / KILL / PICKUP / TALK objective hooks. Slice 3: KILL/TALK pass the STABLE identity key as
## `target` plus the live display string as `legacy_fallback`, so a quest authored either way matches — an
## identity-keyed objective survives display_name edits/localization, while a pre-identity .tres authored against
## a display name (clear_the_block's &"Raider") keeps working unedited. The != target guard means an objective
## matching BOTH forms (every id-less NPC: identity == name) still advances exactly ONCE per event.
func _advance_objectives_matching(obj_type: int, target: StringName, legacy_fallback: StringName = &"") -> void:
	for quest_id in _quests_active.keys():
		var entry: Variant = _quests_active.get(quest_id)
		if entry == null:
			continue
		var quest: Quest = entry["quest"]
		for obj in quest.objectives:
			if obj == null or obj.type != obj_type:
				continue
			if obj.target_id == target \
					or (legacy_fallback != &"" and legacy_fallback != target and obj.target_id == legacy_fallback):
				advance_objective(quest_id, obj.id, 1)

## A story FLAG was set to a truthy value. Two things can happen, in this order: a FLAG objective fires (the
## universal hook — any trigger/lock/dialogue flag drives a quest), and a quest whose expire_on_flag matches is
## FAILED. Called by GameState.set_flag; the tracker never reads flags on its own clock.
func notify_flag_set(flag: StringName) -> void:
	_advance_objectives_matching(QuestObjective.Type.FLAG, flag)
	_expire_quests_on_flag(flag)

## WR-6: fail every ACTIVE quest whose expire_on_flag matches `flag` (the "you missed the window" trigger — e.g.
## set the flag when the hostage dies / the timer ends). Collect ids first since fail_quest mutates _quests_active.
func _expire_quests_on_flag(flag: StringName) -> void:
	var to_fail: Array = []
	for qid in _quests_active:
		var q: Quest = _quests_active[qid].get("quest")
		if q != null and q.expire_on_flag == flag:
			to_fail.append(qid)
	for qid in to_fail:
		fail_quest(qid)

## A player KILL of an NPC (from npc._on_died) advances matching KILL objectives. `target_id` is the NPC's stable
## identity key (NPC.identity_key); `legacy_name` its live display string, kept as the authored-display fallback.
func notify_kill(target_id: StringName, legacy_name: StringName = &"") -> void:
	_advance_objectives_matching(QuestObjective.Type.KILL, target_id, legacy_name)

## The player PICKED UP an item with id `item_id` (from CanPickUp) — advance matching PICKUP objectives.
func notify_pickup(item_id: StringName) -> void:
	_advance_objectives_matching(QuestObjective.Type.PICKUP, item_id)

## The player started TALKING to a character (from DialogueManager.start) — advance TALK objectives. `npc_id` is
## the speaker's stable identity key (NPC.identity_key; an inanimate DialogueNPC passes its resolved name);
## `legacy_name` the resolved speaker-name string, kept as the authored-display fallback.
func notify_talk(npc_id: StringName, legacy_name: StringName = &"") -> void:
	_advance_objectives_matching(QuestObjective.Type.TALK, npc_id, legacy_name)

## The player ENTERED an area named `area_name` (from a TriggerVolume) — advance matching ENTER_AREA objectives.
func notify_enter(area_name: StringName) -> void:
	_advance_objectives_matching(QuestObjective.Type.ENTER_AREA, area_name)

## The player USED an item with id `item_id` (from Player.use_consumable) — advance matching USE_ITEM objectives.
func notify_use(item_id: StringName) -> void:
	_advance_objectives_matching(QuestObjective.Type.USE_ITEM, item_id)


# --- Persistence ----------------------------------------------------------------------------------------------

## Write the tracker to `cfg`, keyed by resource_path (a code-built quest with no path can't round-trip and is
## skipped with a warning). Active quests carry their objective progress; completed and failed carry just the path.
## Called by GameState._save_perks_and_quests — the quest half of the same cfg.
func save_into(cfg: ConfigFile) -> void:
	for qid in _quests_active:
		var entry: Dictionary = _quests_active[qid]
		var q: Quest = entry.get("quest")
		if q == null or q.resource_path == "":
			# The skip is by design (a code-built Quest can't round-trip) but it must not be SILENT — every
			# load-side degrade in this file pairs the drop with a push_warning; the save side gets the same.
			push_warning("QuestTracker: active quest '%s' has no resource_path — it will NOT survive this save" % qid)
			continue
		cfg.set_value("quests_active", String(qid), {"path": q.resource_path, "progress": entry.get("progress", {})})
	for qid in _quests_completed:
		var qc: Quest = _quests_completed[qid]
		if qc != null and qc.resource_path != "":
			cfg.set_value("quests_completed", String(qid), qc.resource_path)
	for qid in _quests_failed:  # WR-6: mirror the completed section — just the path (no progress on a closed quest)
		var qf: Quest = _quests_failed[qid]
		if qf != null and qf.resource_path != "":
			cfg.set_value("quests_failed", String(qid), qf.resource_path)

## Restore the tracker from `cfg` (resource-path keyed). A renamed/removed .tres path is skipped with a warning
## rather than crashing the boot load — degrade, never hard-fail. Repopulates _load_warnings for the HUD.
## Called by GameState._load_perks_and_quests.
func load_from(cfg: ConfigFile) -> void:
	_load_warnings.clear()  # B-F40: fresh warnings for THIS load (the HUD consumes them once)
	_quests_active.clear()
	if cfg.has_section("quests_active"):
		for qid in cfg.get_section_keys("quests_active"):
			var rec = cfg.get_value("quests_active", qid, null)
			if not (rec is Dictionary):
				continue
			var q := load(str(rec.get("path", ""))) as Quest
			if q == null:
				push_warning("QuestTracker: active quest '%s' path didn't load — skipped" % qid)
				_load_warnings.append(PlayerText.SAVE_WARN_ACTIVE_QUEST_MISSING)
				continue
			# Per-VALUE junk guard, not just the dict-shape check: a hand-edited save can hold any Variant under
			# a progress key, and int([3]) is a hard runtime ERROR, not a coercion (player.gd's bag loader
			# documents the same trap) — at advance_objective it would abort BEFORE the assignment, bricking the
			# objective for good. Same accept-list as GameState._cfg_int (int/float/bool convert freely; anything
			# else is junk): a junk value is DROPPED, so that objective degrades to 0 progress — never hard-fail.
			var prog = rec.get("progress", {})
			var progress := {}
			if prog is Dictionary:
				for k in prog:
					var v = prog[k]
					if v is int or v is float or v is bool:
						progress[str(k)] = int(v)
			_quests_active[StringName(qid)] = {"quest": q, "progress": progress}
	_quests_completed.clear()
	if cfg.has_section("quests_completed"):
		for qid in cfg.get_section_keys("quests_completed"):
			var q := load(str(cfg.get_value("quests_completed", qid, ""))) as Quest
			if q == null:
				push_warning("QuestTracker: completed quest '%s' path didn't load — skipped" % qid)
				_load_warnings.append(PlayerText.SAVE_WARN_COMPLETED_QUEST_MISSING)
				continue
			_quests_completed[StringName(qid)] = q
	_quests_failed.clear()  # WR-6: mirror the completed load
	if cfg.has_section("quests_failed"):
		for qid in cfg.get_section_keys("quests_failed"):
			var q := load(str(cfg.get_value("quests_failed", qid, ""))) as Quest
			if q == null:
				push_warning("QuestTracker: failed quest '%s' path didn't load — skipped" % qid)
				_load_warnings.append(PlayerText.SAVE_WARN_FAILED_QUEST_MISSING)
				continue
			_quests_failed[StringName(qid)] = q

## B-F40: hand the HUD the last load's quest-restore warnings and CLEAR them (consume-once, so a HUD rebuild on a
## level change doesn't re-toast old warnings). Returns [] after a clean load. ui.gd calls this in _ready.
func take_load_warnings() -> Array:
	var w := _load_warnings.duplicate()
	_load_warnings.clear()
	return w
