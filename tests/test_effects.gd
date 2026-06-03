extends GutTest

## GUT tests for the "Effects + decals" subsystem (res://scripts/effects/*.gd,
## res://scenes/effects/*.gd, res://scenes/decals/*.gd).
##
## SCOPE — this file ONLY asserts side-effect-free contracts:
##   • exported / const defaults read off BARE instances, and
##   • has_method() presence of the signal handlers / public API, plus
##   • the three genuinely pure paths (GunMesh.is_raised, BloodDropEmitter.start,
##     and the two decal _on_time_til_fadeout_timeout bool flips).
##
## Every effect node here grabs @onready/@export children, plays audio, spawns
## physics bodies, runs create_timer/create_tween, or reads get_tree()/get_viewport()/
## get_world_3d() inside _ready or _process. So these nodes are instantiated with
## `load(path).new()` WITHOUT add_child — _init runs (none define one), _ready does NOT,
## and reading scalar exports / consts off the bare object is safe. They are .free()'d
## (not add_child_autofree) because they never enter the tree.
##
## DELIBERATELY SKIPPED (covered elsewhere or unsafe to unit-test):
##   • Explosion._ready light/mesh/collider sizing, ScreenShakeArea falloff, MuzzleWhiz,
##     BloodSplatter surface, GunMesh shadow, and the GameSettings.effects/audio tuning
##     constants — all already covered by test_smoke.gd via the real scenes.
##   • Runtime behaviour of _do_muzzle_flash / _on_attack_flash_muzzle / explosion.gd
##     spawn handlers / blood_drop impact+raycast / *_process — they spawn nodes, play
##     audio, or dereference null @onready/@export children on a bare instance, so only
##     their has_method presence + scalar defaults are asserted, never CALLED.
##   • particle_time_bind.gd — no consts and no public API worth a brittle private-default
##     assertion; its only behaviour couples to Engine.time_scale. Skipped entirely.


# --- explosion_area.gd (class Explosion) -----------------------------------------

func test_explosion_area_exported_defaults() -> void:
	# Bare instance: Explosion._ready dereferences mesh_instance.mesh (null on a bare
	# node) and would crash, so NEVER add_child — read the scalar exports off the object.
	var n = load("res://scripts/effects/explosion_area.gd").new()
	assert_eq(n.tint_color, Color(0, 0, 0, 0),
		"tint_color must default to alpha-0 so tinting is OFF unless a caller (the paint splat) opts in; _ready only recolours when tint_color.a > 0")
	assert_eq(n.explosion_radius, 4.0,
		"explosion_radius default 4.0 sizes the blast mesh/light/collider and the push falloff distance")
	assert_eq(n.max_explosion_force, 20.0,
		"max_explosion_force default 20.0 is the peak radial impulse applied at the blast centre")
	assert_true(n.deals_damage,
		"deals_damage must default true so a plain Explosion damages bodies it overlaps (light-only sparks opt out)")
	assert_false(n.allowed_shake_screen,
		"allowed_shake_screen must default false; screen shake is opt-in per explosion")
	assert_eq(n.upward_bias, 0.0,
		"upward_bias default 0.0 = pure radial push (no vertical 'juggle') unless a caller raises it")
	assert_eq(n.speed_to_scale, 0.0,
		"speed_to_scale default 0.0 makes the flash mesh start at full size (instant), matching ExplosionMesh's 0 => Vector3.ONE")
	n.free()


func test_explosion_area_has_safe_handlers() -> void:
	# Same bare instance: only assert the handlers EXIST. Do NOT call them — they touch
	# get_tree()/physics (body push, self-free, monitoring-window await).
	var n = load("res://scripts/effects/explosion_area.gd").new()
	assert_true(n.has_method("_on_body_entered"),
		"Explosion must expose _on_body_entered — the body-push / damage handler wired to area_entered in the scene")
	assert_true(n.has_method("_on_timer_timeout"),
		"Explosion must expose _on_timer_timeout — the Timer self-free handler that ends the one-shot blast")
	assert_true(n.has_method("_limit_monitoring_window"),
		"Explosion must expose _limit_monitoring_window — it stops monitoring after a couple frames to avoid Jolt event churn on kills")
	n.free()


# --- explosion_mesh.gd (class ExplosionMesh) -------------------------------------

