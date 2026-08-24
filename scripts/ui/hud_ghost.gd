class_name HudGhost
extends Node

## @system HUD Rendering
## @seam The HUD CanvasLayer's canvas is attached to a SECOND (offscreen, never-cleared) viewport, so the
##       same HUD renders twice per frame: once to the window as it always has, and once into an
##       accumulator that keeps a decaying image of every previous frame.
## @risk Any HUD element that SAMPLES THE SCREEN (hint_screen_texture / BackBufferCopy) must be excluded
##       from the capture — inside the accumulator the "screen" is the HUD-only buffer, so an inverting or
##       full-frame post shader reads garbage there. See ui.gd's exclusion block and ui.set_scoped.
## @risk The DISPLAY rect lives on the very layer it is showing, so it MUST be excluded from the capture
##       or the accumulator feeds on its own output and runs away to white within a few frames.
## @test res://tests/test_hud_ghost.gd
##
## SUBTLE HUD GHOSTING — phosphor persistence for the instrument panel and the reticle.
##
## The fiction: this HUD is a CRT/analog readout, not a decal on the glass. Two things follow from that,
## and this component is both of them:
##
##   1. PERSISTENCE. A phosphor keeps glowing after the beam has moved on. Every captured HUD pixel is
##      accumulated into an offscreen buffer that is multiplied down a little each frame (frame-rate
##      independently: the buffer loses 1/e of itself every `hud_ghost_tau` seconds), and that buffer is
##      drawn BEHIND the live HUD. Anything that MOVES or CHANGES therefore drags a soft tail — the corner
##      panel under the HUD-weight spring, minimap dots, a draining stamina ring, toasts, the +N money
##      float, the hitmarker, a prompt appearing. Anything that sits still is pixel-identical to today:
##      the ghost of a static element is hidden exactly behind the element.
##
##   2. LATENCY. The reticle is welded to screen centre (Player._update_crosshair), so persistence ALONE
##      would never show on it — a static image has no tail. So the captured HUD is drawn into the
##      accumulator at a LAGGED position: a first-order lag of the camera's look rate, a couple of pixels
##      at most (`hud_ghost_drag_gain` / `hud_ghost_drag_max`). Camera still -> zero offset -> the ghost is
##      invisible behind the live HUD. Camera turning -> the ghost slides out from under the whole HUD,
##      crosshair included, and the persistence smears it into a tail. That is the "including the
##      crosshair" half of the effect, and it costs one RenderingServer call per frame.
##
## WHY A SECOND VIEWPORT AND NOT A NODE REFACTOR: the HUD keeps rendering to the window EXACTLY as before.
## Nothing is reparented, no z-order changes, no element loses its screen sampler, and turning the effect
## off (Options -> Accessibility -> "HUD Ghosting" = 0) leaves a pixel-identical HUD. The capture is bought
## with three RenderingServer calls in build() — the HUD's one canvas RID gains the accumulator as a second
## viewer — plus per-CanvasItem opt-outs through `visibility_layer`.
##
## THE GHOST RULE (what is captured): an INSTRUMENT READOUT ghosts; a FULL-SCREEN WASH, a WORLD-DIRECTION
## annotation and THE VIEW MODEL do not. So the corner panel, the reticle, the stamina ring, the look-at
## name, the hitmarker, the centre prompt ladder and the enemy health bar all trail; the hurt/kill/dash
## flashes, the speed vignette, the blood splatter, the directional damage/aim arcs, the sniper glints, the
## scope optics and the gun/arms composite do not (a smeared full-screen wash is mud, a lagging bearing
## would LIE about a direction, and the weapon in your hands is the WORLD, not a readout — it only touches
## this layer because that is where its SubViewport is composited back in).
## Opting out is one line — `HudGhost.set_ghosted(node, false)` — and it carries to the node's whole
## subtree, because the renderer culls a canvas item's children along with it.

## Bit 1 — the accumulator's canvas cull mask. Every CanvasItem defaults to visibility_layer 1, so the
## default for a HUD element is CAPTURED and nothing has to opt IN: a toast built at runtime, a rebuilt HP
## segment, a fresh minimap glyph all ghost for free. That default is the whole reason the mask is this way
## round rather than an opt-in bit.
const CAPTURED_LAYER := 1
## Bit 2 — "window only". The main window viewport's canvas_cull_mask is all bits, so an item moved onto
## this layer still renders on screen exactly as before; it just stops feeding the accumulator.
const UNCAPTURED_LAYER := 2

