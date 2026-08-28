class_name HudSettings
extends Resource

## HUD look + feel: colours, sizes, fonts, and timings for the segmented HP bar, the crosshair stamina
## ring (+ its corner-bar accessibility fallback), the diegetic HUD-weight sway, the money readout, the
## reputation/notification toasts, the crosshair, the centre-screen prompts/meters, the top-centre enemy
## health bar, and the hotbar — all on ONE inspector page (resources/tuning/HudSettings.tres), read as
## GameSettings.hud.<field> by ui.gd, stamina_ring.gd, player_hud.gd, enemy_health_bar.gd, and hotbar.gd.
## These are AUTHOR-TIME numbers (a global tuning group, not
## a player-facing Options row — though the "Stamina ring" mode and the "HUD weight" strength each have a
## matching Accessibility row in SettingsCatalog.tres that gates/scales them at runtime).

@export_group("General")
## The big centred HUD message font (interaction prompts etc.).
@export var hud_font_size: int = 32
## Reticle box size (px); a shader discs it.
@export var crosshair_size: Vector2 = Vector2(4, 4)
## Hide the reticle whenever the weapon is HOLSTERED (FNV/Deus Ex: nothing is aimed, so nothing annotates
## the aim point). The player still spawns holstered, so this is what the game OPENS on. Everything else
## about bare-handed play is untouched — the interaction ray, the look-at name readout under the reticle
## and the talk/pickup prompts all still work; only the dot goes away. OFF restores the old permanent
## reticle. Composed with the dialogue hide in ui.gd's _apply_crosshair_visibility (the single writer).
@export var hide_crosshair_when_holstered: bool = true
## ...but a prop in your HANDS is an aimed thing: a carried Throwable launches straight down the look ray
## (left-click / Z release), so the reticle IS its aim point even though the weapon underneath is holstered
## and draw-locked ("no gun while your hands are full", Player._on_carry_changed). ON re-shows the dot for
## the whole carry — a world-grabbed crate, a hotbar-pulled prop, or your own weapon taken into hand with
## DropHeld (H) — and it OVERRIDES the holster hide above, because the holster here is a side effect of
## carrying rather than a "nothing is aimed" state. OFF leaves carrying to follow the holster rule.
## Dialogue still wins over both (talking isn't an aiming moment).
@export var show_crosshair_while_carrying: bool = true
## Bottom-left clip/reserve ammo readout font (ui.gd) — NOT hud_font_size (that stays the big centred
## message font).
@export var ammo_font_size: int = 18
## Clip fraction at/below which the ammo readout warns.
@export var ammo_low_frac: float = 0.25
## Warning tint for a nearly-empty clip (hp_seg_low family).
@export var ammo_low_color: Color = Color(1.0, 0.45, 0.35)

@export_group("HP bar")
## One HP segment, w x h.
@export var hp_seg_size: Vector2 = Vector2(26, 16)
## Pixels between segments.
@export var hp_seg_gap: float = 3.0
## Bar-cluster origin: x in from the left edge, y up from the bottom to the TOP of the HP segments.
## The stack hangs DOWN from here — HP segments (hp_seg_size.y), stamina_bar_gap, stamina track
## (stamina_bar_size.y) — so at the defaults the cluster keeps a 4 px bottom margin, hugging the corner
## like the hotbar's (4, 4) inset; x = 8 sits on the same left rail as the money/rep readouts. The ammo
## line rides ABOVE the segments and ui.gd derives its band from this same inset, so this one knob moves
## the whole bottom-left cluster.
@export var hp_bar_inset: Vector2 = Vector2(8, 29)
## A drained segment. NEAR-OPAQUE on purpose: at 0.55 alpha the drained segments vanished against dark
## scenes, so a damaged bar read as SHORTER than the stamina bar under it (screenshot QA) — the track must
## always be visible for the pair to read as one gauge.
@export var hp_seg_empty: Color = Color(0.16, 0.05, 0.06, 0.9)
## Live HP (bright red).
@export var hp_seg_fill: Color = Color(0.86, 0.16, 0.16, 0.96)
## Glows hotter with one segment of HP left.
@export var hp_seg_low: Color = Color(1.0, 0.32, 0.22, 1.0)
## Total width budget (px) of the whole segmented HP bar at ANY max HP (ui.gd) — segments shrink, then
## consolidate (one drawn cell = >1 HP) to fit; the bar never grows past this. 232 seats the default
## 8-segment look whole. Tip: set stamina_bar_size.x equal to this to edge-align the two bars.
@export var hp_bar_max_width: float = 232.0
## Narrowest drawable segment (px); below this the bar stops adding segments and consolidates.
@export var hp_seg_min_width: float = 4.0

@export_group("Stamina bar")
## Size of the slim stamina bar tucked under the HP segments.
@export var stamina_bar_size: Vector2 = Vector2(116, 6)
## Pixels between the HP segments and stamina bar.
@export var stamina_bar_gap: float = 3.0
## Drained stamina backing colour.
@export var stamina_empty: Color = Color(0.04, 0.12, 0.16, 0.65)
## Filled stamina colour.
@export var stamina_fill: Color = Color(0.18, 0.75, 0.95, 0.92)
## Fill colour once stamina is nearly exhausted.
@export var stamina_low: Color = Color(0.95, 0.78, 0.25, 1.0)

