@tool
class_name Throwable
extends RigidBody3D

const OUTLINE_SHADER = preload("res://resources/shaders/outline.gdshader")
const FLASH_OVERLAY_SHADER = preload("res://resources/shaders/flash_overlay.gdshader")
const DUST_LARGE = preload("uid://ckxkt0g5gq8bb")
const PARTY_HORN = preload("uid://v2yom7vyodag")
const AIRBORNE_PROBE: float = 0.6  ## a gib with no ground within this many metres below it counts as "mid-air"
const CONFETTI_FRESH_WINDOW_MS: int = 8000  ## a gib older than this (since spawn) no longer confettis when shot
const DESTROY_DECAL = preload("uid://dh1ydtvwvgiqg")  # bullet_hole / scorch decal
const DESTROY_DECAL_SIZE: Vector3 = Vector3(2.0, 1.0, 2.0)
const DESTROY_DECAL_PROBE: float = 3.0
const DESTROY_DECAL_CULL_MASK: int = 2
const DESTROY_DECAL_PARALLEL_THRESHOLD: float = 0.99
const GRAPPLE_DAMAGE_GRACE: float = 1.5  ## a grappled throwable can't hurt the grappler for this long after release
const THROWN_CREDIT_GRACE: float = 4.0  ## seconds a thrown/dropped prop credits its thrower as the attacker after release (covers the flight + a bounce); then it goes inert so a crate later bumped at rest can't blame the thrower

const OUTLINE_HIDDEN_COLOR: Color = Color(0.0, 0.0, 0.0, 1.0)
const OUTLINE_VISIBLE_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const FLASH_PEAK_STRENGTH: float = 2.0
const FLASH_UP_TIME: float = 0.08
const FLASH_DOWN_TIME: float = 0.18

@export var data: ThrowableData : set = _set_data
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
var _confetti_eligible: bool = true  ## cleared when picked up so a thrown gib can't be shot for confetti
var _spawn_msec: int = 0  ## tree-entry time; gates confetti to freshly-spawned gibs (see CONFETTI_FRESH_WINDOW_MS)
var _grapple_owner: Node = null  ## the player currently grappling/tethering this — immune to its impact damage
var _grapple_grace: float = 0.0  ## seconds the grapple owner stays immune (covers the bonk just after release)
var _thrown_by: Node = null  ## who last threw/dropped this (the player) — credited as the attacker for its impact damage so beaning an NPC with it aggros them at the thrower
var _thrown_grace: float = 0.0  ## seconds the thrower stays credited after release (ticked down in _physics_process)

func _ready() -> void:
	_autofit_collision_shape()
	if Engine.is_editor_hint():
		_apply_data_to_visuals()
		return
	if data:
		_apply_data_to_visuals()
		max_hp = data.max_hp
	hp = max_hp
	_spawn_msec = Time.get_ticks_msec()
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	_setup_overlay_chain()

func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		_autofit_collision_shape()
		_apply_data_to_visuals()

func _set_data(value: ThrowableData) -> void:
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
	# outline_width = 1.0 IS the shipped look (the chunky shell): this code previously set a non-existent
	# `outline_thickness` uniform (the same latent no-op talk_helpers.gd documents) plus a dead
	# `use_smooth_normals` toggle, so the shader's 1.0 DEFAULT is what has always rendered. Codified
	# explicitly so a future shader-default change can't silently restyle every throwable. (The old
	# smooth-normal vertex-colour bake was authored for an outline shader that never shipped — the live
	# shader reads only NORMAL — so the whole mesh-rebuild pass was dead work and is gone; see git.)
	_outline_material.set_shader_parameter("outline_width", 1.0)
	_outline_material.next_pass = _flash_material
	var targets: Array[MeshInstance3D] = []
	_collect_mesh_instances(self, targets)
	for m in targets:
		m.material_overlay = _outline_material

