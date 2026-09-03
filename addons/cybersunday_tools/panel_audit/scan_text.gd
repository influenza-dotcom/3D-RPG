@tool
extends RefCounted

## Domain D of the project audit: the hardcoded player-facing text RATCHET. Scans .gd source for raw string
## literals at PAINT sites — the curated idioms below that put words on the player's screen. Every
## player-facing string belongs in PlayerText (scripts/ui/player_text.gd): it is the single chokepoint the
## deferred tr() localization sweep will wrap, so a raw literal at a paint site is debt this domain surfaces.
## The GUT guard (tests/test_player_text.gd) reuses scan_gd_text over a hand-maintained SHRINK-ONLY baseline,
## so the guard and this panel can never disagree — the panel lists the live debt, the test stops it growing.
## run() returns Array[{severity, source, message, domain}] rows like the other domains (every row is domain "code":
## the fix is a programmer moving a literal into PlayerText, so the Audit tab hides these under its default
## "Scene + Content" view); scan_gd_text is the pure, unit-testable core returning offender dicts
## {source, line, pattern, excerpt}, and to_finding() is the pure offender -> row step run() maps through. The
## offender dict is what the GUT ratchet and scripts/tools/text_debt.gd read -- its shape never changes; the row
## dict may only GAIN keys (validate_all.gd and cyber_cmds.gd print its message and severity).

const ScanDisk := preload("res://addons/cybersunday_tools/panel_audit/scan_disk.gd")
## Shared one-read-per-file cache (see scan_cache.gd) — this domain re-reads the same .gd files scan_disk and
## scan_menu_sound already read during one Scan. Inert outside audit_panel's begin()/end() window.
const ScanCache := preload("res://addons/cybersunday_tools/panel_audit/scan_cache.gd")
## The Audit tab's row-filter domain for every row this scanner emits.
const DOMAIN := "code"

## Mirrors ScanDisk.SKIP_DIRS (+ tests_soak, excluded for the same reason as tests: soak fixtures are
## synthetic, not shipped content). addons/ is editor tooling — its strings paint editor surfaces.
const SKIP_DIRS: Array[String] = [".godot", "addons", ".git", "tests", "tests_soak"]
## File→Run editor tools print to the Output panel / editor dialogs, never the player HUD — their strings are
## deliberately NOT PlayerText, so scanning them would be permanent false-positive noise.
const SKIP_DIR_PATHS: Array[String] = ["res://scripts/tools"]
## Individual DEV-ONLY surfaces, skipped for exactly the SKIP_DIR_PATHS reason but living under a walked root.
## A file earns a place here only if NOTHING it paints can ever be player copy — not "it currently has none".
##  - debug_overlay.gd: the F3 developer HUD (FPS / draw calls / node + NPC counts / error tallies), toggled by
##    a raw dev key, never shipped-facing prose. Its readouts must never enter a translation catalog.
##  - debug_console.gd: the backtick developer console. Everything it paints is a command name, a usage line
##    or a command's result — developer diagnostics keyed to identifiers in code, not copy. It is gated on
##    OS.is_debug_build(), so a shipped build never instantiates it at all.
##  - debug_menu.gd: the F1 clickable cheat menu. Its labels are generated from the DebugCommands registry
##    (command names + their one-line developer help), same bar and same debug-build gate as the console.
##  - debug_event_ticker.gd / ai_event_log.gd: the on-screen event column and the AI transition panel. Every line
##    they paint is a timestamped signal/state-transition record keyed to identifiers in code (quest ids, faction
##    ids, perception state names) — a developer timeline, never copy. Same debug-build gate.
## NOT a dump for inconvenient files: npc_bark_ui.gd, for instance, stays scanned because real bark copy
## paints through it (its one non-prose glyph is a designer @export instead — see bubble_tail_glyph).
const SKIP_FILES: Array[String] = [
	"res://scripts/components/debug_overlay.gd",
	"res://scripts/components/debug_console.gd",
	"res://scripts/components/debug_menu.gd",
	"res://scripts/components/debug_event_ticker.gd",
	"res://scripts/components/ai_event_log.gd",
	"res://scripts/tools/dialogue_ui_qa_shots.gd",
]

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
	"add_exit_choice": "\\badd_exit_choice\\(\\s*\"([^\"]*)\"",
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
		out.append(to_finding(o))
	return out


## One scan_gd_text offender ({source, line, pattern, excerpt}) -> the audit row the panel lists. PURE, so the row's
## severity / message / domain are pinned by tests/test_devtools_audit.gd without a project walk.
static func to_finding(o: Dictionary) -> Dictionary:
	return {
		"severity": "WARN",
		"source": String(o["source"]),
		"message": "Hardcoded player-facing string (line %d, %s): %s — move it into PlayerText (tests/test_player_text.gd ratchets the count down-only)." % [int(o["line"]), String(o["pattern"]), String(o["excerpt"])],
		"domain": DOMAIN,
	}


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
		elif entry.get_extension() == "gd" and not SKIP_FILES.has(full):
			var text := ScanCache.text_of(full)
			if not text.is_empty():
				offenders.append_array(scan_gd_text(text, full))
		entry = d.get_next()
	d.list_dir_end()
