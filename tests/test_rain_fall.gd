extends GutTest
## Contract tests for the RainFall drop-in (scripts/components/rain_fall.gd).
##
## What matters here is everything that is NOT the look: that a drop's lifetime actually matches the column it
## has to fall down (get that wrong and drops evaporate in mid-air or pile up below you), that the field RIDES
## the camera (the whole reason a few thousand particles can read as a downpour), and that it stops indoors —
## which is the one claim that involves the physics world and therefore the one most likely to rot silently.
##
## ⭐ Reached through `preload` + `.new()` and typed as `Node`, never by naming `RainFall`: a brand-new
## `class_name` is not in the global class cache until the editor rescans, and naming the type would drop this
## whole file from the suite until then.

const RAIN: GDScript = preload("res://scripts/components/rain_fall.gd")

func _rain(parent: Node) -> Node:
	var r: Node = RAIN.new()
	parent.add_child(r)
	return r

func _host() -> Node3D:
	var host := Node3D.new()
	add_child_autofree(host)
	return host

# ------------------------------------------------------------------------------------------------------------
# the column a drop falls down
# ------------------------------------------------------------------------------------------------------------

func test_a_drops_lifetime_is_the_column_divided_by_the_speed() -> void:
	# If these drift apart the failure is silent and awful: too short and rain evaporates at eye level, too long
	# and every drop is still alive far below you, spending the budget where nobody is looking.
	var r := _rain(_host())
	r.spawn_height = 12.0
	r.fall_depth = 20.0
	r.fall_speed = 16.0
	r._ready()
	assert_almost_eq(float(r.lifetime), 2.0, 0.001, "(12 + 20) / 16 = 2 s")

func test_the_field_is_full_on_the_very_first_frame() -> void:
	# Without the preprocess you watch the rain fill in from the top over a second every time a level loads.
	var r := _rain(_host())
	r._ready()
	assert_almost_eq(float(r.preprocess), float(r.lifetime), 0.001, "preprocess must cover a whole lifetime")

func test_drops_are_simulated_in_world_space_not_with_the_emitter() -> void:
	# local_coords on would drag every drop along as the emitter chases the camera, so rain would hang in the
	# air beside you instead of falling past you.
	var r := _rain(_host())
	r._ready()
	assert_false(r.local_coords, "rain must fall through the world, not with its emitter")

func test_the_emitter_is_a_thin_slab_not_a_box() -> void:
	# A tall emission volume would start some drops halfway down the column, which reads as rain appearing out of
	# nothing at eye level.
	var r := _rain(_host())
	r.volume_extents = Vector2(14.0, 9.0)
	r._ready()
	var pm := r.process_material as ParticleProcessMaterial
	assert_almost_eq(pm.emission_box_extents.x, 14.0, 0.001, "the slab spans the authored width")
	assert_almost_eq(pm.emission_box_extents.z, 9.0, 0.001, "and depth")
	assert_true(pm.emission_box_extents.y < 1.0, "but is thin, so every drop starts at the top of the column")

func test_drops_fall_at_the_authored_speed_and_do_not_accelerate() -> void:
	var r := _rain(_host())
	r.fall_speed = 25.0
	r.lean_degrees = 0.0
	r.spawn_height = 11.0
	r.fall_depth = 14.0
	r._ready()
	var pm := r.process_material as ParticleProcessMaterial
	assert_almost_eq(pm.direction.y, -1.0, 0.001, "straight down")
	assert_true(pm.initial_velocity_min <= 25.0 and pm.initial_velocity_max >= 25.0,
		"the speed spread must straddle the authored %0.1f" % r.fall_speed)
	assert_almost_eq(float(r.lifetime), 1.0, 0.001, "and cross the 25 m column in a second")
	assert_eq(pm.gravity, Vector3.ZERO,
		"gravity on top of the initial velocity would make the whole field accelerate away")

