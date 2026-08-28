extends GutTest

## GUT tests for the "Camera / input / UI" subsystem. Each assert guards a
## load-bearing contract and its message says WHY that invariant matters, so this
## file doubles as executable documentation.
##
## COVERS:
##   ScreenShake (scripts/camera/screen_shake.gd)
##     - shake()/shake_explosion() trauma clamping, additivity, and the design
##       contract that the explosion ceiling exceeds the ordinary one.
##     - trauma decay via _process driven MANUALLY on a DETACHED .new() node
##       (mirrors how test_smoke drives BulletTime._process); decay clamps at 0.
##     - extends Node3D (the camera parents under it so its rotation shakes view).
##   MouseInput (scripts/components/mouse_input.gd)
##     - speed_sensitivity_multiplier() below-threshold == 1.0 and mid-range
##       monotonic falloff (the no-player==1.0 and at-max==sens_min cases are
##       ALREADY in test_smoke and are NOT duplicated here).
##     - rotate / attack signals exist (Head/body/GunMesh + attack.gd wire to them).
##     - SOURCE PIN: mouse look reads InputEventMouseMotion.screen_relative, never
##       `relative` (which the viewport stretch mode pre-scales by canvas/window
##       width, so look speed used to ride the window size).
##     All MouseInput instances are .new() WITHOUT add_child so _ready never runs
##     and the real cursor is never captured.
##   InputManager (managers/InputManager.gd, live autoload)
##     - every action-name constant (test_autoload_order only checks action_forward).
##     - get_movement_vector() returns Vector2.ZERO with no keys held (axis wiring).
##   FreezeFrame (scenes/player/freeze_frame.gd, live autoload)
##     - freeze() exists. The active time_scale path is NOT invoked (it writes
##       Engine.time_scale + awaits a real timer); the disabled no-op is already in
##       test_smoke.
##   CameraEffects (scripts/camera/camera_effects.gd)
##     - the scoped-FOV ownership latch is driven by set_scope_dof/reset_transients without running _process.
##   Hitmarker (scripts/ui/hitmarker.gd), DamageIndicators (scripts/ui/damage_indicators.gd),
##   UI (scripts/ui/ui.gd)
##     - exported defaults, base class, has_method, and the pure state mutators
##       (flash()/add()/_process()/setup()) driven on DETACHED .new() instances.
##
## DELIBERATELY SKIPPED (instantiation is unsafe / behaviour needs a full scene):
##   - CameraEffects._process/bob: those deref a null `player`; only a full Character + tree could exercise them.
##   - flash_light.gd / ray_cast.gd: @onready NodePaths resolve to
##     null on a bare tree and _ready/_process dereference them; ray_cast also does
##     real physics (direct_space_state, impulses, freeze/layer mutation). Their
##     invariants are already guarded by test_smoke's file-content tests.
##   - MouseInput._ready/_unhandled_input/_process: real cursor capture + viewport
##     camera derefs.
##   - FreezeFrame active time-scale path; ui._process (derefs hp/ammo Labels);
##     adding any of the above into a live tree.
##   - The already-covered cases listed inline above (no duplication).
##
## All asserts (assert_eq/_gt/_lt/_true/_false/_not_null/_almost_eq) and the
## has_method/has_signal Object builtins match the existing suite (test_smoke.gd).


# ---------------------------------------------------------------------------
# ScreenShake
# ---------------------------------------------------------------------------

func test_screen_shake_is_node3d() -> void:
	# .new() WITHOUT add_child: _process (which writes rotation every frame and
	# would shake a parented camera) must never run in a test.
	var s := ScreenShake.new()
	assert_true(s is Node3D,
		"ScreenShake must extend Node3D: the camera is parented under it, so rotating this node shakes the view")
	s.free()


func test_screen_shake_clamps_to_max_trauma() -> void:
	var s := ScreenShake.new()
	s.shake(2.0)
	assert_eq(s.trauma, ScreenShake.MAX_TRAUMA,
		"A single shake() must clamp trauma to MAX_TRAUMA (1.0) so one ordinary event can't overshoot the standard ceiling")
	s.free()


func test_screen_shake_is_additive() -> void:
	var s := ScreenShake.new()
	# Two ordinary events stack: 0.3 + 0.3 = 0.6, still under the 1.0 cap.
	s.shake(0.3)
	s.shake(0.3)
	assert_almost_eq(s.trauma, 0.6, 0.001,
		"shake() must add trauma (trauma = min(trauma + amount, cap)) so concurrent events stack instead of overwriting")
	s.free()


func test_screen_shake_explosion_uses_higher_ceiling() -> void:
	var s := ScreenShake.new()
	s.trauma = 0.0
	s.shake_explosion(99.0)
	assert_eq(s.trauma, GameSettings.screen_shake.explosion_max_trauma,
		"shake_explosion() must clamp to explosion_max_trauma (1.6), not MAX_TRAUMA, so blasts can shake harder than ordinary events")
	s.free()


func test_screen_shake_explosion_ceiling_exceeds_ordinary_ceiling() -> void:
	assert_gt(GameSettings.screen_shake.explosion_max_trauma, ScreenShake.MAX_TRAUMA,
		"The explosion ceiling (1.6) must exceed shake()'s ceiling (1.0): this encodes the design contract that explosions are allowed to exceed the ordinary cap")


func test_screen_shake_trauma_decays_on_process() -> void:
	# DETACHED node: _process is called by hand (never added to the tree). Its
	# rotation = randf_range(...) write is inert on an unparented Node3D — no scene.
	var s := ScreenShake.new()
	s.trauma = 1.0
	s._process(1.0)
	assert_lt(s.trauma, 1.0,
		"Trauma must decay each frame so the shake settles instead of persisting forever")
	var expected: float = max(1.0 - GameSettings.screen_shake.decay_rate * 1.0, 0.0)
	assert_almost_eq(s.trauma, expected, 0.001,
		"Decay must be linear at decay_rate (5.0): trauma = max(trauma - decay_rate*delta, 0)")
	s.free()


func test_screen_shake_trauma_decay_clamps_at_zero() -> void:
	var s := ScreenShake.new()
	s.trauma = 0.01
	s._process(10.0)
	assert_eq(s.trauma, 0.0,
		"Decay must clamp at 0.0: a negative trauma would invert the trauma² shake magnitude")
	s.free()


func test_screen_shake_reset_clears_respawn_state() -> void:
	var s := ScreenShake.new()
	s.trauma = 0.75
	s.rotation = Vector3(0.2, -0.3, 0.0)
	s.reset()
	assert_eq(s.trauma, 0.0,
		"ScreenShake.reset must clear trauma so death-adjacent shake cannot carry into the respawn")
	assert_eq(s.rotation, Vector3.ZERO,
		"ScreenShake.reset must restore the shake pivot rotation so the fresh life starts from a neutral camera")
	s.free()


# ---------------------------------------------------------------------------
# CameraEffects
# ---------------------------------------------------------------------------

func test_camera_effects_scope_fov_owner_latch() -> void:
	var cam := CameraEffects.new()
	assert_false(cam._scope_fov_active, "a fresh camera starts with CameraEffects owning ordinary feel FOV")
	cam.set_scope_dof(true, false)
	assert_true(cam._scope_fov_active, "scoping marks ScopeIn as the FOV owner so movement FOV does not fight ADS zoom")
	cam.reset_transients()
	assert_false(cam._scope_fov_active, "respawn/transient reset hands FOV ownership back to CameraEffects")
	cam.free()


