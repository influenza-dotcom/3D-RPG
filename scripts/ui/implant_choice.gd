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
## THE LEDGER RATES THE BUILD FIRST: StartMenu hands the pending creation's stat sheet in via present_build
## (before add_child), and the screen rates it through EconomySettings.credit_rating_for — the underwriting
## sheet (CAPACITY / VIABILITY / TRADE minus EXPOSURE, off the authored per-stat actuarial table) — mapped
## through credit_limit_for to a spending LIMIT capped at GameSettings.economy.credit_limit_max. The rating
## also returns a BAND and a FILED REASON as StringName KEYS, which %Verdict / %Reason paint through
## PlayerText selectors; this screen never branches on wording. The tally tracks the credit still
## extendable, and _refresh_tally greys any UNCHECKED row whose price no longer fits — the cart can never
## bill past limit + player_starting_money, so the never-gated Begin stays safe by construction. A CHECKED
## row never greys (any chip can always come back off the bill).
##
## ⭐Investing always RAISES the rating and dumping always lowers it, by the model's construction — so the
## committed build the player is proud of rates above the sheet that allocated nothing (which is a real,
## scored applicant here: the no-file baseline, ~432, good for one cheap chip). An ABSENT sheet — a bare
## scene with no present_build, i.e. no application at all — is the separate fail-OPEN case and rates the
## ceiling, which is what keeps Begin ungated in tests that never hand a build over.
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
## resulting starting balance, projected from GameSettings.economy.player_starting_money — truthful for
## EVERY created run: the stamp writes exactly base − bill into GameState.money, and the Player's
## profile_active wallet branch reads it back on every loaded=false boot, overriding even a Loadout's money
## override (only a dev boot straight into game.tscn — which never shows this screen — keeps a Loadout's
## money). The balance label tints danger the moment the build goes into debt.
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
## The zero-sum allocator — for its STAT_MIN/STAT_MAX pair ONLY. The bank normalizes its underwriting lines
## against the very bounds the builder clamped to, so the rating can never drift from the sheet it rates.
const StatBudget := preload("res://scripts/ui/stat_budget.gd")

signal confirmed(ability_ids: Array, total_cost: float)
signal cancelled

var _begin_btn: Button            ## the PINNED confirm; never gated — an empty cart is a legal (debt-free) start
var _chip_list: VBoxContainer     ## the authored container the roster rows are code-built into
var _rows: Array[Button] = []     ## independent toggle rows, each carrying "ability_id" + "price" metas (tests drive these)
var _tally: Label                 ## the PINNED footer: running bill + resulting starting balance (danger-tinted in debt)
var _hint: Label                  ## the standing on-credit explainer (no build data — that's %Verdict's job)
var _verdict: Label               ## the Ledger's band + score + limit, painted from the rating's band KEY
var _reason: Label                ## the single filed adverse-action line (or the commendation)
var _stat_values: Dictionary = {} ## the pending creation's stat sheet (present_build) — {} = NO application, rates the ceiling
var _credit_score: int = 0        ## the Ledger's rating of _stat_values (EconomySettings.credit_rating_for)
var _credit_limit: float = 0.0    ## the zorkmids that score is good for (EconomySettings.credit_limit_for)
var _credit_band: StringName = &""    ## verdict-band KEY (EconomySettings.BAND_*) — never a display string
var _credit_reason: StringName = &""  ## filed-reason KEY (EconomySettings.REASON_*) — likewise

func _ready() -> void:
	MenuStyle.apply(self)  # shared menu Theme + button sounds
	_compute_credit()  # score the (possibly absent) build BEFORE binding — _bind_ui paints the verdict line
	_bind_ui()
	_refresh_tally()  # boots at "bill: 0 · balance: base · credit left: full" — nothing checked yet

