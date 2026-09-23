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
## survives an editor rearrange. The transaction arithmetic (fit / buy / remove) lives in tests/test_weapon_bench.gd
## against the component.
##
## ⭐AND IT PINS CONTROLLER PARITY, both halves. The scene half: the two authored Buttons must keep Button's
## default FOCUS_ALL (an authored `focus_mode = 0` is the regression — atm_screen's chips and chip_install's rows
## both shipped a card with NO focusable control, where `ui_*` navigation has nowhere to start and every action
## is pad-unreachable). The runtime half is DRIVEN: the real card is instanced into a SubViewport and opened for
## real through open_bench against a bare off-tree WeaponBench and Player (neither one's _ready runs — the
## tests/test_weapon_bench.gd card idiom), then asked where the pad's focus actually landed.
##
## What is NEW here versus the install screen, and driven below because nothing else can catch it: this screen's
## THIRD parity part — the stat-delta footer answers FOCUS as well as hover, so a pad player gets the same
## before→after preview a mouse player does. A preview surface a pad can never reach is not a preview surface,
## and the omission is invisible in a mouse playtest.

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

## The driven-card fixtures (see _open_card). A bare Player: no _ready, so a backpack and a wallet and nothing else.
const PLAYER_PATH := "res://scripts/player/player.gd"
## A REAL registered weapon template: the footer preview folds from ItemDb.item_by_id(gun.id).
const GUN_ID := &"pistol"
## Minted part ids, namespaced away from test_weapon_bench.gd's and every shipped mod_*.tres.
const P_BARREL := &"test_bench_card_barrel"
const P_SIGHT := &"test_bench_card_sight"

## Shared state the driven card touches, restored in after_each: the bench gates on the payment seam, which reads
## GameState's banking fields, and open_bench / close move the global mouse mode.
var _prev_account: float
var _prev_method: String
var _prev_mouse: Input.MouseMode


func before_each() -> void:
	_prev_account = GameState.account
	_prev_method = GameState.payment_method
	_prev_mouse = Input.mouse_mode
	GameState.account = 0.0
	GameState.payment_method = "debit"


func after_each() -> void:
	for id in [P_BARREL, P_SIGHT]:
		ItemDb._by_id.erase(id)
	GameState.account = _prev_account
	GameState.payment_method = _prev_method
	Input.mouse_mode = _prev_mouse
	if MenuStyle._denied_player != null:
		MenuStyle._denied_player.stop()


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


# --- Controller parity and the card's own discipline, DRIVEN ---------------------------------------------------
## Everything below instances the REAL card and opens it for REAL (see _open_card), then asks the viewport, the
## rows and MenuStyle what a player would actually get — never the script's source text.

## A bare bench with an empty shelf (off-tree, so _ready never seeded one); every slot offered, the shipped default.
func _bench() -> WeaponBench:
	var b := WeaponBench.new()
	b.stock = CharacterInventory.new()
	return b


func _player(money: float = 5000.0) -> Player:
	var p = load(PLAYER_PATH).new()  # no _ready -> bare backpack, no weapon component
	p.inventory = CharacterInventory.new()
	p.money = money
	return p


## A UNIQUE pistol Item — its own WeaponData, so a fit never writes through to the registered template.
func _gun() -> Item:
	var tmpl := ItemDb.item_by_id(GUN_ID)
	assert_true(tmpl != null, "resources/items/ must still ship a '%s' weapon item — the driven card mods it" % GUN_ID)
	return tmpl.clone_unique()