func test_camera_effects_exit_tree_scrubs_scoped_far_dof_off_the_shared_attributes() -> void:
	# CameraAttributesPractical is a SHARED sub-resource of the cached camera_rig.tscn (not
	# resource_local_to_scene), so whatever a dying camera leaves on it is exactly what the NEXT camera's
	# _ready() snapshots as "authored". An F9 quickload mid-ADS frees the scene with the scoped far blur
	# (enabled @ dof_scoped_far_distance) still applied — _exit_tree must put the resting pair back, or
	# resting far blur comes back for the whole process (the one regression path of the 2026-08-24 far-DoF
	# retirement, when camera_rig.tscn stopped authoring far blur at rest).
	# No frame is processed between add_child and remove_child, so _process never runs against the null player.
	var cam := CameraEffects.new()
	var attrs := CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = false
	attrs.dof_blur_far_distance = 10.0
	cam.attributes = attrs
	add_child(cam)   # _ready() snapshots the resting pair off the live attributes
	attrs.dof_blur_far_enabled = true    # the scoped state a mid-ADS quickload leaves behind
	attrs.dof_blur_far_distance = 120.0
	remove_child(cam)
	assert_false(attrs.dof_blur_far_enabled,
		"CameraEffects._exit_tree must restore the resting far-blur enabled flag on the shared attributes — otherwise a quickload while aiming permanently re-enables resting far blur")
	assert_eq(attrs.dof_blur_far_distance, 10.0,
		"CameraEffects._exit_tree must restore the resting far-blur distance on the shared attributes")
	cam.free()


func test_camera_effects_reset_transients_restores_neutral_pose() -> void:
	var cam := CameraEffects.new()
	cam._origin = Vector3(0.1, 0.2, 0.3)
	cam._bob_offset = Vector3(0.4, 0.5, 0.6)
	cam._impact_offset = Vector3(0.7, 0.8, 0.9)
	cam._fov_punch = 12.0
	cam.dialogue_fov = 40.0
	cam._scope_fov_active = true
	cam.position = Vector3(9.0, 8.0, 7.0)
	cam.rotation.z = 0.5
	cam.fov = 35.0
	cam.reset_transients()
	assert_eq(cam._bob_offset, Vector3.ZERO,
		"CameraEffects.reset_transients must clear walk-bob so respawn does not ease out of a stale camera offset")
	assert_eq(cam._impact_offset, Vector3.ZERO,
		"CameraEffects.reset_transients must clear landing impact so respawn starts at the camera rest height")
	assert_eq(cam.position, cam._origin,
		"CameraEffects.reset_transients must snap local position back to the authored camera origin")
	assert_eq(cam.rotation.z, 0.0,
		"CameraEffects.reset_transients must clear strafe/death roll so respawn starts level")
	assert_eq(cam.fov, cam.base_fov,
		"CameraEffects.reset_transients must restore the default FOV immediately instead of easing back after respawn")
	assert_false(cam._scope_fov_active,
		"CameraEffects.reset_transients must hand FOV ownership back to CameraEffects after death/respawn")
	cam.free()


func test_camera_effects_layers_sprint_fov_with_other_cosmetic_fov() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/camera/camera_effects.gd")
	assert_true(src.contains("climber.is_sprinting()"),
		"CameraEffects must read Player.is_sprinting() so the sprint FOV follows the same gates as stamina sprint")
	assert_true(src.contains("GameSettings.camera.sprint_fov_mult"),
		"CameraEffects must add the designer-tuned sprint_fov_mult while sprinting")
	assert_true(src.contains("move_fov + sprint_fov + _fov_punch"),
		"Sprint FOV must layer with the existing movement and dash FOV terms instead of replacing them")
	assert_true(src.contains("clampf(composed_fov, 1.0, 179.0)"),
		"Composed movement FOV must stay inside Camera3D's valid perspective range")


## ⭐ REGRESSION (2026-08-20): moving the FOV slider mid-run left this camera resting at the OLD angle.
##
## `Settings.set_fov()` writes `GameSettings.camera.default_fov` and nothing else. `base_fov` used to be a plain
## field initialised from that value ONCE per camera instance, so after a mid-run change CameraEffects composed
## `_target_fov` against the stale number while ScopeIn's un-scoped branch eased the SAME `fov` property toward
## the fresh one — two writers, two targets, `fov` settling at neither until the level reloaded. `base_fov` is a
## getter now; this test fails if it is ever turned back into a stored field.
##
## The FIELD is written directly, never `Settings.set_fov()`: every Settings setter calls `save_settings()`, and
## a test that went through the setter would rewrite the developer's real user://settings.cfg.
func test_camera_base_fov_follows_a_mid_run_fov_change() -> void:
	var authored: float = GameSettings.camera.default_fov
	var cam := CameraEffects.new()
	assert_almost_eq(cam.base_fov, authored, 0.001,
		"CameraEffects.base_fov must start at the authored rest FOV")

	# The Options slider's effect, without its persistence: only GameSettings changes.
	var moved := authored + 25.0
	GameSettings.camera.default_fov = moved
	assert_almost_eq(cam.base_fov, moved, 0.001,
		"CameraEffects.base_fov must FOLLOW a mid-run GameSettings.camera.default_fov change — a cached copy leaves this camera composing against the old rest FOV while ScopeIn eases toward the new one")
	# The bug in one line: the two writers of `fov` must be aiming at the same number.
	assert_almost_eq(cam.base_fov, GameSettings.camera.default_fov, 0.001,
		"CameraEffects and ScopeIn must agree on the un-scoped rest FOV — ScopeIn eases toward GameSettings.camera.default_fov directly, so base_fov has to be the same value, not a snapshot of it")

	GameSettings.camera.default_fov = authored
	assert_almost_eq(cam.base_fov, authored, 0.001,
		"base_fov must track the restore too (GameSettings.camera is shared across tests — a leaked value would poison every later FOV assertion)")
	cam.free()


func test_scope_in_respects_dialogue_fov_owner() -> void:
	var cam := CameraEffects.new()
	var si := ScopeIn.new()
	var dialogue_fov := maxf(1.0, GameSettings.camera.default_fov - 10.0)
	cam.fov = dialogue_fov
	cam.dialogue_fov = dialogue_fov
	si.camera = cam
	si._process(1.0)
	assert_almost_eq(cam.fov, dialogue_fov, 0.001,
		"ScopeIn must not ease camera.fov back toward default while DialogueController owns dialogue_fov")
	si.free()
	cam.free()


func test_scope_in_clamps_scoped_fov_to_camera_range() -> void:
	var old_scoped_fov := GameSettings.camera.scoped_fov
	var old_scope_zoom_speed := GameSettings.camera.scope_zoom_speed
	var old_magnification := GameSettings.camera.scope_magnification
	var cam := Camera3D.new()
	var si := ScopeIn.new()
	cam.fov = 75.0
	si.camera = cam
	si.is_scoped = true
	# Magnification 0 selects the ABSOLUTE scoped_fov path — the only one a raw angle this small can reach,
	# since the magnification path solves its target from default_fov and can never land below ~1 degree.
	GameSettings.camera.scope_magnification = 0.0
	GameSettings.camera.scoped_fov = 0.01
	GameSettings.camera.scope_zoom_speed = 999.0
	Input.action_press("Zoom")
	si._process(1.0)
	var actual_fov := cam.fov
	Input.action_release("Zoom")
	GameSettings.camera.scoped_fov = old_scoped_fov
	GameSettings.camera.scope_zoom_speed = old_scope_zoom_speed
	GameSettings.camera.scope_magnification = old_magnification
	assert_almost_eq(actual_fov, 1.0, 0.001,
		"ScopeIn must clamp scoped FOV targets to Camera3D's valid range so tiny weapon/global zoom values do not trip set_fov()")
	si.free()
	cam.free()


