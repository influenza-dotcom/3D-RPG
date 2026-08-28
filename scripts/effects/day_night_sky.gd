class_name DayNightSky
extends Node

## Drop-in DAY/NIGHT driver — the VISUAL half of the WorldClock. Reads `WorldClock.time_of_day` each frame.
##
## ⭐⭐THE AUTHORED LOOK IS THE RESTING STATE. A bare DayNightSky changes NOTHING about how the level's day
## looks: the sun keeps its AUTHORED direction, colour and noon energy, the sky material is untouched, and the
## ambient holds its authored value — at noon the level is BYTE-IDENTICAL to the scene with no component. What
## the bare node adds is ONLY the night: sun energy and ambient ease down after dusk, the sun goes fully off
## below the horizon, and the level runs on its fixtures and sky until dawn. A designer's manicured aesthetic
## is the anchor the cycle returns to every day — never something the component repaints with its own taste
## (that mistake shipped once and was reverted the same day).
##
## The cinematic extras are OPT-IN, each its own knob, all defaulting OFF or to "authored":
##  * `drive_sun_rotation` — arc the sun across the sky (horizon at dawn -> `max_sun_pitch_deg` at noon), with
##    a yaw sweep so shadows move. Also engages `high_sun_fog_scale` (see that knob's washout note).
##  * `sun_color_gradient` — colour-ramp the sun over the day (night blue -> dawn amber -> ...). Null = the
##    sun keeps its AUTHORED colour at every hour.
##  * `drive_sky` — day-brighten the StarSky horizon sky via the shader's EXISTING uniforms (`zenith_color`,
##    `horizon_color`, `sun_glow`, `sun_azimuth`) — parameter writes only, never a shader edit or sky swap, so
##    StarSky keeps sole ownership of the material + the kill `flash`. Off = the authored sky holds 24/7.
##  * `dawn_time` / `dusk_time` / `full_brightness_elevation` — WHEN the day is: the horizon crossings and how
##    hard daylight plateaus between them. Defaults (0.25 / 0.75 / 1.0) are the original 6am..6pm raw sinusoid.
##
## ⭐NIGHT IS A STEALTH BUFF, automatically: PlayerLightLevel adds a DirectionalLight's raw energy globally, so
## dropping the key light from the sun's authored energy to the moon's fraction of it drops the player's light
## exposure by the same ratio — darkness-stealth engages at night with zero extra wiring. (It is the moon's
## ENERGY that does this, not the light switching off: with a moon the sun node stays visible all night.
## `moon_energy_scale = 0` restores the fully-dark, fully-hidden night.) Streetlamps still count; give a MyLight
## fixture `night_only` to douse it by day, and the player's own flashlight lights them up while it is on.
##
## SETUP: drop a DayNightSky node anywhere in the level (the main level authors one beside its sun). It
## auto-finds the sun (first DirectionalLight3D under its own scene) and the WorldEnvironment (group
## "world_environment"); point `sun` / `world_environment` explicitly to override. Inert (warns once) if there
## is no sun to drive. To watch a full cycle fast, drop `WorldClock.day_length_seconds` to e.g. 30.

