extends Node

## @system Crash Guard
## @seam The FIRST [autoload] row in project.godot: _init writes user://crash_guard/session.cfg before any other autoload's _init runs, and ONLY a clean quit (_exit_tree) rewrites it as clean — a marker found not-clean at the next boot means the previous run died (a crash, a hang killed from Task Manager, or the editor's Stop button).
## @seam CrashReportScreen (the LAST [autoload] row) calls previous_crash() once in its _ready and shows the player the report; nothing else reads the marker, and any script may drop a breadcrumb(text) so a report says what the game was doing.
## @seam Installs an ErrorSink (scripts/components/error_sink.gd) in EVERY build, so the marker carries the last errors even in a release export; the DebugOverlay's sink is a second, debug-only listener on the same OS.add_logger seam.
## @risk A crash BEFORE this _init (a GDExtension that fails to load, a hollow .pck) leaves no marker and is invisible here — the console wrapper (CYBERSUNDAY.console.exe) and user://logs/godot.log are the only trail, and README says so.
## @risk A heap-corruption fail-fast never delivers NOTIFICATION_CRASH, so the last heartbeat (HEARTBEAT_SECONDS) BOUNDS the moment of death; it does not pin it.
## @test res://tests/test_crash_guard.gd
##
## CrashGuard — the player-facing crash detector. The engine cannot report its own native crash (the process
## is gone before any script runs), so detection is the classic marker file: written at boot, heartbeat while
## alive, marked clean on quit. Whatever survives to the next boot is the post-mortem: build + GPU, uptime, the
## last scene, breadcrumbs, the last errors, and — on Windows — the Application-Error event the OS logged for
## the crashed executable (exception code + faulting module), plus the tail of the crashed run's own engine
## log (Godot rotates it to user://logs/godot<timestamp>.log at the next boot). All of that is composed into
## ONE text file under user://crash_reports/ so a demo player can copy-paste it into a bug report.
##
## DEV BUILDS: running from the editor sets every one of these too, and the Stop button KILLS the game
## process, so the next run reads it as an abnormal end. The report is still written and one Output line
## names it — deliberately, it is exactly the trail a dev wants — but CrashReportScreen only auto-opens
## OUTSIDE the editor, so the card never nags a developer who just pressed Stop.

## Preloaded BY PATH (not the global class_name) so a not-yet-rescanned editor cache cannot cascade — the
## DebugOverlay precedent. See [[new-classname-not-registered-cascade]].
const ErrorSinkScript := preload("res://scripts/components/error_sink.gd")

const MARKER_PATH := "user://crash_guard/session.cfg"
const REPORT_DIR := "user://crash_reports"
const LOG_DIR := "user://logs"          ## where the engine's own file logger rotates (debug/file_logging, on by default on PC)
const KEEP_REPORTS := 10                ## oldest report files are pruned past this many
const HEARTBEAT_SECONDS := 5.0          ## how often the live marker is refreshed (uptime / scene / error tally)
const MAX_BREADCRUMBS := 24
const MAX_ERRORS := 30
const LOG_TAIL_BYTES := 65536           ## how much of the crashed run's engine log is read (from the end)
const LOG_TAIL_LINES := 80              ## and how many of its last lines the report quotes
const WINDOWS_EVENT_COUNT := 8          ## how many recent Application-Error events wevtutil is asked for
const REPORT_SINCE_SLACK := 60          ## seconds before the crashed run's start that a Windows event may still count

var _session: Dictionary = {}
var _previous: Dictionary = {}
var _previous_crash: Dictionary = {}    ## { "report": String, "path": String } once a bad marker became a report
var _sink = null                        ## an ErrorSink (untyped: the DebugOverlay precedent for the new global class_name)
var _accum := 0.0
var _last_error_total := 0


func _init() -> void:
	# _init, not _ready: this is the first autoload, so nothing else has run yet — the marker is on disk before
	# any other autoload's _init can crash the game. (An autoload _init may not touch the tree; nothing here does.)
	_previous = load_marker(MARKER_PATH)
	_session = new_session()
	save_marker(MARKER_PATH, _session)
	_sink = ErrorSinkScript.new(MAX_ERRORS)
	_sink.install()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # the heartbeat keeps running through a paused menu
	if previous_ended_abnormally(_previous):
		_previous_crash = _write_previous_report()
		if not _previous_crash.is_empty():
			print("CrashGuard: the previous run did not exit cleanly — report written to ", _previous_crash.get("path", ""))
	breadcrumb("boot")


