class_name NpcCombat
extends Node

## NPC combat FIRING dispatch, extracted off npc.gd (H2). Owns the per-frame ARMED body (act_alerted: pursue to
## engage range -> aim/telegraph -> reload-when-dry -> charge -> fire, with a combat dodge) and the UNARMED body
## (act_unarmed: close to fist reach -> wind up -> punch), plus the combat-dodge bookkeeping. The GOAP FireArmed /
## FireUnarmed actions call host._act_alerted / host._act_unarmed, now thin facades onto here — the within-frame
## interleaving (reload-while-closing, dodge, fire) stays in ONE place.
##
## `host` is Node-typed to break the NpcCombat <-> NPC class cycle, so every host.X is a DYNAMIC call — see the
## host-facade table in scripts/npc/README.md and grep before renaming an npc.gd member this reads.
##
## STATE SPLIT: the combat-dodge bookkeeping (_dodge_cd / _dodge_t / _dodge_dir + DODGE_MIN_INTERVAL) and the
## burst-fire bookkeeping (_burst_* + the BURST_* dials, WeaponData.npc_burst_count) live HERE. The
## shared attack timers (_fire_timer / _charging / _warned / _shot_miss) STAY on the host — npc.gd._physics_process
## bleeds _fire_timer every frame, get_aim_direction consumes _shot_miss, and a melee<->ranged switch reads
## _charging / _warned — so this component reads/writes them through host. Built in NPC._build_components.

const FISTS: WeaponData = preload("res://resources/weapons/fists.tres")
## SANITY FLOOR: the dodge re-arm interval is clamped to at least this so an over-tuned dodge_interval can't jitter.
const DODGE_MIN_INTERVAL := 2.0
## Below this ground speed (m/s, squared) a target counts as STANDING STILL and gets no lead — collision
## jitter and a single frame of navmesh drift are not movement worth predicting.
const LEAD_MIN_SPEED_SQ := 0.04  # (0.2 m/s)^2
## Coefficient magnitude under which the intercept quadratic is treated as degenerate (target receding at
## exactly the round's own speed) and solved as a linear equation instead.
const LEAD_QUADRATIC_EPSILON := 0.0001
## Below this squared cross-product length two aim directions share no unique rotation PLANE (they are
## collinear — identical or exactly opposed), so slew_toward has to invent an axis rather than normalise a
## zero vector. Sized well above float noise at unit length.
const AIM_SLEW_AXIS_EPSILON := 1e-12
## SANITY FLOOR (seconds) on the gap between two rounds of a BURST — roughly two physics frames, so a weapon
## authored with a zero/negative npc_burst_interval AND a zero attack_speed can't try to empty its clip in one tick.
const MIN_BURST_INTERVAL := 0.03
## How long (seconds) a burst HOLDS its remaining rounds while the shot is momentarily un-takeable before writing
## them off. A trigger squeeze is committed: measured in a live firefight the clear-shot test flickers for single
## frames mid-burst (the NPC's own round crossing its LOS ray, a limb collider answering instead of the body), and
## without this grace roughly a quarter of every SMG burst was truncated to one round for no reason a player could
## see. It does NOT let a round through — every round still passes the full clear-shot gate at the instant it
## fires — so a target that genuinely reaches cover eats nothing; the burst just doesn't forget itself over a blink.
const BURST_LOST_GRACE := 0.15
## Extra seconds (on top of the string's own span) a burst is allowed to take before its owed rounds expire. This is
## the ABANDONMENT guard, measured in real frames rather than in act_alerted calls, because the case it catches is
## act_alerted no longer running at all: a GOAP replan away from FireArmed (perception dropped, we were disarmed, a
## coward bolted) has no exit hook to clear the burst, and without an expiry those rounds would be spat out with no
## wind-up whenever combat resumed. Sized well above the worst legitimate stretch — an AI-LOD far-band NPC thinks
## only every lod_far_interval, so its burst takes several thinks to walk out.
const BURST_WINDOW_SLACK := 0.75

var host: Node = null  ## the NPC we fight for (Node-typed to avoid the class cycle)

