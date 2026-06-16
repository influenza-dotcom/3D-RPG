@tool
class_name BodyModelSwap
extends Node3D

## Drop-in CUSTOM CHARACTER swap with a LIVE EDITOR PREVIEW. Set body_model + head_model to your .glb files and
## they appear in place of the NPC's default Man.glb body + head RIGHT IN THE EDITOR (@tool) -- both at FULL SCALE
## in the SAME frame (under this node), so you tune their size / position / rotation and watch the head sit on the
## torso in real time, no playtest. It hides the Man.glb's own meshes (the Skeleton3D + "Head" bone stay), and at
## runtime the NPC's head-look + sniper glint retarget to the swapped head.
##
## SETUP: drop it under the NPC (the Enemy root). Set body_model (+ optionally head_model). If you use head_model,
## CLEAR the NPC's own head_scene -- this component owns the head then. Dial *_scale / *_position / *_rotation
## until it lines up. The same node does the swap at runtime, so what you see in the editor is what ships.

# --- Body --------------------------------------------------------------------------------------------------------
## Tick this any time the editor preview looks stale (after a .glb reimport or a script reload) to force a rebuild.
@export var refresh_preview: bool = false:
	set(value):
		refresh_preview = false  # momentary: snaps back so it always re-triggers
		_rebuild()
@export var body_model: PackedScene:
	set(value):
		body_model = value
		_rebuild()
## Uniform scale of the swapped body -- it spawns at FULL scale (not the Man.glb Body's 0.335), so start near 1.0.
@export var body_model_scale: float = 1.0:
	set(value):
		body_model_scale = value
		_apply_body_transform()
## Local position of the body under this node -- nudge Y so the feet meet the ground.
@export var body_model_position: Vector3 = Vector3.ZERO:
	set(value):
		body_model_position = value
		_apply_body_transform()
## Rotation (degrees, per axis) of the body -- yaw to face the NPC's +Z forward; pitch/roll if it came in tipped.
@export var body_model_rotation: Vector3 = Vector3.ZERO:
	set(value):
		body_model_rotation = value
		_apply_body_transform()
## Optional texture to skin the body with (applied as an albedo material override over ALL its meshes). Null -> keep the model's own baked material.
@export var body_texture: Texture2D:
	set(value):
		body_texture = value
		_apply_body_texture()
## Flat colour for the body (tints body_texture if one's set, else a solid skin). Leave it WHITE for no override; pick any other colour to tint.
@export var body_color: Color = Color(1, 1, 1, 1):
	set(value):
		body_color = value
		_apply_body_texture()

# --- Head (sits on the torso; the head-look tracks it) -----------------------------------------------------------
@export var head_model: PackedScene:
	set(value):
		head_model = value
		_rebuild()
## Uniform scale of the swapped head -- size it to the torso.
@export var head_scale: float = 1.0:
	set(value):
		head_scale = value
		_apply_head_transform()
## Local position of the head under this node -- raise Y to sit it on the neck of the torso.
@export var head_position: Vector3 = Vector3.ZERO:
	set(value):
		head_position = value
		_apply_head_transform()
## Rotation (degrees) of the head's REST pose -- face it forward; the head-look adds its look-rotation on top.
@export var head_rotation: Vector3 = Vector3.ZERO:
	set(value):
		head_rotation = value
		_apply_head_transform()
## Optional texture to skin the head with (albedo material override over its meshes). Null -> keep the model's own material.
@export var head_texture: Texture2D:
	set(value):
		head_texture = value
		_apply_head_texture()
## Flat colour for the head (tints head_texture if set, else a solid skin). WHITE = no override; pick any other colour to tint.
@export var head_color: Color = Color(1, 1, 1, 1):
	set(value):
		head_color = value
		_apply_head_texture()

# --- Arms (a PAIR from one model: placed as the LEFT arm, mirrored across the body centre for the RIGHT) ----------
@export var arm_model: PackedScene:
	set(value):
		arm_model = value
		_rebuild()
## Uniform scale of each arm.
@export var arm_scale: float = 1.0:
	set(value):
		arm_scale = value
		_apply_arm_transform()
