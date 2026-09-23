extends GutTest

## GUT tests for the "Camera / input / UI" subsystem. Each assert guards a
## load-bearing contract and its message says WHY that invariant matters, so this
## file doubles as executable documentation.
##
## COVERS:
##   ScreenShake (scripts/camera/screen_shake.gd)
##     - shake()/shake_explosion() trauma clamping, additivity, and the design
##       contract that the explosion ceiling exceeds the ordinary one.
##     - trauma decay via _process driven MANUALLY on a DETACHED .new() node: decay_rate is honoured as
##       trauma-per-second, the settle is frame-rate independent, and decay clamps at 0.
##     - extends Node3D (the camera parents under it so its rotation shakes view).
##   MouseInput (scripts/components/mouse_input.gd)
##     - speed_sensitivity_multiplier() below-threshold == 1.0 and mid-range
##       monotonic falloff (the no-player==1.0 and at-max==sens_min cases are
##       ALREADY in test_smoke and are NOT duplicated here).
##     - rotate / attack signals exist (Head/body/GunMesh + attack.gd wire to them).
##     - mouse look turns by InputEventMouseMotion.screen_relative, never `relative` (which the viewport stretch
##       mode pre-scales by canvas/window width, so look speed used to ride the window size), driven through a
##       recompiled copy of mouse_input.gd with only its cursor-capture test lifted (headless never reports a
##       captured cursor — see the test's doc comment).
##     All MouseInput instances are .new() WITHOUT add_child so _ready never runs
##     and the real cursor is never captured.
##   InputManager action names are NOT pinned here: tests/test_input_action_catalog.gd checks every action_* var
##     against the live InputMap, and the Hotbar wheel test below presses InputManager.action_zoom so the raw
##     "Zoom" polls in ScopeIn/Hotbar are proven to read that same action.
##   FreezeFrame (scenes/player/freeze_frame.gd, live autoload)
##     - freeze() exists. The active time_scale path is NOT invoked (it writes
##       Engine.time_scale + awaits a real timer); the disabled no-op is already in
##       test_smoke.
##   CameraEffects (scripts/camera/camera_effects.gd)
##     - _process driven off-tree against a bare Player subclass (_SprintProbe): the scoped-FOV ownership latch
##       really suppresses the movement-FOV writer, and the sprint kick LAYERS on the forward-run kick, inside
##       Camera3D's legal FOV range.
##   Hotbar (scripts/ui/hotbar.gd) — a wheel notch yields to an aimed variable-zoom scope and switches otherwise.
##   Hitmarker (scripts/ui/hitmarker.gd), DamageIndicators (scripts/ui/damage_indicators.gd),
##   UI (scripts/ui/ui.gd)
##     - base class, has_method, the skin invariants that keep each cue visible, and the fade/lifetime state
##       machines (flash()/add()/_process()) driven on DETACHED .new() instances with the skin retuned live;
##       setup() injection + its Player-only wallet/hotbar hooks; set_scoped's reticle + back-buffer swap.
##     - the hitmarker's prewarm paint is taken back by exactly one clearing repaint (counted in-tree).
##
## DELIBERATELY SKIPPED (instantiation is unsafe / behaviour needs a full scene):
##   - CameraEffects in-tree _process/bob with a real Player _ready (a real sprint needs a grounded body —
##     tests/test_player_core.gd drives is_sprinting() itself).
##   - flash_light.gd / ray_cast.gd: @onready NodePaths resolve to
##     null on a bare tree and _ready/_process dereference them; ray_cast also does
##     real physics (direct_space_state, impulses, freeze/layer mutation). Their
##     invariants are already guarded by test_smoke's file-content tests.
##   - MouseInput._ready/_process and the REAL class's _unhandled_input: real cursor capture (never reported
##     headless) + viewport camera derefs (the look body itself is driven through the surrogate above).
##   - FreezeFrame active time-scale path; ui._process (derefs hp/ammo Labels);
##     adding any of the above into a live tree.
##   - The already-covered cases listed inline above (no duplication).
##
## All asserts (assert_eq/_gt/_lt/_true/_false/_not_null/_almost_eq) and the
## has_method/has_signal Object builtins match the existing suite (test_smoke.gd).

