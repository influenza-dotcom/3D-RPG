extends GutTest
## Colour Depth — the screen post-process's colour quantiser.
##
## WHAT IT IS. `post_process.gdshader` snaps every finished frame onto a colour grid. It always did, with one
## scalar `color_steps` authored per material; this feature makes the grid a PLAYER choice and makes it
## PER-CHANNEL, so the depths that actually existed in hardware can be named: RGB565 gives green the odd bit,
## RGB332 starves blue. Settings owns the table (index -> per-channel step count), retro_post.gd's apply_dials()
## pushes the chosen row onto a live material as `quantize_levels` (both retro hosts call it every frame: the
## Player's overlay and the boot screen), and the shader falls back to the material's own `color_steps` when
## nobody is driving it.
##
## WHAT IS DRIVEN AND WHAT IS GREPPED. Headless runs a DUMMY rasterizer and NEVER compiles a .gdshader: a shader
## with a hard syntax error load()s clean. So the shader half is guarded by its source text (the uniforms, the
## sentinel fallback, the vec3 quantise). Everything on the GDScript side is exercised for real: the table
## statics, a save/load round trip (a recompiled Settings pointed at a scratch cfg), apply_dials on a real
## ShaderMaterial read back through get_shader_parameter (a parameter cache, so it works headless), each host's
## per-frame update, the chooser's captions and the `quantize` console command.
##
## The real look check is a windowed run — see scripts/tools/probes/color_depth_qa_shots.gd, which counts the DISTINCT
## COLOURS in a captured frame per depth. That is the one claim about this feature a screenshot can settle.

const SHADER_PATH := "res://resources/shaders/post_process.gdshader"
const SETTINGS_PATH := "res://managers/Settings.gd"
const PLAYER_PATH := "res://scripts/player/player.gd"
const BOOT_SCENE_PATH := "res://scenes/computerroom.tscn"
const OPTIONS_PATH := "res://scripts/ui/options_menu.gd"
const CATALOG_PATH := "res://resources/settings/SettingsCatalog.tres"
const UI_SCENE_PATH := "res://scenes/player/ui.tscn"

const SettingsScript := preload("res://managers/Settings.gd")
## The shared presentation dials both retro hosts push: the in-game overlay on the Player's ColorRect and the
## BOOT SCREEN's own copy in computerroom.tscn, which has no Player at all.
const RetroPost := preload("res://scripts/ui/retro_post.gd")
const Commands := preload("res://scripts/components/debug_commands.gd")
const WorldActions := preload("res://scripts/components/debug_actions_world.gd")

## Every live Settings field these tests stage, snapshotted before each test and put back after. Always written as
## the FIELD, never through the setter: every Settings setter persists, and a test must never rewrite this
## machine's user://settings.cfg.
const STAGED_SETTINGS: Array[StringName] = [&"color_quantization", &"dither_strength", &"contrast", &"colorblind_mode"]

var _settings_before: Dictionary = {}
## The root window's stretch mode at the start of each test: the presentation tests stage RETRO and HIGH FIDELITY
## by switching it, and after_each puts the boot mode back.
var _root_scale_mode: Window.ContentScaleMode = Window.CONTENT_SCALE_MODE_DISABLED
## Where the round-trip test's recompiled Settings saves. Per process, so two concurrent GUT runs never share it.
var _scratch_cfg := ""


func before_each() -> void:
	_settings_before.clear()
	for field in STAGED_SETTINGS:
		_settings_before[field] = Settings.get(field)
	_scratch_cfg = "user://gut_color_quantization_%d.cfg" % OS.get_process_id()
	_root_scale_mode = get_tree().root.content_scale_mode


func after_each() -> void:
	if get_tree().root.content_scale_mode != _root_scale_mode:
		get_tree().root.content_scale_mode = _root_scale_mode
	for field in _settings_before:
		Settings.set(field, _settings_before[field])
	if FileAccess.file_exists(_scratch_cfg):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_scratch_cfg))


func _read(path: String) -> String:
	var s := FileAccess.get_file_as_string(path)
	assert_false(s.is_empty(), "%s must be readable" % path)
	return s


## A material wearing the real post-process shader with nothing pushed onto it yet.
func _fresh_post_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH) as Shader
	return mat


