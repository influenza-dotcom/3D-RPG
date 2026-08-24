extends GutTest

## GUT coverage for the Combat systems subsystem — the four combat scripts under
## res://scripts/combat (weapon_system.gd, scope_in.gd, swap_weapons.gd, attack.gd).
##
## What this file asserts (all SAFE-SURFACE, no scene wiring, no real side effects):
##   - Weapon: the public null-guarded query surface (can_fire/is_busy/is_scoped/
##     current_ammo/equipped_weapon/reload) all report a sane "unwired" answer on a
##     fresh, NOT-add_child'd load(...).new() instance (attack/ammo/inventory/scope_in
##     exports are null), plus its host-facing has_method contract.
##   - ScopeIn: is_scoped starts false; force_unscope() is a safe no-op when already
##     un-scoped and correctly clears + emits scoped_in(false) when flipped manually.
##   - Attack: plain-var defaults, the firing/scope has_method surface, and the two
##     call-safe (current_weapon-guarded) entry points can_enter_scope()/
##     start_secondary_cooldown() behaving as documented no-ops on a bare instance.
##   - SwapWeapons: the out-of-box 6-slot default array, and _try_equip() emitting
##     (or, when out of range, NOT emitting) its equip_this signal.
##
## What this file deliberately SKIPS and why:
##   - Weapon.setup(): un-guarded, dereferences null internal parts — needs the real
##     weapon.tscn (Inventory/Ammo/Timers/spawner). Out of scope.
##   - Attack.can_fire()/is_reload_or_swap_active() CALLS: they dereference the null
##     @export Timer nodes (attack/reload/swap) and would crash a bare instance — only
##     has_method is safe here; the real boolean needs full Timer + Inventory wiring.
##   - Attack._ready/_physics_process and the whole fire/spray/launch/colour-picker/
##     swap-state path: these connect to a null inventory, dereference null
##     character/clip/muzzle, spawn nodes into the tree, play audio, raycast the world,
##     call FreezeFrame, and set Input.mouse_mode — never safe to drive in a unit test.
##     Hence Attack is instantiated WITHOUT add_child throughout (and freed by hand).
##   - ScopeIn._process: requires a real camera + a fully-wired Attack (Timer derefs);
##     the is_scoped state machine is exercised here only via direct field set +
##     force_unscope(), never by ticking a frame.
##   - WeaponData .tres field values, Inventory.equip/weapon_changed, GameSettings/
##     InputManager tuning, and Attack.flash_muzzle wiring are already covered by
##     test_smoke.gd — not duplicated here.
##
## test_smoke.gd already asserts ScopeIn.new().has_method("force_unscope") and (via
## source text) that Attack defines can_enter_scope/_do_launch_attack; the NEW value
## below is the actual runtime BEHAVIOUR (defaults, no-op/flip semantics, emitted
## signals, real return values), not the existence checks.

const WEAPON_SYSTEM_PATH := "res://scripts/combat/weapon_system.gd"
const ATTACK_PATH := "res://scripts/combat/attack.gd"

func _packed_visual_scene(mesh: Mesh) -> PackedScene:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "SceneMesh"
	mi.mesh = mesh
	root.add_child(mi)
	mi.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed


# ---------------------------------------------------------------------------
# Weapon (weapon_system.gd) — public null-guarded query surface.
# A bare load(...).new() leaves every internal @export part null, so its _ready
# (Node3D, no @onready) is side-effect-free; we still avoid add_child since we
# only read the null-guarded getters/methods. setup() is NEVER called (it would
# crash on the null parts).
# ---------------------------------------------------------------------------

func test_weapon_can_fire_false_when_unwired() -> void:
	# Getter body: `attack.can_fire() if attack else false`. attack is null on a
	# fresh instance, so the null-guard must short-circuit to false.
	var w = load(WEAPON_SYSTEM_PATH).new()
	assert_false(w.can_fire(),
		"An unwired Weapon (no Attack component) must never claim it can fire — otherwise a freshly-spawned, un-setup() weapon could shoot.")
	w.free()


func test_weapon_is_busy_false_when_unwired() -> void:
	# Getter body: `attack.is_reload_or_swap_active() if attack else false`.
	var w = load(WEAPON_SYSTEM_PATH).new()
	assert_false(w.is_busy(),
		"An unwired Weapon is not mid-reload/swap — is_busy() must read false so callers don't block a weapon that has no state yet.")
	w.free()


func test_weapon_is_scoped_false_when_unwired() -> void:
	# Property getter: `scope_in.is_scoped if scope_in else false`.
	var w = load(WEAPON_SYSTEM_PATH).new()
	assert_false(w.is_scoped,
		"A Weapon with no ScopeIn component must read as not scoped — a null scope must not surface as garbage 'scoped' state.")
	w.free()


func test_weapon_current_ammo_zero_when_unwired() -> void:
	# Property getter: `ammo.current_ammo if ammo else 0`.
	var w = load(WEAPON_SYSTEM_PATH).new()
	assert_eq(w.current_ammo, 0,
		"An unwired clip (no Ammo component) must report 0 rounds, not uninitialised garbage.")
	w.free()


func test_weapon_equipped_weapon_null_when_unwired() -> void:
	# Property getter: `inventory.equipped_weapon if inventory else null`.
	var w = load(WEAPON_SYSTEM_PATH).new()
	assert_eq(w.equipped_weapon, null,
		"No Inventory means no equipped weapon — equipped_weapon must be null on a bare component, not a stale resource.")
	w.free()


func test_weapon_reload_is_safe_noop_when_unwired() -> void:
	# Body: `if attack: attack._on_reload_reload()`. attack is null, so this must
	# be a no-op and leave the (null-guarded) ammo count at 0.
	var w = load(WEAPON_SYSTEM_PATH).new()
	w.reload()
	assert_eq(w.current_ammo, 0,
		"The AI-reload entry reload() must be a safe no-op before setup() — with no Attack it must not crash and must leave current_ammo at 0.")
	w.free()


func test_weapon_exposes_host_facing_api() -> void:
	# Documents the contract a host relies on: setup() injects refs; the rest are
	# null-guarded queries safe to call any time.
	var w = load(WEAPON_SYSTEM_PATH).new()
	assert_true(w.has_method("setup"),
		"Weapon.setup() is how a host injects the wielder/camera/muzzle — it must exist for the component to ever be wired.")
	assert_true(w.has_method("can_fire"),
		"Weapon.can_fire() is part of the host-facing query surface.")
	assert_true(w.has_method("is_busy"),
		"Weapon.is_busy() is part of the host-facing query surface.")
	assert_true(w.has_method("reload"),
		"Weapon.reload() is the AI-wielder reload entry point on the host-facing surface.")
	w.free()


