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
##   marker_size, max_distance) — the skin only replaces their in-code fallback literals. THE MINIMAP IS
##   THE EXCEPTION, and deliberately so: it is an authored scene with a UI artist pointed at it, so ALL of
##   its paint — colours AND the widths/sizes of what it draws — was consolidated here on 2026-08-19,
##   including two knobs that used to be @exports on the widget itself (marker_radius / arrow_size). The
##   combat indicators are CODE-built (player_hud.gd `.new()`), so their old @export defaults were
##   unreachable in-editor; those defaults move here verbatim.
## Every field's default EQUALS the previously hardcoded value, so the shipped game looks identical
## until an artist edits the .tres (tests/test_hud_skin.gd pins a representative sample).

@export_group("Crosshair")
## OPTIONAL artist reticle art (ui.gd): drawn centred in the crosshair rect INSTEAD of the code-drawn
## flat white disc while unscoped. Null = keep the shader-drawn dot (the shipped look). The scoped
## inverting disc is functional (it samples the screen for contrast) and is not replaced by art.
@export var crosshair_texture: Texture2D

@export_group("HUD ghost")
# The colour of the phosphor trail behind the HUD (scripts/ui/hud_ghost.gd). The RAMP lives here and the
# AMOUNTS (how strong, how long, how far it lags) stay on GameSettings.hud — the house split, same as the
# minimap's colours-here / world-span-there. See the field below for what the gradient is keyed on.
## The ghost's colour ramp, sampled by the AGE of each trail pixel: offset 1.0 is the freshest part of the
## tail (the frame that just left) and offset 0.0 is the oldest, about to vanish. So a gradient authored
## white -> cyan -> violet -> magenta makes the trail SHIFT HUE as it decays, the way a real phosphor does,
## instead of being a dimmer copy of whatever colour the HUD element happened to be. The gradient's own
## ALPHA is multiplied into the fade, so an artist can shape the whole envelope here too.
##
## Null = the shipped code-built ramp (HudGhost.default_gradient) — the MenuSkin "null slot keeps the
## shipped look" rule. How far the ramp REPLACES the source colour is GameSettings.hud.hud_ghost_tint:
## at 0 the ghost is the old plain dimmed copy, at 1 it is pure ramp and carries no source colour at all.
@export var ghost_gradient: Gradient

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
# HUD minimap (scripts/ui/minimap.gd) — the top-right procedural floorplan, and the ARTIST'S WHOLE SURFACE
# for it. THE RULE, which is what makes this findable: if it changes how the map LOOKS it is in this file;
# if it changes what the map DOES it is elsewhere. So every drawn element's COLOUR *and its width/size* sit
# together here — "make the walls thicker" and "make the walls orange" are one trip to one resource.
#
# What is deliberately still elsewhere, because it is behaviour rather than paint: the box's rect and where
# it sits (authored in scenes/ui/hud_minimap.tscn, mirrored into GameSettings.hud for the fallback), how much
# WORLD the box shows and where the section cut is taken (minimap_world_span / _cut_height / _band_height and
# the solid-span + merge knobs on GameSettings.hud — those change which geometry is gathered, not how it is
# inked), the on/off switches for whole channels (Minimap.draw_walls / draw_walkable / dot_npcs /
# dot_stations, in the scene's inspector), and the player's own rows (on/off, rotate, zoom) on Settings.
#
# Marker ART lives in the "Minimap art" group below; every size knob here sizes the drawn glyph AND the art
# that replaces it, so the two can never disagree.
## The player caret's fallback tint (cool blue).
@export var minimap_player_color: Color = Color(0.4, 0.8, 1.0)
## THE ARROW's half-size in px — the drawn caret's half-length, and the half-side of the square an authored
## minimap_player_texture is stretched into. Was Minimap.arrow_size, a per-instance @export on the widget;
## it lives here now so all four marker sizes (caret / POI / body / station) are one group instead of four
## numbers in three files.
@export var minimap_caret_px: float = 5.0
## Fallback tint for a POI MARKER that carries no `color` of its own (the NPC red). Still the WorldMarker /
## quest-beacon fallback it always was — but no longer the neutral-NPC tint, which now has its own slot below.
@export var minimap_npc_color: Color = Color(1.0, 0.4, 0.4)
## A POI beacon's radius in px (the drawn dot, and the half-side of the square its art fills). Was
## Minimap.marker_radius. Note the rim-pin inset takes the LARGER of this and minimap_marker_edge_margin, so
## growing it past that margin pushes pinned beacons inward rather than letting the box clip them.
@export var minimap_poi_glyph_px: float = 4.0
## A NEUTRAL body's ring — a bystander who is neither threat nor ally. Its own slot because the old behaviour
## painted a neutral in `minimap_npc_color`, a salmon RED barely separable from CBPalette's hostile red at a
## 4 px radius (and doubly so once the off-floor fade multiplies the alpha down): the map said "danger" about
## every civilian in the level. Deliberately desaturated so it recedes — a neutral is scenery. The allegiance
## tints themselves are NOT here and must not be: hostile / friendly / companion come from CBPalette so they
## swap with Settings.colorblind_safe_cues and stay in lockstep with the hover name, the dialogue speaker name
## and the enemy health bar.
@export var minimap_neutral_color: Color = Color(0.72, 0.78, 0.8, 0.85)
## A BODY glyph's radius in px. Keep it BELOW minimap_station_glyph_px: "bodies are small and filled, stations
## are large and stroked" is what separates the two alphabets, and a hollow triangle being a campfire while a
## solid one is a man with a gun depends on that size gap as much as on the fill. A test pins the ordering.
@export var minimap_npc_glyph_px: float = 3.6
## The ring drawn around a HOSTILE that has noticed you — one radius step per Perception suspicion tier. Amber:
## a warning, deliberately NOT the hostile red it surrounds (a red ring on a red caret is one fatter red blob).
@export var minimap_alert_color: Color = Color(1.0, 0.75, 0.2, 0.95)
## Px of clear air between the body glyph and its FIRST alert ring. Zero makes that ring a thicker outline on
## the caret rather than a halo around it, which reads as "this NPC is drawn differently", not "it saw you".
@export var minimap_alert_ring_gap_px: float = 2.0
## Px the ring grows per suspicion tier (WARY / SUSPICIOUS / ALERTED). The threat level is carried by SIZE, not
## hue, so it survives the colourblind palette swap — zero collapses all three tiers onto one ring.
@export var minimap_alert_ring_step_px: float = 1.5
## Station glyphs (shop / bank / clinic / trainer / tech / leisure). One tint for the whole family — the KIND is
## carried by the glyph's SHAPE, not by nine more colours nobody could tell apart at 5 px.
@export var minimap_station_color: Color = Color(0.55, 0.9, 1.0, 0.9)
## A STATION glyph's radius in px — and the half-side of the square an authored station badge fills. Kept
## ABOVE minimap_npc_glyph_px on purpose; see that knob.
@export var minimap_station_glyph_px: float = 5.0
## LEVEL EXITS only (a LevelDoor's chevron). Picked out from the station family because a way out of the level
## is a different class of answer from a way to spend money — and it is the one glyph a lost player hunts for.
@export var minimap_exit_color: Color = Color(0.6, 1.0, 0.6, 0.95)
## The north tick on the box rim. Dim on purpose: it is a reference mark, not an instrument, and it must not
## compete with the markers inside the box.
@export var minimap_north_color: Color = Color(0.35, 0.95, 0.85, 0.7)
## Length of the north spoke in px, measured inward from the rim. 0 disables the tick entirely (it is only
## ever drawn in heading-up mode anyway — in north-up the whole plan is already axis-locked).
@export var minimap_north_tick_px: float = 4.0
## The section-cut wall strokes — the map's primary read.
@export var minimap_wall_color: Color = Color(0.35, 0.95, 0.85, 0.9)
## WALL STROKE WIDTH in px. 0 = Godot's transform-independent HAIRLINE, which is the shipped look and the
## crispest one on a 792x444 canvas nearest-upscaled ~2.4x. Anything above 0 is converted through the view
## matrix's px-per-metre so a stroke stays the same thickness on screen at every zoom instead of fattening
## as the player zooms in.
@export var minimap_wall_width: float = 0.0
## OPTIONAL NEON PASS: the walls drawn a SECOND time underneath themselves, wider and (normally) dimmer, so
## the plan can be RESTYLED rather than only recoloured — a bloom/halo without a shader or a second viewport.
## ⚠ ALPHA 0 = OFF, the alpha-as-null sentinel this file already uses; that is the shipped state, so the glow
## costs exactly nothing until an artist reaches for it. Give it the wall hue at a low alpha for neon, or a
## dark colour for a drop-shadowed "inked on paper" look.
@export var minimap_wall_glow_color: Color = Color(0.0, 0.0, 0.0, 0.0)
## The glow pass's stroke width in px. Only meaningful when minimap_wall_glow_color has alpha; must be WIDER
## than minimap_wall_width or the glow hides entirely under the stroke it is meant to surround (and note the
## main stroke's 0 = hairline, so almost any value here shows).
@export var minimap_wall_glow_width: float = 3.0
## The navmesh walkable-floor fill drawn UNDER the walls. Deliberately dim: it is ground, not ink, and at
## full strength it drowns the strokes that carry the actual shape of the rooms.
@export var minimap_walkable_color: Color = Color(0.16, 0.52, 0.56, 0.35)
## Backing behind the plan — the "void" colour, seen wherever nothing was drawn. ⚠ Zero its ALPHA when you put
## a backdrop into the scene's %MapUnder slot, or this paints over it.
@export var minimap_backing_color: Color = Color(0.02, 0.04, 0.06, 0.6)
## The code-drawn contrast rim / corner brackets around the box (the enemy_hp_outline_color family).
@export var minimap_outline_color: Color = Color(0.35, 0.95, 0.85, 0.55)
## The rim's stroke width in px. 0 = no rim at all (which is what you want once a frame lands in the scene's
## %MapOver slot or in minimap_frame_texture). ⚠ This is INK DRAWN OUTSIDE the box's left edge, so it is part
## of the enemy-health-bar clearance maths in tests/test_minimap_hud_layout.gd — growing it a lot can collide.
@export var minimap_outline_width: float = 1.0
## OPTIONAL artist frame art drawn OVER the box. Null = the code-drawn rim (the shipped look) — the
## MenuSkin widget-art fallback rule. SUPERSEDED for most looks by a NinePatchRect dropped into the
## scene's %MapOver slot, which stretches its corners properly instead of scaling the whole PNG; this
## slot stays for a frame that really is one flat stretched image.
@export var minimap_frame_texture: Texture2D

