class_name CameraSettings
extends Resource

## Tuning for the first-person camera (CameraEffects), look/pitch (Head), and ADS zoom (ScopeIn): look
## limits + sensitivity, FOV (default/scoped plus the dynamic fall/rise/forward/sprint kicks), head-bob,
## landing-dip recovery, and strafe tilt.

@export_group("Look")
## Radians of view rotation per SCREEN pixel of mouse movement — the master look speed (the in-game slider scales this). Higher = faster aim.
## The unit is raw OS pixels (MouseInput reads InputEventMouseMotion.screen_relative, never `relative`, which the `viewport`
## stretch mode pre-scales by canvas/window width), so one value feels the same fullscreen, windowed, 1080p or 4K. The default
## is the 08-31 playtest retune: a legacy 0.0028 canvas-px feel re-expressed at 1080p fullscreen (x 792/1920 = 0.001155),
## snapped DOWN one notch onto the Options slider's step grid (SENS_MIN 0.0002 + 38 x 0.000025 = 0.00115 — Range snaps every
## value to min + n*step, so an off-grid default would move the first time the slider is touched). Retune it and
## Settings.SENS_MIN/SENS_MAX + the SettingsCatalog slider range together (Settings.read_mouse_sensitivity migrates
## a pre-switch settings.cfg by the same 792/1920 factor).
@export var mouse_sensitivity: float = 0.00115
## Normal up/down look limit (degrees) — how far the view can tilt before it clamps. 89 = just shy of straight up/down.
@export var pitch_max_deg: float = 89.0
## Degrees before the pitch limit where the look starts easing (soft ramp) instead of hitting a hard wall — bigger = a longer, mushier approach to the clamp.
@export var pitch_soft_ramp_deg: float = 25.0
## Pitch limit while wall-climbing — wider than normal so the view can crane up and over the top of the
## wall, simulating walking onto a different plane. Past 90° the look tips backward over the lip.
@export var pitch_max_climbing_deg: float = 150.0
## How fast the view reels back into range when the pitch limit CONTRACTS (a wall-climb ending — the only widening left) — higher = a snappier recentre, lower = a longer glide back.
@export var pitch_recenter_speed: float = 8.0

