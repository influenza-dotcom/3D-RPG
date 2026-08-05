class_name UI
extends CanvasLayer

## HUD layer. Polls the player's HP and the Ammo clip each frame to refresh the
## labels, and owns the BloodSplatter overlay that Player.on_nearby_death drives.
## The is_instance_valid guards below matter: player/ammo can be freed during a
## death/scene reload while this layer briefly persists.
##
## DIEGETIC HUD WEIGHT (the Borderlands 2 feel): the corner "instrument panel" — HP/stamina bars, ammo,
## money, toasts, quest tracker, hotbar — rides ONE full-rect carrier (`_weighted`) whose position is a
## damped spring trailing camera turns (HudSway, knobs in GameSettings.hud "HUD weight", scaled 0..1 by
## the Options -> Accessibility "HUD Sway" slider). THE MOVED-vs-PINNED RULE: anything that ANNOTATES
## THE AIM POINT stays welded to the layer and never sways — the crosshair (already repositioned per
## frame by Player._update_crosshair; stacking a second offset would double-sway it), the stamina ring
## (it orbits the reticle), and the look-at name under it. PlayerHud's overlays (full-screen flashes,
## the directional damage/aim arcs, hitmarker, the centre-top prompt ladder, the top-centre enemy health
## bar) also stay pinned: the arcs point at world directions and a lagging bearing would lie, and the
## centre-top column is an outline-tight stack whose rows would collide under 8 px of spring drift plus
## the carrier's FOV lens-breath scale. Corner readouts carry mass; combat truth does not.

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
var _crosshair_art: TextureRect  ## OPTIONAL artist reticle (MenuStyle.hud.crosshair_texture): replaces the flat dot while UNSCOPED; null skin slot = never shown
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
## Non-directional HUD tints (knobs, not CBPalette — they mark a category, not a gain/loss direction).
var QUEST_TOAST_COLOR: Color = GameSettings.hud.quest_toast_color        ## new-quest announcement toast
var QUEST_TRACKER_COLOR: Color = GameSettings.hud.quest_tracker_color    ## top-right objective tracker line
var LOAD_WARNING_COLOR: Color = GameSettings.hud.load_warning_color      ## amber save-load caveat toast
var _rep_toasts: VBoxContainer
var _money_label: Label  ## persistent top-left zorkmid readout
## The LIVE floating +N/-N money delta: rapid deltas accumulate into this one label (re-stamped, rise+fade
## restarted) instead of stacking unreadable copies at the same spot; a flurry that nets to zero frees it.
var _money_delta_label: Label = null
var _money_delta_sum: float = 0.0   ## running signed total the live float shows
var _money_delta_tw: Tween = null   ## its rise+fade tween, killed + restarted on each accumulation
var _dialogue_toast_texts: Array[String] = []  ## quest transition toasts earned during dialogue; flushed when it closes
var _dialogue_toast_colors: Array[Color] = []
## Container for the TRANSIENT top-left notifications (the toast stack + the floating +N/-N money deltas).
## Hidden while a conversation is up so popups don't break the letterboxed cinematic; the persistent zorkmid
## readout stays (it's HUD, not a notification). Quest transition toasts are queued until the conversation closes
## so terminal turn-ins still visibly announce completion; generic one-off toasts keep their existing timing.
var _notices: Control
var _look_name: Label  ## centered name readout under the crosshair while aiming at a talkable (FNV-style)
var _quest_tracker: Label  ## top-right active-objective line, refreshed off the GameState quest signals (+ toasts)

## Bottom-corner gameplay HUD — bottom-LEFT: the HP+stamina bar cluster hugging the corner, ammo
## "clip / reserve" line just above it; bottom-RIGHT: the hotbar. Code-built so it's
## always visible + styled, independent of the scene's (hidden, placeholder) HP/AMMO labels.
## The stamina-ring / HUD-sway drop-ins, preloaded BY PATH + kept untyped so this file parses even
## before the editor registers the new class_names in its global cache (the SniperGlints idiom in
## player_hud.gd — "Could not find type X" cascade guard).
const STAMINA_RING_SCRIPT := preload("res://scripts/ui/stamina_ring.gd")
const HUD_SWAY_SCRIPT := preload("res://scripts/ui/hud_sway.gd")

## Full-rect carrier for every corner HUD element that has "weight" (see the header): its position IS
## the live sway offset, so one write a frame moves the whole instrument panel. Children keep their
## absolute canvas coords (the carrier sits at the origin, full-rect), so parenting into it is layout-free.
var _weighted: Control
var _sway = HUD_SWAY_SCRIPT.new()  ## the damped-spring state behind the panel sway (pure math, unit-tested)
var _sway_fov = HUD_SWAY_SCRIPT.new()  ## SECOND spring, scalar (.x only): the FOV "lens breath" scale delta — kept
								   ## separate so a dash punch breathing the lens never eats the offset spring's travel
var _sway_last_yaw: float = 0.0    ## previous frame's camera yaw — the sway target is the per-frame look RATE
var _sway_last_pitch: float = 0.0
var _sway_primed: bool = false     ## false until one yaw/pitch sample exists (else frame one reads a huge fake rate)

