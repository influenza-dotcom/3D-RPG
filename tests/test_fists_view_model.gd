extends GutTest

## Contract tests for the UNARMED first-person visual (resources/weapons/fists.tres).
##
## Unarmed is not a special case in the weapon system — fists.tres is a normal WeaponData that every
## empty-handed fallback equips (Player.FISTS). What makes it read as "unarmed" is that it has NO view model
## at all: the bare fists are the Player's OWN first-person arms rig, the same hands you see when carrying a
## prop, which lives under the camera rather than under the gun rig.
##
## That placement is the whole design, and it is what fixes three things a mounted view-model copy got wrong:
## the hands keep the character's arm colour, they sit centred on the camera instead of offset to the gun's
## side, and they do not tip 45 degrees into the gun's holster park.
##
## The failure modes are silent, so they are pinned here:
##   1. Give fists a `view_model` again and the player holds an object while "unarmed".
##   2. Let a null `view_model` reveal the gun rig's PLACEHOLDER and the player holds a silenced pistol —
##      strictly worse than the claw hammer this replaced.
##   3. Drop the wiring and the fists never appear, or never punch, with no error anywhere.
##
## Driven, never read as text, wherever the unit can run without a Player._ready: Resource loads, off-tree
## first_person_body.gd / weapon_model_swapper.gd / gun_visuals.gd instances, a bare player.gd host wired by hand
## (the test_player_core idiom), and — only where a Tween must be created — the COMPONENT in-tree with its own
## processing switched off. The punch's hit-flash exemption is driven through a real in-tree Attack trigger pull.
## One source read remains, because the code cannot run here: the Player._ready signal connections (Player._ready
## never runs in a unit test).

const FISTS_PATH := "res://resources/weapons/fists.tres"
const WEAPONS_DIR := "res://resources/weapons/"
const PLAYER_SOURCE := "res://scripts/player/player.gd"
const FP_BODY_SOURCE := "res://scripts/player/first_person_body.gd"
const PLAYER_SCENE := "res://scenes/player/Player.tscn"
const ARM_MODEL := "res://assets/models/arm.blend"

var _saved_view_bob: bool = true
var _saved_screen_flash: bool = true


func before_each() -> void:
	_saved_view_bob = Settings.view_bob_enabled
	_saved_screen_flash = Settings.screen_flash_enabled


func after_each() -> void:
	Settings.view_bob_enabled = _saved_view_bob  # the bob test flips the accessibility gate; never leak it
	Settings.screen_flash_enabled = _saved_screen_flash  # the hit-flash test forces the flash toggle on


func _fists() -> WeaponData:
	return load(FISTS_PATH) as WeaponData


## A bare host Player with a Weapon hub (Inventory + Attack) and a FirstPersonBody whose arms rig is `rig`. When
## `in_tree`, the component joins the tree so its slides can create Tweens — with processing OFF, so nothing but
## the calls a test makes ever runs. Caller frees via _teardown.
func _fists_harness(rig: BodyModelSwap, in_tree: bool) -> Dictionary:
	var host = load(PLAYER_SOURCE).new()
	var body = load(FP_BODY_SOURCE).new()
	body.host = host
	if in_tree:
		add_child_autofree(body)
		body.set_process(false)
	var ws := Weapon.new()
	var hub := Inventory.new()
	var atk := Attack.new()
	ws.inventory = hub
	ws.attack = atk
	host.weapon_system = ws
	hub.equipped_weapon = _fists()
	body._fp_arms = rig
	return {"host": host, "body": body, "ws": ws, "hub": hub, "atk": atk, "in_tree": in_tree}


func _teardown(parts: Dictionary) -> void:
	var body = parts["body"]
	body._kill_fp_arm_tween()
	if not parts["in_tree"]:
		(body as Node).free()
	(parts["host"] as Node).free()
	(parts["ws"] as Node).free()
	(parts["hub"] as Node).free()
	(parts["atk"] as Node).free()


## The value Player.tscn SHIPS for one FirstPersonBody export: the scene's authored override when it carries one,
## else the script default (read off `fresh`, an untouched instance). Read off the PackedScene's SceneState, never
## instantiated — so no Player._ready — the same read test_weapon_hands.gd makes for camera_rig.tscn's GunMesh.
func _shipped_fp_body_value(fresh: Object, prop: String) -> Variant:
	var ps := load(PLAYER_SCENE) as PackedScene
	assert_true(ps != null, "scenes/player/Player.tscn must load")
	if ps == null:
		return fresh.get(prop)
	var state := ps.get_state()
	for i in range(state.get_node_count()):
		if state.get_node_name(i) != "FirstPersonBody":
			continue
		for p in range(state.get_node_property_count(i)):
			if state.get_node_property_name(i, p) == prop:
				return state.get_node_property_value(i, p)
		return fresh.get(prop)
	fail_test("Player.tscn must still author a FirstPersonBody node — the fists' shipped tuning lives on it")
	return fresh.get(prop)


## Every drawable MeshInstance3D of a rig's arm pair, skipping InkOutline's invisible tint duplicates (they ARE the
## outline being looked for, not a mesh that should wear one).
func _arm_meshes(rig: BodyModelSwap) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = []
	for part in [rig._arm_left, rig._arm_right]:
		if is_instance_valid(part):
			stack.push_back(part)
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).has_meta(InkOutline.TINT_DUP_META):
			continue
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			out.append(n as MeshInstance3D)
		for c in n.get_children():
			stack.push_back(c)
	return out


