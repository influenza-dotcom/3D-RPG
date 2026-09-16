extends Node
## @system Quests
## @seam QuestTracker OWNS the live quest tracker (active/completed/failed + current stage + objective progress) and the quest signals; GameState keeps one-line forwarders so authored content and old call sites keep working.
## @seam save_into/load_from write and restore the [quests_active]/[quests_completed]/[quests_failed] cfg sections; GameState._save_perks_and_quests / _load_perks_and_quests delegate their quest halves here.
## @seam notify_kill/pickup/talk/enter/use + notify_flag_set are the world's hooks INTO quests — one shared _advance_objectives_matching body behind all of them.
## @seam A STAGED quest (Quest.stages non-empty) is always in one QuestStage: every objective read goes through Quest.objectives_for_stage(entry.stage), a stage hands off via next_stage_id / set_quest_stage, and the save writes the current stage id beside its progress (SAVE_VERSION 6, lazy: no stage field = stages[0]).
## @risk Iterating a stage's objectives while advancing them can hand the quest to its NEXT stage mid-loop; every such loop re-checks the entry's `epoch` so it never advances a same-id objective of the stage it just left.
## @risk A quest transition that forgets _gs().autosave_world_state() leaves progress unpersisted until an unrelated money/xp event happens to coincide — the classic "Continue lost my progress" bug.
## @risk _grant_quest_rewards early-returns off-tree, so a bare test grants NOTHING (not even reputation); asserting rewards without a live player silently passes for the wrong reason.
## @risk Restoring a quest whose .tres moved drops it SILENTLY — the _load_warnings array is the only surface that tells the player, and it is consume-once.
## @test res://tests/test_quests.gd
## @test res://tests/test_quest_tracker.gd
## @test res://tests/test_quest_stages.gd

## QuestTracker — the live quest tracker, split out of GameState (M1).
##
## WHY IT IS ITS OWN AUTOLOAD: quest state is world state, so it has to persist with the profile, but it is not
## *player build* state and it does not belong in the save god-object. GameState.gd was the largest coordination
## point in the project and every quest change dirtied it. The tracker now owns its own dicts, its own signals and
## its own two cfg sections; GameState keeps thin one-line forwarders (see its "Quests" region) so the ~70 authored
## call sites — dialogue choices, TriggerVolumes, QuestStarters, Readables — keep working unedited.
##
## WHAT LIVES WHERE:
##   • Here — the tracker dicts (including each active quest's current stage), the quest signals, the whole quest API, reward granting, the cfg round-trip.
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
## An ACTIVE staged quest moved to a DIFFERENT stage (its next_stage_id on completing a stage, or a set_quest_stage
## jump). NOT emitted for the first stage start_quest puts a quest in -- quest_started covers that. The journal, the HUD
## tracker line and the objective markers repaint on it (the live objective list just changed wholesale).
signal quest_stage_changed(quest: Quest, stage: QuestStage)

## How deep stage entries may nest inside ONE call before the tracker refuses to enter another. A stage whose FLAG
## objectives are already satisfied completes the moment it is entered (the back-fill), so a next_stage_id LOOP of such
## stages would recurse forever; real content never chains anywhere near this many beats in a single instant.
const MAX_STAGE_ENTRY_DEPTH := 32

## THE LIVE TRACKER. _quests_active: quest_id -> { quest: Quest, stage: StringName, epoch: int,
## progress: { objective_id(String): int } }. `stage` is the current QuestStage id (&"" for a stage-less quest), and
## `progress` holds ONLY that stage's objectives (entering a stage re-seeds it). `epoch` counts stage entries, so a loop
## over one stage's objectives can tell that an advance handed the quest to another stage -- even back to the SAME id.
var _quests_active: Dictionary = {}
## Current nesting of _enter_stage (see MAX_STAGE_ENTRY_DEPTH).
var _stage_entry_depth := 0
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

