@tool
extends VBoxContainer

## Audit tab (Check group of the CYBER SUNDAY panel). Scan runs Domain A (the open scene -- every node's config
## warnings + typed level checks), Domain B (a res:// file scan -- dead group literals, missing files, dead
## LootTable / out-of-range Dialogue entries, chained to Domain C's wiring passes: dead story flags, dangling quest /
## faction ids), Domain D (the hardcoded player-facing text ratchet), Domain E (menu-sound blindspots), Domain F (the
## content check -- ContentValidator over the shared item scan) and the designer's own rules in res://audit_rules/,
## then lists the findings ERRORS-FIRST in a Tree. Double-click a row to JUMP to it: a scene finding selects + opens
## the node; a quest or conversation file opens in its CYBER SUNDAY editor tab (the Host handoff); any other file
## opens in the Inspector and is revealed in the FileSystem dock.
##
## DOMAINS + the Show filter: every finding carries a `domain` -- "scene", "content", "code" or "custom" (a missing
## key reads as content). The default view, Scene + Content, HIDES the code rows (group-name tidy-ups in scripts,
## PlayerText literals, silent menu cues): they are a programmer's job, and they were most of what made this tab
## look broken to the designer. The filter touches ONLY the Tree -- the findings list, the counts and the Fix plan
## stay unfiltered, so Fix (N) and its preview still cover everything and the summary says how many rows are hidden.
##
## Reads vs writes: Scan and Auto are read-only. Fix is the ONE writer: it previews the file list, confirms, backs
## every file up to a .bak beside it (fix_ops.gd), rewrites, scans again and reports the changed file names.
##
## Layout contract (shared with every tab in the panel): the button bar and ONE two-line status Label sit above the
## findings Tree; the Tree keeps a small height floor and scrolls its rows itself (the Palette tab's list idiom, so no
## ScrollContainer is wrapped around a control that already scrolls), which keeps the tab's minimum height small. That
## matters because a TabContainer's minimum is the CURRENT tab's minimum, and the editor's bottom splitter keeps the
## height it grew to -- one tall tab stretches the shared panel for everyone.
##
## Off-tree (GUT and the headless probe construct this bare): _init never touches EditorInterface or the tree --
## every editor call lives in a button / timer / dialog handler, which only ever fires inside the editor.

const ScanScene := preload("res://addons/cybersunday_tools/panel_audit/scan_scene.gd")
const ScanDisk := preload("res://addons/cybersunday_tools/panel_audit/scan_disk.gd")
const ScanText := preload("res://addons/cybersunday_tools/panel_audit/scan_text.gd")
const ScanMenuSound := preload("res://addons/cybersunday_tools/panel_audit/scan_menu_sound.gd")
const ScanContent := preload("res://addons/cybersunday_tools/panel_audit/scan_content.gd")
const FixOps := preload("res://addons/cybersunday_tools/panel_audit/fix_ops.gd")
const CustomRules := preload("res://addons/cybersunday_tools/panel_audit/custom_rules.gd")
## One-read-per-file window shared by the text-reading domain scanners (see scan_cache.gd).
const ScanCache := preload("res://addons/cybersunday_tools/panel_audit/scan_cache.gd")
## The ONLY way this tab reaches the CYBER SUNDAY panel (the double-click handoff to Quest Edit / Dialogue Edit).
## Off-tree the lookup returns null and open_in_editor() answers false, so the handoff degrades to the Inspector.
const Host := preload("res://addons/cybersunday_tools/core/host.gd")
## Fills the Show dropdown with the width guards every picker in the panel shares (fit_to_longest_item off, clip_text).
const PickerRows := preload("res://addons/cybersunday_tools/core/picker_rows.gd")

const COLOR_ERROR := Color(1.0, 0.42, 0.42)
const COLOR_WARN := Color(1.0, 0.82, 0.3)
## Status Label font override for a refusal / a partly-failed Fix; removed on the next ordinary write.
const PROBLEM_COLOR := Color(1.0, 0.42, 0.42)

