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
## OPTIONAL drop table: when set, roll it on destroy and spawn ONE spawn_scene per rolled item, stamping the
## item+count onto each (spawn_scene must be a CanPickUp). Null = spawn `count` copies of spawn_scene as-is.
@export var loot_table: LootTable = null

func _ready() -> void:
	var host := get_parent()
	if host == null:
		return
	# Connect to whichever destroy signal the host exposes: CanDestroy.destroyed or Throwable.destroy.
	if host.has_signal(&"destroyed") and not host.is_connected(&"destroyed", _on_destroyed):
		host.connect(&"destroyed", _on_destroyed)
	elif host.has_signal(&"destroy") and not host.is_connected(&"destroy", _on_destroyed):
		host.connect(&"destroy", _on_destroyed)

## Host was destroyed: spawn the drops into the level (NOT under the host — it's about to free itself). With
## a loot_table, roll it and spawn one pickup per rolled item; otherwise spawn `count` fixed copies.
func _on_destroyed() -> void:
	if spawn_scene == null or not spawn_scene.can_instantiate():
		return
	var host := get_parent() as Node3D
	var origin: Vector3 = host.global_position if is_instance_valid(host) else Vector3.ZERO
	var into: Node = get_tree().current_scene if get_tree() != null else null
	if into == null:
		return
	if loot_table != null:
		_spawn_rolled_loot(origin, into)
		return
	for _i in maxi(1, count):
		var obj := spawn_scene.instantiate()
		into.add_child(obj)
		if obj is Node3D:
			(obj as Node3D).global_position = _scatter_pos(origin)

## Roll the loot table and spawn one pickup per rolled item, stamping the item+count onto each spawned
## CanPickUp so the same prefab carries whatever the table rolled.
func _spawn_rolled_loot(origin: Vector3, into: Node) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for d in loot_table.roll(rng):
		var obj := spawn_scene.instantiate()
		var pickup := _as_pickup(obj)  # stamp BEFORE add_child, so the pickup's _ready sees its item
		if pickup != null:
			pickup.item = d["item"]
			pickup.amount = d["count"]
			pickup.build_model_from_item = true  # show the rolled item's own world_model (no-op if it has none)
		into.add_child(obj)
		if obj is Node3D:
			(obj as Node3D).global_position = _scatter_pos(origin)

## Find the CanPickUp in a spawned drop — the root itself or a descendant component — so the rolled item can
## be stamped onto it regardless of how the pickup prefab is structured.
func _as_pickup(node: Node) -> CanPickUp:
	if node is CanPickUp:
		return node as CanPickUp
	for c in node.get_children():
		var found := _as_pickup(c)
		if found != null:
			return found
	return null

## A scattered world position near `origin` (so multiple drops don't stack on the exact same point).
func _scatter_pos(origin: Vector3) -> Vector3:
	return origin + Vector3(randf_range(-scatter, scatter), 0.0, randf_range(-scatter, scatter))
