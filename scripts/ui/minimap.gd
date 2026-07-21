class_name Minimap
extends Control

## A HUD minimap: draws the level's MapData texture with the player (and flagged NPCs) as markers, projected via
## MapData.world_to_uv. Add it to the HUD and assign `map_data`. It reads the player from the &"Player" group
## (Groups.PLAYER) and markers from the &"minimap" group (WorldMarkers / an NPC with show_on_minimap), each drawn
## in its own `color` when it sets one (else the NPC red). Rendering is playtest-tuned; the projection it relies
## on (MapData.world_to_uv) is unit-tested.

@export var map_data: MapData
@export var marker_radius: float = 4.0

func _process(_delta: float) -> void:
	if map_data != null and is_visible_in_tree():
		queue_redraw()

func _draw() -> void:
	if map_data == null or map_data.map_texture == null:
		return
	draw_texture_rect(map_data.map_texture, Rect2(Vector2.ZERO, size), false)
	if not is_inside_tree():
		return
	var player := get_tree().get_first_node_in_group(Groups.PLAYER)
	if player is Node3D:
		_draw_marker((player as Node3D).global_position, map_data.player_marker, Color(0.4, 0.8, 1.0))
	for n in get_tree().get_nodes_in_group(Groups.MINIMAP):
		if n is Node3D:
			# Honour a marker's own color (quest / vendor / exit beacons set it) — type-guarded like compass.gd; a
			# marker that carries none falls back to the NPC red.
			var raw_col: Variant = n.get(&"color")
			var col: Color = raw_col if raw_col is Color else Color(1.0, 0.4, 0.4)
			_draw_marker((n as Node3D).global_position, map_data.npc_marker, col)

func _draw_marker(world_pos: Vector3, tex: Texture2D, fallback: Color) -> void:
	var uv := MapData.world_to_uv(world_pos, map_data.world_bounds)
	var p := Vector2(uv.x * size.x, uv.y * size.y)
	if tex != null:
		draw_texture(tex, p - tex.get_size() * 0.5)
	else:
		draw_circle(p, marker_radius, fallback)
