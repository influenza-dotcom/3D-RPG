extends GutTest

## MENUS DON'T CHANGE SIZE. A menu card must be the SAME size and in the SAME place no matter which tab is
## up or what the player has typed — the screen is a fixed frame, not a box that grows around its content.
##
## The failure this pins is structural, not cosmetic. A Control whose combined MINIMUM size beats the rect its
## anchors give it does not clip and does not scroll: Godot GROWS it past the anchors (grow_horizontal /
## grow_vertical = BOTH, so it swells around its centre). Two ways a menu walks into that:
##   1. A TabContainer's minimum defaults to the CURRENT page's minimum (use_hidden_tabs_for_min_size = false),
##      so a fat page hands the container a fat minimum the moment it is shown. MenuStyle.apply pins the flag ON
##      for every TabContainer under a menu root, which makes the minimum the MAX over all pages — one size,
##      whichever tab is up. (Character creation used to jump 45px taller, and off the top of the screen, when
##      the Shirt tab opened; Options grew 33px wider on Accessibility.)
##   2. That max still has to FIT. A page can outgrow the panel on its own — which is what the artist frame
##      landing exposed: menu_skin.tres's panel stylebox spends 72x76px of every card on the parchment border,
##      so the room inside shrank under what the Shirt tab and the Accessibility two-up columns were built for.
##
## Measured at 792x432 — the SHORTEST the real UI canvas ever gets (base 396x216 + stretch scale 0.5 +
## aspect "expand": 444 tall at 16:9, 495 at 16:10, 432 on an ultrawide, and never narrower than 792). Passing
## here means passing on every shape of monitor. A failure is a LAYOUT BUDGET failure: shrink the page (fold a
## row, narrow a column floor), don't grow the panel's anchor band to hide it.

const CANVAS := Vector2i(792, 432)

## Menu scenes that own an outer card + tabs. Both instantiate standalone (no player / station context).
const SCREENS: Array[String] = [
	"res://scenes/ui/character_creation.tscn",
	"res://scenes/ui/options_menu.tscn",
]

## Sub-pixel slack: anchor bands land on fractions (0.9 * 432 = 388.8), minimums are whole pixels.
const EPS := 0.5


func test_tabbed_menus_keep_one_panel_size_on_every_tab() -> void:
	for path in SCREENS:
		var host := _host()
		var inst: Node = (load(path) as PackedScene).instantiate()
		host.add_child(inst)
		await _frames(4)

		var panel := _panel(inst)
		assert_not_null(panel, "%s has an outer card named Panel" % path)
		if panel == null:
			continue
		var band := _band(panel)
		var tabs := _tabs(inst)
		assert_false(tabs.is_empty(), "%s has a TabContainer" % path)

		for t in tabs:
			# The structural half of the rule — pinned by MenuStyle.apply, authored in the scene as well so the
			# editor preview tells the truth.
			assert_true(t.use_hidden_tabs_for_min_size,
				"%s: %s reports ONE minimum for every page (use_hidden_tabs_for_min_size)" % [path, t.name])

		var first_size := Vector2.ZERO
		var first_pos := Vector2.ZERO
		for t in tabs:
			for i in t.get_tab_count():
				t.current_tab = i
				await _frames(3)
				var page_name: String = t.get_tab_control(i).name
				var pmin := panel.get_combined_minimum_size()
				# The budget half: the biggest page still has to fit the card's anchor band, or the card grows.
				assert_lte(pmin.x, band.x + EPS,
					"%s on tab %s: the card's minimum WIDTH fits its anchor band (%.1f)" % [path, page_name, band.x])
				assert_lte(pmin.y, band.y + EPS,
					"%s on tab %s: the card's minimum HEIGHT fits its anchor band (%.1f)" % [path, page_name, band.y])
				if i == 0:
					first_size = panel.size
					first_pos = panel.global_position
				else:
					assert_almost_eq(panel.size.x, first_size.x, EPS,
						"%s on tab %s: the card is the same WIDTH as on the first tab" % [path, page_name])
					assert_almost_eq(panel.size.y, first_size.y, EPS,
						"%s on tab %s: the card is the same HEIGHT as on the first tab" % [path, page_name])
					assert_almost_eq(panel.global_position.x, first_pos.x, EPS,
						"%s on tab %s: the card has not moved sideways" % [path, page_name])
					assert_almost_eq(panel.global_position.y, first_pos.y, EPS,
						"%s on tab %s: the card has not moved vertically" % [path, page_name])
		inst.queue_free()
		host.queue_free()
		await _frames(2)


