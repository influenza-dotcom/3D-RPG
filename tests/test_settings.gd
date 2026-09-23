extends GutTest
## Tests for the Settings autoload (managers/Settings.gd): the player-facing Options layer + settings.cfg persistence.
##
## THREE WAYS SETTINGS IS DRIVEN HERE, and why each one:
##  - The LIVE autoload, for the clamps and the write-through into GameSettings. Persistence is switched off for the
##    test (Settings._loaded = false makes save_settings a no-op) and every live field a test moves is snapshotted in
##    before_each and put back in after_each. after_each hands persistence back in whatever state it found it
##    (normally ON), so a field left at a test value would be written into this machine's real user://settings.cfg by
##    the NEXT suite that calls any setter (how the dev's saved vertex warp got zeroed by a literal restore line).
##  - A one-line subclass of Settings.gd whose `config_path` seam points at a per-process scratch cfg (_settings_on_scratch_cfg,
##    the tests/test_color_quantization.gd idiom), for the save -> load round trips: the real save_settings and
##    load_settings run end to end and never go near the real file.
##  - A FRESH-INSTALL double (_fresh_install_double): a runtime subclass of the real script that overrides only the
##    three calls reaching outside the instance (load_settings on its no-cfg branch, apply_all, save_settings), so the
##    REAL _ready seeding runs off-tree the way a first boot runs it. The shipped-default pins read that boot, not a
##    bare .new() that never ran _ready.

const SETTINGS_PATH := "res://managers/Settings.gd"
const CATALOG_PATH := "res://resources/settings/SettingsCatalog.tres"
## Plain live-autoload fields the tests below move (directly or through a setter), restored verbatim in after_each.
## render_scale / presentation / the Master volume are restored through their setters instead, because each one
## also re-applies to the live window or audio bus.
const RESTORED_FIELDS: Array[StringName] = [
	&"fov", &"mouse_sensitivity", &"screen_shake_scale", &"ps1_warp_intensity", &"minimap_zoom", &"map_zoom",
	&"music_folder", &"debug_skip_menu", &"debug_always_show_tos",
]

var _fov: float
var _sens: float
var _shake: float
var _fields: Dictionary = {}
var _render_scale: float
var _presentation: int
var _master_volume: float
var _was_loaded: bool
## Where the round-trip tests' recompiled Settings saves. Per process, so two concurrent GUT runs never share it.
var _scratch_cfg := ""

func before_each() -> void:
	_fov = GameSettings.camera.default_fov
	_sens = GameSettings.camera.mouse_sensitivity
	_shake = GameSettings.screen_shake.intensity_multiplier
	_fields.clear()
	for field in RESTORED_FIELDS:
		_fields[field] = Settings.get(field)
	_render_scale = Settings.render_scale
	_presentation = Settings.presentation
	_master_volume = Settings.get_volume(&"Master")
	_was_loaded = Settings._loaded
	Settings._loaded = false  # disable persistence for the duration of the test
	_scratch_cfg = "user://gut_settings_round_trip_%d.cfg" % OS.get_process_id()

func after_each() -> void:
	# Setter restores first, while persistence is still off: each re-applies to the live window / audio bus.
	if Settings.presentation != _presentation:
		Settings.set_presentation(_presentation)
	if not is_equal_approx(Settings.render_scale, _render_scale):
		Settings.set_render_scale(_render_scale)
	if not is_equal_approx(Settings.get_volume(&"Master"), _master_volume):
		Settings.set_volume(&"Master", _master_volume)
	for field in _fields:
		Settings.set(field, _fields[field])
	GameSettings.camera.default_fov = _fov
	GameSettings.camera.mouse_sensitivity = _sens
	GameSettings.screen_shake.intensity_multiplier = _shake
	Settings._loaded = _was_loaded
	_remove_scratch_cfg()


func _remove_scratch_cfg() -> void:
	if not _scratch_cfg.is_empty() and FileAccess.file_exists(_scratch_cfg):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_scratch_cfg))

## The SettingsCatalog row whose key is `key`, or null (and the test failed) when the catalog or the row is missing.
func _catalog_spec(key: StringName) -> SettingSpec:
	var cat := load(CATALOG_PATH) as SettingsCatalog
	assert_true(cat != null, "the settings catalog must load")
	if cat == null:
		return null
	for spec in cat.specs:
		if spec.key == key:
			return spec
	fail_test("Options must carry a '%s' row in SettingsCatalog.tres" % key)
	return null

## The REAL managers/Settings.gd with its `config_path` seam pointed at the scratch cfg, so save_settings
## and load_settings run for real without touching this machine's user://settings.cfg. A one-line subclass sets the seam in _init, so every
## `.new()` a test makes is already redirected; the safety check is that an instance really reports the
## scratch path before any test is allowed to save through it — anything less returns null.
func _settings_on_scratch_cfg() -> GDScript:
	var surrogate := GDScript.new()
	surrogate.source_code = "extends \"%s\"

