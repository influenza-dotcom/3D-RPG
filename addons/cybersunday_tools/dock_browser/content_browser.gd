@tool
extends Control

## UNIFIED CONTENT BROWSER (tab "Browse"): ONE place to find + open ANY content .tres in the project. Where the Tuning
## browser only lists resources/tuning/, this scans EVERY content folder the New tab can write to and shows the files
## in a Tree grouped by content type. A search LineEdit filters live; double-click a row opens it in the Inspector
## (EditorInterface.edit_resource) AND reveals it in the FileSystem dock (EditorInterface.select_file). READ-ONLY: this
## tab never writes a file (QA "Read-only means read-only" -- Browse is on that list).
##
## SOURCE OF TRUTH for the folders: the dock_content/content_dock.gd DIR consts (quests/characters/weapons/items/
## factions/dialogue/loot/perks/status/encounters/schedules/cutscenes/barks/loadouts/abilities/maps/interactables)
## PLUS the folders other tools generate into -- resources/levels (Level tab's New Level), resources/stats (StatText,
## read by the Text tab), resources/parts (body-part .tres under arms/bodies/heads/legs) -- and resources/tuning/.
## ROOTS below must cover every one of those, or a file a designer just generated goes missing from the one tab
## whose job is "find any content file". The PURE scan/filter lives in browse_scan.gd so the GUT test
## (tests/test_devtools_browser.gd) exercises the grouping + search WITHOUT EditorInterface; this file is editor
## glue only.
##
## Host seams (cyber_panel.gd): select_path(path) lets the panel hand a specific file to this tab (find + pick it,
## rescanning if the folders changed and clearing the search when it hid the row). The editor's filesystem_changed
## only raises `_fs_dirty`; the rescan waits for the NEXT reveal of the tab (never mid-edit, never under the
## designer's pick) and keeps the picked row by PATH, never by Tree position. Refresh is the explicit fallback.
##
## OFF-TREE CONTRACT: GUT and the headless probe construct this tab bare (.new(), no parent, no tree), so every widget
## is built in _init and _init never touches EditorInterface / get_tree() outside `if Engine.is_editor_hint():`.
## Editor calls live in the double-click handler, the Refresh handler, and the first-reveal latch (all in-tree).
##
## HEIGHT CONTRACT: this is the one tab that extends a bare Control (a Container would fight the Tree's own
## scrolling). A bare Control's minimum ignores its children, so _get_minimum_size() forwards the anchored VBox's
## combined minimum: the action bar + a 100 px Tree floor + a two-line status, ~180 px in all. That matters because
## a TabContainer's minimum is the CURRENT tab's minimum, and the editor's bottom splitter keeps whatever height it
## grew to -- an oversized floor here would push every other tool taller for the rest of the session.

const Browse := preload("res://addons/cybersunday_tools/dock_browser/browse_scan.gd")

## Designer-facing content-type label -> res:// folder. Mirrors the content_dock.gd DIR consts plus the other
## generated-content folders (see the header). The label is the Tree group header; the order here is the order the
## groups appear (gameplay content first, world/level data next, tuning last). Every key is preserved by the scan
## even when its folder is empty, so the designer sees the section exists ("Quests (0)"). The scan is recursive, so
## a folder with sub-folders (resources/parts/arms, /bodies, /heads, /legs) still lands as one flat group.
const ROOTS := {
	"Quests": "res://resources/quests/",
	"NPCs": "res://resources/characters/",
	"Weapons": "res://resources/weapons/",
	"Items": "res://resources/items/",
	"Throwables": "res://resources/interactables/",
	"Factions": "res://resources/factions/",
	"Dialogue": "res://resources/dialogue/",
	"Loot Tables": "res://resources/loot/",
	"Perks": "res://resources/perks/",
	"Status Effects": "res://resources/status/",
	"Abilities": "res://resources/abilities/",
	"Encounters": "res://resources/encounters/",
	"Schedules": "res://resources/schedules/",
	"Cutscenes": "res://resources/cutscenes/",
	"Barks": "res://resources/barks/",
	"Loadouts": "res://resources/loadouts/",
	"Parts": "res://resources/parts/",
	"Maps": "res://resources/maps/",
	"Levels": "res://resources/levels/",
	"Stat Text": "res://resources/stats/",
	"Tuning": "res://resources/tuning/",
}

