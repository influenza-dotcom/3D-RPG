extends GutTest

## THE WEAPON HOLD: your own hands on the gun you are holding, in first person
## (`FirstPersonBody.weapon_hands`, 2026-09-14 — "let us see the player character's hands when they're holding
## the weapons, similarly to how npcs hold their weapons").
##
## It is the NPC hand-hold seam run BACKWARDS, and that is the thing worth pinning. An NPC's arms are
## authoritative and its weapon is moved to `BodyModelSwap.weapon_grip_position()` (npc.gd `weapon_in_hands`);
## in first person the GUN is authoritative — GunPose owns its sway / ADS / recoil every frame — so the same
## grip is SOLVED FOR and the hands are placed instead. One pose, never two that have to agree.
##
## Four things are pinned, each a way the feature silently stops working:
##   1. THE INVERSION itself (`weapon_hands_position`) — pure and static, so the algebra can be checked without
##      a rig. If it drifts, the hands float beside the weapon rather than on it.
##   2. THE MODE IS EXCLUSIVE. One rig serves three poses (carry hold / bare fists / weapon hold) and only the
##      weapon hold re-solves its transform every frame; the fists' walk-bob and rest-ease write the SAME
##      properties, so both have to yield to this latch or they fight frame by frame.
##   3. THE GATES. Every `_wanted` clause is a host read, and the component holds zero gameplay state.
##   4. THE AUTHORED GRIPS ARE REACHABLE. `WeaponData.view_model_grip` is per-weapon because these view models
##      share no origin — and a grip left at ZERO sits at the gun rig's own origin, which is ON the camera
##      plane: the hands would be solved to a point nothing can render. That is invisible in code review and
##      obvious in one render (scripts/tools/probes/preview_weapon_hands_frame.gd).
##
## Everything is DRIVEN. The live harness (_live) is: a bare player.gd host (off-tree, no `_ready`), the component
## in-tree with its own processing OFF (so its slides can create Tweens and nothing ticks unasked), a GunMesh
## in-tree with PROCESS_MODE_DISABLED (its `_ready` builds the swapper, but GunPose never runs — the test places
## the gun), and a bob mount + arms rig carrying the shipped arm model. Weapons are synthetic WeaponData, so no
## authored flag on a shipped .tres can quietly change what a gate test is testing.

const FP_BODY_SOURCE := "res://scripts/player/first_person_body.gd"
const PLAYER_SOURCE := "res://scripts/player/player.gd"
const CAMERA_RIG := "res://scenes/player/camera_rig.tscn"
const ARM_MODEL := "res://assets/models/arm.blend"
const FISTS_PATH := "res://resources/weapons/fists.tres"
## Every shipped weapon that mounts a view model. fists.tres is excluded on purpose — it is
## `view_model_is_first_person_only`, i.e. the bare-fists rig, which is the OTHER pose of this same rig.
const WEAPONS := [
	"res://resources/weapons/pistol.tres",
	"res://resources/weapons/smg.tres",
	"res://resources/weapons/shotgun.tres",
	"res://resources/weapons/sniper_wep.tres",
	"res://resources/weapons/melee.tres",
	"res://resources/weapons/rock_weapon.tres",
	"res://resources/weapons/spray_paint.tres",
]
## How far in FRONT of the lens an authored grip must land (metres). The camera's near plane is 0.05 and the
## frustum is a point at the eye, so a grip closer than this is outside the view however wide the FOV — the
## hands would be solved onto somewhere nothing draws. Deliberately a floor, not a target: framing is a
## judgement made by rendering, this only catches "nobody authored a grip for the new weapon".
const MIN_GRIP_DEPTH := 0.10


## A synthetic weapon that mounts a (blank) view model — enough for every gate, which only asks "is there one".
func _weapon(grip: Vector3, one_handed: bool = false, hand_scale: float = 1.0) -> WeaponData:
	var wd := WeaponData.new()
	wd.view_model = PackedScene.new()
	wd.view_model_grip = grip
	wd.view_model_one_handed = one_handed
	wd.view_model_hand_scale = hand_scale
	return wd


## The live weapon-hold harness (see the header). `mounted` is what the gun rig has on it AND what the combat
## inventory has equipped — tests that need the two to disagree (a swap in flight) change one of them.
## In the baseline every `_weapon_hands_wanted` clause passes. Caller frees via _teardown.
func _live(mounted: WeaponData) -> Dictionary:
	var host = load(PLAYER_SOURCE).new()
	var body = load(FP_BODY_SOURCE).new()
	body.host = host
	add_child_autofree(body)
	body.set_process(false)
	var gun := GunMesh.new()
	gun.process_mode = Node.PROCESS_MODE_DISABLED  # _ready still builds the swapper; GunPose never ticks
	gun.position = Vector3(0.19, -0.23, -0.19)
	add_child_autofree(gun)
	gun._swapper._mounted_weapon = mounted
	host.gun_mesh = gun
	var ws := Weapon.new()
	var hub := Inventory.new()
	var atk := Attack.new()
	ws.inventory = hub
	ws.attack = atk
	host.weapon_system = ws
	hub.equipped_weapon = mounted
	var mount := Node3D.new()
	add_child_autofree(mount)
	var rig := BodyModelSwap.new()
	rig.animate_arms = false
	rig.arm_model = load(ARM_MODEL)
	mount.add_child(rig)
	rig.arm_rotation = Vector3(0.0, 180.0, 0.0)  # hands down the camera's -Z, as _build_first_person_arms sets
	rig.arm_scale = 0.14
	rig.visible = false  # built hidden
	body._fp_arms = rig
	body._fp_arm_bob_mount = mount
	return {"host": host, "body": body, "gun": gun, "ws": ws, "hub": hub, "atk": atk, "mount": mount, "rig": rig}