const PLAYER_PATH := "res://scripts/player/player.gd"

## A bare Player whose sprint read is an INPUT the test controls. A real is_sprinting() needs a grounded
## in-tree body + stamina + the Run action (tests/test_player_core.gd drives exactly that); CameraEffects only
## consumes the answer, so this isolates the camera's FOV composition from the sprint gates. Never added to
## the tree, so the Player's _ready never runs.
class _SprintProbe extends Player:
	var sprinting: bool = false

	func is_sprinting() -> bool:
		return sprinting


# Globals individual tests retune; snapshotted before and restored after EVERY test so a failing assert
# can never leak a tuned value into a later test (GameSettings / MenuStyle.hud are process-wide resources).
var _saved_fov_effects: bool
var _saved_sprint_fov_mult: float
var _saved_scope_magnification: float
var _saved_hitmarker_duration: float
var _saved_damage_arc_duration: float


func before_each() -> void:
	_saved_fov_effects = Settings.fov_effects_enabled
	_saved_sprint_fov_mult = GameSettings.camera.sprint_fov_mult
	_saved_scope_magnification = GameSettings.camera.scope_magnification
	_saved_hitmarker_duration = MenuStyle.hud.hitmarker_duration
	_saved_damage_arc_duration = MenuStyle.hud.damage_arc_duration


func after_each() -> void:
	Settings.fov_effects_enabled = _saved_fov_effects
	GameSettings.camera.sprint_fov_mult = _saved_sprint_fov_mult
	GameSettings.camera.scope_magnification = _saved_scope_magnification
	MenuStyle.hud.hitmarker_duration = _saved_hitmarker_duration
	MenuStyle.hud.damage_arc_duration = _saved_damage_arc_duration
	Input.action_release(InputManager.action_zoom)


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


func test_screen_shake_trauma_decays_at_the_tuned_rate_independent_of_frame_rate() -> void:
	# DETACHED nodes: _process is called by hand (never added to the tree). Its
	# rotation = randf_range(...) write is inert on an unparented Node3D — no scene.
	# The step is chosen so the decay never reaches the 0 clamp (that edge has its own test below).
	var rate: float = GameSettings.screen_shake.decay_rate
	assert_gt(rate, 0.0, "screen_shake.decay_rate must be positive or a shake never settles")
	var dt := 0.25 / rate  # decay_rate is trauma per SECOND, so this much time must remove a quarter of full trauma
	var one_frame := ScreenShake.new()
	one_frame.trauma = 1.0
	one_frame._process(dt)
	assert_almost_eq(one_frame.trauma, 0.75, 0.001,
		"decay_rate must be honoured as trauma per second: 0.25/decay_rate seconds must settle exactly a quarter of a full shake")
	var ten_frames := ScreenShake.new()
	ten_frames.trauma = 1.0
	for i in 10:
		ten_frames._process(dt / 10.0)
	assert_almost_eq(ten_frames.trauma, one_frame.trauma, 0.001,
		"ten short frames must settle the shake exactly as far as one long frame covering the same time — shake duration must not depend on the frame rate")
	one_frame.free()
	ten_frames.free()


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

## An off-tree CameraEffects wired to a bare _SprintProbe, so _process can run by hand. No `attributes`, so
## set_scope_dof returns before its get_tree() fog/dust pass. Standing still, not sprinting, FOV effects ON.
func _feel_camera() -> Array:
	Settings.fov_effects_enabled = true  # restored in after_each
	var probe := _SprintProbe.new()
	var cam := CameraEffects.new()
	cam.player = probe
	return [cam, probe]


## One settled frame: a delta long enough that every exp() ease in _process lands exactly on its target.
func _settle(cam: CameraEffects) -> void:
	cam._process(100.0)