## The post_process ShaderMaterial a scene AUTHORS, read off its SceneState: nothing is instantiated and no _ready
## runs. It is the cached scene's shared sub-resource, so callers only READ it.
func _authored_post_material(scene_path: String) -> ShaderMaterial:
	var scene := load(scene_path) as PackedScene
	assert_true(scene != null, "%s must load" % scene_path)
	if scene == null:
		return null
	var state := scene.get_state()
	for node_idx in state.get_node_count():
		for prop_idx in state.get_node_property_count(node_idx):
			var value = state.get_node_property_value(node_idx, prop_idx)
			if value is ShaderMaterial and value.shader != null and value.shader.resource_path == SHADER_PATH:
				return value
	assert_true(false, "%s authors no material wearing post_process.gdshader" % scene_path)
	return null


## Stage two different sets of player look dials (fields only), run one host frame after each, and require the
## host's overlay material to carry exactly what was staged. Two stagings, so a host that pushes its own constants,
## or pushes once and stops polling, cannot pass by coincidence.
func _assert_host_obeys_player_dials(host: String, mat: ShaderMaterial, tick: Callable) -> void:
	var stagings := [
		{"dither": 0.25, "depth": 6, "contrast": 1.2, "colorblind": 2},
		{"dither": 0.75, "depth": 2, "contrast": 0.9, "colorblind": 0},
	]
	for staged in stagings:
		Settings.dither_strength = staged["dither"]
		Settings.color_quantization = staged["depth"]
		Settings.contrast = staged["contrast"]
		Settings.colorblind_mode = staged["colorblind"]
		tick.call()
		assert_eq(mat.get_shader_parameter("dither_strength"), staged["dither"],
			"%s: the overlay's dither strength follows the player's Dithering dial" % host)
		assert_eq(mat.get_shader_parameter("quantize_levels"), SettingsScript.COLOR_QUANTIZE_LEVELS[staged["depth"]],
			"%s: the overlay quantises at the player's colour depth %d" % [host, staged["depth"]])
		assert_eq(mat.get_shader_parameter("contrast"), staged["contrast"],
			"%s: the overlay's contrast follows the player's Contrast dial" % host)
		assert_eq(mat.get_shader_parameter("colorblind_mode"), staged["colorblind"],
			"%s: the overlay's colourblind filter follows the player's choice" % host)


## What both debug front-ends hand an action module. `quantize` needs none of it, but run() gets the real shape.
func _console_ctx() -> Dictionary:
	return {&"tree": get_tree(), &"player": null, &"host": null, &"state": {}}


## The real user://settings.cfg as it stands, so a test that runs a command can prove the command left it alone.
func _snapshot_real_cfg() -> Dictionary:
	var path := String(SettingsScript.CONFIG_PATH)
	var exists := FileAccess.file_exists(path)
	return {"path": path, "exists": exists,
		"bytes": FileAccess.get_file_as_bytes(path) if exists else PackedByteArray()}


## Fails if the real cfg changed since `snap`, and puts the original back so a regression does not leave this
## machine's settings rewritten by a test run.
func _assert_real_cfg_untouched(snap: Dictionary, why: String) -> void:
	var path := String(snap["path"])
	var exists := FileAccess.file_exists(path)
	var bytes := FileAccess.get_file_as_bytes(path) if exists else PackedByteArray()
	var changed: bool = exists != bool(snap["exists"]) or bytes != snap["bytes"]
	assert_false(changed, why)
	if not changed:
		return
	if bool(snap["exists"]):
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_buffer(snap["bytes"])
			f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# =============================================================================================================
# The table — the only part of this feature a headless run can actually evaluate
# =============================================================================================================

## Index 0 is not a depth, it is the "leave it alone" sentinel. It has to stay Vector3.ZERO, because that exact
## value is what the shader tests for before falling back to the material's authored `color_steps`. The shipped
## DEFAULT moved off it on 08-31: fresh installs now boot on index 4 (12-bit RGB444), and the sentinel remains
## the player's one-click opt-out back to the untouched materials. Existing installs are unaffected — a stored
## cfg index always wins on load, so nobody's saved look changes, only the first frame of a brand-new install.
func test_the_default_index_is_the_dev_authored_12_bit_look() -> void:
	assert_eq(SettingsScript.COLOR_QUANTIZE_LEVELS[0], Vector3.ZERO,
		"index 0 must be Vector3.ZERO — the sentinel post_process.gdshader tests for (`quantize_levels.r > 0.0`) before falling back to the material's own color_steps")
	var fresh = SettingsScript.new()
	assert_eq(fresh.color_quantization, 4,
		"Colour Depth ships on index 4: the 08-31 defaults pass made the dev-authored 12-bit RGB444 quantise the out-of-box frame (a deliberate reversal of the old ship-on-the-sentinel rule — stored cfg indices still win on load, so only fresh installs see it)")
	fresh.free()
	assert_eq(SettingsScript.COLOR_QUANTIZE_LEVELS[4], Vector3(15, 15, 15),
		"...and index 4 must still BE 12-bit RGB444 — reorder the table and the shipped default silently becomes a different depth")

