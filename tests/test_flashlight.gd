extends GutTest

## The player FLASHLIGHT (scenes/player/flash_light.gd on the camera rig's FlashLight node).
##
## Two layers, both DRIVEN rather than read as source text:
##   1. The AUTHORING contract on the real prefabs (camera_rig.tscn / Player.tscn): the rig's node exists, is a real
##      light rather than the laser, starts off, casts shadows, reaches the view-model layer, and the beam origin is
##      held off the eye. A .tscn holds no comments, so these pins are the only thing guarding an Inspector re-author.
##   2. The SCRIPT's behaviour, on a real flash_light.gd mounted in-tree under a `_Wielder` stub — the smallest
##      Player surface it duck-types (is_alive / pending_verb_actions, plus the carried_light field the stealth sampler
##      stamps). The stub is a Node3D, so _process's `get_parent().global_rotation` is legal; Player._ready() never runs.
##      The per-frame work is stepped by calling _process directly (processing is switched off on mount), so every
##      assert reads one deterministic frame.
##
## It ALSO guards the boundary with the LASER SIGHT, which used to live on this very node and share its key. The
## laser is back as its own rig node (scenes/player/laser_sight_rig.gd) and the two must never re-merge, so the
## tests near the middle drive both sides: the torch lights holstered with no chip, and the laser has no key and
## costs no stealth. The contextual F key's basic arbitration is also pressed for real in
## tests/test_flashlight_contextual_key.gd; the tests at the bottom here cover the pad and the modal/dialogue gate.

const RIG := "res://scenes/player/camera_rig.tscn"
const SCRIPT_PATH := "res://scenes/player/flash_light.gd"
const LASER_PATH := "res://scenes/player/laser_sight_rig.gd"
const CUTSCENE_PLAYER_PATH := "res://scripts/components/cutscene_player.gd"
## No class_name on the registry (deliberate — nothing for the global class cache to miss), so preload it.
const AbilityRegistry := preload("res://scripts/components/abilities/ability_registry.gd")
const FRAME := 1.0 / 60.0

## The Player surface both rig scripts duck-type off an ANCESTOR: flash_light.gd walks up for is_alive() and reads
## pending_verb_actions(); laser_sight_rig.gd walks up for has_mechanic(). carried_light / light_exposure / crouch are
## the fields PlayerLightLevel writes and Perception reads off a target.
class _Wielder extends Node3D:
	var alive: bool = true
	var pending: Array[StringName] = []
	var mechanics: Array[StringName] = []   ## empty = a fresh player with no chip installed
	var carried_light: float = 0.0
	var light_exposure: float = 1.0
	var crouch: Node = null
	func is_alive() -> bool:
		return alive
	func pending_verb_actions() -> Array[StringName]:
		return pending
	func has_mechanic(id: StringName) -> bool:
		return mechanics.has(id)

## The Weapon/Attack node the laser reads (current weapon + holstered state).
class _AttackStub extends Node:
	var current_weapon: Object = null
	var holstered: bool = false

## A gun as the laser reads it: the per-weapon sight flag and the throw distance.
class _GunStub extends RefCounted:
	var has_laser_sight: bool = true
	var effective_range: float = 20.0

## Harness CONTROLS for the no-keybind test: the smallest scripts that DO hear the Light action, one per route a laser
## could grow a key through. Each is driven by the exact stepping/delivery the laser gets, so a laser that "never
## moved" is only evidence while these still hear the key.
## A per-frame POLL from the physics callback (the scripts/player/crouch.gd idiom): one entry per stepped frame.
class _PollEar extends Node:
	var held: Array = []
	func _physics_process(_delta: float) -> void:
		held.append(Input.is_action_pressed(InputManager.action_light))

## An EVENT handler: one entry per Light event it is handed, in arrival order.
class _KeyEar extends Node:
	var heard: Array = []
	func _unhandled_input(event: InputEvent) -> void:
		if event.is_action_pressed(InputManager.action_light):
			heard.append("press")
		elif event.is_action_released(InputManager.action_light):
			heard.append("release")

var _saved_dialogue: DialogueResource = null
var _saved_suspended: bool = false
var _saved_wait_open: bool = false
var _saved_cutscene: bool = false
var _saved_sight_mult: float = 1.0


func before_each() -> void:
	_saved_dialogue = DialogueManager._active
	_saved_suspended = DialogueManager._suspended
	_saved_wait_open = WaitScreen._is_open
	_saved_cutscene = CutscenePlayer.is_active()
	_saved_sight_mult = GameSettings.light_stealth.carried_light_sight_mult


func after_each() -> void:
	# Every gate these tests stage lives on a process-global (autoload fields, a static, a shared .tres, the Input
	# singleton). The tests restore inline before asserting; this is the second net so a failed assert can never
	# leave a later file input-locked or mid-conversation.
	DialogueManager._active = _saved_dialogue
	DialogueManager._suspended = _saved_suspended
	WaitScreen._is_open = _saved_wait_open
	load(CUTSCENE_PLAYER_PATH).set("_active", _saved_cutscene)
	GameSettings.light_stealth.carried_light_sight_mult = _saved_sight_mult
	if Input.is_action_pressed(InputManager.action_light):
		Input.action_release(InputManager.action_light)
	_saved_dialogue = null


# --- harness ----------------------------------------------------------------------------------------------------

func _rig_torch() -> Dictionary:
	var scene := load(RIG) as PackedScene
	assert_not_null(scene, "camera_rig.tscn must load — it carries the flashlight")
	var inst := scene.instantiate()
	var torch := inst.find_child("FlashLight", true, false)
	return {"root": inst, "torch": torch}

func _wielder_in_tree() -> _Wielder:
	var w := _Wielder.new()
	add_child_autofree(w)
	return w

## Mount a real flash_light.gd under `parent` the way camera_rig.tscn does (with its FlashlightClick child). `exports`
## are applied BEFORE the node enters the tree, because _ready reads beam_gradient / reveals_you / light_color once.
func _mount_torch(parent: Node, exports: Dictionary = {}) -> SpotLight3D:
	var torch := SpotLight3D.new()
	torch.set_script(load(SCRIPT_PATH))
	var click := AudioStreamPlayer3D.new()
	click.name = "FlashlightClick"
	torch.add_child(click)
	for key in exports:
		torch.set(key, exports[key])
	parent.add_child(torch)
	torch.set_process(false)
	return torch

## Mount a real laser_sight_rig.gd at the laser's authored punch. With `sub_lights`, it carries the NEGATIVE carving
## child the rig authors plus a grandchild lamp (the "designer adds a third light later" case).
func _mount_laser(parent: Node, sub_lights: bool) -> SpotLight3D:
	var laser := SpotLight3D.new()
	laser.set_script(load(LASER_PATH))
	laser.light_energy = 1000.0
	laser.spot_range = 20.0
	if sub_lights:
		var carve := SpotLight3D.new()
		carve.name = "Carve"
		carve.light_negative = true
		carve.light_energy = 1000.0
		carve.spot_range = 20.0
		var shaper := OmniLight3D.new()
		shaper.name = "Shaper"
		shaper.light_energy = 1000.0
		shaper.omni_range = 20.0
		carve.add_child(shaper)
		laser.add_child(carve)
	parent.add_child(laser)
	laser.set_process(false)
	laser.set_physics_process(false)
	return laser