func test_scoped_camera_leaves_fov_to_scope_in_until_unscoped_or_reset() -> void:
	var rig := _feel_camera()
	var cam: CameraEffects = rig[0]
	var probe: _SprintProbe = rig[1]
	var ads_fov := 40.0  # what ScopeIn eased camera.fov to for ADS; a legal angle well away from base_fov
	assert_gt(absf(cam.base_fov - ads_fov), 5.0, "precondition: the ADS angle must differ from the rest FOV or nothing below discriminates")
	cam.fov = ads_fov
	_settle(cam)
	assert_almost_eq(cam.fov, cam.base_fov, 0.01,
		"control: with nobody scoped, the movement-FOV writer must ease an off-rest fov back to base_fov — otherwise the scoped assert below proves nothing")
	cam.set_scope_dof(true, false)
	cam.fov = ads_fov
	_settle(cam)
	assert_almost_eq(cam.fov, ads_fov, 0.01,
		"while scoped CameraEffects must leave camera.fov to ScopeIn — easing it toward the movement FOV would fight the ADS zoom every frame")
	cam.set_scope_dof(false, false)
	_settle(cam)
	assert_almost_eq(cam.fov, cam.base_fov, 0.01,
		"unscoping must hand camera.fov back to CameraEffects, so the view returns to the rest FOV")
	cam.set_scope_dof(true, false)
	cam.reset_transients()  # respawn while scoped
	cam.fov = ads_fov
	_settle(cam)
	assert_almost_eq(cam.fov, cam.base_fov, 0.01,
		"a respawn reset must hand FOV ownership back too — a death while aiming must not freeze the new life's FOV")
	cam.free()
	probe.free()


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


func test_camera_sprint_fov_layers_on_the_forward_run_kick_inside_the_legal_range() -> void:
	var rig := _feel_camera()
	var cam: CameraEffects = rig[0]
	var probe: _SprintProbe = rig[1]
	var sprint_kick: float = GameSettings.camera.sprint_fov_mult
	assert_gt(sprint_kick, 0.0, "precondition: the shipped sprint_fov_mult must widen the view or there is nothing to layer")
	probe.input_dir = Vector2(0.0, -1.0)  # full forward push
	_settle(cam)
	var run_fov := cam.fov
	assert_gt(run_fov, cam.base_fov + 0.01,
		"precondition: a full forward push must already kick the FOV wide, so the sprint layer below is measured on top of a real run kick")
	probe.sprinting = true
	_settle(cam)
	assert_almost_eq(cam.fov - run_fov, sprint_kick, 0.01,
		"breaking into a sprint must widen the view by exactly sprint_fov_mult ON TOP of the forward-run kick — replacing the run kick (or ignoring is_sprinting) changes the step")
	probe.sprinting = false
	_settle(cam)
	assert_almost_eq(cam.fov, run_fov, 0.01, "dropping out of the sprint must drop exactly the sprint kick back off")
	probe.sprinting = true
	Settings.fov_effects_enabled = false  # restored in after_each
	_settle(cam)
	assert_almost_eq(cam.fov, cam.base_fov, 0.01,
		"with the FOV Effects accessibility toggle off, a sprinting forward run must rest at base_fov — no cosmetic kick survives")
	Settings.fov_effects_enabled = true
	GameSettings.camera.sprint_fov_mult = 500.0  # a too-hot designer value; restored in after_each
	_settle(cam)
	assert_almost_eq(cam.fov, 179.0, 0.01,
		"a stacked FOV past Camera3D's 179-degree limit must clamp to the limit instead of breaking the view")
	cam.free()
	probe.free()


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
	GameSettings.camera.scope_magnification = 2.0  # restored in after_each
	var rest := clampf(GameSettings.camera.default_fov, 1.0, 179.0)
	assert_almost_eq(_apparent_magnification(rest, si.scoped_target_fov(null)), 2.0, 0.001,
		"no weapon must still fall through to the global magnification solve — bare ADS must bring the world exactly scope_magnification closer")
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


func _weapon_item(id: StringName, weapon: WeaponData) -> Item:
	var it := Item.new()
	it.id = id
	it.category = Item.Category.WEAPON
	it.weapon = weapon  # is_weapon() requires a real WeaponData
	return it