## The named depths must actually be the depths they are named after, because the caption is the only thing the
## player is told. 5 bits a channel is 32 levels is 31 steps — an off-by-one here is a wrong claim in the menu.
func test_the_named_depths_carry_the_bit_counts_they_advertise() -> void:
	var table: Array[Vector3] = SettingsScript.COLOR_QUANTIZE_LEVELS
	assert_eq(table[1], Vector3(255, 255, 255),
		"index 1 is '24-bit (Off)' — 8 bits a channel is 255 steps, which is what the framebuffer already holds, so the quantiser becomes a no-op rather than a special case")
	assert_eq(table[2], Vector3(31, 63, 31),
		"index 2 is 16-bit RGB565 — the odd bit goes to GREEN (63 steps), the whole reason this is a vec3")
	assert_eq(table[3], Vector3(31, 31, 31),
		"index 3 is 15-bit RGB555 — the PlayStation's own framebuffer, 5 bits a channel = 31 steps")
	assert_eq(table[6], Vector3(7, 7, 3),
		"index 6 is 8-bit RGB332 — blue is the starved channel (3 steps), not red or green")
	assert_eq(table[8], Vector3(1, 1, 1),
		"index 8 is 3-bit — one bit a channel, eight colours; the coarsest row the menu offers")

## Every depth has to be strictly coarser than the one above it, or the dropdown is lying about being ordered:
## a player stepping down the list expects fewer colours at every press, and the QA harness asserts exactly that.
func test_the_depths_only_ever_get_coarser_down_the_list() -> void:
	var previous := -1
	for i in range(1, SettingsScript.COLOR_QUANTIZE_LEVELS.size()):
		var colors := int(SettingsScript.color_quantize_color_count(i))
		assert_gt(colors, 0, "depth %d must report a colour count — only the index-0 sentinel may report 0" % i)
		if previous >= 0:
			assert_lt(colors, previous,
				"depth %d must offer FEWER colours than depth %d (%d vs %d) — the list is ordered finest-first and the menu presents it that way" % [i, i - 1, colors, previous])
		previous = colors

## The colour count is (steps + 1) per channel multiplied out. It is quoted by the debug command and asserted by
## the QA harness, so it must be the arithmetic and not a hand-typed table that can drift from the levels.
func test_the_colour_count_is_the_levels_multiplied_out() -> void:
	assert_eq(SettingsScript.color_quantize_color_count(3), 32768,
		"15-bit RGB555 is 32 x 32 x 32 = 32768 colours")
	assert_eq(SettingsScript.color_quantize_color_count(2), 65536,
		"16-bit RGB565 is 32 x 64 x 32 = 65536 colours")
	assert_eq(SettingsScript.color_quantize_color_count(6), 256,
		"8-bit RGB332 is 8 x 8 x 4 = 256 colours")
	assert_eq(SettingsScript.color_quantize_color_count(8), 8,
		"3-bit RGB111 is 2 x 2 x 2 = 8 colours")
	assert_eq(SettingsScript.color_quantize_color_count(0), 0,
		"the sentinel cannot know — the count depends on whatever `color_steps` the material authored")

## TOTAL, not trusting. A stale index (a settings.cfg written by a build with more depths, a debug typo, an
## off-by-one in a caller) must land on the sentinel — which means "leave the frame as authored" — and never on
## a garbage vec3, because a garbage vec3 is a divide that blows the whole image out.
func test_an_out_of_range_index_falls_back_to_the_sentinel_not_to_junk() -> void:
	for bad in [-1, -99, SettingsScript.COLOR_QUANTIZE_LEVELS.size(), 9999]:
		assert_eq(SettingsScript.color_quantize_levels(bad), Vector3.ZERO,
			"index %d is outside the table and must return the Vector3.ZERO sentinel, so a bad caller degrades to the authored look rather than to a division by zero" % bad)
		assert_eq(SettingsScript.color_quantize_color_count(bad), 0,
			"index %d must report no colour count either — 0 is the honest answer for 'however the material was authored'" % bad)

