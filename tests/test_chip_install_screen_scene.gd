extends GutTest

## AUTHORED-SCENE wiring contract for ChipInstallScreen (scenes/ui/chip_install_screen.tscn +
## chip_install_screen.gd), mirroring the heal_screen exemplar. Prefab WIRING tests (the silent-when-broken
## seams): the autoload points at the SCENE, every %node the script binds exists, no text is authored in the
## scene (strings belong to PlayerText / l10n, never a .tscn), and the screen-specific layout discipline
## (PANEL_MARGIN band, twin expanding section scrolls, right-aligned wallet) survives the conversion.
## Behaviour (open/install/buy) is in-tree -> playtest + test_chip_install.gd.
##
## ⭐AND IT PINS CONTROLLER PARITY (the test_atm_screen_scene pair), which this screen shipped without: the
## authored rail selector carried `focus_mode = 0` and _make_row stripped every runtime row to FOCUS_NONE, so
## the card had NO focusable control at all — ui navigation had nowhere to start and a pad player could not
## install, buy, flip the rail, or reach anything. The scene half and the runtime half are pinned separately
## below.

const SCENE := "res://scenes/ui/chip_install_screen.tscn"
const SCREEN_SOURCE := "res://scripts/ui/chip_install_screen.gd"

## Every unique name chip_install_screen.gd binds in _bind_ui — a rename in the editor breaks the bind at
## boot, so pin the roster here where it fails loudly instead.
const BOUND := ["Root", "Dim", "Content", "Title", "MoneyInset", "MoneyPlayer", "RailButton",
	"CarriedInset", "CarriedHeading", "CarriedList", "StockInset", "StockHeading", "StockList"]


func test_autoload_is_the_authored_scene() -> void:
	# The conversion contract: the autoload IS the scene (root carries the script), not the bare script —
	# otherwise the authored layout silently never loads and _bind_ui null-derefs at boot.
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://project.godot"), OK, "project.godot parses")
	assert_eq(String(cfg.get_value("autoload", "ChipInstallScreen", "")), "*" + SCENE,
		"the ChipInstallScreen autoload points at the authored scene, not the bare script")


func test_scene_instantiates_with_every_bound_unique_name() -> void:
	var scene: PackedScene = load(SCENE)
	assert_not_null(scene, "the authored scene loads")
	var inst: Node = scene.instantiate()
	assert_not_null(inst, "it instantiates (empty-PackedScene reimport transients aside)")
	assert_true(inst is CanvasLayer, "root is the CanvasLayer the autoload expects")
	assert_not_null(inst.get_script(), "the root carries chip_install_screen.gd")
	for n in BOUND:
		assert_not_null(inst.get_node_or_null("%" + n), "%%%s exists (the script binds it in _bind_ui)" % n)
	inst.free()


func test_scene_authors_no_text() -> void:
	# Strings live in PlayerText (the text-debt ratchet + l10n own them) — a caption typed into the .tscn
	# would bypass both and ship unauthored. The scene must hold only structure.
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	var stack: Array[Node] = [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is Label or n is Button:
			assert_eq(String(n.get(&"text")), "", "%s ships with empty text (the script sets it from PlayerText)" % n.name)
	inst.free()


func test_authored_chrome_keeps_the_layout_contracts() -> void:
	# The screen-specific discipline survives the scene conversion: the PANEL_MARGIN anchor band, the two
	# stacked full-width sections whose scrolls EXPAND vertically (they share the leftover panel height
	# 50/50), the right-aligned expanding wallet readout, and full-screen root/dim.
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	for full in ["Root", "Dim"]:
		var c := inst.get_node("%" + full) as Control
		assert_eq(c.anchor_right, 1.0, "%s spans the screen (anchor_right)" % full)
		assert_eq(c.anchor_bottom, 1.0, "%s spans the screen (anchor_bottom)" % full)
	assert_false((inst.get_node("%Root") as Control).visible, "the screen ships hidden until open_install")
	# The modal inset band — authored anchors must match the script's PANEL_MARGIN pin.
	var margin: float = load(SCREEN_SOURCE).PANEL_MARGIN
	var panel := (inst.get_node("%Content") as Control).get_parent() as PanelContainer
	assert_not_null(panel, "%Content sits in the anchored PanelContainer band")
	assert_almost_eq(panel.anchor_left, margin, 0.0001, "Panel's left anchor is the shared PANEL_MARGIN inset")
	assert_almost_eq(panel.anchor_top, margin, 0.0001, "Panel's top anchor is the shared PANEL_MARGIN inset")
	assert_almost_eq(panel.anchor_right, 1.0 - margin, 0.0001, "Panel's right anchor mirrors PANEL_MARGIN")
	assert_almost_eq(panel.anchor_bottom, 1.0 - margin, 0.0001, "Panel's bottom anchor mirrors PANEL_MARGIN")
	# Twin sections: each row list lives in a ScrollContainer that expands BOTH ways (the 50/50 height
	# split) with horizontal scrolling disabled (rows shrink to the panel width, never scroll sideways).
	for list_name in ["CarriedList", "StockList"]:
		var list := inst.get_node("%" + list_name) as VBoxContainer
		assert_eq(list.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "%s rows fill the section width" % list_name)
		var scroll := list.get_parent() as ScrollContainer
		assert_not_null(scroll, "%s lives in its section ScrollContainer" % list_name)
		assert_eq(scroll.size_flags_vertical, Control.SIZE_EXPAND_FILL, "%s's scroll expands vertically (50/50 height share)" % list_name)
		assert_eq(scroll.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "%s's scroll expands horizontally" % list_name)
		assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED, "%s's scroll never scrolls sideways" % list_name)
	# Wallet readout: right-aligned and EXPAND_FILL so the money phrase lands on the price column's edge.
	var money := inst.get_node("%MoneyPlayer") as Label
	assert_eq(money.horizontal_alignment, HORIZONTAL_ALIGNMENT_RIGHT, "the wallet readout right-aligns onto the price column")
	assert_eq(money.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "the wallet readout spans the row to reach that edge")
	assert_true(inst.get_node("%MoneyInset") is MarginContainer, "the wallet rides a row-inset MarginContainer (margins applied at runtime from the theme)")
	inst.free()


