extends GutTest

## AUTHORED-SCENE wiring contract for WeaponBenchScreen (scenes/ui/weapon_bench_screen.tscn +
## weapon_bench_screen.gd), cast from the test_chip_install_screen_scene.gd exemplar — a PANEL_MARGIN band, a
## right-aligned wallet readout and a rail selector, so the pins are the same shape and drift between the two
## screens is visible at a glance. It DIVERGES from that exemplar in one place, deliberately: this card carries a
## notice band and a five-line stat footer the install screen does not, and it pays for them with a SINGLE
## scrolling list instead of the install screen's two — see test_the_card_actually_fits_on_the_screen below,
## which is the pin that matters most in this file.
##
## Prefab WIRING tests — the silent-when-broken seams: the autoload points at the SCENE (not the bare script, or
## the authored layout never loads and _bind_ui null-derefs at BOOT), every %node the script binds exists, no
## text is authored in the scene (strings belong to PlayerText / l10n, never a .tscn), and the layout discipline
## survives an editor rearrange. Behaviour (open / fit / buy / remove) is in-tree and lives in a playtest plus
## tests/test_weapon_bench.gd against the component.
##
## ⭐AND IT PINS CONTROLLER PARITY, both halves. The scene half: the two authored Buttons must keep Button's
## default FOCUS_ALL (an authored `focus_mode = 0` is the regression — atm_screen's chips and chip_install's rows
## both shipped a card with NO focusable control, where `ui_*` navigation has nowhere to start and every action
## is pad-unreachable). The runtime half is a SOURCE pin, because a unit test must not run this autoload's
## open_bench (it wants a live WeaponBench, a live Player and a real viewport).
##
## What is NEW here versus the install screen, and pinned below because nothing else can catch it: this screen's
## THIRD parity part — the stat-delta footer is wired to `focus_entered` as well as `mouse_entered`, so a pad
## player gets the same before→after preview a mouse player does. A preview surface a pad can never reach is not
## a preview surface, and the omission is invisible in a mouse playtest.

const SCENE := "res://scenes/ui/weapon_bench_screen.tscn"
const SCREEN_SOURCE := "res://scripts/ui/weapon_bench_screen.gd"

## Every unique name weapon_bench_screen.gd binds in _bind_ui (plus the two the layout test reaches for) — a
## rename in the editor breaks the bind at boot, so pin the roster here where it fails loudly instead.
const BOUND := ["Root", "Dim", "Content", "Title", "MoneyInset", "GunButton", "MoneyPlayer", "RailButton",
	"NoticeInset", "Notice", "ListScroll", "ListBox",
	"FittedInset", "FittedHeading", "FittedList",
	"PartsInset", "PartsHeading", "PartsList", "Footer", "Detail"]

## The real UI canvas. project.godot ships 396×216 at stretch scale 0.5, which is a 792×432 base that
## aspect="expand" grows to about 792×445 on a 16:9 display. 432 is the SHORT case (an ultrawide, where expand
## adds width instead) and is therefore the one the budget must survive — see test_the_card_actually_fits.
const CANVAS_SHORT := Vector2i(792, 432)
const CANVAS_16_9 := Vector2i(792, 445)


func test_autoload_is_the_authored_scene() -> void:
	# The conversion contract: the autoload IS the scene (root carries the script), not the bare script —
	# otherwise the authored layout silently never loads and _bind_ui null-derefs at boot.
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://project.godot"), OK, "project.godot parses")
	assert_eq(String(cfg.get_value("autoload", "WeaponBenchScreen", "")), "*" + SCENE,
		"the WeaponBenchScreen autoload points at the authored scene, not the bare script")


func test_scene_instantiates_with_every_bound_unique_name() -> void:
	var scene: PackedScene = load(SCENE)
	assert_not_null(scene, "the authored scene loads")
	var inst: Node = scene.instantiate()
	assert_not_null(inst, "it instantiates (empty-PackedScene reimport transients aside)")
	assert_true(inst is CanvasLayer, "root is the CanvasLayer the autoload expects")
	assert_not_null(inst.get_script(), "the root carries weapon_bench_screen.gd")
	for n in BOUND:
		assert_not_null(inst.get_node_or_null("%" + n), "%%%s exists (the script binds it in _bind_ui)" % n)
	inst.free()


