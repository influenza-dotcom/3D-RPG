class_name WorldGhost
extends Node

## @system Rendering
## @seam An offscreen never-cleared SubViewport keeps a running average of the FINISHED frame (it samples the
##       ROOT viewport's own texture, so it reads last frame), and a full-rect shader adds the difference
##       between that average and the live frame back over the picture.
## @risk The display is itself part of the frame that gets averaged — a feedback loop. It is stable only
##       because the accumulator MIXES toward the screen instead of summing it; see the maths below before
##       changing either the blend or the composite.
## @risk The accumulator averages the WHOLE window, including any CanvasLayer above this one. The display
##       only sees layers below it, so while a menu / dialogue / cutscene owns the screen the two disagree
##       and the effect must be OFF (and the buffer re-cleared on the way back in).
## @test res://tests/test_world_ghost.gd
##
## WORLD GHOSTING — the HUD's phosphor persistence, extended to the picture behind it, very subtly.
##
## The HUD ghost (scripts/ui/hud_ghost.gd) works by lending the HUD's canvas RID to a second viewer. That
## trick has no equivalent here: the world is 3D, there is no canvas to lend, and re-rendering it through a
## second Camera3D would double the frame cost for an effect that is meant to be almost invisible. So this
## takes the other road available to a screen-space effect — a temporal average of the finished frame:
##
##   ACCUMULATE  A <- mix(A, last_frame, k),  k = 1 - exp(-dt / tau)
##   COMPOSITE   out = now + (A - now) * strength
##
## Written that way rather than as a straight cross-fade for one reason: at rest A converges on the frame, so
## `A - now` is ZERO and the composite re-emits the picture unchanged — the effect cannot tint, darken or
## soften a still image, which is the whole "very subtly" promise. It only exists where the picture MOVED.
##
## WHY THE LOOP IS STABLE. The composite is part of the frame the accumulator then averages, so this is
## literal video feedback. Substituting the composite into the accumulate step gives
## `A' = A(1 - k(1 - s)) + k(1 - s)F` — a contraction for any s < 1, converging on the un-ghosted frame F.
## A SUM (`A' = A*decay + frame`) instead of a mix would multiply the picture by 1/(1-decay) and blow out
## within a second. Keep the mix.
##
## WHAT IT DELIBERATELY DOES NOT TOUCH:
##  - THE VIEW MODEL. Masked out per pixel by the gun pass's own alpha (ViewModelCamera.coverage_texture),
##    so the weapon stays crisp while the world behind it trails. Without the mask the gun's walk-bob would
##    smear its own edges — subtle, but the weapon in your hands is not supposed to be a light source.
##  - MENUS / DIALOGUE / CUTSCENES. Gated off entirely (see the @risk above), buffer re-cleared on return.
##  - THE 8-BIT RESIDUE. A never-cleared buffer chasing a target stalls a few steps short of it (round-to-
##    nearest), so `A - now` never quite reaches zero. `dead_zone` clips that away per channel, which is what
##    turns "almost invisible at rest" into "provably identical at rest".

## Below this effective strength the pass stops rendering entirely, so OFF costs nothing.
const MIN_STRENGTH := 0.004
## A blend step never integrates more than this slice of time — a frame hitch would otherwise snap the
## accumulator straight onto the current frame and drop the tail.
const MAX_STEP_DT := 1.0 / 20.0
## Frames the display stays hidden after the buffer is cleared. A freshly cleared accumulator differs wildly
## from the frame, and compositing that difference is a one-frame flash of the clear colour.
const WARMUP_FRAMES := 3
## CanvasLayer the composite draws on: above the HUD (1) so the average and the live frame agree about the
## HUD and the weapon, and below dialogue (90) / cutscenes (100) / modals (120+) / tooltips (200), which the
## gate below switches the whole effect off for anyway.
const DISPLAY_LAYER := 5

var _host: CanvasLayer = null
var _accum: SubViewport = null
var _feed: TextureRect = null
var _layer: CanvasLayer = null
var _display: ColorRect = null
var _mat: ShaderMaterial = null
var _size: Vector2i = Vector2i.ZERO
var _running: bool = false
var _warmup: int = 0
var _gun_mask: Texture2D = null


## The per-frame weight the finished frame is mixed into the accumulator with: the buffer closes 1/e of the
## gap to the picture every `tau` seconds, so the trail is the same LENGTH at 30 fps and at 144. tau <= 0
## snaps (no persistence at all); the result is always a usable 0..1 weight.
static func blend_for(delta: float, tau: float) -> float:
	if tau <= 0.0:
		return 1.0
	return 1.0 - exp(-clampf(delta, 0.0, MAX_STEP_DT) / tau)