## Coalesce a burst of editor signals (saves, reimports) into ONE rescan.
const DEBOUNCE_SEC := 0.75
## How often to poll the edited-scene root (no Control-level scene_changed signal exists).
const SCENE_POLL_SEC := 0.5
## Tree floor: small enough that the tab never forces the shared bottom panel taller than a short display.
const TREE_MIN_HEIGHT := 90
## The Show dropdown's width floor -- wide enough for its longest label, since clip_text drops text from the minimum.
const SHOW_MIN_WIDTH := 200.0

## Show-filter values (the OptionButton rows' metadata). Scene + Content is the designer's default view.
const SHOW_SCENE_CONTENT := "scene_content"
const SHOW_ALL := "all"
const SHOW_CODE := "code"
const SHOW_ROWS := [
	{"label": "Show: Scene + Content", "value": SHOW_SCENE_CONTENT},
	{"label": "Show: Everything", "value": SHOW_ALL},
	{"label": "Show: Code Only", "value": SHOW_CODE},
]
## The domain a finding WITHOUT a `domain` key belongs to (a custom rule written before the key existed, a hand-built
## finding in a test) -- content, so nothing a designer authored can be hidden by accident.
const DOMAIN_DEFAULT := "content"
const DOMAIN_CODE := "code"

## Status + tooltip copy. Verdict tokens (ERROR / WARN) live on the Tree rows only.
const MSG_IDLE := "Press Scan to check the open scene and every content file."
const MSG_SCANNING := "Scanning..."
const MSG_AUTO_SCANNING := "Auto: re-scanning after save..."
const MSG_NO_SCENE_PREFIX := "No scene open -- scene checks skipped. "
const MSG_CLEAN := "No problems found."
const TIP_SCAN := "Scan the open scene and every content file. Read-only."
const TIP_AUTO := "Scan again on its own after every save or scene change (it waits about a second for the burst to settle). Read-only."
const TIP_SHOW := "Which rows the list shows -- Code Only is the programmer's list (group names in scripts, text and sound checks). Fix covers every row whichever view is on."
const TIP_FIX_EMPTY := "No auto-fixable findings in the last scan."
const TIP_FIX := "Apply the mechanical fixes tagged [fixable] (group-name tidy-ups in scripts, loot count clamps). Shows the file list first."
## The refusal the status row shows if Fix is somehow pressed with an empty plan (the button is disabled then, so this
## is the fallback). Refusal grammar: "Couldn't <verb> <thing>: <plain reason>."
const MSG_FIX_NONE := "Couldn't fix anything: the last scan found nothing that can be corrected automatically."

var _tree: Tree = null
## The ONE status row: what the tab is doing, did, or refused. Two lines max; its tooltip mirrors the full text.
var _status: Label = null
var _scan_btn: Button = null
var _show: OptionButton = null
var _auto: CheckButton = null
## "Fix (N)" button — enabled only when the last scan produced auto-fixable findings (FixOps.build_plan non-empty).
var _fix_btn: Button = null
## Preview/confirm dialog for the batch fix (destructive: writes files) — built lazily on first use.
var _fix_dialog: ConfirmationDialog = null
## Scrollable RESULT dialog for the fix outcome (the Changed / Skipped file list) — built lazily on first use. The
## two-line status names the changed files but cannot hold their folders or every skip reason without overflowing
## the short bottom panel, so the detail goes here (a free-floating window that can scroll), satisfying the QA
## write-contract "report which files changed".
var _result_dialog: AcceptDialog = null
var _result_label: RichTextLabel = null
## The most recent scan's UNFILTERED findings + the deduped fix plan derived from them (so Fix uses exactly what was
## found, whatever the Show filter lists).
var _last_findings: Array = []
var _last_plan: Array = []
## Whether the last scan ran with no scene open (the summary says so on every re-render, filter changes included).
var _last_no_scene := false
## True between the "Scanning..." write and the render, so an Auto debounce can't stack a second walk on the first.
var _scanning := false
## One-shot debounce: restarted on every auto-trigger so a burst collapses into a single fire.
var _debounce: Timer = null
## Repeating poll that detects the edited scene root changing (a proxy for scene_changed).
var _scene_poll: Timer = null
var _last_root: Node = null


