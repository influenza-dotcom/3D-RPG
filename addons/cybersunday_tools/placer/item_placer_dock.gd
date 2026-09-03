@tool
extends VBoxContainer

## Place Item tab (Build group of the CYBER SUNDAY panel; Control name "Items" -- tests pin it, the panel sets the
## display title): pick any authored Item and drop a ready world pickup for it into the open scene -- the "find a
## stimpak in the world like Fallout" workflow, no manual node wiring. The placed object is built by the same
## WorldItem.build the runtime inventory drop uses, so editor placement can't drift from in-game behaviour: usually
## a Throwable (RigidBody3D) you carry/throw with the PickupRay AND a CanPickUp CHILD you loot with E; an Item that
## declares a `world_prop` spawns that authored prop scene AS-IS instead. It's editor-visible (the box mesh or the
## item's world model), drops ~3 m in front of the editor camera, and saves into the scene.
##
## Layout, top to bottom: ONE action row (Place Selected + Refresh), a search filter, the item list, ONE status
## label. The ItemList scrolls itself (no ScrollContainer wrap needed) and carries a small height floor so this tab
## can never force the shared bottom panel taller than the screen: a TabContainer's minimum is the CURRENT tab's
## minimum, and the editor's bottom splitter keeps the height it grew to.
##
## The scan is the shared core/item_scan.gd (the ItemDb autoload is non-@tool, so it's empty in the editor); files
## that exist but fail to load are named in the status instead of silently vanishing from the list. Rows read
## "<display name>  (<id>)", sorted by that label, with the file path on the row tooltip; `_items` stays index-
## parallel with the rows currently SHOWN (the filter narrows both together). The placed item parents under the
## node selected in the Scene tree (or the scene root) -- unless that selection is the item this tab placed last,
## in which case the new one lands BESIDE it (see _parent_for) -- and the add is one undoable action.
##
## Host seams (cyber_panel.gd): on_scene_changed(root) is forwarded from EditorPlugin.scene_changed (and once at
## enable) so Place Selected greys with "Open a scene first" BEFORE a click; select_path(path) lets the panel hand a
## specific item file to this tab (find + pick it, clearing the filter if it hid the row). The editor's
## filesystem_changed only raises `_fs_dirty`; the rescan waits for the NEXT reveal of the tab (never mid-edit) and
## keeps the picked item by PATH, never by row index. Off-tree (GUT / the headless probe construct this bare) every
## editor call stays inside a button handler, the first-reveal latch, or behind Engine.is_editor_hint(), so _init
## never touches EditorInterface.

## The ONE canonical subtree-owner (shared with scene_placer.gd). Its instanced-node stop-guard is safety-critical --
## it keeps a placed prefab's @tool live-preview children (the NPC BodyModelSwap limbs) out of the saved .tscn. This
## dock used to carry a hand-copied twin; routing through the single tested static removes the re-divergence trap.
const PlaceOps := preload("res://addons/cybersunday_tools/dock_place/place_ops.gd")
## The shared items-folder scan (also read by the Audit and the File -> Run content validator), so a folder rule
## lands in one place. `_scan_items()` below is the thin wrapper tests call.
const ItemScan := preload("res://addons/cybersunday_tools/core/item_scan.gd")

## One sentence per guard, shared by the Place button's disabled tooltip AND the post-click status (a double-click
## on a row bypasses the disabled button, so the click must never be silent). Sharing the literal keeps them in step.
const MSG_NO_SCENE := "Open a scene first, then Place Selected."
const MSG_NO_PICK := "Pick an item in the list first."
const MSG_IDLE := "Pick an item, then Place Selected -- it lands in front of the camera as a world pickup."
const PLACE_TIP := "Drops the picked item into the open scene in front of the camera, as one undoable step. Writes the open scene -- nothing reaches disk until you save it."
const REFRESH_TIP := "Re-reads the items folder and rebuilds the list, keeping the picked item. Read-only."
const SEARCH_TIP := "Type part of an item's name, id or file name to narrow the list."