## Idle status: the one next step, plus the answer to the question this tab gets asked most ("where do I tune a gun?").
const MSG_IDLE := "Search every content file by name; double-click opens it in the Inspector. Weapon balance lives on each weapon file -- open one from the Weapons group."
## Written to the status before a disk walk so the designer sees the tab is busy, not frozen.
const MSG_SCANNING := "Scanning..."
## Refresh = re-read the list from disk. Never touches what is open in the Inspector.
const REFRESH_TIP := "Re-reads every content folder from disk -- press it when a file you just made is not listed. Read-only."
const SEARCH_TIP := "Type part of a file name or folder name; the list narrows as you type. Read-only."
## Status colour for a refusal / an empty result (the plain text colour is the calm default).
const WARN_COLOR := Color(1.0, 0.85, 0.4)

## Tree floor: small so the tab can shrink on a short bottom panel; the Tree scrolls itself, so nothing is lost.
const TREE_MIN_HEIGHT := 100.0

var _root: VBoxContainer = null   ## anchored full-rect; its combined minimum is this Control's minimum
var _search: LineEdit = null
var _refresh: Button = null
var _tree: Tree = null
var _status: Label = null
var _grouped: Dictionary = {}   ## the last full scan: { group label -> Array[String] of res:// paths }

## Lazy first-reveal latch: the recursive res:// walk runs on first reveal, not at panel construction, so a plugin
## reload (which rebuilds every tab) doesn't pay for a full-project scan nobody is looking at.
var _revealed := false
## Raised by the editor's filesystem_changed (connected in _init, editor only). A rescan while the tab is showing
## would swap the rows under the designer's pick, so it waits for the next reveal; Refresh is the explicit fallback.
var _fs_dirty := false
## True between "Scanning..." and the rebuilt Tree; drops a second scan request that lands mid-walk.
var _scanning := false


func _init() -> void:
	name = "Browse"
	custom_minimum_size = Vector2(110, 90)  # absolute floor; the real minimum comes from the VBox (see _get_minimum_size)

	_root = VBoxContainer.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_theme_constant_override("separation", 4)
	_root.minimum_size_changed.connect(update_minimum_size)
	add_child(_root)

	var bar := HBoxContainer.new()
	_root.add_child(bar)

	_search = LineEdit.new()
	_search.placeholder_text = "Search..."
	_search.tooltip_text = SEARCH_TIP
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(_on_search_changed)
	bar.add_child(_search)

	_refresh = Button.new()
	_refresh.text = "Refresh"
	_refresh.tooltip_text = REFRESH_TIP
	_refresh.pressed.connect(_on_refresh_pressed)
	bar.add_child(_refresh)

	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.custom_minimum_size = Vector2(0, TREE_MIN_HEIGHT)
	_tree.hide_root = true
	_tree.allow_rmb_select = false
	_tree.item_activated.connect(_on_item_activated)   # double-click = open
	_root.add_child(_tree)

	# What the tab just DID or REFUSED (or the next step). Clamped to two lines with the full text on its tooltip, so
	# a long file name can never push the Tree off a short bottom panel.
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 2
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.modulate = Color(1, 1, 1, 0.75)
	_root.add_child(_status)
	_set_status(MSG_IDLE)

	if Engine.is_editor_hint():
		# Editor only (EditorInterface does not exist headless). The connection dies with this Control -- Godot
		# disconnects every signal aimed at an Object when that Object is freed -- so a plugin reload leaves nothing
		# dangling on the editor's filesystem scanner.
		var fs := EditorInterface.get_resource_filesystem()
		if fs != null:
			fs.filesystem_changed.connect(_on_filesystem_changed)

	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()  # no-op off-tree (not visible); in the editor the real reveal fires the signal