func test_explosion_mesh_constants_and_defaults() -> void:
	# Bare instance: ExplosionMesh._process reads GameSettings.effects.explosion_flash_speed
	# every frame, so stay out of the tree — read consts + scalar exports off the object.
	var n = load("res://scripts/effects/explosion_mesh.gd").new()
	assert_eq(n.EMISSION_ENERGY_MULTIPLIER, 3.0,
		"EMISSION_ENERGY_MULTIPLIER 3.0 is the base emissive brightness the flash pulses around")
	assert_eq(n.OUTLINE_COLOR, Color.BLACK,
		"OUTLINE_COLOR must be black so the optional cartoon outline reads as a dark rim")
	assert_eq(n.OUTLINE_WIDTH, 1.0,
		"OUTLINE_WIDTH 1.0 is the outline shader parameter set when has_outline is on")
	assert_eq(n.speed_to_scale, 0.0,
		"speed_to_scale default 0.0 => the mesh starts at full scale (instant flash); >0 grows from zero (explosion bloom)")
	assert_false(n.has_outline,
		"has_outline must default false so the flash mesh has no outline pass unless explicitly enabled")
	n.free()


func test_explosion_mesh_has_tint() -> void:
	# tint() is the recolour entry point the paint splat / Explosion.tint_color path calls.
	# Conservatively assert presence only (do NOT depend on calling it on a bare node).
	var n = load("res://scripts/effects/explosion_mesh.gd").new()
	assert_true(n.has_method("tint"),
		"ExplosionMesh must expose tint(c) so Explosion can recolour the flash + light to match a paint splat")
	n.free()


# --- gun_mesh.gd (class GunMesh) -------------------------------------------------

func test_gun_mesh_raise_constant() -> void:
	# Bare instance: GunMesh._ready walks Sketchfab_Scene children + builds a rim-light
	# material (missing on a bare node), so NEVER add_child — read the const off the object.
	var n = load("res://scripts/effects/gun_mesh.gd").new()
	assert_eq(n.GUN_RAISE_MS, 500,
		"GUN_RAISE_MS 500 is the post-swap/reload raise window the laser sight gates on (no laser while the gun tweens in)")
	n.free()


func test_gun_mesh_safe_surface() -> void:
	var n = load("res://scripts/effects/gun_mesh.gd").new()
	assert_true(n.has_method("is_raised"),
		"GunMesh must expose is_raised() so the laser sight only draws once the gun is fully out")
	assert_true(n.has_method("setup"),
		"GunMesh must expose setup() — the host injects player/inventory/attack and wires the muzzle FX through it")
	assert_true(n.has_method("equipped_marker"),
		"GunMesh must expose equipped_marker(name) so the laser sight can read per-weapon anchor markers")
	assert_true(n.has_method("fire"),
		"GunMesh must expose fire() — the recoil-kick animation driven by Attack.play_animation")
	assert_true(n.has_method("reload"),
		"GunMesh must expose reload() — the reload/swap dip animation")
	assert_true(n.has_method("land"),
		"GunMesh must expose land(intensity) so the gun dips with the camera on landing")
	# is_raised() is pure-safe to CALL on a bare instance: _raise_until_msec defaults to 0,
	# so it returns Time.get_ticks_msec() >= 0 == true with no side effects.
	assert_true(n.is_raised(),
		"With _raise_until_msec at its default 0, is_raised() must be true (gun considered settled, laser allowed) before any reload starts a raise window")
	n.free()


# --- muzzle_flash.gd (class MuzzleFlash) -----------------------------------------

func test_muzzle_flash_type_and_handler() -> void:
	# No _ready defined, but _do_muzzle_flash dereferences a null mesh_instance_3d, so
	# never CALL it — kept bare for symmetry and to assert type + handler presence only.
	var n = load("res://scripts/effects/muzzle_flash.gd").new()
	assert_true(n is Node3D,
		"MuzzleFlash must extend Node3D so it positions its flash mesh + light in 3D at the muzzle")
	assert_true(n.has_method("_do_muzzle_flash"),
		"MuzzleFlash must expose _do_muzzle_flash — the handler wired to Attack.flash_muzzle that blinks the flash on each shot")
	n.free()


# --- ambient_dust.gd (class AmbientDust) -----------------------------------------