@export_group("Stamina ring")
# The SHIPPED stamina readout: an arc around the crosshair (scripts/ui/stamina_ring.gd), so stamina is
# readable without leaving the aim point. The corner bar above stays the accessibility fallback
# (Options -> Accessibility -> "Crosshair Stamina Ring" OFF). The ring draws the FILL ARC ONLY (no
# stamina_empty track — an empty pool renders nothing) and BLENDS stamina_fill -> stamina_low
# continuously with the level — and so does the corner BAR (both call StaminaRing.ring_color; the old
# stamina_low_frac snap threshold is deleted). Shared endpoints keep one stamina dialect.
## Ring radius (px) from the crosshair centre. 14 hugs the reticle (user call: the old
## thread-the-combat-annulus 23 read as TOO BIG): outside the ordinary hit ticks' ~11 px pop reach, so
## only a headshot flash (~21 px, 0.25 s) briefly sweeps across — acceptable now the ring is TRANSIENT
## (invisible at rest, fill-arc only). Keep radius+thickness/2 under ~25 or it collides with the red
## aim-warning arcs (inner edge ~25) that share this centre.
@export var stamina_ring_radius: float = 14.0
## Stroke width of the ring (px). Thin — it's ambient status, not an alarm; at radius 14 a fat stroke
## reads as a second crosshair.
@export var stamina_ring_thickness: float = 2.0
## Where the gauge STARTS, in canvas degrees (y-down: 0 = right, 90 = bottom, 180 = left, 270 = top).
@export var stamina_ring_start_deg: float = 180.0
## SIGNED sweep (degrees): the fill grows from start toward start + sweep, so this one knob carries
## span AND direction. The default 180 / -180 pair sweeps left -> bottom -> right: a half-ring gauge
## hugging the underside of the reticle, filling left-to-right like a meter.
@export var stamina_ring_sweep_deg: float = -180.0
## Alpha multiplier the ring rests at while stamina is FULL (a full ring carries no information; any
## spend pops it back to 1). SHIPPED at 0 — fully invisible at rest, the crosshair area stays completely
## clean (user call: "fully invisible when inactive"); raise it for a faint always-on ghost ring.
@export var stamina_ring_idle_alpha: float = 0.0
## Ease rate (1 - exp idiom) for the idle fade in/out; higher = snappier.
@export var stamina_ring_fade_speed: float = 6.0
## HOLD (seconds) the ring stays fully lit AFTER the pool tops back up before the idle fade begins — a
## split-second linger so recovering to full registers instead of the gauge vanishing the instant the last
## point returns (user call, "delay fading out for a split second after you get back to full stamina").
## The hold only counts a refill the player WATCHED: it is cleared on an adopted frame (revive / level
## load / bar-mode swap), so a full pool that appears off-screen still lands straight on the idle alpha with
## no linger (the same contract stamina_ring's _fade_primed latch enforces). 0 = fade the instant you hit full.
@export var stamina_ring_full_hold: float = 0.4
## Base opacity of the ring's fill arc (the idle fade multiplies ON TOP of this) — the ring reads as a
## translucent annotation over the world rather than solid paint at the aim point (user call). The
## outline rides the same multiplier so the rim never overpowers a faded fill, so this ONE knob carries
## the whole gauge's transparency. Taken 0.6 -> 0.4 on a second user call ("make the stamina bar more
## transparent"), in the same pass that dropped the aim cluster out of the HUD ghost (ui.gd _build_ghost
## rule 4) — both asks are the same ask: keep the aim point clean. Much below ~0.3 the arc stops reading
## over a bright scene even with its outline under it.
@export var stamina_ring_alpha: float = 0.4
## Outline width (px, EACH side of the stroke) drawn under the fill arc — the contrast rim that keeps a
## thin 2px arc legible over bright/dithery scenes. 0 = no outline.
@export var stamina_ring_outline_width: float = 1.0
## Outline colour (fades with the ring's idle alpha).
@export var stamina_ring_outline_color: Color = Color(0.0, 0.0, 0.0, 0.9)

@export_group("HUD weight")
# Diegetic HUD sway (scripts/ui/hud_sway.gd, driven per frame in ui.gd): the corner HUD cluster —
# HP/stamina bars, ammo, money, toasts, quest tracker, hotbar — trails camera turns on a damped spring
# and settles, reading as an instrument panel with mass. The crosshair + stamina ring CAN ride the SAME
# spring at hud_sway_aim_scale, but that knob ships at 0 (pinned reticle — see that knob); the look-name
# label stays pinned too. TWO channels feed the one spring: every ROTATIONAL
# camera behaviour (mouse look, trauma shake from guns/blasts/ram bounces) is MEASURED off the camera
# basis and needs no wiring here, while POSITIONAL impacts the basis can't see (the landing dip) arrive
# as discrete velocity kicks (ui.hud_land -> hud_land_kick below). The player scales the whole effect
# 0..1 (motion comfort) via Options -> Accessibility -> "HUD Sway" (Settings.hud_sway_scale); these
# knobs are the AUTHORED full-strength feel that scale multiplies.
## Px of panel displacement per rad/s of look speed (x = yaw, y = pitch). Positive trails the turn;
## flip a component's sign if the drift reads backwards on a future camera rig.
@export var hud_sway_gain: Vector2 = Vector2(2.6, 2.2)
## Hard cap (px) on the sway displacement — a violent flick parks the panel here, never off-screen.
## Keep it SMALL (the 792x444 canvas magnifies ~2.4x): >12 px starts reading seasick, not weighty.
@export var hud_sway_max: float = 8.0
## Fraction of the panel's spring offset the AIM CLUSTER (crosshair + stamina ring) rides — the same
## spring, so reticle and panel would share ONE mass and one settle, at a whisper of the amplitude.
## SHIPPED AT 0 (user call, 2026-08-26 "remove the sway on the crosshair"): the reticle is the aim
## reference and any motion there reads as aim error, not weight, so it stays classic fully-pinned to
## screen centre while the corner panel still trails. Raise toward ~0.12 (≈1px of an 8px max) to let a
## whisper of the panel's weight reach the reticle again; keep it well under 0.5 (see the test) — large
## reticle motion reads as aim error. Inherits the Accessibility "HUD Sway" scale for free (the offset
## it samples is already scaled), so at 0 the aim cluster is pinned regardless of that slider.
@export var hud_sway_aim_scale: float = 0.0
## Spring stiffness (accel per px of error). Higher = the panel snaps to its lag position faster.
@export var hud_sway_stiffness: float = 70.0
## Spring damping (accel per px/s of velocity). With stiffness 70, damping 12 lands ~0.72 damping
## ratio — slightly under-damped so release settles with ONE small overshoot (the "mass" read);
## raise toward ~17 (critical) for a dead-flat return.
@export var hud_sway_damping: float = 12.0
## Downward velocity kick (px/s) the panel takes on a FULL-intensity landing (ui.hud_land — the discrete
## impact channel; rotational events like screen shake ride the continuous channel for free and need no
## knob here). With the shipped 70/12 spring a kick of v peaks at ~0.044*v px of dip (60 fps sim; the
## continuous-limit ceiling is ~0.054*v) — so 110 lands a ~5 px full-slam dip, inside the hud_sway_max
## ethos. Scales linearly with the landing's crouch-softened intensity, so a soft hop barely nods the panel.
@export var hud_land_kick: float = 110.0
## Hard cap (px/s) on ANY single impact kick, whatever its source or tuning — the impulse-channel twin
## of hud_sway_max. 150 peaks at ~6.6 px; caps BEFORE the accessibility scale (see HudSway.kick_scaled).
@export var hud_kick_max: float = 150.0
## Px of panel lean per m/s of BODY motion (x = lateral strafe, y = vertical). Strafing leans the panel
## against the motion; a jump presses it down and a fall floats it up (the land kick then thuds it).
## At max_speed 5 a full strafe leans ~2.3 px; a 12 m/s fall floats ~3.6 px. Sums with the look-rate
## target under the ONE hud_sway_max cap — velocity lean never buys extra travel on top of a flick.
## Forward speed is deliberately unmapped (no honest 2D direction) — the FOV scale below tells it.
@export var hud_vel_gain: Vector2 = Vector2(0.45, 0.3)
## Panel SCALE delta per fraction-of-rest FOV change — the "lens breath" (HudSway.fov_scale_target):
## dynamic-FOV kicks (fall/rise, forward-run, sprint, dash punch) shrink the panel toward screen centre
## as the lens widens, like something in the world rather than ink on it. 0.1 = a +20% FOV dash punch
## shrinks the panel ~2%. ADS scope + dialogue zoom are gated out entirely (they OWN fov; the panel
## must not sit shrunk for a whole scoped hold). 0 = lens-breath off.
@export var hud_fov_scale_gain: float = 0.1
## Hard cap on the lens-breath scale delta (fraction; 0.04 = the panel never leaves 96%..104%).
@export var hud_fov_scale_max: float = 0.04