## A bare Control's minimum ignores its children; forward the anchored VBox's so the TabContainer (whose minimum is
## the CURRENT tab's) reserves the bar + Tree floor + status instead of clipping them on a short bottom panel.
func _get_minimum_size() -> Vector2:
	if _root == null:
		return Vector2.ZERO
	return _root.get_combined_minimum_size()


## Lazy first-reveal: walk the folders ONCE, the first time the tab is actually shown (not at construction). Later
## reveals rescan only when the editor's filesystem changed while the tab was hidden -- keeping the picked row by
## path (see _scan_now). The Refresh button stays the explicit re-scan.
func _on_visibility_changed() -> void:
	if is_visible_in_tree() and not _revealed:
		_revealed = true
		_scan_now()
	elif is_visible_in_tree() and _fs_dirty:
		_scan_now()


## The editor's FileSystem scanner noticed a change (a new / saved / deleted file anywhere). Only flag it: the
## rescan runs on the next reveal, never under the designer's pick while the tab is showing.
func _on_filesystem_changed() -> void:
	_fs_dirty = true


## Refresh (explicit): re-read every folder from disk. Never touches what is open in the Inspector.
func _on_refresh_pressed() -> void:
	_scan_now(true)


## Walk every content folder from disk into _grouped, then (re)build the Tree honouring the current search box, and
## re-pick whatever row was picked -- by PATH, so a file that moved rows (a new neighbour sorted above it) stays
## picked. In-tree it yields one frame first so "Scanning..." actually paints before the walk; off-tree (the headless
## probe) it runs straight through. `explicit` = the designer pressed Refresh, which earns a "Refreshed" line; the
## lazy paths fall back to the idle / filter status from _rebuild.
func _scan_now(explicit: bool = false) -> void:
	if _scanning:
		return
	_scanning = true
	_set_status(MSG_SCANNING)
	if _refresh != null:
		_refresh.disabled = true
	if is_inside_tree():
		await get_tree().process_frame
	# The row to re-pick is read AFTER the frame yield, never before it: select_path() (the host handoff) is
	# synchronous and can land in that gap, and a `keep` captured earlier would put the OLD row back over it.
	var keep := _selected_path()
	_fs_dirty = false  # cleared right before the walk: a change landing after it raises the flag again
	_grouped = Browse.scan_grouped(ROOTS)
	_scanning = false
	if _refresh != null:
		_refresh.disabled = false
	_rebuild()
	_select_in_tree(keep)
	if explicit:
		_set_status("Refreshed the list -- %s in %d groups." % [_count(_total(), "file", "files"), ROOTS.size()])


## Rebuild the Tree from _grouped, filtered by the search box. Each group is a parent row (label + count); each file
## is a child row showing its FILE NAME, with the full path on the row tooltip and in its metadata (read back on
## double-click and by the by-path re-pick). PURE model -> editor widget; also writes the idle / filter status.
func _rebuild() -> void:
	if _tree == null:
		return
	_tree.clear()
	var needle := _search.text.strip_edges() if _search != null else ""
	var view := Browse.filter_grouped(_grouped, needle) if needle != "" else _grouped

	var tree_root := _tree.create_item()
	var shown := 0
	# Iterate ROOTS so the group order is stable (a filtered view is a subset of these keys).
	for label in ROOTS:
		if not view.has(label):
			continue
		var paths: Array = view[label]
		if needle == "" and paths.is_empty():
			# Unfiltered: still show empty groups so the designer sees the section exists (e.g. "Quests (0)").
			var empty_parent := _tree.create_item(tree_root)
			empty_parent.set_text(0, "%s (0)" % String(label))
			empty_parent.set_selectable(0, false)
			empty_parent.set_custom_color(0, Color(1, 1, 1, 0.5))
			continue
		if paths.is_empty():
			continue
		var parent := _tree.create_item(tree_root)
		parent.set_text(0, "%s (%d)" % [String(label), paths.size()])
		parent.set_selectable(0, false)
		for p in paths:
			var path := String(p)
			var child := _tree.create_item(parent)
			child.set_text(0, path.get_file())
			child.set_tooltip_text(0, path)
			child.set_metadata(0, path)
			shown += 1

	var grand := _total()
	if needle == "":
		if grand == 0:
			_set_status("No content files found -- create one in the New tab, then press Refresh.", true)
		else:
			_set_status(MSG_IDLE)
	elif shown == 0:
		_set_status("No file matches '%s' -- check the spelling, or press Refresh if it was just created." % needle, true)
	else:
		_set_status("%d of %d files match '%s' -- double-click opens one in the Inspector." % [shown, grand, needle])


