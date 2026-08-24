extends GutTest

## The player's own ARMS on their own BODY — first-person body awareness, added 2026-08-13 ("I wanted to see my
## arms on the body itself like how an NPC has arms on their body").
##
## These are NOT the view-model hands (tests/test_fists_view_model.gd owns those): that rig lives under the
## camera on the gun's render layer and is the carry hold / the bare fists. THIS pair hangs off the FP torso at
## real world depth on the main camera, so looking down shows arms attached to your chest.
##
## What is pinned here is the thing the feature's correctness actually rests on:
##   1. The MOUNT is INHERITED from the appearance catalog, never re-authored. "Like an NPC has arms" is only
##      true by construction if these are literally the rows CharacterAppearanceCatalog.configure_swap stamps on
##      every NPC — a copied number would drift silently the first time the cast's proportions are retuned.
##   2. The three mode PITCHES are zeroed. BodyModelSwap poses arms forward/overhead when its host reports a
##      drawn weapon or being airborne; the Player answers is_on_floor, so a live arm_air_pitch throws your own
##      arms over your face on every jump. This is the one that silently ruins the feature.
##   3. A whole_body look is SKIPPED — that model already has arms, so mounting a pair grows you four.
##
## Off-tree throughout (the test_player_core idiom): a bare first_person_body.gd + a bare player.gd host, no
## _ready on either, and a real BodyModelSwap to receive the stamp.

const FP_BODY_SOURCE := "res://scripts/player/first_person_body.gd"
const PLAYER_SOURCE := "res://scripts/player/player.gd"
const SWAP_SOURCE := "res://scripts/components/body_model_swap.gd"


## A bare component + host + rig, wired by hand. Caller frees via _teardown_rig.
func _build() -> Dictionary:
	var host = load(PLAYER_SOURCE).new()
	var body = load(FP_BODY_SOURCE).new()
	body.host = host
	var rig := BodyModelSwap.new()
	return {"host": host, "body": body, "rig": rig}


func _teardown(parts: Dictionary) -> void:
	(parts["rig"] as Node).free()
	(parts["body"] as Node).free()
	(parts["host"] as Node).free()


func _catalog() -> CharacterAppearanceCatalog:
	return CharacterAppearanceCatalog.get_catalog()


func test_the_arm_mount_is_inherited_from_the_appearance_catalog() -> void:
	# ⭐THE contract. The catalog's arm_model / arm_scale / arm_position / arm_rotation are what dress every NPC
	# (configure_swap), so reading them is what makes the player's own arms the same arms rather than a lookalike
	# pair with hand-copied numbers that rot.
	var cat := _catalog()
	assert_not_null(cat, "the appearance catalog must load — it is the source of the arm mount")
	assert_not_null(cat.arm_model, "the catalog must author an arm_model, or nobody in the cast has arms")
	var parts := _build()
	var body = parts["body"]
	var rig: BodyModelSwap = parts["rig"]
	body._configure_fp_body_arms(rig)
	assert_eq(rig.arm_model, cat.arm_model,
		"the FP body arms must mount the CATALOG's arm model — the same one every NPC wears")
	# Scale and position are the catalog's rows THROUGH the two FP-only knobs — that indirection is the whole
	# design: the catalog stays the shared truth (touching it would resize every NPC), while the player's own
	# first-person framing is expressed as a multiplier and an offset on top of it. Both ship NEUTRAL now (x1, +0):
	# the arms used to carry their own diet because the NPC arm is long for the player's 1.0 m eye-to-floor height,
	# and fp_body_scale took that job over for the whole body at once (see the floor and stack tests below).
	assert_almost_eq(rig.arm_scale, cat.arm_scale * body.fp_body_arm_scale_mult, 0.0001,
		"arm_scale must be the CATALOG's scale times the FP-only fp_body_arm_scale_mult — never a hand-authored length")
	assert_eq(rig.arm_position, cat.arm_position + body.fp_body_arm_offset,
		"and the shoulder must be the catalog's position plus the FP-only fp_body_arm_offset")
	assert_eq(rig.arm_rotation, cat.arm_rotation,
		"and at the catalog's arm_rotation — ~90 degrees X is the hanging-at-your-sides rest pose")
	assert_true(rig.animate_arms,
		"animate_arms must be ON — the walk-swing is what stops your own arms reading as a mannequin's")
	_teardown(parts)


