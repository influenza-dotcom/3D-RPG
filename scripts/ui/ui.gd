class_name UI
extends CanvasLayer

## HUD layer. Polls the player's HP and the Ammo clip each frame to refresh the
## labels, and owns the BloodSplatter overlay that Player.on_nearby_death drives.
## The is_instance_valid guards below matter: player/ammo can be freed during a
## death/scene reload while this layer briefly persists.

@export_group("Data Sources")
## The Character whose HP this HUD reads each frame (the player). Usually re-injected by setup(); the scene
## NodePath here is the editor fallback before the host wires it.
@export var player: Character
## The Ammo clip this HUD polls for the "clip / reserve" readout. Re-injected by setup(); the NodePath is
## the editor fallback.
@export var ammo_count: Ammo
@export_group("Scene Label Fallbacks")
## Scene's placeholder HP Label (kept hidden — the live bottom-left HP readout is code-built). Wire the
## scene's HP label here if you author one; the HUD does not require it.
@export var hp: Label
## Scene's placeholder ammo Label (kept hidden — the live bottom-right ammo readout is code-built). Wire the
## scene's ammo label here if you author one; the HUD does not require it.
@export var ammo: Label
@export_group("Overlays")
## The full-screen BloodSplatter overlay this HUD owns; flashed by Player.on_nearby_death when something
## dies near the player. Point it at the BloodSplatter node in the HUD scene.
@export var blood_splatter: BloodSplatter

var crosshair: ColorRect  ## PERMANENT circle reticle, pinned each frame to the TRUE (swayed) aim point by Player._update_crosshair
var _crosshair_bbc: BackBufferCopy  ## full-screen back-buffer copy so the scoped inverting reticle samples a fresh screen (else it washes white)
var _flat_reticle_mat: ShaderMaterial    ## the permanent cheap dot (no screen sampling — no back-buffer cost)
var _scoped_reticle_mat: ShaderMaterial  ## the scoped inverting disc (needs the BackBufferCopy active)
var CROSSHAIR_SIZE: Vector2 = GameSettings.hud.crosshair_size  ## reticle box (px); a shader discs it

## Scope optics overlays: a darkening vignette + an additive anamorphic lens flare, shown only while
## scoped down the rifle (set_scope_optics). Built in _ready so they ride the same HUD layer.
const SCOPE_VIGNETTE_SHADER := preload("res://resources/shaders/scope_vignette.gdshader")
const SCOPE_FLARE_SHADER := preload("res://resources/shaders/scope_lens_flare.gdshader")
var _scope_vignette: ColorRect
var _scope_flare: ColorRect

## Reputation toasts: fading "[Faction] reputation gained!/lost!" lines stacked in the top-left,
## driven by the Reputation autoload's reputation_changed signal.
var REP_TOAST_HOLD: float = GameSettings.hud.rep_toast_hold       ## seconds a toast holds before fading
var REP_TOAST_FADE: float = GameSettings.hud.rep_toast_fade       ## fade-out duration
var REP_TOAST_FONT_SIZE: int = GameSettings.hud.rep_toast_font_size
## Gain/loss toast colours come from CBPalette (colorblind-aware), NOT captures here; only neutral is a HUD knob.
var REP_NEUTRAL_COLOR: Color = GameSettings.hud.rep_neutral_color
var _rep_toasts: VBoxContainer
var _money_label: Label  ## persistent top-left zorkmid readout
var _dialogue_toast_texts: Array[String] = []  ## quest transition toasts earned during dialogue; flushed when it closes
var _dialogue_toast_colors: Array[Color] = []
## Container for the TRANSIENT top-left notifications (the toast stack + the floating +N/-N money deltas).
## Hidden while a conversation is up so popups don't break the letterboxed cinematic; the persistent zorkmid
## readout stays (it's HUD, not a notification). Quest transition toasts are queued until the conversation closes
## so terminal turn-ins still visibly announce completion; generic one-off toasts keep their existing timing.
var _notices: Control
var _look_name: Label  ## centered name readout under the crosshair while aiming at a talkable (FNV-style)
var _quest_tracker: Label  ## top-right active-objective line, refreshed off the GameState quest signals (+ toasts)

