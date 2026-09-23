extends GutTest

## GUT suite for the Projectiles subsystem (scripts/projectiles/*.gd + the ProjectileSpawner that feeds it), driven
## through the REAL scenes: a test puts a real round, rock, paint blob or spawner in the tree, runs the production hook,
## and asserts what the player would get — where a hole / scorch / splat / burst lands, which way a round flies, what
## it damages, what a weapon's settings do to the round it fires.
##
## WHAT IT COVERS:
##   - Flight (Projectile.tscn / rock_projectile.tscn): a round nobody configured still leaves along its own heading;
##     a fired round never tumbles while a lobbed rock does; an unconfigured round damages what it lands on and a
##     visual_only round deals nothing and reports no impact blast.
##   - Impact decals (Bullet / RockProjectile._spawn_decal against a stepped slab): lifted off the surface along its
##     normal yet inside the decal's own projection depth, standing on a wall and on a floor alike, dropped back toward
##     the shooter when the probe finds nothing, never drawn on the view-model gun; a rocket scorch outsizes a hole.
##   - Impact particles (Bullet.particles): the burst lands on the shooter's side, further back off a body than a wall.
##   - PaintProjectile: a splat is an opaque, tinted decal riding the body it hit that replaces the paint it lands on
##     but not paint a splat-width away; paint_gravity arcs the blob and 0 flies it dead straight; the tuning
##     invariants the cull / overlap logic relies on.
##   - ProjectileSpawner: nothing fires without a weapon while the same spawner armed fires one round; the wielder is
##     the one body a round can't hit; launch_angle lobs a level shot; a multi-pellet gun splits its knockback; an AI
##     wielder's round flies slower than the player's from the same gun (plus the pure round_speed dial).
##
## HARNESS RULES:
##   - Every round gets SAFE_LIFE_TIME. Projectile._ready awaits a life timer on the round itself, and resuming that
##     await after the round was freed prints an engine error GUT 9.6 fails on (tests/test_rocket_world_impact.gd).
##   - A slab is stepped (wait_physics_frames) before anything raycasts it: an un-stepped body is invisible to a query.
##   - Whatever the code under test parents to the tree ROOT (decals, particles, sparks, spawned rounds, reparented
##     impact SFX) is recorded through SceneTree.node_added and freed in after_each, then the off-tree stubs.
##   - No Player / NPC _ready ever runs: wielders and victims are bare OFF-TREE Character stubs — the code under test
##     only asks what kind of body it has and which group it is in.
##
## COVERED ELSEWHERE:
##   - Map-brush collision masks and the rocket's real damaging Explosion: tests/test_rocket_world_impact.gd.
##   - _orient_decal_to_normal / orient_decal_to_normal: they only assign a basis to a real
##     Decal node. The basis itself is the pure static Projectile.decal_basis_for_normal, which
##     test_smoke.gd calls DIRECTLY (right-handed, orthonormal, Y = normal on five surfaces).
##   - The spent casing's outline stamp (bullet_casing.gd): tests/test_ink_outline.gd.
##   - ProjectileSpawner.PITCH_AXIS_MIN_LENGTH_SQ has NO driven test on purpose: the only aim it changes is a shot fired
##     exactly vertical, and a vertical round already errors in Projectile._ready's look_at (direction colinear with UP).


## Off-tree victim / wielder stand-in: Character has no abstract funcs, so a bare subclass instantiates. Never added to
## the tree (its _ready builds meshes and overlay chains); the projectile code only reads `is Character` and groups.
class _ConcreteChar extends Character:
	pass


## A brush that takes damage and records it — the smallest body the projectile's damage branch dispatches to
## (DamageApplier.apply's 3-arg non-Character form).
class _DamageableSlab extends StaticBody3D:
	var taken: float = 0.0

	func take_damage(amount: float, _was_crit: bool = false, _attacker: Node = null) -> void:
		taken += amount


const BULLET_SCENE := "res://scenes/projectiles/Projectile.tscn"
const ROCK_SCENE := "res://scenes/projectiles/rock_projectile.tscn"
const PAINT_PROJECTILE_SCRIPT := "res://scripts/projectiles/paint_projectile.gd"