## The outline id InkOutline's duplicate carries for `mi` (TINT_ID_NONE when it has no duplicate at all).
func _outline_id(mi: MeshInstance3D) -> float:
	var dup := mi.get_node_or_null(InkOutline.TINT_DUP_NAME) as MeshInstance3D
	if dup == null:
		return float(InkOutline.TINT_ID_NONE)
	return float(dup.get_meta(InkOutline.TINT_BASE_META, float(InkOutline.TINT_ID_NONE)))


## Every rim-light pass chained onto what `mi` draws with — its material_override and each surface override — as
## the materials themselves, so a caller can ask for the SHARED rim a GunVisuals built.
func _rim_passes(mi: MeshInstance3D) -> Array[Material]:
	var drawn: Array[Material] = [mi.material_override]
	for s in mi.mesh.get_surface_count():
		drawn.append(mi.get_surface_override_material(s))
	var out: Array[Material] = []
	for m in drawn:
		if m == null:
			continue
		var pass_mat := m.next_pass as ShaderMaterial
		if pass_mat != null and pass_mat.shader == GunVisuals.RIM_LIGHT_SHADER:
			out.append(pass_mat)
	return out


# --- The unarmed resource ---------------------------------------------------------------------------

func test_unarmed_mounts_no_weapon_model_at_all() -> void:
	var fists := _fists()
	assert_not_null(fists, "resources/weapons/fists.tres must load as a WeaponData")
	assert_null(fists.view_model,
		"unarmed must mount NO view model — the fists are the Player's own first-person arms rig")
	fists = null

func test_unarmed_declares_that_its_visual_is_first_person_only() -> void:
	# Suppresses the swapper's "you forgot a model" warning (having none is the point here) and makes
	# held_view_model() null so an NPC hand / ground drop / grid tile show nothing — EVEN IF a view model is
	# later authored onto it. That last half is only observable on a weapon that HAS a model, so it is driven on one.
	var fists := _fists()
	assert_true(fists.view_model_is_first_person_only,
		"fists.tres must declare its visual is first-person-only, or it reads as an un-authored weapon")
	var probe := WeaponData.new()
	probe.view_model = PackedScene.new()
	probe.view_model_is_first_person_only = true
	assert_null(probe.held_view_model(),
		"a first-person-only weapon must hand NPCs / drops / the grid NOTHING, even with a view model authored")
	probe.view_model_is_first_person_only = false
	assert_eq(probe.held_view_model(), probe.view_model,
		"control: without the flag the same weapon hands out its view model")
	probe = null
	fists = null

func test_fists_is_flagged_as_a_punch() -> void:
	var fists := _fists()
	assert_true(fists.view_model_punch, "fists.tres must be flagged view_model_punch — its swing is a punch")
	fists = null

## A wielder with a hit-flash sprite of its own (only the Player has one for real) and a liveness switch, so a test can
## end a shot's 85 ms flash beat through Attack's own abort. Never add_child'd, so Character._ready never runs.
class _FlashWielder extends Character:
	var flash: Sprite3D = null
	var alive: bool = true

	func get_hit_flash() -> Node3D:
		return flash

	func is_alive() -> bool:
		return alive


## Pull the trigger ONCE on a real in-tree Attack wielding `weapon`, and report whether the wielder's full-screen hit
## flash came up. The Attack joins the tree (its fire path creates timers and checks is_inside_tree) with a ShellImpact
## child for its @onready read and its own cadence Timers; the clip and hub stay off-tree. The pull runs synchronously
## up to the 85 ms flash await, where the flash state is read. The wielder then "dies", so the resumed beat takes
## Attack's abort (clearing the flash) instead of the world-side shot (raycasts, audio), and the helper waits it out
## before freeing anything.
func _trigger_pull_shows_hit_flash(weapon: WeaponData) -> bool:
	var wielder := _FlashWielder.new()
	wielder.flash = Sprite3D.new()
	wielder.flash.visible = false
	var hub := Inventory.new()
	hub.equipped_weapon = weapon
	var clip := Ammo.new()
	clip.current_weapon = weapon
	var atk := Attack.new()
	atk.inventory = hub
	atk.character = wielder
	atk.clip = clip
	var shell := AudioStreamPlayer3D.new()
	shell.name = "ShellImpact"
	atk.add_child(shell)
	for slot in [&"attack", &"reload", &"swap"]:
		var t := Timer.new()
		t.one_shot = true
		atk.add_child(t)
		atk.set(slot, t)
	add_child(atk)
	atk.set_physics_process(false)  # its per-frame body only polls the real mouse buttons
	atk._on_mouse_input_attack(null)
	var shown := wielder.flash.visible
	wielder.alive = false
	await wait_seconds(0.2)
	assert_false(wielder.flash.visible, "cleanup: the aborted beat must have cleared the flash before the harness is freed")
	atk.free()
	clip.free()
	hub.free()
	wielder.flash.free()
	wielder.free()
	return shown

func test_a_punch_never_shows_the_fullscreen_hit_flash() -> void:
	# Fists are hitscan, so without this exemption every swing popped the camera's white hit-flash — a per-punch
	# screen strobe. Driven through the real trigger pull with the Accessibility "Screen Flashes" toggle ON, so the
	# only thing that can hide the flash is the punch exemption. Both weapons are the shipped fists with the wind-up
	# zeroed (so the pull reaches the flash without an earlier await); the control differs ONLY in view_model_punch.
	Settings.screen_flash_enabled = true
	var punch := (_fists().duplicate() as WeaponData)
	punch.attack_windup = 0.0
	assert_true(punch.view_model_punch and punch.projectile_life_time <= 0.0,
		"sanity: the fists are a hitscan punch, the one kind of swing that reaches the hit-flash branch and is exempt from it")
	var swing := (punch.duplicate() as WeaponData)
	swing.view_model_punch = false
	assert_true(await _trigger_pull_shows_hit_flash(swing),
		"control: the same hitscan swing NOT flagged as a punch does pop the full-screen flash with Screen Flashes on")
	assert_false(await _trigger_pull_shows_hit_flash(punch),
		"a view_model_punch swing must never show the full-screen hit flash, even with Screen Flashes on")
	punch = null
	swing = null

