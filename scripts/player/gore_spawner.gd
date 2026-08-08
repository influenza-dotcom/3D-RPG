class_name GoreSpawner
extends Node3D

## Everything an actor flings OUTWARD when it dies — the on-death gore burst. Lifted wholesale out
## of Character: the floor blood decal, the gib rigid bodies, the rigged-skeleton ragdoll corpse,
## and the "tell nearby players someone died" ping (drives their on-camera blood splatter + shake).
## Character keeps thin gore()/spawn_blood_decal() facades that delegate here.
##
## Code-built child of Character (added in its _ready). It reads the host for everything: its
## transform (decal/gib spawn point, corpse pose), its velocity + explosion_velocity (the launch the
## ragdoll inherits), its bloody_mess node, and the BLOOD_SPLAT_DECAL const and gib_scene /
## ragdoll_scene @exports — all of which stay on the root so the editor/.tscn keep setting them
## per-actor. Gib spawn tuning (counts, velocities, lifetime) comes from GameSettings.effects
## (gib_*). Nothing here holds state; it's a pure spawner driven off the host.

## The actor we belong to — set right after .new(), before add_child. Source of the spawn transform,
## the death launch (velocity + explosion_velocity), the bloody_mess node, and the gore scenes.
var _host: Character

## The body-part drop-in, reached by SCRIPT PATH rather than its `BodyPartGibs` class_name (the LocomotionFx
## idiom in scripts/components/README.md). This script is on Character's parse path, so a class_name here
## would have to be in the editor's global class cache before any actor could compile; a preloaded path never
## is. Only its STATICS are used from here — the per-actor instance is read duck-typed (_body_part_config).
const BodyPartGibsScript := preload("res://scripts/components/body_part_gibs.gd")

## The PIN kill's geometry + policy statics, preloaded by path for exactly the reason above.
const PartPinnerScript := preload("res://scripts/effects/part_pinner.gd")

## Whether the burst currently being spawned is a PIN kill — set by _spawn_body_part_gibs and read by
## _meat_gib_count a few lines later in spawn_gibs, so a pin death can spray fewer loose chunks. The two run
## SYNCHRONOUSLY inside one spawn_gibs() call and nothing else touches it, so this is a parameter in all but
## name; it is a field only because _meat_gib_count's signature is shared with the no-parts path.
var _burst_pinned: bool = false

## Fire the full on-death gore sequence in the monolith's exact order: floor decal, the bloody_mess
## particle burst (if the actor has one), notify nearby players (camera splatter + shake), the gib
## rigid bodies (BOTH the actor's own body parts and the generic meat chunks — spawn_gibs owns that mix),
## then the ragdoll corpse. Order is preserved — Character.gore() delegates straight here. The gibs must
## stay BEFORE _spawn_ragdoll: a corpse/loot bag dropped first would be shoved around by the burst.
func run() -> void:
	spawn_blood_decal()
	if _host.bloody_mess:
		# Hand the host's gore controller our tag BEFORE it spews, so the particle burst, the blood-drop emitter,
		# every drop it rains and every decal those drops leave all join the same group (bloody_mess.gd passes it
		# down the chain). Set duck-typed: `bloody_mess` is exported as a plain Node3D.
		_host.bloody_mess.set(&"gore_tag", _tag_group())
		_host.bloody_mess.particles(Vector3.ZERO)
	_notify_nearby_players_of_death()
	spawn_gibs()
	_spawn_ragdoll()

# --- Ownership tagging: whose death spawned this? ------------------------------------------------------------
#
# Every world node this spawner adds joins the host's death_gore_group() (Character seam; `&""` = tag nothing,
# the base/NPC answer). Only the PLAYER names a group today — Groups.PLAYER_GORE — because only the player's
# death is UNDONE: the checkpoint revive brings it back to life in an otherwise untouched world, and its own
# corpse-splatter must not still be lying at the spot it died. The tag is what makes that sweep surgical:
# an NPC killed in the same firefight leaves its gore exactly where it fell.
#
# Deliberately NOT tagged: the death purse (Player._spill_death_purse) — that MoneyBag is the wallet you have to
# walk back for, not gore, and it is spawned by the Player itself, not here.