@export_group("FOV")
## Resting field of view (degrees) when not scoped — the ONE rest-FOV source of truth. Higher = wider, more peripheral view.
## 120 (the 08-31 defaults retune, up from the original 75) sits exactly ON Settings.FOV_MAX and the Options slider's
## ceiling — widening further means moving the clamp constants and the SettingsCatalog fov row together.
@export var default_fov: float = 120.0
## Field of view (degrees) the camera zooms to when aiming down sights (a weapon's scoped_fov_override beats this). Lower = tighter zoom.
## ONLY consulted when scope_magnification is 0 — see that field for why an ABSOLUTE ADS angle is the wrong shape.
@export var scoped_fov: float = 40.0
## ADS zoom STRENGTH, as a magnification over the player's CURRENT rest FOV: 2 = aiming brings the world twice
## as close. This is the Field-of-View-INVARIANT knob, and the one to tune. The scoped FOV is SOLVED from
## default_fov, so ADS feels the same at 75 FOV as at 120 — whereas the absolute scoped_fov above pins ADS to
## one angle, which silently STRENGTHENS the zoom every time a player widens their FOV slider (at 110 rest the
## original 40-degree scope tune is a 3.9x jump instead of the intended 2.1x, and reads as "way too far in").
## Magnification is a TANGENT ratio, not a ratio of degrees: apparent size goes with tan(fov/2), so halving the
## degrees does NOT double the apparent size. 0 = off, fall back to the absolute scoped_fov (the legacy
## behaviour). The 2.108 default is the magnification the original 75 -> 40 ADS tune worked out to — kept
## verbatim through the 08-31 default_fov retune to 120, which is exactly the drift this knob exists to absorb.
@export var scope_magnification: float = 2.108
## How fast the FOV eases in/out of the scoped zoom (higher = snappier ADS).
@export var scope_zoom_speed: float = 8.0
## Zoom change per mouse-wheel notch while a VARIABLE-zoom scope is aimed (a weapon authoring
## WeaponData.scoped_zoom_fov_min/max — the sniper): each notch MULTIPLIES / divides the scope's
## magnification by this. A TANGENT ratio like scope_magnification above — so a notch feels like the same
## step at 2x as at 40x, which stepping the FOV by flat degrees does not (1->2 degrees halves the zoom;
## 40->41 is imperceptible). <= 1.0 turns the wheel zoom off globally — the wheel then stays on the
## Hotbar's weapon switching even through a variable scope (ScopeIn.wheel_owns_scope_zoom reads this).
@export var scope_zoom_wheel_step: float = 1.25
## Extra FOV (degrees) added at full fall speed — the speed-rush widen as you plummet. 0 disables the fall kick.
@export var fall_fov_mult: float = 60.0
## Extra FOV (degrees) added at full upward speed (rocket/blast launch) — the rise kick. 0 disables it.
@export var rise_fov_mult: float = 40.0
## Extra FOV (degrees) added while pushing forward — a subtle speed-feel widen. 0 disables it.
@export var forward_fov_mult: float = 5.0
## Extra FOV (degrees) added only while the sprint/run tier is active. 0 disables the sprint widen. Stacks ON TOP
## of forward_fov_mult (that one scales with the forward push; this is a flat all-or-nothing kick off the Player's
## stamina-gated is_sprinting()), so the total forward widen is roughly the two summed.
@export var sprint_fov_mult: float = 7.0
## Air-dash FOV punch: an instant outward spike on a scoped-attack launch / air dash, eased back to the
## default FOV by fov_punch_decay (higher = snappier).
@export var dash_fov_punch: float = 40.0
## How fast the air-dash FOV punch eases back to default (higher = snappier; lower = the spike lingers).
@export var fov_punch_decay: float = 7.0
## How fast the dynamic fall/rise/forward/sprint FOV kicks ease toward their target each frame (higher = snappier FOV response).
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

@export_group("Stair Smoothing")
## How fast the view catches up to the eye height after the body auto-steps up/down a stair riser (see
## CameraEffects.step_smooth). The body snaps instantly (collision needs the exact position); this eases the
## CAMERA over that snap so climbing brush/TrenchBroom stairs glides instead of jolting the view up 0.6 m per step.
## Higher = a snappier, less floaty catch-up (0 would freeze the view mid-step — keep it well above 0); lower = a
## longer, smoother glide. ~16 catches up in ~0.15 s.
@export var step_smooth_speed: float = 16.0
## Clamp (metres) on the accumulated step-smoothing offset, so running up a whole staircase (many risers firing in
## quick succession) reads as one continuous rise without the view ever sinking far enough below eye level to look
## like a crouch or clip through the floor. Roughly the player's step_up_height is a sensible ceiling.
@export var step_smooth_max: float = 0.7

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

@export_group("Dialogue Camera")
## Seconds to swing the camera onto a dialogue target when a conversation starts — higher = a slower, lazier pan.
@export var dialogue_focus_duration: float = 0.4
## World-space vertical extent (metres) the dialogue zoom frames — the FOV narrows so a target this tall fills the view at any range. Bigger = a wider (less zoomed) framing.
@export var dialogue_frame_height: float = 3.0
## FOV floor (degrees) for the dialogue zoom, so a distant target doesn't zoom to a pinhole. Higher = a wider minimum framing.
@export var dialogue_min_fov: float = 25.0
## Yaw bias (degrees) the focus swing under-rotates by. 0 (the default) = the speaker frames DEAD CENTRE,
## the classic conversation framing — the person you talk to is the shot. Positive pushes them right of
## centre, clearing the dialogue UI's response rows off the face at the cost of the centred composition;
## it was shipped at 9 on 08-24 and reverted the same day (the off-centre speaker read as "out of focus").
## Composition is a windowed-QA-shot judgement, not a unit-testable number.
@export var dialogue_frame_offset_deg: float = 0.0

