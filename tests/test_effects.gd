extends GutTest

## GUT tests for the "Effects + decals" subsystem (res://scripts/effects/*.gd, the effect components under
## res://scripts/components/, res://scenes/decals/*.gd) — driven through their real entry points wherever a
## headless run allows, and asserted against what the player sees or hears, not against copied literals.
##
## HOW EACH NODE IS BUILT, and why:
##   • OFF-TREE (`load(path).new()`, _ready called by hand or not at all) where the code under test only builds
##     local state: ExplosionMesh, AmbientDust, the PS1 applier, BloodDropEmitter.start, a bare GunMesh (its
##     _ready walks rig children a bare node lacks, so it never runs; the scope-hide test hands it a GunPose child
##     and steps that child's _process by hand) and a bare Player (on_scored_kill only — a Player's
##     _enter_tree/_ready need the full camera rig, so it is NEVER added to the tree).
##   • IN-TREE (add_child_autofree) where the behaviour needs the tree: an Explosion script given the one child
##     its @onready reads ($OmniLight3D) plus an optional ExplosionMesh flash, the real blast scene the projectile
##     bridge spawns, a blood drop's first contact, the decals' grow tween, the blood light's lifetime timer and the
##     blood emitter scenes under slow-mo and a pause.
##
## A SOURCE-TEXT read remains only where no headless test can observe the outcome at all: horizon_sky.gdshader's
## four flash uniforms (headless never compiles a shader).
##
## Tuning knobs are asserted as the relations the design needs (ordered windows, positive, under a ceiling) or as
## the knob visibly honoured when the code runs. A test that retunes a shared GameSettings knob goes through
## _retune(), which after_each unwinds.
##
## Covered elsewhere and deliberately not repeated: the blast light's reach / floor (test_smoke.gd), the flash's
## ink-mask bit and has_outline ring (test_ink_outline.gd), explosion_damage forwarding
## (test_explosion_damage_override.gd), the blast prefab wiring (test_explosion_area_prefab.gd), the PS1 surface
## skip rules (test_ps1_applier.gd) and the blood_drop_* scatter/speed ordering (test_managers_tuning.gd).

const EXPLOSION_MESH_PATH := "res://scripts/components/explosion_mesh.gd"
const EXPLOSION_BRIDGE_PATH := "res://scripts/effects/explosion.gd"
const GUN_MESH_PATH := "res://scripts/effects/gun_mesh.gd"
const AMBIENT_DUST_PATH := "res://scripts/components/ambient_dust.gd"
const BLOOD_DROP_EMITTER_PATH := "res://scripts/effects/blood_drop_emitter.gd"
const BLOOD_DROP_PATH := "res://scripts/effects/blood_drop.gd"
const BLOOD_DROP_SCENE := "res://scenes/effects/blood_drop.tscn"
const BULLET_HOLE_DECAL_PATH := "res://scripts/effects/bullet_hole_decal.gd"
const PS1_APPLIER_PATH := "res://scripts/effects/ps1_applier.gd"
const BLOOD_SPLAT_DECAL_PATH := "res://scenes/decals/blood_splat_decal.gd"
const BLOOD_SPLAT_DECAL_SCENE := "res://scenes/decals/blood_splat_decal.tscn"
const BLOOD_LIGHT_PATH := "res://scenes/decals/blood_light.gd"
const HORIZON_SKY_PATH := "res://resources/shaders/horizon_sky.gdshader"
const PLAYER_PATH := "res://scripts/player/player.gd"

## What the test blasts author on their light and flash, so "left untinted" is distinguishable from "tinted".
const BLAST_AUTHORED_LIGHT := Color(1.0, 0.75, 0.4)
const FLASH_AUTHORED_ALBEDO := Color(1.0, 1.0, 1.0, 0.6)

## [resource, property, previous value] for every shared knob a test retuned — unwound newest-first in after_each.
var _retuned: Array = []
## Engine.time_scale before a test slowed it down (-1 = untouched); after_each puts it back if the test did not.
var _prior_time_scale: float = -1.0


func _retune(res: Resource, prop: StringName, value: Variant) -> void:
	_retuned.append([res, prop, res.get(prop)])
	res.set(prop, value)


func after_each() -> void:
	for i in range(_retuned.size() - 1, -1, -1):
		var entry: Array = _retuned[i]
		(entry[0] as Resource).set(entry[1], entry[2])
	_retuned.clear()
	if _prior_time_scale >= 0.0:
		Engine.time_scale = _prior_time_scale
		_prior_time_scale = -1.0


# --- explosion.gd (projectile-death -> blast bridge) -----------------------------

## Regression guard for every explosion caller: Explosion.instantiate_recovering() — the ONE reimport-recovery source
## (gun_fx spark/burst/flash, paint_projectile pop, explosion.gd bridge) — must always resolve an instantiable blast.
## If the cached load ever bakes empty (editor reimport churn), the fresh-from-disk fallback must still produce a node,
## otherwise a destroyed projectile silently never spawns its blast. Only resolution is under test here, so the node is
## freed without entering the tree (instantiate() does not run _ready); the real scene's in-tree _ready is driven by the
## bridge tests below.
func test_explosion_bridge_scene_is_instantiable() -> void:
	var ex := Explosion.instantiate_recovering()
	assert_not_null(ex,
		"Explosion.instantiate_recovering() must resolve a blast node (the cached scene, or a fresh re-load if it baked empty)")
	if ex != null:
		ex.free()


# --- explosion_area.gd (class Explosion) -----------------------------------------

## A bare Explosion — the SCRIPT, not explosion_area.tscn — carrying the one child its _ready cannot do without
## (the @onready $OmniLight3D) and, when asked, an ExplosionMesh flash wired as mesh_instance. No Timer frees it
## mid-test and no collider catches unrelated bodies, so only the calls a test makes reach it. Returned NOT yet in
## the tree: set exports first (_ready reads them once), then add_child_autofree.
func _new_blast(with_flash: bool = false) -> Explosion:
	var blast := Explosion.new()
	var light := OmniLight3D.new()
	light.name = "OmniLight3D"
	light.light_color = BLAST_AUTHORED_LIGHT
	blast.add_child(light)
	if with_flash:
		var flash = load(EXPLOSION_MESH_PATH).new()
		flash.mesh = SphereMesh.new()
		var authored := StandardMaterial3D.new()
		authored.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		authored.albedo_color = FLASH_AUTHORED_ALBEDO
		flash.set_surface_override_material(0, authored)
		blast.add_child(flash)
		blast.mesh_instance = flash
	return blast


