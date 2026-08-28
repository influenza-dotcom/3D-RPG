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
	Settings.set_mouse_sensitivity(0.0)
	assert_eq(Settings.mouse_sensitivity, Settings.SENS_MIN, "sensitivity clamps to min (0 would freeze the look)")
	Settings.set_mouse_sensitivity(_sens)  # restore the live camera value (after_each restores GameSettings too)


# --- Mouse look: radians per SCREEN pixel -------------------------------------------------------------------
# MouseInput reads InputEventMouseMotion.screen_relative (raw OS pixels), never `relative`, which the project's
# `viewport` stretch mode pre-scales by canvas/window width (792/1920 = 0.41 in 1080p fullscreen, 792/1280 = 0.62
# in a 720p window) — so the OLD 0.002 default turned the view 1.5x further the moment the game went windowed. The
# whole sensitivity domain (design default, SENS_MIN/MAX, the catalog slider, and a saved cfg) moved to the new unit
# at the 1080p-fullscreen factor, so THAT setup feels exactly as it did. These pin the retune + the migration.

## The design default is the old canvas-px 0.002 re-expressed per screen pixel at 1080p fullscreen — a re-tune to
## any other number is a FEEL change and must be deliberate. CameraSettings.new() reads the script default (the live
## GameSettings.camera has already been overwritten by this machine's settings.cfg); a bare Settings seeds the same.
func test_mouse_sensitivity_default_is_the_1080p_fullscreen_retune() -> void:
	assert_almost_eq(Settings.LEGACY_MOUSE_SENS_SCALE, 792.0 / 1920.0, 0.000001,
		"the legacy factor is the 792 px canvas (396 viewport / 0.5 stretch scale) over the 1920 px 1080p fullscreen width")
	var cs := CameraSettings.new()
	assert_almost_eq(cs.mouse_sensitivity, 0.002 * Settings.LEGACY_MOUSE_SENS_SCALE, 0.000001,
		"CameraSettings.mouse_sensitivity must be 0.002 canvas-px x 792/1920 = 0.000825 rad per screen px, so 1080p fullscreen feels identical after the screen_relative switch")
	var fresh = load("res://managers/Settings.gd").new()
	assert_almost_eq(fresh.mouse_sensitivity, cs.mouse_sensitivity, 0.000001,
		"a bare Settings seeds the same default as CameraSettings (the field default only matters off-tree, but it must not drift)")
	fresh.free()
	cs = null

## SENS_MIN..SENS_MAX brackets the default and is the SAME range the catalog slider carries: OptionsMenu's SENSITIVITY
## readout remaps SENS_MIN..SENS_MAX onto 1..100, so a .tres range that drifted from the constants would label the
## slider's left end "37" (or clamp the row short of the constants). The default also has to sit ON the step grid —
## Range snaps every value to min + n*step, so an off-grid default would move the moment the slider is touched.
func test_mouse_sensitivity_range_matches_the_catalog_slider() -> void:
	var def: float = CameraSettings.new().mouse_sensitivity
	assert_lt(Settings.SENS_MIN, Settings.SENS_MAX, "the range is the right way round")
	assert_lt(Settings.SENS_MIN, def, "the design default sits above the slider floor")
	assert_gt(Settings.SENS_MAX, def, "the design default sits below the slider ceiling")
	var readout := int(round(remap(def, Settings.SENS_MIN, Settings.SENS_MAX, 1.0, 100.0)))
	assert_eq(readout, 17,
		"the default must still read '17' on the 1..100 slider — the old range 0.0005..0.01 put 0.002 there, and the retune shifted both ends by the same factor")
	var cat := load("res://resources/settings/SettingsCatalog.tres") as SettingsCatalog
	assert_not_null(cat, "the settings catalog must load")
	if cat == null:
		return
	var found: SettingSpec = null
	for spec in cat.specs:
		if spec.key == &"mouse_sensitivity":
			found = spec
			break
	assert_not_null(found, "Options -> Game must carry the 'Mouse Sensitivity' row")
	if found == null:
		return
	assert_almost_eq(found.min_value, Settings.SENS_MIN, 0.0000001,
		"the catalog slider floor must equal Settings.SENS_MIN (the readout remap + the setter clamp assume it)")
	assert_almost_eq(found.max_value, Settings.SENS_MAX, 0.0000001,
		"the catalog slider ceiling must equal Settings.SENS_MAX")
	assert_gt(found.step, 0.0, "the slider needs a positive step")
	var steps: float = (def - found.min_value) / found.step
	assert_almost_eq(steps, round(steps), 0.001,
		"the design default must lie on the slider's step grid (min + n*step), or the row snaps it to a neighbour the first time it is dragged")

