extends GutTest

## The UI ARTIST'S drop-in surface (MenuSkin "Widget art" groups + MenuStyle consuming them): every menu
## widget's look can be replaced by dropping StyleBoxes/textures into resources/ui/menu_skin.tres — no code.
## Pinned here: the slots exist, an artist StyleBox actually lands in the built Theme (as a DUPLICATE, so
## theme-side mutation never bleeds back into the saved .tres), every empty slot falls back to the generated
## flat look (a BARE skin must keep the pre-art look — the shipped .tres now carries the button-frame art,
## which the shipped-skin test below pins separately), the button caption INK knobs (alpha-0 sentinel =
## palette-derived), the toggle disabled-variant fallback, and the two non-theme consumers (make_meter's
## per-row tint, the player-menu tab strip helpers — all THREE strip states, since the strip must never
## fall through to theme-Button chrome now that the Button slots carry art).
##
## MenuStyle is exercised as a bare load().new() + rebuild() — never _ready() (that builds the tip layer,
## sound players and a tree-global node_added hook; rebuild() alone owns the Theme, which is what's under test).

const STYLE := "res://scripts/ui/menu_style.gd"

var _ms


func before_each() -> void:
	_ms = load(STYLE).new()
	_ms.skin = MenuSkin.new()  # a pristine skin, not the shipped .tres — tests author their own art
	_ms.rebuild()


func after_each() -> void:
	if _ms != null:
		_ms.free()
		_ms = null


func test_skin_exposes_every_artist_art_slot() -> void:
	# The artist-facing contract: these names are what the AUTHORING_GUIDE tells the designer to fill.
	var s := MenuSkin.new()
	for field in ["button_normal", "button_hover", "button_pressed", "button_focus", "button_disabled",
			"toggle_on_icon", "toggle_off_icon", "toggle_on_disabled_icon", "toggle_off_disabled_icon",
			"slider_track", "slider_fill", "slider_grabber",
			"line_edit_normal", "line_edit_focus", "meter_background", "meter_fill",
			"tab_selected", "tab_unselected", "tab_hovered",
			"scrollbar_track", "scrollbar_grabber", "separator_style", "tooltip_panel", "dialogue_panel"]:
		assert_true(field in s, "MenuSkin exposes artist slot %s" % field)
	s = null


func test_empty_slots_keep_the_generated_flat_look() -> void:
	# A skin with no widget art (MenuSkin.new(), or any future alternate .tres shipping art-less) must
	# yield the same generated StyleBoxFlat theme as before the art surface existed.
	for state in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		assert_true(_ms.theme.get_stylebox(state, &"Button") is StyleBoxFlat,
			"Button %s falls back to the generated flat stylebox" % state)
	assert_true(_ms.theme.get_stylebox(&"slider", &"HSlider") is StyleBoxFlat, "slider track generated")
	assert_true(_ms.theme.get_stylebox(&"fill", &"ProgressBar") is StyleBoxFlat, "meter fill generated")
	assert_true(_ms.theme.get_icon(&"grabber", &"HSlider") is ImageTexture, "slider thumb is the generated 3x10 bar")
	assert_true(_ms.theme.get_icon(&"checked", &"CheckButton") is ImageTexture, "toggle is the generated switch")


func test_artist_stylebox_lands_in_the_theme_for_every_widget() -> void:
	# One artist box per slot; each must come back out of the built Theme for its widget/state.
	var slots := {
		"button_normal": [&"normal", &"Button"], "button_hover": [&"hover", &"Button"],
		"button_pressed": [&"pressed", &"Button"], "button_focus": [&"focus", &"Button"],
		"button_disabled": [&"disabled", &"Button"],
		"slider_track": [&"slider", &"HSlider"], "slider_fill": [&"grabber_area", &"HSlider"],
		"line_edit_normal": [&"normal", &"LineEdit"], "line_edit_focus": [&"focus", &"LineEdit"],
		"meter_background": [&"background", &"ProgressBar"], "meter_fill": [&"fill", &"ProgressBar"],
		"tab_selected": [&"tab_selected", &"TabContainer"], "tab_unselected": [&"tab_unselected", &"TabContainer"],
		"tab_hovered": [&"tab_hovered", &"TabContainer"],
		"scrollbar_track": [&"scroll", &"VScrollBar"], "scrollbar_grabber": [&"grabber", &"VScrollBar"],
		"separator_style": [&"separator", &"HSeparator"], "tooltip_panel": [&"panel", &"TooltipPanel"],
	}
	for slot in slots:
		_ms.skin.set(slot, StyleBoxTexture.new())  # a texture box is what a PNG-delivering artist authors
	_ms.rebuild()
	for slot in slots:
		var name: StringName = slots[slot][0]
		var kind: StringName = slots[slot][1]
		assert_true(_ms.theme.get_stylebox(name, kind) is StyleBoxTexture,
			"artist %s replaces the generated %s/%s stylebox" % [slot, kind, name])


