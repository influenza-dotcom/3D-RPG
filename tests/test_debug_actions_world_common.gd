extends GutTest

## The SHARED half of the world debug actions (scripts/components/debug_actions_world_common.gd): the ctx
## accessors, tree lookups, disk scans, formatters and state keys every world action family (main / npc / story /
## view) preloads by PATH. Pins (1) the static surface the dispatcher and the three families call into, (2) the
## pure helpers with concrete inputs, (3) every hard-coded res:// path it names still exists on disk, and (4) the
## state-key contract `release_scene_scoped_state` relies on. Nothing here calls the dispatcher's run(): the
## commands write real autoload state (GameState, WorldClock, saves), so they are pinned by source scan in
## test_debug_commands.gd, and only READ-ONLY helpers are driven live here.

const COMMON_PATH := "res://scripts/components/debug_actions_world_common.gd"
const WORLD_PATH := "res://scripts/components/debug_actions_world.gd"
const Common := preload("res://scripts/components/debug_actions_world_common.gd")
const World := preload("res://scripts/components/debug_actions_world.gd")


func _static_names(script: GDScript) -> Dictionary:
	var out := {}
	for m in script.get_script_method_list():
		out[String(m["name"])] = true
	return out


## A throwaway Node subclass built at runtime, so `_npc_label` / `_find_by_script` can be driven without loading
## an NPC (the same source_code + reload() idiom tests/test_crouch_light_douse.gd uses).
func _npc_double_script() -> GDScript:
	var scr := GDScript.new()
	scr.source_code = "extends Node\nvar hp: float = 30.0\nvar max_hp: float = 100.0\nfunc identity_key() -> String:\n\treturn \"raider_a\"\nfunc is_alive() -> bool:\n\treturn true\n"
	scr.reload()
	return scr


# --- surface ---------------------------------------------------------------------------------------------

func test_common_exposes_every_helper_the_dispatcher_and_families_call() -> void:
	# Every `Common.<name>(` reference in the four world action files must resolve to a static on this script,
	# or the family fails to PARSE and the console / menu that preload it go down with it.
	var names := _static_names(Common)
	var rx := RegEx.new()
	rx.compile("Common\\.(_?[a-z][a-z0-9_]*)\\s*\\(")
	var checked := 0
	for path in [WORLD_PATH, "res://scripts/components/debug_actions_world_npc.gd",
			"res://scripts/components/debug_actions_world_story.gd", "res://scripts/components/debug_actions_world_view.gd"]:
		var src := FileAccess.get_file_as_string(path)
		assert_false(src.is_empty(), "%s must be readable" % path)
		for m in rx.search_all(src):
			var fn := m.get_string(1)
			checked += 1
			assert_true(names.has(fn), "%s calls Common.%s() but debug_actions_world_common.gd has no such static" % [path.get_file(), fn])
	assert_gt(checked, 40, "the families lean on Common heavily — a near-zero count means the regex drifted")


func test_common_exposes_every_const_the_families_read() -> void:
	var consts := (Common as GDScript).get_script_constant_map()
	var rx := RegEx.new()
	rx.compile("Common\\.([A-Z][A-Z0-9_]+)\\b")
	var checked := 0
	for path in [WORLD_PATH, "res://scripts/components/debug_actions_world_npc.gd",
			"res://scripts/components/debug_actions_world_story.gd", "res://scripts/components/debug_actions_world_view.gd"]:
		var src := FileAccess.get_file_as_string(path)
		for m in rx.search_all(src):
			var c := m.get_string(1)
			checked += 1
			assert_true(consts.has(c), "%s reads Common.%s but the const does not exist" % [path.get_file(), c])
	assert_gt(checked, 5, "the families read Common consts (STATE_*, KILL_DAMAGE, SCREENSHOT_DIR...)")


func test_common_has_no_class_name_and_preloads_no_action_module() -> void:
	# The whole reason for the split: this file must be preloadable by every family with no cycle and no
	# dependency on the editor's global class cache.
	var src := FileAccess.get_file_as_string(COMMON_PATH)
	assert_false(src.contains("\nclass_name "), "common has NO class_name — families preload it by PATH")
	for sibling in ["debug_actions_world.gd", "debug_actions_world_npc.gd", "debug_actions_world_story.gd", "debug_actions_world_view.gd"]:
		assert_false(src.contains("preload(\"res://scripts/components/%s\")" % sibling),
			"common must never preload %s (a preload cycle would fail every family at parse)" % sibling)


# --- paths on disk --------------------------------------------------------------------------------------------

