extends GutTest

## PickupRay carry STEP-OVER wall-vs-stair discriminator (ray_cast.gd step_over_gained_ground). This is the pure
## predicate that lets a carried physics prop ride UP a ~0.5 m stair riser while REFUSING to ratchet up a flat wall:
## after the direct chase-cast jams on an obstacle, the prop is lifted a step-up budget and the horizontal advance is
## re-cast from the raised pose; the lift is KEPT only when that raised cast buys meaningfully more HORIZONTAL (XZ)
## travel than the blocked direct cast did. That XZ-gain gate is the whole no-clip guarantee — a wall yields ~0 gain
## at any lift height (rejected), a stair lip opens travel once cleared (accepted). The in-tree carry motion itself
## (cast_motion against frozen kinematic bodies, live world geometry) is manual-playtest territory per the project's
## testing rules; this pins the one pure branch so a future edit can't silently turn the prop into a wall-climber.

func test_stair_lip_is_accepted() -> void:
	# Direct cast jammed on the riser (~0 XZ); lifting cleared the lip so the horizontal opens up (0.4 XZ). Kept.
	assert_true(
		PickupRay.step_over_gained_ground(0.0, 0.4, 0.02),
		"a real stair step-over gains horizontal ground -> the lift is accepted")


func test_flat_wall_is_rejected() -> void:
	# Wall blocks the direct cast AND the raised horizontal (~0 XZ each) -> no gain -> the prop cannot climb it.
	assert_false(
		PickupRay.step_over_gained_ground(0.0, 0.0, 0.02),
		"a flat wall yields no horizontal gain -> the lift is rejected (no wall-climb)")


func test_partial_direct_still_climbs_when_lift_adds_more() -> void:
	# Direct made a little XZ headway (0.1) but the lift opens much more (0.35): the extra beats the threshold -> kept.
	assert_true(
		PickupRay.step_over_gained_ground(0.1, 0.35, 0.02),
		"a lift that adds real XZ over a partial direct cast is a genuine step-over")


func test_negligible_gain_is_rejected() -> void:
	# A sub-threshold sliver of extra clearance (below min_progress) must NOT register as a step-over.
	assert_false(
		PickupRay.step_over_gained_ground(0.10, 0.115, 0.02),
		"an XZ gain under min_progress is a graze, not a step-over")
