extends GutTest

## The VIEW command family (scripts/components/debug_actions_world_view.gd: `inspect`, `navdebug`, `perf`,
## `wireframe`/`overdraw`/`unshaded`, `hud`, `dither`, `dof`, `sway`, `lens`), split out of debug_actions_world.gd
## on 2026-09-11. Pins (1) the static surface the dispatcher routes into (source scan, test_debug_commands.gd's
## approach) and the registry<->family verb parity for `dof` / `sway` by DRIVING each verb against a throwaway
## GunPose / Camera3D — the two commands dispatch through a table lookup and a nested match, so a flat match-arm
## scan reads live verbs as dead, (2) the pure helpers (`_grouped`, `screenshot_stamp`, the HUD path/name
## readouts) with concrete inputs, (3) the "authored mirror" consts (DOF_AUTHORED, SWAY_AUTHORED, LENS_AUTHORED,
## SHADER_DEFAULT_BAYER_ORDER, GRID_TO_BAYER_ORDER) against the files they claim to mirror — the drift each comment
## calls "cosmetic" is a wrong `reset` target, and (4) that every command degrades to ONE honest line off-scene.

const VIEW_PATH := "res://scripts/components/debug_actions_world_view.gd"
const WORLD_PATH := "res://scripts/components/debug_actions_world.gd"
const Commands := preload("res://scripts/components/debug_commands.gd")
const View := preload("res://scripts/components/debug_actions_world_view.gd")
const Common := preload("res://scripts/components/debug_actions_world_common.gd")

const CAMERA_RIG := "res://scenes/player/camera_rig.tscn"
const GUN_POSE := "res://scripts/effects/gun_pose.gd"
const CAMERA_SETTINGS_GD := "res://resources/tuning/CameraSettings.gd"
const CAMERA_SETTINGS_TRES := "res://resources/tuning/CameraSettings.tres"
const POST_SHADER := "res://resources/shaders/post_process.gdshader"


func _static_names(script: GDScript) -> Dictionary:
	var out := {}
	for m in script.get_script_method_list():
		out[String(m["name"])] = true
	return out


## Every `match` arm inside one static, at ANY indent depth. The depth matters: `_cmd_sway`'s match is NESTED
## one level inside an `else:`, so a fixed two-tab scan reads its arms as absent. Arm lines are the only lines in
## these bodies that BEGIN with a quote, so anchoring on `\n\t+"` cannot pick up a string literal mid-statement.
func _arms_in(src: String, func_name: String) -> Dictionary:
	var start := src.find("static func %s(" % func_name)
	assert_gt(start, -1, "%s is defined" % func_name)
	if start < 0:
		return {}
	var end := src.find("\nstatic func ", start + 1)
	var body := src.substr(start, (end - start) if end > 0 else -1)
	var rx := RegEx.new()
	rx.compile("\\n\\t+\"[a-z_]+\"(?:\\s*,\\s*\"[a-z_]+\")*:")
	var out := {}
	for m in rx.search_all(body):
		# Every quoted word on the arm line ("a", "b": ...) is an arm.
		var inner := RegEx.new()
		inner.compile("\"([a-z_]+)\"")
		for w in inner.search_all(m.get_string(0)):
			out[w.get_string(1)] = true
	return out


## A throwaway Node subclass built at runtime (the tests/test_crouch_light_douse.gd idiom), so the duck-typed
## hops `_gun_pose` / `_camera_effects` make (`player.gun_mesh`, `mesh._pose`, `player.camera_effects`) can be
## satisfied without loading Player.tscn or running anyone's _ready.
func _double(source: String) -> GDScript:
	var scr := GDScript.new()
	scr.source_code = source
	scr.reload()
	return scr