## Status colour for a scan that lost files (the label's default colour is restored on every plain write).
const WARN_COLOR := Color(1.0, 0.85, 0.4)

var _search: LineEdit = null
var _list: ItemList = null
var _place_btn: Button = null
var _status: Label = null

## The full scan, sorted by row label. `_items` is the SHOWN subset, index-parallel with the ItemList rows, so a
## row index is always a valid `_items` index even while the search filter is narrowing the list.
var _all_items: Array[Item] = []
var _items: Array[Item] = []
## Item files the last scan found but could not load (reimport in progress, broken script...) -- named in the status.
var _skipped: PackedStringArray = PackedStringArray()

## The node this tab placed most recently. Placing auto-selects it, so a second Place Selected would otherwise nest
## the new pickup INSIDE the previous one (a RigidBody3D under a RigidBody3D); _parent_for reads this to land the
## next item beside it instead. Only ever compared after is_instance_valid -- an undo or a scene close frees it.
var _last_placed: Node = null

## Mirrors the host's on_scene_changed(root) so Place Selected can grey before a click. The handler itself re-reads
## the live edited-scene root (the editor is the source of truth); this flag only drives the button state.
var _scene_open := false

## Raised by the editor's filesystem_changed (connected in _init, editor only). A rescan while the tab is showing
## would swap the rows under the designer's pick, so it waits for the next reveal; Refresh is the explicit fallback.
var _fs_dirty := false

## PL6: lazy first-reveal latch -- the resources/items scan runs on first reveal, not at panel construction.
var _revealed := false


func _init() -> void:
	name = "Items"
	add_theme_constant_override("separation", 4)

	# Action row: the two commands, above the list so they stay put while the list grows.
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	add_child(actions)

	_place_btn = Button.new()
	_place_btn.text = "Place Selected"
	_place_btn.tooltip_text = PLACE_TIP
	_place_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_place_btn.pressed.connect(_place)
	actions.add_child(_place_btn)

	var refresh := Button.new()
	refresh.text = "Refresh"
	refresh.tooltip_text = REFRESH_TIP
	refresh.pressed.connect(_on_refresh)
	actions.add_child(refresh)

	# Search filter (the palette_dock.gd idiom): narrows the rows AND `_items` together, keeping the pick by path.
	_search = LineEdit.new()
	_search.placeholder_text = "Search..."
	_search.tooltip_text = SEARCH_TIP
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t: String) -> void: _rebuild_rows(_picked_path()))
	add_child(_search)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = Vector2(0, 90)  # small floor so the tab can shrink on a short display; the list scrolls itself
	_list.item_selected.connect(func(_i: int) -> void: _update_place_state())
	_list.empty_clicked.connect(func(_p: Vector2, _b: int) -> void: _update_place_state())
	_list.item_activated.connect(func(_i: int) -> void: _place())  # double-click = place
	add_child(_list)

	# What the tab just DID or REFUSED (or the next step). Clamped to two lines with the full text on its tooltip, so
	# a long list of failed files can never push the list off a short bottom panel.
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 2
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.modulate = Color(1, 1, 1, 0.75)
	add_child(_status)
	_set_status(MSG_IDLE)
	_update_place_state()  # no scene known yet -> greyed with "Open a scene first" until the host reports one

	if Engine.is_editor_hint():
		# Editor only (EditorInterface does not exist headless). The connection dies with this Control -- Godot
		# disconnects every signal aimed at an Object when that Object is freed -- so a plugin reload leaves nothing
		# dangling on the editor's filesystem scanner.
		var fs := EditorInterface.get_resource_filesystem()
		if fs != null:
			fs.filesystem_changed.connect(_on_filesystem_changed)

	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()  # no-op off-tree (not visible); in the editor the real reveal fires the signal


## Lazy first-reveal: run the item scan ONCE, the first time the tab is actually shown (not at construction), and
## sync the scene gate from the editor (guarded: no EditorInterface headless). Later reveals rescan only when the
## editor's filesystem changed while the tab was hidden -- keeping the picked item by path (see _reload).
func _on_visibility_changed() -> void:
	if is_visible_in_tree() and not _revealed:
		_revealed = true
		_reload()
		if Engine.is_editor_hint():
			on_scene_changed(EditorInterface.get_edited_scene_root())
	elif is_visible_in_tree() and _fs_dirty:
		_reload()


