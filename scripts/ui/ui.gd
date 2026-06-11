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

var crosshair: ColorRect  ## PERMANENT circle reticle, pinned each frame to the TRUE (swayed) aim point by Player._update_crosshair
var _crosshair_bbc: BackBufferCopy  ## full-screen back-buffer copy so the scoped inverting reticle samples a fresh screen (else it washes white)
var _flat_reticle_mat: ShaderMaterial    ## the permanent cheap dot (no screen sampling — no back-buffer cost)
var _scoped_reticle_mat: ShaderMaterial  ## the scoped inverting disc (needs the BackBufferCopy active)
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
var _money_label: Label  ## persistent top-left zorkmid readout
var _look_name: Label  ## centered name readout under the crosshair while aiming at a talkable (FNV-style)

## Bottom-corner gameplay HUD — HP (left) + ammo "clip / reserve · N clips" (right). Code-built so it's
## always visible + styled, independent of the scene's (hidden, placeholder) HP/AMMO labels.
var _hud_hp: Label
var _hud_ammo: Label
const HUD_FONT_SIZE: int = 32
const HUD_LOW_HP_FRAC: float = 0.3  ## the HP readout turns red below this fraction of max HP

const MONEY_FONT_SIZE: int = 16
const MONEY_DELTA_FONT_SIZE: int = 15
const MONEY_COLOR := Color(1.0, 0.86, 0.3)       ## gold for the persistent zorkmid readout
const MONEY_GAIN_COLOR := Color(0.45, 1.0, 0.5)  ## green +N on a gain
const MONEY_LOSS_COLOR := Color(1.0, 0.5, 0.4)   ## red -N on a spend
const MONEY_DELTA_RISE: float = 22.0             ## pixels the +N/-N floats up as it fades
const MONEY_DELTA_TIME: float = 0.8              ## seconds for that float + fade

func _ready() -> void:
	# PERMANENT circle reticle (the Deus Ex truth-teller): always visible, pinned each frame to the swayed
	# aim point by Player._update_crosshair via set_crosshair_screen_pos. Unscoped it wears a cheap flat-dot
	# material; scoping swaps in the inverting disc + its back-buffer copy (set_scoped). MOUSE_FILTER_IGNORE
	# so it never eats clicks (HUD gotcha). Plain top-left anchors: position IS the absolute screen pixel.
	crosshair = ColorRect.new()
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.custom_minimum_size = CROSSHAIR_SIZE
	crosshair.size = CROSSHAIR_SIZE
	crosshair.position = get_viewport().get_visible_rect().size * 0.5 - crosshair.size * 0.5  # start centred
	_flat_reticle_mat = ShaderMaterial.new()
	_flat_reticle_mat.shader = _make_flat_circle_shader()
	_scoped_reticle_mat = ShaderMaterial.new()
	_scoped_reticle_mat.shader = _make_circle_shader()
	crosshair.material = _flat_reticle_mat
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
	_rep_toasts.position = Vector2(6, 44)  # below the zorkmid readout
	add_child(_rep_toasts)
	# Persistent zorkmid readout in the very top-left; refreshed + a floating +N/-N spawned on
	# Player.money_changed (wired in setup). Outlined like the toasts so it reads over any backdrop.
	_money_label = Label.new()
	_money_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_money_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_money_label.position = Vector2(8, 6)
	_money_label.add_theme_font_size_override(&"font_size", MONEY_FONT_SIZE)
	_money_label.add_theme_color_override(&"font_color", MONEY_COLOR)
	_money_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_money_label.add_theme_constant_override(&"outline_size", 4)
	_money_label.text = _money_text(0)
	add_child(_money_label)
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
	_build_hud()

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

## Build the bottom-corner gameplay HUD: HP pinned bottom-left, ammo bottom-right. Driven in _process.
func _build_hud() -> void:
	_hud_hp = _make_hud_label(false)
	_hud_ammo = _make_hud_label(true)

