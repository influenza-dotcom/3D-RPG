extends CanvasLayer
## WeaponBenchScreen — the GUNSMITH overlay for a WeaponBench station. Autoload; REAL-TIME — it does NOT pause
## the world (the STATION-SCREEN rule, argued in full in the atm_screen.gd header: standing at a counter is not
## a cutscene, and every station screen in the game is real-time now). PROCESS_MODE_ALWAYS is still KEPT, because
## a dialogue-hosted open ("Modify" on a gunsmith NPC) runs under the CONVERSATION's tree pause — without it the
## card would stop painting and its buttons would stop answering the moment it appeared.
##
## THE SHAPE: one gun CYCLER on top, then two full-width sections stacked vertically (the ChipInstallScreen
## silhouette) — FITTED (one row per slot this bench works on, click to pull a part back out and keep it) and
## PARTS (parts you carry, then parts the bench stocks; click to fit / buy & fit). Under them, the always-present
## NOTICE band says WHY a dim row would refuse, and the fixed-height footer previews the before→after stat block
## of whatever row you are hovering OR focused on.
##
## ⭐WHY A CYCLER AND NOT A THIRD LIST: (a) a third list blows the vertical budget inside the 0.12 anchor band at
## the real 792×444 canvas with two scrolls already expanding; (b) it is ONE focusable control that exists in
## EVERY state — including an empty bag — so it is always a valid focus-seed fallback; (c) it is a sideways VIEW
## swap, so it wears the &"tab" cue (the sort-button / rail-button precedent), never a commit cue.
##
## AUTHORED SCENE: the layout lives in scenes/ui/weapon_bench_screen.tscn (this autoload IS that scene — see
## project.godot [autoload]); this script binds its chrome by %unique name in _bind_ui and applies the
## skin-driven look (MenuStyle style_* adopters) on top, so a designer rearranges the panel in the editor and the
## skin keeps owning colours/fonts/separations. NO text is authored in the scene — every string is set here from
## PlayerText (l10n + the text-debt ratchet own strings, never a .tscn). The rows are CONTENT, built at runtime
## (_rebuild/_make_row); the scene authors only the two list containers they populate.
## tests/test_weapon_bench_screen_scene.gd pins the wiring.
##
## ⭐CONTROLLER PARITY (the atm_screen.gd rule, verbatim, and this screen is built to it from day one): every
## action here is reachable through Buttons alone. THE MECHANISM IS THREE PARTS, all required —
##   1. the authored Buttons (%GunButton, %RailButton) carry NO `focus_mode = 0`; Button's default FOCUS_ALL is
##      what a pad navigates onto, and an authored override is the regression the scene test watches for;
##   2. every CODE-BUILT row sets FOCUS_ALL in _make_row — including a DISABLED one, which still HOLDS focus so
##      `ui_*` navigation has somewhere to start (this shipped broken twice: atm_screen's chips, chip_install's
##      rows), and _rebuild re-seats the landing spot after every commit frees the row that held it;
##   3. open_bench SEEDS focus AFTER the card is visible — with no focus owner at all, navigation has nowhere to
##      start from and EVERY control on the card is pad-unreachable.
## A FOURTH part is specific to this screen: the stat-delta footer is wired to `focus_entered` as well as
## `mouse_entered`, so a pad player gets the same before→after detail a mouse player does. The shipped
## hover-footer screens are mouse-only; a preview surface a pad can never reach is not a preview surface.
##
## ⭐THE BENCH IS DUCK-CALLED (`_bench: Node`), never typed as WeaponBench: the component calls open_bench on us
## and we call fit_mod/remove_mod/refusal_reason/… back on it, which as two class_names would be a preload cycle.
## tests/test_dialogue_speaker_contracts.gd pins both halves of that surface by name.

signal opened
signal closed

## Shared modal inset (matches shop / loot / chess / install chrome). The Panel's anchor fractions are AUTHORED
## in the scene; this const is the pin the scene test checks them against.
const PANEL_MARGIN := 0.12

## The fold engine, for the FOOTER PREVIEW only — this screen never writes a stat block (WeaponBench._refit is the
## single writer). Const-preloaded because the kit carries no class_name (it takes a `resolve` Callable precisely
## so it never names ItemDb).
const WeaponModKit = preload("res://scripts/items/weapon_mod_kit.gd")

## Sentinel for _make_row's `price` argument: this row is not an ACTION, so it has no price column. Only the
## offered-but-empty slot rows use it (0 is a real, reachable price — a free removal — and must stay distinct).
const NO_PRICE := -1

