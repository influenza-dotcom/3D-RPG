class_name AimIndicators
extends Control

## "You're being aimed at" warning: a RED arc around the crosshair pointing toward each enemy drawing
## a bead on you. The arc GROWS outward as that enemy's shot charges (0 = just noticing you, 1 = locked
## + about to fire), and how far it grows scales with the shot's DAMAGE — a heavier hit telegraphs a
## bigger ring. Like DamageIndicators the bearing is recomputed every frame from the live `camera`, so
## each arc keeps pointing at its source as you turn. Enemies push reports via report().
##
## SKINNED: radius scaling, arc appearance, alpha ramp, blink beat, and the ping's radius/lifetime
## live on MenuStyle.hud (resources/ui/hud_skin.tres, "Aim warning arcs" group) — this node is
## CODE-built by player_hud.gd, so the skin IS its authoring surface. Read LIVE per frame (cheap).
## Only EXPIRY stays here: it's staleness bookkeeping (when an arc drops), not a look value.

## Seconds an aim entry survives without a fresh report (i.e. the enemy stopped aiming at us).
const EXPIRY: float = 0.2

## Viewer camera (a Node3D). Bearings are taken relative to its facing each frame. Set by the owner.
var camera: Node3D

var _aims: Dictionary = {}  # source instance id -> { pos, charge, damage, warning, t }
var _pings: Dictionary = {} # source instance id -> { pos, t } : transient damage-direction pings
var _blink_t: float = 0.0   # advances every frame; drives the warning blink so all warning radials pulse together
## True while the canvas still HOLDS a painted arc. A CanvasItem only re-runs _draw() on queue_redraw() --
## it does NOT repaint every frame -- so emptying _aims/_pings without queuing one leaves the last frame's
## arc frozen on screen FOREVER. This flag lets the empty state queue exactly ONE clearing redraw.
var _painted: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # never eat input
	# Always process so entries still EXPIRE while the world is paused (dialogue / death / pause menu);
	# otherwise an arc showing at the instant of a pause would freeze on screen until unpause.
	process_mode = Node.PROCESS_MODE_ALWAYS

## Called each frame by an enemy aiming at us: where it's aiming from + its 0..1 readiness.
func report(source: Object, world_pos: Vector3, charge: float, damage: float = 0.0, warning: bool = false) -> void:
	var id := source.get_instance_id()
	if charge <= 0.0:
		# Dropping the arc CHANGES what should be on screen, so it must queue a redraw exactly like the set
		# path below. Without this the arc painted LAST frame just stays there: erasing leaves _aims empty,
		# so _process has nothing to expire and takes its early-out -- and a CanvasItem repaints only when
		# something queues it. THE STUCK RED ARC. It stranded at the arc's pre-shot peak (bright, near max
		# radius) because npc_combat reports the charge computed BEFORE the shot fired. Reachable whenever
		# an enemy's last report is a zero with no positive one behind it in the same frame:
		#   * runs dry -> GOAP replans to FireUnarmed, which reports 0 every frame and never aims a laser;
		#   * swaps to a melee weapon -> act_alerted suppresses the laser's report and zeroes this one;
		#   * fires, then drops the alerted body before the next tick (you broke away / out of perception)
		#     -- the post-shot frame pins charge to exactly 0, so that frame's reports both erase silently.
		# (Walking out of RANGE mid-charge self-heals: the laser's positive report queues a redraw that
		# resolves against the erased dict. Which is why this only bit "sometimes".)
		if _aims.erase(id):
			queue_redraw()
		return
	_aims[id] = {"pos": world_pos, "charge": clampf(charge, 0.0, 1.0), "damage": maxf(damage, 0.0), "warning": warning, "t": Time.get_ticks_msec()}
	queue_redraw()

