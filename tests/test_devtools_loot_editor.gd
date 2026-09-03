extends GutTest

## Tests for the CYBER SUNDAY "Loot Edit" tab: the PURE loot-edit ops (LootEditOps: add/remove/move/expected_drops/
## summary_text) plus the tab's own headless-safe structure — it constructs BARE (.new(), no tree, no EditorInterface),
## its layout contract (top bar + one status Label outside a ScrollContainer, everything else inside), the host
## handoff `select_path` refusing off-tree, and the dirty flag / "Save Loot Table*" rendering. Resources are built
## with .new() and released with `= null` per the RefCounted convention; the tab is .new() + .free().

const Ops := preload("res://addons/cybersunday_tools/dock_loot/loot_edit_ops.gd")
const LootEditor := preload("res://addons/cybersunday_tools/dock_loot/loot_editor.gd")

const SAMPLE_TABLE := "res://resources/loot/sample_loot.tres"


func test_loot_editor_constructs_bare_with_the_layout_contract() -> void:
	# The tab used to be the tallest in the panel (no ScrollContainer). The contract now: a fixed top bar (picker +
	# Refresh + Save Loot Table) and ONE status Label outside a ScrollContainer, every growing widget inside it, no
	# heading Label repeating the tab name, both dropdowns width-guarded, and no floor above 120 px anywhere.
	var ed = LootEditor.new()
	assert_eq(ed.name, "Loot Edit", "the Control name is the panel's routing key and stays 'Loot Edit'")
	assert_eq(ed.get_child_count(), 3, "exactly top bar + status + scroll sit outside the scroll (no heading Label)")
	assert_true(ed._scroll is ScrollContainer, "the third direct child is the ScrollContainer")
	assert_eq(ed._scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED, "the scroll never scrolls sideways (widgets fill the width)")
	assert_lte(ed._scroll.custom_minimum_size.y, 120.0, "the scroll floor stays within the 90..120 px band")
	assert_gte(ed._scroll.custom_minimum_size.y, 90.0, "the scroll floor stays within the 90..120 px band")
	for w in [ed._entry_list, ed._row_box, ed._summary, ed._item_pick, ed._chance, ed._min_count, ed._max_count]:
		assert_true(ed._scroll.is_ancestor_of(w), "%s lives INSIDE the scroll" % w.get_class())
	for w in [ed._table_pick, ed._refresh_btn, ed._save_btn, ed._status]:
		assert_false(ed._scroll.is_ancestor_of(w), "%s stays OUTSIDE the scroll (always visible)" % w.get_class())
	assert_eq(ed._status.max_lines_visible, 2, "the status shows at most two lines")
	assert_eq(ed._status.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "the status wraps by word")
	assert_eq(ed._status.tooltip_text, ed._status.text, "the status tooltip mirrors the full text from the first write")
	assert_false(ed._table_pick.fit_to_longest_item, "the table picker never widens to its longest filename")
	assert_true(ed._table_pick.clip_text, "the table picker clips its own text")
	assert_false(ed._item_pick.fit_to_longest_item, "the item picker never widens to its longest label")
	assert_true(ed._item_pick.clip_text, "the item picker clips its own text")
	assert_lte(_max_floor(ed), 120.0, "no widget in the tab declares a custom_minimum_size taller than 120 px")
	assert_eq(ed._save_btn.text, "Save Loot Table", "the Save button uses the 'Save <Thing>' verb")
	assert_true(ed._save_btn.disabled, "Save is greyed until a table is open")
	assert_eq(ed._save_btn.tooltip_text, "Pick a loot table first.", "the greyed Save names what is missing")
	assert_true(ed._add_btn.disabled, "Add is greyed until a table is open")
	assert_true(ed._remove_btn.disabled and ed._up_btn.disabled and ed._down_btn.disabled, "row buttons are greyed until a row is picked")
	assert_ne(ed._refresh_btn.tooltip_text, "", "Refresh carries a tooltip")
	assert_eq(ed._chance.tooltip_text, "Chance this row drops, 0 to 1 (0.35 = 35 %)", "the Chance tooltip explains the 0..1 scale in designer words")
	assert_ne(ed._min_count.tooltip_text, "", "Min carries a tooltip")
	assert_ne(ed._max_count.tooltip_text, "", "Max carries a tooltip")
	ed.free()


