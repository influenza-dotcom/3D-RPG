@tool
class_name BodyPartGib
extends Throwable

## A gore gib whose VISUAL is a REAL body part torn off the character that just died -- its actual head,
## torso, arm or leg, with that character's own skin/tint -- instead of the generic meat chunk
## (scenes/effects/gore_gib.tscn) every death has always flung. The LEGO / Roblox "the guy comes apart into
## his own pieces" read: the six parts blow outward FROM WHERE THEY SAT ON THE BODY, so for one frame the
## silhouette is still the character before it scatters.
##
## Physically it IS a gore gib: same Throwable chassis, same `gore_gib_data.tres` (is_gib, damages_player
## off, no scorch decal), same &"gib" group + lifetime fade + world cap, same bleed-on-destroy. So a part can
## be shot out of the air for the confetti trick shot, picked up, and thrown, exactly like a meat chunk.
##
## WHO DRIVES IT: GoreSpawner (scripts/player/gore_spawner.gd) on death -- it duplicates the live parts off
## the dying actor's BodyModelSwap and hands each one here via mount_part(). The per-actor opt-out / part
## filter is the BodyPartGibs drop-in (scripts/components/body_part_gibs.gd); the feel numbers are the
## "Body-part gibs" group on GameSettings.effects. Nothing here reads the dead actor -- by the time a gib is
## alive its source is gone (freed, or already recycled by the NPC pool).
##
## SETUP (already done in scenes/effects/body_part_gib.tscn -- only relevant if you build another chassis):
## wire `mesh_instance` to an EMPTY MeshInstance3D (the mount point -- the part hangs UNDER it, so the
## collider auto-fit sizes to the real limb) and `collision_shape` to a CollisionShape3D holding a BoxShape3D.
## Do NOT give the `data` resource a `mesh` or a `material`: Throwable._apply_data_to_visuals would push them
## over the mounted part and wipe the character's skin off it.

## The mounted body part (the duplicate of the dying actor's live part node). Null until mount_part() succeeds
## -- a chassis that never got one is just an invisible gib, which is why GoreSpawner drops it instead.
var _mounted: Node3D = null

## Where the part's ORIGINAL visual centre was in the world, captured at mount time. GoreSpawner reads it back
## through spawn_origin() to place this body, because the mount is computed BEFORE the gib enters the tree
## (see mount_part for why that order is mandatory).
var _spawn_origin: Vector3 = Vector3.ZERO

## The part's own rotation at mount time, with the right-limb mirror already split off onto the child (see
## mount_placement). Read back through spawn_basis() and written onto the body right after add_child.
var _spawn_basis: Basis = Basis.IDENTITY


## Reflection across X, the exact mirror BodyModelSwap._reflect() premultiplies onto the RIGHT arm and leg to
## turn one authored limb model into a matched pair. Its determinant is -1, which is why it has to be split
## back out below before the pose can go anywhere near a rigid body.
const MIRROR_X := Basis(Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, 1.0))

## NOTE: `PartPinnerScript` (the preloaded pin geometry + policy statics) is INHERITED from Throwable and used
## freely below. Do NOT re-declare it here — GDScript rejects a member that shadows one in the parent class, and
## because the failure is a PARSE error the whole chassis loses its script: the gib spawns as a bare RigidBody3D,
## `mount_part` goes missing, and every death silently stops producing body parts at all.

