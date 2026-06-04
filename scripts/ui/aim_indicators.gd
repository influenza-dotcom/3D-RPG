class_name AimIndicators
extends Control

## "You're being aimed at" warning: a RED arc around the crosshair pointing toward each enemy drawing
## a bead on you. The arc GROWS outward as that enemy's shot charges (0 = just noticing you, 1 = locked
## + about to fire), and how far it grows scales with the shot's DAMAGE — a heavier hit telegraphs a
## bigger ring. Like DamageIndicators the bearing is recomputed every frame from the live `camera`, so
## each arc keeps pointing at its source as you turn. Enemies push reports via report().

## Smallest arc radius (px), at charge ~0 — visible the instant an enemy starts aiming.
@export var base_radius: float = 28.0
## Extra radius (px) per point of the shot's damage at FULL charge: a bigger hit => a bigger ring.
@export var damage_to_pixels: float = 70.0
## Hard cap on the arc radius (px) so a very high-damage weapon doesn't blow the ring off-screen.
@export var max_radius: float = 110.0
## Angular width of each arc wedge, in degrees.
@export var arc_degrees: float = 45.0
@export var thickness: float = 6.0
@export var color: Color = Color(0.9, 0.1, 0.1)  # red

## Seconds an aim entry survives without a fresh report (i.e. the enemy stopped aiming at us).
const EXPIRY: float = 0.2
## Blink period (s) while an aim is in its WARNING window (the final beep beat): the radial flashes.
const BLINK_PERIOD: float = 0.12

## A "you were just shot from here" ping reuses this SAME radial (no second indicator): by the time an
## NPC fires its aim charge has reset, so the aim arc is gone — the ping briefly points back at the
## shooter instead, rotating toward them as you turn. PING_TTL = lifetime; PING_RADIUS = its fixed size.
const PING_TTL: float = 0.6
const PING_RADIUS: float = 84.0

## Viewer camera (a Node3D). Bearings are taken relative to its facing each frame. Set by the owner.
var camera: Node3D

var _aims: Dictionary = {}  # source instance id -> { pos, charge, damage, warning, t }
var _pings: Dictionary = {} # source instance id -> { pos, t } : transient damage-direction pings
var _blink_t: float = 0.0   # advances every frame; drives the warning blink so all warning radials pulse together

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # never eat input
	# Always process so entries still EXPIRE while the world is paused (dialogue / death / pause menu);
	# otherwise an arc showing at the instant of a pause would freeze on screen until unpause.
	process_mode = Node.PROCESS_MODE_ALWAYS

## Called each frame by an enemy aiming at us: where it's aiming from + its 0..1 readiness.
func report(source: Object, world_pos: Vector3, charge: float, damage: float = 0.0, warning: bool = false) -> void:
	var id := source.get_instance_id()
	if charge <= 0.0:
		_aims.erase(id)
		return
	_aims[id] = {"pos": world_pos, "charge": clampf(charge, 0.0, 1.0), "damage": maxf(damage, 0.0), "warning": warning, "t": EXPIRY}
	queue_redraw()

## A brief directional ping toward `source` (whoever just shot the owner). Drawn like the aim arcs but
## keyed/sized separately; the owner calls this from indicate_damage_from() so the lone radial swings
## onto the shooter even though the pre-shot aim arc has already cleared.
func ping(source: Object, world_pos: Vector3) -> void:
	if source == null:
		return
	_pings[source.get_instance_id()] = {"pos": world_pos, "t": PING_TTL}
	queue_redraw()

func _process(delta: float) -> void:
	_blink_t += delta
	if _aims.is_empty() and _pings.is_empty():
		return
	for id in _aims.keys():
		# Drop the arc if its source was freed (a stale entry would otherwise get no fresh report to
		# update or erase it), else expire it once it goes stale without a new report.
		if not is_instance_valid(instance_from_id(id)):
			_aims.erase(id)
			continue
		_aims[id]["t"] -= delta
		if _aims[id]["t"] <= 0.0:
			_aims.erase(id)
	for id in _pings.keys():
		if not is_instance_valid(instance_from_id(id)):
			_pings.erase(id)
			continue
		_pings[id]["t"] -= delta
		if _pings[id]["t"] <= 0.0:
			_pings.erase(id)
	queue_redraw()  # redraw every frame so the arcs follow camera rotation

func _draw() -> void:
	if (_aims.is_empty() and _pings.is_empty()) or not is_instance_valid(camera):
		return
	var centre := size * 0.5
	var half := deg_to_rad(arc_degrees) * 0.5
	# Horizontal camera frame (same math as DamageIndicators) so the bearing follows your view.
	var right := camera.global_transform.basis.x
	right.y = 0.0
	if right.length_squared() < 0.0001:
		return
	right = right.normalized()
	var fwd := Vector3.UP.cross(right)
	var eye := camera.global_position
	for id in _aims:
		var aim: Dictionary = _aims[id]
		var to_source: Vector3 = (aim["pos"] as Vector3) - eye
		to_source.y = 0.0
		if to_source.length_squared() < 0.0001:
			continue
		var bearing := atan2(to_source.dot(right), to_source.dot(fwd))
		var a := bearing - PI * 0.5
		var charge := clampf(aim["charge"], 0.0, 1.0)
		# Radius GROWS with the charge, scaled by the shot's damage (bigger hit => bigger ring); opacity
		# also ramps so a just-noticing aim is faint and a locked one is bright.
		var r := minf(base_radius + charge * float(aim["damage"]) * damage_to_pixels, max_radius)
		var col := color
		# In the WARNING window (final beep beat) the radial BLINKS in time with the beep; otherwise its
		# opacity just ramps with the charge (faint while merely noticing, bright once locked).
		if aim.get("warning", false):
			col.a = 1.0 if fmod(_blink_t, BLINK_PERIOD) < BLINK_PERIOD * 0.5 else 0.15
		else:
			col.a = 0.35 + 0.65 * charge
		draw_arc(centre, r, a - half, a + half, 24, col, thickness, true)
	# Damage pings: a brief arc pointing back at whoever just SHOT us, drawn identically to the aim
	# arcs (one red radial system) so it reads as the same indicator swinging onto the shooter. Skip a
	# ping whose source already has a live aim arc, so two arcs never double up on one enemy.
	for id in _pings:
		if _aims.has(id):
			continue
		var ping_data: Dictionary = _pings[id]
		var to_src: Vector3 = (ping_data["pos"] as Vector3) - eye
		to_src.y = 0.0
		if to_src.length_squared() < 0.0001:
			continue
		var pbearing := atan2(to_src.dot(right), to_src.dot(fwd))
		var pa := pbearing - PI * 0.5
		var pcol := color
		pcol.a = clampf(ping_data["t"] / PING_TTL, 0.0, 1.0)
		draw_arc(centre, PING_RADIUS, pa - half, pa + half, 24, pcol, thickness, true)