@export_group("HUD ghosting")
# CRT phosphor persistence for the HUD (scripts/ui/hud_ghost.gd, driven per frame in ui.gd). The HUD's own
# canvas is rendered a SECOND time into a never-cleared offscreen buffer that is multiplied down a little
# each frame; that buffer is drawn BEHIND the live HUD, so anything that moves or changes drags a soft
# tail and anything that sits still is hidden exactly behind itself. Two knob families: PERSISTENCE (how
# strong + how long the tail is) and LATENCY (how far the ghost image lags the live HUD while the camera
# turns — the half that makes the screen-locked RETICLE participate, since a static image has no tail).
# The player scales the whole effect 0..1 via Options -> Accessibility -> "HUD Ghosting"
# (Settings.hud_ghost_scale); these are the AUTHORED amplitudes that dial multiplies.
## How strongly the accumulated ghost is composited behind the HUD, 0..1. This is the master amplitude:
## 0 shuts the whole effect down (the offscreen pass stops rendering entirely, so OFF is free), and the
## HUD is then pixel-identical to a build without this feature. 0.32 reads as a soft echo rather than a
## double image — push past ~0.5 and moving readouts start to look like they are printing twice.
@export_range(0.0, 1.0, 0.01) var hud_ghost_strength: float = 0.32
## Persistence time constant (seconds): the buffer loses 1/e of itself every tau, so the tail is the same
## LENGTH at 30 fps and at 144 (the decay is exp(-delta/tau), not a per-frame constant). 0.10 is roughly
## a 5-frame visible tail at 60 fps. Longer smears the corner panel into a comet under heavy shake;
## shorter collapses toward no effect at all. 0 = no persistence (the buffer is wiped every frame).
@export_range(0.0, 0.6, 0.005) var hud_ghost_tau: float = 0.13
## Px of ghost LAG per rad/s of camera look rate (x = yaw, y = pitch). This is what makes the reticle
## ghost: it is welded to screen centre, so persistence alone would never show on it — instead the whole
## captured HUD is drawn a couple of pixels behind where it actually is while you turn, and the
## persistence smears that offset into a tail. Signs match HudSway.look_target: the ghost trails the turn.
@export var hud_ghost_drag_gain: Vector2 = Vector2(1.7, 1.4)
## Hard cap (px) on that lag, before the player's 0..1 dial scales it. THE SUBTLETY KNOB: 3 px on the
## 792-wide canvas is ~7 screen px at 1080p — visible as motion smear on a flick, invisible when standing
## still (the offset returns to zero and the ghost hides behind the live HUD). Set 0 for pure persistence
## with no double vision at all; past ~6 the reticle starts reading as two reticles mid-turn.
@export_range(0.0, 12.0, 0.5) var hud_ghost_drag_max: float = 3.0
## Seconds for the lag to close 1/e of the gap to its target. A first-order lag, NOT the panel's spring:
## the panel is under-damped on purpose so it settles with one overshoot (that sells mass), but an image's
## latency has no mass and an overshoot here reads as the ghost oscillating around a still reticle.
@export_range(0.0, 0.4, 0.005) var hud_ghost_drag_response: float = 0.045
## Alpha subtracted from the ghost at DISPLAY time to kill the 8-bit decay residue. An RGBA8 buffer
## multiplied by d each frame has a fixed point — once round(n*d) == n the value never falls again (~8/255
## at a typical d) — so without this cut every place the HUD has ever been keeps a permanent faint smear.
## Raise it if a stale outline ever survives; lower it to let the tail's last few steps live longer.
@export_range(0.0, 0.5, 0.005) var hud_ghost_residue_floor: float = 0.06