# ---------------------------------------------------------------------------
# ScopeIn (scope_in.gd) — ADS state machine, tested via direct field set only.
# Never add_child'd: _process derefs `camera`/`attack`. ScopeIn.new() (no tree
# entry) matches the existing test_smoke.gd pattern.
# ---------------------------------------------------------------------------

func test_scope_in_not_scoped_by_default() -> void:
	# `var is_scoped: bool = false` (scope_in.gd:9).
	var si := ScopeIn.new()
	assert_false(si.is_scoped,
		"ADS must start disengaged — a freshly-spawned ScopeIn that began life 'scoped' would zoom the camera with no input.")
	si.free()


func test_scope_in_force_unscope_is_noop_when_not_scoped() -> void:
	# Body only acts `if is_scoped`. Already false, so this must do nothing and
	# (critically) must NOT emit scoped_in — the melee dash calls it unconditionally.
	var si := ScopeIn.new()
	watch_signals(si)
	si.force_unscope()
	assert_false(si.is_scoped,
		"force_unscope() while already un-scoped must leave is_scoped false — the melee dash calls it unconditionally, so it has to be a safe no-op.")
	assert_signal_not_emitted(si, "scoped_in",
		"force_unscope() must not emit scoped_in when nothing changed — a spurious pulse would jolt the FOV/spread every dash.")
	si.free()


func test_scope_in_force_unscope_clears_and_emits_when_scoped() -> void:
	# Manually scope in (no camera touched), then force off: state must clear and
	# scoped_in(false) must fire exactly once. emit is synchronous.
	var si := ScopeIn.new()
	si.is_scoped = true
	watch_signals(si)
	si.force_unscope()
	assert_false(si.is_scoped,
		"Forcing the scope off must clear is_scoped so the gun returns to hip-fire state.")
	assert_signal_emitted(si, "scoped_in",
		"force_unscope() on a scoped weapon must notify listeners via scoped_in so the spread/FOV reset exactly once.")
	si.free()


# ---------------------------------------------------------------------------
# Attack (attack.gd) — bare instance, NEVER add_child'd.
# _ready() (line 61) connects inventory.weapon_changed on a null inventory and
# relies on @onready $ShellImpact (line 42); add_child would crash. We use
# load(...).new() WITHOUT add_child, assert, then free().
# can_fire()/is_reload_or_swap_active() are NOT called (they deref null Timers);
# can_enter_scope()/start_secondary_cooldown() ARE call-safe (guard on the null
# current_weapon first).
# ---------------------------------------------------------------------------

func test_attack_default_flag_state() -> void:
	# attack.gd:50,53,54,59 — current_weapon (untyped null), _is_scoped/_swap_raising/
	# _did_air_dash all start false.
	var a = load(ATTACK_PATH).new()
	assert_eq(a.current_weapon, null,
		"A bare Attack has no equipped weapon — current_weapon must be null until weapon_changed seeds it.")
	assert_false(a._is_scoped,
		"An unwired Attack starts un-scoped (_is_scoped false) so it doesn't apply the scoped spread divisor with no ADS.")
	assert_false(a._did_air_dash,
		"_did_air_dash must start false so the first airborne single-air-dash launch is available.")
	assert_false(a._swap_raising,
		"_swap_raising must start false — no weapon-swap raise is in progress on a fresh Attack.")
	a.free()


func test_attack_can_enter_scope_true_by_default() -> void:
	# attack.gd:102-106 — with current_weapon null the launch/air-dash branch is
	# skipped entirely (it never touches the null character/timers) and returns true.
	var a = load(ATTACK_PATH).new()
	assert_true(a.can_enter_scope(),
		"Re-scoping must be allowed by default — only a spent airborne single_air_dash launch weapon locks ADS, so a bare Attack must report it can enter scope.")
	a.free()


func test_attack_start_secondary_cooldown_is_noop_without_weapon() -> void:
	# attack.gd:87-91 — body is `if not current_weapon: return`, so with no weapon
	# it must NOT touch the null attack Timer. Returns void; verify via state read.
	var a = load(ATTACK_PATH).new()
	a.start_secondary_cooldown()
	assert_eq(a.current_weapon, null,
		"start_secondary_cooldown() must be a safe no-op before a weapon is equipped — it early-returns on a null current_weapon instead of touching the null attack Timer.")
	a.free()


func test_attack_exposes_firing_and_scope_api() -> void:
	# Surface ScopeIn._process and the Weapon host read. NOTE: can_fire() and
	# is_reload_or_swap_active() are only has_method-safe here — calling them on a
	# bare instance would deref the null attack/reload/swap Timers.
	var a = load(ATTACK_PATH).new()
	assert_true(a.has_method("can_fire"),
		"ScopeIn._process and Weapon.can_fire() both call Attack.can_fire() — it must exist on the firing surface.")
	assert_true(a.has_method("is_reload_or_swap_active"),
		"ScopeIn._process and Weapon.is_busy() read Attack.is_reload_or_swap_active() to break/gate ADS — it must exist.")
	assert_true(a.has_method("can_enter_scope"),
		"ScopeIn._process calls can_enter_scope() to enforce the air-dash ADS lockout — it must exist.")
	assert_true(a.has_method("try_fire"),
		"try_fire() is the AI-wielder fire entry point — it must exist for camera-less wielders to attack.")
	assert_true(a.has_method("start_secondary_cooldown"),
		"start_secondary_cooldown() lets secondary actions (e.g. the melee launch) share the firing cadence — it must exist.")
	a.free()


func test_spray_painter_dialogue_started_uses_resource_arg_adapter() -> void:
	var painter := SprayPainter.new()
	add_child_autofree(painter)
	assert_true(DialogueManager.dialogue_started.is_connected(Callable(painter, "_on_dialogue_started")),
		"SprayPainter must connect dialogue_started(resource) to a one-arg adapter so Godot does not call the zero-arg picker-close helper with the emitted DialogueResource")
	assert_false(DialogueManager.dialogue_started.is_connected(Callable(painter, "_close_picker_for_dialogue")),
		"SprayPainter must not connect dialogue_started(resource) directly to _close_picker_for_dialogue(), because that helper intentionally takes no signal arguments")
	painter._on_dialogue_started(DialogueResource.new())
	assert_false(painter.is_open(),
		"SprayPainter's dialogue-start adapter must accept the DialogueResource and safely no-op when the picker is already closed")


# ---------------------------------------------------------------------------
# SwapWeapons (swap_weapons.gd) — the only combat script safe to add_child:
# no _ready, no @onready. add_child_autofree lets watch_signals/assert_signal_*
# observe equip_this; _try_equip is called directly (not via input).
# ---------------------------------------------------------------------------

