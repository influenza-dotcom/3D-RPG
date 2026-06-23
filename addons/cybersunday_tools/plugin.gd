@tool
extends EditorPlugin

## CYBER SUNDAY in-editor dev-tools -- umbrella plugin. Registers ONE Node3D gizmo plugin, ONE bottom panel
## ("CYBER SUNDAY" -- a tabbed host for palette / items / level / tuning / factions / audit / graphs), TWO
## inspector plugins (LootTable / NpcData), and ONE toolbar control (play-from-spawn).
##
## WHY one bottom panel instead of several right-side docks: right-side docks contribute to the editor's MINIMUM
## height (and Godot restores their saved sizes on relaunch, overriding code), so on a short / HiDPI display the
## stacked docks forced the whole editor taller than the screen -- the bottom got clipped and the 3D viewport was
## squished. A single collapsible bottom panel sits OUT of the dock column and never forces the editor taller.
##
## Every add in _enter_tree is paired with a remove in _exit_tree, in REVERSE order, each guarded + freed +
## nulled. The editor reloads plugins on every script change and the user keeps the editor open all day, so an
## unpaired add strands one Control per reload (the #1 hot-reload bug for an editor plugin). Keep it symmetric.

const GizmoPlugin := preload("res://addons/cybersunday_tools/gizmos/cybersunday_gizmo_plugin.gd")
const CyberPanel := preload("res://addons/cybersunday_tools/cyber_panel.gd")
const LootInspector := preload("res://addons/cybersunday_tools/inspectors/loottable_inspector.gd")
const NpcInspector := preload("res://addons/cybersunday_tools/inspectors/npcdata_inspector.gd")
const PlayToolbar := preload("res://addons/cybersunday_tools/toolbar/play_from_spawn.gd")

var _gizmo: EditorNode3DGizmoPlugin = null
var _panel: Control = null
var _loot_insp: EditorInspectorPlugin = null
var _npc_insp: EditorInspectorPlugin = null
var _toolbar: Control = null


func _enter_tree() -> void:
	_gizmo = GizmoPlugin.new()
	add_node_3d_gizmo_plugin(_gizmo)

	# ALL the tool Controls live as tabs inside this one collapsible bottom panel (see header note).
	_panel = CyberPanel.new()
	add_control_to_bottom_panel(_panel, "CYBER SUNDAY")

	_loot_insp = LootInspector.new()
	add_inspector_plugin(_loot_insp)
	_npc_insp = NpcInspector.new()
	add_inspector_plugin(_npc_insp)

	_toolbar = PlayToolbar.new()
	add_control_to_container(EditorPlugin.CONTAINER_TOOLBAR, _toolbar)


func _exit_tree() -> void:
	# Reverse order; each block pairs exactly one _enter_tree add. Toolbar removal is the TWO-arg
	# remove_control_from_container; bottom-panel removal is the single-arg remove_control_from_bottom_panel.
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

	if _panel != null:
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()
		_panel = null

	if _gizmo != null:
		remove_node_3d_gizmo_plugin(_gizmo)
		_gizmo = null
