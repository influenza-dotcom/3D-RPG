extends CanvasLayer

## @system Crash Report Screen
## @seam Autoload modal and the LAST [autoload] row on purpose: unhandled input walks the tree from the last child back, so its ui_cancel wins over every other screen; registered in InputManager's modal registry as blocks_tabs so gameplay stays suppressed while it is up.
## @seam Reads CrashGuard.previous_crash() ONCE in _ready and opens itself over the boot scene when the marker says the last run died — nothing else opens it, and it never auto-opens inside the editor (OS.has_feature("editor")), so the Stop button cannot nag a developer; the file and the Output line still land.
## @seam Copy = DisplayServer.clipboard_set of the whole report; Open folder = OS.shell_open of CrashGuard.report_dir_global(); Report online = OS.shell_open(report_url), an @export a designer points at the tracker (empty = no button).
## @risk The card is a FIXED frame: the report scrolls inside a reserved TextEdit and the status line hides by ALPHA, so copying can never resize or re-centre the card under the cursor (the house rule, tests/test_menu_layout_stability.gd).
## @test res://tests/test_crash_report_screen_scene.gd
##
## CrashReportScreen — what a demo player sees on the launch after a crash: a card saying the last run
## crashed, the report CrashGuard already wrote (scrollable, selectable), and one-click Copy so pasting it
## into a bug report is the whole job. Open folder / Report online are the two escape hatches for a player
## who would rather attach the file or go straight to the tracker.
##
## AUTHORED SCENE: the layout lives in scenes/ui/crash_report_screen.tscn (this autoload IS that scene — see
## project.godot [autoload]); this script binds its chrome by %unique name in _bind_ui and applies the
## skin-driven look (MenuStyle adopters) on top. NO text is authored in the scene — every string is set here
## from PlayerText.
##
## REAL-TIME like the other standalone modals: it opens over the BOOT scene, where there is no world to pause.

signal opened
signal closed

## Where "Report online" sends the player. Empty hides that button (decided once, before the card is ever shown).
@export var report_url: String = "https://github.com/influenza-dotcom/3D-RPG/issues/new"
## Auto-open on boot when CrashGuard found a bad marker. Off = the card only opens through open(); a dev knob.
@export var auto_open: bool = true

var _root: Control
var _title: Label
var _body: Label
var _report_box: TextEdit
var _status: Label
var _copy_btn: Button
var _folder_btn: Button
var _online_btn: Button
var _close_btn: Button
var _is_open := false
var _report := ""
var _report_path := ""
var _prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	layer = 122                                  # above every gameplay modal (121): it opens over the boot scene
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bind_ui()
	_root.visible = false
	if auto_open and not OS.has_feature("editor"):
		var prev: Dictionary = CrashGuard.previous_crash()
		if not prev.is_empty():
			# Deferred: open() grabs the mouse and seeds focus, which wants the boot scene already in the tree.
			open.call_deferred(str(prev.get("report", "")), str(prev.get("path", "")))


func is_open() -> bool:
	return _is_open


## Show the card with `report` in the box. No modal gate: it opens at boot before any other screen exists, and
## a later caller (a menu button) is showing the player something they asked for.
func open(report: String, path: String = "") -> void:
	if _is_open:
		return
	_report = report
	_report_path = path
	_report_box.text = report
	_show_status("", MenuStyle.text_color())
	_prev_mouse_mode = ModalMenu.grab_mouse()
	_is_open = true
	_root.visible = true
	# Seed pad/keyboard focus once the card is VISIBLE (grab_focus on a hidden Control does nothing).
	if is_instance_valid(_copy_btn):
		_copy_btn.grab_focus()
	opened.emit()


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_root.visible = false
	ModalMenu.restore_mouse(_prev_mouse_mode)
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if _is_open and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------------------------------
# Buttons
# ---------------------------------------------------------------------------------------------------

func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(_report)
	MenuStyle.play_commit()
	_show_status(PlayerText.CRASH_COPIED, MenuStyle.accent())


func _on_folder_pressed() -> void:
	MenuStyle.play_select()
	OS.shell_open(CrashGuard.report_dir_global())


func _on_online_pressed() -> void:
	MenuStyle.play_select()
	OS.shell_open(report_url)


## Set (or clear) the status line WITHOUT changing the card's size: the label keeps its reserved height and
## an empty message is hidden with ALPHA, not `visible` (the WaitScreen rule).
func _show_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override(&"font_color", color)
	_status.modulate.a = 0.0 if text.is_empty() else 1.0


# ---------------------------------------------------------------------------------------------------
# UI binding (the layout is AUTHORED in scenes/ui/crash_report_screen.tscn — this adopts it)
# ---------------------------------------------------------------------------------------------------

## Bind the authored chrome by %unique name, style it from the skin, and wire behaviour. What the scene
## guarantees and this preserves:
##  * the card is a FIXED-WIDTH centered dialog (style_dialog_card pins %Card to skin.dialog_width);
##  * the two things that change have RESERVED slots (the report box's minimum height, the status line's),
##    so no repaint can resize or re-centre the card;
##  * CONTROLLER PARITY: the authored Buttons carry NO `focus_mode = 0`, and open() seeds focus on Copy;
##  * every string is set HERE from PlayerText — the scene ships with empty text properties.
func _bind_ui() -> void:
	_root = %Root
	MenuStyle.apply(_root)  # shared menu Theme (panel/buttons/tooltips/fonts) — reskin via resources/ui/menu_skin.tres
	MenuStyle.style_dim(%Dim)
	MenuStyle.style_dialog_card(%Card, 2)
	MenuStyle.style_button_row(%Buttons)
	MenuStyle.style_button_row(%Buttons2)

	_title = MenuStyle.cap_label(%Title)
	MenuStyle.style_title(_title)
	_title.text = MenuStyle.title_text(PlayerText.CRASH_TITLE)

	_body = %Body
	_body.text = PlayerText.CRASH_BODY
	_body.add_theme_color_override(&"font_color", MenuStyle.dim_color())

	_report_box = %Report
	_report_box.editable = false   # selectable + scrollable, never typed into

	_status = %Status
	MenuStyle.style_hint(_status)

	_copy_btn = MenuStyle.cap_button(%CopyButton)
	_copy_btn.text = PlayerText.CRASH_COPY
	_copy_btn.pressed.connect(_on_copy_pressed)
	_online_btn = MenuStyle.cap_button(%OnlineButton)
	_online_btn.text = PlayerText.CRASH_REPORT_ONLINE
	_online_btn.pressed.connect(_on_online_pressed)
	_online_btn.visible = not report_url.strip_edges().is_empty()   # decided before the card is ever shown — no runtime shift
	_folder_btn = MenuStyle.cap_button(%FolderButton)
	_folder_btn.text = PlayerText.CRASH_OPEN_FOLDER
	_folder_btn.pressed.connect(_on_folder_pressed)
	_close_btn = MenuStyle.cap_button(%CloseButton)
	_close_btn.text = PlayerText.CLOSE
	_close_btn.pressed.connect(close)
	_show_status("", MenuStyle.text_color())