@export_group("Sun")
## The sun to drive. Null -> auto-find the first DirectionalLight3D under this node's own scene at _ready.
@export var sun: DirectionalLight3D
## time_of_day fraction the sun RISES (crosses the horizon upward). 0.25 = 6am on the HUD clock.
@export var dawn_time: float = 0.25
## time_of_day fraction the sun SETS. ⭐The default 0.75 (6pm) reproduces the original hard-coded sinusoid; the
## main level authors 0.8333 (8pm) because a 6pm blackout read as "way too dark by 4-5pm" — with the raw sine,
## brightness was already halved by 4pm. Everything rides this window together (energy, ambient, sky, the arc,
## the moon handover), so the horizon crossing and the light always agree. NOT the WorldClock phase boundary:
## `WorldClock.night_start` (schedules, night_only fixtures) is its own GAMEPLAY knob — it now ships at the same
## 0.8333 so lamps and schedules flip at full dark, but set it earlier than dusk_time if you want streetlights
## burning through the dusk fade.
@export var dusk_time: float = 0.75
## Sun elevation (fraction of the noon peak, 0..1) at which daylight SATURATES to full brightness. 1.0 (the
## default) = the original raw sinusoid: brightness tracks elevation all day, so the light starts dying right
## after noon. Lower it and the day PLATEAUS — full authored brightness while the sun is above this elevation,
## with the whole fade to dark compressed into the twilight band just after dawn / before dusk (the main level
## authors 0.35). ⭐Clamped to at most 1.0 live: a higher value would dim NOON below the authored peak and
## quietly break the "bare drop-in keeps the authored noon" contract.
@export var full_brightness_elevation: float = 1.0
## OPT-IN: arc the sun's ORIENTATION (pitch + a gentle yaw sweep) across the day. ⭐OFF (default) = the sun
## holds its AUTHORED direction — the level's manicured key-light angle — and only energy/colour/visibility
## animate. Turning this on also engages high_sun_fog_scale (the climbing sun's washout guard). At night the
## arc hands the orientation back to the AUTHORED rake (the moon's angle) over the dusk crossfade — the raw
## arc would otherwise shine UP from below the horizon all night.
@export var drive_sun_rotation: bool = false
## Sun light energy at high noon. ⭐0 (the default) = use the sun's AUTHORED light_energy as the peak, so the
## bare drop-in keeps the level's authored noon brightness. Set explicitly to retune the whole day's scale.
@export var peak_sun_energy: float = 0.0
## OPTIONAL energy shape over time_of_day (0..1) — sampled for the 0..1 day factor, REPLACING the built-in
## dawn/dusk-window shape entirely (dawn_time / dusk_time / full_brightness_elevation are ignored while a curve
## is authored). ⭐A curve that stays > 0 past the sun's horizon crossing breaks the day>0 ⇔ elev>0 invariant
## the arc's never-points-up handover rests on — keep an authored curve at 0 wherever the sun is down.
@export var sun_energy_curve: Curve
## OPTIONAL sun colour over time_of_day (0..1). ⭐Null (default) -> the sun keeps its AUTHORED colour at every
## hour (the manicured look). Author a Gradient to colour-ramp the day instead — e.g. offsets 0/.25/.5/.75/1
## with night blue (.35,.45,.7) -> dawn amber (1,.65,.35) -> warm noon (.78,.76,.7) -> dusk amber -> night blue.
@export var sun_color_gradient: Gradient

@export_group("Moon")
## ⭐THE NIGHT KEY LIGHT. Fraction of the sun's AUTHORED energy the same DirectionalLight keeps once the sun is
## down — a moon, reusing the sun rather than needing a second authored light. 0 = the old pitch-black night
## (the light switches off entirely below the horizon).
##
## WHY THIS EXISTS: with the sun off, a night lit by flat ambient alone has NO DIRECTION — every surface reads
## the same value, so walls, kerbs and stairs vanish into one dark mass and the street becomes unreadable. A
## dim directional restores the SHAPE (edges, falloff, a sense of where light comes from) at a fraction of the
## brightness. Kept on the sun's authored direction, so the moon lights your composition the same way the sun
## does — the manicured key angle survives the night.
@export var moon_energy_scale: float = 0.2
## Colour of that night key light. Cool blue-white by default — moonlight reads as the sun's cold echo.
@export var moon_color: Color = Color(0.55, 0.65, 0.95)
## Fraction of the sun's authored VOLUMETRIC FOG energy the moon keeps. Low: a moon that pushed the same fog
## energy as the sun would glow the night haze into a grey soup and swallow the neon.
@export var moon_fog_scale: float = 0.25
## Steepest pitch (deg) the sun reaches at noon. ⭐Deliberately NOT 90: at a true overhead noon, vertical
## facades receive grazing-incidence ~nothing and a canyon city goes DARK at midday (probe-verified) — capping
## the arc keeps walls lit at noon while dawn/dusk still hit the horizon. 90 = a physically overhead noon.
@export var max_sun_pitch_deg: float = 58.0
## Compass yaw (deg) the sun's arc centres on at noon; the sweep below rotates it east->west across the day.
@export var sun_yaw_deg: float = 35.0
## Degrees the sun's yaw sweeps over a full day (a moving shadow direction). 0 = fixed compass yaw.
@export var sun_sweep_deg: float = 120.0
## Fraction of the sun's AUTHORED light_volumetric_fog_energy left when the sun is OVERHEAD (elevation 1).
## ⭐The washout guard: the main level tunes fog energy 2.519 for a GRAZING sun, whose fog contribution the
## buildings mostly shadow — an overhead noon sun reaches into every street canyon and at full authored energy
## saturates the volumetric fog to a white sheet (probe-verified). Grazing keeps the authored value; overhead
## scales toward this. 1.0 = off.
@export var high_sun_fog_scale: float = 0.12