## fists.tres is the SHARED cached resource (Player.FISTS preloads the same instance), and one gate test authors a
## view model on it to isolate the identity clause. Whatever it held going in is saved here and put back afterwards,
## even if the test bailed — never a hard-coded value, so a future authored model on fists survives the suite.
var _saved_fists_view_model: PackedScene


func before_each() -> void:
	_saved_fists_view_model = (load(FISTS_PATH) as WeaponData).view_model


func after_each() -> void:
	(load(FISTS_PATH) as WeaponData).view_model = _saved_fists_view_model
	_saved_fists_view_model = null


func _teardown(parts: Dictionary) -> void:
	var body = parts["body"]
	body.set_process(false)
	body._kill_fp_arm_tween()
	body.host = null
	(parts["host"] as Node).free()
	(parts["ws"] as Node).free()
	(parts["hub"] as Node).free()
	(parts["atk"] as Node).free()


## How far the grip the rig's arms form sits from the gun's anchor, in the bob mount's frame (metres). Zero is the
## whole feature: the hands ON the weapon.
func _grip_offset(parts: Dictionary) -> Vector3:
	var rig: BodyModelSwap = parts["rig"]
	var mount: Node3D = parts["mount"]
	var grip: Variant = rig.weapon_grip_position()
	var anchor: Variant = parts["body"]._weapon_hands_anchor()
	if grip == null or anchor == null:
		return Vector3.INF
	return rig.transform * (grip as Vector3) - mount.global_transform.affine_inverse() * (anchor as Vector3)


## The GunMesh's authored mount under the camera, read off camera_rig.tscn's scene state — the same transform
## the live `_weapon_hands_anchor` reads off the node and the frame probe reads off the text.
func _gun_mount() -> Transform3D:
	var ps := load(CAMERA_RIG) as PackedScene
	assert_not_null(ps, "camera_rig.tscn must load")
	var state := ps.get_state()
	for i in range(state.get_node_count()):
		if state.get_node_name(i) != "GunMesh":
			continue
		for p in range(state.get_node_property_count(i)):
			if state.get_node_property_name(i, p) == "transform":
				return state.get_node_property_value(i, p) as Transform3D
	fail_test("camera_rig.tscn must still author a GunMesh transform — the hands are solved against it")
	return Transform3D.IDENTITY


# --- 1. The inversion ---------------------------------------------------------------------------------------

## `rig.transform * grip == anchor` is the whole contract, and weapon_hands_position is the half that solves for
## the rig's ORIGIN. Checked by composing it back: whatever basis the rig wears, the grip its arms form must land
## on the anchor to floating-point — including a ZERO grip (a rebuilt-but-unmeasured rig), which must park the rig
## straight on the anchor rather than warp it.
func test_the_solved_position_puts_the_arms_grip_exactly_on_the_anchor() -> void:
	var cases := [
		[Vector3(0.19, -0.23, -0.19), Basis(), Vector3(0.0, 0.0, -0.27)],
		[Vector3(0.19, -0.23, -0.19), Basis.from_euler(Vector3(deg_to_rad(34.0), 0.0, 0.0)), Vector3(0.0, 0.0, -0.27)],
		[Vector3(-1.5, 2.25, 0.75), Basis.from_euler(Vector3(0.4, -1.1, 0.2)), Vector3(0.03, -0.01, -0.5)],
		[Vector3.ZERO, Basis.from_euler(Vector3(deg_to_rad(80.0), 0.0, 0.0)), Vector3.ZERO],
		[Vector3(1.0, 2.0, 3.0), Basis.from_euler(Vector3(0.3, 0.9, -0.4)), Vector3.ZERO],
	]
	for c in cases:
		var anchor: Vector3 = c[0]
		var basis: Basis = c[1]
		var grip: Vector3 = c[2]
		var origin := FirstPersonBody.weapon_hands_position(anchor, basis, grip)
		var landed := Transform3D(basis, origin) * grip
		assert_almost_eq(landed.x, anchor.x, 0.0001, "solved rig must put the grip on the anchor (x)")
		assert_almost_eq(landed.y, anchor.y, 0.0001, "solved rig must put the grip on the anchor (y)")
		assert_almost_eq(landed.z, anchor.z, 0.0001, "solved rig must put the grip on the anchor (z)")


