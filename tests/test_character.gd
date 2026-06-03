extends GutTest

## Focused GUT suite for the @abstract Character base (scripts/player/character.gd).
##
## COVERS (each assert message states the invariant it guards):
##   - killed_by_only_crits(): fresh=false; latches true through an all-crit kill,
##     false after any non-crit hit, and the false-latch is one-way (crit-then-body).
##   - take_damage() HP arithmetic on the NON-LETHAL path (hp -= amount, no clamp) and
##     its damaged(current_hp, max_hp) signal.
##   - heal() partial restore and clamp-at-max_hp.
##   - hp == max_hp after _ready(); the _dead latch makes take_damage a no-op.
##   - Exported defaults: max_hp (10.0), head_local_y (0.4), explosion_velocity (ZERO).
##   - is_headshot() head-zone threshold; is_off_guard() base false.
##   - Weapon-host aim contract (get_aim_origin/direction/basis) at an identity transform.
##   - get_hit_flash() base null; the base no-op hooks exist (indicate_damage_from,
##     on_dealt_hit, on_weapon_fired, on_weapon_launched).
##
## DELIBERATELY SKIPPED (would crash / mutate the world in a unit run, see character.gd):
##   - The LETHAL take_damage branch (hp<=0) -> gore()+die(): spawns physics gibs/decals
##     into get_tree().root, raycasts the world, reads GameSettings, queue_free()s. Every
##     take_damage test below keeps max_hp huge / damage tiny so hp never reaches 0.
##   - gore()/spawn_gibs()/spawn_blood_decal()/spawn_dust()/flash_red() real tween/
##     _setup_overlay_chain with a real mesh/apply_velocity/apply_blast/gravity/
##     _physics_process/_push_interactables/_apply_fall_damage/_notify_nearby_players_of_death:
##     all need a live physics frame, autoloads, particles, or a real ShaderMaterial.
##     (has_method on spawn_dust / _notify_nearby_players_of_death is already in test_smoke.)
##
## Character is @abstract, so it cannot be instantiated directly. A fresh inner concrete
## stub (_Stub, distinct from test_smoke's _ConcreteCharacter to avoid a merge clash) is
## used. _ready() only assigns hp=max_hp and calls _setup_overlay_chain(), which
## early-returns on a mesh-less stub, so add_child_autofree(_Stub) is side-effect-safe;
## exported defaults are read via load(path).new() WITHOUT add_child (so _ready never runs).

const CHARACTER_PATH := "res://scripts/player/character.gd"

## Concrete stand-in for the @abstract Character base. Named _Stub (not _ConcreteCharacter)
## so this file can coexist with test_smoke.gd's stub if the suites are ever merged.
class _Stub extends Character:
	pass


# --- Exported defaults (pure: load().new() WITHOUT add_child, so _ready never runs) ---

func test_max_hp_default_is_ten() -> void:
	# Mirrors test_smoke's blast_damp_divisor load+new pattern. No add_child => _ready
	# (which would assign hp) never runs, so we read the raw exported default.
	var c = load(CHARACTER_PATH).new()
	assert_eq(c.max_hp, 10.0,
		"Character.max_hp must default to 10.0 — the shared baseline health pool that subclasses tune")
	c.free()


func test_head_local_y_default() -> void:
	var c = load(CHARACTER_PATH).new()
	assert_eq(c.head_local_y, 0.4,
		"head_local_y must default to 0.4 so the head zone sits at the top cap of the 2m capsule attackers aim for")
	c.free()


func test_explosion_velocity_defaults_to_zero() -> void:
	var c = load(CHARACTER_PATH).new()
	assert_eq(c.explosion_velocity, Vector3.ZERO,
		"explosion_velocity must start at ZERO so a freshly spawned actor carries no residual blast impulse")
	c.free()


# --- Base no-op / null hooks (pure: has_method / return value, no add_child needed) ---

func test_indicate_damage_from_is_base_noop() -> void:
	# The directional-damage-indicator hook must EXIST as a safe no-op so Character
	# callers work on enemies that don't override it. Calling it must not crash.
	var c = load(CHARACTER_PATH).new()
	assert_true(c.has_method("indicate_damage_from"),
		"Character must expose indicate_damage_from() as a no-op hook so callers work on non-overriding enemies")
	c.indicate_damage_from(Vector3.ZERO)
	c.free()