## A loose rigid body the blast can shove. Layer/mask 0 keeps it invisible to every Area3D and body, so only the
## explicit _on_body_entered call reaches it; no gravity and no damping, so its velocity is the push alone.
func _loose_body_at(pos: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.collision_layer = 0
	body.collision_mask = 0
	body.gravity_scale = 0.0
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.linear_damp = 0.0
	body.can_sleep = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.1
	shape.shape = sphere
	body.add_child(shape)
	body.position = pos
	add_child_autofree(body)
	return body


## A body that records every take_damage it receives (a runtime-built script: no file on disk).
func _damage_recorder_at(pos: Vector3) -> Node3D:
	var script := GDScript.new()
	script.source_code = "extends StaticBody3D\nvar hits: Array = []\nfunc take_damage(amount, _headshot = false, _attacker = null) -> void:\n\thits.append(amount)\n"
	script.reload()
	var body := StaticBody3D.new()
	body.collision_layer = 0
	body.set_script(script)
	body.position = pos
	add_child_autofree(body)
	return body


func test_blast_push_falls_off_with_distance_and_stops_at_its_radius() -> void:
	var blast := _new_blast()
	blast.explosion_radius = 4.0
	blast.max_explosion_force = 12.0
	add_child_autofree(blast)
	var near := _loose_body_at(Vector3(1.0, 0.0, 0.0))    # 25% of the radius out
	var edge := _loose_body_at(Vector3(0.0, 0.0, 3.0))    # 75% out
	var beyond := _loose_body_at(Vector3(-5.0, 0.0, 0.0)) # past the radius
	await wait_physics_frames(2)  # the bodies join the physics space before they are shoved
	for body in [near, edge, beyond]:
		blast._on_body_entered(body)
	await wait_physics_frames(1)
	assert_gt(near.linear_velocity.x, 0.0,
		"a blast must push a body AWAY from its centre (the near body sits on +X of the blast)")
	assert_gt(edge.linear_velocity.z, 0.0,
		"...in whatever direction the body lies (the edge body sits on +Z)")
	assert_gt(near.linear_velocity.length(), edge.linear_velocity.length() + 0.01,
		"the push must fall off with distance — a body at 25%% of the radius is thrown harder than one at 75%% (near %.2f vs edge %.2f m/s)" % [near.linear_velocity.length(), edge.linear_velocity.length()])
	assert_gt(edge.linear_velocity.length(), 0.01,
		"a body still inside the radius, near its edge, must still be pushed")
	assert_almost_eq(beyond.linear_velocity.length(), 0.0, 0.0001,
		"a body past explosion_radius must not move at all — neither pushed nor pulled in by a negative falloff")


func test_a_default_blast_damages_what_it_overlaps_and_a_cosmetic_one_does_not() -> void:
	# deals_damage left at its script default, exactly as ExplosiveBarrel's blast leaves it.
	var plain := _new_blast()
	add_child_autofree(plain)
	var victim := _damage_recorder_at(Vector3(1.0, 0.0, 0.0))
	plain._on_body_entered(victim)
	var hits: Array = victim.get(&"hits")
	assert_eq(hits.size(), 1,
		"an Explosion that nobody configured must damage the body it catches — environmental blasts rely on that default")
	if hits.size() == 1:
		assert_gt(float(hits[0]), 0.0, "...and the hit must actually cost HP")
	var cosmetic := _new_blast()
	cosmetic.deals_damage = false
	add_child_autofree(cosmetic)
	var bystander := _damage_recorder_at(Vector3(-1.0, 0.0, 0.0))
	cosmetic._on_body_entered(bystander)
	assert_eq((bystander.get(&"hits") as Array).size(), 0,
		"a cosmetic blast (deals_damage = false: hit sparks, paint pops) must never damage what it overlaps")


func test_blast_tint_stays_off_until_a_caller_opts_in() -> void:
	var plain := _new_blast(true)
	add_child_autofree(plain)
	var plain_light := plain.get_node("OmniLight3D") as OmniLight3D
	var plain_flash := plain.mesh_instance.get_surface_override_material(0) as StandardMaterial3D
	assert_true(plain_light.light_color.is_equal_approx(BLAST_AUTHORED_LIGHT),
		"an untinted blast must keep its authored light colour — tinting is opt-in, so every rocket is not recoloured black")
	assert_true(plain_flash.albedo_color.is_equal_approx(FLASH_AUTHORED_ALBEDO),
		"...and its flash keeps its authored albedo")
	var paint := Color(0.1, 0.8, 0.3, 1.0)
	var splat := _new_blast(true)
	splat.tint_color = paint
	add_child_autofree(splat)
	var splat_light := splat.get_node("OmniLight3D") as OmniLight3D
	var splat_flash := splat.mesh_instance.get_surface_override_material(0) as StandardMaterial3D
	assert_true(splat_light.light_color.is_equal_approx(paint),
		"a paint splat's tint must recolour the blast light to the paint")
	assert_true(Color(splat_flash.albedo_color.r, splat_flash.albedo_color.g, splat_flash.albedo_color.b).is_equal_approx(Color(paint.r, paint.g, paint.b)),
		"...and the flash mesh to the paint, got %s" % str(splat_flash.albedo_color))
	assert_almost_eq(splat_flash.albedo_color.a, FLASH_AUTHORED_ALBEDO.a, 0.0001,
		"the tint recolours the flash but keeps its authored transparency — a tinted flash must not turn opaque")
	assert_true(splat_flash.emission.is_equal_approx(paint),
		"the flash's glow takes the paint colour too, so it does not pulse white inside a green splat")


func test_a_blast_forwards_its_bloom_request_to_the_flash_that_readied_first() -> void:
	var instant := _new_blast(true)
	add_child_autofree(instant)
	assert_eq(instant.mesh_instance.scale, Vector3.ONE,
		"a blast left at its default speed_to_scale pops its flash in at full size (the muzzle / hit flash)")
	var bloom := _new_blast(true)
	bloom.speed_to_scale = 3.0
	add_child_autofree(bloom)
	assert_eq(bloom.mesh_instance.scale, Vector3.ZERO,
		"a spawner's bloom request must restart the flash from nothing — the flash readied BEFORE its parent forwarded the value (children ready first), so without the re-apply the bloom pops in at full size")
	assert_almost_eq(bloom.mesh_instance.speed_to_scale, 3.0, 0.0001,
		"...and the flash grows at the rate the spawner asked for")


func test_explosion_area_has_safe_handlers() -> void:
	# Bare OFF-TREE instance: only assert the scene-wired handler names EXIST (explosion_area.tscn and
	# explosion_area_2.tscn connect body_entered and the Timer's timeout to them BY NAME, so a rename breaks only when the
	# scene loads, never at parse time). Never call them here — off-tree they touch get_tree()/physics; _on_body_entered is driven in-tree above,
	# and the private _limit_monitoring_window (a direct call from _ready, never wired by name) is driven below.
	var n = load("res://scripts/components/explosion_area.gd").new()
	assert_true(n.has_method("_on_body_entered"),
		"Explosion must expose _on_body_entered — the body-push / damage handler wired to body_entered in the scene")
	assert_true(n.has_method("_on_timer_timeout"),
		"Explosion must expose _on_timer_timeout — the Timer self-free handler that ends the one-shot blast")
	n.free()


## An explosion only needs a physics step or two to catch what it overlaps. If it keeps listening for its whole visual
## lifetime, every gib and gore drop spawning inside it churns enter/exit events and Jolt hitches on each kill. Timing
## is counted in physics_frame emissions, never process frames. The spark queues its switch-off from _ready, and a
## deferred flush always runs before the next physics_frame. The damaging blast has resumed at most ONCE by then (a
## connection made mid-emission does not fire in that emission), so it is still inside its two-step window.
func test_a_blast_stops_listening_for_overlaps_once_its_detection_window_closes() -> void:
	var spark := _new_blast()
	spark.deals_damage = false
	spark.max_explosion_force = 0.0
	add_child_autofree(spark)
	var blast := _new_blast()
	add_child_autofree(blast)
	assert_true(blast.monitoring,
		"a freshly spawned damaging blast must be listening for the bodies it overlaps")
	await get_tree().physics_frame
	assert_false(spark.monitoring,
		"a visual-only spark (no damage, no push) has nothing to detect, so it must stop listening before its first physics step")
	assert_true(blast.monitoring,
		"a damaging blast must still be listening on its first physics step, or it misses the bodies it should hurt and shove")
	await wait_physics_frames(4)
	assert_false(blast.monitoring,
		"once its detection window closes a damaging blast must stop listening — otherwise gibs spawning inside it churn Jolt overlap events and every kill hitches")


## A level unload can pull a blast out of the tree while its detection window is still counting physics steps. The
## window must end quietly. The early blast is removed before its first await resumes. Without the re-check between
## the two awaits, the window then asks a null get_tree() for physics_frame: two engine errors. The late blast is
## removed after that first resume (it connected before this test's await, and a signal calls its connections in the
## order they were made), so the unload also lands on the window's second step. That path only reaches set_deferred
## today, which is safe off-tree, so it guards against a future tree call there rather than against today's re-check.
func test_a_blast_pulled_out_of_the_tree_mid_window_ends_its_window_without_errors() -> void:
	var early := _new_blast()
	add_child_autofree(early)
	var late := _new_blast()
	add_child_autofree(late)
	remove_child(early)
	await get_tree().physics_frame
	remove_child(late)
	await wait_physics_frames(4)
	assert_engine_error_count(0,
		"a blast unloaded mid-window (level unload, quit) must abandon its detection window quietly, on either physics step, instead of asking a null get_tree() for physics_frame")


# --- explosion_mesh.gd (class ExplosionMesh) -------------------------------------

## An off-tree flash with its _ready run by hand (the ink_outline suite's idiom: _ready touches no tree or
## autoload). `speed` < 0 leaves speed_to_scale at its default; `authored` stands in for a scene material.
func _flash_off_tree(speed: float = -1.0, authored: StandardMaterial3D = null) -> MeshInstance3D:
	var flash = load(EXPLOSION_MESH_PATH).new()
	flash.mesh = SphereMesh.new()
	if authored != null:
		flash.set_surface_override_material(0, authored)
	if speed >= 0.0:
		flash.speed_to_scale = speed
	flash._ready()
	return flash


func test_flash_pops_in_by_default_and_a_bloom_grows_up_to_full_size_never_past() -> void:
	var pop := _flash_off_tree()
	assert_eq(pop.scale, Vector3.ONE,
		"a flash left at its default speed_to_scale must pop in at full size — a muzzle flash that swells in reads as lag")
	for i in 30:
		pop._process(1.0 / 60.0)
	assert_eq(pop.scale, Vector3.ONE, "...and must stay at full size while it pulses")
	var bloom := _flash_off_tree(5.0)
	assert_eq(bloom.scale, Vector3.ZERO, "a blooming flash (speed_to_scale > 0) must start from nothing")
	var last := 0.0
	var shrank_or_overshot := false
	for i in 600:
		bloom._process(1.0 / 60.0)
		if bloom.scale.x < last - 0.000001 or bloom.scale.x > 1.000001:
			shrank_or_overshot = true
		last = bloom.scale.x
	assert_false(shrank_or_overshot,
		"a bloom must only ever GROW, and never swell past full size")
	assert_gt(last, 0.95,
		"...and must actually reach full size (got %.3f after 10 s)" % last)
	pop.free()
	bloom.free()


func test_flash_pulses_under_its_own_base_brightness_and_keeps_its_authored_colour() -> void:
	var fallback := _flash_off_tree()
	var authored_mat := StandardMaterial3D.new()
	authored_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	authored_mat.albedo_color = Color(1.0, 0.9, 0.5, 0.6)
	authored_mat.emission = Color(1.0, 0.4, 0.1)
	authored_mat.emission_energy_multiplier = 5.0
	var authored := _flash_off_tree(-1.0, authored_mat)
	var base: float = ExplosionMesh.EMISSION_ENERGY_MULTIPLIER
	# Step so each frame advances the pulse by 0.05 rad whatever explosion_flash_speed is tuned to: >3 full cycles.
	var dt := 0.05 / maxf(GameSettings.effects.explosion_flash_speed, 0.0001)
	var fb_peak := 0.0
	var fb_low := INF
	var au_peak := 0.0
	var au_alpha_peak := 0.0
	var colour_drifted := false
	for i in 400:
		fallback._process(dt)
		authored._process(dt)
		var fm := fallback.get_surface_override_material(0) as StandardMaterial3D
		var am := authored.get_surface_override_material(0) as StandardMaterial3D
		fb_peak = maxf(fb_peak, fm.emission_energy_multiplier)
		fb_low = minf(fb_low, fm.emission_energy_multiplier)
		au_peak = maxf(au_peak, am.emission_energy_multiplier)
		au_alpha_peak = maxf(au_alpha_peak, am.albedo_color.a)
		if not am.emission.is_equal_approx(authored_mat.emission):
			colour_drifted = true
	assert_true(fb_peak <= base + 0.0001,
		"an unauthored flash must never glow past its base brightness EMISSION_ENERGY_MULTIPLIER (peaked at %.3f)" % fb_peak)
	assert_gt(fb_peak, base * 0.9, "...but must reach it — the flash pulses, it is not stuck dim")
	assert_lt(fb_low, base * 0.1, "...and dips toward dark between pulses, which is what makes it flicker")
	assert_true(au_peak <= 5.0 + 0.0001,
		"a flash on an authored material pulses under THAT material's own brightness (peaked at %.3f)" % au_peak)
	assert_gt(au_peak, 4.5,
		"...and reaches it, not the unauthored fallback's dimmer %.1f" % base)
	assert_true(au_alpha_peak <= 0.6 + 0.0001,
		"a transparent flash flickers its alpha UNDER the authored 0.6 — it must never turn more opaque than authored (peaked at %.3f)" % au_alpha_peak)
	assert_false(colour_drifted,
		"the flash must keep glowing in its authored emission colour while it pulses")
	fallback.free()
	authored.free()


# --- gun_mesh.gd (class GunMesh) -------------------------------------------------

## The post-reload raise window is what is_raised() answers and GunPose mirrors into Attack.gun_raised, so it
## BLOCKS FIRING: it must follow the designer knob GameSettings.effects.gun_raise_time, which also times the raise
## tween. Driven on two bare GunMeshes (no attack -> no agility scale; the tween is bound to an off-tree node and
## never steps): one reload lands under a 1.5 s knob, the other under a 0.1 s knob, and both are read 0.4 s later.
## A window that ignores the knob cannot pass: 0 ms fails the immediate check, anything under 0.4 s releases the
## long gun too early, and anything 0.4 s or longer (e.g. the old fixed GUN_RAISE_MS 500) still holds the short one.
func test_gun_stays_lowered_for_the_tuned_raise_time_after_a_reload_lands() -> void:
	var long_gun = load(GUN_MESH_PATH).new()
	var short_gun = load(GUN_MESH_PATH).new()
	_retune(GameSettings.effects, &"gun_raise_time", 1.5)
	long_gun._on_ammo_finished_reloading()
	_retune(GameSettings.effects, &"gun_raise_time", 0.1)
	short_gun._on_ammo_finished_reloading()
	assert_false(long_gun.is_raised(),
		"right after a reload lands the gun is lowered — no round may leave a muzzle still swinging up")
	assert_false(short_gun.is_raised(), "even a short raise starts with the gun lowered")
	await wait_seconds(0.4)
	assert_false(long_gun.is_raised(),
		"0.4 s into a tuned 1.5 s raise the gun must still be lowered — a shorter window that ignores the knob lets a round leave a muzzle still swinging up")
	assert_true(short_gun.is_raised(),
		"once the tuned 0.1 s raise has elapsed the gun is up and may fire — a window that ignores the knob (e.g. a fixed 500 ms) would still hold fire here")
	long_gun.free()
	short_gun.free()


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


## REGRESSION — "reload, then hold M1 and I fire into the ground."
##
## is_raised() is the ONLY thing between a held trigger and the reload dip: GunPose mirrors it into
## Attack.gun_raised every frame and Attack refuses a player shot while that is false. _raise_until_msec cannot
## answer it alone, because it is stamped when the RAISE starts — all through the DIP it still holds the PREVIOUS
## raise's long-past deadline, so this reported "settled" with the gun swung fully down (0.9m below the camera,
## 25 degrees of muzzle droop). Attack's own reload.is_stopped() gate hid that for every frame but the ONE the two
## hand over, and idle order under Player — GunPose (under Head), THEN the Reload Timer (under Weapon), THEN
## MouseInput (last) — makes losing that frame certain rather than unlucky: gun_raised is cached true at the top
## of the frame the reload finishes, and exactly one round leaves the dipped barrel. So: while a reload or swap is
## in flight the gun is DOWN, and this must say so.
##
## Scope note — the two Timers ARE add_child'd (Timer.start() refuses to run outside the tree, and a running timer
## is the whole precondition under test). GunMesh and Attack stay bare, as everywhere else in this file.
func test_gun_mesh_not_raised_while_reload_or_swap_runs() -> void:
	var gun = load("res://scripts/effects/gun_mesh.gd").new()  # bare: _ready walks rig children a bare node lacks
	var atk := Attack.new()                                    # bare: _ready dereferences a null inventory
	var reload_timer := Timer.new()
	var swap_timer := Timer.new()
	add_child_autofree(reload_timer)
	add_child_autofree(swap_timer)
	atk.reload = reload_timer
	atk.swap = swap_timer
	gun.attack = atk
	assert_true(gun.is_raised(),
		"idle — no reload, no swap, no live raise window — the gun is settled and may fire")
	reload_timer.wait_time = 5.0
	reload_timer.start()
	assert_false(gun.is_raised(),
		"a RELOAD in flight means the gun is at the bottom of its dip — is_raised() must not answer 'settled' merely because the last raise window expired long ago (the shot-into-the-floor bug)")
	reload_timer.stop()
	swap_timer.wait_time = 5.0
	swap_timer.start()
	assert_false(gun.is_raised(),
		"a SWAP dips the gun through that same reload() tween, so it is just as DOWN")
	swap_timer.stop()
	assert_true(gun.is_raised(),
		"with neither timer running the expired raise window is all that is left to check — the gun is back up")
	gun.free()
	atk.free()


# --- gun_mesh.gd view-model visibility (scoped-rifle hide) -----------------------
# GunPose writes host.visible EVERY frame from the accessibility toggle, so the scoped-rifle hide had to be
# folded into that one decision (view_model_visible_now) instead of a separate write in _on_aim_changed,
# which GunPose was clobbering — the bug that left the sniper visible while scoped. The truth table is tested via
# the static; the live host.visible write is driven through a stepped GunPose frame in the test after it.

func test_gun_mesh_view_model_visible_truth_table() -> void:
	var scope_weapon := WeaponData.new()
	scope_weapon.disable_dof_while_scoped = true   # the sniper's "crisp scope": hide the model while ADS
	var iron_weapon := WeaponData.new()
	iron_weapon.disable_dof_while_scoped = false    # ordinary iron-sight ADS: keep the model out
	# Accessibility toggle ON (player wants the view model shown):
	assert_true(GunMesh.view_model_visible_now(true, false, scope_weapon),
		"a scope weapon's model shows when NOT aiming — it's only hidden WHILE scoped")
	assert_false(GunMesh.view_model_visible_now(true, true, scope_weapon),
		"aiming a disable_dof_while_scoped weapon (sniper) HIDES the model so you sight through the scope (the reported bug)")
	assert_true(GunMesh.view_model_visible_now(true, true, iron_weapon),
		"aiming an ordinary weapon keeps its model out for iron-sight ADS")
	assert_true(GunMesh.view_model_visible_now(true, true, null),
		"aiming with no equipped weapon never hides — there's nothing to look through")
	# Accessibility toggle OFF (player hid the FP model) wins regardless of scope state:
	assert_false(GunMesh.view_model_visible_now(false, false, iron_weapon),
		"the hide-view-model accessibility toggle hides it even when not aiming")
	assert_false(GunMesh.view_model_visible_now(false, true, scope_weapon),
		"accessibility hide stays hidden while scoped too")
	scope_weapon = null
	iron_weapon = null


## The wielder GunPose reads each pose frame: a bare Character (never added to the tree) carrying the input_dir the
## hip sway samples. Deliberately NOT a Player, so GunPose's sprint / climb reads (which need a Player's built
## components) are skipped by its own `as Player` check.
class _PoseRider extends Character:
	var input_dir := Vector2.ZERO


## The scoped-rifle hide, end to end through the path a scope toggle really takes: ScopeIn.scoped_in lands in
## GunMesh._on_aim_changed, and the NEXT GunPose frame (the per-frame owner of host.visible) decides visibility.
## That split is the fix for the bug where a hide written in _on_aim_changed was overwritten by GunPose's next frame
## and the sniper stayed visible while scoped, so the outcome is asserted after a pose frame, never after the handler
## alone. Off-tree: a bare GunMesh with a hand-built GunPose child whose _process is stepped by hand.
func test_scoping_a_scope_rifle_hides_the_view_model_on_the_next_pose_frame() -> void:
	var prior_view_model_setting: bool = Settings.view_model_visible
	Settings.view_model_visible = true  # the accessibility hide would mask the scope hide; the dev's settings.cfg may set it
	var gun = load(GUN_MESH_PATH).new()
	var rider := _PoseRider.new()
	var inv := Inventory.new()
	var sniper := WeaponData.new()
	sniper.disable_dof_while_scoped = true  # what sniper_wep.tres authors: look THROUGH the scope
	inv.equipped_weapon = sniper
	gun.player = rider
	gun.inventory = inv
	var pose := GunPose.new()
	pose.host = gun
	gun.add_child(pose)  # off-tree, so its _ready never runs; each frame below is stepped by hand
	gun._on_aim_changed(true)
	pose._process(1.0 / 60.0)
	assert_false(gun.visible,
		"scoping in with a crisp-scope rifle must hide the view model on the next pose frame, so you sight through the scope rather than over the gun")
	gun._on_aim_changed(false)
	pose._process(1.0 / 60.0)
	assert_true(gun.visible, "scoping back out must bring the view model back on the next pose frame")
	# CONTROL: a freshly authored gun (no disable_dof_while_scoped) keeps its model up through the same scope toggle.
	var iron := WeaponData.new()
	inv.equipped_weapon = iron
	gun._on_aim_changed(true)
	pose._process(1.0 / 60.0)
	assert_true(gun.visible, "control: aiming an ordinary gun keeps its view model on screen for iron-sight ADS")
	Settings.view_model_visible = prior_view_model_setting
	gun.free()  # frees the GunPose child with it
	rider.free()
	inv.free()
	sniper = null
	iron = null


# --- muzzle_flash.gd (class MuzzleFlash) -----------------------------------------

func test_muzzle_flash_type_and_handler() -> void:
	# Handler-name pin: GunMesh.setup() connects Attack.flash_muzzle to Callable(mf, "_do_muzzle_flash") BY NAME (gun_mesh.gd).
	# Calling it on a bare node observes nothing (its is_instance_valid guard on the unwired mesh/light returns first),
	# so assert type + name only.
	var n = load("res://scripts/components/muzzle_flash.gd").new()
	assert_true(n is Node3D,
		"MuzzleFlash must extend Node3D so it positions its flash mesh + light in 3D at the muzzle")
	assert_true(n.has_method("_do_muzzle_flash"),
		"MuzzleFlash must expose _do_muzzle_flash — the handler wired to Attack.flash_muzzle that blinks the flash on each shot")
	n.free()


# --- ambient_dust.gd (class AmbientDust) -----------------------------------------

func test_ambient_dust_builds_its_emitter_from_its_knobs() -> void:
	# Off-tree with _ready run by hand: it only builds materials and sets emitter fields. _process (the camera
	# follow, which needs a viewport) never runs.
	var dust = load(AMBIENT_DUST_PATH).new()
	var extents := Vector3(6.0, 3.0, 8.0)
	dust.motes = 120
	dust.mote_lifetime = 9.0
	dust.volume_extents = extents
	dust.mote_size = 0.05
	dust.drift = 0.2
	dust._ready()
	assert_eq(dust.amount, 120, "motes must set how many specks are alive at once")
	assert_almost_eq(dust.lifetime, 9.0, 0.0001, "mote_lifetime must set each speck's life")
	assert_almost_eq(dust.preprocess, dust.lifetime, 0.0001,
		"the field must be pre-simulated for a full lifetime, so the air is already dusty the frame a level loads instead of filling in over seconds")
	assert_false(dust.local_coords,
		"motes must live in WORLD space so you walk through them with parallax — local coords glue the haze to the camera")
	assert_true(dust.is_in_group(Groups.AMBIENT_DUST),
		"the dust must join its group, or the scope bridge cannot hide it for a crisp scope picture")
	var pm := dust.process_material as ParticleProcessMaterial
	assert_true(pm != null, "_ready must build a ParticleProcessMaterial")
	if pm != null:
		assert_eq(pm.emission_box_extents, extents, "motes spawn inside the authored volume")
		assert_lt(pm.gravity.y, 0.0, "drift must settle motes DOWNWARD, not float them up")
		assert_almost_eq(pm.gravity.length(), 0.2, 0.0001, "...at the authored drift rate")
	var quad := dust.draw_pass_1 as QuadMesh
	assert_true(quad != null and quad.size == Vector2(0.05, 0.05), "each mote is a quad of the authored mote_size")
	assert_true(dust.visibility_aabb.encloses(AABB(-extents, extents * 2.0)),
		"the culling box must contain the whole emission volume, or motes at its edge pop out of existence as the emitter chases the camera")
	dust.free()
	# GUARD: a designer thinning the dust to 0 must not hand GPUParticles3D an amount below 1 (it rejects it).
	var none = load(AMBIENT_DUST_PATH).new()
	none.motes = 0
	none._ready()
	assert_eq(none.amount, 1, "motes 0 must clamp the emitter to 1 speck instead of an invalid particle amount")
	none.free()


func test_ambient_dust_ships_as_a_faint_haze_of_specks() -> void:
	var dust = load(AMBIENT_DUST_PATH).new()
	assert_gt(dust.mote_lifetime, 0.0, "a mote must live for a positive time (it is also the pre-fill time)")
	assert_between(dust.mote_color.a, 0.001, 0.5,
		"the shipped mote alpha must stay a faint haze — near-opaque motes read as fog or snow, zero alpha is no dust at all")
	var smallest := minf(dust.volume_extents.x, minf(dust.volume_extents.y, dust.volume_extents.z))
	assert_gt(dust.mote_size, 0.0, "a mote needs a visible size")
	assert_lt(dust.mote_size * 100.0, smallest,
		"a mote is a SPECK — orders of magnitude smaller than the volume it floats in")
	assert_gte(dust.drift, 0.0, "the shipped drift settles dust down; a negative drift makes the haze rise")
	dust.free()


# --- blood_drop_emitter.gd (class BloodDropEmitter) ------------------------------

func test_blood_rain_spawns_every_drop_inside_the_tuned_scatter_and_speed_band() -> void:
	# A narrow band on purpose: a spawn that ignored the knobs (a hard-coded spread or speed) lands outside it.
	var fx := GameSettings.effects
	_retune(fx, &"blood_drop_scatter", 0.25)
	_retune(fx, &"blood_drop_vel_min", 2.0)
	_retune(fx, &"blood_drop_vel_max", 2.5)
	var emitter = load(BLOOD_DROP_EMITTER_PATH).new()
	add_child_autofree(emitter)
	var origin := Vector3(10.0, 2.0, -4.0)
	emitter.start(origin, 16, 16)
	var drops: Array[Node] = []
	var watch := func(node: Node) -> void:
		if node is RigidBody3D:
			drops.append(node)
	get_tree().node_added.connect(watch)
	emitter._physics_process(0.0)  # one batch of all 16, synchronously — before any physics step moves a drop
	get_tree().node_added.disconnect(watch)
	assert_eq(drops.size(), 16, "one batch of per_frame 16 must spawn all 16 drops")
	var stray := ""
	for d in drops:
		var off: Vector3 = (d as Node3D).global_position - origin
		var speed: float = (d as RigidBody3D).linear_velocity.length()
		if absf(off.x) > 0.25001 or absf(off.z) > 0.25001 or off.y < -0.00001 or off.y > 0.25001:
			stray = "offset %s from the death origin" % str(off)
		elif speed < 1.99999 or speed > 2.50001:
			stray = "launch speed %.3f" % speed
		elif (d as RigidBody3D).linear_velocity.y <= 0.0:
			stray = "downward launch %s" % str((d as RigidBody3D).linear_velocity)
		if stray != "":
			break
	assert_eq(stray, "",
		"every drop must spawn within blood_drop_scatter of the death origin (never below it) and launch UPWARD at a speed inside blood_drop_vel_min..max — found a drop with %s" % stray)
	for d in drops:
		if is_instance_valid(d):
			d.free()


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

func test_blood_drop_randomisation_bands_are_ordered_and_keep_blood_off_the_gun() -> void:
	var c: Dictionary = (load(BLOOD_DROP_PATH) as GDScript).get_script_constant_map()
	assert_gt(float(c["PITCH_MIN"]), 0.0,
		"the impact SFX pitch band must stay above 0 — a pitch_scale of 0 is invalid on every splat")
	assert_lt(float(c["PITCH_MIN"]), float(c["PITCH_MAX"]),
		"randf_range(PITCH_MIN, PITCH_MAX) needs an ascending band so neighbouring splats sound different")
	assert_gt(float(c["DECAL_SIZE_MIN"]), 0.0, "the smallest stain a drop leaves must still be visible")
	assert_lt(float(c["DECAL_SIZE_MIN"]), float(c["DECAL_SIZE_MAX"]),
		"randf_range(DECAL_SIZE_MIN, DECAL_SIZE_MAX) needs an ascending band so the stains vary")
	var mask := int(c["DECAL_CULL_MASK"])
	assert_ne(mask, 0, "a decal with an empty cull mask projects onto nothing — drops would leave no stain")
	assert_eq(mask & ViewModelCamera.VIEW_MODEL_LAYER, 0,
		"blood decals must never project onto the first-person gun (render layer ViewModelCamera.VIEW_MODEL_LAYER)")
	assert_gt(float(c["MAX_LIFETIME"]), 0.0,
		"MAX_LIFETIME is the despawn backstop for a drop that tunnels geometry; at 0 or below drops die before landing")


func test_a_lone_blood_drop_splats_audibly_once_and_a_silent_one_stays_quiet() -> void:
	var c: Dictionary = (load(BLOOD_DROP_PATH) as GDScript).get_script_constant_map()
	var scene := load(BLOOD_DROP_SCENE) as PackedScene
	var loud = scene.instantiate()
	loud.gravity_scale = 0.0
	loud.position = Vector3(0.0, 20.0, 0.0)
	add_child_autofree(loud)
	var quiet = scene.instantiate()
	quiet.gravity_scale = 0.0
	quiet.position = Vector3(3.0, 20.0, 0.0)
	quiet.silent = true
	add_child_autofree(quiet)
	await wait_physics_frames(1)  # the contact's surface raycast reads direct_space_state from a stepped space
	var loud_sfx: AudioStreamPlayer3D = loud.impact_sfx
	var quiet_sfx: AudioStreamPlayer3D = quiet.impact_sfx
	loud._on_body_entered(null)
	quiet._on_body_entered(null)
	assert_eq(loud_sfx.get_parent(), get_tree().root,
		"a lone drop's splat SFX must detach to the root so the sound outlives the drop it came from")
	assert_between(loud_sfx.pitch_scale, float(c["PITCH_MIN"]), float(c["PITCH_MAX"]),
		"the splat plays at a pitch inside the randomised PITCH_MIN..PITCH_MAX band")
	assert_true(loud.is_queued_for_deletion(), "a drop frees itself on its first contact")
	# ONE-SHOT: a second contact the same frame must be ignored. A replay re-rolls the pitch, so an unchanged pitch
	# is the observable proof (the SFX's parent cannot tell: it is already under the root, and reparenting to the
	# same parent is a no-op).
	var first_pitch := loud_sfx.pitch_scale
	loud._on_body_entered(null)
	assert_eq(loud_sfx.pitch_scale, first_pitch,
		"a second contact on the same drop must not replay the splat — a replay re-rolls the pitch and re-detaches/double-connects the SFX")
	assert_eq(quiet_sfx.get_parent(), quiet,
		"a silent drop (the mass death burst) must never detach or play its SFX — a 100-drop burst would roar")
	assert_true(quiet.is_queued_for_deletion(), "...but it still frees itself on contact")
	loud_sfx.free()


# --- bullet_hole_decal.gd (no class_name; extends Decal) -------------------------

## Drive a decal's fade by hand (no frame passes between steps): it must hold full alpha until its TimeTilFadeout
## Timer fires, then FADE — not pop — and free itself only once it has faded below decal_fade_min_alpha.
## Untyped `decal`: the fade handler is a script method, not Decal API.
func _assert_holds_then_fades_and_frees(decal, what: String) -> void:
	decal.modulate.a = 1.0
	for i in 20:
		decal._process(0.5)
	assert_almost_eq(decal.modulate.a, 1.0, 0.0001,
		"%s must hold full alpha until its fadeout Timer fires — ten seconds of frames must not dim it" % what)
	decal._on_time_til_fadeout_timeout()
	decal._process(0.001)
	assert_lt(decal.modulate.a, 1.0, "%s must start fading on the first frame after its fadeout Timer fires" % what)
	assert_false(decal.is_queued_for_deletion(), "%s must fade out gradually, not vanish on that first frame" % what)
	var steps := 0
	while not decal.is_queued_for_deletion() and steps < 100000:
		decal._process(0.1)
		steps += 1
	assert_true(decal.is_queued_for_deletion(),
		"%s must free itself once faded, or every impact leaves an invisible node behind for the rest of the level" % what)
	assert_lt(decal.modulate.a, GameSettings.effects.decal_fade_min_alpha,
		"%s must free only once it has faded below decal_fade_min_alpha — never while still visible" % what)


func test_bullet_hole_holds_until_its_timer_then_fades_out_and_frees() -> void:
	var hole = load(BULLET_HOLE_DECAL_PATH).new()
	add_child_autofree(hole)
	_assert_holds_then_fades_and_frees(hole, "a bullet hole")


# --- explosion.gd (no class_name; extends Node3D — projectile->Explosion bridge) -

## Run `action` and return every Explosion it put in the tree (wherever WorldSpawn parented it: the root in a
## level-less test). The real explosion_area.tscn runs its _ready here, exactly as a projectile's death spawns it.
func _explosions_spawned_by(action: Callable) -> Array[Node]:
	var spawned: Array[Node] = []
	var watch := func(node: Node) -> void:
		if node is Explosion:
			spawned.append(node)
	get_tree().node_added.connect(watch)
	action.call()
	get_tree().node_added.disconnect(watch)
	return spawned


func _free_nodes(nodes: Array[Node]) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.free()


func test_rock_impact_spawns_a_damaging_blast_carrying_the_bridge_tuning() -> void:
	var bridge = load(EXPLOSION_BRIDGE_PATH).new()
	bridge.max_explosion_force = 13.0
	bridge.explosion_radius = 2.5
	bridge.upward_bias = 0.4
	bridge.speed_to_scale = 6.0
	add_child_autofree(bridge)
	var impact := Vector3(3.0, 1.0, -2.0)
	var spawned := _explosions_spawned_by(func() -> void: bridge._on_rock_projectile_queued_for_deletion(impact))
	assert_eq(spawned.size(), 1, "a rock / rocket impact must spawn exactly one blast")
	if spawned.size() == 1:
		var blast := spawned[0] as Explosion
		assert_true(blast.deals_damage, "the rock / rocket blast must DAMAGE what it catches")
		assert_almost_eq(blast.max_explosion_force, 13.0, 0.0001, "the blast shoves with the force tuned on the projectile's bridge")
		assert_almost_eq(blast.explosion_radius, 2.5, 0.0001, "...over the radius tuned on the bridge")
		assert_almost_eq(blast.upward_bias, 0.4, 0.0001, "...with the bridge's upward bias")
		assert_almost_eq(blast.speed_to_scale, 6.0, 0.0001, "...and blooms at the bridge's rate")
		assert_true(blast.global_position.is_equal_approx(impact),
			"the blast must go off where the projectile died, got %s" % str(blast.global_position))
	_free_nodes(spawned)


func test_bullet_impact_spawns_a_harmless_spark_whatever_the_rock_tuning() -> void:
	var bridge = load(EXPLOSION_BRIDGE_PATH).new()
	bridge.max_explosion_force = 13.0
	bridge.explosion_radius = 2.5
	add_child_autofree(bridge)
	var spawned := _explosions_spawned_by(func() -> void: bridge._on_projectile_queued_for_deletion(Vector3(0.0, 1.0, 0.0)))
	assert_eq(spawned.size(), 1, "an ordinary bullet impact must spawn exactly one hit spark")
	if spawned.size() == 1:
		var spark := spawned[0] as Explosion
		assert_false(spark.deals_damage,
			"a bullet's hit spark must not damage — the round already dealt its damage, and a damaging spark charged every bullet an extra splash hit")
		assert_eq(spark.max_explosion_force, 0.0, "...nor shove anything, whatever force the rock path is tuned to")
		assert_almost_eq(spark.explosion_radius, GameSettings.effects.explosion_spark_radius, 0.0001,
			"...and it is sized by the spark radius knob, not the rock blast's reach")
	_free_nodes(spawned)


# --- ps1_applier.gd (no class_name; extends Node) --------------------------------

func test_ps1_applier_windows_are_ordered_and_the_shipped_look_is_wobble_only() -> void:
	var a = load(PS1_APPLIER_PATH).new()  # bare: _ready never runs
	assert_gt(a.vertex_snap, 0.0, "vertex_snap is a grid density — at 0 or below there is no grid to snap to")
	assert_true(a.vertex_snap <= a.SNAP_CEIL,
		"the authored vertex_snap must sit at or under SNAP_CEIL, or warp_params clamps the full-intensity value and the knob silently stops responding")
	assert_lt(a.snap_near_fade_start, a.snap_near_fade_end,
		"the near fade eases the wobble IN across an ascending depth window")
	assert_true(a.snap_near_fade_end <= a.snap_far_fade_start,
		"the wobble must reach full strength before the far fade starts easing it out — overlapping windows mean no depth ever gets the full effect")
	assert_lt(a.snap_far_fade_start, a.snap_far_fade_end,
		"the far fade eases the wobble OUT across an ascending depth window")
	assert_lt(a.affine_near, a.affine_far,
		"the affine depth window must be ascending — the shader floors far at near, so an inverted window silently collapses")
	assert_true(a.enabled,
		"SHIP DECISION: a PS1 applier dropped into a scene warps on play with no extra wiring")
	assert_eq(a.affine_amount, 0.0,
		"SHIP DECISION: the affine texture swim ships OFF — on these huge brush triangles it reads as broken rendering, so the shipped look is vertex wobble only")
	assert_true(a.cast_shadows,
		"SHIP DECISION: warped geometry keeps casting shadows (ps1.gdshader skips snapping in the shadow pass)")
	assert_false(a.stabilize_floor_surfaces,
		"SHIP DECISION: floor stabilization ships OFF — freezing floors while adjoining walls warp tears a flickering seam at every stair step and wall base; the snap_near_fade window does the underfoot-comfort job seam-free")
	a.free()


## A one-mesh world for the applier to walk: an opaque StandardMaterial3D box whose AUTHORED shadow mode is
## deliberately not the default, so a restore that merely resets shadows is told apart from a real restore.
func _ps1_world() -> Node3D:
	var world := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "Box"
	var box := BoxMesh.new()
	box.material = StandardMaterial3D.new()
	mi.mesh = box
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	world.add_child(mi)
	return world


func test_ps1_warp_rescales_live_and_zero_percent_restores_the_authored_world() -> void:
	var a = load(PS1_APPLIER_PATH).new()  # off-tree: no Settings lookup; _refresh is the per-frame path's body
	var world := _ps1_world()
	var mi := world.get_node("Box") as MeshInstance3D
	a.target_root = world
	a.vertex_snap = 80.0
	a.affine_amount = 1.0
	a.snap_near_fade_start = 0.5
	a.snap_near_fade_end = 2.0
	a.snap_far_fade_start = 12.0
	a.snap_far_fade_end = 30.0
	a.cast_shadows = false
	a._refresh(1.0)
	var warp := mi.get_surface_override_material(0) as ShaderMaterial
	assert_true(warp != null, "at 100% an opaque level surface must wear the PS1 warp")
	if warp == null:
		world.free()
		a.free()
		return
	assert_almost_eq(float(warp.get_shader_parameter("vertex_snap")), 80.0, 0.0001, "100% pushes the authored vertex_snap to the shader")
	assert_almost_eq(float(warp.get_shader_parameter("affine_amount")), 1.0, 0.0001, "100% pushes the authored affine amount")
	assert_almost_eq(float(warp.get_shader_parameter("snap_near_fade_start")), 0.5, 0.0001, "the authored near fade reaches the shader")
	assert_almost_eq(float(warp.get_shader_parameter("snap_far_fade_end")), 30.0, 0.0001, "the authored far fade reaches the shader")
	assert_eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"cast_shadows = false turns shadow casting off on the geometry it warped")
	a._refresh(0.5)
	assert_eq(mi.get_surface_override_material(0), warp,
		"moving the accessibility slider must RESCALE the live warp material, not re-walk the level")
	assert_almost_eq(float(warp.get_shader_parameter("vertex_snap")), 160.0, 0.0001,
		"half intensity doubles the snap grid on the live material — half the jitter the player sees")
	assert_almost_eq(float(warp.get_shader_parameter("affine_amount")), 0.5, 0.0001, "...and halves the texture swim")
	a._refresh(0.0)
	assert_null(mi.get_surface_override_material(0),
		"0% must clear the override so the level renders with its own material again (the accessibility OFF)")
	assert_eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED,
		"...and hand back the mesh's AUTHORED shadow mode, not a default one")
	a._refresh(0.25)
	assert_true(mi.get_surface_override_material(0) is ShaderMaterial,
		"raising the slider again from 0% must re-apply the warp without a level reload")
	world.free()
	a.free()


