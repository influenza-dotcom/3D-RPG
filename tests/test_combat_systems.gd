extends GutTest

## GUT coverage for the Combat systems subsystem: the combat scripts under res://scripts/combat (weapon_system.gd,
## scope_in.gd, swap_weapons.gd, attack.gd, spray_painter.gd), the Throwable carry / breathing / gib-confetti seams, and
## the stamina price and AGILITY scaling Attack applies to a weapon's clocks.
##
## How the parts are driven without weapon.tscn's _ready:
##   - Attack is NEVER add_child'd (its _ready connects a null inventory and reads @onready $ShellImpact). Its attack /
##     reload / swap slots get real one-shot Timers parented under THIS test instead (_give_timers), because
##     Timer.start() errors off-tree. That is enough to drive the real reload, cooldown, can_fire and scope gates.
##   - ScopeIn is ticked by calling _process by hand with a bare Camera3D, with "Zoom" held through
##     Input.action_press (after_each releases it).
##   - Weapon (weapon_system.gd) is built bare; setup() is never called (it dereferences every internal part).
##   - The Throwable carry-pose and confetti tests go IN the tree: they read global transforms / cast a world ray.
##
## Attack's fire path (_on_mouse_input_attack) is driven only as far as a committed pull (the gates, the round, the
## stamina, the cadence Timer): the off-tree Attack returns at its is_inside_tree() check before the muzzle flash.
## Still NOT driven here: the rest of the shot and the spray / colour-picker path (spawns into the world, raycasts,
## plays audio, calls FreezeFrame) and Throwable destruction (particles, decals, AudioManager). Player and NPC _ready
## never run.

const WEAPON_SYSTEM_PATH := "res://scripts/combat/weapon_system.gd"
const ATTACK_PATH := "res://scripts/combat/attack.gd"

## A Player whose throw_equipped_weapon() only COUNTS the request and succeeds, so Attack's scoped-throw decision can
## be observed without a carry rig. Built at runtime and never add_child'd, so Player._ready never runs.
const THROW_SPY_SOURCE := "extends \"res://scripts/player/player.gd\"\nvar throws: int = 0\nfunc throw_equipped_weapon() -> bool:\n\tthrows += 1\n\treturn true\n"

var _throw_spy_script: GDScript = null


func after_each() -> void:
	Input.action_release("Zoom")  # the ScopeIn tests hold ADS through the real action; never leak it into the next test


func after_all() -> void:
	_throw_spy_script = null


func _new_throw_spy():
	if _throw_spy_script == null:
		_throw_spy_script = GDScript.new()
		_throw_spy_script.source_code = THROW_SPY_SOURCE
		_throw_spy_script.reload()
	return _throw_spy_script.new()


## Real one-shot Timers in the attack / reload / swap slots of a bare, OFF-tree Attack. The Timers are parented under
## this test (Timer.start() errors off-tree) and autofreed; the Attack itself is still never add_child'd.
func _give_timers(a) -> void:
	for slot in [&"attack", &"reload", &"swap"]:
		var t := Timer.new()
		t.one_shot = true
		add_child_autofree(t)
		a.set(slot, t)


## An EMPTY, caliber-less (free refill) clip for `weapon`, parented under the off-tree Attack so freeing the Attack
## frees it too. Both of _on_reload_reload's clip gates (already full / no reserve supply) let a reload through.
func _give_empty_clip(a, weapon: WeaponData) -> Ammo:
	var clip := Ammo.new()
	clip.current_weapon = weapon
	clip.current_ammo = 0
	a.add_child(clip)
	a.clip = clip
	return clip


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


func test_weapon_reload_starts_the_wired_attacks_reload_and_is_a_noop_unwired() -> void:
	# reload() is the AI wielder's ONLY reload (an NPC has no reload input). One rig for both halves: a real Attack
	# holding an empty, free-refill clip that WOULD reload, first not yet handed to the Weapon (the state before setup()
	# wires the parts), then wired. Only the wiring differs, so the first half is the guard and the second its control.
	var gun := _priced_gun()
	gun.reload_time = 2.0
	var a = load(ATTACK_PATH).new()
	_give_timers(a)
	a.current_weapon = gun
	_give_empty_clip(a, gun)
	var w = load(WEAPON_SYSTEM_PATH).new()
	watch_signals(a)
	w.reload()
	assert_true(a.reload.is_stopped(),
		"an unwired Weapon's reload() must be a silent no-op: before setup() it has no Attack to reload through")
	assert_signal_not_emitted(a, "reload_started",
		"no reload may start through a Weapon that is not wired to this Attack")
	w.attack = a
	w.reload()
	assert_false(a.reload.is_stopped(),
		"once wired, reload() must start the Attack's real reload, or an NPC that runs its clip dry can never refill it")
	assert_almost_eq(a.reload.wait_time, 2.0, 0.0001,
		"a wielder-less reload runs for the weapon's authored reload_time")
	assert_signal_emitted(a, "reload_started",
		"the AI reload must emit the same reload_started a player reload does, so its listeners hear it")
	w.free()
	a.free()
	gun = null


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
# ScopeIn (scope_in.gd) — the ADS state machine. Never add_child'd: _process is called by hand with a bare Camera3D
# and a bare Attack carrying real Timers, wired the way weapon.tscn wires them.
# ---------------------------------------------------------------------------

## A ScopeIn wired like weapon.tscn (camera + attack + scoped_in -> Attack._on_scope_in_scoped_in) around a bare
## Attack with real Timers, holding `weapon`. Free with _free_scope_rig.
func _scope_rig(weapon: WeaponData) -> Dictionary:
	var a = load(ATTACK_PATH).new()
	_give_timers(a)
	a.current_weapon = weapon
	var cam := Camera3D.new()
	cam.fov = GameSettings.camera.default_fov
	var si := ScopeIn.new()
	si.camera = cam
	si.attack = a
	si.scoped_in.connect(a._on_scope_in_scoped_in)
	return {"a": a, "cam": cam, "si": si}


func _free_scope_rig(rig: Dictionary) -> void:
	rig["si"].free()
	rig["cam"].free()
	rig["a"].free()