func _init() -> void:
	config_path = \"%s\"
" % [SETTINGS_PATH, _scratch_cfg]
	var err := surrogate.reload()
	assert_eq(err, OK, "the redirecting subclass of Settings.gd compiles")
	if err != OK:
		return null
	var check: Node = surrogate.new()
	var redirected := String(check.config_path)
	check.free()
	assert_eq(redirected, _scratch_cfg, "the surrogate saves to the scratch cfg, never to user://settings.cfg")
	if redirected != _scratch_cfg:
		return null
	return surrogate

## An UNBOOTED Settings exactly as a first launch meets it: the real script, with load_settings reduced to what it
## does when no settings.cfg exists yet (mark loaded, keep the seeded defaults), and apply_all / save_settings made
## inert so the boot neither pushes into the live AudioServer / GameSettings / TranslationServer nor writes the real
## user://settings.cfg. The caller runs _ready() (after staging any pre-boot state) and frees it.
func _fresh_install_double() -> Node:
	var script := GDScript.new()
	script.source_code = ("extends \"%s\"\n\nfunc load_settings() -> void:\n\t_loaded = true\n\n"
		+ "func apply_all() -> void:\n\tpass\n\nfunc save_settings() -> void:\n\tpass\n") % SETTINGS_PATH
	var err := script.reload()
	assert_eq(err, OK, "the fresh-install double (a subclass of the real Settings.gd) compiles")
	if err != OK:
		return null
	return script.new()


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
# The design DEFAULT then moved AGAIN on 08-31 (0.000825 -> 0.00115, the playtest feel snapped to the slider grid);
# the unit, the range constants and the legacy migration below were all left untouched by that second move.

## SHIP DECISION, stated as the relation it came from: the default look speed is the 08-31 playtest feel — a legacy
## 0.0028 canvas-px value re-expressed per screen pixel at 1080p fullscreen (x 792 canvas px / 1920 screen px =
## 0.001155) — snapped DOWN onto the catalog slider's step grid (Range snaps every value to min + n*step, so an
## off-grid default would move the first time the slider is dragged; the on-grid check lives in the catalog test
## below). The step comes from SettingsCatalog.tres, so a slider re-grid demands a re-snapped default. The design
## owner is CameraSettings' script default (the live GameSettings.camera has already been overwritten by this
## machine's settings.cfg), and Settings' own field seed must agree with it.
func test_mouse_sensitivity_default_is_the_playtest_retune_snapped_to_grid() -> void:
	var cs := CameraSettings.new()
	var design: float = cs.mouse_sensitivity
	cs = null
	var fresh = load(SETTINGS_PATH).new()
	var settings_seed: float = fresh.mouse_sensitivity
	fresh.free()
	assert_almost_eq(settings_seed, design, 0.0000001,
		"a bare Settings seeds the same default as CameraSettings — the off-tree seed and the design owner must not drift apart")
	var row := _catalog_spec(&"mouse_sensitivity")
	if row == null:
		return
	var playtest_feel := 0.0028 * 792.0 / 1920.0
	assert_between(design, playtest_feel - row.step, playtest_feel,
		"the default look speed must be the 08-31 playtest feel (0.0028 canvas px at 1080p = %.7f rad per screen px) snapped DOWN by less than one %.6f slider step; got %.7f" % [playtest_feel, row.step, design])

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
	assert_eq(readout, 26,
		"the 08-31 default 0.00115 must read '26' on the 1..100 slider (remap over SENS_MIN..SENS_MAX lands at 25.75 and the readout rounds) — the pre-retune 0.000825 read '17'; a drift here means the default or the range moved without the other")
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
## Every expected number is worked from the historical setup (792 canvas px across a 1920 px 1080p screen), never
## from Settings.LEGACY_MOUSE_SENS_SCALE, so a wrong factor in the constant fails here.
func test_mouse_sensitivity_legacy_cfg_value_is_rescaled_once_on_load() -> void:
	assert_ne(Settings.MOUSE_SENS_KEY, Settings.MOUSE_SENS_LEGACY_KEY,
		"the unit change re-keyed the row — same key would make the rescale compound on every boot")
	var legacy := ConfigFile.new()
	legacy.set_value("input", Settings.MOUSE_SENS_LEGACY_KEY, 0.002)  # the old shipped default, canvas-px units
	assert_almost_eq(Settings.read_mouse_sensitivity(legacy, 9.0), 0.000825, 0.0000001,
		"a legacy 0.002 canvas px must load as 0.000825 rad per screen px (0.002 x 792/1920) — the same 1080p-fullscreen feel, not 2.4x faster")
	# NOTE: a migrated legacy 0.002 used to land EXACTLY on the design default; the 08-31 default retune
	# (0.000825 -> 0.00115) broke that identity ON PURPOSE — the migration preserves the RETURNING player's
	# feel verbatim, it does not chase the fresh-install default. Do not re-add an equality pin here.
	# The new SENS range IS the old canvas-px slider range (0.0005..0.01) re-expressed through the same rule and
	# rounded, so both slider ends still mean what they meant. load_settings clamps the ~3% ceiling overshoot; that
	# clamp is driven through a real load in test_a_legacy_settings_cfg_migrates_once_and_later_choices_stick.
	legacy.set_value("input", Settings.MOUSE_SENS_LEGACY_KEY, 0.0005)
	var old_floor: float = Settings.read_mouse_sensitivity(legacy, 9.0)
	legacy.set_value("input", Settings.MOUSE_SENS_LEGACY_KEY, 0.01)
	var old_ceiling: float = Settings.read_mouse_sensitivity(legacy, 9.0)
	assert_almost_eq(old_floor / Settings.SENS_MIN, 1.0, 0.05,
		"SENS_MIN is the old 0.0005 slider floor in screen-px units (rounded) — a returning player's slowest setting still exists")
	assert_almost_eq(old_ceiling / Settings.SENS_MAX, 1.0, 0.05,
		"SENS_MAX is the old 0.01 slider ceiling in screen-px units (rounded) — a returning player's fastest setting still exists")
	# The new key wins verbatim, even beside a stale old key (a build that wrote both would still read the right unit).
	var current := ConfigFile.new()
	current.set_value("input", Settings.MOUSE_SENS_LEGACY_KEY, 0.002)
	current.set_value("input", Settings.MOUSE_SENS_KEY, 0.003)
	assert_almost_eq(Settings.read_mouse_sensitivity(current, 9.0), 0.003, 0.000001,
		"the screen-px key is authoritative and is NOT rescaled")
	var empty := ConfigFile.new()
	assert_almost_eq(Settings.read_mouse_sensitivity(empty, 0.00115), 0.00115, 0.000001,
		"no key at all -> the fallback (the design default seeded in _ready)")