func test_attack_melee_stamina_gate_and_spend() -> void:
	var a = load(ATTACK_PATH).new()
	var p = load("res://scripts/player/player.gd").new()
	var melee := WeaponData.new()
	melee.is_melee = true
	a.current_weapon = melee
	a.character = p
	p.stamina = 5.0
	assert_true(a._can_start_melee_attack(),
		"a melee swing may start with any positive stamina, even when the cost will overdraw")
	a._spend_melee_attack_stamina()
	assert_almost_eq(p.stamina, 5.0 - GameSettings.player_movement.stamina_melee_attack_cost, 0.001,
		"starting a melee swing spends the configured stamina cost")
	assert_false(a._can_start_melee_attack(),
		"a melee swing may not start while stamina is already empty or in debt")
	p.free()
	a.free()
	melee = null


func test_attack_ranged_weapon_skips_melee_stamina() -> void:
	var a = load(ATTACK_PATH).new()
	var p = load("res://scripts/player/player.gd").new()
	var gun := WeaponData.new()
	gun.is_melee = false
	a.current_weapon = gun
	a.character = p
	p.stamina = 5.0
	assert_true(a._can_start_melee_attack(),
		"non-melee weapons do not use the melee stamina gate")
	a._spend_melee_attack_stamina()
	assert_almost_eq(p.stamina, 5.0, 0.001,
		"non-melee weapons do not spend melee stamina")
	p.free()
	a.free()
	gun = null


# --- Ranged per-shot stamina (_shot_stamina_cost / _spend_shot_stamina) -------------------------------
# The gun twin of the melee pair above, with two deliberate asymmetries:
#   1. NO can-start gate - an empty pool never refuses a shot (an exhausted player still has an attack).
#   2. The price is DERIVED, not hand-authored: stamina_shot_cost x WeaponData.stamina_effort() x the weapon's
#      stamina_cost_mult TRIM, then clamped so cost/attack_speed can never exceed the sprint drain.
# ⭐ Every case here authors attack_speed. A bare WeaponData defaults to 0.1s, which is just UNDER the
# stamina_shot_cost / (ceiling x sprint_drain) = 1.8 / 17.1 = 0.105s break-even, so an unauthored weapon is
# mildly CLAMPED and would not report its derived price. PISTOL_CADENCE is the shipped pistol's, well clear.

const PISTOL_CADENCE := 0.44

## A ranged weapon whose stamina_effort() is exactly its damage (1 pellet, no blast) and whose cadence is clear
## of the clamp - so a test can assert the DERIVED price without the ceiling quietly rewriting it.
func _priced_gun(effort_damage: float = 1.0, cadence: float = PISTOL_CADENCE) -> WeaponData:
	var gun := WeaponData.new()
	gun.is_melee = false
	gun.damage = effort_damage
	gun.attack_speed = cadence
	return gun


func test_attack_ranged_shot_spends_shot_stamina() -> void:
	var a = load(ATTACK_PATH).new()
	var p = load("res://scripts/player/player.gd").new()
	var gun := _priced_gun()
	a.current_weapon = gun
	a.character = p
	assert_almost_eq(gun.stamina_effort(), 1.0, 0.001,
		"a plain 1.0-damage single-projectile round is the effort UNIT, so stamina_shot_cost reads as its price")
	var expected: float = GameSettings.player_movement.stamina_shot_cost
	assert_almost_eq(a._shot_stamina_cost(), expected, 0.001,
		"a baseline ranged shot costs exactly stamina_shot_cost (effort 1.0, trim 1.0, well under the clamp)")
	p.stamina = 50.0
	a._spend_shot_stamina()
	assert_almost_eq(p.stamina, 50.0 - expected, 0.001,
		"firing a ranged weapon spends the derived per-shot stamina cost")
	p.free()
	a.free()
	gun = null


func test_shot_stamina_scales_with_weapon_power() -> void:
	# The whole point of the feature: a powerful weapon costs more per trigger pull than a weak one, with nobody
	# hand-pricing either. Effort is damage x sqrt(pellets) + blast payload.
	var a = load(ATTACK_PATH).new()
	a.character = null
	var weak := _priced_gun(0.5)
	var strong := _priced_gun(2.0)
	a.current_weapon = weak
	var weak_cost := a._shot_stamina_cost()
	a.current_weapon = strong
	var strong_cost := a._shot_stamina_cost()
	assert_gt(strong_cost, weak_cost,
		"a higher-damage weapon must cost more stamina per shot than a weaker one")
	assert_almost_eq(strong_cost / weak_cost, 4.0, 0.001,
		"cost tracks effort LINEARLY: 4x the damage is 4x the stamina (both well clear of the cadence clamp)")
	# Pellets count sub-linearly - one trigger pull, one recoil impulse, and the pellets diverge over spread.
	var buck := _priced_gun(2.0)
	buck.pellet_count = 4
	assert_almost_eq(buck.stamina_effort(), 4.0, 0.001,
		"a 4-pellet 2.0-damage shell scores 2.0 x sqrt(4) = 4.0 effort, not the 8.0 of four separate shots")
	# A blast payload is what lifts the grenade launcher above every solid-round weapon. Compared against an
	# otherwise IDENTICAL solid round at the SAME cadence, so this isolates the payload - and both sit clear of
	# the clamp (7.20 and 14.40 against a 15.39 ceiling), so the difference is the derived price, not the rail.
	var solid := _priced_gun(4.0, 0.9)
	var launcher := _priced_gun(4.0, 0.9)
	launcher.projectile_explodes = true
	assert_almost_eq(launcher.stamina_effort(), 8.0, 0.001,
		"an exploding round adds BLAST_PAYLOAD scaled by radius on top of its direct damage (4.0 + 4.0)")
	a.current_weapon = solid
	var solid_cost := a._shot_stamina_cost()
	a.current_weapon = launcher
	assert_almost_eq(a._shot_stamina_cost(), solid_cost * 2.0, 0.001,
		"the same round costs exactly DOUBLE once it explodes - the blast payload is charged for")
	a.free()
	weak = null
	strong = null
	buck = null
	solid = null
	launcher = null


