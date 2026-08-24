extends GutTest

## The in-game debug tools' PURE core (DebugCommands): registry hygiene, the line parser, validation,
## completion and help rendering — plus the registry<->actions dispatch-parity pin. The IMPURE halves
## (DebugActionsPlayer/DebugActionsWorld run(), the console/menu UIs) are deliberately NOT driven here:
## their commands write real autoload state (GameState.account, WorldClock, saves), so exercising them
## blind under GUT would cheat the test profile. Construct checks confirm they compile; behaviour is
## play-verified.

const Commands := preload("res://scripts/components/debug_commands.gd")

# Preloaded by PATH, untyped consts — the new class_names may not be in the editor cache yet
# (the cascade debug_overlay.gd:9-11 documents).
const PlayerActions := preload("res://scripts/components/debug_actions_player.gd")
const WorldActions := preload("res://scripts/components/debug_actions_world.gd")
const ConsoleScript := preload("res://scripts/components/debug_console.gd")
const MenuScript := preload("res://scripts/components/debug_menu.gd")
const NoclipScript := preload("res://scripts/components/debug_noclip.gd")
const InspectorScript := preload("res://scripts/components/debug_inspector.gd")


# --- registry hygiene ---------------------------------------------------------------------------------------

func test_registry_is_populated_and_names_unique() -> void:
	assert_gt(Commands.COMMANDS.size(), 30, "the command registry should be substantial")
	var seen := {}
	for row in Commands.COMMANDS:
		var n := String(row["name"])
		assert_false(seen.has(n), "duplicate command name '%s'" % n)
		seen[n] = true
		assert_eq(n, n.to_lower(), "command names are lowercase ('%s')" % n)
		assert_false(n.contains(" "), "command names have no spaces ('%s')" % n)


func test_registry_rows_are_internally_consistent() -> void:
	for row in Commands.COMMANDS:
		var n := String(row["name"])
		var kinds: Array = row["args"]
		var arg_names: Array = row["arg_names"]
		assert_eq(arg_names.size(), kinds.size(), "'%s': arg_names must match args 1:1" % n)
		assert_lte(int(row["min_args"]), kinds.size(), "'%s': min_args cannot exceed the arg count" % n)
		assert_true(Commands.CATEGORIES.has(String(row["category"])),
			"'%s': category '%s' must be a known CATEGORIES entry (an unknown one degrades to a stray menu page)" % [n, String(row["category"])])
		var mod: StringName = row["mod"]
		assert_true(mod == &"player" or mod == &"world" or mod == &"meta",
			"'%s': mod must be player/world/meta, got '%s'" % [n, String(mod)])
		# A VERB slot with no verbs list validates nothing and completes nothing — always an authoring mistake.
		for k in kinds:
			if int(k) == Commands.Kind.VERB:
				assert_gt((row["verbs"] as Array).size(), 0, "'%s': a Kind.VERB slot needs a verbs list" % n)


func test_categories_are_ordered_and_complete() -> void:
	var cats := Commands.categories()
	for row in Commands.COMMANDS:
		assert_true(cats.has(String(row["category"])), "categories() must surface every row's category")
	# The menu builds pages in this order; Meta last keeps the cheats in front.
	assert_eq(String(cats[0]), "Player", "Player leads the page order")


func test_find_is_case_and_padding_tolerant() -> void:
	assert_false(Commands.find("god").is_empty(), "find resolves a plain name")
	assert_false(Commands.find("  GOD  ").is_empty(), "find strips and lowercases")
	assert_true(Commands.find("no_such_thing").is_empty(), "a miss is an EMPTY dictionary, not null")


# --- dispatch parity (registry <-> actions) ------------------------------------------------------------------

## ⭐Every &"player"/&"world" row must have a case in its module's `match cmd:` or the command is silently dead
## in BOTH front-ends. run() can't be probed live here (commands write real autoload state), so this pins the
## dispatch by source text: a match arm is exactly the quoted command name. If this fails after a rename, the
## registry row and the module case drifted — fix the module, not this test.
func test_every_registry_row_has_a_dispatch_case() -> void:
	var player_src := FileAccess.get_file_as_string("res://scripts/components/debug_actions_player.gd")
	var world_src := FileAccess.get_file_as_string("res://scripts/components/debug_actions_world.gd")
	assert_false(player_src.is_empty(), "player actions module must be readable")
	assert_false(world_src.is_empty(), "world actions module must be readable")
	for row in Commands.COMMANDS:
		var n := String(row["name"])
		var quoted := "\"%s\"" % n
		match row["mod"]:
			&"player":
				assert_true(player_src.contains(quoted),
					"'%s' (mod player) has no match arm in debug_actions_player.gd — the command is dead" % n)
			&"world":
				assert_true(world_src.contains(quoted),
					"'%s' (mod world) has no match arm in debug_actions_world.gd — the command is dead" % n)
			&"meta":
				pass  # handled inside the console; its construct test below covers compilation


