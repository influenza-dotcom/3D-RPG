class_name RangedEnemy
extends Enemy

## A ranged enemy: it wields the SAME Weapon component the player does, aimed by AI instead of
## a camera. It locks onto the NEAREST hostile target — the player or a faction-opposed NPC (see
## _acquire_target / NPC.is_hostile_to) — then senses it through a Perception layer (view cone +
## line-of-sight with a detection meter) and only turns, aims, lasers, and fires once it has
## actually noticed the target — no 360° omniscience. Place it like a regular Enemy; HP / gore /
## knockback come from Enemy.
##
## Designer surface: drop one in, point weapon_data at any .tres, and tune the perception +
## firing values in the inspector.

const WEAPON_SCENE := preload("res://scenes/weapon.tscn")
const LASER_MAX_LENGTH := 60.0
## Engagement range an enemy falls back to when its weapon reports 0 effective_range - a projectile
## weapon like the rock / rocket launcher, whose damage rides the projectile rather than a hitscan
## ray. Without this the AI's aim ray would be zero-length, so it never reads a clear shot and just
## walks into your face instead of firing.
const UNRANGED_AIM_FALLBACK := 15.0

@export_group("Weapon")
## The weapon this enemy fires — any WeaponData .tres, exactly like the player's.
@export var weapon_data: WeaponData = preload("res://resources/weapons/pistol.tres")
## Local offset of the muzzle (shot origin) from the enemy origin. This model faces +Z.
@export var muzzle_offset: Vector3 = Vector3(0.0, 0.0, 0.0)
## Seconds between shots once alerted (the weapon's own cooldown still applies on top).
@export var fire_cooldown: float = 1.5
## Won't shoot past this distance to the player (separate from how far it can SEE).
@export var fire_range: float = 30.0
## Vertical nudge on the aim point (centre of the player's collision capsule). 0 = dead centre.
@export var target_height: float = 0.0

@export_group("Perception")
## How far the enemy can see.
@export var sight_range: float = 25.0
## Full view-cone angle (degrees). Outside this off its facing it simply can't see you.
@export var fov_degrees: float = 110.0
## Seconds in view before it's fully alerted — your reaction window.
@export var time_to_detect: float = 1.0
## Seconds it stays wary at your last-known spot before giving up.
@export var forget_time: float = 4.0
## Eye height the sight / LOS rays start from.
@export var eye_height: float = 1.4
## Hear the player's noise (gunfire, fast movement) even outside the cone? Crouch is silent.
@export var hearing: bool = true
## How fast it rotates to face what it's looking at.
@export var turn_speed: float = 8.0

@export_group("Laser")
## Draw a laser sight that brightens as it detects / locks onto you.
@export var show_laser: bool = true
## Laser sight colour.
@export var laser_color: Color = Color(1.0, 0.1, 0.1)

@export_group("Movement")
## How fast it walks / chases (m/s).
@export var move_speed: float = 4.0
## Ground acceleration — also how fast it sheds knockback / brakes to a stop (m/s^2).
@export var move_accel: float = 25.0
## Air acceleration (low, so a blast carries it before it recovers) (m/s^2).
@export var air_accel: float = 2.0
## Alerted: closes until the player is within this fraction of the weapon's effective range,
## then holds and fires (so it actually gets in range to hit).
@export var engage_range_fraction: float = 0.9
## Upward impulse for hopping ledges / the far end of an up navigation-link (m/s).
@export var jump_velocity: float = 10.0

@export_group("Behavior")
## How this NPC reacts to a hostile target it has noticed. FIGHT = engage and shoot (the default,
## i.e. today's enemy). FLEE = run away from the threat and never fire (a civilian / coward). Pair
## FLEE + `wanders` + a NEUTRAL/FRIENDLY disposition for a townsperson who only bolts when attacked.
enum ThreatResponse { FIGHT, FLEE }
@export var threat_response: ThreatResponse = ThreatResponse.FIGHT
## Roam near the spawn point while idle (no hostile target) instead of standing still.
@export var wanders: bool = false
## How far from the spawn point wandering may stray (metres).
@export var wander_radius: float = 6.0
## Seconds to linger at each wander stop before picking a new spot (randomised across this range).
@export var wander_dwell_min: float = 1.5
@export var wander_dwell_max: float = 4.0
## When fleeing, how far ahead (metres) to aim each step away from the threat.
@export var flee_distance: float = 12.0