func test_artist_art_is_duplicated_into_the_theme_never_shared() -> void:
	# A theme consumer that mutates its stylebox must never write through into the artist's saved .tres
	# sub-resource (a shared edit would bleed across widgets and back into the skin file on save).
	var art := StyleBoxTexture.new()
	_ms.skin.button_normal = art
	_ms.rebuild()
	assert_ne(_ms.theme.get_stylebox(&"normal", &"Button"), art,
		"the theme carries a DUPLICATE of the artist stylebox, not the .tres sub-resource itself")


func test_artist_slider_thumb_and_toggle_icons_win() -> void:
	var thumb := PlaceholderTexture2D.new()
	var on_tex := PlaceholderTexture2D.new()
	var off_tex := PlaceholderTexture2D.new()
	_ms.skin.slider_grabber = thumb
	_ms.skin.toggle_on_icon = on_tex
	_ms.skin.toggle_off_icon = off_tex
	_ms.rebuild()
	assert_eq(_ms.theme.get_icon(&"grabber", &"HSlider"), thumb, "artist slider thumb replaces the generated bar")
	assert_eq(_ms.theme.get_icon(&"checked", &"CheckBox"), on_tex, "artist ON art replaces the generated switch")
	assert_eq(_ms.theme.get_icon(&"unchecked", &"CheckBox"), off_tex, "artist OFF art too")
	# The disabled variants were NOT delivered: they reuse the enabled art rather than snapping back to the
	# generated switch for one state (which would read as two different controls).
	assert_eq(_ms.theme.get_icon(&"checked_disabled", &"CheckBox"), on_tex,
		"missing disabled ON variant falls back to the artist's enabled ON art")
	assert_eq(_ms.theme.get_icon(&"unchecked_disabled", &"CheckBox"), off_tex,
		"missing disabled OFF variant falls back to the artist's enabled OFF art")


func test_make_meter_tints_a_copy_of_the_artist_fill() -> void:
	# Reputation rows tint their meters per faction. With artist fill art the tint must land on a COPY
	# (StyleBoxFlat.bg_color / StyleBoxTexture.modulate_color), leaving the skin's sub-resource pristine.
	var art := StyleBoxFlat.new()
	art.bg_color = Color.WHITE
	_ms.skin.meter_fill = art
	_ms.rebuild()
	var bar: ProgressBar = _ms.make_meter(Color.RED)
	var fill := bar.get_theme_stylebox(&"fill") as StyleBoxFlat
	assert_eq(fill.bg_color, Color.RED, "the tint recolours the artist flat fill")
	assert_ne(fill, art, "...on a duplicate")
	assert_eq(art.bg_color, Color.WHITE, "the skin's own sub-resource is untouched")
	bar.free()
	var tex_art := StyleBoxTexture.new()
	_ms.skin.meter_fill = tex_art
	var bar2: ProgressBar = _ms.make_meter(Color.GREEN)
	var fill2 := bar2.get_theme_stylebox(&"fill") as StyleBoxTexture
	assert_eq(fill2.modulate_color, Color.GREEN, "a texture fill tints via modulate_color instead")
	assert_eq(tex_art.modulate_color, Color.WHITE, "again on a copy — the artist art keeps its authored modulate")
	bar2.free()