func test_action_modules_expose_the_contract_surface() -> void:
	for mod in [PlayerActions, WorldActions]:
		var methods := {}
		for m in (mod as GDScript).get_script_method_list():
			methods[String(m["name"])] = true
		assert_true(methods.has("run"), "action modules expose run()")
		assert_true(methods.has("sources"), "action modules expose sources()")
	# The shared suspension helpers live in the player module (both UIs call them).
	var player_methods := {}
	for m in (PlayerActions as GDScript).get_script_method_list():
		player_methods[String(m["name"])] = true
	assert_true(player_methods.has("suspend_player"), "suspend_player is the shared freeze helper")
	assert_true(player_methods.has("restore_player"), "restore_player is its inverse")


# --- tokenizer ----------------------------------------------------------------------------------------------

func test_tokenize_splits_on_whitespace() -> void:
	assert_eq(Commands.tokenize("give ammo 30"), PackedStringArray(["give", "ammo", "30"]))
	assert_eq(Commands.tokenize("  spaced   out  "), PackedStringArray(["spaced", "out"]))
	assert_eq(Commands.tokenize("tabs\there"), PackedStringArray(["tabs", "here"]))
	assert_eq(Commands.tokenize("").size(), 0, "blank line -> no tokens")
	assert_eq(Commands.tokenize("   ").size(), 0, "whitespace-only line -> no tokens")


func test_tokenize_honours_quotes() -> void:
	assert_eq(Commands.tokenize("give \"two words\" 3"), PackedStringArray(["give", "two words", "3"]))
	assert_eq(Commands.tokenize("say \"\""), PackedStringArray(["say", ""]), "empty quotes are a deliberate empty token")
	# An unterminated quote closes at end-of-line — a half-typed line is the console's normal state.
	assert_eq(Commands.tokenize("give \"unfinished"), PackedStringArray(["give", "unfinished"]))


# --- validation ---------------------------------------------------------------------------------------------

func test_validate_enforces_arity() -> void:
	var tp := Commands.find("tp")
	assert_eq(Commands.validate(tp, PackedStringArray(["1", "2", "3"])), "", "exact arity passes")
	assert_ne(Commands.validate(tp, PackedStringArray(["1", "2"])), "", "missing a required arg fails")
	assert_ne(Commands.validate(tp, PackedStringArray(["1", "2", "3", "4"])), "", "an extra arg fails")
	var heal := Commands.find("heal")
	assert_eq(Commands.validate(heal, PackedStringArray()), "", "an optional arg may be omitted")


func test_validate_checks_kinds() -> void:
	var tp := Commands.find("tp")
	assert_ne(Commands.validate(tp, PackedStringArray(["1", "x", "3"])), "", "a non-number in a NUMBER slot fails")
	var god := Commands.find("god")
	assert_eq(Commands.validate(god, PackedStringArray(["on"])), "", "on is a legal toggle word")
	assert_ne(Commands.validate(god, PackedStringArray(["maybe"])), "", "an unknown toggle word fails")
	var quest := Commands.find("quest")
	assert_eq(Commands.validate(quest, PackedStringArray(["start", "x"])), "", "a listed verb passes")
	assert_ne(Commands.validate(quest, PackedStringArray(["explode", "x"])), "", "an unlisted verb fails")
	assert_ne(Commands.validate({}, PackedStringArray()), "", "an empty row (find() miss) fails, never crashes")


func test_toggle_value_words_and_flip() -> void:
	assert_true(Commands.toggle_value("on", false))
	assert_false(Commands.toggle_value("off", true))
	assert_true(Commands.toggle_value("", false), "blank flips: bare `noclip` is a toggle")
	assert_false(Commands.toggle_value("", true), "blank flips both ways")


