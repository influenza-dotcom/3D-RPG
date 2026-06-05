class_name GunPose
extends Node3D

## The view-model's per-frame PROCEDURAL POSE — built in code (no .tscn) and owned by GunMesh. Split off so
## the root stays a thin coordinator: this child owns ALL the hip-fire sway / walk-bob / breathing / strafe-roll
## / aim-down-sights tuning (the exports below) and the smoothed-pose runtime state, and runs the once-per-frame
## pose solve. It WRITES the gun's transform every frame (host.position / host.rotation_degrees) on TOP of the
## one-shot recoil kick the root's fire/reload/land/holster tweens drive into host._recoil_pos/_recoil_rot — so
## those kicks ride wherever the procedural rest pose currently sits (hip OR ADS-centred).
##
## Host-coupled: GunMesh builds it in _ready (AFTER seeding base_position/base_rotation, which this child reads
## to initialise its smoothed rest pose) and sets `host` right after .new(). It READS the host's player / attack
## refs, the canonical rest pose + recoil state (base_position, base_rotation, _recoil_pos, _recoil_rot), the ADS
## flag (_aiming) + marker (aim_pos_marker), and reports the raise gate back via host.attack.gun_raised. Off-tree
## (a unit-test GunMesh built via .new() with no add_child) this child never exists, so its _process never runs —
## matching the monolith, whose _process early-returned on an invalid player and never ran without a tree anyway.

@export var sway_amount: float = 0.02
@export var sway_speed: float = 8.0

@export_group("Readiness Tilt")
# How far the muzzle droops while the weapon can't fire (cooldown/reload/swap).
@export var not_ready_pitch_deg: float = 6.0

@export_group("Idle Lower")
## After this long without firing (and not aiming), the view model sinks muzzle-down to read as "not alert".
@export var idle_lower_time: float = 4.0
## Extra muzzle droop (degrees) when idle-lowered, on top of the readiness tilt.
@export var idle_lower_pitch_deg: float = 32.0
## How far the gun sinks (metres) when idle-lowered.
@export var idle_lower_drop: float = 0.05
## Ease speed into/out of the idle-lowered pose.
@export var idle_lower_speed: float = 6.0
## While the player has been in combat within this many seconds (fired / hit / aimed at), the gun stays
## up regardless of idle_lower_time — it only droops once things have been quiet this long.
@export var idle_combat_grace: float = 5.0

@export_group("Motion")
@export var walk_bob_pos: float = 0.004
@export var walk_bob_roll_deg: float = 0.6
@export var strafe_roll_deg: float = 3.0
@export var forward_lag: float = 0.04
@export var vertical_pitch_deg: float = 1.2
@export var max_vertical_pitch_deg: float = 8.0
@export var motion_smooth: float = 10.0

@export_group("Aim Down Sights")
## Where the gun sits while aiming, relative to its resting spot. Aim in-game and nudge this until
## the sights line up with the screen centre.
@export var ads_position: Vector3 = Vector3(-0.03, -0.06, -0.01)
## Extra rotation (degrees) while aiming. Usually leave at zero.
@export var ads_rotation: Vector3 = Vector3.ZERO
## How fast the gun eases in/out of the aim pose.
@export var ads_speed: float = 14.0
## Fraction of the hip-fire sway/bob kept while aiming. 0 = rock steady, 1 = full sway.
@export var ads_sway_mult: float = 0.35

@export_group("Mouse Sway")
@export var mouse_sway_pos: float = 0.04
@export var mouse_sway_roll_deg: float = 0.0
@export var mouse_sway_pitch_deg: float = 0.0
@export var mouse_sway_decay: float = 12.0
@export var mouse_sway_max: float = 0.35

@export_group("Breathing")
@export var breath_pos_amount: float = 0.0035
@export var breath_pitch_deg: float = 0.25
@export var breath_speed: float = 1.6
@export var breath_idle_fade_speed: float = 4.0

