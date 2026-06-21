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


func test_weapon_recoil_bloom_defaults_are_inert() -> void:
	# A weapon with nothing authored adds no recoil/bloom, so the shipped aim feel is unchanged.
	var w := WeaponData.new()
	assert_eq(w.recoil_kick_deg, 0.0, "no vertical recoil by default")
	assert_eq(w.recoil_horizontal_deg, 0.0, "no horizontal recoil by default")
	assert_eq(w.bloom_per_shot_deg, 0.0, "no bloom per shot by default")
	assert_eq(w.bloom_max_deg, 0.0, "no bloom cap by default (bloom off)")
	assert_gt(w.recoil_recovery, 0.0, "recovery rates are positive so a set recoil/bloom can recover")
	assert_gt(w.bloom_recovery, 0.0, "bloom recovery is positive")
	w = null


func test_add_recoil_kicks_up_and_blooms() -> void:
	var sway := AimSway.new()
	var w := WeaponData.new()
	w.recoil_kick_deg = 10.0
	w.bloom_per_shot_deg = 2.0
	w.bloom_max_deg = 5.0
	sway.add_recoil(w)
	assert_almost_eq(sway._recoil.y, deg_to_rad(10.0), 0.0001, "one shot kicks the aim UP (+pitch = up)")
	assert_almost_eq(sway._bloom, 2.0, 0.0001, "one shot blooms by bloom_per_shot_deg")
	sway.add_recoil(w)
	assert_almost_eq(sway._recoil.y, deg_to_rad(20.0), 0.0001, "a second shot stacks the kick")
	assert_almost_eq(sway._bloom, 4.0, 0.0001, "bloom accumulates")
	sway.add_recoil(w)
	assert_almost_eq(sway._bloom, 5.0, 0.0001, "bloom is capped at bloom_max_deg (4+2 -> clamped to 5)")
	sway.free()
	w = null


func test_add_recoil_inert_weapon_is_a_noop() -> void:
	var sway := AimSway.new()
	var w := WeaponData.new()  # all recoil/bloom 0
	sway.add_recoil(w)
	assert_eq(sway._recoil, Vector2.ZERO, "a weapon with no recoil leaves the aim untouched")
	assert_eq(sway._bloom, 0.0, "...and no bloom")
	sway.free()
	w = null


func test_recoil_folds_into_the_offset_when_fired() -> void:
	# After a shot, the kick rides on top of the wander in the produced _offset (proves add_recoil reaches the aim).
	var p = load("res://scripts/player/player.gd").new()
	var sway := AimSway.new()
	sway.host = p
	var w := WeaponData.new()
	w.recoil_kick_deg = 30.0
	sway.add_recoil(w)
	sway._physics_process(1.0 / 60.0)
	assert_gt(sway._offset.y, 0.1, "a fired recoil kick pushes the aim UP (+pitch) well past the small standing wander")
	sway.free()
	p.free()
	w = null


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
