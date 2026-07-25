@tool
class_name SpawnOnDestroy
extends Node

## Drop-in: spawn object(s) when the host is destroyed. Give it to a CanDestroy (shoot-to-break) or a
## Throwable (a crate) and when the host breaks it spawns `spawn_scene` (e.g. a CanPickUp loot item) at the
## host's position — into the LEVEL, so the drops outlive the host. Pair with CanDestroy on a crate to make
## "shoot the crate for loot".
##
## SETUP: drop this under a CanDestroy / Throwable and set `spawn_scene` (plus optional count / scatter).

## Scene spawned into the level when the host breaks (e.g. a CanPickUp loot item). With a loot_table set the rolled
## item is stamped onto each copy — leave this EMPTY and the shipped CanPickUp prefab is used automatically, so just
## assigning a loot_table works. For a FIXED (non-table) drop, set this to the pickup you want.
@export var spawn_scene: PackedScene:
	set(value):
		spawn_scene = value
		update_configuration_warnings()
## How many copies of spawn_scene to drop on destroy. Ignored when loot_table is set (the roll decides count).
@export var count: int = 1
## Random horizontal offset (m) applied per spawn so multiple drops don't stack on the exact same point.
@export var scatter: float = 0.3
## OPTIONAL drop table: when set, roll it on destroy and spawn ONE pickup per rolled item, stamping the item+count
## onto each. spawn_scene defaults to the shipped CanPickUp when left empty. Null = spawn `count` of spawn_scene.
@export var loot_table: LootTable = null:
	set(value):
		loot_table = value
		update_configuration_warnings()
## Optional one-shot played after each spawned object enters the tree. If the spawned object exposes
## sound_pitch_mult, the sound inherits it, which lets a dog crate bark at the revealed dog's rolled size.
@export var spawn_sound: AudioStream
@export var spawn_sound_volume_db: float = 0.0
@export var pitch_spawn_sound_from_spawned: bool = true

## Default pickup used for the loot-table path when spawn_scene is left empty (the rolled item is stamped onto a copy).
const DEFAULT_PICKUP: PackedScene = preload("res://scenes/components/can_pick_up.tscn")

## One process-wide RNG for every loot roll, seeded ONCE (lazily, in roll order) rather than allocating a
## fresh RandomNumberGenerator + randomize() per destroy — that churned an object and re-seeded from the OS
## on every break. Shared across all SpawnOnDestroy instances (static), so its sequence advances naturally.
static var _loot_rng: RandomNumberGenerator = null

static func _shared_rng() -> RandomNumberGenerator:
	if _loot_rng == null:
		_loot_rng = RandomNumberGenerator.new()
		_loot_rng.randomize()
	return _loot_rng

func _ready() -> void:
	if Engine.is_editor_hint():
		return  # @tool: only _get_configuration_warnings runs in the editor; the signal hookup is runtime-only
	var host := get_parent()
	if host == null:
		return
	# Connect to the host's destruction signal — CanDestroy and Throwable both emit `destroyed`.
	if host.has_signal(&"destroyed") and not host.is_connected(&"destroyed", _on_destroyed):
		host.connect(&"destroyed", _on_destroyed)

## Host was destroyed: spawn the drops into the level (NOT under the host — it's about to free itself). With
## a loot_table, roll it and spawn one pickup per rolled item; otherwise spawn `count` fixed copies.
func _on_destroyed() -> void:
	# A loot_table needs a pickup to stamp each rolled item onto; default to the shipped CanPickUp so just setting a
	# loot_table works. A fixed (non-table) drop still needs its own spawn_scene.
	var scene: PackedScene = spawn_scene
	if scene == null and loot_table != null:
		scene = DEFAULT_PICKUP
	if scene == null or not scene.can_instantiate():
		return
	var host := get_parent() as Node3D
	var origin: Vector3 = host.global_position if is_instance_valid(host) else Vector3.ZERO
	var into: Node = get_tree().current_scene if get_tree() != null else null
	if into == null:
		return
	if loot_table != null:
		_spawn_rolled_loot(origin, into, scene)
		return
	for _i in maxi(1, count):
		var obj := scene.instantiate()
		into.add_child(obj)
		if obj is Node3D:
			(obj as Node3D).global_position = _scatter_pos(origin)
		_play_spawn_sound(obj, origin)

## Roll the loot table and spawn one pickup per rolled item, stamping the item+count onto each spawned
## CanPickUp so the same prefab carries whatever the table rolled.
func _spawn_rolled_loot(origin: Vector3, into: Node, scene: PackedScene) -> void:
	for d in loot_table.roll(_shared_rng()):
		var obj := scene.instantiate()
		var pickup := _as_pickup(obj)  # stamp BEFORE add_child, so the pickup's _ready sees its item
		if pickup != null:
			pickup.item = d["item"]
			# Difficulty loot scaling: raw roll() counts must get the same loot_mult every grant() path applies
			# (LootTable.grant does this internally) — without it, destroyed-prop drops ignored difficulty.
			pickup.amount = maxi(1, roundi(d["count"] * GameSettings.difficulty.loot_mult))
			pickup.build_model_from_item = true  # show the rolled item's own world_model (no-op if it has none)
		into.add_child(obj)
		if obj is Node3D:
			(obj as Node3D).global_position = _scatter_pos(origin)
		_play_spawn_sound(obj, origin)

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

func _play_spawn_sound(spawned: Node, origin: Vector3) -> void:
	if spawn_sound == null or not is_inside_tree():
		return
	var pos := origin
	if spawned is Node3D:
		pos = (spawned as Node3D).global_position
	AudioManager.play_sfx(pos, spawn_sound, spawn_sound_volume_db, spawn_sound_pitch(spawned, 1.0, pitch_spawn_sound_from_spawned))

static func spawn_sound_pitch(spawned: Node, base_pitch: float = 1.0, use_spawned_pitch: bool = true) -> float:
	var pitch := maxf(base_pitch, 0.01)
	if not use_spawned_pitch or spawned == null:
		return pitch
	var spawned_pitch: Variant = spawned.get(&"sound_pitch_mult")
	if typeof(spawned_pitch) == TYPE_FLOAT or typeof(spawned_pitch) == TYPE_INT:
		pitch *= maxf(float(spawned_pitch), 0.01)
	return pitch

## Editor warning: a SpawnOnDestroy with no spawn_scene is inert, and one under a host that can't be destroyed
## never fires. Re-evaluated when spawn_scene changes (setter) or the node is re-parented.
func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	if spawn_scene == null and loot_table == null:
		w.append("Nothing to drop — assign a `loot_table` (it spawns the shipped CanPickUp by default) or a `spawn_scene`.")
	var host := get_parent()
	if host != null and not host.has_signal(&"destroyed"):
		w.append("The parent exposes no `destroyed` signal — put this under a CanDestroy or Throwable, or it can never fire.")
	return w
