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
## mouse-only gate on a screen a pad player can walk up to. The runtime half is driven for real on a private
## in-tree instance, opened for a bare off-tree terminal + Player (the test_atm idiom — no Player._ready runs).

const SCENE := "res://scenes/ui/atm_screen.tscn"
const SCREEN_SOURCE := "res://scripts/ui/atm_screen.gd"
const PLAYER_PATH := "res://scripts/player/player.gd"
const ATM_PATH := "res://scripts/components/atm.gd"

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
	assert_true(inst.get_script() != null and String(inst.get_script().resource_path) == SCREEN_SOURCE,
		"the root carries atm_screen.gd (the script whose _bind_ui reads these names)")
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
	# authored Buttons carried `focus_mode = 0`. That is the right call on a keyboard-first dialog (NameEntryDialog
	# keeps the keyboard in its field) and the wrong one here, because this card's other input is a LineEdit — with
	# every Button refusing focus there is no focus owner to navigate FROM, so a pad player cannot deposit,
	# withdraw, flip the rail, or even close. The station screens (heal / respec / shop chrome) now hold the same
	# rule, each pinned in its own scene test. Asserted on the instance rather than by grepping the .tscn, so it
	# reads the value that will actually exist at runtime (Button's own default is FOCUS_ALL — the regression is
	# an authored override).
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	for b in ["RailButton", "DepositButton", "WithdrawButton", "CloseButton"]:
		var btn := inst.get_node("%" + b) as Button
		assert_eq(btn.focus_mode, Control.FOCUS_ALL,
			"%s must take focus (no `focus_mode = 0` in the .tscn) — a pad reaches this screen's actions through the Buttons alone" % b)
	inst.free()


## open_atm grabs the mouse (ModalMenu.grab_mouse) and close() hands back what it found; restored here as well so a
## failed assert between the two can never leave the machine's cursor mode changed.
var _prev_mouse_mode: Input.MouseMode


func before_each() -> void:
	_prev_mouse_mode = Input.mouse_mode


func after_each() -> void:
	Input.mouse_mode = _prev_mouse_mode


## The live chips in %Presets (the ones _bind_ui just built — anything queued for deletion is a stale build).
func _live_chips(screen: Node) -> Array:
	return (screen.get_node("%Presets") as Node).get_children().filter(
		func(c: Node) -> bool: return c is Button and not c.is_queued_for_deletion())


func test_the_pad_landing_spot_is_seeded_when_the_card_opens() -> void:
	# The other half of parity is RUNTIME: the chips are built in _bind_ui and focus is seeded in open_atm, after the
	# card is shown (grab_focus on a hidden Control does nothing). Driven on a private instance of the authored
	# scene — never the AtmScreen autoload — opened for a bare terminal and a bare Player that never enter the tree.
	var screen: Node = (load(SCENE) as PackedScene).instantiate()
	add_child_autofree(screen)  # _ready -> _bind_ui builds the amount chips
	var chips := _live_chips(screen)
	assert_gt(chips.size(), 0, "_bind_ui builds the amount chips — they are the pad path")
	for c in chips:
		assert_eq((c as Button).focus_mode, Control.FOCUS_ALL,
			"amount chip '%s' must take focus — a control a pad can never land on is not a path" % (c as Button).text)
	if chips.is_empty():
		return
	var viewport := screen.get_viewport()
	assert_ne(viewport.gui_get_focus_owner(), chips[0], "control: nothing on the hidden card holds focus before it opens")
	var atm: Node = load(ATM_PATH).new()
	var player: Node = load(PLAYER_PATH).new()
	player.set(&"money", 50.0)
	screen.open_atm(atm, player)
	assert_true(screen.is_open(), "a free terminal with a live player opens")
	assert_eq(viewport.gui_get_focus_owner(), chips[0],
		"open_atm must SEED focus on the first amount chip once the card is visible — with no focus owner, ui navigation has nowhere to start and every button is pad-unreachable")
	screen.close()
	assert_false(screen.is_open(), "the card closes again")
	atm.free()
	player.free()
