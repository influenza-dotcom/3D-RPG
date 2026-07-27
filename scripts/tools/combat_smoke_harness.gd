class_name CombatSmokeHarness
extends Node

## In-tree COMBAT smoke gate (Wave 4 / T1). Spawns ONE pistol raider and ONE opposed-faction townsfolk dummy, lets the
## raider's OWN perception acquire it (we NEVER hand-set _target), and runs real combat for a few seconds. Returns a
## CombatSmokeReport: did the chain land damage and did the combatants close, without leaking nodes. This is the
## widest-coverage NPC test — it exercises perceive/plan/aim/fire/hit/take_damage that the off-tree unit tests
## (planner logic, action dispatch) cannot, so it's the standing gate for the Wave 5/6 npc.gd extractions. OPT-IN
## under tests_soak/ (heavy: full NPC._ready), exactly like SoakHarness.
##
## Determinism (the harness's whole job is to NOT flake):
## - An NPC target is NEVER miss-rolled (miss_chance only applies vs the &"Player" group), and raiders.relation_to
##   (townsfolk) is -1 (mutually hostile), so a raider that SEES a townsfolk WILL land shots — no player involved.
## - Both combatants are stamped a LARGE max_hp (survivor_hp), so neither dies inside the window: the original flake
##   was hp=4 both sides -> a coin-flip who kills whom first. With survivor_hp both survive, damage shows as an hp
##   DROP (min_dummy_hp < start), and the raider can't be killed by the townsfolk's melee before its shots land.
##   (max_hp stamping STICKS: Character._apply_stats is additive — max_hp = max_hp + strength max_hp_bonus.)
## - They spawn facing each other, `separation` apart with clear LOS on the flat sandbox, so perception acquires fast.
## Preloaded by path in the test (not the class_name) to dodge an editor-cache cascade on a headless load.

const ReportScript := preload("res://scripts/tools/combat_smoke_report.gd")

@export var npc_scene: PackedScene = preload("res://scenes/characters/NPC.tscn")
@export var shooter_faction: Faction = preload("res://resources/factions/raiders.tres")
@export var dummy_faction: Faction = preload("res://resources/factions/townsfolk.tres")  # relation to raiders is -1 (hostile)
@export var weapon: WeaponData = preload("res://resources/weapons/pistol.tres")
@export var separation: float = 9.0        ## metres apart at spawn — within sight_range, clear LOS on the flat sandbox
@export var sight_range: float = 30.0      ## stamped on both so acquisition can't fail on a small default over `separation`
@export var survivor_hp: float = 1000.0    ## stamped max_hp on BOTH so neither dies in the window (no death coin-flip)
@export var combat_seconds: float = 9.0    ## generous window: perception time_to_detect + GOAP plan + aim + fire + travel
@export var nav_ready_timeout_frames: int = 600
@export var orphan_slack: int = 8

var _shooter: Node3D = null
var _dummy: Node3D = null
var _spawned: Array[Node] = []


## Run the smoke and return a CombatSmokeReport. Async — awaits physics frames throughout; call as
## `var report = await harness.run_smoke()`. Assumes this node is parented under a booted level with a baked navmesh.
func run_smoke() -> RefCounted:
	var report := ReportScript.new()
	report.orphan_slack = orphan_slack
	report.orphan_baseline = _orphan_count()

	# Gate on nav sync: a query before first sync ERRORS, a bad bake never readies. INCONCLUSIVE, not a false fail.
	report.nav_ready = await _await_nav_ready()
	if not report.nav_ready:
		report.notes.append("navmesh never synced in %d frames — reimport in flight or a bad bake; INCONCLUSIVE" % nav_ready_timeout_frames)
		return report

	var anchor := _spawn_anchor()
	# Shooter at the anchor facing +X; dummy `separation` along +X facing back at it (both see each other immediately).
	_shooter = _spawn_npc("SmokeShooter", shooter_faction, weapon, anchor + Vector3(0.0, 1.0, 0.0), Vector3(1.0, 0.0, 0.0))
	_dummy = _spawn_npc("SmokeDummy", dummy_faction, null, anchor + Vector3(separation, 1.0, 0.0), Vector3(-1.0, 0.0, 0.0))
	if _shooter == null or _dummy == null:
		report.notes.append("could not spawn combatants (no parent level?)")
		return report
	# A couple of frames so both _ready + the perception can see across the gap before we sample the baseline.
	await get_tree().physics_frame
	await get_tree().physics_frame

	report.dummy_start_hp = float(_dummy.get(&"hp"))
	report.min_dummy_hp = report.dummy_start_hp
	report.initial_distance = _shooter.global_position.distance_to(_dummy.global_position)

	var frames := int(maxf(1.0, combat_seconds) * maxi(1, Engine.physics_ticks_per_second))
	for i in frames:
		await get_tree().physics_frame
		if not is_instance_valid(_shooter):
			report.notes.append("shooter freed mid-run (died?)")
			break
		if not is_instance_valid(_dummy):
			report.dummy_died = true  # freed after death = maximal damage landed
			break
		# Sample hp + distance EVERY frame while the dummy is valid, BEFORE the death break — so min_dummy_hp captures
		# the real drop (with survivor_hp the dummy should survive, making the drop the primary damage signal).
		report.min_dummy_hp = minf(report.min_dummy_hp, float(_dummy.get(&"hp")))
		report.min_distance = minf(report.min_distance, _shooter.global_position.distance_to(_dummy.global_position))
		if bool(_dummy.get(&"_dead")):
			report.dummy_died = true
			break

	report.shooter_alive = is_instance_valid(_shooter) and not bool(_shooter.get(&"_dead"))

	_free_combatants()
	await _settle()
	report.orphan_final = _orphan_count()
	return report


## Instance an NPC as a sibling of the level (like EncounterSpawner / SoakHarness), stamping exports BEFORE add_child
## so _ready reads them: faction (hostility), sight_range (acquisition), and — for the shooter — a loaded weapon.
func _spawn_npc(name_str: String, fac: Faction, wep, pos: Vector3, face_dir: Vector3) -> Node3D:
	var parent := get_parent()
	if parent == null:
		return null
	var npc := npc_scene.instantiate()
	npc.set(&"display_name", name_str)
	npc.set(&"faction", fac)
	npc.set(&"sight_range", sight_range)
	npc.set(&"max_hp", survivor_hp)  # both survive the window (no death coin-flip); damage shows as an hp DROP
	if wep != null:
		npc.set(&"weapon_data", wep)
		npc.set(&"starts_unloaded", false)  # spawn with a full magazine so it can fire immediately
	if npc is Node3D:
		# Set the transform BEFORE add_child so NPC._ready captures the intended _spawn_position + LOS geometry, and
		# face the opponent (Perception measures its cone off basis.z = the model's +Z front) so acquisition is immediate.
		(npc as Node3D).position = pos
		(npc as Node3D).rotation.y = atan2(face_dir.x, face_dir.z)
	parent.add_child(npc)
	_spawned.append(npc)
	return npc as Node3D


func _free_combatants() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	_spawned.clear()


## queue_free resolves at frame end; await a few frames so the freed NPCs actually leave the orphan count.
func _settle() -> void:
	for i in 8:
		await get_tree().process_frame


## The level's PlayerSpawn is a guaranteed-on-floor anchor; fall back to a lifted origin if the level has none.
func _spawn_anchor() -> Vector3:
	for n in get_tree().get_nodes_in_group(Groups.PLAYER_SPAWN):
		if n is Node3D:
			return (n as Node3D).global_position
	return Vector3(0.0, 2.0, 0.0)


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


func _orphan_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
