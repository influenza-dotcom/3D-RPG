extends GutTest

## The AUTHORED-SCENE screen idiom, pinned on its exemplar (scenes/ui/heal_screen.tscn + heal_screen.gd).
## Menus are .tscn scenes a designer/artist edits; the script binds chrome by %unique name and applies the
## skin-driven look on top. These are prefab WIRING contract tests (the silent-when-broken seams): the
## autoload points at the SCENE, every %node the script binds exists, and no text is authored in the scene
## (strings belong to PlayerText / l10n, never a .tscn). The one runtime contract pinned here is the pad focus seed
## in open_heal, driven on a second in-tree instance; the heal transaction itself is playtest territory.

const SCENE := "res://scenes/ui/heal_screen.tscn"
const SCREEN_SOURCE := "res://scripts/ui/heal_screen.gd"

## Every unique name heal_screen.gd binds in _bind_ui — a rename in the editor breaks the bind at boot,
## so pin the roster here where it fails loudly instead.
const BOUND := ["Root", "Dim", "Card", "Title", "Status", "Buttons", "RailButton", "HealButton", "CloseButton"]

var _prev_mouse_mode: Input.MouseMode
var _prev_menu_quiet: bool

func before_each() -> void:
	_prev_mouse_mode = Input.mouse_mode
	_prev_menu_quiet = MenuStyle._quiet

func after_each() -> void:
	# open_heal frees the mouse (ModalMenu.grab_mouse) and the focus test mutes MenuStyle; hand both back.
	Input.mouse_mode = _prev_mouse_mode
	MenuStyle._quiet = _prev_menu_quiet


func test_autoload_is_the_authored_scene() -> void:
	# The conversion contract: the autoload IS the scene (root carries the script), not the bare script —
	# otherwise the authored layout silently never loads and _bind_ui null-derefs at boot.
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://project.godot"), OK, "project.godot parses")
	assert_eq(String(cfg.get_value("autoload", "HealScreen", "")), "*" + SCENE,
		"the HealScreen autoload points at the authored scene, not the bare script")


func test_scene_instantiates_with_every_bound_unique_name() -> void:
	var scene: PackedScene = load(SCENE)
	assert_not_null(scene, "the authored scene loads")
	var inst: Node = scene.instantiate()
	assert_not_null(inst, "it instantiates (empty-PackedScene reimport transients aside)")
	assert_true(inst is CanvasLayer, "root is the CanvasLayer the autoload expects")
	assert_true(inst.get_script() != null and inst.get_script().resource_path == SCREEN_SOURCE,
		"the root carries heal_screen.gd itself, not some other script")
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
	# The fixed-width-card discipline survives the scene conversion: buttons split the card EXPAND_FILL and
	# clip their captions; the status label wraps; the dim and root cover the screen (full-rect anchors).
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	for b in ["HealButton", "CloseButton"]:
		var btn := inst.get_node("%" + b) as Button
		assert_eq(btn.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "%s splits the fixed card width" % b)
		assert_true(btn.clip_text, "%s clips its caption instead of growing the card" % b)
	var status := inst.get_node("%Status") as Label
	assert_eq(status.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "the status line wraps within the card")
	for full in ["Root", "Dim"]:
		var c := inst.get_node("%" + full) as Control
		assert_eq(c.anchor_right, 1.0, "%s spans the screen (anchor_right)" % full)
		assert_eq(c.anchor_bottom, 1.0, "%s spans the screen (anchor_bottom)" % full)
	assert_false((inst.get_node("%Root") as Control).visible, "the screen ships hidden until open_heal")
	inst.free()


func test_every_authored_button_is_reachable_by_a_pad() -> void:
	# ⭐THE HALF OF CONTROLLER PARITY THAT LIVES IN THE SCENE (the test_atm_screen_scene.gd pin, and the exact
	# state that screen once shipped in): the authored Buttons — the rail selector included — must NOT carry
	# `focus_mode = 0`. Button's own default FOCUS_ALL is what a pad navigates onto, so the regression is always
	# an authored override; with every Button refusing focus there is no focus owner to navigate FROM and the
	# whole dialog is pad-unreachable. Asserted on the instance rather than by grepping the .tscn, so it reads
	# the value that will actually exist at runtime.
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	for b in ["RailButton", "HealButton", "CloseButton"]:
		var btn := inst.get_node("%" + b) as Button
		assert_eq(btn.focus_mode, Control.FOCUS_ALL,
			"%s must take focus (no `focus_mode = 0` in the .tscn) — a pad reaches this dialog through its Buttons alone" % b)
	inst.free()


## Stands in for a Healer: the duck-typed surface open_heal / _refresh call (heal_name, heal_cost, do_heal).
## A zero cost is the "fully mended" state, which DISABLES the Heal button — the harder case for focus.
class _StubHealer extends Node:
	var heal_name := "Doc"
	func heal_cost(_player: Node) -> int:
		return 0
	func do_heal(_player: Node) -> bool:
		return false


func test_the_pad_landing_spot_is_seeded_when_the_card_opens() -> void:
	# The other half of parity is RUNTIME: open_heal must hand focus to Heal once the card is visible. Driven on a
	# second, in-tree instance of the authored scene (the HealScreen autoload stays untouched) with an off-tree
	# Player (its _ready never runs) and a stub healer.
	MenuStyle._quiet = true  # silence the open/back cues (restored in after_each): a cue still playing at exit leaks its playback
	var screen: Node = (load(SCENE) as PackedScene).instantiate()
	add_child_autofree(screen)
	var healer: Node = autofree(_StubHealer.new())
	var player = load("res://scripts/player/player.gd").new()
	var heal_btn := screen.get_node("%HealButton") as Button
	var closed := {"count": 0}
	screen.closed.connect(func() -> void: closed["count"] += 1)
	# When focus lands, is the card already on screen? A grab taken while the card is still hidden either fails
	# or seeds a focus owner the player cannot see — both leave the pad with nowhere visible to start.
	var focus_landed_on_visible_card: Array[bool] = []
	heal_btn.focus_entered.connect(func() -> void: focus_landed_on_visible_card.append(heal_btn.is_visible_in_tree()))
	assert_false(heal_btn.has_focus(), "control: the hidden card owns no focus before it opens")
	screen.open_heal(healer, null)  # guard: no player -> refused
	assert_false(screen.is_open(), "control: an open with no player is refused")
	assert_false(heal_btn.has_focus(), "a refused open must not seed focus on a card that never showed")
	assert_eq(closed["count"], 1, "the refuse path still emits `closed` (a dialogue-hosted open would strand otherwise)")
	screen.open_heal(healer, player)
	assert_true(screen.is_open(), "precondition: the same screen opens for a real player")
	assert_true(heal_btn.has_focus(),
		"open_heal must SEED focus on the Heal button — with no focus owner, ui navigation has nowhere to start and every button on the card is pad-unreachable")
	assert_eq(focus_landed_on_visible_card, [true] as Array[bool],
		"focus arrives exactly once, AFTER the card is shown — grab_focus before `_root.visible = true` seeds nothing the pad can use")
	assert_true(heal_btn.disabled,
		"precondition: fully mended, so Heal is DISABLED and yet still holds the pad's landing spot (one step reaches Close)")
	screen.close()
	player.free()