## The host's gore tag, re-read per spawn (a virtual call, and the count is single digits per death).
func _tag_group() -> StringName:
	return _host.death_gore_group()

## Join `node` to the host's gore tag, if it has one. No-op for every actor that tags nothing.
func _tag(node: Node) -> void:
	if node == null:
		return
	var group := _tag_group()
	if group != &"":
		node.add_to_group(group)

## Undo this actor's whole death burst: free every world node carrying its gore tag. Returns the number freed
## (0 when the actor tags nothing, or when we're off-tree). queue_free, not free: the burst is RigidBody3Ds and
## this is called from a normal frame, so a deferred free is the only safe one. Nodes already queued are skipped
## so a double-call (or a gib that just expired on its own lifetime) can't be counted twice.
func clear_tagged_gore() -> int:
	var group := _tag_group()
	if group == &"" or not _host.is_inside_tree():
		return 0
	var freed := 0
	for n in _host.get_tree().get_nodes_in_group(group):
		var node := n as Node
		if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		node.queue_free()
		freed += 1
	return freed

## Spawn a flat blood splat decal on the floor beneath the host (on death). Raycasts straight down,
## orients the decal to the hit surface normal, and uses cull_mask = 2 (the world's decal render
## layer) so it lands on level geometry but not on view-model/gun meshes (which live on the gun
## layer). The gib floor-decal logic in bloody_mess.gd mirrors this.
func spawn_blood_decal() -> void:
	if not _host.is_inside_tree():
		return
	var space_state := _host.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		_host.global_position,
		_host.global_position + Vector3.DOWN * 2.0
	)
	query.exclude = [_host]
	var result := space_state.intersect_ray(query)

	if result:
		var decal = Character.BLOOD_SPLAT_DECAL.instantiate()
		if decal == null:  # empty-PackedScene reimport transient -> instantiate() can return null; skip instead of crashing
			return
		_host.get_tree().root.add_child(decal)
		_tag(decal)  # our gore, so the player's revive can wipe its own splat (see _tag_group)

		decal.global_position = result.position + result.normal * 0.02

		decal.cull_mask = 2

		var up: Vector3 = result.normal
		var z: Vector3
		if absf(up.dot(Vector3.UP)) > 0.99:
			z = Vector3.FORWARD.slide(up).normalized()
		else:
			z = Vector3.UP.slide(up).normalized()
		var x := up.cross(z).normalized()
		decal.global_transform.basis = Basis(x, up, z)

## Spawn the on-death corpse/loot drop at the host's spot, launched the way it was knocked/blasted (the
## killing blow), if a ragdoll_scene is assigned. The drop is either a rigged-skeleton Ragdoll (goes limp
## via its own script + consumes the `launch` we set) or a LootBag (a physics Throwable that just falls +
## rests on its own; it ignores `launch`). Both get the LootableCorpse loot child via _attach_loot.
## A loot-gated drop (LootBag.spawn_only_with_loot) is skipped entirely when there's nothing to loot.
func _spawn_ragdoll() -> void:
	if _host.ragdoll_scene == null:
		return
	var corpse := _host.ragdoll_scene.instantiate()
	if corpse == null:  # empty-PackedScene reimport transient -> instantiate() can return null; skip instead of crashing
		return
	# A loot-only drop (a LootBag: the bag IS the loot container) is pointless with nothing to carry, so
	# skip it entirely — an empty-handed kill leaves NO bag. The flag is read off the instance; it's absent
	# (null -> false) on a skeleton Ragdoll, which is a BODY, not a container, and so always spawns. Free
	# the throwaway instance before it ever enters the tree (no _ready side effects, no one-frame flash).
	if bool(corpse.get(&"spawn_only_with_loot")) and not _has_loot():
		corpse.free()
		return
	_sanitize_ragdoll_shapes(corpse)  # fix degenerate (0-size) bone capsules BEFORE they hit the physics server
	corpse.set(&"launch", _host.velocity + _host.explosion_velocity)  # match the death to how we died
	_attach_loot(corpse)  # make the skeleton itself lootable; the ragdoll lingers until emptied
	if corpse is Node3D:
		var c3d := corpse as Node3D
		c3d.position = _host.global_position  # added under root, so local == world
		c3d.rotation.y = _host.global_rotation.y  # face the way we were facing when we died
	_host.get_tree().root.add_child(corpse)
	_tag(corpse)  # the body itself is part of the burst — a revived player must not leave its own corpse behind