## The GunMesh whose transform this poses — set right after .new() in GunMesh._ready. READ-only here aside
## from writing host.position / host.rotation_degrees each frame; the canonical rest + recoil state stays on it.
var host: GunMesh

var _bob_time: float = 0.0
var _breath_time: float = 0.0
var _breath_t: float = 0.0
var _mouse_sway: Vector2 = Vector2.ZERO
var _aim_t: float = 0.0      ## eased 0->1 aim-pose blend
var _idle_lower_t: float = 0.0  ## eased 0->1 idle-lowered (not-alert) blend
var _smoothed_base: Vector3              ## the swayed/aimed rest pose, smoothed
var _smoothed_base_rot: Vector3

## Seed the smoothed rest pose from the host's just-captured base pose, the moment this child enters the tree.
## GunMesh._ready sets base_position/base_rotation BEFORE building this child, exactly as the monolith seeded
## _smoothed_base = base_position right after base_position = position.
func _ready() -> void:
	_smoothed_base = host.base_position
	_smoothed_base_rot = host.base_rotation

## Accumulate a mouse-look sway impulse, clamped to mouse_sway_max — driven by the root's MouseInput.rotate
## handler (the connection stays in GunMesh.setup; the tuning + state live here).
func add_mouse_sway(amt: Vector2) -> void:
	_mouse_sway = (_mouse_sway + amt).limit_length(mouse_sway_max)

