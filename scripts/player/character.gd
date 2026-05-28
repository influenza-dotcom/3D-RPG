class_name Character
extends CharacterBody3D

## Shared base for all damageable, physics-driven actors — Player and Enemy both
## extend this. Provides: HP + death, the damage flash + outline material overlay,
## the decaying "blast" impulse system (explosion_velocity) used for rocket jumps /
## launches / ram knockback, and the on-death gore/gib spawn. Subclasses override
## apply_velocity() for their own movement (Player: full controller; Enemy: friction
## + drift) but reuse the blast and gore machinery here.

## Emitted on every damage application (after hp changes). Health UI listens.
signal damaged(current_hp: float, max_hp: float)
## Emitted once when this character dies (from take_damage). Enemy wires this to its
## death SFX + freeze-frame + the cha-ching kill reward.
signal died()

## Divisor applied to explosion_velocity AFTER move_and_slide each frame — the
## per-frame "give-back" that bleeds a blast impulse down over time. Larger = blast
## decays faster. Must stay > 1 or the blast would never settle.
@export var blast_damp_divisor: float = 1.12

@export var max_hp: int = 10
var hp: int
@export var mesh: Node3D
const BLOOD_SPLAT_DECAL = preload("uid://dg5ui5is8sakg")
const CHARACTER_DUST = preload("uid://um6f8g8g6l7v")
const FLASH_OVERLAY_SHADER = preload("res://resources/shaders/flash_overlay.gdshader")
const OUTLINE_SHADER = preload("res://resources/shaders/outline.gdshader")
const FLASH_PEAK_STRENGTH: float = 2.0
const FLASH_UP_TIME: float = 0.08
const FLASH_DOWN_TIME: float = 0.18
const OUTLINE_THICKNESS: float = 0.085
const OUTLINE_COLOR: Color = Color.BLACK

@export var has_outline: bool = true

## Decaying impulse layered on top of normal movement velocity. Systems ADD to it
## (rocket self-knockback, melee dash, slide-jump, pinball ram bounce, enemy
## knockback); apply_blast() + apply_velocity() consume and decay it. Lets external
## forces fling the actor without permanently overwriting controller velocity.
var explosion_velocity: Vector3

## Grace countdown that keeps a blast "alive" briefly even while grounded, so a
## ground-level blast (e.g. the ram bounce) isn't instantly zeroed by the floor
## check in apply_blast(). Re-armed whenever explosion_velocity is sizable.
var _blast_timer: float = 0.0
## Latched on the killing hit so take_damage()/gore can't fire twice when multiple
## hits land in one frame (e.g. a shotgun's pellets).
var _dead: bool = false
var _flash_material: ShaderMaterial
var _outline_material: ShaderMaterial
var _flash_tween: Tween

func _ready():
	hp = max_hp
	_setup_overlay_chain()

## Build the per-instance damage-flash + black outline as a single material_overlay
## and apply it to every MeshInstance3D under `mesh`. Godot pattern: material_overlay
## renders on top of each surface's own material without modifying it; chaining
## outline.next_pass = flash makes one overlay produce BOTH the inflated-hull outline
## and the hit-flash. has_outline=false skips the outline (flash only). Built once in
## _ready; flash_red() and the death tint then only drive the flash uniform.
func _setup_overlay_chain() -> void:
	if not mesh:
		return
	_flash_material = ShaderMaterial.new()
	_flash_material.shader = FLASH_OVERLAY_SHADER
	_flash_material.set_shader_parameter("flash_strength", 0.0)
	var overlay: Material = _flash_material
	if has_outline:
		_outline_material = ShaderMaterial.new()
		_outline_material.shader = OUTLINE_SHADER
		_outline_material.set_shader_parameter("outline_color", OUTLINE_COLOR)
		_outline_material.set_shader_parameter("outline_thickness", OUTLINE_THICKNESS)
		_outline_material.next_pass = _flash_material
		overlay = _outline_material
	var targets: Array[MeshInstance3D] = []
	_collect_mesh_instances(mesh, targets)
	for m in targets:
		m.material_overlay = overlay