## If the dying actor carries ANYTHING — items OR cash — attach a LootableCorpse (its look-at talk hitbox +
## a COPY of the backpack + the wallet) as a child of the ragdoll, and hand the ragdoll the reference so it
## lingers until looted dry (see ragdoll.gd). The copy is independent, so freeing the dead actor can't
## drain the loot. An empty-bagged NPC with zorkmids must still get a loot node, or its wallet is buried.
func _attach_loot(corpse: Node) -> void:
	if not _has_loot():
		return
	var inv: CharacterInventory = _host.inventory
	var wallet: float = _host.money
	var who_v: Variant = _host.get(&"display_name")
	var who: String = who_v if who_v is String else ""
	var loot := LootableCorpse.new()
	loot.setup(inv, who, wallet)
	corpse.add_child(loot)
	corpse.set(&"loot", loot)

## Whether the dying actor carries anything worth a drop — items OR cash. The single source of truth for
## "has something to loot", shared by _attach_loot (whether to build a loot node) and _spawn_ragdoll (whether
## to spawn a loot-gated bag at all), so the two can never disagree. Cash counts: an empty-bagged NPC with
## zorkmids must still leave a lootable drop, or its wallet is buried with it.
func _has_loot() -> bool:
	var inv: CharacterInventory = _host.inventory
	return (inv != null and not inv.is_empty()) or _host.money > 0.0

## Some rigged skeletons import a bone (often the root joint) with a zero-size collision capsule.
## Jolt refuses to build a 0 radius/height shape and spams an error the instant the corpse enters the
## tree. Walk the (not-yet-added) corpse and give any degenerate capsule/sphere a tiny valid size — on
## a DUPLICATED shape so we never resize a resource other bones might share.
func _sanitize_ragdoll_shapes(root: Node) -> void:
	for cs in root.find_children("*", "CollisionShape3D", true, false):
		var shape: Shape3D = (cs as CollisionShape3D).shape
		if shape is CapsuleShape3D:
			var cap := shape as CapsuleShape3D
			if cap.radius <= 0.0 or cap.height <= 0.0:
				var fixed := cap.duplicate() as CapsuleShape3D
				fixed.radius = maxf(fixed.radius, 0.03)
				fixed.height = maxf(fixed.height, fixed.radius * 2.0 + 0.02)
				(cs as CollisionShape3D).shape = fixed
		elif shape is SphereShape3D and (shape as SphereShape3D).radius <= 0.0:
			var fixed_sphere := shape.duplicate() as SphereShape3D
			fixed_sphere.radius = 0.03
			(cs as CollisionShape3D).shape = fixed_sphere