## StartMenu hands the pending creation's stat build here BEFORE add_child, so _ready scores it (the same
## Dictionary the profile stamp will write into GameState.stat_values). Tests may also call it on a LIVE
## screen — the verdict line, tally and row gates all rescore + repaint.
func present_build(stat_values: Dictionary) -> void:
	_stat_values = stat_values.duplicate()
	if _tally != null:  # already bound — a live re-present
		_compute_credit()
		_paint_credit_hint()
		_refresh_tally()

## Rate the build and derive its limit from the economy knobs — the two pure EconomySettings curves are the
## ONE formula (what the verdict announces IS what the row-gating enforces, the pickpocket rule). The
## allocator's own bounds are forwarded so the underwriting normalizers match the sheet's real range.
func _compute_credit() -> void:
	var eco: EconomySettings = GameSettings.economy
	var rating := EconomySettings.credit_rating_for(_stat_values, eco, StatBudget.STAT_MIN, StatBudget.STAT_MAX)
	_credit_score = int(rating["score"])
	_credit_band = rating["band"]
	_credit_reason = rating["reason"]
	_credit_limit = EconomySettings.credit_limit_for(_credit_score,
			eco.credit_score_min, eco.credit_score_max,
			eco.credit_limit_max, eco.credit_limit_step, eco.credit_limit_curve)

## The most the whole cart may ever bill: the bank's limit plus whatever cash the run actually starts with.
func _spendable() -> float:
	return snappedf(GameSettings.economy.player_starting_money + _credit_limit, Zorkmids.QUANTUM)

## Paint the Ledger's two verdict lines from the rating KEYS. Both labels are ALWAYS painted (never hidden),
## so the block keeps a constant height and the roster below it can't hop between a good and a bad build —
## the heal-screen's constant-line-count precedent.
func _paint_credit_hint() -> void:
	if _verdict != null:
		_verdict.text = PlayerText.implant_choice_verdict(_credit_band, _credit_score, _credit_limit)
		# Gold while the Ledger will lend at all; danger the moment it declines outright — the same
		# solvent/refused colour seam every other wallet readout paints through.
		_verdict.add_theme_color_override(&"font_color",
			MenuStyle.danger() if _credit_band == EconomySettings.BAND_DECLINED else MenuStyle.gold())
	if _reason != null:
		_reason.text = PlayerText.implant_choice_reason(_credit_reason)

## Bind the authored chrome by %unique name, apply the skin-derived values on top, and fill the roster.
func _bind_ui() -> void:
	MenuStyle.style_dim(%Dim)  # the authored dim over the menu behind the panel (skin colour + eats clicks)
	(%Column as VBoxContainer).add_theme_constant_override("separation", MenuStyle.skin.content_separation)

	var title: Label = MenuStyle.cap_label(%Title)
	MenuStyle.style_title(title)
	title.text = MenuStyle.title_text(PlayerText.IMPLANT_CHOICE_TITLE)

	_hint = %Hint
	MenuStyle.style_hint(_hint)
	_hint.text = PlayerText.IMPLANT_CHOICE_HINT  # the standing explainer; the build-specific verdict is below it
	# The Ledger's verdict + the one filed reason. Hint-styled like the line above so the three read as one
	# block; _paint_credit_hint then tints the verdict (gold while it lends, danger when it declines).
	_verdict = %Verdict
	MenuStyle.style_hint(_verdict)
	_reason = %Reason
	MenuStyle.style_hint(_reason)
	_paint_credit_hint()

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
	# MUTED on purpose: Escape reaches _on_back through _input too (this overlay owns its own ui_cancel), so the
	# back cue lives in that ONE handler — leaving the generic click here would double it up on the mouse path.
	MenuStyle.set_button_sound(back, &"")
	_begin_btn = %BeginButton
	_begin_btn.text = PlayerText.BEGIN
	_begin_btn.custom_minimum_size = Vector2(MenuStyle.skin.dialog_button_min_width, 0)
	_begin_btn.pressed.connect(_on_begin)
	# MUTED, not cued. This press IS the heaviest commit in the game — it stamps the profile and puts the
	# implant bill on the ledger — but the cue belongs to StartMenu._on_implant_confirmed, which fires it
	# AFTER _start_game(); _start_game's first act is AudioManager.stop_sfx(), which would cut a cue started
	# here. Sounding it on the button as well just stacks a second voice on the one that survives.
	MenuStyle.set_button_sound(_begin_btn, &"")

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
	var btn := MenuStyle.style_list_row(MenuStyle.size_row_button(Button.new()))  # empty-text row: height-pinned, and pinned to ROW language (its child Labels carry their own inks — artist button-body art would bury them)
	btn.toggle_mode = true
	# MUTE the auto-wired generic click: the cue belongs to _on_row_toggled, which knows the DIRECTION of the
	# flip. Same contract as implants_screen._make_toggle_row — order-free, since _wire_button skips a button
	# already carrying the semantic meta. Hover is untouched.
	MenuStyle.set_button_sound(btn, &"")
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
	btn.set_meta("caption_box", row)  # _refresh_tally dims the caption trio when the row stops fitting the credit
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