func test_scope_in_fresh_rig_stays_at_the_hip_until_zoom_is_held() -> void:
	var gun := _priced_gun()
	var rig := _scope_rig(gun)
	var si: ScopeIn = rig["si"]
	var cam: Camera3D = rig["cam"]
	var rest_fov := cam.fov
	watch_signals(si)
	si._process(0.1)
	assert_false(si.is_scoped,
		"a freshly spawned weapon with Zoom released must be at the hip")
	assert_signal_not_emitted(si, "scoped_in",
		"a fresh rig must not pulse scoped_in on its first frame: a ScopeIn that began life scoped drops out of ADS here and jolts the spread/FOV with no input")
	Input.action_press("Zoom")
	si._process(0.1)
	assert_true(si.is_scoped,
		"holding Zoom on an idle, loaded, drawn weapon must enter ADS (Attack.can_fire() and can_enter_scope() both allow it)")
	assert_eq(get_signal_parameters(si, "scoped_in"), [true],
		"entering ADS must tell Attack scoped_in(true)")
	assert_lt(cam.fov, rest_fov,
		"entering ADS must start narrowing the camera toward the scoped FOV")
	Input.action_release("Zoom")
	si._process(0.1)
	assert_false(si.is_scoped, "releasing Zoom must drop the scope")
	assert_eq(get_signal_parameters(si, "scoped_in"), [false],
		"leaving ADS must tell Attack scoped_in(false)")
	_free_scope_rig(rig)
	gun = null


func test_scope_in_refuses_ads_mid_reload_and_a_reload_breaks_it_but_a_shot_cooldown_does_not() -> void:
	var gun := _priced_gun()
	var rig := _scope_rig(gun)
	var si: ScopeIn = rig["si"]
	var a = rig["a"]
	Input.action_press("Zoom")
	a.reload.start(2.0)
	si._process(0.1)
	assert_false(si.is_scoped,
		"Zoom held mid-reload must NOT enter ADS: the gun is down for the magazine change")
	a.reload.stop()
	si._process(0.1)
	assert_true(si.is_scoped,
		"the same held Zoom enters ADS as soon as the reload is over (control: only the reload refused it)")
	a.attack.start(0.44)
	si._process(0.1)
	assert_true(si.is_scoped,
		"a per-shot cooldown must NOT break ADS, or every automatic weapon would drop out of the scope between shots")
	a.attack.stop()
	a.reload.start(2.0)
	si._process(0.1)
	assert_false(si.is_scoped,
		"a reload starting while scoped must force the scope off even with Zoom still held")
	_free_scope_rig(rig)
	gun = null


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
# Attack (attack.gd) — bare instance, NEVER add_child'd: _ready connects inventory.weapon_changed on a null inventory
# and relies on @onready $ShellImpact. Tests that need the attack / reload / swap clocks give it in-tree Timers
# (_give_timers); a bare instance without them must not call can_fire() / is_reload_or_swap_active().
# ---------------------------------------------------------------------------

func test_attack_starts_at_the_hip_and_only_a_scope_in_arms_the_scoped_weapon_throw() -> void:
	# A throw_on_scoped_attack knife is a knife at the HIP and a thrown knife only while aimed. Attack learns it is aimed
	# solely from ScopeIn's scoped_in signal, so a fresh Attack must start un-scoped: one that began life "scoped" would
	# hurl the player's knife on the very first hip click.
	var knife := _slow_melee(0.88, 0.1)
	knife.throw_on_scoped_attack = true
	knife.pellet_spread = 6.0
	var a = load(ATTACK_PATH).new()
	_give_timers(a)
	var hands = _new_throw_spy()
	a.character = hands
	a._on_weapon_changed(knife)  # what the inventory's weapon_changed does on equip: seeds current_weapon + spread
	assert_false(a._try_scoped_weapon_throw(false),
		"a fresh Attack is at the hip, so a click with a throwable knife must stay an ordinary swing")
	assert_eq(hands.throws, 0, "a hip click must never ask the wielder to throw its weapon")
	a._on_scope_in_scoped_in(true)
	assert_lt(a.current_spread, 6.0, "scoping in must tighten the spread")
	assert_almost_eq(a.current_spread * GameSettings.weapon_general.scope_spread_divisor, 6.0, 0.0001,
		"and by exactly scope_spread_divisor, the knob that tunes ADS accuracy")
	assert_true(a._try_scoped_weapon_throw(false),
		"once scoped, the same click with the same knife IS the throw (control: only the scope state changed)")
	assert_eq(hands.throws, 1, "the throw must go through the wielder's hands exactly once")
	a.attack.stop()
	a._on_scope_in_scoped_in(false)
	assert_almost_eq(a.current_spread, 6.0, 0.0001, "scoping out must restore the hip spread")
	assert_false(a._try_scoped_weapon_throw(false),
		"scoping back out must return the next click to an ordinary swing")
	assert_eq(hands.throws, 1, "no second throw after scoping out")
	hands.free()
	a.free()
	knife = null


func test_attack_secondary_cooldown_shares_the_cadence_of_the_weapon_that_acted() -> void:
	# start_secondary_cooldown lets a non-firing action (the ADS knife throw) block the next attack for one cadence.
	# The Attack is wielder-less, so every cadence expected here is the weapon's authored attack_speed.
	var fists := _slow_melee(1.2, 0.2)
	var knife := _slow_melee(0.88, 0.1)
	var a = load(ATTACK_PATH).new()
	_give_timers(a)
	a.start_secondary_cooldown()
	assert_true(a.attack.is_stopped(),
		"with nothing equipped and no weapon passed there is no cadence to share, so no cooldown may start")
	a.current_weapon = fists
	assert_true(a.can_fire(), "guard: an idle, drawn Attack can fire before the cooldown")
	a.start_secondary_cooldown()
	assert_false(a.can_fire(),
		"a secondary cooldown must block the next attack exactly like a shot's own cooldown")
	assert_almost_eq(a.attack.wait_time, 1.2, 0.0001,
		"with no weapon passed the cooldown paces at the equipped weapon's cadence")
	a.attack.stop()
	a.start_secondary_cooldown(knife)
	assert_almost_eq(a.attack.wait_time, 0.88, 0.0001,
		"the knife throw re-arms the FISTS before it settles up and passes the knife: the cooldown must pace at the knife's 0.88 s, not the fists' 1.2 s")
	a.free()
	fists = null
	knife = null