## PURE GEOMETRY SEAM (static so GUT can pin it with no scene, no tree -- tests/test_body_part_gibs.gd).
## Splits a part's live WORLD transform into "where the rigid body goes" and "how the part sits under it",
## given the centre of the part's own visual AABB in PART-LOCAL space. Returns:
##   origin -- the part's visual CENTRE in world space. The body sits there, not at the part's own origin,
##             because a limb model pivots at its shoulder/hip joint: spinning a gib about that would look
##             like a hinge, and Throwable's collider auto-fit (which centres its BoxShape3D on the body
##             origin) would size a box around the joint instead of around the limb.
##   basis  -- the part's ROTATION, as a proper rotation: orthonormal, unscaled, determinant +1. Everything a
##             RigidBody3D is allowed to have. Scale is stripped because Godot/Jolt do not honour it on a
##             rigid body, and the right limbs' det = -1 mirror is stripped because handing the physics
##             server a reflected basis is the known "negative-scale GLB renders black" failure.
##   local  -- what is left for the part itself: its uniform scale, times that mirror for a right limb. Both
##             are AXIS-ALIGNED (a diagonal basis), which is the second reason to split this way -- the
##             collider auto-fit boxes the mesh in its OWN frame, so a limb hanging at 90 degrees gets a
##             collider the size of the limb instead of the diagonal box that encloses the rotated one.
## Identity check: body(basis, origin) * local == world_xf, so the part does not move a millimetre when it
## becomes a gib -- the burst starts from exactly the pose the player was looking at, mirror and all.
## A degenerate (zero-scale) basis can't be decomposed; it falls back to an unrotated body, which is only
## ever reachable from a part scaled to nothing -- invisible either way.
static func mount_placement(world_xf: Transform3D, centre_local: Vector3) -> Dictionary:
	var centre_world: Vector3 = world_xf * centre_local
	var rot := Basis.IDENTITY
	if absf(world_xf.basis.determinant()) > 0.000001:
		rot = world_xf.basis.orthonormalized()
		if rot.determinant() < 0.0:
			rot = rot * MIRROR_X  # cancel the right-limb reflection -> a real rotation; it re-appears in `local`
	var inv := rot.inverse()
	return {
		"origin": centre_world,
		"basis": rot,
		"local": Transform3D(inv * world_xf.basis, inv * (world_xf.origin - centre_world)),
	}


## The visual AABB of `root` in ITS OWN local space -- the root's own transform is deliberately EXCLUDED
## (the _part_reach idiom in body_model_swap.gd), because mount_part overwrites it. Child transforms DO
## accumulate. Hidden meshes are skipped: on a live part the only hidden mesh is BodyModelSwap's talking
## mouth quad, which is a widget, not anatomy, and would otherwise inflate the collider.
## Returns {"has": bool, "aabb": AABB} -- "has" false means nothing visible to fling.
static func local_visual_aabb(root: Node) -> Dictionary:
	var state := {"has": false, "aabb": AABB()}
	_collect_local_aabb(root, Transform3D.IDENTITY, state)
	return state


static func _collect_local_aabb(node: Node, xf: Transform3D, state: Dictionary) -> void:
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null and mi.visible:
		var box: AABB = xf * mi.mesh.get_aabb()
		state["aabb"] = box if not bool(state["has"]) else (state["aabb"] as AABB).merge(box)
		state["has"] = true
	for c in node.get_children():
		var child_xf := xf
		var c3d := c as Node3D
		if c3d != null:
			child_xf = xf * c3d.transform
		_collect_local_aabb(c, child_xf, state)


## Seat a DUPLICATED body part on this chassis. `part` must be an off-tree duplicate() of the dying actor's
## live BodyModelSwap part (never the original -- a POOLED NPC reuses those exact node instances every life,
## so reparenting or freeing one comes back limbless), and `world_xf` its global_transform captured just
## before the duplicate.
##
## CALL THIS BEFORE add_child()-ing the gib into the world. Two things depend on that order, both inside
## Throwable._ready: the collider auto-fit (which sizes the BoxShape3D from whatever hangs under
## mesh_instance) and _setup_overlay_chain (the ONLY thing that severs the overlay the duplicate inherited --
## see _strip_host_state).
##
## TAKES OWNERSHIP of `part`: on success it is parented here, and on ANY failure it is freed. So the caller
## never has to clean up a duplicate that didn't make it (it is off-tree at that point, and an orphan Node
## leaks -- nothing else references it).
##
## Returns false when the part has no visible geometry at all; the caller should then throw the chassis away.
func mount_part(part: Node3D, world_xf: Transform3D) -> bool:
	var mount := _mesh_root()
	if mount == null or part == null:
		if part != null:
			part.free()
		return false
	_strip_host_state(part)
	var box := local_visual_aabb(part)
	if not bool(box["has"]):
		part.free()  # nothing visible (an empty/placeholder model) -- the caller discards this chassis
		return false
	var placement := mount_placement(world_xf, (box["aabb"] as AABB).get_center())
	part.transform = placement["local"]
	mount.add_child(part)
	_mounted = part
	_spawn_origin = placement["origin"]
	_spawn_basis = placement["basis"]
	return true