## A minted weapon part, REGISTERED with ItemDb so the footer's fold resolves it. One ADD line is enough: the preview
## only has to CHANGE something, and the fold itself is pinned in tests/test_weapon_mods.gd.
func _part(id: StringName, display: String, slot: int, min_gunplay: int = 0) -> Item:
	var line := WeaponStatDelta.new()
	line.property = &"effective_range"
	line.op = WeaponStatDelta.Op.ADD
	line.amount = 8.0
	var lines: Array[WeaponStatDelta] = []
	lines.append(line)
	var mod := WeaponMod.new()
	mod.slot = slot
	mod.deltas = lines
	mod.min_gunplay = min_gunplay
	var part := Item.new()
	part.id = id
	part.display_name = display
	part.category = Item.Category.MISC
	part.max_stack = 10
	part.value = 100.0
	part.weapon_mod = mod
	ItemDb._by_id[id] = part
	return part


## THE REAL CARD, OPENED FOR REAL: the authored scene in a SubViewport at the shipped canvas, its own _ready binding
## the chrome, then open_bench itself — every refuse guard, the gun pick, _rebuild and the focus seed. Two frames
## after, so layout has settled before anything is measured.
func _open_card(b: WeaponBench, p: Player) -> CanvasLayer:
	var vp := SubViewport.new()
	vp.size = CANVAS_16_9
	vp.disable_3d = true
	add_child_autofree(vp)
	var card: CanvasLayer = (load(SCENE) as PackedScene).instantiate()
	vp.add_child(card)
	await wait_process_frames(1)
	card.open_bench(b, p)
	await wait_process_frames(2)
	return card


## Close through the card's own close() (unbinds the bag / stock signals, restores the mouse) and free the off-tree
## rig. The SubViewport and the card itself go with add_child_autofree.
func _close_card(card: CanvasLayer, b: WeaponBench, p: Player) -> void:
	card.close()
	b.stock.free()
	b.free()
	p.inventory.free()
	p.free()


## Every row Button painted in one section, in paint order (a section holding only its hint Label has none).
func _rows(card: Node, list_name: String) -> Array[Button]:
	var out: Array[Button] = []
	for c in card.get_node("%" + list_name).get_children():
		if c is Button:
			out.append(c as Button)
	return out


## The row in `list_name` whose NAME column reads `label` (the _make_row shape: Button > HBox > [slot, name, price]).
func _row_named(card: Node, list_name: String, label: String) -> Button:
	for row in _rows(card, list_name):
		if row.get_child_count() == 0:
			continue
		var hb: Node = row.get_child(0)
		if hb.get_child_count() >= 2 and hb.get_child(1) is Label and (hb.get_child(1) as Label).text == label:
			return row
	return null


## ⭐THE PAD HAS SOMEWHERE TO START. Opening the card must leave a focus owner, and it must be the TOP row — which on
## a fresh gun is an EMPTY slot, dim and DISABLED. That one fact carries the three runtime parity parts at once: rows
## hold focus even when disabled (atm_screen's chips and chip_install's rows both shipped without), the first row
## built is recorded as the landing spot, and the seed lands after the card is SHOWN (grab_focus on a hidden Control
## is a silent no-op). From that spot, walking focus forward must reach every row on the card.
func test_opening_the_card_hands_the_pad_its_top_row() -> void:
	var b := _bench()
	var p := _player()
	var gun := _gun()
	var barrel := _part(P_BARREL, "Card Test Barrel", WeaponData.ModSlot.BARREL)
	p.inventory.add(gun, 1)
	p.inventory.add(barrel, 1)
	var card := await _open_card(b, p)
	assert_true(card.is_open(), "precondition: open_bench accepted a real bench and a player carrying a gun")
	var rows: Array[Button] = _rows(card, "FittedList")
	rows.append_array(_rows(card, "PartsList"))
	assert_gt(rows.size(), 1, "precondition: the card painted its slot rows and the carried part's row")
	if rows.size() < 2:
		_close_card(card, b, p)
		return
	var top: Button = rows[0]
	assert_true(top.disabled, "precondition: the top row is an EMPTY slot, painted dim and disabled")
	assert_eq(card.get_viewport().gui_get_focus_owner(), top,
		"opening the card must hand the pad the TOP row, disabled or not — with no focus owner ui_* navigation has nowhere to start and every control is pad-unreachable")
	var reached := {}
	var at: Control = top
	for i in 64:
		reached[at] = true
		at = at.find_next_valid_focus()
		if at == null or at == top:
			break
	for row in rows:
		assert_true(reached.has(row),
			"row %d of %d must be reachable by walking focus forward from the landing spot — a row a pad can never land on is not a path" % [rows.find(row), rows.size()])
	assert_false(get_tree().paused, "a station screen is REAL-TIME: opening the card must never pause the world")
	_close_card(card, b, p)
	gun = null
	barrel = null