func test_hotbar_wheel_notch_yields_to_an_aimed_variable_scope_and_switches_weapons_otherwise() -> void:
	# The bar and ScopeIn both hear every wheel notch; the Hotbar must YIELD while the aimed weapon's scope owns
	# the wheel, or each notch that dials the sniper's zoom also swaps the weapon out mid-ADS. Driven through
	# the real Hotbar._unhandled_input with a bare off-tree Player (the test_hotbar.gd idiom). The Hotbar itself
	# is in-tree only because the switching branch marks the event handled on the real viewport.
	# Zoom is pressed through InputManager.action_zoom, which also proves the raw "Zoom" polls in ScopeIn and
	# Hotbar read the same action InputManager exposes.
	var p = load(PLAYER_PATH).new()
	p.hp = 1.0  # _ready (which seeds hp) never runs off-tree; the bar's liveness gate needs a living player
	var inv := CharacterInventory.new()
	p.inventory = inv
	var sniper_data := WeaponData.new()
	sniper_data.scoped_zoom_fov_min = 1.0
	sniper_data.scoped_zoom_fov_max = 20.0
	var sniper := _weapon_item(&"sniper", sniper_data)
	var pistol := _weapon_item(&"pistol", WeaponData.new())
	inv.add(sniper)
	inv.add(pistol)
	var ws := Weapon.new()
	var atk := Attack.new()
	atk.current_weapon = sniper_data
	atk.holstered = false
	ws.attack = atk
	p.weapon_system = ws
	var old_step := GameSettings.camera.scope_zoom_wheel_step
	GameSettings.camera.scope_zoom_wheel_step = 1.25  # the wheel zoom's global on-switch
	var hb := Hotbar.new()
	add_child_autofree(hb)
	hb.setup(p)
	inv.equip_item(sniper)
	var notch := InputEventMouseButton.new()
	notch.button_index = MOUSE_BUTTON_WHEEL_DOWN  # project.godot binds this to Hotbar Next
	notch.pressed = true
	assert_true(notch.is_action_pressed(InputManager.action_hotbar_next),
		"precondition: a wheel-down notch must read as Hotbar Next, or the bar never sees it and the yield below is vacuous")
	Input.action_press(InputManager.action_zoom)
	hb._unhandled_input(notch)
	assert_eq(inv.equipped_item, sniper,
		"a wheel notch while AIMING a variable-zoom scope belongs to the zoom dial — the hotbar must not swap the sniper out mid-ADS")
	Input.action_release(InputManager.action_zoom)
	hb._unhandled_input(notch)
	assert_eq(inv.equipped_item, pistol,
		"control: the same notch from the hip must still cycle to the next weapon — the yield is only for an aimed scope")
	GameSettings.camera.scope_zoom_wheel_step = old_step
	ws.free()
	atk.free()
	p.free()
	inv.free()


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
## legacy settings.cfg is migrated by Settings.read_mouse_sensitivity — tests/test_settings.gd pins those.
## DRIVEN THROUGH A SURROGATE: the handler only turns the view while `Input.mouse_mode == MOUSE_MODE_CAPTURED`, and the
## headless display server never reports a captured cursor (setting CAPTURED reads back VISIBLE — tried 2026-09-17),
## so the real class's _unhandled_input cannot be driven under GUT. The surrogate is mouse_input.gd's OWN source,
## read from disk and compiled at test time with exactly two edits: the class_name line dropped (a second MouseInput
## would collide with the global class) and the capture test lifted off the look gate. Everything past that gate —
## the motion field read, the sensitivity scale, the axis mapping, the rotate emit — is the shipped code, so a
## production edit to it reaches this test. If either edit stops matching, the test fails loudly (re-point the
## constants below at the new spelling; never weaken the look asserts).
const MOUSE_INPUT_PATH := "res://scripts/components/mouse_input.gd"
const MOUSE_INPUT_CLASS_LINE := "class_name MouseInput\n"
const MOUSE_LOOK_CAPTURE_GATE := "if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:"
const MOUSE_LOOK_UNGATED := "if event is InputEventMouseMotion:"