## THE GAME ALWAYS STARTS IN FIRST PERSON. `third_person_camera` is the one field on this autoload that is
## deliberately NOT persisted — it is absent from both save_settings and load_settings — so a session that ends
## pulled out still boots at the eye. Pinned through the REAL save/load pair on the scratch cfg, from both ends:
## a live third-person session must not write the mode, and a hand-edited cfg claiming it must not restore it
## (which is what makes the rule hold against an older cfg, or a player who edits the file).
func test_third_person_never_survives_a_restart() -> void:
	var surrogate := _settings_on_scratch_cfg()
	if surrogate == null:
		return
	var playing = surrogate.new()
	playing.load_settings()  # no cfg yet: seeded defaults, _loaded true so the save below is allowed
	assert_false(playing.third_person_camera, "precondition: a fresh install starts in first person")
	playing.set_third_person_camera(true)
	assert_true(playing.third_person_camera, "the live session IS in third person")
	playing.save_settings()  # whatever the player changes next re-writes the whole file
	playing.free()

	var written := ConfigFile.new()
	assert_eq(written.load(_scratch_cfg), OK, "save_settings wrote a cfg")
	assert_false(written.has_section_key("accessibility", "third_person_camera"),
		"the saved cfg must carry NO third-person key — a mode is not a preference to restore (see save_settings)")

	# ...and the other end: even a cfg that claims third person (an older build's file, or a hand edit) boots at
	# the eye, because load_settings never reads the key.
	written.set_value("accessibility", "third_person_camera", true)
	assert_eq(written.save(_scratch_cfg), OK, "staged a cfg that asks for third person")
	var booted = surrogate.new()
	booted.load_settings()
	assert_false(booted.third_person_camera, "a cfg asking for third person must still boot in FIRST person")
	# The camera DISTANCE is a framing preference and does keep persisting — the two must not be confused.
	assert_true(booted.third_person_distance > 0.0, "the distance setting is still loaded (it IS persisted)")
	booted.free()


