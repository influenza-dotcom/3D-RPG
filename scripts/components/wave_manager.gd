@tool
class_name WaveManager
extends Node

## Sequences an EncounterSpawner's definitions as timed WAVES: fire wave 0, wait wave_interval, fire wave 1, …,
## then emit all_waves_done. Point spawner_path at an EncounterSpawner and start() it (e.g. a TriggerVolume with
## action = "start", target = this). For "clear the room over several waves" encounters.

signal wave_started(index: int)
signal all_waves_done

@export var spawner_path: NodePath
@export var wave_interval: float = 5.0  ## seconds between waves
@export var auto_start: bool = false    ## begin on _ready (else a trigger / cutscene calls start())

var _running: bool = false

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if auto_start:
		start()

## Run the waves once (no-op if already running or there's no spawner). Each wave is one EncounterSpawner definition.
func start() -> void:
	if _running:
		return
	var spawner := _spawner()
	if spawner == null:
		return
	_running = true
	var i := 0
	while i < spawner.spawn_definitions.size():
		wave_started.emit(i)
		spawner.trigger_spawn_wave(i)
		i += 1
		if i < spawner.spawn_definitions.size() and is_inside_tree():
			await get_tree().create_timer(maxf(0.0, wave_interval)).timeout
	_running = false
	all_waves_done.emit()

func is_running() -> bool:
	return _running

## Await until every NPC the spawner has produced across all waves is dead (the spawner's `cleared`). Resolves
## immediately if nothing is alive and no run is in progress. A clear during an inter-wave lull doesn't end it —
## the loop keeps waiting while _running. Best awaited after / alongside start(): e.g. a quest step or an exit
## Door that unlocks once the arena is clear. No-op (returns) if there's no spawner.
func wait_for_clear() -> void:
	var spawner := _spawner()
	if spawner == null:
		return
	# Await `cleared` only while NPCs are actually alive (it fires once when the last one dies). Between waves
	# (running, none spawned yet) poll briefly instead — re-awaiting an already-fired `cleared` would hang.
	while _running or spawner.alive_count() > 0:
		if spawner.alive_count() > 0:
			await spawner.cleared
		elif is_inside_tree():
			await get_tree().create_timer(0.1).timeout
		else:
			return

func _spawner() -> EncounterSpawner:
	if spawner_path.is_empty():
		return null
	return get_node_or_null(spawner_path) as EncounterSpawner

func _get_configuration_warnings() -> PackedStringArray:
	if spawner_path.is_empty():
		return PackedStringArray(["WaveManager has no spawner_path — assign an EncounterSpawner to sequence."])
	return PackedStringArray()
