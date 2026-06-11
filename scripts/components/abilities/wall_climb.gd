class_name WallClimb
extends Ability

## WALL CLIMB ability — drop under a Player to grant it. Walk into a wall + hold jump to grip it: push INTO the
## wall to climb up, hold S to climb down, strafe/idle to hang in place; release jump to let go. Climbing clean
## off the top pops you onto the ledge. The Player calls tick() once per physics frame at the climb beat (after
## the main movement build, before the move) and reads is_climbing() for the camera/view-model/footstep cues.
##
## Owns its own tuning (these used to live on the Player as exports — re-tune them HERE on the node now). Defaults
## match the Player's old values, so a node added with no overrides climbs exactly as before.

## Vertical speed (m/s) while scaling a wall.
@export var wall_climb_speed: float = 4.5
## Into-wall press (m/s) applied while gripping so contact (is_on_wall) holds and you can hang still instead of
## peeling off. Absorbed by the wall, so it adds no visible movement.
@export var wall_grip_stick: float = 2.0
## Upward pop when you clear the top of a climb (land on the ledge).
@export var climb_hop_up: float = 5.0
## Forward nudge paired with the top-of-climb hop.
@export var climb_hop_forward: float = 3.5

var _climbing: bool = false  ## true only while actually gripping a wall this frame

func ability_id() -> StringName:
	return &"wall_climb"

## True while scaling a wall — the camera widens its pitch clamp, the view model runs the walk-bob, and climb
## footsteps play off this. Disabled / un-gripped → false.
func is_climbing() -> bool:
	return enabled and _climbing

## One physics frame of wall-climb, called by the Player in place of the old inline climb block (same spot in the
## step, same operations). `direction` is the player's world-space move direction this frame. Mutates host
## velocity through a local (host.velocity is a value copy) so the read-modify-write actually lands on the body.
func tick(direction: Vector3) -> void:
	var was_climbing := _climbing
	_climbing = false
	# Disabled = the whole ability is off: this return precedes BOTH the climb branch and the top-of-climb hop
	# elif below, and every velocity write, so a disabled WallClimb does nothing but keep _climbing false.
	if not enabled:
		return
	var jump_held := Input.is_action_pressed(&"jump")
	if host.is_on_wall() and jump_held and not host.is_encumbered():
		var wall_n: Vector3 = host.get_wall_normal()
		var input_dir: Vector2 = host.input_dir
		var pushing_in := direction.dot(-wall_n) > 0.1
		# Only START a grip by pushing in, so brushing a wall while holding jump doesn't stick you.
		if pushing_in or was_climbing:
			_climbing = true
			var v: Vector3 = host.velocity
			v -= wall_n * maxf(v.dot(wall_n), 0.0)  # don't peel off (kill outward velocity)
			v -= wall_n * wall_grip_stick            # press in a touch so we stay stuck
			# Vertical control keys off FORWARD/BACK input ONLY, so strafing along the wall never makes you rise:
			# W into the wall climbs up, S climbs down, strafe-only / idle holds.
			if pushing_in and input_dir.y < 0.0:
				v.y = wall_climb_speed
			elif input_dir.y > 0.0:
				v.y = -wall_climb_speed
			else:
				v.y = 0.0
			host.velocity = v
			host.camera_effects.bob(v)  # treat the climb as walking — bob the camera (bob() reads is_climbing)
	elif was_climbing and jump_held and not host.is_encumbered():
		# Climbed clean off the top — little hop to pop over the lip and land on the ledge.
		var v: Vector3 = host.velocity
		v.y = maxf(v.y, climb_hop_up)
		v += direction * climb_hop_forward
		host.velocity = v
		if host.jump_sfx:
			host.jump_sfx.play()
