@tool
class_name Throwable
extends RigidBody3D

const ModelResourceUtil = preload("res://scripts/components/model_resource.gd")
const DamageNumberPopupScript = preload("res://scripts/combat/damage_number_popup.gd")
const OUTLINE_SHADER = preload("res://resources/shaders/outline.gdshader")
const FLASH_OVERLAY_SHADER = preload("res://resources/shaders/flash_overlay.gdshader")
const DUST_LARGE = preload("uid://ckxkt0g5gq8bb")
const PARTY_HORN = preload("uid://v2yom7vyodag")
const DESTROY_DECAL = preload("uid://dh1ydtvwvgiqg")  # bullet_hole / scorch decal
const DESTROY_DECAL_SIZE: Vector3 = Vector3(2.0, 1.0, 2.0)
const DESTROY_DECAL_PROBE: float = 3.0
const DESTROY_DECAL_CULL_MASK: int = 2
const DESTROY_DECAL_PARALLEL_THRESHOLD: float = 0.99

const OUTLINE_HIDDEN_COLOR: Color = Color(0.0, 0.0, 0.0, 1.0)
const OUTLINE_VISIBLE_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const FLASH_PEAK_STRENGTH: float = 2.0
const FLASH_UP_TIME: float = 0.08
const FLASH_DOWN_TIME: float = 0.18
const DEFAULT_BREATHE_AMOUNT: float = 0.03
const DEFAULT_BREATHE_RATE: float = 1.6
const DEFAULT_FACE_TRAVEL_MIN_SPEED: float = 2.0  ## the thrown-facing release speed when neither instance nor data sets one
## Smallest per-axis visual extent (m) the collision auto-fit will size to. A degenerate AABB below this on ANY axis
## (an empty / PlaceholderMesh mesh_instance, or a prop whose real visual lives OUTSIDE mesh_instance) would otherwise
## collapse the collider to ~zero -- see _autofit_collision_shape for why that's catastrophic.
const AUTOFIT_MIN_EXTENT: float = 0.01

## The pin geometry + policy statics, preloaded by path rather than referenced by their `PartPinner` class_name
## (the BodyPartGibs idiom in gore_spawner.gd) — this script sits on the actor parse path via Character.
const PartPinnerScript := preload("res://scripts/effects/part_pinner.gd")

enum HeldVisibilityMode { INHERIT, FADE, OPAQUE }

## Safety floor: a stealth decoy NoiseSource MUST be one-shot (a non-positive lifetime would make it persistent
## -- never freeing, pinning hearing NPCs forever). Guarantees the spawned source self-frees even if a config
## resolves to <= 0. Not a designer feel knob (decoy duration is GameSettings.distraction.decoy_lifetime).
const MIN_DECOY_LIFETIME: float = 0.1

## Poll interval (s) a gib whose lifetime has expired waits, while CARRIED, before it may fade + free -- so it never
## despawns out of the player's hands (see begin_gib_lifetime). An epsilon, not a designer feel knob (the gib timings
## are GameSettings.effects.gib_lifetime / gib_fade_time).
const GIB_HELD_DESPAWN_RECHECK: float = 0.5

@export_group("Identity")
## Optional per-instance noun shown in the hover prompt. "Dog" renders as "[throw key] Pick Up Dog".
## Leave blank to inherit `data.display_name`; if both are blank the old generic "Pick Up" prompt is used.
@export var display_name: String = "":
	set(value):
		display_name = "" if value == null else String(value)

@export_group("Audio")
## Optional per-instance pickup sound. Null inherits `data.pickup_sound`; if both are null, pickup is silent.
@export var pickup_sound: AudioStream
## Optional per-instance loop while carried. Null inherits `data.held_loop_sound`; if both are null, holding is silent.
@export var held_loop_sound: AudioStream
## Optional per-instance sound when released/dropped/thrown. Null inherits `data.release_sound`; if both are null, release is silent.
@export var release_sound: AudioStream
## Optional sound for a REAL THROW — the charged Z/E-hold release or the left-click fling — played INSTEAD of
## release_sound, so a hurled knife can whip while a tap-DROP stays quiet. Null inherits `data.throw_sound`; if both
## are null a throw falls back to release_sound, exactly as before this field existed. A forced release
## (death / quickload) is never a throw, so it always uses release_sound.
@export var throw_sound: AudioStream
## Optional sound played when this prop strikes a CHARACTER (an NPC or the player) — e.g. the Dog's bite — INSTEAD of
## the generic impact thud. Null inherits `data.character_impact_sound`; if both are null, a character hit uses the
## normal impact thud. Walls/props always use the generic thud.
@export var character_impact_sound: AudioStream
## Multiplier applied to vocal one-shot sounds from this prop (pickup/release). Random-sized dogs use this so small
## dogs say/yap higher and big dogs say/yap lower; default 1.0 preserves normal throwable audio.
@export var sound_pitch_mult: float = 1.0

@export_group("Carry Pose")
## While carried, yaw this prop so its front faces back toward the player/camera. Off preserves old physics-prop rotation.
@export var face_carrier_while_held: bool = false
## REVERSE that carry pose: point the prop's front AWAY from the carrier, down your look direction, instead of back at
## you. The dog is PRESENTED to you (off — you want to see its face); a knife is held READY TO THROW, blade forward
## (on). Only meaningful with face_carrier_while_held on. Implemented by flipping the aim DIRECTION, not by adding
## another 180 to face_carrier_rotation_degrees — that field is shared with the thrown facing, where the correction is
## mandatory (the knife's Y=180 is what makes the blade lead in flight), so a rotation-based flip here would spin the
## prop in the air too. Flipping the direction also means the carried pose already MATCHES the thrown pose, so a knife
## doesn't visibly snap around when you release it.
@export var face_carrier_reversed: bool = false
## Extra local rotation, in degrees, applied after the face-carrier yaw. Add this if the mesh's authored
## front is not Godot's -Z (common fix: Y=180 for a backward-facing import). Also corrects the THROWN facing below.
@export var face_carrier_rotation_degrees: Vector3 = Vector3.ZERO

@export_group("Throw Pose")
## When THROWN (not merely dropped), continuously rotate the prop so its front noses toward its current TRAVEL
## direction — a thrown knife/spear/bottle leads with its point and tips over as it arcs. OFF by default (crates
## tumble). A plain drop, a forced release (death/quickload), and a re-grab never trigger it; only a real throw
## does. Inherits `data.face_travel_when_thrown` if a ThrowableData sets it. The mesh-front correction reuses
## `face_carrier_rotation_degrees` (same authored front axis as the carry pose).
@export var face_travel_when_thrown: bool = false
## Below this speed (m/s) the facing releases and the prop tumbles/rests naturally — so it noses through the fast
## part of the arc, then stops snapping once it lands or slows. 0 = inherit `data.face_travel_min_speed`, else the
## ~2.0 default; set a positive value to override per-instance.
@export var face_travel_min_speed: float = 0.0

@export_group("Carry Visibility")
## Whether this placed prop fades while held. Inherit uses data.fade_while_held; Fade/Opaque override just this instance.
@export_enum("Inherit", "Fade", "Opaque") var held_visibility_mode: int = HeldVisibilityMode.INHERIT

@export_group("Living Motion")
## Opt this placed prop into a subtle visual-only breathing pulse. Data can also opt in; either one enables it.
@export var breathe: bool = false
## Peak visual scale delta. 0 means inherit `data.breathe_amount` or the default 0.03.
@export var breathe_amount: float = 0.0
## Breathing sine rate. 0 means inherit `data.breathe_rate` or the default 1.6.
@export var breathe_rate: float = 0.0

@export_group("Idle Loop")
## Also play held_loop_sound (e.g. the dog's pant) when the player is NEAR this prop or LOOKING at it — not only while
## carried. So a living prop idles/pants whenever you're paying attention to it, exactly as if you were holding it. Off
## => the loop plays only while held (unchanged). Needs a held_loop_sound (instance or data) to have anything to play.
@export var loop_when_noticed: bool = false
## Play the loop when the human player is within this distance (m), any facing. 0 disables the proximity trigger.
@export var loop_near_radius: float = 3.5
## Play the loop when the player is LOOKING roughly at this prop AND within this distance (m). 0 disables the look trigger.
@export var loop_look_range: float = 12.0
## How centered the prop must be in view to count as "looking at" it: dot(camera_forward, dir_to_prop) >= this
## (~0.97 ≈ a tight crosshair cone; lower = more forgiving). Paired with loop_look_range.
@export_range(0.0, 1.0, 0.01) var loop_look_dot: float = 0.96

@export_group("Prop Setup")
## ThrowableData resource (mesh, material, mass, sounds, gib/decal flags) that defines THIS prop — assigning it pushes those into the node and overrides max_hp from data.max_hp. Null = use the node's own mesh/material/max_hp.
@export var data: ThrowableData : set = _set_data
## The AudioStreamPlayer3D that plays the impact thud (volume/pitch scaled by hit speed); also the fallback for the destroy sound. Wire to the prop's audio child.
@export var impact_sfx: AudioStreamPlayer3D
## The CollisionShape3D auto-fitted to the mesh's bounds on ready/save (unless `auto_fit_collider` is off). Wire to the prop's collider child so its shape tracks the visual size.
@export var collision_shape: CollisionShape3D:
	set(value):
		collision_shape = value
		update_configuration_warnings()