## Both unit migrations, through the REAL load_settings and save_settings (the recompiled Settings on a scratch cfg).
## A cfg from before both switches carries the OLD mouse key in canvas px and a RETRO-era render_scale with no
## presentation key. Each migration must run exactly ONCE: the first boot converts, the save that follows stores the
## converted values in a shape the next boot reads verbatim, and a choice the player makes afterwards survives a
## restart instead of being "migrated" back. A save that re-wrote the legacy key would slow the look 2.4x per launch;
## a save that dropped the presentation key would reset every Retro player to High Fidelity at 1.0 on each boot.
func test_a_legacy_settings_cfg_migrates_once_and_later_choices_stick() -> void:
	var surrogate := _settings_on_scratch_cfg()
	if surrogate == null:
		return
	var old := ConfigFile.new()
	old.set_value("input", Settings.MOUSE_SENS_LEGACY_KEY, 0.002)  # the old shipped default, canvas px
	old.set_value("video", "render_scale", 2.0)  # the old shipped RETRO supersample, no presentation key
	assert_eq(old.save(_scratch_cfg), OK, "precondition: the legacy cfg is on the scratch path")

	var first = surrogate.new()
	first.load_settings()
	assert_almost_eq(first.mouse_sensitivity, 0.000825, 0.0000001,
		"first boot: the legacy 0.002 canvas px loads as 0.000825 rad per screen px (x 792/1920) — load_settings goes through the migration, not a bare read of either key")
	assert_eq(first.presentation, Settings.PRESENTATION_HIGH_FIDELITY,
		"first boot: a pre-presentation cfg gets the shipped High Fidelity look")
	assert_almost_eq(first.render_scale, 1.0, 0.000001,
		"first boot: the RETRO-era 2.0 supersample is reset to native 1.0 — 2.0 of a native target is 4K 3D on a 1080p screen")
	first.save_settings()  # what the player's next Options change does: re-save the whole file
	first.free()

	var saved := ConfigFile.new()
	assert_eq(saved.load(_scratch_cfg), OK, "save_settings wrote the migrated cfg")
	assert_false(saved.has_section_key("input", Settings.MOUSE_SENS_LEGACY_KEY),
		"the saved cfg carries no legacy mouse key: an older build (which knows only that key) would read a screen-px number as canvas px")

	var second = surrogate.new()
	second.load_settings()
	assert_almost_eq(second.mouse_sensitivity, 0.000825, 0.0000001,
		"second boot: the migrated look speed loads verbatim — rescaling it again (0.00034) makes the look 2.4x slower every launch")
	assert_eq(second.presentation, Settings.PRESENTATION_HIGH_FIDELITY, "second boot: still High Fidelity")
	second.set_presentation(Settings.PRESENTATION_RETRO)  # the player opts into Retro with a 1.5x supersample
	second.set_render_scale(1.5)
	second.free()

	var third = surrogate.new()
	third.load_settings()
	assert_eq(third.presentation, Settings.PRESENTATION_RETRO,
		"a Retro choice survives a restart — the era reset must not run again on a cfg this build saved")
	assert_almost_eq(third.render_scale, 1.5, 0.000001,
		"...and so does its render scale")
	third.free()

	# A legacy value at the OLD slider ceiling rescales ~3% past SENS_MAX; the load clamps it onto the new ceiling.
	var ceiling := ConfigFile.new()
	ceiling.set_value("input", Settings.MOUSE_SENS_LEGACY_KEY, 0.01)
	assert_eq(ceiling.save(_scratch_cfg), OK, "precondition: the old-ceiling cfg is on the scratch path")
	var fastest = surrogate.new()
	fastest.load_settings()
	assert_almost_eq(fastest.mouse_sensitivity, Settings.SENS_MAX, 0.0000001,
		"a legacy value at the old slider ceiling loads ON the new ceiling, never faster than the slider can show")
	fastest.free()

## Every on/off row in Options must survive a restart: flip it through its real setter (which saves), then boot a
## fresh instance through the real load_settings and read it back. Driven from SettingsCatalog.tres, so a toggle
## added later is covered the moment its row exists. Catches a setter that forgets to save, a save/load key
## mismatch, and a row load_settings never reads — each of which works all session and forgets on relaunch.
## ISOLATION is the other half: after each restart EVERY OTHER toggle must still read its shipped value. Reading back
## only the flipped row cannot see a load line that reads a NEIGHBOUR's cfg key (a copy-paste slip between adjacent
## _cfg_bool lines): when the two rows ship opposite values, the neighbour's saved value happens to equal the flipped
## one and the flipped row still "survives", while the cross-wired row silently takes on another row's choice.
## (Debug-only rows round-trip too: load_settings sanitises them only in a release build, and GUT is a debug build.)
##
## SESSION_ONLY_TOGGLES is the ONE allowed exception list, and it is deliberately hostile to grow: a row on it is
## a row that forgets the player's choice on every launch, which is a defect for all but a handful of settings.
## Each entry needs a reason that survives being read back cold, and the same rows are asserted to be genuinely
## absent from the saved cfg rather than merely not read — a row that saves but never loads is a bug wearing this
## exemption as a disguise. It is EMPTY today: `third_person_camera` used to sit here, and left with its Options
## row when the view mode went back to the `ToggleView` bind alone (it is still session-only — that half is pinned
## by test_third_person_never_survives_a_restart, which needs no catalog row to do it).
const SESSION_ONLY_TOGGLES := {}

