extends GutTest

## The in-game debug tools' PURE core (DebugCommands): registry hygiene, the line parser, validation,
## completion and help rendering — plus the registry<->actions dispatch-parity pin. The IMPURE halves
## (DebugActionsPlayer/DebugActionsWorld run(), the console/menu UIs) are deliberately NOT driven through run():
## their commands write real autoload state (GameState.account, WorldClock, saves), so exercising them
## blind under GUT would cheat the test profile. What IS driven here is the off-tree-safe glue the UIs share:
## the player freeze/thaw pair, noclip's flight gate over a hand-built (never _ready) Player, and the menu's
## meta-row forwarding to a duck-typed console. The console itself is driven in test_debug_console_exec.gd and
## the inspector in test_debug_ai_seams.gd.

const Commands := preload("res://scripts/components/debug_commands.gd")

# Preloaded by PATH, untyped consts — the new class_names may not be in the editor cache yet
# (the cascade debug_overlay.gd:9-11 documents).
const PlayerActions := preload("res://scripts/components/debug_actions_player.gd")
const WorldActions := preload("res://scripts/components/debug_actions_world.gd")
const MenuScript := preload("res://scripts/components/debug_menu.gd")
const NoclipScript := preload("res://scripts/components/debug_noclip.gd")
const PLAYER_PATH := "res://scripts/player/player.gd"


## A console as the menu sees it: found through console_path by `echo`, answering forwarded meta rows.
class MetaConsoleStub extends Node:
	var calls: Array = []
	func echo(_lines: PackedStringArray) -> void:
		pass
	func run_meta(cmd: String, args: PackedStringArray) -> PackedStringArray:
		calls.append([cmd, args])
		return PackedStringArray(["stub answered " + cmd])


## An older console with no run_meta: the menu must fall back to ONE typed line through run_line.
class LineConsoleStub extends Node:
	var lines := PackedStringArray()
	func echo(_lines: PackedStringArray) -> void:
		pass
	func run_line(line: String) -> void:
		lines.append(line)


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
	# The menu builds pages in this order and opens on the first one, so the player cheats lead.
	assert_eq(String(cats[0]), "Player", "Player leads the page order")


func test_find_is_case_and_padding_tolerant() -> void:
	assert_false(Commands.find("god").is_empty(), "find resolves a plain name")
	assert_false(Commands.find("  GOD  ").is_empty(), "find strips and lowercases")
	assert_true(Commands.find("no_such_thing").is_empty(), "a miss is an EMPTY dictionary, not null")


# --- dispatch parity (registry <-> actions) ------------------------------------------------------------------

## ⭐Every &"player"/&"world" row must have a case in its module's `match cmd:` or the command is silently dead
## in BOTH front-ends. run() can't be probed live here (commands write real autoload state), so this pins the
## dispatch by source text: a match arm is a `"name":` (or `"a", "b":`) pattern line inside run()'s body — NOT any
## quoted mention of the name, which a help string or an error message elsewhere in the module would satisfy.
## If this fails after a rename, the registry row and the module case drifted — fix the module, not this test.
func _run_arms(src: String, module: String) -> Dictionary:
	var start := src.find("static func run(")
	assert_gt(start, -1, "%s defines static func run(" % module)
	if start < 0:
		return {}
	var end := src.find("\nstatic func ", start + 1)
	var body := src.substr(start, (end - start) if end > 0 else -1)
	var line_rx := RegEx.new()
	line_rx.compile("\\n\\t\\t(\"[a-z0-9_]+\"(?:\\s*,\\s*\"[a-z0-9_]+\")*)\\s*:")
	var word_rx := RegEx.new()
	word_rx.compile("\"([a-z0-9_]+)\"")
	var out := {}
	for m in line_rx.search_all(body):
		for w in word_rx.search_all(m.get_string(1)):
			out[w.get_string(1)] = true
	return out


func test_every_registry_row_has_a_dispatch_case() -> void:
	var player_src := FileAccess.get_file_as_string("res://scripts/components/debug_actions_player.gd")
	var world_src := FileAccess.get_file_as_string("res://scripts/components/debug_actions_world.gd")
	assert_false(player_src.is_empty(), "player actions module must be readable")
	assert_false(world_src.is_empty(), "world actions module must be readable")
	var player_arms := _run_arms(player_src, "debug_actions_player.gd")
	var world_arms := _run_arms(world_src, "debug_actions_world.gd")
	assert_gt(player_arms.size(), 10, "the arm scan finds run()'s match arms in the player module (a scan that finds none proves nothing)")
	assert_gt(world_arms.size(), 10, "the arm scan finds run()'s match arms in the world module")
	for row in Commands.COMMANDS:
		var n := String(row["name"])
		match row["mod"]:
			&"player":
				assert_true(player_arms.has(n),
					"'%s' (mod player) has no match arm in debug_actions_player.gd run() — the command is dead" % n)
			&"world":
				assert_true(world_arms.has(n),
					"'%s' (mod world) has no match arm in debug_actions_world.gd run() — the command is dead" % n)
			&"meta":
				pass  # handled inside the console; test_debug_console_exec.gd pins its _run_meta arms


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


