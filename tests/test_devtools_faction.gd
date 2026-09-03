extends GutTest

## Faction-matrix dock: PURE round-trip on the relation helpers, a construct smoke test, and the WRITE CONTRACT --
## a cell change stages the relation on the in-memory Faction and marks it dirty; NOTHING reaches disk until Save
## Factions, which writes through ContentSaveGuard (prior bytes -> <file>.bak). Instantiating the dock forces
## GDScript to compile the WHOLE script (catching errors --import misses for addon-only scripts). The grid is built
## OFF-TREE from temp factions saved under user:// (never the project's real factions folder) via _build_grid, so
## the disk assertions are against throwaway files and no EditorInterface call is ever reached.

const FactionMatrix := preload("res://addons/cybersunday_tools/dock_faction/faction_matrix.gd")

const TMP_A := "user://test_faction_matrix_a.tres"
const TMP_B := "user://test_faction_matrix_b.tres"


func after_each() -> void:
	for f in [TMP_A, TMP_A + ".bak", TMP_B, TMP_B + ".bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)


func _faction(id: String) -> Faction:
	var f := Faction.new()
	f.id = StringName(id)
	f.display_name = id.capitalize()
	return f


## A faction written to a temp file and registered under that path (take_over_path, so a stale cache entry from an
## earlier run can never make the setter error) -- the shape the dock sees for a faction loaded from disk.
## `relations` seeds the file's authored relations; the default {} is OMITTED from the .tres (it equals the script
## default), which is exactly the case the Discard test below pins.
func _saved_faction(id: String, path: String, relations: Dictionary = {}) -> Faction:
	var f := _faction(id)
	f.relations = relations
	f.take_over_path(path)
	assert_eq(ResourceSaver.save(f, path), OK, "temp faction %s should write" % path)
	return f


## Untyped on purpose: the tests poke the dock's private members, which a Node-typed handle would flag.
func _grid_with(a: Faction, b: Faction):
	var d = FactionMatrix.new()
	var list: Array[Faction] = [a, b]
	d._build_grid(list)
	return d


# --- construct + idle state ----------------------------------------------------------------------------------------

func test_faction_dock_constructs() -> void:
	var d = FactionMatrix.new()
	assert_not_null(d, "faction dock should construct (compiles + builds its UI off-tree)")
	assert_eq(d.name, "Factions", "dock tab name")
	assert_eq(d._save_btn.text, "Save Factions", "Save carries no count while nothing has changed")
	assert_true(d._save_btn.disabled, "Save is greyed while nothing has changed")
	assert_eq(d._save_btn.tooltip_text, FactionMatrix.SAVE_TIP_CLEAN, "a greyed Save names what is missing")
	assert_true(d._restore_btn.disabled, "Restore is greyed before any backup exists")
	assert_eq(d._restore_btn.tooltip_text, FactionMatrix.RESTORE_TIP_NONE, "a greyed Restore says no backup exists yet")
	assert_eq(d._status.text, FactionMatrix.MSG_IDLE, "the idle status explains the grid (and where Disposition lives)")
	assert_eq(d._status.tooltip_text, d._status.text, "the status tooltip mirrors the full text")
	assert_eq(d._status.max_lines_visible, 2, "the status clamps to two lines")
	d.free()


func test_build_grid_from_in_memory_factions() -> void:
	var a := _faction("raiders")
	var b := _faction("townsfolk")
	var d = _grid_with(a, b)
	assert_eq(d._grid.columns, 3, "N factions -> N + 1 grid columns (row label + one per faction)")
	assert_eq(d._grid.get_child_count(), 9, "header row + 2 body rows of 3 cells each")
	assert_eq(d._cells.size(), 2, "only the two off-diagonal cells are editable")
	var cell: OptionButton = d._cells[Vector2i(0, 1)]
	assert_eq(cell.tooltip_text, "How Raiders NPCs treat Townsfolk NPCs", "a cell tooltip names from and to in designer words")
	assert_false(cell.fit_to_longest_item, "cells drop the fit-to-longest-item width guard")
	assert_true(cell.clip_text, "cells clip their caption instead of widening the grid")
	assert_eq(cell.selected, 1, "an unlisted relation shows Neutral")
	assert_eq(d._dirty_count(), 0, "a fresh grid has nothing dirty")
	d.free()
	a = null
	b = null


# --- the write contract: stage on edit, write on Save ------------------------------------------------------------

func test_cell_change_stages_in_memory_and_does_not_write_until_save() -> void:
	var a := _saved_faction("raiders", TMP_A)
	var b := _saved_faction("townsfolk", TMP_B)
	var d = _grid_with(a, b)

	d._on_cell_selected(0, 0, 1)  # Raiders -> Townsfolk = Enemy

	assert_eq(FactionMatrix.get_relation(a, b), -1.0, "the in-memory faction takes the edit at once")
	assert_false(FileAccess.get_file_as_string(TMP_A).contains("townsfolk"), "the file is untouched before Save")
	assert_false(FileAccess.file_exists(TMP_A + ".bak"), "no backup is made before Save")
	assert_eq(d._dirty_count(), 1, "one faction is dirty")
	assert_eq(d._save_btn.text, "Save Factions (1)", "Save counts the dirty factions")
	assert_false(d._save_btn.disabled, "Save is live once something changed")
	assert_true(d._status.text.ends_with("(unsaved changes)"), "the status carries the unsaved suffix")
	var cell: OptionButton = d._cells[Vector2i(0, 1)]
	assert_eq(cell.modulate, FactionMatrix.DIRTY_COLOR, "the changed cell is tinted")
	assert_true(d._restore_btn.disabled, "Restore is greyed while edits are unsaved (a restore would drop them)")
	assert_eq(d._restore_btn.tooltip_text, FactionMatrix.RESTORE_TIP_DIRTY, "the greyed Restore says to save or discard first")

	d._on_save()

	assert_true(FileAccess.get_file_as_string(TMP_A).contains("townsfolk"), "Save writes the relation into the file")
	assert_true(FileAccess.file_exists(TMP_A + ".bak"), "Save keeps the previous bytes beside the file as .bak")
	assert_false(FileAccess.get_file_as_string(TMP_A + ".bak").contains("townsfolk"), "the .bak holds the PRE-save bytes")
	assert_false(FileAccess.file_exists(TMP_B + ".bak"), "an unchanged faction is not rewritten (no .bak for it)")
	assert_eq(d._dirty_count(), 0, "everything is clean after a successful save")
	assert_eq(d._save_btn.text, "Save Factions", "the count leaves the Save button")
	assert_true(d._save_btn.disabled, "Save greys again with nothing left to write")
	assert_eq(cell.modulate, Color.WHITE, "the saved cell loses its tint")
	assert_eq(cell.get_meta("loaded_bucket"), 0, "the cell's loaded value is now what was written")
	assert_true(d._status.text.begins_with("Saved test_faction_matrix_a.tres --"), "the status names the file written: %s" % d._status.text)
	assert_false(d._status.text.ends_with("(unsaved changes)"), "the unsaved suffix is gone after Save")
	assert_false(d._restore_btn.disabled, "Restore is live now that a backup exists")
	assert_eq(d._restore_btn.tooltip_text, FactionMatrix.RESTORE_TIP, "the live Restore tooltip says it writes")

	d.free()
	a = null
	b = null


func test_cell_changed_back_to_the_file_value_is_clean_again() -> void:
	var a := _faction("raiders")
	var b := _faction("townsfolk")
	var d = _grid_with(a, b)
	d._on_cell_selected(2, 0, 1)  # Ally
	assert_eq(d._dirty_count(), 1, "changed away from Neutral -> dirty")
	d._on_cell_selected(1, 0, 1)  # back to Neutral (what the grid loaded)
	assert_eq(d._dirty_count(), 0, "changed back to the loaded value -> clean, nothing to write")
	assert_eq(d._save_btn.text, "Save Factions", "no count once the cell matches the file again")
	var cell: OptionButton = d._cells[Vector2i(0, 1)]
	assert_eq(cell.modulate, Color.WHITE, "the tint clears when the cell is back on its file value")
	d.free()
	a = null
	b = null


func test_two_cells_in_one_row_count_as_one_file() -> void:
	var a := _faction("raiders")
	var b := _faction("townsfolk")
	var c := _faction("wildlife")
	var d = FactionMatrix.new()
	var list: Array[Faction] = [a, b, c]
	d._build_grid(list)
	d._on_cell_selected(0, 0, 1)
	d._on_cell_selected(2, 0, 2)
	assert_eq(d._dirty_cells.size(), 2, "two cells are dirty")
	assert_eq(d._dirty_count(), 1, "both cells belong to one faction -> one file to write")
	assert_eq(d._save_btn.text, "Save Factions (1)", "Save counts files, not cells")
	d._on_cell_selected(0, 1, 0)
	assert_eq(d._dirty_count(), 2, "a cell in a second row adds a second file")
	assert_eq(d._dirty_names_text(), "raiders, townsfolk", "the Refresh dialog names the dirty factions (id when there is no file)")
	d.free()
	a = null
	b = null
	c = null


func test_save_with_no_file_reports_a_failure_and_stays_dirty() -> void:
	var a := _faction("raiders")  # in memory only: no resource_path
	var b := _faction("townsfolk")
	var d = _grid_with(a, b)
	d._on_cell_selected(0, 0, 1)
	d._on_save()
	assert_eq(d._dirty_count(), 1, "a faction that couldn't be written stays dirty for a retry")
	assert_true(d._status.text.begins_with("Couldn't save Raiders:"), "the failure names the faction: %s" % d._status.text)
	d.free()
	a = null
	b = null


# --- discard + restore ---------------------------------------------------------------------------------------------

func test_discard_puts_the_files_relation_back_into_the_same_faction() -> void:
	var a := _saved_faction("raiders", TMP_A, {StringName("townsfolk"): 1.0})  # the file says Ally
	var b := _saved_faction("townsfolk", TMP_B)
	var d = _grid_with(a, b)
	var cell: OptionButton = d._cells[Vector2i(0, 1)]
	assert_eq(cell.selected, 2, "precondition: the grid loaded the file's Ally")
	d._on_cell_selected(0, 0, 1)  # staged: Enemy
	assert_eq(FactionMatrix.get_relation(a, b), -1.0, "the edit is staged on the cached faction")
	var dropped: PackedStringArray = d._discard_changes()
	assert_eq(dropped, PackedStringArray(["test_faction_matrix_a.tres"]), "Discard names the file it re-read")
	assert_eq(FactionMatrix.get_relation(a, b), 1.0, "Discard puts the file's relation back INTO the same faction object")
	assert_eq(d._dirty_count(), 0, "nothing is dirty after Discard")
	d.free()
	a = null
	b = null


func test_discard_clears_a_relation_the_file_never_had() -> void:
	# The trap: a .tres omits `relations` when it is the default {}, and an in-place re-read only assigns what it
	# finds -- so without the reset-then-reload order in _reread_relations the staged Enemy would survive its own
	# discard. This pins that the relation is gone afterwards.
	var a := _saved_faction("raiders", TMP_A)  # no relations line in the file
	var b := _saved_faction("townsfolk", TMP_B)
	var d = _grid_with(a, b)
	d._on_cell_selected(0, 0, 1)  # staged: Enemy
	assert_true(a.relations.has(StringName("townsfolk")), "precondition: the edit is staged")
	d._discard_changes()
	assert_false(a.relations.has(StringName("townsfolk")), "a relation the file never had is cleared by Discard")
	assert_eq(d._dirty_count(), 0, "nothing is dirty after Discard")
	d.free()
	a = null
	b = null


func test_restore_refuses_when_no_backup_exists() -> void:
	var a := _saved_faction("raiders", TMP_A)
	var b := _saved_faction("townsfolk", TMP_B)
	var d = _grid_with(a, b)
	d._on_restore_pressed()
	assert_eq(d._status.text, FactionMatrix.MSG_NO_BACKUP, "no .bak anywhere -> refused with 'No backup exists yet'")
	assert_true(d._status.text.contains("No backup exists yet"), "the refusal carries the literal reason")
	assert_false(FileAccess.get_file_as_string(TMP_A).is_empty(), "the file is left alone")
	d.free()
	a = null
	b = null


func test_restore_refuses_while_edits_are_unsaved() -> void:
	var a := _saved_faction("raiders", TMP_A)
	var b := _saved_faction("townsfolk", TMP_B)
	var d = _grid_with(a, b)
	d._on_cell_selected(0, 0, 1)
	d._on_restore_pressed()
	assert_true(d._status.text.begins_with(FactionMatrix.MSG_RESTORE_DIRTY), "unsaved edits -> Restore refuses rather than dropping them")
	assert_eq(d._dirty_count(), 1, "the staged edit survives the refusal")
	d.free()
	a = null
	b = null


func test_restore_backups_copies_the_bak_back_over_the_file() -> void:
	var a := _saved_faction("raiders", TMP_A)
	var b := _saved_faction("townsfolk", TMP_B)
	var d = _grid_with(a, b)
	d._on_cell_selected(0, 0, 1)
	d._on_save()  # TMP_A now holds the Enemy relation; TMP_A.bak holds the pre-save bytes
	assert_true(FileAccess.get_file_as_string(TMP_A).contains("townsfolk"), "precondition: the save landed")
	var list: Array[Faction] = [a, b]
	var rep: Dictionary = FactionMatrix.restore_backups(list)
	var restored: PackedStringArray = rep["restored"]
	var failures: PackedStringArray = rep["failures"]
	assert_eq(restored, PackedStringArray(["test_faction_matrix_a.tres"]), "only the faction WITH a .bak is restored")
	assert_true(failures.is_empty(), "no failures on a plain copy-back")
	assert_false(FileAccess.get_file_as_string(TMP_A).contains("townsfolk"), "the file holds the backup's bytes again")
	assert_true(FileAccess.file_exists(TMP_A + ".bak"), "the .bak is kept (copied, not moved)")
	assert_false(a.relations.has(StringName("townsfolk")), "the restored file is re-read INTO the cached faction")
	d.free()
	a = null
	b = null


# --- pure report lines ---------------------------------------------------------------------------------------------

func test_scan_report_names_skipped_files() -> void:
	assert_eq(FactionMatrix.scan_report(3, PackedStringArray()), "Loaded 3 factions.", "clean scan")
	assert_eq(FactionMatrix.scan_report(1, PackedStringArray()), "Loaded 1 faction.", "singular")
	assert_eq(FactionMatrix.scan_report(2, PackedStringArray(["bad_one", "other"])),
		"Loaded 2 factions; skipped: bad_one, other -- those files didn't load as factions.", "skipped files are named")


func test_save_report_wording() -> void:
	assert_eq(FactionMatrix.save_report(PackedStringArray(["raiders.tres"]), PackedStringArray()),
		"Saved raiders.tres -- the previous version is kept beside it as raiders.tres.bak.", "one file")
	assert_eq(FactionMatrix.save_report(PackedStringArray(["a.tres", "b.tres"]), PackedStringArray()),
		"Saved 2 factions: a.tres, b.tres -- the previous version of each is kept beside it as a .bak file.", "many files")
	assert_eq(FactionMatrix.save_report(PackedStringArray(), PackedStringArray(["x.tres: File not found"])),
		"Couldn't save x.tres: File not found.", "a failure row carries the plain reason")
	assert_eq(FactionMatrix.restore_report(PackedStringArray(["raiders.tres"]), PackedStringArray()),
		"Restored raiders.tres from its last backup -- the grid shows the files again.", "one restore")


# --- pure relation helpers -----------------------------------------------------------------------------------------

func test_set_relation_round_trips_enemy() -> void:
	var a := _faction("raiders")
	var b := _faction("townsfolk")
	FactionMatrix.set_relation(a, b, -1.0)
	assert_eq(FactionMatrix.get_relation(a, b), -1.0, "enemy relation reads back")
	# The relation is stored under b.id, matching Faction.relation_to.
	assert_eq(a.relation_to(StringName("townsfolk")), -1.0, "stored under the other faction's id")
	a = null
	b = null


func test_set_relation_round_trips_ally() -> void:
	var a := _faction("raiders")
	var b := _faction("ncr")
	FactionMatrix.set_relation(a, b, 1.0)
	assert_eq(FactionMatrix.get_relation(a, b), 1.0, "ally relation reads back")
	a = null
	b = null


func test_neutral_clears_the_entry() -> void:
	var a := _faction("raiders")
	var b := _faction("townsfolk")
	FactionMatrix.set_relation(a, b, -1.0)
	assert_true(a.relations.has(StringName("townsfolk")), "non-neutral relation is stored")
	FactionMatrix.set_relation(a, b, 0.0)
	assert_false(a.relations.has(StringName("townsfolk")), "neutral (0.0) clears the entry, keeping the file clean")
	assert_eq(FactionMatrix.get_relation(a, b), 0.0, "neutral reads back as 0.0 (relation_to default)")
	a = null
	b = null


func test_set_relation_is_directional() -> void:
	var a := _faction("raiders")
	var b := _faction("townsfolk")
	FactionMatrix.set_relation(a, b, -1.0)
	assert_eq(FactionMatrix.get_relation(a, b), -1.0, "a -> b is set")
	assert_eq(FactionMatrix.get_relation(b, a), 0.0, "b -> a is independent (directional, not mirrored)")
	a = null
	b = null


func test_set_relation_noops_on_nulls_and_empty_id() -> void:
	var a := _faction("raiders")
	var blank := Faction.new()  # empty id
	FactionMatrix.set_relation(a, blank, -1.0)
	assert_eq(a.relations.size(), 0, "an empty-id target writes nothing (no &\"\" key)")
	FactionMatrix.set_relation(null, a, -1.0)  # must not crash
	assert_eq(FactionMatrix.get_relation(null, a), 0.0, "null read is neutral")
	a = null
	blank = null


func test_bucket_for_maps_score_to_option_index() -> void:
	assert_eq(FactionMatrix.bucket_for(-1.0), 0, "<0 => Enemy")
	assert_eq(FactionMatrix.bucket_for(-0.25), 0, "any negative => Enemy")
	assert_eq(FactionMatrix.bucket_for(0.0), 1, "0 => Neutral")
	assert_eq(FactionMatrix.bucket_for(1.0), 2, ">0 => Ally")
	assert_eq(FactionMatrix.bucket_for(0.5), 2, "any positive => Ally")