var _root: Control
var _title: Label
var _money: Label                 ## your wallet — the header readout (spendable, NOT .money; see _rebuild)
var _notice: Label                ## the always-present refusal band; NEVER hidden with `visible`
var _detail: Label                ## the fixed-height footer: the hovered/focused row's before→after preview
var _footer: Control              ## _detail's clip host — its height is pinned to whole rendered lines
var _gun_heading: Label
var _gun_btn: Button              ## the CYCLER: captions the selected gun, advances to the next on press
var _rail_btn: PaymentRailButton  ## DEBIT/CREDIT selector; rail_changed drives _rebuild (every row re-prices)
var _fitted_list: VBoxContainer
var _parts_list: VBoxContainer
var _first_focus: Button = null   ## first row built by the LAST _rebuild = the pad landing spot open_bench seeds (never stale — the fills re-record it and the old rows are freed)
var _is_open := false
var _prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _player: Player = null
var _bench: Node = null           ## a WeaponBench — typed Node to avoid a WeaponBench<->WeaponBenchScreen class cycle; its API is called dynamically
var _sel_gun: Item = null         ## the weapon the cycler is showing; every row on the card is about THIS gun

func _ready() -> void:
	layer = 121                                  # peer of the other modal overlays (loot / shop / inventory / install)
	process_mode = Node.PROCESS_MODE_ALWAYS      # a dialogue-hosted open runs under the conversation's pause
	_bind_ui()
	_root.visible = false

func is_open() -> bool:
	return _is_open

# ---------------------------------------------------------------------------------------------------
# Open / close
# ---------------------------------------------------------------------------------------------------

## Open the bench for `bench`, serving `player`. Refuses to stack over another modal / dialogue, and bails safely
## on an invalid bench (a stub without the fit API) or no player. ⭐EVERY refuse path emits `closed` (via
## _refuse_open) so a dialogue-hosted open that suspended the conversation on our `closed` one-shot is never
## stranded — bailing without it leaves the box hidden and the tree paused with no error anywhere.
func open_bench(bench: Node, player: Node) -> void:
	if _is_open or DialogueManager.is_active() or InputManager.any_modal_open(self):
		_refuse_open()
		return
	# Duck-typed guard (bench is Node-typed for the class cycle): a node WITHOUT the fit surface reads as
	# not-a-bench and bails, never crashes.
	if not is_instance_valid(bench) or not bench.has_method(&"fit_mod"):
		_refuse_open()
		return
	_player = player as Player
	if not is_instance_valid(_player) or _player.inventory == null:
		_refuse_open()
		return
	_bench = bench
	_bind(true)
	_is_open = true
	# ONE OPEN CUE, NEVER TWO (the station-screen idiom): a walk-up bench answers with its OWN diegetic
	# StationSpeaker chirp, so the generic UI sting is suppressed exactly when that chirp fires and kept when the
	# smith is a person (no speaker). Past every refuse guard, so a bench that couldn't open never beeps or steals
	# the cursor.
	_prev_mouse_mode = ModalMenu.grab_mouse(not StationSpeaker.chirp(bench))
	var name_v: Variant = bench.get(&"bench_name")
	var nm: String = name_v if name_v is String else ""
	_title.text = MenuStyle.title_text(PlayerText.bench_title(nm))
	_sel_gun = _pick_initial_gun()   # the drawn weapon if it is moddable, else the first moddable one in the bag
	_rebuild()
	_root.visible = true
	# Seed pad/keyboard focus AFTER the card is visible — grab_focus on a hidden Control is a silent no-op, so
	# seeding first would leave the pad with no owner anyway. Three-step chain, each candidate checked for BOTH
	# validity and visibility: the first row (a disabled one still holds focus, which is the point), else the gun
	# cycler (the one control that exists in every state, empty bag included), else the rail selector. The rail is
	# the LAST resort because set_available(false) HIDES it on a cash-only bench — an invisible Control cannot take
	# focus, and a chain that assumed otherwise would land the pad nowhere.
	if is_instance_valid(_first_focus) and _first_focus.visible:
		_first_focus.grab_focus()
	elif is_instance_valid(_gun_btn) and _gun_btn.visible:
		_gun_btn.grab_focus()
	elif is_instance_valid(_rail_btn) and _rail_btn.visible:
		_rail_btn.grab_focus()
	opened.emit()

## Guard failed: we never opened, but a dialogue-hosted open (DialogueManager._suspend_for_menu) suspended the
## conversation on our `closed` one-shot BEFORE calling us. Emit `closed` so _resume_from_menu re-shows the box;
## on the standalone path (WeaponBench.start_talk) nothing is listening, so it is harmless. Do NOT touch
## pause/mouse/_is_open here — none of that was mutated yet.
func _refuse_open() -> void:
	closed.emit()

