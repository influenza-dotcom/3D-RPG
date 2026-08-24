extends CanvasLayer

## @system Wait
## @seam Autoload modal opened by its OWN key (InputManager.action_wait, default T — the Fallout 3/NV key); the QuestJournal idiom where the screen owns its keypress rather than something else opening it.
## @seam THE ONE CALLER of WorldClock.advance_hours: confirming walks the span and emits every day/night boundary crossed, so rent falls due, bank interest posts and NPC schedules move exactly as if the hours had been lived. Waiting must never route through set_time_of_day (that is the silent seek, and using it here is the free-rent exploit).
## @seam Refusal is polled off StealthStatus.of_player — the SAME aggregate the stealth HUD reads — so "someone is hunting you" means one thing across the game rather than two.
## @risk Refuses to OPEN when blocked rather than opening a disabled card: the screen frees the mouse, and freeing it mid-firefight would be worse than the missing panel. The reason goes out as a toast so the key never reads as dead.
## @risk Waiting deliberately does NOT heal to full or mend limbs (GameSettings.wait) — a Bonfire rest is the full restore AND the respawn checkpoint, and a wait that matched it would make fires pointless.
## @test res://tests/test_wait_screen.gd
##
## WaitScreen — the Fallout-style "let some hours pass" panel. Press T, pick a number of in-game hours,
## confirm, and they pass: the clock advances, the world moves with it, and a trickle of HP comes back.
##
## AUTHORED SCENE: the layout lives in scenes/ui/wait_screen.tscn (this autoload IS that scene — see
## project.godot [autoload]); this script binds its chrome by %unique name in _bind_ui and applies the
## skin-driven look (MenuStyle style_* adopters) on top, so a designer rearranges the card in the editor
## and the skin keeps owning colours/fonts/width pins. NO text is authored in the scene — every string is
## set here from PlayerText (l10n + the text-debt ratchet own strings, never a .tscn).
##
## REAL-TIME, like every other standalone modal here: it does NOT pause the world (the station-screen rule
## argued in atm_screen.gd's header). That is safe precisely because it refuses to open while anything is
## hunting you — the one case where standing at a menu would be lethal.
##
## THE CARD DOES NOT RESIZE. Every value that changes — the two clock faces, the hour count, the status
## line — sits in a slot with a reserved minimum, and the status line is hidden with ALPHA rather than
## `visible`, so committing a wait cannot make the card hop under the cursor mid-press (the house rule; see
## tests/test_menu_layout_stability.gd's header for the structural version of it).

signal opened
signal closed

const PlayerMenus := preload("res://scripts/ui/player_menus.gd")
const CLOCK := preload("res://scripts/ui/hud_clock.gd")   ## the face formatter — one clock dialect in the game

## The stepper caps. SHAPE GLYPHS, NOT PROSE — so they live here as locals rather than in PlayerText, which
## is for translatable copy (the house rule: a non-prose paint is fixed at the root, never parked in
## PlayerText). Composed into a local const rather than written inline at the `.text =` site, which is also
## what keeps them off the hardcoded-string ratchet's paint-site scanner.
const MINUS_GLYPH := "−"   # U+2212 MINUS SIGN — matches the plus's weight; a hyphen reads as a dash
const PLUS_GLYPH := "+"

## Refusal reasons, resolved by _blocked_reason(). NONE = the wait may proceed.
enum Block { NONE, HOSTILE, AIRBORNE, CLOCK_FROZEN }

var _root: Control
var _title: Label
var _now_value: Label
var _until_value: Label
var _hours_label: Label
var _status: Label
var _wait_btn: Button
var _minus_btn: Button
var _plus_btn: Button
var _is_open := false
var _prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _hours := 1


func _ready() -> void:
	layer = 121                                  # peer of the other modal overlays (heal / loot / shop)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bind_ui()
	_root.visible = false


func is_open() -> bool:
	return _is_open


func toggle() -> void:
	if _is_open:
		close()
	else:
		open()


