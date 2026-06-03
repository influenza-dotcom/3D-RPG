@tool
class_name Interactable
extends RigidBody3D

const OUTLINE_SHADER = preload("res://resources/shaders/outline.gdshader")
const FLASH_OVERLAY_SHADER = preload("res://resources/shaders/flash_overlay.gdshader")
const DUST_LARGE = preload("uid://ckxkt0g5gq8bb")
const DESTROY_DECAL = preload("uid://dh1ydtvwvgiqg")  # bullet_hole / scorch decal
const DESTROY_DECAL_SIZE: Vector3 = Vector3(2.0, 1.0, 2.0)
const DESTROY_DECAL_PROBE: float = 3.0
const DESTROY_DECAL_CULL_MASK: int = 2
const DESTROY_DECAL_PARALLEL_THRESHOLD: float = 0.99

const OUTLINE_THICKNESS: float = 0.015
const OUTLINE_HIDDEN_COLOR: Color = Color(0.0, 0.0, 0.0, 1.0)
const OUTLINE_VISIBLE_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const FLASH_PEAK_STRENGTH: float = 2.0
const FLASH_UP_TIME: float = 0.08
const FLASH_DOWN_TIME: float = 0.18

@export var data: InteractableData : set = _set_data
@export var impact_sfx: AudioStreamPlayer3D
@export var collision_shape: CollisionShape3D
@export var mesh_instance: MeshInstance3D
@export var max_hp: int = 5

var hp: int
var _impact_cooldown: float = 0.0
var _damage_cooldown: float = 0.0
var _outline_material: ShaderMaterial
var _flash_material: ShaderMaterial
var _flash_tween: Tween
var _pre_step_velocity: Vector3 = Vector3.ZERO
var _destroyed: bool = false

func _ready() -> void:
	_autofit_collision_shape()
	if Engine.is_editor_hint():
		_apply_data_to_visuals()
		return
	if data:
		_apply_data_to_visuals()
		max_hp = data.max_hp
	hp = max_hp
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	_setup_overlay_chain()

func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		_autofit_collision_shape()
		_apply_data_to_visuals()

func _set_data(value: InteractableData) -> void:
	data = value
	if Engine.is_editor_hint():
		_apply_data_to_visuals()
		_autofit_collision_shape()

func _apply_data_to_visuals() -> void:
	if not data:
		return
	if mesh_instance:
		if data.mesh:
			mesh_instance.mesh = data.mesh
		if data.material:
			mesh_instance.material_override = data.material
	if data.physics_material:
		physics_material_override = data.physics_material
	if data.mass > 0:
		mass = data.mass
	if impact_sfx and data.impact_sound:
		impact_sfx.stream = data.impact_sound

func _autofit_collision_shape() -> void:
	if not collision_shape or not mesh_instance or not mesh_instance.mesh:
		return
	if not collision_shape.shape:
		return
	var aabb := mesh_instance.mesh.get_aabb()
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

func _setup_overlay_chain() -> void:
	_flash_material = ShaderMaterial.new()
	_flash_material.shader = FLASH_OVERLAY_SHADER
	_flash_material.set_shader_parameter("flash_strength", 0.0)
	_outline_material = ShaderMaterial.new()
	_outline_material.shader = OUTLINE_SHADER
	_outline_material.set_shader_parameter("outline_color", OUTLINE_HIDDEN_COLOR)
	_outline_material.set_shader_parameter("outline_thickness", OUTLINE_THICKNESS)
	_outline_material.set_shader_parameter("use_smooth_normals", true)
	_outline_material.next_pass = _flash_material
	var targets: Array[MeshInstance3D] = []
	_collect_mesh_instances(self, targets)
	for m in targets:
		_bake_smooth_normals_into_color(m)
		m.material_overlay = _outline_material