## Give the wielder a Weapon/Attack node holding `gun` (null = unarmed).
func _arm(w: Node, gun: RefCounted, holstered: bool) -> _AttackStub:
	var weapon_root := Node.new()
	weapon_root.name = "Weapon"
	w.add_child(weapon_root)
	var attack := _AttackStub.new()
	attack.name = "Attack"
	attack.current_weapon = gun
	attack.holstered = holstered
	weapon_root.add_child(attack)
	return attack

## The player's body glow, at the node name the torch resolves off its wielder.
func _add_glow(w: Node, color: Color) -> OmniLight3D:
	var glow := OmniLight3D.new()
	glow.name = "PlayerEmittingLight"
	glow.light_color = color
	w.add_child(glow)
	return glow

## A PlayerLightLevel sampling `host`. No LOS rays (there is no geometry here) and no scene-wide light scan — the
## tests ask it about specific lamps through its own per-light and carried-light samplers.
func _light_meter_on(host: _Wielder) -> PlayerLightLevel:
	var meter := PlayerLightLevel.new()
	meter.host = host
	meter.require_los = false
	meter.auto_collect = false
	host.add_child(meter)
	meter.set_physics_process(false)
	return meter

func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = true
	return e

func _press(torch: SpotLight3D, code: Key) -> void:
	torch._unhandled_input(_key(code))

func _lit(torch: SpotLight3D) -> bool:
	return torch.get(&"_light_on")

func _switch_on(torch: SpotLight3D) -> void:
	torch.set(&"_light_on", true)
	torch._process(FRAME)

func _assert_color_near(actual: Color, expected: Color, msg: String) -> void:
	assert_true(absf(actual.r - expected.r) < 0.001 and absf(actual.g - expected.g) < 0.001 \
			and absf(actual.b - expected.b) < 0.001, "%s (got %s, expected %s)" % [msg, actual, expected])

func _is_inspector_export(obj: Object, prop: StringName) -> bool:
	for p in obj.get_property_list():
		if StringName(p["name"]) == prop:
			var usage: int = p["usage"]
			return (usage & PROPERTY_USAGE_EDITOR) != 0 and (usage & PROPERTY_USAGE_STORAGE) != 0
	return false

## A pressed pad event for the first joypad button bound to `action` in the LIVE InputMap (null if none).
func _pad_press_for(action: StringName) -> InputEventJoypadButton:
	for e in InputMap.action_get_events(action):
		var bound := e as InputEventJoypadButton
		if bound != null:
			var press := InputEventJoypadButton.new()
			press.button_index = bound.button_index
			press.device = maxi(bound.device, 0)
			press.pressed = true
			return press
	return null

## One hand-stepped frame of a node's per-frame work: _physics_process first, then _process, each only where the
## node's script implements it. Mounted nodes have both switched off, so these calls are the only frames they get. A
## key polled from the PHYSICS callback is still a key (scripts/player/crouch.gd reads Crouch there), so stepping
## _process alone would leave that whole route unexercised. Called synchronously from the test body, so an Input poll
## in either callback reads the same frame state as the test's own same-frame precondition.
func _step_frame(node: Node) -> void:
	if node.has_method(&"_physics_process"):
		node.call(&"_physics_process", FRAME)
	if node.has_method(&"_process"):
		node.call(&"_process", FRAME)

## Type real Light keystrokes at `node`: F, then L (both bound to Light), each as a PRESS followed by its RELEASE, one
## event at a time to every input callback the node's script implements, in the order the engine visits them. After
## EACH delivery the node gets a stepped frame and `holds` is asked whether the invariant still stands. Returns
## {deliveries: int, first_break: String}; first_break names the first delivery `holds` failed after ("" = never).
func _light_keystrokes_through(node: Node, holds: Callable) -> Dictionary:
	var deliveries := 0
	var first_break := ""
	for code in [KEY_F, KEY_L]:
		for pressed in [true, false]:
			for hook in [&"_input", &"_shortcut_input", &"_unhandled_key_input", &"_unhandled_input"]:
				if not node.has_method(hook):
					continue
				var event := _key(code)
				event.pressed = pressed
				node.call(hook, event)
				deliveries += 1
				_step_frame(node)
				var still_holds: bool = holds.call()
				if first_break == "" and not still_holds:
					first_break = "%s %s via %s" % [OS.get_keycode_string(code), "press" if pressed else "release", hook]
	return {"deliveries": deliveries, "first_break": first_break}


# --- the authored rig -------------------------------------------------------------------------------------------

func test_rig_carries_a_real_flashlight_that_starts_off() -> void:
	var d := _rig_torch()
	var torch = d["torch"]
	assert_not_null(torch, "the camera rig must carry a FlashLight node — it IS the flashlight (no ability gate)")
	assert_true(torch is SpotLight3D, "the flashlight must be a SpotLight3D (a cone you can aim), not a point lamp")
	assert_false((torch as SpotLight3D).visible,
		"the torch must be authored OFF: a fresh game starts dark and the player reaches for F")
	# The retired LASER was a red, 0.5-degree, energy-1000 pinprick. A flashlight is the opposite of those
	# numbers, so pin the SHAPE (a wide, sane-energy cone) rather than exact tuning a designer may retune.
	# ⭐The old "every channel > 0.5" white-beam pin is GONE ON PURPOSE: the beam now matches the player's body
	# glow, which is a saturated cyan (r ~ 0.004). That pin would have rejected the requested colour outright.
	# The anti-laser guarantee it was really making is carried by the two shape asserts below.
	var l := torch as SpotLight3D
	assert_gt(l.spot_angle, 10.0, "a flashlight throws a WIDE cone (the laser's 0.5 degrees was a pinprick)")
	assert_lt(l.light_energy, 100.0, "a flashlight is a lamp, not the laser's energy-1000 dot")
	d["root"].free()


func test_authored_beam_colour_matches_the_player_body_glow() -> void:
	# ⭐THE CROSS-SCENE CONTRACT the user asked for: "make the flashlight the same colour as the light the player
	# emits". The beam tracks the glow LIVE at runtime (it is HP-tinted), but the two AUTHORED values must agree
	# too — otherwise a rig with match_player_light off, or a frame before the glow resolves, shows a beam that
	# contradicts the body light. Pinned as an equality between the two scenes rather than as a hue literal, so
	# retinting the player glow keeps the torch honest without anyone remembering to edit a second file.
	var d := _rig_torch()
	var beam := (d["torch"] as SpotLight3D).light_color
	var player := (load("res://scenes/player/Player.tscn") as PackedScene).instantiate()
	var glow := player.find_child("PlayerEmittingLight", true, false) as Light3D
	assert_not_null(glow, "Player.tscn must carry PlayerEmittingLight — it is the colour the torch matches")
	if glow != null:
		assert_almost_eq(beam.r, glow.light_color.r, 0.001, "beam RED must match the player's emitted light")
		assert_almost_eq(beam.g, glow.light_color.g, 0.001, "beam GREEN must match the player's emitted light")
		assert_almost_eq(beam.b, glow.light_color.b, 0.001, "beam BLUE must match the player's emitted light")
	player.free()
	d["root"].free()