## The tallest custom_minimum_size.y declared anywhere under `n` (the rule 4 height guard).
func _max_floor(n: Node) -> float:
	var worst := 0.0
	if n is Control:
		worst = (n as Control).custom_minimum_size.y
	for c in n.get_children():
		worst = maxf(worst, _max_floor(c))
	return worst


func test_select_path_off_tree_refuses_without_scanning() -> void:
	# The host handoff needs the tab IN the tree (a host to be found, a viewport for the unsaved-changes dialog). A
	# bare tab returns false and does nothing, so the panel falls back to the Inspector instead of half-opening.
	var ed = LootEditor.new()
	assert_false(ed.select_path(SAMPLE_TABLE), "off-tree (no host) select_path returns false")
	assert_false(ed._revealed, "a refused handoff does not latch the first-reveal scan")
	assert_null(ed._table, "a refused handoff opens nothing")
	assert_eq(ed._item_pick.item_count, 0, "a refused handoff does not scan the items either")
	assert_eq(ed._table_pick.item_count, 0, "a refused handoff does not scan the tables either")
	assert_false(ed.select_path(""), "a blank path is refused")
	ed.free()


func test_scan_tables_report_finds_the_sample_table_and_reports_skips() -> void:
	var rep := LootEditor.scan_tables_report()
	assert_true(rep.has("paths") and rep.has("skipped"), "the report carries both the found paths and the skipped files")
	var paths: Array[String] = rep["paths"]
	assert_true(paths.has(SAMPLE_TABLE), "the sample loot table is discovered under resources/")
	var sorted := paths.duplicate()
	sorted.sort()
	assert_eq(paths, sorted, "paths come back sorted so the picker order is stable")
	assert_eq(LootEditor._scan_loot_tables(), paths, "the plain static list is the report's path list")
	var skipped: PackedStringArray = rep["skipped"]
	for p in skipped:
		assert_false(paths.has(p), "a skipped file is never also listed as a table: %s" % p)