## Far longer than any run: see HARNESS RULES.
const SAFE_LIFE_TIME: float = 600.0
## Far from the origin, so nothing another suite leaves near it can intercept a probe or a flight. Each test works in
## its own cell off this point.
const ARENA := Vector3(60.0, 80.0, 60.0)
## A round's travel speed at the moment it lands, for the tests that hand the impact hooks their velocity directly.
const IMPACT_SPEED: float = 20.0
## Where a stopped round's centre sits off the surface it hit: a collider radius (0.05 in both scenes) and a hair.
## Well inside both variants' probe reach, which is the point — this is a real impact, not a near miss.
const PARKED_GAP: float = 0.1
## How far above a slab a dropped round starts.
const DROP_HEIGHT: float = 5.0
## Every render layer the editor exposes (the Decal / Camera3D cull_mask default).
const ALL_EDITOR_LAYERS: int = (1 << 20) - 1

## Root-parented nodes the code under test created during this test, in arrival order.
var _root_spawns: Array[Node] = []
## Off-tree stubs to free AFTER the root spawns (a spawned round holds its wielder as shooter + collision exception).
var _off_tree: Array[Object] = []


func before_each() -> void:
	_root_spawns = []
	_off_tree = []
	get_tree().node_added.connect(_on_node_added)


func after_each() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	for n in _root_spawns:
		if is_instance_valid(n):
			n.free()
	_root_spawns = []
	for o in _off_tree:
		if is_instance_valid(o):
			o.free()
	_off_tree = []


func _on_node_added(node: Node) -> void:
	if node.get_parent() != get_tree().root:
		return
	if node is Decal or node is GPUParticles3D or node is Projectile or node is Explosion or node is AudioStreamPlayer3D:
		_root_spawns.append(node)


# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------

## A func_godot-style brush (solid, layer 1, scanning nothing): a 4 m cube whose struck face passes through
## `face_point` and faces `face_normal` (an axis direction). `body` swaps in a scripted StaticBody3D.
func _slab(face_point: Vector3, face_normal: Vector3, body: StaticBody3D = null) -> StaticBody3D:
	var s: StaticBody3D = body if body != null else StaticBody3D.new()
	s.collision_layer = 1
	s.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 4.0, 4.0)
	shape.shape = box
	s.add_child(shape)
	add_child_autofree(s)
	s.global_position = face_point - face_normal.normalized() * 2.0
	return s


## A real round of `scene_path` that has just stopped at `at` — the state _on_body_entered hands its hooks. Speed and
## gravity are zeroed only so it stays exactly where the test put it. Both scenes author collision_layer = 0, which is
## what keeps a round out of its own surface probe.
func _parked_round(scene_path: String, at: Vector3) -> Projectile:
	var r: Projectile = (load(scene_path) as PackedScene).instantiate()
	r.life_time = SAFE_LIFE_TIME
	r.speed = 0.0
	r.gravity_scale = 0.0
	add_child_autofree(r)
	r.global_position = at
	return r


func _decals_since(mark: int) -> Array[Decal]:
	var out: Array[Decal] = []
	for i in range(mark, _root_spawns.size()):
		var n := _root_spawns[i]
		if is_instance_valid(n) and n is Decal:
			out.append(n as Decal)
	return out


func _particles_since(mark: int) -> Array[GPUParticles3D]:
	var out: Array[GPUParticles3D] = []
	for i in range(mark, _root_spawns.size()):
		var n := _root_spawns[i]
		if is_instance_valid(n) and n is GPUParticles3D:
			out.append(n as GPUParticles3D)
	return out


## Park a round of `scene_path` just off a stepped wall and run its real _spawn_decal for a shot travelling into the
## face. Returns the ONE decal it placed, or null (after failing the count).
func _impact_decal(scene_path: String, face_point: Vector3, normal: Vector3) -> Decal:
	var r := _parked_round(scene_path, face_point + normal * PARKED_GAP)
	var mark := _root_spawns.size()
	r._spawn_decal(-normal * IMPACT_SPEED)
	var decals := _decals_since(mark)
	assert_eq(decals.size(), 1,
		"%s must place exactly one decal for one impact on a surface inside its probe reach" % scene_path.get_file())
	return decals[0] if decals.size() == 1 else null


