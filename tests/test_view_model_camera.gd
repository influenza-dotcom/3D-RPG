extends GutTest

## Contract test for the FPS view-model render pass (res://scripts/camera/view_model_camera.gd).
##
## SCOPE — the side-effect-free pure static ViewModelCamera.build_default_environment, the light_reach layer
## stamping, and the composite container's attach to the UI (_attach_container, driven on an off-tree UI: its
## draw order, HUD-ghost exemption and death-hide exemption). The rest of the live pass (SubViewport + gun
## camera) reads get_world_3d() / get_viewport() and mutates the main camera's cull_mask, so it's built in-tree
## and verified by playtest, NOT here (per the project's test policy).
##
## WHY this exists: the gun pass deliberately excludes the world's fog and its environment — so it carries its own
## small ambient FLOOR: a flat COLOUR ambient at the requested energy, with fog OFF (no fogging a gun at arm's
## length) and a CLEAR background (the pass is transparent + composited — it must never paint a sky). The floor is
## NOT the gun's lighting: that is the world's lights, which only reach the pass because ViewModelCamera.light_reach
## stamps VIEW_MODEL_LAYER onto them (tests below) — Godot culls lights per camera by the light's own `layers`.

## The HUD-ghost drop-in, preloaded BY PATH (the class-cache cascade guard view_model_camera.gd uses for it too).
const HudGhostScript := preload("res://scripts/ui/hud_ghost.gd")

func test_build_default_environment_gives_a_flat_ambient_fill() -> void:
	var env: Environment = ViewModelCamera.build_default_environment(null, Color(0.9, 0.91, 0.95), 0.75)
	assert_not_null(env, "a default view-model environment must always be built (it's the pitch-black fix)")
	assert_eq(env.ambient_light_source, Environment.AMBIENT_SOURCE_COLOR,
		"the fill must be a flat COLOUR ambient, independent of the world's ~zero ambient")
	assert_eq(env.ambient_light_color, Color(0.9, 0.91, 0.95), "the fill colour must be the requested one")
	assert_almost_eq(env.ambient_light_energy, 0.75, 0.0001, "the fill energy must be the requested one")
	assert_eq(env.ambient_light_sky_contribution, 0.0,
		"the fill must NOT pull sky ambient (the levels set sky contribution to 0)")
	env = null

func test_build_default_environment_disables_fog_and_sky_background() -> void:
	var env: Environment = ViewModelCamera.build_default_environment(null, Color.WHITE, 1.0)
	assert_false(env.fog_enabled, "no distance fog on a gun 30 cm from the lens")
	assert_false(env.volumetric_fog_enabled, "no volumetric fog in the view-model pass (it's the WORLD's scene fill)")
	assert_eq(env.background_mode, Environment.BG_CLEAR_COLOR,
		"a CLEAR background — the SubViewport is transparent and composites over the world, so it must never draw a sky")
	env = null

func test_build_default_environment_copies_world_tonemap_when_given() -> void:
	# The gun must grade like the world (the levels use AgX, tonemap_mode 4): copy the world env's tonemap so it
	# doesn't read brighter / more saturated than the tonemapped world beside it. A null world env just skips the copy.
	var world := Environment.new()
	world.tonemap_mode = Environment.TONE_MAPPER_AGX  # the shipped levels' tonemap (SliceTestLevel env: tonemap_mode = 4)
	world.tonemap_exposure = 1.3
	world.tonemap_white = 2.0
	var env: Environment = ViewModelCamera.build_default_environment(world, Color.WHITE, 0.5)
	assert_eq(env.tonemap_mode, Environment.TONE_MAPPER_AGX, "the view model must inherit the world's tonemap mode (AgX)")
	assert_almost_eq(env.tonemap_exposure, 1.3, 0.0001, "…and its tonemap exposure")
	assert_almost_eq(env.tonemap_white, 2.0, 0.0001, "…and its tonemap white")
	world = null
	env = null