## Whether `collision_shape`'s SHAPE is resized to the visual bounds on ready/save (see _autofit_collision_shape).
## ON is right for almost every prop: the collider tracks whatever mesh the node or its ThrowableData ends up with,
## so a crate reskinned by swapping the `.tres` — or a code-built money bag — is never mis-sized.
##
## Turn it OFF to keep a HAND-AUTHORED collider that deliberately does NOT match the mesh's AABB. The auto-fit only
## rewrites the shape's SIZE; it never touches the CollisionShape3D's own transform, and a BoxShape3D is centred on
## that transform's origin. So a collider intentionally offset/rotated away from the visual centre (the meat gib's
## tilted, raised box) would be grown to the full mesh bounds while KEEPING that offset — a box poking out one side
## of the prop and missing the other. That is strictly worse than either the authored box or a clean auto-fit, which
## is why the opt-out exists rather than "just wire it and retune".
## Cost of turning it off: a ThrowableData mesh swap no longer resizes the collider, so re-author the box by hand.
## (Same field name and meaning as the `auto_fit_collider` on LookAtInteractable / Pettable / Claimable.)
@export var auto_fit_collider: bool = true
## The MeshInstance3D visual root. Data meshes are pushed onto it; data scenes mount under it so carry fade/breathing still work.
## Also what the gib despawn fade tweens (see _fade_out_for_despawn) — an unwired one makes that fade a silent no-op.
@export var mesh_instance: MeshInstance3D:
	set(value):
		mesh_instance = value
		update_configuration_warnings()
## Hit points before the prop breaks (each point of damage subtracts 1). A ThrowableData overrides this from data.max_hp. Higher = tougher prop.
@export var max_hp: int = 5
## Whether this prop can be DAMAGED/DESTROYED at all. ON by default (crates, barrels, gibs break). Turn OFF for props
## that should be indestructible — dropped weapons/items and the dog — so a stray shot or hard impact can't break them:
## take_damage no-ops entirely while off (no hp loss, no hit flash, never destroyed). A ThrowableData with
## destructible = false ALSO forces it off (see is_destructible), so an item resource can mark every instance at once.
@export var destructible: bool = true

@export_group("Tuning")
## seconds a thrown/dropped prop credits its thrower as the attacker after release (covers the flight + a bounce); then it goes inert so a crate later bumped at rest can't blame the thrower
@export var thrown_credit_grace: float = 4.0
## a grappled throwable can't hurt the grappler for this long after release
@export var grapple_damage_grace: float = 1.5
## a gib with no ground within this many metres below it counts as "mid-air"
@export var airborne_probe: float = 0.6
## a gib older than this (since spawn) no longer confettis when shot
@export var confetti_fresh_window_ms: int = 8000
## See-through factor while CARRIED (Deus Ex style): the held prop fades so it doesn't wall off the screen
## at arm's length. 0 = opaque; restored on drop/throw.
@export var carried_transparency: float = 0.4
## Flat multiplier on the impact damage this prop deals to a Character when thrown/launched (ON TOP of the
## speed-based amount and the loyal scale). 1.0 = normal. Raise per-instance for a "heavier hit" prop — the
## dropped MONEY BAG scales it with how many zorkmids it holds (a fat purse is a better bludgeon; see MoneyBag).
@export var impact_damage_mult: float = 1.0
## When set, a hit on a Character resolves as a WEAPON hit — this WeaponData's `damage`, its `headshot_multiplier`
## on a hit in the target's head zone, and its melee/ranged STAT scaling — instead of the generic speed-based prop
## impact. That is the difference between a thrown knife that STABS for what a knife swing does and one that bludgeons
## for however fast it happened to be moving; the blunt formula scales with velocity, so making a weapon fly faster
## silently made it hit far harder. The located hit is also forwarded to take_damage, so limb/zone damage applies
## exactly as it would from a swing or a shot. Null (every crate, gib and gun) keeps the blunt speed formula.
## SCOPE: the crit/headshot AND sneak multipliers apply; the BACKSTAB one does not. Sneak is in because a thrown
## weapon is a stealth verb and the numbers only work with it — the knife's 2 base damage caps out around 9 on a
## headshot against a 14 HP raider, so without the 4x an ambush throw cannot kill anyone it did not already
## wound, which is the wrong shape for the weapon. The victim's own alert state is the gate (Character.is_off_guard,
## the same predicate the hitscan and projectile paths read through DamageApplier.off_guard_for), so a target that
## has locked on takes the ordinary hit. Backstab stays out: it needs the arc between the victim's facing and the
## ATTACKER, and at the impact site the prop knows only where IT came from — a knife thrown at someone's front
## while standing behind them is not a backstab, and the prop cannot tell the difference.
## `impact_damage_mult` still multiplies the result, so that field keeps ONE meaning ("how hard this prop hits when
## thrown") on both paths. A weapon drop takes this from WeaponData.thrown_uses_weapon_damage.
@export var thrown_weapon: WeaponData = null
## Whether a LETHAL hit from this prop staples the body part it struck to the surface behind the victim, blade
## still through it (see GoreSpawner._spawn_pinned_part / GameSettings.effects "Pinned body parts"). Requires
## `thrown_weapon` — the pin needs the located weapon hit's contact point to know WHICH part was struck, and the
## blunt speed path deliberately carries no location at all. A weapon drop takes this from
## WeaponData.thrown_pins_body_part; a hand-placed prop (a spear on a rack) can set it directly.
@export var pins_body_part: bool = false
## Multiplier on the LAUNCH SPEED of a real throw: PickupRay._release scales
## GameSettings.physics_damage.pickup_throw_impulse by this before it becomes the released body's velocity. 1.0 = the
## normal throw every crate gets; raise it for something meant to be HURLED rather than lobbed (the knife leaves the
## hand several times faster than a tossed crate). Applies ONLY to a real throw — the tap-DROP impulse and the forced
## death/quickload release are never scaled, so a fast-throw prop still sets down gently. A weapon drop takes this
## from WeaponData.thrown_impulse_mult, exactly like impact_damage_mult takes thrown_impact_damage_mult.
## NOTE: raising it far enough that the prop crosses its own collider length per physics tick needs continuous
## collision detection or it tunnels through thin geometry — WorldItem stamps `continuous_cd` on a weapon drop that
## opts into a fast throw for that reason.
@export var throw_impulse_mult: float = 1.0

@export_group("Confetti Burst")
## How many confetti flecks the trick-shot burst spawns.
@export var confetti_amount: int = 48
## Seconds each confetti fleck lives.
@export var confetti_lifetime: float = 1.7
## Launch speed range (m/s) for the confetti flecks.
@export var confetti_velocity_min: float = 3.0
## Upper bound (m/s) of the confetti fleck launch-speed range; each fleck draws between min and this. Higher = the burst flies out faster/farther.
@export var confetti_velocity_max: float = 6.5
## Per-fleck scale range (multiplies the base flake mesh size).
@export var confetti_scale_min: float = 0.6
## Upper bound of the per-fleck scale range (multiplies the base flake size); each fleck draws between min and this. Higher = bigger flecks.
@export var confetti_scale_max: float = 1.3

var hp: int
var _impact_cooldown: float = 0.0
var _damage_cooldown: float = 0.0
var _outline_material: ShaderMaterial
var _flash_material: ShaderMaterial
var _flash_tween: Tween
var _pre_step_velocity: Vector3 = Vector3.ZERO
var _destroyed: bool = false
var _confetti_eligible: bool = true  ## cleared when picked up so a thrown gib can't be shot for confetti
var _spawn_msec: int = 0  ## tree-entry time; gates confetti to freshly-spawned gibs (see confetti_fresh_window_ms)
var _grapple_owner: Node = null  ## the player currently grappling/tethering this — immune to its impact damage
var _grapple_grace: float = 0.0  ## seconds the grapple owner stays immune (covers the bonk just after release)
var _thrown_by: Node = null  ## who last threw/dropped this (the player) — credited as the attacker for its impact damage so beaning an NPC with it aggros them at the thrower
var _thrown_grace: float = 0.0  ## seconds the thrower stays credited after release (ticked down in _physics_process)
var _decoy_armed: bool = false  ## armed by mark_thrown_by, consumed on the first landing -> one stealth decoy per throw (decoupled from the damage-credit timer)
var _held_loop_player: AudioStreamPlayer3D = null  ## the looping held/idle player (held_loop_sound); created on demand, follows this prop
var _held: bool = false  ## true while carried (set by on_picked_up/on_dropped); the ambient-loop driver plays the loop while held
const LOOP_NOTICED_LINGER: float = 0.5  ## seconds the noticed loop keeps playing AFTER the player stops noticing, so jitter across the near-radius / look-cone edge (walking the boundary, panning the camera) can't strobe the loop on and off
var _noticed_linger: float = 0.0  ## counts down once the player is no longer noticing; the noticed loop stops only when it reaches 0 (debounces the boundary)
var _breathe_phase: float = 0.0  ## visual-only living-prop sine phase
var _facing_travel: bool = false  ## armed by mark_thrown_for_facing (a real THROW); cleared on landing/slow/re-grab
var _breathe_base_scale: Vector3 = Vector3.ONE  ## authored mesh_instance scale; breathing pulses around this, never the collider/body
var _data_model_root: Node3D = null  ## live PackedScene visual instanced from ThrowableData.mesh, parented under mesh_instance
var _authored_mesh: Mesh = null  ## mesh_instance.mesh before data overrides, so clearing data.mesh can restore the authored visual
var _has_authored_mesh_snapshot: bool = false
## While true the outline is PINNED to _persistent_outline_color and the hover toggle (set_outline_visible, driven by
## PickupRay) can't override it — used to mark a CLAIMED prop with the blue "this is mine" rim (see Claimable /
## set_persistent_outline). Off by default so an unclaimed prop behaves exactly as before (black rim, white on hover).
var _persistent_outline_active: bool = false
var _persistent_outline_color: Color = OUTLINE_VISIBLE_COLOR
## Befriended "loyal" THROWN-combat mode (set by Claimable on befriend, cleared on release). While on, a thrown hit
## SPARES friendly/neutral NPCs (no damage) and deals _loyal_damage_mult× to hostiles. _loyal is false on every normal
## prop, so _loyal_damage_scale returns 1.0 and damage is unchanged — zero effect unless something befriends this prop.
var _loyal: bool = false
var _loyal_damage_mult: float = 1.0
var _loyal_spares_allies: bool = true

