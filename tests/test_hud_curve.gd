extends GutTest

## CURVED HUD GLASS — the corner instrument panel rendered through a SubViewport and composited back with a
## cylindrical warp (resources/shaders/hud_curve.gdshader, driven by ui.gd._apply_hud_curve), so the panel
## wraps TOWARD the viewer at its edges — the inside of a curved monitor, not the outside of a CRT bulge.
##
## ⭐WHAT THIS SUITE CAN AND CANNOT SEE. --headless runs a dummy rasterizer that NEVER COMPILES A SHADER, so a
## broken hud_curve.gdshader load()s perfectly clean and no pixel is ever drawn here. What the suite does instead:
##   1. THE SHAPE, EVALUATED — ShaderWarp lifts warp() out of the shader's own source and runs its statements on
##      the CPU through Expression, so "concave, cylindrical, corners pinned" is MEASURED on the code that ships,
##      and on the `curve` value the live UI actually pushed, rather than pinned as a copied line of text.
##   2. THE DRIVE — a live UI (its real _ready) stands the pass up, tears it down, follows the player's dial
##      (Settings.hud_curve_scale) on the next FRAME, and pushes a value for every uniform either twin declares.
##   3. WHAT ONLY TEXT CAN HOLD — the premultiplied blend mode, the sampler's repeat/filter hints, literal uniform
##      defaults (arithmetic fails the WHOLE compile and draws a fallback material instead) and the HIGH FIDELITY
##      twin (HF_SHADER_PATH) matching this file line for line outside comments. Compile-time facts, no headless
##      signal exists for any of them.
## The look itself is verified by EYE through scripts/tools/probes/hud_curve_qa_shots.gd, a real windowed GPU run.

const SHADER_PATH := "res://resources/shaders/hud_curve.gdshader"
## THE TWIN. Filter hints are COMPILE-TIME, so the HIGH FIDELITY presentation (native-res curve viewport,
## where a nearest tap at the warp's non-integer offsets stairsteps every bowed line) ships as a sibling
## file with `filter_linear` on hud_tex; ui.gd._apply_hud_curve swaps the two live by presentation. Both
## headers promise "ANY edit to this shader must land in BOTH files" — test_the_hf_twin_has_not_forked is
## what holds them to it.
const HF_SHADER_PATH := "res://resources/shaders/hud_curve_hf.gdshader"

## A representative authored bend — a test INPUT, not the shipped value (test_hud_settings_curve_defaults owns
## that). Small enough to sit well inside the shader's divide guard, big enough that every shape check is far
## outside EPS.
const BEND := 0.06
const EPS := 0.0005

var _saved_amount: float
var _saved_ratio: float
var _saved_fade: float
var _saved_chroma: float
var _saved_scale: float
var _saved_loaded: bool