var _hp_bar: Control                    ## bottom-left segmented HP bar (red), rebuilt when max HP changes
var _hp_fills: Array[ColorRect] = []    ## per-segment fill rects (index = displayed segment, left-to-right)
var _hp_seg_count: int = 0              ## current DISPLAYED segment count (round(max_hp) capped by the width budget)
var _hp_seg_w: float = GameSettings.hud.hp_seg_size.x  ## current segment width; shrinks so the bar fits HP_BAR_MAX_WIDTH
var _stamina_bar: Control
var _stamina_bg: ColorRect      ## the stamina track — its WIDTH follows the HP bar's rendered width (see _update_hp_bar)
var _stamina_fill: ColorRect
## The radial stamina gauge around the crosshair (StaminaRing) — the SHIPPED default readout; the corner
## bar above is its accessibility fallback. Exactly ONE of the two is visible (_apply_stamina_mode,
## polled live off Settings.stamina_ring_enabled). Untyped: built from STAMINA_RING_SCRIPT (cache guard).
var _stamina_ring = null
## Mirror of the last _set_gameplay_hud_visible(vis): _apply_stamina_mode runs per frame (the Options
## toggle must apply live), so it needs the dialogue-hide state to compose with — without it, the
## per-frame mode poll would un-hide the stamina readout mid-conversation.
var _gameplay_hud_visible: bool = true
## The stamina bar's live width: EQUALS the HP bar's rendered width, restamped on every segment rebuild —
## the two left-rail bars must stay flush at both edges (a fixed track beside the budget-sized HP bar read
## as the stamina bar "sticking out" whenever max_hp was low). stamina_bar_size.y stays the authored HEIGHT
## knob; .x only seeds the first frame, before the HP bar's initial rebuild stamps the real shared width.
var _stamina_w: float = GameSettings.hud.stamina_bar_size.x
var _hud_ammo: Label
var _hotbar: Hotbar  ## bottom-right quick slots (keys 1-0), built in setup once the player is known
var HUD_FONT_SIZE: int = GameSettings.hud.hud_font_size
var AMMO_FONT_SIZE: int = GameSettings.hud.ammo_font_size    ## bottom-left clip/reserve readout — NOT the big centred message font
var AMMO_LOW_FRAC: float = GameSettings.hud.ammo_low_frac    ## clip fraction at/below which the ammo readout warns
var AMMO_LOW_COLOR: Color = GameSettings.hud.ammo_low_color  ## warning tint for a nearly-empty clip
## Segmented HP bar (bottom-left): one red segment per ~1 max HP until HP_BAR_MAX_WIDTH is hit — then segments
## shrink, and past HP_SEG_MIN_WIDTH consolidate (one drawn cell = >1 HP), so the bar never crowds the hotbar.
var HP_SEG_SIZE: Vector2 = GameSettings.hud.hp_seg_size      ## one FULL-SIZE HP segment, w x h
var HP_SEG_GAP: float = GameSettings.hud.hp_seg_gap          ## px between segments
var HP_BAR_INSET: Vector2 = GameSettings.hud.hp_bar_inset    ## bar origin: x from the left edge, y up from the bottom
var HP_SEG_EMPTY: Color = GameSettings.hud.hp_seg_empty      ## a drained segment (dark, translucent)
var HP_SEG_FILL: Color = GameSettings.hud.hp_seg_fill        ## live HP (bright red)
var HP_SEG_LOW: Color = GameSettings.hud.hp_seg_low          ## glows hotter with one segment of HP left
var HP_BAR_MAX_WIDTH: float = GameSettings.hud.hp_bar_max_width  ## total width budget of the whole bar at ANY max HP
var HP_SEG_MIN_WIDTH: float = GameSettings.hud.hp_seg_min_width  ## narrowest drawable segment before consolidation
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
	# OPTIONAL artist reticle art (HUD skin): a child TextureRect filling the crosshair rect, shown INSTEAD
	# of the shader-drawn flat dot while unscoped (the MenuSkin widget-art fallback rule — null slot = the
	# shipped code-drawn look). Scoping always swaps back to the inverting disc: that shader is FUNCTIONAL
	# (it samples the screen for contrast) and is never replaced by art. Built even when the slot is null so
	# a runtime set_hud_skin + set_scoped repaint can adopt art without a rebuild.
	_crosshair_art = TextureRect.new()
	_crosshair_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_crosshair_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_crosshair_art.stretch_mode = TextureRect.STRETCH_SCALE
	crosshair.add_child(_crosshair_art)
	_apply_crosshair_look(false)
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
	# HUD-weight carrier (see the header's moved-vs-pinned rule): every corner readout parents INTO this
	# full-rect container instead of the layer, and _update_hud_sway writes the spring offset onto its
	# position each frame — one write moves the whole instrument panel. Built BEFORE the corner elements
	# so they can parent straight in; full-rect at the origin so their absolute coords are unchanged.
	# NOTE for hide_hud_for_death: this is one direct child, so the death sweep hides/restores the whole
	# panel as a unit (per-element visibility inside it — dialogue-hidden _notices etc. — is preserved).
	_weighted = Control.new()
	_weighted.name = "WeightedHud"
	_weighted.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weighted.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_weighted)
	# The hotbar is created in setup(), which runs from Player._enter_tree — BEFORE this _ready — so it
	# was parented to the layer itself; move it onto the carrier now that the carrier exists.
	if _hotbar != null and _hotbar.get_parent() == self:
		remove_child(_hotbar)
		_weighted.add_child(_hotbar)
	# Transient-notification layer: everything popup-like in the top-left lives under this one container so
	# dialogue can hide the whole cluster at once (full-rect at the origin, so children keep their absolute
	# screen positions; mouse-ignore like everything else in the HUD). Rides the weight carrier — toasts
	# are corner furniture, not aim annotations.
	_notices = Control.new()
	_notices.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notices.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_weighted.add_child(_notices)
	if not DialogueManager.dialogue_started.is_connected(_on_dialogue_started_signal):
		DialogueManager.dialogue_started.connect(_on_dialogue_started_signal)
	if not DialogueManager.dialogue_finished.is_connected(_on_dialogue_finished):
		DialogueManager.dialogue_finished.connect(_on_dialogue_finished)
	# Reputation toasts in the top-left, driven by the Reputation autoload.
	_rep_toasts = VBoxContainer.new()
	_rep_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rep_toasts.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_rep_toasts.position = Vector2(8, 48)  # on the money readout's 8px rail, below the +N/-N delta's float band
	_notices.add_child(_rep_toasts)
	# Quest tracker: the current active objective, pinned to the FREE top-right corner (money/rep/toasts are
	# top-left, HP/ammo bottom). A FIXED quest_tracker_width column, right-aligned: short lines still hug the
	# right edge, long authored text word-wraps DOWNWARD over empty screen instead of marching left toward the
	# money band. No ellipsis trim — it would eat the "(2/5)" progress tail. Refreshed off the GameState quest
	# signals; hidden when no quest is active.
	_quest_tracker = Label.new()
	_quest_tracker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quest_tracker.anchor_left = 1.0
	_quest_tracker.anchor_right = 1.0
	_quest_tracker.offset_left = -8.0 - GameSettings.hud.quest_tracker_width
	_quest_tracker.offset_right = -8.0
	_quest_tracker.offset_top = 8.0
	_quest_tracker.autowrap_mode = TextServer.AUTOWRAP_WORD
	_quest_tracker.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_quest_tracker.add_theme_font_size_override(&"font_size", REP_TOAST_FONT_SIZE)
	_quest_tracker.add_theme_color_override(&"font_color", QUEST_TRACKER_COLOR)
	# Label chrome (outline colour/width) comes from the artist HUD skin (MenuStyle.hud) — stamped at
	# build time, so a runtime set_hud_skin needs a HUD rebuild (level reload) to repaint these labels.
	_quest_tracker.add_theme_color_override(&"font_outline_color", MenuStyle.hud.label_outline_color)
	_quest_tracker.add_theme_constant_override(&"outline_size", MenuStyle.hud.toast_outline_size)
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
		_push_toast(str(msg), LOAD_WARNING_COLOR)
	# Persistent zorkmid readout in the very top-left; refreshed + a floating +N/-N spawned on
	# Player.money_changed (wired in setup). Outlined like the toasts so it reads over any backdrop.
	# On the weight carrier (it's corner furniture) but NOT under _notices — dialogue hides notifications,
	# and this readout deliberately stays visible through a conversation.
	_money_label = Label.new()
	_money_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_money_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_money_label.position = Vector2(8, 6)
	_money_label.add_theme_font_size_override(&"font_size", MONEY_FONT_SIZE)
	_money_label.add_theme_color_override(&"font_color", MONEY_COLOR)
	_money_label.add_theme_color_override(&"font_outline_color", MenuStyle.hud.label_outline_color)
	_money_label.add_theme_constant_override(&"outline_size", MenuStyle.hud.toast_outline_size)
	_money_label.text = _money_text(0)
	_weighted.add_child(_money_label)
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
	_look_name.add_theme_font_size_override(&"font_size", GameSettings.hud.prompt_font_size)
	_look_name.add_theme_color_override(&"font_outline_color", MenuStyle.hud.label_outline_color)
	_look_name.add_theme_constant_override(&"outline_size", MenuStyle.hud.look_name_outline_size)
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

