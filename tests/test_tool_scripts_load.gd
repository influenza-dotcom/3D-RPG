extends GutTest

## ENTRY-POINT scripts with no runtime caller — the File -> Run EditorScripts (audit_navmesh, bake_funcgodot_navmesh,
## new_level, validate_content), the `-s` SceneTree CLIs (bake_item_icons, __zfight_shots), the kept load-in hitch
## probe and the 2-line @tool root script of scenes/game.tscn — only ever fail the NEXT time a human clicks them: a
## parse regression, a moved res:// path they hard-code, or a renamed helper they consume is otherwise invisible.
## This file pins that contract headless: every script compiles (under GUT load() runs AFTER the autoloads register,
## so a stray `Groups` / `ItemDb` / `NPC` reference is a real check), exposes the hook its runner calls, every
## hard-coded res:// path exists on disk, the helper surface it consumes (NavMeshAudit / ItemScan / ContentValidator
## / BrushZFightClean / icon_render / LevelData) still has that shape, and the PURE helpers inside each script return
## the right thing for concrete inputs. NO tool's _run() / _initialize() is ever executed (new_level writes files,
## bake_funcgodot_navmesh re-bakes the open scene) and the two SceneTree scripts are never instantiated — that would
## hand GUT a second main loop (the test_cyber_bridge idiom). The EditorScripts are never instantiated either —
## headless that is an ENGINE ERROR, which fails a GUT test on its own — so their pure helpers run through the
## source surrogate below (see _tool_surrogate).

const AUDIT_NAVMESH := "res://scripts/tools/audit_navmesh.gd"
const BAKE_FUNCGODOT := "res://scripts/tools/bake_funcgodot_navmesh.gd"
const NEW_LEVEL := "res://scripts/tools/new_level.gd"
const VALIDATE_CONTENT := "res://scripts/tools/validate_content.gd"
const BAKE_ICONS := "res://scripts/tools/bake_item_icons.gd"
const ZFIGHT_SHOTS := "res://scripts/tools/__zfight_shots.gd"
const HITCH_PROBE := "res://scripts/tools/__load_in_hitch_probe.gd"
const HITCH_PROBE_SCENE := "res://scripts/tools/__load_in_hitch_probe.tscn"
const GAME_GD := "res://scenes/game.gd"
const GAME_TSCN := "res://scenes/game.tscn"

const LEVELS_DIR := "res://scenes/levels"
const LEVEL_TEMPLATE := "res://scenes/levels/LevelTemplate.tscn"
const TRENCHBOOM_LEVEL := "res://scenes/levels/trenchboom_test_level.tscn"
const FUNC_GODOT_MAP_SCRIPT := "res://addons/func_godot/src/map/func_godot_map.gd"
const ZFIGHT_CLEAN := "res://scripts/components/brush_zfight_clean.gd"
const ITEM_SCAN := "res://addons/cybersunday_tools/core/item_scan.gd"
const ICON_BAKER := "res://addons/cybersunday_tools/dock_icons/icon_baker.gd"
const ICON_RENDER := "res://addons/cybersunday_tools/dock_icons/icon_render.gd"
const NAVMESH_AUDIT := "res://scripts/tools/navmesh_audit.gd"

## A .tres stores a bake param as a 32-bit float; the GDScript const it is compared against is 64-bit, so the two
## differ in the last bits (0.6 vs 0.60000002384186) and assert_eq on them is a guaranteed red. Tolerance well
## under any meaningful bake change.
const EPS := 0.0001


# ---------------------------------------------------------------------------------------------------------------
# helpers

## Names of the methods a script DEFINES (its own body — none of these scripts chains a base script).
func _methods(script: Script) -> PackedStringArray:
	var out := PackedStringArray()
	for m in script.get_script_method_list():
		out.append(String(m.name))
	return out


## Script constants are invisible to Object.get(); get_script_constant_map() is the engine-native read.
func _consts(script: Script) -> Dictionary:
	var gd := script as GDScript
	return gd.get_script_constant_map() if gd != null else {}


## Index of the node named `node_name` in a PackedScene's SceneState (-1 when absent). Reads the authored .tscn
## WITHOUT instantiating it, so a scene full of Players / NPCs is never brought to life.
func _state_node(state: SceneState, node_name: String) -> int:
	for i in state.get_node_count():
		if String(state.get_node_name(i)) == node_name:
			return i
	return -1


## The authored value of property `prop` on SceneState node `idx` (null when the .tscn doesn't set it).
func _state_prop(state: SceneState, idx: int, prop: String) -> Variant:
	for i in state.get_node_property_count(idx):
		if String(state.get_node_property_name(idx, i)) == prop:
			return state.get_node_property_value(idx, i)
	return null