func test_attack_weapon_swap_lowers_then_raises_and_chains_a_request_queued_mid_swap() -> void:
	# The swap Timer runs TWICE per swap: the down phase, whose end mounts the new model (swap_finished), then the raise,
	# whose end frees the gun to fire. A fresh Attack must read its first swap timeout as the DOWN phase, or the new
	# weapon's model never mounts. The Timer's timeout is unconnected here, so each timeout is played by hand the way a
	# one-shot Timer delivers it: stopped first, then the callback.
	var pistol := _priced_gun()
	var knife := _slow_melee(0.88, 0.1)
	var shotgun := _priced_gun(2.0, 0.9)
	var a = load(ATTACK_PATH).new()
	_give_timers(a)
	var inv := Inventory.new()
	a.inventory = inv
	inv.weapon_changed.connect(a._on_weapon_changed)  # the connection Attack._ready makes
	inv.equip(pistol)
	watch_signals(a)
	a._on_swap_weapons_equip_this(knife)
	assert_signal_emit_count(a, "swap_started", 1, "picking another weapon must start a swap")
	assert_true(a.current_weapon == knife, "the swap equips the picked weapon on the hub as it starts")
	assert_false(a.can_fire(), "nothing may fire while the old weapon is going down")
	a._on_swap_weapons_equip_this(shotgun)
	assert_signal_emit_count(a, "swap_started", 1,
		"a second pick mid-swap must be queued, not started over the swap already running")
	a.swap.stop()
	a._on_swap_timeout()
	assert_signal_emit_count(a, "swap_finished", 1,
		"the FIRST swap timeout on a fresh Attack is the down phase: it must mount the new weapon's model")
	assert_false(a.swap.is_stopped(), "and start the raise, so firing stays blocked until the gun is back up")
	assert_almost_eq(a.swap.wait_time, GameSettings.weapon_general.swap_raise_duration, 0.0001,
		"the raise runs for swap_raise_duration")
	a.swap.stop()
	a._on_swap_timeout()
	assert_signal_emit_count(a, "swap_finished", 1, "the raise ending must not mount a model a second time")
	assert_signal_emit_count(a, "swap_started", 2,
		"the raise ending must chain the pick queued mid-swap, so the LAST selection is what ends up in your hands")
	assert_true(a.current_weapon == shotgun, "the queued shotgun is the weapon being drawn now")
	a.free()
	inv.free()
	pistol = null
	knife = null
	shotgun = null


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
		"ScopeIn._process calls can_enter_scope() before entering ADS — it must exist.")
	assert_true(a.has_method("try_fire"),
		"try_fire() is the AI-wielder fire entry point — it must exist for camera-less wielders to attack.")
	assert_true(a.has_method("start_secondary_cooldown"),
		"start_secondary_cooldown() lets secondary actions share the firing cadence — it must exist.")
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
# Attack stamina: the melee can-start gate + spend, and the derived per-shot ranged price. A bare Attack with a real
# off-tree Player as the wielder (its stamina pool works without _ready).
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
	# The melee can-start gate and the melee spend are MELEE-only. The gate is read on an EMPTY pool, where the same rig
	# refuses a melee weapon: StaminaManager.can_spend_stamina is a has-any test, so on any positive pool a swing would
	# pass too and a gun passing would prove nothing about the ranged exemption. The melee weapon is also the paying
	# control for the spend half.
	var a = load(ATTACK_PATH).new()
	var p = load("res://scripts/player/player.gd").new()
	var gun := _priced_gun()
	var melee := _slow_melee()
	var swing_cost: float = GameSettings.player_movement.stamina_melee_attack_cost
	assert_gt(swing_cost, 0.0, "precondition: a swing has a price, or the paying control below proves nothing")
	a.character = p
	p.stamina = 0.0
	a.current_weapon = melee
	assert_false(a._can_start_melee_attack(),
		"control: on an empty pool the melee stamina gate refuses a melee weapon")
	a.current_weapon = gun
	assert_true(a._can_start_melee_attack(),
		"a ranged weapon on the SAME empty pool is not held by the melee stamina gate")
	p.stamina = 5.0
	a._spend_melee_attack_stamina()
	assert_almost_eq(p.stamina, 5.0, 0.001,
		"a ranged weapon does not spend melee stamina")
	a.current_weapon = melee
	a._spend_melee_attack_stamina()
	assert_almost_eq(p.stamina, 5.0 - swing_cost, 0.001,
		"control: the same spend with the melee weapon equipped does charge the swing")
	p.free()
	a.free()
	gun = null
	melee = null


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
	var weak_cost: float = a._shot_stamina_cost()
	a.current_weapon = strong
	var strong_cost: float = a._shot_stamina_cost()
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
	var solid_cost: float = a._shot_stamina_cost()
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
	var base: float = a._shot_stamina_cost()
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
	var cost: float = a._shot_stamina_cost()
	assert_lt(cost, mv.stamina_shot_cost * absurd.stamina_effort(),
		"an over-powered weapon must be charged LESS than its derived price: the cadence ceiling has to bite")
	var absurder := _priced_gun(1000.0, 0.125)
	a.current_weapon = absurder
	assert_almost_eq(a._shot_stamina_cost(), cost, 0.001,
		"past the ceiling power stops mattering: ten times the damage at the same cadence costs the same per shot")
	assert_lt(cost / 0.125, mv.stamina_sprint_drain,
		"the clamp must hold sustained drain strictly under the sprint drain for ANY weapon a designer authors")
	a.free()
	absurd = null
	absurder = null


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
	# The deliberate melee/ranged asymmetry, driven through the real PLAYER trigger pull (_on_mouse_input_attack): on an
	# empty pool the stamina gate refuses a swing, but a gun still fires and its spend no-ops. The Attack is off-tree, so
	# a pull that gets through every gate (round consumed, stamina charged, cadence Timer started) returns at the
	# is_inside_tree() check before any world effect. A started cadence Timer is therefore the sign the pull was NOT
	# refused. Both weapons are auto_fire with no wind-up, so neither the semi-auto click check (which reads real Input)
	# nor a wind-up await (which needs the tree) is what decides the outcome.
	var gun := _priced_gun()
	gun.auto_fire = true
	var fists := _slow_melee(1.0, 0.0)
	fists.auto_fire = true
	var a = load(ATTACK_PATH).new()
	_give_timers(a)
	var p = load("res://scripts/player/player.gd").new()
	a.character = p
	var clip := _give_empty_clip(a, gun)
	clip.current_ammo = 6
	p.stamina = 0.0
	a.current_weapon = fists
	a._on_mouse_input_attack(null)
	assert_true(a.attack.is_stopped(),
		"control: on an empty pool the melee stamina gate refuses a swing through this same trigger pull")
	p.stamina = 5.0
	a._on_mouse_input_attack(null)
	assert_false(a.attack.is_stopped(),
		"control: the same swing goes through once the pool has stamina, so it was the empty pool that refused it")
	a.attack.stop()
	p.stamina = 0.0
	a.current_weapon = gun
	var rounds: int = clip.current_ammo
	a._on_mouse_input_attack(null)
	assert_false(a.attack.is_stopped(),
		"a gun on the SAME empty pool must still fire: an exhausted player keeps an attack, so there is no shot stamina gate")
	assert_eq(clip.current_ammo, rounds - 1,
		"the round is spent: the shot was committed, not refused")
	assert_almost_eq(p.stamina, 0.0, 0.001,
		"firing on a pool ALREADY at zero is free - the spend no-ops rather than digging the debt deeper")
	p.free()
	a.free()
	gun = null
	fists = null


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
	var cost: float = a._shot_stamina_cost()
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
	# An NPC wielder has no stamina pool (npc.gd has no spend_stamina method), and an unwired Attack has no wielder at
	# all. Both must be silent no-ops, exactly like the melee spend — AI fire is always free. The gun is PRICED, so the
	# spend gets past its zero-cost early return and really reaches the wielder duck-type: calling spend_stamina on the
	# NPC anyway would be a script error, and GUT fails a test on a script error. A Player wielding the same gun is the
	# control that pays. The NPC is built off-tree and never add_child'd, so its _ready never runs.
	var gun := _priced_gun()
	var a = load(ATTACK_PATH).new()
	a.current_weapon = gun
	var cost: float = a._shot_stamina_cost()
	assert_gt(cost, 0.0, "precondition: the shot has a price, so the spend cannot return before the wielder check")
	var npc = load("res://scripts/npc/npc.gd").new()
	assert_false(npc.has_method("spend_stamina"), "precondition: an NPC carries no stamina pool to charge")
	a.character = npc
	a._spend_shot_stamina()  # a priced shot from a stamina-less NPC: must be a silent no-op
	var p = load("res://scripts/player/player.gd").new()
	p.stamina = 50.0
	a.character = p
	a._spend_shot_stamina()
	assert_almost_eq(p.stamina, 50.0 - cost, 0.001,
		"control: the same priced shot charges a stamina-bearing wielder")
	a.character = null
	a._spend_shot_stamina()  # no wielder at all: a silent no-op
	a.current_weapon = null
	assert_almost_eq(a._shot_stamina_cost(), 0.0, 0.001,
		"an Attack with no equipped weapon reports no shot stamina cost")
	a._spend_shot_stamina()
	npc.free()
	p.free()
	a.free()
	gun = null