func _process(delta: float) -> void:
	_accum += delta
	var errors_now: int = _sink.total() if _sink != null else 0
	if _accum < HEARTBEAT_SECONDS and errors_now == _last_error_total:
		return
	_accum = 0.0
	_last_error_total = errors_now
	_refresh_live_fields()
	save_marker(MARKER_PATH, _session)


func _notification(what: int) -> void:
	if what == NOTIFICATION_CRASH:
		# The engine's own crash handler (SEH / signal) caught it — a best-effort last gasp so the report can
		# say so. A heap fail-fast never gets here (see the @risk above).
		_session["crash_signal"] = true
		_refresh_live_fields()
		save_marker(MARKER_PATH, _session)


func _exit_tree() -> void:
	# The ONLY place the marker turns clean. Autoloads leave the tree on quit while scripting is still alive;
	# anything that skips this (a crash, a kill) leaves the not-clean marker for the next boot to find.
	_refresh_live_fields()
	_session["clean_exit"] = true
	save_marker(MARKER_PATH, _session)
	if _sink != null:
		_sink.uninstall()
		_sink = null


# --- public ------------------------------------------------------------------------------------------------

## Leave a note about what the game is doing ("loading res://scenes/levels/x.tscn", "slept 6h"). Written to
## disk at once, so a crash during the very next thing still shows this line as the last one.
func breadcrumb(text: String) -> void:
	var crumbs: Array = _session.get("breadcrumbs", [])
	crumbs.append("%s  %s" % [_uptime_stamp(), text])
	_session["breadcrumbs"] = trim_to(crumbs, MAX_BREADCRUMBS)
	_refresh_live_fields()
	save_marker(MARKER_PATH, _session)


## The previous run's crash, if there was one: { "report": <the whole text>, "path": <user:// file> }; {} otherwise.
func previous_crash() -> Dictionary:
	return _previous_crash.duplicate()


## The OS folder the reports live in (for "Open report folder").
func report_dir_global() -> String:
	return ProjectSettings.globalize_path(REPORT_DIR)


# --- the live marker ---------------------------------------------------------------------------------------

func _refresh_live_fields() -> void:
	_session["uptime"] = _uptime()
	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		_session["scene"] = tree.current_scene.scene_file_path
	if _sink != null:
		_session["error_count"] = _sink.error_count
		_session["warning_count"] = _sink.warning_count
		var recent: Array = []
		for e in _sink.recent():
			recent.append(format_error(e))
		_session["errors"] = recent   # the sink's ring is already capped at MAX_ERRORS


func _uptime() -> float:
	return Time.get_ticks_msec() / 1000.0


func _uptime_stamp() -> String:
	return "%7.1fs" % _uptime()


## Compose + write the report for a bad marker. Returns { report, path } (path "" if the write failed).
func _write_previous_report() -> Dictionary:
	var detected := Time.get_datetime_string_from_system(false)
	var started := str(_previous.get("started", detected))
	var since := int(Time.get_unix_time_from_datetime_string(started)) - REPORT_SINCE_SLACK
	var win := windows_crash_record(str(_previous.get("executable", "")), since)
	var log_path := previous_log_path()
	var tail := log_tail(log_path) if not log_path.is_empty() else PackedStringArray()
	var text := compose_report(_previous, detected, win, log_path, tail)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPORT_DIR))
	var path := REPORT_DIR.path_join("crash_%s.txt" % started.replace(":", "-"))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"report": text, "path": ""}
	f.store_string(text)
	f.close()
	prune_reports(REPORT_DIR, KEEP_REPORTS)
	return {"report": text, "path": path}


# --- pure pieces (unit-tested) -----------------------------------------------------------------------------

