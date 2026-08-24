class_name UI
extends CanvasLayer

## HUD layer. Polls the player's HP and the Ammo clip each frame to refresh the
## labels, and owns the BloodSplatter overlay that Player.on_nearby_death drives.
## The is_instance_valid guards below matter: player/ammo can be freed during a
## death/scene reload while this layer briefly persists.
##
## DIEGETIC HUD WEIGHT (the Borderlands 2 feel): the corner "instrument panel" — HP/stamina bars, ammo,
## money, toasts, quest tracker, minimap, clock, hotbar — rides ONE full-rect carrier (`_weighted`) whose position is a
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

var crosshair: ColorRect  ## circle reticle, re-pinned each frame by Player._update_crosshair (to SCREEN CENTRE — the swaying laser dot is what carries aim truth); shown/hidden ONLY by _apply_crosshair_visibility
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

## CURVED HUD GLASS (resources/shaders/hud_curve.gdshader): the corner instrument panel renders into
## `_curve_viewport` and is composited back through `_curve_rect`'s barrel warp, so the panel bows away at
## its edges like the inside of a curved screen. ONLY the `_weighted` carrier goes through it — the
## crosshair, the stamina ring, the combat arcs and every screen-projected annotation stay direct children
## of this layer and dead flat. That split is the header's moved-vs-pinned rule reused verbatim, and it is
## the right one for free: a node that may not MOVE may not be WARPED either, for the same reason.
##
## ⭐OFF IS THE OLD TREE, NOT AN IDENTITY PASS. At strength 0 the viewport is torn down and `_weighted` goes
## back to being a plain direct child, so a player who turns this off pays for nothing and gets
## pixel-identical rendering (the hud_ghost_scale promise, same reason). That is why the parenting decision
## lives in _apply_hud_curve, polled every frame, rather than being frozen in _ready: the Options row is applied
## live like every other HUD dial.
##
## ⭐A SubViewport IS NOT A CanvasItem, so hide_hud_for_death's direct-child sweep skips it and hides
## `_curve_rect` instead — the panel still vanishes for the death cinematic as ONE unit, exactly as the bare
## carrier used to. The sweep's `is CanvasItem` filter is what makes that work; it is load-bearing here too.
##
## ⭐THE PANEL GOES DEAF INSIDE IT. A nested SubViewport receives input only from a SubViewportContainer,
## and this composite is hand-built, so nothing forwards — the carrier's children stop hearing the keyboard
## the moment the curve stands up. `_unhandled_input` below is the forwarder that fixes it; read it before
## putting anything on the carrier that listens for input rather than polling `Input`.
##
## ⭐THE GHOST STILL SEES THE PANEL. HudGhost captures this layer's canvas, and the carrier's children are on
## the VIEWPORT's canvas once the curve is up — but `_curve_rect` is on this one, so the accumulator picks
## the panel up through its composite and the phosphor tail is of the CURVED panel. Nothing to wire.
const HUD_CURVE_SHADER := preload("res://resources/shaders/hud_curve.gdshader")
var _curve_viewport: SubViewport = null
var _curve_rect: ColorRect = null
var _curve_mat: ShaderMaterial = null

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
var _owed_label: Label   ## the OWED row BESIDE it — shown ONLY while GameState.account is negative (see _stamp_owed_row)
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
var _quest_tracker: Label  ## top-right active-objective line, refreshed off the QuestTracker quest signals (+ toasts)

## Bottom-corner gameplay HUD — bottom-LEFT: the HP+stamina bar cluster hugging the corner, ammo
## "clip / reserve" line just above it; bottom-RIGHT: the hotbar. Code-built so it's
## always visible + styled, independent of the scene's (hidden, placeholder) HP/AMMO labels.
## The stamina-ring / HUD-sway drop-ins, preloaded BY PATH + kept untyped so this file parses even
## before the editor registers the new class_names in its global cache (the SniperGlints idiom in
## player_hud.gd — "Could not find type X" cascade guard).
const STAMINA_RING_SCRIPT := preload("res://scripts/ui/stamina_ring.gd")
const HUD_SWAY_SCRIPT := preload("res://scripts/ui/hud_sway.gd")
const HUD_CLOCK_SCRIPT := preload("res://scripts/ui/hud_clock.gd")
const HUD_GHOST_SCRIPT := preload("res://scripts/ui/hud_ghost.gd")
const WORLD_GHOST_SCRIPT := preload("res://scripts/effects/world_ghost.gd")
## THE MINIMAP IS AN AUTHORED SCENE, not a script (the "menus are scenes" rule, applied to a HUD widget): the
## artist owns its box, its draw order and its two art slots by dragging in the 2D editor, and this file only
## chooses which carrier it rides and then MEASURES the authored box back (see minimap_box) so the clock and the
## objective tracker under it reflow.
##
## A plain String, load()ed at RUNTIME rather than preloaded. A class-scope preload of a SCENE reaches its whole
## script graph at parse time, and this file is `class_name UI` — the day anything under that scene type-refs UI
## back, a preload here is a parse-time "Could not resolve member: Cyclic reference", which is a DIFFERENT and
## much louder failure than the "Could not find type X" cache cascade the by-path preloads above guard against.
## It is safe today (minimap.gd's graph never names UI); a String const cannot go wrong later.
const MINIMAP_SCENE := "res://scenes/ui/hud_minimap.tscn"

## Full-rect carrier for every corner HUD element that has "weight" (see the header): its position IS
## the live sway offset, so one write a frame moves the whole instrument panel. Children keep their
## absolute canvas coords (the carrier sits at the origin, full-rect), so parenting into it is layout-free.
var _weighted: Control
## The top-right procedural floorplan (scripts/ui/minimap.gd). Untyped and preloaded BY PATH like the other
## drop-ins here, so this file parses before the editor registers the new class_name. MAY BE NULL: several
## suites build a bare UI.new() without _ready and call the visibility methods directly, so every touch of
## it below is null-guarded — that guard is load-bearing, not defensive habit.
var _minimap = null
## ROW 2 of the top-right stack: the time-of-day readout (scripts/ui/hud_clock.gd). Untyped and preloaded
## BY PATH for the same class_name-cache reason as _minimap, and null-guarded everywhere for the same
## reason too — several suites build a bare UI.new() with no _ready and call the visibility methods.
var _clock = null
var _sway = HUD_SWAY_SCRIPT.new()  ## the damped-spring state behind the panel sway (pure math, unit-tested)
var _sway_fov = HUD_SWAY_SCRIPT.new()  ## SECOND spring, scalar (.x only): the FOV "lens breath" scale delta — kept
								   ## separate so a dash punch breathing the lens never eats the offset spring's travel
