extends GutTest
## Colour Depth (Options -> Video) — the screen post-process's colour quantiser.
##
## WHAT IT IS. `post_process.gdshader` snaps every finished frame onto a colour grid. It always did, with one
## scalar `color_steps` authored per material; this feature makes the grid a PLAYER choice and makes it
## PER-CHANNEL, so the depths that actually existed in hardware can be named: RGB565 gives green the odd bit,
## RGB332 starves blue. Settings owns the table (index -> per-channel step count), player.gd pushes the chosen
## row onto the live material every frame as `quantize_levels`, and the shader falls back to the material's own
## `color_steps` when nobody is driving it.
##
## WHY THESE TESTS LOOK LIKE THIS. Headless runs a DUMMY rasterizer and NEVER compiles a .gdshader: a shader
## with a hard syntax error load()s clean, reads back fine, and passes every behavioural test in the suite. So
## the shader half can only be guarded by GREPPING ITS SOURCE — hence the pins below on the uniform, on the
## fallback expression, and on the vec3-ness of the quantise itself. The half that CAN be checked properly is
## the table, which is why the mode -> levels mapping is a pure static on Settings rather than a switch inside
## the shader: the numbers the GPU is handed are the numbers asserted here.
##
## The real look check is a windowed run — see scripts/tools/color_depth_qa_shots.gd, which counts the DISTINCT
## COLOURS in a captured frame per depth. That is the one claim about this feature a screenshot can settle.

const SHADER_PATH := "res://resources/shaders/post_process.gdshader"
const SETTINGS_PATH := "res://managers/Settings.gd"
const PLAYER_PATH := "res://scripts/player/player.gd"
## The shared presentation dials both retro hosts push (scripts/ui/retro_post.gd) — the in-game overlay on
## the Player's ColorRect and the BOOT SCREEN's own copy in computerroom.tscn, which has no Player at all.
const RETRO_POST_PATH := "res://scripts/ui/retro_post.gd"
const BOOT_SCENE_PATH := "res://scenes/computerroom.tscn"
const OPTIONS_PATH := "res://scripts/ui/options_menu.gd"
const CATALOG_PATH := "res://resources/settings/SettingsCatalog.tres"
const UI_SCENE_PATH := "res://scenes/player/ui.tscn"

const SettingsScript := preload("res://managers/Settings.gd")

func _read(path: String) -> String:
	var s := FileAccess.get_file_as_string(path)
	assert_false(s.is_empty(), "%s must be readable" % path)
	return s


# =============================================================================================================
# The table — the only part of this feature a headless run can actually evaluate
# =============================================================================================================

## Index 0 is not a depth, it is the "leave it alone" sentinel. It has to stay Vector3.ZERO, because that exact
## value is what the shader tests for before falling back to the material's authored `color_steps` — and it has
## to stay index 0, because that is the shipped default and therefore the frame everyone already has.
func test_the_default_index_is_the_leave_it_authored_sentinel() -> void:
	assert_eq(SettingsScript.COLOR_QUANTIZE_LEVELS[0], Vector3.ZERO,
		"index 0 must be Vector3.ZERO — the sentinel post_process.gdshader tests for (`quantize_levels.r > 0.0`) before falling back to the material's own color_steps")
	var fresh = SettingsScript.new()
	assert_eq(fresh.color_quantization, 0,
		"Colour Depth must SHIP on the sentinel: any other default changes the look of the game on the first frame of every existing save, which is not a thing a new option gets to do")
	fresh.free()

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

## Persistence: the key lives in [video] beside the other look dials, and it must be written AND read back.
## A setting saved but never loaded is the classic half-wiring — it works all session and forgets on restart.
func test_the_setting_round_trips_through_the_video_section() -> void:
	var src := _read(SETTINGS_PATH)
	assert_true(src.contains('cfg.set_value("video", "color_quantization", color_quantization)'),
		"save_settings must write color_quantization under [video] — without this the choice survives exactly one session")
	assert_true(src.contains('cfg.get_value("video", "color_quantization"'),
		"load_settings must read it back from [video], or the saved value is write-only")
	assert_true(src.contains("color_quantization = clampi(int(cfg.get_value"),
		"the load must CLAMP: a cfg written by a build with more depths would otherwise index past the table")