## The ADS zoom must be a property of the WEAPON, not of the player's Field of View slider.
##
## Regression pinned: the scoped FOV used to be one absolute angle (40), so widening the FOV setting silently
## strengthened ADS — 75 -> 40 is a 2.1x jump, but 110 -> 40 is 3.9x, which reads in play as "the zoom is way
## too far in". Solving the scoped FOV from the rest FOV holds the magnification constant instead.
func test_scope_magnification_is_invariant_under_the_fov_setting() -> void:
	var cam_settings := GameSettings.camera
	var old_default := cam_settings.default_fov
	var old_magnification := cam_settings.scope_magnification
	var si := ScopeIn.new()
	cam_settings.scope_magnification = 2.108
	cam_settings.default_fov = 75.0
	var narrow_rest_scoped := si.global_scoped_fov()
	cam_settings.default_fov = 110.0
	var wide_rest_scoped := si.global_scoped_fov()
	cam_settings.default_fov = old_default
	cam_settings.scope_magnification = old_magnification
	si.free()
	assert_almost_eq(narrow_rest_scoped, 40.0, 0.01,
		"the default scope_magnification must reproduce the authored 75 -> 40 ADS feel, so this change is not a re-tune")
	assert_gt(wide_rest_scoped, narrow_rest_scoped,
		"a wider rest FOV must solve to a WIDER scoped FOV — pinning both to the same absolute angle is the bug")
	assert_almost_eq(_apparent_magnification(110.0, wide_rest_scoped), _apparent_magnification(75.0, narrow_rest_scoped), 0.001,
		"ADS magnification must be identical at 75 and 110 rest FOV — zoom strength cannot ride the player's FOV setting")


func test_scope_magnification_zero_restores_the_absolute_scoped_fov() -> void:
	var cam_settings := GameSettings.camera
	var old_magnification := cam_settings.scope_magnification
	var si := ScopeIn.new()
	cam_settings.scope_magnification = 0.0
	var scoped := si.global_scoped_fov()
	cam_settings.scope_magnification = old_magnification
	si.free()
	assert_almost_eq(scoped, cam_settings.scoped_fov, 0.001,
		"scope_magnification 0 is the documented sentinel for the legacy absolute scoped_fov, so a designer can opt back out")


## On-screen magnification between two FOVs. A TANGENT ratio, not a ratio of degrees: apparent size goes with
## tan(fov/2), which is exactly why `default_fov / magnification` would be the wrong formula in ScopeIn.
func _apparent_magnification(rest_fov: float, scoped_fov: float) -> float:
	return tan(deg_to_rad(rest_fov) * 0.5) / tan(deg_to_rad(scoped_fov) * 0.5)


# ---------------------------------------------------------------------------
# Mouse-wheel scope zoom (variable-zoom optics — the sniper)
# ---------------------------------------------------------------------------

func test_variable_scope_zoom_requires_a_usable_range() -> void:
	var w := WeaponData.new()
	assert_false(w.has_variable_scope_zoom(),
		"an unconfigured weapon (0/0) must not claim the wheel — every existing weapon keeps weapon switching through its scope")
	w.scoped_zoom_fov_min = 1.0
	w.scoped_zoom_fov_max = 20.0
	assert_true(w.has_variable_scope_zoom(),
		"authoring 0 < min < max is the documented on-switch for the wheel zoom")
	w.scoped_zoom_fov_max = 1.0
	assert_false(w.has_variable_scope_zoom(),
		"a degenerate range (min >= max) must read as a fixed optic, not a zero-width zoom the wheel fights over")
	w = null


func test_wheel_zoom_seeds_from_the_authored_scope_and_steps_as_a_tangent_ratio() -> void:
	var old_step := GameSettings.camera.scope_zoom_wheel_step
	GameSettings.camera.scope_zoom_wheel_step = 1.25
	var si := ScopeIn.new()
	var w := WeaponData.new()
	w.scoped_fov_override = 0.01  # the sniper's authoring — clamps to Camera3D's 1-degree floor
	w.scoped_zoom_fov_min = 1.0
	w.scoped_zoom_fov_max = 20.0
	assert_almost_eq(si.current_wheel_zoom_fov(w), 1.0, 0.001,
		"the wheel zoom must SEED from the weapon's authored resting zoom (override clamped into range) — scope-in lands exactly on the pre-feature look, the wheel is opt-in from there")
	si.step_wheel_zoom(w, -1)  # one notch OUT
	var widened: float = si.current_wheel_zoom_fov(w)
	assert_gt(widened, 1.0, "wheel down must WIDEN the scope FOV (zoom out)")
	assert_almost_eq(_apparent_magnification(widened, 1.0), 1.25, 0.001,
		"a notch must step the MAGNIFICATION by scope_zoom_wheel_step — a tangent ratio, not degrees (halving an angle does not double apparent size)")
	si.step_wheel_zoom(w, 1)  # and back in
	assert_almost_eq(si.current_wheel_zoom_fov(w), 1.0, 0.001,
		"a notch in must exactly undo a notch out — the step is symmetric on the tangent")
	# The tangent-vs-degrees distinction is INVISIBLE at the 1-degree end (tan is linear there to ~1e-5, so
	# `fov *= step` lands inside any sane tolerance) — so the discriminating assert runs from a WIDE seed,
	# where a degrees-multiplicative step (20 -> 25, magnification 1.2573) misses the tangent's 24.86.
	var wide := WeaponData.new()
	wide.scoped_fov_override = 20.0
	wide.scoped_zoom_fov_min = 1.0
	wide.scoped_zoom_fov_max = 90.0
	si.step_wheel_zoom(wide, -1)
	assert_almost_eq(_apparent_magnification(si.current_wheel_zoom_fov(wide), 20.0), 1.25, 0.001,
		"one notch from a WIDE 20-degree seed must change apparent magnification by exactly the step — this is the point where a degrees-stepping rewrite (fov *= step) actually diverges from the tangent contract and must fail")
	GameSettings.camera.scope_zoom_wheel_step = old_step
	si.free()
	w = null
	wide = null


func test_wheel_zoom_clamps_to_the_authored_range_and_remembers_per_weapon() -> void:
	var old_step := GameSettings.camera.scope_zoom_wheel_step
	GameSettings.camera.scope_zoom_wheel_step = 100.0  # one notch slams into the range ends
	var si := ScopeIn.new()
	var w := WeaponData.new()
	w.scoped_fov_override = 5.0
	w.scoped_zoom_fov_min = 1.0
	w.scoped_zoom_fov_max = 20.0
	si.step_wheel_zoom(w, -1)
	assert_almost_eq(si.current_wheel_zoom_fov(w), 20.0, 0.001,
		"zooming out must stop at scoped_zoom_fov_max — the authored range is the wheel's whole travel")
	si.step_wheel_zoom(w, 1)
	si.step_wheel_zoom(w, 1)
	assert_almost_eq(si.current_wheel_zoom_fov(w), 1.0, 0.001,
		"zooming in must stop at scoped_zoom_fov_min no matter how many notches pile up")
	var other := WeaponData.new()
	other.scoped_fov_override = 8.0
	other.scoped_zoom_fov_min = 2.0
	other.scoped_zoom_fov_max = 30.0
	assert_almost_eq(si.current_wheel_zoom_fov(other), 8.0, 0.001,
		"each weapon's wheel zoom is remembered SEPARATELY (keyed by its WeaponData) — dialing the sniper must not move another scope")
	# The RANGE half of the seed clamp, at a point where it differs from Camera3D's 1..179 clamp: an
	# override authored OUTSIDE the zoom range must seed at the range end, not ease to an out-of-range FOV
	# that the first notch would then snap back from.
	var outside := WeaponData.new()
	outside.scoped_fov_override = 30.0
	outside.scoped_zoom_fov_min = 1.0
	outside.scoped_zoom_fov_max = 20.0
	assert_almost_eq(si.current_wheel_zoom_fov(outside), 20.0, 0.001,
		"a scoped_fov_override outside the authored zoom range must seed CLAMPED INTO the range — the camera clamp alone (1..179) would pass 30 straight through")
	# The documented global off-switch must also make a notch a NO-OP, not just refuse ownership.
	GameSettings.camera.scope_zoom_wheel_step = 1.0
	si.step_wheel_zoom(w, -1)
	assert_almost_eq(si.current_wheel_zoom_fov(w), 1.0, 0.001,
		"with scope_zoom_wheel_step at 1.0 (wheel zoom off) a notch must not move the dial — and a sub-1 step must never invert the zoom direction")
	GameSettings.camera.scope_zoom_wheel_step = old_step
	si.free()
	w = null
	other = null
	outside = null