## The tools' pure helpers are plain INSTANCE methods on an EditorScript — and `EditorScript` is an editor-only
## virtual class, so `load(tool).new()` headless raises "Class 'EditorScript' can only be instantiated by editor."
## (class_db.cpp) + "Can't inherit from a virtual class", and GUT fails a test on any engine error even when every
## assert passes. There is no static / detachable entry to those helpers, so instead of downgrading them to a
## surface-only pin this recompiles the SHIPPED SOURCE verbatim under a RefCounted base: the helper bodies are the
## real ones (a regression in the search or the transform math still fails here), only the base class differs.
## `_run()` is dropped on the way through — it is the one member that reaches for the EditorScript API
## (`get_scene()`, which does not exist off RefCounted), and running it is forbidden anyway (new_level WRITES
## files, bake_funcgodot_navmesh re-bakes the open scene). If a helper ever needs the editor API itself, the
## recompile fails loudly here rather than silently pinning nothing.
func _tool_surrogate(path: String) -> Object:
	var src := FileAccess.get_file_as_string(path)
	assert_false(src.is_empty(), "%s is readable on disk (the surrogate recompiles its source)" % path)
	if src.is_empty():
		return null
	var out := PackedStringArray()
	var in_run := false
	for raw in src.split("\n"):
		var line := String(raw)
		if in_run:
			if line.strip_edges().is_empty() or line.begins_with("\t"):
				continue  # still inside _run's indented body
			in_run = false   # a column-0 line ends the function
		if line.begins_with("func _run("):
			in_run = true
			continue
		if line.begins_with("extends "):
			line = "extends RefCounted"
		out.append(line)
	var gd := GDScript.new()
	gd.source_code = "\n".join(out)
	var err := gd.reload()
	assert_eq(err, OK, "%s recompiles under a RefCounted base — a helper that now needs the EditorScript API must be pinned another way" % path)
	if err != OK:
		return null
	return gd.new()


# ---------------------------------------------------------------------------------------------------------------
# (a) + (b): every script compiles and exposes the hook its runner calls

func test_editor_scripts_compile_as_tool_editorscripts_with_run() -> void:
	for path in [AUDIT_NAVMESH, BAKE_FUNCGODOT, NEW_LEVEL, VALIDATE_CONTENT]:
		var script: Script = load(path)
		assert_not_null(script, "%s must compile (a parse error here only shows on File -> Run)" % path)
		if script == null:
			continue
		assert_true(script.is_tool(), "%s is @tool — File -> Run refuses a non-tool EditorScript" % path)
		assert_eq(script.get_instance_base_type(), &"EditorScript", "%s extends EditorScript (the File -> Run contract)" % path)
		assert_true(_methods(script).has("_run"), "%s defines _run(), the method File -> Run invokes" % path)


func test_scenetree_scripts_compile_with_their_entry_hooks() -> void:
	var icons: Script = load(BAKE_ICONS)
	assert_not_null(icons, "bake_item_icons.gd must compile")
	if icons != null:
		assert_eq(icons.get_instance_base_type(), &"SceneTree", "bake_item_icons is a `-s` SceneTree script")
		var m := _methods(icons)
		assert_true(m.has("_initialize"), "bake_item_icons enters via SceneTree._initialize")
		assert_true(m.has("_run"), "bake_item_icons' _initialize fires the _run coroutine")
	var shots: Script = load(ZFIGHT_SHOTS)
	assert_not_null(shots, "__zfight_shots.gd must compile")
	if shots != null:
		assert_eq(shots.get_instance_base_type(), &"SceneTree", "__zfight_shots is a `-s` SceneTree script")
		var m := _methods(shots)
		assert_true(m.has("_process"), "__zfight_shots drives itself from SceneTree._process (nodes must be in-tree before the census)")
		assert_true(m.has("_build"), "__zfight_shots builds the rig in _build on the first _process frame")
		var settle = _consts(shots).get("SETTLE")
		assert_true(settle is int and int(settle) >= 1,
			"SETTLE must be a whole number of frames >= 1 — the probe rewinds _frame to SETTLE - 1 between shots, so 0 would park it on frame -1")


