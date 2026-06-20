class_name Perception
extends Node3D

## An enemy's senses + awareness state machine. The owner feeds it a target (the player or another
## NPC) and calls sense() each frame; Perception decides what the enemy KNOWS — whether it currently
## perceives the target and how alert it is — while the owner decides what to DO about it.
##
## Vision is a range + horizontal view-cone + line-of-sight test. A detection meter fills
## while the target is perceived and drains when it isn't, so a glimpse isn't an instant
## alert; losing an ALERTED target drops the enemy into INVESTIGATING (wary at the last-known
## spot) before it finally forgets. As a child of the enemy it inherits the enemy's transform,
## so the cone points along the enemy's facing automatically. (Hearing is OR-ed into the
## perceived test in a later slice.)

enum State { UNAWARE, DETECTING, ALERTED, INVESTIGATING }
## A graded awareness tier (finer than the 4 states) for HUD feedback + a read-only planner fact. Derived from
## state + the detection meter via suspicion(); CALM (oblivious) -> WARY -> SUSPICIOUS -> ALERTED (locked on).
enum SuspicionTier { CALM, WARY, SUSPICIOUS, ALERTED }

## Emitted the instant the enemy FIRST becomes aware of the player by ANY sense (sight -> DETECTING
## or sound -> INVESTIGATING), before the meter fills. Drives the MGS "!" alert sting.
signal just_spotted
## Emitted when the enemy locks on / becomes ALERTED (about to fire). Drives the sniper charge sfx.
signal just_alerted

@export_group("Sight")
## How far the enemy can see.
@export var sight_range: float = 25.0
## Multiplier on sight_range while the TARGET is fully crouched — crouching shrinks the range an enemy
## spots you at (stealth). 1.0 = crouch doesn't help; 0.5 = spotted only at half range when fully crouched.
@export_range(0.0, 1.0) var crouch_sight_mult: float = 0.5
## Full horizontal view-cone angle (degrees); the target must be within half this off the
## enemy's forward (+Z, the model's front) to be seen.
@export var fov_degrees: float = 110.0
## Height above the enemy origin that sight rays start from (the "eyes").
@export var eye_height: float = 1.4

@export_group("Sight Falloff")
## Visibility (0..1) vs the target's normalized distance into sight range (0 = point-blank, 1 = at max range):
## scales how fast the detection meter fills. UNSET (null) = no distance falloff (1.0 everywhere), so the
## default reproduces today's hard in-range detection exactly.
@export var range_falloff: Curve = null
## Visibility (0..1) vs the target's normalized angle off the cone centre (0 = dead ahead, 1 = cone edge).
## Unset = no peripheral falloff. Lets the edge of the view cone notice you slower than dead-centre.
@export var peripheral_falloff: Curve = null
## Visibility (0..1) vs the target's light EXPOSURE (0 = pitch dark, 1 = fully lit) — read off the target's
## `light_exposure` (a PlayerLightLevel writes it). Unset = light ignored (enemies see through dark, as today);
## author it (0 -> low, 1 -> 1.0) so a target in shadow fills the meter slower / not at all.
@export var light_falloff: Curve = null
## Floor on the combined visibility factor, so a genuine in-cone line-of-sight sighting still fills the meter to
## ALERTED eventually (just slowly at the far / peripheral / dark fringes). Only matters when a falloff curve is set.
@export_range(0.0, 1.0) var min_visibility: float = 0.15

@export_group("Awareness Timing")
## Seconds of continuous perception to go from first-noticed to fully ALERTED.
@export var time_to_detect: float = 1.0
## Seconds the enemy stays wary at the last-known spot after losing the target before it
## gives up and goes UNAWARE.
@export var forget_time: float = 4.0

@export_group("Hearing")
## Can this enemy hear the player's noise (gunfire, fast movement)? Crouch-walking is silent.
@export var hearing: bool = true

@export_group("Suspicion (feedback)")
## Detection-meter level at/above which suspicion() reads WARY (a faint "did I see something?"). Below it,
## and not ALERTED, the enemy reads CALM.
@export_range(0.0, 1.0) var suspicion_wary_threshold: float = 0.15
## Detection-meter level at/above which suspicion() reads SUSPICIOUS (closing on a lock). At/above 1.0 the
## state is ALERTED anyway, which always wins.
@export_range(0.0, 1.0) var suspicion_suspicious_threshold: float = 0.6

