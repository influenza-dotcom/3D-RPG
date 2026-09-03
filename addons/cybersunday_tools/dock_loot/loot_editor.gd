@tool
extends VBoxContainer

## "Loot Edit" tab for the CYBER SUNDAY bottom panel: edit a LootTable's drop rows WITHOUT the raw inspector.
## Pick a loot table (scanned off-disk -- the ItemDb/registries are non-@tool, empty in-editor), edit each row with
## plain widgets (an item dropdown fed by the shared core/item_scan.gd, a 0..1 chance SpinBox, min/max count
## SpinBoxes), Add/Remove/Up/Down rows, watch a live "expected drops" summary, and SAVE (ContentSaveGuard -> .bak,
## then ResourceSaver + update_file so the editor reimports). All row mutation is delegated to LootEditOps (pure,
## GUT-tested); this file is THIN editor glue only.
##
## LAYOUT CONTRACT (why the tab is shaped this way): a TabContainer's minimum is the CURRENT tab's minimum, and the
## editor's bottom splitter keeps the height it grew to -- so a tall tab, once shown, leaves the panel tall for every
## tab after it. This tab used to be the tallest (no ScrollContainer, ~335 px). Now only the top bar (table picker +
## Refresh + Save Loot Table) and ONE status Label sit outside a ScrollContainer; the rows list, the row buttons, the
## per-row editor and the summary all live inside it, so the whole tab's minimum lands well under ~200 px.
##
## HANDOFF: the panel (cyber_panel.gd, reached only through core/host.gd) calls `select_path(path)` to hand a
## LootTable file to this tab (Browse double-click, Refs, the Blueprints scaffold). Off-tree there is no host and no
## viewport for the unsaved-changes dialog, so select_path refuses (false) and the panel falls back to the Inspector.
##
## DIRTY STATE: every write-through handler and every add/remove/move sets `_dirty`; a successful Save and a load
## clear it. It renders as "Save Loot Table*" and "(unsaved changes)" in the status, and every chokepoint that swaps
## the open table (picker change, select_path, a Refresh whose rescan lost the open file) asks
## "Save changes to <file> first?" (Save / Discard / Cancel) before switching.
##
## Designer-first idiom: a new editor is a NEW @tool Control that owns its tab `name` ("Loot Edit" -- the panel sets
## the DISPLAY title, tests pin the Control name). NO graph-drag, NO hand-written uid:// (ResourceSaver mints it).
## Every string here is a DEVELOPER surface (editor tooling) and never goes through PlayerText.

const Ops := preload("res://addons/cybersunday_tools/dock_loot/loot_edit_ops.gd")
const ContentSaveGuard := preload("res://addons/cybersunday_tools/core/content_save_guard.gd")
const ItemScan := preload("res://addons/cybersunday_tools/core/item_scan.gd")
const PickerRows := preload("res://addons/cybersunday_tools/core/picker_rows.gd")

## Where loot tables are discovered (recursively). Items come from ItemScan.ITEMS_DIR -- the ONE shared item scan.
const SCAN_ROOT := "res://resources"

## Button labels. The Save label is rebuilt with a "*" suffix while there are unsaved changes (see _render_dirty).
const SAVE_LABEL := "Save Loot Table"

## Idle status: the one imperative next step when nothing is open yet.
const IDLE_HINT := "Pick a loot table, then a row -- edits stay in memory until you press Save Loot Table."
## The greyed row editor's next step (a table is open, rows exist, none is picked).
const ROW_HINT := "Pick a row above to edit it, or press Add."
## The greyed row editor's next step when the open table has no rows at all.
const EMPTY_HINT := "Press Add to create the first row."

## Tooltips for the disabled states (rule: a button that cannot apply names what is missing).
const TIP_NO_TABLE := "Pick a loot table first."
const TIP_NO_ROW := "Pick a row in the list first."
## Tooltips for the enabled states: "<What it does>. <Writes X | Read-only>."
const TIP_REFRESH := "Re-read the lists of loot tables and items from disk. Read-only -- the open table stays open."
const TIP_ADD := "Add a new row at the bottom (chance 1, count 1 to 1). Writes nothing until Save Loot Table."
const TIP_REMOVE := "Remove the picked row. Writes nothing until Save Loot Table."
const TIP_UP := "Move the picked row up one place. Writes nothing until Save Loot Table."
const TIP_DOWN := "Move the picked row down one place. Writes nothing until Save Loot Table."
const TIP_CHANCE := "Chance this row drops, 0 to 1 (0.35 = 35 %)"
const TIP_MIN := "Fewest of this item dropped when the row hits."
const TIP_MAX := "Most of this item dropped when the row hits -- never below Min (it is raised to Min if you go under)."

## Status colours for the two verdict tones; the plain tone REMOVES the override so the editor theme's default shows.
const WARN_COLOR := Color(1.0, 0.78, 0.35)
const ERROR_COLOR := Color(1.0, 0.45, 0.45)

# --- fixed top bar + status (outside the scroll) ---
var _table_pick: OptionButton = null
var _refresh_btn: Button = null
var _save_btn: Button = null
var _status: Label = null

# --- everything else (inside the scroll) ---
var _scroll: ScrollContainer = null
var _entry_list: ItemList = null
var _add_btn: Button = null
var _remove_btn: Button = null
var _up_btn: Button = null
var _down_btn: Button = null
var _row_box: VBoxContainer = null
var _item_pick: OptionButton = null
var _chance: SpinBox = null
var _min_count: SpinBox = null
var _max_count: SpinBox = null
var _summary: Label = null