## A brief directional ping toward `source` (whoever just shot the owner). Drawn like the aim arcs but
## keyed/sized separately; the owner calls this from indicate_damage_from() so the lone radial swings
## onto the shooter even though the pre-shot aim arc has already cleared. Its lifetime/size are the
## skin's aim_ping_ttl / aim_ping_radius.
func ping(source: Object, world_pos: Vector3) -> void:
	if source == null:
		return
	_pings[source.get_instance_id()] = {"pos": world_pos, "t": Time.get_ticks_msec()}
	queue_redraw()

func _process(delta: float) -> void:
	_blink_t += delta
	if _aims.is_empty() and _pings.is_empty():
		# Nothing to age -- but if the canvas still holds the last arc, queue the ONE redraw that clears it.
		# Belt-and-suspenders behind report()'s erase path above: ANY future way of emptying these dicts
		# lands here within a frame, so a stale arc can never outlive its entry again.
		if _painted:
			queue_redraw()
		return
	var now := Time.get_ticks_msec()
	var ping_ttl_ms: float = MenuStyle.hud.aim_ping_ttl * 1000.0
	for id in _aims.keys():
		# Drop the arc if its source was freed (a stale entry would otherwise get no fresh report to
		# update or erase it), else expire it once it goes stale without a new report. Staleness is
		# measured on the WALL CLOCK (not accumulated delta) so a hitstop / pause-on-kill / dialogue
		# pause that zeros or scales delta can't strand an arc on screen.
		if not is_instance_valid(instance_from_id(id)) or now - _aims[id]["t"] > EXPIRY * 1000.0:
			_aims.erase(id)
	for id in _pings.keys():
		if not is_instance_valid(instance_from_id(id)) or now - _pings[id]["t"] > ping_ttl_ms:
			_pings.erase(id)
	queue_redraw()  # redraw every frame so the arcs follow camera rotation

func _draw() -> void:
	# Every _draw starts from a CLEARED canvas item, so this run defines what stays on screen; record it
	# for the _process guard above. Set conservatively (an unnecessary clearing redraw is free; a missed
	# one strands an arc), so it counts "we got past the early-outs", not "a stroke actually landed".
	_painted = false
	if (_aims.is_empty() and _pings.is_empty()) or not is_instance_valid(camera):
		return
	_painted = true
	var hud = MenuStyle.hud  # untyped on purpose: HudSkin's class_name may not be cached yet
	var centre := size * 0.5
	var half: float = deg_to_rad(hud.aim_arc_degrees) * 0.5
	# Horizontal camera frame (same math as DamageIndicators) so the bearing follows your view.
	var right := camera.global_transform.basis.x
	right.y = 0.0
	if right.length_squared() < 0.0001:
		return
	right = right.normalized()
	var fwd := Vector3.UP.cross(right)
	var eye := camera.global_position
	var now := Time.get_ticks_msec()
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
		var r: float = minf(hud.aim_arc_base_radius + charge * float(aim["damage"]) * hud.aim_arc_damage_to_pixels, hud.aim_arc_max_radius)
		var col: Color = hud.aim_arc_color
		# In the WARNING window (final beep beat) the radial BLINKS in time with the beep; otherwise its
		# opacity ramps from aim_arc_min_alpha at charge 0 to 1.0 once locked.
		if aim.get("warning", false):
			var period: float = maxf(hud.aim_arc_blink_period, 0.001)
			col.a = 1.0 if fmod(_blink_t, period) < period * 0.5 else hud.aim_arc_blink_dim_alpha
		else:
			col.a = hud.aim_arc_min_alpha + (1.0 - hud.aim_arc_min_alpha) * charge
		draw_arc(centre, r, a - half, a + half, 24, col, hud.aim_arc_thickness, true)
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
		var pcol: Color = hud.aim_arc_color
		# Fade out over the ping's life, measured on the wall clock (same stamp used for expiry above).
		pcol.a = clampf(1.0 - float(now - ping_data["t"]) / (maxf(hud.aim_ping_ttl, 0.001) * 1000.0), 0.0, 1.0)
		draw_arc(centre, hud.aim_ping_radius, pa - half, pa + half, 24, pcol, hud.aim_arc_thickness, true)