## A detached instance of the surrogate described above (never added to the tree, so its _ready never captures the
## real cursor), or null after a failed assert when the source no longer carries the two spots the surrogate edits.
func _mouse_look_surrogate() -> Node3D:
	var src := FileAccess.get_file_as_string(MOUSE_INPUT_PATH)
	assert_eq(src.count(MOUSE_INPUT_CLASS_LINE), 1, "mouse_input.gd declares class_name MouseInput exactly once (the surrogate drops that line)")
	assert_eq(src.count(MOUSE_LOOK_CAPTURE_GATE), 1,
		"mouse_input.gd's look gate is still spelled as MOUSE_LOOK_CAPTURE_GATE — the surrogate lifts its capture test")
	if src.count(MOUSE_INPUT_CLASS_LINE) != 1 or src.count(MOUSE_LOOK_CAPTURE_GATE) != 1:
		return null
	var script := GDScript.new()
	script.source_code = src.replace(MOUSE_INPUT_CLASS_LINE, "").replace(MOUSE_LOOK_CAPTURE_GATE, MOUSE_LOOK_UNGATED)
	var err := script.reload()
	assert_eq(err, OK, "the surrogate of mouse_input.gd compiles")
	if err != OK:
		return null
	return script.new() as Node3D

## Feed one mouse-motion event to `mi`'s look handler and return the ONE look delta it emitted on `rotate`
## (.x = pitch, .y = yaw). `screen_px` is the OS motion; `window_scaled` is what the engine reports as `relative`.
func _look_turn(mi: Node3D, screen_px: Vector2, window_scaled: Vector2) -> Vector2:
	var turns: Array = []
	var sink := func(amt: Vector2) -> void: turns.append(amt)
	mi.connect(&"rotate", sink)
	var motion := InputEventMouseMotion.new()
	motion.screen_relative = screen_px
	motion.relative = window_scaled
	mi.call(&"_unhandled_input", motion)
	mi.disconnect(&"rotate", sink)
	assert_eq(turns.size(), 1, "one mouse-motion event turns the view exactly once")
	return turns[0] if turns.size() == 1 else Vector2.ZERO

func test_mouse_look_turns_by_screen_pixels_not_the_window_scaled_relative() -> void:
	var mi := _mouse_look_surrogate()
	assert_true(mi != null, "the MouseInput look surrogate was built")
	if mi == null:
		return
	# ONE hand motion (20 px across, 12 px up, in OS pixels) as the engine reports it in two window sizes: under the
	# viewport stretch mode `relative` is that motion x 792/window width, so 1080p fullscreen and the 1600x900
	# window hand the handler different `relative` values for the same hand.
	var hand := Vector2(20.0, 12.0)
	var fullscreen := _look_turn(mi, hand, hand * (792.0 / 1920.0))
	var windowed := _look_turn(mi, hand, hand * (792.0 / 1600.0))
	assert_ne(fullscreen.x, 0.0, "control: vertical mouse motion turns the pitch at all, so the equalities below are not two dead zeros")
	assert_ne(fullscreen.y, 0.0, "control: horizontal mouse motion turns the yaw at all")
	assert_eq(windowed, fullscreen,
		"the same hand motion must turn the view the same amount fullscreen and windowed — reading `relative` made look 1.2-1.5x faster the moment the game went windowed (and half as fast at 4K)")
	# CONTROL for what the turn DOES follow: twice the OS motion with the window-scaled value held still turns twice as far.
	var doubled := _look_turn(mi, hand * 2.0, hand * (792.0 / 1920.0))
	assert_almost_eq(doubled.x, fullscreen.x * 2.0, maxf(absf(fullscreen.x) * 0.001, 1e-9),
		"pitch scales with the OS (screen) motion, so one sensitivity value means one thing at every window size")
	assert_almost_eq(doubled.y, fullscreen.y * 2.0, maxf(absf(fullscreen.y) * 0.001, 1e-9),
		"yaw scales with the OS (screen) motion, so one sensitivity value means one thing at every window size")
	mi.free()


# ---------------------------------------------------------------------------
# FreezeFrame (live autoload — assert existence only; invoking the active path
# writes Engine.time_scale and awaits a real timer)
# ---------------------------------------------------------------------------