func test_a_drop_is_a_streak() -> void:
	var r := _rain(_host())
	r.drop_length = 0.6
	r.drop_width = 0.02
	r._ready()
	var quad := r.draw_pass_1 as QuadMesh
	assert_almost_eq(quad.size.y, 0.6, 0.001, "a drop is as long as it was authored")
	assert_true(quad.size.y > quad.size.x * 5.0, "and far longer than it is wide, or it reads as snow")
	# ⭐ The streak is oriented by the NODE, not by a material billboard flag: `transform_align` turns the quad's
	# face to the camera AND lays its length along the drop's velocity. A BaseMaterial3D billboard would
	# overwrite that whole basis in the vertex shader and pin every streak to screen-vertical — which is exactly
	# what made rain look wrong the moment you looked up.
	assert_eq(r.transform_align, GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY,
		"the node aligns the streak to the direction the drop is actually travelling")
	var mat := quad.material as ShaderMaterial
	assert_true(mat != null, "and the drop is drawn by its own shader, not a StandardMaterial3D")
	assert_true(str(mat.shader.resource_path).ends_with("rain_drop.gdshader"), "the rain drop shader")

## The engine's own Y-to-velocity alignment flattens the velocity into the screen plane and NORMALISES it, so it
## can turn a streak but never shorten one — a drop coming straight at the lens still draws full length. The
## shader puts that term back, and it can only do so if it is told which way the rain falls.
func test_the_shader_knows_which_way_the_rain_falls() -> void:
	var r := _rain(_host())
	r.lean_degrees = 30.0
	r.wind_heading_degrees = 90.0
	r._ready()
	var mat := (r.draw_pass_1 as QuadMesh).material as ShaderMaterial
	var dir: Vector3 = mat.get_shader_parameter("fall_direction")
	var pm := r.process_material as ParticleProcessMaterial
	assert_almost_eq(dir.x, pm.direction.x, 0.001, "the shader's fall direction IS the emitter's")
	assert_almost_eq(dir.y, pm.direction.y, 0.001, "in Y too")
	assert_almost_eq(dir.z, pm.direction.z, 0.001, "and in Z — a disagreement here foreshortens the wrong axis")

## ⭐ A streak seen exactly end-on is geometrically a point, and rain that DELETES itself the moment you look up
## at it is a worse lie than rain that never turned. The floor is the whole reason the collapse is safe.
func test_an_end_on_drop_collapses_to_a_dash_and_never_to_nothing() -> void:
	var r := _rain(_host())
	r._ready()
	var mat := (r.draw_pass_1 as QuadMesh).material as ShaderMaterial
	assert_true(float(mat.get_shader_parameter("end_on_length")) > 0.0,
		"an end-on drop must keep SOME length, or looking up deletes the weather")
	assert_true(float(mat.get_shader_parameter("end_on_length")) < 0.5,
		"but clearly less than a side-on one, or nothing was foreshortened")
	assert_true(float(mat.get_shader_parameter("end_on_width")) >= 1.0,
		"and it widens as it shortens, so it reads as a dot rather than a hair")

## The lean has to be a real sideways VELOCITY, because a velocity-aligned streak can only show a lean the drop
## actually has. A sprite rotation on top of it would tilt the quad off the line the drop travels, so the drop
## would visibly slide sideways along its own streak.
func test_the_lean_is_a_real_velocity_not_a_sprite_rotation() -> void:
	var r := _rain(_host())
	r.lean_degrees = 30.0
	r.wind_heading_degrees = 90.0   # drives toward +X
	r.fall_speed = 20.0
	r._ready()
	var pm := r.process_material as ParticleProcessMaterial
	assert_almost_eq(pm.direction.x, 0.5, 0.001, "30 degrees off vertical toward the heading")
	assert_almost_eq(pm.direction.y, -0.866, 0.001, "and still mostly downward")
	assert_almost_eq(pm.direction.z, 0.0, 0.001, "heading 90 is +X, so nothing in Z")
	assert_almost_eq(pm.angle_min, 0.0, 0.001, "and NO sprite roll on top of it")
	assert_almost_eq(pm.angle_max, 0.0, 0.001, "either end of the range")

