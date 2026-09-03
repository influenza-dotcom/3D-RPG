extends GutTest

## The CYBER SUNDAY Reach report — "what can a PLAYER actually reach from the boot scene?", the one question
## neither Stats ("is X referenced by ANY file?") nor Audit (quest-id STRINGS) can answer, and the reason this
## project can hold 0 reachable quests while every other tab reports clean.
##
## TWO LAYERS, deliberately:
##
##  1. PURE unit tests on fixture strings + an INJECTED file map. reach_scan.gd is a plain RefCounted with statics
##     only (no EditorInterface, no scene tree, no DirAccess), so every rule below is driven off-tree. The closure
##     takes text_of as a Callable precisely so a test can hand it a six-entry dictionary instead of a project —
##     the same seam that keeps the shipped tab from materialising a {path: text} map of res:// (the .flitevox.res
##     voices alone are 59 MB, and Godot Strings are UTF-32 internally).
##
##  2. ONE ACCEPTANCE pass that runs the SHIPPED pipeline over the REAL project and pins hand-verified rows. This
##     is the layer that matters most, because of HOW this tab fails: an empty or all-green Reach report is a
##     FAILURE, not a pass — it means the folder-scan guard over-fired and swallowed every real orphan. This
##     project already carries that scar: text_debt.gd once printed "TOTAL: 0" while 132 of 267 strings were
##     unauthored placeholders. So a test that would pass on an EMPTY report is worthless here. The acceptance
##     tests assert the report CONTAINS the known orphans — clear_the_block -> NO START SITE, recover_the_package
##     -> START SITE NOT REACHABLE naming QuestStarter.quest in SliceTestLevel.tscn — and that it prints the real
##     boot chain with real denominators behind it.
##
##     Those rows are the CURRENT state of the game, hand-verified on disk (each is re-derivable with a grep for
##     the resource's path AND its uid). When the game finally gets wired — a Talkable pointing at old_man.tres, a
##     QuestStarter in the live level — they FLIP, and that flip is the single best demonstration the tab works.
##     UPDATE the expectations then; never delete the assertions and never widen a guard to make them go green.
##
## ASSERTION NOTE for whoever edits this file: GUT's assert_string_contains(text, search, match_case) takes NO
## message argument — a third argument lands in match_case and the reasoning is silently swallowed. Where a
## failure message carries the WHY, this file asserts on `.contains(...)` with an explicit message instead.

const Reach := preload("res://addons/cybersunday_tools/dock_reach/reach_scan.gd")
const ReachView := preload("res://addons/cybersunday_tools/dock_reach/reach_view.gd")
## The audit panel's quote-aware, length-preserving `#` masker — the same primitive every scanner in this plugin
## masks with. The source-scan tests below run it over reach_view.gd first, because that file's own docstring says
## "No ResourceSaver, no FileAccess.WRITE, no ProjectSettings.save anywhere below": an UNMASKED grep would read
## those words and fail the read-only test on the very comment that promises the contract.
const ScanWiring := preload("res://addons/cybersunday_tools/panel_audit/scan_wiring.gd")

# --- the hand-verified ground truth (see the acceptance tests for how each was checked) ------------------------
const BOOT_SCENE := "res://scenes/computerroom.tscn"          ## project.godot run/main_scene
const START_MENU := "res://scenes/start_menu.tscn"            ## computerroom.gd:29 const START_MENU_SCENE
const GAME_SCENE := "res://scenes/game.tscn"                  ## start_menu.gd:19 const GAME_SCENE
const LEVEL_DATA := "res://resources/levels/trenchboom.tres"  ## game.tscn:33 level = ExtResource("4_gee14")
const LIVE_LEVEL := "res://scenes/levels/trenchboom_test_level.tscn"  ## trenchboom.tres scene =
const BOOT_GLUE := ["res://scripts/ui/computerroom.gd", "res://scripts/ui/start_menu.gd"]

const QUEST_NO_START := "res://resources/quests/clear_the_block.tres"
const QUEST_UNREACHABLE_START := "res://resources/quests/recover_the_package.tres"
const SLICE_LEVEL := "res://scenes/levels/SliceTestLevel.tscn"  ## holds the only QuestStarter.quest in the project
const OLD_MAN := "res://resources/dialogue/old_man.tres"
const NPC_SCENE := "res://scenes/characters/NPC.tscn"           ## instanced BY the live level
const ITEMS_DIR := "res://resources/items"                      ## item_db.gd:10 ITEMS_DIR, opened at :18

## Every .tscn under scenes/levels/ that no reachable file loads. All five are in the roster (levels_authored
## unions in every .tscn in that folder) and all five must read UNREACHABLE — if any of them flips to reachable
## without the game changing, an edge is being invented (the usual culprit: a res:// path quoted in a DOCSTRING,
## e.g. level_root.gd:8's `scenes/levels/LevelTemplate.tscn` or nav_debug_overlay.gd:14's audit_navmesh mention).
const UNREACHABLE_LEVELS := [
	"res://scenes/levels/SliceTestLevel.tscn",
	"res://scenes/levels/TestLevel.tscn",
	"res://scenes/levels/TestLevel_2.tscn",
	"res://scenes/levels/NavSandbox.tscn",
	"res://scenes/levels/LevelTemplate.tscn",
]

## The acceptance pass is memoised: it walks res:// once (378 serialized files today) and every acceptance test
## reads the SAME report, so splitting the ground truth into focused tests costs one scan, not six.
var _acc: Dictionary = {}


# ================================================================================================================
# BARE res:// LITERALS — the edge collect_referenced misses, and the boot chain depends on
# ================================================================================================================

func test_bare_resource_literals_accepts_a_const_scene_path() -> void:
	# The literal shape of computerroom.gd:29 / start_menu.gd:19 — a const, NOT a preload. Without this edge the
	# closure stops at the boot scene and declares the whole game unreachable.
	var text := "const START_MENU_SCENE := \"res://scenes/start_menu.tscn\"\n"
	var out := Reach.bare_resource_literals(text)
	assert_has(out, "res://scenes/start_menu.tscn", "a bare const res:// scene path is an edge")


func test_bare_resource_literals_rejects_an_extensionless_directory() -> void:
	# item_db.gd:10's ITEMS_DIR. A directory is NOT a file edge — it is handled by folder_scan_roots, a different
	# edge kind with a different meaning. Without the required extension every folder literal in the project would
	# become a phantom hop in the printed chain.
	var text := "const ITEMS_DIR := \"res://resources/items\"\n"
	var out := Reach.bare_resource_literals(text)
	assert_eq(out.size(), 0, "an extension-less res:// directory literal is not a file edge: %s" % str(out))


func test_bare_resource_literals_ignores_a_literal_only_in_a_comment() -> void:
	# This project documents call idioms in prose, so masking is load-bearing: an unmasked docstring literal would
	# invent an edge the GAME does not have, and a false GREEN is the one failure this tab must never produce.
	var text := "## Duplicate \"res://scenes/levels/LevelTemplate.tscn\" to start a level.\n" \
		+ "const GAME_SCENE := \"res://scenes/game.tscn\"\t# the real one\n"
	var out := Reach.bare_resource_literals(text)
	assert_false(out.has("res://scenes/levels/LevelTemplate.tscn"), "a literal inside a # comment is NOT an edge")
	assert_has(out, "res://scenes/game.tscn", "the code literal on the same fixture is still collected")


func test_bare_resource_literals_skips_a_load_argument() -> void:
	# load()/preload() arguments are already collected by ContentStats.collect_referenced; re-collecting them here
	# would only duplicate work in the BFS.
	var text := "const S := preload(\"res://scenes/ui/character_creation.tscn\")\n" \
		+ "\tvar r = ResourceLoader.load(\"res://resources/ui/boot_quotes.tres\")\n"
	var out := Reach.bare_resource_literals(text)
	assert_eq(out.size(), 0, "load()/preload() arguments are collect_referenced's job: %s" % str(out))