@export_group("HUD curve")
# CURVED GLASS. The corner instrument panel is rendered into a SubViewport and composited back through
# resources/shaders/hud_curve.gdshader's cylindrical warp (ui.gd `_apply_hud_curve`), so the panel wraps
# TOWARD you at its edges like the inside of a curved monitor. Same CRT fiction as the ghosting group, and the
# same scope: an INSTRUMENT READOUT curves; the reticle, the stamina ring, the combat arcs and every other
# screen-projected annotation stay dead flat, because they annotate the aim point or a world bearing and a
# warped one would lie. ui.gd's moved-vs-pinned rule already draws exactly that line, so this reuses it
# rather than inventing a second list -- whatever rides the `_weighted` carrier curves, nothing else does.
# AUTHOR-TIME numbers: the player-facing dial is Options -> Accessibility -> "HUD Curve"
# (Settings.hud_curve_scale, polled live), which SCALES hud_curve_amount 0..1 -- the ps1_warp_intensity
# idiom, so this knob is the ceiling and the player picks how much of it they want.
## How far the panel bends, as the fraction of the half-canvas its EDGE MIDPOINTS travel. The bend is
## CONCAVE -- the panel wraps toward you at its edges, the inside of a curved monitor -- and it is FITTED,
## meaning the corners are pinned to the screen corners and the edges bow inward from them. Nothing can
## ever be pushed off the canvas, so this is safe to crank. At 0.08 the bottom-centre content rides ~18 px
## up on the 792x444 canvas; past ~0.2 the panel stops reading as a screen and starts reading as a tube.
@export_range(0.0, 0.3, 0.005) var hud_curve_amount: float = 0.08
## How much the OTHER axis bends too, as a fraction of hud_curve_amount.
## 0 = a monitor curved about a VERTICAL axis (the shipped look): horizontal lines bow, and every vertical
##     stays dead straight -- the plain curved-ultrawide silhouette.
## 1 = SPHERICAL: both axes bow at once, which reads as an eye or a fishbowl rather than a monitor.
## Anything between mixes them; above 1 the verticals bow MORE than the horizontals, which looks wrong on a
## canvas this wide but is left reachable rather than clamped away.
@export_range(0.0, 2.0, 0.05) var hud_curve_axis_ratio: float = 0.0
## Alpha lost toward the bent edge as the panel turns away from the light -- full strength in the corners,
## half at the edge midpoints. Small on purpose: this sells the curve as a SURFACE, and a heavy value just
## dims the HP bar in the exact corner it lives in. 0 = an evenly lit panel.
@export_range(0.0, 1.0, 0.01) var hud_curve_edge_fade: float = 0.12
## Lens fringe at the bent edges, as a FRACTION OF THE WARP (so it grows with hud_curve_amount instead of
## fighting it). OFF BY DEFAULT: the three taps are recombined in premultiplied space, so it fringes the
## anti-aliased edge of every glyph as well as the colour, and on a text-heavy panel that reads as blur
## before it reads as chromatic aberration. Worth trying only alongside a LOW hud_curve_amount.
@export_range(0.0, 1.0, 0.01) var hud_curve_chroma: float = 0.0

## How far the ghost's colour is replaced by the skin's age ramp (HudSkin.ghost_gradient), 0..1. 0 = the
## trail is a dimmed copy of whatever colour the HUD element is; 1 = pure ramp, so a red HP bar and a gold
## money readout leave the SAME coloured trail and the ghost reads as one signal artefact rather than as
## smudged UI. 0.85 keeps a whisper of the source so a trail still belongs to the thing that cast it.
@export_range(0.0, 1.0, 0.01) var hud_ghost_tint: float = 0.85
## Gamma on the trail's displayed alpha — the knob that decides whether the ramp's COLD end is ever seen.
## The buffer's alpha IS the trail's age, and it decays exponentially, so at gamma 1 the oldest third of
## the tail is too faint to show any colour at all and the gradient is wasted. Below 1 lifts that tail
## (0.65 roughly doubles the presence of a 10%-alpha pixel); above 1 crushes it back toward the fresh end.
@export_range(0.15, 2.0, 0.05) var hud_ghost_tail_lift: float = 0.55

@export_group("Money readout")
@export var money_font_size: int = 16
@export var money_delta_font_size: int = 15
## Gold for the persistent zorkmid readout.
@export var money_color: Color = Color(1.0, 0.86, 0.3)
## Green +N on a gain.
@export var money_gain_color: Color = Color(0.45, 1.0, 0.5)
## Red -N on a spend.
@export var money_loss_color: Color = Color(1.0, 0.5, 0.4)
## Red the persistent readout wears while the wallet is NEGATIVE (implants are bought on credit — the run
## can start in debt, and the signed readout IS the debt display). Solvent stays money_color gold. The
## menu wallet labels tint the same state through MenuStyle.wallet_color (MenuSkin.danger_color).
@export var money_debt_color: Color = Color(1.0, 0.5, 0.4)
## Pixels the +N/-N floats up as it fades.
@export var money_delta_rise: float = 22.0
## Seconds for that float + fade.
@export var money_delta_time: float = 0.8

@export_group("Toasts")
## Seconds a toast holds before fading.
@export var rep_toast_hold: float = 2.5
## Fade-out duration.
@export var rep_toast_fade: float = 1.0
@export var rep_toast_font_size: int = 10
## Neutral (no-change) toast text colour. Gain/loss colours are NOT knobs here — they come from CBPalette
## (scripts/ui/cb_palette.gd), which swaps to a colorblind-safe pair when Settings.colorblind_safe_cues is on.
@export var rep_neutral_color: Color = Color(0.85, 0.85, 0.85)
## New-quest announcement toast tint (ui.gd). Quest complete/failed colours are deliberately NOT knobs —
## directional gain/loss feedback routes through CBPalette, same contract as the rep toasts above.
@export var quest_toast_color: Color = Color(0.7, 0.9, 1.0)
## Top-right objective tracker line tint (ui.gd).
@export var quest_tracker_color: Color = Color(0.85, 0.95, 1.0)
## Px column budget for the top-right tracker (English-measured; long lines wrap downward).
@export var quest_tracker_width: float = 300.0
## Amber save-load caveat toast (ui.gd).
@export var load_warning_color: Color = Color(1.0, 0.7, 0.3)

