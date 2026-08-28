extends GutTest

## FOOTSTEP LOUDNESS — how far the player's own movement carries to enemy ears. NoiseEmitter.tick() turns ground
## speed into Player.noise_radius, and enemy Perception.can_hear() tests its distance against exactly that scalar
## (raising INVESTIGATING, never a fire-ready ALERTED — hearing points an enemy at you, sight is what locks on).
##
## What is pinned here is the SHAPE the tuning has to keep, not the feel:
##   • the range band — a run must out-carry a walk, must stay UNDER the enemy's sight_range (see the ⭐ below),
##     and must stay under the gunshot (a shot is the loudest thing you can do);
##   • the standing-still deadzone — the noise channel and the footstep SOUND share one cutoff, so "no footfall
##     played" and "nothing to hear" can never drift apart.
## Built off-tree via .new() (no _ready, per CLAUDE.md): these are export defaults + a source-text seam, not a
## live physics tick — the tick itself needs a floor and a real velocity, so it stays playtested.

const PLAYER_SCRIPT_PATH := "res://scripts/player/player.gd"
const PERCEPTION_SCRIPT_PATH := "res://scripts/npc/perception.gd"


## The audible radius each movement tier actually produces, from the shipped movement tuning.
func _run_radius(p) -> float:
	return GameSettings.player_movement.max_speed * p.noise_move_per_speed


func _walk_radius(p) -> float:
	return _run_radius(p) * GameSettings.player_movement.walk_speed_mult


## ⭐THE CEILING NOBODY GUESSES. Perception.can_hear() bails on `not is_instance_valid(target)`, and an NPC only
## acquires a target within sight_range (NpcTargeting's scan is a plain distance test). So an enemy further away
## than sight_range holds no target at all and hears NOTHING, however loud you are — every metre of footstep
## radius past sight_range is spent on nobody. Turning the footsteps up is only felt while this holds.
func test_a_run_is_heard_inside_the_range_an_enemy_can_even_hold_you_at() -> void:
	var p = load(PLAYER_SCRIPT_PATH).new()
	var perc = load(PERCEPTION_SCRIPT_PATH).new()
	assert_lt(_run_radius(p), perc.sight_range,
		"a full-speed run must be audible from INSIDE sight_range, or the extra loudness reaches no one who could hear it")
	p.free()
	perc.free()


## The tier ladder: running is louder than walking is louder than silence. Crouch (the 1 - crouch_t scale in
## NoiseEmitter) and the deadzone below are the two ways to reach exact silence; walking is never one of them.
func test_the_movement_tiers_stay_ordered_and_audible() -> void:
	var p = load(PLAYER_SCRIPT_PATH).new()
	assert_gt(_walk_radius(p), 0.0, "walking is audible — only crouch and the sub-footfall creep are silent")
	assert_gt(_run_radius(p), _walk_radius(p), "a run must carry further than a walk, or the walk tier buys nothing")
	assert_lt(_run_radius(p), p.noise_gunfire_radius,
		"a gunshot stays the loudest thing you can do — footsteps must not out-carry it")
	p.free()


## ⭐ONE CUTOFF, TWO CHANNELS. The noise deadzone reads footstep_min_horizontal_speed — the SAME setting that gates
## whether Landing.tick_footsteps plays a step at all. Give the noise its own knob and the two drift: a creep that
## makes no sound would still ring an enemy, or an audible footfall would be inaudible to them.
func test_the_noise_deadzone_shares_the_footstep_sound_cutoff() -> void:
	var emitter_src := FileAccess.get_file_as_string("res://scripts/player/noise_emitter.gd")
	assert_string_contains(emitter_src, "GameSettings.player_movement.footstep_min_horizontal_speed")
	var landing_src := FileAccess.get_file_as_string("res://scripts/player/landing.gd")
	assert_string_contains(landing_src, "GameSettings.player_movement.footstep_min_horizontal_speed")
	assert_gt(GameSettings.player_movement.footstep_min_horizontal_speed, 0.0,
		"the cutoff must be positive, or the exponential stop-tail keeps feeding a residual radius after you halt")
