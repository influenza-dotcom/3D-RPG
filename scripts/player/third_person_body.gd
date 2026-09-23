class_name ThirdPersonBody
extends Node3D

## THE CHARACTER YOU SEE IN THIRD PERSON — the player's actual body, at full height, in the world, holding the
## weapon they have equipped. The other half of [[ThirdPersonCamera]]: that node moves the lens, this one puts
## something there to look at. Both are inert (zero cost, nothing built) until the view is actually pulled out.
##
## It is the answer to the "(future) any real third-person player body" note that has sat on
## CharacterAppearanceCatalog since the customizer shipped: the look the player authored on New Game —
## head, body, drawn shirt, skin/arm/leg colours — resolved through the SAME `configure_swap` the menu
## portraits use, so the character behind the camera is the one from the Look tab, not a stand-in.
##
## ⭐WHY THIS NODE EXISTS AT ALL, INSTEAD OF A BodyModelSwap PARENTED STRAIGHT TO THE PLAYER (which is how the
## first-person legs are mounted). BodyModelSwap duck-types its host off `get_parent()`, and the poses it can
## strike are chosen by what that parent answers: `is_holding_gun` puts the hands ON the weapon,
## `aim_pitch_degrees` swings them to the look angle, `is_fists_out` squares them up. The Player answers NONE of
## those, deliberately — FirstPersonBody's `_configure_fp_body_arms` zeroes all three mode pitches and its
## comment spells out why: teaching the Player those methods would silently swing your FIRST-person arms through
## the view model you are holding. So this node stands between them as a PROXY HOST: it forwards the gait reads
## the character needs (velocity, is_on_floor, is_climbing) and answers the weapon-pose reads FirstPersonBody
## must never see. The FP rig keeps its parent (the Player) and its behaviour, unchanged.
##
## ⭐AND IT MUST NEVER GROW A `look` PROPERTY. `BodyModelSwap._look_src()` reads `get_parent().get("look")`, so a
## `look` here would inject an NpcLook over everything `build()` stamps. Same landmine the Player carries (see
## [[character-customizer]]); the rule is now load-bearing on two nodes instead of one.
##
## ⭐THE 180° YAW IS GEOMETRY, NOT TASTE — it is applied in build() rather than authored so it cannot be nudged
## off in the inspector. Catalog parts are authored facing the NPC's +Z; the player faces -Z. FirstPersonBody
## fixes the same mismatch by adding +180 to the torso's own rotation; a whole body has four parts plus a
## procedural gait, so the rig is turned around ONCE at the root instead. The leg steering follows for free —
## `legs_follow_movement` measures its target against this node's own global yaw.
##
## Wiring: a `ThirdPersonBody` child of Player.tscn with `host = NodePath("..")`, dragged onto the Player's
## `tp_body` export. `build()` is host-called from Player._ready (never our own _ready — `host.appearance` is
## only mirrored from GameState inside Player._ready, exactly the ordering contract FirstPersonBody documents).

## The Player this dresses. Null (a bare component in a unit test) makes every entry point a no-op.
@export var host: Player