## One HUD readout label pinned to the bottom-LEFT (right_side=false) or bottom-RIGHT (true) corner,
## white with a black outline so it reads over any scene, mouse-ignoring, above the rest of the HUD.
func _make_hud_label(right_side: bool) -> Label:
	var lbl := Label.new()
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.anchor_top = 1.0
	lbl.anchor_bottom = 1.0
	lbl.offset_top = -58.0
	lbl.offset_bottom = -14.0
	if right_side:
		lbl.anchor_left = 1.0
		lbl.anchor_right = 1.0
		lbl.offset_left = -460.0
		lbl.offset_right = -20.0
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	else:
		lbl.anchor_left = 0.0
		lbl.anchor_right = 0.0
		lbl.offset_left = 20.0
		lbl.offset_right = 460.0
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override(&"font_size", HUD_FONT_SIZE)
	lbl.add_theme_color_override(&"font_color", Color.WHITE)
	lbl.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	lbl.add_theme_constant_override(&"outline_size", 6)
	lbl.z_index = 2
	add_child(lbl)
	return lbl

## A tiny canvas-item shader that fills a Control with a soft, semi-transparent disc — the round ADS
## reticle. Samples the framebuffer behind it (hint_screen_texture + SCREEN_UV) and outputs an adaptive
## high-contrast colour: the INVERTED colour on saturated/colored backgrounds, blended toward a hard
## black/white luminance FLIP near mid-grays (where pure inversion would vanish into the background).
## So it stays visible on anything — bright, dark, colored, or gray. Built inline (no .gdshader asset).
func _make_circle_shader() -> Shader:
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nuniform sampler2D screen_tex : hint_screen_texture, filter_linear;\nvoid fragment() {\n\tfloat d = distance(UV, vec2(0.5));\n\tvec3 screen = texture(screen_tex, SCREEN_UV).rgb;\n\tfloat lum = dot(screen, vec3(0.299, 0.587, 0.114));\n\tvec3 inverted = vec3(1.0) - screen;\n\tvec3 flip = vec3(1.0 - step(0.5, lum));\n\tfloat g = 1.0 - 2.0 * abs(lum - 0.5);\n\tvec3 reticle = mix(inverted, flip, g);\n\tCOLOR = vec4(reticle, (1.0 - smoothstep(0.4, 0.5, d)) * 0.95);\n}"
	return sh

## The PERMANENT reticle's cheap material: a small white disc with a soft dark rim, no screen sampling —
## so the always-on crosshair never pays the full-screen back-buffer copy the inverting disc needs.
func _make_flat_circle_shader() -> Shader:
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nvoid fragment() {\n\tfloat d = distance(UV, vec2(0.5));\n\tfloat disc = 1.0 - smoothstep(0.38, 0.5, d);\n\tfloat rim = smoothstep(0.18, 0.42, d);\n\tvec3 col = mix(vec3(1.0), vec3(0.05), rim);\n\tCOLOR = vec4(col, disc * 0.85);\n}"
	return sh

## Swap the (now permanent) reticle between its cheap flat dot and the scoped inverting disc. Visibility no
## longer changes — the crosshair is a permanent HUD element tracking the true aim point; scoping upgrades
## its material and turns on the back-buffer copy the inverting shader needs. Null-guarded so it is safe to
## call before _ready has built the dot (mirrors the is_instance_valid defensiveness in _process).
func set_scoped(scoped: bool) -> void:
	if crosshair:
		crosshair.material = _scoped_reticle_mat if scoped else _flat_reticle_mat
	# Only pay for the full-screen back-buffer copy while the inverting disc is actually up.
	if _crosshair_bbc:
		_crosshair_bbc.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT if scoped else BackBufferCopy.COPY_MODE_DISABLED