## Build the bottom-left gameplay HUD: a segmented red HP bar (stamina track under it) hugging the
## corner, with the ammo readout just above it. (The weapon hotbar lives bottom-right, built separately
## in hotbar.gd.) Driven in _process.
func _build_hud() -> void:
	_hp_bar = Control.new()
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_bar.anchor_top = 1.0
	_hp_bar.anchor_bottom = 1.0
	_hp_bar.position = Vector2(HP_BAR_INSET.x, -HP_BAR_INSET.y)
	_hp_bar.z_index = 2
	_weighted.add_child(_hp_bar)  # corner readout -> rides the HUD-weight carrier
	_build_stamina_bar()
	# The RADIAL stamina ring (the shipped default readout; the corner bar above is the accessibility
	# fallback — _apply_stamina_mode shows exactly one). A DIRECT child of the layer, NOT of _weighted:
	# it annotates the reticle, so it follows the crosshair's live rect each frame and must never lag.
	# z_index 1: above the full-screen flash/vignette overlays (z 0) so a hurt flash can't drown the
	# gauge, still under the crosshair (z 2); the combat arcs that share its centre are separated by
	# RADIUS (ring 23 px vs aim arcs 28+ / damage 120 — see stamina_ring.gd's annulus-budget note).
	_stamina_ring = STAMINA_RING_SCRIPT.new()
	_stamina_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stamina_ring.z_index = 1
	add_child(_stamina_ring)
	_hud_ammo = _make_hud_label(false)  # bottom-LEFT, restacked just ABOVE the HP bar
	# Ammo-size, not the big centred message font.
	_hud_ammo.add_theme_font_size_override(&"font_size", AMMO_FONT_SIZE)
	# ABOVE the HP segments, not below: the bar cluster hugs the corner (HP_BAR_INSET leaves only ~4 px
	# under the stamina track), and this line is BLANK whenever the weapon is holstered / caliber-less —
	# parked underneath, that empty band read as the bars "floating" over dead space. Every offset derives
	# from HP_BAR_INSET so the one inset knob moves the whole cluster; the 24 px band is the 18px font's
	# ~24 px line box, gapped off the segments by the same STAMINA_BAR_GAP the cluster stacks with.
	_hud_ammo.offset_left = HP_BAR_INSET.x
	_hud_ammo.offset_right = HP_BAR_INSET.x + 440.0
	_hud_ammo.offset_bottom = -(HP_BAR_INSET.y + STAMINA_BAR_GAP)
	_hud_ammo.offset_top = _hud_ammo.offset_bottom - 24.0

