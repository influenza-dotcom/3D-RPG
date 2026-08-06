extends Control

## Implant-purchase step — the SECOND step of New Game. StartMenu raises it when character creation's "Begin"
## is clicked (the creation overlay stays ALIVE-BUT-HIDDEN underneath, so "Back" returns to it with the typed
## name / stat build / painted shirt intact) and only this screen's confirm resets + stamps the profile and
## boots. Implants are fitted ON CREDIT: the player checks ANY set of starting chips (or none — buying
## nothing is the default and Begin is never gated), each billed at its authored Item.value, and the whole
## bill is subtracted from the starting wallet — the balance is ALLOWED to go NEGATIVE, so a loaded build
## starts the run in debt (every paid service then refuses until the wallet climbs back past its cost; the
## HUD's signed readout is the debt display). On "Begin" it emits confirmed(ability_ids, total_cost); on
## "Back", cancelled.
##
## ROSTER: one row per DISTINCT installable ability, disk-driven — ItemDb already scanned resources/items at
## boot, so dropping a new chip .tres in that folder adds a row here with no code change (its value IS its
## creation price — the designer tunes debt on the chip resource). Chips are filtered by
## Item.is_upgrade_chip() and AbilityRegistry.can_build() (the ChipInstaller rule: never offer a grant a
## typo'd installs_ability would silently turn into nothing) and deduped by ABILITY id, not item id
## (chip_takedown installs silent_takedown — the ids don't mirror). Rows paint Item.label() raw ([PH] marker
## and all, the chip-install idiom) plus the AUTHORED ability name (AbilityRegistry.display_name_for) and the
## price (Zorkmids.money_text) — every chip shares one microchip model/icon, so the ability name is the real
## differentiator. Hover = the shared derived ItemInfo.tooltip ("Installs …"), never authored prose.
##
## The PINNED footer tally (%Tally, under the roster, outside the scroll) shows the running bill + the
## resulting starting balance, projected from GameSettings.economy.player_starting_money — truthful for the
## shipped boot, which assigns no Loadout; a Loadout's money override (player.gd wallet settle) would win at
## spawn without showing here. The balance label tints danger the moment the build goes into debt.
##
## AUTHORED SCENE: scenes/ui/implant_choice.tscn owns the structure (the character_creation idiom — %Dim +
## the 0.05..0.95 panel band + a scrolling roster with the tally and Back/Begin PINNED below it); _bind_ui
## binds the chrome by %unique name and applies the skin look via MenuStyle adopt-helpers. NO text is
## authored in the scene — every string is set here from PlayerText. Like character creation and the TOS
## gate this is a MENU-TIME overlay StartMenu owns: deliberately NOT an InputManager modal and NOT an
## autoload (no class_name — the host preloads the SCENE), and it consumes ui_cancel itself so Escape backs
## out instead of stacking the OptionsMenu autoload over the menu. tests/test_implant_choice_scene.gd pins
## the wiring; tests/test_implant_choice.gd covers behaviour + the StartMenu flow seams.

## Canonical ability-name / buildability accessor (path-preloaded, no class_name — the item_info.gd idiom).
const AbilityRegistry := preload("res://scripts/components/abilities/ability_registry.gd")

signal confirmed(ability_ids: Array, total_cost: float)
signal cancelled

var _begin_btn: Button            ## the PINNED confirm; never gated — an empty cart is a legal (debt-free) start
var _chip_list: VBoxContainer     ## the authored container the roster rows are code-built into
var _rows: Array[Button] = []     ## independent toggle rows, each carrying "ability_id" + "price" metas (tests drive these)
var _tally: Label                 ## the PINNED footer: running bill + resulting starting balance (danger-tinted in debt)

func _ready() -> void:
	MenuStyle.apply(self)  # shared menu Theme + button sounds
	_bind_ui()
	_refresh_tally()  # boots at "bill: 0 · balance: base" — nothing checked yet

## Bind the authored chrome by %unique name, apply the skin-derived values on top, and fill the roster.
func _bind_ui() -> void:
	MenuStyle.style_dim(%Dim)  # the authored dim over the menu behind the panel (skin colour + eats clicks)
	(%Column as VBoxContainer).add_theme_constant_override("separation", MenuStyle.skin.content_separation)

	var title: Label = MenuStyle.cap_label(%Title)
	MenuStyle.style_title(title)
	title.text = MenuStyle.title_text(PlayerText.IMPLANT_CHOICE_TITLE)

	var hint: Label = %Hint
	MenuStyle.style_hint(hint)
	hint.text = PlayerText.IMPLANT_CHOICE_HINT

	_chip_list = %ChipList
	_build_rows()

	# The tally: PINNED under the roster (outside the scroll) so the bill/balance stays visible however
	# long the chip list grows. Painted (and tinted) by _refresh_tally on every toggle.
	_tally = MenuStyle.cap_label(%Tally)

	# Back / Begin (PINNED below the tally — always reachable, the character-creation contract).
	MenuStyle.style_button_row(%Buttons)
	var back: Button = %BackButton
	back.text = PlayerText.BACK
	back.custom_minimum_size = Vector2(MenuStyle.skin.dialog_button_min_width, 0)
	back.pressed.connect(_on_back)
	_begin_btn = %BeginButton
	_begin_btn.text = PlayerText.BEGIN
	_begin_btn.custom_minimum_size = Vector2(MenuStyle.skin.dialog_button_min_width, 0)
	_begin_btn.pressed.connect(_on_begin)

