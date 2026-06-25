@tool
extends Control

## UNIFIED CONTENT BROWSER (tab "Browse"): ONE place to find + open ANY content .tres in the project. Where the Tuning
## browser only lists resources/tuning/, this scans EVERY content folder (Quests / NPCs / Weapons / Items / Factions /
## Dialogue / LootTables / Perks / StatusEffects / Encounters / Schedules / Cutscenes / Barks / Loadouts / Abilities /
## Maps / Tuning) and shows them in a Tree grouped by content type. A search
## LineEdit filters live; double-click a row opens it in the Inspector (EditorInterface.edit_resource) AND reveals it in
## the FileSystem dock (EditorInterface.select_file). Refresh re-scans from disk.
##
## SOURCE OF TRUTH for the folders: the dock_content/content_dock.gd DIR consts (quests/characters/weapons/items/
## factions/dialogue/loot/perks/status/encounters/schedules/cutscenes/barks/loadouts/abilities/maps) +
## resources/tuning/. The PURE scan/filter lives in browse_scan.gd so the
## GUT test exercises the grouping + search WITHOUT EditorInterface; this file is editor glue only.

const Browse := preload("res://addons/cybersunday_tools/dock_browser/browse_scan.gd")

## Designer-facing content-type label -> res:// folder. Mirrors the content_dock.gd DIR consts (verified) plus tuning.
## The label is the Tree group header; the order here is the order the groups appear.
const ROOTS := {
	"Quests": "res://resources/quests/",
	"NPCs": "res://resources/characters/",
	"Weapons": "res://resources/weapons/",
	"Items": "res://resources/items/",
	"Factions": "res://resources/factions/",
	"Dialogue": "res://resources/dialogue/",
	"LootTables": "res://resources/loot/",
	"Perks": "res://resources/perks/",
	"StatusEffects": "res://resources/status/",
	"Encounters": "res://resources/encounters/",
	"Schedules": "res://resources/schedules/",
	"Cutscenes": "res://resources/cutscenes/",
	"Barks": "res://resources/barks/",
	"Loadouts": "res://resources/loadouts/",
	"Abilities": "res://resources/abilities/",
	"Maps": "res://resources/maps/",
	"Tuning": "res://resources/tuning/",
}

var _search: LineEdit = null
var _tree: Tree = null
var _status: Label = null
var _grouped: Dictionary = {}   ## the last full scan: { group label -> Array[String] of res:// paths }
var _scanned := false           ## lazy first scan: the recursive res:// walk runs on first reveal, not at _ready


func _init() -> void:
	name = "Browse"
	custom_minimum_size = Vector2(110, 90)  # small floor so the tab can shrink on a short display (per spec ~90-120)


func _ready() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	var head := Label.new()
	head.text = "Content browser -- every content .tres in one place"
	root.add_child(head)

	var bar := HBoxContainer.new()
	root.add_child(bar)

	_search = LineEdit.new()
	_search.placeholder_text = "Search by name..."
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(_on_search_changed)
	bar.add_child(_search)

	var refresh := Button.new()
	refresh.text = "Refresh"
	refresh.pressed.connect(_rescan)
	bar.add_child(refresh)

	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.custom_minimum_size = Vector2(0, 90)  # small floor so the dock can shrink on a short display
	_tree.hide_root = true
	_tree.allow_rmb_select = false
	_tree.item_activated.connect(_on_item_activated)   # double-click = open
	root.add_child(_tree)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = Color(1, 1, 1, 0.75)
	root.add_child(_status)

	# LAZY first scan: the recursive res:// walk is deferred until this tab is first revealed, so a plugin reload
	# (which re-_ready()s every tab) doesn't pay for a full-project scan nobody's looking at. Refresh re-scans on demand.
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()  # cover the case where the tab is already visible on _ready


## First-reveal hook: scan once the tab actually becomes visible. The Refresh button stays the explicit re-scan.
func _on_visibility_changed() -> void:
	if is_visible_in_tree() and not _scanned:
		_scanned = true
		_rescan()


## Walk every content folder from disk into _grouped, then (re)build the Tree honouring the current search needle.
func _rescan() -> void:
	_grouped = Browse.scan_grouped(ROOTS)
	_rebuild()


## Rebuild the Tree from _grouped, filtered by the search box. Each group is a parent row (label + count); each resource
## is a child row whose metadata carries its res:// path (read back on double-click). PURE model -> editor widget.
func _rebuild() -> void:
	if _tree == null:
		return
	_tree.clear()
	var needle := _search.text if _search != null else ""
	var view := Browse.filter_grouped(_grouped, needle) if needle.strip_edges() != "" else _grouped

	var tree_root := _tree.create_item()
	var shown := 0
	var total := 0
	# Iterate ROOTS so the group order is stable (a filtered view is a subset of these keys).
	for label in ROOTS:
		if not view.has(label):
			continue
		var paths: Array = view[label]
		if needle.strip_edges() == "" and paths.is_empty():
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
			child.set_text(0, path.get_file().get_basename())
			child.set_tooltip_text(0, path)
			child.set_metadata(0, path)
			shown += 1
		total += paths.size()

	# Count the true total across the unfiltered model for the status line.
	var grand := 0
	for label in _grouped:
		grand += (_grouped[label] as Array).size()
	if _status != null:
		if needle.strip_edges() == "":
			_status.text = "%d content resource(s) across %d groups. Double-click to open." % [grand, ROOTS.size()]
		else:
			_status.text = "%d of %d match '%s'." % [shown, grand, needle.strip_edges()]


## Live search -- rebuild the filtered Tree on each keystroke. (filter is PURE; the rebuild is cheap.)
func _on_search_changed(_text: String) -> void:
	_rebuild()


## Double-click a resource row: open it in the Inspector AND reveal it in the FileSystem dock. EDITOR-ONLY
## (EditorInterface) -- never exercised by the GUT test. Group rows carry no metadata, so they no-op.
func _on_item_activated() -> void:
	if _tree == null:
		return
	var item := _tree.get_selected()
	if item == null:
		return
	var md: Variant = item.get_metadata(0)
	if not (md is String) or String(md) == "":
		return
	var path := String(md)
	var res := load(path)
	if res == null:
		if _status != null:
			_status.text = "Could not load %s" % path
		return
	EditorInterface.edit_resource(res)
	EditorInterface.select_file(path)  # reveal in the FileSystem dock
	if _status != null:
		_status.text = "Opened %s in the Inspector." % path.get_file()