## The decal-on-a-surface contract every impact decal shares.
func _assert_stands_on_surface(decal: Decal, face_point: Vector3, normal: Vector3, what: String) -> void:
	var lift := (decal.global_position - face_point).dot(normal)
	assert_gt(lift, 0.0,
		"%s must sit OFF the surface on the side its normal faces — at or behind the surface it z-fights or is buried in the wall" % what)
	assert_lt(lift, decal.size.y * 0.5,
		"%s must stay within half its own projection depth (size.y) of the surface, or the box it projects along -Y never reaches the wall and nothing draws" % what)
	var b := decal.global_transform.basis
	assert_gt(b.y.normalized().dot(normal), 0.999,
		"%s must stand with its local Y along the surface normal — a Decal projects along -Y, so any other axis smears it across the surface" % what)
	assert_almost_eq(b.determinant(), 1.0, 0.001,
		"%s must keep an orthonormal RIGHT-HANDED basis (det 1): a degenerate cross product collapses it to 0, a flipped one mirrors the stamp" % what)


## Fly a real bullet down into the slab whose top face passes through `face_point`. Returns
## {consumed: the round was freed by an impact within the budget, last_pos: what queued_for_deletion reported or null}.
func _drop_round_onto(face_point: Vector3, visual_only: bool) -> Dictionary:
	var r: Projectile = (load(BULLET_SCENE) as PackedScene).instantiate()
	r.life_time = SAFE_LIFE_TIME
	# Nudged off pure DOWN: Projectile._ready's look_at(pos + direction, UP) errors on a vertical heading.
	r.direction = Vector3(0.08, -1.0, 0.0).normalized()
	r.speed = IMPACT_SPEED
	r.visual_only = visual_only
	add_child(r)
	r.global_position = face_point + Vector3.UP * DROP_HEIGHT
	var report := {"consumed": false, "last_pos": null}
	r.queued_for_deletion.connect(func(p: Vector3) -> void: report["last_pos"] = p)
	for _i in 90:
		await wait_physics_frames(1)
		if not is_instance_valid(r):
			report["consumed"] = true
			break
	if is_instance_valid(r):
		r.free()
	return report


func _wielder(is_player: bool) -> _ConcreteChar:
	var c := _ConcreteChar.new()
	if is_player:
		c.add_to_group(Groups.PLAYER)
	_off_tree.append(c)
	return c


## A projectile weapon that fires the real bullet scene. No gravity so a launch reads straight off the velocity.
func _armed_weapon() -> WeaponData:
	var w := WeaponData.new()
	w.projectile_scene = load(BULLET_SCENE) as PackedScene
	w.projectile_life_time = SAFE_LIFE_TIME
	w.bullet_gravity_scale = 0.0
	return w


## A spawner wired the way WeaponSystem.setup wires it: an Inventory to watch and the wielder that fires.
func _spawner_for(wielder: Character) -> ProjectileSpawner:
	var inv := Inventory.new()
	add_child_autofree(inv)
	var s := ProjectileSpawner.new()
	s.inventory = inv
	s.player = wielder
	add_child_autofree(s)
	return s


## Pull the trigger once from high above the arena; return the rounds that one call put in the world.
func _fire(s: ProjectileSpawner, aim: Vector3) -> Array[Projectile]:
	var mark := _root_spawns.size()
	s.spawn_projectile(ARENA + Vector3(0.0, 60.0, 0.0), aim, false)
	var rounds: Array[Projectile] = []
	for i in range(mark, _root_spawns.size()):
		var n := _root_spawns[i]
		if is_instance_valid(n) and n is Projectile:
			rounds.append(n as Projectile)
	return rounds


## A parked paint blob with `tint` loaded — the tests below hand _splash its hit directly, so its own per-frame
## raycast is switched off.
func _paint_blob(tint: Color) -> PaintProjectile:
	var blob := PaintProjectile.new()
	blob.paint_color = tint
	add_child_autofree(blob)
	blob.set_physics_process(false)
	blob.global_position = ARENA + Vector3(0.0, 60.0, -30.0)
	return blob


func _paint_on(body: Node) -> Array[Decal]:
	var out: Array[Decal] = []
	for c in body.get_children():
		if c is Decal:
			out.append(c as Decal)
	return out