## ⭐⭐ WORLD LIGHTS ONLY REACH THE GUN PASS BECAUSE THE PASS STAMPS ITS LAYER ONTO THEM.
##
## Godot culls LIGHTS per camera by the light's own VisualInstance3D `layers`, not by light_cull_mask. The gun camera
## culls only VIEW_MODEL_LAYER and every level light is authored on layer 1, so without this stamp the pass has no
## sun, no lamps, no muzzle flash — measured 2026-09-14 (scripts/tools/probes/__view_model_world_light_probe.gd):
## gun-pass mean luminance 0.023 with the fill off, 0.363 once the lights carried the layer. The old 0.75 fill hid it.
## The pixels need a window; these pin the pure stamp + the opt-out + the default that keeps it on.
func test_reach_light_stamps_the_view_model_layer_onto_a_world_light() -> void:
	var l := OmniLight3D.new()
	assert_eq(l.layers & ViewModelCamera.VIEW_MODEL_LAYER, 0, "a fresh light ships on layer 1 only — the bug's precondition")
	assert_true(ViewModelCamera.reach_light(l), "stamping a layer-1 light must report a change")
	assert_ne(l.layers & ViewModelCamera.VIEW_MODEL_LAYER, 0, "…and the light now carries VIEW_MODEL_LAYER, so the gun camera's pass can see it")
	assert_ne(l.layers & 1, 0, "…without losing layer 1 — the stamp ORs, it never assigns (the world must still be lit)")
	assert_false(ViewModelCamera.reach_light(l), "a light that already carries the bit is left alone (the FlashLight's hand-authored layers = 5)")
	l.free()

func test_reach_light_skips_an_exempt_light() -> void:
	var l := OmniLight3D.new()
	l.add_to_group(Groups.VIEW_MODEL_LIGHT_EXEMPT)
	assert_false(ViewModelCamera.reach_light(l), "a light in view_model_light_exempt is the designer's opt-out and must not be stamped")
	assert_eq(l.layers & ViewModelCamera.VIEW_MODEL_LAYER, 0, "…so it never lights the hands")
	assert_false(ViewModelCamera.reach_light(null), "null-safe: node_added hands over whatever entered the tree")
	l.free()

func test_reach_lights_under_walks_a_subtree_and_counts_only_changes() -> void:
	var root := Node3D.new()
	var lamp := OmniLight3D.new()
	var sun := DirectionalLight3D.new()
	var torch := SpotLight3D.new()
	torch.layers = 1 | ViewModelCamera.VIEW_MODEL_LAYER  # already reaches, like the rig's FlashLight
	var deep := Node3D.new()
	root.add_child(lamp)
	root.add_child(deep)
	deep.add_child(sun)
	deep.add_child(torch)
	assert_eq(ViewModelCamera.reach_lights_under(root), 2, "the lamp and the (nested) sun are stamped; the torch already had the bit")
	assert_ne(sun.layers & ViewModelCamera.VIEW_MODEL_LAYER, 0, "a nested DirectionalLight3D — the level's sun — is reached")
	assert_eq(ViewModelCamera.reach_lights_under(root), 0, "a second sweep changes nothing (idempotent)")
	root.free()

func test_light_reach_ships_on() -> void:
	# head.gd builds this node in CODE with no .tscn override, so the export's default IS the shipped value: off, the
	# gun renders in a pass with no world light in it and only the fill keeps it visible (the 2026-09-14 report).
	var vm := ViewModelCamera.new()
	assert_true(vm.light_reach, "light_reach must default ON — without it no world light exists in the gun pass")
	assert_lt(vm.view_model_ambient_energy, 0.5,
		"the fill is a FLOOR under world light, not the light: 0.75 flattened the gun to one brightness (the reported symptom)")
	vm.free()