func close() -> void:
	if not _is_open:
		return
	_bind(false)
	_is_open = false
	_root.visible = false
	ModalMenu.restore_mouse(_prev_mouse_mode)   # its back cue is the only shutdown sound; no commit here closes its own screen, so quiet_next_back() is not needed
	_bench = null
	_player = null
	_sel_gun = null
	_first_focus = null                         # the rows outlive us by a frame (queue_free); never hand the next open a dead Button
	closed.emit()

## (Dis)connect the signals that should repaint the card: the player's bag (a part consumed / a part handed back /
## a gun picked up or dropped), the bench's stock (a part bought off the shelf), and the player's weapon-inventory
## swap stream — that last one is what repaints the header after OUR OWN refit re-equips the gun, since _refit
## replaces the WeaponData object and the cycler's caption is derived from it. Idempotent connect/disconnect.
func _bind(on: bool) -> void:
	var srcs: Array = []
	if is_instance_valid(_player):
		if _player.inventory != null:
			srcs.append(_player.inventory.changed)
		if _player.weapon_system != null and _player.weapon_system.inventory != null:
			srcs.append(_player.weapon_system.inventory.weapon_changed)
	var stock := _bench_stock()
	if stock != null:
		srcs.append(stock.changed)
	for sig in srcs:
		if on and not sig.is_connected(_on_changed):
			sig.connect(_on_changed)
		elif not on and sig.is_connected(_on_changed):
			sig.disconnect(_on_changed)

func _on_changed(_a: Variant = null) -> void:
	if _is_open:
		_rebuild()

func _unhandled_input(event: InputEvent) -> void:
	# Close on the SAME Interact key that opens it (the ray consumes the OPENING press), or on Esc. There is no
	# LineEdit on this card, so the AtmScreen Esc-only exception (a typed key must not close the screen) does not
	# apply here.
	if _is_open and (event.is_action_pressed(InputManager.action_pickup) or event.is_action_pressed(&"ui_cancel")):
		close()
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------------------------------
# Transactions — the REFUSAL half of the sound pair (the commit half lives on the bench)
# ---------------------------------------------------------------------------------------------------

## FIT one part the player is CARRYING onto the selected gun (WeaponBench.fit_mod gates on fitment / slot / the
## registered template / the stat gate / the draw lock / the wallet — every one of them PRE-CHARGE).
## SOUND: the SUCCESS cue lives on WeaponBench._fitted — the shared tail all three transaction paths reach past
## the charge — so only the REFUSAL is cued here, at the one place the bench's bool actually comes back.
## Splitting the pair across two files is deliberate and symmetric with ChipInstaller/ChipInstallScreen:
## duplicating the commit here would double it, and duplicating the refusal into the bench would mean a dozen
## `return false` sites to keep in sync.
func _fit(part: Item) -> void:
	if is_instance_valid(_bench) and is_instance_valid(_player):
		if not _bench.fit_mod(_sel_gun, part, _player):  # the bound signals -> _rebuild refreshes the rows + wallet
			MenuStyle.play_denied()

## BUY one stocked part AND fit it in one payment (WeaponBench.buy_and_fit — same guards, dearer fee, and the part
## never enters the backpack). Refusal cued here for the same reason as _fit's; see its note.
func _buy(part: Item) -> void:
	if is_instance_valid(_bench) and is_instance_valid(_player):
		if not _bench.buy_and_fit(_sel_gun, part, _player):
			MenuStyle.play_denied()

## PULL the part fitted in `slot` back out and keep it (WeaponBench.remove_mod — the one path that moves goods TO
## the player, so it gates on bag space BEFORE the charge). Refusal cued here; see _fit's note.
func _remove(slot: int) -> void:
	if is_instance_valid(_bench) and is_instance_valid(_player):
		if not _bench.remove_mod(_sel_gun, slot, _player):
			MenuStyle.play_denied()

# ---------------------------------------------------------------------------------------------------
# The gun cycler
# ---------------------------------------------------------------------------------------------------

## The weapon the card opens on: the one in the player's HANDS when the bench can work on it (you walked up to
## the smith holding the gun you want changed), else the first moddable weapon in the pack. Null on an empty bag —
## every downstream paint tolerates that and the Notice band says so out loud.
func _pick_initial_gun() -> Item:
	var guns := _moddable()
	if guns.is_empty():
		return null
	var ws: Weapon = _player.weapon_system
	var drawn: WeaponData = ws.equipped_weapon if ws != null else null
	if drawn != null:
		for g in guns:
			var it := g as Item
			if it != null and it.weapon == drawn:
				return it
	return guns[0] as Item

## Advance to the next moddable weapon, WRAPPING. `find` answers -1 for a gun that just left the bag, and -1 + 1
## lands on index 0 — so the "selection went stale" case falls out of the same line instead of needing its own.
func _cycle_gun() -> void:
	if not is_instance_valid(_bench) or not is_instance_valid(_player):
		return
	var guns := _moddable()
	if guns.is_empty():
		return
	_sel_gun = guns[(guns.find(_sel_gun) + 1) % guns.size()] as Item
	_rebuild()

