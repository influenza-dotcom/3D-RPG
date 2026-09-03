@tool
extends VBoxContainer

## Factions tab (Tune group of the CYBER SUNDAY panel; Control name "Factions" -- tests pin it, the panel sets the
## display title): an N x N grid of Enemy / Neutral / Ally dropdowns editing how each faction's NPCs treat every
## other faction's NPCs. Rows = the "from" faction, columns = the "to" faction; each cell sets the FROM faction's
## relation toward the TO faction. Whether a faction attacks the PLAYER is a different field entirely (Faction
## `default_disposition`, edited in the Inspector) and this tab never touches it -- the idle status says so, because
## that is the switch designers reach for here by mistake.
##
## WRITE CONTRACT (the same one Dialogue / Quest / Loot / Text follow): a cell change is STAGED, never committed.
## It writes the relation onto the in-memory Faction resource (the SAME cached instance the Inspector and every
## other tab hold) and marks that faction dirty -- the cell tints, its row label tints, the Save button counts it --
## and NOTHING reaches disk until the designer presses Save Factions. Save writes each dirty faction through
## ContentSaveGuard.save_with_backup (the prior bytes land in <file>.bak first, a one-deep on-disk undo) and names
## every file it changed. Refresh asks before rebuilding while there are unsaved changes (Save / Discard / Cancel;
## Discard re-reads each dirty faction from disk INTO the cached instance, so the Inspector sees the disk state
## too). Restore Last Backup is the explicit undo for a mistaken Save: it copies every faction's .bak back over its
## file and rebuilds the grid -- a disk write, labelled as one on its tooltip, refused while edits are unsaved.
##
## Because the staged edit lives on the shared cached Faction, an unsaved cell change IS visible in the Inspector
## for that faction, and a Ctrl+S there (or a save from another tab holding the same resource) persists it. That is
## the shared-cache contract every content editor here accepts; the dirty count on Save and the "(unsaved changes)"
## suffix on the status exist so the designer always knows something is pending.
##
## Storage matches scripts/faction/faction.gd EXACTLY: Faction.relations is a Dictionary keyed by the OTHER
## faction's `id` (StringName) -> a float relation score (<0 enemies / 0 neutral / >0 allies), read by
## Faction.relation_to(). This tab only edits relations -- it never touches id / display_name /
## default_disposition (deliberately warned-only / save-data-sensitive twins).
##
## The factions are enumerated via scripts/faction/factions.gd (Factions.ids() scans resources/factions/), then
## resolved with Factions.by_id() to get the live Faction resource to edit; a file that enumerates but does not
## load as a Faction is named in the status ("skipped: ...") instead of silently vanishing from the grid.
##
## Layout, top to bottom: ONE action row (Refresh / Save Factions (N) / Restore Last Backup), the grid inside a
## ScrollContainer, ONE status label. The scroller carries a small height floor so this tab can never force the
## shared bottom panel taller than the screen: a TabContainer's minimum is the CURRENT tab's minimum, and the
## editor's bottom splitter keeps the height it grew to. Horizontal scrolling stays ON here on purpose -- the grid
## is legitimately wider than a narrow dock once there are more than a handful of factions.
##
## Off-tree (GUT / the headless probe construct this bare) every editor call stays inside a button handler, the
## first-reveal latch, or behind Engine.is_editor_hint(), so _init never touches EditorInterface. The editor's
## filesystem_changed only raises `_fs_dirty`; the rescan waits for the NEXT reveal of the tab, and never while
## there are unsaved changes (the flag is kept and applied on the next clean reveal).

const RELATION_DIR := "res://resources/factions/"
## The faction registry (factions.gd has NO class_name on purpose -> preload it) -- enumerates + resolves the files.
const Factions := preload("res://scripts/faction/factions.gd")
## Recoverable saves: prior bytes -> <file>.bak before every overwrite (the same guard the content editors use).
const ContentSaveGuard := preload("res://addons/cybersunday_tools/core/content_save_guard.gd")

