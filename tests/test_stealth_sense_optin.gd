extends GutTest

## Rank 18: per-NPC stealth-sense opt-in (body_discovery / hearing_initiates OR'd with the global gates), the
## public investigate() facade routing through Perception, and the InvestigatePoint marker dispatch.

const NpcScript = preload("res://scripts/npc/npc.gd")
const InvestigatePointScript = preload("res://scripts/components/investigate_point.gd")

class StubNpc extends Node3D:
	var investigated = null
	var was_alerted := false
	func investigate(point: Vector3, alerted: bool) -> void:
		investigated = point
		was_alerted = alerted

func test_per_npc_stealth_opt_in_ors_with_global() -> void:
	var npc = NpcScript.new()  # off-tree (no _ready)
	assert_false(npc._hearing_initiates_on(), "hearing off by default (global off + opt-in off)")
	assert_false(npc._body_discovery_on(), "body-discovery off by default")
	npc.hearing_initiates_opt_in = true
	npc.body_discovery_opt_in = true
	assert_true(npc._hearing_initiates_on(), "per-NPC opt-in turns hearing on for this NPC")
	assert_true(npc._body_discovery_on(), "per-NPC opt-in turns body-discovery on for this NPC")
	npc.free()

func test_investigate_routes_to_perception() -> void:
	var npc = NpcScript.new()
	var perc := Perception.new()
	npc._perception = perc
	npc.investigate(Vector3(2, 0, 3), false)
	assert_eq(perc.state, Perception.State.INVESTIGATING, "investigate() puts Perception into INVESTIGATING")
	assert_eq(perc.last_known_position, Vector3(2, 0, 3), "at the requested point")
	assert_true(npc._scripted_investigating, "the scripted-investigate flag is armed")
	perc.free()
	npc.free()

func test_investigate_no_perception_is_noop() -> void:
	var npc = NpcScript.new()
	npc.investigate(Vector3.ZERO, false)  # _perception is null -> safe no-op
	assert_false(npc._scripted_investigating, "no perception -> nothing armed")
	npc.free()

func test_investigate_point_sends_specific_npc() -> void:
	var ip = InvestigatePointScript.new()
	var npc := StubNpc.new()
	npc.name = "Guard"
	ip.add_child(npc)
	ip.npc_path = NodePath("Guard")
	ip.alerted = true
	add_child_autofree(ip)
	ip.global_position = Vector3(7, 0, 0)
	ip.trigger()
	assert_eq(npc.investigated, Vector3(7, 0, 0), "sends the specific NPC to this marker's position")
	assert_true(npc.was_alerted, "the alerted flag is forwarded")
