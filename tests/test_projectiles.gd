extends GutTest

## GUT suite for the Projectiles subsystem (scripts/projectiles/*.gd + the
## ProjectileSpawner that feeds it). Every test guards a const/default/class-shape
## invariant and its message states WHY that invariant matters, so this file doubles
## as executable documentation of the projectile contract.
##
## WHAT IT COVERS (all SAFE — no physics, no scene, no autoload side effects):
##   - Projectile (@abstract base): const contract (DECAL_CULL_MASK, DECAL_SIZE,
##     PARTICLE_BACKOFF/IMPACT_BACKOFF, NORMAL_PARALLEL_THRESHOLD) read via the global
##     type, instance-var flight/multiplier defaults read off a CONCRETE inner stub
##     created WITHOUT add_child, and the queued_for_deletion signal + shared-method shape.
##     (These flight/multiplier fields are plain `var`s with literal defaults, assigned at
##     construction — NOT @export — so `.new()` without add_child reads them directly.)
##   - Bullet / RockProjectile: concrete-variant identity (is Projectile / RigidBody3D),
##     their own decal consts, and that they inherit the base flight defaults unshadowed.
##   - PaintProjectile: full const contract, cross-subsystem cull-mask invariant
##     (== Projectile.DECAL_CULL_MASK), Node3D identity, and default white/full-life state.
##   - ProjectileSpawner: PITCH_AXIS_MIN_LENGTH_SQ const, class shape + method presence,
##     and the no-weapon spawn_projectile() guard (must be a no-op, never a crash).
##   - BulletCasing: bare RigidBody3D class shape (compiles, keeps its base type).
##
## WHAT IT DELIBERATELY SKIPS (and why):
##   - Projectile._ready(): awaits a real life-timer, writes linear_velocity, look_at(),
##     and resolves @onready $CollisionShape3D — would error / start a 10s timer on a
##     bare tree. So Projectile/Bullet/RockProjectile are NEVER add_child'd here; consts
##     come from the global type and defaults from `.new()` (no add_child) then `.free()`.
##   - _on_body_entered / particles / _spawn_decal / PaintProjectile._physics_process &
##     _splash / ProjectileSpawner real-weapon spawn path: full impact pipeline — spawn
##     scenes, raycast the physics world, reparent+play AudioStreamPlayer3Ds, read
##     GameSettings/AudioManager autoloads, apply impulses. Pure side effects + physics;
##     unit-testing them would crash the runner or play audio. Only guarded no-op /
##     pure-data paths are asserted.
##   - _orient_decal_to_normal: needs a real Decal node (test_smoke.gd covers the basis
##     math via its own local helper instead).
##
## All asserts use only helpers confirmed in test_smoke.gd
## (assert_eq/true/false/gt/lt/not_null) plus plain Object API (has_method/has_signal).


## Concrete stand-in for the @abstract Projectile base. Projectile declares TWO @abstract
## funcs (particles, _spawn_decal), so — unlike Character — a bare `extends Projectile`
## stub stays abstract and .new() would fail; both must be overridden here.
class _StubProjectile extends Projectile:
	func particles(_body, _last_velocity) -> void: pass
	func _spawn_decal(_last_velocity: Vector3) -> void: pass


const ROCK_PROJECTILE_SCRIPT := "res://scripts/projectiles/rock_projectile.gd"
const PAINT_PROJECTILE_SCRIPT := "res://scripts/projectiles/paint_projectile.gd"
const BULLET_CASING_SCRIPT := "res://scripts/projectiles/bullet_casing.gd"


# ---------------------------------------------------------------------------
# Projectile (@abstract base) — pure const contract, read via the global type.
# ---------------------------------------------------------------------------

func test_projectile_decal_cull_mask() -> void:
	assert_eq(Projectile.DECAL_CULL_MASK, 1048571,
		"DECAL_CULL_MASK must be 1048571 — all render layers EXCEPT the gun's (layer 3) — so a missed-wall bullet-hole decal isn't culled along with the first-person gun mesh")


func test_projectile_decal_size() -> void:
	assert_eq(Projectile.DECAL_SIZE, Vector3(0.3, 0.1, 0.3),
		"DECAL_SIZE must be a flat (low-Y) 0.3x0.1x0.3 footprint so a bullet hole projects as a thin disc on the surface, not a fat cube")