func _init() -> void:
	name = "Audit"
	add_theme_constant_override("separation", 4)

	var bar := HBoxContainer.new()
	_scan_btn = Button.new()
	_scan_btn.text = "Scan"
	_scan_btn.tooltip_text = TIP_SCAN
	_scan_btn.pressed.connect(_on_scan_pressed)
	bar.add_child(_scan_btn)
	# Batch auto-fix: disabled until a scan finds something fixable; previews + confirms before writing anything.
	# The tooltip is the disabled-state explanation until a plan exists, then the pre-click description of the write.
	_fix_btn = Button.new()
	_fix_btn.text = "Fix"
	_fix_btn.disabled = true
	_fix_btn.tooltip_text = TIP_FIX_EMPTY
	_fix_btn.pressed.connect(_on_fix_pressed)
	bar.add_child(_fix_btn)
	# The Show filter: Tree rows only (see the header). PickerRows.apply sets the shared width guards.
	_show = OptionButton.new()
	PickerRows.apply(_show, SHOW_ROWS, SHOW_SCENE_CONTENT)
	_show.custom_minimum_size = Vector2(SHOW_MIN_WIDTH, 0)
	_show.tooltip_text = TIP_SHOW
	_show.item_selected.connect(_on_show_selected)
	bar.add_child(_show)
	_auto = CheckButton.new()
	_auto.text = "Auto"
	_auto.button_pressed = false  # OFF by default -- nothing runs unless the designer opts in.
	_auto.tooltip_text = TIP_AUTO
	_auto.toggled.connect(_on_auto_toggled)
	bar.add_child(_auto)
	add_child(bar)

	# The status is its OWN full-width row (not wedged into the button bar), clamped to two lines with the full text
	# in its tooltip, so a long summary can never push the Tree off a short bottom panel. The multi-file fix report
	# is NOT put here — it goes to the scrollable result dialog (see _apply_fixes); this row stays a short count.
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 2
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.modulate = Color(1, 1, 1, 0.75)
	add_child(_status)
	_set_status(MSG_IDLE)

	_tree = Tree.new()
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.custom_minimum_size = Vector2(0, TREE_MIN_HEIGHT)  # the Tree scrolls its own rows past this floor
	_tree.item_activated.connect(_on_item_activated)  # double-click / Enter
	add_child(_tree)

	# Debounce timer: one-shot; each auto-trigger restarts it, so only the LAST event in a burst fires a scan.
	_debounce = Timer.new()
	_debounce.one_shot = true
	_debounce.wait_time = DEBOUNCE_SEC
	_debounce.timeout.connect(_on_debounce_timeout)
	add_child(_debounce)

	# Scene poll: a Control has no scene_changed signal, so detect the edited root changing ourselves.
	_scene_poll = Timer.new()
	_scene_poll.one_shot = false
	_scene_poll.wait_time = SCENE_POLL_SEC
	_scene_poll.timeout.connect(_on_scene_poll)
	add_child(_scene_poll)


## Every status write goes through here: the tooltip mirrors the full text (the row is clamped to two lines), and a
## refusal / partly-failed fix paints the row in PROBLEM_COLOR until the next ordinary write.
func _set_status(text: String, problem: bool = false) -> void:
	_status.text = text
	_status.tooltip_text = text
	if problem:
		_status.add_theme_color_override("font_color", PROBLEM_COLOR)
	else:
		_status.remove_theme_color_override("font_color")


## Wire/unwire editor signals when Auto flips. Defer connecting to filesystem_changed until ON so an
## idle panel costs nothing; the scene poll only ticks while ON.
func _on_auto_toggled(on: bool) -> void:
	var fs := EditorInterface.get_resource_filesystem()
	if on:
		if fs != null and not fs.filesystem_changed.is_connected(_request_auto_rescan):
			fs.filesystem_changed.connect(_request_auto_rescan)
		_last_root = EditorInterface.get_edited_scene_root()
		_scene_poll.start()
		_request_auto_rescan()  # kick one scan so turning Auto on reflects the current state
	else:
		if fs != null and fs.filesystem_changed.is_connected(_request_auto_rescan):
			fs.filesystem_changed.disconnect(_request_auto_rescan)
		_scene_poll.stop()
		_debounce.stop()