# --- off-tree glue the impure halves share ---------------------------------------------------------------------

## Both UIs freeze the player on open (or every click on a panel button also pulls the trigger) and thaw it on close
## through this pair. Driven over a hand-built Player (never _ready, never in the tree), whose physics bit and meta
## are plain state off-tree.
func test_suspend_and_restore_player_round_trip_and_thaw_a_body_revived_under_the_console() -> void:
	var p = load(PLAYER_PATH).new()
	p.hp = p.max_hp
	p.set_physics_process(true)
	var snap: Dictionary = PlayerActions.suspend_player(p)
	assert_true(bool(snap.get(&"valid", false)), "a live Player is suspended")
	assert_false(p.is_physics_processing(), "suspend switches the body's own step off, so panel clicks cannot fire the weapon")
	assert_true(p.has_meta(PlayerActions.SUSPEND_META), "and marks the body as held by a debug surface")
	PlayerActions.restore_player(p, snap)
	assert_true(p.is_physics_processing(), "restore hands the running step back — closing the console never leaves you frozen")
	assert_false(p.has_meta(PlayerActions.SUSPEND_META), "and clears the held mark")

	p.set_physics_process(false)  # frozen by something else (a cutscene lock) while alive
	PlayerActions.restore_player(p, PlayerActions.suspend_player(p))
	assert_false(p.is_physics_processing(), "a body already frozen while ALIVE is handed back frozen, exactly as found")

	p.hp = 0.0  # the console opened over a corpse: die() had the step off
	var corpse: Dictionary = PlayerActions.suspend_player(p)
	p.hp = p.max_hp  # `revive` ran while the console was open
	PlayerActions.restore_player(p, corpse)
	assert_true(p.is_physics_processing(),
		"a corpse revived under the console is handed back RUNNING — writing the corpse's frozen snapshot back would strand a living player")
	p.hp = 0.0
	p.set_physics_process(false)
	var still_dead: Dictionary = PlayerActions.suspend_player(p)
	PlayerActions.restore_player(p, still_dead)
	assert_false(p.is_physics_processing(), "control: a corpse that is STILL dead at close stays frozen (only a revive thaws)")
	p.hp = p.max_hp

	# Junk snapshots and non-players: teardown can run after the player is gone or with nothing captured.
	p.set_physics_process(false)
	p.set_meta(PlayerActions.SUSPEND_META, true)
	PlayerActions.restore_player(p, {})
	assert_false(p.is_physics_processing(), "an empty snapshot writes nothing back, even onto a real Player")
	assert_true(p.has_meta(PlayerActions.SUSPEND_META), "and leaves the held mark for the surface that owns it")
	p.remove_meta(PlayerActions.SUSPEND_META)
	PlayerActions.restore_player(null, {&"valid": true, &"physics": true})  # must not error (GUT fails on engine errors)
	var not_a_player := Node.new()
	assert_false(bool(PlayerActions.suspend_player(not_a_player).get(&"valid", true)), "a node that is not a Player is never suspended")
	assert_false(not_a_player.has_meta(PlayerActions.SUSPEND_META), "and is never marked")
	PlayerActions.restore_player(not_a_player, {&"valid": true, &"physics": true})
	assert_false(not_a_player.is_physics_processing(), "restore never writes a snapshot onto a node that is not a Player")
	not_a_player.free()
	p.free()


