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

## An NPC with no rig wired (the shipped default: actors are procedural) must shrug off PLAY_ANIM without stealing
## the NPC's brain or poking anything else; the SAME actor wired to a real AnimationPlayer must actually play the
## clip, and a clip the rig lacks (a typo in the Cutscene resource) must be skipped rather than erroring mid-scene.
func test_actor_play_anim_is_a_no_op_without_a_rig_and_plays_a_wired_clip() -> void:
	var npc := StubNpc.new()
	add_child_autofree(npc)
	var actor = ActorScript.new()
	npc.add_child(actor)
	actor.play_anim(&"wave")  # animation_player_path empty -> nothing to play on
	assert_false(npc.control, "PLAY_ANIM with no rig must not take cutscene control (the NPC's brain keeps running)")
	assert_eq(npc.walked, Vector3.ZERO, "PLAY_ANIM with no rig must not start a scripted walk")
	assert_eq(npc.faced, Vector3.ZERO, "PLAY_ANIM with no rig must not start a scripted turn")

	# Control: wire a real rig with one clip and the same call now plays it.
	var ap := AnimationPlayer.new()
	ap.name = "Rig"
	var lib := AnimationLibrary.new()
	var clip := Animation.new()
	clip.length = 1.0
	lib.add_animation(&"wave", clip)
	ap.add_animation_library(&"", lib)
	npc.add_child(ap)
	actor.animation_player_path = NodePath("../Rig")
	actor.play_anim(&"dance")
	assert_false(ap.is_playing(), "a clip the rig does not have is skipped, not played (and never errors mid-cutscene)")
	actor.play_anim(&"")
	assert_false(ap.is_playing(), "an empty clip name plays nothing")
	actor.play_anim(&"wave")
	assert_true(ap.is_playing(), "a wired rig with the named clip plays it — PLAY_ANIM visibly animates the NPC")
	assert_eq(String(ap.current_animation), "wave", "and it is the clip the cutscene asked for")
	assert_false(npc.control, "playing a clip still never takes the NPC's brain (only walk_to/face do)")
	ap.stop()
	lib = null
	clip = null