@export_group("Ambient")
## Also scale the WorldEnvironment's ambient ENERGY with the day factor, so night is darker than noon.
## StarSky's pinned ambient COLOUR is left alone — this touches energy only.
@export var drive_ambient: bool = true
## The WorldEnvironment whose ambient energy to scale. Null -> auto-find via group "world_environment".
@export var world_environment: WorldEnvironment
## Fraction of the AUTHORED ambient energy at high noon. 1.0 = noon keeps the authored look exactly.
@export var ambient_day_scale: float = 1.0
## Fraction of the AUTHORED ambient energy at deep night. ⭐Ships at 1.0 — night keeps the level's full authored
## ambient, so `drive_ambient` is effectively inert until you lower this. That is deliberate: DIMMING THE
## AMBIENT IS THE WRONG DIAL FOR NIGHT. Ambient is flat, so cutting it removes brightness without adding any
## shape and the street just turns into an unreadable dark mass (0.35 shipped for a day and read as "way too
## dark"). The moon above is what makes night feel like night — a dim DIRECTIONAL that keeps edges and falloff.
## Lower this only if you want night darker AFTER the moon is already tuned.
@export var ambient_night_scale: float = 1.0

@export_group("Sky")
## OPT-IN: drive the StarSky horizon-sky's gradient uniforms with the day factor (day-blue zenith/horizon by
## day, the shader's authored night look by night, the hazy sun-glow tracking the real sun). ⭐OFF (default) =
## the authored horizon sky holds 24/7 — the moody look IS the aesthetic, day and night. Skipped gracefully
## when the live sky isn't the horizon shader (StarSky absent / a custom sky).
@export var drive_sky: bool = false
## Sky colour straight up at high noon (lerps to `sky_night_zenith` by night).
@export var sky_day_zenith: Color = Color(0.21, 0.34, 0.55)
## Sky colour at the horizon at high noon (lerps to `sky_night_horizon` by night).
@export var sky_day_horizon: Color = Color(0.5, 0.62, 0.74)
## Night zenith/horizon — defaults mirror horizon_sky.gdshader's authored uniforms, so an untouched night looks
## exactly like the pre-cycle sky. (Captured as exports, not read from the material: a ShaderMaterial only
## reports uniforms something has SET, so the shader's own defaults are not readable at runtime.)
## ⭐PROBE-CONFIRMED: a Color written to a `source_color` uniform via set_shader_parameter is NOT sRGB-converted
## — it lands exactly as typed, matching the shader's own vec3 literal. (Pre-compensating these to linear was
## tried and moved 30% of night sky pixels; copying the literals verbatim is correct.) Only a literal declared
## in SHADER SOURCE versus a picked Inspector Color can diverge — see horizon_sky.gdshader's tone defaults.
@export var sky_night_zenith: Color = Color(0.015, 0.025, 0.055)
@export var sky_night_horizon: Color = Color(0.06, 0.11, 0.16)
## The horizon shader's hazy sun-glow strength at HIGH NOON (its `sun_glow` uniform). ⭐Lowered from the
## shader's authored 0.5 because that amber lobe is a DUSK read: `haze_color` is sunset amber and the lobe is
## pinned to the horizon whatever the sun's real elevation, so at noon it painted a sunset across the horizon
## band no matter how blue the zenith got (probe-measured: the lobe alone moved the sky by mean 0.151 /
## max 0.475). The NIGHT keeps the authored 0.5 — see below.
@export var sky_sun_glow: float = 0.12
## ⭐⭐THE AUTHORED NIGHT VALUES THE GLOW AND ITS BEARING RETURN TO, mirroring horizon_sky.gdshader's own
## defaults so that day 0 is the authored night EXACTLY. Scaling the glow by `day` alone (what this used to do)
## drove it to 0 at midnight and snapped the azimuth onto the arc's yaw — which changed 100% of night sky
## pixels by up to 82/255. That is the "authored look is the resting state" contract broken by the very knob
## that promises it. Holding both here measured 0 of 131072 sky pixels different from the untouched night.
@export var sky_night_sun_glow: float = 0.5
@export var sky_night_sun_azimuth: float = 0.7

