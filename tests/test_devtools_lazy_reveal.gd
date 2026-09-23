extends GutTest

## PL6: the disk-scanning CYBER SUNDAY tabs scan on FIRST REVEAL (a visibility_changed latch), NOT at panel
## construction -- so opening the panel doesn't fan out a res:// / user:// folder walk for every tab at once (all ~20
## docks are built eagerly in cyber_panel._init). content_browser is the original reference (already lazy; not
## re-tested here).
##
## Pinned by BEHAVIOUR, per dock, through the widget the scan fills (a picker, a list, or the rows box):
##   1. building the tab off-tree (what cyber_panel._init does; test_devtools_layout.gd already requires every tab's
##      _init to be off-tree safe) leaves that widget EMPTY -- an eager scan in _init, however it is spelled, fills it;
##   2. mounted in the tree but still HIDDEN (a background tab) a visibility pass does not scan either, and the first
##      show() -- delivered through the real visibility_changed connection -- DOES fill it (the control that proves
##      the empty widget in 1 and 2 is a real "not scanned", and that the signal is wired to the handler);
##   3. switching away and back to an already-revealed tab does not re-walk the folder (a rescan would rebuild the
##      widget under the designer's pick) -- with a control showing the same hide/show DOES rebuild it while the
##      latch is down, so the sentinel really can see a rescan.
## quest_graph rides the table too: it extends dialogue_graph and must stay lazy by inheritance (its own _init only
## flips the mode picker to Quest).
##
## Every dock here is a plain Control tree whose _init touches no EditorInterface outside an is_editor_hint() guard, so
## mounting one under GUT is safe; every mounted dock goes through add_child_autofree, every bare one is freed.

const DOCKS := [
	{"path": "res://addons/cybersunday_tools/dock_tuning/tuning_browser.gd", "widget": "_list"},
	{"path": "res://addons/cybersunday_tools/dock_loot/loot_editor.gd", "widget": "_table_pick"},
	{"path": "res://addons/cybersunday_tools/dock_quest/quest_editor.gd", "widget": "_picker"},
	{"path": "res://addons/cybersunday_tools/dock_saves/save_inspector.gd", "widget": "_picker"},
	{"path": "res://addons/cybersunday_tools/dock_dialogue/dialogue_editor.gd", "widget": "_picker"},
	{"path": "res://addons/cybersunday_tools/panel_graph/dialogue_graph.gd", "widget": "_picker"},
	{"path": "res://addons/cybersunday_tools/panel_graph/quest_graph.gd", "widget": "_picker"},
	{"path": "res://addons/cybersunday_tools/placer/item_placer_dock.gd", "widget": "_list"},
	{"path": "res://addons/cybersunday_tools/dock_text/text_editor.gd", "widget": "_list_box"},
	{"path": "res://addons/cybersunday_tools/dock_bark/bark_editor.gd", "widget": "_picker"},
	{"path": "res://addons/cybersunday_tools/dock_uicopy/ui_copy_editor.gd", "widget": "_list_box"},
	{"path": "res://addons/cybersunday_tools/dock_item/item_editor.gd", "widget": "_picker"},
]

## Written over row 0 of a picker / list to detect a rebuild: no scanned file is ever labelled this.
const SENTINEL := "<<lazy-reveal sentinel: a rescan rebuilds this row>>"


func test_building_a_scanning_tab_fills_nothing_from_disk() -> void:
	for spec: Dictionary in DOCKS:
		var path := String(spec["path"])
		var widget := String(spec["widget"])
		var script: GDScript = load(path)
		var d = script.new()
		assert_eq(_scan_rows(d, widget), 0,
			"%s: building the tab must leave %s empty -- the panel builds every tab at once, so a scan in _init walks the disk for all of them" % [path.get_file(), widget])
		assert_false(bool(d._revealed), "%s: construction is not a reveal, so the first-reveal latch is still down" % path.get_file())
		assert_true(d.visibility_changed.is_connected(Callable(d, "_on_visibility_changed")),
			"%s: visibility_changed must reach _on_visibility_changed, or the tab stays empty when the designer opens it" % path.get_file())
		d.free()