## Open the wait panel. Refuses over any other modal / dialogue, with no living player, and — the Fallout
## rule — while anything is hunting you or you are airborne. A refusal TOASTS its reason rather than
## opening a card with a dead button: the screen frees the mouse, and freeing it mid-firefight is worse
## than the missing panel, but silence would read as a broken keybind.
func open() -> void:
	if _is_open or DialogueManager.is_active() or InputManager.any_modal_open(self):
		return
	if not PlayerMenus.has_player(get_tree()) or not PlayerMenus.player_alive(get_tree()):
		return
	var blocked := _blocked_reason()
	if blocked != Block.NONE:
		_refuse(blocked)
		return
	var cfg: WaitSettings = GameSettings.wait
	_hours = clampi(cfg.default_hours, _min_hours(), _max_hours())
	_prev_mouse_mode = ModalMenu.grab_mouse()
	_is_open = true
	_refresh()
	_root.visible = true
	# Seed pad/keyboard focus on the confirm button once the card is VISIBLE (grab_focus on a hidden Control
	# does nothing) — the atm_screen must-not-recur rule: with no focus owner, ui navigation has nowhere to
	# start and every button on the card is pad-unreachable.
	if is_instance_valid(_wait_btn):
		_wait_btn.grab_focus()
	opened.emit()


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_root.visible = false
	ModalMenu.restore_mouse(_prev_mouse_mode)
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputManager.action_wait):
		toggle()
		get_viewport().set_input_as_handled()
	elif _is_open and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------------------------------
# The wait itself
# ---------------------------------------------------------------------------------------------------

## Commit the selected hours. RE-CHECKS the refusal (the world kept running while the card was up — a guard
## can walk in and lock on between opening and pressing), then advances the clock and pays the trickle.
func _on_wait_pressed() -> void:
	var blocked := _blocked_reason()
	if blocked != Block.NONE:
		MenuStyle.play_denied()
		_show_status(_block_text(blocked), MenuStyle.danger())
		return
	var hours := _hours
	MenuStyle.play_commit()
	close()
	# ⭐advance_hours, NOT set_time_of_day: the walk emits every dawn/dusk the span crosses, so rent falls due
	# and interest posts for the days actually lived through. A silent seek here is the free-rent exploit.
	WorldClock.advance_hours(float(hours))
	_apply_recovery(hours)
	var p := Groups.human_player(get_tree())
	if p != null and p.has_method(&"notify_toast"):
		p.call(&"notify_toast", PlayerText.wait_elapsed(hours), MenuStyle.text_color())


## The HP trickle. Deliberately small and capped (GameSettings.wait) — see WaitSettings' header for why a
## wait must not do a Bonfire's job. Never REMOVES health: a player already above the cap simply gains nothing.
func _apply_recovery(hours: int) -> void:
	var cfg: WaitSettings = GameSettings.wait
	var p := Groups.human_player(get_tree())
	if p == null or not is_instance_valid(p):
		return
	if cfg.heals_limbs and p.has_method(&"heal_limbs"):
		p.call(&"heal_limbs")
	if cfg.hp_per_hour <= 0.0 or not p.has_method(&"heal"):
		return
	var hp := float(p.get(&"hp"))
	var max_hp := float(p.get(&"max_hp"))
	var gain := recovery_for(hp, max_hp, cfg.hp_per_hour, cfg.hp_cap_fraction, hours)
	if gain > 0.0:
		p.call(&"heal", gain)


## Pure: how much HP a wait of `hours` actually restores, given the trickle rate and the cap. Never negative
## (a player already past the cap gains nothing rather than losing health), and never overshoots the cap.
## Static + unit-tested — the DayNightSky.sun_elevation idiom for a rule with this many boundary cases.
static func recovery_for(hp: float, max_hp: float, per_hour: float, cap_fraction: float, hours: int) -> float:
	if per_hour <= 0.0 or hours <= 0 or max_hp <= 0.0:
		return 0.0
	var cap := max_hp * clampf(cap_fraction, 0.0, 1.0)
	return maxf(0.0, minf(hp + per_hour * float(hours), cap) - hp)