func test_shot_stamina_trim_nudges_the_derived_price() -> void:
	var a = load(ATTACK_PATH).new()
	var p = load("res://scripts/player/player.gd").new()
	var gun := _priced_gun()
	a.current_weapon = gun
	a.character = p
	var base := a._shot_stamina_cost()
	gun.stamina_cost_mult = 0.75
	assert_almost_eq(a._shot_stamina_cost(), base * 0.75, 0.001,
		"stamina_cost_mult TRIMS the derived price rather than replacing it")
	gun.stamina_cost_mult = 0.0
	assert_almost_eq(a._shot_stamina_cost(), 0.0, 0.001,
		"a 0.0 trim makes this weapon's fire free")
	p.stamina = 50.0
	a._spend_shot_stamina()
	assert_almost_eq(p.stamina, 50.0, 0.001,
		"a zero-cost weapon must not touch the pool at all")
	# Neither a negative trim nor negative damage may ever REFILL the pool on a trigger pull.
	gun.stamina_cost_mult = -5.0
	assert_almost_eq(a._shot_stamina_cost(), 0.0, 0.001,
		"a negative stamina_cost_mult floors to 0 instead of paying stamina back per shot")
	gun.stamina_cost_mult = 1.0
	gun.damage = -100.0
	assert_almost_eq(a._shot_stamina_cost(), 0.0, 0.001,
		"negative damage floors the effort to 0 rather than inverting the cost")
	p.free()
	a.free()
	gun = null


func test_shot_stamina_is_clamped_so_fire_never_outdrains_sprinting() -> void:
	# The structural guarantee: power x cadence cannot multiply into an absurd drain, because cost is capped at
	# stamina_shot_drain_ceiling x stamina_sprint_drain x attack_speed. Without it, a big payload on a fast
	# cadence would drain the pool faster than running does.
	var a = load(ATTACK_PATH).new()
	a.character = null
	var mv: PlayerMovementSettings = GameSettings.player_movement
	var absurd := _priced_gun(100.0, 0.125)  # SMG cadence, a hundred damage a round
	a.current_weapon = absurd
	var cost := a._shot_stamina_cost()
	var ceiling: float = mv.stamina_shot_drain_ceiling * mv.stamina_sprint_drain * 0.125
	assert_almost_eq(cost, ceiling, 0.001,
		"an over-powered weapon is clamped to its cadence ceiling instead of charging the derived price")
	assert_lt(cost / 0.125, mv.stamina_sprint_drain,
		"the clamp must hold sustained drain strictly under the sprint drain for ANY weapon a designer authors")
	a.free()
	absurd = null


func test_melee_weapon_pays_no_shot_stamina() -> void:
	var a = load(ATTACK_PATH).new()
	var p = load("res://scripts/player/player.gd").new()
	var melee := WeaponData.new()
	melee.is_melee = true
	melee.damage = 50.0            # ignored: effort never prices a swing
	melee.stamina_cost_mult = 3.0  # ignored: a swing is priced by stamina_melee_attack_cost, never here
	a.current_weapon = melee
	a.character = p
	assert_almost_eq(a._shot_stamina_cost(), 0.0, 0.001,
		"melee weapons are priced by stamina_melee_attack_cost, so their shot cost is 0 whatever their damage")
	p.stamina = 50.0
	a._spend_shot_stamina()
	assert_almost_eq(p.stamina, 50.0, 0.001,
		"a melee swing must not be double-charged through the ranged spend")
	p.free()
	a.free()
	melee = null


func test_shot_stamina_never_refuses_fire_on_an_empty_pool() -> void:
	# The deliberate melee/ranged asymmetry: _can_start_melee_attack() refuses a swing at zero, but there is no
	# equivalent shot gate - an exhausted player must still be able to shoot, so the spend simply no-ops.
	var a = load(ATTACK_PATH).new()
	var p = load("res://scripts/player/player.gd").new()
	var gun := _priced_gun()
	a.current_weapon = gun
	a.character = p
	assert_false(a.has_method("_can_start_shot"),
		"ranged fire must NOT grow a can-start stamina gate - an empty pool may never refuse a shot")
	p.stamina = 0.0
	a._spend_shot_stamina()
	assert_almost_eq(p.stamina, 0.0, 0.001,
		"firing on a pool ALREADY at zero is free - the spend no-ops rather than digging the debt deeper")
	p.free()
	a.free()
	gun = null


func test_shot_from_a_positive_but_insufficient_pool_overdraws_into_debt() -> void:
	# The sharp edge of the ungated design, pinned so the next reader doesn't mistake "never refuses a shot" for
	# "never costs more than you have". StaminaManager.can_spend_stamina is a HAS-ANY test (stamina > EPS), NOT
	# HAS-ENOUGH - so a shot fired on the last sliver of the pool pays in FULL and lands it NEGATIVE, exactly the
	# Dark-Souls overdraw melee/jump/slide already had. The consequence worth knowing: while the pool is in debt
	# every GATED verb is refused, so a last shell really can cost you the punch that follows it.
	var a = load(ATTACK_PATH).new()
	var p = load("res://scripts/player/player.gd").new()
	var gun := _priced_gun(2.0)  # a heavy round, and well clear of the cadence clamp
	a.current_weapon = gun
	a.character = p
	var cost := a._shot_stamina_cost()
	assert_gt(cost, 0.5,
		"the test weapon must cost more than the sliver of pool below, or this proves nothing")
	p.stamina = 0.5
	a._spend_shot_stamina()
	assert_almost_eq(p.stamina, 0.5 - cost, 0.001,
		"a shot from a positive-but-insufficient pool still pays the FULL cost and overdraws into debt")
	assert_lt(p.stamina, 0.0,
		"that overdraw must actually land negative - the clamp floor is -stamina_max, not 0")
	assert_false(p.can_spend_stamina(GameSettings.player_movement.stamina_melee_attack_cost),
		"while the pool is in debt the melee gate refuses, so shooting dry briefly costs you your fists too")
	p.free()
	a.free()
	gun = null


func test_firing_arms_the_long_shot_regen_hold_not_the_movement_one() -> void:
	# A shot must freeze recovery past its own cadence, which is what stops a weapon regenerating between shots
	# and paying for itself. StaminaManager.spend_stamina takes the hold as an optional second argument; Attack
	# passes stamina_regen_delay_after_shot, while every movement verb leaves it defaulted.
	var a = load(ATTACK_PATH).new()
	var p = load("res://scripts/player/player.gd").new()
	var gun := _priced_gun()
	a.current_weapon = gun
	a.character = p
	var mv: PlayerMovementSettings = GameSettings.player_movement
	p.stamina = 50.0
	a._spend_shot_stamina()
	assert_almost_eq(p._stamina_mgr._stamina_regen_delay_left, mv.stamina_regen_delay_after_shot, 0.001,
		"firing must arm the LONG shot hold, not the short movement delay")
	# The movement default is still what an ordinary spend arms - a shot must not have changed jumps or slides.
	p._stamina_mgr._stamina_regen_delay_left = 0.0
	p.spend_stamina(5.0)
	assert_almost_eq(p._stamina_mgr._stamina_regen_delay_left, mv.stamina_regen_delay_after_spend, 0.001,
		"a plain one-argument spend still arms the movement delay, so jump / slide / dash feel is untouched")
	p.free()
	a.free()
	gun = null


