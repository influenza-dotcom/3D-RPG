extends GutTest

## ML-8 DetectionStinger — the "you've been seen" one-shot. The edge+cooldown decision (_eval) is pure and
## unit-tested here; the in-tree poll (_any_npc_alerted_on_player + parent.play()) is playtest-verified per the
## repo convention (it needs real NPCs with perception + an AudioStreamPlayer parent).


func test_default_cooldown_positive() -> void:
	var s := DetectionStinger.new()
	assert_gt(s.cooldown, 0.0, "cooldown defaults positive so a flickering detection can't spam the sting")
	s.free()


func test_stings_on_rising_edge() -> void:
	var s := DetectionStinger.new()
	assert_false(s._eval(false), "no detection -> no sting")
	assert_true(s._eval(true), "the first detection (rising edge) stings")
	s.free()


func test_sustained_detection_stings_once() -> void:
	var s := DetectionStinger.new()
	assert_true(s._eval(true), "first detection stings")
	assert_false(s._eval(true), "a SUSTAINED detection does not re-sting (no new rising edge)")
	assert_false(s._eval(true), "...still silent while continuously detected")
	s.free()


func test_rearms_after_disengage_but_cooldown_blocks_immediate_resting() -> void:
	var s := DetectionStinger.new()
	s.cooldown = 5.0
	assert_true(s._eval(true), "first detection stings and arms the cooldown")
	assert_false(s._eval(false), "all NPCs disengage — re-arms the edge, no sting")
	# A fresh detection arrives while the cooldown is still running -> suppressed.
	assert_false(s._eval(true), "a re-detection within the cooldown window is suppressed (anti-flicker)")
	s.free()


func test_restings_after_cooldown_elapses() -> void:
	var s := DetectionStinger.new()
	s.cooldown = 5.0
	assert_true(s._eval(true), "first detection stings")
	s._eval(false)            # disengage -> re-arm the edge
	s._cooldown_t = 0.0       # simulate the cooldown having elapsed
	assert_true(s._eval(true), "a fresh detection after the cooldown stings again")
	s.free()