## Set each frame by the owner (the NPC) from is_hostile_to(its current target). When false the
## enemy is non-hostile toward that target right now, so both senses report nothing and the state
## machine idles at UNAWARE — no detection, no alert, no fire. Defaults true so a Perception used
## bare (or by a hostile-by-default enemy that never sets it) behaves exactly as before.
var is_hostile: bool = true

var state: State = State.UNAWARE
var detection: float = 0.0          ## 0..1 awareness meter (also drives the laser glow)
var last_known_position: Vector3
var target: Node3D                  ## the target root — player or NPC (set by the owner)
var target_body: Node3D             ## target's collision shape for LOS; falls back to target

var _investigate_t: float = 0.0

## Per-NPC breadcrumb-search scratch (stealth Slice 8): the uncertainty ring + search-age clock layered ON TOP of
## last_known_position. INERT at the SearchSettings defaults (a single point AT the spot). Reset by forget(). The
## motion that consumes it lives in GoapActionSearch; sense() only seeds it + ages it.
var _search: SearchState = SearchState.new()
## GA-4: a COORDINATED search sector (radians) handed down by an alert distribution (GA-1 gives each ally
## TAU*i/n so a squad sweeps different sectors of the shared origin instead of identical rings). NAN = no
## override -> the per-NPC default (_search_phase). Set by begin_search/investigate_point, cleared by forget().
var _sector_phase_override: float = NAN

## One tick of sensing: refresh whether we perceive the target, then advance the state
## machine + detection meter.
func sense(delta: float) -> void:
	# Sight drives the detection meter up to a fire-ready ALERTED; hearing only ever raises a
	# look-toward-it INVESTIGATING (you can't be shot through a wall just for being heard), and
	# refreshes that wariness while the noise lasts.
	var seen := can_see()
	var heard := can_hear()
	if seen or heard:
		last_known_position = _target_point()
	var prev_state := state
	match state:
		State.UNAWARE:
			if seen:
				state = State.DETECTING
			elif heard:
				state = State.INVESTIGATING
				_investigate_t = forget_time
		State.DETECTING:
			var rate := delta / maxf(time_to_detect, 0.01)
			# Distance/angle/light falloff: a far, cone-edge, or shadowed target fills the meter slower. Computed
			# when any falloff curve applies — including the GLOBAL light curve (rank 27.2), which is on by default
			# but inert until a writer drops light_exposure below 1.0 (so an unlit scene detects exactly as before).
			if seen and (range_falloff != null or peripheral_falloff != null or _effective_light_falloff() != null):
				rate *= visibility_factor(_see_distance_frac(), _see_angle_frac(), _target_light_factor())
			detection = clampf(detection + (rate if seen else -rate), 0.0, 1.0)
			if detection >= 1.0:
				state = State.ALERTED
			elif detection <= 0.0:
				if heard:
					state = State.INVESTIGATING
					_investigate_t = forget_time
				else:
					state = State.UNAWARE
		State.ALERTED:
			detection = 1.0
			if not seen:
				state = State.INVESTIGATING
				_investigate_t = forget_time
		State.INVESTIGATING:
			# Seeing the target here re-enters DETECTING (the meter), NOT an instant ALERTED — so
			# a noise that drew the enemy's eye still makes it fill the detection grace before it
			# attacks. A target lost from ALERTED kept its high detection, so it re-locks fast;
			# a fresh noise-investigation starts near zero, so it has to actually spot you.
			if seen:
				state = State.DETECTING
			else:
				detection = maxf(0.0, detection - delta / maxf(forget_time, 0.01))
				_investigate_t = forget_time if heard else _investigate_t - delta
				if _investigate_t <= 0.0:
					state = State.UNAWARE
					detection = 0.0
	# First noticed by ANY sense -> the MGS "!". Locking on to fire -> the sniper charge cue.
	if prev_state == State.UNAWARE and state != State.UNAWARE:
		just_spotted.emit()
	if state == State.ALERTED and prev_state != State.ALERTED:
		just_alerted.emit()
	# Age + (re)seed the breadcrumb search (stealth Slice 8). Aging grows the uncertainty ring over time; (re)seeding
	# fires ONLY on ENTRY into INVESTIGATING (the stealth investigate_point() path seeds itself, guarded the same
	# way) so a persisting noise re-pointing last_known_position every scan can't thrash the ring. Inert at defaults.
	if state == State.INVESTIGATING:
		_search.elapsed += delta
		if prev_state != State.INVESTIGATING:
			begin_search(GameSettings.search.seed_radius)  # combat lost-LOS: no noise source, so seed from the tuning base

