class_name SoakHarness
extends Node

## Headless multi-NPC SOAK harness — the dynamic QA tool unit tests structurally can't be: it boots a real level,
## spawns a wave of REAL wandering NPCs (their full _ready runs, unlike a unit test), ticks the game loop for
## seconds of game-time, and watches for the bug classes that only appear over time with many agents:
##   * STRANDED NPCs — an NPC that keeps giving up in one spot (NPC._stranded_cycles >= 3) is wedged on a bad-bake
##     navmesh island (a prop/car roof the bake made walkable). This is THE recurring nav-grind pain, caught
##     automatically instead of by a human noticing pacing in a playtest.
##   * NODE / ORPHAN LEAKS — spawning then freeing waves of NPCs must return the node count to baseline; an upward
##     trend means a spawn path leaked (a failed .free(), a signal keeping a dead NPC alive).
## It needs NO player and NO combat: idle NPCs with `wanders = true` roam the navmesh on their own, which is exactly
## what surfaces traversal faults. Drop it under a booted level and `await run_soak()`; it returns a SoakReport.
##
## Designer use: add this Node under a level scene, point npc_scene/level at what you want to audit, and run it
## (the tests_soak/ GUT suite drives it headless; an EditorScript could too). DELIBERATELY runs NPC._ready, which
## CLAUDE.md forbids in UNIT tests — that rule keeps the fast suite pure; this is the opt-in heavy harness where
## running the real brain IS the point. Keep it out of res://tests so it never joins the default run.

## Referenced via preload (not the global SoakReport class_name) so a not-yet-rescanned editor cache can't cascade
## into "Could not find type SoakReport" when this loads headless. See [[new-classname-not-registered-cascade]].
const SoakReportScript := preload("res://scripts/tools/soak_report.gd")

@export var npc_scene: PackedScene = preload("res://scenes/enemies/NPC.tscn")
## Spawned NPCs get a real faction (mirrors authored enemies; default raiders). Wandering doesn't strictly need
## one, but stamping it keeps the spawn identical to a hand-placed enemy so the soak exercises the real path.
@export var faction: Faction = preload("res://resources/factions/raiders.tres")
@export var npc_count: int = 4
@export var spawn_spread: float = 10.0          ## horizontal scatter radius around the level's PlayerSpawn
@export var wander_radius: float = 8.0           ## how far each NPC roams from spawn — bigger = more navmesh covered
@export var stranded_seconds: float = 12.0       ## game-time to wander while watching for stranding (needs >~10 s to flag)
@export var leak_waves: int = 2                  ## spawn/free cycles for the node-leak trend check
@export var leak_wave_seconds: float = 3.0
@export var leak_slack: int = 12                 ## tolerated node-count drift first->last wave (constant headless overhead)
@export var nav_ready_timeout_frames: int = 600  ## bail (inconclusive) if the navmesh never syncs

var _spawned: Array[Node] = []
var _peak_by_id: Dictionary = {}  ## instance_id -> { name, pos, cycles } peak _stranded_cycles seen this run


## Run the full soak and return a SoakReport. Async: awaits physics frames throughout, so call as
## `var report = await harness.run_soak()`. Assumes this node is parented under the booted level.
func run_soak() -> RefCounted:
	var report := SoakReportScript.new()
	var level := get_parent()
	report.level_name = String(level.name) if level != null else "<none>"
	report.npc_count = npc_count
	_peak_by_id.clear()

	# Querying the nav map before its first sync ERRORS, and a bad/edited bake never readies — so gate the whole
	# run on it and report INCONCLUSIVE rather than false-failing. See [[nav-map-query-before-sync]].
	report.nav_ready = await _await_nav_ready()
	if not report.nav_ready:
		report.notes.append("navmesh never synced in %d frames — missing/edited bake, or a headless reimport is in flight (retry shortly)" % nav_ready_timeout_frames)
		return report

	var anchor := _spawn_anchor()
	var pst := maxi(1, Engine.physics_ticks_per_second)

	# --- STRANDED phase: a wave of wanderers; sample each NPC's OWN stranded counter (not naive position deltas,
	# which can't tell "paused at a wander point" from "wedged"). The NPC already makes that distinction. ---
	_spawn_wave(anchor)
	var stranded_frames := int(stranded_seconds * pst)
	for i in stranded_frames:
		await get_tree().physics_frame
		if i % 12 == 0:
			_sample_stranded()
	_sample_stranded()
	_record_stranded(report)
	_free_wave()
	await _settle()

	# --- LEAK phase: baseline, then spawn/free waves; node count after each cleanup must not trend up. ---
	report.node_baseline = _node_count()
	report.orphan_baseline = _orphan_count()
	var wave_frames := int(leak_wave_seconds * pst)
	for w in leak_waves:
		_spawn_wave(anchor)
		for j in wave_frames:
			await get_tree().physics_frame
		_free_wave()
		await _settle()
		report.leak_post_wave_nodes.append(_node_count())
	report.orphan_final = _orphan_count()
	report.leak_slack = leak_slack
	return report