@export_group("Minimap")
# The shipped top-right HUD minimap (scripts/ui/minimap.gd, an AUTHORED SCENE — scenes/ui/hud_minimap.tscn —
# instanced by ui.gd). A procedural VECTOR
# floorplan: the walkable navmesh fill for the player's own floor band, plus a section cut of the level's
# STATIC colliders at chest height. No authored texture, no per-level MapData, no second 3D pass — and a
# canvas item cannot be touched by ps1.gdshader's vertex snap, so the plan is immune to the warp.
# WHAT IS LEFT IN THIS GROUP, after the 2026-08-19 split: the numbers that decide which GEOMETRY the map
# gathers and where the box sits — not how any of it is inked. Every PAINT knob (each colour AND the
# width/size of the thing it colours: wall stroke + its optional glow, rim, the four marker sizes, glyph
# stroke, alert-ring gap/step, off-floor tick + fade, north tick, rim-pin margin) now lives together on
# MenuStyle.hud -> resources/ui/hud_skin.tres, so an artist changing the look never has to open a tuning
# resource full of navmesh numbers. THE RULE: looks -> the skin; does -> here or the scene.
# The player-facing on/off, rotate mode and zoom are Options -> Accessibility rows (Settings.minimap_*,
# polled live), and the per-channel draw switches are the widget's own inspector in hud_minimap.tscn.
# THE TIGHT ONE: this corner is SHARED — it is a three-row stack (map, then the "Clock" group below, then
# the quest tracker, whose quest_tracker_width column starts at x 484 on the 792x444 canvas and WRAPS
# DOWNWARD with no bound). ui.gd derives EACH row's top from the row above it (hud_clock_top_for /
# quest_tracker_top_for), so these knobs move the whole stack together; with the clock switched off the
# tracker falls back to minimap_inset.y + minimap_size.y + minimap_tracker_gap exactly as it always did.
# Keep minimap_inset.x + minimap_size.x <= 8 + quest_tracker_width (pinned by a test) or the
# enemy-health-bar clearance maths in tests/test_enemy_health_bar.gd stops bounding this corner.
## Drawn map box, w x h px. WHOLE pixels — fractional sizes rasterize into a ragged comb under the 792x444
## canvas's ~2.4x nearest upscale (the same trap ui.gd's hp_display_seg_width note documents).
##
## THE BOX ITSELF IS AUTHORED NOW, in scenes/ui/hud_minimap.tscn's root offsets — ui.gd measures it back out
## through UI.minimap_box() and reflows the clock and the tracker off THAT. These two knobs are the FALLBACK
## box (no widget: a bare UI in a test, a failed instantiate) and the numbers the shipped scene was authored
## from, which is why every clearance rule above is still pinned against them. Move the box in the editor and
## you MUST mirror it here; tests/test_minimap_scene.gd fails when the two stop describing one rectangle.
@export var minimap_size: Vector2 = Vector2(108, 108)
## Inset from the canvas's TOP-RIGHT corner: x in from the right edge, y down from the top. Authored in the
## scene as the root's offsets (right = -inset.x, top = inset.y) — see minimap_size.
@export var minimap_inset: Vector2 = Vector2(8, 8)
## Px between the map box's bottom edge and the quest tracker's first line.
@export var minimap_tracker_gap: float = 6.0
## Where the quest tracker's top sits when the minimap is OFF. Ships as 8.0 = byte-identical to the
## pre-minimap layout, so turning the map off in Options restores the historical corner exactly rather than
## leaving a hole where it used to be.
@export var minimap_tracker_bare_top: float = 8.0
## true = the map rides ui.gd's _weighted HUD-weight carrier (corner readouts carry mass — the header's
## moved-vs-pinned rule). false = welded to the CanvasLayer. THE ESCAPE HATCH: the carrier also writes a
## +-4% lens-breath SCALE, and a non-integer scale on 1 px vector strokes can shimmer under the nearest
## upscale. Flipping this costs no behaviour — a direct layer child is still swept by hide_hud_for_death.
@export var minimap_rides_hud_weight: bool = true
## World metres across the box's SHORT axis at zoom 1.0. 40 m over 108 px = 2.7 px/m, so a 3 m corridor
## draws ~8 px wide — about the narrowest that still reads at this canvas size.
@export var minimap_world_span: float = 40.0
## Section-cut plane, metres above the player's ORIGIN. Chest height cuts through walls and doorways but
## under most desks and railings, which is what makes a plan read as rooms.
@export var minimap_cut_height: float = 1.2
## One cached deck's vertical validity — the navmesh band filter, the deck cache key's quantum, AND the
## marker cross-floor fade denominator. One number so a floor can never mean three different heights.
@export var minimap_band_height: float = 2.6
## How far CLEAR of the current floor band the player must get before the map redraws as a different storey.
## Without it the whole plan flips the instant the reference height crosses a boundary, and a stair riser, a
## kerb or a gentle slope is enough to make it flip back and forth. (JUMPING is fixed at the root instead —
## the widget keys off the last GROUNDED height, not live altitude, so leaving the ground cannot change which
## floor you are shown.) Ships above one 0.5 m stair riser, so a single step near a boundary does not swap it.
@export var minimap_band_hysteresis: float = 0.6
## Reject the Quake "void seal" — a worldspawn brush enclosing the whole map cuts to one giant rectangle
## that would draw a frame around every room. A cut ring wider than this on BOTH axes is dropped.
@export var minimap_max_solid_span: float = 120.0
## Reject micro-detail (trim, sign backers, pipe collars) that reads as speckle at ~2.7 px/m.
@export var minimap_min_solid_span: float = 0.35
## Draw the wall layer as ONE SILHOUETTE rather than a stack of outlines: where two solids overlap (or abut),
## the sides buried inside the neighbour are dropped, so a room built from four wall brushes prints as a room
## instead of four rectangles crossing at the corners. A level is BUILT from overlapping boxes; a floorplan is
## not DRAWN as one. Off = every solid draws its own closed ring — the original look, and the escape hatch if
## a level's brushwork actually wants those seams. Costs nothing per frame: it runs inside the per-floor bake.
@export var minimap_merge_solids: bool = true
## How far apart (metres) two solids may be and still count as ONE for the merge above. NONZERO IS THE POINT:
## brushes that share a face exactly are the normal case, and an edge lying precisely ON its neighbour's
## boundary survives any clipper (verified against 4.7.1), so only a tolerance makes a shared face cancel from
## BOTH sides. Only the hidden-line TEST is grown — every stroke drawn is the solid's own untouched cut — and
## at the shipped 2.7 px/m this is ~0.14 px, far under one pixel. 0 = exact overlaps only.
@export var minimap_merge_weld: float = 0.05
## Metres of player motion before a repaint — a standing, still player costs literally zero.
@export var minimap_redraw_pos_eps: float = 0.02
## Radians of turn before a repaint (the other half of the same idle gate).
@export var minimap_redraw_yaw_eps: float = 0.004