## Editor warning: a Throwable with no collider or no mesh wired is a broken prop -- the auto-fit has nothing to
## size, and nothing shows / ThrowableData can't push a mesh onto it. (impact_sfx is optional -- it falls back to
## the destroy sound, so it isn't warned.)
func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	if collision_shape == null:
		w.append("No `collision_shape` wired — no collider to auto-fit, so the prop won't collide or be throwable. Add a CollisionShape3D child and assign it.")
	if mesh_instance == null:
		w.append("No `mesh_instance` wired — the prop is invisible and ThrowableData can't push its mesh. Add a MeshInstance3D child and assign it.")
	return w

func _ready() -> void:
	_apply_data_to_visuals()
	_autofit_collision_shape()
	if Engine.is_editor_hint():
		return
	if data:
		max_hp = data.max_hp
	_cache_breathe_base_scale()
	_breathe_phase = randf() * TAU
	hp = max_hp
	_spawn_msec = Time.get_ticks_msec()
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	_setup_overlay_chain()

func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		_apply_data_to_visuals()
		_autofit_collision_shape()

func _exit_tree() -> void:
	_stop_held_loop_sound()

func _set_data(value: ThrowableData) -> void:
	data = value
	if Engine.is_editor_hint():
		_apply_data_to_visuals()
		_autofit_collision_shape()

func _apply_data_to_visuals() -> void:
	if not data:
		return
	if mesh_instance:
		_apply_data_model_resource(data.mesh)
		if data.material:
			_apply_data_material(data.material)
	if data.physics_material:
		physics_material_override = data.physics_material
	if data.mass > 0:
		mass = data.mass
	if impact_sfx and data.impact_sound:
		impact_sfx.stream = data.impact_sound

func _apply_data_model_resource(model: Resource) -> void:
	if mesh_instance == null:
		return
	_remember_authored_mesh()
	if model == null:
		_clear_data_model_root()
		mesh_instance.mesh = _authored_mesh
		return
	if model is Mesh:
		_clear_data_model_root()
		mesh_instance.mesh = model as Mesh
		return
	if model is PackedScene:
		var root: Node3D = ModelResourceUtil.instantiate(model, "ThrowableModel")
		if root == null:
			push_warning("ThrowableData mesh '%s' did not instantiate a Node3D root" % ModelResourceUtil.label(model))
			return
		_clear_data_model_root()
		mesh_instance.mesh = null
		mesh_instance.add_child(root)
		_data_model_root = root
		return
	push_warning("ThrowableData mesh '%s' must be a PackedScene or Mesh" % ModelResourceUtil.label(model))

func _remember_authored_mesh() -> void:
	if mesh_instance != null and not _has_authored_mesh_snapshot and _data_model_root == null:
		_authored_mesh = mesh_instance.mesh
		_has_authored_mesh_snapshot = true

func _clear_data_model_root() -> void:
	if is_instance_valid(_data_model_root):
		var parent := _data_model_root.get_parent()
		if parent != null:
			parent.remove_child(_data_model_root)
		_data_model_root.queue_free()
	_data_model_root = null

func _apply_data_material(material: Material) -> void:
	if mesh_instance == null:
		return
	for m in TalkHelpers.collect_meshes(mesh_instance, null, true):
		m.material_override = material

func _autofit_collision_shape() -> void:
	# Opted-out props keep the collider exactly as authored — see the `auto_fit_collider` export for why a
	# deliberately off-centre collider is made WORSE, not merely retuned, by fitting it to the mesh bounds.
	if not auto_fit_collider:
		return
	if not collision_shape or not mesh_instance:
		return
	if not collision_shape.shape:
		return
	var visual := _visual_aabb()
	if not bool(visual["has"]):
		return
	var aabb: AABB = visual["aabb"]
	# Guard a degenerate (zero / near-zero) visual AABB. mesh_instance can legitimately end up with no real bounds:
	# data.mesh is a PlaceholderMesh (an empty mesh that blanks the default box), or the prop's actual visual is
	# parented OUTSIDE mesh_instance -- the dog crate does BOTH: a PlaceholderMesh hides the box while the real
	# `dogcrate` GLB hangs as a sibling, so _visual_aabb (which only walks mesh_instance) sees nothing. Sizing the
	# collider to that empty AABB yields a (0,0,0) box: the RigidBody falls THROUGH the floor and every shot / melee
	# swing passes straight through it (it can't be damaged because nothing can touch it). This is the regression
	# the dog crate hit once _ready started applying data BEFORE auto-fitting. Bail here and keep whatever collider
	# the scene authored (the base throwable.tscn ships a 1x1x1 box), so the prop stays solid and destructible.
	var s := aabb.size
	if s.x <= AUTOFIT_MIN_EXTENT or s.y <= AUTOFIT_MIN_EXTENT or s.z <= AUTOFIT_MIN_EXTENT:
		return
	var unique_shape := collision_shape.shape.duplicate()
	if unique_shape is BoxShape3D:
		(unique_shape as BoxShape3D).size = aabb.size
	elif unique_shape is SphereShape3D:
		(unique_shape as SphereShape3D).radius = maxf(maxf(aabb.size.x, aabb.size.y), aabb.size.z) * 0.5
	elif unique_shape is CapsuleShape3D:
		(unique_shape as CapsuleShape3D).radius = maxf(aabb.size.x, aabb.size.z) * 0.5
		(unique_shape as CapsuleShape3D).height = aabb.size.y
	elif unique_shape is CylinderShape3D:
		(unique_shape as CylinderShape3D).radius = maxf(aabb.size.x, aabb.size.z) * 0.5
		(unique_shape as CylinderShape3D).height = aabb.size.y
	collision_shape.shape = unique_shape

func _visual_aabb() -> Dictionary:
	var state := {"has": false, "aabb": AABB()}
	_collect_visual_aabb(mesh_instance, Transform3D.IDENTITY, state)
	return state

func _collect_visual_aabb(node: Node, xf: Transform3D, state: Dictionary) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var local_aabb := xf * mi.mesh.get_aabb()
			var current: AABB = state["aabb"]
			state["aabb"] = local_aabb if not bool(state["has"]) else current.merge(local_aabb)
			state["has"] = true
	for child in node.get_children():
		var child_xf := xf
		if child is Node3D:
			child_xf = xf * (child as Node3D).transform
		_collect_visual_aabb(child, child_xf, state)

func _setup_overlay_chain() -> void:
	_flash_material = ShaderMaterial.new()
	_flash_material.shader = FLASH_OVERLAY_SHADER
	_flash_material.set_shader_parameter("flash_strength", 0.0)
	_outline_material = ShaderMaterial.new()
	_outline_material.shader = OUTLINE_SHADER
	_outline_material.set_shader_parameter("outline_color", OUTLINE_HIDDEN_COLOR)
	# outline_width = 1.0 IS the shipped look (the chunky shell): this code previously set a non-existent
	# `outline_thickness` uniform (the same latent no-op talk_helpers.gd documents) plus a dead
	# `use_smooth_normals` toggle, so the shader's 1.0 DEFAULT is what has always rendered. Codified
	# explicitly so a future shader-default change can't silently restyle every throwable. (The old
	# smooth-normal vertex-colour bake was authored for an outline shader that never shipped — the live
	# shader reads only NORMAL — so the whole mesh-rebuild pass was dead work and is gone; see git.)
	_outline_material.set_shader_parameter("outline_width", 1.0)
	_outline_material.next_pass = _flash_material
	var targets := TalkHelpers.collect_meshes(self, null, true)
	for m in targets:
		m.material_overlay = _outline_material

# `want_visible` is a sentinel-defaulted Variant, not `bool = visible`: a default expression is captured at
# the DECLARING node's scope, so `= visible` would bake in THIS Throwable's visible flag (semantically
# wrong — the outline shows on hover, not when the prop is shown) rather than tracking the call-time intent.
# With the null sentinel a no-arg call falls back to the node's CURRENT `visible` at call time; the callers
# (ray_cast.gd) pass an explicit bool, which is used as-is.
func set_outline_visible(want_visible = null) -> void:
	if not _outline_material:
		return
	# A claimed prop PINS its rim colour (the blue "mine" outline) — the hover toggle PickupRay drives can't override
	# it, so the dog reads as yours whether or not you're aiming at it. clear_persistent_outline() lifts the pin.
	if _persistent_outline_active:
		_outline_material.set_shader_parameter("outline_color", _persistent_outline_color)
		return
	var want: bool = bool(want_visible) if want_visible != null else visible
	_outline_material.set_shader_parameter(
		"outline_color",
		OUTLINE_VISIBLE_COLOR if want else OUTLINE_HIDDEN_COLOR
	)

## Pin a persistent outline colour on this prop, shown regardless of hover (set_outline_visible's toggle is overridden
## while active). Used to mark a CLAIMED prop with the blue companion rim so it reads as "mine" at a glance — the same
## blue an NPC companion wears (NPC.OUTLINE_FOLLOWING). Applied immediately. clear_persistent_outline() lifts it.
func set_persistent_outline(color: Color) -> void:
	_persistent_outline_active = true
	_persistent_outline_color = color
	if _outline_material:
		_outline_material.set_shader_parameter("outline_color", color)