func test_shot_stamina_is_safe_without_a_stamina_bearing_wielder() -> void:
	# An NPC wielder has no stamina pool (no spend_stamina method), and an unwired Attack has no wielder at all.
	# Both must be silent no-ops, exactly like the melee spend — AI fire is always free.
	var a = load(ATTACK_PATH).new()
	var gun := WeaponData.new()
	gun.is_melee = false
	a.current_weapon = gun
	a.character = null
	a._spend_shot_stamina()  # must not crash
	a.current_weapon = null
	assert_almost_eq(a._shot_stamina_cost(), 0.0, 0.001,
		"an Attack with no equipped weapon reports no shot stamina cost")
	a._spend_shot_stamina()  # must not crash
	a.free()
	gun = null


func test_swap_weapons_default_slots_empty() -> void:
	# weapon_slots defaults to [] (swap_weapons.gd) so the player starts with NOTHING; a designer populates it on
	# the SwapWeapons node in weapon.tscn (or assigns a Loadout) to hand out a starting kit.
	var sw := SwapWeapons.new()
	assert_eq(sw.weapon_slots.size(), 0,
		"the default loadout is empty -- the player starts with no weapons until the scene / a Loadout supplies them")
	sw.free()


func test_swap_weapons_try_equip_valid_index_emits() -> void:
	# _try_equip(0): slot 0 casts to WeaponData, so equip_this must fire. The default loadout is empty now, so
	# populate slot 0 first (a designer's authored kit).
	var sw := SwapWeapons.new()
	var slots: Array[Resource] = [load("res://resources/weapons/pistol.tres")]
	sw.weapon_slots = slots
	add_child_autofree(sw)
	watch_signals(sw)
	sw._try_equip(0)
	assert_signal_emitted(sw, "equip_this",
		"Selecting a populated slot must broadcast equip_this so Attack/Inventory swap to that weapon.")


func test_swap_weapons_try_equip_out_of_range_does_not_emit() -> void:
	# Bounds guard: `var slots := effective_slots(); if index < 0 or index >= slots.size(): return`
	# (swap_weapons.gd). Neither -1 nor 999 may emit.
	var sw := SwapWeapons.new()
	add_child_autofree(sw)
	watch_signals(sw)
	sw._try_equip(-1)
	sw._try_equip(999)
	assert_signal_not_emitted(sw, "equip_this",
		"An out-of-range slot key must not emit a spurious equip_this — only bound slots (0..5) may trigger a weapon swap.")


func test_swap_weapons_request_equip_emits() -> void:
	# request_equip() is the public entry the inventory UI / equip bridge uses now that keys 1-7 are gone;
	# it must broadcast equip_this so Attack plays the swap and the hub re-equips.
	var sw := SwapWeapons.new()
	add_child_autofree(sw)
	watch_signals(sw)
	var pistol: WeaponData = load("res://resources/weapons/pistol.tres")
	sw.request_equip(pistol)
	assert_signal_emitted(sw, "equip_this",
		"request_equip(weapon) must emit equip_this — it's the swap path the UI triggers instead of a number key.")


func test_swap_weapons_request_equip_null_is_noop() -> void:
	# A null weapon (e.g. an empty/non-weapon item) must not fire a spurious swap.
	var sw := SwapWeapons.new()
	add_child_autofree(sw)
	watch_signals(sw)
	sw.request_equip(null)
	assert_signal_not_emitted(sw, "equip_this",
		"request_equip(null) must emit nothing — there's no weapon to draw.")


# ---------------------------------------------------------------------------
# Throwable (Throwable.gd) — gib-confetti ELIGIBILITY GUARD logic.
# A RigidBody3D whose _ready() arms contact monitoring, connects body_entered,
# builds the overlay chain AND stamps _spawn_msec = Time.get_ticks_msec(). We
# instantiate WITHOUT add_child so _ready never fires: this leaves _spawn_msec at
# its default 0 (so every gib reads as "stale" — far past confetti_fresh_window_ms)
# and avoids the tree/World3D entirely. data is set via `inter.data = d`; the
# _set_data setter only touches visuals under Engine.is_editor_hint(), so outside
# the editor it is a plain assignment (a no-op beyond storing the value).
#
# What we deliberately SKIP and why:
#   - The POSITIVE path (_is_confetti_kill returning true) is intentionally NOT
#     unit-tested: it falls through every guard to _is_airborne(), which derefs
#     get_world_3d().direct_space_state and casts a real raycast — that needs a
#     live tree + World3D + physics space and cannot run on a bare instance. The
#     four early-return guards below (data/is_gib, eligibility, freshness, attacker)
#     each short-circuit BEFORE that world access, so they ARE safe to assert here.
#   - _destroy() / on_impact() / take_damage() and the rest of the destruction
#     path (particles, decals, screen shake, AudioManager, queue_free) are NOT
#     exercised: they spawn nodes into get_tree().root, raycast the world, and
#     play audio — never safe to drive in a unit test without the real scene.
# ---------------------------------------------------------------------------

func test_throwable_look_name_defaults_to_generic_pick_up() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	assert_eq(inter.look_name(), "[PH] Pick Up",
		"An unnamed Throwable must keep the old generic hover prompt.")
	inter.free()


func test_throwable_look_name_uses_instance_display_name() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	inter.display_name = "Dog"
	assert_eq(inter.look_name(), "[PH] Pick Up Dog",
		"A named placed Throwable should render its noun after the shared Pick Up verb.")
	inter.free()


func test_throwable_look_name_uses_data_display_name_when_instance_blank() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	var d := ThrowableData.new()
	d.display_name = "Dog"
	inter.data = d
	assert_eq(inter.look_name(), "[PH] Pick Up Dog",
		"A reusable ThrowableData display_name should name any Throwable instance that does not override it.")
	inter.free()


func test_throwable_instance_display_name_overrides_data_display_name() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	var d := ThrowableData.new()
	d.display_name = "Crate"
	inter.data = d
	inter.display_name = "Dog"
	assert_eq(inter.look_name(), "[PH] Pick Up Dog",
		"A placed Throwable's display_name should win over the shared data resource name.")
	inter.free()


