extends GutTest

## The PURE half of the console's scripting surface (exec / autoexec / bind / --exec): the static helpers factored
## out of scripts/components/debug_console.gd, driven OFF-TREE. The console is constructed with .new() and never
## add_child'd, so _ready (the debug gate, the UI build, the autoexec poll, the binds load) never runs — this file
## proves the script parses and the helpers behave, the same bar tests/test_debug_commands.gd sets for the UI.
##
## Disk: ONLY user://test_debug_binds_* scratch paths, removed in after_each. The console's real files
## (user://debug_binds.cfg, user://autoexec.cfg) are never read or written here. NEVER_WRITTEN is a res:// path
## the user://-only guard must refuse — it exists to prove nothing lands there (and is swept if a regression does).

# Preloaded BY PATH, never by class_name: a brand-new class_name is not in the editor's global class cache until
# it rescans, and a typed reference would fail this whole file to parse (the debug_overlay.gd:9-11 cascade).
const ConsoleScript := preload("res://scripts/components/debug_console.gd")
const MenuScript := preload("res://scripts/components/debug_menu.gd")
const Commands := preload("res://scripts/components/debug_commands.gd")

const TMP_BINDS := "user://test_debug_binds_tmp.cfg"
const NEVER_WRITTEN := "res://tests/test_debug_binds_never_written.cfg"


func after_each() -> void:
	for p in [TMP_BINDS, NEVER_WRITTEN]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


# --- exec_lines ---------------------------------------------------------------------------------------------

func test_exec_lines_drops_blank_and_comment_lines() -> void:
	var text := "# repro: rent ambush\r\n\r\n  god on  \n\t\n# spawn later\nwait 3\n   # indented comment\ntp -29 4 -15\n"
	var lines: PackedStringArray = ConsoleScript.exec_lines(text)
	assert_eq(lines.size(), 3, "three runnable lines survive: %s" % [lines])
	assert_eq(lines[0], "god on", "lines are whitespace-trimmed (CRLF included)")
	assert_eq(lines[1], "wait 3", "the exec-only wait word is a line like any other")
	assert_eq(lines[2], "tp -29 4 -15", "order is preserved")


func test_exec_lines_empty_and_comment_only_text_yield_nothing() -> void:
	assert_eq(ConsoleScript.exec_lines("").size(), 0, "empty text has no lines")
	assert_eq(ConsoleScript.exec_lines("# only\n\n#comments\n").size(), 0, "comment-only text has no lines")


# --- split_chain --------------------------------------------------------------------------------------------

func test_split_chain_splits_on_semicolons_and_trims() -> void:
	var parts: PackedStringArray = ConsoleScript.split_chain("god ; noclip on;heal")
	assert_eq(parts.size(), 3, "three chained commands: %s" % [parts])
	assert_eq(parts[0], "god", "leading/trailing spaces are trimmed off each part")
	assert_eq(parts[1], "noclip on", "inner spaces survive")
	assert_eq(parts[2], "heal", "the last part needs no trailing separator")


func test_split_chain_honours_quotes_and_keeps_them() -> void:
	var parts: PackedStringArray = ConsoleScript.split_chain("give \"big ; sword\" 2; noclip on")
	assert_eq(parts.size(), 2, "a `;` inside quotes must not split: %s" % [parts])
	assert_eq(parts[0], "give \"big ; sword\" 2", "quotes are KEPT for the tokenizer to strip later")
	# And the tokenizer downstream still sees the quoted argument as one token.
	var tokens: PackedStringArray = Commands.tokenize(parts[0])
	assert_eq(tokens.size(), 3, "tokenize keeps the quoted id whole: %s" % [tokens])
	assert_eq(tokens[1], "big ; sword", "the quoted id is a single token")


func test_split_chain_drops_empty_segments() -> void:
	assert_eq(ConsoleScript.split_chain("god;;;").size(), 1, "`god;;;` is one command")
	assert_eq(ConsoleScript.split_chain(";").size(), 0, "a lone separator is nothing")
	assert_eq(ConsoleScript.split_chain("").size(), 0, "empty is nothing")
	assert_eq(ConsoleScript.split_chain("   ").size(), 0, "whitespace is nothing")


# --- resolve_exec_path --------------------------------------------------------------------------------------

func test_resolve_exec_path_bare_name_lands_under_user() -> void:
	assert_eq(ConsoleScript.resolve_exec_path("repro.cfg"), "user://repro.cfg", "a bare name resolves under user://")
	assert_eq(ConsoleScript.resolve_exec_path("  repro.cfg  "), "user://repro.cfg", "surrounding whitespace is trimmed")


