extends GutTest

## Unit tests for the PURE loot-edit ops (LootEditOps) behind the CYBER SUNDAY "Loot Edit" tab. Only the static,
## EditorInterface-free ops are exercised (add/remove/move/expected_drops/summary_text) — the tab UI is thin glue and
## is NOT instantiated here (no EditorInterface in a headless GUT run). Resources are built with .new() and released
## with `= null` per the RefCounted convention.

const Ops := preload("res://addons/cybersunday_tools/dock_loot/loot_edit_ops.gd")
const LootEditor := preload("res://addons/cybersunday_tools/dock_loot/loot_editor.gd")


func test_loot_editor_constructs_and_populates_item_pick_before_opening_a_table() -> void:
	# Regression: _init must scan items + populate the item picker BEFORE _reload_tables() opens the first table —
	# opening selects row 0 -> _load_row -> _select_item_in_pick -> _item_pick.select(), which on an UNpopulated
	# picker was an out-of-bounds engine error on every plugin load with a non-empty LootTable. Constructing the tab
	# exercises that exact path against the project's real loot tables; GUT 9.6 fails the test on the tracked error.
	var ed = LootEditor.new()
	assert_not_null(ed, "the Loot Edit tab constructs off-tree (no EditorInterface in _init)")
	assert_gte(ed._item_pick.item_count, 1, "the item picker holds at least the '(none)' row before any row is selected")
	ed.free()


func _make_entry(chance: float, lo: int, hi: int) -> LootEntry:
	var e := LootEntry.new()
	e.chance = chance
	e.min_count = lo
	e.max_count = hi
	return e


func test_add_entry_appends_valid_default_and_returns_index() -> void:
	var lt := LootTable.new()
	var idx := Ops.add_entry(lt)
	assert_eq(idx, 0, "first add returns index 0")
	assert_eq(lt.entries.size(), 1, "one entry appended")
	var e: LootEntry = lt.entries[0]
	assert_not_null(e, "the appended entry is a real LootEntry")
	assert_eq(e.chance, 1.0, "default chance is 1.0 (always drops once an item is picked)")
	assert_eq(e.min_count, 1, "default min_count 1")
	assert_eq(e.max_count, 1, "default max_count 1")
	assert_null(e.item, "no item assigned yet")
	lt = null


func test_add_entry_on_null_table_returns_minus_one() -> void:
	assert_eq(Ops.add_entry(null), -1, "add_entry(null) is a safe no-op returning -1")


func test_add_entry_returns_growing_indices() -> void:
	var lt := LootTable.new()
	assert_eq(Ops.add_entry(lt), 0, "1st add -> 0")
	assert_eq(Ops.add_entry(lt), 1, "2nd add -> 1")
	assert_eq(Ops.add_entry(lt), 2, "3rd add -> 2")
	assert_eq(lt.entries.size(), 3, "three entries total")
	lt = null


func test_remove_entry_removes_and_returns_true() -> void:
	var lt := LootTable.new()
	var a := _make_entry(0.5, 1, 1)
	var b := _make_entry(0.25, 2, 2)
	lt.entries = [a, b]
	assert_true(Ops.remove_entry(lt, 0), "removing a valid index returns true")
	assert_eq(lt.entries.size(), 1, "one entry left")
	assert_eq(lt.entries[0], b, "the remaining entry is the one we did not remove")
	lt = null
	a = null
	b = null


func test_remove_entry_out_of_range_is_noop() -> void:
	var lt := LootTable.new()
	lt.entries = [_make_entry(1.0, 1, 1)]
	assert_false(Ops.remove_entry(lt, 5), "out-of-range remove returns false")
	assert_false(Ops.remove_entry(lt, -1), "negative index remove returns false")
	assert_eq(lt.entries.size(), 1, "nothing removed")
	assert_false(Ops.remove_entry(null, 0), "remove on null table returns false")
	lt = null


func test_move_entry_down_swaps_and_returns_new_index() -> void:
	var lt := LootTable.new()
	var a := _make_entry(0.1, 1, 1)
	var b := _make_entry(0.2, 1, 1)
	var c := _make_entry(0.3, 1, 1)
	lt.entries = [a, b, c]
	var ni := Ops.move_entry(lt, 0, 1)  # move a down
	assert_eq(ni, 1, "moved-down entry's new index is 1")
	assert_eq(lt.entries[0], b, "b shifted up to slot 0")
	assert_eq(lt.entries[1], a, "a is now in slot 1")
	lt = null
	a = null
	b = null
	c = null


