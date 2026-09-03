@tool
extends VBoxContainer

## CYBER SUNDAY -> Scene Diff: a READ-ONLY structural comparison of two .tscn files, for "what did this scene edit
## actually touch?" without eyeballing the raw text. The designer's flow, which the idle status spells out: before a
## risky edit, duplicate the scene in the FileSystem dock; afterwards put the copy in BEFORE and the edited scene in
## AFTER (Use Selected from the FileSystem dock, or Use Open Scene for the one being edited), then Compare. The tree
## lists the nodes NEW in After, GONE in After, and CHANGED (type or properties), with the per-property differences
## under each changed node. Double-clicking a row opens the scene that holds that node and selects the node.
##
## READ-ONLY: it never merges or writes; apply changes by hand. All the deciding lives in scene_diff.gd (pure,
## GUT-driven on in-memory scene text); this file owns the widgets, the file reads, the tree render, and the
## double-click handoff, plus a few small pure helpers of its own (plan_selection / field_problem / compare_refusal
## / node_label) so the refusal wording and row labels are unit-tested without an editor.
##
## WHO READS IT: a designer who builds the game in the editor and does not read GDScript. Rows and statuses name
## files by their FILE NAME; the full path rides on the row tooltip. The two path fields do show the path they hold,
## because that is the field's value — the designer fills them from the FileSystem dock, never by typing.

const SceneDiff := preload("res://addons/cybersunday_tools/dock_scenediff/scene_diff.gd")

const COLOR_ADD := Color(0.4, 1.0, 0.5)
const COLOR_REMOVE := Color(1.0, 0.45, 0.45)
const COLOR_CHANGE := Color(1.0, 0.82, 0.3)
const COLOR_DETAIL := Color(1, 1, 1, 0.65)
const COLOR_ERROR := Color(1.0, 0.45, 0.45)

## The scrolled body's floor — the only vertical minimum this tab contributes (see the ScrollContainer comment).
const BODY_MIN_HEIGHT := 100.0

const MSG_IDLE := "Before a risky edit, duplicate the scene in the FileSystem dock (right-click -> Duplicate). Afterwards put the copy in Before and the edited scene in After -- or press Use Open Scene -- then Compare."
const MSG_NO_SCENE := "Open a scene first"
const MSG_SELECT_FIRST := "Select a scene in the FileSystem dock first."
const HINT_BEFORE := "Select the copy in the FileSystem dock, then Use Selected."
const HINT_AFTER := "Press Use Open Scene, or select the edited scene and Use Selected."

const TIP_USE_SELECTED := "Fills %s with the scene selected in the FileSystem dock -- select two scenes to fill Before and After at once. Read-only."
const TIP_USE_OPEN := "Fills After with the scene open in the editor. Read-only."
const TIP_COMPARE := "Lists every node After adds, drops or changes compared with Before. Read-only -- nothing is merged or written."
const TIP_BEFORE_FIELD := "The scene as it was -- usually the copy you duplicated in the FileSystem dock before editing."
const TIP_AFTER_FIELD := "The scene as it is now -- the edited scene."

var _before: LineEdit = null
var _after: LineEdit = null
var _use_open_btn: Button = null
var _compare_btn: Button = null
var _tree: Tree = null
var _status: Label = null

## Mirrors the host's on_scene_changed(root): plugin.gd forwards EditorPlugin.scene_changed (and fires once at
## enable), so Use Open Scene is greyed with "Open a scene first" BEFORE the designer clicks it, not after.
var _scene_open := false


