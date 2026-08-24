class_name SniperGlints
extends Control

## Screen-space "sniper glint": a bright additive flare drawn at the SCREEN position of each enemy
## currently aiming at the player, so a distant shooter (especially a sniper) is easy to spot. Because
## it's a HUD element drawn ON TOP of the post-process, the pixelation / fog / scope vignette never dim
## or chop it — it reads clean at any range. Fed via report() from the player (the same aim feed as the
## radial). Skipped for enemies that are close (you can see them anyway) or behind the camera.
##
## SKINNED: the flare's LOOK (core radius, streak length, colour, charge alpha/size ramps) lives on
## MenuStyle.hud (resources/ui/hud_skin.tres, "Sniper glints" group) — this node is CODE-built by
## player_hud.gd, so the skin IS its authoring surface. min_distance / expiry_ms stay HERE as
## functional gates: they decide WHEN a glint shows, not how it looks.

## Don't draw a glint for an enemy closer than this (metres) — up close you don't need help spotting them.
@export var min_distance: float = 18.0

## Real-time milliseconds a glint survives without a fresh report (the enemy stopped aiming). Uses the
## WALL CLOCK, not accumulated delta — so a hitstop / pause-on-kill / dialogue pause (which zero or
## scale delta) can never strand a glint on screen.
@export var expiry_ms: float = 200.0

## The rendering camera, for unproject_position / is_position_behind. Set by the owner.
var camera: Camera3D
var _glints: Dictionary = {}  # source instance id -> { pos, charge, t }
## True while the canvas still HOLDS a painted flare -- see the same flag on AimIndicators. A CanvasItem
## repaints only on queue_redraw(), so dropping the last glint without one leaves the flare frozen on screen.
var _painted: bool = false

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
		# Clearing the glint must queue a redraw just like the set path below, or the flare drawn last frame
		# stays painted. The player feeds charge 0 here the instant the enemy loses the clear shot, and the
		# enemy then reports 0 EVERY frame while out of range -- so _process has nothing left to expire and
		# nothing else would ever repaint. Same defect as AimIndicators.report(); fixed the same way.
		if _glints.erase(id):
			queue_redraw()
		return
	_glints[id] = {"pos": world_pos, "charge": clampf(charge, 0.0, 1.0), "t": Time.get_ticks_msec()}
	queue_redraw()

func _process(_delta: float) -> void:
	if _glints.is_empty():
		# Nothing to expire -- but if the canvas still holds the last flare, queue the ONE redraw that clears
		# it, so no future way of emptying _glints can strand a glint on screen (mirrors AimIndicators).
		if _painted:
			queue_redraw()
		return
	var now := Time.get_ticks_msec()
	for id in _glints.keys():
		# Drop the glint if its source was freed, or if it hasn't been refreshed within expiry_ms of
		# wall-clock time (so a freeze / pause / scene churn can't strand it on screen).
		if not is_instance_valid(instance_from_id(id)) or now - _glints[id]["t"] > expiry_ms:
			_glints.erase(id)
	queue_redraw()  # reproject every frame so the flare tracks the enemy as you both move

func _draw() -> void:
	# This run defines what stays on the (freshly cleared) canvas item; record it for the _process guard.
	# Conservative on purpose -- an extra clearing redraw is free, a missed one strands a flare.
	_painted = false
	if _glints.is_empty() or not is_instance_valid(camera):
		return
	_painted = true
	var hud = MenuStyle.hud  # untyped on purpose: HudSkin's class_name may not be cached yet
	var eye := camera.global_position
	var now := Time.get_ticks_msec()
	for id in _glints:
		# Belt-and-suspenders: never DRAW a glint whose source was freed or whose last report is stale,
		# even if _process hasn't pruned it yet this frame.
		if not is_instance_valid(instance_from_id(id)) or now - _glints[id]["t"] > expiry_ms:
			continue
		var g: Dictionary = _glints[id]
		var world: Vector3 = g["pos"]
		if eye.distance_to(world) < min_distance:
			continue  # too close — no spotting help needed
		if camera.is_position_behind(world):
			continue  # behind us — nothing to mark on screen
		var p := camera.unproject_position(world)
		var charge := clampf(g["charge"], 0.0, 1.0)
		var col: Color = hud.glint_color
		col.a = hud.glint_min_alpha + (1.0 - hud.glint_min_alpha) * charge  # brighter as the shot locks in
		# Core + streaks grow from glint_min_scale of full size as the shot charges.
		var scale_f: float = hud.glint_min_scale + (1.0 - hud.glint_min_scale) * charge
		var r: float = hud.glint_core_radius * scale_f
		var sl: float = hud.glint_streak_length * scale_f
		var thin := maxf(r * 0.35, 1.0)  # streak width derived from the core (keeps the flare proportioned)
		# Bright core + a 4-point anamorphic cross so it reads as a lens glint, not just a dot.
		draw_circle(p, r, col)
		draw_line(p - Vector2(sl, 0.0), p + Vector2(sl, 0.0), col, thin)
		draw_line(p - Vector2(0.0, sl), p + Vector2(0.0, sl), col, thin)
