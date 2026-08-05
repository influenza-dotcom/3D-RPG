class_name HudSkin
extends Resource

## The ARTIST'S in-game HUD skin — the MenuSkin twin for everything drawn DURING gameplay: the combat
## indicators around the crosshair (hitmarker, damage/aim arcs, sniper glints), the compass and minimap
## marker tints, the optional crosshair art, and the shared label chrome (text outlines, hotbar slot
## tints) that ui.gd/hotbar.gd previously hardcoded. Edit resources/ui/hud_skin.tres in the inspector
## (or call MenuStyle.set_hud_skin) and every consumer repaints — no code changes.
##
## SCOPE CONTRACT (why this file is smaller than "the whole HUD"):
## - GAMEPLAY-TUNING numbers (bar geometry, sway springs, hold/fade timings, meter layout budgets)
##   already live on GameSettings.hud (resources/tuning/HudSettings.tres) and STAY there — this skin
##   only owns values that were hardcoded consts/literals in the scripts named per field below.
## - SEMANTIC colours are deliberately NOT here: allegiance / gain-loss tints come from CBPalette
##   (colorblind accessibility, swaps with Settings.colorblind_safe_cues), and accessibility gates
##   (Settings.enemy_health_bar_enabled etc.) stay on Settings.
## - Components that are SCENE-authored keep their per-instance @exports (compass.gd edge_margin,
##   minimap.gd marker_radius, …) — the skin only replaces their in-code fallback literals. The
##   combat indicators are CODE-built (player_hud.gd `.new()`), so their old @export defaults were
##   unreachable in-editor; those defaults move here verbatim.
## Every field's default EQUALS the previously hardcoded value, so the shipped game looks identical
## until an artist edits the .tres (tests/test_hud_skin.gd pins a representative sample).

@export_group("Crosshair")
## OPTIONAL artist reticle art (ui.gd): drawn centred in the crosshair rect INSTEAD of the code-drawn
## flat white disc while unscoped. Null = keep the shader-drawn dot (the shipped look). The scoped
## inverting disc is functional (it samples the screen for contrast) and is not replaced by art.
@export var crosshair_texture: Texture2D

@export_group("Hitmarker")
# Crosshair hit-confirm X ticks (scripts/ui/hitmarker.gd — code-built by player_hud.gd, so these ARE
# its authoring surface now).
## Seconds the marker stays visible per hit, fading out.
@export var hitmarker_duration: float = 0.25
## Length of each of the four ticks (px).
@export var hitmarker_tick_length: float = 5.0
## Gap from the crosshair centre to a tick's inner end (px).
@export var hitmarker_gap: float = 3.0
## Tick line width (px).
@export var hitmarker_thickness: float = 2.0
## Extra px the ticks sit further out at full strength, settling in as they fade (the "pop").
@export var hitmarker_pop_px: float = 3.0
## Body-hit tick colour (alpha fades over hitmarker_duration).
@export var hitmarker_color: Color = Color(1.0, 1.0, 1.0, 0.9)
## Headshot ticks flash this colour, scaled up, so head hits read instantly.
@export var hitmarker_headshot_color: Color = Color(1.0, 0.22, 0.12, 0.95)
## Size multiplier for a headshot pop (ticks, length, gap) — bigger reads louder.
@export var hitmarker_headshot_scale: float = 1.9
## OPTIONAL artist hit-confirm art: drawn centred at the crosshair (modulated by the body/headshot
## colour + fade) INSTEAD of the four code-drawn ticks. Null = keep the drawn X (the shipped look).
@export var hitmarker_texture: Texture2D

@export_group("Damage direction arcs")
# TF2-style "you were hit from here" red arcs (scripts/ui/damage_indicators.gd — code-built).
## Seconds each arc stays visible (it fades over this).
@export var damage_arc_duration: float = 1.0
## Distance of the arc from screen centre (px). Shares the crosshair annulus with the stamina ring
## (~14), aim arcs (28+) and the aim ping (84) — see stamina_ring.gd's annulus-budget note.
@export var damage_arc_radius: float = 120.0
## Angular width of each arc wedge (degrees).
@export var damage_arc_degrees: float = 55.0
## Line thickness of each arc (px). Higher = bolder indicator.
@export var damage_arc_thickness: float = 8.0
## Arc colour (its alpha is the starting opacity, then fades over the duration).
@export var damage_arc_color: Color = Color(0.85, 0.08, 0.08)

