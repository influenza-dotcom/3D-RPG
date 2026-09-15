@tool
extends RefCounted

## Pure model for the Bark Edit tab: the category list a `BarkSet` exposes, and the two-way translation between
## an authored `Array[String]` of lines and the one-bark-per-line text a writer actually types.
##
## Why a separate module: every list mutation in this plugin lives in a `*_edit_ops.gd` of pure statics
## (`dock_loot/loot_edit_ops.gd`, `dock_quest/quest_edit_ops.gd`) so it can be exercised headless without an
## editor, a tree, or a widget. `tests/test_devtools_bark_editor.gd` drives everything here directly.
##
## NO class_name on purpose — const-preloaded by path from the dock, mirroring `content_save_guard.gd` /
## `core/picker_rows.gd`, so there is nothing for the global script class cache to miss.
##
## Every string here is a DEVELOPER surface (editor tooling) and must never be routed through `PlayerText`.

## The folder the tab scans. `BarkSet` resources have no registry — `ItemDb`-style autoloads are empty inside the
## editor anyway (see `core/item_scan.gd`) — so the dock walks this folder, same as every other content tab.
const BARK_DIR := "res://resources/barks"


## The ordered categories a `BarkSet` exposes, read from the RESOURCE ITSELF rather than a hand-kept list here.
## Returns `[{"name": "spot", "group": "Combat"}, ...]` in declaration order.
##
## Deriving beats duplicating: `scripts/npc/bark_set.gd` gained its "Music reactions" group after the first four,
## and a hand-copied list in the plugin would have silently stopped showing whatever was added last — the writer
## would never know the category existed. Walking `get_property_list()` means a new `@export var x: Array[String]`
## in `bark_set.gd` appears in this tab the next time the editor reloads, with no plugin edit at all.
## `tests/test_devtools_bark_editor.gd` pins that the walk finds every category the script declares.
##
## Godot emits an `@export_group("X")` as its own entry carrying `PROPERTY_USAGE_GROUP`; every property after it
## belongs to that group until the next one. Only typed `Array[String]` exports are taken, so a future non-bark
## field on `BarkSet` (a weight, a flag) is skipped instead of being rendered as a text box.
static func categories(res: Resource) -> Array:
	var out: Array = []
	if res == null:
		return out
	var group := ""
	for p in res.get_property_list():
		var usage: int = int(p.get("usage", 0))
		if usage & PROPERTY_USAGE_GROUP:
			group = String(p.get("name", ""))
			continue
		if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or not (usage & PROPERTY_USAGE_EDITOR):
			continue
		if int(p.get("type", TYPE_NIL)) != TYPE_ARRAY:
			continue
		# `hint_string` for a typed array is the element type: "4:" is String (TYPE_STRING == 4). An untyped
		# array, or an Array[int], is not a bark list and must not get a text box.
		if not String(p.get("hint_string", "")).begins_with("%d:" % TYPE_STRING):
			continue
		out.append({"name": String(p.get("name", "")), "group": group})
	return out


## One bark per line -> the authored array. Blank lines and trailing whitespace are dropped, because a writer
## working in a text box leaves both behind constantly and an empty string in the array is not "no bark" — the NPC
## would say nothing aloud while the category counted as filled, suppressing its built-in default lines.
##
## Returns a TYPED `Array[String]`. This matters: `BarkSet.spot` is `Array[String]`, and assigning an untyped
## Array to a typed export fails the assignment outright, so the save would silently write nothing.
static func lines_to_array(text: String) -> Array[String]:
	var out: Array[String] = []
	for raw in text.split("\n"):
		var line := String(raw).strip_edges()
		if line != "":
			out.append(line)
	return out


## The authored array -> one bark per line, for the text box. Inverse of `lines_to_array` for any array that has
## already been through it; an array authored in the Inspector that holds a blank or padded entry comes back
## normalised, which is the same cleanup the next Save would apply anyway.
static func array_to_lines(arr: Variant) -> String:
	if not (arr is Array):
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for v in (arr as Array):
		var line := String(v).strip_edges()
		if line != "":
			parts.append(line)
	return "\n".join(parts)


## True when `text` would change `arr` if saved. The dock's dirty flag keys on this rather than on a raw string
## compare, so re-typing the same lines with different spacing (or adding then deleting a blank line) does NOT
## mark the document dirty and pop an unsaved-changes guard the writer cannot explain.
static func differs(text: String, arr: Variant) -> bool:
	return lines_to_array(text) != lines_to_array(array_to_lines(arr))


## How many categories on `res` carry at least one line. The tab's headline number: a BarkSet reads as "empty" to
## a writer even when the file exists, because every category defaults to `[]` and an empty category means
## "fall back to the NPC's built-in lines" rather than "silence".
static func filled_count(res: Resource) -> int:
	var n := 0
	for c in categories(res):
		var arr = res.get(String(c.get("name", "")))
		if arr is Array and not (arr as Array).is_empty():
			n += 1
	return n


## Total authored lines across every category on `res`.
static func line_count(res: Resource) -> int:
	var n := 0
	for c in categories(res):
		var arr = res.get(String(c.get("name", "")))
		if arr is Array:
			n += (arr as Array).size()
	return n


## The post-save summary: "Saved raider_barks -- 14 lines across 5 categories." Pure so the wording is pinnable
## headless (the `save_report` idiom from `dock_text/text_editor.gd`).
static func save_report(file_name: String, lines: int, filled: int, backup: String) -> String:
	var msg := "Saved %s -- %s across %s." % [file_name, _count(lines, "line", "lines"), _count(filled, "category", "categories")]
	if backup != "":
		msg += " Previous version kept as %s." % backup
	return msg


## "1 line" / "3 lines" — a real singular/plural pair, never a hand-rolled "(s)".
static func _count(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]