## Poll for the edited scene root changing (open/switch/close a scene) -- a proxy for a scene_changed signal.
func _on_scene_poll() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root != _last_root:
		_last_root = root
		_request_auto_rescan()


## Auto-trigger entry point: every editor event routes here and (re)starts the debounce timer, so a burst
## of saves/reimports coalesces into a SINGLE rescan when the timer finally fires. Restart logic is split
## into debounce_restart() so it can be unit-tested with an injected Timer (no EditorInterface).
func _request_auto_rescan() -> void:
	debounce_restart(_debounce)


## Pure, testable debounce step: (re)start the one-shot timer from scratch. Calling it N times in a burst
## leaves exactly ONE pending fire. Kept free of EditorInterface so a headless GUT test can drive it.
static func debounce_restart(timer: Timer) -> void:
	if timer == null:
		return
	timer.stop()
	timer.start()


## Debounce fired: the burst has settled, so run the FULL audit -- but only while Auto is on (a stray timeout after
## toggling off is a no-op). The Auto path announces itself so the designer knows nobody pressed anything.
func _on_debounce_timeout() -> void:
	if _auto != null and _auto.button_pressed:
		await _scan(MSG_AUTO_SCANNING)


func _on_scan_pressed() -> void:
	await _scan(MSG_SCANNING)


## The one scan path (Scan button, Auto, the post-Fix rescan): announce, grey the buttons, give the editor one frame
## to paint the status (the walk blocks the main thread for a moment on a big project), walk, render, release. A scan
## already in flight refuses a second one -- the Auto debounce fires again on the next change anyway.
func _scan(progress_text: String) -> void:
	if _scanning:
		return
	_scanning = true
	_scan_btn.disabled = true
	_scan_btn.tooltip_text = MSG_SCANNING
	_fix_btn.disabled = true
	_set_status(progress_text)
	if is_inside_tree():
		await get_tree().process_frame
	var root := EditorInterface.get_edited_scene_root()
	var findings := _collect(root)
	_render(findings, root == null)
	_scan_btn.disabled = false
	_scan_btn.tooltip_text = TIP_SCAN
	_scanning = false


## Every domain, in order, over the given scene root (null = no scene open: the scene domain is skipped).
func _collect(root: Node) -> Array:
	var findings: Array = []
	if root != null:
		findings.append_array(ScanScene.run(root))
	# The text-reading domains below each walk res:// with their own SKIP policy but re-read the SAME .gd files.
	# One caching window makes each file's bytes leave the disk ONCE per Scan instead of three or four times —
	# which matters most with Auto on, where every editor save replays this whole block. Closed in ALL paths.
	ScanCache.begin()
	findings.append_array(ScanDisk.run())  # Domain B + the chained Domain C wiring passes
	findings.append_array(ScanText.run())  # Domain D: hardcoded player-facing text (the PlayerText ratchet)
	findings.append_array(ScanMenuSound.run())  # Domain E: menu-sound blindspots (silent refusal paths)
	ScanCache.end()  # before the content check + custom rules: they LOAD resources / may read files this scan edited
	findings.append_array(ScanContent.run())  # Domain F: the content check over the shared item scan
	findings.append_array(CustomRules.run(root))  # designer-authored rules in res://audit_rules/ (no-op if absent)
	return findings


## Take a fresh scan's findings: keep them UNFILTERED for Fix, rebuild the plan, then draw the Tree + summary.
func _render(findings: Array, no_scene: bool = false) -> void:
	_last_findings = findings
	_last_plan = FixOps.build_plan(findings)
	_last_no_scene = no_scene
	# Enable Fix only when the scan produced a non-empty plan; label it with the count of files it would touch and
	# swap the tooltip between the disabled-state explanation and the pre-click description of the write.
	if _fix_btn != null:
		_fix_btn.disabled = _last_plan.is_empty()
		_fix_btn.text = "Fix" if _last_plan.is_empty() else "Fix (%d)" % _last_plan.size()
		_fix_btn.tooltip_text = TIP_FIX_EMPTY if _last_plan.is_empty() else TIP_FIX
	_refresh_view()