## Combat-dodge bookkeeping (Feature #5, used only by a combatant in act_alerted). _dodge_cd counts down to the next
## dodge ROLL; _dodge_t is the remaining time of an ACTIVE strafe burst (> 0 = mid-dodge); _dodge_dir is the chosen
## lateral world direction held for that burst.
var _dodge_cd: float = 0.0
var _dodge_t: float = 0.0
var _dodge_dir: Vector3 = Vector3.ZERO

## BURST-FIRE bookkeeping (WeaponData.npc_burst_count). _burst_left is how many rounds of the CURRENT burst are
## still OWED after the one already downrange (0 = not mid-burst — the single-shot default every non-bursting
## weapon sits at forever); _burst_gap counts down to the next of them at the gun's own cyclic rate; _burst_lost
## accumulates the time the shot has been un-takeable inside the string (BURST_LOST_GRACE); _burst_deadline is the
## physics frame the whole string expires on (BURST_WINDOW_SLACK). Lives HERE beside the dodge state, and
## deliberately gets NO cadence timer of its own: every round re-arms the host's full _shot_interval() (see
## _fire_round), so the owed rounds ride _burst_gap alone and a burst abandoned mid-string leaves the NPC already
## paying the normal between-shots cadence.
var _burst_left: int = 0
var _burst_gap: float = 0.0
var _burst_lost: float = 0.0
var _burst_deadline: int = 0


## NPC-pooling reuse reset (NpcPool): clear the dodge state so a reused NPC doesn't strafe sideways on its first
## combat frame from a mid-burst death (_dodge_t > 0 overrides _desired_velocity) and its dodge cadence is
## deterministic. The host-owned fire timers (_fire_timer/_charging/_warned/_shot_miss) are reset by NPC itself.
func reset_for_reuse() -> void:
	_dodge_cd = 0.0
	_dodge_t = 0.0
	_dodge_dir = Vector3.ZERO
	# Drop any half-fired burst: a body that died mid-string would otherwise owe those rounds on its next life
	# and spit them out on its first armed frame, ahead of the fresh wind-up NPC.reset_for_reuse just seeded.
	_burst_left = 0
	_burst_gap = 0.0
	_burst_lost = 0.0
	_burst_deadline = 0


