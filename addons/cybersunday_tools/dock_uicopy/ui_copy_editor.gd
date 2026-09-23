@tool
extends VBoxContainer

## UI COPY — edit the player-facing strings that live in `scripts/ui/player_text.gd`, without opening GDScript.
##
## Why this tab exists: ~520 of the game's player-facing lines — HUD labels, prompts, toasts, menu wording, the
## whole ATM and gunsmith-bench vocabulary — are constants in one ~2,300-line script, and ~190 of them are still
## marked `[PH]`. The Text tab next door cannot reach them: it edits fields on `.tres` resources. So the single
## largest body of unwritten copy in the project was reachable only by editing code, which the authoring guide's
## first page promises a designer never has to do.
##
## WRITE CONTRACT: this is the only tab that rewrites a `.gd` file, so it is the most careful one. Nothing is
## written until **Save UI Copy**; the save VALIDATES every changed line first and refuses the whole batch if any
## one of them would break the game or the test suite (see `UiCopyOps.validate`); the previous file is copied to
## `player_text.gd.bak` before the new bytes land; and the report names how many lines changed and where the
## backup went. Only the quoted VALUE of a known one-line constant is ever touched — names are never renamed,
## lines are never reordered, and any line that is not a `const NAME := "..."` declaration is copied through
## untouched.
##
## What it deliberately cannot do: a prose literal written inline inside a function body. Those sit in
## ternaries, match arms and multi-line call expressions where a line-based rewrite would corrupt code. **List
## code-only lines** shows them so a writer can see what is stuck and name the function to ask about. As of
## 2026-09-15 that list is EMPTY — every template was lifted to a constant declared directly above its function
## — and `tests/test_devtools_ui_copy.gd` pins it at zero, so anything it shows is a regression to report.
##
## The `[PH]` marker is a SOURCE-side authorship signal, never player-visible (a runtime Translation scrubs it).
## The tab shows it exactly as authored, and deleting it is how a writer says "this line is written now" — so the
## tab never strips it automatically.

const ContentSaveGuard := preload("res://addons/cybersunday_tools/core/content_save_guard.gd")
const Ops := preload("res://addons/cybersunday_tools/dock_uicopy/ui_copy_ops.gd")

const SAVE_TIP := "Write the changed lines back into player_text.gd. Checks every line first and keeps a .bak. Writes: on Save only."
const SAVE_TIP_CLEAN := "Change some wording first."
const RELOAD_TIP := "Throw away unsaved edits and re-read the file from disk."
const SEARCH_TIP := "Filter by name or by what the line says."
const ONLY_PH_TIP := "Show only the lines still marked [PH] -- the ones nobody has written yet."
const INLINE_TIP := "Show the lines written inside functions. This tab can't edit those; they need a programmer to lift them out first."
const MSG_SCANNING := "Reading player_text.gd..."
const MSG_MISSING := "Couldn't find player_text.gd. Nothing to edit."
const WARN_COLOR := Color(1.0, 0.85, 0.4)
const ERROR_COLOR := Color(1.0, 0.55, 0.5)
## A value with a line break gets a real multi-line box; everything else a single-line field.
const MULTILINE_HEIGHT := 48.0

var _save_btn: Button
var _reload_btn: Button
var _inline_btn: Button
var _search: LineEdit
var _only_ph: CheckBox
var _list_box: VBoxContainer
var _status: Label
var _inline_dialog: AcceptDialog = null

## One editable line: {"name", "loaded" (value as read from disk), "edit" (LineEdit|TextEdit), "row" (Control),
## "group", "doc", "haystack"}. Dirty is `edit.text != loaded`, per field, exactly like the Text tab — so a save
## writes only what actually changed and a reload moves the baseline before the widget.
var _entries: Array = []
var _inline: Array = []
var _revealed := false
var _status_base := ""
var _status_kind := ""


func _init() -> void:
	name = "UI Copy"
	add_theme_constant_override("separation", 4)

	var btn_row := HBoxContainer.new()
	_save_btn = Button.new()
	_save_btn.pressed.connect(_on_save)
	btn_row.add_child(_save_btn)
	_reload_btn = Button.new()
	_reload_btn.text = "Reload"
	_reload_btn.tooltip_text = RELOAD_TIP
	_reload_btn.pressed.connect(_on_reload)
	btn_row.add_child(_reload_btn)
	_inline_btn = Button.new()
	_inline_btn.text = "List code-only lines"
	_inline_btn.tooltip_text = INLINE_TIP
	_inline_btn.pressed.connect(_on_list_inline)
	btn_row.add_child(_inline_btn)
	_only_ph = CheckBox.new()
	_only_ph.text = "Only unwritten"
	_only_ph.tooltip_text = ONLY_PH_TIP
	_only_ph.button_pressed = true
	_only_ph.toggled.connect(_on_filter_toggled)
	btn_row.add_child(_only_ph)
	_search = LineEdit.new()
	_search.placeholder_text = "Search..."
	_search.tooltip_text = SEARCH_TIP
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(_on_search_changed)
	btn_row.add_child(_search)
	add_child(btn_row)

	add_child(HSeparator.new())

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
	_refresh_dirty_ui()

	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()  # lazy: read the file on first reveal, not now


