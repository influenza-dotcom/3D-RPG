class_name WeaponData
extends Resource

@export var effective_range: float = 20.0
@export var damage: int = 1
@export var projectile_scene: PackedScene
@export var hand_mesh: Mesh
@export var projectile_life_time: float = 10.0
@export var projectile_speed: float = 80.0

@export var max_ammo: int = 10

@export var bullet_gravity_scale: float = 0.1
@export var launch_angle: float = 0.0

@export var max_explosion_force: float = 20.0
@export var explosion_radius: float = 4.0

@export var pellet_count: int = 1
@export var pellet_spread: float = .1

@export var audio: AudioStream          # gunshot / fire sound
@export var whiz_sound: AudioStream     # per-shot bullet snap/whiz played at the muzzle
@export var impact_sound: AudioStream        # hit on world/objects (null = scene default)
@export var impact_enemy_sound: AudioStream  # hit on a character (null = scene default)

@export var spawns_casing: bool = true   # eject a shell casing on fire?
@export var has_muzzle_flash: bool = true # show the muzzle flash mesh/light + sparks on fire?
@export var has_laser_sight: bool = true # show the laser sight for this weapon?
@export var auto_fire: bool = true # hold to keep firing? false = one attack per click (semi-auto)
@export var single_air_dash: bool = false # if true, only one launch/dash allowed per airtime

# When true, ATTACKING WHILE SCOPED (ADS) launches the player in the look
# direction instead of doing a normal attack (e.g. melee dash). Hip-fire still
# does the normal attack; you still zoom with the secondary as usual. Uses the
# weapon's attack_speed as the launch cooldown.
@export var launch_on_scoped_attack: bool = false
@export var launch_force: float = 15.0
@export var launch_upward: float = 4.0

# Wind-up delay (seconds) between the click and the swing actually landing, for
# weight. 0 = instant (the default for all ranged weapons).
@export var attack_windup: float = 0.0
@export var attack_speed: float = 0.1
@export var reload_time: float = 1.5

@export var self_knockback: float = 0.0
@export var enemy_knockback: float = 5.0
@export var enemy_lift: float = 0.0

@export var screen_shake_amount: float = 0.3

# When true the weapon uses raycast (hitscan) damage; when false, spawn a
# projectile_scene instance. Existing weapons left at default `false` to
# preserve the current projectile-based behavior unless explicitly opted in.
@export var use_hitscan: bool = false
