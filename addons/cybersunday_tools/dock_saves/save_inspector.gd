@tool
extends VBoxContainer

## CYBER SUNDAY → Saves: a READ-ONLY inspector for GameState's ConfigFile saves (the autosave, the quicksave, and
## the three manual slots). Pick a slot to dump its sections + keys into a tree — for debugging "what actually
## persisted?" without opening the raw .cfg. It only READS (no editing); the parsing lives in save_inspect.gd.
##
## NOTE: it reads the EDITOR's user:// data dir, so it shows saves written by a game launched FROM the editor
## (Play / Play-From-Spawn). A standalone export writes to its own user dir, which the editor can't see.

const SaveInspect := preload("res://addons/cybersunday_tools/dock_saves/save_inspect.gd")

const COLOR_SECTION := Color(0.6, 0.8, 1.0)

var _picker: OptionButton = null
var _tree: Tree = null
var _summary: Label = null


## PL6: lazy first-reveal latch — the user:// save scan runs on first reveal, not at panel construction.
var _revealed := false


func _init() -> void:
	name = "Saves"
	add_theme_constant_override("separation", 4)

	var bar := HBoxContainer.new()
	_picker = OptionButton.new()
	_picker.tooltip_text = "Which GameState save to inspect (disabled = not on disk yet)."
	_picker.item_selected.connect(_on_picked)
	bar.add_child(_picker)
	var refresh := Button.new()
	refresh.text = "Refresh"
	refresh.tooltip_text = "Re-list the slots + reload the selected save from disk."
	refresh.pressed.connect(_refresh)
	bar.add_child(refresh)
	_summary = Label.new()
	_summary.modulate = Color(1, 1, 1, 0.7)
	bar.add_child(_summary)
	add_child(bar)

	_tree = Tree.new()
	_tree.hide_root = true
	_tree.columns = 2
	_tree.set_column_titles_visible(true)
	_tree.set_column_title(0, "Key")
	_tree.set_column_title(1, "Value")
	_tree.set_column_expand_ratio(0, 1)
	_tree.set_column_expand_ratio(1, 2)
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.custom_minimum_size = Vector2(0, 90)
	add_child(_tree)

	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()  # lazy: list + read user:// saves on first reveal, not at panel construction (mirrors content_browser)


## Lazy first-reveal: list the slots + read the selected save ONCE, the first time the tab is shown (not at construction).
func _on_visibility_changed() -> void:
	if is_visible_in_tree() and not _revealed:
		_revealed = true
		_refresh()


## Re-list the known slots (marking which exist on disk) and re-render the selection, preserving it where possible.
func _refresh() -> void:
	var prev := _picker.selected
	_picker.clear()
	for s in SaveInspect.known_saves():
		var exists: bool = FileAccess.file_exists(s["path"])
		_picker.add_item("%s — %s" % [s["label"], "saved" if exists else "empty"])
		var idx := _picker.item_count - 1
		_picker.set_item_metadata(idx, s["path"])
		_picker.set_item_disabled(idx, not exists)  # can't inspect what isn't there
	if prev >= 0 and prev < _picker.item_count and not _picker.is_item_disabled(prev):
		_picker.select(prev)
	else:
		_select_first_existing()
	_render_selected()


func _select_first_existing() -> void:
	for i in _picker.item_count:
		if not _picker.is_item_disabled(i):
			_picker.select(i)
			return
	_picker.select(-1)  # nothing on disk yet


func _on_picked(_idx: int) -> void:
	_render_selected()


## Load the selected save's ConfigFile and dump its sections (collapsible) -> keys/values into the tree. Fails soft:
## a missing / unreadable / unselected save just updates the summary line, never errors.
func _render_selected() -> void:
	_tree.clear()
	var root := _tree.create_item()
	var idx := _picker.selected
	if idx < 0:
		_summary.text = "No saves on disk yet — launch the game (▶ Play) to create one."
		return
	var path := String(_picker.get_item_metadata(idx))
	if not FileAccess.file_exists(path):
		_summary.text = "%s — not on disk." % path
		return
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		_summary.text = "%s — failed to read (err %d)." % [path, err]
		return
	var model := SaveInspect.config_model(cfg)
	var keys := 0
	for sec in model:
		var sec_item := _tree.create_item(root)
		sec_item.set_text(0, "[%s]" % str(sec["section"]))
		sec_item.set_custom_color(0, COLOR_SECTION)
		for r in sec["rows"]:
			keys += 1
			var it := _tree.create_item(sec_item)
			it.set_text(0, str(r["key"]))
			it.set_text(1, str(r["value"]))
			it.set_tooltip_text(1, str(r["value"]))  # full value on hover (the cell may truncate)
	_summary.text = "%s — %d section(s), %d key(s)." % [path, model.size(), keys]
