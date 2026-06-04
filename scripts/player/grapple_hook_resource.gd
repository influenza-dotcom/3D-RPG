class_name GrappleHookResource
extends Resource

## One-stop config for the player's grapple hook. Assign a .tres of this on the Player
## (grapple_resource) to tune the rope, the hook-tip sprite, the SFX, and the feel without touching
## code — the grapple reads it on creation. Any field left at its default keeps the built-in behaviour.

@export_group("Hook tip")
## Texture for the Sprite3D that rides the fired hook's tip. Null = no sprite shown.
@export var hook_texture: Texture2D
@export var hook_pixel_size: float = 0.01  ## world metres per texture pixel

@export_group("Rope")
@export var rope_color: Color = Color(1.0, 1.0, 1.0, 1.0)
## Optional rope texture, tiled ALONG the rope's length. Null = flat rope_color.
@export var rope_texture: Texture2D
@export var rope_texture_tiles_per_meter: float = 4.0

@export_group("SFX")
## Played (2D) the instant the hook is fired.
@export var launch_sfx: AudioStream
## Played (positional, at the hit point) when the hook attaches to WORLD geometry — a tether anchor
## or a non-enemy RigidBody. Enemy hits use hit_enemy_sfx instead (falls back to this if that's null).
@export var hit_sfx: AudioStream
## Played (positional, at the hit point) when the hook catches / yanks a Character (an enemy). Null =
## fall back to hit_sfx. Optional.
@export var hit_enemy_sfx: AudioStream
## Played (2D) when a shot MISSES — flies to max range having caught nothing and retracts. Null =
## fall back to detach_sfx. Optional.
@export var miss_sfx: AudioStream
## Played (2D) when the rope lets go — a deliberate release of a caught grapple. Optional.
@export var detach_sfx: AudioStream
@export var sfx_volume_db: float = 0.0

@export_group("Tuning")
@export var max_range: float = 30.0
@export var hook_speed: float = 80.0   ## how fast the hook head flies out (m/s)
@export var pull_delay: float = 0.1    ## momentum hold-off after the hook catches
@export var release_launch: float = 12.0  ## extra speed flung toward where you're aiming when you RELEASE a swing
@export var break_distance: float = 45.0  ## force the hook to retract if the player gets this far from the hook point
