class_name CameraEffects
extends Camera3D

## First-person camera "juice": head-bob, landing dip, dynamic FOV (fall widens /
## rise narrows / forward-run kick), and strafe tilt. Pure feel — never affects
## physics. The camera sits UNDER the ScreenShake node, so shake (rotation)
## composes on top of the position/FOV effects produced here.
##
## player.gd drives it: bob(velocity) each grounded frame, land(intensity) on
## touchdown. NOTE: ScopeIn also writes `fov` each frame for ADS zoom — see the
## coupling note in the FOV block of _process.

const BOB_HORIZONTAL_RATIO: float = 0.5
const BOB_MIN_SPEED: float = 0.1

## Depth-of-field while scoped. The authored (hip-fire) far-blur distance is captured in
## _ready(); scoping pushes it out to DOF_SCOPED_FAR_DISTANCE so the scene reads crisp, or
## disables far-blur entirely when the weapon asks for it. Released on unscope.
const DOF_SCOPED_FAR_DISTANCE: float = 120.0
var _dof_default_far_distance: float = 30.0

## Volumetric fog while scoped. A weapon that disables DoF (the sniper's crisp scope) THINS the world's
## volumetric fog so the target isn't a blocky grey blob through the scope. We THIN rather than disable
## because this level has no ambient light — the fog IS the scene fill, so killing it outright went
## pitch black. Density is captured lazily on the first scope (the WorldEnvironment isn't live in
## _ready) and restored on unscope. Raise the factor for a brighter (foggier) scope, lower for clearer.
const SCOPED_FOG_DENSITY_FACTOR: float = 0.3
var _volumetric_fog_default_density: float = 0.05
var _fog_default_captured: bool = false

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
var _target_fov: float
## Transient air-dash FOV spike; eased back to zero each frame in _process.
var _fov_punch: float = 0.0
var dialogue_fov: float = 0.0  ## > 0 overrides the FOV for a distance-based dialogue zoom; 0 = off

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
	position = _origin + _bob_offset + _impact_offset

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

	# Air-dash FOV punch: decay the spike on its own rate, then layer it on top of
	# the target so the dash whooshes the view wide and eases back to normal.
	var punch_t := 1.0 - exp(-GameSettings.camera.fov_punch_decay * delta)
	_fov_punch = lerpf(_fov_punch, 0.0, punch_t)

	_target_fov = base_fov + fall_fov - rise_fov + move_fov + _fov_punch

	# Ease FOV and strafe-tilt (roll into the strafe direction) frame-rate-
	# independently.
	# COUPLING: ScopeIn.gd also assigns `fov` every frame. While NOT scoped it eases
	# toward GameSettings.camera.default_fov — the SAME value base_fov rests at — so
	# the two writers agree and no longer fight over the un-scoped rest FOV. While ADS'd
	# ScopeIn owns `fov` (pulls to the scoped FOV); this movement FOV still nudges toward
	# the wider rest and partially cancels it. TODO: if ADS zoom feels weak while moving,
	# suppress this movement FOV while scoped so ScopeIn is the sole writer there too.
	var fov_t := 1.0 - exp(-GameSettings.camera.fov_lerp_speed * delta)
	var tilt_t := 1.0 - exp(-GameSettings.camera.tilt_speed * delta)
	if dialogue_fov > 0.0:
		fov = dialogue_fov  # follow the player's dialogue-zoom tween directly (its rate = the letterbox bars')
	else:
		fov = lerpf(fov, _target_fov, fov_t)
	rotation.z = lerpf(rotation.z, -player.input_dir.x * GameSettings.camera.tilt_amount, tilt_t)