## The unsaved-changes dialog, built lazily by the first guarded switch (a bare tab under GUT never builds it).
var _guard: ConfirmationDialog = null

var _tables: Array[String] = []              ## resource paths of discovered LootTable files, parallel to _table_pick rows
var _tables_skipped := PackedStringArray()   ## files that declare LootTable but did not load as one (broken / mid-reimport)
var _items: Array[Item] = []                 ## scanned items; parallel to _item_paths / _item_labels
var _item_paths := PackedStringArray()       ## each item's resource_path -- the value PickerRows rows carry
var _item_labels := PackedStringArray()      ## each item's display label
var _items_skipped := PackedStringArray()    ## item files that exist but did not load as an Item
## The PickerRows rows CURRENTLY in `_item_pick`, kept so _on_item_selected can resolve a picked index through
## PickerRows.resolve_pick (the anti-clobber table) instead of trusting the widget's own metadata.
var _item_rows: Array = []
## The picker row that stands for the OPEN table -- its scanned row, or the disabled "no longer on disk" row
## _fill_table_pick appends for a file that vanished mid-edit. This, NOT `_tables.find(...)`, is what a cancelled
## switch restores: the two differ exactly when the open file is gone, which is when a wrong restore hurts most.
var _table_pick_idx := -1
var _table: LootTable = null                 ## the currently-open table (null = nothing open / failed load)

## Unsaved edits to the open table. Set by every write-through handler and every add/remove/move; cleared by a
## successful Save and by every load. Rendered by _render_dirty (button "*") and _render_status ("(unsaved changes)").
var _dirty := false
## The last status line WITHOUT the dirty suffix, so re-rendering after a dirty flip never stacks suffixes.
var _status_base := ""
## "" (plain) / "warn" / "error" -- the tone of the current status line.
var _status_kind := ""

## PL6: lazy first-reveal latch -- the item + loot-table scans run on first reveal, not at panel construction.
var _revealed := false
## Set by the editor's filesystem_changed signal while the tab is hidden or busy; the NEXT in-tree reveal rescans
## (keeping the open table by path). Never rescans mid-edit while the tab is visible; Refresh is the explicit fallback.
var _fs_dirty := false

## The switch waiting on the unsaved-changes dialog (run after Save or Discard), and the picker index to restore
## on Cancel. `_guard_open` makes the three dialog handlers idempotent (a late `canceled` after a handled Discard
## must not restore the old picker index over the new table).
var _pending: Callable = Callable()
var _pending_prev_idx := -1
var _guard_open := false


func _init() -> void:
	name = "Loot Edit"
	add_theme_constant_override("separation", 4)

	# --- fixed top bar: table picker + Refresh + Save Loot Table (outside the scroll, always visible) ---
	var bar := HBoxContainer.new()
	add_child(bar)
	_table_pick = OptionButton.new()
	_table_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_table_pick.fit_to_longest_item = false  # PickerRows.apply re-applies both width guards on every fill; set here too so an
	_table_pick.clip_text = true             # EMPTY picker (before the first reveal) can't widen the panel either
	_table_pick.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_table_pick.tooltip_text = "The loot table to edit. Refresh re-reads every folder under %s." % SCAN_ROOT
	_table_pick.item_selected.connect(_on_table_selected)
	bar.add_child(_table_pick)
	_refresh_btn = _mk_button("Refresh", TIP_REFRESH, _on_refresh_pressed)
	bar.add_child(_refresh_btn)
	_save_btn = _mk_button(SAVE_LABEL, TIP_NO_TABLE, _on_save)
	_save_btn.disabled = true
	bar.add_child(_save_btn)

	# --- the ONE status Label outside the scroll: two visible lines, the full text mirrored into its tooltip ---
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 2
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.modulate = Color(1, 1, 1, 0.75)
	add_child(_status)
	_set_status(IDLE_HINT)

	# --- everything that grows lives INSIDE the scroll, so the tab's minimum is the scroll's floor, not the content ---
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED  # widgets fill the width; only scroll vertically
	_scroll.custom_minimum_size = Vector2(0, 100)
	add_child(_scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 4)
	_scroll.add_child(body)

	# --- rows list ---
	_entry_list = ItemList.new()
	_entry_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_entry_list.custom_minimum_size = Vector2(0, 70)
	_entry_list.tooltip_text = "The table's drop rows. Pick one to edit it below."
	_entry_list.item_selected.connect(_on_row_selected)
	body.add_child(_entry_list)

	# --- row buttons ---
	var btns := HBoxContainer.new()
	body.add_child(btns)
	_add_btn = _mk_button("Add", TIP_NO_TABLE, _on_add)
	btns.add_child(_add_btn)
	_remove_btn = _mk_button("Remove", TIP_NO_ROW, _on_remove)
	btns.add_child(_remove_btn)
	_up_btn = _mk_button("Up", TIP_NO_ROW, func() -> void: _on_move(-1))
	btns.add_child(_up_btn)
	_down_btn = _mk_button("Down", TIP_NO_ROW, func() -> void: _on_move(1))
	btns.add_child(_down_btn)

	# --- per-row editor (THREE-SITE widgets: pushed by _load_row, reset by _clear_row, written by the handlers) ---
	_row_box = VBoxContainer.new()
	body.add_child(_row_box)

	var item_row := HBoxContainer.new()
	_row_box.add_child(item_row)
	item_row.add_child(_mk_label("Item"))
	_item_pick = OptionButton.new()
	_item_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_pick.fit_to_longest_item = false  # PickerRows.apply owns the width guards on every fill; mirrored here for the
	_item_pick.clip_text = true             # empty widget that exists before the first reveal (the test pins item_count 0)
	_item_pick.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # cosmetic; PickerRows leaves it to the caller
	_item_pick.tooltip_text = "The item this row drops. (none) drops nothing. Items come from %s." % ItemScan.ITEMS_DIR
	_item_pick.item_selected.connect(_on_item_selected)
	item_row.add_child(_item_pick)

	var chance_row := HBoxContainer.new()
	_row_box.add_child(chance_row)
	chance_row.add_child(_mk_label("Chance"))
	_chance = SpinBox.new()
	_chance.min_value = 0.0
	_chance.max_value = 1.0
	# A Range SNAPS every value it is given to `step` -- on the way IN as well as out, and `set_value_no_signal`
	# snaps too. So `step` is the finest chance this tab can even DISPLAY: at the old 0.05 an authored 0.02 showed
	# as 0.00. 0.01 = whole percents, which is how the tooltip (and a designer) talks about a drop chance.
	_chance.step = 0.01
	_chance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chance.tooltip_text = TIP_CHANCE
	_chance.value_changed.connect(_on_chance_changed)
	chance_row.add_child(_chance)

	var count_row := HBoxContainer.new()
	_row_box.add_child(count_row)
	count_row.add_child(_mk_label("Min"))
	_min_count = _mk_count_spin(TIP_MIN)
	count_row.add_child(_min_count)
	count_row.add_child(_mk_label("Max"))
	_max_count = _mk_count_spin(TIP_MAX)
	count_row.add_child(_max_count)

	# --- live expected-drops summary (read-only readout, inside the scroll so a long line never grows the tab) ---
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.modulate = Color(1, 1, 1, 0.85)
	_summary.tooltip_text = "What this table yields on average per roll -- an estimate from chance x count, not a playtest."
	body.add_child(_summary)

	_set_row_enabled(false)
	_update_buttons()

	# Editor-only: note a changed project filesystem so the NEXT reveal rescans (a table scaffolded by Blueprints, an
	# item added in the Items tab). Guarded: headless / GUT construct this tab bare and EditorInterface is unavailable.
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_filesystem_changed)

	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()  # lazy: scan items + tables on first reveal, not at panel construction (off-tree this is a no-op)