func test_ps1_master_switch_off_leaves_the_world_unwarped() -> void:
	for on in [true, false]:
		var a = load(PS1_APPLIER_PATH).new()  # bare: no Settings autoload read, so intensity is the full effect
		var world := _ps1_world()
		a.target_root = world
		a.enabled = on
		a._process(1.0 / 60.0)
		var override := (world.get_node("Box") as MeshInstance3D).get_surface_override_material(0)
		if on:
			assert_true(override is ShaderMaterial,
				"CONTROL: an enabled applier warps the level on its first frame")
		else:
			assert_null(override, "enabled = false must never warp the level, whatever the accessibility slider says")
		world.free()
		a.free()


func test_ps1_warp_intensity_scales_jitter_and_affine() -> void:
	# The accessibility slider (Settings.ps1_warp_intensity, Options -> Accessibility) scales the warp via
	# this pure static mapping: 100% = the applier's base values, lower = less jitter + less texture-swim,
	# 0% = OFF. (80.0 / 1.0 below are arbitrary FIXTURE args to the pure static fn, not the shipped
	# defaults — those are checked in test_ps1_applier_windows_are_ordered_and_the_shipped_look_is_wobble_only above.)
	var Ps1: GDScript = load("res://scripts/effects/ps1_applier.gd")
	var full: Dictionary = Ps1.warp_params(80.0, 1.0, 1.0)
	assert_true(full["apply"], "100% intensity applies the warp")
	assert_eq(full["snap"], 80.0, "100% passes the base vertex_snap through unchanged (full jitter)")
	assert_eq(full["affine"], 1.0, "100% passes the base affine amount through unchanged")
	# Jitter amplitude is ∝ 1/vertex_snap, so HALF intensity doubles the snap (half the wobble) and halves affine.
	var half: Dictionary = Ps1.warp_params(80.0, 1.0, 0.5)
	assert_eq(half["snap"], 160.0, "50% doubles vertex_snap -> half the jitter amplitude")
	assert_eq(half["affine"], 0.5, "50% halves the affine texture warp")
	# 0% must NOT apply — the applier clears its material overrides so the world renders normally.
	var off: Dictionary = Ps1.warp_params(80.0, 1.0, 0.0)
	assert_false(off["apply"], "0% intensity must not apply — the level renders normally (overrides cleared)")
	assert_eq(off["affine"], 0.0, "0% has zero affine warp")
	# Clamp + ceiling: >100% saturates to the authored full effect; a near-zero value caps snap at SNAP_CEIL.
	assert_eq(Ps1.warp_params(80.0, 1.0, 2.0)["snap"], 80.0, "intensity clamps to 100% (snap stays at the base value)")
	assert_eq(Ps1.warp_params(80.0, 1.0, 0.001)["snap"], 4096.0, "a near-zero intensity caps vertex_snap at SNAP_CEIL (no absurd grid)")