## The classic bottom-left stamina bar — kept as the ACCESSIBILITY fallback readout (Options ->
## Accessibility -> "Crosshair Stamina Ring" OFF); the ring is the shipped default. Always built (it's
## two rects) so the Options toggle can swap modes instantly with no rebuild; _apply_stamina_mode owns
## which of bar/ring is visible.
func _build_stamina_bar() -> void:
	_stamina_bar = Control.new()
	_stamina_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stamina_bar.anchor_top = 1.0
	_stamina_bar.anchor_bottom = 1.0
	_stamina_bar.position = Vector2(HP_BAR_INSET.x, -HP_BAR_INSET.y + HP_SEG_SIZE.y + STAMINA_BAR_GAP)
	_stamina_bar.z_index = 2
	_weighted.add_child(_stamina_bar)  # corner readout -> rides the HUD-weight carrier (the ring does NOT)
	var bg := ColorRect.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.color = STAMINA_EMPTY
	bg.size = STAMINA_BAR_SIZE
	_stamina_bar.add_child(bg)
	_stamina_bg = bg
	_stamina_fill = ColorRect.new()
	_stamina_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stamina_fill.color = STAMINA_FILL
	_stamina_fill.size = STAMINA_BAR_SIZE
	bg.add_child(_stamina_fill)

## Show/hide gameplay readouts that should not sit over focused dialogue. The stamina readout routes
## through _apply_stamina_mode (which composes this flag with the ring/bar mode choice) so dialogue
## hides whichever widget is active and the close restores only that one.
func _set_gameplay_hud_visible(vis: bool) -> void:
	_gameplay_hud_visible = vis
	if _hp_bar != null:
		_hp_bar.visible = vis
	if _hud_ammo != null:
		_hud_ammo.visible = vis
	if _hotbar != null:
		_hotbar.visible = vis
	_apply_stamina_mode()

## THE STAMINA MODE SWITCH: exactly one of ring/bar shows, polled live off Settings.stamina_ring_enabled
## (so the Options toggle applies the same frame, like loot_beacons/detection_meter). The RING ships as
## the default — stamina gates the twitch verbs (sprint/dash/jump), so its readout belongs at the aim
## point; the corner bar stays as the accessibility opt-in for players who want a stable peripheral
## readout or find motion at the crosshair distracting (rationale mirrored on Settings.stamina_ring_enabled).
## Composes with the dialogue-hide flag, and BAILS during the death cinematic: hide_hud_for_death has
## hidden these nodes and remembered which — a per-frame re-show here would resurrect them over the fade.
func _apply_stamina_mode() -> void:
	if not _death_hidden_hud.is_empty():
		return
	var ring_mode: bool = Settings.stamina_ring_enabled
	if _stamina_ring != null:
		_stamina_ring.visible = _gameplay_hud_visible and ring_mode
	if _stamina_bar != null:
		_stamina_bar.visible = _gameplay_hud_visible and not ring_mode

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
	# Corner-readout chrome from the artist HUD skin (build-time stamp; a runtime skin swap needs a rebuild).
	lbl.add_theme_color_override(&"font_color", MenuStyle.hud.corner_label_color)
	lbl.add_theme_color_override(&"font_outline_color", MenuStyle.hud.corner_label_outline_color)
	lbl.add_theme_constant_override(&"outline_size", MenuStyle.hud.corner_label_outline_size)
	lbl.z_index = 2
	# Corner readout -> the HUD-weight carrier (self only as a pre-_ready fallback, mirroring setup()).
	(_weighted if _weighted != null else self).add_child(lbl)
	return lbl

## (Re)build the HP bar's DISPLAYED segments at the current _hp_seg_w. Called when max HP changes (level-up /
## perk strength); the caller stamps _hp_seg_w first so the rebuilt bar always fits its width budget.
func _rebuild_hp_segments(count: int) -> void:
	for c in _hp_bar.get_children():
		c.queue_free()
	_hp_fills.clear()
	for i in count:
		var bg := ColorRect.new()
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.color = HP_SEG_EMPTY
		bg.position = Vector2(float(i) * (_hp_seg_w + HP_SEG_GAP), 0.0)
		bg.size = Vector2(_hp_seg_w, HP_SEG_SIZE.y)
		_hp_bar.add_child(bg)
		var fill := ColorRect.new()
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fill.color = HP_SEG_FILL
		fill.size = Vector2(_hp_seg_w, HP_SEG_SIZE.y)
		bg.add_child(fill)
		_hp_fills.append(fill)
	_hp_seg_count = count

