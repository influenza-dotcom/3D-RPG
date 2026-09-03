extends GutTest

## Contract test for the FPS view-model render pass (res://scripts/camera/view_model_camera.gd).
##
## SCOPE — only the side-effect-free pure static ViewModelCamera.build_default_environment. The live pass
## (SubViewport + gun camera + composite container) reads get_world_3d() / get_viewport() and mutates the main
## camera's cull_mask, so it's built in-tree and verified by playtest, NOT here (per the project's test policy).
##
## WHY this exists: the levels run with near-zero ambient light (volumetric FOG is the scene fill) and the gun pass
## deliberately excludes that fog — so WITHOUT its own environment the view model renders pitch black. This guards
## the fill that fixes it: a flat COLOUR ambient at the requested energy, with fog OFF (no fogging a gun at arm's
## length) and a CLEAR background (the pass is transparent + composited — it must never paint a sky).

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
## by scripts/tools/__respawn_viewmodel_probe.gd, which counts the disagreement per frame — a shader-free,
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
	var item := Control.new()
	assert_false(item.has_meta(UI.DEATH_HIDE_EXEMPT_META), "a plain HUD child is swept by default — nothing has to opt IN")
	UI.set_death_hide_exempt(item, true)
	assert_true(item.has_meta(UI.DEATH_HIDE_EXEMPT_META), "flagging sets the meta hide_hud_for_death reads")
	UI.set_death_hide_exempt(item, false)
	assert_false(item.has_meta(UI.DEATH_HIDE_EXEMPT_META), "…and un-flagging removes it, rather than leaving a false")
	UI.set_death_hide_exempt(null, true)  # null-safe: a caller may flag an optional overlay unguarded
	item.free()

func test_the_pass_flags_its_own_composite() -> void:
	# The CALL, not the bare name: _attach_container is the only place that can flag the container, and the
	# flag is invisible in every headless test that does not build the live pass (SubViewport + gun camera +
	# a real viewport), so nothing else would catch its removal.
	var src := FileAccess.get_file_as_string("res://scripts/camera/view_model_camera.gd")
	assert_true(src.contains("UI_SCRIPT.set_death_hide_exempt(_container, true)"),
		"_attach_container must exempt the composite from UI.hide_hud_for_death(), or dying leaves the view model's outline drawing around a weapon that is no longer composited")
	assert_true(src.contains("HUD_GHOST_SCRIPT.set_ghosted(_container, false)"),
		"…and keep the ghost opt-out beside it — same node, same reason (it is not a HUD readout), and the two are meant to be read together")
