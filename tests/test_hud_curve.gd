extends GutTest

## CURVED HUD GLASS — the corner instrument panel rendered through a SubViewport and composited back with a
## cylindrical warp (resources/shaders/hud_curve.gdshader, driven by ui.gd._apply_hud_curve), so the panel
## wraps TOWARD the viewer at its edges — the inside of a curved monitor, not the outside of a CRT bulge.
##
## ⭐WHAT THIS SUITE CAN AND CANNOT SEE. --headless runs a dummy rasterizer that NEVER COMPILES A SHADER, so a
## broken hud_curve.gdshader load()s perfectly clean and every assertion below still passes. Nothing here can
## see a curve. What it CAN do is guard the two failure modes that are otherwise silent:
##   1. SOURCE-TEXT pins on the shader — the uniforms code pushes still exist under those names, the
##      premultiplied blend mode is still declared, the sampler still refuses to repeat, and no default
##      contains arithmetic (which fails the WHOLE compile and draws a fallback material instead) — and
##      the HIGH FIDELITY twin (HF_SHADER_PATH) still matches this file line for line outside comments.
##   2. STRUCTURE — the carrier really moves into the viewport when the bend is on and really comes back out
##      at 0, so "off" is the pre-curve tree rather than an identity pass nobody notices they are paying for.
## The look itself is verified by EYE through scripts/tools/hud_curve_qa_shots.gd, a real windowed GPU run.

const SHADER_PATH := "res://resources/shaders/hud_curve.gdshader"
## THE TWIN. Filter hints are COMPILE-TIME, so the HIGH FIDELITY presentation (native-res curve viewport,
## where a nearest tap at the warp's non-integer offsets stairsteps every bowed line) ships as a sibling
## file with `filter_linear` on hud_tex; ui.gd._apply_hud_curve swaps the two live by presentation. Both
## headers promise "ANY edit to this shader must land in BOTH files" — test_the_hf_twin_has_not_forked is
## what holds them to it.
const HF_SHADER_PATH := "res://resources/shaders/hud_curve_hf.gdshader"
const UI_PATH := "res://scripts/ui/ui.gd"

## Every uniform ui.gd pushes onto the curve material. A rename on either side is invisible at runtime —
## set_shader_parameter on an unknown name is a silent no-op — so this list is the contract.
const PUSHED_UNIFORMS := ["hud_tex", "curve", "edge_fade", "chroma"]

var _saved_amount: float
var _saved_ratio: float
var _saved_fade: float
var _saved_chroma: float
var _saved_scale: float


func before_each() -> void:
	# GameSettings.hud is a SHARED preloaded resource and Settings is an autoload: mutating either leaks into
	# every later test in the run. Snapshot and restore. ⭐The plain var is assigned directly and never through
	# Settings.set_hud_curve_scale(), because that setter calls save_settings() and would rewrite the
	# developer's real user://settings.cfg from a test run.
	_saved_amount = GameSettings.hud.hud_curve_amount
	_saved_ratio = GameSettings.hud.hud_curve_axis_ratio
	_saved_fade = GameSettings.hud.hud_curve_edge_fade
	_saved_chroma = GameSettings.hud.hud_curve_chroma
	_saved_scale = Settings.hud_curve_scale


func after_each() -> void:
	GameSettings.hud.hud_curve_amount = _saved_amount
	GameSettings.hud.hud_curve_axis_ratio = _saved_ratio
	GameSettings.hud.hud_curve_edge_fade = _saved_fade
	GameSettings.hud.hud_curve_chroma = _saved_chroma
	Settings.hud_curve_scale = _saved_scale


func _read(path: String) -> String:
	var s := FileAccess.get_file_as_string(path)
	assert_false(s.is_empty(), "%s must be readable" % path)
	return s


# === the shader, by source text (the only headless guard there is) ===========================================

func test_every_uniform_the_code_pushes_is_declared() -> void:
	var src := _read(SHADER_PATH)
	var decl := RegEx.new()
	decl.compile("(?m)^\\s*uniform\\s+\\w+\\s+(\\w+)")
	var declared := PackedStringArray()
	for m in decl.search_all(src):
		declared.append(m.get_string(1))
	assert_gt(declared.size(), 0, "found no uniform declarations — the regex has drifted")
	for uname in PUSHED_UNIFORMS:
		assert_true(declared.has(uname),
			"hud_curve.gdshader must declare uniform '%s' — ui.gd._apply_hud_curve pushes it, and pushing a name the shader does not declare is a SILENT no-op: the curve would simply stop responding to its knob with nothing logged. Declared: %s"
				% [uname, ", ".join(declared)])