## Lazy first-reveal: run the disk scans + initial populate ONCE, the first time the tab is actually shown. Later
## reveals rescan only when the editor's filesystem changed meanwhile (`_fs_dirty`), keeping the open table by path.
func _on_visibility_changed() -> void:
	if is_visible_in_tree() and not _revealed:
		_revealed = true
		_fs_dirty = false
		# Scan items + populate the picker BEFORE opening a table: _reload_tables() opens the first table, which selects
		# row 0 -> _load_row -> _sync_item_pick; the rows model needs _item_paths/_item_labels ready or every item would
		# render as an off-scan transient row.
		_rescan_items()
		_reload_tables()
	elif is_visible_in_tree() and _fs_dirty:
		_fs_dirty = false
		_rescan_keep_open()


func _on_filesystem_changed() -> void:
	_fs_dirty = true


# --- host handoff -------------------------------------------------------------------------------------------------

## Panel handoff (cyber_panel.open_in_editor -> Host): find `path` among the loot tables on disk and open it here.
## Returns true when the file was found and the switch was made or is pending the unsaved-changes answer; false for
## a blank path, a bare off-tree tab (no host, and no viewport for the dialog -- the panel then falls back to the
## Inspector), or a file that is not a loot table under SCAN_ROOT. Marks the reveal latch itself: the visibility
## pass that follows a show_tab must not redo the first-reveal scan and clobber this pick.
func select_path(path: String) -> bool:
	if path.is_empty() or not is_inside_tree():
		return false
	_revealed = true
	_fs_dirty = false
	_rescan_items()
	_rescan_table_list()
	var open_path := _table.resource_path if _table != null else ""
	_fill_table_pick(open_path)  # the rescan replaced _tables: the picker's rows must never outlive the list they index
	if not _tables.has(path):
		_set_status("Couldn't open %s: it isn't a loot table under %s.%s" % [path.get_file(), SCAN_ROOT.get_file(), _scan_note()], "warn")
		return false
	var open_it := func() -> void:
		_fill_table_pick(path)
		_open_table(path)
	_guard_then(_table_pick_idx, open_it)
	return true


# --- table discovery / selection ----------------------------------------------------------------------------------

## First reveal: scan the table list and open the FIRST table (there is nothing open yet to keep).
func _reload_tables() -> void:
	_rescan_table_list()
	_open_first_table()