# ---------------------------------------------------------------------------
# Flight
# ---------------------------------------------------------------------------

func test_an_unconfigured_round_leaves_along_its_own_heading() -> void:
	# Only the life timer is set: direction and speed are the round's own defaults — what a round spawned by anything
	# other than ProjectileSpawner flies with. Gravity stays as authored, so only the horizontal motion is judged.
	var r: Projectile = (load(BULLET_SCENE) as PackedScene).instantiate()
	r.life_time = SAFE_LIFE_TIME
	add_child_autofree(r)
	var start := ARENA + Vector3(0.0, 40.0, 0.0)
	r.global_position = start
	var heading := r.direction
	await wait_physics_frames(6)
	var travel := r.global_position - start
	travel.y = 0.0
	assert_gt(travel.dot(heading), 0.0,
		"A round nobody configured must still leave along its own default heading — a zero default speed or a Bullet that shadows it would park the round at the muzzle")
	assert_lt((travel - heading * travel.dot(heading)).length(), 0.01,
		"...and fly straight along that heading, not drift sideways off it")


func test_a_fired_round_never_tumbles_but_a_lobbed_rock_does() -> void:
	# Contact torque is what spins a stopped round; set the spin directly. The rock is the CONTROL: it has no rotation
	# lock (it SHOULD tumble), so it proves the same spin visibly turns an unlocked projectile.
	var aim := Vector3(1.0, 0.0, -1.0).normalized()
	var spin := Vector3(0.0, 8.0, 0.0)
	var rounds: Array[Projectile] = []
	for scene_path in [BULLET_SCENE, ROCK_SCENE]:
		var r: Projectile = (load(scene_path) as PackedScene).instantiate()
		r.life_time = SAFE_LIFE_TIME
		r.speed = 0.0
		r.gravity_scale = 0.0
		r.direction = aim
		add_child_autofree(r)
		r.global_position = ARENA + Vector3(6.0 * rounds.size(), 40.0, 10.0)
		r.angular_velocity = spin
		rounds.append(r)
	await wait_physics_frames(10)
	assert_gt((-rounds[0].global_transform.basis.z).dot(aim), 0.999,
		"A fired bullet must keep pointing along its shot no matter what spins it — its 2.4 m tracer needle around a 5 cm collider sweeps a ~3 m disc if it turns (Bullet locks rotation after look_at)")
	assert_lt((-rounds[1].global_transform.basis.z).dot(aim), 0.99,
		"CONTROL: the same spin must visibly turn a lobbed rock (no rotation lock), or this harness can't see a tumble at all")


func test_an_unconfigured_round_damages_what_it_lands_on_and_a_visual_only_round_does_not() -> void:
	var real_face := ARENA + Vector3(-20.0, 0.0, 0.0)
	var target := _slab(real_face, Vector3.UP, _DamageableSlab.new()) as _DamageableSlab
	var real: Dictionary = await _drop_round_onto(real_face, false)
	assert_true(real["consumed"], "harness: the dropped round must reach and be consumed by the slab")
	assert_gt(target.taken, 0.0,
		"A round fired without a spawner must still deal damage on impact — its own damage default must be positive and visual_only must default off")
	assert_true(real["last_pos"] != null,
		"CONTROL: a damaging round reports its impact through queued_for_deletion (explosion.gd spawns the hit spark from it)")

	var ghost_face := ARENA + Vector3(20.0, 0.0, 0.0)
	var ghost_target := _slab(ghost_face, Vector3.UP, _DamageableSlab.new()) as _DamageableSlab
	var ghost: Dictionary = await _drop_round_onto(ghost_face, true)
	assert_true(ghost["consumed"],
		"CONTROL: a visual_only round still lands on (and is consumed by) the same kind of target")
	assert_eq(ghost_target.taken, 0.0,
		"A visual_only round (the cosmetic copy of a shot another path already resolved) must deal NO damage, or every such shot hits twice")
	assert_true(ghost["last_pos"] == null,
		"...and must not report an impact blast either (queued_for_deletion is the damaging-impact signal)")


# ---------------------------------------------------------------------------
# Impact decals
# ---------------------------------------------------------------------------