## Any row flipped either way (independent toggles — no ButtonGroup): re-tally the bill and say WHICH WAY the
## chip went. The step pair carries the direction here exactly as it does on the in-game Implants tab
## (implants_screen._on_row_toggled) — the two implant toggles are the same verb and must sound the same. The
## rows are muted in _make_row so this is the press's only voice. No denied branch: a row that no longer fits
## the credit is DISABLED by _refresh_tally and never emits, and un-checking is always allowed.
func _on_row_toggled(on: bool) -> void:
	MenuStyle.play_step(1 if on else -1)
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

## Re-paint the footer (running bill + post-debit starting balance + credit still extendable, projected
## from the same economy knob the profile stamp debits from — truthful for every created run, see the
## header note) and RE-GATE the roster: an UNCHECKED row whose price no longer fits the remaining credit
## disables + dims (the level-up broke-row look) — the cart can never bill past _spendable(), so Begin
## stays legitimately never-gated. A CHECKED row never disables: any chip can always come back off the
## bill. Gold while solvent, danger the moment the build dips into debt.
func _refresh_tally() -> void:
	if _tally == null:
		return
	var base: float = GameSettings.economy.player_starting_money
	var cost := _total_cost()
	var balance := snappedf(base - cost, Zorkmids.QUANTUM)
	var credit_left := snappedf(maxf(0.0, _spendable() - cost), Zorkmids.QUANTUM)
	_tally.text = PlayerText.implant_choice_tally(cost, balance, credit_left)
	_tally.add_theme_color_override(&"font_color", MenuStyle.wallet_color(balance))  # the shared solvent/debt seam
	for row in _rows:
		if row.button_pressed:
			continue  # checked rows stay live — un-checking must always be possible
		var fits: bool = float(row.get_meta("price")) <= credit_left
		row.disabled = not fits
		(row.get_meta("caption_box") as Control).modulate.a = 1.0 if fits else 0.4

## Confirm: hand the cart (ability ids + the bill) to StartMenu, which resets + stamps the profile — the
## unlocks AND the debt — and boots. An empty cart is a legal, debt-free start; Begin is never gated.
func _on_begin() -> void:
	confirmed.emit(_picked_ids(), _total_cost())

## Back: drop this step and return to the (kept-alive) character-creation overlay. No profile change.
## The BACK cue is fired here rather than on %BackButton (which _bind_ui mutes) because the Escape path below
## lands on this same handler and is not a Button — one cue site keeps mouse and keyboard sounding identical.
func _on_back() -> void:
	MenuStyle.play_back()  # before the emit: the host frees this screen the moment it hears `cancelled`
	cancelled.emit()

## Consume ui_cancel while this overlay is up (menu-time overlay, deliberately NOT an InputManager modal —
## the character_creation idiom): Escape backs out to creation instead of stacking OptionsMenu over the menu.
func _input(event: InputEvent) -> void:
	if not visible or not is_inside_tree():
		return
	if event.is_action_pressed(&"ui_cancel"):
		_on_back()
		get_viewport().set_input_as_handled()