func test_hitch_probe_compiles_and_its_scene_wraps_it() -> void:
	var probe: Script = load(HITCH_PROBE)
	assert_not_null(probe, "__load_in_hitch_probe.gd must compile (it references NPC + EffectPrewarmer, both resolved after autoloads)")
	if probe == null:
		return
	assert_eq(probe.get_instance_base_type(), &"Node", "the probe is a plain Node the .tscn roots")
	var m := _methods(probe)
	for hook in ["_ready", "_process", "_on_node_added", "_run", "_collect_links", "_drift_report", "_pipeline_deltas", "_dump"]:
		assert_true(m.has(hook), "the probe defines %s()" % hook)
	assert_true(ResourceLoader.exists(HITCH_PROBE_SCENE), "the probe's launcher scene exists (the documented run line names it)")
	var ps := load(HITCH_PROBE_SCENE) as PackedScene
	assert_not_null(ps, "the launcher scene loads")
	if ps == null:
		return
	var st := ps.get_state()
	assert_eq(String(st.get_node_name(0)), "LoadInHitchProbe", "the root is named LoadInHitchProbe — _process skips the swap frame by that name")
	var scr = _state_prop(st, 0, "script")
	assert_true(scr is Script and (scr as Script).resource_path == HITCH_PROBE, "the launcher root carries the probe script")


func test_game_gd_is_the_tool_root_script_of_game_tscn() -> void:
	var script: Script = load(GAME_GD)
	assert_not_null(script, "scenes/game.gd must compile")
	if script == null:
		return
	assert_true(script.is_tool(), "game.gd is @tool (the editor runs it on the open scene)")
	assert_eq(script.get_instance_base_type(), &"Node3D", "game.gd extends Node3D, the type of game.tscn's root")
	var ps := load(GAME_TSCN) as PackedScene
	assert_not_null(ps, "game.tscn loads")
	if ps == null:
		return
	var st := ps.get_state()
	var scr = _state_prop(st, 0, "script")
	assert_true(scr is Script and (scr as Script).resource_path == GAME_GD, "game.tscn's root node is scripted by scenes/game.gd")
	assert_eq(String(st.get_node_type(0)), "Node3D", "game.tscn's root is a Node3D (matches game.gd's base)")


# ---------------------------------------------------------------------------------------------------------------
# audit_navmesh.gd — the File -> Run navmesh health report

func test_audit_navmesh_level_scan_finds_every_level_scene() -> void:
	assert_true(DirAccess.dir_exists_absolute(LEVELS_DIR), "the hard-coded scenes/levels folder exists")
	var tool := _tool_surrogate(AUDIT_NAVMESH)
	if tool == null:
		return
	var found: Array = tool._all_level_scenes()
	assert_gt(found.size(), 0, "the scan finds at least one level scene")
	var expected := 0
	for f in DirAccess.get_files_at(LEVELS_DIR):
		if String(f).ends_with(".tscn"):
			expected += 1
	assert_eq(found.size(), expected, "the scan lists exactly the .tscn files in scenes/levels (no sub-folders, no .tres)")
	for p in found:
		assert_true(String(p).begins_with("res://scenes/levels/") and String(p).ends_with(".tscn"), "%s is a res:// level scene path" % p)
		assert_true(ResourceLoader.exists(String(p)), "%s exists on disk" % p)
	assert_true(found.has(LEVEL_TEMPLATE), "LevelTemplate.tscn is among the scanned levels")
	assert_eq(_consts(load(AUDIT_NAVMESH)).get("LEVELS"), [], "LEVELS ships EMPTY so a File -> Run audits every level, not a stale hand-list")
	tool = null


func test_audit_navmesh_offtree_world_transform_composes_up_the_chain() -> void:
	var tool := _tool_surrogate(AUDIT_NAVMESH)
	if tool == null:
		return
	# Off-tree on purpose: the helper exists BECAUSE global_transform errors off-tree; it must only read .transform.
	var root := Node.new()
	var a := Node3D.new()
	a.position = Vector3(1, 0, 0)
	var b := Node3D.new()
	b.position = Vector3(0, 2, 0)
	var c := Node3D.new()
	c.position = Vector3(0, 0, 3)
	root.add_child(a)
	a.add_child(b)
	b.add_child(c)
	var t: Transform3D = tool._global_xform_offtree(c)
	assert_eq(t.origin, Vector3(1, 2, 3), "the composed origin sums every Node3D ancestor's local offset")
	assert_eq(tool._global_xform_offtree(a).origin, Vector3(1, 0, 0), "the chain stops at the first non-Node3D ancestor (the plain root)")
	root.free()
	tool = null