## ...AND WITH NOTHING TO LIST. An empty bag has no gun, so FITTED paints no slot rows and PARTS holds only its hint:
## there is no row to seed. The gun cycler is the one control present in every state, so the pad lands there.
func test_an_empty_bag_hands_the_pad_the_gun_cycler() -> void:
	var b := _bench()
	var p := _player()
	var card := await _open_card(b, p)
	assert_true(card.is_open(), "precondition: an empty bag still opens the card (the Notice band says why nothing is listed)")
	assert_eq(_rows(card, "FittedList").size() + _rows(card, "PartsList").size(), 0, "precondition: no rows at all")
	assert_eq(card.get_viewport().gui_get_focus_owner(), card.get_node("%GunButton"),
		"with no rows the gun cycler must take the pad's focus — it exists in every state, and a seed that stopped at the rows would leave the pad nowhere")
	_close_card(card, b, p)


## ⭐A COMMIT FREES THE ROW THE PAD WAS ON. Every fit repaints both lists, destroying the focused row AND the landing
## spot the last paint recorded. The repaint must re-record the spot before it refills the lists and hand focus to a
## LIVE row — or the pad is stranded after one action, and a stale landing spot is a queue_freed Button handed to
## grab_focus.
func test_a_commit_re_seats_the_pad_on_a_live_row() -> void:
	var b := _bench()
	var p := _player()
	var gun := _gun()
	var barrel := _part(P_BARREL, "Card Test Barrel", WeaponData.ModSlot.BARREL)
	p.inventory.add(gun, 1)
	p.inventory.add(barrel, 1)
	var card := await _open_card(b, p)
	var row := _row_named(card, "PartsList", barrel.label())
	assert_true(row != null and not row.disabled, "precondition: the carried barrel paints a live FIT row")
	if row == null:
		_close_card(card, b, p)
		return
	row.grab_focus()
	assert_eq(card.get_viewport().gui_get_focus_owner(), row, "precondition: the pad is on the barrel's row")
	row.pressed.emit()  # what the pad's ui_accept delivers — through the row's own bound action
	assert_true(_row_named(card, "FittedList", barrel.label()) != null, "precondition: the fit went through and the card repainted")
	var owner: Control = card.get_viewport().gui_get_focus_owner()
	assert_true(owner != null and owner.is_inside_tree() and not owner.is_queued_for_deletion(),
		"after a commit the pad must be on a LIVE control — the row it pressed was just freed by the repaint")
	var fitted := card.get_node("%FittedList")
	var parts := card.get_node("%PartsList")
	assert_true(owner != null and (fitted.is_ancestor_of(owner) or parts.is_ancestor_of(owner)),
		"...and on a row of the REBUILT card, so the pad's next press does something")
	_close_card(card, b, p)
	await wait_process_frames(1)  # let the rows the repaints queue_freed actually go, so GUT reports no orphans
	gun = null
	barrel = null