# ---------------------------------------------------------------------------
# SwapWeapons (swap_weapons.gd) — the only combat script safe to add_child:
# no _ready, no @onready. add_child_autofree lets watch_signals/assert_signal_*
# observe equip_this; _try_equip is called directly (not via input).
# ---------------------------------------------------------------------------

func test_shipped_weapon_prefab_starts_the_player_with_no_weapons() -> void:
	# The starting kit is read off the PREFAB, not the script default: Player seeds its backpack from
	# Weapon.weapon_loadout(), which reads the SwapWeapons child of the weapon.tscn it instantiates, so a slot or a
	# Loadout authored on that node would hand everyone a kit whatever swap_weapons.gd defaults to. Instantiated only,
	# never added to the tree (no _ready runs).
	var w = load("res://scenes/weapons/weapon.tscn").instantiate()
	assert_true(w.get_node_or_null("SwapWeapons") is SwapWeapons,
		"weapon.tscn must keep its SwapWeapons child, or weapon_loadout() reads [] for the wrong reason and the check below proves nothing")
	assert_eq(w.weapon_loadout().size(), 0,
		"SHIP DECISION: the player starts with NO weapons (scavenge your own gear), so the shipped weapon prefab must not author a starting kit")
	assert_true(w.loadout() == null,
		"SHIP DECISION: no Loadout resource on the shipped prefab may hand out a kit, clips or money either")
	w.free()


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
	# ONE authored slot, so both out-of-range edges and the in-range control share a rig: -1 (a negative index would
	# WRAP to the last slot in GDScript) and slots.size() (the first index past the end) must both be refused, while
	# slot 0 of the same loadout emits.
	var sw := SwapWeapons.new()
	var pistol: WeaponData = load("res://resources/weapons/pistol.tres")
	var slots: Array[Resource] = [pistol]
	sw.weapon_slots = slots
	add_child_autofree(sw)
	watch_signals(sw)
	sw._try_equip(-1)
	sw._try_equip(1)
	assert_signal_not_emitted(sw, "equip_this",
		"An out-of-range slot key (-1, or one past the last authored slot) must not emit a spurious equip_this — only an index inside the authored slots may trigger a weapon swap.")
	sw._try_equip(0)
	assert_signal_emit_count(sw, "equip_this", 1,
		"control: the in-range slot of the same loadout does emit, so the refusals above came from the bounds check")
	assert_eq(get_signal_parameters(sw, "equip_this"), [pistol],
		"and it hands out that slot's weapon")


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
# Throwable (Throwable.gd) — the instance -> ThrowableData -> default resolvers, the carry pose, breathing, and the
# gib-confetti trick-shot. Most tests build the prop OFF-tree (load(...).new(), no add_child) so _ready never arms
# contact monitoring or builds the overlay chain; `inter.data = d` is a plain assignment outside the editor.
# The carry-pose and confetti tests go IN the tree (they read global transforms / cast a world ray).
# Not exercised: _destroy() / on_impact() / take_damage() (particles, decals, screen shake, AudioManager, queue_free).
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