## Bottom-corner gameplay HUD — HP (left) + ammo "clip / reserve · N clips" (right). Code-built so it's
## always visible + styled, independent of the scene's (hidden, placeholder) HP/AMMO labels.
var _hp_bar: Control                    ## bottom-left segmented HP bar (red), rebuilt when max HP changes
var _hp_fills: Array[ColorRect] = []    ## per-segment fill rects (index = HP unit, left-to-right)
var _hp_seg_count: int = 0              ## current segment count (= round(max_hp)); a change triggers a rebuild
var _stamina_bar: Control
var _stamina_fill: ColorRect
var _hud_ammo: Label
var _hotbar: Hotbar  ## bottom-centre quick slots (keys 1-0), built in setup once the player is known
var HUD_FONT_SIZE: int = GameSettings.hud.hud_font_size
## Segmented HP bar (bottom-left): one red segment per ~1 max HP, with the ammo readout just beneath it.
var HP_SEG_SIZE: Vector2 = GameSettings.hud.hp_seg_size      ## one HP segment, w x h
var HP_SEG_GAP: float = GameSettings.hud.hp_seg_gap          ## px between segments
var HP_BAR_INSET: Vector2 = GameSettings.hud.hp_bar_inset    ## bar origin: x from the left edge, y up from the bottom
var HP_SEG_EMPTY: Color = GameSettings.hud.hp_seg_empty      ## a drained segment (dark, translucent)
var HP_SEG_FILL: Color = GameSettings.hud.hp_seg_fill        ## live HP (bright red)
var HP_SEG_LOW: Color = GameSettings.hud.hp_seg_low          ## glows hotter with one segment of HP left
var STAMINA_BAR_SIZE: Vector2 = GameSettings.hud.stamina_bar_size
var STAMINA_BAR_GAP: float = GameSettings.hud.stamina_bar_gap
var STAMINA_EMPTY: Color = GameSettings.hud.stamina_empty
var STAMINA_FILL: Color = GameSettings.hud.stamina_fill
var STAMINA_LOW: Color = GameSettings.hud.stamina_low

var MONEY_FONT_SIZE: int = GameSettings.hud.money_font_size
var MONEY_DELTA_FONT_SIZE: int = GameSettings.hud.money_delta_font_size
var MONEY_COLOR: Color = GameSettings.hud.money_color              ## gold for the persistent zorkmid readout
var MONEY_GAIN_COLOR: Color = GameSettings.hud.money_gain_color    ## green +N on a gain
var MONEY_LOSS_COLOR: Color = GameSettings.hud.money_loss_color    ## red -N on a spend
var MONEY_DELTA_RISE: float = GameSettings.hud.money_delta_rise    ## pixels the +N/-N floats up as it fades
var MONEY_DELTA_TIME: float = GameSettings.hud.money_delta_time    ## seconds for that float + fade

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
	# The reticle hide/show while a conversation is up is folded into _on_dialogue_started / _on_dialogue_finished
	# below — NOT a `set_crosshair_visible.bind(false)` connection: dialogue_started now emits the DialogueResource,
	# so that bound setter would be called with TWO args (resource + the bound false) and error "expected 1, got 2"
	# (Godot 4 does NOT drop extra signal args). The signal reaches the HUD via the _on_dialogue_started_signal
	# adapter (connected below), which accepts the resource arg and forwards to the 0-arg _on_dialogue_started.
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
	# Transient-notification layer: everything popup-like in the top-left lives under this one container so
	# dialogue can hide the whole cluster at once (full-rect at the origin, so children keep their absolute
	# screen positions; mouse-ignore like everything else in the HUD).
	_notices = Control.new()
	_notices.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notices.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_notices)
	if not DialogueManager.dialogue_started.is_connected(_on_dialogue_started_signal):
		DialogueManager.dialogue_started.connect(_on_dialogue_started_signal)
	if not DialogueManager.dialogue_finished.is_connected(_on_dialogue_finished):
		DialogueManager.dialogue_finished.connect(_on_dialogue_finished)
	# Reputation toasts in the top-left, driven by the Reputation autoload.
	_rep_toasts = VBoxContainer.new()
	_rep_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rep_toasts.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_rep_toasts.position = Vector2(6, 44)  # below the zorkmid readout
	_notices.add_child(_rep_toasts)
	# Quest tracker: the current active objective, pinned to the FREE top-right corner (money/rep/toasts are
	# top-left, HP/ammo bottom). Right-anchored + right-aligned so it grows leftward from the corner. Refreshed
	# off the GameState quest signals; hidden when no quest is active. (Exact inset is playtest-tunable.)
	_quest_tracker = Label.new()
	_quest_tracker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quest_tracker.anchor_left = 1.0
	_quest_tracker.anchor_right = 1.0
	_quest_tracker.grow_horizontal = Control.GROW_DIRECTION_BEGIN  # auto-size leftward from the right edge
	_quest_tracker.offset_right = -8.0
	_quest_tracker.offset_top = 8.0
	_quest_tracker.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_quest_tracker.add_theme_font_size_override(&"font_size", REP_TOAST_FONT_SIZE)
	_quest_tracker.add_theme_color_override(&"font_color", Color(0.85, 0.95, 1.0))
	_quest_tracker.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_quest_tracker.add_theme_constant_override(&"outline_size", 4)
	_quest_tracker.visible = false
	_notices.add_child(_quest_tracker)
	# Quest feedback: tracker line + toasts, driven by the GameState quest signals (an autoload, self-wired here).
	GameState.quest_started.connect(_on_quest_started)
	GameState.objective_advanced.connect(_on_quest_objective)
	GameState.quest_completed.connect(_on_quest_completed)
	GameState.quest_failed.connect(_on_quest_failed)
	_refresh_quest_tracker()  # show any already-active quest (e.g. one restored from a save) from frame one
	# B-F40: if the last profile load dropped any quest whose .tres went missing, tell the player — otherwise that
	# progress vanishes silently. Consume-once (take_load_warnings clears them) so a HUD rebuild on a level change
	# doesn't re-toast old warnings. Amber = a load caveat.
	for msg in GameState.take_load_warnings():
		_push_toast(str(msg), Color(1.0, 0.7, 0.3))
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
	# This readout paints composed prompts carrying NAMES — including player-TYPED pet names pushed onto a
	# host's display_name by Claimable._apply_name ("Take Rex", "[E] Pet Rex"). Typed text must never be
	# looked up as a translation msgid, so the label opts out of Godot's automatic Control-text translation.
	_look_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
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
	_set_gameplay_hud_visible(not DialogueManager.is_engaged())

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