## No zero component anywhere in a REAL depth: the shader divides by this vector, and a zero would produce inf
## on that channel — a solid red/green/blue screen, not a subtle wrong.
func test_no_real_depth_can_divide_by_zero() -> void:
	for i in range(1, SettingsScript.COLOR_QUANTIZE_LEVELS.size()):
		var l: Vector3 = SettingsScript.COLOR_QUANTIZE_LEVELS[i]
		assert_gt(l.x, 0.0, "depth %d red steps must be positive — the shader divides by this" % i)
		assert_gt(l.y, 0.0, "depth %d green steps must be positive — the shader divides by this" % i)
		assert_gt(l.z, 0.0, "depth %d blue steps must be positive — the shader divides by this" % i)


# =============================================================================================================
# Settings — clamp, persistence key, round trip
# =============================================================================================================

## The clamp is the guard the load path leans on. A bare off-tree instance never ran _ready, so _loaded stays
## false and save_settings() early-returns — the setter tests here can never touch the real settings.cfg.
func test_the_setter_clamps_into_the_table() -> void:
	var s = SettingsScript.new()
	var last := int(SettingsScript.COLOR_QUANTIZE_LEVELS.size()) - 1
	s.set_color_quantization(99)
	assert_eq(s.color_quantization, last, "a too-high index clamps to the coarsest depth, never past the table")
	s.set_color_quantization(-5)
	assert_eq(s.color_quantization, 0, "a negative index clamps to the sentinel — the authored look is the safe end")
	s.set_color_quantization(3)
	assert_eq(s.color_quantization, 3, "an in-range index is kept verbatim")
	s.free()

## The REAL managers/Settings.gd with its `config_path` seam pointed at the scratch cfg, so save_settings
## and load_settings run for real without going near this machine's user://settings.cfg. A one-line subclass sets the seam in _init, so every
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

## Persistence: the depth is written under [video] beside the other look dials AND read back. A setting that is
## saved but never loaded works all session and forgets on restart. Then the clamp the load leans on: a cfg written
## by a build with MORE depths, or edited by hand, must load inside the table and never index past it.
func test_the_setting_round_trips_through_the_video_section() -> void:
	var surrogate := _settings_on_scratch_cfg()
	if surrogate == null:
		return
	var saved := 6
	var writer = surrogate.new()
	writer._loaded = true  # a bare instance never ran load_settings, and save_settings refuses to write before it has
	writer.set_color_quantization(saved)
	writer.free()
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(_scratch_cfg), OK, "set_color_quantization saved a settings file")
	assert_eq(cfg.get_value("video", "color_quantization", -1), saved, "the depth is stored under [video]")

	var reader = surrogate.new()
	assert_ne(reader.color_quantization, saved, "control: a fresh instance does not already hold the saved depth")
	reader.load_settings()
	assert_eq(reader.color_quantization, saved, "load_settings reads the saved depth back")
	reader.free()

	var last := SettingsScript.COLOR_QUANTIZE_LEVELS.size() - 1
	for stale in [[last + 5, last], [-3, 0]]:
		var old_cfg := ConfigFile.new()
		old_cfg.set_value("video", "color_quantization", stale[0])
		old_cfg.save(_scratch_cfg)
		var loader = surrogate.new()
		loader.load_settings()
		assert_eq(loader.color_quantization, stale[1],
			"a stored depth of %d loads clamped to %d, so the shader is never handed a row past the table" % stale)
		loader.free()


# =============================================================================================================
# The shader seam — source-text pins, because headless never compiles a .gdshader
# =============================================================================================================

## The uniform apply_dials writes into. Renaming it in the shader breaks NOTHING loudly: set_shader_parameter on a
## name that does not exist is silently discarded, so the chosen depth would simply stop doing anything.
func test_the_shader_declares_the_quantize_levels_uniform() -> void:
	var src := _read(SHADER_PATH)
	assert_true(src.contains("uniform vec3 quantize_levels"),
		"post_process.gdshader must declare `uniform vec3 quantize_levels`: a push to a missing uniform is dropped without an error")

## THE FALLBACK IS THE CONTRACT. Materials nobody drives (this shader on a bare quad in the editor, a new host that
## forgot apply_dials) must keep quantising at their authored `color_steps`. That is one expression, and if it goes,
## every un-driven material silently jumps to vec3(0) and divides by zero.
func test_the_shader_falls_back_to_the_authored_color_steps() -> void:
	var src := _read(SHADER_PATH)
	assert_true(src.contains("quantize_levels.r > 0.0 ? quantize_levels : vec3(float(color_steps))"),
		"post_process.gdshader must keep the sentinel fallback: an un-driven material has quantize_levels at vec3(0), a divide by zero without it")