## The three discrete relation buckets the matrix offers, mapped to the float score stored in Faction.relations.
## A cell shows the bucket nearest the stored float (see bucket_for / RELATION_VALUES). Enemy => -1 (NPC.is_hostile
## fires on <0); Neutral => 0 (Faction.relation_to also returns 0 for an UNLISTED faction); Ally => +1.
const RELATION_LABELS := ["Enemy", "Neutral", "Ally"]
const RELATION_VALUES := [-1.0, 0.0, 1.0]

## The idle status: what the grid means, and where the OTHER hostility switch lives (whether a faction attacks the
## player is not a relation, it is Faction.default_disposition in the Inspector).
const MSG_IDLE := "How each faction's NPCs treat other factions' NPCs. Whether a faction attacks the PLAYER is its Disposition field in the Inspector."
const MSG_NO_FACTIONS := "No factions found in the factions folder -- create one with the New tab, then Refresh."
const MSG_NO_BACKUP := "Couldn't restore the last backup: No backup exists yet -- Save Factions makes one."
const MSG_RESTORE_DIRTY := "Couldn't restore the last backup: there are unsaved changes -- Save Factions or Refresh (Discard) first."
const MSG_SAVE_CLEAN := "Couldn't save: nothing has changed -- change a cell first."

## One tooltip per action button: what it does, then whether it writes. The Save / Restore tooltips swap to a
## "what is missing" sentence while the button is greyed (rule: a disabled button names what is missing).
const REFRESH_TIP := "Re-reads the factions folder and rebuilds the grid, asking first when there are unsaved changes. Read-only."
const SAVE_TIP := "Writes every changed faction to its file, keeping the previous version beside it as a .bak file. Writes faction files."
const SAVE_TIP_CLEAN := "Change a cell first."
const RESTORE_TIP := "Copies each faction's last backup (.bak) back over its file, then rebuilds the grid. Writes faction files."
const RESTORE_TIP_NONE := "No backup exists yet -- Save Factions makes one."
const RESTORE_TIP_DIRTY := "Save Factions or Refresh (Discard) first."

## Status colour for a refused command / a scan that lost files (the label's default colour is restored on every
## plain write). DIRTY_COLOR tints a cell (whole-button modulate) and its row label while the change is unsaved.
const WARN_COLOR := Color(1.0, 0.85, 0.4)
const DIRTY_COLOR := Color(1.0, 0.9, 0.55)
## Cells drop OptionButton's fit-to-longest-item width so the grid stays uniform; this floor keeps "Neutral" readable.
const CELL_MIN_WIDTH := 84.0

var _grid: GridContainer = null
var _status: Label = null
var _refresh_btn: Button = null
var _save_btn: Button = null
var _restore_btn: Button = null
## The factions in grid order (row i == column i). Each is the live cached Faction resource, edited in place.
var _factions: Array[Faction] = []
## Row labels in grid order, tinted while their faction has an unsaved change.
var _row_labels: Array[Label] = []
## Vector2i(row, col) -> the editable OptionButton (off-diagonal cells only; the diagonal is locked to Ally).
var _cells: Dictionary = {}
## Vector2i(row, col) -> true while that cell differs from what was loaded from (or last saved to) its file. A cell
## changed and then changed BACK is clean again. A faction is dirty when any cell in its row is; Save writes those.
var _dirty_cells: Dictionary = {}
## True when at least one faction file has a .bak beside it -- checked at every rescan / save / restore, so the
## Restore button can grey with "No backup exists yet" BEFORE a click (the click itself stays guarded too).
var _has_backup := false
var _status_base := ""     # the last status message, before the "(unsaved changes)" suffix
var _status_warn := false
## The unsaved-changes guard on Refresh, built lazily on first use (a popup needs the tree; _init runs off-tree).
var _guard: ConfirmationDialog = null

## Raised by the editor's filesystem_changed (connected in _init, editor only). A rescan while the tab is showing
## would rebuild the grid under the designer's mouse -- and under an unsaved edit -- so the flag waits for the next
## reveal, and is KEPT (not applied) while there are unsaved changes.
var _fs_dirty := false
## Lazy first-reveal latch -- the faction scan (which LOADS every file under resources/factions/ and builds an
## N x N OptionButton grid) runs on first reveal, not at panel construction. cyber_panel._init() builds every tab
## eagerly, and the editor reconstructs the panel on every plugin reload, so an _init-time scan costs a full folder
## load on every editor start even when this tab is never opened. Mirrors content_browser / tuning_browser /
## item_placer_dock (pinned by tests/test_devtools_lazy_reveal.gd).
var _revealed := false


