class_name HudSettings
extends Resource

## HUD look + feel: colours, sizes, fonts, and timings for the segmented HP bar, the money readout, the
## reputation/notification toasts, and the crosshair — all on ONE inspector page
## (resources/tuning/HudSettings.tres), read as GameSettings.hud.<field> by ui.gd. These are AUTHOR-TIME numbers
## (a global tuning group, not a player-facing Options row), matching the other GameSettings.* groups.

@export_group("General")
## The big centred HUD message font (interaction prompts etc.).
@export var hud_font_size: int = 32
## Reticle box size (px); a shader discs it.
@export var crosshair_size: Vector2 = Vector2(4, 4)

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
@export var rep_gain_color: Color = Color(0.4, 1.0, 0.45)
@export var rep_loss_color: Color = Color(1.0, 0.45, 0.4)
@export var rep_neutral_color: Color = Color(0.85, 0.85, 0.85)