## The editor's FileSystem scanner noticed a change (a new / saved / deleted file anywhere). Only flag it: the
## rescan runs on the next reveal, never under the designer's pick while the tab is showing.
func _on_filesystem_changed() -> void:
	_fs_dirty = true


## Host seam (cyber_panel.on_scene_changed, forwarded from EditorPlugin.scene_changed and once at enable): grey
## Place Selected while no scene is open. `root` may be null (every scene closed). is_instance_valid guards a stale
## root handed over mid-close -- a freed Object compares unequal to null in GDScript, so a bare null test is not enough.
func on_scene_changed(root: Node) -> void:
	_scene_open = is_instance_valid(root)
	_update_place_state()


## Host seam (cyber_panel.open_in_editor): find + pick the item saved at `path` in this tab's own list. Scans first
## if the tab has never been revealed (or the folder changed since), and clears the search filter when it hid the
## row. true when the row is now picked; false when no such item is in the items folder.
func select_path(path: String) -> bool:
	if path.is_empty():
		return false
	if not _revealed or _fs_dirty:
		_reload()
	if _select_by_path(path):
		return true
	if _search != null and _search.text != "":
		_search.text = ""  # the setter does not emit text_changed, so rebuild by hand
		_rebuild_rows(path)
		return _picked_path() == path
	return false


## Place Selected's disabled state + tooltip, derived from the two gates. Scene first: with no scene open there is
## nothing to place into, so that is the more useful thing to tell the designer even when no row is picked either.
## When both gates pass the tooltip is the plain rule-of-the-button text.
func _update_place_state() -> void:
	if _place_btn == null:
		return
	if not _scene_open:
		_place_btn.disabled = true
		_place_btn.tooltip_text = MSG_NO_SCENE
	elif _picked_item() == null:
		_place_btn.disabled = true
		_place_btn.tooltip_text = MSG_NO_PICK
	else:
		_place_btn.disabled = false
		_place_btn.tooltip_text = PLACE_TIP


## Every status write: the label clamps to two lines, so the tooltip mirrors the whole message. `warn` tints the
## text (a scan that lost files); a plain write restores the label's default colour.
func _set_status(msg: String, warn: bool = false) -> void:
	if _status == null:
		return
	_status.text = msg
	_status.tooltip_text = msg
	if warn:
		_status.add_theme_color_override("font_color", WARN_COLOR)
	else:
		_status.remove_theme_color_override("font_color")


## The explicit Refresh command: re-read the folder (keeping the pick by path) and say so -- unless the scan has
## something to complain about, in which case _reload's own message stays.
func _on_refresh() -> void:
	_reload()
	if _skipped.is_empty() and not _all_items.is_empty():
		_set_status("Refreshed the item list -- %s; pick one, then Place Selected." % _count(_all_items.size(), "item", "items"))


## Re-read the items folder, rebuild the rows through the current filter, and restore the previously picked item BY
## PATH (a row index is meaningless after a resort or a new file). Clears the filesystem-dirty flag and writes the
## scan verdict to the status: the idle next step, or the files that failed to load.
func _reload() -> void:
	var keep := _picked_path()
	var rep := ItemScan.scan_report()
	_all_items = []
	for it: Item in rep["items"]:
		_all_items.append(it)
	_all_items.sort_custom(_row_before)
	_skipped = rep["skipped"]
	_fs_dirty = false
	_rebuild_rows(keep)
	if not _skipped.is_empty():
		var names := PackedStringArray()
		for p: String in _skipped:
			names.append(p.get_file())
		_set_status("Couldn't load %s: %s -- still importing? press Refresh." % [_count(_skipped.size(), "item file", "item files"), ", ".join(names)], true)
	elif _all_items.is_empty():
		_set_status("No items found in the items folder -- create one in the New tab, then Refresh.", true)
	else:
		_set_status(MSG_IDLE)


