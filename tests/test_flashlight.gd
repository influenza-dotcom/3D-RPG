extends GutTest

## The player FLASHLIGHT (scenes/player/flash_light.gd on the camera rig's FlashLight node).
##
## The script itself is NOT instantiated in-tree here: its _process drives global_rotation off a parent
## transform and _ready walks ancestors, which a bare node has none of (the same reason test_camera_input_ui
## deliberately skips flash_light.gd). What IS pinned is the AUTHORING contract — the rig's node exists, is a
## real light rather than the laser, starts off, and reaches the view-model layer — plus the file-level
## invariants that a future edit could silently break.
##
## It ALSO guards the boundary with the LASER SIGHT, which used to live on this very node and share its key. The
## laser is back as its own rig node (scenes/player/laser_sight_rig.gd) and the two must never re-merge, so the
## tests near the bottom pin them apart from both sides: the torch must not gate on the weapon's laser flag, and
## the laser must not grow a keybind or a stealth cost.

const RIG := "res://scenes/player/camera_rig.tscn"
const SCRIPT_PATH := "res://scenes/player/flash_light.gd"
## No class_name on the registry (deliberate — nothing for the global class cache to miss), so preload it.
const AbilityRegistry := preload("res://scripts/components/abilities/ability_registry.gd")

func _rig_torch() -> Dictionary:
	var scene := load(RIG) as PackedScene
	assert_not_null(scene, "camera_rig.tscn must load — it carries the flashlight")
	var inst := scene.instantiate()
	var torch := inst.find_child("FlashLight", true, false)
	return {"root": inst, "torch": torch}

func _source() -> String:
	var f := FileAccess.open(SCRIPT_PATH, FileAccess.READ)
	assert_not_null(f, "flash_light.gd must exist on disk")
	return f.get_as_text() if f != null else ""

## The source with whole-line comments stripped. REQUIRED for the "must not gate on X" pins below: this file's
## header explains at length what it deliberately does NOT gate on ("works holstered", "no has_mechanic gate"),
## so a naive substring search over the raw text matches the prose and fails on a correct implementation.
func _code() -> String:
	var out := ""
	for line in _source().split("\n"):
		if not line.strip_edges().begins_with("#"):
			out += line + "\n"
	return out


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


func test_beam_tracks_the_glow_live_rather_than_copying_a_literal() -> void:
	# The glow's colour is HP-driven (Player.health_light_color_for, off the `damaged` signal), so a hard-coded
	# hue would only ever be right at full health. Pin that the implementation READS the live node — and that
	# the match is a designer switch, not a hidden rule.
	var src := _code()
	assert_true("@export var match_player_light" in src,
		"matching the body glow must be a designer switch (off = keep the authored beam colour)")
	assert_true("PlayerEmittingLight" in src,
		"the beam must read the player's actual glow node, so any future retint is inherited for free")
	assert_true("light_color = _glow.light_color" in src,
		"the beam must COPY the live glow colour, never re-derive the HP blend (one blend, one home)")
	assert_false("health_light_color_for" in src,
		"the torch must never re-derive the HP blend itself — it reads the glow node the blend already wrote")


## ⭐THE WHITE CORE. A SpotLight3D has ONE light_color, so "white in the middle, HP colour at the rim" is not a
## property you can set — it is a light PROJECTOR (a radial GradientTexture2D the light multiplies itself by).
## These asserts are behavioural: they build the real ramp on a real node and read what came out.
##
## Built OFF-TREE deliberately. Adding this script to the tree runs _process, which reads
## `get_parent().global_rotation` — a GutTest is a plain Node, so that is an engine error, and GUT 9.6 fails the
## suite on those. _build_beam_gradient touches nothing outside the node, so calling it directly is honest.
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
## and NO projector. This is the escape hatch the class doc promises for the white volumetric shaft.
func test_the_gradient_can_be_switched_off_back_to_a_flat_tinted_beam() -> void:
	var src := _code()
	assert_true("@export var beam_gradient" in src, "the gradient must be a designer switch, not a hidden rule")
	assert_true("if beam_gradient:" in src and "_build_beam_gradient()" in src,
		"the projector must only be built when the switch is on — off = the light keeps its authored colour")
	var torch: SpotLight3D = load(SCRIPT_PATH).new()
	torch.beam_gradient = false
	assert_null(torch.light_projector,
		"with the gradient off nothing may author a projector — a stale one would silently keep the white core")
	torch.free()