# --- 2. The mode is exclusive -------------------------------------------------------------------------------

## The weapon hold re-solves position / tilt / scale / spread EVERY FRAME, and the fists' per-frame pose ease
## writes the same properties toward a fixed rest — so with the weapon latch up that ease must leave the rig
## alone, and the bob's closed-gate branch must not park the arm-pump property the solve also owns.
func test_the_fists_pose_ease_and_bob_yield_to_the_weapon_solve() -> void:
	var parts := _live(_weapon(Vector3(0.2, -0.02, 0.0)))
	var body = parts["body"]
	var rig: BodyModelSwap = parts["rig"]
	rig.visible = true
	body._weapon_hands_up = true
	rig.arm_scale = 0.05
	rig.arm_position = Vector3(0.02, 0.0, 0.0)
	rig.position = Vector3(0.1, -0.3, -0.4)
	rig.rotation_degrees = Vector3(62.0, 20.0, 0.0)
	rig.arm_stride_deg = 3.0
	body._update_fp_arm_bob(0.1)
	assert_almost_eq(rig.arm_scale, 0.05, 0.00001, "the fists' ease must not pull a weapon-held rig toward the carry scale")
	assert_almost_eq(rig.arm_position.x, 0.02, 0.00001, "...nor its spread")
	assert_true(rig.position.is_equal_approx(Vector3(0.1, -0.3, -0.4)), "...nor its position (the solve's hard write)")
	assert_almost_eq(rig.rotation_degrees.x, 62.0, 0.0001, "...nor its tilt")
	assert_almost_eq(rig.arm_stride_deg, 3.0, 0.00001, "the bob's closed gate must not park a property the weapon latch owns")
	body._weapon_hands_up = false
	body._update_fp_arm_bob(0.1)
	assert_gt(rig.arm_scale, 0.05, "control: with the weapon latch DOWN the same call eases the rig toward its rest")
	assert_almost_eq(rig.arm_stride_deg, 0.0, 0.00001, "control: ...and parks the arm-pump")
	_teardown(parts)


## The grip is a HARD write: a recoil kick that moves the gun in one frame must move the hands in that frame. Only
## the draw/handoff RESIDUAL (_weapon_hands_settle) eases, on top of a grip that is never lagged.
func test_the_grip_is_a_hard_write_and_only_the_draw_residual_eases() -> void:
	var parts := _live(_weapon(Vector3(0.2, -0.02, 0.0)))
	var body = parts["body"]
	var gun: GunMesh = parts["gun"]
	parts["rig"].visible = true
	body._weapon_hands_up = true
	var dt := 1.0 / 60.0
	body._update_weapon_hands(dt)
	assert_lt(_grip_offset(parts).length(), 0.0005, "settled, the hands' grip must sit ON the gun's anchor")
	gun.position += Vector3(0.0, 0.03, 0.02)  # a recoil kick between two frames
	body._update_weapon_hands(dt)
	assert_lt(_grip_offset(parts).length(), 0.0005,
		"one frame after a 3.6 cm kick the grip must already be on the moved gun (off by %s) — an eased follow trails every shot" % _grip_offset(parts))
	body._weapon_hands_settle = Vector3(0.0, -0.35, 0.0)  # a fresh draw: rise from below the grip
	body._update_weapon_hands(dt)
	var residual := _grip_offset(parts)
	assert_true(residual.y < -0.001 and residual.y > -0.35,
		"a draw residual must EASE toward the grip (one frame in: %s), not snap and not hold" % residual)
	assert_almost_eq(residual.x, 0.0, 0.0005, "the rise is straight up — no sideways residual")
	for i in 120:
		body._update_weapon_hands(dt)
	assert_lt(_grip_offset(parts).length(), 0.001, "two seconds on, the draw has settled onto the grip")
	_teardown(parts)


## ...and the solve must read THIS frame's gun. The component ticks at priority -1, BEFORE GunPose writes the gun
## (priority 0), so a direct call would glue the hands to LAST frame's gun — one frame behind every recoil kick
## (the 2026-09-15 "they don't move with the weapon" report). A priority-0 stand-in moves the gun every frame here.
func test_the_grip_solve_reads_this_frames_gun_not_last_frames() -> void:
	var parts := _live(_weapon(Vector3(0.2, -0.02, 0.0)))
	var body = parts["body"]
	parts["rig"].visible = true
	body._weapon_hands_up = true
	var script := GDScript.new()
	script.source_code = "extends Node\nvar gun: Node3D\nvar step := Vector3.ZERO\nfunc _process(_delta: float) -> void:\n\tgun.position += step\n"
	script.reload()
	var mover := Node.new()
	mover.set_script(script)
	mover.set("gun", parts["gun"])
	mover.set("step", Vector3(0.0, 0.02, 0.0))  # 2 cm a frame: a gun pose that moves EVERY frame
	add_child_autofree(mover)
	body.set_process(true)
	for i in 4:
		await get_tree().process_frame
	var off := _grip_offset(parts)
	body.set_process(false)
	mover.set("step", Vector3.ZERO)
	assert_lt(off.length(), 0.0005,
		"the hands must sit on the gun as it was drawn THIS frame (off by %s — one frame's 2 cm step means the solve ran before the gun moved)" % off)
	_teardown(parts)