# ================================================================================================================
# THE FOLDER-SCAN GUARD — the false-positive half, and the constraint that keeps it from eating the report
# ================================================================================================================

func test_folder_scan_roots_finds_the_item_db_shape() -> void:
	# The single most important case in the project: the literal is bound to a const at the top of the file and the
	# open() names the CONST, not the literal. Matching only inline literals would condemn ItemDb's 35 items.
	var text := "const ITEMS_DIR := \"res://resources/items\"\n\nfunc _ready() -> void:\n" \
		+ "\tvar dir := DirAccess.open(ITEMS_DIR)\n"
	var out := Reach.folder_scan_roots(text)
	assert_eq(out, ["res://resources/items"], "a const-bound dir opened by NAME is a folder-scan root")


func test_folder_scan_roots_normalises_a_trailing_slash() -> void:
	# calibers.gd / item_ids.gd spell the same folder with a trailing slash; both must collapse onto ONE root, or
	# the guard fires for "res://resources/items/" while the closure keys members under "res://resources/items".
	var text := "const ITEMS_DIR := \"res://resources/items/\"\n\tvar d := DirAccess.open(ITEMS_DIR)\n"
	var out := Reach.folder_scan_roots(text)
	assert_eq(out, ["res://resources/items"], "a trailing slash is trimmed so the two spellings are one root")


func test_folder_scan_roots_ignores_the_stats_view_shape() -> void:
	# THE CASE THAT WOULD KILL THE FEATURE. stats_view.gd holds 15 extension-less res:// dir literals in a
	# DICTIONARY const — resources/quests/ among them — and opens a loop VARIABLE. If this returned those dirs,
	# every content folder in the game would be whitelisted and the report would go permanently, silently empty.
	# (Belt AND braces: closure() also only evaluates this on files already IN the closure.)
	var text := "const COUNT_DIRS := {\n" \
		+ "\t\"Items\": \"res://resources/items/\", \"Quests\": \"res://resources/quests/\",\n" \
		+ "\t\"Dialogue\": \"res://resources/dialogue/\", \"Loot\": \"res://resources/loot/\",\n" \
		+ "}\n\nfunc _count() -> void:\n\tfor label in COUNT_DIRS:\n\t\tvar dir: String = COUNT_DIRS[label]\n" \
		+ "\t\tvar d := DirAccess.open(dir)\n"
	var out := Reach.folder_scan_roots(text)
	assert_eq(out, [], "a Dictionary const + a loop variable binds NO directory to a name: %s" % str(out))


func test_folder_scan_roots_ignores_a_file_literal_and_the_project_root() -> void:
	# A FILE literal is an ordinary reference edge, and res:// itself holds config, not scanned content — the
	# text_debt.gd / menu_sound_debt.gd shape, which walks the whole project and must whitelist nothing.
	var text := "\tvar a := DirAccess.open(\"res://resources/items/healthpack.tres\")\n" \
		+ "\tvar b := DirAccess.open(\"res://\")\n"
	var out := Reach.folder_scan_roots(text)
	assert_eq(out, [], "neither a file literal nor the project root is a content-scan root: %s" % str(out))


func test_folder_scan_roots_ignores_a_commented_out_open() -> void:
	var text := "const ITEMS_DIR := \"res://resources/items\"\n\t# var dir := DirAccess.open(ITEMS_DIR)\n"
	var out := Reach.folder_scan_roots(text)
	assert_eq(out, [], "a DirAccess.open inside a comment scans nothing at runtime: %s" % str(out))


# ================================================================================================================
# THE CLOSURE — a BFS over injected text, which is what makes it both testable AND cheap
# ================================================================================================================

## The fixture "project" the closure tests walk. a.tscn -> b.tscn -> c.gd -> d.tres, one edge that resolves ONLY
## through the injected uid index, and an isolated e.tres nothing points at.
##
## c.gd carries TWO phantoms in its DOCSTRING, because a .gd's edges come from two collectors and BOTH have to be
## handed masked text: a bare literal (bare_resource_literals masks on its own, so that one holds even if edges()
## regresses) and a preload() CALL — which collect_referenced does not mask, so edges() must feed it the masked
## text or the phantom becomes a real edge. Not hypothetical: this project documents call idioms in prose
## constantly, and a `## ... preload("res://scenes/levels/SliceTestLevel.tscn")` in some docstring would make an
## UNREACHABLE level read as reachable. A false GREEN is the one failure this tab must never produce.
func _fixture_files() -> Dictionary:
	var b := "[gd_scene format=3]\n[ext_resource type=\"Script\" path=\"res://c.gd\" id=\"1\"]\n"
	b += "[ext_resource type=\"Resource\" uid=\"uid://fixtureonly\" id=\"2\"]\n"
	var c := "## Prose naming \"res://phantom.tscn\", which the game never loads.\n"
	c += "## The idiom is preload(\"res://phantom_preload.tscn\") - prose describing a call, not a call.\n"
	c += "const NEXT := \"res://d.tres\"\n"
	var stub := "[gd_resource type=\"Resource\" format=3]\n"
	return {
		"res://a.tscn": "[gd_scene format=3]\n[ext_resource type=\"PackedScene\" path=\"res://b.tscn\" id=\"1\"]\n",
		"res://b.tscn": b,
		"res://c.gd": c,
		"res://d.tres": stub,
		"res://e.tres": stub,
		"res://uid_target.tres": stub,
	}


## The injected reader seam, untyped exactly as the module documents it (`func(p): return fixture[p]`): the BFS
## pulls text ONLY for the paths it pops, so a test needs a dictionary, not a project.
func _reader(files: Dictionary) -> Callable:
	return func(p):
		return str(files.get(p, ""))


func _no_dirs() -> Callable:
	return func(_d):
		return []


func test_closure_reaches_transitively_and_leaves_the_isolated_file_out() -> void:
	var uid_index := {"uid://fixtureonly": "res://uid_target.tres"}
	var cl := Reach.closure(["res://a.tscn"], _reader(_fixture_files()), uid_index, _no_dirs())
	var reached: Dictionary = cl["reached"]
	assert_true(reached.has("res://b.tscn"), "a direct ext_resource path edge is followed")
	assert_true(reached.has("res://c.gd"), "a script ext_resource edge is followed")
	assert_true(reached.has("res://d.tres"), "a BARE res:// literal inside a .gd carries the chain onward")
	assert_true(reached.has("res://uid_target.tres"), "a uid-only edge resolves through the INJECTED index")
	assert_false(reached.has("res://e.tres"), "nothing points at e.tres — it stays outside the closure")
	assert_false(reached.has("res://phantom.tscn"), "a literal quoted in a docstring is not an edge")
	# The dangerous half of the same rule, and the one bare_resource_literals cannot cover on its own: a preload()
	# quoted in a DOCSTRING is collect_referenced's regex shape, so edges() must hand IT masked text too. Feeding it
	# the raw source instead is a one-word change that would make an unreachable level report as reachable.
	assert_false(reached.has("res://phantom_preload.tscn"),
		"a preload() quoted in a DOCSTRING is not an edge either — collect_referenced is fed MASKED .gd text")


func test_closure_records_depth_parent_and_why_for_every_hop() -> void:
	var uid_index := {"uid://fixtureonly": "res://uid_target.tres"}
	var cl := Reach.closure(["res://a.tscn"], _reader(_fixture_files()), uid_index, _no_dirs())
	var depth_of: Dictionary = cl["depth_of"]
	var parent_of: Dictionary = cl["parent_of"]
	var via: Dictionary = cl["via"]
	assert_eq(int(depth_of["res://a.tscn"]), 0, "a root sits at depth 0")
	assert_eq(int(depth_of["res://d.tres"]), 3, "a -> b -> c.gd -> d is three hops")
	assert_eq(str(parent_of["res://d.tres"]), "res://c.gd", "the parent is the file that PULLED it in")
	assert_eq(str(parent_of["res://a.tscn"]), "", "a root has no parent")
	assert_eq(str(via["res://a.tscn"]), Reach.VIA_ROOT, "roots are tagged as roots")
	assert_eq(str(via["res://d.tres"]), Reach.VIA_REF, "an explicit reference is tagged as a reference")