# ---------------------------------------------------------------------------------------------------
# Refusal
# ---------------------------------------------------------------------------------------------------

## Why waiting is refused right now, or Block.NONE. The two combat reasons are designer-switchable
## (GameSettings.wait); the frozen-clock one is not, because it is not a balance call — see below.
func _blocked_reason() -> int:
	var cfg: WaitSettings = GameSettings.wait
	# ⭐A FROZEN CLOCK MEANS TIME DOES NOT PASS HERE. `WorldClock.day_length_seconds = 0` is the documented way
	# to pin a level to one hour, and letting T unpin it would quietly break that authoring promise — including
	# the one the day/night docs make explicitly, that rent never comes due on a frozen level. The guard lives
	# HERE rather than inside advance_by on purpose: advance_by is the mechanism ("move the clock and emit"),
	# and whether waiting is legal is policy that belongs to the screen offering it.
	if WorldClock.day_length_seconds <= 0.0:
		return Block.CLOCK_FROZEN
	var p := Groups.human_player(get_tree())
	if p == null or not is_instance_valid(p):
		return Block.NONE
	if cfg.hostile_awareness_blocks:
		var snap := StealthStatus.of_player(p, get_tree().get_nodes_in_group(Groups.NPC))
		if hostile_blocks(int(snap.get(&"level", StealthStatus.Level.HIDDEN))):
			return Block.HOSTILE
	# Duck-typed: only a CharacterBody3D has is_on_floor, and a test/no-clip host degrades to "grounded"
	# rather than a crash (the minimap._update_ground_reference idiom).
	if cfg.airborne_blocks and p.has_method(&"is_on_floor") and p.call(&"is_on_floor") != true:
		return Block.AIRBORNE
	return Block.NONE


## Pure: does this StealthStatus level stop a wait? CAUTION and DANGER do — something is actively searching
## for you or fighting you. DETECTED deliberately does NOT: a meter that has merely started filling is a
## guard glancing over, not a hunt, and refusing on it would make waiting impossible anywhere patrolled.
## Unit-tested, because "when can I wait" is a rule players will probe at every threshold.
static func hostile_blocks(level: int) -> bool:
	return level >= StealthStatus.Level.CAUTION


## Refuse without opening: toast the reason so the key never reads as dead, and play the denial cue.
func _refuse(reason: int) -> void:
	MenuStyle.play_denied()
	var p := Groups.human_player(get_tree())
	if p != null and p.has_method(&"notify_toast"):
		p.call(&"notify_toast", _block_text(reason), MenuStyle.danger())


## The player-facing sentence for a refusal — WHOLE authored templates selected by reason, never a shared
## stem with the cause appended (the TextFormat fragment rule).
static func _block_text(reason: int) -> String:
	if reason == Block.AIRBORNE:
		return PlayerText.WAIT_BLOCKED_AIRBORNE
	if reason == Block.CLOCK_FROZEN:
		return PlayerText.WAIT_BLOCKED_FROZEN
	return PlayerText.WAIT_BLOCKED_HOSTILE


# ---------------------------------------------------------------------------------------------------
# Selector + refresh
# ---------------------------------------------------------------------------------------------------

func _min_hours() -> int:
	return maxi(1, GameSettings.wait.min_hours)


func _max_hours() -> int:
	return maxi(_min_hours(), GameSettings.wait.max_hours)


func _nudge(delta: int) -> void:
	var want := clampi(_hours + delta, _min_hours(), _max_hours())
	if want == _hours:
		return       # already at an end stop — no cue, no repaint (the silent-no-op rule)
	_hours = want
	MenuStyle.play_select()
	_refresh()