func test_a_bullet_hole_sits_just_off_a_wall_and_projects_into_it() -> void:
	var face := ARENA + Vector3(0.0, 0.0, 20.0)
	var normal := Vector3.BACK  # the wall faces +Z; the shot travels -Z into it
	_slab(face, normal)
	await wait_physics_frames(2)
	var hole := _impact_decal(BULLET_SCENE, face, normal)
	if hole == null:
		return
	_assert_stands_on_surface(hole, face, normal, "A bullet hole on a wall")
	assert_true(hole.size.y < hole.size.x and hole.size.y < hole.size.z,
		"A bullet hole must be a thin disc (projection depth under its footprint), not a cube that paints everything around the impact")


func test_a_bullet_hole_in_a_floor_lies_flat_on_the_floor() -> void:
	# A floor normal is parallel to UP — the one surface where crossing with UP degenerates, so the decal basis has to
	# pick its other reference axis (NORMAL_PARALLEL_THRESHOLD). The shot travels straight down into it.
	var face := ARENA + Vector3(20.0, 0.0, 20.0)
	_slab(face, Vector3.UP)
	await wait_physics_frames(2)
	var r := _parked_round(BULLET_SCENE, face + Vector3.UP * PARKED_GAP)
	var mark := _root_spawns.size()
	r._spawn_decal(Vector3.DOWN * IMPACT_SPEED)
	var decals := _decals_since(mark)
	assert_eq(decals.size(), 1, "A shot into the floor must leave exactly one bullet hole")
	if decals.size() != 1:
		return
	_assert_stands_on_surface(decals[0], face, Vector3.UP, "A bullet hole in the floor")


func test_a_bullet_that_finds_no_surface_leaves_its_hole_just_behind_the_impact_point() -> void:
	# Nothing within probe reach (a thin prop's edge, a body that moved): the hit still marks where the round stopped.
	var r := _parked_round(BULLET_SCENE, ARENA + Vector3(-20.0, 40.0, 20.0))
	var travel := Vector3(0.3, -0.2, -1.0).normalized()
	var mark := _root_spawns.size()
	r._spawn_decal(travel * IMPACT_SPEED)
	var decals := _decals_since(mark)
	assert_eq(decals.size(), 1, "A hit whose probe finds no surface must still leave a hole")
	if decals.size() != 1:
		return
	var offset := decals[0].global_position - r.global_position
	assert_lt(offset.dot(travel), 0.0,
		"With no surface to stand on, the hole must back off toward the SHOOTER (against the travel), not on past the impact into whatever it hit")
	assert_lt(offset.length(), decals[0].size.x,
		"...and stay within one hole-width of where the round stopped")


func test_impact_decals_draw_on_every_layer_except_the_view_model_gun() -> void:
	var face := ARENA + Vector3(-20.0, 0.0, -20.0)
	var normal := Vector3.BACK
	_slab(face, normal)
	await wait_physics_frames(2)
	var hole := _impact_decal(BULLET_SCENE, face + Vector3.LEFT, normal)
	var scorch := _impact_decal(ROCK_SCENE, face + Vector3.RIGHT, normal)
	if hole == null or scorch == null:
		return
	for pair in [["bullet hole", hole], ["rocket scorch", scorch]]:
		var mask: int = (pair[1] as Decal).cull_mask
		assert_eq(mask & ViewModelCamera.VIEW_MODEL_LAYER, 0,
			"A %s must NOT project onto the view-model layer — a shot at a wall right in front of you would stamp the hole onto your own gun" % pair[0])
		assert_eq((mask | ViewModelCamera.VIEW_MODEL_LAYER) & ALL_EDITOR_LAYERS, ALL_EDITOR_LAYERS,
			"A %s must still project onto EVERY other render layer (world brushes, props, missed layer-2-only walls)" % pair[0])


func test_a_rocket_scorch_outsizes_a_bullet_hole_and_still_stands_on_the_wall() -> void:
	var face := ARENA + Vector3(20.0, 0.0, 40.0)
	var normal := Vector3.BACK
	_slab(face, normal)
	await wait_physics_frames(2)
	var hole := _impact_decal(BULLET_SCENE, face + Vector3.LEFT, normal)
	var scorch := _impact_decal(ROCK_SCENE, face + Vector3.RIGHT, normal)
	if hole == null or scorch == null:
		return
	assert_true(scorch.size.x > hole.size.x and scorch.size.z > hole.size.z,
		"A rocket's scorch mark must cover more wall than a bullet hole — a rocket that leaves a pistol-sized mark reads as a dud")
	_assert_stands_on_surface(scorch, face + Vector3.RIGHT, normal, "A rocket scorch on a wall")


