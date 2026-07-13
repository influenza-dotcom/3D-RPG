extends GutTest

## PL6: the disk-scanning CYBER SUNDAY tabs scan on FIRST REVEAL (a visibility_changed latch), NOT at panel
## construction — so opening the panel doesn't fan out a res:// / user:// folder walk for every tab at once (all ~20
## docks are built eagerly in cyber_panel._init). This pins the lazy pattern in each converted dock by SOURCE-SCAN:
## instantiating an editor dock headless builds a pile of Controls for no benefit and risks editor-only calls, so we
## assert the STRUCTURE instead — a _revealed latch, a visibility_changed -> _on_visibility_changed connection, a
## once-guard on (is_visible_in_tree() and not _revealed), and the _revealed = true latch set. content_browser is the
## original reference (already lazy; not re-tested here).

const LAZY_DOCKS := [
	"res://addons/cybersunday_tools/dock_tuning/tuning_browser.gd",
	"res://addons/cybersunday_tools/dock_loot/loot_editor.gd",
	"res://addons/cybersunday_tools/dock_quest/quest_editor.gd",
	"res://addons/cybersunday_tools/dock_saves/save_inspector.gd",
	"res://addons/cybersunday_tools/dock_dialogue/dialogue_editor.gd",
	"res://addons/cybersunday_tools/panel_graph/dialogue_graph.gd",
	"res://addons/cybersunday_tools/placer/item_placer_dock.gd",
	"res://addons/cybersunday_tools/dock_text/text_editor.gd",
]


func test_disk_scanning_docks_are_lazy_on_first_reveal() -> void:
	for path in LAZY_DOCKS:
		var src := FileAccess.get_file_as_string(path)
		assert_ne(src, "", "dock source should be readable: %s" % path)
		assert_true(src.contains("var _revealed"), "%s should declare a _revealed first-reveal latch" % path)
		assert_true(src.contains("visibility_changed.connect(_on_visibility_changed)"), "%s should connect visibility_changed to the lazy handler" % path)
		assert_true(src.contains("func _on_visibility_changed"), "%s should define _on_visibility_changed" % path)
		assert_true(src.contains("is_visible_in_tree() and not _revealed"), "%s must guard the scan on the first in-tree reveal" % path)
		assert_true(src.contains("_revealed = true"), "%s must latch _revealed = true so the scan runs only once" % path)


func test_quest_graph_subclass_stays_lazy_by_inheritance() -> void:
	# quest_graph extends the now-lazy dialogue_graph and inherits its first-reveal latch. It must NOT re-introduce an
	# eager _refresh_picker() in its own _init: that would scan at construction AND double-scan on reveal (select()
	# doesn't set _revealed). It should only set the Quest mode and let the inherited latch populate on reveal.
	var src := FileAccess.get_file_as_string("res://addons/cybersunday_tools/panel_graph/quest_graph.gd")
	assert_ne(src, "", "quest_graph.gd source should be readable")
	assert_false(src.contains("_refresh_picker()"), "quest_graph must NOT eager-scan — the inherited lazy latch populates on reveal")
	assert_true(src.contains("_mode.select(1)"), "quest_graph should still default to Quest mode (index 1)")
