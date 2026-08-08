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
## Base opacity of the ring's fill arc (the idle fade multiplies ON TOP of this) — the ring reads as a
## translucent annotation over the world rather than solid paint at the aim point (user call). The
## outline rides the same multiplier so the rim never overpowers a faded fill.
@export var stamina_ring_alpha: float = 0.6
## Outline width (px, EACH side of the stroke) drawn under the fill arc — the contrast rim that keeps a
## thin 2px arc legible over bright/dithery scenes. 0 = no outline.
@export var stamina_ring_outline_width: float = 1.0
## Outline colour (fades with the ring's idle alpha).
@export var stamina_ring_outline_color: Color = Color(0.0, 0.0, 0.0, 0.9)

@export_group("HUD weight")
# Diegetic HUD sway (scripts/ui/hud_sway.gd, driven per frame in ui.gd): the corner HUD cluster —
# HP/stamina bars, ammo, money, toasts, quest tracker, hotbar — trails camera turns on a damped spring
# and settles, reading as an instrument panel with mass. The crosshair + stamina ring ride the SAME
# spring at hud_sway_aim_scale (a whisper — see that knob); the look-name label stays pinned. TWO channels feed the one spring: every ROTATIONAL
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
## spring, so reticle and panel share ONE mass and one settle, just at a whisper of the amplitude
## (0.12 of an 8px max ≈ 1px). MUCH subtler than the panel by design: the reticle is the aim reference
## and large motion there reads as aim error, not weight. 0 = classic fully-pinned reticle. Inherits
## the Accessibility "HUD Sway" scale for free (the offset it samples is already scaled).
@export var hud_sway_aim_scale: float = 0.12
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
## Distance (px) from the canvas top to the TOP of the bar's TRACK. THE TIGHT ONE: the centre-top column below
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