## Begin tracking `quest` — no-op if it's null/idless, already active, or already completed. Puts a staged quest in
## stages[0] (a stage-less quest's stage is &""), seeds that stage's objectives to 0, emits quest_started, then runs
## the stage-entry effects (set_flag_on_enter + the FLAG back-fill -- see _run_stage_entry).
func start_quest(quest: Quest) -> void:
	if quest == null or quest.id == &"" or is_quest_active(quest.id) or is_quest_completed(quest.id) or is_quest_failed(quest.id):
		return  # WR-6: a failed quest is closed for good — it can't be re-started
	if quest.prereq_quest_id != &"" and not is_quest_completed(quest.prereq_quest_id):
		return  # a prerequisite quest hasn't been finished yet — this one can't start
	var stage := quest.first_stage_id()
	_quests_active[quest.id] = {"quest": quest, "stage": stage, "epoch": 0, "progress": _seed_progress(quest, stage)}
	quest_started.emit(quest)
	_run_stage_entry(quest.id)
	_gs().autosave_world_state()  # a started quest is world state — persist it

## Bump an active quest's objective toward its required_count (clamped). The objective is looked up in the quest's
## CURRENT stage only (a stage-less quest: its own objectives), so an id belonging to another stage is a no-op. Once
## every non-optional objective of that stage is met: a stage with a next_stage_id hands the quest on to it (whatever
## auto_complete says -- that flag governs only the END); a terminal stage, or a stage-less quest, completes when the
## quest auto_completes. No-op for an unknown quest/objective.
func advance_objective(quest_id: StringName, objective_id: StringName, amount: int = 1) -> void:
	if not is_quest_active(quest_id):
		return
	var entry: Dictionary = _quests_active[quest_id]
	var quest: Quest = entry["quest"]
	var stage: StringName = entry.get("stage", &"")
	var obj := _quest_objective(quest, objective_id, stage)
	if obj == null:
		return
	var key := String(objective_id)
	var progress: Dictionary = entry["progress"]
	progress[key] = mini(int(progress.get(key, 0)) + amount, obj.required_count)
	objective_advanced.emit(quest, obj)
	if not _at_epoch(quest_id, int(entry.get("epoch", 0))):
		return  # a listener moved or closed the quest inside the emit -- this advance's stage is no longer current
	if _all_required_done(quest.objectives_for_stage(stage), progress):
		var st := quest.stage_by_id(stage)
		if st != null and st.next_stage_id != &"":
			if _enter_stage(quest_id, st.next_stage_id):
				return  # _enter_stage autosaved
			_gs().autosave_world_state()  # a dangling next_stage_id: the quest stays put (warned), but the tick persists
			return
		if quest.auto_complete:
			complete_quest(quest_id)  # this autosaves via complete_quest, so don't double-save below
			return
	_gs().autosave_world_state()  # objective progress is world state — persist it


## Move an ACTIVE staged quest to the stage `stage_id` -- a JUMP from wherever it is (the DialogueChoice
## set_quest_stage_id consequence; two routes converge by jumping into the same stage). Returns true when the quest is
## now in that stage. Re-entering the stage it is ALREADY in is a no-op that answers true (it does not reset that
## stage's progress). Refused (false, with a warning naming the ids) for a quest that is not active, a stage-less quest,
## or an id that names no stage of it -- the Audit reports that last one as an ERROR.
func set_quest_stage(quest_id: StringName, stage_id: StringName) -> bool:
	if not is_quest_active(quest_id):
		return false
	var entry: Dictionary = _quests_active[quest_id]
	var quest: Quest = entry["quest"]
	if not quest.has_stages():
		push_warning("QuestTracker: set_quest_stage('%s', '%s') -- that quest has no stages" % [quest_id, stage_id])
		return false
	if entry.get("stage", &"") == stage_id:
		return true
	return _enter_stage(quest_id, stage_id)