func test_impact_particles_burst_on_the_shooters_side_and_further_back_off_a_body_than_a_wall() -> void:
	var r := _parked_round(BULLET_SCENE, ARENA + Vector3(0.0, 40.0, -40.0))
	var travel := Vector3.FORWARD
	# particles() only asks what KIND of body it hit, so both stay off-tree.
	var wall := StaticBody3D.new()
	_off_tree.append(wall)
	var victim := _wielder(false)

	var mark := _root_spawns.size()
	r.particles(wall, travel * IMPACT_SPEED)
	var dust := _particles_since(mark)
	mark = _root_spawns.size()
	r.particles(victim, travel * IMPACT_SPEED)
	var blood := _particles_since(mark)
	assert_eq(dust.size(), 1, "A wall hit must burst exactly one particle effect")
	assert_eq(blood.size(), 1, "A body hit must burst exactly one particle effect")
	if dust.size() != 1 or blood.size() != 1:
		return
	var dust_back := -(dust[0].global_position - r.global_position).dot(travel)
	var blood_back := -(blood[0].global_position - r.global_position).dot(travel)
	assert_gt(dust_back, 0.0,
		"Impact dust must burst on the shooter's side of the hit (backed off against the travel), not inside the wall")
	assert_gt(blood_back, dust_back,
		"A body hit must pull its burst FURTHER back than a wall hit, so the blood reads in front of the body instead of inside its capsule")


# ---------------------------------------------------------------------------
# PaintProjectile
# ---------------------------------------------------------------------------

func test_a_paint_splat_is_an_opaque_tinted_decal_riding_the_body_it_hit() -> void:
	var face := ARENA + Vector3(-40.0, 0.0, 0.0)
	var normal := Vector3.BACK
	var wall := _slab(face, normal)
	var tint := Color(0.2, 0.6, 0.9)
	var blob := _paint_blob(tint)
	blob._splash(face, normal, wall)
	var splats := _paint_on(wall)
	assert_eq(splats.size(), 1,
		"A blob landing on a body must leave one splat parented to THAT body, so the paint rides along when it moves")
	if splats.size() != 1:
		return
	var splat := splats[0]
	_assert_stands_on_surface(splat, face, normal, "A paint splat")
	assert_eq(splat.cull_mask & ViewModelCamera.VIEW_MODEL_LAYER, 0,
		"Paint must never project onto the view-model gun, same as a bullet hole")
	assert_almost_eq(splat.modulate.a, 1.0, 0.001,
		"Fresh paint must be fully opaque so it covers what is underneath, not blend with it")
	assert_true(Color(splat.modulate, 1.0).is_equal_approx(Color(tint, 1.0)),
		"The splat must wear the blob's wheel-selected colour")


func test_a_fresh_splat_replaces_the_paint_it_lands_on_but_not_paint_a_splat_width_away() -> void:
	var face := ARENA + Vector3(-40.0, 0.0, 20.0)
	var normal := Vector3.BACK
	var wall := _slab(face, normal)
	var blob := _paint_blob(Color.GREEN)
	blob._splash(face, normal, wall)
	var first := _paint_on(wall)[0]
	blob._splash(face + Vector3.RIGHT * first.size.x, normal, wall)
	assert_false(first.is_queued_for_deletion(),
		"CONTROL: paint a whole splat-width along the wall is a separate tag and must survive")
	blob._splash(face, normal, wall)
	assert_true(first.is_queued_for_deletion(),
		"A fresh splat landing on existing paint must destroy and replace it — newest paint wins, no stacked decals")