var _env: WorldEnvironment = null
var _warned: bool = false
var _authored_sun_energy: float = 1.0        ## captured at _ready — the noon peak while peak_sun_energy is 0
var _authored_sun_color: Color = Color.WHITE ## captured at _ready — the sun's colour while no gradient is authored
var _authored_sun_fog: float = 1.0           ## captured at _ready — light_volumetric_fog_energy, scaled by elevation
var _authored_sun_quat := Quaternion.IDENTITY ## captured at _ready — the manicured key angle the arc returns to at night
var _authored_ambient: float = 1.0           ## captured at _ready — the base the day/night scales multiply
var _sky_mat: ShaderMaterial = null     ## last horizon-sky material checked (identity cache for _sky_ok)
var _sky_ok: bool = false               ## does _sky_mat expose the horizon uniforms we drive?

func _ready() -> void:
	add_to_group(Groups.DAY_NIGHT)
	if sun == null:
		sun = _find_directional_light()
	_env = world_environment if world_environment != null else _find_world_environment()
	if sun != null:
		_authored_sun_energy = sun.light_energy
		_authored_sun_color = sun.light_color
		_authored_sun_fog = sun.light_volumetric_fog_energy
		_authored_sun_quat = sun.global_basis.get_rotation_quaternion()
	if _env != null and _env.environment != null:
		# Captured AFTER StarSky's node_added pass, so on a sky-sourced env this reads StarSky's pinned 1.0 and
		# on a colour-sourced env (the main level) the designer's authored value — either way, "what noon looks
		# like today" is the anchor.
		_authored_ambient = _env.environment.ambient_light_energy
	if sun == null and not _warned:
		_warned = true
		push_warning("DayNightSky: no DirectionalLight3D found to drive — add one to the level, or set `sun`. Doing nothing.")

