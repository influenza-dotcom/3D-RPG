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
## Deliberate exceptions to that scope are SOURCE-TEXT pins on seams no headless test can drive and whose
## drift fails silently: the ExplosionMesh ink-mask/ring contract (in its section below), the blood emitters' no-time-scale-script
## contract (bottom of the file — headless never simulates GPU particles at all), and — at the BOTTOM
## of this file — the on-kill cue, which is split across subsystems: the sky flash is StarSky's (effects, and
## pinned here), but the camera kick belongs to Player.on_scored_kill, which no headless test can build (see
## test_player_core.gd's construction note). Both halves of that cue are pinned together, next to each other,
## so a retune of one cannot silently orphan the other. Those tests read source as TEXT (player.gd, the sky
## shader, explosion_mesh.gd) plus a ScreenShakeSettings resource, and stay side-effect-free.
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


# --- explosion.gd (projectile-death -> blast bridge) -----------------------------

## Regression guard for every explosion caller: Explosion.instantiate_recovering() — the ONE reimport-recovery source
## (gun_fx spark/burst/flash, paint_projectile pop, explosion.gd bridge) — must always resolve an instantiable blast.
## If the cached load ever bakes empty (editor reimport churn), the fresh-from-disk fallback must still produce a node,
## otherwise a destroyed projectile silently never spawns its blast. A bare instantiate does NOT run _ready (it would
## dereference null @export children), so never add_child — free the bare node.
func test_explosion_bridge_scene_is_instantiable() -> void:
	var ex := Explosion.instantiate_recovering()
	assert_not_null(ex,
		"Explosion.instantiate_recovering() must resolve a blast node (the cached scene, or a fresh re-load if it baked empty)")
	if ex != null:
		ex.free()


# --- explosion_area.gd (class Explosion) -----------------------------------------

func test_explosion_area_exported_defaults() -> void:
	# Bare instance: Explosion._ready dereferences mesh_instance.mesh (null on a bare
	# node) and would crash, so NEVER add_child — read the scalar exports off the object.
	var n = load("res://scripts/components/explosion_area.gd").new()
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
	var n = load("res://scripts/components/explosion_area.gd").new()
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
	# (The old OUTLINE_COLOR / OUTLINE_WIDTH pins died with the inverted hull on 2026-08-27 —
	# the flash's optional outline is InkOutline's screen-space ring now; see the source pin below.)
	var n = load("res://scripts/components/explosion_mesh.gd").new()
	assert_eq(n.EMISSION_ENERGY_MULTIPLIER, 3.0,
		"EMISSION_ENERGY_MULTIPLIER 3.0 is the base emissive brightness the flash pulses around")
	assert_eq(n.speed_to_scale, 0.0,
		"speed_to_scale default 0.0 => the mesh starts at full scale (instant flash); >0 grows from zero (explosion bloom)")
	assert_false(n.has_outline,
		"has_outline must default false so the flash mesh has no outline pass unless explicitly enabled")
	n.free()


## SILENT-FAILURE GUARD for the flash's ink contract, replacing the OUTLINE_COLOR / OUTLINE_WIDTH pins that
## went with the inverted hull (2026-08-27, "the ring owns every actor"). has_outline now means "InkOutline's
## screen-space ring, and only the ring", and BOTH halves of that contract fail invisibly: drop the
## ACTOR_INK_MASK_LAYER stamp and the WORLD's edge-detect quietly re-inks every explosion / hit spark as if it
## were geometry (the exact 2026-08-16 defect the stamp exists to prevent); drop the TINT_ID_NEUTRAL ring and
## the muzzle flash just loses its line with no error anywhere. Both live in _ready, which needs real scene
## children — so this is a source-text pin like the StarSky / on_scored_kill guards at the bottom of this file.
## If it fails, restore the calls or update the pin to the new seam — do not just delete the assertion.
func test_explosion_mesh_rides_the_ink_ring() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/components/explosion_mesh.gd")
	assert_false(src.is_empty(),
		"explosion_mesh.gd must be readable — it owns the flash's ink-mask + optional-ring contract")
	assert_true(src.contains("layers |= InkOutline.ACTOR_INK_MASK_LAYER"),
		"ExplosionMesh._ready must OR InkOutline.ACTOR_INK_MASK_LAYER into layers — a flash is LIGHT, not geometry, and without the mask bit the world's screen-space ink draws a black ring around every explosion and bullet-impact spark")
	assert_true(src.contains("InkOutline.apply_tint_mesh(self, InkOutline.TINT_ID_NEUTRAL)"),
		"has_outline's ON path must be InkOutline.apply_tint_mesh(self, InkOutline.TINT_ID_NEUTRAL) — since the hull's deletion the ring IS the flash's only outline, and the neutral id keeps it the same black at the same weight as every other line in the game")