# --- The placeholder trap ---------------------------------------------------------------------------

func test_a_missing_view_model_never_reveals_the_placeholder_pistol() -> void:
	# THE regression that makes "unarmed" hand you a gun. The rig's built-in Sketchfab_Scene is an instance of
	# silenced.tscn, so equipping a weapon with no view model must leave that placeholder HIDDEN — driven on a bare
	# gun rig carrying a stand-in placeholder (a mesh) and its muzzle FX (which must never be touched).
	var gun := GunMesh.new()
	var placeholder := Node3D.new()
	placeholder.name = "Sketchfab_Scene"
	gun.add_child(placeholder)
	var pistol_mesh := MeshInstance3D.new()
	pistol_mesh.mesh = BoxMesh.new()
	placeholder.add_child(pistol_mesh)
	var muzzle := Node3D.new()
	muzzle.name = "PlayerMuzzle"
	placeholder.add_child(muzzle)
	var flash := MeshInstance3D.new()
	flash.mesh = BoxMesh.new()
	muzzle.add_child(flash)
	var hub := Inventory.new()
	hub.equipped_weapon = _fists()
	gun.inventory = hub
	var swapper := WeaponModelSwapper.new()
	swapper.host = gun
	assert_true(pistol_mesh.mesh != null, "sanity: the placeholder pistol starts out drawn")
	swapper.equip()
	assert_null(pistol_mesh.mesh,
		"equipping UNARMED must hide the placeholder — it is a silenced pistol, and unarmed has no view model")
	assert_true(flash.mesh != null, "the muzzle FX under the placeholder must be left alone")
	assert_eq(swapper.mounted_weapon(), _fists(), "the swapper must stamp FISTS as mounted even though there is no scene")
	swapper.equip()  # a second no-model equip (fists -> fists, or a swap that lands on unarmed again)
	assert_null(pistol_mesh.mesh, "a repeat unarmed equip must never bring the placeholder pistol back")
	swapper.free()
	gun.free()
	hub.free()

# --- The Player-side wiring --------------------------------------------------------------------------

func test_the_player_shows_and_punches_with_its_own_hands() -> void:
	# The COMPONENT half, driven: with FISTS equipped and unholstered, the refresh the host calls raises THE arms
	# rig as fists, and a swing strikes that rig with the hand the mouse picked. Holstered, the same swing does not.
	var rig := BodyModelSwap.new()
	add_child_autofree(rig)
	rig.visible = false  # built hidden, exactly as _build_first_person_arms leaves it
	var parts := _fists_harness(rig, true)
	var body = parts["body"]
	var atk: Attack = parts["atk"]
	body.refresh_unarmed_hands()
	assert_true(body._unarmed_hands_up, "FISTS equipped + unholstered: the refresh must raise the bare fists")
	assert_true(rig.visible, "...and put the arms rig on screen")
	atk.last_attack_alt = false
	body.on_attack_play_animation()
	assert_eq(rig._strike_t, 1.0, "a punch must drive the hands' own strike — without it the swing has no animation at all")
	assert_eq(rig._strike_side, 1.0, "the primary button throws the LEFT fist")
	atk.last_attack_alt = true
	body.on_attack_play_animation()
	assert_eq(rig._strike_side, -1.0, "the alt button (right click) throws the RIGHT fist")
	atk.holstered = true
	body.refresh_unarmed_hands()
	assert_false(body._unarmed_hands_up, "holstering must put the fists away")
	rig._strike_t = 0.0
	body.on_attack_play_animation()
	assert_eq(rig._strike_t, 0.0, "hands that are not up as fists (stowed, or holding a prop) must never swing")
	_teardown(parts)
	# The HOST half: Player._ready makes these connections and a unit test must not run Player._ready (it builds
	# weapons, nav and audio), so they are pinned by source — the tests/test_npc_home_return.gd idiom.
	var src := FileAccess.get_file_as_string(PLAYER_SOURCE)
	assert_true(src.contains("weapon_system.attack.swap_finished.connect(fp_body.refresh_unarmed_hands)"),
		"the Player must refresh the fists when a weapon swap lands — drop it and the fists never move")
	assert_true(src.contains("weapon_system.attack.play_animation.connect(fp_body.on_attack_play_animation)"),
		"the punch must hang off Attack.play_animation, the one per-swing signal")