## A graded suspicion tier from the state + detection meter — for HUD feedback and a (read-only) planner fact.
## ALERTED state reads ALERTED; otherwise the meter buckets it: CALM below wary_threshold, WARY up to
## suspicious_threshold, SUSPICIOUS above. (The thresholds stay at the Perception default across NPCs by design —
## they're player-feedback-consistency knobs, intentionally global, unlike the now-per-archetype crouch_sight_mult.)
func suspicion() -> SuspicionTier:
	if state == State.ALERTED:
		return SuspicionTier.ALERTED
	if detection >= suspicion_suspicious_threshold:
		return SuspicionTier.SUSPICIOUS
	if detection >= suspicion_wary_threshold:
		return SuspicionTier.WARY
	return SuspicionTier.CALM

## Keep the investigation alive — the owner is still TRAVELING to the last-known spot, so the give-up
## clock shouldn't be ticking yet. Without this, forget_time measured the WALK + the search together: an
## enemy that lost you across the map spent its whole budget en route and gave up the moment it arrived
## (the "enemies don't really investigate" feel). The owner calls this each frame it's still moving there,
## so forget_time becomes time spent actually SEARCHING at the spot.
func refresh_investigation() -> void:
	if state == State.INVESTIGATING:
		_investigate_t = forget_time

## Force full alert toward a known position — e.g. the enemy just got shot, so it instantly
## knows roughly where you are. sense() takes over next tick: it stays ALERTED while it can
## see you, or turns to investigate the spot (so a shot in the back spins it around).
func alert_to(_position: Vector3) -> void:
	var prev := state
	last_known_position = _position
	detection = 1.0
	state = State.ALERTED
	if prev == State.UNAWARE:
		just_spotted.emit()  # shot out of nowhere still counts as a detection ("!")
	# Intentionally NO just_alerted here: being shot shouldn't replay the sniper charge sting on
	# every hit. That sting fires on a genuine sense-based lock-on + per-shot wind-up instead.

## Send the owner to LOOK at `pos` (a heard noise, a seen body) WITHOUT the full lock-on of alert_to: it
## walks over and searches the spot but doesn't draw + fire on empty air. No-op once already DETECTING or
## ALERTED -- a real target it can see outranks a hunch. sense() takes over next tick (spots the killer en
## route -> DETECTING; finds nothing -> drains over forget_time and forgets). Backs stealth body-discovery and
## the distraction-noise channel -- the engine-side counterpart to alert_to.
##
## `alerting` controls the MGS just_spotted "!" sting on the UNAWARE -> investigate transition: TRUE for a
## NOISE (the player wants to SEE the guard react to a decoy), FALSE for a seen BODY (a corpse is not an enemy
## contact -- the caller fires its own "Hey -- a body!" call-out instead, so the enemy sting/popup + the combat
## detection bark don't mislabel the body or swallow the body line).
## `seed_radius` (Slice 8) sizes the breadcrumb search's uncertainty ring — a loud noise seeds a wider area than a
## faint one (0 until Slice 8.5 wires real per-channel seeds; inert at the SearchSettings defaults regardless).
func investigate_point(pos: Vector3, alerting: bool = true, seed_radius: float = 0.0, sector_phase: float = NAN) -> void:
	if state == State.DETECTING or state == State.ALERTED:
		return
	var prev := state
	last_known_position = pos
	state = State.INVESTIGATING
	_investigate_t = forget_time
	# Seed the search only on ENTRY — a persisting/moving noise re-points last_known_position every scan, and
	# re-seeding each time would thrash the ring (Slice 8.3 re-seeds on a real point move instead). `sector_phase`
	# (GA-4) coordinates a squad's sweep when an alert distributes one; NAN keeps the per-NPC default.
	if prev != State.INVESTIGATING:
		begin_search(seed_radius, sector_phase)
	if alerting and prev == State.UNAWARE:
		just_spotted.emit()