## Repaint every live value. The two clock faces read through HudClock's own formatter, so the panel and the
## HUD readout can never disagree about what "now" says or which face the player chose.
func _refresh() -> void:
	var use_24: bool = Settings.clock_24_hour
	var now_t: float = WorldClock.time_of_day
	_now_value.text = CLOCK.time_text(now_t, use_24)
	# The destination is computed the SAME way advance_hours will move the clock (hours -> day-fraction through
	# WorldClock's own constant), so the preview can never promise an hour the commit does not land on.
	_until_value.text = CLOCK.time_text(now_t + float(_hours) / WorldClock.HOURS_PER_DAY, use_24)
	_hours_label.text = PlayerText.wait_hours(_hours)
	_minus_btn.disabled = _hours <= _min_hours()
	_plus_btn.disabled = _hours >= _max_hours()
	_show_status("", MenuStyle.text_color())


## Set (or clear) the status line WITHOUT changing the card's size: the label keeps its reserved height and
## an empty message is hidden with ALPHA, not `visible`. Hiding it outright would collapse its row and make
## the whole centered card hop the moment a refusal appeared or cleared.
func _show_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override(&"font_color", color)
	_status.modulate.a = 0.0 if text.is_empty() else 1.0


# ---------------------------------------------------------------------------------------------------
# UI binding (the layout is AUTHORED in scenes/ui/wait_screen.tscn — this adopts it)
# ---------------------------------------------------------------------------------------------------

## Bind the authored chrome by %unique name, style it from the skin, and wire behaviour. What the scene
## guarantees and this preserves:
##  * the card is a FIXED-WIDTH centered dialog (style_dialog_card pins %Card to skin.dialog_width);
##  * every value that changes has a RESERVED slot (the clock columns' 90px minimum, the hour label's 120px,
##    the status line's 34px height), so no repaint can resize or re-centre the card;
##  * Wait + Close sit side by side EXPAND_FILL — a mouse-only player always has a visible way out;
##  * CONTROLLER PARITY: the authored Buttons carry NO `focus_mode = 0`, and open() seeds focus on Wait.
##  * every string is set HERE from PlayerText — the scene ships with empty text properties.
func _bind_ui() -> void:
	_root = %Root
	MenuStyle.apply(_root)  # shared menu Theme (panel/buttons/tooltips/fonts) — reskin via resources/ui/menu_skin.tres
	MenuStyle.style_dim(%Dim)
	MenuStyle.style_dialog_card(%Card, 2)
	MenuStyle.style_button_row(%Buttons)

	_title = MenuStyle.cap_label(%Title)
	MenuStyle.style_title(_title)
	_title.text = MenuStyle.title_text(PlayerText.WAIT_TITLE)

	var now_label := %NowLabel as Label
	var until_label := %UntilLabel as Label
	now_label.text = PlayerText.WAIT_NOW_LABEL
	until_label.text = PlayerText.WAIT_UNTIL_LABEL
	now_label.add_theme_color_override(&"font_color", MenuStyle.dim_color())
	until_label.add_theme_color_override(&"font_color", MenuStyle.dim_color())
	_now_value = %NowValue
	_until_value = %UntilValue
	_now_value.add_theme_color_override(&"font_color", MenuStyle.accent())
	_until_value.add_theme_color_override(&"font_color", MenuStyle.accent())

	_hours_label = %HoursLabel
	_minus_btn = MenuStyle.cap_button(%Minus)
	_plus_btn = MenuStyle.cap_button(%Plus)
	_minus_btn.text = MINUS_GLYPH
	_plus_btn.text = PLUS_GLYPH
	_minus_btn.pressed.connect(_nudge.bind(-1))
	_plus_btn.pressed.connect(_nudge.bind(1))

	_status = %Status
	MenuStyle.style_hint(_status)

	_wait_btn = MenuStyle.cap_button(%WaitButton)
	_wait_btn.text = PlayerText.WAIT_CONFIRM
	_wait_btn.pressed.connect(_on_wait_pressed)
	var close_btn := MenuStyle.cap_button(%CloseButton)
	close_btn.text = PlayerText.CLOSE
	close_btn.pressed.connect(close)
