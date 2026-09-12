extends RefCounted

## The STORY commands of the in-game debug console (`flag`, `flags`, `quest`, `quests`, `notify`, `ledger`,
## `wipeobjects`, `resurrect`, `names`): one of the three command families split out of debug_actions_world.gd on
## 2026-09-11. `DebugActionsWorld.run()` still owns EVERY match arm — a registry row's case lives there and calls in
## here — so adding a command is still ONE registry row + ONE match case, plus the `_cmd_*` static in the family
## file it belongs to. Shared helpers live in debug_actions_world_common.gd (`Common.`).
##
## CONTRACT (as the main file): a `_cmd_*` returns the lines to print — NEVER null, NEVER push_error.

const Common := preload("res://scripts/components/debug_actions_world_common.gd")
# Brand-new class_names are preloaded BY PATH into an untyped-usable const, never referenced by their class_name:
# until the editor rescans, a type annotation fails the WHOLE file to parse with "Could not find type X" and that
# cascades into every script that touches it. Precedent: debug_overlay.gd:11 (ErrorSinkScript).
const DebugCommandsScript := preload("res://scripts/components/debug_commands.gd")
const GroupsScript := preload("res://scripts/world/groups.gd")


# =============================================================================================================
# STORY
# =============================================================================================================

## Read / set / ERASE a story flag.
##
## Two traps drive the shape of this command:
##   - set_flag(name, false) does NOT unset. It stores false, still autosaves, and has_flag() still returns true;
##     notify_flag_set is gated on a TRUTHY value so nothing downstream is driven. `clear` is the real unset, and
##     it must poke flags.erase() (there is no public API) plus an explicit autosave, because erase bypasses both.
##   - a TRUTHY set fans out: notify_flag_set -> FLAG objectives advance -> a quest can auto-complete (granting
##     money/xp/items/reputation) -> its next_quest chain starts, and any quest with expire_on_flag FAILS.
static func _cmd_flag(args: PackedStringArray) -> PackedStringArray:
	var flag_name := args[0].strip_edges()
	if flag_name == "":
		return Common._one("flag name is blank")
	var out := PackedStringArray()

	if args.size() < 2:
		if not GameState.has_flag(flag_name):
			out.append("%s: not set" % flag_name)
			return out
		out.append("%s = %s" % [flag_name, str(GameState.get_flag(flag_name))])
		out.append("(as bool: %s)" % str(GameState.get_flag_bool(flag_name)))
		return out

	var raw := args[1].strip_edges()
	var lower := raw.to_lower()
	if lower == "clear":
		# GameState.flags is keyed by String (set_flag coerces a StringName at the boundary), so erase with a String.
		if not GameState.flags.has(flag_name):
			return Common._one("%s was not set — nothing to erase" % flag_name)
		GameState.flags.erase(flag_name)
		GameState.autosave_world_state()  # erase() bypasses the write set_flag would have queued
		out.append("%s ERASED (has_flag is now false)" % flag_name)
		out.append("! nothing was notified and nothing repaints — a quest already advanced by this flag stays advanced.")
		return out

	var value: Variant = raw
	if ["true", "on", "1", "yes"].has(lower):
		value = true
	elif ["false", "off", "0", "no"].has(lower):
		value = false
	elif raw.is_valid_int():
		value = raw.to_int()
	elif raw.is_valid_float():
		value = raw.to_float()

	GameState.set_flag(flag_name, value)
	out.append("%s = %s" % [flag_name, str(value)])
	# ⭐The fan-out predicate MUST be set_flag's own (`if value:` — Variant booleanize, GameState.gd:1172), NOT
	# GameState.as_bool(). as_bool deliberately reports FALSE for anything that is not a bool/int/float, so a
	# `flag mytag hello` would be announced as inert while set_flag had in fact fired notify_flag_set: a non-empty
	# String (or Array / Dictionary) booleanizes TRUE. Reporting the wrong half here is worse than saying nothing,
	# because it tells you no quest moved when one just did.
	if value:
		out.append("! truthy: FLAG objectives advanced, a quest may have auto-completed (rewards granted, next_quest started), and any quest with expire_on_flag FAILED.")
	else:
		out.append("! a falsy value does NOT unset the flag — has_flag() is still true and nothing was notified. Use `flag %s clear` to erase the key." % flag_name)
	out.append("this queued a full-profile write over your Continue save.")
	return out

static func _cmd_flags() -> PackedStringArray:
	var out := PackedStringArray()
	var keys := PackedStringArray()
	for k in GameState.flags.keys():
		keys.append(String(k))
	keys.sort()
	if keys.is_empty():
		out.append("no story flags set this run")
	else:
		for k in keys:
			out.append("  %-44s %s" % [k, str(GameState.flags[k])])
		out.append("%d flag(s) set" % keys.size())
	# The shipped game authors essentially zero story flags — a content scan would come back empty, so name the one
	# flag that actually exists in code.
	out.append("known in code: %s" % String(GameState.HOLSTER_FORGIVENESS_TUTORIAL_SEEN_FLAG))
	return out

