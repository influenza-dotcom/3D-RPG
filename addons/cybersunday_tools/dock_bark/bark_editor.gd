@tool
extends VBoxContainer

## BARK EDIT — write the combat and reaction lines an NPC shouts, one bark per line.
##
## Why this tab exists: barks are the only major body of player-facing prose in the project with NO authoring
## surface. They are `Array[String]` fields on a `BarkSet`, and array-nested text is explicitly out of scope for
## the Text tab (`dock_text/text_sources.gd`), so the only way to write one was the raw Inspector array widget —
## click +, click the new row, type, repeat, for 21 categories. Every shipped BarkSet is empty, and
## `DESIGN.md` Appendix B ranks barks as the FIRST writing task. This turns each category into a plain text box
## where one line is one bark.
##
## WRITE CONTRACT: read-only until the writer presses **Save Barks**. Nothing on disk changes on a keystroke, on
## a category switch, or on a file switch — a switch with unsaved work pops Save / Discard / Cancel first.
## `ContentSaveGuard` keeps the previous version as a one-deep `.tres.bak` before every overwrite.
##
## THE EMPTY-CATEGORY RULE, which the tab states in words because it is the one thing a writer gets wrong: an
## empty category does NOT mean the NPC is silent. It means "use the built-in default lines" (`npc.gd._bark_pool`
## falls through to its `BARK_*` consts). So filling one category on a profile overrides only that category. To
## make an NPC genuinely silent you need a different mechanism, not an empty box.
##
## Editing happens on the SHARED cached Resource (`load()` hands every tab the same object), which is why the
## dirty marker and the "(unsaved changes)" suffix exist — a Ctrl+S in the Inspector would persist staged text.
## Never `CACHE_MODE_REPLACE` here except on the deliberate Discard path.

const ContentSaveGuard := preload("res://addons/cybersunday_tools/core/content_save_guard.gd")
const PickerRows := preload("res://addons/cybersunday_tools/core/picker_rows.gd")
const Ops := preload("res://addons/cybersunday_tools/dock_bark/bark_edit_ops.gd")

const SAVE_TIP := "Write the edited lines back to the bark file. Keeps the previous version as a .bak. Writes: on Save only."
const SAVE_TIP_CLEAN := "Edit some lines first."
const RELOAD_TIP := "Throw away unsaved edits and re-read the bark file from disk."
const PICKER_TIP := "Which bark set to edit. Files live in the barks folder; every NPC archetype points at one."
const MSG_SCANNING := "Scanning..."
const MSG_EMPTY := "No bark sets found. Make one with New, then come back here."
const MSG_PICK := "Pick a bark set to start writing."
const EMPTY_NOTE := "An empty box means the NPC falls back to its built-in lines for that category -- not silence."
const WARN_COLOR := Color(1.0, 0.85, 0.4)
const ERROR_COLOR := Color(1.0, 0.55, 0.5)
## One text box is three lines tall before it starts growing. Tall enough to see a short bark list whole, short
## enough that all 21 fit the bottom panel's scroller without the writer losing the Save button.
const BOX_MIN_HEIGHT := 54.0

## Plain-English hints per category, keyed by the property name on `BarkSet`. A category NOT in here still renders
## (the list comes off the resource, see `Ops.categories`) — it just shows its name alone, which is the degrade
## that keeps a newly-added bark category visible instead of hidden.
const HINTS := {
	"spot": "Sees an enemy and calls it out.",
	"hurt": "Badly wounded.",
	"reload": "Reloading and wants cover.",
	"combat_end": "Lost sight of the target.",
	"lost_interest": "Gave up searching.",
	"search": "Hunting for someone it lost.",
	"flee": "Broke and ran.",
	"check_body": "Found a corpse.",
	"greet": "Player looks at it, no trouble yet.",
	"thanks": "Player helped it.",
	"death_ally": "Watched one of its own die.",
	"death_approve": "Watched an enemy of its die.",
	"death_question": "A bystander, unsure about a killing.",
	"warn_attack": "Player hit it but has not started a fight yet.",
	"aggro": "That last hit started the fight.",
	"pardon": "Player holstered; grudge dropped.",
	"pardon_fleeing": "Same, but caught mid-run. Falls back to the line above when empty.",
	"music_awful": "Hears a track it hates.",
	"music_meh": "Hears a track it can live with.",
	"music_good": "Hears a track it likes.",
	"music_great": "Hears its favourite track.",
}

var _save_btn: Button
var _reload_btn: Button
var _picker: OptionButton
var _list_box: VBoxContainer
var _status: Label

