class_name CameraEffects
extends Camera3D

## First-person camera "juice": head-bob, landing dip, dynamic FOV (fall widens /
## rise narrows / forward-run + sprint kick), and strafe tilt. Pure feel — never affects
## physics. The camera sits UNDER the ScreenShake node, so shake (rotation)
## composes on top of the position/FOV effects produced here.
##
## player.gd drives it: bob(velocity) each grounded frame, land(intensity) on
## touchdown. NOTE: ScopeIn also writes `fov` each frame for ADS zoom — see the
## coupling note in the FOV block of _process.

# Scope DoF + fog feel tunables live in GameSettings.camera (dof_scoped_far_distance / scoped_fog_density_factor),
# as do the head-bob ratio/threshold (bob_horizontal_ratio / bob_min_speed). The vars below hold the runtime
# BASELINES captured from the live scene so unscope can restore them.
## The authored (hip-fire) far-blur distance, captured in _ready(); scoping pushes it out to
## GameSettings.camera.dof_scoped_far_distance so the scene reads crisp, then restores this on unscope.
var _dof_default_far_distance: float = 30.0
## The world's volumetric-fog density, captured lazily on the first scope (the WorldEnvironment isn't live in
## _ready). A crisp-scope weapon THINS it by GameSettings.camera.scoped_fog_density_factor so the target isn't a
## blocky grey blob; we THIN rather than disable because this level has no ambient light — the fog IS the scene
## fill, and killing it outright went pitch black. Restored on unscope.
var _volumetric_fog_default_density: float = 0.05
var _fog_default_captured: bool = false

## The player this camera belongs to; read every frame for velocity, input_dir and climb state that drive head-bob, the speed-line/forward FOV, and strafe tilt.
@export var player: Character

var base_amt: float
var bob_amount: float = GameSettings.camera.bob_amount
var base_fov: float = GameSettings.camera.default_fov

var _time: float = 0.0
## Camera's rest local position; bob + impact offsets are layered on top of it.
var _origin: Vector3
## Sinusoidal walk-bob displacement (recomputed in bob()).
var _bob_offset: Vector3
## Transient landing-dip displacement; eased back to zero each frame in _process.
var _impact_offset: Vector3
## Transient stair step-smoothing offset (metres, vertical): set by step_smooth() the frame the body auto-steps a
## riser, eased back to zero each frame in _process so the view glides to the new eye height instead of snapping.
var _step_offset: float = 0.0
var _target_fov: float
## Transient air-dash FOV spike; eased back to zero each frame in _process.
var _fov_punch: float = 0.0
var dialogue_fov: float = 0.0  ## > 0 overrides the FOV for a distance-based dialogue zoom; 0 = off
var _scope_fov_active: bool = false  ## true while ScopeIn owns camera.fov for ADS zoom

func _ready() -> void:
	base_amt = bob_amount
	_origin = position
	# base_fov stays at GameSettings.camera.default_fov — the ONE rest-FOV source of
	# truth (see the field's initializer). We deliberately do NOT capture the scene
	# node's authored `fov` here: that value (a wider editor-preview default) used to
	# overwrite base_fov, which left CameraEffects resting wide while ScopeIn pulled
	# un-scoped toward default_fov — the two fought over `fov` every un-scoped frame.
	# Both writers now agree on default_fov when not scoped (see the COUPLING note below).
	_target_fov = base_fov
	if attributes is CameraAttributesPractical:
		_dof_default_far_distance = attributes.dof_blur_far_distance