@export_group("Third-Person Body")
## Build the body at all. Off = third person still works, you are just invisible in it (a spectator-ish view).
@export var enabled: bool = true
## Extra metres of daylight between the soles and the floor plane. Small on purpose: it is the margin that keeps
## the feet off a slope or a stair riser rather than welded through it (the same ~2 cm FirstPersonBody's
## `fp_leg_offset` bakes in).
@export var ground_clearance: float = 0.02
## HOW BIG THE CHARACTER IS, as a multiple of the size every NPC in the game already is (1.0 = exactly the
## catalog rig at its authored scale, so you stand the same height as the people around you). Feet stay planted
## at any value — only the head moves.
##
## ⭐IT USED TO BE A FIT, AND THE FIT WAS WRONG. The first build derived the scale so the character's head landed
## exactly on the camera pivot: `(eye height above floor − clearance) / 1.599`, about 0.62. That is defensible on
## paper — the lens orbits the head, and the player's own eye really is 1.0 m up — but it makes the player ~1.15 m
## tall next to 1.85 m NPCs, and in play it reads as a child following adults around ("he's WAAAY too small
## compared to NPCs", 2026-09-18). Matching the WORLD beats matching the player's own eye: the camera is behind
## you in third person, and a camera orbiting chest height instead of eye height is what every third-person
## shooter does anyway. Raise it past 1.0 and the head clips ceilings the collision capsule fits under.
@export var character_scale: float = 1.0
## HOW FAR A CROUCH MAY SHRINK THE CHARACTER, as a fraction of their standing size. There is no crouch
## ANIMATION on this rig, so the duck is expressed as size: the character is scaled by however far the eye has
## dropped toward the floor (which is exactly what the crouch does to the collision capsule — it shrinks it about
## its base), with the feet staying planted. This game's crouch is deep (the eye goes from 1.00 m to 0.40 m), so
## unclamped that is a 40% character — a doll, not a crouch. Clamped, they visibly hunker and then stop.
## 1.0 disables the crouch response entirely; the honest floor is somewhere around 0.7.
@export_range(0.3, 1.0, 0.01) var crouch_min_scale: float = 0.72
## Wear the black ACTOR OUTLINE — the ring every NPC and prop in this game wears. On, because in third person you
## ARE one of the actors on screen: without it your character is the only figure in the frame drawn with the
## world's scribbly per-crease ink instead of a clean silhouette. See FirstPersonBody.first_person_body_outline
## for the full "the ring owns actors, ink owns the world" argument.
@export var body_outline: bool = true

@export_group("Third-Person Body: reveal")
## Pull-out blend at which the character appears. NOT zero, and that is the whole point: at a blend of 0.1 the
## lens is ~20 cm behind the eye and the character's head — which sits exactly AT that eye — fills the frame.
## Waiting until the camera is most of a metre out means the body fades in already clear of the near plane.
@export_range(0.0, 1.0, 0.01) var reveal_blend: float = 0.35
## ...and is fully solid by this blend. Between the two it dithers in on BodyModelSwap's screen-door channels —
## the same retro stipple the first-person body reveals with, never smooth alpha.
@export_range(0.0, 1.0, 0.01) var full_blend: float = 0.7

@export_group("Third-Person Body: weapon")
## Show the equipped weapon in the character's hands. The model, the hold pose and the scale all come from the
## weapon's own `npc_hold_*` authoring — one set of hand-hold values, used by every actor that holds a gun.
@export var weapon_in_hands: bool = true
## Yaw correction mapping a view model's +X business-end onto the character's +Z forward — the player-side twin
## of `NPC.weapon_mesh_rotation`, and it must stay in step with it. A weapon with `npc_hold_override` on ignores
## this and places itself from its own authored pose.
@export var weapon_hold_rotation: Vector3 = Vector3(0.0, -90.0, 0.0)
## Degrees the held weapon may swing up/down with the look. The barrel tracking your aim is most of what sells
## "that character is holding the gun I am shooting"; clamped so a look at your own feet doesn't fold the arms
## through the chest.
@export var weapon_aim_pitch_limit: float = 55.0

# --- Model geometry constants (the catalog rig's own proportions, measured, not tuned) ---
## ⭐⭐THE RIG NODE'S NAME, AND IT MUST NEVER BE "Body". `BodyModelSwap._target_body()` resolves the host's
## DEFAULT mesh — the one a swapped-in model replaces — as `default_body` or, failing that,
## `get_parent().get_node_or_null("Body")`; and every rebuild ends with `_set_meshes_visible(_target_body(),
## false)`, which walks that node and hides every MeshInstance3D under it. Name the swap "Body" and it becomes
## its own default mesh: the rig builds the whole character correctly, positions it correctly, reports
## `visible = true` on the swap and on every tint duplicate — and then hides all six real part meshes on the
## last line of its own build. The result is a character that is present and measurable in every way except
## that nothing is drawn (cost: an afternoon, 2026-09-17). The name is a const so the test can pin it.
const RIG_NAME := "Character"
## Metres from the rig's origin up to the HEAD's centre, at scale 1 — the catalog/enemy head seat (0.615).
const HEAD_ABOVE_ORIGIN := 0.615
## Metres from the rig's origin down to the SOLES, at scale 1. The same 0.984 FirstPersonBody's `fp_leg_offset`
## formula is built on; the two files must agree, because they are measuring one model.
const FEET_BELOW_ORIGIN := 0.984
## Soles-to-head span at scale 1 — i.e. the character is 1.599 m tall at `character_scale` 1.0, the same height
## as every NPC. Kept as the ONE place those proportions are written down: the probe reads it to judge framing,
## and the old eye-fit (retired 09-18, see character_scale) divided it into the player's 1.0 m eye height.
const BODY_SPAN := HEAD_ABOVE_ORIGIN + FEET_BELOW_ORIGIN

