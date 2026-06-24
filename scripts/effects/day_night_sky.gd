class_name DayNightSky
extends Node

## Drop-in DAY/NIGHT driver. Reads the WorldClock autoload's time_of_day each frame and arcs the level's SUN
## (a DirectionalLight3D) across the sky — pitch (overhead at noon, on the horizon at dawn/dusk, below at night),
## brightness (peak at noon, off at night), and warmth (amber dawn/dusk, white noon, cool night) — and optionally
## dims the WorldEnvironment's ambient at night. This makes the (now-persisted) WorldClock + NPC schedules +
## light-stealth all read VISUALLY. Complements StarSky (which paints the static horizon sky + the kill flash);
## this only touches the sun + ambient ENERGY, never StarSky's sky material.
##
## SETUP: drop a DayNightSky node anywhere in the level. It auto-finds the first DirectionalLight3D as the sun and
## the WorldEnvironment in group "world_environment"; point `sun` / `world_environment` explicitly to override.
## Inert (warns once) if there's no DirectionalLight3D to drive. Tune the knobs below per level / per mood.

## The sun to drive. Null -> auto-find the first DirectionalLight3D in the current scene at _ready.
@export var sun: DirectionalLight3D
## Arc the sun's ORIENTATION (pitch + a gentle yaw sweep) across the day. Off -> only energy/colour animate.
@export var drive_sun_rotation: bool = true
## Sun light energy at high noon (the peak the day curve scales toward). 0 = never lit.
@export var peak_sun_energy: float = 1.0
## OPTIONAL energy shape over time_of_day (0..1) — sampled for the 0..1 day factor. Null -> a clean sinusoid
## (max(sun_elevation, 0)): 0 below the horizon, peaking at noon.
@export var sun_energy_curve: Curve
## OPTIONAL sun colour over time_of_day (0..1). Null -> a built-in gradient (cool night -> amber dawn -> white
## noon -> amber dusk -> cool night).
@export var sun_color_gradient: Gradient
## Compass yaw (deg) the sun's arc centres on at noon; the sweep below rotates it east->west across the day.
@export var sun_yaw_deg: float = 35.0
## Degrees the sun's yaw sweeps over a full day (a moving shadow direction). 0 = fixed compass yaw.
@export var sun_sweep_deg: float = 120.0

## Also modulate the WorldEnvironment's ambient ENERGY (day-bright -> night-dim) so noon doesn't look as dark as
## night. Additive over StarSky's pinned ambient COLOUR (which it leaves alone). Off -> the sun is the only cue.
@export var drive_ambient: bool = true
## The WorldEnvironment whose ambient energy to modulate. Null -> auto-find via group "world_environment".
@export var world_environment: WorldEnvironment
## Ambient energy at noon / at deep night (lerped by the day factor). Day 1.0 keeps StarSky's authored look at noon.
@export var ambient_day_energy: float = 1.0
@export var ambient_night_energy: float = 0.5

var _env: WorldEnvironment = null
var _warned: bool = false

func _ready() -> void:
	if sun == null:
		sun = _find_directional_light()
	_env = world_environment if world_environment != null else _find_world_environment()
	if sun == null and not _warned:
		_warned = true
		push_warning("DayNightSky: no DirectionalLight3D found to drive — add one to the level, or set `sun`. Doing nothing.")

func _process(_delta: float) -> void:
	if sun == null:
		return
	var t: float = WorldClock.time_of_day
	var elev := sun_elevation(t)
	var day := day_factor(t, sun_energy_curve)
	if drive_sun_rotation:
		var pitch := -elev * 90.0  # noon (elev 1) -> -90 (light points straight down); dawn (elev 0) -> 0 (horizon)
		var yaw := sun_yaw_deg + (t - 0.5) * sun_sweep_deg
		sun.global_rotation = Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0)
	sun.light_energy = day * peak_sun_energy
	sun.light_color = _sun_color(t)
	sun.visible = day > 0.001  # fully off below the horizon (StarSky's sky carries the night)
	if drive_ambient and _env != null and _env.environment != null:
		_env.environment.ambient_light_energy = lerpf(ambient_night_energy, ambient_day_energy, day)

## Sun elevation -1..1 over time_of_day: -1 at midnight (below the horizon), 0 at dawn (0.25) / dusk (0.75) on the
## horizon, +1 at noon (0.5) overhead. A clean sinusoid (-cos), so the arc is smooth and wraps. Pure — unit-tested.
static func sun_elevation(t: float) -> float:
	return -cos(TAU * fposmod(t, 1.0))

## The 0..1 day light factor: a custom energy `curve` sampled at t when given, else max(sun_elevation, 0) — 0 below
## the horizon (night), peaking at noon. Pure (the curve is passed in) so it's unit-testable.
static func day_factor(t: float, curve: Curve = null) -> float:
	if curve != null:
		return clampf(curve.sample(fposmod(t, 1.0)), 0.0, 1.0)
	return maxf(sun_elevation(t), 0.0)

## The sun colour at time `t` — the authored gradient if set, else a built-in cool-night/amber-dawn/white-noon ramp.
func _sun_color(t: float) -> Color:
	if sun_color_gradient != null:
		return sun_color_gradient.sample(fposmod(t, 1.0))
	return _default_color_gradient().sample(fposmod(t, 1.0))

## Built-in default sun gradient (cached): night blue -> dawn amber -> noon white -> dusk amber -> night blue.
var _default_grad: Gradient = null
func _default_color_gradient() -> Gradient:
	if _default_grad == null:
		_default_grad = Gradient.new()
		_default_grad.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
		_default_grad.colors = PackedColorArray([
			Color(0.35, 0.45, 0.7),   # midnight: cool blue
			Color(1.0, 0.65, 0.35),   # dawn: amber
			Color(1.0, 0.97, 0.9),    # noon: near-white warm
			Color(1.0, 0.6, 0.32),    # dusk: amber
			Color(0.35, 0.45, 0.7),   # back to midnight blue (wraps)
		])
	return _default_grad

## First DirectionalLight3D in the loaded scene (the sun), or null. Auto-find for the drop-in (the level usually
## has exactly one). Searched depth-first from the current scene root.
func _find_directional_light() -> DirectionalLight3D:
	if not is_inside_tree() or get_tree() == null or get_tree().current_scene == null:
		return null
	return _first_dir_light(get_tree().current_scene)

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
