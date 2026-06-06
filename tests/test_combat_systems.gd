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


# ---------------------------------------------------------------------------
# SwapWeapons (swap_weapons.gd) — the only combat script safe to add_child:
# no _ready, no @onready. add_child_autofree lets watch_signals/assert_signal_*
# observe equip_this; _try_equip is called directly (not via input).
# ---------------------------------------------------------------------------

func test_swap_weapons_has_seven_default_slots() -> void:
	# @export weapon_slots = [7 preloads] (swap_weapons.gd:18-26): pistol, rock, shotgun, smg,
	# melee, spray_paint, sniper — bound to weapon-slot inputs 1..7. The .tres are the same
	# files preloaded by test_smoke.gd, so they resolve.
	var sw := SwapWeapons.new()
	assert_eq(sw.weapon_slots.size(), 7,
		"The out-of-box slot mapping (slots 1..7) must be fully populated so weapon switching works without any inspector wiring.")
	assert_true(sw.weapon_slots[0] is WeaponData,
		"Slot 0's default must be a real WeaponData (the pistol preload) — _try_equip casts via `as WeaponData`, so a non-WeaponData entry would silently fail to equip.")
	sw.free()


func test_swap_weapons_try_equip_valid_index_emits() -> void:
	# _try_equip(0): slot 0 casts to WeaponData, so equip_this must fire.
	var sw := SwapWeapons.new()
	add_child_autofree(sw)
	watch_signals(sw)
	sw._try_equip(0)
	assert_signal_emitted(sw, "equip_this",
		"Selecting a populated slot must broadcast equip_this so Attack/Inventory swap to that weapon.")


func test_swap_weapons_try_equip_out_of_range_does_not_emit() -> void:
	# Bounds guard: `if index < 0 or index >= weapon_slots.size(): return`
	# (swap_weapons.gd:42-43). Neither -1 nor 999 may emit.
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
	sw.request_equip(sw.weapon_slots[0] as WeaponData)
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
# its default 0 (so every gib reads as "stale" — far past CONFETTI_FRESH_WINDOW_MS)
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

func test_interactable_confetti_eligible_true_on_fresh_instance() -> void:
	# `var _confetti_eligible: bool = true` (Throwable.gd:38) — a fresh gib is
	# eligible for the confetti trick-shot until something picks it up.
	var inter = load("res://scripts/combat/Throwable.gd").new()
	assert_true(inter._confetti_eligible,
		"A freshly-spawned Throwable must start confetti-eligible — a gib straight off a kill is the only thing that can earn the trick-shot confetti.")
	inter.free()


func test_interactable_on_picked_up_clears_confetti_eligible() -> void:
	# on_picked_up() body: `_confetti_eligible = false` (Throwable.gd:435-436).
	# Picking a gib up disqualifies it from the confetti trick-shot (anti-cheese).
	var inter = load("res://scripts/combat/Throwable.gd").new()
	inter.on_picked_up(null)
	assert_false(inter._confetti_eligible,
		"on_picked_up() must clear _confetti_eligible so a picked-up/thrown gib can't be shot for cheesed confetti.")
	inter.free()


func test_interactable_is_confetti_kill_false_when_data_null() -> void:
	# First guard: `if data == null or not data.is_gib: return false`
	# (Throwable.gd:290-291). With no data resource at all it must bail out
	# immediately — before any eligibility/freshness/world access.
	var inter = load("res://scripts/combat/Throwable.gd").new()
	assert_false(inter._is_confetti_kill(null),
		"_is_confetti_kill() must return false when data is null — a prop with no ThrowableData is never a gib and can't confetti.")
	inter.free()


func test_interactable_is_confetti_kill_false_for_non_gib_data() -> void:
	# Same first guard via the `not data.is_gib` arm: a crate-style ThrowableData
	# (is_gib defaults to false) must never confetti.
	var inter = load("res://scripts/combat/Throwable.gd").new()
	var d := ThrowableData.new()
	# is_gib defaults to false (throwable_data.gd:26) — a plain crate.
	inter.data = d
	assert_false(inter._is_confetti_kill(null),
		"_is_confetti_kill() must return false for a non-gib ThrowableData — crates and barrels never burst into confetti, only gore gibs.")
	inter.free()


func test_interactable_is_confetti_kill_false_after_pickup() -> void:
	# Eligibility guard: `if not _confetti_eligible: return false`
	# (Throwable.gd:292-293). With a GIB data resource the first guard passes,
	# but on_picked_up() has cleared eligibility — and that gate short-circuits
	# BEFORE any world/raycast access, so this is safe with no tree.
	var inter = load("res://scripts/combat/Throwable.gd").new()
	var d := ThrowableData.new()
	d.is_gib = true
	inter.data = d
	inter.on_picked_up(null)
	assert_false(inter._is_confetti_kill(null),
		"_is_confetti_kill() must return false once a gib has been picked up — the eligibility gate disqualifies a thrown gib before any world access.")
	inter.free()


func test_interactable_is_confetti_kill_false_for_stale_gib() -> void:
	# Freshness guard: `if Time.get_ticks_msec() - _spawn_msec >= CONFETTI_FRESH_WINDOW_MS: return false`.
	# Stamp _spawn_msec deterministically into the PAST (older than the window) so staleness never depends
	# on how long the engine has been up. The freshness gate (3rd check) trips BEFORE the attacker/world
	# checks, so even a valid Player-group attacker still yields false — proving it's the staleness (not a
	# null attacker) that disqualifies the gib, and confirming no World3D is ever touched on this path.
	var inter = load("res://scripts/combat/Throwable.gd").new()
	var d := ThrowableData.new()
	d.is_gib = true
	inter.data = d
	inter._spawn_msec = Time.get_ticks_msec() - Throwable.CONFETTI_FRESH_WINDOW_MS - 1000
	var attacker := Node.new()
	attacker.add_to_group(&"Player")
	assert_false(inter._is_confetti_kill(attacker),
		"_is_confetti_kill() must return false for a stale gib — only a gib fresh off a kill (within CONFETTI_FRESH_WINDOW_MS) qualifies; the freshness gate trips before the attacker/world checks.")
	attacker.free()
	inter.free()