# --- spark_attack.gd (SparkAttack; extends GPUParticles3D) -----------------------

func test_spark_attack_handler() -> void:
	# No _ready defined; assert handler presence only. Do NOT call it — it fires restart()
	# which emits the one-shot particle burst.
	var n = load("res://scripts/components/spark_attack.gd").new()
	assert_true(n.has_method("_on_attack_flash_muzzle"),
		"spark_attack.gd must expose _on_attack_flash_muzzle — the handler wired to Attack.flash_muzzle that re-fires the muzzle sparks")
	n.free()


# --- muzzle_smoke.gd (class MuzzleSmoke) -----------------------------------------

func test_muzzle_smoke_type_and_handler() -> void:
	# Bare instance: with no scene-authored process_material, _ready has nothing to duplicate (it only forces
	# emitting off and idles _process), and _on_attack_flash_muzzle returns at once (_proc_mat == null), so
	# calling the handler here observes nothing; it never restarts the emitter in any case. Assert TYPE + the
	# handler name GunMesh.setup() connects BY NAME (Callable(sm, "_on_attack_flash_muzzle")).
	var n = load("res://scripts/components/muzzle_smoke.gd").new()
	assert_true(n is GPUParticles3D,
		"MuzzleSmoke must extend GPUParticles3D — it IS the emitter, so authoring is 'drop the scene under a muzzle marker', not 'add a script that spawns one'")
	assert_true(n.has_method("_on_attack_flash_muzzle"),
		"MuzzleSmoke must expose _on_attack_flash_muzzle — the handler wired to Attack.flash_muzzle that puffs the barrel on each shot")
	n.free()