func act_alerted(delta: float) -> void:
	var aim: Vector3 = host._aim_point()
	# How close we WANT to be SCALES with the weapon (see _engage_range): close until comfortably inside that
	# engage range (engage_range_fraction pulls it just inside), then hold + fire. Every ranged shot we take
	# is a LIVE projectile (enemies never hitscan — ShotResolver.ai_fires_live_projectile), so all of this
	# gating decides when the trigger pulls, never where damage stops.
	var engage_dist: float = host._engage_range()
	# How far we'll actually TAKE the shot: the engage range plus the projectile GRACE BAND (attempt_fire_range).
	# Between the two the NPC fires WHILE still closing, so a kiting target takes dodgeable projectile fire out
	# here instead of enjoying a silent chase it can backpedal forever. The chase target stays engage_dist —
	# grace never makes an NPC hold position farther out, it only lets the trigger work on the way in.
	var attempt_dist: float = attempt_fire_range(
			engage_dist, host._weapon.equipped_weapon, GameSettings.npc_ai.fire_grace_range)
	var dist: float = host.global_position.distance_to(aim)
	host._face_point(aim, delta)  # keep aiming at the target even while strafing, so a dodge reads as a sidestep
	# Laser opacity AND the player's aim radial reflect a ranged shot's charge: 0 right after firing,
	# ramping to 1 (opaque / about to fire) as the cooldown elapses. Melee weapons still use this attack
	# path, but suppress the ranged warning package so they read like close-range swings.
	var uses_ranged_telegraphs: bool = host._current_weapon_uses_ranged_attack_telegraphs()
	if not uses_ranged_telegraphs:
		host._aim_sfx_delay = -1.0
	var charge := clampf(1.0 - host._fire_timer / maxf(host._shot_interval(), 0.001), 0.0, 1.0)
	var hit: Dictionary = host._aim_laser_at(aim, charge, uses_ranged_telegraphs)
	# Point-blank override: when the target is right on top of us the LOS ray starts INSIDE its collider and
	# registers NO hit (Godot rays ignore the shape they begin in), which used to read as "no clear shot" — so
	# an enemy crowded by the player, or one charged down by a melee NPC, just stood there holding fire. Within
	# point-blank range (GameSettings.npc_ai) we treat the shot as clear regardless (you're touching them;
	# you can pull the trigger).
	var clear: bool = (not hit.is_empty() and hit.get("collider") == host._target) \
			or dist <= GameSettings.npc_ai.point_blank_range
	var target_climb: float = _target_climb_to(host._target_body, aim)
	if should_chase_while_alerted(clear, dist, engage_dist, host.engage_range_fraction, target_climb):
		host._move_toward(aim, true, host._target_body)  # pursuit: allow the nav-hop so it vaults a low crate to close on you
	else:
		# Combat dodge (Feature #5): occasionally break into a brief lateral strafe instead of holding still.
		# Only dodge while holding a usable firing spot; if LOS is blocked or the target is on a ledge, movement
		# pressure wins so the strafe burst cannot overwrite the pathing that gets the NPC unstuck.
		_maybe_dodge(delta, aim)
	# Reload the instant we run dry — even with no clear shot or out of range — so the enemy ducks
	# and reloads behind cover instead of standing empty until you peek. AI has no reload input, so
	# trigger it directly; is_busy() then blocks the fire below until the fresh clip is up.
	if host._weapon.current_ammo == 0 and not host._weapon.is_busy() and host._weapon.ammo != null and host._weapon.ammo.has_reload_supply():
		host._weapon.reload()
		host._try_reload_bark()
	# A shot only winds up with a clear line, the target inside our ATTEMPT range (engage + the projectile
	# grace band, computed above — a projectile weapon may pull the trigger past its nominal engage range),
	# AND the weapon actually READY: not mid-reload/swap and with ammo. Gating the WIND-UP on readiness (not
	# just the fire) makes the NPC visibly pause to reload instead of charging straight through the reload
	# and firing the instant the fresh clip lands.
	var can_shoot: bool = clear and dist <= attempt_dist \
			and not host._weapon.is_busy() and host._weapon.current_ammo != 0
	if can_shoot:
		if not host._charging:
			host._charging = true
			if uses_ranged_telegraphs:
				host._on_aim()  # lock-on charge sting, now only once we can actually hit you
		# _physics_process bled the timer +delta this frame; subtract 2*delta to net the -delta wind-up.
		host._fire_timer = maxf(0.0, host._fire_timer - 2.0 * delta)
		# Incoming-shot warning: a beat before the shot, beep 2D so the player always hears it. The
		# beep_lead_time window (GameSettings.npc_ai) is our firing cadence; the beep's mix/pitch is the audio child's.
		# ONE beep per BURST, not per round: mid-burst (_burst_left > 0) the rounds are already arriving, so a
		# warning is both too late and wrong — it re-arms for the NEXT burst once the string finishes.
		if uses_ranged_telegraphs and not host._warned and _burst_left <= 0 \
				and host._fire_timer <= GameSettings.npc_ai.beep_lead_time \
				and is_instance_valid(host._target) and host._target.is_in_group(Groups.PLAYER):
			host._warned = true
			if host._audio_cues != null:
				host._audio_cues.play_incoming_beep()
	else:
		# Lost the shot (LOS broken / out of range): the charge bleeds back down in _physics_process.
		# Re-arm the per-shot STING so RE-acquiring the target re-telegraphs; AIM_COOLDOWN_MS throttles it so a
		# fast peek can't spam it. (The FIRST lock-on is now telegraphed range-independently by _on_locked_on off
		# Perception.just_alerted, so this re-arm only covers later re-acquisitions, not the initial run-in.) The
		# louder incoming BEEP still only re-arms on a FULL bleed, so it won't re-warn on every bob.
		host._charging = false
		if host._fire_timer >= host._shot_interval():
			host._warned = false
	# BURST FIRE (WeaponData.npc_burst_count — the SMG ships 3). The FIRST round of a burst is the ordinary
	# telegraphed trigger pull in the `elif` below; the 2nd..Nth are OWED rounds that ride _burst_gap at the gun's
	# own cyclic rate, independent of the far slower telegraph cadence every round re-arms. So an automatic weapon
	# reads brrrp / breathe / brrrp instead of one paced shot, while the breathing floor keeps owning the gap
	# BETWEEN bursts. A weapon left at the default count of 1 never enters the first branch at all — its
	# `_burst_left` is 0 forever and the fire path is byte-identical to before bursts existed.
	var burst_weapon: WeaponData = host._weapon.equipped_weapon
	if _burst_left > 0:
		if Engine.get_physics_frames() > _burst_deadline or host._weapon.current_ammo == 0:
			# Expired (act_alerted stopped running mid-string — see BURST_WINDOW_SLACK) or the clip ran dry: the
			# owed rounds are written off. A dry gun's next trigger pull belongs to the reload above, not here.
			_burst_left = 0
		elif not can_shoot:
			# The shot is momentarily un-takeable. HOLD the rest of the string through a brief flicker
			# (BURST_LOST_GRACE) but fire nothing — a round only ever leaves the barrel on a frame that passes
			# the full clear-shot gate, so a target that actually reaches cover still eats nothing.
			_burst_lost += delta
			if _burst_lost > BURST_LOST_GRACE:
				_burst_left = 0
		else:
			_burst_lost = 0.0
			_burst_gap -= delta
			# The weapon's OWN cadence timer is the hard ceiling, and at the default interval (attack_speed) the
			# two land on the same frame — so WAIT for it rather than spend an owed round on a refused shot.
			# (Under AI LOD a distant NPC thinks every lod_*_interval, so its burst simply stretches to that.)
			if _burst_gap <= 0.0 and not _weapon_shot_in_progress():
				_fire_round()
				_burst_left -= 1
				_burst_gap = burst_interval_for(burst_weapon)
	elif can_shoot and host._fire_timer <= 0.0 and host._weapon.current_ammo != 0:
		_fire_round()
		_burst_left = burst_rounds_for(burst_weapon) - 1
		_burst_gap = burst_interval_for(burst_weapon)
		_burst_lost = 0.0
		_burst_deadline = Engine.get_physics_frames() + burst_window_frames(burst_weapon)
	# Pass whether we can actually fire on the player RIGHT NOW: the glint clears the instant we lose the
	# clear shot, instead of lingering at our position through the post-shot / lost-LOS charge bleed.
	if uses_ranged_telegraphs:
		host._report_aim(charge, can_shoot)
	else:
		host._report_aim(0.0, false)