func test_audit_navmesh_links_land_in_region_local_space() -> void:
	var tool := _tool_surrogate(AUDIT_NAVMESH)
	if tool == null:
		return
	var root := Node3D.new()
	var region := NavigationRegion3D.new()
	region.position = Vector3(10, 0, 0)
	root.add_child(region)
	var link := NavigationLink3D.new()
	link.position = Vector3(0, 0, 5)
	link.start_position = Vector3.ZERO
	link.end_position = Vector3(1, 0, 0)
	link.bidirectional = false
	root.add_child(link)
	var off := NavigationLink3D.new()
	off.enabled = false
	root.add_child(off)
	var nested := NavigationRegion3D.new()
	link.add_child(nested)
	var regions: Array[NavigationRegion3D] = []
	tool._collect(root, regions)
	assert_eq(regions.size(), 2, "_collect finds every NavigationRegion3D, nested ones included")
	var links: Array[NavigationLink3D] = []
	tool._collect_links(root, links)
	assert_eq(links.size(), 1, "_collect_links skips a DISABLED link (it can't bridge islands)")
	var local: Array = tool._links_local(region, links)
	assert_eq(local.size(), 1, "one {a,b,bidirectional} entry per enabled link")
	if local.size() == 1:
		assert_eq(local[0].a, Vector3(-10, 0, 5), "the link's start lands in the region's LOCAL (navmesh) space")
		assert_eq(local[0].b, Vector3(-9, 0, 5), "the link's end lands in the region's LOCAL (navmesh) space")
		assert_false(local[0].bidirectional, "the link's direction flag rides along for the reachability verdict")
	root.free()
	tool = null


func test_audit_navmesh_consumes_navmesh_audit_report_keys() -> void:
	var audit: Script = load(NAVMESH_AUDIT)
	assert_not_null(audit, "navmesh_audit.gd (the analysis the tool prints) compiles")
	if audit == null:
		return
	var m := _methods(audit)
	assert_true(m.has("analyze") and m.has("reachability"), "NavMeshAudit still offers analyze() + reachability(), the two calls _audit makes")
	var rep: Dictionary = NavMeshAudit.analyze(NavigationMesh.new())
	for key in ["ok", "poly_count", "vertex_count", "islands", "floor_y", "total_area", "warnings", "settings"]:
		assert_true(rep.has(key), "analyze() reports `%s` (the audit line formats it)" % key)
	for key in ["agent_max_climb", "agent_max_slope", "agent_radius"]:
		assert_true((rep.get("settings", {}) as Dictionary).has(key), "analyze().settings carries `%s` (the audit's settings suffix)" % key)
	assert_false(rep.ok, "an UNBAKED (0-poly) navmesh reports not-ok")
	var reach: Dictionary = NavMeshAudit.reachability(NavigationMesh.new(), [])
	for key in ["ok", "effective_islands", "warnings"]:
		assert_true(reach.has(key), "reachability() reports `%s` (the audit line formats it)" % key)


# ---------------------------------------------------------------------------------------------------------------
# bake_funcgodot_navmesh.gd — wires a TrenchBroom level into the `navmesh` group and bakes with the project params

func test_bake_funcgodot_params_match_level_template_navmesh() -> void:
	var consts := _consts(load(BAKE_FUNCGODOT))
	var ps := load(LEVEL_TEMPLATE) as PackedScene
	assert_not_null(ps, "LevelTemplate.tscn (the declared lockstep source) loads")
	if ps == null:
		return
	var st := ps.get_state()
	var idx := _state_node(st, "NavigationRegion3D")
	assert_gte(idx, 0, "LevelTemplate has a NavigationRegion3D")
	if idx < 0:
		return
	var nm := _state_prop(st, idx, "navigation_mesh") as NavigationMesh
	assert_not_null(nm, "the template region carries an authored NavigationMesh")
	if nm == null:
		return
	# The comment block promises "genuine lockstep" and records that this list drifted once already.
	assert_almost_eq(consts.get("AGENT_RADIUS"), nm.agent_radius, EPS, "AGENT_RADIUS matches LevelTemplate")
	assert_almost_eq(consts.get("AGENT_HEIGHT"), nm.agent_height, EPS, "AGENT_HEIGHT matches LevelTemplate")
	assert_almost_eq(consts.get("AGENT_MAX_CLIMB"), nm.agent_max_climb, EPS, "AGENT_MAX_CLIMB matches LevelTemplate")
	assert_almost_eq(consts.get("AGENT_MAX_SLOPE"), nm.agent_max_slope, EPS, "AGENT_MAX_SLOPE matches LevelTemplate")
	assert_almost_eq(consts.get("CELL_SIZE"), nm.cell_size, EPS, "CELL_SIZE matches LevelTemplate")
	assert_almost_eq(consts.get("CELL_HEIGHT"), nm.cell_height, EPS, "CELL_HEIGHT matches LevelTemplate")
	assert_almost_eq(consts.get("REGION_MIN_SIZE"), nm.region_min_size, EPS, "REGION_MIN_SIZE matches LevelTemplate")
	assert_almost_eq(consts.get("EDGE_MAX_ERROR"), nm.edge_max_error, EPS, "EDGE_MAX_ERROR matches LevelTemplate")
	assert_eq(consts.get("FILTER_LOW_HANGING_OBSTACLES"), nm.filter_low_hanging_obstacles, "FILTER_LOW_HANGING_OBSTACLES matches LevelTemplate (the param that drifted once)")
	assert_eq(nm.geometry_source_geometry_mode, NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN, "the template bakes from a GROUP with children, as the tool stamps")
	assert_eq(nm.geometry_parsed_geometry_type, NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS, "the template parses STATIC COLLIDERS, as the tool stamps")
	assert_eq(nm.geometry_source_group_name, Groups.NAVMESH, "the template's bake group is Groups.NAVMESH, the group the tool adds the map to")
	assert_eq(Groups.NAVMESH, &"navmesh", "Groups.NAVMESH is the literal `navmesh` group the tool's docs name")


