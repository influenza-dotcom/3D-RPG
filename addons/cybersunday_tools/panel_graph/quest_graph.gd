@tool
extends "res://addons/cybersunday_tools/panel_graph/dialogue_graph.gd"

## Quest-first variant of the combined "Graphs" panel. The chosen design is ONE bottom panel (dialogue_graph.gd)
## with a Dialogue/Quest mode picker that reuses graph_data.gd for both modes -- so this file exists mainly to
## satisfy the two-file layout and to offer a standalone Quest-only entry point. It simply boots the shared panel
## pre-set to Quest mode. plugin.gd registers the combined panel (dialogue_graph.gd), NOT this subclass.
##
## Kept tiny + constructible (.new()) so the GUT compile test still covers it. No new logic lives here -- all the
## building is in graph_data.gd and all the rendering in the parent.

func _init() -> void:
	super()
	# Default this entry point to Quest mode (index 1) and repopulate from the quest folder.
	if _mode != null:
		_mode.select(1)
		_refresh_picker()