## The chromatic split, in PIXELS, for the current look rates: the accumulator's red and blue channels are
## sampled a hair either side of green along the direction the view is moving, so a moving edge fringes the
## way an analog signal does. Zero when the camera is still, which keeps a static frame free of it.
static func chroma_offset(yaw_rate: float, pitch_rate: float, gain: Vector2, max_px: float) -> Vector2:
	return Vector2(yaw_rate * gain.x, pitch_rate * gain.y).limit_length(maxf(max_px, 0.0))


## The authored amplitude scaled by the player's 0..1 dial (the HudGhost.strength_for idiom — same clamp
## order, pinned by a test rather than inferred from the caller).
static func strength_for(authored: float, player_scale: float) -> float:
	return clampf(authored, 0.0, 1.0) * clampf(player_scale, 0.0, 1.0)


## True while something other than gameplay owns the screen. The accumulator averages the WHOLE window but
## the composite only sees the layers under it, so a menu / dialogue / cutscene at layer 90+ is in the
## average and not in the live sample — the difference between them would paint a ghost of the menu across
## the world. Both predicates are needed: gameplay_suppressed() covers modals / cutscene / name entry, and
## world_frozen() adds the conversation, which is not a modal.
static func suppressed() -> bool:
	return InputManager.gameplay_suppressed() or InputManager.world_frozen()


## Build the pass. `host` is the HUD CanvasLayer — used only as a parent so this dies with the player's UI;
## the composite gets its own layer above it (see DISPLAY_LAYER). Degrades to an inert no-op with no viewport
## (the bare UI.new() test seam). Returns true when the pass is live.
func build(host: CanvasLayer) -> bool:
	if host == null or not host.is_inside_tree():
		return false
	var vp := host.get_viewport()
	if vp == null:
		return false
	_size = Vector2i(vp.get_visible_rect().size.round())
	if _size.x <= 0 or _size.y <= 0:
		return false
	_host = host
	# THE ACCUMULATOR. Opaque (this is a picture, not an overlay) and never cleared, so last frame's average
	# is still sitting there when this frame's mix runs. ⭐ use_hdr_2d must stay OFF: an HDR render target
	# with a never-cleared target hard-crashes the D3D12 backend on 4.7.1 (the same trap the HUD ghost hit).
	_accum = SubViewport.new()
	_accum.name = "WorldGhostAccum"
	_accum.size = _size
	_accum.transparent_bg = false
	_accum.disable_3d = true
	_accum.gui_disable_input = true
	_accum.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_accum.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	add_child(_accum)
	# THE FEED. One full-rect draw of the ROOT viewport's own texture at alpha k — that IS the moving average,
	# so there is no separate decay quad here (unlike the HUD ghost, whose buffer holds premultiplied alpha
	# and needs a multiply). A SubViewport renders before its parent, so this samples the PREVIOUS finished
	# frame; the one-frame lag is exactly what a ghost is made of.
	_feed = TextureRect.new()
	_feed.name = "Feed"
	_feed.texture = vp.get_texture()
	_feed.size = Vector2(_size)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # 1:1, never resample the picture
	_accum.add_child(_feed)
	# THE COMPOSITE, on its own layer above the HUD. A ColorRect (not a TextureRect) with the accumulator
	# passed in as an explicit uniform: the shader needs UV to mean "screen position", and a ColorRect's UV
	# does that with no stretch-mode semantics in the way.
	_layer = CanvasLayer.new()
	_layer.name = "WorldGhostLayer"
	_layer.layer = DISPLAY_LAYER
	_host.add_child(_layer)
	_display = ColorRect.new()
	_display.name = "WorldGhost"
	_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = _make_shader()
	_mat.set_shader_parameter(&"accum_tex", _accum.get_texture())
	_display.material = _mat
	_layer.add_child(_display)
	_display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_display.visible = false
	_warmup = WARMUP_FRAMES
	return true