func test_bake_funcgodot_first_of_type_is_depth_first() -> void:
	var tool := _tool_surrogate(BAKE_FUNCGODOT)
	if tool == null:
		return
	var root := Node.new()
	var branch := Node3D.new()
	var deep := NavigationRegion3D.new()
	var shallow := NavigationRegion3D.new()
	root.add_child(branch)
	branch.add_child(deep)
	root.add_child(shallow)
	assert_eq(tool._first_of_type(root, "NavigationRegion3D"), deep, "depth-first: the region inside the first branch wins over a later sibling")
	assert_eq(tool._first_of_type(deep, "NavigationRegion3D"), deep, "a node that IS the type returns itself")
	assert_null(tool._first_of_type(root, "Camera3D"), "no match -> null (the tool then push_errors instead of baking)")
	root.free()
	tool = null


func test_bake_funcgodot_finds_the_map_by_script_then_by_name() -> void:
	var tool := _tool_surrogate(BAKE_FUNCGODOT)
	if tool == null:
		return
	assert_true(ResourceLoader.exists(FUNC_GODOT_MAP_SCRIPT), "func_godot_map.gd (the script-path match) still exists at its addon path")
	var root := Node.new()
	var plain := Node3D.new()
	plain.name = "Geometry"
	root.add_child(plain)
	assert_null(tool._find_funcgodot_map(root), "no FuncGodotMap anywhere -> null")
	var by_name := Node3D.new()
	by_name.name = "FuncGodotMap"
	plain.add_child(by_name)
	assert_eq(tool._find_funcgodot_map(root), by_name, "a node literally named FuncGodotMap is found (nested, no script)")
	var renamed := Node3D.new()
	renamed.name = "MyMap"
	renamed.set_script(load(FUNC_GODOT_MAP_SCRIPT))  # inert to attach (test_brush_zfight_clean relies on the same)
	root.add_child(renamed)
	root.move_child(renamed, 0)
	assert_eq(tool._find_funcgodot_map(root), renamed, "a RENAMED node carrying func_godot_map.gd still matches (the script-path branch, not the name)")
	root.free()
	tool = null


# ---------------------------------------------------------------------------------------------------------------
# new_level.gd — clones LevelTemplate into a new level + LevelData

func test_new_level_ships_placeholder_name_and_its_paths_exist() -> void:
	var consts := _consts(load(NEW_LEVEL))
	assert_eq(consts.get("NEW_LEVEL_NAME"), "MyLevel", "the committed NEW_LEVEL_NAME is the placeholder — File -> Run on a fresh checkout warns instead of WRITING files")
	assert_eq(consts.get("DISPLAY_NAME"), "", "DISPLAY_NAME ships blank (falls back to the level name)")
	assert_eq(consts.get("TEMPLATE_SCENE"), LEVEL_TEMPLATE, "the template path is LevelTemplate.tscn")
	assert_true(ResourceLoader.exists(LEVEL_TEMPLATE), "the template scene exists — a moved template breaks the tool with a push_error")
	assert_true(DirAccess.dir_exists_absolute("res://resources/levels"), "resources/levels (the .tres output folder) exists")
	assert_true(DirAccess.dir_exists_absolute(LEVELS_DIR), "scenes/levels (the .tscn output folder) exists")
	var data := LevelData.new()
	assert_true("scene" in data and "display_name" in data, "LevelData exposes `scene` + `display_name`, the two fields the tool writes")
	data = null


# ---------------------------------------------------------------------------------------------------------------
# validate_content.gd — File -> Run content sanity report