## A settings.cfg from before the switch carries the OLD key in canvas-px units; it is rescaled ONCE by the 1080p
## factor so a returning player's look is unchanged (not ~2.4x faster). The new key wins verbatim; neither = fallback.
## Driven through the pure static rule with an in-memory ConfigFile so the real user://settings.cfg is never touched.
func test_mouse_sensitivity_legacy_cfg_value_is_rescaled_once_on_load() -> void:
	assert_ne(Settings.MOUSE_SENS_KEY, Settings.MOUSE_SENS_LEGACY_KEY,
		"the unit change re-keyed the row — same key would make the rescale compound on every boot")
	var legacy := ConfigFile.new()
	legacy.set_value("input", Settings.MOUSE_SENS_LEGACY_KEY, 0.002)  # the old shipped default, canvas-px units
	assert_almost_eq(Settings.read_mouse_sensitivity(legacy, 9.0), 0.002 * Settings.LEGACY_MOUSE_SENS_SCALE, 0.000001,
		"a legacy 0.002 must load as 0.000825 rad per screen px — the same 1080p-fullscreen feel, not 2.4x faster")
	assert_almost_eq(Settings.read_mouse_sensitivity(legacy, 9.0), CameraSettings.new().mouse_sensitivity, 0.000001,
		"...which is exactly the new design default, so a returning player and a new one feel the same")
	# The old ceiling rescales to ~3% over SENS_MAX; load_settings clamps (mirrors contrast / ps1_warp_intensity).
	legacy.set_value("input", Settings.MOUSE_SENS_LEGACY_KEY, 0.01)
	var top := clampf(Settings.read_mouse_sensitivity(legacy, 9.0), Settings.SENS_MIN, Settings.SENS_MAX)
	assert_almost_eq(top, Settings.SENS_MAX, 0.0000001, "a legacy value at the old slider ceiling lands on the new ceiling")
	# The new key wins verbatim, even beside a stale old key (a build that wrote both would still read the right unit).
	var current := ConfigFile.new()
	current.set_value("input", Settings.MOUSE_SENS_LEGACY_KEY, 0.002)
	current.set_value("input", Settings.MOUSE_SENS_KEY, 0.003)
	assert_almost_eq(Settings.read_mouse_sensitivity(current, 9.0), 0.003, 0.000001,
		"the screen-px key is authoritative and is NOT rescaled")
	var empty := ConfigFile.new()
	assert_almost_eq(Settings.read_mouse_sensitivity(empty, 0.000825), 0.000825, 0.000001,
		"no key at all -> the fallback (the design default seeded in _ready)")

## save_settings must persist ONLY the new key: writing the legacy key again would hand the next boot a screen-px
## number to rescale as canvas-px (2.4x slower every launch). Source-text pin: save_settings writes the real
## user://settings.cfg, so it is never invoked under GUT.
func test_mouse_sensitivity_persists_under_the_screen_key_only() -> void:
	var src := FileAccess.get_file_as_string("res://managers/Settings.gd")
	assert_true(src.contains('cfg.set_value("input", MOUSE_SENS_KEY, mouse_sensitivity)'),
		"save_settings must write mouse_sensitivity under MOUSE_SENS_KEY (screen-px units)")
	assert_false(src.contains('cfg.set_value("input", MOUSE_SENS_LEGACY_KEY'),
		"save_settings must never write the legacy key — read_mouse_sensitivity would rescale it again next boot")
	assert_false(src.contains('cfg.set_value("input", "mouse_sensitivity"'),
		"...nor its literal spelling")
	assert_true(src.contains("read_mouse_sensitivity(cfg, mouse_sensitivity)"),
		"load_settings must go through the pure migration rule, not a bare get_value on either key")

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


# --- Presentation: native-res HIGH FIDELITY vs the classic ~792x444 RETRO pixel pipeline --------------------

