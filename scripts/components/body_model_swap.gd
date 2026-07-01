@tool
class_name BodyModelSwap
extends Node3D

const ModelResourceUtil = preload("res://scripts/components/model_resource.gd")

## Drop-in CUSTOM CHARACTER swap with a LIVE EDITOR PREVIEW. Set body_model + head_model to your .glb files and
## they appear as the NPC's body + head RIGHT IN THE EDITOR (@tool) -- both at FULL SCALE
## in the SAME frame (under this node), so you tune their size / position / rotation and watch the head sit on the
## torso in real time, no playtest. This node IS the visible body: the shipped enemy.tscn no longer carries a
## default Man.glb "Body" node (removed as a vestigial hidden placeholder), so the enemy root's `mesh` export
## points HERE and the damage-flash + combat outline walk these swapped parts. If a base body node IS present
## (a "Body" sibling, or a wired `default_body`), its meshes are hidden behind the swap. At runtime the NPC's
## head-look + sniper glint retarget to the swapped head.
##
## SETUP: drop it under the NPC (the Enemy root). Set body_model (+ optionally head_model). Dial *_scale /
## *_position / *_rotation until it lines up. The same node does the swap at runtime, so what you see in the
## editor is what ships.

# --- Body --------------------------------------------------------------------------------------------------------
## Tick this any time the editor preview looks stale (after a .glb reimport or a script reload) to force a rebuild.
@export var refresh_preview: bool = false:
	set(value):
		refresh_preview = false  # momentary: snaps back so it always re-triggers
		_rebuild()
@export var body_model: Resource:
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
@export var head_model: Resource:
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
@export var arm_model: Resource:
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
## Build only the LEFT arm (skip the mirrored right) -- for a first-person view-model arm, where you see one hand on the weapon.
@export var single_arm: bool = false:
	set(value):
		single_arm = value
		_rebuild()
## Render-layer bitmask to force ALL spawned meshes onto (0 = leave them on their own layer). Set it to the view-model
## layer (4) for a first-person part so it draws in the gun's dedicated camera pass -- over the world, no clipping.
@export var view_model_layer: int = 0:
	set(value):
		view_model_layer = value
		_apply_view_model_layer()

# --- Legs (a PAIR from one model, mirrored across the body centre like the arms; they swing with the gait) --------
@export var leg_model: Resource:
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
## Whether the swapped meshes CAST SHADOWS. Default true (NPCs cast normal shadows). Set false for the Player's
## FIRST-PERSON legs — a shadow cast from under the camera looks wrong. Applied to every spawned mesh on each rebuild.
@export var casts_shadow: bool = true:
	set(value):
		casts_shadow = value
		_apply_cast_shadow()