## The Shirt tab is the page that decides character creation's card size, and its budget is written down in
## the screen itself (SHIRT_PAGE_HEIGHT_BUDGET, with the arithmetic that derived it). Pin the page against
## that number, not just against the panel: it fails at the row that broke it, with the const to fix.
func test_the_shirt_page_stays_inside_its_written_budget() -> void:
	var host := _host()
	var inst: Node = (load("res://scenes/ui/character_creation.tscn") as PackedScene).instantiate()
	host.add_child(inst)
	await _frames(4)

	var budget: float = float(load("res://scripts/ui/character_creation.gd").get_script_constant_map()
		.get("SHIRT_PAGE_HEIGHT_BUDGET", 0))
	assert_gt(budget, 0.0, "the screen still declares SHIRT_PAGE_HEIGHT_BUDGET")
	var shirt := inst.get_node("%ShirtTab") as Control
	assert_lte(shirt.get_combined_minimum_size().y, budget,
		"the Shirt page's minimum height stays inside the budget its screen documents (%.0f)" % budget)

	inst.queue_free()
	host.queue_free()
	await _frames(2)


## The chess card has no tabs, but it has the same failure: two MUTUALLY EXCLUSIVE panes of very different
## size (the 8x8 board with the Board Visualizer chip installed, the blindfold placeholder without it), one
## visible per open. The sighted pane's grid is a hard 8 x BOARD_CELL floor with zero separation, and it was
## sized against the OLD generated panel box (2x16px) — under the artist frame (36/40) the same board pushed
## the card ~23px past its band, so a sighted open rendered a bigger, higher card than a blindfold one.
func test_the_chess_card_fits_its_band_with_the_board_shown() -> void:
	var host := _host()
	var inst: Node = (load("res://scenes/ui/chess_screen.tscn") as PackedScene).instantiate()
	host.add_child(inst)
	(inst.get_node("%Root") as Control).visible = true  # a hidden screen never lays out
	await _frames(4)

	var panel := _panel(inst)
	var band := _band(panel)
	var board := inst.get_node("%BoardBox") as Control
	var blind := inst.get_node("%BlindfoldBox") as Control

	# open_match picks exactly one pane (chess_screen.gd _has_board); measure the card in each.
	for sighted in [true, false]:
		board.visible = sighted
		blind.visible = not sighted
		await _frames(3)
		var pmin := panel.get_combined_minimum_size()
		var which := "the board" if sighted else "the blindfold placeholder"
		assert_lte(pmin.y, band.y + EPS,
			"the chess card's minimum HEIGHT fits its anchor band (%.1f) with %s shown" % [band.y, which])
		assert_lte(pmin.x, band.x + EPS,
			"the chess card's minimum WIDTH fits its anchor band (%.1f) with %s shown" % [band.x, which])

	inst.queue_free()
	host.queue_free()
	await _frames(2)


## Typing a name must not reflow the screen: the "name required" hint hides with ALPHA and keeps its layout
## slot (a `visible = false` child is DROPPED from a VBox, which used to jump the whole tab block up a line on
## the first keystroke of every New Game). Same card, same place, hint still visible.
func test_character_creation_does_not_reflow_when_the_name_is_typed() -> void:
	var host := _host()
	var inst: Node = (load("res://scenes/ui/character_creation.tscn") as PackedScene).instantiate()
	host.add_child(inst)
	await _frames(4)

	var panel := _panel(inst)
	var before_size := panel.size
	var before_pos := panel.global_position
	var hint := inst.get_node("%NameHint") as Control

	(inst.get_node("%NameEdit") as LineEdit).text = "Ada"
	inst.call(&"_on_name_changed", "Ada")  # setting .text in code doesn't emit text_changed
	await _frames(3)

	assert_true(hint.visible, "the name hint keeps its layout slot (hidden by alpha, never `visible`)")
	assert_almost_eq(hint.self_modulate.a, 0.0, 0.01, "the named state fades the hint out")
	assert_almost_eq(panel.size.y, before_size.y, EPS, "the card is the same height once a name is typed")
	assert_almost_eq(panel.global_position.y, before_pos.y, EPS, "the card has not moved")

	inst.queue_free()
	host.queue_free()
	await _frames(2)


# --- helpers ---------------------------------------------------------------------------------------------

## A viewport pinned to the real canvas, so every measurement below is in the pixels the player gets.
func _host() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = CANVAS
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED  # layout only; nothing is drawn
	add_child_autofree(vp)
	return vp

## The screen's outer card. Every menu scene here names it "Panel" (the scene tests pin that name).
func _panel(inst: Node) -> Control:
	var found := inst.find_children("Panel", "", true, false)
	return found[0] as Control if not found.is_empty() else null

## The rect the card's anchors hand it — what it must fit inside.
func _band(panel: Control) -> Vector2:
	return Vector2(
		(panel.anchor_right - panel.anchor_left) * float(CANVAS.x),
		(panel.anchor_bottom - panel.anchor_top) * float(CANVAS.y))

func _tabs(inst: Node) -> Array[Node]:
	return inst.find_children("*", "TabContainer", true, false)

func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