## The Show filter changed: redraw from the findings already in hand -- never a rescan.
func _on_show_selected(_idx: int) -> void:
	_refresh_view()


## Draw the Tree from _last_findings through the Show filter, then the summary (unfiltered counts + hidden count).
##
## Row order is errors, then warnings, then ANY OTHER severity a custom rule invented (a rule that answers "warn"
## instead of "WARN" is still listed, at the bottom, painted as a warning). Nothing is silently dropped: the summary
## counts every finding, so a row that is counted but never drawn reads as a phantom problem the designer can't find.
## `hidden` is counted from the FILTER's own decision for the same reason -- "N code rows hidden" must mean exactly
## the rows the Show view chose not to list, never "everything the draw loop happened not to reach".
func _refresh_view() -> void:
	var mode := _show_mode()
	_tree.clear()
	var root_item := _tree.create_item()
	var hidden := 0
	for pass_sev in ["ERROR", "WARN", ""]:  # "" = the catch-all pass for anything that is neither
		for f in _last_findings:
			if not (f is Dictionary):
				continue
			var sev := String(f.get("severity", ""))
			if pass_sev == "":
				if sev == "ERROR" or sev == "WARN":
					continue  # already drawn by its own pass
			elif sev != pass_sev:
				continue
			if not row_visible(domain_of(f), mode):
				hidden += 1
				continue
			var it := _tree.create_item(root_item)
			it.set_text(0, row_text(f))
			it.set_custom_color(0, COLOR_ERROR if sev == "ERROR" else COLOR_WARN)
			# The full source path lives in the tooltip (the row shows the file name), with the message under it so
			# a clipped row still reads whole on hover.
			it.set_tooltip_text(0, "%s\n%s" % [str(f.get("source", "")), str(f.get("message", ""))])
			it.set_metadata(0, f)
	_set_status(summary_text(_last_findings, _last_plan.size(), hidden, mode, _last_no_scene))


## The Show dropdown's current value; the default view when nothing is selected (never happens after apply, but a
## Variant read stays guarded).
func _show_mode() -> String:
	var m: Variant = _show.get_selected_metadata() if _show != null else null
	return String(m) if m is String else SHOW_SCENE_CONTENT


# --- pure row / summary helpers (unit-tested) ---------------------------------------------------------------------

## Which domain a finding belongs to; a missing key reads as content (see DOMAIN_DEFAULT).
static func domain_of(f: Dictionary) -> String:
	return String(f.get("domain", DOMAIN_DEFAULT))


## Whether a row of `domain` is listed under Show mode `mode`: Everything lists all, Code Only lists the code rows,
## Scene + Content (the default) lists every row that is NOT code -- so scene, content and custom-rule rows.
static func row_visible(domain: String, mode: String) -> bool:
	if mode == SHOW_ALL:
		return true
	if mode == SHOW_CODE:
		return domain == DOMAIN_CODE
	return domain != DOMAIN_CODE


## The Tree row: '<SEV>   <message> -- <file name><tag>'. The message leads because it is what the designer acts on;
## the file name closes the row and the full path waits in the tooltip. A code row is prefixed "[code]" so it reads
## as the programmer's even under Show: Everything.
static func row_text(f: Dictionary) -> String:
	var sev := String(f.get("severity", ""))
	var msg := String(f.get("message", ""))
	if domain_of(f) == DOMAIN_CODE:
		msg = "[code] " + msg
	var tag := "  [fixable]" if (f.get("fix") is Dictionary) else ""
	return "%s   %s -- %s%s" % [sev, msg, source_label(String(f.get("source", ""))), tag]