## The whole per-shot gate in one pure call. Pinned here because it is the ONLY place three separate
## authoring surfaces meet — the player's Options dial, the project-wide has_muzzle_flash flag, and the
## per-weapon muzzle_smoke_scale — and a wrong precedence between them is invisible until you play.
func test_muzzle_smoke_puff_scale_truth_table() -> void:
	var Smoke = load("res://scripts/components/muzzle_smoke.gd")
	var gun := WeaponData.new()
	gun.has_muzzle_flash = true
	gun.muzzle_smoke_scale = 1.5
	var melee := WeaponData.new()
	melee.has_muzzle_flash = false
	melee.muzzle_smoke_scale = 1.0

	assert_almost_eq(float(Smoke.puff_scale(gun, 1.0)), 1.5, 0.0001,
		"A gun's own muzzle_smoke_scale IS the puff size while the player's dial is at full")
	assert_almost_eq(float(Smoke.puff_scale(gun, 0.5)), 0.75, 0.0001,
		"The player's Options dial MULTIPLIES the weapon's scale, so half the dial is half the puff")
	assert_eq(float(Smoke.puff_scale(gun, 0.0)), 0.0,
		"Dial at 0 must kill the smoke for every weapon — checked first, so the emitter never even restarts")
	assert_almost_eq(float(Smoke.puff_scale(gun, 2.0)), 1.5, 0.0001,
		"The dial is clamped to 0..1: a stale/hand-edited cfg above 1 must not scale every gun's smoke up")
	assert_eq(float(Smoke.puff_scale(melee, 1.0)), 0.0,
		"has_muzzle_flash false (melee / fists / spray can) means no smoke whatever muzzle_smoke_scale says — so a new melee weapon is dry with no extra authoring")
	assert_almost_eq(float(Smoke.puff_scale(null, 1.0)), 1.0, 0.0001,
		"A null weapon means NO weapon source was wired (bare rig / test scene), not 'unarmed' — degrade to the authored puff like MuzzleFlash and SparkAttack do, never to silence")
	gun.muzzle_smoke_scale = 0.0
	assert_eq(float(Smoke.puff_scale(gun, 1.0)), 0.0,
		"muzzle_smoke_scale 0 is the per-weapon opt-out for a gun that flashes but must not smoke")
	gun = null
	melee = null