func test_beam_colour_is_cosmetic_and_cannot_move_stealth() -> void:
	# PlayerLightLevel weighs lights by energy/range/distance and never reads colour, so recolouring the torch
	# must not have quietly become a gameplay change. Pin the sampler's blindness at its source.
	var f := FileAccess.open("res://scripts/player/player_light_level.gd", FileAccess.READ)
	assert_not_null(f, "player_light_level.gd must exist")
	var lit := f.get_as_text() if f != null else ""
	assert_false("light_color" in lit,
		"the stealth light meter must never read a light's COLOUR — recolouring the torch is a look change only")


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


func test_flashlight_is_not_gated_on_a_weapon_or_an_ability() -> void:
	# The whole point of the swap: the old laser only lit up with a laser-capable weapon DRAWN and the
	# `laser_sight` mechanic unlocked. A flashlight must answer to none of that — it works holstered, unarmed,
	# and for every player from the first frame ("you get the flashlight by default").
	var src := _code()
	assert_false("has_laser_sight" in src,
		"the flashlight must not gate on the weapon's laser flag (that flag is NPC-only now)")
	assert_false("holstered" in src,
		"the flashlight must not gate on the weapon being drawn — it is a torch, not a gun attachment")
	assert_false("has_mechanic" in src,
		"the flashlight must not gate on an unlockable mechanic — every player has it by default")


func test_flashlight_keeps_the_designer_seams_the_rig_relies_on() -> void:
	# These three were pinned when this node drove the laser and stay true for the torch: the origin marker is an
	# @export the SCENE wires (never a brittle relative path), and the follow is exp-based so the hand-held lag
	# feels identical at any frame rate.
	var src := _source()
	assert_false('"../LightPosition"' in src,
		"flash_light.gd must not hard-code the ../LightPosition NodePath — the scene wires the @export")
	assert_true("@export var light_position" in src,
		"flash_light.gd must expose light_position as an @export so the scene wires it")
	assert_true("@export var follow_rate" in src,
		"flash_light.gd must expose the follow rate as an @export (designer-tunable smoothing)")
	assert_true("exp(-follow_rate" in src,
		"flash_light.gd must use exp-based frame-rate-independent smoothing")


func test_stealth_opt_out_uses_the_existing_exempt_group() -> void:
	# reveals_you = false must reuse the group PlayerLightLevel ALREADY honours, not add a new branch there —
	# so "who feeds detection" keeps exactly one home.
	var src := _source()
	assert_true("@export var reveals_you" in src,
		"the stealth trade must be a designer knob, not a hard-coded rule")
	assert_true("STEALTH_LIGHT_EXEMPT" in src,
		"opting out must join Groups.STEALTH_LIGHT_EXEMPT — the seam PlayerLightLevel already checks")


func test_the_lit_torch_actually_costs_you_stealth() -> void:
	# ⭐The cost has to be a GROUP membership, because the light meter alone cannot charge for a torch: exposure
	# saturates at 1.0 (the same as standing under a streetlamp), so being lit can only ever cancel the darkness
	# discount. &"carried_light" is the seam PlayerLightLevel turns into player.carried_light, which Perception
	# reads as a wider sight range + a faster detection fill. Pin BOTH sides so neither can drift off alone.
	var src := _code()
	assert_true("add_to_group(Groups.CARRIED_LIGHT)" in src,
		"a revealing torch must join Groups.CARRIED_LIGHT or it is free stealth-wise")
	var f := FileAccess.open("res://scripts/player/player_light_level.gd", FileAccess.READ)
	assert_not_null(f, "player_light_level.gd must exist")
	var lit := f.get_as_text() if f != null else ""
	assert_true("Groups.CARRIED_LIGHT" in lit,
		"the sampler must read that same group — it is what stamps player.carried_light")
	assert_true("carried_light" in _player_source(),
		"player.gd must declare the carried_light field Perception reads off the target")


func _player_source() -> String:
	var f := FileAccess.open("res://scripts/player/player.gd", FileAccess.READ)
	return f.get_as_text() if f != null else ""


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
	# ⭐PlayerLightLevel auto-collects EVERY visible Light3D and weighs it by energy alone — it never reads
	# light_negative. An energy-1000 dot sitting at the player, plus the NEGATIVE sub-light that carves its core,
	# would together saturate the meter the moment the chip was fitted: buying a laser sight would silently mean
	# "enemies always see you". The exemption must cover the whole subtree, not just the scripted node.
	var f := FileAccess.open("res://scenes/player/laser_sight_rig.gd", FileAccess.READ)
	assert_not_null(f, "laser_sight_rig.gd must exist")
	var src := f.get_as_text() if f != null else ""
	assert_true("STEALTH_LIGHT_EXEMPT" in src,
		"the laser must join Groups.STEALTH_LIGHT_EXEMPT — the seam PlayerLightLevel already checks")
	assert_true("get_children()" in src,
		"the exemption must WALK the subtree: the negative sub-light is a child, and it is summed as energy too")
	# Pin the CALL, not the bare identifier: the header comment above names Groups.CARRIED_LIGHT to explain the
	# trade the laser deliberately does NOT make, and a substring test on the name alone reads that prose as the
	# very thing it is disclaiming. add_to_group(...) is the only line that would actually charge the penalty.
	assert_false("add_to_group(Groups.CARRIED_LIGHT)" in src,
		"the laser must NOT take the torch's beacon penalty — it lights a wall, not you")


