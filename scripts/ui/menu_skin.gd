class_name MenuSkin
extends Resource

## The ARTIST'S menu skin — ONE Resource that reskins every menu without touching code. Edit
## resources/ui/menu_skin.tres in the inspector (or assign a different .tres / call MenuStyle.set_skin)
## to change the whole game's menu look: drop a PNG into background_texture for a custom backdrop,
## recolour the palette, swap fonts, hand your own StyleBox to panel_style to fully replace the panel
## chrome — or fill the "Widget art" groups below with per-state StyleBoxes/textures to replace the
## generated look of every button, slider, toggle, tab, meter, text field, scrollbar and tooltip in the
## game. MenuStyle (autoload) reads this and builds the live Theme every menu uses; every slot is optional
## and falls back to the flat generated look, so art can land piecemeal.

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
## Primary menu text — PANEL ink: it colours text sitting on the menu panel/card. The shipped skin runs it
## DARK (the artist's plum on the olive panel), so a surface that draws over the WORLD or the dark
## start-menu background must pin its own light ink instead of consuming this: dialogue line text
## (DialogueSettings.dialogue_text_color), the start menu's quote/attribution labels, the grid tiles'
## stack-count badge (tile_count_color, below — it paints over ITEM ART in a dark cell, not on the panel).
@export var text_color: Color = Color(0.92, 0.92, 0.95)
## Secondary / hint / dim text. Same PANEL-ink caveat as text_color.
@export var text_dim_color: Color = Color(1.0, 1.0, 1.0, 0.45)
## The single ACCENT — selection bar, focused control, active tab, slider fill.
@export var accent_color: Color = Color(0.95, 0.85, 0.4)
## Currency (zorkmid) text.
@export var gold_color: Color = Color(0.95, 0.85, 0.4)
## Warnings (over-encumbered, can't-afford).
@export var danger_color: Color = Color(1.0, 0.55, 0.4)
## Text colour of a disabled control. (With no button art, hover styling is generated from accent_color —
## MenuStyle._accent_bar; once button art lands, the "Widget art — buttons" hover slot + ink knobs own it.)
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