## `fall_speed` is the DOWNWARD speed. A leaning drop travels further per metre of descent, so it has to move
## faster along its own line — otherwise the lean secretly slows the rain and the lifetime over-runs the column.
func test_leaning_does_not_slow_the_fall() -> void:
	var r := _rain(_host())
	r.lean_degrees = 60.0
	r.fall_speed = 10.0
	r._ready()
	var pm := r.process_material as ParticleProcessMaterial
	var mid := (pm.initial_velocity_min + pm.initial_velocity_max) * 0.5
	assert_almost_eq(mid * -pm.direction.y, 10.0, 0.01, "the DOWNWARD component is still the authored speed")
	assert_true(mid > 19.0, "which at 60 degrees means moving about twice that along the streak")

# ------------------------------------------------------------------------------------------------------------
# it rides the camera
# ------------------------------------------------------------------------------------------------------------

func test_the_field_rides_above_whatever_camera_is_rendering() -> void:
	# The entire reason a few thousand drops can read as a downpour: every one of them is in frame.
	var host := _host()
	var cam := Camera3D.new()
	host.add_child(cam)
	cam.make_current()
	cam.global_position = Vector3(30.0, 7.0, -12.0)
	var r := _rain(host)
	r.spawn_height = 11.0
	r.lean_degrees = 0.0       # straight down, so there is no upwind offset to account for (next test)
	r.stop_when_sheltered = false
	r._ready()
	r._process(0.016)
	assert_almost_eq(r.global_position.x, 30.0, 0.01, "the emitter follows the camera in X")
	assert_almost_eq(r.global_position.z, -12.0, 0.01, "and in Z")
	assert_almost_eq(r.global_position.y, 18.0, 0.01, "and rides `spawn_height` above it")

## Leaning drops are born upwind and land downwind. An emitter centred overhead would therefore thin out the
## upwind half of the view by the time the drops reach eye level, so it rides half a drift into the weather.
func test_the_emitter_rides_upwind_when_the_rain_leans() -> void:
	var host := _host()
	var cam := Camera3D.new()
	host.add_child(cam)
	cam.make_current()
	cam.global_position = Vector3.ZERO
	var r := _rain(host)
	r.lean_degrees = 45.0
	r.wind_heading_degrees = 90.0   # drives toward +X
	r.stop_when_sheltered = false
	r._ready()
	r._process(0.016)
	assert_true(r.global_position.x < -0.5, "the emitter sits UPWIND (-X) of a camera the rain blows toward +X")
	assert_almost_eq(r.global_position.z, 0.0, 0.01, "and square on the axis the weather is not crossing")

# ------------------------------------------------------------------------------------------------------------
# it stops indoors
# ------------------------------------------------------------------------------------------------------------

## A camera under a solid roof, and the same camera in the open. Physics needs a couple of stepped frames before
## a raycast reports anything — an un-stepped body is the trap here, not the idle frame.
func _sheltered_under(roof: bool) -> bool:
	var host := _host()
	var cam := Camera3D.new()
	host.add_child(cam)
	cam.make_current()
	cam.global_position = Vector3.ZERO
	if roof:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(20.0, 1.0, 20.0)
		shape.shape = box
		body.add_child(shape)
		host.add_child(body)
		body.global_position = Vector3(0.0, 6.0, 0.0)
	var r := _rain(host)
	r.shelter_probe_height = 30.0
	r._ready()
	await wait_physics_frames(3)
	return r._is_sheltered(cam)

func test_it_knows_when_something_is_overhead() -> void:
	var sheltered: bool = await _sheltered_under(true)
	assert_true(sheltered, "a solid roof 6 m up must read as shelter")

func test_it_knows_when_the_sky_is_open() -> void:
	var sheltered: bool = await _sheltered_under(false)
	assert_false(sheltered, "open sky must not read as shelter")