## Forget everything and drop to UNAWARE with a cleared meter. Called by the owner when it has NO valid target
## (the one it was tracking died or left sight_range), so a STALE ALERTED/INVESTIGATING from the instant before
## the target vanished can't linger — with no one to perceive, the enemy is oblivious. sense() then re-escalates
## from scratch when a new target is acquired (a returned target is re-detected, not instantly re-locked).
func forget() -> void:
	state = State.UNAWARE
	detection = 0.0
	_investigate_t = 0.0
	_search.clear()  # a stale widened ring/breadcrumbs must not leak into the next investigation
	_sector_phase_override = NAN  # GA-4: drop a coordinated sector so the next search reverts to the per-NPC default

# --- Search (stealth Slice 8) ---------------------------------------------------------------------------------
# The enriched INVESTIGATING behaviour: a breadcrumb ring around last_known_position whose radius grows with the
# search age and whose intensity falls off over the give-up clock. INERT at the SearchSettings defaults
# (max_search_radius 0 / sample_points 1 / intensity_curve null) -> a single point AT the spot + flat energy =
# today's stare. All pure (no transform reads) so they're off-tree-testable; the MOTION that consumes them lives
# in GoapActionSearch.

## (Re)seed the breadcrumb search around the current last_known_position — called when the enemy ENTERS
## INVESTIGATING (a lost target, a heard noise, a discovered body). `seed_radius` is the channel's uncertainty seed
## (0 until Slice 8.5 wires per-channel seeds); the ring radius is clamped into the SearchSettings min/max, so at
## the inert default (max 0) it lays a single breadcrumb at the spot. Resets the search-age clock (separate from the
## _investigate_t give-up clock, which refresh_investigation keeps decoupled from travel).
func begin_search(seed_radius: float = 0.0, sector_phase: float = NAN) -> void:
	_search.seed_radius = seed_radius
	_search.elapsed = 0.0
	_search.reached_origin = false
	# GA-4: a non-NAN sector_phase is a squad-coordinated sweep sector; a NAN one is a SOLO/combat search and must
	# revert to the per-NPC default. Assigned UNCONDITIONALLY (not just on non-NAN) so a later solo begin_search —
	# combat lost-LOS, a fresh noise investigation, the natural give-up's next entry — can't inherit a stale squad
	# sector from a prior engagement (those paths re-enter here with NAN but never route through forget()).
	_sector_phase_override = sector_phase
	_search.regenerate(last_known_position, search_ring_radius(), effective_samples(), _search_phase())

## True when the search feature is dialed on (a real area to sweep): a positive ring radius AND more than one
## sample point. At the inert default (max_search_radius 0 / sample_points 1) this is false, so GoapActionSearch
## walks last_known_position directly with the legacy in-place sweep — byte-identical to before.
func searching_area() -> bool:
	return search_ring_radius() > 0.0 and GameSettings.search.sample_points > 1

## Step the breadcrumb sweep: advance to the next crumb (reset its travel timer); when the trail is exhausted,
## regenerate a fresh ring at the CURRENT (grown) radius around last_known_position — so the NPC keeps widening its
## sweep until the give-up clock expires. Called by GoapActionSearch on arrival at / time-out of a crumb.
func advance_search() -> void:
	_search.advance()  # resets the per-crumb travel + dwell timers
	if _search.exhausted():
		_search.regenerate(last_known_position, search_ring_radius(), effective_samples(), _search_phase())

## Age the time spent walking toward the current crumb; if it exceeds crumb_timeout the crumb is unreachable
## (off-mesh / walled-in) so skip it. Only called AFTER reaching the search area, so a long initial walk to a far
## last-known spot is never mistaken for a stuck crumb.
func tick_crumb_travel(delta: float) -> void:
	_search.crumb_travel_t += delta
	if _search.crumb_travel_t >= GameSettings.search.crumb_timeout:
		advance_search()

## How many breadcrumbs to lay THIS regeneration: scales from the full sample_points (frantic) down toward 1 (a
## resigned single glance) by search intensity, so a fading search checks fewer places. Always at least 1.
func effective_samples() -> int:
	return maxi(1, int(round(lerpf(1.0, float(GameSettings.search.sample_points), search_intensity()))))

