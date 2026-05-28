class_name GunMesh
extends MeshInstance3D

const RIM_LIGHT_SHADER = preload("res://resources/shaders/rim_light.gdshader")

@export var sway_amount: float = 0.02
@export var sway_speed: float = 8.0
@export var player: Character
@export var inventory: Inventory

@export_group("Motion")
@export var walk_bob_pos: float = 0.004
@export var walk_bob_roll_deg: float = 0.6
@export var strafe_roll_deg: float = 3.0
@export var forward_lag: float = 0.04
@export var vertical_pitch_deg: float = 1.2
@export var max_vertical_pitch_deg: float = 8.0
@export var motion_smooth: float = 10.0

@export_group("Mouse Sway")
@export var mouse_sway_pos: float = 0.04
@export var mouse_sway_roll_deg: float = 0.0
@export var mouse_sway_pitch_deg: float = 0.0
@export var mouse_sway_decay: float = 12.0
@export var mouse_sway_max: float = 0.35

@export_group("Breathing")
@export var breath_pos_amount: float = 0.0035
@export var breath_pitch_deg: float = 0.25
@export var breath_speed: float = 1.6
@export var breath_idle_fade_speed: float = 4.0

@export_group("Rim Light")
@export var rim_color: Color = Color(0.95, 0.88, 0.75)
@export var rim_power: float = 5.0
@export var rim_strength: float = 0.5
@export var rim_top_bias: float = 0.35

var tween: Tween
var base_position: Vector3
var base_rotation: Vector3
var _bob_time: float = 0.0
var _breath_time: float = 0.0
var _breath_t: float = 0.0
var _mouse_sway: Vector2 = Vector2.ZERO
var _rim_material: ShaderMaterial

func _ready():
	base_position = position
	base_rotation = rotation_degrees
	_disable_shadows_recursive(self)
	_setup_rim_light()

func _disable_shadows_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_shadows_recursive(child)

func _setup_rim_light() -> void:
	_rim_material = ShaderMaterial.new()
	_rim_material.shader = RIM_LIGHT_SHADER
	_rim_material.set_shader_parameter("rim_color", rim_color)
	_rim_material.set_shader_parameter("rim_power", rim_power)
	_rim_material.set_shader_parameter("rim_strength", rim_strength)
	_rim_material.set_shader_parameter("top_bias", rim_top_bias)
	_apply_rim_recursive(self)

func _apply_rim_recursive(node: Node) -> int:
	var n := 0
	if node is MeshInstance3D:
		n += _chain_rim_on_mesh(node as MeshInstance3D)
	for child in node.get_children():
		n += _apply_rim_recursive(child)
	return n

func _chain_rim_on_mesh(mi: MeshInstance3D) -> int:
	if not mi.mesh or not _rim_material:
		return 0
	var applied := 0
	for surface_idx in mi.mesh.get_surface_count():
		var base: Material = mi.get_surface_override_material(surface_idx)
		if not base:
			base = mi.mesh.surface_get_material(surface_idx)
		if not base and mi.material_override:
			base = mi.material_override
		var chained: Material
		if base:
			chained = base.duplicate()
		else:
			chained = StandardMaterial3D.new()
		chained.next_pass = _rim_material
		mi.set_surface_override_material(surface_idx, chained)
		applied += 1
	return applied