## warp() as the shader ships it, evaluated on the CPU. Built from shader SOURCE (not a GDScript copy of the
## maths): each `vec2|float name = expr;` and the final `return expr;` of warp()'s body becomes one Expression,
## with GLSL's vec2 / clamp / min / max / dot routed to the component-wise glsl_* methods below (Godot's own
## clamp/min/max are NOT component-wise on vectors). An algebraically equivalent rewrite measures the same; a
## construct this cannot read leaves `ok` false with the reason in `why`, which fails the test loudly.
class ShaderWarp:
	var ok := false
	var why := ""
	var _params := PackedStringArray()
	var _binds := PackedStringArray()   # the local each statement defines; "" = the return
	var _inputs: Array = []             # the input names each statement was parsed against
	var _exprs: Array[Expression] = []

	func _init(code: String) -> void:
		var comments := RegEx.new()
		comments.compile("//[^\\n]*")
		var src := comments.sub(code, "", true)
		var fn := RegEx.new()
		fn.compile("vec2\\s+warp\\s*\\(([^)]*)\\)\\s*\\{([^}]*)\\}")
		var m := fn.search(src)
		if m == null:
			why = "no `vec2 warp(...) { ... }` (without nested braces) in the shader"
			return
		for p: String in m.get_string(1).split(",", false):
			var words := p.strip_edges().split(" ", false)
			_params.append(words[words.size() - 1])
		if _params.size() != 2:
			why = "warp() is expected to take (vec2 d, float k); found %s" % [_params]
			return
		var glsl_call := RegEx.new()
		glsl_call.compile("\\b(vec2|clamp|min|max|dot)\\s*\\(")
		var local := RegEx.new()
		local.compile("^(?:const\\s+)?(?:vec2|float)\\s+(\\w+)\\s*=\\s*([\\s\\S]+)$")
		var known := PackedStringArray(_params)
		known.append("curve")
		for raw: String in m.get_string(2).split(";", false):
			var stmt := raw.strip_edges()
			if stmt.is_empty():
				continue
			var bind := ""
			var body := ""
			if stmt.begins_with("return "):
				body = stmt.substr(7)
			else:
				var lm := local.search(stmt)
				if lm == null:
					why = "unsupported statement in warp(): '%s'" % stmt
					return
				bind = lm.get_string(1)
				body = lm.get_string(2)
			var e := Expression.new()
			if e.parse(glsl_call.sub(body, "glsl_$1(", true), known) != OK:
				why = "cannot evaluate '%s': %s" % [body, e.get_error_text()]
				return
			_binds.append(bind)
			_inputs.append(known.duplicate())
			_exprs.append(e)
			if bind != "":
				known.append(bind)
		if not _binds.has(""):
			why = "warp() has no return statement"
			return
		ok = true

	## The source point, CENTRED (-1..1 across the panel), that the output point `d` (also centred) samples.
	func centred(curve: Vector2, d: Vector2, k: float = 1.0) -> Vector2:
		var vals := {_params[0]: d, _params[1]: k, "curve": curve}
		for i in _exprs.size():
			var args := []
			for n in _inputs[i]:
				args.append(vals[n])
			var r = _exprs[i].execute(args, self)
			if _exprs[i].has_execute_failed():
				why = "warp() statement %d failed: %s" % [i, _exprs[i].get_error_text()]
				return Vector2(NAN, NAN)
			if _binds[i] == "":
				if not r is Vector2:
					why = "warp() returned %s, not a vec2" % [r]
					return Vector2(NAN, NAN)
				var uv: Vector2 = r
				return (uv - Vector2(0.5, 0.5)) * 2.0
			vals[_binds[i]] = r
		return Vector2(NAN, NAN)

	func glsl_vec2(a, b = null) -> Vector2:
		return Vector2(a, a) if b == null else Vector2(a, b)

	func glsl_clamp(x, lo, hi):
		if x is Vector2:
			var xv: Vector2 = x
			return xv.clamp(_v(lo), _v(hi))
		return clampf(x, lo, hi)

	func glsl_min(a, b):
		if a is Vector2 or b is Vector2:
			return _v(a).min(_v(b))
		return minf(a, b)

	func glsl_max(a, b):
		if a is Vector2 or b is Vector2:
			return _v(a).max(_v(b))
		return maxf(a, b)

	func glsl_dot(a, b) -> float:
		return _v(a).dot(_v(b))

	func _v(a) -> Vector2:
		return a if a is Vector2 else Vector2(a, a)


func before_each() -> void:
	# GameSettings.hud is a SHARED preloaded resource and Settings is an autoload: mutating either leaks into
	# every later test in the run. Snapshot and restore. The plain vars are assigned directly; the ONE test that
	# drives Settings.set_hud_curve_scale() drops Settings._loaded first, because save_settings() refuses while
	# it is false — otherwise the setter would rewrite the developer's real user://settings.cfg from a test run.
	_saved_amount = GameSettings.hud.hud_curve_amount
	_saved_ratio = GameSettings.hud.hud_curve_axis_ratio
	_saved_fade = GameSettings.hud.hud_curve_edge_fade
	_saved_chroma = GameSettings.hud.hud_curve_chroma
	_saved_scale = Settings.hud_curve_scale
	_saved_loaded = Settings._loaded


func after_each() -> void:
	GameSettings.hud.hud_curve_amount = _saved_amount
	GameSettings.hud.hud_curve_axis_ratio = _saved_ratio
	GameSettings.hud.hud_curve_edge_fade = _saved_fade
	GameSettings.hud.hud_curve_chroma = _saved_chroma
	Settings.hud_curve_scale = _saved_scale
	Settings._loaded = _saved_loaded


func _read(path: String) -> String:
	var s := FileAccess.get_file_as_string(path)
	assert_false(s.is_empty(), "%s must be readable" % path)
	return s


func _shader_warp(code: String, label: String) -> ShaderWarp:
	var w := ShaderWarp.new(code)
	assert_true(w.ok,
		"%s: warp() could not be evaluated headless (%s). The bend's shape is measured by running warp()'s own statements; if warp() was restructured, teach ShaderWarp the new construct rather than deleting the shape checks."
			% [label, w.why])
	return w if w.ok else null