## The bench's own answer for "which of the player's weapons can I work on" — never re-derived here, so the
## cycler can never offer a gun every row would refuse (the bench filters out weapons with no registered ItemDb
## template, which have no pristine base to fold from).
func _moddable() -> Array:
	if not is_instance_valid(_bench) or not is_instance_valid(_player):
		return []
	return _bench.moddable_weapons(_player) as Array

## The bench's stock inventory, type-guarded (a vanished / non-WeaponBench node reads as null).
func _bench_stock() -> CharacterInventory:
	if not is_instance_valid(_bench):
		return null
	var raw: Variant = _bench.get(&"stock")
	return raw if raw is CharacterInventory else null

## Whether this till honours the ledger rails — drives both the rail selector's visibility and which wallet
## number the header quotes, so the two can never disagree.
func _takes_ledger() -> bool:
	if not is_instance_valid(_bench):
		return false
	return bool(_bench.get(&"accepts_ledger"))

# ---------------------------------------------------------------------------------------------------
# Paint
# ---------------------------------------------------------------------------------------------------

func _rebuild() -> void:
	if not is_instance_valid(_bench) or not is_instance_valid(_player):
		return
	# ORDER MATTERS: set_available writes the flag, refresh() re-applies `visible = _available` AND repaints the
	# caption from the live rail (which may have been flipped at an ATM since this card was built). Refreshing
	# first would paint the caption and then show a selector a cash-only bench cannot honour.
	var takes_ledger := _takes_ledger()
	_rail_btn.set_available(takes_ledger)
	_rail_btn.refresh()
	# ⭐spendable(), never .money: a player whose zorkmids are all BANKED must not read "Your zorkmids: 0" beside a
	# row the till would happily serve. The argument is the same flag the bench charges on, so the header quotes
	# exactly the pot the buttons are gated against.
	var purse := _player.spendable(takes_ledger)
	_money.text = PlayerText.wallet_you(purse)
	_money.add_theme_color_override(&"font_color", MenuStyle.wallet_color(purse))  # gold, or danger while in debt
	# The selection may have left the bag since the last paint (sold, dropped, stolen) — re-resolve before anything
	# reads it, or every row below would describe a gun the player no longer has. Walked ONCE: this runs on every
	# inventory.changed, and moddable_weapons is a full bag scan plus a template lookup per weapon.
	var guns := _moddable()
	if _sel_gun != null and not guns.has(_sel_gun):
		_sel_gun = _pick_initial_gun()
	_gun_btn.text = _gun_caption()
	# Nothing to cycle TO is a DEAD press, not a silent one — it still holds focus (Button.disabled does not
	# clear focus_mode), so the pad's landing-spot fallback chain is unaffected.
	_gun_btn.disabled = guns.size() < 2
	# The GUN-LEVEL notice: the reasons that apply to the whole card (no weapon, hands full). Constant height,
	# NEVER hidden with `visible` — a band that appears and disappears hops the card mid-transaction.
	_notice.text = PlayerText.bench_notice(_bench.refusal_reason(_sel_gun, null, _player), 0)
	# ⭐Before the fills, not after: holding the OLD first row would hand open_bench a queue_freed Button, which is
	# the shipped bug this line exists to prevent.
	_first_focus = null
	_fill_fitted()
	_fill_parts()
	_preview_clear()   # the footer's resting state — the selected gun's own header, at constant line count
	# Re-seed the pad landing spot when THIS rebuild just destroyed it (the level_up_screen idiom): every fit / buy
	# / remove / rail flip funnels here and frees the row that HELD focus, which would strand a pad after one
	# action. Only a NULL or DYING owner is stolen from — a player parked on the gun cycler or the rail selector
	# keeps their place. The open-time rebuild lands here with the root still hidden, where grab_focus is a silent
	# no-op — open_bench seeds again right after showing it.
	if _is_open and _root.is_inside_tree() and is_instance_valid(_first_focus):
		var focused: Control = _root.get_viewport().gui_get_focus_owner()
		if focused == null or _fitted_list.is_ancestor_of(focused) or _parts_list.is_ancestor_of(focused):
			_first_focus.grab_focus()

## The cycler's caption (and the footer's resting header): the selected gun's authored label beside its
## filled-slot count. With nothing to work on it says so instead of going blank — a blank Button reads as broken.
func _gun_caption() -> String:
	if _sel_gun == null or _sel_gun.weapon == null:
		return PlayerText.BENCH_NO_GUN
	return PlayerText.bench_gun(_sel_gun.label(), _sel_gun.weapon.fitted_mod_count(), WeaponData.MOD_SLOT_PROPS.size())

