extends GutTest

## THIRD PERSON — the camera arm (scripts/camera/third_person_camera.gd) and the character it exists to look at
## (scripts/player/third_person_body.gd).
##
## Four things are pinned here, all of them off-tree or off the PackedScene's STATE — a real Player._ready wants
## the whole prefab, weapon.tscn, nav and audio, and mutates shared statics (the house rule the FirstPersonBody
## wiring test spells out):
##   1. The PREFAB WIRING. Both halves are scene-wired drop-ins whose NodePaths resolve on TREE ENTRY, so an
##      unwired export is invisible until you play. The arm must be a CHILD of the rig root and NOT a parent of
##      ScreenShake — that is the whole reason `Head.camera` / `Head.screen_shake` still resolve.
##   2. The FIT ARITHMETIC. The character's soles belong on the floor and its head at the camera pivot; both fall
##      out of one live input, and the pair must stay derived rather than authored.
##   3. The VIEW-MODEL TRUTH TABLE. A first-person gun must not draw while the camera is behind the character,
##      and the third_person argument must not disturb what the other three arguments already meant.
##   4. The INPUT SURFACE. The toggle's action name has to exist on all three surfaces InputManager validates.

const PLAYER_SCENE := "res://scenes/player/Player.tscn"
const CAMERA_RIG_SCENE := "res://scenes/player/camera_rig.tscn"
const TP_BODY_SOURCE := "res://scripts/player/third_person_body.gd"
const TP_CAMERA_SOURCE := "res://scripts/camera/third_person_camera.gd"


func _state(path: String) -> SceneState:
	var ps := load(path) as PackedScene
	assert_not_null(ps, "%s must load" % path)
	return ps.get_state()


func _node_index(state: SceneState, node_name: String) -> int:
	for i in range(state.get_node_count()):
		if state.get_node_name(i) == node_name:
			return i
	return -1


func _node_prop(state: SceneState, idx: int, prop: String) -> Variant:
	for p in range(state.get_node_property_count(idx)):
		if state.get_node_property_name(idx, p) == prop:
			return state.get_node_property_value(idx, p)
	return null


# --- 1. Prefab wiring -------------------------------------------------------------------------------------

func test_the_player_prefab_wires_the_third_person_body() -> void:
	var state := _state(PLAYER_SCENE)
	var idx := _node_index(state, "ThirdPersonBody")
	assert_true(idx >= 0, "Player.tscn must carry a ThirdPersonBody child (the character seen in third person)")
	# SceneState spells a direct child "./<name>"; anything deeper would carry a parent segment.
	assert_eq(str(state.get_node_path(idx)), "./ThirdPersonBody",
			"ThirdPersonBody must be a DIRECT child of the Player — the rig is mounted and yawed in the player's own frame")
	var host: Variant = _node_prop(state, idx, "host")
	assert_eq(str(host), "..", "ThirdPersonBody.host must be wired to the Player ('..'), or every entry point no-ops")
	var root := _node_index(state, "Player")
	assert_eq(str(_node_prop(state, root, "tp_body")), "ThirdPersonBody",
			"the Player's tp_body export must point at that child, or build() is never called")


func test_the_camera_rig_wires_the_third_person_arm_beside_the_shake_pivot() -> void:
	var state := _state(CAMERA_RIG_SCENE)
	var idx := _node_index(state, "CameraArm")
	assert_true(idx >= 0, "camera_rig.tscn must carry the CameraArm (ThirdPersonCamera) node")
	# ⭐The arm is a SIBLING of ScreenShake, never its parent: Head.camera / Head.screen_shake resolve
	# "ScreenShake/Camera3D" and "ScreenShake" BY NAME, and half the project reaches the camera through them.
	assert_eq(str(state.get_node_path(idx)), "./CameraArm",
			"CameraArm must hang off the rig ROOT — reparenting ScreenShake under it would rename the one stable camera path")
	var shake := _node_index(state, "ScreenShake")
	assert_eq(str(state.get_node_path(shake)), "./ScreenShake",
			"ScreenShake must stay a direct child of Head (Head.camera/screen_shake resolve it by that path)")
	assert_eq(state.get_node_type(idx), "SpringArm3D",
			"the arm must BE a SpringArm3D — the wall-avoidance cast is the engine's, not ours")
	# Built inert: an arm with a resting length would shove the camera back before anything asked it to.
	assert_eq(float(_node_prop(state, idx, "spring_length")), 0.0,
			"CameraArm must rest at zero length so a first-person boot is identical to one without this node")
	assert_not_null(_node_prop(state, idx, "shape"),
			"CameraArm needs a probe shape — a bare ray slips the lens through corners the sphere stops at")


