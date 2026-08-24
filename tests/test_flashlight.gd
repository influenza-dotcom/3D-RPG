extends GutTest

## The player FLASHLIGHT (scenes/player/flash_light.gd on the camera rig's FlashLight node).
##
## The script itself is NOT instantiated in-tree here: its _process drives global_rotation off a parent
## transform and _ready walks ancestors, which a bare node has none of (the same reason test_camera_input_ui
## deliberately skips flash_light.gd). What IS pinned is the AUTHORING contract — the rig's node exists, is a
## real light rather than the retired laser, starts off, and reaches the view-model layer — plus the file-level
## invariants that a future edit could silently break, and the fact that the retired laser sight is really gone.

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


func test_retired_laser_sight_is_gone_everywhere_it_would_break() -> void:
	# The ability, its scene, its chip and the beam mesh were removed when the flashlight took F. The registry is
	# scanned from disk, so a leftover would silently re-offer an unbuildable id in the UpgradePickup dropdown.
	assert_false(FileAccess.file_exists("res://scripts/components/abilities/laser_sight.gd"),
		"the LaserSight ability script must be gone")
	assert_false(FileAccess.file_exists("res://scenes/components/abilities/LaserSight.tscn"),
		"the LaserSight ability scene must be gone (the registry scans this folder)")
	assert_false(FileAccess.file_exists("res://resources/items/chip_laser_sight.tres"),
		"the laser-sight chip item must be gone — there is nothing left to install")
	assert_false(FileAccess.file_exists("res://scenes/player/laser_mesh.gd"),
		"the player's laser beam mesh script must be gone")
	assert_false(AbilityRegistry.ids().has("laser_sight"),
		"the ability registry must no longer offer laser_sight (it could not be built if picked)")


func test_a_save_that_still_lists_laser_sight_degrades_quietly() -> void:
	# Old profiles carry the id. The rebuild must grant nothing rather than crash — the documented @risk on the
	# Ability base, and the reason removing an ability is safe at all.
	var p = load("res://scripts/player/player.gd").new()
	p.set_unlocks([&"laser_sight", &"wall_climb"])
	assert_false(p.has_mechanic(&"laser_sight"),
		"a retired id in an old save grants nothing (AbilityManager._build returns null for an unknown id)")
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