func test_the_fists_rest_closer_to_the_camera_than_the_carry_hold() -> void:
	# The GUARD geometry, pinned because it is counter-intuitive and was tuned by rendering it (the fists-frame
	# probe, 2026-08-05): the shoulders DROP while a rig tilt swings the arms up, so the fists rise into the lower
	# third FORESHORTENED — that foreshortening is what reads as "fists close". Off-tree FirstPersonBody instance —
	# _ready never runs; every helper here is pure math over exports + the latch, no host needed. (The AUTHORED
	# Player.tscn numbers get the same relations in tests/test_first_person_body_wiring.gd.)
	var p = load(FP_BODY_SOURCE).new()
	var carry: Vector3 = p._fp_arm_rest()
	assert_eq(carry, p.fp_arm_offset,
		"with the fists down the hands must rest at the carry hold (fp_arm_offset), unchanged")
	assert_eq(p._fp_arm_rest_tilt(), 0.0,
		"and rest FLAT — the carry hold reaches for a prop, it doesn't guard")
	assert_eq(p._fp_arm_rest_scale(), p.fp_arm_scale,
		"and at the authored carry scale — the hold must stay sized to the props it reaches for")
	assert_eq(p._fp_arm_rest_spread(), p.fp_arm_spread,
		"and at the authored carry spread — the hold's hands sit where the held prop is")
	p._unarmed_hands_up = true
	var guard: Vector3 = p._fp_arm_rest()
	assert_gt(guard.z, carry.z,
		"the guard must sit NEARER the lens (+Z is toward the camera) than the carry hold")
	assert_gt(p._fp_arm_rest_tilt(), 0.0,
		"the guard must tip the rig UP from the flat carry hold — the tilt is what foreshortens the fists toward the lens")
	assert_gt(p._fp_arm_rest_scale(), p.fp_arm_scale,
		"the guard must scale the fists UP (fp_arm_unarmed_scale_mult > 1) — the size boost on top of the foreshortening")
	assert_gt(p._fp_arm_rest_spread(), p.fp_arm_spread,
		"the guard must spread WIDER than the carry hold, so the two fists read distinct and never cover the crosshair")
	# RELATIVE on purpose: retuning the carry rest must move the guard with it (one knob, no second rig to re-pose).
	var shift := Vector3(0.05, -0.2, 0.3)
	p.fp_arm_offset += shift
	var guard_moved: Vector3 = p._fp_arm_rest()
	assert_true(guard_moved.is_equal_approx(guard + shift),
		"moving the carry rest by %s must move the guard by the same amount (guard %s -> %s)" % [shift, guard, guard_moved])
	p.free()
	# "SHIP with" means what Player.tscn ships: its FirstPersonBody authors its own fp_arm_unarmed_bob_pos, so the
	# script default says nothing about the shipped walk-bob. Each value is the scene's override when it has one,
	# else the default an untouched instance carries.
	var fresh = load(FP_BODY_SOURCE).new()
	var bob_pos: float = _shipped_fp_body_value(fresh, "fp_arm_unarmed_bob_pos")
	var breath_pos: float = _shipped_fp_body_value(fresh, "fp_arm_unarmed_breath_pos")
	var stride_deg: float = _shipped_fp_body_value(fresh, "fp_arm_unarmed_stride_deg")
	fresh.free()
	assert_gt(bob_pos, 0.0,
		"the fists must ship with a walk-bob (Player.tscn's fp_arm_unarmed_bob_pos %s > 0) — like every mounted weapon's GunPose bob" % bob_pos)
	assert_gt(breath_pos, 0.0,
		"and with an idle breath (shipped fp_arm_unarmed_breath_pos %s > 0) — standing guard must read alive, not statue hands" % breath_pos)
	assert_gt(stride_deg, 0.0,
		"and with a walking arm-pump (shipped fp_arm_unarmed_stride_deg %s > 0) — the fists alternate, not bob in lockstep" % stride_deg)
	# ...and the arm-pump must ALTERNATE on the rig itself: left rises as right falls. Measured on a live pair.
	var rig := BodyModelSwap.new()
	rig.animate_arms = false
	rig.arm_model = load(ARM_MODEL)
	add_child_autofree(rig)
	rig.arm_rotation = Vector3(0.0, 180.0, 0.0)
	rig.arm_scale = 0.5
	rig.arm_position = Vector3(0.2, 0.0, 0.0)
	var reach := rig._arm_reach_measured()
	assert_gt(reach, 0.0, "the shipped arm model must measure a reach")
	var tip := Vector3(0.0, 0.0, reach)
	var left_rest: Vector3 = rig._arm_left.transform * tip
	var right_rest: Vector3 = rig._arm_right.transform * tip
	rig.arm_stride_deg = 10.0
	var left_dy: float = (rig._arm_left.transform * tip).y - left_rest.y
	var right_dy: float = (rig._arm_right.transform * tip).y - right_rest.y
	assert_true(absf(left_dy) > 0.001 and absf(right_dy) > 0.001, "a 10 degree stride must actually move both fists")
	assert_lt(left_dy * right_dy, 0.0,
		"the stride must be ANTISYMMETRIC — one fist up while the other goes down (dy %s / %s); a shared sign is just more bob" % [left_dy, right_dy])