func test_throwable_resolved_display_name_is_bare_noun() -> void:
	# resolved_display_name() is the verb-less twin of look_name() — external readers (Pettable's "[Q] Pet <name>")
	# want the NOUN only, not "Pick Up <name>".
	var inter = load("res://scripts/components/Throwable.gd").new()
	assert_eq(inter.resolved_display_name(), "",
		"An unnamed Throwable resolves to the empty noun (look_name then renders the generic 'Pick Up').")
	inter.display_name = "Dog"
	assert_eq(inter.resolved_display_name(), "Dog",
		"resolved_display_name returns the noun with NO 'Pick Up' verb, so 'Pet Dog' reads cleanly.")
	inter.free()


func test_throwable_resolved_display_name_falls_back_to_data() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	var d := ThrowableData.new()
	d.display_name = "Dog"
	inter.data = d
	assert_eq(inter.resolved_display_name(), "Dog",
		"A blank instance name resolves to the ThrowableData noun (so a pettable throwable reads 'Pet Dog').")
	assert_eq(inter.look_name(), "[PH] Pick Up Dog",
		"look_name still prefixes the verb over the SAME resolved noun — the refactor is output-identical.")
	inter.free()


func test_throwable_data_mesh_resource_pushes_to_visual_root() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	var mi := MeshInstance3D.new()
	inter.add_child(mi)
	inter.mesh_instance = mi
	var d := ThrowableData.new()
	var box := BoxMesh.new()
	d.mesh = box
	inter.data = d
	inter._apply_data_to_visuals()
	assert_eq(mi.mesh, box,
		"A ThrowableData mesh can be a raw Mesh resource, like an imported .obj.")
	inter.free()


func test_throwable_data_scene_resource_mounts_under_visual_root_and_fits_collision() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	var mi := MeshInstance3D.new()
	inter.add_child(mi)
	inter.mesh_instance = mi
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE
	cs.shape = shape
	inter.add_child(cs)
	inter.collision_shape = cs
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 3.0, 4.0)
	var d := ThrowableData.new()
	d.mesh = _packed_visual_scene(box)
	inter.data = d
	inter._apply_data_to_visuals()
	inter._autofit_collision_shape()
	assert_null(mi.mesh,
		"A scene model hides the placeholder mesh and mounts under the existing visual root.")
	var meshes: Array[MeshInstance3D] = []
	for mesh_node in TalkHelpers.collect_meshes(mi, null, true):
		if mesh_node.mesh != null:
			meshes.append(mesh_node)
	assert_eq(meshes.size(), 1,
		"The mounted scene's MeshInstance3D stays discoverable for outlines, carry fade, and materials.")
	if meshes.size() == 1:
		assert_eq(meshes[0].mesh, box,
			"The mounted scene uses the ThrowableData PackedScene's mesh.")
	assert_eq((cs.shape as BoxShape3D).size, Vector3(2.0, 3.0, 4.0),
		"Throwable collision auto-fit reads nested scene meshes, not only mesh_instance.mesh.")
	inter.free()


func test_throwable_face_travel_defaults_off() -> void:
	var t = load("res://scripts/components/Throwable.gd").new()
	assert_false(t.faces_travel_when_thrown(),
		"A throwable doesn't face its travel direction by default — crates tumble.")
	t.free()


func test_throwable_face_travel_instance_toggle() -> void:
	var t = load("res://scripts/components/Throwable.gd").new()
	t.face_travel_when_thrown = true
	assert_true(t.faces_travel_when_thrown(),
		"The per-instance toggle opts a placed throwable into facing its travel direction.")
	t.free()


func test_throwable_face_travel_inherits_data() -> void:
	var t = load("res://scripts/components/Throwable.gd").new()
	var d := ThrowableData.new()
	d.face_travel_when_thrown = true
	t.data = d
	assert_true(t.faces_travel_when_thrown(),
		"A ThrowableData that opts in makes any instance face its travel direction (instance left default).")
	t.free()


func test_throwable_face_travel_min_speed_resolves_instance_then_data_then_default() -> void:
	# The whole Throw Pose group is authorable on the resource: min_speed resolves instance(>0) -> data(>0) -> default.
	var t = load("res://scripts/components/Throwable.gd").new()
	assert_eq(t._resolved_face_travel_min_speed(), 2.0,
		"no instance/data override falls back to the default release speed")
	var d := ThrowableData.new()
	d.face_travel_min_speed = 5.0
	t.data = d
	assert_eq(t._resolved_face_travel_min_speed(), 5.0,
		"a ThrowableData min speed is used when the instance leaves it 0 (inherit)")
	t.face_travel_min_speed = 3.0
	assert_eq(t._resolved_face_travel_min_speed(), 3.0,
		"a per-instance min speed (> 0) overrides the data value")
	t.free()


func test_throwable_mark_thrown_for_facing_respects_toggle() -> void:
	# mark_thrown_for_facing arms the per-frame _integrate_forces facing ONLY when the prop opts in: a real throw of
	# a non-opted prop must not start facing. (_facing_travel read via get(); the in-flight orientation math in
	# _integrate_forces needs a live physics step, so it's left to manual playtest.)
	var off = load("res://scripts/components/Throwable.gd").new()
	off.mark_thrown_for_facing()
	assert_false(off.get("_facing_travel"),
		"Throwing a prop that didn't opt in must NOT arm travel-facing.")
	off.free()

	var on = load("res://scripts/components/Throwable.gd").new()
	on.face_travel_when_thrown = true
	on.mark_thrown_for_facing()
	assert_true(on.get("_facing_travel"),
		"Throwing an opted-in prop arms travel-facing.")
	on.free()


func test_throwable_pickup_sound_defaults_to_silent() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	assert_true(inter._pickup_sound() == null,
		"An unconfigured Throwable should have no pickup sound by default.")
	inter.free()


func test_throwable_character_impact_sound_defaults_to_null() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	assert_true(inter._character_impact_sound() == null,
		"With no instance/data character-impact sound, a character hit falls back to the generic thud.")
	inter.free()


func test_throwable_character_impact_sound_resolves_instance_then_data() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	var d := ThrowableData.new()
	var data_bite := AudioStreamWAV.new()
	d.character_impact_sound = data_bite
	inter.data = d
	assert_eq(inter._character_impact_sound(), data_bite,
		"A ThrowableData character-impact sound is used when the instance doesn't override it (the Dog's bite on its .tres).")
	var instance_bite := AudioStreamWAV.new()
	inter.character_impact_sound = instance_bite
	assert_eq(inter._character_impact_sound(), instance_bite,
		"A per-instance character-impact sound overrides the data one.")
	inter.free()