func test_tab_strip_helpers_wear_the_same_artist_tab_art() -> void:
	# The player-menu strip is hand-built Buttons, not a TabContainer — its helpers must consume the SAME
	# tab slots so one delivered tab art skins both tab systems (one visual language, one artist file).
	assert_true(_ms.make_active_tab_style() is StyleBoxFlat, "no art -> the generated underline styles")
	assert_true(_ms.make_inactive_tab_style() is StyleBoxFlat, "no art -> the generated transparent rest state")
	var sel := StyleBoxTexture.new()
	var hov := StyleBoxTexture.new()
	var uns := StyleBoxTexture.new()
	_ms.skin.tab_selected = sel
	_ms.skin.tab_hovered = hov
	_ms.skin.tab_unselected = uns
	var active: StyleBox = _ms.make_active_tab_style()
	var hover: StyleBox = _ms.make_hover_tab_style()
	var rest: StyleBox = _ms.make_inactive_tab_style()
	assert_true(active is StyleBoxTexture and active != sel, "active tab wears a duplicate of tab_selected")
	assert_true(hover is StyleBoxTexture and hover != hov, "hovered tab wears a duplicate of tab_hovered")
	assert_true(rest is StyleBoxTexture and rest != uns, "resting inactive tab wears a duplicate of tab_unselected")


func test_button_ink_knobs_default_to_the_palette_derived_colours() -> void:
	# Alpha 0 = unset: a pristine skin's Button caption colours must be EXACTLY the palette-derived set
	# the theme always used (text_dim / text / accent / text / disabled_text), so art-less skins repaint
	# identically. The knobs only bite when an ink is authored with alpha > 0.
	var s: MenuSkin = _ms.skin
	assert_eq(_ms.theme.get_color(&"font_color", &"Button"), s.text_dim_color, "rest ink derives from text_dim_color")
	assert_eq(_ms.theme.get_color(&"font_hover_color", &"Button"), s.text_color, "hover ink derives from text_color")
	assert_eq(_ms.theme.get_color(&"font_pressed_color", &"Button"), s.accent_color, "pressed ink derives from accent_color")
	assert_eq(_ms.theme.get_color(&"font_focus_color", &"Button"), s.text_color, "focus ink derives from text_color")
	assert_eq(_ms.theme.get_color(&"font_hover_pressed_color", &"Button"), s.accent_color, "hover_pressed rides the pressed ink")
	assert_eq(_ms.theme.get_color(&"font_disabled_color", &"Button"), s.disabled_text_color, "disabled ink derives from disabled_text_color")


func test_authored_button_ink_replaces_the_derived_colour_per_state() -> void:
	# An authored ink (alpha > 0) wins for ITS state only — the others keep deriving, so inks can land
	# per-state exactly like the art slots do.
	var ink := Color(0.2, 0.15, 0.1, 1.0)
	_ms.skin.button_font_color = ink
	_ms.rebuild()
	assert_eq(_ms.theme.get_color(&"font_color", &"Button"), ink, "authored rest ink lands in the theme")
	assert_eq(_ms.theme.get_color(&"font_hover_color", &"Button"), _ms.skin.text_color,
		"hover ink still derives while its knob is unset")
	var pressed_ink := Color(0.4, 0.3, 0.1, 1.0)
	_ms.skin.button_font_pressed_color = pressed_ink
	_ms.rebuild()
	assert_eq(_ms.theme.get_color(&"font_pressed_color", &"Button"), pressed_ink, "authored pressed ink lands")
	assert_eq(_ms.theme.get_color(&"font_hover_pressed_color", &"Button"), pressed_ink,
		"hover_pressed follows the authored pressed ink — one knob for both held states")