func _process(_delta: float) -> void:
	if sun == null:
		return
	var t: float = WorldClock.time_of_day
	var elev := sun_elevation(t, dawn_time, dusk_time)
	var day := day_factor(t, sun_energy_curve, dawn_time, dusk_time, full_brightness_elevation)
	# Yaw sweeps around the day window's MIDPOINT (solar noon), not 0.5 — with an asymmetric authored window
	# (the main level's 6am..8pm) the sun's highest point lands mid-window, and the sweep should mirror it.
	var yaw := sun_yaw_deg + (t - (dawn_time + dusk_time) * 0.5) * sun_sweep_deg
	# ⭐DAY AND NIGHT ARE ONE LIGHT. Above the horizon it is the sun (authored colour + energy scaled by the day
	# factor); below it the SAME light becomes the moon — dim, cool, still on the authored direction. Crossfaded
	# over `day` rather than switched at the horizon, so dusk hands over to moonlight without a visible pop.
	var moon_lead := moon_lead_for(day)
	if drive_sun_rotation:
		var pitch := -elev * max_sun_pitch_deg  # noon (elev 1) -> steepest; dawn/dusk (elev 0) -> 0 (horizon)
		# ⭐THE ARC MUST NOT FOLLOW THE SUN UNDER THE WORLD. Below the horizon -elev flips sign, so the raw arc
		# pitch turns POSITIVE — a key light shining UP from underground (probe-measured +58° at midnight): the
		# street loses every edge the moon exists to keep, and shadows land on undersides. So the ORIENTATION
		# rides the same dusk crossfade as the energy/colour: as the moon takes the lead, the arc hands the
		# angle back to the AUTHORED rake the moon was designed to hold. Euler write, not a basis write — a
		# basis assignment would wipe an authored scale 60x/s.
		var arc := Quaternion.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0))
		sun.global_rotation = Basis(key_light_quat_for(arc, _authored_sun_quat, moon_lead)).get_euler()
	var moon_energy := maxf(0.0, moon_energy_scale) * maxf(0.0, _authored_sun_energy)
	sun.light_energy = key_light_energy_for(
			sun_energy_for(day, peak_sun_energy, _authored_sun_energy), moon_energy, moon_lead)
	sun.light_color = _sun_color(t).lerp(moon_color, moon_lead)
	# ONE fog expression, both regimes: the ARC's washout guard (only when we drive the rotation — a held
	# authored direction keeps the authored value it was tuned for) times the MOON's damping, because a moon
	# pushing the sun's fog energy greys the night haze into soup and swallows the neon.
	var fog_scale := fog_energy_scale_for(elev, high_sun_fog_scale) if drive_sun_rotation else 1.0
	sun.light_volumetric_fog_energy = _authored_sun_fog * fog_scale * lerpf(maxf(0.0, moon_fog_scale), 1.0, clampf(day * 2.0, 0.0, 1.0))
	# Only fully dark when the designer has actually turned the moon off; otherwise the night key light stays on.
	sun.visible = day > 0.001 or moon_energy > 0.0
	if drive_ambient and _env != null and _env.environment != null:
		_env.environment.ambient_light_energy = ambient_energy_for(_authored_ambient, day, ambient_day_scale, ambient_night_scale)
	if drive_sky:
		_drive_sky_material(day, yaw)

## The live day factor (0 deep night .. 1 high noon) — the ONE value other systems may sample off this driver
## (found via group "day_night", duck-typed). ViewModelCamera dims its gun fill by it at night.
func current_day_factor() -> float:
	return day_factor(WorldClock.time_of_day, sun_energy_curve, dawn_time, dusk_time, full_brightness_elevation)

## Sun elevation -1..1 over time_of_day: -1 mid-night (below the horizon), 0 on the horizon at `dawn`/`dusk`,
## +1 at the day window's midpoint (solar noon). Two sine half-arcs stitched at the horizon crossings — at the
## default 0.25/0.75 window this is EXACTLY the original -cos(TAU*t) sinusoid, so a bare drop-in is unchanged;
## an authored window (the main level's 6am..8pm) just moves where the crossings land. Smooth, wraps, and stays
## the single source of "is the sun up" — day_factor derives from it, so day > 0 ⇔ elev > 0 holds for ANY
## window (the invariant key_light_quat_for's never-points-up construction rests on). Pure — unit-tested.
static func sun_elevation(t: float, dawn: float = 0.25, dusk: float = 0.75) -> float:
	t = fposmod(t, 1.0)
	dawn = clampf(dawn, 0.01, 0.97)
	dusk = clampf(dusk, dawn + 0.02, 0.99)
	if t >= dawn and t < dusk:
		return sin(PI * (t - dawn) / (dusk - dawn))
	var since_dusk := t - dusk if t >= dusk else t + 1.0 - dusk
	return -sin(PI * since_dusk / (1.0 - (dusk - dawn)))