func test_every_options_toggle_survives_a_restart() -> void:
	var surrogate := _settings_on_scratch_cfg()
	if surrogate == null:
		return
	var cat := load(CATALOG_PATH) as SettingsCatalog
	assert_true(cat != null, "the settings catalog must load")
	if cat == null:
		return
	# The shipped value of every toggle row, read off ONE bare instance (the same seed each writer and reader starts from).
	var toggles: Array[SettingSpec] = []
	var shipped_by_getter := {}
	var probe = surrogate.new()
	for spec in cat.specs:
		if spec.control != SettingSpec.Widget.TOGGLE or spec.getter == &"" or spec.setter == &"":
			continue
		var value: Variant = probe.get(spec.getter)
		if not (value is bool):
			fail_test("toggle row '%s' reads Settings.%s, which is not a bool field" % [spec.key, spec.getter])
			continue
		toggles.append(spec)
		shipped_by_getter[spec.getter] = value
	probe.free()
	assert_gt(toggles.size(), 1, "precondition: the catalog offers several toggles, so the isolation check has neighbours to watch")
	var covered: Array[StringName] = []
	for spec in toggles:
		if SESSION_ONLY_TOGGLES.has(spec.getter):
			continue  # asserted separately below — this row is MEANT to forget (see SESSION_ONLY_TOGGLES)
		var shipped: bool = shipped_by_getter[spec.getter]
		_remove_scratch_cfg()
		var writer = surrogate.new()
		writer._loaded = true  # a bare instance never ran load_settings, and save_settings refuses to write before it
		writer.call(spec.setter, not shipped)
		writer.free()
		var reader = surrogate.new()
		reader.load_settings()
		var after_load: Variant = reader.get(spec.getter)
		var drifted := PackedStringArray()
		for other in toggles:
			if other.getter != spec.getter and reader.get(other.getter) != shipped_by_getter[other.getter]:
				drifted.append(String(other.getter))
		reader.free()
		assert_eq(after_load, not shipped,
			"Options toggle '%s' (%s) must survive a restart: set to %s, it came back %s" % [spec.key, spec.setter, not shipped, after_load])
		assert_eq(drifted.size(), 0,
			"restart isolation: flipping '%s' must leave every other Options toggle at its shipped value, but %s came back flipped — a load_settings line reading a neighbour's cfg key carries one player's choice onto another row" % [spec.key, drifted])
		covered.append(spec.getter)
	for must in [&"hitstop_enabled", &"screen_flash_enabled", &"tts_enabled", &"heartbeat_enabled", &"minimap_enabled",
			&"minimap_rotates", &"minimap_show_npcs", &"minimap_show_stations", &"clock_enabled", &"clock_24_hour"]:
		assert_true(covered.has(must), "the Options catalog must still offer a toggle bound to Settings.%s" % must)
	# The exempt rows: each must STILL be an Options toggle (so the exemption can't quietly outlive its row), and
	# must write nothing to the cfg — "not loaded" alone would leave a key an older build could still restore.
	for getter in SESSION_ONLY_TOGGLES:
		var spec: SettingSpec = null
		for t in toggles:
			if t.getter == getter:
				spec = t
		assert_true(spec != null, "Settings.%s is exempt from the restart rule but no longer has an Options row" % getter)
		if spec == null:
			continue
		_remove_scratch_cfg()
		var writer = surrogate.new()
		writer._loaded = true
		writer.call(spec.setter, true)
		writer.save_settings()  # the next Options change the player makes
		writer.free()
		var cfg := ConfigFile.new()
		if cfg.load(_scratch_cfg) == OK:
			for section in cfg.get_sections():
				assert_false(cfg.has_section_key(section, String(getter)),
					"'%s' is session-only (%s), so nothing may write it to the cfg — a saved key is a restore waiting to happen" % [
						spec.key, SESSION_ONLY_TOGGLES[getter]])
		var reader = surrogate.new()
		reader.load_settings()
		assert_false(bool(reader.get(getter)),
			"'%s' must come back OFF after a restart: %s" % [spec.key, SESSION_ONLY_TOGGLES[getter]])
		reader.free()

func test_set_volume_clamps_to_unit_range() -> void:
	Settings.set_volume(&"Master", 5.0)
	assert_eq(Settings.get_volume(&"Master"), 1.0, "volume clamps to 1.0")
	Settings.set_volume(&"Master", -1.0)
	assert_eq(Settings.get_volume(&"Master"), 0.0, "volume clamps to 0.0 (mute)")

