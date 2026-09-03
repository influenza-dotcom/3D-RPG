@tool
extends VBoxContainer

## CYBER SUNDAY -> Check -> Refs: the READ-ONLY "what points at this file?" viewer, i.e. the delete / rename impact
## preview. Type a file (or select one in the FileSystem dock and press Use Selected) and it lists every scene,
## resource and script that references it -- by path OR by uid -- with the referring line as the "where". Unlike
## Godot's own View Owners it also catches scripts that load()/preload() the file. It only READS: the walk lives in
## ref_scan.gd; this file is the presentation and the one-step command surface.
##
## ONE STEP, FOUR ENTRANCES. Find Refs, Enter in the path box, Use Selected (fills the box AND searches -- one click,
## not two) and the host handoff select_path(path) (core/host.gd -> cyber_panel.gd; the Stats tab hands its
## unreferenced rows here) all land in _run_search(), which validates the path, says "Scanning...", greys both
## buttons and yields ONE frame in-tree so that status paints before the synchronous project walk holds the main
## thread. select_path validates first and reports whether the file was accepted, because the host reads the bool
## straight back -- the rows themselves arrive a frame later.
##
## LAYOUT CONTRACT (shared by every tab): the path row and the ONE status Label sit OUTSIDE a ScrollContainer that
## fences the Tree's height, so this tab's minimum never grows with the result count. A TabContainer's minimum is
## the CURRENT tab's minimum, and the editor's bottom splitter keeps the height it grew to -- so a tab that once
## asked for a tall minimum leaves the panel tall until the designer drags it back. Rows are the file NAME (the full
## path in the tooltip) and the referring line cut to LINE_CHARS (the whole line in the tooltip); horizontal
## scrolling is disabled, so nothing here can widen the bottom panel.
##
## OFF-TREE: GUT and the headless probe construct this bare (.new(), no parent, no tree), so _init touches no
## EditorInterface and never awaits; those calls live in the button handlers and in _run_search's in-tree-only yield.
## The Control `name` stays "Refs" -- the panel keys its tab title and its show_tab routing on it.

const RefScan := preload("res://addons/cybersunday_tools/dock_refs/ref_scan.gd")
const Host := preload("res://addons/cybersunday_tools/core/host.gd")

const COLOR_FILE := Color(0.6, 0.85, 1.0)
const COLOR_LINE := Color(1, 1, 1, 0.6)
const TINT_WARN := Color(1.0, 0.82, 0.3)
const TINT_OK := Color(0.6, 1.0, 0.6)

## The ScrollContainer's height floor: the only vertical minimum this tab contributes (see the layout contract).
const BODY_MIN_HEIGHT := 100
## A referring line is cut to this many characters in the Tree; the full line lives in the row's tooltip.
const LINE_CHARS := 80

const MSG_IDLE := "Type or select a file, then Find Refs -- lists every scene, resource and script that points at it, so you know what breaks before deleting or renaming."
const MSG_SCANNING := "Scanning..."
const MSG_NO_PATH := "Type a file first, or select one in the FileSystem dock and press Use Selected."
const MSG_NO_SELECTION := "Select a file in the FileSystem dock first, then Use Selected."
const PATH_TIP := "The file to check, by its path inside the project folder (for example resources/items/healthpack.tres). Enter runs the search."
const USE_SELECTED_TIP := "Fills the path from the file selected in the FileSystem dock and finds its references straight away. Read-only."
const FIND_TIP := "Lists every scene, resource and script that points at this file. Read-only."

var _target: LineEdit = null
var _use_btn: Button = null
var _find_btn: Button = null
var _status: Label = null
var _tree: Tree = null
## True from "Scanning..." until the rows are rendered: both buttons grey, and a second request (Enter while the
## button is still down, a handoff landing mid-walk) is dropped instead of queuing a second project walk.
var _scanning := false


