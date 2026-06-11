extends GutTest

## AimSway (Deus Ex aim wander) + its PlayerAimSettings tuning. The wander drifts the player's true shot
## direction around the camera centre; stance steadies it (standing < moving; crouch multiplies down).
## apply() is pure rotation math, tested directly; the stance-amplitude tick runs on an off-tree player
## (velocity zero, no crouch component) so it exercises the standing path without a tree.

func test_player_aim_settings_defaults_are_sane() -> void:
	var s: PlayerAimSettings = GameSettings.player_aim
	assert_true(s is PlayerAimSettings, "GameSettings.player_aim must be a PlayerAimSettings")
	assert_gt(s.sway_moving_deg, s.sway_standing_deg,
		"moving must sway MORE than standing still — accuracy improves when planted (rule d)")
	assert_gt(s.sway_standing_deg, 0.0, "standing sway stays > 0 — the gun always wanders a little (rule b)")
	assert_gt(s.sway_crouch_mult, 0.0, "crouch steadies, never freezes (a 0 multiplier would be aimbot-still)")
	assert_lt(s.sway_crouch_mult, 1.0, "crouching must steady the wander further than standing (rule d)")
	assert_gt(s.sway_speed, 0.0, "the wander must actually drift")


func test_apply_rotates_by_the_current_offset() -> void:
	var sway := AimSway.new()
	var fwd := Vector3.FORWARD
	assert_eq(sway.apply(fwd, Basis.IDENTITY), fwd, "zero offset -> the camera ray is untouched")
	sway._offset = Vector2(0.1, 0.0)  # 0.1 rad of yaw wander
	var out: Vector3 = sway.apply(fwd, Basis.IDENTITY)
	assert_almost_eq(fwd.angle_to(out), 0.1, 0.0001,
		"the swayed direction deviates from the camera ray by exactly the wander angle")
	assert_almost_eq(out.length(), 1.0, 0.0001, "the swayed direction stays normalised")
	sway.free()


func test_standing_tick_keeps_the_wander_inside_the_standing_amplitude() -> void:
	# Off-tree player: velocity zero (standing), no crouch component -> the tick must produce an offset no
	# larger than the standing amplitude. Run a few ticks across the drift so the bound holds over time.
	var p = load("res://scripts/player/player.gd").new()
	var sway := AimSway.new()
	sway.host = p
	var bound := deg_to_rad(GameSettings.player_aim.sway_standing_deg)
	for i in 60:
		sway._physics_process(1.0 / 60.0)
		assert_lte(absf(sway._offset.x), bound + 0.0001,
			"standing still, the yaw wander never exceeds the standing amplitude")
		assert_lte(absf(sway._offset.y), bound + 0.0001,
			"standing still, the pitch wander never exceeds the standing amplitude")
	sway.free()
	p.free()