## Below this effective strength the whole thing shuts down (viewport update DISABLED, display hidden) so
## the OFF setting costs nothing at all rather than rendering a fully transparent pass every frame.
const MIN_STRENGTH := 0.004

## One decay/lag step never integrates more than this slice of time. A frame hitch fed into exp() would
## wipe the buffer in a single frame; clamping just means the tail survives a stall, which nobody can see.
const MAX_STEP_DT := 1.0 / 20.0

var _ui: CanvasLayer = null
var _accum: SubViewport = null
var _decay: ColorRect = null
var _display: TextureRect = null
var _decay_mat: ShaderMaterial = null
var _display_mat: ShaderMaterial = null
var _canvas: RID = RID()           ## the HUD canvas we attached; kept so _exit_tree can detach it cleanly
var _size: Vector2i = Vector2i.ZERO
var _running: bool = false         ## the accumulator is currently rendering (mirrors the strength gate)
var _drag: Vector2 = Vector2.ZERO  ## current lagged offset (px, canvas space) the capture is drawn at
var _ramp_source: Gradient = null  ## the Gradient the live ramp texture was baked from, for change detection
var _ramp_tex: GradientTexture1D = null


## The shipped age ramp, used whenever the HUD skin's slot is null (the MenuSkin fallback rule). Keyed by
## trail AGE — offset 1.0 is the pixel that just left the HUD, 0.0 is the one about to vanish — so the tail
## runs pale cyan-white -> cyan -> violet -> magenta as it decays. That is a real phosphor behaviour (P7
## phosphor visibly changes colour as it fades) and it is also what separates this from a plain translucent
## copy: the trail's HUE tells you how old it is, so a fast flick reads as a spectrum and a slow drift as a
## single hue. Alpha stays 1 across the ramp — the fade is owned by hud_ghost_tail_lift, so an artist who
## replaces this gradient changes the COLOUR without accidentally rewriting the falloff.
static func default_gradient() -> Gradient:
	var g := Gradient.new()
	# THE STOPS ARE BUNCHED TOWARD THE FRESH END ON PURPOSE. The buffer decays exponentially, so a pixel is
	# already down to ~0.6 alpha three frames after it left the HUD and the whole back half of the tail lives
	# below 0.3 — spread the stops evenly and the bright, actually-visible part of the trail all lands on one
	# colour and the ramp reads as a tint rather than a gradient. Starting the fresh end at a saturated cyan
	# (not white) is the other half of that: the freshest pixel is the brightest thing in the trail, so if it
	# is white the trail looks like a translucent copy no matter what the rest of the ramp does.
	g.offsets = PackedFloat32Array([0.0, 0.42, 0.70, 1.0])
	g.colors = PackedColorArray([
		Color(1.00, 0.15, 0.55),  # oldest — magenta, the last thing to leave
		Color(0.65, 0.25, 1.00),  # violet
		Color(0.20, 0.55, 1.00),  # blue
		Color(0.10, 0.85, 1.00),  # freshest — SATURATED cyan, never a pale near-white (see above)
	])
	return g


## The ramp the skin is currently asking for: its authored gradient, else the shipped one. Static so a test
## can pin the fallback without building a viewport.
static func gradient_for(skin_gradient: Gradient) -> Gradient:
	return skin_gradient if skin_gradient != null else default_gradient()


## The per-frame multiplier that decays the accumulator: the buffer loses 1/e of itself every `tau`
## seconds, so the tail is the SAME length at 30 fps and at 144. A non-positive tau means "no persistence"
## (wipe every frame); the caller still gets a valid multiplier.
static func decay_for(delta: float, tau: float) -> float:
	if tau <= 0.0:
		return 0.0
	return exp(-clampf(delta, 0.0, MAX_STEP_DT) / tau)


