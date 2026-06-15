class_name NpcHeadLookMount
extends Node3D

## Fallout-3 / New-Vegas INDEPENDENT HEAD TRACKING. Drop ONE under an NPC's root (the Enemy node) and its
## presence gives that NPC a head that turns to face what it's attending to (its foe, a nearby player, a
## noise/corpse it's investigating) independent of the body -- smoothly, clamped to a realistic neck cone, easing
## back to neutral when nothing's in range. So heads come alive instead of the whole body swivelling as one
## lifeless block.
##
## It rotates the NPC's VISIBLE custom head -- the head_scene mesh instanced under head_node (host.head_visual()),
## NOT the buried Man.glb skeleton bone (that bone drives the placeholder head only). The head node is a plain
## Node3D the animation never touches, so rotating it composes cleanly on top of the body yaw with no clobbering.
##
## INERT unless GameSettings.npc_ai.head_look is ON (global rollout flag, default OFF -> the head sits at its rest
## pose, byte-identical to before) AND `enabled` here is true. Drop it on the shared enemy.tscn now and flip the
## global flag to playtest, like the body_discovery / hearing_initiates stealth slices. All host reads are
## duck-typed with explicit conversions (no := inference off a dynamic .* chain) and fall back to NEUTRAL.

## Per-instance master switch (e.g. a statue-still sniper). The global GameSettings.npc_ai.head_look still gates everything.
@export var enabled: bool = true
## Max distance (m) the head tracks a target; past it the head returns to neutral. A sniper can crane farther than a townsperson.
@export var look_range: float = 12.0
## Half-cone yaw clamp (deg) of head rotation relative to the body's forward -- a target past this is dropped to neutral (the body must turn first).
@export var max_yaw_deg: float = 70.0
## Half-cone pitch clamp (deg) up/down -- caps how far the head tilts to look high/low.
@export var max_pitch_deg: float = 35.0
## Exponential rate the head eases to its target angle (higher = snappier). A touch under the body turn_speed (8) reads as a gentle head lead.
@export var turn_speed: float = 6.0
## When idle (no foe / no hunch), also glance at a nearby real player in range -- the FNV "notices you" beat. Off -> the head only tracks real attention.
@export var look_at_player: bool = true
## The NPC brain (npc.gd) this reads its look target + visible head from; defaults to this node's parent (the Enemy root).
@export var host_path: NodePath = ^".."

var host: Node = null
var _head: Node3D = null         ## the visible head node we rotate (resolved lazily -- it's built in the host's _ready)
var _neutral: Basis              ## the head's rest local basis (captured once); look rotations compose onto it
var _captured: bool = false
var _cur_yaw: float = 0.0        ## smoothed head yaw offset (rad) relative to the body's forward; 0 = straight ahead
var _cur_pitch: float = 0.0      ## smoothed head pitch (rad); + = looking up

# --- pure aim math (static, off-tree-safe -> unit-tested; never touches the tree) ------------------------------

## Yaw offset + pitch (rad) for a head at `from` to look at `target`, in the BODY frame whose forward is +Z and up
## is +Y (matching _face_point's atan2(dx, dz)). `body_yaw` is the body's current world yaw, so the returned yaw is
## RELATIVE to where the body already faces (0 = dead ahead). Pitch is absolute (+ up). Pure.
static func aim_offsets(from: Vector3, target: Vector3, body_yaw: float) -> Vector2:
	var to := target - from
	var flat := maxf(Vector2(to.x, to.z).length(), 0.0001)
	var yaw_off := wrapf(atan2(to.x, to.z) - body_yaw, -PI, PI)
	var pitch := atan2(to.y, flat)
	return Vector2(yaw_off, pitch)

## True when planar `range_m` + the yaw/pitch offsets (rad) all sit inside the look cone -- otherwise the head
## would crane unnaturally and we command neutral instead. Pure.
static func in_cone(range_m: float, yaw_off: float, pitch: float, look_range: float, max_yaw: float, max_pitch: float) -> bool:
	return range_m <= look_range and absf(yaw_off) <= max_yaw and absf(pitch) <= max_pitch