## Pin the reticle to an absolute screen position (its centre on `p`) — the TRUE aim point, projected by
## Player._update_crosshair from the swayed shot direction, so the crosshair never lies about where a shot
## will land. Null-guarded for calls before _ready.
func set_crosshair_screen_pos(p: Vector2) -> void:
	if crosshair:
		crosshair.position = p - crosshair.size * 0.5

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

## The top-left zorkmid readout text.
func _money_text(total: int) -> String:
	return "%d zm" % total

## Player.money changed (add_money): refresh the readout and float a colour-coded +N / -N up from it.
func _on_money_changed(total: int, delta: int) -> void:
	if _money_label != null:
		_money_label.text = _money_text(total)
	if delta == 0:
		return
	var ind := Label.new()
	ind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ind.text = "+%d" % delta if delta > 0 else "%d" % delta  # a negative delta already carries its minus
	ind.add_theme_font_size_override(&"font_size", MONEY_DELTA_FONT_SIZE)
	ind.add_theme_color_override(&"font_color", MONEY_GAIN_COLOR if delta > 0 else MONEY_LOSS_COLOR)
	ind.add_theme_color_override(&"font_outline_color", Color.BLACK)
	ind.add_theme_constant_override(&"outline_size", 4)
	ind.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	ind.position = Vector2(8, 26)
	add_child(ind)
	var tw := ind.create_tween()
	tw.tween_property(ind, "position:y", ind.position.y - MONEY_DELTA_RISE, MONEY_DELTA_TIME).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(ind, "modulate:a", 0.0, MONEY_DELTA_TIME)
	tw.tween_callback(ind.queue_free)

## Inject the player whose HP this HUD shows and the ammo clip it reads. Called once by
## the host so the HUD's cross-actor refs don't depend on scene NodePaths, which get
## cleared when this layer is extracted into its own scene.
func setup(p_player: Character, p_ammo_count: Ammo) -> void:
	player = p_player
	ammo_count = p_ammo_count
	# Connect the floating +N / -N money indicator to the wallet (duck-typed: money_changed lives on Player,
	# but this HUD knows it only as a Character). The persistent readout text is POLLED in _process, not
	# seeded here, so it's right from frame one even though setup() runs before this HUD's _ready.
	if player != null and player.has_signal(&"money_changed") and not player.is_connected(&"money_changed", _on_money_changed):
		player.connect(&"money_changed", _on_money_changed)

func _process(_delta: float) -> void:
	if is_instance_valid(player) and _hud_hp != null:
		_hud_hp.text = _hp_text()
		var frac := player.hp / maxf(player.max_hp, 1.0)
		_hud_hp.add_theme_color_override(&"font_color", Color(1.0, 0.38, 0.34) if frac < HUD_LOW_HP_FRAC else Color.WHITE)
	if is_instance_valid(ammo_count) and _hud_ammo != null:
		_hud_ammo.text = _ammo_text()
	# Poll the zorkmid readout from the wallet every frame (like HP), so it's correct from frame one even
	# though setup() runs before this HUD's _ready built the label. money_changed still drives the +N/-N float.
	if _money_label != null and is_instance_valid(player):
		_money_label.text = _money_text(int(player.get(&"money")))

## HP readout, e.g. "87 / 100" (current / max).
func _hp_text() -> String:
	return "%d / %d" % [int(round(player.hp)), int(round(player.max_hp))]

## Ammo readout for the equipped weapon: "clip / reserve" (rounds in the magazine / rounds left in the
## backpack). Blank for a caliber-less weapon (melee / rock / spray) — those carry no reserve and their
## clip count is a sentinel, so there's nothing meaningful to show.
func _ammo_text() -> String:
	var weapon: WeaponData = ammo_count.current_weapon
	if weapon == null or weapon.caliber == &"" or not is_instance_valid(player) or player.inventory == null:
		return ""
	return "%d / %d" % [ammo_count.current_ammo, player.inventory.ammo_count(weapon.caliber)]