## Seconds to dwell (look around) at the current breadcrumb: lerps from crumb_dwell_max (resigned, intensity 0) to
## crumb_dwell_min (frantic, intensity 1), so the NPC darts between points early and lingers as it gives up.
func crumb_dwell_duration() -> float:
	return lerpf(GameSettings.search.crumb_dwell_max, GameSettings.search.crumb_dwell_min, search_intensity())

## Age the dwell at the current breadcrumb; true once it has lingered past crumb_dwell_duration() (time to move on).
func dwell_elapsed(delta: float) -> bool:
	_search.crumb_dwell_t += delta
	return _search.crumb_dwell_t >= crumb_dwell_duration()

## The current uncertainty radius (m): the seed plus growth over the search age, clamped into the SearchSettings
## min/max. At the inert default (max 0) this is 0 -> a single-point search (today's behaviour).
func search_ring_radius() -> float:
	return clampf(_search.seed_radius + GameSettings.search.uncertainty_grow_rate * _search.elapsed,
		GameSettings.search.min_search_radius, GameSettings.search.max_search_radius)

## Search PROGRESS 0..1: 0 just after (re)seeding (frantic), 1 as the give-up clock runs out. A pure READ of the
## existing _investigate_t / forget_time clock — no parallel timer, so give-up + the lost-interest barks fire on the
## same expiry as before. (A heard noise re-arms _investigate_t, which resets progress toward 0 = frantic again.)
func search_progress() -> float:
	return 1.0 - clampf(_investigate_t / maxf(forget_time, 0.01), 0.0, 1.0)

## Search ENERGY 0..1 driving move urgency / dwell / breadcrumb density: SearchSettings.intensity_curve sampled at
## search_progress(). A NULL curve (the parity default) reads as flat 1.0 (no falloff) — this guard is why leaving
## the curve unset never crashes. An authored falling curve = frantic look first, resigned wander as it gives up.
func search_intensity() -> float:
	var curve: Curve = GameSettings.search.intensity_curve
	if curve == null:
		return 1.0
	return clampf(curve.sample(clampf(search_progress(), 0.0, 1.0)), 0.0, 1.0)

## A stable per-NPC phase offset (radians) so neighbours hearing the same noise don't sweep identical breadcrumb
## rings. Off-tree-safe (get_instance_id needs no transform/tree); irrelevant at the inert single-point default.
func _search_phase() -> float:
	if not is_nan(_sector_phase_override):
		return _sector_phase_override  # GA-4: a squad-coordinated sector overrides the per-NPC default
	return wrapf(float(get_instance_id()) * 0.000133, 0.0, TAU)

