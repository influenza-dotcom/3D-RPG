extends GutTest

## The PURE half of the console's scripting surface (exec / autoexec / bind / --exec): the static helpers factored
## out of scripts/components/debug_console.gd, driven OFF-TREE. The console is constructed with .new() and never
## add_child'd, so _ready (the debug gate, the UI build, the autoexec poll, the binds load) never runs — this file
## proves the script parses and the helpers behave, the same bar tests/test_debug_commands.gd sets for the UI.
##
## Disk: ONLY user://test_debug_binds_* / user://test_debug_exec_* scratch paths, removed in after_each. The console's real files
## (user://debug_binds.cfg, user://autoexec.cfg) are never read or written here. NEVER_WRITTEN is a res:// path
## the user://-only guard must refuse — it exists to prove nothing lands there (and is swept if a regression does).

# Preloaded BY PATH, never by class_name: a brand-new class_name is not in the editor's global class cache until
# it rescans, and a typed reference would fail this whole file to parse (the debug_overlay.gd:9-11 cascade).
const ConsoleScript := preload("res://scripts/components/debug_console.gd")
const MenuScript := preload("res://scripts/components/debug_menu.gd")
const Commands := preload("res://scripts/components/debug_commands.gd")

const TMP_BINDS := "user://test_debug_binds_tmp.cfg"
const NEVER_WRITTEN := "res://tests/test_debug_binds_never_written.cfg"
## Two scratch command files for the exec nesting tests (distinct lines so queue ORDER is observable).
const TMP_EXEC_OUTER := "user://test_debug_exec_outer_tmp.cfg"
const TMP_EXEC_INNER := "user://test_debug_exec_inner_tmp.cfg"


## The real console with its two tree-bound edges stubbed: the scrollback append is RECORDED instead of needing the
## built log (off-tree, the shipped _add_line drops every line because the log box was never built), and `keys`' walk
## of the scene tree for OTHER drop-ins' toggle keys answers "none" (off-tree, get_tree() raises an engine error).
## _run_meta's dispatch, the binds file read and every line the console composes are the shipped code.
class _ConsoleSpy extends ConsoleScript:
	var logged: PackedStringArray = PackedStringArray()

	func _add_line(text: String, _color: Color) -> void:
		logged.append(text)

	func _toggle_key_pairs() -> Array:
		return []


func after_each() -> void:
	for p in [TMP_BINDS, NEVER_WRITTEN, TMP_EXEC_OUTER, TMP_EXEC_INNER]:
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
	# The engine itself WOULD resolve a combo (to F6 | the Ctrl mask), so KEY_NONE here is the console's own refusal,
	# not a lookup miss — a bind stored under a masked code could never match the raw keycode the fire path compares.
	assert_ne(int(OS.find_keycode_from_string("Ctrl+F6")), KEY_NONE, "precondition: Godot parses 'Ctrl+F6' into a masked keycode")
	assert_eq(ConsoleScript.bind_key_from_word("Ctrl+F6"), KEY_NONE, "modifier combos are refused (the fire path compares the raw keycode)")


func test_bind_key_round_trips_through_get_keycode_string() -> void:
	# The binds file stores OS.get_keycode_string(keycode) as the key name; loading it back must find the same key.
	for keycode in [KEY_F6, KEY_KP_ADD, KEY_QUOTELEFT, KEY_G, KEY_PAGEDOWN, KEY_SPACE]:
		var name := OS.get_keycode_string(keycode)
		assert_eq(ConsoleScript.bind_key_from_word(name), keycode, "'%s' round-trips to its keycode" % name)


# --- the console off-tree: parses, exports present, binds file round-trip ------------------------------------