func test_the_laser_has_no_keybind_of_its_own() -> void:
	# ⭐The design decision, pinned: own the chip and the sight is on. No toggle, no action lookup, no _input.
	# The Implants tab's per-implant on/off switch (Ability.enabled, which has_mechanic reads) is the only switch.
	var f := FileAccess.open("res://scenes/player/laser_sight_rig.gd", FileAccess.READ)
	var src := f.get_as_text() if f != null else ""
	assert_false("_unhandled_input" in src, "the laser must not listen for input — it has no key")
	assert_false("is_action_pressed" in src, "the laser must not poll an action — it has no key")
	assert_true("has_mechanic" in src, "the laser must gate on the mechanic the chip grants")


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


func test_the_beam_origin_is_held_off_the_eye_so_shadows_are_visible() -> void:
	# ⭐THE SHADOW PIN, and it is pure GEOMETRY rather than a render setting. A light sitting exactly on the
	# camera puts every shadow it casts perfectly BEHIND the thing casting it, so each caster hides its own
	# shadow and the beam reads as flat, shadowless fill — with shadow_enabled true the entire time. That is
	# what the rig shipped: LightPosition was authored at the Camera3D's local origin, and the FlashLight node's
	# own -0.187 X offset was DEAD (top_level + the per-frame global_position write overwrite it every frame),
	# so no one could see the authored intent was not reaching the screen.
	#
	# Verified by eye with scripts/tools/flashlight_qa_shots.gd (a real windowed GPU run — a box in front of a
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
	# ⭐THE PAD BUG THIS SHAPE EXISTS TO AVOID. actions_share_binding() compares ACTIONS: Light also carries the
	# pad's left-stick click and PickUp carries Y — controls that share nothing — so an action-level test would
	# refuse the CONTROLLER toggle whenever an interactable was in the crosshair. Asking the EVENT which actions
	# it fires keeps each device honest. Pinned as source text because no headless test can press a gamepad.
	var src := _code()
	assert_true("event.is_action_pressed(InputManager.action_pickup)" in src,
		"the torch must decide the share by asking the EVENT, so a pad press (never shared) never defers")
	assert_false("actions_share_binding" in src,
		"the torch must NOT use the action-level share helper — it would swallow the pad's left-stick toggle")

func test_the_torch_stands_down_for_a_pending_interact() -> void:
	# The deferral must read the SAME list the lean arbitrates against (Player.pending_verb_actions), so the
	# torch and the interact can never disagree about what one press meant.
	var src := _code()
	assert_true("pending_verb_actions" in src,
		"the torch must defer through Player.pending_verb_actions() — the one duck-typed verb scan — rather " +
		"than re-deriving 'is an interact available' and drifting out of lockstep with PickupRay")

func test_the_toggle_is_gated_on_menus_and_dialogue() -> void:
	# ⭐This was MISSING and was a live defect even on the old dedicated key: the player menus deliberately do
	# not pause the tree, and this node sits LATER in the rig than both PickupRay and every modal screen — and
	# _unhandled_input runs in REVERSE tree order — so the torch sees the press FIRST and cannot wait to learn
	# whether a screen consumed it. Without these two the key flicks the beam and plays the click on every
	# screen-close and every dialogue advance.
	var src := _code()
	assert_true("DialogueManager.is_active()" in src,
		"the toggle must stand down while a conversation is up — F advances the box (and the un-paused intro " +
		"beat still routes input here)")
	assert_true("InputManager.gameplay_suppressed()" in src,
		"the toggle must stand down over any modal / cutscene / name-entry prompt — those own the keyboard, " +
		"and the player menus do not pause the tree")

## The physical keycodes bound to `action` right now (the LIVE InputMap, so a default change shows up here).
func _keycodes_for(action: StringName) -> Array:
	var codes := []
	for event in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key != null:
			codes.append(key.physical_keycode)
	return codes
