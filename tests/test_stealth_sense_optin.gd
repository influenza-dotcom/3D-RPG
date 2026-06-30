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
	# This verifies the OR logic (per-NPC opt-in OR the global gate). The project SHIPS these globals ON, so force
	# them OFF locally to prove the per-NPC opt-in alone flips one NPC on regardless of the global. Restored
	# synchronously (GUT asserts don't halt, so the restore always runs).
	var prior_body: bool = GameSettings.npc_ai.body_discovery
	var prior_hear: bool = GameSettings.npc_ai.hearing_initiates
	GameSettings.npc_ai.body_discovery = false
	GameSettings.npc_ai.hearing_initiates = false
	var npc = NpcScript.new()  # off-tree (no _ready)
	assert_false(npc._hearing_initiates_on(), "global off + opt-in off -> hearing off for this NPC")
	assert_false(npc._body_discovery_on(), "global off + opt-in off -> body-discovery off for this NPC")
	npc.hearing_initiates_opt_in = true
	npc.body_discovery_opt_in = true
	assert_true(npc._hearing_initiates_on(), "per-NPC opt-in turns hearing on even with the global off")
	assert_true(npc._body_discovery_on(), "per-NPC opt-in turns body-discovery on even with the global off")
	npc.free()
	GameSettings.npc_ai.body_discovery = prior_body
	GameSettings.npc_ai.hearing_initiates = prior_hear

func test_noise_initiation_requires_hostile_disposition() -> void:
	var npc = NpcScript.new()
	npc.hearing_initiates_opt_in = true
	npc.disposition = Disposition.Kind.HOSTILE
	assert_true(npc._noise_initiates_on(), "hostile NPCs can react to the shared noise channel")
	npc.disposition = Disposition.Kind.NEUTRAL
	assert_false(npc._noise_initiates_on(), "neutral NPCs ignore noise for the simplified stealth loop")
	npc.disposition = Disposition.Kind.FRIENDLY
	assert_false(npc._noise_initiates_on(), "friendly NPCs ignore noise for the simplified stealth loop")
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
