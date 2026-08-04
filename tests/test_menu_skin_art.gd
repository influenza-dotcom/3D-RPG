extends GutTest

## The UI ARTIST'S drop-in surface (MenuSkin "Widget art" groups + MenuStyle consuming them): every menu
## widget's look can be replaced by dropping StyleBoxes/textures into resources/ui/menu_skin.tres — no code.
## Pinned here: the slots exist, an artist StyleBox actually lands in the built Theme (as a DUPLICATE, so
## theme-side mutation never bleeds back into the saved .tres), every empty slot falls back to the generated
## flat look (the shipped skin has no art yet — the game must look identical), the toggle disabled-variant
## fallback, and the two non-theme consumers (make_meter's per-row tint, the player-menu tab strip helpers).
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
			"scrollbar_track", "scrollbar_grabber", "separator_style", "tooltip_panel"]:
		assert_true(field in s, "MenuSkin exposes artist slot %s" % field)
	s = null


func test_empty_slots_keep_the_generated_flat_look() -> void:
	# The shipped menu_skin.tres carries no widget art yet — every slot null must yield the same generated
	# StyleBoxFlat theme as before the surface existed, so landing this feature changes nothing on screen.
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
	var sel := StyleBoxTexture.new()
	var hov := StyleBoxTexture.new()
	_ms.skin.tab_selected = sel
	_ms.skin.tab_hovered = hov
	var active: StyleBox = _ms.make_active_tab_style()
	var hover: StyleBox = _ms.make_hover_tab_style()
	assert_true(active is StyleBoxTexture and active != sel, "active tab wears a duplicate of tab_selected")
	assert_true(hover is StyleBoxTexture and hover != hov, "hovered tab wears a duplicate of tab_hovered")
