extends GutTest

## AUTHORED-SCENE wiring contract for RespecScreen (scenes/ui/respec_screen.tscn + respec_screen.gd),
## following the heal_screen exemplar (tests/test_heal_screen_scene.gd). Menus are .tscn scenes a
## designer/artist edits; the script binds chrome by %unique name and applies the skin-driven look on
## top. These pin the silent-when-broken seams: the autoload points at the SCENE, every %node the
## script binds exists, and no text is authored in the scene (strings belong to PlayerText / l10n,
## never a .tscn). One runtime half is DRIVEN on the live autoload: opening the card seeds pad focus (an off-tree
## RespecStation + a bare Player, never added to the tree — the test_merchant.gd ShopScreen idiom). The confirm
## transaction itself is RespecStation.do_respec, pinned in tests/test_respec.gd.

const SCENE := "res://scenes/ui/respec_screen.tscn"

## Every unique name respec_screen.gd binds in _bind_ui — a rename in the editor breaks the bind at
## boot, so pin the roster here where it fails loudly instead.
const BOUND := ["Root", "Dim", "Card", "Title", "Blurb", "Status", "Scroll", "List", "Buttons", "RailButton", "ConfirmButton", "CancelButton"]


func test_autoload_is_the_authored_scene() -> void:
	# The conversion contract: the autoload IS the scene (root carries the script), not the bare script —
	# otherwise the authored layout silently never loads and _bind_ui null-derefs at boot.
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://project.godot"), OK, "project.godot parses")
	assert_eq(String(cfg.get_value("autoload", "RespecScreen", "")), "*" + SCENE,
		"the RespecScreen autoload points at the authored scene, not the bare script")


func test_scene_instantiates_with_every_bound_unique_name() -> void:
	var scene: PackedScene = load(SCENE)
	assert_not_null(scene, "the authored scene loads")
	var inst: Node = scene.instantiate()
	assert_not_null(inst, "it instantiates (empty-PackedScene reimport transients aside)")
	assert_true(inst is CanvasLayer, "root is the CanvasLayer the autoload expects")
	assert_not_null(inst.get_script(), "the root carries respec_screen.gd")
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
	# The fixed-width-card discipline survives the scene conversion: buttons split the card EXPAND_FILL
	# (Confirm at 1.5x — the emphasized, destructive action) and clip their captions; the blurb + status
	# lines wrap; the perk list scrolls (never horizontally — rows ellipsize) and fills the card width;
	# the dim and root cover the screen (full-rect anchors); the screen ships hidden.
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	for b in ["ConfirmButton", "CancelButton"]:
		var btn := inst.get_node("%" + b) as Button
		assert_eq(btn.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "%s splits the fixed card width" % b)
		assert_true(btn.clip_text, "%s clips its caption instead of growing the card" % b)
	var confirm := inst.get_node("%ConfirmButton") as Button
	var cancel := inst.get_node("%CancelButton") as Button
	assert_gt(confirm.size_flags_stretch_ratio, cancel.size_flags_stretch_ratio,
		"Confirm out-stretches Cancel — the emphasized, destructive action carries the cost caption, so it gets the wider share")
	for wrapping in ["Blurb", "Status"]:
		var lbl := inst.get_node("%" + wrapping) as Label
		assert_eq(lbl.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "%s wraps within the fixed card instead of widening it" % wrapping)
	var scroll := inst.get_node("%Scroll") as ScrollContainer
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED,
		"the refund preview never scrolls horizontally — perk rows ellipsize (see _refresh)")
	var list := inst.get_node("%List") as VBoxContainer
	assert_eq(list.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "the perk list takes the full card width inside the scroll")
	assert_eq(list.alignment, BoxContainer.ALIGNMENT_CENTER, "perk rows stay centred like the procedural build")
	for full in ["Root", "Dim"]:
		var c := inst.get_node("%" + full) as Control
		assert_eq(c.anchor_right, 1.0, "%s spans the screen (anchor_right)" % full)
		assert_eq(c.anchor_bottom, 1.0, "%s spans the screen (anchor_bottom)" % full)
	assert_false((inst.get_node("%Root") as Control).visible, "the screen ships hidden until open_respec")
	inst.free()


func test_every_authored_button_is_reachable_by_a_pad() -> void:
	# ⭐THE HALF OF CONTROLLER PARITY THAT LIVES IN THE SCENE (the test_atm_screen_scene.gd pin, and the exact
	# state that screen once shipped in): the authored Buttons — the rail selector included — must NOT carry
	# `focus_mode = 0`. Button's own default FOCUS_ALL is what a pad navigates onto, so the regression is always
	# an authored override; with every Button refusing focus there is no focus owner to navigate FROM and the
	# whole dialog is pad-unreachable. Asserted on the instance rather than by grepping the .tscn, so it reads
	# the value that will actually exist at runtime.
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	for b in ["RailButton", "ConfirmButton", "CancelButton"]:
		var btn := inst.get_node("%" + b) as Button
		assert_eq(btn.focus_mode, Control.FOCUS_ALL,
			"%s must take focus (no `focus_mode = 0` in the .tscn) — a pad reaches this dialog through its Buttons alone" % b)
	inst.free()


## The live-autoload fixtures for the focus test, released in after_each whatever the asserts did.
var _station: Node = null
var _player: Node = null
var _prev_account: float
var _prev_method: String

func before_each() -> void:
	# Player.charge_total/spendable read the SHARED GameState banking fields while the card prices the respec.
	_prev_account = GameState.account
	_prev_method = GameState.payment_method

func after_each() -> void:
	if RespecScreen.is_open():
		RespecScreen.close()
	if is_instance_valid(_player):
		_player.free()  # frees the PerkManager the preview find-or-created on it, too
	if is_instance_valid(_station):
		_station.free()
	_player = null
	_station = null
	GameState.account = _prev_account
	GameState.payment_method = _prev_method


func test_the_pad_landing_spot_is_seeded_when_the_card_opens() -> void:
	# The other half of parity is RUNTIME: open_respec must hand the viewport a focus owner, or ui navigation has
	# nowhere to start and every button on the card is pad-unreachable. Driven on the live autoload (its _ready
	# already bound the chrome) with an off-tree RespecStation and a bare Player — neither enters the tree, so no
	# station or Player _ready runs. A FREE station and a perk-less player is the edge the landing spot must
	# survive: Confirm is DISABLED there (nothing to refund) and must still take the focus the pad steps off from.
	GameState.account = 0.0
	GameState.payment_method = "debit"
	var st := RespecStation.new()
	st.respec_cost = 0.0
	_station = st
	_player = load("res://scripts/player/player.gd").new()
	get_viewport().gui_release_focus()
	var confirm: Button = RespecScreen._confirm_btn
	assert_false(confirm.has_focus(), "precondition: nothing on the card owns focus before it opens")
	RespecScreen.open_respec(_station, _player)
	assert_true(RespecScreen.is_open(), "precondition: the card opens on a valid station + player")
	assert_true(confirm.disabled, "precondition: a perk-less player leaves Confirm disabled (the edge under test)")
	assert_true(confirm.has_focus(),
		"open_respec must SEED focus on Confirm — with no focus owner, ui navigation has nowhere to start and every button on the card is pad-unreachable")
	RespecScreen.close()
	assert_false(confirm.has_focus(), "closing the card hides it and releases the focus it seeded")