@export_group("Text drop shadow")
## THE SAME LIGHT THE ART IS BAKED WITH. The panel/button/tooltip/dialogue PNGs carry a drop shadow baked
## into a transparent pad (scripts/tools/bake_ui_shadows.gd — straight down, never diagonal); these three
## knobs put the matching shadow under menu TEXT so the chrome and the type read as one lit object instead
## of two. Keep them in step with that tool's light: a text shadow that leans sideways while the panels drop
## straight down is the exact disagreement the bake exists to kill.
##
## Shadow ink. ⚠ ALPHA 0 = NO TEXT SHADOW — the same alpha-as-null-sentinel the button_font_*_color knobs
## use, so an art-less skin stays flat and the shipped skin opts in. Author it as a DARK, mostly-transparent
## ink: it has to read under the dark plum panel ink AND under the light ink that off-panel surfaces pin for
## themselves (the start-menu quote, the dialogue line, the grid tiles' count badge).
@export var text_shadow_color: Color = Color(0, 0, 0, 0)
## How far the shadow falls, in CANVAS pixels (the 792x444 base — the 0.5 stretch doubles it on screen, so 1
## here is the smallest useful drop and already reads clearly). Keep X at 0: that is what "straight down"
## means, and it is the whole point of this group.
##
## ⚠ WHAT THIS REACHES, AND WHAT IT CANNOT. Godot 4.7 gives font-shadow theme items to Label, RichTextLabel
## and TooltipLabel and to NOTHING ELSE — Button, TabBar/TabContainer and LineEdit never read one. So menu
## text wears this shadow (every title, hint, options row, list column, stat/price/wallet readout), but
## BUTTON CAPTIONS, the two tab strips and the four text fields do not, and cannot without re-drawing their
## glyphs by hand. That is deliberate, not an oversight: the shipped skin paints captions DARK on the LIGHT
## parchment button art, where a dark drop shadow is very nearly invisible anyway, while panel Labels are
## plum on mid-dark olive, where it reads. ⚠ Setting `font_shadow_color` on the `Button` theme type SUCCEEDS
## and does nothing — Theme.has_color() will even confirm it is there. Don't be fooled into "fixing" it that way.
@export var text_shadow_offset: Vector2i = Vector2i(0, 1)
## Softness — grows the shadow outward by this many px before it falls off (Godot's `shadow_outline_size`).
## 0 = a crisp offset copy, which is what the pixel-font look wants; 1 already reads as a blur at this scale.
## ⚠ TooltipLabel has no such theme item in Godot 4.7, so the tooltip card's text ignores this one knob.
@export var text_shadow_blur: int = 0

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
## Width FLOOR for one player-menu tab button (Inventory/Stats/Implants/Map/Reputation/Journal). The strip
## stretches to the panel's width; this only guards pathological narrow canvases. Keep the SIX
## tabs' total (6x + separations) under the 0.12-margin panel width at the smallest canvas — at the shipped
## 72 that is 432 + 30 vs the ~602 px the 792-wide canvas leaves inside the band, so a seventh tab is the
## next thing that would need this floor lowered.
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
## Options: the HSlider track's minimum width on a full-width (single-column) settings row. A FLOOR — the
## slider is EXPAND_FILL and takes whatever the row has left; this only decides how narrow the page's
## MINIMUM is, i.e. how small the panel may get before the slider starts pushing back.
@export var slider_width: int = 120
## Options: the same floor inside a two-up dense column (the Accessibility tab), where two full-width rows
## have to share one panel. The half-column fit at the 792x444 canvas: the Options panel's 0.07..0.93 band
## is 681px, the artist frame stylebox eats 72 of it, and the page's own insets another 20
## (options_menu.PAGE_MARGIN each side — the right one now split between air and the always-visible
## scrollbar's gutter, which is why widening scrollbar_width costs the columns nothing) — so the two
## columns plus their 10px gutter must fit ~589px. 110 (dense label) + 10 + 90 + 10 + 56 (readout) = 276 per
## column -> 562. At the drawn width the slider still gets ~103px, so this floor never binds in practice; it
## exists so the page's MINIMUM stays inside the panel instead of growing the card when Accessibility opens.
@export var slider_width_dense: int = 90
## Options: the keybind rebind buttons — a fixed-width right-aligned column, not full-width bars. 120 fits
## the widest real ENGLISH binding name ("Mouse Wheel Up" ≈ 119px incl. the 10+10 margins of the shipped
## art button boxes — the parchment frames' content margins are 1px wider per edge than the generated 9+9,
## so the slack here is now exactly 1px; a wider future art box must re-verify this fit). The button is
## cap_button()'d so anything longer (the armed PlayerText.OPTIONS_BIND_PROMPT, an exotic key name) clips
## instead of growing the button and shifting the column. The Controls tab lays out single-column, so
## extra width here comes out of the EXPAND_FILL name label.
@export var rebind_button_width: int = 120
## Options: left setting-name column floor on a full-width row, so every tab's controls start on one rail.
@export var setting_label_col_width: int = 130
## Options: setting-name column floor inside a two-up dense column (the Accessibility tab). The half-column
## fit is English-measured: 110 + 10 + slider_width_dense (90) + 10 + slider_readout_width (56) = 276, and two
## of those plus the 10px gutter and the page's 20px of insets (see slider_width_dense — the scrollbar rides
## inside them, it does not add to them) fit the panel's ~609px inner width — the full
## setting_label_col_width (130) would overflow it and grow the whole Options card. A locale growing either
## label width must re-verify that sum (tests/test_menu_layout_stability.gd fails if it stops fitting).
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

