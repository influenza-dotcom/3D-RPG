class_name WeaponData
extends Resource

## A weapon definition — every knob the firing pipeline reads. Make a new weapon by creating a WeaponData
## .tres and filling these in; the @export_groups below are how they're laid out in the Inspector.

@export_group("General")
@export var effective_range: float = 20.0
## When true the weapon uses raycast (hitscan) damage; when false it spawns a projectile_scene instance.
## Existing weapons stay at the default false to keep projectile behaviour unless explicitly opted in.
@export var use_hitscan: bool = false
## Movement-speed multiplier applied to the wielder WHILE THIS WEAPON IS DRAWN (not holstered).
## 1.0 = no penalty; a heavier weapon sets this lower (e.g. 0.8) to slow the holder down, FNV-style.
@export var move_speed_multiplier: float = 1.0

@export_group("Damage")
@export var damage: float = 1.0
## Damage multiplier when a shot lands in a target's head zone (see Character.head_local_y).
@export var headshot_multiplier: float = 2.0
## Damage multiplier for a sneak attack — hitting an enemy that hasn't noticed you yet (not ALERTED).
## Stacks with headshot_multiplier, so a stealth headshot is multiplier x multiplier.
@export var sneak_attack_multiplier: float = 2.0
## When a shot deals MORE damage than the victim's remaining HP, the excess "overkill" pierces through
## and carries on to hit whoever's behind them (hitscan + projectiles). Default on. The overkill passes
## through as flat damage (no re-applied crit/sneak multipliers).
@export var overkill_penetration: bool = true

@export_group("Firing")
@export var pellet_count: int = 1
@export var pellet_spread: float = .1
@export var auto_fire: bool = true # hold to keep firing? false = one attack per click (semi-auto)
## Wind-up delay (seconds) between the click and the swing actually landing, for weight. 0 = instant
## (the default for all ranged weapons).
@export var attack_windup: float = 0.0
@export var attack_speed: float = 0.1

@export_group("Ammo & Reload")
@export var max_ammo: int = 10
## Ammo caliber this weapon draws from the wielder's reserve on reload (e.g. &"9mm"). Weapons that share
## a caliber share reserve ammo (pistol + SMG = 9mm). EMPTY = no reserve: the clip refills for free on
## reload (melee / rock / spray paint). The player can only reload a calibered weapon if the backpack
## holds matching ammo.
@export var caliber: StringName = &""
@export var auto_reload: bool = false # automatically start a reload the instant a shot empties the clip?
@export var reload_time: float = 1.5

@export_group("Projectile")
@export var projectile_scene: PackedScene
@export var projectile_speed: float = 80.0
@export var projectile_life_time: float = 10.0
@export var bullet_gravity_scale: float = 0.1
@export var launch_angle: float = 0.0
@export var has_tracer: bool = false # spawn a brief tracer mesh (bullet material) from the muzzle to the shot point?

@export_group("Explosion")
@export var max_explosion_force: float = 20.0
@export var explosion_radius: float = 4.0

@export_group("Knockback")
@export var self_knockback: float = 0.0
@export var enemy_knockback: float = 5.0
@export var enemy_lift: float = 0.0

@export_group("View Model")
## This weapon's first-person view-model scene (e.g. ak_472.tscn). The gun rig instantiates it on equip
## so each weapon shows its own mesh + material. Unset = the rig's built-in placeholder shows.
@export var view_model: PackedScene
@export var hand_mesh: Mesh

@export_group("Muzzle & Casing")
@export var has_muzzle_flash: bool = true # show the muzzle flash mesh/light + sparks on fire?
@export var has_laser_sight: bool = true # show the laser sight for this weapon?
@export var spawns_casing: bool = true   # eject a shell casing on fire?
## Scales the ejected shell casing — its mesh (and the RigidBody casing's collision). 1.0 = unchanged;
## > 1 = a bigger shell (e.g. the sniper's fat round), < 1 = a daintier one. Only matters when
## spawns_casing is true.
@export var casing_size_scale: float = 1.0

@export_group("Audio")
@export var audio: AudioStream          # gunshot / fire sound
@export var whiz_sound: AudioStream     # per-shot bullet snap/whiz played at the muzzle
@export var impact_sound: AudioStream        # hit on world/objects (null = scene default)
@export var impact_enemy_sound: AudioStream  # hit on a character (null = scene default)
@export var reload_sound: AudioStream        # reload sfx (null = scene default ReloadSFX stream)

@export_group("Feedback")
@export var screen_shake_amount: float = 0.3
## Bigger one-shot shake for a scoped-attack launch / air dash specifically (screen_shake_amount stays
## the per-shot fire shake).
@export var launch_screen_shake: float = 0.6
## Hitstop ("screen freeze") when this weapon hits an enemy — a brief slow-mo for punch. hitstop_duration
## = real-time hold; hitstop_recovery = how long it eases back to full speed. Set both low (or 0) on a
## fast weapon like the SMG so the per-shot freezes don't pile up.
@export var hitstop_duration: float = 0.005
@export var hitstop_recovery: float = 0.2

@export_group("ADS / Scope")
## scoped_fov_override: FOV this weapon zooms to while scoped (ADS). 0.0 = use GameSettings.camera.scoped_fov;
## > 0.0 = this weapon's own scope FOV (a sniper sets a deep, narrow value).
@export var scoped_fov_override: float = 0.0
## When true the camera's depth-of-field blur is turned OFF while scoped (a clear, crisp scope picture);
## when false, scoping merely LESSENS the DoF.
@export var disable_dof_while_scoped: bool = false

@export_group("Scoped-Attack Launch")
## When true, ATTACKING WHILE SCOPED (ADS) launches the player in the look direction instead of doing a
## normal attack (e.g. melee dash). Hip-fire still does the normal attack; you still zoom with the
## secondary as usual. Uses the weapon's attack_speed as the launch cooldown.
@export var launch_on_scoped_attack: bool = false
@export var launch_force: float = 15.0
@export var launch_upward: float = 4.0
@export var single_air_dash: bool = false # if true, only one launch/dash allowed per airtime

@export_group("Spray Paint")
## Spray-paint "graffiti" mode: hold fire to spray persistent coloured paint decals onto whatever surface
## you aim at, instead of dealing damage. Pair with auto_fire = true + a fast attack_speed.
@export var is_spray_paint: bool = false
## Tag colours the spray cycles through at random (one per splat). Edit freely.
@export var paint_colors: Array[Color] = [
	Color(0.92, 0.12, 0.15), Color(0.13, 0.45, 0.95), Color(0.18, 0.85, 0.22),
	Color(0.97, 0.85, 0.12), Color(0.93, 0.22, 0.82), Color(0.12, 0.9, 0.9),
]