## Refresh (and the filesystem-changed reveal): re-read both lists and KEEP the open table, matched by path -- never
## by index, since a new file sorts anywhere. The open resource itself is not reloaded (that is Reload, which this
## tab does not offer). Only when the open file has VANISHED from disk does the rescan have to swap it out, and then
## a dirty table gets the unsaved-changes dialog first (Save writes the file back, so the re-run finds it again) and
## the swap SAYS the old file is gone -- a table silently replaced under the designer reads as lost work.
func _rescan_keep_open() -> void:
	_rescan_items()
	_rescan_table_list()
	var open_path := _table.resource_path if _table != null else ""
	# Refill FIRST, before any early return or dialog: the rescan replaced `_tables`, and a picker still holding the
	# previous scan's rows indexes the new list (a cancelled guard would then leave the two permanently crossed).
	_fill_table_pick(open_path)
	if _table != null and _tables.has(open_path):
		_load_row(_current_entry())  # the item rows were rebuilt -- re-point the row editor at the picked entry
		_set_status("Refreshed -- %s and %s found. %s stays open.%s" % [_count_text(_tables.size(), "loot table"), _count_text(_items.size(), "item"), open_path.get_file(), _scan_note()])
		return
	if _table != null and _dirty:
		_guard_then(_table_pick_idx, _rescan_keep_open)
		return
	var lost := open_path.get_file()
	_open_first_table()
	if not lost.is_empty():
		# Prepend the reason the open table went away, keeping an ERROR tone when the replacement open ALSO failed --
		# a "warn" must never paint over an "error".
		_set_status("%s is no longer on disk. %s" % [lost, _status_base], "error" if _status_kind == "error" else "warn")


## Re-read the loot-table list from disk (no widget or open-table changes -- the callers decide what to keep).
func _rescan_table_list() -> void:
	var rep := scan_tables_report()
	var paths: Array[String] = rep["paths"]
	_tables = paths
	_tables_skipped = rep["skipped"]


func _open_first_table() -> void:
	if _tables.is_empty():
		_fill_table_pick("")
		_clear_loaded()
		_set_status("No loot tables found under %s -- make one (the Blueprints tab's Enemy Pack, or the New tab), then press Refresh.%s" % [SCAN_ROOT.get_file(), _scan_note()], "warn")
		return
	_fill_table_pick(_tables[0])
	_open_table(_tables[0])


## Fill the table picker from `_tables` and point it at `want` ("" -> nothing selected). MUST be called in the same
## breath as every `_rescan_table_list()`: the picker's rows are indexes INTO `_tables`, so rows left over from an
## older scan would open the wrong file (or silently nothing) the next time one is picked.
## Routed through PickerRows.apply for its WIDTH GUARDS (fit_to_longest_item off + clip_text): a dropdown that sizes
## to its longest filename would widen the whole bottom panel. select() never emits item_selected, so this can't
## re-enter _on_table_selected.
func _fill_table_pick(want: String) -> void:
	var rows: Array = []
	for p in _tables:
		rows.append({"label": p.get_file().get_basename(), "value": p})
	if not want.is_empty() and not _tables.has(want):
		# The open table is no longer on disk (deleted or renamed while it was open). Show it as a DISABLED trailing
		# row -- the PickerRows anti-clobber idiom -- so the picker can never read as some OTHER table while this one
		# is still open and editable. It can't be clicked, and _on_table_selected only indexes the scanned `_tables`.
		rows.append({"label": want.get_file().get_basename(), "value": want, "disabled": true})
	PickerRows.apply(_table_pick, rows, want)
	if want.is_empty():
		_table_pick.select(-1)  # PickerRows.index_of falls back to row 0 for a blank value; "nothing open" must READ as nothing
	_table_pick_idx = _table_pick.selected


## Refresh button: say "Scanning...", grey the button, let the editor paint one frame (in-tree only -- a handler,
## never _init), then rescan keeping the open table. The disk walk reads every resource header under SCAN_ROOT, so
## the designer sees the tab respond before it finishes.
func _on_refresh_pressed() -> void:
	_refresh_btn.disabled = true
	_set_status("Scanning...")
	if is_inside_tree():
		await get_tree().process_frame
	_rescan_keep_open()
	_refresh_btn.disabled = false


## Picker change: open the picked table, through the unsaved-changes guard. Re-picking the OPEN table is a no-op (the
## popup emits item_selected even for the same row; asking "Save changes?" for a non-switch would be noise).
func _on_table_selected(idx: int) -> void:
	if idx < 0 or idx >= _tables.size():
		return
	var path := _tables[idx]
	var open_path := _table.resource_path if _table != null else ""
	if path == open_path:
		return
	_guard_then(_table_pick_idx, func() -> void: _open_table(path))


## Load `path` and make it the open table. Clears the dirty flag (a load is the clean baseline). A failed load nulls
## the open table, clears the lists and disables the row editor + Save, so the widgets never show a stale table.
func _open_table(path: String) -> void:
	_clear_dirty()
	var res := load(path)
	_table = res as LootTable
	if _table == null:
		_clear_loaded()
		_set_status("Couldn't open %s: the file wouldn't read -- it may still be importing. Press Refresh to try again." % path.get_file(), "error")
		return
	_table_pick_idx = _tables.find(path)
	_table_pick.select(_table_pick_idx)  # -1 when the picker was rebuilt without it; harmless
	_refresh_entries()
	_update_buttons()
	if _table.entries.is_empty():
		_set_row_enabled(false)
		_clear_row()
		_set_status("Opened %s -- no rows yet. %s%s" % [path.get_file(), EMPTY_HINT, _scan_note()])
	else:
		_entry_list.select(0)
		_on_row_selected(0)
		_set_status("Opened %s -- %s. %s%s" % [path.get_file(), _count_text(_table.entries.size(), "row"), ROW_HINT, _scan_note()])


## Forget the open table: null it, blank the rows list + row editor, grey Save. Used by a failed load and by an
## empty scan. The item picker is reset to "(none)" (not left empty) so a later row load has rows to select from.
func _clear_loaded() -> void:
	_table = null
	_clear_dirty()
	if _entry_list != null:
		_entry_list.clear()
	_refresh_summary()
	_set_row_enabled(false)
	_clear_row()
	_update_buttons()