## Lift the persistent outline, restoring the HIDDEN (default) rim. We deliberately do NOT restore the white "hovered"
## look here: the claimed rim is driven by ClaimInteraction's ray, which is INDEPENDENT of the PickupRay that owns the
## hover toggle (different reach / aim-sway / hitbox), so an unclaim can complete on a frame when PickupRay is NOT
## targeting this prop — pinning white there would leave a stuck "highlighted" rim on a prop you're not even looking
## at. Hidden is the safe default; PickupRay repaints white on the next genuine hover (the target then changes, so its
## toggle fires). The only cost is no white rim for the rest of an in-place hover right after release — it self-heals
## the next time you look away and back.
func clear_persistent_outline() -> void:
	_persistent_outline_active = false
	if _outline_material:
		_outline_material.set_shader_parameter("outline_color", OUTLINE_HIDDEN_COLOR)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _impact_cooldown > 0.0:
		_impact_cooldown -= delta
	if _damage_cooldown > 0.0:
		_damage_cooldown -= delta
	if _grapple_grace > 0.0:
		_grapple_grace -= delta
		if _grapple_grace <= 0.0:
			_grapple_owner = null
	if _thrown_grace > 0.0:
		_thrown_grace -= delta
		if _thrown_grace <= 0.0:
			_thrown_by = null
	_animate_breathing(delta)
	_update_ambient_loop(delta)
	_pre_step_velocity = linear_velocity

## Continuous "face travel direction" for a THROWN prop (see face_travel_when_thrown). A no-op unless _facing_travel
## is armed, so a normal prop's physics is untouched. _integrate_forces is the engine-sanctioned place to override a
## dynamic body's rotation each physics step: aim the model front along the CURRENT velocity (matching the
## look_at / face_carrier -Z front convention + the same mesh-front offset) and zero the spin so tumbling can't
## fight it. Releases itself once the prop slows below face_travel_min_speed (landed / at rest), after which it
## tumbles and settles naturally. Frozen/sleeping bodies never integrate, so a held or resting prop is unaffected.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not _facing_travel:
		return
	var vel := state.linear_velocity
	if vel.length() < _resolved_face_travel_min_speed():
		_facing_travel = false  # landed / slowed — hand it back to physics to tumble and rest
		return
	var prop_scale := state.transform.basis.get_scale()  # preserve an authored non-unit scale
	var xf := state.transform
	xf.basis = travel_facing_basis(vel.normalized()).scaled(prop_scale)
	state.transform = xf
	state.angular_velocity = Vector3.ZERO

