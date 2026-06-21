extends GutTest

## ML-8 DetectionStinger — the "you've been seen" one-shot. The edge+cooldown decision (_eval) is pure and
## unit-tested here; the in-tree poll (_any_npc_alerted_on_player + parent.play()) is playtest-verified per the
## repo convention (it needs real NPCs with perception + an AudioStreamPlayer parent). The NPC predicate the
## poll depends on (is_alerted_on_player) IS pinned below — it's what the review found mis-scoped.

const NPC_PATH := "res://scripts/npc/npc.gd"


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


## The predicate the stinger polls (review fix): is_alerted_on_player must distinguish a player target from an
## NPC-vs-NPC fight, so the "you've been seen" cue never fires when the player wasn't actually spotted.
func test_alerted_on_player_only_fires_for_a_player_target() -> void:
	var npc = load(NPC_PATH).new()  # off-tree: no _ready (the sanctioned NPC unit pattern)
	var perc := Perception.new()    # _perception is typed Perception — use the real node, just set its state
	perc.state = Perception.State.ALERTED
	npc._perception = perc
	var player_target := Node3D.new()
	add_child_autofree(player_target)
	player_target.add_to_group(&"Player")  # capital-P combat/identity group
	npc._target = player_target
	assert_true(npc.is_alerted_on_player(), "ALERTED on a Player-group target IS the 'you've been seen' condition")
	var npc_target := Node3D.new()  # re-target ANOTHER npc -> an NPC-vs-NPC fight
	add_child_autofree(npc_target)
	npc._target = npc_target
	assert_true(npc.is_in_combat(), "still in combat (ALERTED on a valid target)")
	assert_false(npc.is_alerted_on_player(), "an NPC-vs-NPC fight must NOT trip the player detection sting")
	npc._perception = null
	perc.free()
	npc.free()
