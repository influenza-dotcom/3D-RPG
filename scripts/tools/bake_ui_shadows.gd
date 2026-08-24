extends SceneTree

## RE-AIMS the baked drop shadow on the UI art PNGs, in place:
##
##   godot --headless --path <absolute project path> -s scripts/tools/bake_ui_shadows.gd
##
## WHY THIS EXISTS. The menu art wears its drop shadow BAKED INTO THE PNG, not drawn by a StyleBox — the
## artist's frames are 9-patched StyleBoxTextures and Godot has no per-StyleBoxTexture shadow. That bake was
## originally done by hand, which made the shadow's direction and softness un-reproducible. This tool owns it.
##
## THE HOUSE LIGHT IS STRAIGHT OVERHEAD. Every shadow falls straight DOWN — offset (0, +dy), never diagonal.
## A diagonal shadow reads as a second, disagreeing light source once several pieces of chrome (panel, buttons,
## tooltip, dialogue box) are on screen together; one vertical light is what makes the whole menu look like one
## object. That is the ONE rule this tool enforces, and re-running it is how you restore it after new art lands.
##
## THE SHADOW RULE (shared with menu_skin.tres and tests/test_menu_skin_art.gd): the shadow lives entirely in a
## transparent PAD around the art body, and that pad rides in the StyleBoxTexture's EXPAND margins — draw-only,
## outside the layout rect. So a shadow can never move a tuned layout metric (rebind_button_width's 1px slack,
## the dense Options column fit). `pad` below MUST equal that texture's authored expand margin; the shadow is
## sized to reach EXACTLY the pad and no further, so the canvas never has to grow.
##
## IT RE-AIMS, IT DOES NOT INVENT. Colour and strength are SAMPLED from the shadow already in the file (the
## strongest pixel outside the body rect), so the artist's per-asset shadow weight survives a re-run — this only
## changes the DIRECTION and the falloff. The art body itself is lifted out of the padded canvas untouched: the
## old shadow only ever lived in the pad, so cropping the body is lossless. That also makes the tool idempotent —
## run it twice and the second run is a no-op in everything but the last bit of the body's 1px antialiased rim.
##
## AFTER RUNNING: the freshly written PNGs still need the EDITOR to re-import them before the game sees the new
## pixels — focusing the open editor triggers that scan automatically. Do NOT run `--import` while the editor is
## open (it can yield empty PackedScenes).
##
## -s compiles this script BEFORE autoloads exist, so nothing here may preload or touch an autoload.

## One row per baked-shadow texture. `pad` is the transparent shadow margin around the art body, in pixels, and
## is the SAME number as that texture's StyleBoxTexture `expand_margin_*` in resources/ui/menu_skin.tres — the two
## must move together or the shadow starts eating (or floating off) the drawn rect. Adding artist art with a baked
## shadow? Add its row here rather than hand-compositing, so it inherits the one house light.
const TARGETS: Array[Dictionary] = [
	{"path": "res://assets/textures/ui/menu_panel.png", "pad": 8},            # sb_panel
	{"path": "res://assets/textures/ui/button_frame_normal.png", "pad": 5},   # sb_btn_normal
	{"path": "res://assets/textures/ui/button_frame_hover.png", "pad": 5},    # sb_btn_hover
	{"path": "res://assets/textures/ui/button_frame_selected.png", "pad": 5}, # sb_btn_pressed
	{"path": "res://assets/textures/ui/menu_panel_tip.png", "pad": 3},        # sb_tooltip
	{"path": "res://assets/textures/ui/dialogue_panel.png", "pad": 8},        # sb_dialogue
]

## How much of the pad is SOFT edge rather than solid offset. The rest of the pad is the drop distance, so the
## shadow's total downward reach is always exactly `pad` — that is what lets the canvas stay the size it is.
## Tuned to land the softness where the hand bake had it (a ~2px ramp under the big panel, 1px under a button);
## raise it for a hazier shadow, but never past ~0.5 or the blur starts spilling ABOVE the body (see _plan).
const BLUR_FRACTION: float = 0.28


func _initialize() -> void:
	var changed: int = 0
	for t in TARGETS:
		if _rebake(String(t["path"]), int(t["pad"])):
			changed += 1
	print("bake_ui_shadows: %d/%d textures re-aimed straight down." % [changed, TARGETS.size()])
	quit(0 if changed == TARGETS.size() else 1)


## drop distance + blur radius for a given pad. Both are integers because the mask is blurred with whole-pixel
## box passes; `dy + blur == pad` is the invariant that keeps the shadow inside the canvas.
## The blur also spreads UPWARD from the offset mask, so the shadow stays clear of the body's top edge only while
## `blur < dy` — i.e. while BLUR_FRACTION stays under 0.5. A shadow peeking out above the card would read as a
## light from below and undo the whole point.
func _plan(pad: int) -> Vector2i:
	var blur: int = maxi(1, int(round(float(pad) * BLUR_FRACTION)))
	return Vector2i(pad - blur, blur)  # x = drop distance (dy), y = blur radius


