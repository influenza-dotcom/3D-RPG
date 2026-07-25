@tool
class_name NpcHeadLookMount
extends Node3D

## Fallout-3 / New-Vegas INDEPENDENT HEAD TRACKING. Drop ONE under an NPC's root (the Enemy node) and its
## presence gives that NPC a head that turns to face what it's attending to (its foe, a nearby player, a
## noise/corpse it's investigating) independent of the body -- smoothly, clamped to a realistic neck cone, easing
## back to neutral when nothing's in range. So heads come alive instead of the whole body swivelling as one
## lifeless block.
##
## It rotates the NPC's VISIBLE custom head -- a BodyModelSwap component's swapped head (host.head_visual()),
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
## Half-cone yaw clamp (deg) of head rotation relative to the body's forward -- a target past this is dropped to
## neutral (the body must turn first). Keep it near a real neck's INDEPENDENT range (~50-60): crank it toward 90 and
## the head craning that far owl-swings the jaw / back of the skull into the collar + shoulders (the head-into-body
## clip). Tighten it and the head hands off to a body turn sooner instead of clipping.
@export var max_yaw_deg: float = 55.0
## Half-cone pitch clamp (deg) up/down -- caps how far the head tilts to look high/low. Same clip caution as the yaw:
## a big down-tilt dives the chin into the chest, so keep it modest (~25) unless neck_pivot is dialed in below.
@export var max_pitch_deg: float = 25.0
## Hinge the head turn at the base of the NECK instead of the head node's own origin — an offset (metres, in the
## head's PARENT space, i.e. below/behind the head origin) about which the look rotation pivots. WHY: the head-look
## composes its rotation onto the swapped head node, which rotates about THAT node's origin — and each head .glb
## plants its origin somewhere different (kyle's headblue sits at head_position y≈0.6; the female look at y≈0.28,
## z≈-0.2 BEHIND the face). When that origin isn't at the neck, a turn ARCS the skull into the torso/shoulders
## (the head-into-body clip) instead of pivoting on the neck. A pivot ~5-12 cm below the head origin swings the head
## like a real neck: a down-look pushes the face FORWARD off the chest rather than straight down into it. ZERO
## (default) leaves the rotation exactly about the head origin — byte-identical to before, and it doesn't touch the
## head's POSITION at all (so the dialogue talk head-bob, which writes position.y, is untouched). Per-rig knob:
## dial it in playtest (head-look is runtime-only, no editor preview); an origin that sits behind the face wants a
## positive Z to bring the pivot up under the head. The head-look stays flag-gated, so this is inert until head_look is on.
@export var neck_pivot: Vector3 = Vector3.ZERO
## Exponential rate the head eases to its target angle (higher = snappier). A touch under the body turn_speed (8) reads as a gentle head lead.
@export var turn_speed: float = 6.0
## When idle (no foe / no hunch), also glance at a nearby real player in range -- the FNV "notices you" beat. Off -> the head only tracks real attention.
@export var look_at_player: bool = true
## The NPC brain (npc.gd) this reads its look target + visible head from; defaults to this node's parent (the Enemy root).
@export var host_path: NodePath = ^".."

# The same tuning resource the GameSettings autoload preloads (Godot caches it by path, so this is the
# SAME instance, not a copy). Read directly so the editor warning can see the global gate value -- the
# GameSettings autoload node isn't instantiated in the editor, so GameSettings.npc_ai would be null here.
const _NPC_AI := preload("res://resources/tuning/NpcAiSettings.tres")

var host: Node = null
var _head: Node3D = null         ## the visible head node we rotate (resolved lazily -- it's built in the host's _ready)
var _neutral: Basis              ## the head's rest local basis (captured per head node); look rotations compose onto it
var _neutral_origin: Vector3     ## the head's rest local origin captured with _neutral — FALLBACK base for the neck_pivot hinge, used only when the head's parent offers no live head_rest_position() (see _rest_origin)
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
static func in_cone(range_m: float, yaw_off: float, pitch: float, max_range: float, max_yaw: float, max_pitch: float) -> bool:
	return range_m <= max_range and absf(yaw_off) <= max_yaw and absf(pitch) <= max_pitch

