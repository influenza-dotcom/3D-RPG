extends RefCounted

## The Player's STAMINA / SPRINT economy, pulled out of player.gd so the pool, the spend/drain rules, the regen
## curve + its post-spend delay, and the sprint lockout live in one cohesive, testable unit instead of ~110 lines
## woven through the god-object. Method NAMES are unchanged from the Player originals (including the leading
## underscores — the NpcVoice keep-it-private precedent), and the Player keeps a 1-line forwarder per method with
## the identical signature, so every caller (attack.gd's melee/air-dash duck-types, wall_climb/grapple drains,
## GroundMovement's typed sprint gates, character_stats.restamp_derived's apply_stamina_max_delta probe, and the
## white-box tests) is untouched.
##
## WHY RefCounted (not a Node / autoload) — the AbilityManager idiom:
##  - Built at the Player's var-init and wired in Player._init (host + the signal relay), so the white-box unit
##    tests — which build a bare `Player.new()` and NEVER run _ready — can drive spend/drain/regen immediately.
##    A Node child would need add_child (only reachable in _ready) and would leak as an orphan off-tree.
##  - It holds no per-frame process and no tree presence; it is pure state + logic. ⭐ The DRIVE BEATS stay in
##    Player._physics_process at their exact positions — _update_stamina_recovery runs from BOTH branches (the
##    dialogue-frozen early-out AND the live tail) and _update_sprint_lockout ticks before the dialogue gate.
##    Do NOT "simplify" them into a manager-side per-frame tick: die() calls set_physics_process(false), so
##    regen and the lockout countdown must freeze exactly when the Player's physics step does.
##
## NO class_name, BY CHOICE: player.gd is the sole runtime consumer and preloads this BY PATH (the StatBudgetRef /
## NpcDistraction idiom); a brand-new class_name risks the stale-class-cache cascade in the next headless run.
##
## HOST is the owning Player, injected once (Player._init sets `host = self`). Typed to the BASE `Character` —
## never Player — because a preload-by-path script naming the Player class is the class_name↔preload parse-cycle
## trap; Character is safe (it never references Player or this manager) and covers the hot path typed: velocity,
## is_on_floor(), stats_or_default(), status_stat_modifier(). The Player-SCRIPT-only surface is read dynamically
## with the established idioms: host.get(&"input_dir") / (&"crouch") / (&"_is_scoped"),
## host.call(&"is_climbing" / &"is_sliding" / &"is_grappling").
##
## NULL-GUARD table — a BARE manager (host == null, straight `load(...).new()` in a test) must never crash; every
## host touch degrades to the bare off-tree Player's own defaults:
##   endurance stamina bonus -> 0.0 (stamina_max = the base tuning max, still floored at 1.0)
##   is_on_floor -> false          velocity -> Vector3.ZERO       input_dir -> Vector2.ZERO
##   crouch -> null (standing)     _is_scoped -> false            climbing / sliding / grappling -> false
##
## TUNING: the manager holds ZERO knobs. Every number stays on GameSettings.player_movement (max_stamina, the
## stamina_regen_* tier rates, stamina_regen_delay_after_spend, stamina_sprint_drain / stamina_sprint_lockout,
## and the per-verb jump / melee / dash / slide / grapple / SHOT costs read by the callers) plus
## GameSettings.weapon_general.allow_sprint_while_scoped — designer-tuned .tres resources, never consts here.
## The ONE stamina cost that is not a flat player_movement number: the RANGED SHOT, which attack.gd DERIVES
## per weapon as stamina_shot_cost x WeaponData.stamina_effort() (damage / pellets / blast payload) x that
## weapon's stamina_cost_mult trim, clamped by stamina_shot_drain_ceiling so no gun can out-drain sprinting.

## Relayed out by the Player as its own `stamina_changed` (Player._on_stamina_changed — the mechanic_unlocked
## relay idiom, synchronous, so emission order/count is unchanged); external consumers keep connecting to the
## PLAYER's signal. NOTE ui.gd doesn't even connect — it POLLS player.get(&"stamina") / call(&"stamina_max")
## per frame through the Player's raw `stamina` property alias + forwarder.
signal stamina_changed(current: float, maximum: float)

const STAMINA_EPS := 0.001

var host: Character = null  ## the owning Player, injected by Player._init (null = a bare manager in a unit test)

## The live pool. Seeded from the tuning resource at var-init — the same timing as the old Player field, since the
## Player constructs this manager at ITS var-init. Deliberately a bare var: the Player's `stamina` property aliases
## it RAW (no clamp, no emit), preserving the old bare-var semantics for the HUD poll and the tests' raw writes
## (Dark-Souls overdraw drives it below zero on purpose; _set_stamina is the only clamped writer).
var stamina: float = GameSettings.player_movement.max_stamina
var _stamina_regen_delay_left: float = 0.0
var _sprint_lockout_left: float = 0.0

