@tool
extends RefCounted

## Domain D of the project audit: the hardcoded player-facing text RATCHET. Scans .gd source for raw string
## literals at PAINT sites — the curated idioms below that put words on the player's screen. Every
## player-facing string belongs in PlayerText (scripts/ui/player_text.gd): it is the single chokepoint the
## deferred tr() localization sweep will wrap, so a raw literal at a paint site is debt this domain surfaces.
## The GUT guard (tests/test_player_text.gd) reuses scan_gd_text over a hand-maintained SHRINK-ONLY baseline,
## so the guard and this panel can never disagree — the panel lists the live debt, the test stops it growing.
## run() returns Array[{severity, source, message}] rows like the other domains; scan_gd_text is the pure,
## unit-testable core returning offender dicts {source, line, pattern, excerpt}.

const ScanDisk := preload("res://addons/cybersunday_tools/panel_audit/scan_disk.gd")

## Mirrors ScanDisk.SKIP_DIRS (+ tests_soak, excluded for the same reason as tests: soak fixtures are
## synthetic, not shipped content). addons/ is editor tooling — its strings paint editor surfaces.
const SKIP_DIRS: Array[String] = [".godot", "addons", ".git", "tests", "tests_soak"]
## File→Run editor tools print to the Output panel / editor dialogs, never the player HUD — their strings are
## deliberately NOT PlayerText, so scanning them would be permanent false-positive noise.
const SKIP_DIR_PATHS: Array[String] = ["res://scripts/tools"]

## The CURATED paint idioms — every entry is an ENUMERABLE call/assignment shape, NEVER a fuzzy English-word
## grep (prose in ordinary strings — ids, paths, format keys — must not trip this). Each regex captures the
## literal so an empty "" (clearing a label) is skipped; a "[PH] " literal is NOT skipped — [PH] marks
## unauthored COPY, but the chokepoint rule is about WHERE the string lives, so a [PH] literal at a paint
## site is still debt. Verified against the tree 2026-07-26:
##  - live production hits today: text_assign, add_extra_choice, make_title, make_hint, add_button;
##  - zero-offender WATCH patterns (the API exists, production feeds it PlayerText — a new literal is
##    exactly the regression this ratchet exists to catch): placeholder_assign, tooltip_assign,
##    notify_toast, ui_toast, push_toast (also matches _push_toast), attach_tip, title_text.
## attach_tip's literal is its SECOND arg; [^,]* is bounded by the first comma, so a first arg containing a
## comma (a nested two-arg call) is a known false-negative — acceptable for a ratchet.
const PATTERNS := {
	"text_assign": "\\.text\\s*=\\s*\"([^\"]*)\"",
	"placeholder_assign": "\\.placeholder_text\\s*=\\s*\"([^\"]*)\"",
	"tooltip_assign": "\\.tooltip_text\\s*=\\s*\"([^\"]*)\"",
	"add_extra_choice": "\\badd_extra_choice\\(\\s*\"([^\"]*)\"",
	"notify_toast": "\\bnotify_toast\\(\\s*\"([^\"]*)\"",
	"ui_toast": "\\bUI\\.toast\\(\\s*\"([^\"]*)\"",
	"push_toast": "push_toast\\(\\s*\"([^\"]*)\"",
	"make_title": "\\bmake_title\\(\\s*\"([^\"]*)\"",
	"make_hint": "\\bmake_hint\\(\\s*\"([^\"]*)\"",
	"add_button": "_add_button\\(\\s*\"([^\"]*)\"",
	"attach_tip": "\\battach_tip\\([^,]*,\\s*\"([^\"]*)\"",
	"title_text": "\\btitle_text\\(\\s*\"([^\"]*)\"",
}


static func run() -> Array:
	var offenders: Array = []
	_scan_dir("res://", offenders)
	var out: Array = []
	for o: Dictionary in offenders:
		out.append({
			"severity": "WARN",
			"source": String(o["source"]),
			"message": "Hardcoded player-facing string (line %d, %s): %s — move it into PlayerText (tests/test_player_text.gd ratchets the count down-only)." % [int(o["line"]), String(o["pattern"]), String(o["excerpt"])],
		})
	return out


## Paint-site literal findings in one .gd's source text. Comments are masked FIRST via ScanDisk.mask_comments
## (reused, not reimplemented — length-preserving, so match offsets stay valid in the ORIGINAL text and the
## reported line/excerpt are exact). A literal quoted inside a `#` comment is prose, never a finding.
static func scan_gd_text(text: String, source: String) -> Array:
	var out: Array = []
	var masked := ScanDisk.mask_comments(text)
	var lines := text.split("\n")
	for pname: String in PATTERNS:
		var re := RegEx.new()
		re.compile(PATTERNS[pname])
		for m in re.search_all(masked):
			if m.get_string(1).is_empty():
				continue  # `.text = ""` clears a control — not a paint
			var start := m.get_start(0)
			# count(what, from, to) treats to==0 as "to the end", so a match at offset 0 needs the guard.
			var line := (masked.count("\n", 0, start) + 1) if start > 0 else 1
			var excerpt := lines[line - 1].strip_edges() if line - 1 < lines.size() else ""
			out.append({"source": source, "line": line, "pattern": pname, "excerpt": excerpt.left(120)})
	# Findings are collected per-pattern; sort by line so panel rows read top-to-bottom per file.
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["line"]) < int(b["line"]))
	return out


static func _scan_dir(path: String, offenders: Array) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var entry := d.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = d.get_next()
			continue
		var full := path.path_join(entry)
		if d.current_is_dir():
			if not SKIP_DIRS.has(entry) and not SKIP_DIR_PATHS.has(full):
				_scan_dir(full, offenders)
		elif entry.get_extension() == "gd":
			var f := FileAccess.open(full, FileAccess.READ)
			if f != null:
				offenders.append_array(scan_gd_text(f.get_as_text(), full))
		entry = d.get_next()
	d.list_dir_end()