func test_the_stow_sinks_straight_down_from_whatever_pose_it_leaves() -> void:
	# The 2026-08-09 report: "when holstering my unarmed fists it doesn't go down — they extend outward first
	# and then disappear." The stow target was hardcoded to `fp_arm_offset - fp_arm_draw_rise`, anchored to the
	# CARRY rest on the (once true) reasoning that it was the lower of the two rests. The guard nudge is
	# negative in Y and large in +Z, so at the AUTHORED pose that anchor sat ABOVE the guard and 1.49 m toward
	# the lens: holstering RAISED the fists and threw them a metre and a half forward, then blinked them off at
	# peak size — a reach, not a stow. Render-proven.
	#
	# ⭐This is why the pin drives ARBITRARY poses rather than the script defaults: at the DEFAULT nudge the
	# carry anchor really is below the guard, so the bug was invisible off-tree and only ever showed against
	# Player.tscn's authored numbers (on the FirstPersonBody child, since the extraction). And it drives the REAL
	# stow, _slide_fp_arms(false) with the component in-tree so its Tween exists, stepping that Tween by hand: the
	# old mis-anchor lived at the call site, so re-anchoring the stow to a named rest there, or inside
	# fp_arm_stow_target, lands the hands somewhere other than straight below these poses and fails here.
	var rig := BodyModelSwap.new()
	add_child_autofree(rig)
	var parts := _fists_harness(rig, true)
	var body = parts["body"]
	var rise: float = body.fp_arm_draw_rise
	var slide: float = body.fp_arm_draw_time
	assert_true(rise > 0.0 and slide > 0.0, "sanity: the stow must have a rise to sink by and a time to take")
	body._unarmed_hands_up = false  # by stow time the refresh has already flipped the latch to the next mode
	for pose in [Vector3(0.0, -1.83, 1.745), Vector3(0.4, 2.0, -3.0)]:
		rig.visible = true
		rig.position = pose
		body._slide_fp_arms(false)
		var tween: Tween = body._fp_arm_tween
		assert_true(tween != null and tween.is_valid(), "stowing visible hands at %s must start a slide" % pose)
		if tween == null or not tween.is_valid():
			continue
		tween.custom_step(slide * 0.5)
		assert_almost_eq(rig.position.x, pose.x, 0.00001,
			"mid-stow the hands must not travel SIDEWAYS from %s — x stays the pose's, whatever rest it left" % pose)
		assert_almost_eq(rig.position.z, pose.z, 0.00001,
			"...nor in DEPTH — a z shift is the fists reaching outward / away, the reported bug (from %s)" % pose)
		assert_lt(rig.position.y, pose.y,
			"...and already on the way DOWN from %s — a stow that rises first is a draw with the frames reversed" % pose)
		tween.custom_step(slide)  # past the end: the sink lands and its tail switches the rig off
		assert_true(rig.position.is_equal_approx(pose - Vector3(0.0, rise, 0.0)),
			"the stow must end exactly fp_arm_draw_rise straight BELOW where the hands were (%s -> %s)" % [pose, rig.position])
		assert_false(rig.visible, "only once the sink has landed does the stow switch the hands off")
	_teardown(parts)

# --- The walk-bob anti-jitter contract ---------------------------------------------------------------

func test_the_bob_phase_only_advances_and_stays_bounded() -> void:
	# This is the 2026-08-08 "the fists jitter while walking" regression, pinned.
	#
	# The phase used to be EASED TOWARD ZERO on any frame that wasn't "grounded and moving". A phase grows
	# without bound while you walk, so that lerp moved it TENS OF RADIANS in a single frame — whole bob cycles.
	# And `is_on_floor()` blips false for single frames constantly while genuinely walking (brush seams, the
	# 0.5 m stair risers, any bump), so every blip teleported the hands to an unrelated point in the walk cycle.
	# Measured on the shipped rig that was a 6.3 deg one-frame stride snap = 0.32 m of fist travel; the fix
	# brings the worst single-frame step to 0.42 deg = 0.021 m, i.e. the normal walk cadence.
	var script := load(FP_BODY_SOURCE)
	var dt := 1.0 / 60.0
	var speed := 8.0  # GameSettings.camera.bob_speed default
	# 60 s of walking — the phase must stay small, not drift into the hundreds.
	var phase := 0.0
	for i in 3600:
		phase = script.advance_bob_phase(phase, speed, dt, true)
	assert_between(phase, 0.0, TAU * 2.0,
		"the walk-bob phase must stay WRAPPED inside one half-rate period (TAU*2), however long you walk")
	# The load-bearing one: a non-advancing frame must HOLD the phase, never ease it toward zero.
	var held: float = script.advance_bob_phase(phase, speed, dt, false)
	assert_eq(held, phase,
		"a non-advancing frame must HOLD the phase — easing a PHASE toward zero is what made a one-frame is_on_floor() blip teleport the fists mid-stride")
	# And an advancing frame moves it by exactly one step (never backwards by a jump).
	var stepped: float = script.advance_bob_phase(phase, speed, dt, true)
	assert_almost_eq(absf(wrapf(stepped - phase, -PI, PI)), dt * speed, 0.0001,
		"an advancing frame must move the phase by exactly delta * bob_speed")

func test_the_bob_cadence_scales_with_speed_and_has_a_true_off_position() -> void:
	# "I want the fists bobbing to actually scale with how fast the player moves" (2026-08-09). Amplitude
	# already scaled; the CADENCE was flat, so a walk and a sprint traced the same figure-eight at the same
	# footstep rate — one gait at two volumes.
	var script := load(FP_BODY_SOURCE)
	var base := 8.0  # GameSettings.camera.bob_speed default
	# gain 0 is a TRUE off switch: the flat rate at every speed, i.e. the behaviour this replaced, bit for bit.
	for ratio in [0.0, 0.5, 1.0, 3.0]:
		assert_almost_eq(script.bob_cadence(base, ratio, 0.0), base, 0.00001,
			"gain 0 must return the flat authored rate at EVERY speed — the knob's off position must not drift")
	# Monotone in speed, and a walk must be visibly slower than a run (that gap IS the feature).
	var walk: float = script.bob_cadence(base, 0.7, 0.7)   # walk_speed_mult
	var run: float = script.bob_cadence(base, 1.0, 0.7)
	assert_lt(walk, run, "a walk must pump SLOWER than a run")
	assert_almost_eq(run, base, 0.00001,
		"the run tier must land on the authored rate exactly — the knob retimes the tiers around it, not past it")
	# A boost stack speeds it up but can never strobe: the ceiling only opens as far as the designer's gain.
	var bhop: float = script.bob_cadence(base, 12.0, 0.7)
	assert_gt(bhop, run, "a bhop-boosted sprint must pump faster than the run tier")
	assert_lte(bhop, base * (1.0 + 0.7 * 2.0) + 0.00001,
		"...but stay under the gain-proportional ceiling — an unclamped rate blurs the arms")

