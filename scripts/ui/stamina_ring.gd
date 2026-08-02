class_name StaminaRing
extends Control

## Radial stamina gauge wrapped AROUND the reticle (the ULTRAKILL / DOOM Eternal idiom): an arc that
## drains as stamina is spent, so the player reads the pool without looking away from the aim point.
## This is the SHIPPED default stamina readout; the classic bottom-left bar remains available as the
## accessibility fallback (Options -> Accessibility -> "Crosshair Stamina Ring" OFF) — see
## ui.gd _apply_stamina_mode for the mode switch and the default-choice rationale.
##
## CONTRACTS (ui.gd owns the driving):
## - `centre` is re-stamped EVERY frame from the live crosshair rect (crosshair.position + size * 0.5),
##   never from the viewport centre — the crosshair is repositioned per frame by Player._update_crosshair,
##   and a ring anchored anywhere else visibly detaches from the reticle the moment that policy sways it.
## - The ring must never ride the diegetic HUD-weight carrier (ui.gd `_weighted`) — but it is no longer
##   fully pinned either: the CROSSHAIR carries a whisper of the sway (hud_sway_aim_scale, ~1px max), and
##   the ring follows it through the centre stamp, re-stamped AFTER the sway write each frame (ui.gd
##   _update_hud_sway) so ring + reticle move as ONE. A ring lagging its own reticle reads as a broken
##   crosshair, which is why the stamp order matters more than the amplitude.
## - Annulus budget around the crosshair (same-centre neighbours): the Hitmarker's body ticks pop to
##   ~11 px, its headshot ticks to ~21; AimIndicators start at base_radius 28 (stroke 6 -> inner edge
##   ~25); DamageIndicators sit at 120 and the aim ping at 84. The default radius 14 / stroke 2 hugs the
##   reticle just OUTSIDE the body ticks — only a headshot flash (0.25 s) briefly crosses it, tolerable
##   because the ring is TRANSIENT (invisible at rest). A designer raising the radius past ~25 starts
##   kissing the aim-warning arcs.
##
## Geometry, colours, and fade knobs are HudSettings fields (resources/tuning/HudSettings.tres,
## "Stamina ring" group), read LIVE in _draw so inspector tuning shows without a scene reload. The fill
## colour ENDPOINTS (stamina_fill / stamina_low) are SHARED with the corner bar so both modes speak the
## same stamina dialect — but the ring BLENDS between them continuously with the fill level (see
## ring_color) — the corner BAR blends with the same function (one dialect); the ring draws NO track (fill arc only —
## an empty pool renders nothing; see _draw).

## Ring centre in absolute screen px — the CROSSHAIR's live centre, stamped by ui.gd each frame.
var centre: Vector2 = Vector2.ZERO
## Stamina fraction 0..1 (ui.gd stamps it from Player.stamina / stamina_max each frame).
var fill: float = 1.0
## Idle-fade multiplier on the whole ring's alpha: eases toward stamina_ring_idle_alpha while the pool
## is full (a full ring is zero-information — fade it so the crosshair area stays clean), snaps back
## toward 1.0 the moment any stamina is spent. Eased in _process, applied in _draw.
var _alpha_mult: float = 1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # never eat input (HUD gotcha, same as every overlay)

func _process(delta: float) -> void:
	if not visible:
		return
	# Frame-rate-independent ease toward the idle/active alpha (the 1 - exp idiom used HUD-wide).
	var t := 1.0 - exp(-GameSettings.hud.stamina_ring_fade_speed * delta)
	var target := alpha_target(fill, GameSettings.hud.stamina_ring_idle_alpha)
	_alpha_mult = lerpf(_alpha_mult, target, t)
	# SNAP the asymptote shut: the exp-lerp approaches its target forever without arriving, and with the
	# shipped idle alpha of 0 that residue is a permanent ghost ring at ~1% opacity — visibly NOT the
	# "fully invisible when inactive" contract. Inside a hair of the target, land exactly on it.
	if absf(_alpha_mult - target) < 0.01:
		_alpha_mult = target
	queue_redraw()  # redraw every frame — the centre tracks the live (possibly swaying) crosshair

