@tool
extends VBoxContainer

## Palette tab (Build group of the CYBER SUNDAY panel): a searchable, category-grouped list of every drop-in
## component in core/catalog.gd, with one-click "Add to Selected Node". It kills the discoverability problem for the
## ~67-component catalog and makes the canonical components the path of least resistance. Adds are one undoable
## EditorUndoRedoManager action; nothing reaches disk until the designer saves the scene.
##
## add_mode "instance" -> load+instantiate the prefab; "child" -> build the script's native base (via the script's
## get_instance_base_type) and attach the script. The new node parents under the node selected in the Scene tree
## (or the scene root), becomes the editor selection, and is pushed into the Inspector so the designer can fill its
## fields at once -- the description row already told them which fields matter (the catalog row's key_exports).
##
## SIBLING RULE (shared with the Place / Place Item tabs, see _parent_for): because an Add SELECTS what it just
## added, a second Add would otherwise land the new component INSIDE the previous one -- a QuestStarter under a
## Talkable -- which is never what "add two components to this node" means. So when the Scene-tree selection IS the
## component this tab added last, the new one goes under that node's PARENT instead. Any other selection is a
## deliberate parent and is honoured as-is.
##
## Two read-outs, deliberately separate: `_desc` under the list is WHAT the picked component does (plus the
## Inspector fields it wants) and `_status` under the Add button is what the tab just DID or REFUSED. A refusal must
## never overwrite the description the designer was reading -- that was the old single-label design. Both are
## 2-line clamped autowrap labels whose tooltip mirrors the full text on every write. The Tree scrolls itself (no
## ScrollContainer wrap needed) and carries a small height floor so the tab can never force the shared bottom panel
## taller than the screen: a TabContainer's minimum is the CURRENT tab's minimum, and the editor's bottom splitter
## keeps the height it grew to.
##
## Host seams (cyber_panel.gd): on_scene_changed(root) is forwarded from EditorPlugin.scene_changed (and once at
## enable) so the Add button greys with "Open a scene first" BEFORE a click, not after. The lazy first-reveal latch
## re-asks the editor for the edited scene the first time the tab is actually shown, covering a tab built after that
## enable-time call. Off-tree (GUT / the headless probe construct this bare) every editor call stays inside a button
## handler or behind Engine.is_editor_hint(), so _init never touches EditorInterface.

const Catalog := preload("res://addons/cybersunday_tools/core/catalog.gd")

## One sentence per guard, shared by the Add button's disabled tooltip AND the post-click status (a double-click on
## a row bypasses the disabled button, so the click must never be silent). Sharing the literal keeps them in step.
const MSG_NO_SCENE := "Open a scene first, then Add."
const MSG_NO_PICK := "Pick a component in the list first."
const MSG_IDLE := "Pick a component, then Add to Selected Node -- it lands under the node selected in the Scene tree, or the scene root."
const ADD_TIP := "Adds the picked component under the node selected in the Scene tree, or the scene root, as one undoable step. Writes the open scene -- nothing reaches disk until you save it."
const SEARCH_TIP := "Type part of a component's name or description to narrow the list."

var _search: LineEdit = null
var _tree: Tree = null
var _desc: Label = null
var _add_btn: Button = null
var _status: Label = null

## Mirrors the host's on_scene_changed(root) so the Add button can grey before a click. The handler itself re-reads
## the live edited-scene root (the editor is the source of truth); this flag only drives the button state.
var _scene_open := false

## The node this tab added most recently -- the SIBLING RULE state (see _parent_for). A plain Node reference, never
## kept alive by us: Nodes aren't reference-counted, and undo (or a scene close) frees this one out from under the
## field, so every read goes through is_instance_valid FIRST -- `x is T` on a freed instance hard-crashes the editor.
var _last_added: Node = null

## Lazy first-reveal latch -- the tab asks the editor for the edited scene the first time it is actually shown, not
## at panel construction (cyber_panel._init builds every tab eagerly, and _init must stay free of editor calls so the
## bare off-tree construction under GUT keeps working). Mirrors content_browser / scene_placer / item_placer_dock.
var _revealed := false