## The offset the capture is drawn at for the current look rates: px = rate (rad/s) * gain (px·s/rad) per
## axis, clamped to `max_px`. Positive gain trails the turn (yaw right -> the ghost hangs left), matching
## HudSway.look_target's sign convention so the panel's mass and the image's latency read as one story.
static func drag_target(yaw_rate: float, pitch_rate: float, gain: Vector2, max_px: float) -> Vector2:
	return Vector2(yaw_rate * gain.x, pitch_rate * gain.y).limit_length(maxf(max_px, 0.0))


## First-order lag toward `target` — NOT a spring. The panel's sway is deliberately under-damped so it
## settles with one overshoot (that is what sells mass); an image's latency has no mass and must not
## bounce, or the ghost visibly oscillates around a reticle that is standing still. `response` is the
## seconds to close 1/e of the gap; <= 0 snaps.
static func lag_step(current: Vector2, target: Vector2, response: float, delta: float) -> Vector2:
	if response <= 0.0:
		return target
	var k := 1.0 - exp(-clampf(delta, 0.0, MAX_STEP_DT) / response)
	return current + (target - current) * k


## The authored ghost amplitude scaled by the player's 0..1 Options dial. Static + argument-fed (the
## HudSway.kick_scaled idiom) so the clamp order is pinned by a test rather than by reading the caller.
static func strength_for(authored: float, player_scale: float) -> float:
	return clampf(authored, 0.0, 1.0) * clampf(player_scale, 0.0, 1.0)


## Opt a HUD element (and everything under it) IN or OUT of the ghost capture. Out = it still renders to
## the window untouched, it just stops feeding the accumulator. Null-safe so a caller can flag optional
## overlays without guarding each one.
static func set_ghosted(item: CanvasItem, ghosted: bool) -> void:
	if item == null:
		return
	item.visibility_layer = CAPTURED_LAYER if ghosted else UNCAPTURED_LAYER


## Build the capture onto `ui` — the HUD CanvasLayer whose canvas is duplicated into the accumulator, and
## the parent the ghost's display rect is added to. Degrades to an inert no-op when there is no viewport
## yet (the bare `UI.new()` test seam), so nothing here can fail a suite that never renders. Returns true
## when the effect is live, so the caller knows whether its own exclusion writes matter.
##
## `screen_pass` is that layer's SCREEN-SPACE POST-PROCESS rect (ui.tscn's ColorRect), if it has one. The
## display rect is seated immediately after it — see _place_display for why that seat is load-bearing and
## why passing null is only correct for a layer that genuinely has no such pass.
func build(ui: CanvasLayer, screen_pass: CanvasItem = null) -> bool:
	if ui == null or not ui.is_inside_tree():
		return false
	var vp := ui.get_viewport()
	if vp == null:
		return false
	_size = Vector2i(vp.get_visible_rect().size.round())
	if _size.x <= 0 or _size.y <= 0:
		return false
	_ui = ui
	# THE ACCUMULATOR. transparent_bg + CLEAR_MODE_NEVER is the persistence itself: nothing wipes the
	# colour buffer, so last frame's HUD is still sitting there when this frame's decay quad multiplies it
	# down and this frame's HUD draws over it. ⭐ use_hdr_2d must stay OFF — an HDR render target with a
	# never-cleared target hard-crashes the D3D12 backend (verified on 4.7.1), and the 8-bit rounding floor
	# that leaves behind is cut at display time instead (see `residue_floor`).
	_accum = SubViewport.new()
	_accum.name = "HudGhostAccum"
	_accum.size = _size
	_accum.transparent_bg = true
	_accum.disable_3d = true
	_accum.gui_disable_input = true
	_accum.canvas_cull_mask = CAPTURED_LAYER
	_accum.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_accum.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE  # frame one starts from a known-empty buffer
	add_child(_accum)
	# THE DECAY QUAD. It lives in the accumulator's OWN World2D canvas, which stacks at layer 0 — below the
	# HUD canvas attached at layer 1 — so the order inside the accumulator is always "fade what is already
	# there, then draw this frame's HUD over it". blend_mul multiplies BOTH colour and alpha by the uniform,
	# which keeps the buffer's premultiplied-alpha invariant intact as it fades.
	_decay = ColorRect.new()
	_decay.name = "Decay"
	_decay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_decay.size = Vector2(_size)
	_decay_mat = ShaderMaterial.new()
	_decay_mat.shader = _make_decay_shader()
	_decay_mat.set_shader_parameter(&"decay", 0.9)
	_decay.material = _decay_mat
	_accum.add_child(_decay)
	# THE DISPLAY. A plain rect on the HUD layer showing the accumulator. It has two seats to honour, and they
	# pull in opposite directions: it must draw BELOW every readout (the ghost may never cover the crisp thing
	# it is the echo of) and ABOVE this layer's screen-space post-process pass (or it becomes INPUT to that
	# shader instead of a HUD element). See _place_display — the second half is a POSITION, not a z_index.
	_display = TextureRect.new()
	_display.name = "HudGhost"
	_display.texture = _accum.get_texture()
	_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # 1:1 with the canvas; never resample the HUD
	_display_mat = ShaderMaterial.new()
	_display_mat.shader = _make_display_shader()
	_refresh_ramp()
	_display.material = _display_mat
	# ⭐ THE FEEDBACK GUARD: this rect is a child of the very layer being captured, so without the opt-out
	# the accumulator would photograph its own last output every frame and run away to white in seconds.
	set_ghosted(_display, false)
	_ui.add_child(_display)
	_place_display(screen_pass)
	_display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_display.visible = false  # poll() opens it once a strength is known; OFF must cost nothing on frame one
	# THE CAPTURE ITSELF: attach the HUD's existing canvas to the accumulator as a SECOND viewer. The canvas
	# stays attached to the window exactly as before — this adds a viewer, it does not move one. Stacking
	# layer 1 puts it above the decay quad's canvas (0); the transform is re-stamped every frame by poll().
	_canvas = _ui.get_canvas()
	var rid := _accum.get_viewport_rid()
	RenderingServer.viewport_attach_canvas(rid, _canvas)
	RenderingServer.viewport_set_canvas_stacking(rid, _canvas, 1, 0)
	RenderingServer.viewport_set_canvas_transform(rid, _canvas, Transform2D())
	return true