# The READY-TO-THROW carry pose (face_carrier_reversed — every weapon) must follow the carrier's look UP AND DOWN,
# not just its yaw. The pose flattened the aim before, so a held weapon sat dead level no matter where you aimed;
# it also disagreed with the throw, which PickupRay._release always launched along the carrier's FULL forward
# (-basis.z). These pin the two halves of that: the reversed pose takes the pitch, and it takes it EXACTLY (same
# vector as the launch), so what is in your hands lies along the throw it is about to make.
func test_throwable_reversed_carry_pose_follows_carrier_pitch() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	inter.face_carrier_while_held = true
	inter.face_carrier_reversed = true
	add_child_autofree(inter)  # face_carrier reads global_transform / calls look_at — off-tree those are identity
	inter.global_transform = Transform3D(Basis.IDENTITY, Vector3.ZERO)
	# A carrier looking 40° DOWN, standing back and above the prop (the hold anchor sits ahead of the camera).
	var carrier := Transform3D(Basis.from_euler(Vector3(deg_to_rad(-40.0), 0.0, 0.0)), Vector3(0.0, 1.0, 1.5))
	inter.face_carrier(carrier)
	var prop_front: Vector3 = (-inter.global_transform.basis.z).normalized()
	var carrier_front: Vector3 = (-carrier.basis.z).normalized()
	assert_almost_eq(prop_front.dot(carrier_front), 1.0, 0.0001,
		"the ready-to-throw pose must point down the carrier's FULL forward — the same vector PickupRay._release throws along")
	assert_lt(prop_front.y, -0.5,
		"looking 40 degrees down must dip the held weapon's business end, not leave it level")


# ...and the PRESENTED pose (the dog, face_carrier_reversed OFF) must NOT take the pitch: a dog held out at arm's
# length should keep its feet under it when you glance at the floor. Same carrier, opposite expectation — this is
# the guard that the pitch fix stayed on the weapon side of the branch.
func test_throwable_presented_carry_pose_stays_level_through_pitch() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	inter.face_carrier_while_held = true  # reversed left OFF: presented, not ready-to-throw
	add_child_autofree(inter)
	inter.global_transform = Transform3D(Basis.IDENTITY, Vector3.ZERO)
	var carrier := Transform3D(Basis.from_euler(Vector3(deg_to_rad(-40.0), 0.0, 0.0)), Vector3(0.0, 1.0, 1.5))
	inter.face_carrier(carrier)
	var prop_front: Vector3 = (-inter.global_transform.basis.z).normalized()
	assert_almost_eq(prop_front.y, 0.0, 0.0001,
		"the presented pose stays upright — only the reversed ready-to-throw pose follows the look up and down")


# The mesh-front correction has to survive the pitch, on the axis a GUN actually uses. Every gun view_model here
# points its barrel down mesh +X (its Muzzle marker sits at +X), which is why WeaponData.thrown_face_rotation_degrees
# defaults to Y=+90 — that is the yaw that swings +X onto the aim's -Z. Pin that the corrected axis, not the raw -Z,
# is what ends up along a PITCHED look.
func test_throwable_reversed_carry_pose_aims_the_corrected_gun_axis() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	inter.face_carrier_while_held = true
	inter.face_carrier_reversed = true
	inter.face_carrier_rotation_degrees = Vector3(0.0, 90.0, 0.0)  # the gun convention: barrel is local +X
	add_child_autofree(inter)
	inter.global_transform = Transform3D(Basis.IDENTITY, Vector3.ZERO)
	var carrier := Transform3D(Basis.from_euler(Vector3(deg_to_rad(25.0), deg_to_rad(70.0), 0.0)), Vector3(0.0, 1.0, 1.5))
	inter.face_carrier(carrier)
	var barrel: Vector3 = inter.global_transform.basis.x.normalized()
	var carrier_front: Vector3 = (-carrier.basis.z).normalized()
	assert_almost_eq(barrel.dot(carrier_front), 1.0, 0.0001,
		"with the +90 gun correction the drop's local +X (the barrel) must lie along the look, pitch included")


# Straight up is inside the normal look range (the pitch clamp is 89 degrees, and wall-climbing opens it to 150 —
# past vertical). Vector3.UP as the look_at hint is degenerate there: the engine errors and the prop flips. The
# reversed pose borrows the CARRIER's up axis, which is perpendicular to its forward by construction, so this must
# come out finite and still aimed. GUT 9.6 fails a test on an engine error, so a regression here shows up as a
# failure either way.
func test_throwable_reversed_carry_pose_survives_looking_straight_up() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	inter.face_carrier_while_held = true
	inter.face_carrier_reversed = true
	add_child_autofree(inter)
	inter.global_transform = Transform3D(Basis.IDENTITY, Vector3.ZERO)
	var carrier := Transform3D(Basis.from_euler(Vector3(deg_to_rad(90.0), 0.0, 0.0)), Vector3(0.0, 1.0, 0.0))
	inter.face_carrier(carrier)
	var prop_front: Vector3 = (-inter.global_transform.basis.z).normalized()
	assert_almost_eq(prop_front.y, 1.0, 0.001,
		"looking straight up must point the held weapon straight up, not error out or flip it")


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