## ------------------------------------------------------------------------------------------------------
## WIDGET ART — the UI artist's drop-in surface. Every slot below is OPTIONAL: null keeps the generated
## flat look built from the Palette group, so the skin works with zero art and each delivered asset can
## land one at a time. To use a PNG, wrap it in a StyleBoxTexture (Inspector: New StyleBoxTexture, drop
## the texture in, set its Texture Margins for 9-patch stretch) — a StyleBoxFlat also works for hand-set
## colours per state. Icon slots (slider thumb, toggles) take a bare Texture2D. MenuStyle consumes these
## when it builds the shared Theme, so ONE slot reskins that widget in EVERY menu at once — including
## menus authored as their own .tscn scenes, since the Theme flows down from each menu root.
## ------------------------------------------------------------------------------------------------------

@export_group("Widget art — buttons")
## Button at rest. The generated default is TRANSPARENT (text-forward buttons); artist art here gives every
## menu button a visible body. Sized by content — deliver a 9-patch so any caption width works.
@export var button_normal: StyleBox
## Button under the mouse (default: a 2px accent bar on the left, no fill).
@export var button_hover: StyleBox
## Button held down (default: accent bar + faint accent fill). SHIPPED STAND-IN (2026-08-12): the artist's
## "Selected" frame arrived byte-identical to "Normal", so the shipped box wears button_frame_selected.png
## (currently that copy) darkened via modulate_color — when the real Selected art lands, replace the PNG
## and clear the modulate.
@export var button_pressed: StyleBox
## Button holding keyboard/controller focus (default: same as pressed). Keep it visually distinct from
## normal — this is the only "you are here" cue when navigating without a mouse. ⚠ Godot draws this box
## as an OVERLAY on top of the current STATE box (normal/hover/pressed/disabled), not instead of it — so
## deliver a transparent-centred ring/outline here, never an opaque body: an opaque focus box hides the
## state art underneath and paints a body onto focused DISABLED buttons (the heal card seeds focus on a
## Heal button that can be disabled — that is how this was caught). The shipped skin uses a 1px accent
## ring (a StyleBoxFlat authored in the .tres) over the parchment button art for exactly this reason.
@export var button_focus: StyleBox
## Button that can't be clicked. Fallback follows the TOGGLE-ICON rule: null with button_normal art set =
## MenuStyle derives a DIMMED copy of the rest body (an enable/disable flip greys the same body instead of
## popping it out of existence); null on an art-less skin = transparent, the disabled_text_color grey talks.
@export var button_disabled: StyleBox

## OPTIONAL button caption inks, one per state — for when button art needs its own text colours. The
## palette-derived defaults (text_dim/text/accent) were chosen for TRANSPARENT buttons on the dark panel;
## an opaque light body (the shipped parchment frames) makes them unreadable, so any knob with alpha > 0
## replaces the derived colour for that state (MenuStyle._ink). Alpha 0 = unset — a fully transparent
## caption is never a real want, so alpha doubles as the null sentinel, the Color twin of the null-StyleBox
## fallback rule above. These colour ONLY real theme Buttons: the player-menu tab strip pins its hover/
## pressed caption ink back to text_color (its hover visuals are tab-language chrome on the PANEL, not
## button art — see PlayerMenus.build_tab_strip), and Labels never consult Button colours.
@export var button_font_color: Color = Color(0, 0, 0, 0)
## Ink under the mouse (derived default: text_color).
@export var button_font_hover_color: Color = Color(0, 0, 0, 0)
## Ink while held down, and for hover_pressed (derived default: accent_color).
@export var button_font_pressed_color: Color = Color(0, 0, 0, 0)
## Ink holding keyboard/controller focus (derived default: text_color).
@export var button_font_focus_color: Color = Color(0, 0, 0, 0)
## Ink of a disabled caption (derived default: disabled_text_color). The shipped skin authors a muted
## dark olive here because its disabled BODY is the derived dimmed-parchment copy of the rest art (see
## button_disabled) — the light disabled_text_color would wash out on it.
@export var button_font_disabled_color: Color = Color(0, 0, 0, 0)