## How far the panel's bottom-centre content moves UP under `curve`, as a fraction of the half-height: the
## output row whose sample is exactly the source's bottom edge, found by bisection so nothing here assumes the
## warp's algebra. Positive = tucked in (concave); negative = pushed out past the edge and cropped (convex).
func _bottom_centre_travel(w: ShaderWarp, curve: Vector2) -> float:
	var lo := 0.0
	var hi := 2.0
	for i in 40:
		var mid := (lo + hi) * 0.5
		if w.centred(curve, Vector2(0.0, mid)).y < 1.0:
			lo = mid
		else:
			hi = mid
	return 1.0 - (lo + hi) * 0.5


static func _declared_uniforms(code: String) -> PackedStringArray:
	var decl := RegEx.new()
	decl.compile("(?m)^\\s*uniform\\s+\\w+\\s+(\\w+)")
	var out := PackedStringArray()
	for m in decl.search_all(code):
		out.append(m.get_string(1))
	return out


# === the shader, by source text (compile-time facts with no headless signal) ================================

func test_the_premultiplied_blend_mode_is_declared() -> void:
	var modes := RegEx.new()
	modes.compile("(?m)^\\s*render_mode\\s+([^;]*);")
	var m := modes.search(_read(SHADER_PATH))
	assert_not_null(m, "hud_curve.gdshader must declare a render_mode line")
	if m == null:
		return
	var listed := Array(m.get_string(1).split(",")).map(func(s: String) -> String: return s.strip_edges())
	assert_has(listed, "blend_premul_alpha",
		"hud_curve.gdshader must declare `render_mode blend_premul_alpha`. A Viewport render target stores PREMULTIPLIED alpha (measured on 4.7.1: red at alpha 0.5 reads back (0.498, 0, 0, 0.498)), and compositing that under the default mix blend multiplies by alpha a SECOND time — every partially-transparent HUD pixel lands ~25% too dark while opaque ones are untouched, which reads as dark halos around the glyphs rather than as a dim HUD.")


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


# === the shape, evaluated from the shader's own warp() ======================================================

## Three properties of warp(), each a different bug if it drifts, measured with only the Y bend live (the
## shipped cylinder shape):
##   FITTED — the corners read their own corners. Unfitted, a concave panel projects to a pincushion whose
##     corners flare OUT and the bottom-left HP bar leaves the canvas.
##   CONCAVE — the edge midpoints read BEYOND the panel (a transparent sliver) because the panel's edge content
##     has tucked inward, by the authored fraction of the half-height. A convex (CRT) bend reads inside instead.
##   CYLINDRICAL — every vertical line stays dead straight while horizontal lines bow. A radial dot(d, d) term
##     bends both at once and always reads as a fisheye, never as a monitor curved about one axis.
func test_the_warp_is_a_concave_cylinder_with_its_corners_pinned() -> void:
	var w := _shader_warp(_read(SHADER_PATH), "hud_curve.gdshader")
	if w == null:
		return
	var cyl := Vector2(0.0, BEND)
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var got := w.centred(cyl, corner)
		assert_lt(got.distance_to(corner), EPS,
			"FITTED: the panel corner %s must sample its own corner, but it reads %s — an unfitted concave bend flares the corners outward and pushes the bottom-left HP bar off the canvas" % [corner, got])
	var bottom := w.centred(cyl, Vector2(0.0, 1.0)).y
	var top := w.centred(cyl, Vector2(0.0, -1.0)).y
	assert_gt(bottom, 1.0 + EPS,
		"CONCAVE: the bottom edge's midpoint must read BELOW the panel (a transparent sliver where the edge tucked up), but it reads %.4f — a reading inside the panel is the convex CRT bulge this was corrected away from" % bottom)
	assert_lt(top, -1.0 - EPS,
		"CONCAVE: the top edge's midpoint must read ABOVE the panel, but it reads %.4f" % top)
	assert_almost_eq(_bottom_centre_travel(w, cyl), BEND, 0.001,
		"`curve` is authored as the fraction of the half-height the edge midpoint travels (0.06 = ~13 px on the 792x444 canvas); the evaluated warp moves the bottom-centre content by a different amount, so every authored hud_curve_amount now means something else on screen")
	for dx: float in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		for dy: float in [-1.0, -0.3, 0.4, 1.0]:
			assert_almost_eq(w.centred(cyl, Vector2(dx, dy)).x, dx, EPS,
				"CYLINDRICAL: with only the Y bend live, the vertical line at x=%.1f must stay dead straight (checked at y=%.1f) — a bend that also moves X there reads as a fisheye, not a monitor curved about a vertical axis" % [dx, dy])
	var mid_row_centre := absf(w.centred(cyl, Vector2(0.0, 0.5)).y)
	var mid_row_side := absf(w.centred(cyl, Vector2(1.0, 0.5)).y)
	assert_gt(mid_row_centre, mid_row_side + EPS,
		"CYLINDRICAL: a horizontal line must BOW — halfway down, the centre column must sample further out (%.4f) than the side (%.4f), or the Y bend has stopped bowing horizontal lines at all" % [mid_row_centre, mid_row_side])


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