## FITTED: one row per slot this bench OFFERS, always — an empty slot renders BENCH_EMPTY_SLOT, dim and disabled.
## Fixed arity is the whole point: the section never collapses and never re-flows as parts come and go, so the
## card cannot hop under the player's cursor mid-transaction. WeaponBench.fitted_parts owns the slot walk (a
## fitted id that no longer resolves comes back with a null `part`, which renders as empty and self-heals).
func _fill_fitted() -> void:
	_clear(_fitted_list)
	for e in _bench.fitted_parts(_sel_gun):
		var slot: int = e.get("slot", 0)
		var part: Item = e.get("part")
		if part == null:
			_add_row(_fitted_list, _make_row(slot, null, NO_PRICE, false, &"", &"", Callable()))
			continue
		# A REMOVE row previews the STRIPPED block (&"" into this slot) — the mirror image of a fit preview.
		# ⭐`removing = true` — the direction is PASSED, not inferred. Parts stack, so a spare copy of a fitted
		# part carries the same Item.id; the bench cannot tell the two rows apart from the id alone, and when it
		# tried, a duplicate rendered as a live FIT row that always refused. See WeaponBench.refusal_reason.
		var reason: StringName = _bench.refusal_reason(_sel_gun, part, _player, true)
		_add_row(_fitted_list, _make_row(slot, part, _bench.remove_fee(part), reason == &"", &"", reason, _remove.bind(slot)))

## PARTS: the parts you CARRY that fit this gun first (FIT rows, priced at the labour fee), then the ones the
## bench STOCKS (BUY & FIT rows, priced at markup + labour). Carried first because fitting one you already own is
## strictly cheaper — the bench excludes a stocked duplicate of a carried part for the same reason.
func _fill_parts() -> void:
	_clear(_parts_list)
	var carried: Array = _bench.fittable_parts(_sel_gun, _player)
	var stocked: Array = _bench.stock_parts(_sel_gun, _player)
	if carried.is_empty() and stocked.is_empty():
		_parts_list.add_child(MenuStyle.make_hint(PlayerText.BENCH_NO_PARTS))
		return
	for p in carried:
		var part := p as Item
		if part == null:
			continue
		var reason: StringName = _bench.refusal_reason(_sel_gun, part, _player)
		_add_row(_parts_list, _make_row(part.weapon_mod.slot, part, _bench.fit_fee(part), reason == &"", part.id, reason, _fit.bind(part)))
	for p in stocked:
		var part2 := p as Item
		if part2 == null:
			continue
		# ⭐RE-PRICE THE DIM. refusal_reason quotes the FIT fee (it cannot know which section a row lives in), and a
		# buy & fit is always dearer — so a shelf row the player cannot fund would otherwise render live. Same
		# predicate, same RAW base, same order as the bench's own guard; only the number differs.
		var price: int = _bench.buy_and_fit_cost(part2)
		var reason2: StringName = _bench.refusal_reason(_sel_gun, part2, _player)
		if reason2 == &"" and not _bench.can_afford(float(price), _player):
			reason2 = &"afford"
		_add_row(_parts_list, _make_row(part2.weapon_mod.slot, part2, price, reason2 == &"", part2.id, reason2, _buy.bind(part2)))

## Add one built row and record the FIRST one as the pad landing spot (fitted fills before parts, so the seed is
## the top-left control either way).
func _add_row(list: VBoxContainer, row: Button) -> void:
	list.add_child(row)
	if _first_focus == null:
		_first_focus = row

## ⭐remove_child BEFORE queue_free: a queued child is still a child for the rest of the frame and still counts
## toward the container's layout, so the section would briefly size itself to the OLD rows plus the new ones.
func _clear(list: VBoxContainer) -> void:
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()