@export_group("Widget art — toggles")
## CheckButton/CheckBox ON art (default: a generated 20x10 switch). All four slots swap together —
## deliver the full set or none, or an ON without an OFF will read as two different controls.
@export var toggle_on_icon: Texture2D
## Toggle OFF art.
@export var toggle_off_icon: Texture2D
## Toggle ON while the row is disabled (null with toggle_on_icon set = reuses toggle_on_icon).
@export var toggle_on_disabled_icon: Texture2D
## Toggle OFF while the row is disabled (null with toggle_off_icon set = reuses toggle_off_icon).
@export var toggle_off_disabled_icon: Texture2D

@export_group("Widget art — sliders")
## The empty slider track (default: a thin 12%-white bar).
@export var slider_track: StyleBox
## The filled part of the track, left of the thumb (default: a thin accent bar).
@export var slider_fill: StyleBox
## The draggable thumb (default: a generated 3x10 accent bar).
@export var slider_grabber: Texture2D

@export_group("Widget art — text fields")
## LineEdit (name entry / character creation) at rest.
@export var line_edit_normal: StyleBox
## LineEdit while focused/typing (default: the rest look with an accent border).
@export var line_edit_focus: StyleBox

@export_group("Widget art — meters")
## ProgressBar track (reputation standings et al).
@export var meter_background: StyleBox
## ProgressBar fill. Tinted meters (make_meter) recolour a COPY of this per row: a StyleBoxFlat by
## bg_color, a StyleBoxTexture by modulate_color — so deliver fill art in white/grey if you want the
## per-faction tints to read true.
@export var meter_fill: StyleBox

@export_group("Widget art — tabs")
## The active tab, in BOTH tab systems (the Options TabContainer and the player-menu strip). Default:
## transparent with a 2px accent underline.
@export var tab_selected: StyleBox
## An inactive tab at rest (default: transparent).
@export var tab_unselected: StyleBox
## An inactive tab under the mouse (default: TabContainer transparent / strip underline at 35%).
@export var tab_hovered: StyleBox

@export_group("Widget art — scrollbars")
## THE KNOB THAT DECIDES WHETHER A SCROLLBAR EXISTS AT ALL — the bar's thickness in canvas px. A ScrollBar
## takes its cross-axis size from the CONTENT MARGINS of its track box and from nothing else, so MenuStyle
## stamps this number onto whichever box the bar ends up wearing — the generated one AND an artist's, which
## would otherwise re-collapse the bar the day a margin-less PNG lands. Until 2026-08-27 no box carried
## margins and every scrollbar in the game drew ZERO px wide: not faint, not clipped — absent, and
## un-grabbable. Four "this page silently hides half its rows" bugs were that one defect (Options→Controls
## showed 4 of 44 bindings, Accessibility 14 of 33, character creation 4 of 6 stats, the Stats tab cut a
## sentence mid-word).
## ⚠ ALSO A LAYOUT BUDGET, not just paint: a ScrollContainer RESERVES this many px beside its content, so a
## page with no width to spare must pay for the bar out of its own gutter rather than out of its rows —
## options_menu._add_tab pulls its right page margin in by exactly this number for that reason. Retuning it
## therefore retunes those hosts; re-verify tests/test_menu_layout_stability.gd after a change.
## 0 = stamp nothing and let the boxes' own margins decide (an artist delivering a full-metric 9-patch).
@export var scrollbar_width: int = 8
## Scrollbar track (default: a flat bar in scrollbar_track_color).
@export var scrollbar_track: StyleBox
## Scrollbar thumb. ONE slot for all three states, like the slider's thumb: deliver it and the bar stops
## lighting up under the mouse (default: a flat bar in scrollbar_grabber_color that goes ACCENT on
## hover/drag — the same "this control is live" language the focus ring and the active tab speak).
@export var scrollbar_grabber: StyleBox
## OPTIONAL track ink — ⚠ ALPHA 0 = derive (the same null sentinel the button_font_*_color knobs use): a
## faint wash of text_color. Consulted only while scrollbar_track is empty; a delivered StyleBox carries its
## own colour. Author it against the PANEL, not the screen: the shipped skin runs a DARK ink on LIGHT
## parchment, which is exactly where the old 5%-alpha track would have been invisible even at a real width.
@export var scrollbar_track_color: Color = Color(0, 0, 0, 0)
## OPTIONAL resting-thumb ink — same alpha-0-derives sentinel, same panel-contrast rule. The thumb is the
## affordance ("this page has more"), so keep it well clear of the track: 75%-alpha text_color by default,
## roughly four times the track's wash.
@export var scrollbar_grabber_color: Color = Color(0, 0, 0, 0)

