extends GutTest

## CrashGuard (managers/CrashGuard.gd) — the marker-file crash detector behind the player-facing crash report.
## Everything a report is MADE of is a static, pure function, so it tests off-tree with fabricated markers and
## a captured wevtutil transcript. The one live check is the boot-time contract in THIS process: the autoload
## wrote its marker before the suite loaded, and that marker still says "not clean" (only _exit_tree flips it).

const GUARD := preload("res://managers/CrashGuard.gd")
const TMP_MARKER := "user://gut_temp_directory/crash_guard_marker_test.cfg"
const TMP_LOG := "user://gut_temp_directory/crash_guard_tail_test.log"

## A real `wevtutil qe Application ... /rd:true /f:text` transcript, trimmed: newest event first, two apps.
const WEVTUTIL_SAMPLE := """Event[0]:
  Log Name: Application
  Source: Application Error
  Date: 2026-09-12T11:31:02.3140000Z
  Event ID: 1000
  Description:
Faulting application name: CYBERSUNDAY.exe, version: 4.7.2.0, time stamp: 0x6a8269f4
Faulting module name: ntdll.dll, version: 10.0.19041.6456, time stamp: 0x7ec9c15d
Exception code: 0xc0000005
Fault offset: 0x000000000002faad
Faulting process id: 0x5bf8

Event[1]:
  Log Name: Application
  Source: Application Error
  Date: 2026-09-12T09:42:57.0000000Z
  Event ID: 1000
  Description:
Faulting application name: other.exe, version: 1.0.0.0, time stamp: 0x0
Faulting module name: other.dll, version: 1.0.0.0, time stamp: 0x0
Exception code: 0xc0000374
Fault offset: 0x0000000000000001
"""


func _unix(iso: String) -> int:
	return int(Time.get_unix_time_from_datetime_string(iso))


func _fake_marker() -> Dictionary:
	return {
		"started": "2026-09-12T11:20:00", "clean_exit": false, "crash_signal": false, "uptime": 312.4,
		"scene": "res://scenes/game.tscn", "game_version": "", "debug_build": false, "editor_run": false,
		"executable": "CYBERSUNDAY.exe", "godot": "4.7.2.stable", "os": "Windows 10.0.19045", "cpu": "cpu",
		"gpu": "NVIDIA GeForce GTX 1660", "gpu_driver": "nvidia 1.0", "renderer": "d3d12 / forward_plus",
		"locale": "en_US", "breadcrumbs": ["    0.0s  boot", "   12.5s  loading res://scenes/levels/alive.tscn"],
		"errors": ["[ERROR] res://scripts/x.gd:12 _ready — boom"], "error_count": 1, "warning_count": 4,
	}


# --- what counts as a crash ---------------------------------------------------------------------------

func test_a_missing_or_clean_marker_is_not_a_crash() -> void:
	assert_false(GUARD.previous_ended_abnormally({}), "no marker at all (first launch) -> nothing to report")
	assert_false(GUARD.previous_ended_abnormally({"clean_exit": true, "started": "x"}), "a clean quit -> nothing to report")


func test_a_marker_that_was_never_marked_clean_is_a_crash() -> void:
	assert_true(GUARD.previous_ended_abnormally({"clean_exit": false, "started": "x"}),
			"the marker survived to the next boot without _exit_tree flipping it -> the run died")
	assert_true(GUARD.previous_ended_abnormally({"started": "x"}),
			"a marker with no clean_exit key at all is treated as not clean, never as clean by default")


func test_marker_round_trips_through_the_config_file() -> void:
	var m := _fake_marker()
	assert_true(GUARD.save_marker(TMP_MARKER, m), "save_marker writes under user://")
	var back: Dictionary = GUARD.load_marker(TMP_MARKER)
	assert_eq(back.get("started"), m["started"], "started survives")
	assert_eq(back.get("clean_exit"), false, "clean_exit survives as a bool, not a string")
	assert_eq(back.get("breadcrumbs"), m["breadcrumbs"], "the breadcrumb array survives intact")
	assert_eq(back.get("errors"), m["errors"], "the error lines survive intact")
	assert_almost_eq(float(back.get("uptime")), 312.4, 0.001, "uptime survives")
	assert_eq(GUARD.load_marker("user://gut_temp_directory/does_not_exist.cfg"), {}, "a missing file loads as {}")


# --- Windows' own record of the crash -------------------------------------------------------------------

func test_windows_events_pick_the_newest_record_for_this_executable() -> void:
	var rec: Dictionary = GUARD.parse_windows_crash_events(WEVTUTIL_SAMPLE, "CYBERSUNDAY.exe", _unix("2026-09-12T11:00:00"))
	assert_eq(rec.get("exception"), "0xc0000005", "the exception code is read off the record")
	assert_eq(rec.get("module"), "ntdll.dll", "the faulting module is the name only, not its version tail")
	assert_eq(rec.get("offset"), "0x000000000002faad", "the fault offset is kept verbatim")
	assert_eq(rec.get("when"), "2026-09-12T11:31:02", "the event time is the local ISO stamp without the fraction")
	assert_eq(rec.get("app"), "CYBERSUNDAY.exe", "the app name is the executable's file name")