## Where mount_part decided this body belongs in the world (the part's visual centre). GoreSpawner writes it
## onto global_position right after add_child, because a not-yet-in-tree node has no global transform to set.
func spawn_origin() -> Vector3:
	return _spawn_origin


## The rotation mount_part decided this body should launch at (the part's own facing, mirror stripped out).
## Written onto global_basis alongside spawn_origin, for the same reason.
func spawn_basis() -> Basis:
	return _spawn_basis


## Cut every tie the duplicate still has to the (possibly POOLED, therefore still-live) character it came off,
## and to the rig it was posed for:
##   * material_overlay -- the duplicate inherits the dead NPC's per-limb combat outline chained to that limb's
##     PERSISTENT flash ShaderMaterial (npc_outline.gd). That material outlives the body and keeps being driven
##     by the recycled NPC's next life, so an un-cleared gib can freeze mid-flash or re-flash later. Throwable's
##     own overlay pass would overwrite the slot at _ready anyway; clearing here makes the intent explicit and
##     covers a chassis whose _ready hasn't run yet.
##   * the `talk_prev_overlay` meta -- TalkHelpers' look-at-highlight stash. duplicate() copies metadata, so a
##     character killed while the player was looking at it hands its stashed overlay to the gib. Inert but stale.
##   * material_override -- the character's skin. SHARED BY REFERENCE with the living/pooled original, so it is
##     duplicated here per the writable-material rule (mesh_coat.gd) and never mutated in place.
##   * layers / cast_shadow / transparency -- forced back to world defaults. A first-person rig sets
##     view_model_layer (so the part would draw only in the gun camera) and casts_shadow off; a gib is world
##     geometry and must render and shadow like one.
##   * hidden meshes -- freed. The only one on a live part is the talking mouth quad, a billboarded widget that
##     would keep facing the camera on a tumbling limb.
func _strip_host_state(root: Node) -> void:
	var doomed: Array[Node] = []
	_walk_strip(root, doomed)
	for n in doomed:
		var p := n.get_parent()
		if p != null:
			p.remove_child(n)
		n.free()  # free(), not queue_free(): this whole subtree is off-tree and about to be measured


func _walk_strip(node: Node, doomed: Array[Node]) -> void:
	var mi := node as MeshInstance3D
	if mi != null:
		if not mi.visible:
			doomed.append(mi)
			return  # its children go with it
		mi.material_overlay = null
		if mi.has_meta(&"talk_prev_overlay"):
			mi.remove_meta(&"talk_prev_overlay")
		if mi.material_override != null:
			mi.material_override = mi.material_override.duplicate()
			# The FP torso's dithered see-through rides the MATERIAL channel (BodyModelSwap.body_transparency:
			# the planar shirt shader's see_through uniform, or a tagged alpha-hash duplicate) — the
			# GeometryInstance3D.transparency reset below can't clear it, and a gib must read as a SOLID prop
			# (a crouched death otherwise flings a near-invisible torso that still offers its pickup prompt).
			var sm := mi.material_override as ShaderMaterial
			if sm != null and sm.get_shader_parameter(&"see_through") != null:
				sm.set_shader_parameter(&"see_through", 0.0)
			var bm := mi.material_override as BaseMaterial3D
			if bm != null and bm.has_meta(&"bms_body_transp"):
				bm.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				bm.albedo_color.a = 1.0
		if mi.mesh != null:
			# Same rule for per-SURFACE overrides (the plain-skin torso's see-through dups): ours are tagged,
			# and clearing them falls back to the mesh's baked material — which IS the solid original.
			for s in mi.mesh.get_surface_count():
				var so := mi.get_surface_override_material(s)
				if so != null and so.has_meta(&"bms_body_transp"):
					mi.set_surface_override_material(s, null)
		# Layer 1 (a gib is plain world-visible geometry, whatever view-model layer the limb wore) PLUS
		# the ink-mask bit: the duplicate keeps the dead NPC's hull outline material, so like every
		# hull-rimmed actor it must stay OUT of the screen-space ink pass or the rim gets double-lined.
		mi.layers = 1 | InkOutline.ACTOR_INK_MASK_LAYER
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.transparency = 0.0
	for c in node.get_children():
		_walk_strip(c, doomed)


