extends GutTest

## JUMP + LANDING LOUDNESS — the impact channel of the player's stealth noise. NoiseEmitter.jump() / .land()
## arm a decaying spike that tick() folds into Player.noise_radius alongside the gunfire spike and the
## ground-speed footstep noise (loudest wins), which is the scalar enemy Perception.can_hear() tests against and
## the &"noise" group scan investigates.
##
## This channel exists to close a specific hole: the footstep channel is gated on is_on_floor(), so before it a
## player who left the ground was PERFECTLY SILENT — a bunny-hop chain past a guard, or a drop from a roof into a
## room, cost nothing. What is pinned here is the SHAPE that has to keep holding, not the feel:
##   • the band — a routine hop must out-carry a walk, and even a terminal drop must stay under the gunshot;
##   • the kerb gate — the noise and the landing SOUND share one cutoff, so "a thump played" and "an NPC heard a
##     thump" can never drift apart (the same house rule as the footstep deadzone in test_player_footstep_noise);
##   • ⭐the HOLD vs the NPC scan interval — the one property whose failure is invisible in a playtest.
## Built off-tree via .new() (no _ready, per CLAUDE.md). tick() is safe off-tree: is_on_floor() is false, so the
## footstep branch (which would need host.crouch) is skipped, and the live NoiseSource is only created in-tree.

const PLAYER_SCRIPT_PATH := "res://scripts/player/player.gd"
const NOISE_EMITTER_SCRIPT_PATH := "res://scripts/player/noise_emitter.gd"
const LANDING_SCRIPT_PATH := "res://scripts/player/landing.gd"


func _emitter(p) -> Node:
	var e = load(NOISE_EMITTER_SCRIPT_PATH).new()
	e.host = p
	return e


## The landing impact a plain flat-ground jump actually produces, from the SHIPPED movement tuning — rise under
## normal gravity to the apex, fall back under fall_gravity_mult, and score it through the real Landing.impact_for.
## Derived rather than hardcoded so re-tuning the jump moves this test's expectations with it.
func _flat_jump_impact() -> float:
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var apex := pow(GameSettings.player_movement.jump_velocity, 2.0) / (2.0 * g)
	var land_speed := sqrt(2.0 * g * GameSettings.player_movement.fall_gravity_mult * apex)
	return load(LANDING_SCRIPT_PATH).impact_for(-land_speed)


func _walk_radius(p) -> float:
	return GameSettings.player_movement.max_speed * GameSettings.player_movement.walk_speed_mult * p.noise_move_per_speed


## The whole point of the feature: leaving the ground is no longer free. A jump and the landing that ends it both
## write a positive radius while airborne — the state in which the footstep channel is gated to exact silence.
func test_jumping_and_landing_are_audible_at_all() -> void:
	var p = load(PLAYER_SCRIPT_PATH).new()
	var e = _emitter(p)
	assert_eq(p.noise_radius, 0.0, "a fresh player is silent before anything happens")
	e.jump()
	e.tick(1.0 / 60.0)
	assert_gt(p.noise_radius, 0.0, "a jump must be heard — the footstep channel is gated on is_on_floor(), so without this an airborne player is perfectly silent")
	var jumped: float = p.noise_radius
	e.free()
	var e2 = _emitter(p)
	p.noise_radius = 0.0
	e2.land(1.0)
	e2.tick(1.0 / 60.0)
	assert_gt(p.noise_radius, jumped, "a full-strength landing must out-carry the push-off that started it — the fall is the part that gives you away")
	e2.free()
	p.free()