## Put an active quest into `stage_id`: re-seed progress for that stage's objectives, bump the entry's epoch, emit
## quest_stage_changed, run the stage-entry effects, autosave. False (warned) for an unknown stage or a nesting past
## MAX_STAGE_ENTRY_DEPTH (a next_stage_id loop whose stages all complete on entry).
func _enter_stage(quest_id: StringName, stage_id: StringName) -> bool:
	var entry: Dictionary = _quests_active[quest_id]
	var quest: Quest = entry["quest"]
	var st := quest.stage_by_id(stage_id)
	if st == null:
		push_warning("QuestTracker: quest '%s' has no stage '%s' -- it stays in '%s'" % [quest_id, stage_id, entry.get("stage", &"")])
		return false
	if _stage_entry_depth >= MAX_STAGE_ENTRY_DEPTH:
		push_warning("QuestTracker: quest '%s' entered %d stages in one instant -- a next_stage_id loop of stages that complete on entry; stopped before '%s'" % [quest_id, MAX_STAGE_ENTRY_DEPTH, stage_id])
		return false
	_stage_entry_depth += 1
	entry["stage"] = stage_id
	entry["epoch"] = int(entry.get("epoch", 0)) + 1
	entry["progress"] = _seed_progress(quest, stage_id)
	quest_stage_changed.emit(quest, st)
	_run_stage_entry(quest_id)
	_stage_entry_depth -= 1
	_gs().autosave_world_state()  # a stage change is world state — persist it
	return true


## What happens the moment a quest is IN a stage (its first, on start; any later one, on entry):
##   1. M15 back-fill: every FLAG objective of the stage whose flag is ALREADY set advances once -- a chained quest or
##      a later beat keying on a flag something flipped earlier. set_flag won't fire again, so without this the
##      objective stalls at 0. Mirrors the live set_flag hook (advance_objective), so it can complete the stage /
##      the quest identically; get_flag defaults false, so an unset/falsey flag is NOT satisfied.
##   2. set_flag_on_enter, but only when that flag is not ALREADY truthy. Order matters: the back-fill has already
##      counted an already-set flag once, and GameState.set_flag notifies on EVERY truthy write, so setting it again
##      would tick a matching objective a second time.
## Both steps stop the moment the quest leaves the stage (an advance completed it, or a flag listener moved / closed
## it): the epoch check keeps a stale loop from ticking a same-id objective of the stage it handed off to.
func _run_stage_entry(quest_id: StringName) -> void:
	if not is_quest_active(quest_id):
		return
	var entry: Dictionary = _quests_active[quest_id]
	var quest: Quest = entry["quest"]
	var stage: StringName = entry.get("stage", &"")
	var epoch := int(entry.get("epoch", 0))
	for obj in quest.objectives_for_stage(stage):
		if not _at_epoch(quest_id, epoch):
			return
		if obj != null and obj.id != &"" and obj.type == QuestObjective.Type.FLAG and _gs().get_flag(obj.target_id):
			advance_objective(quest_id, obj.id, 1)
	if not _at_epoch(quest_id, epoch):
		return
	var st := quest.stage_by_id(stage)
	if st != null and st.set_flag_on_enter != &"" and not _gs().get_flag(st.set_flag_on_enter):
		_gs().set_flag(st.set_flag_on_enter, true)


## True while `quest_id` is still active AND still in the stage entry numbered `epoch`.
func _at_epoch(quest_id: StringName, epoch: int) -> bool:
	var entry: Variant = _quests_active.get(quest_id)
	return entry != null and int(entry.get("epoch", 0)) == epoch


## {objective id: 0} for every id'd objective of the quest while in `stage_id`.
func _seed_progress(quest: Quest, stage_id: StringName) -> Dictionary:
	var progress := {}
	for obj in quest.objectives_for_stage(stage_id):
		if obj != null and obj.id != &"":
			progress[String(obj.id)] = 0
	return progress

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

## The id of the stage an ACTIVE quest is in -- &"" for a stage-less quest or a quest that isn't active.
func current_stage_id(quest_id: StringName) -> StringName:
	var entry: Variant = _quests_active.get(quest_id)
	return entry.get("stage", &"") if entry != null else &""