func test_scoped_target_fov_prefers_the_wheel_zoom_over_the_fixed_override() -> void:
	var old_step := GameSettings.camera.scope_zoom_wheel_step
	GameSettings.camera.scope_zoom_wheel_step = 2.0
	var si := ScopeIn.new()
	var w := WeaponData.new()
	w.scoped_fov_override = 5.0
	assert_almost_eq(si.scoped_target_fov(w), 5.0, 0.001,
		"a fixed optic (no zoom range) must keep easing to its absolute scoped_fov_override — pre-feature ADS is untouched")
	w.scoped_zoom_fov_min = 1.0
	w.scoped_zoom_fov_max = 20.0
	si.step_wheel_zoom(w, -1)
	assert_gt(si.scoped_target_fov(w), 5.0,
		"with a range authored, the scoped target must be the wheel-dialed zoom, not the frozen override")
	assert_almost_eq(si.scoped_target_fov(null), si.global_scoped_fov(), 0.001,
		"no weapon must still fall through to the global magnification solve — bare ADS keeps working")
	GameSettings.camera.scope_zoom_wheel_step = old_step
	si.free()
	w = null


func test_wheel_owns_scope_zoom_grants_an_aimed_variable_scope_then_refuses_each_gate() -> void:
	# The POSITIVE pin comes first and is load-bearing: without it every refusal below is vacuous — the
	# predicate's final Zoom-held conjunct is false in a bare GUT run, so an always-false predicate (typo'd
	# action, inverted gate) would pass pure-refusal asserts while shipping the feature dead. Zoom is held
	# via Input.action_press, the same off-tree idiom the scoped-FOV clamp test above already uses, and
	# each refusal then flips EXACTLY ONE gate off the granted baseline so it discriminates that gate.
	# Attack.new() bare is the established off-tree idiom (no add_child, so _ready never runs).
	var old_step := GameSettings.camera.scope_zoom_wheel_step
	GameSettings.camera.scope_zoom_wheel_step = 1.25
	var atk := Attack.new()
	var w := WeaponData.new()
	w.scoped_zoom_fov_min = 1.0
	w.scoped_zoom_fov_max = 20.0
	atk.current_weapon = w
	atk.holstered = false
	Input.action_press("Zoom")
	assert_true(ScopeIn.wheel_owns_scope_zoom(atk),
		"an AIMED (Zoom held, un-holstered) variable scope must OWN the wheel — this is the whole feature; the refusals below only mean something against this granted baseline")
	atk.holstered = true
	assert_false(ScopeIn.wheel_owns_scope_zoom(atk),
		"a holstered variable scope must not eat the wheel — you scroll OFF a put-away sniper like any gun")
	atk.holstered = false
	var fixed := WeaponData.new()
	fixed.scoped_fov_override = 5.0
	atk.current_weapon = fixed
	assert_false(ScopeIn.wheel_owns_scope_zoom(atk),
		"a FIXED optic must never claim the wheel — only an authored scoped_zoom_fov_min/max range does")
	atk.current_weapon = null
	assert_false(ScopeIn.wheel_owns_scope_zoom(atk),
		"no weapon drawn must leave the wheel with the hotbar")
	atk.current_weapon = w
	GameSettings.camera.scope_zoom_wheel_step = 1.0
	assert_false(ScopeIn.wheel_owns_scope_zoom(atk),
		"scope_zoom_wheel_step <= 1.0 is the documented global off-switch — it must hand the wheel back to weapon switching even through an aimed variable scope")
	GameSettings.camera.scope_zoom_wheel_step = 1.25
	Input.action_release("Zoom")
	assert_false(ScopeIn.wheel_owns_scope_zoom(atk),
		"Zoom released must return the wheel to weapon switching — the hip wheel always cycles")
	assert_false(ScopeIn.wheel_owns_scope_zoom(null),
		"no Attack at all (a bare rig) must leave the wheel with the hotbar")
	GameSettings.camera.scope_zoom_wheel_step = old_step
	atk.free()
	w = null
	fixed = null


func test_sniper_authors_a_wheel_zoom_range_that_preserves_its_resting_look() -> void:
	var sniper: WeaponData = load("res://resources/weapons/sniper_wep.tres")
	assert_true(sniper.has_variable_scope_zoom(),
		"the sniper is THE variable-zoom scope — its .tres must author the wheel range (scoped_zoom_fov_min/max)")
	var si := ScopeIn.new()
	var seeded: float = si.current_wheel_zoom_fov(sniper)
	si.free()
	assert_almost_eq(seeded, clampf(sniper.scoped_fov_override, 1.0, 179.0), 0.001,
		"the wheel seed must equal the sniper's pre-feature scoped look (its override under Camera3D's clamp) — adding the wheel must not move the authored scope-in")


func test_hotbar_wheel_branch_yields_through_the_shared_scope_predicate() -> void:
	# SOURCE PIN (the file-established idiom for wiring a bare test can't drive): the Hotbar's wheel branch
	# must consult _scope_owns_wheel beside _spray_owns_wheel, and that yield must route through the SAME
	# ScopeIn.wheel_owns_scope_zoom the scope consumes notches with — delete either and every behavioural
	# test here stays green while the bar fights the scope for each notch (weapon switches mid-ADS).
	var src := FileAccess.get_file_as_string("res://scripts/ui/hotbar.gd")
	assert_string_contains(src, "not _spray_owns_wheel() and not _scope_owns_wheel(")
	assert_string_contains(src, "ScopeIn.wheel_owns_scope_zoom")


# ---------------------------------------------------------------------------
# MouseInput  (always .new() WITHOUT add_child so _ready never captures the cursor)
# ---------------------------------------------------------------------------

func test_mouse_input_sensitivity_below_threshold_is_full() -> void:
	# No add_child -> _ready's Input.mouse_mode = MOUSE_MODE_CAPTURED never fires.
	var mi := MouseInput.new()
	var p := CharacterBody3D.new()
	# Speed below sens_reduction_threshold (6.5): the falloff must not kick in yet.
	p.velocity = Vector3(GameSettings.bunnyhop.sens_reduction_threshold * 0.5, 0.0, 0.0)
	mi.player = p
	assert_almost_eq(mi.speed_sensitivity_multiplier(), 1.0, 0.001,
		"Below the speed threshold, look sensitivity must stay at 1.0 — the falloff only kicks in past the threshold, so slow movement keeps full aim control")
	mi.free()
	p.free()


func test_mouse_input_sensitivity_midrange_is_between_min_and_full() -> void:
	var mi := MouseInput.new()
	var p := CharacterBody3D.new()
	# Speed at the midpoint between threshold and max_speed -> t in (0,1).
	var mid: float = (GameSettings.bunnyhop.sens_reduction_threshold + GameSettings.bunnyhop.max_speed) * 0.5
	p.velocity = Vector3(mid, 0.0, 0.0)
	mi.player = p
	var m := mi.speed_sensitivity_multiplier()
	assert_lt(m, 1.0,
		"At mid speed the multiplier must be below 1.0: sensitivity scales smoothly down as horizontal speed rises")
	assert_gt(m, GameSettings.bunnyhop.sens_min_multiplier,
		"At mid speed the multiplier must stay above sens_min_multiplier (0.5): the floor is only reached at max bhop speed, so the falloff is gradual, not a jump")
	mi.free()
	p.free()


