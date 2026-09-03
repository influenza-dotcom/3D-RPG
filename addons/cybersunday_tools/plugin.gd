@tool
extends EditorPlugin

## CYBER SUNDAY in-editor dev-tools -- umbrella plugin. Registers ONE Node3D gizmo plugin, ONE bottom panel
## ("CYBER SUNDAY" -- cyber_panel.gd, FIVE job groups of tools: Build / Create / Tune / Check / Advanced, 24 tools
## in all), FIVE inspector plugins (LootTable / NpcData / WeaponData / GoapProfile / Perk), and ONE toolbar control
## (play-from-spawn).
##
## The panel is also the tabs' HANDOFF HOST (open_in_editor / show_tab -- see cyber_panel.gd + core/host.gd); this
## plugin gives it the two things only an EditorPlugin has: `make_bottom_panel_item_visible` (so a handoff can expand
## a collapsed panel) and the `scene_changed` signal (so placement tabs can grey their buttons before a click).
##
## The AI Bridge tool (Advanced group) is the odd one out: it hosts an OPT-IN localhost command server (127.0.0.1
## only, token-gated, OFF until the user presses Start) that lets an external AI client read editor state, refresh
## the FileSystem cache after an external write, and reveal a resource. It is registered like any other tab -- the
## plugin owns no socket itself, so disabling the plugin closes the port with everything else.
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
const WeaponInspector := preload("res://addons/cybersunday_tools/inspectors/weapondata_inspector.gd")
const GoapInspector := preload("res://addons/cybersunday_tools/inspectors/goapprofile_inspector.gd")
const PerkInspector := preload("res://addons/cybersunday_tools/inspectors/perk_inspector.gd")
const PlayToolbar := preload("res://addons/cybersunday_tools/toolbar/play_from_spawn.gd")

var _gizmo: EditorNode3DGizmoPlugin = null
var _panel: Control = null
var _loot_insp: EditorInspectorPlugin = null
var _npc_insp: EditorInspectorPlugin = null
var _weapon_insp: EditorInspectorPlugin = null
var _goap_insp: EditorInspectorPlugin = null
var _perk_insp: EditorInspectorPlugin = null
var _toolbar: Control = null


func _enter_tree() -> void:
	_gizmo = GizmoPlugin.new()
	add_node_3d_gizmo_plugin(_gizmo)

	# ALL the tool Controls live as tabs inside this one collapsible bottom panel (see header note).
	_panel = CyberPanel.new()
	add_control_to_bottom_panel(_panel, "CYBER SUNDAY")
	# Handoff host wiring (see header): let show_tab expand the panel, and feed scene changes to the tabs -- once now
	# (the plugin may be enabled with a scene already open) and on every switch after.
	_panel.reveal_panel = make_bottom_panel_item_visible.bind(_panel)
	scene_changed.connect(_panel.on_scene_changed)
	_panel.on_scene_changed(EditorInterface.get_edited_scene_root())

	_loot_insp = LootInspector.new()
	add_inspector_plugin(_loot_insp)
	_npc_insp = NpcInspector.new()
	add_inspector_plugin(_npc_insp)
	_weapon_insp = WeaponInspector.new()
	add_inspector_plugin(_weapon_insp)
	_goap_insp = GoapInspector.new()
	add_inspector_plugin(_goap_insp)
	_perk_insp = PerkInspector.new()
	add_inspector_plugin(_perk_insp)

	_toolbar = PlayToolbar.new()
	add_control_to_container(EditorPlugin.CONTAINER_TOOLBAR, _toolbar)


func _exit_tree() -> void:
	# Reverse order; each block pairs exactly one _enter_tree add. Toolbar removal is the TWO-arg
	# remove_control_from_container; bottom-panel removal is the single-arg remove_control_from_bottom_panel.
	if _toolbar != null:
		remove_control_from_container(EditorPlugin.CONTAINER_TOOLBAR, _toolbar)
		_toolbar.queue_free()
		_toolbar = null

	if _perk_insp != null:
		remove_inspector_plugin(_perk_insp)
		_perk_insp = null
	if _goap_insp != null:
		remove_inspector_plugin(_goap_insp)
		_goap_insp = null
	if _weapon_insp != null:
		remove_inspector_plugin(_weapon_insp)
		_weapon_insp = null
	if _npc_insp != null:
		remove_inspector_plugin(_npc_insp)
		_npc_insp = null
	if _loot_insp != null:
		remove_inspector_plugin(_loot_insp)
		_loot_insp = null

	if _panel != null:
		if scene_changed.is_connected(_panel.on_scene_changed):
			scene_changed.disconnect(_panel.on_scene_changed)
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()
		_panel = null

	if _gizmo != null:
		remove_node_3d_gizmo_plugin(_gizmo)
		_gizmo = null