var _rows: Array = []                 ## PickerRows model for _picker
var _paths: PackedStringArray = PackedStringArray()
var _res: Resource = null             ## the open BarkSet (shared cached instance)
var _path := ""                       ## its resource_path, the key every re-point uses (never a row index)
var _boxes: Dictionary = {}           ## category name -> TextEdit
var _dirty := false
var _revealed := false
var _fs_dirty := false
var _status_base := ""
var _status_kind := ""
var _guard: ConfirmationDialog = null
var _guard_then: Callable = Callable()
var _guard_prev_idx := -1


func _init() -> void:
	name = "Bark Edit"
	add_theme_constant_override("separation", 4)

	var btn_row := HBoxContainer.new()
	_save_btn = Button.new()
	_save_btn.pressed.connect(_on_save)
	btn_row.add_child(_save_btn)
	_reload_btn = Button.new()
	_reload_btn.text = "Reload"
	_reload_btn.tooltip_text = RELOAD_TIP
	_reload_btn.pressed.connect(_on_reload_pressed)
	btn_row.add_child(_reload_btn)
	_picker = OptionButton.new()
	_picker.tooltip_text = PICKER_TIP
	# The width guards `PickerRows.apply` also sets, applied HERE too because the first fill is lazy: until the tab
	# is revealed the picker is empty, and an empty OptionButton still defaults `fit_to_longest_item` TRUE, which
	# propagates a content minimum width out through the scroller and widens the whole bottom panel.
	_picker.fit_to_longest_item = false
	_picker.clip_text = true
	_picker.item_selected.connect(_on_picked)
	btn_row.add_child(_picker)
	add_child(btn_row)

	add_child(HSeparator.new())

	# Everything that grows lives in here: 21 text boxes are far taller than the bottom panel, and a TabContainer
	# takes its minimum height from the CURRENT tab, so an unscrolled body would push Save off the screen.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 90)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_list_box)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 2
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.modulate = Color(1, 1, 1, 0.75)
	add_child(_status)
	_set_status(MSG_SCANNING)
	_render_dirty()

	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()  # lazy: scan on first reveal, not now


## Lazy first-reveal, then a rescan only when the filesystem changed under us — never mid-edit, because a rescan
## rebuilds the picker and would drop staged text.
func _on_visibility_changed() -> void:
	if is_visible_in_tree() and not _revealed:
		_revealed = true
		_rescan()
	elif is_visible_in_tree() and _revealed and _fs_dirty and not _dirty:
		_fs_dirty = false
		_rescan()


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE and Engine.is_editor_hint():
		var fs := EditorInterface.get_resource_filesystem()
		if not fs.filesystem_changed.is_connected(_on_filesystem_changed):
			fs.filesystem_changed.connect(_on_filesystem_changed)


func _on_filesystem_changed() -> void:
	_fs_dirty = true


# --- scan -------------------------------------------------------------------------------------------------

## Walk the bark folder and refill the picker, re-pointing at the SAME PATH rather than the same row index — a
## file added or removed alphabetically above the open one shifts every index below it.
func _rescan() -> void:
	_paths = scan_paths()
	var labels := PackedStringArray()
	for p in _paths:
		labels.append(p.get_file().get_basename())
	_rows = PickerRows.path_rows(_paths, labels, _path, _res != null)
	PickerRows.apply(_picker, _rows, _path)
	if _paths.is_empty():
		_clear_list()
		_set_status(MSG_EMPTY, "warn")
		_render_dirty()
		return
	if _path == "":
		_clear_list()
		_set_status(MSG_PICK)
		_render_dirty()
		return
	_load_path(_path)


## Every BarkSet on disk, sorted. A pure static so a test can compare it against the folder without a dock.
static func scan_paths() -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(Ops.BARK_DIR):
		return out
	var names := PackedStringArray(DirAccess.get_files_at(Ops.BARK_DIR))
	names.sort()
	for n in names:
		var fname := String(n).trim_suffix(".remap")
		var ext := fname.get_extension().to_lower()
		if ext != "tres" and ext != "res":
			continue
		var path: String = Ops.BARK_DIR.path_join(fname)
		if not out.has(path):
			out.append(path)
	return out


# --- load / build -----------------------------------------------------------------------------------------

func _clear_list() -> void:
	for c in _list_box.get_children():
		c.queue_free()
	_boxes.clear()


## Open one bark file and build a text box per category. `replace` is the Discard path ONLY: a plain `load()`
## hands back the shared cached object every other tab is holding, so replacing it any other time would wipe
## somebody else's unsaved edits.
func _load_path(path: String, replace: bool = false) -> void:
	# ResourceLoader.load, not the `load()` shorthand: only the former takes a cache mode.
	var mode := ResourceLoader.CACHE_MODE_REPLACE if replace else ResourceLoader.CACHE_MODE_REUSE
	var res := ResourceLoader.load(path, "", mode)
	if res == null:
		_clear_list()
		_res = null
		_set_status("Couldn't open %s: the file didn't load." % path.get_file(), "error")
		_render_dirty()
		return
	_res = res
	_path = path
	_dirty = false
	_build_rows()
	_set_status(_summary_line())
	_render_dirty()


