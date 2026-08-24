extends GutTest

## AUTHORED-SCENE wiring contracts for the level-up screen (scenes/ui/level_up_screen.tscn +
## level_up_screen.gd), mirroring the heal-screen exemplar (tests/test_heal_screen_scene.gd). Menus are
## .tscn scenes a designer edits; the script binds chrome by %unique name and applies the skin-driven look
## on top. These pin the silent-when-broken seams: the autoload points at the SCENE, every %node the
## script binds exists, no text is authored in the scene (strings belong to PlayerText / l10n, never a
## .tscn), and the screen-specific layout discipline (PANEL_MARGIN band, edge-pinned header halves,
## scroll-with-centered-body) survives the conversion. Behaviour (open/level-up) is in-tree -> playtest.
##
## ⭐AND IT PINS CONTROLLER PARITY (the atm_screen must-not-recur rule, both halves): the authored RailButton
## must NOT carry `focus_mode = 0`, the code-built stat/perk rows must set FOCUS_ALL, and open_level_up must
## SEED focus on the first row once the panel is visible — with no focus owner, ui navigation has nowhere to
## start and every row on the panel is pad-unreachable.

const SCENE := "res://scenes/ui/level_up_screen.tscn"
const SCREEN_SOURCE := "res://scripts/ui/level_up_screen.gd"

## Every unique name level_up_screen.gd binds in _bind_ui — a rename in the editor breaks the bind at boot,
## so pin the roster here where it fails loudly instead.
const BOUND := ["Root", "Dim", "VBox", "Title", "Header", "LevelLabel", "MoneyLabel", "RailButton", "CreditNotice", "Body", "Rows", "Perks"]


func test_autoload_is_the_authored_scene() -> void:
	# The conversion contract: the autoload IS the scene (root carries the script), not the bare script —
	# otherwise the authored layout silently never loads and _bind_ui null-derefs at boot.
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://project.godot"), OK, "project.godot parses")
	assert_eq(String(cfg.get_value("autoload", "LevelUpScreen", "")), "*" + SCENE,
		"the LevelUpScreen autoload points at the authored scene, not the bare script")


func test_scene_instantiates_with_every_bound_unique_name() -> void:
	var scene: PackedScene = load(SCENE)
	assert_not_null(scene, "the authored scene loads")
	var inst: Node = scene.instantiate()
	assert_not_null(inst, "it instantiates (empty-PackedScene reimport transients aside)")
	assert_true(inst is CanvasLayer, "root is the CanvasLayer the autoload expects")
	assert_not_null(inst.get_script(), "the root carries level_up_screen.gd")
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
	# The screen-specific discipline survives the scene conversion: the PANEL_MARGIN anchor band, the
	# edge-pinned half-row header labels (ellipsis-trimmed so money-length changes never slide them), and
	# the scroll whose EXPAND_FILL centered body is what actually centers the short six-stat list.
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	for full in ["Root", "Dim"]:
		var c := inst.get_node("%" + full) as Control
		assert_eq(c.anchor_right, 1.0, "%s spans the screen (anchor_right)" % full)
		assert_eq(c.anchor_bottom, 1.0, "%s spans the screen (anchor_bottom)" % full)
	assert_false((inst.get_node("%Root") as Control).visible, "the screen ships hidden until open_level_up")
	# The modal inset band — authored anchors must match the script's PANEL_MARGIN pin.
	var margin: float = load("res://scripts/ui/level_up_screen.gd").PANEL_MARGIN
	var panel := inst.get_node("%Root/Panel") as PanelContainer
	assert_not_null(panel, "Root/Panel is the anchor-band PanelContainer")
	# almost_eq: Control anchors are float32 in the engine, so the authored 0.12 reads back ~0.119999997.
	assert_almost_eq(panel.anchor_left, margin, 0.0001, "Panel's left anchor is the shared PANEL_MARGIN inset")
	assert_almost_eq(panel.anchor_top, margin, 0.0001, "Panel's top anchor is the shared PANEL_MARGIN inset")
	assert_almost_eq(panel.anchor_right, 1.0 - margin, 0.0001, "Panel's right anchor mirrors PANEL_MARGIN")
	assert_almost_eq(panel.anchor_bottom, 1.0 - margin, 0.0001, "Panel's bottom anchor mirrors PANEL_MARGIN")
	# Edge-pinned header halves: each label takes half the row so neither MOVES as the money string grows.
	for n in ["LevelLabel", "MoneyLabel"]:
		var l := inst.get_node("%" + n) as Label
		assert_eq(l.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "%s takes half the header row (edge-pinned pair)" % n)
		assert_eq(l.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS, "%s trims a pathological amount within its half" % n)
	assert_eq((inst.get_node("%MoneyLabel") as Label).horizontal_alignment, HORIZONTAL_ALIGNMENT_RIGHT,
		"the wallet half hugs the panel's RIGHT edge")
	# Scroll + centered body: the scroll expands to leftover height; the body fills its viewport with
	# ALIGNMENT_CENTER so the short stat list floats centered while a long perk list scrolls.
	var scroll := inst.get_node("%VBox").get_node("Scroll") as ScrollContainer
	assert_not_null(scroll, "VBox/Scroll hosts the stats + perks list")
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED, "width is anchor-fixed; only length varies")
	assert_eq(scroll.size_flags_vertical, Control.SIZE_EXPAND_FILL, "the scroll expands to all leftover panel height")
	var body := inst.get_node("%Body") as VBoxContainer
	assert_eq(body.size_flags_vertical, Control.SIZE_EXPAND_FILL, "Body fills the scroll viewport so centering can work")
	assert_eq(body.alignment, BoxContainer.ALIGNMENT_CENTER, "short content centers INSIDE the scroll viewport")
	assert_eq((inst.get_node("%VBox") as VBoxContainer).alignment, BoxContainer.ALIGNMENT_CENTER,
		"the chrome VBox keeps the centered-card alignment (inert while the scroll expands, load-bearing if it's removed)")
	# The dynamic containers the rebuilds fill must ship EMPTY — rows are runtime-built per stat/perk.
	for n in ["Rows", "Perks"]:
		assert_eq((inst.get_node("%" + n) as VBoxContainer).get_child_count(), 0,
			"%s ships empty (rows are built at runtime from the station/player)" % n)
	inst.free()