## Build the bottom-left gameplay HUD: a segmented red HP bar with the ammo readout just beneath it. (The
## weapon hotbar lives bottom-right, built separately in hotbar.gd.) Driven in _process.
func _build_hud() -> void:
	_hp_bar = Control.new()
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_bar.anchor_top = 1.0
	_hp_bar.anchor_bottom = 1.0
	_hp_bar.position = Vector2(HP_BAR_INSET.x, -HP_BAR_INSET.y)
	_hp_bar.z_index = 2
	add_child(_hp_bar)
	_build_stamina_bar()
	_hud_ammo = _make_hud_label(false)  # bottom-LEFT, repositioned just under the HP bar
	_hud_ammo.offset_top = -35.0
	_hud_ammo.offset_bottom = -4.0

func _build_stamina_bar() -> void:
	_stamina_bar = Control.new()
	_stamina_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stamina_bar.anchor_top = 1.0
	_stamina_bar.anchor_bottom = 1.0
	_stamina_bar.position = Vector2(HP_BAR_INSET.x, -HP_BAR_INSET.y + HP_SEG_SIZE.y + STAMINA_BAR_GAP)
	_stamina_bar.z_index = 2
	add_child(_stamina_bar)
	var bg := ColorRect.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.color = STAMINA_EMPTY
	bg.size = STAMINA_BAR_SIZE
	_stamina_bar.add_child(bg)
	_stamina_fill = ColorRect.new()
	_stamina_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stamina_fill.color = STAMINA_FILL
	_stamina_fill.size = STAMINA_BAR_SIZE
	bg.add_child(_stamina_fill)

## Show/hide gameplay readouts that should not sit over focused dialogue.
func _set_gameplay_hud_visible(vis: bool) -> void:
	if _hp_bar != null:
		_hp_bar.visible = vis
	if _stamina_bar != null:
		_stamina_bar.visible = vis
	if _hud_ammo != null:
		_hud_ammo.visible = vis
	if _hotbar != null:
		_hotbar.visible = vis

## HUD nodes hidden for the death cinematic; restored on the in-place revive (a full reload rebuilds a fresh UI).
var _death_hidden_hud: Array[CanvasItem] = []