func test_explosion_mesh_has_tint() -> void:
	# tint() is the recolour entry point the paint splat / Explosion.tint_color path calls.
	# Conservatively assert presence only (do NOT depend on calling it on a bare node).
	var n = load("res://scripts/components/explosion_mesh.gd").new()
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
	# COUPLING: the live window AND the raise tween both derive from the designer knob
	# GameSettings.effects.gun_raise_time via int(t * 1000) (the unholster() derivation); the const
	# above stays as the baseline/anchor, so the field's DEFAULT must match it or the shipped
	# laser-gate window silently splits from the raise animation.
	var fx := EffectsSettings.new()
	assert_eq(fx.gun_raise_time, n.GUN_RAISE_MS / 1000.0,
		"gun_raise_time must default to GUN_RAISE_MS / 1000 — one knob drives both the post-reload raise tween and the laser-sight gate window")
	fx = null
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
# which GunPose was clobbering — the bug that left the sniper visible while scoped. Truth table, tested via
# the static (the live host.visible write is in-tree / playtested).

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


func test_gun_mesh_on_aim_changed_sets_aiming_not_visibility() -> void:
	# _on_aim_changed must ONLY record the _aiming flag (GunPose reads it to drive both the ADS pose and the
	# scope-hide). It must NOT write `visible` itself — GunPose owns host.visible per frame, so a write here
	# would just be clobbered. Bare instance (no _ready), so no GunPose runs.
	var n = load("res://scripts/effects/gun_mesh.gd").new()
	var before: bool = n.visible
	n._on_aim_changed(true)
	assert_true(n._aiming,
		"_on_aim_changed(true) records _aiming so GunPose can apply the ADS pose + scope-hide")
	assert_eq(n.visible, before,
		"_on_aim_changed must NOT touch visibility — GunPose owns host.visible per-frame (writing it here was the clobbered scope-hide bug)")
	n._on_aim_changed(false)
	assert_false(n._aiming, "_on_aim_changed(false) clears _aiming on unscope")
	n.free()


# --- muzzle_flash.gd (class MuzzleFlash) -----------------------------------------

func test_muzzle_flash_type_and_handler() -> void:
	# No _ready defined, but _do_muzzle_flash dereferences a null mesh_instance_3d, so
	# never CALL it — kept bare for symmetry and to assert type + handler presence only.
	var n = load("res://scripts/components/muzzle_flash.gd").new()
	assert_true(n is Node3D,
		"MuzzleFlash must extend Node3D so it positions its flash mesh + light in 3D at the muzzle")
	assert_true(n.has_method("_do_muzzle_flash"),
		"MuzzleFlash must expose _do_muzzle_flash — the handler wired to Attack.flash_muzzle that blinks the flash on each shot")
	n.free()


# --- ambient_dust.gd (class AmbientDust) -----------------------------------------

func test_ambient_dust_exported_defaults() -> void:
	# Bare instance: AmbientDust._ready builds particle/process materials and _process reads
	# get_viewport().get_camera_3d(), so NEVER add_child — read the scalar exports off it.
	var n = load("res://scripts/components/ambient_dust.gd").new()
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

