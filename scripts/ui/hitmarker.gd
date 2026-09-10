class_name Hitmarker
extends Control

## Crosshair hit-confirm: four short ticks forming an X around the centre that pop in and fade
## out whenever the player lands damage. flash(headshot) makes a HEADSHOT pop bigger and in a
## distinct colour, so head hits read instantly. The owner calls flash().
##
## SKINNED: every look value (timing, tick geometry, colours, the optional artist texture) lives on
## MenuStyle.hud (resources/ui/hud_skin.tres, "Hitmarker" group) — this node is CODE-built by
## player_hud.gd, so the skin IS its authoring surface. Fields are read LIVE at flash/draw time
## (cheap: a handful per pop) so inspector edits and runtime skin swaps show immediately.

var _t: float = 0.0
var _headshot: bool = false
## > 0 = the next _draw paints ONE near-invisible marker at this strength and clears it (see warm_draw).
var _warm_alpha: float = 0.0
## A warm paint is sitting on the canvas and nothing else will ever redraw it away — the next processed
## frame spends this on one empty redraw. See warm_draw's "ONE PAINT IS NOT ONE FRAME".
var _warm_painted: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## Pop the marker. Pass headshot = true for the bigger, coloured head-hit confirm.
func flash(headshot := false) -> void:
	_t = MenuStyle.hud.hitmarker_duration
	_headshot = headshot
	queue_redraw()

## Draw the marker ONCE at `alpha` strength (the in-level EffectPrewarmer's 2D pass, behind its black cover after a
## level loads) so its canvas draw is issued before the first real hit — 2D pipelines have no precompilation, and a
## near-transparent draw is the only warm there is. Never touches _t / _headshot, so a live flash is unaffected: the
## one warm paint happens on the next _draw, which spends `_warm_alpha` there (that is the STAGED strength clearing
## itself — not the canvas; read on).
##
## ⭐ONE PAINT IS NOT ONE FRAME, AND THAT WAS A SHIPPED BUG (fixed 2026-09-08, user: "there's always a transparent
## X on my crosshair"). A CanvasItem KEEPS its draw list until something calls queue_redraw() again, and this node
## only redraws while a flash is fading (_process early-outs at _t <= 0) — so the warm ticks stayed on the canvas
## at the crosshair from the level load until the first landed hit cleared them. Worse, the hitmarker IS captured
## by the HUD ghost (hud_ghost.gd's ghost rule keeps the aim CLUSTER out, not this), so a permanently-lit source
## fed the phosphor accumulator every frame and came back several times brighter than it was drawn. Measured with
## scripts/tools/__hitmarker_warm_probe.tscn on the ticks' own footprint: the live 0.01 paint alone is 0.006 of
## screen brightness, the ghost takes it to 0.05 mean / 0.12 peak — ~35x this instrument's noise floor, i.e. a
## faint but real X. So _draw ARMS _warm_painted and the next processed frame spends it on one redraw with
## nothing left to paint; THAT frame is what empties the draw list. The warm is on screen for one frame, as its
## caller (EffectPrewarmer._warm_2d) has always claimed.
func warm_draw(alpha: float) -> void:
	_warm_alpha = alpha
	queue_redraw()

func _process(delta: float) -> void:
	# The warm paint's own clean-up, BEFORE the fade early-out below (that early-out is exactly why nothing
	# else would ever take it back). Costs one redraw, once, per warm.
	if _warm_painted:
		_warm_painted = false
		queue_redraw()
	if _t <= 0.0:
		return
	_t -= delta
	queue_redraw()

func _draw() -> void:
	if _warm_alpha > 0.0:
		var warm := _warm_alpha
		_warm_alpha = 0.0
		if _t <= 0.0:  # a live flash already paints this frame at full strength — that draw warms the same pipeline
			_warm_painted = true  # armed ONLY when the warm actually reaches the canvas; a live flash clears its own
			_draw_marker(warm)
			return
	if _t <= 0.0:
		return
	var hud = MenuStyle.hud  # untyped on purpose: HudSkin's class_name may not be cached yet
	_draw_marker(clampf(_t / maxf(hud.hitmarker_duration, 0.001), 0.0, 1.0))

## Paint the marker at fade strength `a` (1 = a fresh pop, 0 = gone): alpha AND the pop-out distance both ride it.
func _draw_marker(a: float) -> void:
	var hud = MenuStyle.hud  # untyped on purpose: HudSkin's class_name may not be cached yet
	var col: Color = hud.hitmarker_headshot_color if _headshot else hud.hitmarker_color
	col.a *= a
	var mult: float = hud.hitmarker_headshot_scale if _headshot else 1.0
	var centre := size * 0.5
	# OPTIONAL artist art: one centred texture (modulated by the body/headshot colour + fade, scaled
	# by the headshot mult) replaces the four drawn ticks. Null = the shipped code-drawn X.
	var tex: Texture2D = hud.hitmarker_texture
	if tex != null:
		var ts: Vector2 = tex.get_size() * mult
		draw_texture_rect(tex, Rect2(centre - ts * 0.5, ts), false, col)
		return
	var tick_len: float = hud.hitmarker_tick_length * mult
	var tick_w: float = hud.hitmarker_thickness * mult
	# Slight pop: ticks sit hitmarker_pop_px further out at full strength, settle in as they fade.
	var g: float = (hud.hitmarker_gap + hud.hitmarker_pop_px * a) * mult
	for dir in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var d = dir.normalized()
		draw_line(centre + d * g, centre + d * (g + tick_len), col, tick_w, true)
