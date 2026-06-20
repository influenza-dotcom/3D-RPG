extends GutTest

## Drop-in AlarmPanel (GA-3): trip it -> reinforcement wave (EncounterSpawner) + faction-wide aggro + klaxon,
## ONE-SHOT. The risk it guards is reputation MULTIPLICATION — flipping a whole squad hostile must drop the
## faction standing ONCE, not once per member. That mitigation lives in aggro_faction_members (members are
## provoked with apply_rep=false; the panel applies the single penalty itself), pinned here with stubs. The full
## in-tree trip() (spawner + the live &"npc" scan + the single Reputation hit) is playtested.

const ALARM_PATH := "res://scripts/components/alarm_panel.gd"


## A minimal faction-member stand-in: just the duck-typed surface aggro_faction_members reads (a `faction` and
## a provoke(attacker, apply_rep) that records the flag) — so we test the aggro without a real NPC's heavy _ready.
class StubMember extends Node:
	var faction: Faction
	var provoked: bool = false
	var last_apply_rep = null
	func provoke(_attacker = null, apply_rep: bool = true) -> void:
		provoked = true
		last_apply_rep = apply_rep


func _faction(id: StringName) -> Faction:
	var f := Faction.new()
	f.id = id
	return f


func test_defaults_are_inert() -> void:
	var a = load(ALARM_PATH).new()
	assert_eq(a.alarm_faction_id, "", "no faction aggro until a designer picks one")
	assert_false(a.has_tripped(), "starts un-tripped")
	a.free()


func test_trip_latches_one_shot() -> void:
	# With no faction + no spawner, trip() just flips the one-shot latch (no real NPC / spawner needed).
	var a = load(ALARM_PATH).new()
	add_child_autofree(a)
	a.trip()
	assert_true(a.has_tripped(), "the alarm reads tripped after the first trip")


func test_aggro_members_flips_matching_faction_once_without_rep() -> void:
	# The GA-3 mitigation: each member is provoked WITHOUT re-dropping rep (the panel applies the penalty once),
	# and only the alarm faction's members are touched.
	var guards := _faction(&"guards")
	var raiders := _faction(&"raiders")
	var g1 := StubMember.new()
	g1.faction = guards
	var g2 := StubMember.new()
	g2.faction = guards
	var r1 := StubMember.new()
	r1.faction = raiders
	var n: int = AlarmPanel.aggro_faction_members([g1, g2, r1, null], guards, null)
	assert_eq(n, 2, "both guards flipped, the raider + the null skipped")
	assert_true(g1.provoked and g2.provoked, "every alarm-faction member goes hostile")
	assert_false(r1.provoked, "a different faction is untouched")
	assert_eq(g1.last_apply_rep, false, "members are aggroed WITHOUT re-dropping rep (no per-NPC multiplication)")
	assert_eq(g2.last_apply_rep, false, "...the second member too")
	g1.free()
	g2.free()
	r1.free()
	guards = null
	raiders = null


func test_aggro_members_null_faction_is_noop() -> void:
	var m := StubMember.new()
	m.faction = _faction(&"guards")
	assert_eq(AlarmPanel.aggro_faction_members([m], null, null), 0, "no alarm faction -> nobody is aggroed")
	assert_false(m.provoked, "the member is left alone")
	m.free()
