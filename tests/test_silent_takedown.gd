extends GutTest

## Pure-logic tests for the Slice 6b takedown eligibility predicate (SilentTakedown.eligible). Mirrors
## test_damage_applier's is_behind cases: no tree, no nodes — call the static with literal booleans/floats. The
## in-tree raycast + kill path is left to manual playtest (per CLAUDE.md, don't run Player/NPC _ready in a test).

const SilentTakedown := preload("res://scripts/player/silent_takedown.gd")


func test_alerted_target_never_eligible() -> void:
	# off_guard=false (the NPC has locked on) blocks a takedown no matter what else holds.
	assert_false(SilentTakedown.eligible(false, true, false, true, true, 1.0, 2.0),
		"An ALERTED (not off-guard) target can never be silently taken down")


func test_offguard_behind_in_range_is_eligible() -> void:
	assert_true(SilentTakedown.eligible(true, true, false, true, true, 1.0, 2.0),
		"Off-guard + behind + within range = eligible")


func test_range_gate() -> void:
	assert_false(SilentTakedown.eligible(true, false, false, true, true, 3.0, 2.0),
		"Beyond max_range = not eligible")
	assert_true(SilentTakedown.eligible(true, false, false, true, true, 2.0, 2.0),
		"Exactly at max_range = eligible (inclusive)")


func test_behind_gate() -> void:
	assert_false(SilentTakedown.eligible(true, false, false, false, true, 1.0, 2.0),
		"Not behind, with require_behind on = not eligible")
	assert_true(SilentTakedown.eligible(true, false, false, false, false, 1.0, 2.0),
		"Front allowed when require_behind is off")


func test_crouch_gate() -> void:
	assert_false(SilentTakedown.eligible(true, false, true, true, true, 1.0, 2.0),
		"Standing, with require_crouch on = not eligible")
	assert_true(SilentTakedown.eligible(true, true, true, true, true, 1.0, 2.0),
		"Crouched satisfies require_crouch")
