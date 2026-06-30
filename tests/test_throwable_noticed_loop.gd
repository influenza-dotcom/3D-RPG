extends GutTest

## Tests for Throwable.loop_noticed — the "pant when the player is near or looking at me" policy that drives the dog's
## idle loop (the same held_loop_sound it plays while carried) when you're paying attention to it. Pure static + literal
## args (mirrors loyal_scale / Pettable.eligible) — no tree/camera; the live player + camera resolution
## (_player_noticing) and the per-frame loop start/stop (_update_ambient_loop) are manual-playtest / live-path covered.

const Throwable := preload("res://scripts/components/Throwable.gd")

# Args: (dist, near_radius, look_range, look_dot, view_dot)

func test_near_triggers_regardless_of_facing() -> void:
	# Within the proximity radius -> pant even when looking away (view_dot well below look_dot).
	assert_true(Throwable.loop_noticed(2.0, 3.5, 12.0, 0.96, -1.0),
		"inside near_radius the prop pants regardless of where the player faces")


func test_outside_near_and_not_looking_is_silent() -> void:
	assert_false(Throwable.loop_noticed(8.0, 3.5, 12.0, 0.96, 0.0),
		"beyond near_radius and not centered in view -> no pant")


func test_looking_within_range_triggers() -> void:
	# Out of near range but inside look range AND centered enough (view_dot >= look_dot).
	assert_true(Throwable.loop_noticed(8.0, 3.5, 12.0, 0.96, 0.98),
		"looking roughly at the prop within look_range starts the pant")


func test_looking_but_too_far_is_silent() -> void:
	assert_false(Throwable.loop_noticed(20.0, 3.5, 12.0, 0.96, 1.0),
		"dead-on but beyond look_range -> no pant")


func test_looking_but_off_center_is_silent() -> void:
	assert_false(Throwable.loop_noticed(8.0, 3.5, 12.0, 0.96, 0.5),
		"within look_range but not centered enough (view_dot < look_dot) -> no pant")


func test_zero_radii_disable_triggers() -> void:
	# Both triggers off -> never noticed (the loop would then only play while held).
	assert_false(Throwable.loop_noticed(0.5, 0.0, 0.0, 0.96, 1.0),
		"near_radius 0 and look_range 0 disable both triggers")