## Frame-rate-independent exponential ease of `cur` toward `target` at rate `k` (the same shape as _face_yaw). Pure.
static func ease_toward(cur: float, target: float, k: float, delta: float) -> float:
	return lerpf(cur, target, 1.0 - exp(-k * delta))

## Priority for WHAT the head should look at, given the brain's already-resolved perception facts. Extracted here
## (with the other pure head-look math) so the ordering AND the "never look at what we can't sense" gates are
## unit-testable off-tree. Returns the chosen world point, or null when nothing warrants a look (the head eases to
## neutral). The whole point is TRUTHFULNESS: the head only ever points where perception currently vouches for, so
## an NPC never telegraphs seeing you when it doesn't. Priority, high→low:
##   1. `foe_visible` — a foe we currently SEE (the brain passes true only while ALERTED, i.e. sense() confirms
##      sight this frame): aim the head at its LIVE position (`foe_point`).
##   2. `aware` — any awareness short of a live sighting (still building detection, or investigating a heard
##      noise / lost target / discovered body): look at `last_known` (the last spot we actually sensed), NOT a
##      target's true position we can no longer see.
##   3. `can_glance_player` — an idle, unaware NPC turning its head to a nearby real player it can GENUINELY see
##      (the caller has already range/cone/LOS-gated this): glance at `player_point`.
##   4. `has_radio` — a nearby playing radio this idle NPC is enjoying: `radio_point`.
## Each Vector3 is read only when its companion bool is set, so callers may pass Vector3.ZERO for an idle channel.
static func resolve_look_point(
		foe_visible: bool, foe_point: Vector3,
		aware: bool, last_known: Vector3,
		can_glance_player: bool, player_point: Vector3,
		has_radio: bool, radio_point: Vector3) -> Variant:
	if foe_visible:
		return foe_point
	if aware:
		return last_known
	if can_glance_player:
		return player_point
	if has_radio:
		return radio_point
	return null

# --- per-frame apply ------------------------------------------------------------------------------------------

func _ready() -> void:
	if Engine.is_editor_hint():
		return  # @tool: the editor only evaluates _get_configuration_warnings, never the runtime head-look
	host = get_node_or_null(host_path)
	# Keep ticking through the dialogue freeze: a talking NPC goes PROCESS_MODE_DISABLED and the tree pauses once
	# the box opens, which would otherwise stop _process and leave the head frozen stiff mid-conversation. ALWAYS
	# (the same mode DialogueManager uses) lets the head stay alive and keep facing whoever it's talking to.
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return  # @tool: never run the head-look in the editor (it reads autoloads like DialogueManager that aren't present)
	var head := _head_visual()
	if head == null:
		return
	# We run ALWAYS so dialogue doesn't freeze the head -- but a NON-dialogue pause (the pause menu) should hold
	# the head exactly where it is, not let it keep easing.
	if get_tree().paused and not DialogueManager.is_active():
		return
	if not _captured:  # the head's rest pose (the host bakes a body-aligned baseline rotation into it) is our neutral
		_neutral = head.transform.basis
		_neutral_origin = head.transform.origin  # captured too so a neck_pivot turn can rotate ABOUT the rest position
		_captured = true
	var active := enabled and GameSettings.npc_ai.head_look and is_instance_valid(host)
	# During a conversation, ONLY the NPC being talked to keeps its head-look; every other NPC eases to neutral
	# (the speaker is the NPC root we hang under, or a talkable child of it).
	if active and DialogueManager.is_active():
		var sp: Node = DialogueManager.current_speaker()
		if not (sp == host or (sp != null and host.is_ancestor_of(sp))):
			active = false
	var want := _desired_offsets(head) if active else Vector2.ZERO
	# Inert + already at neutral -> leave the head exactly at its rest pose (parity): with the flag off from boot,
	# _cur_* are 0, so we never rotate the head at all.
	if not active and absf(_cur_yaw) < 0.0005 and absf(_cur_pitch) < 0.0005:
		return
	_cur_yaw = ease_toward(_cur_yaw, want.x, turn_speed, delta)
	_cur_pitch = ease_toward(_cur_pitch, want.y, turn_speed, delta)
	# Compose the smoothed look (yaw about up, pitch about right -- negated so + pitch looks UP) onto the neutral
	# rest pose, in the head's parent (body) space. NOTE: if a playtest shows the head aiming off, the yaw/pitch
	# axis or sign here is the knob to flip (feature is flag-gated, so default behaviour is unaffected).
	var rot := Basis(Vector3.UP, _cur_yaw) * Basis(Vector3.RIGHT, -_cur_pitch)
	var t := head.transform
	t.basis = rot * _neutral
	# With neck_pivot set, HINGE the turn at the neck instead of the head node's own origin: rotate the rest origin
	# about the pivot point P = rest + neck_pivot, so origin' = P + rot*(rest - P), which simplifies to
	# rest + (neck_pivot - rot*neck_pivot). Stops the skull arcing into the torso on a big turn (see the neck_pivot
	# doc). The rest base is read LIVE each frame (_rest_origin) so the hinge follows posture — a one-shot capture
	# pinned the head at its spawn-time height across sit/stand + the seated ground-snap. ZERO -> skip the origin
	# write entirely so the head's POSITION is left exactly as it was (byte-identical to before, and it never
	# fights the dialogue talk head-bob's position.y write).
	if neck_pivot != Vector3.ZERO:
		t.origin = _rest_origin(head) + (neck_pivot - rot * neck_pivot)
	head.transform = t