func _init() -> void:
	name = "Refs"
	add_theme_constant_override("separation", 4)

	# --- head: the path box + the two commands, outside the scroll ----------------------------------------------
	var bar := HBoxContainer.new()
	_target = LineEdit.new()
	_target.placeholder_text = "Path of the file to check"
	_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target.tooltip_text = PATH_TIP
	_target.text_changed.connect(_on_target_changed)
	_target.text_submitted.connect(_on_target_submitted)
	bar.add_child(_target)
	_use_btn = Button.new()
	_use_btn.text = "Use Selected"
	_use_btn.pressed.connect(_on_use_selected)
	bar.add_child(_use_btn)
	_find_btn = Button.new()
	_find_btn.text = "Find Refs"
	_find_btn.pressed.connect(_on_find_pressed)
	bar.add_child(_find_btn)
	add_child(bar)

	# --- the ONE status Label, outside the scroll: two lines on screen, the whole message in its tooltip --------
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 2
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.modulate = Color(1, 1, 1, 0.75)
	_status.mouse_filter = Control.MOUSE_FILTER_PASS  # a Label ignores the mouse by default, which also hides its tooltip
	add_child(_status)

	# --- body: bounded + scrolled ---------------------------------------------------------------------------------
	# The Tree carries its own scrollbars, so this ScrollContainer is the HEIGHT FENCE, not a second scroller: its
	# custom_minimum_size is the only vertical minimum this tab contributes, however many rows the Tree holds. The
	# Tree keeps SIZE_EXPAND_FILL, which a Godot 4 ScrollContainer honours by stretching an expanding child to the
	# container's size -- so the Tree fills the panel and the outer scroll never engages. Horizontal scrolling is
	# DISABLED because a long ext_resource row must never widen the bottom panel; rows are cut (short_line) and carry
	# the full text in their tooltip.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, BODY_MIN_HEIGHT)
	add_child(scroll)

	_tree = Tree.new()
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.custom_minimum_size = Vector2(0, 90)
	_tree.item_activated.connect(_on_activated)  # double-click / Enter on a row opens that file
	scroll.add_child(_tree)

	_set_status(MSG_IDLE)
	_update_buttons()


# ================================================================================================================
# ENTRANCES -- every one of them lands in _run_search()
# ================================================================================================================

## Typing in the path box only re-evaluates the buttons; the search waits for Enter / Find Refs.
func _on_target_changed(_text: String) -> void:
	_update_buttons()


## Enter in the path box runs the search.
func _on_target_submitted(_text: String) -> void:
	_run_search()


func _on_find_pressed() -> void:
	_run_search()


## Use Selected: fill the path from the FileSystem dock's selection and search AT ONCE (one click, not two). A
## folder selection is refused by _validated_target with a message that says so. Editor-only (EditorInterface) --
## a handler, never _init.
func _on_use_selected() -> void:
	var sel := EditorInterface.get_selected_paths()
	if sel.is_empty():
		_set_status(MSG_NO_SELECTION, TINT_WARN)
		return
	_target.text = sel[0]  # the text setter does NOT emit text_changed, so the buttons are re-evaluated by hand
	_update_buttons()
	_run_search()


## Host seam (core/host.gd -> cyber_panel.gd): fill the path box with `path` and search at once. true when the file
## exists and the search started; false when the path is blank, names a folder or nothing on disk, or a search is
## already running -- the box still shows the path and the status says why, so the designer can fix it and press
## Find Refs. Synchronous by contract (the host reads the bool straight back); in-tree the rows arrive a frame later.
func select_path(path: String) -> bool:
	_target.text = path.strip_edges()
	_update_buttons()
	if _scanning:
		return false
	if _validated_target().is_empty():
		return false
	_run_search()
	return true


# ================================================================================================================
# THE SEARCH
# ================================================================================================================

