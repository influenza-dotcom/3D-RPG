extends GutTest

## The PURE half of the console's `roundtrip` harness (scripts/components/debug_roundtrip.gd): flatten_profile /
## flatten_world / flatten_live / merged_keys / diff_snapshots / values_equal / is_ignored / value_text. Driven on
## a BARE `load("res://managers/GameState.gd").new()` (never the autoload — a test must never touch the user's real
## profile) plus a bare QuestTracker wired to it (the tests/test_quests.gd isolation idiom). The live half — begin()'s
## capture -> scratch write -> _load_and_reload -> settle -> capture B — reloads the whole scene and is play-verified
## in-game; here only its REFUSAL path (no player) is exercised, which touches nothing.
##
## Nothing here writes a save: flatten reads fields, and the one file this harness ever writes (SCRATCH_PATH) is pinned
## as a NON-canonical user:// path so the real gamestate / quicksave / slots can never be its target.

## Preloaded by PATH into an untyped const — the class_name is brand-new and may not be in the editor cache yet (the
## cascade debug_overlay.gd:9-11 documents). Same idiom as tests/test_debug_marks.gd:13.
const Roundtrip := preload("res://scripts/components/debug_roundtrip.gd")
const GAMESTATE_PATH := "res://managers/GameState.gd"
const QUESTTRACKER_PATH := "res://managers/QuestTracker.gd"
## A path for a code-built Quest so QuestTracker.save_into can round-trip it (it SKIPS a path-less quest with a
## warning). take_over_path registers the resource under this res:// path in the cache without any file on disk;
## the name is unique to this test so nothing else can ever resolve it.
const FAKE_QUEST_PATH := "res://tests/__debug_roundtrip_fake_quest.tres"


## A bare GameState wired BOTH WAYS to its own bare QuestTracker. Free with _free_gs.
func _bare_gs() -> Node:
	var gs = load(GAMESTATE_PATH).new()
	var qt = load(QUESTTRACKER_PATH).new()
	gs.quest_tracker = qt
	qt.game_state = gs
	return gs


func _free_gs(gs: Node) -> void:
	if gs.quest_tracker != null:
		gs.quest_tracker.free()
	gs.free()


# --- constants the command rides on ------------------------------------------------------------------------

func test_scratch_path_is_a_non_canonical_user_file() -> void:
	var path := String(Roundtrip.SCRATCH_PATH)
	assert_true(path.begins_with("user://"), "the scratch save lives under user://, got %s" % path)
	var gs := _bare_gs()
	# sandbox_files() IS resolve_save_path's exact-path allowlist — anything not in it passes through unchanged, which
	# is the guarantee the harness doc makes ("the sandbox rewrite never touched it, the real profile is untouched").
	var canonical: PackedStringArray = gs.sandbox_files()
	assert_false(canonical.has(path), "the scratch path must never be one of the five canonical profile paths: %s" % path)
	assert_eq(gs.resolve_save_path(path), path, "a non-canonical path resolves to itself (sandbox off)")
	_free_gs(gs)


func test_default_ignore_covers_the_free_running_fields_and_nothing_else() -> void:
	var ignore: PackedStringArray = Roundtrip.DEFAULT_IGNORE
	for key in ["time_of_day", "status/3/remaining", "respawn/position", "respawn/has", "respawn/yaw",
			"world/res://resources/levels/alive.tres/npc/id:guard_1/yaw"]:
		assert_true(Roundtrip.is_ignored(key, ignore), "%s free-runs between captures and must be ignored" % key)
	for key in ["money", "status/3/path", "world/res://resources/levels/alive.tres/npc/id:guard_1/pos",
			"world/res://resources/levels/alive.tres/npc/id:guard_1/hp", "inventory/equipped", "time_of_day_x"]:
		assert_false(Roundtrip.is_ignored(key, ignore), "%s is identity and must be compared" % key)


func test_is_ignored_accepts_exact_prefix_and_glob() -> void:
	var ignore := PackedStringArray(["exact", "sub", "a/*/z"])
	assert_true(Roundtrip.is_ignored("exact", ignore), "an exact key")
	assert_false(Roundtrip.is_ignored("exactly", ignore), "an exact pattern is not a prefix match")
	assert_true(Roundtrip.is_ignored("sub/one", ignore), "a bare word owns its whole subtree")
	assert_true(Roundtrip.is_ignored("sub/one/two", ignore), "...at any depth")
	assert_false(Roundtrip.is_ignored("subway", ignore), "but only across a slash")
	assert_true(Roundtrip.is_ignored("a/res://x/y.tres/z", ignore), "a glob star spans slashes and dots")
	assert_false(Roundtrip.is_ignored("a/b/y", ignore), "a glob still has to match the tail")
	assert_false(Roundtrip.is_ignored("anything", PackedStringArray([""])), "an empty pattern ignores nothing")


