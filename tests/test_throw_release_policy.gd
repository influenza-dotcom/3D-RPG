extends GutTest

## PickupRay's release policy — the pure pair (is_throw_release / launch_impulse) that decides whether letting go of a
## carried prop is a real THROW, and how fast it leaves the hand. Everything throw-only in PickupRay._release hangs off
## that single answer: the launch speed, the prop's throw_sound, and the thrown facing (mark_thrown_for_facing).
##
## THE invariant worth pinning: `launch_impulse` reads the RAW impulse to classify the release and applies the prop's
## throw_impulse_mult only AFTER. Fold those two steps together and a prop tuned to fly fast (the knife, 2.5x) would
## have its gentle 1.0 tap-DROP scaled to 2.5 — and on a hotter multiplier, promoted past the 12.0 throw threshold, so
## an H tap-drop would nose, whip and credit the player as an attack. The in-tree release (physics restore, velocity,
## collision exceptions) is manual-playtest territory per the project's testing rules; this pins the pure branch.
##
## Numbers mirror PhysicsDamageSettings defaults: pickup_drop_impulse 1.0, pickup_throw_impulse 12.0.

const DROP := 1.0
const THROW := 12.0


func test_charged_release_at_the_threshold_is_a_throw() -> void:
	assert_true(PickupRay.is_throw_release(THROW, THROW, true), "an impulse AT the throw threshold is a throw")
	assert_true(PickupRay.is_throw_release(THROW + 5.0, THROW, true), "an impulse above the threshold is a throw")


func test_tap_drop_is_not_a_throw() -> void:
	assert_false(PickupRay.is_throw_release(DROP, THROW, true), "the tap-drop impulse is below the threshold")


func test_forced_release_is_never_a_throw() -> void:
	# force_release_held (death / quickload / scene teardown) passes credit_thrower false — it must not nose the prop,
	# play a throw whip, or credit the player with an attack, whatever impulse it uses.
	assert_false(PickupRay.is_throw_release(THROW, THROW, false),
		"a forced release is not a throw even at full throw impulse")


func test_throw_is_scaled_by_the_props_multiplier() -> void:
	assert_almost_eq(PickupRay.launch_impulse(THROW, THROW, 2.5, true), 30.0, 0.0001,
		"a 2.5x prop (the knife) leaves the hand at 2.5x the base throw speed")
	assert_almost_eq(PickupRay.launch_impulse(THROW, THROW, 1.0, true), THROW, 0.0001,
		"a normal prop throws at exactly the tuned base impulse")


func test_tap_drop_is_never_scaled_even_on_a_fast_throw_prop() -> void:
	# The whole reason the multiplier is applied AFTER the classification: setting a knife down must stay a gentle set-
	# down, not a 2.5x shove — and must never cross the threshold into throw behaviour.
	assert_almost_eq(PickupRay.launch_impulse(DROP, THROW, 2.5, true), DROP, 0.0001,
		"a fast-throw prop's tap-drop keeps the plain drop impulse")
	assert_false(PickupRay.is_throw_release(PickupRay.launch_impulse(DROP, THROW, 2.5, true), THROW, true),
		"and the scaled result still can't be re-read as a throw")


func test_a_very_hot_multiplier_cannot_promote_a_drop() -> void:
	# The failure mode stated as a number: 1.0 x 20 = 20, which is well past the 12.0 threshold. Scaling first would
	# turn every tap-drop of that prop into a full throw.
	assert_almost_eq(PickupRay.launch_impulse(DROP, THROW, 20.0, true), DROP, 0.0001,
		"even a 20x prop's tap-drop stays at the drop impulse")


func test_forced_release_is_not_scaled() -> void:
	assert_almost_eq(PickupRay.launch_impulse(THROW, THROW, 2.5, false), THROW, 0.0001,
		"a forced release ignores the throw multiplier")


func test_resolved_multiplier_floors_at_zero() -> void:
	# A negative authored multiplier would fling the prop BACKWARD out of your face; Throwable floors it.
	var t: Throwable = load("res://scripts/components/Throwable.gd").new()
	t.throw_impulse_mult = -3.0
	assert_eq(t.resolved_throw_impulse_mult(), 0.0, "a negative throw multiplier is floored to 0, never reversed")
	t.throw_impulse_mult = 2.5
	assert_almost_eq(t.resolved_throw_impulse_mult(), 2.5, 0.0001, "a positive multiplier passes through")
	t.free()
