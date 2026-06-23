@tool
extends VBoxContainer

## "Loot Edit" tab for the CYBER SUNDAY bottom panel: edit a LootTable's drop entries WITHOUT the raw inspector.
## Pick a LootTable .tres (scanned off-disk — the ItemDb/registries are non-@tool, empty in-editor), edit each row
## with plain widgets (item OptionButton scanning resources/items/, a 0..1 chance SpinBox, min/max count SpinBoxes),
## Add/Remove/Up/Down rows, watch a live "expected drops" summary, and SAVE (ResourceSaver.save + update_file so the
## editor reimports). All mutation is delegated to LootEditOps (pure, GUT-tested); this file is THIN editor glue only.
##
## Designer-first idiom: a new editor is a NEW @tool Control that owns its tab `name` with a SMALL minimum size so it
## never bloats the panel. NO graph-drag, NO hand-written uid:// (ResourceSaver mints it).

const Ops := preload("res://addons/cybersunday_tools/dock_loot/loot_edit_ops.gd")

const ITEMS_DIR := "res://resources/items"
const SCAN_ROOT := "res://resources"

var _table_pick: OptionButton = null
var _entry_list: ItemList = null
var _item_pick: OptionButton = null
var _chance: SpinBox = null
var _min_count: SpinBox = null
var _max_count: SpinBox = null
var _row_box: VBoxContainer = null
var _summary: Label = null
var _status: Label = null

var _tables: Array[String] = []        ## resource paths of discovered LootTable .tres, parallel to _table_pick items
var _items: Array[Item] = []           ## scanned items, parallel to _item_pick items (index 0 = "(none)")
var _table: LootTable = null           ## the currently-open table
var _suppress := false                 ## guard: ignore widget signals while we re-populate them programmatically


func _init() -> void:
	name = "Loot Edit"
	custom_minimum_size = Vector2(0, 110)  # small floor so the bottom panel can still shrink on a short display
	add_theme_constant_override("separation", 4)

	var head := Label.new()
	head.text = "Edit a LootTable's drops"
	add_child(head)

	# --- table picker row ---
	var pick_row := HBoxContainer.new()
	add_child(pick_row)
	_table_pick = OptionButton.new()
	_table_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_table_pick.item_selected.connect(_on_table_selected)
	pick_row.add_child(_table_pick)
	var refresh := Button.new()
	refresh.text = "Refresh"
	refresh.pressed.connect(_reload_tables)
	pick_row.add_child(refresh)

	# --- entries list ---
	_entry_list = ItemList.new()
	_entry_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_entry_list.custom_minimum_size = Vector2(0, 70)
	_entry_list.item_selected.connect(_on_row_selected)
	add_child(_entry_list)

	# --- row buttons ---
	var btns := HBoxContainer.new()
	add_child(btns)
	_add_btn(btns, "Add", _on_add)
	_add_btn(btns, "Remove", _on_remove)
	_add_btn(btns, "Up", func(): _on_move(-1))
	_add_btn(btns, "Down", func(): _on_move(1))

	# --- per-row editor ---
	_row_box = VBoxContainer.new()
	add_child(_row_box)

	var item_row := HBoxContainer.new()
	_row_box.add_child(item_row)
	item_row.add_child(_mk_label("Item"))
	_item_pick = OptionButton.new()
	_item_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_pick.item_selected.connect(_on_item_selected)
	item_row.add_child(_item_pick)

	var chance_row := HBoxContainer.new()
	_row_box.add_child(chance_row)
	chance_row.add_child(_mk_label("Chance"))
	_chance = SpinBox.new()
	_chance.min_value = 0.0
	_chance.max_value = 1.0
	_chance.step = 0.05
	_chance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chance.value_changed.connect(func(_v): _on_field_changed())
	chance_row.add_child(_chance)

	var count_row := HBoxContainer.new()
	_row_box.add_child(count_row)
	count_row.add_child(_mk_label("Min"))
	_min_count = _mk_count_spin()
	count_row.add_child(_min_count)
	count_row.add_child(_mk_label("Max"))
	_max_count = _mk_count_spin()
	count_row.add_child(_max_count)

	# --- summary + save + status ---
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.modulate = Color(1, 1, 1, 0.85)
	add_child(_summary)

	var save := Button.new()
	save.text = "Save table"
	save.pressed.connect(_on_save)
	add_child(save)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = Color(1, 1, 1, 0.7)
	add_child(_status)

	_reload_tables()
	_items = _scan_items()
	_populate_item_pick()
	_set_row_enabled(false)


