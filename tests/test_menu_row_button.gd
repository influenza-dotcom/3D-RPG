extends GutTest

## The row-button geometry contract behind the menus' selection "cursor" (MenuStyle.size_row_button).
## The list screens build multi-column rows as an EMPTY-TEXT Button carrying full-rect child Labels inset
## by the stylebox content margins — but an empty text buffer contributes ZERO height to
## Button.get_minimum_size(), so a bare row button collapses to its v-margins (~10px) and lays out half a
## line ABOVE the glyphs its labels draw: the hover/pressed/focus accent bar (the menu "cursor") and the
## click hitbox stop wrapping the text (first reported on the implant chooser). size_row_button pins the
## button back to the exact box a one-line caption would earn. These tests pin the engine premise, the
## helper's math, and that the row builders actually route through it.

## Every screen that builds empty-text row buttons with child-label content — extend when a new screen
## adopts the idiom (the helper's doc comment names the rule).
const ROW_BUILDER_FILES := [
	"res://scripts/ui/implant_choice.gd",
	"res://scripts/ui/chip_install_screen.gd",
	"res://scripts/ui/implants_screen.gd",  # the Implants tab's INSTALLED toggle rows (switch an implant off)
]


## The reference box: what one line of caption text earns a Button under the live menu theme.
func _captioned_height() -> float:
	var b := Button.new()
	b.theme = MenuStyle.theme
	b.text = "X"
	var h: float = b.get_minimum_size().y
	b.free()
	return h


func test_empty_button_still_collapses_without_the_helper() -> void:
	# The ENGINE premise the helper exists for. If this ever fails, Godot started reserving a text line
	# for empty-text buttons — size_row_button is then redundant and can be retired (harmless meanwhile).
	var empty := Button.new()
	empty.theme = MenuStyle.theme
	assert_lt(empty.get_minimum_size().y, _captioned_height(),
		"an empty-text Button reports less min height than a captioned one (margins-only vs margins+line)")
	empty.free()


func test_size_row_button_restores_the_captioned_box() -> void:
	var btn := MenuStyle.size_row_button(Button.new())
	var want := _captioned_height()
	assert_gte(btn.custom_minimum_size.y, want,
		"the pinned row height covers a full caption box (margins + one text line)")
	assert_lte(btn.custom_minimum_size.y, want + 1.0,
		"...without over-reserving (ceil rounding at most)")
	btn.free()


func test_implant_rows_are_pinned() -> void:
	# Drive the REAL builder off-tree (no _ready — the scene-test idiom): its rows must carry the pin, or
	# the selection bar/hitbox drift back off the text the moment someone reverts the _make_row line.
	var ic: Control = (load("res://scripts/ui/implant_choice.gd") as GDScript).new()
	var row: Button = ic._make_row("QA Chip", "QA Ability", "1 zm")
	assert_gte(row.custom_minimum_size.y, _captioned_height(),
		"an implant roster row occupies the same box a captioned Button would (selection bar + hitbox wrap the text)")
	row.free()
	ic.free()


func test_row_builders_route_through_the_helper() -> void:
	# chip_install's _make_row can't run bare off-tree (it composes an ItemInfo tooltip off _player), so
	# the seam is pinned at the source level — the same loud-failure style as the host-preload scene tests.
	for path: String in ROW_BUILDER_FILES:
		var src := FileAccess.get_file_as_string(path)
		assert_true(src.contains("size_row_button("),
			"%s pins its empty-text row buttons via MenuStyle.size_row_button" % path)