func _process(delta: float) -> void:
	# Ease the landing dip back toward rest, then compose rest + bob + dip into the
	# camera's local position. _bob_offset is updated separately in bob().
	var recovery_t := 1.0 - exp(-GameSettings.camera.recovery_speed * delta)
	_impact_offset = _impact_offset.lerp(Vector3.ZERO, recovery_t)
	# Stair step-smoothing: the body teleports up/down a riser instantly (physics needs the exact snap), so this
	# vertical offset cancels that jump on the VIEW and eases to zero, gliding the eyes to the new height instead of
	# hard-snapping. Same decaying-local-offset idiom as the landing dip above; composed into position.y below.
	var step_t := 1.0 - exp(-GameSettings.camera.step_smooth_speed * delta)
	_step_offset = lerpf(_step_offset, 0.0, step_t)
	position = _origin + _bob_offset + _impact_offset
	position.y += _step_offset

	# Speed-line FOV: falling widens FOV, rising narrows it (sense of vertical
	# momentum). Normalized against the same divisor as landing impact so it scales
	# over the same velocity range.
	# Climbing reads as WALKING, not vertical flight: zero the rise/fall (speed-line) FOV while scaling a
	# wall so climbing up doesn't narrow the view like a launch — the forward-move FOV kick below still runs.
	var climber := player as Player
	var climbing := climber != null and climber.is_climbing()
	var vertical_norm: float = 0.0 if climbing else clampf(-player.velocity.y / GameSettings.player_movement.landing_impact_divisor, 0.0, 1.0)
	var rising_norm: float = 0.0 if climbing else clampf(player.velocity.y / GameSettings.player_movement.landing_impact_divisor, 0.0, 1.0)
	var fall_fov := vertical_norm * GameSettings.camera.fall_fov_mult
	var rise_fov := rising_norm * GameSettings.camera.rise_fov_mult

	# Forward run adds a subtle FOV kick (sense of speed). input_dir.y < 0 = forward.
	var move_fov := 0.0
	if player.input_dir.y < 0:
		move_fov = -player.input_dir.y * GameSettings.camera.forward_fov_mult
	# SPRINT adds a second, flat kick ON TOP of the forward-run one above: the run kick scales with stick/key
	# push, so it can't distinguish a walk-forward from a sprint. This is all-or-nothing off the Player's
	# sprint tier (stamina-gated — is_sprinting() is false once stamina runs out), so the view snaps wider the
	# moment you actually break into a run and drops back when the sprint does.
	var sprint_fov := 0.0
	if climber != null and climber.is_sprinting():
		sprint_fov = GameSettings.camera.sprint_fov_mult

	# Air-dash FOV punch: decay the spike on its own rate, then layer it on top of
	# the target so the dash whooshes the view wide and eases back to normal.
	var punch_t := 1.0 - exp(-GameSettings.camera.fov_punch_decay * delta)
	_fov_punch = lerpf(_fov_punch, 0.0, punch_t)

	# Accessibility: "FOV Effects" off drops every COSMETIC FOV kick (fall / rise / forward-run / sprint /
	# air-dash), resting the view at base_fov. ADS / scope zoom is unaffected — ScopeIn owns `fov` while scoped.
	if not Settings.fov_effects_enabled:
		fall_fov = 0.0
		rise_fov = 0.0
		move_fov = 0.0
		sprint_fov = 0.0
		_fov_punch = 0.0
	# Clamped to Camera3D's LEGAL fov range: these kicks STACK (a sprinting fall into a dash punch layers
	# fall + run + sprint + punch on top of base_fov), and a designer tuning the *_fov_mult exports up can push
	# the sum past 179 — an out-of-range `fov` assignment errors and the view breaks. Clamping here keeps a
	# too-hot tuning value merely ugly rather than broken.
	var composed_fov := base_fov + fall_fov - rise_fov + move_fov + sprint_fov + _fov_punch
	_target_fov = clampf(composed_fov, 1.0, 179.0)

	# Ease FOV and strafe-tilt (roll into the strafe direction) frame-rate-
	# independently.
	# COUPLING: ScopeIn.gd also assigns `fov` every frame. While NOT scoped it eases
	# toward GameSettings.camera.default_fov — the SAME value base_fov rests at — so
	# the two writers agree and no longer fight over the un-scoped rest FOV. While ADS'd
	# ScopeIn owns `fov` (pulls to the scoped FOV); `_scope_fov_active` suppresses this writer while scoped.
	var fov_t := 1.0 - exp(-GameSettings.camera.fov_lerp_speed * delta)
	var tilt_t := 1.0 - exp(-GameSettings.camera.tilt_speed * delta)
	if dialogue_fov > 0.0:
		fov = dialogue_fov  # follow the player's dialogue-zoom tween directly (its rate = the letterbox bars')
	elif not _scope_fov_active:
		fov = lerpf(fov, _target_fov, fov_t)
	# Accessibility: "Camera Tilt" off stops the strafe roll — ease the view back to level instead.
	var tilt_target: float = -player.input_dir.x * GameSettings.camera.tilt_amount if Settings.camera_tilt_enabled else 0.0
	rotation.z = lerpf(rotation.z, tilt_target, tilt_t)


