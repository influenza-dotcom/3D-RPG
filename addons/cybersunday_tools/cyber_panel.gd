@tool
extends TabContainer

## Single host for every CYBER SUNDAY tool Control, each an inner tab (Palette / Items / Level / Tuning / Factions
## / Audit / Graphs). plugin.gd adds THIS as ONE collapsible bottom panel instead of several right-side docks --
## right-side docks contribute to the editor's MINIMUM height (and Godot restores their saved sizes on relaunch),
## which on a short/HiDPI display forces the whole editor taller than the screen and squishes the 3D viewport. A
## bottom panel is collapsible and out of the dock column, so it never forces the editor taller. Each child Control
## sets its own `name`, which TabContainer uses as the tab title.

const PaletteDock := preload("res://addons/cybersunday_tools/dock_palette/palette_dock.gd")
const ItemPlacerDock := preload("res://addons/cybersunday_tools/placer/item_placer_dock.gd")
const LevelDock := preload("res://addons/cybersunday_tools/dock_level/level_dock.gd")
const TuningBrowser := preload("res://addons/cybersunday_tools/dock_tuning/tuning_browser.gd")
const FactionDock := preload("res://addons/cybersunday_tools/dock_faction/faction_matrix.gd")
const AuditPanel := preload("res://addons/cybersunday_tools/panel_audit/audit_panel.gd")
const GraphsPanel := preload("res://addons/cybersunday_tools/panel_graph/dialogue_graph.gd")


func _init() -> void:
	name = "CYBER SUNDAY"
	add_child(PaletteDock.new())
	add_child(ItemPlacerDock.new())
	add_child(LevelDock.new())
	add_child(TuningBrowser.new())
	add_child(FactionDock.new())
	add_child(AuditPanel.new())
	add_child(GraphsPanel.new())