func test_the_bob_leans_against_the_direction_of_travel() -> void:
	# The other half of the same ask ("...which direction"). Inertia: the pair drifts AGAINST the move, the
	# same sign rule HudSway.velocity_target uses for the corner HUD.
	var script := load(FP_BODY_SOURCE)
	var travel := 0.127  # Player.tscn's FirstPersonBody fp_arm_unarmed_bob_pos — the authored value, not the script default
	var mult := Vector2(0.6, 0.4)
	assert_lt(script.bob_lean(1.0, 0.0, travel, mult).x, 0.0,
		"strafing RIGHT must drift the fists LEFT — leaning INTO the move reads as the hands leading the body")
	assert_gt(script.bob_lean(-1.0, 0.0, travel, mult).x, 0.0, "and strafing left, right — the read is symmetric")
	assert_gt(script.bob_lean(0.0, 1.0, travel, mult).z, 0.0,
		"running FORWARD must trail the fists back toward the lens (+Z is behind the camera)")
	assert_lt(script.bob_lean(0.0, -1.0, travel, mult).z, 0.0, "and backpedalling must press them away from it")
	assert_eq(script.bob_lean(0.0, 0.0, travel, mult), Vector3.ZERO, "standing still must not lean at all")
	assert_eq(script.bob_lean(1.0, 1.0, travel, Vector2.ZERO), Vector3.ZERO,
		"and a zeroed multiplier must be direction-blind — the knob needs an off position too")
	# The lean is a MULTIPLE of the bob travel on purpose: absolute metres would stop reading the next time
	# the guard pose (and with it every depth-coupled travel knob) is retuned.
	var doubled: Vector3 = script.bob_lean(1.0, 1.0, travel * 2.0, mult)
	assert_almost_eq(doubled.x, script.bob_lean(1.0, 1.0, travel, mult).x * 2.0, 0.00001,
		"the lean must scale with fp_arm_unarmed_bob_pos — it is expressed relative to the bob travel")
	# Ratios clamp at the run tier: a boost buys cadence, never more reach on a ~2.9 m lever.
	assert_eq(script.bob_lean(9.0, 9.0, travel, mult), script.bob_lean(1.0, 1.0, travel, mult),
		"a bhop-boosted ratio must clamp to the run tier's lean — unclamped travel is how the 08-08 stride popped")

func test_the_walk_bob_amplitude_is_eased_not_stepped() -> void:
	# The phase fix above is only half of it: the AMPLITUDE must ease too. Taking the raw grounded-and-moving gate
	# as the amplitude meant one blip frame drove the arm-pump to zero and the next drove it back to full — a
	# ±fp_arm_unarmed_stride_deg snap on a ~2.9 m lever. Driven through the real per-frame update: fists up and
	# mid-walk at full amplitude, then ONE frame whose gate reads zero (an off-tree host is never on the floor and
	# is standing still — exactly what an is_on_floor() blip looks like to this code).
	Settings.view_bob_enabled = false  # skips only the velocity LEAN, whose body-yaw read needs an in-tree host; the gate is zero regardless
	var rig := BodyModelSwap.new()
	var parts := _fists_harness(rig, false)
	var body = parts["body"]
	var mount := Node3D.new()
	body._fp_arm_bob_mount = mount
	body._unarmed_hands_up = true
	body._fp_bob_gate = 1.0
	body._fp_bob_amp = 1.0
	body._fp_bob_time = TAU  # a stride zero-crossing, so the pump's own TARGET this frame is ~0
	rig.arm_stride_deg = 7.0
	var dt := 1.0 / 60.0
	body._update_fp_arm_bob(dt)
	assert_gt(body._fp_bob_amp, 0.5,
		"one zero-gate frame must only EASE the walk-bob amplitude down (got %s) — snapping it to zero is the jitter" % body._fp_bob_amp)
	assert_lt(body._fp_bob_amp, 1.0, "...but it must start easing toward the new gate, not hold")
	assert_gt(rig.arm_stride_deg, 3.5,
		"the arm-pump must be written SMOOTHED (got %s deg) — a raw write pops the whole pair on a single-frame change" % rig.arm_stride_deg)
	assert_almost_eq(body._fp_bob_time, TAU, 0.00001,
		"a non-advancing frame must HOLD the bob phase in the live update too — never lerp it toward zero")
	for i in 180:
		body._update_fp_arm_bob(dt)
	assert_lt(body._fp_bob_amp, 0.01, "held at zero, the eased amplitude must actually settle out (3 s)")
	assert_lt(absf(rig.arm_stride_deg), 0.05, "...and the smoothed pump with it")
	mount.free()
	rig.free()
	_teardown(parts)