func test_the_premultiplied_blend_mode_is_declared() -> void:
	var src := _read(SHADER_PATH)
	assert_true(src.contains("render_mode blend_premul_alpha;"),
		"hud_curve.gdshader must declare `render_mode blend_premul_alpha;`. A Viewport render target stores PREMULTIPLIED alpha (measured on 4.7.1: red at alpha 0.5 reads back (0.498, 0, 0, 0.498)), and compositing that under the default mix blend multiplies by alpha a SECOND time — every partially-transparent HUD pixel lands ~25% too dark while opaque ones are untouched, which reads as dark halos around the glyphs rather than as a dim HUD.")


func test_the_sampler_refuses_to_repeat_and_stays_nearest() -> void:
	var src := _read(SHADER_PATH)
	var decl := RegEx.new()
	decl.compile("uniform\\s+sampler2D\\s+hud_tex\\s*:([^;]*);")
	var m := decl.search(src)
	assert_not_null(m, "hud_tex must be declared as a hinted sampler2D")
	if m == null:
		return
	var hints := m.get_string(1)
	assert_true(hints.contains("repeat_disable"),
		"hud_tex must carry repeat_disable: a barrel warp ALWAYS samples outside 0..1 near the edges, and with repeat ENABLED the opposite side of the HUD wraps into the swept-out corners. Hints found: '%s'" % hints)
	assert_true(hints.contains("filter_nearest"),
		"hud_tex must carry filter_nearest, and the uniform hint is what actually decides it — it outranks the node's texture_filter, and the project sets no default_texture_filter, so the engine default (LINEAR) would otherwise soften the entire HUD. Hints found: '%s'" % hints)


func test_uniform_defaults_are_literal_constants() -> void:
	# The test_ink_outline / test_color_quantization guard, applied to this shader: Godot will not fold
	# arithmetic in a uniform initializer, and one such default fails the WHOLE shader to compile — which
	# draws a fallback material, i.e. a solid rectangle over the HUD, not a missing effect.
	var decl := RegEx.new()
	decl.compile("(?m)^\\s*uniform\\s+\\w+\\s+(\\w+)[^=\\n]*=\\s*([^;]+);")
	var arith := RegEx.new()
	arith.compile("[\\d\\)]\\s*[/*+\\-]")
	var checked := 0
	for m in decl.search_all(_read(SHADER_PATH)):
		checked += 1
		assert_null(arith.search(m.get_string(2)),
			"hud_curve.gdshader: uniform '%s' has arithmetic in its default ('%s'). Write the literal and put the maths in a comment."
				% [m.get_string(1), m.get_string(2).strip_edges()])
	assert_gt(checked, 0, "found no uniform defaults to check — the declaration regex has drifted")


func test_the_bend_is_concave_cross_coupled_and_fitted() -> void:
	# Three properties of warp(), each of which is a different bug if it drifts:
	#   CROSS-COUPLED — x bent by y*y and y by x*x. A radial dot(d, d) term instead bends both axes at once
	#     and always reads as a fisheye, never as a monitor curved about one axis.
	#   CONCAVE — the MINUS sign. Flip it and the panel bulges outward like a CRT face, which is the exact
	#     thing this was corrected away from; it looks plausible in a still and wrong in motion.
	#   FITTED — divided by the bend at the extreme, which pins the corners. Without it a concave panel
	#     projects to a pincushion whose corners flare OUT, and the bottom-left HP bar leaves the canvas.
	var src := _read(SHADER_PATH)
	assert_true(src.contains("vec2 bend = vec2(1.0 - c.x * d.y * d.y, 1.0 - c.y * d.x * d.x);"),
		"hud_curve.gdshader's warp() must bend each axis by the SQUARE OF THE OTHER, with a MINUS sign: 'vec2 bend = vec2(1.0 - c.x * d.y * d.y, 1.0 - c.y * d.x * d.x);'. A plus sign turns the panel convex (the outside of a CRT bulge); a radial dot(d, d) term turns it into a fisheye.")
	assert_true(src.contains("return (d * bend / (vec2(1.0) - c)) * 0.5 + vec2(0.5);"),
		"hud_curve.gdshader's warp() must divide by the bend at the extreme ('/ (vec2(1.0) - c)') so the panel is FITTED and its corners are pinned to the screen corners. Drop that and a concave bend flares the corners outward, pushing the bottom-left HP bar off the canvas.")