func test_a_hidden_tab_waits_and_its_first_show_fills_it() -> void:
	for spec: Dictionary in DOCKS:
		var path := String(spec["path"])
		var widget := String(spec["widget"])
		var d = _mount_hidden(path)
		d._on_visibility_changed()  # a visibility pass while the tab is still a background tab in the tree
		assert_eq(_scan_rows(d, widget), 0,
			"%s: a tab that is in the tree but hidden has not been revealed -- %s must stay empty" % [path.get_file(), widget])
		assert_false(bool(d._revealed), "%s: a hidden visibility pass must not spend the first-reveal latch" % path.get_file())
		d.show()  # the TabContainer switching to this tab: visibility_changed fires through the real connection
		assert_gt(_scan_rows(d, widget), 0,
			"%s: the first show must scan the folder and fill %s (otherwise the designer opens an empty tab)" % [path.get_file(), widget])
		assert_true(bool(d._revealed), "%s: the first show latches the reveal so the scan runs once" % path.get_file())


func test_showing_an_already_revealed_tab_again_does_not_rescan() -> void:
	for spec: Dictionary in DOCKS:
		var path := String(spec["path"])
		var widget := String(spec["widget"])
		var d = _mount_hidden(path)
		d.show()
		var planted: Object = _plant_sentinel(d, widget)
		d.hide()
		d.show()
		assert_true(_sentinel_survived(d, widget, planted),
			"%s: switching away and back must not re-walk the folder and rebuild %s under the designer's pick" % [path.get_file(), widget])
		# CONTROL: with the latch knocked down the very same hide/show DOES rescan, so the sentinel can see a rebuild.
		d._revealed = false
		d.hide()
		d.show()
		assert_false(_sentinel_survived(d, widget, planted),
			"%s: control -- a reveal with the latch down rescans and rebuilds %s (the sentinel must be able to see that)" % [path.get_file(), widget])


# --- helpers ------------------------------------------------------------------------------------------------------

## A dock built bare, hidden, then parented under this test (autofreed) -- a background tab that has never been shown.
func _mount_hidden(path: String) -> Control:
	var script: GDScript = load(path)
	var d: Control = script.new()
	d.hide()
	add_child_autofree(d)
	return d


## How many rows the scan put in `widget`: items for a picker / list, child rows for a VBox. -1 = no such widget.
func _scan_rows(d: Object, widget: String) -> int:
	var w: Object = d.get(widget)
	if w is OptionButton:
		return (w as OptionButton).item_count
	if w is ItemList:
		return (w as ItemList).item_count
	if w is Node:
		return (w as Node).get_child_count()
	return -1


## Mark what the last scan built: rename row 0 of a picker / list (a rebuild re-adds it under its real label), or hand
## back the first child of a rows box (a rebuild queue_frees it). Returns that child, or null for a picker / list.
func _plant_sentinel(d: Object, widget: String) -> Object:
	var w: Object = d.get(widget)
	if w is OptionButton and (w as OptionButton).item_count > 0:
		(w as OptionButton).set_item_text(0, SENTINEL)
	elif w is ItemList and (w as ItemList).item_count > 0:
		(w as ItemList).set_item_text(0, SENTINEL)
	elif w is Node and (w as Node).get_child_count() > 0:
		return (w as Node).get_child(0)
	return null


func _sentinel_survived(d: Object, widget: String, planted: Object) -> bool:
	var w: Object = d.get(widget)
	if w is OptionButton:
		return (w as OptionButton).item_count > 0 and (w as OptionButton).get_item_text(0) == SENTINEL
	if w is ItemList:
		return (w as ItemList).item_count > 0 and (w as ItemList).get_item_text(0) == SENTINEL
	return is_instance_valid(planted) and not (planted as Node).is_queued_for_deletion()