func _rebake(res_path: String, pad: int) -> bool:
	var abs_path: String = ProjectSettings.globalize_path(res_path)
	var img: Image = Image.load_from_file(abs_path)
	if img == null:
		push_error("bake_ui_shadows: can't read " + res_path)
		return false
	img.convert(Image.FORMAT_RGBA8)

	var w: int = img.get_width()
	var h: int = img.get_height()
	var bw: int = w - pad * 2
	var bh: int = h - pad * 2
	if bw <= 0 or bh <= 0:
		push_error("bake_ui_shadows: %s is smaller than its %dpx pad" % [res_path, pad])
		return false

	var plan: Vector2i = _plan(pad)
	var dy: int = plan.x
	var blur: int = plan.y

	# SAMPLE the outgoing shadow — strongest pixel strictly OUTSIDE the body rect. That region is shadow and
	# nothing else, so its peak alpha is this asset's authored shadow weight and its RGB is the shadow's colour
	# (the parchment set bakes a warm near-black, the dialogue box a pure black; both survive a re-run).
	var peak: float = 0.0
	var tint: Color = Color(0, 0, 0)
	for y in h:
		var in_rows: bool = y >= pad and y < pad + bh
		for x in w:
			if in_rows and x >= pad and x < pad + bw:
				continue
			var c: Color = img.get_pixelv(Vector2i(x, y))
			if c.a > peak:
				peak = c.a
				tint = Color(c.r, c.g, c.b)
	if peak <= 0.0:
		push_warning("bake_ui_shadows: %s has no baked shadow to re-aim — skipped." % res_path)
		return false

	# LIFT the body out of the padded canvas. The old shadow never reached inside this rect (it lives in the pad),
	# so this is the art exactly as the artist delivered it, at game scale.
	var body: Image = Image.create(bw, bh, false, Image.FORMAT_RGBA8)
	body.blit_rect(img, Rect2i(pad, pad, bw, bh), Vector2i.ZERO)

	# BUILD the shadow mask: the body's own alpha silhouette (so a cut-out in the art — the dialogue box's corner
	# notch — casts a shadow with the same hole in it), dropped straight down by dy, then softened.
	var mask: PackedFloat32Array = PackedFloat32Array()
	mask.resize(w * h)
	for y in bh:
		var row: int = (y + pad + dy) * w
		for x in bw:
			mask[row + x + pad] = body.get_pixelv(Vector2i(x, y)).a
	for _i in blur:
		mask = _soften(mask, w, h)

	# COMPOSE: shadow first, art over it. blend_rect is straight source-over, which is what a drop shadow is.
	var out: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var row: int = y * w
		for x in w:
			var a: float = mask[row + x] * peak
			if a > 0.0:
				out.set_pixelv(Vector2i(x, y), Color(tint.r, tint.g, tint.b, a))
	out.blend_rect(body, Rect2i(0, 0, bw, bh), Vector2i(pad, pad))

	var err: int = out.save_png(abs_path)
	if err != OK:
		push_error("bake_ui_shadows: save failed (%d) for %s" % [err, res_path])
		return false
	print("  %s  %dx%d body in %dx%d canvas — drop %dpx, blur %dpx, alpha %.2f" % [
		res_path.get_file(), bw, bh, w, h, dy, blur, peak])
	return true


## ONE separable box pass of radius 1 over the mask — run `blur` times, which spreads the edge exactly `blur`
## pixels each way while stacking toward a gaussian-ish ramp (a single wide box pass ramps too linearly and reads
## as a bevel, not a shadow). Off-canvas samples count as empty; the mask is built so the spread can never reach
## a canvas edge it would need to clamp against.
func _soften(src: PackedFloat32Array, w: int, h: int) -> PackedFloat32Array:
	var tmp: PackedFloat32Array = PackedFloat32Array()
	tmp.resize(w * h)
	for y in h:
		var row: int = y * w
		for x in w:
			var s: float = src[row + x]
			if x > 0:
				s += src[row + x - 1]
			if x < w - 1:
				s += src[row + x + 1]
			tmp[row + x] = s / 3.0
	var dst: PackedFloat32Array = PackedFloat32Array()
	dst.resize(w * h)
	for y in h:
		var row: int = y * w
		for x in w:
			var s: float = tmp[row + x]
			if y > 0:
				s += tmp[row + x - w]
			if y < h - 1:
				s += tmp[row + x + w]
			dst[row + x] = s / 3.0
	return dst