var _swap: BodyModelSwap = null
## Hand anchor the held weapon hangs off — a Marker3D riding the grip the animated arms currently form, so the
## gun is never a second pose that has to agree with the hands; it IS the hands' pose (NPC's idiom).
var _hand: Marker3D = null
var _weapon_mesh: Node3D = null
## The held model's own "Muzzle" marker when it has one — where shots visibly leave the gun in third person.
var _barrel: Marker3D = null
## Player-local Y of the capsule's BOTTOM — the floor under the character. Constant: the crouch shrinks the
## capsule about its base, so this is captured once at build and never moves.
var _floor_y: float = -1.0
## The eye height captured at build — i.e. STANDING, because build() is host-called from Player._ready, before
## anything has crouched (the same "this IS the standing Y" capture FirstPersonBody makes for its torso sink).
## The crouch clamp is measured against it.
var _standing_eye_y: float = 0.0
## Smoothed aim elevation (radians, + = up) the held weapon is pitched by.
var _aim_pitch: float = 0.0

# --- Proxy-host surface: what the BodyModelSwap child reads off its parent (see the class doc) ---
## Mirrored from the host every frame so the gait strides at the player's real speed. A plain field, because
## `BodyModelSwap` reads it with `host.get(&"velocity")`.
var velocity: Vector3 = Vector3.ZERO

func is_on_floor() -> bool:
	return host != null and host.is_on_floor()

func is_climbing() -> bool:
	return host != null and host.is_climbing()

## Hands ON the weapon: a real gun is mounted and not put away. Reads the MOUNTED weapon, never the inventory's
## equipped one — during a swap the inventory already says "knife" while the pistol is still the model on the
## rig, and the hands must dress what is actually there (FirstPersonBody learned this the expensive way).
func is_holding_gun() -> bool:
	return _mounted_weapon() != null and not _holstered()

## Squared up bare-handed: unarmed, not put away, not carrying a prop.
func is_fists_out() -> bool:
	return host != null and not host._carrying and _mounted_weapon() == null and not _holstered()

## Look elevation in degrees (+ = up) — the seam BodyModelSwap.aim_pitch_contribution() uses to swing raised
## arms with the aim, and the pitch the held weapon is tilted by.
## ⭐SIGN: the Head owns pitch via `rotate_x` off MouseInput, which emits a POSITIVE pitch for a mouse moved up
## (`-screen_relative.y`), so `head.rotation.x` is already "+ = up" and passes through unnegated. (Not to be
## confused with FirstPersonBody's reveal, which wants the DOWN-look and therefore negates it.)
func aim_pitch_degrees() -> float:
	if host == null or not is_instance_valid(host.head):
		return 0.0
	return clampf(host.head.rotation_degrees.x, -weapon_aim_pitch_limit, weapon_aim_pitch_limit)