func _collect_mesh_instances(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_mesh_instances(child, out)

## Cache of baked (smooth-normal → vertex-colour) meshes, keyed by source mesh and shared across
## all instances. This bake is a CPU mesh rebuild; gore gibs spawn 6 at a time sharing ONE mesh,
## so re-running it per instance every kill was a main-thread hitch. Bake once, reuse everywhere.
static var _smooth_normal_bake_cache: Dictionary = {}

func _bake_smooth_normals_into_color(mi: MeshInstance3D) -> void:
	if not mi.mesh:
		return
	var orig := mi.mesh
	var surf_count := orig.get_surface_count()
	var overrides := []
	for s in surf_count:
		overrides.append(mi.get_surface_override_material(s))
	# Reuse a previously-baked result for this source mesh (meshes are safely shareable).
	var cached = _smooth_normal_bake_cache.get(orig)
	if cached:
		mi.mesh = cached
		for s in overrides.size():
			if overrides[s]:
				mi.set_surface_override_material(s, overrides[s])
		return
	var new_mesh := ArrayMesh.new()
	for surface_idx in surf_count:
		var arrays := orig.surface_get_arrays(surface_idx)
		var prim_type := Mesh.PRIMITIVE_TRIANGLES
		if orig.has_method("surface_get_primitive_type"):
			prim_type = orig.surface_get_primitive_type(surface_idx)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		if verts.size() == 0 or norms.size() != verts.size():
			new_mesh.add_surface_from_arrays(prim_type, arrays)
		else:
			var buckets := {}
			var snap := Vector3(0.0001, 0.0001, 0.0001)
			for i in verts.size():
				var key := verts[i].snapped(snap)
				if buckets.has(key):
					buckets[key] = (buckets[key] as Vector3) + norms[i]
				else:
					buckets[key] = norms[i]
			var colors := PackedColorArray()
			colors.resize(verts.size())
			for i in verts.size():
				var key := verts[i].snapped(snap)
				var sn: Vector3 = (buckets[key] as Vector3).normalized()
				colors[i] = Color(sn.x * 0.5 + 0.5, sn.y * 0.5 + 0.5, sn.z * 0.5 + 0.5, 1.0)
			arrays[Mesh.ARRAY_COLOR] = colors
			new_mesh.add_surface_from_arrays(prim_type, arrays)
		var mat := orig.surface_get_material(surface_idx)
		if mat:
			new_mesh.surface_set_material(surface_idx, mat)
	mi.mesh = new_mesh
	_smooth_normal_bake_cache[orig] = new_mesh
	for s in overrides.size():
		if overrides[s]:
			mi.set_surface_override_material(s, overrides[s])

func set_outline_visible(_visible: bool = visible) -> void:
	if not _outline_material:
		return
	_outline_material.set_shader_parameter(
		"outline_color",
		OUTLINE_VISIBLE_COLOR if _visible else OUTLINE_HIDDEN_COLOR
	)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _impact_cooldown > 0.0:
		_impact_cooldown -= delta
	if _damage_cooldown > 0.0:
		_damage_cooldown -= delta
	_pre_step_velocity = linear_velocity

func _on_body_entered(body: Node) -> void:
	var my_speed := _pre_step_velocity.length()
	var their_speed := 0.0
	if body is RigidBody3D:
		their_speed = (body as RigidBody3D).linear_velocity.length()
	elif body is CharacterBody3D:
		their_speed = (body as CharacterBody3D).velocity.length()
	var impact_speed := maxf(my_speed, their_speed)
	on_impact(impact_speed)
	_try_damage_character(body, my_speed)
	_try_self_damage(impact_speed)

func _try_damage_character(body: Node, my_speed: float) -> void:
	if not body is Character:
		return
	if _damage_cooldown > 0.0:
		return
	if my_speed < GameSettings.physics_damage.interactable_damage_min_velocity:
		return
	var damage := int(roundf((my_speed - GameSettings.physics_damage.interactable_damage_min_velocity) * GameSettings.physics_damage.interactable_damage_per_m_per_s))
	if damage <= 0:
		return
	var character := body as Character
	EffectFactory.spawn_blood_particle(character.global_position)
	if character.get("bloody_mess"):
		var dir := _pre_step_velocity if _pre_step_velocity.length() > 0.01 else Vector3.UP
		character.bloody_mess.splatter_at(character.global_position, dir)
	character.take_damage(damage)
	_damage_cooldown = GameSettings.physics_damage.interactable_damage_cooldown

func _try_self_damage(impact_speed: float) -> void:
	if impact_speed < GameSettings.physics_damage.interactable_self_damage_min_velocity:
		return
	var dmg := int(roundf((impact_speed - GameSettings.physics_damage.interactable_self_damage_min_velocity) * GameSettings.physics_damage.interactable_self_damage_per_m_per_s))
	if dmg <= 0:
		return
	take_damage(dmg)

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

func take_damage(amount: int, _was_crit: bool = false, _attacker: Node = null) -> void:
	if _destroyed:
		return
	hp -= amount
	_flash_red()
	if hp <= 0:
		_destroy()

func _flash_red() -> void:
	if not _flash_material:
		return
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_material, "shader_parameter/flash_strength", FLASH_PEAK_STRENGTH, FLASH_UP_TIME)
	_flash_tween.tween_property(_flash_material, "shader_parameter/flash_strength", 0.0, FLASH_DOWN_TIME)

signal destroy

func _destroy() -> void:
	destroy.emit()
	_destroyed = true
	_wake_contacts()
	_spawn_destroy_particle()
	_spawn_destroy_decal()
	_shake_nearby_screens()
	_play_destroy_sound()
	queue_free()

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
	var particle_scene: PackedScene = data.destroy_particle_scene if data and data.destroy_particle_scene else DUST_LARGE
	if not particle_scene:
		return
	var p = particle_scene.instantiate()
	get_tree().root.add_child(p)
	if p is Node3D:
		(p as Node3D).global_position = global_position
	if p is GPUParticles3D:
		(p as GPUParticles3D).emitting = true
		(p as GPUParticles3D).finished.connect(p.queue_free)
	elif p.has_signal("finished"):
		p.finished.connect(p.queue_free)

func _shake_nearby_screens() -> void:
	var amount: float = data.destroy_screen_shake if data else GameSettings.physics_damage.interactable_destroy_shake_amount
	if amount <= 0.0:
		return
	var players := get_tree().get_nodes_in_group("Player")
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

func on_picked_up(_picker: Node) -> void:
	pass

func on_dropped() -> void:
	pass
