extends SceneTree

## TEXT DEBT REPORT — the headless view of Domain D (hardcoded player-facing strings). Prints the per-file
## offender counts in exactly the shape tests/test_player_text.gd's BASELINE table wants, so paying the debt
## down never means hand-counting: move literals into PlayerText, re-run this, paste the table.
##
## Run it (headless, no editor needed):
##   godot --headless -s scripts/tools/text_debt.gd            # per-file counts + total
##   godot --headless -s scripts/tools/text_debt.gd -- --list  # also list every offending line
##
## Scope MIRRORS tests/test_player_text.gd (production roots + top-level res://*.gd, minus scripts/tools),
## NOT ScanText.run()'s own res:// walk — the guard's scope is the one the BASELINE is measured against, and
## this file lives in the excluded scripts/tools/ so it can never count itself.

## RUNTIME load, never preload: ScanText preloads ScanDisk, whose compile chain reaches loot_table.gd ->
## GameSettings — an autoload that ISN'T registered yet when a `-s` script's compile chain runs at boot
## ("Identifier not found: GameSettings"). By the first process frame the autoloads are up. Same reasoning
## validate_all.gd documents for ContentValidator / ScanDisk.
const SCAN_TEXT_PATH := "res://addons/cybersunday_tools/panel_audit/scan_text.gd"

const PRODUCTION_ROOTS := ["res://scripts", "res://managers", "res://scenes", "res://resources"]
const EXCLUDED_DIRS := ["res://scripts/tools"]

var _done := false
var _scan_text: GDScript = null
var _skip_files: Array = []


func _process(_delta: float) -> bool:
	if not _done:
		_done = true
		quit(_run())
	return false


func _run() -> int:
	var list_lines := false
	for a in OS.get_cmdline_user_args():
		if a == "--list":
			list_lines = true

	_scan_text = load(SCAN_TEXT_PATH)  # runtime load: see the const comment (autoload timing at boot)
	if _scan_text == null:
		printerr("text_debt: could not load ", SCAN_TEXT_PATH)
		return 1
	_skip_files = _scan_text.get_script_constant_map().get("SKIP_FILES", [])

	var offenders: Array = []
	var d := DirAccess.open("res://")
	if d != null:
		d.list_dir_begin()
		var entry := d.get_next()
		while entry != "":
			if not entry.begins_with(".") and not d.current_is_dir() and entry.get_extension() == "gd":
				_scan_file("res://".path_join(entry), offenders)
			entry = d.get_next()
		d.list_dir_end()
	for root: String in PRODUCTION_ROOTS:
		_walk(root, offenders)

	var by_file := {}
	for o: Dictionary in offenders:
		var src := String(o["source"])
		if not by_file.has(src):
			by_file[src] = []
		(by_file[src] as Array).append(o)

	var files: Array = by_file.keys()
	files.sort()
	print_rich("\n[b]== text debt (Domain D: hardcoded player-facing strings) ==[/b]")
	print("\nBASELINE table shape (paste into tests/test_player_text.gd):")
	for f: String in files:
		print("\t\"%s\": %d," % [f, (by_file[f] as Array).size()])
	if list_lines:
		for f: String in files:
			print("\n  ", f)
			for o: Dictionary in by_file[f]:
				print("    line %4d  %-18s %s" % [int(o["line"]), String(o["pattern"]), String(o["excerpt"])])
	print_rich("\n[b]TOTAL: %d[/b] offender(s) across %d file(s)   (BASELINE_HIGH_WATER)" % [offenders.size(), files.size()])
	return 0


func _walk(dir: String, offenders: Array) -> void:
	if EXCLUDED_DIRS.has(dir):
		return
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var entry := d.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = d.get_next()
			continue
		var full: String = dir.path_join(entry)
		if d.current_is_dir():
			_walk(full, offenders)
		elif entry.get_extension() == "gd":
			_scan_file(full, offenders)
		entry = d.get_next()
	d.list_dir_end()


func _scan_file(path: String, offenders: Array) -> void:
	# Honour the scanner's own per-file skips (dev-only surfaces) — this walk calls scan_gd_text directly
	# instead of ScanText.run()'s _scan_dir, so the const is the one source of truth all three consumers
	# (panel, this tool, tests/test_player_text.gd) read.
	if _skip_files.has(path):
		return
	var src := FileAccess.get_file_as_string(path)
	if src.is_empty():
		return
	offenders.append_array(_scan_text.scan_gd_text(src, path))