## The whole outward gib burst: the actor's OWN body parts (head / torso / arms / legs, lifted off its
## BodyModelSwap — see _spawn_body_part_gibs) plus generic meat chunks. When body parts fly, the chunk count
## drops to the smaller body_part_gib_meat_count, because up to six limbs are already in the air; with body
## parts off it stays the full gib_count and this behaves exactly as it always did. Both kinds share the
## &"gib" group, the world cap, and one mutual collision-exception pass at the end.
func spawn_gibs() -> void:
	var parts := _spawn_body_part_gibs()
	var meat_count := _meat_gib_count(not parts.is_empty())
	# Keep concurrent gibs under the cap — cull the oldest so a long fight doesn't leave hundreds around.
	# The parts are already in the tree and in the group, so the cap is enforced against the chunks alone;
	# budgeting for the limbs happens on gib_max_active (raised when body parts landed).
	_enforce_gib_cap(meat_count)
	var spawned: Array[RigidBody3D] = []
	spawned.append_array(parts)
	if _host.gib_scene != null:
		for i in meat_count:
			var gib = _host.gib_scene.instantiate()
			if gib == null:  # empty-PackedScene reimport transient -> instantiate() can return null; skip instead of crashing
				continue
			_host.get_tree().root.add_child(gib)
			_tag(gib)  # ownership tag alongside the &"gib" group below — see _tag_group
			gib.begin_gib_lifetime(GameSettings.effects.gib_lifetime, GameSettings.effects.gib_fade_time)  # &"gib" group + timed fade-out
			# Per-spawn fragility roll. Override hp after add_child so _ready (which
			# sets hp from data.max_hp) has already run. Some gibs survive impact,
			# others break on first contact.
			var random_hp: int = randi_range(GameSettings.effects.gib_hp_min, GameSettings.effects.gib_hp_max)
			gib.max_hp = random_hp
			gib.hp = random_hp
			gib.global_position = _host.global_position + Vector3(
				randf_range(-GameSettings.effects.gib_spawn_offset_xz, GameSettings.effects.gib_spawn_offset_xz),
				randf_range(GameSettings.effects.gib_spawn_offset_y_min, GameSettings.effects.gib_spawn_offset_y_max),
				randf_range(-GameSettings.effects.gib_spawn_offset_xz, GameSettings.effects.gib_spawn_offset_xz)
			)
			var dir: Vector3 = Vector3(
				randf_range(-1.0, 1.0),
				randf_range(GameSettings.effects.gib_up_bias_min, GameSettings.effects.gib_up_bias_max),
				randf_range(-1.0, 1.0)
			).normalized()
			gib.linear_velocity = dir * randf_range(GameSettings.effects.gib_vel_min, GameSettings.effects.gib_vel_max)
			gib.angular_velocity = Vector3(
				randf_range(-GameSettings.effects.gib_angular_range, GameSettings.effects.gib_angular_range),
				randf_range(-GameSettings.effects.gib_angular_range, GameSettings.effects.gib_angular_range),
				randf_range(-GameSettings.effects.gib_angular_range, GameSettings.effects.gib_angular_range),
			)
			spawned.append(gib)
	# Mutual collision exceptions so gibs from this death don't collide with
	# each other on spawn — they'd otherwise overlap and the physics engine
	# would shove them apart at high speed, triggering self-damage instantly.
	# Body parts are in this list too: they spawn INSIDE each other's volume (a shoulder overlaps the torso),
	# so without this the solver would blow the body apart at absurd speed and self-damage every limb.
	for i in spawned.size():
		for j in range(i + 1, spawned.size()):
			spawned[i].add_collision_exception_with(spawned[j])

# --- Body-part gibs: the actor comes apart into its OWN limbs -----------------------------------------------
#
# The LEGO / Roblox read. Every part the dying actor is actually WEARING (its BodyModelSwap's live head,
# torso, arms and legs, with that character's own skin and tint) is DUPLICATED onto a BodyPartGib chassis and
# flung from exactly where it sat on the body — so for one frame the silhouette is still the character, and
# then it opens up. Governed by GameSettings.effects.body_part_gibs_enabled, overridden per actor by a
# BodyPartGibs drop-in child.
#
# DUPLICATE, NEVER TAKE: the parts are the SAME node instances a POOLED NPC reuses for its next life (nothing
# rebuilds them — BodyModelSwap has no reset_for_reuse), so reparenting or freeing an original would bring
# that body back permanently limbless. Every original is left untouched.

