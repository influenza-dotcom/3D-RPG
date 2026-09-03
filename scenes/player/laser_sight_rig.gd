extends SpotLight3D

## The player's LASER SIGHT — the red DOT projected onto the world where your shot will actually land, plus the
## short beam cone at the muzzle (the sibling LaserMesh, whose visibility this node drives). It is an UNLOCKABLE:
## the dot stays dark until the wielder has the `laser_sight` mechanic, granted by the LaserSight Ability node
## (resources/items/chip_laser_sight.tres installs it).
##
## ⭐THERE IS NO KEY AND THERE IS NO TOGGLE. If you own the chip and it is switched on, the laser is on. This is
## the deliberate difference from the node it was carved out of: the laser USED to live on the flashlight and
## share its key, which is exactly what killed it when the torch claimed that key for itself
## (scenes/player/flash_light.gd). A sight you have to remember to switch on is a sight you are not using when it
## matters, and the Implants tab already owns an on/off switch for every implant — `enabled` on the Ability node,
## which `has_mechanic` reads — so a second, per-frame switch would be a second answer to the same question.
## Adding a keybind here would also mean four new name surfaces plus its own modal gate, for a toggle the implant
## screen already provides.
##
## ⭐IT IS A SEPARATE NODE FROM THE FLASHLIGHT ON PURPOSE, and must stay one. The two were one SpotLight3D until
## the torch landed; the torch is now a wide white shadow-casting lamp with a gradient projector and a stealth
## cost, and the laser is a 0.5-degree energy-1000 pinprick with neither. tests/test_flashlight.gd pins that
## shape split from both sides (the torch must not gate on the weapon's laser flag; this node must not grow a
## key). Keep them apart.
##
## ⭐THE DOT SHOWS WHERE THE SHOT LANDS, NOT WHERE THE CAMERA POINTS — that is the entire feature. The shot is a
## ray from the CAMERA (Player.get_aim_origin) along the SWAYED aim (Player.get_aim_direction, which carries the
## Deus Ex aim wander), while this light sits at the MUZZLE. Aiming the light merely parallel to the aim would
## offset the dot from the real impact by muzzle/camera parallax — the "dot doesn't line up with where I'm
## aiming" bug. So we converge instead: point the light from the muzzle AT a point on the camera ray, `spot_range`
## metres out. The dot then sits on the true impact point and visibly WANDERS with the sway, which is what makes
## the wander readable at all — without this, AimSway is felt but never seen (see Player.get_aim_direction).
##
## ⭐IT COSTS NO STEALTH, BY GROUP MEMBERSHIP, AND THAT IS NOT OPTIONAL. PlayerLightLevel auto-collects EVERY
## visible Light3D in the scene and weighs it by energy and distance — and this lamp is energy 1000 sitting AT the
## player. Left ungrouped it would saturate the light meter the instant the chip was fitted, so buying a laser
## sight would silently mean "enemies always see you", with nothing anywhere reporting it. Joining
## Groups.STEALTH_LIGHT_EXEMPT in _ready is what keeps a 0.5-degree dot from reading as a floodlight. (The torch
## makes the opposite trade deliberately, via Groups.CARRIED_LIGHT — see flash_light.gd. A laser is a thread of
## light landing on a wall metres away; it is not lighting YOU.)
##
## ORIGIN: the equipped weapon's own "Muzzle" marker, so the dot leaves whatever gun is actually held, falling
## back to the view-model rig's built-in muzzle. Deliberately NOT the rig's `LightPosition` marker (which the old
## shared node used) — that marker has since moved off to the player's LEFT to give the TORCH its off-hand
## shadow-casting origin, and a laser thrown from the off hand while the gun is in the right one is just wrong.

## The mechanic this node draws for — the id the LaserSight Ability grants and the chip installs.
const MECHANIC := &"laser_sight"

## How snappily the dot chases your aim. This is the SHIPPED feel of the original sight (a faint trail behind a
## fast flick, dead steady when you are still); raise it to weld the dot to the aim, lower it for a heavier drag.
## The easing is exp-based, so the feel is identical at any frame rate.
@export var follow_rate: float = 15.0
## The muzzle beam cone (the sibling LaserMesh). Its VISIBILITY is driven here so the beam and the dot can never
## disagree about whether the sight is on; its per-frame ALIGNMENT is its own script's job (laser_mesh.gd).
## Optional — leave unset for a dot with no beam.
@export var beam: MeshInstance3D

@onready var _gun_mesh: GunMesh = get_node_or_null("../GunMesh") as GunMesh
## The view-model rig's built-in muzzle: the origin fallback when no swapped-in weapon model offers its own marker.
@onready var _rig_muzzle: Marker3D = get_node_or_null("../GunMesh/Sketchfab_Scene/PlayerMuzzle") as Marker3D

var _wielder: Node = null  ## the owning Player, found by ancestor walk (duck-typed; null on a bare test rig)
var _attack: Node = null   ## the Weapon/Attack node, resolved off the wielder and re-resolved if ever freed


func _ready() -> void:
	# Detach from the parent transform: position and rotation are both driven manually below, because the dot is
	# aimed at a converged point rather than welded to the camera's facing.
	top_level = true
	visible = false  # nothing is drawn until _process proves the mechanic is active and a sighted gun is out
	_wielder = _find_wielder()
	# ⭐The stealth exemption — see the class doc. A membership, not a branch in PlayerLightLevel, so "who feeds
	# detection" keeps exactly one home. Static: the sampler re-reads `visible` every tick, so the gates below
	# already turn any contribution off without touching groups.
	_exempt_from_the_light_meter(self)