## The head's CURRENT rest origin — the base the neck-pivot hinge shifts around. Read live from whatever placed
## the head (its parent's head_rest_position(): a BodyModelSwap keeps it posture-aware, so the seated drop, the
## seated ground-snap, and a stand-up all flow straight through), falling back to the one-shot _neutral_origin
## capture for a head no swap owns. Duck-typed like every host read here.
func _rest_origin(head: Node3D) -> Vector3:
	var par := head.get_parent()
	if par != null and par.has_method(&"head_rest_position"):
		var p: Variant = par.call(&"head_rest_position")
		if p is Vector3:
			return p
	return _neutral_origin

## Resolve (and cache) the host's visible head node. Lazy: the head is instanced in the host's _ready, which runs
## AFTER this child's _ready, so it isn't available until the first frame.
func _head_visual() -> Node3D:
	if _head != null and is_instance_valid(_head):
		return _head
	if is_instance_valid(host) and host.has_method(&"head_visual"):
		var h: Variant = host.call(&"head_visual")
		if h is Node3D:
			_head = h
			# A NEW head node (a pool-reuse look swap rebuilt the parts): its authored rest pose is not the old
			# node's — re-capture, or the fresh head wears the previous life's neutral basis.
			_captured = false
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
	var max_range := look_range
	if is_instance_valid(host) and host.has_method(&"head_look_max_range"):
		var host_range: Variant = host.call(&"head_look_max_range", look_range)
		if host_range is float or host_range is int:
			max_range = maxf(0.0, float(host_range))
	if not in_cone(rng, off.x, off.y, max_range, deg_to_rad(max_yaw_deg), deg_to_rad(max_pitch_deg)):
		return Vector2.ZERO
	return off

## Editor warning: this component is INERT until the right switches are on, which isn't obvious from the
## scene tree. Surfaces WHY the head won't move so a designer doesn't think it's broken. (Reads the saved
## flag straight from NpcAiSettings.tres -- see _NPC_AI -- so it's accurate without the runtime autoload.)
func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not enabled:
		warnings.append("`enabled` is off — this head won't track (per-instance master switch).")
	if not _NPC_AI.head_look:
		warnings.append("Head tracking is OFF globally (head_look in NpcAiSettings.tres) — no NPC head turns until you enable it. This component stays inert until then.")
	return warnings