## One refresh settles BOTH latches and runs exactly one transition: asking the fists first and the weapon second
## made a gun draw stow the hands (the fists answer) and then immediately raise them (the weapon answer).
func test_a_drawn_weapon_outranks_the_fists_in_one_transition() -> void:
	var parts := _live(_weapon(Vector3(0.2, -0.02, 0.0)))
	var body = parts["body"]
	var rig: BodyModelSwap = parts["rig"]
	parts["hub"].equipped_weapon = load(FISTS_PATH)  # the combat hub reads FISTS while a real model is mounted
	assert_true(body._weapon_hands_wanted(), "sanity: the weapon hold answers yes")
	assert_true(body._unarmed_hands_wanted(), "sanity: ...and so, on its own, would the fists")
	body.refresh_unarmed_hands()
	assert_true(body._weapon_hands_up, "a drawn weapon must win the rig")
	assert_false(body._unarmed_hands_up, "...and the fists must NOT also claim it — one mode, not two")
	# A repeat refresh with nothing changed must early-out rather than re-run the draw.
	body._weapon_hands_settle = Vector3.ZERO  # the rise has finished...
	rig.position += Vector3(0.0, 0.1, 0.0)  # ...and the live solve has moved the rig since
	body.refresh_unarmed_hands()
	assert_eq(body._weapon_hands_settle, Vector3.ZERO,
		"a refresh where NEITHER latch moved must not re-fire the transition (it seeded a fresh residual)")
	_teardown(parts)


## Carrying a prop is the third pose of the same rig and it is on_carry_changed's, not ours — and dying is nobody's.
func test_a_carried_prop_takes_the_rig_off_the_weapon_solve() -> void:
	var parts := _live(_weapon(Vector3(0.2, -0.02, 0.0)))
	var body = parts["body"]
	var host = parts["host"]
	var rig: BodyModelSwap = parts["rig"]
	assert_true(body._weapon_hands_wanted(), "baseline: a drawn, visible, mounted weapon wants the hands")
	for latch in ["_carrying", "_dying", "_dead"]:
		host.set(latch, true)
		assert_false(body._weapon_hands_wanted(), "%s must refuse the weapon hold — hands full of crate / a death cinematic are not hands on a gun" % latch)
		host.set(latch, false)
		assert_true(body._weapon_hands_wanted(), "control: clearing %s gives the hands back" % latch)
	# The grab itself: after the holster beat the CARRY hold takes the rig and the grip solve stands down.
	body.fp_arm_draw_delay = 0.01
	body._weapon_hands_up = true
	host._carrying = true
	host._dying = true
	await body.on_carry_changed(true)
	assert_false(rig.visible, "a death during the holster beat must not pop the carry hands into the cinematic")
	host._dying = false
	await body.on_carry_changed(true)
	assert_true(rig.visible, "control: alive, the carry hands slide up after the beat")
	assert_false(body._weapon_hands_up, "...and the grip solve is stood down, or it keeps writing over the carry slide")
	_teardown(parts)


# --- 3. The gates -------------------------------------------------------------------------------------------

## A component with no host must answer false rather than reach through a null; with a host, the feature toggle
## must switch the whole pose off.
func test_the_want_check_is_null_safe_and_respects_its_toggle() -> void:
	var bare = load(FP_BODY_SOURCE).new()
	assert_false(bare._weapon_hands_wanted(), "a bare component with no host wants nothing on screen")
	bare.free()
	var parts := _live(_weapon(Vector3(0.2, -0.02, 0.0)))
	var body = parts["body"]
	assert_true(body._weapon_hands_wanted(), "control: switched on, the same harness wants the hands")
	body.weapon_hands = false
	assert_false(body._weapon_hands_wanted(), "the toggle must switch the whole pose off")
	_teardown(parts)


