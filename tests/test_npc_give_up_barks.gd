extends GutTest

## C36: the give-up bark latches (_saw_combat / _was_aware / _alerted_allies) must clear at the END of every
## engagement, from the ONE shared settle helper — so a target that dies / frees mid-fight (which reaches the
## no-target branch, NOT the has-target perception-drop path) can't leave them latched and mis-fire a spurious
## "combat over" bark on the FIRST frame of the NEXT engagement. Built off-tree via load(...).new() WITHOUT _ready
## (per CLAUDE.md — _ready instantiates weapon.tscn/nav/audio and mutates statics); _voice stays null so the bark
## facades no-op, making this pure latch bookkeeping (no transforms touched -> GUT 9.6-safe).

const NPC_PATH := "res://scripts/npc/npc.gd"


func test_settle_clears_engagement_latches() -> void:
	var e = load(NPC_PATH).new()
	e._was_aware = true
	e._saw_combat = true
	e._alerted_allies = true
	e._settle_engagement_barks()  # a fighter (saw_combat) that just lost its target -> combat-over bark + full reset
	assert_false(e._saw_combat, "settle clears _saw_combat")
	assert_false(e._was_aware, "settle clears _was_aware")
	assert_false(e._alerted_allies, "settle clears _alerted_allies (re-arms the ally broadcast for the next engagement)")
	e.free()


func test_settle_is_a_noop_when_never_aware() -> void:
	# The internal `if not _was_aware: return` guard means an NPC that never noticed a threat pays nothing and fires
	# no bark — preserving the old `elif _was_aware:` gate exactly. The flags stay false (no accidental mutation).
	var e = load(NPC_PATH).new()
	e._was_aware = false
	e._saw_combat = false
	e._alerted_allies = false
	e._settle_engagement_barks()
	assert_false(e._saw_combat, "no-op when never aware: _saw_combat stays false")
	assert_false(e._was_aware, "no-op when never aware: _was_aware stays false")
	assert_false(e._alerted_allies, "no-op when never aware: _alerted_allies stays false")
	e.free()
