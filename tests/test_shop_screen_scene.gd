extends GutTest

## ShopScreen's AUTHORED-SCENE wiring (scenes/ui/shop_screen.tscn + scripts/ui/shop_screen.gd), mirroring
## the heal-screen exemplar's contract tests (test_heal_screen_scene.gd). Menus are .tscn scenes a
## designer/artist edits; the script binds chrome by %unique name and applies the skin-driven look on top.
## These are prefab WIRING contract tests (the silent-when-broken seams): the autoload points at the SCENE,
## every %node the script binds exists, no text is authored in the scene (strings belong to PlayerText /
## l10n, never a .tscn), and the shop's own layout discipline holds. One runtime half is DRIVEN on the live
## autoload — open_shop seeds pad focus, with the cash-only fallback — using an off-tree Merchant + bare Player (the
## test_merchant.gd idiom). Behaviour (open/buy/sell, and the real-time posture) stays covered by test_merchant.gd.

const SCENE := "res://scenes/ui/shop_screen.tscn"

## Every unique name shop_screen.gd binds in _bind_ui — a rename in the editor breaks the bind at boot,
## so pin the roster here where it fails loudly instead.
const BOUND := [
	"Root", "Dim", "VBox", "TitleSpacer", "Title", "SortButton", "RailButton",
	"Columns", "StockColumn", "StockWallet", "StockScroll",
	"PlayerColumn", "PlayerWallet", "PlayerScroll", "Footer", "Detail",
]


func test_autoload_is_the_authored_scene() -> void:
	# The conversion contract: the autoload IS the scene (root carries the script), not the bare script —
	# otherwise the authored layout silently never loads and _bind_ui null-derefs at boot.
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://project.godot"), OK, "project.godot parses")
	assert_eq(String(cfg.get_value("autoload", "ShopScreen", "")), "*" + SCENE,
		"the ShopScreen autoload points at the authored scene, not the bare script")


func test_scene_instantiates_with_every_bound_unique_name() -> void:
	var scene: PackedScene = load(SCENE)
	assert_not_null(scene, "the authored scene loads")
	var inst: Node = scene.instantiate()
	assert_not_null(inst, "it instantiates (empty-PackedScene reimport transients aside)")
	assert_true(inst is CanvasLayer, "root is the CanvasLayer the autoload expects")
	assert_not_null(inst.get_script(), "the root carries shop_screen.gd")
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


func test_bound_chrome_keeps_the_layout_contracts() -> void:
	# The shop's own layout discipline survives the scene conversion:
	#  * root/dim span the screen; the panel keeps the 0.05 (tall) anchor band (the design-canvas geometry every
	#    cell-size number in _bind_ui's comments is derived from);
	#  * the Sort button clips + right-aligns (its FIXED width is a skin budget, code-set; focus is pinned
	#    separately below — the pad-parity contract);
	#  * the two columns EXPAND_FILL side-by-side, each scroll slot expands with horizontal scroll DISABLED
	#    (the too-short-window fallback must never scroll sideways);
	#  * the wallet headings trim with "…" instead of widening their column (no-shift rule);
	#  * the footer is a clip host (fixed height is skin-derived, code-set) with the detail label filling it,
	#    centred + wrapping — the fixed-height detail line can't squeeze the grids;
	#  * the screen ships hidden until open_shop.
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	for full in ["Root", "Dim"]:
		var c := inst.get_node("%" + full) as Control
		assert_eq(c.anchor_right, 1.0, "%s spans the screen (anchor_right)" % full)
		assert_eq(c.anchor_bottom, 1.0, "%s spans the screen (anchor_bottom)" % full)
	assert_false((inst.get_node("%Root") as Control).visible, "the screen ships hidden until open_shop")
	var panel := (inst.get_node("%VBox") as Control).get_parent() as Control
	assert_true(panel is PanelContainer, "the content VBox lives in the themed PanelContainer")
	assert_almost_eq(panel.anchor_left, 0.05, 0.001, "the panel keeps the 0.05 (tall) anchor band (left)")
	assert_almost_eq(panel.anchor_bottom, 0.95, 0.001, "the panel keeps the 0.05 (tall) anchor band (bottom)")
	var sort_btn := inst.get_node("%SortButton") as Button
	assert_true(sort_btn.clip_text, "the Sort button clips its caption (fixed footprint as the mode cycles)")
	assert_eq(sort_btn.alignment, HORIZONTAL_ALIGNMENT_RIGHT, "the Sort caption right-aligns against the panel edge")
	assert_eq((inst.get_node("%Title") as Control).size_flags_horizontal, Control.SIZE_EXPAND_FILL,
		"the title expands between its two fixed flanks (optical centring)")
	assert_eq((inst.get_node("%Columns") as Control).size_flags_vertical, Control.SIZE_EXPAND_FILL,
		"the columns row takes the panel's spare height (grids get the room)")
	for col in ["StockColumn", "PlayerColumn"]:
		assert_eq((inst.get_node("%" + col) as Control).size_flags_horizontal, Control.SIZE_EXPAND_FILL,
			"%s splits the panel width evenly with its sibling" % col)
	for sc in ["StockScroll", "PlayerScroll"]:
		var scroll := inst.get_node("%" + sc) as ScrollContainer
		assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED,
			"%s never scrolls sideways (the fallback is vertical-only)" % sc)
		assert_eq(scroll.size_flags_vertical, Control.SIZE_EXPAND_FILL, "%s fills its column's slot" % sc)
	for w in ["StockWallet", "PlayerWallet"]:
		assert_eq((inst.get_node("%" + w) as Label).text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS,
			"%s trims a huge amount instead of widening the column" % w)
	assert_true((inst.get_node("%Footer") as Control).clip_contents,
		"the footer clips overflow (a long tooltip can't grow it and squeeze the grids)")
	var detail := inst.get_node("%Detail") as Label
	assert_eq(detail.horizontal_alignment, HORIZONTAL_ALIGNMENT_CENTER, "the detail line centres under both grids")
	assert_eq(detail.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "the detail line wraps within the footer")
	assert_eq(detail.anchor_right, 1.0, "the detail label fills the clip footer (anchor_right)")
	inst.free()