func test_freeze_frame_exposes_freeze() -> void:
	assert_true(FreezeFrame.has_method("freeze"),
		"FreezeFrame must expose freeze(): enemy hit/death hitstop calls FreezeFrame.freeze(...) by name (asserting existence does not invoke the time_scale write)")


# ---------------------------------------------------------------------------
# Hitmarker  (.new() WITHOUT add_child, except the warm-paint guard, which counts real in-tree repaints)
# ---------------------------------------------------------------------------

func test_hitmarker_is_control_with_flash() -> void:
	var h = load("res://scripts/ui/hitmarker.gd").new()
	assert_true(h is Control,
		"Hitmarker must extend Control: it draws as a HUD overlay")
	assert_true(h.has_method("flash"),
		"Hitmarker must expose flash(): the owner calls it on every confirmed hit")
	h.free()


func test_hitmarker_skin_keeps_the_confirm_visible_and_head_hits_bigger() -> void:
	# Hitmarker's look lives on MenuStyle.hud (HudSkin) — it is code-built, so the skin IS its authoring surface.
	# These are the invariants a retune must keep, not the tuned numbers themselves (test_hud_skin.gd owns those).
	var hud = MenuStyle.hud
	assert_gt(hud.hitmarker_duration, 0.0,
		"hitmarker_duration must be positive — a zero fade window ends the pop on the frame it is armed, so hits never confirm")
	assert_gt(hud.hitmarker_headshot_scale, 1.0,
		"hitmarker_headshot_scale must exceed 1.0 — the load-bearing 'head hits read bigger' invariant")
	if hud.hitmarker_texture == null:  # the code-drawn X: only then do the tick metrics paint anything
		assert_gt(hud.hitmarker_tick_length, 0.0,
			"with no artist texture the confirm IS the drawn ticks, so hitmarker_tick_length must be positive or the marker is invisible")
		assert_gt(hud.hitmarker_thickness, 0.0,
			"with no artist texture the ticks need a positive hitmarker_thickness to render")


func test_hitmarker_fade_follows_the_skin_window_and_the_latest_hit_picks_the_look() -> void:
	# Off-tree: queue_redraw is a no-op, so flash/_process run by hand. `_t > 0` is exactly _draw's "still
	# showing" gate (it paints nothing once _t <= 0), so it is the observable for "the marker is on screen".
	# The window is retuned on the LIVE skin (restored in after_each) to prove it is read at flash time.
	var h := Hitmarker.new()
	MenuStyle.hud.hitmarker_duration = 0.6
	h.flash(true)
	h._process(0.5)
	assert_gt(h._t, 0.0, "0.5 s into a 0.6 s skin window the hit-confirm must still be showing")
	h._process(0.2)
	assert_true(h._t <= 0.0, "past the skin's fade window the hit-confirm must be gone")
	var ended := h._t
	h._process(1.0)
	assert_eq(h._t, ended, "a finished marker must idle (no redraw churn) rather than keep counting down")
	MenuStyle.hud.hitmarker_duration = 2.0
	h.flash(false)
	h._process(1.5)
	assert_gt(h._t, 0.0,
		"a designer retuning the skin to a 2 s window must see the marker still showing at 1.5 s — the window is read from the skin on every flash")
	assert_false(h._headshot, "a body hit after a headshot must draw in the ordinary colour/scale, not keep the head look")
	h.flash(true)
	assert_true(h._headshot, "a headshot must switch the marker to the bigger headshot colour/scale")
	h.free()