func test_a_paint_blob_arcs_down_under_paint_gravity_and_flies_dead_straight_without_it() -> void:
	var launch := Vector3(0.0, 0.0, -10.0)
	var lobbed := PaintProjectile.new()
	lobbed.velocity = launch
	add_child_autofree(lobbed)
	var lobbed_start := ARENA + Vector3(-40.0, 60.0, 40.0)
	lobbed.global_position = lobbed_start
	var straight := PaintProjectile.new()
	straight.velocity = launch
	straight.paint_gravity = 0.0
	add_child_autofree(straight)
	var straight_start := ARENA + Vector3(-34.0, 60.0, 40.0)
	straight.global_position = straight_start
	await wait_physics_frames(10)
	assert_lt(lobbed.global_position.y, lobbed_start.y - 0.001,
		"A paint blob must arc DOWN under its default paint_gravity — the lobbed spray-can toss")
	assert_lt(lobbed.global_position.z, lobbed_start.z, "...while still carrying forward along its launch")
	assert_almost_eq(straight.global_position.y, straight_start.y, 0.0001,
		"paint_gravity 0 must fly the blob dead straight (the documented meaning of 0)")
	assert_lt(straight.global_position.z, straight_start.z, "CONTROL: the straight blob did fly")


func test_paint_projectile_const_invariants() -> void:
	# Cull mask stays a const (engineering); the rest are now @export feel knobs read off an instance.
	assert_eq(PaintProjectile.PAINT_CULL_MASK, Projectile.DECAL_CULL_MASK,
		"Paint and bullet decals must share the same gun-layer exclusion mask — this is the cross-subsystem cull-mask contract")
	var p = load(PAINT_PROJECTILE_SCRIPT).new()  # no add_child: skip the mesh-building _ready
	assert_gt(p.max_paint_decals, 0,
		"The global paint-decal cap must be positive or the cull logic would free every decal immediately")
	assert_gt(p.lifetime, 0.0,
		"Blob lifetime must be positive so a blob that misses everything still eventually self-frees")
	assert_true(p.overlap_factor > 0.0 and p.overlap_factor < 1.0,
		"overlap_factor must be a sane fraction of decal width (0..1) so the overlap-replace radius is smaller than the splat itself")
	p.free()


# ---------------------------------------------------------------------------
# ProjectileSpawner
# ---------------------------------------------------------------------------

func test_a_spawner_with_no_weapon_fires_nothing_and_the_same_spawner_armed_fires_one_round() -> void:
	var s := _spawner_for(_wielder(true))
	assert_eq(_fire(s, Vector3.FORWARD).size(), 0,
		"Pulling the trigger with no weapon equipped must put NO round in the world (and not crash)")
	s.inventory.equip(_armed_weapon())
	assert_eq(_fire(s, Vector3.FORWARD).size(), 1,
		"CONTROL: once the Inventory equips a projectile weapon, the SAME spawner must fire exactly one round per call")


func test_a_spawned_round_can_never_hit_its_own_wielder() -> void:
	var wielder := _wielder(false)
	var bystander := _wielder(false)
	var s := _spawner_for(wielder)
	s.inventory.equip(_armed_weapon())
	var rounds := _fire(s, Vector3.FORWARD)
	assert_eq(rounds.size(), 1, "harness: the armed spawner fires one round")
	if rounds.size() != 1:
		return
	var exceptions := rounds[0].get_collision_exceptions()
	assert_true(exceptions.has(wielder),
		"A round must never collide with the body that fired it — it spawns inside the wielder's own capsule")
	assert_false(exceptions.has(bystander),
		"CONTROL: only the wielder is excepted; the round must still hit everyone else")


func test_launch_angle_lobs_a_level_shot_upward() -> void:
	var s := _spawner_for(_wielder(true))
	var w := _armed_weapon()
	s.inventory.equip(w)
	var level := _fire(s, Vector3.FORWARD)
	w.launch_angle = 15.0
	var lobbed := _fire(s, Vector3.FORWARD)
	assert_eq(level.size() + lobbed.size(), 2, "harness: each trigger pull fires one round")
	if level.size() != 1 or lobbed.size() != 1:
		return
	assert_almost_eq(level[0].linear_velocity.y, 0.0, 0.001,
		"CONTROL: with launch_angle 0 a level shot leaves level")
	assert_gt(lobbed[0].linear_velocity.y, 0.0,
		"A positive launch_angle must pitch a level shot UP (the grenade-style lob), not down into the floor")
	assert_lt(lobbed[0].linear_velocity.z, 0.0, "...while still flying toward the aim")


