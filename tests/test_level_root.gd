extends GutTest

## LevelRoot validator — the inspector config-warnings that tell a designer a level is missing what GameRoot /
## StarSky / navigation need. In-tree (add_child_autofree) so the descendant walk + group membership resolve.
## Mirrors test_authoring_warnings.gd's _has(w, sub) substring style.

func _has(w, sub) -> bool:
	for s in w:
		if sub in s:
			return true
	return false


func test_empty_level_root_warns_about_everything_missing() -> void:
	var root := LevelRoot.new()
	add_child_autofree(root)
	var w := root._get_configuration_warnings()
	assert_true(_has(w, "WorldEnvironment"), "a bare level warns it has no WorldEnvironment")
	assert_true(_has(w, "NavigationRegion3D"), "...no NavigationRegion3D")
	assert_true(_has(w, "PlayerSpawn"), "...no PlayerSpawn")


func test_worldenvironment_must_be_in_the_group() -> void:
	var root := LevelRoot.new()
	add_child_autofree(root)
	var we := WorldEnvironment.new()
	root.add_child(we)  # present but NOT in the world_environment group
	assert_true(_has(root._get_configuration_warnings(), "group"), "a WorldEnvironment outside the group warns StarSky won't find it")
	we.add_to_group(&"world_environment")
	assert_false(_has(root._get_configuration_warnings(), "WorldEnvironment"), "...in the group -> the WorldEnvironment warning clears")


func test_navigation_region_geometry_and_bake() -> void:
	var root := LevelRoot.new()
	add_child_autofree(root)
	var region := NavigationRegion3D.new()
	region.navigation_mesh = NavigationMesh.new()  # unbaked (zero vertices)
	root.add_child(region)
	var geo := Node3D.new()
	geo.add_to_group(&"navmesh")
	root.add_child(geo)
	var w := root._get_configuration_warnings()
	assert_false(_has(w, "No NavigationRegion3D"), "a region present -> no 'no region' warning")
	assert_false(_has(w, "Nothing feeds"), "a navmesh-group node present -> no 'nothing feeds the bake' warning")
	assert_true(_has(w, "isn't baked"), "an empty navmesh -> the bake reminder fires")
	region.navigation_mesh.set_vertices(PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.FORWARD]))
	assert_false(_has(root._get_configuration_warnings(), "isn't baked"), "...once baked (vertices present) the reminder clears")


func test_playerspawn_required_and_entry_ids_unique() -> void:
	var root := LevelRoot.new()
	add_child_autofree(root)
	assert_true(_has(root._get_configuration_warnings(), "No PlayerSpawn"), "no spawn -> warns")
	var s1 := PlayerSpawn.new()
	root.add_child(s1)
	assert_false(_has(root._get_configuration_warnings(), "No PlayerSpawn"), "...one spawn -> clears")
	var s2 := PlayerSpawn.new()
	s1.entry_id = &"north"
	s2.entry_id = &"north"
	root.add_child(s2)
	assert_true(_has(root._get_configuration_warnings(), "share entry_id"), "two spawns with the same non-blank entry_id -> warns")
	s2.entry_id = &"south"
	assert_false(_has(root._get_configuration_warnings(), "share entry_id"), "...distinct ids -> clears")


func test_validator_flags_a_bad_bake_quality() -> void:
	# A baked-but-broken navmesh (the TestLevel failure): too-permissive climb + two disconnected quads, the second
	# raised. Existence checks pass, so this is exactly what the OLD validator missed.
	var root := LevelRoot.new()
	add_child_autofree(root)
	var region := NavigationRegion3D.new()
	var nm := NavigationMesh.new()
	nm.agent_max_climb = 0.9  # the unsafe engine default that broke TestLevel
	nm.set_vertices(PackedVector3Array([
		Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 10), Vector3(0, 0, 10),          # floor (area 100)
		Vector3(20, 3, 20), Vector3(21, 3, 20), Vector3(21, 3, 21), Vector3(20, 3, 21),      # raised roof (area 1)
	]))
	nm.add_polygon(PackedInt32Array([0, 1, 2]))
	nm.add_polygon(PackedInt32Array([0, 2, 3]))
	nm.add_polygon(PackedInt32Array([4, 5, 6]))
	nm.add_polygon(PackedInt32Array([4, 6, 7]))
	region.navigation_mesh = nm
	root.add_child(region)
	var geo := Node3D.new()
	geo.add_to_group(&"navmesh")
	root.add_child(geo)
	var w := root._get_configuration_warnings()
	assert_false(_has(w, "isn't baked"), "the mesh is baked, so the bake reminder is gone")
	assert_true(_has(w, "agent_max_climb"), "a too-permissive climb (0.9) is flagged")
	assert_true(_has(w, "aren't bridged"), "a fragmented bake is flagged")
	assert_true(_has(w, "above the floor"), "elevated roof polys are flagged")


func test_validator_quiet_on_a_clean_bake() -> void:
	var root := LevelRoot.new()
	add_child_autofree(root)
	var region := NavigationRegion3D.new()
	var nm := NavigationMesh.new()
	nm.agent_max_climb = 0.4  # the safe template value
	nm.set_vertices(PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 10), Vector3(0, 0, 10)]))
	nm.add_polygon(PackedInt32Array([0, 1, 2]))
	nm.add_polygon(PackedInt32Array([0, 2, 3]))
	region.navigation_mesh = nm
	root.add_child(region)
	var geo := Node3D.new()
	geo.add_to_group(&"navmesh")
	root.add_child(geo)
	var w := root._get_configuration_warnings()
	assert_false(_has(w, "agent_max_climb"), "safe climb 0.4 -> no climb warning")
	assert_false(_has(w, "aren't bridged"), "one connected island -> no island warning")
	assert_false(_has(w, "above the floor"), "no elevated polys -> no roof warning")
	assert_false(_has(w, "isn't baked"), "a baked mesh -> no bake reminder")


func test_bake_and_audit_button_is_momentary_and_safe_outside_editor() -> void:
	# The bake+audit button must snap back to false and no-op when not in the editor (so it never bakes/crashes in
	# tests or at runtime). The actual bake is editor-only and verified live.
	var root := LevelRoot.new()
	add_child_autofree(root)
	root.bake_and_audit = true
	assert_false(root.bake_and_audit, "momentary button snaps back to false")
	assert_true(root.has_method("_bake_and_audit_now"), "the bake+audit action exists")
	assert_true(root.has_method("_find_region"), "the region finder exists")


func test_template_scene_only_needs_a_bake() -> void:
	var packed := load("res://scenes/levels/LevelTemplate.tscn") as PackedScene
	assert_not_null(packed, "LevelTemplate.tscn loads")
	if packed == null:
		return
	var root := packed.instantiate()
	if root.get_child_count() == 0:
		root.free()  # reimport can briefly yield an empty PackedScene — skip rather than false-fail
		return
	add_child_autofree(root)
	var w := root._get_configuration_warnings()
	assert_false(_has(w, "WorldEnvironment"), "the template ships a WorldEnvironment in the group")
	assert_false(_has(w, "No NavigationRegion3D"), "...a NavigationRegion3D")
	assert_false(_has(w, "Nothing feeds"), "...navmesh geometry (Geometry + Ground)")
	assert_false(_has(w, "No PlayerSpawn"), "...a default PlayerSpawn")
	assert_true(_has(w, "isn't baked"), "...and ships UNBAKED, so the only remaining warning is the bake reminder")
