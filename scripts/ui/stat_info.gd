class_name StatInfo
extends RefCounted

## Human-readable breakdowns for the six CharacterStats — fed into menu tooltips so HOVERING a stat shows
## what it does and its effect at the current value. Pure formatter; reads the live sheet for the current
## numbers. The wording mirrors the per-stat doc comments on CharacterStats so the two never drift.

const TITLES := {
	&"strength": "Strength", &"persuasion": "Persuasion", &"gunplay": "Gunplay",
	&"endurance": "Endurance", &"streetwise": "Streetwise", &"agility": "Agility",
}
const BLURB := {
	&"strength": "Carry capacity — haul more before the over-encumbered slog kicks in.",
	&"persuasion": "Haggling — buy cheaper, sell dearer, and pass dialogue checks.",
	&"gunplay": "Steady hands — tightens the gun's idle sway for tighter shots.",
	&"endurance": "Vitality — raises your max HP (applied when you spawn).",
	&"streetwise": "Standing — good deeds land bigger, slip-ups sting less.",
	&"agility": "Fleetness — moves you faster on foot.",
}

## A multi-line tooltip for `stat` given the character's live `sheet` (null = treated as baseline).
static func tooltip(stat: StringName, sheet: CharacterStats) -> String:
	var s: CharacterStats = sheet if sheet != null else CharacterStats.new()
	var v: int = s.get_stat(stat)
	var title: String = TITLES.get(stat, str(stat))
	var blurb: String = BLURB.get(stat, "")
	return "%s  ·  %d\n%s\nNow: %s" % [title, v, blurb, _effect(stat, s)]

## The single-line "current effect" string for `stat` at the sheet's live value. Sign-correct across the whole
## range: a NEGATIVE stat reads as a real penalty (a minus, not a stray "+-"), since character creation lets a
## stat go below baseline and CharacterStats inverts every derived effect there.
static func _effect(stat: StringName, s: CharacterStats) -> String:
	match stat:
		&"strength":
			return "%s carry capacity" % _signed_num(s.carry_bonus())
		&"endurance":
			return "%s max HP" % _signed_num(s.max_hp_bonus())
		&"persuasion":
			# + on each = in your favour (cheaper buys / dearer sales); both flip past baseline.
			return "buys %s, sales %s" % [
				_signed_pct(roundi((1.0 - s.buy_price_mult()) * 100.0)),
				_signed_pct(roundi((s.sell_price_mult() - 1.0) * 100.0))]
		&"gunplay":
			return "%s aim steadiness" % _signed_pct(roundi((1.0 - s.sway_mult()) * 100.0))
		&"streetwise":
			# gains: + = bigger (good). penalties: the CHANGE in loss size, so - = losses shrank (good).
			return "rep gains %s, penalties %s" % [
				_signed_pct(roundi((s.rep_gain_mult() - 1.0) * 100.0)),
				_signed_pct(roundi((s.rep_loss_mult() - 1.0) * 100.0))]
		&"agility":
			return "%s move speed" % _signed_pct(roundi((s.move_speed_mult() - 1.0) * 100.0))
	return ""

## Trim a float to a bare/half readout ("4" / "4.5"), matching the Zorkmids.fmt feel. A negative carries its own minus.
static func _num(x: float) -> String:
	if is_equal_approx(x, roundf(x)):
		return str(int(roundf(x)))
	return ("%.1f" % x).rstrip("0").rstrip(".")

## A SIGNED bare/half number: "+4", "-4", "+4.5", and "0" at baseline (never "+0" / "-0").
static func _signed_num(x: float) -> String:
	if is_zero_approx(x):
		return "0"
	return ("+" + _num(x)) if x > 0.0 else _num(x)  # a negative already carries its minus

## A SIGNED percentage: "+8%", "-8%", and "0%" at baseline.
static func _signed_pct(p: int) -> String:
	if p == 0:
		return "0%"
	return ("+%d%%" % p) if p > 0 else ("%d%%" % p)  # a negative already carries its minus
