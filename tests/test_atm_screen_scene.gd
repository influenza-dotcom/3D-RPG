extends GutTest

## The AUTHORED-SCENE screen contract for the LEDGER TERMINAL (scenes/ui/atm_screen.tscn + atm_screen.gd), the
## same shape test_heal_screen_scene.gd pins on its exemplar. Menus are .tscn scenes a designer/artist edits; the
## script binds chrome by %unique name and applies the skin-driven look on top. These are prefab WIRING contract
## tests (the silent-when-broken seams): the autoload points at the SCENE, every %node the script binds exists,
## and no text is authored in the scene (strings belong to PlayerText / l10n, never a .tscn). Behaviour
## (open/deposit/withdraw) is in-tree -> playtest.
##
## ⭐WHY THIS SCREEN NEEDS ITS OWN FILE. _bind_ui() hard-binds THIRTEEN %unique names straight out of _ready with
## no null guards, and this autoload is instanced at BOOT — so renaming one node in the editor is not "a screen
## that looks wrong", it is a null-deref before the main menu paints. It was the only station screen without a
## wiring test.
##
## ⭐AND IT PINS CONTROLLER PARITY, which this screen has already shipped broken once: the authored Buttons must
## carry NO `focus_mode = 0` (Button's default FOCUS_ALL is what a pad navigates onto), the code-built amount
## chips must set FOCUS_ALL, and open_atm must SEED focus on the first chip once the card is visible. With no
## focus owner at all, ui navigation has nowhere to start and EVERY button on the card is unreachable — a
## mouse-only gate on a screen a pad player can walk up to.

const SCENE := "res://scenes/ui/atm_screen.tscn"
const SCREEN_SOURCE := "res://scripts/ui/atm_screen.gd"

## Every unique name atm_screen.gd binds in _bind_ui, in bind order — a rename in the editor breaks the bind at
## boot, so pin the roster here where it fails loudly instead.
const BOUND := ["Root", "Dim", "Card", "Buttons", "Title", "Statement", "Hint", "AmountEdit", "Presets",
	"RailButton", "DepositButton", "WithdrawButton", "CloseButton"]

## The three buttons that split the bottom row. RailButton sits on its own line above them (a cycling selector,
## not a dialog action), so it takes the fixed card width rather than a share of the row.
const ROW_BUTTONS := ["DepositButton", "WithdrawButton", "CloseButton"]


func test_autoload_is_the_authored_scene() -> void:
	# The conversion contract: the autoload IS the scene (root carries the script), not the bare script —
	# otherwise the authored layout silently never loads and _bind_ui null-derefs at boot.
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://project.godot"), OK, "project.godot parses")
	assert_eq(String(cfg.get_value("autoload", "AtmScreen", "")), "*" + SCENE,
		"the AtmScreen autoload points at the authored scene, not the bare script")


func test_scene_instantiates_with_every_bound_unique_name() -> void:
	var scene: PackedScene = load(SCENE)
	assert_not_null(scene, "the authored scene loads")
	var inst: Node = scene.instantiate()
	assert_not_null(inst, "it instantiates (empty-PackedScene reimport transients aside)")
	assert_true(inst is CanvasLayer, "root is the CanvasLayer the autoload expects")
	assert_not_null(inst.get_script(), "the root carries atm_screen.gd")
	for n in BOUND:
		assert_not_null(inst.get_node_or_null("%" + n), "%%%s exists (the script binds it in _bind_ui)" % n)
	inst.free()


