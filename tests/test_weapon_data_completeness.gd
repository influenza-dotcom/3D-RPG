extends GutTest
# Content contracts for the shipped weapon roster: every .tres in res://resources/weapons/ loads as a WeaponData with
# its fields at the declared types, and the roster-wide authoring rules hold (weight classes, the knife's hand and
# throw pose, the held/thrown flags, the agility floors). Relations and driven poses rather than tuning literals, so a
# balance retune stays green and a weapon that breaks the rule goes red.

const WEAPONS_DIR := "res://resources/weapons/"
## The knife's world Item: the drop tests below build it through the real WorldItem.build path.
const KNIFE_ITEM := "res://resources/items/melee_item.tres"
## Axis conventions of the imported MODELS (facts about the meshes, documented on WeaponData.npc_hold_rotation and
## thrown_face_rotation_degrees): the knife's BLADE points down its view-model root's -X (the reverse of a gun's +X
## barrel), and an NPC's hand anchor faces +Z.
const KNIFE_BLADE_AXIS := Vector3.LEFT
const NPC_HAND_FORWARD := Vector3.BACK
## How much SHORTER (as a fraction of the box) the posed knife may be than its hand-tuned drop collider. Loose on
## purpose: a little air inside the box is harmless, but a model re-posed far smaller than the box it was tuned against
## is the wrong scale.
const COLLIDER_FIT_TOLERANCE := 0.15
## How much LONGER (as a fraction of the box) the posed knife may be than that collider. Tight on purpose: any blade
## past the box is a blade the physics can't see, so this only absorbs mesh-bounds rounding, not a scale drift.
const COLLIDER_POKE_SLACK := 0.03
## The long guns, heaviest first: each must slow you while drawn, and each more than the next.
const LONG_GUNS_HEAVIEST_FIRST: Array[String] = ["shotgun", "sniper_wep", "smg"]
## Everything else you can draw, bare fists included: none of it may slow you.
const UNPENALISED_WEAPONS: Array[String] = ["pistol", "melee", "rock_weapon", "spray_paint", "fists"]

func test_all_weapon_tres_have_required_fields() -> void:
	var files := _list_tres()
	assert_gt(files.size(), 0,
		"There must be at least one weapon .tres in %s to validate" % WEAPONS_DIR)
	for path in files:
		_check_weapon(path)