func test_move_entry_up_swaps_and_returns_new_index() -> void:
	var lt := LootTable.new()
	var a := _make_entry(0.1, 1, 1)
	var b := _make_entry(0.2, 1, 1)
	lt.entries = [a, b]
	var ni := Ops.move_entry(lt, 1, -1)  # move b up
	assert_eq(ni, 0, "moved-up entry's new index is 0")
	assert_eq(lt.entries[0], b, "b is now first")
	assert_eq(lt.entries[1], a, "a slid down")
	lt = null
	a = null
	b = null


func test_move_entry_at_edge_is_noop() -> void:
	var lt := LootTable.new()
	lt.entries = [_make_entry(1.0, 1, 1), _make_entry(1.0, 1, 1)]
	assert_eq(Ops.move_entry(lt, 0, -1), 0, "moving the top entry up returns the same index (no-op)")
	assert_eq(Ops.move_entry(lt, 1, 1), 1, "moving the bottom entry down returns the same index (no-op)")
	assert_eq(Ops.move_entry(lt, 0, 0), 0, "dir 0 is a no-op")
	assert_eq(Ops.move_entry(lt, 9, 1), 9, "out-of-range index returns itself unchanged")
	assert_eq(Ops.move_entry(null, 0, 1), 0, "null table returns the index unchanged")
	lt = null


func test_expected_drops_is_chance_times_average_count() -> void:
	var it := Item.new()
	var e := _make_entry(0.5, 2, 4)
	e.item = it
	# avg of [2,4] = 3, * 0.5 = 1.5
	assert_almost_eq(Ops.expected_drops(e), 1.5, 0.0001, "expected = chance * mean(min,max)")
	e = null
	it = null


func test_expected_drops_zero_without_item_or_chance() -> void:
	var no_item := _make_entry(1.0, 1, 1)
	assert_eq(Ops.expected_drops(no_item), 0.0, "no item -> drops nothing")
	var it := Item.new()
	var zero_chance := _make_entry(0.0, 1, 5)
	zero_chance.item = it
	assert_eq(Ops.expected_drops(zero_chance), 0.0, "zero chance -> drops nothing (matches roll's strict <)")
	assert_eq(Ops.expected_drops(null), 0.0, "null entry -> 0")
	no_item = null
	zero_chance = null
	it = null


func test_expected_drops_clamps_chance_and_count_like_roll() -> void:
	var it := Item.new()
	var e := _make_entry(1.0, 5, 2)  # max < min: roll clamps hi = max(lo,max) = 5
	e.item = it
	assert_almost_eq(Ops.expected_drops(e), 5.0, 0.0001, "max<min is clamped so the range is [5,5] = 5")
	var neg := _make_entry(1.0, -3, 3)  # min<0: roll clamps lo = max(0,min) = 0 -> mean(0,3)=1.5
	neg.item = it
	assert_almost_eq(Ops.expected_drops(neg), 1.5, 0.0001, "negative min is clamped to 0")
	e = null
	neg = null
	it = null


func test_summary_text_empty_and_null() -> void:
	var lt := LootTable.new()
	assert_string_contains(Ops.summary_text(lt), "Empty", "empty table summary mentions Empty")
	assert_string_contains(Ops.summary_text(null), "Empty", "null table summary is the empty line")
	lt = null


func test_summary_text_totals_and_flags_dead_rows() -> void:
	var it := Item.new()
	var lt := LootTable.new()
	var good := _make_entry(0.5, 2, 2)  # expected 1.0
	good.item = it
	var dead := _make_entry(1.0, 1, 1)  # no item -> 0, a dead row
	lt.entries = [good, dead]
	var s := Ops.summary_text(lt)
	assert_string_contains(s, "2 row", "summary reports the row count")
	assert_string_contains(s, "1.00", "summary reports ~1.00 expected per roll")
	assert_string_contains(s, "drop nothing", "summary flags the dead row")
	lt = null
	good = null
	dead = null
	it = null