# --- table discovery / selection ----------------------------------------------------------------------------------

func _reload_tables() -> void:
	_tables = _scan_loot_tables()
	if _table_pick == null:
		return
	_table_pick.clear()
	for p in _tables:
		_table_pick.add_item(p.get_file().get_basename())
	if _tables.is_empty():
		_set_status("No LootTable .tres found under %s." % SCAN_ROOT)
		_table = null
		_refresh_entries()
		_set_row_enabled(false)
		return
	_table_pick.select(0)
	_open_table(_tables[0])


func _on_table_selected(idx: int) -> void:
	if idx < 0 or idx >= _tables.size():
		return
	_open_table(_tables[idx])


func _open_table(path: String) -> void:
	_table = load(path) as LootTable
	if _table == null:
		_set_status("Failed to load %s as a LootTable." % path)
		_refresh_entries()
		_set_row_enabled(false)
		return
	_set_status("Editing %s — %d row(s)." % [path.get_file(), _table.entries.size()])
	_refresh_entries()
	if _table.entries.is_empty():
		_set_row_enabled(false)
		_clear_row()
	else:
		_entry_list.select(0)
		_on_row_selected(0)


## Recursively scan SCAN_ROOT for .tres/.res that load as a LootTable. The registries are non-@tool (empty in-editor),
## so we discover by loading + type-checking, exactly like item_placer_dock scans items.
static func _scan_loot_tables() -> Array[String]:
	var out: Array[String] = []
	_scan_dir_for_tables(SCAN_ROOT, out)
	out.sort()
	return out