## Pure fill math for one HP segment: the 0..1 fraction segment `i` shows, given `hp` of `max_hp` split across
## `seg_count` segments (the last live one partially). Static so it's unit-testable on a bare instance.
static func hp_segment_fill(cur_hp: float, max_hp: float, seg_count: int, i: int) -> float:
	var m := maxf(max_hp, 0.0001)
	var per := m / float(maxi(seg_count, 1))
	return clampf((clampf(cur_hp, 0.0, m) - per * float(i)) / per, 0.0, 1.0)

## How many segments the bar DRAWS for `max_hp` under a total width `budget`: one per HP until segments would
## dip below `min_w`, then the count caps and one drawn cell represents >1 HP. Static so it's unit-testable.
static func hp_display_seg_count(max_hp: float, budget: float, gap: float, min_w: float) -> int:
	var want := maxi(1, int(round(maxf(max_hp, 1.0))))
	var cap := maxi(1, int(floorf((budget + gap) / (min_w + gap))))
	return mini(want, cap)

## The per-segment width that lets `count` segments + their gaps span exactly `budget`, clamped to the authored
## full width (an under-budget bar keeps the default look) and a 1px floor. Static so it's unit-testable.
static func hp_display_seg_width(count: int, budget: float, gap: float, full_w: float) -> float:
	# FLOORED to a whole pixel: a fractional width ((budget - gaps)/count is integral only when the divisor
	# cooperates) makes each segment's float position rasterize independently on the low-res 792x444 canvas —
	# adjacent segments land a pixel apart in width/gap and the ~2.4x nearest upscale magnifies the bar into a
	# ragged comb (screenshot-QA class). Whole-pixel widths + the whole-pixel gap keep every edge aligned; the
	# bar renders up to count-1 px narrower than the budget, which no eye can see.
	return clampf(floorf((budget - gap * float(count - 1)) / float(maxi(count, 1))), 1.0, full_w)

## Drive the segmented HP bar from hp / max_hp each frame: each segment fills left-to-right (the last live one
## partially), and the live segments glow hotter with a segment or less of HP remaining.
func _update_hp_bar() -> void:
	var maxhp := maxf(player.max_hp, 1.0)
	var want := hp_display_seg_count(maxhp, HP_BAR_MAX_WIDTH, HP_SEG_GAP, HP_SEG_MIN_WIDTH)
	if want != _hp_seg_count:
		_hp_seg_w = hp_display_seg_width(want, HP_BAR_MAX_WIDTH, HP_SEG_GAP, HP_SEG_SIZE.x)
		_rebuild_hp_segments(want)
		# Keep the stamina track flush with the HP bar at BOTH edges: restamp the shared width whenever the
		# HP bar's rendered width changes (segment count is the only thing that moves it).
		_stamina_w = float(want) * _hp_seg_w + float(want - 1) * HP_SEG_GAP
		if _stamina_bg != null:
			_stamina_bg.size.x = _stamina_w
	var per := maxhp / float(_hp_seg_count)  # HP represented by one DISPLAYED segment (>1 HP once consolidated)
	var cur_hp := clampf(player.hp, 0.0, maxhp)
	var critical := cur_hp <= per + 0.001        # one displayed segment or less left
	for i in _hp_fills.size():
		var f := hp_segment_fill(player.hp, maxhp, _hp_seg_count, i)
		var fill := _hp_fills[i]
		fill.size.x = _hp_seg_w * f
		fill.visible = f > 0.001
		fill.color = HP_SEG_LOW if critical else HP_SEG_FILL

## Pure stamina-bar fill math, kept static so tests can cover it without building the HUD tree.
static func stamina_bar_fill(cur_stamina: float, max_stamina: float) -> float:
	if max_stamina <= 0.0001:
		return 1.0
	return clampf(cur_stamina / max_stamina, 0.0, 1.0)

## The player's live stamina fraction — the ONE source both readout modes draw from (a hostless /
## stamina-less Character degrades to a full pool, which the ring idle-fades to near-invisible).
func _stamina_frac() -> float:
	if not is_instance_valid(player) or not player.has_method(&"stamina_max"):
		return 1.0
	return stamina_bar_fill(float(player.get(&"stamina")), float(player.call(&"stamina_max")))

## Per-frame stamina drive: apply the ring/bar mode, then feed only the ACTIVE widget. The ring's
## centre is re-stamped from the CROSSHAIR'S LIVE RECT every frame — never from the viewport centre —
## because Player._update_crosshair repositions the reticle each frame (today to screen centre; the
## moment that policy sways, a viewport-anchored ring would visibly detach from the reticle it annotates).
func _update_stamina_readout() -> void:
	_apply_stamina_mode()
	if _stamina_ring != null and Settings.stamina_ring_enabled:
		if crosshair != null:
			_stamina_ring.centre = crosshair.position + crosshair.size * 0.5
		_stamina_ring.fill = _stamina_frac()
	elif _stamina_bar != null:
		_update_stamina_bar()

func _update_stamina_bar() -> void:
	if _stamina_fill == null or not player.has_method(&"stamina_max"):
		return
	var f := _stamina_frac()
	_stamina_fill.size.x = _stamina_w * f
	_stamina_fill.visible = f > 0.001
	# Same CONTINUOUS blue->yellow blend as the crosshair ring (StaminaRing.ring_color, user call) — the
	# colour IS the level in both modes, no threshold snap. One blend function drives both readouts, so
	# the two stamina dialects can never drift apart again.
	_stamina_fill.color = STAMINA_RING_SCRIPT.ring_color(f, STAMINA_FILL, STAMINA_LOW)