## In range, inside the horizontal view cone, and with a clear line of sight to the target.
func can_see() -> bool:
	if not is_hostile:
		return false
	if not is_instance_valid(target):
		return false
	var eye := global_position + Vector3.UP * eye_height
	var tp := _target_point()
	var to_target := tp - eye
	var dist := to_target.length()
	if dist < 0.001 or dist > _effective_sight_range():
		return false
	# Horizontal cone only (vertical unbounded), so crouch height never hides you on its own.
	var flat_to := Vector3(to_target.x, 0.0, to_target.z)
	var fwd := global_transform.basis.z  # +Z is this model's front
	var flat_fwd := Vector3(fwd.x, 0.0, fwd.z)
	if flat_to.length_squared() > 0.0001 and flat_fwd.length_squared() > 0.0001:
		if rad_to_deg(flat_fwd.angle_to(flat_to)) > fov_degrees * 0.5:
			return false
	# Line of sight: nothing solid between the eyes and the target.
	var query := PhysicsRayQueryParameters3D.create(eye, tp)
	query.exclude = [get_parent()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == target

## True if this enemy can SEE `node` right now: within sight_range, inside the horizontal view cone, and with a
## clear line of sight to it. UNLIKE can_see(), it ignores hostility + the assigned target -- so a NON-hostile NPC
## can use it to notice e.g. the player pointing a gun at it (the "watch where you're aiming" bark should only
## fire when the NPC can actually see you do it). World-guarded -> false off-tree.
func can_see_node(node: Node3D) -> bool:
	if not is_instance_valid(node):
		return false
	var world := get_world_3d()
	if world == null or not world.space.is_valid():
		return false
	var eye := global_position + Vector3.UP * eye_height
	var tp := node.global_position
	var to_target := tp - eye
	var dist := to_target.length()
	if dist < 0.001 or dist > sight_range:
		return false
	var flat_to := Vector3(to_target.x, 0.0, to_target.z)
	var fwd := global_transform.basis.z  # +Z is this model's front
	var flat_fwd := Vector3(fwd.x, 0.0, fwd.z)
	if flat_to.length_squared() > 0.0001 and flat_fwd.length_squared() > 0.0001:
		if rad_to_deg(flat_fwd.angle_to(flat_to)) > fov_degrees * 0.5:
			return false
	var query := PhysicsRayQueryParameters3D.create(eye, tp)
	query.exclude = [get_parent()]
	var hit := world.direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == node

## Sight range, shortened while the target is CROUCHING (stealth) — a deeper crouch shrinks how close an
## enemy must be to spot you. Reads the target's `crouch` component duck-typed (only the player has one);
## any target without it uses the full range. Hearing is already silenced by crouch via noise_radius.
func _effective_sight_range() -> float:
	if not is_instance_valid(target):
		return sight_range
	var crouch: Variant = target.get(&"crouch")
	if not (crouch is Object) or not is_instance_valid(crouch):
		return sight_range
	# Duck-typed read: the crouch component's crouch_t into a Variant + a numeric type-guard. A target whose
	# crouch node lacks it (or holds a non-number) is treated as standing — full range, the neutral fallback.
	var raw: Variant = crouch.get(&"crouch_t")
	if not (raw is float or raw is int):
		return sight_range
	var ct: float = clampf(float(raw), 0.0, 1.0)
	return sight_range * lerpf(1.0, crouch_sight_mult, ct)

## Per-frame visibility scalar (0..1) for a target at normalized distance `dist_frac` (0 = point-blank, 1 = at
## sight range) and `angle_frac` (0 = dead centre, 1 = cone edge): the DETECTING meter fills FASTER for a close,
## centred target. Each falloff is a Curve @export; an UNSET curve contributes 1.0 (so by default, with both
## unset, this returns 1.0 — detection is unchanged). Floored at min_visibility so a genuine in-cone
## line-of-sight sighting still fills the meter to ALERTED eventually, just slowly at the fringes. Pure.
func visibility_factor(dist_frac: float, angle_frac: float, light_factor: float = 1.0) -> float:
	var r := range_falloff.sample(clampf(dist_frac, 0.0, 1.0)) if range_falloff != null else 1.0
	var a := peripheral_falloff.sample(clampf(angle_frac, 0.0, 1.0)) if peripheral_falloff != null else 1.0
	return clampf(r * a * clampf(light_factor, 0.0, 1.0), min_visibility, 1.0)

## The target's light visibility factor (0..1) for visibility_factor's third arg: its `light_exposure` (duck-typed,
## 1.0 = fully lit when absent/unset) mapped through light_falloff. Returns 1.0 (no light effect) when
## light_falloff is unset, so light is opt-in. Numeric type-guard per the duck-typed-read rule.
func _target_light_factor() -> float:
	var curve := _effective_light_falloff()
	if curve == null or not is_instance_valid(target):
		return 1.0
	var raw: Variant = target.get(&"light_exposure")
	var exposure := float(raw) if (raw is float or raw is int) else 1.0
	return curve.sample(clampf(exposure, 0.0, 1.0))

## The light-falloff curve in effect: this NPC's own Perception.light_falloff (per-archetype override) if set,
## else the GLOBAL default (GameSettings.light_stealth.falloff()) — so one global curve turns shadow-stealth on
## game-wide with no per-NPC authoring (rank 27.2). Null only if the global settings are somehow absent.
func _effective_light_falloff() -> Curve:
	if light_falloff != null:
		return light_falloff
	var ls: Variant = GameSettings.light_stealth
	return ls.falloff() if ls != null else null

## The current target's distance into sight range, normalized 0..1 (for the range falloff); 0 with no target.
## In-tree (reads transforms); called from sense() only when a falloff curve is authored.
func _see_distance_frac() -> float:
	if not is_instance_valid(target):
		return 0.0
	var eye := global_position + Vector3.UP * eye_height
	return clampf(eye.distance_to(_target_point()) / maxf(_effective_sight_range(), 0.001), 0.0, 1.0)

## The current target's angle off the cone centre, normalized 0..1 (0 = dead ahead, 1 = at the fov edge); 0 with
## no target / degenerate geometry. Mirrors the horizontal-cone math in can_see().
func _see_angle_frac() -> float:
	if not is_instance_valid(target):
		return 0.0
	var to_target := _target_point() - (global_position + Vector3.UP * eye_height)
	var flat_to := Vector3(to_target.x, 0.0, to_target.z)
	var fwd := global_transform.basis.z
	var flat_fwd := Vector3(fwd.x, 0.0, fwd.z)
	if flat_to.length_squared() < 0.0001 or flat_fwd.length_squared() < 0.0001:
		return 0.0
	return clampf(rad_to_deg(flat_fwd.angle_to(flat_to)) / maxf(fov_degrees * 0.5, 0.001), 0.0, 1.0)

## Hearing: the player's current noise (a gunfire spike + fast movement; crouch is silent) reaches us within
## its audible radius. Ignores the view cone (sound is non-directional); WALLS only muffle it when
## hearing_occlusion is on (hearing_attenuation), else sound rounds corners exactly as before.
func can_hear() -> bool:
	if not is_hostile or not hearing or not is_instance_valid(target):
		return false
	# Duck-typed read: the target's noise_radius into a Variant + a numeric type-guard. A target lacking it
	# (or holding a non-number) reports no audible noise — the neutral fallback (can't be heard).
	var nr: Variant = target.get(&"noise_radius")
	if not (nr is float or nr is int):
		return false
	var tp := _target_point()
	return global_position.distance_to(tp) <= float(nr) * hearing_attenuation(tp)

func _target_point() -> Vector3:
	var node: Node3D = target_body if is_instance_valid(target_body) else target
	return node.global_position if is_instance_valid(node) else global_position

## Sound occlusion (stealth Slice 7): a 0..1 multiplier on a heard noise's effective RADIUS from WALLS between
## this enemy's eye and the noise at `source_pos`. Clear line -> 1.0; a wall in the way -> 1 -
## hearing_wall_attenuation (so the noise is heard only at closer range, or silenced when attenuation is 1).
## OFF by default (GameSettings.npc_ai.hearing_occlusion) -> always 1.0, so sound rounds corners as before and
## an off-tree caller never raycasts. The source's OWN body (e.g. the player carrying the live NoiseSource)
## doesn't count -- the ray stops short of it; only geometry well before it. Read by can_hear + NPC._loudest_noise.
func hearing_attenuation(source_pos: Vector3) -> float:
	if not GameSettings.npc_ai.hearing_occlusion:
		return 1.0
	if not _wall_between(global_position + Vector3.UP * eye_height, source_pos):
		return 1.0
	return clampf(1.0 - GameSettings.npc_ai.hearing_wall_attenuation, 0.0, 1.0)

## True when solid geometry sits between `from` and `to` (a wall the sound has to pass). World-guarded (off-tree
## -> false). Excludes our own NPC body. The ray STOPS hearing_source_skip metres short of `to` so the source's
## own collider (the player's ~0.5 m capsule, a decoy body) is never the hit -- without that, a clear line of
## sight self-occludes because the source body radius (~0.5) sits right at the destination. Maskless like
## can_see(), so a third body genuinely between listener and source still muffles (accepted emergent occlusion).
func _wall_between(from: Vector3, to: Vector3) -> bool:
	var world := get_world_3d()
	if world == null or not world.space.is_valid():
		return false
	var offset := to - from
	var dist := offset.length()
	var skip: float = GameSettings.npc_ai.hearing_source_skip
	if dist <= skip:
		return false  # too close for a wall to fit between the eye and the source's own body
	var endpoint := to - offset / dist * skip  # stop short of the source so it can't self-occlude
	var q := PhysicsRayQueryParameters3D.create(from, endpoint)
	q.exclude = [get_parent()]
	return not world.direct_space_state.intersect_ray(q).is_empty()