## The shake slider is a PERCENTAGE of the authored shake (the intensity captured at boot), so it must scale
## linearly, clamp at the 200% ceiling, and never compound: re-applying the same scale lands on the same intensity
## (a model that multiplied the CURRENT intensity would ratchet the shake up on every Options Apply).
## ORDER MATTERS: 200% is applied twice straight after the 100% baseline, before any other scale. With a 50% step in
## between, a compounding model walks A -> A/2 -> A -> 2A and the "twice" check would still see 2A.
func test_screen_shake_scale_scales_baseline_intensity() -> void:
	Settings.set_screen_shake_scale(1.0)
	var authored: float = GameSettings.screen_shake.intensity_multiplier
	assert_gt(authored, 0.0, "precondition: the authored shake is non-zero, so a scale has something to scale")
	assert_almost_eq(authored, Settings._base_shake_intensity, 0.00001,
		"100% shake is exactly the authored intensity Settings captured at boot, not an offset copy of it")
	Settings.set_screen_shake_scale(2.0)
	assert_almost_eq(GameSettings.screen_shake.intensity_multiplier, authored * 2.0, 0.00001,
		"200% doubles the authored intensity")
	Settings.set_screen_shake_scale(2.0)
	assert_almost_eq(GameSettings.screen_shake.intensity_multiplier, authored * 2.0, 0.00001,
		"re-applying 200% does not compound: a model that multiplied the CURRENT intensity would land on 4x here and ratchet the shake up on every Options Apply")
	Settings.set_screen_shake_scale(0.5)
	assert_almost_eq(GameSettings.screen_shake.intensity_multiplier, authored * 0.5, 0.00001,
		"50% shake halves the authored intensity")
	Settings.set_screen_shake_scale(9.0)
	assert_almost_eq(GameSettings.screen_shake.intensity_multiplier, authored * 2.0, 0.00001,
		"an out-of-range scale clamps to the 200% ceiling")
	Settings.set_screen_shake_scale(0.0)
	assert_eq(GameSettings.screen_shake.intensity_multiplier, 0.0, "0% shake -> zero intensity")

func test_render_scale_clamps() -> void:
	Settings.set_render_scale(99.0)
	assert_eq(Settings.render_scale, Settings.RENDER_SCALE_MAX, "render scale clamps to max")


# --- Presentation: native-res HIGH FIDELITY vs the classic ~792x444 RETRO pixel pipeline --------------------

## The shipped presentation is HIGH FIDELITY, and a first boot must render its 3D at NATIVE resolution:
## project.godot's rendering/scaling_3d/scale 2.0 is the RETRO buffer's supersample, and re-read against a native
## root target it means 3840x2160 3D on a 1080p screen. load_settings early-returns when no cfg exists, so only
## _ready's seed protects that first boot. Driven through the REAL _ready on the fresh-install double; off-tree there
## is no window, so the pre-seed render_scale is the field's own supersample value, standing in for the window's 2.0.
## The RETRO control proves the reset belongs to HIGH FIDELITY and is not an unconditional 1.0 that would strip the
## Retro look's supersample.
func test_fresh_install_boots_high_fidelity_at_native_render_scale() -> void:
	var boot = _fresh_install_double()
	if boot == null:
		return
	var pre_seed: float = boot.render_scale
	assert_gt(pre_seed, 1.0, "precondition: the pre-boot render_scale is a supersample, so a reset to 1.0 is observable")
	boot._ready()
	assert_eq(boot.presentation, Settings.PRESENTATION_HIGH_FIDELITY,
		"SHIP DECISION: a fresh install boots the native-resolution High Fidelity presentation (Retro is the opt-in)")
	assert_almost_eq(boot.render_scale, 1.0, 0.000001,
		"a fresh High Fidelity install renders 3D at native resolution; keeping the Retro supersample would be 4K 3D on a 1080p screen")
	boot.free()
	var retro = _fresh_install_double()
	retro.presentation = Settings.PRESENTATION_RETRO
	retro._ready()
	assert_almost_eq(retro.render_scale, pre_seed, 0.000001,
		"control: booting under RETRO keeps its supersample of the ~792x444 buffer — the native reset is High Fidelity's alone")
	retro.free()

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

## native_scale()/render_size() are the unit-converter seam every pixel-unit effect reads live per frame.
## Off-tree there is no window, so both must degrade to the RETRO identity — GUT drives effect params (e.g.
## InkOutline._params) off-tree, and a null-window crash here would redden every one of those suites.
func test_native_scale_degrades_to_retro_identity_off_tree() -> void:
	var fresh = load("res://managers/Settings.gd").new()
	assert_almost_eq(fresh.native_scale(), 1.0, 0.000001, "no window -> 1.0 (canvas px ARE render px)")
	assert_eq(fresh.render_size(), Vector2i(792, 444), "no window -> the 16:9 logical canvas fallback")
	fresh.free()

