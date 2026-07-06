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