## Impact kick — the DISCRETE channel into the HUD-weight spring (see HudSway's header for the two-channel
## model). Any camera-impacting event whose motion is POSITIONAL (invisible to the rotational basis
## measurement below) calls this with an authored px/s kick; today that's the landing dip via hud_land(),
## and a future thump (a heavy door, a vehicle impact) just calls it too. Cap-then-accessibility-scale
## lives in HudSway.kick_scaled so the order is pinned by tests; at sway scale 0 the kick silences.
func hud_kick(kick: Vector2) -> void:
	_sway.impulse(HUD_SWAY_SCRIPT.kick_scaled(kick, GameSettings.hud.hud_kick_max, Settings.hud_sway_scale))

## Landing touchdown -> the panel dips with the camera and settles back up. `intensity` is player.gd's
## dampened landing impact [0..1] (fall-speed-normalized, crouch-softened) — the SAME signal the camera
## dip (CameraEffects.land) and landing shake read, so all three tell one story at one strength.
func hud_land(intensity: float) -> void:
	hud_kick(HUD_SWAY_SCRIPT.land_kick(intensity, GameSettings.hud.hud_land_kick))

## Per-frame diegetic HUD weight (see the header's moved-vs-pinned rule): measure the camera's look
## rates, spring the _weighted carrier toward the lag target, write the offset. Knobs live in
## GameSettings.hud ("HUD weight") and are read LIVE so inspector tuning shows immediately; the 0..1
## Settings.hud_sway_scale (Options -> Accessibility -> "HUD Sway") multiplies the TARGET, so motion
## comfort scales amplitude without changing the spring's character. At scale 0 (or no camera) the
## target is ZERO and the spring still steps — the panel eases home instead of freezing mid-offset.
##
## COVERAGE NOTE (why there's no per-event shake wiring): the basis read below is GLOBAL and the camera
## sits under the ScreenShake node (scenes/player/camera_rig.tscn), so EVERY rotational camera event —
## mouse look, weapon-fire shake, explosions, the pinball ram, landing's own shake pulse — already
## drives this spring; heavy trauma reads as the panel rattling against its mount at the hud_sway_max
## cap. POSITIONAL camera motion is deliberately split: the landing dip arrives as a hud_land() kick
## (a rotation-only measurement can't see it), while walk-bob and the stair step-glide are deliberately
## NOT coupled — bob would keep the panel permanently busy duplicating the view's own bob (and stops
## with it when view_bob_enabled is off), and step_smooth exists precisely to HIDE the riser snap the
## panel would otherwise re-surface.
func _update_hud_sway(delta: float) -> void:
	if _weighted == null:
		return
	var sway_scale := clampf(float(Settings.hud_sway_scale), 0.0, 1.0)
	var target := Vector2.ZERO
	var fov_target := 0.0
	# The camera lives on the Player subclass (camera_effects); this HUD's `player` is typed Character,
	# so the read is duck-typed .get() with a null degrade (the duck-typed-property-reads house rule).
	var cam: Node3D = null
	if is_instance_valid(player):
		cam = player.get(&"camera_effects") as Node3D
	if cam != null and is_instance_valid(cam) and cam.is_inside_tree() and sway_scale > 0.0 and delta > 0.0:
		var fwd: Vector3 = -cam.global_transform.basis.z
		var yaw := atan2(-fwd.x, -fwd.z)
		var pitch := asin(clampf(fwd.y, -1.0, 1.0))
		var look := Vector2.ZERO
		if _sway_primed:
			# wrapf on the yaw delta: the +-PI seam would otherwise read a full-circle fake flick.
			var yaw_rate := wrapf(yaw - _sway_last_yaw, -PI, PI) / delta
			var pitch_rate := (pitch - _sway_last_pitch) / delta
			look = HUD_SWAY_SCRIPT.look_target(yaw_rate, pitch_rate,
					GameSettings.hud.hud_sway_gain, GameSettings.hud.hud_sway_max)
		_sway_last_yaw = yaw
		_sway_last_pitch = pitch
		_sway_primed = true
		# BODY-motion lean: strafe velocity (along the camera's right axis) leans the panel against the
		# move; vertical velocity floats it on a fall / presses it on a launch — so a jump reads
		# float-then-thud with the land kick. Summed with the look target and clamped as ONE promise:
		# hud_sway_max caps the total, so leaning into a strafe never buys a flick extra travel.
		var lateral: float = player.velocity.dot(cam.global_transform.basis.x)
		var lean: Vector2 = HUD_SWAY_SCRIPT.velocity_target(lateral, player.velocity.y, GameSettings.hud.hud_vel_gain)
		target = (look + lean).limit_length(GameSettings.hud.hud_sway_max) * sway_scale
		# Lens breath: dynamic-FOV kicks (fall/rise, run, sprint, dash punch) breathe the lens, and the
		# panel — being "in the world" — shrinks toward centre as it widens (HudSway.fov_scale_target).
		# GATED OUT while ADS-scoped or dialogue-zoomed: those own `fov` wholesale (a scope drops it to
		# ~40), and a level-coupling would park the panel shrunk/grown for the whole hold. Duck-typed
		# reads with `== true` / explicit null checks — never bool()/float() on a Variant (no such ctor).
		var cam3d := cam as Camera3D
		var rest_v: Variant = cam.get(&"base_fov")
		var dlg_v: Variant = cam.get(&"dialogue_fov")
		var scoped: bool = cam.get(&"_scope_fov_active") == true
		var in_dialogue_zoom: bool = dlg_v != null and (dlg_v as float) > 0.0
		if cam3d != null and rest_v != null and not scoped and not in_dialogue_zoom:
			fov_target = HUD_SWAY_SCRIPT.fov_scale_target(cam3d.fov, rest_v as float,
					GameSettings.hud.hud_fov_scale_gain, GameSettings.hud.hud_fov_scale_max) * sway_scale
	else:
		_sway_primed = false  # re-prime on the next valid sample (a respawn/teleport won't fake a flick)
	_weighted.position = _sway.step(target, GameSettings.hud.hud_sway_stiffness, GameSettings.hud.hud_sway_damping, delta)
	# AIM CLUSTER sway (user call): the crosshair rides the SAME spring at a whisper of the amplitude
	# (hud_sway_aim_scale), so reticle and panel move as one mass — and the stamina ring re-stamps its
	# centre HERE, after the crosshair write, because _update_stamina_readout ran earlier this frame and
	# a frame-stale centre would detach the ring from the reticle it annotates (the ring's own contract).
	# _crosshair_base is the unswayed centre from set_crosshair_screen_pos; look-name stays pinned.
	if crosshair != null:
		crosshair.position = _crosshair_base - crosshair.size * 0.5 + _sway.offset * GameSettings.hud.hud_sway_aim_scale
		if _stamina_ring != null:
			_stamina_ring.centre = crosshair.position + crosshair.size * 0.5
	# The scalar lens-breath spring shares the offset spring's stiffness/damping so the panel is ONE mass
	# with one motion character, not two objects. Pivot at the rect's centre: scale must breathe the
	# corners toward/away from the screen middle, exactly as a widening lens moves the world.
	var breath: float = _sway_fov.step(Vector2(fov_target, 0.0),
			GameSettings.hud.hud_sway_stiffness, GameSettings.hud.hud_sway_damping, delta).x
	_weighted.pivot_offset = _weighted.size * 0.5
	_weighted.scale = Vector2.ONE * (1.0 + breath)

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
	_apply_crosshair_look(scoped)
	# Only pay for the full-screen back-buffer copy while the inverting disc is actually up.
	if _crosshair_bbc:
		_crosshair_bbc.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT if scoped else BackBufferCopy.COPY_MODE_DISABLED

