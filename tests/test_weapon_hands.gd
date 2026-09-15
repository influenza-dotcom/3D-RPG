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
##      weapon hold re-solves its transform every frame; the fists' walk-bob and rest-ease write the SAME four
##      properties, so both have to yield to this latch or they fight frame by frame.
##   3. THE NULL GUARDS. Every `_wanted` clause is a host read, and the component holds zero gameplay state.
##   4. THE AUTHORED GRIPS ARE REACHABLE. `WeaponData.view_model_grip` is per-weapon because these view models
##      share no origin — and a grip left at ZERO sits at the gun rig's own origin, which is ON the camera
##      plane: the hands would be solved to a point nothing can render. That is invisible in code review and
##      obvious in one render (scripts/tools/probes/preview_weapon_hands_frame.gd).
##
## Off-tree throughout (the test_fp_body_arms idiom): a bare first_person_body.gd + a bare player.gd host, no
## `_ready` on either.

const FP_BODY_SOURCE := "res://scripts/player/first_person_body.gd"
const PLAYER_SOURCE := "res://scripts/player/player.gd"
const CAMERA_RIG := "res://scenes/player/camera_rig.tscn"
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


func _build() -> Dictionary:
	var host = load(PLAYER_SOURCE).new()
	var body = load(FP_BODY_SOURCE).new()
	body.host = host
	return {"host": host, "body": body}


func _teardown(parts: Dictionary) -> void:
	(parts["body"] as Node).free()
	(parts["host"] as Node).free()