## Live search -- rebuild the filtered Tree on each keystroke. (filter is PURE; the rebuild is cheap.)
func _on_search_changed(_text: String) -> void:
	_rebuild()


## Host seam: find + pick the row for `path` (a res:// file), walking the folders first if this tab has never been
## revealed (or the folders changed since), and clearing the search when it hid the row. Synchronous on purpose --
## the host reads the bool straight back. true when the row is now picked; false when no such file is in any group.
func select_path(path: String) -> bool:
	if path.is_empty():
		return false
	if not _revealed or _fs_dirty or _grouped.is_empty():
		_revealed = true
		_fs_dirty = false
		_grouped = Browse.scan_grouped(ROOTS)
		_rebuild()
	if _select_in_tree(path):
		return true
	if _search != null and _search.text != "":
		_search.text = ""  # the setter does not emit text_changed, so rebuild by hand
		_rebuild()
		return _select_in_tree(path)
	return false


## Double-click a file row: open it in the Inspector AND reveal it in the FileSystem dock. EDITOR-ONLY
## (EditorInterface) -- never exercised by the GUT test. Group rows carry no metadata, so they no-op.
func _on_item_activated() -> void:
	var path := _selected_path()
	if path == "":
		return
	var res := load(path)
	if res == null:
		_set_status("Couldn't open %s: the file did not load -- is a reimport still running? Try Refresh." % path.get_file(), true)
		return
	EditorInterface.edit_resource(res)
	EditorInterface.select_file(path)  # reveal in the FileSystem dock
	_set_status("Opened %s in the Inspector -- also selected in the FileSystem dock." % path.get_file())


# ──────────────────────────────────────────────────────────────────────────────────────────────────────────
# Small helpers
# ──────────────────────────────────────────────────────────────────────────────────────────────────────────

## The res:// path carried by the picked Tree row, or "" (nothing picked, or a group header).
func _selected_path() -> String:
	if _tree == null:
		return ""
	var item := _tree.get_selected()
	if item == null:
		return ""
	var md: Variant = item.get_metadata(0)
	if md is String:
		return String(md)
	return ""


## Pick the row whose metadata is `path` (and scroll it into view). Selection survives a rescan by PATH, never by
## Tree position -- a new file sorted above the picked one shifts every row below it. false when no row carries it.
func _select_in_tree(path: String) -> bool:
	if _tree == null or path == "":
		return false
	var tree_root := _tree.get_root()
	if tree_root == null:
		return false
	var group := tree_root.get_first_child()
	while group != null:
		var row := group.get_first_child()
		while row != null:
			var md: Variant = row.get_metadata(0)
			if md is String and String(md) == path:
				row.select(0)
				_tree.scroll_to_item(row)
				return true
			row = row.get_next()
		group = group.get_next()
	return false


## True total across the unfiltered model (every group), for the status line.
func _total() -> int:
	var grand := 0
	for label in _grouped:
		grand += (_grouped[label] as Array).size()
	return grand


## "1 file" / "12 files" -- a developer surface (editor tooling), so no PlayerText / TextFormat.
static func _count(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]


## One writer for the status line: the tooltip mirrors the full text (the label is clamped to two lines), and a
## refusal / empty result is tinted via a theme override (never bbcode -- this is a plain Label).
func _set_status(msg: String, warn: bool = false) -> void:
	if _status == null:
		return
	_status.text = msg
	_status.tooltip_text = msg
	if warn:
		_status.add_theme_color_override("font_color", WARN_COLOR)
	else:
		_status.remove_theme_color_override("font_color")