func _init() -> void:
	name = "Scene Diff"
	add_theme_constant_override("separation", 4)

	# --- head: OUTSIDE the scroll, so the fields and buttons never scroll out from under the user ---------------
	# Row 1: Before  [path]  Use Selected.   Row 2: After  [path]  Use Selected  Use Open Scene  Compare.
	# Compare sits on the After row (the last thing the designer fills) instead of a third row of its own — one row
	# less of head is one row less of panel height for every tab after this one.
	_before = _make_edit("the copy you made before editing", TIP_BEFORE_FIELD)
	_after = _make_edit("the edited scene", TIP_AFTER_FIELD)
	add_child(_path_row("Before", _before))
	var after_row := _path_row("After", _after)
	_use_open_btn = Button.new()
	_use_open_btn.text = "Use Open Scene"
	_use_open_btn.pressed.connect(_use_open_scene)
	after_row.add_child(_use_open_btn)
	_compare_btn = Button.new()
	_compare_btn.text = "Compare"
	_compare_btn.pressed.connect(_compare)
	after_row.add_child(_compare_btn)
	add_child(after_row)

	# The status line is its OWN full-width row, NOT a sibling inside a button HBox: an autowrap Label packed into an
	# HBoxContainer collapses to its longest-word minimum width and wraps into a tall, narrow column beside the
	# buttons. Clamped to TWO lines so a long verdict can never grow the head; the full text is mirrored onto its
	# tooltip on every write (_set_status).
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 2
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.modulate = Color(1, 1, 1, 0.75)
	_status.mouse_filter = Control.MOUSE_FILTER_PASS  # a Label ignores the mouse by default, which also hides its tooltip
	add_child(_status)

	# --- body: bounded + scrolled -------------------------------------------------------------------------------
	# The Tree carries its own scrollbars, so this ScrollContainer is the HEIGHT FENCE, not a second scroller: its
	# custom_minimum_size is the only vertical minimum this tab contributes, however many rows the Tree holds. That
	# matters because a TabContainer's minimum is the CURRENT tab's minimum and the editor's bottom splitter keeps
	# whatever height it grew to — so one tall tab, once shown, leaves the panel tall for every tab after it. The
	# Tree keeps SIZE_EXPAND_FILL, which a Godot 4 ScrollContainer honours by stretching an expanding child to the
	# container's size, so the Tree fills the panel and the outer scroll never engages. Horizontal scrolling is
	# DISABLED because a long row must never widen the bottom panel; the Tree elides those rows and every row
	# carries its full text (plus the file's path) as a tooltip.
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
	_tree.custom_minimum_size = Vector2(0, 90)  # small floor, mirroring stats_view / audit_panel
	_tree.item_activated.connect(_on_activated)  # double-click / Enter
	scroll.add_child(_tree)

	_apply_scene_state()
	_update_compare_state()
	_set_status(MSG_IDLE)