## Three ship decisions on a first boot. Each channel ships ON and its Options row only takes it AWAY:
##  - screen flashes: the authored hurt/dash/kill flashes fire until a photosensitive player suppresses them in
##    Accessibility (PlayerHud.flash_* / StarSky.flash_kill poll the field at fire time);
##  - text-to-speech: the 2026-09-01 design call — players must HEAR an NPC when they talk to them; the old
##    ship-silent accessibility framing was deliberately overruled, so silence is the opt-OUT;
##  - the low-HP heartbeat: the same opt-out shape (the player's _update_low_hp polls it each frame).
## Read off the fresh-install double after the real _ready, so a boot-time seed that overrode a default shows here.
## Whether each toggle then persists is test_every_options_toggle_survives_a_restart's job.
func test_fresh_install_ships_flashes_speech_and_heartbeat_on() -> void:
	var boot = _fresh_install_double()
	if boot == null:
		return
	boot._ready()
	assert_true(boot.screen_flash_enabled,
		"SHIP DECISION: the full-screen flashes are ON on a fresh install (the Accessibility toggle only SUPPRESSES them)")
	assert_true(boot.tts_enabled,
		"SHIP DECISION (2026-09-01): Text-to-Speech is ON on a fresh install — hearing NPCs is part of the design, silence is the opt-out")
	assert_true(boot.heartbeat_enabled,
		"SHIP DECISION: the low-HP heartbeat is ON on a fresh install (the toggle only SILENCES it)")
	boot.free()

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

func test_ps1_warp_intensity_default_off_and_clamps() -> void:
	# OFF (0.0) by default — since the 08-31 defaults retune the PS1 vertex wobble is opt-IN: a fresh Settings
	# (var default, no cfg) renders the level with no warp at all (PS1Applier holds no material overrides at 0),
	# and the Options -> Accessibility slider dials the authored effect back up.
	var fresh = load("res://managers/Settings.gd").new()
	assert_eq(fresh.ps1_warp_intensity, 0.0,
		"PS1 vertex-warp intensity defaults to 0% — the wobble is opt-in since 08-31; a stored cfg value still wins on load, so only fresh installs boot warp-free")
	fresh.free()
	# Round-trips + clamps through the live setter PS1Applier polls each frame (after_each puts the prior value back).
	Settings.set_ps1_warp_intensity(2.0)
	assert_eq(Settings.ps1_warp_intensity, 1.0, "intensity clamps to 100%")
	Settings.set_ps1_warp_intensity(-1.0)
	assert_eq(Settings.ps1_warp_intensity, 0.0, "intensity clamps to 0% (warp off)")
	Settings.set_ps1_warp_intensity(0.5)
	assert_eq(Settings.ps1_warp_intensity, 0.5, "an in-range intensity is stored verbatim")


## The minimap rows (Options -> HUD / Accessibility). ALL are polled live — there is deliberately no apply_all entry —
## so the contracts are the shipped defaults, the clamps, and persistence (test_every_options_toggle_survives_a_restart).
## The defaults read the fresh-install double after the real _ready, never the autoload, whose _ready has already
## loaded user://settings.cfg and would report whatever this machine last saved rather than the shipped default.
## The two zooms are tuning numbers, so they are held to the invariants the design needs rather than to their literals.
func test_fresh_install_minimap_and_map_defaults() -> void:
	var boot = _fresh_install_double()
	if boot == null:
		return
	boot._ready()
	assert_true(boot.minimap_enabled, "SHIP DECISION: the minimap ships ON — it is the shipped HUD, not an opt-in")
	assert_false(boot.minimap_rotates,
		"SHIP DECISION (08-31): north-up is the shipped mode (the plan stays axis-locked and the caret spins, matching the Map tab) — heading-up is the Rotate Minimap opt-in")
	assert_true(boot.minimap_show_npcs, "SHIP DECISION: NPC dots ship visible")
	assert_true(boot.minimap_show_stations,
		"SHIP DECISION: station glyphs ship ON — a shop is a fixture, not a body, so marking it leaks no tactical information; the row is a DECLUTTER opt-out, not a difficulty one")
	var corner: float = boot.minimap_zoom
	var page: float = boot.map_zoom
	boot.free()
	assert_between(corner, Settings.MINIMAP_ZOOM_MIN, Settings.MINIMAP_ZOOM_MAX,
		"the corner box's shipped zoom sits inside the shared clamp, or the first slider touch or reload snaps it somewhere else")
	assert_between(page, Settings.MINIMAP_ZOOM_MIN, Settings.MINIMAP_ZOOM_MAX,
		"the Map tab's shipped zoom sits inside the same shared clamp")
	assert_gt(corner, 1.0,
		"SHIP DECISION (08-31): the corner box ships zoomed IN — fewer metres across than GameSettings.hud.minimap_world_span")
	assert_gt(page, 1.0,
		"SHIP DECISION (08-31): the Map tab opens zoomed in on a readable district, not the whole GameSettings.hud.map_world_span")
	var stops: PackedFloat32Array = GameSettings.hud.minimap_zoom_steps
	if stops.is_empty():
		return  # an empty list disables the Cycle Minimap Zoom key, so there is no cycle to land on
	var on_cycle := false
	for stop in stops:
		if is_equal_approx(stop, corner):
			on_cycle = true
	assert_true(on_cycle,
		"the shipped minimap zoom %.2f must be one of the Cycle Minimap Zoom key's stops %s — otherwise one press leaves the out-of-box zoom and no amount of cycling returns to it" % [corner, stops])

