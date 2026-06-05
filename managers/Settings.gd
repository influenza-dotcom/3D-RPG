extends Node
## Settings — the player-facing OPTIONS layer + persistence. Distinct from GameSettings (the live
## gameplay-tuning registry of .tres resources): this autoload owns only what the Options menu can
## change and is responsible for SAVING those choices to user://settings.cfg and APPLYING each one to
## the right place — the Window/DisplayServer (video), the AudioServer buses (volume), and a few
## GameSettings.camera / .screen_shake fields (FOV, sensitivity, shake). It loads + applies on boot
## (before the main scene, since it's an autoload) so a returning player's choices are live immediately,
## and re-saves on every setter. Available from BOTH the start menu and in-game.
##
## Percentage/scale models are anchored to the AUTHORED design: at boot we capture each bus's layout dB
## and the shake/bob baselines, so a slider at 100% reproduces the mix the game shipped with rather than
## flattening it to 0 dB.

const CONFIG_PATH := "user://settings.cfg"

## Window-mode menu index -> Window.Mode. Order matches the Video tab dropdown.
const WINDOW_MODES: Array[int] = [
	Window.MODE_WINDOWED,             # 0 Windowed
	Window.MODE_FULLSCREEN,           # 1 Borderless fullscreen
	Window.MODE_EXCLUSIVE_FULLSCREEN, # 2 Exclusive fullscreen
]
## Resolution presets offered while in Windowed mode.
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160),
]
## Audio buses exposed as volume sliders, in display order. "Master" is the implicit bus 0.
const VOLUME_BUSES: Array[StringName] = [&"Master", &"music", &"sfx", &"ambient", &"voice"]

const FOV_MIN := 60.0
const FOV_MAX := 120.0
const RENDER_SCALE_MIN := 0.5
const RENDER_SCALE_MAX := 2.0
const SENS_MIN := 0.0005
const SENS_MAX := 0.01

# --- Stored settings (defaults; seeded from the live design then overwritten by load_settings) ---
var window_mode: int = 2                       ## index into WINDOW_MODES
var windowed_size: Vector2i = Vector2i(1280, 720)
var vsync: bool = false
var max_fps: int = 144
var render_scale: float = 2.0                  ## Viewport.scaling_3d_scale
var fov: float = 75.0                          ## -> GameSettings.camera.default_fov
var volumes: Dictionary = {}                   ## StringName bus -> float (0..1; 1.0 = authored level)
var mouse_sensitivity: float = 0.002           ## -> GameSettings.camera.mouse_sensitivity
var screen_shake_scale: float = 1.0            ## scales GameSettings.screen_shake.intensity_multiplier
var hitstop_enabled: bool = true               ## off = player immune to the freeze-frame slow (FreezeFrame reads this live)

# --- Captured baselines so percentage models preserve the authored design ---
var _base_bus_db: Dictionary = {}              ## bus -> dB from the loaded layout
var _base_shake_intensity: float = 1.0
var _loaded: bool = false

func _ready() -> void:
	_capture_baselines()
	# Seed stored fields from the live design defaults so a MISSING cfg reproduces the authored game.
	fov = GameSettings.camera.default_fov
	mouse_sensitivity = GameSettings.camera.mouse_sensitivity
	var win := get_window()
	if win != null:
		window_mode = _mode_to_index(win.mode)
		render_scale = win.scaling_3d_scale
	for bus in VOLUME_BUSES:
		volumes[bus] = 1.0
	load_settings()
	apply_all()

## Snapshot the engine/design values the percentage sliders scale FROM (run once, before any apply).
func _capture_baselines() -> void:
	for bus in VOLUME_BUSES:
		var idx := AudioServer.get_bus_index(bus)
		_base_bus_db[bus] = AudioServer.get_bus_volume_db(idx) if idx >= 0 else 0.0
	_base_shake_intensity = GameSettings.screen_shake.intensity_multiplier

# ---------------------------------------------------------------------------------------------------
# Apply
# ---------------------------------------------------------------------------------------------------

func apply_all() -> void:
	apply_video()
	apply_audio()
	apply_input()
	apply_accessibility()

func apply_video() -> void:
	var win := get_window()
	if win == null:
		return  # headless / no live window — nothing to size (settings still persist)
	var mode: int = WINDOW_MODES[clampi(window_mode, 0, WINDOW_MODES.size() - 1)]
	win.mode = mode
	if mode == Window.MODE_WINDOWED:
		win.size = windowed_size
		var screen_size := DisplayServer.screen_get_size(win.current_screen)
		if screen_size.x > 0 and screen_size.y > 0:
			win.position = (screen_size - windowed_size) / 2  # re-centre after a resize
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = max_fps
	win.scaling_3d_scale = render_scale
	GameSettings.camera.default_fov = fov

