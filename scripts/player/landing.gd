class_name Landing
extends Node

## The two POST-MOVE ground beats, lifted off `Player._physics_process` (M13 residual — the half of the plan
## `GroundMovement` did not take). Owns exactly two things:
##   • `on_land()` — the touchdown burst: one impact number told by camera, gun, shake, HUD panel, audio, dust,
##     the Slide ability, and fall damage, so every channel reads the SAME landing.
##   • `tick_footsteps()` — the footstep cadence + its two stacking dB cuts, and the timer/interval state behind it.
##
## ⚠ It does NOT own the jump / bhop / blast-jump / slide-jump / edge-friction interleave. That stays inline on the
## Player root **in order** because those beats are byte-order-critical (a jump reads the velocity the previous beat
## wrote). Landing is safe to extract precisely because both of its beats run AFTER `apply_velocity()` and feed only
## presentation + fall damage — nothing later in the frame reads what they write.
##
## Wiring: a `Landing` child of Player.tscn with `host = NodePath("..")`, dragged onto the Player's `landing` export
## (the PlayerLightLevel / CrouchLightDouse `host` idiom). Every entry point is null-guarded so an off-tree Player
## built in a unit test (no prefab, no children) can hold one without crashing.

## The Player this drives. Wire to `..` in the scene; typed so `host.crouch` / `host.walking_sfx` resolve statically.
@export var host: Player

## Seconds until the next footstep. Counts down every physics tick; re-armed to `footstep_interval` on each step.
var _footstep_timer: float = 0.0
## Current seconds BETWEEN footsteps — recomputed each tick from the frame's `target_speed`, so the cadence quickens
## as you speed up. Public (read-only in practice) because it is the readable measure of stride rate.
var footstep_interval: float = 0.0
## The WalkingSFX node's authored `volume_db`, captured ONCE before the first step modulates it. Without the latch a
## re-capture after a crouched step would bake that step's dB cut in as the new "base" and the volume would ratchet down.
var _walking_sfx_base_db: float = 0.0
## ...and its authored `max_db`, the CEILING, latched by the same one-shot capture and for the same ratchet reason —
## the per-step cut is written onto it as well, because at this node's 80 dB base the ceiling IS the loudness you
## hear (see tick_footsteps).
var _walking_sfx_base_max_db: float = 0.0
var _base_db_captured: bool = false

func _ready() -> void:
	footstep_interval = GameSettings.player_movement.footstep_base_interval
	_capture_base_db()

## The 0..1 landing strength for a touchdown at `pre_landing_velocity` (that frame's `velocity.y`, negative while
## falling). Every channel — camera dip, gun dip, shake, HUD dip, SFX volume/pitch, dust — is scaled by this ONE
## number, which is why it is worth having in isolation. A pure static so the curve is testable without a Player.
static func impact_for(pre_landing_velocity: float) -> float:
	return clampf(-pre_landing_velocity / GameSettings.player_movement.landing_impact_divisor, 0.0, 1.0)

## Seconds between footsteps while chasing `target_speed` — INVERSELY proportional, so a sprint steps faster than a
## walk and the authored `footstep_base_interval` is the cadence at full `max_speed`. Pure static, same reason.
static func interval_for(target_speed: float) -> float:
	return GameSettings.player_movement.footstep_base_interval * (GameSettings.player_movement.max_speed / max(target_speed, 0.01))

## Latch the authored footstep volume AND ceiling. Called from `_ready` (a child's `_ready` runs before its parent's,
## and exported NodePaths are already resolved by then) and again lazily on the first tick, so an off-tree or
## late-wired host still gets a correct base instead of 0 dB.
func _capture_base_db() -> void:
	if _base_db_captured or host == null or host.walking_sfx == null:
		return
	_walking_sfx_base_db = host.walking_sfx.volume_db
	_walking_sfx_base_max_db = host.walking_sfx.max_db
	_base_db_captured = true