## The one search path. Validates the box (a refusal writes its own status and stops here), then says "Scanning...",
## greys both buttons, yields one frame IN-TREE ONLY so that paints before the synchronous project walk (a bare
## GUT / headless construction never awaits), runs ref_scan's walk and renders the rows.
func _run_search() -> void:
	if _scanning:
		return
	var path := _validated_target()
	if path.is_empty():
		return
	_scanning = true
	_update_buttons()
	_tree.clear()
	_set_status(MSG_SCANNING)
	if is_inside_tree():
		await get_tree().process_frame
	var stats := {}
	var refs: Array = RefScan.find_referencers(path, "res://", stats)
	_render(path, refs, stats)
	_scanning = false
	_update_buttons()


## The path box, checked: "" (with the refusal already written to the status) when it is blank, names a folder, or
## names nothing on disk; otherwise the accepted project path. A path typed WITHOUT the project prefix is accepted
## and written back to the box in its full form, so what the designer copied out of a tooltip works as typed.
func _validated_target() -> String:
	var raw := _target.text.strip_edges()
	if raw.is_empty():
		_set_status(MSG_NO_PATH, TINT_WARN)
		return ""
	var path := raw if raw.begins_with("res://") else "res://" + raw.trim_prefix("/")
	if path.ends_with("/") or DirAccess.dir_exists_absolute(path):
		_set_status("Couldn't find refs for %s: that is a folder -- pick one file inside it." % _display_name(path), TINT_WARN)
		return ""
	if not FileAccess.file_exists(path):
		_set_status("Couldn't find refs for %s: there is no file at that path -- check the spelling, or select it in the FileSystem dock and press Use Selected." % path.get_file(), TINT_WARN)
		return ""
	if path != raw:
		_target.text = path
	return path


## Fill the Tree from ref_scan's rows and write the verdict. A file row shows the file NAME (plus how many places in
## it point at the target when there is more than one); its referring lines hang under it, cut to LINE_CHARS. Every
## row carries the full path in its tooltip and as metadata, so a double-click on either level opens that file.
##
## `stats` is ref_scan's denominator ({read, skipped_large}); the verdict prints it, because "nothing points at it"
## over 0 files read and over 900 files read are completely different answers to "is it safe to delete?". It is
## optional so a test can render synthetic rows without inventing one.
func _render(target: String, refs: Array, stats: Dictionary = {}) -> void:
	_tree.clear()
	var root := _tree.create_item()
	var target_name := target.get_file()
	for entry in refs:
		var row: Dictionary = entry if entry is Dictionary else {}
		var file := String(row.get("file", ""))
		if file.is_empty():
			continue
		var lines: PackedStringArray = row.get("lines", PackedStringArray())
		var file_item := _tree.create_item(root)
		var label := file.get_file()
		if lines.size() > 1:
			label += "  (%d places)" % lines.size()
		file_item.set_text(0, label)
		file_item.set_custom_color(0, COLOR_FILE)
		file_item.set_tooltip_text(0, file + "\nDouble-click to open it.")
		file_item.set_metadata(0, file)
		for line in lines:
			var line_item := _tree.create_item(file_item)
			line_item.set_text(0, short_line(line))
			line_item.set_custom_color(0, COLOR_LINE)
			line_item.set_tooltip_text(0, line + "\n" + file)
			line_item.set_metadata(0, file)
	var searched := searched_note(stats)
	if refs.is_empty():
		_set_status("Found nothing that points at %s -- no scene, resource or script mentions it, so deleting or renaming it is likely safe.%s The search reads file text, so only a name spelled out in a file is found." % [target_name, searched], TINT_OK)
	elif refs.size() == 1:
		_set_status("Found 1 file that points at %s -- double-click the row to open it, and check it before deleting or renaming.%s" % [target_name, searched])
	else:
		_set_status("Found %d files that point at %s -- double-click a row to open it, and go through every one before deleting or renaming.%s" % [refs.size(), target_name, searched])