## Spawn one BodyPartGib per modelled body part and return them (empty when the feature is off for this
## actor, when it has no BodyModelSwap, or when nothing is modelled). Each part is captured at its LIVE world
## transform, so a sitter's ground-snapped pose and a mid-animation limb swing both come apart truthfully.
func _spawn_body_part_gibs() -> Array[RigidBody3D]:
	var out: Array[RigidBody3D] = []
	_burst_pinned = false  # cleared UP FRONT: every early return below would otherwise leave the previous death's
						   # verdict standing for _meat_gib_count (the host is reused under NPC pooling)
	var cfg := _body_part_config()
	if not _body_parts_enabled(cfg):
		return out
	var swap := _find_body_swap()
	if swap == null:
		return out
	# A FIRST-PERSON rig (the player's view-model arms/legs) forces its meshes onto the gun camera's render
	# layer. Those are not a body — they are a HUD prop drawn over the world — so they never gib.
	var vm_layer: Variant = swap.get(&"view_model_layer")
	if (vm_layer is int or vm_layer is float) and float(vm_layer) > 0.0:
		return out
	var parts: Variant = swap.call(&"character_parts")
	if not (parts is Array):
		return out
	var cfg_scene: Variant = cfg.get("scene", null)
	var scene: PackedScene = cfg_scene if cfg_scene is PackedScene else BodyPartGibsScript.default_scene()
	if scene == null:
		return out
	var speed_scale := float(cfg.get("speed_scale", 1.0))
	# Two passes: gather first so the launch directions can radiate from the burst's OWN centre (the mean of
	# the part centres ~ the middle of the chest), not from the host origin, which sits at the feet.
	var pending: Array = []
	var pending_keys := PackedStringArray()  # parallel to `pending` — the PIN needs to name the limb it picked
	var centre_sum := Vector3.ZERO
	for entry in parts:
		if not (entry is Dictionary):
			continue
		var key: String = String((entry as Dictionary).get("key", ""))
		if not _wants_part(cfg, key):
			continue
		var node = (entry as Dictionary).get("node", null)
		var part := node as Node3D
		if part == null or not is_instance_valid(part) or not part.is_inside_tree():
			continue
		var world_xf := part.global_transform
		var gib = scene.instantiate()
		if gib == null:  # empty-PackedScene reimport transient -> instantiate() can return null; skip instead of crashing
			continue
		# MOUNT BEFORE add_child. Throwable._ready both auto-fits the collider from whatever hangs under the
		# mount point AND re-writes the overlay chain (the only thing that severs the dead NPC's per-limb
		# flash material off the duplicate) — mounting afterwards misses both.
		# mount_part TAKES OWNERSHIP of the duplicate — it frees it if it can't be mounted — so a rejected
		# part never leaves an orphan node behind. Only the chassis is ours to free here.
		if not gib.mount_part(part.duplicate(), world_xf):
			gib.free()  # no visible geometry on that part — nothing to fling
			continue
		gib.display_name = PlayerText.body_part(key)  # so the hover prompt reads "Pick Up Head", not just "Pick Up"
		pending.append(gib)
		pending_keys.append(key)
		centre_sum += gib.spawn_origin()
	if pending.is_empty():
		return out
	var burst_centre: Vector3 = centre_sum / float(pending.size())
	# PIN KILL: did a thrown weapon put a marker on this body, and is there a wall behind it? Resolved BEFORE any
	# gib enters the tree — the probe would otherwise have to shoot past six freshly-spawned limbs — using the
	# spawn origins mount_part already computed off-tree. Empty when this is an ordinary death, which is all of
	# them but a thrown-weapon kill, and the whole block below then behaves exactly as it did before pins existed.
	var pin := _resolve_pin(pending, pending_keys)
	_burst_pinned = not pin.is_empty()  # read by _meat_gib_count back in spawn_gibs
	# QUIET THE BURST on a pin kill. The staple only reads as the thing that happened if it IS the thing that
	# happened: at full launch speed the wall gets its limb inside a cloud of five more, all moving, and nobody
	# sees which one behaved differently. Scaled down, the rest of the body crumples where it stood instead.
	if _burst_pinned:
		speed_scale *= GameSettings.effects.pinned_part_burst_speed_scale
	# The killing blow's push, so a rocket blows the body apart downrange instead of straight up. Read the
	# same way the ragdoll reads its launch (velocity + explosion_velocity), then scaled by the inherit knob.
	var inherited: Vector3 = (_host.velocity + _host.explosion_velocity) * GameSettings.effects.body_part_gib_launch_inherit
	for i in pending.size():
		var gib = pending[i]
		_host.get_tree().root.add_child(gib)
		_tag(gib)  # ownership tag alongside the &"gib" group begin_gib_lifetime adds below — see _tag_group
		# The part's own visual centre + facing — it does not move or turn a millimetre on becoming a gib, so
		# the body is still whole for the frame the burst starts. (Added under root, so local == world.)
		gib.global_position = gib.spawn_origin()
		gib.global_basis = gib.spawn_basis()
		# hp / mass AFTER add_child: Throwable._ready sets hp from data.max_hp and mass from data.mass, so an
		# earlier write would be clobbered (the same ordering the meat chunks above rely on).
		var random_hp: int = randi_range(GameSettings.effects.body_part_gib_hp_min, GameSettings.effects.body_part_gib_hp_max)
		gib.max_hp = random_hp
		gib.hp = random_hp
		gib.mass = GameSettings.effects.body_part_gib_mass
		if _burst_pinned and int(pin["index"]) == i:
			# THE stapled limb. No burst velocity and no inherited knockback — begin_pin_flight owns its motion
			# entirely, flying it straight down the ray the probe already cleared. Called AFTER the spawn pose is
			# written, because the seat depth is measured off this limb's live basis and its auto-fitted collider.
			gib.begin_pin_flight(
				pin["point"], pin["dir"],
				GameSettings.effects.pinned_part_flight_speed,
				GameSettings.effects.pinned_part_bury,
				GameSettings.effects.pinned_part_blade_embed,
				pin["blade"], pin["surface"])
			# Its own, longer lifetime: the trophy outlives the loose limbs, and its expiry is also what
			# eventually hands the player's knife back if they never walk over to pull it out.
			gib.begin_gib_lifetime(GameSettings.effects.pinned_part_lifetime, GameSettings.effects.body_part_gib_fade_time)
			out.append(gib)
			continue
		gib.linear_velocity = _part_launch(gib.spawn_origin(), burst_centre) * speed_scale + inherited
		gib.angular_velocity = Vector3(
			randf_range(-GameSettings.effects.body_part_gib_angular_range, GameSettings.effects.body_part_gib_angular_range),
			randf_range(-GameSettings.effects.body_part_gib_angular_range, GameSettings.effects.body_part_gib_angular_range),
			randf_range(-GameSettings.effects.body_part_gib_angular_range, GameSettings.effects.body_part_gib_angular_range),
		)
		gib.begin_gib_lifetime(GameSettings.effects.body_part_gib_lifetime, GameSettings.effects.body_part_gib_fade_time)  # &"gib" group + timed fade-out
		out.append(gib)
	return out

