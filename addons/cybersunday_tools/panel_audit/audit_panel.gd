@tool
extends VBoxContainer

## Project audit bottom panel: Re-scan runs Domain A (the edited scene tree -- every node's config warnings + typed
## level checks), Domain B (a res:// file scan -- dead group literals, broken ext_resource refs, dead LootTable /
## out-of-range Dialogue entries), Domain D (the hardcoded player-facing text ratchet -- raw literals at paint
## sites that belong in PlayerText) and Domain E (menu-sound blindspots -- a branch-gated success cue whose
## refusal path is silent) and lists the findings ERRORS-FIRST in a Tree. Double-click a row to JUMP to it:
## a scene-node finding selects + opens the node; a file finding opens the resource + reveals it in FileSystem.

const ScanScene := preload("res://addons/cybersunday_tools/panel_audit/scan_scene.gd")
const ScanDisk := preload("res://addons/cybersunday_tools/panel_audit/scan_disk.gd")
const ScanText := preload("res://addons/cybersunday_tools/panel_audit/scan_text.gd")
const ScanMenuSound := preload("res://addons/cybersunday_tools/panel_audit/scan_menu_sound.gd")
const FixOps := preload("res://addons/cybersunday_tools/panel_audit/fix_ops.gd")
const CustomRules := preload("res://addons/cybersunday_tools/panel_audit/custom_rules.gd")
## One-read-per-file window shared by the four domain scanners below (see scan_cache.gd).
const ScanCache := preload("res://addons/cybersunday_tools/panel_audit/scan_cache.gd")

const COLOR_ERROR := Color(1.0, 0.42, 0.42)
const COLOR_WARN := Color(1.0, 0.82, 0.3)

## Coalesce a burst of editor signals (saves, reimports) into ONE rescan.
const DEBOUNCE_SEC := 0.75
## How often to poll the edited-scene root (no Control-level scene_changed signal exists).
const SCENE_POLL_SEC := 0.5

var _tree: Tree = null
var _summary: Label = null
var _auto: CheckButton = null
## "Fix N" button — enabled only when the last scan produced auto-fixable findings (FixOps.build_plan non-empty).
var _fix_btn: Button = null
## Preview/confirm dialog for the batch fix (destructive: writes files) — built lazily on first use.
var _fix_dialog: ConfirmationDialog = null
## Scrollable RESULT dialog for the fix outcome (the Changed / Skipped path list) — built lazily on first use. The
## one-line panel _summary can't hold a multi-file report without overflowing the short bottom panel, so the detail
## goes here (a free-floating window that can scroll), satisfying the QA write-contract "report which files changed".
var _result_dialog: AcceptDialog = null
var _result_label: RichTextLabel = null
## The most recent scan's findings + the deduped fix plan derived from them (so Fix uses exactly what's shown).
var _last_findings: Array = []
var _last_plan: Array = []
## One-shot debounce: restarted on every auto-trigger so a burst collapses into a single fire.
var _debounce: Timer = null
## Repeating poll that detects the edited scene root changing (a proxy for scene_changed).
var _scene_poll: Timer = null
var _last_root: Node = null


func _init() -> void:
	name = "Audit"
	add_theme_constant_override("separation", 4)

	var bar := HBoxContainer.new()
	var rescan := Button.new()
	rescan.text = "Re-scan"
	rescan.pressed.connect(_rescan)
	bar.add_child(rescan)
	# Batch auto-fix: disabled until a scan finds something fixable; previews + confirms before writing anything.
	_fix_btn = Button.new()
	_fix_btn.text = "Fix"
	_fix_btn.disabled = true
	# Name ALL of FixOps.KNOWN_KINDS: this tooltip is the pre-click description of a batch write that rewrites SOURCE
	# files, and group_literal is by far the highest-volume one. Keep it in sync when a fix kind is added.
	_fix_btn.tooltip_text = "Apply the safe, mechanical fixes among the findings: dead \"player\" group -> Groups.PLAYER; every raw registered group literal -> its Groups.<CONST> (rewrites .gd source project-wide); LootTable max<min clamp. Previews the exact file list first."
	_fix_btn.pressed.connect(_on_fix_pressed)
	bar.add_child(_fix_btn)
	_auto = CheckButton.new()
	_auto.text = "Auto"
	_auto.button_pressed = false  # OFF by default -- nothing changes unless the user opts in.
	_auto.tooltip_text = "Re-run the full audit (scene + disk) automatically, debounced ~%.2fs, on editor file/scene changes." % DEBOUNCE_SEC
	_auto.toggled.connect(_on_auto_toggled)
	bar.add_child(_auto)
	add_child(bar)

	# The summary is its OWN full-width row (not wedged into the button bar) and autowraps, so a long status line
	# wraps across the panel instead of pushing the buttons off the right edge. The multi-file fix report is NOT put
	# here — it goes to the scrollable result dialog (see _apply_fixes); this line stays a short count.
	_summary = Label.new()
	_summary.modulate = Color(1, 1, 1, 0.7)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_summary)

	_tree = Tree.new()
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.custom_minimum_size = Vector2(0, 90)  # small floor so the bottom panel stays compact
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

	_summary.text = "Click Re-scan to audit the open scene + the project."


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


## Debounce fired: the burst has settled, so run the FULL audit (scene + disk) -- but only while Auto is on
## (a stray timeout after toggling off is a no-op).
func _on_debounce_timeout() -> void:
	if _auto != null and _auto.button_pressed:
		_rescan()