func test_usage_marks_required_vs_optional() -> void:
	var give := Commands.usage(Commands.find("give"))
	assert_true(give.contains("<item id>"), "required args render angled: %s" % give)
	assert_true(give.contains("[count]"), "optional args render bracketed: %s" % give)
	var quest := Commands.usage(Commands.find("quest"))
	assert_true(quest.contains("start|complete|fail|show"), "a VERB slot renders its word list: %s" % quest)


# --- completion ---------------------------------------------------------------------------------------------

func test_complete_command_names() -> void:
	var r := Commands.complete("gi", {})
	assert_true((r["matches"] as PackedStringArray).has("give"), "gi completes toward give")
	var one := Commands.complete("noc", {})
	assert_eq(String(one["line"]), "noclip ", "a unique match completes fully and appends the separator")


func test_complete_argument_slots_use_sources() -> void:
	var sources := {&"item": PackedStringArray(["ammo", "ammo_pistol", "medkit"])}
	var r := Commands.complete("give am", sources)
	assert_eq(String(r["line"]), "give ammo", "the common prefix fills in")
	assert_eq((r["matches"] as PackedStringArray).size(), 2, "both ammo ids are offered")
	var typed := Commands.complete("give ammo_p", sources)
	assert_eq(String(typed["line"]), "give ammo_pistol ", "a unique id completes and moves on")
	# A trailing space means the caret sits in the NEXT slot: complete over the whole source, not the command.
	var next := Commands.complete("give ", sources)
	assert_eq((next["matches"] as PackedStringArray).size(), 3, "a fresh slot offers the whole source")


func test_complete_degrades_without_crashing() -> void:
	assert_eq(String(Commands.complete("zzz nono", {})["line"]), "zzz nono", "an unknown command leaves the line alone")
	assert_eq((Commands.complete("clear extra", {})["matches"] as PackedStringArray).size(), 0,
		"a slot past the row's arity offers nothing")
	var god := Commands.complete("god o", {})
	assert_eq((god["matches"] as PackedStringArray).size(), 2, "TOGGLE slots complete from on/off with no source dict")


func test_common_prefix() -> void:
	assert_eq(Commands.common_prefix(PackedStringArray(["ammo", "ammo_pistol"])), "ammo")
	assert_eq(Commands.common_prefix(PackedStringArray(["abc"])), "abc")
	assert_eq(Commands.common_prefix(PackedStringArray()), "")


# --- search (the F1 menu's search bar) ------------------------------------------------------------------------

func _found(query: String) -> PackedStringArray:
	var out := PackedStringArray()
	for row in Commands.search(query):
		out.append(String(row["name"]))
	return out


func test_search_terms_splits_and_lowercases() -> void:
	assert_eq(Array(Commands.search_terms("  GOD   mode\tOn ")), ["god", "mode", "on"],
		"terms are lower-cased, whitespace-split (tabs included) and blank-free")
	assert_eq(Commands.search_terms("").size(), 0, "a blank query has no terms")
	assert_eq(Commands.search_terms("   \t ").size(), 0, "a whitespace-only query has no terms")


func test_search_with_no_query_filters_nothing() -> void:
	# The menu hands this the raw contents of its field, so "no query" has to mean "no filter" rather than
	# "no results" — otherwise an empty search bar would paint an empty panel.
	assert_eq(Commands.search("").size(), Commands.COMMANDS.size(), "a blank query returns every row")
	assert_eq(Commands.search("   ").size(), Commands.COMMANDS.size(), "so does a whitespace-only one")


func test_search_ranks_the_name_match_first() -> void:
	var hits := _found("god")
	assert_gt(hits.size(), 0, "'god' finds something")
	assert_eq(hits[0], "god", "an EXACT name match leads, never a row that merely mentions it in its help")
	var kills := _found("kill")
	assert_eq(kills[0], "kill", "exact beats prefix")
	assert_true(kills.has("killall"), "and the prefix match is still in the list")
	# The contract, stated without naming today's registry: every row whose NAME carries the query sorts above
	# every row that only matched through its help line.
	var last_named := -1
	var first_unnamed := kills.size()
	for i in kills.size():
		if kills[i].contains("kill"):
			last_named = i
		elif i < first_unnamed:
			first_unnamed = i
	assert_lt(last_named, first_unnamed, "name matches come before help-text-only matches: %s" % str(kills))