## Endurance-boosted cap, re-read live (status modifiers move it between frames), floored at 1.0 so the fraction
## math never divides by zero. Bare manager: no stat sheet -> the base tuning max.
func stamina_max() -> float:
	var bonus := 0.0
	if host != null:
		bonus = host.stats_or_default().stamina_bonus(host.status_stat_modifier(&"endurance"))
	return maxf(1.0, GameSettings.player_movement.max_stamina + bonus)

## The endurance re-stamp beat (CharacterStats.restamp_derived duck-calls the Player's forwarder): grow the pool
## by the gained headroom (a raised max heals the difference), then guarantee ONE HUD emit even when the clamp
## left the VALUE numerically unchanged — a lowered max still moves the bar's denominator.
func apply_stamina_max_delta(old_max: float) -> void:
	var new_max := stamina_max()
	var target := stamina
	if new_max > old_max:
		target += new_max - old_max
	var before := stamina
	_set_stamina(target)
	if is_equal_approx(before, stamina) and not is_equal_approx(old_max, new_max):
		stamina_changed.emit(stamina, new_max)

func stamina_fraction() -> float:
	var maximum := stamina_max()
	if maximum <= STAMINA_EPS:
		return 1.0
	return clampf(stamina / maximum, 0.0, 1.0)

func can_spend_stamina(cost: float) -> bool:
	return cost <= 0.0 or stamina > STAMINA_EPS

func is_sprint_locked_out() -> bool:
	return _sprint_lockout_left > STAMINA_EPS

func can_sprint() -> bool:
	return stamina > STAMINA_EPS and not is_sprint_locked_out()

## Aiming down sights locks out the run tier — the ONE gate both sprint consumers share: _wants_sprint()
## (stamina drain + is_sprinting()'s FOV widen) and GroundMovement.compute_target_speed (the walk-tier
## fallback). While scoped you're pinned to the walk tier and THEN slowed again by scope_speed_mult, so
## ADS is a committed, planted stance rather than a sprint you can keep holding. Designer opt-out:
## GameSettings.weapon_general.allow_sprint_while_scoped.
## (_is_scoped stays a HOST var on purpose: ScopeCoordinator writes host._is_scoped and GroundMovement + the
## scope tests read it off the Player, so this manager reads it dynamically rather than owning it.)
func sprint_blocked_by_scope() -> bool:
	var scoped := false
	if host != null:
		var raw: Variant = host.get(&"_is_scoped")
		scoped = raw is bool and raw
	return scoped and not GameSettings.weapon_general.allow_sprint_while_scoped

## Spend a one-off cost and hold off regen behind it. `regen_delay` lets a caller ask for a LONGER hold than the
## movement default: Attack passes stamina_regen_delay_after_shot so a trigger pull freezes recovery well past the
## weapon's own cadence, which is what stops a slow weapon regenerating between its own shots and paying for
## itself. Negative (the default) means "use stamina_regen_delay_after_spend" — so every existing one-arg caller,
## and every duck-typed has_method(&"spend_stamina") call site, is unchanged.
## NOTE a REFUSED spend (empty pool) returns before the hold is armed, which is what keeps the design
## self-terminating: once the pool bottoms out the drain stops AND recovery resumes normally.
func spend_stamina(cost: float, regen_delay: float = -1.0) -> bool:
	if cost <= 0.0:
		return true
	if not can_spend_stamina(cost):
		return false
	_set_stamina(stamina - cost)
	# GameSettings is an untyped autoload, so the fallback is read into an explicitly TYPED local rather than
	# inferred through a ternary (the house no-`:=`-from-a-Variant rule).
	var default_hold: float = GameSettings.player_movement.stamina_regen_delay_after_spend
	var hold := regen_delay if regen_delay >= 0.0 else default_hold
	_stamina_regen_delay_left = maxf(_stamina_regen_delay_left, hold)
	return true

func drain_stamina(rate: float, delta: float) -> bool:
	if rate <= 0.0:
		return true
	if stamina <= STAMINA_EPS:
		return false
	_set_stamina(stamina - rate * maxf(delta, 0.0))
	_stamina_regen_delay_left = maxf(_stamina_regen_delay_left, GameSettings.player_movement.stamina_regen_delay_after_spend)
	return stamina > STAMINA_EPS

func _begin_sprint_lockout() -> void:
	_sprint_lockout_left = maxf(_sprint_lockout_left, GameSettings.player_movement.stamina_sprint_lockout)

func _update_sprint_lockout(delta: float) -> void:
	if _sprint_lockout_left > 0.0:
		_sprint_lockout_left = maxf(_sprint_lockout_left - maxf(delta, 0.0), 0.0)