## Hide the whole gameplay HUD for the death cinematic — but KEEP the post-process ColorRect. That rect is a
## child of THIS CanvasLayer and it renders the death grayscale / closing vignette / fade AND hosts the death
## card, so the old blunt `ui.visible = false` hid the entire cinematic along with the HUD (the bug that made
## death snap-cut with no fade). This hides every currently-visible direct child EXCEPT the ColorRect,
## remembering exactly which it hid so the revive shows back only those (placeholders already hidden stay hidden;
## the death card, added AFTER this runs, is untouched and renders over the fade).
func hide_hud_for_death() -> void:
	var keep := get_node_or_null(^"ColorRect")
	_death_hidden_hud.clear()
	for child in get_children():
		if child == keep:
			continue
		if child is CanvasItem and (child as CanvasItem).visible:
			(child as CanvasItem).visible = false
			_death_hidden_hud.append(child)

## Restore the HUD hidden by hide_hud_for_death() — the in-place revive (_respawn_at_checkpoint) calls this.
func restore_hud_after_death() -> void:
	for ci in _death_hidden_hud:
		if is_instance_valid(ci):
			ci.visible = true
	_death_hidden_hud.clear()

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

## (Re)build the HP bar's segments: one per ~1 max HP. Called when max HP changes (level-up / perk strength).
func _rebuild_hp_segments(count: int) -> void:
	for c in _hp_bar.get_children():
		c.queue_free()
	_hp_fills.clear()
	for i in count:
		var bg := ColorRect.new()
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.color = HP_SEG_EMPTY
		bg.position = Vector2(float(i) * (HP_SEG_SIZE.x + HP_SEG_GAP), 0.0)
		bg.size = HP_SEG_SIZE
		_hp_bar.add_child(bg)
		var fill := ColorRect.new()
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fill.color = HP_SEG_FILL
		fill.size = HP_SEG_SIZE
		bg.add_child(fill)
		_hp_fills.append(fill)
	_hp_seg_count = count

## Pure fill math for one HP segment: the 0..1 fraction segment `i` shows, given `hp` of `max_hp` split across
## `seg_count` segments (the last live one partially). Static so it's unit-testable on a bare instance.
static func hp_segment_fill(cur_hp: float, max_hp: float, seg_count: int, i: int) -> float:
	var m := maxf(max_hp, 0.0001)
	var per := m / float(maxi(seg_count, 1))
	return clampf((clampf(cur_hp, 0.0, m) - per * float(i)) / per, 0.0, 1.0)

## Drive the segmented HP bar from hp / max_hp each frame: each segment fills left-to-right (the last live one
## partially), and the live segments glow hotter with a segment or less of HP remaining.
func _update_hp_bar() -> void:
	var maxhp := maxf(player.max_hp, 1.0)
	var want := maxi(1, int(round(maxhp)))
	if want != _hp_seg_count:
		_rebuild_hp_segments(want)
	var per := maxhp / float(_hp_seg_count)  # HP represented by one segment
	var cur_hp := clampf(player.hp, 0.0, maxhp)
	var critical := cur_hp <= per + 0.001        # one segment or less left
	for i in _hp_fills.size():
		var f := hp_segment_fill(player.hp, maxhp, _hp_seg_count, i)
		var fill := _hp_fills[i]
		fill.size.x = HP_SEG_SIZE.x * f
		fill.visible = f > 0.001
		fill.color = HP_SEG_LOW if critical else HP_SEG_FILL

## Pure stamina-bar fill math, kept static so tests can cover it without building the HUD tree.
static func stamina_bar_fill(cur_stamina: float, max_stamina: float) -> float:
	if max_stamina <= 0.0001:
		return 1.0
	return clampf(cur_stamina / max_stamina, 0.0, 1.0)

func _update_stamina_bar() -> void:
	if _stamina_fill == null or not player.has_method(&"stamina_max"):
		return
	var maximum: float = float(player.call(&"stamina_max"))
	var current: float = float(player.get(&"stamina"))
	var f := stamina_bar_fill(current, maximum)
	_stamina_fill.size.x = STAMINA_BAR_SIZE.x * f
	_stamina_fill.visible = f > 0.001
	_stamina_fill.color = STAMINA_LOW if f <= 0.25 else STAMINA_FILL

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