## The hands must vanish with the view model they are holding, not outlive it — the accessibility toggle
## (Settings.view_model_visible) and the sniper's scoped hide both land on GunPose's per-frame `visible` write.
func test_the_hands_hide_whenever_the_view_model_does() -> void:
	var real := _weapon(Vector3(0.2, -0.02, 0.0))
	var parts := _live(real)
	var body = parts["body"]
	var gun: GunMesh = parts["gun"]
	assert_true(body._weapon_hands_wanted(), "baseline: the hands are wanted")
	gun.visible = false
	assert_false(body._weapon_hands_wanted(), "a hidden view model must take the hands with it — GunPose owns that visible flag")
	gun.visible = true
	assert_true(body._weapon_hands_wanted(), "control: shown again, the hands come back")
	gun._swapper._mounted_weapon = WeaponData.new()
	assert_false(body._weapon_hands_wanted(), "a weapon with no view_model shows nothing, so there is nothing to hold")
	# FISTS refuse by IDENTITY, not by lacking a view model: fists.tres authors no view_model, so the clause above
	# would already refuse it and prove nothing about this one. Author a scene on the SHARED cached Player.FISTS so
	# only the identity clause stands in the way, and put it back BEFORE asserting (after_each is the second net).
	var fists := load(FISTS_PATH) as WeaponData
	fists.view_model = PackedScene.new()
	gun._swapper._mounted_weapon = fists
	var fists_wanted: bool = body._weapon_hands_wanted()
	fists.view_model = _saved_fists_view_model  # what before_each found on it, not an assumed null
	assert_false(fists_wanted, "unarmed is the FISTS pose of this rig, never a weapon hold, even with a view model authored on fists")
	gun._swapper._mounted_weapon = real
	parts["atk"].holstered = true
	assert_false(body._weapon_hands_wanted(), "a holstered weapon takes the hands with it")
	_teardown(parts)


## The hands TURN with the gun, not just travel with it. GunPose droops the gun 18° after a few quiet seconds (and
## kicks it on every shot); a rig whose orientation stayed camera-level slid down with the weapon while pointing
## the wrong way. So however far the gun rotates off its rest, the rig must rotate by exactly that much.
func test_the_rig_basis_turns_with_the_gun() -> void:
	var body = load(FP_BODY_SOURCE).new()
	assert_eq(body._gun_delta_basis(), Basis(), "no gun rig -> identity delta -> the plain authored pose")
	body.free()
	var parts := _live(_weapon(Vector3(0.2, -0.02, 0.0)))
	var gun: GunMesh = parts["gun"]
	var rig: BodyModelSwap = parts["rig"]
	gun.rotation_degrees = Vector3(0.0, 90.0, 0.0)  # the rig's baked barrel yaw...
	gun.base_rotation = gun.rotation_degrees  # ...captured as the rest pose, exactly as GunMesh._ready does
	var gun_rest := gun.transform.basis
	assert_true(parts["body"]._solve_weapon_hands() != null, "the solve must place the rig on a live harness")
	var rig_rest := rig.transform.basis
	gun.rotation_degrees = Vector3(-18.0, 90.0, 6.0)  # idle droop + a kick
	parts["body"]._solve_weapon_hands()
	var gun_turn := gun.transform.basis * gun_rest.inverse()
	var rig_turn := rig.transform.basis * rig_rest.inverse()
	assert_false(gun_turn.is_equal_approx(Basis()), "sanity: the gun really turned")
	for axis in 3:
		assert_true(rig_turn[axis].is_equal_approx(gun_turn[axis]),
			"the rig must turn with the gun (column %d: rig %s vs gun %s)" % [axis, rig_turn[axis], gun_turn[axis]])
	_teardown(parts)


## The hands dress the VISIBLE gun. Attack equips the new weapon on the inventory the instant a swap STARTS but
## the rig mounts its model only at swap_finished — so every per-weapon read in this pose must key on the rig's
## MOUNTED weapon, or the hands leap to the next weapon's grip on the current weapon's model for the whole
## down-swing (the 2026-09-15 "swap messes up where your hands are" — probe: __weapon_hands_swap_probe.tscn).
func test_every_per_weapon_read_keys_on_the_mounted_weapon_not_the_inventory() -> void:
	var mounted := _weapon(Vector3(0.2, -0.02, 0.0), false, 0.7)
	var next := _weapon(Vector3(0.45, 0.05, 0.1), true, 1.6)
	var parts := _live(mounted)
	var body = parts["body"]
	var gun: GunMesh = parts["gun"]
	var hub: Inventory = parts["hub"]
	var anchor_settled: Vector3 = body._weapon_hands_anchor()
	hub.equipped_weapon = next  # the swap has STARTED: the inventory already names the next weapon
	assert_true(body._weapon_hands_wanted(), "mid-swap the mounted weapon still wants the hands")
	assert_almost_eq(body._weapon_hands_scale(), 0.7, 0.00001, "the hand size must be the MOUNTED weapon's, not the inventory's 1.6")
	assert_false(body._weapon_hands_one_handed(), "the one-handed hold must be the MOUNTED weapon's, not the inventory's")
	assert_true((body._weapon_hands_anchor() as Vector3).is_equal_approx(anchor_settled),
		"the grip anchor must not move while only the INVENTORY has changed — the pistol is still the model on screen")
	gun._swapper._mounted_weapon = next  # swap_finished: the new model lands
	assert_false((body._weapon_hands_anchor() as Vector3).is_equal_approx(anchor_settled), "...and follows the model once it does")
	assert_almost_eq(body._weapon_hands_scale(), 1.6, 0.00001, "...the size too")
	assert_true(body._weapon_hands_one_handed(), "...and the one-handed hold")
	gun._swapper._mounted_weapon = load(FISTS_PATH)
	hub.equipped_weapon = mounted
	assert_false(body._weapon_hands_wanted(), "fists still mounted must refuse, whatever the inventory already says")
	# The swapper stamps the mounted weapon in the one place the model actually changes — even for no scene at all.
	var fists := load(FISTS_PATH) as WeaponData
	gun._swapper._mounted_weapon = mounted
	hub.equipped_weapon = fists
	gun.inventory = hub
	gun._swapper.equip()
	assert_eq(gun.mounted_weapon(), fists, "WeaponModelSwapper.equip must stamp the weapon it just mounted")
	_teardown(parts)