func _collect_mesh_instances(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_mesh_instances(child, out)

func flash_red() -> void:
	if not _flash_material:
		return
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(
		_flash_material, "shader_parameter/flash_strength", FLASH_PEAK_STRENGTH*4, FLASH_UP_TIME
	)
	_flash_tween.tween_property(
		_flash_material, "shader_parameter/flash_strength", 0.0, FLASH_DOWN_TIME
	)

func take_damage(_amount: int):
	# Guard: prevents multi-hit kills (e.g. shotgun's 9 pellets in one frame)
	# from triggering gore/die multiple times. queue_free is deferred so the
	# body still exists in the same frame and would otherwise receive every
	# subsequent pellet, each one firing 100 rain drops + 6 gibs + a death SFX.
	if _dead:
		return
	flash_red()
	hp -= _amount
	damaged.emit(hp, max_hp)
	if hp <= 0:
		_dead = true
		gore()
		die()

func die():
	died.emit()
	queue_free()

func heal(_amount: int):
	hp = min(hp + _amount, max_hp)
	damaged.emit(hp, max_hp)

func gravity(delta: float):
	if !is_on_floor():
		velocity += get_gravity() * delta

## Standard move step. Adds the blast impulse to velocity for THIS frame's move,
## slides, pushes any rigid bodies hit, then removes a fraction (1/blast_damp_divisor)
## of the blast so it bleeds off over subsequent frames instead of persisting.
## pre_move_velocity is captured BEFORE move_and_slide because the slide response
## zeroes velocity into surfaces, and _push_interactables needs the original speed.
func apply_velocity():
	velocity += explosion_velocity
	var pre_move_velocity := velocity
	move_and_slide()
	_push_interactables(pre_move_velocity)
	velocity -= explosion_velocity / blast_damp_divisor

## Variant that slides WITHOUT first adding explosion_velocity, yet still applies the
## post-move damp. TODO: currently has no callers (dead code) and is asymmetric — it
## subtracts the blast give-back without the matching add. Verify intent before use;
## left as-is (no behavior change).
func apply_velocity_launch_forward():
	var pre_move_velocity := velocity
	move_and_slide()
	_push_interactables(pre_move_velocity)
	velocity -= explosion_velocity / blast_damp_divisor

func _push_interactables(pre_move_velocity: Vector3) -> void:
	# CharacterBody3D doesn't push RigidBody3D on its own. After move_and_slide,
	# apply an impulse to any non-frozen rigid body we collided with, scaled by
	# how fast we were moving into it. Uses the PRE-move velocity because the
	# collision response already zeroed `velocity` into the body by now.
	var force: float = GameSettings.physics_damage.character_push_force
	if force <= 0.0:
		return
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var collider := c.get_collider()
		if collider is RigidBody3D:
			var rb := collider as RigidBody3D
			if rb.freeze:
				continue
			var push_dir := -c.get_normal()
			var into_speed := pre_move_velocity.dot(push_dir)
			if into_speed <= 0.0:
				continue
			var contact_offset := c.get_position() - rb.global_position
			rb.apply_impulse(push_dir * into_speed * force, contact_offset)

## Per-frame blast bookkeeping, called before apply_velocity(). A sizable blast
## (re)arms the grace timer so a fresh impulse survives at least blast_grace_timer
## seconds even on the floor. Once grounded AND grace has elapsed, the blast is
## hard-zeroed (so you don't keep sliding after landing). While airborne or within
## grace it eases toward zero frame-rate-independently, snapping to zero below a min
## magnitude to avoid an endless tiny residual.
func apply_blast():
	if explosion_velocity.length() > GameSettings.physics_damage.blast_min_magnitude:
		_blast_timer = GameSettings.physics_damage.blast_grace_timer

	if is_on_floor() and _blast_timer <= 0.0:
		explosion_velocity = Vector3.ZERO
		return

	var dt := get_physics_process_delta_time()
	_blast_timer -= dt
	var blast_t := 1.0 - pow(1.0 - GameSettings.physics_damage.blast_decay_rate, dt * GameSettings.player_movement.smoothing_reference_fps)
	explosion_velocity = explosion_velocity.lerp(Vector3.ZERO, blast_t)
	if explosion_velocity.length() < GameSettings.physics_damage.blast_min_magnitude:
		explosion_velocity = Vector3.ZERO

## Base actor step — Enemy uses this; Player overrides _physics_process entirely.
## Order is load-bearing: gravity first so the frame's downward accel is in velocity,
## apply_blast() next to arm/decay the impulse, apply_velocity() last to add the
## blast and move. Do not reorder.
func _physics_process(delta: float) -> void:
	gravity(delta)
	apply_blast()
	apply_velocity()

## Spawn a flat blood splat decal on the floor beneath the character (on death).
## Raycasts straight down, orients the decal to the hit surface normal, and uses
## cull_mask = 2 (the world's decal render layer) so it lands on level geometry but
## not on view-model/gun meshes (which live on the gun layer). The gib floor-decal
## logic in bloody_mess.gd mirrors this.
func spawn_blood_decal() -> void:
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + Vector3.DOWN * 2.0
	)
	query.exclude = [self]
	var result := space_state.intersect_ray(query)

	if result:
		var decal = BLOOD_SPLAT_DECAL.instantiate()
		get_tree().root.add_child(decal)

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