## Show / hide the reticle — driven by dialogue start/end (a conversation hides it). Guarded for a freed
## crosshair. The parent HUD's own `visible` (cleared on death) still wins, so this never un-hides a dead HUD.
func set_crosshair_visible(vis: bool) -> void:
	if is_instance_valid(crosshair):
		crosshair.visible = vis

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
	if faction == null or is_zero_approx(delta):
		return
	_push_toast(PlayerText.reputation_changed(_faction_name(faction), delta > 0.0),
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
	_push_toast(PlayerText.alignment_changed(_faction_name(faction), kind_text), col)

## The faction's player-facing name for the rep/alignment toasts: the AUTHORED Faction.display_name, degrading
## to the capitalized id when a faction ships without one — the same authored-wins/capitalize-degrade shape as
## StatInfo.title, and never a blank. Static + pure so the display-name contract test pins it off-tree.
static func _faction_name(faction: Faction) -> String:
	return faction.display_name if not faction.display_name.is_empty() else String(faction.id).capitalize()

## Hide transient notifications and bottom-left gameplay readouts while a conversation is up (they'd float over
## the letterboxed cinematic); everything reappears — including any toast pushed mid-talk that hasn't expired —
## on finish.
## dialogue_finished also fires on the death-abort path, so the layer can't get stuck hidden.
func _on_dialogue_started_signal(_resource: DialogueResource) -> void:
	_on_dialogue_started()

func _on_dialogue_started() -> void:
	if _notices != null:
		_notices.visible = false
	set_crosshair_visible(false)  # talking isn't an aiming moment (folded here off the fragile .bind connection)
	_set_gameplay_hud_visible(false)

func _on_dialogue_finished() -> void:
	if _notices != null:
		_notices.visible = true
	set_crosshair_visible(true)
	_set_gameplay_hud_visible(true)
	_flush_dialogue_toasts()

## Public entry for one-off gameplay toasts (sneak result, limb cripples, ...). Routed through the same
## fading top-left stack + style as the reputation toasts so all notifications read consistently.
## Static toast: fire a HUD toast from code with no player/HUD ref (a TriggerVolume / CutsceneAction). Finds the
## live player and routes to its notify_toast -> push_toast. No-op if there's no player (e.g. the start menu).
static func toast(text: String, color := Color.WHITE) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	for p in tree.get_nodes_in_group(Groups.PLAYER):
		if p.has_method(&"notify_toast"):
			p.call(&"notify_toast", text, color)
			return

func push_toast(text: String, color: Color) -> void:
	_push_toast(text, color)

## Quest transitions often fire from a dialogue choice (e.g. a terminal turn-in). Dialogue hides notices, so queue
## those toasts until the conversation closes instead of starting their fade timer behind the letterbox.
func _push_quest_toast(text: String, color: Color) -> void:
	if DialogueManager.is_active():
		_dialogue_toast_texts.append(text)
		_dialogue_toast_colors.append(color)
		return
	_push_toast(text, color)

func _flush_dialogue_toasts() -> void:
	for i in _dialogue_toast_texts.size():
		_push_toast(_dialogue_toast_texts[i], _dialogue_toast_colors[i])
	_dialogue_toast_texts.clear()
	_dialogue_toast_colors.clear()

## Stack a fading, colour-coded line in the top-left (newest on top).
func _push_toast(text: String, color: Color) -> void:
	if _rep_toasts == null:
		return
	var label := Label.new()
	# Toasts are composed runtime strings that can carry a player-TYPED pet name (Claimable's befriend /
	# released toasts) — typed text must never be looked up as a translation msgid (atr opt-out).
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
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

# --- Quest feedback (tracker line + transition toasts) ------------------------------------------------------

## The HUD quest-tracker line for one objective — pure (no GameState), so it's unit-testable. e.g.
## "◈ Rescue the hostage — Reach the vault (2/5)". The count shows only for a multi-step objective.
static func quest_tracker_line(title: String, objective_desc: String, progress: int, required: int) -> String:
	return PlayerText.quest_tracker_line(title, objective_desc, progress, required)

## Refresh the tracker to the FIRST active quest's first incomplete, non-optional objective (or hide it when no
## quest is active). Cheap — runs only on a quest signal, not per frame.
func _refresh_quest_tracker() -> void:
	if _quest_tracker == null:
		return
	for qid in GameState.active_quest_ids():
		var quest: Quest = GameState.active_quest(qid)
		if quest == null:
			continue
		for obj in quest.objectives:
			if obj == null or obj.optional or GameState.is_objective_done(qid, obj.id):
				continue
			var desc: String = obj.description if obj.description != "" else String(obj.id)
			_quest_tracker.text = quest_tracker_line(quest.title, desc, GameState.objective_progress(qid, obj.id), obj.required_count)
			_quest_tracker.visible = true
			return
	_quest_tracker.text = ""
	_quest_tracker.visible = false

func _on_quest_started(quest: Quest) -> void:
	if quest != null:
		_push_quest_toast(PlayerText.new_quest(quest.title), Color(0.7, 0.9, 1.0))
	_refresh_quest_tracker()

## Toast only when an objective FULLY completes (not on every increment of a kill-N), then refresh the tracker.
func _on_quest_objective(quest: Quest, objective: QuestObjective) -> void:
	if quest != null and objective != null and GameState.is_objective_done(quest.id, objective.id):
		var desc: String = objective.description if objective.description != "" else String(objective.id)
		_push_quest_toast(PlayerText.objective_complete(desc), Color(0.6, 1.0, 0.7))
	_refresh_quest_tracker()

func _on_quest_completed(quest: Quest) -> void:
	if quest != null:
		_push_quest_toast(PlayerText.quest_complete(quest.title), Color(0.5, 1.0, 0.6))
	_refresh_quest_tracker()

func _on_quest_failed(quest: Quest) -> void:
	if quest != null:
		_push_quest_toast(PlayerText.quest_failed(quest.title), Color(0.9, 0.45, 0.45))
	_refresh_quest_tracker()

## The top-left zorkmid readout text — the whole money phrase (Zorkmids.MONEY_TEMPLATE owns the "zm" word).
func _money_text(total: float) -> String:
	return Zorkmids.money_text(total)

## Player.money changed (add_money): refresh the readout and float a colour-coded +N / -N up from it.
func _on_money_changed(total: float, delta: float) -> void:
	if _money_label != null:
		_money_label.text = _money_text(total)
	if is_zero_approx(delta):
		return
	var ind := Label.new()
	ind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ind.text = PlayerText.money_delta(delta)
	ind.add_theme_font_size_override(&"font_size", MONEY_DELTA_FONT_SIZE)
	ind.add_theme_color_override(&"font_color", MONEY_GAIN_COLOR if delta > 0.0 else MONEY_LOSS_COLOR)
	ind.add_theme_color_override(&"font_outline_color", Color.BLACK)
	ind.add_theme_constant_override(&"outline_size", 4)
	ind.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	ind.position = Vector2(8, 26)
	_notices.add_child(ind)  # under the notification layer, so dialogue hides the float with the toasts
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
	# Connect the floating +N / -N money indicator to the wallet. money_changed lives on EVERY Character now
	# (NPC wallets), so gate on the actual Player — this HUD must only ever narrate the player's money, and
	# a future refactor handing it an NPC must not silently pollute the readout.
	if p_player is Player and not player.is_connected(&"money_changed", _on_money_changed):
		player.connect(&"money_changed", _on_money_changed)
	# The Deus Ex hotbar (keys 1-0), auto-filled from the backpack. Its wiring is DEFERRED: setup() runs
	# from Player._enter_tree, but the backpack is built (and seeded / save-restored) during Player._ready —
	# by the deferred call it exists and is stocked, so the slots fill immediately.
	if _hotbar == null and p_player is Player:
		_hotbar = Hotbar.new()
		add_child(_hotbar)
		_hotbar.visible = not DialogueManager.is_engaged()
		_hotbar.setup.call_deferred(p_player as Player)

func _process(_delta: float) -> void:
	if is_instance_valid(player) and _hp_bar != null:
		_update_hp_bar()
	if is_instance_valid(player) and _stamina_bar != null:
		_update_stamina_bar()
	if is_instance_valid(ammo_count) and _hud_ammo != null:
		_hud_ammo.text = _ammo_text()
	# Poll the zorkmid readout from the wallet every frame (like HP), so it's correct from frame one even
	# though setup() runs before this HUD's _ready built the label. money_changed still drives the +N/-N
	# float. NO int() here — zorkmids are FRACTIONAL now, and a truncating poll would stomp the correct
	# signal-driven text every frame ("12.5" would never survive a frame).
	if _money_label != null and is_instance_valid(player):
		_money_label.text = _money_text(float(player.get(&"money")))

## Ammo readout for the equipped weapon: "clip / reserve" (rounds in the magazine / rounds left in the
## backpack). Blank for a caliber-less weapon (melee / rock / spray) — those carry no reserve and their
## clip count is a sentinel, so there's nothing meaningful to show.
func _ammo_text() -> String:
	var weapon: WeaponData = ammo_count.current_weapon
	if weapon == null or weapon.caliber == &"" or not is_instance_valid(player) or player.inventory == null:
		return ""
	return "%d / %d" % [ammo_count.current_ammo, player.inventory.ammo_count(weapon.caliber)]
