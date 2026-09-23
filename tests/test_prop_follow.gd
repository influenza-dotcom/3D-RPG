extends GutTest

## Tests for PropFollow — the teleport-behind follow for physics props (the prop twin of CompanionFollow). The blink
## DECISION (should_blink) and the off-screen test (in_view_cone) are pure static maths — literal numbers/vectors, no
## tree. _try_blink's on-screen SOURCE guard and a landing are driven in a tiny in-tree rig (floor + a camera-carrying
## player stand-in); the full _physics_process loop needs a real Player (Groups.human_player), so it stays playtest-only.

const PropFollow := preload("res://scripts/components/prop_follow.gd")


func test_blinks_when_far_and_off_cooldown() -> void:
	assert_true(PropFollow.should_blink(12.0, 9.0, 0.0),
		"past the distance threshold AND off cooldown => the prop may blink up behind the player")


func test_no_blink_when_close() -> void:
	assert_false(PropFollow.should_blink(3.0, 9.0, 0.0),
		"within the distance threshold the prop is 'keeping up' and stays put")


func test_no_blink_while_on_cooldown() -> void:
	assert_false(PropFollow.should_blink(20.0, 9.0, 0.5),
		"even far behind, a blink is forbidden until the cooldown bleeds to zero (no strobing)")


func test_ships_disabled_and_a_disabled_follower_stays_inert() -> void:
	var f = PropFollow.new()
	assert_false(f.enabled,
		"ship decision: PropFollow ships disabled -- an unclaimed prop never follows; only a claim (or the designer) switches it on")
	# ...and the flag is honoured: in the tree under a live prop, the default follower's physics tick does nothing at
	# all -- not even bleeding the blink cooldown Claimable re-arms on claim.
	var prop := Node3D.new()
	add_child_autofree(prop)
	prop.add_child(f)  # freed with the autofreed prop
	f.reset_cooldown()
	f._physics_process(10.0)
	assert_almost_eq(f._cooldown, f.teleport_cooldown, 0.0001,
		"a disabled follower's tick is a no-op (the cooldown is untouched after 10 s)")
	f.enabled = true  # what Claimable does on claim
	f._physics_process(10.0)
	assert_almost_eq(f._cooldown, 0.0, 0.0001, "control: once switched on, the same tick runs and bleeds the cooldown")


func test_in_view_cone_detects_on_screen() -> void:
	# Camera at origin looking down +X (fwd_flat = (1,0,0)); a point straight ahead is on-screen.
	var on := PropFollow.in_view_cone(Vector3.ZERO, Vector3(1, 0, 0), Vector3(10, 0, 0), 0.35)
	assert_true(on, "a point directly in front of the camera is inside the view cone (would pop on-screen)")


func test_in_view_cone_clears_behind() -> void:
	# A point straight BEHIND the camera is outside the cone — safe to blink there.
	var behind := PropFollow.in_view_cone(Vector3.ZERO, Vector3(1, 0, 0), Vector3(-10, 0, 0), 0.35)
	assert_false(behind, "a point behind the player is outside the view cone — a hidden teleport is allowed there")


## The HUMAN-player stand-in _try_blink reads: a Node3D exposing the view camera as camera_effects.
class ViewerStub extends Node3D:
	var camera_effects: Camera3D = null


## An in-tree Node3D prop at `at`, freed with the test.
func _prop_at(at: Vector3) -> Node3D:
	var prop := Node3D.new()
	add_child_autofree(prop)
	prop.global_position = at
	return prop


func test_a_prop_the_player_is_looking_at_never_blinks_away() -> void:
	# _try_blink guards its SOURCE with the view cone (not just the landing spot): a prop the player has turned to LOOK
	# at must be refused, or it vanishes from in front of them. Rig: a wide floor, a player at the origin whose camera
	# looks down -Z, and two far-behind-the-leash props -- one straight ahead (on-screen), one straight behind.
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 80.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	add_child_autofree(floor_body)
	var player := ViewerStub.new()
	add_child_autofree(player)
	var cam := Camera3D.new()  # default orientation: looking down -Z
	player.add_child(cam)
	player.camera_effects = cam
	var on_screen := _prop_at(Vector3(0.0, 0.0, -20.0))
	var off_screen := _prop_at(Vector3(0.0, 0.0, 20.0))
	await wait_physics_frames(3)  # let the floor register so the landing down-ray can hit it
	var follow = PropFollow.new()  # off-tree: _try_blink reads only its arguments and this node's exports

	assert_false(follow._try_blink(on_screen, player),
		"a prop inside the player's view cone must refuse to blink (it would vanish in front of them)")
	assert_eq(on_screen.global_position, Vector3(0.0, 0.0, -20.0), "...and it stays exactly where the player sees it")

	# Control: the same rig and follower, with the prop OUT of view -> the blink runs and lands behind the player.
	assert_true(follow._try_blink(off_screen, player), "an off-screen prop with floor behind the player blinks")
	assert_almost_eq(off_screen.global_position, Vector3(0.0, 0.1, follow.teleport_behind), Vector3.ONE * 0.05,
		"...landing teleport_behind metres straight behind the player, resting a hair above the floor")
	follow.free()