## Walk head-bob, called by player.gd ONLY while grounded. Amplitude and rate
## scale with speed (faster = bigger, quicker); below BOB_MIN_SPEED the offset is
## eased out so a still player has a still camera. Horizontal bob runs at half the
## vertical rate (figure-8 feel). This is the CAMERA bob — the gun mesh and the
## view-model hands run their own separate bob in gun_mesh.gd.
func bob(velocity: Vector3) -> void:
	var max_speed := GameSettings.player_movement.max_speed
	var speed_factor: float = player.current_speed / max_speed
	var planar := Vector2(velocity.x, velocity.z).length()
	# While climbing the motion is vertical (and current_speed isn't maintained mid-climb), so stand the
	# climb speed in for the planar speed AND the speed factor — the camera bobs as if walking up the wall.
	var climber := player as Player
	if climber != null and climber.is_climbing():
		planar = maxf(planar, absf(velocity.y))
		speed_factor = clampf(planar / max_speed, 0.0, 1.0)
	bob_amount = base_amt * speed_factor
	var speed = planar * speed_factor
	if speed < BOB_MIN_SPEED:
		var dt := get_process_delta_time()
		var t := 1.0 - exp(-GameSettings.camera.recovery_speed * dt)
		_bob_offset = _bob_offset.lerp(Vector3.ZERO, t)
		return
	_time += get_process_delta_time() * GameSettings.camera.bob_speed
	_bob_offset.y = sin(_time) * bob_amount * speed
	_bob_offset.x = cos(_time * BOB_HORIZONTAL_RATIO) * bob_amount * speed * BOB_HORIZONTAL_RATIO

## Punch the camera downward on landing; _process eases it back up. `intensity` is
## the normalized landing impact (player.gd scales it by fall speed and crouch).
func land(intensity: float = 1.0) -> void:
	_impact_offset.y -= GameSettings.camera.land_impact * intensity

## Punch the FOV way out instantly for an air-dash whoosh; _process then eases it
## back. Snaps to an ABSOLUTE wide FOV (base + punch) rather than current + punch:
## the dash fires from ADS (scoped FOV is a narrow ~40), so a relative bump would
## barely clear default. maxf() means it never narrows an already-wide fall FOV.
## The `_fov_punch` term keeps _target_fov raised while it decays so the per-frame
## ease doesn't immediately cancel it. Magnitude + recovery live in CameraSettings.
func fov_punch() -> void:
	_fov_punch = GameSettings.camera.dash_fov_punch
	fov = maxf(fov, base_fov + _fov_punch)

## Apply the depth-of-field state for the current scope/weapon combo. Called from the host's
## scope bridge (player._on_scoped_in). `scoped` = ADS active; `disable_dof` = the weapon's
## WeaponData.disable_dof_while_scoped. Three states: not scoped -> normal; scoped + keep ->
## reduced (far blur pushed out); scoped + disable -> far blur off. A disable-DoF weapon (the sniper)
## also THINS the world's volumetric fog while scoped, for a clearer scope picture.
func set_scope_dof(scoped: bool, disable_dof: bool) -> void:
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
		attrs.dof_blur_far_distance = DOF_SCOPED_FAR_DISTANCE

	# Volumetric fog rides the same "crisp scope" flag as the DoF kill: a scoped sniper THINS the fog so
	# the target reads clearly instead of as a blocky grey blob. We thin (not disable) because the level
	# has no ambient light — the fog is the scene fill, and killing it went pitch black. Captured lazily.
	var we := get_tree().get_first_node_in_group(&"world_environment") as WorldEnvironment
	if we and we.environment:
		var env := we.environment
		if not _fog_default_captured:
			_volumetric_fog_default_density = env.volumetric_fog_density
			_fog_default_captured = true
		if scoped and disable_dof:
			env.volumetric_fog_density = _volumetric_fog_default_density * SCOPED_FOG_DENSITY_FACTOR
		else:
			env.volumetric_fog_density = _volumetric_fog_default_density
	# Atmospheric dust rides the same crisp-scope flag: hide the floating motes through the scope (same
	# clear-picture intent as thinning the fog), restored on unscope or for a non-crisp ADS.
	for d in get_tree().get_nodes_in_group(&"ambient_dust"):
		if d is Node3D:
			(d as Node3D).visible = not (scoped and disable_dof)