## The shipped default is HIGH FIDELITY. A bare instance never runs _ready, so this pins the var default; the
## _ready seeding rule (render_scale forced to 1.0 under the HIGH FIDELITY default, because project.godot's
## scaling_3d/scale 2.0 is the RETRO-buffer supersample and would mean 4K-on-1080p 3D) is pinned as source text
## below — a live-autoload assertion would just read back this machine's settings.cfg.
func test_presentation_defaults_high_fidelity() -> void:
	var fresh = load("res://managers/Settings.gd").new()
	assert_eq(fresh.presentation, Settings.PRESENTATION_HIGH_FIDELITY, "a fresh Settings defaults to High Fidelity")
	fresh.free()

func test_set_presentation_clamps_and_round_trips() -> void:
	var before: int = Settings.presentation
	Settings.set_presentation(99)
	assert_eq(Settings.presentation, Settings.PRESENTATION_COUNT - 1, "presentation clamps to the last real mode")
	Settings.set_presentation(-5)
	assert_eq(Settings.presentation, 0, "presentation clamps to the first mode")
	Settings.set_presentation(Settings.PRESENTATION_RETRO)
	assert_eq(Settings.presentation, Settings.PRESENTATION_RETRO, "Retro is selectable")
	Settings.set_presentation(before)  # restore the live mode (persistence is off via _loaded, but the window is real)

## A settings.cfg from before the presentation split carries no "presentation" key; its render_scale was a
## supersample of the RETRO buffer (typically the old 2.0 default) and must NOT be re-read against a native
## target — the era migration hands such a cfg HIGH FIDELITY at render_scale 1.0, exactly once (save_settings
## always writes the key afterwards). Driven through the pure static rule with an in-memory ConfigFile so the
## real user://settings.cfg is never touched.
func test_presentation_era_migration_resets_render_scale_once() -> void:
	var old_era := ConfigFile.new()
	old_era.set_value("video", "render_scale", 2.0)  # the old shipped default, RETRO-buffer units
	var migrated: Dictionary = Settings.read_presentation(old_era, Settings.PRESENTATION_RETRO, 9.0)
	assert_eq(int(migrated["presentation"]), Settings.PRESENTATION_HIGH_FIDELITY,
		"a pre-presentation cfg gets the new shipped look")
	assert_almost_eq(float(migrated["render_scale"]), 1.0, 0.000001,
		"...and its RETRO-era render_scale is reset to 1.0 — 2.0 of a native target is 4K-on-1080p 3D")
	var keyed := ConfigFile.new()
	keyed.set_value("video", "presentation", Settings.PRESENTATION_RETRO)
	keyed.set_value("video", "render_scale", 1.5)
	var kept: Dictionary = Settings.read_presentation(keyed, Settings.PRESENTATION_HIGH_FIDELITY, 9.0)
	assert_eq(int(kept["presentation"]), Settings.PRESENTATION_RETRO, "a keyed cfg's mode is read verbatim")
	assert_almost_eq(float(kept["render_scale"]), 1.5, 0.000001, "...and its render_scale survives untouched")
	var empty := ConfigFile.new()
	var fresh_install: Dictionary = Settings.read_presentation(empty, Settings.PRESENTATION_RETRO, 2.0)
	assert_eq(int(fresh_install["presentation"]), Settings.PRESENTATION_HIGH_FIDELITY,
		"an empty cfg (fresh install reading an empty file) also lands on the shipped default")

## Source-text pins (save_settings writes the real user://settings.cfg, so it is never invoked under GUT):
## the presentation key must ALWAYS be written — its presence is what makes the era migration one-shot — and
## both the loader and the _ready seed must go through/respect the presentation-aware rules.
func test_presentation_persists_and_loads_through_the_pure_rule() -> void:
	var src := FileAccess.get_file_as_string("res://managers/Settings.gd")
	assert_true(src.contains('cfg.set_value("video", "presentation", presentation)'),
		"save_settings must write the presentation key on every save")
	assert_true(src.contains("read_presentation(cfg, presentation, render_scale)"),
		"load_settings must go through the pure era-migration rule, not a bare get_value pair")
	assert_true(src.contains("if presentation == PRESENTATION_HIGH_FIDELITY:\n\t\trender_scale = 1.0"),
		"_ready must re-seed render_scale to 1.0 under the HIGH FIDELITY default — load_settings early-returns on a fresh install, so only the seed protects first boot")