func test_muzzle_smoke_tuning_defaults() -> void:
	var fx := GameSettings.effects
	assert_eq(typeof(fx.muzzle_smoke_alpha), TYPE_FLOAT,
		"EffectsSettings.muzzle_smoke_alpha must be a float — MuzzleSmoke writes it into the process material's colour, on top of the ramp's per-particle fade")
	assert_between(fx.muzzle_smoke_alpha, 0.0, 1.0,
		"muzzle_smoke_alpha IS an alpha, so it must stay inside 0..1")
	assert_gt(fx.muzzle_smoke_hold, 0.0,
		"muzzle_smoke_hold is the seconds the barrel keeps STREAMING after a shot — at 0 the emitter is switched off the same frame it is switched on and no smoke ever appears")
	assert_gte(fx.muzzle_smoke_delay, 0.0,
		"muzzle_smoke_delay is a WAIT in seconds, so it can never be negative; 0 is the legitimate 'smoke on the same frame as the flash' setting")
	# The whole point of the delay is that the smoke is a SEPARATE beat from the bang. If it ever grows past
	# the hold, emission would start only after the window that feeds it has already expired — the barrel
	# would arm, wait, and then never smoke at all. Nothing else in the codebase relates these two.
	assert_lt(fx.muzzle_smoke_delay, fx.muzzle_smoke_hold + fx.muzzle_smoke_taper,
		"muzzle_smoke_delay must stay shorter than the hold+taper it delays, or the barrel arms and then never actually smokes")
	assert_gte(fx.muzzle_smoke_taper, 0.0,
		"muzzle_smoke_taper is the seconds the stream takes to PETER OUT, so it can never be negative; 0 is the hard-cut setting")
	assert_gte(fx.muzzle_smoke_attack, 0.0,
		"muzzle_smoke_attack is the seconds the stream takes to SWELL IN, so it can never be negative; 0 is the snap-to-full-flow setting")
	# The swell and the taper are the two ends of ONE amount_ratio envelope (min of both), so a swell longer
	# than the window it swells into means the stream starts fading before it ever reaches full flow — the
	# effect quietly guts itself and nothing else in the codebase relates these two numbers.
	assert_lt(fx.muzzle_smoke_attack, fx.muzzle_smoke_hold,
		"muzzle_smoke_attack must finish inside muzzle_smoke_hold, or the stream begins tapering before it has swelled to full flow")


