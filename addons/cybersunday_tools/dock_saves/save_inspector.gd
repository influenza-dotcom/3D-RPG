@tool
extends VBoxContainer

## CYBER SUNDAY -> Saves: a READ-ONLY inspector for the game's ConfigFile saves (the autosave, the quicksave and the
## three manual slots). Pick a slot to dump its sections + keys into a tree -- for answering "what actually
## persisted?" without opening the raw .cfg by hand. It only READS (no editing, no Save button, no file writes);
## the parsing lives in save_inspect.gd, which is PURE and GUT-tested.
##
## WHERE THE SAVES ARE: it reads the EDITOR's user:// data dir -- ProjectSettings.globalize_path("user://"), the
## project's app_userdata folder keyed by config/name -- so it shows saves written by a game launched FROM this
## editor (the toolbar's Play / Play From Spawn). An exported game writes to its own user dir, which the editor
## can't see. The picker tooltip and the "no saves here yet" line both name that folder, so a designer looking at
## an empty list knows exactly which folder to check.
##
## WHO READS IT: a designer who builds the game in the editor and does not read GDScript -- so the status names a
## slot by its label ("Autosave", "Slot 2") and a file by its FILE NAME, a read failure reports Godot's
## error_string() rather than a bare number, and the raw folder path rides on tooltips / the no-saves line only.
##
## LAYOUT CONTRACT (shared by every CYBER SUNDAY tab): the picker + Refresh bar and ONE status Label live OUTSIDE a
## ScrollContainer; the Tree lives INSIDE it. A TabContainer's minimum is the CURRENT tab's minimum, and the
## editor's bottom splitter keeps the height it grew to -- so a tab with a tall floor drags the whole panel up for
## every tab shown after it. The ScrollContainer's small floor is therefore the only vertical minimum this tab
## contributes, however many keys a save holds. The status is clamped to TWO lines (its tooltip carries the full
## text) so a long file name or error can never grow the head either.

const SaveInspect := preload("res://addons/cybersunday_tools/dock_saves/save_inspect.gd")
## Only its PICKER_MIN_WIDTH floor is used here. The slot picker's rows are a fixed list carrying a disabled flag
## per missing file, which `PickerRows.apply`'s "(none)"-row-at-index-0 model doesn't fit (there is no field to
## clear in a read-only viewer) -- so the width guards are set by hand in _init, mirroring what `apply` would set.
const PickerRows := preload("res://addons/cybersunday_tools/core/picker_rows.gd")

const COLOR_SECTION := Color(0.6, 0.8, 1.0)
const COLOR_WARN := Color(1.0, 0.82, 0.3)  # the tint the Stats / Reach status lines use for a refusal

## Height floors. The ScrollContainer floor is the tab's only vertical minimum (see LAYOUT CONTRACT above); the
## Tree's floor is smaller still so it never fights that fence. Both stay at or under the 110 px cap.
const BODY_MIN_HEIGHT := 110.0
const TREE_MIN_HEIGHT := 90.0

const MSG_IDLE := "Pick a save slot to see what it stored -- saves written by a game launched from this editor."

var _picker: OptionButton = null
var _refresh_btn: Button = null
var _tree: Tree = null
var _status: Label = null

## The absolute folder the saves live in: ProjectSettings.globalize_path("user://"), resolved ONCE at construction.
## Read from ProjectSettings, not EditorInterface, so it is safe off-tree and headless (where it resolves to the
## same app_userdata path the editor would use).
var _saves_dir := ""

## PL6: lazy first-reveal latch -- the user:// save scan runs on first reveal, not at panel construction.
var _revealed := false