func test_projectile_backoff_consts() -> void:
	assert_eq(Projectile.PARTICLE_BACKOFF, 0.1,
		"PARTICLE_BACKOFF must be 0.1 — how far generic impact particles are pulled back off the surface")
	assert_eq(Projectile.IMPACT_BACKOFF, 0.4,
		"IMPACT_BACKOFF must be 0.4 — how far a character-hit's particles/decal anchor is pulled back (also the queued_for_deletion last-pos offset)")
	assert_gt(Projectile.IMPACT_BACKOFF, Projectile.PARTICLE_BACKOFF,
		"Character hits must pull effects FURTHER off the surface than generic hits, so blood/sparks read clearly in front of the body")


func test_projectile_normal_parallel_threshold() -> void:
	assert_eq(Projectile.NORMAL_PARALLEL_THRESHOLD, 0.99,
		"NORMAL_PARALLEL_THRESHOLD must be 0.99 — the |dot| cutoff for treating the surface normal as parallel to UP when picking a fallback reference axis for the decal basis")
	assert_lt(Projectile.NORMAL_PARALLEL_THRESHOLD, 1.0,
		"Threshold must be strictly below 1.0 so a near-vertical (floor/ceiling) normal trips the fallback branch before the cross product degenerates")


# ---------------------------------------------------------------------------
# Projectile instance-var defaults — read off the CONCRETE stub WITHOUT add_child
# (so _ready never runs the life-timer or touches $CollisionShape3D). These are plain
# `var`s with literal defaults, assigned at construction, so reading them off `.new()`
# (without ever entering the tree) is correct and side-effect-free.
# ---------------------------------------------------------------------------

func test_projectile_default_flight_vars() -> void:
	var p := _StubProjectile.new()  # no add_child: _ready (life-timer + @onready) must not run
	assert_eq(p.speed, 8.0,
		"Projectile.speed default must be 8.0 — the safety net for any projectile spawned before ProjectileSpawner overwrites it per-weapon")
	assert_eq(p.damage, 2.0,
		"Projectile.damage default must be 2.0 so a weaponless projectile still deals non-zero damage")
	assert_eq(p.life_time, 10.0,
		"Projectile.life_time default must be 10.0s so an unconfigured projectile still self-deletes")
	p.free()


func test_projectile_default_multiplier_and_flag_vars() -> void:
	var p := _StubProjectile.new()  # no add_child
	assert_eq(p.headshot_multiplier, 2.0,
		"headshot_multiplier default must be 2.0 so crit math is sane even before the spawner sets the per-weapon value")
	assert_eq(p.sneak_attack_multiplier, 2.0,
		"sneak_attack_multiplier default must be 2.0 so an off-guard hit still multiplies damage by default")
	assert_false(p.visual_only,
		"visual_only must default to false so a projectile created without the spawner still actually deals damage")
	assert_eq(p.direction, Vector3.FORWARD,
		"direction must default to Vector3.FORWARD so an unconfigured projectile has a valid launch axis (look_at/velocity)")
	p.free()


# ---------------------------------------------------------------------------
# Projectile signal + shared-method shape — on the no-add_child stub.
# ---------------------------------------------------------------------------

func test_projectile_has_queued_for_deletion_signal() -> void:
	var p := _StubProjectile.new()  # no add_child
	assert_true(p.has_signal("queued_for_deletion"),
		"Projectile must expose the queued_for_deletion signal — explosion.gd wires the blast/SFX to this exact name")
	p.free()


func test_projectile_has_shared_methods() -> void:
	var p := _StubProjectile.new()  # no add_child
	assert_true(p.has_method("on_deletion"),
		"Projectile must expose on_deletion() — the overridable deletion hook concrete variants extend")
	assert_true(p.has_method("_on_queued_for_deletion"),
		"Projectile must expose _on_queued_for_deletion() — the queued_for_deletion handler that calls on_deletion()")
	assert_true(p.has_method("_orient_decal_to_normal"),
		"Projectile must expose _orient_decal_to_normal() — the shared decal-orientation helper Bullet/RockProjectile call")
	p.free()


# ---------------------------------------------------------------------------
# Bullet — concrete Projectile variant (global type, NO add_child).
# ---------------------------------------------------------------------------