static func _scan_dir_for_tables(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for d in dir.get_directories():
		_scan_dir_for_tables(dir_path.path_join(d), out)
	for f in dir.get_files():
		var fname := f.trim_suffix(".remap")
		if not (fname.ends_with(".tres") or fname.ends_with(".res")):
			continue
		var p := dir_path.path_join(fname)
		var res := load(p)
		if res is LootTable:
			out.append(p)


# --- entries list -------------------------------------------------------------------------------------------------

func _refresh_entries() -> void:
	if _entry_list == null:
		return
	var sel := _selected_row()
	_entry_list.clear()
	if _table != null:
		var i := 0
		for e in _table.entries:
			_entry_list.add_item("[%d] %s" % [i, _entry_label(e)])
			i += 1
	_refresh_summary()
	if sel >= 0 and sel < _entry_list.item_count:
		_entry_list.select(sel)


func _on_row_selected(_idx: int) -> void:
	var i := _selected_row()
	if _table == null or i < 0 or i >= _table.entries.size():
		_set_row_enabled(false)
		_clear_row()
		return
	_set_row_enabled(true)
	_load_row(_table.entries[i])


func _load_row(e: LootEntry) -> void:
	if e == null:
		_set_row_enabled(false)
		return
	_suppress = true
	_select_item_in_pick(e.item)
	_chance.value = clampf(e.chance, 0.0, 1.0)
	_min_count.value = e.min_count
	_max_count.value = e.max_count
	_suppress = false


## Blank the per-row widgets so a disabled/empty row never shows the previous table's last entry. _load_row(null)
## early-returns without touching the widgets, so the reset must be explicit.
func _clear_row() -> void:
	_suppress = true
	if _item_pick != null:
		_item_pick.select(0)
	if _chance != null:
		_chance.value = 0.0
	if _min_count != null:
		_min_count.value = 0
	if _max_count != null:
		_max_count.value = 0
	_suppress = false


func _on_field_changed() -> void:
	if _suppress:
		return
	var i := _selected_row()
	if _table == null or i < 0 or i >= _table.entries.size():
		return
	var e := _table.entries[i]
	if e == null:
		return
	e.chance = _chance.value
	var lo := maxi(0, int(_min_count.value))
	var hi := maxi(lo, int(_max_count.value))
	e.min_count = lo
	e.max_count = hi
	# Reflect the normalized counts back so the SpinBoxes match what we stored (no max<min on disk).
	_suppress = true
	_min_count.value = lo
	_max_count.value = hi
	_suppress = false
	_entry_list.set_item_text(i, "[%d] %s" % [i, _entry_label(e)])
	_refresh_summary()


func _on_item_selected(pick_idx: int) -> void:
	if _suppress:
		return
	var i := _selected_row()
	if _table == null or i < 0 or i >= _table.entries.size():
		return
	var e := _table.entries[i]
	if e == null:
		return
	e.item = null if pick_idx <= 0 else _items[pick_idx - 1]
	_entry_list.set_item_text(i, "[%d] %s" % [i, _entry_label(e)])
	_refresh_summary()


# --- row mutation (delegates to pure ops) -------------------------------------------------------------------------

func _on_add() -> void:
	if _table == null:
		_set_status("Pick a LootTable first.")
		return
	var idx := Ops.add_entry(_table)
	_refresh_entries()
	if idx >= 0:
		_entry_list.select(idx)
		_on_row_selected(idx)
	_set_status("Added row %d — pick an item, then Save." % idx)


func _on_remove() -> void:
	var i := _selected_row()
	if not Ops.remove_entry(_table, i):
		_set_status("Select a row to remove.")
		return
	_refresh_entries()
	var n := _table.entries.size()
	if n > 0:
		var ni := mini(i, n - 1)
		_entry_list.select(ni)
		_on_row_selected(ni)
	else:
		_set_row_enabled(false)
	_set_status("Removed row %d." % i)


func _on_move(dir: int) -> void:
	var i := _selected_row()
	var j := Ops.move_entry(_table, i, dir)
	if j == i:
		return
	_refresh_entries()
	_entry_list.select(j)
	_on_row_selected(j)


# --- save ---------------------------------------------------------------------------------------------------------

func _on_save() -> void:
	if _table == null:
		_set_status("Nothing to save — pick a LootTable.")
		return
	var path := _table.resource_path
	if path.is_empty():
		_set_status("This table has no resource_path on disk — can't save.")
		return
	var err := ResourceSaver.save(_table, path)
	if err != OK:
		_set_status("Save FAILED (err %d) for %s." % [err, path])
		return
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(path)
	_set_status("Saved %s." % path.get_file())


# --- item picker --------------------------------------------------------------------------------------------------

func _populate_item_pick() -> void:
	if _item_pick == null:
		return
	_item_pick.clear()
	_item_pick.add_item("(none)")  # index 0 — leaves entry.item null
	for it in _items:
		_item_pick.add_item(_item_label(it))


func _select_item_in_pick(it: Item) -> void:
	if _item_pick == null:
		return
	if it == null:
		_item_pick.select(0)
		return
	var idx := _items.find(it)
	_item_pick.select(0 if idx < 0 else idx + 1)


## Scan resources/items/ for Item .tres/.res (mirrors ItemDb's boot scan; the autoload itself is empty in-editor).
static func _scan_items() -> Array[Item]:
	var out: Array[Item] = []
	var dir := DirAccess.open(ITEMS_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		var fname := f.trim_suffix(".remap")
		if not (fname.ends_with(".tres") or fname.ends_with(".res")):
			continue
		var it := load(ITEMS_DIR.path_join(fname)) as Item
		if it != null:
			out.append(it)
	return out


# --- helpers ------------------------------------------------------------------------------------------------------

func _refresh_summary() -> void:
	if _summary != null:
		_summary.text = Ops.summary_text(_table)


func _selected_row() -> int:
	if _entry_list == null:
		return -1
	var sel := _entry_list.get_selected_items()
	return -1 if sel.is_empty() else sel[0]


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


func _set_status(s: String) -> void:
	if _status != null:
		_status.text = s


func _entry_label(e: LootEntry) -> String:
	if e == null:
		return "(null entry)"
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


func _add_btn(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)


func _mk_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _mk_count_spin() -> SpinBox:
	var s := SpinBox.new()
	s.min_value = 0
	s.max_value = 9999
	s.step = 1
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(_v): _on_field_changed())
	return s