func test_chain_to_and_content_chain_print_the_path_that_was_followed() -> void:
	# A reachability gauge nobody can audit is a green light nobody should trust: the report must be able to show
	# its work. content_chain elides the .gd GLUE hops (they carry the edge, they are not places a player goes) but
	# always keeps the first and last, so the chain still states where it started and where it ended.
	var cl := Reach.closure(["res://a.tscn"], _reader(_fixture_files()), {}, _no_dirs())
	var parent_of: Dictionary = cl["parent_of"]
	var full := Reach.chain_to("res://d.tres", parent_of)
	assert_eq(full, ["res://a.tscn", "res://b.tscn", "res://c.gd", "res://d.tres"], "the full chain is root-first")
	assert_eq(Reach.content_chain(full), ["res://a.tscn", "res://b.tscn", "res://d.tres"], "the .gd glue hop is elided")
	assert_eq(Reach.chain_to("res://e.tres", parent_of), [], "a file that was never reached has no chain")


func test_closure_terminates_on_a_reference_cycle() -> void:
	# Two scenes pointing at each other. First-visit-wins is what terminates this AND what makes depth/parent
	# describe the SHORTEST chain; without it the BFS would queue forever.
	var loop_b := "[ext_resource path=\"res://loop_a.tscn\" id=\"1\"]\n"
	loop_b += "[ext_resource path=\"res://loop_c.tres\" id=\"2\"]\n"
	var files := {
		"res://loop_a.tscn": "[ext_resource path=\"res://loop_b.tscn\" id=\"1\"]\n",
		"res://loop_b.tscn": loop_b,
		"res://loop_c.tres": "[gd_resource type=\"Resource\" format=3]\n",
	}
	var cl := Reach.closure(["res://loop_a.tscn"], _reader(files), {}, _no_dirs())
	var reached: Dictionary = cl["reached"]
	var parent_of: Dictionary = cl["parent_of"]
	assert_eq(reached.size(), 3, "the cycle is walked exactly once: %s" % str(reached.keys()))
	assert_true(reached.has("res://loop_c.tres"), "the file BEYOND the cycle is still reached")
	assert_eq(str(parent_of["res://loop_a.tscn"]), "", "the back-edge never re-parents the root")


func test_closure_reports_an_unreadable_file_as_a_skip() -> void:
	# A load()/read can come back empty mid-reimport (the designer usually has the editor open). Reporting a CLEAN
	# result over a file nobody actually read is the exact lie this tab exists to catch, so it becomes a SKIP.
	var files := {"res://root.tscn": "[ext_resource path=\"res://half_written.tscn\" id=\"1\"]\n"}
	var cl := Reach.closure(["res://root.tscn"], _reader(files), {}, _no_dirs())
	var reached: Dictionary = cl["reached"]
	assert_has(cl["unread"], "res://half_written.tscn", "an empty read is surfaced as a skip, never silenced")
	assert_true(reached.has("res://half_written.tscn"), "it is still REACHED — we just could not follow through it")


func test_closure_marks_folder_scan_members_reached_and_names_who_declared_the_root() -> void:
	var files := {
		"res://boot.gd": "const ITEMS_DIR := \"res://resources/items\"\n\tvar dir := DirAccess.open(ITEMS_DIR)\n",
	}
	var members := {"res://resources/items": ["res://resources/items/knife.tres", "res://resources/items/ammo.tres"]}
	var dir_members := func(d):
		return members.get(d, [])
	var cl := Reach.closure(["res://boot.gd"], _reader(files), {}, dir_members)
	var reached: Dictionary = cl["reached"]
	var via: Dictionary = cl["via"]
	var folder_roots: Dictionary = cl["folder_roots"]
	assert_true(reached.has("res://resources/items/knife.tres"), "a folder-scanned member is USED, not an orphan")
	assert_true(reached.has("res://resources/items/ammo.tres"), "every member of the scanned dir is spared")
	assert_eq(str(via["res://resources/items/knife.tres"]), Reach.VIA_SCAN, "and it is tagged as a SCAN pull-in")
	assert_eq(str(folder_roots.get("res://resources/items", "")), "res://boot.gd", "the guard names who declared the root")


func test_closure_never_reads_a_binary_res_file() -> void:
	# PERFORMANCE IS A CORRECTNESS CONSTRAINT: addons/text_to_speech/voices/ alone is 59 MB of .flitevox.res with
	# no res:// edges in it, and Godot Strings are UTF-32 internally. Dropping "res" from this tab's ext list is
	# what keeps a tab CLICK from spiking hundreds of MB. It is still marked reached — we just never read it.
	assert_false(Reach.SCANNED_EXTS.has("res"), "\"res\" is deliberately NOT scanned (the 59 MB voice blobs)")
	var reads: Array = []
	var reader := func(p):
		reads.append(p)
		return ""
	var cl := Reach.closure(["res://voices/cmu_us_slt.flitevox.res", "res://a.tscn"], reader, {}, _no_dirs())
	var reached: Dictionary = cl["reached"]
	assert_false(reads.has("res://voices/cmu_us_slt.flitevox.res"), "the binary .res is never opened: %s" % str(reads))
	assert_has(reads, "res://a.tscn", "a scannable extension IS read")
	assert_true(reached.has("res://voices/cmu_us_slt.flitevox.res"), "it is still reached, just never walked through")
	assert_false(cl["unread"].has("res://voices/cmu_us_slt.flitevox.res"), "a file we chose not to read is not a SKIP")


func test_normalize_ref_handles_every_spelling_a_root_or_edge_arrives_in() -> void:
	assert_eq(Reach.normalize_ref("*res://managers/GameState.gd", {}), "res://managers/GameState.gd",
		"ProjectSettings marks a singleton autoload with a leading *")
	assert_eq(Reach.normalize_ref("*uid://fixtureonly", {"uid://fixtureonly": "res://y.tscn"}), "res://y.tscn",
		"two autoloads (FreezeFrame, DialogueManager) are uid-ONLY — no path at all")
	assert_eq(Reach.normalize_ref("res://x.tscn::3", {}), "res://x.tscn", "a sub-resource ref names the owning FILE")
	assert_eq(Reach.normalize_ref("res://x.tres.remap", {}), "res://x.tres", "an exported build's .remap is stripped")
	assert_eq(Reach.normalize_ref("PlayerSpawn", {}), "", "a value that names no res:// file is dropped, not guessed")


# ================================================================================================================
# SERIALIZED READING — ext_resource rows and the fields that hold a Resource REFERENCE
# ================================================================================================================

func test_ext_resource_index_captures_path_and_id_independently() -> void:
	# Attribute order is not guaranteed by the serializer, and a row can carry a path with no uid (or a uid with no
	# path). A uid-only row must be left UNRESOLVED rather than fake-resolved onto some other row's file. (The
	# separate uid-versus-id trap has its own test below; the two RESOLVING rows here are deliberately uid-free, so a
	# failure on either of them means the attribute-ORDER handling broke and not the id capture. The third row is the
	# uid-ONLY one — it carries a uid on purpose, and is expected to resolve to nothing at all.)
	var text := "[gd_scene load_steps=3 format=3]\n" \
		+ "[ext_resource type=\"Script\" path=\"res://scripts/components/quest_starter.gd\" id=\"8_qstart\"]\n" \
		+ "[ext_resource id=\"9_quest\" type=\"Resource\" path=\"res://resources/quests/recover_the_package.tres\"]\n" \
		+ "[ext_resource type=\"Resource\" uid=\"uid://nopathrow\" id=\"10_uidonly\"]\n"
	var index := Reach.ext_resource_index(text)
	assert_eq(str(index.get("8_qstart", "")), "res://scripts/components/quest_starter.gd", "path= before id= resolves")
	assert_eq(str(index.get("9_quest", "")), "res://resources/quests/recover_the_package.tres", "id= before path= resolves too")
	assert_false(index.has("10_uidonly"), "a uid-only row has no path to resolve to — it is left out, not invented")