func test_the_fists_stay_down_while_a_real_weapon_is_mid_draw() -> void:
	# The bare-fist FLASH fix (the H toggle's put-back): between the carry release and the rewield landing, the
	# combat inventory still reads FISTS + unholstered — exactly the state that raises the fists — so
	# _unarmed_hands_wanted() must refuse while either suppressor is up: the player's _rewield_in_flight latch
	# (stash_held_item's synchronous release→equip span) or the BACKPACK's optimistic equipped_item (a
	# real-weapon draw QUEUED behind a mid-flight swap lands frames later). Off-tree: the FirstPersonBody with
	# a bare host Player + Weapon hub + BodyModelSwap wired by hand, _ready never runs on any of them (the
	# test_player_core idiom) — the component READS the suppressors off its host, it holds none itself.
	var p = load(PLAYER_SOURCE).new()
	var body = load(FP_BODY_SOURCE).new()
	body.host = p
	var ws := Weapon.new()
	var hub := Inventory.new()
	ws.inventory = hub
	p.weapon_system = ws
	var arms := BodyModelSwap.new()
	body._fp_arms = arms
	hub.equipped_weapon = _fists()
	assert_true(body._unarmed_hands_wanted(),
		"baseline: FISTS equipped, unholstered, empty-handed — the fists are wanted")
	p._rewield_in_flight = true
	assert_false(body._unarmed_hands_wanted(),
		"the put-back's release→equip window must suppress the fists — this IS the flash fix")
	p._rewield_in_flight = false
	var bag := CharacterInventory.new()
	p.inventory = bag
	assert_true(body._unarmed_hands_wanted(),
		"an empty backpack equipped-marker changes nothing — genuine unarmed still raises the fists")
	var knife := Item.new()
	knife.category = Item.Category.WEAPON
	knife.weapon = WeaponData.new()
	bag.equipped_item = knife  # the optimistic marker a queued draw leaves while equipped_weapon still reads FISTS
	assert_false(body._unarmed_hands_wanted(),
		"a bag weapon MID-DRAW (equipped_item set, combat hub still FISTS) must suppress the fists too")
	body.free()  # component first, host after — neither is in-tree, so the order is hygiene, not load-bearing
	p.free()
	ws.free()
	hub.free()
	arms.free()
	bag.free()

func test_a_stow_freezes_the_guard_pose() -> void:
	# Holstering the fists used to morph them into the flat carry reach WHILE they sank out of frame — the latch
	# flips to carry-mode at stow start, and the per-frame pose ease chased it on screen (the reported
	# "holding-items arm flash" on holster). A stow must FREEZE the pose (sink AS fists); once the stow's tail has
	# hidden the rig, easing resumes (the next draw re-poses from scratch anyway).
	var rig := BodyModelSwap.new()
	add_child_autofree(rig)
	var parts := _fists_harness(rig, true)
	var body = parts["body"]
	var guard_scale: float = body.fp_arm_scale * body.fp_arm_unarmed_scale_mult
	var guard_spread: float = body.fp_arm_unarmed_spread
	assert_true(guard_scale > body.fp_arm_scale and guard_spread > body.fp_arm_spread,
		"sanity: the guard and carry poses must differ, or a freeze is unobservable")
	rig.visible = true
	rig.arm_scale = guard_scale
	rig.arm_position = Vector3(guard_spread, 0.0, 0.0)
	body._unarmed_hands_up = false  # refresh has already flipped the latch to the mode we are stowing FOR
	body._slide_fp_arms(false)
	body._update_fp_arm_bob(0.1)
	assert_almost_eq(rig.arm_scale, guard_scale, 0.00001,
		"mid-stow the per-frame ease must NOT pull the fists toward the carry scale — they sink AS fists")
	assert_almost_eq(rig.arm_position.x, guard_spread, 0.00001, "...nor toward the carry spread")
	body._hide_fp_arms()  # the stow's tail: fully out of frame, pose easing may resume
	body._update_fp_arm_bob(0.1)
	assert_lt(rig.arm_scale, guard_scale, "control: once the stow has finished the ease DOES pull toward the carry rest")
	assert_lt(rig.arm_position.x, guard_spread, "control: ...spread included")
	_teardown(parts)