func _init() -> void:
	name = "Saves"
	add_theme_constant_override("separation", 4)
	_saves_dir = ProjectSettings.globalize_path("user://")

	# --- head: OUTSIDE the scroll, so the picker + Refresh never scroll out from under the designer ---------------
	var bar := HBoxContainer.new()
	_picker = OptionButton.new()
	_picker.tooltip_text = "Which save to look at -- a slot marked 'empty' has no file yet. Saves folder: %s" % _saves_dir
	# Width guards, by hand (see the PickerRows note above): fit_to_longest_item defaults TRUE on OptionButton and
	# would make the longest row the bar's minimum width; clip_text drops the shown label from the minimum too; the
	# floor keeps the now-unanchored box from collapsing when every row is short.
	_picker.fit_to_longest_item = false
	_picker.clip_text = true
	_picker.custom_minimum_size = Vector2(PickerRows.PICKER_MIN_WIDTH, 0)
	_picker.item_selected.connect(_on_picked)
	bar.add_child(_picker)
	_refresh_btn = Button.new()
	_refresh_btn.text = "Refresh"
	# Re-reading the picked save is deliberate: this tab holds nothing the designer authored, so there is nothing to
	# lose, and re-reading is the only way to see a save the game just wrote without re-picking the slot.
	_refresh_btn.tooltip_text = "Re-list the save slots and re-read the picked one from disk. Read-only."
	_refresh_btn.pressed.connect(_refresh)
	bar.add_child(_refresh_btn)
	add_child(bar)

	# The status line is its OWN full-width row (it used to sit beside the picker and clip), autowraps, and is
	# clamped to TWO lines so a long file name or error can never grow the head; the full text is mirrored onto its
	# tooltip on every write (_set_status is the one writer).
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 2
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.modulate = Color(1, 1, 1, 0.75)
	_status.mouse_filter = Control.MOUSE_FILTER_PASS  # a Label ignores the mouse by default, which also hides its tooltip
	add_child(_status)

	# --- body: bounded + scrolled ----------------------------------------------------------------------------------
	# The Tree carries its own scrollbars, so this ScrollContainer is the HEIGHT FENCE, not a second scroller: its
	# custom_minimum_size is the only vertical minimum this tab contributes to the TabContainer, no matter how many
	# keys the save holds. The Tree keeps SIZE_EXPAND_FILL, which a Godot 4 ScrollContainer honours by stretching an
	# expanding child to the container's size -- so the Tree fills the panel and the outer scroll never engages.
	# Horizontal scrolling is DISABLED because a long value must never widen the bottom panel; the Tree elides and
	# scrolls those cells internally, and every value cell carries its full text as a tooltip.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, BODY_MIN_HEIGHT)
	add_child(scroll)

	_tree = Tree.new()
	_tree.hide_root = true
	_tree.columns = 2
	_tree.set_column_titles_visible(true)
	_tree.set_column_title(0, "Key")
	_tree.set_column_title(1, "Value")
	_tree.set_column_expand_ratio(0, 1)
	_tree.set_column_expand_ratio(1, 2)
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.custom_minimum_size = Vector2(0, TREE_MIN_HEIGHT)
	scroll.add_child(_tree)

	_set_status(MSG_IDLE)

	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()  # no-op off-tree (not visible); in the editor the real reveal fires the signal


## Lazy first-reveal: list the slots + read the picked save ONCE, the first time the tab is shown (not at construction).
func _on_visibility_changed() -> void:
	if is_visible_in_tree() and not _revealed:
		_revealed = true
		_refresh()


## Re-list the known slots (marking which exist on disk) and re-read the picked one, preserving the pick BY PATH --
## never by index -- so a slot that just appeared on disk can't shift the selection onto a different save.
func _refresh() -> void:
	var prev_path := ""
	if _picker.selected >= 0:
		prev_path = String(_picker.get_item_metadata(_picker.selected))
	_picker.clear()
	var found := -1
	for s in SaveInspect.known_saves():
		var path := String(s["path"])
		var exists: bool = FileAccess.file_exists(path)
		_picker.add_item("%s -- %s" % [String(s["label"]), "saved" if exists else "empty"])
		var idx := _picker.item_count - 1
		_picker.set_item_metadata(idx, path)
		_picker.set_item_disabled(idx, not exists)  # can't inspect what isn't there
		if exists and path == prev_path:
			found = idx
	if found >= 0:
		_picker.select(found)
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


## Load the picked save's ConfigFile and dump its sections (collapsible) -> keys/values into the tree. Fails soft:
## a missing / unreadable / unpicked save just writes the status line, never an editor error.
func _render_selected() -> void:
	_tree.clear()
	var root := _tree.create_item()
	var idx := _picker.selected
	if idx < 0:
		_set_status("No saves here yet -- launch the game from this editor (Play or Play From Spawn) to write one. Saves folder: %s" % _saves_dir)
		return
	var path := String(_picker.get_item_metadata(idx))
	var label := _slot_label(path)
	var file := path.get_file()
	if not FileAccess.file_exists(path):
		# Only reachable if the file vanished AFTER the list was built (a disabled row can't be picked).
		_set_status("Couldn't read %s: %s is no longer in the saves folder -- press Refresh to re-list." % [label, file], true)
		return
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		_set_status("Couldn't read %s: %s (%s) -- press Refresh to try again." % [label, error_string(err), file], true)
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
	_set_status("Read %s -- %s, %s (%s)." % [label, _count(model.size(), "section", "sections"), _count(keys, "key", "keys"), file])


## The designer-facing label ("Autosave", "Slot 2") for a save path, from the same list the picker is built from;
## falls back to the file name so a path outside the known list still reads as something rather than blank.
static func _slot_label(path: String) -> String:
	for s in SaveInspect.known_saves():
		if String(s["path"]) == path:
			return String(s["label"])
	return path.get_file()


## "1 key" / "37 keys" -- editor tooling, so a local two-form pick is fine (TextFormat.plural is for player prose).
static func _count(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]


## The ONE status writer: text + tooltip mirror (the Label clamps to two lines, so the tooltip carries the rest) and
## the warn tint via a theme colour override -- never bbcode, which a plain Label has none of.
func _set_status(msg: String, warn: bool = false) -> void:
	_status.text = msg
	_status.tooltip_text = msg
	if warn:
		_status.add_theme_color_override("font_color", COLOR_WARN)
	else:
		_status.remove_theme_color_override("font_color")