## Send ONE round downrange and re-arm the shared telegraph cadence — the body of a trigger pull, shared by the
## FIRST round of a burst and every owed round after it, so a bursting weapon and a single-shot one fire through
## exactly the same code. The miss roll is PER ROUND rather than per burst, so a spray partly connects instead of
## whiffing as a block. Every round re-arms the host's FULL _shot_interval(): the owed rounds ride _burst_gap
## instead, so nothing here can fire early, and a burst abandoned mid-string leaves the cadence already paid.
func _fire_round() -> void:
	# Roll a miss only on shots AT THE PLAYER ("npcs firing at you"); on a miss the shot deflects wide
	# (get_aim_direction consumes _shot_miss) and a ricochet whiffs past. Default miss_chance 0 = never.
	host._shot_miss = host.miss_chance > 0.0 \
			and is_instance_valid(host._target) and host._target.is_in_group(Groups.PLAYER) \
			and randf() < host.miss_chance
	host._weapon.attack.try_fire()
	host._emit_gunfire_noise()  # GA-2: let allies HEAR the shot on the &"noise" channel (throttled; opt-in)
	if host._shot_miss and host._audio_cues != null:
		host._audio_cues.play_miss()
	host._fire_timer = host._shot_interval()
	host._warned = false  # re-arm the warning for the next shot
	# Drop back to "not charging" so the next shot's lock-on sting only re-fires if we're STILL in
	# range next frame. A melee swing that knocks the player out of range then won't phantom-charge
	# (and re-play the sting) the instant the attack finishes; it re-stings when it re-closes to range.
	host._charging = false