func test_shipped_skin_carries_the_button_frame_art() -> void:
	# The wiring contract for the ARTIST'S FIRST DELIVERY (2026-08-12, the parchment button frames): the
	# shipped .tres carries a textured box in normal/hover/pressed, a transparent focus RING (never a
	# textured body — asserted below with the why), dark caption inks for all five states (disabled's
	# body is the code-derived dimmed rest art, so its ink darkens too), and IDENTICAL content margins
	# across the boxes so a button can't resize as it is hovered/pressed (menus-don't-shift discipline).
	# KNOWN STAND-IN: the artist's "Selected" file arrived byte-identical to "Normal", so
	# button_frame_selected.png is currently a copy and the pressed box darkens it via modulate_color —
	# when real Selected art lands, replace that PNG and clear the modulate.
	var shipped: MenuSkin = load("res://resources/ui/menu_skin.tres")
	assert_not_null(shipped, "the shipped skin loads")
	var boxes: Array[StyleBox] = []
	for slot in ["button_normal", "button_hover", "button_pressed"]:
		var sb: StyleBox = shipped.get(slot)
		assert_true(sb is StyleBoxTexture, "%s carries the artist StyleBoxTexture" % slot)
		if sb is StyleBoxTexture:
			assert_not_null((sb as StyleBoxTexture).texture, "%s has its PNG assigned" % slot)
			boxes.append(sb)
	# FOCUS is the exception, by Godot's own drawing model: the focus box is an OVERLAY painted on top of
	# the current state box, so it must never carry an opaque body (it would hide hover/pressed art and
	# dress focused DISABLED buttons in a body — the heal card's focus-seeded Heal button caught this).
	# The shipped skin authors a transparent accent RING instead.
	var focus_sb: StyleBox = shipped.button_focus
	assert_true(focus_sb is StyleBoxFlat, "button_focus is the authored focus ring, not a textured body")
	if focus_sb is StyleBoxFlat:
		assert_false((focus_sb as StyleBoxFlat).draw_center,
			"the focus ring paints no center — it overlays every state, including disabled")
		boxes.append(focus_sb)
	assert_null(shipped.button_disabled,
		"disabled art stays null — MenuStyle derives its dimmed body from the rest art (the toggle-icon rule)")
	# The PANEL (the artist's rectangle revision — the first notched version was replaced 2026-08-12):
	# torn dark border ~28-32px at the baked 600x375 body, PLUS a baked drop shadow in an 8px canvas pad.
	# THE SHADOW RULE: baked shadows ride in EXPAND margins (draw-only, outside the layout rect), never in
	# content margins — texture margins cover border+pad, expand margins equal the pad, and layout metrics
	# stay shadow-independent. Same rule on the button boxes below (5px pad).
	var panel_sb: StyleBox = shipped.panel_style
	assert_true(panel_sb is StyleBoxTexture, "panel_style carries the artist panel StyleBoxTexture")
	if panel_sb is StyleBoxTexture:
		assert_not_null((panel_sb as StyleBoxTexture).texture, "panel art has its PNG assigned")
		assert_gte((panel_sb as StyleBoxTexture).texture_margin_left, 34.0,
			"panel texture margins span the torn border plus the shadow pad")
		assert_gt((panel_sb as StyleBoxTexture).expand_margin_bottom, 0.0,
			"the panel's baked shadow rides in expand margins (draw-only)")
	# The tooltip wears the SAME panel art at tooltip scale (its own small bake — the full-size panel's
	# margins would swallow a one-line tip; the compact-card lesson applied to the smallest card of all).
	assert_true(shipped.tooltip_panel is StyleBoxTexture, "tooltip_panel carries the tip-scale panel art")
	if shipped.tooltip_panel is StyleBoxTexture:
		assert_not_null((shipped.tooltip_panel as StyleBoxTexture).texture, "tip art has its PNG assigned")
	for sb in boxes:
		if sb is StyleBoxTexture:
			assert_eq(Vector2((sb as StyleBoxTexture).expand_margin_left, (sb as StyleBoxTexture).expand_margin_bottom),
				Vector2(5.0, 5.0),
				"every button state box carries the same 5px shadow expand pad (uniform shadow, zero layout cost)")
	for sb in boxes:
		assert_eq(Vector4(sb.content_margin_left, sb.content_margin_top,
				sb.content_margin_right, sb.content_margin_bottom),
			Vector4(boxes[0].content_margin_left, boxes[0].content_margin_top,
				boxes[0].content_margin_right, boxes[0].content_margin_bottom),
			"every wired state shares one content-margin metric on all four edges (no per-state resize)")
	for state_knob in ["button_font_color", "button_font_hover_color", "button_font_pressed_color",
			"button_font_focus_color", "button_font_disabled_color"]:
		assert_gt((shipped.get(state_knob) as Color).a, 0.0, "%s is authored for the opaque body" % state_knob)


func test_dialogue_panel_slot_is_null_by_default_and_hands_out_duplicates() -> void:
	# The dialogue box is the ONE art slot whose null is a look rather than a missing asset: DialogueView
	# reads the null and wears a StyleBoxEmpty, keeping the background-LESS chrome (outlined text straight
	# over the 3D world) it shipped with. So the helper must return null rather than derive a fallback.
	assert_null(_ms.make_dialogue_panel_style(),
		"an art-less skin returns null — DialogueView keeps its background-less look")
	var art := StyleBoxTexture.new()
	_ms.skin.dialogue_panel = art
	var got: StyleBox = _ms.make_dialogue_panel_style()
	assert_true(got is StyleBoxTexture, "the authored dialogue art comes back out")
	if got != null:
		assert_ne(got.get_instance_id(), art.get_instance_id(),
			"...as a DUPLICATE (the _pick rule): the caller mounts it on a Control, and mutating a shared .tres sub-resource would bleed back into the saved skin")
	# The consumer, pinned by source: DialogueView is the only reader, and this slot has no theme entry to
	# assert against (it is deliberately NOT the theme panel). If that call is renamed or moved, update
	# THIS pin — do not delete it.
	var src := FileAccess.get_file_as_string("res://scripts/dialogue/dialogue_view.gd")
	assert_true(src.contains("MenuStyle.make_dialogue_panel_style()"),
		"DialogueView backs its box with the skin's dialogue art slot")