## THE BAND. A routine hop has to be louder than the quiet walk tier or the channel changes nothing you would
## notice; a terminal drop has to stay under the gunshot, which is this game's ceiling for "the loudest thing you
## can do" (the same invariant test_player_footstep_noise pins for a run).
func test_the_impact_band_sits_between_a_walk_and_a_gunshot() -> void:
	var p = load(PLAYER_SCRIPT_PATH).new()
	var e = _emitter(p)
	e.land(_flat_jump_impact())
	e.tick(1.0 / 60.0)
	var hop: float = p.noise_radius
	assert_gt(hop, _walk_radius(p), "landing a flat jump must carry further than strolling — a hop is a heavier sound than a footfall, and if it is not the loudest-wins fold hides this channel behind the walk you were already making")
	var e2 = _emitter(p)
	e2.land(1.0)
	e2.tick(1.0 / 60.0)
	assert_gt(p.noise_radius, hop, "a long drop must out-carry a flat hop, or height costs the player nothing")
	assert_lt(p.noise_radius, p.noise_gunfire_radius, "a gunshot stays the loudest thing you can do — falling off a roof must not out-carry it")
	e.free()
	e2.free()
	p.free()


## ⭐ONE CUTOFF, TWO CHANNELS — the footstep deadzone rule applied to the touchdown. Under
## land_sfx_min_impact_to_play no landing thump PLAYS, so there must be nothing for an enemy to hear; give the
## noise its own threshold and the two drift, and stepping off a kerb starts silently ringing guards.
func test_a_landing_too_soft_to_thump_is_also_too_soft_to_hear() -> void:
	var p = load(PLAYER_SCRIPT_PATH).new()
	var e = _emitter(p)
	var cutoff: float = GameSettings.audio.land_sfx_min_impact_to_play
	assert_gt(cutoff, 0.0, "the cutoff must be positive, or every micro-contact with the floor rings the noise channel")
	e.land(cutoff * 0.5)
	e.tick(1.0 / 60.0)
	assert_eq(p.noise_radius, 0.0, "a step-down too soft to play the land SFX must make no noise either")
	e.land(cutoff)
	e.tick(1.0 / 60.0)
	assert_gt(p.noise_radius, 0.0, "at the cutoff the thump plays, so it must also be heard")
	e.free()
	p.free()


func test_the_landing_gate_shares_the_land_sfx_cutoff() -> void:
	var emitter_src := FileAccess.get_file_as_string(NOISE_EMITTER_SCRIPT_PATH)
	assert_string_contains(emitter_src, "GameSettings.audio.land_sfx_min_impact_to_play")
	var landing_src := FileAccess.get_file_as_string(LANDING_SCRIPT_PATH)
	assert_string_contains(landing_src, "GameSettings.audio.land_sfx_min_impact_to_play")


## ⭐THE PROPERTY WHOSE FAILURE IS INVISIBLE. An idle NPC only walks the &"noise" group every
## distraction_scan_interval seconds (NpcDistraction.scan_distractions). A spike that decays away inside one scan
## window can expire UNHEARD by every not-yet-targeting NPC — while a hostile already holding the player as a
## target still hears it, because Perception.can_hear() runs every frame. So the feature keeps looking half-alive
## instead of breaking outright. The full-radius hold is what makes the guarantee independent of the radii.
func test_the_impact_hold_outlasts_an_npcs_noise_scan_window() -> void:
	var p = load(PLAYER_SCRIPT_PATH).new()
	assert_gt(p.noise_impact_hold, GameSettings.npc_ai.distraction_scan_interval,
		"the jump/landing spike must hold full radius for longer than an idle NPC's scan interval, or a spike can fall entirely between two scans and be heard by nobody who has not already noticed you")
	p.free()


## ...and the hold actually holds: the QUIETEST impact event (a bare jump) is still at full radius after a whole
## scan window has passed. Pinning the behaviour as well as the numbers, because the hold is what a future
## re-tune of the radii is most likely to quietly undo.
func test_the_quietest_impact_survives_a_whole_scan_window_at_full_radius() -> void:
	var p = load(PLAYER_SCRIPT_PATH).new()
	var e = _emitter(p)
	e.jump()
	var step := 1.0 / 60.0
	var elapsed := 0.0
	while elapsed < GameSettings.npc_ai.distraction_scan_interval:
		e.tick(step)
		elapsed += step
	assert_almost_eq(p.noise_radius, p.noise_jump_radius, 0.001,
		"a jump must still be at full radius one scan interval later — the hold is the whole reason an idle NPC cannot miss it")
	# ...and it does eventually go quiet, or the player would ring forever after one hop.
	for _i in range(600):
		e.tick(step)
	assert_eq(p.noise_radius, 0.0, "the spike must decay back to exact silence — a residual radius would pin the player audible (and the minimap noise ring open) forever")
	e.free()
	p.free()