## The twin rule, mechanised. Returns PATH's code as {n: line number, s: text} rows: comment-only and blank
## lines dropped (each twin's header paragraph is the one PROSE difference allowed), and the hud_tex filter
## hint — the one CODE difference allowed — replaced by a placeholder after asserting the file carries ITS
## OWN hint. Everything left must match the sibling byte for byte.
func _twin_code_lines(path: String, own_filter: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var lines := _read(path).replace("\r\n", "\n").split("\n")
	var sampler_seen := false
	for i in lines.size():
		var line: String = lines[i]
		var stripped := line.strip_edges()
		if stripped.is_empty() or stripped.begins_with("//"):
			continue
		if line.contains("sampler2D hud_tex"):
			assert_true(line.contains(own_filter),
				"%s must hint hud_tex with %s — that hint IS the point of having two files: compile-time nearest keeps the RETRO logical-res target crunchy, linear keeps the HIGH FIDELITY native-res warp from stairstepping. Line: '%s'"
					% [path, own_filter, line.strip_edges()])
			line = line.replace(own_filter, "<own_filter>")
			sampler_seen = true
		rows.append({"n": i + 1, "s": line})
	assert_true(sampler_seen,
		"%s must declare the hud_tex sampler — without it the twin diff is vacuous" % path)
	return rows


func test_the_hf_twin_has_not_forked() -> void:
	var retro := _twin_code_lines(SHADER_PATH, "filter_nearest")
	var hf := _twin_code_lines(HF_SHADER_PATH, "filter_linear")
	# Fail on the FIRST drifted line, naming both sides — a whole-file dump would bury the one line that moved.
	for i in mini(retro.size(), hf.size()):
		if retro[i]["s"] != hf[i]["s"]:
			assert_eq(retro[i]["s"], hf[i]["s"],
				"TWIN DRIFT between hud_curve.gdshader:%d and hud_curve_hf.gdshader:%d. These files are TWINS — byte-identical except each one's own header paragraph and the hud_tex filter hint (filter_nearest RETRO / filter_linear HIGH FIDELITY; ui.gd._apply_hud_curve swaps them by presentation) — so an edit that landed in only one of them has FORKED the two presentations. Port the edit to the sibling; never let them diverge."
					% [retro[i]["n"], hf[i]["n"]])
			return
	assert_eq(retro.size(), hf.size(),
		"hud_curve.gdshader has %d code lines but hud_curve_hf.gdshader has %d — their common prefix matches, so code was ADDED or REMOVED at the tail of one file only. The twins must stay byte-identical outside comments and the hud_tex filter hint; port the edit to the sibling."
			% [retro.size(), hf.size()])


# === the drive, by source text ===============================================================================

func test_ui_polls_the_curve_every_frame() -> void:
	var src := _read(UI_PATH)
	assert_true(src.contains("\t_apply_hud_curve()\n\t_update_hud_sway(delta)"),
		"ui.gd._process must call _apply_hud_curve() each frame — the Options row is applied live, and without the poll the bend would freeze at whatever it was when the HUD was built.")
	assert_eq(src.count("_apply_hud_curve()"), 3,
		"expected exactly three _apply_hud_curve() call sites (its own definition, _ready, _process) — a fourth caller means the on/off decision has escaped the one function that owns it.")


# === structure: off is the OLD TREE, not an identity pass ====================================================

## A LIVE UI layer. Adding it to the tree RUNS _ready, which builds the real carrier and stands the real
## curve up — so these tests drive the shipping path. (A hand-made stub carrier assigned over `_weighted`
## afterwards would only ever prove that the stub moved, while _ready's real carrier sat in the viewport
## behind it: that mistake fails as "the carrier must render INSIDE the curve viewport", which is exactly
## the assertion you would then be tempted to weaken.)
func _live_ui() -> UI:
	var ui := UI.new()
	add_child_autofree(ui)
	assert_not_null(ui._weighted, "precondition: _ready must have built the HUD-weight carrier")
	return ui


func test_the_carrier_moves_into_the_viewport_when_the_bend_is_on() -> void:
	var ui := _live_ui()
	GameSettings.hud.hud_curve_amount = 0.05
	Settings.hud_curve_scale = 1.0
	ui._apply_hud_curve()
	assert_not_null(ui._curve_viewport, "a non-zero bend must stand the curve viewport up")
	assert_true(ui._weighted.get_parent() is SubViewport,
		"the carrier must render INSIDE the curve viewport — that is the whole mechanism; left on the layer it would draw flat and the composite would sample an empty target.")
	assert_not_null(ui._curve_rect, "the composite rect must exist to draw the viewport back")
	assert_eq(ui._curve_rect.get_parent(), ui,
		"the composite must be a DIRECT child of the layer: hide_hud_for_death sweeps direct CanvasItem children, and that sweep is what takes the panel down for the death cinematic.")


func test_zero_tears_it_back_down_to_the_plain_tree() -> void:
	var ui := _live_ui()
	GameSettings.hud.hud_curve_amount = 0.05
	Settings.hud_curve_scale = 1.0
	ui._apply_hud_curve()
	assert_true(ui._weighted.get_parent() is SubViewport, "precondition: the bend is on")
	Settings.hud_curve_scale = 0.0
	ui._apply_hud_curve()
	assert_eq(ui._weighted.get_parent(), ui,
		"at strength 0 the carrier must be a plain direct child again — OFF is the pre-curve tree, not an identity shader pass the player still pays for.")
	assert_null(ui._curve_viewport, "the viewport must be released at 0, not merely idled")
	assert_null(ui._curve_rect, "the composite must be released at 0")


func test_either_half_at_zero_means_off() -> void:
	var ui := _live_ui()
	# The authored ceiling at zero.
	GameSettings.hud.hud_curve_amount = 0.0
	Settings.hud_curve_scale = 1.0
	ui._apply_hud_curve()
	assert_null(ui._curve_viewport, "an authored amount of 0 means off however the player's dial is set")
	# The player's dial at zero.
	GameSettings.hud.hud_curve_amount = 0.05
	Settings.hud_curve_scale = 0.0
	ui._apply_hud_curve()
	assert_null(ui._curve_viewport, "a player dial of 0 means off however the amount is authored")


func test_a_bare_ui_never_added_to_the_tree_survives_the_poll() -> void:
	# Several suites build a bare UI.new() and call its visibility methods WITHOUT ever adding it to the tree,
	# so _ready never runs and `_weighted` stays null. The poll runs from _process and must not deref it, nor
	# call get_viewport() on a node with no viewport — that guard is load-bearing, not defensive habit
	# (ui.gd's own rule for `_minimap` / `_clock`).
	var ui: UI = autofree(UI.new())
	assert_false(ui.is_inside_tree(), "precondition: never parented, so _ready never ran")
	assert_null(ui._weighted, "precondition: no carrier without _ready")
	ui._apply_hud_curve()
	assert_null(ui._curve_viewport, "a UI that never ran _ready must build nothing")


# === the knobs ===============================================================================================

func test_hud_settings_curve_defaults() -> void:
	var h := HudSettings.new()
	assert_gt(h.hud_curve_amount, 0.0, "the curve ships ON — it is the feature, and 0 would make it invisible")
	assert_lte(h.hud_curve_amount, 0.2,
		"the shipped bend must stay under the point where the panel stops reading as a screen and starts reading as a tube")
	assert_almost_eq(h.hud_curve_axis_ratio, 0.0, 0.001,
		"ships CYLINDRICAL — a monitor curved about a vertical axis, so horizontal lines bow and every vertical stays dead straight. 1.0 would be the spherical/fishbowl bend, which is not the shape this was asked for.")
	assert_almost_eq(h.hud_curve_chroma, 0.0, 0.001,
		"the lens fringe ships OFF: it fringes the anti-aliased edge of every glyph as well as the colour, which on a text-heavy panel reads as blur")
	assert_gte(h.hud_curve_edge_fade, 0.0, "edge fade is a 0..1 fraction")
	assert_lte(h.hud_curve_edge_fade, 1.0, "edge fade is a 0..1 fraction")


func test_settings_hud_curve_scale_default_full_and_clamps() -> void:
	var s = load("res://managers/Settings.gd").new()
	assert_almost_eq(s.hud_curve_scale, 1.0, 0.001, "the player dial defaults to the full authored bend")
	s.hud_curve_scale = clampf(2.5, 0.0, 1.0)
	assert_almost_eq(s.hud_curve_scale, 1.0, 0.001, "clamps above 1")
	s.hud_curve_scale = clampf(-3.0, 0.0, 1.0)
	assert_almost_eq(s.hud_curve_scale, 0.0, 0.001, "clamps below 0")
	s.free()


func test_the_options_row_exists_and_binds() -> void:
	var cat = load("res://resources/settings/SettingsCatalog.tres")
	var row = null
	for spec in cat.specs:
		if spec.key == &"hud_curve":
			row = spec
			break
	assert_not_null(row, "a 'hud_curve' row must be listed in SettingsCatalog.specs — a sub_resource that is not in that array is invisible in the menu")
	if row == null:
		return
	assert_eq(row.tab, &"Accessibility",
		"the curve belongs on Accessibility with ps1_warp / view_bob / hud_sway: a warped panel is a motion-comfort setting, not a video-quality one")
	assert_eq(row.getter, &"hud_curve_scale", "the row must read the Settings var")
	assert_eq(row.setter, &"set_hud_curve_scale", "the row must write through the Settings setter")
	assert_true(Settings.has_method("set_hud_curve_scale"), "the setter the row names must exist on Settings")
