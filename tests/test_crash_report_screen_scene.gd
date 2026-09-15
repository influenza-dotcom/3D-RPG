extends GutTest

## The AUTHORED-SCENE contract for the crash report card (scenes/ui/crash_report_screen.tscn + crash_report_screen.gd),
## the test_atm_screen_scene.gd shape: the autoload points at the SCENE, every %node _bind_ui binds exists, no text is
## authored in the scene, the buttons stay pad-focusable, and the two things that change (the report, the status line)
## have reserved slots so the card never resizes. Open/copy behaviour is pinned on a fresh instance (never the live
## autoload — a failed assert must not leave a global screen open for the rest of the suite).
##
## It also pins the two PLACEMENT facts the crash guard's @seams rely on: CrashGuard is the FIRST autoload (its
## marker must hit disk before any other autoload's _init can crash), and this screen is the LAST (its ui_cancel
## wins the unhandled-input walk over every other modal).

const SCENE := "res://scenes/ui/crash_report_screen.tscn"
const SCREEN := preload("res://scripts/ui/crash_report_screen.gd")
const UNIQUE_NAMES: Array[String] = ["Root", "Dim", "Card", "Title", "Body", "Report", "Status", "Buttons", "Buttons2",
		"CopyButton", "OnlineButton", "FolderButton", "CloseButton"]
const BUTTONS: Array[String] = ["CopyButton", "OnlineButton", "FolderButton", "CloseButton"]


func _autoload_names() -> Array[String]:
	var names: Array[String] = []
	for p in ProjectSettings.get_property_list():
		var n := str(p.get("name", ""))
		if n.begins_with("autoload/"):
			names.append(n.trim_prefix("autoload/"))
	return names


func test_autoloads_point_at_the_scene_and_the_script_and_sit_at_both_ends() -> void:
	assert_eq(ProjectSettings.get_setting("autoload/CrashReportScreen"), "*" + SCENE, "the CrashReportScreen autoload is the authored scene")
	assert_eq(ProjectSettings.get_setting("autoload/CrashGuard"), "*res://managers/CrashGuard.gd", "the CrashGuard autoload is the script")
	var names := _autoload_names()
	assert_eq(names.front(), "CrashGuard", "CrashGuard is the FIRST autoload — its _init must run before any other autoload can crash")
	assert_eq(names.back(), "CrashReportScreen", "CrashReportScreen is the LAST autoload — its ui_cancel wins the unhandled-input walk")


func test_every_unique_name_the_script_binds_exists_and_ships_no_text() -> void:
	var inst := (load(SCENE) as PackedScene).instantiate()
	for nm in UNIQUE_NAMES:
		var node := inst.get_node_or_null("%" + nm)
		assert_not_null(node, "%%%s must exist — _bind_ui binds it at boot with no null guard" % nm)
		if node != null and node.get(&"text") != null:
			assert_eq(str(node.get(&"text")), "", "%%%s ships with EMPTY text — strings come from PlayerText, never a .tscn" % nm)
	inst.free()


func test_buttons_stay_pad_focusable_and_changing_slots_are_reserved() -> void:
	var inst := (load(SCENE) as PackedScene).instantiate()
	for nm in BUTTONS:
		var b := inst.get_node_or_null("%" + nm) as Button
		assert_not_null(b, "%s is a Button" % nm)
		if b != null:
			assert_ne(b.focus_mode, Control.FOCUS_NONE, "%s must stay focusable for controller navigation" % nm)
	assert_gt((inst.get_node("%Report") as Control).custom_minimum_size.y, 0.0,
			"the report box reserves height — a short report must not shrink the card, a long one scrolls inside it")
	assert_gt((inst.get_node("%Status") as Control).custom_minimum_size.y, 0.0,
			"the status line reserves height, or 'Copied' appearing re-centres the whole card")
	inst.free()


func test_registered_in_the_modal_registry_as_a_hands_owning_screen() -> void:
	assert_true(InputManager._modal_screens().has(CrashReportScreen), "the screen is a registry row (gameplay_suppressed / close_all_modals cover it)")
	CrashReportScreen.set(&"_is_open", true)
	assert_true(InputManager.any_tab_blocking_open(), "it owns the cursor while the player copies — a Pip-Boy tab must refuse over it")
	CrashReportScreen.set(&"_is_open", false)


func test_open_fills_the_box_and_close_clears_the_modal() -> void:
	var inst := (load(SCENE) as PackedScene).instantiate()
	inst.auto_open = false
	add_child_autofree(inst)
	assert_false(inst.is_open(), "closed at rest")
	watch_signals(inst)
	inst.open("REPORT TEXT", "user://crash_reports/x.txt")
	assert_true(inst.is_open(), "open() opens")
	assert_eq((inst.get_node("%Report") as TextEdit).text, "REPORT TEXT", "the report lands in the box")
	assert_false((inst.get_node("%Report") as TextEdit).editable, "the box is read-only — selectable, never typed into")
	assert_signal_emitted(inst, "opened", "opened fires")
	inst.close()
	assert_false(inst.is_open(), "close() closes")
	assert_signal_emitted(inst, "closed", "closed fires")


func test_never_auto_opens_under_the_editor() -> void:
	# The Stop button kills the game process, which the marker cannot tell from a crash — so under the editor
	# feature the card stays closed and the dev gets the Output line + file instead. GUT runs in the editor binary.
	assert_true(OS.has_feature("editor"), "this suite runs in the editor binary, the case the gate is for")
	var src := FileAccess.get_file_as_string("res://scripts/ui/crash_report_screen.gd")
	assert_true(src.contains("not OS.has_feature(\"editor\")"), "auto-open is gated on not running from the editor")
	assert_false(CrashReportScreen.is_open(), "the live autoload did not auto-open in this (editor-binary) process")