## The node the part mounts under: the wired `mesh_instance` export, else the "Model" child by name. The
## fallback covers a chassis instantiated off-tree in a unit test, where a node-path export may not have been
## resolved yet.
func _mesh_root() -> MeshInstance3D:
	if mesh_instance != null:
		return mesh_instance
	return get_node_or_null(^"Model") as MeshInstance3D


# --- The PIN kill: this limb is carried to a wall and stapled there ------------------------------------------
#
# A thrown weapon that lands a LETHAL hit (Throwable.pins_body_part) doesn't just fling the part it struck with
# the other five -- it carries that one into the surface behind the victim and leaves it there with the blade
# through it. GoreSpawner picks the part and probes for the surface; everything from the launch onward is here.
#
# THE LIMB FLIES ON RAILS. Both collision layers go to ZERO for the whole pin, and gravity with them, so the part
# travels in a dead-straight line down the exact ray the probe already cleared and stops by ARITHMETIC (the
# half-space test in PartPinnerScript.reached), never by collision. That one decision removes most of what makes this
# kind of effect fragile: it cannot be knocked off course by the five limbs bursting beside it, cannot self-damage
# on arrival (Throwable._try_self_damage never fires), needs none of spawn_gibs' mutual collision-exception pass,
# and cannot tunnel. It also means the seated trophy is INERT -- it does not block NPC line of sight, does not
# shove the player, and cannot confuse a navmesh that was baked in the editor and will never know it is there.
# The layers come back the moment it drops off the wall, and it finishes life as an ordinary gib.

var _pin_flying: bool = false
var _pin_seated: bool = false
var _pin_dir: Vector3 = Vector3.ZERO
var _pin_seat: Vector3 = Vector3.ZERO          ## where the body comes to rest, sunk into the surface
var _pin_limb_free: Vector3 = Vector3.ZERO     ## where it goes BEFORE unfreezing — clear of the surface it is buried in
                                               ## (deliberately NOT named _pin_free_position: Throwable holds a field
                                               ## by that name for the BLADE, and GDScript rejects a shadowed member)
var _pin_flight_left: float = 0.0
var _pin_blade: Throwable = null               ## the weapon that put it here; parked embedded on arrival
var _pin_blade_pose: Transform3D = Transform3D.IDENTITY
var _pin_blade_free: Vector3 = Vector3.ZERO
var _pin_surface: Node = null                  ## the collider we are stapled to; when it dies, so do we
var _pin_prior_layer: int = 0
var _pin_prior_mask: int = 0
var _pin_limb_gravity: float = 1.0

## Hard ceiling (seconds) on the flight. The half-space test is the real arrival check; this only exists so a
## part that somehow never crosses its seat plane -- a degenerate direction, a probe point behind us -- seats
## anyway instead of drifting away forever with its physics disabled. Not a feel knob.
const PIN_FLIGHT_TIMEOUT: float = 2.0