# --- Arm + leg animation (RUNTIME only -- the editor shows the static rest pose for placement) --------------------
## Animate the arms in-game: swing while walking unarmed, raise to hold a drawn weapon, rest by the side otherwise. Off -> arms stay at their static rest pose.
@export var animate_arms: bool = true
## How far (degrees) the arms swing forward/back while walking unarmed. Left + right swing OPPOSITE (the mirror handles it) -- Minecraft-style.
@export var arm_swing_amplitude: float = 35.0
## How fast the arms swing while walking.
@export var arm_swing_rate: float = 9.0
## Pitch (degrees) the arms raise to when the NPC has a weapon drawn (holding it forward). Flip the sign if your arm model points the wrong way.
@export var arm_hold_pitch: float = -65.0
## How close (m) the foe must be before the NPC raises its weapon into the hold pose. Farther than this it keeps a
## weapon DRAWN but its arms DOWN (hanging / walk-swing) — so an enemy only "takes aim" when you get close, not the
## instant it draws across the map. Purely cosmetic: it never changes when the NPC actually fires. 0 -> always raised
## the moment the gun is out (the old behaviour). Read off the host's aim_distance(); no target -> arms stay down.
@export var arm_raise_range: float = 10.0
## Pitch (degrees) the arms hold FORWARD when the NPC is squared up to fight UNARMED (fists out) — held up so a fist enemy reads as armed-with-fists, with a gentle ALTERNATING sway on top (arm_fists_*_sway) instead of the normal walk swing. Driven by the host's is_fists_out(); drops back to the side when it's not fighting. Flip the sign if your arm model points the wrong way.
@export var arm_fists_pitch: float = -75.0
## Degrees the fists-out arms gently sway (arms ALTERNATE — one forward, one back) while STANDING — a small idle motion so the squared-up reach isn't frozen. 0 = perfectly still.
@export var arm_fists_idle_sway: float = 5.0
## Degrees the fists-out arms sway while WALKING — bigger than the idle sway, so the arms swing more as it advances on you.
@export var arm_fists_walk_sway: float = 16.0
## Cadence of the fists-out IDLE sway. Walking uses the normal arm_swing_rate so the sway locks to the gait.
@export var arm_fists_idle_rate: float = 3.5
## Planar speed (m/s) above which the NPC counts as walking. The arms + legs share this ONE gait threshold (and arm_swing_rate as the cadence) so they stay locked into a single walk cycle.
@export var arm_move_threshold: float = 0.4
## Animate the LEGS: swing them with the walk cycle whether or not a weapon is drawn (the legs always carry the body). Off -> legs stay at their static rest pose.
@export var animate_legs: bool = true
## How far (degrees) the legs swing forward/back while walking. They swing OPPOSITE each other AND opposite the same-side arm -- a natural contralateral (Minecraft) gait.
@export var leg_swing_amplitude: float = 28.0
## How much WIDER + FASTER the legs kick in the AIR vs the ground walk -- their mid-air FLAIL (a frantic bicycle kick). 1 = same as walking; higher = more frantic.
@export var leg_air_flail_scale: float = 1.8
## Drive the legs off ACTUAL VELOCITY instead of the NPC mid-air flail. Off (NPC default): legs do the wide bicycle
## flail while airborne. On (the Player's FP legs): the legs run their normal speed-gated walk gait on the ground
## AND in the air, so they track your real movement -- still when you're not moving horizontally, striding when you
## are -- instead of thrashing.
@export var velocity_driven_legs: bool = false
## With velocity_driven_legs on, the speed (m/s) at which the legs cycle at their base cadence (arm_swing_rate).
## Below it the stride slows; above it (bhop / dash) it quickens — so the walk-cycle SPEED tracks how fast you move.
## Set near the host's run speed.
@export var velocity_leg_ref_speed: float = 5.0
## Steer the LEGS to face the direction the NPC is actually MOVING, independent of the torso (which keeps facing
## its aim/look). So an enemy strafing or backpedalling around you has its hips pointed along its path while its
## chest stays trained on you — a natural run-and-gun. Off -> legs stay square with the torso (the old behaviour).
@export var legs_follow_movement: bool = true
## How fast (higher = snappier) the legs swivel toward the movement direction. Lower = a lazier, sliding turn.
@export var leg_turn_rate: float = 9.0
## Pitch (degrees) the arms snap to when AIRBORNE and not holding a gun -- both straight up, roller-coaster / Roblox style. Tune to point your arm model overhead (more negative usually raises them further back).
@export var arm_air_pitch: float = -160.0
## Pitch (degrees) the arms FLAIL up to on a fist strike (NPC._punch), on top of the by-side rest pose, then ease back down. Set so the arms swing up and over toward the target.
@export var arm_strike_pitch: float = -120.0
## Seconds the fist-strike flail takes to rise and settle back to the side. ~1s reads as "wind up and strike".
@export var arm_strike_duration: float = 1.0

# --- Breathing (RUNTIME only) — a subtle, slow CHEST rise/fall on the torso, Deus Ex idle style -----------------
## Breathe: scale the BODY (torso only — head/arms/legs are separate) up and down on a slow sine so a standing
## NPC looks alive. Off -> the torso holds its static scale.
@export var breathe: bool = true
## Peak scale delta of the breath [fraction]: 0.03 = the chest swells ~3% at the top of the inhale. Keep it small.
@export var breathe_amount: float = 0.03
## Breaths per ~6.3s of phase (a sine rate): ~1.6 ≈ one calm breath every ~4s. Lower = slower, heavier breathing.
@export var breathe_rate: float = 1.6

