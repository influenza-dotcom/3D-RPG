extends GutTest

## The Tuning browser dock (plugin step 3) -- the dock constructs (compile-check, since --import skips addon-only
## scripts), and the PURE _scan_tuning helper returns a non-empty set of real tuning .tres paths. EditorInterface /
## edit_resource is editor-only and is NOT exercised here (it can't run headless).

const TuningBrowser := preload("res://addons/cybersunday_tools/dock_tuning/tuning_browser.gd")


func test_tuning_browser_constructs() -> void:
	var d = TuningBrowser.new()
	assert_not_null(d, "tuning browser should construct (compiles + _init builds its UI off-tree)")
	assert_eq(d.name, "Tuning", "dock tab name")
	d.free()


func test_scan_tuning_returns_real_tres() -> void:
	var rows := TuningBrowser._scan_tuning()
	assert_gt(rows.size(), 0, "resources/tuning/ should yield at least one tuning group")
	for r in rows:
		var path := String(r.get("path", ""))
		assert_true(path.ends_with(".tres") or path.ends_with(".res"), "every row points at a real resource file: %s" % path)
		assert_true(FileAccess.file_exists(path), "the scanned path exists on disk: %s" % path)
		assert_true(r.get("res") is Resource, "every row carries a loaded Resource (for edit_resource): %s" % path)
		assert_ne(String(r.get("name", "")), "", "every row has a display name")


func test_scan_tuning_includes_known_gamesettings_group() -> void:
	# EconomySettings.tres is a GameSettings group (GameSettings.economy) and lives in resources/tuning/.
	var rows := TuningBrowser._scan_tuning()
	var names: Array[String] = []
	for r in rows:
		names.append(String(r.get("name", "")))
	assert_true(names.has("EconomySettings"), "the browser lists the EconomySettings tuning group; got %s" % str(names))


func test_scan_tuning_describes_by_class_name() -> void:
	var rows := TuningBrowser._scan_tuning()
	var found_economy := false
	for r in rows:
		if String(r.get("name", "")) == "EconomySettings":
			found_economy = true
			assert_eq(String(r.get("desc", "")), "EconomySettings", "the row description is the resource's class_name")
	assert_true(found_economy, "EconomySettings row present to check its description")