func test_search_matches_help_text_not_just_names() -> void:
	# The whole point of the bar: reach a command by what it DOES when you cannot remember what it is called.
	# "continuous-fall" lives only in god's help line.
	assert_true(_found("continuous-fall").has("god"), "a word from the help line finds the row")
	assert_gt(_found("crosshair").size(), 0, "prose-only queries return something")


func test_search_matches_category_and_argument_names() -> void:
	assert_gt(_found("economy").size(), 0, "a page name is searchable")
	assert_true(_found("on/off").has("god"), "an argument NAME is searchable (god takes an on/off slot)")


func test_search_terms_are_anded_so_more_words_narrow() -> void:
	var one := _found("npc")
	var two := _found("npc spawn")
	assert_gt(one.size(), two.size(), "adding a word must NARROW the list, never widen it")
	for name_s in two:
		assert_true(one.has(name_s), "'%s' survived both queries, so it must be in the looser one too" % name_s)


func test_search_is_case_insensitive_and_substring() -> void:
	assert_eq(Array(_found("GOD")), Array(_found("god")), "case does not change the result")
	# Substring, not prefix — `complete()` owns the prefix half for the console's Tab key.
	assert_true(_found("ffect").has("effect"), "a match in the MIDDLE of a name counts")


func test_search_misses_return_nothing_rather_than_everything() -> void:
	assert_eq(_found("zzzznotacommand").size(), 0, "a query nothing carries returns no rows")


func test_search_never_invents_or_duplicates_rows() -> void:
	var seen := {}
	for row in Commands.search("e"):
		var n := String(row["name"])
		assert_false(seen.has(n), "'%s' appears twice in one result" % n)
		seen[n] = true
		assert_false(Commands.find(n).is_empty(), "every hit is a real registry row")


func test_haystack_covers_every_searchable_field_and_tolerates_junk() -> void:
	var hay := Commands.haystack(Commands.find("god"))
	assert_true(hay.contains("god"), "the haystack carries the name")
	assert_true(hay.contains("player"), "and the category")
	assert_true(hay.contains("armor_flat"), "and the help line")
	assert_eq(hay, hay.to_lower(), "the haystack is lower-cased once, so callers never have to be")
	assert_eq(Commands.haystack({}), "", "an empty row is an empty haystack, never a crash")


# --- help ----------------------------------------------------------------------------------------------------

func test_help_lines_cover_every_command() -> void:
	var joined := "\n".join(Commands.help_lines())
	for row in Commands.COMMANDS:
		assert_true(joined.contains(String(row["name"])), "help lists '%s'" % String(row["name"]))


func test_help_for_flags_danger() -> void:
	var lines := "\n".join(Commands.help_for(Commands.find("respec")))
	assert_true(lines.contains("destructive"), "a danger row's help carries the destructive warning")
	assert_eq(Commands.help_for({}).size(), 0, "help_for an empty row is empty, never a crash")


# --- construct checks (compilation proof for the impure halves) ----------------------------------------------

func test_debug_ui_components_construct_off_tree() -> void:
	# .new() without add_child never runs _ready, so no UI is built and no autoload is touched — this is purely
	# "the file parses and the class constructs", the same bar test_debug_overlay.gd sets.
	var console = (ConsoleScript as GDScript).new()
	assert_not_null(console, "DebugConsole constructs")
	console.free()
	var menu = (MenuScript as GDScript).new()
	assert_not_null(menu, "DebugMenu constructs")
	menu.free()
	var noclip = (NoclipScript as GDScript).new()
	assert_not_null(noclip, "DebugNoclip constructs")
	noclip.free()
	var inspector = (InspectorScript as GDScript).new()
	assert_not_null(inspector, "DebugInspector constructs")
	inspector.free()


func test_restore_player_tolerates_junk() -> void:
	# The one shared helper safe to drive off-tree: restore with no player / an empty snapshot must be a no-op,
	# because _exit_tree teardown can run after the player is already freed.
	PlayerActions.restore_player(null, {})
	PlayerActions.restore_player(null, {&"valid": true})
	var not_a_player := Node.new()
	PlayerActions.restore_player(not_a_player, {&"valid": true, &"physics": true})
	not_a_player.free()
	assert_true(true, "restore_player is null/junk-safe on every teardown path")