## True while the weapon's own cadence timer is still running from the last round (Attack.is_shot_in_progress).
## A burst asks BEFORE spending an owed round: WeaponData.attack_speed is the gun's hard ceiling and Attack
## silently REFUSES a shot inside it, so at the default burst interval (attack_speed itself) a one-frame race
## between the physics tick and that idle-processed Timer would otherwise eat rounds out of the middle of a burst.
func _weapon_shot_in_progress() -> bool:
	if host._weapon == null:
		return false
	var atk = host._weapon.attack  # duck-typed off the Node-typed host (Attack; null on a stub weapon)
	return atk != null and atk.is_shot_in_progress()


## How many rounds an NPC wielding `w` answers ONE trigger pull with — WeaponData.npc_burst_count, floored at the
## single aimed shot so an unauthored (or nonsense) weapon behaves exactly as it did before bursts existed.
## Pure + static (the attempt_fire_range idiom) so tests pin the burst against the authored .tres with no live NPC.
static func burst_rounds_for(w: WeaponData) -> int:
	if w == null:
		return 1
	return maxi(1, w.npc_burst_count)


## Seconds between the rounds INSIDE that burst: the weapon's authored npc_burst_interval, or — at its 0 default —
## the gun's own cyclic rate, attack_speed. Held above MIN_BURST_INTERVAL so a weapon authoring neither can't try
## to empty its clip in a single frame. Pure + static, same reason as burst_rounds_for.
static func burst_interval_for(w: WeaponData) -> float:
	if w == null:
		return MIN_BURST_INTERVAL
	if w.npc_burst_interval > 0.0:
		return maxf(MIN_BURST_INTERVAL, w.npc_burst_interval)
	return maxf(MIN_BURST_INTERVAL, w.attack_speed)


## How many physics frames a burst has to finish in before its owed rounds expire: the string's own span plus
## BURST_WINDOW_SLACK. Real frames rather than think ticks, because the case this catches is act_alerted no longer
## being called at all (a GOAP replan away from FireArmed, which has no exit hook to clear the burst with).
## Deliberately generous — a resumed round still has to pass the whole clear-shot gate to leave the barrel, so the
## only thing an over-long window costs is a round that skipped its wind-up telegraph.
static func burst_window_frames(w: WeaponData) -> int:
	var span: float = (burst_rounds_for(w) - 1) * burst_interval_for(w) + BURST_WINDOW_SLACK
	return maxi(1, int(ceil(span * float(maxi(1, Engine.physics_ticks_per_second)))))


## The distance an armed NPC still ATTEMPTS a shot at: the weapon-scaled engage range, extended by the
## projectile grace band (GameSettings.npc_ai.fire_grace_range) for a weapon that spawns physical rounds
## (WeaponData.projectile_scene). Since the "enemies never hitscan" rule (2026-08-25,
## ShotResolver.ai_fires_live_projectile) EVERY ranged AI shot is a live round whose damage rides the flight
## — effective_range caps nothing for AI any more — so this band is purely about how far past the engage
## standoff the trigger still pulls, instead of letting a kiting target backpedal a short-range gun forever.
## A weapon with NO projectile_scene gets no grace: for AI that now means MELEE, whose reach really is the
## short damage trace, so an out-of-band attempt would be a guaranteed miss. An effective_range-0 weapon
## (the lobbed rock) gets no grace EITHER, even though it spawns projectiles: its engage range is already
## the unranged-fallback guess, and its flat ballistic lob grounds inside that fallback, so band shots would
## be guaranteed-miss theater while burning finite thrown ammo. Negative grace clamps to none — it must
## never SHRINK the fire range.
## Pure + static (the should_chase_while_alerted idiom) so tests pin it against the authored WeaponData .tres.
static func attempt_fire_range(engage_range: float, weapon: WeaponData, grace_range: float) -> float:
	if weapon != null and weapon.projectile_scene != null and weapon.effective_range > 0.0:
		return engage_range + maxf(0.0, grace_range)
	return engage_range