## Local position of the LEFT arm (its shoulder); the RIGHT arm is mirrored across X automatically. Set X to one side of the torso.
@export var arm_position: Vector3 = Vector3.ZERO:
	set(value):
		arm_position = value
		_apply_arm_transform()
## Rotation (degrees) of the LEFT arm; the RIGHT arm's rotation is mirrored to match.
@export var arm_rotation: Vector3 = Vector3.ZERO:
	set(value):
		arm_rotation = value
		_apply_arm_transform()
## Optional texture to skin both arms with (albedo override). Null -> keep the model's own material.
@export var arm_texture: Texture2D:
	set(value):
		arm_texture = value
		_apply_arm_texture()
## Flat colour for both arms (tints arm_texture if set, else a solid skin). WHITE = no override; pick any other colour to tint.
@export var arm_color: Color = Color(1, 1, 1, 1):
	set(value):
		arm_color = value
		_apply_arm_texture()

# --- Legs (a PAIR from one model, mirrored across the body centre like the arms; they swing with the gait) --------
@export var leg_model: PackedScene:
	set(value):
		leg_model = value
		_rebuild()
## Uniform scale of each leg.
@export var leg_scale: float = 1.0:
	set(value):
		leg_scale = value
		_apply_leg_transform()
## Local position of the LEFT leg (its hip); the RIGHT leg is mirrored across X automatically. Set X to one side of the torso, lower Y to the hip.
@export var leg_position: Vector3 = Vector3.ZERO:
	set(value):
		leg_position = value
		_apply_leg_transform()
## Rotation (degrees) of the LEFT leg; the RIGHT leg's rotation is mirrored to match.
@export var leg_rotation: Vector3 = Vector3.ZERO:
	set(value):
		leg_rotation = value
		_apply_leg_transform()
## Optional texture to skin both legs with (albedo override). Null -> keep the model's own material.
@export var leg_texture: Texture2D:
	set(value):
		leg_texture = value
		_apply_leg_texture()
## Flat colour for both legs (tints leg_texture if set, else a solid skin). WHITE = no override; pick any other colour to tint.
@export var leg_color: Color = Color(1, 1, 1, 1):
	set(value):
		leg_color = value
		_apply_leg_texture()

# --- Arm + leg animation (RUNTIME only -- the editor shows the static rest pose for placement) --------------------
## Animate the arms in-game: swing while walking unarmed, raise to hold a drawn weapon, rest by the side otherwise. Off -> arms stay at their static rest pose.
@export var animate_arms: bool = true
## How far (degrees) the arms swing forward/back while walking unarmed. Left + right swing OPPOSITE (the mirror handles it) -- Minecraft-style.
@export var arm_swing_amplitude: float = 35.0
## How fast the arms swing while walking.
@export var arm_swing_rate: float = 9.0
## Pitch (degrees) the arms raise to when the NPC has a weapon drawn (holding it forward). Flip the sign if your arm model points the wrong way.
@export var arm_hold_pitch: float = -65.0
## Planar speed (m/s) above which the NPC counts as walking. The arms + legs share this ONE gait threshold (and arm_swing_rate as the cadence) so they stay locked into a single walk cycle.
@export var arm_move_threshold: float = 0.4
## Animate the LEGS: swing them with the walk cycle whether or not a weapon is drawn (the legs always carry the body). Off -> legs stay at their static rest pose.
@export var animate_legs: bool = true
## How far (degrees) the legs swing forward/back while walking. They swing OPPOSITE each other AND opposite the same-side arm -- a natural contralateral (Minecraft) gait.
@export var leg_swing_amplitude: float = 28.0
## How much WIDER + FASTER the legs kick in the AIR vs the ground walk -- their mid-air FLAIL (a frantic bicycle kick). 1 = same as walking; higher = more frantic.
@export var leg_air_flail_scale: float = 1.8
## Pitch (degrees) the arms snap to when AIRBORNE and not holding a gun -- both straight up, roller-coaster / Roblox style. Tune to point your arm model overhead (more negative usually raises them further back).
@export var arm_air_pitch: float = -160.0
## Pitch (degrees) the arms FLAIL up to on a fist strike (NPC._punch), on top of the by-side rest pose, then ease back down. Set so the arms swing up and over toward the target.
@export var arm_strike_pitch: float = -120.0
## Seconds the fist-strike flail takes to rise and settle back to the side. ~1s reads as "wind up and strike".
@export var arm_strike_duration: float = 1.0