func _init() -> void:
	name = "Factions"
	add_theme_constant_override("separation", 4)

	# --- action row: Refresh (read-only), Save Factions (N) (the ONE write), Restore Last Backup (the undo) ----
	var actions := HBoxContainer.new()
	_refresh_btn = Button.new()
	_refresh_btn.text = "Refresh"
	_refresh_btn.tooltip_text = REFRESH_TIP
	_refresh_btn.pressed.connect(_on_refresh_pressed)
	actions.add_child(_refresh_btn)
	_save_btn = Button.new()
	_save_btn.pressed.connect(_on_save)
	actions.add_child(_save_btn)
	_restore_btn = Button.new()
	_restore_btn.text = "Restore Last Backup"
	_restore_btn.pressed.connect(_on_restore_pressed)
	actions.add_child(_restore_btn)
	add_child(actions)

	# --- the grid, inside the ONE scroller ------------------------------------------------------------------
	# Vertical floor only; horizontal_scroll_mode stays AUTO (the default) -- an N x N grid of dropdowns is
	# legitimately wider than a narrow dock, and clipping it would hide whole factions.
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 100)
	add_child(scroll)
	_grid = GridContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)

	# What the tab just DID or REFUSED (or the next step). Clamped to two lines with the full text on its tooltip,
	# so a long save report can never push the grid off a short bottom panel.
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 2
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.modulate = Color(1, 1, 1, 0.75)
	_status.mouse_filter = Control.MOUSE_FILTER_PASS  # a Label ignores the mouse by default, which also hides its tooltip
	add_child(_status)
	_set_status(MSG_IDLE)
	_refresh_dirty_ui()  # Save starts greyed (nothing changed); Restore greyed until a rescan finds a .bak

	# EditorInterface: the filesystem signal only FLAGS the grid stale (see _fs_dirty). Guarded so the off-tree /
	# headless construction (GUT, the probe) never touches the editor.
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_filesystem_changed)
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()  # no-op off-tree (not visible); in the editor the real reveal fires the signal


## Lazy first-reveal: load the factions + build the grid ONCE, the first time the tab is actually shown. Later
## reveals rescan only when the editor's filesystem changed underneath us AND nothing is unsaved -- a rebuild would
## drop the staged cells, so the flag stays raised until the next clean reveal (or an explicit Refresh).
func _on_visibility_changed() -> void:
	if is_visible_in_tree() and not _revealed:
		_revealed = true
		_rescan()
	elif is_visible_in_tree() and _fs_dirty:
		if not _dirty_cells.is_empty():
			return  # keep the flag; apply it on the next reveal with nothing pending
		_rescan()


## The editor's FileSystem scanner noticed a change (a new / saved / deleted file anywhere). Only flag it: the
## rescan runs on the next clean reveal, never under the designer's edit while the tab is showing.
func _on_filesystem_changed() -> void:
	_fs_dirty = true


# --- pure relation helpers (testable WITHOUT disk / EditorInterface) ---------------------------------------------

## Set faction `a`'s relation toward faction `b` to `value` -- the in-memory half of a cell change (the disk half is
## Save Factions). Stores under b.id in a.relations -- matching Faction.relation_to(b.id). A neutral (0.0) clears
## the entry so the file stays clean (Faction.relation_to returns 0 for an unlisted id anyway). No-ops on nulls /
## empty b.id. Pure + static so the test can round-trip it on throwaway Faction.new()s.
static func set_relation(a: Faction, b: Faction, value: float) -> void:
	if a == null or b == null:
		return
	var key := StringName(b.id)
	if String(key).is_empty():
		return
	if is_equal_approx(value, 0.0):
		a.relations.erase(key)
	else:
		a.relations[key] = value

## Faction `a`'s relation score toward faction `b` (0.0 if unset / nulls), via the SAME read as runtime
## (Faction.relation_to). Pure mirror of set_relation for the round-trip test.
static func get_relation(a: Faction, b: Faction) -> float:
	if a == null or b == null:
		return 0.0
	# Read the relations Dictionary DIRECTLY (mirrors Faction.relation_to) -- a property read works in the editor's
	# tool mode, whereas calling relation_to() (faction.gd isn't @tool) errors on dock init at edit time.
	return float(a.relations.get(StringName(b.id), 0.0))