func test_the_fp_offset_nudges_the_catalog_shoulder_without_replacing_it() -> void:
	# The fp_torso_offset idiom: first-person-specific framing is a nudge ADDED to the authored mount, so a
	# catalog retune still moves the arms and the nudge keeps meaning the same thing.
	var cat := _catalog()
	var parts := _build()
	var body = parts["body"]
	var rig: BodyModelSwap = parts["rig"]
	body.fp_body_arm_offset = Vector3(0.01, -0.2, 0.03)
	body._configure_fp_body_arms(rig)
	assert_eq(rig.arm_position, cat.arm_position + Vector3(0.01, -0.2, 0.03),
		"fp_body_arm_offset must ADD to the catalog's arm_position, never replace it")
	_teardown(parts)


func test_every_mode_pitch_is_zeroed_so_your_arms_only_hang_and_walk() -> void:
	# ⭐The jump bug, pinned. BodyModelSwap's airborne branch swings arms to arm_air_pitch (-160 by default: both
	# arms straight overhead, the NPC roller-coaster flail), and `airborne` is just `not host.is_on_floor()`,
	# which the Player very much does answer — so leaving that default live means every jump throws your own arms
	# over your face. The two weapon pitches are inert only because the Player happens not to implement
	# is_holding_gun / is_fists_out; they are zeroed anyway so adding either later can't swing the body arms
	# forward through the view model.
	var parts := _build()
	var body = parts["body"]
	var rig: BodyModelSwap = parts["rig"]
	assert_ne(rig.arm_air_pitch, 0.0,
		"sanity: BodyModelSwap must still SHIP a non-zero arm_air_pitch, or this test is pinning nothing (NPCs use it)")
	body._configure_fp_body_arms(rig)
	assert_eq(rig.arm_air_pitch, 0.0,
		"arm_air_pitch must be zeroed — otherwise jumping salutes the sky with your own arms")
	assert_eq(rig.arm_hold_pitch, 0.0,
		"arm_hold_pitch must be zeroed — a future is_holding_gun on the Player must not pose the body arms forward")
	assert_eq(rig.arm_fists_pitch, 0.0,
		"arm_fists_pitch must be zeroed for the same reason")
	_teardown(parts)


func test_the_toggle_and_a_whole_body_look_both_mount_nothing() -> void:
	# first_person_body_arms off must leave the rig untouched (the empty-frame behaviour this feature replaced),
	# and a whole_body appearance must skip: that model is one piece with its own arms, so a mounted pair = four.
	var parts := _build()
	var body = parts["body"]
	var rig: BodyModelSwap = parts["rig"]
	body.first_person_body_arms = false
	body._configure_fp_body_arms(rig)
	assert_null(rig.arm_model, "first_person_body_arms = false must mount no arms at all")
	body.first_person_body_arms = true
	# Drive the whole_body branch by pointing the appearance at a synthetic one-piece body option. It needs a
	# real `model`: the catalog's lookups only ever match options that pass CharacterPartOption.is_valid(), so a
	# model-less stub is silently invisible to body_option() AND to the default_body() fallback — which lands on
	# `body == null` and mounts arms after all. (That is exactly how this test failed the first time.)
	var whole := CharacterPartOption.new()
	whole.id = &"__test_whole__"
	whole.model = load("res://scenes/bodyparts/torso.tscn")
	whole.whole_body = true
	var cat := _catalog()
	var saved := cat.bodies.duplicate()
	cat.bodies = [whole] as Array[CharacterPartOption]
	parts["host"].appearance = {"body": "__test_whole__"}
	body._configure_fp_body_arms(rig)
	cat.bodies = saved  # restore BEFORE asserting, so a failure can't leak the stub into later tests
	assert_null(rig.arm_model,
		"a whole_body look must skip the arm mount — the one-piece model already has arms")
	whole = null
	_teardown(parts)


