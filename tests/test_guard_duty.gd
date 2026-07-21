extends GutTest

## Rank 19: GuardDuty puts its parent NPC on bodyguard duty (guard(protectee)), resolving the protectee by path
## or group; EncounterSpawner.spawn_points cycle placement and attach_scenes add components to each spawn.

const GuardDutyScript = preload("res://scripts/components/guard_duty.gd")
const EncounterSpawnerScript = preload("res://scripts/components/encounter_spawner.gd")

class StubGuardNpc extends Node:
	var guarding = null
	func guard(c) -> void:
		guarding = c

func test_guard_duty_calls_guard_with_path_target() -> void:
	var npc := StubGuardNpc.new()
	var vip := Node3D.new()
	vip.name = "Vip"
	npc.add_child(vip)
	var gd = GuardDutyScript.new()
	npc.add_child(gd)
	gd.protectee_path = NodePath("../Vip")
	add_child_autofree(npc)  # entering the tree fires gd._ready
	assert_eq(npc.guarding, vip, "GuardDuty puts the parent NPC on guard duty for the path target")

func test_guard_duty_resolves_protectee_by_group() -> void:
	var vip := Node3D.new()
	vip.add_to_group(Groups.VIP)
	add_child_autofree(vip)
	var npc := StubGuardNpc.new()
	var gd = GuardDutyScript.new()
	gd.protectee_group = Groups.VIP
	npc.add_child(gd)
	add_child_autofree(npc)
	assert_eq(npc.guarding, vip, "GuardDuty finds the VIP by group when no path is set")

func test_spawn_points_cycle_placement() -> void:
	var sp = EncounterSpawnerScript.new()
	add_child_autofree(sp)
	var m0 := Marker3D.new()
	m0.name = "M0"
	sp.add_child(m0)
	m0.global_position = Vector3(1, 0, 0)
	var m1 := Marker3D.new()
	m1.name = "M1"
	sp.add_child(m1)
	m1.global_position = Vector3(2, 0, 0)
	var pts: Array[NodePath] = [NodePath("M0"), NodePath("M1")]
	sp.spawn_points = pts
	var def := SpawnDefinition.new()
	assert_eq(sp._spawn_position(def), Vector3(1, 0, 0), "first spawn at marker 0")
	assert_eq(sp._spawn_position(def), Vector3(2, 0, 0), "second at marker 1")
	assert_eq(sp._spawn_position(def), Vector3(1, 0, 0), "cycles back to marker 0")

func test_attach_scenes_added_as_children() -> void:
	var sp = EncounterSpawnerScript.new()
	var npc := Node.new()
	add_child_autofree(npc)
	var inner := Node.new()
	var ps := PackedScene.new()
	ps.pack(inner)
	inner.free()
	var scenes: Array[PackedScene] = [ps]
	sp.attach_scenes = scenes
	sp._attach_components(npc)
	assert_eq(npc.get_child_count(), 1, "each attach_scenes component is added under the spawn")
	sp.free()