# === the drive: what a live UI pushes, and when ==============================================================

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


func _pushed_curve(ui: UI) -> Vector2:
	var v = ui._curve_mat.get_shader_parameter("curve") if ui._curve_mat != null else null
	assert_true(v is Vector2, "ui.gd must push `curve` onto the live curve material as a Vector2 (read back: %s)" % [v])
	return v if v is Vector2 else Vector2(NAN, NAN)


func _pushed_float(ui: UI, uname: String) -> float:
	var v = ui._curve_mat.get_shader_parameter(uname) if ui._curve_mat != null else null
	assert_true(v is float, "ui.gd must push `%s` onto the live curve material as a float (read back: %s)" % [uname, v])
	return v if v is float else NAN


## set_shader_parameter on a name the shader does not declare is a SILENT no-op, and a declared uniform nobody
## pushes just sits at its default — so a rename on EITHER side (ui.gd's push or the shader's declaration)
## leaves the curve deaf to its knob with nothing logged. Read the declarations off BOTH twins (the live
## material mounts one or the other by presentation, and ui.gd swaps them without re-pushing anything but
## hud_tex) and demand a pushed value on the live material for every one.
func test_every_uniform_either_twin_declares_is_pushed() -> void:
	GameSettings.hud.hud_curve_amount = BEND
	Settings.hud_curve_scale = 1.0
	var ui := _live_ui()
	ui._apply_hud_curve()
	assert_true(ui._curve_mat != null, "a non-zero bend must build the curve material")
	if ui._curve_mat == null:
		return
	for path: String in [SHADER_PATH, HF_SHADER_PATH]:
		var declared := _declared_uniforms(_read(path))
		assert_gt(declared.size(), 0, "found no uniform declarations in %s — the regex has drifted" % path)
		for uname in declared:
			assert_true(ui._curve_mat.get_shader_parameter(uname) != null,
				"%s declares uniform '%s' but ui.gd never pushed a value for it — a renamed push (or a renamed uniform) leaves that knob silently dead. Declared: %s"
					% [path, uname, ", ".join(declared)])
	assert_eq(ui._curve_mat.get_shader_parameter("hud_tex"), ui._curve_viewport.get_texture(),
		"hud_tex must be the texture of the viewport the carrier renders into — anything else composites an empty or stale target over the HUD's corner")


