@tool
extends RefCounted

## Domain E of the project audit: MENU-SOUND BLINDSPOTS — a player action the code took a decision about and
## then answered with SILENCE.
##
## THE RULE, in one sentence: if a function fires a SUCCESS cue from inside a branch, the branch it did NOT
## take must speak too. A `MenuStyle.play_commit()` nested under `if station.do_thing(...)` is a promise that
## the screen reports its verdict; without a matching `play_denied()` anywhere in that function, the refusal
## path is mute and a can't-afford / out-of-stock / bag-full press is indistinguishable from a dead button.
## That was the single largest gap in the cue system (menu_style.gd's "menu sounds" block owns the vocabulary):
## roughly twenty screens gated a commit on a success bool and said nothing on false, because until the
## `denied` cue existed there was nothing honest to say.
##
## WHY A SCANNER AND NOT A CHECKLIST: the cue sites are spread across ~20 screens plus the player and the
## station components, and the failure mode is invisible — nothing errors, nothing looks wrong in the editor,
## and a playtester only notices if they happen to be broke. A per-screen list drifts the moment someone adds
## a screen; this finds the shape instead.
##
## HOW THE NESTING TEST WORKS (and why it is the right filter): only a cue INSIDE a branch is a promise. An
## UNCONDITIONAL cue at the function's own base indent already fires on every path through that function, so
## there is no other path to cover — that is what exempts a shared success tail like
## ChipInstaller._grant (reached only past the charge; its refusals are cued at the screen that owns the bool)
## and a never-gated act like StartMenu's new-run stamp, with no exemption list to maintain.
##
## run() returns Array[{severity, source, message}] rows like the other domains; scan_gd_text is the pure,
## unit-testable core returning offender dicts {source, line, func_name, cue}. The GUT guard
## (tests/test_menu_sound_coverage.gd) reuses that core over a SHRINK-ONLY baseline, exactly as
## tests/test_player_text.gd does over scan_text's — the panel lists the live debt, the test stops it growing.

const ScanDisk := preload("res://addons/cybersunday_tools/panel_audit/scan_disk.gd")
## Shared one-read-per-file cache (see scan_cache.gd) — this domain re-reads the same .gd files scan_disk and
## scan_text already read during one Re-scan. Inert outside audit_panel's begin()/end() window.
const ScanCache := preload("res://addons/cybersunday_tools/panel_audit/scan_cache.gd")

## Mirrors ScanText.SKIP_DIRS. tests/ and tests_soak/ call the play_* seams to ASSERT on them (a test that
## fires a commit with no denial is not a blindspot), and addons/ is editor tooling with no menu audio at all.
const SKIP_DIRS: Array[String] = [".godot", "addons", ".git", "tests", "tests_soak"]
## File→Run editor tools drive no player-facing menu.
const SKIP_DIR_PATHS: Array[String] = ["res://scripts/tools"]
## MenuStyle itself DEFINES the seams (play_commit/play_denied are one-line bodies calling play_ui) — scanning
## the vocabulary's own implementation for uses of the vocabulary is pure noise.
const SKIP_FILES: Array[String] = ["res://scripts/ui/menu_style.gd"]

## Cues that assert SOMETHING HAPPENED. play_step is here because the toggles and steppers use it as their
## confirm (implants_screen / character_creation / implant_choice): "the value moved" is a success claim just
## as much as "money changed hands".
const SUCCESS_CUES: Array[String] = ["play_commit", "play_select", "play_step", "play_slider_step"]
## The cue that discharges the obligation. play_back deliberately does NOT count, even though it is sometimes
## the right companion: it means "this closed / I honoured your cancel", which is exactly the confusion the
## denial cue exists to end — a refused Confirm that plays the ordinary close sound reads as "done". Accepting
## it here would also have let the real bug through that motivated this domain:
## InventoryScreen._on_item_pressed already contained a play_back (the unequip branch) while its refused-equip
## branch was silent, so a play_back-counts rule would have called that function covered.
const DENIAL_CUE: String = "play_denied"

## "<file>::<func>" sites where the OTHER branch is genuinely not a refusal, so no denial belongs there. The
## scanner reads source text and cannot tell an ABORT from a REFUSAL; this is where that judgement is written
## down, in the open, instead of as a silent baseline number.
##
## A function earns a place here only if the non-success branch ALREADY CUES and that cue is correct — never
## because adding the pair is inconvenient. Prefer restructuring first: a cue that can never be refused
## belongs at the function's base indent (an early-return guard, the TermsOfServiceScreen._on_decline shape),
## which needs no exemption at all.
##
##  - options_menu.gd::_input — the live rebind capture. Its two outcomes are "binding written" (commit) and
##    "Esc pressed, capture aborted" (back). The abort refuses nothing: the player asked to stop and the game
##    did. Both branches speak, so the press is never silent — which is all this domain actually cares about.
const EXEMPT_FUNCS: Array[String] = [
	"res://scripts/ui/options_menu.gd::_input",
]


