extends RefCounted

# NO @tool / NO class_name / NO extends Node: a plain script of PURE STATICS backing the Dialogue Edit tab's
# CONSEQUENCES block (the seven fields dialogue_choice.gd exports under @export_group("Consequences") that
# DialogueManager._apply_choice_effects really applies, and that this tab historically told designers to author
# "on the .tres in the raw inspector"). Const-preloaded BY PATH from the @tool glue exactly like its sibling
# dialogue_edit_ops.gd, so there is nothing for the global script class cache to miss.
#
# PURE means: no EditorInterface, no scene tree, no ResourceSaver, no autoload. `load()` IS used (quest_rows has
# to read a .tres to learn its id) which is the same thing dialogue_editor._refresh_picker already does — it works
# headless, so every static here is GUT-testable on throwaway .new() resources and real fixture folders.
#
# Every string here is a DEVELOPER surface (editor tooling): literals on purpose, NEVER routed through PlayerText.
# Everything returned is JSON-safe — real String, never StringName. That matters because JSON.stringify silently
# COERCES a StringName into a quoted string instead of failing, so a leaked StringName is an invisible type drift;
# both `Quest.id` and most DialogueChoice consequence ids ARE StringNames, so each one is String()-ed here.
#
# Field/method names verified against (only the fields this module actually READS are listed — a "verified"
# list that names fields nobody here touches is prose that rots the first time one of them is renamed):
#   scripts/quests/quest.gd:9,29       -> id / prereq_quest_id (both StringName)
#   managers/QuestTracker.gd:88-92     -> the start_quest silent-no-op conditions quest_start_warnings mirrors
#   scripts/dialogue/dialogue_choice.gd:66-89 -> the @export_group("Consequences") block (the seven exports)
#   scripts/dialogue/dialogue_manager.gd:345-380 -> the runtime GATES each summary tag keys off

## Folder scan + the picker-row label helper. Preloaded by path (inspector_calc.gd is itself a plain
## `extends RefCounted` with no class_name), so this module stays independent of the global class cache.
const InspectorCalc := preload("res://addons/cybersunday_tools/inspectors/inspector_calc.gd")

## Shown in place of a blank `Quest.id` in a picker row. Deliberately NOT "(none)" — that label belongs to
## PickerRows row 0, which means "clear the field", and two rows reading the same thing would be a trap.
## A row labelled this way is still selectable: picking it is exactly the case quest_start_warnings warns about.
const BLANK_ID_LABEL := "(no id)"

## Between the quest id and its filename in a picker label: "clear_the_block  (clear_the_block)". Two spaces,
## matching PickerRows.OFF_DISK_SUFFIX, so the parenthetical reads as an annotation rather than part of the id.
const LABEL_SEP := "  "

## Prepended to a NON-EMPTY consequence_summary so the glue can append the result to a choice row with a plain
## `row_text + consequence_summary(ch)` and get "2: I'll take the job.  [Q+]". An EMPTY summary returns "" with
## NO separator, so a consequence-free choice row is byte-identical to today's. Keep the separator INSIDE this
## function: a caller that adds its own would leave trailing whitespace on every effect-free row.
const SUMMARY_PREFIX := "  "

## The consequence tags, in the order consequence_summary emits them. Named consts so the glue's tooltip / the
## authoring docs / the GUT test can all pin the same literals instead of re-typing them.
const TAG_START_QUEST := "[Q+]"       # start_quest_on_choice is assigned  (dialogue_manager.gd:348)
const TAG_COMPLETE_QUEST := "[Q done]"  # complete_quest_id is set         (dialogue_manager.gd:352)
const TAG_ADVANCE_QUEST := "[Q++]"    # BOTH advance ids are set           (dialogue_manager.gd:350)
const TAG_GIVE_ITEM := "[item]"       # an id AND a count > 0              (dialogue_manager.gd:359)
const TAG_GIVE_MONEY := "[$]"         # give_money != 0 (negative = a fee) (dialogue_manager.gd:357)
const TAG_REWARD_REP := "[rep]"       # faction id AND a non-zero delta    (dialogue_manager.gd:375)
const TAG_AGGRO := "[aggro]"          # aggro_speaker                      (dialogue_manager.gd:379)


# ──────────────────────────────────────────────────────────────────────────────────────────────────────────
# Start-quest picker rows
# ──────────────────────────────────────────────────────────────────────────────────────────────────────────