func test_the_head_rig_exposes_the_arm_to_its_host() -> void:
	var head: Head = load("res://scripts/player/head.gd").new()
	assert_true(head.has_method("setup"), "Head.setup is the rig's one injection point")
	# Off-tree the getter must degrade to null rather than throw — an older camera_rig with no arm is "first
	# person only", not a crash.
	assert_null(head.camera_arm, "Head.camera_arm must be null when the rig has no arm authored")
	head.free()


func test_the_arm_rebases_the_rig_parts_that_measure_from_the_eye() -> void:
	# ⭐The pull-out drags everything under the camera with it. Three of those children encode a DISTANCE FROM
	# THE EYE and break if they ride along: the pickup ray's reach, the carried prop's anchor, and the torch's
	# beam origin. ThirdPersonCamera rebases them by name, so a rename in the rig silently disables the fix —
	# this is the test that catches that rename.
	var state := _state(CAMERA_RIG_SCENE)
	var tp_cam: GDScript = load(TP_CAMERA_SOURCE)
	for path in tp_cam.REBASED_NODES:
		var leaf: String = String(path).get_file()
		var idx := _node_index(state, leaf)
		assert_true(idx >= 0, "camera_rig.tscn must still carry '%s' — ThirdPersonCamera rebases it by path" % path)
		assert_eq(str(state.get_node_path(idx)), "./" + String(path),
				"'%s' must stay at that exact path, or the third-person rebase silently stops finding it" % path)


func test_the_first_person_body_composes_its_two_visibility_latches() -> void:
	# The legs/torso rig answers to the death/revive latch AND the view mode. Settling them separately is how a
	# revive taken in third person would put a SECOND body on the screen beside the character.
	var fp: FirstPersonBody = load("res://scripts/player/first_person_body.gd").new()
	var rig := BodyModelSwap.new()
	fp._fp_legs = rig
	fp.set_legs_visible(true)
	assert_true(rig.visible, "alive and in first person: the FP body is on screen")
	fp.set_third_person(true)
	assert_false(rig.visible, "third person hides it — the full-height character stands in the same spot")
	fp.set_legs_visible(true)
	assert_false(rig.visible, "a revive while in third person must NOT bring the first-person body back")
	fp.set_third_person(false)
	assert_true(rig.visible, "...and returning to first person restores it")
	rig.free()
	fp.free()


# --- 2. The fit arithmetic --------------------------------------------------------------------------------

func test_the_character_stands_at_npc_size_with_its_feet_on_the_floor() -> void:
	# ⭐The player is NOT fitted to their own eye height any more (that made them ~1.15 m against 1.85 m NPCs —
	# "he's WAAAY too small", 2026-09-18). At character_scale 1.0 they are exactly the size of the catalog rig
	# every NPC wears, and it is the FEET that are pinned, not the head.
	var tp: GDScript = load(TP_BODY_SOURCE)
	var floor_y := -1.0
	var clearance := 0.02
	var k := 1.0
	var mount: float = tp.fit_mount_y(floor_y, clearance, k)
	assert_almost_eq(mount - tp.FEET_BELOW_ORIGIN * k, floor_y + clearance, 0.0005,
			"the soles must sit one clearance above the capsule base, not through the floor or floating")
	assert_almost_eq(float(tp.BODY_SPAN) * k, 1.599, 0.001,
			"at scale 1 the character is the same 1.6 m the NPC rig is — the whole point of the size change")
	# ...and the head ends up ABOVE the camera pivot, which is the trade the size buys: the lens orbits chest
	# height like every third-person shooter instead of sitting inside the character's skull.
	var head_y: float = mount + tp.HEAD_ABOVE_ORIGIN * k
	assert_true(head_y > 0.0, "an NPC-sized character's head clears the player's eye (the camera pivot)")