## The RELATION_VALUES index whose bucket best matches `score` (<0 => Enemy, 0 => Neutral, >0 => Ally).
static func bucket_for(score: float) -> int:
	if score < 0.0:
		return 0
	if score > 0.0:
		return 2
	return 1


# --- pure report lines (pinned headless) --------------------------------------------------------------------------

## The scan status when some files under the factions folder enumerated but did not load as factions:
## "Loaded 2 factions; skipped: bad_one, other -- those files didn't load as factions."
static func scan_report(loaded: int, skipped: PackedStringArray) -> String:
	var head := "Loaded %s" % _count(loaded, "faction", "factions")
	if skipped.is_empty():
		return head + "."
	return "%s; skipped: %s -- those files didn't load as factions." % [head, ", ".join(skipped)]


## The save status line: "Saved raiders.tres -- the previous version is kept beside it as raiders.tres.bak." (or the
## plural form naming every file), then one "Couldn't save <file>: <reason>." per failure (each `failures` row is
## already "<file>: <reason>", the reason being error_string(err) -- never a bare number).
static func save_report(saved: PackedStringArray, failures: PackedStringArray) -> String:
	var parts := PackedStringArray()
	if saved.size() == 1:
		parts.append("Saved %s -- the previous version is kept beside it as %s.bak." % [saved[0], saved[0]])
	elif saved.size() > 1:
		parts.append("Saved %s: %s -- the previous version of each is kept beside it as a .bak file." % [
			_count(saved.size(), "faction", "factions"), ", ".join(saved)])
	for row in failures:
		parts.append("Couldn't save %s." % row)
	return " ".join(parts)


## The restore status line: "Restored raiders.tres from its last backup -- the grid shows the files again." (or the
## plural form), then one "Couldn't restore <file>: <reason>." per failure.
static func restore_report(restored: PackedStringArray, failures: PackedStringArray) -> String:
	var parts := PackedStringArray()
	if restored.size() == 1:
		parts.append("Restored %s from its last backup -- the grid shows the files again." % restored[0])
	elif restored.size() > 1:
		parts.append("Restored %s from their last backups: %s -- the grid shows the files again." % [
			_count(restored.size(), "faction", "factions"), ", ".join(restored)])
	for row in failures:
		parts.append("Couldn't restore %s." % row)
	return " ".join(parts)


## "1 faction" / "3 factions" -- one place for the count wording used across the status lines.
static func _count(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]


# --- scan + build ---------------------------------------------------------------------------------------------------

## Re-read the factions folder and rebuild the grid from the live (cached) resources. Files that enumerate but do
## not load as a Faction are named in the status. Clears _fs_dirty: this IS the rescan the filesystem flag asks
## for. Drops any staged cells -- every caller either checked _dirty_cells is empty or asked the designer first.
func _rescan() -> void:
	_fs_dirty = false
	var found: Array[Faction] = []
	var skipped := PackedStringArray()
	for fid in Factions.ids():
		var f := Factions.by_id(fid)
		if f == null:
			skipped.append(fid)
			continue
		found.append(f)
	_build_grid(found)
	_has_backup = _any_backup_exists()
	_refresh_dirty_ui()
	if found.is_empty():
		_set_status(MSG_NO_FACTIONS, true)
	elif skipped.is_empty():
		_set_status(MSG_IDLE)
	else:
		_set_status(scan_report(found.size(), skipped), true)