func test_resolve_exec_path_res_and_user_paths_pass_through() -> void:
	assert_eq(ConsoleScript.resolve_exec_path("user://sub/x.cfg"), "user://sub/x.cfg", "user:// is used as-is")
	assert_eq(ConsoleScript.resolve_exec_path("res://tests/fixtures/x.cfg"), "res://tests/fixtures/x.cfg", "res:// is used as-is")


func test_resolve_exec_path_blank_stays_blank() -> void:
	assert_eq(ConsoleScript.resolve_exec_path(""), "", "blank stays blank so the caller can report it")
	assert_eq(ConsoleScript.resolve_exec_path("   "), "", "whitespace-only is blank")


# --- parse_cmdline ------------------------------------------------------------------------------------------

func test_parse_cmdline_collects_exec_lines_and_autoexec_override() -> void:
	var args := PackedStringArray([
		"--shots-dir=user://x",           # somebody else's user arg — ignored
		"--exec=god on; noclip on",
		"--autoexec=repro.cfg",
		"--exec=heal",
	])
	var parsed: Dictionary = ConsoleScript.parse_cmdline(args)
	assert_true(parsed.has("exec"), "result carries an exec key")
	assert_true(parsed.has("autoexec"), "result carries an autoexec key")
	var lines: PackedStringArray = parsed["exec"]
	assert_eq(lines.size(), 3, "--exec lines are split on ; and concatenated across repeats: %s" % [lines])
	assert_eq(lines[0], "god on", "first line")
	assert_eq(lines[1], "noclip on", "second line")
	assert_eq(lines[2], "heal", "a later --exec appends after the earlier one")
	assert_eq(String(parsed["autoexec"]), "user://repro.cfg", "--autoexec resolves like an exec name (bare -> user://)")


func test_parse_cmdline_with_nothing_relevant() -> void:
	var parsed: Dictionary = ConsoleScript.parse_cmdline(PackedStringArray())
	var lines: PackedStringArray = parsed["exec"]
	assert_eq(lines.size(), 0, "no --exec means no lines")
	assert_eq(String(parsed["autoexec"]), "", "no --autoexec means an empty override")
	var other: Dictionary = ConsoleScript.parse_cmdline(PackedStringArray(["--verbose", "--exec"]))
	var other_lines: PackedStringArray = other["exec"]
	assert_eq(other_lines.size(), 0, "a bare --exec with no = is not a line")


# --- bind_key_from_word -------------------------------------------------------------------------------------

func test_bind_key_from_word_resolves_godot_key_names() -> void:
	assert_eq(ConsoleScript.bind_key_from_word("F6"), KEY_F6, "a function key by name")
	assert_eq(ConsoleScript.bind_key_from_word("PageUp"), KEY_PAGEUP, "a navigation key by its Godot name")
	assert_eq(ConsoleScript.bind_key_from_word("Space"), KEY_SPACE, "space by name")
	assert_eq(ConsoleScript.bind_key_from_word("G"), KEY_G, "a letter")
	assert_eq(ConsoleScript.bind_key_from_word("5"), KEY_5, "a digit")


func test_bind_key_from_word_accepts_enum_spelling_and_lowercase() -> void:
	assert_eq(ConsoleScript.bind_key_from_word("KP_ADD"), KEY_KP_ADD, "the KEY_ enum spelling minus its prefix")
	assert_eq(ConsoleScript.bind_key_from_word("KEY_KP_ADD"), KEY_KP_ADD, "the full KEY_ enum spelling")
	assert_eq(ConsoleScript.bind_key_from_word("kp add"), KEY_KP_ADD, "Godot's own display name, lowercase")
	assert_eq(ConsoleScript.bind_key_from_word("f6"), KEY_F6, "lowercase function key")
	assert_eq(ConsoleScript.bind_key_from_word("g"), KEY_G, "lowercase letter")
	assert_eq(ConsoleScript.bind_key_from_word("  F7  "), KEY_F7, "surrounding whitespace is trimmed")


func test_bind_key_from_word_refuses_junk_and_modifier_combos() -> void:
	assert_eq(ConsoleScript.bind_key_from_word("notakey"), KEY_NONE, "an unknown word is KEY_NONE")
	assert_eq(ConsoleScript.bind_key_from_word(""), KEY_NONE, "blank is KEY_NONE")
	assert_eq(ConsoleScript.bind_key_from_word("Ctrl+F6"), KEY_NONE, "modifier combos are refused (the fire path compares the raw keycode)")