func test_shipped_skin_carries_the_dialogue_box_art_with_its_notch_intact() -> void:
	# The artist's SECOND panel (the "alternative" background — the transparent one whose rectangle
	# revision became panel_style) dressed the dialogue box on 2026-08-12. It is baked at 0.4 of the 800px
	# master (torn border ~35px -> ~14px, right for a box that stands ~160px on the 792x444 canvas) into a
	# canvas with the house 8px shadow pad.
	var shipped: MenuSkin = load("res://resources/ui/menu_skin.tres")
	assert_not_null(shipped, "the shipped skin loads")
	var sb := shipped.dialogue_panel as StyleBoxTexture
	assert_not_null(sb, "dialogue_panel carries the artist's dialogue-box StyleBoxTexture")
	if sb == null:
		return
	assert_not_null(sb.texture, "the dialogue art has its PNG assigned")
	# THE SHADOW RULE, same as panel_style and the button boxes: the baked pad rides in EXPAND margins
	# (draw-only, outside the layout rect) so no dialogue layout metric moves with the shadow.
	assert_gt(sb.expand_margin_bottom, 0.0, "the baked shadow rides in expand margins (draw-only)")
	assert_eq(sb.expand_margin_left, sb.expand_margin_bottom, "the shadow pad is uniform on every edge")
	# THE NOTCH CONTRACT — the thing that makes this art different from every other slot. Its bottom-left
	# corner is genuinely CUT AWAY (transparent), and a 9-patch draws only the CORNER cells at native size:
	# any part of the cut that spills past texture_margin_left / texture_margin_bottom lands in a stretched
	# edge or centre cell and smears across the whole box. Probed against the real PNG so a re-bake at a
	# different scale, or a margin "tidy", fails here instead of on screen.
	var img: Image = sb.texture.get_image()
	assert_not_null(img, "the dialogue art's image is readable")
	if img == null:
		return
	var w := img.get_width()
	var h := img.get_height()
	var pad := int(sb.expand_margin_left)
	assert_lt(img.get_pixel(pad + 16, h - pad - 20).a, 0.05,
		"the bottom-left corner really is cut away — this art's whole point")
	var cut_col := int(sb.texture_margin_left)
	var leaked := 0
	for y in range(pad, h - pad):
		if img.get_pixel(cut_col, y).a < 0.98:
			leaked += 1
	assert_eq(leaked, 0,
		"the cut stops short of texture_margin_left — nothing leaks into the stretched centre columns")
	var cut_row := h - int(sb.texture_margin_bottom)
	leaked = 0
	for x in range(pad, w - pad):
		if img.get_pixel(x, cut_row).a < 0.98:
			leaked += 1
	assert_eq(leaked, 0,
		"...and stops above texture_margin_bottom — nothing leaks into the stretched bottom edge")
	# CONTENT margins must clear the cut too, or the last choice button / the continue hint paints over a
	# hole. The worst point is the content rect's bottom-LEFT corner (measured off the layout rect, which
	# sits `pad` inside the drawn art — the expand margin is draw-only).
	assert_gt(img.get_pixel(pad + int(sb.content_margin_left), h - pad - int(sb.content_margin_bottom) - 1).a, 0.98,
		"the content rect's bottom-left corner sits on solid art, never in the cut")