func test_the_fists_wear_the_weapon_look() -> void:
	# The gun view model's dress pass (GunVisuals: rim light + the view-model outline, shadows off) is stamped onto
	# the FP arms rig too, so bare fists read as first-class view-model gear beside an outlined gun, not raw skin.
	# Built IN-TREE, the way Player._ready builds it: an off-tree BodyModelSwap never instances its arm pair and an
	# off-tree GunVisuals never builds its rim material, so off-tree the dress has nothing to land on and nothing to
	# stamp — a rig that was never dressed would look identical. The camera's processing is OFF (its _process reads
	# a live player) and the test never yields a frame, so nothing but the build itself runs.
	var host = load(PLAYER_SOURCE).new()
	var camera := CameraEffects.new()
	camera.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(camera)
	host.camera_effects = camera
	var body = load(FP_BODY_SOURCE).new()
	body.host = host
	body._build_first_person_arms()
	var rig: BodyModelSwap = body._fp_arms
	assert_true(rig != null, "the carry/fists arms rig must build under a camera")
	var visuals: GunVisuals = rig.get_node_or_null("FistVisuals") as GunVisuals if rig != null else null
	assert_true(visuals != null, "the arms rig must carry a GunVisuals dress child — the same look pass as every weapon view model")
	if rig != null and visuals != null:
		assert_eq(visuals.host, rig, "...dressing THE arms rig, so the rim and outline land on the fists")
		var rim: ShaderMaterial = visuals._rim_material
		assert_true(rim != null, "the dress child must have built its rim material by the time the build returns")
		var dressed := _arm_meshes(rig)
		assert_gt(dressed.size(), 0, "the in-tree build must instance the arm pair's meshes, or there is nothing to dress")
		for mi in dressed:
			assert_almost_eq(_outline_id(mi), float(InkOutline.TINT_ID_VIEW_MODEL), 0.001,
				"arm mesh %s must wear the VIEW-MODEL outline ring — the gun's only outline, and the fists' beside it" % mi.name)
			assert_true(rim != null and _rim_passes(mi).has(rim),
				"arm mesh %s must chain the shared rim light onto what it draws with — without it the fists are raw skin beside a rim-lit gun" % mi.name)
		# CONTROL: the same arm pair on a rig configured exactly as the build configures it, in the same camera, but
		# never dressed. It must show NEITHER mark — so the look above is the dress pass's doing, not the rig's own.
		var bare := BodyModelSwap.new()
		bare.casts_shadow = false
		bare.animate_arms = false
		bare.view_model_layer = ViewModelCamera.VIEW_MODEL_LAYER
		bare.arm_model = body.fp_arm_model
		bare.arm_color = rig.arm_color
		camera.add_child(bare)
		var undressed := _arm_meshes(bare)
		assert_eq(undressed.size(), dressed.size(), "control: the undressed pair must instance the same meshes")
		for mi in undressed:
			assert_almost_eq(_outline_id(mi), float(InkOutline.TINT_ID_NONE), 0.001,
				"control: undressed arm mesh %s must carry no outline ring of its own" % mi.name)
			assert_eq(_rim_passes(mi).size(), 0, "control: undressed arm mesh %s must carry no rim light of its own" % mi.name)
	body.free()
	camera.free()
	host.free()
	# ...and the rim must survive the arm TINT: BodyModelSwap colours arms through material_override, which outranks
	# every per-surface material, so a rim chained per-surface would silently vanish on a customised arm colour.
	var dresser := GunVisuals.new()
	add_child_autofree(dresser)  # _ready builds the shared rim material
	var tinted_arm := MeshInstance3D.new()
	tinted_arm.mesh = BoxMesh.new()
	var tint := StandardMaterial3D.new()
	tinted_arm.material_override = tint
	dresser.dress(tinted_arm)
	var dressed := tinted_arm.material_override
	assert_true(dressed != null and dressed.next_pass == dresser._rim_material,
		"the rim must chain onto a mesh's material_override when one exists — a customised arm colour must keep the rim")
	assert_null(tint.next_pass, "...on a per-instance duplicate, never the shared tint material")
	var bare_arm := MeshInstance3D.new()
	bare_arm.mesh = BoxMesh.new()
	dresser.dress(bare_arm)
	var surface := bare_arm.get_surface_override_material(0)
	assert_true(surface != null and surface.next_pass == dresser._rim_material,
		"control: an untinted mesh takes the rim per-surface")
	tinted_arm.free()
	bare_arm.free()

func test_the_unarmed_hands_are_the_carry_hands() -> void:
	# The reuse IS the fix: a separate rig under the gun would lose the arm tint, sit off-centre and inherit the
	# holster tip. So the build must produce ONE arms rig under the camera, and the punch knobs must land on that
	# very rig — the one the carry relay and the fists refresh both drive (_fp_arms).
	var host = load(PLAYER_SOURCE).new()
	var camera := CameraEffects.new()
	host.camera_effects = camera
	var body = load(FP_BODY_SOURCE).new()
	body.host = host
	body.fp_arm_punch_pitch = -12.5  # distinctive, so a match can't be a coincidence with a BodyModelSwap default
	body.fp_arm_punch_duration = 0.27
	body.fp_arm_punch_thrust = Vector3(-0.01, 0.03, -0.2)
	body.fp_arm_punch_offhand = 0.33
	body._build_first_person_arms()
	var rigs: Array[BodyModelSwap] = []
	var stack: Array[Node] = [camera]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is BodyModelSwap:
			rigs.append(n as BodyModelSwap)
	assert_eq(rigs.size(), 1, "exactly ONE arms rig may hang under the camera — a second one is the regression")
	var rig: BodyModelSwap = body._fp_arms
	assert_true(rig != null and rigs.has(rig), "that rig must be the component's _fp_arms, the one carry and fists share")
	if rig != null:
		assert_false(rig.visible, "it builds HIDDEN — hands appear only when carrying or when the fists come up")
		assert_eq(rig.view_model_layer, ViewModelCamera.VIEW_MODEL_LAYER, "it draws in the gun's view-model pass (no wall clipping)")
		assert_almost_eq(rig.arm_strike_pitch, -12.5, 0.0001, "the punch pitch must be stamped onto THAT rig")
		assert_almost_eq(rig.arm_strike_duration, 0.27, 0.0001, "...and the punch duration")
		assert_true(rig.arm_strike_thrust.is_equal_approx(Vector3(-0.01, 0.03, -0.2)), "...and the thrust")
		assert_almost_eq(rig.arm_strike_offhand_scale, 0.33, 0.0001, "...and the off-hand share")
	body.free()
	camera.free()
	host.free()

# --- Every OTHER weapon must be unaffected ----------------------------------------------------------

func test_real_weapons_still_mount_their_own_model() -> void:
	var dir := DirAccess.open(WEAPONS_DIR)
	assert_not_null(dir, "resources/weapons/ must exist")
	var checked := 0
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".tres"):
			var path := WEAPONS_DIR + name
			if path != FISTS_PATH:
				var wd := load(path) as WeaponData
				if wd != null:
					checked += 1
					assert_not_null(wd.view_model,
						"%s is a real weapon and must mount a view model — a null one now shows nothing at all" % name)
					assert_false(wd.view_model_is_first_person_only,
						"%s must NOT be first-person-only — it would vanish from NPC hands and the ground" % name)
					assert_false(wd.view_model_punch,
						"%s is not a punch — flagging it would kick the gun FORWARD instead of recoiling" % name)
					assert_eq(wd.held_view_model(), wd.view_model,
						"%s must hand out its normal view model to NPCs / drops / the grid" % name)
					wd = null
		name = dir.get_next()
	dir.list_dir_end()
	assert_gt(checked, 0, "the sweep must actually find the other weapon resources")
