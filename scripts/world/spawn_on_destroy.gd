class_name SpawnOnDestroy
extends Node

## Drop-in: spawn object(s) when the host is destroyed. Give it to a CanDestroy (shoot-to-break) or a
## Throwable (a crate) and when the host breaks it spawns `spawn_scene` (e.g. a CanPickUp loot item) at the
## host's position — into the LEVEL, so the drops outlive the host. Pair with CanDestroy on a crate to make
## "shoot the crate for loot".
##
## SETUP: drop this under a CanDestroy / Throwable and set `spawn_scene` (plus optional count / scatter).

@export var spawn_scene: PackedScene
@export var count: int = 1
## Random horizontal offset (m) applied per spawn so multiple drops don't stack on the exact same point.
@export var scatter: float = 0.3

func _ready() -> void:
	var host := get_parent()
	if host == null:
		return
	# Connect to whichever destroy signal the host exposes: CanDestroy.destroyed or Throwable.destroy.
	if host.has_signal(&"destroyed") and not host.is_connected(&"destroyed", _on_destroyed):
		host.connect(&"destroyed", _on_destroyed)
	elif host.has_signal(&"destroy") and not host.is_connected(&"destroy", _on_destroyed):
		host.connect(&"destroy", _on_destroyed)

## Host was destroyed: spawn the drops into the level (NOT under the host — it's about to free itself).
func _on_destroyed() -> void:
	if spawn_scene == null or not spawn_scene.can_instantiate():
		return
	var host := get_parent() as Node3D
	var origin: Vector3 = host.global_position if is_instance_valid(host) else Vector3.ZERO
	var into: Node = get_tree().current_scene if get_tree() != null else null
	if into == null:
		return
	for _i in maxi(1, count):
		var obj := spawn_scene.instantiate()
		into.add_child(obj)
		if obj is Node3D:
			(obj as Node3D).global_position = origin + Vector3(randf_range(-scatter, scatter), 0.0, randf_range(-scatter, scatter))