## Build the N x N grid for `factions` (grid order == array order). Split from _rescan so a test can hand it
## in-memory / temp-file factions and never touch the project's real factions folder. Resets every per-grid
## table (cells, dirty marks, row labels) -- the previous grid is gone, so its dirty marks are meaningless.
func _build_grid(factions: Array[Faction]) -> void:
	# remove_child BEFORE queue_free: a queue_free'd child stays in the tree (and in get_children()) until the end of
	# the frame, so the new header/cells added below would lay out alongside the old grid for a frame.
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_cells.clear()
	_dirty_cells.clear()
	_row_labels.clear()
	_factions = factions

	var n := _factions.size()
	if n == 0:
		_grid.columns = 1
		var empty := Label.new()
		empty.text = "No factions yet."
		# The folder is the hint, in designer words: the scheme prefix is engine spelling and belongs nowhere a
		# designer reads, tooltip included.
		empty.tooltip_text = "Faction files live in %s -- make one in the New tab, then press Refresh." % RELATION_DIR.trim_prefix("res://")
		empty.mouse_filter = Control.MOUSE_FILTER_PASS  # a Label ignores the mouse by default, which hides its tooltip
		_grid.add_child(empty)
		return

	_grid.columns = n + 1

	# Header row: the corner legend + a column header per faction.
	_grid.add_child(_corner_label())
	for col in range(n):
		_grid.add_child(_header_label(_factions[col]))

	# One body row per "from" faction.
	for row in range(n):
		var lbl := _row_label(_factions[row])
		_row_labels.append(lbl)
		_grid.add_child(lbl)
		for col in range(n):
			_grid.add_child(_make_cell(row, col))


func _corner_label() -> Control:
	var l := Label.new()
	l.text = "from \\ to"
	l.tooltip_text = "Rows: the faction whose NPCs act. Columns: the faction they act toward."
	return l

func _header_label(f: Faction) -> Control:
	var l := Label.new()
	l.text = _faction_name(f)
	l.tooltip_text = _file_name(f)
	return l

func _row_label(f: Faction) -> Label:
	var l := Label.new()
	l.text = _faction_name(f)
	l.tooltip_text = _file_name(f)
	return l

## The designer-facing name: display_name, else the id, else the file's stem (a faction is never shown blank).
func _faction_name(f: Faction) -> String:
	var dn := f.display_name.strip_edges()
	if not dn.is_empty():
		return dn
	var id := String(f.id)
	return id if not id.is_empty() else f.resource_path.get_file().get_basename()

## The file name for tooltips ("raiders.tres"); an in-memory faction with no file shows its id instead.
func _file_name(f: Faction) -> String:
	var path := f.resource_path
	return path.get_file() if not path.is_empty() else String(f.id)


func _make_cell(row: int, col: int) -> Control:
	var ob := OptionButton.new()
	for i in range(RELATION_LABELS.size()):
		ob.add_item(RELATION_LABELS[i], i)
	# Width guards (the PickerRows.apply idiom): drop the fit-to-longest-item minimum so every cell is the same
	# width, clip the caption instead of widening the grid, and floor the width so "Neutral" stays readable.
	ob.fit_to_longest_item = false
	ob.clip_text = true
	ob.custom_minimum_size = Vector2(CELL_MIN_WIDTH, 0)
	var from_f: Faction = _factions[row]
	var to_f: Faction = _factions[col]
	if row == col:
		# A faction's relation to itself is always friendly and not editable.
		ob.select(2)
		ob.disabled = true
		ob.tooltip_text = "%s NPCs always treat their own faction as allies -- not editable." % _faction_name(from_f)
		return ob
	var loaded := bucket_for(get_relation(from_f, to_f))
	ob.select(loaded)  # select() does NOT emit item_selected, so the push can never stage a change
	ob.set_meta("loaded_bucket", loaded)  # what the file holds; a cell back on this value is clean again
	ob.tooltip_text = "How %s NPCs treat %s NPCs" % [_faction_name(from_f), _faction_name(to_f)]
	ob.item_selected.connect(_on_cell_selected.bind(row, col))
	_cells[Vector2i(row, col)] = ob
	return ob


# --- the cell edit: STAGE in memory, mark dirty, never write ----------------------------------------------------------