var _sway_last_yaw: float = 0.0    ## previous frame's camera yaw — the sway target is the per-frame look RATE
var _sway_last_pitch: float = 0.0
var _sway_primed: bool = false     ## false until one yaw/pitch sample exists (else frame one reads a huge fake rate)
## Last measured camera look rate (rad/s, x = yaw, y = pitch) — the sway spring computes it and the ghost
## reuses THAT SAME sample rather than measuring the basis a second time: two independent measurements of
## one camera drift apart across a frame boundary, and the panel’s mass and the image’s latency would
## then narrate slightly different turns. Zero whenever there is no valid camera.
var _look_rate: Vector2 = Vector2.ZERO
## CRT phosphor persistence behind the whole HUD (scripts/ui/hud_ghost.gd). Untyped + preloaded BY PATH
## like the other drop-ins here, and MAY BE NULL: it builds only when this layer is actually in a tree
## with a viewport, so the bare UI.new() suites keep working untouched.
var _ghost = null
## The same persistence extended to the PICTURE (scripts/effects/world_ghost.gd) — a separate component and a
## separate player dial, because it is a different mechanism (a temporal average of the finished frame, not a
## second view of this canvas) and a different comfort decision. Same null-guard contract as _ghost.
var _world_ghost = null

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
var MONEY_DEBT_COLOR: Color = GameSettings.hud.money_debt_color    ## readout red while the wallet is NEGATIVE (in debt)
var MONEY_DELTA_RISE: float = GameSettings.hud.money_delta_rise    ## pixels the +N/-N floats up as it fades
var MONEY_DELTA_TIME: float = GameSettings.hud.money_delta_time    ## seconds for that float + fade
## THE TOP-LEFT MONEY RAIL'S VERTICAL PADDING — the first row's inset from the top edge AND the gap between every
## row below it, so the whole rail derives from this ONE number instead of three hand-typed y literals that can
## drift into each other. Three rows, top to bottom:
##   row 1  MONEY_ROW_PAD                the persistent zorkmid readout, with the OWED row BESIDE it (one HBox)
##   row 2  _money_delta_row_y()         the transient +N/-N float, which RISES MONEY_DELTA_RISE px out of it
##   row 3  that + MONEY_DELTA_FONT_SIZE + pad   the rep/quest toast stack, clear of the float band's bottom edge
## The OWED row used to be hand-placed at `6 + MONEY_FONT_SIZE + 2` (y≈24) — INSIDE row 2's band, and painted in
## money_debt_color, which ships as the SAME Color as money_loss_color: every -N spend float drew straight over
## it in an identical red. It's HUD layout, not a gameplay number, so it stays a const here rather than a
## HudSettings knob — the FONT SIZES the rows derive from are the designer-facing half.
const MONEY_ROW_PAD := 6.0