func test_validate_content_consumes_item_scan_and_content_validator() -> void:
	assert_true(ResourceLoader.exists(ITEM_SCAN), "item_scan.gd (the preloaded folder scan) exists at its addon path")
	var scan: Script = load(ITEM_SCAN)
	assert_not_null(scan, "item_scan.gd compiles")
	if scan == null:
		return
	assert_true(_methods(scan).has("scan_report"), "ItemScan.scan_report() is the call the tool makes")
	var empty: Dictionary = scan.scan_report("res://this/folder/does/not/exist")
	assert_true(empty.has("items") and empty.has("skipped"), "scan_report returns {items, skipped} — the two keys the tool reads")
	assert_true(empty["items"] is Array and (empty["items"] as Array).is_empty(), "a missing folder scans to an empty items Array")
	assert_true(empty["skipped"] is PackedStringArray and (empty["skipped"] as PackedStringArray).is_empty(), "a missing folder scans to an empty skipped PackedStringArray")
	var real: Dictionary = scan.scan_report()
	assert_gt((real["items"] as Array).size(), 0, "the default scan (resources/items) finds authored items — otherwise the checks run over nothing")
	for it in real["items"]:
		assert_true(it is Item, "every scanned entry is an Item")
	var problems = ContentValidator.run([])
	assert_true(problems is PackedStringArray, "ContentValidator.run(items) returns the PackedStringArray the tool prints line by line")


# ---------------------------------------------------------------------------------------------------------------
# bake_item_icons.gd — CLI icon baker

func test_bake_item_icons_paths_and_render_math() -> void:
	for p in [ICON_BAKER, ICON_RENDER]:
		assert_true(ResourceLoader.exists(p), "%s exists (the baker load()s it lazily by path)" % p)
	assert_true(DirAccess.dir_exists_absolute("res://resources/items"), "resources/items (the scanned input folder) exists")
	assert_true(DirAccess.dir_exists_absolute("res://resources/icons"), "resources/icons (the PNG output folder) exists")
	var baker: Script = load(ICON_BAKER)
	var render: Script = load(ICON_RENDER)
	assert_not_null(baker, "icon_baker.gd compiles")
	assert_not_null(render, "icon_render.gd compiles")
	if baker == null or render == null:
		return
	var cell = _consts(baker).get("CELL")
	assert_true(cell is int and int(cell) > 0, "Baker.CELL (the px-per-grid-cell both the Icons tab and this CLI bake at) is a positive int")
	if not (cell is int and int(cell) > 0):
		return
	assert_eq(render.pixel_size(2, 1, cell), Vector2i(2 * cell, cell), "a 2x1 item bakes an icon two cells wide and one cell tall")
	assert_eq(render.pixel_size(1, 3, cell), Vector2i(cell, 3 * cell), "width and height are not swapped: a 1x3 item bakes a tall icon")
	assert_eq(render.pixel_size(0, 0, cell), Vector2i(cell, cell), "a degenerate 0x0 footprint floors to one cell rather than a 0 px image")
	assert_eq(baker.save_png(null, "res://resources/icons/_never_written.png"), ERR_INVALID_DATA, "save_png(null) refuses without touching disk")
	assert_false(FileAccess.file_exists("res://resources/icons/_never_written.png"), "the refused save wrote nothing")
	var rig = baker.new()
	assert_true(rig.has_method("bake_item"), "the baker instance offers bake_item(item, px, host)")
	rig = null
	var item := Item.new()
	assert_true("id" in item and "grid_width" in item and "grid_height" in item, "Item exposes id / grid_width / grid_height, the fields the baker reads")
	item = null


# ---------------------------------------------------------------------------------------------------------------
# __zfight_shots.gd — before/after A/B of BrushZFightClean

func test_zfight_shots_level_and_cleaner_contract() -> void:
	assert_true(ResourceLoader.exists(TRENCHBOOM_LEVEL), "the live level the probe loads exists")
	var ps := load(TRENCHBOOM_LEVEL) as PackedScene
	assert_not_null(ps, "trenchboom_test_level.tscn loads")
	if ps != null:
		assert_gte(_state_node(ps.get_state(), "FuncGodotMap"), 0, "the level authors a node named FuncGodotMap — the probe find_child()s it by that name")
	assert_true(ResourceLoader.exists(ZFIGHT_CLEAN), "brush_zfight_clean.gd exists at the path the probe load()s")
	var cleaner_script: Script = load(ZFIGHT_CLEAN)
	assert_not_null(cleaner_script, "brush_zfight_clean.gd compiles")
	if cleaner_script == null:
		return
	var cleaner: Node = cleaner_script.new()
	autofree(cleaner)
	assert_true(cleaner.has_method("overlap_report") and cleaner.has_method("clean"), "the cleaner offers overlap_report() + clean(), the probe's two calls")
	var holder := Node3D.new()
	add_child_autofree(holder)  # in-tree: the census reads global_transform
	var before: Dictionary = cleaner.overlap_report(holder, 6)
	assert_eq(before.get("pairs"), 0, "an empty holder censuses 0 pairs")
	assert_eq(before.get("area_m2"), 0.0, "an empty holder censuses 0 m2")
	assert_true(before.has("top") and (before["top"] as Array).is_empty(), "top_n > 0 adds a `top` list (empty here) — the list the probe parks cameras over")
	var after: Dictionary = cleaner.clean(holder)
	for key in ["pairs", "tris_clipped", "ms"]:
		assert_true(after.has(key), "clean() reports `%s` (the probe's tally line formats it)" % key)