# MARKER GLYPHS. Markers paint AFTER the view matrix is reset, so every px below is a real screen pixel and a
# glyph is zoom-invariant by construction (walls and floor fill scale with zoom; markers never do). The SHAPE
# vocabulary itself is pure maths in scripts/ui/map_glyph.gd — these are only its sizes.
# ⭐WHOLE-ISH PIXELS. The 792x444 canvas is nearest-upscaled ~2.4x, so a glyph sized in fractions rasterizes
# into a lopsided blob. Half-pixel steps survive; finer ones do not.
## THE SCANNER RIM, in metres: how deep a band at the edge of a scanner implant's reach fades body dots out
## over. The REACH itself is not here — it is authored per chip on the scanner ability scenes (BioScanner 22 m,
## DeepScanner 55 m), because the number you bought is what the tier means; this is only how the edge of it is
## drawn, which is presentation and shared by every tier.
##
## WHY A BAND AT ALL. A hard clip makes a walking body's dot blink in and out at a fixed radius, which reads as
## the map glitching rather than as the scanner reaching its limit — and on the 120 m Map tab the rim can sit
## well inside the drawn view, so there is nothing else on screen to explain the pop. A ramp says "signal, and
## it is running out". 0 = the hard clip back, for a designer who wants the harsher read.
@export var minimap_scan_fade_m: float = 3.0
## Zoom steps the "Cycle Minimap Zoom" key walks through, in order, wrapping at the end. Each is the same
## multiplier Options -> Accessibility -> "Minimap Zoom" sets, so the key and the slider write ONE value
## (Settings.minimap_zoom) and can never disagree. Values outside Settings.MINIMAP_ZOOM_MIN/MAX are clamped by
## the setter; an EMPTY list disables the key entirely.
@export var minimap_zoom_steps: PackedFloat32Array = PackedFloat32Array([1.0, 1.5, 2.25])

# THE MAP TAB (scripts/ui/map_screen.gd — the sixth Pip-Boy tab, default M) draws the SAME widget at panel
# size, so everything above still applies to it: the cut height, band height, solid-span rejects, merge and
# the zoom steps are shared, and every colour still comes off MenuStyle.hud. Only the four numbers below are
# its own, because they are the ones the corner box can't answer for a full-screen read: how much WORLD a
# page-sized map should show, how far one wheel notch moves it, and how far off the player the view may be
# DRAGGED. Its heading is forced NORTH_UP and its zoom lives on Settings.map_zoom (the Options → Accessibility
# "Map Zoom" row) — both authored on the widget's own "Instance view" exports in scenes/ui/map_screen.tscn,
# not here.
## World metres across the MAP TAB's short axis at zoom 1.0. Three times the corner box's span: the panel is
## ~3x taller than the 108 px box, so this lands at a similar px/m while showing a district instead of a room.
## The player's Map Zoom row divides it (0.5x–3.0x = 240 m out to 40 m in, the corner box's own span at 3x).
@export var map_world_span: float = 120.0
## How much one mouse-wheel notch moves the map tab's zoom. The wheel is the map's primary zoom affordance
## (the footer's two buttons are the pad/keyboard path and step by the same amount), so this is the feel knob:
## bigger crosses the 0.5–3.0 range in fewer notches. Clamped at the ends by Settings.set_map_zoom.
@export var map_zoom_wheel_step: float = 0.25
## HOW FAR THE MAP TAB MAY BE PANNED off the player, in world metres — the clamp the map screen puts on
## Minimap.view_offset.length() as the player drags the plan (or walks it with the movement keys / stick).
##
## WHY PANNING EXISTS AT ALL: the widget is player-CENTRED by construction, so before this the reachable world
## was whatever the zoom floor showed — Settings.MINIMAP_ZOOM_MIN (0.5) over map_world_span (120) is 240 m
## around the player, which is a plaza on a district map and made the far half of a level literally unviewable.
## 400 m is about a district's diagonal here. Panning past where the level is BAKED is honest rather than
## broken: the plan simply runs out, because there is nothing out there to draw.
##
## ⭐It is a LEASH, not a boundary: the pan is an offset from the player, so walking drags the whole window
## along. Zero pins the map back to the player and disables panning outright.
@export var map_pan_range: float = 400.0
## Keyboard / stick pan speed on the map tab, in VIEW-HEIGHTS per second — deliberately not metres per second.
## A metre rate would crawl at the zoomed-out district view and rocket at the zoomed-in room view; a rate in
## screenfuls covers the same fraction of what the player can SEE at every zoom, which is the thing their hand
## is actually steering. 0.9 walks the view just under one screenful a second, close to the feel of dragging
## it with the mouse. 0 disables the key/stick path and leaves the drag (and the pad's Place Pin button).
@export var map_pan_speed: float = 0.9

@export_group("Clock")
# The HUD time-of-day readout (scripts/ui/hud_clock.gd, code-built by ui.gd). ROW 2 OF THE TOP-RIGHT STACK:
# minimap, then this, then the quest tracker — and ui.gd derives EVERY row's top from the row above it
# (hud_clock_top_for / quest_tracker_top_for), so these knobs slide the stack instead of colliding with it.
# The clock rides whatever carrier the map does (minimap_rides_hud_weight): they read as ONE instrument
# cluster, and a clock that swayed while the map above it stood still would visibly shear.
# AUTHOR-TIME numbers only — the player-facing on/off and the 12/24-hour face are Options -> Accessibility
# rows (Settings.clock_enabled / Settings.clock_24_hour, polled live), and the tint is MenuStyle.hud.clock_color.
## The clock line's box, w x h px. WIDTH deliberately matches minimap_size.x so the right edges of the map and
## the digits line up into one column; the digits are RIGHT-aligned inside it. WHOLE pixels — a fractional box
## rasterizes into a ragged comb under the 792x444 canvas's ~2.4x nearest upscale (the minimap_size rule).
## ⭐HEIGHT MUST CLEAR THE FONT'S RENDERED LINE BOX, NOT JUST clock_font_size. A Label's minimum height is its
## ascent+descent, which for the default face at size 16 measures 21 px — so an "obviously fine" 18 was
## silently overridden to 21 by the Label, while the quest tracker below still reckoned 18 and sat 3 px closer
## than the gap said. Probe-verified in a real windowed boot; keep a few px of headroom over the font size.
@export var clock_size: Vector2 = Vector2(108, 22)
## Px between the map box's bottom edge and the clock's top. Ships tighter than minimap_tracker_gap: the clock
## is the map's caption, and the quest tracker below is the separate thing that needs the breathing room.
@export var clock_map_gap: float = 3.0
## Px between the clock's bottom edge and the quest tracker's first line.
@export var clock_tracker_gap: float = 5.0
## Where the clock's top sits when the MINIMAP is off — the minimap_tracker_bare_top role, one row up. Ships
## at 8.0 so switching the map off in Options lifts the clock into the corner rather than leaving a 114 px hole.
@export var clock_bare_top: float = 8.0
## Digit size. Bigger than the quest tracker's line on purpose: this is a glanceable instrument, not prose.
@export var clock_font_size: int = 16