# =============================================================================================================
# The shader seam — source-text pins, because headless never compiles a .gdshader
# =============================================================================================================

## The uniform player.gd writes into. Renaming it in the shader breaks NOTHING loudly: set_shader_parameter on a
## name that does not exist is silently discarded, so the dropdown would simply stop doing anything.
func test_the_shader_declares_the_uniform_player_gd_pushes() -> void:
	var src := _read(SHADER_PATH)
	assert_true(src.contains("uniform vec3 quantize_levels"),
		"post_process.gdshader must declare `uniform vec3 quantize_levels` — player.gd pushes it every frame, and a set_shader_parameter to a missing uniform is silently dropped, so a rename here turns the whole Colour Depth row into a dead control with no error anywhere")

## THE FALLBACK IS THE CONTRACT. Materials nobody drives — computerroom.tscn's CRT wall, this shader on a bare
## quad in the editor — must keep quantising at their authored `color_steps`. That is one expression, and if it
## goes, every un-driven material silently jumps to vec3(0) and divides by zero.
func test_the_shader_falls_back_to_the_authored_color_steps() -> void:
	var src := _read(SHADER_PATH)
	assert_true(src.contains("quantize_levels.r > 0.0 ? quantize_levels : vec3(float(color_steps))"),
		"post_process.gdshader must keep the sentinel fallback — an un-driven material (computerroom.tscn's CRT) has quantize_levels at vec3(0), and without this branch that is a divide by zero across the whole frame instead of the authored look")

## The quantise has to be the VECTOR one. Reverting `steps` to a float would compile, keep every other pin
## green, and quietly collapse RGB565 and RGB332 back onto equal channels — the exact thing this feature adds.
func test_the_quantise_is_per_channel() -> void:
	var src := _read(SHADER_PATH)
	assert_true(src.contains("vec3 steps = quantize_levels.r > 0.0"),
		"the quantise step count must be a vec3 — a float `steps` still compiles and still posterises, it just silently throws away the unequal channels that are the entire point of RGB565 and RGB332")
	assert_true(src.contains("final_color = floor(final_color * steps + threshold) / steps;"),
		"the quantise stays ONE fused floor over the vec3 (dither threshold folded in) — splitting it back into a posterize pass plus a dither pass makes the dither a mathematical no-op, which is what it was before")

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

## The push site. player.gd must hand the shader the LEVELS, never the menu index — the shader has no idea what
## an index is, and pushing one would quantise the frame to 3 steps at "15-bit (PS1)".
func test_player_pushes_the_levels_not_the_index() -> void:
	var src := _read(RETRO_POST_PATH)
	assert_true(src.contains('mat.set_shader_parameter("quantize_levels", Settings.color_quantize_levels(Settings.color_quantization))'),
		"retro_post.gd must push the TABLE LOOKUP, not the raw index — the uniform is a per-channel step count, so pushing the menu index would quantise a '15-bit (PS1)' frame to 3 steps a channel and look like the wrong row entirely")

## The presentation-split compensation uniform (render px per logical canvas px, see Settings.native_scale()).
## Same failure mode as quantize_levels above: player.gd pushes "pixel_scale" every frame, and a
## set_shader_parameter to a missing/renamed uniform is silently dropped — the HIGH FIDELITY dither cell and
## film grain would quietly collapse to native-pixel fine noise with no error anywhere.
func test_the_shader_declares_the_pixel_scale_uniform() -> void:
	var src := _read(SHADER_PATH)
	assert_true(src.contains("uniform float pixel_scale"),
		"post_process.gdshader must declare `uniform float pixel_scale` — the dither-cell/grain compensation player.gd pushes every frame; a rename here is a silently dropped write, so HIGH FIDELITY would ship a dither ~2.4x finer than authored and nothing would catch it")

