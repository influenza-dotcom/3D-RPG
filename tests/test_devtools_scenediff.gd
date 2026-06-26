extends GutTest

## The CYBER SUNDAY Scene Diff tab: the PURE .tscn parse + diff are unit-tested with in-memory scene text; the file
## reads + tree render are editor glue (construct check). No scene is ever instantiated — it's a structural text diff.

const SceneDiff := preload("res://addons/cybersunday_tools/dock_scenediff/scene_diff.gd")
const SceneDiffView := preload("res://addons/cybersunday_tools/dock_scenediff/scene_diff_view.gd")


func test_parse_scene_keys_nodes_by_path() -> void:
	var text := "[gd_scene format=3]\n[ext_resource type=\"Script\" path=\"res://x.gd\" id=\"1\"]\n" \
		+ "[node name=\"Root\" type=\"Node3D\"]\n" \
		+ "[node name=\"Mesh\" type=\"MeshInstance3D\" parent=\".\"]\nvisible = true\n" \
		+ "[node name=\"Box\" type=\"CollisionShape3D\" parent=\"Mesh\"]\n"
	var m := SceneDiff.parse_scene(text)
	assert_true(m.has("."), "the root node is keyed as '.'")
	assert_eq(String(m["."]["type"]), "Node3D", "root type captured")
	assert_true(m.has("Mesh"), "a child of root is keyed by its name")
	assert_eq(String(m["Mesh"]["props"]["visible"]), "true", "a node property line is captured")
	assert_true(m.has("Mesh/Box"), "a grandchild is keyed parent/name")
	assert_eq(String(m["Mesh/Box"]["type"]), "CollisionShape3D", "grandchild type captured")
	assert_false(m.has("res://x.gd"), "ext_resource blocks are NOT modelled as nodes")


func test_diff_scenes_added_removed_changed() -> void:
	var a := SceneDiff.parse_scene("[node name=\"Root\" type=\"Node3D\"]\n[node name=\"Mesh\" type=\"MeshInstance3D\" parent=\".\"]\nvisible = true\n[node name=\"Area\" type=\"Area3D\" parent=\".\"]\n")
	var b := SceneDiff.parse_scene("[node name=\"Root\" type=\"Node3D\"]\n[node name=\"Mesh\" type=\"MeshInstance3D\" parent=\".\"]\nvisible = false\n[node name=\"Light\" type=\"OmniLight3D\" parent=\".\"]\n")
	var d := SceneDiff.diff_scenes(a, b)
	assert_eq(d["added"], ["Light"], "Light is in B only")
	assert_eq(d["removed"], ["Area"], "Area is in A only")
	assert_eq((d["changed"] as Array).size(), 1, "only Mesh changed")
	assert_eq(String(d["changed"][0]["key"]), "Mesh", "the changed node is Mesh")
	assert_true("visible: true -> false" in d["changed"][0]["props_changed"], "the property delta is reported")


func test_diff_flags_type_change_and_identical() -> void:
	var a := SceneDiff.parse_scene("[node name=\"Root\" type=\"Node3D\"]\n[node name=\"N\" type=\"Area3D\" parent=\".\"]\n")
	var b := SceneDiff.parse_scene("[node name=\"Root\" type=\"Node3D\"]\n[node name=\"N\" type=\"StaticBody3D\" parent=\".\"]\n")
	var d := SceneDiff.diff_scenes(a, b)
	assert_eq((d["changed"] as Array).size(), 1, "the retyped node is a change")
	assert_string_contains(String(d["changed"][0]["type_change"]), "Area3D -> StaticBody3D", "the type change is reported")
	var same := SceneDiff.diff_scenes(a, a)
	assert_true(same["added"].is_empty() and same["removed"].is_empty() and same["changed"].is_empty(), "a scene vs itself has no differences")


func test_scene_diff_view_constructs() -> void:
	var v = SceneDiffView.new()
	assert_not_null(v, "the Scene Diff tab constructs (compiles + _init builds UI off-tree)")
	assert_eq(v.name, "Scene Diff")
	v.free()