## Recursively scan SCAN_ROOT for .tres/.res that load as a LootTable. The registries are non-@tool (empty in-editor),
## so we discover by type-checking; a TEXT .tres is pre-filtered on its `script_class="LootTable"` header first (the
## scan_disk.gd idiom) so the scan doesn't load -- and drag in the whole dependency graph of -- every resource in the
## project just to find a handful of tables. A BINARY .res has no readable header, so it still needs the load().
## Returns {paths: Array[String] (sorted), skipped: PackedStringArray} -- `skipped` are .tres that DECLARE LootTable
## but did not load as one (a broken script or a reimport in progress), so the tab can say so instead of silently
## listing one table fewer. A .res that turns out not to be a table is simply not a table, never "skipped".
static func scan_tables_report() -> Dictionary:
	var paths: Array[String] = []
	var skipped: Array[String] = []  # a plain Array so the recursion appends by REFERENCE (a packed array may copy)
	_scan_dir_for_tables(SCAN_ROOT, paths, skipped)
	paths.sort()
	return {"paths": paths, "skipped": PackedStringArray(skipped)}


## The plain sorted path list (kept as the static API other tools may call; the tab itself reads the report).
static func _scan_loot_tables() -> Array[String]:
	var rep := scan_tables_report()
	var paths: Array[String] = rep["paths"]
	return paths