@export_group("Widget art — misc")
## The hairline HSeparator/VSeparator (default: a 1px 8%-white top border).
@export var separator_style: StyleBox
## The tooltip card — BOTH the custom in-viewport cursor tip and native theme tooltips (default: a
## near-black bordered panel).
@export var tooltip_panel: StyleBox
## The DIALOGUE box's background (the bottom conversation panel, DialogueView). Its OWN slot rather than
## the theme panel on purpose: this box is short and very wide (~632x160 on the 792x444 canvas) and floats
## over the 3D world, so the full screen-card art in panel_style would drown it — the same reason compact
## confirm cards take make_plain_panel_style. null = the box keeps its background-LESS look: outlined text
## straight over the world, with only the response menu backed by the plain generated panel (what it wore
## before any art landed, and still the fallback for an art-less skin).
## ⚠ Art with a TRANSPARENT cut-out (the shipped notch in the bottom-left corner) only survives 9-patching
## if the texture margin on that side CONTAINS the whole cut — the corner cell is the one region drawn at
## native size; anything spilling into a stretched edge/centre cell smears. The matching content margin
## must clear it too, or text/choice buttons land over the hole. See resources/ui/menu_skin.tres sb_dialogue.
@export var dialogue_panel: StyleBox
## Whether the dialogue box actually WEARS the dialogue_panel art. A GATE rather than emptying the slot,
## on purpose: the slot keeps the artist's authored art (and its tests / shadow-bake target) while the
## shipped look is the box-LESS one — outlined text + per-row beds straight over the 3D world, 2026-08-24.
## Flip this back on to restore the olive slab without re-wiring anything.
@export var dialogue_panel_enabled: bool = true
## The dialogue RESPONSE ROW's rest-state bed — a translucent near-black plate behind each choice row.
## Rest-state, not hover-state, deliberately: the dialogue camera centres+zooms the LIT speaker into the
## column's region, so bare outlined text would sit on the brightest surface in the frame. null = the
## generated default (MenuStyle.make_dialogue_choice_normal).
@export var dialogue_choice_normal: StyleBox
## The response row's hover/selected bed — the rest bed raised, plus a 3px left rule in the accent gold.
## null = the generated default (MenuStyle.make_dialogue_choice_hover).
@export var dialogue_choice_hover: StyleBox
## Row ink for the dialogue response rows. NOT button_font_color (menu-PANEL ink, dark since the plum
## palette): these rows float over the 3D world on translucent beds, so the ink must stay light — the
## same rule dialogue_text_color / tile_count_color follow.
@export var dialogue_choice_font_color: Color = Color(0.94, 0.93, 0.87)
## Tint of a response row whose SKILL CHECK the player passes (the "[Streetwise 6]"-labelled rows).
## Gold-adjacent, but its own slot: gate state must be re-inkable without moving the accent.
@export var dialogue_choice_gate_pass_color: Color = Color(0.95, 0.85, 0.4)
## Tint of a FAILED non-stat gate row (reputation/perk/item/quest — still selectable, routes to the fail
## branch). Only painted while DialogueSettings.show_failed_gate_tags is on; muted terracotta so it reads
## as "risky", never as the hostile red.
@export var dialogue_choice_gate_fail_color: Color = Color(0.85, 0.55, 0.4)