## ONE row: a full-width Button carrying an HBox of THREE Labels — the SLOT in its own fixed left column (so the
## six slot names stack into a readable spine down both sections), the part NAME (trims with "…" when long), and
## the PRICE as its own right-aligned column. The ChipInstallScreen row template widened by one column.
##
##   `part`       null = an offered-but-empty slot (renders BENCH_EMPTY_SLOT, dim, disabled, no price, no preview).
##   `price`      NO_PRICE = no price column at all; 0 = BENCH_FREE (only reachable on a REMOVAL — fitting refuses
##                a zero fee outright); >0 = the ALL-IN quoted total (see the paint note below).
##   `preview_id` what this row would FIT into `slot` — &"" is the removal/strip preview, which is exactly right
##                for a FITTED row and is why the two directions need no second function.
##   `reason`     the row's refusal KEY, already computed by the caller. Passed in rather than re-derived so the
##                Notice band the preview paints can never disagree with the dim the row already carries — the
##                buy & fit rows re-price their own dim, and a second derivation here would miss that.
func _make_row(slot: int, part: Item, price: int, enabled: bool, preview_id: StringName, reason: StringName, on_press: Callable) -> Button:
	var btn := MenuStyle.style_list_row(MenuStyle.size_row_button(Button.new()))  # BOTH, always: height-pinned AND pinned to ROW language (its child Labels carry their own inks — artist button-body art would bury them)
	# ⭐FOCUS_ALL even when DISABLED. The rows ARE the pad path; a card whose only focusable controls are the two
	# authored buttons gives `ui_*` navigation nowhere to start, which is the state atm_screen and chip_install
	# both shipped in. A disabled row still holds focus, and the Notice band then tells the pad player WHY it is
	# dim — which is the whole reason that band is always present.
	btn.focus_mode = Control.FOCUS_ALL
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.disabled = not enabled
	var sb: StyleBox = MenuStyle.theme.get_stylebox(&"normal", &"Button")
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = sb.content_margin_left
	row.offset_top = sb.content_margin_top
	row.offset_right = -sb.content_margin_right
	row.offset_bottom = -sb.content_margin_bottom
	btn.add_child(row)

	var slot_l := MenuStyle.cap_label(Label.new())
	slot_l.text = PlayerText.mod_slot_name(slot)
	slot_l.custom_minimum_size.x = float(MenuStyle.skin.stat_name_col_width)  # shared skin budget — the same column the stat sheets use, so the two surfaces align
	slot_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_l.add_theme_color_override(&"font_color", MenuStyle.dim_color())     # always dim: the slot is context, the NAME is the subject
	row.add_child(slot_l)

	var name_l := Label.new()
	name_l.text = part.label() if part != null else PlayerText.BENCH_EMPTY_SLOT
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # a long part name trims; the price column never moves
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_l.add_theme_color_override(&"font_color", MenuStyle.text_color() if enabled else MenuStyle.skin.disabled_text_color)
	row.add_child(name_l)

	var price_l := Label.new()
	# Paint the ALL-IN number (ShopScreen / ChipInstallScreen parity): a ledger-funded job carries the account's
	# service charge, so the sticker fee alone would under-quote what actually leaves the player. WeaponBench
	# charges through the same player.charge(), which re-derives this same total — the label and the till can
	# never disagree. Note the bench's own can_afford still takes the RAW base (it folds the fee in itself;
	# feeding it the total would fee the fee and falsely refuse).
	if price == NO_PRICE:
		price_l.text = ""
	elif price <= 0:
		price_l.text = PlayerText.BENCH_FREE
	else:
		price_l.text = Zorkmids.money_text(_bench.quoted_total(float(price), _player))  # the whole money phrase — the "zm" word lives in Zorkmids.MONEY_TEMPLATE
	price_l.size_flags_horizontal = Control.SIZE_SHRINK_END
	price_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_l.custom_minimum_size.x = float(MenuStyle.skin.price_col_width)  # fixed-ish floor -> every row's price lands in one aligned column (skin budget, shared with ShopScreen)
	price_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_l.add_theme_color_override(&"font_color", MenuStyle.gold() if enabled else (MenuStyle.danger() if price > 0 else MenuStyle.dim_color()))
	row.add_child(price_l)

	if part != null:
		# Hover a row to see the part's derived breakdown — "Barrel part · Range +8 · Spread -25%" + weight/value
		# (ItemInfo._effect_lines -> WeaponModInfo.part_line). This IS the surface where you decide to fit a part,
		# so it must say what the part DOES, not just its name; a disabled, can't-afford row tips too.
		MenuStyle.attach_tip(btn, ItemInfo.tooltip(part, _player.inventory))
		# ⭐THE PAD GETS THE SAME DETAIL THE MOUSE DOES — focus_entered alongside mouse_entered, at one connect per
		# row. Wired on DISABLED rows as well: reading why you cannot afford something is exactly when the
		# before/after matters most.
		btn.mouse_entered.connect(_preview.bind(slot, preview_id, reason))
		btn.focus_entered.connect(_preview.bind(slot, preview_id, reason))
		btn.mouse_exited.connect(_preview_clear)
		btn.focus_exited.connect(_preview_clear)
	# MUTE the row's auto-wired generic click: MenuStyle.apply() + the global node_added hook wire a click onto
	# EVERY BaseButton under a menu root, and the commit cue already fires from WeaponBench._fitted / _removed —
	# the shared tail of all three transaction paths. Unmuted, a success would sound twice and a refusal once,
	# which is precisely backwards. Muted unconditionally: a dim row is disabled (never emits pressed), but the
	# mute is what makes the funnel the sole voice.
	MenuStyle.set_button_sound(btn, &"")
	if enabled and on_press.is_valid():
		btn.pressed.connect(on_press)
	return btn