func test_body_glow_is_kept_out_of_the_volumetric_fog() -> void:
	# ⭐THE WILL-O'-THE-WISP PIN. The body glow is welded to the Player origin, so it can never lag POSITIONALLY —
	# but Godot's volumetric fog is a temporally-accumulated froxel grid, and its reprojection carries the PREVIOUS
	# frame's in-scattering forward by volumetric_fog_temporal_reprojection_amount (engine default 0.9) with no
	# per-light motion vectors. Reprojection is world-space, so the fog this lamp lit last frame stays where it
	# was in the WORLD — which is behind a moving player. At 0.9 the residue is still ~10% bright 22 frames later:
	# roughly 1.8 m behind at a sprint, against an omni_range of only ~2.13. Every play level runs
	# volumetric_fog_enabled = true and leaves the reprojection default alone, and project.godot turns the froxel
	# blur OFF (environment/volumetric_fog/use_filter=0), so the residue keeps hard block edges. The result reads
	# as a second, dimmer cyan ball chasing you — a will-o'-the-wisp, exactly the folklore the colour suggests.
	#
	# Authoring the light OUT of the fog is the fix, and it costs nothing this project relies on: the stealth meter
	# (player_light_level.gd) weighs light_energy / omni_range / visible and never reads fog energy, CrouchLightDouse
	# writes light_energy only, and the HP tint rides light_color — so detection, the crouch douse and the
	# health-colour readout are all untouched. view_model.tscn already does the same on the muzzle flash, the
	# project's other fast-moving player-attached lamp.
	#
	# Pinned because a .tscn holds no comments: re-author this node in the Inspector, lose this line, and the wisp
	# comes back silently with nothing to notice it. If a designer ever WANTS a halo in the air around the player,
	# the honest lever is the level Environment's reprojection amount (+ use_filter), not this property — lowering
	# fog energy dims the ghost and the halo by the same factor and leaves the trail exactly as long.
	var player := (load("res://scenes/player/Player.tscn") as PackedScene).instantiate()
	var glow := player.find_child("PlayerEmittingLight", true, false) as Light3D
	assert_not_null(glow, "Player.tscn must carry PlayerEmittingLight — it is the lamp this rule is about")
	if glow != null:
		assert_eq(glow.light_volumetric_fog_energy, 0.0,
				"the player's body glow must contribute NOTHING to volumetric fog — the froxel grid's temporal " +
				"reprojection has no per-light motion vectors, so a lamp riding the player smears ~1.8 m behind " +
				"at a sprint and reads as a cyan wisp following them")
	player.free()


func test_flashlight_reaches_the_view_model_layer() -> void:
	# The gun renders in its OWN camera pass that culls to VIEW_MODEL_LAYER, and lights are camera-cull-masked —
	# so a torch on the world layer alone would light the street but leave the weapon in your hands unlit. The
	# node's `layers` must span BOTH for your own flashlight to fall on your own gun.
	var d := _rig_torch()
	var l := d["torch"] as SpotLight3D
	assert_ne(l.layers & ViewModelCamera.VIEW_MODEL_LAYER, 0,
		"the flashlight must include the view-model layer or it never lights the gun in your hands")
	assert_ne(l.layers & 1, 0, "...and layer 1, or it never lights the world")
	d["root"].free()


func test_flashlight_click_and_origin_marker_are_wired() -> void:
	var d := _rig_torch()
	var torch = d["torch"]
	assert_not_null(torch.get_node_or_null("FlashlightClick"),
		"the toggle's click is the authored FlashlightClick child (mute or delete it for a silent torch)")
	assert_not_null(torch.get(&"light_position"),
		"light_position must be wired to the rig's LightPosition — it is where the beam originates each frame")
	d["root"].free()


func test_the_beam_origin_is_held_off_the_eye_so_shadows_are_visible() -> void:
	# ⭐THE SHADOW PIN, and it is pure GEOMETRY rather than a render setting. A light sitting exactly on the
	# camera puts every shadow it casts perfectly BEHIND the thing casting it, so each caster hides its own
	# shadow and the beam reads as flat, shadowless fill — with shadow_enabled true the entire time. That is
	# what the rig shipped: LightPosition was authored at the Camera3D's local origin, and the FlashLight node's
	# own -0.187 X offset was DEAD (top_level + the per-frame global_position write overwrite it every frame),
	# so no one could see the authored intent was not reaching the screen.
	#
	# Verified by eye with scripts/tools/probes/flashlight_qa_shots.gd (a real windowed GPU run — a box in front of a
	# wall, at night): on the eye the wall is blank, 0.27 m off it a hard shadow appears. No unit test can see
	# a shadow, so what is pinned here is the SEPARATION that causes one.
	#
	# ⭐The upper bound is NOT the authored 0.5 m capsule radius, and the difference is a real engine trap:
	# CapsuleShape3D.height clamps radius to height/2 and NEVER restores it, so the first crouch of a session
	# (crouch.gd writes height only, ratio 0.6) permanently narrows the player's collider to 0.4589 m — measured
	# on 4.7.1 with this rig's numbers. An origin outside the capsule can be shoved through a wall the player is
	# leaning on, and the beam would light the room on the far side. So the ceiling here is 0.35: comfortably
	# inside even the crouched radius, rather than sanctioning values that sit ON the capsule wall — which is
	# exactly the surface that contacts geometry, i.e. the failure this message warns about.
	var d := _rig_torch()
	var marker := d["torch"].get(&"light_position") as Marker3D
	assert_not_null(marker, "the beam origin marker must be wired — it is what this test measures")
	if marker != null:
		# The measurement below is marker.position — LOCAL — which is only the eye-relative offset while the
		# marker's parent IS the camera. Reparent it and the pin would happily report a healthy 0.27 with the
		# beam back on the lens, so the frame of reference is asserted here rather than assumed. (Deliberately
		# NOT global_position.distance_to(camera): this rig is instantiated off-tree and GUT 9.6 turns the
		# resulting engine errors into failures.)
		assert_true(marker.get_parent() is Camera3D,
			"LightPosition must stay a child of the Camera3D — its LOCAL position is what makes this an " +
			"eye-relative offset at all; reparent it and this pin silently measures the wrong origin")
		var offset: float = marker.position.length()
		assert_gt(offset, 0.1,
			"the beam origin must be held OFF the eye (>0.1 m) or the torch casts no visible shadow — every " +
			"shadow lands perfectly behind its own caster and the world reads as flat fill")
		assert_lt(offset, 0.35,
			"...but must stay well inside the player's capsule (0.4589 m radius once they have crouched " +
			"once), or leaning on a wall puts the beam origin through it and lights the far side")
	d["root"].free()


func test_the_torch_casts_real_time_shadows() -> void:
	# The other half of the pair above: the separation only buys anything while the light actually renders a
	# shadow map. A .tscn holds no comments, so re-authoring this node in the Inspector can drop the flag with
	# nothing left to notice it — and the failure looks exactly like the eye-coincidence bug, which is how it
	# would get misdiagnosed.
	var d := _rig_torch()
	var l := d["torch"] as SpotLight3D
	assert_true(l.shadow_enabled,
		"the flashlight must cast real-time shadows — it is the player's only light in a dark level, and a " +
		"torch that lights straight through props reads as fog, not as a beam")
	d["root"].free()


# --- the beam colour: live glow copy, white core, flat fallback --------------------------------------------------