# --- Hide target -------------------------------------------------------------------------------------------------
## The Man.glb instance whose meshes are hidden. Empty -> auto-find a sibling "Body" node under the NPC.
@export var default_body: Node3D:
	set(value):
		default_body = value
		_rebuild()
## LEGACY: the head mount kept visible when you're NOT using head_model (a runtime head_scene). Ignored once head_model is set (then ALL Man.glb meshes hide and the component's head shows).
@export var keep_node: Node3D:
	set(value):
		keep_node = value
		_rebuild()

var _body: Node3D = null       ## live body instance (unowned -> never baked into the .tscn)
var _head: Node3D = null       ## live head instance (the head-look's target at runtime)
var _arm_left: Node3D = null   ## live left-arm instance
var _arm_right: Node3D = null  ## live right-arm instance (a mirror of the left)
var _leg_left: Node3D = null   ## live left-leg instance
var _leg_right: Node3D = null  ## live right-leg instance (a mirror of the left)
var _swing_phase: float = 0.0    ## walk-cycle phase, advanced only while moving (shared by arms + legs -> one gait)
var _mode_pitch: float = 0.0     ## smoothed SYMMETRIC pitch (both arms): raised to hold a weapon, else 0
var _swing_blend: float = 0.0    ## smoothed 0..1 fade for the arms' ANTISYMMETRIC walk swing (left +swing, right -swing)
var _leg_blend: float = 0.0      ## smoothed 0..1 fade for the legs' walk swing (left -swing, right +swing -> contralateral to the arms)
var _strike_t: float = 0.0       ## 1 -> 0 fist-strike flail envelope, set by strike() on a punch, decays over arm_strike_duration
var _host_model_sig: String = ""  ## editor live-preview: last seen host body/head MODEL signature (rebuild on change)
var _host_xf_sig: String = ""     ## editor live-preview: last seen host transform/skin signature (re-place on change)

func _ready() -> void:
	_rebuild()

func _process(delta: float) -> void:
	# The editor preview is the STATIC rest pose (so you can place the limbs); the swing/hold animation is runtime.
	if Engine.is_editor_hint():
		_editor_poll_host()  # live-preview the NPC root's body/head model overrides as you edit them
		return
	if animate_arms or animate_legs:
		_animate_limbs(delta)

