class_name SkyTitle
extends Node3D

## A huge title card "drawn in the sky": a billboarded Label3D parked FAR in the direction the player is looking,
## so world geometry (the city skyline) OCCLUDES it -- it's a real depth-tested 3D object at sky distance -- while
## it stays big, readable, and tracks the view. It FADES IN at a cue time after the game-start spawn, so the title
## drop lands a beat into the entrance. SELF-ARMS on spawn (and the player also pings it as the spawn fade-in
## begins), so the cue always runs regardless of how the game started; reveals once it elapses. Flip
## test_show_immediately to preview it instantly while tuning.
##
## SETUP: drop ONE under the Game root. Tune cue_seconds BY EAR if it lands early/late (the cue counts from when
## the title is armed, not from any audible beat). sky_distance is auto-clamped just inside the camera's far plane
## so the title never gets clipped away.
##
## Deliberately NOT a @tool script: every node here is BUILT at runtime (_ready spawns the Label3D, the overlay
## CanvasLayer and its BackBufferCopy, then _process runs a wall-clock timeline), and none of it carries an
## `owner`, so running it in-editor would only burn frames and spawn unsaveable nodes while a scene is open.

## The title text (all-caps reads best as a sky title).
@export var text: String = "CYBER SUNDAY"
## Seconds after the intro song starts to reveal the title. 2:48 = 168s. Tune by ear.
@export var cue_seconds: float = 168.0
## Seconds the title takes to fade up from nothing.
@export var fade_in_time: float = 2.5
## Seconds the title HOLDS at full visibility before it fades back out and disappears.
@export var hold_seconds: float = 30.0
## Seconds the title takes to fade out at the end.
@export var fade_out_time: float = 2.5
## How far (m) ahead of the camera the title sits -- large, so it reads as sky distance and the skyline cuts across
## it. Auto-clamped to just inside the camera's far plane.
@export var sky_distance: float = 350.0
## On-screen size knobs (bump for bigger) + colour. The label sits at a constant distance, so its apparent size is
## steady. "CYBER SUNDAY" is WIDE -- if it overflows the screen, LOWER pixel_size (or raise sky_distance); if it
## looks tiny, raise pixel_size. Tune with test_show_immediately on.
@export var pixel_size: float = 0.25
@export var font_size: int = 256
@export var text_color: Color = Color.WHITE
## Vertical STRETCH -- 1 = normal, >1 = taller letters (a tall, imposing title), <1 = squashed. Width is unchanged.
@export var vertical_stretch: float = 1.5
## TESTING: reveal the title IMMEDIATELY (skip the ~2:48 cue) so you can see + size it without waiting. Turn OFF
## for the real timed drop.
@export var test_show_immediately: bool = false
## Also draw a DUPLICATE of the title ON TOP OF EVERYTHING (a screen overlay) with the ADS reticle's colour-
## INVERT effect -- it pops over the HUD + world (never occluded) while the sky copy gets cut by the skyline.
@export var overlay_enabled: bool = true
## Fine-tune the on-top duplicate's overall size vs the sky copy (1 = geometrically matched to the sky copy's
## on-screen box; nudge up/down to taste).
@export var overlay_size_scale: float = 1.0

var _label: Label3D = null
var _armed: bool = false
var _t: float = 0.0
var _shown_t: float = 0.0   ## seconds since the title was revealed -- drives fade-in -> hold -> fade-out
var _revealed: bool = false
var _done: bool = false     ## true once it has fully faded out -- stops further work

const OVERLAY_LAYER := 100  ## CanvasLayer for the on-top duplicate -- above the HUD, below the pause menu (128)
## Fixed reference font size the overlay Label is rasterised at ONCE; Control.scale then matches it to the sky
## copy's on-screen box each frame (so glyphs stay crisp and the text isn't re-shaped per frame). Big enough that
## the typical on-screen size is a DOWNSCALE (sharp), not an upscale (blurry).
## PRESENTATION NOTE: under HIGH FIDELITY the overlay covers ~Settings.native_scale() times (~2.4x at 1080p) more
## device px than the canvas math suggests; per-viewport font oversampling is expected to keep the glyphs crisp
## at that scale. Flagged for the windowed QA pass — no code change.
const OVERLAY_REF_FONT_SIZE := 256
var _overlay_layer: CanvasLayer = null
var _overlay_bbc: BackBufferCopy = null
var _overlay_label: Label = null
var _last_usec: int = 0     ## wall-clock timestamp of the last tick -- the cue + fade run on REAL time (immune to pause + slow-mo) so the entrance timeline never drifts