func test_every_authored_button_is_reachable_by_a_pad() -> void:
	# ⭐THE HALF OF CONTROLLER PARITY THAT LIVES IN THE SCENE (the test_atm_screen_scene.gd pin, and the exact
	# regression class that screen once shipped): the one authored Button here — the rail selector — must NOT
	# carry `focus_mode = 0`; Button's own default FOCUS_ALL is what a pad navigates onto, so the regression is
	# always an authored override. Every OTHER action on this panel is a code-built row (_rebuild / _perk_row —
	# the runtime half below pins those), so an unfocusable rail selector would leave the scene authoring zero
	# focusable controls. Asserted on the instance rather than by grepping the .tscn, so it reads the value
	# that will actually exist at runtime.
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	var btn := inst.get_node("%RailButton") as Button
	assert_eq(btn.focus_mode, Control.FOCUS_ALL,
		"RailButton must take focus (no `focus_mode = 0` in the .tscn) — it is this panel's only authored Button and the pad's fallback landing spot")
	# ...on a station that LENDS. A LevelUp with `accepts_credit` off hides the selector (_rebuild calls
	# set_available(false)) and shows %CreditNotice instead, so on THAT card the fallback is gone — which is
	# why open_level_up's fallback branch also tests `_rail_btn.visible`, and why pad reachability really
	# rests on the code-built stat rows (FOCUS_ALL in _rebuild, seeded into _first_focus). Pinned below.
	assert_false((inst.get_node("%CreditNotice") as Label).visible,
		"CreditNotice ships HIDDEN — _rebuild reveals it only for a station that takes no credit, so a lending station's card is unchanged")
	inst.free()


func test_the_pad_landing_spot_is_seeded_when_the_panel_opens() -> void:
	# The other half of parity is RUNTIME (rows built in _rebuild, focus grabbed in open_level_up on a live
	# viewport), which a unit test must not run — this autoload's _ready binds real chrome and open_level_up
	# wants a live LevelUp station and Player. So it is pinned by SOURCE, the test_atm_screen_scene.gd /
	# test_payment_rail_selector.gd idiom.
	#
	# Every offset below is guarded before it is sliced or compared: find() answers -1 for a needle that has
	# been renamed away and a bad substr yields "", over which a contains() check quietly reads as "absent" — a
	# pin that retires itself in silence is worse than no pin.
	var src := FileAccess.get_file_as_string(SCREEN_SOURCE)
	assert_gt(src.length(), 0, "level_up_screen.gd must be readable")
	assert_true(src.contains("btn.focus_mode = Control.FOCUS_ALL"),
		"_rebuild/_perk_row must build the rows FOCUS_ALL — the rows ARE the pad path, and a control a pad can never land on is not a path")
	assert_true(src.contains("_first_focus = btn"),
		"the first stat row built must be recorded as the screen's landing spot")
	var open_at := src.find("func open_level_up(")
	assert_gt(open_at, -1, "func open_level_up( no longer present — the pin is stale")
	assert_eq(src.rfind("func open_level_up("), open_at,
		"open_level_up must be defined exactly ONCE, or the body sliced below is not the one that runs")
	var open_end := src.find("\nfunc ", open_at + 1)
	assert_gt(open_end, open_at, "open_level_up's body must end at the next function — the pin is stale")
	var body := src.substr(open_at, open_end - open_at)
	var shown := body.find("_root.visible = true")
	assert_gt(shown, -1, "_root.visible = true no longer present in open_level_up — the pin is stale")
	var grabbed := body.find("_first_focus.grab_focus()")
	assert_gt(grabbed, -1,
		"open_level_up must SEED focus on the first stat row — with no focus owner, ui navigation has nowhere to start and every row is unreachable")
	assert_gt(grabbed, shown,
		"and it must grab AFTER the panel is shown — grab_focus on a hidden Control does nothing, so seeding first would leave the pad with no owner anyway")