func test_every_authored_button_is_reachable_by_a_pad() -> void:
	# ⭐THE HALF OF CONTROLLER PARITY THAT LIVES IN THE SCENE (the test_atm_screen_scene pin, same argument): the
	# rail selector is this screen's ONE authored Button, and it shipped `focus_mode = 0` — combined with the
	# focus-stripped runtime rows, the card had no focus owner to navigate FROM. Asserted on the instance rather
	# than by grepping the .tscn, so it reads the value that will actually exist at runtime (Button's own default
	# is FOCUS_ALL — the regression is an authored override).
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	var btn := inst.get_node("%RailButton") as Button
	assert_eq(btn.focus_mode, Control.FOCUS_ALL,
		"RailButton must take focus (no `focus_mode = 0` in the .tscn) — a pad reaches this screen's actions through the Buttons alone")
	inst.free()


func test_the_pad_landing_spot_is_seeded_when_the_card_opens() -> void:
	# The other half of parity is RUNTIME (rows built in _fill/_make_row, focus grabbed in open_install on a live
	# viewport), which a unit test must not run — this autoload's _ready binds real chrome and open_install wants
	# a live ChipInstaller and Player. So it is pinned by SOURCE, the tests/test_payment_rail_selector.gd idiom.
	#
	# Every offset below is guarded before it is sliced or compared: find() answers -1 for a needle that has been
	# renamed away and a bad substr yields "", over which a contains() check quietly reads as "absent" — a pin
	# that retires itself in silence is worse than no pin.
	var src := FileAccess.get_file_as_string(SCREEN_SOURCE)
	assert_gt(src.length(), 0, "chip_install_screen.gd must be readable")
	assert_true(src.contains("btn.focus_mode = Control.FOCUS_ALL"),
		"_make_row must build the install rows FOCUS_ALL — the rows ARE the pad path, and a control a pad can never land on is not a path")
	assert_true(src.contains("_first_focus = row_btn"),
		"the first row built must be recorded as the screen's landing spot (re-recorded every _rebuild — the old rows are freed)")
	var open_at := src.find("func open_install(")
	assert_gt(open_at, -1, "func open_install( no longer present — the pin is stale")
	assert_eq(src.rfind("func open_install("), open_at,
		"open_install must be defined exactly ONCE, or the body sliced below is not the one that runs")
	var open_end := src.find("\nfunc ", open_at + 1)
	assert_gt(open_end, open_at, "open_install's body must end at the next function — the pin is stale")
	var body := src.substr(open_at, open_end - open_at)
	var shown := body.find("_root.visible = true")
	assert_gt(shown, -1, "_root.visible = true no longer present in open_install — the pin is stale")
	var grabbed := body.find("_first_focus.grab_focus()")
	assert_gt(grabbed, -1,
		"open_install must SEED focus on the first install row — with no focus owner, ui navigation has nowhere to start and every control is pad-unreachable")
	assert_gt(grabbed, shown,
		"and it must grab AFTER the card is shown — grab_focus on a hidden Control does nothing, so seeding first would leave the pad with no owner anyway")
	assert_true(body.contains("_rail_btn.grab_focus()"),
		"and when the mechanic offers NOTHING (both lists empty — hint Labels only), the rail selector — the one authored Button — must take the seed instead")