## ⭐ The regression this file exists to hold down. `Player.is_indoors` answers "am I in a room" from a 6 m
## ceiling scan; it is a plain `false` under a bridge, an awning, a gantry or an atrium roof — and a plain
## `false` in any level that never got an IndoorAmbienceDucker. Taking it as the verdict rained on your head in
## all of those, so the node's own (taller, wider) fan has to be able to overrule a `false`.
func test_a_roof_the_player_does_not_call_indoors_still_stops_the_rain() -> void:
	var host := _host()
	var cam := Camera3D.new()
	host.add_child(cam)
	cam.make_current()
	cam.global_position = Vector3.ZERO
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30.0, 1.0, 30.0)
	shape.shape = box
	body.add_child(shape)
	host.add_child(body)
	body.global_position = Vector3(0.0, 18.0, 0.0)   # well above the player's 6 m indoors scan
	var r := _rain(host)
	r._ready()
	await wait_physics_frames(3)
	assert_true(r._is_sheltered(cam), "a roof 18 m up is still a roof, whatever the player's flag says")

## A single ray flickers you back out into the rain under a skylight or a rafter gap, so the probe is a fan and
## a minority of misses still counts as covered.
func test_a_gap_directly_overhead_does_not_flicker_the_rain_back_on() -> void:
	var host := _host()
	var cam := Camera3D.new()
	host.add_child(cam)
	cam.make_current()
	cam.global_position = Vector3.ZERO
	# Two slabs with a narrow slot between them, the slot centred right over the camera.
	for side: float in [-1.0, 1.0]:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(10.0, 1.0, 20.0)
		shape.shape = box
		body.add_child(shape)
		host.add_child(body)
		body.global_position = Vector3(side * 5.4, 8.0, 0.0)
	var r := _rain(host)
	r.shelter_probe_radius = 0.9
	r._ready()
	await wait_physics_frames(3)
	assert_true(r._is_sheltered(cam), "a slot overhead is not open sky")

## Moving far enough must re-probe even mid-throttle — a fixed interval is what makes rain keep falling through
## the ceiling for the first stride indoors.
func test_walking_a_long_way_re_probes_before_the_throttle_expires() -> void:
	var host := _host()
	var cam := Camera3D.new()
	host.add_child(cam)
	cam.make_current()
	cam.global_position = Vector3.ZERO
	var r := _rain(host)
	r._ready()
	r._process(0.016)              # first sample: open sky, and primes the field
	r._shelter_timer = 999.0       # throttle wide open
	r._sheltered = true            # a stale verdict the next _process must not simply keep
	r._process(0.016)
	assert_true(r._sheltered, "standing still keeps the throttled verdict")
	cam.global_position = Vector3(0.0, 0.0, 40.0)
	r._process(0.016)
	assert_false(r._sheltered, "but moving a long way re-probes immediately")

func test_walking_under_cover_stops_the_emitter_rather_than_hiding_the_rain() -> void:
	# The FALLBACK path (`occlude_under_roofs` off). Hiding would delete the drops already in the air, so cover
	# would snap the rain off between one frame and the next; stopping the emitter lets the last drops finish.
	var host := _host()
	var cam := Camera3D.new()
	host.add_child(cam)
	cam.make_current()
	var r := _rain(host)
	r.occlude_under_roofs = false
	r._ready()
	r._sheltered = true
	r._shelter_timer = 999.0   # so _process uses the state above instead of re-probing
	r._process(0.016)
	assert_false(r.emitting, "sheltered must stop EMITTING")
	assert_true(r.visible, "but must not hide the node, or drops in flight vanish")

## ⭐ THE REGRESSION THE OCCLUSION PATH EXISTS TO PREVENT. Switching the emitter off under a roof deletes the
## weather EVERYWHERE, because the field rides the camera — so standing in a doorway you watched a dry city
## through it. With per-drop occlusion the emitter is left alone and the drops cull themselves.
func test_cover_does_not_switch_the_whole_field_off_when_drops_cull_themselves() -> void:
	var host := _host()
	var cam := Camera3D.new()
	host.add_child(cam)
	cam.make_current()
	var r := _rain(host)
	r._ready()
	r._sheltered = true
	r._shelter_timer = 999.0
	r._process(0.016)
	assert_true(r.occlude_under_roofs, "occlusion is the default path")
	assert_true(r.emitting, "cover must NOT stop the emitter, or the rain you can see outside dies with it")