## The rotation this prop wears when nosing along `dir` — its authored front pointed down that direction, with the
## same mesh-front correction the carry pose applies (face_carrier_rotation_degrees; the knife's Y=180 is what makes
## the BLADE lead instead of the hilt). Split out of _integrate_forces so the thrown facing has ONE home: the pin
## seat (BodyPartGib._seat, which parks an embedded blade at an authored pose rather than letting physics aim it)
## needs the identical basis, and a second copy of this would be a silently-hilt-first bug waiting to happen.
func travel_facing_basis(dir: Vector3) -> Basis:
	if dir.length_squared() < 0.000001:
		return global_basis.orthonormalized()
	var d := dir.normalized()
	# look_at degenerates when the travel is straight up/down; swap the up hint so the basis stays valid.
	var up := Vector3.UP if absf(d.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	var aimed := Basis.looking_at(d, up)  # -Z points along dir, matching look_at / face_carrier
	var offset := _face_carrier_offset_radians()
	if offset != Vector3.ZERO:
		aimed = aimed * Basis.from_euler(offset)  # same mesh-front correction the carry pose uses
	return aimed.orthonormalized()

## This prop's collider SIZE as full extents on each axis, in its own local frame — what the pin geometry measures
## to seat a body flush against a surface (PartPinner.support_along). Covers the four shape kinds the auto-fit
## writes (see _autofit_collision_shape); anything else, or no collider at all, reports ZERO, which seats the body
## exactly on the surface point — visibly shallow rather than NaN or a wild offset.
func collider_size() -> Vector3:
	if collision_shape == null or collision_shape.shape == null:
		return Vector3.ZERO
	var s := collision_shape.shape
	if s is BoxShape3D:
		return (s as BoxShape3D).size
	if s is SphereShape3D:
		var d: float = (s as SphereShape3D).radius * 2.0
		return Vector3(d, d, d)
	if s is CapsuleShape3D:
		var cap := s as CapsuleShape3D
		return Vector3(cap.radius * 2.0, cap.height, cap.radius * 2.0)
	if s is CylinderShape3D:
		var cyl := s as CylinderShape3D
		return Vector3(cyl.radius * 2.0, cyl.height, cyl.radius * 2.0)
	return Vector3.ZERO

func _on_body_entered(body: Node) -> void:
	var my_speed := _pre_step_velocity.length()
	var their_speed := 0.0
	if body is RigidBody3D:
		their_speed = (body as RigidBody3D).linear_velocity.length()
	elif body is CharacterBody3D:
		their_speed = (body as CharacterBody3D).velocity.length()
	var impact_speed := maxf(my_speed, their_speed)
	_play_impact(body, impact_speed)
	_emit_decoy_noise()  # stealth: a thrown decoy prop drops a lure-noise where it lands
	_try_damage_character(body, my_speed)
	_try_self_damage(impact_speed)

func _try_damage_character(body: Node, my_speed: float) -> void:
	if not body is Character:
		return
	var character := body as Character
	# Gore gibs (data.damages_player = false) don't hurt the PLAYER — being pelted by your own kill's
	# flying chunks shouldn't chip your health. Other characters still take impact damage.
	if character.is_in_group(Groups.PLAYER) and data and not data.damages_player:
		return
	# A throwable the player is grappling (or just released) must not hurt the grappler: reeling a crate
	# toward yourself, or slamming into a tethered one and shoving it back into you, shouldn't chip your HP.
	if _grapple_grace > 0.0 and body == _grapple_owner:
		return
	# A befriended ("loyal") prop is the player's — it SPARES friendly/neutral NPCs entirely (no damage, no blood, no
	# cooldown burned) and hits HOSTILE NPCs harder. scale is 1.0 for every non-befriended prop, so normal throwables
	# are completely unaffected. Resolved per-hit from the target's LIVE disposition (a provoked neutral reads hostile).
	var damage_scale := _loyal_damage_scale(character)
	if damage_scale <= 0.0:
		return
	if _damage_cooldown > 0.0:
		return
	# Shared speed gate on BOTH paths: a prop resting against someone, or nudged into them at walking pace, never
	# hurts. A knife has to actually be travelling to stab.
	if my_speed < GameSettings.physics_damage.interactable_damage_min_velocity:
		return
	# Credit the thrower (or grappler) as the attacker so beaning an NPC with a thrown prop counts as the
	# player attacking it — the NPC provokes and rounds on you, same as a gunshot.
	var attacker := _credited_attacker()
	var was_crit := false
	# Vector3.INF is take_damage's "un-located hit" sentinel: a tumbling crate rolls no limb/zone damage. The WEAPON
	# path below replaces it with a real contact point, so a thrown blade wounds a limb exactly as a swing would.
	var hit_pos := Vector3.INF
	var damage: float
	if thrown_weapon != null:
		# WEAPON hit: the prop IS a weapon, so it deals what that weapon deals rather than a velocity-derived bludgeon.
		# Approximation worth naming: `global_position` is the prop's ORIGIN, not the true contact manifold (Godot's
		# body_entered carries no contact point). For a slender weapon whose collider is centred on its model that
		# lands within a few cm of the strike, which is inside the head-zone granularity is_headshot tests against.
		hit_pos = global_position
		# The player is immune to headshots from NPCs (a one-shot to the head feels cheap) — the SAME rule the hitscan
		# and projectile paths use, applied here through the same helper rather than re-derived.
		var from_ai := attacker != null and not attacker.is_in_group(Groups.PLAYER)
		was_crit = character.is_headshot(hit_pos) and ShotResolver.crit_allowed(character, from_ai)
		# The thrower's own stat sheet scales it, so a thrown knife tracks STRENGTH exactly like a knife swing.
		var thrower_stats: CharacterStats = (attacker as Character).stats_or_default() if attacker is Character else null
		# SNEAK: a victim that hasn't locked on takes the ambush multiplier — see thrown_weapon's docstring for why
		# it's in and backstab still isn't. Read off the victim directly rather than through
		# DamageApplier.off_guard_for (identical rule, minus an `is Character` test we have already passed):
		# DamageApplier type-refs Throwable in hp_before, so reaching back would close a class_name parse cycle.
		var off_guard := character.is_off_guard()
		damage = ShotResolver.scaled_damage(
			thrown_weapon.damage, thrown_weapon.headshot_multiplier, thrown_weapon.sneak_attack_multiplier,
			was_crit, off_guard, thrown_weapon.backstab_multiplier, false,
			thrower_stats, 0.0, thrown_weapon.is_melee, 0.0)
		damage *= damage_scale * impact_damage_mult
		# The same sneak-or-not toast the hitscan path shows (damage_trace.gd), so a thrown ambush reads as one
		# instead of silently paying four times the damage. Player throws only — an NPC has no such method.
		if attacker != null and attacker.is_in_group(Groups.PLAYER) and attacker.has_method(&"notify_sneak_result"):
			attacker.call(&"notify_sneak_result", off_guard)
	else:
		damage = roundf((my_speed - GameSettings.physics_damage.interactable_damage_min_velocity) * GameSettings.physics_damage.interactable_damage_per_m_per_s)
		damage = roundf(damage * damage_scale * impact_damage_mult)  # impact_damage_mult: 1.0 for a normal prop; a money bag scales it with its zorkmids
	if damage <= 0.0:
		return
	EffectFactory.spawn_blood_particle(character.global_position)
	if character.get("bloody_mess"):
		var dir := _pre_step_velocity if _pre_step_velocity.length() > 0.01 else Vector3.UP
		character.bloody_mess.splatter_at(character.global_position, dir)
	var hp_before := character.hp
	# PIN INTENT — stashed on the victim IMMEDIATELY before the lethal hit, the NPC.mark_silent_takedown idiom,
	# because the decision cannot be threaded as an argument: take_damage -> _begin_death -> (a SceneTree timer, for
	# the death-freeze beat) -> _complete_death -> gore() -> GoreSpawner is a dozen signatures and crosses a timer
	# boundary. Marked UNCONDITIONALLY rather than predicting lethality here (armour, difficulty and DR all move the
	# number after we hand it over); Character clears it again on the survive branch, and on pooled reuse.
	# `hit_pos` is the SAME point the damage classified against, so a strike never carries two contact points.
	if pins_body_part and thrown_weapon != null and _pre_step_velocity.length() > 0.01:
		var throw_dir := _pre_step_velocity.normalized()
		var surface := _probe_pin_surface(hit_pos, throw_dir, character)
		if not surface.is_empty():
			character.mark_pin_hit(hit_pos, throw_dir, self, surface)
	character.take_damage(damage, was_crit, attacker, hit_pos)
	var hp_after := character.hp if is_instance_valid(character) else 0.0
	var real_loss := hp_before - hp_after
	DamageNumberPopupScript.show(character, real_loss, global_position, was_crit, attacker)
	_damage_cooldown = GameSettings.physics_damage.interactable_damage_cooldown

## Enter/exit "loyal" thrown-combat mode — called by Claimable on befriend / release. While on, a THROWN hit spares
## FRIENDLY+NEUTRAL NPCs (no damage) and multiplies damage to HOSTILE NPCs by `damage_mult`; `spares_allies` off makes
## it hit everyone (hostiles still get the multiplier). Off restores normal throwable damage to all characters.
func set_loyal_combat(enabled: bool, damage_mult: float = 1.0, spares_allies: bool = true) -> void:
	_loyal = enabled
	_loyal_damage_mult = maxf(0.0, damage_mult)
	_loyal_spares_allies = spares_allies

## Per-hit damage multiplier for THIS prop hitting `character`, or 0.0 to SPARE it. Resolves the target's NPC-ness +
## live hostility, then delegates to the pure static loyal_scale() (so the policy is unit-testable). The human player
## has no resolved_disposition() (the data.damages_player guard above governs it), so loyalty never alters the player.
func _loyal_damage_scale(character: Character) -> float:
	var is_npc := character.has_method(&"resolved_disposition")
	# `: bool` annotation: resolved_disposition() is a dynamic call (Character doesn't declare it), so the comparison is
	# Variant-typed and `:=` can't infer. Short-circuit on is_npc so the call only fires on an actual NPC.
	var is_hostile: bool = is_npc and character.resolved_disposition() == Disposition.Kind.HOSTILE
	return loyal_scale(_loyal, is_npc, is_hostile, _loyal_damage_mult, _loyal_spares_allies)

## Pure damage-scale policy (static + literal-arg so it's unit-testable, mirroring Pettable.eligible): a non-loyal prop
## always returns 1.0 (normal throwables unchanged); a loyal prop returns the multiplier vs a hostile NPC, 0.0 to spare
## a non-hostile NPC (unless spares_allies is off → 1.0), and 1.0 for a non-NPC (the player).
static func loyal_scale(loyal: bool, is_npc: bool, is_hostile: bool, damage_mult: float, spares_allies: bool) -> float:
	if not loyal:
		return 1.0
	if not is_npc:
		return 1.0
	if is_hostile:
		return damage_mult
	return 0.0 if spares_allies else 1.0

func _try_self_damage(impact_speed: float) -> void:
	if impact_speed < GameSettings.physics_damage.interactable_self_damage_min_velocity:
		return
	var dmg := int(roundf((impact_speed - GameSettings.physics_damage.interactable_self_damage_min_velocity) * GameSettings.physics_damage.interactable_self_damage_per_m_per_s))
	if dmg <= 0:
		return
	take_damage(dmg)

## Mark this throwable as currently grappled/tethered by `by` (the player). While grappled — and for a
## short grace after release — it deals NO impact damage to that player (see _try_damage_character).
## Refreshed each frame the grapple holds it, so the grace only starts counting down once released.
func mark_grappled_by(by: Node) -> void:
	_grapple_owner = by
	_grapple_grace = grapple_damage_grace

## Mark this throwable as just THROWN (or dropped) by `by` (the player). For a short grace after, any impact
## damage it deals to a Character credits `by` as the attacker — so beaning an NPC with a thrown crate aggros
## them at the thrower, exactly like shooting them. After the grace the prop is inert again.
func mark_thrown_by(by: Node) -> void:
	_thrown_by = by
	_thrown_grace = thrown_credit_grace
	_decoy_armed = true  # arm a fresh stealth decoy for THIS throw's first strike (its own flag, NOT the damage timer)

## Whether this prop noses toward its travel direction when thrown — the per-instance toggle OR a ThrowableData
## that opts in (mirrors faces_carrier_while_held). Read by mark_thrown_for_facing.
func faces_travel_when_thrown() -> bool:
	return face_travel_when_thrown or (data != null and data.face_travel_when_thrown)

## The resolved thrown-facing release speed: a per-instance override (> 0) wins, else the ThrowableData value
## (> 0), else the default. Mirrors _resolved_breathe_amount so the whole Throw Pose group is authorable on the
## resource. Read by _integrate_forces.
func _resolved_face_travel_min_speed() -> float:
	if face_travel_min_speed > 0.0:
		return face_travel_min_speed
	if data != null and data.face_travel_min_speed > 0.0:
		return data.face_travel_min_speed
	return DEFAULT_FACE_TRAVEL_MIN_SPEED

## Arm "face travel direction" — called by the PickupRay (ray_cast.gd) / grapple ONLY on a real THROW (a
## high-impulse fling), never a tap-drop or a forced release. Arms only when the toggle (instance or data) is on;
## _integrate_forces then noses the prop toward its velocity until it slows below face_travel_min_speed.
func mark_thrown_for_facing() -> void:
	_facing_travel = faces_travel_when_thrown()

# --- Embedded (pinned) blade ---------------------------------------------------------------------------------
#
# A knife that landed a PIN kill ends up driven into the wall through the limb it carried there. Physically that
# is just "frozen at an authored pose", but the release has to be handled carefully: the collider is deliberately
# buried in static geometry while pinned, and clearing `freeze` on a body that overlaps a wall lets the solver's
# depenetration fire it across the room. So unpin() restores the free pose FIRST and only then goes dynamic.
# Driven by BodyPartGib (which owns the limb this blade is through) — it pins on seating and unpins on despawn.

var _pinned: bool = false
var _pin_free_position: Vector3 = Vector3.ZERO  ## where to put the body before it goes dynamic again — clear of the surface
var _pin_prior_gravity: float = 1.0

## Look for the surface to staple a body part to: straight on down the throw, from the strike. Returns
## {"point", "normal", "collider"} or {} when there is nothing worth pinning to (open ground behind them, or only
## a graze — see PartPinner.surface_accepts).
##
## ⚠️ THIS MUST RUN AT STRIKE TIME, AND THAT IS THE WHOLE REASON IT LIVES HERE RATHER THAN IN GoreSpawner, WHERE
## THE REST OF THE PIN LOGIC IS. `PhysicsDirectSpaceState3D` is only valid to query DURING the physics frame, and
## the death burst does not run in one: an NPC's gore() is fired from the death-freeze SceneTreeTimer, whose
## timeout lands on the IDLE frame, so a raycast there returns an empty result no matter what is standing in
## front of it. That silently made the pin unreachable in the shipped build — every other seam correct, the probe
## finding a wall exactly never. `_on_body_entered` IS a physics callback (`_is_airborne` already ray-queries
## from this same path), so the answer found here is real; it rides along in the marker to be spent later.
func _probe_pin_surface(from: Vector3, dir: Vector3, victim: Node) -> Dictionary:
	if not is_inside_tree():
		return {}
	var fx := GameSettings.effects
	if not fx.pinned_parts_enabled:
		return {}
	var space := get_world_3d().direct_space_state
	if space == null:
		return {}
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * fx.pinned_part_probe_distance, fx.pinned_part_probe_mask)
	# Exclude ourselves and the body we just struck, plus every live gib — a previous kill's limb lying between
	# this victim and the wall would otherwise BE the "surface", and the pin would hang off a despawning chunk.
	var excluded: Array[RID] = [get_rid()]
	var victim_body := victim as CollisionObject3D
	if victim_body != null:
		excluded.append(victim_body.get_rid())
	for g in get_tree().get_nodes_in_group(Groups.GIB):
		var body := g as CollisionObject3D
		if body != null:
			excluded.append(body.get_rid())
	query.exclude = excluded
	var res := space.intersect_ray(query)
	if res.is_empty():
		return {}
	if not PartPinnerScript.surface_accepts(res["normal"], dir, fx.pinned_part_max_surface_angle):
		return {}
	return {"point": res["position"], "normal": res["normal"], "collider": res["collider"]}

## True while this prop is embedded in a surface. Read by PickupRay so a grab can release it first.
func is_pinned() -> bool:
	return _pinned

## Park this prop, frozen, at `pose` — the embedded blade. `free_position` is where unpin() will put it before it
## goes dynamic again: somewhere its collider is clear of the surface it is buried in. STATIC (not KINEMATIC)
## freeze on purpose: a kinematic frozen body is code-moved and PUSHES what it touches, and this one is
## deliberately overlapping a wall. The collision layer is deliberately LEFT ALONE so the prop stays solid — that
## is what lets PickupRay's aim ray still find it, which is the whole retrieval beat.
func pin_at(pose: Transform3D, free_position: Vector3) -> void:
	if _pinned or _held or not is_inside_tree():
		return
	_pinned = true
	_pin_free_position = free_position
	_pin_prior_gravity = gravity_scale
	_facing_travel = false  # the flight is over; nothing left for _integrate_forces to nose toward
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	gravity_scale = 0.0
	global_transform = pose
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true