func test_crouching_shrinks_the_character_and_keeps_the_feet_planted() -> void:
	var tp: GDScript = load(TP_BODY_SOURCE)
	var floor_y := -1.0
	var clearance := 0.02
	var standing := 1.0  # the player's eye rests 1.0 m above the capsule base
	# A crouch lowers the head while the capsule's BASE stays put (Crouch._apply), and the character scales by
	# the same ratio — the rig has no crouch animation, so the duck IS the size change.
	var crouched: float = tp.crouch_factor(0.402, standing, 0.0)
	assert_true(crouched < 1.0, "a crouched character must be smaller than a standing one")
	assert_true(crouched < 0.45, "the raw ratio really does collapse at full crouch — that is the clamp's reason")
	# ...but only so far.
	var clamped: float = tp.crouch_factor(0.402, standing, 0.72)
	assert_almost_eq(clamped, 0.72, 0.001, "the clamp holds the character at its floor")
	# Whatever the factor ends up being, the mount takes the FINAL scale, so the feet never leave the floor.
	var mount: float = tp.fit_mount_y(floor_y, clearance, clamped)
	assert_almost_eq(mount - tp.FEET_BELOW_ORIGIN * clamped, floor_y + clearance, 0.0005,
			"crouched or clamped, the feet must still be on the floor")
	assert_eq(tp.crouch_factor(1.0, standing, 0.72), 1.0, "standing is no crouch at all")


func test_the_crouch_factor_survives_a_degenerate_capsule() -> void:
	var tp: GDScript = load(TP_BODY_SOURCE)
	# A zero/negative standing height would divide by zero; it must answer "no crouch", never a collapsed or
	# inverted character (a negative scale renders every part inside-out).
	assert_eq(tp.crouch_factor(1.0, 0.0, 0.72), 1.0, "a degenerate standing height must not scale the character")
	assert_true(tp.crouch_factor(-5.0, 1.0, 0.72) > 0.0, "a nonsense eye height must still leave a positive scale")


# --- 3. The view model ------------------------------------------------------------------------------------

func test_the_first_person_view_model_is_hidden_in_third_person() -> void:
	# The three pre-existing arguments keep their exact meaning...
	assert_true(GunMesh.view_model_visible_now(true, false, null),
			"the view model shows in first person with the accessibility toggle on")
	assert_false(GunMesh.view_model_visible_now(false, false, null),
			"the accessibility toggle still gates everything")
	# ...and third person overrides all of them: there is a real gun in the character's hands out there.
	assert_false(GunMesh.view_model_visible_now(true, false, null, true),
			"a first-person gun must not draw while the camera is behind the character")


# --- 4. The input surface ---------------------------------------------------------------------------------

func test_the_view_toggle_exists_on_every_input_surface() -> void:
	assert_true(InputMap.has_action(InputManager.action_toggle_view),
			"ToggleView must be in the InputMap (project.godot [input]) or the key polls a dead action")
	var catalog := InputManager.action_catalog()
	assert_not_null(catalog, "the ActionCatalog must load")
	assert_true(catalog.rebindable_actions().has(InputManager.action_toggle_view),
			"ToggleView needs an ActionSpec row, or Options -> Controls can't rebind it")
	var drift: Dictionary = InputManager.validate_action_sources()
	assert_true((drift["code_missing_in_map"] as Array).is_empty(),
			"no action_* var may name an action the InputMap lacks: %s" % [drift["code_missing_in_map"]])
	assert_true((drift["code_missing_in_catalog"] as Array).is_empty(),
			"no action_* var may be missing from the rebind catalog: %s" % [drift["code_missing_in_catalog"]])