func test_scene_authors_no_text() -> void:
	# Strings live in PlayerText (the text-debt ratchet + l10n own them) — a caption typed into the .tscn would
	# bypass both and ship unauthored. The scene must hold only structure.
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	var stack: Array[Node] = [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is Label or n is Button or n is LineEdit:
			assert_eq(String(n.get(&"text")), "", "%s ships with empty text (the script sets it from PlayerText)" % n.name)
		if n is LineEdit:
			assert_eq(String(n.get(&"placeholder_text")), "", "%s ships with an empty placeholder" % n.name)
	inst.free()


func test_authored_chrome_keeps_the_layout_contracts() -> void:
	# The screen-specific discipline survives the scene conversion: the PANEL_MARGIN anchor band, the two stacked
	# full-width sections whose scrolls EXPAND vertically (they share the leftover panel height 50/50), the
	# right-aligned expanding wallet readout, and a full-screen root/dim that ships HIDDEN.
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	for full in ["Root", "Dim"]:
		var c := inst.get_node("%" + full) as Control
		assert_eq(c.anchor_right, 1.0, "%s spans the screen (anchor_right)" % full)
		assert_eq(c.anchor_bottom, 1.0, "%s spans the screen (anchor_bottom)" % full)
	assert_false((inst.get_node("%Root") as Control).visible, "the screen ships hidden until open_bench")
	# The modal inset band — authored anchors must match the script's PANEL_MARGIN pin.
	var margin: float = load(SCREEN_SOURCE).PANEL_MARGIN
	var panel := (inst.get_node("%Content") as Control).get_parent() as PanelContainer
	assert_not_null(panel, "%Content sits in the anchored PanelContainer band")
	assert_almost_eq(panel.anchor_left, margin, 0.0001, "Panel's left anchor is the shared PANEL_MARGIN inset")
	assert_almost_eq(panel.anchor_top, margin, 0.0001, "Panel's top anchor is the shared PANEL_MARGIN inset")
	assert_almost_eq(panel.anchor_right, 1.0 - margin, 0.0001, "Panel's right anchor mirrors PANEL_MARGIN")
	assert_almost_eq(panel.anchor_bottom, 1.0 - margin, 0.0001, "Panel's bottom anchor mirrors PANEL_MARGIN")
	# ⭐ONE scroll, shared by BOTH sections — the constraint the card shipped broken on (see
	# test_the_card_actually_fits_on_the_screen). Each list must sit INSIDE it, so a well-meant editor rearrange
	# that gives either section its own expanding scroll again is caught here rather than in a playtest.
	var scroll := inst.get_node("%ListScroll") as ScrollContainer
	assert_eq(scroll.size_flags_vertical, Control.SIZE_EXPAND_FILL, "the list scroll expands vertically — it takes ALL the leftover panel height")
	assert_eq(scroll.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "the list scroll expands horizontally")
	assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED, "rows shrink to the panel width, never scroll sideways")
	assert_true(scroll.follow_focus,
		"the scroll must FOLLOW FOCUS — with two viewports each list scrolled its own focused row into view for free; sharing one, a pad navigating below the fold would carry the highlight off-screen")
	for list_name in ["FittedList", "PartsList"]:
		var list := inst.get_node("%" + list_name) as VBoxContainer
		assert_eq(list.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "%s rows fill the section width" % list_name)
		assert_true(scroll.is_ancestor_of(list), "%s lives inside the ONE shared scroll" % list_name)
	var expanding := 0
	for c in (inst.get_node("%Content") as VBoxContainer).get_children():
		var ct := c as Control
		if ct != null and ct.size_flags_vertical == Control.SIZE_EXPAND_FILL:
			expanding += 1
	assert_eq(expanding, 1,
		"exactly ONE child of %Content may expand vertically — a second one halves the list, and this card has no height to halve")
	# Wallet readout: right-aligned and EXPAND_FILL so the money phrase lands on the price column's edge, with
	# the rail selector sharing its row.
	var money := inst.get_node("%MoneyPlayer") as Label
	assert_eq(money.horizontal_alignment, HORIZONTAL_ALIGNMENT_RIGHT, "the wallet readout right-aligns onto the price column")
	assert_eq(money.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "the wallet readout spans the row to reach that edge")
	assert_true(inst.get_node("%MoneyInset") is MarginContainer, "the wallet rides a row-inset MarginContainer (margins applied at runtime from the theme)")
	# ⭐The FOOTER is a fixed-height CLIP HOST with the Detail Label anchored inside it — NOT a bare Label in the
	# VBox. A Label reports its full wrapped height as its minimum, so a long preview would grow the footer and
	# shrink the two expanding scrolls above it: the whole card would pump on every hover (the inventory_screen
	# lesson). _bind_ui pins the host's height to a whole number of rendered lines; the scene must give it a host
	# that clips and a child that feeds nothing back.
	var footer := inst.get_node("%Footer") as Control
	assert_false(footer is Label, "the footer is a plain Control clip host, not the Label itself")
	assert_true(footer.clip_contents, "the footer clips — an overflowing preview must be cut, never allowed to grow the card")
	var detail := inst.get_node("%Detail") as Label
	assert_eq(detail.get_parent(), footer, "%Detail is anchored INSIDE the clip host so it feeds no minimum size back to the VBox")
	assert_eq(detail.anchor_right, 1.0, "%Detail fills its host horizontally")
	assert_eq(detail.anchor_bottom, 1.0, "%Detail fills its host vertically")
	assert_eq(detail.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "%Detail wraps — a long stat row must not widen the panel")
	inst.free()