## The QuestStage an ACTIVE quest is in (null for a stage-less quest or one that isn't active) -- the journal reads its
## journal_text.
func current_stage(quest_id: StringName) -> QuestStage:
	var entry: Variant = _quests_active.get(quest_id)
	if entry == null:
		return null
	var quest: Quest = entry["quest"]
	return quest.stage_by_id(entry.get("stage", &"")) if quest != null else null

## The objectives an ACTIVE quest is working on right now: the current stage's (a stage-less quest: its own). Empty
## for a quest that isn't active. Every reader of "what does the player have to do" goes through here -- the journal,
## the HUD tracker line, the objective markers, the debug console.
func current_objectives(quest_id: StringName) -> Array[QuestObjective]:
	var entry: Variant = _quests_active.get(quest_id)
	if entry == null or entry["quest"] == null:
		var none: Array[QuestObjective] = []
		return none
	return (entry["quest"] as Quest).objectives_for_stage(entry.get("stage", &""))

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
	var entry: Dictionary = _quests_active[quest_id]
	var obj := _quest_objective(entry["quest"], objective_id, entry.get("stage", &""))
	return obj != null and int(entry["progress"].get(String(objective_id), 0)) >= obj.required_count

## The objective `objective_id` of `quest` while in `stage_id` (the current stage's list only), or null.
func _quest_objective(quest: Quest, objective_id: StringName, stage_id: StringName = &"") -> QuestObjective:
	if quest == null:
		return null
	for obj in quest.objectives_for_stage(stage_id):
		if obj != null and obj.id == objective_id:
			return obj
	return null

## Every non-optional objective in `objectives` has reached its required_count in `progress`.
func _all_required_done(objectives: Array[QuestObjective], progress: Dictionary) -> bool:
	for obj in objectives:
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
##
## Only the CURRENT stage's objectives match (a staged quest does not react to an event its player is not on yet), and
## the walk stops for a quest the moment an advance hands it to another stage -- the epoch check -- so one event can
## never tick a same-id objective of the stage it just entered.
func _advance_objectives_matching(obj_type: int, target: StringName, legacy_fallback: StringName = &"") -> void:
	for quest_id in _quests_active.keys():
		var entry: Variant = _quests_active.get(quest_id)
		if entry == null:
			continue
		var quest: Quest = entry["quest"]
		var epoch := int(entry.get("epoch", 0))
		for obj in quest.objectives_for_stage(entry.get("stage", &"")):
			if not _at_epoch(quest_id, epoch):
				break
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
## A STAGED active quest also carries `stage` -- its current stage id, beside the progress that belongs to that stage
## (SAVE_VERSION 6). A stage-less quest writes no `stage` key at all, so its record is byte-for-byte the pre-stages
## {path, progress} an older build reads.
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
		var rec := {"path": q.resource_path, "progress": entry.get("progress", {})}
		var stage: StringName = entry.get("stage", &"")
		if stage != &"":
			rec["stage"] = String(stage)
		cfg.set_value("quests_active", String(qid), rec)
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
## STAGES, lazily (SAVE_VERSION 6 -- no load-time fold): a staged quest's record with no `stage` field (a save written
## before stages, or before the quest GAINED stages) resumes in stages[0]; a `stage` that names no stage of the quest
## (renamed or deleted since the save) also resumes in stages[0], with a warning naming it. Resuming never re-runs
## the stage-entry effects: the flags they set were saved with the profile. A stage-less quest ignores the field.
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
			var stage := StringName(str(rec.get("stage", "")))
			if q.has_stages():
				if q.stage_by_id(stage) == null:
					if stage != &"":
						push_warning("QuestTracker: active quest '%s' was saved in stage '%s', which it no longer has -- resuming at its first stage" % [qid, stage])
					stage = q.first_stage_id()
			else:
				stage = &""
			_quests_active[StringName(qid)] = {"quest": q, "stage": stage, "epoch": 0, "progress": progress}
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