func _ready() -> void:
	# The circle reticle, re-pinned each frame by Player._update_crosshair via set_crosshair_screen_pos —
	# to SCREEN CENTRE, a FIXED reticle (Deus Ex): it deliberately does NOT track the shot, the swaying
	# laser dot does. (This said "the swayed aim point" for a long while; it never did.) It is not
	# permanent either — see the suppression latches. Unscoped it wears a cheap flat-dot
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
	# It is added to the LAYER here even when the HUD curve is on: _apply_hud_curve owns the reparent into
	# the curve viewport, so there is exactly one place that decides where the carrier lives.
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
	# Row 3 of the money rail (see MONEY_ROW_PAD): same 8px left rail as the readout, one pad below the BOTTOM
	# edge of the +N/-N delta's float band — derived, so a HudSettings font bump slides it instead of colliding.
	_rep_toasts.position = Vector2(8, _money_delta_row_y() + float(MONEY_DELTA_FONT_SIZE) + MONEY_ROW_PAD)
	_notices.add_child(_rep_toasts)
	# TOP-RIGHT STACK, ROW 1: the procedural minimap — a vector floorplan of the floor the player is standing
	# on, drawn from the level's baked navmesh (+ its static colliders). Built BEFORE the quest tracker below
	# because that tracker's offset_top is DERIVED from this box's footprint (quest_tracker_top) instead of
	# the literal 8.0 it used to carry: the corner is shared now, and one of the two has to own the reflow.
	# THE BOX IS AUTHORED, not computed. anchors, offsets, z_index (1: above the full-screen hurt/kill/dash
	# flashes PlayerHud adds to this layer at z 0, still under the crosshair at z 2 — the stamina ring's
	# reasoning), clip_contents and texture_filter all live in scenes/ui/hud_minimap.tscn now, alongside the
	# %MapUnder / %MapOver art slots. Nothing here writes a single one of them back.
	var packed := load(MINIMAP_SCENE) as PackedScene
	# A null instance is a legitimate degrade, not a crash: a transient reimport can hand back nothing, and
	# every touch of _minimap below is already null-guarded for the bare-UI.new() suites.
	_minimap = packed.instantiate() if packed != null else null
	if _minimap != null:
		_minimap.name = "Minimap"
		# The one thing a .tscn cannot express is WHICH CARRIER it rides, so that branch stays here: the two arms
		# differ in anti-shimmer and in hide_hud_for_death semantics (see HudSettings.minimap_rides_hud_weight).
		if GameSettings.hud.minimap_rides_hud_weight:
			_weighted.add_child(_minimap)  # corner readout -> rides the HUD-weight carrier (the header's rule)
		else:
			add_child(_minimap)  # pinned to the layer; still swept by hide_hud_for_death's direct-child loop
	# TOP-RIGHT STACK, ROW 2: the time-of-day clock, the map's caption. It answers the one question the
	# day/night cycle's lighting cannot — the moon keeps midnight legible and interiors are lit around the
	# clock, so "what time is it" was previously a walk outside and a squint at the sun.
	# Right-aligned in a box the same WIDTH as the map so the two right edges line up into one column, and
	# parented to whichever carrier the map chose: they are one instrument cluster, and a clock swaying under
	# a static map (or vice versa) would visibly shear. Built between the map and the tracker because BOTH of
	# its neighbours' tops are derived from it — see hud_clock_top / quest_tracker_top.
	_clock = HUD_CLOCK_SCRIPT.new()
	_clock.name = "HudClock"
	_clock.anchor_left = 1.0
	_clock.anchor_right = 1.0
	# Right rail measured off the AUTHORED map box, not the knob: the two right edges line up into one column,
	# so sliding the map in the editor must slide the clock's rail with it. Built after the map, so it is set.
	var map_box := minimap_box(_minimap)
	_clock.offset_right = -map_box.position.x
	_clock.offset_left = -map_box.position.x - GameSettings.hud.clock_size.x
	var clock_top := hud_clock_top(true)   # seeded map-up; _apply_minimap_visibility re-derives it per frame
	_clock.offset_top = clock_top
	_clock.offset_bottom = clock_top + GameSettings.hud.clock_size.y
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_clock.add_theme_font_size_override(&"font_size", GameSettings.hud.clock_font_size)
	_clock.add_theme_color_override(&"font_color", MenuStyle.hud.clock_color)
	# Same black-outline dialect as the quest tracker it stacks with (stamped at build time — a runtime
	# set_hud_skin needs a HUD rebuild to repaint it, exactly like the tracker below).
	_clock.add_theme_color_override(&"font_outline_color", MenuStyle.hud.label_outline_color)
	_clock.add_theme_constant_override(&"outline_size", MenuStyle.hud.toast_outline_size)
	_clock.z_index = 1  # the minimap's tier: over PlayerHud's full-screen flashes, under the crosshair
	if GameSettings.hud.minimap_rides_hud_weight:
		_weighted.add_child(_clock)
	else:
		add_child(_clock)
	# Quest tracker: the current active objective, in the top-right corner UNDER the minimap (money/rep/toasts are
	# top-left, HP/ammo bottom). A FIXED quest_tracker_width column, right-aligned: short lines still hug the
	# right edge, long authored text word-wraps DOWNWARD over empty screen instead of marching left toward the
	# money band. No ellipsis trim — it would eat the "(2/5)" progress tail. Refreshed off the QuestTracker
	# autoload's quest signals; hidden when no quest is active.
	_quest_tracker = Label.new()
	_quest_tracker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quest_tracker.anchor_left = 1.0
	_quest_tracker.anchor_right = 1.0
	_quest_tracker.offset_left = -8.0 - GameSettings.hud.quest_tracker_width
	_quest_tracker.offset_right = -8.0
	_quest_tracker.offset_top = quest_tracker_top(true, true)
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
	# Quest feedback: tracker line + toasts, driven by the QuestTracker autoload's quest signals (self-wired
	# here). The signals live on QuestTracker; the tracker line's READS still go through GameState's one-line
	# forwarding accessors (active_quest_ids / active_quest / objective_progress — see _refresh_quest_tracker).
	QuestTracker.quest_started.connect(_on_quest_started)
	QuestTracker.objective_advanced.connect(_on_quest_objective)
	QuestTracker.quest_completed.connect(_on_quest_completed)
	QuestTracker.quest_failed.connect(_on_quest_failed)
	_refresh_quest_tracker()  # show any already-active quest (e.g. one restored from a save) from frame one
	# B-F40: if the last profile load dropped any quest whose .tres went missing, tell the player — otherwise that
	# progress vanishes silently. Consume-once (take_load_warnings clears them) so a HUD rebuild on a level change
	# doesn't re-toast old warnings. Amber = a load caveat.
	for msg in GameState.take_load_warnings():
		_push_toast(str(msg), LOAD_WARNING_COLOR)
	# ROW 1 OF THE MONEY RAIL: the persistent zorkmid readout with the OWED row beside it, carried by ONE
	# HBoxContainer rather than two hand-placed labels — the zorkmid text is variable-width, so only a container
	# can put a second readout after it, and hiding the (usually hidden) OWED label collapses the gap for free.
	# Refreshed + a floating +N/-N spawned on Player.money_changed (wired in setup). Outlined like the toasts so
	# it reads over any backdrop. On the weight carrier (it's corner furniture) but NOT under _notices —
	# dialogue hides notifications, and this readout deliberately stays visible through a conversation.
	var money_row := HBoxContainer.new()
	money_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	money_row.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	money_row.position = Vector2(8, MONEY_ROW_PAD)
	money_row.add_theme_constant_override(&"separation", int(MONEY_ROW_PAD))
	_weighted.add_child(money_row)
	_money_label = Label.new()
	_money_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_money_label.add_theme_font_size_override(&"font_size", MONEY_FONT_SIZE)
	_money_label.add_theme_color_override(&"font_color", MONEY_COLOR)
	_money_label.add_theme_color_override(&"font_outline_color", MenuStyle.hud.label_outline_color)
	_money_label.add_theme_constant_override(&"outline_size", MenuStyle.hud.toast_outline_size)
	money_row.add_child(_money_label)
	# THE OWED ROW — to the RIGHT of the zorkmid readout on the same top line, and only while the ledger account
	# is NEGATIVE. The readout beside it is CASH-ONLY (Character.money), so without this the run's debt is
	# invisible outside the ATM screen — and it compounds daily (LedgerAccrual: 2%/day against savings' 0.5%).
	# Hidden while solvent, so a run that never borrows never sees it. Same font/outline as the readout; always
	# the debt tint. It must NOT go UNDER the readout: that band is row 2, reserved for the +N/-N money float,
	# and money_debt_color ships as the same Color as money_loss_color (see MONEY_ROW_PAD).
	_owed_label = Label.new()
	_owed_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_owed_label.add_theme_font_size_override(&"font_size", MONEY_FONT_SIZE)
	_owed_label.add_theme_color_override(&"font_color", MONEY_DEBT_COLOR)
	_owed_label.add_theme_color_override(&"font_outline_color", MenuStyle.hud.label_outline_color)
	_owed_label.add_theme_constant_override(&"outline_size", MenuStyle.hud.toast_outline_size)
	_owed_label.visible = false
	money_row.add_child(_owed_label)
	_stamp_money_readout(0.0)  # placeholder until the first poll/signal; the stamp owns text + debt tint + the OWED row
	# THE OWED ROW'S REAL DRIVER. GameState.account moves on two paths the WALLET never sees — a credit purchase
	# that draws nothing from an empty wallet (Player.charge debits the account alone, so money_changed never
	# fires) and the daily LedgerAccrual interest. The row currently repaints on those anyway ONLY because
	# _process's per-frame WALLET poll routes through the same stamp: coupling, not a contract — it goes stale the
	# moment that poll is dropped or its is_instance_valid(player) gate closes (death, pre-setup). This signal is
	# the honest wire, and it stays a signal — never a second per-frame poll on the account.
	if not GameState.account_changed.is_connected(_on_account_changed):
		GameState.account_changed.connect(_on_account_changed)
	if not Reputation.reputation_changed.is_connected(_on_reputation_changed):
		Reputation.reputation_changed.connect(_on_reputation_changed)
	if not Reputation.alignment_changed.is_connected(_on_alignment_changed):
		Reputation.alignment_changed.connect(_on_alignment_changed)
	# Look-at name readout (FNV-style): a centered label just below the crosshair, shown while aiming at a
	# talkable target (set_look_name). Hidden until then.
	_look_name = Label.new()
	# This readout paints composed prompts carrying NAMES — including player-TYPED pet names pushed onto a
	# host's display_name by Claimable._apply_name ("Take Rex", "Pet Rex"). Typed text must never be
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
	# Boot the reticle from the LIVE world state rather than assuming "shown": this HUD is rebuilt on every
	# level load / respawn reload, which can land mid-conversation. The HOLSTER half is stamped by the Player
	# (its _ready runs AFTER ours — we're its child), which both connects holster_changed and seeds the latch
	# from the final holster state.
	set_crosshair_visible(not DialogueManager.is_engaged())
	_build_ghost()
	# AFTER _build_ghost, so the composite rect is born on a canvas the accumulator is already watching, and
	# on frame ONE rather than on the first _process — a HUD that snaps from flat to curved after a frame
	# reads as a glitch on every level load.
	_apply_hud_curve()