func _process(delta: float) -> void:
	var player: Character = host.player
	if !is_instance_valid(player) or !player:
		return
	var attack: Attack = host.attack

	var on_floor := player.is_on_floor()
	# Climbing counts as walking for the view-model bob: the motion is vertical while scaling a wall, so
	# stand the climb speed in for the planar speed and treat the climb itself as "grounded".
	var climber := player as Player
	var climbing := climber != null and climber.is_climbing()
	var horizontal_speed := Vector2(player.velocity.x, player.velocity.z).length()
	if climbing:
		horizontal_speed = maxf(horizontal_speed, absf(player.velocity.y))

	var bob_factor := 0.0
	# Accessibility: skip the walk-bob entirely when view bobbing is off (read live).
	if Settings.view_bob_enabled and (on_floor or climbing) and horizontal_speed > GameSettings.player_movement.footstep_min_horizontal_speed:
		_bob_time += delta * GameSettings.camera.bob_speed
		bob_factor = clampf(horizontal_speed / GameSettings.player_movement.max_speed, 0.0, 1.0)
	else:
		_bob_time = lerpf(_bob_time, 0.0, 1.0 - exp(-motion_smooth * delta))

	var bob_x := cos(_bob_time * 0.5) * walk_bob_pos * bob_factor
	var bob_y := sin(_bob_time) * walk_bob_pos * bob_factor
	var bob_roll := sin(_bob_time * 0.5) * walk_bob_roll_deg * bob_factor

	# Breathing: subtle vertical sway + pitch when standing still, fades when moving.
	var idle_target := 0.0 if (horizontal_speed > GameSettings.player_movement.footstep_min_horizontal_speed or not on_floor) else 1.0
	_breath_t = lerpf(_breath_t, idle_target, 1.0 - exp(-breath_idle_fade_speed * delta))
	_breath_time += delta * breath_speed
	var breath_y := sin(_breath_time) * breath_pos_amount * _breath_t
	var breath_pitch := sin(_breath_time * 0.5) * breath_pitch_deg * _breath_t

	_mouse_sway = _mouse_sway.lerp(Vector2.ZERO, 1.0 - exp(-mouse_sway_decay * delta))
	var mouse_off_x := -_mouse_sway.y * mouse_sway_pos
	var mouse_off_y := _mouse_sway.x * mouse_sway_pos
	var mouse_roll := -_mouse_sway.y * mouse_sway_roll_deg
	var mouse_pitch := -_mouse_sway.x * mouse_sway_pitch_deg

	var sway_x = -player.input_dir.x * sway_amount
	var sway_y = player.input_dir.y * sway_amount * 0.5
	var forward_off = -player.input_dir.y * forward_lag

	var roll = player.input_dir.x * strafe_roll_deg
	var pitch := clampf(-player.velocity.y * vertical_pitch_deg, -max_vertical_pitch_deg, max_vertical_pitch_deg)

	# Droop the muzzle while the weapon isn't ready to fire (negative X tilts the
	# barrel down, same convention as reload/land). Eased by the motion lerp below.
	var ready_pitch := -not_ready_pitch_deg if (attack and not attack.can_fire()) else 0.0

	# Aim-down-sights: ease the rest pose toward the centred aim pose, and damp the sway while
	# aiming so the gun holds steady on target.
	_aim_t = lerpf(_aim_t, 1.0 if host._aiming else 0.0, 1.0 - exp(-ads_speed * delta))
	var marker := host.aim_pos_marker
	var aim_target: Vector3 = marker.position if marker else ads_position
	var aim_pos := host.base_position.lerp(aim_target, _aim_t)
	var aim_rot := host.base_rotation.lerp(host.base_rotation + ads_rotation, _aim_t)
	var sway_damp := lerpf(1.0, ads_sway_mult, _aim_t)

	# Idle lower: after idle_lower_time without firing (and not aiming), sink the muzzle to read as "not
	# alert". Firing resets the timer (raises instantly); aiming suppresses it; and so does recent combat —
	# being shot at or aimed at auto-raises the weapon even if we haven't fired in a while.
	# player is typed Character (no seconds_since_combat); call it dynamically, guarded by has_method.
	var recent_combat: bool = player.has_method(&"seconds_since_combat") \
		and float(player.call(&"seconds_since_combat")) < idle_combat_grace
	var idle_lowered := attack != null and not host._aiming and not recent_combat and attack.seconds_since_fire() >= idle_lower_time
	_idle_lower_t = lerpf(_idle_lower_t, 1.0 if idle_lowered else 0.0, 1.0 - exp(-idle_lower_speed * delta))

	var target_pos := aim_pos + Vector3(sway_x + bob_x + mouse_off_x, sway_y + bob_y + breath_y + mouse_off_y, forward_off) * sway_damp
	var target_rot := aim_rot + Vector3(pitch + mouse_pitch + breath_pitch + ready_pitch, 0.0, roll + bob_roll + mouse_roll) * sway_damp
	# Apply the idle-lower on top (outside sway_damp so it isn't diluted): a drop + muzzle-down tilt.
	target_pos.y -= idle_lower_drop * _idle_lower_t
	target_rot.x -= idle_lower_pitch_deg * _idle_lower_t

	var t := 1.0 - exp(-motion_smooth * delta)
	# Smooth the swayed/aimed rest pose, then add the recoil kick ON TOP — so fire/reload/land kicks
	# are relative to wherever the gun is now (hip OR ADS-centred) instead of snapping to the hip.
	_smoothed_base = _smoothed_base.lerp(target_pos, t)
	_smoothed_base_rot = _smoothed_base_rot.lerp(target_rot, t)
	host.position = _smoothed_base + host._recoil_pos
	host.rotation_degrees = _smoothed_base_rot + host._recoil_rot
	# Accessibility (read live so the menu toggles apply instantly): hide the view model, and/or mirror it
	# to the LEFT hand — negate the gun's x offset + flip the mesh scale.x so the whole model mirrors over.
	host.visible = Settings.view_model_visible
	if Settings.view_model_left_handed:
		host.position.x = -host.position.x
		host.scale.x = -absf(host.scale.x)
	else:
		host.scale.x = absf(host.scale.x)
	# Tell Attack whether the gun has finished raising into view, so it won't fire mid-raise
	# (which would shoot from the still-lowered muzzle — e.g. into the floor at your feet).
	if attack:
		attack.gun_raised = host.is_raised()