## Runtime limb motion driven by the host NPC's state, on ONE shared gait phase so the arms and legs stay locked.
## ARMS pick a symmetric mode pose -- hold a GUN forward (is_holding_gun), or straight UP when airborne+unarmed
## (roller-coaster / Roblox), else by the side -- with the fist-strike FLAIL added on top, and the antisymmetric
## walk swing when moving unarmed on the ground. LEGS swing while walking on the ground (contralateral to the
## arms) and FLAIL (faster + wider) in the air; they rest only when grounded and still. Each pair mirrors L/R
## across the body centre. Duck-typed host reads.
func _animate_limbs(delta: float) -> void:
	var host := get_parent()
	if host == null:
		return
	var gun_out: bool = host.has_method(&"is_holding_gun") and bool(host.call(&"is_holding_gun"))
	var airborne: bool = host.has_method(&"is_on_floor") and not bool(host.call(&"is_on_floor"))
	var speed := 0.0
	var v: Variant = host.get(&"velocity")
	if v is Vector3:
		speed = Vector2(v.x, v.z).length()
	var moving := not airborne and speed > arm_move_threshold  # a walk cycle only makes sense on the ground
	var arms_walking := animate_arms and not gun_out and moving  # arms swing only when moving UNARMED on the ground
	var legs_active := animate_legs and (moving or airborne)     # legs swing while walking AND flail while airborne
	# ONE gait phase, advanced whenever a limb is moving -- FASTER in the air so the legs flail (a quick bicycle
	# kick) instead of stroll. The arms don't swing mid-air, so the air rate only ever drives the legs.
	if arms_walking or legs_active:
		_swing_phase += delta * (arm_swing_rate * leg_air_flail_scale if airborne else arm_swing_rate)
	var swing := sin(_swing_phase)
	# ARMS: symmetric mode pose (hold / up-in-air / side) + the fist-strike flail + the antisymmetric walk swing.
	if animate_arms and is_instance_valid(_arm_left):
		var mode_target := 0.0  # by the side
		if gun_out:
			mode_target = arm_hold_pitch        # holding a gun forward
		elif airborne:
			mode_target = arm_air_pitch          # both arms straight up (roller coaster)
		_mode_pitch = lerpf(_mode_pitch, mode_target, 1.0 - exp(-12.0 * delta))
		_strike_t = maxf(0.0, _strike_t - delta / maxf(arm_strike_duration, 0.01))
		var flail := arm_strike_pitch * smoothstep(0.0, 1.0, _strike_t) if not gun_out else 0.0  # fists: snap up, ease down
		_swing_blend = lerpf(_swing_blend, 1.0 if arms_walking else 0.0, 1.0 - exp(-10.0 * delta))
		var a := swing * arm_swing_amplitude * _swing_blend
		_arm_left.transform = _arm_pose(arm_rotation + Vector3(_mode_pitch + flail + a, 0.0, 0.0))
		if is_instance_valid(_arm_right):
			_arm_right.transform = _reflect() * _arm_pose(arm_rotation + Vector3(_mode_pitch + flail - a, 0.0, 0.0))
	# LEGS: swing forward/back -- a walk on the ground, a faster + WIDER flail in the air. Left -swing / right
	# +swing -> opposite each other (and contralateral to the arms while walking).
	if animate_legs and is_instance_valid(_leg_left):
		_leg_blend = lerpf(_leg_blend, 1.0 if legs_active else 0.0, 1.0 - exp(-10.0 * delta))
		var leg_amp := leg_swing_amplitude * leg_air_flail_scale if airborne else leg_swing_amplitude
		var l := swing * leg_amp * _leg_blend
		_leg_left.transform = _leg_pose(-l)
		if is_instance_valid(_leg_right):
			_leg_right.transform = _reflect() * _leg_pose(l)

## Kick off the fist-strike FLAIL: the arms snap up (arm_strike_pitch) then ease back to the side over
## arm_strike_duration. Called by the NPC the moment it lands a punch (npc.gd _punch). No-op visually while a gun
## is out (the flail is suppressed there) or with no arms swapped in.
func strike() -> void:
	_strike_t = 1.0

## The Man.glb instance to hide: the wired override, else the NPC's "Body" sibling.
func _target_body() -> Node3D:
	if is_instance_valid(default_body):
		return default_body
	var p := get_parent()
	return p.get_node_or_null(^"Body") as Node3D if p != null else null

## The mesh subtree to KEEP visible: nothing once we own the head (an effective head model -> hide all Man.glb
## meshes), else the legacy head mount (keep_node override, or "Head" under the body) so a runtime head_scene survives.
func _keep() -> Node:
	if _eff_head()["model"] != null:
		return null
	if is_instance_valid(keep_node):
		return keep_node
	var b := _target_body()
	return b.get_node_or_null(^"Head") if b != null else null

# --- Per-NPC appearance override (the BodyModelSwap reads its host NPC root's body/head model fields) -----------

## A part's effective look, resolved from the host NPC's root exports (when set) else this node's own. The host
## can override the MODEL (+ its scale/pos/rot) AND, INDEPENDENTLY, the TEXTURE / COLOUR -- so you can re-skin the
## default body without swapping its mesh. A swapped model with no host tex/colour shows its OWN material. Lets a
## designer retune an NPC's look by clicking it in the level (no "Editable Children"), with this @tool preview live.
func _host_part(model_f: StringName, scale_f: StringName, pos_f: StringName, rot_f: StringName, tex_f: StringName, col_f: StringName,
		own_model: PackedScene, own_scale: float, own_pos: Vector3, own_rot: Vector3, own_tex: Texture2D, own_col: Color) -> Dictionary:
	var h := get_parent()
	var ht: Variant = h.get(tex_f) if h != null else null
	var hc: Variant = h.get(col_f) if h != null else null
	var overridden := h != null and h.get(model_f) is PackedScene
	# Texture / colour resolve INDEPENDENTLY of the model: the host's when it sets one, else the swapped model's
	# OWN material (null / white) if the MODEL was overridden, else this node's own default skin.
	var tex: Texture2D = ht if ht is Texture2D else (null if overridden else own_tex)
	var col: Color = hc if (hc is Color and hc != Color.WHITE) else (Color.WHITE if overridden else own_col)
	if overridden:
		return {"model": h.get(model_f), "scale": float(h.get(scale_f)), "pos": h.get(pos_f), "rot": h.get(rot_f), "tex": tex, "col": col}
	return {"model": own_model, "scale": own_scale, "pos": own_pos, "rot": own_rot, "tex": tex, "col": col}