## Starting a level already under a roof is the one case the tail-off gets wrong: `_ready` has just preprocessed
## a full lifetime of drops into the air above you, and they would fall through the ceiling. ⭐ The clear has to
## survive `restart()` switching emitting back on, which is the trap this test exists for.
func test_starting_under_a_roof_does_not_open_with_a_column_of_rain() -> void:
	var host := _host()
	var cam := Camera3D.new()
	host.add_child(cam)
	cam.make_current()
	cam.global_position = Vector3.ZERO
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30.0, 1.0, 30.0)
	shape.shape = box
	body.add_child(shape)
	host.add_child(body)
	body.global_position = Vector3(0.0, 5.0, 0.0)
	var r := _rain(host)
	r.occlude_under_roofs = false   # the fallback path is the one that clears the field; see the test below
	r._ready()
	await wait_physics_frames(3)
	r._process(0.016)
	assert_true(r._sheltered, "the very first probe must see the roof")
	assert_false(r.emitting, "and the field must not be emitting after it")

func test_the_shelter_probe_can_be_switched_off_entirely() -> void:
	var host := _host()
	var cam := Camera3D.new()
	host.add_child(cam)
	cam.make_current()
	var r := _rain(host)
	r.stop_when_sheltered = false
	r._ready()
	r._sheltered = true
	r._process(0.016)
	assert_true(r.emitting, "with the probe off the rain must keep falling regardless")

# ------------------------------------------------------------------------------------------------------------
# the sky heightfield
# ------------------------------------------------------------------------------------------------------------

## A camera under one end of a long slab, with the other end of the world open. Physics needs a couple of
## stepped frames before a raycast reports anything.
func _grid_stage(roof_at: Vector3, roof_size: Vector3) -> Array:
	var host := _host()
	var cam := Camera3D.new()
	host.add_child(cam)
	cam.make_current()
	cam.global_position = Vector3.ZERO
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = roof_size
	shape.shape = box
	body.add_child(shape)
	host.add_child(body)
	body.global_position = roof_at
	var r := _rain(host)
	r._ready()
	await wait_physics_frames(3)
	r._process(0.016)   # the first sweep covers the WHOLE grid, so one frame is enough
	return [r, cam]

## ⭐ THE PROBE POINTS DOWN. A ray cast UP finds the first thing above its origin, which on an upper floor is the
## ceiling BELOW you; cast down from above everything and the first hit is the topmost surface, which is the
## height rain actually stops at.
func test_the_grid_records_the_top_of_whatever_covers_a_cell() -> void:
	var made: Array = await _grid_stage(Vector3(0.0, 9.0, 0.0), Vector3(12.0, 2.0, 12.0))
	var r: Node = made[0]
	assert_almost_eq(r.sky_height_at(Vector3.ZERO), 10.0, 0.2,
		"the cell under the slab stops rain at the slab's TOP face (9 + half of 2)")

func test_a_cell_with_open_sky_over_it_stops_no_rain_at_all() -> void:
	var made: Array = await _grid_stage(Vector3(0.0, 9.0, 0.0), Vector3(12.0, 2.0, 12.0))
	var r: Node = made[0]
	# 10 m out, well clear of a 12 m slab centred on the origin, and inside the 28 m field.
	assert_true(r.sky_height_at(Vector3(10.0, 0.0, 0.0)) < -1000.0,
		"open sky must read as the SKY_OPEN sentinel, not as a roof at zero")

## The whole point: standing under cover, the cell you are in is shut and a cell a few metres out is not. That
## difference is the rain you can see through the doorway.
func test_standing_under_cover_leaves_the_street_outside_raining() -> void:
	var made: Array = await _grid_stage(Vector3(0.0, 6.0, 0.0), Vector3(10.0, 1.0, 10.0))
	var r: Node = made[0]
	assert_true(r.sky_height_at(Vector3.ZERO) > 1.0, "over my head is covered")
	assert_true(r.sky_height_at(Vector3(11.0, 0.0, 0.0)) < -1000.0, "and eleven metres out is not")

