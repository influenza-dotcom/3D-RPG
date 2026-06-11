extends GutTest

## The bonfire respawn loop: GameState's respawn point + the Bonfire's rest (full heal + set respawn point).
## The death -> respawn teleport itself is in-tree Player behaviour (playtested); here we pin the respawn data
## and the rest logic. The Bonfire is added IN-TREE because rest() reads its global_position/global_rotation
## (off-tree those raise a tracked engine error that GUT fails on).

const PLAYER_PATH := "res://scripts/player/player.gd"


func test_gamestate_respawn_point() -> void:
	GameState.clear()
	assert_false(GameState.has_respawn, "no respawn point on a fresh state")
	GameState.set_respawn(Vector3(1.0, 2.0, 3.0), 0.5)
	assert_true(GameState.has_respawn, "set_respawn arms the point")
	assert_eq(GameState.respawn_position, Vector3(1.0, 2.0, 3.0), "the position is stored")
	assert_almost_eq(GameState.respawn_yaw, 0.5, 0.0001, "the facing yaw is stored")
	GameState.clear()
	assert_false(GameState.has_respawn, "clear forgets the point (a fresh game)")


func test_bonfire_rest_heals_and_sets_respawn() -> void:
	GameState.clear()
	var b := Bonfire.new()
	add_child_autofree(b)  # in-tree so global_position/global_rotation are valid
	b.global_position = Vector3(5.0, 0.0, 5.0)
	var p = load(PLAYER_PATH).new()
	p.max_hp = 100.0
	p.hp = 30.0
	assert_true(b.rest(p), "resting succeeds for a player")
	assert_almost_eq(p.hp, 100.0, 0.0001, "rest fully heals HP")
	assert_true(GameState.has_respawn, "rest sets the respawn point")
	assert_eq(GameState.respawn_position, Vector3(5.0, 0.0, 5.0), "the respawn point is the bonfire's position")
	p.free()
	GameState.clear()