# --- Talking (dialogue) — head bob + a Tomodachi-style mouth, active ONLY on the NPC you're talking to ----------
## Bob the head up/down while THIS NPC is delivering a dialogue line (it's the one you're talking to). Heads read
## as too static otherwise. Needs a head node (a head_model swapped in). Off -> static head.
@export var talk_head_bob: bool = true
## Height (m) of the talking head bob.
@export var talk_bob_height: float = 0.03
## Head bobs per ~6.3s (a sine rate) while talking — higher = a chattier, more animated nod.
@export var talk_bob_rate: float = 9.0
## How fast the bob eases in/out as the NPC starts/stops delivering a line.
@export var talk_bob_ease: float = 8.0
## Show a Tomodachi-style MOUTH (a black line that flaps open into a black circle, over and over) on the face
## while this NPC is speaking a line or a bark; it hides between utterances. A billboard, so it always faces the
## camera (never oriented away). Needs a head node (a head_model swap). Off -> no mouth.
@export var show_mouth: bool = true
## Radius (m) of the mouth circle at full open. The mouth rides the head, so it scales with the head.
@export var mouth_size: float = 0.06
## Mouth position in HEAD-LOCAL space (+Z is the face front). Tune it to sit on the model's mouth — if you don't
## see it, it may be inside the head; push Z out (more forward) and adjust Y to taste.
@export var mouth_position: Vector3 = Vector3(0.0, -0.03, 0.14)
## Mouth flaps per ~6.3s (a sine rate) — the open/close chatter speed while speaking.
@export var mouth_flap_rate: float = 22.0

# --- Hide target -------------------------------------------------------------------------------------------------
## The base body instance whose meshes get hidden behind the swap. Empty -> auto-find a sibling "Body" node under
## the NPC. NOTE: the shipped enemy.tscn no longer ships a default "Body" (removed as a vestigial hidden
## placeholder), so this resolves to null and the hide is a harmless no-op by default; set it only if you add a
## base mesh you deliberately want hidden.
@export var default_body: Node3D:
	set(value):
		default_body = value
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
var _leg_world_yaw: float = 0.0  ## smoothed WORLD-space facing of the legs (tracks movement dir; eases to the torso yaw when still)
var _leg_yaw_ready: bool = false ## once true, _leg_world_yaw has been seeded to the body yaw (avoids a spawn-frame swivel from 0)
var _bob_phase: float = 0.0      ## talking head-bob sine phase
var _bob_amt: float = 0.0        ## smoothed 0..1 talking bob envelope (eases in/out as line delivery starts/stops)
var _bob_head: Node3D = null     ## the head node currently being bobbed (re-resolved if it rebuilds)
var _bob_rest_y: float = 0.0     ## that head's rest local Y, captured so the bob oscillates AROUND it
var _mouth: MeshInstance3D = null  ## the Tomodachi mouth (a billboarded black-circle quad on the face); lazily built
var _mouth_phase: float = 0.0    ## mouth-flap sine phase
var _talk_t: float = 0.0         ## talking-envelope countdown (seconds): the head bobs + mouth flaps while >0; pulsed by talk_for() per spoken utterance

static var _mouth_texture: Texture2D = null  ## the shared black-circle texture for every mouth (built once)
var _strike_t: float = 0.0       ## 1 -> 0 fist-strike flail envelope, set by strike() on a punch, decays over arm_strike_duration
var _fists_sway: float = 0.0     ## smoothed fists-out alternating-sway amplitude (eases to 0 when not squared up)
var _breathe_phase: float = 0.0  ## breathing sine phase (advances at breathe_rate while alive)
var _body_base_scale: float = 1.0  ## the torso's authored uniform scale; breathing modulates AROUND it (cached so _process doesn't re-resolve _eff_body each frame)
var _host_model_sig: String = ""  ## editor live-preview: last seen host body/head MODEL signature (rebuild on change)
var _host_xf_sig: String = ""     ## editor live-preview: last seen host transform/skin signature (re-place on change)

func _ready() -> void:
	# Keep processing the idle breathing even while the world is PAUSED for dialogue and the host NPC is frozen:
	# DialogueManager does get_tree().paused = true AND sets the speaker to PROCESS_MODE_DISABLED. An EXPLICIT
	# process mode is independent of the tree-pause and of the parent's mode, so the NPC you're talking to keeps
	# breathing (its frozen state is still readable). Runtime only -- the editor preview is unaffected.
	if not Engine.is_editor_hint():
		process_mode = Node.PROCESS_MODE_ALWAYS
		_breathe_phase = randf() * TAU  # random start across the breath cycle so NPCs don't all inhale in lockstep
	_rebuild()