## One path field. Editable (a designer CAN paste a path), but the intended fill is the row's buttons; a typed
## change re-evaluates Compare's disabled state like a button fill does.
func _make_edit(placeholder: String, tip: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.tooltip_text = tip
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_changed.connect(func(_t: String) -> void: _update_compare_state())
	return edit


## One head row: the field's name, its path field, and Use Selected (fills it from the FileSystem dock selection).
## Returned un-parented so the caller can append the After row's extra buttons before adding it.
func _path_row(field: String, edit: LineEdit) -> HBoxContainer:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = field
	lbl.custom_minimum_size = Vector2(48, 0)  # the two fields line up under each other
	row.add_child(lbl)
	row.add_child(edit)
	var use := Button.new()
	use.text = "Use Selected"
	use.tooltip_text = TIP_USE_SELECTED % field
	use.pressed.connect(func() -> void: _use_selected(field))
	row.add_child(use)
	return row


# ================================================================================================================
# Pure helpers — no editor, no widgets; GUT-pinned in tests/test_devtools_scenediff.gd
# ================================================================================================================

## What a Use Selected press on `field` ("Before" / "After") does with the FileSystem dock selection `sel`.
## Returns {before, after, error}: `before` / `after` are the paths to fill ("" = leave that field alone), `error`
## is the refusal to show ("" = accepted). Non-scene files in the selection are skipped; TWO or more selected scenes
## fill Before with the first and After with the second whichever row's button was pressed (the FileSystem dock
## lists them in tree order, so the status names which went where); one scene fills just `field`.
static func plan_selection(sel: PackedStringArray, field: String) -> Dictionary:
	var out := {"before": "", "after": "", "error": ""}
	if sel.is_empty():
		out["error"] = MSG_SELECT_FIRST
		return out
	var scenes := PackedStringArray()
	for p in sel:
		if p.ends_with(".tscn"):
			scenes.append(p)
	if scenes.is_empty():
		out["error"] = "Couldn't fill %s: %s is not a scene file (.tscn)." % [field, sel[0].get_file()]
		return out
	if scenes.size() >= 2:
		out["before"] = scenes[0]
		out["after"] = scenes[1]
		return out
	out["before" if field == "Before" else "after"] = scenes[0]
	return out


## Why one path field cannot be compared: "" when it can, else "<Field>: empty" / "<Field>: not an existing .tscn".
static func field_problem(field: String, path: String) -> String:
	if path.is_empty():
		return "%s: empty" % field
	if not path.ends_with(".tscn") or not FileAccess.file_exists(path):
		return "%s: not an existing .tscn" % field
	return ""


## The whole refusal for a Compare over these two paths, or "" when the compare may run. Before is checked first so
## the designer fixes the fields in the order they fill them; each refusal ends with the way to fill that field.
static func compare_refusal(before: String, after: String) -> String:
	var pb := field_problem("Before", before)
	if pb != "":
		return "Couldn't compare -- %s. %s" % [pb, HINT_BEFORE]
	var pa := field_problem("After", after)
	if pa != "":
		return "Couldn't compare -- %s. %s" % [pa, HINT_AFTER]
	if before == after:
		return "Couldn't compare: Before and After are the same file -- put the copy in Before and the edited scene in After."
	return ""


## How a node row reads: the root as "<RootName> (root)" (its model key is the fixed "."), every other node as its
## path from the root — the same words the Scene dock shows. `model` is the parsed scene the node lives in.
static func node_label(key: String, model: Dictionary) -> String:
	if key != ".":
		return key
	var root_name := String((model.get(".", {}) as Dictionary).get("name", ""))
	return "%s (root)" % root_name if not root_name.is_empty() else "(root)"


# ================================================================================================================
# Handlers — the only places that touch EditorInterface (in-tree by construction: a button was clicked)
# ================================================================================================================

func _use_selected(field: String) -> void:
	var plan := plan_selection(EditorInterface.get_selected_paths(), field)
	var err := String(plan["error"])
	if err != "":
		_set_status(err, true)
		return
	var before := String(plan["before"])
	var after := String(plan["after"])
	if before != "":
		_before.text = before
	if after != "":
		_after.text = after
	_update_compare_state()
	if before != "" and after != "":
		_set_status("Filled Before with %s and After with %s -- check the copy is in Before, then Compare." % [before.get_file(), after.get_file()])
	else:
		var filled := before if before != "" else after
		_set_status("Filled %s with %s -- %s" % [field, filled.get_file(), _next_step()])


func _use_open_scene() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		_set_status("Open a scene first, then Use Open Scene.", true)
		return
	var path := root.scene_file_path
	if path.is_empty():
		_set_status("Couldn't fill After: the open scene hasn't been saved yet -- save it (Ctrl+S) first.", true)
		return
	_after.text = path
	_update_compare_state()
	_set_status("Filled After with %s -- %s" % [path.get_file(), _next_step()])


## Compare: validate both fields (pure), read both files, diff (pure), render. Synchronous — a text parse of even
## the live level is quick enough that a "Comparing..." frame would never be seen.
func _compare() -> void:
	_tree.clear()
	var before_path := _before.text.strip_edges()
	var after_path := _after.text.strip_edges()
	var refusal := compare_refusal(before_path, after_path)
	if refusal != "":
		_set_status(refusal, true)
		return
	var before_model := SceneDiff.parse_scene(FileAccess.get_file_as_string(before_path))
	var after_model := SceneDiff.parse_scene(FileAccess.get_file_as_string(after_path))
	var d := SceneDiff.diff_scenes(before_model, after_model)
	_render(d, before_model, after_model, before_path, after_path)


## Double-click a row: open the scene that holds that node and select the node in it. A NEW or CHANGED row lives in
## After, a GONE row in Before (that is the only file it still exists in) — the row's metadata says which. Opening a
## scene and selecting a node are editor-state changes, not file writes; the tab still writes nothing.
func _on_activated() -> void:
	var it := _tree.get_selected()
	if it == null:
		return
	var meta: Variant = it.get_metadata(0)
	if not (meta is Dictionary):
		return  # a section header
	var file := String((meta as Dictionary).get("file", ""))
	var node := String((meta as Dictionary).get("node", ""))
	if file.is_empty():
		return
	if not FileAccess.file_exists(file):
		# A row can outlive its file (renamed or deleted since the compare), or the editor may still be importing it.
		_set_status("Couldn't open %s: the file is missing or still importing -- press Compare again." % file.get_file(), true)
		return
	EditorInterface.open_scene_from_path(file)
	var root := EditorInterface.get_edited_scene_root()
	if root == null or root.scene_file_path != file:
		_set_status("Opened %s -- find %s in the Scene dock." % [file.get_file(), _node_words(node)])
		return
	var n := root.get_node_or_null(NodePath(node))  # "." is the root itself
	if n == null:
		_set_status("Opened %s -- couldn't find %s in it (renamed or removed since the compare?). Press Compare again." % [file.get_file(), _node_words(node)], true)
		return
	var sel := EditorInterface.get_selection()
	sel.clear()
	sel.add_node(n)
	EditorInterface.edit_node(n)
	_set_status("Opened %s and selected %s." % [file.get_file(), n.name])


# ================================================================================================================
# Render + state
# ================================================================================================================

## Paint one diff into the (already cleared) tree: New in After / Gone in After / Changed, each row carrying the
## file it can be opened from + its node key as metadata. `before_model` / `after_model` are the parsed scenes
## (for the root's name); `before_path` / `after_path` the files they came from.
func _render(d: Dictionary, before_model: Dictionary, after_model: Dictionary, before_path: String, after_path: String) -> void:
	var root := _tree.create_item()
	var added: Array = d["added"]
	var removed: Array = d["removed"]
	var changed: Array = d["changed"]
	var before_name := before_path.get_file()
	var after_name := after_path.get_file()
	if added.is_empty() and removed.is_empty() and changed.is_empty():
		_set_status("Compared %s with %s -- no differences (same nodes, types and properties)." % [before_name, after_name])
		return
	_section(root, "New in After (%d)" % added.size(), added, COLOR_ADD, after_model, after_path)
	_section(root, "Gone in After (%d)" % removed.size(), removed, COLOR_REMOVE, before_model, before_path)
	if not changed.is_empty():
		var head := _tree.create_item(root)
		head.set_text(0, "Changed (%d)" % changed.size())
		head.set_custom_color(0, COLOR_CHANGE)
		for c in changed:
			var key := String(c["key"])
			var ni := _row(head, node_label(key, after_model), COLOR_CHANGE, after_path, key)
			if str(c["type_change"]) != "":
				_detail(ni, str(c["type_change"]), after_path, key)
			for p in c["props_changed"]:
				_detail(ni, "~ " + str(p), after_path, key)
			for p in c["props_added"]:
				_detail(ni, "+ " + str(p), after_path, key)
			for p in c["props_removed"]:
				_detail(ni, "- " + str(p), after_path, key)
	_set_status("Compared %s with %s -- %d new, %d gone, %d changed." % [before_name, after_name, added.size(), removed.size(), changed.size()])


## One section header + one row per node key, skipped entirely when there is nothing to list.
func _section(root: TreeItem, title: String, keys: Array, col: Color, model: Dictionary, file: String) -> void:
	if keys.is_empty():
		return
	var head := _tree.create_item(root)
	head.set_text(0, title)
	head.set_custom_color(0, col)
	for k in keys:
		_row(head, node_label(String(k), model), col, file, String(k))


## A node row: text, colour, and the metadata the double-click handoff reads ({file, node}). The tooltip carries
## the full row text (horizontal scrolling is disabled and a long row elides), the file's path — the one place the
## path appears — and the double-click hint.
func _row(parent: TreeItem, text: String, col: Color, file: String, node: String) -> TreeItem:
	var it := _tree.create_item(parent)
	it.set_text(0, text)
	it.set_custom_color(0, col)
	it.set_metadata(0, {"file": file, "node": node})
	it.set_tooltip_text(0, "%s\n%s\nDouble-click to open %s and select this node." % [text, file, file.get_file()])
	return it


## A per-property line under a changed node. Carries its parent's metadata so double-clicking the property also
## lands on the node that owns it.
func _detail(parent: TreeItem, text: String, file: String, node: String) -> void:
	var it := _tree.create_item(parent)
	it.set_text(0, text)
	it.set_custom_color(0, COLOR_DETAIL)
	it.set_metadata(0, {"file": file, "node": node})
	it.set_tooltip_text(0, "%s\n%s\nDouble-click to open %s and select the node." % [text, file, file.get_file()])


## Host seam (cyber_panel.on_scene_changed): grey Use Open Scene while no scene is open. `root` may be null.
func on_scene_changed(root: Node) -> void:
	_scene_open = is_instance_valid(root)
	_apply_scene_state()


func _apply_scene_state() -> void:
	_use_open_btn.disabled = not _scene_open
	_use_open_btn.tooltip_text = TIP_USE_OPEN if _scene_open else MSG_NO_SCENE


## Compare is greyed until BOTH fields hold something, and its tooltip names the missing one; the post-click
## refusal (compare_refusal) stays as the fallback for a path that is filled but wrong.
func _update_compare_state() -> void:
	var before_blank := _before.text.strip_edges().is_empty()
	var after_blank := _after.text.strip_edges().is_empty()
	_compare_btn.disabled = before_blank or after_blank
	if before_blank and after_blank:
		_compare_btn.tooltip_text = "Fill Before and After first"
	elif before_blank:
		_compare_btn.tooltip_text = "Fill Before first"
	elif after_blank:
		_compare_btn.tooltip_text = "Fill After first"
	else:
		_compare_btn.tooltip_text = TIP_COMPARE


## The imperative tail of a "Filled X with Y -- ..." status: what to do next given which fields hold a path.
func _next_step() -> String:
	var before_blank := _before.text.strip_edges().is_empty()
	var after_blank := _after.text.strip_edges().is_empty()
	if before_blank:
		return "now fill Before, then Compare."
	if after_blank:
		return "now fill After, then Compare."
	return "press Compare."


## "the root" / "node Mesh/Box" — how a status names the node a row points at.
static func _node_words(node: String) -> String:
	return "the root" if node == "." else "node %s" % node


## Write the status line and mirror it onto the tooltip (the Label is clamped to two lines, so the tooltip is where
## a long message stays readable in full). `error` tints the text through a theme colour override — the modulate
## alpha stays the panel-wide 0.75 either way.
func _set_status(msg: String, error: bool = false) -> void:
	_status.text = msg
	_status.tooltip_text = msg
	if error:
		_status.add_theme_color_override("font_color", COLOR_ERROR)
	else:
		_status.remove_theme_color_override("font_color")