# --- flatten_profile ----------------------------------------------------------------------------------------

func test_flatten_profile_reads_a_bare_gamestate() -> void:
	var gs := _bare_gs()
	gs.money = 42.5
	gs.account = -12.0
	gs.payment_method = "credit"
	gs.player_name = "Ada"
	gs.xp = 300.0
	gs.level = 3
	gs.current_level_path = "res://resources/levels/alive.tres"
	gs.stat_values[&"strength"] = 4
	gs.unlocks.append(&"grapple")
	gs.unlocks.append(&"air_dash")
	gs.flags["met_old_man"] = true
	gs.reputation["raiders"] = -20.0
	gs.known_names["id:old_man"] = true
	gs.perk_paths.append("res://resources/perks/tough.tres")
	gs.perk_grants["tough"] = "iron_skin"
	gs.skill_points = 2
	gs.points_earned = 5
	gs.world_objects = {"res://resources/levels/alive.tres": {"Door@1": {"open": true, "locked": false}}}
	gs.has_inventory = true
	gs.inventory_stacks = [
		{"id": "knife", "count": 1, "x": 0, "y": 0, "w": 1, "h": 2},
		{"id": "ammo_9mm", "count": 30, "x": 1, "y": 0, "w": 1, "h": 1},
		{"id": "ammo_9mm", "count": 12},
	]
	gs.equipped_index = 0
	gs.status_effects = [{"path": "res://resources/status/adrenaline.tres", "remaining": 3.5}]
	gs.set_respawn(Vector3(1, 2, 3), 0.5)

	var flat: Dictionary = Roundtrip.flatten_profile(gs, null)

	assert_eq(flat.get("money"), 42.5, "money")
	assert_eq(flat.get("account"), -12.0, "the signed ledger account")
	assert_eq(flat.get("payment_method"), "credit", "payment rail")
	assert_eq(flat.get("player_name"), "Ada", "name")
	assert_eq(flat.get("xp"), 300.0, "xp")
	assert_eq(flat.get("level"), 3, "level")
	assert_eq(flat.get("current_level_path"), "res://resources/levels/alive.tres", "the level identity")
	assert_eq(flat.get("stat/strength"), 4, "stats are per-key")
	assert_eq(flat.get("unlocks"), ["air_dash", "grapple"], "unlocks are a SORTED string list (order is not identity)")
	assert_eq(flat.get("flag/met_old_man"), true, "flags are per-key")
	assert_eq(flat.get("reputation/raiders"), -20.0, "reputation is per-faction")
	assert_eq(flat.get("known_names"), ["id:old_man"], "known names are the sorted key list")
	assert_eq(flat.get("perks/paths"), ["res://resources/perks/tough.tres"], "perk paths")
	assert_eq(flat.get("perks/grant/tough"), "iron_skin", "perk grants are per-perk")
	assert_eq(flat.get("perks/skill_points"), 2, "skill points")
	assert_eq(flat.get("perks/points_earned"), 5, "points earned")
	assert_eq(flat.get("world_objects/res://resources/levels/alive.tres/Door@1"), {"open": true, "locked": false},
		"world_objects are per level/key with the state Dictionary as the value")
	assert_eq(flat.get("inventory/has"), true, "inventory/has")
	assert_eq(flat.get("inventory/count"), 3, "inventory/count")
	assert_eq(flat.get("inventory/knife#0"), {"id": "knife", "count": 1, "x": 0, "y": 0, "w": 1, "h": 2},
		"a stack is keyed id#ordinal and carries its grid placement")
	assert_true(flat.has("inventory/ammo_9mm#0") and flat.has("inventory/ammo_9mm#1"),
		"two stacks of one id get ordinals 0 and 1, not one clobbering the other")
	assert_eq(flat.get("inventory/equipped"), "knife", "equipped_index is RESOLVED to the item id")
	assert_eq(flat.get("status/0/path"), "res://resources/status/adrenaline.tres", "status path is its own key")
	assert_eq(flat.get("status/0/remaining"), 3.5, "status remaining is a SEPARATE key (so it can be ignored alone)")
	assert_eq(flat.get("respawn/has"), true, "respawn/has")
	assert_eq(flat.get("respawn/position"), Vector3(1, 2, 3), "respawn/position")
	assert_true(flat.has("time_of_day"), "time_of_day is captured (and ignored by default)")
	_free_gs(gs)