## Walk head-bob, called by player.gd ONLY while grounded. Amplitude and rate
## scale with speed (faster = bigger, quicker); below GameSettings.camera.bob_min_speed the offset is
## eased out so a still player has a still camera. Horizontal bob runs at half the
## vertical rate (figure-8 feel). This is the CAMERA bob — the gun and the bare fists run their own
## separate, independently-integrated bobs (GunPose._process in scripts/effects/gun_pose.gd and
## FirstPersonBody._update_fp_arm_bob), both of which advance on the RENDER delta because they run in _process.
##
## TIMEBASE CONTRACT — bob() is called from _physics_process ONLY (player.gd's ground-movement arm and
## WallClimb.tick, which the same _physics_process drives), so every integrator in here MUST use the
## PHYSICS delta. Using get_process_delta_time() here is the bug this comment exists to prevent: it
## returns the idle/render delta, so a 60 Hz physics tick advancing by a render delta scales the whole
## bob by 60/render_fps — correct at exactly 60 fps, and six times too slow at a 360 fps cap, which
## reads in-game as "the head-bob is gone" (the camera drifts once per room instead of once per step)
## while the gun/fists bobs, correctly integrated, keep their footstep cadence.
func bob(velocity: Vector3) -> void:
	# Accessibility: head-bob off -> ease any current offset out and stop (read live so the toggle applies now).
	if not Settings.view_bob_enabled:
		var off_dt := get_physics_process_delta_time()
		_bob_offset = _bob_offset.lerp(Vector3.ZERO, 1.0 - exp(-GameSettings.camera.recovery_speed * off_dt))
		return
	var max_speed := GameSettings.player_movement.max_speed
	var speed_factor: float = player.current_speed / max_speed
	var planar := Vector2(velocity.x, velocity.z).length()
	# While climbing the motion is vertical (and current_speed isn't maintained mid-climb), so stand the
	# climb speed in for the planar speed AND the speed factor — the camera bobs as if walking up the wall.
	var climber := player as Player
	if climber != null and climber.is_climbing():
		# Climb motion is VERTICAL; the wall-grip "stick" adds a constant into-wall HORIZONTAL push, so
		# driving the bob off planar speed would keep it bobbing even when held still on the wall. Use the
		# vertical climb speed alone, so a wall-hold (velocity.y == 0) reads as standing still.
		planar = absf(velocity.y)
		speed_factor = clampf(planar / max_speed, 0.0, 1.0)
	# AGILITY can push current_speed (and the actual velocity) PAST max_speed, which would grow the bob without
	# bound until the camera dips through the floor. Cap both bob inputs at the max-speed level, so a fast build
	# bobs like a brisk walk -- never deeper.
	speed_factor = clampf(speed_factor, 0.0, 1.0)
	bob_amount = base_amt * speed_factor
	var speed = minf(planar, max_speed) * speed_factor
	# NOTE: `speed` already carries speed_factor, so this compares bob_min_speed against roughly
	# current_speed^2 / max_speed, NOT the raw planar speed its tuning comment describes — the effective
	# near-still cutoff is ~0.71 m/s, not 0.1. Harmless (every real movement tier clears it) but don't
	# read the threshold as m/s of travel.
	if speed < GameSettings.camera.bob_min_speed:
		var dt := get_physics_process_delta_time()
		var t := 1.0 - exp(-GameSettings.camera.recovery_speed * dt)
		_bob_offset = _bob_offset.lerp(Vector3.ZERO, t)
		return
	_time += get_physics_process_delta_time() * GameSettings.camera.bob_speed
	_bob_offset.y = sin(_time) * bob_amount * speed
	var bob_h_ratio: float = GameSettings.camera.bob_horizontal_ratio
	_bob_offset.x = cos(_time * bob_h_ratio) * bob_amount * speed * bob_h_ratio

## Punch the camera downward on landing; _process eases it back up. `intensity` is
## the normalized landing impact (player.gd scales it by fall speed and crouch).
func land(intensity: float = 1.0) -> void:
	_impact_offset.y -= GameSettings.camera.land_impact * intensity