func test_ext_resource_index_is_not_fooled_by_the_uid_attribute() -> void:
	# The row below is VERBATIM from scenes/levels/SliceTestLevel.tscn:13 — and `uid=` before `id=` is the order
	# Godot's own serializer writes, so this is the shape of nearly every ext_resource row in the project.
	#
	# THE TRAP: an unanchored `id="([^"]+)"` matches INSIDE `uid="…"` (the leftmost match wins), so the row gets
	# keyed by its uid string instead of by "9_quest". Then ExtResource("9_quest") resolves to "", every quest
	# start site becomes unresolvable, and the report degrades a WIRED quest to NO START SITE — a wrong verdict
	# that still looks like a finding, which is the hardest kind of failure to notice. The id capture must be
	# word-boundary anchored (\bid=") for the same reason `path=` already is unambiguous.
	var row := "[ext_resource type=\"Resource\" uid=\"uid://cgt8fc4lpnl0a\" path=\"res://resources/quests/recover_the_package.tres\" id=\"9_quest\"]\n"
	var index := Reach.ext_resource_index(row)
	assert_eq(str(index.get("9_quest", "")), QUEST_UNREACHABLE_START,
		"the ExtResource ID keys the row — the uid must not be captured as the id")
	assert_false(index.has("uid://cgt8fc4lpnl0a"), "the uid is not an ExtResource id and must not key the index")


func test_ext_resource_ids_discards_the_array_element_type_script() -> void:
	# THE TRAP, taken verbatim from resources/quests/clear_the_block.tres:31 — the FIRST ExtResource on the line is
	# the element-TYPE script (quest_objective.gd), not an element. Taking the first match would report a quest's
	# objective SCRIPT as the started quest.
	var value := "Array[ExtResource(\"1_tveky\")]([SubResource(\"Resource_1cldg\"), SubResource(\"Resource_0imx4\")])"
	var ids := Reach.ext_resource_ids(value)
	assert_eq(ids, [], "the Array[...] type bracket holds no element references: %s" % str(ids))


func test_ext_resource_ids_keeps_the_elements_outside_the_type_bracket() -> void:
	var value := "Array[ExtResource(\"1_tveky\")]([ExtResource(\"9_quest\")])"
	var ids := Reach.ext_resource_ids(value)
	assert_eq(ids, ["9_quest"], "only the id INSIDE the value survives the type-bracket discard")


func test_quest_start_sites_matches_all_three_component_fields() -> void:
	var text := "[gd_scene format=3]\n" \
		+ "[ext_resource type=\"Resource\" path=\"res://resources/quests/recover_the_package.tres\" id=\"9_quest\"]\n" \
		+ "[node name=\"QuestStarter\" type=\"Area3D\" parent=\"Objects\"]\nquest = ExtResource(\"9_quest\")\n" \
		+ "[node name=\"Trigger\" type=\"Area3D\" parent=\"Objects\"]\nstart_quest = ExtResource(\"9_quest\")\n" \
		+ "[sub_resource type=\"Resource\" id=\"Choice_1\"]\nstart_quest_on_choice = ExtResource(\"9_quest\")\n"
	var sites := Reach.quest_start_sites(text)
	var labels: Array = []
	for s in sites:
		var sd := s as Dictionary
		assert_eq(str(sd["path"]), "res://resources/quests/recover_the_package.tres", "each site resolves to the quest file")
		labels.append(str(sd["label"]))
	assert_eq(sites.size(), 3, "all three START paths are found: %s" % str(labels))
	assert_has(labels, "QuestStarter.quest", "a finding must name the COMPONENT, not a bare \"quest\"")
	assert_has(labels, "TriggerVolume.start_quest", "the TriggerVolume start path is found")
	assert_has(labels, "DialogueChoice.start_quest_on_choice", "the DialogueChoice start path is found")


func test_quest_start_sites_captures_the_node_name_of_the_matched_block() -> void:
	# The report row reads 'QuestStarter.quest on node "QuestBoard" in SliceTestLevel.tscn' so the designer can find
	# the starter in the scene dock — the node name is what they type into its filter. It must come from the block
	# the field was matched in (never a neighbouring node), and a site inside a [sub_resource] block (a
	# DialogueChoice in a .tres) has no node to name, so it carries "".
	var text := "[gd_scene format=3]\n" \
		+ "[ext_resource type=\"Resource\" path=\"res://resources/quests/recover_the_package.tres\" id=\"9_quest\"]\n" \
		+ "[node name=\"Decoy\" type=\"Node3D\" parent=\"Objects\"]\n" \
		+ "[node name=\"QuestBoard\" type=\"Area3D\" parent=\"Objects\" groups=[\"interact\"]]\nquest = ExtResource(\"9_quest\")\n" \
		+ "[node name=\"WalkIn\" type=\"Area3D\" parent=\"Objects\"]\nstart_quest = ExtResource(\"9_quest\")\n" \
		+ "[sub_resource type=\"Resource\" id=\"Choice_1\"]\nstart_quest_on_choice = ExtResource(\"9_quest\")\n"
	var sites := Reach.quest_start_sites(text)
	assert_eq(sites.size(), 3, "three sites, one per block: %s" % str(sites))
	var node_of := {}
	for s in sites:
		var sd := s as Dictionary
		node_of[str(sd["label"])] = str(sd.get("node", "<missing>"))
	assert_eq(str(node_of.get("QuestStarter.quest", "")), "QuestBoard", "the [node name=...] of the matched block is captured")
	assert_eq(str(node_of.get("TriggerVolume.start_quest", "")), "WalkIn", "each site names ITS OWN node, not a neighbour's")
	assert_eq(str(node_of.get("DialogueChoice.start_quest_on_choice", "x")), "", "a [sub_resource] block has no node name — \"\", never invented")


func test_block_node_name_reads_only_a_node_header() -> void:
	# The header line taken from scenes/levels/SliceTestLevel.tscn:347 (the real QuestStarter block), plus the shape
	# with a groups=[...] attribute — its `]` must not cut the capture short (name is always the FIRST attribute).
	assert_eq(Reach.block_node_name("[node name=\"QuestStarter\" type=\"Area3D\" parent=\"Objects/QuestBoard\" node_paths=PackedStringArray(\"highlight_target\")]\nscript = ExtResource(\"8_qstart\")\n"),
		"QuestStarter", "the name attribute of a [node ...] header")
	assert_eq(Reach.block_node_name("[node name=\"NavigationRegion3D\" type=\"NavigationRegion3D\" parent=\".\" groups=[\"navmesh\"]]\n"),
		"NavigationRegion3D", "a groups=[...] bracket later on the header does not truncate the capture")
	assert_eq(Reach.block_node_name("[sub_resource type=\"Resource\" id=\"Choice_1\"]\nstart_quest_on_choice = ExtResource(\"9_quest\")\n"),
		"", "a [sub_resource] block is not a node")
	assert_eq(Reach.block_node_name("[resource]\nid = &\"clear_the_block\"\n"), "", "nor is the [resource] block")
	assert_eq(Reach.block_node_name("quest = ExtResource(\"9_quest\")\n"), "", "a bare fixture with no header names nothing")


func test_quest_start_sites_ignores_quest_id_STRING_fields() -> void:
	# The reference-vs-string distinction is the entire reason this module exists instead of another
	# scan_wiring.QUEST_ID_FIELDS entry: an id string is not a start site, and `quest` must not match
	# `required_quest_id` (nor `start_quest` match `start_quest_on_choice` — each field is anchored and independent).
	var text := "[resource]\nid = &\"clear_the_block\"\nprereq_quest_id = &\"recover_package\"\n" \
		+ "required_quest_id = &\"recover_package\"\ncomplete_quest_id = &\"recover_package\"\n"
	var sites := Reach.quest_start_sites(text)
	assert_eq(sites.size(), 0, "an id STRING field starts nothing: %s" % str(sites))