## Thin wrapper over the shared scan (tests call it): every authored Item under resources/items/, folder order.
static func _scan_items() -> Array[Item]:
	return ItemScan.scan()


## Rebuild the ItemList rows from `_all_items` through the search filter, keeping `_items` index-parallel with what
## is shown, then re-pick `keep_path` if its row survived. ItemList.clear() drops the selection silently (no
## item_selected), so the Place gate is re-derived here -- a filter that hid the picked row must grey the button.
func _rebuild_rows(keep_path: String = "") -> void:
	if _list == null:
		return
	_list.clear()
	_items = []
	var filter := _search.text.strip_edges().to_lower() if _search != null else ""
	for it in _all_items:
		var text := _row_text(it)
		if filter != "" and not (text.to_lower().contains(filter) or it.resource_path.get_file().to_lower().contains(filter)):
			continue
		var idx := _list.add_item(text)
		_list.set_item_tooltip(idx, it.resource_path)  # the file path lives on the row's tooltip, never in the row text
		_items.append(it)
	_select_by_path(keep_path)
	_update_place_state()


## Pick the shown row whose item is saved at `path` (no-op on ""), scrolling it into view. ItemList.select() does
## not emit item_selected, so the Place gate is refreshed here. false when no shown row matches.
func _select_by_path(path: String) -> bool:
	if _list == null or path.is_empty():
		return false
	for i in _items.size():
		if _items[i].resource_path == path:
			_list.select(i)
			_list.ensure_current_is_visible()
			_update_place_state()
			return true
	return false


## The Item behind the picked row, or null (nothing picked, or a stale index from a rebuild in flight).
func _picked_item() -> Item:
	if _list == null:
		return null
	var sel := _list.get_selected_items()
	if sel.is_empty():
		return null
	var i: int = sel[0]
	if i < 0 or i >= _items.size():
		return null
	return _items[i]


## The picked item's file path, or "" -- the key every rescan / filter rebuild restores the pick by.
func _picked_path() -> String:
	var it := _picked_item()
	return it.resource_path if it != null else ""


## Drop the picked item into the open scene as ONE undoable action, then make it the editor selection. Guards run
## scene-first and BEFORE the node is built, so a refusal never has an orphan to free. Every early return writes its
## sentence to the status because a double-click on a row reaches here even while Place Selected is disabled.
func _place() -> void:
	var root := EditorInterface.get_edited_scene_root()
	on_scene_changed(root)  # keep the button state honest with what this click just observed
	if root == null:
		_set_status(MSG_NO_SCENE)
		return
	var it := _picked_item()
	if it == null:
		_set_status(MSG_NO_PICK)
		return
	var node := _make_pickup(it)
	if node == null:
		_set_status("Couldn't build %s: its pickup scene didn't load." % _item_label(it))
		return
	var sel := EditorInterface.get_selection().get_selected_nodes()
	var picked: Node = sel[0] if not sel.is_empty() else null
	var parent := _parent_for(sel, root)
	var pos := _viewport_focus()
	var ur := EditorInterface.get_editor_undo_redo()
	ur.create_action("Place %s" % _item_label(it))
	ur.add_do_method(parent, "add_child", node)
	ur.add_do_reference(node)
	ur.add_do_method(PlaceOps, "own_recursive", node, root)  # own the whole built subtree so every node saves (the ONE tested static)
	ur.add_do_property(node, "global_position", pos)  # drop it in front of the editor camera, not at the origin
	ur.add_undo_method(parent, "remove_child", node)
	ur.commit_action()
	_last_placed = node
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(node)
	# An authored world_prop that actually loaded roots ITS scene; anything else is the default throwable shell
	# (WorldItem.build falls back to it when the prop scene is missing, so the field alone would misreport).
	var kind := "authored prop" if (not it.world_prop.is_empty() and node.scene_file_path == it.world_prop) else "throwable pickup"
	var where := "under %s" % parent.name if parent != root else "under the scene root"
	# Name the redirect when the sibling rule moved the pickup off the selected node, so "under Props" instead of
	# "under the pickup I just dropped" never reads as the tab ignoring the Scene-tree selection.
	if picked != null and is_instance_valid(picked) and parent != picked:
		where = "beside %s, %s" % [picked.name, where]
	_set_status("Placed %s (%s) %s -- selected; drag to fine-tune, then save the scene." % [_item_label(it), kind, where])