## The quantise has to be the VECTOR one. Reverting `steps` to a float would compile, keep every other pin
## green, and quietly collapse RGB565 and RGB332 back onto equal channels — the exact thing this feature adds.
func test_the_quantise_is_per_channel() -> void:
	var src := _read(SHADER_PATH)
	assert_true(src.contains("vec3 steps = quantize_levels.r > 0.0"),
		"the quantise step count must be a vec3: a float `steps` still posterises but throws away RGB565's and RGB332's unequal channels")
	assert_true(src.contains("final_color = floor(final_color * steps + threshold) / steps;"),
		"the quantise stays ONE fused floor with the dither threshold folded in: a separate dither pass after posterising is a mathematical no-op")

## Godot does not constant-fold a uniform initializer: `= vec3(1.0/2.0)` is "Expected constant expression" and
## fails the WHOLE shader — which draws a fallback material, not a missing effect. The default added here is a
## literal, and this keeps it that way. (The same guard test_ink_outline.gd runs over the ink shaders.)
func test_uniform_defaults_are_literal_constants() -> void:
	var decl := RegEx.new()
	decl.compile("(?m)^\\s*uniform\\s+\\w+\\s+(\\w+)[^=\\n]*=\\s*([^;]+);")
	# A BINARY operator always follows a digit or a closing paren; a leading `-` (a negative literal) never
	# does, so a signed default is not a false positive.
	var arith := RegEx.new()
	arith.compile("[\\d\\)]\\s*[/*+\\-]")
	var checked := 0
	for m in decl.search_all(_read(SHADER_PATH)):
		checked += 1
		assert_null(arith.search(m.get_string(2)),
			"post_process.gdshader: uniform '%s' has arithmetic in its default (`%s`) — Godot will not fold it and the WHOLE shader fails to compile, which draws a fallback material rather than a missing effect. Write the literal, note the maths in a comment."
				% [m.get_string(1), m.get_string(2).strip_edges()])
	assert_gt(checked, 0, "found no uniform defaults to check — the declaration regex has drifted")

## The presentation-split compensation uniform (render px per logical canvas px). Same failure mode as
## quantize_levels: a push to a missing or renamed uniform is silently dropped, and HIGH FIDELITY's dither cell and
## film grain would collapse to native-pixel noise with no error anywhere.
func test_the_shader_declares_the_pixel_scale_uniform() -> void:
	var src := _read(SHADER_PATH)
	assert_true(src.contains("uniform float pixel_scale"),
		"post_process.gdshader must declare `uniform float pixel_scale`, the dither-cell and grain compensation apply_dials pushes")


# =============================================================================================================
# The push — retro_post.apply_dials on a real ShaderMaterial
# =============================================================================================================

## The shader has no idea what a menu index is: it wants a per-channel STEP COUNT. Pushing the index would quantise
## a 15-bit frame to 3 steps a channel. And the Authored depth must arrive as the Vector3.ZERO sentinel, the value
## the shader tests before falling back to the material's own color_steps.
func test_the_dials_push_the_levels_not_the_index() -> void:
	var mat := _fresh_post_material()
	for depth in [2, 6]:
		Settings.color_quantization = depth
		RetroPost.apply_dials(mat)
		var pushed = mat.get_shader_parameter("quantize_levels")
		assert_eq(typeof(pushed), TYPE_VECTOR3, "depth %d reaches the shader as a vec3 step count, never as the int index" % depth)
		assert_eq(pushed, SettingsScript.COLOR_QUANTIZE_LEVELS[depth], "depth %d pushes its own row of the table" % depth)
	Settings.color_quantization = 0
	RetroPost.apply_dials(mat)
	assert_eq(mat.get_shader_parameter("quantize_levels"), Vector3.ZERO,
		"the Authored depth pushes the zero sentinel, so the shader keeps the material's own color_steps")

## pixel_scale is the dither cell's size in RENDER pixels, so it has to follow the presentation. In RETRO the canvas
## IS the render target and the cell is exactly one pixel, the buffer pixel the Bayer matrix was designed for. In
## HIGH FIDELITY one canvas pixel spans several native pixels, and the cell must span the nearest whole number of
## them or the dither shrinks to native-pixel noise. Headless GUT boots HIGH FIDELITY on a 1280x720 dummy window
## (about 1.6 render px per canvas px), so RETRO is staged by switching the root window's stretch mode.
func test_the_dials_push_pixel_scale() -> void:
	var mat := _fresh_post_material()
	assert_eq(mat.get_shader_parameter("pixel_scale"), null, "control: a fresh material carries no pixel_scale")
	var root := get_tree().root
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT  # RETRO's stretch
	RetroPost.apply_dials(mat)
	assert_eq(mat.get_shader_parameter("pixel_scale"), 1.0, "RETRO: the dither cell is exactly one render pixel")

	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS  # HIGH FIDELITY's stretch
	var ratio := float(root.size.x) / root.get_visible_rect().size.x
	if ratio < 1.5:
		pending("this window puts fewer than 1.5 render pixels under a canvas pixel; headless GUT's dummy window puts about 1.6")
		return
	RetroPost.apply_dials(mat)
	var pushed = mat.get_shader_parameter("pixel_scale")
	assert_eq(typeof(pushed), TYPE_FLOAT, "HIGH FIDELITY: apply_dials pushes pixel_scale as a float")
	if typeof(pushed) != TYPE_FLOAT:
		return
	assert_eq(float(pushed), roundf(float(pushed)), "HIGH FIDELITY: the dither cell is a whole number of render pixels")
	assert_true(absf(float(pushed) - ratio) <= 0.5,
		"HIGH FIDELITY: the dither cell (%s px) must span the render pixels under one canvas pixel (%.2f)" % [pushed, ratio])