func _init() -> void:
	name = "Palette"
	add_theme_constant_override("separation", 4)

	_search = LineEdit.new()
	_search.placeholder_text = "Search..."
	_search.tooltip_text = SEARCH_TIP
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t: String) -> void: _rebuild_tree())
	add_child(_search)

	_tree = Tree.new()
	_tree.hide_root = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.custom_minimum_size = Vector2(0, 90)  # small floor so the dock can shrink on a short display; the Tree scrolls itself
	_tree.item_selected.connect(_on_item_selected)
	_tree.item_activated.connect(_on_add)  # double-click = add
	add_child(_tree)

	# WHAT the picked component does. Clamped to two lines (the tooltip carries the full text) so a long catalog
	# description can never push the Add button off a short bottom panel.
	_desc = Label.new()
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.max_lines_visible = 2
	_desc.custom_minimum_size = Vector2(0, 24)
	_desc.modulate = Color(1, 1, 1, 0.75)
	add_child(_desc)

	_add_btn = Button.new()
	_add_btn.text = "Add to Selected Node"
	_add_btn.pressed.connect(_on_add)
	add_child(_add_btn)

	# What the tab just DID or REFUSED -- its own full-width row under the Add button, so a refusal never replaces the
	# description above. Same two-line clamp + tooltip mirror as _desc.
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 2
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.modulate = Color(1, 1, 1, 0.75)
	add_child(_status)
	_set_status(MSG_IDLE)

	_rebuild_tree()  # the catalog is a compile-time const -- no disk walk, so it is safe (and cheap) at construction

	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()  # no-op off-tree (not visible); in the editor the real reveal fires the signal


## Lazy first-reveal: the first time the tab is actually shown, sync the scene gate from the editor. Guarded by
## Engine.is_editor_hint() because EditorInterface is not a thing in a headless / GUT construction. After this the
## host keeps the gate current through on_scene_changed.
func _on_visibility_changed() -> void:
	if is_visible_in_tree() and not _revealed:
		_revealed = true
		if Engine.is_editor_hint():
			on_scene_changed(EditorInterface.get_edited_scene_root())


## Host seam (cyber_panel.on_scene_changed, forwarded from EditorPlugin.scene_changed and once at enable): grey the
## Add button while no scene is open. `root` may be null (every scene closed). is_instance_valid guards a stale root
## handed over mid-close -- a freed Object compares unequal to null in GDScript, so a bare null test is not enough.
func on_scene_changed(root: Node) -> void:
	_scene_open = is_instance_valid(root)
	_update_add_state()


## The Add button's disabled state + tooltip, derived from the two gates. Scene first: with no scene open there is
## nothing to add into, so that is the more useful thing to tell the designer even when no row is picked either.
## When both gates pass the tooltip is the plain rule-of-the-button text.
func _update_add_state() -> void:
	if _add_btn == null:
		return
	if not _scene_open:
		_add_btn.disabled = true
		_add_btn.tooltip_text = MSG_NO_SCENE
	elif _selected_row().is_empty():
		_add_btn.disabled = true
		_add_btn.tooltip_text = MSG_NO_PICK
	else:
		_add_btn.disabled = false
		_add_btn.tooltip_text = ADD_TIP


func _set_status(msg: String) -> void:
	if _status == null:
		return
	_status.text = msg
	_status.tooltip_text = msg  # the label clamps to two lines; hovering shows the whole message


func _set_desc(msg: String) -> void:
	if _desc == null:
		return
	_desc.text = msg
	_desc.tooltip_text = msg  # same clamp/mirror contract as the status row


func _rebuild_tree() -> void:
	if _tree == null:
		return
	_tree.clear()
	var root_item := _tree.create_item()
	var filter := _search.text.strip_edges().to_lower()
	var cats := {}
	for row in Catalog.COMPONENTS:
		var label := str(row["class_name"])
		var desc := str(row.get("description", ""))
		if filter != "" and not (label.to_lower().contains(filter) or desc.to_lower().contains(filter)):
			continue
		var cat := str(row.get("category", "Misc"))
		if not cats.has(cat):
			var ci := _tree.create_item(root_item)
			ci.set_text(0, cat)
			ci.set_selectable(0, false)
			ci.set_custom_color(0, Color(0.6, 0.8, 1.0))
			cats[cat] = ci
		var it := _tree.create_item(cats[cat])
		it.set_text(0, label)
		it.set_tooltip_text(0, desc)  # hover any row for what it does, without having to pick it first
		it.set_metadata(0, row)
	# Tree.clear() drops the selection silently (no item_selected), so re-run the selection handler: a search filter
	# that hid the picked row must also clear its description and grey the Add button, or the tab shows a stale
	# description beside a "Pick a component" tooltip.
	_on_item_selected()


func _selected_row() -> Dictionary:
	var it := _tree.get_selected()
	if it == null:
		return {}
	var md: Variant = it.get_metadata(0)
	return md if md is Dictionary else {}