## A ctx whose `player` satisfies both `_camera_effects` and `_gun_pose`. Everything is off-tree and parented
## under the returned player, so ONE free() at the end of the test drops the lot; add_child on an off-tree node
## never enters the SceneTree, so no _ready runs.
func _view_ctx() -> Dictionary:
	var player := Node.new()
	player.set_script(_double("extends Node\nvar gun_mesh: Node = null\nvar camera_effects: Node3D = null\n"))
	var mesh := Node.new()
	mesh.set_script(_double("extends Node\nvar _pose: Node = null\nfunc pose() -> Node:\n\treturn _pose\n"))
	var pose := (load(GUN_POSE) as GDScript).new() as Node
	var cam := Camera3D.new()
	cam.attributes = CameraAttributesPractical.new()
	mesh.add_child(pose)
	player.add_child(mesh)
	player.add_child(cam)
	mesh.set(&"_pose", pose)
	player.set(&"gun_mesh", mesh)
	player.set(&"camera_effects", cam)
	return {&"player": player}


# --- dispatch surface -------------------------------------------------------------------------------------------

func test_dispatcher_routes_into_statics_that_exist_and_none_is_dead() -> void:
	var names := _static_names(View)
	var world_src := FileAccess.get_file_as_string(WORLD_PATH)
	var rx := RegEx.new()
	rx.compile("ViewActions\\.(_cmd_[a-z_]+)\\(")
	var routed := {}
	for m in rx.search_all(world_src):
		var fn := m.get_string(1)
		routed[fn] = true
		assert_true(names.has(fn), "debug_actions_world.gd routes to ViewActions.%s() which does not exist" % fn)
	for fn in names.keys():
		if String(fn).begins_with("_cmd_"):
			assert_true(routed.has(fn), "%s is defined in the view family but never routed (dead handler)" % String(fn))
	assert_gte(routed.size(), 9, "inspect/navdebug/perf/debug_draw/hud/dither/dof/sway/lens all route here")


func test_every_view_row_routes_to_this_family_except_the_two_documented_stay_behinds() -> void:
	# `screenshot` and `quantize` deliberately stay in the main file (the header says why: tests pin their arms
	# there). Everything else on the View page must come here, or the split drifted.
	var world_src := FileAccess.get_file_as_string(WORLD_PATH)
	var stay := {"screenshot": true, "quantize": true}
	for row in Commands.in_category("View"):
		var n := String(row["name"])
		assert_eq(row["mod"], &"world", "'%s' on the View page is a world-module command" % n)
		# Anchor on the ARM (a line that begins with the quoted name, at match-arm indent), not on the first
		# occurrence of the word anywhere in the file — help text and other bodies quote these names too.
		var rx := RegEx.new()
		rx.compile("\\n\\t+(?:\"[a-z_]+\", )*\"%s\"(?:, \"[a-z_]+\")*:.*" % n)
		var m := rx.search(world_src)
		assert_true(m != null, "'%s' has a dispatch arm in debug_actions_world.gd" % n)
		if m == null:
			continue
		var line := m.get_string(0).strip_edges()
		if stay.has(n):
			assert_false(line.contains("ViewActions."), "'%s' is documented to stay in the main file: %s" % [n, line.strip_edges()])
		else:
			assert_true(line.contains("ViewActions._cmd_"), "'%s' (View page) must route into ViewActions: %s" % [n, line.strip_edges()])


func test_debug_draw_arms_cover_the_three_shared_enum_commands() -> void:
	var src := FileAccess.get_file_as_string(VIEW_PATH)
	var arms := _arms_in(src, "_cmd_debug_draw")
	for n in ["wireframe", "overdraw", "unshaded"]:
		assert_true(arms.has(n), "_cmd_debug_draw maps '%s' onto Viewport.debug_draw" % n)
		assert_false(Commands.find(n).is_empty(), "'%s' is a registry row" % n)


