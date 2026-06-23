@tool
extends VBoxContainer

## Project audit bottom panel: Re-scan runs Domain A (the edited scene tree -- every node's config warnings + typed
## level checks) and Domain B (a res:// file scan -- dead group literals, broken ext_resource refs, dead LootTable /
## out-of-range Dialogue entries) and lists the findings ERRORS-FIRST in a Tree. Double-click a row to JUMP to it:
## a scene-node finding selects + opens the node; a file finding opens the resource + reveals it in FileSystem.

const ScanScene := preload("res://addons/cybersunday_tools/panel_audit/scan_scene.gd")
const ScanDisk := preload("res://addons/cybersunday_tools/panel_audit/scan_disk.gd")

const COLOR_ERROR := Color(1.0, 0.42, 0.42)
const COLOR_WARN := Color(1.0, 0.82, 0.3)

## Coalesce a burst of editor signals (saves, reimports) into ONE rescan.
const DEBOUNCE_SEC := 0.75
## How often to poll the edited-scene root (no Control-level scene_changed signal exists).
const SCENE_POLL_SEC := 0.5

var _tree: Tree = null
var _summary: Label = null
var _auto: CheckButton = null
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
	_auto = CheckButton.new()
	_auto.text = "Auto"
	_auto.button_pressed = false  # OFF by default -- nothing changes unless the user opts in.
	_auto.tooltip_text = "Re-run the full audit (scene + disk) automatically, debounced ~%.2fs, on editor file/scene changes." % DEBOUNCE_SEC
	_auto.toggled.connect(_on_auto_toggled)
	bar.add_child(_auto)
	_summary = Label.new()
	_summary.modulate = Color(1, 1, 1, 0.7)
	bar.add_child(_summary)
	add_child(bar)

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
	findings.append_array(ScanDisk.run())
	_render(findings)


func _render(findings: Array) -> void:
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
			it.set_text(0, "%s   %s — %s" % [sev, str(f.get("source", "")), str(f.get("message", ""))])
			it.set_custom_color(0, COLOR_ERROR if sev == "ERROR" else COLOR_WARN)
			it.set_tooltip_text(0, str(f.get("message", "")))
			it.set_metadata(0, f)
	if findings.is_empty():
		_summary.text = "No issues found."
	else:
		_summary.text = "%d issue(s): %d error / %d warn — double-click a row to jump." % [findings.size(), errs, warns]


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
