@tool
extends EditorPlugin

## CYBER SUNDAY in-editor dev-tools -- umbrella plugin. Registers ONE Node3D gizmo plugin, THREE control
## docks (palette / item-placer / level-tools), ONE bottom panel (audit), TWO inspector plugins
## (LootTable / NpcData), and ONE toolbar control (play-from-spawn).
##
## Every add in _enter_tree is paired with a remove in _exit_tree, in REVERSE order, each guarded + freed +
## nulled. The editor reloads plugins on every script change and the user keeps the editor open all day, so an
## unpaired add strands one Control per reload (the #1 hot-reload bug for an editor plugin). Keep it symmetric.
##
## Sub-tools are pure-script Controls instantiated with .new() (house pref: code over a .tscn), so this file
## preloads the SCRIPTS, not packed scenes. They ship as stubs first; each is fleshed out in its own build step.

const GizmoPlugin := preload("res://addons/cybersunday_tools/gizmos/cybersunday_gizmo_plugin.gd")
const PaletteDock := preload("res://addons/cybersunday_tools/dock_palette/palette_dock.gd")
const LevelDock := preload("res://addons/cybersunday_tools/dock_level/level_dock.gd")
const AuditPanel := preload("res://addons/cybersunday_tools/panel_audit/audit_panel.gd")
const ItemPlacerDock := preload("res://addons/cybersunday_tools/placer/item_placer_dock.gd")
const LootInspector := preload("res://addons/cybersunday_tools/inspectors/loottable_inspector.gd")
const NpcInspector := preload("res://addons/cybersunday_tools/inspectors/npcdata_inspector.gd")
const PlayToolbar := preload("res://addons/cybersunday_tools/toolbar/play_from_spawn.gd")
const TuningBrowser := preload("res://addons/cybersunday_tools/dock_tuning/tuning_browser.gd")
const FactionDock := preload("res://addons/cybersunday_tools/dock_faction/faction_matrix.gd")
const GraphsPanel := preload("res://addons/cybersunday_tools/panel_graph/dialogue_graph.gd")

var _gizmo: EditorNode3DGizmoPlugin = null
var _palette: Control = null
var _level: Control = null
var _audit: Control = null
var _placer: Control = null
var _loot_insp: EditorInspectorPlugin = null
var _npc_insp: EditorInspectorPlugin = null
var _toolbar: Control = null
var _tuning: Control = null
var _factions: Control = null
var _graphs: Control = null


func _enter_tree() -> void:
	_gizmo = GizmoPlugin.new()
	add_node_3d_gizmo_plugin(_gizmo)

	_palette = PaletteDock.new()
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, _palette)

	_placer = ItemPlacerDock.new()
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_BL, _placer)

	_level = LevelDock.new()
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_BL, _level)

	_tuning = TuningBrowser.new()
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_BL, _tuning)

	_factions = FactionDock.new()
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_BL, _factions)

	_audit = AuditPanel.new()
	add_control_to_bottom_panel(_audit, "Audit")

	_graphs = GraphsPanel.new()
	add_control_to_bottom_panel(_graphs, "Graphs")

	_loot_insp = LootInspector.new()
	add_inspector_plugin(_loot_insp)
	_npc_insp = NpcInspector.new()
	add_inspector_plugin(_npc_insp)

	_toolbar = PlayToolbar.new()
	add_control_to_container(EditorPlugin.CONTAINER_TOOLBAR, _toolbar)


func _exit_tree() -> void:
	# Reverse order; each block pairs exactly one _enter_tree add. Toolbar removal is the TWO-arg
	# remove_control_from_container; dock removal is the single-arg remove_control_from_docks (asymmetric).
	if _toolbar != null:
		remove_control_from_container(EditorPlugin.CONTAINER_TOOLBAR, _toolbar)
		_toolbar.queue_free()
		_toolbar = null

	if _npc_insp != null:
		remove_inspector_plugin(_npc_insp)
		_npc_insp = null
	if _loot_insp != null:
		remove_inspector_plugin(_loot_insp)
		_loot_insp = null

	if _graphs != null:
		remove_control_from_bottom_panel(_graphs)
		_graphs.queue_free()
		_graphs = null

	if _audit != null:
		remove_control_from_bottom_panel(_audit)
		_audit.queue_free()
		_audit = null

	if _factions != null:
		remove_control_from_docks(_factions)
		_factions.queue_free()
		_factions = null
	if _tuning != null:
		remove_control_from_docks(_tuning)
		_tuning.queue_free()
		_tuning = null

	if _level != null:
		remove_control_from_docks(_level)
		_level.queue_free()
		_level = null
	if _placer != null:
		remove_control_from_docks(_placer)
		_placer.queue_free()
		_placer = null
	if _palette != null:
		remove_control_from_docks(_palette)
		_palette.queue_free()
		_palette = null

	if _gizmo != null:
		remove_node_3d_gizmo_plugin(_gizmo)
		_gizmo = null