## Is the player actively TRYING to sprint this frame? (Real stick input + grounded + no special movement + not
## crouched + not scoped + the Run modifier held.) `input_vector` stays a parameter — the Player's drive beat and
## is_sprinting()'s Player-side body both pass the live input_dir. Reads Input/InputManager directly, the same
## way the GroundMovement statics already do.
func _wants_sprint(input_vector: Vector2) -> bool:
	if input_vector.length() <= 0.1:
		return false
	if host == null or not host.is_on_floor():
		return false
	if _special_movement_active():
		return false
	# Crouch gate, duck-typed off host.crouch.crouch_t (the crouch_light_douse idiom): the Crouch node is a
	# Player-script @export, so a bare host — or no crouch node wired — reads standing (no gate).
	var crouch: Variant = host.get(&"crouch")  # host null-checked above
	if is_instance_valid(crouch) and crouch is Object:  # validity FIRST — `is` on a freed instance crashes (house rule)
		var raw_t: Variant = (crouch as Object).get(&"crouch_t")
		if (raw_t is float or raw_t is int) and float(raw_t) >= 0.5:
			return false
	if sprint_blocked_by_scope():
		return false
	return Input.is_action_pressed(InputManager.action_run)

func _drain_sprint_stamina(delta: float) -> bool:
	if not can_sprint():
		return false
	var still_has_stamina := drain_stamina(GameSettings.player_movement.stamina_sprint_drain, delta)
	if not still_has_stamina:
		_begin_sprint_lockout()
	return still_has_stamina

## The ONE clamped writer ([-max, max] — negative floor = the Dark-Souls overdraw the tests pin) and the ONE
## emit site. Emits the MANAGER's signal; the Player relays it out unchanged. `emit_change = false` is the
## _ready seed (fill silently before the HUD exists).
func _set_stamina(value: float, emit_change: bool = true) -> void:
	var maximum := stamina_max()
	var next := clampf(value, -maximum, maximum)
	if is_equal_approx(stamina, next):
		return
	stamina = next
	if emit_change:
		stamina_changed.emit(stamina, maximum)

## The climbing / sliding / grappling triple gathered at ONE null-guard site (both _wants_sprint and the regen
## curve read it). The three predicates are Player-script methods backed by the ability nodes, so they're dynamic
## calls; a bare host reads false = no special movement.
func _special_movement_active() -> bool:
	if host == null:
		return false
	return bool(host.call(&"is_climbing")) or bool(host.call(&"is_sliding")) or bool(host.call(&"is_grappling"))

## The whole regen curve as a PURE static (the Landing impact_for / GroundMovement precedent) — testable with no
## host. Tier pick, most-demanding state first: special movement (climb/slide/grapple) -> airborne -> moving ->
## idle, where "moving" = real stick input OR real horizontal speed (the footstep threshold, so residual slide
## still counts as moving). The four rates are the GameSettings.player_movement.stamina_regen_* knobs;
## test_settings_load pins their idle > moving > active ordering.
static func recovery_rate_for(special_active: bool, airborne: bool, input_len: float, horiz_speed: float) -> float:
	if special_active:
		return GameSettings.player_movement.stamina_regen_active
	if airborne:
		return GameSettings.player_movement.stamina_regen_airborne
	var moving := input_len > 0.1 or horiz_speed > GameSettings.player_movement.footstep_min_horizontal_speed
	if moving:
		return GameSettings.player_movement.stamina_regen_moving
	return GameSettings.player_movement.stamina_regen_idle

## Instance wrapper over the pure curve: sample the host's live movement state, then pick the tier.
func _stamina_recovery_rate() -> float:
	var vel: Vector3 = host.velocity if host != null else Vector3.ZERO
	var input_vec := Vector2.ZERO
	if host != null:
		var raw: Variant = host.get(&"input_dir")
		if raw is Vector2:
			input_vec = raw
	var airborne := host == null or not host.is_on_floor()
	return recovery_rate_for(_special_movement_active(), airborne, input_vec.length(), Vector2(vel.x, vel.z).length())

## ⭐ Driven from BOTH Player._physics_process branches — the dialogue-frozen early-out AND the live tail — so
## stamina regenerates while frozen in a conversation. The delay gate eats the post-spend hold first; an OVERFULL
## pool (an endurance drop mid-life) snaps back down through _set_stamina's clamp; anything short of full climbs
## at the picked tier rate.
func _update_stamina_recovery(delta: float) -> void:
	if _stamina_regen_delay_left > 0.0:
		_stamina_regen_delay_left = maxf(_stamina_regen_delay_left - delta, 0.0)
		return
	var maximum := stamina_max()
	if stamina > maximum + STAMINA_EPS:
		_set_stamina(stamina)
		return
	if stamina >= maximum - STAMINA_EPS:
		return
	var rate := _stamina_recovery_rate()
	if rate > 0.0:
		_set_stamina(stamina + rate * delta)

## The in-place revive beat (Player._respawn_at_checkpoint): the fresh life can sprint immediately. NOTE the
## regen DELAY is deliberately NOT cleared on revive — the revive refills the pool to full anyway, so it's moot.
func clear_sprint_lockout() -> void:
	_sprint_lockout_left = 0.0