# --- 4. The authored grips are reachable ---------------------------------------------------------------------

## A grip left at the WeaponData default sits on the gun rig's origin — which camera_rig.tscn parks on the
## camera plane, outside any frustum. Every shipped weapon must author one far enough down its own barrel to be
## on screen. This is the test that catches "a new weapon was added and nobody ran the frame probe".
func test_every_shipped_weapon_authors_a_grip_the_camera_can_see() -> void:
	# The REAL _weapon_hands_anchor, with the gun rig parked at camera_rig.tscn's authored mount. The harness gun
	# sits under this GutTest, a plain Node, so its global frame IS the camera-local frame the mount is authored in
	# — and the anchor comes out in the camera's metres, where z < 0 is in front of the lens.
	var parts := _live(_weapon(Vector3.ZERO))
	var gun: GunMesh = parts["gun"]
	gun.transform = _gun_mount()
	for path in WEAPONS:
		var wd := load(path) as WeaponData
		assert_not_null(wd, "%s must load as a WeaponData" % path)
		if wd == null:
			continue
		assert_not_null(wd.view_model, "%s is in this list because it mounts a view model" % path)
		gun._swapper._mounted_weapon = wd
		var raw: Variant = parts["body"]._weapon_hands_anchor()
		assert_true(raw is Vector3, "%s: a mounted weapon on an in-tree gun rig must yield a grip anchor" % path)
		if not (raw is Vector3):
			continue
		var anchor: Vector3 = raw
		assert_lt(anchor.z, -MIN_GRIP_DEPTH,
			"%s: view_model_grip must sit at least %s m in front of the lens (anchor z %s) or the hands solve to a point nothing renders — re-run scripts/tools/probes/preview_weapon_hands_frame.gd"
			% [path, MIN_GRIP_DEPTH, anchor.z])
	_teardown(parts)


## The grip is authored in the GUN's own frame, whose +X runs down the barrel (the project convention
## WeaponData.npc_hold_rotation already documents). Pinned so the axis meaning cannot quietly flip: a positive X
## is what carries the hands FORWARD, away from the eye.
func test_the_grip_axis_convention_is_down_the_barrel() -> void:
	var mount := _gun_mount()
	var forward := mount.basis.orthonormalized() * Vector3(1.0, 0.0, 0.0)
	assert_lt(forward.z, -0.9,
		"the gun rig's local +X must still point AWAY from the camera (-Z) — every authored view_model_grip reads it as 'down the barrel'")


## ...and the reconciliation that makes that reachability hold at RUN time. Two of the gates move with no signal
## behind them (the view-model accessibility toggle and the sniper's scoped hide both land on GunPose's per-frame
## `visible` write), so the latch is re-asked each frame — but only while the fists are NOT the pose on screen,
## because their handoff timing is signal-driven on purpose.
func test_the_weapon_latch_is_reconciled_every_frame_but_never_the_fists() -> void:
	var parts := _live(_weapon(Vector3(0.2, -0.02, 0.0)))
	var body = parts["body"]
	var gun: GunMesh = parts["gun"]
	var dt := 1.0 / 60.0
	parts["rig"].visible = true
	body._weapon_hands_up = true
	gun.visible = false  # no signal announces this
	body._update_weapon_hands(dt)
	assert_false(body._weapon_hands_up, "the per-frame update must drop the latch when the view model hides")
	gun.visible = true
	body._update_weapon_hands(dt)
	assert_true(body._weapon_hands_up, "...and raise it again when the view model returns, with no signal either way")
	body._weapon_hands_up = false
	body._unarmed_hands_up = true  # the fists own the rig
	body._update_weapon_hands(dt)
	assert_false(body._weapon_hands_up, "while the fists own the rig the per-frame update must not seize it — that handoff is signal-driven")
	_teardown(parts)


# --- 5. The two-handed V, and the one-handed collapse ---------------------------------------------------------

## A live rig with the shipped arm model, posed the way the weapon hold poses it. In-tree so the pair really
## instances and the hand positions can be read off real transforms (the test_fp_body_arms idiom).
func _hold_rig(spread: float, converge: float) -> BodyModelSwap:
	var rig := BodyModelSwap.new()
	rig.animate_arms = false
	rig.arm_model = load(ARM_MODEL)
	add_child_autofree(rig)
	rig.arm_rotation = Vector3(0.0, 180.0, 0.0)  # hands down the camera's -Z, as _build_first_person_arms sets
	rig.arm_scale = 0.14
	rig.arm_position = Vector3(spread, 0.0, 0.0)
	rig.arm_converge_deg = converge
	return rig