## The grid is anchored to the WORLD, not to the camera, so a texel is a fixed patch of ground. Anchoring it to
## the camera would slide the pattern as you walked and shimmer every roof edge.
func test_the_grid_is_anchored_to_the_world_so_walking_does_not_slide_it() -> void:
	var made: Array = await _grid_stage(Vector3(0.0, 6.0, 0.0), Vector3(10.0, 1.0, 10.0))
	var r: Node = made[0]
	var cam: Camera3D = made[1]
	var before: float = r.sky_height_at(Vector3(3.0, 0.0, 3.0))
	cam.global_position = Vector3(4.0, 0.0, 0.0)
	r._process(0.016)
	assert_almost_eq(r.sky_height_at(Vector3(3.0, 0.0, 3.0)), before, 0.01,
		"the same patch of world must read the same after the camera moves")

## The shader does the identical lookup, so it has to be told the same cell size and grid width the node used.
func test_the_shader_is_handed_the_grid_it_has_to_sample() -> void:
	var r := _rain(_host())
	r.volume_extents = Vector2(14.0, 14.0)
	r.sky_grid_cells = 28
	r._ready()
	var mat := (r.draw_pass_1 as QuadMesh).material as ShaderMaterial
	assert_true(bool(mat.get_shader_parameter("sky_occlusion_enabled")), "occlusion is announced to the shader")
	assert_true(mat.get_shader_parameter("sky_height") is Texture2D, "with the heightfield itself")
	assert_eq(int(mat.get_shader_parameter("sky_grid_cells")), 28, "and the grid width")
	assert_almost_eq(float(mat.get_shader_parameter("sky_cell_size")), 1.0, 0.001,
		"28 m of field across 28 cells is a 1 m cell")

## ⭐ The shader's fallback for an unset sampler is BLACK, which reads as a roof at y = 0 and would cull the
## whole world. The flag must never be true without a texture behind it.
func test_the_shader_is_told_occlusion_is_off_when_there_is_no_grid() -> void:
	var r := _rain(_host())
	r.occlude_under_roofs = false
	r._ready()
	var mat := (r.draw_pass_1 as QuadMesh).material as ShaderMaterial
	assert_false(bool(mat.get_shader_parameter("sky_occlusion_enabled")),
		"no grid must mean no occlusion, or an unset sampler reads black and hides everything below y=0")

## A grid too slow to sweep drags its roof edges behind the player, which is an authoring mistake the inspector
## should catch rather than something to discover in a level.
func test_it_warns_when_the_grid_cannot_keep_up() -> void:
	var r := _rain(_host())
	r.sky_grid_cells = 64
	r.sky_cells_per_frame = 4
	assert_string_contains(str(r._get_configuration_warnings()), "sky_cells_per_frame")

# ------------------------------------------------------------------------------------------------------------
# the rain bed
# ------------------------------------------------------------------------------------------------------------

func test_it_plays_a_looping_bed_on_the_ambient_bus() -> void:
	# ⭐ The bus is the whole point: `ambient` is what the player's Ambient volume slider governs and what
	# IndoorAmbienceDucker muffles behind a roof. A bare AudioStreamPlayer defaults to Master and escapes both.
	var r := _rain(_host())
	r._ready()
	var bed := r._bed as AudioStreamPlayer
	assert_true(bed != null, "a rain bed must be built")
	assert_eq(bed.bus, &"ambient", "and routed to the ambient bus, never Master")
	assert_true(bed.stream != null, "with the shipped rain loop loaded")
	assert_true(bed.playing, "and playing")

func test_the_bed_is_not_positional() -> void:
	# Rain is not somewhere, it is everywhere — a 3D player would pan it and fade it with distance.
	var r := _rain(_host())
	r._ready()
	assert_false(r._bed is AudioStreamPlayer3D, "the bed must be a plain, non-positional player")

func test_the_bed_can_be_switched_off_without_touching_the_visual_rain() -> void:
	var r := _rain(_host())
	r.use_default_sound = false
	r._ready()
	assert_true(r._bed == null, "no bed when the default is declined and nothing is assigned")
	assert_true(r.draw_pass_1 != null, "but the rain itself is unaffected")

