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


# --- NPC.suspicion_of: the HUD-facing facade (2026-08-13) -----------------------------------------------

## The third member of the awareness_of / detection_of family, added so the minimap's hostile alert ring could
## read a graded tier without reaching into the private _perception child. Built off-tree with .new() and NO
## add_child — running an NPC's _ready in a unit test instantiates weapon.tscn, nav, audio and mutates shared
## statics (the house rule).
func _bare_npc() -> Node:
	return load("res://scripts/npc/npc.gd").new()

## A bare NPC has no Perception child at all, so the facade must degrade to CALM rather than erroring — the
## same null-safety awareness_of and detection_of promise.
func test_npc_suspicion_of_is_calm_without_a_perception() -> void:
	var n := _bare_npc()
	var who := Node3D.new()
	assert_eq(n.suspicion_of(who), Perception.SuspicionTier.CALM,
		"no Perception child -> CALM, never a crash inside a HUD paint loop")
	who.free()
	n.free()

## THE TARGET GATE, which is what makes the alert ring honest: the tier is reported only for the node the NPC is
## actually tracking. Without it, a guard fighting a stray dog would ring as "they are onto YOU".
func test_npc_suspicion_of_is_target_gated() -> void:
	var n := _bare_npc()
	var me := Node3D.new()
	var someone_else := Node3D.new()
	var p := Perception.new()
	p.state = Perception.State.ALERTED
	p.detection = 1.0
	p.target = someone_else
	n._perception = p
	assert_eq(n.suspicion_of(me), Perception.SuspicionTier.CALM,
		"ALERTED on somebody ELSE reads CALM toward me")
	p.target = me
	assert_eq(n.suspicion_of(me), Perception.SuspicionTier.ALERTED,
		"...and ALERTED toward me once I am the target")
	p.free()
	someone_else.free()
	me.free()
	n.free()

## The graded middle of the ladder reaches the facade intact — the ring draws one step per tier, so WARY and
## SUSPICIOUS must not both collapse to "something".
func test_npc_suspicion_of_passes_the_graded_tiers_through() -> void:
	var n := _bare_npc()
	var me := Node3D.new()
	var p := Perception.new()
	p.state = Perception.State.DETECTING
	p.target = me
	n._perception = p
	p.detection = 0.0
	assert_eq(n.suspicion_of(me), Perception.SuspicionTier.CALM, "an empty meter is CALM")
	p.detection = 0.3
	assert_eq(n.suspicion_of(me), Perception.SuspicionTier.WARY, "a filling meter is WARY")
	p.detection = 0.9
	assert_eq(n.suspicion_of(me), Perception.SuspicionTier.SUSPICIOUS, "a nearly-full meter is SUSPICIOUS")
	p.free()
	me.free()
	n.free()
