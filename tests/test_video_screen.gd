extends GutTest

## VideoScreen drop-in (scripts/components/video_screen.gd) — the in-game TV / live monitor. The heavy I/O (the
## camera feed, the HTTP snapshot polling) is in-tree / playtest-only; this pins the PURE surface off-tree: sane
## @export defaults and the editor config warnings. Built via .new() (NO add_child -> no _ready -> never opens a
## camera or the network), so it stays safe + side-effect-free in the suite.

func test_defaults_are_sane() -> void:
	var v := VideoScreen.new()
	assert_eq(v.source, VideoScreen.Source.WEBCAM, "defaults to the zero-config webcam source (no url needed)")
	assert_gt(v.fps, 0.0, "the snapshot fetch rate must be positive")
	assert_true(v.autoplay, "autoplay on by default so a dropped-in screen just works when the scene runs")
	assert_gte(v.brightness, 0.0, "brightness (emission energy) is non-negative")
	v.free()

func test_config_warning_without_a_mesh() -> void:
	var v := VideoScreen.new()
	assert_true(_has(v._get_configuration_warnings(), "Mesh"),
		"warns at edit time when there's no mesh to draw the video onto")
	v.free()

func test_snapshot_source_warns_without_url() -> void:
	var v := VideoScreen.new()
	v.source = VideoScreen.Source.SNAPSHOT
	assert_true(_has(v._get_configuration_warnings(), "needs a url"),
		"SNAPSHOT source warns at edit time when no url is set")
	v.free()

func test_mjpeg_source_warns_without_url() -> void:
	var v := VideoScreen.new()
	v.source = VideoScreen.Source.MJPEG
	assert_true(_has(v._get_configuration_warnings(), "needs a url"),
		"MJPEG source warns at edit time when no url is set")
	v.free()

func test_webcam_source_does_not_require_a_url() -> void:
	var v := VideoScreen.new()
	# WEBCAM is the default; its only warning should be about the mesh, never a url.
	assert_false(_has(v._get_configuration_warnings(), "needs a url"),
		"the webcam source needs no url, so it must not warn about one")
	v.free()

func _has(w: PackedStringArray, fragment: String) -> bool:
	for s in w:
		if s.contains(fragment):
			return true
	return false