var _weapon: Weapon
var _muzzle: Marker3D
## MGS-style "!" alert played once when an enemy first spots the player (Perception DETECTING).
## The cooldown is shared across all enemies (static) so a swarm spotting you at once = one sting.
const MGS_ALERT = preload("res://assets/413641__djlprojects__metal-gear-solid-inspired-alert-surprise-sfx.wav")
const ALERT_COOLDOWN_MS: int = 3000
static var _last_alert_msec: int = 0
## Sniper "charging aim" sting (Nuclear Throne), played positionally from the enemy when it locks on
## AND at the start of each shot's charge. Short cooldown only dedups near-simultaneous triggers
## (e.g. lock + an immediate first shot); the fire cadence is the real rhythm.
const AIM_SFX = preload("res://sndSniperTarget.wav")
const AIM_COOLDOWN_MS: int = 250
var _last_aim_msec: int = 0

var _perception: Perception
var _target: Node3D
var _target_body: Node3D  # target's collision shape (centre tracks crouch); falls back to _target
var _laser: MeshInstance3D
var _fire_timer: float = 0.0
var _spawn_yaw: float = 0.0
var _spawn_position: Vector3
var _desired_velocity: Vector3 = Vector3.ZERO
var _nav: NavigationAgent3D

## Target re-acquisition throttle. We do NOT scan every frame (that would be O(n^2) across all
## NPCs). Instead we re-scan every RETARGET_INTERVAL seconds, or immediately when the current
## target becomes invalid / dies / leaves sight_range (handled in _physics_process).
const RETARGET_INTERVAL: float = 0.5
var _retarget_timer: float = 0.0

## Wander bookkeeping (used only when `wanders`): the current roam destination + a dwell pause.
var _wander_target: Vector3
var _has_wander_target: bool = false
var _wander_dwell: float = 0.0

func _ready() -> void:
	super._ready()
	_fire_timer = fire_cooldown  # seed a full wind-up so the first shot charges instead of firing instantly
	_spawn_yaw = rotation.y
	_spawn_position = global_position
	_muzzle = Marker3D.new()
	add_child(_muzzle)
	_muzzle.position = muzzle_offset
	_weapon = WEAPON_SCENE.instantiate()
	add_child(_weapon)
	# No camera -> ScopeIn no-ops (no ADS) and the input-driven parts are disabled.
	_weapon.setup(self, null, _muzzle)
	if weapon_data:
		_weapon.inventory.equip(weapon_data)
	_build_laser()
	_build_perception()
	_build_nav()
	_acquire_target()

## Off guard (eligible for the sneak-attack bonus) until fully ALERTED — i.e. while UNAWARE, still
## DETECTING, or INVESTIGATING a noise. Once it locks on and engages, no more free sneak damage.
func is_off_guard() -> bool:
	return _perception != null and _perception.state != Perception.State.ALERTED

func _build_perception() -> void:
	_perception = Perception.new()
	_perception.sight_range = sight_range
	_perception.fov_degrees = fov_degrees
	_perception.time_to_detect = time_to_detect
	_perception.forget_time = forget_time
	_perception.eye_height = eye_height
	_perception.hearing = hearing
	_perception.just_spotted.connect(_on_spotted)
	_perception.just_alerted.connect(_on_aim)
	add_child(_perception)

## Play the MGS "!" sting (2D so it reads regardless of which enemy spotted you), throttled by a
## shared cooldown so a group spotting you at once doesn't stack the sound.
func _on_spotted() -> void:
	if threat_response == ThreatResponse.FLEE:
		return  # a fleeing civilian noticing danger isn't a combat "!" alert
	var now := Time.get_ticks_msec()
	if now - _last_alert_msec < ALERT_COOLDOWN_MS:
		return
	_last_alert_msec = now
	AudioManager.play_sfx(global_position, MGS_ALERT, 0.0, 1.0)

## Play the sniper charge sting from this enemy's position when it locks on to fire.
func _on_aim() -> void:
	if threat_response == ThreatResponse.FLEE:
		return  # fleers never aim or charge a shot, so no sniper-charge sting
	var now := Time.get_ticks_msec()
	if now - _last_aim_msec < AIM_COOLDOWN_MS:
		return
	_last_aim_msec = now
	AudioManager.play_2d_sfx(AIM_SFX)
	#AudioManager.play_sfx(global_position, AIM_SFX, 0.0, 1.0)