func test_ambient_dust_exported_defaults() -> void:
	# Bare instance: AmbientDust._ready builds particle/process materials and _process reads
	# get_viewport().get_camera_3d(), so NEVER add_child — read the scalar exports off it.
	var n = load("res://scripts/effects/ambient_dust.gd").new()
	assert_eq(n.motes, 350,
		"motes default 350 sets how many dust specks live in the haze volume at once (cost/density tradeoff)")
	assert_eq(n.mote_lifetime, 14.0,
		"mote_lifetime default 14.0s is both a mote's life and the preprocess time used to pre-fill the field at level start")
	assert_eq(n.volume_extents, Vector3(20.0, 10.0, 20.0),
		"volume_extents default (20,10,20) is the half-size of the emission box that re-centres on the camera each frame")
	assert_eq(n.mote_size, 0.02,
		"mote_size default 0.02m keeps each mote a tiny speck rather than a visible quad")
	assert_eq(n.drift, 0.04,
		"drift default 0.04 m/s is the gentle downward settle applied via gravity + initial velocity")
	assert_eq(n.turbulence, 0.15,
		"turbulence default 0.15 is the wandering-motion strength so motes never sit perfectly still")
	assert_eq(n.mote_color, Color(0.86, 0.82, 0.74, 0.13),
		"mote_color default is a warm low-alpha tint so the dust reads as subtle haze, not fog")
	n.free()


# --- blood_drop_emitter.gd (class BloodDropEmitter) ------------------------------

func test_blood_drop_emitter_constants() -> void:
	# Bare instance: _physics_process spawns drops once in the tree (there is no _ready),
	# so NEVER add_child — read the consts off the object.
	var n = load("res://scripts/effects/blood_drop_emitter.gd").new()
	assert_eq(n.SCATTER, 1.8,
		"SCATTER 1.8 is the spawn-position spread (metres) around the death origin for each blood drop")
	assert_eq(n.VEL_MIN, 3.0,
		"VEL_MIN 3.0 is the slowest initial launch speed for a blood drop")
	assert_eq(n.VEL_MAX, 9.0,
		"VEL_MAX 9.0 is the fastest initial launch speed; VEL_MIN..VEL_MAX is the randf_range the rain uses")
	n.free()


func test_blood_drop_emitter_start_clamps() -> void:
	# start() ONLY assigns/clamps the scalar fields (no node spawning), so it is
	# side-effect-free on a bare instance.
	var n = load("res://scripts/effects/blood_drop_emitter.gd").new()
	n.start(Vector3.ZERO, 100, 5)
	assert_eq(n._remaining, 100,
		"start() must store the requested drop count so _physics_process knows how many remain to spawn")
	assert_eq(n._per_frame, 5,
		"start() must store per_frame so the rain batches that many drops per physics frame (amortizing the physics-server cost)")
	n.start(Vector3.ZERO, -10, 0)
	assert_eq(n._remaining, 0,
		"start() must clamp a negative count to 0 via maxi(0, count) so the emitter immediately self-frees instead of looping")
	assert_eq(n._per_frame, 1,
		"start() must clamp per_frame to at least 1 via maxi(1, per_frame) so the batch loop always makes progress")
	n.free()


# --- blood_drop.gd (no class_name; extends RigidBody3D) --------------------------

func test_blood_drop_constants_and_default() -> void:
	# Bare instance: _ready arms a 6s create_timer, so NEVER add_child — read consts off it.
	var n = load("res://scripts/effects/blood_drop.gd").new()
	assert_eq(n.MAX_LIFETIME, 6.0,
		"MAX_LIFETIME 6.0s is the safety despawn so a drop that tunnels geometry (never firing body_entered) can't leak forever")
	assert_eq(n.PITCH_MIN, 0.7,
		"PITCH_MIN 0.7 is the lowest randomised impact-SFX pitch")
	assert_eq(n.PITCH_MAX, 1.4,
		"PITCH_MAX 1.4 is the highest randomised impact-SFX pitch; PITCH_MIN..PITCH_MAX varies each splat")
	assert_eq(n.DECAL_SIZE_MIN, 0.4,
		"DECAL_SIZE_MIN 0.4 is the smallest randomised blood-splat decal size")
	assert_eq(n.DECAL_SIZE_MAX, 1.2,
		"DECAL_SIZE_MAX 1.2 is the largest randomised blood-splat decal size")
	assert_eq(n.DECAL_CULL_MASK, 2,
		"DECAL_CULL_MASK 2 puts the blood decal on a render layer that excludes the gun mesh so blood never projects onto the weapon")
	assert_false(n.silent,
		"silent must default false (a lone drop plays its impact SFX); mass spawners flip it true so a 100-drop burst doesn't roar")
	n.free()


# --- bullet_hole_decal.gd (no class_name; extends Decal) -------------------------

func test_bullet_hole_decal_fade_flip() -> void:
	# No _ready defined; _on_time_til_fadeout_timeout only sets a bool (no tree/tween/free),
	# so it is safe to CALL on a bare instance.
	var n = load("res://scripts/effects/bullet_hole_decal.gd").new()
	assert_false(n.begin_fade_out,
		"begin_fade_out must start false so a fresh bullet hole holds full alpha until its fadeout Timer fires")
	n._on_time_til_fadeout_timeout()
	assert_true(n.begin_fade_out,
		"_on_time_til_fadeout_timeout() must flip begin_fade_out true so _process starts lerping the decal's alpha to zero")
	n.free()