## THE HUD GHOST (scripts/ui/hud_ghost.gd): re-render this layer's canvas into a never-cleared offscreen
## buffer that fades a little each frame, and draw that buffer BEHIND the live HUD — so moving readouts drag
## a soft tail, and while the camera turns the whole ghost image lags a couple of pixels so the screen-locked
## reticle participates too. Built LAST, after every overlay above exists, because the opt-outs below name
## the nodes they flag.
##
## THE GHOST RULE: an INSTRUMENT READOUT ghosts; a FULL-SCREEN WASH and a WORLD-DIRECTION annotation do not.
## Opting out is one `visibility_layer` write that carries to the node's whole subtree, and there are exactly
## three reasons to spend one:
##   1. IT WOULD BREAK — anything that SAMPLES THE SCREEN. Inside the capture the "screen" is the HUD-only
##      buffer, so this layer's own state post-process rect (which re-emits the whole sampled frame opaquely)
##      would paint the accumulator solid, and the reticle's back-buffer copy would read a near-empty screen.
##      The SCOPED inverting reticle is the same problem and is handled per-transition in set_scoped.
##   2. IT WOULD BE MUD — a full-screen wash (the hurt / kill / dash flashes, the speed vignette, the blood
##      splatter, the scope optics) smeared over its own tail is a haze, not an echo. They own their fades.
##   3. IT WOULD LIE — the directional damage arcs, the "being aimed at" radials and the sniper glints point
##      at WORLD directions. A lagging bearing reports a threat that is no longer there.
##   4. IT ISN'T THE HUD — the VIEW MODEL. The gun pass is rendered by its own camera into its own
##      SubViewport and composited back through a full-rect SubViewportContainer that happens to live on
##      this layer (ViewModelCamera._attach_container, which flags itself there). That is a compositing
##      detail, not a readout: ghosted, the whole weapon smears behind itself on every turn.
## ⭐THE DISPLAY RECT'S SEAT IS THE OTHER HALF OF THIS BLOCK, and it is an INDEX, not a z_index: it goes
## immediately after this layer's post-process ColorRect, which is what keeps the ghost OUT of that shader's
## screen fetch. It used to sit at z -1 — below the pass — and the barrel lens then bent the echo off the
## readout it echoes. hud_ghost.gd `_place_display` carries the full account.
## Everything else is captured BY DEFAULT (visibility_layer 1) and needs no wiring at all — which is what
## keeps runtime-built children (a fresh toast, a rebuilt HP segment, a new minimap glyph) ghosting for free.
func _build_ghost() -> void:
	if _ghost != null:
		return
	_ghost = HUD_GHOST_SCRIPT.new()
	_ghost.name = "HudGhostDriver"
	add_child(_ghost)
	# The post-process ColorRect is handed over TWICE over the next three lines, for two different reasons that
	# happen to name the same node: it is the screen-space pass the display rect must be seated ABOVE (or the
	# ghost is drawn through the barrel lens and lands off its own readout — hud_ghost.gd `_place_display`),
	# and it is exclusion (1) below, because it samples the screen and must not be captured.
	var screen_pass := get_node_or_null(^"ColorRect") as CanvasItem
	if not _ghost.build(self, screen_pass):
		return
	# (1) would break: the screen samplers this layer owns.
	HUD_GHOST_SCRIPT.set_ghosted(screen_pass, false)
	HUD_GHOST_SCRIPT.set_ghosted(_crosshair_bbc, false)
	# (2) would be mud: the full-screen washes this layer owns directly.
	HUD_GHOST_SCRIPT.set_ghosted(get_node_or_null(^"BloodSplatter") as CanvasItem, false)
	HUD_GHOST_SCRIPT.set_ghosted(_scope_vignette, false)
	HUD_GHOST_SCRIPT.set_ghosted(_scope_flare, false)
	# PlayerHud's overlays are built later (from Player._ready, which runs after this layer's _ready), so they
	# flag themselves at the bottom of PlayerHud.build under rules 2 and 3.
	_build_world_ghost()

## THE WORLD GHOST (scripts/effects/world_ghost.gd): the same persistence, applied very faintly to the picture
## behind the HUD. Built and driven from here because this layer is where the game already keeps its
## screen-space passes (the post-process rect is a child of it), but it is NOT on this canvas — it makes its
## own CanvasLayer ABOVE this one, so the frame it composites over is the same frame its accumulator averaged
## (this HUD and the weapon included). That is also why it needs no ghost-capture opt-out: a separate canvas
## is never captured by the HUD ghost, which only borrowed THIS one.
func _build_world_ghost() -> void:
	if _world_ghost != null:
		return
	_world_ghost = WORLD_GHOST_SCRIPT.new()
	_world_ghost.name = "WorldGhostDriver"
	add_child(_world_ghost)
	_world_ghost.build(self)


## The live bend: the authored barrel amount, scaled by the Options -> Accessibility "HUD Curve" dial.
## Either half at zero means OFF, and OFF tears the whole apparatus down — see the field block.
func _hud_curve_strength() -> float:
	return maxf(GameSettings.hud.hud_curve_amount, 0.0) * clampf(float(Settings.hud_curve_scale), 0.0, 1.0)

## Stand the curved-glass pass up / tear it down, and keep its render target and uniforms current. Polled
## every frame from _process because the Options row applies live. Safe on a bare UI.new(): several suites
## build one without ever running _ready, so `_weighted` is null there and this returns before touching
## GameSettings, Settings or the tree.
func _apply_hud_curve() -> void:
	if _weighted == null or not is_inside_tree():
		return
	if _hud_curve_strength() <= 0.0:
		_teardown_hud_curve()
		return
	if _curve_viewport == null:
		_build_hud_curve()
	# ⭐THE CANVAS IS NOT A CONSTANT: stretch aspect "expand" grows it with the window's aspect ratio, so a
	# render target frozen at the boot size would crop the panel the moment the window changed. `_weighted` is
	# PRESET_FULL_RECT, so its own size follows this — and _update_hud_sway reads that size for the lens-breath
	# pivot, which is the second reason this must track the real canvas instead of a hardcoded 792x444.
	var canvas: Vector2 = get_viewport().get_visible_rect().size
	var want := Vector2i(maxi(int(roundf(canvas.x)), 1), maxi(int(roundf(canvas.y)), 1))
	if _curve_viewport.size != want:
		_curve_viewport.size = want
	# Park the render target whenever the composite is down (the death cinematic, `hud off`): an invisible
	# pass should cost nothing, the ink_outline.gd idiom. `_curve_rect` is precisely what the sweep hides.
	var mode := SubViewport.UPDATE_ALWAYS if _curve_rect.visible else SubViewport.UPDATE_DISABLED
	if _curve_viewport.render_target_update_mode != mode:
		_curve_viewport.render_target_update_mode = mode
	var amount := _hud_curve_strength()
	# `amount` always drives the Y bend, because that is the one that bows HORIZONTAL lines — the signature
	# of a monitor curved about a VERTICAL axis, which is the shape being asked for. `axis_ratio` scales the
	# X bend on top of it: 0 leaves every vertical dead straight (the shipped cylinder), 1 bends both axes
	# equally (a spherical, eye-like bulge). Positive is CONCAVE — the inside of the cylinder; see the shader.
	_curve_mat.set_shader_parameter("curve",
		Vector2(amount * maxf(GameSettings.hud.hud_curve_axis_ratio, 0.0), amount))
	_curve_mat.set_shader_parameter("edge_fade", clampf(GameSettings.hud.hud_curve_edge_fade, 0.0, 1.0))
	_curve_mat.set_shader_parameter("chroma", clampf(GameSettings.hud.hud_curve_chroma, 0.0, 1.0))

