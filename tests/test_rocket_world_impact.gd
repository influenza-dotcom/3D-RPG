extends GutTest

## The rocket must DETONATE ON THE WORLD, not only on people.
##
## THE BUG THIS PINS (reported: "rocket launcher only explodes when it hits NPCs"):
## the map's brush geometry — func_godot `worldspawn` / `func_geo` / `func_detail`, see
## addons/func_godot/fgd/*.tres — is authored `collision_layer = 1, collision_mask = 0`.
## It SCANS NOTHING and relies entirely on whatever hits it to scan LAYER 1.
## rock_projectile.tscn shipped `collision_mask = 2` (characters only) with no
## `collision_layer` override, so BOTH halves of the collision test came up empty:
##     rocket.mask(2) & world.layer(1) == 0     and     world.mask(0) & rocket.layer(1) == 0
## The rocket flew straight THROUGH every wall, floor and ceiling and then died on its
## `life_time` timeout — a path that deliberately does NOT emit `queued_for_deletion` — so
## explosion.gd's bridge never fired and no blast ever spawned. Only a direct hit on a
## Player/Enemy (layer 2) detonated it. Bullets never had this: Projectile.tscn is
## `collision_layer = 0, collision_mask = 3`.
##
## WHY A PHYSICS TEST: a collision-mask typo is invisible to every pure-data assertion in
## test_projectiles.gd. This flies a REAL rock projectile into a worldspawn-shaped
## StaticBody3D and asserts the whole user-visible chain — impact -> queued_for_deletion ->
## a real Explosion in the tree. Scoped run:
##   & "C:\Users\dalla\bin\godot.cmd" --headless --path . -s addons/gut/gut_cmdln.gd \
##       -gdir=res://tests -gprefix=test_rocket_world_impact -gexit

const ROCK_SCENE := "res://scenes/projectiles/rock_projectile.tscn"
const BULLET_SCENE := "res://scenes/projectiles/Projectile.tscn"

## Long enough that the projectile's `_ready` life-timer never fires during the run: it awaits
## on the projectile itself, and resuming that await after the impact freed the node would
## print an engine error (which GUT 9.6 turns into a failure).
const SAFE_LIFE_TIME: float = 600.0

## A stand-in for one func_godot brush: solid, on layer 1, scanning NOTHING (mask 0).
## These three numbers ARE the contract under test — keep them matching worldspawn.tres.
func _worldspawn_slab() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 1.0, 8.0)
	shape.shape = box
	body.add_child(shape)
	return body


## Fly `projectile_scene` straight down into a worldspawn slab. Returns true if the
## projectile reported an impact (emitted queued_for_deletion) within `frames`.
func _drops_onto_world(projectile_scene: String, frames: int = 90) -> bool:
	var slab := _worldspawn_slab()
	add_child_autofree(slab)
	slab.global_position = Vector3.ZERO

	var round_ = load(projectile_scene).instantiate()  # untyped: instantiate() returns Variant, so := cannot infer
	# Nudged off pure DOWN on purpose: Projectile._ready does look_at(pos + direction, UP),
	# and a perfectly vertical direction is colinear with UP -> an engine warning GUT counts
	# as a failure. A real shot is never exactly vertical either.
	round_.direction = Vector3(0.08, -1.0, 0.0).normalized()
	round_.speed = 20.0
	round_.life_time = SAFE_LIFE_TIME
	add_child(round_)
	round_.global_position = Vector3(0.0, 5.0, 0.0)

	var impacts: Array[bool] = [false]
	round_.queued_for_deletion.connect(func(_last_pos: Vector3) -> void: impacts[0] = true)

	for _i in frames:
		await wait_physics_frames(1)
		if impacts[0]:
			break

	if is_instance_valid(round_):
		round_.queue_free()
	return impacts[0]