func test_throwable_pickup_sound_uses_data_sound_when_instance_blank() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	var stream := AudioStreamWAV.new()
	var d := ThrowableData.new()
	d.pickup_sound = stream
	inter.data = d
	assert_true(inter._pickup_sound() == stream,
		"A reusable ThrowableData pickup_sound should supply the pickup SFX for instances that do not override it.")
	inter.free()
	stream = null


func test_throwable_pickup_sound_instance_overrides_data_sound() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	var data_stream := AudioStreamWAV.new()
	var instance_stream := AudioStreamWAV.new()
	var d := ThrowableData.new()
	d.pickup_sound = data_stream
	inter.data = d
	inter.pickup_sound = instance_stream
	assert_true(inter._pickup_sound() == instance_stream,
		"A placed Throwable's pickup_sound should win over the shared data resource sound.")
	inter.free()
	data_stream = null
	instance_stream = null


func test_throwable_held_loop_sound_defaults_to_silent() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	assert_true(inter._held_loop_sound() == null,
		"An unconfigured Throwable should have no held-loop sound by default.")
	inter.free()


func test_throwable_held_loop_sound_uses_data_sound_when_instance_blank() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	var stream := AudioStreamWAV.new()
	var d := ThrowableData.new()
	d.held_loop_sound = stream
	inter.data = d
	assert_true(inter._held_loop_sound() == stream,
		"A reusable ThrowableData held_loop_sound should supply the looping carry SFX for instances that do not override it.")
	inter.free()
	stream = null


func test_throwable_held_loop_sound_instance_overrides_data_sound() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	var data_stream := AudioStreamWAV.new()
	var instance_stream := AudioStreamWAV.new()
	var d := ThrowableData.new()
	d.held_loop_sound = data_stream
	inter.data = d
	inter.held_loop_sound = instance_stream
	assert_true(inter._held_loop_sound() == instance_stream,
		"A placed Throwable's held_loop_sound should win over the shared data resource loop.")
	inter.free()
	data_stream = null
	instance_stream = null


func test_throwable_release_sound_defaults_to_silent() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	assert_true(inter._release_sound() == null,
		"An unconfigured Throwable should have no release sound by default.")
	inter.free()


func test_throwable_release_sound_uses_data_sound_when_instance_blank() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	var stream := AudioStreamWAV.new()
	var d := ThrowableData.new()
	d.release_sound = stream
	inter.data = d
	assert_true(inter._release_sound() == stream,
		"A reusable ThrowableData release_sound should supply the drop/throw SFX for instances that do not override it.")
	inter.free()
	stream = null


func test_throwable_release_sound_instance_overrides_data_sound() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	var data_stream := AudioStreamWAV.new()
	var instance_stream := AudioStreamWAV.new()
	var d := ThrowableData.new()
	d.release_sound = data_stream
	inter.data = d
	inter.release_sound = instance_stream
	assert_true(inter._release_sound() == instance_stream,
		"A placed Throwable's release_sound should win over the shared data resource sound.")
	inter.free()
	data_stream = null
	instance_stream = null


func test_throwable_face_carrier_defaults_off() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	assert_false(inter.faces_carrier_while_held(),
		"An unconfigured Throwable should preserve its old held rotation by default.")
	inter.free()


func test_throwable_face_carrier_reads_data_opt_in() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	var d := ThrowableData.new()
	d.face_carrier_while_held = true
	inter.data = d
	assert_true(inter.faces_carrier_while_held(),
		"A reusable ThrowableData can opt every instance into facing the carrier while held.")
	inter.free()


func test_throwable_face_carrier_reads_instance_opt_in() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	inter.face_carrier_while_held = true
	assert_true(inter.faces_carrier_while_held(),
		"A placed Throwable can opt just that instance into facing the carrier while held.")
	inter.free()


func test_throwable_face_carrier_offset_combines_data_and_instance_degrees() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	var d := ThrowableData.new()
	d.face_carrier_rotation_degrees = Vector3(0.0, 90.0, 0.0)
	inter.data = d
	inter.face_carrier_rotation_degrees = Vector3(0.0, 45.0, 0.0)
	var offset: Vector3 = inter._face_carrier_offset_radians()
	assert_almost_eq(offset.y, deg_to_rad(135.0), 0.0001,
		"data + instance face-carrier offsets should combine so a shared import-axis fix can be nudged per prop.")
	inter.free()


func test_throwable_face_carrier_preserves_scale_with_rotation_offset() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	inter.face_carrier_while_held = true
	inter.face_carrier_rotation_degrees = Vector3(0.0, 180.0, 0.0)
	# face_carrier() reads global_transform/global_position and calls look_at — all of which return
	# identity (and raise tracked engine errors GUT 9.6 fails on) on an off-tree node. Put it in the
	# tree first so the transform set below AND the global-space reads inside face_carrier operate on a
	# real transform; add_child_autofree owns teardown (so the trailing inter.free() is dropped).
	add_child_autofree(inter)
	var authored_scale := Vector3(0.3, 0.3, 0.3)
	inter.global_transform = Transform3D(Basis.IDENTITY.scaled(authored_scale), Vector3.ZERO)
	inter.face_carrier(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 5.0)))
	var resulting_scale: Vector3 = inter.global_transform.basis.get_scale()
	assert_almost_eq(resulting_scale.x, authored_scale.x, 0.0001,
		"face_carrier must preserve authored X scale when applying a rotation offset.")
	assert_almost_eq(resulting_scale.y, authored_scale.y, 0.0001,
		"face_carrier must preserve authored Y scale when applying a rotation offset.")
	assert_almost_eq(resulting_scale.z, authored_scale.z, 0.0001,
		"face_carrier must preserve authored Z scale when applying a rotation offset.")


func test_throwable_held_visibility_defaults_to_fade() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	assert_true(inter.fades_while_held(),
		"An unconfigured Throwable should keep the old see-through held-object behavior.")
	inter.free()


func test_throwable_held_visibility_inherits_data_opaque_opt_out() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	var d := ThrowableData.new()
	d.fade_while_held = false
	inter.data = d
	assert_false(inter.fades_while_held(),
		"A reusable ThrowableData can make every prop of that type opaque while held.")
	inter.free()


func test_throwable_held_visibility_instance_can_force_fade_over_data() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	var d := ThrowableData.new()
	d.fade_while_held = false
	inter.data = d
	inter.held_visibility_mode = Throwable.HeldVisibilityMode.FADE
	assert_true(inter.fades_while_held(),
		"A placed Throwable can force carry fade even when its shared data is opaque.")
	inter.free()


func test_throwable_held_visibility_instance_can_force_opaque() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	inter.held_visibility_mode = Throwable.HeldVisibilityMode.OPAQUE
	assert_false(inter.fades_while_held(),
		"A placed Throwable can stay opaque while held without needing a custom data resource.")
	inter.free()