func test_blood_drop_emitter_tuning_defaults() -> void:
	# The per-drop spawn parameters moved to GameSettings.effects (EffectsSettings); pin the
	# script defaults on a fresh resource so the emitter's spawn shape stays designer-tunable
	# without silently drifting.
	var fx := EffectsSettings.new()
	assert_eq(fx.blood_drop_scatter, 1.8,
		"blood_drop_scatter 1.8 is the spawn-position spread (metres) around the death origin for each blood drop")
	assert_eq(fx.blood_drop_vel_min, 3.0,
		"blood_drop_vel_min 3.0 is the slowest initial launch speed for a blood drop")
	assert_eq(fx.blood_drop_vel_max, 9.0,
		"blood_drop_vel_max 9.0 is the fastest initial launch speed; vel_min..vel_max is the randf_range the rain uses")
	fx = null


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
	assert_eq(n.vertex_snap, 396.0,
		"vertex_snap default 396.0 = one snap cell per texel of the real 792-wide screen buffer; the unwelded brush mesh tears open by up to one cell at seams, so a coarser grid (like the old 80) holes buildings through to the sky")
	assert_eq(n.snap_far_fade_start, 20.0,
		"snap_far_fade_start default 20.0m — the snap begins easing out here so distant buildings stop jittering (their coplanar brush faces z-fight and per-frame jitter turns that into flashing)")
	assert_eq(n.snap_far_fade_end, 40.0,
		"snap_far_fade_end default 40.0m — past this depth geometry renders unwarped: no re-randomized z-fights, no sky-tears, no far-DOF re-blur shimmer at range")
	assert_eq(n.affine_amount, 0.0,
		"affine_amount default 0.0 — the affine texture swim smears textures on huge brush triangles (reads as broken, not retro), so the shipped look is vertex wobble only; affine is per-instance opt-in")
	assert_eq(n.affine_near, 1.0,
		"affine_near default 1.0m — closer than this renders perspective-correct so point-blank textures stay clean")
	assert_eq(n.affine_far, 6.0,
		"affine_far default 6.0m — the depth clamp that stops one huge brush triangle smearing its texture (ratio <= far/near)")
	assert_true(n.cast_shadows,
		"cast_shadows must default true — casting is stable now that ps1.gdshader skips snapping in the shadow pass (a snapped shadow map strobed every lit surface); OFF is only for the flat no-realtime-shadows look")
	assert_false(n.stabilize_floor_surfaces,
		"floor stabilization must default false — freezing floors while adjoining walls warp tears a flickering seam at every stair-step and wall-base contact; the snap_near_fade window covers the underfoot-comfort job seam-free")
	assert_eq(n.snap_near_fade_start, 0.75,
		"snap_near_fade_start default 0.75m — the snap eases in from the camera so point-blank geometry and the floor underfoot hold still")
	assert_eq(n.snap_near_fade_end, 1.5,
		"snap_near_fade_end default 1.5m — full wobble from here out to the far fade")
	n.free()


func test_ps1_warp_intensity_scales_jitter_and_affine() -> void:
	# The accessibility slider (Settings.ps1_warp_intensity, Options -> Accessibility) scales the warp via
	# this pure static mapping: 100% = the applier's base values, lower = less jitter + less texture-swim,
	# 0% = OFF. (80.0 / 1.0 below are arbitrary FIXTURE args to the pure static fn, not the shipped
	# defaults — those are pinned in test_ps1_applier_exported_defaults above.)
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
	# Bare instance: _ready duplicates the two scene-authored materials (null here) and
	# _on_attack_flash_muzzle reads the Settings / GameSettings autoloads and restarts the
	# emitter, so assert TYPE + surface only and never CALL either.
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


# --- star_sky.gd + horizon_sky.gdshader (the on-kill sky flash) ------------------

## SILENT-FAILURE GUARD for the on-kill sky pop. StarSky.flash_kill drives TWO uniforms on
## horizon_sky.gdshader: it TWEENS `flash` (0 -> peak -> hold -> 0) and it SETS `flash_color` from
## GameSettings.effects.sky_flash_color. Both writes are probed through StarSky._has_param first, so renaming
## or deleting either uniform in the .gdshader does not error anywhere — it just quietly stops the kill flash
## (no `flash`) or quietly reverts it to the shader's own hard-coded default (no `flash_color`), and nothing else in the
## project would ever notice. Headless runs NEVER compile a .gdshader either, so no smoke test can catch it.
## Hence a source-text pin on both uniform names. If this fails, either restore the names or update
## scripts/effects/star_sky.gd (flash_kill) to match — do not just delete the assertion.
func test_horizon_sky_declares_both_kill_flash_uniforms() -> void:
	var src := FileAccess.get_file_as_string("res://resources/shaders/horizon_sky.gdshader")
	assert_false(src.is_empty(),
		"horizon_sky.gdshader must be readable — StarSky preloads it as the runtime sky for every WorldEnvironment")
	assert_true(src.contains("uniform float flash "),
		"horizon_sky.gdshader must declare `uniform float flash` — StarSky.flash_kill tweens shader_parameter/flash, and its _has_param probe SKIPS the whole kill flash (warning once) when the uniform is gone")
	assert_true(src.contains("uniform vec3  flash_color"),
		"horizon_sky.gdshader must declare `uniform vec3 flash_color` — StarSky.flash_kill sets it from GameSettings.effects.sky_flash_color; without it the kill pop silently falls back to the shader's OWN hard-coded default instead of the designer's live colour")
	assert_true(src.contains("uniform float hurt_flash"),
		"horizon_sky.gdshader must declare `uniform float hurt_flash` — StarSky.flash_hurt tweens it on a SECOND channel so a hit can't cut a kill's flash short; without it taking damage silently stops washing the sky red")
	assert_true(src.contains("uniform vec3  hurt_flash_color"),
		"horizon_sky.gdshader must declare `uniform vec3 hurt_flash_color` — StarSky.flash_hurt sets it from GameSettings.effects.sky_hurt_color; without it the damage wash falls back to the shader's own red")

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