## Rows for the "Start quest" picker: `{"paths": PackedStringArray, "labels": PackedStringArray}`, parallel, ready
## to hand straight to PickerRows.path_rows(paths, labels, current, has_ref). A missing folder yields two empties.
##
## LABELLED BY `quest.id`, NOT BY FILENAME, and that is load-bearing, not cosmetic: resources/quests/
## recover_the_package.tres carries `id = &"recover_package"`, and in the tab this picker sits three rows above
## "Complete quest id" / "Advance quest id", which key on Quest.id. A filename label there teaches the designer the
## wrong key and manufactures a silent runtime no-op (QuestTracker looks up nothing and returns). The filename is
## kept in the parenthetical because that is what the designer sees in the FileSystem dock — both halves are useful,
## the id just has to come first.
##
## Each path is `load()`ed and TYPE-FILTERED with `is Quest`: resources/quests/ may hold other .tres alongside (and
## a failed load returns null, which `is Quest` rejects), so a non-Quest can never reach a picker whose write-back
## assigns to a `Quest` field. Loading the folder is cheap — two files today, and the same reveal already loads all
## ~35 items through ItemIds.ids().
##
## NOTE: InspectorCalc.resource_paths_in is NON-RECURSIVE, while this tab's own `_scan_resources` (the DIALOGUE
## folder scan in dialogue_editor.gd) IS recursive. That difference is deliberate and correct today —
## resources/quests/ is flat (two files), quests are addressed by a flat `id` namespace, and the Quests tab's own
## picker scans it non-recursively too (quest_editor.gd `_scan_quest_paths`), so the two tabs offer the SAME set.
## Do not "fix" this into a recursive scan without also deciding what a nested folder would MEAN for quest ids —
## and without changing quest_editor to match, or the two pickers start disagreeing about what a quest is.
## (Cited by function name, not line number: dialogue_editor.gd is the glue this module ships with and its line
## numbers move every time a row is added.)
static func quest_rows(dir: String) -> Dictionary:
	var paths := PackedStringArray()
	var labels := PackedStringArray()
	for p: String in InspectorCalc.resource_paths_in(dir):
		var res := load(p)  # null on a failed/mid-reimport load — `is Quest` rejects it, so no null ever reaches a row
		if not (res is Quest):
			continue
		var q: Quest = res
		var id := String(q.id)  # StringName -> String: keep the row JSON-safe
		# Split out rather than inlined: GDScript binds `%` TIGHTER than `+`, so the one-liner form of this label
		# reads as if the format applied to the whole concatenation when it does not. Two locals, no ambiguity.
		var shown := id if id != "" else BLANK_ID_LABEL
		var stem := "(%s)" % InspectorCalc.picker_label_for(p)
		paths.append(p)
		labels.append(shown + LABEL_SEP + stem)
	return {"paths": paths, "labels": labels}


# ──────────────────────────────────────────────────────────────────────────────────────────────────────────
# The feature's own audit: will this quest actually start?
# ──────────────────────────────────────────────────────────────────────────────────────────────────────────

## Warnings for a quest a designer just wired into `start_quest_on_choice` — the states where
## QuestTracker.start_quest (managers/QuestTracker.gd:88-92) returns SILENTLY, so the choice would look authored,
## save cleanly, and start NOTHING in game. One line per problem; EMPTY means "this really will start".
## Rendered on the tab's existing `_status` from the pick handler, which is the only feedback surface this write has
## — without it Phase 1 would ship the tab's highest-value field with a green-looking gauge measuring nothing.
##
## AUTHORABLE STATE ONLY, because this module is pure and has no tracker to ask. start_quest also refuses when the
## quest is ALREADY active / completed / failed (and a failed quest is closed for good), but those are live save
## state, not properties of the .tres — a warning about them here would be a guess. The two conditions below are
## fully determined by what is on disk, so they are checkable and worth checking. (A prereq id naming a quest that
## exists on NO .tres is a third on-disk certainty, but proving it needs the folder scan this signature does not
## take — leave it to a caller that has one rather than widening a pure audit into a second scan.)
##
## KEEP EACH LINE SHORT, and keep it in DESIGNER words -- no method names, no field names in backticks, no file
## extensions. These land on the tab's `_status` Label, which is read by someone who never opens a script, and which
## lives OUTSIDE the right column's ScrollContainer with autowrap on -- so every wrapped line is real, permanent
## height. (The panel's height is the CURRENT tab's minimum plus whatever the editor's bottom splitter has already
## grown to; it does not track the tallest tab, so a long line here costs height on THIS tab and keeps it.) Name the
## problem, the consequence and the fix; the reasoning belongs in this docstring, not on screen.
static func quest_start_warnings(quest: Quest) -> PackedStringArray:
	var w := PackedStringArray()
	if quest == null:
		return w  # nothing assigned is not an error — "(none)" is a legitimate authored state
	if quest.id == &"":
		w.append("this quest has no id, so picking the choice starts nothing -- give it one on the Quests tab.")
	if quest.prereq_quest_id != &"":
		w.append("it only starts after quest '%s' is completed -- until then, picking the choice does nothing." % String(quest.prereq_quest_id))
	return w


# ──────────────────────────────────────────────────────────────────────────────────────────────────────────
# Choice-row consequence tags
# ──────────────────────────────────────────────────────────────────────────────────────────────────────────

