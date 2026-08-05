class_name DamageIndicators
extends Control

## TF2-style directional damage indicators: a fading red arc around the crosshair pointing toward
## each recent damage source. The owner records a hit's WORLD position via add(); the on-screen
## bearing is recomputed every frame from the live `camera` orientation, so each arc keeps pointing
## at its source as you turn — a frozen bearing would drift and mislead the moment you rotate.
##
## SKINNED: duration, radius, arc width, thickness and colour live on MenuStyle.hud
## (resources/ui/hud_skin.tres, "Damage direction arcs" group) — this node is CODE-built by
## player_hud.gd, so the skin IS its authoring surface. Read LIVE each draw (5 fields; cheap).

## Viewer camera (a Node3D). Bearings are taken relative to its facing each frame. Set by the
## owner (Player) right after creation.
var camera: Node3D

var _hits: Array[Dictionary] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # never eat input
	# Stay live through pauses so an arc landing as the world pauses can't freeze mid-screen (mirrors AimIndicators).
	process_mode = Node.PROCESS_MODE_ALWAYS

## Record a damage source at `world_pos`; its on-screen direction is computed live in _draw.
func add(world_pos: Vector3) -> void:
	_hits.append({"pos": world_pos, "t": MenuStyle.hud.damage_arc_duration})
	queue_redraw()

func _process(delta: float) -> void:
	if _hits.is_empty():
		return
	for i in range(_hits.size() - 1, -1, -1):
		_hits[i]["t"] -= delta
		if _hits[i]["t"] <= 0.0:
			_hits.remove_at(i)
	queue_redraw()  # redraw every frame so the arcs follow camera rotation

func _draw() -> void:
	if _hits.is_empty() or not is_instance_valid(camera):
		return
	var hud = MenuStyle.hud  # untyped on purpose: HudSkin's class_name may not be cached yet
	var centre := size * 0.5
	var half: float = deg_to_rad(hud.damage_arc_degrees) * 0.5
	# Horizontal camera frame: right (X) flattened, forward from it. Yawing turns these, so the
	# bearing — and thus the arc — follows where the player is looking.
	var right := camera.global_transform.basis.x
	right.y = 0.0
	if right.length_squared() < 0.0001:
		return
	right = right.normalized()
	var fwd := Vector3.UP.cross(right)
	var eye := camera.global_position
	for h in _hits:
		var to_source: Vector3 = (h["pos"] as Vector3) - eye
		to_source.y = 0.0
		if to_source.length_squared() < 0.0001:
			continue
		# 0 = dead ahead (top of screen). Godot 2D angles run 0 = +x clockwise, so subtract 90.
		var bearing := atan2(to_source.dot(right), to_source.dot(fwd))
		var a := bearing - PI * 0.5
		var col: Color = hud.damage_arc_color
		col.a *= clampf(h["t"] / maxf(hud.damage_arc_duration, 0.001), 0.0, 1.0)
		draw_arc(centre, hud.damage_arc_radius, a - half, a + half, 24, col, hud.damage_arc_thickness, true)
