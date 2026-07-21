class_name PlayerSpawn
extends Marker3D

## A named arrival point in a level. On level load, GameRoot teleports the Player to the PlayerSpawn whose
## `entry_id` matches the LevelDoor that sent them (or the first one, for the default entrance), and seeds it as
## the respawn point. Drop one per entrance; leave `entry_id` blank for the level's default arrival.

@export var entry_id: StringName = &""

func _ready() -> void:
	add_to_group(Groups.PLAYER_SPAWN)
	# The prefab carries an editor-only "EditorGizmo" arrow so the spawn is visible while authoring; drop it at
	# runtime. Null-safe so a bare PlayerSpawn.new() (no gizmo child, e.g. in tests) is unaffected.
	if not Engine.is_editor_hint():
		var gizmo := get_node_or_null(^"EditorGizmo")
		if gizmo != null:
			gizmo.queue_free()

## Move `player` to this spawn — position + yaw (matching the player's own respawn-yaw convention).
func place(player: Node3D) -> void:
	if player == null:
		return
	player.global_position = global_position
	player.rotation = Vector3(0.0, global_rotation.y, 0.0)