func test_windows_events_ignore_other_executables_and_older_records() -> void:
	assert_eq(GUARD.parse_windows_crash_events(WEVTUTIL_SAMPLE, "nope.exe", 0), {}, "another program's crash is not ours")
	assert_eq(GUARD.parse_windows_crash_events(WEVTUTIL_SAMPLE, "CYBERSUNDAY.exe", _unix("2026-09-12T11:40:00")), {},
			"a record from BEFORE the crashed run began is an older crash, not this one")
	var other: Dictionary = GUARD.parse_windows_crash_events(WEVTUTIL_SAMPLE, "other.exe", 0)
	assert_eq(other.get("exception"), "0xc0000374", "a later block is still found when the first is another app")
	assert_eq(GUARD.parse_windows_crash_events("", "CYBERSUNDAY.exe", 0), {}, "empty output -> {} rather than an error")


# --- the report -----------------------------------------------------------------------------------------

func test_report_carries_every_section_a_bug_report_needs() -> void:
	var win := {"when": "2026-09-12T11:25:12", "exception": "0xc0000005", "module": "ntdll.dll", "offset": "0x2faad", "app": "CYBERSUNDAY.exe"}
	var tail := PackedStringArray(["ERROR: last line of the engine log"])
	var text: String = GUARD.compose_report(_fake_marker(), "2026-09-12T11:26:00", win, "user://logs/godot2026.log", tail)
	for needle in ["CYBER SUNDAY crash report", "2026-09-12T11:20:00", "res://scenes/game.tscn", "release build", "exported",
			"NVIDIA GeForce GTX 1660", "d3d12 / forward_plus", "0xc0000005 in ntdll.dll", "loading res://scenes/levels/alive.tscn",
			"[ERROR] res://scripts/x.gd:12 _ready — boom", "1 errors, 4 warnings", "last line of the engine log", "5 min 12 s"]:
		assert_true(text.contains(needle), "the report names '%s'" % needle)


func test_report_degrades_when_nothing_was_captured() -> void:
	var bare := {"started": "2026-09-12T11:20:00", "clean_exit": false}
	var text: String = GUARD.compose_report(bare, "2026-09-12T11:26:00", {}, "", PackedStringArray())
	assert_true(text.contains("died during startup"), "no scene recorded -> says the run died during startup")
	assert_true(text.contains("none found for this executable"), "no Windows record -> says so instead of a blank")
	assert_true(text.contains("not found"), "no engine log -> says so instead of a blank")
	assert_true(text.contains("(none)"), "empty breadcrumbs / errors print a placeholder, never nothing")


func test_error_lines_carry_a_trace_only_when_the_engine_gave_one() -> void:
	var bare := GUARD.format_error({"type": "ERROR", "file": "res://a.gd", "line": 3, "function": "_ready", "code": "boom"})
	assert_eq(bare, "[ERROR] res://a.gd:3 _ready — boom", "no trace -> no arrow")
	var traced := GUARD.format_error({"type": "WARN", "file": "res://a.gd", "line": 3, "function": "f", "code": "x", "trace": "g (res://b.gd:9)"})
	assert_true(traced.ends_with("  <- g (res://b.gd:9)"), "a trace is appended after an arrow")


func test_breadcrumb_ring_keeps_the_newest() -> void:
	assert_eq(GUARD.trim_to([1, 2, 3], 5), [1, 2, 3], "under the cap -> untouched")
	assert_eq(GUARD.trim_to([1, 2, 3, 4, 5, 6], 4), [3, 4, 5, 6], "over the cap -> the OLDEST fall off")


func test_log_tail_reads_only_the_end_of_a_big_file() -> void:
	var f := FileAccess.open(TMP_LOG, FileAccess.WRITE)
	for i in 500:
		f.store_line("line %d — é" % i)   # a non-ASCII char per line: a mid-sequence seek must not corrupt the decode
	f.close()
	var tail: PackedStringArray = GUARD.log_tail(TMP_LOG, 1024, 10)
	assert_eq(tail.size(), 10, "capped at max_lines")
	assert_eq(tail[9], "line 499 — é", "the last line of the file is the last line of the tail")
	assert_eq(tail[0], "line 490 — é", "and the ten are contiguous, whole lines")
	assert_eq(GUARD.log_tail("user://gut_temp_directory/nope.log").size(), 0, "a missing log -> empty, no error")


# --- the live contract --------------------------------------------------------------------------------------

func test_the_live_autoload_wrote_its_marker_at_boot_and_it_is_not_clean_yet() -> void:
	assert_true(FileAccess.file_exists(GUARD.MARKER_PATH), "CrashGuard._init wrote the session marker before the suite loaded")
	var m: Dictionary = GUARD.load_marker(GUARD.MARKER_PATH)
	assert_eq(m.get("clean_exit"), false, "the marker is NOT clean while the process lives — only _exit_tree flips it")
	assert_false(str(m.get("started", "")).is_empty(), "the marker names when this run began")
	assert_eq(m.get("executable"), OS.get_executable_path().get_file(), "the marker names THIS executable (what the Windows event lookup matches on)")
	assert_true(CrashGuard.previous_crash() is Dictionary, "previous_crash() answers a Dictionary ({} when the last run quit cleanly)")
	assert_true(CrashGuard.report_dir_global().ends_with("crash_reports"), "the report folder is user://crash_reports, globalized for shell_open")