## The shipped scene is ONLY the scripted root — levels instance it and PreloadManager warms it — so everything
## the rain draws with must come from _ready, not from resources a level used to bake in beside an inline node.
func test_the_shipped_scene_builds_its_own_rain_when_instanced_bare() -> void:
	var ps: PackedScene = load("res://scenes/components/rain_fall.tscn")
	var r: Node = ps.instantiate()
	assert_true(r.get_script() == RAIN, "the scene's root IS the RainFall script")
	assert_true(r.process_material == null and r.draw_pass_1 == null, "(nothing baked into the scene itself)")
	_host().add_child(r)
	assert_true(r.process_material is ParticleProcessMaterial, "_ready builds the process material")
	assert_true(r.draw_pass_1 is QuadMesh, "_ready builds the drop streak")
	assert_eq(int(r.amount), int(r.drops), "and sizes the field from its drops export")
	assert_true(r._bed != null, "a bare instance brings its rain bed")

func test_declining_the_sound_before_entering_the_tree_never_starts_a_bed() -> void:
	# The boot particle warm-up does exactly this (PreloadManager._prewarm_gpu_particles), so the rain loop is
	# never heard for the eight frames the emitter spends compiling in a throwaway viewport.
	var r: Node = (load("res://scenes/components/rain_fall.tscn") as PackedScene).instantiate()
	r.set(&"use_default_sound", false)
	_host().add_child(r)
	assert_true(r._bed == null, "no bed was ever started")
	var players := r.find_children("*", "AudioStreamPlayer", true, false)
	assert_eq(players.size(), 0, "and no audio player sits under the emitter")
	assert_true(r.draw_pass_1 != null, "while the rain itself still builds, which is what the warm-up needs")

func test_shelter_ducks_the_bed_instead_of_silencing_it() -> void:
	# You still hear rain on the roof over your head; a hard cut reads as the weather being switched off.
	var host := _host()
	var cam := Camera3D.new()
	host.add_child(cam)
	cam.make_current()
	var r := _rain(host)
	r.sound_volume_db = -9.0
	r.sheltered_volume_db = -19.0
	r.sound_fade_db_per_second = 1000.0   # so one step lands on the target
	r._ready()
	r._sheltered = true
	r._shelter_timer = 999.0
	r._process(0.1)
	assert_almost_eq(float(r._bed.volume_db), -19.0, 0.01, "sheltered ducks the bed toward its indoor level")
	r._sheltered = false
	r._process(0.1)
	assert_almost_eq(float(r._bed.volume_db), -9.0, 0.01, "and back out under open sky")

func test_the_bed_fades_rather_than_jumping() -> void:
	var host := _host()
	var cam := Camera3D.new()
	host.add_child(cam)
	cam.make_current()
	var r := _rain(host)
	r.sound_volume_db = 0.0
	r.sheltered_volume_db = -40.0
	r.sound_fade_db_per_second = 10.0
	r._ready()
	r._sheltered = true
	r._shelter_timer = 999.0
	r._process(0.1)   # 10 dB/s for 0.1 s = 1 dB, nowhere near the target
	assert_almost_eq(float(r._bed.volume_db), -1.0, 0.01, "a doorway must be a transition, not a switch")

func test_it_warns_when_the_bus_does_not_exist() -> void:
	var r := _rain(_host())
	r.sound_bus = &"no_such_bus"
	assert_string_contains(str(r._get_configuration_warnings()), "sound_bus")

# ------------------------------------------------------------------------------------------------------------
# inspector warnings
# ------------------------------------------------------------------------------------------------------------

func test_it_warns_when_a_drop_is_not_a_streak() -> void:
	var r := _rain(_host())
	r.drop_length = 0.01
	r.drop_width = 0.02
	assert_string_contains(str(r._get_configuration_warnings()), "STREAK")

func test_it_warns_when_the_column_has_no_height() -> void:
	var r := _rain(_host())
	r.spawn_height = 0.0
	assert_string_contains(str(r._get_configuration_warnings()), "spawn_height")