## Pure arc math: the [from, to] angles (radians) the fill arc spans for `fill_frac` of the gauge.
## `start_deg` is where the gauge BEGINS (canvas angles: 0 = right, 90 = bottom, 180 = left, 270 = top —
## y is down); `sweep_deg` is SIGNED — the fill grows from start toward start + sweep, so one knob
## carries both the span and the direction (the default 180 / -180 sweeps left -> bottom -> right,
## a half-ring gauge hugging the underside of the reticle). Static so tests pin it off-tree.
static func arc_angles(fill_frac: float, start_deg: float, sweep_deg: float) -> Vector2:
	var from := deg_to_rad(start_deg)
	return Vector2(from, from + deg_to_rad(sweep_deg) * clampf(fill_frac, 0.0, 1.0))

## Pure colour blend: a CONTINUOUS gradient from the full colour (blue) toward the low colour (yellow)
## as the pool drains — the colour IS the fill level, with no threshold snap. Shared by BOTH stamina
## modes (the ring here; the corner bar via ui.gd _update_stamina_bar — user call), so the
## stamina_fill / stamina_low endpoints recolour the whole dialect at once.
static func ring_color(fill_frac: float, fill_col: Color, low_col: Color) -> Color:
	return low_col.lerp(fill_col, clampf(fill_frac, 0.0, 1.0))

## Pure idle-fade target: a full pool rests at the faint idle alpha, anything less pops to fully lit.
static func alpha_target(fill_frac: float, idle_alpha: float) -> float:
	return idle_alpha if fill_frac >= 0.999 else 1.0

## Pure outline-span pad: widen the fill arc's angular span by `pad_rad` on BOTH ends, respecting the
## sweep's direction — so the outline caps the arc's TIPS as well as its long edges (a same-span outline
## under a wider stroke leaves the two ends bare). `span` is arc_angles' (from, to); to < from on a
## negative sweep, so the pad extends outward along whichever way the arc runs.
static func outline_span(span: Vector2, pad_rad: float) -> Vector2:
	var s := 1.0 if span.y >= span.x else -1.0
	return Vector2(span.x - s * pad_rad, span.y + s * pad_rad)

func _draw() -> void:
	if _alpha_mult <= 0.001:
		return  # fully faded (idle at the shipped 0 alpha) — draw nothing at all, not arcs at alpha 0
	var hud: HudSettings = GameSettings.hud
	# Point density scales with the sweep so a designer widening the gauge keeps a smooth curve.
	var points := maxi(8, int(ceilf(absf(hud.stamina_ring_sweep_deg) / 6.0)))
	# FILL ARC ONLY — no track/backing behind it (user call): the arc's LENGTH is the gauge, and a dark
	# full-sweep backing read as a black ring stamped around the crosshair. Consequences owned on purpose:
	# a fully-drained pool renders NOTHING (the moment of maximum "you have no stamina" shows an empty
	# reticle — the colour gradient warns well before that), and the gauge's extent is only visible while
	# draining, which is exactly the ambient read the ring is for.
	if fill > 0.001:
		var span := arc_angles(fill, hud.stamina_ring_start_deg, hud.stamina_ring_sweep_deg)
		var col := ring_color(fill, hud.stamina_fill, hud.stamina_low)
		col.a *= _alpha_mult * hud.stamina_ring_alpha
		# Contrast outline UNDER the fill: a wider dark arc, angular span padded so the tips are capped
		# too (outline_span). Only ever drawn beneath the LIVE fill span — the no-track contract holds.
		if hud.stamina_ring_outline_width > 0.0:
			var oc := hud.stamina_ring_outline_color
			oc.a *= _alpha_mult * hud.stamina_ring_alpha
			var pad := hud.stamina_ring_outline_width / maxf(hud.stamina_ring_radius, 1.0)
			var ospan := outline_span(span, pad)
			draw_arc(centre, hud.stamina_ring_radius, ospan.x, ospan.y, points,
					oc, hud.stamina_ring_thickness + hud.stamina_ring_outline_width * 2.0, true)
		draw_arc(centre, hud.stamina_ring_radius, span.x, span.y, points, col, hud.stamina_ring_thickness, true)