func test_a_multi_pellet_gun_splits_its_knockback_so_the_pellets_add_back_up_to_the_weapons_push() -> void:
	var s := _spawner_for(_wielder(true))
	var w := _armed_weapon()
	w.enemy_knockback = 8.0
	w.enemy_lift = 2.0
	w.pellet_count = 1
	s.inventory.equip(w)
	var solo := _fire(s, Vector3.FORWARD)
	w.pellet_count = 4
	var pellet := _fire(s, Vector3.FORWARD)
	assert_eq(solo.size() + pellet.size(), 2, "harness: each trigger pull fires one round")
	if solo.size() != 1 or pellet.size() != 1:
		return
	assert_almost_eq(solo[0].enemy_knockback, w.enemy_knockback, 0.001,
		"CONTROL: a single-pellet gun's one round carries the weapon's whole knockback")
	assert_almost_eq(pellet[0].enemy_knockback * w.pellet_count, w.enemy_knockback, 0.001,
		"A multi-pellet gun's rounds must SHARE its knockback, so a full volley shoves exactly as hard as the weapon says (a hitscan shotgun splits it the same way)")
	assert_almost_eq(pellet[0].enemy_lift * w.pellet_count, w.enemy_lift, 0.001,
		"...and share its lift the same way")


func test_an_ai_wielders_round_flies_slower_than_the_players_from_the_same_gun() -> void:
	var w := _armed_weapon()
	w.npc_projectile_speed_mult = 0.5
	var hero := _spawner_for(_wielder(true))
	hero.inventory.equip(w)
	var npc := _spawner_for(_wielder(false))
	npc.inventory.equip(w)
	var hero_rounds := _fire(hero, Vector3.FORWARD)
	var npc_rounds := _fire(npc, Vector3.FORWARD)
	assert_eq(hero_rounds.size() + npc_rounds.size(), 2, "harness: each trigger pull fires one round")
	if hero_rounds.size() != 1 or npc_rounds.size() != 1:
		return
	var hero_speed := hero_rounds[0].linear_velocity.length()
	assert_almost_eq(hero_speed, w.projectile_speed, 0.01,
		"The player's round must fly at the weapon's authored projectile_speed — the AI dodge dial never touches the player's feel")
	assert_lt(npc_rounds[0].linear_velocity.length(), hero_speed,
		"An AI wielder's round from the same gun must fly slower, so incoming enemy fire is dodgeable")


## The AI dodge-window dial (2026-08-25): round_speed is the pure static spawn_projectile stamps onto every
## round — the authored projectile_speed for the player (and a NULL/unwired wielder), times the weapon's
## npc_projectile_speed_mult for an AI wielder. Enemies never hitscan, so this is what makes their fire
## visibly slower than the player's identical gun. Pinned against the authored .tres so a rebalance shows here.
func test_projectile_spawner_round_speed_slows_ai_rounds_only() -> void:
	assert_eq(ProjectileSpawner.round_speed(null, true), 0.0,
		"null weapon -> 0 speed (the spawn path never reaches round_speed without a weapon; the 0 is a safe inert)")
	var w := WeaponData.new()
	w.projectile_speed = 60.0
	assert_eq(ProjectileSpawner.round_speed(w, true), 60.0,
		"a PLAYER wielder always gets the authored projectile_speed — the mult must never touch the player's feel")
	assert_eq(ProjectileSpawner.round_speed(w, false), 60.0,
		"default npc_projectile_speed_mult 1.0 -> AI rounds at authored speed (no behavior change until a .tres opts in)")
	w.npc_projectile_speed_mult = 0.5
	assert_eq(ProjectileSpawner.round_speed(w, false), 30.0,
		"an AI wielder's rounds fly projectile_speed x npc_projectile_speed_mult — the per-weapon dodge window")
	assert_eq(ProjectileSpawner.round_speed(w, true), 60.0,
		"the same weapon in the player's hands still fires at full authored speed")
	w = null
	var pistol := load("res://resources/weapons/pistol.tres") as WeaponData
	assert_eq(ProjectileSpawner.round_speed(pistol, false), pistol.projectile_speed * 0.5,
		"pistol.tres authors npc_projectile_speed_mult 0.5 — enemy pea-shooter rounds fly at half the player's, the shipped dodge window")
	pistol = null