func _rescan() -> void:
	var findings: Array = []
	var root := EditorInterface.get_edited_scene_root()
	if root != null:
		findings.append_array(ScanScene.run(root))
	# The disk-reading domains below each walk res:// with their own SKIP policy but re-read the SAME .gd files.
	# One caching window makes each file's bytes leave the disk ONCE per Re-scan instead of three or four times —
	# which matters most with Auto on, where every editor save replays this whole block. Closed in ALL paths.
	ScanCache.begin()
	findings.append_array(ScanDisk.run())
	findings.append_array(ScanText.run())  # Domain D: hardcoded player-facing text (the PlayerText ratchet)
	findings.append_array(ScanMenuSound.run())  # Domain E: menu-sound blindspots (silent refusal paths)
	ScanCache.end()  # before the custom rules: a designer rule may read files this scan just wrote/edited
	findings.append_array(CustomRules.run(root))  # designer-authored rules in res://audit_rules/ (no-op if absent)
	_render(findings)


func _render(findings: Array) -> void:
	_last_findings = findings
	_last_plan = FixOps.build_plan(findings)
	_tree.clear()
	var root_item := _tree.create_item()
	var errs := 0
	var warns := 0
	# Errors first, then warnings.
	for sev in ["ERROR", "WARN"]:
		for f in findings:
			if String(f.get("severity", "")) != sev:
				continue
			if sev == "ERROR":
				errs += 1
			else:
				warns += 1
			var it := _tree.create_item(root_item)
			var tag := "  [fixable]" if (f.get("fix") is Dictionary) else ""
			it.set_text(0, "%s   %s — %s%s" % [sev, str(f.get("source", "")), str(f.get("message", "")), tag])
			it.set_custom_color(0, COLOR_ERROR if sev == "ERROR" else COLOR_WARN)
			it.set_tooltip_text(0, str(f.get("message", "")))
			it.set_metadata(0, f)
	# Enable Fix only when the scan produced a non-empty plan; label it with the count of files it would touch.
	if _fix_btn != null:
		_fix_btn.disabled = _last_plan.is_empty()
		_fix_btn.text = "Fix" if _last_plan.is_empty() else "Fix (%d)" % _last_plan.size()
	if findings.is_empty():
		_summary.text = "No issues found."
	else:
		var fixable := "" if _last_plan.is_empty() else " — %d auto-fixable" % _last_plan.size()
		_summary.text = "%d issue(s): %d error / %d warn%s — double-click a row to jump." % [findings.size(), errs, warns, fixable]


## Fix pressed: build the confirm dialog body from the (already-computed) plan and pop it up. The apply is gated
## behind the user confirming — nothing is written on the click itself.
func _on_fix_pressed() -> void:
	if _last_plan.is_empty():
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
	_fix_dialog.dialog_text = "Apply %d fix(es)?\n\n%s\n\nChanges are written to disk. Save any open scripts first; use version control to revert." % [_last_plan.size(), "\n".join(lines)]
	_fix_dialog.popup_centered(Vector2i(640, 0))


## Confirmed: run the plan, reimport, re-scan so the panel reflects the new state, and report the outcome.
func _apply_fixes() -> void:
	var result := FixOps.apply_plan(_last_plan)
	var fs := EditorInterface.get_resource_filesystem()
	if fs != null:
		fs.scan()  # pick up the rewritten .gd / re-saved .tres
	_rescan()
	# The panel summary stays a SHORT one-line count — it shares the short bottom panel with the findings Tree.
	var msg := "Fixed %d issue(s) across %d file(s)." % [int(result.get("fixed", 0)), int(result.get("files", 0))]
	# Write contract (CYBER_SUNDAY_PLUGIN_QA): a write must REPORT which files changed — list every rewritten path,
	# and surface ALL skip reasons (not just the first). That multi-line path list would overflow the one-line summary
	# unreadably (long res:// paths + a growing list, no scroll), so it goes to a scrollable result dialog instead.
	var written: Array = result.get("written", [])
	var errs: Array = result.get("errors", [])
	if written.is_empty() and errs.is_empty():
		_summary.text = msg
		return
	_summary.text = "%s See the dialog for changed / skipped files." % msg
	var report := PackedStringArray([msg])
	if not written.is_empty():
		report.append("")
		report.append("Changed:")
		for p in written:
			report.append("  • " + str(p))
	if not errs.is_empty():
		report.append("")
		report.append("Skipped %d:" % errs.size())
		for e in errs:
			report.append("  • " + str(e))
	_ensure_result_dialog()
	_result_label.text = "\n".join(report)
	_result_dialog.popup_centered(Vector2i(640, 420))


## Lazily build the scrollable fix-result dialog: an AcceptDialog whose body is a ScrollContainer over a
## RichTextLabel, so a long Changed / Skipped path list scrolls inside a window instead of clipping in the panel.
## bbcode stays off so res:// paths render literally (no accidental tag interpretation).
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


## Double-click a finding: jump to the offending node (select + open it) or, for a file finding, open the resource
## and reveal it in the FileSystem dock.
func _on_item_activated() -> void:
	var it := _tree.get_selected()
	if it == null:
		return
	var f: Variant = it.get_metadata(0)
	if not (f is Dictionary):
		return
	var node: Variant = f.get("node")
	if node is Node and is_instance_valid(node):
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(node)
		EditorInterface.edit_node(node)
		return
	var src := str(f.get("source", ""))
	if src.begins_with("res://"):
		if ResourceLoader.exists(src):
			EditorInterface.edit_resource(load(src))
		EditorInterface.select_file(src)
