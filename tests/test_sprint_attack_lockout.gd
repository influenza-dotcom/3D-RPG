extends GutTest

## "You can't shoot while sprinting." A trigger pull mid-sprint ends the sprint, keeps you off the run tier for
## PlayerMovementSettings.sprint_attack_lockout, and (for a gun) is held until the view model is back up out of
## its sprint pose. The pose itself is pinned in test_gun_pose.gd; this file pins the gameplay half on a real,
## off-tree Player (no _ready — its stamina manager exists at construction, which test_player_core relies on
## too) and a bare Attack, whose sprint_lowered mirror is set by hand exactly as GunPose sets it every frame.
## The live timing (the first round after the sprint-out, a one-frame tap still firing, sprint resuming after the
## LAST shot of a burst) is checked in game by scripts/tools/probes/__sprint_pose_probe.tscn.

const PLAYER_SCRIPT_PATH := "res://scripts/player/player.gd"


func test_interrupt_sprint_locks_sprint_out_for_the_attack_lockout() -> void:
	var p = load(PLAYER_SCRIPT_PATH).new()
	p.stamina = p.stamina_max()  # off-tree there is no _ready to fill the pool
	var lockout: float = GameSettings.player_movement.sprint_attack_lockout
	assert_gt(lockout, 0.0, "sprint_attack_lockout must be positive or an attack never stops a sprint")
	assert_true(p.can_sprint(), "a fresh player with full stamina can sprint")
	p.interrupt_sprint()
	assert_false(p.can_sprint(), "an attack must end the sprint on the spot")
	p._update_sprint_lockout(lockout - 0.01)
	assert_false(p.can_sprint(), "sprint stays unavailable for the whole sprint_attack_lockout")
	p._update_sprint_lockout(0.02)
	assert_true(p.can_sprint(), "sprint comes back once the attack lockout has run out")
	p.free()


## Both lockouts share one timer. An attack while you're already exhausted must not CUT the 3 s exhaustion
## lockout down to the short attack one.
func test_attack_lockout_never_shortens_the_exhaustion_lockout() -> void:
	var p = load(PLAYER_SCRIPT_PATH).new()
	p.stamina = p.stamina_max()  # off-tree there is no _ready to fill the pool
	p._begin_sprint_lockout()
	p.interrupt_sprint()
	assert_almost_eq(p._stamina_mgr._sprint_lockout_left, GameSettings.player_movement.stamina_sprint_lockout, 0.001,
		"an attack during the exhaustion lockout must leave the longer lockout in place")
	p.free()


## A GUN: a pull while the view model is still in its sprint pose ends the sprint AND is buffered, so it fires once
## the gun is up instead of being eaten by the semi-auto just-pressed rule.
func test_a_gun_pull_mid_sprint_is_held_and_ends_the_sprint() -> void:
	var p = load(PLAYER_SCRIPT_PATH).new()
	p.stamina = p.stamina_max()  # off-tree there is no _ready to fill the pool
	var a := Attack.new()
	var gun := WeaponData.new()
	a.character = p
	a.current_weapon = gun
	a.sprint_lowered = true
	assert_true(a._sprint_out_gate(true), "a gun pull from the sprint pose must be held, not fired")
	assert_false(p.can_sprint(), "the pull must end the sprint so the gun can come up")
	assert_ne(a._sprint_out_fire_msec, 0, "the pull must be buffered to fire once the gun is up")
	assert_true(a._sprint_out_fire_alt, "the buffer must remember which button pulled it")
	a.free()
	p.free()
	gun = null


## FISTS: no sprint pose to come up out of, so a punch swings at once — but it still ends the sprint.
func test_a_punch_mid_sprint_swings_at_once_and_still_ends_the_sprint() -> void:
	var p = load(PLAYER_SCRIPT_PATH).new()
	p.stamina = p.stamina_max()  # off-tree there is no _ready to fill the pool
	var a := Attack.new()
	var fists := WeaponData.new()
	fists.view_model_punch = true
	a.character = p
	a.current_weapon = fists
	a.sprint_lowered = true
	assert_false(a._sprint_out_gate(false), "a punch must not wait on a sprint pose the fists rig doesn't have")
	assert_false(p.can_sprint(), "a punch must still end the sprint")
	assert_eq(a._sprint_out_fire_msec, 0, "a punch that swings at once must not leave a buffered pull behind")
	a.free()
	p.free()
	fists = null


## Not sprinting and the gun is up: the gate is invisible — no lockout, nothing buffered.
func test_the_gate_does_nothing_when_not_sprinting() -> void:
	var p = load(PLAYER_SCRIPT_PATH).new()
	p.stamina = p.stamina_max()  # off-tree there is no _ready to fill the pool
	var a := Attack.new()
	var gun := WeaponData.new()
	a.character = p
	a.current_weapon = gun
	a.sprint_lowered = false
	assert_false(a._sprint_out_gate(false), "an ordinary pull (no sprint, gun up) must go straight through")
	assert_true(p.can_sprint(), "an ordinary pull must not touch the sprint lockout at the gate")
	assert_eq(a._sprint_out_fire_msec, 0, "an ordinary pull must not buffer anything")
	a.free()
	p.free()
	gun = null