## What this machine and build are — captured at boot into the marker, so the report describes the run that
## CRASHED, not the run that found it.
static func environment() -> Dictionary:
	return {
		"game_version": str(ProjectSettings.get_setting("application/config/version", "")),
		"executable": OS.get_executable_path().get_file(),
		"debug_build": OS.is_debug_build(),
		"editor_run": OS.has_feature("editor"),
		"godot": str(Engine.get_version_info().get("string", "")),
		"os": "%s %s" % [OS.get_name(), OS.get_version()],
		"cpu": OS.get_processor_name(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"gpu_driver": " ".join(OS.get_video_adapter_driver_info()),
		"renderer": "%s / %s" % [RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_current_rendering_method()],
		"locale": OS.get_locale(),
	}


## A fresh, not-yet-clean marker for the run that is starting now.
static func new_session() -> Dictionary:
	var s := environment()
	s["started"] = Time.get_datetime_string_from_system(false)   # local, ISO "YYYY-MM-DDTHH:MM:SS"
	s["clean_exit"] = false
	s["crash_signal"] = false
	s["uptime"] = 0.0
	s["scene"] = ""
	s["breadcrumbs"] = []
	s["errors"] = []
	s["error_count"] = 0
	s["warning_count"] = 0
	return s


static func save_marker(path: String, data: Dictionary) -> bool:
	var dir := ProjectSettings.globalize_path(path.get_base_dir())
	if not DirAccess.dir_exists_absolute(dir) and DirAccess.make_dir_recursive_absolute(dir) != OK:
		return false
	var cfg := ConfigFile.new()
	for k in data:
		cfg.set_value("session", str(k), data[k])
	return cfg.save(path) == OK


static func load_marker(path: String) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK or not cfg.has_section("session"):
		return {}
	var out := {}
	for k in cfg.get_section_keys("session"):
		out[k] = cfg.get_value("session", k)
	return out


## A marker that exists and was never marked clean = the run it describes died.
static func previous_ended_abnormally(marker: Dictionary) -> bool:
	return not marker.is_empty() and marker.get("clean_exit", false) != true


static func trim_to(list: Array, cap: int) -> Array:
	if list.size() <= cap:
		return list
	return list.slice(list.size() - cap)


## One ErrorSink record as one report line, with its GDScript trace when the engine gave one.
static func format_error(e: Dictionary) -> String:
	var line := "[%s] %s:%d %s — %s" % [str(e.get("type", "ERROR")), str(e.get("file", "")),
			int(e.get("line", 0)), str(e.get("function", "")), str(e.get("code", ""))]
	var trace := str(e.get("trace", ""))
	return line if trace.is_empty() else line + "  <- " + trace


## Ask Windows for its own record of the crash: the Application-Error event (exception code, faulting
## module, offset) it logs for every process that dies on an unhandled exception. `wevtutil` ships with
## Windows and needs no admin rights to read the Application log. {} elsewhere or when nothing matches.
static func windows_crash_record(exe_name: String, since_unix: int) -> Dictionary:
	if OS.get_name() != "Windows" or exe_name.is_empty():
		return {}
	var out: Array = []
	var code := OS.execute("wevtutil", ["qe", "Application",
			"/q:*[System[Provider[@Name='Application Error'] and (EventID=1000)]]",
			"/c:%d" % WINDOWS_EVENT_COUNT, "/rd:true", "/f:text"], out, true)
	if code != 0 or out.is_empty():
		return {}
	return parse_windows_crash_events(str(out[0]), exe_name, since_unix)


## Parse `wevtutil qe ... /f:text` output (newest first) into the first record for `exe_name` at or after
## `since_unix`. wevtutil prints the event's LOCAL time with a spurious trailing "Z"; markers are local ISO
## too, and both go through the same (UTC-assuming) parser, so the comparison stays consistent.
static func parse_windows_crash_events(text: String, exe_name: String, since_unix: int) -> Dictionary:
	for block in text.split("Event[", false):
		var app := _field(block, "Faulting application name:")
		if app.is_empty():
			continue
		app = app.split(",")[0].strip_edges()
		if app.to_lower() != exe_name.to_lower():
			continue
		var when := _field(block, "Date:").left(19)
		if int(Time.get_unix_time_from_datetime_string(when)) < since_unix:
			continue
		return {
			"when": when,
			"exception": _field(block, "Exception code:"),
			"module": _field(block, "Faulting module name:").split(",")[0].strip_edges(),
			"offset": _field(block, "Fault offset:"),
			"app": app,
		}
	return {}


static func _field(block: String, key: String) -> String:
	var i := block.find(key)
	if i < 0:
		return ""
	var rest := block.substr(i + key.length())
	var nl := rest.find("\n")
	return (rest if nl < 0 else rest.left(nl)).strip_edges()


## The crashed run's engine log. Godot's file logger renames the last run's godot.log to godot<stamp>.log
## when THIS run starts, so the newest rotated file (by modified time) is the previous run's. Exact for a
## player's install (one process); under DEV, concurrent headless/test processes share the same logs folder
## and the newest file can be one of theirs — read the header lines before trusting a dev-machine tail.
static func previous_log_path() -> String:
	var dir := DirAccess.open(LOG_DIR)
	if dir == null:
		return ""
	var best := ""
	var best_time := 0
	for file_name in dir.get_files():
		if not file_name.begins_with("godot") or not file_name.ends_with(".log") or file_name == "godot.log":
			continue
		var path := LOG_DIR.path_join(file_name)
		var t := FileAccess.get_modified_time(path)
		if t > best_time:
			best_time = t
			best = path
	return best


## The last `max_lines` lines of a (possibly huge) file, reading at most `max_bytes` from its end. Resumes at
## a line start so a UTF-8 sequence split by the seek is never decoded.
static func log_tail(path: String, max_bytes: int = LOG_TAIL_BYTES, max_lines: int = LOG_TAIL_LINES) -> PackedStringArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedStringArray()
	var length := int(f.get_length())
	var start := maxi(0, length - max_bytes)
	f.seek(start)
	var bytes := f.get_buffer(length - start)
	f.close()
	if start > 0:
		var nl := bytes.find(10)
		bytes = bytes.slice(nl + 1) if nl >= 0 else PackedByteArray()
	var lines := bytes.get_string_from_utf8().split("\n")
	while lines.size() > 0 and lines[lines.size() - 1].strip_edges().is_empty():
		lines.remove_at(lines.size() - 1)
	if lines.size() > max_lines:
		lines = lines.slice(lines.size() - max_lines)
	return lines


## Keep the newest `keep` report files (names sort by start time), remove the rest.
static func prune_reports(dir_path: String, keep: int) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	var names: Array = []
	for file_name in dir.get_files():
		if file_name.begins_with("crash_") and file_name.ends_with(".txt"):
			names.append(file_name)
	names.sort()
	while names.size() > keep:
		dir.remove(String(names.pop_front()))


## The whole report as one string — the thing the player copies. Every section is labelled so a reader who
## gets it pasted into an issue knows what they are looking at without the game in front of them.
static func compose_report(prev: Dictionary, detected_at: String, win: Dictionary, log_path: String, tail: PackedStringArray) -> String:
	var L: PackedStringArray = []
	L.append("CYBER SUNDAY crash report")
	L.append("=========================")
	L.append("Copy everything in this file into your bug report.")
	L.append("")
	L.append("Detected at:        %s (on the next launch)" % detected_at)
	L.append("Crashed run began:  %s" % str(prev.get("started", "?")))
	L.append("Ran for:            %s" % _seconds_text(float(prev.get("uptime", 0.0))))
	L.append("Ended:              %s" % ("the engine's crash handler fired" if prev.get("crash_signal", false) == true
			else "no clean exit (crash, killed, or lost power)"))
	L.append("Last scene:         %s" % _or(str(prev.get("scene", "")), "(none yet — died during startup)"))
	L.append("")
	L.append("Game version:       %s  (%s, %s)" % [_or(str(prev.get("game_version", "")), "unset"),
			"debug build" if prev.get("debug_build", false) == true else "release build",
			"run from the editor" if prev.get("editor_run", false) == true else "exported"])
	L.append("Executable:         %s" % str(prev.get("executable", "")))
	L.append("Godot:              %s" % str(prev.get("godot", "")))
	L.append("OS:                 %s" % str(prev.get("os", "")))
	L.append("CPU:                %s" % str(prev.get("cpu", "")))
	L.append("GPU:                %s  driver %s" % [str(prev.get("gpu", "")), str(prev.get("gpu_driver", ""))])
	L.append("Renderer:           %s" % str(prev.get("renderer", "")))
	L.append("Locale:             %s" % str(prev.get("locale", "")))
	L.append("")
	L.append("Windows crash record (Application Error event):")
	if win.is_empty():
		L.append("  none found for this executable since the run began")
	else:
		L.append("  %s  exception %s in %s  offset %s  (%s)" % [str(win.get("when", "")), str(win.get("exception", "")),
				str(win.get("module", "")), str(win.get("offset", "")), str(win.get("app", ""))])
	L.append("")
	L.append("Breadcrumbs (uptime  event):")
	var crumbs: Array = prev.get("breadcrumbs", [])
	if crumbs.is_empty():
		L.append("  (none)")
	for c in crumbs:
		L.append("  " + str(c))
	L.append("")
	var errs: Array = prev.get("errors", [])
	L.append("Errors in that run: %d errors, %d warnings — the last %d:" % [int(prev.get("error_count", 0)),
			int(prev.get("warning_count", 0)), errs.size()])
	if errs.is_empty():
		L.append("  (none)")
	for e in errs:
		L.append("  " + str(e))
	L.append("")
	L.append("Engine log of the crashed run (%s), last %d lines:" % [_or(log_path, "not found"), tail.size()])
	L.append("-----------------------------------------------------------------")
	for line in tail:
		L.append(line)
	L.append("-----------------------------------------------------------------")
	L.append("end of report")
	return "\n".join(L)


static func _or(s: String, fallback: String) -> String:
	return fallback if s.strip_edges().is_empty() else s


static func _seconds_text(secs: float) -> String:
	if secs < 60.0:
		return "%.1f s" % secs
	@warning_ignore("integer_division") # whole minutes are the point
	return "%d min %d s  (%.0f s)" % [int(secs) / 60, int(secs) % 60, secs]