func _fp_source() -> String:
	var f := FileAccess.open(FP_BODY_SOURCE, FileAccess.READ)
	assert_not_null(f, "first_person_body.gd must be readable")
	return "" if f == null else f.get_as_text()


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
## on the anchor to floating-point.
func test_the_solved_position_puts_the_arms_grip_exactly_on_the_anchor() -> void:
	var cases := [
		[Vector3(0.19, -0.23, -0.19), Basis(), Vector3(0.0, 0.0, -0.27)],
		[Vector3(0.19, -0.23, -0.19), Basis.from_euler(Vector3(deg_to_rad(34.0), 0.0, 0.0)), Vector3(0.0, 0.0, -0.27)],
		[Vector3(-1.5, 2.25, 0.75), Basis.from_euler(Vector3(0.4, -1.1, 0.2)), Vector3(0.03, -0.01, -0.5)],
		[Vector3.ZERO, Basis.from_euler(Vector3(deg_to_rad(80.0), 0.0, 0.0)), Vector3.ZERO],
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


## A rig with no arms yet reports a ZERO grip, and then the rig simply sits ON the anchor. Pinned because it is
## the degenerate case the live solve hands straight through (weapon_grip_position returns null for "no arms",
## which _solve_weapon_hands bails on — but a zero grip from a rebuilt-but-unmeasured rig must not warp it).
func test_a_zero_grip_parks_the_rig_on_the_anchor() -> void:
	assert_eq(FirstPersonBody.weapon_hands_position(Vector3(1.0, 2.0, 3.0), Basis(), Vector3.ZERO),
		Vector3(1.0, 2.0, 3.0), "with no reach to correct for, the rig origin IS the anchor")


# --- 2. The mode is exclusive -------------------------------------------------------------------------------

## The weapon hold re-solves position / tilt / scale / spread / stagger EVERY FRAME, and the fists' per-frame
## pose ease writes the same properties toward a fixed rest. Both live in this one file, so the gate is a source
## contract: if either loses its `_weapon_hands_up` guard the two writers alternate and the hands judder off the
## gun. (`arm_stride_deg` is the sharpest case — the weapon hold borrows it for the fore/aft hand stagger, and
## the bob's closed-gate branch parks it to zero.)
func test_the_fists_pose_ease_and_bob_yield_to_the_weapon_solve() -> void:
	var src := _fp_source()
	assert_true(src.contains("not _fp_arm_stowing and not _weapon_hands_up"),
		"the per-frame pose ease must skip while the weapon solve owns the rig's transform")
	assert_true(src.contains("_fp_arms.arm_stagger = stagger"),
		"the weapon hold's fore/aft stagger must be the METRES shift (arm_stagger), never a pitch — a pitch crosses the arms")
	assert_true(src.contains("func _update_weapon_hands"), "the per-frame grip solve must exist")
	# ...and ticked DEFERRED, never called: this component runs at process_priority -1, BEFORE GunPose writes the
	# gun's transform, so a direct call would glue the hands to LAST frame's gun — one frame behind every recoil
	# kick, which reads as the gun jumping out of your hands on each shot (the 2026-09-15 "they don't move with
	# the weapon" report).
	assert_true(src.contains("_update_weapon_hands.call_deferred(delta)"),
		"the grip solve must run deferred from _process so it lands AFTER GunPose has moved the gun this frame")
	assert_false(src.contains("_fp_arms.position = _fp_arms.position.lerp(target"),
		"the grip must be a HARD write — an eased follow trails every recoil kick by several frames")
	assert_true(src.contains("_fp_arms.position = (target as Vector3) + _weapon_hands_settle"),
		"only the draw/handoff RESIDUAL eases (_weapon_hands_settle); the grip under it is never lagged")


## One refresh settles BOTH latches and runs exactly one transition. Pinned as a source contract because the
## failure is a sequencing one: asking the fists first and the weapon second made a gun draw stow the hands
## (the fists answer) and then immediately raise them (the weapon answer) — a visible bounce on every swap.
func test_a_drawn_weapon_outranks_the_fists_in_one_transition() -> void:
	var src := _fp_source()
	assert_true(src.contains("var want_fists := (not want_weapon) and _unarmed_hands_wanted()"),
		"the fists must be asked only once the weapon has answered — one mode wins, not two")
	assert_true(src.contains("if want_weapon == _weapon_hands_up and want_fists == _unarmed_hands_up:"),
		"refresh must early-out when NEITHER latch moved, so a repeat call can't re-fire a slide")


## Carrying a prop is the third pose of the same rig and it is on_carry_changed's, not ours — so both `_wanted`
## calls answer false while `_carrying` is up, and the grab explicitly stands the solve down.
func test_a_carried_prop_takes_the_rig_off_the_weapon_solve() -> void:
	var src := _fp_source()
	assert_true(src.contains("_weapon_hands_up = false  # the CARRY hold owns the rig now"),
		"a carry grab must clear the weapon latch before the carry slide writes the rig's position")
	var parts := _build()
	var body = parts["body"]
	var host = parts["host"]
	host._carrying = true
	assert_false(body._weapon_hands_wanted(), "hands full of crate are not hands on a gun")
	host._carrying = false
	host._dying = true
	assert_false(body._weapon_hands_wanted(), "the death cinematic must not raise hands onto the view model")
	_teardown(parts)


# --- 3. The null guards -------------------------------------------------------------------------------------

## Every clause is a host read, so a component with no host — or with the feature switched off — must answer
## false rather than reaching through a null. The same contract _unarmed_hands_wanted already carries.
func test_the_want_check_is_null_safe_and_respects_its_toggle() -> void:
	var body = load(FP_BODY_SOURCE).new()
	assert_false(body._weapon_hands_wanted(), "a bare component with no host wants nothing on screen")
	body.free()
	var parts := _build()
	var b = parts["body"]
	b.weapon_hands = false
	assert_false(b._weapon_hands_wanted(), "the toggle must switch the whole pose off")
	_teardown(parts)


## The hands must vanish with the view model they are holding, not outlive it — the accessibility toggle
## (Settings.view_model_visible) and the sniper's scoped hide both land on GunPose's per-frame `visible` write,
## so reading the rig's live `visible` is what keeps one decision instead of three.
func test_the_hands_hide_whenever_the_view_model_does() -> void:
	var src := _fp_source()
	assert_true(src.contains("if gun == null or not gun.is_inside_tree() or not gun.visible:"),
		"a hidden view model must take the hands with it — GunPose owns that visible flag")
	assert_true(src.contains("if wd == null or wd.view_model == null:"),
		"a weapon with no view_model shows nothing, so there is nothing to hold")


## The hands TURN with the gun, not just travel with it. GunPose droops the gun 18° after a few quiet seconds
## (and kicks it on every shot); a rig whose orientation stayed camera-level slid down with the weapon while
## pointing the wrong way — the standing player's view, i.e. nearly always. The rig basis must be the gun's
## rotation off its rest composed with the authored pose.
func test_the_rig_basis_turns_with_the_gun() -> void:
	var src := _fp_source()
	assert_true(src.contains("func _gun_delta_basis() -> Basis:"), "the gun-delta seam must exist")
	assert_true(src.contains("gun.transform.basis.orthonormalized() * rest.inverse()"),
		"...and be the live gun basis over its captured rest (GunMesh.base_rotation)")
	assert_true(src.contains("* _gun_delta_basis() \\\n\t\t\t* Basis.from_euler(Vector3(deg_to_rad(weapon_hands_tilt_deg), deg_to_rad(weapon_hands_yaw_deg), 0.0))"),
		"the solve must compose gun delta x authored pose into the rig basis (never rotation_degrees alone)")
	# Pure check of the composition: an off-tree body (no gun) yields identity, so the pose IS the authored one.
	var body = load(FP_BODY_SOURCE).new()
	assert_eq(body._gun_delta_basis(), Basis(), "no gun rig -> identity delta -> plain authored pose")
	body.free()


## The hands dress the VISIBLE gun. Attack equips the new weapon on the inventory the instant a swap STARTS but
## the rig mounts its model only at swap_finished — so every per-weapon read in this pose must key on the rig's
## MOUNTED weapon, or the hands leap to the next weapon's grip on the current weapon's model for the whole
## down-swing (the 2026-09-15 "swap messes up where your hands are" — probe: __weapon_hands_swap_probe.tscn).
func test_every_per_weapon_read_keys_on_the_mounted_weapon_not_the_inventory() -> void:
	var src := _fp_source()
	assert_true(src.contains("func _mounted_weapon() -> WeaponData:"), "the mounted-weapon seam must exist")
	assert_true(src.contains("return host.gun_mesh.mounted_weapon()"), "...and read it off the gun rig")
	for fn in ["_weapon_hands_wanted", "_weapon_hands_anchor", "_weapon_hands_scale", "_weapon_hands_one_handed"]:
		var body := src.substr(src.find("func " + fn + "("))
		body = body.substr(0, body.find("\nfunc "))
		assert_true(body.contains("_mounted_weapon()"), fn + " must key on the MOUNTED weapon")
		assert_false(body.contains("inventory.equipped_weapon"), fn + " must not read the inventory's equipped weapon")
	# ...and the swapper stamps it in the one place the model actually changes.
	var sw := FileAccess.open("res://scripts/effects/weapon_model_swapper.gd", FileAccess.READ).get_as_text()
	assert_true(sw.contains("_mounted_weapon = inventory.equipped_weapon"),
		"WeaponModelSwapper.equip must stamp the mounted weapon beside the model it mounts")


# --- 4. The authored grips are reachable ---------------------------------------------------------------------

## A grip left at the WeaponData default sits on the gun rig's origin — which camera_rig.tscn parks on the
## camera plane, outside any frustum. Every shipped weapon must author one far enough down its own barrel to be
## on screen. This is the test that catches "a new weapon was added and nobody ran the frame probe".
func test_every_shipped_weapon_authors_a_grip_the_camera_can_see() -> void:
	var mount := _gun_mount()
	for path in WEAPONS:
		var wd := load(path) as WeaponData
		assert_not_null(wd, "%s must load as a WeaponData" % path)
		if wd == null:
			continue
		assert_not_null(wd.view_model, "%s is in this list because it mounts a view model" % path)
		# The live anchor, exactly as _weapon_hands_anchor builds it (the rig's own basis, never its transform —
		# these models nest under wildly scaled parents and a grip pushed through one comes out in the wrong unit).
		var anchor: Vector3 = mount.origin + mount.basis.orthonormalized() * wd.view_model_grip
		assert_lt(anchor.z, -MIN_GRIP_DEPTH,
			"%s: view_model_grip must sit at least %s m in front of the lens (anchor z %s) or the hands solve to a point nothing renders — re-run scripts/tools/probes/preview_weapon_hands_frame.gd"
			% [path, MIN_GRIP_DEPTH, anchor.z])


## The grip is authored in the GUN's own frame, whose +X runs down the barrel (the project convention
## WeaponData.npc_hold_rotation already documents). Pinned so the axis meaning cannot quietly flip: a positive X
## is what carries the hands FORWARD, away from the eye.
func test_the_grip_axis_convention_is_down_the_barrel() -> void:
	var mount := _gun_mount()
	var forward := mount.basis.orthonormalized() * Vector3(1.0, 0.0, 0.0)
	assert_lt(forward.z, -0.9,
		"the gun rig's local +X must still point AWAY from the camera (-Z) — every authored view_model_grip reads it as 'down the barrel'")


## ...and the reconciliation that makes that reachability hold at RUN time. Two of the gates move with no signal
## behind them (the view-model accessibility toggle and the sniper's scoped hide both land on GunPose's
## per-frame `visible` write), so the latch is re-asked each frame — but only while the fists are NOT the pose on
## screen, because their handoff timing is signal-driven on purpose.
func test_the_weapon_latch_is_reconciled_every_frame_but_never_the_fists() -> void:
	var src := _fp_source()
	assert_true(src.contains("if want != _weapon_hands_up and not _unarmed_hands_up:"),
		"the weapon latch must re-settle per frame, and must stand down while the fists own the rig")


# --- 5. The two-handed V, and the one-handed collapse ---------------------------------------------------------

## A live rig with the shipped arm model, posed the way the weapon hold poses it. In-tree so the pair really
## instances and the hand positions can be read off real transforms (the test_fp_body_arms idiom).
func _hold_rig(spread: float, converge: float) -> BodyModelSwap:
	var rig := BodyModelSwap.new()
	rig.animate_arms = false
	rig.arm_model = load("res://assets/models/arm.blend")
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
	rig.arm_model = load("res://assets/models/arm.blend")
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


## The source contract for that pairing, since the three writes live apart from each other in the solve.
func test_the_solve_zeroes_spread_converge_and_stagger_together_for_one_hand() -> void:
	var src := _fp_source()
	assert_true(src.contains("var spread := 0.0 if one else weapon_hands_spread"),
		"a one-handed hold must collapse the spread")
	assert_true(src.contains("var converge := 0.0 if one else weapon_hands_converge_deg"),
		"...and the converge with it")
	assert_true(src.contains("var stagger := 0.0 if one else weapon_hands_stagger"),
		"...and the fore/aft stagger, which is also a two-hand term")


# --- 6. Every way OUT of the weapon pose opens the grip again ---------------------------------------------

## The 2026-09-15 CARRY REGRESSION: a grab holsters the weapon (the hands start a 0.22 s stow) and draws the
## carry hold after only fp_arm_draw_delay 0.18 s — so the carry draw runs while the rig is STILL VISIBLE and the
## hidden-only reset in _slide_fp_arms is skipped. Scale and spread survive that race (the per-frame pose ease
## pulls them to rest); the converge, the hidden off hand and the stagger had no ease path, so you carried the
## crate with one tiny converged hand. Pinned as a source contract on the three exits.
func test_every_exit_from_the_weapon_pose_opens_the_grip() -> void:
	var src := _fp_source()
	assert_true(src.contains("func _open_weapon_grip"), "the grip-opening seam must exist")
	var draw_fn := src.substr(src.find("func _slide_fp_arms("))
	draw_fn = draw_fn.substr(0, draw_fn.find("
func "))
	var hidden_block_end := draw_fn.find("_fp_arms.visible = true")
	var open_at := draw_fn.find("_open_weapon_grip()")
	assert_true(open_at >= 0 and open_at < hidden_block_end,
		"a carry / fists DRAW must open the grip before it shows the rig")
	# ...and NOT inside the `if not _fp_arms.visible:` block — that is precisely the race
	var hidden_if := draw_fn.find("if not _fp_arms.visible:")
	var hidden_if_end := draw_fn.find("
		_open_weapon_grip()")
	assert_true(hidden_if_end > 0 and hidden_if_end > hidden_if,
		"_open_weapon_grip must run UNCONDITIONALLY on a draw (two tabs deep, outside the hidden-only reset)")
	var ease_fn := src.substr(src.find("func _ease_fp_arms_to_rest("))
	ease_fn = ease_fn.substr(0, ease_fn.find("
func "))
	assert_true(ease_fn.contains("_open_weapon_grip()"), "the weapon->fists handoff must open the grip")
	var hide_fn := src.substr(src.find("func _hide_fp_arms("))
	hide_fn = hide_fn.substr(0, hide_fn.find("
func "))
	assert_true(hide_fn.contains("_open_weapon_grip()"), "the stow tail must open the grip once the rig is off screen")


## And the seam itself, on a live rig: it clears exactly the three terms the weapon solve writes.
func test_open_weapon_grip_clears_converge_offhand_and_stagger() -> void:
	var parts := _build()
	var body = parts["body"]
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
	_teardown(parts)