## Join Groups.STEALTH_LIGHT_EXEMPT, and take EVERY descendant Light3D with us. The dot is authored as a PAIR —
## the bright red spot plus a NEGATIVE sub-light that carves its core down to a pinprick — and the sampler's
## `_light_contribution_for` weighs a light by `light_energy` alone: it never reads `light_negative`, so the
## carving light would be summed as a second energy-1000 floodlight rather than subtracted. Exempting only the
## node this script sits on would therefore leave the worse half of the pair feeding detection. Walking the
## subtree also covers a designer adding a third lamp to shape the dot later.
func _exempt_from_the_light_meter(n: Node) -> void:
	if n is Light3D:
		n.add_to_group(Groups.STEALTH_LIGHT_EXEMPT)
	for c in n.get_children():
		_exempt_from_the_light_meter(c)


## The owning Player, located by walking ANCESTORS for the mechanic surface rather than by a deep relative path
## (the old shared node's `../../../../Weapon/Attack` broke every time the rig moved). Duck-typed: anything that
## answers has_mechanic will do, and a bare rig in a test finds nothing and simply stays dark.
func _find_wielder() -> Node:
	var n: Node = get_parent()
	while n != null:
		if n.has_method(&"has_mechanic"):
			return n
		n = n.get_parent()
	return null


## The Weapon/Attack node off the wielder, cached. Re-resolved whenever the cached one has been freed, so a
## rebuilt weapon rig re-links itself instead of going permanently dark.
func _attack_node() -> Node:
	if is_instance_valid(_attack):
		return _attack
	_attack = null
	if _wielder != null:
		_attack = _wielder.get_node_or_null("Weapon/Attack")
	return _attack


func _process(delta: float) -> void:
	var attack: Node = _attack_node()
	var weapon: Object = attack.current_weapon if attack != null else null
	# ⭐`_wielder` is Node-typed, so has_mechanic() resolves dynamically (Variant) and the whole or-chain has NO
	# inferable type — `:=` here is a PARSE ERROR that would kill this entire script. Annotate every duck-typed
	# bool explicitly. Same for the liveness read below.
	var unlocked: bool = _wielder != null and _wielder.has_mechanic(MECHANIC)
	# A DEAD wielder's sight goes out: die() never holsters the weapon or touches this node, and _process keeps
	# running through the whole death cinematic — without this the corpse sweeps a live tracking dot across the
	# world while the camera rolls. Duck-typed (a rig with no wielder counts as alive), and is_alive() flips back
	# on respawn, so the sight simply returns.
	var alive: bool = _wielder == null or not _wielder.has_method(&"is_alive") or _wielder.is_alive()
	# The gun must be OUT and SETTLED, not still tweening up from a reload or a swap — otherwise the dot draws
	# from a half-raised muzzle and skates across the floor. GunMesh.is_raised() derives its window from the same
	# designer knob as the raise tween, so the gate cannot drift from the animation.
	var gun_ready: bool = _gun_mesh == null or _gun_mesh.is_raised()
	# `has_laser_sight` is the per-weapon "this gun wears a sight" flag: false on fists, melee and the spray can,
	# so a laser never sprouts from a fist. (It also gates the NPC aiming beam — one authored flag, both sides.)
	var sighted: bool = weapon != null and bool(weapon.get(&"has_laser_sight"))

	visible = unlocked and alive and sighted and gun_ready and attack != null and not attack.holstered
	if is_instance_valid(beam):
		beam.visible = visible
	if not visible:
		return

	# Throw exactly as far as the gun shoots, so the dot dies at the edge of the weapon's useful range instead of
	# painting a wall on the far side of the map. Read defensively: `.get()` on an absent property returns null,
	# and float(null) is a hard constructor error, not a quiet 0.
	var reach: Variant = weapon.get(&"effective_range")
	var range_m: float = float(reach) if (reach is float or reach is int) else 0.0
	spot_range = range_m if range_m > 0.0 else 15.0

	global_position = _muzzle_origin()
	# Converge on the camera ray at the throw distance — this is the parallax correction the class doc explains.
	# No per-frame space query: a raycast from _process can hit the locked physics space and freeze the aim.
	var target_rot: Vector3 = get_parent().global_rotation
	if _wielder != null and _wielder.has_method(&"get_aim_direction") and _wielder.has_method(&"get_aim_origin"):
		var aim_dir: Vector3 = _wielder.get_aim_direction()
		if aim_dir.length_squared() > 0.0001:
			var converge: Vector3 = _wielder.get_aim_origin() + aim_dir * maxf(spot_range, 1.0)
			var to_point := converge - global_position
			# The y-guard keeps looking_at away from its degenerate straight-up/straight-down case.
			if to_point.length_squared() > 0.0001 and absf(to_point.normalized().y) < 0.99:
				target_rot = Basis.looking_at(to_point).get_euler()
	var t := 1.0 - exp(-follow_rate * delta)
	global_rotation.x = lerp_angle(global_rotation.x, target_rot.x, t)
	global_rotation.y = lerp_angle(global_rotation.y, target_rot.y, t)
	global_rotation.z = lerp_angle(global_rotation.z, target_rot.z, t)


## Where the beam leaves the gun: the equipped weapon model's own "Muzzle" marker (case-insensitive, via the
## MuzzleRig), else the view-model rig's built-in one. The SAME source laser_mesh.gd uses for the beam cone, so
## the dot and the beam always start from one point.
func _muzzle_origin() -> Vector3:
	var anchor: Node3D = _gun_mesh.equipped_marker("muzzle") if _gun_mesh != null else null
	if not is_instance_valid(anchor):
		anchor = _rig_muzzle
	return anchor.global_position if is_instance_valid(anchor) else global_position