func test_hitmarker_warm_paint_is_taken_back_after_one_frame() -> void:
	# ⭐THE "always a transparent X on my crosshair" REGRESSION GUARD (2026-09-08). EffectPrewarmer._warm_2d hands
	# the marker ONE near-invisible paint on the black fade-in to compile the canvas pipeline. A CanvasItem KEEPS
	# its draw list until something calls queue_redraw() again, and _process early-outs while _t <= 0 — so nothing
	# ever did, and the warm ticks sat on the crosshair for the whole level (the HUD ghost, which captures the
	# hitmarker, then accumulated that static source into a plainly visible X). _draw arms _warm_painted the frame
	# the ticks reach the canvas; the next PROCESSED frame must spend it on one empty redraw.
	# IN-TREE on purpose: the bug is a MISSING REPAINT, and queue_redraw() only does anything inside the tree. The
	# observable is the node's own `draw` signal, which the engine emits once per real repaint: a warm must cost
	# exactly TWO — the near-invisible paint, then the empty one that takes it back — and then go quiet.
	var h := Hitmarker.new()
	add_child_autofree(h)
	for i in 3:
		await get_tree().process_frame  # let the enter-tree / theme / resize repaints land before counting
	var repaints: Array = [0]
	h.draw.connect(func() -> void: repaints[0] += 1)
	for i in 6:
		await get_tree().process_frame
	assert_eq(repaints[0], 0,
		"control: an idle hitmarker does not repaint on its own, so every repaint counted below is the warm's doing")
	h.warm_draw(0.01)
	for i in 6:
		await get_tree().process_frame
	assert_eq(repaints[0], 2,
		"a warm costs exactly two repaints: the near-invisible paint, then ONE empty repaint that clears the retained draw list. 1 = the warm ticks stay on the crosshair for the whole level (the shipped 'transparent X'); more = the clear re-arms itself and repaints every frame for the life of the HUD")
	assert_false(h._warm_painted, "the clean-up latch is spent once the clearing repaint has been queued")
	assert_true(h._t <= 0.0, "a warm never starts a live flash: the fade timer stays idle, so nothing else would ever repaint the ticks away")


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


func test_damage_arc_skin_keeps_the_cue_on_the_smallest_canvas() -> void:
	# DamageIndicators' look lives on MenuStyle.hud (HudSkin). Invariants a retune must keep, not the tuned
	# numbers (test_hud_skin.gd owns those). The smallest UI canvas is the base viewport height divided by the
	# stretch scale (aspect=expand only ever GROWS it), so an arc ring must fit inside half of that height or
	# the "hit from above/behind" wedges draw off screen.
	var hud = MenuStyle.hud
	var min_canvas_h: float = float(ProjectSettings.get_setting("display/window/size/viewport_height")) \
		/ float(ProjectSettings.get_setting("display/window/stretch/scale"))
	assert_gt(hud.damage_arc_duration, 0.0,
		"damage_arc_duration must be positive — a zero lifetime culls every arc on the next frame, so the directional cue never reads")
	assert_gt(hud.damage_arc_radius, 0.0,
		"damage_arc_radius must be positive so the arc sits off the crosshair centre")
	assert_lt(hud.damage_arc_radius + hud.damage_arc_thickness * 0.5, min_canvas_h * 0.5,
		"the arc ring must fit inside half the smallest canvas height (%s px) or the top/bottom wedges draw off screen" % min_canvas_h)
	assert_gt(hud.damage_arc_degrees, 0.0,
		"damage_arc_degrees must be positive so each wedge has angular width")
	assert_lt(hud.damage_arc_degrees, 360.0,
		"damage_arc_degrees must stay under a full circle — a 360-degree wedge is a ring that no longer points at the source")
	assert_gt(hud.damage_arc_thickness, 0.0,
		"damage_arc_thickness must be positive so the arc renders")


func test_damage_arcs_live_for_the_skin_lifetime_each_on_its_own_clock() -> void:
	# add()/_process never deref the camera (only _draw does), so they run off-tree by hand. The lifetime is
	# retuned on the LIVE skin (restored in after_each) to prove add() reads it per hit.
	MenuStyle.hud.damage_arc_duration = 2.0
	var di := DamageIndicators.new()
	var first_source := Vector3(5.0, 0.0, 0.0)
	var second_source := Vector3(0.0, 0.0, -5.0)
	di.add(first_source)
	di._process(1.5)
	assert_eq(di._hits.size(), 1,
		"with the skin retuned to a 2 s lifetime, an arc must still be on screen 1.5 s after the hit")
	di.add(second_source)  # a second hit lands later
	di._process(0.6)  # the first is now 2.1 s old, the second 0.6 s
	assert_eq(di._hits.size(), 1, "the older arc must expire on its own clock without taking the newer one with it")
	if di._hits.size() == 1:
		assert_eq(di._hits[0]["pos"], second_source,
			"the SURVIVING arc must be the newer hit, still keyed by its world position so its bearing follows the player's turn")
	di._process(1.5)
	assert_eq(di._hits.size(), 0, "the newer arc must expire once its own lifetime has run out too")
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