## ⭐THE FIX FOR "it looks like a plank": the two arms are MIRRORS about the rig's centre, so closing the hands by
## closing the SPREAD collapses them into one overlapping slab. What an NPC's front view shows is a V — shoulders
## wide, hands meeting on one point — and that is `arm_converge_deg`, which until 2026-09-14 only existed on the
## ANIMATED path (arm_hold_converge_deg) and so did nothing at all on an `animate_arms`-off rig like this one.
func test_converge_closes_the_hands_without_closing_the_shoulders() -> void:
	var open_rig := _hold_rig(0.105, 0.0)
	var closed_rig := _hold_rig(0.105, 24.0)
	var reach := open_rig._arm_reach_measured()
	assert_gt(reach, 0.0, "the shipped arm model must measure a reach, or there is no hand to place")
	var tip := Vector3(0.0, 0.0, reach)
	var open_hand: Vector3 = open_rig._arm_left.transform * tip
	var closed_hand: Vector3 = closed_rig._arm_left.transform * tip
	assert_eq(open_rig.arm_position.x, closed_rig.arm_position.x,
		"the SHOULDERS must not move — converge is the other half of the pair, not a narrower spread")
	assert_lt(absf(closed_hand.x), absf(open_hand.x),
		"converging must bring the LEFT hand toward the centreline (%s -> %s)" % [open_hand.x, closed_hand.x])
	# ...and at the angle the shipped pose uses, it should close nearly all of it: asin(spread/reach) is the exact
	# solution, and the shipped 24° is that at this rig's proportions. Loose bound — this pins the geometry, not a
	# framing decision.
	assert_lt(absf(closed_hand.x), absf(open_hand.x) * 0.35,
		"24 degrees should close most of a 0.105 m half-spread at this reach, not shave a little off it")


## One-handed (a knife, a spray can) hides the off hand WITHOUT rebuilding. `single_arm` would rebuild, which
## re-instances the parts and so strands the GunVisuals rim + outline the view model dresses them with.
func test_one_handed_hides_the_offhand_and_survives_a_rebuild() -> void:
	var rig := _hold_rig(0.0, 0.0)
	assert_true(is_instance_valid(rig._arm_right), "the pair must still be BUILT — this is a visibility toggle")
	rig.hide_offhand = true
	assert_true(rig._arm_left.visible, "the leading hand stays")
	assert_false(rig._arm_right.visible, "...and the off hand goes")
	# A rebuild (an appearance swap) instances a fresh, visible pair — the hold must be re-asserted, or a
	# one-handed weapon silently grows a second hand the next time the player changes clothes.
	rig.arm_model = load(ARM_MODEL)
	assert_false(rig._arm_right.visible, "a rebuilt pair must come back with the off hand still hidden")


## ...and the reason the collapse is not optional: weapon_grip_position() averages BOTH hands, drawn or not.
## Spread apart with one hidden, the grip it reports sits between a visible hand and an invisible one — and the
## weapon then hangs there, beside the hand you can see. THAT is the "the hands don't line up with the knife" read.
func test_a_one_handed_grip_must_be_collapsed_or_it_reports_a_phantom_midpoint() -> void:
	var spread_rig := _hold_rig(0.105, 0.0)
	spread_rig.hide_offhand = true
	var reach := spread_rig._arm_reach_measured()
	var visible_hand: Vector3 = spread_rig._arm_left.transform * Vector3(0.0, 0.0, reach)
	var reported: Variant = spread_rig.weapon_grip_position()
	assert_true(reported is Vector3, "the rig must still report a grip")
	assert_gt(absf((reported as Vector3).x - visible_hand.x), 0.05,
		"a SPREAD one-handed pair reports a grip nowhere near the hand you can see — which is why FirstPersonBody zeroes the spread and the converge together with hide_offhand")
	var collapsed := _hold_rig(0.0, 0.0)
	collapsed.hide_offhand = true
	var hand2: Vector3 = collapsed._arm_left.transform * Vector3(0.0, 0.0, collapsed._arm_reach_measured())
	var grip2: Variant = collapsed.weapon_grip_position()
	assert_almost_eq((grip2 as Vector3).x, hand2.x, 0.001,
		"collapsed, the averaged grip IS the visible hand — the weapon lands in it")