## Double-click a row: open the referring file and reveal it in the FileSystem dock. A scene opens in the editor;
## anything else goes through the host (a quest / conversation / loot table / archetype lands in its own tab, the
## panel opens the Inspector itself for the rest); with no host (off the panel) the Inspector fallback is ours.
## Editor-only (EditorInterface) -- a handler, never exercised by the GUT test.
func _on_activated() -> void:
	var it := _tree.get_selected()
	if it == null:
		return
	var p := str(it.get_metadata(0))
	if not p.begins_with("res://"):
		return
	var opened_in_tab := false
	if p.get_extension() == "tscn":
		EditorInterface.open_scene_from_path(p)
	elif not ResourceLoader.exists(p):
		_set_status("Couldn't open %s: the file did not load -- is a reimport still running? Press Find Refs again." % p.get_file(), TINT_WARN)
		return
	elif Host.find(self) != null:
		opened_in_tab = Host.open_in_editor(self, p)  # false = the panel opened it in the Inspector instead
	else:
		EditorInterface.edit_resource(load(p))  # a script opens in the script editor; a resource in the Inspector
	EditorInterface.select_file(p)
	if opened_in_tab:
		_set_status("Opened %s in its own tab -- also selected in the FileSystem dock." % p.get_file())
	else:
		_set_status("Opened %s -- also selected in the FileSystem dock." % p.get_file())


# ================================================================================================================
# Helpers
# ================================================================================================================

## The Tree text for a referring line: whitespace-trimmed and cut to `cap` characters with a "..." tail, so one
## long ext_resource row can't widen the panel. Pure; pinned by tests/test_devtools_refs.gd.
static func short_line(line: String, cap: int = LINE_CHARS) -> String:
	var l := line.strip_edges()
	if l.length() <= cap:
		return l
	return l.left(cap - 3).strip_edges() + "..."


## The DENOMINATOR clause every verdict ends with: how many files the search actually read, and — only when there
## were any — how many were too big to read at all. "Found nothing" over 0 files read and over 900 files read are
## completely different answers to "is it safe to delete?", and the first one is a broken search wearing a clean
## verdict. Leads with a space so it drops straight onto the end of a sentence; "" when the caller handed over no
## stats (a test rendering synthetic rows), so the verdict still reads as a sentence.
static func searched_note(stats: Dictionary) -> String:
	if not stats.has("read"):
		return ""
	var note := " Searched %s." % _count(int(stats.get("read", 0)), "file", "files")
	var big: Array = stats.get("skipped_large", [])
	if not big.is_empty():
		note += " %s too big to search, so a reference inside one would be missed." % _count(big.size(), "file was", "files were")
	return note


## "1 file" / "2 files" -- a real plural, never a hand-rolled "(s)", in every count a designer reads.
static func _count(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]


## A folder path's last segment for a message ("resources/items/" -> "items"); the project root when there is none.
static func _display_name(path: String) -> String:
	var n := path.trim_suffix("/").get_file()
	return n if not n.is_empty() else "the project folder"


## Button states, re-evaluated on every keystroke and around a search: Find Refs greys with "Type a file first..."
## on a blank box and both grey with "Scanning..." mid-walk, so the tooltip names what is missing BEFORE a click;
## the post-click status is the fallback.
func _update_buttons() -> void:
	var blank := _target.text.strip_edges().is_empty()
	_find_btn.disabled = _scanning or blank
	_find_btn.tooltip_text = MSG_SCANNING if _scanning else (MSG_NO_PATH if blank else FIND_TIP)
	_use_btn.disabled = _scanning
	_use_btn.tooltip_text = MSG_SCANNING if _scanning else USE_SELECTED_TIP


## The one status row: two lines on screen, the whole message in the tooltip. A tint with alpha (TINT_WARN /
## TINT_OK) colours the text through a theme override; the default Color() clears it back to the theme colour.
func _set_status(msg: String, tint: Color = Color()) -> void:
	if _status == null:
		return
	_status.text = msg
	_status.tooltip_text = msg
	if tint.a > 0.0:
		_status.add_theme_color_override("font_color", tint)
	else:
		_status.remove_theme_color_override("font_color")