## TARGET LEADING — where to actually aim a travelling round so it MEETS a moving target instead of
## chasing it. Solves the real intercept quadratic: find the flight time t at which the round (launched
## from `origin` at `round_speed`) and the target (at `target_pos`, drifting at `target_velocity`) are in
## the same place, then return the point the target reaches at t.
##
## WHY: since the "enemies never hitscan" rule (2026-08-25, ShotResolver.ai_fires_live_projectile) EVERY
## ranged AI shot is a physical round with real travel time — but the NPC still aimed at the target's
## CURRENT position, so holding a strafe walked you out of the bullet's path and incoming fire could be
## dodged indefinitely without ever changing direction. Aiming at the intercept is what makes travel time a
## dodge WINDOW (juke and the prediction is wrong) instead of a free pass.
##
## Only the HORIZONTAL component of `target_velocity` is led. A jumping or falling target is on a gravity
## arc, and extrapolating its instantaneous vertical velocity linearly would sling the aim metres over its
## head on the way up (and into the floor on the way down) — strafing is the dodge this is here to answer,
## so vertical is deliberately left un-led and hopping still throws aim off.
##
## `lead_fraction` scales the resulting OFFSET, not the solve: 1.0 is the exact intercept, 0 aims at the
## target's navel (the old behaviour), and anything between under-leads by that share of the drift — the
## per-NPC marksmanship dial (NPC.aim_lead_fraction). `max_lead_time` clamps the predicted flight so a
## degenerate solve (or a target further out than its round usefully reaches) can't aim metres into a wall.
##
## Degenerate inputs all fall back to `target_pos` — no lead is always a legal aim point: no round speed,
## no lead budget, a target that isn't meaningfully moving, or a target moving AWAY faster than the round
## flies (no real root: nothing can catch it, so don't invent a lead).
## Pure + static (the attempt_fire_range idiom) so tests pin the geometry without a tree.
static func lead_aim_point(
		origin: Vector3,
		target_pos: Vector3,
		target_velocity: Vector3,
		round_speed: float,
		lead_fraction: float,
		max_lead_time: float) -> Vector3:
	if round_speed <= 0.0 or lead_fraction <= 0.0 or max_lead_time <= 0.0:
		return target_pos
	var vel := target_velocity
	vel.y = 0.0  # horizontal only — see the note above on gravity arcs
	if vel.length_squared() < LEAD_MIN_SPEED_SQ:
		return target_pos  # standing still (or drifting imperceptibly): nothing to lead
	var to_target := target_pos - origin
	# |to_target + vel*t| = round_speed*t  ->  (|vel|^2 - speed^2) t^2 + 2 (to_target . vel) t + |to_target|^2 = 0
	var a := vel.length_squared() - round_speed * round_speed
	var b := 2.0 * to_target.dot(vel)
	var c := to_target.length_squared()
	var t := -1.0
	if absf(a) < LEAD_QUADRATIC_EPSILON:
		# Target receding at exactly the round's speed: the quadratic collapses to a line.
		if absf(b) > LEAD_QUADRATIC_EPSILON:
			t = -c / b
	else:
		var disc := b * b - 4.0 * a * c
		if disc >= 0.0:
			var root := sqrt(disc)
			# Two candidate flight times; take the SOONEST one that lies in the future. (While the round
			# outruns the target — every shipped case — a is negative and exactly one root is positive.)
			var t1 := (-b + root) / (2.0 * a)
			var t2 := (-b - root) / (2.0 * a)
			for candidate: float in [minf(t1, t2), maxf(t1, t2)]:
				if candidate > 0.0:
					t = candidate
					break
	if t <= 0.0:
		return target_pos  # unreachable / no intercept — aim at the body rather than at a guess
	return target_pos + vel * minf(t, max_lead_time) * lead_fraction