## Decide whether THIS death staples a limb to a wall, and which limb to which point. Returns
## {index, point, dir, blade, surface} — the index into `pending` / `pending_keys` of the limb to pin, the world
## point on the surface, the weapon's travel direction, the blade to embed, and the collider we are pinning to —
## or {} for every death that isn't a pin kill, which is nearly all of them.
##
## The intent is CONSUMED unconditionally the moment there is one (take_pin_hit clears as it reads), even when
## this then rejects the pin: a marker that survived a rejection would be spent by some later death instead.
func _resolve_pin(pending: Array, keys: PackedStringArray) -> Dictionary:
	var fx := GameSettings.effects
	if not fx.pinned_parts_enabled or _host == null or not _host.has_method(&"take_pin_hit"):
		return {}
	var hit: Dictionary = _host.take_pin_hit()
	if hit.is_empty():
		return {}
	# The marker holds a HARD reference to the blade across the death-freeze beat, and the player can pick the
	# knife back up inside that window — which frees the world prop. is_instance_valid FIRST: `is` / `as` on a
	# freed instance is the crash this codebase has hit before, and a freed Object is also falsy, so an
	# `if blade:` test would silently look like "no blade" while `blade is Throwable` took the game down.
	var blade_ref: Variant = hit.get("blade", null)
	if not is_instance_valid(blade_ref):
		return {}
	var blade := blade_ref as Throwable
	if blade == null or not blade.is_inside_tree():
		return {}
	var contact: Vector3 = hit.get("contact", Vector3.INF)
	var dir: Vector3 = hit.get("dir", Vector3.ZERO)
	if not contact.is_finite() or dir.length_squared() < 0.000001:
		return {}
	# WHICH limb: the one whose live visual centre is nearest the strike. See PartPinner.nearest_key for why this
	# and not Character.body_part_at — in short, that classifier has no left/right and desyncs on a seated actor.
	var entries: Array = []
	for i in pending.size():
		entries.append({"key": keys[i], "centre": pending[i].spawn_origin()})
	var key := PartPinnerScript.nearest_key(contact, entries)
	if key == "":
		return {}
	# The pinnable set is its OWN filter, not the BodyPartGibs burst toggles: those answer "does this actor come
	# apart into limbs", which wants all six, while this answers "is this limb worth looking at on a wall", which
	# ships as head + torso. Reusing wants_part's pure signature keeps one home for the key -> toggle mapping.
	if not BodyPartGibsScript.wants_part(key, fx.pinned_part_head, fx.pinned_part_torso, fx.pinned_part_arms, fx.pinned_part_legs):
		return {}
	var index := keys.find(key)
	if index < 0:
		return {}
	# has_method, not a bare call later: a designer may point BodyPartGibs.part_gib_scene at their OWN chassis, and
	# that contract only asks for a Throwable with the mount-point surface — pinning is newer than the contract, so
	# a chassis without it bursts normally instead of taking the whole death path down. Checked HERE rather than at
	# the launch so _burst_pinned (which also quiets the burst and the chunk count) can never claim a pin that the
	# chassis is then unable to perform.
	if not (pending[index] as Object).has_method(&"begin_pin_flight"):
		return {}
	# WHERE: already decided. The wall was probed at STRIKE time by Throwable._probe_pin_surface, because this
	# code does NOT run in a physics frame (an NPC's gore() fires from the death-freeze SceneTreeTimer, on the
	# idle frame) and a space-state query here comes back empty however solid the wall is. Do not "simplify" this
	# by moving the raycast back down here — that is the exact bug that shipped and made the feature inert.
	var surface: Dictionary = hit.get("surface", {})
	if surface.is_empty():
		return {}
	var collider: Variant = surface.get("collider", null)
	if not is_instance_valid(collider):
		return {}  # the wall was freed during the death-freeze beat (a level swap mid-kill)
	var point: Vector3 = surface.get("point", Vector3.INF)
	if not point.is_finite():
		return {}
	return {
		"index": index,
		"point": point,
		"dir": dir,
		"blade": blade,
		"surface": collider,
	}

