extends GutTest

## Contract for "enemies stop attacking you once you actually die": a DOWNED character must never be a valid
## combat target. The player is the reason this exists — on death it stays in the tree through its death
## sequence + in-place checkpoint revive (Character._dead latched, hp 0) instead of freeing like an NPC, so an
## enemy would otherwise keep firing at the frozen corpse. Pure logic (Character.is_alive + the static
## NpcTargeting._is_live gate), built off-tree with load().new() WITHOUT add_child so _ready never runs.

const CHARACTER_PATH := "res://scripts/player/character.gd"


func _character(hp: float, dead: bool):
	# hp is only seeded from max_hp in _ready (which we deliberately don't run off-tree), so stamp it by hand.
	var c = load(CHARACTER_PATH).new()
	c.hp = hp
	c._dead = dead
	return c


func test_is_alive_reflects_death_latch_and_hp() -> void:
	var alive = _character(5.0, false)
	assert_true(alive.is_alive(), "a character with HP and no death-latch is alive")
	alive.free()

	var latched = _character(5.0, true)
	assert_false(latched.is_alive(), "the _dead latch alone makes a character not-alive even with HP left on the frozen corpse")
	latched.free()

	var bled_out = _character(0.0, false)
	assert_false(bled_out.is_alive(), "0 HP is not alive")
	bled_out.free()


func test_targeting_drops_a_dead_character_but_keeps_a_live_one() -> void:
	var live = _character(5.0, false)
	assert_true(NpcTargeting._is_live(live), "a live character is a valid target")
	live.free()

	var dead = _character(5.0, true)
	assert_false(NpcTargeting._is_live(dead), "a DEAD character is dropped as a target — enemies stop shooting the corpse")
	dead.free()


func test_is_live_treats_a_non_character_as_live() -> void:
	# test_hostility puts a bare Node3D in the &"Player" group; a non-Character can't be 'dead', so the liveness
	# gate must not drop it (it stays a valid target exactly as before this change).
	var stub := Node3D.new()
	assert_true(NpcTargeting._is_live(stub), "a non-Character node can't be dead -> stays a valid target")
	stub.free()


func test_is_live_rejects_a_freed_instance() -> void:
	var freed = _character(5.0, false)
	freed.free()
	assert_false(NpcTargeting._is_live(freed), "a freed instance is not a valid target (is_instance_valid guard runs first)")