func test_quest_start_sites_discards_an_array_element_type_in_a_start_field() -> void:
	# The type-bracket discard has to survive the field matcher too, or a start site would report the element-type
	# SCRIPT (quest_objective.gd) as the quest a QuestStarter starts.
	var text := "[gd_scene format=3]\n" \
		+ "[ext_resource type=\"Script\" path=\"res://scripts/quests/quest_objective.gd\" id=\"1_tveky\"]\n" \
		+ "[ext_resource type=\"Resource\" path=\"res://resources/quests/recover_the_package.tres\" id=\"9_quest\"]\n" \
		+ "[node name=\"QuestStarter\" type=\"Area3D\"]\nquest = Array[ExtResource(\"1_tveky\")]([ExtResource(\"9_quest\")])\n"
	var sites := Reach.quest_start_sites(text)
	assert_eq(sites.size(), 1, "exactly one start site, not one per ExtResource on the line: %s" % str(sites))
	assert_eq(str((sites[0] as Dictionary)["path"]), "res://resources/quests/recover_the_package.tres",
		"the element-type script is never reported as the started quest")


func test_resource_field_ref_reads_the_resource_block() -> void:
	# A LevelData's scene / a Quest's next_quest must be read off the [resource] block, not off some unrelated
	# sub_resource that happens to carry a field of the same name.
	# The ext_resource rows are the real serialization (uid= AND path=, in Godot's own attribute order) taken from
	# resources/levels/trenchboom.tres — this is exactly the text the glue feeds in when it reads a LevelData.scene.
	var text := "[gd_resource type=\"Resource\" script_class=\"LevelData\" format=3]\n" \
		+ "[ext_resource type=\"PackedScene\" uid=\"uid://dd2gyjqq3ja1d\" path=\"res://scenes/levels/trenchboom_test_level.tscn\" id=\"1_d34lp\"]\n" \
		+ "[ext_resource type=\"PackedScene\" uid=\"uid://decoyuid\" path=\"res://scenes/levels/decoy.tscn\" id=\"2_decoy\"]\n" \
		+ "[sub_resource type=\"Resource\" id=\"Sub_1\"]\nscene = ExtResource(\"2_decoy\")\n" \
		+ "[resource]\nscene = ExtResource(\"1_d34lp\")\n"
	assert_eq(Reach.resource_field_ref(text, "scene"), LIVE_LEVEL, "the [resource] block wins over a sub_resource")
	assert_eq(Reach.resource_field_ref(text, "next_quest"), "", "an absent field resolves to \"\", never to a guess")


func test_declares_script_class_is_a_one_line_header_gate() -> void:
	var text := "[gd_resource type=\"Resource\" script_class=\"Quest\" format=3 uid=\"uid://cl5xwy1ad8jxi\"]\n"
	assert_true(Reach.declares_script_class(text, "Quest"), "the header gate identifies a .tres without load()ing it")
	assert_false(Reach.declares_script_class(text, "LevelData"), "and does not match a different class")


# ================================================================================================================
# VERDICTS — two independent axes, three actionable answers
# ================================================================================================================

func test_classify_quest_returns_three_distinct_verdicts() -> void:
	# The two failures need OPPOSITE fixes, which is why they are not collapsed into one boolean: NO START SITE
	# means "wire it", START SITE NOT REACHABLE means "its HOST is the problem, not the wiring".
	var reached := {"res://scenes/levels/live.tscn": true}
	var quest := "res://resources/quests/q.tres"
	var in_live := [{"file": "res://scenes/levels/live.tscn", "field": "quest", "label": "QuestStarter.quest"}]
	var in_orphan := [{"file": "res://scenes/levels/orphan.tscn", "field": "quest", "label": "QuestStarter.quest"}]
	assert_eq(Reach.classify_quest(quest, [], reached), Reach.VERDICT_NO_START, "no site anywhere -> wire it")
	assert_eq(Reach.classify_quest(quest, in_orphan, reached), Reach.VERDICT_UNREACHABLE_START,
		"wired, but inside a scene the boot chain never loads")
	assert_eq(Reach.classify_quest(quest, in_live, reached), Reach.VERDICT_OK, "wired inside a reached scene")
	assert_ne(Reach.VERDICT_NO_START, Reach.VERDICT_UNREACHABLE_START, "the two failures must read differently")
	assert_ne(Reach.VERDICT_OK, Reach.VERDICT_UNREACHABLE_START, "and neither may read as OK")
	# The WORDING is a designer-facing surface, not an internal enum: it is what the Tree prints and what the
	# acceptance rows in docs/CYBER_SUNDAY_PLUGIN_QA.md quote verbatim. Every other assertion in this file compares
	# against the consts, so a rename would ship green while the docs went stale — pin the three strings once, here.
	assert_eq(Reach.VERDICT_NO_START, "NO START SITE", "the printed wording is pinned (the QA doc quotes it)")
	assert_eq(Reach.VERDICT_UNREACHABLE_START, "START SITE NOT REACHABLE", "so is the second failure's wording")
	assert_eq(Reach.VERDICT_OK, "OK", "and the pass wording")


func test_classify_quest_ignores_a_site_inside_the_quests_own_file() -> void:
	var quest := "res://resources/quests/q.tres"
	var self_site := [{"file": quest, "field": "next_quest", "label": Reach.CHAIN_FIELD}]
	assert_eq(Reach.classify_quest(quest, self_site, {quest: true}), Reach.VERDICT_NO_START,
		"a resource cannot be its own start site")


func test_inherit_chained_starts_gives_a_stage_its_parent_as_a_site() -> void:
	# Quest.next_quest is the 4th start path and is not a component field at all: a stage that is only ever started
	# by the previous stage completing must not be reported as unwired.
	var sites_by_quest := {"res://q/one.tres": [{"file": "res://scenes/live.tscn", "field": "quest", "label": "QuestStarter.quest"}]}
	var next_of := {"res://q/one.tres": "res://q/two.tres"}
	var out := Reach.inherit_chained_starts(sites_by_quest, next_of)
	assert_true(out.has("res://q/two.tres"), "a chained stage with no wiring of its own still gets an entry")
	var two: Array = out["res://q/two.tres"]
	assert_eq(two.size(), 1, "exactly one inherited site")
	assert_eq(str((two[0] as Dictionary)["file"]), "res://q/one.tres", "its start site is the parent quest FILE")
	assert_eq(str((two[0] as Dictionary)["label"]), Reach.CHAIN_FIELD, "labelled as the chain field, not a component")
	assert_false(sites_by_quest.has("res://q/two.tres"), "the caller's map is NOT mutated")
	assert_eq((sites_by_quest["res://q/one.tres"] as Array).size(), 1, "nor is the parent's own site list")


# ================================================================================================================
# THE REPORT — assembled from a closure result plus the glue's disk survey
# ================================================================================================================

## The report rows are read BY PATH, never by index, so adding content never shuffles an assertion onto the wrong
## subject. Returns {} when no row matches, which the caller asserts on explicitly.
func _row_for(rows: Array, key: String, value: String) -> Dictionary:
	for r in rows:
		if str((r as Dictionary).get(key, "")) == value:
			return r as Dictionary
	return {}