func test_every_authored_button_is_reachable_by_a_pad() -> void:
	# ⭐THE HALF OF CONTROLLER PARITY THAT LIVES IN THE SCENE (the test_atm_screen_scene / test_chip_install pin,
	# same argument): these are the card's only AUTHORED Buttons, and the gun cycler in particular is the
	# focus-seed FALLBACK — the one control that exists in every state, including an empty bag. An authored
	# `focus_mode = 0` on either would leave a pad with nowhere to land whenever the lists are empty. Asserted on
	# the instance rather than by grepping the .tscn, so it reads the value that will actually exist at runtime
	# (Button's own default is FOCUS_ALL — the regression is an authored override).
	var inst: Node = (load(SCENE) as PackedScene).instantiate()
	for btn_name in ["RailButton", "GunButton"]:
		var btn := inst.get_node("%" + btn_name) as Button
		assert_eq(btn.focus_mode, Control.FOCUS_ALL,
			"%s must take focus (no `focus_mode = 0` in the .tscn) — a pad reaches this screen's actions through the Buttons alone" % btn_name)
	inst.free()


func test_the_pad_landing_spot_is_seeded_when_the_card_opens() -> void:
	# The other half of parity is RUNTIME (rows built in _make_row, focus grabbed in open_bench on a live
	# viewport), which a unit test must not run — this autoload's _ready binds real chrome and open_bench wants a
	# live WeaponBench and Player. So it is pinned by SOURCE, the tests/test_payment_rail_selector.gd idiom.
	#
	# ⭐Every offset below is GUARDED before it is sliced or compared: find() answers -1 for a needle that has been
	# renamed away, substr(-1, …) silently slices from the END of the file, and a contains() over that garbage
	# reads as "absent" — a pin that retires itself in silence is worse than no pin at all.
	var src := FileAccess.get_file_as_string(SCREEN_SOURCE)
	assert_gt(src.length(), 0, "weapon_bench_screen.gd must be readable")
	assert_true(src.contains("btn.focus_mode = Control.FOCUS_ALL"),
		"_make_row must build every row FOCUS_ALL — including a disabled one; the rows ARE the pad path, and a control a pad can never land on is not a path")
	assert_true(src.contains("_first_focus = row"),
		"the first row built must be recorded as the screen's landing spot (re-recorded every _rebuild — the old rows are freed)")
	assert_true(src.contains("_first_focus = null"),
		"_rebuild must clear the landing spot BEFORE the fills re-record it, or open_bench is handed a queue_freed Button")
	var open_at := src.find("func open_bench(")
	assert_gt(open_at, -1, "func open_bench( no longer present — the pin is stale")
	assert_eq(src.rfind("func open_bench("), open_at,
		"open_bench must be defined exactly ONCE, or the body sliced below is not the one that runs")
	var open_end := src.find("\nfunc ", open_at + 1)
	assert_gt(open_end, open_at, "open_bench's body must end at the next function — the pin is stale")
	var body := src.substr(open_at, open_end - open_at)
	var shown := body.find("_root.visible = true")
	assert_gt(shown, -1, "_root.visible = true no longer present in open_bench — the pin is stale")
	var grabbed := body.find("_first_focus.grab_focus()")
	assert_gt(grabbed, -1,
		"open_bench must SEED focus on the first row — with no focus owner, ui navigation has nowhere to start and every control is pad-unreachable")
	assert_gt(grabbed, shown,
		"and it must grab AFTER the card is shown — grab_focus on a hidden Control does nothing, so seeding first would leave the pad with no owner anyway")
	# The three-step fallback chain, each candidate checked for VISIBILITY as well as validity: set_available(false)
	# HIDES the rail selector on a cash-only bench, and grab_focus on a hidden Control is a silent no-op.
	assert_true(body.contains("_gun_btn.grab_focus()"),
		"with no rows at all (empty bag — both lists hold hint Labels), the gun cycler must take the seed: it is the one control that exists in every state")
	assert_true(body.contains("_rail_btn.grab_focus()"),
		"and the rail selector is the last resort behind it")
	assert_true(body.contains("_gun_btn.visible"),
		"each focus candidate must be checked for .visible too — a hidden Control cannot take focus, so an unchecked chain lands the pad nowhere")