func test_middle_mouse_toggles_the_view_and_reads_first_in_prompts() -> void:
	var events := InputMap.action_get_events(InputManager.action_toggle_view)
	var mmb_at := -1
	for i in events.size():
		var mb := events[i] as InputEventMouseButton
		if mb != null and mb.button_index == MOUSE_BUTTON_MIDDLE:
			mmb_at = i
	assert_true(mmb_at >= 0, "middle mouse must toggle first/third person")
	# ⭐FIRST in the list on purpose: InputManager.get_action_binding() reports the first key/mouse event, so
	# every prompt and the Controls row read "Mouse 3" rather than the keyboard fallback.
	assert_eq(mmb_at, 0, "middle mouse must be the FIRST event, or prompts name the keyboard fallback instead")
	assert_true(events.size() > 1, "the keyboard fallback (P) must survive beside it")


func test_the_camera_only_owns_the_wheel_while_the_view_is_out() -> void:
	# The wheel is the hotbar's cycle in first person and the camera's distance dial in third — and the hand-off
	# is an explicit predicate on both sides, never a race between _unhandled_input handlers.
	var arm: ThirdPersonCamera = load(TP_CAMERA_SOURCE).new()
	var notch := InputEventMouseButton.new()
	notch.button_index = MOUSE_BUTTON_WHEEL_UP
	notch.pressed = true
	arm.blend = 0.0
	assert_false(arm.owns_wheel(notch), "in first person the wheel still belongs to the hotbar")
	arm.blend = 1.0
	assert_true(arm.owns_wheel(notch), "pulled out, the wheel dials the camera distance")
	# A REBOUND KEY on Hotbar Next/Prev has no camera meaning — yielding it would leave that key dead in third
	# person (the rule Hotbar._scope_owns_wheel already documents for the scope dial).
	var key := InputEventKey.new()
	key.physical_keycode = KEY_N
	key.pressed = true
	assert_false(arm.owns_wheel(key), "only a real wheel notch is the camera's — never a rebound key")
	arm.free()


func test_free_look_is_off_until_a_press_is_actually_held() -> void:
	var arm: ThirdPersonCamera = load(TP_CAMERA_SOURCE).new()
	assert_false(arm.free_look_active(), "a fresh arm is not free-looking")
	# The aim accessors and MouseInput both key off this, so it must never be true by default: a stuck `true`
	# would silently detach aim from the camera in first person.
	arm.blend = 1.0
	assert_false(arm.free_look_active(), "merely being in third person is not a free-look drag")
	arm.free()


func test_the_camera_distance_is_a_clamped_persisted_setting() -> void:
	var s: Object = load("res://managers/Settings.gd").new()
	assert_true(s.has_method("set_third_person_distance"), "the wheel writes the distance through one setter")
	s.set_third_person_distance(999.0)
	assert_eq(s.third_person_distance, Settings.TP_DISTANCE_MAX, "the wheel cannot push the lens past the ceiling")
	s.set_third_person_distance(-5.0)
	assert_eq(s.third_person_distance, Settings.TP_DISTANCE_MIN,
			"...nor inside the character's head, which would be a worse first person, not a closer third")
	s.free()


## THE VIEW IS THE PLAYER'S, NOT THE MENU'S. Both third-person rows were pulled from Options: the mode is the
## `ToggleView` bind (middle mouse / P / BACK) and the distance is the mouse wheel while pulled out, so a toggle
## and a slider duplicating them only gave the player a second, slower way to reach the same two knobs — and a
## menu row for a mode that deliberately never persists reads as a preference it is not. The setters stay (the key
## and the wheel call them); what must not come back is a catalog row for either.
func test_options_does_not_duplicate_the_view_key_or_the_zoom_wheel() -> void:
	var catalog := load("res://resources/settings/SettingsCatalog.tres")
	assert_not_null(catalog, "SettingsCatalog.tres must load")
	for spec in catalog.specs:
		assert_ne(str(spec.key), "third_person",
				"the view mode belongs to the ToggleView bind — an Options row for it is a duplicate")
		assert_ne(str(spec.key), "third_person_distance",
				"the pull-out distance belongs to the mouse wheel — an Options slider for it is a duplicate")
	var s: Object = load("res://managers/Settings.gd").new()
	assert_true(s.has_method("set_third_person_camera"), "Settings still owns the setter the ToggleView bind calls")
	assert_true(s.has_method("set_third_person_distance"), "...and the one the mouse wheel calls")
	assert_false(s.third_person_camera, "first person stays the default — this is a first-person game")
	s.free()