## Lazy first-reveal. Later reveals do NOT re-read: this tab holds staged text that only exists in its widgets
## (there is no shared cached Resource to fall back on), so an automatic reload would silently discard writing.
func _on_visibility_changed() -> void:
	if is_visible_in_tree() and not _revealed:
		_revealed = true
		_rescan()


# --- scan / build -----------------------------------------------------------------------------------------

func _rescan() -> void:
	for c in _list_box.get_children():
		c.queue_free()
	_entries.clear()
	_inline.clear()
	if not FileAccess.file_exists(Ops.SOURCE_PATH):
		_set_status(MSG_MISSING, "error")
		_refresh_dirty_ui()
		return
	var text := FileAccess.get_file_as_string(Ops.SOURCE_PATH)
	var parsed := Ops.parse(text)
	_inline = Ops.inline_literals(text)
	var group := ""
	for e in parsed:
		var g := Ops.group_of(String(e["name"]))
		if g != group:
			group = g
			var head := Label.new()
			head.text = group
			_list_box.add_child(head)
		_list_box.add_child(_build_row(e))
	_set_status(Ops.summary(parsed, _inline.size()))
	_apply_filter()
	_refresh_dirty_ui()


func _build_row(e: Dictionary) -> Control:
	var row := VBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value := String(e["value"])
	var lbl := Label.new()
	lbl.text = String(e["name"])
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(lbl)
	# The `##` block above the constant is the only place the hard constraints live -- "ONE LINE, and keep any
	# re-wording inside one", "keep every line under ~100 chars: it paints on an 11px band". A copy editor cannot
	# infer those, so they are shown as help rather than left in the source for nobody to read.
	var doc := String(e["doc"])
	if doc != "":
		var help := Label.new()
		help.text = doc
		help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		help.max_lines_visible = 3
		help.tooltip_text = doc
		help.modulate = Color(1, 1, 1, 0.6)
		row.add_child(help)
	var edit: Control
	if value.contains("\n"):
		var te := TextEdit.new()
		te.custom_minimum_size = Vector2(0, MULTILINE_HEIGHT)
		te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		te.text = value
		te.text_changed.connect(_on_edited)
		edit = te
	else:
		var le := LineEdit.new()
		le.text = value
		le.text_changed.connect(_on_line_edited)
		edit = le
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	_entries.append({
		"name": String(e["name"]),
		"loaded": value,
		"edit": edit,
		"row": row,
		"doc": doc,
		"haystack": (String(e["name"]) + " " + value).to_lower(),
	})
	return row


# --- edit / dirty -----------------------------------------------------------------------------------------

## LineEdit.text_changed passes the new text, TextEdit.text_changed passes nothing — two handlers rather than one
## with a default argument, so neither signal shape can drift into the other.
func _on_line_edited(_new_text: String) -> void:
	_refresh_dirty_ui()
	_render_status()


func _on_edited() -> void:
	_refresh_dirty_ui()
	_render_status()


func _dirty_entries() -> Array:
	var out: Array = []
	for e in _entries:
		var edit = e["edit"]
		if edit != null and String(edit.text) != String(e["loaded"]):
			out.append(e)
	return out


func _refresh_dirty_ui() -> void:
	var n := _dirty_entries().size()
	_save_btn.text = "Save UI Copy (%d)" % n if n > 0 else "Save UI Copy"
	_save_btn.disabled = n == 0
	_save_btn.tooltip_text = SAVE_TIP if n > 0 else SAVE_TIP_CLEAN
	_inline_btn.disabled = _inline.is_empty()


# --- filter -----------------------------------------------------------------------------------------------

func _on_search_changed(_t: String) -> void:
	_apply_filter()


func _on_filter_toggled(_pressed: bool) -> void:
	_apply_filter()


## Default to the unwritten lines only. 347 rows is a lot to scroll past to find the 87 that need writing, and a
## dirty row always stays visible so a filter change can never hide unsaved work.
func _apply_filter() -> void:
	var needle := _search.text.strip_edges().to_lower()
	var only_ph := _only_ph.button_pressed
	for e in _entries:
		var row: Control = e["row"]
		if row == null:
			continue
		var edit = e["edit"]
		var dirty := edit != null and String(edit.text) != String(e["loaded"])
		var is_ph := String(e["loaded"]).begins_with("[PH] ")
		var hit := needle == "" or String(e["haystack"]).contains(needle)
		row.visible = dirty or (hit and (not only_ph or is_ph))


# --- save -------------------------------------------------------------------------------------------------