## Registry -> family: every verb the `dof` and `sway` rows advertise is really HANDLED. Driven, not scanned.
## A match-arm scan is the wrong instrument: `_cmd_sway` routes its five knob verbs through the SWAY_KNOBS table
## (`SWAY_KNOBS.get(verb, &"")`, debug_actions_world_view.gd:536) and only `preset`/`off`/`reset` reach a match,
## which is nested inside the `else:` — so a scan that expects one flat match reads all eight verbs as dead when
## every one of them works. The observable contract instead: both commands END with an always-printed live
## report, and a HANDLED verb prints a line naming itself IN FRONT of that report, while an unknown verb prints
## the bare report. Each verb is driven with no value, which is the branch that cannot change the game's look.
func test_every_registry_verb_for_dof_and_sway_is_handled_when_driven() -> void:
	var ctx := _view_ctx()
	var player: Node = ctx[&"player"]
	var unknown := PackedStringArray(["zzz_not_a_verb"])
	var baselines := {"dof": View._cmd_dof(ctx, unknown).size(), "sway": View._cmd_sway(ctx, unknown).size()}
	assert_gt(int(baselines["dof"]), 0, "an unknown `dof` verb still prints the live report (the baseline)")
	assert_gt(int(baselines["sway"]), 0, "an unknown `sway` verb still prints the live report (the baseline)")
	for cmd in ["dof", "sway"]:
		var verbs: Array = Commands.find(cmd)["verbs"]
		assert_gt(verbs.size(), 3, "%s lists its knobs" % cmd)
		for v in verbs:
			var verb := String(v)
			var args := PackedStringArray([verb])
			var out: PackedStringArray = View._cmd_dof(ctx, args) if cmd == "dof" else View._cmd_sway(ctx, args)
			assert_gt(out.size(), int(baselines[cmd]),
				"registry verb '%s %s' printed nothing above the live report — it is not handled" % [cmd, verb])
			assert_true(out[0].to_lower().begins_with("%s %s" % [cmd, verb]),
				"'%s %s' answers about itself, so the handler really took it: %s" % [cmd, verb, out[0]])
	player.free()


## Family -> registry, the other direction, which stays a source scan because an UNADVERTISED verb has nothing
## to drive it with. Both dispatch mechanisms are read: the match arms (at any indent) plus, for `sway`, the
## SWAY_KNOBS table keys that never appear as an arm at all.
func test_neither_family_handles_a_verb_the_registry_never_offers() -> void:
	var src := FileAccess.get_file_as_string(VIEW_PATH)
	var handled := {"dof": _arms_in(src, "_cmd_dof"), "sway": _arms_in(src, "_cmd_sway")}
	for knob in View.SWAY_KNOBS.keys():
		(handled["sway"] as Dictionary)[String(knob)] = true
	for cmd in ["dof", "sway"]:
		var verbs: Array = Commands.find(cmd)["verbs"]
		var arms: Dictionary = handled[cmd]
		assert_eq(arms.size(), verbs.size(), "%s handles exactly as many verbs as the registry offers" % cmd)
		for a in arms.keys():
			assert_true(verbs.has(String(a)), "_cmd_%s handles '%s' but the registry never offers it" % [cmd, String(a)])


func test_sway_knob_table_and_registry_agree() -> void:
	var verbs: Array = Commands.find("sway")["verbs"]
	for knob in View.SWAY_KNOBS.keys():
		assert_true(verbs.has(String(knob)), "SWAY_KNOBS '%s' is a registry verb" % String(knob))
		assert_true(View.SWAY_AUTHORED.has(knob), "SWAY_AUTHORED carries a reset value for '%s'" % String(knob))
	assert_eq(View.SWAY_PRESETS.size(), View.SWAY_PRESET_NAMES.size(), "one name per preset")
	for i in View.SWAY_PRESETS.size():
		var preset: Dictionary = View.SWAY_PRESETS[i]
		assert_eq(preset.size(), View.SWAY_KNOBS.size(), "preset %d (%s) sets every knob" % [i, View.SWAY_PRESET_NAMES[i]])
		for knob in View.SWAY_KNOBS.keys():
			assert_true(preset.has(knob), "preset %d carries '%s'" % [i, String(knob)])


func test_family_preloads_exist_and_there_is_no_class_name() -> void:
	var src := FileAccess.get_file_as_string(VIEW_PATH)
	assert_false(src.contains("\nclass_name "), "the family has no class_name (preloaded by path)")
	var rx := RegEx.new()
	rx.compile("preload\\(\"(res://[^\"]+)\"\\)")
	var n := 0
	for m in rx.search_all(src):
		n += 1
		assert_true(ResourceLoader.exists(m.get_string(1)), "preload target %s must exist" % m.get_string(1))
	assert_gte(n, 5, "Common, DebugCommands, DebugOverlay, NavDebugOverlay and Groups are preloaded")


