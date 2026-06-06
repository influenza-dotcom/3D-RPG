class_name UI
extends CanvasLayer

## HUD layer. Polls the player's HP and the Ammo clip each frame to refresh the
## labels, and owns the BloodSplatter overlay that Player.on_nearby_death drives.
## The is_instance_valid guards below matter: player/ammo can be freed during a
## death/scene reload while this layer briefly persists.

@export var player: Character
@export var ammo_count: Ammo
@export var hp: Label
@export var ammo: Label
@export var blood_splatter: BloodSplatter

var crosshair: ColorRect  ## centered semi-transparent circle reticle (inverts whatever's behind it); shown only while scoped (ADS)
var _crosshair_bbc: BackBufferCopy  ## full-screen back-buffer copy so the inverting reticle samples a fresh screen (else it washes white)
const CROSSHAIR_SIZE := Vector2(4, 4)  ## reticle box (px); a shader discs it — smaller than the old 6px square

## Scope optics overlays: a darkening vignette + an additive anamorphic lens flare, shown only while
## scoped down the rifle (set_scope_optics). Built in _ready so they ride the same HUD layer.
const SCOPE_VIGNETTE_SHADER := preload("res://resources/shaders/scope_vignette.gdshader")
const SCOPE_FLARE_SHADER := preload("res://resources/shaders/scope_lens_flare.gdshader")
var _scope_vignette: ColorRect
var _scope_flare: ColorRect

## Reputation toasts: fading "[Faction] reputation gained!/lost!" lines stacked in the top-left,
## driven by the Reputation autoload's reputation_changed signal.
const REP_TOAST_HOLD: float = 2.5    ## seconds a toast holds before fading
const REP_TOAST_FADE: float = 1.0    ## fade-out duration
const REP_TOAST_FONT_SIZE: int = 10
const REP_GAIN_COLOR := Color(0.4, 1.0, 0.45)
const REP_LOSS_COLOR := Color(1.0, 0.45, 0.4)
const REP_NEUTRAL_COLOR := Color(0.85, 0.85, 0.85)
var _rep_toasts: VBoxContainer
var _look_name: Label  ## centered name readout under the crosshair while aiming at a talkable (FNV-style)

func _ready() -> void:
	# Centered semi-transparent CIRCLE reticle that inverts the view behind it. Hidden until ScopeIn
	# reports scoped-in (set_scoped). MOUSE_FILTER_IGNORE so it never eats clicks (HUD gotcha).
	crosshair = ColorRect.new()
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.custom_minimum_size = CROSSHAIR_SIZE
	crosshair.size = CROSSHAIR_SIZE
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = -crosshair.size * 0.5  # centre the box on the screen centre
	# A tiny canvas shader turns the box into a soft, semi-transparent disc that shows the inverted
	# colour of the view behind it (a round reticle).
	var circle_mat := ShaderMaterial.new()
	circle_mat.shader = _make_circle_shader()
	crosshair.material = circle_mat
	crosshair.visible = false
	crosshair.z_index = 2  # above the scope overlays + the back-buffer copy, so the reticle is always on top
	add_child(crosshair)
	# Scope optics: a vignette (darkens the edges) + a lens flare (additive anamorphic streak), both
	# full-rect, mouse-ignoring, hidden until set_scope_optics shows them on a rifle scope-in. Added
	# AFTER the crosshair so they composite on top of the rest of the HUD.
	_scope_vignette = _make_scope_overlay(SCOPE_VIGNETTE_SHADER)
	_scope_flare = _make_scope_overlay(SCOPE_FLARE_SHADER)
	# Guarantee the inverting crosshair samples a FRESH, full-screen back buffer. A tiny ColorRect's
	# automatic screen-texture copy can read stale/empty pixels, so 1.0 - screen washes to solid white.
	# This copy sits just below the reticle (z 1 < 2) and only runs while scoped (toggled in set_scoped).
	_crosshair_bbc = BackBufferCopy.new()
	_crosshair_bbc.copy_mode = BackBufferCopy.COPY_MODE_DISABLED
	_crosshair_bbc.z_index = 1
	add_child(_crosshair_bbc)
	# Reputation toasts in the top-left, driven by the Reputation autoload.
	_rep_toasts = VBoxContainer.new()
	_rep_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rep_toasts.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_rep_toasts.position = Vector2(6, 6)
	add_child(_rep_toasts)
	if not Reputation.reputation_changed.is_connected(_on_reputation_changed):
		Reputation.reputation_changed.connect(_on_reputation_changed)
	if not Reputation.alignment_changed.is_connected(_on_alignment_changed):
		Reputation.alignment_changed.connect(_on_alignment_changed)
	# Look-at name readout (FNV-style): a centered label just below the crosshair, shown while aiming at a
	# talkable target (set_look_name). Hidden until then.
	_look_name = Label.new()
	_look_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_look_name.anchor_left = 0.0
	_look_name.anchor_right = 1.0
	_look_name.anchor_top = 0.5
	_look_name.anchor_bottom = 0.5
	_look_name.offset_top = 16.0
	_look_name.offset_bottom = 44.0
	_look_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_look_name.add_theme_font_size_override(&"font_size", 15)
	_look_name.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_look_name.add_theme_constant_override(&"outline_size", 5)
	_look_name.visible = false
	_look_name.z_index = 2
	add_child(_look_name)

