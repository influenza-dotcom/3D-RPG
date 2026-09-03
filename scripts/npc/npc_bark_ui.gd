class_name NpcBarkUi
extends Node3D

## NPC head-popup PRESENTATION, split off npc.gd. Owns the bark speech BUBBLE and the billboarded head ICONS (the
## "!" alert, the turned-hostile cue) — their build / position / fade-then-free lifecycle. Built as a child in
## NPC._build_components (host = the NPC, at the NPC's local origin so every position stays head-relative exactly as
## before); the NPC drives it through thin facades (_popup_text / _popup_icon / _clear_bark_bubble), so all call
## sites — including the cross-NPC `saved._popup_icon(...)` — are unchanged.

## Shipped popup defaults, kept as consts so npc.gd's STATIC reads (NpcBarkUi.POPUP_HOLD / .POPUP_FADE in
## _bark_duration_ms, which runs off-tree with no instance) still resolve and the GUT pins stay green. The
## inspector @export vars below default to these — designers tune the instance, the consts stay the baseline.
const POPUP_HEAD_Y: float = 1.5
const POPUP_HOLD: float = 0.35
const POPUP_FADE: float = 0.65
const POPUP_WORLD_HEIGHT: float = 0.7
const BUBBLE_WIDTH_PER_CHAR: float = 0.5
const BUBBLE_WIDTH_PAD: float = 0.18
const BUBBLE_HEIGHT_SCALE: float = 1.25
const BUBBLE_HEIGHT_PAD: float = 0.12
const BUBBLE_HOLD_BASE: float = 0.8
const BUBBLE_HOLD_PER_CHAR: float = 0.09

## Bubble / icon sizing + timing — inspector-tunable, defaulting to the shipped consts above, so behaviour
## (and any test) stays identical unless a designer overrides them.
@export var popup_head_y: float = POPUP_HEAD_Y          ## head-relative Y the "!" icon / bubble float at
@export var popup_hold: float = POPUP_HOLD              ## min seconds a popup holds before it fades
@export var popup_fade: float = POPUP_FADE              ## seconds the fade-out tween runs
@export var popup_world_height: float = POPUP_WORLD_HEIGHT  ## head-icon height (m); any texture scales to this

## Bark-bubble background SIZING heuristic (a length estimate — padding absorbs proportional fonts).
@export var bubble_width_per_char: float = BUBBLE_WIDTH_PER_CHAR  ## width metres per char (× font_size × pixel_size)
@export var bubble_width_pad: float = BUBBLE_WIDTH_PAD       ## extra width padding (metres)
@export var bubble_height_scale: float = BUBBLE_HEIGHT_SCALE ## height as a multiple of one text line
@export var bubble_height_pad: float = BUBBLE_HEIGHT_PAD     ## extra height padding (metres)
## The pointer drawn under the bubble. ART, not copy — it must never become a translation msgid (a translator
## has nothing to translate, and a "translated" arrow would break the shape), which is why it lives here as a
## designer knob rather than in PlayerText. U+25BC BLACK DOWN-POINTING TRIANGLE; re-skin to taste.
@export var bubble_tail_glyph: String = "▼"

## Bark HOLD heuristic — longer lines linger longer before fading.
@export var bubble_hold_base: float = BUBBLE_HOLD_BASE       ## base hold seconds for the bubble
@export var bubble_hold_per_char: float = BUBBLE_HOLD_PER_CHAR  ## extra hold seconds per character

var host: Node = null
var _bark_bubble: Node3D = null  ## the live bark speech bubble (force-cleared on entering dialogue, via clear())

static var _bubble_bg_tex: ImageTexture

## A cached 1x1 white texture for the bark bubble's tinted background sprite.
static func _bubble_bg_texture() -> ImageTexture:
	if _bubble_bg_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_bubble_bg_tex = ImageTexture.create_from_image(img)
	return _bubble_bg_tex