func test_build_report_counts_verdicts_levels_dialogue_and_skips() -> void:
	var cl := {
		"reached": {
			"res://scenes/wired.tscn": true, "res://scenes/levels/live.tscn": true,
			"res://resources/items/knife.tres": true,
		},
		"depth_of": {"res://scenes/wired.tscn": 0, "res://scenes/levels/live.tscn": 2, "res://resources/items/knife.tres": 1},
		"parent_of": {"res://scenes/wired.tscn": "", "res://scenes/levels/live.tscn": "res://scenes/wired.tscn",
			"res://resources/items/knife.tres": "res://scripts/items/item_db.gd"},
		"via": {"res://scenes/wired.tscn": Reach.VIA_ROOT, "res://scenes/levels/live.tscn": Reach.VIA_REF,
			"res://resources/items/knife.tres": Reach.VIA_SCAN},
		"folder_roots": {"res://resources/items": "res://scripts/items/item_db.gd"},
		"unread": ["res://scenes/half_written.tscn"],
	}
	var found := {
		"levels_wired": ["res://scenes/levels/live.tscn", "res://scenes/levels/orphan.tscn"],
		"levels_authored": ["res://scenes/levels/live.tscn", "res://scenes/levels/orphan.tscn", "res://scenes/levels/unwired.tscn"],
		"quests": ["res://q/lonely.tres", "res://q/hosted.tres"],
		"quest_sites": {"res://q/hosted.tres": [{"file": "res://scenes/levels/orphan.tscn", "field": "quest", "label": "QuestStarter.quest", "node": "QuestBoard"}]},
		"quest_next": {},
		"dialogue": ["res://d/never_reached.tres"],
		"skipped": ["res://scenes/locked.tscn"],
	}
	var report := Reach.build_report(cl, found)
	var counts: Dictionary = report["counts"]

	assert_eq(int(counts["levels_total"]), 3, "the roster UNIONS wired levels with everything authored in the folder")
	assert_eq(int(counts["levels_reachable"]), 1, "only the level the closure reached counts as reachable")
	var orphan := _row_for(report["levels"], "path", "res://scenes/levels/orphan.tscn")
	assert_true(bool(orphan.get("wired", false)), "a LevelData points at orphan.tscn — it needs its LOADER fixed")
	var unwired := _row_for(report["levels"], "path", "res://scenes/levels/unwired.tscn")
	assert_false(bool(unwired.get("wired", true)), "unwired.tscn has no LevelData at all — a different fix")

	assert_eq(int(counts["quests_total"]), 2, "every quest found is rostered, sites or not")
	assert_eq(int(counts["quests_no_start"]), 1, "lonely.tres has no start site anywhere")
	assert_eq(int(counts["quests_unreachable_start"]), 1, "hosted.tres is wired inside an unreachable level")
	assert_eq(int(counts["quests_ok"]), 0, "neither quest can be started by a player")
	var hosted := _row_for(report["quests"], "path", "res://q/hosted.tres")
	assert_eq(str(hosted.get("verdict", "")), Reach.VERDICT_UNREACHABLE_START, "the verdict rides on the row")
	var hosted_sites: Array = hosted.get("sites", [])
	assert_eq(hosted_sites.size(), 1, "its start site is reported so the designer knows WHERE to look")
	assert_false(bool((hosted_sites[0] as Dictionary)["reachable"]), "and that the site's host is not reached")
	assert_eq(str((hosted_sites[0] as Dictionary).get("node", "")), "QuestBoard",
		"the scene node holding the starter rides through to the row, so the tab can print 'on node \"QuestBoard\"'")

	assert_eq(int(counts["dialogue_total"]), 1, "the dialogue roster is the glue's survey")
	assert_eq(int(counts["dialogue_reachable"]), 0, "nothing reachable points at it")

	assert_eq(int(counts["skipped"]), 2, "the glue's unreadable files and the closure's unread files are MERGED")
	assert_has(report["skipped"], "res://scenes/half_written.tscn", "the closure's own unread file is surfaced")
	assert_has(report["skipped"], "res://scenes/locked.tscn", "as is the survey's")

	assert_eq(str(report["chain_leaf"]), "res://scenes/levels/live.tscn", "the chain lands in the shallowest reachable level")
	assert_eq(report["chain"], ["res://scenes/wired.tscn", "res://scenes/levels/live.tscn"], "and the chain is printable")

	assert_eq(int(counts["folder_scan_roots"]), 1, "the guard's receipt is part of the report")
	assert_eq(int(counts["folder_scan_members"]), 1, "including how many files it spared from the orphan list")
	var root_row := _row_for(report["folder_roots"], "dir", "res://resources/items")
	assert_eq(str(root_row.get("declared_by", "")), "res://scripts/items/item_db.gd", "and which file declared it")


func test_build_report_values_are_plain_strings_not_stringnames() -> void:
	# JSON.stringify does NOT fail on a StringName — it silently COERCES it into a quoted String and the document
	# re-parses fine, so a round-trip guard is blind to exactly the bug it looks like it is catching. The only real
	# check is the TYPE itself, which is why nothing here is wrapped in String() first.
	var found := {"quests": ["res://q/one.tres"], "levels_authored": ["res://scenes/levels/a.tscn"],
		"dialogue": ["res://d/a.tres"]}
	var report := Reach.build_report({"reached": {}, "depth_of": {}, "parent_of": {}, "via": {}}, found)
	var quest := (report["quests"] as Array)[0] as Dictionary
	assert_eq(typeof(quest["path"]), TYPE_STRING, "a quest path is a String, not a StringName")
	assert_eq(typeof(quest["verdict"]), TYPE_STRING, "so is its verdict")
	var level := (report["levels"] as Array)[0] as Dictionary
	assert_eq(typeof(level["path"]), TYPE_STRING, "so is a level path")
	assert_eq(typeof(level["reachable"]), TYPE_BOOL, "and reachability is a plain bool")


# ================================================================================================================
# THE TAB ITSELF — construct smoke + the two contracts a future edit could silently break
# ================================================================================================================

func test_reach_view_constructs() -> void:
	# Off-tree: _init builds the widgets, but is_visible_in_tree() is false outside a tree, so constructing the tab
	# does NOT kick off a project walk.
	var v = ReachView.new()
	assert_not_null(v, "the Reach tab constructs (compiles + _init builds UI off-tree)")
	assert_eq(v.name, "Reach")
	# The Quest / Dialogue tabs' Check Reach buttons do Host.show_tab("Reach") then call("rescan") — a rename here
	# would leave those buttons switching tabs and silently re-running nothing.
	assert_true(v.has_method("rescan"), "rescan() is the public entry the Check Reach handoffs call")
	assert_eq(v._status.text, ReachView.MSG_IDLE, "idle status is one imperative next step, not a blank line")
	assert_eq(v._status.tooltip_text, v._status.text, "the status tooltip mirrors the text from the first write")
	assert_eq(v._status.max_lines_visible, 2, "the status Label is clamped to two lines (the tooltip carries the rest)")
	v.free()


func test_reach_view_status_leads_with_the_verdict_then_the_counts() -> void:
	# The status is the one line a designer reads without opening the tree, so its shape is pinned: the verdict in
	# plain words FIRST, then the denominators — the numbers that make "0 problems out of 0 looked at" and "0 problems
	# out of 378 looked at" read differently. Off-tree: _status_text is a pure formatter over a counts dictionary.
	var v = ReachView.new()
	var counts := {
		"quests_ok": 1, "quests_total": 2, "levels_reachable": 1, "levels_total": 5,
		"dialogue_reachable": 2, "dialogue_total": 3, "reached": 412,
		"folder_scan_roots": 1, "folder_scan_members": 18, "skipped": 0,
	}
	var line: String = v._status_text(counts, 15, 378, false)
	assert_true(line.begins_with("Quests: 1 of 2 can be started by a player -- Levels: 1 of 5 are loaded from the boot scene -- Conversations: 2 of 3 reachable."),
		"the verdict leads, quests first (they are why the tab exists): %s" % line)
	assert_true(line.ends_with("Scanned 378 files, walked 412 from 15 boot roots, 1 folder loaded whole (18 files), 0 unreadable, 0 start sites unmatched."),
		"then the denominators in plain words with real plurals: %s" % line)
	assert_false(line.contains("SUSPECT"), "no capitalised token outside the verdict words")
	var bad: String = v._status_text(counts, 15, 378, true)
	assert_true(bad.begins_with("Scan incomplete -- "), "a degenerate scan leads with the warning, in words: %s" % bad)
	assert_true(bad.contains("press Scan again"), "and says what to do about it")
	assert_true(bad.contains("Quests: 1 of 2"), "the verdict still follows, so the two-line Label shows both")
	v.free()