## A compact "this choice DOES something" suffix for a choice row: "" when nothing fires, else SUMMARY_PREFIX plus
## the space-joined tags in the const order above — "  [Q+] [item] [$]". With the Consequences block scrolling
## below 28 rows, the row text is the only at-a-glance signal that a choice carries a payload at all.
##
## DUCK-TYPED reads (`choice.get(&"...")`), the panel_graph/graph_data.gd:86-101 _choice_has_gate idiom: no
## compile-time DialogueChoice dependency, and it runs off-tree on a bare .new().
##
## EVERY TAG KEYS OFF THE VALUE THE RUNTIME ITSELF GATES ON, never mere field presence, and that is the whole
## subtlety here: `give_item_count` DEFAULTS TO 1 (dialogue_choice.gd:80), so a fresh DialogueChoice is NOT
## all-zero. Tagging "a consequence field is non-default" would put [item] on every new choice ever added.
## `consequence_summary(DialogueChoice.new()) == ""` is the pinned test for exactly that.
##
## `set_flag` is deliberately NOT tagged. It is bookkeeping rather than a payload the player feels, it is already
## the one consequence this tab has surfaced since day one, and it appears on most branching choices — a tag on
## nearly every row is noise, which is the opposite of what this suffix is for.
static func consequence_summary(choice: Variant) -> String:
	# typeof() reads the Variant tag WITHOUT dereferencing, so this is safe even for an Object freed out from under
	# a queued refresh — `choice is Object` would CRASH on a freed instance (is_instance_valid must come first).
	# A non-Object Variant (null, a hand-built Dictionary) is also answered "" rather than poked with .get().
	if typeof(choice) != TYPE_OBJECT or not is_instance_valid(choice):
		return ""
	var tags := PackedStringArray()
	if _is_ref(choice.get(&"start_quest_on_choice")):
		tags.append(TAG_START_QUEST)
	if _txt(choice.get(&"complete_quest_id")) != "":
		tags.append(TAG_COMPLETE_QUEST)
	# BOTH advance fields, because dialogue_manager.gd:350 requires both — one alone advances nothing.
	if _txt(choice.get(&"advance_quest_id")) != "" and _txt(choice.get(&"advance_objective_id")) != "":
		tags.append(TAG_ADVANCE_QUEST)
	# An id AND a positive count, because dialogue_manager.gd:359 gates the inventory add on BOTH — and the tab's
	# "Give item count" SpinBox has min_value 0, so an id with a 0 count is authorable and hands over nothing. Same
	# PAIR shape as [Q++] above and [rep] below: a half-authored pair is not a consequence, and a row claiming one
	# would be a green gauge measuring nothing. The DEFAULT count is 1, so this only ever withholds the tag from an
	# explicitly zeroed count — never from a freshly stamped item id.
	if _txt(choice.get(&"give_item_id")) != "" and _num(choice.get(&"give_item_count")) > 0.0:
		tags.append(TAG_GIVE_ITEM)
	if _num(choice.get(&"give_money")) != 0.0:
		tags.append(TAG_GIVE_MONEY)
	# Reputation needs an id AND a non-zero delta (dialogue_manager.gd:375) — a faction with a 0 delta is inert.
	if _txt(choice.get(&"reward_reputation_faction_id")) != "" and _num(choice.get(&"reward_reputation")) != 0.0:
		tags.append(TAG_REWARD_REP)
	if _flag(choice.get(&"aggro_speaker")):
		tags.append(TAG_AGGRO)
	if tags.is_empty():
		return ""
	return SUMMARY_PREFIX + " ".join(tags)


# ──────────────────────────────────────────────────────────────────────────────────────────────────────────
# Variant readers — the duck-typed reads above go through these, never through a bare cast
# ──────────────────────────────────────────────────────────────────────────────────────────────────────────

## A duck-typed text field as a real String, "" for anything that is not text. TYPE-CHECKED FIRST on purpose:
## `Object.get()` hands back null for a property that does not exist, and `String(null)` stringifies to "<null>" —
## non-empty, so a bare String() cast would report a tag for a field the object does not even have.
static func _txt(v: Variant) -> String:
	if v is String or v is StringName:
		return String(v)
	return ""


## A duck-typed number as a float, 0.0 for anything that is not numeric. Same reason as _txt: `float(null)` is an
## invalid conversion, so the type test has to come before the cast.
static func _num(v: Variant) -> float:
	if v is float or v is int:
		return float(v)
	return 0.0


## A duck-typed bool. Variant TRUTHINESS, never `bool(v)`: Godot 4's bool() has constructors for bool/int/float
## ONLY, so `bool(<String>)` throws "Nonexistent 'bool' constructor" at runtime (the trap picker_rows.gd:171-174
## documents). An `if` coerces without a constructor, so a junk value degrades quietly instead of crashing the dock.
static func _flag(v: Variant) -> bool:
	if v:
		return true
	return false


## True when a duck-typed field holds a LIVE object reference (the `start_quest_on_choice != null` gate at
## dialogue_manager.gd:348). is_instance_valid is checked instead of `!= null` so a Resource freed mid-session
## reads as "nothing assigned" rather than tagging a reference the runtime would skip.
static func _is_ref(v: Variant) -> bool:
	return typeof(v) == TYPE_OBJECT and is_instance_valid(v)