# ---------------------------------------------------------------------------------------------------
# The footer preview (before -> after, in the shipped fixed-height hover footer)
# ---------------------------------------------------------------------------------------------------

## Paint what this row would DO to the selected gun: fold `preview_id` into `slot` on a fresh copy of the
## PRISTINE template (&"" = the strip preview a FITTED row shows) and diff it against the gun's live block.
## Nothing here mutates anything — WeaponBench._refit is the single writer of a fitted set; this is the same fold
## run for display, which is why the preview can never disagree with the commit.
##
## The Notice band moves with the footer: a row's own refusal KEY replaces the gun-level one while you are on it,
## so a pad player who cannot press a row reads WHY without a tooltip. _preview_clear puts the gun-level band
## back. `n` is the stat gate's required rating, read only by the &"stat_gate" sentence.
func _preview(slot: int, preview_id: StringName, reason: StringName) -> void:
	if not _is_open or _sel_gun == null or _sel_gun.weapon == null:
		return
	var tmpl := ItemDb.item_by_id(_sel_gun.id)
	if tmpl == null or not tmpl.is_weapon() or tmpl.weapon == null:
		return   # no pristine base to fold from; the bench refuses this gun anyway (its template gate)
	# The row's SUBJECT — the part arriving on a FIT row, the one leaving on a REMOVE row. It names the header and
	# supplies the stat gate's number.
	var subject_id: StringName = preview_id if preview_id != &"" else _sel_gun.weapon.mod_id(slot)
	var subject := ItemDb.item_by_id(subject_id)
	var ids := WeaponModKit.slot_map(_sel_gun.weapon)
	ids[slot] = preview_id
	var after := WeaponModKit.rebuild(tmpl.weapon, ids, ItemDb._resolve_weapon_mod)
	var header: String = subject.label() if subject != null else _gun_caption()
	_detail.text = WeaponModInfo.compare_block(_sel_gun.weapon, after, header, _footer_lines())
	var gate: int = 0
	if subject != null and subject.is_weapon_mod():
		gate = subject.weapon_mod.min_gunplay
	_notice.text = PlayerText.bench_notice(reason, gate)

## The footer's RESTING state: the selected gun's own header over blank rows. compare_block(x, x, …) reports no
## changes and pads to the full budget, so the footer's line count is CONSTANT whether you are hovering a row or
## not — a footer that grew on hover would re-lay-out the two expanding scrolls above it and pump the whole card
## (the inventory_screen lesson). The Notice band goes back to the gun-level question at the same instant.
func _preview_clear() -> void:
	if _detail == null:
		return
	var block: WeaponData = _sel_gun.weapon if _sel_gun != null else null
	_detail.text = WeaponModInfo.compare_block(block, block, _gun_caption(), _footer_lines())
	if is_instance_valid(_bench) and is_instance_valid(_player):
		_notice.text = PlayerText.bench_notice(_bench.refusal_reason(_sel_gun, null, _player), 0)

## The footer's line budget — a designer knob (MenuSkin.footer_hint_lines), floored at 1 so a misconfigured skin
## degrades to a bare header rather than an empty footer.
func _footer_lines() -> int:
	return maxi(MenuStyle.skin.footer_hint_lines, 1)

# ---------------------------------------------------------------------------------------------------
# UI binding (the layout is AUTHORED in scenes/ui/weapon_bench_screen.tscn — this adopts it)
# ---------------------------------------------------------------------------------------------------