func _eff_body() -> Dictionary:
	return _host_part(&"body_model", &"body_model_scale", &"body_model_position", &"body_model_rotation", &"body_texture", &"body_color",
			body_model, body_model_scale, body_model_position, body_model_rotation, body_texture, body_color)

func _eff_head() -> Dictionary:
	return _host_part(&"head_model", &"head_model_scale", &"head_model_position", &"head_model_rotation", &"head_texture", &"head_color",
			head_model, head_scale, head_position, head_rotation, head_texture, head_color)

## Effective ARM / LEG tint: the host NPC's colour when it sets a non-white one, else this node's own (the shared
## default tint). The arm/leg MODEL + placement always stay this node's -- they're gait-animated, not host-swappable.
func _eff_arm_color() -> Color:
	var h := get_parent()
	var hc: Variant = h.get(&"arm_color") if h != null else null
	return hc if hc is Color and hc != Color.WHITE else arm_color

func _eff_leg_color() -> Color:
	var h := get_parent()
	var hc: Variant = h.get(&"leg_color") if h != null else null
	return hc if hc is Color and hc != Color.WHITE else leg_color

## Live-preview the host's body/head overrides while editing: re-instance on a MODEL change, just re-place on a
## transform / skin change (so dragging an offset doesn't thrash a full rebuild every editor frame).
func _editor_poll_host() -> void:
	var eb := _eff_body()
	var eh := _eff_head()
	if str(eb["model"]) + "|" + str(eh["model"]) != _host_model_sig:
		_rebuild()  # re-snapshots the signatures at its end
		return
	var xsig := _xf_sig(eb, eh)
	if xsig != _host_xf_sig:
		_host_xf_sig = xsig
		_apply_body_transform()
		_apply_body_texture()
		_apply_head_transform()
		_apply_head_texture()
		_apply_arm_texture()  # arm/leg COLOUR is host-overridable too (model/placement aren't)
		_apply_leg_texture()

## A string fingerprint of the resolved body+head transforms/skins + arm/leg tints, to detect a skin/placement
## edit without a full rebuild.
func _xf_sig(eb: Dictionary, eh: Dictionary) -> String:
	return str(eb["scale"]) + str(eb["pos"]) + str(eb["rot"]) + str(eb["tex"]) + str(eb["col"]) + \
		str(eh["scale"]) + str(eh["pos"]) + str(eh["rot"]) + str(eh["tex"]) + str(eh["col"]) + \
		str(_eff_arm_color()) + str(_eff_leg_color())