## native_scale()/render_size() are the unit-converter seam every pixel-unit effect reads live per frame.
## Off-tree there is no window, so both must degrade to the RETRO identity — GUT drives effect params (e.g.
## InkOutline._params) off-tree, and a null-window crash here would redden every one of those suites.
func test_native_scale_degrades_to_retro_identity_off_tree() -> void:
	var fresh = load("res://managers/Settings.gd").new()
	assert_almost_eq(fresh.native_scale(), 1.0, 0.000001, "no window -> 1.0 (canvas px ARE render px)")
	assert_eq(fresh.render_size(), Vector2i(792, 444), "no window -> the 16:9 logical canvas fallback")
	fresh.free()

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
	assert_eq(fresh.map_zoom, 1.0, "the MAP TAB ships at 1x = GameSettings.hud.map_world_span verbatim")
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

## The MAP TAB's zoom is its OWN stored value on the SHARED clamp — the two maps are the same widget at two
## sizes, so one range describes both, but scrolling the page-sized map must never move the corner box (they
## divide different spans: map_world_span vs minimap_world_span).
func test_map_zoom_clamps_and_is_independent_of_the_minimap_row() -> void:
	var was_minimap: float = Settings.minimap_zoom
	Settings.set_map_zoom(9.0)
	assert_almost_eq(Settings.map_zoom, Settings.MINIMAP_ZOOM_MAX, 0.0001, "map zoom clamps to the shared MAX")
	Settings.set_map_zoom(0.0)
	assert_almost_eq(Settings.map_zoom, Settings.MINIMAP_ZOOM_MIN, 0.0001, "map zoom clamps to the shared MIN")
	Settings.set_map_zoom(2.0)
	assert_almost_eq(Settings.map_zoom, 2.0, 0.0001, "an in-range map zoom is stored verbatim")
	assert_almost_eq(Settings.minimap_zoom, was_minimap, 0.0001,
		"...and moving the MAP's zoom leaves the HUD minimap's row untouched — a shared field would make scrolling the map re-zoom the corner box")
	Settings.set_map_zoom(1.0)  # restore the default so the suite leaves the map unzoomed

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
	Settings.set_minimap_show_stations(false)
	assert_false(Settings.minimap_show_stations, "station glyphs can be switched off — a busy market is a lot of glyphs on a 108 px box")
	Settings.set_minimap_show_stations(true)
	assert_true(Settings.minimap_show_stations, "...and back on")

## The station row ships ON: a shop is a fixture, not a body, so knowing one is there leaks no tactical
## information — it is a DECLUTTER row, not a difficulty one (unlike minimap_show_npcs beside it).
func test_minimap_station_row_ships_on() -> void:
	var fresh = load("res://managers/Settings.gd").new()
	assert_true(fresh.minimap_show_stations, "stations are marked by default")
	fresh.free()

## The catalog row has to EXIST and point at the real getter/setter pair, or the toggle above is unreachable
## from Options (the tests/test_hud_clock.gd catalog-row idiom).
func test_minimap_station_row_is_in_the_options_catalog() -> void:
	var cat := load("res://resources/settings/SettingsCatalog.tres") as SettingsCatalog
	assert_not_null(cat, "the settings catalog must load")
	if cat == null:
		return
	var found: SettingSpec = null
	for spec in cat.specs:
		if spec.key == &"minimap_stations":
			found = spec
			break
	assert_not_null(found, "Options -> Accessibility must carry a 'Stations On Minimap' row")
	if found == null:
		return
	assert_eq(found.tab, &"Accessibility", "it belongs beside the rest of the declutter family")
	assert_eq(found.getter, &"minimap_show_stations", "bound to the Settings field")
	assert_eq(found.setter, &"set_minimap_show_stations", "...and to its setter")
	assert_false(found.label.is_empty(), "a row with no label is an invisible row")

func test_clock_defaults() -> void:
	var fresh = load("res://managers/Settings.gd").new()
	assert_true(fresh.clock_enabled,
		"the HUD clock ships ON — the day/night cycle's lighting is otherwise the only time signal, and it is a poor instrument (the moon keeps midnight legible, interiors are lit around the clock)")
	assert_true(fresh.clock_24_hour, "24-hour is the shipped face")
	fresh.free()

func test_clock_toggles_round_trip() -> void:
	Settings.set_clock_enabled(false)
	assert_false(Settings.clock_enabled, "the clock can be turned off")
	Settings.set_clock_enabled(true)
	assert_true(Settings.clock_enabled, "...and back on")
	Settings.set_clock_24_hour(false)
	assert_false(Settings.clock_24_hour, "the 12-hour face is reachable")
	Settings.set_clock_24_hour(true)
	assert_true(Settings.clock_24_hour, "...and 24-hour restores")
