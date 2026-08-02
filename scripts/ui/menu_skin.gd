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

@export_group("Character preview (3D showcase)")
## Radial-gradient CENTRE of the studio backdrop behind the 3D character showcase (inspect screen, creator,
## stats portrait). Skin-driven so the showcase reskins with the rest of the menus (was hard-coded).
@export var preview_backdrop_center: Color = Color(0.17, 0.18, 0.22)
## Radial-gradient EDGE of the studio backdrop (fades to this toward the corners).
@export var preview_backdrop_edge: Color = Color(0.04, 0.045, 0.06)
## Albedo of the pedestal disc the showcased character stands on.
@export var preview_pedestal_color: Color = Color(0.10, 0.11, 0.14)

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
## How many lines tall a hover-tooltip FOOTER stands (MenuStyle.make_hint_footer — the loot/pickpocket and
## inventory screens). The footer is FIXED-height so hovering can't re-lay-out the grids above it, which makes
## this a genuine BUDGET: every line reserved here is stolen from the EXPAND_FILL grid columns, so raising it
## shrinks the item tiles. 5 = the longest real tooltip (name + effect/stat line + weight/value) at 4, plus ONE
## for the pickpocket odds line that rides on top of it in pickpocket mode. Verified against the shipped pistol
## and microchip tooltips by screenshot; 6 visibly shrank the tiles for no gain. The height is snapped to a
## whole number of RENDERED lines, so a longer-than-budget tooltip clips between lines, never through glyphs.
@export var footer_hint_lines: int = 5
## Extra glyph spacing (px) on titles for the tracked-uppercase look. 0 = none.
@export var title_tracking: int = 4
## UPPERCASE titles + section headers (the sleek look). Off = leave the author's casing. Consulted ONLY by
## MenuStyle.title_text (the single casing chokepoint) — so a future per-locale MenuSkin remap can flip
## casing off wholesale for locales with no meaningful uppercase (CJK, Turkish dotted/dotless i).
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

@export_group("Layout budgets (English-measured px)")
## Fixed pixel budgets for TEXT-bearing columns and buttons, hoisted out of the screens so ONE authored
## resource owns them. Three contracts shared by every knob in this group:
##  (a) each value is measured against the ENGLISH strings that land in that slot — German runs +30-40%
##      longer, so a translated string WILL clip at these widths;
##  (b) a future locale retunes them via a per-locale remapped menu_skin.tres (the same remap surface as
##      uppercase_titles / the CJK type-ramp decision), re-verifying each knob's fit math documented below;
##  (c) do NOT "fix" a clipped string by growing a budget here globally — the fixed widths are exactly what
##      stops runtime text from resizing/shifting controls (the make_dialog card-hop bug, the options
##      rebind-column jump, the shop sort-button drift). Growing one here retunes EVERY locale at once;
##      that is a deliberate per-locale-skin decision, never a clipping hotfix.

