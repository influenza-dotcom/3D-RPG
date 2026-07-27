class_name NpcPoolReuseHarness
extends Node

## In-tree gate for NPC node POOLING (NpcPool). Warms a small fleet of real armed NPCs into a pool, then runs several
## acquire -> kill -> re-acquire cycles and checks the three pooling invariants (see NpcPoolReuseReport): the SAME
## instances come back (reuse, not re-instancing), the pool count stays flat (no leak/growth), and a re-acquired body
## is a pristine post-_ready combatant (reset worked). This is the widest-coverage test of NPC.reset_for_reuse + every
## component reset — it runs the real NPC._ready + a real death (take_damage -> die -> pool.reclaim) that the off-tree
## unit tests can't. OPT-IN under tests_soak/ (heavy: full NPC._ready), exactly like CombatSmokeHarness / SoakHarness.
## Preloaded by path in the test (not the class_name) to dodge an editor-cache cascade on a headless load.

const PoolScript := preload("res://scripts/components/npc_pool.gd")
const DefScript := preload("res://scripts/combat/spawn_definition.gd")
const ReportScript := preload("res://scripts/tools/npc_pool_reuse_report.gd")

@export var npc_scene: PackedScene = preload("res://scenes/characters/NPC.tscn")
@export var faction: Faction = preload("res://resources/factions/raiders.tres")
@export var weapon: WeaponData = preload("res://resources/weapons/pistol.tres")
@export var fleet: int = 3                 ## bodies warmed into the pool (and acquired each cycle)
@export var cycles: int = 3                ## acquire -> kill -> re-acquire rounds
@export var nav_ready_timeout_frames: int = 600

var _pool: Node = null
var _def: Resource = null


## Run the reuse smoke and return an NpcPoolReuseReport. Async — call as `await harness.run_reuse()`. Assumes this
## node is parented under a booted level (a navmesh helps the NPCs' per-frame nav reads not error, but no movement
## is required for the reset checks).
func run_reuse() -> RefCounted:
	var report := ReportScript.new()
	report.warmed = fleet
	report.cycles = cycles

	report.nav_ready = await _await_nav_ready()
	if not report.nav_ready:
		report.notes.append("navmesh never synced in %d frames — reimport in flight or a bad bake; INCONCLUSIVE" % nav_ready_timeout_frames)
		return report

	var parent := get_parent()
	if parent == null:
		report.notes.append("no parent level to spawn into")
		return report

	# Build the pool + a code-authored loadout def (profile-less: faction + weapon overrides), warm the fleet.
	_pool = PoolScript.new()
	_pool.name = &"ReuseTestPool"
	parent.add_child(_pool)
	_def = DefScript.new()
	_def.npc_scene = npc_scene
	_def.faction_override = faction
	_def.weapon_override = weapon
	_def.count = fleet
	_def.auto_aggro = false
	_pool.warm(_def, fleet)
	# A couple of frames so the warmed bodies' _ready + the DEFERRED enable_grid settle before we acquire.
	await get_tree().process_frame
	await get_tree().process_frame
	report.pool_count_start = int(_pool.get(&"_all").size())

	var anchor := _spawn_anchor()

	# --- RESET-CLEANLINESS: one body at a time, checked the INSTANT it is re-acquired (before ANY physics frame) ---
	# Isolated from combat: only one live body exists during the check, and we sample before its AI (or a neighbour's)
	# can touch it — so a failure is genuinely reset_for_reuse, not two spawned raiders shooting each other.
	var probe = _pool.acquire(_def, parent, anchor + Vector3(0.0, 1.0, 0.0))
	if probe == null:
		report.notes.append("initial acquire returned null (warm produced no bodies)")
		return report
	probe.take_damage(9_999.0, false, null, Vector3.INF)  # synchronous: -> die -> pool.reclaim -> parked
	var reused = _pool.acquire(_def, parent, anchor + Vector3(0.0, 1.0, 0.0))  # the SAME instance, freshly reset
	if reused == null:
		report.notes.append("re-acquire after a kill returned null (reclaim didn't re-bank the body)")
		return report
	report.reset_clean = _check_reset([reused], report.reset_notes)  # sampled with ZERO physics frames elapsed
	reused.take_damage(9_999.0, false, null, Vector3.INF)  # re-park it for the reuse/stability loop below
	await get_tree().physics_frame

	# --- REUSE + STABILITY: acquire the whole fleet, confirm the SAME instances come back, and the pool never grows.
	var original_ids: Array[int] = []
	report.reused_all_same = true
	for cycle in cycles:
		var acquired: Array = []
		for i in fleet:
			var pos := anchor + Vector3(float(i) * 3.0, 1.0, 0.0)
			var npc = _pool.acquire(_def, parent, pos)
			if npc == null:
				report.notes.append("acquire returned null on cycle %d (bucket drained unexpectedly)" % cycle)
				continue
			acquired.append(npc)
		if cycle == 0:
			for npc in acquired:
				original_ids.append(npc.get_instance_id())
		else:
			for npc in acquired:  # every body handed out must be one of the ORIGINAL warmed instances
				if not original_ids.has(npc.get_instance_id()):
					report.reused_all_same = false
		# Kill them all — take_damage -> _begin_death (no freeze for pooled) -> gore + die -> pool.reclaim (parked).
		for npc in acquired:
			if is_instance_valid(npc):
				npc.take_damage(9_999.0, false, null, Vector3.INF)
		await get_tree().physics_frame

	report.pool_count_final = int(_pool.get(&"_all").size())
	return report


## Assert every reused body is a pristine post-_ready combatant. Appends a note per failing check; returns true only
## when ALL bodies pass ALL checks. Duck-typed reads (get/call) so the harness needn't hard-depend on NPC internals.
func _check_reset(bodies: Array, out_notes: Array[String]) -> bool:
	var clean := true
	for npc in bodies:
		if not is_instance_valid(npc):
			out_notes.append("a reused body was freed (should be parked, not freed)")
			clean = false
			continue
		var label := String(npc.get(&"display_name"))
		if bool(npc.get(&"_dead")):
			out_notes.append("%s: _dead still true" % label); clean = false
		var hp := float(npc.get(&"hp")); var max_hp := float(npc.get(&"max_hp"))
		if not is_equal_approx(hp, max_hp):
			out_notes.append("%s: hp %.1f != max_hp %.1f" % [label, hp, max_hp]); clean = false
		if npc.get(&"_target") != null:
			out_notes.append("%s: _target not cleared" % label); clean = false
		var perc = npc.get(&"_perception")
		if perc != null and int(perc.get(&"state")) != int(Perception.State.UNAWARE):
			out_notes.append("%s: perception not UNAWARE (%d)" % [label, int(perc.get(&"state"))]); clean = false
		if npc.process_mode != Node.PROCESS_MODE_INHERIT:
			out_notes.append("%s: process_mode not INHERIT" % label); clean = false
		if not npc.visible:
			out_notes.append("%s: not visible" % label); clean = false
		var inv = npc.get(&"inventory")
		if inv != null and inv.is_empty():
			out_notes.append("%s: backpack empty (not re-seeded)" % label); clean = false
		var ft := float(npc.get(&"_fire_timer"))
		var shot := float(npc.call(&"_shot_interval"))
		if not is_equal_approx(ft, shot):
			out_notes.append("%s: _fire_timer %.3f != _shot_interval %.3f (first shot not re-armed)" % [label, ft, shot]); clean = false
	return clean


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