## Build the character. Host-called from Player._ready, after the appearance dict has been mirrored from
## GameState. Idempotent-ish: a second call is ignored rather than stacking a second body.
func build() -> void:
	if host == null or not enabled or _swap != null:
		return
	rotation.y = PI  # see the class doc: catalog parts face +Z, the player faces -Z
	_floor_y = _capsule_bottom_y()
	if is_instance_valid(host.head):
		_standing_eye_y = host.head.position.y
	var catalog := CharacterAppearanceCatalog.get_catalog()
	if catalog == null:
		return
	var swap := BodyModelSwap.new()
	swap.name = RIG_NAME  # ⭐never "Body" — see RIG_NAME
	swap.actor_outline = body_outline  # BEFORE any model: the rig re-applies it on every later rebuild itself
	swap.animate_legs = true
	swap.legs_follow_movement = true
	swap.legs_square_when_idle = false  # on STOP the feet HOLD your last travel direction instead of snapping to the look
	swap.velocity_driven_legs = true    # stride off real velocity, in the air too — no NPC mid-air bicycle flail
	swap.velocity_leg_ref_speed = GameSettings.player_movement.max_speed
	swap.arms_hold_when_drawn = true
	swap.arm_aim_pitch_limit = weapon_aim_pitch_limit
	add_child(swap)
	# The WHOLE look — head included. This is the one rig in the game that wants all four parts: the FP torso
	# slice skips the head because it would sit inside the lens, which is exactly where it belongs from here.
	catalog.configure_swap(swap, host.appearance)
	_swap = swap
	_hand = Marker3D.new()
	_hand.name = "WeaponHand"
	add_child(_hand)
	_fit_to_player()
	_refresh_weapon_mesh()
	set_shown(false)  # built hidden; the camera's blend reveals it

## Player-local Y of the capsule's bottom. Derived from the authored collider rather than assumed, so a retuned
## player capsule moves the character's feet with it instead of quietly floating them.
func _capsule_bottom_y() -> float:
	var cs: CollisionShape3D = host.player_collision_shape if host != null else null
	if cs == null:
		return -1.0
	var capsule := cs.shape as CapsuleShape3D
	if capsule == null:
		return -1.0
	return cs.position.y - capsule.height * 0.5

## SIZE AND MOUNT, every frame. The size is `character_scale` (a multiple of NPC size) times how far the eye has
## ducked toward the floor; the mount is whatever puts that scaled rig's soles on the floor. Both derive from
## the single live input `head.position.y`, so the two can never drift apart — the trap FirstPersonBody's paired
## `fp_body_scale` / `fp_leg_offset` documents at length.
##
## ⭐THE CROUCH RIDES HERE BECAUSE THE RIG HAS NO CROUCH ANIMATION. This game's crouch shrinks the collision
## capsule about its base and drops the head by the same delta (see Crouch._apply), so scaling the character by
## the same ratio is not a fudge — it is the same thing the physics is doing, and the feet stay planted by
## construction. Clamped by crouch_min_scale so a deep crouch hunkers rather than shrinking into a doll.
func _fit_to_player() -> void:
	if _swap == null or host == null or not is_instance_valid(host.head):
		return
	var k := character_scale * crouch_factor(host.head.position.y - _floor_y,
			_standing_eye_y - _floor_y, crouch_min_scale)
	if absf(_swap.scale.x - k) > 0.0005:
		_swap.scale = Vector3.ONE * k
	var mount := fit_mount_y(_floor_y, ground_clearance, k)
	if absf(_swap.position.y - mount) > 0.0005:
		_swap.position.y = mount

## SIZE AND MOUNT, DERIVED FROM ONE INPUT so they cannot drift apart (the trap FirstPersonBody's paired
## `fp_body_scale` / `fp_leg_offset` documents at length). The scale is `character_scale` times the crouch
## factor; the mount is whatever puts THAT scaled rig's soles on the floor. Static so the invariants are
## unit-testable off-tree — the GunMesh.view_model_visible_now idiom.
##
## Where the scaled rig has to hang so its soles land `clearance` above the floor. Takes the FINAL scale, so the
## feet stay planted whatever the crouch or the size knob did.
static func fit_mount_y(floor_y: float, clearance: float, k: float) -> float:
	return floor_y + clearance + FEET_BELOW_ORIGIN * k

## HOW FAR THE CHARACTER HAS DUCKED, 0.. 1 as a multiplier on their standing size — the whole crouch, since this
## rig has no crouch animation. It is the ratio of the LIVE eye height above the floor to the standing one,
## which is exactly what this game's crouch does to the collision capsule (shrink it about its base), floored at
## `min_ratio` so a deep crouch hunkers instead of turning the character into a doll. Degenerate inputs (a
## zero/negative standing height) answer 1.0 — no crouch — rather than dividing by zero.
static func crouch_factor(eye_above_floor: float, standing_above_floor: float, min_ratio: float) -> float:
	if standing_above_floor <= 0.001:
		return 1.0
	return clampf(eye_above_floor / standing_above_floor, clampf(min_ratio, 0.05, 1.0), 1.0)