## A bunny-hop lands and jumps a frame or two apart. The spike takes the LOUDEST of the overlapping events, never
## the latest: without that, the quiet push-off would cut the loud touchdown thud short and chaining hops would be
## QUIETER than a single one — exactly backwards.
func test_a_jump_right_after_a_landing_cannot_cut_the_thud_short() -> void:
	var p = load(PLAYER_SCRIPT_PATH).new()
	var e = _emitter(p)
	e.land(1.0)
	e.tick(1.0 / 60.0)
	var thud: float = p.noise_radius
	e.jump()  # the very next hop in a bhop chain — quieter than the landing it follows
	e.tick(1.0 / 60.0)
	assert_almost_eq(p.noise_radius, thud, 0.001, "hopping straight out of a hard landing must not make you quieter than standing in it")
	assert_gt(p.noise_radius, p.noise_jump_radius, "the louder landing still owns the channel, not the jump that overwrote nothing")
	e.free()
	p.free()


## ⭐A DEAD PLAYER MUST GO QUIET, and this channel is what made that reachable. `Player.die()` ends with
## `set_physics_process(false)`, so `tick()` stops and whatever radius was last written stays FROZEN on
## `noise_radius` and on the live `NoiseSource` — permanently. A fall death is the routine case: `_apply_fall_damage`
## is called from `Landing.on_land`, so the landing thud is armed at full radius on the exact frame we die, and
## without `silence()` every death-by-falling leaves a ~25 m siren standing at the body.
func test_going_silent_clears_every_channel_at_once() -> void:
	var p = load(PLAYER_SCRIPT_PATH).new()
	var e = _emitter(p)
	e.gunfire()
	e.land(1.0)
	e.tick(1.0 / 60.0)
	assert_gt(p.noise_radius, 0.0, "precondition: the player is loudly audible before dying")
	e.silence()
	assert_eq(p.noise_radius, 0.0, "death must zero the radius outright — tick() will not run again to decay it")
	# ...and it must STAY zero. tick() derives noise_radius from the spike values, so clearing only the host
	# scalar would let the very next tick (a revive, a stray beat) resurrect the pre-death radius.
	e.tick(1.0 / 60.0)
	assert_eq(p.noise_radius, 0.0, "a tick after going silent must not resurrect the spike — silence has to clear the channels themselves, not just the scalar tick() writes from them")
	e.free()
	p.free()


func test_die_actually_calls_silence() -> void:
	var player_src := FileAccess.get_file_as_string(PLAYER_SCRIPT_PATH)
	assert_string_contains(player_src, "_noise.silence()")


## The impact channel must never SHRINK what an enemy hears: it is folded in with maxf against the gunfire spike
## and the footstep noise. A landing thud mid-firefight is swallowed by the shot, which is why a quiet event here
## is free — the channel only changes anything when you were otherwise silent.
func test_a_landing_never_quietens_a_louder_gunshot() -> void:
	var p = load(PLAYER_SCRIPT_PATH).new()
	var e = _emitter(p)
	e.land(0.2)
	e.tick(1.0 / 60.0)
	var land_only: float = p.noise_radius
	e.free()
	var e2 = _emitter(p)
	e2.gunfire()
	e2.land(0.2)
	e2.tick(1.0 / 60.0)
	assert_gt(p.noise_radius, land_only,
		"a soft landing during a gunshot must not pull the radius down to the landing's — the channels are a loudest-wins max, not a replace")
	e2.free()
	p.free()
