extends CanvasLayer
## HealScreen — the PAY-TO-HEAL overlay for a Healer component. Autoload; REAL-TIME — it does NOT pause the
## world (the STATION-SCREEN rule, argued in full in the atm_screen.gd header; PROCESS_MODE_ALWAYS anyway, so
## a dialogue-hosted open keeps working under the conversation's pause); frees the mouse on open.
## Restores HP to FULL and clears ALL limb damage for zorkmids; the cost is LINEAR in missing HP. Opened by
## Healer.start_talk (standalone med-station) or the dialogue "Heal" option (open_heal).
##
## AUTHORED SCENE: the layout lives in scenes/ui/heal_screen.tscn (this autoload IS that scene — see
## project.godot [autoload]); this script binds its chrome by %unique name in _bind_ui and applies the
## skin-driven look (MenuStyle style_* adopters) on top, so a designer rearranges the card in the editor
## and the skin keeps owning colours/fonts/width pins. NO text is authored in the scene — every string is
## set here from PlayerText (l10n + the text-debt ratchet own strings, never a .tscn). The exemplar for
## the scene-based screen idiom (AUTHORING_GUIDE "Menus are scenes"); tests/test_heal_screen_scene.gd
## pins the wiring.

signal opened
signal closed


var _root: Control
var _title: Label
var _status: Label
var _heal_btn: Button
var _rail_btn: PaymentRailButton  ## DEBIT/CREDIT selector; its rail_changed drives _refresh (the Heal gate moves with it)
var _is_open := false
var _prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _player: Player = null
var _healer: Node = null  ## a Healer — typed Node to avoid a Healer<->HealScreen class cycle; its API is called dynamically

func _ready() -> void:
	layer = 121                                  # peer of the other modal overlays (loot / inventory / shop)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bind_ui()
	_root.visible = false

func is_open() -> bool:
	return _is_open

## Open the heal screen for `healer`, treating `player`. Refuses to stack over another modal / dialogue, and
## bails safely on an invalid healer or no player. EVERY refuse path emits `closed` (via _refuse_open) so a
## dialogue-hosted open that suspended the conversation on our `closed` one-shot is never stranded (see below).
func open_heal(healer: Node, player: Node) -> void:
	if _is_open or DialogueManager.is_active() or InputManager.any_modal_open(self):  # M5: refuse over ANY other menu (incl. QuestJournal)
		_refuse_open()
		return
	if not is_instance_valid(healer):
		_refuse_open()
		return
	_player = player as Player
	if not is_instance_valid(_player):
		_refuse_open()
		return
	_healer = healer
	_is_open = true
	# ONE OPEN CUE, NEVER TWO (the station-screen idiom): a self-serve med-station answers with its OWN diegetic
	# StationSpeaker chirp, so the generic UI sting is suppressed exactly when that chirp fires and kept when the
	# healer is a person (no speaker). Past every refuse guard, so a station that couldn't open never beeps.
	_prev_mouse_mode = ModalMenu.grab_mouse(not StationSpeaker.chirp(healer))
	var heal_name_v: Variant = healer.get(&"heal_name")  # duck-typed: only is_instance_valid was checked, not the type
	var heal_nm: String = heal_name_v if heal_name_v is String else ""
	# Runtime re-title MUST route through title_text() — make_title only cases its constructor argument.
	_title.text = MenuStyle.title_text(PlayerText.heal_title(heal_nm))
	_refresh()
	_root.visible = true
	# Seed pad/keyboard focus on the Heal button (the OptionsMenu `_first_focus` / SaveLoadScreen / AtmScreen
	# idiom) — AFTER the card is visible, since grab_focus on a hidden Control does nothing. Heal is the natural
	# landing spot (the card's one transaction); a disabled Heal (fully mended / can't afford) still HOLDS focus,
	# so ui navigation starts there and one step reaches Close either way. Without a focus owner, navigation has
	# nowhere to start and every button on the card is pad-unreachable (the atm_screen must-not-recur rule).
	if is_instance_valid(_heal_btn):
		_heal_btn.grab_focus()
	opened.emit()

## Guard failed: we never opened, but a dialogue-hosted open (DialogueManager._suspend_for_menu) suspended the
## conversation on our `closed` one-shot BEFORE calling us. Emit `closed` so _resume_from_menu re-shows the box;
## on the standalone path (Healer.start_talk) nothing is listening, so it is harmless. Do NOT touch
## pause/mouse/_is_open here — none of that was mutated yet.
func _refuse_open() -> void:
	closed.emit()

func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_root.visible = false
	ModalMenu.restore_mouse(_prev_mouse_mode)
	_healer = null
	_player = null
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	# Close on the SAME Interact key that opens it (the ray consumes the OPENING press — see ray_cast.gd,
	# which skips interacting while we're open), or on Esc.
	if _is_open and (event.is_action_pressed(InputManager.action_pickup) or event.is_action_pressed(&"ui_cancel")):
		close()
		get_viewport().set_input_as_handled()

## Pay + heal, then refresh (the button disables once you're fully mended).
func _on_heal_pressed() -> void:
	if is_instance_valid(_healer) and is_instance_valid(_player):
		# Cue on the HEALER's verdict rather than on "the button was enabled": do_heal re-runs its own
		# cost + can_pay gate and then FAIL-CLOSES if charge() refuses, so an enabled button is not a promise of
		# a heal — which is exactly why the false branch needs its own voice instead of silence. The button is
		# muted in _bind_ui, so this pair is the press's only voice.
		var healed: bool = _healer.do_heal(_player)
		if healed:
			MenuStyle.play_commit()
		else:
			MenuStyle.play_denied()
		_refresh()