func test_mouse_input_exposes_rotate_and_attack_signals() -> void:
	var mi := MouseInput.new()
	assert_true(mi.has_signal("rotate"),
		"MouseInput must declare the 'rotate' signal: Head (pitch), the Player body (yaw) and GunMesh (sway) all connect to this exact name — a rename silently breaks aiming")
	assert_true(mi.has_signal("attack"),
		"MouseInput must declare the 'attack' signal: attack.gd wires firing to this exact name — a rename silently breaks shooting")
	mi.free()


## Mouse look must read InputEventMouseMotion.screen_relative (raw OS pixels), NEVER `relative`. project.godot runs the
## 396x216 viewport at stretch mode "viewport" / scale 0.5 (a 792 px canvas), and under that mode the engine basis-
## transforms `relative` by canvas/window width before _unhandled_input sees it: 792/1920 = 0.41 in 1080p fullscreen,
## 792/1600 = 0.50 in the 1600x900 window, 792/1280 = 0.62 at 720p, 792/3840 = 0.21 at 4K. So the same hand motion
## turned the view 1.2-1.5x further the moment the game went WINDOWED and half as far on a 4K screen (the sensitivity
## default was tuned against 1080p fullscreen). screen_relative is unscaled, so one sensitivity means one thing
## everywhere; GameSettings.camera.mouse_sensitivity + Settings.SENS_MIN/MAX moved to that unit (x 792/1920) and a
## legacy settings.cfg is migrated by Settings.read_mouse_sensitivity — tests/test_settings.gd pins those. Source-text
## pin (the handler needs a captured cursor + a live viewport, so it is never driven under GUT); comment lines are
## masked so this prose can name the forbidden read.
func test_mouse_input_reads_screen_relative_not_relative() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/components/mouse_input.gd")
	var code_lines: Array[String] = []
	for line in src.split("\n"):
		var body: String = line.get_slice("#", 0)  # drop trailing comments; a whole-line comment leaves only indent
		if not body.strip_edges().is_empty():
			code_lines.append(body)
	var code := "\n".join(code_lines)
	assert_true(code.contains("mm.screen_relative.x") and code.contains("mm.screen_relative.y"),
		"MouseInput._unhandled_input must turn BOTH look axes from screen_relative (unscaled OS pixels) so look speed is window/resolution independent")
	assert_false(code.contains(".relative"),
		"MouseInput must not read InputEventMouseMotion.relative anywhere — the viewport stretch mode pre-scales it by canvas/window width, so mouse look would ride the window size again (1.5x faster in a 720p window, 0.5x at 4K)")


# ---------------------------------------------------------------------------
# InputManager (live autoload — action-name strings must mirror project.godot's InputMap)
# ---------------------------------------------------------------------------

func test_input_manager_action_name_constants() -> void:
	assert_eq(InputManager.action_forward, &"forward",
		"action_forward must be 'forward' to match the InputMap; drift breaks forward movement with no error")
	assert_eq(InputManager.action_backward, &"backward",
		"action_backward must be 'backward' to match the InputMap")
	assert_eq(InputManager.action_left, &"left",
		"action_left must be 'left' to match the InputMap")
	assert_eq(InputManager.action_right, &"right",
		"action_right must be 'right' to match the InputMap")
	assert_eq(InputManager.action_jump, &"jump",
		"action_jump must be 'jump' to match the InputMap")
	assert_eq(InputManager.action_crouch, &"Crouch",
		"action_crouch must be 'Crouch' (capitalised) to match the InputMap")
	assert_eq(InputManager.action_attack, &"Attack",
		"action_attack must be 'Attack' to match the InputMap (MouseInput._process reads this exact name)")
	assert_eq(InputManager.action_reload, &"Reload",
		"action_reload must be 'Reload' to match the InputMap")
	assert_eq(InputManager.action_zoom, &"Zoom",
		"action_zoom must be 'Zoom' to match the InputMap")
	assert_eq(InputManager.action_pickup, &"PickUp",
		"action_pickup must be 'PickUp' to match the InputMap")
	assert_eq(InputManager.action_light, &"Light",
		"action_light must be 'Light' to match the InputMap")
	assert_eq(InputManager.action_grapple, &"Grapple",
		"action_grapple must be 'Grapple' to match the InputMap")
	assert_eq(InputManager.action_weapon_slot_1, &"Weapon Slot 1",
		"action_weapon_slot_1 must be 'Weapon Slot 1' to match the InputMap")
	assert_eq(InputManager.action_weapon_slot_2, &"Weapon Slot 2",
		"action_weapon_slot_2 must be 'Weapon Slot 2' to match the InputMap")
	assert_eq(InputManager.action_weapon_slot_3, &"Weapon Slot 3",
		"action_weapon_slot_3 must be 'Weapon Slot 3' to match the InputMap")
	assert_eq(InputManager.action_weapon_slot_4, &"Weapon Slot 4",
		"action_weapon_slot_4 must be 'Weapon Slot 4' to match the InputMap")
	assert_eq(InputManager.action_weapon_slot_5, &"Weapon Slot 5",
		"action_weapon_slot_5 must be 'Weapon Slot 5' to match the InputMap")
	assert_eq(InputManager.action_weapon_slot_6, &"Weapon Slot 6",
		"action_weapon_slot_6 must be 'Weapon Slot 6' to match the InputMap")


func test_input_manager_movement_vector_zero_with_no_input() -> void:
	# Read-only Input query; in a headless GUT run no keys are held.
	var v := InputManager.get_movement_vector()
	assert_eq(v, Vector2.ZERO,
		"get_movement_vector() must return ZERO with no keys held; this also pins the get_vector arg order (left,right,forward,backward) — a swapped pair would invert strafing")


# ---------------------------------------------------------------------------
# FreezeFrame (live autoload — assert existence only; invoking the active path
# writes Engine.time_scale and awaits a real timer)
# ---------------------------------------------------------------------------

func test_freeze_frame_exposes_freeze() -> void:
	assert_true(FreezeFrame.has_method("freeze"),
		"FreezeFrame must expose freeze(): enemy hit/death hitstop calls FreezeFrame.freeze(...) by name (asserting existence does not invoke the time_scale write)")


# ---------------------------------------------------------------------------
# Hitmarker  (.new() WITHOUT add_child; _draw never runs on a non-displayed Control)
# ---------------------------------------------------------------------------

func test_hitmarker_is_control_with_flash() -> void:
	var h = load("res://scripts/ui/hitmarker.gd").new()
	assert_true(h is Control,
		"Hitmarker must extend Control: it draws as a HUD overlay")
	assert_true(h.has_method("flash"),
		"Hitmarker must expose flash(): the owner calls it on every confirmed hit")
	h.free()


func test_hitmarker_skin_defaults() -> void:
	# Hitmarker's look moved onto MenuStyle.hud (HudSkin) — it is code-built, so the skin IS its
	# authoring surface. Pin the load-bearing values there instead of the removed @exports.
	var hud = MenuStyle.hud
	assert_eq(hud.hitmarker_duration, 0.25,
		"hitmarker_duration default (0.25s) is the fade window the HUD juice tuning relies on")
	assert_gt(hud.hitmarker_tick_length, 0.0,
		"hitmarker_tick_length must be positive so the confirm ticks are visible")
	assert_gt(hud.hitmarker_thickness, 0.0,
		"hitmarker_thickness must be positive so the ticks render")
	assert_gt(hud.hitmarker_headshot_scale, 1.0,
		"hitmarker_headshot_scale must exceed 1.0 — the load-bearing 'head hits read bigger' invariant")