func test_dirty_flag_follows_every_edit_and_renders_on_save_button_and_status() -> void:
	# Rule 10: every write-through handler and every add/remove/move sets _dirty; a load clears it. It renders as a
	# '*' on the Save button and '(unsaved changes)' in the status. Driven bare with an in-memory table (no disk).
	var ed = LootEditor.new()
	var lt := LootTable.new()
	ed._table = lt
	ed._update_buttons()
	assert_false(ed._dirty, "a freshly assigned table starts clean")
	assert_false(ed._save_btn.disabled, "Save is enabled once a table is open")
	assert_eq(ed._save_btn.text, "Save Loot Table", "no star while clean")

	ed._on_add()
	assert_eq(lt.entries.size(), 1, "Add appended a row through the pure op")
	assert_true(ed._dirty, "Add marks the table dirty")
	assert_eq(ed._save_btn.text, "Save Loot Table*", "the dirty Save button carries a '*' suffix")
	assert_true(ed._status.text.ends_with("(unsaved changes)"), "the dirty status ends with '(unsaved changes)'")
	assert_eq(ed._status.tooltip_text, ed._status.text, "the status tooltip mirrors the text after a dirty write")
	assert_eq(ed._selected_row(), 0, "the new row is picked for editing")
	assert_false(ed._remove_btn.disabled, "Remove is enabled once a row is picked")
	assert_eq(int(ed._min_count.value), 1, "the row editor was PUSHED from the new entry (min 1)")
	assert_eq(int(ed._max_count.value), 1, "the row editor was PUSHED from the new entry (max 1)")

	# Widget -> model write-through: raising Min above Max raises Max to Min and says so.
	# NOTE an engine fact this test has to work around: an OFF-TREE Range (SpinBox / slider) does NOT emit
	# `value_changed` when `.value` is assigned -- verified in Godot 4.7 with a bare SpinBox and a bare HSlider.
	# GUT builds every tab off-tree, so setting the widget alone would drive nothing. Push the widget, then call
	# the write handler the signal calls in the editor; that is exactly the pair a designer's edit produces.
	ed._min_count.set_value_no_signal(3)
	ed._on_counts_changed()
	var e: LootEntry = lt.entries[0]
	assert_eq(e.min_count, 3, "Min wrote through to the entry")
	assert_eq(e.max_count, 3, "Max was raised to Min so no max < min reaches disk")
	assert_eq(int(ed._max_count.value), 3, "the Max SpinBox shows the raised value")
	assert_true(ed._status.text.begins_with("Raised Max to 3"), "the status says Max was raised: %s" % ed._status.text)
	assert_true(ed._status.text.contains("(unsaved changes)"), "the dirty suffix is appended once, never stacked")
	assert_eq(ed._status.text.count("(unsaved changes)"), 1, "the dirty suffix appears exactly once")

	# Item picker anti-clobber: a stale index KEEPS the item, index 0 (the "(none)" row) is the one intended clear.
	# The row is given a real item first -- a fresh row's item is already null, so "it ended up null" would otherwise
	# pass no matter which branch ran.
	var it := Item.new()
	e.item = it
	ed._clear_dirty()
	ed._on_item_selected(99)
	assert_eq(e.item, it, "an out-of-range pick keeps the assigned item")
	assert_false(ed._dirty, "an out-of-range pick is refused and does not dirty the table")
	ed._on_item_selected(0)
	assert_null(e.item, "index 0 is the one intended clear")
	assert_true(ed._dirty, "clearing the item is an edit")

	# Saving a table with no file on disk refuses in plain words and stays dirty (nothing was written).
	ed._on_save()
	assert_true(ed._dirty, "a refused save leaves the table dirty")
	assert_true(ed._status.text.begins_with("Couldn't save"), "a refused save uses the \"Couldn't <verb>\" grammar: %s" % ed._status.text)

	# Off-tree there is no viewport for the dialog: a guarded switch refuses instead of dropping the edits.
	var tables: Array[String] = [SAMPLE_TABLE]
	ed._tables = tables
	ed._on_table_selected(0)
	assert_eq(ed._table, lt, "a dirty table is kept open when the guard cannot ask")
	assert_true(ed._status.text.begins_with("Couldn't switch tables"), "the refused switch says why: %s" % ed._status.text)

	# Move / Remove are edits too; removing the last row greys the row editor and points at Add.
	ed._on_add()
	ed._clear_dirty()
	ed._on_move(-1)
	assert_true(ed._dirty, "moving a row up is an edit")
	ed._clear_dirty()
	ed._on_remove()
	ed._on_remove()
	assert_eq(lt.entries.size(), 0, "both rows removed")
	assert_true(ed._dirty, "removing a row is an edit")
	assert_true(ed._status.text.contains("Press Add to create the first row."), "an emptied table points at Add: %s" % ed._status.text)
	assert_true(ed._remove_btn.disabled, "Remove is greyed again with no row to pick")

	# A load (here: a failed one) clears the flag, nulls the table and greys Save.
	ed._clear_loaded()
	assert_false(ed._dirty, "clearing the open table clears the dirty flag")
	assert_null(ed._table, "the open table is nulled")
	assert_eq(ed._save_btn.text, "Save Loot Table", "the star is gone")
	assert_true(ed._save_btn.disabled, "Save is greyed with nothing open")
	assert_eq(int(ed._min_count.value), 1, "the row editor RESET to the LootEntry default (min 1, not 0)")
	assert_eq(ed._chance.value, 1.0, "the row editor RESET to the LootEntry default (chance 1.0, not 0)")
	ed.free()
	lt = null
	e = null
	it = null


func test_editing_counts_never_rewrites_an_off_grid_chance() -> void:
	# Regression (data safety): Chance and the counts sit on SEPARATE write handlers. A Range SNAPS whatever it is
	# handed to its `step` -- on the way IN too, `set_value_no_signal` included -- so the single shared handler this
	# replaced re-derived `chance` from the widget on EVERY count edit: an authored 0.005 was displayed rounded and
	# then written back rounded by an edit that only ever touched Min.
	var ed = LootEditor.new()
	var lt := LootTable.new()
	ed._table = lt
	ed._on_add()
	var e: LootEntry = lt.entries[0]
	e.chance = 0.005
	ed._load_row(e)  # PUSH site: the widget rounds to its 0.01 step, the entry keeps the authored value
	assert_almost_eq(e.chance, 0.005, 0.0001, "pushing a row into the widgets must never write back to the entry")
	assert_ne(ed._chance.value, 0.005, "the SpinBox really cannot show this value -- that is the trap being pinned")

	ed._min_count.set_value_no_signal(2)  # off-tree a Range does not emit value_changed on assignment (Godot 4.7),
	ed._on_counts_changed()               # so call the handler its signal calls in the editor
	assert_eq(e.min_count, 2, "the count edit wrote through")
	assert_almost_eq(e.chance, 0.005, 0.0001, "a count edit leaves the authored chance exactly as it was")

	ed._chance.set_value_no_signal(0.25)  # dialing Chance itself DOES write, and writes what the designer picked
	ed._on_chance_changed()
	assert_almost_eq(e.chance, 0.25, 0.0001, "the Chance handler writes the picked value")
	assert_eq(e.min_count, 2, "and leaves the counts alone")
	ed.free()
	lt = null
	e = null


