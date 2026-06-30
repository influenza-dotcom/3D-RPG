class_name ErrorSink
extends Logger

## Runtime error / warning capture. `extends Logger` so `OS.add_logger(self)` routes EVERY engine error,
## push_error, and push_warning through `_log_error` — giving a playtest a live count + a post-mortem trail
## (user://session_errors.log) instead of console lines that vanish when the process exits. This is the runtime
## half of the QA "error capture" work; GUT already fails tests on unhandled push_errors, but a dogfooding
## play session had no record at all. DEV-TOOL: the DebugOverlay install()s one (debug builds only) and shows the
## counts; it never mutates gameplay. Reference it via preload (not the global class_name) so a not-yet-rescanned
## editor cache can't cascade. See [[new-classname-not-registered-cascade]].
##
## The counting / classification is PURE (driven only by the _log_error args), so tests call _log_error directly
## with simulated push_error / push_warning / engine params — no real errors needed. THREAD-SAFE: _log_error can
## fire from any thread (mirrors GutErrorTracker's Mutex); never call push_error/print here (would re-enter logging).

const DEFAULT_MAX_RECENT := 50
## Logger.ErrorType ordinals (ERROR=0, WARNING=1, SCRIPT=2, SHADER=3). A WARNING is the only non-error type we
## bucket as a warning; everything else through the error logger (push_error, engine, script, shader) is an error.
const WARNING_TYPE := 1

var error_count := 0
var warning_count := 0
var _recent: Array = []   ## ring buffer of { type, code, rationale, file, function, line } (newest last), capped
var _max_recent := DEFAULT_MAX_RECENT
var _mutex := Mutex.new()
var _installed := false


func _init(max_recent: int = DEFAULT_MAX_RECENT) -> void:
	_max_recent = maxi(1, max_recent)


# --- Logger override --------------------------------------------------------------------------------------------

## Godot's Logger virtual: every error/warning that reaches the engine logger arrives here (signature must match
## exactly or the override is ignored). Classify push_warning + engine warnings as warnings, everything else as
## errors. Field updates only — no logging calls (re-entrancy) and no gameplay side effects.
func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	var is_warning := error_type == WARNING_TYPE or function == &"push_warning"
	_mutex.lock()
	if is_warning:
		warning_count += 1
	else:
		error_count += 1
	_recent.append({
		"type": ("WARN" if is_warning else "ERROR"),
		"code": code, "rationale": rationale, "file": file, "function": function, "line": line,
	})
	if _recent.size() > _max_recent:
		_recent = _recent.slice(_recent.size() - _max_recent)
	_mutex.unlock()


# --- install / report -------------------------------------------------------------------------------------------

## Register with the engine so errors start flowing here. MUST be paired with uninstall() before this object is
## freed — the engine keeps a raw pointer to a registered logger, so freeing an installed one would dangle it.
func install() -> void:
	if not _installed:
		OS.add_logger(self)
		_installed = true


func uninstall() -> void:
	if _installed:
		OS.remove_logger(self)
		_installed = false


func total() -> int:
	return error_count + warning_count


## A compact, snapshot copy of the recent buffer (locked) for a HUD/dump reader — never hand out the live array.
func recent() -> Array:
	_mutex.lock()
	var out := _recent.duplicate(true)
	_mutex.unlock()
	return out


## Dump the session's captured errors to `path` (user://...). Returns true on write. Called on quit by the overlay
## so a playtest leaves a post-mortem trail even if nobody watched the console.
func write_log(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_line("# session errors — %d error(s), %d warning(s) — %s"
		% [error_count, warning_count, Time.get_datetime_string_from_system()])
	for e in recent():
		f.store_line("[%s] %s:%d  %s  —  %s" % [
			str(e.get("type")), str(e.get("file")), int(e.get("line")),
			str(e.get("function")), str(e.get("code")),
		])
	f.close()
	return true