## The launch velocity for a part sitting at `origin` in a burst centred on `centre`: OUTWARD from the centre
## (so the head goes up, the legs go out, the arms go sideways — the body visibly opens up rather than
## scattering at random), never downward into the floor, jittered by body_part_gib_spread, with an upward pop
## added on top. A part sitting exactly at the centre falls back to straight up.
func _part_launch(origin: Vector3, centre: Vector3) -> Vector3:
	var dir := origin - centre
	dir.y = maxf(dir.y, 0.0)  # never fire a limb through the ground it's standing on
	if dir.length_squared() < 0.0001:
		dir = Vector3.UP
	dir = dir.normalized()
	var spread: float = GameSettings.effects.body_part_gib_spread
	if spread > 0.0:
		dir = (dir + Vector3(randf_range(-spread, spread), randf_range(-spread, spread), randf_range(-spread, spread))).normalized()
	var speed := randf_range(GameSettings.effects.body_part_gib_vel_min, GameSettings.effects.body_part_gib_vel_max)
	var pop := randf_range(GameSettings.effects.body_part_gib_up_bias_min, GameSettings.effects.body_part_gib_up_bias_max)
	return dir * speed + Vector3.UP * pop

## How many MEAT chunks this death sprays. With body parts in the air it's the smaller
## body_part_gib_meat_count (per-actor overridable on the BodyPartGibs drop-in); otherwise the full gib_count,
## unchanged from before body parts existed. Floored at 0 so a negative authored value can't feed a bad loop.
func _meat_gib_count(parts_flew: bool) -> int:
	if not parts_flew:
		return maxi(GameSettings.effects.gib_count, 0)
	var cfg := _body_part_config()
	var global_count: int = GameSettings.effects.body_part_gib_meat_count
	# A PIN kill sprays its own (lower, shipped as zero) chunk count for the same reason it quiets the limb burst:
	# loose gore competes with the one thing the player is meant to be looking at. -1 inherits the normal count.
	if _burst_pinned:
		global_count = BodyPartGibsScript.resolve_meat_count(GameSettings.effects.pinned_part_meat_count, global_count)
	# A per-actor override still wins over both — that is an explicit designer decision about THIS character.
	var count := BodyPartGibsScript.resolve_meat_count(int(cfg.get("meat_gib_count", -1)), global_count)
	return maxi(count, 0)