# --- explosion.gd (no class_name; extends Node3D — projectile->Explosion bridge) -

func test_explosion_bridge_defaults_and_handlers() -> void:
	# No _ready defined; reading exports + has_method is safe. Do NOT call the handlers —
	# they instantiate + add_child an Explosion to the root and play SFX.
	var n = load("res://scripts/effects/explosion.gd").new()
	assert_eq(n.max_explosion_force, 20.0,
		"explosion.gd max_explosion_force default 20.0 is the force handed to the Explosion it spawns on a rock-projectile impact")
	assert_eq(n.explosion_radius, 4.0,
		"explosion.gd explosion_radius default 4.0 is the blast radius handed to the spawned Explosion")
	assert_eq(n.upward_bias, 0.0,
		"explosion.gd upward_bias default 0.0 forwards no vertical bias to the spawned Explosion unless tuned")
	assert_true(n.has_method("_on_rock_projectile_queued_for_deletion"),
		"explosion.gd must expose _on_rock_projectile_queued_for_deletion — the rock-impact handler that spawns a damaging blast + SFX")
	assert_true(n.has_method("_on_projectile_queued_for_deletion"),
		"explosion.gd must expose _on_projectile_queued_for_deletion — the generic-impact handler that spawns a force-less spark")
	n.free()


# --- ps1_applier.gd (no class_name; extends Node) --------------------------------

func test_ps1_applier_exported_defaults() -> void:
	# Bare instance: _ready defers _apply which rewrites every scene material, so NEVER
	# add_child — read the scalar exports off the object.
	var n = load("res://scripts/effects/ps1_applier.gd").new()
	assert_true(n.enabled,
		"enabled must default true so dropping the PS1 applier into a level applies the warp on play with no extra wiring")
	assert_eq(n.vertex_snap, 80.0,
		"vertex_snap default 80.0 is the moderate PS1 wobble (lower = chunkier) passed to the warp shader")
	assert_eq(n.affine_amount, 1.0,
		"affine_amount default 1.0 = full PS1 affine (perspective-incorrect) texture warp")
	assert_true(n.cast_shadows,
		"cast_shadows must default true so warped geometry keeps casting shadows unless the user turns it off to avoid jitter acne")
	n.free()


# --- spark_attack.gd (no class_name; extends GPUParticles3D) ---------------------

func test_spark_attack_handler() -> void:
	# No _ready defined; assert handler presence only. Do NOT call it — it fires restart()
	# which emits the one-shot particle burst.
	var n = load("res://scenes/effects/spark_attack.gd").new()
	assert_true(n.has_method("_on_attack_flash_muzzle"),
		"spark_attack.gd must expose _on_attack_flash_muzzle — the handler wired to Attack.flash_muzzle that re-fires the muzzle sparks")
	n.free()


# --- blood_splat_decal.gd (no class_name; extends Decal) -------------------------

func test_blood_splat_decal_defaults_and_fade_flip() -> void:
	# Bare instance: _ready starts a grow tween via create_tween, so NEVER add_child —
	# read the scalar exports off the object. The fade flip is a pure bool set, safe to call.
	var n = load("res://scenes/decals/blood_splat_decal.gd").new()
	assert_eq(n.target_size, Vector3(4.0, 0.15, 4.0),
		"target_size default (4,0.15,4) is the splat size the decal grows to (spawners override per-drop)")
	assert_eq(n.grow_time, 1.25,
		"grow_time default 1.25s is how long the quint-ease 'splat' grow animation takes")
	assert_false(n.begin_fade_out,
		"begin_fade_out must start false so the splat holds while it grows, until its fadeout Timer fires")
	n._on_time_til_fadeout_timeout()
	assert_true(n.begin_fade_out,
		"_on_time_til_fadeout_timeout() must flip begin_fade_out true so _process fades the splat's alpha out and frees it")
	n.free()


# --- blood_light.gd (no class_name; extends OmniLight3D) -------------------------

func test_blood_light_default() -> void:
	# Bare instance: _ready awaits a create_timer then queue_free, so NEVER add_child —
	# just verify the export exists as a float at its default.
	var n = load("res://scenes/decals/blood_light.gd").new()
	assert_eq(n.time_to_destroy, 0.0,
		"time_to_destroy default 0.0 (the scene assigns the real wet-highlight lifetime); this just verifies the export exists as a float")
	n.free()