# --- authored mirrors (the "cosmetic drift" the comments warn about) ---------------------------------------------

func test_dof_authored_mirrors_camera_rig_and_engine_defaults() -> void:
	var tscn := FileAccess.get_file_as_string(CAMERA_RIG)
	assert_false(tscn.is_empty(), "camera_rig.tscn is readable")
	var rx := RegEx.new()
	rx.compile("dof_blur_near_distance = ([0-9.]+)")
	var m := rx.search(tscn)
	assert_not_null(m, "camera_rig.tscn authors dof_blur_near_distance (the one DOF field it writes)")
	if m != null:
		assert_almost_eq(float(View.DOF_AUTHORED["near_distance"]), m.get_string(1).to_float(), 0.0001,
			"DOF_AUTHORED.near_distance mirrors the .tscn — `dof reset` restores this number")
	# Every field the table says is ABSENT from the scene must still be absent, and its value must be the engine
	# default a fresh CameraAttributesPractical carries.
	var fresh := CameraAttributesPractical.new()
	var absent := {
		"near_enabled": "dof_blur_near_enabled", "near_transition": "dof_blur_near_transition",
		"far_enabled": "dof_blur_far_enabled", "far_distance": "dof_blur_far_distance",
		"far_transition": "dof_blur_far_transition", "amount": "dof_blur_amount",
	}
	for key in absent.keys():
		var prop: String = absent[key]
		assert_false(tscn.contains(prop + " ="), "camera_rig.tscn must not author %s (DOF_AUTHORED says it is absent -> engine default)" % prop)
		var engine_v: Variant = fresh.get(prop)
		var table_v: Variant = View.DOF_AUTHORED[key]
		if engine_v is bool:
			assert_eq(bool(table_v), bool(engine_v), "DOF_AUTHORED.%s is the engine default for %s" % [key, prop])
		else:
			assert_almost_eq(float(table_v), float(engine_v), 0.0001, "DOF_AUTHORED.%s is the engine default for %s" % [key, prop])
	fresh = null


func test_sway_authored_mirrors_gun_pose_exports() -> void:
	# GunPose is built with .new() by GunMesh — no .tscn override anywhere — so the script defaults ARE the
	# shipped values `sway reset` restores. Off-tree .new() never runs _ready.
	var pose := (load(GUN_POSE) as GDScript).new() as Node
	assert_not_null(pose, "gun_pose.gd constructs off-tree")
	if pose == null:
		return
	for knob in View.SWAY_KNOBS.keys():
		var prop: StringName = View.SWAY_KNOBS[knob]
		var live: Variant = pose.get(prop)
		assert_not_null(live, "GunPose exposes %s (SWAY_KNOBS '%s')" % [String(prop), String(knob)])
		if live != null:
			assert_almost_eq(float(View.SWAY_AUTHORED[knob]), float(live), 0.0001,
				"SWAY_AUTHORED.%s mirrors gun_pose.gd's @export default for %s" % [String(knob), String(prop)])
	pose.free()


func test_lens_authored_mirrors_camera_settings_and_the_tres_has_no_override() -> void:
	var cam := (load(CAMERA_SETTINGS_GD) as GDScript).new() as Resource
	assert_not_null(cam, "CameraSettings.gd constructs")
	if cam != null:
		assert_almost_eq(float(View.LENS_AUTHORED["barrel"]), float(cam.get(&"lens_barrel_amount")), 0.0001, "LENS_AUTHORED.barrel mirrors the @export default")
		assert_almost_eq(float(View.LENS_AUTHORED["chroma"]), float(cam.get(&"lens_chroma_amount")), 0.0001, "LENS_AUTHORED.chroma mirrors the @export default")
	cam = null
	var tres := FileAccess.get_file_as_string(CAMERA_SETTINGS_TRES)
	assert_false(tres.is_empty(), "CameraSettings.tres is readable")
	assert_false(tres.contains("lens_barrel_amount"), "the .tres carries NO lens_barrel_amount override (the comment's whole claim)")
	assert_false(tres.contains("lens_chroma_amount"), "the .tres carries NO lens_chroma_amount override")