## Build the curve viewport + its composite rect and move the carrier inside. Never called directly — go
## through _apply_hud_curve, which owns the on/off decision.
func _build_hud_curve() -> void:
	# The carrier's slot in the child list IS its slot in the draw order, and the composite has to inherit it:
	# the panel used to draw under the full-screen flashes the Player adds later, and appending at the end
	# would quietly promote it above them.
	var slot := _weighted.get_index()
	_curve_viewport = SubViewport.new()
	_curve_viewport.name = "HudCurveViewport"
	# transparent_bg or the panel paints an opaque clear colour over the entire world. UPDATE_ALWAYS because a
	# SubViewport that is NOT under a SubViewportContainer has no reliable visibility signal for
	# UPDATE_WHEN_VISIBLE to key off — the call every hand-composited pass in this project already makes
	# (view_model_camera.gd, ink_outline.gd, character_preview.gd). The default CLEAR_MODE_ALWAYS is correct
	# and deliberately left alone: CLEAR_MODE_NEVER would accumulate last frame's panel.
	_curve_viewport.transparent_bg = true
	_curve_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var canvas: Vector2 = get_viewport().get_visible_rect().size
	_curve_viewport.size = Vector2i(maxi(int(roundf(canvas.x)), 1), maxi(int(roundf(canvas.y)), 1))
	# Keep the panel's own art crunchy INSIDE the viewport. This governs how the carrier's children sample
	# THEIR textures and has no say over how the composite samples the render target — that is the shader's
	# own filter_nearest hint, which outranks every node-level setting.
	_curve_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(_curve_viewport)
	_curve_mat = ShaderMaterial.new()
	_curve_mat.shader = HUD_CURVE_SHADER
	_curve_mat.set_shader_parameter("hud_tex", _curve_viewport.get_texture())
	_curve_rect = ColorRect.new()
	_curve_rect.name = "HudCurve"
	_curve_rect.material = _curve_mat
	_curve_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# z 2 is the carrier's TALLEST child (the HP/stamina bars and the corner labels), not its own z 0: those
	# were deliberately lifted above the full-screen flashes so a hurt wash cannot drown a gauge, and
	# flattening the panel into one composite collapses that ladder to whatever this rect carries. Taking the
	# max keeps the authored intent (readouts stay legible through a flash); the cost is that the map, hotbar
	# and toasts rise with them, which nothing overlaps — they are corner furniture and the flashes are washes.
	_curve_rect.z_index = 2
	_curve_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_curve_rect)
	move_child(_curve_rect, slot)
	# Inherit the carrier's hidden state: if the death sweep (or `hud off`) is holding the panel DOWN right
	# now, the composite must be born down too, and it has to TAKE THE CARRIER'S PLACE in the sweep's list —
	# the restore walks that list, and leaving a node in it that no longer answers for the panel would either
	# strand the HUD hidden or pop it back over the death fade.
	if not _weighted.visible:
		_curve_rect.visible = false
		var at := _death_hidden_hud.find(_weighted)
		if at >= 0:
			_death_hidden_hud[at] = _curve_rect
		_weighted.visible = true
	_reparent_weighted(_curve_viewport)

## Tear the curve down and hand the carrier back to the layer, in the composite's draw slot. The tree is then
## EXACTLY the pre-curve one: no residual viewport, no identity shader pass, nothing left to pay for.
func _teardown_hud_curve() -> void:
	if _curve_viewport == null:
		return
	var slot := -1
	var was_down := false
	if is_instance_valid(_curve_rect):
		slot = _curve_rect.get_index()
		was_down = not _curve_rect.visible
	_reparent_weighted(self)
	if slot >= 0:
		move_child(_weighted, slot)
	# The mirror of the adoption in _build_hud_curve: hand the composite's hidden state, and its seat in the
	# death sweep's list, back to the carrier before the composite stops existing.
	if was_down:
		_weighted.visible = false
		var at := _death_hidden_hud.find(_curve_rect)
		if at >= 0:
			_death_hidden_hud[at] = _weighted
	if is_instance_valid(_curve_rect):
		_curve_rect.queue_free()
	_curve_rect = null
	_curve_mat = null
	_curve_viewport.queue_free()
	_curve_viewport = null

## Move the carrier between this layer and the curve viewport without disturbing anything it holds. Nothing
## here touches its transform: it is PRESET_FULL_RECT in both homes and both homes are the same canvas size,
## so every child keeps its absolute coords — the same promise the carrier already makes to anything that
## parents into it.
func _reparent_weighted(to: Node) -> void:
	if _weighted == null or to == null or _weighted.get_parent() == to:
		return
	var from := _weighted.get_parent()
	if from != null:
		from.remove_child(_weighted)
	to.add_child(_weighted)
	_weighted.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

