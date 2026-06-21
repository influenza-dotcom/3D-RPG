class_name RentCollector
extends Node

## Drop-in RECURRING MONEY SINK — a landlord on a timer. Every `period_days` in-game days (counted as WorldClock
## dawns) it charges the player `rent_amount` zorkmids. OFF by default (rent_amount 0 -> inert): dropping one in
## changes nothing until a designer sets the rent. Put it under a landlord NPC, a rented safehouse, or the level
## root as a book-keeper. The player can never go into DEBT here — if they can't cover the rent it takes whatever
## they have (down to zero) and emits `payment_missed` with the shortfall, so a designer can wire a consequence
## (an eviction TriggerVolume, a reputation hit, a threatening toast). Pairs with WorldClock (rank 28a); a frozen
## clock (day_length_seconds 0) never advances, so rent never comes due. Mirrors the Healer / RespecStation
## per-instance @export idiom — every knob is on this node, no code.

signal rent_paid(amount: float)         ## the full rent was collected this cycle
signal payment_missed(shortfall: float) ## the player couldn't cover it — `shortfall` went unpaid (wire eviction/rep here)

@export_group("Rent")
## Zorkmids charged each cycle. 0 (default) = OFF — no rent is ever collected. Fractional is fine (Zorkmids).
@export var rent_amount: float = 0.0
## In-game days between charges (one WorldClock dawn = one day). Floored at 1 — rent at least daily when armed.
@export var period_days: int = 1
@export_group("Feedback")
## OPTIONAL toast when rent is collected; a "%s" in it is replaced with the amount. Blank = silent.
@export var paid_message: String = ""
## OPTIONAL toast when the player can't cover the rent. Blank = silent.
@export var missed_message: String = ""

var _days_since_charge: int = 0  ## dawns counted since the last charge; rent comes due at period_days

func _ready() -> void:
	WorldClock.phase_changed.connect(_on_phase_changed)

## A WorldClock phase boundary — count only the DAWN (-> DAY) crossings as "a new day". When period_days of
## them have elapsed, the rent comes due.
func _on_phase_changed(new_phase: int) -> void:
	if new_phase == WorldClock.Phase.DAY and _advance_day():
		collect()

## Count one dawn; resets and returns true when `period_days` have elapsed (= rent is due). PURE/unit-testable.
func _advance_day() -> bool:
	_days_since_charge += 1
	if _days_since_charge >= maxi(1, period_days):
		_days_since_charge = 0
		return true
	return false

## Collect the rent NOW (also callable directly — a "pay up" dialogue option). No-op when disarmed (rent 0) or
## no player is found. Never pushes the wallet negative: pays min(rent, wallet) and emits payment_missed on a
## shortfall. Pass `player_node` to charge a specific wallet; omit it to find the player via the &"player" group.
func collect(player_node: Node = null) -> void:
	if rent_amount <= 0.0:
		return
	var player := player_node if player_node != null else _player()
	if player == null or not player.has_method(&"add_money"):
		return
	var money_v: Variant = player.get(&"money")
	var wallet: float = maxf(0.0, float(money_v)) if money_v != null else 0.0
	var pay := minf(rent_amount, wallet)
	if pay > 0.0:
		player.add_money(-pay)  # the ONE wallet seam -> HUD readout + the floating -N indicator
	if pay < rent_amount:
		if not missed_message.is_empty() and player.has_method(&"notify_toast"):
			player.notify_toast(missed_message, Color(0.95, 0.6, 0.6))
		payment_missed.emit(rent_amount - pay)
	else:
		if not paid_message.is_empty() and player.has_method(&"notify_toast"):
			player.notify_toast(_fmt_paid(pay), Color(0.85, 0.85, 0.6))
		rent_paid.emit(pay)

## The paid toast text — substitutes the amount into paid_message when it carries a "%" placeholder, else as-is.
func _fmt_paid(amount: float) -> String:
	return paid_message % Zorkmids.fmt(amount) if paid_message.contains("%") else paid_message

func _player() -> Node:
	return get_tree().get_first_node_in_group(&"player") if is_inside_tree() else null