func test_disabled_body_derives_dimmed_from_rest_art_when_unset() -> void:
	# The toggle-icon rule applied to buttons: rest art + no disabled art -> the theme's disabled box is a
	# DIMMED duplicate of the rest box, never the generated transparent one — an enable/disable flip must
	# grey the same body, not pop it in and out of existence. (A pristine art-less skin keeps the
	# transparent generated disabled box — test_empty_slots_keep_the_generated_flat_look pins that side.)
	var art := StyleBoxTexture.new()
	art.modulate_color = Color.WHITE
	_ms.skin.button_normal = art
	_ms.rebuild()
	# Explicit type: _ms is Variant-held, so `.theme` is a Variant chain and := can infer nothing from it.
	var dis: StyleBox = _ms.theme.get_stylebox(&"disabled", &"Button")
	assert_true(dis is StyleBoxTexture, "disabled derives a textured body from the rest art")
	if dis is StyleBoxTexture:
		assert_lt((dis as StyleBoxTexture).modulate_color.get_luminance(), 1.0,
			"...dimmed via modulate, so it reads greyed-out")
		# The derive is a duplicate, so the disabled box KEEPS the rest box's content margins — a runtime
		# disabled flip must not change the button's minimum size (the card-hop / row-jitter regression a
		# 9/5 generated fallback under 10/6 art boxes would reintroduce).
		assert_eq(Vector4(dis.content_margin_left, dis.content_margin_top,
				dis.content_margin_right, dis.content_margin_bottom),
			Vector4(art.content_margin_left, art.content_margin_top,
				art.content_margin_right, art.content_margin_bottom),
			"the derived disabled box shares the rest box's content margins on all four edges")
	assert_eq(art.modulate_color, Color.WHITE, "the skin's own rest box is untouched (dim lands on a duplicate)")
	var explicit := StyleBoxFlat.new()
	_ms.skin.button_disabled = explicit
	_ms.rebuild()
	assert_true(_ms.theme.get_stylebox(&"disabled", &"Button") is StyleBoxFlat,
		"authored disabled art still wins over the derive")


func test_grid_tile_badge_keeps_its_own_light_ink_off_the_panel_palette() -> void:
	# The PANEL-ink boundary, grid side: a tile's stack-count badge ("x3", a money amount) paints over the
	# ITEM ART inside a dark tinted cell — NOT on the menu card — so it must never consume text_color. The
	# shipped skin runs a dark plum panel ink; the badge stayed the light hotbar white it always was. Same
	# family as dialogue_text_color and the start menu's quote: a surface off the panel pins its own ink.
	var shipped: MenuSkin = load("res://resources/ui/menu_skin.tres")
	assert_not_null(shipped, "the shipped skin loads")
	assert_lt(shipped.text_color.get_luminance(), 0.35, "the shipped panel ink is dark (the plum) — the premise")
	assert_gt(shipped.tile_count_color.get_luminance(), 0.7, "...and the grid badge ink is still light against it")
	assert_gt(shipped.tile_count_color.a, 0.9, "the badge ink is opaque — it reads at 22px loot cells")
	# The paint site, pinned by source: the regression this guards is a future pass "tidying" the badge back
	# onto the shared palette accessor, which would flip it dark with the panel the next time the skin does.
	# If grid_tile.gd's badge draw is renamed/moved, update THIS pin — do not delete it.
	var src := FileAccess.get_file_as_string("res://scripts/ui/grid_tile.gd")
	assert_true(src.contains("MenuStyle.skin.tile_count_color"),
		"grid_tile.gd draws the count badge with the skin's grid knob")
	assert_false(src.contains("MenuStyle.text_color()"),
		"grid_tile.gd never paints with the PANEL ink accessor")


func test_text_drop_shadow_reaches_every_theme_type_that_has_one() -> void:
	# THE TYPE HALF of the straight-overhead light (the art half is the baked PNG shadow pinned below).
	# Godot 4.7 gives font-shadow theme items to Label, RichTextLabel and TooltipLabel and to NOTHING else —
	# Button, TabBar and LineEdit never read one. Stamping it on Button "succeeds" and draws nothing, which
	# is exactly the trap this test exists to keep someone from re-introducing as a fix.
	var s := MenuSkin.new()
	s.text_shadow_color = Color(0, 0, 0, 0.5)
	s.text_shadow_offset = Vector2i(0, 2)
	_ms.skin = s
	_ms.rebuild()
	for kind in [&"Label", &"RichTextLabel", &"TooltipLabel"]:
		assert_eq(_ms.theme.get_color(&"font_shadow_color", kind), Color(0, 0, 0, 0.5),
			"%s carries the skin's text shadow ink" % kind)
		assert_eq(_ms.theme.get_constant(&"shadow_offset_x", kind), 0,
			"%s drops its shadow with no sideways lean" % kind)
		assert_eq(_ms.theme.get_constant(&"shadow_offset_y", kind), 2,
			"%s drops its shadow downward" % kind)
	s = null