## Noclip flies the REAL body by switching its physics step off. Off-tree nothing arms it (the release-build state:
## _ready never ran); armed, it must fly only a live player, hand back exactly the step it found, and never
## resurrect a body that died mid-flight.
func test_noclip_flies_only_a_live_player_once_armed_and_hands_the_step_back_as_found() -> void:
	var host := Node.new()
	var p = load(PLAYER_PATH).new()
	p.name = "Body"
	host.add_child(p)
	var noclip = (NoclipScript as GDScript).new()
	host.add_child(noclip)
	noclip.player_path = NodePath("../Body")
	p.hp = p.max_hp
	p.set_physics_process(true)

	assert_false(noclip.set_enabled(true), "an unarmed noclip (release build / never readied) refuses to fly")
	assert_false(noclip.is_enabled(), "and reports not flying")
	assert_true(p.is_physics_processing(), "and never touched the body")

	noclip.set(&"_armed", true)  # what _ready does in a debug build
	p.set(&"_continuous_fall_time", 3.5)  # banked mid-fall when noclip went on
	assert_true(noclip.set_enabled(true), "armed with a live player, flight starts")
	assert_true(noclip.is_enabled(), "and reports flying")
	assert_false(p.is_physics_processing(), "flying switches the body's own step off (no gravity, no move_and_slide)")
	assert_almost_eq(float(p.get(&"_continuous_fall_time")), 0.0, 0.0001, "a flight hands back a fresh fall budget, never a part-spent one")
	assert_false(noclip.set_enabled(false), "switching off reports not flying")
	assert_true(p.is_physics_processing(), "and hands the running step back")
	assert_gt(int(p.get(&"_ground_snap_frames_left")), 0, "switching off arms the ground snap so a flight ends in a landing")

	p.set_physics_process(false)  # already frozen (e.g. the console is open) when flight starts
	assert_true(noclip.set_enabled(true), "a frozen but live body can still be flown")
	noclip.set_enabled(false)
	assert_false(p.is_physics_processing(), "stopping restores the frozen step it found instead of thawing it")

	p.set_physics_process(true)
	assert_true(noclip.set_enabled(true), "flying again")
	p.hp = 0.0  # shot while flying
	noclip.set_enabled(false)
	assert_false(p.is_physics_processing(), "a body killed mid-flight is NOT handed its step back — die()'s cinematic owns it")

	p.set_physics_process(true)
	assert_false(noclip.set_enabled(true), "a corpse is never flown")
	assert_false(noclip.is_enabled(), "and the refusal reports not flying")
	assert_true(p.is_physics_processing(), "and leaves the corpse's step bit untouched")
	host.free()


## `exec` and `bind` need the console's exec queue / key table, so the menu forwards them to a duck-typed console
## and paints what comes back. Driven off-tree: the console is wired through console_path to a sibling stub.
func test_menu_forwards_console_only_meta_rows_and_says_so_when_there_is_no_console() -> void:
	var host := Node.new()
	var menu = (MenuScript as GDScript).new()
	host.add_child(menu)

	var help: PackedStringArray = menu.call(&"_run_meta", "help", PackedStringArray())
	assert_eq(help, Commands.help_lines(), "`help` is answered by the menu itself — it needs no console")
	var none: PackedStringArray = menu.call(&"_run_meta", "exec", PackedStringArray(["repro.cfg"]))
	assert_eq(none.size(), 1, "with no console, exec answers one line: %s" % [none])
	assert_true(none[0].begins_with("exec:") and none[0].contains("DebugConsole"),
		"and it names the missing console instead of silently doing nothing: %s" % [none])

	var console := MetaConsoleStub.new()
	console.name = "Console"
	host.add_child(console)
	menu.set(&"console_path", NodePath("../Console"))
	var answered: PackedStringArray = menu.call(&"_run_meta", "bind", PackedStringArray(["F6", "god; noclip on"]))
	assert_eq(answered, PackedStringArray(["stub answered bind"]), "the console's own lines come back to be painted on the menu strip")
	assert_eq(console.calls.size(), 1, "the row is forwarded exactly once")
	if console.calls.size() == 1:
		assert_eq(String(console.calls[0][0]), "bind", "as the same command")
		assert_eq(console.calls[0][1], PackedStringArray(["F6", "god; noclip on"]), "with the widget argv untouched (no re-tokenising)")

	var line_console := LineConsoleStub.new()
	line_console.name = "OldConsole"
	host.add_child(line_console)
	menu.set(&"console_path", NodePath("../OldConsole"))
	var fallback: PackedStringArray = menu.call(&"_run_meta", "bind", PackedStringArray(["F6", "god; noclip on"]))
	assert_eq(line_console.lines.size(), 1, "a console with no run_meta gets ONE typed line")
	if line_console.lines.size() == 1:
		assert_eq(Commands.tokenize(line_console.lines[0]), PackedStringArray(["bind", "F6", "god; noclip on"]),
			"which the console's tokenizer splits back into the argv the widgets produced: %s" % line_console.lines[0])
	assert_eq(fallback.size(), 1, "and the menu says where the result went: %s" % [fallback])
	host.free()
