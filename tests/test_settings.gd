extends GutTest
## Smoke + clamp tests for the Settings autoload (the user-facing options + persistence layer).
## Persistence is disabled per-test (Settings._loaded = false makes save_settings a no-op) so these
## NEVER write the real user://settings.cfg, and the live GameSettings fields the setters write through
## to are captured + restored so we don't pollute the camera/shake suites.

var _fov: float
var _sens: float
var _shake: float
var _music_folder: String

func before_each() -> void:
	_fov = GameSettings.camera.default_fov
	_sens = GameSettings.camera.mouse_sensitivity
	_shake = GameSettings.screen_shake.intensity_multiplier
	_music_folder = Settings.music_folder
	Settings._loaded = false  # disable persistence for the duration of the test

func after_each() -> void:
	GameSettings.camera.default_fov = _fov
	GameSettings.camera.mouse_sensitivity = _sens
	GameSettings.screen_shake.intensity_multiplier = _shake
	Settings.music_folder = _music_folder
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

func test_screen_flash_default_on_and_toggles() -> void:
	# ON by default (the suppression is opt-IN, like the heartbeat): a fresh Settings (var default, no cfg) is on,
	# so the authored hurt/dash/kill flashes fire until a photosensitive player disables them in Accessibility.
	var fresh = load("res://managers/Settings.gd").new()
	assert_true(fresh.screen_flash_enabled, "the full-screen flashes are ON by default (the toggle only SUPPRESSES them)")
	fresh.free()
	# Round-trips through the live setter PlayerHud.flash_* / StarSky.flash_kill poll at fire time.
	Settings.set_screen_flash_enabled(false)
	assert_false(Settings.screen_flash_enabled, "the full-screen flashes can be suppressed")
	Settings.set_screen_flash_enabled(true)
	assert_true(Settings.screen_flash_enabled, "the full-screen flashes can be re-enabled")

func test_music_folder_default_blank_and_round_trips() -> void:
	# Blank by default (a fresh Settings, no cfg) -> radios use their own curated res:// folders.
	var fresh = load("res://managers/Settings.gd").new()
	assert_eq(fresh.music_folder, "", "the player music-folder override is blank by default")
	fresh.free()
	Settings.set_music_folder("user://my_tunes")
	assert_eq(Settings.music_folder, "user://my_tunes", "set_music_folder stores the path")
	Settings.set_music_folder("  user://padded  ")
	assert_eq(Settings.music_folder, "user://padded", "set_music_folder trims surrounding whitespace")
	Settings.set_music_folder("")
	assert_eq(Settings.music_folder, "", "set_music_folder('') clears the override back to the per-radio default")

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

func test_heartbeat_default_on_and_toggles() -> void:
	# ON by default (the silence is opt-IN, the inverse of tts): a fresh Settings (var default, no cfg) is on.
	var fresh = load("res://managers/Settings.gd").new()
	assert_true(fresh.heartbeat_enabled, "the low-HP heartbeat is ON by default (the toggle only SILENCES it)")
	fresh.free()
	# Round-trips through the live setter the player polls each frame in _update_low_hp.
	Settings.set_heartbeat_enabled(false)
	assert_false(Settings.heartbeat_enabled, "the heartbeat pulse can be silenced")
	Settings.set_heartbeat_enabled(true)
	assert_true(Settings.heartbeat_enabled, "the heartbeat pulse can be re-enabled")

func test_ps1_warp_intensity_default_full_and_clamps() -> void:
	# FULL (1.0) by default — a fresh Settings (var default, no cfg) leaves the authored PS1 warp unscaled
	# until a player dials the Options -> Accessibility slider down (motion comfort).
	var fresh = load("res://managers/Settings.gd").new()
	assert_eq(fresh.ps1_warp_intensity, 1.0, "PS1 vertex-warp intensity defaults to 100% (full authored effect)")
	fresh.free()
	# Round-trips + clamps through the live setter PS1Applier polls each frame.
	Settings.set_ps1_warp_intensity(2.0)
	assert_eq(Settings.ps1_warp_intensity, 1.0, "intensity clamps to 100%")
	Settings.set_ps1_warp_intensity(-1.0)
	assert_eq(Settings.ps1_warp_intensity, 0.0, "intensity clamps to 0% (warp off)")
	Settings.set_ps1_warp_intensity(0.5)
	assert_eq(Settings.ps1_warp_intensity, 0.5, "an in-range intensity is stored verbatim")
	Settings.set_ps1_warp_intensity(1.0)  # restore the default so the suite leaves it unscaled


## The three minimap rows (Options -> Accessibility). ALL THREE are polled live — there is deliberately no
## apply_all entry — so the only contract here is default + clamp + round-trip. A bare Settings.new() is used
## for the defaults because the autoload's _ready has already loaded user://settings.cfg, which would report
## whatever this machine last saved rather than the shipped default.
func test_minimap_defaults() -> void:
	var fresh = load("res://managers/Settings.gd").new()
	assert_true(fresh.minimap_enabled, "the minimap ships ON — it is the shipped HUD, not an opt-in")
	assert_true(fresh.minimap_rotates, "heading-up is the shipped mode (the plan turns under a fixed caret)")
	assert_eq(fresh.minimap_zoom, 1.0, "zoom ships at 1x = GameSettings.hud.minimap_world_span verbatim")
	assert_true(fresh.minimap_show_npcs, "NPC dots ship visible")
	fresh.free()

func test_minimap_zoom_clamps() -> void:
	Settings.set_minimap_zoom(9.0)
	assert_almost_eq(Settings.minimap_zoom, Settings.MINIMAP_ZOOM_MAX, 0.0001, "zoom clamps to MINIMAP_ZOOM_MAX")
	Settings.set_minimap_zoom(0.0)
	assert_almost_eq(Settings.minimap_zoom, Settings.MINIMAP_ZOOM_MIN, 0.0001, "zoom clamps to MINIMAP_ZOOM_MIN")
	Settings.set_minimap_zoom(1.5)
	assert_almost_eq(Settings.minimap_zoom, 1.5, 0.0001, "an in-range zoom is stored verbatim")
	assert_lt(Settings.MINIMAP_ZOOM_MIN, Settings.MINIMAP_ZOOM_MAX, "the range is the right way round")
	Settings.set_minimap_zoom(1.0)  # restore the default so the suite leaves the HUD unzoomed

func test_minimap_toggles_round_trip() -> void:
	Settings.set_minimap_enabled(false)
	assert_false(Settings.minimap_enabled, "the map can be turned off")
	Settings.set_minimap_enabled(true)
	assert_true(Settings.minimap_enabled, "...and back on")
	Settings.set_minimap_rotates(false)
	assert_false(Settings.minimap_rotates, "north-up is reachable")
	Settings.set_minimap_rotates(true)
	assert_true(Settings.minimap_rotates, "...and heading-up restores")
	Settings.set_minimap_show_npcs(false)
	assert_false(Settings.minimap_show_npcs, "NPC dots can be switched off — it is a real gameplay affordance")
	Settings.set_minimap_show_npcs(true)
	assert_true(Settings.minimap_show_npcs, "...and back on")