func test_console_off_tree_refuses_meta_until_enabled_and_keeps_its_files_under_user() -> void:
	# .new() without add_child never runs _ready: no debug gate, no UI, no autoexec poll, no binds load.
	var console = (ConsoleScript as GDScript).new()
	# DebugMenu finds a console DUCK-TYPED (_search_console: echo + run_line) and forwards exec/bind through
	# run_meta via has_method — renaming any of the three silently disconnects the menu from the console.
	assert_true(console.has_method(&"run_line"), "run_line is the public typed-line entry (the menu's fallback route)")
	assert_true(console.has_method(&"run_meta"), "run_meta is the public entry the menu forwards exec/bind through")
	assert_true(console.has_method(&"echo"), "echo is the public entry the menu prints through")
	# The default files must live under user:// — an exported build cannot write res://, and a dev build must never
	# write a project file (the same rule _save_binds enforces on a hand-set path).
	assert_true(String(console.get("binds_path")).begins_with("user://"), "binds persist under user://: %s" % String(console.get("binds_path")))
	assert_true(ConsoleScript.resolve_exec_path(String(console.get("autoexec_path"))).begins_with("user://"),
		"the default autoexec resolves under user://: %s" % String(console.get("autoexec_path")))
	# Off-tree, _ready never ran, so the debug gate never opened: run_meta must refuse with a line, not act.
	var refused: Variant = console.call(&"run_meta", "bind", PackedStringArray())
	assert_true(refused is PackedStringArray, "run_meta always answers with lines")
	assert_true((refused as PackedStringArray).size() == 1 and String((refused as PackedStringArray)[0]).contains("disabled"),
		"an un-gated console says it is disabled instead of touching its binds: %s" % [refused])
	# Control: the SAME call past the gate answers the bind listing, so the refusal above is the gate and nothing else.
	console.set("_enabled", true)
	var listed: PackedStringArray = console.call(&"run_meta", "bind", PackedStringArray())
	assert_gt(listed.size(), 0, "an enabled console answers `bind` with lines")
	assert_false(String(listed[0]).contains("disabled"), "past the gate the console lists its binds instead of refusing: %s" % [listed])
	assert_true(String(listed[0]).begins_with("bind:"), "the listing is the bind command's own output: %s" % [listed])
	console.free()