func _build_nav() -> void:
	_nav = NavigationAgent3D.new()
	_nav.path_desired_distance = 0.5
	_nav.target_desired_distance = 1.0
	add_child(_nav)

func _physics_process(delta: float) -> void:
	_desired_velocity = Vector3.ZERO  # default: hold position; states below may drive it
	# Re-acquire on a throttle, or immediately when the current target is gone / dead / out of
	# range / no longer hostile. _target_invalid() keeps this an O(1) check most frames; the full
	# O(n) scan only runs on the timer or a genuine invalidation — never an every-frame O(n^2).
	_retarget_timer -= delta
	if _retarget_timer <= 0.0 or _target_invalid():
		_acquire_target()
		_retarget_timer = RETARGET_INTERVAL
	if not is_instance_valid(_target):
		# Nothing hostile around: live a little instead of freezing - wander near spawn (if `wanders`)
		# or just hold position. This is the common case for a NEUTRAL/FRIENDLY NPC with no enemies.
		_idle(delta, false)
		_hide_laser()
		super._physics_process(delta)
		return
	# Hostility gate: kept for symmetry with today. _acquire_target only ever returns a hostile
	# target, so this stays true while engaged; it cleanly idles a non-hostile NPC with no peers.
	_perception.is_hostile = is_hostile_to(_target)
	_perception.sense(delta)
	# A fleer runs from any threat it has noticed rather than fighting it (no aim, laser, or fire).
	# While still UNAWARE it falls through to the idle branch below, so a coward wanders until it
	# actually spots danger, then bolts.
	if threat_response == ThreatResponse.FLEE and _perception.state != Perception.State.UNAWARE:
		_act_flee(delta)
		_hide_laser()
		super._physics_process(delta)
		return
	match _perception.state:
		Perception.State.UNAWARE:
			# No threat perceived: wander (if `wanders`), else walk back to post if knocked away
			# then watch the spawn direction - the unchanged default for a plain enemy.
			_idle(delta, true)
			_hide_laser()
		Perception.State.DETECTING:
			_face_point(_perception.last_known_position, delta)
			_hide_laser()  # detecting only — no laser until it's actually aiming to shoot (ALERTED)
		Perception.State.ALERTED:
			_act_alerted(delta)
		Perception.State.INVESTIGATING:
			# Go check the last-known spot; face where it walks, then look around once there.
			if _move_toward(_perception.last_known_position):
				_face_travel(delta)
			else:
				_face_point(_perception.last_known_position, delta)
			_hide_laser()  # investigating a noise — not aiming to shoot, so no laser
	super._physics_process(delta)  # gravity + blast + locomotion move (uses _desired_velocity)

## Alerted: track the player, keep the laser hot, and fire on cadence while the shot is clear.
func _act_alerted(delta: float) -> void:
	var aim := _aim_point()
	# Close until the player is comfortably inside our weapon's effective range, then hold + fire.
	if global_position.distance_to(aim) > _aim_range() * engage_range_fraction:
		_move_toward(aim)
	_face_point(aim, delta)
	_fire_timer = maxf(0.0, _fire_timer - delta)
	# Laser opacity AND the player's aim radial reflect the shot's charge: 0 right after firing,
	# ramping to 1 (opaque / about to fire) as the cooldown elapses.
	var charge := clampf(1.0 - _fire_timer / maxf(fire_cooldown, 0.001), 0.0, 1.0)
	var hit := _aim_laser_at(aim, charge)
	var clear: bool = not hit.is_empty() and hit.get("collider") == _target
	# Reload the instant we run dry — even with no clear shot or out of range — so the enemy ducks
	# and reloads behind cover instead of standing empty until you peek. AI has no reload input, so
	# trigger it directly; is_busy() then blocks the fire below until the fresh clip is up.
	if _weapon.current_ammo == 0 and not _weapon.is_busy():
		_weapon.reload()
	if clear and global_position.distance_to(aim) <= fire_range and _fire_timer <= 0.0 and _weapon.current_ammo != 0:
		_weapon.attack.try_fire()
		_fire_timer = fire_cooldown
		_on_aim()  # play the charge sting for the next shot, so it sounds every shot — not just on lock
	_report_aim(charge)