## Launch this limb at the surface the probe found and staple it there on arrival. `surface_point` / `dir` are the
## probe hit and the weapon's travel direction; `bury` and `blade_embed` are the tuning (see the "Pinned body
## parts" group on GameSettings.effects); `blade` is the Throwable that struck, parked embedded once we land;
## `surface` is the collider we are pinning to, watched so a level swap takes the trophy with it.
## CALL AFTER add_child + the spawn pose is written -- the seat depth is measured from the live collider the
## auto-fit sized to this specific limb, and the body must already be where it starts flying from.
func begin_pin_flight(surface_point: Vector3, dir: Vector3, speed: float, bury: float, blade_embed: float, blade: Throwable, surface: Node) -> void:
	if _pin_flying or _pin_seated or dir.length_squared() < 0.000001:
		return
	_pin_dir = dir.normalized()
	_pin_surface = surface
	# Seat depth is measured against the limb's OWN collider, which Throwable's auto-fit sized to this exact part
	# at _ready -- so a head and a forearm each bite into the wall by the same fraction of their own thickness.
	var support := PartPinnerScript.support_along(global_basis, collider_size(), _pin_dir)
	_pin_seat = PartPinnerScript.seat_origin(surface_point, _pin_dir, support, bury)
	_pin_limb_free = PartPinnerScript.seat_origin(surface_point, _pin_dir, support, 0.0)  # fully clear, for the release
	if is_instance_valid(blade):
		_pin_blade = blade
		# The blade's embedded pose, authored rather than left to physics: aimed down the travel direction through
		# the SAME facing helper the thrown flight uses, so the mesh-front correction applies and the point goes in
		# first. Measured from the SURFACE, not from the limb -- the knife goes through the limb INTO the wall.
		var blade_basis := blade.travel_facing_basis(_pin_dir)
		var blade_half := PartPinnerScript.support_along(blade_basis, blade.collider_size(), _pin_dir)
		_pin_blade_pose = Transform3D(blade_basis, PartPinnerScript.blade_origin(surface_point, _pin_dir, blade_half, blade_embed))
		_pin_blade_free = surface_point - _pin_dir * (blade_half + 0.05)
	_pin_prior_layer = collision_layer
	_pin_prior_mask = collision_mask
	_pin_limb_gravity = gravity_scale
	collision_layer = 0
	collision_mask = 0
	gravity_scale = 0.0
	angular_velocity = Vector3.ZERO  # no tumble: the limb has to arrive at the pose the seat was measured for
	linear_velocity = _pin_dir * speed
	_pin_flight_left = PIN_FLIGHT_TIMEOUT
	_pin_flying = true


## Drive the flight, then watch the wall. Chains to Throwable's own bookkeeping (impact/damage cooldowns, the
## thrown-credit timer, breathing, _pre_step_velocity) -- dropping the super() call would strand all of it.
func _physics_process(delta: float) -> void:
	super(delta)
	if Engine.is_editor_hint():
		return
	if _pin_flying:
		_pin_flight_left -= delta
		if PartPinnerScript.reached(global_position, _pin_seat, _pin_dir) or _pin_flight_left <= 0.0:
			_seat()
		return
	if not _pin_seated:
		return
	# A level swap frees the "Level" subtree, but gore is parented under the tree ROOT and survives it (see
	# GoreSpawner) -- so a pin outliving a door transition would hang in the next map's empty air with the wall it
	# was stapled to gone. The trophy belongs to its wall: when that collider goes, so does this.
	if not is_instance_valid(_pin_surface) or not _pin_surface.is_inside_tree():
		_release_pin()
		queue_free()
		return
	# PULL THE KNIFE, DROP THE LIMB. The blade is what is holding this up, so the moment it stops being pinned --
	# the player walked over and grabbed it (PickupRay._pick_up unpins first), or it was freed outright -- the limb
	# comes off the wall and falls. Polled rather than signalled because the blade can leave through either of
	# those two doors and only one of them is a call we make; a stale is_instance_valid check covers both.
	if not is_instance_valid(_pin_blade) or not _pin_blade.is_pinned():
		_release_pin()


