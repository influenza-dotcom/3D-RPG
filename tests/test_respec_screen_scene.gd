extends GutTest

## AUTHORED-SCENE wiring contract for RespecScreen (scenes/ui/respec_screen.tscn + respec_screen.gd),
## following the heal_screen exemplar (tests/test_heal_screen_scene.gd). Menus are .tscn scenes a
## designer/artist edits; the script binds chrome by %unique name and applies the skin-driven look on
## top. These pin the silent-when-broken seams: the autoload points at the SCENE, every %node the
## script binds exists, and no text is authored in the scene (strings belong to PlayerText / l10n,
## never a .tscn). Behaviour (open/confirm) is in-tree -> playtest.

const SCENE := "res://scenes/ui/respec_screen.tscn"
const SCREEN_SOURCE := "res://scripts/ui/respec_screen.gd"

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
	assert_eq(confirm.size_flags_stretch_ratio, 1.5, "Confirm gets 1.5x the stretch — it carries the cost caption")
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


func test_the_pad_landing_spot_is_seeded_when_the_card_opens() -> void:
	# The other half of parity is RUNTIME (focus grabbed in open_respec on a live viewport), which a unit test
	# must not run — this autoload's _ready binds real chrome and open_respec wants a live RespecStation and
	# Player. So it is pinned by SOURCE, the test_atm_screen_scene.gd / test_payment_rail_selector.gd idiom.
	#
	# Every offset below is guarded before it is sliced or compared: find() answers -1 for a needle that has
	# been renamed away and a bad substr yields "", over which a contains() check quietly reads as "absent" — a
	# pin that retires itself in silence is worse than no pin.
	var src := FileAccess.get_file_as_string(SCREEN_SOURCE)
	assert_gt(src.length(), 0, "respec_screen.gd must be readable")
	var open_at := src.find("func open_respec(")
	assert_gt(open_at, -1, "func open_respec( no longer present — the pin is stale")
	assert_eq(src.rfind("func open_respec("), open_at,
		"open_respec must be defined exactly ONCE, or the body sliced below is not the one that runs")
	var open_end := src.find("\nfunc ", open_at + 1)
	assert_gt(open_end, open_at, "open_respec's body must end at the next function — the pin is stale")
	var body := src.substr(open_at, open_end - open_at)
	var shown := body.find("_root.visible = true")
	assert_gt(shown, -1, "_root.visible = true no longer present in open_respec — the pin is stale")
	var grabbed := body.find("_confirm_btn.grab_focus()")
	assert_gt(grabbed, -1,
		"open_respec must SEED focus on Confirm — with no focus owner, ui navigation has nowhere to start and every button on the card is pad-unreachable")
	assert_gt(grabbed, shown,
		"and it must grab AFTER the card is shown — grab_focus on a hidden Control does nothing, so seeding first would leave the pad with no owner anyway")