## Stair step-smoothing hook — player.gd calls this the frame the body auto-steps up (+) or down (−) a riser
## (see Player._try_step_up_motion / _try_step_down). `step_delta_y` is the body's INSTANT vertical jump; we shift
## the view the OPPOSITE way so the world appears NOT to move this frame, then _process eases the offset to zero so
## the eyes glide up/down to the new height instead of snapping. Accumulates + clamps (step_smooth_max) so running a
## whole staircase reads as one continuous rise, never a dip deep enough to look like a crouch or clip the floor.
## Purely cosmetic — physics has already moved the body to the correct spot.
func step_smooth(step_delta_y: float) -> void:
	var cap: float = maxf(0.0, GameSettings.camera.step_smooth_max)
	_step_offset = clampf(_step_offset - step_delta_y, -cap, cap)

## Clear the transient feel offsets (a respawn): set_process(false) during the death cinematic freezes their
## decay, so a death mid-bob / landing-dip / FOV-punch / dialogue-zoom / death-roll would otherwise EASE OUT
## of stale values over the first live frames of the new life instead of starting clean.
func reset_transients() -> void:
	_bob_offset = Vector3.ZERO
	_impact_offset = Vector3.ZERO
	_step_offset = 0.0
	_fov_punch = 0.0
	dialogue_fov = 0.0
	_scope_fov_active = false
	_target_fov = base_fov
	position = _origin
	rotation.z = 0.0
	fov = base_fov

## Punch the FOV way out instantly for an air-dash whoosh; _process then eases it
## back. Snaps to an ABSOLUTE wide FOV (base + punch) rather than current + punch:
## the dash fires from ADS (scoped FOV is a narrow ~40), so a relative bump would
## barely clear default. maxf() means it never narrows an already-wide fall FOV.
## The `_fov_punch` term keeps _target_fov raised while it decays so the per-frame
## ease doesn't immediately cancel it. Magnitude + recovery live in CameraSettings.
func fov_punch() -> void:
	if not Settings.fov_effects_enabled:
		return  # cosmetic FOV disabled (accessibility) — skip the air-dash whoosh
	_fov_punch = GameSettings.camera.dash_fov_punch
	fov = maxf(fov, base_fov + _fov_punch)

## Apply the depth-of-field state for the current scope/weapon combo. Called from the host's
## scope bridge (player._on_scoped_in). `scoped` = ADS active; `disable_dof` = the weapon's
## WeaponData.disable_dof_while_scoped. Three states: not scoped -> normal; scoped + keep ->
## reduced (far blur pushed out); scoped + disable -> far blur off. A disable-DoF weapon (the sniper)
## also THINS the world's volumetric fog while scoped, for a clearer scope picture.
func set_scope_dof(scoped: bool, disable_dof: bool) -> void:
	_scope_fov_active = scoped
	var attrs := attributes as CameraAttributesPractical
	if attrs == null:
		return
	if not scoped:
		attrs.dof_blur_far_enabled = true
		attrs.dof_blur_far_distance = _dof_default_far_distance
	elif disable_dof:
		attrs.dof_blur_far_enabled = false
	else:
		attrs.dof_blur_far_enabled = true
		attrs.dof_blur_far_distance = GameSettings.camera.dof_scoped_far_distance

	# Volumetric fog rides the same "crisp scope" flag as the DoF kill: a scoped sniper THINS the fog so
	# the target reads clearly instead of as a blocky grey blob. We thin (not disable) because the level
	# has no ambient light — the fog is the scene fill, and killing it went pitch black. Captured lazily.
	var we := get_tree().get_first_node_in_group(Groups.WORLD_ENVIRONMENT) as WorldEnvironment
	if we and we.environment:
		var env := we.environment
		if not _fog_default_captured:
			_volumetric_fog_default_density = env.volumetric_fog_density
			_fog_default_captured = true
		if scoped and disable_dof:
			env.volumetric_fog_density = _volumetric_fog_default_density * GameSettings.camera.scoped_fog_density_factor
		else:
			env.volumetric_fog_density = _volumetric_fog_default_density
	# Atmospheric dust rides the same crisp-scope flag: hide the floating motes through the scope (same
	# clear-picture intent as thinning the fog), restored on unscope or for a non-crisp ADS.
	for d in get_tree().get_nodes_in_group(Groups.AMBIENT_DUST):
		if d is Node3D:
			(d as Node3D).visible = not (scoped and disable_dof)
