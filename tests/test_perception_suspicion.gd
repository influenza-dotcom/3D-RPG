extends GutTest

## Perception.suspicion() -- the graded CALM/WARY/SUSPICIOUS/ALERTED tier from the state + detection meter, for
## HUD feedback + a future read-only planner fact. Pure: build a Perception off-tree (.new(), no _ready), set
## state/detection directly, assert the tier. (Perception is a Node3D but suspicion() only reads fields.)

func _perc() -> Perception:
	return Perception.new()

func test_unaware_is_calm() -> void:
	var p := _perc()
	p.state = Perception.State.UNAWARE
	p.detection = 0.0
	assert_eq(p.suspicion(), Perception.SuspicionTier.CALM, "oblivious -> CALM")
	p.free()

func test_alerted_state_is_alerted_tier_regardless_of_meter() -> void:
	var p := _perc()
	p.state = Perception.State.ALERTED
	p.detection = 1.0
	assert_eq(p.suspicion(), Perception.SuspicionTier.ALERTED, "locked on -> ALERTED")
	p.free()

func test_meter_buckets_calm_wary_suspicious() -> void:
	var p := _perc()
	p.state = Perception.State.DETECTING
	p.detection = 0.05  # below wary_threshold (default 0.15)
	assert_eq(p.suspicion(), Perception.SuspicionTier.CALM, "barely noticed -> still CALM")
	p.detection = 0.3   # >= 0.15, < 0.6
	assert_eq(p.suspicion(), Perception.SuspicionTier.WARY, "meter past the wary threshold -> WARY")
	p.detection = 0.7   # >= 0.6
	assert_eq(p.suspicion(), Perception.SuspicionTier.SUSPICIOUS, "meter past the suspicious threshold -> SUSPICIOUS")
	p.free()

func test_thresholds_are_honored() -> void:
	var p := _perc()
	p.state = Perception.State.INVESTIGATING
	p.suspicion_wary_threshold = 0.4
	p.suspicion_suspicious_threshold = 0.8
	p.detection = 0.3
	assert_eq(p.suspicion(), Perception.SuspicionTier.CALM, "below the raised wary threshold -> CALM")
	p.detection = 0.5
	assert_eq(p.suspicion(), Perception.SuspicionTier.WARY, "between raised thresholds -> WARY")
	p.detection = 0.9
	assert_eq(p.suspicion(), Perception.SuspicionTier.SUSPICIOUS, "above the raised suspicious threshold -> SUSPICIOUS")
	p.free()