## The solve itself makes that pairing: a two-handed weapon gets the V (spread + converge) and the fore/aft stagger
## as a METRES shift (never the arm-pump pitch, which crosses the forearms at this tilt); a one-handed weapon
## collapses all three together and hides the off hand.
func test_the_solve_zeroes_spread_converge_and_stagger_together_for_one_hand() -> void:
	var parts := _live(_weapon(Vector3(0.2, -0.02, 0.0), false))
	var body = parts["body"]
	var rig: BodyModelSwap = parts["rig"]
	body.weapon_hands_spread = 0.1
	body.weapon_hands_converge_deg = 20.0
	body.weapon_hands_stagger = 0.04
	rig.arm_stride_deg = 7.0  # a leftover fists arm-pump
	assert_true(body._solve_weapon_hands() != null, "the two-handed solve must place the rig")
	assert_gt(rig.arm_position.x, 0.0, "two hands: the shoulders stay spread")
	assert_gt(rig.arm_converge_deg, 0.0, "two hands: ...and converge onto one point (the V)")
	assert_gt(rig.arm_stagger, 0.0, "two hands: the support hand sits AHEAD along the weapon, as a metres shift")
	assert_almost_eq(rig.arm_stride_deg, 0.0, 0.00001, "the fists' arm-pump pitch is never part of this pose")
	assert_false(rig.hide_offhand, "two hands: both drawn")
	parts["gun"]._swapper._mounted_weapon = _weapon(Vector3(0.2, -0.02, 0.0), true)
	body._solve_weapon_hands()
	assert_almost_eq(rig.arm_position.x, 0.0, 0.00001, "a one-handed hold must collapse the spread")
	assert_almost_eq(rig.arm_converge_deg, 0.0, 0.00001, "...and the converge with it")
	assert_almost_eq(rig.arm_stagger, 0.0, 0.00001, "...and the fore/aft stagger, which is also a two-hand term")
	assert_true(rig.hide_offhand, "...and hide the off hand")
	_teardown(parts)


# --- 6. Every way OUT of the weapon pose opens the grip again ---------------------------------------------

## The weapon hold's two-hand geometry, as the solve leaves it on the rig.
func _close_grip(rig: BodyModelSwap) -> void:
	rig.arm_converge_deg = 24.0
	rig.hide_offhand = true
	rig.arm_stagger = 0.03
	rig.rotation_degrees = Vector3(62.0, 20.0, 0.0)


func _assert_grip_open(rig: BodyModelSwap, exit_name: String) -> void:
	assert_almost_eq(rig.arm_converge_deg, 0.0, 0.00001, "%s must open the converge" % exit_name)
	assert_false(rig.hide_offhand, "%s must bring the off hand back" % exit_name)
	assert_almost_eq(rig.arm_stagger, 0.0, 0.00001, "%s must clear the stagger" % exit_name)
	assert_almost_eq(rig.rotation_degrees.y, 0.0, 0.0001, "%s must clear the weapon hold's yaw" % exit_name)


## The 2026-09-15 CARRY REGRESSION: a grab holsters the weapon (the hands start a 0.22 s stow) and draws the
## carry hold after only fp_arm_draw_delay 0.18 s — so the carry draw runs while the rig is STILL VISIBLE and the
## hidden-only reset in _slide_fp_arms is skipped. The converge, the hidden off hand and the stagger have no ease
## path, so you carried the crate with one tiny converged hand. Driven on all three exits.
func test_every_exit_from_the_weapon_pose_opens_the_grip() -> void:
	var parts := _live(_weapon(Vector3(0.2, -0.02, 0.0)))
	var body = parts["body"]
	var rig: BodyModelSwap = parts["rig"]
	rig.visible = true  # mid-stow: still on screen when the carry draw lands — the race
	_close_grip(rig)
	body._slide_fp_arms(true)
	_assert_grip_open(rig, "a carry / fists DRAW over a still-visible rig")
	_close_grip(rig)
	body._ease_fp_arms_to_rest()
	_assert_grip_open(rig, "the weapon->fists handoff")
	_close_grip(rig)
	body._hide_fp_arms()
	_assert_grip_open(rig, "the stow tail")
	assert_false(rig.visible, "the stow tail hides the rig")
	_teardown(parts)


## And the seam itself, on a live rig: it clears exactly the three terms the weapon solve writes.
func test_open_weapon_grip_clears_converge_offhand_and_stagger() -> void:
	var host = load(PLAYER_SOURCE).new()
	var body = load(FP_BODY_SOURCE).new()
	body.host = host
	var rig := _hold_rig(0.105, 24.0)
	rig.hide_offhand = true
	rig.arm_stagger = 0.05
	body._fp_arms = rig
	body._open_weapon_grip()
	assert_eq(rig.arm_converge_deg, 0.0, "converge opened")
	assert_false(rig.hide_offhand, "off hand back")
	assert_eq(rig.arm_stagger, 0.0, "stagger cleared")
	# The yaw is the one that got out: the hold writes rotation_degrees whole, the other poses only tween X.
	rig.rotation_degrees = Vector3(62.0, 20.0, 0.0)
	body._open_weapon_grip()
	assert_eq(rig.rotation_degrees.y, 0.0, "the weapon hold's yaw must not survive into the carry hold / fists")
	assert_eq(rig.rotation_degrees.z, 0.0, "...nor any roll")
	assert_true(rig._arm_right.visible, "...and the right arm is actually drawn again")
	body._fp_arms = null
	body.free()
	host.free()