## AIM INERTIA: rotate `current` toward `goal` by AT MOST `max_step_rad`, and return the unit direction that
## lands on. The geometry half of "an NPC's aim has to swing onto you" — NPC._tick_aim_tracking calls this once
## a physics frame with `aim_turn_rate() * delta` and keeps the result as the direction its shots actually fly.
##
## WHY a hard rate cap rather than a smoothing ease: the cap has ZERO steady-state error. Once the required
## turn rate drops under the cap this returns `goal` EXACTLY, so an NPC tracking an ordinary strafe is aimed
## precisely at the intercept lead_aim_point solved — the 2026-08-26 "holding a strafe dodges forever" fix
## stays fully intact. An exponential ease would instead leave a permanent angular lag proportional to your
## lateral speed, which is exactly that infinite dodge handed back. The cost is paid on CHANGE only: acquiring,
## re-acquiring from a new angle, a dash, an about-face, a close-range circle strafe.
##
## Degenerate inputs all fall back to snapping onto `goal` (a legal aim is always better than a stuck one): a
## zero-length goal is refused outright by returning `current` (nothing to aim at), an un-seeded `current`
## and a non-positive step both mean "no inertia yet / none configured".
## Pure + static (the attempt_fire_range idiom) so tests pin the geometry without a tree.
static func slew_toward(current: Vector3, goal: Vector3, max_step_rad: float) -> Vector3:
	var to := goal.normalized()
	if to.is_zero_approx():
		return current  # no aim point at all — hold what we have
	var from := current.normalized()
	if from.is_zero_approx() or max_step_rad <= 0.0:
		return to  # never tracked before, or the cap is switched off: snap (the pre-inertia behaviour)
	var angle := from.angle_to(to)
	if angle <= max_step_rad:
		return to  # within reach this frame — land EXACTLY on the goal, so tracking has no residual lag
	var axis := from.cross(to)
	if axis.length_squared() < AIM_SLEW_AXIS_EPSILON:
		# Collinear: either already there (caught by the angle test above) or aiming EXACTLY 180 deg away, where
		# every plane is an equally valid way round. Pick a stable perpendicular so a target dead behind still
		# costs a full about-face instead of snapping; UP fails only when `from` is itself vertical.
		axis = from.cross(Vector3.UP)
		if axis.length_squared() < AIM_SLEW_AXIS_EPSILON:
			axis = from.cross(Vector3.RIGHT)
	return from.rotated(axis.normalized(), max_step_rad).normalized()


static func should_chase_while_alerted(
		clear_shot: bool,
		distance: float,
		engage_distance: float,
		engage_fraction: float,
		target_climb: float) -> bool:
	if distance > engage_distance * engage_fraction:
		return true
	if not clear_shot:
		return true
	return absf(target_climb) > Locomotor.HOP_MIN_CLIMB


func _target_climb_to(target_body: Variant, fallback_target: Vector3) -> float:
	var host_body := host as Node3D
	if host_body == null:
		return 0.0
	var target_node := target_body as Node3D
	var target_floor: float = Locomotor.collision_bottom_y(target_node, fallback_target.y) if is_instance_valid(target_node) else fallback_target.y
	var self_floor: float = Locomotor.collision_bottom_y(host_body, host_body.global_position.y)
	return target_floor - self_floor


## Unarmed melee fallback (a combatant with no usable gun, OR a civilian brawler): close to fist reach, then
## wind up the punch silently. It deliberately does NOT paint the laser, charge sting, incoming-shot beep, or
## player's aim radial: a punch is not a ranged shot. Reuses _fire_timer + _shot_interval() (the fist cadence).
## The hit (_punch) applies directly via take_damage, so a struck neutral grudges us back.
func act_unarmed(delta: float) -> void:
	# Unarmed and ALERTED: grabbing a nearby weapon beats punching — while NpcScavenge has a reachable
	# upgrade it owns the locomotion; the fists charge resumes the instant there's nothing to grab.
	if host._scavenge != null and host._scavenge.act(delta):
		return
	var aim: Vector3 = host._aim_point()
	var dist: float = host.global_position.distance_to(aim)
	var reach: float = host._engage_range()  # FISTS' reach while unarmed — same weapon-scaled engage logic as the gun
	if dist > reach * host.engage_range_fraction:
		host._move_toward(aim, true, host._target_body)  # close the gap to fist reach; allow the hop so it vaults up after you
	host._face_point(aim, delta)
	# No ranged laser/radial package for fists; close-range swings are read from movement and animation/audio.
	host._hide_laser()
	var can_punch: bool = dist <= reach and is_instance_valid(host._target)
	if can_punch:
		# A punch winds up SILENTLY — NO lock-on charge sting (that's the ranged sniper-charge sound; it read
		# wrong on a melee swing). _charging still tracks the wind-up so a melee->ranged switch stays clean.
		host._charging = true
		# _physics_process bled the timer +delta this frame; subtract 2*delta to net the -delta wind-up.
		host._fire_timer = maxf(0.0, host._fire_timer - 2.0 * delta)
		# NOTE: no incoming-shot beep here either — the beep is ranged-only (it was annoying firing on every
		# punch). _warned stays managed below for a melee->ranged switch.
	else:
		# Out of reach: the wind-up bleeds back up (in _physics_process); re-arm the telegraph for re-closing.
		host._charging = false
		if host._fire_timer >= host._shot_interval():
			host._warned = false
	if can_punch and host._fire_timer <= 0.0:
		_punch()
		host._fire_timer = host._shot_interval()
		host._warned = false
		host._charging = false
	# Fists do NOT paint the player's ranged aim warning. Clear it every frame so a prior gun threat
	# cannot linger through the chase.
	host._report_aim(0.0, false)