## Taking a hit aggros us toward the shooter — no free backstabs. Provoke (NPC handles the
## hostility flip + reputation drop), then alert Perception toward where the hit came from so a
## shot in the back spins us around. Overrides NPC._on_damaged_by (called from take_damage).
func _on_damaged_by(attacker: Node, was_crit: bool = false) -> void:
	super._on_damaged_by(attacker, was_crit)  # NPC: flip _provoked + drop faction rep if the player hit us
	if not _perception:
		return
	# Prefer the actual attacker's position; fall back to the player's aim point (covers a hit
	# whose source we can't localize, preserving the old behaviour).
	if attacker is Node3D and is_instance_valid(attacker):
		_perception.alert_to((attacker as Node3D).global_position)
	elif is_instance_valid(_target):
		_perception.alert_to(_aim_point())

## The hit freeze-frame still rides the `damaged` signal (wired in enemy.tscn). The aggro/turn-
## toward-shooter logic moved to _on_damaged_by (which gets the attacker identity take_damage now
## passes). Kept so the scene signal connection stays valid and the hitstop still fires.
func _on_damaged(current_hp: float, _max_hp: float) -> void:
	super._on_damaged(current_hp, _max_hp)

# --- Locomotion: NavigationAgent3D pathing composed with the inherited knockback ---
## Path one step toward `target`: sets _desired_velocity along the next path point. Returns
## true while still travelling (false when arrived / no path). Verticality is handled by
## gravity + move_and_slide walking the baked navmesh surface.
func _move_toward(target: Vector3) -> bool:
	if not _nav:
		return false
	_nav.target_position = target
	var to_next: Vector3
	if not _nav.is_navigation_finished():
		# Normal: follow the baked navmesh path (routes around walls + obstacles).
		to_next = _nav.get_next_path_position() - global_position
		if Vector2(to_next.x, to_next.z).length() < 0.05:
			# Path won't advance — navmesh is missing/floating/disconnected under us, so the
			# agent can't route. Head straight at the target so pursuit still works. (Fix the
			# bake for proper wall-avoidance + verticality.)
			to_next = target - global_position
	elif not _nav.is_target_reachable():
		# No navmesh path to you (you dropped off a ledge / off the mesh): commit and head
		# straight for you, walking off the edge if pursuit demands it. Gravity does the fall.
		to_next = target - global_position
		if Vector2(to_next.x, to_next.z).length() < 0.5:
			return false
	else:
		return false  # genuinely arrived
	var climb := to_next.y
	to_next.y = 0.0
	# Hop up toward a higher path point — a ledge, or the far end of an up navigation-link.
	if climb > 0.6 and is_on_floor():
		velocity.y = jump_velocity
	if to_next.length() < 0.05:
		return false
	_desired_velocity = to_next.normalized() * move_speed
	return true

func _face_travel(delta: float) -> void:
	if _desired_velocity.length_squared() > 0.0001:
		_face_point(global_position + _desired_velocity, delta)

## Non-combat idle update. Wanderers roam near spawn; otherwise the NPC either returns to its post
## (return_to_post, when knocked away) or just holds still - the prior target-less behaviour, so a
## plain FIGHT enemy is completely unchanged.
func _idle(delta: float, return_to_post: bool) -> void:
	if wanders:
		_wander(delta)
		return
	if not return_to_post:
		return
	if _move_toward(_spawn_position):
		_face_travel(delta)
	else:
		_face_yaw(_spawn_yaw, delta)

## Roam: walk to a random point within wander_radius of spawn, dwell a beat on arrival, then pick a
## fresh one. Reuses the same navmesh pathing + facing as combat pursuit, so it routes around walls.
func _wander(delta: float) -> void:
	if _wander_dwell > 0.0:
		_wander_dwell -= delta  # lingering at a stop, standing where we arrived
		return
	if not _has_wander_target:
		_wander_target = _pick_wander_point()
		_has_wander_target = true
	if _move_toward(_wander_target):
		_face_travel(delta)
	else:
		# Arrived, or the navmesh wouldn't route there: pause, then choose a new spot next time.
		_has_wander_target = false
		_wander_dwell = randf_range(wander_dwell_min, wander_dwell_max)