## ⭐THE PREVIEW REACHES A PAD. Focusing a part row must paint the same before→after footer hovering it does, and
## leaving the row — by focus or by mouse — must put the footer back at rest, or a stale preview describes a row the
## player is no longer on.
func test_the_footer_previews_a_focused_row_exactly_as_a_hovered_one() -> void:
	var b := _bench()
	var p := _player()
	var gun := _gun()
	var barrel := _part(P_BARREL, "Card Test Barrel", WeaponData.ModSlot.BARREL)
	p.inventory.add(gun, 1)
	p.inventory.add(barrel, 1)
	var card := await _open_card(b, p)
	var detail := card.get_node("%Detail") as Label
	var resting: String = detail.text
	var row := _row_named(card, "PartsList", barrel.label())
	assert_true(row != null, "precondition: the carried barrel paints a row")
	if row == null:
		_close_card(card, b, p)
		return
	row.grab_focus()
	var focused_preview: String = detail.text
	assert_ne(focused_preview, resting, "a pad focusing a part row must repaint the footer — the preview cannot be mouse-only")
	assert_true(focused_preview.contains(barrel.label()),
		"...with that part's own before→after block, headed by its name (the footer read: %s)" % focused_preview.c_escape())
	(card.get_node("%GunButton") as Button).grab_focus()
	assert_eq(detail.text, resting, "moving focus OFF the row must put the footer back at rest")
	row.mouse_entered.emit()
	assert_eq(detail.text, focused_preview, "a hover paints exactly the preview a focus does — one surface, two ways in")
	row.mouse_exited.emit()
	assert_eq(detail.text, resting, "...and the mouse leaving clears it too")
	_close_card(card, b, p)
	gun = null
	barrel = null


## THE NOTICE BAND HOLDS ITS LINE. It says nothing at rest and names the refusal while you are on a gated row — and in
## both states it is ON the card at the same height, so nothing below it hops under the cursor mid-transaction (the
## heal_screen constant-line-count lesson).
func test_the_notice_band_keeps_its_place_whether_or_not_it_has_something_to_say() -> void:
	var b := _bench()
	var p := _player()
	var gun := _gun()
	var sight := _part(P_SIGHT, "Card Test Sight", WeaponData.ModSlot.SIGHT, 99)  # a Gunplay gate nobody meets
	p.inventory.add(gun, 1)
	p.inventory.add(sight, 1)
	var card := await _open_card(b, p)
	var notice := card.get_node("%Notice") as Label
	var parts := card.get_node("%PartsList") as Control
	assert_eq(notice.text, "", "precondition: at rest, with a gun in the bag and nothing refused, the band has nothing to say")
	assert_true(notice.is_visible_in_tree(), "the SILENT band must stay on the card — hiding it re-flows everything under it")
	var rest_h: float = notice.size.y
	var rest_rows: Rect2 = parts.get_global_rect()
	var row := _row_named(card, "PartsList", sight.label())
	assert_true(row != null and row.disabled, "precondition: the gated sight paints a dim row")
	if row == null:
		_close_card(card, b, p)
		return
	row.mouse_entered.emit()
	await wait_process_frames(2)
	assert_ne(notice.text, "", "precondition: on the gated row the band names the refusal")
	assert_true(notice.is_visible_in_tree(), "the SPEAKING band is on the card too")
	assert_eq(notice.size.y, rest_h, "the band is the same height speaking as silent")
	assert_eq(parts.get_global_rect(), rest_rows, "...so the rows under it do not move when a reason comes or goes")
	_close_card(card, b, p)
	gun = null
	sight = null