## A cell change: write the relation onto the in-memory Faction, then mark (or clear) the cell's dirty state against
## what its file holds. Nothing reaches disk here -- that is Save Factions.
func _on_cell_selected(idx: int, row: int, col: int) -> void:
	if row == col:
		return
	if row < 0 or row >= _factions.size() or col < 0 or col >= _factions.size():
		return
	if idx < 0 or idx >= RELATION_VALUES.size():
		return
	var from_f: Faction = _factions[row]
	var to_f: Faction = _factions[col]
	set_relation(from_f, to_f, RELATION_VALUES[idx])
	var key := Vector2i(row, col)
	var cell: OptionButton = _cells.get(key)
	var loaded: int = cell.get_meta("loaded_bucket", idx) if cell != null else idx
	var dirty := idx != loaded
	if dirty:
		# Stage the BUCKET, not just a flag: _mark_row_clean needs to know what was actually written, and the widget
		# is the wrong source for it (a programmatic selection never round-trips through `selected`).
		_dirty_cells[key] = idx
	else:
		_dirty_cells.erase(key)
	_tint_cell(cell, dirty)
	_refresh_dirty_ui()
	_set_status("Set how %s NPCs treat %s NPCs to %s -- not written until Save Factions." % [
		_faction_name(from_f), _faction_name(to_f), RELATION_LABELS[idx]])


## Whole-button tint while a cell's value differs from its file (cleared on save / discard / rebuild).
func _tint_cell(cell: OptionButton, dirty: bool) -> void:
	if cell == null:
		return
	cell.modulate = DIRTY_COLOR if dirty else Color.WHITE


## The dirty faction rows (sorted, unique) -- one file to write per row.
func _dirty_rows() -> Array[int]:
	var rows: Array[int] = []
	for key: Vector2i in _dirty_cells.keys():
		if not rows.has(key.x):
			rows.append(key.x)
	rows.sort()
	return rows


## How many factions have an unsaved change (== how many files Save Factions would write).
func _dirty_count() -> int:
	return _dirty_rows().size()


## After a successful save of `row`'s faction: its cells' loaded value becomes what they show now, the tints clear.
func _mark_row_clean(row: int) -> void:
	for key: Vector2i in _dirty_cells.keys():
		if key.x != row:
			continue
		var cell: OptionButton = _cells.get(key)
		if cell != null:
			# The new clean baseline is the bucket that was SAVED (staged in _dirty_cells), not whatever the widget
			# currently shows -- those agree after a designer's click, but only the staged value is the one on disk.
			cell.set_meta("loaded_bucket", int(_dirty_cells[key]))
			_tint_cell(cell, false)
		_dirty_cells.erase(key)


## The Save / Restore buttons' text, enabled state and tooltips, the row-label tints, and the status suffix, all
## from the live dirty state. Save reads "Save Factions (N)" and is greyed with a "what is missing" tooltip while
## nothing has changed; Restore is greyed while edits are unsaved (they would be lost) or no .bak exists yet.
func _refresh_dirty_ui() -> void:
	var rows := _dirty_rows()
	var n := rows.size()
	if _save_btn != null:
		_save_btn.text = ("Save Factions (%d)" % n) if n > 0 else "Save Factions"
		_save_btn.disabled = n == 0
		_save_btn.tooltip_text = SAVE_TIP if n > 0 else SAVE_TIP_CLEAN
	if _restore_btn != null:
		if n > 0:
			_restore_btn.disabled = true
			_restore_btn.tooltip_text = RESTORE_TIP_DIRTY
		elif not _has_backup:
			_restore_btn.disabled = true
			_restore_btn.tooltip_text = RESTORE_TIP_NONE
		else:
			_restore_btn.disabled = false
			_restore_btn.tooltip_text = RESTORE_TIP
	for i in range(_row_labels.size()):
		var lbl: Label = _row_labels[i]
		if rows.has(i):
			lbl.add_theme_color_override("font_color", DIRTY_COLOR)
		else:
			lbl.remove_theme_color_override("font_color")
	_render_status()


## The changed file names for the Refresh dialog: up to six by name, then "and N more".
func _dirty_names_text() -> String:
	var names := PackedStringArray()
	for row in _dirty_rows():
		names.append(_file_name(_factions[row]))
	if names.size() <= 6:
		return ", ".join(names)
	var head := PackedStringArray()
	for i in 6:
		head.append(names[i])
	return "%s and %d more" % [", ".join(head), names.size() - 6]


# --- save -----------------------------------------------------------------------------------------------------------

