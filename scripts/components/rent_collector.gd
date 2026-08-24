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
##
## ⭐SERVE NOTICE BEFORE YOU CHARGE. A recurring charge the player was never told about does not read as a debt
## clock — it reads as a bug ("what rent?"). This is not hypothetical: with the shipping clock (600 s/day, the
## game opening at noon) the first dawn lands 7m30s into a fresh run, and `player_starting_money` is 0, so an
## un-graced collector's very FIRST player-facing word about rent is a red "you failed to pay" toast against a
## wallet that was empty by construction. `notice_message` + `grace_days` exist to make the first word a NOTICE
## of the terms instead. Author both on any armed instance; a level that arms rent silently is an authoring bug
## (pinned for the shipping level by tests/test_shipping_level_rent.gd).

signal rent_paid(amount: float)         ## the full rent was collected this cycle
signal payment_missed(shortfall: float) ## the player couldn't cover it — `shortfall` went unpaid (wire eviction/rep here)
signal notice_served(amount: float)     ## the terms were announced, before any money moved (wire a quest flag / a landlord bark)

## Toast tints, kept together so the three rent beats read as one escalating voice: the notice is the neutral
## paperwork blue-white, a collection is the muted gold of money leaving, a miss is the warning red. Consts
## rather than @exports — the colour IS the severity here, and a designer retinting a miss to look benign
## would be undoing the point of the beat.
const NOTICE_COLOR := Color(0.78, 0.85, 0.95)
const PAID_COLOR := Color(0.85, 0.85, 0.6)
const MISSED_COLOR := Color(0.95, 0.6, 0.6)

@export_group("Rent")
## Zorkmids charged each cycle. 0 (default) = OFF — no rent is ever collected (and no notice is served: a
## disarmed collector is completely silent). Fractional is fine (Zorkmids).
@export var rent_amount: float = 0.0
## In-game days between charges (one WorldClock dawn = one day). Floored at 1 — rent at least daily when armed.
@export var period_days: int = 1
## Dawns of GRACE before the meter starts. The notice is served on the FIRST dawn; this many dawns (that one
## included) pass without a charge, then the period counter begins. 1 = "told at the first dawn, billed at the
## second" — the setting an armed collector wants, so the player is warned a full in-game day ahead.
## 0 (default) keeps the pre-notice behaviour: the first dawn charges immediately.
@export_range(0, 30, 1) var grace_days: int = 0
@export_group("Feedback")
## OPTIONAL toast served ONCE, at the first dawn, stating the terms BEFORE any money moves — the answer to
## "what rent?". Tokens: "{amount}" (the charge) and "{days}" (period_days). Blank = the terms are never
## announced, which is what makes a charge read as a bug. Author this on any armed collector.
@export var notice_message: String = ""
## OPTIONAL toast when rent is collected; "{amount}" in it is replaced with the formatted amount (a legacy
## "%s" is also accepted). Blank = silent.
@export var paid_message: String = ""
## OPTIONAL toast when the player can't cover the rent. Same token substitution as the others — "{amount}" is
## the rent that was OWED, plus "{shortfall}" (what went unpaid) and "{paid}" (what was actually taken).
## Blank = silent.
@export var missed_message: String = ""

var _days_since_charge: int = 0  ## dawns counted since the last charge; rent comes due at period_days
var _notice_served: bool = false ## the terms have been announced; one-shot, gates the notice toast + signal
var _dawns_seen: int = 0         ## dawns counted since this collector armed; the first grace_days of them are free

func _ready() -> void:
	WorldClock.phase_changed.connect(_on_phase_changed)

## A WorldClock phase boundary — count only the DAWN (-> DAY) crossings as "a new day".
func _on_phase_changed(new_phase: int) -> void:
	if new_phase != WorldClock.Phase.DAY or rent_amount <= 0.0:
		return  # a disarmed collector never even announces itself
	if _consume_dawn():
		collect()

## Book-keep ONE dawn and report whether the rent is due on it: serve the notice on the first dawn, let the
## `grace_days` window pass untaxed, then run the period counter. Kept separate from _on_phase_changed (and
## derived from the exports live, never seeded in _ready) so the whole notice -> grace -> charge schedule is
## unit-testable off-tree, the way _advance_day already is — the notice toast simply no-ops without a Player
## while `notice_served` still fires.
##
## ⭐Order matters: notice, then grace, then charge. With grace_days 0 the notice and the first charge land on
## the SAME dawn — legal (it is the pre-notice default, kept so an existing authored collector is unchanged),
## but the player reads the terms and the bill together, so prefer >= 1 on anything armed. Note also that
## WorldClock.advance_by() (the player Waiting) delivers several dawns IN ONE FRAME, so a long wait walks
## notice -> grace -> charge in a single call, exactly as if the days had been lived.
func _consume_dawn() -> bool:
	if not _notice_served:
		_notice_served = true
		_serve_notice()
	_dawns_seen += 1
	if _dawns_seen <= maxi(0, grace_days):
		return false  # still inside the grace window — the meter has not started
	return _advance_day()