func test_the_detail_footer_is_wired_to_focus_as_well_as_hover() -> void:
	# ⭐THE THIRD PART OF PARITY, and the one unique to this screen: the before→after stat preview must reach a PAD
	# player. Every shipped hover-footer screen is mouse-only, so the omission would look normal in review and be
	# invisible in a mouse playtest — the pad player simply never learns what a part does before paying for it.
	# One connect per row is the whole cost.
	var src := FileAccess.get_file_as_string(SCREEN_SOURCE)
	assert_gt(src.length(), 0, "weapon_bench_screen.gd must be readable")
	for wiring in ["btn.mouse_entered.connect(_preview", "btn.focus_entered.connect(_preview",
			"btn.mouse_exited.connect(_preview_clear)", "btn.focus_exited.connect(_preview_clear)"]:
		assert_true(src.contains(wiring),
			"_make_row must wire `%s` — the pad gets the same detail the mouse does, and the footer must clear on BOTH exits or it strands a stale preview" % wiring)


func test_the_notice_band_is_never_hidden_and_the_rows_are_muted() -> void:
	# Two invariants that are pure source discipline — nothing about the scene or a live viewport can catch either.
	#
	# 1. The Notice band keeps CONSTANT HEIGHT: bench_notice returns "" for the no-reason key precisely so the band
	#    can say nothing without vanishing. Hiding it with `visible` would re-flow the VBox and hop the card under
	#    the player's cursor mid-transaction (the heal_screen constant-line-count lesson).
	# 2. Every code-built row MUTES its auto-wired generic click: MenuStyle.apply() + the global node_added hook
	#    put a click on every BaseButton under a menu root, and the commit cue already fires from the bench's
	#    shared success tail. Unmuted, a success sounds twice and a refusal once — precisely backwards.
	var src := FileAccess.get_file_as_string(SCREEN_SOURCE)
	assert_gt(src.length(), 0, "weapon_bench_screen.gd must be readable")
	assert_false(src.contains("_notice.visible"),
		"the Notice band must never be hidden with `visible` — it holds a constant one-line height and simply says nothing when there is nothing to say")
	assert_true(src.contains("MenuStyle.set_button_sound(btn, &\"\")"),
		"_make_row must mute the row's generic click — the commit cue lives on WeaponBench's shared success tail, and both would double it")
	assert_true(src.contains("MenuStyle.set_button_sound(_gun_btn, &\"tab\")"),
		"the gun cycler is a sideways VIEW swap, so it wears the tab cue, never a commit cue")
	assert_true(src.contains("MenuStyle.play_denied()"),
		"the REFUSAL half of the sound pair lives here, at the one place each of the bench's bools comes back")
	assert_false(src.contains("get_tree().paused"),
		"a station screen is REAL-TIME — it must never touch get_tree().paused (the atm_screen.gd header carries the argument)")