func _ready() -> void:
	add_to_group(Groups.SKY_TITLE)
	# Run on WALL-CLOCK, ALWAYS: the cue + fade time the game-start entrance, which keeps running through
	# pause / shops / slow-mo -- so the title timeline must too, or it drifts off the intended beat.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_usec = Time.get_ticks_usec()
	_label = Label3D.new()
	_label.text = text
	_label.font_size = font_size
	_label.pixel_size = pixel_size
	_label.outline_size = 0                                    # all-white, no outline
	_label.modulate = Color(text_color.r, text_color.g, text_color.b, 0.0)  # start fully transparent
	# Billboard OFF -- we orient it toward the camera MANUALLY each frame (matching the camera's basis) so a
	# non-uniform (vertical) scale survives, which Label3D's own billboard would drop.
	_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_label.double_sided = true
	_label.shaded = false                                      # flat full-bright, reads as a sky title
	_label.no_depth_test = false                               # KEEP depth test on, so the skyline occludes it
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)
	_label.visible = false
	if overlay_enabled:
		_build_overlay()
	arm()  # self-arm on spawn, so the cue runs even if nothing pings us (direct scene run / etc.)

## Start the cue countdown. Self-called on _ready (so the title works regardless of how the game started) and also
## pinged by the player as the spawn fade-in begins. Idempotent -- the first arm wins, so it counts from spawn.
func arm() -> void:
	if _armed:
		return
	_armed = true
	_t = 0.0

func _process(_delta: float) -> void:
	if not _armed or _done:
		return
	# Drive the timeline from WALL-CLOCK (immune to Engine.time_scale + pause), so the title stays on the beat of
	# the external music regardless of slow-mo / pause. (Mirrors bullet_time.gd.)
	var now := Time.get_ticks_usec()
	var rt := float(now - _last_usec) / 1_000_000.0
	_last_usec = now
	if not _revealed:
		_t += rt
		if not test_show_immediately and _t < cue_seconds:
			return
		_revealed = true
		_label.visible = true
	_shown_t += rt  # accumulate the fade clock BEFORE the camera guard, so a null-camera gap can't drift it off the beat
	# Park the title far ahead of the active camera (so it tracks where you look), kept inside the far plane.
	# Being a real 3D object at sky distance, closer geometry (the skyline) depth-occludes it.
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		# No camera (a teardown / cutscene window) -> idle the overlay so its BackBufferCopy isn't doing a
		# per-frame full-screen viewport copy with nothing to show; the lifecycle resumes when a camera returns.
		if _overlay_label != null and _overlay_label.visible:
			_overlay_label.visible = false
			_overlay_bbc.copy_mode = BackBufferCopy.COPY_MODE_DISABLED
		return
	var cb := cam.global_transform.basis.orthonormalized()
	var dist := minf(sky_distance, cam.far * 0.9)
	var world_center := cam.global_position - cb.z * dist
	# Face the camera by matching its basis (the label's +Z points back at the camera -> readable, not mirrored),
	# with the UP column scaled for the vertical STRETCH -> camera-facing AND taller. Parked far ahead (along the
	# camera's -Z) so the skyline depth-occludes it.
	_label.global_transform = Transform3D(Basis(cb.x, cb.y * vertical_stretch, cb.z), world_center)
	# Lifecycle: fade IN -> HOLD (hold_seconds) -> fade OUT, then hide for good (_shown_t advanced above the cam guard).
	var fi := maxf(fade_in_time, 0.001)
	var fo := maxf(fade_out_time, 0.001)
	var alpha := 1.0  # the HOLD level (between fade-in and fade-out)
	if _shown_t < fi:
		alpha = _shown_t / fi                                  # fading in
	elif _shown_t >= fi + hold_seconds + fo:
		alpha = 0.0                                            # done -> gone
		_done = true
		_label.visible = false
	elif _shown_t > fi + hold_seconds:
		alpha = 1.0 - (_shown_t - fi - hold_seconds) / fo      # fading out
	_label.modulate = Color(text_color.r, text_color.g, text_color.b, alpha)
	# Drive the on-top inverted duplicate in lockstep: same screen-centre, same fade.
	if _overlay_label != null:
		_sync_overlay(cam, world_center, cb.y, alpha)

## Build the on-top duplicate: a screen-centred Label on a high CanvasLayer that INVERTS the screen behind its
## glyphs (the same adaptive invert as the ADS reticle), fed by a full-screen BackBufferCopy. It draws over the
## HUD + world, so it stays crisp while the sky copy gets occluded by the skyline.
func _build_overlay() -> void:
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = OVERLAY_LAYER
	add_child(_overlay_layer)
	# A fresh full-screen back buffer so the invert samples the real screen (else 1.0 - screen washes to white).
	# Only runs while the title is up (toggled in _sync_overlay).
	_overlay_bbc = BackBufferCopy.new()
	_overlay_bbc.copy_mode = BackBufferCopy.COPY_MODE_DISABLED
	_overlay_layer.add_child(_overlay_bbc)
	_overlay_label = Label.new()
	_overlay_label.text = text
	_overlay_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Content-sized + manually placed/scaled each frame (see _sync_overlay) so it lands EXACTLY on the sky copy's
	# on-screen box, INCLUDING its vertical stretch. Rasterised once at OVERLAY_REF_FONT_SIZE; Control.scale sizes it.
	_overlay_label.add_theme_font_size_override(&"font_size", OVERLAY_REF_FONT_SIZE)
	var mat := ShaderMaterial.new()
	mat.shader = _make_invert_text_shader()
	_overlay_label.material = mat
	_overlay_label.modulate.a = 0.0
	_overlay_label.visible = false
	_overlay_label.z_index = 1  # above the back-buffer copy (z 0)
	_overlay_layer.add_child(_overlay_label)