## Show / hide the whole character (body + held weapon) in one place.
func set_shown(on: bool) -> void:
	if _swap != null:
		_swap.visible = on
	if _hand != null:
		_hand.visible = on

## Is the character on screen right now? Read by tests and by the shot-origin decision.
func is_shown() -> bool:
	return _swap != null and _swap.visible

func _process(delta: float) -> void:
	if host == null or _swap == null:
		return
	velocity = host.velocity  # mirrored for the gait (see the proxy-host block)
	var blend := _camera_blend()
	var show := blend >= reveal_blend
	if show != is_shown():
		set_shown(show)
		_apply_shot_origin()
	if not show:
		return
	_fit_to_player()
	# Dither in across the reveal band on the rig's own screen-door channels. The HEAD has no transparency
	# channel of its own, so it arrives solid at `reveal_blend` — by which point the lens is far enough back
	# that it reads as the character stepping into frame rather than a pop in your face.
	var band := maxf(full_blend - reveal_blend, 0.0001)
	var see := clampf(1.0 - (blend - reveal_blend) / band, 0.0, 1.0)
	if absf(_swap.body_transparency - see) > 0.002:
		_swap.body_transparency = see
	if absf(_swap.arm_transparency - see) > 0.002:
		_swap.arm_transparency = see
	if absf(_swap.leg_transparency - see) > 0.002:
		_swap.leg_transparency = see
	_update_hand(delta)

## The camera's live pull-out, or 0 when there is no third-person arm on the rig at all (an older camera_rig,
## an off-tree player) — in which case this body simply never shows.
func _camera_blend() -> float:
	if host == null or not is_instance_valid(host.head):
		return 0.0
	var arm := host.head.camera_arm
	return arm.blend if arm != null else 0.0

## Put the gun in the hands and point it where the player is looking. The position is the grip the ANIMATED arms
## currently form (`weapon_grip_position`, swap-local, mapped through the swap's full transform — basis AND
## origin, because the rig is both scaled and mounted), so the weapon can never visibly detach from the hands:
## it is not a second pose that has to agree with the arms, it IS the arms' pose. The pitch is the look
## elevation, eased, applied about the grip — yaw is untouched, because the body already faces where you look.
func _update_hand(delta: float) -> void:
	if _hand == null or _swap == null:
		return
	var raw: Variant = _swap.weapon_grip_position()
	if raw is Vector3:
		_hand.position = _swap.transform * (raw as Vector3)
	# ⭐THE HAND CARRIES THE RIG'S SCALE, and it is not optional. The weapon's `npc_hold_*` pose — including the
	# `npc_held_display_scale` readability boost — is authored against a FULL-SIZE character rig, the one an NPC
	# has. This character is fitted to the player's 1.0 m eye (~0.62), so an anchor left at scale 1 mounts a gun
	# nearly three times too big: it reads as a rifle lying across the character's head rather than a weapon in
	# their hands. Scaling the anchor (rather than the model) keeps ONE meaning for every npc_hold_* number —
	# "how this weapon sits in a character's hands" — at any rig size.
	var k: float = _swap.scale.y
	if absf(_hand.scale.y - k) > 0.0005:
		_hand.scale = Vector3.ONE * k
	_aim_pitch = lerpf(_aim_pitch, deg_to_rad(aim_pitch_degrees()) if is_holding_gun() else 0.0,
			1.0 - exp(-12.0 * delta))
	_hand.rotation.x = -_aim_pitch  # the mounted model faces +Z; -X rotation tilts it UP
	# The HOLSTER is a per-frame state with no signal we own, so the gun's visibility is settled here — and the
	# shot origin has to follow it, or drawing a holstered weapon in third person would leave the tracer coming
	# out of the camera until the next weapon swap happened to re-point it.
	var out := is_holding_gun()
	if _weapon_mesh != null and _weapon_mesh.visible != out:
		_weapon_mesh.visible = out
		_apply_shot_origin()