# --- Shared marker geometry: the four knobs every marker channel reads, rather than one copy each. ---
## Stroke width in px for every HOLLOW glyph — the stroked station badges, the neutral body ring, the alert
## rings, the off-storey ticks and the north spoke. 0 = Godot's hairline (the minimap_wall_width idiom).
@export var minimap_glyph_stroke_px: float = 1.0
## Length in px of the little up/down tick beside a marker on ANOTHER storey. 0 disables the ticks and leaves
## the alpha fade below to say "not here" on its own — which it does mutely, without saying which way.
@export var minimap_floor_tick_px: float = 3.0
## Alpha MULTIPLIER applied to a marker one floor band away, so a beacon two storeys up fades instead of
## pretending to be in this room. Paint, not tuning: it is literally a colour alpha. 1.0 removes the fade
## entirely and makes the map lie about vertical position.
@export var minimap_marker_floor_alpha: float = 0.3
## How far in from the rim (px) an off-box marker PINS. Raise it to keep pinned beacons clear of a frame
## dropped into the scene's %MapOver slot — a bezel drawn over the rim would otherwise cover them. The pin
## takes the LARGER of this and the glyph's own radius, so a glyph can never be sliced in half by the box's
## clip_contents.
@export var minimap_marker_edge_margin: float = 5.0