## THE BENCH IS THE ONLY VOICE OF A COMMIT. MenuStyle's node_added hook puts the generic click on every Button that
## joins a menu root, and the success cue already fires from WeaponBench's shared tail — an unmuted row would sound
## twice on a success and once on a refusal, precisely backwards. The gun cycler is a sideways VIEW swap and wears the
## tab cue instead. The probe Button is the control: it proves the hook is live under THIS card, so a row without the
## click was muted rather than simply never wired.
func test_rows_carry_no_generic_click_and_the_cycler_wears_the_tab_cue() -> void:
	var b := _bench()
	var p := _player()
	var gun := _gun()
	var barrel := _part(P_BARREL, "Card Test Barrel", WeaponData.ModSlot.BARREL)
	p.inventory.add(gun, 1)
	p.inventory.add(barrel, 1)
	var card := await _open_card(b, p)
	var root := card.get_node("%Root")
	var probe := Button.new()
	root.add_child(probe)
	assert_true(probe.pressed.is_connected(MenuStyle._play_click),
		"precondition: an ordinary Button joining this card DOES get the generic click from the node_added hook")
	root.remove_child(probe)
	probe.free()
	var rows: Array[Button] = _rows(card, "FittedList")
	rows.append_array(_rows(card, "PartsList"))
	assert_gt(rows.size(), 0, "precondition: the card painted rows")
	for row in rows:
		assert_false(row.pressed.is_connected(MenuStyle._play_click),
			"row %d must carry NO generic click — the commit cue lives on the bench's success tail, and both would double it" % rows.find(row))
	var gun_btn := card.get_node("%GunButton") as Button
	assert_false(gun_btn.pressed.is_connected(MenuStyle._play_click), "the gun cycler carries no generic click either")
	assert_eq(StringName(gun_btn.get_meta(&"_snd_semantic", &"")), &"tab",
		"...it speaks the TAB cue: cycling the gun changes what you are LOOKING at, never what you own")
	_close_card(card, b, p)
	gun = null
	barrel = null


## THE REFUSAL HALF OF THE SOUND PAIR lives on this card, at the one place the bench's bool comes back. A commit the
## bench refuses must SAY no — a silent refusal reads as a dead button — and a commit it honours must not.
func test_a_refused_commit_says_no_and_an_honoured_one_does_not() -> void:
	var b := _bench()
	var p := _player()
	var gun := _gun()
	var barrel := _part(P_BARREL, "Card Test Barrel", WeaponData.ModSlot.BARREL)
	var sight := _part(P_SIGHT, "Card Test Sight", WeaponData.ModSlot.SIGHT)
	p.inventory.add(gun, 1)
	p.inventory.add(barrel, 1)
	p.inventory.add(sight, 1)
	var card := await _open_card(b, p)
	var denied: AudioStreamPlayer = MenuStyle._denied_player
	assert_true(denied != null, "precondition: MenuStyle built its denial voice")
	var barrel_row := _row_named(card, "PartsList", barrel.label())
	assert_true(barrel_row != null and not barrel_row.disabled, "precondition: the carried barrel paints a live FIT row")
	if denied == null or barrel_row == null:
		_close_card(card, b, p)
		return
	denied.stop()
	barrel_row.pressed.emit()
	assert_true(_row_named(card, "FittedList", barrel.label()) != null, "precondition: the barrel fit went through")
	assert_false(denied.playing, "an HONOURED fit must not sound the refusal cue")
	var sight_row := _row_named(card, "PartsList", sight.label())  # the fit above repainted the list
	assert_true(sight_row != null and not sight_row.disabled, "precondition: the sight is still offered as a live FIT row")
	if sight_row == null:
		_close_card(card, b, p)
		return
	p.money = 0.0  # the wallet empties while the card is open: no bound signal repaints the row's dim
	sight_row.pressed.emit()
	assert_true(_row_named(card, "FittedList", sight.label()) == null, "precondition: the unfunded fit was refused")
	assert_true(denied.playing,
		"a REFUSED fit must speak the denied cue — nothing else in the game answers that press, so silence reads as a dead button")
	_close_card(card, b, p)
	await wait_process_frames(1)  # let the rows the repaint queue_freed actually go, so GUT reports no orphans
	gun = null
	barrel = null
	sight = null


## ⭐⭐THE PIN THIS FILE EXISTS FOR. The scene pins above are wiring checks — each reads a flag and says the
## flag is set — and the driven tests watch focus, the footer and the cues. Not one of them could see the bug this
## screen SHIPPED with: the card was authored exactly as
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