## Per-frame drive, called from ui.gd's _process right after the sway spring steps — it hands over the same
## look rates it just measured, so the ghost's latency and the panel's mass narrate one camera motion.
## `may_show` is false while the death cinematic owns HUD visibility: the display rect is a direct child of
## the layer, so hide_hud_for_death already hid it and remembered it, and writing `visible` here would
## resurrect it over the fade (the _apply_stamina_mode / _apply_crosshair_visibility house rule).
func poll(delta: float, yaw_rate: float, pitch_rate: float, may_show: bool) -> void:
	if _accum == null or _display == null:
		return
	var hud: HudSettings = GameSettings.hud
	var scale := clampf(Settings.hud_ghost_scale, 0.0, 1.0)
	var strength := strength_for(hud.hud_ghost_strength, scale)
	var want := strength >= MIN_STRENGTH
	if want != _running:
		_running = want
		# Coming back on, start from an empty buffer: whatever is still sitting in the render target is as
		# many seconds stale as the effect was off for, and fading that in reads as a smear from nowhere.
		# CLEAR_MODE_ONCE flips itself back to NEVER after that one frame.
		_accum.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
		_accum.render_target_update_mode = SubViewport.UPDATE_ALWAYS if want else SubViewport.UPDATE_DISABLED
		_drag = Vector2.ZERO
	if may_show:
		_display.visible = want
	if not want:
		return
	_match_canvas_size()
	_refresh_ramp()
	_decay_mat.set_shader_parameter(&"decay", decay_for(delta, hud.hud_ghost_tau))
	_display_mat.set_shader_parameter(&"strength", strength)
	_display_mat.set_shader_parameter(&"residue_floor", clampf(hud.hud_ghost_residue_floor, 0.0, 0.5))
	_display_mat.set_shader_parameter(&"tint", clampf(hud.hud_ghost_tint, 0.0, 1.0))
	_display_mat.set_shader_parameter(&"tail_lift", maxf(hud.hud_ghost_tail_lift, 0.01))
	# The latency offset: where the capture is drawn RELATIVE to the live HUD. Its cap rides the same player
	# dial as the strength, so one slider takes the whole effect from full to silent — and a player who
	# wants persistence with no double vision zeroes hud_ghost_drag_max instead. Rounded to whole canvas
	# pixels: the display samples the accumulator 1:1 with a NEAREST filter, and a fractional offset would
	# shimmer the ghost's edges against that grid instead of sliding cleanly.
	var target := drag_target(yaw_rate, pitch_rate, hud.hud_ghost_drag_gain, hud.hud_ghost_drag_max * scale)
	_drag = lag_step(_drag, target, hud.hud_ghost_drag_response, delta)
	RenderingServer.viewport_set_canvas_transform(_accum.get_viewport_rid(), _canvas,
			Transform2D(0.0, _drag.round()))


