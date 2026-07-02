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
	# Default this entry point to Quest mode (index 1). The inherited first-reveal latch
	# (dialogue_graph._on_visibility_changed) populates the picker from the quest folder on reveal — do NOT eager-scan
	# here: that would defeat the lazy latch and, since OptionButton.select() doesn't emit item_selected, it would also
	# double-scan on the first reveal.
	if _mode != null:
		_mode.select(1)