## Re-instance the body + head previews and (un)hide the Man.glb meshes; re-point the NPC's head reference at our
## head (runtime). Tree-guarded so a setter firing during scene load (before children exist) is a no-op.
func _rebuild() -> void:
	if not is_inside_tree():
		return
	for n in [_body, _head, _arm_left, _arm_right, _leg_left, _leg_right]:
		if is_instance_valid(n):
			n.queue_free()
	_body = null
	_head = null
	_arm_left = null
	_arm_right = null
	_leg_left = null
	_leg_right = null
	_set_meshes_visible(_target_body(), true)  # restore first, so clearing a model un-hides the Man.glb mesh
	var eb := _eff_body()
	var eh := _eff_head()
	if eb["model"] != null:
		var b: Node = (eb["model"] as PackedScene).instantiate()
		if b is Node3D:
			_body = b
			add_child(_body)  # UNOWNED on purpose: a live preview that isn't saved into the .tscn
			_apply_body_transform()
			_apply_body_texture()
		else:
			b.queue_free()
	if eh["model"] != null:
		var h: Node = (eh["model"] as PackedScene).instantiate()
		if h is Node3D:
			_head = h
			add_child(_head)
			_apply_head_transform()
			_apply_head_texture()
		else:
			h.queue_free()
	if arm_model != null:
		var arms := _instance_pair(arm_model)
		_arm_left = arms[0]
		_arm_right = arms[1]
		_apply_arm_transform()
		_apply_arm_texture()
	if leg_model != null:
		var legs := _instance_pair(leg_model)
		_leg_left = legs[0]
		_leg_right = legs[1]
		_apply_leg_transform()
		_apply_leg_texture()
	# Hide the Man.glb meshes once a body or head is swapped in. NOTE: Man.glb is ONE skinned mesh (BaseHuman); its
	# head is a "Head" BONE, not a toggleable node -- so we can't node-hide just the head. Every shipped NPC swaps
	# in a body_model (torso.tscn), so eb.model is non-null and the whole rig hides cleanly; a head-only swap with
	# NO body_model isn't a supported config on this rig (it'd hide the body too -- there's no head mesh to keep).
	if eb["model"] != null or eh["model"] != null:
		_set_meshes_visible(_target_body(), false)
	_register_head()
	if Engine.is_editor_hint():  # snapshot the resolved look so the editor poll only rebuilds on an ACTUAL change
		_host_model_sig = str(eb["model"]) + "|" + str(eh["model"])
		_host_xf_sig = _xf_sig(eb, eh)

## Instantiate a mirrored PAIR (arms or legs) from one scene: returns [left, right], each a Node3D added as our
## child, or null when the scene's root isn't a Node3D (which is freed, never leaked). The caller mirrors [1].
func _instance_pair(scene: PackedScene) -> Array:
	var pair: Array = [null, null]
	for i in 2:
		var n: Node = scene.instantiate()
		if n is Node3D:
			pair[i] = n
			add_child(n)  # UNOWNED on purpose: a live preview that isn't saved into the .tscn
		else:
			n.queue_free()
	return pair

func _apply_body_transform() -> void:
	if is_instance_valid(_body):
		var e := _eff_body()
		_body.position = e["pos"]
		_body.rotation_degrees = e["rot"]
		_body.scale = Vector3.ONE * float(e["scale"])

func _apply_head_transform() -> void:
	if is_instance_valid(_head):
		var e := _eff_head()
		_head.position = e["pos"]
		_head.rotation_degrees = e["rot"]
		_head.scale = Vector3.ONE * float(e["scale"])

## Place the LEFT arm from the exports, then make the RIGHT arm its mirror across the body centre (X=0) -- one arm
## model becomes a matched pair. The reflection (a negative-X basis) flips the geometry so it reads as the other hand.
func _apply_arm_transform() -> void:
	if is_instance_valid(_arm_left):
		_arm_left.transform = _arm_pose(arm_rotation)
	if is_instance_valid(_arm_right):
		_arm_right.transform = _reflect() * _arm_pose(arm_rotation)

## One arm's local transform from its rotation (degrees) at the shoulder, sized by arm_scale.
func _arm_pose(rot_deg: Vector3) -> Transform3D:
	var b := Basis.from_euler(Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)))
	return Transform3D(b.scaled(Vector3.ONE * arm_scale), arm_position)

## Place the LEFT leg at its rest pose, then mirror it across the body centre (X=0) for the RIGHT leg -- the same
## one-model-becomes-a-pair trick as the arms.
func _apply_leg_transform() -> void:
	if is_instance_valid(_leg_left):
		_leg_left.transform = _leg_pose(0.0)
	if is_instance_valid(_leg_right):
		_leg_right.transform = _reflect() * _leg_pose(0.0)