func test_hard_coded_paths_exist_on_disk() -> void:
	assert_true(ResourceLoader.exists(Common.INSPECTOR_SCRIPT_PATH),
		"INSPECTOR_SCRIPT_PATH is loaded lazily, so a moved debug_inspector.gd breaks `who`/`npc`/`inspect` SILENTLY")
	assert_true(DirAccess.dir_exists_absolute(Common.QUEST_DIR), "QUEST_DIR must exist or `quest`/`quests` scan nothing")
	for p in Common.CLEAN_HIDDEN_SCRIPT_PATHS:
		assert_true(ResourceLoader.exists(p), "CLEAN_HIDDEN_SCRIPT_PATHS entry %s must exist (`screenshot clean` matches by script path)" % p)
	assert_true(Common.SCREENSHOT_DIR.begins_with("user://"), "debug output goes under user:// only (project rule)")


func test_perception_copied_once_fields_are_real_exports_on_both_ends() -> void:
	# `npc rebrain` re-stamps these from the NPC's exports onto its Perception; a renamed field on either side
	# would make the re-stamp a silent no-op.
	var npc_props := {}
	for p in (load("res://scripts/npc/npc.gd") as GDScript).get_script_property_list():
		npc_props[String(p["name"])] = true
	var per_props := {}
	for p in (load("res://scripts/npc/perception.gd") as GDScript).get_script_property_list():
		per_props[String(p["name"])] = true
	assert_gt(Common.PERCEPTION_COPIED_ONCE.size(), 5, "the copied-once list is populated")
	for f in Common.PERCEPTION_COPIED_ONCE:
		assert_true(npc_props.has(String(f)), "PERCEPTION_COPIED_ONCE field '%s' must be a property on npc.gd" % String(f))
		assert_true(per_props.has(String(f)), "PERCEPTION_COPIED_ONCE field '%s' must be a property on perception.gd" % String(f))


# --- state keys -------------------------------------------------------------------------------------------------

func test_state_keys_are_namespaced_and_distinct() -> void:
	var keys := [Common.STATE_FREEZE_AI, Common.STATE_NPC_STICKY, Common.STATE_HUD_HIDDEN]
	var seen := {}
	for k in keys:
		assert_true(String(k).begins_with("world/"), "state key '%s' is namespaced 'world/' so the player module cannot collide" % String(k))
		assert_false(seen.has(k), "state key '%s' is unique" % String(k))
		seen[k] = true


func test_release_scene_scoped_state_erases_every_common_key() -> void:
	# The dispatcher's unwind must drop every scene-scoped key common declares — a stale sticky NPC handle or
	# HUD snapshot would point into the freed scene. Driven with a state that carries NO timescale bank, so the
	# call touches no autoload.
	var state := {Common.STATE_FREEZE_AI: true, Common.STATE_NPC_STICKY: null, Common.STATE_HUD_HIDDEN: PackedStringArray(["HP"]), &"other/keep": 1}
	var notes := World.release_scene_scoped_state({&"state": state})
	assert_eq(notes.size(), 0, "no timescale bank -> no note (nothing else is reported)")
	for k in [Common.STATE_FREEZE_AI, Common.STATE_NPC_STICKY, Common.STATE_HUD_HIDDEN]:
		assert_false(state.has(k), "release_scene_scoped_state erases %s" % String(k))
	assert_true(state.has(&"other/keep"), "keys the world module does not own are left alone")
	var again := World.release_scene_scoped_state({&"state": state})
	assert_eq(again.size(), 0, "idempotent: a second release on an empty state is a silent no-op")
	var no_state := World.release_scene_scoped_state({})
	assert_eq(no_state.size(), 0, "a ctx with no state dictionary degrades to a no-op, never a crash")


# --- ctx helpers ------------------------------------------------------------------------------------------------

func test_ctx_accessors_degrade_to_null_on_missing_junk_and_freed() -> void:
	assert_null(Common._tree({}), "no tree key -> null")
	assert_null(Common._tree({&"tree": 5}), "a non-object tree -> null (is_instance_valid first, then the cast)")
	assert_null(Common._player({}), "no player -> null")
	var n := Node.new()
	assert_eq(Common._player({&"player": n}), n, "a live player comes back as-is")
	assert_null(Common._player3d({&"player": n}), "a plain Node is not a Node3D -> null (the cast, not an error)")
	var n3 := Node3D.new()
	assert_eq(Common._player3d({&"player": n3}), n3, "a Node3D player casts")
	n3.free()
	n.free()
	assert_null(Common._player({&"player": n}), "a FREED player handle degrades to null (validity is checked BEFORE the cast)")
	assert_null(Common._game_root(null), "_game_root(null tree) is null")