@export_group("Grid tiles")
## The tetris-grid stack tiles (grid_tile.gd / grid_inventory_view.gd) — the inventory/loot/shop cells.
## Equipped-item border. Defaults to the accent gold — the designer decides any divergence from the
## ammo/money category gold.
@export var equipped_border_color: Color = Color(0.95, 0.85, 0.4)
## Border tint of a consumable stack's tile (the non-weapon "use it" category).
@export var tile_consumable_color: Color = Color(0.45, 0.80, 0.52)
## The thin ring the overlay draws around the hovered stack.
@export var tile_hover_ring_color: Color = Color(1, 1, 1, 0.85)
## Ink of a tile's stack-count / money badge ("x3", "12.50"). A GRID ink, deliberately NOT text_color: the
## badge paints over the ITEM ART inside a dark tinted cell, never on the menu panel, so it must stay LIGHT
## even while the panel palette runs dark (the shipped plum) — the same rule the HUD labels follow, and the
## same white the hotbar's slot text wears (HudSettings.hotbar_filled_color). Drawn over a black outline, so
## it reads on any icon.
@export var tile_count_color: Color = Color(0.92, 0.92, 0.95)
## Alpha the source tile dims to while its stack is being dragged.
@export var drag_source_dim_alpha: float = 0.35

## ------------------------------------------------------------------------------------------------------
## SOUNDS — the menu's whole audio vocabulary, one AudioStream slot per SEMANTIC event. Every slot is
## OPTIONAL (null = that event is silent), so audio can land one cue at a time exactly like the widget art.
## MenuStyle owns the players and every play site; a screen NEVER preloads a clip or builds its own
## AudioStreamPlayer — it calls MenuStyle.play_open() / play_back() / play_tab() / … (see menu_style.gd's
## "menu sounds" block). That is what keeps the vocabulary consistent across 20 screens and reskinnable from
## this one resource.
##
## THE GRAMMAR (why there are several cues and not one click): the player should be able to tell what
## happened with their eyes shut. Sideways moves (tab/step) sound different from depth moves (open/back), a
## cue that SPENDS something (money, a level, a save slot) is heavier than an ordinary confirm, and an action
## the game REFUSED must never sound like one it accepted. Keep new cues inside that grammar rather than
## adding a per-screen one-off.
## ------------------------------------------------------------------------------------------------------

@export_group("Sounds")
## Played when the mouse hovers any menu button — the highest-frequency cue in the game, so keep it SHORT
## and quiet. Auto-wired to every button under a menu root; no per-button code. null = silent.
@export var hover_sound: AudioStream
## Played when any menu button is clicked. The DEFAULT confirm — a button with a more specific meaning
## (back, tab, commit) overrides it via MenuStyle.set_button_sound instead of stacking a second cue.
@export var click_sound: AudioStream
## Played when a menu comes up COLD. NEVER on a tab/page swap within an already-open menu group — that is
## tab_sound. This is the longest cue in the set, so it is deliberately reserved for a real entrance.
@export var open_sound: AudioStream
## Played on back / close / cancel: the last menu of a group closing, an Esc, a dismissed confirm dialog.
@export var back_sound: AudioStream
## Played when the view swaps SIDEWAYS without opening or closing — the player-menu tab strip, the Options
## and character-creation tab bars, the shop's sort cycle, the payment-rail flip.
@export var tab_sound: AudioStream
## Played when a value steps DOWN/LEFT (a cycler's prev arrow, a minus button, a slider tick downward).
## Keep it matched with step_right_sound — a mismatched pair reads as a broken control, not as direction.
@export var step_left_sound: AudioStream
## Played when a value steps UP/RIGHT. The step_left_sound twin — see its note.
@export var step_right_sound: AudioStream
## Played on a HEAVY commit: money spent, a level taken, a save written, a new run stamped. Deliberately
## NOT for ordinary confirms — if everything is heavy, nothing is.
@export var commit_sound: AudioStream
## Played when the game REFUSED what the player just asked for: can't afford it, out of stock, backpack
## full, nothing to withdraw, an illegal chess move, a stat already at its floor. This is the ONE cue with a
## DERIVED fallback — leave it null and MenuStyle plays back_sound at denied_pitch_scale instead, so a
## refusal is audible out of the box without a ninth clip to author. Assign a real clip to override.
##
## Its whole job is to be the sound of NOTHING HAPPENING, which is why it must never be reused for a
## de-escalation the game did honour (putting a weapon away, dismissing a confirm) — those are back_sound.
@export var denied_sound: AudioStream