@export var bloody_mess: Node3D

# Gore-gib system: when a character dies, spawn a handful of interactable
# rigid bodies that fly outward. The gib's visuals, mesh, sounds, mass,
# data resource (incl. destroy particle), and outline are all editable in
# res://scenes/effects/gore_gib.tscn. Per-spawn we only randomize position,
# velocity, rotation, and a fragility roll.
@export var gib_scene: PackedScene = preload("uid://bgore1gib0scn")
const GIB_COUNT: int = 6
const GIB_SPAWN_OFFSET_XZ: float = 0.3
const GIB_SPAWN_OFFSET_Y_MIN: float = 0.4
const GIB_SPAWN_OFFSET_Y_MAX: float = 1.0
const GIB_VEL_MIN: float = 7.0
const GIB_VEL_MAX: float = 14.0
const GIB_UP_BIAS_MIN: float = 0.8
const GIB_UP_BIAS_MAX: float = 2.2
const GIB_ANGULAR_RANGE: float = 18.0
const GIB_HP_MIN: int = 1
const GIB_HP_MAX: int = 2

func gore() -> void:
	spawn_blood_decal()
	if bloody_mess:
		bloody_mess.particles(Vector3.ZERO)
	_notify_nearby_players_of_death()
	spawn_gibs()

func spawn_gibs() -> void:
	if gib_scene == null:
		return
	var spawned: Array[RigidBody3D] = []
	for i in GIB_COUNT:
		var gib = gib_scene.instantiate()
		get_tree().root.add_child(gib)
		# Per-spawn fragility roll. Override hp after add_child so _ready (which
		# sets hp from data.max_hp) has already run. Some gibs survive impact,
		# others break on first contact.
		var random_hp := randi_range(GIB_HP_MIN, GIB_HP_MAX)
		gib.max_hp = random_hp
		gib.hp = random_hp
		gib.global_position = global_position + Vector3(
			randf_range(-GIB_SPAWN_OFFSET_XZ, GIB_SPAWN_OFFSET_XZ),
			randf_range(GIB_SPAWN_OFFSET_Y_MIN, GIB_SPAWN_OFFSET_Y_MAX),
			randf_range(-GIB_SPAWN_OFFSET_XZ, GIB_SPAWN_OFFSET_XZ)
		)
		var dir := Vector3(
			randf_range(-1.0, 1.0),
			randf_range(GIB_UP_BIAS_MIN, GIB_UP_BIAS_MAX),
			randf_range(-1.0, 1.0)
		).normalized()
		gib.linear_velocity = dir * randf_range(GIB_VEL_MIN, GIB_VEL_MAX)
		gib.angular_velocity = Vector3(
			randf_range(-GIB_ANGULAR_RANGE, GIB_ANGULAR_RANGE),
			randf_range(-GIB_ANGULAR_RANGE, GIB_ANGULAR_RANGE),
			randf_range(-GIB_ANGULAR_RANGE, GIB_ANGULAR_RANGE),
		)
		spawned.append(gib)
	# Mutual collision exceptions so gibs from this death don't collide with
	# each other on spawn — they'd otherwise overlap and the physics engine
	# would shove them apart at high speed, triggering self-damage instantly.
	for i in spawned.size():
		for j in range(i + 1, spawned.size()):
			spawned[i].add_collision_exception_with(spawned[j])

func _notify_nearby_players_of_death() -> void:
	var range_max := maxf(GameSettings.effects.blood_splatter_range, GameSettings.screen_shake.death_shake_range)
	var players := get_tree().get_nodes_in_group("Player")
	for p in players:
		if p == self:
			continue
		if not p is Node3D:
			continue
		var d := global_position.distance_to(p.global_position)
		if d > range_max:
			continue
		if p.has_method("on_nearby_death"):
			p.on_nearby_death(d)

func spawn_dust(intensity: float = 1.0) -> void:
	if not is_inside_tree():
		return
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + Vector3.DOWN * GameSettings.effects.dust_ground_probe_distance
	)
	query.exclude = [self]
	var result := space_state.intersect_ray(query)
	var pos: Vector3 = result.position if result else global_position
	var dust: GPUParticles3D = CHARACTER_DUST.instantiate()
	get_tree().root.add_child(dust)
	dust.global_position = pos + Vector3.UP * GameSettings.effects.dust_ground_offset
	var safe_intensity = max(intensity, 0.05)
	dust.scale = Vector3.ONE * safe_intensity
	dust.amount_ratio = clampf(safe_intensity, GameSettings.effects.dust_amount_ratio_min, 1.0)
	dust.emitting = true
	dust.finished.connect(dust.queue_free)