func test_ui_setup_injects_refs_before_its_labels_exist_and_hooks_the_wallet_only_for_the_player() -> void:
	# setup() runs from Player._enter_tree, BEFORE this layer's _ready builds any label — so it runs on a bare,
	# off-tree UI here. An NPC is a Character but not the Player: this HUD must never narrate an NPC's wallet.
	var u = load("res://scripts/ui/ui.gd").new()
	var npc: NPC = load("res://scripts/npc/npc.gd").new()
	var ammo := Ammo.new()
	u.setup(npc, ammo)
	assert_eq(u.player, npc, "setup() must inject the character the HUD reads HP/stamina from")
	assert_eq(u.ammo_count, ammo, "setup() must inject the Ammo node the ammo readout reads")
	assert_false(npc.is_connected(&"money_changed", u._on_money_changed),
		"a non-Player character must NOT get its wallet wired to the HUD's money readout")
	assert_true(u._hotbar == null, "a non-Player character must not get the player's hotbar built")
	u.free()
	npc.free()
	# Control: the SAME call with the real Player does wire both, so the refusals above are the Player gate.
	var hud = load("res://scripts/ui/ui.gd").new()
	var p = load(PLAYER_PATH).new()
	hud.setup(p, ammo)
	assert_eq(hud.player, p, "setup() must inject the Player")
	assert_true(p.is_connected(&"money_changed", hud._on_money_changed),
		"control: the Player's wallet changes must drive the HUD money readout and its +N/-N float")
	assert_true(hud._hotbar != null, "control: the Player gets the Deus Ex hotbar built under the HUD")
	await get_tree().process_frame  # let the hotbar's deferred setup(p) run while p is still alive
	hud.free()
	p.free()
	ammo.free()


func test_ui_set_scoped_swaps_to_the_inverting_reticle_and_pays_for_the_back_buffer_only_while_scoped() -> void:
	# The scope bridge (player._on_scoped_in) can fire before the HUD's _ready has built the reticle: on a bare
	# instance set_scoped must be a safe no-op. Then the reticle parts _ready would build are handed in by hand
	# (no shader compile is needed to compare material identity) to drive the real swap.
	var u = load("res://scripts/ui/ui.gd").new()
	u.set_scoped(true)
	u.set_scoped(false)
	assert_true(u.crosshair == null, "set_scoped before _ready must not build a reticle of its own")
	var dot := ColorRect.new()
	var bbc := BackBufferCopy.new()
	var art := TextureRect.new()
	var flat_mat := ShaderMaterial.new()
	var scoped_mat := ShaderMaterial.new()
	u.crosshair = dot
	u._crosshair_bbc = bbc
	u._crosshair_art = art
	u._flat_reticle_mat = flat_mat
	u._scoped_reticle_mat = scoped_mat
	u.set_scoped(true)
	assert_eq(dot.material, scoped_mat,
		"scoped, the reticle must wear the inverting disc — it is the only reticle that stays readable against any backdrop through a scope")
	assert_eq(bbc.copy_mode, BackBufferCopy.COPY_MODE_VIEWPORT,
		"scoped, the full-screen back-buffer copy must be ON so the inverting disc samples a fresh screen (else it washes white)")
	assert_false(art.visible, "scoped, the optional artist reticle must be hidden under the inverting disc")
	u.set_scoped(false)
	assert_true(dot.material != scoped_mat, "unscoped, the reticle must leave the inverting disc")
	assert_eq(bbc.copy_mode, BackBufferCopy.COPY_MODE_DISABLED,
		"unscoped, the full-screen back-buffer copy must be OFF — paying for it every hip-fire frame is pure waste")
	u.free()
	dot.free()
	bbc.free()
	art.free()


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