func test_throwable_breathe_defaults_off_and_an_untuned_opt_in_still_breathes_subtly() -> void:
	var inter = load("res://scripts/components/Throwable.gd").new()
	assert_false(inter.breathes(),
		"An unconfigured Throwable should stay visually static by default.")
	var mi := MeshInstance3D.new()
	inter.add_child(mi)
	inter.mesh_instance = mi
	inter.hp = 1
	inter.breathe = true  # opted in, breathe_amount / breathe_rate left at 0 = inherit the defaults
	inter._cache_breathe_base_scale()
	var peak := 0.0
	for i in 200:  # 10 s of 0.05 s ticks: several whole breaths at any sane default rate
		inter._animate_breathing(0.05)
		peak = maxf(peak, absf(mi.scale.x - 1.0))
	assert_gt(peak, 0.0,
		"a prop opted into breathing with no tuning must still visibly pulse: 0 on the knobs means inherit the default, not off")
	assert_lt(peak, 0.1,
		"the untuned default must read as a subtle breath, not the prop swelling by 10% or more")
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


# ---------------------------------------------------------------------------
# Gib-confetti trick-shot (_is_confetti_kill). IN the tree: its last gate is _is_airborne's world raycast, and _ready
# stamps the spawn time the freshness gate measures. Each gib is frozen (no gravity drift) far above anything a test
# builds, so it reads as mid-air. Every test starts from a gib that DOES qualify and flips exactly one condition, so a
# refusal can never pass just because the whole predicate went dead.
# ---------------------------------------------------------------------------

const CONFETTI_Y := 5000.0


func _fresh_midair_gib(x: float) -> Throwable:
	var gib := Throwable.new()
	gib.freeze = true
	add_child_autofree(gib)
	gib.global_position = Vector3(x, CONFETTI_Y, 0.0)
	var d := ThrowableData.new()
	d.is_gib = true
	gib.data = d
	return gib


func _player_shooter() -> Node:
	var shooter: Node = autofree(Node.new())
	shooter.add_to_group(Groups.PLAYER)  # off-tree: is_in_group answers, and no global group scan can see it
	return shooter


func test_throwable_fresh_midair_gib_shot_by_the_player_confettis_until_it_is_picked_up() -> void:
	var gib := _fresh_midair_gib(0.0)
	var shooter := _player_shooter()
	assert_true(gib._is_confetti_kill(shooter),
		"a gib fresh off a kill, shot mid-air by the player, must be a confetti trick-shot")
	gib.on_picked_up(null)
	assert_false(gib._is_confetti_kill(shooter),
		"once the player has picked the gib up it is disqualified: tossing a gib and shooting it must not farm confetti")


func test_interactable_is_confetti_kill_false_when_data_null() -> void:
	var gib := _fresh_midair_gib(10.0)
	var shooter := _player_shooter()
	assert_true(gib._is_confetti_kill(shooter), "guard: this mid-air gib qualifies while it carries gib data")
	gib.data = null
	assert_false(gib._is_confetti_kill(shooter),
		"a prop with no ThrowableData is not a gib and must never confetti")


func test_interactable_is_confetti_kill_false_for_non_gib_data() -> void:
	var gib := _fresh_midair_gib(20.0)
	var shooter := _player_shooter()
	assert_true(gib._is_confetti_kill(shooter), "guard: this mid-air gib qualifies while its data is a gib")
	gib.data = ThrowableData.new()  # a plain crate: is_gib left at its default
	assert_false(gib._is_confetti_kill(shooter),
		"crates and barrels never burst into confetti, only gore gibs")


func test_interactable_is_confetti_kill_false_for_stale_gib() -> void:
	var gib := _fresh_midair_gib(30.0)
	var shooter := _player_shooter()
	assert_true(gib._is_confetti_kill(shooter), "guard: the gib qualifies the moment it bursts out")
	gib._spawn_msec = Time.get_ticks_msec() - gib.confetti_fresh_window_ms - 1000
	assert_false(gib._is_confetti_kill(shooter),
		"a gib older than confetti_fresh_window_ms has been lying around, not flying off a fresh kill, so it must not confetti")


func test_throwable_confetti_needs_the_player_to_have_fired_the_shot() -> void:
	var gib := _fresh_midair_gib(40.0)
	assert_true(gib._is_confetti_kill(_player_shooter()), "guard: the player's shot qualifies")
	var npc_shooter: Node = autofree(Node.new())
	assert_false(gib._is_confetti_kill(npc_shooter),
		"an NPC's round hitting the same mid-air gib must not pay out the player's trick-shot")
	assert_false(gib._is_confetti_kill(null),
		"nor may a hit with no attacker at all")


# ---------------------------------------------------------------------------
# AGILITY-scaled durations (attack.gd effective_attack_speed / _windup / _reload_time).
# Built the same way as the melee-stamina pair above: a bare Attack (never add_child'd) with a real Player as
# the wielder, whose Character.stats_or_default() lazily builds a baseline sheet we then write.
# ---------------------------------------------------------------------------

## A bare Attack wired to a fresh Player whose sheet carries `agi`. Caller frees both via _free_pair.
func _wielder_attack(agi: int, weapon: WeaponData) -> Array:
	var a = load(ATTACK_PATH).new()
	var p = load("res://scripts/player/player.gd").new()
	p.stats = CharacterStats.new()
	p.stats.agility = agi
	a.character = p
	a.current_weapon = weapon
	return [a, p]

func _free_pair(pair: Array) -> void:
	pair[0].free()
	pair[1].free()

## A melee weapon authored well clear of the min_melee_attack_speed floor, so a test can read the raw curve
## without the floor quietly rewriting it (the _priced_gun idiom above, for the melee clock).
func _slow_melee(cadence: float = 1.0, windup: float = 0.2) -> WeaponData:
	var w := WeaponData.new()
	w.is_melee = true
	w.attack_speed = cadence
	w.attack_windup = windup
	w.reload_time = 0.0
	return w


func test_attack_baseline_agility_leaves_every_authored_duration_untouched() -> void:
	# THE load-bearing contract. A baseline sheet must reproduce the .tres numbers EXACTLY — if this drifts, every
	# weapon in the game was silently re-tuned by a stat nobody spent a point on.
	var melee := _slow_melee(1.0, 0.2)
	var gun := _priced_gun()
	gun.reload_time = 2.0
	var pair := _wielder_attack(0, melee)
	var a = pair[0]
	assert_almost_eq(a.effective_attack_speed(), 1.0, 0.0001,
		"agility 0 swings at exactly the authored attack_speed")
	assert_almost_eq(a.effective_attack_windup(), 0.2, 0.0001,
		"agility 0 winds up for exactly the authored attack_windup")
	a.current_weapon = gun
	assert_almost_eq(a.effective_reload_time(), 2.0, 0.0001,
		"agility 0 reloads in exactly the authored reload_time")
	_free_pair(pair)
	melee = null
	gun = null