func test_text_drop_shadow_is_off_until_a_skin_authors_it() -> void:
	# The alpha-0 sentinel, same rule as the button_font_*_color ink knobs: a bare skin must generate the
	# identical pre-shadow theme, so art and type can land one at a time.
	assert_eq(MenuSkin.new().text_shadow_color.a, 0.0, "an unskinned MenuSkin draws no text shadow")
	assert_eq(_ms.theme.get_color(&"font_shadow_color", &"Label").a, 0.0,
		"a bare skin's Label shadow ink is transparent — the entry exists so a reskin can turn it on")


func test_shipped_skin_drops_its_text_shadow_straight_down() -> void:
	var shipped: MenuSkin = load("res://resources/ui/menu_skin.tres")
	assert_not_null(shipped, "the shipped skin loads")
	assert_gt(shipped.text_shadow_color.a, 0.0, "the shipped skin opts INTO the text shadow")
	assert_lt(shipped.text_shadow_color.get_luminance(), 0.2, "the text shadow is a dark ink")
	assert_eq(shipped.text_shadow_offset.x, 0,
		"STRAIGHT DOWN: a sideways lean here would disagree with the baked art shadow (see the PNG test below)")
	assert_gt(shipped.text_shadow_offset.y, 0, "...and it does fall, rather than sitting under the glyph")
	# The cursor tip hangs off MenuStyle's own CanvasLayer, so NO theme reaches it and _style_tip must repeat
	# the shadow by hand. Source-pinned: without this, the tip is the one menu text surface left flat.
	var src := FileAccess.get_file_as_string("res://scripts/ui/menu_style.gd")
	assert_true(src.contains("_tip_label.add_theme_color_override(&\"font_shadow_color\", skin.text_shadow_color)"),
		"_style_tip gives the in-viewport cursor tip the same text shadow by hand")


func test_shipped_art_bakes_its_drop_shadow_straight_down() -> void:
	# THE ART HALF, pinned at the PIXEL. Every baked shadow falls straight down: nothing above the body, a
	# shadow below it, and the two side edges equal (pure blur spill, no sideways offset). Re-aim with
	# scripts/tools/bake_ui_shadows.gd; a diagonal shadow reads as a second light source once several pieces
	# of chrome share a screen, which is the whole reason that tool exists.
	# `pad` is each box's authored expand margin — the transparent canvas margin the shadow lives in.
	var shipped: MenuSkin = load("res://resources/ui/menu_skin.tres")
	assert_not_null(shipped, "the shipped skin loads")
	var cases := [
		[shipped.panel_style, "panel"], [shipped.tooltip_panel, "tooltip"],
		[shipped.button_normal, "button normal"], [shipped.button_hover, "button hover"],
		[shipped.button_pressed, "button pressed"], [shipped.dialogue_panel, "dialogue"],
	]
	for case in cases:
		var sb: StyleBoxTexture = case[0] as StyleBoxTexture
		assert_not_null(sb, "%s art is a StyleBoxTexture" % case[1])
		if sb == null:
			continue
		var img: Image = sb.texture.get_image()
		assert_not_null(img, "%s art decodes to an Image (lossless import)" % case[1])
		if img == null:
			continue
		var pad: int = int(sb.expand_margin_left)
		assert_gt(pad, 0, "%s reserves a shadow pad in its expand margins" % case[1])
		var w: int = img.get_width()
		var h: int = img.get_height()
		var mid_x: int = w / 2
		var mid_y: int = h / 2
		assert_eq(img.get_pixel(mid_x, pad - 1).a, 0.0,
			"%s casts NOTHING above its body — the light is overhead" % case[1])
		assert_gt(img.get_pixel(mid_x, h - pad).a, 0.0,
			"%s casts its shadow below its body" % case[1])
		# The only thing outside the body's left/right edges is the blur spilling sideways, so the two must
		# match. An offset shadow makes one side 0 and the other solid — that is the diagonal this forbids.
		var left: float = img.get_pixel(pad - 1, mid_y).a
		var right: float = img.get_pixel(w - pad, mid_y).a
		assert_almost_eq(left, right, 0.05,
			"%s spills the same amount either side — no sideways offset" % case[1])