## Arrival: stop dead at the measured seat and freeze there, then park the blade through us. STATIC rather than
## KINEMATIC freeze -- a kinematic frozen body is code-moved and PUSHES what it overlaps, and this one is
## deliberately sunk into a wall.
func _seat() -> void:
	_pin_flying = false
	_pin_seated = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_position = _pin_seat
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	if is_instance_valid(_pin_blade):
		_pin_blade.pin_at(_pin_blade_pose, _pin_blade_free)


## Come off the wall: hand the blade back, restore the collider and gravity, and go dynamic so the limb drops and
## tumbles like an ordinary gib. Order matters -- the body is moved CLEAR of the surface before `freeze` is
## cleared, because the solver depenetrates an overlapping body by firing it out at speed, which would look like
## the wall spitting a head across the room.
func _release_pin() -> void:
	if is_instance_valid(_pin_blade):
		_pin_blade.unpin()
	_pin_blade = null
	if not _pin_seated:
		return
	_pin_seated = false
	if is_inside_tree():
		global_position = _pin_limb_free
	collision_layer = _pin_prior_layer
	collision_mask = _pin_prior_mask
	gravity_scale = _pin_limb_gravity
	freeze = false


## True once this limb has arrived and is stapled in place (as opposed to still in flight, or never pinned).
func is_pin_seated() -> bool:
	return _pin_seated


## True if this limb is the PIN of its death — either still flying to the wall or already stapled to it. The
## seam an integration test asserts on (tests/test_pin_kill_integration.gd), since the flight takes real physics
## frames and `is_pin_seated` is false for the first few of them.
func is_pin_active() -> bool:
	return _pin_flying or _pin_seated


## Fade the WHOLE mounted limb, not just the mount point. Throwable's base despawn fade tweens
## `mesh_instance.transparency`, and GeometryInstance3D.transparency is PER-INSTANCE -- it does not propagate
## to child MeshInstance3Ds -- so a body part hanging under the mount would pop out of existence instead of
## fading. Every visible mesh in the subtree is tweened in parallel over the same `fade`.
##
## A PINNED limb gets two extra beats first: it is released (so it falls off the wall and frees the player's
## knife) and then left to tumble for pinned_part_drop_linger before the fade starts. Dissolving a trophy in
## place would read as it being deleted; dropping it reads as the body finally giving. The base seam's docstring
## invites an override that takes as long as it needs, and begin_gib_lifetime awaits this before freeing.
func _fade_out_for_despawn(fade: float) -> void:
	if _pin_seated:
		_release_pin()
		var linger: float = GameSettings.effects.pinned_part_drop_linger
		if linger > 0.0 and is_inside_tree():
			await get_tree().create_timer(linger).timeout
		if not is_inside_tree():
			return
	var targets: Array[GeometryInstance3D] = []
	_collect_geometry(self, targets)
	if targets.is_empty():
		return
	var tw := create_tween().set_parallel(true)
	for g in targets:
		tw.tween_property(g, "transparency", 1.0, fade)
	await tw.finished


func _collect_geometry(node: Node, out: Array[GeometryInstance3D]) -> void:
	var g := node as GeometryInstance3D
	if g != null:
		out.append(g)
	for c in node.get_children():
		_collect_geometry(c, out)


## Editor warning on top of Throwable's own (no collider / no mesh_instance): a chassis whose mount point is
## pre-loaded with a mesh would fling that mesh alongside the body part it is handed.
func _get_configuration_warnings() -> PackedStringArray:
	var w := super()
	if mesh_instance != null and mesh_instance.mesh != null:
		w.append("`mesh_instance` already holds a mesh — a body-part gib mounts the character's own part under it, so this one would fly along with it. Clear the mesh.")
	if data != null and (data.mesh != null or data.material != null):
		w.append("The assigned ThrowableData sets a mesh/material — Throwable pushes those over the mounted body part at _ready and wipes the character's skin off it. Use a data resource that sets neither (resources/interactables/gore_gib_data.tres).")
	return w