## Fill the roster: one INDEPENDENT toggle row per distinct installable ability (a shop cart, not a radio —
## check as many as you can stomach the debt for; no opt-out row, since buying nothing is just Begin with
## nothing checked). Every toggle re-tallies the bill.
func _build_rows() -> void:
	for c in _chip_list.get_children():
		c.queue_free()
	_rows.clear()
	for item: Item in _chip_roster():
		var price: float = snappedf(item.value, Zorkmids.QUANTUM)
		var row := _make_row(item.label(), AbilityRegistry.display_name_for(item.installs_ability),
				Zorkmids.money_text(price))
		row.set_meta("ability_id", item.installs_ability)
		row.set_meta("price", price)
		row.toggled.connect(_on_row_toggled)
		# Hover for the derived breakdown ("Installs <Ability>" + weight/value) — the chip name alone is [PH].
		MenuStyle.attach_tip(row, ItemInfo.tooltip(item))
		_chip_list.add_child(row)
		_rows.append(row)

## Every distinct installable ability's chip Item, from the ItemDb boot scan (export-safe, unlike the
## editor-only AbilityRegistry.ids() directory listing). Sorted by label so the list order is stable.
func _chip_roster() -> Array[Item]:
	var out: Array[Item] = []
	var seen := {}
	for item: Item in ItemDb.all_items():
		# value <= 0 fails closed (the ChipInstaller/Merchant convention): a mis-authored price must not put
		# a row on this bill whose shown charge the stamp would then diverge from — show == charge, always.
		if item == null or not item.is_upgrade_chip() or item.value <= 0.0:
			continue
		if seen.has(item.installs_ability) or not AbilityRegistry.can_build(item.installs_ability):
			continue
		seen[item.installs_ability] = true
		out.append(item)
	out.sort_custom(func(a: Item, b: Item) -> bool: return a.label().naturalnocasecmp_to(b.label()) < 0)
	return out

## One roster row: a full-width TOGGLE Button carrying an HBox of three Labels — the chip's item label on the
## left (trims with "…" when long), the authored ability name as the accent column, and the PRICE right-aligned
## in the shared skin price column. Mirrors ChipInstallScreen._make_row (same columns — this one just bills at
## Begin instead of on click).
func _make_row(text: String, ability_name: String, price_text: String) -> Button:
	var btn := MenuStyle.size_row_button(Button.new())  # empty-text button: without the pin its rect (selection bar + hitbox) collapses above the labels
	btn.toggle_mode = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb: StyleBox = MenuStyle.theme.get_stylebox(&"normal", &"Button")
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = sb.content_margin_left
	row.offset_top = sb.content_margin_top
	row.offset_right = -sb.content_margin_right
	row.offset_bottom = -sb.content_margin_bottom
	btn.add_child(row)
	var name_l := Label.new()
	name_l.text = text
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # a long name trims; the fixed columns never move
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_l)
	if not ability_name.is_empty():
		var ability_l := Label.new()
		ability_l.text = ability_name
		ability_l.size_flags_horizontal = Control.SIZE_SHRINK_END
		ability_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		ability_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ability_l.add_theme_color_override(&"font_color", MenuStyle.accent())
		row.add_child(ability_l)
	if not price_text.is_empty():
		var price_l := Label.new()
		price_l.text = price_text
		price_l.size_flags_horizontal = Control.SIZE_SHRINK_END
		price_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		price_l.custom_minimum_size.x = float(MenuStyle.skin.price_col_width)  # the shared aligned price column (ShopScreen/ChipInstallScreen budget)
		price_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		price_l.add_theme_color_override(&"font_color", MenuStyle.gold())
		row.add_child(price_l)
	return btn

## Any row flipped either way (independent toggles — no ButtonGroup): just re-tally the bill.
func _on_row_toggled(_on: bool) -> void:
	_refresh_tally()

## The checked rows' ability ids, in list order — the confirmed payload.
func _picked_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for row in _rows:
		if row.button_pressed:
			out.append(StringName(row.get_meta("ability_id")))
	return out

## The checked rows' summed bill — ONE formula feeds the tally display AND the confirmed payload (the
## pickpocket rule: what you show is what you charge).
func _total_cost() -> float:
	var total := 0.0
	for row in _rows:
		if row.button_pressed:
			total += float(row.get_meta("price"))
	return snappedf(total, Zorkmids.QUANTUM)

## Re-paint the footer: the running bill + the post-debit starting balance, projected from the same economy
## knob the boot seeds from (truthful while no Loadout overrides money — see the header note). Gold while
## solvent, danger the moment the build dips into debt.
func _refresh_tally() -> void:
	if _tally == null:
		return
	var base: float = GameSettings.economy.player_starting_money
	var cost := _total_cost()
	var balance := snappedf(base - cost, Zorkmids.QUANTUM)
	_tally.text = PlayerText.implant_choice_tally(cost, balance)
	_tally.add_theme_color_override(&"font_color", MenuStyle.gold() if balance >= 0.0 else MenuStyle.danger())

## Confirm: hand the cart (ability ids + the bill) to StartMenu, which resets + stamps the profile — the
## unlocks AND the debt — and boots. An empty cart is a legal, debt-free start; Begin is never gated.
func _on_begin() -> void:
	confirmed.emit(_picked_ids(), _total_cost())

## Back: drop this step and return to the (kept-alive) character-creation overlay. No profile change.
func _on_back() -> void:
	cancelled.emit()

## Consume ui_cancel while this overlay is up (menu-time overlay, deliberately NOT an InputManager modal —
## the character_creation idiom): Escape backs out to creation instead of stacking OptionsMenu over the menu.
func _input(event: InputEvent) -> void:
	if not visible or not is_inside_tree():
		return
	if event.is_action_pressed(&"ui_cancel"):
		_on_back()
		get_viewport().set_input_as_handled()