func test_scene_authors_no_text() -> void:
	# Strings live in PlayerText (the text-debt ratchet + l10n own them) — a caption typed into the .tscn
	# would bypass both and ship unauthored. The scene must hold only structure. The LineEdit is swept too:
	# its PLACEHOLDER is player-facing prose as much as any caption, and _bind_ui sets it from PlayerText.
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	var stack: Array[Node] = [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is Label or n is Button or n is LineEdit:
			assert_eq(String(n.get(&"text")), "", "%s ships with empty text (the script sets it from PlayerText)" % n.name)
		if n is LineEdit:
			assert_eq((n as LineEdit).placeholder_text, "",
				"%s ships with an empty placeholder (_bind_ui sets it from PlayerText)" % n.name)
	inst.free()


func test_bound_chrome_keeps_the_layout_contracts() -> void:
	# The fixed-width-card discipline: the row buttons split the card EXPAND_FILL and clip their captions (a long
	# "Settle your debt" caption must never grow the card), the statement and hint wrap, and the dim and root
	# cover the screen (full-rect anchors).
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	for b in ROW_BUTTONS:
		var btn := inst.get_node("%" + b) as Button
		assert_eq(btn.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "%s splits the fixed card width" % b)
		assert_true(btn.clip_text, "%s clips its caption instead of growing the card" % b)
	assert_true((inst.get_node("%RailButton") as Button).clip_text,
		"RailButton clips its caption too — the rail names are set from PlayerText and must not widen the card")
	for wrapped in ["Statement", "Hint"]:
		var lbl := inst.get_node("%" + wrapped) as Label
		assert_eq(lbl.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "the %s wraps within the card" % wrapped)
	for full in ["Root", "Dim"]:
		var c := inst.get_node("%" + full) as Control
		assert_eq(c.anchor_right, 1.0, "%s spans the screen (anchor_right)" % full)
		assert_eq(c.anchor_bottom, 1.0, "%s spans the screen (anchor_bottom)" % full)
	assert_false((inst.get_node("%Root") as Control).visible, "the screen ships hidden until open_atm")
	inst.free()


func test_every_authored_button_is_reachable_by_a_pad() -> void:
	# ⭐THE HALF OF CONTROLLER PARITY THAT LIVES IN THE SCENE, and the exact state this screen shipped in: all four
	# authored Buttons carried `focus_mode = 0`. That is the right call on HealScreen (a mouse-driven two-button
	# dialog) and the wrong one here, because this card's other input is a LineEdit — with every Button refusing
	# focus there is no focus owner to navigate FROM, so a pad player cannot deposit, withdraw, flip the rail, or
	# even close. Asserted on the instance rather than by grepping the .tscn, so it reads the value that will
	# actually exist at runtime (Button's own default is FOCUS_ALL — the regression is an authored override).
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	for b in ["RailButton", "DepositButton", "WithdrawButton", "CloseButton"]:
		var btn := inst.get_node("%" + b) as Button
		assert_eq(btn.focus_mode, Control.FOCUS_ALL,
			"%s must take focus (no `focus_mode = 0` in the .tscn) — a pad reaches this screen's actions through the Buttons alone" % b)
	inst.free()


func test_the_pad_landing_spot_is_seeded_when_the_card_opens() -> void:
	# The other half of parity is RUNTIME (chips built in _bind_ui, focus grabbed in open_atm on a live viewport),
	# which a unit test must not run — this autoload's _ready binds real chrome and open_atm wants a live Atm and
	# Player. So it is pinned by SOURCE, the tests/test_payment_rail_selector.gd idiom.
	#
	# Every offset below is guarded before it is sliced or compared: find() answers -1 for a needle that has been
	# renamed away and a bad substr yields "", over which a contains() check quietly reads as "absent" — a pin
	# that retires itself in silence is worse than no pin.
	var src := FileAccess.get_file_as_string(SCREEN_SOURCE)
	assert_gt(src.length(), 0, "atm_screen.gd must be readable")
	assert_true(src.contains("b.focus_mode = Control.FOCUS_ALL"),
		"_add_chip must build the amount chips FOCUS_ALL — the chips ARE the pad path, and a control a pad can never land on is not a path")
	assert_true(src.contains("_first_focus = b"),
		"the first chip built must be recorded as the screen's landing spot")
	var open_at := src.find("func open_atm(")
	assert_gt(open_at, -1, "func open_atm( no longer present — the pin is stale")
	assert_eq(src.rfind("func open_atm("), open_at,
		"open_atm must be defined exactly ONCE, or the body sliced below is not the one that runs")
	var open_end := src.find("\nfunc ", open_at + 1)
	assert_gt(open_end, open_at, "open_atm's body must end at the next function — the pin is stale")
	var body := src.substr(open_at, open_end - open_at)
	var shown := body.find("_root.visible = true")
	assert_gt(shown, -1, "_root.visible = true no longer present in open_atm — the pin is stale")
	var grabbed := body.find("_first_focus.grab_focus()")
	assert_gt(grabbed, -1,
		"open_atm must SEED focus on the first chip — with no focus owner, ui navigation has nowhere to start and every button is unreachable")
	assert_gt(grabbed, shown,
		"and it must grab AFTER the card is shown — grab_focus on a hidden Control does nothing, so seeding first would leave the pad with no owner anyway")