## Per-frame drive, called from ui.gd's _process with the SAME camera look rates the HUD sway measured, so
## the chromatic split and the HUD's own latency narrate one motion instead of two measurements of it.
func poll(delta: float, yaw_rate: float, pitch_rate: float) -> void:
	if _accum == null or _display == null:
		return
	var fx: EffectsSettings = GameSettings.effects
	var scale := clampf(Settings.world_ghost_scale, 0.0, 1.0)
	var strength := strength_for(fx.world_ghost_strength, scale)
	var want := strength >= MIN_STRENGTH and not suppressed()
	if want != _running:
		_running = want
		# Re-clear on every transition. Coming back from a menu the buffer holds an average of the MENU, and
		# compositing the difference between that and the world is a full-screen flash of the pause screen.
		_accum.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
		_accum.render_target_update_mode = SubViewport.UPDATE_ALWAYS if want else SubViewport.UPDATE_DISABLED
		_warmup = WARMUP_FRAMES
	if not want:
		_display.visible = false
		return
	_match_canvas_size()
	if _warmup > 0:
		# Keep feeding the accumulator but show nothing: a just-cleared buffer differs from the frame by the
		# whole picture, and that difference composited is a one-frame flash.
		_warmup -= 1
		_display.visible = false
		return
	_display.visible = true
	_feed.modulate.a = blend_for(delta, fx.world_ghost_tau)
	_mat.set_shader_parameter(&"strength", strength)
	_mat.set_shader_parameter(&"dead_zone", maxf(fx.world_ghost_dead_zone, 0.0))
	# The split is authored in PIXELS and handed over in UV, so the same knob means the same visual width at
	# any resolution. Scaled by the player dial with everything else.
	var px := chroma_offset(yaw_rate, pitch_rate, fx.world_ghost_chroma_gain, fx.world_ghost_chroma_px * scale)
	_mat.set_shader_parameter(&"chroma", px / Vector2(maxi(_size.x, 1), maxi(_size.y, 1)))
	_refresh_gun_mask()


## Keep the weapon's coverage mask current. Looked up lazily and re-checked while missing, because the gun
## pass is built by Head.setup during the Player's _enter_tree — which may or may not have run by the time
## this layer's _ready did — and because a weapon swap never rebuilds the pass, so once found it is stable.
func _refresh_gun_mask() -> void:
	if _gun_mask != null:
		return
	if _host == null or not _host.is_inside_tree():
		return
	var player := _host.get_parent()
	if player == null:
		return
	var cam := player.find_child("ViewModelCamera", true, false)
	if cam == null or not cam.has_method(&"coverage_texture"):
		return
	var tex: Variant = cam.call(&"coverage_texture")
	if tex is Texture2D:
		_gun_mask = tex as Texture2D
		_mat.set_shader_parameter(&"gun_mask", _gun_mask)


## Track the canvas size (stretch aspect is "expand", so it is not a constant) and re-clear through the
## change — a resized render target's contents are undefined, and here that would composite as noise.
func _match_canvas_size() -> void:
	if _host == null or not _host.is_inside_tree():
		return
	var vp := _host.get_viewport()
	if vp == null:
		return
	var now := Vector2i(vp.get_visible_rect().size.round())
	if now.x <= 0 or now.y <= 0 or now == _size:
		return
	_size = now
	_accum.size = now
	_feed.size = Vector2(now)
	_accum.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	_warmup = WARMUP_FRAMES


## The composite. Four jobs, in order:
##   - `now`  — the frame as it stands under this layer (world + weapon + HUD + the HUD's own ghost).
##   - `past` — the accumulator, with R and B sampled a hair either side of G along the motion direction.
##     That chromatic split is what makes a moving edge read as an ANALOG ghost rather than as motion blur;
##     at rest the offset is zero and all three channels sample the same texel, so it costs nothing visually.
##   - the DEAD ZONE — a never-cleared 8-bit buffer chasing a target stalls a few steps short of it, so the
##     difference never quite reaches zero. Clipping it per channel is what makes "invisible at rest" exact
##     rather than approximate.
##   - the GUN MASK — the weapon's own coverage alpha, zeroing the trail wherever the view model is drawn.
##     Defaults transparent, so with no gun pass the mask is 0 and the composite simply behaves as if the
##     weapon were part of the world.
func _make_shader() -> Shader:
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nrender_mode unshaded;\nuniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;\nuniform sampler2D accum_tex : hint_default_black, repeat_disable, filter_linear;\nuniform sampler2D gun_mask : hint_default_transparent, repeat_disable, filter_nearest;\nuniform float strength : hint_range(0.0, 1.0) = 0.12;\nuniform float dead_zone : hint_range(0.0, 0.2) = 0.01;\nuniform vec2 chroma = vec2(0.0);\nvoid fragment() {\n\tvec3 now = texture(screen_tex, SCREEN_UV).rgb;\n\tvec3 past = vec3(\n\t\ttexture(accum_tex, UV + chroma).r,\n\t\ttexture(accum_tex, UV).g,\n\t\ttexture(accum_tex, UV - chroma).b);\n\tvec3 d = past - now;\n\td = sign(d) * max(abs(d) - dead_zone, vec3(0.0));\n\td *= 1.0 - texture(gun_mask, SCREEN_UV).a;\n\tCOLOR = vec4(now + d * strength, 1.0);\n}"
	return sh
