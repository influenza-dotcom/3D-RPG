@tool
extends RefCounted

## PURE static ops for the CYBER SUNDAY "Loot Edit" tab — mutate a LootTable's `entries` list and NOTHING else:
## no EditorInterface, no ResourceSaver, no scene-tree, no file I/O. The tab (loot_editor.gd) owns all the editor
## glue (scan the folder -> call an op here -> ResourceSaver.save -> update_file). Keeping these pure is what lets
## the GUT suite exercise them headless (an EditorInterface call would crash a headless test).
##
## Every op is BOUNDS-GUARDED and a no-op on a null table / out-of-range index, so the thin UI never has to
## pre-validate. add_entry appends a VALID, default LootEntry (chance 1.0, count 1..1) so a fresh row drops
## something the moment a designer picks an item. No `uid://` is ever hand-written — the tab's ResourceSaver.save
## mints the uid at runtime.


## Append a fresh, sensibly-seeded LootEntry (no item yet, chance 1.0, 1..1) and return its index, or -1 if the
## table is null. The new row is the last entry, so the UI can select it immediately.
static func add_entry(lt: LootTable) -> int:
	if lt == null:
		return -1
	var e := LootEntry.new()
	e.item = null
	e.chance = 1.0
	e.min_count = 1
	e.max_count = 1
	lt.entries.append(e)
	return lt.entries.size() - 1


## Remove the entry at `i`. No-op (returns false) on a null table or an out-of-range index. Returns true if a row
## was removed.
static func remove_entry(lt: LootTable, i: int) -> bool:
	if lt == null or i < 0 or i >= lt.entries.size():
		return false
	lt.entries.remove_at(i)
	return true


## Move the entry at `i` one slot in `dir` (dir < 0 = up/toward 0, dir > 0 = down). Returns the entry's NEW index,
## or the unchanged `i` if the move is a no-op (null table, bad index, or already at the end in that direction).
static func move_entry(lt: LootTable, i: int, dir: int) -> int:
	if lt == null or i < 0 or i >= lt.entries.size() or dir == 0:
		return i
	var j := i + (1 if dir > 0 else -1)
	if j < 0 or j >= lt.entries.size():
		return i  # already at an edge — nothing to swap with
	var tmp: LootEntry = lt.entries[i]
	lt.entries[i] = lt.entries[j]
	lt.entries[j] = tmp
	return j


## The EXPECTED count of `entry` per roll: chance * average count over the [min,max] range, matching LootTable.roll's
## clamping (lo = max(0,min), hi = max(lo,max)). 0.0 for a null entry / null item / zero chance. PURE — used for the
## tab's live "expected drops" summary without a Monte-Carlo.
static func expected_drops(entry: LootEntry) -> float:
	if entry == null or entry.item == null:
		return 0.0
	var c := clampf(entry.chance, 0.0, 1.0)
	if c <= 0.0:
		return 0.0
	var lo := maxi(0, entry.min_count)
	var hi := maxi(lo, entry.max_count)
	var avg := (float(lo) + float(hi)) * 0.5
	return c * avg


## A one-line, designer-readable summary of the whole table's expected yield (sum of expected_drops over every row,
## plus a flag for rows that drop nothing). PURE. Empty / null -> a friendly "nothing" line.
## Real plurals, never a hand-rolled "(s)" — this line sits under the row list where the tab's own status prose
## ("3 rows", "1 item") is one glance away, and the two must not read as if different people wrote them.
static func summary_text(lt: LootTable) -> String:
	if lt == null or lt.entries.is_empty():
		return "Empty table -- drops nothing."
	var total := 0.0
	var dead := 0
	for e in lt.entries:
		var ex := expected_drops(e)
		total += ex
		if ex <= 0.0:
			dead += 1
	var tail := "" if dead == 0 else "  (%s %s nothing)" % [_plural(dead, "row"), "drops" if dead == 1 else "drop"]
	var yield_noun := "item" if is_equal_approx(total, 1.0) else "items"
	return "%s -- about %.2f %s expected per roll.%s" % [_plural(lt.entries.size(), "row"), total, yield_noun, tail]


## "1 row" / "3 rows" — the count wording shared by this summary and the tab's status lines. Editor tooling prose,
## never PlayerText (which is the player-facing surface; this string only ever reaches the designer's panel).
static func _plural(n: int, noun: String) -> String:
	return "%d %s%s" % [n, noun, "" if n == 1 else "s"]
