extends GutTest

## Tests for PropFollow — the teleport-behind follow for physics props (the prop twin of CompanionFollow). The blink
## DECISION (should_blink) and the off-screen test (in_view_cone) are pure static maths — literal numbers/vectors, no
## tree. The actual teleport (down-ray + RigidBody move) is in-tree and physics-driven, so it's manual-playtest only.

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


func test_disabled_by_default() -> void:
	# Off-tree field read — PropFollow.new() with no add_child runs no process. It ships OFF so an unclaimed prop
	# never follows; Claimable flips it on when the prop is claimed.
	var f = PropFollow.new()
	assert_false(f.enabled,
		"PropFollow ships disabled — only a claim (or the designer) switches it on")
	f.free()


func test_in_view_cone_detects_on_screen() -> void:
	# Camera at origin looking down +X (fwd_flat = (1,0,0)); a point straight ahead is on-screen.
	var on := PropFollow.in_view_cone(Vector3.ZERO, Vector3(1, 0, 0), Vector3(10, 0, 0), 0.35)
	assert_true(on, "a point directly in front of the camera is inside the view cone (would pop on-screen)")


func test_in_view_cone_clears_behind() -> void:
	# A point straight BEHIND the camera is outside the cone — safe to blink there.
	var behind := PropFollow.in_view_cone(Vector3.ZERO, Vector3(1, 0, 0), Vector3(-10, 0, 0), 0.35)
	assert_false(behind, "a point behind the player is outside the view cone — a hidden teleport is allowed there")


func test_source_on_screen_forbids_blink() -> void:
	# _try_blink now guards its SOURCE with this same in_view_cone test (not just the landing spot): a prop the
	# player has turned to LOOK at — in front of the camera, so inside the cone — must be refused so it can't vanish
	# from view. This asserts the maths that gate reads; the in-tree teleport itself is manual-playtest only.
	var prop_in_front := PropFollow.in_view_cone(Vector3.ZERO, Vector3(1, 0, 0), Vector3(10, 0, 0), 0.35)
	assert_true(prop_in_front,
		"a prop the player is looking at is on-screen -> _try_blink's source guard refuses the blink (no vanishing)")