## ...and the push site must exist too: the uniform alone is a dead knob stuck at its RETRO default 1.0.
func test_player_pushes_pixel_scale() -> void:
	var src := _read(RETRO_POST_PATH)
	assert_true(src.contains('mat.set_shader_parameter("pixel_scale"'),
		"retro_post.apply_dials must push `pixel_scale` — un-pushed, the uniform sits at its RETRO-identity default 1.0 and HIGH FIDELITY's dither cell and grain speckle shrink to one native pixel")


## ⭐BOTH HOSTS MUST GO THROUGH THE HELPER. The boot screen (computerroom.tscn) wears the same shader with no
## Player to drive it, so before the helper existed it obeyed NONE of the player's look rows: the Dithering
## slider did nothing on the first thing a player sees, and the room quantised at its own authored colour
## depth forever. A host that re-inlines its own pushes is that bug coming back silently, so the delegation
## is pinned rather than trusted.
func test_both_retro_hosts_push_through_the_shared_dials() -> void:
	for path in [PLAYER_PATH, "res://scripts/ui/computerroom.gd"]:
		var src := _read(path)
		assert_true(src.contains("RETRO_POST.apply_dials("),
			"%s must push the presentation dials through retro_post.apply_dials() — a private copy is how the boot screen and the game drifted apart in the first place" % path)
		assert_false(src.contains('set_shader_parameter("dither_strength"'),
			"%s must NOT push dither_strength itself — apply_dials owns it, and two writers is two behaviours" % path)


## The boot screen is the FIRST thing a player sees, so its authored baseline has to be the game's baseline:
## the dither cell is derived from the downscale grid, so a coarser render_scale here does not just pixelate
## the room, it makes the DITHER visibly chunkier than every other screen (the reported "the dithering on the
## first screen looks weird" — the room shipped at render_scale 320 against the overlay's 1584).
func test_the_boot_screen_matches_the_games_authored_retro_baseline() -> void:
	var boot := _read(BOOT_SCENE_PATH)
	var ui := _read(UI_SCENE_PATH)
	for line in ["shader_parameter/render_scale = 1584.0", "shader_parameter/color_steps = 16",
			"shader_parameter/bayer_order = 3"]:
		assert_true(ui.contains(line), "ui.tscn should author %s (the reference baseline)" % line)
		assert_true(boot.contains(line),
			"computerroom.tscn must author %s — the boot screen wears the SAME shader, and the dither cell is derived from the downscale grid, so a different value here reads as a different dither on the first screen" % line)

## The pixelation no-op is authored in TWO places that must agree: ui.tscn's shader_parameter/render_scale
## (what RETRO renders with, read as-authored) and player.gd's POST_PIXELATION_CELLS (what the poll pushes in
## RETRO and derives the HIGH FIDELITY floor from). Moving either side alone un-no-ops one of the two modes —
## the exact just-above-the-buffer comb resample post_process.gdshader's render_scale comment documents.
func test_the_authored_pixelation_no_op_and_its_player_mirror_agree() -> void:
	var dials := _read(RETRO_POST_PATH)
	assert_true(dials.contains("const PIXELATION_CELLS := 1584.0"),
		"retro_post.gd must mirror ui.tscn's authored render_scale as `const PIXELATION_CELLS := 1584.0` — the poll pushes it verbatim in RETRO, so any other value here silently changes the shipped RETRO frame")
	var scene := _read(UI_SCENE_PATH)
	assert_true(scene.contains("render_scale = 1584.0"),
		"scenes/player/ui.tscn must author shader_parameter/render_scale = 1584.0 (2x the 792 px RETRO buffer = the documented no-op) — if this was deliberately re-authored, move player.gd's POST_PIXELATION_CELLS in the same change or the two presentation modes disagree about the no-op")