func test_beam_tracks_the_glow_live_rather_than_copying_a_literal() -> void:
	# The glow's colour is HP-driven (Player.health_light_color_for, off the `damaged` signal), so a hard-coded hue
	# would only ever be right at full health. The torch must COPY whatever the glow node holds this frame — so the
	# glow here is given colours no HP blend produces (green, blue): only a copy can land them on the beam.
	var player := (load("res://scenes/player/Player.tscn") as PackedScene).instantiate()
	assert_true(player.get_node_or_null(^"PlayerEmittingLight") is Light3D,
		"Player.tscn must carry PlayerEmittingLight as a DIRECT child of the root — the torch resolves the glow " +
		"off its wielder by that exact path, so nesting it anywhere else leaves the beam at its authored colour")
	player.free()

	var authored := Color(0.003921569, 1.0, 1.0)   # the healthy cyan the rig authors
	var w := _wielder_in_tree()
	var glow := _add_glow(w, Color(0.2, 0.9, 0.1))
	var flat := _mount_torch(w, {"beam_gradient": false, "light_color": authored})
	var fixed := _mount_torch(w, {"beam_gradient": false, "match_player_light": false, "light_color": authored})
	flat._process(FRAME)
	fixed._process(FRAME)
	_assert_color_near(flat.light_color, Color(0.2, 0.9, 0.1),
		"with the gradient off the WHOLE beam must take the body glow's colour, read off the live node")
	_assert_color_near(fixed.light_color, authored,
		"match_player_light OFF is the designer switch: the beam keeps its authored colour even with a glow to copy")
	assert_true(_is_inspector_export(fixed, &"match_player_light"),
		"match_player_light must be an Inspector switch (stored in the scene) — matching the body glow is a " +
		"designer choice, not a code edit")

	glow.light_color = Color(0.9, 0.1, 0.05)   # the player just got hurt
	flat._process(FRAME)
	_assert_color_near(flat.light_color, Color(0.9, 0.1, 0.05),
		"the beam must follow the glow on the very next frame — a hurt player reads their HP off the wall")

	glow.free()   # the player rig is rebuilt (respawn) and its glow with it
	_add_glow(w, Color(0.1, 0.3, 1.0))
	flat._process(FRAME)
	_assert_color_near(flat.light_color, Color(0.1, 0.3, 1.0),
		"a freed glow must be re-resolved, not held dead — a rebuilt player's torch has to re-link to the new glow")

	var graded := _mount_torch(w, {"light_color": authored})   # the shipped default: beam_gradient on
	graded._process(FRAME)
	assert_eq(graded.light_color, Color.WHITE,
		"with the gradient on the glow must never tint light_color — that is the white CORE")
	var tex := graded.light_projector as GradientTexture2D
	assert_true(tex != null and tex.gradient != null, "precondition: the gradient beam built its projector")
	if tex != null and tex.gradient != null:
		_assert_color_near(tex.gradient.get_color(tex.gradient.get_point_count() - 1), Color(0.1, 0.3, 1.0),
			"...the live glow colour lands on the gradient's RIM instead")


## ⭐THE WHITE CORE. A SpotLight3D has ONE light_color, so "white in the middle, HP colour at the rim" is not a
## property you can set — it is a light PROJECTOR (a radial GradientTexture2D the light multiplies itself by).
## These asserts are behavioural: they build the real ramp on a real node and read what came out.
##
## Built OFF-TREE deliberately: _build_beam_gradient touches nothing outside the node, so calling it directly is
## honest, and it isolates the ramp from _ready's wielder walk.
func test_the_beam_is_a_white_cored_gradient_rather_than_one_flat_colour() -> void:
	var torch: SpotLight3D = load(SCRIPT_PATH).new()
	var authored := Color(0.003921569, 1.0, 1.0)   # the healthy cyan the rig authors
	torch.light_color = authored
	torch.set("_authored_color", authored)          # what _ready captures before the gradient claims light_color
	torch.call("_build_beam_gradient")

	assert_eq(torch.light_color, Color.WHITE,
		"the light itself must go WHITE — the projector is a MULTIPLY, so any tint here would stain the core")
	var tex := torch.light_projector as GradientTexture2D
	assert_not_null(tex, "the beam's gradient IS the light_projector; without it there is no core/rim at all")
	if tex != null:
		assert_eq(tex.fill, GradientTexture2D.FILL_RADIAL,
			"the ramp must run from the middle of the cone outward, not left-to-right across it")
		assert_eq(tex.fill_from, Vector2(0.5, 0.5), "the white core sits at the centre of the projected square")
		# ⭐The rim lands at UV radius 0.5 because a spot projector covers the light's SQUARE frustum and the lit
		# circle is the one inscribed in it. Reaching to a corner would push the HP colour outside the cone.
		assert_eq(tex.fill_to, Vector2(1.0, 0.5),
			"the ramp must END at the cone's rim (radius 0.5), or the tint never fully arrives on screen")
		var ramp := tex.gradient
		assert_not_null(ramp, "the projector must be driven by a Gradient — that is what a colour change rewrites")
		if ramp != null:
			assert_eq(ramp.get_color(0), Color.WHITE, "the centre stop is white: that is the whole request")
			assert_almost_eq(ramp.get_color(ramp.get_point_count() - 1).r, authored.r, 0.001,
				"with no player glow to read, the rim falls back to the AUTHORED beam colour, never white or black")

	# The rim tracks HP live: hand it the damaged red and the ring must follow while the core stays white.
	torch.call("_set_beam_rim", Color(1.0, 0.05, 0.02))
	var rim: Color = (torch.light_projector as GradientTexture2D).gradient.get_color(2)
	assert_almost_eq(rim.r, 1.0, 0.001, "a hurt player's rim must carry the damaged RED")
	assert_almost_eq(rim.g, 0.05, 0.001, "a hurt player's rim must carry the damaged GREEN")
	assert_eq(torch.light_color, Color.WHITE, "bleeding must never tint the CORE — that is the point of the split")
	torch.free()


## The loudness dial. beam_rim_tint is what a designer reaches for when the coloured ring is too strong; at 0 the
## rim is white and the beam is visually back to a plain torch WITHOUT turning the gradient machinery off.
func test_the_rim_tint_dial_can_pull_the_ring_back_to_white() -> void:
	var torch: SpotLight3D = load(SCRIPT_PATH).new()
	torch.beam_rim_tint = 0.0
	torch.call("_build_beam_gradient")
	torch.call("_set_beam_rim", Color(1.0, 0.05, 0.02))
	assert_eq((torch.light_projector as GradientTexture2D).gradient.get_color(2), Color.WHITE,
		"beam_rim_tint 0 must leave the rim white — the soft opt-out, so nobody has to disable beam_gradient")
	torch.free()


