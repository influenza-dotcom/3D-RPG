class_name MenuSkin
extends Resource

## The ARTIST'S menu skin — ONE Resource that reskins every menu without touching code. Edit
## resources/ui/menu_skin.tres in the inspector (or assign a different .tres / call MenuStyle.set_skin)
## to change the whole game's menu look: drop a PNG into background_texture for a custom backdrop,
## recolour the palette, swap fonts, or hand your own StyleBox to panel_style to fully replace the panel
## chrome. MenuStyle (autoload) reads this and builds the live Theme every menu uses.

@export_group("Background (full-screen menus)")
## Custom backdrop image for full-screen menus (the start menu). Drop a PNG/texture here; null = flat colour.
@export var background_texture: Texture2D
## ...or a whole scene (animated / shader background); takes priority over the texture when set.
@export var background_scene: PackedScene
## Flat fill used when neither a texture nor a scene is set.
@export var background_color: Color = Color(0.04, 0.04, 0.055, 1.0)

@export_group("Backdrop (in-game modals)")
## The dim drawn over the gameplay world behind an in-game modal (inventory/shop/loot/…). Higher alpha = darker.
@export var backdrop_dim: Color = Color(0.0, 0.0, 0.0, 0.55)

@export_group("Panel")
## Panel fill colour (the menu card). Alpha < 1 lets the dimmed world/background show faintly through.
@export var panel_color: Color = Color(0.05, 0.055, 0.07, 0.94)
## Hairline panel border colour.
@export var panel_border_color: Color = Color(1.0, 1.0, 1.0, 0.06)
## Panel border thickness (px). 0 = borderless.
@export var panel_border_width: int = 1
## Panel corner rounding (px). 0 = sharp.
@export var panel_corner_radius: int = 2
## Inner padding (px) between the panel edge and its contents.
@export var panel_content_margin: int = 16
## OPTIONAL: your own StyleBox (e.g. a StyleBoxTexture 9-patch) to fully replace the panel chrome; null = built from the colours above.
@export var panel_style: StyleBox

@export_group("Palette")
## Primary menu text.
@export var text_color: Color = Color(0.92, 0.92, 0.95)
## Secondary / hint / dim text.
@export var text_dim_color: Color = Color(1.0, 1.0, 1.0, 0.45)
## The single ACCENT — selection bar, focused control, active tab, slider fill.
@export var accent_color: Color = Color(0.95, 0.85, 0.4)
## Currency (zorkmid) text.
@export var gold_color: Color = Color(0.95, 0.85, 0.4)
## Warnings (over-encumbered, can't-afford).
@export var danger_color: Color = Color(1.0, 0.55, 0.4)
## Text colour of a disabled control. (Hover styling is NOT a skin knob — MenuStyle builds the hover
## stylebox from accent_color; see MenuStyle._accent_bar.)
@export var disabled_text_color: Color = Color(1.0, 1.0, 1.0, 0.28)

@export_group("Typography")
## OPTIONAL custom body font; null = Godot's default font.
@export var body_font: Font
## OPTIONAL custom title font; null = the body/default font (MenuStyle still adds tracking).
@export var title_font: Font
## Tracked title size (px).
@export var title_size: int = 15
## Sub-header / section size (px).
@export var header_size: int = 13
## Body / control / button text size (px).
@export var body_size: int = 12
## Footnote / hint size (px).
@export var hint_size: int = 11
## Extra glyph spacing (px) on titles for the tracked-uppercase look. 0 = none.
@export var title_tracking: int = 4
## UPPERCASE titles + section headers (the sleek look). Off = leave the author's casing.
@export var uppercase_titles: bool = true

@export_group("Layout")
## Root VBox separation shared by every panel screen (inventory/stats/shop/loot/options/…) so the
## title/hint rhythm stays identical when flipping between menus. Screens read this instead of a
## per-file magic number.
@export var content_separation: int = 8
## Gap between buttons in a confirm/cancel row (heal/respec/name-entry/character-creation).
@export var button_row_separation: int = 8
## Minimum width of a dialog action button (Confirm/Cancel/Close/Heal). One value so the
## transaction modals' buttons match across screens.
@export var dialog_button_min_width: int = 160
## Width FLOOR for one player-menu tab button (Inventory/Stats/Reputation/Journal). The strip
## stretches to the panel's width; this only guards pathological narrow canvases. Keep the four
## tabs' total (4x + separations) under the 0.12-margin panel width at the smallest canvas.
@export var tab_min_width: int = 72
## FIXED width (px) of a centered transaction / prompt dialog card (heal / respec / name-entry). The card
## is pinned to EXACTLY this width regardless of its text (MenuStyle.make_dialog), so a long station /
## merchant / prompt name or a big cost can never grow it or shift it off-centre — titles + costs clip
## with "…" and status lines wrap within it. This is the fixed-width discipline that keeps the floating
## modals from re-sizing per string the way the anchored full-panel screens (shop/loot/stats) already don't.
@export var dialog_width: int = 380

@export_group("Sounds")
## Played when the mouse hovers any menu button. Drop an AudioStream here in the inspector; null = silent.
@export var hover_sound: AudioStream
## Played when any menu button is clicked. Drop an AudioStream here; null = silent.
@export var click_sound: AudioStream
## Volume (dB) for the menu hover/click sounds.
@export var ui_sound_volume_db: float = 0.0