# =============================================================================================================
# The menu seam
# =============================================================================================================

## The row has to exist, sit on Video, and bind the real getter/setter pair — they resolve BY NAME at menu-open,
## so a typo here is a dead row that nothing catches until someone opens Options.
func test_the_options_row_exists_and_binds_the_real_pair() -> void:
	var cat := load(CATALOG_PATH) as SettingsCatalog
	assert_not_null(cat, "the settings catalog must load")
	if cat == null:
		return
	var found: SettingSpec = null
	for spec in cat.specs:
		if spec != null and spec.key == &"color_quantization":
			found = spec
			break
	assert_not_null(found, "Options -> Video must carry a Colour Depth row (the [sub_resource] block AND its entry in the specs array — a block on its own is inert and shows no row)")
	if found == null:
		return
	assert_eq(found.tab, &"Video", "it is a LOOK, not a comfort setting — it belongs on Video beside Ink Outline and Dithering")
	assert_eq(found.getter, &"color_quantization", "bound to the Settings field")
	assert_eq(found.setter, &"set_color_quantization", "...and to its setter")
	assert_false(found.label.is_empty(), "a row with no label is an invisible row")
	assert_eq(found.control, SettingSpec.Widget.CUSTOM,
		"it must stay a CUSTOM code-built chooser: the editor STRIPS a generic DROPDOWN's options on a .tres re-save, which has already left this project with an empty in-game menu twice")
	assert_eq(found.custom_handler, &"_emit_color_quantization",
		"the CUSTOM handler name resolves on OptionsMenu by name — a rename on either side is a row that builds nothing")

## ARRAY ORDER IS BEHAVIOUR: the cycler stages the raw INDEX, so caption N is depth N. A caption list SHORTER
## than the table does not error — _option_row clamps — it just makes the missing depths unreachable from the
## menu, which is the kind of bug that reads as "the last option does nothing".
func test_every_depth_has_a_caption() -> void:
	var src := _read(OPTIONS_PATH)
	assert_true(src.contains("func _emit_color_quantization("),
		"options_menu.gd must define the handler the catalog names")
	var captions := src.count("PlayerText.OPTIONS_CQ_")
	assert_eq(captions, SettingsScript.COLOR_QUANTIZE_LEVELS.size(),
		"the Colour Depth cycler lists %d caption(s) for %d depth(s) — the cycler maps index straight into COLOR_QUANTIZE_LEVELS, so a short list silently makes the deepest rows unreachable (the row clamps, it does not error)"
			% [captions, SettingsScript.COLOR_QUANTIZE_LEVELS.size()])


# =============================================================================================================
# The debug seam
# =============================================================================================================

## Registry rows and action cases are two files that must agree; a row with no case prints "not a world command"
## at runtime and nowhere else. (The console rejects bad arity before the action runs, so the row's arity is the
## contract the action gets to trust.)
func test_the_quantize_command_is_registered_and_handled() -> void:
	var registry := _read("res://scripts/components/debug_commands.gd")
	var actions := _read("res://scripts/components/debug_actions_world.gd")
	assert_true(registry.contains('"name": "quantize", "mod": &"world", "category": "View"'),
		"the `quantize` command must be registered under View, beside `dither` — the F1 menu builds its pages straight from this registry, so one row serves both surfaces")
	assert_true(actions.contains('"quantize": return _cmd_quantize(args)'),
		"debug_actions_world.gd must dispatch it — a registry row with no matching case prints a drift warning at runtime and nothing catches it earlier")
	assert_true(actions.contains('Settings.set(&"color_quantization", want)'),
		"the command must poke the FIELD, not call set_color_quantization: every Settings setter persists, and a debug command that rewrites the player's real settings.cfg is this project's own documented trap")