## SILENT-FAILURE GUARD for the kick under the kill flash, and the reason it is a source-text pin: no
## headless test can drive it. test_player_core.gd documents WHY — Player._enter_tree unconditionally
## dereferences a dozen child nodes and calls head.setup(), so a bare Player crashes the runner, and Player
## is never built in-tree in a unit suite. That leaves `screen_shake.shake(...)` inside on_scored_kill with
## NOTHING watching it: delete the line and every test still passes, the sky still flashes red, and the
## only symptom is a kill that no longer kicks — exactly the class of quiet regression the sibling sky-flash
## pin above exists for. So we pin the call site itself, sliced to on_scored_kill so a shake() somewhere
## else in the 3.5k-line file cannot satisfy it.
##
## If this fails, restore the call or update the slice — do not just delete the assertion.
func test_on_scored_kill_kicks_the_screen_shake() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/player/player.gd")
	assert_false(src.is_empty(),
		"player.gd must be readable — it owns on_scored_kill, the single seam every credited kill funnels through")
	var start := src.find("func on_scored_kill(")
	assert_true(start != -1,
		"player.gd must still declare `func on_scored_kill(` — Character.take_damage's lethal branch calls it duck-typed by NAME, so a rename silently stops every kill cue (flash AND kick) with no error anywhere")
	# Slice to the END of the function (the next top-level `func `) so a shake() call elsewhere in the file
	# — weapon fire, landing, the ram bounce — cannot stand in for this one.
	var next_func := src.find("\nfunc ", start + 1)
	var body := src.substr(start, next_func - start) if next_func != -1 else src.substr(start)
	assert_true(body.contains("screen_shake.shake(GameSettings.screen_shake.kill_shake_amount)"),
		"on_scored_kill must feed ScreenShake the kill kick — `screen_shake.shake(GameSettings.screen_shake.kill_shake_amount)`. Without it a kill still flashes the sky but the camera never answers, and nothing else in the project would notice")
	# shake(), NOT shake_explosion(): the latter raises the trauma ceiling to explosion_max_trauma so blasts can
	# out-shake everything else. A kill borrowing that ceiling would out-punch the grenade that scored it.
	assert_false(body.contains("shake_explosion("),
		"the kill kick must go through shake() and not shake_explosion() — shake_explosion raises the trauma ceiling to explosion_max_trauma, which is reserved for actual blasts")
	# The null guard is what keeps this safe off-tree / on a rig-less Player: `screen_shake` is resolved from the
	# head rig in _ready and is null before that (and in every test that builds a bare Player).
	assert_true(body.contains("if screen_shake:"),
		"the kill kick must be guarded by `if screen_shake:` — the handle is resolved from the head camera rig in _ready and is null on a bare/off-tree Player, where an unguarded call would crash the kill cue")


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
## SOURCE-TEXT pin rather than a behavioural one, and deliberately so: headless NEVER simulates GPU particles, so
## no in-process test can observe either half. The cheap, honest guard is that the authored scenes carry no script
## on the emitter at all — these are pure authored particle systems and their timing belongs to the engine.
func test_blood_emitters_carry_no_timing_script() -> void:
	for scene_path in ["res://scenes/effects/blood.tscn", "res://scenes/effects/bloody_mess.tscn"]:
		var src := FileAccess.get_file_as_string(scene_path)
		# An empty read (scene moved, or the editor is mid-reimport) would make both asserts below pass vacuously.
		assert_false(src.is_empty(),
			"%s must be readable as text — an empty read means the scene moved or is mid-reimport, and the two guards below would pass vacuously" % scene_path)
		assert_false(src.contains("particle_time_bind"),
			"%s must not carry particle_time_bind.gd. It multiplied speed_scale by Engine.time_scale on top of the frame step Godot has ALREADY scaled, so every bullet-time / hitstop slow-mo hit the burst twice — measured 23.9x slower instead of 5x at time_scale 0.2" % scene_path)
		# Also pinned as a whole, because a re-save can reduce an ext_resource to a bare `uid://` with no path in it,
		# and the name check above would then miss the very script it exists to catch.
		assert_false(src.contains("script = ExtResource"),
			"%s must carry NO script on its emitter — it is a pure authored GPUParticles3D and its speed_scale / process_mode belong to the engine and the Inspector. A script here is how the squared-slow-mo and pause-through bugs both got in" % scene_path)