## ⭐⭐ THE COMPOSITE IS NOT A HUD READOUT, AND THE DEATH CINEMATIC MUST NOT SWEEP IT AWAY.
##
## The whole first-person view model — gun, arms, legs — reaches the screen through ONE full-rect
## SubViewportContainer that this pass parents on the HUD CanvasLayer, and the pass strips VIEW_MODEL_LAYER
## from the main camera, so hiding that Control deletes the weapon from the frame outright. Its OUTLINE does
## not go with it: an InkOutline tint duplicate lives in the 3D world on ACTOR_TINT_LAYER and is drawn by the
## ink pass on the main camera, which no HUD write can reach. So the two are on different render paths and
## only an explicit exemption keeps them agreeing.
##
## Reported 2026-09-02: "when you die and respawn, sometimes the outline for your view model is visible when
## the view model itself is not." UI.hide_hud_for_death() hid the composite; the ring kept drawing around
## nothing, for the 0.24 s keel-over and again for the revive's 1.0 s respawn_hud_delay quiet window (measured
## by scripts/tools/probes/__respawn_viewmodel_probe.gd, which counts the disagreement per frame — a shader-free,
## headless-safe node-state check, since the pixels themselves need a real window).
func test_the_death_hide_spares_a_flagged_child() -> void:
	var ui := UI.new()
	var readout := Control.new()      # an ordinary HUD element: hidden for the cinematic, restored on the revive
	var composite := Control.new()    # stands in for ViewModelComposite: a compositing detail, never hidden
	ui.add_child(readout)
	ui.add_child(composite)
	UI.set_death_hide_exempt(composite, true)

	ui.hide_hud_for_death()
	assert_false(readout.visible, "an ordinary HUD readout is still hidden for the death cinematic")
	assert_true(composite.visible,
		"a flagged child must SURVIVE the death hide — this one composites the view model, and its outline is drawn by a pass the HUD cannot reach")
	assert_true(ui._death_hidden_hud.has(readout), "the readout is remembered so the revive can show it back")
	assert_false(ui._death_hidden_hud.has(composite),
		"…and the exempt child is never recorded, so it cannot be 'restored' out of a state it never entered")
	ui.free()

func test_the_exempt_flag_round_trips() -> void:
	# Judged by the sweep that reads the flag, not by how the flag is stored: un-flagging must hand the child back
	# to the death hide. The sweep tests for the flag's PRESENCE, so an un-flag that left a `false` behind would
	# keep the child exempt for good.
	var ui := UI.new()
	var item := Control.new()
	ui.add_child(item)
	UI.set_death_hide_exempt(item, true)
	UI.set_death_hide_exempt(item, false)
	UI.set_death_hide_exempt(null, true)  # null-safe: a caller may flag an optional overlay unguarded (an engine error fails this test)
	ui.hide_hud_for_death()
	assert_false(item.visible, "a child flagged and then un-flagged is swept by the death hide like any other readout")
	assert_true(ui._death_hidden_hud.has(item), "…and remembered, so the revive shows it back")
	# Control: the same child, flagged again, survives the same sweep, so the hide above is the un-flag's doing.
	item.visible = true
	UI.set_death_hide_exempt(item, true)
	ui.hide_hud_for_death()
	assert_true(item.visible, "control: the same child with the flag set is spared by the death hide")
	ui.free()

func test_the_pass_composite_survives_the_death_hide_and_skips_the_ghost() -> void:
	# _attach_container is the one step of the live pass that needs no viewport or world: it only parents a
	# SubViewportContainer on the HUD layer. Drive it against a real (off-tree) UI and play the death hide over it,
	# so the flags are proven by what the sweep actually does, not by the call being spelled somewhere.
	var ui := UI.new()
	var post := ColorRect.new()
	post.name = "ColorRect"  # the post-process rect hide_hud_for_death keeps (ui.tscn's child 0 before the pass)
	ui.add_child(post)
	var readout := Control.new()  # an ordinary HUD readout: the control case for both sweeps
	ui.add_child(readout)
	var vm := ViewModelCamera.new()
	vm._sub_viewport = SubViewport.new()  # _build_pass creates this before attaching; nothing here renders it
	vm._attach_container(ui)
	var composite := ui.get_node_or_null(^"ViewModelComposite") as Control
	assert_true(composite != null, "attaching the pass must parent the view-model composite on the HUD layer")
	assert_eq(composite.get_index(), 0, "the composite sits UNDER the post-process rect, so the gun dithers with the world")
	assert_ne(readout.visibility_layer & HudGhostScript.CAPTURED_LAYER, 0, "control: an ordinary HUD readout feeds the ghost capture")
	assert_eq(composite.visibility_layer & HudGhostScript.CAPTURED_LAYER, 0,
		"the composite must stay OUT of the ghost capture, or the whole weapon smears behind itself on every turn")
	ui.hide_hud_for_death()
	assert_false(readout.visible, "control: the death hide still sweeps an ordinary readout")
	assert_true(composite.visible,
		"the composite must SURVIVE the death hide, or dying leaves the view model's outline drawing around a weapon that is no longer composited")
	ui.free()
	vm.free()