func _validate_property(property: Dictionary) -> void:
	if property.name in [&"body_model", &"head_model", &"arm_model", &"leg_model"]:
		property.hint = PROPERTY_HINT_RESOURCE_TYPE
		property.hint_string = ModelResourceUtil.HINT

func _process(delta: float) -> void:
	# The editor preview is the STATIC rest pose (so you can place the limbs); the swing/hold animation is runtime.
	if Engine.is_editor_hint():
		_editor_poll_host()  # live-preview the NPC root's body/head model overrides as you edit them
		return
	# Skip the gait animation while the world is PAUSED (dialogue): the speaker (and every other NPC) is frozen,
	# and its last velocity would still read as "walking" and keep swinging the arms. Breathing runs regardless
	# (below), so the NPC you're talking to stays alive without the limbs animating mid-freeze.
	if not get_tree().paused and (animate_arms or animate_legs):
		_animate_limbs(delta)
	if breathe:
		# Only the NPC you're TALKING TO breathes during a conversation — every other NPC holds still. (Without
		# this they'd all keep breathing through the dialogue pause, since this node is PROCESS_MODE_ALWAYS.)
		if not (DialogueManager.is_active() and not _is_dialogue_speaker()):
			_breathe(delta)
	_animate_talk(delta)  # talking head-bob + mouth flap (active only on the NPC currently delivering a line)

## A subtle, slow CHEST rise/fall: scale the torso (the body mesh only — head/arms/legs are separate children,
## so they don't grow with it) on a sine around its authored scale, Deus Ex idle style. Rests at the base scale
## once the host is dead (no breathing corpse) — duck-typed HP read, per the duck-typed-read rule.
func _breathe(delta: float) -> void:
	if not is_instance_valid(_body):
		return
	var host := get_parent()
	var raw: Variant = host.get(&"hp") if host != null else null
	var alive := not (raw is float or raw is int) or float(raw) > 0.0
	if not alive:
		_body.scale = Vector3.ONE * _body_base_scale  # rest at the authored scale; a corpse doesn't breathe
		return
	_breathe_phase += delta * breathe_rate
	_body.scale = Vector3.ONE * (_body_base_scale * (1.0 + sin(_breathe_phase) * breathe_amount))

## True when the NPC this body belongs to is the one currently in dialogue with the player (so the talking
## head-bob / mouth + the speaker-only breathing apply to it alone). is_ancestor_of covers any nesting depth.
func _is_dialogue_speaker() -> bool:
	var sp: Node = DialogueManager.current_speaker()
	return sp != null and sp.is_ancestor_of(self)

## The head node the talk bob + mouth ride on: this component's own swapped head if present, else the host's
## resolved visible head (head_visual()). Null -> no separate head node (bob/mouth are no-ops).
func _talk_head() -> Node3D:
	if is_instance_valid(_head):
		return _head
	var host := get_parent()
	if host != null and host.has_method(&"head_visual"):
		var h: Variant = host.call(&"head_visual")
		if h is Node3D:
			return h
	return null

## Talking presentation, runtime-only (called every frame). The head BOBS and a Tomodachi MOUTH flaps while this
## NPC is the active speaker delivering a line; both ease/close otherwise. Keyed off DialogueManager so no
## NPC-side wiring is needed; non-speakers fall through cheaply (current_speaker() != us -> talking false).
func _animate_talk(delta: float) -> void:
	if _talk_t > 0.0:
		_talk_t = maxf(0.0, _talk_t - delta)
	var talking := _talk_t > 0.0
	# Steady-state fast path: not talking, bob already settled, mouth already hidden -> nothing to do. Skips the
	# work for every silent NPC on every frame (the common case), while still letting the bob ease back out.
	if not talking and _bob_amt < 0.001 and not (is_instance_valid(_mouth) and _mouth.visible):
		return
	_talk_head_bob(delta, talking)
	_talk_mouth(delta, talking)

## Pulse the talking envelope: the head bobs + the mouth flaps for `seconds` (the utterance length). Pushed by
## the host NPC (NPC.note_speaking) whenever it speaks a dialogue line OR a bark, so the animation tracks ACTUAL
## utterances, not the whole dialogue turn. maxf so an overlapping pulse never cuts an in-flight one short.
func talk_for(seconds: float) -> void:
	_talk_t = maxf(_talk_t, seconds)