## A world-space SPEECH BUBBLE above the head (parented to us, which sits at the NPC's origin, so it follows the NPC
## as it moves): a black panel + the bark text + a small downward "▼" tail. All Y-billboarded (BILLBOARD_FIXED_Y) so
## they yaw to the camera TOGETHER as one upright card. Floated well above popup_head_y so it clears the "!" alert.
func show_text(text: String) -> void:
	if text.is_empty() or not is_inside_tree():
		return
	var bubble := Node3D.new()
	add_child(bubble)  # parented to US (at the NPC origin) so the bubble tracks the NPC's movement as it walks
	_bark_bubble = bubble  # remember it so entering dialogue can force-clear it (see clear())
	bubble.position = Vector3(0.0, popup_head_y + 0.35, 0.0)  # just above the head

	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y  # yaw-only so the whole bubble stays one upright card
	label.no_depth_test = true   # read through walls / our own mesh, like the "!"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.font_size = 56
	label.pixel_size = 0.004     # world metres per font pixel
	label.modulate = Color.WHITE
	label.render_priority = 2    # draw the text OVER the bubble bg
	bubble.add_child(label)

	# Black bubble background, sized to the text (a length heuristic — padding absorbs proportional fonts).
	var w := maxf(float(text.length()) * bubble_width_per_char * label.font_size * label.pixel_size, 0.4) + bubble_width_pad
	var h := bubble_height_scale * label.font_size * label.pixel_size + bubble_height_pad
	var bg := Sprite3D.new()
	bg.texture = _bubble_bg_texture()
	bg.modulate = Color(0.0, 0.0, 0.0, 0.92)
	bg.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	bg.shaded = false
	bg.no_depth_test = true
	bg.pixel_size = 1.0
	bg.scale = Vector3(w, h, 1.0)  # 1x1 tex * pixel_size 1.0 = 1 m, scaled to w x h metres
	bg.render_priority = 1
	bubble.add_child(bg)

	# A small black tail under the bubble pointing down at us; same Y-billboard as the panel so it tracks
	# dead-centre below it instead of drifting. The glyph is SHAPE, not copy (see bubble_tail_glyph) — it is
	# drawn with a Label3D only because that is the cheapest way to paint it beside the text.
	var tail := Label3D.new()
	tail.text = bubble_tail_glyph
	tail.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	tail.no_depth_test = true
	tail.font_size = 48
	tail.pixel_size = 0.004
	tail.modulate = Color(0.0, 0.0, 0.0, 0.92)
	tail.render_priority = 1
	bubble.add_child(tail)
	tail.position = Vector3(0.0, -h * 0.6, 0.0)

	# Hold (longer for longer lines), THEN fade the whole bubble out together + free. NB: use .parallel() per fade,
	# NOT set_parallel(true), so the fades don't run during the hold.
	var tween := bubble.create_tween()
	tween.tween_interval(maxf(popup_hold, bubble_hold_base + float(text.length()) * bubble_hold_per_char))
	tween.tween_property(label, "modulate:a", 0.0, popup_fade)
	tween.parallel().tween_property(bg, "modulate:a", 0.0, popup_fade)
	tween.parallel().tween_property(tail, "modulate:a", 0.0, popup_fade)
	# Label3D draws a separate text OUTLINE whose alpha modulate:a does NOT touch — fade it in lockstep so the "▼"
	# tail / text edge don't keep an opaque outline after the panel fades.
	tween.parallel().tween_property(label, "outline_modulate:a", 0.0, popup_fade)
	tween.parallel().tween_property(tail, "outline_modulate:a", 0.0, popup_fade)
	tween.tween_callback(_on_bubble_finished.bind(bubble))

## Natural end of a bark bubble's fade: free it + drop our handle (so clear() has nothing stale).
func _on_bubble_finished(bubble: Node3D) -> void:
	if _bark_bubble == bubble:
		_bark_bubble = null
	if is_instance_valid(bubble):
		bubble.queue_free()

## Immediately remove the current bark speech bubble (if any). Called on entering dialogue so a lingering bark
## balloon doesn't hang over the conversation. (The NPC's no-overlap gate reset stays on the NPC facade.)
func clear() -> void:
	if is_instance_valid(_bark_bubble):
		_bark_bubble.queue_free()
	_bark_bubble = null

## Build the head-icon Sprite3D, UN-parented and un-animated: `tex` the cue art, `world_height` the metres it is
## scaled to (any texture). Every flag here shapes the sprite's MATERIAL VARIANT (billboard, not fixed-size,
## no_depth_test, unshaded) — which is why it lives in one static: show_icon and the in-level EffectPrewarmer
## (which draws one "!" near-invisibly on the black fade-in after a level loads, so the first alert doesn't
## compile it mid-firefight) must build the identical object. tests/test_effect_prewarm.gd pins the routing.
static func build_icon(tex: Texture2D, world_height: float) -> Sprite3D:
	var icon := Sprite3D.new()
	icon.texture = tex
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED  # always face the camera
	icon.fixed_size = false      # world-space: planted above the head + scales with distance
	icon.no_depth_test = true    # read through walls / our own mesh so the cue is never occluded
	icon.shaded = false          # flat, unlit
	var tex_height := float(tex.get_height()) if tex != null else 1.0
	icon.pixel_size = world_height / maxf(tex_height, 1.0)  # ~world_height m tall, any texture
	return icon

## Pop a billboarded icon above the head, hold briefly, fade its alpha to 0, then free — built through build_icon.
## Used by the alert "!" and the turn-hostile cue. extra_y nudges the icon off the default head height so distinct
## cues don't stack. follow=true parents it to us (tracks movement); follow=false parents to the tree root so the
## cue SURVIVES our death (a one-shotted friendly still pops the "negative" icon even as we're freed this frame).
func show_icon(tex: Texture2D, follow: bool = false, extra_y: float = 0.0) -> void:
	if tex == null or not is_inside_tree():
		return
	var icon := build_icon(tex, popup_world_height)
	if follow:
		add_child(icon)
		icon.position = Vector3(0.0, popup_head_y + extra_y, 0.0)
	else:
		get_tree().root.add_child(icon)
		icon.global_position = global_position + Vector3(0.0, popup_head_y + extra_y, 0.0)
	var tween := icon.create_tween()
	tween.tween_interval(popup_hold)
	tween.tween_property(icon, "modulate:a", 0.0, popup_fade)
	tween.tween_callback(icon.queue_free)