func test_bayer_defaults_mirror_the_shader_and_the_grid_table_is_consistent() -> void:
	var shader := FileAccess.get_file_as_string(POST_SHADER)
	assert_false(shader.is_empty(), "post_process.gdshader is readable (source scan only — headless never compiles shaders)")
	var rx := RegEx.new()
	rx.compile("uniform int bayer_order[^=;]*=\\s*(\\d+)")
	var m := rx.search(shader)
	assert_not_null(m, "the shader declares a bayer_order uniform with a default")
	if m != null:
		assert_eq(View.SHADER_DEFAULT_BAYER_ORDER, m.get_string(1).to_int(), "SHADER_DEFAULT_BAYER_ORDER mirrors the shader default (it labels a material with no override)")
	assert_eq(int(View.GRID_TO_BAYER_ORDER[0]), 0, "grid 0 is the OFF entry and must not collide with the unknown -1")
	for width in View.GRID_TO_BAYER_ORDER.keys():
		var order := int(View.GRID_TO_BAYER_ORDER[width])
		if int(width) > 0:
			assert_eq(1 << order, int(width), "grid width %d is 1 << bayer_order %d" % [int(width), order])
	assert_true(View.GRID_TO_BAYER_ORDER.has(1 << View.SHADER_DEFAULT_BAYER_ORDER), "the shader-default grid is one the command can hand back")


# --- pure helpers -----------------------------------------------------------------------------------------------

func test_grouped_inserts_thousands_separators() -> void:
	assert_eq(View._grouped(16777216), "16,777,216", "nine digits -> two separators")
	assert_eq(View._grouped(1000), "1,000", "exactly one thousand")
	assert_eq(View._grouped(999), "999", "under a thousand has none")
	assert_eq(View._grouped(0), "0", "zero")
	assert_eq(View._grouped(-5), "0", "a negative clamps to 0 (a count is never negative)")


func test_screenshot_stamp_is_filename_safe() -> void:
	assert_eq(View.screenshot_stamp("2026-08-18 14:03:07"), "2026-08-18_14-03-07", "space -> _, colons -> -")
	assert_eq(View.screenshot_stamp("2026-08-18T14:03:07"), "2026-08-18_14-03-07", "the ISO T maps to the same shape")
	var live := View.screenshot_stamp(Time.get_datetime_string_from_system(false, true))
	assert_false(live.contains(":") or live.contains(" "), "a live stamp carries no character Windows or a shell would choke on: %s" % live)


func test_next_screenshot_path_lives_under_the_user_dir_and_never_repeats() -> void:
	var first := View._next_screenshot_path()
	var second := View._next_screenshot_path()
	assert_true(first.begins_with(Common.SCREENSHOT_DIR + "/"), "paths land under SCREENSHOT_DIR: %s" % first)
	assert_true(first.ends_with(".png"), "and are .png files: %s" % first)
	assert_ne(first, second, "two calls in a row never hand out the same name (same-second serial)")


func test_hud_held_paths_copies_or_is_empty() -> void:
	assert_eq(View._hud_held_paths({}).size(), 0, "no snapshot -> empty")
	assert_eq(View._hud_held_paths({Common.STATE_HUD_HIDDEN: "junk"}).size(), 0, "a clobbered snapshot -> empty, never an error")
	var state := {Common.STATE_HUD_HIDDEN: PackedStringArray(["HP", "AMMO"])}
	var held := View._hud_held_paths(state)
	assert_eq(held.size(), 2, "the held paths read back")
	held.append("X")
	assert_eq((state[Common.STATE_HUD_HIDDEN] as PackedStringArray).size(), 2, "the caller gets a COPY — mutating it never touches the state")