# ---------------------------------------------------------------------------------------------------------------
# __load_in_hitch_probe.gd — the kept load-in hitch diagnostic

## The run tag the dump test writes under, so its JSON can never collide with a real probe run's file.
const HITCH_DUMP_TAG := "gut_tool_scripts_load"
const HITCH_DUMP_PATH := "user://load_in_hitch_gut_tool_scripts_load.json"


func after_each() -> void:
	if FileAccess.file_exists(HITCH_DUMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(HITCH_DUMP_PATH))


func test_hitch_probe_knobs_are_coherent() -> void:
	var consts := _consts(load(HITCH_PROBE))
	assert_eq(consts.get("GAME"), GAME_TSCN, "the probe boots the REAL game.tscn")
	assert_true(ResourceLoader.exists(GAME_TSCN), "game.tscn exists (the threaded load target)")
	assert_gt(float(consts.get("WINDOW_SEC", 0.0)), 0.0,
		"the recording window must be positive — at 0 _process stops and dumps on the first recorded frame")
	assert_gt(float(consts.get("PRINT_FLOOR_MS", 0.0)), 1000.0 / 60.0,
		"the print floor must sit above one 60 Hz frame, or every ordinary frame prints and the hitches drown")
	var monitors: Array = consts.get("PIPE_MONITORS", [])
	var names: Array = consts.get("PIPE_NAMES", [])
	assert_gt(monitors.size(), 0, "at least one pipeline-compilation monitor is sampled")
	assert_eq(names.size(), monitors.size(), "PIPE_NAMES labels every PIPE_MONITORS entry (they are indexed together)")
	var probe: Node = load(HITCH_PROBE).new()  # OFF-tree on purpose: _ready resizes the window + hooks the tree
	assert_eq(probe._pipe_prev.size(), monitors.size(), "the previous-sample array covers every monitor (_pipeline_deltas indexes it per monitor)")
	probe.free()


func test_hitch_probe_dump_writes_the_recorded_frames_to_its_run_tagged_json() -> void:
	# The probe's whole output contract: `user://load_in_hitch_<tag>.json` holding the run tag, the --no-* flags and
	# every recorded frame. Driven with a hand-filled frame list (no scene swap, no window) under a test-only tag.
	var probe: Node = load(HITCH_PROBE).new()
	probe._run_tag = HITCH_DUMP_TAG
	probe._flags = PackedStringArray(["navlinks"])
	probe._frames = [{"t": 0.1, "dt": 35.0}, {"t": 0.2, "dt": 5.0}, {"t": 0.7, "dt": 8.0}]
	probe._dump()
	probe.free()
	assert_true(FileAccess.file_exists(HITCH_DUMP_PATH), "_dump writes user://load_in_hitch_<run tag>.json")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(HITCH_DUMP_PATH))
	assert_true(parsed is Dictionary, "the dump is one JSON object")
	if not parsed is Dictionary:
		return
	var dump: Dictionary = parsed
	assert_eq(String(dump.get("run", "")), HITCH_DUMP_TAG, "the dump records which run it was")
	assert_eq(dump.get("flags", []), ["navlinks"], "the dump records the --no-* flags the run was made with")
	var frames: Array = dump.get("frames", [])
	assert_eq(frames.size(), 3, "every recorded frame is written, not just the ones over the print floor")
	if frames.size() == 3:
		assert_almost_eq(float(frames[0].get("dt", 0.0)), 35.0, 0.001, "frames keep their recorded durations, in order")
		assert_almost_eq(float(frames[2].get("t", 0.0)), 0.7, 0.001, "frames keep their recorded timestamps, in order")


func test_hitch_probe_node_added_tallies_every_node_but_caps_the_names() -> void:
	var probe: Node = load(HITCH_PROBE).new()
	var born: Array[Node] = []
	for i in 20:
		var n := Node.new()
		n.name = "Born%d" % i
		born.append(n)
		probe._on_node_added(n)
	assert_eq(probe._added_count, 20, "every node born this frame is counted")
	assert_eq(probe._added.size(), 16, "only the first 16 names are kept (the print line stays readable)")
	assert_eq(probe._added[0], "Node:Born0", "names are recorded as Class:name")
	for n in born:
		n.free()
	probe.free()