## Bob the head up/down (position only, so it composes with the head-look's basis writes) around its rest Y while
## talking, easing the amplitude in/out. Re-caches the rest Y if the head node is rebuilt.
func _talk_head_bob(delta: float, talking: bool) -> void:
	if not talk_head_bob:
		return
	var head := _talk_head()
	if head == null:
		return
	if head != _bob_head:
		_bob_head = head
		_bob_rest_y = head.position.y
	_bob_amt = lerpf(_bob_amt, 1.0 if talking else 0.0, 1.0 - exp(-talk_bob_ease * delta))
	if talking:
		_bob_phase += delta * talk_bob_rate
	head.position.y = _bob_rest_y + sin(_bob_phase) * talk_bob_height * _bob_amt

## Flap the mouth (a billboarded black circle on the face) between a thin line and a full circle while talking;
## hide it otherwise. Built lazily on the current head (rebuilt if the head node changes — e.g. a model swap).
func _talk_mouth(delta: float, talking: bool) -> void:
	if not show_mouth:
		return
	var head := _talk_head()
	if head == null:
		return
	if not is_instance_valid(_mouth) or _mouth.get_parent() != head:
		_build_mouth(head)
	if not talking:
		if _mouth.visible:
			_mouth.visible = false
		_mouth_phase = 0.0
		return
	_mouth.visible = true
	_mouth_phase += delta * mouth_flap_rate
	var open := 0.5 - 0.5 * cos(_mouth_phase)         # 0 = a thin line, 1 = a full circle
	_mouth.scale = Vector3(1.0, lerpf(0.1, 1.0, open), 1.0)  # squash vertically -> the line<->circle flap

## Create the mouth: a black-circle QuadMesh parented to the head's face, billboarded toward the camera so it
## can never be oriented away / hidden by a model whose face isn't +Z. Uses a MESH + StandardMaterial3D billboard
## with billboard_keep_scale=true (NOT a Sprite3D / node billboard) — the flap is driven by the node's scale.y,
## which a plain billboard DISCARDS (see ambient_dust.gd / sky_title.gd). Unshaded black, alpha-cut to the circle.
func _build_mouth(head: Node3D) -> void:
	if is_instance_valid(_mouth):
		_mouth.queue_free()
	_mouth = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(mouth_size * 2.0, mouth_size * 2.0)
	_mouth.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _mouth_circle_texture()           # white circle on transparent; tinted black below
	mat.albedo_color = Color.BLACK
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # flat black regardless of lighting
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA     # the circle's alpha cuts the quad corners
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED             # visible from both sides
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true                         # CRITICAL: keep the node scale so scale.y can flap it
	_mouth.material_override = mat
	_mouth.position = mouth_position
	_mouth.visible = false
	head.add_child(_mouth)