## TOUCHDOWN. Call on the frame `is_on_floor()` first goes true, with the velocity captured BEFORE `apply_velocity()`
## (the move zeroes `velocity.y` on contact, so the impact has to be measured from the pre-move value).
## `pre_landing_velocity` is that frame's `velocity.y` (negative while falling); `pre_velocity` the full vector the
## Slide ability needs to decide whether this was a fast enough crouched landing to slide out of.
func on_land(pre_landing_velocity: float, pre_velocity: Vector3) -> void:
	if host == null:
		return
	var impact := impact_for(pre_landing_velocity)
	# Crouching absorbs the landing: at a full crouch every PRESENTATION channel goes quiet. Fall damage and the
	# land SFX deliberately read the RAW impact instead — crouching softens how a landing looks, not how far you fell.
	var dampened_impact := impact * (1.0 - host.crouch.crouch_t) if host.crouch != null else impact
	if host.camera_effects != null:
		host.camera_effects.land(dampened_impact)
	if host.gun_mesh and impact > 0.0:
		host.gun_mesh.land(impact)
	if host.screen_shake and dampened_impact > 0.0:
		host.screen_shake.shake(dampened_impact * 1.5)
	# The HUD-weight panel dips with the same crouch-softened impact (Ui.hud_land): the camera dip is a
	# POSITIONAL offset the sway spring's rotation measurement can't see, so the landing is handed to the
	# discrete kick channel here — one event, one strength, told by camera + gun + shake + panel together.
	if host.ui and dampened_impact > 0.0:
		host.ui.hud_land(dampened_impact)
	if impact >= GameSettings.audio.land_sfx_min_impact_to_play:
		# One-shot through AudioManager (spatialized + self-freeing); volume + pitch scale with landing impact
		# off the authored bases. play_sfx no-ops on a null stream.
		# ⭐The impact cut is written onto BOTH the volume and the CEILING, and exactly one of them ever bites: the
		# spawned player outputs min(volume_db + distance attenuation, max_db), and at the 80 dB base above that is
		# ALWAYS the ceiling — so cutting volume_db alone changed nothing you could hear and a kerb landed exactly
		# as hard as a lethal fall. Cutting both leaves the hardest landing at the authored ceiling (unchanged
		# loudness) while the soft ones finally drop away, and keeps the knob correct if that 80 dB base is ever
		# brought down to a sane one — then the volume side takes over and the ceiling stops mattering.
		var land_cut := (1.0 - impact) * GameSettings.audio.land_sfx_volume_db_reduction
		var land_vol := host.land_sound_base_volume_db - land_cut
		var land_pitch := lerpf(
			host.land_sound_base_pitch + GameSettings.audio.land_sfx_pitch_spread,
			host.land_sound_base_pitch - GameSettings.audio.land_sfx_pitch_spread,
			impact
		)
		AudioManager.play_sfx(host.global_position, host.land_sound, land_vol, land_pitch,
			AudioManager.SFX_BUS, host.land_sound_max_db - land_cut)
	if impact >= GameSettings.effects.dust_land_min_impact_to_spawn:
		host.spawn_dust(GameSettings.effects.dust_land_base_intensity + impact * GameSettings.effects.dust_land_impact_bonus)
	var slide: Slide = host._slide
	if slide != null:
		slide.try_start(pre_velocity)  # begin a slide on a fast crouched landing (the Slide ability decides)
	# HP cost for a hard landing (FallDamage math, gated by the fall-immunity upgrade). pre_landing_velocity is
	# negative falling, so negate for a positive fall speed.
	host._apply_fall_damage(-pre_landing_velocity)

## FOOTSTEP CADENCE. Call every physics tick with the frame's `target_speed` (from `GroundMovement.compute_target_speed`),
## which sets the stride rate: the interval shortens as the target speed rises, so a sprint steps faster than a walk.
func tick_footsteps(delta: float, target_speed: float) -> void:
	if host == null:
		return
	_capture_base_db()
	_footstep_timer -= delta
	footstep_interval = interval_for(target_speed)
	var planar_speed := Vector2(host.velocity.x, host.velocity.z).length()
	var on_foot := host.is_on_floor() and planar_speed > GameSettings.player_movement.footstep_min_horizontal_speed
	# Climb footsteps only while actually moving up/down the wall — a wall-hold (velocity.y == 0) is silent
	# like standing still (the into-wall grip push isn't real movement, so don't count it).
	var on_climb := host.is_climbing() and absf(host.velocity.y) > GameSettings.player_movement.footstep_min_horizontal_speed
	if not (on_foot or on_climb) or host.is_sliding() or _footstep_timer > 0.0:
		return
	if host.walking_sfx == null:
		return
	# Footstep loudness = authored base minus two independent dB cuts that stack cleanly:
	#   • crouch — quieter the deeper you're crouched (quiet_footstep_db * crouch_t; full cut at full crouch).
	#   • speed  — quieter the slower you're moving. A creep at footstep_min_horizontal_speed takes the full
	#     footstep_slow_volume_db cut, easing to 0 (full loudness) by max_speed; bhop overspeed clamps at 0.
	#     Climb uses vertical speed as its "how fast am I moving" measure. This mirrors the cadence in
	#     footstep_interval above, which already quickens with speed — now loudness swells with it too.
	var move_speed := absf(host.velocity.y) if on_climb else planar_speed
	var speed_t := clampf(inverse_lerp(GameSettings.player_movement.footstep_min_horizontal_speed, GameSettings.player_movement.max_speed, move_speed), 0.0, 1.0)
	var speed_db := lerpf(GameSettings.player_movement.footstep_slow_volume_db, 0.0, speed_t)
	var crouch_db := GameSettings.player_crouch.quiet_footstep_db * host.crouch.crouch_t if host.crouch != null else 0.0
	# ⭐The stacked cut goes onto the CEILING as well as the volume, and only one of them ever bites. An
	# AudioStreamPlayer3D outputs min(volume_db + distance attenuation, max_db), and the attenuation is POSITIVE
	# inside unit_size (~+20 dB at the ~1 m from the listener to your own feet) — so WalkingSFX's authored 80 dB
	# base sums to ~100 and every step was pinned to the ceiling: BOTH knobs above were dead on arrival and a
	# crouch-creep was exactly as loud as a sprint. Cutting the ceiling too leaves the loudest step at the
	# authored max_db (unchanged — the mix is not being re-balanced here) and lets the cuts be heard; the volume
	# write stays so the knobs keep working the ordinary way if that 80 dB base is ever brought down to a sane
	# one. Both are latched bases, never the live values, or a crouched step would ratchet the next one quieter.
	host.walking_sfx.volume_db = _walking_sfx_base_db + crouch_db + speed_db
	host.walking_sfx.max_db = _walking_sfx_base_max_db + crouch_db + speed_db
	host.walking_sfx.play()
	_footstep_timer = footstep_interval