@export_subgroup("Volume")
## MASTER trim (dB) for every menu sound. Each per-cue trim below is ADDED to this, so one knob moves the
## whole UI mix. (Kept at this exact name because MenuStyle and tests/test_options_menu.gd both read it.)
@export var ui_sound_volume_db: float = 0.0
## Per-cue trim (dB) added to ui_sound_volume_db. The shipped clips are NOT normalised against each other
## (they span 0.10s to 1.66s), and they land on the "sfx" bus which already carries its own trim plus a
## distortion insert — so levelling them by ear is a designer job here, never an import-time normalize.
@export var hover_volume_db: float = 0.0
## Per-cue trim for click_sound — see hover_volume_db.
@export var click_volume_db: float = 0.0
## Per-cue trim for open_sound — the longest cue; usually the first one that needs pulling down.
@export var open_volume_db: float = 0.0
## Per-cue trim for back_sound.
@export var back_volume_db: float = 0.0
## Per-cue trim for tab_sound.
@export var tab_volume_db: float = 0.0
## Per-cue trim for the step_left/step_right PAIR — ONE knob on purpose, so the two directions can never
## drift to different loudnesses (which reads as one arrow being broken).
@export var step_volume_db: float = 0.0
## Per-cue trim for commit_sound.
@export var commit_volume_db: float = 0.0
## Per-cue trim for denied_sound (or for the pitched back_sound it falls back to).
@export var denied_volume_db: float = -2.0
## Playback pitch for the DERIVED denial cue — only consulted while denied_sound is null, i.e. when the
## refusal is being spoken by back_sound. Detuning it is what stops "you can't do that" from sounding
## identical to "menu closed": below 1.0 the same clip reads as a wrong-buzzer, not as a door shutting.
## Applies to an assigned denied_sound too, so an authored clip can be tuned here without re-exporting it.
@export_range(0.25, 2.0, 0.01) var denied_pitch_scale: float = 0.75

@export_subgroup("Retrigger limits")
## Minimum seconds between two hover ticks. Sweeping the cursor down a 12-row list fires a dozen
## mouse_entered signals within a few frames; ticks inside this gap are DROPPED (never queued), which is
## what turns a machine-gun into a texture. 0 = no limit.
@export var hover_min_interval: float = 0.05
## Minimum seconds between two value-step ticks. Tames keyboard AUTO-REPEAT on the Options cyclers (which
## echo at the OS repeat rate) and fast slider drags. Roughly half the step clip's length is a good floor.
@export var step_min_interval: float = 0.08
## How many ticks a FULL slider sweep should produce, whatever that slider's own step is. MenuStyle
## quantises value_changed into this many buckets before playing, so Max FPS (hundreds of steps) and a
## 0..1 accessibility slider (a handful) both feel identical instead of one buzzing and one going silent.
@export var slider_tick_count: int = 12