func test_the_arms_dissolve_on_the_same_curve_as_the_torso_they_hang_off() -> void:
	# BodyModelSwap gained arm_transparency for exactly one reason: the FP torso already fades out (the look-down
	# dissolve, and fully on crouch), and arms that DON'T fade with it leave two limbs floating under the camera
	# with no body — worse-looking than either extreme. Source-pinned because the driver is a per-frame write.
	var rig := BodyModelSwap.new()
	assert_eq(rig.arm_transparency, 0.0,
		"arm_transparency must default to 0 — every existing NPC rig has to take the same zero-cost early-out body_transparency does")
	rig.free()
	var src := FileAccess.get_file_as_string(FP_BODY_SOURCE)
	assert_true(src.contains("var arm_see := lerpf(see, 1.0, _fp_body_arm_hide_t)"),
		"_update_fp_torso must build the arms' see-through from the torso's own `see`, so the two can never disagree — the hide term composes ON TOP of it")
	assert_true(src.contains("_fp_arm_catalog_pos + fp_body_arm_offset - Vector3(0.0, sink, 0.0)"),
		"and must sink the shoulders by the same crouch drop as the chest, or the arms detach as you crouch")


func test_the_body_arms_get_out_of_the_way_when_the_view_model_owns_your_hands() -> void:
	# "when youre unholstered, i want the arms to disappear" — the one-pair-of-arms-on-screen rule. Two distinct
	# reasons, and both matter: a DRAWN weapon (the gun/raised fists are what your arms are doing) and a CARRIED
	# prop (the view-model hands are visibly holding it). The second is not covered by the first, because carrying
	# force-holsters the weapon — so a holster-only gate would leave your body arms hanging at your sides while
	# your other hands carry a crate.
	var parts := _build()
	var body = parts["body"]
	var host = parts["host"]
	var ws := Weapon.new()
	var atk := Attack.new()
	ws.attack = atk
	host.weapon_system = ws
	atk.holstered = true
	assert_false(body._fp_body_arms_hidden(),
		"holstered and empty-handed is exactly when you SHOULD see your own arms")
	atk.holstered = false
	assert_true(body._fp_body_arms_hidden(),
		"a DRAWN weapon must hide the body arms — this is the ask")
	# The view-model rig's live `visible` is the second reason. Deliberately read live rather than latched, so the
	# stow slide finishes before the real arms come back.
	atk.holstered = true
	var vm := BodyModelSwap.new()
	body._fp_arms = vm
	vm.visible = false
	assert_false(body._fp_body_arms_hidden(),
		"a view-model rig that is present but HIDDEN holds nothing — the body arms stay")
	vm.visible = true
	assert_true(body._fp_body_arms_hidden(),
		"...but visible view-model hands (a carried prop) must hide them too, even though carrying force-holsters the weapon")
	vm.free()
	ws.free()
	atk.free()
	_teardown(parts)


## The FP body rig exactly as _build_first_person_legs + _configure_fp_body_arms + _configure_fp_torso build it,
## in-tree so the parts really instance and a real AABB can be measured off real transforms. Still NOT a Player —
## a bare BodyModelSwap with three models and no _ready anywhere. Shared by the floor and stack tests below, which
## ask two different questions of the same geometry.
func _mirror_fp_rig() -> BodyModelSwap:
	var cat := _catalog()
	var body = load(FP_BODY_SOURCE).new()
	var rig := BodyModelSwap.new()
	rig.animate_arms = false  # REST pose: the worst case for depth (a swing rotates the far end UP)
	rig.animate_legs = false
	rig.breathe = false
	assert_eq(cat.leg_position, Vector3(0.095, -0.265, -0.02),
		"_build_first_person_legs hardcodes this hip offset; if the catalog's leg_position diverges from it this test stops guarding the real rig")
	rig.leg_scale = body.fp_leg_scale
	rig.leg_position = cat.leg_position
	rig.leg_rotation = cat.leg_rotation
	rig.leg_model = cat.leg_model
	rig.arm_scale = cat.arm_scale * body.fp_body_arm_scale_mult
	rig.arm_position = cat.arm_position + body.fp_body_arm_offset
	rig.arm_rotation = cat.arm_rotation
	rig.arm_model = cat.arm_model
	# The TORSO slice, which this mirror used to omit — and omitting it is exactly why no test could see the legs
	# climb over the chest. The stack question is meaningless without the part the legs were stacking on top of.
	var part := cat.body_option("")
	if part == null:
		part = cat.default_body()
	assert_not_null(part, "the catalog must resolve a default body — it is the chest the FP rig wears")
	if part != null:
		rig.body_model_scale = part.scale
		rig.body_model_rotation = part.rotation + Vector3(0.0, 180.0, 0.0)
		rig.body_model_position = part.position + body.fp_torso_offset
		rig.body_model = part.model
	add_child_autofree(rig)
	rig.position = body.fp_leg_offset
	rig.scale = Vector3.ONE * body.fp_body_scale  # ⭐the whole-rig diet — every measurement below is in Player metres
	body.free()
	return rig