func test_state_returns_the_host_dictionary_by_reference_or_a_throwaway() -> void:
	var host := {}
	var s := Common._state({&"state": host})
	s[&"x"] = 1
	assert_true(host.has(&"x"), "the host's Dictionary is returned by reference — toggles persist across commands")
	var throwaway := Common._state({})
	assert_eq(throwaway.size(), 0, "no state supplied -> a fresh empty Dictionary, never a crash")
	assert_eq(Common._state({&"state": "junk"}).size(), 0, "a non-Dictionary state degrades to a throwaway")


func test_one_wraps_a_single_line() -> void:
	var out := Common._one("hello")
	assert_eq(out.size(), 1, "_one is exactly one line")
	assert_eq(out[0], "hello", "and it is the line given")


# --- tree lookups -----------------------------------------------------------------------------------------------

func test_find_by_script_and_find_or_create_match_by_script_identity() -> void:
	var scr := _npc_double_script()
	var root := Node.new()
	var plain := Node.new()
	plain.name = "Plain"
	root.add_child(plain)
	var deep := Node.new()
	deep.set_script(scr)
	deep.name = "Deep"
	plain.add_child(deep)
	# Identity compared with ==, not assert_eq: GUT stringifies a Node whose script is not file-backed through
	# inst_to_dict(), which is an engine error on a runtime-built GDScript.
	assert_true(Common._find_by_script(root, scr) == deep, "depth-first search finds the node carrying the script under a plain parent")
	assert_null(Common._find_by_script(root, null), "a null script finds nothing")
	assert_null(Common._find_by_script(null, scr), "a null root finds nothing")
	var made := Common._find_or_create(root, &"Probe", scr)
	# `!= null` through assert_true, never assert_not_null: assert_not_null formats its subject EAGERLY through
	# GutStringUtils.type2str -> inst_to_dict (addons/gut/strutils.gd:86), which raises "Not based on a resource
	# file" on a node carrying a runtime-built GDScript and fails the test as an Unexpected Error.
	assert_true(made != null, "find_or_create builds a node when the name is free")
	assert_eq(String(made.name), "Probe", "and names it as asked")
	assert_true(made.get_parent() == root, "under the given parent")
	assert_true(Common._find_or_create(root, &"Probe", scr) == made, "a second call returns the SAME node")
	assert_null(Common._find_or_create(root, &"Plain", scr), "a name taken by an UNRELATED node refuses rather than shadowing it")
	assert_null(Common._find_or_create(null, &"Probe", scr), "a null parent -> null")
	root.free()


func test_has_level_root_script_matches_by_file_name() -> void:
	var bare := Node.new()
	assert_false(Common._has_level_root_script(bare), "a script-less node is not a level root")
	bare.set_script(_npc_double_script())
	assert_false(Common._has_level_root_script(bare), "an unrelated runtime script is not level_root.gd")
	bare.free()
	assert_true(ResourceLoader.exists("res://scripts/world/level_root.gd"), "level_root.gd exists (the file name `warp` checks for)")


func test_inspector_and_resolve_degrade_without_a_tree() -> void:
	assert_null(Common._inspector({}), "no tree -> no inspector (never created off-scene)")
	var pick := Common._resolve_aimed_npc({})
	assert_null(pick[&"npc"], "no inspector -> no NPC")
	assert_false(bool(pick[&"sticky"]), "no inspector -> not sticky")
	assert_true(String(pick[&"error"]).contains("DebugInspector"), "the error line names the missing inspector: %s" % String(pick[&"error"]))


# --- content scans ----------------------------------------------------------------------------------------------

func test_quest_scan_is_keyed_by_quest_id_not_file_stem() -> void:
	var index := Common._quests()
	assert_gt(index.size(), 0, "the quest folder holds authored quests")
	assert_true(index.has("recover_package"), "recover_the_package.tres declares id recover_package — the scan keys by Quest.id")
	assert_false(index.has("recover_the_package"), "the FILE STEM is not a key (that is the trap the scan exists for)")
	for k in index.keys():
		assert_true(ResourceLoader.exists(String(index[k])), "quest '%s' maps to a path on disk" % String(k))
	assert_eq(Common._quests(), index, "the scan is cached — a second call returns the same index")


func test_scan_tolerates_a_missing_folder_and_a_wrong_key_field() -> void:
	assert_eq(Common._scan("res://no/such/folder/", "quest.gd", "objectives", "id").size(), 0, "a missing folder scans to empty, never errors")
	var by_stem := Common._scan(Common.QUEST_DIR, "quest.gd", "objectives", "")
	assert_true(by_stem.has("recover_the_package"), "a blank key_field keys by file stem")
	var no_key := Common._scan(Common.QUEST_DIR, "quest.gd", "objectives", "no_such_field")
	assert_eq(no_key.size(), 0, "a key field no resource carries yields NO entries rather than blank keys")