func test_rocket_detonates_on_worldspawn_geometry() -> void:
	var hit: bool = await _drops_onto_world(ROCK_SCENE)
	assert_true(hit,
		"A rocket fired into map brush geometry must impact and emit queued_for_deletion. It did not — rock_projectile.tscn's collision_mask does not scan LAYER 1, and func_godot worldspawn/func_geo/func_detail are layer 1 with mask 0, so neither side detects the other and the rocket flies through the level (only NPCs on layer 2 ever detonate it)")


func test_bullet_also_impacts_worldspawn_geometry() -> void:
	# The control: the ordinary bullet (collision_layer = 0, collision_mask = 3) has always
	# hit walls. If THIS ever fails the slab/harness is wrong, not the rocket's mask.
	var hit: bool = await _drops_onto_world(BULLET_SCENE)
	assert_true(hit,
		"The plain bullet must impact the same worldspawn slab — it scans layer 1 via collision_mask = 3. A failure here means this test's slab no longer matches func_godot's authored layer/mask, not that the bullet regressed")


func test_rocket_impact_spawns_a_real_explosion() -> void:
	# The end-to-end payoff: impact -> the scene-wired queued_for_deletion -> explosion.gd's
	# bridge -> a real Explosion in the tree. This is what the player actually sees.
	# Watched through SceneTree.node_added rather than by polling root's children: the blast
	# self-frees on its own 0.2s one-shot Timer, so a poll can miss the window entirely.
	var blast: Array[Node] = [null]
	var watch := func(node: Node) -> void:
		if node is Explosion and blast[0] == null:
			blast[0] = node
	get_tree().node_added.connect(watch)

	var slab := _worldspawn_slab()
	add_child_autofree(slab)
	slab.global_position = Vector3.ZERO

	var rocket = load(ROCK_SCENE).instantiate()  # untyped: instantiate() returns Variant, so := cannot infer
	rocket.direction = Vector3(0.08, -1.0, 0.0).normalized()  # off pure vertical: look_at(UP) would warn (see _drops_onto_world)
	rocket.speed = 20.0
	rocket.life_time = SAFE_LIFE_TIME
	add_child(rocket)
	rocket.global_position = Vector3(0.0, 5.0, 0.0)

	for _i in 90:
		await wait_physics_frames(1)
		if blast[0] != null:
			break

	get_tree().node_added.disconnect(watch)
	if is_instance_valid(rocket):
		rocket.queue_free()
	assert_not_null(blast[0],
		"A rocket that hits the world must put a real Explosion in the scene tree (explosion.gd's _on_rock_projectile_queued_for_deletion). None appeared, so the impact never reached the blast bridge")
	if blast[0] == null:
		return
	# ...and it must LIVE, not pop and vanish inside one frame: the blast's own 0.2s one-shot
	# Timer is what the player sees and what Explosion._on_body_entered damages/pushes through.
	await wait_physics_frames(2)
	assert_true(is_instance_valid(blast[0]) and (blast[0] as Node).is_inside_tree(),
		"The spawned Explosion must still be in the tree a couple of physics frames after impact — it damages and pushes on body entry and fades on its authored 0.2s Timer; a blast that frees immediately would be invisible and harmless")


# ---------------------------------------------------------------------------
# Cheap authored-value pins, so a future edit to rock_projectile.tscn that reverts
# the mask fails loudly here even if the physics test above is ever skipped.
# ---------------------------------------------------------------------------

## Bit 1 (value 1) is the world/environment layer — what func_godot's solid classes build on.
const WORLD_LAYER_BIT: int = 1

func test_rock_projectile_scene_scans_the_world_layer() -> void:
	var rocket = load(ROCK_SCENE).instantiate()  # untyped: instantiate() returns Variant, so := cannot infer
	assert_true((rocket.collision_mask & WORLD_LAYER_BIT) != 0,
		"rock_projectile.tscn must scan layer 1 (the world) in collision_mask — func_godot brushes are layer 1 / mask 0 and cannot detect the rocket themselves, so if the rocket does not scan them the rocket passes through the level")
	assert_true((rocket.collision_mask & 2) != 0,
		"rock_projectile.tscn must keep scanning layer 2 (Player/Enemy) so a direct hit on a character still detonates")
	rocket.free()