## A random point on the disc of radius wander_radius around spawn (sqrt keeps it uniformly spread,
## not clustered at the centre).
func _pick_wander_point() -> Vector3:
	var ang := randf() * TAU
	var r := sqrt(randf()) * wander_radius
	return _spawn_position + Vector3(cos(ang) * r, 0.0, sin(ang) * r)

## Flee: each frame, head for a point flee_distance straight away from the threat. Recomputed every
## frame so the destination keeps running ahead of us; we face the way we run and never fire.
func _act_flee(delta: float) -> void:
	var away := global_position - _aim_point()
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = Vector3(sin(_spawn_yaw), 0.0, cos(_spawn_yaw))  # standing on the threat: bolt spawn-ward
	var flee_to := global_position + away.normalized() * flee_distance
	if _move_toward(flee_to):
		_face_travel(delta)
	else:
		_face_point(flee_to, delta)

## Locomotion + knockback: ease horizontal velocity toward the desired (nav) velocity — which
## also bleeds off a blast and brakes to a stop when idle — then add the decaying blast impulse
## and slide. Mirrors Enemy.apply_velocity's blast + fall-damage tail.
func apply_velocity() -> void:
	var horizontal := Vector2(velocity.x, velocity.z)
	var desired_h := Vector2(_desired_velocity.x, _desired_velocity.z)
	var rate := move_accel if is_on_floor() else air_accel
	horizontal = horizontal.move_toward(desired_h, rate * get_physics_process_delta_time())
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	velocity += explosion_velocity
	var pre_move_velocity := velocity
	var was_grounded := is_on_floor()
	move_and_slide()
	if is_on_floor() and not was_grounded:
		_apply_fall_damage(-pre_move_velocity.y)
	_push_interactables(pre_move_velocity)
	velocity -= explosion_velocity / blast_damp_divisor

# --- Facing (smooth yaw; this model's front is +Z, so yaw = atan2(dx, dz)) ---
func _face_point(point: Vector3, delta: float) -> void:
	var to := point - global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	_face_yaw(atan2(to.x, to.z), delta)

func _face_yaw(target_yaw: float, delta: float) -> void:
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))

# --- Target acquisition ---
## Cheap per-frame test: is the current target no longer worth keeping? (gone, freed, out of
## sight_range, or hostility lapsed — e.g. a provoke wore off or rep shifted). Forces a re-scan.
func _target_invalid() -> bool:
	if not is_instance_valid(_target):
		return true
	if global_position.distance_to(_target.global_position) > sight_range:
		return true
	return not is_hostile_to(_target)

## Pick the nearest hostile node: the player plus every NPC peer, filtered by is_hostile_to()
## and sight_range, nearest wins. Defaults to the player when it's the only/nearest hostile, so a
## lone player-hostile enemy behaves exactly as before. Throttled by the caller (RETARGET_INTERVAL)
## so this O(n) scan is not an every-frame cost. Also binds Perception to whatever we locked.
func _acquire_target() -> void:
	var best: Node3D = null
	var best_d := INF
	# The player is just another candidate — same hostility + range test as any NPC.
	var player := get_tree().get_first_node_in_group(&"Player") as Node3D
	if is_instance_valid(player) and is_hostile_to(player):
		var pd := global_position.distance_to(player.global_position)
		if pd <= sight_range:
			best = player
			best_d = pd
	for node in get_tree().get_nodes_in_group(&"npc"):
		var npc := node as NPC
		if npc == null or npc == self or not is_instance_valid(npc):
			continue
		if not is_hostile_to(npc):
			continue
		var d := global_position.distance_to(npc.global_position)
		if d <= sight_range and d < best_d:
			best = npc
			best_d = d
	_target = best
	# Resolve the LOS body: the player exposes "PlayerCollisionShape"; NPCs fall back to the root
	# (their CollisionShape is unnamed, and the root collider works for the ray identity test).
	_target_body = _target.get_node_or_null(^"PlayerCollisionShape") if _target else null
	if not _target_body:
		_target_body = _target
	if _perception:
		_perception.target = _target
		_perception.target_body = _target_body

## World point to aim at: the centre of the target's collision capsule (+ optional nudge).
func _aim_point() -> Vector3:
	var node: Node3D = _target_body if is_instance_valid(_target_body) else _target
	return node.global_position + Vector3.UP * target_height

