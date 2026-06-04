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
## Volume (dB) the impact one-shots play at when an NPC fired the round. The .tscn authors them very
## loud (volume_db 80) so a PLAYER hit reads as always-audible feedback at any range; at that level the
## AudioStreamPlayer3D distance falloff is saturated, so a distant NPC's impact blasts the player like
## a flat 2D sound. NPC-fired impacts drop to this so the 3D attenuation actually applies.
const NPC_IMPACT_VOLUME_DB: float = 0.0
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
	# The shooter can be freed mid-flight (e.g. the enemy that fired this died before the shot landed).
	# A freed reference passed to take_damage() errors, so collapse it to null = an unattributed hit.
	if not is_instance_valid(shooter):
		shooter = null
	var last_velocity := linear_velocity
	linear_velocity = Vector3.ZERO

	particles(body, last_velocity)

	if body.has_method("take_damage"):
		if !visual_only:
			var was_crit := body is Character and (body as Character).is_headshot(global_position)
			# Player is immune to headshots from NPCs (no cheap one-shots): an NPC-fired round on the
			# player ignores the crit multiplier. Player shots + NPC-vs-NPC crits are unaffected.
			if was_crit and (body as Character).is_in_group(&"Player") and not (shooter and shooter.is_in_group(&"Player")):
				was_crit = false
			body.take_damage(damage * (headshot_multiplier if was_crit else 1.0) * (sneak_attack_multiplier if body is Character and (body as Character).is_off_guard() else 1.0), was_crit, shooter)
			if body is Character:
				# Mirror the hitscan path for projectile hits (the SMG and other short-range
				# weapons deal their damage out here, past the raycast's effective_range): the
				# victim's directional arc + the shooter's hitmarker (player flashes; enemies no-op).
				if shooter:
					(body as Character).indicate_damage_from(shooter.global_position, shooter)
					shooter.on_dealt_hit(body is Character and (body as Character).is_headshot(global_position), clampf((body as Character).hp / maxf((body as Character).max_hp, 1.0), 0.0, 1.0))
				# Pitch tracks the enemy's remaining HP — deeper as they near death.
				var enemy := body as Character
				var frac := clampf(enemy.hp / maxf(enemy.max_hp, 1.0), 0.0, 1.0)
				var hit_pitch := lerpf(GameSettings.audio.enemy_hit_pitch_low_hp, GameSettings.audio.enemy_hit_pitch_full_hp, frac) * (1.5 if (body as Character).is_headshot(global_position) else 1.0)
				# The player ALSO hears the per-weapon impact-against-a-character (impact_enemy_hit /
				# impact_enemy_sound), HP-pitched, alongside the 2D ding from on_dealt_hit; an NPC-fired
				# round plays the positional generic impact instead (no ding for a distant NPC-vs-NPC trade).
				if shooter and shooter.is_in_group(&"Player"):
					_emit_impact(impact_enemy_hit, hit_pitch)
				else:
					_emit_impact(impact_generic, hit_pitch)
			elif not body is Interactable:
				# Interactables (crates, gibs) play their own contextual impact
				# sound via on_impact() below — skip the weapon's generic clang.
				_emit_impact(impact_generic, randf_range(GameSettings.audio.impact_pitch_min, GameSettings.audio.impact_pitch_max))
	else:
		_spawn_decal(last_velocity)
		if !visual_only:
			_emit_impact(impact_generic, randf_range(GameSettings.audio.impact_pitch_min, GameSettings.audio.impact_pitch_max))

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

## Play an impact one-shot at the hit point, reparented to the tree root so it outlives the
## projectile's queue_free. For an NPC-fired round the volume drops to NPC_IMPACT_VOLUME_DB so the 3D
## distance attenuation applies (the nodes are authored very loud for always-audible PLAYER feedback,
## which from a distant NPC reads as a flat 2D blast); the player's own shots keep the authored volume.
func _emit_impact(sfx: AudioStreamPlayer3D, pitch: float) -> void:
	sfx.reparent(get_tree().root)
	sfx.pitch_scale = pitch
	if not (shooter and shooter.is_in_group(&"Player")):
		sfx.volume_db = NPC_IMPACT_VOLUME_DB
	sfx.play()
	sfx.finished.connect(sfx.queue_free)