## The shared circle texture every mouth uses — a filled WHITE disc on transparent (the material tints it via
## albedo_color, so it stays recolourable). Built once (static), shared across all mouths.
static func _mouth_circle_texture() -> Texture2D:
	if _mouth_texture != null:
		return _mouth_texture
	var px := 64
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 1.0, 1.0, 0.0))
	var c := px * 0.5
	var r := px * 0.5 - 1.0
	for y in range(px):
		for x in range(px):
			var dx := float(x) + 0.5 - c
			var dy := float(y) + 0.5 - c
			if dx * dx + dy * dy <= r * r:
				img.set_pixel(x, y, Color.WHITE)
	_mouth_texture = ImageTexture.create_from_image(img)
	return _mouth_texture

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
	var gun_out := HostMethodHelper.try_call_bool(host, &"is_holding_gun")
	# Arms RAISE into the weapon-hold pose only when the foe is within arm_raise_range; farther out the gun stays
	# drawn but the arms hang at the side / swing with the stride. Purely cosmetic — it never gates actual firing.
	# arm_raise_range <= 0, or a host without aim_distance(), keeps the old always-raised-on-draw behaviour; no
	# target (aim_distance() == INF) keeps the arms down (searching with the weapon low until the foe is close).
	var raised := gun_out
	if gun_out and arm_raise_range > 0.0 and host.has_method(&"aim_distance"):
		raised = float(host.call(&"aim_distance")) <= arm_raise_range
	var fists_out := HostMethodHelper.try_call_bool(host, &"is_fists_out")
	var airborne := not HostMethodHelper.try_call_bool(host, &"is_on_floor", true)  # default true: no method -> not airborne
	var climbing := HostMethodHelper.try_call_bool(host, &"is_climbing")
	# On a wall (wall-climb) the host isn't on the floor but isn't free-falling either — treat it as grounded so the
	# legs stride against the wall instead of doing the airborne bicycle-flail. (The host pitches the rig onto the
	# wall separately.)
	if climbing:
		airborne = false
	# velocity_driven_legs (the Player's FP legs): the legs run their normal speed-gated walk gait in the AIR too,
	# tracking real velocity, instead of the NPC mid-air "bicycle" flail. airborne_flail keeps the NPC behaviour.
	var airborne_flail := airborne and not velocity_driven_legs
	var speed := 0.0
	var planar := 0.0
	var v: Variant = host.get(&"velocity")
	if v is Vector3:
		planar = Vector2((v as Vector3).x, (v as Vector3).z).length()
		speed = planar
		if climbing:
			speed = maxf(planar, absf((v as Vector3).y))  # scaling a wall: stride off the VERTICAL climb speed — going "up" IS moving
	var moving := (not airborne or velocity_driven_legs) and speed > arm_move_threshold  # walk cycle: grounded, or anytime when velocity-driven
	# Fists-out holds the forward pose with its OWN alternating sway (below), which replaces the normal walk swing.
	var arms_walking := animate_arms and not raised and not fists_out and moving  # arms swing when moving with arms NOT raised (unarmed, or armed-but-far)
	var legs_active := animate_legs and (moving or airborne_flail)  # legs swing while walking AND (NPC) flail while airborne
	# ONE gait phase, advanced whenever a limb is moving AND while fists are out (so the squared-up reach bobs even
	# standing still). FASTER in the air so the legs flail (a quick bicycle kick); a slow lurch when squared up +
	# standing; else the walk rate. The arms don't swing mid-air, so the air rate only ever drives the legs + bob.
	if arms_walking or legs_active or fists_out:
		var phase_rate := arm_swing_rate
		if velocity_driven_legs and legs_active:
			# Stride CADENCE tracks real speed: cycle at arm_swing_rate at velocity_leg_ref_speed, slower below,
			# quicker above (bhop/dash). So the walk animation's speed is dictated by how fast you're actually going.
			phase_rate = arm_swing_rate * clampf(speed / maxf(velocity_leg_ref_speed, 0.01), 0.3, 3.0)
		elif airborne_flail:
			phase_rate *= leg_air_flail_scale
		elif fists_out and not moving:
			phase_rate = arm_fists_idle_rate
		_swing_phase += delta * phase_rate
	var swing := sin(_swing_phase)
	# ARMS: symmetric mode pose (hold / up-in-air / side) + the fist-strike flail + the antisymmetric walk swing.
	if animate_arms and is_instance_valid(_arm_left):
		var mode_target := 0.0  # by the side
		if raised:
			mode_target = arm_hold_pitch        # holding a gun forward (only once the foe is close — see `raised`)
		elif airborne:
			mode_target = arm_air_pitch          # both arms straight up (roller coaster)
		elif fists_out:
			mode_target = arm_fists_pitch        # arms out — squared up to punch
		_mode_pitch = lerpf(_mode_pitch, mode_target, 1.0 - exp(-12.0 * delta))
		_strike_t = maxf(0.0, _strike_t - delta / maxf(arm_strike_duration, 0.01))
		var flail := arm_strike_pitch * smoothstep(0.0, 1.0, _strike_t) if not gun_out else 0.0  # fists: snap up, ease down
		_swing_blend = lerpf(_swing_blend, 1.0 if arms_walking else 0.0, 1.0 - exp(-10.0 * delta))
		var a := swing * arm_swing_amplitude * _swing_blend  # antisymmetric walk swing (0 while fists are out)
		# Fists-out: an ANTISYMMETRIC sway (arms ALTERNATE -- one forward, one back, like a natural stride) on top
		# of the forward hold -- small standing, bigger walking -- so the reach looks alive. Smoothed to ease in.
		var sway_target := (arm_fists_walk_sway if moving else arm_fists_idle_sway) if fists_out else 0.0
		_fists_sway = lerpf(_fists_sway, sway_target, 1.0 - exp(-8.0 * delta))
		var s := swing * _fists_sway  # left +s / right -s -> the arms alternate (same shape as the walk swing)
		_arm_left.transform = _arm_pose(arm_rotation + Vector3(_mode_pitch + flail + a + s, 0.0, 0.0))
		if is_instance_valid(_arm_right):
			_arm_right.transform = _reflect() * _arm_pose(arm_rotation + Vector3(_mode_pitch + flail - a - s, 0.0, 0.0))
	# LEGS: swing forward/back -- a walk on the ground, a faster + WIDER flail in the air. Left -swing / right
	# +swing -> opposite each other (and contralateral to the arms while walking).
	if animate_legs and is_instance_valid(_leg_left):
		_leg_blend = lerpf(_leg_blend, 1.0 if legs_active else 0.0, 1.0 - exp(-10.0 * delta))
		var leg_amp := leg_swing_amplitude
		if airborne_flail:
			leg_amp = leg_swing_amplitude * leg_air_flail_scale
		elif climbing:
			leg_amp = leg_swing_amplitude * 0.5  # gentler steps while scaling a wall — less foot-into-wall on the forward swing
		var l := swing * leg_amp * _leg_blend
		# Decouple the leg yaw from the torso: ease the legs' WORLD facing toward the movement direction while
		# moving on the ground, back to the body's own yaw when still / airborne. The LOCAL turn applied to the
		# legs is the gap to the body's current yaw, recomputed each frame, so the legs hold the movement line
		# even as the torso swivels to keep its aim on you. Pre-multiplied so it rotates the whole hip about UP.
		var leg_turn := Transform3D.IDENTITY
		if legs_follow_movement:
			var body_yaw := global_transform.basis.get_euler().y
			if not _leg_yaw_ready:
				_leg_world_yaw = body_yaw
				_leg_yaw_ready = true
			var target_yaw := body_yaw
			if moving and planar > arm_move_threshold:  # only HORIZONTAL movement steers the leg facing (a vertical climb shouldn't swivel them)
				target_yaw = atan2(v.x, v.z)
			_leg_world_yaw = lerp_angle(_leg_world_yaw, target_yaw, 1.0 - exp(-leg_turn_rate * delta))
			leg_turn = Transform3D(Basis(Vector3.UP, wrapf(_leg_world_yaw - body_yaw, -PI, PI)))
		_leg_left.transform = leg_turn * _leg_pose(-l)
		if is_instance_valid(_leg_right):
			_leg_right.transform = leg_turn * _reflect() * _leg_pose(l)

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
## meshes), else the Man.glb's own "Head" subtree under the body -- so a BODY-ONLY swap keeps the default head.
func _keep() -> Node:
	if _eff_head()["model"] != null:
		return null
	var b := _target_body()
	return b.get_node_or_null(^"Head") if b != null else null