## Mount (or clear) the equipped weapon's model at the hand. Host-called on every swap, and once at build.
## Mirrors `NPC._build_weapon_mesh` — same `held_view_model()` seam (which returns null for the FISTS, whose
## view model is the player's own first-person arms rig and would mount as a pair of floating forearms), same
## `npc_hold_override` re-pose for a weapon whose root bakes a first-person-only transform, same
## `npc_held_display_scale` readability boost, and the same world-renderable pass afterwards.
func refresh_weapon() -> void:
	_refresh_weapon_mesh()

func _refresh_weapon_mesh() -> void:
	if is_instance_valid(_weapon_mesh):
		_weapon_mesh.queue_free()
	_weapon_mesh = null
	_barrel = null
	if not weapon_in_hands or _hand == null:
		_apply_shot_origin()
		return
	var wd := _mounted_weapon()
	var vm: PackedScene = wd.held_view_model() if wd != null else null
	if vm == null:
		_apply_shot_origin()
		return
	_weapon_mesh = vm.instantiate()
	_hand.add_child(_weapon_mesh)
	if wd.npc_hold_override:
		_weapon_mesh.position = wd.npc_hold_position
		_weapon_mesh.rotation_degrees = wd.npc_hold_rotation
		_weapon_mesh.scale = Vector3.ONE * wd.npc_hold_scale * wd.npc_held_display_scale
	else:
		_weapon_mesh.rotation_degrees = weapon_hold_rotation
		_weapon_mesh.scale *= wd.npc_held_display_scale
	_weapon_mesh.position += wd.npc_hold_trim
	# ⭐AND MAKE IT A WORLD OBJECT. A view model is authored to draw on the view-model layer with depth testing
	# off — that is how the player's gun draws over the world from its own pass. Hung in a world-space hand
	# as-is, the same mesh renders THROUGH WALLS. Shared with the NPC hand mount rather than copied a third
	# time: it is one rule about one class of scene, and a second copy is a second thing to forget.
	NPC._make_held_model_world_renderable(_weapon_mesh)
	_barrel = NodeFinder.find_first_by_name(_weapon_mesh, "muzzle") as Marker3D
	_weapon_mesh.visible = is_holding_gun()
	_apply_shot_origin()

## WHERE SHOTS VISIBLY COME FROM. The damage trace is unaffected by any of this — it is cast from the screen
## centre (`Player.get_aim_origin`) and always was — but the TRACER and the spawned projectile start at
## `Attack.muzzle`, which in first person is the marker on the view model under the lens. Pulled out, that
## marker is two metres BEHIND the character, so every shot would streak past your own head. While the body is
## on screen with a gun in its hand, point both spawners at the barrel of the gun you can actually see; put
## them back on the rig's own muzzle the moment it isn't.
##
## Safe to flip at will: `WeaponSystem.muzzle` is resolved ONCE in setup() from the gun rig's persistent
## PlayerMuzzle marker and never reassigned, so it is a stable value to restore to across weapon swaps.
func _apply_shot_origin() -> void:
	if host == null or host.weapon_system == null:
		return
	var ws := host.weapon_system
	var third := is_shown() and _barrel != null and is_instance_valid(_barrel) and is_holding_gun()
	var m: Marker3D = _barrel if third else ws.muzzle
	if ws.attack != null:
		ws.attack.muzzle = m
	if ws.projectile_spawner != null:
		ws.projectile_spawner.muzzle = m

## The weapon whose model is MOUNTED on the first-person rig right now (null = unarmed / fists). The same
## reading FirstPersonBody's hands use, and for the same reason: mid-swap the inventory has already moved on.
func _mounted_weapon() -> WeaponData:
	if host == null:
		return null
	var gun := host.gun_mesh
	var wd: WeaponData = gun.mounted_weapon() if gun != null else null
	if wd == null and host.weapon_system != null and host.weapon_system.inventory != null:
		wd = host.weapon_system.inventory.equipped_weapon
	if wd == null:
		return null
	if wd == Player.FISTS or wd.resource_path == Player.FISTS.resource_path:
		return null
	return wd

func _holstered() -> bool:
	if host == null or host.weapon_system == null or host.weapon_system.attack == null:
		return false
	return host.weapon_system.attack.holstered