func test_throwable_breathe_defaults_off() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	assert_false(inter.breathes(),
		"An unconfigured Throwable should stay visually static by default.")
	assert_eq(inter._resolved_breathe_amount(), 0.03,
		"Default throwable breathe amount mirrors the NPC torso breathe amount.")
	assert_eq(inter._resolved_breathe_rate(), 1.6,
		"Default throwable breathe rate mirrors the NPC torso breathe rate.")
	inter.free()


func test_throwable_breathe_reads_data_opt_in() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	var d := ThrowableData.new()
	d.breathe = true
	inter.data = d
	assert_true(inter.breathes(),
		"A reusable ThrowableData can opt every living prop of that type into breathing.")
	inter.free()


func test_throwable_breathe_reads_instance_opt_in() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	inter.breathe = true
	assert_true(inter.breathes(),
		"A placed Throwable can opt just that instance into breathing.")
	inter.free()


func test_throwable_breathe_instance_tuning_overrides_data_tuning() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	var d := ThrowableData.new()
	d.breathe_amount = 0.02
	d.breathe_rate = 0.8
	inter.data = d
	inter.breathe_amount = 0.08
	inter.breathe_rate = 2.4
	assert_eq(inter._resolved_breathe_amount(), 0.08,
		"A placed Throwable's positive breathe_amount should override the shared data amount.")
	assert_eq(inter._resolved_breathe_rate(), 2.4,
		"A placed Throwable's positive breathe_rate should override the shared data rate.")
	inter.free()


func test_throwable_breathe_scales_visual_only() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	var mi := MeshInstance3D.new()
	mi.scale = Vector3(2.0, 3.0, 4.0)
	inter.mesh_instance = mi
	inter.add_child(mi)
	inter.breathe = true
	inter.breathe_amount = 0.1
	inter.breathe_rate = 1.0
	inter.hp = 1
	inter._cache_breathe_base_scale()
	var body_scale: Vector3 = inter.scale
	inter._animate_breathing(PI * 0.5)
	assert_eq(inter.scale, body_scale,
		"Throwable breathing must not resize the RigidBody/collider root.")
	assert_almost_eq(mi.scale.x, 2.2, 0.0001,
		"Throwable breathing should pulse the visual mesh around its authored X scale.")
	assert_almost_eq(mi.scale.y, 3.3, 0.0001,
		"Throwable breathing should pulse the visual mesh around its authored Y scale.")
	assert_almost_eq(mi.scale.z, 4.4, 0.0001,
		"Throwable breathing should pulse the visual mesh around its authored Z scale.")
	inter.free()


func test_interactable_confetti_eligible_true_on_fresh_instance() -> void:
	# `var _confetti_eligible: bool = true` (Throwable.gd:38) — a fresh gib is
	# eligible for the confetti trick-shot until something picks it up.
	var inter = load("res://scripts/components/Throwable.gd").new()
	assert_true(inter._confetti_eligible,
		"A freshly-spawned Throwable must start confetti-eligible — a gib straight off a kill is the only thing that can earn the trick-shot confetti.")
	inter.free()


func test_interactable_on_picked_up_clears_confetti_eligible() -> void:
	# on_picked_up() body: `_confetti_eligible = false` (Throwable.gd:435-436).
	# Picking a gib up disqualifies it from the confetti trick-shot (anti-cheese).
	var inter = load("res://scripts/components/Throwable.gd").new()
	inter.on_picked_up(null)
	assert_false(inter._confetti_eligible,
		"on_picked_up() must clear _confetti_eligible so a picked-up/thrown gib can't be shot for cheesed confetti.")
	inter.free()


func test_interactable_is_confetti_kill_false_when_data_null() -> void:
	# First guard: `if data == null or not data.is_gib: return false`
	# (Throwable.gd:290-291). With no data resource at all it must bail out
	# immediately — before any eligibility/freshness/world access.
	var inter = load("res://scripts/components/Throwable.gd").new()
	assert_false(inter._is_confetti_kill(null),
		"_is_confetti_kill() must return false when data is null — a prop with no ThrowableData is never a gib and can't confetti.")
	inter.free()


func test_interactable_is_confetti_kill_false_for_non_gib_data() -> void:
	# Same first guard via the `not data.is_gib` arm: a crate-style ThrowableData
	# (is_gib defaults to false) must never confetti.
	var inter = load("res://scripts/components/Throwable.gd").new()
	var d := ThrowableData.new()
	# is_gib defaults to false (throwable_data.gd:89) — a plain crate.
	inter.data = d
	assert_false(inter._is_confetti_kill(null),
		"_is_confetti_kill() must return false for a non-gib ThrowableData — crates and barrels never burst into confetti, only gore gibs.")
	inter.free()


func test_interactable_is_confetti_kill_false_after_pickup() -> void:
	# Eligibility guard: `if not _confetti_eligible: return false`
	# (Throwable.gd:292-293). With a GIB data resource the first guard passes,
	# but on_picked_up() has cleared eligibility — and that gate short-circuits
	# BEFORE any world/raycast access, so this is safe with no tree.
	var inter = load("res://scripts/components/Throwable.gd").new()
	var d := ThrowableData.new()
	d.is_gib = true
	inter.data = d
	inter.on_picked_up(null)
	assert_false(inter._is_confetti_kill(null),
		"_is_confetti_kill() must return false once a gib has been picked up — the eligibility gate disqualifies a thrown gib before any world access.")
	inter.free()


func test_interactable_is_confetti_kill_false_for_stale_gib() -> void:
	# Freshness guard: `if Time.get_ticks_msec() - _spawn_msec >= confetti_fresh_window_ms: return false`.
	# Stamp _spawn_msec deterministically into the PAST (older than the window) so staleness never depends
	# on how long the engine has been up. The freshness gate (3rd check) trips BEFORE the attacker/world
	# checks, so even a valid Player-group attacker still yields false — proving it's the staleness (not a
	# null attacker) that disqualifies the gib, and confirming no World3D is ever touched on this path.
	var inter = load("res://scripts/components/Throwable.gd").new()
	var d := ThrowableData.new()
	d.is_gib = true
	inter.data = d
	inter._spawn_msec = Time.get_ticks_msec() - inter.confetti_fresh_window_ms - 1000
	var attacker := Node.new()
	attacker.add_to_group(&"Player")
	assert_false(inter._is_confetti_kill(attacker),
		"_is_confetti_kill() must return false for a stale gib — only a gib fresh off a kill (within confetti_fresh_window_ms) qualifies; the freshness gate trips before the attacker/world checks.")
	attacker.free()
	inter.free()