## ⭐THE CURVE VIEWPORT IS DEAF UNTIL SOMEBODY HANDS IT THE KEYBOARD, AND THIS IS THAT SOMEBODY.
## The root Window pumps only ITS OWN `_unhandled_input` group; a nested SubViewport hears nothing unless a
## `SubViewportContainer` forwards into it, and this composite is hand-built (a ColorRect sampling the render
## target — the project's hand-composited idiom), so there is no container. The moment `_weighted` moved inside
## `_curve_viewport`, every carrier child went deaf. The Hotbar is the one that noticed: its slot keys (1-0) and
## the weapon wheel live in `_unhandled_input`, so a HUD curve of any strength — and it defaults ON — silently
## killed the entire bar while it still rendered perfectly. Verified against 4.7.1: a Control inside a bare
## SubViewport receives ZERO events from the main pump, and `push_input(ev, true)` delivers them
## (`push_unhandled_input` does too, but 4.7 deprecates it).
##
## Forwarded from `_unhandled_input`, so the panel sees only what the world's GUI and `_input` already declined —
## the same slot the carrier's children used to occupy. `is_input_handled()` carries a consumer's
## `set_input_as_handled()` back out, so a slot key still STOPS here instead of falling through to the next
## gameplay consumer, exactly as it did before the curve existed.
##
## ⭐UNCONDITIONAL ON PURPOSE — not gated on `_curve_rect.visible`. A hidden CanvasItem still receives unhandled
## input (verified), so the death sweep and `hud off` never silenced the bar in the pre-curve tree and must not
## start to now: OFF IS THE OLD TREE is the promise the whole curve block is built on, and a curve that quietly
## changed WHICH KEYS WORK would break it just as badly as one that changed the pixels.
func _unhandled_input(event: InputEvent) -> void:
	if _curve_viewport == null or not _curve_viewport.is_inside_tree():
		return  # curve off -> `_weighted` is a plain child of this layer and hears the pump directly
	_curve_viewport.push_input(event, true)
	if _curve_viewport.is_input_handled():
		get_viewport().set_input_as_handled()


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
	_apply_minimap_visibility()

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

## THE TOP-RIGHT STACK, as three derived tops. Row 1 is the minimap at its own inset; row 2 is the clock;
## row 3 is the objective tracker. Each row's top is computed from the row ABOVE it, and every row can be
## switched off independently by the player, so the two functions below are the whole reflow rule.
##
## Pure: the y the CLOCK's top sits at. Under the map when the map is up (inset + box height + gap); with
## the map off (Options -> Accessibility -> "Minimap") it lifts to GameSettings.hud.clock_bare_top rather
## than leaving a 114 px hole where the map used to be. Static + unit-tested for the reason its sibling
## below is: "the top-right stack does not collide" is a layout INVARIANT, not something to eyeball once.
static func hud_clock_top_for(map_visible: bool, inset_y: float, map_h: float, gap: float, bare: float) -> float:
	return (inset_y + map_h + gap) if map_visible else bare

## Pure: the y the top-right objective column's first line starts at. WITH the minimap up it sits under it
## (inset + box height + gap); with the map off (Options -> Accessibility -> "Minimap") it returns to
## GameSettings.hud.minimap_tracker_bare_top, which ships as 8.0 — byte-identical to the pre-minimap
## layout, so turning the map off restores the historical corner exactly instead of leaving a hole where
## it used to be.
##
## The CLOCK row is an ADDITIVE trailing argument, defaulting to "no clock": with it omitted this returns
## exactly what it always did, so the pre-clock pins in tests/test_minimap_hud_layout.gd still describe the
## live rule rather than a rewritten one. When the clock IS up the tracker drops by its box plus its own
## gap — measured from wherever the clock actually landed, which is why the map's own visibility only
## enters once (through the clock's top) and is never double-counted here.
static func quest_tracker_top_for(map_visible: bool, inset_y: float, map_h: float, gap: float, bare: float,
		clock_visible: bool = false, clock_h: float = 0.0, clock_gap: float = 0.0,
		clock_map_gap: float = 0.0, clock_bare: float = 0.0) -> float:
	if clock_visible:
		return hud_clock_top_for(map_visible, inset_y, map_h, clock_map_gap, clock_bare) + clock_h + clock_gap
	return (inset_y + map_h + gap) if map_visible else bare

## Pure: THE AUTHORED MINIMAP BOX, as {position = the (right, top) INSET from the screen's top-right corner,
## size = the drawn box}. This is what makes scenes/ui/hud_minimap.tscn the measurement rather than just the
## art: drag the box in the 2D editor and the clock and the objective tracker under it move with it, because
## both derive their tops from what this returns.
##
## Fed the four ANCHOR OFFSETS the .tscn authors, never the Control's `size`/`position`: a freshly instantiated,
## unparented Control is 0x0 until the first layout sort, and the clock/tracker seeds below run before that sort.
## A non-positive box — a bare Control.new() with all-zero offsets, a failed instantiate — answers `fallback`,
## which is how the knob-derived layout survives a missing map completely unchanged.
##
## Right-anchored, so the offsets are NEGATIVE distances from the right screen edge: the inset is -offset_right.
static func minimap_box_from(offset_left: float, offset_top: float, offset_right: float,
		offset_bottom: float, fallback: Rect2) -> Rect2:
	var w := offset_right - offset_left
	var h := offset_bottom - offset_top
	if w <= 0.0 or h <= 0.0:
		return fallback
	return Rect2(-offset_right, offset_top, w, h)

## The same rule bound to the live widget, with GameSettings.hud's knobs as the fallback box. Computed per call
## rather than cached in a field: there is no seeding order to get wrong, and a bare UI.new() whose _minimap is
## still null automatically reads the knobs. Untyped param + an `is Control` gate (not a duck-typed .get()) so
## the suites that substitute a bare Control.new() land on the fallback with no special-casing.
func minimap_box(map) -> Rect2:
	var fallback := Rect2(GameSettings.hud.minimap_inset, GameSettings.hud.minimap_size)
	if not (map is Control):
		return fallback
	var c := map as Control
	return minimap_box_from(c.offset_left, c.offset_top, c.offset_right, c.offset_bottom, fallback)

## The clock rule bound to the live knobs — and, for the two terms the artist owns, to the AUTHORED box.
func hud_clock_top(map_visible: bool) -> float:
	var h := GameSettings.hud
	var b := minimap_box(_minimap)
	return hud_clock_top_for(map_visible, b.position.y, b.size.y,
			h.clock_map_gap, h.clock_bare_top)

## The same rule bound to the live knobs. Note the two pure statics above keep their exact signatures: the
## authored box enters HERE, at the live-binding layer, so every literal pin in tests/test_minimap_hud_layout.gd
## still describes the real rule rather than a rewritten one.
func quest_tracker_top(map_visible: bool, clock_visible: bool = false) -> float:
	var h := GameSettings.hud
	var b := minimap_box(_minimap)
	return quest_tracker_top_for(map_visible, b.position.y, b.size.y,
			h.minimap_tracker_gap, h.minimap_tracker_bare_top,
			clock_visible, h.clock_size.y, h.clock_tracker_gap, h.clock_map_gap, h.clock_bare_top)