func test_reach_view_site_rows_name_the_node_and_the_file() -> void:
	# 'QuestStarter.quest on node "QuestStarter" in SliceTestLevel.tscn' — file NAME in the row (the res:// path rides
	# on the tooltip), the node so the designer can find it in the scene dock, and no node clause at all for a site
	# inside a resource (a DialogueChoice), where there is no node to name.
	assert_eq(ReachView._site_where("QuestStarter", SLICE_LEVEL), "on node \"QuestStarter\" in SliceTestLevel.tscn",
		"a scene-node site names the node and the file, not the path")
	assert_eq(ReachView._site_where("", OLD_MAN), "in old_man.tres", "a resource site names only the file")
	assert_eq(ReachView._count(1, "hop", "hops"), "1 hop", "singular")
	assert_eq(ReachView._count(5, "hop", "hops"), "5 hops", "plural — never a hand-rolled (s)")


func test_reach_view_double_click_opens_a_scene_as_a_scene() -> void:
	# A site row's file is the .tscn HOLDING the starter, so a double-click must land the designer IN that scene
	# (open_scene_from_path), not merely show a PackedScene in the Inspector. Source-scanned like the other tab
	# contracts: the handler needs a live editor. The Scan button and its "Scanning..." feedback are pinned beside it
	# — Rescan/Refresh mean other things elsewhere in the panel, and a long walk with no feedback reads as a hang.
	var src := FileAccess.get_file_as_string("res://addons/cybersunday_tools/dock_reach/reach_view.gd")
	assert_ne(src, "", "reach_view.gd source should be readable")
	assert_true(src.contains("EditorInterface.open_scene_from_path("), "a .tscn row opens as the edited scene")
	assert_true(src.contains("EditorInterface.edit_resource("), "any other file keeps the Inspector / script editor route")
	assert_true(src.contains("EditorInterface.select_file("), "and the file is revealed in the FileSystem dock")
	assert_true(src.contains("text = \"Scan\""), "the one verb on this tab is Scan")
	assert_false(src.contains("\"Rescan\""), "Rescan is retired — it is not a panel verb")
	assert_true(src.contains("\"Scanning...\""), "the walk announces itself before it holds the main thread")
	assert_true(src.contains("await get_tree().process_frame"), "and yields one frame so that announcement paints")


func test_reach_view_bounds_its_own_height() -> void:
	# A TabContainer's minimum is the CURRENT tab's minimum, and the editor's bottom splitter keeps whatever height it
	# grew to — so one tall tab, once shown, leaves the panel tall for every tab after it, and this plugin has TWICE
	# shipped a tab that pushed the panel past the bottom of the screen that way. Source-scanned rather than
	# measured: an off-tree Control has no layout pass to measure, and what must not regress is the STRUCTURE (a
	# small floor + no horizontal growth).
	var src := FileAccess.get_file_as_string("res://addons/cybersunday_tools/dock_reach/reach_view.gd")
	assert_ne(src, "", "reach_view.gd source should be readable")
	assert_true(src.contains("ScrollContainer.SCROLL_MODE_DISABLED"),
		"a long res:// path must never widen the bottom panel — horizontal scrolling stays disabled")
	assert_true(src.contains("custom_minimum_size = Vector2(0, BODY_MIN_HEIGHT)"),
		"the scrolled body carries the tab's only vertical minimum")
	assert_lte(ReachView.BODY_MIN_HEIGHT, 120.0, "the body floor stays small (mirrors content_dock / stats_view)")


func test_reach_view_is_read_only() -> void:
	# Read-only tabs must STAY read-only unless the UI label and the authoring docs make a write explicit. Reach
	# reports; it writes nothing, which is also why the plugin's preview/confirm/report-changed-paths write contract
	# does not apply to it and cannot be got wrong. Scanned over MASKED source: the file's own docstring names all
	# three of these as things it does not do, and a raw grep would trip on the promise instead of a violation.
	var code := ScanWiring._mask_comments(FileAccess.get_file_as_string("res://addons/cybersunday_tools/dock_reach/reach_view.gd"))
	assert_ne(code, "", "reach_view.gd source should be readable")
	assert_false(code.contains("ResourceSaver"), "Reach must never save a resource")
	assert_false(code.contains("FileAccess"), "Reach must never touch a file directly — reads go through ScanCache")
	assert_false(code.contains("ProjectSettings.save"), "Reach reads project settings; it never writes them")


func test_reach_view_scans_lazily_on_first_reveal() -> void:
	# cyber_panel builds EVERY tab eagerly on each plugin reload, so without a latch a plugin toggle would fan out a
	# full res:// walk for a tab nobody clicked. This tab is not in tests/test_devtools_lazy_reveal.gd's LAZY_DOCKS
	# (that list is the PL6 conversion set), so it pins its own latch here — same substrings, same contract.
	var src := FileAccess.get_file_as_string("res://addons/cybersunday_tools/dock_reach/reach_view.gd")
	assert_ne(src, "", "reach_view.gd source should be readable")
	assert_true(src.contains("var _revealed"), "the tab declares a _revealed first-reveal latch")
	assert_true(src.contains("visibility_changed.connect(_on_visibility_changed)"), "connected to the lazy handler")
	assert_true(src.contains("func _on_visibility_changed"), "which is defined")
	assert_true(src.contains("is_visible_in_tree() and not _revealed"), "and guards the scan on the first in-tree reveal")
	assert_true(src.contains("_revealed = true"), "latching so the walk runs once, not on every visibility flip")


# ================================================================================================================
# ACCEPTANCE — the SHIPPED pipeline over the REAL project, pinned to hand-verified ground truth
# ================================================================================================================

## Run the real scan ONCE and memoise it: roots -> survey -> closure -> report, in the exact order _rescan() uses,
## through the tab's own glue — with ONE deliberate substitution, the injected reader (see the comment on it below).
## Every acceptance test below reads this same result.
func _acceptance() -> Dictionary:
	if not _acc.is_empty():
		return _acc
	var view := ReachView.new()
	var roots := ReachView.boot_roots()
	var survey := view._survey()
	var found: Dictionary = survey["found"]
	var surveyed := int(survey["surveyed"])
	# The injected reader guards on file_exists first. ScanCache.text_of (what the tab passes) returns "" for an
	# unreadable file, so this is the same contract — minus the console noise a dangling res:// literal would
	# otherwise produce, and GUT 9.6 fails a test on ANY engine error.
	var reader := func(p):
		return FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else ""
	var cl := Reach.closure(roots, reader, {}, view._dir_members)
	var report := Reach.build_report(cl, found)
	var counts: Dictionary = report["counts"]
	_acc = {
		"roots": roots,
		"surveyed": surveyed,
		"closure": cl,
		"report": report,
		"suspect": view._is_suspect(counts, roots.size(), surveyed),
	}
	view.free()
	return _acc


func test_acceptance_denominators_are_not_degenerate() -> void:
	# READ THIS FIRST IF SOMETHING BELOW FAILS. "0 problems out of 0 things looked at" and "0 problems out of 378
	# things looked at" must never read the same, so the denominators are asserted BEFORE any finding: an empty
	# report is evidence of a broken scan, not of a clean project.
	var acc := _acceptance()
	var counts: Dictionary = (acc["report"] as Dictionary)["counts"]
	assert_gte((acc["roots"] as Array).size(), 2, "main_scene + the autoloads are the boot roots")
	assert_gte(int(acc["surveyed"]), 200, "the disk survey reads every .tscn/.tres in res:// (378 today)")
	assert_gte(int(counts["reached"]), 100, "the closure walks the game, not just the roots")
	assert_gte(int(counts["levels_total"]), 6, "the level roster unions wired + authored levels")
	assert_gte(int(counts["quests_total"]), 2, "both authored quests are rostered")
	assert_false(bool(acc["suspect"]), "the real project must not read as a degenerate scan")