## The twins exist for ONE reason — the sampler filter is compile-time — so the twin on the live material must
## match the target it samples: a render target bigger than the logical canvas (HIGH FIDELITY, native res) needs
## the linear tap or every bowed line stairsteps; a logical-res target (RETRO) needs nearest or the whole panel
## softens. A headless run still has a real root Window, but it only ever sits in ONE presentation (whatever the
## developer's settings.cfg says), so BOTH are driven here by flipping the property Settings.apply_video flips —
## Window.content_scale_mode — on a window twice the canvas, and the per-frame poll must follow every flip on the
## same live UI: RETRO -> HIGH FIDELITY -> back to RETRO. The window is restored before anything is asserted.
func test_the_mounted_twin_filters_to_match_the_render_target() -> void:
	GameSettings.hud.hud_curve_amount = BEND
	Settings.hud_curve_scale = 1.0
	var win := get_window()
	var saved_mode := win.content_scale_mode
	var saved_size := win.size
	var canvas := win.get_visible_rect().size
	win.size = Vector2i(canvas.round()) * 2  # native res is then unambiguously bigger than the canvas
	var ui := _live_ui()
	var hint := RegEx.new()
	hint.compile("uniform\\s+sampler2D\\s+hud_tex\\s*:([^;]*);")
	var seen: Array[Dictionary] = []
	for mode in [Window.CONTENT_SCALE_MODE_VIEWPORT, Window.CONTENT_SCALE_MODE_CANVAS_ITEMS, Window.CONTENT_SCALE_MODE_VIEWPORT]:
		win.content_scale_mode = mode
		ui._apply_hud_curve()
		var row := {"retro": mode == Window.CONTENT_SCALE_MODE_VIEWPORT, "target": Vector2i.ZERO, "hints": ""}
		if ui._curve_viewport != null and ui._curve_mat != null and ui._curve_mat.shader != null:
			row["target"] = ui._curve_viewport.size
			var m := hint.search(ui._curve_mat.shader.code)
			row["hints"] = m.get_string(1).strip_edges() if m != null else "<no hinted hud_tex sampler>"
		seen.append(row)
	win.content_scale_mode = saved_mode
	win.size = saved_size
	for i in seen.size():
		var row: Dictionary = seen[i]
		var target: Vector2i = row["target"]
		var label := "step %d (%s)" % [i + 1, "RETRO" if row["retro"] else "HIGH FIDELITY"]
		assert_true(target != Vector2i.ZERO, "%s: a non-zero bend must stand up the curve viewport and mount a shader" % label)
		var native := float(target.x) > canvas.x + 0.5
		assert_eq(native, not row["retro"],
			"precondition, %s: the curve target is %s against a %s canvas — RETRO must render at the logical canvas and HIGH FIDELITY above it, or this step is not testing the presentation it names" % [label, target, canvas])
		var want := "filter_nearest" if row["retro"] else "filter_linear"
		assert_true(String(row["hints"]).contains(want),
			"%s: the live poll must mount the twin that samples hud_tex with %s for a %s target — the mounted shader carries '%s'"
				% [label, want, "logical-res" if row["retro"] else "native-res", row["hints"]])


## The audit gap this closes: the pushed `curve` is fed through the shader's own warp(), so an axis swap in
## ui.gd's push (amount on X instead of Y) or a dial that stops scaling it shows up as the WRONG SHAPE.
func test_the_live_push_bows_horizontal_lines_by_the_dialled_amount() -> void:
	GameSettings.hud.hud_curve_amount = BEND
	GameSettings.hud.hud_curve_axis_ratio = 0.0
	Settings.hud_curve_scale = 1.0
	var ui := _live_ui()
	ui._apply_hud_curve()
	if ui._curve_mat == null or ui._curve_mat.shader == null:
		assert_true(false, "a non-zero bend must mount a shader on the curve material")
		return
	var w := _shader_warp(ui._curve_mat.shader.code, "the mounted curve shader")
	if w == null:
		return
	var full := _pushed_curve(ui)
	assert_almost_eq(w.centred(full, Vector2(1.0, 0.0)).x, 1.0, EPS,
		"axis_ratio 0 ships a CYLINDER: the right edge at mid-height must stay put. It moved, so the amount is reaching the X bend — the verticals bow and the panel reads as the wrong kind of curve")
	assert_almost_eq(_bottom_centre_travel(w, full), BEND, 0.001,
		"with the player's dial at 1 the bottom-centre content must tuck up by the FULL authored hud_curve_amount of the half-height")
	Settings.hud_curve_scale = 0.5
	ui._apply_hud_curve()
	assert_almost_eq(_bottom_centre_travel(w, _pushed_curve(ui)), BEND * 0.5, 0.001,
		"the player's dial SCALES the bend: half the dial must give half the tuck, or a motion-sensitive player cannot dial it back")
	Settings.hud_curve_scale = 2.5
	ui._apply_hud_curve()
	assert_almost_eq(_bottom_centre_travel(w, _pushed_curve(ui)), BEND, 0.001,
		"the authored amount is the CEILING: a dial above 1 (a hand-edited settings.cfg) must not bend the panel past it")
	Settings.hud_curve_scale = 1.0
	GameSettings.hud.hud_curve_axis_ratio = 1.0
	ui._apply_hud_curve()
	assert_gt(w.centred(_pushed_curve(ui), Vector2(1.0, 0.0)).x, 1.0 + EPS,
		"axis_ratio 1 is the spherical bend: the SIDE edges must tuck in as well, or the ratio knob has come unwired")


