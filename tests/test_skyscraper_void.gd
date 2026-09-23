extends GutTest
## Contract tests for the SkyscraperVoid drop-in (scripts/components/skyscraper_void.gd) — the runtime facade
## that turns a level's footprint into the roof of a tower.
##
## What is worth pinning here is everything a screenshot CANNOT judge, and every invariant whose failure looks
## like an art problem instead of a bug:
##   • the facade faces OUTWARD whichever way the author wound the footprint (a flipped quad is an invisible
##     building, not an ugly one);
##   • UV.x is METRES along the perimeter (the shader divides by `bay_width`, so a 0..1 UV would rescale the
##     window grid per edge and destroy the sense of size that is the entire point);
##   • the walls wear a ShaderMaterial, which is the ONLY reason Ps1Warp's applier leaves the drop alone;
##   • it builds no collider and casts no shadow, so it cannot touch play;
##   • the auto fit never measures its own output (or the footprint grows on every rebuild);
##   • the neighbour skyline is deterministic from the seed and entirely BELOW your roofline.
##
## ⭐ The component is reached through `preload` + `.new()` and typed as `Node`, never by naming
## `SkyscraperVoid`: a brand-new `class_name` is not in the global class cache until the editor rescans, and
## naming the type would drop this whole FILE from the suite until then.

const VOID: GDScript = preload("res://scripts/components/skyscraper_void.gd")
const FACADE_SHADER_PATH := "res://resources/shaders/facade_void.gdshader"
const CLOUD_SHADER_PATH := "res://resources/shaders/overcast_clouds.gdshader"

# ------------------------------------------------------------------------------------------------------------
# harness
# ------------------------------------------------------------------------------------------------------------

## A bare stand-in for a level root: in-tree (the component needs a tree for the group/env lookups) and freed
## with the test.
func _host() -> Node3D:
	var host := Node3D.new()
	add_child_autofree(host)
	return host

## A drop with an AUTHORED footprint (no fit) and no neighbours — the narrow case most tests want.
func _drop(host: Node3D, size: Vector2 = Vector2(40.0, 60.0)) -> Node:
	var v: Node = VOID.new()
	v.fit_to_level = false
	v.footprint_size = size
	v.footprint_center = Vector2.ZERO
	v.footprint_inset = 0.0
	v.depth = 500.0
	v.haze_distance = 900.0
	v.haze_floor_depth = 200.0
	v.haze_floor_enabled = true   # ships OFF (the reference has no ground); the plane's own tests want one
	v.facade_enabled = true       # ships OFF too (it traces the level's boundary); the skirt's tests want one
	v.clouds_enabled = false      # ships ON; the overcast deck has its own tests and would skew the mesh counts
	v.tower_count = 0
	v.auto_haze_from_fog = false
	host.add_child(v)   # _ready() builds
	return v

func _arrays(mi: MeshInstance3D, surface: int) -> Array:
	return mi.mesh.surface_get_arrays(surface)

func _mesh_child(v: Node, child: String) -> MeshInstance3D:
	return v.get_node_or_null(child) as MeshInstance3D

# ------------------------------------------------------------------------------------------------------------
# the facade skirt
# ------------------------------------------------------------------------------------------------------------