## Resolve what the reticle rect shows: scoped -> the inverting disc shader (always — it's functional);
## unscoped -> the artist texture from the HUD skin when authored, else the shader-drawn flat dot.
## Reads MenuStyle.hud at each scope transition, so a runtime skin swap adopts new art on the next
## scope in/out without a HUD rebuild.
func _apply_crosshair_look(scoped: bool) -> void:
	if crosshair == null:
		return
	var art: Texture2D = MenuStyle.hud.crosshair_texture
	var use_art := art != null and not scoped
	if _crosshair_art != null:
		_crosshair_art.texture = art
		_crosshair_art.visible = use_art
	# With art up, the ColorRect must paint NOTHING: material off and fully transparent (a bare ColorRect
	# with no material still fills its rect with `color`).
	crosshair.material = null if use_art else (_scoped_reticle_mat if scoped else _flat_reticle_mat)
	crosshair.color = Color(1, 1, 1, 0) if use_art else Color.WHITE

## Pin the reticle to an absolute screen position (its centre on `p`) — the TRUE aim point, projected by
## Player._update_crosshair from the swayed shot direction, so the crosshair never lies about where a shot
## will land. Null-guarded for calls before _ready.
## The UNSWAYED crosshair centre (what the player's aim actually points at). The rendered reticle sits at
## this plus the subtle aim-cluster share of the sway offset — see _update_hud_sway.
var _crosshair_base: Vector2 = Vector2.ZERO

func set_crosshair_screen_pos(p: Vector2) -> void:
	_crosshair_base = p
	if crosshair:
		# Write with the CURRENT aim-sway offset so a physics-frame reposition can't strip the sway for a
		# frame (the sway update refreshes it each process frame with the freshly-stepped spring).
		crosshair.position = p - crosshair.size * 0.5 + _sway.offset * GameSettings.hud.hud_sway_aim_scale

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
	# The ALIGNMENT_*_WORD consts are BOTH the painted word and alignment_changed's template-selection key —
	# a local literal drifting from them would silently fall back to the Neutral template.
	var kind_text := PlayerText.ALIGNMENT_NEUTRAL_WORD
	var col := REP_NEUTRAL_COLOR
	match new_kind:
		Disposition.Kind.HOSTILE:
			kind_text = PlayerText.ALIGNMENT_HOSTILE_WORD
			col = CBPalette.loss()
		Disposition.Kind.FRIENDLY:
			kind_text = PlayerText.ALIGNMENT_FRIENDLY_WORD
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
	label.add_theme_color_override(&"font_outline_color", MenuStyle.hud.label_outline_color)
	label.add_theme_constant_override(&"outline_size", MenuStyle.hud.toast_outline_size)
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
		_push_quest_toast(PlayerText.new_quest(quest.title), QUEST_TOAST_COLOR)
	_refresh_quest_tracker()