## Announce the terms — the one-shot "here is what you owe and how often" toast, fired before a zorkmid has
## moved. Silent when the designer left notice_message blank (the signal still fires so a bark/quest flag can
## carry the beat instead).
func _serve_notice() -> void:
	var player := _player()
	if player != null and not notice_message.is_empty() and player.has_method(&"notify_toast"):
		player.notify_toast(_fmt_notice(), NOTICE_COLOR)
	notice_served.emit(rent_amount)

## Count one dawn; resets and returns true when `period_days` have elapsed (= rent is due). PURE/unit-testable.
func _advance_day() -> bool:
	_days_since_charge += 1
	if _days_since_charge >= maxi(1, period_days):
		_days_since_charge = 0
		return true
	return false

## Collect the rent NOW (also callable directly — a "pay up" dialogue option). No-op when disarmed (rent 0) or
## no player is found. Never pushes the wallet negative: pays min(rent, wallet) and emits payment_missed on a
## shortfall. Pass `player_node` to charge a specific wallet; omit it to find the player via the Player group (Groups.PLAYER).
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
			player.notify_toast(_fmt_missed(pay), MISSED_COLOR)
		payment_missed.emit(rent_amount - pay)
	else:
		if not paid_message.is_empty() and player.has_method(&"notify_toast"):
			player.notify_toast(_fmt_paid(pay), PAID_COLOR)
		rent_paid.emit(pay)

## The paid toast text — substitutes the collected amount into paid_message's "{amount}" token (the pre-token
## "%s" is still honoured for old authored scenes).
func _fmt_paid(amount: float) -> String:
	return _fmt(paid_message, {"{amount}": Zorkmids.money_text(amount)}, amount)

## The NOTICE text — the terms, before any money moves. "{amount}" is the charge, "{days}" its period, floored
## exactly the way _advance_day floors it so the line can never promise a cadence the counter won't keep.
func _fmt_notice() -> String:
	return _fmt(notice_message, {
		"{amount}": Zorkmids.money_text(rent_amount),
		"{days}": str(maxi(1, period_days)),
	}, rent_amount)

## The MISSED text. `paid` is what was actually taken, so "{shortfall}" is the remainder — the number the old
## "the shortfall has been noted" line could never show, because missed_message used to reach notify_toast RAW
## (a designer's "{shortfall}" rendered literally on screen). "{amount}" is the rent that was OWED, not the
## part collected, so the player learns both the size of the obligation and the size of the miss.
func _fmt_missed(paid: float) -> String:
	return _fmt(missed_message, {
		"{amount}": Zorkmids.money_text(rent_amount),
		"{shortfall}": Zorkmids.money_text(rent_amount - paid),
		"{paid}": Zorkmids.money_text(paid),
	}, rent_amount)

## Shared token substitution for every authored line.
##
## Money lands as the WHOLE Zorkmids.money_text phrase ("20 zm"), never the bare Zorkmids.fmt number: a rent
## toast is player prose about money, and the repo rule is that money reaches prose as one phrase rather than a
## digit the designer has to remember to append a unit to. (The pre-notice component used fmt(), which is why
## the shipping line rendered as "Rent collected — 20." — a charge with no currency on it, in a game whose
## whole loop is the currency.) Author "{amount}", not "{amount} zm".
##
## Token-REPLACE, never the `%` format operator: a literal percent anywhere in the line (e.g. "10% off") would
## raise an "unsupported format character" engine error on `%`. `legacy_amount` backs the pre-token "%s"
## placeholder that old authored scenes still carry.
func _fmt(template: String, tokens: Dictionary, legacy_amount: float) -> String:
	var out := template
	for token in tokens:
		out = out.replace(String(token), String(tokens[token]))
	return out.replace("%s", Zorkmids.money_text(legacy_amount))

func _player() -> Node:
	return get_tree().get_first_node_in_group(Groups.PLAYER) if is_inside_tree() else null
