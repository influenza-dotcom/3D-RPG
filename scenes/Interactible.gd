class_name Interactable
extends RigidBody3D

const OUTLINE_SHADER = preload("res://resources/shaders/outline.gdshader")
const OUTLINE_THICKNESS: float = 0.015
const OUTLINE_HIDDEN_COLOR: Color = Color(1.0, 1.0, 1.0, 0.0)
const OUTLINE_VISIBLE_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)

@export var impact_sfx: AudioStreamPlayer3D
@export var collision_shape: CollisionShape3D
@export var mesh_instance: MeshInstance3D
@export var max_hp: int = 5

var hp: int
var _impact_cooldown: float = 0.0
var _damage_cooldown: float = 0.0
var _outline_material: ShaderMaterial
var _pre_step_velocity: Vector3 = Vector3.ZERO
var _destroyed: bool = false

func _ready() -> void:
	hp = max_hp
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	_autofit_collision_shape()
	_setup_outline()

func _autofit_collision_shape() -> void:
	if not collision_shape or not mesh_instance or not mesh_instance.mesh:
		return
	var aabb := mesh_instance.mesh.get_aabb()
	if not collision_shape.shape:
		return
	var unique_shape := collision_shape.shape.duplicate()
	if unique_shape is BoxShape3D:
		(unique_shape as BoxShape3D).size = aabb.size
	elif unique_shape is SphereShape3D:
		(unique_shape as SphereShape3D).radius = maxf(maxf(aabb.size.x, aabb.size.y), aabb.size.z) * 0.5
	elif unique_shape is CapsuleShape3D:
		(unique_shape as CapsuleShape3D).radius = maxf(aabb.size.x, aabb.size.z) * 0.5
		(unique_shape as CapsuleShape3D).height = aabb.size.y
	collision_shape.shape = unique_shape

func _setup_outline() -> void:
	_outline_material = ShaderMaterial.new()
	_outline_material.shader = OUTLINE_SHADER
	_outline_material.set_shader_parameter("outline_color", OUTLINE_HIDDEN_COLOR)
	_outline_material.set_shader_parameter("outline_thickness", OUTLINE_THICKNESS)
	_outline_material.set_shader_parameter("use_smooth_normals", true)
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

func _bake_smooth_normals_into_color(mi: MeshInstance3D) -> void:
	if not mi.mesh:
		return
	var orig := mi.mesh
	var surf_count := orig.get_surface_count()
	var overrides := []
	for s in surf_count:
		overrides.append(mi.get_surface_override_material(s))
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
	for s in overrides.size():
		if overrides[s]:
			mi.set_surface_override_material(s, overrides[s])

func set_outline_visible(visible: bool) -> void:
	if not _outline_material:
		return
	_outline_material.set_shader_parameter(
		"outline_color",
		OUTLINE_VISIBLE_COLOR if visible else OUTLINE_HIDDEN_COLOR
	)

func _physics_process(delta: float) -> void:
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
	on_impact(maxf(my_speed, their_speed))
	_try_damage_character(body, my_speed)

func _try_damage_character(body: Node, my_speed: float) -> void:
	if not body is Character:
		return
	if _damage_cooldown > 0.0:
		return
	if my_speed < GameTuning.INTERACTABLE_DAMAGE_MIN_VELOCITY:
		return
	var damage := int(roundf((my_speed - GameTuning.INTERACTABLE_DAMAGE_MIN_VELOCITY) * GameTuning.INTERACTABLE_DAMAGE_PER_M_PER_S))
	if damage <= 0:
		return
	var character := body as Character
	character.take_damage(damage)
	_damage_cooldown = GameTuning.INTERACTABLE_DAMAGE_COOLDOWN

func on_impact(speed: float) -> void:
	if not impact_sfx:
		return
	if _impact_cooldown > 0.0:
		return
	if speed < GameTuning.INTERACTABLE_IMPACT_MIN_VELOCITY:
		return
	var span := GameTuning.INTERACTABLE_IMPACT_MAX_VELOCITY - GameTuning.INTERACTABLE_IMPACT_MIN_VELOCITY
	var t := clampf((speed - GameTuning.INTERACTABLE_IMPACT_MIN_VELOCITY) / span, 0.0, 1.0)
	impact_sfx.volume_db = lerpf(GameTuning.INTERACTABLE_IMPACT_MIN_DB, GameTuning.INTERACTABLE_IMPACT_MAX_DB, t)
	impact_sfx.pitch_scale = 1.0 + randf_range(-GameTuning.INTERACTABLE_IMPACT_PITCH_SPREAD, GameTuning.INTERACTABLE_IMPACT_PITCH_SPREAD)
	impact_sfx.play()
	_impact_cooldown = GameTuning.INTERACTABLE_IMPACT_COOLDOWN

func take_damage(amount: int) -> void:
	if _destroyed:
		return
	hp -= amount
	if hp <= 0:
		_destroy()

func _destroy() -> void:
	_destroyed = true
	if impact_sfx and impact_sfx.stream:
		impact_sfx.reparent(get_tree().root)
		impact_sfx.global_position = global_position
		impact_sfx.pitch_scale = 0.55
		impact_sfx.volume_db = 4.0
		impact_sfx.play()
		impact_sfx.finished.connect(impact_sfx.queue_free)
	queue_free()

func on_picked_up(_picker: Node) -> void:
	pass

func on_dropped() -> void:
	pass