## Build one full-rect, input-ignoring HUD overlay carrying `shader`, hidden by default.
func _make_scope_overlay(shader: Shader) -> ColorRect:
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = shader
	rect.material = mat
	rect.visible = false
	add_child(rect)
	return rect

## A tiny canvas-item shader that fills a Control with a soft, semi-transparent disc — the round ADS
## reticle. Samples the framebuffer behind it (hint_screen_texture + SCREEN_UV) and outputs an adaptive
## high-contrast colour: the INVERTED colour on saturated/colored backgrounds, blended toward a hard
## black/white luminance FLIP near mid-grays (where pure inversion would vanish into the background).
## So it stays visible on anything — bright, dark, colored, or gray. Built inline (no .gdshader asset).
func _make_circle_shader() -> Shader:
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nuniform sampler2D screen_tex : hint_screen_texture, filter_linear;\nvoid fragment() {\n\tfloat d = distance(UV, vec2(0.5));\n\tvec3 screen = texture(screen_tex, SCREEN_UV).rgb;\n\tfloat lum = dot(screen, vec3(0.299, 0.587, 0.114));\n\tvec3 inverted = vec3(1.0) - screen;\n\tvec3 flip = vec3(1.0 - step(0.5, lum));\n\tfloat g = 1.0 - 2.0 * abs(lum - 0.5);\n\tvec3 reticle = mix(inverted, flip, g);\n\tCOLOR = vec4(reticle, (1.0 - smoothstep(0.4, 0.5, d)) * 0.95);\n}"
	return sh

## Toggle the aiming reticle with the scope state. Null-guarded so it is safe to call before
## _ready has built the dot (mirrors the is_instance_valid defensiveness in _process).
func set_scoped(scoped: bool) -> void:
	if crosshair:
		crosshair.visible = scoped
	# Only pay for the full-screen back-buffer copy while the reticle is actually up.
	if _crosshair_bbc:
		_crosshair_bbc.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT if scoped else BackBufferCopy.COPY_MODE_DISABLED

## Show/hide the look-at name readout (FNV-style) under the crosshair. Empty text hides it; a colour tints
## the name (e.g. green for a friendly NPC). Driven by Player.on_look_target_changed via the interaction ray.
func set_look_name(text: String, color: Color) -> void:
	if _look_name == null:
		return
	if text.is_empty():
		_look_name.visible = false
		return
	_look_name.text = text
	_look_name.add_theme_color_override(&"font_color", color)
	_look_name.visible = true

## Show/hide the rifle scope optics (vignette + lens flare). Driven by player._on_scoped_in; only the
## scoped rifle turns these on, so a generic ADS weapon still scopes without the scope-tunnel look.
func set_scope_optics(on: bool) -> void:
	if _scope_vignette:
		_scope_vignette.visible = on
	if _scope_flare:
		_scope_flare.visible = on

## Pop a fading "[Faction] reputation gained!/lost!" toast in the top-left when standing changes.
func _on_reputation_changed(faction: Faction, delta: float, _new_total: float) -> void:
	if faction == null or delta == 0.0:
		return
	_push_toast("%s reputation %s!" % [_faction_name(faction), ("gained" if delta > 0.0 else "lost")],
			CBPalette.gain() if delta > 0.0 else CBPalette.loss())

## Announce the new standing when a faction's disposition toward the player crosses a threshold.
func _on_alignment_changed(faction: Faction, new_kind: int) -> void:
	if faction == null:
		return
	var kind_text := "Neutral"
	var col := REP_NEUTRAL_COLOR
	match new_kind:
		Disposition.Kind.HOSTILE:
			kind_text = "Hostile"
			col = CBPalette.loss()
		Disposition.Kind.FRIENDLY:
			kind_text = "Friendly"
			col = CBPalette.gain()
	_push_toast("%s is now %s!" % [_faction_name(faction), kind_text], col)

func _faction_name(faction: Faction) -> String:
	return faction.display_name if not faction.display_name.is_empty() else String(faction.id)

## Public entry for one-off gameplay toasts (sneak result, limb cripples, ...). Routed through the same
## fading top-left stack + style as the reputation toasts so all notifications read consistently.
func push_toast(text: String, color: Color) -> void:
	_push_toast(text, color)

## Stack a fading, colour-coded line in the top-left (newest on top).
func _push_toast(text: String, color: Color) -> void:
	if _rep_toasts == null:
		return
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"font_size", REP_TOAST_FONT_SIZE)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 4)
	_rep_toasts.add_child(label)
	_rep_toasts.move_child(label, 0)  # newest at the top
	var tw := label.create_tween()
	tw.tween_interval(REP_TOAST_HOLD)
	tw.tween_property(label, "modulate:a", 0.0, REP_TOAST_FADE)
	tw.tween_callback(label.queue_free)

## Inject the player whose HP this HUD shows and the ammo clip it reads. Called once by
## the host so the HUD's cross-actor refs don't depend on scene NodePaths, which get
## cleared when this layer is extracted into its own scene.
func setup(p_player: Character, p_ammo_count: Ammo) -> void:
	player = p_player
	ammo_count = p_ammo_count

func _process(_delta: float) -> void:
	if is_instance_valid(player):
		hp.text = str(player.hp)
	
	if is_instance_valid(ammo_count):
		ammo.text = "%d" % ammo_count.current_ammo