## The per-actor BodyPartGibs override as a plain config Dictionary, or {} when the actor has none. Direct
## children only — the same shallow scan npc.gd uses to find the BodyModelSwap, and what the component's
## docstring promises a designer. Duck-typed on the marker method (never `is BodyPartGibs`): this script is
## on Character's parse path, and a brand-new class_name referenced from here fails to resolve until the
## editor registers it in its global class cache, taking every actor script down with it.
func _body_part_config() -> Dictionary:
	for c in _host.get_children():
		if c.has_method(&"body_part_gib_config"):
			var cfg: Variant = c.call(&"body_part_gib_config")
			if cfg is Dictionary:
				return cfg
	return {}

## Whether THIS actor comes apart into body parts: a BodyPartGibs drop-in is the authority when one is
## present (so it can turn the burst on for one actor while the global switch is off, and off while it's on);
## otherwise the global GameSettings.effects switch decides.
func _body_parts_enabled(cfg: Dictionary) -> bool:
	if cfg.is_empty():
		return GameSettings.effects.body_part_gibs_enabled
	return bool(cfg.get("enabled", true))

## Whether this actor flings the part with the given character_parts() key. No component -> every modelled
## part flies (the default-on behaviour); with one, its four per-part toggles decide.
func _wants_part(cfg: Dictionary, key: String) -> bool:
	if cfg.is_empty():
		return true
	return BodyPartGibsScript.wants_part(key,
		bool(cfg.get("head", true)), bool(cfg.get("torso", true)),
		bool(cfg.get("arms", true)), bool(cfg.get("legs", true)))

## The host's BodyModelSwap — the source of the flying parts. Duck-typed on character_parts() rather than
## `is BodyModelSwap`, mirroring npc.gd's _find_body_swap so this stays host-agnostic (the Player rig and the
## unit-test stubs both satisfy the same marker method).
func _find_body_swap() -> Node:
	for c in _host.get_children():
		if c.has_method(&"character_parts"):
			return c
	return null

## Cull the oldest gibs so that spawning `incoming` more keeps the total at/under
## GameSettings.effects.gib_max_active. Gibs register in the &"gib" group (begin_gib_lifetime); the
## group is roughly insertion-ordered, so the front entries are the oldest — free those first.
func _enforce_gib_cap(incoming: int) -> void:
	var gibs := _host.get_tree().get_nodes_in_group(Groups.GIB)
	var over: int = gibs.size() + incoming - GameSettings.effects.gib_max_active
	var i := 0
	while i < over and i < gibs.size():
		if is_instance_valid(gibs[i]):
			gibs[i].queue_free()
		i += 1

func _notify_nearby_players_of_death() -> void:
	var range_max := maxf(GameSettings.effects.blood_splatter_range, GameSettings.screen_shake.death_shake_range)
	var players := _host.get_tree().get_nodes_in_group(Groups.PLAYER)
	for p in players:
		if p == _host:
			continue
		if not p is Node3D:
			continue
		var d := _host.global_position.distance_to(p.global_position)
		if d > range_max:
			continue
		if p.has_method("on_nearby_death"):
			p.on_nearby_death(d)