## The pixelation no-op is authored in TWO places that must agree: ui.tscn's render_scale on the shipped overlay and
## retro_post.gd's PIXELATION_CELLS, which the poll pushes every frame in RETRO. Any other count re-samples the
## shipped RETRO frame: the just-above-the-buffer comb post_process.gdshader's render_scale note warns about.
func test_the_poll_leaves_the_authored_pixelation_untouched() -> void:
	var authored_mat := _authored_post_material(UI_SCENE_PATH)
	if authored_mat == null:
		return
	var authored = authored_mat.get_shader_parameter("render_scale")
	assert_eq(typeof(authored), TYPE_FLOAT, "ui.tscn authors a render_scale on the in-game overlay")
	if typeof(authored) != TYPE_FLOAT:
		return
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT  # RETRO's stretch
	var mat := _fresh_post_material()
	RetroPost.apply_dials(mat)
	var pushed = mat.get_shader_parameter("render_scale")
	assert_eq(typeof(pushed), TYPE_FLOAT, "apply_dials pushes render_scale")
	if typeof(pushed) == TYPE_FLOAT:
		assert_almost_eq(float(pushed), float(authored), 0.01,
			"RETRO: the per-frame push must equal ui.tscn's authored render_scale, or the poll re-pixelates the shipped frame")

## HIGH FIDELITY's buffer is the NATIVE window, so the authored cell count can land just above the buffer width: the
## comb zone, which crawls on fences and railings. The downscale must sit at least 2x the native width there, and
## never below the authored no-op.
func test_high_fidelity_lifts_the_downscale_clear_of_the_comb() -> void:
	var root := get_tree().root
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS  # HIGH FIDELITY's stretch
	if root.size.x <= root.get_visible_rect().size.x:
		pending("this window is no wider than the canvas, so there is no native buffer to clear; headless GUT's dummy window is")
		return
	var mat := _fresh_post_material()
	RetroPost.apply_dials(mat)
	var pushed = mat.get_shader_parameter("render_scale")
	assert_eq(typeof(pushed), TYPE_FLOAT, "apply_dials pushes render_scale")
	if typeof(pushed) != TYPE_FLOAT:
		return
	assert_true(float(pushed) >= 2.0 * float(root.size.x),
		"HIGH FIDELITY: %s cells for a %d px native buffer sits inside the comb zone (needs at least 2x)" % [pushed, root.size.x])
	assert_true(float(pushed) >= RetroPost.PIXELATION_CELLS,
		"HIGH FIDELITY never downscales coarser than RETRO's authored no-op")


# =============================================================================================================
# The hosts — both screens that wear the overlay obey the player's look dials every frame
# =============================================================================================================

## ⭐THE BOOT SCREEN IS NOT DRIVEN BY THE PLAYER. computerroom.tscn wears its own copy of the shader with no Player
## in the scene, so before the shared dials existed the Dithering slider did nothing on the first thing a player
## sees. Driven on the real authored scene: the host finds the overlay under its own CanvasLayer and pushes the
## player's dials onto it each frame. Instantiated off-tree (no _ready, no menu, no audio); the overlay gets a fresh
## material so the cached scene's shared one is never written.
func test_the_boot_screen_obeys_the_players_look_dials() -> void:
	var scene := load(BOOT_SCENE_PATH) as PackedScene
	assert_true(scene != null, "computerroom.tscn must load")
	if scene == null:
		return
	var room = scene.instantiate()
	var rect := room.get_node_or_null("CanvasLayer/ColorRect") as ColorRect
	assert_true(rect != null and rect.material is ShaderMaterial, "the boot screen authors its overlay ColorRect under CanvasLayer")
	if rect == null:
		room.free()
		return
	var mat := _fresh_post_material()
	rect.material = mat
	room.canvas_layer = room.get_node("CanvasLayer")
	room.monitor_glow = room.get_node("computer/MonitorGlow")
	room.world_environment = room.get_node("WorldEnvironment")
	room._resolve_post_material()
	_assert_host_obeys_player_dials("computerroom (boot screen)", mat, Callable(room, "_process").bind(0.0))
	room.free()