func test_flatten_profile_equipped_resolves_to_blank_when_nothing_is_drawn() -> void:
	var gs := _bare_gs()
	gs.has_inventory = true
	gs.inventory_stacks = [{"id": "knife", "count": 1}]
	gs.equipped_index = -1
	var flat: Dictionary = Roundtrip.flatten_profile(gs, null)
	assert_eq(flat.get("inventory/equipped"), "", "fists / nothing equipped reads as an empty id")
	gs.equipped_index = 7  # a bad index (the save's stack was skipped on restore) resolves to blank too, never crashes
	flat = Roundtrip.flatten_profile(gs, null)
	assert_eq(flat.get("inventory/equipped"), "", "an out-of-range equipped_index resolves to blank")
	_free_gs(gs)


func test_flatten_profile_values_are_deep_copies() -> void:
	# GameState clears and refills the SAME Dictionaries on every capture()/load_from_disk — a snapshot that aliased
	# them would silently turn into capture B. Mutate after flattening and the snapshot must not move.
	var gs := _bare_gs()
	gs.world_objects = {"res://lvl.tres": {"Door@1": {"open": true}}}
	gs.inventory_stacks = [{"id": "knife", "count": 1}]
	gs.stat_values[&"strength"] = 4
	var flat: Dictionary = Roundtrip.flatten_profile(gs, null)
	gs.world_objects["res://lvl.tres"]["Door@1"]["open"] = false
	gs.inventory_stacks[0]["count"] = 99
	gs.stat_values.clear()
	assert_eq(flat.get("world_objects/res://lvl.tres/Door@1"), {"open": true}, "the world_objects state was copied, not aliased")
	assert_eq(flat.get("inventory/knife#0"), {"id": "knife", "count": 1}, "the stack entry was copied, not aliased")
	assert_eq(flat.get("stat/strength"), 4, "a scalar read before the clear stays")
	_free_gs(gs)


func test_flatten_profile_reads_quests_through_save_into() -> void:
	var gs := _bare_gs()
	var q := Quest.new()
	q.id = &"rt_quest"
	q.take_over_path(FAKE_QUEST_PATH)  # save_into skips (with a warning) a quest that has no resource_path
	gs.start_quest(q)
	var flat: Dictionary = Roundtrip.flatten_profile(gs, gs.quest_tracker)
	assert_true(flat.has("quests/active/rt_quest"), "an active quest lands under quests/active/<id>: %s" % str(flat.keys()))
	var entry: Variant = flat.get("quests/active/rt_quest")
	assert_true(entry is Dictionary, "the active entry is the {path, progress} record save_into writes")
	if entry is Dictionary:
		assert_eq((entry as Dictionary).get("path"), FAKE_QUEST_PATH, "keyed by the quest's resource_path, exactly as the save is")
	assert_eq(flat.get("quests/active_count"), 1, "the live journal count rides beside the cfg keys")
	assert_eq(flat.get("quests/completed_count"), 0, "nothing completed yet")
	gs.complete_quest(&"rt_quest")
	flat = Roundtrip.flatten_profile(gs, gs.quest_tracker)
	assert_false(flat.has("quests/active/rt_quest"), "a completed quest leaves the active bucket")
	assert_eq(flat.get("quests/completed/rt_quest"), FAKE_QUEST_PATH, "...and lands under quests/completed/<id> as its path")
	assert_eq(flat.get("quests/active_count"), 0, "the live active count follows")
	assert_eq(flat.get("quests/completed_count"), 1, "...and so does the completed count")
	_free_gs(gs)
	q = null


func test_flatten_profile_counts_a_pathless_quest_the_cfg_keys_cannot_see() -> void:
	# save_into SKIPS (and warns about) a code-built quest with no resource_path — by design, it cannot round-trip. So
	# it is absent from quests/active/<id> on BOTH sides of a diff and only the live count can show the round trip
	# dropped it. The skip's push_warning is expected here and must not fail the test.
	var gs := _bare_gs()
	var q := Quest.new()
	q.id = &"rt_pathless"
	gs.start_quest(q)
	var flat: Dictionary = Roundtrip.flatten_profile(gs, gs.quest_tracker)
	assert_false(flat.has("quests/active/rt_pathless"), "a path-less quest is not in the cfg-derived keys (save_into skipped it)")
	assert_eq(flat.get("quests/active_count"), 1, "...but the live journal count still sees it")
	_free_gs(gs)
	q = null