func test_minimap_zoom_clamps() -> void:
	Settings.set_minimap_zoom(9.0)
	assert_almost_eq(Settings.minimap_zoom, Settings.MINIMAP_ZOOM_MAX, 0.0001, "zoom clamps to MINIMAP_ZOOM_MAX")
	Settings.set_minimap_zoom(0.0)
	assert_almost_eq(Settings.minimap_zoom, Settings.MINIMAP_ZOOM_MIN, 0.0001, "zoom clamps to MINIMAP_ZOOM_MIN")
	Settings.set_minimap_zoom(2.5)
	assert_almost_eq(Settings.minimap_zoom, 2.5, 0.0001, "an in-range zoom is stored verbatim")
	assert_lt(Settings.MINIMAP_ZOOM_MIN, Settings.MINIMAP_ZOOM_MAX, "the range is the right way round")

## The MAP TAB's zoom is its OWN stored value on the SHARED clamp — the two maps are the same widget at two
## sizes, so one range describes both, but scrolling the page-sized map must never move the corner box (they
## divide different spans: map_world_span vs minimap_world_span).
func test_map_zoom_clamps_and_is_independent_of_the_minimap_row() -> void:
	var was_minimap: float = Settings.minimap_zoom
	Settings.set_map_zoom(9.0)
	assert_almost_eq(Settings.map_zoom, Settings.MINIMAP_ZOOM_MAX, 0.0001, "map zoom clamps to the shared MAX")
	Settings.set_map_zoom(0.0)
	assert_almost_eq(Settings.map_zoom, Settings.MINIMAP_ZOOM_MIN, 0.0001, "map zoom clamps to the shared MIN")
	Settings.set_map_zoom(1.5)
	assert_almost_eq(Settings.map_zoom, 1.5, 0.0001, "an in-range map zoom is stored verbatim")
	assert_almost_eq(Settings.minimap_zoom, was_minimap, 0.0001,
		"...and moving the MAP's zoom leaves the HUD minimap's row untouched — a shared field would make scrolling the map re-zoom the corner box")

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
	assert_not_null(found, "Options -> HUD must carry a 'Stations On Minimap' row")
	if found == null:
		return
	assert_eq(found.tab, &"HUD", "it belongs beside the rest of the declutter family")
	assert_eq(found.getter, &"minimap_show_stations", "bound to the Settings field")
	assert_eq(found.setter, &"set_minimap_show_stations", "...and to its setter")
	assert_false(found.label.is_empty(), "a row with no label is an invisible row")

## Two ship decisions on a first boot, read off the fresh-install double after the real _ready. Persistence of both
## rows is test_every_options_toggle_survives_a_restart's job.
func test_fresh_install_clock_defaults() -> void:
	var boot = _fresh_install_double()
	if boot == null:
		return
	boot._ready()
	assert_true(boot.clock_enabled,
		"SHIP DECISION: the HUD clock ships ON — the day/night cycle's lighting is otherwise the only time signal, and it is a poor instrument (the moon keeps midnight legible, interiors are lit around the clock)")
	assert_true(boot.clock_24_hour, "SHIP DECISION: the 24-hour face is the shipped face (12-hour with AM/PM is the opt-in)")
	boot.free()


func test_release_build_ignores_persisted_debug_flags() -> void:
	# A settings.cfg written by a debug build (or hand-edited) can carry skip_menu=true / always_show_tos=true; a
	# release export must not boot past the menu or replay the Terms gate because of it. load_settings ends by
	# calling this with OS.is_debug_build() — a parameter because that flag is always true under GUT.
	var prev_skip: bool = Settings.debug_skip_menu
	var prev_tos: bool = Settings.debug_always_show_tos
	Settings.debug_skip_menu = true
	Settings.debug_always_show_tos = true
	Settings._sanitize_debug_flags(true)
	assert_true(Settings.debug_skip_menu and Settings.debug_always_show_tos,
		"a debug build keeps both toggles exactly as persisted")
	Settings._sanitize_debug_flags(false)
	assert_false(Settings.debug_skip_menu, "a release build forces Skip Main Menu OFF whatever the cfg says")
	assert_false(Settings.debug_always_show_tos, "a release build forces Always Show Terms OFF whatever the cfg says")
	Settings.debug_skip_menu = prev_skip
	Settings.debug_always_show_tos = prev_tos