func test_table_picker_shows_an_open_file_that_vanished_as_a_disabled_row() -> void:
	# The picker's rows are indexes INTO _tables, so they are rebuilt in the same breath as every rescan. When the
	# rescan no longer finds the OPEN table (deleted / renamed mid-edit) the picker must not read as some OTHER
	# table: a disabled trailing row stands for the missing file, and _table_pick_idx remembers it as the row a
	# cancelled unsaved-changes dialog restores.
	var ed = LootEditor.new()
	var tables: Array[String] = [SAMPLE_TABLE]
	ed._tables = tables
	ed._fill_table_pick("res://resources/loot/deleted_table.tres")
	assert_eq(ed._table_pick.item_count, 2, "the one scanned table plus a row for the vanished file")
	assert_eq(ed._table_pick.selected, 1, "the picker points at the vanished file, never at the other table")
	assert_eq(ed._table_pick_idx, 1, "the cancelled-switch restore index is that same row")
	assert_true(ed._table_pick.is_item_disabled(1), "the vanished row is informational and cannot be picked")

	ed._fill_table_pick(SAMPLE_TABLE)
	assert_eq(ed._table_pick.item_count, 1, "a table that IS on disk needs no transient row")
	assert_eq(ed._table_pick_idx, 0, "and the restore index follows it")

	ed._fill_table_pick("")
	assert_eq(ed._table_pick.selected, -1, "nothing open must READ as nothing, not as row 0")
	assert_eq(ed._table_pick_idx, -1, "with no row to restore")
	ed.free()


func test_loot_editor_populates_item_pick_on_first_reveal_before_opening_a_table() -> void:
	# Regression: first reveal must scan items + populate the item picker BEFORE _reload_tables() opens the first
	# table. Opening selects row 0 -> _load_row -> _sync_item_pick -> PickerRows.apply, which needs the scanned
	# _item_paths/_item_labels ready or every item renders as an off-scan transient row (and, before PickerRows,
	# select() on an UNpopulated picker was an out-of-bounds engine error). Construct off-tree, then mount and reveal.
	var ed = LootEditor.new()
	assert_not_null(ed, "the Loot Edit tab constructs off-tree (no EditorInterface in _init)")
	assert_eq(ed._item_pick.item_count, 0, "item scanning is lazy before the tab enters the tree")
	add_child_autofree(ed)
	ed._on_visibility_changed()
	assert_true(ed._revealed, "the in-tree visibility pass latches the first reveal")
	assert_gte(ed._item_pick.item_count, 1, "the item picker holds at least the '(none)' row before any row is selected")


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
	assert_true(Ops.summary_text(lt).contains("Empty"), "empty table summary mentions Empty")
	assert_true(Ops.summary_text(null).contains("Empty"), "null table summary is the empty line")
	lt = null


func test_summary_text_totals_and_flags_dead_rows() -> void:
	var it := Item.new()
	var lt := LootTable.new()
	var good := _make_entry(0.5, 2, 2)  # expected 1.0
	good.item = it
	var dead := _make_entry(1.0, 1, 1)  # no item -> 0, a dead row
	lt.entries = [good, dead]
	var s := Ops.summary_text(lt)
	assert_true(s.contains("2 rows"), "summary reports the row count: %s" % s)
	assert_true(s.contains("1.00"), "summary reports ~1.00 expected per roll: %s" % s)
	assert_true(s.contains("1 row drops nothing"), "summary flags the dead row in real words: %s" % s)
	assert_false(s.contains("(s)"), "the readout uses real plurals, never a hand-rolled '(s)': %s" % s)
	lt = null
	good = null
	dead = null
	it = null