func test_flatten_profile_tolerates_null_and_a_tracker_without_save_into() -> void:
	assert_eq(Roundtrip.flatten_profile(null, null), {}, "no GameState -> an empty snapshot, never a crash")
	var gs := _bare_gs()
	var not_a_tracker := Node.new()
	var flat: Dictionary = Roundtrip.flatten_profile(gs, not_a_tracker)
	assert_true(flat.has("money"), "the profile half still flattens")
	for k in flat:
		assert_false(String(k).begins_with("quests/"), "no quest keys without a save_into()")
	not_a_tracker.free()
	_free_gs(gs)


# --- flatten_world / flatten_live ------------------------------------------------------------------------------

func test_flatten_world_splits_npc_fields_and_sorts_the_dead() -> void:
	var flat: Dictionary = Roundtrip.flatten_world({
		"res://lvl.tres": {
			"authored_npcs": {"id:guard": {"alive": true, "pos": Vector3(1, 2, 3), "yaw": 0.4, "hp": 7.0}},
			"dead_authored": ["id:z", "id:a"],
			"containers": {"id:crate": {"stacks": [{"id": "ammo", "count": 3}], "grid": true}},
		},
		"junk": 7,
	})
	assert_eq(flat.get("world/res://lvl.tres/npc/id:guard/hp"), 7.0, "hp is its own key (exact)")
	assert_eq(flat.get("world/res://lvl.tres/npc/id:guard/pos"), Vector3(1, 2, 3), "pos is its own key (tolerance)")
	assert_eq(flat.get("world/res://lvl.tres/npc/id:guard/yaw"), 0.4, "yaw is its own key (ignored by default)")
	assert_eq(flat.get("world/res://lvl.tres/dead"), ["id:a", "id:z"], "the dead set is sorted")
	assert_eq(flat.get("world/res://lvl.tres/container/id:crate"), {"stacks": [{"id": "ammo", "count": 3}], "grid": true},
		"a container's entry rides whole (compared by value)")
	for k in flat:
		assert_false(String(k).begins_with("world/junk"), "a junk-typed level bucket is skipped")


func test_flatten_live_degrades_per_missing_hop() -> void:
	assert_eq(Roundtrip.flatten_live(null, null), {}, "no player, no level -> nothing")
	var stub := Node.new()  # no hp, no weapon_system, no inventory, not a Node3D
	var flat: Dictionary = Roundtrip.flatten_live(stub, null)
	assert_true(flat.has("live/hp"), "an absent field reads as a null value, still a key")
	assert_false(flat.has("live/pos"), "a non-Node3D has no position key")
	assert_false(flat.has("live/drawn_weapon"), "no weapon_system -> no drawn-weapon key")
	assert_false(flat.has("live/bag_equipped"), "no inventory -> no bag key")
	stub.free()
	var level := Node.new()
	level.name = "Level"
	flat = Roundtrip.flatten_live(null, level)
	assert_eq(flat.get("live/level_name"), "Level", "the level's name is recorded")
	assert_true(flat.has("live/level_scene"), "and its scene path")
	level.free()


# --- merged_keys / diff_snapshots ---------------------------------------------------------------------------------

func test_diff_identical_is_empty_and_counts_compared_fields() -> void:
	var a := {"money": 10, "name": "Ada", "time_of_day": 0.25}
	var b := {"money": 10, "name": "Ada", "time_of_day": 0.75}
	var ignore := PackedStringArray(["time_of_day"])
	assert_eq(Roundtrip.diff_snapshots(a, b, ignore), PackedStringArray(), "identical over the compared keys -> no lines")
	assert_eq(Roundtrip.merged_keys(a, b, ignore), PackedStringArray(["money", "name"]), "the compared keys, sorted, minus the ignored one")


func test_diff_one_change_prints_key_a_arrow_b() -> void:
	var lines: PackedStringArray = Roundtrip.diff_snapshots({"money": 10, "name": "Ada"}, {"money": 25, "name": "Ada"}, PackedStringArray())
	assert_eq(lines.size(), 1, "exactly one changed field")
	assert_eq(lines[0], "money: 10 -> 25", "the line is `key: A -> B`")