## Land one weak fist hit on the current target (player or NPC — both are Characters). Routed through
## take_damage, so it triggers the victim's hurt feedback and (for an NPC) the damage-grudge.
func _punch() -> void:
	var victim := host._target as Character
	if victim != null:
		victim.take_damage(FISTS.damage, false, host, host._aim_point())
		# SWAT the victim back -- up and away horizontally -- through the SAME decaying blast impulse the player
		# (apply_blast) and NPCs (apply_velocity) already consume for rocket-jumps / explosions: a horizontal push
		# AWAY from us PLUS an upward lift, so a punch sends them flying like a backhand. Reuses FISTS' enemy_knockback
		# / enemy_lift (tunable on fists.tres); skips a knockback-immune NPC (the player has no such field, so it's
		# always swatted). is_instance_valid guards a fatal punch that already freed the victim.
		if is_instance_valid(victim) and not victim.get(&"immune_to_weapon_knockback"):
			var away: Vector3 = victim.global_position - host.global_position
			away.y = 0.0
			var dir: Vector3 = away.normalized() if away.length_squared() > 0.0001 else host.global_basis.z
			victim.explosion_velocity += dir * FISTS.enemy_knockback + Vector3.UP * FISTS.enemy_lift
	# Throw the fist-strike flail on the swapped arms (drop-in BodyModelSwap), if one's attached -- arms snap up
	# and over toward the target, then ease back to the side. Duck-typed; a non-swapped NPC just has no arms to flail.
	var swap: Node = host._find_body_swap()
	if swap != null and swap.has_method(&"strike"):
		swap.call(&"strike")


## Combat dodge (Feature #5): occasionally sidestep instead of standing still while ALERTED on a live
## target. Two phases sharing the dodge_* tuning: an ACTIVE burst (_dodge_t > 0) drives _desired_velocity
## sideways at dodge_speed_fraction of move_speed — overriding the hold/pursuit set by act_alerted — and
## otherwise a cooldown (_dodge_cd) counts down to the next ROLL, which on success (dodge_chance) picks a
## fresh left/right lateral direction relative to the target and opens a dodge_duration burst. The strafe
## flows through the normal locomotion in apply_velocity() (no teleport, navmesh pathing untouched), so a
## subtle, cooldown-gated weave — not constant jitter. dodge_chance 0 disables it; only ever called with a
## live combat target (from act_alerted), so it never fires while idle/searching.
func _maybe_dodge(delta: float, aim: Vector3) -> void:
	if _dodge_t > 0.0:
		# Mid-burst: keep driving the chosen lateral direction (overriding pursuit/hold) until it elapses.
		_dodge_t -= delta
		host._desired_velocity = _dodge_dir * host.move_speed * host.dodge_speed_fraction
		return
	_dodge_cd -= delta
	if _dodge_cd > 0.0 or host.dodge_chance <= 0.0:
		return
	_dodge_cd = maxf(host.dodge_interval, DODGE_MIN_INTERVAL)  # rolled this cycle — re-arm (floored so it can't constantly jitter)
	if randf() >= host.dodge_chance:
		return
	# Lateral = horizontal perpendicular to the flat us->target vector, flipped to a random side. Degenerate
	# (standing on the target) -> skip the dodge this cycle rather than strafe in a meaningless direction.
	var to: Vector3 = aim - host.global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	var lateral: Vector3 = to.normalized().cross(Vector3.UP)  # perpendicular in the ground plane
	_dodge_dir = lateral if randf() < 0.5 else -lateral
	_dodge_t = host.dodge_duration
	host._desired_velocity = _dodge_dir * host.move_speed * host.dodge_speed_fraction