func test_attack_agility_shortens_a_melee_swing_and_lengthens_a_clumsy_one() -> void:
	var melee := _slow_melee(1.0, 0.2)
	var quick := _wielder_attack(4, melee)
	assert_almost_eq(quick[0].effective_attack_speed(), 0.8, 0.0001,
		"agility 4 -> a 1.0s swing cycles in 0.8s (5% per point, matching CharacterStats.melee_time_mult)")
	_free_pair(quick)
	var clumsy := _wielder_attack(-3, melee)
	assert_almost_eq(clumsy[0].effective_attack_speed(), 1.15, 0.0001,
		"a NEGATIVE agility drags the swing out past the authored cadence — worse forever, no upper clamp")
	_free_pair(clumsy)
	melee = null


func test_attack_agility_scales_the_windup_by_the_same_factor_as_the_cadence() -> void:
	# ⭐ The wind-up sits INSIDE the cadence (attack.gd starts the cooldown, then awaits the wind-up before the hit
	# lands). Scaling only the cadence would leave the wind-up an unscaled constant that eats a quick build's whole
	# shortened window — and past the floor it would shrink to nothing while the cadence held, so the swing's SHAPE
	# would change rather than its speed. One shared post-floor scale is what pins the ratio.
	var melee := _slow_melee(1.0, 0.2)
	for agi in [0, 4, 10, 13, 20, -3]:
		var pair := _wielder_attack(agi, melee)
		var a = pair[0]
		var cadence: float = a.effective_attack_speed()
		var windup: float = a.effective_attack_windup()
		assert_almost_eq(windup / cadence, 0.2, 0.0001,
			"the authored wind-up:cadence ratio (0.2) must hold at agility %d — at every value, floored or not" % agi)
		_free_pair(pair)
	melee = null


func test_attack_agility_leaves_a_gun_cadence_alone() -> void:
	# Agility buys HANDS, not the gun's mechanism. A mechanical rate of fire is not athleticism, and
	# _shot_stamina_cost derives its clamp FROM attack_speed — scaling it here would move the shot price too.
	var gun := _priced_gun(1.0, 0.44)
	gun.attack_windup = 0.11
	var pair := _wielder_attack(10, gun)
	assert_almost_eq(pair[0].effective_attack_speed(), 0.44, 0.0001,
		"agility 10 does NOT speed up a gun's cyclic rate — that is gunplay's domain, and the shot price is derived from it")
	assert_almost_eq(pair[0].effective_attack_windup(), 0.11, 0.0001,
		"nor a gun's click-to-hit wind-up (the shotgun really does author 0.11s of it)")
	_free_pair(pair)
	gun = null


func test_attack_agility_shortens_every_reload_melee_or_not() -> void:
	# The reload half is NOT restricted to melee: a reload is hands, not the gun's mechanism, and it is what makes
	# agility worth points to a shooter.
	var gun := _priced_gun()
	gun.reload_time = 2.0
	var pair := _wielder_attack(4, gun)
	assert_almost_eq(pair[0].effective_reload_time(), 1.6, 0.0001,
		"agility 4 -> a 2.0s reload finishes in 1.6s, on a RANGED weapon")
	_free_pair(pair)
	gun = null


func test_attack_floors_hold_the_scaled_durations_off_zero() -> void:
	# CharacterStats.melee_time_mult / reload_time_mult reach EXACTLY 0 at agility 20 and the level-up station has
	# no cap, so without these floors a specialist build assigns 0 to a Timer's wait_time — an engine error, and a
	# fire cooldown that never elapses.
	var wg: WeaponGeneralSettings = GameSettings.weapon_general
	var melee := _slow_melee(1.0, 0.2)
	var gun := _priced_gun()
	gun.reload_time = 2.0
	var pair := _wielder_attack(20, melee)
	var a = pair[0]
	assert_almost_eq(a.effective_attack_speed(), wg.min_melee_attack_speed, 0.0001,
		"agility 20 drives the multiplier to 0, so the cadence lands exactly on min_melee_attack_speed instead of 0")
	assert_gt(a.effective_attack_speed(), 0.0,
		"and is strictly positive — a Timer.wait_time of 0 is an engine error")
	a.current_weapon = gun
	assert_almost_eq(a.effective_reload_time(), wg.min_reload_time, 0.0001,
		"the reload lands on min_reload_time for the same reason")
	assert_gt(a.effective_reload_time(), 0.0, "and is strictly positive")
	_free_pair(pair)
	melee = null
	gun = null


func test_attack_floor_never_lengthens_an_authored_duration() -> void:
	# ⭐ THE NEUTRALITY TRAP. The floors bound how far AGILITY may compress a clock; they are NOT a statement that
	# every weapon takes at least that long. Applied unconditionally, a melee weapon authored FASTER than the floor
	# would swing SLOWER than its .tres says for a baseline character — and the shipped fists (reload_time 0.0)
	# would gain a quarter-second reload nobody authored. _duration_floor is what stops both.
	var wg: WeaponGeneralSettings = GameSettings.weapon_general
	var fast := _slow_melee(wg.min_melee_attack_speed * 0.5, 0.02)
	var pair := _wielder_attack(0, fast)
	var a = pair[0]
	assert_almost_eq(a.effective_attack_speed(), fast.attack_speed, 0.0001,
		"a melee weapon authored under the floor keeps its authored cadence at baseline — the floor must never SLOW anything")
	assert_almost_eq(a.effective_reload_time(), 0.0, 0.0001,
		"and a 0.0 authored reload_time (both shipped melee weapons) stays 0.0 rather than becoming min_reload_time")
	_free_pair(pair)
	# It is already at/under the physical minimum, so agility buys it nothing further either.
	var quick := _wielder_attack(10, fast)
	assert_almost_eq(quick[0].effective_attack_speed(), fast.attack_speed, 0.0001,
		"agility cannot compress a weapon already authored below the floor — it is at the physical minimum already")
	_free_pair(quick)
	fast = null