# --- Per-NPC appearance override (the BodyModelSwap reads its host NPC root's body/head model fields) -----------

## The SOURCE of per-NPC appearance overrides: the host NPC's assigned `look` (an NpcLook resource) when it has
## one, else the host node itself (its inline flat fields). NpcLook MIRRORS the host's field names, so _host_part
## and _eff_*_color read whichever is in play uniformly via .get(field). Null host -> null (no override).
func _look_src() -> Object:
	var h := get_parent()
	if h == null:
		return null
	var lk: Variant = h.get(&"look")
	return lk if lk is NpcLook else h

## A part's effective look, resolved from the host NPC's root exports (when set) else this node's own. The host
## can override the MODEL (+ its scale/pos/rot) AND, INDEPENDENTLY, the TEXTURE / COLOUR -- so you can re-skin the
## default body without swapping its mesh. A swapped model with no host tex/colour shows its OWN material. Lets a
## designer retune an NPC's look by clicking it in the level (no "Editable Children"), with this @tool preview live.
func _host_part(model_f: StringName, scale_f: StringName, pos_f: StringName, rot_f: StringName, tex_f: StringName, col_f: StringName,
		own_model: Resource, own_scale: float, own_pos: Vector3, own_rot: Vector3, own_tex: Texture2D, own_col: Color) -> Dictionary:
	var h := _look_src()
	var ht: Variant = h.get(tex_f) if h != null else null
	var hc: Variant = h.get(col_f) if h != null else null
	var overridden := h != null and ModelResourceUtil.is_model(h.get(model_f))
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
	var h := _look_src()
	var hc: Variant = h.get(&"arm_color") if h != null else null
	return hc if hc is Color and hc != Color.WHITE else arm_color