@export_group("Compass")
# The TOP-CENTRE heading tape (scripts/ui/hud_compass.gd, code-built by ui.gd): the eight rose letters and
# their degree ticks sliding under a fixed index caret, plus a pip for every `compass`-group marker at its
# bearing. It is PINNED to the HUD layer and un-ghosted (a bearing that lags is a bearing that lies — the
# same standing rule the damage arcs are held to; see ui.gd's header).
# THE TIGHT ONE: this band is ROW 0 OF THE CENTRE-TOP COLUMN, and everything under it (the enemy health bar,
# then the stealth badge -> detection meter -> claim -> takedown/pet ladder) is pushed down by exactly
# compass_top + compass_size.y + compass_column_gap through UI.centre_column_top_for. So growing the tape
# SLIDES the column instead of colliding with it, and switching the compass off in Options returns the
# column to its historical offsets byte-for-byte.
# AUTHOR-TIME numbers only — the player-facing on/off is an Options -> Accessibility row
# (Settings.compass_enabled, polled live), and every colour/tick/fade is MenuStyle.hud ("Compass").
## The tape's box, w x h px, centred horizontally on the canvas. WIDTH is the instrument's precision: at the
## shipped 300 px / 120 deg span one canvas pixel is 0.4 deg, and a narrower band packs the rose letters
## tighter rather than showing less. HEIGHT must clear the three stacked rows the widget draws — ticks
## hanging from the top edge, the letter baseline (compass_label_baseline_px up from the bottom), and the
## marker chevrons seated on the bottom edge. At the shipped skin that budget is ticks/caret y 0..4, the
## letters y ~7..15, and the chevrons y 18..24 — three rows with ~3 px between them, measured from a real
## windowed capture (scripts/tools/hud_compass_qa_shots.gd), not eyeballed. WHOLE pixels: a fractional box
## rasterizes into a ragged comb under the 792x444 canvas's ~2.4x nearest upscale (the minimap_size /
## clock_size rule).
@export var compass_size: Vector2 = Vector2(300, 24)
## Px from the canvas top to the tape's RESTING top edge. Ships at 4 — hard against the top of the screen,
## the same inset the enemy health bar used to own before the compass took row 0 (user call: "closer to the
## top").
## Note what this knob is and is NOT. The tape rides the HUD-weight carrier, so it drifts UP as well as down,
## and this is the budget for the UP half — but overrunning it only CROPS the band against the screen edge,
## where overrunning compass_column_gap below COLLIDES with the enemy health bar. A crop degrades (you lose a
## few px of tick row on a hard flick, which reads as the weight effect working); a collision is a bug. That
## asymmetry is why this one is spent down to the edge and that one is not. The floor is that the instrument
## must never vanish ENTIRELY — compass_top + compass_size.y has to outlast the carrier's worst-case upward
## travel, which tests/test_hud_compass.gd pins against the live sway knobs.
@export var compass_top: float = 4.0
## Px between the tape's RESTING bottom edge and the top of the centre-top column below it (the enemy health
## bar's own track).
## ⭐THIS GAP IS A SWAY BUDGET, not breathing room, and that is why it is so much larger than it looks like
## it needs to be. The tape MOVES (it rides `_weighted`) and the column under it is PINNED, so the gap has to
## absorb the carrier's whole downward travel or the rose lands on the enemy health bar: up to hud_sway_max
## (8 px) of spring offset, PLUS the lens-breath scale pulling the band toward screen centre — at a resting
## bottom edge of 28 on the 444-tall canvas that is (222 - 28) * hud_fov_scale_max ≈ 7.8 px. 16 clears the
## bar's ink by ~3 px at the simultaneous worst case, the same margin enemy_hp_size budgets against the
## quest tracker. `tests/test_hud_compass.gd` pins it against the LIVE sway knobs, so raising hud_sway_max
## or hud_fov_scale_max fails there instead of shipping an overlap.
@export var compass_column_gap: float = 16.0
## How many DEGREES the full width of the tape shows. THE FEEL KNOB: smaller = a longer, more precise scale
## that swings fast under a flick; larger = more of the rose visible at once (at 180 you can see the bearing
## behind each shoulder). 120 shows three rose letters at rest, which is the Skyrim/Far Cry reading.
@export var compass_span_deg: float = 120.0
## Degrees between graduations. ⭐MUST DIVIDE 45 — the rose LETTERS are drawn from this same walk, so a step
## that misses the 45s (say 20) silently drops N/E/S/W off the tape entirely.
@export var compass_tick_step_deg: float = 15.0
## N/E/S/W letter size. Bigger than the intercardinals below on purpose: this is a glanceable instrument and
## the four cardinals are what a player actually navigates by.
@export var compass_font_size: int = 11
## NE/SE/SW/NW letter size — two glyphs in the same band, so it has to be smaller or the rose collides.
@export var compass_minor_font_size: int = 8
## Hide compass-group marker pips farther than this from the camera (0 = no limit, the shipped value). The
## screen-edge Compass component carries the same knob as a per-instance @export; this is the tape's copy
## because the two widgets can reasonably want different reach — the tape is a NAVIGATION instrument and a
## distant quest bearing is exactly what it is for.
@export var compass_marker_max_distance: float = 0.0

@export_group("Centre prompts")
## Shared centre-screen prompt size (ui.gd's look-at name + player_hud.gd's takedown/pet/claim cues).
@export var prompt_font_size: int = 14
## The [ HIDDEN ] badge keeps its own smaller size — persistent status, not a momentary prompt (player_hud.gd).
@export var stealth_font_size: int = 12

