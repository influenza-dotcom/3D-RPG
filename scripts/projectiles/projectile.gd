@abstract
class_name Projectile
extends RigidBody3D

## Abstract base for all projectiles: owns flight (direction/speed/life_time), the
## damage + knockback + impact-SFX orchestration in _on_body_entered, and the
## queued_for_deletion deletion hook. Concrete variants (Bullet, RockProjectile)
## implement the two per-variant hooks below: particles() and _spawn_decal().

var direction: Vector3 = Vector3.FORWARD
var speed: float = 8.00
var damage: float = 2.0
var headshot_multiplier: float = 2.0  # set by ProjectileSpawner from the weapon
var sneak_attack_multiplier: float = 2.0  # set by ProjectileSpawner from the weapon
var life_time: float = 10.0
@onready var collision_shape_3d: CollisionShape3D = $CollisionShape3D

var visual_only: bool = false
var _consumed: bool = false
## Who fired this — set by ProjectileSpawner to the wielder. Used to flash their hitmarker
## (and feed the victim's damage arc) when a long-range/out-of-range projectile lands.
var shooter: Character = null

const BULLET_HOLE_DECAL = preload("uid://dh1ydtvwvgiqg")

const DECAL_SIZE: Vector3 = Vector3(0.3, 0.1, 0.3)
const DECAL_CULL_MASK: int = 1048571  # all render layers except the gun's (layer 3); layer-2-only missed walls
const PARTICLE_BACKOFF: float = 0.1
const IMPACT_BACKOFF: float = 0.4
const NORMAL_PARALLEL_THRESHOLD: float = 0.99
@export var impact_enemy_hit: AudioStreamPlayer3D
@export var impact_generic: AudioStreamPlayer3D

signal queued_for_deletion(_last_pos: Vector3)

func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 1
	linear_velocity = direction * speed
	if direction != Vector3.ZERO:
		look_at(global_position + direction, Vector3.UP)
	await get_tree().create_timer(life_time).timeout
	if is_inside_tree():
		queue_free()

## Spawn this variant's impact particles (blood/dust for a bullet, scorch dust for a
## rocket). Called from _on_body_entered on every hit. Concrete subclasses implement.
@abstract func particles(_body, _last_velocity) -> void

func _on_body_entered(body):
	if _consumed:
		return
	_consumed = true
	var last_velocity := linear_velocity
	linear_velocity = Vector3.ZERO

	particles(body, last_velocity)

	if body.has_method("take_damage"):
		if !visual_only:
			var was_crit := body is Character and (body as Character).is_headshot(global_position)
			body.take_damage(damage * (headshot_multiplier if was_crit else 1.0) * (sneak_attack_multiplier if body is Character and (body as Character).is_off_guard() else 1.0), was_crit)
			if body is Character:
				# Mirror the hitscan path for projectile hits (the SMG and other short-range
				# weapons deal their damage out here, past the raycast's effective_range): the
				# victim's directional arc + the shooter's hitmarker (player flashes; enemies no-op).
				if shooter:
					(body as Character).indicate_damage_from(shooter.global_position)
					shooter.on_dealt_hit(body is Character and (body as Character).is_headshot(global_position))
				# Pitch tracks the enemy's remaining HP — deeper as they near death.
				var enemy := body as Character
				var frac := clampf(enemy.hp / maxf(enemy.max_hp, 1.0), 0.0, 1.0)
				impact_enemy_hit.reparent(get_tree().root)
				impact_enemy_hit.pitch_scale = lerpf(GameSettings.audio.enemy_hit_pitch_low_hp, GameSettings.audio.enemy_hit_pitch_full_hp, frac) * (1.5 if (body as Character).is_headshot(global_position) else 1.0)
				impact_enemy_hit.play()
				impact_enemy_hit.finished.connect(impact_enemy_hit.queue_free)
			elif not body is Interactable:
				# Interactables (crates, gibs) play their own contextual impact
				# sound via on_impact() below — skip the weapon's generic clang.
				impact_generic.reparent(get_tree().root)
				impact_generic.pitch_scale = randf_range(GameSettings.audio.impact_pitch_min, GameSettings.audio.impact_pitch_max)
				impact_generic.play()
				impact_generic.finished.connect(impact_generic.queue_free)
	else:
		_spawn_decal(last_velocity)
		if !visual_only:
			impact_generic.reparent(get_tree().root)
			impact_generic.pitch_scale = randf_range(GameSettings.audio.impact_pitch_min, GameSettings.audio.impact_pitch_max)
			impact_generic.play()
			impact_generic.finished.connect(impact_generic.queue_free)

	if not visual_only and body is RigidBody3D and not (body is Projectile):
		var rb := body as RigidBody3D
		var impulse := last_velocity.normalized() * GameSettings.physics_damage.bullet_interactable_knockback
		rb.apply_impulse(impulse, global_position - rb.global_position)
		if rb is Interactable:
			(rb as Interactable).on_impact(GameSettings.physics_damage.interactable_impact_max_velocity)

	if not visual_only:
		var hit_dir := last_velocity.normalized()
		queued_for_deletion.emit(global_position - hit_dir * IMPACT_BACKOFF)
	queue_free()

## Spawn this variant's impact decal (small bullet hole vs large scorch), oriented to
## the surface hit. Called from _on_body_entered for non-damageable bodies. Subclasses implement.
@abstract func _spawn_decal(last_velocity: Vector3) -> void


func _on_queued_for_deletion(_last_pos: Vector3) -> void:
	on_deletion()

func _orient_decal_to_normal(decal: Decal, normal: Vector3) -> void:
	var up := normal
	var z: Vector3
	if absf(up.dot(Vector3.UP)) > NORMAL_PARALLEL_THRESHOLD:
		z = Vector3.FORWARD.slide(up).normalized()
	else:
		z = Vector3.UP.slide(up).normalized()
	var x := up.cross(z).normalized()
	decal.global_transform.basis = Basis(x, up, z)

func on_deletion() -> void:
	pass