## Save Factions: write ONLY the dirty factions, each through ContentSaveGuard.save_with_backup (prior bytes ->
## <file>.bak first), then update_file so the editor re-reads it. Reports the saved file names and, per failure, the
## file name with the plain reason (error_string) -- never a bare error number, never swallowed. A faction that failed
## stays dirty for a retry. Handler-only work but no tree needed, so the test drives it off-tree.
func _on_save() -> void:
	var saved := PackedStringArray()
	var failures := PackedStringArray()
	for row in _dirty_rows():
		var f: Faction = _factions[row]
		var path := f.resource_path
		if path.is_empty():
			failures.append("%s: it has no file on disk yet" % _faction_name(f))
			continue
		var err := ContentSaveGuard.save_with_backup(f, path)
		if err != OK:
			failures.append("%s: %s" % [path.get_file(), error_string(err)])
			push_warning("Factions: couldn't save %s: %s" % [path, error_string(err)])
			continue
		if Engine.is_editor_hint():
			EditorInterface.get_resource_filesystem().update_file(path)
		_mark_row_clean(row)
		saved.append(path.get_file())
	_has_backup = _any_backup_exists()
	_refresh_dirty_ui()
	if saved.is_empty() and failures.is_empty():
		_set_status(MSG_SAVE_CLEAN)  # fallback only: the button is greyed while nothing has changed
		return
	_set_status(save_report(saved, failures), not failures.is_empty())


## True when any loaded faction file has a .bak beside it (what Restore Last Backup would copy back).
func _any_backup_exists() -> bool:
	for f: Faction in _factions:
		var path := f.resource_path
		if not path.is_empty() and FileAccess.file_exists(ContentSaveGuard.backup_path(path)):
			return true
	return false


# --- refresh (asks first when dirty) ----------------------------------------------------------------------------------

## The Refresh command. With unsaved changes it asks first (Save / Discard / Cancel); otherwise it rescans now.
func _on_refresh_pressed() -> void:
	if _dirty_cells.is_empty():
		_rescan()
		return
	_ask_before_refresh()


## The unsaved-changes guard on Refresh, built lazily on first use (a popup needs the tree; _init runs off-tree).
func _ask_before_refresh() -> void:
	if _guard == null:
		_guard = ConfirmationDialog.new()
		_guard.title = "Unsaved factions"
		_guard.ok_button_text = "Save"
		_guard.cancel_button_text = "Cancel"
		_guard.add_button("Discard", false, "discard")
		_guard.confirmed.connect(_on_guard_save)
		_guard.custom_action.connect(_on_guard_custom)
		_guard.canceled.connect(_on_guard_cancel)
		add_child(_guard)
	_guard.dialog_text = "Save changes to %s first?" % _dirty_names_text()
	_guard.popup_centered()


## "Save": save first; refresh only when everything saved, so a failed write never has its edits dropped underneath
## it (the save report stays on the status and the cells stay dirty for a retry).
func _on_guard_save() -> void:
	_on_save()
	if not _dirty_cells.is_empty():
		# Name the thing that was refused (the grid), then hand over the save report verbatim -- it already carries a
		# "Couldn't save <file>: <reason>." per failure, which is the plain reason the refusal grammar asks for.
		_set_status("Couldn't refresh the grid: %s" % _status_base, true)
		return
	_rescan()


## "Discard": put the files' bytes back over the in-memory factions, then rebuild. A custom dialog button does not
## close the dialog by itself, hence the explicit hide().
func _on_guard_custom(action: StringName) -> void:
	if action != &"discard":
		return
	_guard.hide()
	var dropped := _discard_changes()
	_rescan()
	if not dropped.is_empty():
		_set_status("Discarded the changes to %s -- the grid shows the files again." % ", ".join(dropped))


## "Cancel": nothing moves; there is no picker here to restore.
func _on_guard_cancel() -> void:
	_set_status("Kept the grid as it is -- the unsaved changes are still here.")


## Drop every staged cell by re-reading each dirty faction's file INTO its cached instance (see _reread_relations
## for the default-omission trap that makes the reset-then-reload order load-bearing). Returns the file names it
## re-read. A file that is gone is warned and skipped -- its staged edit then simply drops out with the next
## rebuild. Off-tree safe: no editor call, no tree.
func _discard_changes() -> PackedStringArray:
	var dropped := PackedStringArray()
	for row in _dirty_rows():
		var f: Faction = _factions[row]
		var path := f.resource_path
		if path.is_empty():
			continue
		if not FileAccess.file_exists(path):
			push_warning("Factions: couldn't re-read %s to discard its changes -- the file is gone." % path)
			continue
		_reread_relations(f)
		dropped.append(path.get_file())
	_dirty_cells.clear()
	for cell: OptionButton in _cells.values():
		_tint_cell(cell, false)
	_refresh_dirty_ui()
	return dropped


