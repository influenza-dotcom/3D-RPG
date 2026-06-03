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
	base_fov = fov
	_target_fov = base_fov

func _process(delta: float) -> void:
	# Ease the landing dip back toward rest, then compose rest + bob + dip into the
	# camera's local position. _bob_offset is updated separately in bob().
	var recovery_t := 1.0 - exp(-GameSettings.camera.recovery_speed * delta)
	_impact_offset = _impact_offset.lerp(Vector3.ZERO, recovery_t)
	position = _origin + _bob_offset + _impact_offset

	# Speed-line FOV: falling widens FOV, rising narrows it (sense of vertical
	# momentum). Normalized against the same divisor as landing impact so it scales
	# over the same velocity range.
	var vertical_norm := clampf(-player.velocity.y / GameSettings.player_movement.landing_impact_divisor, 0.0, 1.0)
	var rising_norm := clampf(player.velocity.y / GameSettings.player_movement.landing_impact_divisor, 0.0, 1.0)
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
	# COUPLING: ScopeIn.gd also assigns `fov` every frame toward the scoped FOV.
	# While ADS'd, these two writers pull toward different targets and partially
	# cancel. TODO: if ADS zoom feels weak while moving, give one system ownership
	# of `fov` (e.g. suppress this movement FOV while scoped). Behavior unchanged.
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
	bob_amount = base_amt * speed_factor
	var speed = Vector2(velocity.x, velocity.z).length() * speed_factor
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