func test_lookup_is_case_insensitive_and_sorted_keys_sort() -> void:
	var index := {"TestLevel": "res://a.tres", "alive": "res://b.tres"}
	assert_eq(Common._lookup(index, "TestLevel"), "res://a.tres", "exact hit")
	assert_eq(Common._lookup(index, "testlevel"), "res://a.tres", "case-insensitive hit")
	assert_eq(Common._lookup(index, "nope"), "", "a miss is the empty string")
	assert_eq(Array(Common._sorted_keys(index)), ["TestLevel", "alive"], "keys come back sorted (String order)")
	assert_eq(Common._sorted_keys({}).size(), 0, "an empty index sorts to nothing")


# --- formatting -------------------------------------------------------------------------------------------------

func test_facts_text_sorts_keys_and_formats_floats() -> void:
	assert_eq(Common._facts_text({}), "{}", "an empty dictionary renders as {}")
	assert_eq(Common._facts_text({&"b": true, &"a": 1.5, "c": 3}), "{a=1.50, b=true, c=3}",
		"keys sort, floats print 2dp, StringName and String keys both resolve")


func test_numeric_variant_guards() -> void:
	assert_eq(Common._int_of(null, 7), 7, "_int_of(null) falls back instead of the invalid-constructor error")
	assert_eq(Common._int_of(3.9), 3, "a float truncates")
	assert_eq(Common._int_of(true), 1, "a bool counts as 1")
	assert_eq(Common._int_of("5", 9), 9, "a String is junk here (Object.get() never hands back a parsed number) -> fallback")
	assert_eq(Common._float_of(null, 2.5), 2.5, "_float_of(null) falls back")
	assert_eq(Common._float_of(2), 2.0, "an int widens")
	assert_eq(Common._float_of("x"), 0.0, "junk -> the default 0.0")
	assert_true(Common._bool_of(true), "_bool_of(true)")
	assert_false(Common._bool_of(null), "_bool_of(null) is false, never bool(null)")
	assert_false(Common._bool_of(1), "only a REAL bool reads true")


func test_count_of_and_vec3_text() -> void:
	assert_eq(Common._count_of([1, 2, 3]), 3, "Array size")
	assert_eq(Common._count_of({"a": 1}), 1, "Dictionary size")
	assert_eq(Common._count_of(null), 0, "null -> 0")
	assert_eq(Common._count_of("str"), 0, "a String is not a container -> 0")
	assert_eq(Common._vec3_text(Vector3(1.5, -2.0, 3.0)), "(1.5, -2.0, 3.0)", "one decimal per axis")


func test_npc_label_reads_identity_and_hp_duck_typed() -> void:
	var plain := Node.new()
	plain.name = "Wall"
	assert_eq(Common._npc_label(plain), "Wall", "a node with no identity_key / is_alive is just its name")
	plain.free()
	var npc := Node.new()
	npc.set_script(_npc_double_script())
	npc.name = "Raider"
	assert_eq(Common._npc_label(npc), "Raider (raider_a)  hp 30/100", "name, identity key and hp x/y")
	npc.free()


func test_quest_report_and_reward_text_read_the_authored_quest() -> void:
	var index := Common._quests()
	var path := String(index.get("recover_package", ""))
	assert_ne(path, "", "recover_package is on disk")
	var quest := load(path) as Resource
	assert_not_null(quest, "the quest loads")
	var reward := Common._reward_text(quest)
	assert_true(reward.contains("money 120"), "reward_money reads through: %s" % reward)
	assert_true(reward.contains("xp 35"), "reward_xp reads through: %s" % reward)
	assert_true(reward.contains("rep on 1 faction"), "reward_reputation counts its keys: %s" % reward)
	var report := Common._quest_report(quest, &"recover_package", path)
	assert_gt(report.size(), 3, "the report is several lines")
	assert_true(report[0].begins_with("recover_package"), "the header leads with the id: %s" % report[0])
	assert_true(report[0].contains("[PH] Recover the Package"), "and carries the title: %s" % report[0])
	assert_true(report[1].contains("recover_the_package.tres"), "the file line names the .tres: %s" % report[1])
	var found_objective := false
	for line in report:
		if line.contains("slice_package"):
			found_objective = true
	assert_true(found_objective, "every objective's target_id is listed")
	var state := Common._quest_state(&"__gut_never_a_quest__")
	assert_eq(state, "-", "an unknown quest id reads '-' (not active / done / failed)")