static func _scan_dir_for_tables(dir_path: String, out: Array[String], skipped: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for d in dir.get_directories():
		_scan_dir_for_tables(dir_path.path_join(d), out, skipped)
	for f in dir.get_files():
		var fname := f.trim_suffix(".remap")
		if not (fname.ends_with(".tres") or fname.ends_with(".res")):
			continue
		var p := dir_path.path_join(fname)
		var is_text := fname.ends_with(".tres")
		# Cheap text-header gate before the expensive load(). A .tres that doesn't declare LootTable can't BE one.
		if is_text and not ("script_class=\"LootTable\"" in FileAccess.get_file_as_string(p)):
			continue
		var res := load(p)
		if res is LootTable:
			out.append(p)
		elif is_text:
			skipped.append(p)  # declared itself a LootTable but didn't load as one -- worth reporting, not hiding


# --- entries list -------------------------------------------------------------------------------------------------

func _refresh_entries() -> void:
	if _entry_list == null:
		return
	var sel := _selected_row()
	_entry_list.clear()
	if _table != null:
		var i := 0
		for e in _table.entries:
			_entry_list.add_item(_row_text(i, e))
			i += 1
	_refresh_summary()
	if sel >= 0 and sel < _entry_list.item_count:
		_entry_list.select(sel)
	_update_buttons()


func _on_row_selected(_idx: int) -> void:
	var e := _current_entry()
	if e == null:
		_set_row_enabled(false)
		_clear_row()
		_update_buttons()
		return
	_set_row_enabled(true)
	_load_row(e)
	_update_buttons()


## PUSH site (three-site rule): copy one entry into the row widgets with NO-SIGNAL setters, so a load can never
## re-enter the write handlers and stamp widget defaults onto the resource. A null entry leaves the widgets alone
## (callers pair it with _clear_row when they mean "blank").
## The widgets are a LOSSY view of the entry: a Range rounds every value it is handed to its `step` and clamps it to
## min/max, so what is shown can differ slightly from what is stored. That is why each widget writes back only its
## OWN field (see _on_chance_changed) -- the rounding must never leak into a field the designer did not touch.
func _load_row(e: LootEntry) -> void:
	if e == null:
		_set_row_enabled(false)
		return
	_sync_item_pick(e.item)
	_chance.set_value_no_signal(clampf(e.chance, 0.0, 1.0))
	_min_count.set_value_no_signal(e.min_count)
	_max_count.set_value_no_signal(e.max_count)


## RESET site (three-site rule): return the row widgets to the RESOURCE's defaults (LootEntry: no item, chance 1.0,
## count 1..1 -- NOT zeros), so a disabled/empty row never shows the previous table's last entry and a later push
## starts from the same baseline a fresh row has. No-signal setters, same reason as _load_row.
func _clear_row() -> void:
	if _item_pick != null:
		_sync_item_pick(null)
	if _chance != null:
		_chance.set_value_no_signal(1.0)
	if _min_count != null:
		_min_count.set_value_no_signal(1)
	if _max_count != null:
		_max_count.set_value_no_signal(1)


## WRITE site for Chance -- and ONLY Chance. Chance and the counts are deliberately on SEPARATE handlers: a shared
## one re-derived every field from its widget on every keystroke, and a SpinBox snaps what it is given to `step`
## (and clamps it to min/max), so nudging Min would quietly write the SNAPPED chance back over the authored one --
## an 0.02 chance became 0.00 through an edit that never touched Chance. Each widget now writes only its own field,
## so a value this tab can't represent exactly survives until the designer dials that field on purpose.
func _on_chance_changed(_value: float = 0.0) -> void:
	var e := _current_entry()
	if e == null:
		return
	e.chance = _chance.value
	_after_row_edit(e)
	_set_status("Changed row [%d] -- %s." % [_selected_row(), _entry_label(e)])


## WRITE site for Min / Max. Normalizes like LootTable.roll does (min >= 0, max >= min) and pushes the normalized
## counts back with no-signal setters so the SpinBoxes match what was stored (no max < min on disk).
func _on_counts_changed(_value: float = 0.0) -> void:
	var e := _current_entry()
	if e == null:
		return
	var lo := maxi(0, int(_min_count.value))
	var raw_hi := int(_max_count.value)
	var hi := maxi(lo, raw_hi)
	e.min_count = lo
	e.max_count = hi
	_min_count.set_value_no_signal(lo)
	_max_count.set_value_no_signal(hi)
	_after_row_edit(e)
	if raw_hi < lo:
		_set_status("Raised Max to %d -- Max can't be below Min." % hi, "warn")
	else:
		_set_status("Changed row [%d] -- %s." % [_selected_row(), _entry_label(e)])


## The shared tail of every per-row write: re-label the picked row in the list, re-total the summary, flag the
## unsaved changes. The caller owns the status line (each edit reports its own words).
func _after_row_edit(e: LootEntry) -> void:
	var i := _selected_row()
	if i >= 0:
		_entry_list.set_item_text(i, _row_text(i, e))
	_refresh_summary()
	_mark_dirty()


## WRITE site for the item. Every branch goes through PickerRows.resolve_pick, the anti-clobber table: index 0 ->
## clear (the one explicit, intended clear), an out-of-range index -> keep (a stale index from a dropdown rebuilt
## under a queued signal is refused, never guessed), an empty-valued row at index > 0 -> keep (re-picking the
## "(inline / unsaved)" row must NOT wipe an in-memory Item). Only a real, representable pick assigns.
func _on_item_selected(pick_idx: int) -> void:
	var i := _selected_row()
	var e := _current_entry()
	if e == null:
		return
	var pick: Dictionary = PickerRows.resolve_pick(_item_rows, pick_idx)
	var action := String(pick.get("action", "keep"))
	if action == "keep":
		return
	if action == "clear":
		e.item = null
		_entry_list.set_item_text(i, _row_text(i, e))
		_refresh_summary()
		_mark_dirty()
		_set_status("Cleared the item on row [%d] -- it drops nothing until you pick one." % i, "warn")
		return
	var path := String(pick.get("value", ""))
	var it := _item_for_path(path)
	if it == null:
		_set_status("Couldn't use %s: it isn't an item. Row [%d] was left unchanged." % [path.get_file(), i], "error")
		return
	e.item = it
	_entry_list.set_item_text(i, _row_text(i, e))
	_refresh_summary()
	_mark_dirty()
	_set_status("Changed row [%d] -- %s." % [i, _entry_label(e)])


# --- row mutation (delegates to pure ops) -------------------------------------------------------------------------

func _on_add() -> void:
	if _table == null:
		_set_status(TIP_NO_TABLE, "warn")
		return
	var idx := Ops.add_entry(_table)
	_refresh_entries()
	if idx >= 0:
		_entry_list.select(idx)
		_on_row_selected(idx)
	_mark_dirty()
	_set_status("Added row [%d] -- pick an item, then Save Loot Table." % idx)


func _on_remove() -> void:
	var i := _selected_row()
	if not Ops.remove_entry(_table, i):
		_set_status(TIP_NO_ROW if _table != null else TIP_NO_TABLE, "warn")
		return
	_refresh_entries()
	var n := _table.entries.size()
	if n > 0:
		var ni := mini(i, n - 1)
		_entry_list.select(ni)
		_on_row_selected(ni)
	else:
		_set_row_enabled(false)
		_clear_row()
		_update_buttons()
	_mark_dirty()
	if n > 0:
		_set_status("Removed row [%d] -- %s left." % [i, _count_text(n, "row")])
	else:
		_set_status("Removed row [%d] -- the table is empty. %s" % [i, EMPTY_HINT])


func _on_move(dir: int) -> void:
	var i := _selected_row()
	if _table == null or i < 0:
		_set_status(TIP_NO_ROW if _table != null else TIP_NO_TABLE, "warn")
		return
	var j := Ops.move_entry(_table, i, dir)
	if j == i:
		return  # already at that edge -- nothing moved, nothing to report
	_refresh_entries()
	_entry_list.select(j)
	_on_row_selected(j)
	_mark_dirty()
	_set_status("Moved row [%d] to [%d]." % [i, j])


# --- save ---------------------------------------------------------------------------------------------------------

func _on_save() -> void:
	_save_table()


## Write the open table back to its file. Existing bytes go to "<file>.bak" first (ContentSaveGuard), then the
## editor is told to reimport. Returns true on success; the status names the written file and its backup, or the
## plain reason it couldn't.
func _save_table() -> bool:
	if _table == null:
		_set_status(TIP_NO_TABLE, "warn")
		return false
	var path := _table.resource_path
	if path.is_empty():
		_set_status("Couldn't save this table: it has no file on disk yet -- save it from the Inspector first.", "error")
		return false
	var had_file := FileAccess.file_exists(path)
	var err := ContentSaveGuard.save_with_backup(_table, path)  # PL5: prior bytes -> .tres.bak first, so a mis-save is recoverable
	if err != OK:
		_set_status("Couldn't save %s: %s." % [path.get_file(), error_string(err)], "error")
		return false
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(path)
	_clear_dirty()
	if had_file:
		_set_status("Saved %s -- the previous version is beside it as %s." % [path.get_file(), ContentSaveGuard.backup_path(path).get_file()])
	else:
		_set_status("Saved %s -- first save, so no backup was made." % path.get_file())
	return true


# --- unsaved-changes guard ----------------------------------------------------------------------------------------

## Run `then` now when nothing is at stake; otherwise ask "Save changes to <file> first?" and run it after Save or
## Discard. Cancel restores the picker to `prev_idx` and runs nothing. A bare off-tree tab has no viewport to pop the
## dialog over, so it refuses rather than silently dropping edits (select_path already returns false off-tree; this
## is the belt-and-braces for a direct handler call under GUT). `then` is the LAST parameter on purpose: callers
## pass a lambda, and GDScript parses a lambda cleanly only as the final argument.
func _guard_then(prev_idx: int, then: Callable) -> void:
	if not _dirty or _table == null:
		then.call()
		return
	if not is_inside_tree():
		_set_status("Couldn't switch tables: %s has unsaved changes. Press Save Loot Table first." % _table_name(), "warn")
		return
	_pending = then
	_pending_prev_idx = prev_idx
	if _guard == null:
		_guard = ConfirmationDialog.new()
		_guard.title = "Unsaved changes"
		_guard.ok_button_text = "Save"
		_guard.cancel_button_text = "Cancel"
		_guard.add_button("Discard", true, "discard")
		_guard.confirmed.connect(_on_guard_save)
		_guard.custom_action.connect(_on_guard_custom)
		_guard.canceled.connect(_on_guard_cancel)
		add_child(_guard)
	_guard.dialog_text = "Save changes to %s first?" % _table_name()
	_guard_open = true
	_guard.popup_centered()


## Save: write the file, then make the pending switch. A FAILED save keeps the dirty table open (the status already
## says why) and puts the picker back, so nothing is lost behind a switch.
func _on_guard_save() -> void:
	if not _guard_open:
		return
	_guard_open = false
	var then := _pending
	_pending = Callable()
	if not _save_table():
		_table_pick.select(_pending_prev_idx)
		return
	var saved := _status_base  # keep the "Saved <file> -- ..." line in front of whatever the switch reports
	then.call()
	_set_status("%s %s" % [saved, _status_base], _status_kind)


## Discard: put the file's bytes back over the in-memory table (CACHE_MODE_REPLACE reloads INTO the cached instance,
## so anything else holding this table -- an NpcData.loot -- sees the disk state too), then make the pending switch.
## A custom dialog button does not close the dialog by itself, hence the explicit hide().
func _on_guard_custom(action: StringName) -> void:
	if action != &"discard" or not _guard_open:
		return
	_guard_open = false
	_guard.hide()
	var then := _pending
	_pending = Callable()
	_discard_changes()
	then.call()


func _on_guard_cancel() -> void:
	if not _guard_open:
		return
	_guard_open = false
	_pending = Callable()
	_table_pick.select(_pending_prev_idx)
	if _table != null:
		_set_status("Kept %s open -- its unsaved changes are still here." % _table_name())


func _discard_changes() -> void:
	if _table == null:
		return
	var path := _table.resource_path
	_clear_dirty()
	var fresh := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as LootTable
	if fresh == null:
		# The file is gone (or mid-reimport): there is nothing to restore, so the discarded table is simply dropped.
		_clear_loaded()
		_set_status("Discarded the changes to %s -- its file couldn't be re-read, so nothing is open." % path.get_file(), "warn")
		return
	_table = fresh


# --- item picker --------------------------------------------------------------------------------------------------

## Re-read the items through the ONE shared scan (core/item_scan.gd), keeping the parallel path/label arrays the
## PickerRows rows are built from. Files that exist but did not load are kept for the status line (_scan_note).
func _rescan_items() -> void:
	var rep := ItemScan.scan_report()
	var scanned: Array[Item] = rep["items"]
	_items.clear()
	_item_paths = PackedStringArray()
	_item_labels = PackedStringArray()
	for it in scanned:
		_items.append(it)
		_item_paths.append(it.resource_path)
		_item_labels.append(_item_label(it))
	_items_skipped = rep["skipped"]


## Fill the item dropdown and point it at `it`. The rows are REBUILT from the scan on every call, not just
## re-selected: PickerRows.path_rows appends at most ONE transient row (an item outside the items folder, or an
## inline sub-resource), so without the rebuild a transient left over from the PREVIOUS row would linger, still
## selectable, and clicking it would assign the wrong Item to a different row.
func _sync_item_pick(it: Item) -> void:
	if _item_pick == null:
		return
	var current := it.resource_path if it != null else ""
	_item_rows = PickerRows.path_rows(_item_paths, _item_labels, current, it != null)
	PickerRows.apply(_item_pick, _item_rows, current)
	if it != null and current.is_empty() and not _item_rows.is_empty():
		# An INLINE / unsaved Item has no path to match on, so apply() would leave the widget reading "(none)" while
		# a reference really IS assigned. path_rows appends its "(inline / unsaved)" row LAST for exactly this case;
		# select it by index. Display-only: resolve_pick refuses to write back through it.
		_item_pick.select(_item_rows.size() - 1)


## The scanned Item for `path`, or a fresh load for a path the scan doesn't hold (null when it isn't an Item).
func _item_for_path(path: String) -> Item:
	var idx := _item_paths.find(path)
	if idx >= 0 and idx < _items.size():
		return _items[idx]
	return load(path) as Item


## Kept as a static alias for other tools (dock_quest/quest_editor.gd calls LootEditor._scan_items()); the shared
## scan itself lives in core/item_scan.gd so a new folder rule lands in one place.
static func _scan_items() -> Array[Item]:
	return ItemScan.scan()


# --- helpers ------------------------------------------------------------------------------------------------------

func _refresh_summary() -> void:
	if _summary != null:
		_summary.text = Ops.summary_text(_table)


func _selected_row() -> int:
	if _entry_list == null:
		return -1
	var sel := _entry_list.get_selected_items()
	return -1 if sel.is_empty() else sel[0]


## The open table's file name for prose ("sample_loot.tres"), or "this table" for one that has no file yet.
func _table_name() -> String:
	if _table == null or _table.resource_path.is_empty():
		return "this table"
	return _table.resource_path.get_file()


## The picked row's entry, or null when no table is open / nothing is picked / the row is a null slot.
func _current_entry() -> LootEntry:
	var i := _selected_row()
	if _table == null or i < 0 or i >= _table.entries.size():
		return null
	return _table.entries[i]


func _set_row_enabled(on: bool) -> void:
	if _row_box != null:
		_row_box.modulate = Color(1, 1, 1, 1.0 if on else 0.45)
	for w in [_item_pick, _chance, _min_count, _max_count]:
		if w != null:
			_set_editable(w, on)


func _set_editable(w: Control, on: bool) -> void:
	if w is SpinBox:
		(w as SpinBox).editable = on
	elif w is OptionButton:
		(w as OptionButton).disabled = not on


## Grey every button that cannot apply right now and say what is missing in its tooltip; re-enable with the action
## tooltip otherwise. Called after every open / clear / row-selection change.
func _update_buttons() -> void:
	var has_table := _table != null
	var has_row := has_table and _selected_row() >= 0
	if _save_btn != null:
		_save_btn.disabled = not has_table
		_save_btn.tooltip_text = _save_tip() if has_table else TIP_NO_TABLE
	if _add_btn != null:
		_add_btn.disabled = not has_table
		_add_btn.tooltip_text = TIP_ADD if has_table else TIP_NO_TABLE
	for pair in [[_remove_btn, TIP_REMOVE], [_up_btn, TIP_UP], [_down_btn, TIP_DOWN]]:
		var b: Button = pair[0]
		var tip: String = pair[1]
		if b == null:
			continue
		b.disabled = not has_row
		b.tooltip_text = tip if has_row else (TIP_NO_ROW if has_table else TIP_NO_TABLE)


## Save's enabled tooltip names the file it writes and the backup it leaves (paths belong in tooltips, not status).
func _save_tip() -> String:
	if _table == null or _table.resource_path.is_empty():
		return "Write this table's rows back to its file. Writes the table file and keeps the previous version as a .bak beside it."
	return "Write this table's rows back to %s. Writes that file and keeps the previous version as %s." % [_table.resource_path, ContentSaveGuard.backup_path(_table.resource_path).get_file()]


func _mark_dirty() -> void:
	if _dirty:
		return
	_dirty = true
	_render_dirty()
	_render_status()


func _clear_dirty() -> void:
	if not _dirty:
		return
	_dirty = false
	_render_dirty()
	_render_status()


## "Save Loot Table*" while there are unsaved changes.
func _render_dirty() -> void:
	if _save_btn != null:
		_save_btn.text = SAVE_LABEL + ("*" if _dirty else "")


## Status contract: two visible lines, the FULL text mirrored into the tooltip on every write, colour by tone
## through a theme override (never bbcode), and the dirty suffix appended at render time so it never stacks.
func _set_status(s: String, kind: String = "") -> void:
	_status_base = s
	_status_kind = kind
	_render_status()


func _render_status() -> void:
	if _status == null:
		return
	var t := _status_base + (" (unsaved changes)" if _dirty else "")
	_status.text = t
	_status.tooltip_text = t
	match _status_kind:
		"error":
			_status.add_theme_color_override("font_color", ERROR_COLOR)
		"warn":
			_status.add_theme_color_override("font_color", WARN_COLOR)
		_:
			_status.remove_theme_color_override("font_color")


## " N file(s) couldn't be read: a.tres, b.tres." for the status, or "" when both scans were clean. Names the files
## (by file name) so a designer knows WHICH table or item is missing from the lists instead of guessing.
func _scan_note() -> String:
	var bad := PackedStringArray()
	for p in _tables_skipped:
		bad.append(String(p).get_file())
	for p in _items_skipped:
		bad.append(String(p).get_file())
	if bad.is_empty():
		return ""
	return " %s couldn't be read: %s." % [_count_text(bad.size(), "file"), ", ".join(bad)]


## "1 row" / "3 rows" -- editor tooling prose, never PlayerText.
static func _count_text(n: int, noun: String) -> String:
	return "%d %s%s" % [n, noun, "" if n == 1 else "s"]


func _row_text(i: int, e: LootEntry) -> String:
	return "[%d] %s" % [i, _entry_label(e)]


func _entry_label(e: LootEntry) -> String:
	if e == null:
		return "(empty slot)"
	if e.item == null:
		return "(no item) @ %.0f%%" % (e.chance * 100.0)
	return "%s ×%d–%d @ %.0f%%" % [_item_label(e.item), e.min_count, e.max_count, e.chance * 100.0]


static func _item_label(it: Item) -> String:
	if it == null:
		return "(none)"
	if not it.display_name.is_empty():
		return it.display_name
	if it.id != &"":
		return String(it.id)
	if it.resource_path != "":
		return it.resource_path.get_file().get_basename()
	return str(it)


## Callable LAST so a lambda handler parses cleanly as the final argument.
func _mk_button(text: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(cb)
	return b


func _mk_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _mk_count_spin(tip: String) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = 0
	s.max_value = 9999  # a sanity ceiling, not the resource's: a count this tab can't show is left alone unless
	s.step = 1          # the designer edits a count on purpose (see the split-handler note on _on_chance_changed)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.tooltip_text = tip
	s.value_changed.connect(_on_counts_changed)
	return s