func apply_audio() -> void:
	for bus in VOLUME_BUSES:
		var idx := AudioServer.get_bus_index(bus)
		if idx < 0:
			continue
		var v: float = clampf(float(volumes.get(bus, 1.0)), 0.0, 1.0)
		AudioServer.set_bus_mute(idx, v <= 0.0)
		if v > 0.0:
			# Authored dB + the slider in dB: 100% = base, 50% ~ -6 dB, 0% = mute. Preserves the mix.
			AudioServer.set_bus_volume_db(idx, float(_base_bus_db[bus]) + linear_to_db(v))

func apply_input() -> void:
	GameSettings.camera.mouse_sensitivity = mouse_sensitivity

func apply_accessibility() -> void:
	GameSettings.screen_shake.intensity_multiplier = _base_shake_intensity * screen_shake_scale

# ---------------------------------------------------------------------------------------------------
# Setters — each applies immediately AND persists, so the menu is pure data-binding
# ---------------------------------------------------------------------------------------------------

func set_window_mode(index: int) -> void:
	window_mode = clampi(index, 0, WINDOW_MODES.size() - 1)
	apply_video()
	save_settings()

func set_windowed_size(size: Vector2i) -> void:
	windowed_size = size
	apply_video()
	save_settings()

func set_vsync(on: bool) -> void:
	vsync = on
	apply_video()
	save_settings()

func set_max_fps(n: int) -> void:
	max_fps = maxi(0, n)
	apply_video()
	save_settings()

func set_render_scale(f: float) -> void:
	render_scale = clampf(f, RENDER_SCALE_MIN, RENDER_SCALE_MAX)
	apply_video()
	save_settings()

func set_fov(f: float) -> void:
	fov = clampf(f, FOV_MIN, FOV_MAX)
	GameSettings.camera.default_fov = fov
	save_settings()

func set_volume(bus: StringName, v: float) -> void:
	volumes[bus] = clampf(v, 0.0, 1.0)
	apply_audio()
	save_settings()

func set_mouse_sensitivity(f: float) -> void:
	mouse_sensitivity = clampf(f, SENS_MIN, SENS_MAX)
	GameSettings.camera.mouse_sensitivity = mouse_sensitivity
	save_settings()

func set_screen_shake_scale(f: float) -> void:
	screen_shake_scale = clampf(f, 0.0, 2.0)
	apply_accessibility()
	save_settings()

func set_hitstop_enabled(on: bool) -> void:
	hitstop_enabled = on
	save_settings()

func get_volume(bus: StringName) -> float:
	return float(volumes.get(bus, 1.0))

# ---------------------------------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------------------------------

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		_loaded = true  # no file yet — keep the design defaults seeded in _ready
		return
	window_mode = int(cfg.get_value("video", "window_mode", window_mode))
	windowed_size = cfg.get_value("video", "windowed_size", windowed_size)
	vsync = bool(cfg.get_value("video", "vsync", vsync))
	max_fps = int(cfg.get_value("video", "max_fps", max_fps))
	render_scale = float(cfg.get_value("video", "render_scale", render_scale))
	fov = float(cfg.get_value("video", "fov", fov))
	for bus in VOLUME_BUSES:
		volumes[bus] = float(cfg.get_value("audio", String(bus), volumes.get(bus, 1.0)))
	mouse_sensitivity = float(cfg.get_value("input", "mouse_sensitivity", mouse_sensitivity))
	screen_shake_scale = float(cfg.get_value("accessibility", "screen_shake_scale", screen_shake_scale))
	hitstop_enabled = bool(cfg.get_value("accessibility", "hitstop_enabled", hitstop_enabled))
	_loaded = true

func save_settings() -> void:
	if not _loaded:
		return  # never clobber the file before load_settings has run
	var cfg := ConfigFile.new()
	cfg.set_value("video", "window_mode", window_mode)
	cfg.set_value("video", "windowed_size", windowed_size)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "max_fps", max_fps)
	cfg.set_value("video", "render_scale", render_scale)
	cfg.set_value("video", "fov", fov)
	for bus in VOLUME_BUSES:
		cfg.set_value("audio", String(bus), float(volumes.get(bus, 1.0)))
	cfg.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("accessibility", "screen_shake_scale", screen_shake_scale)
	cfg.set_value("accessibility", "hitstop_enabled", hitstop_enabled)
	cfg.save(CONFIG_PATH)

## Window.Mode -> our dropdown index (defaults to Exclusive Fullscreen if it's an unlisted mode).
func _mode_to_index(mode: int) -> int:
	var i := WINDOW_MODES.find(mode)
	return i if i >= 0 else 2