## Switching the gradient OFF must leave the pre-gradient torch exactly as it was: one flat, fully tinted cone
## and NO projector. This is the escape hatch the class doc promises for the white volumetric shaft. Driven through
## the real _ready (in-tree), with the shipped default as the control, so the "no projector" read is not vacuous.
func test_the_gradient_can_be_switched_off_back_to_a_flat_tinted_beam() -> void:
	var cyan := Color(0.003921569, 1.0, 1.0)
	var w := _wielder_in_tree()
	var graded := _mount_torch(w, {"beam_gradient": true, "light_color": cyan})
	var flat := _mount_torch(w, {"beam_gradient": false, "light_color": cyan})
	assert_true(graded.light_projector != null,
		"control: with the gradient on, _ready builds the white-core projector")
	assert_eq(graded.light_color, Color.WHITE, "control: ...and hands the tint over to it")
	assert_true(flat.light_projector == null,
		"with the gradient off nothing may author a projector — a stale one would silently keep the white core")
	_assert_color_near(flat.light_color, cyan,
		"...and the light keeps its authored tint across the whole cone, exactly the pre-gradient torch")
	assert_true(_is_inspector_export(flat, &"beam_gradient"),
		"beam_gradient must be an Inspector switch (stored in the scene) — the escape hatch is a designer toggle, " +
		"not a code edit")


func test_beam_colour_is_cosmetic_and_cannot_move_stealth() -> void:
	# PlayerLightLevel weighs lights by energy/range/distance, so recolouring the torch must not have quietly become
	# a gameplay change. Drive a real recolour (bright white -> a dim red, gradient off so light_color itself moves)
	# and ask the sampler about the SAME lamp before and after. Energy 0.5 keeps both readings clear of their 1.0
	# clamps, so a colour-weighted sampler would visibly change its answer.
	var w := _wielder_in_tree()
	var meter := _light_meter_on(w)
	var glow := _add_glow(w, Color.WHITE)
	var torch := _mount_torch(w, {"beam_gradient": false, "light_energy": 0.5})
	_switch_on(torch)
	var at := w.global_position
	var meter_white := meter._light_contribution_for(torch, at)
	var beacon_white := meter._sample_carried()

	glow.light_color = Color(0.25, 0.0, 0.0)
	torch._process(FRAME)
	_assert_color_near(torch.light_color, Color(0.25, 0.0, 0.0), "precondition: the beam really did recolour")
	assert_gt(meter_white, 0.0, "precondition: the lit torch feeds the light meter at all")
	assert_gt(beacon_white, 0.0, "precondition: ...and the carried-light beacon")
	assert_almost_eq(meter._light_contribution_for(torch, at), meter_white, 0.0001,
		"the light meter must read the same exposure off a red beam as a white one — colour is a look change only")
	assert_almost_eq(meter._sample_carried(), beacon_white, 0.0001,
		"...and the beacon penalty must not care what colour the torch is either")


# --- the torch vs the weapon, and how it follows you ------------------------------------------------------------

func test_flashlight_is_not_gated_on_a_weapon_or_an_ability() -> void:
	# The whole point of the swap: the old laser only lit up with a laser-capable weapon DRAWN and the `laser_sight`
	# mechanic unlocked. A flashlight must answer to none of that — it works holstered, unarmed, and for every player
	# from the first frame. The wielder here owns no mechanic at all and has an Attack node that is holstered.
	var w := _wielder_in_tree()
	var attack := _arm(w, null, true)
	var torch := _mount_torch(w)
	_press(torch, KEY_L)
	torch._process(FRAME)
	assert_true(_lit(torch), "an unarmed, holstered player with no chips must still be able to switch the torch on")
	assert_true(torch.visible, "...and the beam must actually be showing — nothing weapon-side may hide it")
	var sightless := _GunStub.new()
	sightless.has_laser_sight = false
	attack.current_weapon = sightless
	torch._process(FRAME)
	assert_true(torch.visible,
		"holding a gun with no laser sight, still holstered, must not put the torch out — that flag is the laser's")


func test_the_beam_origin_follows_the_marker_the_scene_wires_every_frame() -> void:
	# light_position is an @export the SCENE wires, never a brittle relative path. So the marker here is deliberately
	# NOT named LightPosition, and a decoy that IS sits at the eye: a hard-coded "../LightPosition" lands on the decoy.
	var w := _wielder_in_tree()
	w.global_position = Vector3(4.0, 0.0, 0.0)
	var decoy := Marker3D.new()
	decoy.name = "LightPosition"
	w.add_child(decoy)
	var origin := Marker3D.new()
	origin.name = "OffHandOrigin"
	origin.position = Vector3(-0.2, -0.15, 0.0)
	w.add_child(origin)
	var torch := _mount_torch(w, {"light_position": origin})
	torch._process(FRAME)
	assert_lt(torch.global_position.distance_to(origin.global_position), 0.0001,
		"the beam must originate at whatever marker light_position points to (got %s, marker %s)" %
		[torch.global_position, origin.global_position])
	# The torch is top_level, so moving the player does not carry it along — only the per-frame snap does.
	w.global_position = Vector3(4.0, 0.0, 2.0)
	torch._process(FRAME)
	assert_lt(torch.global_position.distance_to(origin.global_position), 0.0001,
		"as the player walks, the beam origin must re-snap to the marker EVERY frame (got %s, marker %s)" %
		[torch.global_position, origin.global_position])
	assert_true(_is_inspector_export(torch, &"light_position"),
		"light_position must be an Inspector export (stored in the scene) — camera_rig.tscn wires the origin marker " +
		"through it; a plain var hides it from the designer and the next re-save of the rig drops that wiring")


func test_the_beam_trails_the_aim_identically_at_any_frame_rate() -> void:
	# The hand-held lag: the beam eases toward where the camera (its parent) looks. Two 60 fps frames must land
	# exactly where one 30 fps frame does, or the torch feels heavier on a slow machine than a fast one.
	var w := _wielder_in_tree()
	var torch := _mount_torch(w)
	torch.set(&"_light_on", true)
	w.rotation = Vector3(0.0, 1.0, 0.0)       # the camera has just turned 1 rad...
	torch.global_rotation = Vector3.ZERO      # ...and the beam is still pointing where it was
	torch._process(1.0 / 60.0)
	var one_frame_at_60 := torch.global_rotation.y
	torch._process(1.0 / 60.0)
	var two_frames_at_60 := torch.global_rotation.y
	torch.global_rotation = Vector3.ZERO
	torch._process(1.0 / 30.0)
	var one_frame_at_30 := torch.global_rotation.y
	assert_gt(one_frame_at_60, 0.0, "a lit beam must start turning toward the aim on the first frame")
	assert_lt(one_frame_at_60, 0.99, "...but LAG behind it — a rigid snap is a lamp bolted to your skull, not a torch")
	assert_gt(two_frames_at_60, one_frame_at_60, "...and keep closing the gap frame after frame")
	assert_almost_eq(two_frames_at_60, one_frame_at_30, 0.0005,
		"two frames at 60 fps must land exactly where one frame at 30 fps does — the lag is frame-rate independent")

	torch.global_rotation = Vector3.ZERO
	torch.follow_rate = 60.0
	torch._process(1.0 / 60.0)
	assert_gt(torch.global_rotation.y, one_frame_at_60 + 0.05,
		"follow_rate is the live dial: a higher rate must hug the aim tighter over the same frame")
	assert_true(_is_inspector_export(torch, &"follow_rate"),
		"follow_rate must be an Inspector export (stored in the scene) — designer-tunable smoothing, not a hidden number")