func _write_exec(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	assert_true(f != null, "scratch exec file %s opens for writing" % path)
	if f != null:
		f.store_string(text)
		f.close()


func _queued_lines(console: Object) -> PackedStringArray:
	var out := PackedStringArray()
	for entry in console.get("_exec_queue"):
		out.append(String(entry["line"]))
	return out


func test_exec_depth_limit_refuses_only_past_the_cap() -> void:
	# A file that execs itself must stop at exec_depth_limit, but every level UP TO the cap must still run.
	_write_exec(TMP_EXEC_OUTER, "god on\nheal\n")
	var console = (ConsoleScript as GDScript).new()
	console.set("exec_depth_limit", 2)
	var top: PackedStringArray = console.call(&"_exec_file", TMP_EXEC_OUTER, 1)
	assert_true(top.size() == 1 and top[0].contains("queued"), "a top-level exec queues its file: %s" % [top])
	var at_cap: PackedStringArray = console.call(&"_exec_file", TMP_EXEC_OUTER, 2)
	assert_true(at_cap.size() == 1 and at_cap[0].contains("queued"), "a nested exec AT the cap still runs: %s" % [at_cap])
	assert_eq(_queued_lines(console).size(), 4, "both files' lines are queued")
	var past: PackedStringArray = console.call(&"_exec_file", TMP_EXEC_OUTER, 3)
	assert_true(past.size() == 1 and past[0].contains("refused"), "one level past the cap is refused: %s" % [past])
	assert_eq(_queued_lines(console).size(), 4, "and the refused file queued nothing")
	# The cap is honoured whatever it is set to, and a 0/negative cap still lets a typed top-level exec run.
	console.set("exec_depth_limit", 0)
	var floor_top: PackedStringArray = console.call(&"_exec_file", TMP_EXEC_OUTER, 1)
	assert_true(floor_top[0].contains("queued"), "a cap of 0 floors to 1: a typed exec is never refused: %s" % [floor_top])
	var floor_nested: PackedStringArray = console.call(&"_exec_file", TMP_EXEC_OUTER, 2)
	assert_true(floor_nested[0].contains("refused"), "…but any nesting under a floored cap is: %s" % [floor_nested])
	console.free()


func test_nested_exec_splices_in_front_and_a_top_level_exec_appends() -> void:
	# A nested exec reads like a shell `source`: its lines run before the rest of the outer file. A second typed exec
	# while one is still stepping runs AFTER it, never interleaved.
	_write_exec(TMP_EXEC_OUTER, "god on\nheal\n")
	_write_exec(TMP_EXEC_INNER, "clock\n")
	var console = (ConsoleScript as GDScript).new()
	console.call(&"_exec_file", TMP_EXEC_OUTER, 1)
	console.call(&"_exec_file", TMP_EXEC_INNER, 2)
	assert_eq(_queued_lines(console), PackedStringArray(["clock", "god on", "heal"]),
		"the nested file's line runs next, ahead of the outer file's remaining lines")
	console.call(&"_exec_file", TMP_EXEC_INNER, 1)
	assert_eq(_queued_lines(console), PackedStringArray(["clock", "god on", "heal", "clock"]),
		"a top-level exec queues behind everything already stepping")
	var missing: PackedStringArray = console.call(&"_exec_file", "user://test_debug_exec_definitely_absent.cfg", 1)
	assert_true(missing[0].contains("no such file"), "a missing file is reported: %s" % [missing])
	assert_eq(_queued_lines(console).size(), 4, "and queues nothing")
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
	# A first run has no binds file yet. Loading must CLEAR whatever the console already held (a reload never keeps a
	# stale key live) and say nothing — the warning line is reserved for a file that EXISTS but will not parse. The
	# console is seeded so the clear is visible, and the spy records the scrollback an off-tree console would drop.
	var console := _ConsoleSpy.new()
	console.binds_path = "user://test_debug_binds_definitely_absent.cfg"
	console._binds[KEY_F6] = "god"
	console._load_binds()
	assert_eq(console._binds.size(), 0, "no file means no binds — a stale bind from before the load is cleared: %s" % [console._binds])
	assert_eq(console.logged.size(), 0, "a missing file is the normal first-run state and prints nothing: %s" % [console.logged])
	# CONTROL: the same console pointed at a file that EXISTS but will not parse does warn (naming the file), so the
	# silence above is the missing-file branch and not a console that can never print.
	var f := FileAccess.open(TMP_BINDS, FileAccess.WRITE)
	assert_true(f != null, "scratch binds file %s opens for writing" % TMP_BINDS)
	if f != null:
		f.store_string("[binds
F6 = \"god
")  # an unterminated section header: ConfigFile.load refuses it
		f.close()
	console.binds_path = TMP_BINDS
	console._binds[KEY_F6] = "god"
	console._load_binds()
	assert_engine_error("ConfigFile parse error", "the engine itself reports the unparseable fixture (expected, consumed here)")
	assert_eq(console._binds.size(), 0, "an unparseable file loads no binds either")
	assert_eq(console.logged.size(), 1, "an existing file that will not load is reported, once: %s" % [console.logged])
	if console.logged.size() == 1:
		assert_true(console.logged[0].contains(TMP_BINDS), "the warning names the file to fix or delete: %s" % console.logged[0])
	console.free()


# --- registry seam: the meta rows this console answers exist ------------------------------------------------

func test_registry_carries_the_exec_and_bind_meta_rows() -> void:
	var exec_row: Dictionary = Commands.find("exec")
	assert_false(exec_row.is_empty(), "the registry has an `exec` row")
	assert_eq(exec_row["mod"], &"meta", "exec is a meta row (the console answers it)")
	# _run_meta reads args[0] for exec unguarded, so validate() is what must refuse a bare `exec`.
	assert_ne(Commands.validate(exec_row, PackedStringArray()), "", "a bare `exec` is refused (it needs a file)")
	assert_eq(Commands.validate(exec_row, PackedStringArray(["repro.cfg"])), "", "`exec repro.cfg` runs")
	var bind_row: Dictionary = Commands.find("bind")
	assert_false(bind_row.is_empty(), "the registry has a `bind` row")
	assert_eq(bind_row["mod"], &"meta", "bind is a meta row (the console answers it)")
	assert_eq(Commands.validate(bind_row, PackedStringArray()), "", "a bare `bind` lists")
	assert_eq(Commands.validate(bind_row, PackedStringArray(["F6"])), "", "`bind F6` clears")
	assert_eq(Commands.validate(bind_row, PackedStringArray(["F6", "god; noclip on"])), "", "`bind F6 \"line\"` sets")
	assert_ne(Commands.validate(bind_row, PackedStringArray(["F6", "god", "extra"])), "",
		"a third token is refused — an unquoted chained line must not be silently truncated to its first word")
	# `wait` is deliberately NOT a row: it is exec-only and handled before run_line.
	assert_true(Commands.find("wait").is_empty(), "wait is exec-only, never a registry row")


## Every `&"meta"` row must reach a real arm in the console's _run_meta. The menu FORWARDS any meta row it has no
## answer for to run_meta, so a missing arm is the one place a meta command goes dead — it answers the console's
## NO_HANDLER line on both surfaces. DRIVEN: each row runs through the public run_meta, past the debug gate, with the
## smallest argv its registry row validates (a TEXT slot gets a file name that does not exist, so `exec` queues nothing).
func test_console_has_a_meta_case_for_every_meta_row() -> void:
	var console := _ConsoleSpy.new()
	console._enabled = true   # off-tree _ready never opened the debug gate
	# CONTROL: a meta name with no arm DOES come back as the NO_HANDLER line, so the check below can tell the two apart.
	var unknown := "zz_not_a_meta_row"
	assert_eq(console.run_meta(unknown, PackedStringArray()), PackedStringArray([ConsoleScript.NO_HANDLER % [unknown, "meta"]]),
		"a meta name with no arm answers the console's no-handler line")
	var checked := 0
	for row in Commands.COMMANDS:
		if row["mod"] != &"meta":
			continue
		checked += 1
		var n := String(row["name"])
		var argv := _smallest_valid_argv(row)
		assert_eq(Commands.validate(row, argv), "",
			"fixture: the probe argv %s satisfies meta row '%s' (extend _smallest_valid_argv for its argument kind)" % [argv, n])
		var answer: PackedStringArray = console.run_meta(n, argv)
		assert_false(answer.has(ConsoleScript.NO_HANDLER % [n, "meta"]),
			"meta row '%s' has an arm in debug_console.gd _run_meta — without one the command is dead on both surfaces: %s" % [n, answer])
	assert_gt(checked, 0, "the registry carries meta rows to check")
	assert_eq(_queued_lines(console).size(), 0, "the probe never queued a command file (the exec probe names a file that does not exist)")
	console.free()


## `row`'s min_args arguments, one harmless word per slot kind: a TEXT slot names a user:// file that never exists.
func _smallest_valid_argv(row: Dictionary) -> PackedStringArray:
	var argv := PackedStringArray()
	var kinds: Array = row["args"]
	for i in int(row["min_args"]):
		match int(kinds[i]):
			Commands.Kind.NUMBER:
				argv.append("1")
			Commands.Kind.TOGGLE:
				argv.append("off")
			Commands.Kind.COMMAND:
				argv.append("help")
			Commands.Kind.VERB:
				argv.append(String((row["verbs"] as Array)[0]))
			_:
				argv.append("test_debug_exec_definitely_absent.cfg")
	return argv