func test_on_dealt_hit_is_base_noop() -> void:
	var c = load(CHARACTER_PATH).new()
	assert_true(c.has_method("on_dealt_hit"),
		"Character must expose on_dealt_hit() so any wielder can be told it landed a hit without a Player-specific override")
	c.free()


func test_weapon_fire_and_launch_hooks_exist() -> void:
	var c = load(CHARACTER_PATH).new()
	assert_true(c.has_method("on_weapon_fired"),
		"Character must expose on_weapon_fired() — a hosted Weapon calls it every shot, so an Enemy wielder needs no override")
	assert_true(c.has_method("on_weapon_launched"),
		"Character must expose on_weapon_launched() — the launch/dash feedback hook a hosted Weapon calls, as a base no-op")
	c.free()


func test_get_hit_flash_base_returns_null() -> void:
	var c = load(CHARACTER_PATH).new()
	assert_null(c.get_hit_flash(),
		"get_hit_flash() base must return null so a Weapon skips the camera-space hit-flash for enemies (only the player has one)")
	c.free()


func test_is_off_guard_base_returns_false() -> void:
	var c = load(CHARACTER_PATH).new()
	assert_false(c.is_off_guard(),
		"is_off_guard() base must be false — the player is never an ambush target; only enemies override it for the sneak-attack bonus")
	c.free()


# --- _ready initialization (add_child so _ready runs; safe on a mesh-less stub) ---

func test_hp_equals_max_hp_after_ready() -> void:
	# add_child triggers _ready(), which sets hp = max_hp and calls _setup_overlay_chain()
	# (a no-op here: the stub has no `mesh`, so it early-returns before touching materials).
	var c := _Stub.new()
	add_child_autofree(c)
	assert_eq(c.hp, c.max_hp,
		"_ready() must initialize hp to max_hp so a freshly spawned actor starts at full health")


# --- killed_by_only_crits() state machine (large max_hp keeps every hit non-lethal) ---

func test_killed_by_only_crits_fresh_is_false() -> void:
	# No hits yet => _took_any_hit is false. The all-crit applause reward must NOT fire
	# on an actor that never took damage.
	var c := _Stub.new()
	add_child_autofree(c)
	assert_false(c.killed_by_only_crits(),
		"A fresh actor that took no damage must NOT qualify for the all-crit reward (_took_any_hit is still false)")


func test_killed_by_only_crits_true_after_crit_hit() -> void:
	# Raise max_hp BEFORE add_child so _ready sets hp=1000; a 1.0 crit leaves hp at 999>0,
	# so no die()/gore() branch runs.
	var c := _Stub.new()
	c.max_hp = 1000.0
	add_child_autofree(c)
	c.take_damage(1.0, true)
	assert_true(c.killed_by_only_crits(),
		"After only a crit hit, killed_by_only_crits() must be true — an all-headshot kill earns the applause reward")


func test_killed_by_only_crits_false_after_noncrit_hit() -> void:
	var c := _Stub.new()
	c.max_hp = 1000.0
	add_child_autofree(c)
	c.take_damage(1.0, false)
	assert_false(c.killed_by_only_crits(),
		"Any non-crit (body/fall/explosion) damage must disqualify the all-crit reward by latching _all_crits=false")


func test_killed_by_only_crits_noncrit_latches_after_crit() -> void:
	# Crit first, then a single body shot: the false-latch must be one-way.
	var c := _Stub.new()
	c.max_hp = 1000.0
	add_child_autofree(c)
	c.take_damage(1.0, true)
	c.take_damage(1.0, false)
	assert_false(c.killed_by_only_crits(),
		"A single mixed-in body shot must permanently disqualify the kill even after a prior crit (_all_crits=false is one-way)")


# --- take_damage HP arithmetic + damaged signal (non-lethal path only) ---