@export_group("Minimap art")
# THE UI ARTIST'S DROP-IN SURFACE for the minimap's MARKERS — the MenuSkin widget-art rule, applied to the
# three families a scene node cannot reach (a %MapOver child cannot draw a badge at a position recomputed
# every frame). Every slot is OPTIONAL and null by default, so the shipped map is pixel-identical and each
# delivered PNG lands ONE AT A TIME.
#
# THE CONTRACT, the same for all ten: art replaces the marker's SILHOUETTE only. Where it sits, how big it
# is and what colour it wears are NOT here — position comes from the world, size from the px knobs on
# GameSettings.hud (a texture is stretched into a square of 2x that radius, so it can never encode its own
# size), and tint from the colour the channel already resolved, multiplied by the off-floor alpha fade.
# Deliver art WHITE/GREY and let the tint do the colouring, exactly as MenuSkin's meter fills ask.
#
# WHAT IS DELIBERATELY NOT HERE: the four body glyphs, the alert ring, the floor tick and the north tick.
# Those are 2-4 px marks whose meaning IS their shape — the accessibility channel this project chose over
# hue because hue fails at that size and swaps under Settings.colorblind_safe_cues. Art there buys a smudge
# and costs the alphabet. The backdrop and the frame are not here either: they are whole-box LAYERS, and
# the scene's %MapUnder / %MapOver slots draw them properly. See scripts/ui/minimap_art.gd.
#
# Every name ends `_texture` on purpose: the matching `_px` / `_width` names are the SIZE knobs in the
# Minimap group above, and each art slot is stretched to exactly the size its drawn twin used.