## Seat the display rect in the HUD layer's draw order: immediately AFTER the screen-space post-process pass,
## and before everything else on the layer.
##
## ⭐⭐IT IS AN INDEX, NOT A z_index, AND THAT IS THE WHOLE POINT. This rect has to be after ONE named sibling
## and before all the others; no single z can say that, because the pass and the readouts share z 0..2. The
## first version said `z_index = -1` — below every readout, correct on that half, and it quietly put the ghost
## on the WRONG SIDE OF THE POST-PROCESS. Everything drawn before that rect is what its SCREEN_TEXTURE fetch
## reads; everything drawn after is untouched by it. The whole live HUD is after. The ghost was before.
##
## ⭐⭐WHY IT WENT FROM HARMLESS TO A BUG. While the pass was per-pixel (quantise / dither / grain / night
## vision) being on the wrong side only meant the echo was tinted and posterised differently from the readout
## it echoes. Then post_process.gdshader grew `lens_barrel` — a radial BARREL WARP of the fetch, on by default.
## A warp MOVES pixels, so the ghost was being bent by a world lens its own source never sees: measured at the
## shipped 0.12 the minimap's ghost stood clear of the minimap while the camera was dead still, which is
## exactly the promise this effect is built on ("camera still -> offset 0 -> the ghost hides behind the HUD").
## Seating it after the pass ends that coupling for good — no present or future screen-space effect can move a
## HUD echo off its readout, and nothing here has to track the lens's formula to stay aligned.
##
## ⭐THE CONSEQUENCE TO KNOW: from above the pass, the ghost also draws over the VIEW MODEL composite (HUD
## child 0, deliberately BELOW the post-process rect so the weapon is lens-warped with the world it belongs
## to), where z -1 used to hide it. That is the consistent reading — the hotbar and the corner cluster
## THEMSELVES draw over the gun, so their echo does too — and the alternative is worse: masking the trail out
## of the weapon would mean sampling its coverage through the very lens warp this seat exists to stop tracking.
##
## Stable against the moves that come later: ViewModelCamera inserts its composite at index 0 (shifting this
## rect and the pass together, so their order is preserved), and every other HUD child — a toast, a prompt,
## the curve composite taking the carrier's slot — is added at or after the carrier, far above this seat.
func _place_display(screen_pass: CanvasItem) -> void:
	var at := 0
	if screen_pass != null and screen_pass.get_parent() == _ui:
		at = screen_pass.get_index() + 1
	_ui.move_child(_display, at)


## (Re)bake the age ramp into the texture the display shader samples. Compared BY REFERENCE against the
## gradient the current texture came from, so this is a pointer test on a normal frame and a rebuild only
## when MenuStyle.set_hud_skin actually swaps the resource — a skin swap emits nothing (the same trailing
## edge the Options rows are polled for), so noticing it here is the whole reason this runs per frame.
func _refresh_ramp() -> void:
	var want := gradient_for(MenuStyle.hud.ghost_gradient)
	if _ramp_tex != null and _ramp_source == want:
		return
	_ramp_source = want
	_ramp_tex = GradientTexture1D.new()
	_ramp_tex.gradient = want
	_ramp_tex.width = 256  # the tail crosses the whole ramp in a few frames; 256 steps is already smooth
	_display_mat.set_shader_parameter(&"ramp", _ramp_tex)