## Validate EVERY changed line before writing ANY of them. A partial write of a batch would leave the file in a
## state the writer did not ask for and could not easily identify, and the `.bak` is only one deep.
func _on_save() -> void:
	var dirty := _dirty_entries()
	if dirty.is_empty():
		_set_status("Nothing changed.", "warn")
		return
	var edits := {}
	for e in dirty:
		var value := String(e["edit"].text)
		var problem := Ops.validate(String(e["name"]), value, String(e["loaded"]))
		if problem != "":
			_set_status("Didn't save: %s" % problem, "error")
			return
		edits[String(e["name"])] = value
	if not FileAccess.file_exists(Ops.SOURCE_PATH):
		_set_status(MSG_MISSING, "error")
		return
	var text := FileAccess.get_file_as_string(Ops.SOURCE_PATH)
	var result := Ops.apply(text, edits)
	var count := int(result["count"])
	if count == 0:
		_set_status("Didn't save: couldn't find those lines in the file any more. Press Reload.", "error")
		return
	# ResourceSaver can't write a script, so this is ContentSaveGuard's backup rule applied by hand -- the same
	# shape `panel_audit/fix_ops.gd` uses for the only other .gd rewrite in the plugin.
	var bak := ContentSaveGuard.backup_path(Ops.SOURCE_PATH)
	var cp := DirAccess.copy_absolute(Ops.SOURCE_PATH, bak)
	if cp != OK:
		push_warning("UI Copy: couldn't back up %s -> %s (%s)" % [Ops.SOURCE_PATH, bak, error_string(cp)])
		_set_status("Didn't save: couldn't make a backup first (%s)." % error_string(cp), "error")
		return
	var f := FileAccess.open(Ops.SOURCE_PATH, FileAccess.WRITE)
	if f == null:
		_set_status("Didn't save: couldn't open the file to write (%s)." % error_string(FileAccess.get_open_error()), "error")
		return
	f.store_string(String(result["text"]))
	f.close()
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(Ops.SOURCE_PATH)
	for e in dirty:
		e["loaded"] = String(e["edit"].text)
	_refresh_dirty_ui()
	_apply_filter()
	_set_status("Saved %s. Previous version kept as %s." % [
		Ops.count_of(count, "line", "lines"), bak.get_file()])


func _on_reload() -> void:
	var n := _dirty_entries().size()
	_revealed = true
	_rescan()
	if n > 0:
		_set_status("Reloaded from disk -- %s of unsaved wording thrown away." % Ops.count_of(n, "line", "lines"), "warn")


# --- the read-only half -----------------------------------------------------------------------------------

## A multi-line report never goes in the status Label (it is clamped to two lines on a short panel) -- it goes to a
## dialog window, which can scroll past the panel's own height.
func _on_list_inline() -> void:
	if _inline.is_empty():
		_set_status("No lines are written inside functions.", "warn")
		return
	if not is_inside_tree():
		_set_status("%s written inside functions; open the tab to list them." % Ops.count_of(_inline.size(), "line is", "lines are"), "warn")
		return
	if _inline_dialog == null:
		_inline_dialog = AcceptDialog.new()
		_inline_dialog.title = "Lines written inside functions"
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(520, 320)
		var body := Label.new()
		body.name = "Body"
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(500, 0)
		scroll.add_child(body)
		_inline_dialog.add_child(scroll)
		add_child(_inline_dialog)
	var lines := PackedStringArray()
	lines.append("These %d lines are written inside functions, so this tab can't edit them. A programmer has to lift each one out into a named constant first; then it shows up above." % _inline.size())
	lines.append("")
	for item in _inline:
		lines.append("%s (line %d):  %s" % [String(item["func_name"]), int(item["line"]) + 1, String(item["text"])])
	var body_label := _inline_dialog.find_child("Body", true, false)
	if body_label != null:
		body_label.text = "\n".join(lines)
	_inline_dialog.popup_centered()


# --- handoff / status -------------------------------------------------------------------------------------

## `cyber_panel.open_in_editor` duck-types this. The tab edits exactly one known file, so it accepts only that
## path and refuses anything else rather than pretending to open it.
func select_path(path: String) -> bool:
	if path != Ops.SOURCE_PATH or not is_inside_tree():
		return false
	_revealed = true
	_rescan()
	return true


func _set_status(msg: String, kind: String = "") -> void:
	_status_base = msg
	_status_kind = kind
	_render_status()


func _render_status() -> void:
	if _status == null:
		return
	var msg := _status_base
	var n := _dirty_entries().size()
	if n > 0:
		msg += " (unsaved changes)"
	_status.text = msg
	_status.tooltip_text = msg
	if _status_kind == "error":
		_status.add_theme_color_override("font_color", ERROR_COLOR)
	elif _status_kind == "warn":
		_status.add_theme_color_override("font_color", WARN_COLOR)
	else:
		_status.remove_theme_color_override("font_color")