func _build_rows() -> void:
	_clear_list()
	var cats := Ops.categories(_res)
	if cats.is_empty():
		var warn := Label.new()
		warn.text = "That file has no bark categories. Is it really a bark set?"
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list_box.add_child(warn)
		return
	var note := Label.new()
	note.text = EMPTY_NOTE
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(1, 1, 1, 0.7)
	_list_box.add_child(note)
	var group := ""
	for c in cats:
		var cname := String(c.get("name", ""))
		var cgroup := String(c.get("group", ""))
		if cgroup != group:
			group = cgroup
			var head := Label.new()
			head.text = group if group != "" else "Other"
			_list_box.add_child(head)
		_list_box.add_child(_build_row(cname))


func _build_row(cname: String) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl := Label.new()
	var hint := String(HINTS.get(cname, ""))
	lbl.text = cname if hint == "" else "%s  --  %s" % [cname, hint]
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(lbl)
	var te := TextEdit.new()
	te.custom_minimum_size = Vector2(0, BOX_MIN_HEIGHT)
	te.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	te.placeholder_text = "One bark per line."
	# Grow with the content where the engine offers it, so a long list does not hide its own tail behind an inner
	# scrollbar nested in the panel's scroller. Guarded: the property is not worth a hard version dependency.
	if "scroll_fit_content_height" in te:
		te.set("scroll_fit_content_height", true)
	te.text = Ops.array_to_lines(_res.get(cname))
	te.text_changed.connect(_on_text_changed)
	box.add_child(te)
	_boxes[cname] = te
	return box


# --- edit / dirty -----------------------------------------------------------------------------------------

## Any box changed. Dirty is recomputed against the RESOURCE rather than latched true, so deleting a stray blank
## line the writer just typed puts the document back to clean instead of leaving a guard they cannot clear.
func _on_text_changed() -> void:
	var was := _dirty
	_dirty = _compute_dirty()
	if _dirty != was:
		_render_dirty()
	_render_status()


func _compute_dirty() -> bool:
	if _res == null:
		return false
	for cname in _boxes:
		var te: TextEdit = _boxes[cname]
		if te != null and Ops.differs(te.text, _res.get(String(cname))):
			return true
	return false


func _render_dirty() -> void:
	var can := _dirty and _res != null
	_save_btn.text = "Save Barks *" if can else "Save Barks"
	_save_btn.disabled = not can
	_save_btn.tooltip_text = SAVE_TIP if can else SAVE_TIP_CLEAN
	_reload_btn.disabled = _res == null


# --- picker -----------------------------------------------------------------------------------------------

func _on_picked(idx: int) -> void:
	var intent := PickerRows.resolve_pick(_rows, idx)
	var action := String(intent.get("action", "keep"))
	if action == "keep":
		return
	var target := String(intent.get("value", ""))
	if _dirty:
		_ask_unsaved(func() -> void: _apply_pick(action, target))
		return
	_apply_pick(action, target)


func _apply_pick(action: String, target: String) -> void:
	if action == "clear":
		_res = null
		_path = ""
		_dirty = false
		_clear_list()
		_set_status(MSG_PICK)
		_render_dirty()
		return
	_load_path(target)


# --- unsaved guard ----------------------------------------------------------------------------------------

## Pop Save / Discard / Cancel before anything that would drop staged text. Built lazily: `_init` runs off-tree
## (GUT constructs every tab bare), and a dialog needs the tree to pop.
func _ask_unsaved(then: Callable) -> void:
	_guard_then = then
	_guard_prev_idx = PickerRows.index_of(_rows, _path)
	if not is_inside_tree():
		_set_status("Save or discard your edits first.", "warn")
		return
	if _guard == null:
		_guard = ConfirmationDialog.new()
		_guard.dialog_text = "Save changes first?"
		_guard.ok_button_text = "Save"
		_guard.add_button("Discard", true, "discard")
		_guard.confirmed.connect(_on_guard_save)
		_guard.custom_action.connect(_on_guard_custom)
		_guard.canceled.connect(_on_guard_cancel)
		add_child(_guard)
	_guard.dialog_text = "Save changes to %s first?" % _path.get_file()
	_guard.popup_centered()


func _on_guard_save() -> void:
	_on_save()
	_run_guarded()