## Frame-rate-independent exponential ease of `cur` toward `target` at rate `k` (the same shape as _face_yaw). Pure.
static func ease_toward(cur: float, target: float, k: float, delta: float) -> float:
	return lerpf(cur, target, 1.0 - exp(-k * delta))

# --- per-frame apply ------------------------------------------------------------------------------------------

func _ready() -> void:
	host = get_node_or_null(host_path)
	# Keep ticking through the dialogue freeze: a talking NPC goes PROCESS_MODE_DISABLED and the tree pauses once
	# the box opens, which would otherwise stop _process and leave the head frozen stiff mid-conversation. ALWAYS
	# (the same mode DialogueManager uses) lets the head stay alive and keep facing whoever it's talking to.
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	var head := _head_visual()
	if head == null:
		return
	# We run ALWAYS so dialogue doesn't freeze the head -- but a NON-dialogue pause (the pause menu) should hold
	# the head exactly where it is, not let it keep easing.
	if get_tree().paused and not DialogueManager.is_active():
		return
	if not _captured:  # the head's rest pose (the host bakes a body-aligned baseline rotation into it) is our neutral
		_neutral = head.transform.basis
		_captured = true
	var active := enabled and GameSettings.npc_ai.head_look and is_instance_valid(host)
	var want := _desired_offsets(head) if active else Vector2.ZERO
	# Inert + already at neutral -> leave the head exactly at its rest pose (parity): with the flag off from boot,
	# _cur_* are 0, so we never rotate the head at all.
	if not active and absf(_cur_yaw) < 0.0005 and absf(_cur_pitch) < 0.0005:
		return
	_cur_yaw = ease_toward(_cur_yaw, want.x, turn_speed, delta)
	_cur_pitch = ease_toward(_cur_pitch, want.y, turn_speed, delta)
	# Compose the smoothed look (yaw about up, pitch about right -- negated so + pitch looks UP) onto the neutral
	# rest pose, in the head's parent (body) space, leaving the head's position untouched. NOTE: if a playtest
	# shows the head aiming off, the yaw/pitch axis or sign here is the knob to flip (feature is flag-gated, so
	# default behaviour is unaffected).
	var t := head.transform
	t.basis = Basis(Vector3.UP, _cur_yaw) * Basis(Vector3.RIGHT, -_cur_pitch) * _neutral
	head.transform = t

## Resolve (and cache) the host's visible head node. Lazy: the head is instanced in the host's _ready, which runs
## AFTER this child's _ready, so it isn't available until the first frame.
func _head_visual() -> Node3D:
	if _head != null and is_instance_valid(_head):
		return _head
	if is_instance_valid(host) and host.has_method(&"head_visual"):
		var h: Variant = host.call(&"head_visual")
		if h is Node3D:
			_head = h
	return _head

## The clamped head yaw/pitch (rad) for the current look target, or Vector2.ZERO (neutral) when there's no valid
## in-cone target. In-tree only (reads global transforms via the host); never called off-tree.
func _desired_offsets(head: Node3D) -> Vector2:
	if not host.has_method(&"head_look_point"):
		return Vector2.ZERO
	var tp: Variant = host.call(&"head_look_point", look_at_player)
	if not (tp is Vector3):
		return Vector2.ZERO
	var point: Vector3 = tp
	var head_world := head.global_position
	var n3 := host as Node3D
	var body_yaw := n3.rotation.y if n3 != null else 0.0
	var off := aim_offsets(head_world, point, body_yaw)
	var rng := head_world.distance_to(point)  # true 3D distance, matching look_range's "distance (m)" doc
	if not in_cone(rng, off.x, off.y, look_range, deg_to_rad(max_yaw_deg), deg_to_rad(max_pitch_deg)):
		return Vector2.ZERO
	return off
