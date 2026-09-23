extends GutTest

## The row-button geometry contract behind the menus' selection "cursor" (MenuStyle.size_row_button).
## The list screens build multi-column rows as an EMPTY-TEXT Button carrying full-rect child Labels inset
## by the stylebox content margins — but an empty text buffer contributes ZERO height to
## Button.get_minimum_size(), so a bare row button collapses to its v-margins (~12px under the shipped art
## skin) and lays out half a line ABOVE the glyphs its labels draw: the hover/pressed/focus accent bar (the
## menu "cursor") and the click hitbox stop wrapping the text (first reported on the implant chooser).
## size_row_button pins the button back to the exact box a one-line caption would earn. These tests pin the
## engine premise, that a sized row lays out as tall as a captioned sibling, and that every screen's REAL row
## builder produces a row that tall (implant_choice, chip_install and the Implants tab's toggle rows — driven
## off-tree, never through _ready).
##
## Probes here measure IN-tree: an off-tree Control with `.theme` assigned resolves the ThemeDB FALLBACK
## theme (theme-owner assignment happens on tree entry), which is exactly the blindness the helper itself
## had to fix — reference and helper must both measure the real menu theme or the compare is fiction.

## The scenes whose row builders are driven below (instantiated, never added to the tree — no _ready runs).
## Extend with a new test when another screen adopts the empty-text row idiom (the helper's doc comment names it).
const CHIP_INSTALL_SCENE := "res://scenes/ui/chip_install_screen.tscn"
const IMPLANTS_SCENE := "res://scenes/ui/implants_screen.tscn"
const PLAYER_PATH := "res://scripts/player/player.gd"


## The reference box: what one line of caption text earns a Button under the live menu theme (measured
## in-tree — see the header note).
func _captioned_height() -> float:
	var b := Button.new()
	b.theme = MenuStyle.theme
	b.text = "X"
	add_child(b)
	var h: float = b.get_minimum_size().y
	remove_child(b)
	b.free()
	return h


func test_empty_button_still_collapses_without_the_helper() -> void:
	# The ENGINE premise the helper exists for. If this ever fails, Godot started reserving a text line
	# for empty-text buttons — size_row_button is then redundant and can be retired (harmless meanwhile).
	var empty := Button.new()
	empty.theme = MenuStyle.theme
	add_child(empty)
	assert_lt(empty.get_minimum_size().y, _captioned_height(),
		"an empty-text Button reports less min height than a captioned one (margins-only vs margins+line)")
	remove_child(empty)
	empty.free()


## The requirement observed through real layout rather than a re-run of the helper's own probe: a list lays a
## sized row out exactly as tall as a captioned Button beside it under the same menu theme. Shorter and the
## selection bar + hitbox ride above the row's glyphs; taller and every row pads the list (the old off-tree probe
## measured the fallback theme and over-reserved 1-3 px). The Buttons carry no theme of their own: they inherit
## it from the list, the way a screen's rows inherit it from the screen.
func test_size_row_button_lays_out_as_tall_as_a_captioned_sibling() -> void:
	var list := VBoxContainer.new()
	list.theme = MenuStyle.theme
	add_child_autofree(list)
	var captioned := Button.new()
	captioned.text = "Air Dash"
	list.add_child(captioned)
	var bare := Button.new()
	list.add_child(bare)
	var row := MenuStyle.size_row_button(Button.new())
	list.add_child(row)
	await wait_process_frames(1)
	var cap_h := captioned.size.y
	assert_lt(bare.size.y, cap_h,
		"control: without the helper an empty-text Button lays out shorter than its captioned sibling (%s vs %s)" % [bare.size.y, cap_h])
	assert_true(row.size.y >= cap_h,
		"a sized row lays out at least as tall as the captioned Button beside it, so its bar wraps a full line (%s vs %s)" % [row.size.y, cap_h])
	assert_true(row.size.y < cap_h + 1.0,
		"...and less than a pixel taller (the helper rounds up), never a padded row (%s vs %s)" % [row.size.y, cap_h])


func test_implant_rows_are_pinned() -> void:
	# Drive the REAL builder off-tree (no _ready — the scene-test idiom): its rows must carry the pin, or
	# the selection bar/hitbox drift back off the text the moment someone reverts the _make_row line.
	var ic: Control = (load("res://scripts/ui/implant_choice.gd") as GDScript).new()
	var row: Button = ic._make_row("QA Chip", "QA Ability", "1 zm")
	assert_gte(row.custom_minimum_size.y, _captioned_height(),
		"an implant roster row occupies the same box a captioned Button would (selection bar + hitbox wrap the text)")
	row.free()
	ic.free()


func test_chip_install_rows_are_pinned() -> void:
	# chip_install's _make_row prices the row off `_player` (charge_total) and tips it off the player's bag, so it
	# is driven with a bare off-tree Player carrying a backpack and cash (the test_chip_install_screen_scene idiom;
	# no Player._ready runs). The screen itself is instantiated, never added to the tree.
	var screen: Node = (load(CHIP_INSTALL_SCENE) as PackedScene).instantiate()
	var p: Node = load(PLAYER_PATH).new()
	p.set(&"inventory", CharacterInventory.new())
	p.set(&"money", 1000.0)
	screen.set(&"_player", p)
	var chip := Item.new()
	chip.id = &"qa_row_chip"
	chip.display_name = "QA Chip"
	chip.installs_ability = &"grapple"
	var row: Button = screen._make_row(chip, 100, true, false)
	assert_gte(row.custom_minimum_size.y, _captioned_height(),
		"a chip-install row occupies the same box a captioned Button would (selection bar + hitbox wrap the text)")
	var broke: Button = screen._make_row(chip, 100, false, true)
	assert_gte(broke.custom_minimum_size.y, _captioned_height(),
		"an UNAFFORDABLE (disabled) install row keeps the same box — a greyed row must not collapse above its labels")
	row.free()
	broke.free()
	screen.free()
	(p.get(&"inventory") as Node).free()
	p.free()
	chip = null


func test_implant_toggle_rows_are_pinned() -> void:
	# The Implants tab's INSTALLED rows (switch an implant off). _make_toggle_row needs only the MenuStyle autoload.
	var screen: Node = (load(IMPLANTS_SCENE) as PackedScene).instantiate()
	var on_row: Button = screen._make_toggle_row(&"air_dash", "Air Dash", "Air Dash Chip", true)
	var off_row: Button = screen._make_toggle_row(&"slide", "Slide", "", false)
	assert_gte(on_row.custom_minimum_size.y, _captioned_height(),
		"an active implant's toggle row occupies a captioned Button's box (the pressed accent bar wraps the name)")
	assert_gte(off_row.custom_minimum_size.y, _captioned_height(),
		"a switched-off row with no chip column is just as tall — the dimmed caption still sits inside its bar")
	on_row.free()
	off_row.free()
	screen.free()