func test_bullet_is_concrete_projectile_rigidbody() -> void:
	var b := Bullet.new()  # no add_child: _ready is inherited and only runs on add_child
	assert_true(b is Projectile,
		"Bullet must be a Projectile so ProjectileSpawner can set .direction/.damage/etc. through the base API")
	assert_true(b is RigidBody3D,
		"Bullet must be a RigidBody3D so it flies under physics and collides to trigger _on_body_entered")
	b.free()


func test_bullet_decal_fallback_backoff() -> void:
	assert_eq(Bullet.DECAL_FALLBACK_BACKOFF, 0.05,
		"Bullet.DECAL_FALLBACK_BACKOFF must be 0.05 — where the bullet-hole decal is placed when the impact raycast finds no surface")


func test_bullet_inherits_projectile_flight_defaults() -> void:
	var b := Bullet.new()  # no add_child
	assert_eq(b.speed, 8.0,
		"Bullet must inherit Projectile.speed==8.0 unshadowed (the concrete variant must not redefine the base default)")
	assert_eq(b.damage, 2.0,
		"Bullet must inherit Projectile.damage==2.0 unshadowed")
	assert_eq(b.life_time, 10.0,
		"Bullet must inherit Projectile.life_time==10.0 unshadowed")
	b.free()


# ---------------------------------------------------------------------------
# RockProjectile — concrete variant with NO class_name; load the Script.
# ---------------------------------------------------------------------------

func test_rock_projectile_decal_consts() -> void:
	var RP := load(ROCK_PROJECTILE_SCRIPT)  # no class_name — consts read off the loaded Script
	assert_eq(RP.ROCK_DECAL_SCALE, 10.0,
		"ROCK_DECAL_SCALE must be 10.0 so the rocket's scorch mark is 10x a bullet hole (DECAL_SIZE * 10)")
	assert_eq(RP.ROCK_DECAL_PROBE_DISTANCE, 0.8,
		"ROCK_DECAL_PROBE_DISTANCE must be 0.8 — the raycast half-length used to find the surface for the larger scorch decal")
	assert_eq(RP.ROCK_DECAL_NORMAL_OFFSET, 0.05,
		"ROCK_DECAL_NORMAL_OFFSET must be 0.05 — how far the scorch decal is lifted off the surface along its normal to avoid z-fighting")


func test_rock_projectile_is_concrete_projectile() -> void:
	var r = load(ROCK_PROJECTILE_SCRIPT).new()  # no add_child: _ready inherited from Projectile
	assert_true(r is Projectile,
		"RockProjectile must satisfy the Projectile contract — explosion.gd connects to its inherited queued_for_deletion signal")
	r.free()


# ---------------------------------------------------------------------------
# PaintProjectile — code-built blob (global type). Const contract + Node3D shape.
# ---------------------------------------------------------------------------

func test_paint_projectile_consts() -> void:
	assert_eq(PaintProjectile.PAINT_SIZE, 0.5,
		"PAINT_SIZE must be 0.5 — the splat decal width")
	assert_eq(PaintProjectile.PAINT_ALPHA, 1.0,
		"PAINT_ALPHA must be 1.0 — fresh paint is fully opaque so it covers what's underneath, no blending")
	assert_eq(PaintProjectile.MAX_PAINT_DECALS, 8000,
		"MAX_PAINT_DECALS must be 8000 — the global decal cap that prevents unbounded decal growth (oldest culled past this)")
	assert_eq(PaintProjectile.OVERLAP_FACTOR, 0.3,
		"OVERLAP_FACTOR must be 0.3 — a fresh splat replaces any paint within 0.3x its width")
	assert_eq(PaintProjectile.PAINT_CULL_MASK, 1048571,
		"PAINT_CULL_MASK must be 1048571 — all layers except the gun's (layer 3), matching the bullet decal so paint never lands on the first-person gun")
	assert_eq(PaintProjectile.PAINT_EMISSION, 1.0,
		"PAINT_EMISSION must be 1.0 — full-bright so paint never dims in shadow")
	assert_eq(PaintProjectile.PAINT_GRAVITY, 6.0,
		"PAINT_GRAVITY must be 6.0 — the gentle downward arc applied to the blob each frame")
	assert_eq(PaintProjectile.LIFETIME, 4.0,
		"LIFETIME must be 4.0s — the blob frees itself if it never hits anything")
	assert_eq(PaintProjectile.BLOB_RADIUS, 0.06,
		"BLOB_RADIUS must be 0.06 — the in-flight sphere mesh radius")
	assert_eq(PaintProjectile.SPLAT_VOLUME_DB, -4.0,
		"SPLAT_VOLUME_DB must be -4.0 — the splat SFX volume in dB")