func test_every_authored_button_is_reachable_by_a_pad() -> void:
	# ⭐THE HALF OF CONTROLLER PARITY THAT LIVES IN THE SCENE (the test_atm_screen_scene.gd pin, and the exact
	# state that screen once shipped in): the authored chrome Buttons must NOT carry `focus_mode = 0` — Button's
	# own default FOCUS_ALL is what a pad navigates onto, so the regression is always an authored override.
	# HONEST SPLIT: this pins the CHROME only. The buy/sell surface is the two GridInventoryViews, which are
	# deliberately mouse-driven (FOCUS_NONE in grid_inventory_view.gd _ready — test_loot_drop pins that side),
	# so this test does NOT claim the shop is fully pad-playable; it claims no BUTTON is pad-unreachable, which
	# is the atm must-not-recur rule. Asserted on the instance rather than by grepping the .tscn, so it reads
	# the value that will actually exist at runtime.
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	for b in ["SortButton", "RailButton"]:
		var btn := inst.get_node("%" + b) as Button
		assert_eq(btn.focus_mode, Control.FOCUS_ALL,
			"%s must take focus (no `focus_mode = 0` in the .tscn) — a pad reaches this screen's chrome through the Buttons alone" % b)
	inst.free()


## Off-tree fixtures for the focus tests (the test_merchant.gd shapes), released in after_each whatever the asserts did.
var _merchant: Merchant = null
var _player: Player = null
var _prev_account: float
var _prev_method: String

func before_each() -> void:
	# Pricing the rows reads the SHARED GameState banking fields (the payment seam); pin a known posture.
	_prev_account = GameState.account
	_prev_method = GameState.payment_method
	GameState.account = 0.0
	GameState.payment_method = "debit"

func after_each() -> void:
	if ShopScreen.is_open():
		ShopScreen.close()
	if _merchant != null:
		_merchant.stock.free()
		_merchant.free()
		_merchant = null
	if _player != null:
		_player.inventory.free()
		_player.free()
		_player = null
	GameState.account = _prev_account
	GameState.payment_method = _prev_method

## Open the LIVE autoload on a fresh off-tree merchant (never added to the tree, so no Merchant/Player _ready runs).
func _open_shop(accepts_ledger: bool) -> void:
	_merchant = Merchant.new()
	_merchant.stock = CharacterInventory.new()
	_merchant.accepts_ledger = accepts_ledger
	_player = load("res://scripts/player/player.gd").new()
	_player.inventory = CharacterInventory.new()
	get_viewport().gui_release_focus()
	ShopScreen.open_shop(_merchant, _player)


func test_the_pad_landing_spot_is_seeded_when_the_shop_opens() -> void:
	# The other half of parity is RUNTIME: open_shop must hand the viewport a focus owner, or ui navigation has
	# nowhere to start and every chrome button is pad-unreachable. A merchant that takes the ledger SHOWS the rail
	# selector (it re-prices every deal), so the pad lands there.
	_open_shop(true)
	assert_true(ShopScreen.is_open(), "precondition: the shop opens on a valid merchant + player")
	var rail: Button = ShopScreen._rail_btn
	assert_true(rail.is_visible_in_tree(), "precondition: a ledger-accepting merchant shows the rail selector")
	assert_true(rail.has_focus(),
		"open_shop must SEED focus on the rail selector — with no focus owner, ui navigation has nowhere to start and every chrome button is pad-unreachable")


func test_a_cash_only_shop_seeds_focus_on_sort_instead() -> void:
	# The fallback, with the rail case above as its control: a cash-only merchant HIDES the rail selector, and focus
	# parked on an invisible button strands the pad just as surely as no owner at all — so Sort, which every shop
	# shows, must take it.
	_open_shop(false)
	assert_true(ShopScreen.is_open(), "precondition: a cash-only merchant still opens the shop")
	var rail: Button = ShopScreen._rail_btn
	var sort: Button = ShopScreen._sort_btn
	assert_false(rail.visible, "precondition: a cash-only merchant hides the rail selector")
	assert_true(sort.is_visible_in_tree(), "precondition: Sort shows on every shop")
	assert_true(sort.has_focus(),
		"a cash-only shop must seed focus on Sort — the rail is hidden, so rail-only seeding strands exactly those shops")
	assert_false(rail.has_focus(), "and never on the hidden rail selector")
