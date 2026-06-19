@tool
class_name MapData
extends Resource

## An authored map for a level: a top-down TEXTURE plus the WORLD RECT it covers, so a Minimap / MapScreen can
## project any world position onto the image. Drop a top-down render of the level into map_texture and set
## world_bounds to the X/Z area (in world units) it spans.

@export var map_texture: Texture2D
## The world area the texture covers — Rect x/width = world X, Rect y/height = world Z (units). Drives the projection.
@export var world_bounds: Rect2 = Rect2(-50, -50, 100, 100)
@export var player_marker: Texture2D
@export var npc_marker: Texture2D

## Project a WORLD position onto the map's [0,1] UV (X -> u, Z -> v). Pure. Returns the centre on degenerate
## bounds (no divide-by-zero). Clamp/scale to the map rect at the draw site.
static func world_to_uv(world_pos: Vector3, bounds: Rect2) -> Vector2:
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return Vector2(0.5, 0.5)
	return Vector2(
		(world_pos.x - bounds.position.x) / bounds.size.x,
		(world_pos.z - bounds.position.y) / bounds.size.y,
	)
