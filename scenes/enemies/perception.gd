class_name Perception
extends Node3D

## An enemy's senses + awareness state machine. The owner feeds it a target (the player) and
## calls sense() each frame; Perception decides what the enemy KNOWS — whether it currently
## perceives the target and how alert it is — while the owner decides what to DO about it.
##
## Vision is a range + horizontal view-cone + line-of-sight test. A detection meter fills
## while the target is perceived and drains when it isn't, so a glimpse isn't an instant
## alert; losing an ALERTED target drops the enemy into INVESTIGATING (wary at the last-known
## spot) before it finally forgets. As a child of the enemy it inherits the enemy's transform,
## so the cone points along the enemy's facing automatically. (Hearing is OR-ed into the
## perceived test in a later slice.)

enum State { UNAWARE, DETECTING, ALERTED, INVESTIGATING }

## How far the enemy can see.
@export var sight_range: float = 25.0
## Full horizontal view-cone angle (degrees); the target must be within half this off the
## enemy's forward (+Z, the model's front) to be seen.
@export var fov_degrees: float = 110.0
## Seconds of continuous perception to go from first-noticed to fully ALERTED.
@export var time_to_detect: float = 1.0
## Seconds the enemy stays wary at the last-known spot after losing the target before it
## gives up and goes UNAWARE.
@export var forget_time: float = 4.0
## Height above the enemy origin that sight rays start from (the "eyes").
@export var eye_height: float = 1.4
## Can this enemy hear the player's noise (gunfire, fast movement)? Crouch-walking is silent.
@export var hearing: bool = true

var state: State = State.UNAWARE
var detection: float = 0.0          ## 0..1 awareness meter (also drives the laser glow)
var last_known_position: Vector3
var target: Node3D                  ## the player root (set by the owner)
var target_body: Node3D             ## player's collision shape for LOS; falls back to target

var _investigate_t: float = 0.0

## One tick of sensing: refresh whether we perceive the target, then advance the state
## machine + detection meter.
func sense(delta: float) -> void:
	# Sight drives the detection meter up to a fire-ready ALERTED; hearing only ever raises a
	# look-toward-it INVESTIGATING (you can't be shot through a wall just for being heard), and
	# refreshes that wariness while the noise lasts.
	var seen := can_see()
	var heard := can_hear()
	if seen or heard:
		last_known_position = _target_point()
	match state:
		State.UNAWARE:
			if seen:
				state = State.DETECTING
			elif heard:
				state = State.INVESTIGATING
				_investigate_t = forget_time
		State.DETECTING:
			var rate := delta / maxf(time_to_detect, 0.01)
			detection = clampf(detection + (rate if seen else -rate), 0.0, 1.0)
			if detection >= 1.0:
				state = State.ALERTED
			elif detection <= 0.0:
				if heard:
					state = State.INVESTIGATING
					_investigate_t = forget_time
				else:
					state = State.UNAWARE
		State.ALERTED:
			detection = 1.0
			if not seen:
				state = State.INVESTIGATING
				_investigate_t = forget_time
		State.INVESTIGATING:
			# Seeing the target here re-enters DETECTING (the meter), NOT an instant ALERTED — so
			# a noise that drew the enemy's eye still makes it fill the detection grace before it
			# attacks. A target lost from ALERTED kept its high detection, so it re-locks fast;
			# a fresh noise-investigation starts near zero, so it has to actually spot you.
			if seen:
				state = State.DETECTING
			else:
				detection = maxf(0.0, detection - delta / maxf(forget_time, 0.01))
				_investigate_t = forget_time if heard else _investigate_t - delta
				if _investigate_t <= 0.0:
					state = State.UNAWARE
					detection = 0.0

## Force full alert toward a known position — e.g. the enemy just got shot, so it instantly
## knows roughly where you are. sense() takes over next tick: it stays ALERTED while it can
## see you, or turns to investigate the spot (so a shot in the back spins it around).
func alert_to(_position: Vector3) -> void:
	last_known_position = _position
	detection = 1.0
	state = State.ALERTED

## In range, inside the horizontal view cone, and with a clear line of sight to the target.
func can_see() -> bool:
	if not is_instance_valid(target):
		return false
	var eye := global_position + Vector3.UP * eye_height
	var tp := _target_point()
	var to_target := tp - eye
	var dist := to_target.length()
	if dist < 0.001 or dist > sight_range:
		return false
	# Horizontal cone only (vertical unbounded), so crouch height never hides you on its own.
	var flat_to := Vector3(to_target.x, 0.0, to_target.z)
	var fwd := global_transform.basis.z  # +Z is this model's front
	var flat_fwd := Vector3(fwd.x, 0.0, fwd.z)
	if flat_to.length_squared() > 0.0001 and flat_fwd.length_squared() > 0.0001:
		if rad_to_deg(flat_fwd.angle_to(flat_to)) > fov_degrees * 0.5:
			return false
	# Line of sight: nothing solid between the eyes and the target.
	var query := PhysicsRayQueryParameters3D.create(eye, tp)
	query.exclude = [get_parent()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == target

## Hearing: the player's current noise (a gunfire spike + fast movement; crouch is silent)
## reaches us within its audible radius. Ignores the cone + LOS — sound travels around things.
func can_hear() -> bool:
	if not hearing or not is_instance_valid(target):
		return false
	var nr: Variant = target.get("noise_radius")
	if nr == null:
		return false
	return global_position.distance_to(_target_point()) <= float(nr)

func _target_point() -> Vector3:
	var node: Node3D = target_body if is_instance_valid(target_body) else target
	return node.global_position if is_instance_valid(node) else global_position