## Release the embedded prop back to normal physics — it drops out of the wall. Called when the limb it is
## through despawns, and by PickupRay the moment the player grabs it.
## Two guards, both load-bearing:
##   * not _pinned — the despawn path and the pickup path can both reach here for one blade, and the second must
##     not stomp physics state the first already handed back.
##   * _held — while carried, PickupRay OWNS this body's freeze / gravity / layer and restores its own snapshot
##     on release; writing freeze here would drop a carried knife out of the player's hands mid-carry.
func unpin() -> void:
	if not _pinned:
		return
	_pinned = false
	if _held:
		return
	if is_inside_tree():
		global_position = _pin_free_position  # clear of the surface BEFORE going dynamic — see the block comment
	freeze = false
	gravity_scale = _pin_prior_gravity
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

## Who to blame for this prop's impact damage right now: whoever just threw it (within the throw grace),
## else whoever is grappling / just released it (a tethered slam is a deliberate hit too), else no-one — a
## stray bump while at rest credits nobody, so it can't wrongly aggro an NPC at the player.
func _credited_attacker() -> Node:
	if is_instance_valid(_thrown_by) and _thrown_grace > 0.0:
		return _thrown_by
	if is_instance_valid(_grapple_owner) and _grapple_grace > 0.0:
		return _grapple_owner
	return null

## Stealth "thrown decoy": on the FIRST strike after a deliberate throw, drop a one-shot NoiseSource at that
## spot so NPCs that hear it (GameSettings.npc_ai.hearing_initiates) come investigate -- "lob a rock to lure a
## guard." Gated on _decoy_armed (set ONLY by mark_thrown_by, consumed here) so a crate bumped at REST never
## lures and a later bounce can't re-emit, while a slow lob still fires whenever it finally lands -- the arming
## is its OWN flag, decoupled from the damage-credit timer (_thrown_grace). Off unless the prop's ThrowableData
## has noise_on_land. The node lives in the world (self-freeing via lifetime), NOT under us, so picking the prop
## back up can't cut the sound short; the lifetime is floored positive so a decoy is never persistent.
## NOTE: "first strike" is the first body contact (usually the ground landing, but a wall/prop clang counts too).
func _emit_decoy_noise() -> void:
	if data == null or not data.noise_on_land:
		return
	if not _decoy_armed:
		return  # only the first strike of a deliberate throw — not a resting bump or a later bounce
	if not is_inside_tree():
		return
	_decoy_armed = false
	var cfg := data.resolved_decoy(GameSettings.distraction)
	var src := NoiseSource.new()
	src.radius = float(cfg[&"radius"])
	src.decay = float(cfg[&"decay"])
	src.lifetime = maxf(float(cfg[&"lifetime"]), MIN_DECOY_LIFETIME)  # always one-shot — never a persistent (leaking) source
	get_tree().root.add_child(src)
	src.global_position = global_position

## Mark this throwable as a GORE GIB with a limited lifetime: register it in the &"gib" group (for the
## spawn-time cap in GoreSpawner), wait `lifetime` seconds, then fade the mesh out over `fade` and free
## itself — so gibs don't pile up forever (mirrors the ragdoll corpse timeout). Only gore gibs call this;
## crates / other throwables never do, so they persist as before.
func begin_gib_lifetime(lifetime: float, fade: float) -> void:
	add_to_group(Groups.GIB)
	await get_tree().create_timer(lifetime).timeout
	# Never despawn a gib that's currently being CARRIED: fading it to invisible and freeing it out of the player's
	# hands looks like it vanished in your grip, and a held prop freed mid-carry used to strand the player (the gun
	# holstered + draw-locked with a dead held reference). Wait until it's been dropped; a re-grab re-defers. `_held`
	# is set by on_picked_up and cleared by on_dropped -- including the death / quickload force-release -- so a gib
	# carried past its lifetime simply lives on in your hands, then fades + frees like any other once released.
	while _held and not _destroyed and is_inside_tree():
		await get_tree().create_timer(GIB_HELD_DESPAWN_RECHECK).timeout
	if _destroyed or not is_inside_tree():
		return  # already shot apart / culled / freed during the wait
	_destroyed = true  # claim it so a stray hit mid-fade can't also run _destroy()
	await _fade_out_for_despawn(fade)
	if is_inside_tree():
		queue_free()

## The despawn fade, split out as an OVERRIDABLE seam. Base: tween the wired mesh_instance's transparency --
## correct for a gib whose whole visual IS that one MeshInstance3D. A subclass whose visual is a SUBTREE
## under the mount point must override it, because GeometryInstance3D.transparency is per-instance and does
## NOT propagate to children (BodyPartGib, which flies a real limb, does exactly that). Always awaited, so an
## override may take as long as `fade`; queue_free happens after it returns.
func _fade_out_for_despawn(fade: float) -> void:
	if mesh_instance == null:
		return
	var tw := create_tween()
	tw.tween_property(mesh_instance, "transparency", 1.0, fade)
	await tw.finished

## Route the impact SFX: striking a CHARACTER (NPC/player) with a configured character_impact_sound plays THAT (the
## Dog's bite) instead of the generic body-thud; everything else (walls, props) — and any prop without a character
## sound — uses the normal impact_sfx thud. Backward-compatible: a prop with no character sound thuds on everything
## exactly as before.
func _play_impact(body: Node, speed: float) -> void:
	if body is Character and _character_impact_sound() != null:
		_play_character_impact(speed)
	else:
		on_impact(speed)

## Play the character-impact sound (e.g. the Dog's bite) positionally at the prop, scaled by hit speed like the
## generic thud and sharing the same _impact_cooldown so a bite and a thud can't double up. AudioManager.play_sfx
## spawns a SELF-FREEING one-shot, so the sound survives the prop being picked up / destroyed right after the hit.
func _play_character_impact(speed: float) -> void:
	var stream := _character_impact_sound()
	if stream == null or not is_inside_tree():
		return
	if _impact_cooldown > 0.0:
		return
	if speed < GameSettings.physics_damage.interactable_impact_min_velocity:
		return
	var span := maxf(GameSettings.physics_damage.interactable_impact_max_velocity - GameSettings.physics_damage.interactable_impact_min_velocity, 0.001)
	var t := clampf((speed - GameSettings.physics_damage.interactable_impact_min_velocity) / span, 0.0, 1.0)
	var vol := lerpf(GameSettings.physics_damage.interactable_impact_min_db, GameSettings.physics_damage.interactable_impact_max_db, t)
	var pitch := 1.0 + randf_range(-GameSettings.physics_damage.interactable_impact_pitch_spread, GameSettings.physics_damage.interactable_impact_pitch_spread)
	AudioManager.play_sfx(global_position, stream, vol, pitch)
	_impact_cooldown = GameSettings.physics_damage.interactable_impact_cooldown

func on_impact(speed: float) -> void:
	if not impact_sfx:
		return
	if _impact_cooldown > 0.0:
		return
	if speed < GameSettings.physics_damage.interactable_impact_min_velocity:
		return
	var span := GameSettings.physics_damage.interactable_impact_max_velocity - GameSettings.physics_damage.interactable_impact_min_velocity
	var t := clampf((speed - GameSettings.physics_damage.interactable_impact_min_velocity) / span, 0.0, 1.0)
	impact_sfx.volume_db = lerpf(GameSettings.physics_damage.interactable_impact_min_db, GameSettings.physics_damage.interactable_impact_max_db, t)
	impact_sfx.pitch_scale = 1.0 + randf_range(-GameSettings.physics_damage.interactable_impact_pitch_spread, GameSettings.physics_damage.interactable_impact_pitch_spread)
	impact_sfx.play()
	_impact_cooldown = GameSettings.physics_damage.interactable_impact_cooldown

## Whether this prop can be damaged right now: the instance toggle AND (if a ThrowableData is assigned) its toggle —
## EITHER set to false makes the prop indestructible (fail-safe toward "can't be destroyed"). Read by take_damage.
func is_destructible() -> bool:
	return destructible and (data == null or data.destructible)

func take_damage(amount: int, _was_crit: bool = false, attacker: Node = null) -> void:
	if _destroyed:
		return
	if not is_destructible():
		return  # indestructible prop (a dropped item / the dog): no hp loss, no hit flash, can't be destroyed
	hp -= amount
	_flash_red()
	if hp <= 0:
		_destroy(attacker)

func _flash_red() -> void:
	if not _flash_material:
		return
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_material, "shader_parameter/flash_strength", FLASH_PEAK_STRENGTH, FLASH_UP_TIME)
	_flash_tween.tween_property(_flash_material, "shader_parameter/flash_strength", 0.0, FLASH_DOWN_TIME)

signal destroyed

func _destroy(attacker: Node = null) -> void:
	destroyed.emit()
	_destroyed = true
	_wake_contacts()
	_spawn_destroy_particle()
	_spawn_destroy_decal()
	_shake_nearby_screens()
	_play_destroy_sound()
	# Bonus on TOP of the normal gore (blood + splosh still play): a gib the PLAYER shoots out of the air
	# right after it bursts from a kill gets a celebratory confetti pop + party horn. Picked-up/thrown or
	# stale gibs are disqualified (anti-cheese); crates never qualify.
	if _is_confetti_kill(attacker):
		EffectFactory.spawn_blood_particle(global_position)  # a clear blood burst too — confetti is ON TOP of the gore
		_spawn_confetti()
		AudioManager.play_sfx(global_position, PARTY_HORN, 0.0, 1.0)  # 3D positional one-shot
		# The trick shot PAYS (size: resources/tuning/EconomySettings.tres). Rides the exact same
		# anti-cheese gate as the confetti itself (fresh off a kill, never picked up/thrown, airborne),
		# so the bounty can't be farmed with tossed or stale gibs.
		var confetti_pay: float = GameSettings.economy.confetti_bounty
		if confetti_pay > 0.0 and attacker != null and attacker.has_method(&"reward_kill"):
			attacker.reward_kill(confetti_pay)
			if attacker.has_method(&"notify_toast"):
				attacker.notify_toast(PlayerText.confetti(confetti_pay), Color(1.0, 0.86, 0.3))
	queue_free()

