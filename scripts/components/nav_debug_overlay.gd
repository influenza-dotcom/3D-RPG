@tool
class_name NavDebugOverlay
extends Node

## Drop this Node into a level (or bind `toggle_action`) to VISUALIZE navigation while you play: it turns on Godot's
## built-in navmesh debug draw (the green walkable polygons) and every NPC's current path line, so you can SEE
## whether a stuck NPC is off the mesh, stranded on a stray roof poly, or just grinding against geometry.
## Debug-build only (editor Play / a debug export) and INERT by default — a safe no-op in a release build. Pairs
## with the File -> Run navmesh audit (scripts/tools/audit_navmesh.gd): the audit tells you WHICH polys are bad, this
## shows you the NPCs hitting them at runtime.

@export var enabled: bool = false: set = set_enabled  ## start state; flip in the inspector or call toggle()
@export var toggle_action: StringName = &""           ## optional Input action to toggle live; blank = none
@export var agent_paths: bool = true                  ## also draw every NavigationAgent3D's path line

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	set_process_input(toggle_action != &"")
	if enabled:
		_apply(true)

func set_enabled(v: bool) -> void:
	enabled = v
	if is_inside_tree() and not Engine.is_editor_hint():
		_apply(v)

func toggle() -> void:
	set_enabled(not enabled)

func _input(event: InputEvent) -> void:
	if toggle_action != &"" and event.is_action_pressed(toggle_action):
		toggle()

func _apply(on: bool) -> void:
	# Each call is guarded so it can never crash if a debug-only API is absent in this build.
	if NavigationServer3D.has_method("set_debug_enabled"):
		NavigationServer3D.set_debug_enabled(on)
	var tree := get_tree()
	if tree == null:
		return
	if "debug_navigation_hint" in tree:
		tree.debug_navigation_hint = on
	if agent_paths:
		var agents: Array[NavigationAgent3D] = []
		_collect_agents(tree.root, agents)
		for agent in agents:
			agent.debug_enabled = on

func _collect_agents(node: Node, out: Array[NavigationAgent3D]) -> void:
	if node is NavigationAgent3D:
		out.append(node)
	for c in node.get_children():
		_collect_agents(c, out)