## Describe the picked row: "<Category> -- <description>", plus the Inspector fields the designer will have to fill
## (the catalog row's key_exports) on a second line, so they know what the Inspector will ask BEFORE they add it.
func _on_item_selected() -> void:
	var row := _selected_row()
	if row.is_empty():
		_set_desc("")
		_update_add_state()
		return
	var text := "%s -- %s" % [str(row.get("category", "")), str(row.get("description", ""))]
	var keys_v: Variant = row.get("key_exports", [])
	var keys: PackedStringArray = PackedStringArray(keys_v) if keys_v is Array else PackedStringArray()
	if not keys.is_empty():
		text += "\nInspector fields to fill: %s" % ", ".join(keys)
	_set_desc(text)
	_update_add_state()


## Add the picked component under the Scene-tree selection (or the scene root) as ONE undoable action, then make the
## new node the editor selection and push it into the Inspector. Guards run scene-first and BEFORE the node is
## built, so a refusal never has an orphan to free. Every early return writes its sentence to the status because a
## double-click on a row reaches here even while the Add button is disabled.
func _on_add() -> void:
	var root := EditorInterface.get_edited_scene_root()
	on_scene_changed(root)  # keep the button state honest with what this click just observed
	if root == null:
		_set_status(MSG_NO_SCENE)
		return
	var row := _selected_row()
	if row.is_empty():
		_set_status(MSG_NO_PICK)
		return
	var node := _make_node(row)
	if node == null:
		# "that component" rather than a bare "?" for the (impossible-in-practice) row with no name: a refusal that
		# reads "Couldn't add ?" tells a designer nothing about what to do next.
		_set_status("Couldn't add %s: its scene or script file is missing." % str(row.get("class_name", "that component")))
		return
	var sel := EditorInterface.get_selection().get_selected_nodes()
	var picked: Node = sel[0] if not sel.is_empty() else null
	var parent := _parent_for(picked, root)
	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action("Add %s" % node.name)
	ur.add_do_method(parent, "add_child", node)
	ur.add_do_property(node, "owner", root)
	ur.add_do_reference(node)
	ur.add_undo_method(parent, "remove_child", node)
	ur.commit_action()
	# The do-methods have run: node.name is now the final (possibly de-duplicated) name. Select it and open it in
	# the Inspector so the designer lands straight on the fields the description row named. Remember it FIRST: the
	# selection we just took is exactly what _parent_for has to see through on the next Add (the SIBLING RULE).
	_last_added = node
	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node(node)
	EditorInterface.edit_node(node)
	var where := "under %s" % parent.name if parent != root else "under the scene root"
	if picked != null and is_instance_valid(picked) and parent != picked:
		where = "beside %s, %s" % [picked.name, where]
	_set_status("Added %s %s -- selected; fill its fields in the Inspector, then save the scene." % [node.name, where])


## SIBLING RULE: the parent for a new component. Nothing selected -> the scene root. The component this tab added
## LAST -> its parent, so a second Add lands beside the first instead of nesting inside it (adding auto-selects, so
## without this "add Talkable, add QuestStarter" would bury the second under the first). Anything else -> the
## selection, a deliberate parent. is_instance_valid FIRST on every read of _last_added: undo frees it, and a freed
## instance compares UNEQUAL to null, so a bare null test would sail straight into a dangling reference.
func _parent_for(picked: Node, root: Node) -> Node:
	if picked == null or not is_instance_valid(picked):
		return root
	if is_instance_valid(_last_added) and picked == _last_added:
		var up := _last_added.get_parent()
		if up != null:
			return up
		return root
	return picked


## Build a fresh node for a catalog row (no editor calls -- unit-testable). "instance" instantiates the prefab;
## "child" builds the script's native base type and attaches the script. Returns null on any missing piece.
func _make_node(row: Dictionary) -> Node:
	var mode := str(row.get("add_mode", ""))
	if mode == "instance":
		var sc := str(row.get("scene_path", ""))
		if sc == "":
			return null
		var ps := load(sc) as PackedScene
		return ps.instantiate() if ps != null else null
	# "child": bare node of the script's native base + the script
	var sp := str(row.get("script_path", ""))
	if sp == "":
		return null
	var s := load(sp) as GDScript
	if s == null:
		return null
	var base := s.get_instance_base_type()
	if base == &"" or not ClassDB.can_instantiate(base):
		return null
	var node := ClassDB.instantiate(base) as Node
	if node == null:
		return null
	node.set_script(s)
	node.name = str(row.get("class_name", base))
	return node
