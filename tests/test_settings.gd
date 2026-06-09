extends GutTest
## Smoke + clamp tests for the Settings autoload (the user-facing options + persistence layer).
## Persistence is disabled per-test (Settings._loaded = false makes save_settings a no-op) so these
## NEVER write the real user://settings.cfg, and the live GameSettings fields the setters write through
## to are captured + restored so we don't pollute the camera/shake suites.

var _fov: float
var _sens: float
var _shake: float

func before_each() -> void:
	_fov = GameSettings.camera.default_fov
	_sens = GameSettings.camera.mouse_sensitivity
	_shake = GameSettings.screen_shake.intensity_multiplier
	Settings._loaded = false  # disable persistence for the duration of the test

func after_each() -> void:
	GameSettings.camera.default_fov = _fov
	GameSettings.camera.mouse_sensitivity = _sens
	GameSettings.screen_shake.intensity_multiplier = _shake
	Settings._loaded = true

func test_autoload_present() -> void:
	assert_not_null(Settings, "Settings autoload should be registered")

func test_set_fov_clamps_and_writes_through() -> void:
	Settings.set_fov(9999.0)
	assert_eq(Settings.fov, Settings.FOV_MAX, "FOV clamps to max")
	assert_eq(GameSettings.camera.default_fov, Settings.FOV_MAX, "FOV writes through to GameSettings")
	Settings.set_fov(0.0)
	assert_eq(Settings.fov, Settings.FOV_MIN, "FOV clamps to min")

func test_set_mouse_sensitivity_clamps_and_writes_through() -> void:
	Settings.set_mouse_sensitivity(99.0)
	assert_eq(Settings.mouse_sensitivity, Settings.SENS_MAX, "sensitivity clamps to max")
	assert_eq(GameSettings.camera.mouse_sensitivity, Settings.SENS_MAX, "sensitivity writes through")

func test_set_volume_clamps_to_unit_range() -> void:
	Settings.set_volume(&"Master", 5.0)
	assert_eq(Settings.get_volume(&"Master"), 1.0, "volume clamps to 1.0")
	Settings.set_volume(&"Master", -1.0)
	assert_eq(Settings.get_volume(&"Master"), 0.0, "volume clamps to 0.0 (mute)")

func test_screen_shake_scale_scales_baseline_intensity() -> void:
	Settings.set_screen_shake_scale(0.0)
	assert_eq(GameSettings.screen_shake.intensity_multiplier, 0.0, "0% shake -> zero intensity")

func test_render_scale_clamps() -> void:
	Settings.set_render_scale(99.0)
	assert_eq(Settings.render_scale, Settings.RENDER_SCALE_MAX, "render scale clamps to max")

func test_hitstop_toggle() -> void:
	Settings.set_hitstop_enabled(false)
	assert_false(Settings.hitstop_enabled, "hitstop can be disabled (player immune to freeze-frame slow)")
	Settings.set_hitstop_enabled(true)
	assert_true(Settings.hitstop_enabled, "hitstop can be re-enabled")

func test_tts_default_off_and_toggles() -> void:
	# OFF by default (the accessibility requirement): a fresh Settings (var default, no cfg load) is off.
	var fresh = load("res://managers/Settings.gd").new()
	assert_false(fresh.tts_enabled, "Text-to-Speech is OFF by default")
	fresh.free()
	# Round-trips through the live setter (restored to off so the suite leaves it at the default).
	Settings.set_tts_enabled(true)
	assert_true(Settings.tts_enabled, "TTS can be enabled")
	Settings.set_tts_enabled(false)
	assert_false(Settings.tts_enabled, "TTS can be disabled")