## Keep the duplicate in lockstep with the sky copy: shown only while the title is up (and in front of the
## camera), faded by the same alpha, and font-sized to match its on-screen height (projected each frame, only
## re-applied when it actually changes so the text isn't re-shaped every frame).
func _sync_overlay(cam: Camera3D, world_center: Vector3, up: Vector3, alpha: float) -> void:
	var showing := _revealed and alpha > 0.002 and not cam.is_position_behind(world_center)
	if _overlay_label.visible != showing:
		_overlay_label.visible = showing
		_overlay_bbc.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT if showing else BackBufferCopy.COPY_MODE_DISABLED
	if not showing:
		return
	_overlay_label.modulate.a = alpha
	var font := _overlay_label.get_theme_font(&"font")
	if font == null:
		return
	# The overlay's NATURAL pixel size at the reference font (same default font + glyphs as the sky Label3D).
	var nat := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, OVERLAY_REF_FONT_SIZE)
	if nat.x < 1.0 or nat.y < 1.0:
		return
	# Land EXACTLY on the sky copy's on-screen box. The sky Label3D is stretched VERTICALLY (vertical_stretch), but
	# a 2D Label scales uniformly per glyph -> scale X / Y INDEPENDENTLY: Y to the sky copy's projected (stretched)
	# height, X to its UNSTRETCHED width (= scale.y / vertical_stretch). Both heights are font-METRIC based
	# (get_height / get_string_size) so they stay consistent. (The OLD code fed a projected pixel HEIGHT straight in
	# as a font_size -- oversizing by the line-height factor -- and ignored the stretch, which made it ~vertical_stretch
	# too WIDE: the huge, overflowing, misaligned duplicate.)
	var sky_world_half_h := font.get_height(font_size) * pixel_size * vertical_stretch * 0.5
	# Both anchors go through the world LENS's display map: the sky copy this overlay welds onto is bent
	# by the post barrel warp, while this label draws ABOVE it — unmapped, the pair detaches by the warp
	# displacement at the title's radius (the sniper-glint fix; see CameraSettings.lens_display_point).
	# Warping BOTH points also keeps the projected height measure consistent with the displayed glyphs.
	var canvas := get_viewport().get_visible_rect().size
	var rs := Vector2(Settings.render_size())
	var lens_k: float = GameSettings.camera.lens_barrel_amount * clampf(Settings.lens_curve, 0.0, 1.0)
	var p_c := CameraSettings.lens_display_point(cam.unproject_position(world_center), canvas, rs.x / rs.y, lens_k)
	var p_top := CameraSettings.lens_display_point(cam.unproject_position(world_center + up * sky_world_half_h), canvas, rs.x / rs.y, lens_k)
	var sky_h_px := p_c.distance_to(p_top) * 2.0  # the sky copy's full on-screen (stretched) height, px
	var sy := (sky_h_px / nat.y) * maxf(overlay_size_scale, 0.01)
	var sx := sy / maxf(vertical_stretch, 0.001)   # width tracks the sky copy's UNstretched width
	_overlay_label.size = nat
	_overlay_label.pivot_offset = nat * 0.5
	_overlay_label.scale = Vector2(sx, sy)
	_overlay_label.position = p_c - nat * 0.5      # the scaled box centred on the sky copy's screen point

## Inline canvas_item shader for the duplicate: invert the screen behind each glyph (the ADS reticle's adaptive
## invert -- pure inversion on colour, a hard black/white luminance FLIP near mid-grays so it never vanishes),
## masked by the font glyph coverage and the label's fade alpha.
func _make_invert_text_shader() -> Shader:
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nuniform sampler2D screen_tex : hint_screen_texture, filter_linear;\nvoid fragment() {\n\tfloat glyph = texture(TEXTURE, UV).a;\n\tvec3 screen = texture(screen_tex, SCREEN_UV).rgb;\n\tfloat lum = dot(screen, vec3(0.299, 0.587, 0.114));\n\tvec3 inverted = vec3(1.0) - screen;\n\tvec3 flip = vec3(1.0 - step(0.5, lum));\n\tfloat g = 1.0 - 2.0 * abs(lum - 0.5);\n\tvec3 outc = mix(inverted, flip, g);\n\tCOLOR = vec4(outc, glyph * COLOR.a);\n}"
	return sh