func test_take_damage_subtracts_amount_nonlethal() -> void:
	var c := _Stub.new()
	c.max_hp = 1000.0
	add_child_autofree(c)
	c.take_damage(7.0, false)
	assert_eq(c.hp, 993.0,
		"take_damage must subtract exactly the amount from hp (1000 - 7) before the death check, with no clamping on the non-lethal path")


func test_take_damage_emits_damaged_signal() -> void:
	# watch_signals / assert_signal_emitted are confirmed in test_smoke's test_inventory_* tests.
	var c := _Stub.new()
	c.max_hp = 1000.0
	add_child_autofree(c)
	watch_signals(c)
	c.take_damage(1.0, false)
	assert_signal_emitted(c, "damaged",
		"take_damage must emit damaged(current_hp, max_hp) on every hit so the health UI can update")


func test_dead_latch_makes_take_damage_a_noop() -> void:
	# The multi-hit guard (lines 116-117): once _dead, take_damage early-returns so a
	# shotgun's pellets in one frame can't re-run gore/die. We assert the guard's no-op;
	# this NEVER triggers the real death path.
	var c := _Stub.new()
	add_child_autofree(c)
	c._dead = true
	var hp_before: float = c.hp
	c.take_damage(5.0, false)
	assert_eq(c.hp, hp_before,
		"While _dead, take_damage must early-return and leave hp untouched so multi-hit-in-one-frame can't re-run death bookkeeping")


# --- heal() (add_child so hp is initialized; only side effect is a damaged.emit) ---

func test_heal_clamps_at_max_hp() -> void:
	# After _ready, hp == max_hp (10). Healing past the cap must not overheal.
	var c := _Stub.new()
	add_child_autofree(c)
	c.heal(5.0)
	assert_eq(c.hp, 10.0,
		"heal() must use min(hp + amount, max_hp) so overheal can never exceed the cap")


func test_heal_restores_partial_hp() -> void:
	var c := _Stub.new()
	c.max_hp = 1000.0
	add_child_autofree(c)
	c.take_damage(10.0, false)
	c.heal(4.0)
	assert_eq(c.hp, 994.0,
		"heal() below the cap must add exactly the amount back (1000 - 10 + 4), the inverse of take_damage")


# --- is_headshot() head-zone threshold (to_local at an identity transform is pure math) ---

func test_is_headshot_above_threshold() -> void:
	# Stub stays at the default transform (origin, identity basis), so to_local is identity:
	# the world y maps straight to local y, compared against head_local_y (0.4).
	var c := _Stub.new()
	add_child_autofree(c)
	assert_true(c.is_headshot(Vector3(0.0, 0.5, 0.0)),
		"A hit at local y 0.5 (>= head_local_y 0.4) must count as a headshot for the damage multiplier")


func test_is_headshot_below_threshold() -> void:
	var c := _Stub.new()
	add_child_autofree(c)
	assert_false(c.is_headshot(Vector3(0.0, 0.3, 0.0)),
		"A hit at local y 0.3 (< head_local_y 0.4) must NOT count as a headshot — it's below the head zone")


# --- Weapon-host aim contract (identity transform => deterministic) ---

func test_get_aim_direction_is_forward() -> void:
	# At an identity basis, -global_basis.z is straight forward (0,0,-1). This lets the
	# same Weapon fire correctly without a camera.
	var c := _Stub.new()
	add_child_autofree(c)
	assert_eq(c.get_aim_direction(), Vector3(0.0, 0.0, -1.0),
		"get_aim_direction() must fire straight forward (-global_basis.z) from the body so a camera-less wielder still aims")


func test_get_aim_basis_is_identity_at_identity_transform() -> void:
	var c := _Stub.new()
	add_child_autofree(c)
	assert_eq(c.get_aim_basis(), Basis.IDENTITY,
		"get_aim_basis() must return this body's transform basis (identity here) — the basis projectile spread rotates around")


func test_get_aim_origin_is_global_position() -> void:
	var c := _Stub.new()
	add_child_autofree(c)
	assert_eq(c.get_aim_origin(), Vector3.ZERO,
		"get_aim_origin() must return the body's global_position (origin here) — where hitscan/projectiles originate")