## How a row names its source: a file by its file name (a folder by its folder name), the wiring scan's project-wide
## marker by a plain word, a scene node by its path in the scene (already designer-readable), anything else as-is.
static func source_label(src: String) -> String:
	if src.is_empty():
		return "project"
	if src.begins_with("res:// "):
		return "project-wide"  # scan_wiring's "res:// (project-wide)" marker for a flag it found nowhere in particular
	if src.begins_with("res://"):
		var f := src.trim_suffix("/").get_file()
		return f if not f.is_empty() else "project"
	return src


## The status summary: the unfiltered counts (errors + warnings + auto-fixable), the jump hint, and how many rows the
## current Show view hides. A scan with no scene open says so first, so a clean-looking list is never mistaken for a
## checked scene.
static func summary_text(findings: Array, fixable: int, hidden: int, mode: String, no_scene: bool) -> String:
	var s := MSG_NO_SCENE_PREFIX if no_scene else ""
	if findings.is_empty():
		return s + MSG_CLEAN
	var errs := 0
	var warns := 0
	for f in findings:
		if f is Dictionary and String(f.get("severity", "")) == "ERROR":
			errs += 1
		else:
			warns += 1
	s += "Found %s: %s, %s" % [_n(findings.size(), "problem", "problems"), _n(errs, "error", "errors"), _n(warns, "warning", "warnings")]
	if fixable > 0:
		s += " -- %d auto-fixable" % fixable
	s += ". Double-click a row to jump to it."
	if hidden > 0:
		if mode == SHOW_CODE:
			s += " -- %s hidden" % _n(hidden, "scene + content row", "scene + content rows")
		else:
			s += " -- %s hidden" % _n(hidden, "code row", "code rows")
	return s


## "1 file" / "3 files" -- editor copy, never player text (so no TextFormat / PlayerText here).
static func _n(count: int, one: String, many: String) -> String:
	return "%d %s" % [count, one if count == 1 else many]


## "player.gd  (scripts/player)" -- the result dialog's file line: the name first, the folder in parentheses.
static func _file_label(path: String) -> String:
	var folder := path.get_base_dir().trim_prefix("res://")
	return path.get_file() if folder.is_empty() else "%s  (%s)" % [path.get_file(), folder]


# --- Fix -------------------------------------------------------------------------------------------------------

## Fix pressed: build the confirm dialog body from the (already-computed, UNFILTERED) plan and pop it up. The apply is
## gated behind the designer confirming — nothing is written on the click itself.
func _on_fix_pressed() -> void:
	if _last_plan.is_empty():
		_set_status(MSG_FIX_NONE, true)  # the button is disabled in this state; this is the fallback if it isn't
		return
	if _fix_dialog == null:
		_fix_dialog = ConfirmationDialog.new()
		_fix_dialog.title = "Apply automatic fixes"
		_fix_dialog.ok_button_text = "Apply"
		_fix_dialog.confirmed.connect(_apply_fixes)
		add_child(_fix_dialog)
	var lines := PackedStringArray()
	for row in _last_plan:
		lines.append("• " + str(row.get("label", "")))
	_fix_dialog.dialog_text = "Apply %s?\n\n%s\n\nThese files are rewritten on disk. Each one is copied to a \".bak\" file beside it first, so a fix can be put back." % [
		_n(_last_plan.size(), "fix", "fixes"), "\n".join(lines)]
	_fix_dialog.popup_centered(Vector2i(640, 0))