## The in-game overlay: the Player's post-process driver pushes the same dials through the same helper. A bare
## off-tree Player at full health, so the per-frame update touches the overlay and returns before the heartbeat.
func test_the_in_game_overlay_obeys_the_players_look_dials() -> void:
	var player = load(PLAYER_PATH).new()
	var rect := ColorRect.new()
	var mat := _fresh_post_material()
	rect.material = mat
	player._post_rect = rect
	player.hp = player.max_hp
	_assert_host_obeys_player_dials("player overlay", mat, Callable(player, "_update_low_hp").bind(0.0))
	rect.free()
	player.free()

## The boot screen is the FIRST thing a player sees, so its authored baseline has to be the game's: the dither cell
## is derived from the downscale grid, so a coarser render_scale there does not just pixelate the room, it makes
## the DITHER visibly chunkier than every other screen (the room once shipped at render_scale 320 against the
## overlay's 1584). color_steps and bayer_order are never pushed by apply_dials, so only the scenes keep those equal.
## render_scale IS overwritten by the per-frame poll (cells_for_presentation), so its authored copy only governs
## the editor preview and the frame before the first poll; it is still compared so both scenes stay on the
## PIXELATION_CELLS the poll pushes in RETRO.
func test_the_boot_screen_matches_the_games_authored_retro_baseline() -> void:
	var boot := _authored_post_material(BOOT_SCENE_PATH)
	var game := _authored_post_material(UI_SCENE_PATH)
	if boot == null or game == null:
		return
	for param in ["render_scale", "color_steps", "bayer_order"]:
		var want = game.get_shader_parameter(param)
		assert_true(want != null, "ui.tscn authors %s on the in-game overlay (the reference baseline)" % param)
		assert_eq(boot.get_shader_parameter(param), want,
			"computerroom.tscn must author the same %s as ui.tscn: a different value reads as a different dither on the first screen" % param)


# =============================================================================================================
# The menu seam
# =============================================================================================================

## The Colour Depth row is NO LONGER an Options row (2026-09-16): a seven-step depth cycler beside Dithering, Ink
## Outline and Muzzle Smoke read as a developer panel, not a player setting. The Settings field, its setter and
## the captions all survive (the value still loads/saves and the cycler builder still exists for a future skin
## or debug surface), but the catalog must not list it — pinned so nobody restores it by accident.
func test_the_options_row_is_deliberately_absent() -> void:
	var cat := load(CATALOG_PATH) as SettingsCatalog
	assert_not_null(cat, "the settings catalog must load")
	if cat == null:
		return
	for spec in cat.specs:
		if spec != null:
			assert_ne(spec.key, &"color_quantization", "Colour Depth is not a player-facing Options row")
	assert_true(Settings.has_method("set_color_quantization"), "the setting itself survives (saved/loaded, just not on the menu)")

## ARRAY ORDER IS BEHAVIOUR: the chooser maps the raw INDEX straight into COLOR_QUANTIZE_LEVELS, so caption N is
## depth N. A caption list SHORTER than the table does not error (the row clamps its index), it paints the last
## caption again for every depth past the end: the "the last option does nothing" bug. So the chooser is built once
## per depth and every depth must paint a caption of its own.
## A caption list LONGER than the table is the mirror bug (a caption offered for a depth with no table row, which
## the setter clamps straight back to the last depth), so one index past the end is staged too: the row clamps it
## to items.size() - 1, and only a list exactly as long as the table repaints the LAST depth's caption there.
## The index is staged as a FIELD write (restored by after_each); the cycler buttons are never pressed, because
## _cycle_option -> _stage calls the persisting setter and would rewrite user://settings.cfg.
func test_every_depth_has_a_caption() -> void:
	var menu = load(OPTIONS_PATH).new()
	assert_true(menu.has_method("_emit_color_quantization"), "OptionsMenu still builds the Colour Depth chooser")
	if not menu.has_method("_emit_color_quantization"):
		menu.free()
		return
	var spec := SettingSpec.new()
	spec.key = &"color_quantization"
	spec.getter = &"color_quantization"
	spec.setter = &"set_color_quantization"
	var shown := {}
	for depth in SettingsScript.COLOR_QUANTIZE_LEVELS.size():
		Settings.color_quantization = depth
		var parent := VBoxContainer.new()
		var value_btn := menu._emit_color_quantization(parent, spec) as Button
		var caption := value_btn.text if value_btn != null else ""
		assert_false(caption.is_empty(), "depth %d paints a caption" % depth)
		assert_false(shown.has(caption),
			"depth %d paints '%s', already shown for depth %s: the caption list is shorter than the table" % [depth, caption, shown.get(caption)])
		shown[caption] = depth
		parent.free()
	var depths: int = SettingsScript.COLOR_QUANTIZE_LEVELS.size()
	Settings.color_quantization = depths
	var past_parent := VBoxContainer.new()
	var past_btn := menu._emit_color_quantization(past_parent, spec) as Button
	var past_caption := past_btn.text if past_btn != null else ""
	assert_eq(shown.get(past_caption, -1), depths - 1,
		"index %d (one past the %d-row table) paints '%s': it must clamp onto the last depth's caption, or the caption list is longer than the table" % [depths, depths, past_caption])
	past_parent.free()
	menu.free()


