class_name HudSettings
extends Resource

## HUD look + feel: colours, sizes, fonts, and timings for the segmented HP bar, the money readout, the
## reputation/notification toasts, the crosshair, the centre-screen prompts/meters, and the hotbar — all on
## ONE inspector page (resources/tuning/HudSettings.tres), read as GameSettings.hud.<field> by ui.gd,
## player_hud.gd, and hotbar.gd. These are AUTHOR-TIME numbers (a global tuning group, not a player-facing
## Options row), matching the other GameSettings.* groups.

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
## Bar origin: x in from the left edge, y up from the bottom.
@export var hp_bar_inset: Vector2 = Vector2(20, 60)
## A drained segment (dark, translucent).
@export var hp_seg_empty: Color = Color(0.22, 0.05, 0.06, 0.55)
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
## Fill fraction at/below which the bar wears stamina_low (ui.gd).
@export var stamina_low_frac: float = 0.25

@export_group("Money readout")
@export var money_font_size: int = 16
@export var money_delta_font_size: int = 15
## Gold for the persistent zorkmid readout.
@export var money_color: Color = Color(1.0, 0.86, 0.3)
## Green +N on a gain.
@export var money_gain_color: Color = Color(0.45, 1.0, 0.5)
## Red -N on a spend.
@export var money_loss_color: Color = Color(1.0, 0.5, 0.4)
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

@export_group("Hotbar")
## Slot metrics for the 792x444 canvas (hotbar.gd): 10 x 56px + 9 x 2px gaps = 578px.
@export var hotbar_slot_size: Vector2 = Vector2(56, 32)
## The slot's key caption (the bound key in its corner).
@export var hotbar_key_font_size: int = 9
## The slot's item-name line.
@export var hotbar_name_font_size: int = 12
## The slot's stack-count corner readout.
@export var hotbar_count_font_size: int = 9
## Pixels between slots.
@export var hotbar_separation: int = 2
## Bar inset from the canvas's bottom-right corner (x in from the right, y up from the bottom).
@export var hotbar_inset: Vector2 = Vector2(4, 4)
## An unassigned slot's text tint.
@export var hotbar_empty_color: Color = Color(1, 1, 1, 0.25)
## An assigned slot's text tint.
@export var hotbar_filled_color: Color = Color(0.92, 0.92, 0.95)
## The drawn weapon's / in-hand prop's slot — gold, like the money readout.
@export var hotbar_equipped_color: Color = Color(1.0, 0.86, 0.3)