## Where a new item goes: under the node selected in the Scene tree, or the scene root -- EXCEPT when that selection
## is the item this tab placed last (placing auto-selects it), where the new one lands BESIDE it, under the same
## parent. The Place and Palette tabs carry the same rule; without it two quick placements nest the second pickup
## inside the first's physics body. `sel` is the editor selection (may be empty); pure over its inputs (plus the
## remembered node), so tests/test_devtools_docks.gd drives it off-tree.
func _parent_for(sel: Array[Node], root: Node) -> Node:
	if sel.is_empty():
		return root
	var picked: Node = sel[0]
	# A selection held across a scene close can hand back a freed node; is_instance_valid FIRST, always (a freed
	# Object compares UNEQUAL to null, so a bare null test would let a dangling reference through to add_child).
	if not is_instance_valid(picked):
		return root
	if is_instance_valid(_last_placed) and picked == _last_placed:
		var up := _last_placed.get_parent()
		if up != null:
			return up
		return root
	return picked


## Where to drop a placed item: ~3 m in front of the 3D editor camera so it lands in view (not at the world origin).
## Falls back to the origin if there's no open 3D viewport / camera.
func _viewport_focus() -> Vector3:
	var vp := EditorInterface.get_editor_viewport_3d(0)
	if vp == null:
		return Vector3.ZERO
	var cam := vp.get_camera_3d()
	if cam == null:
		return Vector3.ZERO
	return cam.global_position - cam.global_basis.z * 3.0


## Build a placed item IDENTICAL to an inventory drop: WorldItem.build yields a Throwable (carry/throw with Z)
## carrying a CanPickUp child (loot with E), or the item's authored world_prop scene as-is. Same canonical builder
## Player.drop_item uses, so the behavior matches exactly -- gravity, grab, throw, loot. Its box / weapon-view-model
## visual is a real mesh, so it renders in the editor too (unlike CanPickUp's runtime-only build).
func _make_pickup(it: Item) -> Node:
	if it == null:
		return null
	var node := WorldItem.build(it, 1)
	if node != null:
		node.name = _node_name_for(it)
	return node


## The designer-facing name for status lines and undo entries: display name, else id (Item.label()), else the FILE
## name. Item.label() answers "Item" for a resource with neither, which would be a useless row -- the file name is
## what the designer can find in the FileSystem dock.
static func _item_label(it: Item) -> String:
	if it == null:
		return "(no item)"
	if not it.display_name.is_empty() or it.id != &"":
		return it.label()
	if it.resource_path != "":
		return it.resource_path.get_file().get_basename()
	return it.label()


## A list row: "<display name>  (<id>)". The bracketed id is dropped when the row already shows it (a blank display
## name falls back to the id) or the item has none -- never an empty "()".
static func _row_text(it: Item) -> String:
	var lbl := _item_label(it)
	if it != null and not it.display_name.is_empty() and it.id != &"":
		return "%s  (%s)" % [lbl, String(it.id)]
	return lbl


## Sort order for the rows: by row text, case-insensitive with natural number ordering ("Ammo 9" before "Ammo 10").
static func _row_before(a: Item, b: Item) -> bool:
	return _row_text(a).naturalnocasecmp_to(_row_text(b)) < 0


## "1 item" / "3 items" for a status line -- designer words, so a real plural rather than a bare "(s)".
static func _count(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]


## The placed node's name: "Item_<id>" (stable and path-safe), else the label, sanitised for the scene tree.
static func _node_name_for(it: Item) -> String:
	var key := String(it.id) if (it != null and it.id != &"") else _item_label(it)
	return ("Item_%s" % key).validate_node_name()
