class_name PhysicsDamageSettings
extends Resource

## The physics / damage / interaction tuning hub, grouped below. Consumed broadly:
## explosion damage (Explosion), player ram + body-check (player.gd), character-vs-
## rigidbody push (Character), the blast/recovery decay (Character.apply_blast), enemy
## knockback friction (Enemy), the pickup/throw system (PickupRay), and all
## Throwable impact/damage/destruction behaviour.

@export_group("Explosion")
@export var explosion_damage: int = 1

@export_group("Player Ram")
# Body-check damage: when the player moves faster than ram_min_speed and
# collides with an enemy, the enemy takes ram_damage + knockback. Lets the
# launch weapon (and bunnyhopping) hurt enemies on contact.
@export var ram_min_speed: float = 8.0
# Damage scales with impact speed: damage = round(speed * ram_damage_per_speed),
# floored at 1. ram_damage is kept as a legacy/minimum reference.
@export var ram_damage: int = 2
@export var ram_damage_per_speed: float = 0.35
@export var ram_knockback: float = 10.0
@export var ram_cooldown: float = 0.25

@export_group("Character Push")
# Impulse multiplier for characters (player + enemies) shoving RigidBody3D
# interactables they walk into. impulse = into_speed * this. 0 disables.
@export var character_push_force: float = 0.6

@export_group("Blast / Recovery")
@export var blast_grace_timer: float = 0.2
@export var blast_decay_rate: float = 0.05
@export var blast_min_magnitude: float = 0.1

@export_group("Enemy Movement Physics")
@export var enemy_ground_friction: float = 8.0
@export var enemy_air_friction: float = 1.0
@export var enemy_friction_min_speed: float = 0.01

@export_group("Pickup / Holding")
@export var pickup_hold_follow_rate: float = 14.0
@export var pickup_max_step_per_frame: float = 0.5
@export var pickup_hold_angular_damping: float = 0.85
@export var pickup_max_hold_distance: float = 4.0
@export var pickup_drop_impulse: float = 1.0
@export var pickup_throw_impulse: float = 12.0
@export var pickup_e_hold_threshold: float = 0.18
@export var pickup_held_collision_layer: int = 4
@export var pickup_drop_exception_delay: float = 1.0
@export var pickup_drop_lateral_nudge: float = 0.6
@export var pickup_safe_horizontal_distance: float = 1.0
@export var pickup_slide_off_impulse: float = 3.0
@export var pickup_safe_recheck_delay: float = 0.3
@export var pickup_ram_knockback_scale: float = 0.7

@export_group("Throwable / Crate")
@export var interactable_max_hp_default: int = 5
@export var interactable_impact_min_velocity: float = 1.5
@export var interactable_impact_max_velocity: float = 10.0
@export var interactable_impact_min_db: float = -24.0
@export var interactable_impact_max_db: float = 0.0
@export var interactable_impact_cooldown: float = 0.08
@export var interactable_impact_pitch_spread: float = 0.15
@export var bullet_interactable_knockback: float = 5.0
@export var interactable_damage_min_velocity: float = 6.0
@export var interactable_damage_per_m_per_s: float = 0.4
@export var interactable_damage_knockback_scale: float = 0.6
@export var interactable_damage_cooldown: float = 0.5
@export var interactable_self_damage_min_velocity: float = 5.0
@export var interactable_self_damage_per_m_per_s: float = 0.3
@export var interactable_destroy_shake_amount: float = 0.4
@export var interactable_destroy_shake_range: float = 8.0
