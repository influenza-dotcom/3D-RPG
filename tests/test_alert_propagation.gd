extends GutTest

## GA-1 alert propagation: an NPC that goes ALERTED on first-hand contact tells same-faction allies within
## alert_radius to converge + investigate the threat — so a squad reacts together, not as solo islands. The
## broadcast is latched once per engagement and routed through investigate() (which does NOT re-broadcast), so
## there's no alert storm. The live &"npc" group scan in _alert_allies is in-tree (playtested); the per-ally
## gate (should_alert_ally) is pure and pinned here, alongside the opt-in default + the latch field.

const NPC_PATH := "res://scripts/npc/npc.gd"


func _faction(id: StringName) -> Faction:
	var f := Faction.new()
	f.id = id
	return f


func test_alert_radius_defaults_off() -> void:
	var n = load(NPC_PATH).new()
	assert_eq(n.alert_radius, 0.0, "alert propagation is OFF by default (opt-in per NPC; existing encounters unchanged)")
	assert_false(n._alerted_allies, "the broadcast latch starts un-fired")
	n.free()


func test_alerts_same_faction_ally_in_range() -> void:
	var guards := _faction(&"guards")
	assert_true(NPC.should_alert_ally(guards, Vector3.ZERO, 20.0, guards, Vector3(5.0, 0.0, 0.0), true),
		"a same-faction, alive ally within radius is alerted")
	guards = null


func test_does_not_alert_out_of_range() -> void:
	var guards := _faction(&"guards")
	assert_false(NPC.should_alert_ally(guards, Vector3.ZERO, 10.0, guards, Vector3(50.0, 0.0, 0.0), true),
		"an ally beyond the radius is not alerted")
	guards = null


func test_does_not_alert_dead_ally() -> void:
	var guards := _faction(&"guards")
	assert_false(NPC.should_alert_ally(guards, Vector3.ZERO, 20.0, guards, Vector3(2.0, 0.0, 0.0), false),
		"a downed ally is not alerted")
	guards = null


func test_zero_radius_alerts_nobody() -> void:
	var guards := _faction(&"guards")
	assert_false(NPC.should_alert_ally(guards, Vector3.ZERO, 0.0, guards, Vector3(1.0, 0.0, 0.0), true),
		"radius 0 (the off default) alerts nobody")
	guards = null


func test_does_not_alert_non_allies() -> void:
	var guards := _faction(&"guards")
	var raiders := _faction(&"raiders")
	assert_false(NPC.should_alert_ally(guards, Vector3.ZERO, 50.0, raiders, Vector3(1.0, 0.0, 0.0), true),
		"a different (non-allied) faction is not alerted")
	assert_false(NPC.should_alert_ally(null, Vector3.ZERO, 50.0, null, Vector3(1.0, 0.0, 0.0), true),
		"unaligned NPCs (no faction) have no allies to alert")
	guards = null
	raiders = null