@export_group("Prompt meters")
## Backing colour shared by the four centre-screen bars (player_hud.gd: detection + takedown/pet/claim).
@export var meter_bg_color: Color = Color(0.05, 0.05, 0.07, 0.65)
## Fill colour of the three hold-to-act bars (takedown/pet/claim).
@export var meter_fill_color: Color = Color(0.92, 0.92, 0.95, 0.95)
## Detection-heat lerp endpoints — the detection bar's FILL warms safe -> hot as enemies notice you.
@export var detection_safe_color: Color = Color(0.55, 0.82, 0.62)
@export var detection_hot_color: Color = Color(1.0, 0.27, 0.22)

@export_group("Enemy health bar")
# The top-centre "who am I shooting" meter (scripts/ui/enemy_health_bar.gd, built by player_hud.gd): a slim
# allegiance-tinted HP bar that pops on any hit the player lands and self-expires a beat later. The FILL
# colour is deliberately NOT a knob here — it encodes the target's ALLEGIANCE, so it must swap with Options
# -> Accessibility -> "Colorblind-Safe Cues", which is CBPalette's job (the same standing exclusion as the
# rep/quest toast gain-loss colours above). The bar's TRACK reuses meter_bg_color from "Prompt meters" so the
# whole HUD speaks one meter dialect. The player can hide the bar entirely via Options -> Accessibility ->
# "Enemy Health Bar" (Settings.enemy_health_bar_enabled, polled live).
## Distance (px) from the CENTRE-TOP COLUMN's top to the TOP of the bar's TRACK — the column's own origin is
## the canvas top plus whatever the compass band above it reserves (UI.centre_column_top_for), so this stays
## the same number whether the compass is on or off. THE TIGHT ONE: the centre-top column below
## is a contiguous, outline-tight stack (stealth badge -> detection bar -> claim -> takedown/pet, ending at
## y 123) whose first ink — the [ HIDDEN ] badge's outline — reaches up to y 15. MEASURE THE RIM: the contrast
## rim below grows the painted band one px on every side, so at the default top 4 / height 8 / rim 1 the ink is
## y 3..13 and clears the badge by 2 px. Use EnemyHealthBar.ink_rect() for the real footprint — never the size
## knob alone (tests/test_enemy_health_bar.gd pins it that way). Raising the height, the rim or this offset
## eats the gap; move the badge (player_hud.gd _stealth_label offset_top) if you need more room.
@export var enemy_hp_top: float = 4.0
## Track size, w x h (the rim adds enemy_hp_outline_width on each side on top of this). Width is capped by the
## top-right quest tracker, whose column starts at x 484 on the 792-wide canvas — but that tracker RIDES THE
## HUD-WEIGHT CARRIER while this bar is pinned, so the gap has to absorb the carrier's motion: up to
## hud_sway_max (8 px) of spring travel plus the lens-breath scale pulling the column ~3.5 px toward centre.
## 144 centres the track to x 324..468 and the ink to 323..469, leaving ~3 px even at the worst-case sway.
## Anything past ~150 can kiss a wrapped objective line during a hard flick.
@export var enemy_hp_size: Vector2 = Vector2(144, 8)
## Fill tint for a target with no allegiance to read — a plain Character, or a NEUTRAL NPC. This is the
## `neutral` argument handed to CBPalette.disposition_color; hostile / friendly / companion tints come from
## CBPalette itself and are not authorable here (see the group note above).
@export var enemy_hp_neutral_color: Color = Color(0.92, 0.92, 0.95, 0.95)
## Seconds the bar stays fully lit after the LAST hit on that target. Measured on the WALL CLOCK, so a kill's
## hitstop or a conversation's pause cannot stretch it.
@export var enemy_hp_hold_time: float = 3.0
## Seconds the bar takes to fade out once the hold elapses.
@export var enemy_hp_fade_time: float = 0.6
## The "chip" shard — the bright sliver marking where the bar stood before this hit, drawn under the live
## fill so a big hit reads as a chunk taken out rather than a silent slide.
@export var enemy_hp_chip_color: Color = Color(1.0, 1.0, 1.0, 0.75)
## Seconds the chip holds still before it starts catching up. Long enough for the eye to register the shard
## as a discrete quantity of damage; 0 = no shard at all (it collapses onto the fill immediately).
@export var enemy_hp_chip_delay: float = 0.25
## How fast the chip then slides down, in bar-fractions per second (1.0 = a full-width sweep in one second).
@export var enemy_hp_chip_speed: float = 0.9
## Contrast rim drawn under the whole bar, px on EACH side. Keeps a dark track legible against a dark scene,
## the way the stamina ring's outline does at the reticle. 0 = no rim.
@export var enemy_hp_outline_width: float = 1.0
@export var enemy_hp_outline_color: Color = Color(0.0, 0.0, 0.0, 0.85)

@export_group("Hotbar")
## Slot metrics (hotbar.gd). These defaults are the SHIPPED, eye-tuned look — 38x24 slots with 7/8px type.
## A "rescale for the 792x444 canvas" pass once bumped them to 56x32/9-12px because a stale code comment
## claimed the old numbers targeted the wrong viewport; on screen that read as a GINORMOUS bar (the user's
## word). The authored look wins over derived math: resize by eye, in the inspector, or not at all.
@export var hotbar_slot_size: Vector2 = Vector2(38, 24)
## The slot's key caption (the bound key in its corner).
@export var hotbar_key_font_size: int = 7
## The slot's item-name line.
@export var hotbar_name_font_size: int = 8
## The slot's stack-count corner readout.
@export var hotbar_count_font_size: int = 7
## Pixels between slots.
@export var hotbar_separation: int = 1
## Bar inset from the canvas's bottom-right corner (x in from the right, y up from the bottom).
@export var hotbar_inset: Vector2 = Vector2(4, 4)
## An unassigned slot's text tint.
@export var hotbar_empty_color: Color = Color(1, 1, 1, 0.25)
## An assigned slot's text tint.
@export var hotbar_filled_color: Color = Color(0.92, 0.92, 0.95)
## The drawn weapon's / in-hand prop's slot — gold, like the money readout.
@export var hotbar_equipped_color: Color = Color(1.0, 0.86, 0.3)