func _collect_mesh_instances(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_mesh_instances(child, out)

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
	if _grapple_grace > 0.0:
		_grapple_grace -= delta
		if _grapple_grace <= 0.0:
			_grapple_owner = null
	if _thrown_grace > 0.0:
		_thrown_grace -= delta
		if _thrown_grace <= 0.0:
			_thrown_by = null
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
	# Gore gibs (data.damages_player = false) don't hurt the PLAYER — being pelted by your own kill's
	# flying chunks shouldn't chip your health. Other characters still take impact damage.
	if body.is_in_group(&"Player") and data and not data.damages_player:
		return
	# A throwable the player is grappling (or just released) must not hurt the grappler: reeling a crate
	# toward yourself, or slamming into a tethered one and shoving it back into you, shouldn't chip your HP.
	if _grapple_grace > 0.0 and body == _grapple_owner:
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
	# Credit the thrower (or grappler) as the attacker so beaning an NPC with a thrown prop counts as the
	# player attacking it — the NPC provokes and rounds on you, same as a gunshot. No hit point passed
	# (default Vector3.INF) so it aggros without also rolling locational/limb damage from a blunt prop.
	character.take_damage(damage, false, _credited_attacker())
	_damage_cooldown = GameSettings.physics_damage.interactable_damage_cooldown

func _try_self_damage(impact_speed: float) -> void:
	if impact_speed < GameSettings.physics_damage.interactable_self_damage_min_velocity:
		return
	var dmg := int(roundf((impact_speed - GameSettings.physics_damage.interactable_self_damage_min_velocity) * GameSettings.physics_damage.interactable_self_damage_per_m_per_s))
	if dmg <= 0:
		return
	take_damage(dmg)

## Mark this throwable as currently grappled/tethered by `by` (the player). While grappled — and for a
## short grace after release — it deals NO impact damage to that player (see _try_damage_character).
## Refreshed each frame the grapple holds it, so the grace only starts counting down once released.
func mark_grappled_by(by: Node) -> void:
	_grapple_owner = by
	_grapple_grace = GRAPPLE_DAMAGE_GRACE

## Mark this throwable as just THROWN (or dropped) by `by` (the player). For a short grace after, any impact
## damage it deals to a Character credits `by` as the attacker — so beaning an NPC with a thrown crate aggros
## them at the thrower, exactly like shooting them. After the grace the prop is inert again.
func mark_thrown_by(by: Node) -> void:
	_thrown_by = by
	_thrown_grace = THROWN_CREDIT_GRACE

## Who to blame for this prop's impact damage right now: whoever just threw it (within the throw grace),
## else whoever is grappling / just released it (a tethered slam is a deliberate hit too), else no-one — a
## stray bump while at rest credits nobody, so it can't wrongly aggro an NPC at the player.
func _credited_attacker() -> Node:
	if is_instance_valid(_thrown_by) and _thrown_grace > 0.0:
		return _thrown_by
	if is_instance_valid(_grapple_owner) and _grapple_grace > 0.0:
		return _grapple_owner
	return null

## Mark this throwable as a GORE GIB with a limited lifetime: register it in the &"gib" group (for the
## spawn-time cap in GoreSpawner), wait `lifetime` seconds, then fade the mesh out over `fade` and free
## itself — so gibs don't pile up forever (mirrors the ragdoll corpse timeout). Only gore gibs call this;
## crates / other throwables never do, so they persist as before.
func begin_gib_lifetime(lifetime: float, fade: float) -> void:
	add_to_group(&"gib")
	await get_tree().create_timer(lifetime).timeout
	if _destroyed or not is_inside_tree():
		return  # already shot apart / culled / freed during the wait
	_destroyed = true  # claim it so a stray hit mid-fade can't also run _destroy()
	if mesh_instance:
		var tw := create_tween()
		tw.tween_property(mesh_instance, "transparency", 1.0, fade)
		await tw.finished
	if is_inside_tree():
		queue_free()

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

func take_damage(amount: int, _was_crit: bool = false, attacker: Node = null) -> void:
	if _destroyed:
		return
	hp -= amount
	_flash_red()
	if hp <= 0:
		_destroy(attacker)

func _flash_red() -> void:
	if not _flash_material:
		return
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_material, "shader_parameter/flash_strength", FLASH_PEAK_STRENGTH, FLASH_UP_TIME)
	_flash_tween.tween_property(_flash_material, "shader_parameter/flash_strength", 0.0, FLASH_DOWN_TIME)

signal destroy

func _destroy(attacker: Node = null) -> void:
	destroy.emit()
	_destroyed = true
	_wake_contacts()
	_spawn_destroy_particle()
	_spawn_destroy_decal()
	_shake_nearby_screens()
	_play_destroy_sound()
	# Bonus on TOP of the normal gore (blood + splosh still play): a gib the PLAYER shoots out of the air
	# right after it bursts from a kill gets a celebratory confetti pop + party horn. Picked-up/thrown or
	# stale gibs are disqualified (anti-cheese); crates never qualify.
	if _is_confetti_kill(attacker):
		EffectFactory.spawn_blood_particle(global_position)  # a clear blood burst too — confetti is ON TOP of the gore
		_spawn_confetti()
		AudioManager.play_sfx(global_position, PARTY_HORN, 0.0, 1.0)  # 3D positional one-shot
	queue_free()