## True only for a gore gib that the PLAYER shot while it was airborne — the confetti trick-shot trigger.
func _is_confetti_kill(attacker: Node) -> bool:
	if data == null or not data.is_gib:
		return false
	if not _confetti_eligible:
		return false  # already picked up / thrown -- no cheesing confetti with a tossed gib
	if Time.get_ticks_msec() - _spawn_msec >= confetti_fresh_window_ms:
		return false  # only a gib fresh off a kill qualifies, not one that's been lying around
	if attacker == null or not attacker.is_in_group(Groups.PLAYER):
		return false
	return _is_airborne()

## True if nothing solid sits just below us — i.e. the prop is in flight, not resting on a surface.
func _is_airborne() -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3.DOWN * airborne_probe)
	query.exclude = [get_rid()]
	return space.intersect_ray(query).is_empty()

## Burst of multicolour confetti flecks at our position — a self-freeing, code-built GPUParticles3D
## (one-shot). Each fleck draws a random colour from a rainbow ramp (color_initial_ramp) and tumbles.
func _spawn_confetti() -> void:
	var p := GPUParticles3D.new()
	get_tree().root.add_child(p)
	p.global_position = global_position
	p.amount = confetti_amount
	p.lifetime = confetti_lifetime
	p.one_shot = true
	p.explosiveness = 1.0
	p.speed_scale = 1.3
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
	grad.colors = PackedColorArray([
		Color(0.95, 0.20, 0.25), Color(0.98, 0.62, 0.12), Color(0.97, 0.90, 0.20),
		Color(0.22, 0.82, 0.30), Color(0.20, 0.55, 0.95), Color(0.70, 0.30, 0.90),
	])
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	var ppm := ParticleProcessMaterial.new()
	ppm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	ppm.emission_sphere_radius = 0.12
	ppm.direction = Vector3(0.0, 1.0, 0.0)
	ppm.spread = 120.0
	ppm.initial_velocity_min = confetti_velocity_min
	ppm.initial_velocity_max = confetti_velocity_max
	ppm.gravity = Vector3(0.0, -9.0, 0.0)
	ppm.angular_velocity_min = -540.0
	ppm.angular_velocity_max = 540.0
	ppm.scale_min = confetti_scale_min
	ppm.scale_max = confetti_scale_max
	ppm.color_initial_ramp = grad_tex
	ppm.turbulence_enabled = true
	ppm.turbulence_noise_strength = 2.2
	ppm.turbulence_noise_scale = 1.4
	p.process_material = ppm
	var flake := BoxMesh.new()
	flake.size = Vector3(0.06, 0.06, 0.012)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	flake.material = mat
	p.draw_pass_1 = flake
	p.emitting = true
	p.finished.connect(p.queue_free)

func _spawn_destroy_decal() -> void:
	# Leave a scorch/blast decal on the floor below, oriented to the surface.
	# Covers destruction by any means (shot, explosion, ram). Opt-out via the
	# data resource's spawns_destroy_decal (gibs disable it — they bleed instead).
	if data and not data.spawns_destroy_decal:
		return
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + Vector3.DOWN * DESTROY_DECAL_PROBE
	)
	query.exclude = [get_rid()]
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return
	var decal = DESTROY_DECAL.instantiate()
	get_tree().root.add_child(decal)
	decal.size = DESTROY_DECAL_SIZE
	decal.cull_mask = DESTROY_DECAL_CULL_MASK
	var normal: Vector3 = result["normal"]
	decal.global_position = result["position"] + normal * GameSettings.effects.decal_normal_offset
	var up := normal
	var z: Vector3
	if absf(up.dot(Vector3.UP)) > DESTROY_DECAL_PARALLEL_THRESHOLD:
		z = Vector3.FORWARD.slide(up).normalized()
	else:
		z = Vector3.UP.slide(up).normalized()
	var x := up.cross(z).normalized()
	decal.global_transform.basis = Basis(x, up, z)

func _wake_contacts() -> void:
	# Wake any rigid bodies currently in contact so a stack of crates above
	# this one falls correctly when the supporting box is destroyed.
	for c in get_colliding_bodies():
		if c is RigidBody3D:
			(c as RigidBody3D).sleeping = false

func _spawn_destroy_particle() -> void:
	# Break puff: the data's destroy_particle_scene, else the shared large dust. Routes through
	# EffectFactory.spawn_at — the ONE place the instantiate -> position -> emit -> auto-free idiom lives —
	# instead of hand-copying it here (this was a byte-for-byte duplicate of spawn_at). spawn_at also
	# null-guards the empty-PackedScene reimport transient for free, and gives a future global
	# effects-off / pooling hook a single home. Not a NAMED factory wrapper (see EffectFactory's H3 note):
	# the scene is chosen here (data override vs DUST_LARGE), so we call the generic helper directly.
	var particle_scene: PackedScene = data.destroy_particle_scene if data and data.destroy_particle_scene else DUST_LARGE
	if not particle_scene:
		return
	EffectFactory.spawn_at(particle_scene, global_position)

func _shake_nearby_screens() -> void:
	var amount: float = data.destroy_screen_shake if data else GameSettings.physics_damage.interactable_destroy_shake_amount
	if amount <= 0.0:
		return
	var players := get_tree().get_nodes_in_group(Groups.PLAYER)
	for player_node in players:
		if not player_node is Node3D:
			continue
		var dist: float = (player_node as Node3D).global_position.distance_to(global_position)
		if dist > GameSettings.physics_damage.interactable_destroy_shake_range:
			continue
		var t: float = 1.0 - clampf(dist / GameSettings.physics_damage.interactable_destroy_shake_range, 0.0, 1.0)
		var ss = player_node.get("screen_shake")
		if ss and ss.has_method("shake"):
			ss.shake(t * amount)

func _play_destroy_sound() -> void:
	# Pick the destroy sound (falling back to the impact sound), then spawn an
	# independent one-shot player via AudioManager. Reusing impact_sfx and
	# reparenting it raced with this node's queue_free and often cut the sound
	# off before it played — a fresh, self-freeing player is robust.
	var stream: AudioStream = null
	if data and data.destroy_sound:
		stream = data.destroy_sound
	elif impact_sfx:
		stream = impact_sfx.stream
	if not stream:
		return
	AudioManager.play_sfx(global_position, stream, -2.0, 1.0)

## The resolved human NOUN for this prop, with NO verb prefix: the per-instance `display_name`, else the
## `data.display_name` from the ThrowableData, else "" when both are blank. Shared by look_name() (which prefixes
## "Pick Up") and external readers that want the bare name — e.g. Pettable.pet_name() builds "[Q] Pet <name>" from
## it, so a pettable throwable reads "Pet Dog", not "Pet Throwable". Null-safe: both display_name (set = coerce
## null→"") and `data` (typed ThrowableData) are guarded, so .strip_edges() can't crash.
func resolved_display_name() -> String:
	var prop_name := display_name.strip_edges()
	if prop_name.is_empty() and data != null:
		prop_name = data.display_name.strip_edges()
	return prop_name

## Hover label for the look-at readout. A named throwable reads "[<throw key>] Pick Up <name>";
## unnamed throwables preserve the old generic "[<throw key>] Pick Up". PickupRay falls back to the
## Throwable as the readout target when no talk handler is aimed, and the player's readout prefixes the
## CARRY key — the input unique to throwables (E would stash a dual item). Delegates the noun to
## resolved_display_name() so the look-at readout and Pettable's pet prompt resolve the same name identically.
func look_name() -> String:
	var prop_name := resolved_display_name()
	return PlayerText.pick_up(prop_name)

func on_picked_up(_picker: Node) -> void:
	_confetti_eligible = false  # handled by the player -- no longer a fresh kill gib (anti-confetti-cheese)
	_facing_travel = false  # re-grabbing mid-flight cancels the thrown-facing; the next throw re-arms it
	_held = true  # the ambient-loop driver (_update_ambient_loop) starts the held loop from this next physics frame
	_play_pickup_sound()
	_set_carried_transparency(true)

## Let go of by the carrier. `threw` marks a REAL THROW (the charged hold-release / left-click fling) as opposed to a
## tap-drop or the forced death-quickload release; it selects the SOUND only (throw_sound over release_sound) — the
## launch physics is the caller's (PickupRay._release). Defaulted false so every older/manual caller and the two
## prompt tests keep the plain drop behaviour.
func on_dropped(threw: bool = false) -> void:
	_held = false  # _update_ambient_loop stops the loop next frame — UNLESS loop_when_noticed keeps it (you're still near/looking)
	_play_release_sound(threw)
	_set_carried_transparency(false)

func _pickup_sound() -> AudioStream:
	if pickup_sound != null:
		return pickup_sound
	return data.pickup_sound if data != null else null

func _play_pickup_sound() -> void:
	var stream := _pickup_sound()
	if stream == null or not is_inside_tree():
		return
	AudioManager.play_sfx(global_position, stream, 0.0, _vocal_pitch())

func _release_sound() -> AudioStream:
	if release_sound != null:
		return release_sound
	return data.release_sound if data != null else null

## The dedicated THROW sound: the per-instance override, else the ThrowableData's, else null. Mirrors _release_sound /
## _character_impact_sound. Null => a throw falls back to the release sound, so nothing changes for a prop that
## doesn't author one.
func _throw_sound() -> AudioStream:
	if throw_sound != null:
		return throw_sound
	return data.throw_sound if data != null else null

## The launch-speed multiplier a real THROW of this prop applies, floored at 0 so a negative authored value can never
## fling the prop BACKWARD out of the thrower's face. Read by PickupRay._release.
func resolved_throw_impulse_mult() -> float:
	return maxf(throw_impulse_mult, 0.0)