## Bind the authored chrome by %unique name, style it from the skin, and wire behaviour. What each piece
## guarantees:
##  * the panel is the PANEL_MARGIN anchor band (authored; the scene test pins the fractions against the const).
##  * the two stacked full-width sections both EXPAND vertically (authored), so they share the leftover panel
##    height 50/50 — the ChipInstallScreen shape.
##  * the wallet readout, the gun row, the notice band and both section headings are row-inset
##    (_style_row_inset) so their edges land on the rows' slot/name/price columns instead of overhanging them.
##  * the NOTICE band reserves ONE rendered line and the FOOTER reserves footer_hint_lines of them, measured off
##    the live Labels — neither may ever be hidden with `visible`, or the card hops.
##  * the ROWS are runtime content: _fill_fitted/_fill_parts rebuild them on every bound-signal change; the scene
##    authors only %FittedList / %PartsList, the containers they populate.
##  * every string is set HERE from PlayerText — the scene ships with empty text properties.
func _bind_ui() -> void:
	_root = %Root
	MenuStyle.apply(_root)  # shared menu Theme (panel/buttons/tooltips/fonts) — reskin via resources/ui/menu_skin.tres
	MenuStyle.style_dim(%Dim)

	var content: VBoxContainer = %Content
	content.add_theme_constant_override("separation", MenuStyle.skin.content_separation)  # shared vertical rhythm

	_title = %Title
	MenuStyle.style_title(_title)
	_title.text = MenuStyle.title_text(PlayerText.BENCH_SCREEN_TITLE)  # open_bench re-titles per bench

	# Wallet — one header readout (your spendable zorkmids). Right-aligned and expanding (authored), header-sized
	# gold (_rebuild re-tints danger while in debt); row-inset so its right edge lands on the rows' price column.
	_money = %MoneyPlayer
	_money.add_theme_font_size_override("font_size", MenuStyle.skin.header_size)
	_money.add_theme_color_override(&"font_color", MenuStyle.gold())
	# The rail selector rides the SAME row as the wallet: flipping it changes every price gate on this card, so
	# its signal drives the rebuild — and nothing else. The button owns its own &"tab" cue (a host cue would stack
	# a second voice) and its own visibility (set_available in _rebuild hides it on a cash-only bench).
	_rail_btn = %RailButton as PaymentRailButton
	MenuStyle.cap_button(_rail_btn)
	_rail_btn.rail_changed.connect(_rebuild)
	_style_row_inset(%MoneyInset)

	# The gun CYCLER row: a heading on the left, the cycling Button on the right. &"tab", never a commit cue —
	# pressing it changes what you are LOOKING at, not what you own.
	_gun_heading = %GunHeading
	_gun_btn = %GunButton
	MenuStyle.cap_button(_gun_btn)
	MenuStyle.set_button_sound(_gun_btn, &"tab")
	_gun_btn.pressed.connect(_cycle_gun)
	_bind_section_heading(_gun_heading, %GunInset, PlayerText.BENCH_GUN_HEADING)

	# The NOTICE band. Hint-styled and pinned to exactly ONE rendered line: it is ALWAYS present and says nothing
	# when there is nothing to say (bench_notice returns "" for the no-reason key), so the card's height never
	# moves as reasons come and go.
	_notice = %Notice
	MenuStyle.style_hint(_notice)
	_notice.custom_minimum_size.y = _line_height(_notice)
	_style_row_inset(%NoticeInset)

	_bind_section_heading(%FittedHeading, %FittedInset, PlayerText.BENCH_FITTED_HEADING)
	_bind_section_heading(%PartsHeading, %PartsInset, PlayerText.BENCH_PARTS_HEADING)
	_fitted_list = %FittedList
	_parts_list = %PartsList

	# The before→after footer, in the shared fixed-height clip host (the inventory_screen / loot_screen
	# construct): the Label is anchored INSIDE a plain Control whose height is a whole number of rendered lines,
	# so an overflowing preview clips cleanly BETWEEN lines and — critically — feeds no minimum size back into
	# the VBox. A bare Label reports its full wrapped height as its minimum, which would grow the footer and
	# SHRINK the two expanding scrolls above it on every hover.
	_footer = %Footer
	_detail = %Detail
	MenuStyle.style_hint(_detail)  # dim wrap-friendly footnote styling from the skin
	_footer.custom_minimum_size.y = float(_footer_lines()) * _line_height(_detail)

## One Label's real rendered line height (get_line_height folds the theme's line_spacing), with the shared
## pre-measurement estimate for the boot frame where the font is not resolvable yet — the inventory_screen
## fallback, verbatim, because a 0 here would collapse the band or the footer to nothing.
func _line_height(l: Label) -> float:
	var h: float = l.get_line_height()
	return h if h > 0.0 else float(MenuStyle.skin.hint_size + 4)

## Adopt one authored section heading: PlayerText string through the single casing seam (headings case with their
## shop/loot/install siblings) + header size, and row-inset its Margin wrapper so the heading's left edge sits
## over the rows' slot column. Copied from chip_install_screen.gd — the two screens are the same silhouette.
func _bind_section_heading(head: Label, inset: MarginContainer, heading: String) -> void:
	head.text = MenuStyle.title_text(heading)
	head.add_theme_font_size_override("font_size", MenuStyle.skin.header_size)
	_style_row_inset(inset)

## Adopt an authored MarginContainer wrapper: left/right margins equal the theme Button's content inset, so a
## header element — a section heading, the wallet readout, the notice band — lines up edge-for-edge with the slot
## column (left) and price column (right) of the Button rows below it. Wraps only header elements, never the row
## Buttons — hit-testing is unaffected. Margins are THEME-derived, so they are applied here, never authored in
## the scene. Copied from chip_install_screen.gd.
func _style_row_inset(m: MarginContainer) -> void:
	var sb: StyleBox = MenuStyle.theme.get_stylebox(&"normal", &"Button")
	m.add_theme_constant_override(&"margin_left", int(sb.content_margin_left))
	m.add_theme_constant_override(&"margin_right", int(sb.content_margin_right))