# --- spawning ---------------------------------------------------------------------------------------------------

## Instance npc_count NPCs as siblings of the level (like EncounterSpawner), stamping exports BEFORE add_child so
## their _ready reads them, then scattering them around the anchor. `wanders` MUST be set — it defaults false, and
## a non-wandering idle NPC just stands still (no stranding signal, no traversal stress).
func _spawn_wave(anchor: Vector3) -> void:
	var parent := get_parent()
	if parent == null:
		return
	for i in npc_count:
		var npc := npc_scene.instantiate()
		npc.set(&"display_name", "Soak%d" % i)
		npc.set(&"wanders", true)
		npc.set(&"wander_radius", wander_radius)
		if faction != null:
			npc.set(&"faction", faction)
		parent.add_child(npc)
		if npc is Node3D:
			(npc as Node3D).global_position = anchor + _scatter()
		_spawned.append(npc)


func _free_wave() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	_spawned.clear()


## queue_free resolves at frame end; await a few frames so the freed NPCs actually leave the node count before it
## is sampled (otherwise the leak baseline reads high and every wave looks clean by comparison).
func _settle() -> void:
	for i in 8:
		await get_tree().process_frame


## The level's PlayerSpawn is a guaranteed-on-floor anchor; fall back to the origin (lifted) if the level has none.
func _spawn_anchor() -> Vector3:
	for n in get_tree().get_nodes_in_group(Groups.PLAYER_SPAWN):
		if n is Node3D:
			return (n as Node3D).global_position
	return Vector3(0.0, 2.0, 0.0)


## A random horizontal offset within spawn_spread (uniform over the disc), lifted 1 m so the NPC drops onto the
## floor rather than spawning half-buried.
func _scatter() -> Vector3:
	var ang := randf() * TAU
	var d := sqrt(randf()) * spawn_spread
	return Vector3(cos(ang) * d, 1.0, sin(ang) * d)


# --- stranded sampling ------------------------------------------------------------------------------------------

## Record the PEAK _stranded_cycles seen per NPC (it resets to 0 on genuine progress, so we must track the high
## water mark, not the instantaneous value). Reading the underscore var directly is intentional — it's the
## engine's own stranded signal and there is no public accessor.
func _sample_stranded() -> void:
	for n in _spawned:
		if not is_instance_valid(n):
			continue
		var cycles := int(n.get(&"_stranded_cycles"))
		var id := n.get_instance_id()
		var prev: Dictionary = _peak_by_id.get(id, {})
		if cycles > int(prev.get("cycles", -1)):
			var pos := (n as Node3D).global_position if n is Node3D else Vector3.ZERO
			_peak_by_id[id] = {"name": String(n.get(&"display_name")), "pos": pos, "cycles": cycles}


func _record_stranded(report: RefCounted) -> void:
	var peak := 0
	for id in _peak_by_id:
		var e: Dictionary = _peak_by_id[id]
		var c := int(e.get("cycles", 0))
		peak = maxi(peak, c)
		if c >= SoakReportScript.STRANDED_THRESHOLD:
			report.stranded.append(e)
	report.peak_stranded_cycles = peak


# --- navmesh + counts -------------------------------------------------------------------------------------------

func _await_nav_ready() -> bool:
	for i in nav_ready_timeout_frames:
		if NavigationUtils.is_nav_map_ready(_nav_map()):
			return true
		await get_tree().physics_frame
	return NavigationUtils.is_nav_map_ready(_nav_map())


func _nav_map() -> RID:
	for n in get_tree().get_nodes_in_group(Groups.NAVMESH):
		if n is NavigationRegion3D:
			return (n as NavigationRegion3D).get_navigation_map()
	var w := get_tree().root.get_world_3d()
	return w.navigation_map if w != null else RID()


func _node_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))


func _orphan_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
