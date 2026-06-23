@tool
extends VBoxContainer

## Tuning browser dock: ONE place to find + open every global tuning resource. These are the GameSettings groups
## -- the .tres files in res://resources/tuning/ that every system reads its numbers through (GameSettings.economy.*,
## GameSettings.camera.*, ...). Click / double-click a row and it opens in the Inspector (EditorInterface.edit_resource),
## so a designer never has to hunt the FileSystem dock for the right .tres.
##
## SOURCE OF TRUTH: the GameSettings autoload binds each group as `var <name>: <Class> = preload(".tres")`, and EVERY
## one of those .tres lives in res://resources/tuning/ (verified against managers/GameSettings.gd). Reflecting the
## autoload would mean instantiating a non-@tool Node at edit time; the .tres folder IS the same set and is pure to
## scan, so we scan the folder -- the exact idiom ItemDb / item_placer_dock use for resources/items/. The scan is a
## static helper (_scan_tuning) so the GUT test can assert it returns real paths WITHOUT touching EditorInterface.

## Folder holding the GameSettings tuning groups (the .tres each `GameSettings.<group>` preloads).
const TUNING_DIR := "res://resources/tuning"

var _list: ItemList = null
var _entries: Array[Dictionary] = []   ## [{ path:String, name:String, desc:String, res:Resource }]
var _status: Label = null


func _init() -> void:
	name = "Tuning"
	add_theme_constant_override("separation", 4)

	var head := Label.new()
	head.text = "Global tuning resources (GameSettings groups)"
	add_child(head)

	var hint := Label.new()
	hint.text = "Double-click to open in the Inspector."
	hint.modulate = Color(1, 1, 1, 0.6)
	add_child(hint)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = Vector2(0, 90)  # small floor so the dock can shrink on a short display
	_list.item_activated.connect(_on_activated)   # double-click = open
	_list.item_selected.connect(_on_activated)    # single-click also opens (cheap, idempotent)
	add_child(_list)

	var refresh := Button.new()
	refresh.text = "Refresh list"
	refresh.pressed.connect(_reload)
	add_child(refresh)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = Color(1, 1, 1, 0.75)
	add_child(_status)

	_reload()


func _reload() -> void:
	_entries = _scan_tuning()
	if _list == null:
		return
	_list.clear()
	for e in _entries:
		var label := String(e.get("name", "?"))
		var desc := String(e.get("desc", ""))
		var idx := _list.add_item(label if desc == "" else "%s  --  %s" % [label, desc])
		_list.set_item_tooltip(idx, String(e.get("path", "")))
	if _status != null:
		_status.text = "%d tuning group(s) in %s." % [_entries.size(), TUNING_DIR]


## Scan resources/tuning/ for tuning Resources. Each .tres there is a GameSettings group (verified against
## managers/GameSettings.gd). PURE -- no EditorInterface -- so the GUT test can call it. Returns rows sorted by name,
## each carrying the loaded Resource + a one-line description pulled from the resource's class.
static func _scan_tuning() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(TUNING_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		var fname := f.trim_suffix(".remap")   # exported builds may append .remap to packed resources
		if not (fname.ends_with(".tres") or fname.ends_with(".res")):
			continue
		var path := TUNING_DIR.path_join(fname)
		var res := load(path) as Resource
		if res == null:
			continue
		out.append({
			"path": path,
			"name": fname.get_basename(),
			"desc": _describe(res),
			"res": res,
		})
	out.sort_custom(func(a, b): return String(a["name"]) < String(b["name"]))
	return out


## A short per-row description: the resource's script class_name (the GameSettings group type), e.g. "EconomySettings".
## Falls back to the base class name. PURE -- safe in the headless test.
static func _describe(res: Resource) -> String:
	if res == null:
		return ""
	var scr: Variant = res.get_script()
	if scr is GDScript:
		var gname := String((scr as GDScript).get_global_name())
		if gname != "":
			return gname
	return res.get_class()


## Open the selected tuning resource in the Inspector. EDITOR-ONLY (EditorInterface) -- not exercised by the test.
func _on_activated(idx: int) -> void:
	if idx < 0 or idx >= _entries.size():
		return
	var res: Resource = _entries[idx].get("res", null)
	if res == null:
		if _status != null:
			_status.text = "That row has no loaded resource."
		return
	EditorInterface.edit_resource(res)
	if _status != null:
		_status.text = "Opened %s in the Inspector." % String(_entries[idx].get("name", "?"))