## Start / complete / fail / inspect / advance a quest, keyed by Quest.id — which is NOT the filename
## (resources/quests/recover_the_package.tres declares id "recover_package"). The registry row is
## [VERB, QUEST, TEXT, NUMBER] min 2, so `args` is 2..4 long: slots 2 and 3 (objective id, amount) exist only for
## `advance` and are IGNORED by the other four verbs, so `quest show x y 3` is not an arity error.
static func _cmd_quest(args: PackedStringArray) -> PackedStringArray:
	var verb := args[0].to_lower()
	var wanted := args[1]
	var path := Common._lookup(Common._quests(), wanted)
	if path == "":
		return Common._one("no quest with id \"%s\" — try: %s" % [wanted, ", ".join(Common._sorted_keys(Common._quests()))])
	# Typed as Quest so it can be handed straight to QuestTracker.start_quest (which takes the RESOURCE, not an id)
	# without an unsafe-argument downcast — and so a .tres that is NOT a Quest comes back null instead of erroring
	# deep inside the tracker.
	var quest := load(path) as Quest
	if quest == null:
		return Common._one("%s did not load as a Quest" % path)
	var qid := StringName(String(quest.get("id")))

	match verb:
		"show":
			return Common._quest_report(quest, qid, path)
		"start":
			# start_quest has SIX silent no-op paths. Report WHICH one hit, or the command just looks broken.
			if qid == &"":
				return Common._one("%s has a BLANK id — start_quest refuses it" % path.get_file())
			if QuestTracker.is_quest_active(qid):
				return Common._one("%s is already ACTIVE — start_quest no-ops" % qid)
			if QuestTracker.is_quest_completed(qid):
				return Common._one("%s is already COMPLETED — start_quest no-ops" % qid)
			if QuestTracker.is_quest_failed(qid):
				return Common._one("%s is FAILED — closed forever. start_quest refuses it and there is no un-fail; only QuestTracker.reset() reopens it." % qid)
			var prereq := StringName(String(quest.get("prereq_quest_id")))
			if prereq != &"" and not QuestTracker.is_quest_completed(prereq):
				return Common._one("%s needs prereq \"%s\" completed first — start_quest no-ops" % [qid, prereq])
			QuestTracker.start_quest(quest)
			var out := PackedStringArray()
			if QuestTracker.is_quest_active(qid):
				out.append("started %s (\"%s\")" % [qid, String(quest.get("title"))])
			else:
				out.append("start_quest ran but %s is still not active — a no-op path this command did not anticipate" % qid)
			out.append("FLAG objectives whose flag was already set were back-filled; a full-profile save was queued.")
			return out
		"complete":
			if not QuestTracker.is_quest_active(qid):
				return Common._one("%s is not ACTIVE — complete_quest requires an active quest (state: %s)" % [qid, Common._quest_state(qid)])
			QuestTracker.complete_quest(qid)
			var out2 := PackedStringArray()
			out2.append("completed %s" % qid)
			out2.append(Common._reward_text(quest))
			out2.append("! rewards were granted BEFORE quest_completed fired — and grant silently gives NOTHING with no live player (a main-menu context).")
			if quest.get("next_quest") != null:
				out2.append("next_quest chained automatically.")
			return out2
		"fail":
			if not QuestTracker.is_quest_active(qid):
				return Common._one("%s is not ACTIVE — fail_quest requires an active quest (state: %s)" % [qid, Common._quest_state(qid)])
			QuestTracker.fail_quest(qid)
			var out3 := PackedStringArray()
			out3.append("failed %s — no rewards, no chaining" % qid)
			out3.append("! a failed quest can NEVER be restarted. Only QuestTracker.reset() (which wipes the whole journal) gets it back.")
			return out3
		"advance":
			return _quest_advance(quest, qid, args)
	return Common._one("unknown quest action \"%s\"" % verb)

## `quest advance <quest> [objective] [n]` — tick ONE objective through QuestTracker.advance_objective, the real
## path (objective_advanced -> HUD tracker + compass/minimap marker sync -> auto_complete -> complete_quest ->
## rewards -> next_quest). `complete` skips all of that, so this is the only way to stand a quest at KILL 3/5
## without killing things.
##
## Three silent no-ops in advance_objective are turned into lines here: quest not ACTIVE (:111), unknown objective
## id (:116-117), and — not a no-op but invisible — the mini() clamp to required_count (:120) that makes a tick on a
## finished objective change nothing while STILL firing the signal and the cascade check. Progress is keyed by
## String(objective_id) inside the tracker; we only ever go through its API, never poke _quests_active.
##
## Objective ids are PER-QUEST (quest.objectives[].id, blank ones are unkeyed), so with no id given the objectives
## are LISTED with live progress and nothing is ticked. The list is taken off the tracker's OWN Quest instance
## (active_quest) rather than the disk copy: load() caches, so they are normally the same resource, but the ids
## advance_objective will actually match are the tracker's — that instance is the truth.
static func _quest_advance(quest: Quest, qid: StringName, args: PackedStringArray) -> PackedStringArray:
	var live := QuestTracker.active_quest(qid)
	if live != null:
		quest = live
	var oid_raw := args[2].strip_edges() if args.size() > 2 else ""
	var active := QuestTracker.is_quest_active(qid)
	var out := PackedStringArray()

	if oid_raw == "":
		if active:
			out.append("quest advance %s needs an objective id — objectives (progress/required):" % qid)
		else:
			out.append("%s is not ACTIVE (state: %s) — advance_objective silently no-ops on it; `quest start %s` first. Its objectives:" % [qid, Common._quest_state(qid), qid])
		out.append_array(_objective_lines(quest, qid))
		out.append("usage: quest advance %s <objective id> [amount]   (amount defaults to 1; a negative amount un-ticks)" % qid)
		return out

	if not active:
		return Common._one("%s is not ACTIVE (state: %s) — advance_objective returns before touching anything; `quest start %s` first" % [qid, Common._quest_state(qid), qid])

	var obj := _find_objective(quest, oid_raw)
	if obj == null:
		out.append("no objective \"%s\" on %s (matched exactly, then case-insensitively) — advance_objective would silently no-op. Objectives:" % [oid_raw, qid])
		out.append_array(_objective_lines(quest, qid))
		return out
	var oid := StringName(String(obj.get("id")))
	if oid == &"":
		return Common._one("that objective has a BLANK id — start_quest never seeded progress for it and advance_objective cannot address it (author an id on the QuestObjective)")

	var amount := 1
	if args.size() > 3:
		amount = int(args[3].to_float())
	if amount == 0:
		return Common._one("amount 0 ticks nothing (it would still fire objective_advanced and the auto-complete check for no change) — pass a positive count, or a negative one to un-tick")
	var required := Common._int_of(obj.get("required_count"), 1)
	var before := QuestTracker.objective_progress(qid, oid)
	# The tracker clamps only the TOP (mini to required_count): a negative amount past zero would leave a NEGATIVE
	# count in the save. Floor it here and say so.
	var floored := false
	if amount < 0 and before + amount < 0:
		amount = -before
		floored = true
	if amount == 0:
		return Common._one("%s/%s is already at 0 — nothing to un-tick" % [qid, oid])
	var active_before := _active_id_set()

	QuestTracker.advance_objective(qid, oid, amount)

	if oid_raw != String(oid):
		out.append("(\"%s\" resolved case-insensitively to the authored id \"%s\")" % [oid_raw, oid])
	if floored:
		out.append("(amount floored to %d so the count cannot go below 0 — the tracker only clamps the top)" % amount)
	# It was ACTIVE going in (guarded above), so "completed now" can only mean this very call cascaded.
	if QuestTracker.is_quest_completed(qid):
		# The whole cascade fired inside that one call: mini() clamp -> objective_advanced -> _all_required_done ->
		# complete_quest -> _grant_quest_rewards -> quest_completed -> start_quest(next_quest).
		out.append("%s/%s %d -> DONE (%d required) and that was the LAST open required objective: auto_complete cascaded — %s is COMPLETED" % [qid, oid, before, required, qid])
		out.append("  " + Common._reward_text(quest) + " — granted NOW (nothing is granted with no live player, e.g. a main-menu context)")
		var next_v: Variant = quest.get("next_quest")
		if next_v != null and next_v is Resource:
			var next_id := StringName(String((next_v as Resource).get("id")))
			if next_id != &"" and QuestTracker.is_quest_active(next_id) and not active_before.has(String(next_id)):
				out.append("  next_quest %s STARTED (its FLAG objectives whose flag is already set were back-filled)" % next_id)
			elif next_id != &"" and active_before.has(String(next_id)):
				out.append("  next_quest %s was ALREADY active — start_quest no-oped on it" % next_id)
			elif next_id != &"" and QuestTracker.is_quest_completed(next_id):
				# Two histories read the same here: it was completed before (start_quest refused it), or it STARTED and
				# its back-filled FLAG objectives completed it inside this very cascade (rewards granted, its own
				# next_quest chained). _new_active_since below names anything that chained past it.
				out.append("  next_quest %s is COMPLETED — either it already was (start_quest no-oped), or it started and its back-filled FLAG objectives finished it in this same cascade (its rewards granted too)" % next_id)
			else:
				out.append("  next_quest %s did NOT start (failed already, blank id, or an unmet prereq — start_quest's silent no-ops)" % next_id)
	else:
		var after := QuestTracker.objective_progress(qid, oid)
		var done := QuestTracker.is_objective_done(qid, oid)
		out.append("%s/%s %d -> %d / %d%s" % [qid, oid, before, after, required, "  DONE" if done else ""])
		if after == before:
			out.append("  no change: already at required_count — mini() clamped it, but objective_advanced STILL fired and the auto-complete check ran")
		if done:
			var open := _open_required_objectives(quest, qid)
			if not Common._bool_of(quest.get("auto_complete")):
				if open.is_empty():
					out.append("  every required objective is met but auto_complete is OFF — `quest complete %s` is the explicit turn-in" % qid)
			elif not open.is_empty():
				out.append("  still open (required): %s — the quest completes when the last of these is met" % ", ".join(open))
	out.append("objective_advanced fired (HUD quest tracker + compass/minimap markers repaint); a coalesced full-profile write was queued over your Continue save (it also nulls a pending in-memory WorldSnapshot).")
	var started := _new_active_since(active_before)
	if not started.is_empty():
		out.append("newly ACTIVE after the cascade: %s" % ", ".join(started))
	return out