func test_a_dark_torch_snaps_to_the_aim_so_switching_on_never_swings_in() -> void:
	# While OFF the beam rides the aim exactly, so a torch switched on mid-turn lights where you are looking instead
	# of sweeping in from wherever it last pointed. The lit case is the control that the same turn is otherwise eased.
	var w := _wielder_in_tree()
	var torch := _mount_torch(w)   # authored off
	w.rotation = Vector3(0.0, 1.0, 0.0)
	torch.global_rotation = Vector3.ZERO
	torch._process(FRAME)
	assert_almost_eq(torch.global_rotation.y, 1.0, 0.0005,
		"a dark torch must snap straight to the aim, so switching it on never swings the beam in from a stale angle")
	torch.set(&"_light_on", true)
	torch.global_rotation = Vector3.ZERO
	torch._process(FRAME)
	assert_lt(torch.global_rotation.y, 0.9, "control: the same turn with the torch LIT is eased, not snapped")


# --- the stealth trade ------------------------------------------------------------------------------------------

func test_stealth_opt_out_uses_the_existing_exempt_group() -> void:
	# reveals_you = false must reuse the group PlayerLightLevel ALREADY honours, not add a new branch there — so the
	# opted-out beam, lit at the player, must read as NOTHING to both the meter and the beacon. A default torch lit
	# in the same spot is the control that the sampler would otherwise charge for it.
	var w := _wielder_in_tree()
	var meter := _light_meter_on(w)
	var revealing := _mount_torch(w)
	var opted_out := _mount_torch(w, {"reveals_you": false})
	_switch_on(opted_out)
	revealing._process(FRAME)   # still off
	var at := w.global_position
	assert_true(opted_out.visible, "precondition: the opted-out beam is lit")
	assert_true(opted_out.is_in_group(Groups.STEALTH_LIGHT_EXEMPT),
		"opting out must join Groups.STEALTH_LIGHT_EXEMPT — the seam PlayerLightLevel already checks")
	assert_false(opted_out.is_in_group(Groups.CARRIED_LIGHT), "...and must NOT also join the beacon group")
	assert_almost_eq(meter._light_contribution_for(opted_out, at), 0.0, 0.0001,
		"a lit reveals_you=false torch must add nothing to the stealth light meter")
	assert_almost_eq(meter._sample_carried(), 0.0, 0.0001,
		"...and must not stamp the carried-light beacon either — the beam is free stealth-wise")

	_switch_on(revealing)
	assert_gt(meter._light_contribution_for(revealing, at), 0.0,
		"control: the default (reveals_you) torch lit at the same spot DOES feed the meter")
	assert_gt(meter._sample_carried(), 0.0, "control: ...and does stamp the beacon")
	assert_true(_is_inspector_export(opted_out, &"reveals_you"),
		"reveals_you must be an Inspector switch (stored in the scene) — the stealth trade is a designer knob, " +
		"not a code edit")


func test_the_lit_torch_actually_costs_you_stealth() -> void:
	# ⭐The cost has to be a GROUP membership, because the light meter alone cannot charge for a torch: exposure
	# saturates at 1.0 (the same as standing under a streetlamp), so being lit can only ever cancel the darkness
	# discount. The chain driven here end to end: press the Light key -> the real torch lights -> PlayerLightLevel's
	# tick stamps host.carried_light -> an enemy Perception looking at that host sees further. Then switch it off.
	GameSettings.light_stealth.carried_light_sight_mult = 2.0
	var w := _wielder_in_tree()
	var meter := _light_meter_on(w)
	var torch := _mount_torch(w)
	var eyes := Perception.new()
	eyes.sight_range = 25.0
	eyes.target = w

	meter._physics_process(1.0)
	var dark_range := eyes._effective_sight_range()
	assert_almost_eq(w.carried_light, 0.0, 0.0001, "torch off: the sampler stamps no carried light")

	_press(torch, KEY_L)
	torch._process(FRAME)
	meter._physics_process(1.0)
	var lit_beacon := w.carried_light
	var lit_range := eyes._effective_sight_range()

	_press(torch, KEY_L)
	torch._process(FRAME)
	meter._physics_process(1.0)
	var refunded := w.carried_light
	eyes.free()

	assert_gt(lit_beacon, 0.0, "a lit torch must stamp carried_light on the player, or it is free stealth-wise")
	assert_gt(lit_range, dark_range, "...which an enemy must see as a LONGER sight range to you")
	assert_almost_eq(refunded, 0.0, 0.0001, "switching the torch off must refund the whole beacon penalty")

	# The stamp is a duck-typed host.set(): on a Player without the field it would silently land nowhere.
	var p = load("res://scripts/player/player.gd").new()
	assert_true(&"carried_light" in p,
		"player.gd must declare carried_light — PlayerLightLevel writes it and Perception reads it off the target")
	p.free()


# --- the laser sight: its own node, no key, no stealth cost -----------------------------------------------------

func test_the_laser_sight_is_back_and_is_its_own_node() -> void:
	# ⭐The laser sight was RETIRED when the flashlight took this key, and is now RESTORED as a separate node —
	# these asserts used to pin the opposite (that every laser file was gone). The registry is scanned from disk,
	# so the four files below are exactly what makes `laser_sight` a real, buildable, purchasable mechanic again;
	# losing any one of them re-creates a different silent failure (an unbuildable id in the UpgradePickup
	# dropdown, a chip that installs nothing, a dot with no beam).
	assert_true(FileAccess.file_exists("res://scripts/components/abilities/laser_sight.gd"),
		"the LaserSight ability script must exist — a runtime grant builds from it")
	assert_true(FileAccess.file_exists("res://scenes/components/abilities/LaserSight.tscn"),
		"the LaserSight ability scene must exist (the registry scans this folder for ids)")
	assert_true(FileAccess.file_exists("res://resources/items/chip_laser_sight.tres"),
		"the laser-sight chip must exist — it is what puts the row in the New Game implant roster")
	assert_true(FileAccess.file_exists("res://scenes/player/laser_mesh.gd"),
		"the player's laser beam mesh script must exist")
	assert_true(AbilityRegistry.ids().has("laser_sight"),
		"the ability registry must offer laser_sight again")
	assert_true(AbilityRegistry.can_build(&"laser_sight"),
		"laser_sight must be runtime-buildable — a chip install and a save load both go through _build")


func test_the_torch_and_the_laser_are_separate_nodes() -> void:
	# ⭐THE WHOLE REASON THE LASER DIED THE FIRST TIME: it lived ON the flashlight and shared its key. They are now
	# two nodes on the rig with two different jobs, and this pins that they cannot silently re-merge — a wide white
	# lamp with a stealth cost, and a 0.5-degree energy-1000 pinprick with none.
	var scene := load(RIG) as PackedScene
	assert_not_null(scene, "camera_rig.tscn must load")
	var inst := scene.instantiate()
	var torch := inst.find_child("FlashLight", true, false) as SpotLight3D
	var laser := inst.find_child("LaserSight", true, false) as SpotLight3D
	assert_not_null(torch, "the rig must carry the FlashLight node")
	assert_not_null(laser, "the rig must carry the LaserSight node")
	if torch != null and laser != null:
		assert_ne(torch, laser, "the torch and the laser must be DIFFERENT nodes — merging them is what retired the sight")
		assert_lt(laser.spot_angle, 1.0, "the laser is a pinprick (0.5 degrees), not a cone")
		assert_gt(laser.light_energy, 100.0, "the laser dot needs its energy-1000 punch to read on a lit wall")
		assert_false(laser.visible, "the laser starts dark — it lights up only once the chip is installed")
	inst.free()