## One leg's local transform: the rest orientation (leg_rotation) SWUNG forward/back by swing_deg about the body's
## hip (X) axis, applied in BODY space (pre-multiplied) -- so the swing stays forward/back however leg_rotation
## yaws the model to point down. (Baking the swing into the model's local euler, like the arms do, sways the leg
## SIDEWAYS once it's yawed.) Sized by leg_scale at leg_position; the swing pivots about the model origin, so
## author leg.blend's origin at the hip.
func _leg_pose(swing_deg: float) -> Transform3D:
	var rest := Basis.from_euler(Vector3(deg_to_rad(leg_rotation.x), deg_to_rad(leg_rotation.y), deg_to_rad(leg_rotation.z)))
	var swung := Basis(Vector3.RIGHT, deg_to_rad(swing_deg)) * rest
	return Transform3D(swung.scaled(Vector3.ONE * leg_scale), leg_position)

## Reflection across the body's centre plane (X=0) -- turns a left-arm pose into the mirrored right arm.
func _reflect() -> Transform3D:
	return Transform3D(Basis(Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, 1.0)), Vector3.ZERO)

func _apply_body_texture() -> void:
	var e := _eff_body()
	_skin(_body, e["tex"], e["col"])  # skins the swapped body model (every shipped NPC has one; texture re-skins it in place)

func _apply_head_texture() -> void:
	var e := _eff_head()
	_skin(_head, e["tex"], e["col"])

func _apply_arm_texture() -> void:
	var c := _eff_arm_color()
	_skin(_arm_left, arm_texture, c)
	_skin(_arm_right, arm_texture, c)

func _apply_leg_texture() -> void:
	var c := _eff_leg_color()
	_skin(_leg_left, leg_texture, c)
	_skin(_leg_right, leg_texture, c)

## Override every MeshInstance3D under `root` with an albedo material from `tex` and/or `color` -- a texture OR any
## NON-WHITE colour builds the override (the colour tints the texture, or is a flat skin on its own). No texture +
## plain WHITE -> clear the override, restoring the model's own baked material (so WHITE is the "leave it" default).
func _skin(root: Node3D, tex: Texture2D, color: Color) -> void:
	if not is_instance_valid(root):
		return
	var tinted := color != Color.WHITE
	var mat: Material = null
	if tex != null or tinted:
		var sm := StandardMaterial3D.new()
		if tex != null:
			sm.albedo_texture = tex
		if tinted:
			sm.albedo_color = Color(color.r, color.g, color.b, 1.0)
		mat = sm
	_set_mesh_material(root, mat)

func _set_mesh_material(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for c in node.get_children():
		_set_mesh_material(c, mat)

## Point the NPC's head-look + sniper glint at our swapped head (runtime only -- npc.gd isn't @tool, so its
## methods don't run in the editor). Null when we own no head, so the NPC falls back to its own head_scene.
func _register_head() -> void:
	if Engine.is_editor_hint():
		return
	var host := get_parent()
	if host != null and host.has_method(&"register_swapped_head"):
		host.register_swapped_head(_head)

func _set_meshes_visible(root: Node, vis: bool) -> void:
	if root == null:
		return
	_walk_meshes(root, _keep(), vis)

func _walk_meshes(node: Node, keep: Node, vis: bool) -> void:
	if node == keep:
		return
	if node is MeshInstance3D:
		(node as MeshInstance3D).visible = vis
	for c in node.get_children():
		_walk_meshes(c, keep, vis)

## The custom model PARTS as {key, node} entries -- so the NPC can (a) rim each with the combat-outline overlay
## (the Man.glb meshes that carry the rim are hidden once we swap) and (b) flash the SPECIFIC part that's hit.
## Only valid (instanced) parts are returned. Keys: torso / head / arm_l / arm_r / leg_l / leg_r; the _l entries
## are the un-mirrored instance, the _r entries the mirrored side.
func character_parts() -> Array:
	var parts: Array = []
	if is_instance_valid(_body):
		parts.append({"key": "torso", "node": _body})
	if is_instance_valid(_head):
		parts.append({"key": "head", "node": _head})
	if is_instance_valid(_arm_left):
		parts.append({"key": "arm_l", "node": _arm_left})
	if is_instance_valid(_arm_right):
		parts.append({"key": "arm_r", "node": _arm_right})
	if is_instance_valid(_leg_left):
		parts.append({"key": "leg_l", "node": _leg_left})
	if is_instance_valid(_leg_right):
		parts.append({"key": "leg_r", "node": _leg_right})
	return parts