# --- blood_splat_decal.gd (no class_name; extends Decal) -------------------------

func test_blood_splat_grows_to_its_target_size_then_holds_until_its_timer_and_fades() -> void:
	var splat = load(BLOOD_SPLAT_DECAL_PATH).new()
	var spawn_size := Vector3(0.01, 0.01, 0.01)
	var target := Vector3(1.5, 0.2, 1.5)
	splat.size = spawn_size
	splat.target_size = target
	splat.grow_time = 0.1
	add_child_autofree(splat)  # _ready starts the grow tween
	assert_true(splat.size.is_equal_approx(spawn_size),
		"a splat must GROW from its spawn size — it must not snap to full size the frame it lands")
	await wait_seconds(0.4)
	assert_true(splat.size.is_equal_approx(target),
		"after grow_time the splat must have spread to exactly its target_size, got %s" % str(splat.size))
	_assert_holds_then_fades_and_frees(splat, "a blood splat")


# --- blood_light.gd (no class_name; extends OmniLight3D) -------------------------

func test_blood_light_glow_frees_itself_after_its_lifetime() -> void:
	var brief = load(BLOOD_LIGHT_PATH).new()
	brief.time_to_destroy = 0.05
	add_child_autofree(brief)
	var lasting = load(BLOOD_LIGHT_PATH).new()
	lasting.time_to_destroy = 30.0
	add_child_autofree(lasting)
	await wait_seconds(0.3)
	assert_false(is_instance_valid(brief),
		"the wet-blood glow must free itself once time_to_destroy has passed — dozens of splats must not pile up lights")
	assert_true(is_instance_valid(lasting) and lasting.is_inside_tree(),
		"CONTROL: a glow whose lifetime has not passed is still lit")
	# The script default (0) is a placeholder; the splat scene assigns the real lifetime.
	var splat := (load(BLOOD_SPLAT_DECAL_SCENE) as PackedScene).instantiate()  # off-tree: no Timer, no tween
	var glow := splat.get_node_or_null(^"BloodLight")
	assert_true(glow != null and float(glow.get(&"time_to_destroy")) > 0.0,
		"blood_splat_decal.tscn must give its BloodLight a positive time_to_destroy — at the script's 0 the glow frees the frame the splat lands and the wet highlight never shows")
	splat.free()


# --- star_sky.gd + horizon_sky.gdshader (the on-kill sky flash) ------------------

## SILENT-FAILURE GUARD for the sky pops. StarSky drives FOUR uniforms on horizon_sky.gdshader across two
## channels: it TWEENS `flash` / `hurt_flash` and SETS `flash_color` / `hurt_flash_color` from the EffectsSettings
## colours. Every write is probed through StarSky._has_param first, so a renamed or deleted uniform errors nowhere —
## the kill flash (or the damage wash) just quietly stops, or reverts to the shader's own hard-coded colour.
##
## Kept as a SOURCE read because headless runs NEVER compile a .gdshader, so no test can ask the material which
## parameters it publishes. Tolerant of spacing and alignment, blind to comments, and it also requires each
## uniform to be READ by the shader code: a declared-but-unused uniform still publishes its parameter, so the
## tween runs and the sky never changes.
func test_horizon_sky_declares_and_reads_all_four_flash_uniforms() -> void:
	var src := FileAccess.get_file_as_string(HORIZON_SKY_PATH)
	assert_false(src.is_empty(),
		"horizon_sky.gdshader must be readable — StarSky preloads it as the runtime sky for every WorldEnvironment")
	var code := RegEx.create_from_string("(?s)/\\*.*?\\*/").sub(src, "", true)
	code = RegEx.create_from_string("//[^\\n]*").sub(code, "", true)
	for u in [["float", "flash", "StarSky.flash_kill tweens it; without it the kill flash is skipped entirely"],
			["vec3", "flash_color", "flash_kill sets it from sky_flash_color; without it the kill pop ignores the designer's colour"],
			["float", "hurt_flash", "StarSky.flash_hurt tweens it on its own channel; without it taking damage stops washing the sky"],
			["vec3", "hurt_flash_color", "flash_hurt sets it from sky_hurt_color; without it the damage wash ignores the designer's colour"]]:
		var type_name: String = u[0]
		var uniform_name: String = u[1]
		var declared := RegEx.create_from_string("\\buniform\\s+%s\\s+%s\\b" % [type_name, uniform_name]).search(code)
		assert_true(declared != null,
			"horizon_sky.gdshader must declare `uniform %s %s` — %s" % [type_name, uniform_name, u[2]])
		var mentions := RegEx.create_from_string("\\b%s\\b" % uniform_name).search_all(code).size()
		assert_gt(mentions, 1,
			"horizon_sky.gdshader must READ `%s` in its shader code, not only declare it — an unused uniform still publishes the parameter, so StarSky's write lands and the sky never changes" % uniform_name)

## The colour StarSky writes is a designer knob, so its VALUE is deliberately not pinned (the user tunes it).
## What is pinned is the shape the read site depends on: flash_kill builds `up -> optional hold -> down` and
## clamps the peak, so the three times must be floats and the colour must be a Color. A wrong TYPE here is the
## one mistake that would error inside the tween instead of just looking different.
func test_sky_flash_tuning_field_types() -> void:
	var s := EffectsSettings.new()  # class_name is global; a Resource, so release it with = null (never free)
	assert_eq(typeof(s.sky_flash_color), TYPE_COLOR,
		"sky_flash_color must be a Color — StarSky.flash_kill passes it straight to set_shader_parameter for a vec3 uniform")
	assert_eq(typeof(s.sky_flash_peak), TYPE_FLOAT,
		"sky_flash_peak must be a float — flash_kill clampf()s it into the tween's target value")
	assert_eq(typeof(s.sky_hurt_color), TYPE_COLOR,
		"sky_hurt_color must be a Color — StarSky.flash_hurt passes it straight to set_shader_parameter for a vec3 uniform")
	assert_eq(typeof(s.sky_hurt_peak), TYPE_FLOAT,
		"sky_hurt_peak must be a float — _run_channel clampf()s it into the tween's target value")
	for field in ["sky_flash_up_time", "sky_flash_hold_time", "sky_flash_down_time",
			"sky_hurt_up_time", "sky_hurt_hold_time", "sky_hurt_down_time"]:
		assert_eq(typeof(s.get(field)), TYPE_FLOAT,
			"%s must be a float — _run_channel passes it as a tweener duration (hold is skipped entirely at <= 0)" % field)
	# The hurt wash must stay SHORTER than the kill flash: you take damage far more often than you kill, and a red
	# beat as long as the kill one would sit red through a firefight and swallow the kill cue it has to read apart from.
	var kill_beat: float = s.sky_flash_up_time + s.sky_flash_hold_time + s.sky_flash_down_time
	var hurt_beat: float = s.sky_hurt_up_time + s.sky_hurt_hold_time + s.sky_hurt_down_time
	assert_lt(hurt_beat, kill_beat,
		"the hurt sky wash (%.2fs) must stay shorter than the kill flash (%.2fs) — damage is frequent, kills are not; a red beat this long or longer holds the sky red through sustained fire" % [hurt_beat, kill_beat])
	s = null