func _list_tres() -> Array:
	var out: Array = []
	var dir := DirAccess.open(WEAPONS_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var _name := dir.get_next()
	while _name != "":
		if not dir.current_is_dir() and _name.ends_with(".tres"):
			out.append(WEAPONS_DIR + _name)
		_name = dir.get_next()
	dir.list_dir_end()
	return out

func _check_weapon(path: String) -> void:
	var w := load(path) as WeaponData
	assert_not_null(w, "%s must load as a WeaponData" % path)
	# damage is declared `float = 1.0` in weapon_data.gd — the .tres int-looking
	# literals still parse as floats, so this is TYPE_FLOAT (NOT TYPE_INT).
	_check_field(w, "damage", TYPE_FLOAT, path)
	_check_field(w, "attack_speed", TYPE_FLOAT, path)
	_check_field(w, "reload_time", TYPE_FLOAT, path)
	# max_ammo and pellet_count are genuinely `int` in source (whole rounds /
	# whole pellets), so they stay TYPE_INT.
	_check_field(w, "max_ammo", TYPE_INT, path)
	_check_field(w, "pellet_count", TYPE_INT, path)
	_check_field(w, "pellet_spread", TYPE_FLOAT, path)
	# Per-weapon multiplier on the global per-shot stamina cost (GameSettings.player_movement.stamina_shot_cost).
	# Declared `float = 1.0`, so an int-looking .tres literal (`stamina_cost_mult = 2`) still parses as a FLOAT —
	# the same trap damage above documents. The BALANCE of the authored values is swept by test_combat_data.gd.
	_check_field(w, "stamina_cost_mult", TYPE_FLOAT, path)
	# The weapon-side STEALTH lever: multiplies how far this gun's shot carries (player.gd on_weapon_fired ->
	# NoiseEmitter.gunfire(mult)). Declared `float = 1.0`, so an authored `noise_radius_mult = 0` in a .tres
	# would still parse FLOAT — the same int-literal trap damage above documents. A suppressor MULTs it down.
	_check_field(w, "noise_radius_mult", TYPE_FLOAT, path)
	# Does a round from this weapon explode? A pricing/authoring FACT, not a behaviour switch - nothing on
	# WeaponData can otherwise tell an explosive apart (explosion_radius defaults 4.0 on every weapon and
	# max_explosion_force defaults 20.0, so the PISTOL nominally out-blasts the launcher's authored 10.0).
	_check_field(w, "projectile_explodes", TYPE_BOOL, path)
	# Phase 4 additions
	_check_field(w, "screen_shake_amount", TYPE_FLOAT, path)
	_check_field(w, "self_knockback", TYPE_FLOAT, path)
	_check_field(w, "enemy_knockback", TYPE_FLOAT, path)
	_check_field(w, "enemy_lift", TYPE_FLOAT, path)
	_check_field(w, "bullet_gravity_scale", TYPE_FLOAT, path)
	# AI dodge-window dial: multiplies projectile_speed ONLY for an AI wielder's rounds (ProjectileSpawner
	# round_speed) — enemies never hitscan, so this is what makes their fire visibly dodgeable per weapon.
	_check_field(w, "npc_projectile_speed_mult", TYPE_FLOAT, path)
	# AI BURST fire: how many rounds an NPC answers one trigger pull with, and the gap between them (0 = the
	# gun'''s own attack_speed). npc_burst_count is genuinely `int` in source (whole rounds), like pellet_count
	# above; the interval is `float = 0.0`, so an int-looking `npc_burst_interval = 0` in a .tres still parses
	# FLOAT — the same trap damage above documents. Player fire never reads either.
	_check_field(w, "npc_burst_count", TYPE_INT, path)
	_check_field(w, "npc_burst_interval", TYPE_FLOAT, path)
	_check_field(w, "launch_angle", TYPE_FLOAT, path)
	_check_field(w, "max_explosion_force", TYPE_FLOAT, path)
	_check_field(w, "explosion_radius", TYPE_FLOAT, path)
	# NPC hand-hold override (lets a view-model whose ROOT bakes a first-person-only pose — the knife — sit
	# right in an NPC's hand; npc.gd _build_weapon_mesh reads these). Off by default so guns are untouched.
	_check_field(w, "npc_hold_override", TYPE_BOOL, path)
	_check_field(w, "npc_hold_position", TYPE_VECTOR3, path)
	_check_field(w, "npc_hold_rotation", TYPE_VECTOR3, path)
	_check_field(w, "npc_hold_scale", TYPE_FLOAT, path)
	# Fist trim: pulls an ENLARGED model back onto the hand (the display boost below scales the model's baked
	# forward offset along with its size). NPC-hand only — drops and the preview never read it.
	_check_field(w, "npc_hold_trim", TYPE_VECTOR3, path)
	# Held-out readability boost (npc.gd _build_weapon_mesh MULTIPLIES it onto whatever scale survives the mount:
	# a gun's baked FP root scale, or an override weapon's npc_hold_scale — one field, one meaning for every
	# weapon). Display-only: the FP view-model, ground drops, icons, and preview never read it.
	_check_field(w, "npc_held_display_scale", TYPE_FLOAT, path)
	# In-flight streak for a THROWN copy (WorldItem._make_throwable stamps a ThrowTrail child from these; the
	# effect is scripts/components/throw_trail.gd). Off by default — a gun tumbles away without one.
	_check_field(w, "thrown_trail", TYPE_BOOL, path)
	_check_field(w, "thrown_trail_color", TYPE_COLOR, path)
	# The six fitted-mod slot ids (weapon_data.gd @export_group("Modifications")). These are @export_STORAGE:
	# invisible in the inspector, never authored, written only by WeaponBench via WeaponModKit.rebuild — but
	# they are still SCRIPT_VARIABLE, which is precisely what makes ItemDb.weapon_delta_for diff them onto the
	# EXISTING weapon_delta save key with no new save plumbing. Two things are pinned here and nowhere else:
	#   • the declared type stays TYPE_STRING_NAME — it is in ItemDb._is_weapon_delta_type's allow-list, so a
	#     drift to String/int would silently drop every fitted part from the save with no error anywhere;
	#   • a shipped weapon .tres ships BLANK (asserted below) — a stray authored id in a TEMPLATE would give
	#     every instance of that gun a permanent non-empty delta and a mod nobody fitted.
	# Iterating MOD_SLOT_PROPS rather than a second hand-list means a seventh slot stays the three coordinated
	# edits weapon_data.gd promises; the array's own order/length is pinned by tests/test_weapon_mods.gd.
	for prop in WeaponData.MOD_SLOT_PROPS:
		_check_field(w, String(prop), TYPE_STRING_NAME, path)
		assert_eq(StringName(w.get(String(prop))), &"",
			"%s.%s must ship BLANK — mod slots are runtime-owned, never authored into a template" % [path, prop])

func _check_field(obj: Object, field: String, expected_type: int, src: String) -> void:
	assert_true(field in obj, "%s must have field '%s'" % [src, field])
	var actual_type := typeof(obj.get(field))
	assert_eq(actual_type, expected_type,
		"%s.%s has type %d, expected %d" % [src, field, actual_type, expected_type])

func _weapon(wep: String) -> WeaponData:
	return load(WEAPONS_DIR + wep + ".tres") as WeaponData

# --- move_speed_multiplier: "heavier weapons slow you while drawn" ---
# GroundMovement.compute_target_speed (the player) and WeaponStance.current_move_speed (an NPC) MULTIPLY the wielder's
# speed by the drawn weapon's move_speed_multiplier. The numbers themselves are balance and free to retune; what these
# pin is the WEIGHT CLASS each weapon ships in. Together they make the shotgun the heaviest thing you can draw, and the
# last test says so outright.

# Zero does not slow you, it roots you in place the moment the weapon comes out, and a negative value turns your
# movement keys around. Walks the disk rather than a hand list, so a NEW weapon .tres is caught the day it lands.
func test_no_weapon_roots_or_reverses_its_wielder_while_drawn() -> void:
	var files := _list_tres()
	assert_gt(files.size(), 0, "there must be weapons to check")
	for path in files:
		var w := load(path) as WeaponData
		if w == null:
			continue  # the field-type sweep above already fails a .tres that isn't a WeaponData
		assert_gt(w.move_speed_multiplier, 0.0,
			"%s authors move_speed_multiplier %.3f: drawing it would freeze (0) or reverse (<0) whoever holds it" % [path, w.move_speed_multiplier])

# The long guns carry a real penalty that grows with the gun: the shotgun slows you most, the sniper less, the SMG
# only a little. A retune that keeps that order stays green; a sniper retuned heavier than the shotgun goes red.
func test_long_guns_slow_you_more_the_heavier_they_are() -> void:
	var heavier := ""
	var heavier_mult := 0.0
	for wep in LONG_GUNS_HEAVIEST_FIRST:
		var w := _weapon(wep)
		assert_not_null(w, "%s.tres must load as a WeaponData" % wep)
		if w == null:
			return
		assert_lt(w.move_speed_multiplier, 1.0,
			"%s is a long gun and must slow you while drawn, but authors move_speed_multiplier %.3f" % [wep, w.move_speed_multiplier])
		if heavier != "":
			assert_lt(heavier_mult, w.move_speed_multiplier,
				"%s (%.3f) must slow you MORE than %s (%.3f): the weight order is shotgun, then sniper, then SMG" % [heavier, heavier_mult, wep, w.move_speed_multiplier])
		heavier = wep
		heavier_mult = w.move_speed_multiplier

# The pistol, knife, rock launcher and spray can carry no movement penalty, and neither do bare fists: they are the
# unarmed fallback, and being unarmed must never be slower than having your gun holstered. A value above 1.0 (a
# speed-up) is allowed, a value below it is not.
func test_light_weapons_and_bare_fists_never_slow_you() -> void:
	for wep in UNPENALISED_WEAPONS:
		var w := _weapon(wep)
		assert_not_null(w, "%s.tres must load as a WeaponData" % wep)
		if w == null:
			continue
		assert_gte(w.move_speed_multiplier, 1.0,
			"%s must not slow you while drawn (only the long guns do), but authors move_speed_multiplier %.3f" % [wep, w.move_speed_multiplier])

# Walks the disk rather than the two weight-class lists above, so a NEWLY authored weapon heavier than the shotgun is
# caught even before anyone files it into a class.
func test_shotgun_is_the_heaviest_weapon_you_can_draw() -> void:
	var shotgun := _weapon("shotgun")
	assert_not_null(shotgun, "shotgun.tres must load as a WeaponData")
	if shotgun == null:
		return
	var files := _list_tres()
	assert_gt(files.size(), 1, "there must be weapons besides the shotgun to compare against")
	for path in files:
		if path == WEAPONS_DIR + "shotgun.tres":
			continue
		var w := load(path) as WeaponData
		if w == null:
			continue  # the field-type sweep above already fails a .tres that isn't a WeaponData
		assert_lt(shotgun.move_speed_multiplier, w.move_speed_multiplier,
			"the shotgun (%.3f) must slow you more than %s (%.3f): it is the heaviest weapon in the game" % [shotgun.move_speed_multiplier, path, w.move_speed_multiplier])

# Fists are the unarmed fallback NPCs use with nothing equipped. The actual values are the designer's to
# tune, so this just pins that it LOADS and is functional — positive damage / reach / cadence (the wind-up
# in _shot_interval divides by attack_speed, and _act_unarmed closes to effective_range).
func test_fists_loads_as_a_usable_melee_weapon() -> void:
	var w := load("res://resources/weapons/fists.tres") as WeaponData
	assert_not_null(w, "fists.tres must load as a WeaponData")
	assert_gt(w.damage, 0.0, "fists must deal some damage")
	assert_gt(w.effective_range, 0.0, "fists need a positive reach (the close-to distance)")
	assert_gt(w.attack_speed, 0.0, "fists need a positive swing cadence (the wind-up divides by it)")

# --- NPC hand-hold (knife) ---
# The knife's view_model (knife.tscn) bakes a first-person-only pose in its ROOT (scale 1.585, a Z-tilt, a
# forward offset for the player's gun camera). An NPC hangs the SAME scene off its hand anchor; without the
# override it inherited that baked scale + offset and only corrected yaw, so the knife floated ~0.45 m off the
# hand, oversized. The override is what fixes it, and its pose has to put the blade (mesh -X) down the hand's +Z
# forward, upright. Posed here the way npc.gd _build_weapon_mesh poses it (rotation_degrees on the model root), so
# any Euler triple that lands the blade forward passes and a gun's -90 yaw copied onto the knife does not.
func test_knife_blade_points_forward_in_an_npc_hand() -> void:
	var w := _weapon("melee")
	assert_not_null(w, "melee.tres must load as a WeaponData")
	if w == null:
		return
	assert_true(w.is_melee, "the knife is a melee weapon")
	assert_true(w.npc_hold_override, "the knife MUST override the NPC hand-hold — its view_model bakes an FP-only root pose")
	var mount := Node3D.new()
	mount.rotation_degrees = w.npc_hold_rotation
	var blade := mount.basis * KNIFE_BLADE_AXIS
	var up := mount.basis * Vector3.UP
	mount.free()
	assert_almost_eq(blade.dot(NPC_HAND_FORWARD), 1.0, 0.001,
		"npc_hold_rotation %s points the knife's blade along %s, not the NPC's +Z forward: enemies would hold it handle-first or sideways" % [w.npc_hold_rotation, blade])
	assert_almost_eq(up.dot(Vector3.UP), 1.0, 0.001,
		"npc_hold_rotation %s tips the knife off upright (model up now %s): the blade would be held rolled or pitched" % [w.npc_hold_rotation, up])
	# ...and the NPC-hand readability boost is what makes it READ at NPC viewing distance. It rides on top of
	# npc_hold_scale (which the ground drop and the character preview also read), so the held knife can be
	# enlarged for the hand WITHOUT resizing the dropped/thrown copy — whose dropped_collision_size is
	# hand-tuned to the native blade (pinned against the real mesh by the drop test below).
	assert_gt(w.npc_held_display_scale, 1.0,
		"the knife must still get an NPC-hand size boost, or it vanishes into a 0.75 m arm")

## Bounds of every MeshInstance3D under `node`, in the DROP's local space (the walk Throwable._collect_visual_aabb
## does). An empty dictionary means nothing renders.
func _visual_bounds(node: Node, xf: Transform3D, state: Dictionary) -> Dictionary:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var box := xf * mi.mesh.get_aabb()
			state["aabb"] = box if not state.has("aabb") else (state["aabb"] as AABB).merge(box)
	for child in node.get_children():
		var child_xf := xf
		if child is Node3D:
			child_xf = xf * (child as Node3D).transform
		_visual_bounds(child, child_xf, state)
	return state

## The knife dropped through the real WorldItem.build path (case 3: its view model, re-posed by the npc_hold_* fields),
## or null after failing the test. Off-tree: Throwable._ready never runs. The caller frees it.
func _build_knife_drop() -> Throwable:
	var item := load(KNIFE_ITEM) as Item
	assert_not_null(item, "%s must load as an Item" % KNIFE_ITEM)
	if item == null:
		return null
	var drop := WorldItem.build(item, 1)
	if not (drop is Throwable):
		fail_test("dropping the knife must build a Throwable (WorldItem.build case 3), got %s" % drop)
		if is_instance_valid(drop):
			drop.free()
		return null
	return drop as Throwable

# The drop re-poses the knife at NATIVE size, which is the size its hand-tuned dropped_collision_size (a slender box
# long in local Z, the axis a throw noses along) was measured against. Measured from the real posed mesh bounds: a
# knife dropped at its baked FP scale, or with the NPC display boost, pokes out of its own collider and clips walls
# with a blade the physics can't see.
func test_dropped_knife_model_fills_its_hand_tuned_collider() -> void:
	var w := _weapon("melee")
	var drop := _build_knife_drop()
	if w == null or drop == null:
		if drop != null:
			drop.free()
		return
	var visual := drop.get_node_or_null(^"Visual") as Node3D
	assert_true(visual != null, "the knife drop wraps its view model in a 'Visual' child")
	if visual != null:
		var state := _visual_bounds(visual, visual.transform, {})
		assert_true(state.has("aabb"), "the dropped knife has renderable bounds")
		if state.has("aabb"):
			var size := (state["aabb"] as AABB).size
			var box := w.dropped_collision_size
			assert_gt(size.z, maxf(size.x, size.y),
				"the posed knife must lie along local Z, the axis its throw noses along (posed bounds %s)" % size)
			# One-sided on purpose: poking OUT of the box is the bug, sitting a little inside it is not.
			assert_lte(size.z, box.z * (1.0 + COLLIDER_POKE_SLACK),
				"the dropped knife is %.3f m long but its dropped_collision_size is only %.3f m: the blade pokes out of the collider the physics sees" % [size.z, box.z])
			assert_gte(size.z, box.z * (1.0 - COLLIDER_FIT_TOLERANCE),
				"the dropped knife is %.3f m long inside a %.3f m collider: the model was re-posed far smaller than the box it was tuned against" % [size.z, box.z])
	drop.free()

# The override exists for ONE authoring situation, documented on WeaponData.npc_hold_override: a view_model whose ROOT
# bakes a first-person-only pose — an offset, a tilt or a non-uniform scale (the knife's 1.585 scale, Z-tilt and
# forward offset). npc.gd's default mount only corrects yaw, so a baked root floats off the hand without it. A CLEAN
# root — identity (the AK) or a centred uniform scale (the pistol's 0.001) — mounts right via weapon_mesh_rotation, and
# the override would DISCARD that root (the pistol's load-bearing 0.001 replaced by npc_hold_scale). So the flag must
# match the model, both ways. Measured off each weapon's real view-model root and walked from disk, so a gun re-imported
# with a baked root, or a NEW weapon authored from the wrong template, goes red without anyone updating a list.
func test_npc_hold_override_is_on_exactly_where_the_view_model_root_bakes_a_pose() -> void:
	var measured := 0
	for path in _list_tres():
		var w := load(path) as WeaponData
		if w == null:
			continue  # the field-type sweep above already fails a .tres that isn't a WeaponData
		var vm := w.held_view_model()
		if vm == null:
			continue  # nothing is mounted in an NPC's hand (bare fists' rig is first-person-only), so nothing to correct
		var root := vm.instantiate()
		var root3 := root as Node3D
		assert_true(root3 != null, "%s's view_model root must be a Node3D for an NPC hand to mount it" % path)
		if root3 == null:
			if root != null:
				root.free()
			continue
		var xf := root3.transform
		root.free()
		var root_scale := xf.basis.get_scale()
		var offset := not xf.origin.is_zero_approx()
		var tilted := not xf.basis.orthonormalized().is_equal_approx(Basis.IDENTITY)
		var squashed := maxf(absf(root_scale.x - root_scale.y), absf(root_scale.x - root_scale.z)) > absf(root_scale.x) * 0.001
		var baked := offset or tilted or squashed
		measured += 1
		assert_eq(w.npc_hold_override, baked,
			"%s's view_model root is %s (offset %s, tilted %s, non-uniform scale %s), so npc_hold_override must be %s: a baked root without it floats off an NPC's hand, and a clean root with it loses the scale it mounts at" % [path, xf, offset, tilted, squashed, baked])
	assert_gt(measured, 0, "precondition: at least one weapon on disk has a view model an NPC can hold")

# The held pose is game-wide too, for the same reason the streak is: a weapon in your HANDS that ignores where you
# are looking reads as a bug, not as flavour. DRIVEN, not read off the resource: every weapon on disk with a model to
# hold is dropped through the real WorldItem.build (which stamps held_faces_aim and thrown_face_rotation_degrees onto
# the Throwable), posed by the real Throwable.face_carrier for a look that is both pitched and yawed, and its business
# end is MEASURED on the posed model — a gun's barrel from its own Muzzle marker (NodeFinder, the lookup npc.gd fires
# from), the knife's blade from its documented -X blade axis. Whatever the authored numbers, that end must lie along the
# look. The control strips the mesh-front correction off the same drop, which must NOT land it there, so the check is
# known to measure the correction. Bare fists hold no model (their rig is first-person-only), so there is nothing to pose.
func test_every_weapon_you_can_hold_points_its_business_end_down_your_aim() -> void:
	# 25 degrees up and 70 degrees round from world forward, so neither a level-only pose nor an axis that merely
	# happens to line up with world -Z can pass.
	var carrier := Transform3D(Basis.from_euler(Vector3(deg_to_rad(25.0), deg_to_rad(70.0), 0.0)), Vector3(0.0, 1.0, 1.5))
	var look := (-carrier.basis.z).normalized()
	var measured := 0
	for path in _list_tres():
		var w := load(path) as WeaponData
		if w == null or w.held_view_model() == null:
			continue  # the field-type sweep fails a non-WeaponData; a first-person-only rig (bare fists) is never held as a model
		var item := Item.new()
		item.category = Item.Category.WEAPON
		item.weapon = w
		var drop := WorldItem.build(item, 1) as Throwable
		item = null
		if drop == null:
			fail_test("%s's view model must drop as a Throwable (WorldItem.build case 3)" % path)
			continue
		var visual := drop.get_node_or_null(^"Visual") as Node3D
		var muzzle: Node3D = NodeFinder.find_first_by_name(visual, "muzzle") if visual != null else null
		var is_knife: bool = path == WEAPONS_DIR + "melee.tres"
		if visual == null or (muzzle == null and not is_knife):
			# A ranged weapon needs the marker: without it an NPC's shots leave its hand, not the barrel. A melee model
			# other than the knife has no documented business-end axis to measure, so it is left out rather than guessed.
			assert_true(visual != null and w.is_melee,
				"%s drops with no Visual child, or is a ranged weapon whose dropped model has no Muzzle marker to find the barrel by" % path)
			drop.free()
			continue
		add_child_autofree(drop)  # face_carrier reads global transforms and calls look_at: an engine error off-tree
		drop.global_transform = Transform3D.IDENTITY
		drop.face_carrier(carrier)
		assert_gt(_business_end_along(visual, muzzle, look), 0.7,
			"%s held for a pitched, yawed look must point its business end down that look (within ~45 degrees): held_faces_aim, the reversed carry pose and its front correction together are what put it there" % path)
		drop.face_carrier_rotation_degrees = Vector3.ZERO
		drop.global_transform = Transform3D.IDENTITY
		drop.face_carrier(carrier)
		assert_lt(_business_end_along(visual, muzzle, look), 0.7,
			"control: the same %s drop with its mesh-front correction stripped must NOT point down the look, or the check above proves nothing" % path)
		measured += 1
	assert_gt(measured, 1, "precondition: the knife and at least one gun were posed and measured")


## How squarely the posed weapon's business end lies along `look` (1 = dead on): the direction from the model's origin to
## its Muzzle marker for a gun, or the knife's blade axis when there is no marker.
func _business_end_along(visual: Node3D, muzzle: Node3D, look: Vector3) -> float:
	var end: Vector3
	if muzzle != null:
		end = muzzle.global_position - visual.global_position
	else:
		end = visual.global_basis * KNIFE_BLADE_AXIS
	return end.normalized().dot(look)

# The knife's front correction, driven: WorldItem.build re-poses the dropped model with npc_hold_rotation (blade onto
# the drop's +Z, the TAIL of the aim) and stamps thrown_face_rotation_degrees onto the Throwable, whose
# travel_facing_basis noses the body along its flight. Whatever the authored numbers, the BLADE must lead on every
# throw, straight, pitched or sideways. The control re-stamps the guns' default correction on the same drop, which
# must NOT lead with the blade, so the check is known to be measuring the correction and not something always true.
func test_thrown_knife_leads_with_its_blade() -> void:
	var drop := _build_knife_drop()
	if drop == null:
		return
	var visual := drop.get_node_or_null(^"Visual") as Node3D
	assert_true(visual != null, "the knife drop wraps its view model in a 'Visual' child")
	if visual == null:
		drop.free()
		return
	var blade_in_body := (visual.transform.basis * KNIFE_BLADE_AXIS).normalized()
	for dir: Vector3 in [Vector3.FORWARD, Vector3(0.4, 0.5, -1.0).normalized(), Vector3.RIGHT, Vector3(-0.3, -0.6, 0.2).normalized()]:
		var blade := (drop.travel_facing_basis(dir) * blade_in_body).normalized()
		assert_gt(blade.dot(dir), 0.999,
			"a knife thrown along %s flies with its blade along %s: it must lead with the point, not the handle or the flat" % [dir, blade])
	var gun_default := WeaponData.new()
	drop.face_carrier_rotation_degrees = gun_default.thrown_face_rotation_degrees
	gun_default = null
	var uncorrected := (drop.travel_facing_basis(Vector3.FORWARD) * blade_in_body).normalized()
	assert_lt(uncorrected.dot(Vector3.FORWARD), 0.5,
		"control: with a gun's default front correction the same knife drop must NOT lead with its blade, or the check above proves nothing")
	drop.free()

# The in-flight streak is game-wide: EVERY weapon draws a white tracer through the arc of a real throw, not just
# the blade it shipped for. This pins the whole roster ON — the inverse of what it pinned before — because the
# failure mode is silent and per-resource: a weapon whose `thrown_trail` gets un-ticked (or a NEW weapon .tres
# authored from a stale template) just quietly throws bare, and nothing else in the suite would notice. The one
# WHITE assert covers the colour drifting per weapon, which would break the "every throw looks like a throw" read
# the effect exists for. `fists` is in the roster even though there is no fists Item to drop: it costs nothing,
# and it keeps this list identical to the scoped-throw roster below rather than subtly different.
func test_every_weapon_streaks_when_thrown() -> void:
	for wep in ["melee", "pistol", "shotgun", "smg", "sniper_wep", "rock_weapon", "spray_paint", "fists"]:
		var path := "res://resources/weapons/%s.tres" % wep
		var w := load(path) as WeaponData
		assert_not_null(w, "%s must load as a WeaponData" % path)
		assert_true(w.thrown_trail, "%s must draw a streak in flight — the tracer is on every thrown weapon" % wep)
		assert_eq(w.thrown_trail_color, Color(1.0, 1.0, 1.0, 1.0),
			"%s's streak is WHITE, like every other weapon's" % wep)

# ADS + attack HURLS a weapon that opts in (WeaponData.throw_on_scoped_attack) instead of swinging it. That is a
# trigger pull that permanently gives the weapon away, so the roster is pinned in BOTH directions: the knife must keep
# it (silently losing the gesture is invisible in play until you notice ADS does nothing) and nothing else may pick it
# up (a gun authored from a stale template would fling itself across the room the first time you aimed and fired).
# The no_ads pairing is pinned with it: a weapon that cannot aim down sights can never reach a scoped attack, so the
# two flags together would be a dead knob rather than a feature.
func test_only_the_knife_throws_on_a_scoped_attack() -> void:
	var knife := load("res://resources/weapons/melee.tres") as WeaponData
	assert_not_null(knife, "melee.tres must load as a WeaponData")
	assert_true(knife.throw_on_scoped_attack,
		"the knife is THE ADS-throw weapon — aiming and firing must hurl the blade, not swing it")
	assert_false(knife.no_ads,
		"and it must be able to aim down sights at all, or the gesture can never fire")
	for wep in ["pistol", "shotgun", "smg", "sniper_wep", "rock_weapon", "spray_paint", "fists"]:
		var w := load("res://resources/weapons/%s.tres" % wep) as WeaponData
		assert_not_null(w, "%s must load as a WeaponData" % wep)
		assert_false(w.throw_on_scoped_attack,
			"%s must NOT throw itself when you aim and fire — scoping a gun is how you shoot it" % wep)


# --- AGILITY floor ratchet (2026-09-02) --------------------------------------------------------------
# A wielder's AGILITY compresses a melee cadence and every reload, and Attack holds the scaled result to
# GameSettings.weapon_general.min_melee_attack_speed / min_reload_time. Attack._duration_floor makes those
# floors non-lengthening, so a weapon authored UNDER one keeps its authored speed and simply gains nothing
# from agility. That is safe, but it is also silent: the weapon becomes a dead end for the stat with no
# error anywhere. This walks every .tres on disk (not a hand-listed const set) so a NEWLY authored weapon
# is caught the day it lands rather than the day someone notices their agility build does nothing with it.

func test_no_shipped_weapon_is_authored_under_the_agility_floors() -> void:
	var wg: WeaponGeneralSettings = GameSettings.weapon_general
	var files := _list_tres()
	assert_gt(files.size(), 0, "there must be weapons to check")
	for path in files:
		var w := load(path) as WeaponData
		if w == null:
			continue
		if w.is_melee:
			assert_gte(w.attack_speed, wg.min_melee_attack_speed,
				"%s is melee and authors attack_speed %.3f, at or under min_melee_attack_speed %.3f — agility would buy this weapon NOTHING (Attack._duration_floor refuses to slow it, so it just stops responding to the stat). Raise the cadence or lower the floor deliberately." % [path, w.attack_speed, wg.min_melee_attack_speed])
		# The reload floor only binds a weapon that can actually run a reload. A free-refill / infinite-ammo
		# weapon (both melee weapons, the rock, the spray can) authors reload_time 0.0 and never reaches
		# _on_reload_reload at all — flooring THAT to 0.25 s is exactly the neutrality break _duration_floor
		# exists to prevent, so those are deliberately exempt rather than quietly rounded up.
		if not w.is_infinite_ammo and w.reload_time > 0.0:
			assert_gte(w.reload_time, wg.min_reload_time,
				"%s authors reload_time %.3f, under min_reload_time %.3f — the reload is already at the floor, so agility cannot shorten it." % [path, w.reload_time, wg.min_reload_time])
		w = null