## The 0..1 day light factor: a custom energy `curve` sampled at t when given, else the sun's elevation over the
## dawn..dusk window divided by `full_elev` and clamped — so elevations above `full_elev` SATURATE to full
## brightness (the afternoon plateau) and the fade lives in the twilight band. full_elev 1.0 collapses to the
## original max(sun_elevation, 0); it is clamped to at most 1.0 so no value can dim the authored noon. Pure
## (the curve is passed in) so it's unit-testable.
static func day_factor(t: float, curve: Curve = null, dawn: float = 0.25, dusk: float = 0.75, full_elev: float = 1.0) -> float:
	if curve != null:
		return clampf(curve.sample(fposmod(t, 1.0)), 0.0, 1.0)
	return clampf(sun_elevation(t, dawn, dusk) / clampf(full_elev, 0.001, 1.0), 0.0, 1.0)

## The sun's energy for a day factor: the explicit peak when set, else the AUTHORED energy captured at _ready —
## the "bare drop-in keeps the authored noon" contract. Pure — unit-tested.
static func sun_energy_for(day: float, peak: float, authored: float) -> float:
	return maxf(0.0, day) * (peak if peak > 0.0 else maxf(0.0, authored))

## Ambient energy for a day factor: the AUTHORED energy scaled between the night and day fractions. Pure —
## unit-tested. (Scales of the authored value, never absolutes: an absolute day energy of 1.0 would sextuple the
## main level's authored 0.15 the moment the component dropped in.)
static func ambient_energy_for(authored: float, day: float, day_scale: float, night_scale: float) -> float:
	return maxf(0.0, authored) * lerpf(maxf(0.0, night_scale), maxf(0.0, day_scale), clampf(day, 0.0, 1.0))

## Volumetric-fog energy scale for a sun elevation: 1.0 grazing (the regime the authored value was tuned in),
## lerping to `high_scale` overhead — the noon-washout guard (see high_sun_fog_scale). Pure — unit-tested.
static func fog_energy_scale_for(elevation: float, high_scale: float) -> float:
	return lerpf(1.0, clampf(high_scale, 0.0, 1.0), clampf(elevation, 0.0, 1.0))

## How far the key light has handed over from SUN to MOON: 0 in full day, 1 once the sun is properly down.
## The x4 finishes the handover early in the dusk fade, while the sun's own term is already near nothing and
## cannot fight it — so the crossfade reads as one light changing character, not two lights swapping. Pure.
static func moon_lead_for(day: float) -> float:
	return 1.0 - clampf(day * 4.0, 0.0, 1.0)

## The ONE key light's ORIENTATION for a moon handover `lead` (0 full day .. 1 deep night): the day ARC
## rotation slerped back onto the AUTHORED rake as the moon takes the lead. Slerp, never a per-axis euler lerp —
## the authored rake can decompose into a far euler branch (yaw 180°) and component-lerping across branches
## tumbles the light mid-handover. Live, lead only leaves 0 while the arc is still above the horizon (day > 0
## ⇔ elev > 0), so every blend runs between two DOWNWARD angles — the light can never point up. Pure — unit-tested.
static func key_light_quat_for(arc: Quaternion, authored: Quaternion, lead: float) -> Quaternion:
	return arc.slerp(authored, clampf(lead, 0.0, 1.0))

## The ONE key light's energy: the sun's own value, or the moon's once it leads — whichever is greater, so the
## crossfade can never dip through a dark seam at dusk (a plain lerp between them does exactly that). Pure —
## unit-tested. moon_energy 0 collapses this to the sun alone (the fully-dark night).
static func key_light_energy_for(sun_energy: float, moon_energy: float, moon_lead: float) -> float:
	return maxf(maxf(0.0, sun_energy), maxf(0.0, moon_energy) * clampf(moon_lead, 0.0, 1.0))

## The sun colour at time `t` — the authored Gradient when one is set, else the sun's AUTHORED colour verbatim.
## ⭐There is deliberately NO built-in colour ramp: a component default that repaints the designer's key light
## replaces the level's manicured aesthetic with the component's taste (shipped once, reverted the same day).
## The doc on `sun_color_gradient` carries a recipe for anyone who wants the classic dawn-amber ramp.
func _sun_color(t: float) -> Color:
	if sun_color_gradient != null:
		return sun_color_gradient.sample(fposmod(t, 1.0))
	return _authored_sun_color