## Put a faction file's bytes back over its cached instance: the disk half of Discard and Restore. CACHE_MODE_REPLACE
## re-reads the file INTO the same Resource object (so the Inspector and anything else holding it see the disk
## state), but a .tres OMITS every property that equals its script default -- a faction with no relations has no
## `relations` line at all -- and an in-place re-read only assigns the properties it finds. Without the reset below, a
## relation staged where the file had NONE would silently survive its own "discard". `relations` is the ONE field this
## tab edits, so resetting it to the resource default first, then letting the file re-apply whatever it does hold,
## is exact. Warns (never throws) when the re-read fails; the next rebuild then drops that faction from the grid.
static func _reread_relations(f: Faction) -> void:
	f.relations = {}
	var fresh := ResourceLoader.load(f.resource_path, "", ResourceLoader.CACHE_MODE_REPLACE) as Faction
	if fresh == null:
		push_warning("Factions: couldn't re-read %s -- Refresh to reload the grid." % f.resource_path)


# --- restore last backup (the explicit undo for a mistaken Save) ------------------------------------------------------

## Restore Last Backup: copy every faction's .bak back over its file, re-read each restored file into its cached
## instance, then rebuild the grid. Refused (status + greyed button) while edits are unsaved -- the rebuild would
## drop them -- and when no faction has a .bak yet.
func _on_restore_pressed() -> void:
	if not _dirty_cells.is_empty():
		_set_status(MSG_RESTORE_DIRTY, true)
		return
	var rep := restore_backups(_factions)
	var restored: PackedStringArray = rep["restored"]
	var failures: PackedStringArray = rep["failures"]
	if restored.is_empty() and failures.is_empty():
		_set_status(MSG_NO_BACKUP, true)
		return
	_rescan()
	_set_status(restore_report(restored, failures), not failures.is_empty())


## The disk half of Restore Last Backup, split out so the test can run it on temp files: for every faction with a
## <file>.bak beside it, copy the .bak back over the file (the .bak itself is kept) and re-read the file INTO the
## cached instance (_reread_relations, as Discard does). Returns {restored: PackedStringArray, failures:
## PackedStringArray} of file names / "<file>: <reason>" rows. A faction with no .bak is simply not listed.
static func restore_backups(factions: Array[Faction]) -> Dictionary:
	var restored := PackedStringArray()
	var failures := PackedStringArray()
	for f: Faction in factions:
		var path := f.resource_path
		if path.is_empty():
			continue
		var bak := ContentSaveGuard.backup_path(path)
		if not FileAccess.file_exists(bak):
			continue
		var err := DirAccess.copy_absolute(bak, path)
		if err != OK:
			failures.append("%s: %s" % [path.get_file(), error_string(err)])
			push_warning("Factions: couldn't restore %s from %s: %s" % [path, bak, error_string(err)])
			continue
		_reread_relations(f)
		if Engine.is_editor_hint():
			EditorInterface.get_resource_filesystem().update_file(path)
		restored.append(path.get_file())
	return {"restored": restored, "failures": failures}


# --- status -----------------------------------------------------------------------------------------------------------

## Every status write: the label clamps to two lines, so the tooltip mirrors the whole message. `warn` tints the
## text (a refused command, a scan that lost files); a plain write restores the label's default colour. The
## "(unsaved changes)" suffix is re-applied by _render_status from the live dirty state, so it never goes stale.
func _set_status(msg: String, warn: bool = false) -> void:
	_status_base = msg
	_status_warn = warn
	_render_status()


func _render_status() -> void:
	if _status == null:
		return
	var msg := _status_base
	if not _dirty_cells.is_empty():
		msg += " (unsaved changes)"
	_status.text = msg
	_status.tooltip_text = msg
	if _status_warn:
		_status.add_theme_color_override("font_color", WARN_COLOR)
	else:
		_status.remove_theme_color_override("font_color")