# --- the on-kill SCREEN SHAKE (Player.on_scored_kill -> ScreenShake.shake) -------

## The kick under the kill flash, DRIVEN rather than read as text: Player.on_scored_kill runs on a BARE Player
## (load().new(), never added to the tree — its _enter_tree/_ready need the full camera rig), with a bare ScreenShake
## standing in for the handle _ready resolves off the head rig. The call's other two cues are inert there: StarSky
## skips with no sky material, and the HUD handle is null.
func test_a_credited_kill_kicks_the_camera_under_the_ordinary_trauma_ceiling() -> void:
	_retune(GameSettings.screen_shake, &"kill_shake_amount", 0.3)
	var player = load(PLAYER_PATH).new()
	player.on_scored_kill()  # no rig yet (null off-tree and before _ready): the kill cue must not crash
	var rig := ScreenShake.new()
	player.screen_shake = rig
	player.on_scored_kill()
	assert_almost_eq(rig.trauma, 0.3, 0.0001,
		"a credited kill must add kill_shake_amount of trauma — without it a kill still flashes the sky but the camera never answers")
	# shake(), not shake_explosion(): blasts get a higher ceiling so they can out-shake everything, and a kill
	# borrowing it would out-punch the grenade that scored it.
	assert_gt(GameSettings.screen_shake.explosion_max_trauma, ScreenShake.MAX_TRAUMA,
		"CONTROL: the explosion ceiling sits above the ordinary one, so the saturation check below can tell them apart")
	rig.trauma = ScreenShake.MAX_TRAUMA - 0.1
	player.on_scored_kill()
	assert_almost_eq(rig.trauma, ScreenShake.MAX_TRAUMA, 0.0001,
		"a kill on top of heavy shake must saturate at ScreenShake.MAX_TRAUMA — the ordinary ceiling, never the explosion one")
	rig.free()
	player.free()


func test_no_kill_kick_once_the_player_is_dying() -> void:
	# Retuned so the CONTROL below never depends on the shipped kill_shake_amount (0 is its documented off switch).
	_retune(GameSettings.screen_shake, &"kill_shake_amount", 0.3)
	var player = load(PLAYER_PATH).new()
	var rig := ScreenShake.new()
	player.screen_shake = rig
	player._dying = true
	player.on_scored_kill()
	assert_eq(rig.trauma, 0.0,
		"a kill credited while the player's own death plays (a grenade landing post-mortem) must not kick the death cinematic's camera")
	player._dying = false
	player.on_scored_kill()
	assert_gt(rig.trauma, 0.0, "CONTROL: the same player and rig do kick once alive")
	rig.free()
	player.free()


## The kick's TUNING. Its value is a designer knob so it is not pinned to a number, but three properties the
## read site leans on are: it must exist as a float (on_scored_kill passes it straight into shake()), it must be
## POSITIVE out of the box (0 is the documented "off" switch — shipping at 0 would mean the feature never fires
## for anyone), and it must stay under ScreenShake.MAX_TRAUMA, above which shake()'s clamp makes the number a lie
## and any further tuning silently does nothing.
func test_kill_shake_tuning_default() -> void:
	var s := ScreenShakeSettings.new()  # class_name is global; a Resource, so release it with = null (never free)
	assert_eq(typeof(s.kill_shake_amount), TYPE_FLOAT,
		"kill_shake_amount must be a float — Player.on_scored_kill passes it straight to ScreenShake.shake(), which adds it to trauma")
	assert_gt(s.kill_shake_amount, 0.0,
		"kill_shake_amount must ship POSITIVE — 0 is its documented off switch, so a 0 default would mean no kill in the game ever kicks the camera")
	assert_lte(s.kill_shake_amount, ScreenShake.MAX_TRAUMA,
		"kill_shake_amount must stay within ScreenShake.MAX_TRAUMA (%.2f) — shake() clamps to it, so a larger value is silently truncated and stops responding to tuning" % ScreenShake.MAX_TRAUMA)
	# A kill you are CREDITED with and a death that merely happened NEXT TO you are separate events with separate
	# knobs, and on_scored_kill fires at any range while on_nearby_death falls off to nothing by death_shake_range.
	# Point-blank, both land on the same trauma pool — so the kill kick must not on its own be the harder of the
	# two, or killing at arm's length would read as a bigger event than the blast/gore right in your face.
	assert_lte(s.kill_shake_amount, s.death_shake_amount,
		"the credited-kill kick (%.2f) must not exceed the point-blank nearby-death kick (%.2f) — both stack on the same trauma pool at close range, and the up-close death is meant to be the more violent of the two" % [s.kill_shake_amount, s.death_shake_amount])
	s = null


# --- blood emitters must not hand-drive Engine.time_scale ------------------------

## ⭐blood.tscn and bloody_mess.tscn used to carry a `ParticleTimeBind` script that re-wrote the emitter's
## `speed_scale = base * Engine.time_scale` every frame. That SQUARED every slow-mo. Godot already multiplies the
## frame step it hands the RenderingServer by Engine.time_scale, so the second multiply landed on top of it and the
## burst advanced at time_scale**2. Measured in a real window at Engine.time_scale 0.2 (BulletTime's airborne
## slow-mo, the project's clean repro): the blood burst needed 23.9x its normal wall-clock time to develop instead
## of 5x, i.e. it crawled at 1/25 speed while the world merely halved-and-halved-again. dust.tscn never carried the
## script and was the control at 4.6x.
##
## The same script also pinned the emitter to PROCESS_MODE_ALWAYS, which is the second half of the defect: Godot
## zeroes a PAUSED GPUParticles3D's server-side speed scale through NOTIFICATION_PAUSED (the behaviour
## EffectPrewarmer._arm_particles deliberately works around), so an always-processing emitter never gets the
## notification. Blood was the only effect in the game that kept flying through a dialogue pause and through
## FreezeFrame.pause_briefly()'s hard pause-on-kill, while dust, sparks, smoke and gibs all held still.
##
## Headless never SIMULATES GPU particles, so the burst's pace cannot be measured here, but both CAUSES are
## observable on the real scenes in the tree: whatever runs on an emitter each frame (a script, whatever its name or
## however a re-save spells its ext_resource) gets to rewrite speed_scale under a slow-mo, and the emitter's
## effective process mode decides whether a paused tree stops it. So each scene is instantiated under a PAUSABLE
## parent (the mode a level's gore inherits), run for a few frames at time_scale 0.2, and checked against a second
## instance that never entered the tree (the Inspector's speed_scale).
func test_blood_emitters_keep_their_authored_pace_under_slow_mo_and_stop_for_a_pause() -> void:
	for scene_path in ["res://scenes/effects/blood.tscn", "res://scenes/effects/bloody_mess.tscn"]:
		var packed := load(scene_path) as PackedScene
		assert_true(packed != null, "%s must load as a PackedScene" % scene_path)
		if packed == null:
			continue
		var authored := packed.instantiate()  # never enters the tree: its speed_scale values are the authored ones
		var holder := Node.new()
		holder.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child_autofree(holder)
		var live := packed.instantiate()
		holder.add_child(live)
		var live_emitters := _gpu_emitters(live)
		var authored_emitters := _gpu_emitters(authored)
		assert_gt(live_emitters.size(), 0, "%s must hold at least one GPUParticles3D, or the checks below pass vacuously" % scene_path)
		_prior_time_scale = Engine.time_scale
		Engine.time_scale = 0.2  # BulletTime's airborne slow-mo, the measured repro
		await wait_process_frames(3)
		assert_almost_eq(Engine.time_scale, 0.2, 0.0001, "setup: the slow-mo held through the frames the emitters ran")
		for i in live_emitters.size():
			var em: GPUParticles3D = live_emitters[i]
			var src: GPUParticles3D = authored_emitters[i]
			assert_almost_eq(em.speed_scale, src.speed_scale, 0.0001,
				"%s: %s must keep its authored speed_scale under slow-mo. Godot already scales the frame step by Engine.time_scale, so anything that multiplies speed_scale by it too squares every bullet-time / hitstop slow-mo (measured 23.9x slower instead of 5x at time_scale 0.2)" % [scene_path, em.name])
		Engine.time_scale = _prior_time_scale
		_prior_time_scale = -1.0
		var prior_paused: bool = get_tree().paused
		for em: GPUParticles3D in live_emitters:
			assert_true(em.can_process(), "control: %s: %s processes while the tree runs" % [scene_path, em.name])
		get_tree().paused = true
		var runs_while_paused: Array[String] = []
		for em: GPUParticles3D in live_emitters:
			if em.can_process():
				runs_while_paused.append(String(em.name))
		get_tree().paused = prior_paused
		assert_true(runs_while_paused.is_empty(),
			"%s: every emitter must stop with a paused tree like dust, sparks, smoke and gibs do (still processing: %s). An always-processing emitter never gets NOTIFICATION_PAUSED, so blood kept flying through a dialogue pause and the pause-on-kill" % [scene_path, ", ".join(runs_while_paused)])
		authored.free()


## `root` itself plus every GPUParticles3D under it, in tree order (so two instances of one scene line up by index).
func _gpu_emitters(root: Node) -> Array[GPUParticles3D]:
	var out: Array[GPUParticles3D] = []
	if root is GPUParticles3D:
		out.append(root as GPUParticles3D)
	for n in root.find_children("*", "GPUParticles3D", true, false):
		out.append(n as GPUParticles3D)
	return out