static func run() -> Array:
	var offenders: Array = []
	_scan_dir("res://", offenders)
	var out: Array = []
	for o: Dictionary in offenders:
		out.append({
			"severity": "WARN",
			"source": String(o["source"]),
			"message": "Silent refusal path (line %d, %s in %s): the success cue is branch-gated but the function never calls MenuStyle.play_denied() — the refused press makes no sound. Pair them, or hoist the cue out of the branch if it can never be refused." % [
				int(o["line"]), String(o["cue"]), String(o["func_name"])],
		})
	return out


static func _scan_dir(path: String, out: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := path.path_join(name) if path != "res://" else "res://" + name
		if dir.current_is_dir():
			if not SKIP_DIRS.has(name) and not SKIP_DIR_PATHS.has(full):
				_scan_dir(full, out)
		elif name.ends_with(".gd") and not SKIP_FILES.has(full):
			var text := ScanCache.text_of(full)
			if not text.is_empty():
				out.append_array(scan_gd_text(text, full))
		name = dir.get_next()
	dir.list_dir_end()


## Offending cue sites in one .gd's source. PURE (text in, dicts out) so the GUT guard and this panel can
## never disagree about what counts.
##
## Comments are masked FIRST (ScanDisk.mask_comments, reused not reimplemented) — every cue site in this
## codebase carries a paragraph ABOUT the cue, and those paragraphs name play_commit / play_denied constantly.
## Unmasked, a function whose comment merely mentions the denial would look covered. Masking is
## length-preserving, so indentation is untouched.
##
## Indent is measured in TABS (project convention — CLAUDE.md mandates tabs), counted off the masked line.
static func scan_gd_text(text: String, source: String) -> Array:
	var out: Array = []
	var lines := ScanDisk.mask_comments(text).split("\n")
	var fn := ""            ## current function name ("" = file scope)
	var fn_line := 0
	var base_indent := -1   ## the shallowest STATEMENT indent seen in this function = its unbranched level
	var found: Array = []   ## {line, cue, indent} for success cues in the current function
	var has_denial := false
	for i in lines.size():
		var line: String = lines[i]
		var stripped := line.strip_edges()
		if stripped.is_empty():
			continue
		var indent := _tab_indent(line)
		if stripped.begins_with("func ") or stripped.begins_with("static func "):
			_flush(found, has_denial, base_indent, fn, source, out)
			fn = _func_name(stripped)
			fn_line = i + 1
			base_indent = -1
			found = []
			has_denial = false
			continue
		if fn == "":
			continue
		# The first statement of the body sets the unbranched level. Every later statement can only LOWER it
		# (a `for` body, then a bare line after the loop) — never raise it, or a function that opens with a
		# guard clause would treat its own body as branch-nested.
		base_indent = indent if base_indent < 0 else mini(base_indent, indent)
		if line.contains("MenuStyle." + DENIAL_CUE):
			has_denial = true
			continue
		for cue in SUCCESS_CUES:
			if line.contains("MenuStyle." + cue + "("):
				found.append({"line": i + 1, "cue": cue, "indent": indent, "func_name": fn, "func_line": fn_line})
				break
	_flush(found, has_denial, base_indent, fn, source, out)
	return out


## Emit the current function's offenders: every success cue nested DEEPER than the function's unbranched
## level, when nothing in the function denied. One row per cue site so the panel points at the exact line.
static func _flush(found: Array, has_denial: bool, base_indent: int, fn: String, source: String, out: Array) -> void:
	if has_denial or fn == "" or found.is_empty() or base_indent < 0:
		return
	if EXEMPT_FUNCS.has(source + "::" + fn):
		return
	for f: Dictionary in found:
		if int(f["indent"]) > base_indent:
			out.append({
				"source": source,
				"line": int(f["line"]),
				"func_name": fn,
				"cue": String(f["cue"]),
			})


## Leading TAB count. A space-indented line reads as 0 and therefore as unbranched — deliberately lenient:
## this domain must never fail a file over whitespace style (the tabs rule has its own home in CLAUDE.md).
static func _tab_indent(line: String) -> int:
	var n := 0
	while n < line.length() and line[n] == "\t":
		n += 1
	return n


## "func _on_buy(item: Item) -> void:" -> "_on_buy". Anonymous/garbled lines degrade to "" (skipped).
static func _func_name(stripped: String) -> String:
	var s := stripped.trim_prefix("static ").trim_prefix("func ").strip_edges()
	var paren := s.find("(")
	return s.substr(0, paren).strip_edges() if paren > 0 else ""
