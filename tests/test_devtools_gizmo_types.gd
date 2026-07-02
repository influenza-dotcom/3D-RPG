extends GutTest

## PL3: pin the gizmo plugin's is-Type membership (GizmoTypes) against silent drift. A `node is X` case added to the
## plugin's _redraw without registering X in GIZMO_CLASS_NAMES means the gizmo never fires for X (is_gizmo_target
## false) and that _redraw branch is dead. Runs headless: GizmoTypes is a plain RefCounted (not the editor gizmo
## plugin), and the drift check reads the plugin's TEXT (never constructs the EditorNode3DGizmoPlugin, unavailable headless).

const GizmoTypes := preload("res://addons/cybersunday_tools/gizmos/gizmo_types.gd")
const PLUGIN_SRC := "res://addons/cybersunday_tools/gizmos/cybersunday_gizmo_plugin.gd"


func test_gizmo_class_names_count_and_unique() -> void:
	assert_eq(GizmoTypes.GIZMO_CLASS_NAMES.size(), 17, "the gizmo membership list should hold the 17 visualized types")
	var seen := {}
	for n in GizmoTypes.GIZMO_CLASS_NAMES:
		assert_false(seen.has(String(n)), "duplicate gizmo class name '%s'" % n)
		seen[String(n)] = true


func test_redraw_cases_are_all_registered() -> void:
	# Every `node is X` the plugin checks (in _redraw + the handle methods) must be a registered gizmo type, or the
	# gizmo would never fire for X and that branch would be dead. Source-scan keeps the two in sync without drawing.
	var src := FileAccess.get_file_as_string(PLUGIN_SRC)
	assert_ne(src, "", "the gizmo plugin source should be readable")
	var registered := {}
	for n in GizmoTypes.GIZMO_CLASS_NAMES:
		registered[String(n)] = true
	var re := RegEx.new()
	re.compile("node is (\\w+)")
	var found := 0
	for m in re.search_all(src):
		var cn := m.get_string(1)
		found += 1
		assert_true(registered.has(cn), "the plugin checks `node is %s` but it's not in GizmoTypes.GIZMO_CLASS_NAMES (the gizmo would never fire for it)" % cn)
	assert_gt(found, 0, "the source-scan should find the `node is X` gizmo cases")


func test_is_gizmo_target_positive_and_negative() -> void:
	# Spot-check the predicate on real instances (.new() runs only _init — safe off-tree for these spatial nodes).
	var tv := TriggerVolume.new()
	assert_true(GizmoTypes.is_gizmo_target(tv), "a TriggerVolume is a gizmo target")
	tv.free()
	var wm := WorldMarker.new()
	assert_true(GizmoTypes.is_gizmo_target(wm), "a WorldMarker is a gizmo target")
	wm.free()
	var plain := Node3D.new()
	assert_false(GizmoTypes.is_gizmo_target(plain), "a plain Node3D is NOT a gizmo target")
	plain.free()