func test_acceptance_prints_the_real_boot_chain() -> void:
	# project.godot:14 boots computerroom.tscn; computerroom.gd:29 const START_MENU_SCENE and start_menu.gd:19
	# const GAME_SCENE are the ONLY link from the boot scene into the game — bare res:// literals, invisible to a
	# load()/preload() regex. Without them this report would stop at the boot scene and call the game unreachable.
	#
	# The chain is deterministic, but it is decided by a TIE: options_menu.gd (reached at depth 1, because
	# options_menu.tscn is an autoload root) also does change_scene_to_file("res://scenes/start_menu.tscn"), so it
	# too could parent start_menu.tscn at depth 2. main_scene is appended FIRST in boot_roots(), so computerroom.gd
	# is queued — and popped — before options_menu.gd, and first-visit-wins gives the chain the BOOT route. If this
	# assertion ever fails with options_menu.tscn at the head, the root ORDER changed, not the reachability.
	var acc := _acceptance()
	var report: Dictionary = acc["report"]
	var chain := PackedStringArray()
	for p in report["chain"]:
		chain.append(str(p))
	var expected := PackedStringArray([BOOT_SCENE, START_MENU, GAME_SCENE, LEVEL_DATA, LIVE_LEVEL])
	assert_eq(" -> ".join(chain), " -> ".join(expected), "the printed content chain")
	assert_eq(str(report["chain_leaf"]), LIVE_LEVEL, "the boot chain lands in the one level a player actually loads")
	var full: Array = report["chain_full"]
	for glue in BOOT_GLUE:
		assert_has(full, glue, "the full chain shows the .gd hop that carried the edge, so the tab can be audited")


func test_acceptance_quests_are_the_finding() -> void:
	# THE ROW THAT PROVES THE TAB WORKS. Both quests are unreachable today, for two DIFFERENT reasons, and Stats
	# calls one of them healthy forever ("referenced by SliceTestLevel.tscn"). Re-derive with a grep for each
	# quest's path AND its uid:// — clear_the_block.tres is referenced by nothing project-wide;
	# recover_the_package.tres only by scenes/levels/SliceTestLevel.tscn, which nothing loads.
	var acc := _acceptance()
	var report: Dictionary = acc["report"]
	var quests: Array = report["quests"]

	var lonely := _row_for(quests, "path", QUEST_NO_START)
	assert_false(lonely.is_empty(), "clear_the_block.tres MUST appear in the report — an empty report is the failure mode")
	assert_eq(str(lonely.get("verdict", "")), Reach.VERDICT_NO_START,
		"nothing anywhere assigns clear_the_block to a QuestStarter / TriggerVolume / DialogueChoice: WIRE IT")
	assert_eq((lonely.get("sites", []) as Array).size(), 0, "and it has no start site to show")

	var hosted := _row_for(quests, "path", QUEST_UNREACHABLE_START)
	assert_false(hosted.is_empty(), "recover_the_package.tres MUST appear in the report")
	assert_eq(str(hosted.get("verdict", "")), Reach.VERDICT_UNREACHABLE_START,
		"recover_the_package IS wired — its HOST level is what no player can reach")
	var sites: Array = []
	var reachable_sites := 0
	for s in hosted.get("sites", []):
		var sd := s as Dictionary
		sites.append("%s in %s" % [str(sd["label"]), str(sd["file"])])
		if bool(sd["reachable"]):
			reachable_sites += 1
	assert_has(sites, "QuestStarter.quest in %s" % SLICE_LEVEL,
		"the finding must name the component AND the file, or the designer cannot act on it")
	assert_eq(reachable_sites, 0, "no start site for it sits inside the closure")
	# scenes/levels/SliceTestLevel.tscn:347 — `[node name="QuestStarter" type="Area3D" parent="Objects/QuestBoard"`
	# holds the `quest = ExtResource("9_quest")` line, so the row can say WHICH node to look for in the scene dock.
	var node_names: Array = []
	for s in hosted.get("sites", []):
		var sd := s as Dictionary
		if str(sd["file"]) == SLICE_LEVEL:
			node_names.append(str(sd.get("node", "")))
	assert_has(node_names, "QuestStarter", "the real start site names the scene node holding it: %s" % str(node_names))

	var counts: Dictionary = report["counts"]
	assert_gte(int(counts["quests_no_start"]), 1, "at least one quest is unwired")
	assert_gte(int(counts["quests_unreachable_start"]), 1, "at least one quest is wired into an unreachable scene")


func test_acceptance_level_roster_separates_the_live_level_from_the_orphans() -> void:
	var acc := _acceptance()
	var levels: Array = (acc["report"] as Dictionary)["levels"]
	var live := _row_for(levels, "path", LIVE_LEVEL)
	assert_false(live.is_empty(), "the live level is rostered")
	assert_true(bool(live.get("reachable", false)), "trenchboom_test_level.tscn is the level the boot chain loads")
	for path in UNREACHABLE_LEVELS:
		var row := _row_for(levels, "path", str(path))
		assert_false(row.is_empty(), "%s must be ROSTERED, not silently dropped" % str(path))
		assert_false(bool(row.get("reachable", true)), "%s is authored but no reachable file loads it" % str(path))


func test_acceptance_closure_follows_packedscene_instancing_and_leaves_old_man_outside() -> void:
	# old_man.tres is referenced by THREE files (scenes/characters/chip_mechanic.tscn, scenes/levels/TestLevel.tscn,
	# scenes/levels/TestLevel_2.tscn) — which is exactly why Stats reports it healthy. All three are outside the
	# closure, so no player can ever hear that conversation.
	#
	# The companion assertion matters just as much: NPC.tscn (instanced BY the live level) IS reached, which proves
	# the walk follows PackedScene instancing edges into scenes/characters/ rather than only level-to-level edges.
	# Without it, "old_man is unreachable" could just mean the walk never looks at character scenes at all.
	var acc := _acceptance()
	var report: Dictionary = acc["report"]
	var reached: Dictionary = (acc["closure"] as Dictionary)["reached"]
	assert_true(reached.has(NPC_SCENE), "the live level instances NPC.tscn — PackedScene edges ARE followed")
	var row := _row_for(report["dialogue"], "path", OLD_MAN)
	assert_false(row.is_empty(), "old_man.tres is rostered as dialogue")
	assert_false(bool(row.get("reachable", true)),
		"all three of its referrers are outside the closure, so no reachable NPC points at it")


func test_acceptance_folder_scan_guard_spares_every_scanned_item() -> void:
	# THE OTHER WAY TO GET THIS WRONG. ItemDb registers items by DROPPING A .tres IN THE FOLDER (item_db.gd:18
	# opens ITEMS_DIR and load()s whatever it finds) — nothing references them by path. A finder that ignored that
	# would condemn all 35 and the report would be noise a designer learns to ignore. The directory listing here is
	# the TEST's own read of disk, never the module's.
	var acc := _acceptance()
	var report: Dictionary = acc["report"]
	var counts: Dictionary = report["counts"]
	var reached: Dictionary = (acc["closure"] as Dictionary)["reached"]

	assert_false(_row_for(report["folder_roots"], "dir", ITEMS_DIR).is_empty(),
		"res://resources/items must be detected as a folder-scan root")
	assert_gte(int(counts["folder_scan_members"]), 1, "and it must actually spare files from the orphan list")

	var items := DirAccess.get_files_at(ITEMS_DIR)
	assert_gte(items.size(), 10, "sanity: the items folder is populated (35 today)")
	var condemned: Array = []
	for f in items:
		var path := ITEMS_DIR.path_join(str(f))
		if path.get_extension() != "tres":
			continue
		if not reached.has(path):
			condemned.append(path)
	assert_eq(condemned.size(), 0, "0 folder-scanned items may be condemned: %s" % str(condemned))
