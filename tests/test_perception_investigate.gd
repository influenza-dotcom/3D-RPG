extends GutTest

## Perception.investigate_point -- the "go LOOK at this spot" entry point (a softer alert_to that backs stealth
## body-discovery and any future distraction-noise). From UNAWARE/INVESTIGATING it forces INVESTIGATING toward
## the point and re-arms the search clock; from DETECTING/ALERTED it's a no-op (a real, seen target outranks a
## hunch). Fires just_spotted only on the UNAWARE -> aware transition. Pure state machine (no transform/tree
## reads), so it tests on a bare off-tree Perception.

func _perc() -> Perception:
	return Perception.new()

func test_from_unaware_starts_investigating_and_pings() -> void:
	var p := _perc()
	watch_signals(p)
	var spot := Vector3(3.0, 0.0, -2.0)
	p.investigate_point(spot)
	assert_eq(p.state, Perception.State.INVESTIGATING, "UNAWARE + a body/noise -> INVESTIGATING")
	assert_eq(p.last_known_position, spot, "the spot to search is recorded as last_known_position")
	assert_signal_emitted(p, "just_spotted", "first-noticed from UNAWARE fires the '!' sting")
	p.free()

func test_already_investigating_updates_spot_without_repinging() -> void:
	var p := _perc()
	p.investigate_point(Vector3(1.0, 0.0, 0.0))  # UNAWARE -> INVESTIGATING (consumes the one ping)
	watch_signals(p)
	var spot := Vector3(5.0, 0.0, 5.0)
	p.investigate_point(spot)
	assert_eq(p.state, Perception.State.INVESTIGATING, "stays INVESTIGATING")
	assert_eq(p.last_known_position, spot, "a fresher body/noise re-points the search")
	assert_signal_not_emitted(p, "just_spotted", "already aware -> no second '!' sting")
	p.free()

func test_noop_while_detecting() -> void:
	var p := _perc()
	p.state = Perception.State.DETECTING
	p.last_known_position = Vector3.ZERO
	p.investigate_point(Vector3(9.0, 0.0, 9.0))
	assert_eq(p.state, Perception.State.DETECTING, "a body can't downgrade an in-progress sighting")
	assert_eq(p.last_known_position, Vector3.ZERO, "and doesn't steer the last-known spot off the real target")
	p.free()

func test_noop_while_alerted() -> void:
	var p := _perc()
	p.state = Perception.State.ALERTED
	p.investigate_point(Vector3(9.0, 0.0, 9.0))
	assert_eq(p.state, Perception.State.ALERTED, "a locked-on enemy ignores a body on the floor")
	p.free()

func test_non_alerting_investigate_skips_the_spotted_sting() -> void:
	# A seen BODY investigates QUIETLY (alerting=false): it still goes INVESTIGATING toward the spot, but does
	# NOT fire just_spotted -- so it can't masquerade as an enemy "!" sighting or fire the combat detection
	# bark (body-discovery owns its own "Hey -- a body!" line). Noise keeps the default alerting=true sting.
	var p := _perc()
	watch_signals(p)
	var spot := Vector3(2.0, 0.0, 6.0)
	p.investigate_point(spot, false)
	assert_eq(p.state, Perception.State.INVESTIGATING, "still walks over to search the spot")
	assert_eq(p.last_known_position, spot, "still records where to search")
	assert_signal_not_emitted(p, "just_spotted", "a quiet (body) investigation must NOT fire the enemy '!' sting")
	p.free()