# =============================================================================================================
# The debug seam
# =============================================================================================================

## Both debug front-ends go registry -> validate -> the row's action module -> run(), so that is how this is
## driven: the row exists, a depth index is a legal call, it routes to the WORLD actions on the same F1 page as
## `dither`, and running it moves the live depth.
##
## ⭐THE FIELD, NEVER THE SETTER: every Settings setter persists, and a debug command that leaves someone's real
## settings.cfg at 3-bit after they close the console is this project's own documented trap. So the live depth
## must change while user://settings.cfg stays byte-for-byte what it was.
func test_the_quantize_command_is_registered_and_handled() -> void:
	var row := Commands.find("quantize")
	assert_false(row.is_empty(), "`quantize` is a registered debug command")
	if row.is_empty():
		return
	assert_eq(row["mod"], &"world", "`quantize` routes to DebugActionsWorld, the module that handles it")
	assert_eq(row["category"], Commands.find("dither").get("category"), "`quantize` sits on the same F1 page as `dither`")
	assert_true(bool(Settings.get(&"_loaded")),
		"precondition: the Settings autoload has loaded, so a setter call WOULD rewrite settings.cfg and the byte check below is live")

	var snap := _snapshot_real_cfg()
	var stored := ConfigFile.new()
	var stored_depth := -1
	if bool(snap["exists"]) and stored.load(String(snap["path"])) == OK:
		stored_depth = int(stored.get_value("video", "color_quantization", -1))
	var want := -1
	for candidate in [6, 2, 7]:
		if candidate != Settings.color_quantization and candidate != stored_depth:
			want = candidate
			break
	var args := PackedStringArray([str(want)])
	assert_eq(Commands.validate(row, args), "", "a depth index is a legal `quantize` call")
	var out := WorldActions.run("quantize", _console_ctx(), args)
	assert_false(out.is_empty(), "`quantize %d` reports what it did" % want)
	assert_false("\n".join(out).contains("not a world command"), "DebugActionsWorld handles `quantize` (no drift warning)")
	assert_eq(Settings.color_quantization, want, "`quantize %d` moves the live colour depth" % want)
	_assert_real_cfg_untouched(snap, "`quantize` must set the FIELD only: running it rewrote user://settings.cfg")

## A depth outside the table is refused and leaves the live depth alone: the console lets any NUMBER through
## validation, so this refusal is the only thing between a typo and a garbage index. Control: the same call with
## the coarsest real depth is accepted.
func test_the_quantize_command_refuses_a_depth_outside_the_table() -> void:
	var count := SettingsScript.COLOR_QUANTIZE_LEVELS.size()
	var snap := _snapshot_real_cfg()
	Settings.color_quantization = 3
	for bad in [str(count), "-1"]:
		var out := WorldActions.run("quantize", _console_ctx(), PackedStringArray([bad]))
		assert_false(out.is_empty(), "`quantize %s` explains the refusal instead of silently doing nothing" % bad)
		assert_eq(Settings.color_quantization, 3, "`quantize %s` leaves the live depth where it was" % bad)
	WorldActions.run("quantize", _console_ctx(), PackedStringArray([str(count - 1)]))
	assert_eq(Settings.color_quantization, count - 1, "control: the coarsest real depth is accepted by the same call")
	_assert_real_cfg_untouched(snap, "`quantize` must set the FIELD only: running it rewrote user://settings.cfg")