func test_bind_key_round_trips_through_get_keycode_string() -> void:
	# The binds file stores OS.get_keycode_string(keycode) as the key name; loading it back must find the same key.
	for keycode in [KEY_F6, KEY_KP_ADD, KEY_QUOTELEFT, KEY_G, KEY_PAGEDOWN, KEY_SPACE]:
		var name := OS.get_keycode_string(keycode)
		assert_eq(ConsoleScript.bind_key_from_word(name), keycode, "'%s' round-trips to its keycode" % name)


# --- the console off-tree: parses, exports present, binds file round-trip ------------------------------------

func test_console_constructs_off_tree_with_scripting_exports() -> void:
	# .new() without add_child never runs _ready: no debug gate, no UI, no autoexec poll, no binds load.
	var console = (ConsoleScript as GDScript).new()
	assert_not_null(console, "DebugConsole constructs off-tree")
	assert_true(bool(console.get("run_autoexec")), "autoexec is on by default (debug builds only, gated in _ready)")
	assert_eq(String(console.get("autoexec_path")), "user://autoexec.cfg", "the default autoexec lives under user://")
	assert_true(bool(console.get("mirror_to_stdout")), "the stdout mirror is on by default")
	assert_eq(int(console.get("exec_depth_limit")), 4, "the exec nesting cap defaults to 4")
	assert_eq(String(console.get("binds_path")), "user://debug_binds.cfg", "binds persist under user://")
	assert_true(console.has_method(&"run_line"), "run_line is the public typed-line entry (the menu's fallback route)")
	assert_true(console.has_method(&"run_meta"), "run_meta is the public entry the menu forwards exec/bind through")
	assert_true(console.has_method(&"echo"), "echo is the public entry the menu prints through")
	# Off-tree, _ready never ran, so the debug gate never opened: run_meta must refuse with a line, not act.
	var refused: Variant = console.call(&"run_meta", "bind", PackedStringArray())
	assert_true(refused is PackedStringArray, "run_meta always answers with lines")
	assert_true((refused as PackedStringArray).size() == 1 and String((refused as PackedStringArray)[0]).contains("disabled"),
		"an un-gated console says it is disabled instead of touching its binds: %s" % [refused])
	console.free()


func test_save_binds_refuses_a_path_outside_user() -> void:
	# binds_path is an export a scene could point anywhere; the console must never write a project file.
	var console = (ConsoleScript as GDScript).new()
	console.set("binds_path", NEVER_WRITTEN)
	var binds: Dictionary = console.get("_binds")
	binds[KEY_F6] = "god"
	console.call(&"_save_binds")
	console.free()
	assert_false(FileAccess.file_exists(NEVER_WRITTEN), "a res:// binds_path is refused — nothing is written under the project")


func test_menu_quote_arg_rebuilds_a_line_the_tokenizer_splits_the_same_way() -> void:
	# The menu's run_line FALLBACK re-joins widget tokens into one console line; the console's tokenizer must
	# hand back exactly the argv the widgets produced (spaces survive, an empty token still counts, inner quotes
	# cannot be escaped so they are dropped).
	assert_eq(MenuScript._quote_arg("F6"), "F6", "a plain token is left bare")
	assert_eq(MenuScript._quote_arg("god; noclip on"), "\"god; noclip on\"", "a token with spaces is quoted")
	assert_eq(MenuScript._quote_arg(""), "\"\"", "an empty token is kept as an explicit empty argument")
	assert_eq(MenuScript._quote_arg("say \"hi\" now"), "\"say hi now\"", "inner quotes are dropped (no escape exists)")
	var line := "bind %s %s" % [MenuScript._quote_arg("F6"), MenuScript._quote_arg("god; noclip on")]
	var tokens: PackedStringArray = Commands.tokenize(line)
	assert_eq(tokens.size(), 3, "bind + key + one line token: %s" % [tokens])
	assert_eq(tokens[2], "god; noclip on", "the chained line arrives as ONE argument, exactly as the widget produced it")


