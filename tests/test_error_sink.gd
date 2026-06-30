extends GutTest

## Fast off-tree coverage of ErrorSink's counting / classification (scripts/components/error_sink.gd). It drives
## the Logger virtual `_log_error` DIRECTLY with simulated push_error / push_warning / engine params — no real
## errors needed, so the suite stays clean. Preloaded by path (not the global class_name), matching DebugOverlay.

const SinkScript := preload("res://scripts/components/error_sink.gd")


## An empty, correctly-typed backtrace arg for _log_error (its signature requires Array[ScriptBacktrace]).
func _bt() -> Array[ScriptBacktrace]:
	var b: Array[ScriptBacktrace] = []
	return b


## Logger may be RefCounted (auto-freed on ref drop) or a bare Object (must be freed) — release either cleanly.
func _free_sink(sink) -> void:
	if not (sink is RefCounted):
		sink.free()


func test_push_error_counts_as_error() -> void:
	var sink = SinkScript.new()
	sink._log_error("push_error", "res://a.gd", 10, "boom", "", false, 0, _bt())
	assert_eq(sink.error_count, 1, "a push_error increments error_count")
	assert_eq(sink.warning_count, 0, "and not the warning count")
	_free_sink(sink)


func test_push_warning_counts_as_warning() -> void:
	var sink = SinkScript.new()
	sink._log_error("push_warning", "res://a.gd", 5, "careful", "", false, 1, _bt())
	assert_eq(sink.warning_count, 1, "a push_warning increments warning_count")
	assert_eq(sink.error_count, 0, "and not the error count")
	_free_sink(sink)


func test_engine_error_counts_as_error() -> void:
	# An engine error (ERR_PRINT etc.): function is the real fn, error_type 0 (ERROR) -> an error, not a warning.
	var sink = SinkScript.new()
	sink._log_error("some_func", "res://b.gd", 22, "Parameter X is null", "", false, 0, _bt())
	assert_eq(sink.error_count, 1, "an engine error counts as an error")
	assert_eq(sink.warning_count, 0)
	_free_sink(sink)


func test_engine_warning_type_counts_as_warning() -> void:
	# An engine WARNING (error_type 1 = Logger.ERROR_TYPE_WARNING) with a non-push function still buckets as a warning.
	var sink = SinkScript.new()
	sink._log_error("some_func", "res://b.gd", 22, "deprecated", "", false, 1, _bt())
	assert_eq(sink.warning_count, 1, "error_type WARNING is a warning regardless of the function name")
	assert_eq(sink.error_count, 0)
	_free_sink(sink)


func test_total_sums_both() -> void:
	var sink = SinkScript.new()
	sink._log_error("push_error", "a", 1, "e", "", false, 0, _bt())
	sink._log_error("push_warning", "a", 1, "w", "", false, 1, _bt())
	assert_eq(sink.total(), 2, "total() is errors + warnings")
	_free_sink(sink)


func test_recent_is_capped_and_keeps_newest() -> void:
	var sink = SinkScript.new(3)  # max_recent = 3
	for i in 5:
		sink._log_error("push_error", "res://a.gd", i, "code%d" % i, "", false, 0, _bt())
	var r := sink.recent()
	assert_eq(r.size(), 3, "the ring buffer keeps only the last max_recent entries")
	assert_eq(str(r[r.size() - 1].get("code")), "code4", "the newest entry is retained")
	assert_eq(str(r[0].get("code")), "code2", "the oldest entries were dropped")
	assert_eq(sink.error_count, 5, "the COUNT is never capped — only the recent buffer is")
	_free_sink(sink)


func test_recent_returns_a_snapshot_copy() -> void:
	var sink = SinkScript.new()
	sink._log_error("push_error", "res://a.gd", 1, "x", "", false, 0, _bt())
	var r := sink.recent()
	r.clear()  # mutating the returned copy must not touch the sink's live buffer
	assert_eq(sink.recent().size(), 1, "recent() hands out a copy, not the live array")
	_free_sink(sink)


func test_write_log_writes_the_captured_errors() -> void:
	var sink = SinkScript.new()
	sink._log_error("push_error", "res://a.gd", 7, "kaboom", "", false, 0, _bt())
	var path := "user://_test_error_sink.log"
	assert_true(sink.write_log(path), "write_log returns true on a successful write")
	assert_true(FileAccess.file_exists(path), "the log file is created")
	assert_true("kaboom" in FileAccess.get_file_as_string(path), "the log contains the captured error code")
	DirAccess.remove_absolute(path)
	_free_sink(sink)


func test_install_uninstall_is_safe() -> void:
	# Real OS.add_logger/remove_logger round-trip; uninstall immediately so it captures nothing else from the suite.
	var sink = SinkScript.new()
	sink.install()
	sink.uninstall()
	assert_false(sink._installed, "uninstall clears the installed flag (and deregisters the logger)")
	_free_sink(sink)