func test_hitmarker_flash_arms_timer_and_records_headshot() -> void:
	# flash() only sets _t/_headshot + queue_redraw (a no-op off-screen). No _draw.
	var h := Hitmarker.new()
	h.flash(true)
	assert_almost_eq(h._t, MenuStyle.hud.hitmarker_duration, 0.001,
		"flash() must arm the fade timer _t from the SKIN's hitmarker_duration (the wiring seam) so the marker pops at full strength")
	assert_true(h._headshot,
		"flash(true) must record the headshot flag that _draw uses to pick the bigger headshot colour/scale")
	h.flash(false)
	assert_false(h._headshot,
		"flash(false) must clear the headshot flag so an ordinary hit draws in the normal colour/scale")
	h.free()


# ---------------------------------------------------------------------------
# DamageIndicators  (.new() WITHOUT add_child; _process/_draw never touch camera here)
# ---------------------------------------------------------------------------

func test_damage_indicators_is_control_with_add() -> void:
	var di = load("res://scripts/ui/damage_indicators.gd").new()
	assert_true(di is Control,
		"DamageIndicators must extend Control: it draws as a HUD overlay")
	assert_true(di.has_method("add"),
		"DamageIndicators must expose add(): the Player records hit world-positions through it")
	di.free()


func test_damage_indicators_skin_defaults() -> void:
	# DamageIndicators' look moved onto MenuStyle.hud (HudSkin) — code-built, so the skin IS its
	# authoring surface. Pin the load-bearing values there instead of the removed @exports.
	var hud = MenuStyle.hud
	assert_eq(hud.damage_arc_duration, 1.0,
		"damage_arc_duration default (1.0s) is the arc lifetime the directional-damage cue relies on")
	assert_gt(hud.damage_arc_radius, 0.0,
		"damage_arc_radius must be positive so the arc sits off the crosshair centre")
	assert_gt(hud.damage_arc_degrees, 0.0,
		"damage_arc_degrees must be positive so each wedge has angular width")
	assert_gt(hud.damage_arc_thickness, 0.0,
		"damage_arc_thickness must be positive so the arc renders")


func test_damage_indicators_add_records_hit_at_full_lifetime() -> void:
	# add() only appends to _hits + queue_redraw — no camera deref.
	var di := DamageIndicators.new()
	di.add(Vector3(1, 2, 3))
	assert_eq(di._hits.size(), 1,
		"add() must record one entry so the overlay has a source to draw")
	assert_almost_eq(di._hits[0]["t"], MenuStyle.hud.damage_arc_duration, 0.001,
		"A new hit must start at full lifetime (t == the SKIN's damage_arc_duration — the wiring seam) so its arc begins at full opacity")
	assert_eq(di._hits[0]["pos"], Vector3(1, 2, 3),
		"add() must store the source world position so the bearing can be recomputed live as the player turns")
	di.free()


func test_damage_indicators_process_ages_and_culls() -> void:
	# _process only decrements t, removes expired, queue_redraw — it never derefs camera.
	var di := DamageIndicators.new()
	di.add(Vector3(1, 0, 0))
	di._process(MenuStyle.hud.damage_arc_duration + 0.1)
	assert_eq(di._hits.size(), 0,
		"_process must remove expired hits so the overlay clears once an indicator's time runs out")
	di.free()


func test_combat_indicators_dropped_shadowed_look_exports() -> void:
	# The code-built combat indicators (Hitmarker / DamageIndicators / AimIndicators / SniperGlints)
	# read their look from MenuStyle.hud. Their old per-node look @exports were REMOVED, not kept as
	# fallbacks — a surviving one would be a shadowed default an artist could edit with no effect.
	# (SniperGlints keeps min_distance / expiry_ms: functional gates, deliberately not skinned.)
	var checks := {
		"res://scripts/ui/hitmarker.gd": ["duration", "tick_length", "gap", "color", "headshot_color"],
		"res://scripts/ui/damage_indicators.gd": ["duration", "radius", "arc_degrees", "thickness", "color"],
		"res://scripts/ui/aim_indicators.gd": ["base_radius", "damage_to_pixels", "max_radius", "color"],
		"res://scripts/ui/sniper_glints.gd": ["core_radius", "streak_length", "color"],
	}
	for path in checks:
		var inst = load(path).new()
		for prop in checks[path]:
			assert_false(prop in inst,
				"%s must not keep dead look knob '%s' — it lives on MenuStyle.hud now" % [path, prop])
		inst.free()


# --- The stale-paint contract shared by AimIndicators + SniperGlints -------------------------------
# A CanvasItem repaints ONLY when queue_redraw() is called — never automatically per frame. Both widgets
# drop an entry from report() when the enemy loses the shot (charge <= 0), and both _process() bodies
# early-return once their dict is empty. Miss the queue_redraw on those two paths and the LAST painted
# frame stays on screen forever: an enemy you walk out of range of reports charge 0 every frame from then
# on (npc.gd caps _fire_timer at the shot interval, so the charge pins to 0), leaving _process nothing to
# expire — the red arc froze at its pre-shot peak, bright and near max radius. These run IN-TREE with a
# stand-in camera so the real paint/clear cycle is exercised, not just the dict bookkeeping.

func _drawn_aim_indicators() -> AimIndicators:
	var ind := AimIndicators.new()
	add_child_autofree(ind)
	ind.size = Vector2(792, 444)  # the UI canvas size; _draw takes its centre from this
	var cam := Node3D.new()       # a bare Node3D is all AimIndicators reads (basis + global_position)
	add_child_autofree(cam)
	ind.camera = cam
	return ind