func test_the_laser_never_feeds_the_stealth_light_meter() -> void:
	# ⭐PlayerLightLevel weighs EVERY visible Light3D by energy alone — it never reads light_negative. An energy-1000
	# dot sitting at the player, plus the NEGATIVE sub-light that carves its core, would together saturate the meter
	# the moment the chip was fitted: buying a laser sight would silently mean "enemies always see you". So the
	# exemption must cover the whole subtree, and the laser must not take the torch's beacon penalty either. An
	# ungrouped lamp of the same punch at the same spot is the control that the sampler would otherwise count it.
	var w := _wielder_in_tree()
	var meter := _light_meter_on(w)
	var laser := _mount_laser(w, true)
	laser.visible = true   # lit, as with the chip fitted and a sighted gun drawn
	var carve := laser.get_node(^"Carve") as SpotLight3D
	var shaper := laser.get_node(^"Carve/Shaper") as OmniLight3D
	var bare := SpotLight3D.new()
	bare.light_energy = 1000.0
	bare.spot_range = 20.0
	w.add_child(bare)
	var at := w.global_position
	assert_gt(meter._light_contribution_for(bare, at), 0.0,
		"control: an ungrouped lamp of the laser's punch at the player floods the light meter")
	assert_almost_eq(meter._light_contribution_for(laser, at), 0.0, 0.0001,
		"the lit laser dot itself must add nothing to the stealth light meter")
	assert_almost_eq(meter._light_contribution_for(carve, at), 0.0, 0.0001,
		"the NEGATIVE carving sub-light must add nothing either — the sampler sums it as energy, not subtraction")
	assert_almost_eq(meter._light_contribution_for(shaper, at), 0.0, 0.0001,
		"a lamp nested deeper under the laser must be exempt too — the exemption walks the whole subtree")
	assert_almost_eq(meter._sample_carried(), 0.0, 0.0001,
		"the laser must NOT take the torch's beacon penalty — it lights a wall, not you")
	bare.add_to_group(Groups.CARRIED_LIGHT)
	assert_gt(meter._sample_carried(), 0.0, "control: a lamp that DID join the beacon group here would be charged")


func test_the_laser_has_no_keybind_of_its_own() -> void:
	# ⭐The design decision: own the chip and the sight is on. No toggle, no action poll, no input callback — the
	# Implants tab's per-implant switch (Ability.enabled, which has_mechanic reads) is the only switch. So press the
	# Light action every way a script could hear it (the Input singleton for a poll from EITHER per-frame callback,
	# every input callback the node implements for an event handler, the press AND its release) and the sight must
	# not move; then flip the mechanic and it must.
	var w := _wielder_in_tree()
	w.mechanics = [&"laser_sight"] as Array[StringName]
	_arm(w, _GunStub.new(), false)
	var laser := _mount_laser(w, false)
	_step_frame(laser)
	assert_true(laser.visible, "control: chip owned + a sighted gun drawn = the sight is on, with no key ever pressed")

	# (1) A POLL. Hold the Light action on the Input singleton and step one frame — _physics_process AND _process, so
	# a key polled from either callback is run — then let go and step another. The _PollEar gets the same two frames:
	# it is the control that this stepping really reaches a physics-callback poll, and that such a poll hears the
	# hold and then the release. Without it, "the laser never moved" could just mean the callback never ran.
	var poll_ear: _PollEar = autofree(_PollEar.new())
	Input.action_press(InputManager.action_light)
	var poll_sees_press: bool = Input.is_action_just_pressed(InputManager.action_light)
	_step_frame(poll_ear)
	_step_frame(laser)
	var on_after_poll := laser.visible
	Input.action_release(InputManager.action_light)
	_step_frame(poll_ear)
	_step_frame(laser)
	var on_after_release := laser.visible
	assert_true(poll_sees_press, "precondition: the Light press is visible to a same-frame action poll")
	assert_eq(poll_ear.held, [true, false],
		"control: a stepped _physics_process poll hears Light held on the pressed frame, and let go after the release")
	assert_true(on_after_poll,
		"holding the Light action must not move the laser from a per-frame poll (_process OR _physics_process) — no key")
	assert_true(on_after_release, "...nor may letting go of it")

	# (2) AN EVENT. Hand F, then L (both bound to Light), each as a PRESS and then its RELEASE, ONE EVENT AT A TIME to
	# every input callback the node implements, and read the sight after EACH delivery. Reading once at the end would
	# let a real toggle cancel itself out (put out on F, relit on L, "still on" at the end), and pressed-only events
	# would never reach a toggle keyed on the release. The shipped laser implements none of these callbacks, so its
	# pass is expected to deliver nothing (hooks_seen 0) — it exists to catch one being added. The _KeyEar goes through
	# the very same delivery first: the control that these hand-built events really read as Light presses AND releases.
	var key_ear: _KeyEar = autofree(_KeyEar.new())
	var ear_pass := _light_keystrokes_through(key_ear, func() -> bool: return true)
	assert_eq(key_ear.heard, ["press", "release", "press", "release"],
		"control: the F and L keystrokes reach an input callback as a Light press then its release, twice (%d deliveries)"
		% [ear_pass["deliveries"]])
	var laser_pass := _light_keystrokes_through(laser, func() -> bool: return laser.visible)
	var went_dark_on: String = laser_pass["first_break"]
	var hooks_seen: int = laser_pass["deliveries"]
	assert_true(went_dark_on == "",
		("no single Light key event, pressed or released, may put the laser out — it has no key "
		+ "(went dark on %s; %d callback deliveries)") % [went_dark_on, hooks_seen])

	w.mechanics = [] as Array[StringName]
	_step_frame(laser)
	assert_false(laser.visible, "switching the implant off (has_mechanic false) must put the sight out — the ONE switch")
	w.mechanics = [&"laser_sight"] as Array[StringName]
	_step_frame(laser)
	assert_true(laser.visible, "...and switching it back on relights it with no key involved")


func test_a_save_that_lists_a_retired_ability_id_degrades_quietly() -> void:
	# Old profiles can carry an id no longer on disk. The rebuild must grant nothing rather than crash — the
	# documented @risk on the Ability base, and the reason retiring an ability is safe at all. (This used to use
	# `laser_sight` as its dead id; that one is a live mechanic again, so it needs an id that never shipped.)
	var p = load("res://scripts/player/player.gd").new()
	p.set_unlocks([&"x_ray_vision", &"wall_climb"])
	assert_false(p.has_mechanic(&"x_ray_vision"),
		"an unknown id in an old save grants nothing (AbilityManager._build returns null for an unbuildable id)")
	assert_true(p.has_mechanic(&"wall_climb"),
		"...and the rest of that save's unlocks still load — one dead id must not poison the set")
	p.free()


# --- the SHARED F key: the torch is Interact's contextual fallback, with L as the unconditional escape --------

