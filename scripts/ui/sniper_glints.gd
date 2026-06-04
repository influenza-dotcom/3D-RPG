class_name SniperGlints
extends Control

## Screen-space "sniper glint": a bright additive flare drawn at the SCREEN position of each enemy
## currently aiming at the player, so a distant shooter (especially a sniper) is easy to spot. Because
## it's a HUD element drawn ON TOP of the post-process, the pixelation / fog / scope vignette never dim
## or chop it — it reads clean at any range. Fed via report() from the player (the same aim feed as the
## radial). Skipped for enemies that are close (you can see them anyway) or behind the camera.

## Don't draw a glint for an enemy closer than this (metres) — up close you don't need help spotting them.
@export var min_distance: float = 18.0
## Flare core radius (px) at full charge; it grows from a fraction of this as the shot charges.
@export var core_radius: float = 6.0
## Half-length (px) of the anamorphic cross streaks at full charge.
@export var streak_length: float = 22.0
@export var color: Color = Color(0.7, 0.85, 1.0)  # cool blue-white

## Real-time milliseconds a glint survives without a fresh report (the enemy stopped aiming). Uses the
## WALL CLOCK, not accumulated delta — so a hitstop / pause-on-kill / dialogue pause (which zero or
## scale delta) can never strand a glint on screen.
const EXPIRY_MS: float = 200.0

## The rendering camera, for unproject_position / is_position_behind. Set by the owner.
var camera: Camera3D
var _glints: Dictionary = {}  # source instance id -> { pos, charge, t }

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # never eat input
	# Stay live through pauses so a glint can't freeze on screen (mirrors AimIndicators).
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Additive blend so the flare BRIGHTENS the view like a real lens glint instead of flat-painting it.
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat

## Called each aiming frame for an enemy drawing a bead on us: its world position + 0..1 readiness.
func report(source: Object, world_pos: Vector3, charge: float) -> void:
	if source == null:
		return
	var id := source.get_instance_id()
	if charge <= 0.0:
		_glints.erase(id)
		return
	_glints[id] = {"pos": world_pos, "charge": clampf(charge, 0.0, 1.0), "t": Time.get_ticks_msec()}
	queue_redraw()

func _process(_delta: float) -> void:
	if _glints.is_empty():
		return
	var now := Time.get_ticks_msec()
	for id in _glints.keys():
		# Drop the glint if its source was freed, or if it hasn't been refreshed within EXPIRY_MS of
		# wall-clock time (so a freeze / pause / scene churn can't strand it on screen).
		if not is_instance_valid(instance_from_id(id)) or now - _glints[id]["t"] > EXPIRY_MS:
			_glints.erase(id)
	queue_redraw()  # reproject every frame so the flare tracks the enemy as you both move

func _draw() -> void:
	if _glints.is_empty() or not is_instance_valid(camera):
		return
	var eye := camera.global_position
	for id in _glints:
		var g: Dictionary = _glints[id]
		var world: Vector3 = g["pos"]
		if eye.distance_to(world) < min_distance:
			continue  # too close — no spotting help needed
		if camera.is_position_behind(world):
			continue  # behind us — nothing to mark on screen
		var p := camera.unproject_position(world)
		var charge := clampf(g["charge"], 0.0, 1.0)
		var col := color
		col.a = 0.4 + 0.6 * charge  # brighter as the shot locks in
		var r := core_radius * (0.45 + 0.55 * charge)
		var sl := streak_length * (0.45 + 0.55 * charge)
		var thin := maxf(r * 0.35, 1.0)
		# Bright core + a 4-point anamorphic cross so it reads as a lens glint, not just a dot.
		draw_circle(p, r, col)
		draw_line(p - Vector2(sl, 0.0), p + Vector2(sl, 0.0), col, thin)
		draw_line(p - Vector2(0.0, sl), p + Vector2(0.0, sl), col, thin)