func test_aim_indicators_clears_the_arc_when_the_aim_drops() -> void:
	# THE bug this pins: walk out of a ranged enemy's range and the red "being aimed at" arc stuck on
	# screen. report(charge 0) erased the entry but queued no redraw, and _process then early-returned on
	# the empty dict — so nothing ever repainted the (already-drawn) arc away.
	var ind := _drawn_aim_indicators()
	var src := Node.new()
	add_child_autofree(src)
	ind.report(src, Vector3(0, 0, -5), 0.9, 4.0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(ind._painted,
		"A live aim report must actually PAINT an arc — otherwise this test can't tell a clear from a no-op")
	ind.report(src, Vector3(0, 0, -5), 0.0, 4.0)  # enemy lost the shot: out of range / LOS broken / dry
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(ind._painted,
		"Dropping the last aim must queue the redraw that CLEARS the arc: a CanvasItem repaints only on queue_redraw, so without one the arc stays frozen on screen forever")
	assert_eq(ind._aims.size(), 0,
		"report(charge 0) must also drop the entry itself, so no later frame can resurrect the arc")


func test_aim_indicators_empty_process_still_clears_a_stale_paint() -> void:
	# Belt-and-suspenders half of the fix: whatever empties _aims/_pings, the FIRST _process afterwards
	# must clear a canvas that still holds paint, instead of early-returning and stranding it.
	var ind := _drawn_aim_indicators()
	var src := Node.new()
	add_child_autofree(src)
	ind.report(src, Vector3(0, 0, -5), 0.9, 4.0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(ind._painted, "precondition: an arc is on the canvas")
	ind._aims.clear()  # emptied WITHOUT going through report() — the path report()'s own fix can't cover
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(ind._painted,
		"_process must queue one clearing redraw when the dicts are empty but the canvas still holds an arc")


func test_sniper_glints_clear_when_the_shot_is_lost() -> void:
	# SniperGlints.report() carries the identical erase-without-redraw shape and the identical empty
	# early-return, fed by the SAME player_hud call — so a lost clear shot could strand a flare too.
	var g := SniperGlints.new()
	add_child_autofree(g)
	g.size = Vector2(792, 444)
	var cam := Camera3D.new()  # SniperGlints needs a REAL Camera3D: it unprojects the world position
	add_child_autofree(cam)
	g.camera = cam
	var src := Node.new()
	add_child_autofree(src)
	g.report(src, Vector3(0, 0, -40), 0.8)  # beyond min_distance (18 m), in front of the camera
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(g._painted, "a live glint report must paint a flare")
	g.report(src, Vector3(0, 0, -40), 0.0)  # the player feeds 0 the instant the clear shot is lost
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(g._painted,
		"Losing the clear shot must queue the redraw that CLEARS the flare, not just erase the dict entry")


# ---------------------------------------------------------------------------
# UI (HUD)  (.new() WITHOUT add_child; ui._process derefs hp/ammo Labels)
# ---------------------------------------------------------------------------

func test_ui_is_canvaslayer_with_setup() -> void:
	var u = load("res://scripts/ui/ui.gd").new()
	assert_true(u is CanvasLayer,
		"UI must extend CanvasLayer: it is the HUD layer drawn over the 3D view")
	assert_true(u.has_method("setup"),
		"UI must expose setup(): it is the dependency-injection entry the host calls")
	u.free()


func test_ui_setup_assigns_refs_without_requiring_labels() -> void:
	# setup() performs only two assignments and no deref, so null args are safe.
	var u = load("res://scripts/ui/ui.gd").new()
	u.setup(null, null)
	assert_eq(u.player, null,
		"setup() must assign the player ref directly (no deref) so the HUD can be wired before the player exists")
	assert_eq(u.ammo_count, null,
		"setup() must assign the ammo ref directly (no deref) so it doesn't require the Ammo node to be present at injection time")
	u.free()


func test_ui_set_scoped_is_null_safe() -> void:
	# On a bare .new() the engine never calls _ready, so crosshair stays null. set_scoped's
	# `if crosshair:` guard must make these calls safe no-ops (the scope bridge can fire before
	# the HUD's _ready has built the dot). Mirrors the detached-instance pattern above.
	var u = load("res://scripts/ui/ui.gd").new()
	assert_true(u.has_method("set_scoped"),
		"UI must expose set_scoped(): player._on_scoped_in calls it to show/hide the ADS reticle")
	u.set_scoped(true)
	u.set_scoped(false)
	assert_eq(u.crosshair, null,
		"crosshair stays null until _ready builds it; set_scoped must not create it or deref a null on a bare instance")
	u.free()


# UI HUD readouts: hp_segment_fill / _ammo_text are pure (no _ready-built nodes touched), so they run on a
# bare instance (or as a static) — no in-tree HUD build needed.

func test_ui_hp_segment_fill_partials() -> void:
	var UI = load("res://scripts/ui/ui.gd")  # static pure fill math behind the segmented HP bar
	# 2.5 of 4 HP across 4 segments: two full, one half, one empty.
	assert_eq(UI.hp_segment_fill(2.5, 4.0, 4, 0), 1.0, "first segment full")
	assert_eq(UI.hp_segment_fill(2.5, 4.0, 4, 1), 1.0, "second segment full")
	assert_almost_eq(UI.hp_segment_fill(2.5, 4.0, 4, 2), 0.5, 0.001, "third segment half-filled")
	assert_eq(UI.hp_segment_fill(2.5, 4.0, 4, 3), 0.0, "fourth segment empty")
	assert_eq(UI.hp_segment_fill(0.0, 4.0, 4, 0), 0.0, "zero HP leaves the first segment empty")
	assert_eq(UI.hp_segment_fill(4.0, 4.0, 4, 3), 1.0, "full HP fills the last segment")


func test_ui_hp_display_seg_count_respects_width_budget() -> void:
	var UI = load("res://scripts/ui/ui.gd")  # static budget math behind the fixed-width segmented HP bar
	# Defaults (budget 232, gap 3, min width 4): the base 8-HP look is under budget, so it stays one segment
	# per HP — pixel-identical to the pre-budget bar.
	assert_eq(UI.hp_display_seg_count(8.0, 232.0, 3.0, 4.0), 8, "default 8-HP look keeps one segment per HP")
	# Huge max HP caps at floor((budget+gap)/(min_w+gap)) drawn segments; past that one cell represents >1 HP.
	assert_eq(UI.hp_display_seg_count(200.0, 232.0, 3.0, 4.0), 33, "huge max HP caps at the 33 segments that fit the budget")
	assert_eq(UI.hp_display_seg_count(33.0, 232.0, 3.0, 4.0), 33, "exactly-at-cap max HP still draws one segment per HP")
	assert_eq(UI.hp_display_seg_count(0.0, 232.0, 3.0, 4.0), 1, "degenerate max HP still draws one segment")


func test_ui_hp_display_seg_width_whole_pixels_within_budget() -> void:
	var UI = load("res://scripts/ui/ui.gd")
	# Under budget the segments keep the authored full width — never widened to soak up spare budget.
	assert_eq(UI.hp_display_seg_width(8, 232.0, 3.0, 26.0), 26.0, "8 default segments render at the full 26px width")
	assert_eq(UI.hp_display_seg_width(1, 232.0, 3.0, 26.0), 26.0, "a lone segment clamps to full width, not the whole budget")
	# Over budget they shrink to a WHOLE-PIXEL width within the budget. Deliberately floored, not exact-fit:
	# fractional widths rasterize adjacent segments at different integer sizes on the low-res canvas (a ragged
	# comb after the ~2.4x upscale), so the bar trades up to count-1 invisible pixels for aligned edges.
	var w: float = UI.hp_display_seg_width(20, 232.0, 3.0, 26.0)
	assert_lte(w, 26.0, "shrunk segments never exceed the authored full width")
	assert_eq(w, floorf(w), "a shrunk width is always a whole pixel — fractional widths render a ragged comb")
	assert_lte(w * 20.0 + 3.0 * 19.0, 232.0, "20 shrunk segments + gaps stay within the 232px budget")
	assert_gt((w + 1.0) * 20.0 + 3.0 * 19.0, 232.0, "…and one more pixel per segment would burst it (no wasted width)")
	# Absurd counts hit the 1px floor rather than a zero/negative width.
	assert_eq(UI.hp_display_seg_width(1000, 232.0, 3.0, 26.0), 1.0, "width never drops below the 1px floor")


func test_ui_stamina_bar_fill() -> void:
	var UI = load("res://scripts/ui/ui.gd")
	assert_eq(UI.stamina_bar_fill(100.0, 100.0), 1.0, "full stamina fills the bar")
	assert_almost_eq(UI.stamina_bar_fill(25.0, 100.0), 0.25, 0.001, "partial stamina maps linearly")
	assert_eq(UI.stamina_bar_fill(0.0, 100.0), 0.0, "empty stamina empties the bar")
	assert_eq(UI.stamina_bar_fill(-10.0, 100.0), 0.0, "stamina debt still renders as an empty bar")
	assert_eq(UI.stamina_bar_fill(10.0, 0.0), 1.0, "a zero max is treated as full rather than divide-by-zero")


func test_ui_ammo_text_shows_clip_and_reserve() -> void:
	var u = load("res://scripts/ui/ui.gd").new()
	var p: NPC = load("res://scripts/npc/npc.gd").new()
	p.inventory = CharacterInventory.new()
	p.inventory.add(ItemDb.ammo_item_for(&"pistol"), 4)  # 4 spare clips
	u.player = p
	var ammo := Ammo.new()
	var w := WeaponData.new()
	w.caliber = &"pistol"
	w.max_ammo = 12
	ammo.current_weapon = w
	ammo.current_ammo = 12
	u.ammo_count = ammo
	assert_eq(u._ammo_text(), "12 / 4",
		"the ammo readout is current rounds / spare clips")
	u.free()
	p.inventory.free()
	p.free()
	ammo.free()
	w = null


func test_ui_ammo_text_blank_for_caliberless_weapon() -> void:
	var u = load("res://scripts/ui/ui.gd").new()
	var p: NPC = load("res://scripts/npc/npc.gd").new()
	p.inventory = CharacterInventory.new()
	u.player = p
	var ammo := Ammo.new()
	var w := WeaponData.new()
	w.caliber = &""  # melee / rock / spray — no reserve concept
	ammo.current_weapon = w
	ammo.current_ammo = 0
	u.ammo_count = ammo
	assert_eq(u._ammo_text(), "",
		"a caliber-less weapon shows no reserve readout")
	u.free()
	p.inventory.free()
	p.free()
	ammo.free()
	w = null


# ---------------------------------------------------------------------------
# CameraSettings / Head — wall-climb pitch widening (this session's change)
# ---------------------------------------------------------------------------

func test_camera_settings_climbing_pitch_wider_than_normal_limit() -> void:
	# Resource.new(): pure tuning data, no node/tree needed. The climb clamp must be
	# strictly wider than the normal look limit so the view can crane up and over the wall lip.
	var cs := CameraSettings.new()
	assert_gt(cs.pitch_max_climbing_deg, cs.pitch_max_deg,
		"pitch_max_climbing_deg must exceed pitch_max_deg: wall-climbing widens the pitch clamp so the view can crane up and over the top of the wall — a non-wider value would silently disable the climb-look feature")


func test_head_pitch_limit_ignores_a_held_prop() -> void:
	# Carrying an object used to clamp the look to camera.pitch_max_holding_deg (30 deg), so picking anything
	# up read as the camera seizing: you could not look at your own feet or up a stairwell while holding a
	# crate. That branch (and the knob behind it) was removed 2026-08-27 -- a held prop must now leave the
	# FULL look range intact, and the wall-climb widening is the ONLY thing allowed to move the limit.
	# Head.new() without add_child: setup() was never called, so _player is null and _is_climbing() is false
	# (see the test below), which isolates the carry case.
	var head := Head.new()
	var ray := PickupRay.new()
	var prop := Throwable.new()
	ray.held_object = prop
	head.pickup_ray = ray
	assert_almost_eq(head._target_max_pitch(), deg_to_rad(GameSettings.camera.pitch_max_deg), 0.0001,
		"holding an object must not tighten the look-pitch clamp: with a prop in hand _target_max_pitch stays at the normal pitch_max_deg, so the view keeps its full up/down range while carrying")
	prop.free()
	ray.free()
	head.free()


func test_head_is_climbing_false_without_injected_player() -> void:
	# Head.new() WITHOUT add_child: _ready/_process never run; camera/screen_shake are
	# get_node_or_null getters so the bare instance is safe. setup() was never called, so
	# _player stays null and `_player as Player` yields null — _is_climbing() must short-circuit
	# to false instead of dereferencing a null and crashing.
	var head := Head.new()
	assert_false(head._is_climbing(),
		"_is_climbing() must return false when no player has been injected: the '_player as Player' cast is null, and the `p != null and ...` guard must safely return false rather than calling is_climbing() on null")
	head.free()


func test_head_reset_pitch_clears_vertical_look_only() -> void:
	var head := Head.new()
	head.rotation = Vector3(0.7, 0.2, -0.1)
	head.reset_pitch()
	assert_eq(head.rotation.x, 0.0,
		"Head.reset_pitch must clear vertical look so a respawn does not keep the death-time camera pitch")
	assert_almost_eq(head.rotation.y, 0.2, 0.0001,
		"Head.reset_pitch must leave local yaw alone; Player restores body yaw from GameState.respawn_yaw")
	assert_almost_eq(head.rotation.z, -0.1, 0.0001,
		"Head.reset_pitch must leave roll alone; ScreenShake/CameraEffects own their own roll resets")
	head.free()


# --- Lens display map (CameraSettings.lens_display_point) --------------------------------------------------
# The world barrel lens bends the PICTURE only; HUD annotations from unproject_position (sniper glints,
# compass markers, the sky-title overlay) draw ABOVE it and must be mapped to where the warp DISPLAYS their
# point. These pin the pure static against the shader's own forward mapping (post_process.gdshader
# lens_warp: source_radius = output_radius * (1 + k*r2n)/(1 + k), corners pinned), verified live 2026-08-25
# by the presentation QA probe: warp_delta sub-pixel at centre and mid-radius, RETRO and HIGH FIDELITY alike.

## The shader's forward map (output -> the source uv it fetches), transliterated for the round-trip below.
func _shader_lens_source(out_p: Vector2, canvas: Vector2, aspect: float, k: float) -> Vector2:
	var c := (out_p / canvas) * 2.0 - Vector2.ONE
	c.x *= aspect
	var r2n := c.dot(c) / (aspect * aspect + 1.0)
	c *= (1.0 + k * r2n) / (1.0 + k)
	c.x /= aspect
	return (c + Vector2.ONE) * 0.5 * canvas

func test_lens_display_point_is_identity_at_zero_bend() -> void:
	var canvas := Vector2(792.0, 444.0)
	var p := Vector2(500.0, 120.0)
	assert_eq(CameraSettings.lens_display_point(p, canvas, 1920.0 / 1080.0, 0.0), p,
		"k == 0 must be an exact pass-through, so callers can apply the map unconditionally")

func test_lens_display_point_inverts_the_shader_forward_map() -> void:
	# Round-trip: pick DISPLAY (output) points, run them through the shader's forward map to get the
	# source (= what unproject_position reports), and require the inverse to recover the display point.
	var canvas := Vector2(792.0, 444.0)
	var aspect := 1920.0 / 1080.0
	for k in [0.05, 0.12, 0.5, 1.0]:
		for out_p in [Vector2(396.0, 222.0), Vector2(500.0, 150.0), Vector2(700.0, 400.0), Vector2(60.0, 40.0)]:
			var src: Vector2 = _shader_lens_source(out_p, canvas, aspect, k)
			var back: Vector2 = CameraSettings.lens_display_point(src, canvas, aspect, k)
			assert_almost_eq(back.x, out_p.x, 0.05,
				"inverse must recover the display x within 1/20 px (k=%s, p=%s)" % [k, out_p])
			assert_almost_eq(back.y, out_p.y, 0.05,
				"inverse must recover the display y within 1/20 px (k=%s, p=%s)" % [k, out_p])

func test_lens_display_point_pushes_content_outward_and_pins_corners() -> void:
	var canvas := Vector2(792.0, 444.0)
	var aspect := 792.0 / 444.0
	# Centre magnification: a mid-radius source point DISPLAYS farther from the centre than it was rendered.
	var src := Vector2(550.0, 300.0)
	var disp: Vector2 = CameraSettings.lens_display_point(src, canvas, aspect, 0.12)
	var centre := canvas * 0.5
	assert_gt((disp - centre).length(), (src - centre).length(),
		"a positive bend magnifies the centre, so displayed points sit OUTWARD of their rendered position")
	# The corner is pinned by the shader's (1 + k) normalisation — the inverse must honour it.
	var corner := Vector2(792.0, 444.0)
	var back: Vector2 = CameraSettings.lens_display_point(corner, canvas, aspect, 0.5)
	assert_almost_eq(back.x, corner.x, 0.05, "corners are pinned at any bend (x)")
	assert_almost_eq(back.y, corner.y, 0.05, "corners are pinned at any bend (y)")