func test_builds_one_quad_per_footprint_edge() -> void:
	var v := _drop(_host())
	var facade := _mesh_child(v, "Facade")
	assert_true(facade != null, "the drop must build a `Facade` MeshInstance3D")
	assert_eq(facade.mesh.get_surface_count(), 1, "the skirt is one surface")
	var arr := _arrays(facade, 0)
	assert_eq((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 16, "4 edges x 4 corners")
	assert_eq((arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), 24, "4 edges x 2 triangles")

func test_the_skirt_hangs_from_the_roofline_down_by_depth() -> void:
	var v := _drop(_host())
	v.top_overlap = 0.5
	v.depth = 500.0
	v.build()
	var box: AABB = _mesh_child(v, "Facade").mesh.get_aabb()
	assert_almost_eq(box.position.y + box.size.y, 0.5, 0.01, "the top reaches `top_overlap` above the roofline")
	assert_almost_eq(box.position.y, -500.0, 0.01, "the bottom is `depth` below the roofline")

func test_uv_x_is_metres_along_the_perimeter_not_zero_to_one() -> void:
	# The shader reads window columns as UV.x / bay_width. If this ever became a normalised 0..1 UV, a 60 m wall
	# and a 40 m wall would draw the SAME number of windows and the building would stop having a size.
	var v := _drop(_host(), Vector2(40.0, 60.0))
	var uvs: PackedVector2Array = _arrays(_mesh_child(v, "Facade"), 0)[Mesh.ARRAY_TEX_UV]
	var widest := 0.0
	for uv in uvs:
		widest = maxf(widest, uv.x)
	assert_almost_eq(widest, 200.0, 0.01, "UV.x runs to the full perimeter in metres (2*40 + 2*60)")

func test_uv_y_is_metres_of_drop() -> void:
	var v := _drop(_host())
	var uvs: PackedVector2Array = _arrays(_mesh_child(v, "Facade"), 0)[Mesh.ARRAY_TEX_UV]
	var deepest := 0.0
	for uv in uvs:
		deepest = maxf(deepest, uv.y)
	assert_almost_eq(deepest, 500.5, 0.01, "UV.y spans top_overlap + depth in metres")

func test_wall_normals_face_outward() -> void:
	var v := _drop(_host())
	var arr := _arrays(_mesh_child(v, "Facade"), 0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	for i in verts.size():
		var out := Vector3(verts[i].x, 0.0, verts[i].z)   # footprint is centred on the origin here
		assert_true(norms[i].dot(out.normalized()) > 0.5,
			"vertex %d's normal %s must point away from the building's centre, not into it" % [i, norms[i]])

func test_the_walls_wind_so_their_outer_face_is_the_visible_one() -> void:
	# The winding, not the normal attribute (see CROSS_POINTS_AWAY_FROM_THE_VISIBLE_SIDE): for a wall you see
	# from outside the building, each triangle's right-hand cross product must point back INTO the footprint.
	var v := _drop(_host())
	var arr := _arrays(_mesh_child(v, "Facade"), 0)
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for t in idx.size() / 3:
		var facing := _winding(arr, t).normalized()
		var mid := verts[idx[t * 3]]
		var inward := -Vector3(mid.x, 0.0, mid.z).normalized()   # footprint centred on the origin
		assert_true(facing.dot(inward) > 0.5,
			"wall triangle %d winds inside-out (cross %s vs inward %s) — the facade would be invisible" % [t, facing, inward])

func test_a_clockwise_authored_footprint_is_rewound_so_the_facade_still_faces_out() -> void:
	# A designer typing points into the Inspector has no reason to know which winding Godot wants, and the
	# failure mode is silent: with backface culling on, an inside-out skirt is a building you cannot see.
	var v: Node = VOID.new()
	v.fit_to_level = false
	v.tower_count = 0
	v.auto_haze_from_fog = false
	v.facade_enabled = true
	v.footprint_points = PackedVector2Array([
		Vector2(-20.0, -20.0), Vector2(-20.0, 20.0), Vector2(20.0, 20.0), Vector2(20.0, -20.0),
	])   # clockwise in X/Z
	_host().add_child(v)
	var arr := _arrays(_mesh_child(v, "Facade"), 0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	for i in verts.size():
		var out := Vector3(verts[i].x, 0.0, verts[i].z)
		assert_true(norms[i].dot(out.normalized()) > 0.5,
			"a clockwise footprint must be rewound; vertex %d's normal %s points inward" % [i, norms[i]])

# ------------------------------------------------------------------------------------------------------------
# it must not be repainted, and it must not touch play
# ------------------------------------------------------------------------------------------------------------

func test_every_surface_wears_the_facade_shader_so_ps1warp_leaves_it_alone() -> void:
	# Ps1Warp's applier swaps every plain BaseMaterial3D surface in a level for the PS1 warp shader and SKIPS
	# ShaderMaterial surfaces (scripts/effects/ps1_applier.gd::_ps1ify). A StandardMaterial3D here would mean
	# the whole drop gets repainted on load — the facade, the haze plane and the skyline all at once.
	var v := _drop(_host())
	v.tower_count = 4
	v.build()
	for child in v.get_children():
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s) as ShaderMaterial
			assert_true(mat != null, "%s surface %d must carry a ShaderMaterial" % [mi.name, s])
			assert_eq(mat.shader.resource_path, FACADE_SHADER_PATH,
				"%s surface %d must wear the facade shader" % [mi.name, s])

func test_it_builds_no_collider_and_casts_no_shadow() -> void:
	var v := _drop(_host())
	v.tower_count = 3
	v.build()
	var stack: Array[Node] = [v]
	var meshes := 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		assert_true(not (n is CollisionObject3D) and not (n is CollisionShape3D),
			"%s is collision — the drop must be unreachable, unshootable scenery" % n.name)
		var mi := n as MeshInstance3D
		if mi != null:
			meshes += 1
			assert_eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
				"%s must not cast a shadow (a 3 km wall would shadow the level)" % mi.name)
			assert_eq(mi.gi_mode, GeometryInstance3D.GI_MODE_DISABLED, "%s must stay out of GI" % mi.name)
		for c in n.get_children():
			stack.append(c)
	assert_eq(meshes, 3, "facade + haze floor + towers")

func test_it_gives_every_mesh_a_custom_aabb_so_it_cannot_be_culled_out_of_frame() -> void:
	var v := _drop(_host())
	for child in v.get_children():
		var mi := child as MeshInstance3D
		if mi != null:
			assert_true(mi.custom_aabb.size.length() > 0.0,
				"%s needs a custom AABB — seen almost edge-on over a parapet, its real bounds cull it" % mi.name)

func test_rebuilding_replaces_its_output_instead_of_stacking_it() -> void:
	var v := _drop(_host())
	v.build()
	v.build()
	var names := PackedStringArray()
	for c in v.get_children():
		names.append(c.name)
	assert_eq(names.size(), 2, "one facade + one haze floor after three builds, got %s" % str(names))

# ------------------------------------------------------------------------------------------------------------
# the auto fit
# ------------------------------------------------------------------------------------------------------------

func _boxy(host: Node3D, at: Vector3, size: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	host.add_child(mi)
	mi.position = at
	return mi

## Two boxes with a known merged extent (x: -35..55, z: -5..25) and a known lowest point (y = -2).
func _two_box_level(host: Node3D) -> void:
	_boxy(host, Vector3(-30.0, 0.0, 0.0), Vector3(10.0, 4.0, 10.0))     # x: -35..-25, y: -2..2
	_boxy(host, Vector3(50.0, 6.0, 20.0), Vector3(10.0, 4.0, 10.0))     # x:  45..55,  y:  4..8

func test_the_fit_takes_the_footprint_rect_from_the_level_geometry() -> void:
	var host := _host()
	_two_box_level(host)
	var v: Node = VOID.new()
	v.fit_to_level = true
	v.footprint_inset = 0.0
	v.tower_count = 0
	v.auto_haze_from_fog = false
	v.facade_enabled = true
	host.add_child(v)
	var box: AABB = _mesh_child(v, "Facade").mesh.get_aabb()
	assert_almost_eq(box.size.x, 90.0, 0.01, "the skirt spans the fitted X extent (-35..55)")
	assert_almost_eq(box.size.z, 30.0, 0.01, "the skirt spans the fitted Z extent (-5..25)")

func test_the_roofline_defaults_to_this_nodes_own_height_not_the_levels_lowest_point() -> void:
	# The bug this pins, measured on the shipped city map: its AABB bottom is the underside of the skybox brush
	# 50 m under the street, so a LEVEL_BOTTOM default hung the whole facade in an invisible basement. The floor
	# the player stands on is authored by DRAGGING this node, which is also the only version the editor preview
	# can reproduce (an edit-time scene has no physics to probe the ground with).
	var host := _host()
	_two_box_level(host)
	var v: Node = VOID.new()
	v.fit_to_level = true
	v.tower_count = 0
	v.auto_haze_from_fog = false
	v.facade_enabled = true
	host.add_child(v)
	v.position = Vector3(0.0, 12.0, 0.0)
	v.build()
	assert_almost_eq(float(v.last_roof_y), 0.0, 0.01, "NODE_Y means local 0 — the node's own height")
	var top: float = _mesh_child(v, "Facade").global_transform.origin.y + _mesh_child(v, "Facade").mesh.get_aabb().end.y
	assert_almost_eq(top, 12.5, 0.01, "so in WORLD space the skirt's top follows the node (12 + top_overlap)")

func test_the_level_bottom_roofline_hangs_the_drop_from_the_lowest_geometry() -> void:
	var host := _host()
	_two_box_level(host)
	var v: Node = VOID.new()
	v.fit_to_level = true
	v.roofline = 1   # Roofline.LEVEL_BOTTOM
	v.tower_count = 0
	v.auto_haze_from_fog = false
	host.add_child(v)
	assert_almost_eq(float(v.last_roof_y), -2.0, 0.01, "LEVEL_BOTTOM is the lowest point of the geometry")

func test_the_roofline_offset_nudges_it() -> void:
	var v := _drop(_host())
	v.roofline_offset = -3.0
	v.build()
	assert_almost_eq(float(v.last_roof_y), -3.0, 0.01, "the offset sinks the roofline into the floor brush")

func test_the_inset_pulls_the_skirt_inside_the_fitted_edge() -> void:
	var host := _host()
	_boxy(host, Vector3.ZERO, Vector3(40.0, 2.0, 40.0))
	var v: Node = VOID.new()
	v.fit_to_level = true
	v.footprint_inset = 2.0
	v.tower_count = 0
	v.auto_haze_from_fog = false
	v.facade_enabled = true
	host.add_child(v)
	var box: AABB = _mesh_child(v, "Facade").mesh.get_aabb()
	assert_almost_eq(box.size.x, 36.0, 0.01, "a 2 m inset takes 2 m off each side of a 40 m footprint")

func test_the_fit_never_measures_its_own_facade() -> void:
	# The regression this exists for: the facade is kilometres tall and kilometres wide, so a second fit that
	# counted it would hand back a footprint the size of the drop — and every rebuild would grow again.
	var host := _host()
	_boxy(host, Vector3.ZERO, Vector3(40.0, 2.0, 40.0))
	var v: Node = VOID.new()
	v.fit_to_level = true
	v.footprint_inset = 0.0
	v.tower_count = 0
	v.auto_haze_from_fog = false
	host.add_child(v)
	var first: PackedVector2Array = v.last_footprint
	v.build()
	assert_eq(v.last_footprint, first, "the footprint must be identical on a rebuild, not grown by its own output")

# ------------------------------------------------------------------------------------------------------------
# the neighbour skyline
# ------------------------------------------------------------------------------------------------------------

func _tower_walls(v: Node) -> Array:
	return _arrays(_mesh_child(v, "Towers"), 0)

func test_every_neighbour_roof_sits_below_your_own_when_none_may_rise() -> void:
	# The "tallest building in the city" configuration: no near blocks, nothing allowed to rise. Then every
	# neighbour roof must be at least `tower_drop_min` under yours, or the read collapses.
	var v := _drop(_host())
	v.tower_count = 12
	v.tower_drop_min = 70.0
	v.tower_near_count = 0
	v.tower_rise_share = 0.0
	v.build()
	var verts: PackedVector3Array = _tower_walls(v)[Mesh.ARRAY_VERTEX]
	var highest := -INF
	for p in verts:
		highest = maxf(highest, p.y)
	assert_true(highest <= float(v.last_roof_y) - 70.0,
		"the tallest neighbour tops out at %.1f, which is not at least 70 m below the roofline %.1f" % [highest, v.last_roof_y])

func test_the_near_neighbours_loom_over_you_and_stand_close() -> void:
	# The opposite configuration, and the shipped one. The reference frame's sense of height comes from the next
	# block standing a few dozen metres away and running UP past the top of the screen — without these the view
	# is floating slabs seen from a helicopter (probe-caught 2026-09-18).
	var v := _drop(_host(), Vector2(40.0, 60.0))
	v.tower_count = 6
	v.tower_near_count = 3
	v.tower_near_gap = 26.0
	v.tower_rise_max = 120.0
	v.build()
	var verts: PackedVector3Array = _tower_walls(v)[Mesh.ARRAY_VERTEX]
	var highest := -INF
	var closest := INF
	for p in verts:
		highest = maxf(highest, p.y)
		closest = minf(closest, Vector2(p.x, p.z).length())
	assert_true(highest > float(v.last_roof_y) + 50.0,
		"the near neighbours must rise well above the roofline; the tallest reached %.1f vs roofline %.1f" % [highest, v.last_roof_y])
	# span of a 40 x 60 footprint = 36.06 m from the centre; + the 26 m gap, and nothing may be nearer.
	assert_true(closest > 36.0, "a neighbour wall is %.1f m from the centre — inside the building" % closest)
	assert_true(closest < 140.0, "the nearest neighbour is %.1f m away — nothing is looming" % closest)

func test_neighbour_towers_stand_clear_of_the_level_footprint() -> void:
	var v := _drop(_host(), Vector2(40.0, 60.0))
	v.tower_count = 16
	v.build()
	var verts: PackedVector3Array = _tower_walls(v)[Mesh.ARRAY_VERTEX]
	for p in verts:
		assert_true(absf(p.x) > 20.0 or absf(p.z) > 30.0,
			"a neighbour tower has a wall at (%.1f, %.1f) — inside the level's own footprint" % [p.x, p.z])

func test_the_skyline_is_deterministic_from_the_seed() -> void:
	# Nothing about the drop is saved, so the skyline has to come back identical after a reload, a death or a
	# door — otherwise the city rearranges itself every time the player dies.
	var host := _host()
	var a := _drop(host)
	a.tower_count = 8
	a.tower_seed = 4242
	a.build()
	var b := _drop(host)
	b.tower_count = 8
	b.tower_seed = 4242
	b.build()
	assert_eq(_tower_walls(b)[Mesh.ARRAY_VERTEX], _tower_walls(a)[Mesh.ARRAY_VERTEX],
		"the same seed must rebuild the same skyline")
	var c := _drop(host)
	c.tower_count = 8
	c.tower_seed = 9999
	c.build()
	assert_ne(_tower_walls(c)[Mesh.ARRAY_VERTEX], _tower_walls(a)[Mesh.ARRAY_VERTEX],
		"a different seed must re-roll the skyline")

func test_tower_roofs_are_a_second_surface_with_its_own_flat_material() -> void:
	# Two surfaces, two materials — which is why the node must NOT use `material_override` (an override outranks
	# every surface material and would paint the window grid flat across the roof caps).
	var v := _drop(_host())
	v.tower_count = 6
	v.build()
	var towers := _mesh_child(v, "Towers")
	assert_eq(towers.mesh.get_surface_count(), 2, "walls + roof caps")
	assert_true(towers.material_override == null, "a material_override here would erase the roof material")
	var walls := towers.get_active_material(0) as ShaderMaterial
	var roofs := towers.get_active_material(1) as ShaderMaterial
	assert_false(bool(walls.get_shader_parameter("flat_fill")), "surface 0 is the window grid")
	assert_true(bool(roofs.get_shader_parameter("flat_fill")), "surface 1 is flat-filled roof caps")

## ⭐ GODOT'S FRONT FACE IS THE SIDE THE RIGHT-HAND CROSS PRODUCT POINTS AWAY FROM. Derived from this very
## component's WALLS, which are known-good (they render from outside the building, probe-confirmed): for an
## outward-facing wall the cross product of its triangle points INWARD. So a surface visible from ABOVE — a roof
## cap, the fog disc — must cross-product DOWNWARD. Getting this backwards is invisible in the normals and
## invisible in any single still; it just deletes the surface from the only view that matters.
const CROSS_POINTS_AWAY_FROM_THE_VISIBLE_SIDE := true

## The right-hand normal of triangle `t` of a surface's arrays.
func _winding(arr: Array, t: int) -> Vector3:
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var a := verts[idx[t * 3]]
	var b := verts[idx[t * 3 + 1]]
	var c := verts[idx[t * 3 + 2]]
	return (b - a).cross(c - a)

func test_the_caps_face_up() -> void:
	# The GEOMETRIC winding of the fog disc and the tower roof caps, not their NORMAL attribute — the attribute
	# was already UP while the triangles faced the other way, which backface-culled the fog out of every view
	# from the roof (you looked through the floor of the world into the sky) and left the towers roofless.
	# Probe-caught 2026-09-17; nothing else in this file would have failed.
	var v := _drop(_host())
	v.tower_count = 5
	v.build()
	for surface in [
		_arrays(_mesh_child(v, "HazeFloor"), 0),
		_arrays(_mesh_child(v, "Towers"), 1),
	]:
		var idx: PackedInt32Array = surface[Mesh.ARRAY_INDEX]
		assert_true(idx.size() >= 3, "a cap surface must have triangles")
		for t in idx.size() / 3:
			var facing := _winding(surface, t)
			assert_true(facing.y < 0.0,
				"cap triangle %d winds the wrong way (cross %s must point DOWN) — it is culled from above" % [t, facing])

# ------------------------------------------------------------------------------------------------------------
# the overcast deck
# ------------------------------------------------------------------------------------------------------------

func test_the_overcast_deck_ships_on_and_hangs_above_the_roofline() -> void:
	var v := _drop(_host())
	v.clouds_enabled = true
	v.cloud_height = 210.0
	v.build()
	var clouds := _mesh_child(v, "Clouds")
	assert_true(clouds != null, "clouds_enabled must build a `Clouds` deck")
	var box: AABB = clouds.mesh.get_aabb()
	assert_almost_eq(box.position.y, 210.0, 0.01, "the deck hangs `cloud_height` above the roofline")
	assert_true(box.size.x > 1000.0, "and it is wide enough that its rim is nowhere near the player")

func test_the_overcast_deck_can_be_switched_off() -> void:
	var v := _drop(_host())
	v.clouds_enabled = false
	v.build()
	assert_true(_mesh_child(v, "Clouds") == null, "clouds_enabled off must build no deck")

func test_the_deck_wears_its_own_shader_and_is_told_where_its_rim_is() -> void:
	# The rim fade is what stops the overcast having a visible edge, and it can only work if the shader knows
	# where the disc is and how big it is — those two uniforms are load-bearing, not decoration. The material is
	# a ShaderMaterial for the same reason everything else here is: Ps1Warp only repaints BaseMaterial3D.
	var v := _drop(_host())
	v.clouds_enabled = true
	v.cloud_extent = 4000.0
	v.footprint_center = Vector2(25.0, -40.0)
	v.build()
	var mat := _mesh_child(v, "Clouds").get_active_material(0) as ShaderMaterial
	assert_true(mat != null, "the deck must carry a ShaderMaterial")
	assert_eq(mat.shader.resource_path, CLOUD_SHADER_PATH, "and its own cloud shader, not the facade's")
	assert_almost_eq(float(mat.get_shader_parameter("disc_radius")), 4000.0, 0.01, "the rim fade needs the radius")
	var centre: Vector3 = mat.get_shader_parameter("disc_centre")
	assert_almost_eq(centre.x, 25.0, 0.01, "and the disc's centre, in world space")
	assert_almost_eq(centre.z, -40.0, 0.01, "and the disc's centre, in world space")

func test_the_deck_ships_moving_and_the_shader_is_told_which_way() -> void:
	# The drift is safe to ship on because the cloud field is EXACTLY periodic and the offset is wrapped at that
	# period in cell space — not because the speed is low. (TIME-driven noise that is not periodic is the trap
	# this project has already been bitten by: unbounded TIME, decaying precision, a pattern that starts crawling
	# hours in.) What a test can pin is that the knobs reach the material.
	var v := _drop(_host())
	v.clouds_enabled = true
	v.cloud_drift = 9.0
	v.cloud_drift_dir = Vector2(0.0, 1.0)
	v.build()
	var mat := _mesh_child(v, "Clouds").get_active_material(0) as ShaderMaterial
	assert_almost_eq(float(mat.get_shader_parameter("drift")), 9.0, 0.001, "the deck must be told its speed")
	var dir: Vector2 = mat.get_shader_parameter("drift_dir")
	assert_almost_eq(dir.y, 1.0, 0.001, "and which way the weather is going")

func test_it_warns_when_the_decks_rim_could_come_into_view() -> void:
	var v := _drop(_host())
	v.clouds_enabled = true
	v.cloud_extent = 100.0
	v.haze_distance = 1400.0
	assert_string_contains(str(v._get_configuration_warnings()), "cloud_extent")

# ------------------------------------------------------------------------------------------------------------
# the haze
# ------------------------------------------------------------------------------------------------------------

func test_the_haze_plane_sits_between_the_roof_and_the_bottom_of_the_drop() -> void:
	var v := _drop(_host())
	var y: float = _mesh_child(v, "HazeFloor").mesh.get_aabb().position.y
	assert_almost_eq(y, -200.0, 0.01, "the plane is haze_floor_depth below the roofline")
	assert_true(y > -500.0, "and above the bottom edge of the facade, or the cut shows")

func test_the_haze_plane_can_be_switched_off() -> void:
	var v := _drop(_host())
	v.haze_floor_enabled = false
	v.build()
	assert_true(_mesh_child(v, "HazeFloor") == null, "haze_floor_enabled off must build no plane")

func test_the_haze_colour_follows_the_levels_fog_when_asked() -> void:
	# The drop has to dissolve into the SAME grey the sky is wearing; matching the fog is how it welds to a level
	# whose palette (or day/night state) this component knows nothing about.
	var host := _host()
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.fog_enabled = true
	env.fog_light_color = Color(0.2, 0.4, 0.6)
	we.environment = env
	we.add_to_group(Groups.WORLD_ENVIRONMENT)
	host.add_child(we)
	var v := _drop(host)
	v.auto_haze_from_fog = true
	v.build()
	var mat := _mesh_child(v, "Facade").get_active_material(0) as ShaderMaterial
	var haze: Color = mat.get_shader_parameter("haze_color")
	assert_almost_eq(haze.r, 0.2, 0.001, "haze red must come from the fog")
	assert_almost_eq(haze.b, 0.6, 0.001, "haze blue must come from the fog")

func test_the_haze_colour_stays_the_export_when_the_level_has_no_fog() -> void:
	var v := _drop(_host())
	v.auto_haze_from_fog = true
	v.haze_color = Color(0.9, 0.1, 0.1)
	v.build()
	var mat := _mesh_child(v, "Facade").get_active_material(0) as ShaderMaterial
	var haze: Color = mat.get_shader_parameter("haze_color")
	assert_almost_eq(haze.r, 0.9, 0.001, "with no fog to read, the authored colour must survive")

# ------------------------------------------------------------------------------------------------------------
# inspector warnings (the designer-facing surface)
# ------------------------------------------------------------------------------------------------------------

func test_it_warns_when_the_haze_plane_would_sit_at_or_below_the_bottom_of_the_drop() -> void:
	var v := _drop(_host())
	v.depth = 100.0
	v.haze_floor_depth = 100.0
	assert_string_contains(str(v._get_configuration_warnings()), "fog plane")

func test_it_warns_when_rotated() -> void:
	var v := _drop(_host())
	v.rotation_degrees = Vector3(0.0, 0.0, 12.0)
	assert_string_contains(str(v._get_configuration_warnings()), "rotated")

func test_it_warns_when_authored_points_cannot_form_an_outline() -> void:
	var v := _drop(_host())
	v.footprint_points = PackedVector2Array([Vector2.ZERO, Vector2.ONE])
	assert_string_contains(str(v._get_configuration_warnings()), "3+ points")

func test_it_warns_when_the_near_ring_is_inside_the_building() -> void:
	var v := _drop(_host(), Vector2(400.0, 400.0))
	v.tower_count = 4
	v.tower_ring_min = 10.0
	v.build()
	assert_string_contains(str(v._get_configuration_warnings()), "tower_ring_min")

func test_it_warns_when_the_fog_does_not_run_out_where_the_city_does() -> void:
	# The mistake behind two separate live-game reports: a fade whose range has nothing to do with how deep the
	# city actually is. Too short and the far half fogs out in one step; too long and nothing ever recedes.
	var v := _drop(_host())
	v.tower_count = 8
	v.tower_ring_max = 2600.0
	v.haze_distance = 400.0
	assert_string_contains(str(v._get_configuration_warnings()), "much shorter than the ring")
	v.haze_distance = 20000.0
	assert_string_contains(str(v._get_configuration_warnings()), "far longer than the city")

func test_the_facade_ships_off() -> void:
	# By request: a wall tracing the level's own outline announces that the level HAS an outline, and from a
	# rooftop you only ever see it edge-on anyway. The drop is sold by the skyline around you.
	var v: Node = VOID.new()
	v.fit_to_level = false
	v.tower_count = 0
	v.auto_haze_from_fog = false
	_host().add_child(v)
	assert_true(_mesh_child(v, "Facade") == null, "facade_enabled must default OFF")

func test_no_neighbour_roof_is_close_enough_to_look_reachable() -> void:
	# A neighbouring roof within jumping (or grappling) distance stops being scenery and becomes a promise the
	# level cannot keep. The near ring is measured wall to wall, so nothing may sit inside `tower_near_gap`.
	var v := _drop(_host(), Vector2(40.0, 60.0))
	v.tower_count = 10
	v.tower_near_count = 3
	v.tower_near_gap = 95.0
	v.build()
	var verts: PackedVector3Array = _tower_walls(v)[Mesh.ARRAY_VERTEX]
	var span := Vector2(20.0, 30.0).length()   # half-diagonal of the 40 x 60 footprint
	var closest := INF
	for p in verts:
		closest = minf(closest, Vector2(p.x, p.z).length())
	assert_true(closest >= span + 95.0,
		"a neighbour wall is %.1f m from the centre; with a %.1f m span and a 95 m gap nothing may be nearer than %.1f" % [closest, span, span + 95.0])

func test_it_warns_when_a_neighbour_is_close_enough_to_look_jumpable() -> void:
	var v := _drop(_host())
	v.tower_near_count = 3
	v.tower_near_gap = 12.0
	assert_string_contains(str(v._get_configuration_warnings()), "tower_near_gap")

func test_the_fog_plane_ships_off() -> void:
	# The reference has no ground and no horizon line — a lit fog floor is a surface, and a surface tells the eye
	# exactly how deep the hole is. A plain instance must build only the facade.
	var v: Node = VOID.new()
	v.fit_to_level = false
	v.tower_count = 0
	v.auto_haze_from_fog = false
	_host().add_child(v)
	assert_true(_mesh_child(v, "HazeFloor") == null, "haze_floor_enabled must default OFF")