## Options: the right-aligned slider value readout column — an EXACT width, not a floor (the readout Label
## is cap_label()'d, so a wide string clips instead of shrinking the slider mid-drag). English readout
## strings ("No cap", "100%") measure under ~56px at body_size 12; setting_label_col_width_dense's
## half-column math assumes this exact value.
@export var slider_readout_width: int = 56
## Options: the keybind rebind buttons — a fixed-width right-aligned column, not full-width bars. 120 fits
## the widest real ENGLISH binding name ("Mouse Wheel Up" ≈ 117px incl. the 9+9 stylebox margins); the
## button is cap_button()'d so anything longer (the armed PlayerText.OPTIONS_BIND_PROMPT, an exotic key
## name) clips instead of growing the button and shifting the column. The Controls tab lays out
## single-column, so extra width here comes out of the EXPAND_FILL name label.
@export var rebind_button_width: int = 120
## Options: left setting-name column floor on a full-width row, so every tab's controls start on one rail.
@export var setting_label_col_width: int = 130
## Options: setting-name column floor inside a two-up dense column (the Accessibility tab). The half-column
## fit is English-measured: 110 + 10 + 120 (slider min width) + 10 + slider_readout_width (56) = 306 fits a
## ~310px half-column at the 792x444 canvas — the full setting_label_col_width (130) would overflow it. A
## locale growing either label width must re-verify that sum.
@export var setting_label_col_width_dense: int = 110
## Shop: the Sort cycle button's fixed min width (cap_button clip_text pins BOTH edges) — ≥ the widest
## ENGLISH caption ("Sort: Default") so the footprint never shifts as the caption cycles.
@export var sort_button_width: int = 128
## Shop + chip-install: price column floor so every row's price lands in one aligned right column. A floor,
## not a cap — mostly digits plus the currency tag, but a locale that reformats prices retunes it here.
@export var price_col_width: int = 80
## Level-up: width cap for a stat/perk row's column group (name | value | +1 | cost), centered as one unit.
## English fit math: stat_name_col_width (76) + 22 + 20 fixed columns + 3x6 separations leaves ~204px for
## the right-aligned cost — roomy for "(9,999 zm)". Uncapped, the cost column stretched to the panel's full
## ~570px inner width and floated ~450px from its stat name.
@export var level_up_cols_width: int = 340
## Level-up: the stat-NAME cell inside that column group — fits the longest ENGLISH StatText title; a
## longer title clips with "…" (the cells are cap_label()'d).
@export var stat_name_col_width: int = 76
## Reputation: the right-aligned disposition word column — fits ENGLISH "Friendly"/"Hostile"/"Neutral"
## without per-row width churn.
@export var disposition_col_width: int = 90
## Character creation: the ‹ value › cycler's fixed value label (clip_text) — seats every ENGLISH catalog
## display name; anything longer clips instead of stranding the < > arrows at the row's far edges.
@export var cycler_value_width: int = 120
## Start menu: min width of the Continue/New Game/Settings/Quit buttons — fits the widest ENGLISH caption
## with air (a floor, not a clip budget).
@export var start_button_min_width: int = 220
## Reputation: right-aligned signed standing column — fits ENGLISH "+100"/"-100" at header_size.
@export var rep_value_col_width: int = 60

@export_group("Glyphs")
## The step arrows of EVERY cycler row — the Options choice cyclers (options_menu._option_row) AND the
## character creator's part cyclers (character_creation._make_cycler). THE one canonical glyph home:
## non-prose PAINT lives on the skin, never PlayerText (CLAUDE.md — shape glyphs are a designer export,
## not parked prose). PLAIN ASCII by default because the pixel font has no guillemets (‹ › render as
## tofu). An RTL locale swaps the pair via its per-locale menu_skin.tres.
@export var cycler_prev_glyph: String = "<"
## Forward twin of cycler_prev_glyph — see its note.
@export var cycler_next_glyph: String = ">"

@export_group("Grid tiles")
## The tetris-grid stack tiles (grid_tile.gd / grid_inventory_view.gd) — the inventory/loot/shop cells.
## Equipped-item border. Defaults to the accent gold — the designer decides any divergence from the
## ammo/money category gold.
@export var equipped_border_color: Color = Color(0.95, 0.85, 0.4)
## Border tint of a consumable stack's tile (the non-weapon "use it" category).
@export var tile_consumable_color: Color = Color(0.45, 0.80, 0.52)
## The thin ring the overlay draws around the hovered stack.
@export var tile_hover_ring_color: Color = Color(1, 1, 1, 0.85)
## Alpha the source tile dims to while its stack is being dragged.
@export var drag_source_dim_alpha: float = 0.35

@export_group("Sounds")
## Played when the mouse hovers any menu button. Drop an AudioStream here in the inspector; null = silent.
@export var hover_sound: AudioStream
## Played when any menu button is clicked. Drop an AudioStream here; null = silent.
@export var click_sound: AudioStream
## Volume (dB) for the menu hover/click sounds.
@export var ui_sound_volume_db: float = 0.0