func test_binds_file_round_trip_off_tree() -> void:
	# _load_binds / _save_binds touch only `binds_path` and the console's own toggle_key — no tree, no UI — so an
	# off-tree console can prove the ConfigFile shape: [binds] key name -> line.
	var writer = (ConsoleScript as GDScript).new()
	writer.set("binds_path", TMP_BINDS)
	var binds: Dictionary = writer.get("_binds")
	binds[KEY_F6] = "god; noclip on"
	binds[KEY_KP_ADD] = "heal"
	writer.call(&"_save_binds")
	writer.free()
	assert_true(FileAccess.file_exists(TMP_BINDS), "save wrote the scratch binds file")

	var cfg := ConfigFile.new()
	assert_eq(cfg.load(TMP_BINDS), OK, "the scratch file is a readable ConfigFile")
	assert_true(cfg.has_section("binds"), "binds live in a [binds] section")
	assert_eq(String(cfg.get_value("binds", OS.get_keycode_string(KEY_F6), "")), "god; noclip on", "F6's line is stored under its key name")

	var reader = (ConsoleScript as GDScript).new()
	reader.set("binds_path", TMP_BINDS)
	reader.call(&"_load_binds")
	var loaded: Dictionary = reader.get("_binds")
	assert_eq(loaded.size(), 2, "both binds load back: %s" % [loaded])
	assert_eq(String(loaded.get(KEY_F6, "")), "god; noclip on", "F6 round-trips")
	assert_eq(String(loaded.get(KEY_KP_ADD, "")), "heal", "Kp Add round-trips")
	reader.free()


func test_load_binds_skips_junk_and_the_console_toggle_key() -> void:
	# A hand-edited file: an unknown key name, a non-String value, a blank line and the console's own toggle key
	# (backtick) must all be skipped — never crash the boot, never double-book the toggle.
	var cfg := ConfigFile.new()
	cfg.set_value("binds", "NotAKey", "god")
	cfg.set_value("binds", OS.get_keycode_string(KEY_F8), 42)
	cfg.set_value("binds", OS.get_keycode_string(KEY_F9), "   ")
	cfg.set_value("binds", OS.get_keycode_string(KEY_QUOTELEFT), "help")
	cfg.set_value("binds", OS.get_keycode_string(KEY_F10), "clock")
	assert_eq(cfg.save(TMP_BINDS), OK, "wrote the junk fixture")

	var console = (ConsoleScript as GDScript).new()
	console.set("binds_path", TMP_BINDS)
	assert_eq(int(console.get("toggle_key")), KEY_QUOTELEFT, "precondition: the console toggles on backtick")
	console.call(&"_load_binds")
	var loaded: Dictionary = console.get("_binds")
	assert_eq(loaded.size(), 1, "only the one sane entry survives: %s" % [loaded])
	assert_eq(String(loaded.get(KEY_F10, "")), "clock", "F10 = clock is the survivor")
	assert_false(loaded.has(KEY_QUOTELEFT), "the console's own toggle key is never adopted as a bind")
	console.free()


func test_load_binds_with_no_file_is_empty_and_quiet() -> void:
	var console = (ConsoleScript as GDScript).new()
	console.set("binds_path", "user://test_debug_binds_definitely_absent.cfg")
	console.call(&"_load_binds")
	var loaded: Dictionary = console.get("_binds")
	assert_eq(loaded.size(), 0, "no file means no binds — the normal first-run state")
	console.free()


# --- registry seam: the meta rows this console answers exist ------------------------------------------------

func test_registry_carries_the_exec_and_bind_meta_rows() -> void:
	var exec_row: Dictionary = Commands.find("exec")
	assert_false(exec_row.is_empty(), "the registry has an `exec` row")
	assert_eq(exec_row["mod"], &"meta", "exec is a meta row (the console answers it)")
	assert_eq(int(exec_row["min_args"]), 1, "exec needs a file")
	var bind_row: Dictionary = Commands.find("bind")
	assert_false(bind_row.is_empty(), "the registry has a `bind` row")
	assert_eq(bind_row["mod"], &"meta", "bind is a meta row (the console answers it)")
	assert_eq(int(bind_row["min_args"]), 0, "bare `bind` lists")
	var kinds: Array = bind_row["args"]
	assert_eq(kinds.size(), 2, "bind takes at most key + line")
	# `wait` is deliberately NOT a row: it is exec-only and handled before run_line.
	assert_true(Commands.find("wait").is_empty(), "wait is exec-only, never a registry row")


## Every `&"meta"` row must have a match arm in the console's _run_meta — pinned by SOURCE TEXT, the same idiom
## tests/test_debug_commands.gd uses for the player/world modules (run_line cannot be driven off-tree: it needs
## the built log). The menu now FORWARDS unknown meta rows to the console, so a missing arm here is the only place
## a meta command can go dead — it would print the console's NO_HANDLER line from both surfaces.
func test_console_has_a_meta_case_for_every_meta_row() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/components/debug_console.gd")
	assert_false(src.is_empty(), "the console script must be readable")
	for row in Commands.COMMANDS:
		if row["mod"] != &"meta":
			continue
		var n := String(row["name"])
		assert_true(src.contains("\"%s\":" % n),
			"meta row '%s' has no `\"%s\":` case in debug_console.gd _run_meta — the command is dead on both surfaces" % [n, n])
