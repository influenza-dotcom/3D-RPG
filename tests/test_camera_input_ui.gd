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
##   MouseInput (scripts/input/mouse_input.gd)
##     - speed_sensitivity_multiplier() below-threshold == 1.0 and mid-range
##       monotonic falloff (the no-player==1.0 and at-max==sens_min cases are
##       ALREADY in test_smoke and are NOT duplicated here).
##     - rotate / attack signals exist (Head/body/GunMesh + attack.gd wire to them).
##     All MouseInput instances are .new() WITHOUT add_child so _ready never runs
##     and the real cursor is never captured.
##   InputManager (managers/InputManager.gd, live autoload)
##     - every action-name constant (test_autoload_order only checks action_forward).
##     - get_movement_vector() returns Vector2.ZERO with no keys held (axis wiring).
##   FreezeFrame (scenes/player/freeze_frame.gd, live autoload)
##     - freeze() exists. The active time_scale path is NOT invoked (it writes
##       Engine.time_scale + awaits a real timer); the disabled no-op is already in
##       test_smoke.
##   Hitmarker (scripts/ui/hitmarker.gd), DamageIndicators (scripts/ui/damage_indicators.gd),
##   UI (scripts/ui/ui.gd)
##     - exported defaults, base class, has_method, and the pure state mutators
##       (flash()/add()/_process()/setup()) driven on DETACHED .new() instances.
##
## DELIBERATELY SKIPPED (instantiation is unsafe / behaviour needs a full scene):
##   - camera_effects.gd (CameraEffects): every method derefs a null `player`; only
##     a full Character + tree could exercise it. Not worth a fragile test.
##   - flash_light.gd / laser_mesh.gd / ray_cast.gd: @onready NodePaths resolve to
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


func test_hitmarker_exported_defaults() -> void:
	var h = load("res://scripts/ui/hitmarker.gd").new()
	assert_eq(h.duration, 0.25,
		"Hitmarker.duration default (0.25s) is the fade window the HUD juice tuning relies on")
	assert_gt(h.tick_length, 0.0,
		"tick_length must be positive so the confirm ticks are visible")
	assert_gt(h.thickness, 0.0,
		"thickness must be positive so the ticks render")
	assert_gt(h.headshot_scale, 1.0,
		"headshot_scale must exceed 1.0 — the load-bearing 'head hits read bigger' invariant")
	h.free()


func test_hitmarker_flash_arms_timer_and_records_headshot() -> void:
	# flash() only sets _t/_headshot + queue_redraw (a no-op off-screen). No _draw.
	var h := Hitmarker.new()
	h.flash(true)
	assert_almost_eq(h._t, h.duration, 0.001,
		"flash() must reset the fade timer _t to duration so the marker pops at full strength")
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


func test_damage_indicators_exported_defaults() -> void:
	var di = load("res://scripts/ui/damage_indicators.gd").new()
	assert_eq(di.duration, 1.0,
		"DamageIndicators.duration default (1.0s) is the arc lifetime the directional-damage cue relies on")
	assert_gt(di.radius, 0.0,
		"radius must be positive so the arc sits off the crosshair centre")
	assert_gt(di.arc_degrees, 0.0,
		"arc_degrees must be positive so each wedge has angular width")
	assert_gt(di.thickness, 0.0,
		"thickness must be positive so the arc renders")
	di.free()


func test_damage_indicators_add_records_hit_at_full_lifetime() -> void:
	# add() only appends to _hits + queue_redraw — no camera deref.
	var di := DamageIndicators.new()
	di.add(Vector3(1, 2, 3))
	assert_eq(di._hits.size(), 1,
		"add() must record one entry so the overlay has a source to draw")
	assert_almost_eq(di._hits[0]["t"], di.duration, 0.001,
		"A new hit must start at full lifetime (t == duration) so its arc begins at full opacity")
	assert_eq(di._hits[0]["pos"], Vector3(1, 2, 3),
		"add() must store the source world position so the bearing can be recomputed live as the player turns")
	di.free()


func test_damage_indicators_process_ages_and_culls() -> void:
	# _process only decrements t, removes expired, queue_redraw — it never derefs camera.
	var di := DamageIndicators.new()
	di.add(Vector3(1, 0, 0))
	di._process(di.duration + 0.1)
	assert_eq(di._hits.size(), 0,
		"_process must remove expired hits so the overlay clears once an indicator's time runs out")
	di.free()


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


# UI HUD readouts: _hp_text / _ammo_text are pure formatters (no _ready-built nodes touched), so they run
# on a bare .new() instance with player/ammo_count assigned — no in-tree HUD build needed.

func test_ui_hp_text_formats_current_and_max() -> void:
	var u = load("res://scripts/ui/ui.gd").new()
	var p: NPC = load("res://scripts/npc/npc.gd").new()  # an NPC is a Character with hp/max_hp
	p.max_hp = 100.0
	p.hp = 87.0
	u.player = p
	assert_eq(u._hp_text(), "87 / 100",
		"the health readout shows rounded current / max, with no 'HP' label")
	u.free()
	p.free()


func test_ui_ammo_text_shows_clip_and_reserve() -> void:
	var u = load("res://scripts/ui/ui.gd").new()
	var p: NPC = load("res://scripts/npc/npc.gd").new()
	p.inventory = CharacterInventory.new()
	p.inventory.add(ItemDb.ammo_item_for(&"9mm"), 4)  # 4 spare clips
	u.player = p
	var ammo := Ammo.new()
	var w := WeaponData.new()
	w.caliber = &"9mm"
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


func test_head_is_climbing_false_without_injected_player() -> void:
	# Head.new() WITHOUT add_child: _ready/_process never run; camera/screen_shake are
	# get_node_or_null getters so the bare instance is safe. setup() was never called, so
	# _player stays null and `_player as Player` yields null — _is_climbing() must short-circuit
	# to false instead of dereferencing a null and crashing.
	var head := Head.new()
	assert_false(head._is_climbing(),
		"_is_climbing() must return false when no player has been injected: the '_player as Player' cast is null, and the `p != null and ...` guard must safely return false rather than calling is_climbing() on null")
	head.free()