## THE WHOLE TOP-RIGHT STACK's visibility and reflow, polled live off Settings.minimap_enabled and
## Settings.clock_enabled so either Options toggle bites the same frame with no rebuild (the loot_beacons /
## detection_meter / stamina_ring family), composed with the dialogue-hide flag. Kept under its original
## name — tests/test_hud_feedback.gd calls it directly — but it now owns three rows, not one: the map, the
## clock under it, and the objective tracker under that. The two lower rows re-derive their tops here
## because each was pushed down to clear a row the player may have just switched off. BAILS during the
## death cinematic for exactly the reason _apply_stamina_mode does: hide_hud_for_death has already hidden
## these and remembered which, and a per-frame re-show here would resurrect the panel over the fade.
func _apply_minimap_visibility() -> void:
	if not _death_hidden_hud.is_empty():
		return
	# `_minimap != null` is part of the QUESTION, not a guard: a failed instantiate must lift the clock into the
	# corner and pull the tracker up with it, exactly as switching the map off in Options does — not leave a
	# 114 px hole under a map that is not there.
	var want: bool = _minimap != null and _gameplay_hud_visible and Settings.minimap_enabled
	var want_clock: bool = _gameplay_hud_visible and Settings.clock_enabled
	if _minimap != null:
		_minimap.visible = want
	# The clock re-derives its OWN top too: switching the map off in Options must lift the clock into the
	# corner, not just slide the tracker up underneath a clock that stayed put.
	if _clock != null:
		_clock.visible = want_clock
		var clock_top := hud_clock_top(want)
		if not is_equal_approx(_clock.offset_top, clock_top):
			_clock.offset_top = clock_top
			_clock.offset_bottom = clock_top + GameSettings.hud.clock_size.y
	if _quest_tracker != null:
		var top := quest_tracker_top(want, want_clock)
		if not is_equal_approx(_quest_tracker.offset_top, top):
			_quest_tracker.offset_top = top

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
	_purge_transient_notices()
	for ci in _death_hidden_hud:
		if is_instance_valid(ci):
			ci.visible = true
	_death_hidden_hud.clear()
	# Re-derive the reticle rather than trusting the snapshot: the blanket restore above would show a
	# crosshair that was up at the killing blow even though the fresh life starts with the weapon stowed
	# (and _apply_crosshair_visibility bailed for every holster/dialogue change made during the cinematic).
	# Must run AFTER the clear — the apply no-ops while the death list is non-empty.
	_apply_crosshair_visibility()

## Free every transient top-left notification that predates this restore — the toast labels under _rep_toasts
## and the +N/-N money float. Their hold/fade tweens are deliberately NOT ignore_time_scale, so the death
## cinematic's slow-mo stretches them: a toast born on the killing-blow frame (a cripple line, a dialogue-abort
## flush) or pushed invisibly mid-cinematic by a POSTHUMOUS kill (collateral/long-range bounty, a kill-quest
## objective, a faction hit) is often still alive when the HUD returns, popping half-faded over the spawn
## fade-in. The fresh life starts with a clean stack; the deliberate revive receipts (wallet / grudge / tutorial
## toasts) are pushed AFTER this restore by _finish_respawn_hud_restore, so they are never swept. Nodes are
## hidden before queue_free — a freed node still draws until end of frame, and one stale frame is the bug.
func _purge_transient_notices() -> void:
	if _rep_toasts != null:
		for t in _rep_toasts.get_children():
			if t is CanvasItem:
				(t as CanvasItem).visible = false
			t.queue_free()
	if is_instance_valid(_money_delta_label):
		if _money_delta_tw != null:
			_money_delta_tw.kill()
		_money_delta_label.visible = false
		_money_delta_label.queue_free()
	_money_delta_label = null
	_money_delta_tw = null
	_money_delta_sum = 0.0

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
		_look_rate = Vector2.ZERO
		if _sway_primed:
			# wrapf on the yaw delta: the +-PI seam would otherwise read a full-circle fake flick.
			var yaw_rate := wrapf(yaw - _sway_last_yaw, -PI, PI) / delta
			var pitch_rate := (pitch - _sway_last_pitch) / delta
			look = HUD_SWAY_SCRIPT.look_target(yaw_rate, pitch_rate,
					GameSettings.hud.hud_sway_gain, GameSettings.hud.hud_sway_max)
			_look_rate = Vector2(yaw_rate, pitch_rate)  # the ghost’s latency rides this same sample
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
		_look_rate = Vector2.ZERO
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

## Swap the reticle between its cheap flat dot and the scoped inverting disc. This does NOT touch visibility
## — that's _apply_crosshair_visibility's alone (and scoping implies a drawn weapon anyway: ScopeIn refuses
## to ADS a holstered one). Scoping only upgrades the material and turns on the back-buffer copy the
## inverting shader needs. Null-guarded so it is safe to call before _ready has built the dot.
func set_scoped(scoped: bool) -> void:
	_apply_crosshair_look(scoped)
	# Only pay for the full-screen back-buffer copy while the inverting disc is actually up.
	if _crosshair_bbc:
		_crosshair_bbc.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT if scoped else BackBufferCopy.COPY_MODE_DISABLED
	# ...and the reticle leaves the HUD-ghost capture for exactly as long as it wears that shader. Inside the
	# ghost’s offscreen buffer the "screen" is the HUD alone, so `1.0 - screen` resolves to near-white there
	# and the ghost would trail a bright disc behind a reticle whose entire job is contrast. Scoping is also
	# where a second reticle image is least wanted, so the aim point simply stops ghosting while you are down
	# the scope and resumes on the way out — the panel and the rest of the HUD keep ghosting throughout.
	HUD_GHOST_SCRIPT.set_ghosted(crosshair, not scoped)

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

## THE RETICLE'S TWO SUPPRESSION LATCHES. Two owners hide the crosshair — a conversation, and the weapon
## being HOLSTERED — and they OVERLAP: dialogue force-holsters the weapon (DialogueController) and restores
## that state on finish, so an imperative show/hide would let the conversation's closing `show` un-hide the
## reticle over a weapon that is still put away (and a hold-R holster taken mid-conversation would do the
## mirror on the un-holster). Latch per REASON and derive; _apply_crosshair_visibility is the SINGLE writer
## of crosshair.visible. Order-independent — whichever owner settles last, the answer is the same.
var _crosshair_hidden_dialogue: bool = false
var _crosshair_hidden_holstered: bool = false

## Show / hide the reticle for a CONVERSATION — the historical name + contract (vis=false hides), now one
## latch of two. The parent HUD's own `visible` (cleared on death) still wins, so this never un-hides a dead HUD.
func set_crosshair_visible(vis: bool) -> void:
	_crosshair_hidden_dialogue = not vis
	_apply_crosshair_visibility()

## The weapon was put away / brought back out — driven by Attack.holster_changed, connected in Player._ready
## (which also seeds it, since set_holstered emits nothing when the value is unchanged). Nothing is aimed
## while it's stowed, so the aim-point annotation goes with it; gated on the designer knob, read HERE so
## flipping it in the inspector applies without a holster round-trip.
func set_crosshair_holstered(holstered: bool) -> void:
	_crosshair_hidden_holstered = holstered
	_apply_crosshair_visibility()