func test_light_binds_both_the_shared_key_and_an_unconditional_one() -> void:
	# ⭐The whole arrangement expressed as data. F is Interact's key too, so the torch DEFERS on it; L is the
	# torch's alone so it can never be locked out. Drop the L binding and the beam becomes unreachable for as
	# long as interact_available() is true — which is the ENTIRE time you are carrying a prop.
	var codes := _keycodes_for(InputManager.action_light)
	assert_true(codes.has(KEY_F),
		"Flashlight must bind F — the contextual key it shares with Interact")
	assert_true(codes.has(KEY_L),
		"Flashlight must ALSO bind L, which never defers — carrying a prop makes Interact permanently " +
		"available, so without a second key F could never reach the torch")

func test_the_torch_shares_f_with_interact_and_nothing_else() -> void:
	assert_true(InputManager.actions_share_binding(InputManager.action_light, InputManager.action_pickup),
		"Flashlight must share a binding with Interact — that sharing IS the contextual rule; without it the " +
		"torch would toggle UNDER every interact instead of standing down for it")
	# It must not quietly collide with the OTHER contextual keys, or three verbs would arbitrate over one press.
	assert_false(InputManager.actions_share_binding(InputManager.action_light, InputManager.action_takedown),
		"Flashlight must not share with Takedown (Q) — Q already arbitrates takedown/pet against the lean")
	assert_false(InputManager.actions_share_binding(InputManager.action_light, InputManager.action_lean_left),
		"Flashlight must not share with Lean Left (Q)")
	assert_false(InputManager.actions_share_binding(InputManager.action_light, InputManager.action_lean_right),
		"Flashlight must not share with Lean Right (E)")

func test_the_contextual_test_is_event_level_not_action_level() -> void:
	# ⭐THE PAD BUG THIS SHAPE EXISTS TO AVOID. actions_share_binding() compares ACTIONS: Light also carries the pad's
	# left-stick click and PickUp carries Y — controls that share nothing — so an action-level test would refuse the
	# CONTROLLER toggle whenever an interactable was in the crosshair. Pressed for real: the pad button bound to
	# Light in the live InputMap, with an interact pending, against F in the same state as the control.
	var pad := _pad_press_for(InputManager.action_light)
	assert_true(pad != null, "precondition: Light must carry a pad button (InputManager adds it at boot)")
	if pad == null:
		return
	assert_false(pad.is_action_pressed(InputManager.action_pickup),
		"precondition: the pad's Light button is not also Interact's")
	assert_true(InputManager.actions_share_binding(InputManager.action_light, InputManager.action_pickup),
		"precondition: the two ACTIONS do share a key (F) — which is exactly what an action-level test would trip on")
	var w := _wielder_in_tree()
	w.pending = [InputManager.action_pickup] as Array[StringName]
	var torch := _mount_torch(w)
	_press(torch, KEY_F)
	assert_false(_lit(torch), "control: with an interact pending, the SHARED keyboard key stands down")
	torch._unhandled_input(pad)
	assert_true(_lit(torch),
		"the pad toggle shares no button with Interact, so it must never defer — the torch asks the EVENT, not the action")

func test_the_torch_stands_down_for_a_pending_interact() -> void:
	# The deferral reads the wielder's verb scan (Player.pending_verb_actions) on EVERY press, so the torch and the
	# interact can never disagree about what one press meant — and it blocks F in both directions, not just "on".
	var w := _wielder_in_tree()
	var torch := _mount_torch(w)
	w.pending = [InputManager.action_pickup] as Array[StringName]
	_press(torch, KEY_F)
	assert_false(_lit(torch), "aimed at an interactable, F belongs to Interact — the torch must not switch on under it")
	w.pending = [] as Array[StringName]
	_press(torch, KEY_F)
	assert_true(_lit(torch), "the moment the verb scan empties, F must reach the torch — re-read per press, never latched")
	w.pending = [InputManager.action_pickup] as Array[StringName]
	_press(torch, KEY_F)
	assert_true(_lit(torch), "...and a newly pending interact must stop F putting the torch OUT, too")

## ⭐THE MENU / DIALOGUE GATE. This was MISSING and was a live defect even on the old dedicated key: the player menus
## deliberately do not pause the tree, and this node sits LATER in the rig than both PickupRay and every modal
## screen — and _unhandled_input runs in REVERSE tree order — so the torch sees the press FIRST and cannot wait to
## learn whether a screen consumed it. Each of the three tests below stages exactly ONE suppressor (asserting the
## other half of the gate is quiet), presses L (which never defers to Interact, so the gate is the only thing that
## can refuse it), then clears the suppressor and presses again as the control.

func test_the_toggle_stands_down_while_a_conversation_is_up() -> void:
	var w := _wielder_in_tree()
	var torch := _mount_torch(w)
	DialogueManager._active = DialogueResource.new()
	DialogueManager._suspended = false
	var talking: bool = DialogueManager.is_active()
	var suppressed: bool = InputManager.gameplay_suppressed()
	_press(torch, KEY_L)
	var lit_mid_conversation := _lit(torch)
	DialogueManager._active = _saved_dialogue   # restore BEFORE asserting (after_each is the second net)
	DialogueManager._suspended = _saved_suspended
	_press(torch, KEY_L)
	assert_true(talking, "precondition: a conversation is up")
	assert_false(suppressed, "precondition: nothing else suppresses gameplay — the dialogue half is what is under test")
	assert_false(lit_mid_conversation,
		"the torch key must do nothing while a conversation is up — F/L would flick the beam on every dialogue advance")
	assert_true(_lit(torch), "control: once the conversation ends, the same press toggles the torch")

func test_the_toggle_stands_down_over_a_modal_screen() -> void:
	var w := _wielder_in_tree()
	var torch := _mount_torch(w)
	WaitScreen._is_open = true
	var suppressed: bool = InputManager.gameplay_suppressed()
	var talking: bool = DialogueManager.is_active()
	_press(torch, KEY_L)
	var lit_over_menu := _lit(torch)
	WaitScreen._is_open = _saved_wait_open
	_press(torch, KEY_L)
	assert_true(suppressed, "precondition: an open registry screen suppresses gameplay")
	assert_false(talking, "precondition: no conversation — the modal half of the gate is what is under test")
	assert_false(lit_over_menu,
		"the torch key must do nothing over an open menu — the menus do not pause the tree, so nothing else stops it")
	assert_true(_lit(torch), "control: with the menu closed, the same press toggles the torch")

func test_the_toggle_stands_down_during_a_cutscene() -> void:
	var w := _wielder_in_tree()
	var torch := _mount_torch(w)
	load(CUTSCENE_PLAYER_PATH).set("_active", true)
	var suppressed: bool = InputManager.gameplay_suppressed()
	var talking: bool = DialogueManager.is_active()
	_press(torch, KEY_L)
	var lit_in_cutscene := _lit(torch)
	load(CUTSCENE_PLAYER_PATH).set("_active", _saved_cutscene)
	_press(torch, KEY_L)
	assert_true(suppressed, "precondition: a playing cutscene suppresses gameplay")
	assert_false(talking, "precondition: no conversation — the control-lock half of the gate is what is under test")
	assert_false(lit_in_cutscene, "the torch key must do nothing while a cutscene holds the player's controls")
	assert_true(_lit(torch), "control: once the cutscene ends, the same press toggles the torch")

## The physical keycodes bound to `action` right now (the LIVE InputMap, so a default change shows up here).
func _keycodes_for(action: StringName) -> Array:
	var codes := []
	for event in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key != null:
			codes.append(key.physical_keycode)
	return codes