## Update the status line + the Heal button (cost, affordability, nothing-to-heal).
func _refresh() -> void:
	if not is_instance_valid(_healer) or not is_instance_valid(_player):
		return
	var cost: int = _healer.heal_cost(_player)
	if _rail_btn != null:
		_rail_btn.refresh()  # the rail may have been flipped at an ATM since this screen was last built
	# Paint the ALL-IN number (shop-screen parity): do_heal debits through player.charge(), so a rail-funded heal
	# carries the account's service charge and the sticker price alone would under-quote what actually leaves the
	# player. charge_total re-derives it from the SAME split charge() draws on. The gates below stay on the RAW
	# cost — can_pay folds the fee in itself, and the cost<=0 nothing-to-heal branch is the healer's own verdict.
	var shown_cost := _player.charge_total(float(cost))
	# The affordability wording rides the WRAPPING status line (not the button) so the button caption stays
	# short + fixed-width — the card is pinned to skin.dialog_width and a long "can't afford" caption would
	# otherwise be the one string long enough to clip on the button. We pass only the FACTS (limb damage on
	# its own line, affordability): PlayerText.heal_status selects one of four whole authored templates —
	# this screen never assembles line fragments (the TextFormat rule).
	var cant := cost > 0 and not _player.can_pay(float(cost))  # the SAME predicate Healer.do_heal gates on
	# spendable(), not `money` (the RespecScreen twin documents this same wart — respec_screen.gd _refresh): the
	# funds readout must count the account (and the armed credit line) that the do_heal gate can actually draw
	# on, or a banked player reads "Your zorkmids: 0" beside an enabled Heal button.
	var status_text := PlayerText.heal_status(int(round(_player.hp)), int(round(_player.max_hp)), _player.has_limb_damage(), _player.spendable(), cant)
	# Pad the status to a CONSTANT 4 lines (HP / limb / zorkmids / note is the worst case). make_dialog pins
	# the card's WIDTH only — its height shrink-wraps and the CenterContainer re-centers on every height
	# change, so when a Heal click cleared the limb line the whole card (title, text, buttons) visibly hopped
	# mid-transaction. Blank pad lines keep the height identical in every state (and across opens).
	while status_text.count("\n") < 3:
		status_text += "\n "
	_status.text = status_text
	_status.add_theme_color_override(&"font_color", MenuStyle.danger() if cant else MenuStyle.text_color())
	if cost <= 0:
		_heal_btn.text = PlayerText.HEAL_FULLY_HEALED
		_heal_btn.disabled = true
	else:
		_heal_btn.text = PlayerText.heal_button(shown_cost)  # the all-in quote; short caption in every state — can't-afford greys it out (below)
		_heal_btn.disabled = cant

# ---------------------------------------------------------------------------------------------------
# UI binding (the layout is AUTHORED in scenes/ui/heal_screen.tscn — this adopts it)
# ---------------------------------------------------------------------------------------------------

## Bind the authored chrome by %unique name, style it from the skin, and wire behaviour. What each piece
## still guarantees (the same contracts the old procedural build carried):
##  * the card is a FIXED-WIDTH centered dialog (style_dialog_card pins %Card to skin.dialog_width) — a
##    long healer name in the title or a big cost can never grow it or slide it off-centre; title/buttons
##    are capped (clip + "…"), the status line wraps.
##  * Heal + Close sit side by side EXPAND_FILL (authored in the scene): once fully healed the Heal button
##    DISABLES, so without Close a mouse-only player had no visible way out (Esc/Interact still close).
##  * CONTROLLER PARITY (the atm_screen must-not-recur rule): the authored Buttons carry NO `focus_mode = 0`
##    (Button's default FOCUS_ALL is what a pad navigates onto) and open_heal SEEDS focus on Heal once the
##    card is visible — with no focus owner, ui navigation has nowhere to start and every button is
##    unreachable. tests/test_heal_screen_scene.gd pins both halves.
##  * every string is set HERE from PlayerText — the scene ships with empty text properties.
func _bind_ui() -> void:
	_root = %Root
	MenuStyle.apply(_root)  # shared menu Theme (panel/buttons/tooltips/fonts) — reskin via resources/ui/menu_skin.tres
	MenuStyle.style_dim(%Dim)
	MenuStyle.style_dialog_card(%Card, 2)  # +2 separation: this few-row card wants a touch more air
	MenuStyle.style_button_row(%Buttons)

	_title = MenuStyle.cap_label(%Title)
	MenuStyle.style_title(_title)
	_title.text = MenuStyle.title_text(PlayerText.HEAL_SCREEN_TITLE)  # open_heal re-titles per healer

	_status = %Status
	_status.add_theme_font_size_override("font_size", MenuStyle.skin.header_size)

	# The DEBIT/CREDIT selector sits on its OWN row above Heal/Close, so the two-button row keeps its authored
	# EXPAND_FILL widths. Its signal drives _refresh because the armed rail changes what the till may draw on —
	# the affordability dim moves with the flip. (The all-in quoted cost itself is rail-invariant: the service fee
	# rides the cash shortfall whichever rail funds it — test_payment.gd pins that.)
	_rail_btn = %RailButton as PaymentRailButton
	MenuStyle.cap_button(_rail_btn)
	_rail_btn.rail_changed.connect(_refresh)

	_heal_btn = MenuStyle.cap_button(%HealButton)
	_heal_btn.pressed.connect(_on_heal_pressed)
	MenuStyle.set_button_sound(_heal_btn, &"")  # the commit is cued CONDITIONALLY in _on_heal_pressed; the generic click would double it

	var close_btn: Button = MenuStyle.cap_button(%CloseButton)
	close_btn.text = PlayerText.CLOSE
	close_btn.pressed.connect(close)  # close() no-ops when not open, so this stays externally safe