## Per-objective lines for `quest advance` (id, type word, target, optional, and live progress while ACTIVE).
## Read duck-typed off the Resource like _quest_report, so a partial/malformed objective degrades to a line.
static func _objective_lines(quest: Resource, qid: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	var objectives_v: Variant = quest.get("objectives")
	if not (objectives_v is Array):
		out.append("  (no objectives array on this quest)")
		return out
	var objectives: Array = objectives_v
	var active := QuestTracker.is_quest_active(qid)
	var listed := 0
	for o in objectives:
		var obj := o as Resource
		if obj == null:
			continue
		var oid := StringName(String(obj.get("id")))
		var line := "  %-18s %-10s target \"%s\"" % [
			(String(oid) if oid != &"" else "(blank id!)"), _objective_type_text(Common._int_of(obj.get("type"), -1)), String(obj.get("target_id"))]
		if Common._bool_of(obj.get("optional")):
			line += " (optional)"
		if active and oid != &"":
			# objective_progress reads 0 for a NON-active quest and is_objective_done reads true for EVERY objective
			# of a completed one — both only mean something while the quest is active (same caveat as `quest show`).
			line += "   %d/%d%s" % [
				QuestTracker.objective_progress(qid, oid), Common._int_of(obj.get("required_count"), 1),
				"  DONE" if QuestTracker.is_objective_done(qid, oid) else ""]
		out.append(line)
		listed += 1
	if listed == 0:
		out.append("  (no objectives authored)")
	return out

## The objective whose id is `wanted` — exact first, then case-insensitive (typing convenience; the RESOLVED
## authored id is what gets sent, and the caller says so). Null when nothing matches.
static func _find_objective(quest: Resource, wanted: String) -> Resource:
	var objectives_v: Variant = quest.get("objectives")
	if not (objectives_v is Array):
		return null
	var objectives: Array = objectives_v
	for o in objectives:
		var obj := o as Resource
		if obj != null and String(obj.get("id")) == wanted:
			return obj
	var lower := wanted.to_lower()
	for o in objectives:
		var obj := o as Resource
		if obj != null and String(obj.get("id")).to_lower() == lower:
			return obj
	return null

## Ids of the REQUIRED (non-optional) objectives of an ACTIVE quest that are not yet done — what still gates
## auto-complete. Empty for a non-active quest.
static func _open_required_objectives(quest: Resource, qid: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	if not QuestTracker.is_quest_active(qid):
		return out
	var objectives_v: Variant = quest.get("objectives")
	if not (objectives_v is Array):
		return out
	var objectives: Array = objectives_v
	for o in objectives:
		var obj := o as Resource
		if obj == null or Common._bool_of(obj.get("optional")):
			continue
		var oid := StringName(String(obj.get("id")))
		if oid != &"" and not QuestTracker.is_objective_done(qid, oid):
			out.append(String(oid))
	return out

## { quest id -> true } of everything active right now — snapshotted BEFORE a cascade so newly chained quests
## (next_quest, and its next_quest if a back-filled FLAG completes it in turn) can be named afterwards.
static func _active_id_set() -> Dictionary:
	var out := {}
	for a in QuestTracker.active_quest_ids():
		out[String(a)] = true
	return out

static func _new_active_since(before: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for a in QuestTracker.active_quest_ids():
		var s := String(a)
		if not before.has(s):
			out.append(s)
	out.sort()
	return out

## if/elif rather than `match`, like _perception_state_text: an enum reached through a class is a subscript the
## analyzer need not fold into a constant pattern — a comparison always works.
static func _objective_type_text(t: int) -> String:
	if t == QuestObjective.Type.KILL:
		return "KILL"
	if t == QuestObjective.Type.TALK:
		return "TALK"
	if t == QuestObjective.Type.PICKUP:
		return "PICKUP"
	if t == QuestObjective.Type.ENTER_AREA:
		return "ENTER_AREA"
	if t == QuestObjective.Type.USE_ITEM:
		return "USE_ITEM"
	if t == QuestObjective.Type.FLAG:
		return "FLAG"
	return "type %d" % t

## `notify <kill|talk|pickup|enter|use> [target] [legacy name]` — fire the SAME QuestTracker hook the game fires
## (npc.gd _on_died -> notify_kill / DialogueManager.start -> notify_talk / CanPickUp -> notify_pickup /
## TriggerVolume -> notify_enter / Player.use_consumable -> notify_use) WITHOUT doing the thing, and report which
## active objectives matched. `quest advance` bypasses matching entirely; the bug class this project actually had is
## the KEY — quests key NpcData.id (the identity key) with the display name as a legacy fallback
## (_advance_objectives_matching), and only a notify-driven test proves an authored target_id will ever match.
##
## With no target, kill/talk take the NPC under the crosshair through the module's picker (_resolve_aimed_npc: the
## crosshair NPC first, else the sticky last `npc` target — labelled) and send its identity_key() as the target
## with its live display_name as the legacy fallback — exactly the pair npc.gd:1420 sends on a real kill. The
## match report mirrors the tracker's own predicate (target_id == target, or == legacy when legacy differs from
## target) rather than diffing counts, because a tick on an already-finished objective changes no count while
## STILL matching (and still cascading).
static func _cmd_notify(ctx: Dictionary, args: PackedStringArray) -> PackedStringArray:
	var verb := args[0].strip_edges().to_lower()
	var obj_type := _notify_type_for(verb)
	if obj_type < 0:
		return Common._one("unknown notify event \"%s\" (kill, talk, pickup, enter, use — registry/actions drift)" % verb)
	var target := args[1].strip_edges() if args.size() > 1 else ""
	var legacy := args[2].strip_edges() if args.size() > 2 else ""
	var pair := verb == "kill" or verb == "talk"
	var out := PackedStringArray()
	# Only notify_kill / notify_talk take a legacy fallback; the registry row is one shape for all five verbs, so a
	# third token on pickup/enter/use is legal to type but NEVER reaches the tracker. It must not reach the match
	# report either — mirroring the tracker's predicate with a legacy the hook never received would print a MATCH
	# for an objective the game did not advance. Blank it here and say so.
	if not pair and legacy != "":
		out.append("(third argument \"%s\" ignored — notify_%s takes one id; only kill/talk have a legacy-name fallback)" % [legacy, verb])
		legacy = ""

	if target == "":
		if not pair:
			var need := "an Item.id (`items` lists them)"
			if verb == "enter":
				need = "an area name (a TriggerVolume's quest_area_id — none ships in any level, so this is the only way to test ENTER_AREA today)"
			return Common._one("notify %s needs a target: %s" % [verb, need])
		var pick := Common._resolve_aimed_npc(ctx)
		var err: String = pick[&"error"]
		if err != "":
			return Common._one("notify %s: %s" % [verb, err])
		var npc: Node = pick[&"npc"]
		if not npc.has_method(&"identity_key"):
			return Common._one("notify %s: %s has no identity_key() — not an NPC-shaped node" % [verb, String(npc.name)])
		target = String(npc.call(&"identity_key"))
		if legacy == "":
			var dn: Variant = npc.get(&"display_name")
			legacy = String(dn) if dn is String else ""
		out.append("notify %s <- %s%s" % [verb, Common._npc_label(npc), "   (sticky: your last `npc` target — the crosshair is not on an NPC)" if bool(pick[&"sticky"]) else ""])
		if target == "":
			out.append("notify %s: that NPC's identity_key() is BLANK (no NpcData.id and no display_name) — nothing to send, hook NOT fired" % verb)
			return out

	# Snapshot BEFORE the hook so the cascade (auto-complete -> rewards -> next_quest) can be named afterwards.
	var rows := _objective_rows_of_type(obj_type)
	var active_before := _active_id_set()
	var t_key := StringName(target)
	var l_key := StringName(legacy)
	var source := ""
	match verb:
		"kill":
			QuestTracker.notify_kill(t_key, l_key)
			source = "NPC._on_died fires on a player kill"
		"talk":
			QuestTracker.notify_talk(t_key, l_key)
			source = "DialogueManager.start fires with a named speaker"
		"pickup":
			QuestTracker.notify_pickup(t_key)
			source = "CanPickUp fires on a pickup"
		"enter":
			QuestTracker.notify_enter(t_key)
			source = "TriggerVolume fires with a quest_area_id"
		"use":
			QuestTracker.notify_use(t_key)
			source = "Player.use_consumable fires on use"
	var sent := "\"%s\"" % target
	if pair and legacy != "":
		sent += ", legacy \"%s\"" % legacy
	out.append("QuestTracker.notify_%s(%s) fired — the hook %s" % [verb, sent, source])

	if rows.is_empty():
		out.append("no ACTIVE %s objective exists right now — nothing could match (`quests` lists what is on disk; `quest start <id>` first)" % _objective_type_text(obj_type))
	else:
		var matched := 0
		for r in rows:
			var qid := StringName(String(r["qid"]))
			var oid := StringName(String(r["oid"]))
			var authored := StringName(String(r["target"]))
			var hit_id := authored == t_key
			var hit_legacy := l_key != &"" and l_key != t_key and authored == l_key
			if hit_id or hit_legacy:
				matched += 1
				var after_text := "quest COMPLETED" if QuestTracker.is_quest_completed(qid) else str(QuestTracker.objective_progress(qid, oid))
				out.append("  MATCH %s/%s (target_id \"%s\" via the %s): %d -> %s / %d" % [
					qid, oid, authored, "identity key" if hit_id else "legacy display name", int(r["before"]), after_text, int(r["required"])])
			else:
				out.append("  no match %s/%s: target_id \"%s\" != %s" % [qid, oid, authored, sent])
		if matched == 0:
			out.append("! no active %s objective's target_id matched what was sent — the exact bug class this command exposes: for KILL/TALK author the NpcData.id (or the display name as the legacy fallback), for PICKUP/USE_ITEM the Item.id, for ENTER_AREA the TriggerVolume's quest_area_id" % _objective_type_text(obj_type))
		else:
			out.append("each match ran the full advance cascade: objective_advanced (HUD tracker + markers) -> auto_complete -> rewards (money/xp/items/rep) -> next_quest, and queued a full-profile write over your Continue save (nulling a pending in-memory WorldSnapshot).")
	var started := _new_active_since(active_before)
	if not started.is_empty():
		out.append("newly ACTIVE after the cascade: %s" % ", ".join(started))

	# What did NOT happen — the hook is the whole command.
	match verb:
		"kill":
			out.append("hook only — no NPC died: no XP, bounty, corpse, faction kill_penalty or witness bark (`npc kill` does the real thing).")
		"talk":
			out.append("hook only — DialogueManager.start was NOT called: no speaker freeze, no tree pause, no reveal_name, no cursor change.")
		"enter":
			out.append("hook only — no TriggerVolume fired its other actions (flags, level load, cutscene).")
		_:
			out.append("hook only — no item moved or was consumed.")
	return out

## Every objective of `obj_type` on every ACTIVE quest, with its progress BEFORE a hook fires — the rows the
## tracker's _advance_objectives_matching walks. Read through the tracker's public API only (active_quest_ids /
## active_quest / objective_progress); the id list is a fresh keys() Array, so a cascade erasing from
## _quests_active cannot invalidate this walk.
static func _objective_rows_of_type(obj_type: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for a in QuestTracker.active_quest_ids():
		var qid := StringName(String(a))
		var quest := QuestTracker.active_quest(qid)
		if quest == null:
			continue
		var objectives_v: Variant = quest.get("objectives")
		if not (objectives_v is Array):
			continue
		var objectives: Array = objectives_v
		for o in objectives:
			var obj := o as Resource
			if obj == null or Common._int_of(obj.get("type"), -1) != obj_type:
				continue
			var oid := StringName(String(obj.get("id")))
			rows.append({
				"qid": String(qid), "oid": String(oid), "target": String(obj.get("target_id")),
				"required": Common._int_of(obj.get("required_count"), 1), "before": QuestTracker.objective_progress(qid, oid),
			})
	return rows

## notify verb -> QuestObjective.Type, -1 for an unknown word (validate() already restricted the slot, so -1 is
## registry/actions drift). if-chain for the same reason as _objective_type_text.
static func _notify_type_for(verb: String) -> int:
	if verb == "kill":
		return QuestObjective.Type.KILL
	if verb == "talk":
		return QuestObjective.Type.TALK
	if verb == "pickup":
		return QuestObjective.Type.PICKUP
	if verb == "enter":
		return QuestObjective.Type.ENTER_AREA
	if verb == "use":
		return QuestObjective.Type.USE_ITEM
	return -1

## `ledger [all]` — READ-ONLY dump of the live save-ledger state. Three things nothing else shows:
##   1. GameState.world_objects (the additive per-object PROFILE-tier ledger: Door open/locked, consumed pickups,
##      destroyed props) for the current level — every level with `all`;
##   2. GameState._dead_authored (the cross-level authored-NPC death ledger — EXACT-SNAPSHOT tier only, private
##      with no getter and no clear, read via GameState.get(&"…") — underscore is convention here, not access);
##   3. the latches: world_snapshot present?, _world_snapshot_pending, reload_pending(), _world_save_queued.
## Flags the two key-shape traps world_save_id.gd documents: entries on the FRAGILE level|path|pos fallback (no
## save_id — a move/rename silently orphans them) and entries whose level component is BLANK (recorded while
## current_level_path was "" — the code-built LevelData trap). The editor Saves dock reads ON-DISK cfg only and
## the F3 overlay shows account/level/time, so _dead_authored appears nowhere else.
## Never calls consume_world_snapshot() (a destructive one-shot latch) or take_load_warnings() (consume-once, and
## ui.gd already owns it) — every read here is a plain field/getter.
static func _cmd_ledger(args: PackedStringArray) -> PackedStringArray:
	var all := not args.is_empty() and args[0].strip_edges().to_lower() == "all"
	var level := String(GameState.current_level_path)
	var out := PackedStringArray()
	out.append("ledger — current level \"%s\"%s" % [level, "   (BLANK: no level loaded, or a code-built LevelData — this level's buckets are keyed by \"\")" if level == "" else ""])

	# --- 1. world_objects (profile tier) ---
	var wo: Dictionary = GameState.world_objects
	var levels := PackedStringArray()
	if all:
		levels = Common._sorted_keys(wo)
		var total := 0
		for lvl in levels:
			var b: Variant = wo.get(lvl)
			if b is Dictionary:
				total += (b as Dictionary).size()
		out.append("-- world_objects: %d level bucket(s), %d entries in all   (profile tier: Continue, quicksave and slot files all carry it)" % [levels.size(), total])
		if levels.is_empty():
			out.append("   (empty — nothing has recorded object state this run)")
	else:
		levels.append(level)
	for lvl in levels:
		var bucket_v: Variant = wo.get(lvl)
		if not (bucket_v is Dictionary) or (bucket_v as Dictionary).is_empty():
			out.append("-- world_objects[\"%s\"]: no entries%s" % [lvl, "" if all else "   (profile tier: Continue, quicksave and slot files all carry it; `ledger all` shows other levels)"])
			continue
		var bucket: Dictionary = bucket_v
		out.append("-- world_objects[\"%s\"]: %d entr%s%s" % [lvl, bucket.size(), "y" if bucket.size() == 1 else "ies", "" if all else "   (profile tier: Continue, quicksave and slot files all carry it)"])
		var keys := Common._sorted_keys(bucket)
		var fragile := 0
		var blank_level := 0
		var shown := 0
		for k in keys:
			if not k.begins_with("id:"):
				fragile += 1
				if k.begins_with("|"):
					blank_level += 1
			if shown < Common.LEDGER_MAX_LINES:
				var st: Variant = bucket.get(k)
				out.append("   %s  ->  %s" % [k, Common._facts_text(st as Dictionary) if st is Dictionary else str(st)])
				shown += 1
		if keys.size() > shown:
			out.append("   ... %d more" % (keys.size() - shown))
		if fragile > 0:
			out.append("   ! %d on the FRAGILE fallback key (no save_id): moving or renaming that node between saves silently orphans the entry (world_save_id.gd @risk)" % fragile)
		if blank_level > 0:
			out.append("   ! %d recorded with a BLANK level component (current_level_path was \"\" at record time — the code-built LevelData trap); a real level never matches them" % blank_level)

	# --- 2. the cross-level dead-NPC ledger (exact-snapshot tier) ---
	var dead_v: Variant = GameState.get(&"_dead_authored")
	if not (dead_v is Dictionary):
		out.append("-- dead authored NPCs: GameState has no _dead_authored Dictionary (API drift) — nothing to read")
	else:
		var dead: Dictionary = dead_v
		var dlevels := PackedStringArray()
		if all:
			dlevels = Common._sorted_keys(dead)
			out.append("-- dead authored NPCs (_dead_authored): %d level bucket(s)   (exact-snapshot tier ONLY: session-live, reaches disk only folded into a manual quick/slot save's [world_snapshot]; the profile never carries it; load_level frees the NPCs under these keys on EVERY re-instantiate)" % dlevels.size())
			if dlevels.is_empty():
				out.append("   (empty — no authored NPC has died this session and no snapshot load restored one)")
		else:
			dlevels.append(level)
		for lvl in dlevels:
			var b: Variant = dead.get(lvl)
			if not (b is Dictionary) or (b as Dictionary).is_empty():
				out.append("-- dead authored NPCs [\"%s\"]: none%s" % [lvl, "" if all else "   (exact-snapshot tier ONLY: session-live, folded into a manual quick/slot save; the profile never carries it; load_level frees the NPCs under these keys on every re-instantiate)"])
				continue
			var keys := Common._sorted_keys(b as Dictionary)
			out.append("-- dead authored NPCs [\"%s\"]: %d%s" % [lvl, keys.size(), "" if all else "   (exact-snapshot tier ONLY: session-live, folded into a manual quick/slot save; the profile never carries it; load_level frees the NPCs under these keys on every re-instantiate — `resurrect` clears this bucket)"])
			var shown := 0
			for k in keys:
				if shown < Common.LEDGER_MAX_LINES:
					out.append("   %s" % k)
					shown += 1
			if keys.size() > shown:
				out.append("   ... %d more" % (keys.size() - shown))

	# --- corpse discovery, the one other profile-tier world ledger (not level-bucketed) ---
	out.append("-- discovered_corpses: %d key(s) in all   (profile tier; keyed by Corpse.save_id / the WorldSaveId fallback, not bucketed per level)" % GameState.discovered_corpses.size())

	# --- 3. latches ---
	var snap: Variant = GameState.get(&"world_snapshot")
	var snap_text := "none"
	if snap != null and is_instance_valid(snap):
		snap_text = "present"
		if snap.has_method(&"is_empty") and bool(snap.call(&"is_empty")):
			snap_text += " (empty)"
	out.append("-- latches: world_snapshot %s · _world_snapshot_pending %s · reload_pending %s · _world_save_queued %s" % [
		snap_text, str(Common._bool_of(GameState.get(&"_world_snapshot_pending"))), str(bool(GameState.reload_pending())), str(Common._bool_of(GameState.get(&"_world_save_queued")))])
	out.append("   world_snapshot = the in-memory exact snapshot left by the last manual quick/slot save or load (ANY autosave nulls it); pending = a loaded one GameRoot has not applied yet; reload_pending = a quickload is in flight (autosave refuses); _world_save_queued = a coalesced world-state autosave flushes at end of frame.")
	out.append("key shape (WorldSaveId.key_for): 'id:<save_id>' when the object has an authored save_id, else '<level>|<node path>|x,y,z' (fragile — re-keys on any move/rename); NPC.snapshot_key drops the position: 'id:<save_id>' else '<level>|<node path>'.")
	out.append("in NEITHER ledger by design: corpses, dropped loot, dynamic (spawner) NPCs. Container contents ride the exact-snapshot tier only.")
	return out

## `wipeobjects` (danger) — erase this level's world_objects bucket, persist the erase, then re-instantiate the level
## in place so every consumed pickup / opened door / destroyed prop comes back at its authored state — without a New
## Game. The survey's own gotcha: world_objects has no public clear; the ONLY in-repo clear sits inside
## reset_for_new_game(), which also wipes money, stats, quests, flags and reputation. And clearing the ledger changes
## NOTHING on screen by itself — Door / CanPickUp / CanDestroy / MoneyPickup / UpgradePickup all consult it only in
## _ready — so the re-instantiate is half the command.
##
## ORDER: guards (BEFORE any mutation, so a refusal never leaves the ledger erased with the level still showing the
## old state) -> erase -> autosave_world_state() -> load_level(same LevelData, place_at_spawn=false). The autosave is
## queued deferred and runs BEFORE load_level's own deferred hooks (FIFO), so what hits disk is the wiped ledger.
static func _cmd_wipeobjects(ctx: Dictionary) -> PackedStringArray:
	var g := _same_level_reload_guard(ctx)
	var err: String = g[&"error"]
	if err != "":
		return Common._one("wipeobjects REFUSED — " + err)
	var path: String = g[&"path"]
	var bucket_v: Variant = GameState.world_objects.get(path)
	var count := (bucket_v as Dictionary).size() if bucket_v is Dictionary else 0
	if count == 0:
		var none := PackedStringArray()
		none.append("no world_objects entries recorded under \"%s\" — nothing to wipe, and the level was NOT re-loaded." % path)
		none.append("(`reload` re-instantiates the whole scene; `ledger all` shows whether the entries sit under a different level key)")
		return none

	GameState.world_objects.erase(path)
	GameState.autosave_world_state()  # erase() bypasses the write record_object_state would have queued
	var out := PackedStringArray()
	out.append("wiped %d world_objects entr%s for \"%s\" (doors' open/locked, consumed pickups, destroyed props)." % [count, "y" if count == 1 else "ies", path])
	# The flush resolves the player itself (GameState.live_player, by group) — ctx's handle is only a proxy for
	# whether that will find anyone; autosave() is a hard no-op without an in-tree player.
	if Common._player(ctx) == null:
		out.append("! no player in ctx: if there is no live in-tree player the queued autosave NO-OPs, and the wipe lives in memory only until the next successful save.")
	else:
		out.append("a coalesced full-profile autosave was queued (deferred, end of frame): your Continue save now holds the wiped ledger, and a pending in-memory WorldSnapshot is nulled by it. (Sandbox rewrite applies if `sandbox on`.)")
	out.append_array(_reload_same_level(ctx, g))
	out.append("every Door / CanPickUp / CanDestroy / MoneyPickup / UpgradePickup reads the ledger ONLY in _ready — the re-instantiate is what makes them come back authored.")
	out.append("untouched: discovered_corpses, the cross-level dead-NPC ledger (authored NPCs you killed stay dead — `resurrect` is the other half), and the exact-snapshot container DATA in any quick/slot file (the LIVE containers still re-seeded authored contents, per the line above — that is the re-instantiate, not this ledger).")
	out.append("! a quicksave / slot file written BEFORE this still holds the OLD ledger — loading it brings every entry back.")
	return out

## `resurrect` (danger) — forget every authored-NPC death recorded for this level (GameState._dead_authored[level],
## the private cross-level ledger) and re-instantiate the level in place, so every authored NPC the player killed
## this session stands again — the undo for `killall`. The trap it exists for: `killall` -> take_damage -> died ->
## NPC._record_snapshot_death -> GameState.record_npc_death for every AUTHORED body; then `reload` / a door swap ->
## GameRoot.load_level -> _suppress_dead_authored frees them again, so the level stays EMPTY for the rest of the
## process; only a New Game or a quickload resets the ledger, and nothing public clears it.
##
## The Dictionary GameState.get(&"_dead_authored") hands back IS the field (Godot Dictionaries are shared by
## reference; only duplicate() copies), so erase() on it lands on the ledger itself. That is the ONLY route — an
## intentional underscore reach, verified after the fact so a copy could never masquerade as a clear.
static func _cmd_resurrect(ctx: Dictionary) -> PackedStringArray:
	var g := _same_level_reload_guard(ctx)
	var err: String = g[&"error"]
	if err != "":
		return Common._one("resurrect REFUSED — " + err)
	var path: String = g[&"path"]
	var dead_v: Variant = GameState.get(&"_dead_authored")
	if not (dead_v is Dictionary):
		return Common._one("resurrect REFUSED — GameState has no _dead_authored Dictionary (API drift); nothing to clear, level not re-loaded")
	var dead: Dictionary = dead_v
	var bucket_v: Variant = dead.get(path)
	var keys := Common._sorted_keys(bucket_v as Dictionary) if bucket_v is Dictionary else PackedStringArray()
	if keys.is_empty():
		var none := PackedStringArray()
		none.append("no authored deaths recorded for \"%s\" — every authored NPC already stands (or was never killed); the level was NOT re-loaded." % path)
		none.append("dynamic (spawner-produced) bodies never enter this ledger — their EncounterSpawner re-arms on a `reload`. `ledger all` shows other levels' buckets.")
		return none

	dead.erase(path)
	# Belt-and-braces: confirm the erase landed on the FIELD, not on a copy, before freeing the whole level over it.
	var check: Variant = GameState.get(&"_dead_authored")
	if check is Dictionary and (check as Dictionary).has(path):
		return Common._one("resurrect REFUSED — erase() did not reach GameState._dead_authored (a copy came back?); the ledger still holds %d key(s) and the level was NOT re-loaded" % keys.size())

	var out := PackedStringArray()
	var named := PackedStringArray()
	for i in mini(keys.size(), Common.RESURRECT_MAX_NAMED):
		named.append(keys[i])
	out.append("forgot %d authored death%s for \"%s\": %s%s" % [
		keys.size(), "" if keys.size() == 1 else "s", path, ", ".join(named),
		("  (+%d more)" % (keys.size() - named.size())) if keys.size() > named.size() else ""])
	out.append_array(_reload_same_level(ctx, g))
	out.append("GameRoot's deferred _suppress_dead_authored now finds an empty bucket, so every authored NPC stands at its .tscn spot with full hp; their corpses went with the old subtree (corpses are not persisted).")
	out.append("kill XP, bounty, faction kill_penalty and any KILL objective fire again on a re-kill — a cheat, they are re-farmable.")
	# The two save tiers, honestly: this ledger never touches the profile, and the exact-snapshot tier is SEPARATE.
	out.append("no disk write happened: this ledger reaches disk only folded into a manual quick/slot save's [world_snapshot]. A quicksave/slot made BEFORE this still holds the deaths — loading it restores _dead_authored from its dead_map() and load_level frees them again (resurrect does NOT survive an older quickload). A quicksave made from HERE captures them alive (capture: live wins) and sticks. Continue/autosave never carried the ledger, so that tier revived them anyway.")
	return out

## The guards `wipeobjects` / `resurrect` run BEFORE touching a ledger, mirroring `_cmd_warp`'s for the SAME
## LevelData — a refusal must never leave a ledger erased while the level still shows the old state. Returns
## {&"error": String (non-empty = refuse verbatim), &"data": the loaded LevelData, &"root": the GameRoot node,
## &"path": GameState.current_level_path}.
static func _same_level_reload_guard(ctx: Dictionary) -> Dictionary:
	var out := {&"error": "", &"data": null, &"root": null, &"path": ""}
	var tree := Common._tree(ctx)
	if tree == null:
		out[&"error"] = "no SceneTree"
		return out
	var path := String(GameState.current_level_path)
	if path == "":
		# A code-built LevelData records nothing (blank resource_path), so there is no .tres to re-load AND every
		# ledger key for it carries a blank level component — the trap `warp` refuses for the same reason.
		out[&"error"] = "GameState.current_level_path is BLANK (no level loaded, or a code-built LevelData) — nothing to re-load; `warp <level>` onto a real .tres first"
		return out
	if not ResourceLoader.exists(path):
		out[&"error"] = "current_level_path \"%s\" does not resolve on disk (deleted / renamed .tres) — cannot re-load it" % path
		return out
	var data := load(path)
	if data == null:
		out[&"error"] = "could not load LevelData %s" % path
		return out
	if String(data.resource_path) == "":
		out[&"error"] = "%s loaded with a blank resource_path — re-loading it would blank current_level_path and break the ledger keys" % path
		return out
	if data.get("scene") == null:
		out[&"error"] = "%s has no `scene` — GameRoot.load_level no-ops on it" % path
		return out
	var gr := Common._game_root(tree)
	if gr == null:
		out[&"error"] = "no GameRoot in the tree (group \"%s\") — an in-place level re-load is only possible in the gameplay scene" % String(GroupsScript.GAME_ROOT)
		return out
	if not gr.has_method(&"load_level"):
		out[&"error"] = "the node in group \"%s\" has no load_level()" % String(GroupsScript.GAME_ROOT)
		return out
	if GameState.reload_pending():
		# The scene is about to reload on its own, autosave() refuses meanwhile, and the ledger edit would ride into
		# a fresh boot that reads the just-loaded profile anyway.
		out[&"error"] = "a quickload is in flight (GameState.reload_pending) — let the fresh scene boot first"
		return out
	out[&"data"] = data
	out[&"root"] = gr
	out[&"path"] = path
	return out

## Re-instantiate the CURRENT level over itself: GameRoot.load_level(same LevelData, entry_id "", place_at_spawn
## = false) — the Player is a SIBLING of Level (game.tscn), so it survives, and place_at_spawn=false leaves it
## standing where it is (game_root.gd:115). Synchronous: instantiate + add_child happen inside the call (safe from
## a console _input / a menu button, NEVER from a _ready). Same post-load notes and state hygiene as `_cmd_warp`;
## unlike `reload`/`load` this does NOT release the scene-scoped state — the player (its ghost meta, the timescale
## override) survives a level swap exactly as it does under `warp`.
static func _reload_same_level(ctx: Dictionary, g: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	# Read both handles as bare Variants and validity-check BEFORE the typed cast: a typed assignment of a freed
	# instance is a script error, not a null (the same rule every ctx accessor here follows).
	var gr_v: Variant = g[&"root"]
	var data_v: Variant = g[&"data"]
	if gr_v == null or not is_instance_valid(gr_v) or data_v == null or not is_instance_valid(data_v):
		out.append("! level re-load skipped: the guard's GameRoot/LevelData went away between check and call")
		return out
	var gr := gr_v as Node
	var data := data_v as Resource
	if gr == null or data == null:
		out.append("! level re-load skipped: the guard handed back a non-Node root or a non-Resource level")
		return out
	gr.call(&"load_level", data, &"", false)
	out.append("level re-instantiated in place (GameRoot.load_level on the same LevelData, place_at_spawn = false — you keep standing where you are; if that was in a doorway that re-closed or on a prop that came back, `noclip`/`tpaim` out).")
	var tree := Common._tree(ctx)
	var lvl := Common._level_node(tree)
	if lvl == null:
		out.append("! no \"Level\" child after the load — the scene may have instantiated null (reimport transient); the old subtree was already detached, so `reload` to recover")
	elif not Common._has_level_root_script(lvl):
		# ps1_warp.gd:43 gates cover() on `level_root is LevelRoot` and returns silently otherwise.
		out.append("! this level's root carries no level_root.gd, so Ps1Warp.cover() skipped it — no PS1 vertex-snap here.")
	out.append("the old subtree was queue_free()d: corpses, dropped items, spawned NPCs and anything you parented into Level are gone; the RentCollector's dawn counters reset (the notice can serve again next dawn), DayNightSky re-captures its authored look, and the fresh NavigationRegion3D needs a map-sync frame before NPCs path.")
	# Everything below is what a fresh Level._ready re-seeds from authored exports — none of it reads either ledger, so
	# it comes back regardless of what the caller wiped (container.gd seeds in _ready and only a WorldSnapshot.apply
	# restores contents; a persist_collected=false pickup never recorded itself; a recruited companion is an authored
	# NPC that stayed parented under Level — CompanionRecruiter never reparents it — so it went with the subtree).
	out.append("also re-seeded to authored by the re-instantiate: every ItemContainer's contents (loot you took is back — re-farmable), MoneyPickup/UpgradePickup with persist_collected off, and every EncounterSpawner re-arms; a recruited companion standing in this level was freed with it and its fresh copy is NOT following you.")
	# The old cast went with the subtree and the new one boots live, so a latched `freezeai ON` would now lie; the
	# sticky `npc` target is a Node that was just freed.
	var state := Common._state(ctx)
	state.erase(Common.STATE_FREEZE_AI)
	state.erase(Common.STATE_NPC_STICKY)
	return out

static func _cmd_quests() -> PackedStringArray:
	var index := Common._quests()
	var out := PackedStringArray()
	if index.is_empty():
		out.append("no Quest resources under %s" % Common.QUEST_DIR)
	for qid in Common._sorted_keys(index):
		var path := String(index[qid])
		var quest := load(path)
		var title := String(quest.get("title")) if quest != null else "?"
		var file := path.get_file()
		var note := "" if file.get_basename() == qid else "   (file: %s)" % file
		out.append("  %-10s %-22s %s%s" % [Common._quest_state(StringName(qid)), qid, title, note])
	out.append("keyed by Quest.id, which is NOT the filename.")
	# active_quest_ids() returns the live dict's keys; anything already tracked but no longer on disk still shows.
	var extra := PackedStringArray()
	for a in QuestTracker.active_quest_ids():
		var s := String(a)
		if not index.has(s):
			extra.append(s)
	if not extra.is_empty():
		out.append("active but not on disk: %s" % ", ".join(extra))
	return out

## Lift or restore the stranger-name veil. `names on` = real names shown (the veil OFF), because that is what a
## debug command is for; the wording is stated explicitly in the output so nobody has to guess the polarity.
static func _cmd_names(args: PackedStringArray) -> PackedStringArray:
	var showing := not bool(GameState.stranger_names_enabled)
	var on := bool(DebugCommandsScript.toggle_value("" if args.is_empty() else args[0], showing))
	GameState.stranger_names_enabled = not on
	var out := PackedStringArray()
	out.append("names %s — real names are %s (stranger_names_enabled = %s)" % [
		"ON" if on else "OFF", "SHOWN" if on else "veiled", str(bool(GameState.stranger_names_enabled))])
	out.append("nothing repaints on the flip: the look-at readout, corpse header and dialogue speaker update on their next natural refresh.")
	out.append("this switch is deliberately NOT serialized — it resets to veiled on the next launch and never bakes into a save.")
	return out