## How far the aim ray / laser reaches — the equipped weapon's own effective range.
func _aim_range() -> float:
	var w: WeaponData = _weapon.equipped_weapon if _weapon else null
	if w == null:
		return LASER_MAX_LENGTH
	return w.effective_range if w.effective_range > 0.0 else UNRANGED_AIM_FALLBACK

# --- Laser sight ---
func _build_laser() -> void:
	_laser = MeshInstance3D.new()
	var beam := BoxMesh.new()
	beam.size = Vector3(0.02, 0.02, 1.0)
	_laser.mesh = beam
	_laser.top_level = true  # ignore our own (rotating) transform; placed in world space
	_laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA  # so the beam can fade in via alpha
	mat.emission_enabled = true
	mat.emission = laser_color
	var start := laser_color
	start.a = 0.0
	mat.albedo_color = start
	mat.emission_energy_multiplier = 0.0
	_laser.material_override = mat
	add_child(_laser)
	_laser.visible = false

func _hide_laser() -> void:
	if _laser:
		_laser.visible = false

## Called by DialogueManager when this enemy becomes / stops being the one being talked to. While
## talking it's frozen, so its aim loop can't hide the laser itself; do it here. The AI re-shows
## the laser on its own once it unfreezes and re-acquires.
func set_in_dialogue(on: bool) -> void:
	if on:
		_hide_laser()

## Feed the player's aim indicator our position + how ready we are to fire (0 = just noticing you,
## 1 = locked / about to shoot), so a white radial points at us and ramps opaque.
func _report_aim(charge: float) -> void:
	if is_instance_valid(_target) and _target.has_method(&"indicate_aimed_from"):
		_target.indicate_aimed_from(self, global_position, charge)

## Point the laser from the muzzle toward `point` (capped at weapon range), glowing by `charge`
## (0..1). Returns the ray hit so callers can reuse it (e.g. the clear-shot test).
func _aim_laser_at(point: Vector3, charge: float) -> Dictionary:
	_report_aim(charge)  # warn the player (the white aim radial); ALERTED overrides with fire-readiness
	var origin := get_aim_origin()
	var dir := point - origin
	if dir.length() < 0.01:
		_hide_laser()
		return {}
	dir = dir.normalized()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * _aim_range())
	query.exclude = [self]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not show_laser or not _laser:
		_hide_laser()
		return hit
	var endpoint: Vector3 = hit.position if not hit.is_empty() else origin + dir * _aim_range()
	var dist := origin.distance_to(endpoint)
	if dist < 0.01:
		_hide_laser()
		return hit
	# Beam basis by hand: Z column = direction * length (so the unit box stretches ALONG the
	# aim); X/Y kept unit + perpendicular so it stays thin. Centred at the midpoint it spans
	# exactly muzzle -> endpoint.
	var bdir := (endpoint - origin) / dist
	var x := bdir.cross(Vector3.UP)
	if x.length_squared() < 0.000001:
		x = bdir.cross(Vector3.FORWARD)
	x = x.normalized()
	var y := x.cross(bdir).normalized()
	_laser.visible = true
	_laser.global_transform = Transform3D(Basis(x, y, bdir * dist), (origin + endpoint) * 0.5)
	var mat := _laser.material_override as StandardMaterial3D
	if mat:
		# Opacity ramps with the charge: fully transparent while it's merely noticing you,
		# fully opaque the instant it's locked and firing — a fast "no fire -> fire" read.
		var a := clampf(charge, 0.0, 1.0)
		var c := laser_color
		c.a = a
		mat.albedo_color = c
		mat.emission_energy_multiplier = a * 5.0
	return hit

# --- WeaponHost aim contract: from the muzzle toward the player, no camera ---
func get_aim_origin() -> Vector3:
	return _muzzle.global_position if _muzzle else global_position

func get_aim_direction() -> Vector3:
	if not is_instance_valid(_target) or not _muzzle:
		return global_basis.z
	return (_aim_point() - _muzzle.global_position).normalized()

func get_aim_basis() -> Basis:
	var dir := get_aim_direction()
	# Avoid a degenerate basis if we're ever aiming near-straight up/down.
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	return Basis.looking_at(dir, up)