func test_hud_names_labels_named_nodes_and_classes_for_auto_named_ones() -> void:
	var ui := Node.new()
	var hp := Node.new()
	hp.name = "HP"
	ui.add_child(hp)
	var auto := Node.new()
	ui.add_child(auto)  # unnamed -> "@Node@N": the code-built case
	var paths := PackedStringArray(["HP", String(auto.name), "Gone"])
	var text := View._hud_names(ui, paths)
	assert_true(text.begins_with("HP, "), "a named node prints its name: %s" % text)
	assert_true(text.contains("Node"), "an auto-named node prints its CLASS: %s" % text)
	assert_false(text.contains("@"), "no @ auto-name leaks: %s" % text)
	assert_false(text.contains("Gone"), "a path that no longer resolves is skipped: %s" % text)
	assert_eq(View._hud_names(ui, PackedStringArray()), "(nothing was visible)", "an empty sweep says so")
	var many := PackedStringArray()
	for i in View.HUD_NAMES_MAX + 3:
		var n := Node.new()
		n.name = "N%d" % i
		ui.add_child(n)
		many.append(n.name)
	var capped := View._hud_names(ui, many)
	assert_true(capped.ends_with("+3 more"), "past HUD_NAMES_MAX the tail is counted: %s" % capped)
	ui.free()


func test_hud_layer_and_death_ownership_are_null_safe() -> void:
	assert_null(View._hud_layer(null), "no player -> no HUD layer")
	var plain := Node.new()
	assert_null(View._hud_layer(plain), "a node with no `ui` -> null")
	assert_false(View._hud_owned_by_death(plain), "a node with no _dying/_hud_quiet is not owned by the death cinematic")
	assert_false(View._hud_owned_by_death(null), "null is not owned either")
	plain.free()


# --- degradation off-scene --------------------------------------------------------------------------------------

func test_every_command_degrades_to_one_honest_line_with_no_scene() -> void:
	var none := PackedStringArray()
	var cases := {
		"inspect": View._cmd_inspect({}, none),
		"navdebug": View._cmd_navdebug({}, none),
		"perf": View._cmd_perf({}, none),
		"wireframe": View._cmd_debug_draw("wireframe", {}, none),
		"hud": View._cmd_hud({}, none),
		"dither": View._cmd_dither({}, none),
		"dof": View._cmd_dof({}, none),
		"sway": View._cmd_sway({}, none),
	}
	for cmd in cases.keys():
		var out: PackedStringArray = cases[cmd]
		assert_eq(out.size(), 1, "`%s` with no tree / player is exactly one line" % String(cmd))
		assert_gt(out[0].length(), 10, "`%s` explains itself rather than printing an empty line: %s" % [String(cmd), out[0]])
	assert_true(cases["hud"][0].begins_with("hud: no player"), "hud names the missing player")
	assert_true(cases["dof"][0].begins_with("dof: no player camera"), "dof names the missing camera")
	assert_true(cases["sway"][0].begins_with("sway: no GunPose"), "sway names the missing pose")
	assert_true(cases["dither"][0].begins_with("dither: no post-process material"), "dither names the missing material")


func test_lens_with_no_args_only_reports_and_prints_the_authored_pair() -> void:
	var cam_set: Variant = GameSettings.get(&"camera")
	if cam_set == null:
		pass_test("no GameSettings.camera group in this run — nothing to read")
		return
	var barrel_before := float((cam_set as Resource).get(&"lens_barrel_amount"))
	var chroma_before := float((cam_set as Resource).get(&"lens_chroma_amount"))
	var out := View._cmd_lens({}, PackedStringArray())
	var joined := "\n".join(out)
	assert_true(joined.contains("live: barrel"), "the report line is always printed")
	assert_true(joined.contains("authored %.3f / %.2f" % [float(View.LENS_AUTHORED["barrel"]), float(View.LENS_AUTHORED["chroma"])]),
		"the authored pair in the report IS LENS_AUTHORED: %s" % joined)
	assert_almost_eq(float((cam_set as Resource).get(&"lens_barrel_amount")), barrel_before, 0.0001, "no args -> barrel untouched")
	assert_almost_eq(float((cam_set as Resource).get(&"lens_chroma_amount")), chroma_before, 0.0001, "no args -> chroma untouched")
