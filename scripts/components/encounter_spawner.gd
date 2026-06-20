@tool
class_name EncounterSpawner
extends Node3D

## Drop into a level to spawn enemies on cue — wire a TriggerVolume (action = "trigger_spawn", target = this) or
## call trigger_spawn() from anything. Each SpawnDefinition instances `count` NPCs scattered within its
## spawn_radius of this node, stamping the archetype / faction / weapon overrides and (optionally) aggroing them
## onto the player. The foundation of authored encounters — no more hand-placing every enemy alive from frame 1.

signal spawned(npc: Node)
## Every NPC this spawner produced is now dead or despawned — wire an exit Door's unlock to it for a
## "clear the room to proceed" gate. Only fires after at least one spawn existed (never on an empty spawner).
signal cleared
## The live-spawn count changed (after each spawn and each death) — drive a "3 enemies left" HUD counter.
signal alive_count_changed(count: int)

@export var spawn_definitions: Array[SpawnDefinition] = []

var _alive: Array[Node] = []  ## spawns still alive — each leaves on its died OR tree_exited (whichever first)

## Spawn EVERY definition (the common case — one trigger fires this once).
func trigger_spawn() -> void:
	for i in spawn_definitions.size():
		trigger_spawn_wave(i)

## Spawn just one definition by index (a WaveManager steps these one at a time).
func trigger_spawn_wave(index: int) -> void:
	if index < 0 or index >= spawn_definitions.size():
		return
	var def := spawn_definitions[index]
	if def == null or def.npc_scene == null or get_parent() == null:
		return
	for i in def.count:
		_spawn_one(def)
		if def.spawn_delay > 0.0 and i < def.count - 1 and is_inside_tree():
			await get_tree().create_timer(def.spawn_delay).timeout

## Instance one NPC from `def`, apply its overrides (BEFORE add_child so the NPC's _ready stamps them), place it
## within the scatter radius, and aggro it onto the player when asked.
func _spawn_one(def: SpawnDefinition) -> void:
	var npc: Node = def.npc_scene.instantiate()
	if def.profile != null:
		npc.set(&"profile", def.profile)
	if def.faction_override != null:
		npc.set(&"faction_id", "")  # clear the id dropdown so our faction override wins in _resolve_faction
		npc.set(&"faction", def.faction_override)
	if def.weapon_override != null:
		npc.set(&"weapon_data", def.weapon_override)
	get_parent().add_child(npc)  # into the level, as a sibling of the spawner
	if npc is Node3D:
		(npc as Node3D).global_position = global_position + _random_offset(def.spawn_radius)
	if def.auto_aggro and npc.has_method(&"provoke"):
		npc.provoke(_player())
	spawned.emit(npc)
	_track_spawn(npc)

## Track a freshly-spawned NPC for the cleared / alive_count_changed signals: it leaves _alive the moment it
## dies OR is freed (whichever fires first), so an encounter still counts as cleared if a body is despawned
## rather than killed. Split out so a test can drive it with a stub node (no real NPC _ready).
func _track_spawn(npc: Node) -> void:
	if npc == null or _alive.has(npc):
		return
	_alive.append(npc)
	if npc.has_signal(&"died"):
		npc.died.connect(_on_spawn_gone.bind(npc))
	npc.tree_exited.connect(_on_spawn_gone.bind(npc))
	alive_count_changed.emit(_alive.size())

## A tracked spawn died or left the tree — drop it once (died + tree_exited can both fire for the same NPC)
## and announce the new count; when the last one goes, the encounter is cleared.
func _on_spawn_gone(npc: Node) -> void:
	if not _alive.has(npc):
		return
	_alive.erase(npc)
	alive_count_changed.emit(_alive.size())
	if _alive.is_empty():
		cleared.emit()

## How many tracked spawns are still alive (0 once the encounter is cleared).
func alive_count() -> int:
	return _alive.size()

## A random horizontal offset within `radius` (uniform over the disc) to scatter the spawns. Pure.
func _random_offset(radius: float) -> Vector3:
	var ang := randf() * TAU
	var dist := sqrt(randf()) * maxf(0.0, radius)
	return Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)

func _player() -> Node:
	return get_tree().get_first_node_in_group(&"player") if is_inside_tree() else null

func _get_configuration_warnings() -> PackedStringArray:
	if spawn_definitions.is_empty():
		return PackedStringArray(["EncounterSpawner has no spawn_definitions — it will spawn nothing."])
	return PackedStringArray()
