extends GutTest

## FOOTSTEP LOUDNESS — how far the player's own movement carries to enemy ears. NoiseEmitter.tick() writes the
## footstep channel (NoiseEmitter.footstep_radius_for) into Player.noise_radius, and enemy Perception.can_hear()
## tests its distance against exactly that scalar (raising INVESTIGATING, never a fire-ready ALERTED — hearing
## points an enemy at you, sight is what locks on).
##
## Every radius below is PRODUCED by the real footstep channel at the shipped movement speeds, then held against a
## separately-authored listener range (Perception.sight_range, Player.noise_gunfire_radius) or against the footstep
## SOUND's own gate (Landing.is_footfall_speed). tick()'s is_on_floor() gate itself is not driven: an off-tree
## Player (no _ready, per CLAUDE.md) is never on a floor, so the grounded call site stays playtested —
## test_player_jump_noise drives tick() for the airborne channels.

const PLAYER_SCRIPT_PATH := "res://scripts/player/player.gd"
const PERCEPTION_SCRIPT_PATH := "res://scripts/npc/perception.gd"

var _player = null
var _standing: Crouch = null
var _saved_cutoff: float = 0.0


func before_each() -> void:
	_saved_cutoff = GameSettings.player_movement.footstep_min_horizontal_speed
	_player = load(PLAYER_SCRIPT_PATH).new()
	_standing = Crouch.new()  # crouch_t 0 — fully upright


func after_each() -> void:
	# The cutoff lives on the shared movement .tres — a failed assert must never leave it moved for later files.
	GameSettings.player_movement.footstep_min_horizontal_speed = _saved_cutoff
	_player.free()
	_player = null
	_standing.free()
	_standing = null


## The footstep channel's radius at `speed` m/s for the shipped player's noise_move_per_speed.
func _radius_at(speed: float, crouch: Crouch = null) -> float:
	return NoiseEmitter.footstep_radius_for(speed, _player.noise_move_per_speed, crouch if crouch != null else _standing)


func _crouch_at(t: float) -> Crouch:
	var c := Crouch.new()
	c.crouch_t = t
	return c


## ⭐THE CEILING NOBODY GUESSES. Perception.can_hear() bails on `not is_instance_valid(target)`, and an NPC only
## acquires a target within sight_range (NpcTargeting's scan is a plain distance test). So an enemy further away
## than sight_range holds no target at all and hears NOTHING, however loud you are — every metre of footstep
## radius past sight_range is spent on nobody. Turning the footsteps up is only felt while this holds.
func test_a_run_is_heard_inside_the_range_an_enemy_can_even_hold_you_at() -> void:
	var perc = load(PERCEPTION_SCRIPT_PATH).new()
	var sight: float = perc.sight_range
	perc.free()
	var run := _radius_at(GameSettings.player_movement.max_speed)
	assert_gt(run, 0.0, "a full-speed run on foot must be audible at all — the footstep channel produced silence at max_speed")
	assert_lt(run, sight,
		"a full-speed run (%.1f m) must be audible from INSIDE sight_range (%.1f m), or the extra loudness reaches no one who could hear it" % [run, sight])


## The tier ladder: running is louder than walking is louder than silence, and the radius keeps climbing with speed
## all the way up — a flat or inverted curve would make sneaking at a walk buy nothing.
func test_the_movement_tiers_stay_ordered_and_audible() -> void:
	var run_speed: float = GameSettings.player_movement.max_speed
	var walk := _radius_at(run_speed * GameSettings.player_movement.walk_speed_mult)
	var run := _radius_at(run_speed)
	assert_gt(walk, 0.0, "walking is audible — only crouch and the sub-footfall creep are silent")
	assert_gt(run, walk, "a run (%.2f m) must carry further than a walk (%.2f m), or the walk tier buys nothing" % [run, walk])
	assert_lt(run, _player.noise_gunfire_radius,
		"a gunshot stays the loudest thing you can do — a run (%.1f m) must not out-carry it" % run)
	var cutoff: float = GameSettings.player_movement.footstep_min_horizontal_speed
	var last := 0.0
	for i in range(1, 11):
		var speed := lerpf(cutoff, run_speed, float(i) / 10.0)
		var r := _radius_at(speed)
		assert_gt(r, last, "footsteps must get LOUDER with every step up in speed (%.2f m/s gave %.2f m, not above %.2f m)" % [speed, r, last])
		last = r


## Crouch is the stealth tier: a full crouch is exact silence even at a run, and part-way down is part-way quiet.
func test_a_full_crouch_is_silent_and_a_half_crouch_is_quieter_than_standing() -> void:
	var run_speed: float = GameSettings.player_movement.max_speed
	var full := _crouch_at(1.0)
	var half := _crouch_at(0.5)
	var crouched := _radius_at(run_speed, full)
	var half_down := _radius_at(run_speed, half)
	full.free()
	half.free()
	var standing := _radius_at(run_speed)
	assert_eq(crouched, 0.0, "a FULL crouch must be exactly silent on the footstep channel, even at max_speed — that is the whole stealth tier")
	assert_gt(half_down, 0.0, "a half crouch is not yet silent — the cut eases in with crouch_t")
	assert_lt(half_down, standing, "a half crouch (%.2f m) must be quieter than standing at the same speed (%.2f m)" % [half_down, standing])


## ⭐ONE CUTOFF, TWO CHANNELS. The noise deadzone and the footstep SOUND's gate (Landing.is_footfall_speed, the test
## tick_footsteps plays a step on) read the same footstep_min_horizontal_speed. Give the noise its own knob and the
## two drift: a creep that makes no sound would still ring an enemy, or an audible footfall would be inaudible to
## them. Checked at the shipped cutoff AND with the knob moved, so a hardcoded copy of today's value cannot pass.
func test_the_noise_deadzone_shares_the_footstep_sound_cutoff() -> void:
	assert_gt(_saved_cutoff, 0.0,
		"the shipped cutoff must be positive, or the exponential stop-tail keeps feeding a residual radius after you halt")
	assert_eq(_radius_at(_saved_cutoff * 0.02), 0.0,
		"a stop-tail residual speed under the cutoff must write a HARD 0, not a sliver of radius that trickles out through the minimap ring")
	for cutoff in [_saved_cutoff, _saved_cutoff * 4.0 + 1.0]:
		GameSettings.player_movement.footstep_min_horizontal_speed = cutoff
		assert_eq(_radius_at(cutoff), 0.0,
			"exactly AT the %.2f m/s cutoff no footstep plays, so the noise must be silent too" % cutoff)
		assert_gt(_radius_at(cutoff + 0.01), 0.0,
			"just over the %.2f m/s cutoff a footstep plays, so an enemy must be able to hear it" % cutoff)
		for speed in [cutoff * 0.5, cutoff, cutoff + 0.01, cutoff * 2.0]:
			var heard := _radius_at(speed) > 0.0
			var stepped := Landing.is_footfall_speed(speed)
			assert_eq(heard, stepped,
				"at %.2f m/s with the cutoff at %.2f the footstep SOUND says %s but the NOISE says %s — the two channels have drifted apart" % [speed, cutoff, stepped, heard])
	GameSettings.player_movement.footstep_min_horizontal_speed = _saved_cutoff