func _eff_leg_color() -> Color:
	var h := _look_src()
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
		var b: Node3D = ModelResourceUtil.instantiate(eb["model"], "BodyModel")
		if b != null:
			_body = b
			add_child(_body)  # UNOWNED on purpose: a live preview that isn't saved into the .tscn
			_apply_body_transform()
			_apply_body_texture()
	if eh["model"] != null:
		var h: Node3D = ModelResourceUtil.instantiate(eh["model"], "HeadModel")
		if h != null:
			_head = h
			add_child(_head)
			_apply_head_transform()
			_apply_head_texture()
	if arm_model != null:
		var arms := _instance_pair(arm_model, 1 if single_arm else 2)  # single_arm: LEFT only (a first-person view-model arm)
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
	_apply_cast_shadow()  # re-instanced meshes inherit the current casts_shadow setting
	_apply_view_model_layer()  # ...and the view-model render layer, if this rig is a first-person part
	if Engine.is_editor_hint():  # snapshot the resolved look so the editor poll only rebuilds on an ACTUAL change
		_host_model_sig = str(eb["model"]) + "|" + str(eh["model"])
		_host_xf_sig = _xf_sig(eb, eh)
		update_configuration_warnings()  # the head-only-no-body warning depends on the resolved eb/eh models

## Editor warning: the rig can't do a head-only swap. Man.glb is ONE skinned mesh whose head is a BONE, so
## swapping in a head with no body hides the body too (there's no separate head mesh to keep). Flags the case
## where the EFFECTIVE head model is set but the EFFECTIVE body model is null -- resolving the host NPC's
## overrides exactly like the live preview (_eff_body / _eff_head), so a body supplied on the NPC root counts.
func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	if _eff_head()["model"] != null and _eff_body()["model"] == null:
		w.append("Head model set with no body model — unsupported on this rig (Man.glb's head is a bone, so this hides the whole body). Set a body_model (here or on the NPC root), or clear the head model.")
	return w

## Instantiate a mirrored PAIR (arms or legs) from one model resource: returns [left, right], each a Node3D added as our
## child, or null when the resource cannot produce a Node3D. The caller mirrors [1].
func _instance_pair(model: Resource, count: int = 2) -> Array:
	var pair: Array = [null, null]
	for i in count:
		var n: Node3D = ModelResourceUtil.instantiate(model, "ModelPart")
		if n != null:
			pair[i] = n
			add_child(n)  # UNOWNED on purpose: a live preview that isn't saved into the .tscn
	return pair

func _apply_body_transform() -> void:
	if is_instance_valid(_body):
		var e := _eff_body()
		_body.position = e["pos"]
		_body.rotation_degrees = e["rot"]
		_body_base_scale = float(e["scale"])  # cache the authored scale so runtime breathing pulses around it
		_body.scale = Vector3.ONE * _body_base_scale

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

## Apply casts_shadow to every spawned part's meshes, so re-instanced meshes inherit it after a rebuild.
func _apply_cast_shadow() -> void:
	var mode: GeometryInstance3D.ShadowCastingSetting = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for root in [_body, _head, _arm_left, _arm_right, _leg_left, _leg_right]:
		_set_cast_shadow(root, mode)

## Recursively set cast_shadow on every GeometryInstance3D (MeshInstance3D etc.) under `node`.
func _set_cast_shadow(node: Node, mode: GeometryInstance3D.ShadowCastingSetting) -> void:
	if not is_instance_valid(node):
		return
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = mode
	for c in node.get_children():
		_set_cast_shadow(c, mode)

## Force every spawned mesh onto `view_model_layer` (a render-layer bitmask) when it's set (> 0), so a first-person
## body part (e.g. the player's left arm) draws in the dedicated view-model camera pass ON TOP of the world, with no
## wall clipping -- exactly like the gun. 0 (the default) leaves the models on their own layers, unchanged.
func _apply_view_model_layer() -> void:
	if view_model_layer <= 0:
		return
	for root in [_body, _head, _arm_left, _arm_right, _leg_left, _leg_right]:
		_set_render_layer(root, view_model_layer)

func _set_render_layer(node: Node, layers: int) -> void:
	if not is_instance_valid(node):
		return
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layers
	for c in node.get_children():
		_set_render_layer(c, layers)

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
## methods don't run in the editor). Null when we own no head (the NPC's glint then uses the Man.glb head bone).
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
