extends Control

## Free-implant choice — the SECOND step of New Game. StartMenu raises it when character creation's "Begin"
## is clicked (the creation overlay stays ALIVE-BUT-HIDDEN underneath, so "Back" returns to it with the typed
## name / stat build / painted shirt intact) and only the implant confirm resets + stamps the profile and
## boots. The player picks ONE starting microchip ability on the house — or explicitly declines (the
## zero-ability fresh start stays a legal, deliberate build; every OTHER ability still goes through the paid
## ChipInstaller economy). On "Begin" it emits confirmed(ability_id) (&"" = declined); on "Back", cancelled.
##
## ROSTER: one row per DISTINCT installable ability, disk-driven — ItemDb already scanned resources/items at
## boot, so dropping a new chip .tres in that folder adds a row here with no code change. Chips are filtered
## by Item.is_upgrade_chip() and AbilityRegistry.can_build() (the ChipInstaller rule: never offer a grant a
## typo'd installs_ability would silently turn into nothing) and deduped by ABILITY id, not item id
## (chip_takedown installs silent_takedown — the ids don't mirror). Rows paint Item.label() raw ([PH] marker
## and all, the chip-install idiom) plus the AUTHORED ability name (AbilityRegistry.display_name_for) as an
## accent column — every chip shares one microchip model/icon, so the ability name is the real
## differentiator. Hover = the shared derived ItemInfo.tooltip ("Installs …"), never authored prose.
##
## AUTHORED SCENE: scenes/ui/implant_choice.tscn owns the structure (the character_creation idiom — %Dim +
## the 0.05..0.95 panel band + a scrolling roster with Back/Begin PINNED below it); _bind_ui binds the chrome
## by %unique name and applies the skin look via MenuStyle adopt-helpers. NO text is authored in the scene —
## every string is set here from PlayerText. Like character creation and the TOS gate this is a MENU-TIME
## overlay StartMenu owns: deliberately NOT an InputManager modal and NOT an autoload (no class_name — the
## host preloads the SCENE), and it consumes ui_cancel itself so Escape backs out instead of stacking the
## OptionsMenu autoload over the menu. tests/test_implant_choice_scene.gd pins the wiring;
## tests/test_implant_choice.gd covers behaviour + the StartMenu flow seams.

## Canonical ability-name / buildability accessor (path-preloaded, no class_name — the item_info.gd idiom).
const AbilityRegistry := preload("res://scripts/components/abilities/ability_registry.gd")

signal confirmed(ability_id: StringName)
signal cancelled

var _begin_btn: Button            ## the PINNED confirm; gated OFF until a row — a chip or "No Implant" — is picked
var _chip_list: VBoxContainer     ## the authored container the roster rows are code-built into
var _rows: Array[Button] = []     ## the toggle rows in list order, each carrying an "ability_id" meta (tests drive these)
var _picked := false              ## true once ANY row was chosen — the free pick must be explicit, even the pick of nothing
var _choice: StringName = &""     ## the picked ability id; &"" while unpicked OR when "No Implant" is the pick

func _ready() -> void:
	MenuStyle.apply(self)  # shared menu Theme + button sounds
	_bind_ui()
	_refresh_begin()  # boots disabled: no row is down yet

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

	# Back / Begin (PINNED below the scrolling roster — always reachable, the character-creation contract).
	MenuStyle.style_button_row(%Buttons)
	var back: Button = %BackButton
	back.text = PlayerText.BACK
	back.custom_minimum_size = Vector2(MenuStyle.skin.dialog_button_min_width, 0)
	back.pressed.connect(_on_back)
	_begin_btn = %BeginButton
	_begin_btn.text = PlayerText.BEGIN
	_begin_btn.custom_minimum_size = Vector2(MenuStyle.skin.dialog_button_min_width, 0)
	_begin_btn.pressed.connect(_on_begin)

## Fill the roster: one toggle row per distinct installable ability, then the explicit "No Implant" opt-out
## LAST (the opt-out reads after the offers). One ButtonGroup so exactly one row is ever down; Begin stays
## disabled until SOME row is.
func _build_rows() -> void:
	for c in _chip_list.get_children():
		c.queue_free()
	_rows.clear()
	var group := ButtonGroup.new()
	for item: Item in _chip_roster():
		var row := _make_row(item.label(), AbilityRegistry.display_name_for(item.installs_ability), group)
		row.set_meta("ability_id", item.installs_ability)
		row.toggled.connect(_on_pick.bind(item.installs_ability))
		# Hover for the derived breakdown ("Installs <Ability>" + weight/value) — the chip name alone is [PH].
		MenuStyle.attach_tip(row, ItemInfo.tooltip(item))
		_chip_list.add_child(row)
		_rows.append(row)
	var none := _make_row(PlayerText.IMPLANT_CHOICE_NONE, "", group)
	none.set_meta("ability_id", &"")
	none.toggled.connect(_on_pick.bind(&""))
	_chip_list.add_child(none)
	_rows.append(none)

## Every distinct installable ability's chip Item, from the ItemDb boot scan (export-safe, unlike the
## editor-only AbilityRegistry.ids() directory listing). Sorted by label so the list order is stable.
func _chip_roster() -> Array[Item]:
	var out: Array[Item] = []
	var seen := {}
	for item: Item in ItemDb.all_items():
		if item == null or not item.is_upgrade_chip():
			continue
		if seen.has(item.installs_ability) or not AbilityRegistry.can_build(item.installs_ability):
			continue
		seen[item.installs_ability] = true
		out.append(item)
	out.sort_custom(func(a: Item, b: Item) -> bool: return a.label().naturalnocasecmp_to(b.label()) < 0)
	return out

## One roster row: a full-width TOGGLE Button carrying an HBox of two Labels — the chip's item label on the
## left (trims with "…" when long) and the authored ability name right-aligned as its own accent column.
## Mirrors ChipInstallScreen._make_row (minus the price column — this one's free).
func _make_row(text: String, ability_name: String, group: ButtonGroup) -> Button:
	var btn := MenuStyle.size_row_button(Button.new())  # empty-text button: without the pin its rect (selection bar + hitbox) collapses above the labels
	btn.toggle_mode = true
	btn.button_group = group
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
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # a long name trims; the ability column never moves
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
	return btn

## A row went down (ButtonGroup: exactly one is ever down). Ignore the paired "up" of the old pick; arm Begin.
func _on_pick(on: bool, ability_id: StringName) -> void:
	if not on:
		return
	_picked = true
	_choice = ability_id
	_refresh_begin()

## Begin waits on an EXPLICIT pick — a chip or "No Implant" — so the free implant is never skipped by reflex.
func _refresh_begin() -> void:
	if _begin_btn != null:
		_begin_btn.disabled = not _picked

## Confirm: hand the picked ability id (&"" = declined) to StartMenu, which resets + stamps the profile
## (including this grant) and boots. The unpicked refusal backstops any non-button trigger, like Begin's gate.
func _on_begin() -> void:
	if not _picked:
		return
	confirmed.emit(_choice)

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