## ⭐⭐THE PIN THIS FILE EXISTS FOR. Every other assertion here is a wiring check — it reads a flag and says the
## flag is set. Not one of them could see the bug this screen SHIPPED with: the card was authored exactly as
## designed, every unique name resolved, every focus_mode was right, and BOTH row lists rendered at ZERO HEIGHT
## on the real canvas. The whole clickable content of the menu was invisible and unclickable, and the Panel
## overflowed its own anchor band on top of it (minimum 340px inside a 338px band).
##
## Nothing catches that but ARITHMETIC, so this test does the arithmetic the only way that cannot drift: it lays
## the real scene out in a real viewport at the real canvas size and measures what the player would get. The
## chrome is what starved it — title, wallet row, gun row, notice band, two section headings and a five-line stat
## footer, plus eight separations, came to 264px inside a 262px box — so the FLOOR below is deliberately stated in
## ROWS, not pixels: it survives a font change, a skin retune or a new chrome element, and it fails the moment
## someone spends the list's height again.
##
## The floor is ONE row per shipped sibling (chip_install gets 2.0, shop 3.5) — but two is the honest minimum for
## a card whose FITTED section alone is six slots, and the short 792×432 canvas is the case that must clear it.
func test_the_card_actually_fits_on_the_screen() -> void:
	var row_probe := MenuStyle.size_row_button(Button.new())
	var row_h: float = row_probe.custom_minimum_size.y
	row_probe.free()   # size_row_button hands back an OFF-tree Button; unfreed it lands in GUT's orphan report
	assert_gt(row_h, 0.0, "a row button reports a real height (the probe measured under the live theme)")
	for canvas in [CANVAS_SHORT, CANVAS_16_9]:
		var vp := SubViewport.new()
		vp.size = canvas
		vp.disable_3d = true
		add_child_autofree(vp)
		var card: Node = (load(SCENE) as PackedScene).instantiate()
		vp.add_child(card)
		await wait_process_frames(1)
		var root_c := card.get_node("Root") as Control
		root_c.visible = true
		# The captions _rebuild would paint. An EMPTY Button measures a shorter line box than a captioned one, so
		# a card measured blank flatters itself by ~11px per button row — exactly the margin this bug hid in.
		(card.get_node("%Title") as Label).text = PlayerText.bench_title("")
		(card.get_node("%GunButton") as Button).text = PlayerText.bench_gun("Pistol", 2, 6)
		(card.get_node("%MoneyPlayer") as Label).text = PlayerText.wallet_you(1240)
		(card.get_node("%RailButton") as Button).text = "DEBIT"
		(card.get_node("%FittedHeading") as Label).text = PlayerText.BENCH_FITTED_HEADING
		(card.get_node("%PartsHeading") as Label).text = PlayerText.BENCH_PARTS_HEADING
		await wait_process_frames(4)
		var panel := root_c.get_node("Panel") as Control
		var band: float = (panel.anchor_bottom - panel.anchor_top) * float(canvas.y)
		assert_lte(panel.get_combined_minimum_size().y, band,
			"at %dx%d the card's chrome must FIT the PANEL_MARGIN band (%.0fpx) — a bigger minimum makes the Panel overflow its own anchors and hang off the bottom of the screen" % [canvas.x, canvas.y, band])
		var scroll := card.get_node("%ListScroll") as ScrollContainer
		assert_gte(scroll.size.y, row_h * 2.0,
			"at %dx%d the row list must show at least TWO %.0fpx rows (it got %.0fpx = %.2f rows) — the FITTED section alone is six slots, and a list too short to hold one row is a menu with no content at all" % [canvas.x, canvas.y, row_h, scroll.size.y, scroll.size.y / row_h])
		# ⭐The gun cycler shipped 20px wide — its whole caption clipped away — because cap_button sets clip_text,
		# and in Godot 4 clip_text (like any text_overrun_behavior) zeroes a Button's minimum WIDTH outright. Beside
		# an EXPAND_FILL sibling that collapses it to its stylebox margins. It is the one control that exists in
		# every state and the pad's focus-seed fallback, so a nameless sliver is not a cosmetic loss.
		var gun := card.get_node("%GunButton") as Button
		assert_gte(gun.size.x, float(MenuStyle.skin.cycler_value_width),
			"at %dx%d the gun cycler must be at least its skin width budget (%dpx), not the %.0fpx of bare stylebox margin clip_text leaves it" % [canvas.x, canvas.y, MenuStyle.skin.cycler_value_width, gun.size.x])
		card.free()
		vp.queue_free()
		await wait_process_frames(1)