## The lowest / highest world-space Y of every mesh under `part`, as (low, high). Mirrors the frame probe's own
## reader (scripts/tools/preview_fp_body_frame.gd::_world_aabb) — both answer "where is this limb actually".
func _y_span(part: Node3D) -> Vector2:
	var low := INF
	var high := -INF
	var stack: Array[Node] = [part]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		var mi := n as MeshInstance3D
		if mi != null and mi.mesh != null:
			var box: AABB = mi.global_transform * mi.get_aabb()
			low = minf(low, box.position.y)
			high = maxf(high, box.position.y + box.size.y)
	return Vector2(low, high)


## Where the player's feet stand, straight off the authored prefab: the collision capsule's bottom.
func _player_floor_y() -> float:
	var state := (load("res://scenes/player/Player.tscn") as PackedScene).get_state()
	var floor_y := INF
	for i in range(state.get_node_count()):
		if state.get_node_name(i) != "PlayerCollisionShape":
			continue
		var xform := Transform3D.IDENTITY
		var shape: Shape3D = null
		for p in range(state.get_node_property_count(i)):
			match state.get_node_property_name(i, p):
				"transform": xform = state.get_node_property_value(i, p)
				"shape": shape = state.get_node_property_value(i, p)
		var cap := shape as CapsuleShape3D
		assert_not_null(cap, "the player's collider must be a CapsuleShape3D for this test to locate the floor")
		if cap != null:
			floor_y = xform.origin.y - cap.height * 0.5
	return floor_y


func test_no_limb_hangs_through_the_floor() -> void:
	# 2026-08-14: "the players limbs are too long and they clip into the floor slightly." Measured at the time:
	# the ARMS hung 0.130 m below the floor and the LEGS a full 0.534 m — and that 0.534 was exactly how far the
	# whole rig was mounted too low (the NPC body puts its feet ~0.984 m under its swap origin, while the player's
	# floor is only 1.0 m under the eye).
	#
	# This pins the OUTCOME (nothing pokes through the ground), not the numbers, so a future re-tune of the pose is
	# free to move things as long as the body still stands on the floor.
	var floor_y := _player_floor_y()
	assert_ne(floor_y, INF, "Player.tscn must have a PlayerCollisionShape — it defines where the feet stand")
	var rig := _mirror_fp_rig()
	for row in [["arm L", rig._arm_left], ["arm R", rig._arm_right], ["leg L", rig._leg_left],
			["leg R", rig._leg_right], ["torso", rig._body]]:
		var part: Node3D = row[1]
		assert_not_null(part, "%s must have instanced — the mount is read off the catalog" % row[0])
		if part == null:
			continue
		var span := _y_span(part)
		assert_ne(span.x, INF, "%s must contain a mesh to measure" % row[0])
		assert_gte(span.x, floor_y,
			"%s hangs to y=%.4f but the floor is y=%.4f — a limb through the ground is visible every time you look down (re-run scripts/tools/preview_fp_body_frame.gd for the clearance report)" % [row[0], span.x, floor_y])


func test_the_hips_sit_under_the_chest() -> void:
	# ⭐⭐2026-08-15: "legs are drawn on top of the body, rather than below it." The legs were mounted 0.19 m ABOVE
	# the top of the torso, so looking down you saw thighs painted over your own chest. Nothing about it was a
	# draw-order or transparency fault — every part renders opaque on one layer of one camera, and the z-buffer was
	# faithfully drawing what it was given: a body assembled in the wrong order.
	#
	# It survived because the only geometric pin here measured CLEARANCE, which is one-sided — it looks down, so a
	# part mounted too HIGH passes it silently, and one mounted too LOW (the torso, which is what actually moved)
	# passes it too. THIS is the other side. The frame probe prints the same comparison as its STACK line.
	var rig := _mirror_fp_rig()
	assert_not_null(rig._leg_left, "the legs must instance — this test is about where they sit")
	assert_not_null(rig._body, "the torso must instance, or there is nothing for the hips to sit under")
	if rig._leg_left == null or rig._body == null:
		return
	var hip := _y_span(rig._leg_left).y  # the TOP of the leg model IS the hip it pivots on
	var chest := _y_span(rig._body)
	assert_lte(hip, chest.y,
		"the hip tops out at y=%.4f but the chest only reaches y=%.4f — the legs are mounted above the body and will draw over it (see fp_body_scale / fp_torso_offset)" % [hip, chest.y])