## Confirmed: run the plan, reimport, scan again so the panel reflects the new state, then report the outcome -- the
## changed FILE NAMES on the status row (the write contract), the full list + every skip reason in the result dialog.
func _apply_fixes() -> void:
	var result := FixOps.apply_plan(_last_plan)
	var fs := EditorInterface.get_resource_filesystem()
	if fs != null:
		fs.scan()  # pick up the rewritten scripts / re-saved loot tables
	await _scan(MSG_SCANNING)
	var written: Array = result.get("written", [])
	var errs: Array = result.get("errors", [])
	if written.is_empty() and errs.is_empty():
		_set_status("Nothing needed fixing -- the files already matched.")
		return
	var msg := "Fixed %s in %s." % [_n(int(result.get("fixed", 0)), "problem", "problems"), _n(int(result.get("files", 0)), "file", "files")]
	var names := PackedStringArray()
	for p in written:
		names.append(str(p).get_file())
	# Nothing written + something skipped is a REFUSAL, not a result: leading with "Fixed 0 problems in 0 files"
	# would report work that never happened. Refusal grammar first, the count only when a file really changed.
	var line := ""
	if names.is_empty():
		line = "Couldn't fix %s: see the report for what stopped each one." % _n(errs.size(), "file", "files")
	else:
		line = "%s Changed: %s." % [msg, ", ".join(names)]
		if not errs.is_empty():
			line += " Couldn't fix %s -- see the report." % _n(errs.size(), "file", "files")
	_set_status(line, not errs.is_empty())
	# Write contract (CYBER_SUNDAY_PLUGIN_QA): a write must REPORT which files changed — every rewritten file with
	# its folder, and ALL skip reasons (not just the first). That list would overflow the two-line status, so it goes
	# to the scrollable result dialog.
	var report := PackedStringArray([msg if not names.is_empty() else "No file was changed."])
	if not written.is_empty():
		report.append("")
		report.append("Changed (each has a .bak copy beside it):")
		for p in written:
			report.append("  • " + _file_label(str(p)))
	if not errs.is_empty():
		report.append("")
		report.append("Couldn't fix %s:" % _n(errs.size(), "file", "files"))
		for e in errs:
			# Skip rows are {source, error} -- named the same way as the Changed list (file name + folder), never a
			# raw path, since this dialog body is designer copy with no tooltip to hide one in.
			var row: Dictionary = e if e is Dictionary else {}
			report.append("  • %s -- %s" % [_file_label(str(row.get("source", ""))), str(row.get("error", ""))])
	_ensure_result_dialog()
	_result_label.text = "\n".join(report)
	_result_dialog.popup_centered(Vector2i(640, 420))


## Lazily build the scrollable fix-result dialog: an AcceptDialog whose body is a ScrollContainer over a
## RichTextLabel, so a long Changed / Couldn't-fix list scrolls inside a window instead of clipping in the panel.
## bbcode stays off so file names render literally (no accidental tag interpretation).
func _ensure_result_dialog() -> void:
	if _result_dialog != null:
		return
	_result_dialog = AcceptDialog.new()
	_result_dialog.title = "Fix results"
	_result_dialog.min_size = Vector2i(520, 300)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(500, 260)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_result_label = RichTextLabel.new()
	_result_label.fit_content = true
	_result_label.selection_enabled = true
	_result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_result_label)
	_result_dialog.add_child(scroll)
	add_child(_result_dialog)


# --- jump ------------------------------------------------------------------------------------------------------

## Double-click a finding: jump to the offending node (select + open it); hand a content file to the CYBER SUNDAY tab
## that edits it (Host.open_in_editor -> cyber_panel: a quest -> Quest Edit, a conversation -> Dialogue Edit, a loot
## table -> Loot Edit -- which matters most for the loot rows, since that tab is where the designer fixes them);
## otherwise open the file in the Inspector and reveal it in the FileSystem dock. The host decides which types it can
## route, so there is no type list to keep in sync here -- it answers false for anything it doesn't own. A folder
## source (the skipped-items row) or a file that no longer loads is still revealed, never opened.
func _on_item_activated() -> void:
	var it := _tree.get_selected()
	if it == null:
		return
	var f: Variant = it.get_metadata(0)
	if not (f is Dictionary):
		return
	var node: Variant = f.get("node")
	if is_instance_valid(node) and node is Node:  # validity FIRST: `is` on a freed instance crashes the editor
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(node)
		EditorInterface.edit_node(node)
		return
	var src := str(f.get("source", ""))
	if not src.begins_with("res://"):
		return
	if not ResourceLoader.exists(src):
		EditorInterface.select_file(src)
		return
	var res: Variant = load(src)
	if res != null and Host.open_in_editor(self, src):
		return  # the panel switched to that editor tab and it loaded the file
	if res != null:
		EditorInterface.edit_resource(res)
	EditorInterface.select_file(src)