## Lerp the horizon sky between its authored night look and the day colours, and swing the hazy sun-glow with
## the real sun. Parameter writes on StarSky's material only — the `flash` uniform and the panorama binding stay
## StarSky's. Re-resolved each frame (StarSky repaints envs on scene load), with an identity-cached uniform
## check so a non-horizon sky (custom material, StarSky absent) is skipped silently instead of spammed.
func _drive_sky_material(day: float, yaw_deg: float) -> void:
	var mat := _live_sky_material()
	if mat == null:
		return
	mat.set_shader_parameter(&"zenith_color", sky_night_zenith.lerp(sky_day_zenith, day))
	mat.set_shader_parameter(&"horizon_color", sky_night_horizon.lerp(sky_day_horizon, day))
	mat.set_shader_parameter(&"sun_glow", lerpf(maxf(0.0, sky_night_sun_glow), maxf(0.0, sky_sun_glow), day))
	# ⭐The bearing EASES from the authored night azimuth to the live sun's yaw as the day comes up, rather than
	# snapping to the arc at every hour — at day 0 that is the authored 0.7 rad, the other half of what made
	# `drive_sky` repaint the night. Accepted cost, stated rather than hidden: through the dusk fade the lobe
	# migrates ~25° off the setting sun as it hands the bearing back. lerp_angle, not lerpf: the arc's yaw is
	# a designer knob and a wider sun_sweep_deg would straddle ±PI, where component lerp takes the long way.
	mat.set_shader_parameter(&"sun_azimuth",
			lerp_angle(sky_night_sun_azimuth, wrapf(deg_to_rad(yaw_deg), -PI, PI), day))
	# ⭐AND THE HORIZON BAND ITSELF. The gradient above the band is only half the sky — the authored skybox image
	# laid along the horizon carries its OWN night sky, and lerping the gradient to day while the band stayed
	# night drew a hard dark arc across the top of the image (probe-verified). `day` re-grades the band's palette
	# in step, so the two halves meet. Written from HERE, not from a general "drive any sky" hook, precisely so
	# the band can never be day while the gradient is night.
	mat.set_shader_parameter(&"day", clampf(day, 0.0, 1.0))

## The env's live sky ShaderMaterial IF it exposes the horizon uniforms we drive, else null. The uniform probe
## is the StarSky._has_param idiom (a ShaderMaterial publishes one shader_parameter/<uniform> property per
## declared uniform), cached per material INSTANCE so it runs once per repaint, not per frame.
func _live_sky_material() -> ShaderMaterial:
	if _env == null or _env.environment == null or _env.environment.sky == null:
		return null
	var mat := _env.environment.sky.sky_material as ShaderMaterial
	if mat == null:
		return null
	if mat != _sky_mat:
		_sky_mat = mat
		_sky_ok = false
		for p in mat.get_property_list():
			if p.get("name", "") == "shader_parameter/zenith_color":
				_sky_ok = true
				break
	return mat if _sky_ok else null

## First DirectionalLight3D under this node's OWN scene (the level usually has exactly one), or null. Rooted on
## `owner` (the scene this node was saved into) so it works instanced under GameRoot AND in a bare probe tree;
## falls back to current_scene for a hand-dropped, never-saved node.
func _find_directional_light() -> DirectionalLight3D:
	if not is_inside_tree():
		return null
	var base: Node = owner
	if base == null:
		base = get_tree().current_scene
	if base == null:
		return null
	return _first_dir_light(base)

func _first_dir_light(node: Node) -> DirectionalLight3D:
	if node is DirectionalLight3D:
		return node as DirectionalLight3D
	for c in node.get_children():
		var found := _first_dir_light(c)
		if found != null:
			return found
	return null

## The level's WorldEnvironment (group "world_environment", as StarSky uses), or null.
func _find_world_environment() -> WorldEnvironment:
	if not is_inside_tree() or get_tree() == null:
		return null
	for n in get_tree().get_nodes_in_group(Groups.WORLD_ENVIRONMENT):
		if n is WorldEnvironment:
			return n as WorldEnvironment
	return null
