extends GutTest

## Unit tests for the pure architecture-annotation scanner/renderer (scripts/tools/arch_scan.gd). Off-tree, no _ready,
## no editor -- feeds synthetic source text to parse_file() + synthetic entries to render(), matching the "pure builder
## tested with in-memory data" idiom of the dialogue/quest graph_data tests.

const ArchScan := preload("res://scripts/tools/arch_scan.gd")


func _src(lines: Array) -> String:
	return "\n".join(lines)


func test_block_above_class_name_becomes_one_entry() -> void:
	var text := _src([
		"## @system NPC Brain",
		"## @seam GOAP is the sole NPC decision layer.",
		"## @risk Scene wiring can regress silently without a contract test.",
		"## @test res://tests/test_goap_executor.gd",
		"extends CharacterBody3D",
		"class_name NPC",
	])
	var entries := ArchScan.parse_file("res://scripts/npc/npc.gd", text, {})
	assert_eq(entries.size(), 1, "one @system block -> one entry")
	var e: Dictionary = entries[0]
	assert_eq(String(e.get("system")), "NPC Brain", "system name captured")
	assert_eq(String(e.get("anchor")), "class NPC", "class_name resolves the anchor")
	assert_eq(String(e.get("file")), "res://scripts/npc/npc.gd", "file path recorded")
	assert_eq(String(e.get("seam")), "GOAP is the sole NPC decision layer.", "seam captured")
	assert_eq((e.get("risks") as Array).size(), 1, "one risk captured")
	var tests := e.get("tests") as Array
	assert_eq(tests.size(), 1, "one test captured")
	assert_eq(String(tests[0]), "res://tests/test_goap_executor.gd", "test path captured verbatim")


func test_autoload_without_class_name_anchors_on_autoload_name() -> void:
	var text := _src([
		"extends Node",
		"## @system Save Model",
		"## @seam GameState is a profile/checkpoint save, not a world snapshot.",
	])
	var autoloads := {"res://managers/GameState.gd": "GameState"}
	var entries := ArchScan.parse_file("res://managers/GameState.gd", text, autoloads)
	assert_eq(entries.size(), 1, "block found even below extends")
	assert_eq(String(entries[0].get("anchor")), "autoload GameState", "no class_name -> autoload name from the map")


func test_block_without_system_is_ignored() -> void:
	var text := _src([
		"## Just an ordinary doc comment.",
		"## @seam an orphan seam with no @system",
		"class_name Foo",
	])
	var entries := ArchScan.parse_file("res://scripts/foo.gd", text, {})
	assert_eq(entries.size(), 0, "a block with no @system is not an architecture entry")


func test_repeated_seam_joins_and_risks_accumulate() -> void:
	var text := _src([
		"## @system Economy",
		"## @seam Wallet is the authoritative float.",
		"## @seam A loot source carries its cash as a coin stack.",
		"## @risk Double-count if the coin tile is serialized.",
		"## @risk Loot loss if the changed signal fires mid-transfer.",
		"class_name SyntheticWallet",
	])
	var e: Dictionary = ArchScan.parse_file("res://scripts/inventory/synthetic_wallet.gd", text, {})[0]
	assert_eq(String(e.get("seam")), "Wallet is the authoritative float. A loot source carries its cash as a coin stack.", "repeated @seam joins with a space")
	assert_eq((e.get("risks") as Array).size(), 2, "each @risk accumulates")


func test_two_blocks_in_one_file_make_two_entries() -> void:
	var text := _src([
		"## @system Save Model",
		"## @seam Atomic write via .tmp + .bak rotation.",
		"",
		"## @system Save Model",
		"## @seam world_objects is an ADDITIVE per-object ledger.",
		"extends Node",
	])
	var autoloads := {"res://managers/GameState.gd": "GameState"}
	var entries := ArchScan.parse_file("res://managers/GameState.gd", text, autoloads)
	assert_eq(entries.size(), 2, "two blank-line-separated @system blocks -> two entries")
	for e in entries:
		assert_eq(String(e.get("anchor")), "autoload GameState", "both entries share the file's anchor")


func test_fallback_anchor_is_basename() -> void:
	var text := _src([
		"## @system Misc",
		"## @seam A plain node with neither class_name nor an autoload entry.",
		"extends Node",
	])
	var entries := ArchScan.parse_file("res://scripts/misc/thing.gd", text, {})
	assert_eq(String(entries[0].get("anchor")), "file thing.gd", "no class_name + not an autoload -> file basename")


func test_render_is_sorted_and_well_formed() -> void:
	var entries := [
		{"system": "Beta", "file": "res://b.gd", "anchor": "class B", "seam": "seam b", "risks": [], "tests": []},
		{"system": "Alpha", "file": "res://a.gd", "anchor": "class A", "seam": "seam a", "risks": ["risk a"], "tests": ["res://tests/test_a.gd"]},
	]
	var out := ArchScan.render(entries)
	assert_eq(out.find("# System Map"), 0, "starts with the title")
	assert_true(out.ends_with("\n"), "exactly one trailing newline")
	assert_true(out.find("## Alpha") != -1 and out.find("## Beta") != -1, "both system sections present")
	assert_true(out.find("## Alpha") < out.find("## Beta"), "systems render in sorted order regardless of input order")
	assert_true(out.find("seam a") != -1, "seam text rendered")
	assert_true(out.find("- **Risk:** risk a") != -1, "risk rendered as a bullet")
	assert_true(out.find("`tests/test_a.gd`") != -1, "test path rendered (res:// stripped)")
	assert_true(out.find("**Test:** _none") != -1, "an entry with no test is flagged as playtest-only")


func test_scene_root_script_path_resolves_the_root_script() -> void:
	# The authored-scene autoload shape (heal/shop/loot/options/save-load screens): the .tscn hosts the script,
	# so the scanner must see through it or the anchor degrades from "autoload Name" to the basename fallback.
	var tscn := _src([
		"[gd_scene load_steps=2 format=3]",
		"",
		"[ext_resource type=\"Script\" uid=\"uid://abc123\" path=\"res://scripts/ui/loot_screen.gd\" id=\"1\"]",
		"",
		"[node name=\"LootScreen\" type=\"CanvasLayer\"]",
		"layer = 121",
		"script = ExtResource(\"1\")",
		"",
		"[node name=\"Root\" type=\"Control\" parent=\".\"]",
		"unique_name_in_owner = true",
	])
	assert_eq(ArchScan.scene_root_script_path(tscn), "res://scripts/ui/loot_screen.gd",
		"root node's script = ExtResource(id) resolves through the ext_resource table")


func test_scene_root_script_path_scriptless_or_non_scene_is_empty() -> void:
	var no_script := _src([
		"[gd_scene load_steps=1 format=3]",
		"",
		"[node name=\"Bare\" type=\"Node\"]",
		"",
		"[node name=\"Child\" type=\"Node\" parent=\".\"]",
	])
	assert_eq(ArchScan.scene_root_script_path(no_script), "", "a scriptless root resolves to empty")
	assert_eq(ArchScan.scene_root_script_path("not a scene at all"), "", "non-scene text resolves to empty")


func test_read_doc_normalizes_crlf_and_missing() -> void:
	assert_eq(ArchScan.read_doc("res://does_not_exist_arch.md"), "", "missing doc reads as empty string")
	var tmp := "user://arch_scan_read_test.md"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	f.store_string("line1\r\nline2\r\n")
	f.close()
	assert_eq(ArchScan.read_doc(tmp), "line1\nline2\n", "CRLF normalized to LF on read")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
