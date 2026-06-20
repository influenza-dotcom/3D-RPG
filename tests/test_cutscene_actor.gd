extends GutTest

## Rank 11 (CutsceneActor): the NPC brain-suppress state surface (set_cutscene_control / walk_to / face) and the
## CutsceneActor facade delegating to its NPC. Pure state — no NPC _ready/_physics_process (playtest covers the
## actual stepping); the always-release guarantee is in test_cutscene.gd.

const NpcScript = preload("res://scripts/npc/npc.gd")
const ActorScript = preload("res://scripts/components/cutscene_actor.gd")

class StubNpc extends Node:
	var control := false
	var walked: Vector3 = Vector3.ZERO
	var faced: Vector3 = Vector3.ZERO
	func set_cutscene_control(on: bool) -> void:
		control = on
	func walk_to(p: Vector3) -> void:
		walked = p
	func face(p: Vector3) -> void:
		faced = p

func test_npc_cutscene_control_state() -> void:
	var npc = NpcScript.new()  # off-tree (no _ready)
	npc.set_cutscene_control(true)
	npc.walk_to(Vector3(3, 0, 4))
	npc.face(Vector3(1, 0, 0))
	assert_true(npc._cutscene_control, "set_cutscene_control(true) suppresses the brain")
	assert_true(npc._cutscene_has_walk, "walk_to arms a scripted walk")
	assert_eq(npc._cutscene_walk_target, Vector3(3, 0, 4), "walk target stored")
	assert_true(npc._cutscene_has_face, "face arms a scripted turn")
	npc.set_cutscene_control(false)
	assert_false(npc._cutscene_control, "control released")
	assert_false(npc._cutscene_has_walk, "release clears the scripted walk")
	assert_false(npc._cutscene_has_face, "release clears the scripted face")
	npc.free()

func test_actor_delegates_to_npc() -> void:
	var actor = ActorScript.new()
	var npc := StubNpc.new()
	npc.add_child(actor)  # actor's _npc() falls back to its parent
	actor.walk_to(Vector3(5, 0, 0))
	assert_true(npc.control, "walk_to takes cutscene control of the NPC")
	assert_eq(npc.walked, Vector3(5, 0, 0), "walk_to forwards the point")
	actor.face(Vector3(0, 0, 9))
	assert_eq(npc.faced, Vector3(0, 0, 9), "face forwards the point")
	actor.end()
	assert_false(npc.control, "end releases control")
	npc.free()

func test_actor_play_anim_no_rig_is_noop() -> void:
	var actor = ActorScript.new()
	var npc := StubNpc.new()
	npc.add_child(actor)
	actor.play_anim(&"wave")  # no AnimationPlayer assigned -> must not crash
	assert_true(true, "play_anim with no rig is a safe no-op")
	npc.free()