func _on_guard_custom(action: StringName) -> void:
	if String(action) != "discard":
		return
	if _guard != null:
		_guard.hide()
	_discard()
	_run_guarded()


## Cancel restores the picker BY PATH — a row index captured before the popup can point at a different file if
## the filesystem changed while the dialog was up.
func _on_guard_cancel() -> void:
	_guard_then = Callable()
	if _picker != null and _guard_prev_idx >= 0 and _guard_prev_idx < _picker.item_count:
		_picker.select(_guard_prev_idx)


func _run_guarded() -> void:
	var then := _guard_then
	_guard_then = Callable()
	if then.is_valid():
		then.call()


## Discard really discards: re-read the file with the cache REPLACED, so the staged text on the shared instance
## is gone rather than merely un-shown.
func _discard() -> void:
	_dirty = false
	if _path != "":
		_load_path(_path, true)


func _on_reload_pressed() -> void:
	if _path == "":
		_set_status(MSG_PICK)
		return
	if _dirty:
		_ask_unsaved(func() -> void: _discard())
		return
	_discard()


# --- save -------------------------------------------------------------------------------------------------

func _on_save() -> void:
	if _res == null:
		_set_status("Nothing open to save.", "warn")
		return
	if _path == "":
		_set_status("Couldn't save: that bark set has no file yet.", "error")
		return
	for cname in _boxes:
		var te: TextEdit = _boxes[cname]
		if te == null:
			continue
		_res.set(String(cname), Ops.lines_to_array(te.text))
	var had_file := FileAccess.file_exists(_path)
	var err := ContentSaveGuard.save_with_backup(_res, _path)
	if err != OK:
		push_warning("Bark Edit: couldn't save %s: %s" % [_path, error_string(err)])
		_set_status("Couldn't save %s: %s." % [_path.get_file(), error_string(err)], "error")
		return
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(_path)
	_dirty = false
	_render_dirty()
	var bak := ContentSaveGuard.backup_path(_path).get_file() if had_file else ""
	var msg := Ops.save_report(_path.get_file(), Ops.line_count(_res), Ops.filled_count(_res), bak)
	var users := _users_line()
	if users != "":
		msg += " " + users
	_set_status(msg)


## Who actually reads this file — reported once per Save, the `quest_editor` "start sites" idiom. A writer filling
## a bark set that no archetype points at gets silence in game and no error anywhere, so the answer belongs here.
func _users_line() -> String:
	var users := PackedStringArray()
	var dir := "res://resources/characters"
	if DirAccess.dir_exists_absolute(dir):
		for n in DirAccess.get_files_at(dir):
			var fname := String(n).trim_suffix(".remap")
			if fname.get_extension().to_lower() != "tres":
				continue
			var res := load(dir.path_join(fname))
			if res == null:
				continue
			var bs = res.get("bark_set")
			if bs is Resource and (bs as Resource).resource_path == _path:
				users.append(fname.get_basename())
	if users.is_empty():
		return "No NPC archetype points at it yet, so nothing says these lines."
	return "Used by %s." % ", ".join(users)


# --- handoff ----------------------------------------------------------------------------------------------

## Open one file by path — the duck-typed entry point `cyber_panel.open_in_editor` calls when a BarkSet is
## double-clicked in Browse / Refs / New. Rescans and refills the picker in the same breath so the tab is not
## left showing a file the picker does not list. Returns false off-tree (GUT), where there is nothing to show.
func select_path(path: String) -> bool:
	if path == "" or not ResourceLoader.exists(path):
		return false
	if not is_inside_tree():
		return false
	_revealed = true
	_path = path
	_rescan()
	return _res != null


# --- status -----------------------------------------------------------------------------------------------

func _summary_line() -> String:
	if _res == null:
		return MSG_PICK
	var filled := Ops.filled_count(_res)
	var total := Ops.categories(_res).size()
	if filled == 0:
		return "%s is empty -- every one of its %d categories falls back to the built-in lines." % [_path.get_file(), total]
	return "%s -- %d of %d categories written, %d lines." % [_path.get_file(), filled, total, Ops.line_count(_res)]


func _set_status(msg: String, kind: String = "") -> void:
	_status_base = msg
	_status_kind = kind
	_render_status()


func _render_status() -> void:
	if _status == null:
		return
	var msg := _status_base
	if _dirty:
		msg += " (unsaved changes)"
	_status.text = msg
	_status.tooltip_text = msg
	if _status_kind == "error":
		_status.add_theme_color_override("font_color", ERROR_COLOR)
	elif _status_kind == "warn":
		_status.add_theme_color_override("font_color", WARN_COLOR)
	else:
		_status.remove_theme_color_override("font_color")