## Keep the accumulator the same size as the canvas. The window stretch aspect is "expand", so the canvas
## is NOT a constant — a resize or a resolution change hands the HUD a different rect, and a stale buffer
## would stretch the ghost across it. Re-clear on the way through: a resized render target's contents are
## undefined.
func _match_canvas_size() -> void:
	if _ui == null or not _ui.is_inside_tree():
		return
	var vp := _ui.get_viewport()
	if vp == null:
		return
	var now := Vector2i(vp.get_visible_rect().size.round())
	if now.x <= 0 or now.y <= 0 or now == _size:
		return
	_size = now
	_accum.size = now
	_decay.size = Vector2(now)
	_accum.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE


## Detach the borrowed canvas before this node (and the accumulator's RID with it) goes away. The canvas
## belongs to the HUD layer, not to us — leaving a dead viewport attached to a live canvas is exactly the
## kind of dangling RID that survives a scene reload and bites two levels later.
func _exit_tree() -> void:
	if _accum != null and _canvas.is_valid():
		RenderingServer.viewport_remove_canvas(_accum.get_viewport_rid(), _canvas)
	_canvas = RID()


## Multiply the accumulator down. Written as a `blend_mul` canvas shader rather than a modulate because the
## multiply has to hit the DESTINATION (what is already in the buffer), not this quad's own colour.
func _make_decay_shader() -> Shader:
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nrender_mode blend_mul, unshaded;\nuniform float decay : hint_range(0.0, 1.0) = 0.9;\nvoid fragment() {\n\tCOLOR = vec4(decay);\n}"
	return sh


## Draw the accumulator behind the HUD, recoloured by AGE. Four things this shader has to get right:
##   - blend_premul_alpha: a transparent SubViewport stores PREMULTIPLIED colour (verified — an 85%-alpha
##     yellow reads back as rgb * 0.85). Compositing that with ordinary alpha blending double-multiplies
##     every edge and rims the whole HUD in dark fringes. It is also why the source colour has to be
##     UN-premultiplied (rgb / a) before it can be mixed with the ramp: mixing the premultiplied value
##     would tint by brightness rather than by hue and the faint end of the tail would mix toward black.
##   - THE RAMP IS KEYED ON ALPHA, and that works because alpha IS age here: every frame multiplies the
##     whole buffer down, so how transparent a trail pixel is says exactly how long ago it was the HUD.
##     One texture fetch turns that into the artist's colour, which is what makes this a gradient rather
##     than a dimmed copy — a red bar and a gold readout leave the same-coloured trail.
##   - residue_floor: an 8-bit render target multiplied by d each frame has a FIXED POINT — once a channel
##     is small enough that round(n * d) == n it never falls again (~8/255 at a typical d), so without this
##     cut every place the HUD has ever been keeps a permanent faint smear. Subtracting the floor and
##     renormalising kills the tail's last few steps and costs nothing visible at the bright end. It is
##     applied BEFORE the ramp lookup so the ramp's cold end lands on the real end of the tail.
##   - tail_lift: without it the exponential fade makes the cold half of the ramp invisible and the whole
##     gradient collapses to its hot end. The gamma lifts the old tail just enough for its colour to read.
## The ramp is sampled with NO source_color hint on purpose: canvas items composite in the viewport's sRGB
## space, so the gradient's authored bytes are already in the right space and a conversion would wash it.
func _make_display_shader() -> Shader:
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nrender_mode blend_premul_alpha, unshaded;\nuniform sampler2D ramp : hint_default_white, filter_linear, repeat_disable;\nuniform float strength : hint_range(0.0, 1.0) = 0.35;\nuniform float residue_floor : hint_range(0.0, 0.5) = 0.06;\nuniform float tint : hint_range(0.0, 1.0) = 0.85;\nuniform float tail_lift : hint_range(0.05, 2.0) = 0.65;\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV);\n\tfloat age = max(c.a - residue_floor, 0.0) / max(1.0 - residue_floor, 0.0001);\n\tvec3 src = c.a > 0.0001 ? c.rgb / c.a : vec3(0.0);\n\tvec4 ramp_c = texture(ramp, vec2(age, 0.5));\n\tvec3 col = mix(src, ramp_c.rgb, tint);\n\tfloat a = pow(age, tail_lift) * ramp_c.a;\n\tCOLOR = vec4(col * a, a) * strength;\n}"
	return sh
