class_name CameraSettings
extends Resource

## Tuning for the first-person camera (CameraEffects), look/pitch (Head), and ADS zoom (ScopeIn): look
## limits + sensitivity, FOV (default/scoped plus the dynamic fall/rise/forward kicks), head-bob,
## landing-dip recovery, and strafe tilt.

@export_group("Look")
## Radians of view rotation per pixel of mouse movement — the master look speed (the in-game slider scales this). Higher = faster aim.
@export var mouse_sensitivity: float = 0.002
## Normal up/down look limit (degrees) — how far the view can tilt before it clamps. 89 = just shy of straight up/down.
@export var pitch_max_deg: float = 89.0
## Tighter pitch limit (degrees) while HOLDING a pickup, so a carried object stays in frame instead of swinging past the camera.
@export var pitch_max_holding_deg: float = 30.0
## Degrees before the pitch limit where the look starts easing (soft ramp) instead of hitting a hard wall — bigger = a longer, mushier approach to the clamp.
@export var pitch_soft_ramp_deg: float = 25.0
## Pitch limit while wall-climbing — wider than normal so the view can crane up and over the top of the
## wall, simulating walking onto a different plane. Past 90° the look tips backward over the lip.
@export var pitch_max_climbing_deg: float = 150.0
## How fast the view reels back into range when the pitch limit CONTRACTS (climb ended / picked up an object) — higher = a snappier recentre, lower = a longer glide back.
@export var pitch_recenter_speed: float = 8.0

@export_group("FOV")
## Resting field of view (degrees) when not scoped — the ONE rest-FOV source of truth. Higher = wider, more peripheral view.
@export var default_fov: float = 75.0
## Field of view (degrees) the camera zooms to when aiming down sights (a weapon's scoped_fov_override beats this). Lower = tighter zoom.
@export var scoped_fov: float = 40.0
## How fast the FOV eases in/out of the scoped zoom (higher = snappier ADS).
@export var scope_zoom_speed: float = 8.0
## Extra FOV (degrees) added at full fall speed — the speed-rush widen as you plummet. 0 disables the fall kick.
@export var fall_fov_mult: float = 60.0
## Extra FOV (degrees) added at full upward speed (rocket/blast launch) — the rise kick. 0 disables it.
@export var rise_fov_mult: float = 40.0
## Extra FOV (degrees) added while pushing forward — a subtle speed-feel widen. 0 disables it.
@export var forward_fov_mult: float = 5.0
## Air-dash FOV punch: an instant outward spike on a scoped-attack launch / air dash, eased back to the
## default FOV by fov_punch_decay (higher = snappier).
@export var dash_fov_punch: float = 40.0
## How fast the air-dash FOV punch eases back to default (higher = snappier; lower = the spike lingers).
@export var fov_punch_decay: float = 7.0
## How fast the dynamic fall/rise/forward FOV kicks ease toward their target each frame (higher = snappier FOV response).
@export var fov_lerp_speed: float = 5.0

@export_group("Head Bob")
## Bob cadence — how fast the head bobs while moving (higher = quicker steps). Scales with speed.
@export var bob_speed: float = 8.0
## Bob travel — peak vertical head sway (metres) at full speed. 0 disables head bob.
@export var bob_amount: float = 0.015
## Horizontal-to-vertical bob ratio — the side-sway as a fraction of the vertical bob, making a figure-8 sway. Higher = a wider side-to-side roll.
@export var bob_horizontal_ratio: float = 0.5
## Planar speed (m/s) below which the bob eases out to rest — the near-still threshold so a creep doesn't bob. Higher = stops bobbing sooner.
@export var bob_min_speed: float = 0.1

@export_group("Landing Dip")
## How far (metres) the camera dips down on a full-force landing — scaled by impact strength. Bigger = more dramatic thud.
@export var land_impact: float = 1.0
## How fast the camera springs back up from the landing dip and settles bob (higher = snappier recovery).
@export var recovery_speed: float = 10.0

@export_group("Strafe Tilt")
## Camera roll (radians) when strafing sideways — the lean into the turn. 0 = no tilt (also toggleable in accessibility settings).
@export var tilt_amount: float = 0.1
## How fast the view eases into/out of the strafe tilt (higher = snappier lean).
@export var tilt_speed: float = 3.0

@export_group("Scope (ADS)")
## Far depth-of-field blur distance (metres) while scoped — pushed out from the hip-fire default so the scoped view reads crisp. Bigger = the world stays sharp further out.
@export var dof_scoped_far_distance: float = 120.0
## Volumetric-fog density multiplier while scoped with a crisp-scope (DoF-disabling) weapon, e.g. the sniper — thins the fog so the target isn't a grey blob. Lower = clearer scope; 1.0 = no thinning.
@export var scoped_fog_density_factor: float = 0.3
## How far the music bus drops (dB) while scoped — a slight quieting for a focused feel (mirrors the dialogue duck). More negative = quieter.
@export var scope_music_duck_db: float = -6.0
## Fade time (seconds) for the scope music duck in/out — higher = a slower, smoother dip.
@export var scope_music_duck_time: float = 0.25