func test_attack_live_agility_buff_reaches_the_real_swing_and_reload() -> void:
	# A carried +agility trinket / a stim must move the SWING, not just the number the Stats screen prints —
	# that is the whole reason Attack._agility_bonus folds Character.status_stat_modifier in at this seam.
	var melee := _slow_melee(1.0, 0.2)
	var pair := _wielder_attack(0, melee)
	var a = pair[0]
	var p = pair[1]
	var eff := StatusEffect.new()
	eff.duration = 999.0
	eff.stat_modifiers = {"agility": 4}
	var mgr := StatusEffectManager.new()
	p.add_child(mgr)
	mgr.apply_effect(eff)
	assert_almost_eq(p.status_stat_modifier(&"agility"), 4.0, 0.0001,
		"the buff is live on the wielder (guard: if this fails the assertion below proves nothing)")
	assert_almost_eq(a.effective_attack_speed(), 0.8, 0.0001,
		"a live +4 agility buff on a BASELINE sheet swings exactly as fast as an authored agility 4")
	assert_almost_eq(a.effective_attack_windup(), 0.16, 0.0001,
		"and shortens the wind-up with it, keeping the ratio")
	_free_pair(pair)
	melee = null
	eff = null


func test_attack_effective_durations_are_safe_with_no_wielder_and_no_weapon() -> void:
	# The off-tree case the whole suite depends on: a bare Attack has a null `character` AND may have no weapon.
	# Neither may crash, and a wielder-less Attack must report the AUTHORED numbers (an AI body with no sheet).
	var a = load(ATTACK_PATH).new()
	assert_almost_eq(a.effective_attack_speed(), 0.0, 0.0001,
		"no weapon -> 0.0 rather than a null deref")
	assert_almost_eq(a.effective_reload_time(), 0.0, 0.0001, "same for the reload clock")
	assert_almost_eq(a.effective_attack_windup(), 0.0, 0.0001, "same for the wind-up")
	var melee := _slow_melee(1.0, 0.2)
	a.current_weapon = melee
	assert_almost_eq(a.effective_attack_speed(), 1.0, 0.0001,
		"a wielder-less Attack takes the authored cadence untouched")
	assert_almost_eq(a.effective_attack_windup(), 0.2, 0.0001, "and the authored wind-up")
	a.free()
	melee = null


func test_attack_reload_view_scale_tracks_the_reload_it_scaled() -> void:
	# ⭐ The view model's reload DIP and RAISE ride this factor, and the raise window is what is_raised() reports
	# and GunPose mirrors into `gun_raised` — which BLOCKS FIRING. So a fixed 0.5 s raise would be a flat tail on
	# every reload that agility could never shorten: the player-felt reload would be effective + 0.5 s, turning a
	# promised 4x into 2x. That is an interior plateau arriving by the back door, and the NO SOFT CAP contract
	# forbids it. This pins the factor against the seconds the reload Timer is ACTUALLY waiting, read off a real reload
	# started through _on_reload_reload, so the view gesture and the clock cannot drift apart.
	var gun := _priced_gun()
	gun.reload_time = 2.0
	for agi in [0, 4, 10, 20]:
		var pair := _wielder_attack(agi, gun)
		var a = pair[0]
		_give_timers(a)
		_give_empty_clip(a, gun)
		a._on_reload_reload()
		assert_false(a.reload.is_stopped(), "guard: the reload must actually have started at agility %d" % agi)
		var timer_seconds: float = a.reload.wait_time
		assert_almost_eq(a.reload_view_scale() * gun.reload_time, timer_seconds, 0.0001,
			"at agility %d the view model's reload gesture must be scaled by exactly the ratio the reload Timer is waiting" % agi)
		_free_pair(pair)
	gun = null


func test_attack_reload_view_scale_is_one_at_baseline_and_for_a_reloadless_weapon() -> void:
	var gun := _priced_gun()
	gun.reload_time = 2.0
	var pair := _wielder_attack(0, gun)
	assert_almost_eq(pair[0].reload_view_scale(), 1.0, 0.0001,
		"a baseline wielder leaves the view-model reload gesture at its authored EffectsSettings length")
	_free_pair(pair)
	# A weapon that authors no reload has no gesture to compress — and 0.0/0.0 must not reach the caller.
	var melee := _slow_melee(1.0, 0.2)
	var quick := _wielder_attack(20, melee)
	assert_almost_eq(quick[0].reload_view_scale(), 1.0, 0.0001,
		"a 0.0-reload weapon (both shipped melee weapons) reports 1.0 rather than dividing by zero")
	_free_pair(quick)
	var bare = load(ATTACK_PATH).new()
	assert_almost_eq(bare.reload_view_scale(), 1.0, 0.0001, "and so does an Attack with no weapon at all")
	bare.free()
	gun = null
	melee = null


func test_felt_reload_stays_linear_in_agility_once_the_view_scale_is_applied() -> void:
	# The whole point of the coupling, stated as the property that matters: the time from pressing reload to
	# being able to fire again must shrink in PROPORTION to the stat, not asymptote onto a fixed animation tail.
	var raise_time: float = GameSettings.effects.gun_raise_time
	var gun := _priced_gun()
	gun.reload_time = 2.0
	var baseline := _wielder_attack(0, gun)
	var felt_base: float = baseline[0].effective_reload_time() + raise_time * baseline[0].reload_view_scale()
	_free_pair(baseline)
	var quick := _wielder_attack(10, gun)  # multiplier 0.5
	var felt_quick: float = quick[0].effective_reload_time() + raise_time * quick[0].reload_view_scale()
	_free_pair(quick)
	assert_almost_eq(felt_quick, felt_base * 0.5, 0.0001,
		"agility 10 halves the FELT reload (timer + the firing-blocked raise), not just the Timer half — an unscaled raise would leave it at %.3f instead of %.3f" % [gun.reload_time * 0.5 + raise_time, felt_base * 0.5])
	gun = null