## The one place crosshair.visible is written. BAILS during the death cinematic for the same reason
## _apply_stamina_mode does: hide_hud_for_death has hidden these nodes and remembered exactly which, so a
## write here would resurrect the reticle over the fade — restore_hud_after_death re-applies this instead.
## The latches keep updating while it bails, so the revive adopts whatever the world settled on meanwhile.
func _apply_crosshair_visibility() -> void:
	if not is_instance_valid(crosshair) or not _death_hidden_hud.is_empty():
		return
	crosshair.visible = crosshair_shown(_crosshair_hidden_dialogue, _crosshair_hidden_holstered,
			GameSettings.hud.hide_crosshair_when_holstered)

## PURE composition rule (the StaminaRing/HudSway static idiom): tests/test_crosshair_visibility.gd pins the
## truth table off-tree, without building this CanvasLayer or the autoloads its _ready needs.
static func crosshair_shown(hidden_by_dialogue: bool, holstered: bool, hide_when_holstered: bool) -> bool:
	return not hidden_by_dialogue and not (holstered and hide_when_holstered)

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
## Gate on is_engaged(), NOT is_active(): the notices layer is hidden for the whole dialogue_started ->
## dialogue_finished span (nothing listens to suspended/resumed), but is_active() reads FALSE while a sub-menu
## suspends the conversation (e.g. buying a quest-objective item in Trade) — that toast must queue too.
func _push_quest_toast(text: String, color: Color) -> void:
	if DialogueManager.is_engaged():
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

## Row 2 of the money rail: the y the +N/-N float SPAWNS at, before it rises MONEY_DELTA_RISE px out of the band.
## Derived from row 1's own font so a HudSettings money_font_size bump slides the band down with the readout
## instead of letting the float draw over it (see MONEY_ROW_PAD for the whole rail).
func _money_delta_row_y() -> float:
	return MONEY_ROW_PAD + float(MONEY_FONT_SIZE) + MONEY_ROW_PAD

## Stamp the top-left readout — text AND tint in one seam (the build, the money_changed signal and the
## per-frame _process poll all route here so the colour can never lag the number). Gold while solvent, the debt
## red the moment the WALLET ITSELF is negative. The payment seam never does that (Player.charge spends cash then
## the account and refuses to push `money` below zero — the wallet is cash-only), but an authored
## DialogueChoice.give_money fee still can: it is documented as "NEGATIVE for a fee/cost" and DialogueManager
## applies it with no affordability gate, so the branch is a live case, not dead code. The run's DEBT is a
## different number living on the ledger account, and it is the OWED row beside this one that displays it.
func _stamp_money_readout(total: float) -> void:
	if _money_label == null:
		return
	_money_label.text = _money_text(total)
	_money_label.add_theme_color_override(&"font_color", MONEY_COLOR if total >= 0.0 else MONEY_DEBT_COLOR)
	_stamp_owed_row()  # rides the same stamp so the debt row can never lag the readout it sits beside

## THE ONE OWED-ROW PAINTER — both drivers below route here, so the row has exactly one place that decides
## whether it shows and what it says. It reads the LEDGER account, not the wallet: they are different money
## (cash vs the signed savings/debt balance), and only the account can owe.
##   1. _stamp_money_readout — keeps the row in lockstep with the readout beside it.
##   2. _on_account_changed  — the account moves on paths the WALLET never sees (a credit purchase with an empty
##      wallet debits the account alone; LedgerAccrual posts interest at dawn), and money_changed is blind to both.
func _stamp_owed_row() -> void:
	if _owed_label == null:
		return
	var account: float = GameState.account
	_owed_label.visible = account < 0.0
	if _owed_label.visible:
		_owed_label.text = PlayerText.hud_owed(absf(account))  # absolute — Zorkmids.fmt prints its own minus

## GameState.account_changed -> repaint the OWED row. The arity must match the signal EXACTLY (Godot 4 does not
## drop extra args), so this takes the emitted balance even though the painter re-reads GameState.account itself —
## the account is the single source of truth and no caller should be able to paint a row the ledger disagrees with.
func _on_account_changed(_value: float) -> void:
	_stamp_owed_row()

## Player.money changed (add_money): refresh the readout and float a colour-coded +N / -N up from it.
## Rapid deltas (a coin-pile vacuum, a multi-item sale) ACCUMULATE into the one live float — re-stamped and its
## rise+fade restarted — instead of stacking unreadable copies at the same spot; a flurry that nets to zero
## frees the float outright. The tween's queue_free + the validity guard naturally reset the cycle — the guard
## must also reject a label whose fade already queue_free'd THIS frame (still "valid" until end-of-frame), else
## a same-frame delta re-stamps a dying node and that float never renders.
func _on_money_changed(total: float, delta: float) -> void:
	_stamp_money_readout(total)
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
		_money_delta_label.position = Vector2(8, _money_delta_row_y())  # back to the band's top for the restarted rise
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
	ind.position = Vector2(8, _money_delta_row_y())  # row 2 of the money rail — the float's band, below the readout
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
	# Deliberately NOT gated on a live player: the Options toggle has to work on any frame, including the
	# ones around a death/respawn where `player` is briefly invalid.
	_apply_minimap_visibility()
	_apply_hud_curve()
	_update_hud_sway(delta)
	# AFTER the sway, so the ghost lags the panel position this frame actually settled on — and it is fed the
	# look rate the sway just measured rather than re-reading the camera. `may_show` mirrors the
	# _apply_stamina_mode / _apply_crosshair_visibility rule: the ghost’s display rect is a direct child of
	# this layer, so hide_hud_for_death has already hidden it and remembered it, and a blind re-show here
	# would resurrect it over the death fade.
	if _ghost != null:
		_ghost.poll(delta, _look_rate.x, _look_rate.y, _death_hidden_hud.is_empty())
	# The world ghost takes no `may_show`: its composite lives on its OWN layer, so the death sweep (which
	# only walks this layer's direct CanvasItem children) never hid it and there is no latch to respect. It
	# stays up through the cinematic on purpose — like the post-process rect, it is the picture's look rather
	# than a HUD readout, and switching it off mid-death would read as the image changing character.
	if _world_ghost != null:
		_world_ghost.poll(delta, _look_rate.x, _look_rate.y)
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
		_stamp_money_readout(float(player.get(&"money")))

## Ammo readout for the equipped weapon: "clip / reserve" (rounds in the magazine / rounds left in the
## backpack). Blank for a caliber-less weapon (melee / rock / spray) — those carry no reserve and their
## clip count is a sentinel, so there's nothing meaningful to show.
func _ammo_text() -> String:
	var weapon: WeaponData = ammo_count.current_weapon
	if weapon == null or weapon.caliber == &"" or not is_instance_valid(player) or player.inventory == null:
		return ""
	return "%d / %d" % [ammo_count.current_ammo, player.inventory.ammo_count(weapon.caliber)]