func _process(delta: float) -> void:
	if !is_instance_valid(player) or !player:
		return

	var horizontal_speed := Vector2(player.velocity.x, player.velocity.z).length()
	var on_floor := player.is_on_floor()

	var bob_factor := 0.0
	if on_floor and horizontal_speed > GameSettings.player_movement.footstep_min_horizontal_speed:
		_bob_time += delta * GameSettings.camera.bob_speed
		bob_factor = clampf(horizontal_speed / GameSettings.player_movement.max_speed, 0.0, 1.0)
	else:
		_bob_time = lerpf(_bob_time, 0.0, 1.0 - exp(-motion_smooth * delta))

	var bob_x := cos(_bob_time * 0.5) * walk_bob_pos * bob_factor
	var bob_y := sin(_bob_time) * walk_bob_pos * bob_factor
	var bob_roll := sin(_bob_time * 0.5) * walk_bob_roll_deg * bob_factor

	# Breathing: subtle vertical sway + pitch when standing still, fades when moving.
	var idle_target := 0.0 if (horizontal_speed > GameSettings.player_movement.footstep_min_horizontal_speed or not on_floor) else 1.0
	_breath_t = lerpf(_breath_t, idle_target, 1.0 - exp(-breath_idle_fade_speed * delta))
	_breath_time += delta * breath_speed
	var breath_y := sin(_breath_time) * breath_pos_amount * _breath_t
	var breath_pitch := sin(_breath_time * 0.5) * breath_pitch_deg * _breath_t

	_mouse_sway = _mouse_sway.lerp(Vector2.ZERO, 1.0 - exp(-mouse_sway_decay * delta))
	var mouse_off_x := -_mouse_sway.y * mouse_sway_pos
	var mouse_off_y := _mouse_sway.x * mouse_sway_pos
	var mouse_roll := -_mouse_sway.y * mouse_sway_roll_deg
	var mouse_pitch := -_mouse_sway.x * mouse_sway_pitch_deg

	var sway_x = -player.input_dir.x * sway_amount
	var sway_y = player.input_dir.y * sway_amount * 0.5
	var forward_off = -player.input_dir.y * forward_lag

	var roll = player.input_dir.x * strafe_roll_deg
	var pitch := clampf(-player.velocity.y * vertical_pitch_deg, -max_vertical_pitch_deg, max_vertical_pitch_deg)

	var target_pos := base_position + Vector3(sway_x + bob_x + mouse_off_x, sway_y + bob_y + breath_y + mouse_off_y, forward_off)
	var target_rot := base_rotation + Vector3(pitch + mouse_pitch + breath_pitch, 0.0, roll + bob_roll + mouse_roll)

	var t := 1.0 - exp(-motion_smooth * delta)
	position = position.lerp(target_pos, t)
	rotation_degrees = rotation_degrees.lerp(target_rot, t)

func fire():
	if tween:
		tween.kill()
	position = base_position
	rotation_degrees = base_rotation
	tween = create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "position", base_position + Vector3(0.0, 0.1, 0.4), 0.05)
	tween.tween_property(self, "rotation_degrees", base_rotation + Vector3(-5.0, 0.0, 0.0), 0.05)
	tween.chain().tween_property(self, "position", base_position, 0.1)
	tween.chain().tween_property(self, "rotation_degrees", base_rotation, 0.1)

func reload():
	if tween:
		tween.kill()
	position = base_position
	rotation_degrees = base_rotation
	tween = create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "position", base_position + Vector3(0.0, -0.9, 0.4), 0.5)
	tween.tween_property(self, "rotation_degrees", base_rotation + Vector3(-25.0, 0.0, 0.0), 0.5)

func land(intensity: float = 1.0) -> void:
	# Brief downward dip + slight barrel rise so the gun "absorbs" the landing
	# impact alongside the camera dip. Intensity is the same impact value the
	# camera uses, so heavier landings dip the gun further.
	# Don't interrupt an active fire/reload/swap tween — a tiny landing from
	# something like a downward shot recoil would otherwise stop those mid-anim.
	if tween and tween.is_running():
		return
	position = base_position
	rotation_degrees = base_rotation
	var dip := -0.08 * intensity
	var pitch := 4.0 * intensity
	tween = create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "position", base_position + Vector3(0.0, dip, 0.0), 0.08)
	tween.tween_property(self, "rotation_degrees", base_rotation + Vector3(pitch, 0.0, 0.0), 0.08)
	tween.chain().tween_property(self, "position", base_position, 0.18)
	tween.chain().tween_property(self, "rotation_degrees", base_rotation, 0.18)

func _on_ammo_finished_reloading() -> void:
	if tween:
		tween.kill()
	tween = create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "position", base_position, 0.5)
	tween.tween_property(self, "rotation_degrees", base_rotation, 0.5)

func _on_swap_finished() -> void:
	if inventory and inventory.equipped_weapon and inventory.equipped_weapon.hand_mesh:
		mesh = inventory.equipped_weapon.hand_mesh
		_chain_rim_on_mesh(self)
	_on_ammo_finished_reloading()

func _on_mouse_input_rotate(amt: Vector2) -> void:
	_mouse_sway = (_mouse_sway + amt).limit_length(mouse_sway_max)