func test_diff_ignored_key_is_silent_even_when_it_changed() -> void:
	var a := {"money": 10, "status/0/remaining": 5.0, "status/0/path": "res://a.tres", "respawn/position": Vector3.ZERO}
	var b := {"money": 10, "status/0/remaining": 2.0, "status/0/path": "res://b.tres", "respawn/position": Vector3(9, 9, 9)}
	var lines: PackedStringArray = Roundtrip.diff_snapshots(a, b, Roundtrip.DEFAULT_IGNORE)
	assert_eq(lines.size(), 1, "only the status PATH change survives the default ignore list: %s" % str(lines))
	assert_string_contains(lines[0], "status/0/path")
	assert_false(" ".join(lines).contains("remaining"), "the ticking timer is not reported")
	assert_false(" ".join(lines).contains("respawn"), "the rewritten checkpoint is not reported")


func test_diff_reports_missing_keys_on_either_side() -> void:
	var lines: PackedStringArray = Roundtrip.diff_snapshots({"only_a": 1}, {"only_b": 2}, PackedStringArray())
	assert_eq(lines.size(), 2, "one line per one-sided key")
	assert_eq(lines[0], "only_a: 1 -> (missing)", "a key that vanished")
	assert_eq(lines[1], "only_b: (missing) -> 2", "a key that appeared")


func test_diff_positions_within_tolerance_are_equal() -> void:
	var a := {"live/pos": Vector3(0, 0, 0)}
	var b := {"live/pos": Vector3(0.6, 0.0, 0.0)}
	assert_eq(Roundtrip.diff_snapshots(a, b, PackedStringArray()).size(), 0, "0.6 m is inside the default %.1f m tolerance" % Roundtrip.POSITION_TOLERANCE)
	assert_eq(Roundtrip.diff_snapshots(a, {"live/pos": Vector3(1.5, 0.0, 0.0)}, PackedStringArray()).size(), 1, "1.5 m is a real move")
	assert_eq(Roundtrip.diff_snapshots(a, b, PackedStringArray(), 0.1).size(), 1, "the tolerance is a parameter")


func test_values_equal_is_approx_for_floats_and_recursive_for_containers() -> void:
	assert_true(Roundtrip.values_equal(0.1 + 0.2, 0.3, 1.0), "floats compare approx (a ConfigFile round trip is text)")
	assert_true(Roundtrip.values_equal(3, 3.0, 1.0), "int and float of the same value are equal")
	assert_false(Roundtrip.values_equal(true, 1, 1.0), "a bool is not a number")
	assert_true(Roundtrip.values_equal({"pos": Vector3.ZERO, "n": [1, 2.0]}, {"pos": Vector3(0.5, 0, 0), "n": [1.0, 2]}, 1.0),
		"nested Dictionaries/Arrays apply the same tolerances")
	assert_false(Roundtrip.values_equal({"a": 1}, {"a": 1, "b": 2}, 1.0), "a different key count is a difference")
	assert_false(Roundtrip.values_equal([1, 2], [2, 1], 1.0), "Arrays are ordered")
	assert_false(Roundtrip.values_equal("1", 1, 1.0), "a String is never equal to a number")


func test_value_text_quotes_strings_and_caps_length() -> void:
	assert_eq(Roundtrip.value_text("knife"), "\"knife\"", "Strings are quoted so a blank reads as \"\"")
	assert_eq(Roundtrip.value_text(Vector3(1.234, 2, 3)), "(1.23, 2.00, 3.00)", "Vector3 to 2 decimals")
	assert_eq(Roundtrip.value_text(10), "10", "an int is plain")
	var long_value := []
	for i in 200:
		long_value.append(i)
	var text: String = Roundtrip.value_text(long_value)
	assert_lte(text.length(), int(Roundtrip.MAX_VALUE_CHARS), "a long value is capped")
	assert_true(text.ends_with("…"), "...with an ellipsis")


# --- the harness node: construct + refusal path only (the live path reloads the scene) --------------------------

func test_harness_constructs_off_tree_and_refuses_without_a_player() -> void:
	var h = Roundtrip.new()
	assert_not_null(h, "the harness compiles + constructs off-tree (no _ready until added to a tree)")
	var refusal: String = h.begin(null)
	assert_string_contains(refusal, "REFUSED")
	assert_string_contains(refusal, "player")
	h.free()