func test_hitch_probe_navlinks_flag_disables_auto_project() -> void:
	var probe: Node = load(HITCH_PROBE).new()
	var link := NavLink.new()  # off-tree: no _ready, so no projection is scheduled
	assert_true(link.auto_project, "NavLink auto-projects by default (the burst the probe measures)")
	probe._on_node_added(link)
	assert_true(link.auto_project, "without --no-navlinks the probe leaves auto_project alone")
	probe._flags = PackedStringArray(["navlinks"])
	probe._on_node_added(link)
	assert_false(link.auto_project, "--no-navlinks flips auto_project off on every NavigationLink3D as it is born")
	assert_eq(probe._added_count, 2, "both births were tallied")
	link.free()
	probe.free()


func test_hitch_probe_pipeline_deltas_label_each_monitor_then_go_quiet() -> void:
	# Prime the previous samples so monitor i reads exactly i + 1 compilations since the last read: each delta must
	# come out under ITS monitor's label, in monitor order, and the read must re-baseline so the next one is quiet.
	var probe: Node = load(HITCH_PROBE).new()
	var consts := _consts(load(HITCH_PROBE))
	var monitors: Array = consts.get("PIPE_MONITORS", [])
	var names: Array = consts.get("PIPE_NAMES", [])
	var expected := PackedStringArray()
	for i in monitors.size():
		probe._pipe_prev[i] = Performance.get_monitor(monitors[i]) - float(i + 1)
		expected.append("%s+%d" % [names[i], i + 1])
	assert_eq(probe._pipeline_deltas(), ",".join(expected),
		"every monitor that moved reports under its own label with its own delta, comma-joined in monitor order")
	assert_eq(probe._pipeline_deltas(), "", "no pipeline compiled between two back-to-back reads -> empty string (the print gate)")
	probe.free()


func test_hitch_probe_collects_links_and_their_authored_endpoints() -> void:
	var probe: Node = load(HITCH_PROBE).new()
	var lvl := Node3D.new()
	var branch := Node3D.new()
	lvl.add_child(branch)
	var a := NavLink.new()
	a.start_position = Vector3(1, 0, 0)
	a.end_position = Vector3(2, 0, 0)
	branch.add_child(a)
	var b := NavLink.new()
	b.start_position = Vector3(0, 0, 3)
	b.end_position = Vector3(0, 0, 4)
	lvl.add_child(b)
	lvl.add_child(Node3D.new())
	probe._collect_links(lvl)
	assert_eq(probe._links.size(), 2, "every NavigationLink3D under the level is collected, nested or not")
	assert_eq(probe._authored.size(), 2, "one authored [start, end] pair per link")
	assert_eq(probe._authored[0], [Vector3(1, 0, 0), Vector3(2, 0, 0)], "the authored endpoints are snapshotted at collection time (drift is measured against them)")
	a.end_position = Vector3(2, 0.5, 0)  # simulate a projection move; the report only prints, so this pins it runs clean
	probe._drift_report()
	lvl.free()
	probe.free()


# new_worldspace.gd — scaffolds a streamed worldspace (persistent scene + a grid of baked chunks + LevelData)

func test_new_worldspace_is_a_run_tool_that_ships_its_placeholder_name() -> void:
	const NEW_WORLDSPACE := "res://scripts/tools/new_worldspace.gd"
	var script: Script = load(NEW_WORLDSPACE)
	assert_not_null(script, "new_worldspace.gd must compile (a parse error here only shows on File -> Run)")
	if script == null:
		return
	assert_true(script.is_tool(), "new_worldspace.gd is @tool — File -> Run refuses a non-tool EditorScript")
	assert_eq(script.get_instance_base_type(), &"EditorScript", "new_worldspace.gd extends EditorScript")
	assert_true(_methods(script).has("_run"), "new_worldspace.gd defines _run()")
	var consts := _consts(script)
	assert_eq(consts.get("WORLD_NAME"), "MyWorld", "the committed WORLD_NAME is the placeholder — File -> Run on a fresh checkout warns instead of WRITING a world")
	var builder: Script = consts.get("Builder")
	assert_not_null(builder, "the tool drives scripts/world/worldspace_builder.gd")
	if builder != null:
		assert_true(ResourceLoader.exists(String(_consts(builder).get("TEMPLATE_SCENE", ""))), "the builder's persistent-layer template exists")