@export_group("Aim warning arcs")
# "You're being aimed at" radial warning (scripts/ui/aim_indicators.gd — code-built). The arc grows
# outward as the enemy's shot charges, scaled by the shot's damage.
## Smallest arc radius (px), at charge ~0 — visible the instant an enemy starts aiming. Keep >= ~26:
## the stamina ring (radius 14) and hitmarker ticks (~11–21 px) live inside this.
@export var aim_arc_base_radius: float = 28.0
## Extra radius (px) per point of the shot's damage at FULL charge: a bigger hit => a bigger ring.
@export var aim_arc_damage_to_pixels: float = 70.0
## Hard cap on the arc radius (px) so a very high-damage weapon doesn't blow the ring off-screen.
@export var aim_arc_max_radius: float = 110.0
## Angular width of each arc wedge (degrees).
@export var aim_arc_degrees: float = 45.0
## Stroke width of the arc (px) — a thicker, more alarming line than the damage arcs.
@export var aim_arc_thickness: float = 6.0
## Warning arc colour; opacity is driven by charge at draw time, so author the RGB here.
@export var aim_arc_color: Color = Color(0.9, 0.1, 0.1)
## Arc opacity at charge 0 (it ramps linearly to 1.0 at full charge): faint while an enemy is merely
## noticing you, bright once locked.
@export var aim_arc_min_alpha: float = 0.35
## Blink period (s) while an aim is in its final-warning beep beat: the radial flashes with the beep.
@export var aim_arc_blink_period: float = 0.12
## The blink's DIM phase opacity (the bright phase is 1.0).
@export var aim_arc_blink_dim_alpha: float = 0.15
## Fixed radius (px) of the "you were just shot from here" ping — the same radial briefly swung onto
## the shooter after their aim arc has already cleared.
@export var aim_ping_radius: float = 84.0
## Seconds that damage-direction ping lives (it fades over this).
@export var aim_ping_ttl: float = 0.6

@export_group("Sniper glints")
# Screen-space lens flare over each distant enemy aiming at the player (scripts/ui/sniper_glints.gd —
# code-built; drawn ADDITIVE, so brighter RGB = more dazzling). min_distance/expiry stay functional
# consts on the component — they gate WHEN a glint shows, not how it looks.
## Flare core radius (px) at full charge; it grows from glint_min_scale of this as the shot charges.
@export var glint_core_radius: float = 6.0
## Half-length (px) of the anamorphic cross streaks at full charge.
@export var glint_streak_length: float = 22.0
## Flare colour (cool blue-white). Alpha ramps with charge at draw time.
@export var glint_color: Color = Color(0.7, 0.85, 1.0)
## Glint opacity at charge 0 (ramps linearly to 1.0 as the shot locks in).
@export var glint_min_alpha: float = 0.4
## Fraction of full size the core/streaks start at when the enemy has only just begun aiming.
@export var glint_min_scale: float = 0.45

@export_group("Compass")
# Screen-edge compass markers (scripts/ui/compass.gd). Its geometry (edge_margin, marker_size,
# max_distance) stays scene-authored @exports on the component; the skin owns paint.
## Tint for a compass marker whose WorldMarker carries no `color` of its own (gold, like the money
## readout).
@export var compass_fallback_color: Color = Color(1.0, 0.85, 0.3)
## OPTIONAL artist marker art: drawn centred at the marker/chevron point (modulated by the marker's
## colour) INSTEAD of the code-drawn dot. Null = keep the drawn circle (the shipped look).
@export var compass_marker_texture: Texture2D

@export_group("Minimap")
# HUD minimap markers (scripts/ui/minimap.gd). Marker ART already comes from the authored MapData
# resource (player_marker / npc_marker textures); these are the code-drawn FALLBACK dot tints used
# when a MapData ships without that art.
## The player dot's fallback tint (cool blue).
@export var minimap_player_color: Color = Color(0.4, 0.8, 1.0)
## Fallback tint for an NPC/marker that carries no `color` of its own (the NPC red).
@export var minimap_npc_color: Color = Color(1.0, 0.4, 0.4)

@export_group("Label chrome")
# The shared black-outline dialect every code-built HUD label wears (ui.gd) so text reads over any
# scene. One colour + per-tier widths; the font SIZES stay on GameSettings.hud.
## Outline colour for the toast / money / quest-tracker / look-name labels.
@export var label_outline_color: Color = Color(0.0, 0.0, 0.0, 1.0)
## Outline width (px) on the small top-left/top-right text: toasts, money readout + delta, quest tracker.
@export var toast_outline_size: int = 4
## Outline width (px) on the centred look-at name under the crosshair.
@export var look_name_outline_size: int = 5
## Outline width (px) on the big corner readout labels (the ammo "clip / reserve" line).
@export var corner_label_outline_size: int = 6
## Outline colour of those big corner readouts (slightly translucent, unlike the hard label outline).
@export var corner_label_outline_color: Color = Color(0.0, 0.0, 0.0, 0.9)
## The corner readouts' resting text colour (the ammo line when the clip isn't low).
@export var corner_label_color: Color = Color.WHITE

@export_group("Hotbar chrome")
# Residual hotbar literals (scripts/ui/hotbar.gd _build_bar). Slot metrics/fonts and the empty/filled/
# equipped NAME tints already live on GameSettings.hud ("Hotbar" group) and stay there.
## Self-modulate of each slot's PanelContainer — the quiet, semi-transparent chrome under the HUD.
@export var hotbar_panel_modulate: Color = Color(1, 1, 1, 0.55)
## The slot's key-caption tint (the bound key in its corner).
@export var hotbar_key_color: Color = Color(1, 1, 1, 0.5)
## The slot's stack-count corner readout tint.
@export var hotbar_count_color: Color = Color(1, 1, 1, 0.6)
## Outline width (px) on the slot's item-name line.
@export var hotbar_name_outline_size: int = 2