func test_paint_projectile_const_invariants() -> void:
	assert_eq(PaintProjectile.PAINT_CULL_MASK, Projectile.DECAL_CULL_MASK,
		"Paint and bullet decals must share the same gun-layer exclusion mask — this is the cross-subsystem cull-mask contract")
	assert_gt(PaintProjectile.MAX_PAINT_DECALS, 0,
		"The global paint-decal cap must be positive or the cull logic would free every decal immediately")
	assert_gt(PaintProjectile.LIFETIME, 0.0,
		"Blob lifetime must be positive so a blob that misses everything still eventually self-frees")
	assert_true(PaintProjectile.OVERLAP_FACTOR > 0.0 and PaintProjectile.OVERLAP_FACTOR < 1.0,
		"OVERLAP_FACTOR must be a sane fraction of decal width (0..1) so the overlap-replace radius is smaller than the splat itself")


func test_paint_projectile_is_node3d_with_defaults() -> void:
	var p = load(PAINT_PROJECTILE_SCRIPT).new()  # no add_child: skip the mesh-building _ready
	assert_true(p is Node3D,
		"PaintProjectile must be a Node3D — it is intentionally NOT a RigidBody3D (a self-contained raycast blob, no physics body)")
	assert_eq(p.paint_color, Color.WHITE,
		"paint_color must default to white — a visible default blob before Attack hands it the wheel-selected colour")
	assert_eq(p._life, PaintProjectile.LIFETIME,
		"_life must initialize to LIFETIME so a fresh blob gets its full flight time before self-deleting")
	p.free()


# ---------------------------------------------------------------------------
# ProjectileSpawner — const, class shape, method presence, no-weapon guard.
# NEVER add_child: _ready() dereferences the null `inventory` @export and crashes.
# ---------------------------------------------------------------------------

func test_projectile_spawner_pitch_axis_min_length_sq() -> void:
	assert_eq(ProjectileSpawner.PITCH_AXIS_MIN_LENGTH_SQ, 0.0001,
		"PITCH_AXIS_MIN_LENGTH_SQ must be 0.0001 — the min squared length of the pitch axis before launch_angle rotation is applied, so firing straight up never normalizes a zero vector")


func test_projectile_spawner_class_shape() -> void:
	var s := ProjectileSpawner.new()  # no add_child: _ready dereferences null `inventory`
	assert_true(s is Node3D,
		"ProjectileSpawner must be a Node3D so it sits in the player rig and reads the muzzle Marker3D")
	assert_true(s.has_method("spawn_projectile"),
		"ProjectileSpawner must expose spawn_projectile() — the single entry point Attack calls to fire any projectile weapon")
	assert_true(s.has_method("_on_weapon_changed"),
		"ProjectileSpawner must expose _on_weapon_changed() — the Inventory.weapon_changed handler that updates current_weapon")
	s.free()


func test_projectile_spawner_spawn_with_no_weapon_is_noop() -> void:
	var s := ProjectileSpawner.new()  # no add_child: current_weapon stays null (_ready never ran)
	assert_eq(s.current_weapon, null,
		"A bare spawner must have a null current_weapon before any weapon is equipped")
	# The `if not current_weapon` guard returns before any get_tree()/instantiate(),
	# so this reaches only the safe early-return branch — never the real spawn path.
	s.spawn_projectile(Vector3.ZERO, Vector3.FORWARD, false)
	assert_eq(s.current_weapon, null,
		"Firing with no equipped weapon must be a no-op (early return), never a crash or a spawn")
	s.free()


# ---------------------------------------------------------------------------
# BulletCasing — bare `extends RigidBody3D`, NO class_name; load the Script.
# ---------------------------------------------------------------------------

func test_bullet_casing_is_rigidbody() -> void:
	var c = load(BULLET_CASING_SCRIPT).new()  # no class_name; no _ready/@onready, safe to .new()
	assert_true(c is RigidBody3D,
		"BulletCasing must be a RigidBody3D so spent shells bounce/roll under physics; this also verifies the script compiles and keeps its base type")
	c.free()