func test_the_wall_pose_never_wipes_the_body_scale() -> void:
	# ⭐⭐THE REGRESSION THIS FILE COULD NOT SEE. A Basis holds rotation AND scale in the same three columns, so
	# `_fp_legs.transform.basis = Basis()` does not mean "no rotation" — it means "no rotation, AND scale 1".
	# update_leg_wall_pose() is called unconditionally from Player._physics_process and takes exactly that rest
	# branch on every grounded frame, so it silently reset the whole first-person body to full NPC size 60 times
	# a second: feet 0.37 m through the floor, chest 45.6 degrees below the horizon — INSIDE a 120-degree FOV
	# while standing still, looking straight ahead. The user's report was "the body can be seen without looking
	# down"; `fp_body_scale` had simply never survived past the first physics frame.
	#
	# ⭐Nothing else in this project could catch it: the frame probe and every other geometry test here BUILD
	# THEIR OWN RIG and set the scale themselves, so they all measured a rig this call had never touched. The pin
	# has to drive the real call. It runs on a bare component with a stub host — no Player._ready anywhere.
	# A bare off-tree Player as the host (the _build() idiom — no _ready, so none of the rig/audio/nav setup
	# runs). It answers all three reads this call makes: _shadow_wall_blend defaults 0.0 and a CharacterBody3D
	# that has never moved reports is_on_wall() false, which lands us in the REST branch on purpose.
	var parts := _build()
	var body = parts["body"]
	var rig: BodyModelSwap = parts["rig"]
	body._fp_legs = rig
	rig.scale = Vector3.ONE * body.fp_body_scale
	body.update_leg_wall_pose()
	assert_true(rig.scale.is_equal_approx(Vector3.ONE * body.fp_body_scale),
		"the resting wall pose wiped the rig scale to %s — every basis write here owes fp_body_scale (route it through _fp_legs_basis)" % rig.scale)
	body.update_leg_wall_pose()  # ...and again, because a one-shot reset would still pass a single call
	assert_true(rig.scale.is_equal_approx(Vector3.ONE * body.fp_body_scale),
		"the wall pose is not idempotent on scale — it drifts by a factor every physics frame")
	_teardown(parts)


func test_the_rig_mount_is_derived_from_its_scale() -> void:
	# ⭐fp_leg_offset is NOT a taste value: it is `-1.0 + 0.984 x fp_body_scale + clearance`, where 0.984 is how far
	# below its own origin the NPC body model puts its feet and -1.0 is the player's floor. So the two knobs are a
	# PAIR — retuning the scale without recomputing the mount buries the feet or floats them, and this catches that
	# in a bare unit test before anyone has to notice it on screen. Pinned as a clearance BAND, not a number, so a
	# deliberate re-frame that moves both together still passes.
	var body = load(FP_BODY_SOURCE).new()
	var clearance: float = body.fp_leg_offset.y + 0.984 * body.fp_body_scale + 1.0
	assert_gte(clearance, 0.0,
		"at fp_body_scale %.2f the mount fp_leg_offset.y %.3f buries the feet %.3f m through the floor" % [body.fp_body_scale, body.fp_leg_offset.y, -clearance])
	assert_lte(clearance, 0.06,
		"...and %.3f m of clearance floats the body above the ground; the mount must track fp_body_scale" % clearance)
	body.free()


func test_the_hide_gate_is_null_safe_in_every_direction() -> void:
	# The component's standing contract: a bare instance (no host, no weapon system, no rigs) must no-op rather
	# than crash — an off-tree Player or a unit-test stub hits every one of these.
	var bare = load(FP_BODY_SOURCE).new()
	assert_false(bare._fp_body_arms_hidden(), "no host must hide nothing")
	var parts := _build()
	assert_false(parts["body"]._fp_body_arms_hidden(),
		"a host with no weapon_system reads as nothing drawn, and no view-model rig as nothing held")
	_teardown(parts)
	bare.free()