## The PLAYER CARET. Replaces: the drawn triangle at the box centre. Sized by: minimap_caret_px (a square
## of 2x it). Tinted by: minimap_player_color. ROTATES: yes — the only slot here that does. Author it
## pointing SCREEN-UP; in heading-up mode it stays pointing up while the plan turns under it, and in
## north-up mode it spins to show your bearing. A per-level MapData.player_marker still wins over this.
@export var minimap_player_texture: Texture2D
## A POI BEACON (a WorldMarker, or one QuestMarkerSync spawned for a live objective). Replaces: the flat
## filled dot. Sized by: minimap_poi_glyph_px. Tinted by: the marker's own `color`, else
## minimap_npc_color. ROTATES: no. Note this channel PINS to the box rim when its target is off-screen, so
## art here should read at the edge as well as in the middle. A per-level MapData.npc_marker wins over it.
@export var minimap_poi_texture: Texture2D
## THE STATION FAMILY BADGE — the fallback every station kind wears when its own slot below is empty.
## Replaces: the stroked glyph. Sized by: minimap_station_glyph_px. Tinted by: the StationMarker's own
## `color` when it sets one, else minimap_station_color (or minimap_exit_color for a level exit).
## ROTATES: no — a shop is a shop from every bearing.
## Filling THIS alone and leaving the seven empty deliberately collapses the alphabet to one badge; that is
## a legitimate art direction, and it is the honest way to say it.
@export var minimap_station_texture: Texture2D
## Shop (a Merchant). Replaces the stroked diamond. Same size/tint/rotation contract as the family badge.
@export var minimap_station_shop_texture: Texture2D
## Bank (an Atm). Replaces the stroked hexagon.
@export var minimap_station_bank_texture: Texture2D
## Clinic (a Healer). Replaces the stroked cross.
@export var minimap_station_heal_texture: Texture2D
## Trainer (LevelUp / PerkStation / RespecStation). Replaces the stroked INVERTED triangle — and an art slot
## bypasses that inversion entirely, so draw a trainer badge that is already unmistakable against the
## hostile caret rather than relying on the flip.
@export var minimap_station_train_texture: Texture2D
## Tech booth (a ChipInstaller). Replaces the stroked square.
@export var minimap_station_tech_texture: Texture2D
## Rest / play (a Bonfire or ChessMatch). Replaces the stroked circle.
@export var minimap_station_leisure_texture: Texture2D
## Level exit (a LevelDoor). Replaces the stroked chevron, and keeps its own minimap_exit_color tint — it is
## picked out of the family on purpose, being the one glyph a lost player hunts for.
@export var minimap_station_exit_texture: Texture2D

@export_group("Clock")
# The HUD time-of-day readout (scripts/ui/hud_clock.gd) directly under the map. Paint only, like the group
# above: the box, gaps and digit size are author-time tuning on GameSettings.hud's "Clock" group, and the
# on/off + 12/24-hour face belong to the player on Settings. The digits wear the shared Label-chrome
# outline below, so only the fill colour is a slot of its own.
## The digits' tint. Matches minimap_wall_color's cyan so the map and its caption read as one instrument;
## retint it alone if a skin wants the time to stand apart from the plan.
@export var clock_color: Color = Color(0.35, 0.95, 0.85, 0.9)

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