func test_fade_and_fringe_reach_the_shader_inside_zero_to_one() -> void:
	GameSettings.hud.hud_curve_amount = BEND
	Settings.hud_curve_scale = 1.0
	GameSettings.hud.hud_curve_edge_fade = 0.3
	GameSettings.hud.hud_curve_chroma = 0.2
	var ui := _live_ui()
	ui._apply_hud_curve()
	assert_almost_eq(_pushed_float(ui, "edge_fade"), 0.3, 0.0001, "an in-range edge fade must reach the shader unchanged")
	assert_almost_eq(_pushed_float(ui, "chroma"), 0.2, 0.0001, "an in-range lens fringe must reach the shader unchanged")
	GameSettings.hud.hud_curve_edge_fade = 3.0
	GameSettings.hud.hud_curve_chroma = -1.0
	ui._apply_hud_curve()
	assert_between(_pushed_float(ui, "edge_fade"), 0.0, 1.0,
		"an out-of-range edge fade must land inside the shader's 0..1 hint: the corner multiplier is 1 - fade, so a fade of 3 would paint the panel's corners with NEGATIVE premultiplied colour")
	assert_between(_pushed_float(ui, "chroma"), 0.0, 1.0,
		"an out-of-range lens fringe must land inside the shader's 0..1 hint")


## Settings.hud_curve_scale applies LIVE: whatever writes it (set_hud_curve_scale, a settings load) never calls
## _apply_hud_curve, so only the per-frame poll can make the change bite. Everything here waits on real frames
## instead of calling the function.
func test_the_dial_is_followed_on_the_next_frame() -> void:
	GameSettings.hud.hud_curve_amount = BEND
	Settings.hud_curve_scale = 1.0
	var ui := _live_ui()
	assert_not_null(ui._curve_viewport, "precondition: _ready stood the curve up with the dial at 1")
	Settings.hud_curve_scale = 0.0
	await wait_process_frames(2)
	assert_null(ui._curve_viewport,
		"dropping the dial to 0 must tear the curve down within a frame with nobody calling _apply_hud_curve — without the per-frame poll the bend stays frozen at whatever it was when the HUD was built")
	assert_eq(ui._weighted.get_parent(), ui, "after the live teardown the carrier must be a plain child of the layer again")
	Settings.hud_curve_scale = 1.0
	await wait_process_frames(2)
	assert_not_null(ui._curve_viewport, "raising the dial again must stand the curve back up live")
	var before := _pushed_curve(ui)
	Settings.hud_curve_scale = 0.5
	await wait_process_frames(2)
	assert_almost_eq(_pushed_curve(ui).y, before.y * 0.5, 0.0001,
		"a partial dial must re-push the bend live, not only switch the pass on and off")


# === structure: off is the OLD TREE, not an identity pass ====================================================

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


func test_the_settings_setter_clamps_the_dial_into_zero_to_one() -> void:
	var fresh = load("res://managers/Settings.gd").new()
	assert_almost_eq(fresh.hud_curve_scale, 1.0, 0.001,
		"SHIP DECISION: the player's dial defaults to the full authored bend — the curve is the feature, and a motion-sensitive player dials it down from there")
	fresh.free()
	# save_settings() refuses while _loaded is false (restored in after_each), so the setter cannot rewrite the
	# developer's real user://settings.cfg.
	Settings._loaded = false
	Settings.set_hud_curve_scale(2.5)
	assert_almost_eq(Settings.hud_curve_scale, 1.0, 0.0001, "set_hud_curve_scale must clamp a dial above 1 down to the full authored bend")
	Settings.set_hud_curve_scale(-3.0)
	assert_almost_eq(Settings.hud_curve_scale, 0.0, 0.0001, "set_hud_curve_scale must clamp a negative dial to 0 (curve off), never an inverted convex bend")
	Settings.set_hud_curve_scale(0.4)
	assert_almost_eq(Settings.hud_curve_scale, 0.4, 0.0001, "an in-range dial must be stored verbatim")


## The HUD Curve row is NO LONGER an Options row (2026-09-16): HUD Curve / Ghosting / Sway are cosmetic post
## knobs that read as a developer panel on the Accessibility tab. The Settings field and setter survive (saved,
## loaded, applied live); the catalog must not list it — pinned so nobody restores it by accident.
func test_the_options_row_is_deliberately_absent() -> void:
	var cat = load("res://resources/settings/SettingsCatalog.tres")
	for spec in cat.specs:
		if spec != null:
			assert_ne(spec.key, &"hud_curve", "HUD Curve is not a player-facing Options row")
	assert_true(Settings.has_method("set_hud_curve_scale"), "the setting itself survives (saved/loaded, just not on the menu)")