## The character-impact sound (e.g. the Dog's bite): the per-instance override, else the ThrowableData's, else null.
## Mirrors _pickup_sound / _release_sound. Null => character hits fall back to the generic impact thud.
func _character_impact_sound() -> AudioStream:
	if character_impact_sound != null:
		return character_impact_sound
	return data.character_impact_sound if data != null else null

func _vocal_pitch(base_pitch: float = 1.0) -> float:
	return maxf(base_pitch, 0.01) * maxf(sound_pitch_mult, 0.01)

func _play_release_sound(threw: bool = false) -> void:
	# A real throw prefers the dedicated throw_sound and DEGRADES to the release sound when none is authored, so
	# adding throw_sound to one prop can't silence every other prop's drop.
	var stream := _throw_sound() if threw else null
	if stream == null:
		stream = _release_sound()
	if stream == null or not is_inside_tree():
		return
	AudioManager.play_sfx(global_position, stream, 0.0, _vocal_pitch())

func _held_loop_sound() -> AudioStream:
	if held_loop_sound != null:
		return held_loop_sound
	return data.held_loop_sound if data != null else null

func _start_held_loop_sound() -> void:
	var stream := _held_loop_sound()
	if stream == null or not is_inside_tree():
		return
	_stop_held_loop_sound()
	_held_loop_player = AudioStreamPlayer3D.new()
	_held_loop_player.name = "HeldLoopSFX"
	_held_loop_player.stream = stream
	_held_loop_player.bus = &"sfx"
	_held_loop_player.max_distance = AudioManager.DEFAULT_3D_MAX_DISTANCE
	_held_loop_player.finished.connect(_on_held_loop_finished)
	add_child(_held_loop_player)
	_held_loop_player.play()

func _stop_held_loop_sound() -> void:
	if _held_loop_player != null and is_instance_valid(_held_loop_player):
		_held_loop_player.stop()
		_held_loop_player.queue_free()
	_held_loop_player = null

func _on_held_loop_finished() -> void:
	if _held_loop_player == null or not is_instance_valid(_held_loop_player) or _held_loop_player.is_queued_for_deletion():
		return
	_held_loop_player.play()

## Drive the held/idle loop each physics frame from ONE predicate: play while HELD, and — if loop_when_noticed — also
## while the player is NEAR or LOOKING at this prop. A single owner for _held_loop_player, so the held pant and the
## "noticed" pant never double up or fight (dropping a watched dog hands the same loop straight over). Idempotent:
## (re)starts only when nothing is playing, stops only when something is.
func _update_ambient_loop(delta: float) -> void:
	if _destroyed:
		return  # being destroyed -> queue_free + _exit_tree stop the loop
	if _loop_should_play(delta):
		if _held_loop_player == null and _held_loop_sound() != null and is_inside_tree():
			_start_held_loop_sound()
	elif _held_loop_player != null:
		_stop_held_loop_sound()

## Should the loop be sounding this frame? Carried -> always (and clears the linger). Otherwise, if loop_when_noticed,
## play while the player is noticing AND for a short LINGER after they stop — so jitter across the near-radius / look-
## cone boundary (slow walking the edge, panning the camera near the cone) re-arms the linger every time it dips back in
## and never strobes the loop on/off. A non-noticed, non-held prop never lingers (stops promptly on drop, as before).
func _loop_should_play(delta: float) -> bool:
	if _held:
		_noticed_linger = 0.0
		return true
	if not loop_when_noticed:
		return false
	if _player_noticing():
		_noticed_linger = LOOP_NOTICED_LINGER  # re-arm — keep playing
		return true
	if _noticed_linger > 0.0:
		_noticed_linger = maxf(0.0, _noticed_linger - delta)
		return _noticed_linger > 0.0
	return false

## True if the human player is NEAR this prop (within loop_near_radius, any facing) OR LOOKING at it (within
## loop_look_range AND inside the camera view cone per loop_look_dot). Cheap; only runs for a noticed, not-held prop.
## No player / no camera -> false.
func _player_noticing() -> bool:
	var player := _real_player()
	if player == null:
		return false
	var dist := player.global_position.distance_to(global_position)
	# view_dot = how centered the prop is in the player's view (-2 = "no camera / can't tell" -> never counts as looking).
	var view_dot := -2.0
	var cam := player.get(&"camera_effects") as Camera3D
	if cam != null and is_instance_valid(cam):
		var to_prop := global_position - cam.global_position
		if to_prop.length_squared() > 0.0001:
			view_dot = (-cam.global_transform.basis.z).dot(to_prop.normalized())
	return loop_noticed(dist, loop_near_radius, loop_look_range, loop_look_dot, view_dot)

## Pure "is the player paying attention?" policy (static + literal-arg so it's unit-testable, mirroring loyal_scale):
## NEAR (within near_radius, any facing) OR LOOKING (within look_range AND view_dot >= look_dot). A radius/range of 0
## disables that trigger.
static func loop_noticed(dist: float, near_radius: float, look_range: float, look_dot: float, view_dot: float) -> bool:
	if near_radius > 0.0 and dist <= near_radius:
		return true
	if look_range > 0.0 and dist <= look_range and view_dot >= look_dot:
		return true
	return false

## The HUMAN player (the non-NPC member of the Player group), or null — companions join the group but are NPCs.
## The human player — the filter lives on Groups now (M6). Off-tree get_tree() is null, so this returns null then too.
func _real_player() -> Node3D:
	return Groups.human_player(get_tree())

func breathes() -> bool:
	return breathe or (data != null and data.breathe)

func _resolved_breathe_amount() -> float:
	if breathe_amount > 0.0:
		return breathe_amount
	if data != null and data.breathe_amount > 0.0:
		return data.breathe_amount
	return DEFAULT_BREATHE_AMOUNT

func _resolved_breathe_rate() -> float:
	if breathe_rate > 0.0:
		return breathe_rate
	if data != null and data.breathe_rate > 0.0:
		return data.breathe_rate
	return DEFAULT_BREATHE_RATE

func _cache_breathe_base_scale() -> void:
	if mesh_instance != null:
		_breathe_base_scale = mesh_instance.scale

func _reset_breathe_scale() -> void:
	if mesh_instance != null:
		mesh_instance.scale = _breathe_base_scale

## Living-prop idle: pulse the visual mesh only, not the RigidBody/CollisionShape scale.
func _animate_breathing(delta: float) -> void:
	if mesh_instance == null:
		return
	if not breathes() or _destroyed or hp <= 0:
		_reset_breathe_scale()
		return
	_breathe_phase += delta * _resolved_breathe_rate()
	var breath_scale := 1.0 + sin(_breathe_phase) * _resolved_breathe_amount()
	mesh_instance.scale = _breathe_base_scale * breath_scale

func faces_carrier_while_held() -> bool:
	return face_carrier_while_held or (data != null and data.face_carrier_while_held)

## Whether the carry pose points the prop's front AWAY from the carrier (a knife held blade-forward, ready to throw)
## rather than back at it (the dog presented to you). Mirrors faces_carrier_while_held: the per-instance toggle OR a
## ThrowableData that opts in. Read by face_carrier().
func faces_carrier_reversed() -> bool:
	return face_carrier_reversed or (data != null and data.face_carrier_reversed)

func fades_while_held() -> bool:
	match held_visibility_mode:
		HeldVisibilityMode.FADE:
			return true
		HeldVisibilityMode.OPAQUE:
			return false
		_:
			return data.fade_while_held if data != null else true

func _face_carrier_offset_radians() -> Vector3:
	var deg := face_carrier_rotation_degrees
	if data != null:
		deg += data.face_carrier_rotation_degrees
	return Vector3(deg_to_rad(deg.x), deg_to_rad(deg.y), deg_to_rad(deg.z))

## Portal-style presentation pose: keep the prop upright, but rotate its Godot-forward (-Z) toward the
## carrier/camera while held. Imported meshes can use face_carrier_rotation_degrees to correct their front axis.
## faces_carrier_reversed() flips the AIM (not the correction) so the front points away down your look direction
## instead — a knife held blade-forward, ready to throw. See face_carrier_reversed for why the flip lives here and
## not in the rotation offset.
func face_carrier(carrier_transform: Transform3D) -> void:
	if not faces_carrier_while_held():
		return
	var carried_scale := global_transform.basis.get_scale()
	var to_carrier := carrier_transform.origin - global_position
	to_carrier.y = 0.0
	if to_carrier.length_squared() < 0.0001:
		to_carrier = carrier_transform.basis.z
		to_carrier.y = 0.0
	if to_carrier.length_squared() < 0.0001:
		return
	if faces_carrier_reversed():
		to_carrier = -to_carrier  # aim AWAY from the carrier: the prop's front now leads down the carrier's forward
	look_at(global_position + to_carrier.normalized(), Vector3.UP)
	var t := global_transform
	var held_basis := t.basis.orthonormalized()
	var offset := _face_carrier_offset_radians()
	if offset != Vector3.ZERO:
		held_basis = (held_basis * Basis.from_euler(offset)).orthonormalized()
	t.basis = held_basis.scaled(carried_scale)
	global_transform = t

## Deus Ex-style carry fade: apply/clear carried_transparency on every MeshInstance3D under us (the same
## set the outline collects), via GeometryInstance3D.transparency. Fired from on_picked_up / on_dropped, so
## every grab path (PickUp hold AND the throw key) and every release (drop, throw, yanked-too-far) gets it.
## Some authored props opt out and stay opaque while carried.
func _set_carried_transparency(carried: bool) -> void:
	var targets := TalkHelpers.collect_meshes(self, null, true)
	var alpha := carried_transparency if carried and fades_while_held() else 0.0
	for m in targets:
		m.transparency = alpha