## True only for a gore gib that the PLAYER shot while it was airborne — the confetti trick-shot trigger.
func _is_confetti_kill(attacker: Node) -> bool:
	if data == null or not data.is_gib:
		return false
	if not _confetti_eligible:
		return false  # already picked up / thrown -- no cheesing confetti with a tossed gib
	if Time.get_ticks_msec() - _spawn_msec >= CONFETTI_FRESH_WINDOW_MS:
		return false  # only a gib fresh off a kill qualifies, not one that's been lying around
	if attacker == null or not attacker.is_in_group(&"Player"):
		return false
	return _is_airborne()

## True if nothing solid sits just below us — i.e. the prop is in flight, not resting on a surface.
func _is_airborne() -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3.DOWN * AIRBORNE_PROBE)
	query.exclude = [get_rid()]
	return space.intersect_ray(query).is_empty()

## Burst of multicolour confetti flecks at our position — a self-freeing, code-built GPUParticles3D
## (one-shot). Each fleck draws a random colour from a rainbow ramp (color_initial_ramp) and tumbles.
func _spawn_confetti() -> void:
	var p := GPUParticles3D.new()
	get_tree().root.add_child(p)
	p.global_position = global_position
	p.amount = 48
	p.lifetime = 1.7
	p.one_shot = true
	p.explosiveness = 1.0
	p.speed_scale = 1.3
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
	grad.colors = PackedColorArray([
		Color(0.95, 0.20, 0.25), Color(0.98, 0.62, 0.12), Color(0.97, 0.90, 0.20),
		Color(0.22, 0.82, 0.30), Color(0.20, 0.55, 0.95), Color(0.70, 0.30, 0.90),
	])
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	var ppm := ParticleProcessMaterial.new()
	ppm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	ppm.emission_sphere_radius = 0.12
	ppm.direction = Vector3(0.0, 1.0, 0.0)
	ppm.spread = 120.0
	ppm.initial_velocity_min = 3.0
	ppm.initial_velocity_max = 6.5
	ppm.gravity = Vector3(0.0, -9.0, 0.0)
	ppm.angular_velocity_min = -540.0
	ppm.angular_velocity_max = 540.0
	ppm.scale_min = 0.6
	ppm.scale_max = 1.3
	ppm.color_initial_ramp = grad_tex
	ppm.turbulence_enabled = true
	ppm.turbulence_noise_strength = 2.2
	ppm.turbulence_noise_scale = 1.4
	p.process_material = ppm
	var flake := BoxMesh.new()
	flake.size = Vector3(0.06, 0.06, 0.012)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	flake.material = mat
	p.draw_pass_1 = flake
	p.emitting = true
	p.finished.connect(p.queue_free)

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

## See-through factor while CARRIED (Deus Ex style): the held prop fades so it doesn't wall off the screen
## at arm's length. 0 = opaque; restored on drop/throw.
const CARRIED_TRANSPARENCY: float = 0.4

## Hover label for the look-at readout. A bare throwable under the crosshair reads "[<throw key>] Pick Up":
## PickupRay falls back to the Throwable as the readout target when no talk handler is aimed, and the
## player's readout prefixes the CARRY key — the input unique to throwables (E would stash a dual item).
func look_name() -> String:
	return "Pick Up"

func on_picked_up(_picker: Node) -> void:
	_confetti_eligible = false  # handled by the player -- no longer a fresh kill gib (anti-confetti-cheese)
	_set_carried_transparency(true)

func on_dropped() -> void:
	_set_carried_transparency(false)

## Deus Ex-style carry fade: apply/clear CARRIED_TRANSPARENCY on every MeshInstance3D under us (the same
## set the outline collects), via GeometryInstance3D.transparency. Fired from on_picked_up / on_dropped, so
## every grab path (PickUp hold AND the throw key) and every release (drop, throw, yanked-too-far) gets it.
func _set_carried_transparency(carried: bool) -> void:
	var targets: Array[MeshInstance3D] = []
	_collect_mesh_instances(self, targets)
	for m in targets:
		m.transparency = CARRIED_TRANSPARENCY if carried else 0.0