## Toast only when an objective FULLY completes (not on every increment of a kill-N), then refresh the tracker.
func _on_quest_objective(quest: Quest, objective: QuestObjective) -> void:
	if quest != null and objective != null and GameState.is_objective_done(quest.id, objective.id):
		var desc: String = objective.description if objective.description != "" else String(objective.id)
		_push_quest_toast(PlayerText.objective_complete(desc), CBPalette.gain())
	_refresh_quest_tracker()

func _on_quest_completed(quest: Quest) -> void:
	if quest != null:
		_push_quest_toast(PlayerText.quest_complete(quest.title), CBPalette.gain())
	_refresh_quest_tracker()

func _on_quest_failed(quest: Quest) -> void:
	if quest != null:
		_push_quest_toast(PlayerText.quest_failed(quest.title), CBPalette.loss())
	_refresh_quest_tracker()

## The top-left zorkmid readout text — the whole money phrase (Zorkmids.MONEY_TEMPLATE owns the "zm" word).
func _money_text(total: float) -> String:
	return Zorkmids.money_text(total)

## Player.money changed (add_money): refresh the readout and float a colour-coded +N / -N up from it.
## Rapid deltas (a coin-pile vacuum, a multi-item sale) ACCUMULATE into the one live float — re-stamped and its
## rise+fade restarted — instead of stacking unreadable copies at the same spot; a flurry that nets to zero
## frees the float outright. The tween's queue_free + the validity guard naturally reset the cycle — the guard
## must also reject a label whose fade already queue_free'd THIS frame (still "valid" until end-of-frame), else
## a same-frame delta re-stamps a dying node and that float never renders.
func _on_money_changed(total: float, delta: float) -> void:
	if _money_label != null:
		_money_label.text = _money_text(total)
	if is_zero_approx(delta):
		return
	if is_instance_valid(_money_delta_label) and not _money_delta_label.is_queued_for_deletion():
		_money_delta_sum += delta
		if is_zero_approx(_money_delta_sum):
			if _money_delta_tw != null:
				_money_delta_tw.kill()
			_money_delta_label.queue_free()
			_money_delta_label = null
			_money_delta_tw = null
			return
		_money_delta_label.position = Vector2(8, 26)
		_money_delta_label.modulate.a = 1.0
		_money_delta_label.text = PlayerText.money_delta(_money_delta_sum)
		_money_delta_label.add_theme_color_override(&"font_color", MONEY_GAIN_COLOR if _money_delta_sum > 0.0 else MONEY_LOSS_COLOR)
		if _money_delta_tw != null:
			_money_delta_tw.kill()
		_money_delta_tw = _money_delta_float(_money_delta_label)
		return
	_money_delta_sum = delta
	var ind := Label.new()
	ind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ind.text = PlayerText.money_delta(delta)
	ind.add_theme_font_size_override(&"font_size", MONEY_DELTA_FONT_SIZE)
	ind.add_theme_color_override(&"font_color", MONEY_GAIN_COLOR if delta > 0.0 else MONEY_LOSS_COLOR)
	ind.add_theme_color_override(&"font_outline_color", MenuStyle.hud.label_outline_color)
	ind.add_theme_constant_override(&"outline_size", MenuStyle.hud.toast_outline_size)
	ind.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	ind.position = Vector2(8, 26)
	_notices.add_child(ind)  # under the notification layer, so dialogue hides the float with the toasts
	_money_delta_label = ind
	_money_delta_tw = _money_delta_float(ind)

## The +N/-N float's rise+fade, shared by the fresh-label and re-stamp paths so both cycles look identical.
func _money_delta_float(ind: Label) -> Tween:
	var tw := ind.create_tween()
	tw.tween_property(ind, "position:y", ind.position.y - MONEY_DELTA_RISE, MONEY_DELTA_TIME).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(ind, "modulate:a", 0.0, MONEY_DELTA_TIME)
	tw.tween_callback(ind.queue_free)
	return tw

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
		# setup() runs from Player._enter_tree, BEFORE this layer's _ready builds the HUD-weight carrier —
		# parent to the carrier when it already exists (a re-setup), else to the layer; _ready reparents.
		(_weighted if _weighted != null else self).add_child(_hotbar)
		_hotbar.visible = not DialogueManager.is_engaged()
		_hotbar.setup.call_deferred(p_player as Player)

func _process(delta: float) -> void:
	if is_instance_valid(player) and _hp_bar != null:
		_update_hp_bar()
	if is_instance_valid(player):
		_update_stamina_readout()
	_update_hud_sway(delta)
	if is_instance_valid(ammo_count) and _hud_ammo != null:
		_hud_ammo.text = _ammo_text()
		# Low-clip warning (parity with the HP/stamina bars). Caliber-less weapons (blank readout) never warn.
		var w: WeaponData = ammo_count.current_weapon
		var low := w != null and w.caliber != &"" and w.max_ammo > 0 and float(ammo_count.current_ammo) <= ceilf(float(w.max_ammo) * AMMO_LOW_FRAC)
		# Resting tint comes from the HUD skin LIVE (per-frame read, one field — a skin swap recolours it
		# without a rebuild); the low-clip warning tint stays a GameSettings.hud tuning knob.
		_hud_ammo.add_theme_color_override(&"font_color", AMMO_LOW_COLOR if low else MenuStyle.hud.corner_label_color)
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