@export_group("Lens")
## Barrel (fisheye) bend of the WHOLE rendered frame at full strength — the centre magnified, the periphery
## squeezed, straight lines off the centre bowing outward. This is the number the player's Accessibility "Lens
## Curve" slider scales, and it is read as CENTRE MAGNIFICATION MINUS ONE: 0.12 = the middle of the frame reads
## ~12% bigger, with the CORNERS PINNED (post_process.gdshader normalises the bend by the corner, so the frame
## never shows a black edge at any strength). 0 = a perfectly flat frame.
##
## It is a screen-space warp, NOT a projection change: no Camera3D property can bow a straight line (FOV is a
## uniform scale on the image — see the note on CameraEffects.base_fov), which is why this lives in the
## post-process rather than on the camera. It reads strongest at a wide field of view, because there is more
## off-axis frame for it to bend.
@export var lens_barrel_amount: float = 0.12
## Lens fringe (chromatic aberration) as a FRACTION OF THE BEND, so it grows with the curve and vanishes with it
## instead of sitting on a flat frame as a colour error. This is what makes the warp read as GLASS rather than as
## a wobble. 0 = off; ~0.35 is a subtle edge fringe; 1.0 is a strong one. Costs two extra screen taps when on.
@export var lens_chroma_amount: float = 0.35

## Where the barrel lens DISPLAYS a screen point the 3D pass rendered at `p` (canvas units; `canvas` = the
## logical viewport size the caller draws in). The lens is a POST warp: it bends the PICTURE only, while
## HUD annotations placed from Camera3D.unproject_position (sniper glints, compass world markers, the sky
## title's overlay) draw ABOVE it — so at any bend > 0 an annotation detaches from the object it marks by
## the warp displacement. That gap always existed, but RETRO's chunky nearest-upscale mushed it into the
## blob; a native-res HIGH FIDELITY frame shows it plainly at range (reported 2026-08-25 as "the sniper
## glint is completely misaligned" — measured at ~4-8 px mid-radius with the shipped 0.12 bend, identical
## in BOTH presentation modes, zero with the lens off). Callers pass their point through this before
## drawing.
##
## The math is the exact INVERSE of post_process.gdshader's lens_warp(), which maps an OUTPUT uv to the
## SOURCE uv it fetches (radius factor (1 + k*r2n)/(1 + k), corners pinned): given the SOURCE radius,
## solve for the OUTPUT radius — monotonic over the whole dial (f' > 0), so four Newton steps from o = s
## land sub-pixel. STATIC + pure so it is assertable off-tree and free of autoload reads:
##  - `render_aspect` must be the RENDER target's aspect (Settings.render_size().x / .y), matching the
##    shader's SCREEN_PIXEL_SIZE ratio — the logical canvas aspect is ~0.3% off it under canvas_items'
##    floored size-2d override.
##  - `k` is the LIVE bend the shader was pushed: lens_barrel_amount * Settings.lens_curve — the same
##    product player.gd's poll writes as `lens_barrel`. k == 0 returns `p` untouched, so callers pass it
##    unconditionally instead of branching.
static func lens_display_point(p: Vector2, canvas: Vector2, render_aspect: float, k: float) -> Vector2:
	if k == 0.0 or canvas.x <= 0.0 or canvas.y <= 0.0:
		return p
	var c := (p / canvas) * 2.0 - Vector2.ONE
	c.x *= render_aspect
	var r2_corner := render_aspect * render_aspect + 1.0
	var s := c.length()
	if s < 0.0001:
		return p  # dead centre never moves (and the Newton scale below would divide by ~0)
	var o := s
	for i in 4:
		var f := o * (1.0 + k * o * o / r2_corner) / (1.0 + k) - s
		var fp := (1.0 + 3.0 * k * o * o / r2_corner) / (1.0 + k)
		o -= f / fp
	c *= o / s
	c.x /= render_aspect
	return (c + Vector2.ONE) * 0.5 * canvas
